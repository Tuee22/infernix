#!/usr/bin/env python3

from __future__ import annotations

import argparse
import importlib
import importlib.util
import json
import pathlib
import platform
import subprocess
import sys


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


def probe_external_command(locator: str, adapter_id: str) -> str:
    if not locator:
        return "command unavailable"
    if adapter_id == "jvm-cli":
        ok, output = run_command([locator, "-version"])
    else:
        ok, output = run_command([locator, "--help"])
        if not ok:
            ok, output = run_command([locator, "--version"])
    status = "ready" if ok else "unavailable"
    detail = output or locator
    return f"{status}:{detail}"


def probe_python_module(locator: str) -> str:
    if not locator:
        return "module unavailable"
    available = importlib.util.find_spec(locator) is not None
    if not available:
        return "module unavailable"
    try:
        module = importlib.import_module(locator)
        version = getattr(module, "__version__", "")
    except Exception as exc:  # pragma: no cover - defensive reporting
        return f"module import failed:{exc}"
    suffix = f" {version}" if isinstance(version, str) and version else ""
    return f"module ready:{locator}{suffix}"


def probe_gpu(bundle: dict[str, object]) -> str:
    runtime_mode = string_field(bundle, "runtimeMode")
    runtime_lane = string_field(bundle, "runtimeLane")
    if runtime_mode != "linux-cuda" and "gpu" not in runtime_lane:
        return "cpu-or-host-lane"
    ok, output = run_command(["nvidia-smi", "-L"])
    if ok:
        first_gpu = output.splitlines()[0] if output else "gpu-visible"
        return f"gpu-visible:{first_gpu}"
    return f"gpu-unavailable:{output}"


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


def probe_adapter(bundle: dict[str, object], adapter_id: str) -> str:
    adapter_type = string_field(bundle, "engineAdapterType")
    adapter_locator = string_field(bundle, "engineAdapterLocator")
    if adapter_type == "external-command":
        return probe_external_command(adapter_locator, adapter_id)
    if adapter_type == "python-module":
        return probe_python_module(adapter_locator)
    return "adapter probe unavailable"


def render_output(bundle: dict[str, object], adapter_id: str, input_text: str) -> str:
    family = string_field(bundle, "family")
    selected_engine = string_field(bundle, "selectedEngine")
    reference_model = string_field(bundle, "referenceModel")
    runtime_mode = string_field(bundle, "runtimeMode")
    artifact_mode = string_field(bundle, "artifactAcquisitionMode")
    fetch_status = string_field(bundle, "sourceArtifactFetchStatus")
    source_uri = string_field(bundle, "sourceArtifactUri")
    source_manifest = load_source_manifest(bundle)
    resolved_url = string_field(bundle, "sourceArtifactResolvedUrl") or (
        source_manifest.get("resolvedSourceUrl") if isinstance(source_manifest.get("resolvedSourceUrl"), str) else ""
    )
    content_type = string_field(bundle, "sourceArtifactContentType") or (
        source_manifest.get("contentType") if isinstance(source_manifest.get("contentType"), str) else ""
    )
    adapter_status = probe_adapter(bundle, adapter_id)
    gpu_status = probe_gpu(bundle)
    platform_id = f"{platform.system().lower()}-{platform.machine().lower()}"
    verb = {
        "llm": "answered",
        "speech": "transcribed",
        "audio": "processed",
        "music": "transcribed",
        "image": "rendered",
        "video": "rendered",
    }.get(family, "executed")

    return (
        f"{selected_engine} {verb} {reference_model} on {runtime_mode} ({platform_id}) "
        f"via {adapter_id or string_field(bundle, 'engineAdapterId') or 'engine-probe'}; "
        f"adapter={adapter_status}; gpu={gpu_status}; "
        f"artifact={artifact_mode}/{fetch_status}/{content_type or 'unknown'}; "
        f"source={resolved_url or source_uri or 'unresolved'}; "
        f"input={input_text}"
    )


def main() -> int:
    args = parse_args()
    try:
        bundle = load_bundle(pathlib.Path(args.artifact_bundle).resolve())
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        print(f"engine-probe: {exc}", file=sys.stderr)
        return 1

    if string_field(bundle, "artifactAcquisitionMode") == "":
        print("engine-probe: artifact bundle is missing artifact acquisition metadata", file=sys.stderr)
        return 1

    print(render_output(bundle, args.adapter_id, args.input_text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
