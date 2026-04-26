from __future__ import annotations

import sys
from collections.abc import Callable

import infernix.runtime.inference_pb2 as inference_pb2


def _decode_request() -> inference_pb2.WorkerRequest:
    request = inference_pb2.WorkerRequest()
    request.ParseFromString(sys.stdin.buffer.read())
    return request


def _write_response(response: inference_pb2.WorkerResponse) -> None:
    sys.stdout.buffer.write(response.SerializeToString())


def run_text_adapter(transform: Callable[[inference_pb2.WorkerRequest], str]) -> int:
    request = _decode_request()
    try:
        output_text = transform(request)
    except Exception as exc:
        error_response = inference_pb2.WorkerResponse(
            error_code="adapter_failed",
            error_message=str(exc),
        )
        _write_response(error_response)
        return 0
    response = inference_pb2.WorkerResponse(output_text=output_text)
    _write_response(response)
    return 0
