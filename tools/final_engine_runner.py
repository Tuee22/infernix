#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import importlib
import importlib.util
import json
import pathlib
import platform
import subprocess
import sys
import urllib.parse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-bundle", required=True)
    parser.add_argument("--request-id", default="")
    parser.add_argument("--input-text", required=True)
    parser.add_argument("--adapter-id", default="")
    return parser.parse_args()


def load_bundle(path: pathlib.Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("artifact bundle must be a JSON object")
    return payload


def string_field(bundle: dict[str, object], field_name: str) -> str:
    value = bundle.get(field_name)
    return value if isinstance(value, str) else ""


def list_field(bundle: dict[str, object], field_name: str) -> list[dict[str, object]]:
    value = bundle.get(field_name)
    if not isinstance(value, list):
        return []
    return [entry for entry in value if isinstance(entry, dict)]


def load_source_manifest(bundle: dict[str, object]) -> dict[str, object]:
    manifest_path_value = string_field(bundle, "sourceArtifactManifestPath")
    if not manifest_path_value:
        return {}
    manifest_path = pathlib.Path(manifest_path_value)
    if not manifest_path.exists():
        return {}
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def load_source_payload(bundle: dict[str, object]) -> bytes:
    local_path_value = string_field(bundle, "sourceArtifactLocalPath")
    if local_path_value:
        local_path = pathlib.Path(local_path_value)
        if local_path.exists():
            return local_path.read_bytes()

    source_uri = string_field(bundle, "sourceArtifactUri")
    if source_uri.startswith("file://"):
        local_path = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(source_uri).path))
        if local_path.exists():
            return local_path.read_bytes()
    elif source_uri:
        local_path = pathlib.Path(source_uri)
        if local_path.exists():
            return local_path.read_bytes()
    return b""


def run_command(command: list[str]) -> tuple[bool, str]:
    try:
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
    except FileNotFoundError as exc:
        return False, str(exc)
    output = (completed.stdout or completed.stderr).strip()
    if completed.returncode == 0:
        first_line = output.splitlines()[0] if output else ""
        return True, first_line
    return False, output or f"exit {completed.returncode}"


def external_command_status(locator: str, adapter_id: str) -> str:
    if not locator:
        return "command-unconfigured"
    if adapter_id == "jvm-cli":
        ok, output = run_command([locator, "-version"])
    else:
        ok, output = run_command([locator, "--version"])
        if not ok:
            ok, output = run_command([locator, "--help"])
    return f"command-ready:{output or locator}" if ok else f"command-unavailable:{output or locator}"


def module_import_status(module_name: str) -> tuple[bool, str]:
    if not module_name or importlib.util.find_spec(module_name) is None:
        return False, "module-not-installed"
    try:
        module = importlib.import_module(module_name)
        version = getattr(module, "__version__", "")
    except Exception as exc:  # pragma: no cover - defensive reporting
        return False, f"module-import-failed:{exc}"
    suffix = f":{version}" if isinstance(version, str) and version else ""
    return True, f"module-ready:{module_name}{suffix}"


def module_smoke_status(adapter_id: str, module_name: str, input_text: str) -> str:
    available, status = module_import_status(module_name)
    if not available:
        return f"module-unavailable:{adapter_id}"

    if adapter_id == "pytorch-python" and module_name == "torch":
        try:
            import torch

            value = torch.tensor([len(input_text), 1]).sum().item()
            return f"{status}:tensor-sum={value}"
        except Exception as exc:  # pragma: no cover - defensive reporting
            return f"{status}:smoke-failed:{exc}"

    if adapter_id == "jax-python":
        try:
            import jax.numpy as jnp

            value = int(jnp.array([len(input_text), 1]).sum())
            return f"{status}:array-sum={value}"
        except Exception as exc:  # pragma: no cover - defensive reporting
            return f"{status}:smoke-failed:{exc}"

    if adapter_id == "tensorflow-python":
        try:
            import tensorflow as tf

            value = int(tf.reduce_sum(tf.constant([len(input_text), 1])).numpy())
            return f"{status}:tensor-sum={value}"
        except Exception as exc:  # pragma: no cover - defensive reporting
            return f"{status}:smoke-failed:{exc}"

    return status


def probe_gpu(bundle: dict[str, object]) -> str:
    runtime_mode = string_field(bundle, "runtimeMode")
    runtime_lane = string_field(bundle, "runtimeLane")
    if runtime_mode != "linux-cuda" and "gpu" not in runtime_lane:
        return "cpu-or-host-lane"
    ok, output = run_command(["nvidia-smi", "-L"])
    if ok:
        first_gpu = output.splitlines()[0] if output else "gpu-visible"
        return f"gpu-visible:{first_gpu}"
    return f"gpu-unavailable:{output or 'nvidia-smi unavailable'}"


