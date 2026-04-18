#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
import tempfile
import os
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
HELM_HOME_ROOT = REPO_ROOT / ".data" / "helm"
HELM_REPOSITORIES = [
    ("goharbor", "https://helm.goharbor.io"),
    ("apachepulsar", "https://pulsar.apache.org/charts"),
    ("bitnami", "https://charts.bitnami.com/bitnami"),
    ("ingress-nginx", "https://kubernetes.github.io/ingress-nginx"),
]
HELM_DEPENDENCY_ARCHIVES = [
    REPO_ROOT / "chart" / "charts" / "harbor-1.18.3.tgz",
    REPO_ROOT / "chart" / "charts" / "pulsar-4.5.0.tgz",
    REPO_ROOT / "chart" / "charts" / "minio-17.0.21.tgz",
    REPO_ROOT / "chart" / "charts" / "ingress-nginx-4.15.1.tgz",
]


def fail(message: str) -> None:
    print(f"helm-chart-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command: list[str], *, capture_output: bool = False) -> str:
    helm_env = {
        **dict(os.environ),
        "HELM_CONFIG_HOME": str(HELM_HOME_ROOT / "config"),
        "HELM_CACHE_HOME": str(HELM_HOME_ROOT / "cache"),
        "HELM_DATA_HOME": str(HELM_HOME_ROOT / "data"),
    }
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=capture_output,
        env=helm_env,
    )
    if result.returncode != 0:
        output = (result.stdout or "") + (result.stderr or "")
        fail(f"command failed: {' '.join(command)}\n{output}".rstrip())
    return result.stdout if capture_output else ""


def main() -> int:
    for path in (HELM_HOME_ROOT / "config", HELM_HOME_ROOT / "cache", HELM_HOME_ROOT / "data"):
        path.mkdir(parents=True, exist_ok=True)
    if not all(path.exists() for path in HELM_DEPENDENCY_ARCHIVES):
        for repo_name, repo_url in HELM_REPOSITORIES:
            run(["helm", "repo", "add", "--force-update", repo_name, repo_url])
        run(["helm", "dependency", "build", "chart"])
    run(["helm", "lint", "chart"])
    rendered_chart = run(
        ["helm", "template", "infernix", "chart", "--namespace", "platform"],
        capture_output=True,
    )

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".yaml",
        prefix="infernix-chart-",
        encoding="utf-8",
    ) as rendered_file:
        rendered_file.write(rendered_chart)
        rendered_file.flush()
        run(["python3", str(REPO_ROOT / "tools" / "discover_chart_claims.py"), rendered_file.name])

    print("helm-chart-check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
