from __future__ import annotations

from adapters.common import (
    AdapterContext,
    render_engine_output,
    run_context_adapter,
    run_setup_bootstrap,
    short_digest,
)


def transform(context: AdapterContext) -> str:
    detail = "img=" + short_digest(context.input_text)
    return render_engine_output("diffusers-python", context, detail)


def main() -> int:
    return run_context_adapter(transform)


def setup() -> int:
    return run_setup_bootstrap("diffusers-python")


if __name__ == "__main__":
    raise SystemExit(main())
