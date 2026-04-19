#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from runtime_backend import RuntimeBackend


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-root", required=True)
    parser.add_argument("--runtime-mode", required=True)
    return parser.parse_args()


def load_model() -> dict[str, object]:
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        raise ValueError("model payload must be a JSON object")
    return payload


def main() -> int:
    args = parse_args()
    data_root = pathlib.Path(args.data_root).resolve()
    paths = {
        "data_root": data_root,
        "results_root": data_root / "runtime" / "results",
        "object_store_root": data_root / "object-store",
        "model_cache_root": data_root / "runtime" / "model-cache",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)

    try:
        model = load_model()
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"runtime-fixture-backend: {exc}", file=sys.stderr)
        return 1

    backend = RuntimeBackend(
        paths=paths,
        runtime_mode=args.runtime_mode,
        control_plane_context="host-native",
        daemon_location="fixture-helper",
        publication_state={"routes": []},
        allow_filesystem_fallback=True,
    )
    try:
        print(json.dumps(backend.materialize_cache(model), sort_keys=True))
    finally:
        backend.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
