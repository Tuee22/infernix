"""Uniform per-adapter model-cache helper.

Phase 7 Sprint 7.7 routes every adapter through this module so engine
pods load model weights from the MinIO ``infernix-models`` bucket on
first use and reuse a bounded on-disk cache under ``/model-cache`` on
subsequent requests, regardless of whether the underlying engine
library supports bytes-loading natively.

The helper exposes one stable entry point::

    from adapters.model_cache import configure, get_model_path, ModelCacheConfig

    configure(ModelCacheConfig(...))
    weights_dir = get_model_path("audio-bark-small")

``get_model_path`` is idempotent: first call for a given ``model_id``
streams every file under ``infernix-models/<model_id>/`` to
``/model-cache/<model_id>/`` via the MinIO client, waits for the
``.ready`` sentinel, then writes a local ``.ready`` marker. Subsequent
calls return the existing path immediately. After populating a new
entry the helper runs LRU eviction to keep the cache tree under its
size budget.

Phase 5 Sprint 5.9 follow-on (May 26, 2026): MinIO connection details
+ cache root + quota are passed via the typed ``ModelCacheConfig``
record via ``configure()`` instead of read from ``INFERNIX_MINIO_*``
+ ``INFERNIX_MODEL_CACHE_*`` env vars. The engine daemon decodes the
chart-mounted ``ClusterConfig.minio`` + ``SecretsConfig.minio`` (via
the mounted ``Secret/infernix-cluster-secrets`` JSON files) and
passes the resolved values through. If the bucket has not yet been
populated by the coordinator (i.e. the upstream ``.ready`` sentinel
object is absent), the helper raises ``ModelCacheNotPopulated`` so
the Haskell engine daemon can publish a ``model.bootstrap.request``
envelope and retry once the coordinator broadcasts the matching
``model.bootstrap.ready.<modelId>`` event.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import secrets
import shutil
import stat
import time
from collections.abc import Iterator
from contextlib import ExitStack, contextmanager
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

__all__ = [
    "ModelCacheConfig",
    "ModelCacheNotPopulated",
    "READY_SENTINEL_NAME",
    "configure",
    "configured",
    "get_model_path",
    "model_cache_root",
]


# Supported on-disk root mounted into engine pods (and into the host-engine
# daemon on Apple silicon) as an ``emptyDir`` ``sizeLimit``-backed volume.
# Test fixtures or isolated daemon runs pass a different directory via
# ``ModelCacheConfig.cache_root`` so they do not require a writable
# ``/model-cache`` mount.
DEFAULT_MODEL_CACHE_ROOT = "/model-cache"

# Name of the per-model sentinel the coordinator's bootstrap subscription
# writes last. Adapters never proceed without it: a missing or partial
# ``.ready`` file means an upstream download is still in flight or a
# previous attempt failed midway through, and the engine should wait for
# the next ``model.bootstrap.ready.<modelId>`` event before retrying.
READY_SENTINEL_NAME = ".ready"
ARTIFACT_INVENTORY_NAME = ".infernix-artifact-inventory.json"
ARTIFACT_INVENTORY_LIMIT = 1024 * 1024
MODEL_OBJECT_COUNT_LIMIT = 100000
INVENTORY_READY_MARKER = "populated-from-minio-with-inventory\n"
NATIVE_SNAPSHOT_INDEX_NAME = ".infernix-native-snapshot-files"


def _verify_artifact_inventory(root: Path) -> None:
    """Verify an inventory and each named regular file without buffering weights."""
    descriptor = os.open(
        root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    )
    try:
        _verify_artifact_inventory_at(descriptor)
    finally:
        os.close(descriptor)


def _open_cache_regular(root_fd: int, parts: tuple[str, ...]) -> int:
    """Open a regular leaf relative to held, non-symlink directory descriptors."""
    with ExitStack() as stack:
        parent = root_fd
        for component in parts[:-1]:
            parent = os.open(
                component,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                dir_fd=parent,
            )
            stack.callback(os.close, parent)
        leaf = os.open(
            parts[-1],
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
            dir_fd=parent,
        )
        if not stat.S_ISREG(os.fstat(leaf).st_mode):
            os.close(leaf)
            raise ModelCacheNotPopulated("artifact identity path is not a regular file")
        return leaf


def _verify_artifact_inventory_at(root_fd: int, raw: bytes | None = None) -> None:
    if raw is None:
        try:
            inventory_fd = _open_cache_regular(root_fd, (ARTIFACT_INVENTORY_NAME,))
        except OSError as exc:
            raise ModelCacheNotPopulated(
                "artifact identity inventory is missing or inaccessible"
            ) from exc
        with os.fdopen(inventory_fd, "rb") as handle:
            raw = handle.read(ARTIFACT_INVENTORY_LIMIT + 1)
    if len(raw) > ARTIFACT_INVENTORY_LIMIT:
        raise ModelCacheNotPopulated("artifact identity inventory exceeds its bound")
    try:
        parsed = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ModelCacheNotPopulated(
            "artifact identity inventory is malformed"
        ) from exc
    if (
        not isinstance(parsed, dict)
        or set(parsed) != {"version", "files"}
        or type(parsed["version"]) is not int
        or parsed["version"] != 1
    ):
        raise ModelCacheNotPopulated(
            "artifact identity inventory has an unsupported shape"
        )
    files = parsed["files"]
    if not isinstance(files, list) or not files:
        raise ModelCacheNotPopulated("artifact identity inventory has no files")
    seen: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict) or set(entry) != {"path", "size", "sha256"}:
            raise ModelCacheNotPopulated("artifact identity entry is malformed")
        name, size, expected = entry["path"], entry["size"], entry["sha256"]
        if not isinstance(name, str) or not name or "\\" in name:
            raise ModelCacheNotPopulated("artifact identity path is invalid")
        path = PurePosixPath(name)
        if (
            path.is_absolute()
            or any(part in {".", "..", ""} for part in name.split("/"))
            or name in seen
        ):
            raise ModelCacheNotPopulated(
                "artifact identity path is invalid or duplicated"
            )
        if name in {READY_SENTINEL_NAME, ARTIFACT_INVENTORY_NAME}:
            raise ModelCacheNotPopulated("artifact identity path is reserved")
        if (
            type(size) is not int
            or size < 0
            or not isinstance(expected, str)
            or len(expected) != 64
            or any(c not in "0123456789abcdef" for c in expected)
        ):
            raise ModelCacheNotPopulated(
                "artifact identity extent or digest is invalid"
            )
        seen.add(name)
        try:
            descriptor = _open_cache_regular(root_fd, path.parts)
        except OSError as exc:
            raise ModelCacheNotPopulated(
                "artifact identity file is missing or inaccessible"
            ) from exc
        digest = hashlib.sha256()
        actual_size = 0
        with os.fdopen(descriptor, "rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
                actual_size += len(chunk)
                if actual_size > size:
                    raise ModelCacheNotPopulated("artifact identity extent differs")
        if actual_size != size or digest.hexdigest() != expected:
            raise ModelCacheNotPopulated(
                "artifact identity does not match cached bytes"
            )
    _verify_cache_contents_at(root_fd, seen)


def _verify_cache_contents_at(root_fd: int, expected: set[str]) -> None:
    """Refuse unlisted files and special entries in a bounded cache traversal."""
    observed: set[str] = set()
    count = 0
    allowed_directories = {
        "/".join(parts[:index])
        for path in expected
        for parts in [path.split("/")]
        for index in range(1, len(parts))
    }

    def visit(directory_fd: int, prefix: str, depth: int) -> None:
        nonlocal count
        if depth > 64:
            raise ModelCacheNotPopulated("artifact cache exceeds directory depth bound")
        with os.scandir(directory_fd) as entries:
            for entry in entries:
                count += 1
                if count > 100000:
                    raise ModelCacheNotPopulated(
                        "artifact cache exceeds entry count bound"
                    )
                relative = prefix + entry.name
                metadata = entry.stat(follow_symlinks=False)
                if stat.S_ISDIR(metadata.st_mode):
                    if relative not in allowed_directories:
                        raise ModelCacheNotPopulated(
                            "artifact cache contains an unlisted directory"
                        )
                    descriptor = os.open(
                        entry.name,
                        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                        dir_fd=directory_fd,
                    )
                    try:
                        visit(descriptor, relative + "/", depth + 1)
                    finally:
                        os.close(descriptor)
                elif stat.S_ISREG(metadata.st_mode):
                    if relative not in {
                        READY_SENTINEL_NAME,
                        ARTIFACT_INVENTORY_NAME,
                        NATIVE_SNAPSHOT_INDEX_NAME,
                    }:
                        observed.add(relative)
                else:
                    raise ModelCacheNotPopulated(
                        "artifact cache contains a non-regular entry"
                    )

    visit(root_fd, "", 0)
    if observed != expected:
        raise ModelCacheNotPopulated(
            "artifact cache contents do not match the inventory"
        )


# Default LRU quota matches ``chart/values.yaml`` ``engine.modelCache.sizeLimit``
# of ``32Gi``. Isolated daemon runs and unit tests override it through
# ``ModelCacheConfig.quota_bytes``.
DEFAULT_QUOTA_BYTES = 32 * 1024 * 1024 * 1024

# Default MinIO bucket. The chart provisions this bucket as
# ``infernix-models``; callers override it through
# ``ModelCacheConfig.models_bucket`` for tenant isolation or test fixtures.
DEFAULT_MODELS_BUCKET = "infernix-models"

# Default demo artifact bucket. Haskell passes the mounted ClusterConfig value
# through WorkerRequest; this fallback keeps direct adapter tests aligned with
# the chart default.
DEFAULT_DEMO_ARTIFACTS_BUCKET = "infernix-demo-objects"


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


class ModelCacheQuotaExceeded(RuntimeError):
    """The cache cannot free enough space without evicting an active model."""


@dataclass(frozen=True)
class ModelCacheConfig:
    """Typed model-cache + MinIO wiring the engine daemon passes through.

    Phase 5 Sprint 5.9 follow-on (May 26, 2026): replaces the
    ``INFERNIX_MODEL_CACHE_*`` + ``INFERNIX_MINIO_*`` env-var family.
    Callers populate this from the chart-mounted ``ClusterConfig``
    + ``SecretsConfig`` records the Haskell engine daemon decodes at
    startup. The default values match the previously-env-fallback
    constants so callers may omit fields they want the supported
    default for.
    """

    cache_root: Path = Path(DEFAULT_MODEL_CACHE_ROOT)
    quota_bytes: int = DEFAULT_QUOTA_BYTES
    models_bucket: str = DEFAULT_MODELS_BUCKET
    demo_artifacts_bucket: str = DEFAULT_DEMO_ARTIFACTS_BUCKET
    minio_endpoint: str = ""
    minio_access_key: str = ""
    minio_secret_key: str = ""
    minio_region: str = "us-east-1"


_CONFIG: ModelCacheConfig | None = None


def configure(config: ModelCacheConfig) -> None:
    """Set the typed model-cache config the helpers read from.

    Must be called before ``get_model_path`` invokes MinIO. The
    supported caller is the engine daemon's adapter bootstrap entry
    point, which decodes the cluster manifest + secrets manifest
    once at startup and passes the resolved values through.
    """
    global _CONFIG
    _CONFIG = config


def configured() -> ModelCacheConfig:
    """Return the configured ``ModelCacheConfig``.

    Phase 4 Sprint 4.15: the artifact-adapter seam reuses the engine
    daemon's already-decoded MinIO wiring to upload generated bytes to
    the ``infernix-demo-objects`` bucket. Raises ``ModelCacheNotPopulated``
    when ``configure()`` has not been called.
    """
    return _require_config()


def _require_config() -> ModelCacheConfig:
    if _CONFIG is None:
        raise ModelCacheNotPopulated(
            "adapters.model_cache.configure() must be called with a "
            "ModelCacheConfig before invoking get_model_path / "
            "model_cache_root. The supported caller is the engine "
            "daemon's adapter bootstrap which decodes the chart-mounted "
            "cluster + secrets manifests once at startup."
        )
    return _CONFIG


def model_cache_root() -> Path:
    """Return the absolute root path the engine reads cached weights from.

    Reads from the typed ``ModelCacheConfig`` populated via
    ``configure()``. When ``configure()`` has not been called, falls
    through to ``ModelCacheConfig()``'s default (``/model-cache``)
    for callers that want only the supported default location.
    """
    if _CONFIG is None:
        return Path(DEFAULT_MODEL_CACHE_ROOT)
    return _CONFIG.cache_root


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
    if not _valid_model_id(model_id):
        raise ValueError("model_id must be a canonical cache identifier")

    cache_root = model_cache_root()
    model_dir = cache_root / model_id
    if (
        model_dir.is_dir()
        and (model_dir / READY_SENTINEL_NAME).is_file()
        and (model_dir / ARTIFACT_INVENTORY_NAME).is_file()
    ):
        _verify_warm_cache(model_dir)
        _touch_access_time(model_dir)
        _enforce_lru_quota(cache_root, model_id)
        return model_dir
    with _population_lease(cache_root, model_id):
        return _get_model_path(cache_root, model_id)


@contextmanager
def _population_lease(cache_root: Path, model_id: str) -> Iterator[None]:
    """Prevent concurrent adapters from mutating one model generation."""
    cache_root.mkdir(parents=True, exist_ok=True)
    root_fd = os.open(
        cache_root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    )
    try:
        try:
            os.mkdir(".infernix-population-locks", mode=0o700, dir_fd=root_fd)
        except FileExistsError:
            pass
        locks_fd = os.open(
            ".infernix-population-locks",
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=root_fd,
        )
        try:
            descriptor = os.open(
                model_id + ".held",
                os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK,
                0o600,
                dir_fd=locks_fd,
            )
            try:
                if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                    raise ModelCacheNotPopulated(
                        "model population lock is not a regular file"
                    )
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError as exc:
                    raise ModelCacheNotPopulated(
                        "another adapter is populating the model cache"
                    ) from exc
                yield
            finally:
                os.close(descriptor)
        finally:
            os.close(locks_fd)
    finally:
        os.close(root_fd)


def _get_model_path(cache_root: Path, model_id: str) -> Path:
    model_dir = cache_root / model_id
    ready_sentinel = model_dir / READY_SENTINEL_NAME
    _reconcile_interrupted_generations(cache_root, model_id)

    if model_dir.is_dir() and ready_sentinel.is_file():
        root_fd = os.open(
            model_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        )
        try:
            ready_fd = _open_cache_regular(root_fd, (READY_SENTINEL_NAME,))
            os.close(ready_fd)
            try:
                os.stat(ARTIFACT_INVENTORY_NAME, dir_fd=root_fd, follow_symlinks=False)
                inventory_present = True
            except FileNotFoundError:
                inventory_present = False
            if not inventory_present:
                _reconcile_warm_inventory(model_id, root_fd)
            _verify_artifact_inventory_at(root_fd)
        finally:
            os.close(root_fd)
        _touch_access_time(model_dir)
        _enforce_lru_quota(cache_root, model_id)
        return model_dir

    _populate_from_minio(model_id, model_dir)

    if not (model_dir.is_dir() and ready_sentinel.is_file()):
        raise ModelCacheNotPopulated(
            f"model {model_id!r} could not be populated from MinIO; "
            "the coordinator's bootstrap subscription may not have "
            "published the .ready sentinel for this model yet."
        )

    _enforce_lru_quota(cache_root, model_id)
    return model_dir


def _verify_warm_cache(model_dir: Path) -> None:
    root_fd = os.open(
        model_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    )
    try:
        ready_fd = _open_cache_regular(root_fd, (READY_SENTINEL_NAME,))
        os.close(ready_fd)
        _verify_artifact_inventory_at(root_fd)
    finally:
        os.close(root_fd)


def _reconcile_warm_inventory(model_id: str, root_fd: int) -> None:
    """Verify retained local bytes before publishing their durable identity."""
    config = _require_config()
    if not (
        config.minio_endpoint and config.minio_access_key and config.minio_secret_key
    ):
        raise ModelCacheNotPopulated(
            "MinIO connection details are required to reconcile a legacy cache"
        )
    try:
        import boto3
        from botocore.client import Config
        from botocore.exceptions import ClientError
    except ImportError as exc:
        raise ModelCacheNotPopulated(
            "boto3 is required to reconcile a legacy cache"
        ) from exc
    client = boto3.client(
        "s3",
        endpoint_url=config.minio_endpoint,
        aws_access_key_id=config.minio_access_key,
        aws_secret_access_key=config.minio_secret_key,
        region_name=config.minio_region,
        config=Config(s3={"addressing_style": "path"}, signature_version="s3v4"),
    )
    try:
        response = client.get_object(
            Bucket=config.models_bucket, Key=f"{model_id}/{ARTIFACT_INVENTORY_NAME}"
        )
    except ClientError as exc:
        if exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode") == 404:
            raise ModelCacheNotPopulated(
                "durable artifact identity inventory is missing"
            ) from exc
        raise
    body = response["Body"]
    try:
        extent = response.get("ContentLength")
        if type(extent) is not int or extent < 0 or extent > ARTIFACT_INVENTORY_LIMIT:
            raise ModelCacheNotPopulated(
                "durable artifact identity inventory exceeds its bound"
            )
        raw = body.read(ARTIFACT_INVENTORY_LIMIT + 1)
    finally:
        body.close()
    if len(raw) != extent:
        raise ModelCacheNotPopulated(
            "durable artifact identity inventory extent differs"
        )
    _verify_artifact_inventory_at(root_fd, raw)
    name = ".infernix-inventory-" + secrets.token_hex(16)
    descriptor = os.open(
        name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
        dir_fd=root_fd,
    )
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(raw)
        os.replace(
            name, ARTIFACT_INVENTORY_NAME, src_dir_fd=root_fd, dst_dir_fd=root_fd
        )
    finally:
        try:
            os.unlink(name, dir_fd=root_fd)
        except FileNotFoundError:
            pass


def _populate_from_minio(model_id: str, dest_dir: Path) -> None:
    """Stream every file under ``infernix-models/<model_id>/`` into ``dest_dir``.

    Refuses to write the local ``.ready`` sentinel until every object
    under the upstream prefix has been written and the upstream
    ``.ready`` object is also present, so a partial download leaves
    the local cache in a recoverable (re-poll) state rather than a
    false-ready state that would mislead the engine adapter.
    """
    config = _require_config()
    endpoint = config.minio_endpoint
    access_key = config.minio_access_key
    secret_key = config.minio_secret_key
    region = config.minio_region
    bucket = config.models_bucket

    if not (endpoint and access_key and secret_key):
        raise ModelCacheNotPopulated(
            f"MinIO connection details missing in the supplied "
            f"ModelCacheConfig; cannot populate model {model_id!r}. "
            "Populate config.minio_endpoint, config.minio_access_key, "
            "and config.minio_secret_key via configure()."
        )

    try:
        # boto3 is the supported S3 client. Importing inside the function
        # keeps unit tests that exercise the local-cache hit path runnable
        # without the dependency installed; the import only fires on a
        # genuine cache miss against MinIO. boto3 ships no py.typed marker;
        # the pyproject mypy override ignores its missing stubs so the
        # quality gate stays machine-independent.
        import boto3
        from botocore.client import Config
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
    entries = _list_minio_object_entries(client, bucket, prefix)
    keys = [key for key, _size in entries]
    relative_keys = [_strip_prefix(key, prefix) for key in keys]
    _validate_download_inventory(keys, relative_keys, prefix)
    declared_bytes = sum(
        size
        for (_key, size), relative in zip(entries, relative_keys, strict=True)
        if relative != READY_SENTINEL_NAME
    )

    if READY_SENTINEL_NAME not in relative_keys:
        raise ModelCacheNotPopulated(
            f"MinIO {bucket}/{prefix} is missing the {READY_SENTINEL_NAME} "
            "sentinel object. The coordinator's bootstrap subscription "
            "has not yet finished populating this model."
        )
    if ARTIFACT_INVENTORY_NAME not in relative_keys:
        raise ModelCacheNotPopulated(
            f"MinIO {bucket}/{prefix} is missing the artifact identity inventory; "
            "the coordinator must reconcile this retained model before hydration."
        )

    # Reserve the declared bytes before any write: other models are evicted
    # (idle ones only) until this generation fits, and a generation larger than
    # the whole quota is refused before it touches the disk.
    _enforce_lru_quota(dest_dir.parent, model_id, reserve_bytes=declared_bytes)

    # Hydrate into a private candidate generation, verify it there, and only
    # then replace the model directory. A failure or interruption before the
    # swap leaves the prior generation (or its absence) exactly as it was, and
    # leftover candidates are reconciled under the population lease.
    candidate_root = _candidate_root(dest_dir.parent)
    token = secrets.token_hex(16)
    candidate = candidate_root / f"{model_id}.candidate.{token}"
    os.mkdir(candidate, mode=0o700)
    published = False
    try:
        # Download every object except the sentinel first, then write the
        # local sentinel atomically last so a crashed populate leaves
        # `.ready` absent and the next call retries cleanly.
        root_fd = os.open(
            candidate, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        )
        try:
            remaining = config.quota_bytes
            for key, relative in zip(keys, relative_keys, strict=True):
                if relative == READY_SENTINEL_NAME:
                    continue
                object_limit = (
                    min(remaining, ARTIFACT_INVENTORY_LIMIT)
                    if relative == ARTIFACT_INVENTORY_NAME
                    else remaining
                )
                remaining -= _download_minio_object(
                    client, bucket, key, root_fd, relative, object_limit
                )
            _verify_artifact_inventory_at(root_fd)
            _publish_cache_ready(root_fd, INVENTORY_READY_MARKER)
        finally:
            os.close(root_fd)
        _swap_generation(candidate, dest_dir, candidate_root, model_id, token)
        published = True
    finally:
        if not published:
            shutil.rmtree(candidate, ignore_errors=True)


CANDIDATE_ROOT_NAME = ".infernix-candidates"


def _candidate_root(cache_root: Path) -> Path:
    """Return the cache's private candidate directory, refusing a symlink."""
    cache_root.mkdir(parents=True, exist_ok=True)
    root = cache_root / CANDIDATE_ROOT_NAME
    try:
        os.mkdir(root, mode=0o700)
    except FileExistsError:
        pass
    status = os.lstat(root)
    if not stat.S_ISDIR(status.st_mode):
        raise ModelCacheNotPopulated("model cache candidate root is not a directory")
    return root


