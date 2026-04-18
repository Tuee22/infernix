#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
REQUIRED_PROTO_FILES = {
    Path("proto/infernix/runtime/inference.proto"): {
        "package": "package infernix.runtime;",
        "symbols": [
            "message RequestField",
            "message CatalogEntry",
            "message GeneratedCatalog",
            "message InferenceRequest",
            "message ResultPayload",
            "message InferenceResult",
            "message ErrorResponse",
        ],
    },
    Path("proto/infernix/manifest/runtime_manifest.proto"): {
        "package": "package infernix.manifest;",
        "symbols": [
            "message ModelMaterialization",
            "message RuntimeCacheEntry",
            "message RuntimeManifest",
        ],
    },
    Path("proto/infernix/api/inference_service.proto"): {
        "package": "package infernix.api;",
        "symbols": [
            "message ListCatalogRequest",
            "message ListCatalogResponse",
            "message GetModelRequest",
            "message SubmitInferenceRequest",
            "message GetInferenceResultRequest",
            "service InferenceService",
        ],
    },
}


def fail(message: str) -> None:
    print(f"proto-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    syntax_re = re.compile(r'^syntax = "proto3";$', re.MULTILINE)

    for relative_path, expectations in REQUIRED_PROTO_FILES.items():
        full_path = REPO_ROOT / relative_path
        if not full_path.exists():
            fail(f"missing required proto file: {relative_path}")
        contents = full_path.read_text(encoding="utf-8")
        if not syntax_re.search(contents):
            fail(f"{relative_path} must declare syntax = \"proto3\";")
        if expectations["package"] not in contents:
            fail(f"{relative_path} is missing package declaration {expectations['package']}")
        for symbol in expectations["symbols"]:
            if symbol not in contents:
                fail(f"{relative_path} is missing required symbol: {symbol}")

    print("proto-check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
