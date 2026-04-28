from __future__ import annotations

from adapters.common import (
    AdapterContext,
    render_engine_output,
    run_context_adapter,
    run_setup_bootstrap,
)


def transform(context: AdapterContext) -> str:
    vowels = sum(1 for character in context.input_text.lower() if character in "aeiou")
    detail = f"chars={len(context.input_text)}:vowels={vowels}"
    return render_engine_output("tensorflow-python", context, detail)


def main() -> int:
    return run_context_adapter(transform)


def setup() -> int:
    return run_setup_bootstrap("tensorflow-python")


if __name__ == "__main__":
    raise SystemExit(main())
