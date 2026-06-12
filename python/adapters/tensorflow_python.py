from __future__ import annotations

import io

from adapters.common import (
    AdapterContext,
    ArtifactResult,
    download_demo_object,
    materialize_temp_input,
    run_artifact_adapter,
    run_setup_from_argv,
)
from adapters.model_cache import get_model_path


def transform(context: AdapterContext) -> ArtifactResult:
    # Phase 4 Sprint 4.7/4.15: real TensorFlow artifact families — Basic
    # Pitch audio-to-MIDI and Omnizart music transcription. Both consume an
    # audio object reference and return a MIDI artifact. Frameworks are
    # lazy-imported so the quality gate stays machine-independent.
    if "omnizart" in context.model_id:
        return _transcribe_omnizart(context)
    return _audio_to_midi_basic_pitch(context)


def _audio_to_midi_basic_pitch(context: AdapterContext) -> ArtifactResult:
    try:
        from basic_pitch.inference import predict
    except ImportError as exc:
        raise RuntimeError(
            "basic-pitch is not installed in this TensorFlow engine venv; "
            "the published package requires TensorFlow <2.15.1 and is a "
            "named residual on the Python 3.12 / CUDA 12.8 substrate. Use "
            "the Core ML or ONNX Basic Pitch lane until a maintained "
            "TensorFlow package is adopted."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    input_audio = download_demo_object(context.input_object_ref)
    audio_path = materialize_temp_input(input_audio, ".wav")
    _, midi_data, _ = predict(audio_path, str(weights_dir))
    buffer = io.BytesIO()
    midi_data.write(buffer)
    return ArtifactResult(
        data=buffer.getvalue(), content_type="audio/midi", suffix=".mid"
    )


def _transcribe_omnizart(context: AdapterContext) -> ArtifactResult:
    try:
        from omnizart.music import app as music_app
    except ImportError as exc:
        raise RuntimeError(
            "omnizart is not installed in this TensorFlow engine venv; "
            "the upstream TF1-era stack is a named residual on the Python "
            "3.12 / CUDA 12.8 substrate."
        ) from exc
    _ = get_model_path(context.model_id)
    input_audio = download_demo_object(context.input_object_ref)
    audio_path = materialize_temp_input(input_audio, ".wav")
    midi_object = music_app.transcribe(audio_path)
    midi_path = materialize_temp_input(b"", ".mid")
    midi_object.write(midi_path)
    with open(midi_path, "rb") as midi_file:
        data = midi_file.read()
    return ArtifactResult(data=data, content_type="audio/midi", suffix=".mid")


def main() -> int:
    return run_artifact_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("tensorflow-python")


if __name__ == "__main__":
    raise SystemExit(main())
