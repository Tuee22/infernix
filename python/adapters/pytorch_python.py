from __future__ import annotations

import inspect
import io
import zipfile
from typing import Any

from adapters.common import (
    AdapterContext,
    ArtifactResult,
    download_demo_object,
    materialize_temp_input,
    run_artifact_adapter,
    run_setup_from_argv,
)
from adapters.model_cache import get_model_path


def _preferred_torch_device(torch_module: Any) -> str:
    mps_backend = getattr(getattr(torch_module, "backends", object()), "mps", None)
    if mps_backend is not None and mps_backend.is_available():
        return "mps"
    cuda_available = getattr(
        getattr(torch_module, "cuda", object()), "is_available", None
    )
    if cuda_available is not None and cuda_available():
        return "cuda"
    return "cpu"


def _install_mt3_transformers_checkpoint_compat() -> None:
    try:
        import torch
        from torch.utils.checkpoint import checkpoint as torch_checkpoint
        from transformers.models.t5 import modeling_t5
    except ImportError as exc:
        raise RuntimeError(
            "torch/transformers are not installed in this engine venv; "
            "install the prebuilt host wheels for the MT3 transcription engine."
        ) from exc
    if not hasattr(modeling_t5, "checkpoint"):
        modeling_t5.checkpoint = torch_checkpoint
    _install_mt3_transformers_cache_position_compat(modeling_t5, torch)


def _install_mt3_transformers_cache_position_compat(
    modeling_t5: Any, torch_module: Any
) -> None:
    t5_block = modeling_t5.T5Block
    original_forward = t5_block.forward
    if getattr(original_forward, "_infernix_mt3_cache_position_compat", False):
        return

    forward_parameters = set(inspect.signature(original_forward).parameters)
    rename_past_key_values = (
        "past_key_value" in forward_parameters
        and "past_key_values" not in forward_parameters
    )

    def forward_with_cache_position(
        self: Any, hidden_states: Any, *args: Any, **kwargs: Any
    ) -> Any:
        # mr_mt3's vendored T5Stack calls the upstream transformers T5Block
        # with the plural `past_key_values` keyword, but transformers <4.50
        # names the parameter `past_key_value` (singular). Translate the
        # keyword so the real forward runs; this is an argument-name
        # adaptation, not a substitute for real model output.
        if rename_past_key_values and "past_key_values" in kwargs:
            kwargs.setdefault("past_key_value", kwargs.pop("past_key_values"))

        def cache_position() -> Any:
            return torch_module.arange(
                hidden_states.shape[1], device=hidden_states.device
            )

        if len(args) >= 12:
            positional_args = list(args)
            if positional_args[11] is None:
                positional_args[11] = cache_position()
            return original_forward(self, hidden_states, *positional_args, **kwargs)
        if kwargs.get("cache_position") is None:
            kwargs["cache_position"] = cache_position()
        return original_forward(self, hidden_states, *args, **kwargs)

    forward_with_cache_position._infernix_mt3_cache_position_compat = True  # type: ignore[attr-defined]
    t5_block.forward = forward_with_cache_position


def _disable_mt3_generation_cache(mt3_adapter: Any) -> None:
    inner_model = getattr(mt3_adapter, "_model", None)
    if inner_model is None:
        return
    if getattr(inner_model, "_infernix_no_cache_generate", False):
        return
    config = getattr(inner_model, "config", None)
    if config is not None and hasattr(config, "use_cache"):
        config.use_cache = False
    generation_config = getattr(inner_model, "generation_config", None)
    if generation_config is not None and hasattr(generation_config, "use_cache"):
        generation_config.use_cache = False
    original_generate = inner_model.generate

    def generate_without_cache(*args: Any, **kwargs: Any) -> Any:
        kwargs.setdefault("use_cache", False)
        return original_generate(*args, **kwargs)

    inner_model.generate = generate_without_cache
    inner_model._infernix_no_cache_generate = True


def transform(context: AdapterContext) -> ArtifactResult:
    # Phase 4 Sprint 4.7/4.15/4.22: real PyTorch artifact families dispatched
    # by model id — Bark audio generation (text prompt -> WAV), Demucs/
    # Open-Unmix source separation (audio input -> stem ZIP), and ByteDance
    # piano transcription (audio input -> MIDI). Frameworks are lazy-imported
    # so the quality gate stays machine-independent.
    model_id = context.model_id
    if "bark" in model_id:
        return _generate_bark(context)
    if "demucs" in model_id:
        return _separate_sources(context)
    if "unmix" in model_id:
        return _separate_open_unmix(context)
    if model_id in {"music-mt3-infer", "music-mr-mt3"}:
        return _transcribe_mt3(context)
    if "omnizart" in model_id:
        return _transcribe_piano(context)
    if "mt3" in model_id:
        raise RuntimeError(f"no real mt3 variant is wired for model id {model_id!r}")
    raise RuntimeError(f"no pytorch artifact family is wired for model id {model_id!r}")


