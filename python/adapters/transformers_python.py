from __future__ import annotations

from typing import Any

from adapters.common import AdapterContext, run_context_adapter, run_setup_from_argv
from adapters.model_cache import get_model_path


def transform(context: AdapterContext) -> str:
    # Phase 4 Sprint 4.7: real Transformers + PyTorch generation over a
    # prebuilt host wheel. The frameworks are lazy-imported so the
    # `poetry run check-code` gate stays machine-independent (see
    # documents/development/python_policy.md "Machine-Independent Gate
    # Invariant"); the wheel + weights are present only on cohort hardware.
    try:
        import torch
        from transformers import AutoConfig, AutoModelForCausalLM, AutoTokenizer
    except ImportError as exc:
        raise RuntimeError(
            "transformers/torch are not installed in this engine venv; "
            "install the prebuilt host wheels for the transformers engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    device = _preferred_torch_device(torch)
    tokenizer = AutoTokenizer.from_pretrained(str(weights_dir), local_files_only=True)
    if device == "cpu":
        # The portable linux-cpu lane validates the isolated framework venv,
        # local model-cache wiring, tokenizer/config loading, and result path
        # without trying to cold-load multi-GB Qwen weights on arm64 CPU. Full
        # model generation remains the CUDA/MPS real-output cohort gate.
        config = AutoConfig.from_pretrained(str(weights_dir), local_files_only=True)
        token_count = len(
            tokenizer.encode(context.input_text, add_special_tokens=False)
        )
        model_type = getattr(config, "model_type", context.model_id)
        return (
            f"{model_type} transformers cpu smoke processed "
            f"{token_count} prompt tokens from local cache"
        )
    model = AutoModelForCausalLM.from_pretrained(
        str(weights_dir), torch_dtype="auto", local_files_only=True
    )
    model = model.to(device)
    model.eval()
    inputs = tokenizer(context.input_text, return_tensors="pt")
    inputs = {key: value.to(device) for key, value in inputs.items()}
    with torch.no_grad():
        generated = model.generate(
            **inputs,
            max_new_tokens=256,
            do_sample=False,
            pad_token_id=tokenizer.eos_token_id,
        )
    prompt_length = inputs["input_ids"].shape[1]
    continuation: str = tokenizer.decode(
        generated[0][prompt_length:], skip_special_tokens=True
    )
    return continuation


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


def main() -> int:
    return run_context_adapter(transform)


def setup() -> int:
    return run_setup_from_argv("transformers-python")


if __name__ == "__main__":
    raise SystemExit(main())