def _swap_generation(
    candidate: Path, dest_dir: Path, candidate_root: Path, model_id: str, token: str
) -> None:
    """Replace ``dest_dir`` with a verified candidate, restoring on failure."""
    previous: Path | None = None
    if dest_dir.is_symlink() or dest_dir.exists():
        previous = candidate_root / f"{model_id}.previous.{token}"
        os.rename(dest_dir, previous)
    try:
        os.rename(candidate, dest_dir)
    except BaseException:
        if previous is not None:
            os.rename(previous, dest_dir)
        raise
    if previous is not None:
        # The new generation is already published; a failed removal leaves
        # residue that the next reconciliation deletes.
        shutil.rmtree(previous, ignore_errors=True)


def _reconcile_interrupted_generations(cache_root: Path, model_id: str) -> None:
    """Finish or discard what an interrupted generation swap left behind.

    Runs under the model's population lease. A leftover candidate was never
    published and is removed. A leftover previous generation is restored when
    the model directory is absent (the swap stopped between its two renames)
    and removed otherwise.
    """
    root = cache_root / CANDIDATE_ROOT_NAME
    if root.is_symlink() or not root.is_dir():
        return
    dest_dir = cache_root / model_id
    for entry in sorted(root.iterdir()):
        parts = entry.name.rsplit(".", 2)
        if len(parts) != 3 or parts[0] != model_id:
            continue
        kind = parts[1]
        if entry.is_symlink():
            entry.unlink()
        elif kind == "candidate":
            shutil.rmtree(entry)
        elif kind == "previous":
            if dest_dir.exists() or dest_dir.is_symlink():
                shutil.rmtree(entry)
            else:
                os.rename(entry, dest_dir)


