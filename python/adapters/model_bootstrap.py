from __future__ import annotations

import argparse
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

READY_SENTINEL_NAME = ".ready"

# Open-Unmix `umxhq` is published as four first-party per-target state dicts on
# Zenodo (record 3370489), not a single file or a HuggingFace repo. The catalog
# download URL is that record; the bootstrap stages each target as
# `<target>.pth` so the adapter can rebuild the umxhq architecture and load them.
_OPEN_UNMIX_UMXHQ_RECORD = "zenodo.org/records/3370489"
_OPEN_UNMIX_UMXHQ_TARGETS = {
    "vocals": "https://zenodo.org/records/3370489/files/vocals-b62c91ce.pth",
    "drums": "https://zenodo.org/records/3370489/files/drums-9619578f.pth",
    "bass": "https://zenodo.org/records/3370489/files/bass-8d85a5bd.pth",
    "other": "https://zenodo.org/records/3370489/files/other-b52fbbf7.pth",
}


def run_model_bootstrap_from_argv() -> int:
    parser = argparse.ArgumentParser(
        prog="bootstrap-model-snapshot",
        description=(
            "Populate an infernix-models MinIO prefix from an upstream model URL."
        ),
    )
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--minio-endpoint", required=True)
    parser.add_argument("--minio-access-key", required=True)
    parser.add_argument("--minio-secret-key", required=True)
    parser.add_argument("--minio-region", required=True)
    parser.add_argument("--models-bucket", required=True)
    args = parser.parse_args()

    client = _s3_client(
        endpoint=args.minio_endpoint,
        access_key=args.minio_access_key,
        secret_key=args.minio_secret_key,
        region=args.minio_region,
    )
    if _sentinel_exists(client, args.models_bucket, args.model_id):
        _write_ready_sentinel(client, args.models_bucket, args.model_id)
        return 0

    repo_id = _hugging_face_repo_id(args.download_url)
    with tempfile.TemporaryDirectory(prefix="infernix-model-bootstrap-") as temp_root:
        if _is_open_unmix_umxhq(args.download_url):
            snapshot_root = Path(temp_root) / "snapshot"
            _download_open_unmix_umxhq(snapshot_root)
            _upload_directory(client, args.models_bucket, args.model_id, snapshot_root)
        elif repo_id is None:
            payload_path = Path(temp_root) / "payload"
            _download_single_payload(args.download_url, payload_path)
            _upload_file(
                client, args.models_bucket, args.model_id, payload_path, "payload"
            )
        else:
            snapshot_root = Path(temp_root) / "snapshot"
            _download_hugging_face_snapshot(repo_id, snapshot_root)
            _upload_directory(client, args.models_bucket, args.model_id, snapshot_root)

    _write_ready_sentinel(client, args.models_bucket, args.model_id)
    return 0


def _s3_client(*, endpoint: str, access_key: str, secret_key: str, region: str) -> Any:
    import boto3
    from botocore.client import Config

    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name=region,
        config=Config(s3={"addressing_style": "path"}, signature_version="s3v4"),
    )


def _sentinel_exists(client: Any, bucket: str, model_id: str) -> bool:
    try:
        client.head_object(Bucket=bucket, Key=f"{model_id}/{READY_SENTINEL_NAME}")
        return True
    except Exception:
        return False


def _write_ready_sentinel(client: Any, bucket: str, model_id: str) -> None:
    client.put_object(
        Bucket=bucket,
        Key=f"{model_id}/{READY_SENTINEL_NAME}",
        Body=b"ready\n",
        ContentType="text/plain; charset=utf-8",
    )


def _hugging_face_repo_id(download_url: str) -> str | None:
    parsed = urllib.parse.urlparse(download_url)
    if parsed.scheme not in {"http", "https"}:
        return None
    if parsed.netloc.lower() != "huggingface.co":
        return None
    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 2:
        return None
    if "resolve" in parts or "blob" in parts:
        return None
    return "/".join(parts[:2])


