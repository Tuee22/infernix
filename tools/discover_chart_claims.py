#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path

import yaml


def fail(message: str) -> None:
    print(f"discover-chart-claims: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_workload_name(name: str, release: str) -> str:
    prefix = f"{release}-"
    workload = name.removeprefix(prefix)
    double_prefix = f"{release}-pulsar-"
    if workload.startswith(double_prefix):
        workload = "pulsar-" + workload.removeprefix(double_prefix)
    return workload


def normalize_claim_name(template_name: str, workload: str) -> str:
    if template_name.startswith(f"{workload}-"):
        return template_name.removeprefix(f"{workload}-")
    last_segment = template_name.rsplit("-", 1)[-1]
    return last_segment or template_name


def derive_release(metadata: dict) -> str:
    labels = metadata.get("labels") or {}
    return (
        labels.get("infernix.io/release")
        or labels.get("release")
        or labels.get("app.kubernetes.io/instance")
        or metadata.get("name", "").split("-", 1)[0]
    )


def parse_explicit_claim(metadata: dict) -> tuple[str, int, str]:
    labels = metadata.get("labels") or {}
    if all(key in labels for key in ("infernix.io/workload", "infernix.io/ordinal", "infernix.io/claim")):
        return (
            str(labels["infernix.io/workload"]),
            int(str(labels["infernix.io/ordinal"])),
            str(labels["infernix.io/claim"]),
        )

    release = derive_release(metadata)
    name = str(metadata.get("name", ""))
    parts = name.split("-")
    if len(parts) >= 4 and parts[0] == release and parts[-2].isdigit():
        workload = "-".join(parts[1:-2])
        ordinal = int(parts[-2])
        claim = parts[-1]
        return workload, ordinal, claim

    workload = normalize_workload_name(name, release)
    return workload, 0, "data"


def explicit_claim_rows(document: dict) -> list[tuple[str, str, str, int, str, str, str]]:
    metadata = document.get("metadata") or {}
    spec = document.get("spec") or {}
    storage_class = spec.get("storageClassName")
    if storage_class != "infernix-manual":
        fail(f"PersistentVolumeClaim uses unsupported storageClassName {storage_class!r}")

    release = derive_release(metadata)
    workload, ordinal, claim = parse_explicit_claim(metadata)
    size = (((spec.get("resources") or {}).get("requests") or {}).get("storage")) or "5Gi"
    return [
        (
            str(metadata.get("namespace") or "default"),
            release,
            workload,
            ordinal,
            claim,
            str(metadata.get("name")),
            str(size),
        )
    ]


def statefulset_claim_rows(document: dict) -> list[tuple[str, str, str, int, str, str, str]]:
    metadata = document.get("metadata") or {}
    spec = document.get("spec") or {}
    namespace = str(metadata.get("namespace") or "default")
    release = derive_release(metadata)
    statefulset_name = str(metadata.get("name"))
    workload = normalize_workload_name(statefulset_name, release)
    replicas = int(spec.get("replicas") or 1)
    rows: list[tuple[str, str, str, int, str, str, str]] = []

    for template in spec.get("volumeClaimTemplates") or []:
        template_metadata = template.get("metadata") or {}
        template_spec = template.get("spec") or {}
        storage_class = template_spec.get("storageClassName")
        if storage_class != "infernix-manual":
            fail(
                "StatefulSet volumeClaimTemplate "
                f"{statefulset_name}/{template_metadata.get('name')} uses unsupported storageClassName {storage_class!r}"
            )
        template_name = str(template_metadata.get("name"))
        claim = normalize_claim_name(template_name, workload)
        size = (((template_spec.get("resources") or {}).get("requests") or {}).get("storage")) or "5Gi"
        for ordinal in range(replicas):
            rows.append(
                (
                    namespace,
                    release,
                    workload,
                    ordinal,
                    claim,
                    f"{template_name}-{statefulset_name}-{ordinal}",
                    str(size),
                )
            )
    return rows


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: discover_chart_claims.py <rendered-chart.yaml>")

    rendered_chart_path = Path(sys.argv[1])
    rendered_chart = rendered_chart_path.read_text(encoding="utf-8").replace("\t", "  ")
    documents = list(yaml.safe_load_all(rendered_chart))
    discovered: list[tuple[str, str, str, int, str, str, str]] = []

    for document in documents:
        if not isinstance(document, dict):
            continue
        kind = document.get("kind")
        if kind == "PersistentVolumeClaim":
            discovered.extend(explicit_claim_rows(document))
        elif kind == "StatefulSet":
            discovered.extend(statefulset_claim_rows(document))

    if not discovered:
        fail("rendered chart did not contain any persistent claims")

    ordered = sorted(discovered, key=lambda row: (row[0], row[1], row[2], row[3], row[4], row[5]))
    for namespace, release, workload, ordinal, claim, pvc_name, size in ordered:
        print("\t".join([namespace, release, workload, str(ordinal), claim, pvc_name, size]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
