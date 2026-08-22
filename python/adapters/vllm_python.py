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


def _observed_device_envelope_mib() -> int:
    """Phase 6 Sprint 6.51 — the device's own total, in MiB.

    Read from the same NVML surface the sampler uses, so the arena's denominator
    is an observation of the card this pod was scheduled onto rather than a
    number anybody wrote down.
    """
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError(
            "a device arena was requested on a host with no visible CUDA device"
        )
    total_bytes = int(torch.cuda.get_device_properties(0).total_memory)
    return total_bytes // (1024 * 1024)


def _device_arena_fraction(context: AdapterContext) -> float:
    """Phase 6 Sprint 6.51 — the admitted device quantity over the observed
    device envelope.

    The retired literal made the engine's device consumption follow from a
    fraction and from whichever card the pod was scheduled onto: change the card
    and the same model consumed a different amount; change the model and it
    consumed the same amount. A number with both of those properties is
    determined by the hardware, and admitting a model against a derived
    requirement while the engine sizes itself from the card leaves the admission
    decision with nothing downstream that respects it.

    Read out of the installed package rather than out of its documentation
    string, ``gpu_memory_utilization`` has exactly three uses: a startup check
    that free memory is at least the requested fraction of total, the sizing of
    the key/value cache arena, and a log line. No allocation path consults it
    afterwards. It is an admission input and an arena input, and every
    description of it as a limit is a category error.
    """
    admitted_mib = context.require_device_mib()
    envelope_mib = _observed_device_envelope_mib()
    if envelope_mib <= 0:
        raise RuntimeError(
            "the observed device envelope is not positive, so no arena fraction "
            "can be derived from it"
        )
    if admitted_mib > envelope_mib:
        raise RuntimeError(
            f"the admitted device quantity of {admitted_mib} MiB exceeds the "
            f"observed device envelope of {envelope_mib} MiB"
        )
    return admitted_mib / envelope_mib


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
        "max_model_len": context.context_length,
        # Phase 6 Sprint 6.51: the arena is the admitted device quantity over the
        # observed device envelope, so it tracks the model rather than the card.
        # A larger card now yields a *smaller* fraction for the same model, and
        # that inversion is the observable sign that the number has stopped
        # belonging to the hardware.
        "gpu_memory_utilization": _device_arena_fraction(context),
    }
    if context.model_id.endswith("-awq"):
        llm_options.update({"quantization": "awq", "dtype": "half"})
    elif context.model_id.endswith("-gptq"):
        llm_options.update({"quantization": "gptq", "dtype": "half"})
    engine = None
    try:
        engine = LLM(**llm_options)
        sampling = SamplingParams(max_tokens=context.generation_bound)
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
