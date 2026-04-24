#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml


HARBOR_PREFIXES = ("goharbor/", "docker.io/goharbor/", "quay.io/goharbor/")
REQUIRED_IMAGES = {
    "service": "infernix-service:local",
    "web": "infernix-web:local",
}
POSTGRES_OPERATOR_IMAGE = "docker.io/percona/percona-postgresql-operator:2.9.0"
POSTGRES_DATABASE_IMAGE = "docker.io/percona/percona-distribution-postgresql:18.3-1"
POSTGRES_PGBOUNCER_IMAGE = "docker.io/percona/percona-pgbouncer:1.25.1-1"
POSTGRES_PGBACKREST_IMAGE = "docker.io/percona/percona-pgbackrest:2.58.0-1"
DOCKER_PUSH_TIMEOUT_SECONDS = 900
DOCKER_PULL_VERIFY_TIMEOUT_SECONDS = 900
REGISTRY_READY_ATTEMPTS = 24
LOGIN_ATTEMPTS = 6
PULL_VERIFY_ATTEMPTS = 6


def fail(message: str) -> None:
    print(f"publish-chart-images: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
    )
    if result.returncode != 0:
        if capture:
            fail(f"command failed: {' '.join(command)}\n{result.stdout}{result.stderr}")
        fail(f"command failed: {' '.join(command)}")
    return result.stdout if capture else ""