def _generate_bark(context: AdapterContext) -> ArtifactResult:
    weights_dir = get_model_path(context.model_id)
    try:
        import scipy.io.wavfile
        import torch
        from transformers import AutoProcessor, BarkModel
    except ImportError as exc:
        raise RuntimeError(
            "transformers/scipy are not installed in this engine venv; "
            "install the prebuilt host wheels for the Bark audio engine."
        ) from exc
    # Wave I real-output fix: run Bark on the GPU/MPS accelerator instead of
    # the default CPU placement so generation completes within the routed
    # result-publish budget. Move the model and every tensor input to the
    # device, leaving non-tensor processor entries (e.g. voice presets) intact.
    device = _preferred_torch_device(torch)
    processor = AutoProcessor.from_pretrained(str(weights_dir), local_files_only=True)
    model = BarkModel.from_pretrained(str(weights_dir), local_files_only=True)
    model = model.to(device)
    inputs = processor(context.input_text)
    inputs = {
        key: (value.to(device) if hasattr(value, "to") else value)
        for key, value in inputs.items()
    }
    audio = model.generate(**inputs)
    sample_rate = int(model.generation_config.sample_rate)
    buffer = io.BytesIO()
    scipy.io.wavfile.write(buffer, sample_rate, audio.cpu().numpy().squeeze())
    return ArtifactResult(
        data=buffer.getvalue(), content_type="audio/wav", suffix=".wav"
    )