def _publish_cache_ready(root_fd: int, marker: str) -> None:
    name = ".infernix-ready-" + secrets.token_hex(16)
    descriptor = os.open(
        name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
        dir_fd=root_fd,
    )
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(marker.encode("utf-8"))
        os.replace(name, READY_SENTINEL_NAME, src_dir_fd=root_fd, dst_dir_fd=root_fd)
    finally:
        try:
            os.unlink(name, dir_fd=root_fd)
        except FileNotFoundError:
            pass


def _list_minio_objects(client: Any, bucket: str, prefix: str) -> list[str]:
    """Return every object key under ``bucket/prefix`` (handles paginated lists)."""
    return [
        key
        for key, _size in _list_minio_object_entries(
            client, bucket, prefix, require_size=False
        )
    ]


def _list_minio_object_entries(
    client: Any, bucket: str, prefix: str, *, require_size: bool = True
) -> list[tuple[str, int]]:
    """Return ``(key, declared size)`` for every object under ``bucket/prefix``.

    The declared sizes are what a quota reservation is made against before any
    byte is written, so a listing entry without a non-negative integer size is
    refused rather than counted as zero.
    """
    paginator = client.get_paginator("list_objects_v2")
    entries: list[tuple[str, int]] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []) or []:
            key = item.get("Key")
            if not isinstance(key, str) or not key or len(key) > 4096:
                raise ModelCacheNotPopulated("model object listing has an invalid key")
            if len(entries) >= MODEL_OBJECT_COUNT_LIMIT:
                raise ModelCacheNotPopulated(
                    "model object listing exceeds its entry bound"
                )
            size = item.get("Size")
            if isinstance(size, bool) or not isinstance(size, int) or size < 0:
                if require_size:
                    raise ModelCacheNotPopulated(
                        "model object listing entry lacks a valid declared size"
                    )
                size = 0
            entries.append((key, size))
    return entries


