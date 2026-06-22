from __future__ import annotations

import gc
from contextlib import suppress

from adapters.common import AdapterContext, run_context_adapter, run_setup_from_argv
from adapters.model_cache import get_model_path


def _release_vllm_engine(engine: object | None) -> None:
    if engine is not None:
        llm_engine = getattr(engine, "llm_engine", None)
        engine_core = getattr(llm_engine, "engine_core", None)
        if engine_core is not None:
            with suppress(Exception):
                engine_core.shutdown()
        sleep = getattr(engine, "sleep", None)
        if callable(sleep):
            with suppress(Exception):
                sleep(level=2)

    with suppress(Exception):
        from vllm.distributed.parallel_state import cleanup_dist_env_and_memory

        cleanup_dist_env_and_memory()

    with suppress(Exception):
        import torch

        if torch.cuda.is_available():
            torch.cuda.synchronize()
            torch.cuda.empty_cache()
            torch.cuda.ipc_collect()
    gc.collect()


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
    # the same real GPU inference without the toolchain dependency. The routed
    # smoke path asks for short continuations, so cap the KV-cache context window
    # instead of letting long-context model defaults make quantized rows flaky on
    # the single-GPU validation lane.
    llm_options = {
        "model": str(weights_dir),
        "enforce_eager": True,
        "max_model_len": 2048,
        "gpu_memory_utilization": 0.25,
    }
    if context.model_id.endswith("-awq"):
        llm_options.update({"quantization": "awq", "dtype": "half"})
    elif context.model_id.endswith("-gptq"):
        llm_options.update({"quantization": "gptq", "dtype": "half"})
    engine = None
    try:
        engine = LLM(**llm_options)
        sampling = SamplingParams(max_tokens=256)
        outputs = engine.generate([context.input_text], sampling)
        continuation: str = outputs[0].outputs[0].text
        return continuation
    finally:
        _release_vllm_engine(engine)


def main() -> int:
    return run_context_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("vllm-python")


if __name__ == "__main__":
    raise SystemExit(main())