def _download_hugging_face_snapshot(repo_id: str, destination: Path) -> None:
    import time

    from huggingface_hub import snapshot_download
    from huggingface_hub.errors import HfHubHTTPError, LocalEntryNotFoundError

    allow_patterns = _snapshot_allow_patterns(repo_id)
    ignore_patterns = [
        ".gitattributes",
        "*.md",
        "*.png",
        "*.jpg",
        "*.jpeg",
        "*.gif",
        "*.h5",
        "*.msgpack",
        "*.onnx",
        "*.onnx_data",
        "*.ot",
        "*.tflite",
    ]
    # The Hub metadata/API surface is rate-limited per source IP; under a busy
    # cohort run it intermittently returns HTTP 429, which surfaces here as
    # LocalEntryNotFoundError / HfHubHTTPError even when the CDN file path is
    # healthy. snapshot_download resumes partial downloads, so retry with
    # exponential backoff until a non-throttled window lands rather than failing
    # the whole model bootstrap on a transient 429.
    last_error: Exception | None = None
    for attempt in range(10):
        try:
            download_options: dict[str, Any] = {
                "repo_id": repo_id,
                "revision": "main",
                "local_dir": str(destination),
                "ignore_patterns": ignore_patterns,
            }
            if allow_patterns is not None:
                download_options["allow_patterns"] = allow_patterns
            snapshot_download(
                **download_options,
            )
            return
        except (LocalEntryNotFoundError, HfHubHTTPError, OSError) as error:
            last_error = error
            time.sleep(min(60.0, 5.0 * (2.0**attempt)))
    if last_error is not None:
        raise last_error


def _snapshot_allow_patterns(repo_id: str) -> list[str] | None:
    normalized_repo_id = repo_id.lower()
    if normalized_repo_id == "stabilityai/sdxl-turbo":
        return [
            "model_index.json",
            "scheduler/*",
            "text_encoder/config.json",
            "text_encoder/model.fp16.safetensors",
            "text_encoder_2/config.json",
            "text_encoder_2/model.fp16.safetensors",
            "tokenizer/*",
            "tokenizer_2/*",
            "unet/config.json",
            "unet/diffusion_pytorch_model.fp16.safetensors",
            "vae/config.json",
            "vae/diffusion_pytorch_model.fp16.safetensors",
        ]
    return None


def _download_single_payload(download_url: str, destination: Path) -> None:
    with urllib.request.urlopen(download_url) as response:
        content_type = response.headers.get_content_type()
        first_chunk = response.read(1024 * 1024)
        if "html" in content_type or _looks_like_html(first_chunk):
            raise RuntimeError(
                f"refusing to stage non-weight content from {download_url}: "
                "the response is an HTML page (Content-Type "
                f"{content_type}), not a single-file model weight. The download "
                "URL likely points at a repository landing page."
            )
        with destination.open("wb") as handle:
            handle.write(first_chunk)
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                handle.write(chunk)


def _looks_like_html(data: bytes) -> bool:
    head = data[:512].lstrip().lower()
    return head.startswith((b"<!doctype", b"<html", b"<head", b"<?xml"))


def _is_open_unmix_umxhq(download_url: str) -> bool:
    return _OPEN_UNMIX_UMXHQ_RECORD in download_url


def _download_open_unmix_umxhq(destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for target, target_url in _OPEN_UNMIX_UMXHQ_TARGETS.items():
        _download_single_payload(target_url, destination / f"{target}.pth")


def _upload_directory(client: Any, bucket: str, model_id: str, root: Path) -> None:
    for path in sorted(root.rglob("*")):
        if not path.is_file() or _skip_snapshot_file(root, path):
            continue
        relative_key = path.relative_to(root).as_posix()
        _upload_file(client, bucket, model_id, path, relative_key)


def _skip_snapshot_file(root: Path, path: Path) -> bool:
    relative_parts = path.relative_to(root).parts
    return any(part in {".cache", ".locks", "__pycache__"} for part in relative_parts)


def _upload_file(
    client: Any, bucket: str, model_id: str, source: Path, relative_key: str
) -> None:
    client.upload_file(str(source), bucket, f"{model_id}/{relative_key}")
