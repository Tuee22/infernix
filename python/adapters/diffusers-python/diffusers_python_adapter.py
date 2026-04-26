from __future__ import annotations

import infernix.runtime.inference_pb2 as inference_pb2
from common import run_text_adapter


def transform(request: inference_pb2.WorkerRequest) -> str:
    return request.input_text.strip()


if __name__ == "__main__":
    raise SystemExit(run_text_adapter(transform))
