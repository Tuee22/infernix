from __future__ import annotations

from adapters.common import (
    inference_pb2,
    request_input_text,
    run_setup_noop,
    run_text_adapter,
)


def transform(request: inference_pb2.WorkerRequest) -> str:
    return request_input_text(request).strip()


def main() -> int:
    return run_text_adapter(transform)


def setup() -> int:
    return run_setup_noop("pytorch-python")


if __name__ == "__main__":
    raise SystemExit(main())