def _separate_sources(context: AdapterContext) -> ArtifactResult:
    try:
        import soundfile
        import torch
        from demucs.apply import apply_model
        from demucs.states import load_model
    except ImportError as exc:
        raise RuntimeError(
            "torch/soundfile/demucs are not installed in this engine venv; "
            "install the prebuilt host wheels for the source-separation engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    checkpoint_path = weights_dir / "payload"
    device = _preferred_torch_device(torch)
    input_audio = download_demo_object(context.input_object_ref)
    audio_array, sample_rate = soundfile.read(
        io.BytesIO(input_audio),
        dtype="float32",
        always_2d=True,
    )
    waveform = torch.as_tensor(audio_array.T.copy())
    try:
        # The Demucs checkpoint is the trusted, content-addressed first-party
        # weight staged from `dl.fbaipublicfiles.com` into the model cache.
        # torch>=2.6 defaults `weights_only=True`, which rejects the demucs
        # model classes pickled in the package, so the trusted package dict is
        # loaded explicitly and handed to demucs `load_model` (which accepts a
        # dict and reconstructs the model from its klass/args/kwargs/state).
        package = torch.load(
            str(checkpoint_path), map_location="cpu", weights_only=False
        )
        model = load_model(package)
    except Exception as exc:
        raise RuntimeError(
            f"unable to load source-separation model from {checkpoint_path}"
        ) from exc
    model.eval()
    # Wave I real-output fix: run separation on the GPU/MPS accelerator; demucs
    # `apply_model` moves the model and per-chunk tensors to the named device.
    stems = apply_model(model, waveform.unsqueeze(0), device=device)[0]
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as bundle:
        for index, source_name in enumerate(model.sources):
            stem_buffer = io.BytesIO()
            stem_audio = stems[index].detach().cpu().transpose(0, 1).numpy()
            soundfile.write(stem_buffer, stem_audio, sample_rate, format="WAV")
            bundle.writestr(f"{source_name}.wav", stem_buffer.getvalue())
    return ArtifactResult(
        data=archive.getvalue(), content_type="application/zip", suffix=".zip"
    )


def _separate_open_unmix(context: AdapterContext) -> ArtifactResult:
    try:
        import openunmix
        import soundfile
        import torch
    except ImportError as exc:
        raise RuntimeError(
            "torch/soundfile/openunmix are not installed in this engine venv; "
            "install the prebuilt host wheels for the source-separation engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    device = _preferred_torch_device(torch)
    input_audio = download_demo_object(context.input_object_ref)
    audio_array, sample_rate = soundfile.read(
        io.BytesIO(input_audio),
        dtype="float32",
        always_2d=True,
    )
    # Open-Unmix consumes (batch, channels, samples) at 44.1 kHz stereo.
    waveform = torch.as_tensor(audio_array.T.copy()).unsqueeze(0)
    try:
        # Build the umxhq architecture and load the real per-target state dicts
        # staged from the first-party Zenodo weights. `strict=False` mirrors
        # `openunmix.umxhq_spec`: the checkpoints carry extra recomputed STFT
        # window / sample-rate buffers the rebuilt model does not expose.
        separator = openunmix.umxhq(pretrained=False, device=device)
        for target, target_model in separator.target_models.items():
            state = torch.load(
                str(weights_dir / f"{target}.pth"),
                map_location="cpu",
                weights_only=False,
            )
            target_model.load_state_dict(state, strict=False)
            target_model.eval()
        separator.eval()
    except Exception as exc:
        raise RuntimeError(
            f"unable to load Open-Unmix model from {weights_dir}"
        ) from exc
    targets = list(separator.target_models.keys())
    with torch.no_grad():
        estimates = separator(waveform.to(device))[0]
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as bundle:
        for index, source_name in enumerate(targets):
            stem_buffer = io.BytesIO()
            stem_audio = estimates[index].detach().cpu().transpose(0, 1).numpy()
            soundfile.write(stem_buffer, stem_audio, sample_rate, format="WAV")
            bundle.writestr(f"{source_name}.wav", stem_buffer.getvalue())
    return ArtifactResult(
        data=archive.getvalue(), content_type="application/zip", suffix=".zip"
    )


def _transcribe_mt3(context: AdapterContext) -> ArtifactResult:
    # mt3-infer currently supports CUDA/CPU auto-placement, not Apple MPS. The
    # Apple catalog therefore declares these rows as PyTorch CPU until a real
    # MPS path is validated.
    import tempfile

    try:
        import librosa
        import torch
    except ImportError as exc:
        raise RuntimeError(
            "librosa/torch are not installed in this engine venv; "
            "install the prebuilt host wheels for the MT3 transcription engine."
        ) from exc
    _install_mt3_transformers_checkpoint_compat()
    try:
        from mt3_infer import load_model
    except ImportError as exc:
        raise RuntimeError(
            "mt3_infer is not installed in this engine venv; install the "
            "prebuilt host wheels for the MT3 transcription engine."
        ) from exc

    weights_dir = get_model_path(context.model_id)
    if context.model_id == "music-mr-mt3":
        mt3_model_name = "mr_mt3"
        checkpoint_path = weights_dir / "payload"
    elif context.model_id == "music-mt3-infer":
        mt3_model_name = "mt3_pytorch"
        checkpoint_path = weights_dir
    else:
        raise RuntimeError(f"unsupported mt3 model id {context.model_id!r}")

    device = "cuda" if torch.cuda.is_available() else "cpu"
    input_audio = download_demo_object(context.input_object_ref)
    temp_wav = materialize_temp_input(input_audio, ".wav")
    audio, _sample_rate = librosa.load(temp_wav, sr=16000, mono=True)
    model = load_model(
        mt3_model_name,
        checkpoint_path=str(checkpoint_path),
        device=device,
        auto_download=False,
        cache=True,
    )
    if context.model_id == "music-mt3-infer":
        _disable_mt3_generation_cache(model)
    midi = model.transcribe(audio.astype("float32", copy=False), sr=16000)
    with tempfile.NamedTemporaryFile(suffix=".mid", delete=False) as handle:
        midi_path = handle.name
    midi.save(midi_path)
    with open(midi_path, "rb") as handle:
        midi_bytes = handle.read()
    return ArtifactResult(data=midi_bytes, content_type="audio/midi", suffix=".mid")


def _transcribe_piano(context: AdapterContext) -> ArtifactResult:
    # Phase 4 Sprint 4.22: ByteDance/qiuqiangkong piano transcription via the
    # maintained `piano_transcription_inference` package. The single-file CRNN
    # checkpoint is staged into the model cache (MinIO infernix-models) by the
    # bootstrap path and resolved via get_model_path; we pass it explicitly as
    # checkpoint_path so the package never auto-downloads to a HOME-relative
    # path or reads MT3_CHECKPOINT_DIR (no-env-vars + model_cache doctrine).
    import tempfile

    try:
        import librosa
        import torch
        from piano_transcription_inference import PianoTranscription
    except ImportError as exc:
        raise RuntimeError(
            "librosa/piano_transcription_inference are not installed in this "
            "engine venv; install the prebuilt host wheels for the piano "
            "transcription engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    checkpoint = str(weights_dir / "payload")
    device = _preferred_torch_device(torch)
    input_audio = download_demo_object(context.input_object_ref)
    temp_wav = materialize_temp_input(input_audio, ".wav")
    audio, _ = librosa.load(temp_wav, sr=16000, mono=True)
    with tempfile.NamedTemporaryFile(suffix=".mid", delete=False) as handle:
        midi_path = handle.name
    transcriptor = PianoTranscription(device=device, checkpoint_path=checkpoint)
    transcriptor.transcribe(audio, midi_path)
    with open(midi_path, "rb") as handle:
        midi_bytes = handle.read()
    return ArtifactResult(data=midi_bytes, content_type="audio/midi", suffix=".mid")


def main() -> int:
    return run_artifact_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("pytorch-python")


if __name__ == "__main__":
    raise SystemExit(main())
