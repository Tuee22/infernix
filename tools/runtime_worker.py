#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shlex
import subprocess
import sys


REQUIRED_FIELDS = {
    "artifactKind": str,
    "schemaVersion": int,
    "runtimeMode": str,
    "matrixRowId": str,
    "modelId": str,
    "displayName": str,
    "family": str,
    "artifactType": str,
    "referenceModel": str,
    "selectedEngine": str,
    "runtimeLane": str,
    "sourceDownloadUrl": str,
    "workerProfile": str,
}


def load_bundle(path: pathlib.Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("artifact bundle must be a JSON object")
    for field_name, field_type in REQUIRED_FIELDS.items():
        value = payload.get(field_name)
        if not isinstance(value, field_type) or value == "":
            raise ValueError(f"artifact bundle has invalid {field_name}")
    if payload["artifactKind"] != "infernix-runtime-bundle":
        raise ValueError("artifact bundle has unsupported artifactKind")
    return payload


def infer_engine_adapter_id(selected_engine: str) -> str:
    normalized = selected_engine.lower()
    if "llama.cpp" in normalized:
        return "llama-cpp-cli"
    if "whisper.cpp" in normalized:
        return "whisper-cpp-cli"
    if "jvm" in normalized:
        return "jvm-cli"
    if "ctranslate2" in normalized:
        return "ctranslate2-python"
    if "onnx runtime" in normalized:
        return "onnxruntime-python"
    if "vllm" in normalized:
        return "vllm-python"
    if "mlx" in normalized:
        return "mlx-python"
    if "diffusers" in normalized or "comfyui" in normalized:
        return "diffusers-python"
    if "tensorflow" in normalized:
        return "tensorflow-python"
    if "core ml" in normalized:
        return "coreml-python"
    if "jax" in normalized:
        return "jax-python"
    if "pytorch" in normalized or "transformers" in normalized:
        return "pytorch-python"
    raise RuntimeError(f"unsupported selected engine mapping: {selected_engine}")


def adapter_id_for(bundle: dict[str, object]) -> str:
    configured = bundle.get("engineAdapterId")
    if isinstance(configured, str) and configured:
        return configured
    return infer_engine_adapter_id(str(bundle["selectedEngine"]))


def adapter_env_var_name(adapter_id: str) -> str:
    normalized = []
    for character in adapter_id.upper():
        if character.isalnum():
            normalized.append(character)
        else:
            normalized.append("_")
    return "INFERNIX_ENGINE_COMMAND_" + "".join(normalized)


def parse_command_prefix(raw_value: str) -> list[str]:
    command_prefix = shlex.split(raw_value)
    if not command_prefix:
        raise ValueError("command prefix must not be empty")
    return command_prefix


def resolve_command_prefix(bundle: dict[str, object]) -> tuple[list[str], str]:
    adapter_id = adapter_id_for(bundle)
    adapter_override = os.environ.get(adapter_env_var_name(adapter_id))
    if adapter_override:
        return parse_command_prefix(adapter_override), "adapter-specific command override"

    fixture_command = os.environ.get("INFERNIX_ENGINE_FIXTURE_COMMAND")
    if fixture_command:
        return parse_command_prefix(fixture_command), "engine fixture command"

    raise RuntimeError(
        "no engine command is configured for "
        f"{adapter_id}; set {adapter_env_var_name(adapter_id)} or INFERNIX_ENGINE_FIXTURE_COMMAND"
    )


def execute_engine_command(
    bundle_path: pathlib.Path,
    bundle: dict[str, object],
    request_id: str,
    input_text: str,
) -> str:
    command_prefix, resolution_source = resolve_command_prefix(bundle)
    command = command_prefix + [
        "--artifact-bundle",
        str(bundle_path),
        "--request-id",
        request_id,
        "--input-text",
        input_text,
        "--adapter-id",
        adapter_id_for(bundle),
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        error_output = (completed.stderr or completed.stdout).strip()
        raise RuntimeError(
            f"{resolution_source} exited with {completed.returncode}: {error_output or 'no output'}"
        )
    output_text = completed.stdout.strip()
    if not output_text:
        raise RuntimeError(f"{resolution_source} produced no output")
    return output_text


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-bundle", required=True)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--input-text")
    return parser.parse_args()


def run_once(bundle_path: pathlib.Path, bundle: dict[str, object], input_text: str | None) -> int:
    if input_text is None:
        print("runtime-worker: --input-text is required with --once", file=sys.stderr)
        return 1
    try:
        print(execute_engine_command(bundle_path, bundle, "once", input_text))
    except RuntimeError as exc:
        print(f"runtime-worker: {exc}", file=sys.stderr)
        return 1
    return 0


def run_stream(bundle_path: pathlib.Path, bundle: dict[str, object]) -> int:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError as exc:
            print(json.dumps({"error": f"invalid request payload: {exc}"}), flush=True)
            continue
        if not isinstance(payload, dict):
            print(json.dumps({"error": "request payload must be a JSON object"}), flush=True)
            continue
        request_id = payload.get("requestId")
        input_text = payload.get("inputText")
        if not isinstance(request_id, str) or not isinstance(input_text, str):
            print(json.dumps({"error": "requestId and inputText are required strings"}), flush=True)
            continue
        try:
            output_text = execute_engine_command(bundle_path, bundle, request_id, input_text)
            print(
                json.dumps(
                    {
                        "requestId": request_id,
                        "outputText": output_text,
                    }
                ),
                flush=True,
            )
        except RuntimeError as exc:
            print(
                json.dumps(
                    {
                        "requestId": request_id,
                        "error": str(exc),
                    }
                ),
                flush=True,
            )
    return 0


def main() -> int:
    args = parse_args()
    bundle_path = pathlib.Path(args.artifact_bundle).resolve()
    try:
        bundle = load_bundle(bundle_path)
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        print(f"runtime-worker: {exc}", file=sys.stderr)
        return 1

    if args.once:
        return run_once(bundle_path, bundle, args.input_text)
    return run_stream(bundle_path, bundle)


if __name__ == "__main__":
    raise SystemExit(main())
