"""Uniform per-adapter model-cache helper.

Phase 7 Sprint 7.7 routes every adapter through this module so engine pods
load model weights from the MinIO ``infernix-models`` bucket on first use
and reuse a bounded on-disk cache under ``/model-cache`` on subsequent
requests, regardless of whether the underlying engine library supports
bytes-loading natively.

The helper exposes one stable entry point::

    from adapters.model_cache import get_model_path

    weights_dir = get_model_path("audio-bark-small")

``get_model_path`` is idempotent: first call for a given ``model_id`` waits
on the coordinator-published ``.ready`` sentinel and then materializes a
local mirror under ``/model-cache/<model_id>/``; subsequent calls return
the existing path immediately. The MinIO download client and LRU eviction
loop both live here so per-adapter wrappers can stay thin.

Implementation notes
--------------------

The actual MinIO client wiring and LRU eviction land together with the
Sprint 7.14 chaos suite that proves the bootstrap/Failover semantics under
real Pulsar. Until then this module is a contract-only scaffold: it owns
the supported call shape, the cache root, and the failure mode that
adapters surface when the cache is empty so a future commit can drop in
the real client without churning every adapter again.

When ``/model-cache/<model_id>/`` already contains a ``.ready`` sentinel
the helper returns that path. When it does not, the call raises a clear
``ModelCacheNotPopulated`` error pointing at the supported bootstrap path
so adapter logs name the right next step instead of crashing with an
opaque ``FileNotFoundError``.
"""

from __future__ import annotations

import os
from pathlib import Path

__all__ = [
    "ModelCacheNotPopulated",
    "get_model_path",
    "model_cache_root",
    "READY_SENTINEL_NAME",
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


class ModelCacheNotPopulated(RuntimeError):
    """Raised when ``get_model_path`` is called before the coordinator has
    populated the requested model into the local ``/model-cache`` mirror.

    The supported recovery path is for the engine to publish a
    ``model.bootstrap.request`` envelope on the ``infernix/system``
    namespace and wait for the matching ``.ready`` event. Engine pods on
    real clusters reach this state only on first use of a model on a
    given node; subsequent calls reuse the cached copy.
    """


def model_cache_root() -> Path:
    """Return the absolute root path the engine reads cached weights from.

    Honours ``INFERNIX_MODEL_CACHE_ROOT`` so isolated daemon runs and unit
    tests can redirect the helper without mutating ``/model-cache``.
    """
    configured = os.environ.get("INFERNIX_MODEL_CACHE_ROOT")
    return Path(configured) if configured else Path(DEFAULT_MODEL_CACHE_ROOT)


def get_model_path(model_id: str) -> Path:
    """Return the local cache directory for ``model_id``.

    Contract:

    * The directory is guaranteed to contain every file the engine needs
      to load the model offline before this function returns.
    * The directory tree is read-only from the adapter's perspective;
      eviction is owned by this module's background reaper, not by the
      caller.
    * Calls are idempotent — repeat calls return the same path without
      touching MinIO or Pulsar.

    Raises ``ModelCacheNotPopulated`` if the local mirror is missing or
    incomplete. The engine entrypoint catches that exception, publishes a
    ``model.bootstrap.request`` envelope, and reschedules itself when the
    coordinator broadcasts the matching ``.ready`` event.
    """
    if not model_id:
        raise ValueError("model_id must be non-empty")

    cache_root = model_cache_root()
    model_dir = cache_root / model_id
    ready_sentinel = model_dir / READY_SENTINEL_NAME

    if model_dir.is_dir() and ready_sentinel.is_file():
        return model_dir

    raise ModelCacheNotPopulated(
        f"model {model_id!r} is not present at {model_dir} yet; "
        "the engine should publish a model.bootstrap.request envelope on "
        "the infernix/system namespace and wait for the coordinator to "
        "write the .ready sentinel before retrying."
    )
