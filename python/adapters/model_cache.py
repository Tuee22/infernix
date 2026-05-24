"""Uniform per-adapter model-cache helper.

Phase 7 Sprint 7.7 routes every adapter through this module so engine
pods load model weights from the MinIO ``infernix-models`` bucket on
first use and reuse a bounded on-disk cache under ``/model-cache`` on
subsequent requests, regardless of whether the underlying engine
library supports bytes-loading natively.

The helper exposes one stable entry point::

    from adapters.model_cache import get_model_path

    weights_dir = get_model_path("audio-bark-small")

``get_model_path`` is idempotent: first call for a given ``model_id``
streams every file under ``infernix-models/<model_id>/`` to
``/model-cache/<model_id>/`` via the MinIO client, waits for the
``.ready`` sentinel, then writes a local ``.ready`` marker. Subsequent
calls return the existing path immediately. After populating a new
entry the helper runs LRU eviction to keep the cache tree under its
size budget.

The MinIO client uses boto3's S3 surface against the
``INFERNIX_MINIO_*`` env vars the chart injects. If the bucket has not
yet been populated by the coordinator (i.e. the upstream
``.ready`` sentinel object is absent), the helper raises
``ModelCacheNotPopulated`` so the Haskell engine daemon can publish a
``model.bootstrap.request`` envelope and retry once the coordinator
broadcasts the matching ``model.bootstrap.ready.<modelId>`` event.
"""

from __future__ import annotations

import os
import shutil
import time
from pathlib import Path
from typing import Any, cast

__all__ = [
    "ModelCacheNotPopulated",
    "READY_SENTINEL_NAME",
    "get_model_path",
    "model_cache_root",
]


# Supported on-disk root mounted into engine pods (and into the host-engine
# daemon on Apple silicon) as an ``emptyDir`` ``sizeLimit``-backed volume.
# Operators may point a unit-test or isolated daemon run at a different
# directory through ``INFERNIX_MODEL_CACHE_ROOT`` so test fixtures do not
# require a writable ``/model-cache`` mount.
DEFAULT_MODEL_CACHE_ROOT = "/model-cache"

# Name of the per-model sentinel the coordinator's bootstrap subscription
# writes last. Adapters never proceed without it: a missing or partial
# ``.ready`` file means an upstream download is still in flight or a
# previous attempt failed midway through, and the engine should wait for
# the next ``model.bootstrap.ready.<modelId>`` event before retrying.
READY_SENTINEL_NAME = ".ready"

# Default LRU quota matches ``chart/values.yaml`` ``engine.modelCache.sizeLimit``
# of ``32Gi``. Operators override via ``INFERNIX_MODEL_CACHE_QUOTA_BYTES``
# for isolated daemon runs and unit tests.
DEFAULT_QUOTA_BYTES = 32 * 1024 * 1024 * 1024

# Default MinIO bucket. The chart provisions this bucket as
# ``infernix-models``; operators may override via ``INFERNIX_MODELS_BUCKET``
# for tenant isolation or test fixtures.
DEFAULT_MODELS_BUCKET = "infernix-models"


class ModelCacheNotPopulated(RuntimeError):
    """Raised when ``get_model_path`` cannot return a populated cache.

    The supported recovery path is for the engine daemon to publish a
    ``model.bootstrap.request`` envelope on the ``infernix/system``
    namespace and wait for the matching ``.ready`` event. Engine pods
    on real clusters reach this state only on first use of a model on
    a given node; subsequent calls reuse the cached copy. Concurrent
    bootstrap requests for the same model are deduplicated by
    Pulsar's broker-side dedup so the upstream download fires once.
    """


def model_cache_root() -> Path:
    """Return the absolute root path the engine reads cached weights from.

    Honours ``INFERNIX_MODEL_CACHE_ROOT`` so isolated daemon runs and
    unit tests can redirect the helper without mutating
    ``/model-cache``.
    """
    configured = os.environ.get("INFERNIX_MODEL_CACHE_ROOT")
    return Path(configured) if configured else Path(DEFAULT_MODEL_CACHE_ROOT)


