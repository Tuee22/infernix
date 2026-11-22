from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile
from enum import Enum
from pathlib import Path
from typing import Any

READY_SENTINEL_NAME = ".ready"
NATIVE_SNAPSHOT_INDEX_NAME = ".infernix-native-snapshot-files"
ARTIFACT_INVENTORY_NAME = ".infernix-artifact-inventory.json"
SNAPSHOT_INVENTORY_LIMIT = 1024 * 1024

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
_MT3_PYTORCH_PRETRAINED_REPO = "github.com/kunato/mt3-pytorch"
_MT3_PYTORCH_PRETRAINED_FILES = {
    "config.json": "https://raw.githubusercontent.com/kunato/mt3-pytorch/master/pretrained/config.json",
    "mt3.pth": "https://media.githubusercontent.com/media/kunato/mt3-pytorch/master/pretrained/mt3.pth",
}
_MT3_PYTORCH_MT3_PTH_BYTES = 183_672_643
_MT3_PYTORCH_MT3_PTH_SHA256 = (
    "b8a3807ed265059abd25ad7f68142c06c35e8f6144dcaa45bd55946a3745398f"
)


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
    if _existing_model_cache_ready(
        client,
        args.models_bucket,
        args.model_id,
        args.download_url,
    ):
        if not _is_package_backed_native_model(args.model_id):
            _ensure_retained_artifact_inventory(
                client, args.models_bucket, args.model_id, args.download_url
            )
        return 0
    if _is_package_backed_native_model(args.model_id):
        _write_ready_sentinel(client, args.models_bucket, args.model_id)
        return 0

    repo_id = _hugging_face_repo_id(args.download_url)
    with tempfile.TemporaryDirectory(prefix="infernix-model-bootstrap-") as temp_root:
        if _is_mt3_pytorch_pretrained(args.download_url):
            snapshot_root = Path(temp_root) / "snapshot"
            _download_mt3_pytorch_pretrained(snapshot_root)
            _upload_directory(client, args.models_bucket, args.model_id, snapshot_root)
        elif _is_open_unmix_umxhq(args.download_url):
            snapshot_root = Path(temp_root) / "snapshot"
            _download_open_unmix_umxhq(snapshot_root)
            _upload_directory(client, args.models_bucket, args.model_id, snapshot_root)
        elif repo_id is None:
            payload_path = Path(temp_root) / "payload"
            _download_single_payload(args.download_url, payload_path)
            _upload_file(
                client, args.models_bucket, args.model_id, payload_path, "payload"
            )
            _upload_artifact_inventory(
                client, args.models_bucket, args.model_id, [("payload", payload_path)]
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
    from botocore.exceptions import ClientError

    try:
        client.head_object(Bucket=bucket, Key=f"{model_id}/{READY_SENTINEL_NAME}")
        return True
    except ClientError as exc:
        if exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode") == 404:
            return False
        raise


class CacheValidity(Enum):
    """Three-valued verdict on a retained model cache.

    The warm-model-cache stall had a sibling on this side: ``_delete_model_prefix``
    (which removes the ``.ready`` sentinel) was reachable whenever revalidation
    returned ``False`` — and revalidation returned ``False`` on both genuine
    corruption *and* a fallible MinIO read. On the retained-state second
    ``cluster up``, a transient read fault (MinIO/registry contending for the same
    backing store) would therefore destroy a valid retained sentinel, leaving the
    barrier polling forever for a model it just deleted. Making the verdict
    three-valued keeps "I could not verify it" (``UNVERIFIABLE``) distinct from
    "it is definitely broken" (``CORRUPT``), so deletion is reachable only through
    a confirmed-corrupt witness a caught exception cannot produce.
    """

    VALID = "valid"
    CORRUPT = "corrupt"
    UNVERIFIABLE = "unverifiable"


def _existing_model_cache_ready(
    client: Any, bucket: str, model_id: str, download_url: str
) -> bool:
    if not _sentinel_exists(client, bucket, model_id):
        return False
    if not _is_mt3_pytorch_pretrained(download_url):
        return True
    validity = _mt3_pytorch_cache_validity(client, bucket, model_id)
    if validity is CacheValidity.CORRUPT:
        # Only a confirmed-corrupt cache is destroyed and re-staged. VALID and
        # UNVERIFIABLE both keep the retained sentinel: a transient read fault
        # must never delete a good cache, and a cache that is genuinely broken
        # but unverifiable fails closed at inference (realness contract) rather
        # than being silently deleted on a blip.
        _delete_model_prefix(client, bucket, model_id)
        return False
    return True


def _mt3_pytorch_cache_validity(
    client: Any, bucket: str, model_id: str
) -> CacheValidity:
    try:
        config_size = _object_size(client, bucket, f"{model_id}/config.json")
        checkpoint_size = _object_size(client, bucket, f"{model_id}/mt3.pth")
        index_size = _object_size(
            client, bucket, f"{model_id}/{NATIVE_SNAPSHOT_INDEX_NAME}"
        )
    except Exception:
        # A fallible HEAD is not evidence of corruption.
        return CacheValidity.UNVERIFIABLE
    expected_shape = (
        100 <= config_size <= 1024 * 1024
        and checkpoint_size == _MT3_PYTORCH_MT3_PTH_BYTES
        and index_size > 0
    )
    if not expected_shape:
        # Deterministic HEAD-size mismatch: the only confirmed-corrupt signal,
        # and it never touches the network payload.
        return CacheValidity.CORRUPT
    try:
        with tempfile.TemporaryDirectory(prefix="infernix-mt3-cache-check-") as root:
            snapshot_root = Path(root)
            client.download_file(
                bucket, f"{model_id}/config.json", str(snapshot_root / "config.json")
            )
            client.download_file(
                bucket, f"{model_id}/mt3.pth", str(snapshot_root / "mt3.pth")
            )
            _validate_mt3_pytorch_snapshot(snapshot_root)
    except Exception:
        # A read/validation fault during the deep check is treated as
        # unverifiable, not corrupt, so a MinIO blip cannot delete the sentinel.
        return CacheValidity.UNVERIFIABLE
    return CacheValidity.VALID


def _object_size(client: Any, bucket: str, key: str) -> int:
    response = client.head_object(Bucket=bucket, Key=key)
    return int(response["ContentLength"])


def _delete_model_prefix(client: Any, bucket: str, model_id: str) -> None:
    prefix = f"{model_id}/"
    paginator = client.get_paginator("list_objects_v2")
    pending: list[dict[str, str]] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []) or []:
            key = item.get("Key")
            if key:
                pending.append({"Key": key})
            if len(pending) == 1000:
                client.delete_objects(Bucket=bucket, Delete={"Objects": pending})
                pending = []
    if pending:
        client.delete_objects(Bucket=bucket, Delete={"Objects": pending})


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
    if normalized_repo_id == "huggingfacetb/smollm2-135m-instruct":
        return [
            "config.json",
            "generation_config.json",
            "merges.txt",
            "model.safetensors",
            "special_tokens_map.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "vocab.json",
        ]
    if normalized_repo_id == "apple/coreml-stable-diffusion-v1-5-palettized":
        return [
            "original/packages/**",
        ]
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


