from __future__ import annotations

import io
import zipfile

from adapters.common import (
    AdapterContext,
    ArtifactResult,
    download_demo_object,
    run_artifact_adapter,
    run_setup_from_argv,
)
from adapters.model_cache import get_model_path


def transform(context: AdapterContext) -> ArtifactResult:
    # Phase 4 Sprint 4.7/4.15: real PyTorch artifact families — Bark audio
    # generation (text prompt -> WAV) and Demucs/Open-Unmix source
    # separation (audio input -> stem ZIP). Frameworks are lazy-imported so
    # the quality gate stays machine-independent.
    if "bark" in context.model_id:
        return _generate_bark(context)
    return _separate_sources(context)


def _generate_bark(context: AdapterContext) -> ArtifactResult:
    try:
        import scipy.io.wavfile
        from transformers import AutoProcessor, BarkModel
    except ImportError as exc:
        raise RuntimeError(
            "transformers/scipy are not installed in this engine venv; "
            "install the prebuilt host wheels for the Bark audio engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    processor = AutoProcessor.from_pretrained(str(weights_dir))
    model = BarkModel.from_pretrained(str(weights_dir))
    inputs = processor(context.input_text)
    audio = model.generate(**inputs)
    sample_rate = int(model.generation_config.sample_rate)
    buffer = io.BytesIO()
    scipy.io.wavfile.write(buffer, sample_rate, audio.cpu().numpy().squeeze())
    return ArtifactResult(
        data=buffer.getvalue(), content_type="audio/wav", suffix=".wav"
    )


def _separate_sources(context: AdapterContext) -> ArtifactResult:
    try:
        import torchaudio
        from demucs.apply import apply_model
        from demucs.pretrained import get_model
    except ImportError as exc:
        raise RuntimeError(
            "torchaudio/demucs are not installed in this engine venv; "
            "install the prebuilt host wheels for the source-separation engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    input_audio = download_demo_object(context.input_object_ref)
    waveform, sample_rate = torchaudio.load(io.BytesIO(input_audio))
    model = get_model(str(weights_dir))
    stems = apply_model(model, waveform.unsqueeze(0))[0]
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as bundle:
        for index, source_name in enumerate(model.sources):
            stem_buffer = io.BytesIO()
            torchaudio.save(stem_buffer, stems[index], sample_rate, format="wav")
            bundle.writestr(f"{source_name}.wav", stem_buffer.getvalue())
    return ArtifactResult(
        data=archive.getvalue(), content_type="application/zip", suffix=".zip"
    )


def main() -> int:
    return run_artifact_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("pytorch-python")


if __name__ == "__main__":
    raise SystemExit(main())
