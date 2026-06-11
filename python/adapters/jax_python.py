from __future__ import annotations

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
    # Phase 4 Sprint 4.7/4.15: real MT3 (JAX) multi-instrument music
    # transcription. Consumes an audio object reference and returns a MIDI
    # artifact. The JAX stack is lazy-imported so the quality gate stays
    # machine-independent.
    try:
        from mt3_inference import InferenceModel
    except ImportError as exc:
        raise RuntimeError(
            "the MT3/JAX stack is not installed in this engine venv; "
            "install the prebuilt host wheels for the MT3 engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    input_audio = download_demo_object(context.input_object_ref)
    audio_path = materialize_temp_input(input_audio, ".wav")
    model = InferenceModel(str(weights_dir))
    midi_object = model.transcribe(audio_path)
    midi_path = materialize_temp_input(b"", ".mid")
    midi_object.write(midi_path)
    with open(midi_path, "rb") as midi_file:
        data = midi_file.read()
    return ArtifactResult(data=data, content_type="audio/midi", suffix=".mid")


def main() -> int:
    return run_artifact_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("jax-python")


if __name__ == "__main__":
    raise SystemExit(main())