def maybe_run(command: list[str]) -> bool:
    result = subprocess.run(command, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def registry_ready(harbor_api_host: str) -> bool:
    try:
        with urllib.request.urlopen(f"http://{harbor_api_host}/v2/", timeout=5) as response:
            return response.status in {200, 401, 403}
    except urllib.error.HTTPError as exc:
        return exc.code in {200, 401, 403}
    except Exception:
        return False


def wait_for_registry(harbor_api_host: str) -> None:
    for attempt in range(1, REGISTRY_READY_ATTEMPTS + 1):
        if registry_ready(harbor_api_host):
            return
        if attempt < REGISTRY_READY_ATTEMPTS:
            time.sleep(min(attempt, 5))
    fail(f"Harbor registry at {harbor_api_host} never became ready for docker login")


def harbor_api_headers(harbor_user: str, harbor_password: str) -> dict[str, str]:
    credentials = base64.b64encode(f"{harbor_user}:{harbor_password}".encode("utf-8")).decode("ascii")
    return {"Authorization": f"Basic {credentials}"}


def harbor_repository_path(target_repository: str, harbor_host: str, harbor_project: str) -> str:
    prefix = f"{harbor_host}/{harbor_project}/"
    if not target_repository.startswith(prefix):
        fail(f"target repository {target_repository} did not match Harbor prefix {prefix}")
    return target_repository[len(prefix) :]


def harbor_repository_url(harbor_api_host: str, harbor_project: str, repository_path: str) -> str:
    encoded_project = urllib.parse.quote(harbor_project, safe="")
    encoded_repository = urllib.parse.quote(urllib.parse.quote(repository_path, safe=""), safe="")
    return (
        f"http://{harbor_api_host}/api/v2.0/projects/{encoded_project}/repositories/"
        f"{encoded_repository}/artifacts?page_size=100&with_tag=true"
    )


def harbor_tag_exists(
    harbor_host: str,
    harbor_api_host: str,
    harbor_project: str,
    harbor_user: str,
    harbor_password: str,
    target_repository: str,
    target_tag: str,
) -> bool:
    repository_path = harbor_repository_path(target_repository, harbor_host, harbor_project)
    request = urllib.request.Request(harbor_repository_url(harbor_api_host, harbor_project, repository_path))
    for header, value in harbor_api_headers(harbor_user, harbor_password).items():
        request.add_header(header, value)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return False
        return False
    except Exception:
        return False

    if not isinstance(payload, list):
        return False
    for artifact in payload:
        for tag in artifact.get("tags") or []:
            if tag.get("name") == target_tag:
                return True
    return False


def login_harbor_with_retries(
    harbor_host: str, harbor_api_host: str, harbor_user: str, harbor_password: str
) -> None:
    wait_for_registry(harbor_api_host)
    last_failure = ""
    for attempt in range(1, LOGIN_ATTEMPTS + 1):
        result = subprocess.run(
            ["docker", "login", harbor_host, "--username", harbor_user, "--password-stdin"],
            check=False,
            input=harbor_password + "\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode == 0:
            return
        last_failure = f"{result.stdout}{result.stderr}".strip() or f"docker login exited with status {result.returncode}"
        if registry_ready(harbor_api_host) and attempt < LOGIN_ATTEMPTS:
            time.sleep(attempt * 2)
            continue
        if attempt < LOGIN_ATTEMPTS:
            wait_for_registry(harbor_api_host)
    fail(f"docker login failed for {harbor_host}\n{last_failure}")


def load_images(rendered_chart_path: Path) -> list[str]:
    rendered = rendered_chart_path.read_text(encoding="utf-8").replace("\t", "  ")
    documents = list(yaml.safe_load_all(rendered))
    images: set[str] = set()
    for document in documents:
        if not isinstance(document, dict):
            continue
        spec = pod_spec(document)
        if not isinstance(spec, dict):
            spec = None
        if isinstance(spec, dict):
            for key in ("initContainers", "containers"):
                for container in spec.get(key) or []:
                    if not isinstance(container, dict):
                        continue
                    image = container.get("image")
                    if isinstance(image, str) and image:
                        images.add(image)
        for image in custom_resource_images(document):
            images.add(image)
    if not images:
        fail("rendered chart did not contain any workload image references")
    return sorted(images)


def pod_spec(document: dict) -> dict | None:
    kind = document.get("kind")
    spec = document.get("spec") or {}
    if kind == "Pod":
        return spec
    if kind == "CronJob":
        return (((spec.get("jobTemplate") or {}).get("spec") or {}).get("template") or {}).get("spec")
    if kind in {
        "DaemonSet",
        "Deployment",
        "Job",
        "ReplicaSet",
        "ReplicationController",
        "StatefulSet",
    }:
        return ((spec.get("template") or {}).get("spec") or {})
    return None


def custom_resource_images(document: dict) -> list[str]:
    if document.get("kind") != "PerconaPGCluster":
        return []

    spec = document.get("spec") or {}
    images: list[str] = []
    for image in (
        spec.get("image"),
        ((spec.get("proxy") or {}).get("pgBouncer") or {}).get("image"),
        ((spec.get("backups") or {}).get("pgbackrest") or {}).get("image"),
    ):
        if isinstance(image, str) and image:
            images.append(image)
    return images


def is_harbor_image(image: str) -> bool:
    return image.startswith(HARBOR_PREFIXES)


def ensure_local_image(image: str) -> None:
    if maybe_run(["docker", "image", "inspect", image]):
        return
    run(["docker", "pull", image])


def normalize_repository_path(image: str) -> str:
    repository = image
    if "@" in repository:
        repository = repository.split("@", 1)[0]
    if ":" in repository and repository.rfind(":") > repository.rfind("/"):
        repository = repository.rsplit(":", 1)[0]
    parts = repository.split("/")
    if len(parts) > 1 and ("." in parts[0] or ":" in parts[0] or parts[0] == "localhost"):
        parts = parts[1:]
    return "/".join(parts)


def image_tag(image: str) -> str:
    if "@" in image:
        return image.split("@", 1)[1].replace(":", "-")
    if ":" in image and image.rfind(":") > image.rfind("/"):
        return image.rsplit(":", 1)[1]
    return "latest"


def content_address_tag(image: str) -> str:
    inspection = json.loads(run(["docker", "image", "inspect", image], capture=True))
    if not inspection:
        fail(f"image inspect returned no payload for {image}")
    record = inspection[0]
    for repo_digest in record.get("RepoDigests") or []:
        digest = repo_digest.split("@", 1)[1]
        if digest:
            return digest.replace(":", "-")
    image_id = record.get("Id")
    if not image_id:
        fail(f"image inspect did not include an image id for {image}")
    return image_id.replace(":", "-")


def target_image_ref(image: str, harbor_host: str, harbor_project: str) -> tuple[str, str]:
    repository_path = normalize_repository_path(image)
    digest_tag = content_address_tag(image)
    repository = f"{harbor_host}/{harbor_project}/{repository_path}"
    return repository, digest_tag


def publish_if_needed(
    source_image: str,
    target_repository: str,
    target_tag: str,
    harbor_host: str,
    harbor_api_host: str,
    harbor_project: str,
    harbor_user: str,
    harbor_password: str,
) -> None:
    target_ref = f"{target_repository}:{target_tag}"
    run(["docker", "tag", source_image, target_ref])
    if harbor_tag_exists(
        harbor_host, harbor_api_host, harbor_project, harbor_user, harbor_password, target_repository, target_tag
    ):
        verify_registry_pull(target_ref, harbor_api_host)
        return
    push_image_with_retries(target_ref, harbor_host, harbor_api_host, harbor_project, harbor_user, harbor_password)
    verify_registry_pull(target_ref, harbor_api_host)


def push_image_with_retries(
    target_ref: str,
    harbor_host: str,
    harbor_api_host: str,
    harbor_project: str,
    harbor_user: str,
    harbor_password: str,
    *,
    attempts: int = 4,
) -> None:
    last_failure = ""
    target_repository, _, target_tag = target_ref.rpartition(":")
    for attempt in range(1, attempts + 1):
        try:
            result = subprocess.run(
                ["docker", "push", target_ref],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=DOCKER_PUSH_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            if harbor_tag_exists(
                harbor_host, harbor_api_host, harbor_project, harbor_user, harbor_password, target_repository, target_tag
            ):
                return
            combined_output = f"{exc.stdout or ''}{exc.stderr or ''}".strip()
            last_failure = (
                f"docker push timed out after {DOCKER_PUSH_TIMEOUT_SECONDS} seconds"
                + (f"\n{combined_output}" if combined_output else "")
            )
        else:
            if result.returncode == 0:
                return
            if harbor_tag_exists(
                harbor_host, harbor_api_host, harbor_project, harbor_user, harbor_password, target_repository, target_tag
            ):
                return

            combined_output = f"{result.stdout}{result.stderr}".strip()
            last_failure = combined_output or f"docker push exited with status {result.returncode}"
        if attempt < attempts:
            retry_delay_seconds = attempt * 5
            print(
                (
                    "publish-chart-images: "
                    f"retrying docker push for {target_ref} after attempt {attempt}/{attempts} failed"
                ),
                file=sys.stderr,
            )
            time.sleep(retry_delay_seconds)

    fail(f"docker push failed for {target_ref}\n{last_failure}")


def verify_registry_pull(target_ref: str, harbor_api_host: str, *, attempts: int = PULL_VERIFY_ATTEMPTS) -> None:
    wait_for_registry(harbor_api_host)
    last_failure = ""
    for attempt in range(1, attempts + 1):
        try:
            result = subprocess.run(
                ["docker", "pull", target_ref],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=DOCKER_PULL_VERIFY_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            combined_output = f"{exc.stdout or ''}{exc.stderr or ''}".strip()
            last_failure = (
                f"docker pull timed out after {DOCKER_PULL_VERIFY_TIMEOUT_SECONDS} seconds"
                + (f"\n{combined_output}" if combined_output else "")
            )
        else:
            if result.returncode == 0:
                return
            combined_output = f"{result.stdout}{result.stderr}".strip()
            last_failure = combined_output or f"docker pull exited with status {result.returncode}"
        if attempt < attempts:
            if registry_ready(harbor_api_host):
                time.sleep(attempt * 2)
            else:
                wait_for_registry(harbor_api_host)

    fail(f"docker pull verification failed for {target_ref}\n{last_failure}")


def emit_overlay(published_images: dict[str, tuple[str, str]], output_path: Path) -> None:
    def require(image: str) -> tuple[str, str]:
        if image not in published_images:
            fail(f"required image {image} was not published")
        return published_images[image]

    service_repository, service_tag = require("infernix-service:local")
    web_repository, web_tag = require("infernix-web:local")

    minio_image = next((image for image in published_images if image.endswith("/minio:2025.7.23-debian-12-r3")), None)
    minio_shell_image = next((image for image in published_images if image.endswith("/os-shell:12-debian-12-r50")), None)
    minio_console_image = next((image for image in published_images if image.endswith("/minio-object-browser:2.0.2-debian-12-r3")), None)
    pulsar_image = next((image for image in published_images if image.endswith("/pulsar-all:4.0.9")), None)
    postgres_operator_image = next((image for image in published_images if image == POSTGRES_OPERATOR_IMAGE), None)
    postgres_database_image = next((image for image in published_images if image == POSTGRES_DATABASE_IMAGE), None)
    postgres_pgbouncer_image = next((image for image in published_images if image == POSTGRES_PGBOUNCER_IMAGE), None)
    postgres_pgbackrest_image = next((image for image in published_images if image == POSTGRES_PGBACKREST_IMAGE), None)

    if not all(
        [
            minio_image,
            minio_shell_image,
            minio_console_image,
            pulsar_image,
            postgres_operator_image,
            postgres_database_image,
            postgres_pgbouncer_image,
            postgres_pgbackrest_image,
        ]
    ):
        fail("did not discover every non-Harbor third-party image required for the final Harbor-backed rollout")

    minio_repository, minio_tag = require(minio_image)
    minio_shell_repository, minio_shell_tag = require(minio_shell_image)
    minio_console_repository, minio_console_tag = require(minio_console_image)
    pulsar_repository, pulsar_tag = require(pulsar_image)
    postgres_operator_repository, postgres_operator_tag = require(postgres_operator_image)
    postgres_database_repository, postgres_database_tag = require(postgres_database_image)
    postgres_pgbouncer_repository, postgres_pgbouncer_tag = require(postgres_pgbouncer_image)
    postgres_pgbackrest_repository, postgres_pgbackrest_tag = require(postgres_pgbackrest_image)

    overlay = {
        "service": {
            "image": {
                "repository": service_repository,
                "tag": service_tag,
                "pullPolicy": "IfNotPresent",
            }
        },
        "web": {
            "image": {
                "repository": web_repository,
                "tag": web_tag,
                "pullPolicy": "IfNotPresent",
            }
        },
        "minio": {
            "image": split_registry_repository(minio_repository, minio_tag),
            "defaultInitContainers": {
                "volumePermissions": {
                    "image": split_registry_repository(minio_shell_repository, minio_shell_tag)
                }
            },
            "console": {
                "image": split_registry_repository(minio_console_repository, minio_console_tag)
            },
        },
        "pulsar": {
            "defaultPulsarImageRepository": pulsar_repository,
            "defaultPulsarImageTag": pulsar_tag,
            "defaultPullPolicy": "IfNotPresent",
        },
        "postgresOperator": {
            "image": f"{postgres_operator_repository}:{postgres_operator_tag}",
            "imagePullPolicy": "IfNotPresent",
        },
        "harborpg": {
            "image": f"{postgres_database_repository}:{postgres_database_tag}",
            "imagePullPolicy": "IfNotPresent",
            "backups": {
                "pgbackrest": {
                    "image": f"{postgres_pgbackrest_repository}:{postgres_pgbackrest_tag}"
                }
            },
            "proxy": {
                "pgBouncer": {
                    "image": f"{postgres_pgbouncer_repository}:{postgres_pgbouncer_tag}"
                }
            },
        },
    }
    minio_client_image = next((image for image in published_images if image.endswith("/minio-client:2025.7.21-debian-12-r2")), None)
    if minio_client_image is not None:
        minio_client_repository, minio_client_tag = require(minio_client_image)
        overlay["minio"]["clientImage"] = split_registry_repository(minio_client_repository, minio_client_tag)
    output_path.write_text(yaml.safe_dump(overlay, sort_keys=False), encoding="utf-8")


def split_registry_repository(repository: str, tag: str) -> dict[str, str]:
    registry, _, remainder = repository.partition("/")
    return {
        "registry": registry,
        "repository": remainder,
        "tag": tag,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("rendered_chart")
    parser.add_argument("output")
    parser.add_argument("--harbor-host", default="localhost:30002")
    parser.add_argument("--harbor-api-host")
    parser.add_argument("--harbor-project", default="library")
    parser.add_argument("--harbor-user", default="admin")
    parser.add_argument("--harbor-password", default="Harbor12345")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rendered_chart_path = Path(args.rendered_chart)
    output_path = Path(args.output)
    harbor_api_host = args.harbor_api_host or args.harbor_host

    images = load_images(rendered_chart_path)
    publishable_images = [image for image in images if not is_harbor_image(image)]
    for required_image in REQUIRED_IMAGES.values():
        if required_image not in publishable_images:
            fail(f"required repo-owned image {required_image} was not present in the rendered chart")

    login_harbor_with_retries(args.harbor_host, harbor_api_host, args.harbor_user, args.harbor_password)

    published_images: dict[str, tuple[str, str]] = {}
    for image in publishable_images:
        ensure_local_image(image)
        target_repository, target_tag = target_image_ref(image, args.harbor_host, args.harbor_project)
        publish_if_needed(
            image,
            target_repository,
            target_tag,
            args.harbor_host,
            harbor_api_host,
            args.harbor_project,
            args.harbor_user,
            args.harbor_password,
        )
        published_images[image] = (target_repository, target_tag)

    emit_overlay(published_images, output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
