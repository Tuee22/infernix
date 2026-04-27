from __future__ import annotations

import importlib
import os
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any, cast


def _repo_root() -> Path:
    configured = os.environ.get("INFERNIX_REPO_ROOT")
    if configured:
        return Path(configured)
    return Path(__file__).resolve().parents[3]


generated_proto_root = _repo_root() / "tools" / "generated_proto"
if str(generated_proto_root) not in sys.path:
    sys.path.insert(0, str(generated_proto_root))

inference_pb2: Any = importlib.import_module("infernix.runtime.inference_pb2")

__all__ = [
    "inference_pb2",
    "request_input_text",
    "run_check_code",
    "run_setup_noop",
    "run_text_adapter",
]


def _decode_request() -> inference_pb2.WorkerRequest:
    request = inference_pb2.WorkerRequest()
    request.ParseFromString(sys.stdin.buffer.read())
    return request


def _write_response(response: inference_pb2.WorkerResponse) -> None:
    sys.stdout.buffer.write(response.SerializeToString())


def request_input_text(request: inference_pb2.WorkerRequest) -> str:
    return cast(str, request.input_text)


def run_text_adapter(transform: Callable[[inference_pb2.WorkerRequest], str]) -> int:
    request = _decode_request()
    try:
        output_text = transform(request)
    except Exception as exc:  # pragma: no cover - surfaced through worker tests
        error_response = inference_pb2.WorkerResponse(
            error_code="adapter_failed",
            error_message=str(exc),
        )
        _write_response(error_response)
        return 0
    response = inference_pb2.WorkerResponse(output_text=output_text)
    _write_response(response)
    return 0


def run_setup_noop(adapter_id: str) -> int:
    print(f"setup ready: {adapter_id}")
    return 0


def run_check_code() -> int:
    project_root = Path(__file__).resolve().parent.parent
    env = os.environ.copy()
    existing_mypy_path = env.get("MYPYPATH")
    env["MYPYPATH"] = (
        str(generated_proto_root)
        if not existing_mypy_path
        else existing_mypy_path + os.pathsep + str(generated_proto_root)
    )
    commands = [
        [sys.executable, "-m", "mypy", "--strict", "adapters"],
        [sys.executable, "-m", "black", "--check", "adapters"],
        [sys.executable, "-m", "ruff", "check", "adapters"],
    ]
    for command in commands:
        subprocess.run(command, cwd=project_root, check=True, env=env)
    return 0
