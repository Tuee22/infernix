from __future__ import annotations

from adapters.common import AdapterContext, run_context_adapter, run_setup_from_argv
from adapters.model_cache import get_model_path


def transform(context: AdapterContext) -> str:
    # Phase 4 Sprint 4.7: real vLLM generation over a prebuilt host wheel.
    # vLLM is lazy-imported (it is CUDA-Linux-centric and absent on other
    # hosts) so the quality gate stays machine-independent.
    try:
        from vllm import LLM, SamplingParams
    except ImportError as exc:
        raise RuntimeError(
            "vllm is not installed in this engine venv; install the "
            "prebuilt host wheel for the vLLM engine (CUDA Linux)."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    # enforce_eager skips vLLM's torch.compile / CUDA-graph capture path, which
    # JIT-compiles kernels through torch inductor + triton and therefore needs a
    # host C compiler at runtime. The framework-free engine image ships no
    # toolchain, so the compile path raises InductorError ("Failed to find C
    # compiler") and the engine core fails to initialize; eager execution runs
    # the same real GPU inference without the toolchain dependency.
    engine = LLM(model=str(weights_dir), enforce_eager=True)
    sampling = SamplingParams(max_tokens=256)
    outputs = engine.generate([context.input_text], sampling)
    continuation: str = outputs[0].outputs[0].text
    return continuation


def main() -> int:
    return run_context_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("vllm-python")


if __name__ == "__main__":
    raise SystemExit(main())
