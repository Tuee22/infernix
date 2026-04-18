#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
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


def load_bundle(path: pathlib.Path) -> dict:
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


def render_output(bundle: dict, input_text: str) -> str:
    engine = bundle["selectedEngine"]
    engine_adapter = bundle.get("engineAdapterId", infer_engine_adapter_id(engine))
    acquisition_mode = bundle.get("artifactAcquisitionMode", "unknown")
    fetch_status = bundle.get("sourceArtifactFetchStatus", "unfetched")
    family = bundle["family"]
    reference_model = bundle["referenceModel"]
    artifact_type = bundle["artifactType"]
    runtime_mode = bundle["runtimeMode"]
    adapter_summary = f"{engine_adapter}/{acquisition_mode}/{fetch_status}"

    if family == "llm":
        return f"{engine} worker ({adapter_summary}) for {reference_model} responded on {runtime_mode}: {input_text}"
    if family == "speech":
        return f"{engine} worker ({adapter_summary}) transcribed {reference_model} ({artifact_type}) input: {input_text}"
    if family == "audio":
        return f"{engine} worker ({adapter_summary}) processed audio pipeline {reference_model}: {input_text}"
    if family == "music":
        return f"{engine} worker ({adapter_summary}) transcribed music workload {reference_model}: {input_text}"
    if family == "image":
        return f"{engine} worker ({adapter_summary}) rendered image prompt for {reference_model}: {input_text}"
    if family == "video":
        return f"{engine} worker ({adapter_summary}) rendered video prompt for {reference_model}: {input_text}"
    return f"{engine} worker ({adapter_summary}) executed tool workload {reference_model}: {input_text}"


def infer_engine_adapter_id(selected_engine: str) -> str:
    normalized = selected_engine.lower()
    if "llama.cpp" in normalized:
        return "llama-cpp-cli"
    if "whisper.cpp" in normalized:
        return "whisper-cpp-cli"
    if "ctranslate2" in normalized:
        return "ctranslate2-python"
    if "vllm" in normalized:
        return "vllm-python"
    if "mlx" in normalized:
        return "mlx-python"
    if "tensorflow" in normalized:
        return "tensorflow-python"
    if "core ml" in normalized:
        return "coreml-python"
    if "jax" in normalized:
        return "jax-python"
    if "pytorch" in normalized or "transformers" in normalized:
        return "pytorch-python"
    return "fallback-template"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-bundle", required=True)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--input-text")
    return parser.parse_args()


def run_once(bundle: dict, input_text: str | None) -> int:
    if input_text is None:
        print("runtime-worker: --input-text is required with --once", file=sys.stderr)
        return 1
    print(render_output(bundle, input_text))
    return 0


def run_stream(bundle: dict) -> int:
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
        print(
            json.dumps(
                {
                    "requestId": request_id,
                    "outputText": render_output(bundle, input_text),
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
        return run_once(bundle, args.input_text)
    return run_stream(bundle)


if __name__ == "__main__":
    raise SystemExit(main())
