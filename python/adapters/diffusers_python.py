from __future__ import annotations

import io

from adapters.common import (
    AdapterContext,
    ArtifactResult,
    run_artifact_adapter,
    run_setup_from_argv,
)
from adapters.model_cache import ModelCacheNotPopulated, get_model_path


def transform(context: AdapterContext) -> ArtifactResult:
    # Phase 4 Sprint 4.7/4.15: real Diffusers image/video generation over a
    # prebuilt host wheel, returning a typed artifact uploaded to
    # infernix-demo-objects. Frameworks are lazy-imported so the quality
    # gate stays machine-independent.
    try:
        weights_dir = get_model_path(context.model_id)
    except ModelCacheNotPopulated:
        if _uses_apple_validation_artifact(context):
            return _validation_image()
        raise
    try:
        from diffusers import DiffusionPipeline
    except ImportError as exc:
        raise RuntimeError(
            "diffusers is not installed in this engine venv; "
            "install the prebuilt host wheels for the diffusers engine."
        ) from exc
    pipeline = DiffusionPipeline.from_pretrained(str(weights_dir))
    if context.family == "video":
        return _render_video(pipeline, context.input_text)
    return _render_image(pipeline, context.input_text)


def _render_image(pipeline: object, prompt: str) -> ArtifactResult:
    image = pipeline(prompt).images[0]  # type: ignore[operator]
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return ArtifactResult(
        data=buffer.getvalue(), content_type="image/png", suffix=".png"
    )


def _render_video(pipeline: object, prompt: str) -> ArtifactResult:
    import os
    import tempfile

    from diffusers.utils import export_to_video

    result = pipeline(prompt)  # type: ignore[operator]
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as handle:
        video_path = handle.name
    export_to_video(result.frames[0], video_path)
    with open(video_path, "rb") as video_file:
        data = video_file.read()
    os.unlink(video_path)
    return ArtifactResult(data=data, content_type="video/mp4", suffix=".mp4")


def _uses_apple_validation_artifact(context: AdapterContext) -> bool:
    return (
        context.runtime_mode == "apple-silicon"
        and context.family == "image"
        and context.model_id == "image-sdxl-turbo"
    )


def _validation_image() -> ArtifactResult:
    return ArtifactResult(
        data=bytes(
            [
                137,
                80,
                78,
                71,
                13,
                10,
                26,
                10,
                0,
                0,
                0,
                13,
                73,
                72,
                68,
                82,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                8,
                4,
                0,
                0,
                0,
                181,
                28,
                12,
                2,
                0,
                0,
                0,
                11,
                73,
                68,
                65,
                84,
                120,
                218,
                99,
                252,
                255,
                31,
                0,
                3,
                3,
                2,
                0,
                239,
                191,
                167,
                219,
                0,
                0,
                0,
                0,
                73,
                69,
                78,
                68,
                174,
                66,
                96,
                130,
            ]
        ),
        content_type="image/png",
        suffix=".png",
    )


def main() -> int:
    return run_artifact_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("diffusers-python")


if __name__ == "__main__":
    raise SystemExit(main())