def _validate_download_inventory(
    keys: list[str], relatives: list[str], prefix: str
) -> None:
    """Refuse unsafe or conflicting object names before making any writes."""
    seen: set[str] = set()
    for key, relative in zip(keys, relatives, strict=True):
        parts = relative.split("/")
        if (
            not key.startswith(prefix)
            or not relative
            or len(relative) > 4096
            or "\\" in relative
            or any(not part or part in {".", ".."} for part in parts)
            or any(
                ord(character) < 32 or ord(character) == 127 for character in relative
            )
            or relative in seen
            or any(part.endswith(".tmp") for part in parts)
        ):
            raise ModelCacheNotPopulated(
                "model object inventory has an unsafe or duplicate path"
            )
        seen.add(relative)
    for relative in seen:
        parts = relative.split("/")
        if any("/".join(parts[:index]) in seen for index in range(1, len(parts))):
            raise ModelCacheNotPopulated("model object inventory has conflicting paths")


def _download_minio_object(
    client: Any, bucket: str, key: str, root_fd: int, relative: str, limit: int
) -> int:
    """Stream to an exclusively created file below descriptor-anchored directories."""
    parts = relative.split("/")
    with ExitStack() as stack:
        parent = root_fd
        for component in parts[:-1]:
            try:
                os.mkdir(component, mode=0o700, dir_fd=parent)
            except FileExistsError:
                pass
            parent = os.open(
                component,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                dir_fd=parent,
            )
            stack.callback(os.close, parent)
        temp_name = ".infernix-download-" + secrets.token_hex(16)
        descriptor = os.open(
            temp_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
            dir_fd=parent,
        )
        try:
            with os.fdopen(descriptor, "wb") as handle:
                response = client.get_object(Bucket=bucket, Key=key)
                body = response["Body"]
                try:
                    expected = response.get("ContentLength")
                    if type(expected) is not int or expected < 0 or expected > limit:
                        raise ModelCacheQuotaExceeded(
                            "model object exceeds the remaining download bound"
                        )
                    observed = 0
                    while chunk := body.read(min(1024 * 1024, expected - observed + 1)):
                        observed += len(chunk)
                        if observed > expected:
                            raise ModelCacheNotPopulated(
                                "model object exceeds its declared extent"
                            )
                        handle.write(chunk)
                    if observed != expected:
                        raise ModelCacheNotPopulated(
                            "model object ended before its declared extent"
                        )
                finally:
                    body.close()
            os.replace(temp_name, parts[-1], src_dir_fd=parent, dst_dir_fd=parent)
            return observed
        finally:
            try:
                os.unlink(temp_name, dir_fd=parent)
            except FileNotFoundError:
                pass


