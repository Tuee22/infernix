from __future__ import annotations

import io
from typing import Any

from adapters.common import (
    AdapterContext,
    ArtifactResult,
    run_artifact_adapter,
    run_setup_from_argv,
)
from adapters.model_cache import get_model_path


def transform(context: AdapterContext) -> ArtifactResult:
    # Phase 4 Sprint 4.7/4.15: real Diffusers image/video generation over a
    # prebuilt host wheel, returning a typed artifact uploaded to
    # infernix-demo-objects. Frameworks are lazy-imported so the quality
    # gate stays machine-independent.
    weights_dir = get_model_path(context.model_id)
    try:
        import torch
        from diffusers import DiffusionPipeline
    except ImportError as exc:
        raise RuntimeError(
            "diffusers is not installed in this engine venv; "
            "install the prebuilt host wheels for the diffusers engine."
        ) from exc
    # Wave I real-output fix: diffusion pipelines must run on the GPU/MPS
    # accelerator, not the default CPU placement. On CPU (fp32) SDXL never
    # finishes inside the routed result-publish budget; the cohort lanes load
    # in half precision and move the pipeline to the available device.
    device = _preferred_torch_device(torch)
    dtype = torch.float16 if device in {"cuda", "mps"} else torch.float32
    load_options: dict[str, Any] = {
        "torch_dtype": dtype,
        "local_files_only": True,
    }
    if context.model_id == "image-sdxl-turbo":
        load_options["variant"] = "fp16"
        load_options["use_safetensors"] = True
    pipeline = DiffusionPipeline.from_pretrained(str(weights_dir), **load_options)
    pipeline = pipeline.to(device)
    if context.family == "video":
        return _render_video(pipeline, context.input_text)
    return _render_image(pipeline, context.input_text)


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


def main() -> int:
    return run_artifact_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("diffusers-python")


if __name__ == "__main__":
    raise SystemExit(main())
