#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("overlay")
    return parser.parse_args()


def render_ref(image: dict[str, str]) -> str:
    repository = image.get("repository", "").strip()
    tag = image.get("tag", "").strip()
    if not repository or not tag:
        return ""
    registry = image.get("registry", "").strip()
    if registry:
        return f"{registry}/{repository}:{tag}"
    return f"{repository}:{tag}"


def main() -> int:
    args = parse_args()
    overlay = yaml.safe_load(Path(args.overlay).read_text(encoding="utf-8")) or {}
    image_refs: list[str] = []

    for section, path in (
        ("service", ("image",)),
        ("web", ("image",)),
        ("minio", ("image",)),
        ("minio", ("defaultInitContainers", "volumePermissions", "image")),
        ("minio", ("console", "image")),
        ("minio", ("clientImage",)),
    ):
        current = overlay.get(section) or {}
        for key in path:
            if not isinstance(current, dict):
                current = {}
                break
            current = current.get(key) or {}
        if isinstance(current, dict):
            image_ref = render_ref(current)
            if image_ref:
                image_refs.append(image_ref)

    pulsar_repository = ((overlay.get("pulsar") or {}).get("defaultPulsarImageRepository") or "").strip()
    pulsar_tag = ((overlay.get("pulsar") or {}).get("defaultPulsarImageTag") or "").strip()
    if pulsar_repository and pulsar_tag:
        image_refs.append(f"{pulsar_repository}:{pulsar_tag}")

    for image_ref in dict.fromkeys(image_refs):
        print(image_ref)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