def get_model_path(model_id: str) -> Path:
    """Return the local cache directory for ``model_id``.

    Contract:

    * The directory is guaranteed to contain every file the engine
      needs to load the model offline before this function returns.
    * The directory tree is read-only from the adapter's perspective;
      eviction is owned by this module's LRU loop, not by the caller.
    * Calls are idempotent — repeat calls return the same path
      without touching MinIO or Pulsar.

    Raises ``ModelCacheNotPopulated`` if the local mirror is missing
    or incomplete *and* the MinIO bucket does not yet hold the
    upstream ``.ready`` sentinel. The Haskell engine daemon catches
    that exception, publishes a ``model.bootstrap.request`` envelope,
    and retries when the coordinator publishes the matching
    ``.ready`` event.
    """
    if not model_id:
        raise ValueError("model_id must be non-empty")

    cache_root = model_cache_root()
    model_dir = cache_root / model_id
    ready_sentinel = model_dir / READY_SENTINEL_NAME

    if model_dir.is_dir() and ready_sentinel.is_file():
        _touch_access_time(model_dir)
        return model_dir

    _populate_from_minio(model_id, model_dir)

    if not (model_dir.is_dir() and ready_sentinel.is_file()):
        raise ModelCacheNotPopulated(
            f"model {model_id!r} could not be populated from MinIO; "
            "the coordinator's bootstrap subscription may not have "
            "published the .ready sentinel for this model yet."
        )

    _enforce_lru_quota(cache_root)
    return model_dir


def _populate_from_minio(model_id: str, dest_dir: Path) -> None:
    """Stream every file under ``infernix-models/<model_id>/`` into ``dest_dir``.

    Refuses to write the local ``.ready`` sentinel until every object
    under the upstream prefix has been written and the upstream
    ``.ready`` object is also present, so a partial download leaves
    the local cache in a recoverable (re-poll) state rather than a
    false-ready state that would mislead the engine adapter.
    """
    endpoint = os.environ.get("INFERNIX_MINIO_ENDPOINT")
    access_key = os.environ.get("INFERNIX_MINIO_ACCESS_KEY")
    secret_key = os.environ.get("INFERNIX_MINIO_SECRET_KEY")
    region = os.environ.get("INFERNIX_MINIO_REGION", "us-east-1")
    bucket = os.environ.get("INFERNIX_MODELS_BUCKET", DEFAULT_MODELS_BUCKET)

    if not (endpoint and access_key and secret_key):
        raise ModelCacheNotPopulated(
            f"MinIO connection env vars missing; cannot populate model "
            f"{model_id!r}. Set INFERNIX_MINIO_ENDPOINT, "
            "INFERNIX_MINIO_ACCESS_KEY, and INFERNIX_MINIO_SECRET_KEY."
        )

    try:
        # boto3 is the supported S3 client. Importing inside the function
        # keeps unit tests that exercise the local-cache hit path runnable
        # without the dependency installed; the import only fires on a
        # genuine cache miss against MinIO. The package ships without a
        # py.typed marker so mypy needs the import-untyped suppression.
        import boto3  # type: ignore[import-untyped]
        from botocore.client import Config  # type: ignore[import-untyped]
    except ImportError as exc:
        raise ModelCacheNotPopulated(
            f"boto3 is unavailable in this engine venv; cannot populate "
            f"model {model_id!r} from MinIO. Run `poetry install` to "
            "reconcile the supported adapter dependencies."
        ) from exc

    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name=region,
        # Path-style addressing is the MinIO-supported access mode; the
        # virtual-host style requires bucket-name DNS records that the
        # chart does not provision.
        config=Config(s3={"addressing_style": "path"}, signature_version="s3v4"),
    )

    prefix = f"{model_id}/"
    keys = _list_minio_objects(client, bucket, prefix)
    relative_keys = [_strip_prefix(key, prefix) for key in keys]

    if READY_SENTINEL_NAME not in relative_keys:
        raise ModelCacheNotPopulated(
            f"MinIO {bucket}/{prefix} is missing the {READY_SENTINEL_NAME} "
            "sentinel object. The coordinator's bootstrap subscription "
            "has not yet finished populating this model."
        )

    dest_dir.mkdir(parents=True, exist_ok=True)

    # Download every object except the sentinel first, then write the
    # local sentinel atomically last so a crashed populate leaves
    # `.ready` absent and the next call retries cleanly.
    for key, relative in zip(keys, relative_keys, strict=True):
        if relative == READY_SENTINEL_NAME:
            continue
        local_path = dest_dir / relative
        local_path.parent.mkdir(parents=True, exist_ok=True)
        _download_minio_object(client, bucket, key, local_path)

    sentinel_path = dest_dir / READY_SENTINEL_NAME
    sentinel_tmp = sentinel_path.with_suffix(".tmp")
    sentinel_tmp.write_text("populated-from-minio\n", encoding="utf-8")
    sentinel_tmp.replace(sentinel_path)


