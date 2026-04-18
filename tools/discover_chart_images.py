#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path

import yaml


WORKLOAD_KINDS = {
    "CronJob",
    "DaemonSet",
    "Deployment",
    "Job",
    "Pod",
    "ReplicaSet",
    "ReplicationController",
    "StatefulSet",
}


def fail(message: str) -> None:
    print(f"discover-chart-images: {message}", file=sys.stderr)
    raise SystemExit(1)


def pod_spec_for(document: dict) -> dict | None:
    kind = document.get("kind")
    spec = document.get("spec") or {}
    if kind == "Pod":
        return spec
    if kind == "CronJob":
        return (((spec.get("jobTemplate") or {}).get("spec") or {}).get("template") or {}).get("spec")
    return ((spec.get("template") or {}).get("spec") or {}) if kind in WORKLOAD_KINDS else None


def image_refs(pod_spec: dict | None) -> list[str]:
    if not isinstance(pod_spec, dict):
        return []
    refs: list[str] = []
    for container_key in ("initContainers", "containers"):
        for container in pod_spec.get(container_key) or []:
            if not isinstance(container, dict):
                continue
            image = container.get("image")
            if isinstance(image, str) and image:
                refs.append(image)
    return refs


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: discover_chart_images.py <rendered-chart.yaml>")

    rendered_chart_path = Path(sys.argv[1])
    rendered_chart = rendered_chart_path.read_text(encoding="utf-8").replace("\t", "  ")
    documents = list(yaml.safe_load_all(rendered_chart))
    discovered = sorted({image for document in documents if isinstance(document, dict) for image in image_refs(pod_spec_for(document))})
    if not discovered:
        fail("rendered chart did not contain any workload image references")
    for image in discovered:
        print(image)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
