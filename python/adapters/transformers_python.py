from __future__ import annotations

from typing import Any, cast

from adapters.common import (
    AdapterContext,
    ConversationTurn,
    run_context_adapter,
    run_setup_from_argv,
)
from adapters.model_cache import get_model_path


def transform(context: AdapterContext) -> str:
    # Phase 4 Sprint 4.7: real Transformers + PyTorch generation over a
    # prebuilt host wheel. The frameworks are lazy-imported so the
    # `poetry run check-code` gate stays machine-independent (see
    # documents/development/python_policy.md "Machine-Independent Gate
    # Invariant"); the wheel + weights are present only on cohort hardware.
    try:
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer
    except ImportError as exc:
        raise RuntimeError(
            "transformers/torch are not installed in this engine venv; "
            "install the prebuilt host wheels for the transformers engine."
        ) from exc
    weights_dir = get_model_path(context.model_id)
    device = _preferred_torch_device(torch)
    tokenizer = AutoTokenizer.from_pretrained(str(weights_dir), local_files_only=True)
    model = AutoModelForCausalLM.from_pretrained(
        str(weights_dir),
        torch_dtype="auto",
        local_files_only=True,
        low_cpu_mem_usage=True,
    )
    model = model.to(device)
    model.eval()
    # Phase 7 Sprint 7.31: this engine holds no state between requests, so the
    # verified prefix is replayed in full rather than a reuse being claimed.
    inputs = _tokenize_prompt(tokenizer, context.prompt_turns())
    inputs = {key: value.to(device) for key, value in inputs.items()}
    with torch.no_grad():
        generated = model.generate(
            **inputs,
            max_new_tokens=context.generation_bound,
            do_sample=False,
            pad_token_id=tokenizer.eos_token_id,
        )
    prompt_length = inputs["input_ids"].shape[1]
    continuation: str = tokenizer.decode(
        generated[0][prompt_length:], skip_special_tokens=True
    )
    return continuation


def _tokenize_prompt(tokenizer: Any, turns: list[ConversationTurn]) -> dict[str, Any]:
    """Tokenize the whole verified prefix, newest turn last.

    A chat template is given every turn with its own role, which is what makes
    the model's answer depend on the conversation rather than on the last
    message alone. Without a template the turns are flattened in order, which is
    a weaker replay but still a replay; dropping the earlier turns would not be.
    """
    if getattr(tokenizer, "chat_template", None):
        messages = [{"role": turn.role, "content": turn.text} for turn in turns]
        try:
            templated = tokenizer.apply_chat_template(
                messages,
                add_generation_prompt=True,
                tokenize=True,
                return_dict=True,
                return_tensors="pt",
            )
        except TypeError:
            templated = None
        if isinstance(templated, dict):
            return templated
    flattened = "\n".join(f"{turn.role}: {turn.text}" for turn in turns)
    return cast(dict[str, Any], tokenizer(flattened, return_tensors="pt"))


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