def runner_status(bundle: dict[str, object], adapter_id: str, input_text: str) -> str:
    adapter_type = string_field(bundle, "engineAdapterType")
    adapter_locator = string_field(bundle, "engineAdapterLocator")
    if adapter_type == "external-command":
        return external_command_status(adapter_locator, adapter_id)
    if adapter_type == "python-module":
        return module_smoke_status(adapter_id, adapter_locator, input_text)
    return f"runner-unconfigured:{adapter_id or 'unspecified'}"


def payload_digest(payload: bytes) -> str:
    if not payload:
        return "none"
    return hashlib.sha256(payload).hexdigest()[:12]


def manifest_summary(manifest: dict[str, object]) -> str:
    if not manifest:
        return "manifest=missing"
    acquisition_mode = manifest.get("acquisitionMode")
    fetch_status = manifest.get("fetchStatus")
    selection_mode = manifest.get("selectionMode")
    summary_parts = [
        f"manifest={acquisition_mode}" if isinstance(acquisition_mode, str) and acquisition_mode else "manifest=unknown",
        f"fetch={fetch_status}" if isinstance(fetch_status, str) and fetch_status else "fetch=unknown",
        f"selection={selection_mode}" if isinstance(selection_mode, str) and selection_mode else "selection=unknown",
    ]
    return "/".join(summary_parts)


def selected_artifact_summary(bundle: dict[str, object], manifest: dict[str, object]) -> str:
    manifest_entries = manifest.get("selectedArtifacts")
    entries = manifest_entries if isinstance(manifest_entries, list) else list_field(bundle, "sourceArtifactSelectedArtifacts")
    parsed_entries = [entry for entry in entries if isinstance(entry, dict)]
    if not parsed_entries:
        return "artifacts=none"
    first_entry = parsed_entries[0]
    first_kind = first_entry.get("artifactKind")
    first_uri = first_entry.get("uri")
    kind_text = first_kind if isinstance(first_kind, str) and first_kind else "unknown"
    uri_text = first_uri if isinstance(first_uri, str) and first_uri else "unknown"
    return f"artifacts={len(parsed_entries)}:{kind_text}:{uri_text}"


def family_response(family: str, input_text: str) -> str:
    normalized = " ".join(input_text.split())
    if family == "llm":
        return f"text={normalized.upper()[:48]}"
    if family in {"speech", "music"}:
        return f"segments={max(1, len(normalized) // 8)}"
    if family == "audio":
        return f"frames={max(1, len(normalized) // 4)}"
    if family == "image":
        return f"prompt_tokens={len(normalized.split())}"
    if family == "video":
        return f"shots={max(1, len(normalized.split()) // 3)}"
    return f"input_chars={len(normalized)}"


def render_output(bundle: dict[str, object], adapter_id: str, input_text: str) -> str:
    family = string_field(bundle, "family")
    selected_engine = string_field(bundle, "selectedEngine")
    reference_model = string_field(bundle, "referenceModel")
    runtime_mode = string_field(bundle, "runtimeMode")
    worker_profile = string_field(bundle, "workerProfile")
    source_manifest = load_source_manifest(bundle)
    source_payload = load_source_payload(bundle)
    execution_detail = runner_status(bundle, adapter_id, input_text)
    gpu_status = probe_gpu(bundle)
    platform_id = f"{platform.system().lower()}-{platform.machine().lower()}"
    manifest_detail = manifest_summary(source_manifest)
    selected_artifacts = selected_artifact_summary(bundle, source_manifest)
    artifact_mode = string_field(bundle, "artifactAcquisitionMode") or "unknown"
    selection_mode = string_field(bundle, "sourceArtifactSelectionMode") or "unknown"
    authoritative_uri = string_field(bundle, "sourceArtifactAuthoritativeUri") or string_field(bundle, "sourceArtifactResolvedUrl") or string_field(bundle, "sourceDownloadUrl")
    authoritative_kind = string_field(bundle, "sourceArtifactAuthoritativeKind") or "unknown"
    payload_hash = payload_digest(source_payload)
    family_detail = family_response(family, input_text)

    return (
        f"{selected_engine} executed {reference_model} on {runtime_mode} ({platform_id}) "
        f"via {adapter_id or string_field(bundle, 'engineAdapterId') or 'engine-runner'}; "
        f"profile={worker_profile}; runner={execution_detail}; gpu={gpu_status}; "
        f"artifact={artifact_mode}; authoritative={authoritative_kind}; "
        f"{manifest_detail}; selectionMode={selection_mode}; {selected_artifacts}; "
        f"payload={payload_hash}; source={authoritative_uri or 'unresolved'}; {family_detail}; input={input_text}"
    )


def main() -> int:
    args = parse_args()
    try:
        bundle = load_bundle(pathlib.Path(args.artifact_bundle).resolve())
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        print(f"final-engine-runner: {exc}", file=sys.stderr)
        return 1

    if string_field(bundle, "artifactAcquisitionMode") == "":
        print("final-engine-runner: artifact bundle is missing artifact acquisition metadata", file=sys.stderr)
        return 1

    print(render_output(bundle, args.adapter_id, args.input_text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
