from __future__ import annotations

import hashlib
import importlib
import json
import os
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast


def _repo_root() -> Path:
    configured = os.environ.get("INFERNIX_REPO_ROOT")
    if configured:
        return Path(configured)
    return Path(__file__).resolve().parents[2]


generated_proto_root = _repo_root() / "tools" / "generated_proto"
if str(generated_proto_root) not in sys.path:
    sys.path.insert(0, str(generated_proto_root))

try:
    inference_pb2: Any = importlib.import_module("infernix.runtime.inference_pb2")
except ModuleNotFoundError:  # pragma: no cover - exercised before proto generation
    inference_pb2 = None

__all__ = [
    "AdapterContext",
    "inference_pb2",
    "normalized_input_text",
    "render_engine_output",
    "run_check_code",
    "run_context_adapter",
    "run_setup_bootstrap",
]


@dataclass(frozen=True)
class AdapterContext:
    adapter_id: str
    runtime_mode: str
    model_id: str
    display_name: str
    family: str
    selected_engine: str
    artifact_type: str
    runtime_lane: str
    input_text: str
    bootstrap_ready: bool
    bootstrap_manifest_path: str


def _decode_request() -> inference_pb2.WorkerRequest:
    _require_inference_pb2()
    request = inference_pb2.WorkerRequest()
    request.ParseFromString(sys.stdin.buffer.read())
    return request


def _write_response(response: inference_pb2.WorkerResponse) -> None:
    sys.stdout.buffer.write(response.SerializeToString())


def normalized_input_text(value: str) -> str:
    return " ".join(value.split())


def run_context_adapter(transform: Callable[[AdapterContext], str]) -> int:
    request = _decode_request()
    try:
        output_text = transform(load_adapter_context(request))
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


def run_setup_bootstrap(adapter_id: str) -> int:
    install_root = _engine_install_root(adapter_id)
    install_root.mkdir(parents=True, exist_ok=True)
    bootstrap_manifest = {
        "adapterId": adapter_id,
        "repoRoot": str(_repo_root()),
        "runtimeMode": os.environ.get("INFERNIX_ACTIVE_SUBSTRATE", "unknown"),
        "updatedAt": datetime.now(UTC).isoformat(),
    }
    (install_root / "bootstrap.json").write_text(
        json.dumps(bootstrap_manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
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


def load_adapter_context(request: inference_pb2.WorkerRequest) -> AdapterContext:
    # Phase 7 Sprint 7.7 retires the ./.data/object-store/ tree, so the
    # daemon ships model metadata straight on the WorkerRequest envelope
    # instead of staging synthetic artifact-bundle / source-manifest JSON
    # files. The MinIO infernix-models bucket is now the only durable
    # source of weight artifacts, fetched lazily by
    # adapters.model_cache.get_model_path.
    bootstrap_path = Path(cast(str, request.engine_install_root)) / "bootstrap.json"
    bootstrap_ready = bootstrap_path.exists()
    return AdapterContext(
        adapter_id=cast(str, request.adapter_id),
        runtime_mode=cast(str, request.runtime_mode),
        model_id=cast(str, request.request_model_id),
        display_name=cast(str, request.display_name),
        family=cast(str, request.family),
        selected_engine=cast(str, request.selected_engine),
        artifact_type=cast(str, request.artifact_type),
        runtime_lane=cast(str, request.runtime_lane),
        input_text=normalized_input_text(cast(str, request.input_text)),
        bootstrap_ready=bootstrap_ready,
        bootstrap_manifest_path=str(bootstrap_path),
    )


def render_engine_output(
    adapter_name: str, context: AdapterContext, detail: str
) -> str:
    readiness = "ready" if context.bootstrap_ready else "cold"
    return "|".join(
        [
            adapter_name,
            readiness,
            context.model_id,
            detail,
            context.input_text,
        ]
    )


def short_digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:10]


def word_list(value: str) -> list[str]:
    normalized = normalized_input_text(value)
    return [] if not normalized else normalized.split(" ")


def _engine_install_root(adapter_id: str) -> Path:
    configured = os.environ.get("INFERNIX_ENGINE_INSTALL_ROOT")
    if configured:
        return Path(configured)
    return _repo_root() / ".data" / "engines" / adapter_id


def _require_inference_pb2() -> Any:
    global inference_pb2
    if inference_pb2 is None:
        inference_pb2 = importlib.import_module("infernix.runtime.inference_pb2")
    return inference_pb2