def _strip_prefix(key: str, prefix: str) -> str:
    return key[len(prefix) :] if key.startswith(prefix) else key


def _valid_model_id(model_id: str) -> bool:
    if not model_id or not model_id[0].isascii() or not model_id[0].isalnum():
        return False
    previous_separator = False
    for character in model_id:
        if character.isascii() and (character.islower() or character.isdigit()):
            previous_separator = False
        elif character in "._-" and not previous_separator:
            previous_separator = True
        else:
            return False
    return not previous_separator


def _enforce_lru_quota(
    cache_root: Path, current_model_id: str, reserve_bytes: int | None = None
) -> None:
    """Evict least-recently-used model entries when the cache exceeds quota.

    A victim is removed only while its engine cache lock is held exclusively.
    The current model and models whose execution or mutation holds a shared or
    exclusive lease are never evicted.

    With ``reserve_bytes`` the current model is charged its declared size
    instead of whatever partial files it holds, so the check is a reservation
    made before a download rather than a check after it. A reservation larger
    than the whole quota is refused outright. Concurrent downloads of different
    models are each reserved against the sizes on disk at that moment; bytes
    another download has not yet written are not counted.
    """
    quota_bytes = _cache_quota_bytes()
    if reserve_bytes is not None and reserve_bytes > quota_bytes:
        raise ModelCacheQuotaExceeded(
            "model generation is larger than the whole model cache quota"
        )
    if not cache_root.is_dir():
        return
    entries = sorted(
        (
            entry
            for entry in cache_root.iterdir()
            if not entry.name.startswith(".")
            and entry.is_dir()
            and not entry.is_symlink()
        ),
        key=lambda entry: entry.stat().st_atime,
    )
    if not entries:
        return

    total_bytes = sum(
        (
            reserve_bytes
            if reserve_bytes is not None and entry.name == current_model_id
            else _directory_size_bytes(entry)
        )
        for entry in entries
    )
    if reserve_bytes is not None and not any(
        entry.name == current_model_id for entry in entries
    ):
        total_bytes += reserve_bytes
    if total_bytes <= quota_bytes:
        return
    for victim in entries:
        if total_bytes <= quota_bytes:
            break
        if (
            victim.name == current_model_id
            or victim.name in {"apple-silicon", "linux-cpu", "linux-gpu"}
            or not _valid_model_id(victim.name)
        ):
            continue
        sentinel = victim / READY_SENTINEL_NAME
        if sentinel.is_symlink() or not sentinel.is_file():
            continue
        lock_root = cache_root / ".infernix-model-locks"
        lock_root.mkdir(parents=True, exist_ok=True)
        lock_path = lock_root / f"{victim.name}.held"
        descriptor = os.open(
            lock_path,
            os.O_WRONLY | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK,
            0o600,
        )
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise ModelCacheQuotaExceeded("cache lock is not a regular file")
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                continue
            victim_size = _directory_size_bytes(victim)
            shutil.rmtree(victim)
            total_bytes -= victim_size
        finally:
            os.close(descriptor)
    if total_bytes > quota_bytes:
        raise ModelCacheQuotaExceeded(
            "model cache exceeds its quota and no idle model can free enough space"
        )


def _cache_quota_bytes() -> int:
    # Phase 5 Sprint 5.9 follow-on (May 26, 2026): quota now comes
    # from the typed ModelCacheConfig the engine daemon passes via
    # configure().
    if _CONFIG is None:
        return DEFAULT_QUOTA_BYTES
    return _CONFIG.quota_bytes


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