def _is_mt3_pytorch_pretrained(download_url: str) -> bool:
    return _MT3_PYTORCH_PRETRAINED_REPO in download_url


def _is_package_backed_native_model(model_id: str) -> bool:
    return model_id in {"audio-basic-pitch-coreml"}


def _download_mt3_pytorch_pretrained(destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            for relative_path, target_url in _MT3_PYTORCH_PRETRAINED_FILES.items():
                _download_single_payload(target_url, destination / relative_path)
            _validate_mt3_pytorch_snapshot(destination)
            return
        except Exception as error:
            last_error = error
            for relative_path in _MT3_PYTORCH_PRETRAINED_FILES:
                (destination / relative_path).unlink(missing_ok=True)
            if attempt < 2:
                time.sleep(5.0 * (attempt + 1))
    if last_error is not None:
        raise last_error


def _validate_mt3_pytorch_snapshot(root: Path) -> None:
    config_path = root / "config.json"
    checkpoint_path = root / "mt3.pth"
    with config_path.open("r", encoding="utf-8") as handle:
        json.load(handle)
    checkpoint_size = checkpoint_path.stat().st_size
    if checkpoint_size != _MT3_PYTORCH_MT3_PTH_BYTES:
        raise RuntimeError(
            "refusing to stage MT3-PyTorch checkpoint from "
            f"{_MT3_PYTORCH_PRETRAINED_FILES['mt3.pth']}: expected "
            f"{_MT3_PYTORCH_MT3_PTH_BYTES} bytes, got {checkpoint_size}"
        )
    checkpoint_sha256 = _sha256_file(checkpoint_path)
    if checkpoint_sha256 != _MT3_PYTORCH_MT3_PTH_SHA256:
        raise RuntimeError(
            "refusing to stage MT3-PyTorch checkpoint from "
            f"{_MT3_PYTORCH_PRETRAINED_FILES['mt3.pth']}: expected sha256 "
            f"{_MT3_PYTORCH_MT3_PTH_SHA256}, got {checkpoint_sha256}"
        )
    if not zipfile.is_zipfile(checkpoint_path):
        raise RuntimeError(
            "refusing to stage MT3-PyTorch checkpoint: mt3.pth is not a "
            "valid PyTorch zip archive"
        )
    with zipfile.ZipFile(checkpoint_path) as archive:
        bad_member = archive.testzip()
    if bad_member is not None:
        raise RuntimeError(
            "refusing to stage MT3-PyTorch checkpoint: mt3.pth failed zip "
            f"integrity at {bad_member}"
        )


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _download_open_unmix_umxhq(destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for target, target_url in _OPEN_UNMIX_UMXHQ_TARGETS.items():
        _download_single_payload(target_url, destination / f"{target}.pth")


def _upload_directory(client: Any, bucket: str, model_id: str, root: Path) -> None:
    uploaded_files = _snapshot_inventory_sources(root)
    uploaded_keys = [name for name, _ in uploaded_files]
    for relative_key, path in uploaded_files:
        _upload_file(client, bucket, model_id, path, relative_key)
    client.put_object(
        Bucket=bucket,
        Key=f"{model_id}/{NATIVE_SNAPSHOT_INDEX_NAME}",
        Body=("\n".join(uploaded_keys) + "\n").encode("utf-8"),
        ContentType="text/plain; charset=utf-8",
    )
    _upload_artifact_inventory(client, bucket, model_id, uploaded_files)


def _upload_artifact_inventory(
    client: Any,
    bucket: str,
    model_id: str,
    files: list[tuple[str, Path]],
    *,
    only_if_missing: bool = False,
) -> None:
    """Publish the producer's file identities before the ready sentinel.

    The inventory describes the local upload sources. Consumers must still
    verify the downloaded bytes against it; publishing it alone does not prove
    the object store or a cache contains those bytes.
    """
    entries = []
    for relative_key, source in sorted(files):
        digest = hashlib.sha256()
        size = 0
        with source.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
                size += len(chunk)
        entries.append(
            {"path": relative_key, "size": size, "sha256": digest.hexdigest()}
        )
    payload = json.dumps(
        {"version": 1, "files": entries}, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    if not entries or len(payload) > 1024 * 1024:
        raise ValueError("artifact inventory is empty or exceeds its size bound")
    request: dict[str, Any] = {
        "Bucket": bucket,
        "Key": f"{model_id}/{ARTIFACT_INVENTORY_NAME}",
        "Body": payload,
        "ContentType": "application/json",
    }
    if only_if_missing:
        request["IfNoneMatch"] = "*"
    client.put_object(**request)


def _ensure_retained_artifact_inventory(
    client: Any, bucket: str, model_id: str, download_url: str
) -> None:
    """Add identity only after retained bytes match a fresh upstream copy.

    This operation never removes or replaces retained model objects. Failures
    preserve the existing sentinel and do not publish a new inventory.
    """
    from botocore.exceptions import ClientError

    try:
        client.head_object(Bucket=bucket, Key=f"{model_id}/{ARTIFACT_INVENTORY_NAME}")
        return
    except ClientError as exc:
        status = exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
        if status != 404:
            raise

    with tempfile.TemporaryDirectory(
        prefix="infernix-retained-inventory-"
    ) as temporary:
        root = Path(temporary)
        repo_id = _hugging_face_repo_id(download_url)
        is_snapshot = True
        if _is_mt3_pytorch_pretrained(download_url):
            snapshot = root / "snapshot"
            _download_mt3_pytorch_pretrained(snapshot)
            files = _snapshot_inventory_sources(snapshot)
        elif _is_open_unmix_umxhq(download_url):
            snapshot = root / "snapshot"
            _download_open_unmix_umxhq(snapshot)
            files = _snapshot_inventory_sources(snapshot)
        elif repo_id is None:
            is_snapshot = False
            payload = root / "payload"
            _download_single_payload(download_url, payload)
            files = [("payload", payload)]
        else:
            snapshot = root / "snapshot"
            _download_hugging_face_snapshot(repo_id, snapshot)
            files = _snapshot_inventory_sources(snapshot)
        _verify_retained_artifacts(
            client, bucket, model_id, files, require_index=is_snapshot
        )
        _upload_artifact_inventory(
            client, bucket, model_id, files, only_if_missing=True
        )


def _snapshot_inventory_sources(root: Path) -> list[tuple[str, Path]]:
    files: list[tuple[str, Path]] = []
    count = 0
    index_size = 0
    inventory_size = len(b'{"files":[],"version":1}')

    def visit(directory: Path, depth: int) -> None:
        nonlocal count, index_size, inventory_size
        if depth > 64:
            raise ValueError("upstream snapshot exceeds its directory depth bound")
        with os.scandir(directory) as entries:
            for entry in entries:
                count += 1
                if count > 100000:
                    raise ValueError("upstream snapshot exceeds its entry count bound")
                path = Path(entry.path)
                if _skip_snapshot_file(root, path):
                    continue
                name = path.relative_to(root).as_posix()
                if (
                    len(name) > 4096
                    or "\\" in name
                    or any(ord(c) < 32 or ord(c) == 127 for c in name)
                ):
                    raise ValueError("upstream snapshot contains an invalid path")
                if entry.is_symlink():
                    raise ValueError("upstream snapshot contains a symbolic link")
                if entry.is_dir(follow_symlinks=False):
                    visit(path, depth + 1)
                elif entry.is_file(follow_symlinks=False):
                    index_size += len(name.encode("utf-8")) + 1
                    encoded_entry = json.dumps(
                        {
                            "path": name,
                            "size": entry.stat(follow_symlinks=False).st_size,
                            "sha256": "0" * 64,
                        },
                        separators=(",", ":"),
                        sort_keys=True,
                    ).encode("utf-8")
                    inventory_size += len(encoded_entry) + (1 if files else 0)
                    if (
                        index_size > SNAPSHOT_INVENTORY_LIMIT
                        or inventory_size > SNAPSHOT_INVENTORY_LIMIT
                    ):
                        raise ValueError(
                            "upstream snapshot inventory exceeds its size bound"
                        )
                    files.append((name, path))
                else:
                    raise ValueError("upstream snapshot contains a non-regular entry")

    visit(root, 0)
    files.sort(key=lambda item: item[0])
    if not files or any(
        name
        in {READY_SENTINEL_NAME, ARTIFACT_INVENTORY_NAME, NATIVE_SNAPSHOT_INDEX_NAME}
        for name, _ in files
    ):
        raise ValueError("upstream snapshot has no files or contains reserved names")
    return files


def _verify_retained_artifacts(
    client: Any,
    bucket: str,
    model_id: str,
    files: list[tuple[str, Path]],
    *,
    require_index: bool,
) -> None:
    """Compare complete retained inventory and bytes without mutating it."""
    prefix = f"{model_id}/"
    observed: set[str] = set()
    for page in client.get_paginator("list_objects_v2").paginate(
        Bucket=bucket, Prefix=prefix
    ):
        for item in page.get("Contents", []) or []:
            key = item.get("Key")
            if not isinstance(key, str) or not key.startswith(prefix):
                raise ValueError("retained object listing contains an invalid key")
            relative = key[len(prefix) :]
            if relative in observed or len(observed) >= 100000:
                raise ValueError(
                    "retained object listing is duplicated or exceeds its bound"
                )
            observed.add(relative)
    expected = {name for name, _ in files}
    metadata = {READY_SENTINEL_NAME, NATIVE_SNAPSHOT_INDEX_NAME}
    unsafe = any(
        not name
        or len(name) > 4096
        or "\\" in name
        or any(not part or part in {".", ".."} for part in name.split("/"))
        or any(ord(character) < 32 or ord(character) == 127 for character in name)
        for name in expected
    )
    if (
        unsafe
        or not expected
        or len(expected) != len(files)
        or observed - metadata != expected
        or READY_SENTINEL_NAME not in observed
        or (require_index and NATIVE_SNAPSHOT_INDEX_NAME not in observed)
    ):
        raise ValueError("retained artifact inventory differs from upstream")
    if require_index:
        index_response = client.get_object(
            Bucket=bucket, Key=prefix + NATIVE_SNAPSHOT_INDEX_NAME
        )
        index_body = index_response["Body"]
        try:
            index = index_body.read(1024 * 1024 + 1)
        finally:
            index_body.close()
        try:
            index_names = index.decode("utf-8").splitlines()
        except UnicodeDecodeError as exc:
            raise ValueError("retained snapshot index is not UTF-8") from exc
        if (
            len(index) > 1024 * 1024
            or len(index_names) != len(expected)
            or set(index_names) != expected
        ):
            raise ValueError("retained snapshot index differs from upstream")
    for name, source in files:
        local_digest = hashlib.sha256()
        local_size = 0
        with source.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                local_digest.update(chunk)
                local_size += len(chunk)
        response = client.get_object(Bucket=bucket, Key=prefix + name)
        body = response["Body"]
        try:
            if (
                type(response.get("ContentLength")) is not int
                or response.get("ContentLength") != local_size
            ):
                raise ValueError("retained object extent differs from upstream")
            remote_digest = hashlib.sha256()
            size = 0
            while chunk := body.read(min(1024 * 1024, local_size - size + 1)):
                size += len(chunk)
                if size > local_size:
                    raise ValueError("retained object exceeds its declared extent")
                remote_digest.update(chunk)
            if size != local_size or remote_digest.digest() != local_digest.digest():
                raise ValueError("retained object bytes differ from upstream")
        finally:
            body.close()


def _skip_snapshot_file(root: Path, path: Path) -> bool:
    relative_parts = path.relative_to(root).parts
    return any(part in {".cache", ".locks", "__pycache__"} for part in relative_parts)


def _upload_file(
    client: Any, bucket: str, model_id: str, source: Path, relative_key: str
) -> None:
    client.upload_file(str(source), bucket, f"{model_id}/{relative_key}")