def _list_minio_objects(client: Any, bucket: str, prefix: str) -> list[str]:
    """Return every object key under ``bucket/prefix`` (handles paginated lists)."""
    paginator = client.get_paginator("list_objects_v2")
    keys: list[str] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []) or []:
            key = cast(str, item.get("Key", ""))
            if key:
                keys.append(key)
    return keys


def _download_minio_object(client: Any, bucket: str, key: str, dest_path: Path) -> None:
    """Stream ``bucket/key`` into ``dest_path`` via a temp file + atomic rename."""
    temp_path = dest_path.with_suffix(dest_path.suffix + ".tmp")
    with temp_path.open("wb") as dest_handle:
        client.download_fileobj(bucket, key, dest_handle)
    temp_path.replace(dest_path)


def _strip_prefix(key: str, prefix: str) -> str:
    return key[len(prefix) :] if key.startswith(prefix) else key


def _enforce_lru_quota(cache_root: Path) -> None:
    """Evict least-recently-used model entries when the cache exceeds quota.

    Quota is read from ``INFERNIX_MODEL_CACHE_QUOTA_BYTES`` or defaults
    to ``DEFAULT_QUOTA_BYTES``. The function preserves at least one
    entry so a tightly bounded cache (less than one model's footprint)
    still serves the most-recently-loaded model.
    """
    if not cache_root.is_dir():
        return

    quota_bytes = _cache_quota_bytes()
    entries = sorted(
        (entry for entry in cache_root.iterdir() if entry.is_dir()),
        key=lambda entry: entry.stat().st_atime,
    )
    if not entries:
        return

    total_bytes = sum(_directory_size_bytes(entry) for entry in entries)
    eviction_index = 0
    while total_bytes > quota_bytes and eviction_index < len(entries) - 1:
        victim = entries[eviction_index]
        victim_size = _directory_size_bytes(victim)
        shutil.rmtree(victim, ignore_errors=True)
        total_bytes -= victim_size
        eviction_index += 1


def _cache_quota_bytes() -> int:
    configured = os.environ.get("INFERNIX_MODEL_CACHE_QUOTA_BYTES")
    if configured:
        try:
            return int(configured)
        except ValueError:
            return DEFAULT_QUOTA_BYTES
    return DEFAULT_QUOTA_BYTES


def _directory_size_bytes(path: Path) -> int:
    total = 0
    for entry in path.rglob("*"):
        if entry.is_file():
            total += entry.stat().st_size
    return total


def _touch_access_time(path: Path) -> None:
    """Bump atime/mtime so the LRU sort puts this entry at the tail."""
    now = time.time()
    try:
        os.utime(path, (now, now))
    except OSError:
        # Best-effort: on read-only mounts the touch fails but the
        # entry is still usable. The next eviction round picks a
        # different victim.
        pass
