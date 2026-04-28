from __future__ import annotations

from adapters.common import (
    AdapterContext,
    render_engine_output,
    run_context_adapter,
    run_setup_bootstrap,
    word_list,
)


def transform(context: AdapterContext) -> str:
    words = word_list(context.input_text)
    detail = "shape=" + ("x".join(str(len(word)) for word in words) if words else "0")
    return render_engine_output("jax-python", context, detail)


def main() -> int:
    return run_context_adapter(transform)


def setup() -> int:
    return run_setup_bootstrap("jax-python")


if __name__ == "__main__":
    raise SystemExit(main())
