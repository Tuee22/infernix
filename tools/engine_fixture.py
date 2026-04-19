#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
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


def render_fixture_output(bundle: dict[str, object], adapter_id: str, input_text: str) -> str:
    engine = string_field(bundle, "selectedEngine")
    family = string_field(bundle, "family")
    reference_model = string_field(bundle, "referenceModel")
    runtime_mode = string_field(bundle, "runtimeMode")
    acquisition_mode = string_field(bundle, "artifactAcquisitionMode")
    fetch_status = string_field(bundle, "sourceArtifactFetchStatus")
    adapter_summary = f"{adapter_id or 'fixture-engine'}/{acquisition_mode}/{fetch_status}"

    if family == "llm":
        return f"{engine} fixture ({adapter_summary}) answered on {runtime_mode} for {reference_model}: {input_text}"
    if family == "speech":
        return f"{engine} fixture ({adapter_summary}) transcribed {reference_model}: {input_text}"
    if family == "audio":
        return f"{engine} fixture ({adapter_summary}) processed audio workload {reference_model}: {input_text}"
    if family == "music":
        return f"{engine} fixture ({adapter_summary}) transcribed music workload {reference_model}: {input_text}"
    if family == "image":
        return f"{engine} fixture ({adapter_summary}) rendered image prompt for {reference_model}: {input_text}"
    if family == "video":
        return f"{engine} fixture ({adapter_summary}) rendered video prompt for {reference_model}: {input_text}"
    return f"{engine} fixture ({adapter_summary}) executed {reference_model}: {input_text}"


def string_field(bundle: dict[str, object], field_name: str) -> str:
    value = bundle.get(field_name)
    return value if isinstance(value, str) else ""


def main() -> int:
    args = parse_args()
    try:
        bundle = load_bundle(pathlib.Path(args.artifact_bundle).resolve())
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        print(f"engine-fixture: {exc}", file=sys.stderr)
        return 1

    print(render_fixture_output(bundle, args.adapter_id, args.input_text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
