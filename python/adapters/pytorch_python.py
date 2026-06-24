from __future__ import annotations

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


def transform(context: AdapterContext) -> ArtifactResult:
    # Phase 4 Sprint 4.7/4.15/4.22: real PyTorch artifact families dispatched
    # by model id — Bark audio generation (text prompt -> WAV), Demucs/
    # Open-Unmix source separation (audio input -> stem ZIP), and ByteDance
    # piano transcription (audio input -> MIDI). Frameworks are lazy-imported
    # so the quality gate stays machine-independent.
    model_id = context.model_id
    if "bark" in model_id:
        return _generate_bark(context)
    if "demucs" in model_id or "unmix" in model_id:
        return _separate_sources(context)
    if "omnizart" in model_id:
        return _transcribe_piano(context)
    if "mt3" in model_id:
        raise RuntimeError(
            "real MT3 multi-instrument transcription is not yet wired on the "
            "pytorch adapter (reopened Phase 4 Sprint 4.22; YourMT3+ MoE "
            "deferred)"
        )
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
    processor = AutoProcessor.from_pretrained(str(weights_dir))
    model = BarkModel.from_pretrained(str(weights_dir)).to(device)
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
        from demucs.pretrained import get_model
    except ImportError as exc:
        raise RuntimeError(
            "torch/soundfile/demucs are not installed in this engine venv; "
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
    waveform = torch.as_tensor(audio_array.T.copy())
    try:
        model = get_model(str(weights_dir))
    except Exception as exc:
        raise RuntimeError(
            f"unable to load source-separation model from {weights_dir}"
        ) from exc
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
