# Object Storage

**Status**: Authoritative source
**Referenced by**: [model_lifecycle.md](model_lifecycle.md), [../architecture/runtime_modes.md](../architecture/runtime_modes.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Define the supported object-storage contract: which MinIO
> buckets exist, what they hold, who reads and writes them, and how the
> coordinator's lazy model-bootstrap workflow populates platform model
> weights with exactly-once semantics.

## Current Status

The supported object-storage contract uses two MinIO buckets:
`infernix-models` always-on and `infernix-demo-objects` demo-gated.
`src/Infernix/Runtime/Cache.hs` is structured around
`modelCacheRoot/<runtimeMode>/<modelId>/manifest.pb` so manifests sit
beside the cached weights, and the durable-source URI shape used by
the cache-status payload and the `RuntimeManifest` proto is
`minio://infernix-models/<modelId>/`. Engines pull weights from MinIO;
no on-host filesystem path pretends to be S3.

## Bucket Inventory

The supported target shape uses two MinIO buckets and nothing else:

| Bucket | Gating | Key layout | Purpose |
|---|---|---|---|
| `infernix-models` | Always-on (not demo-gated) | `<modelId>/<filename>` plus a per-model `<modelId>/.ready` sentinel object | Platform-owned model weights, tokenizers, and configs. Populated lazily by the coordinator's model-bootstrap Failover subscription on first use. Read by every engine pod (Linux substrates) and by the on-host engine daemon (Apple silicon). |
| `infernix-demo-objects` | Demo-gated (absent when `demo_ui = false`) | `users/<userId>/contexts/<contextId>/uploads/<objectKey>` and `users/<userId>/contexts/<contextId>/generated/<objectKey>` | User uploads (browser → presigned PUT) plus engine-generated artifacts (image PNGs, audio WAVs, video frames, MusicXML) written by the engine adapter on the `generated/` prefix. Read by the browser via presigned GET URLs minted at `/api/objects`. |

## Bucket Scope Policies

- `infernix-models` is read by every engine and the coordinator's
  bootstrap worker; only the coordinator's service account has PUT
  permission. The bucket is not browser-addressable directly; weights
  never leave the cluster.
- `infernix-demo-objects` uses per-user grant-minting scope checks that restrict
  the default object path to the authenticated user's prefix. Presigned URLs are bearer
  capabilities until expiry, so callers must treat them as session-confidential. See
  [../tools/minio.md](../tools/minio.md) for the policy details.
- Cross-bucket access is not part of the supported contract.

## Engine Model-Weight Loading

Every engine adapter loads model weights through one shared helper:
`python/adapters/common/model_cache.py`, exposing the function
`get_model_path(model_id) -> filesystem path`. Every adapter calls it
regardless of underlying engine family; there is no bytes-loading
branch.

The helper:

1. Checks `/model-cache/<modelId>/.ready` on the engine pod's
   `emptyDir` mount. If present, returns the path immediately.
2. If absent, checks `infernix-models/<modelId>/.ready` in MinIO.
   - If absent, publishes a request to
     `infernix/system/model.bootstrap.request` with producer dedup
     key = `modelId`, then subscribes to
     `model.bootstrap.ready.<modelId>` with a bounded timeout. The
     coordinator's bootstrap worker handles the upload (see below).
   - When `.ready` appears in MinIO, downloads every file under
     `infernix-models/<modelId>/` to `/model-cache/<modelId>/`,
     enforcing the cache's LRU eviction policy if the `emptyDir`
     `sizeLimit` is being approached.
3. Returns the local filesystem path.

The model cache is ephemeral: a pod restart wipes `/model-cache/` and
the next load repopulates from MinIO. Aggressive eviction is by
design — the user explicitly accepted repeated MinIO pulls as the
price of true daemon statelessness.

For binary inference outputs (image PNGs, audio WAVs, video frames,
large MusicXML), the engine adapter PUTs the bytes directly into
`infernix-demo-objects` at the appropriate per-user prefix and the
result payload carries an `ObjectRef` (bucket + key). Text outputs
ride inline in the protobuf result message and never touch object
storage.

## Coordinator Model-Bootstrap Workflow

The coordinator's third Failover subscription type (alongside the
single-flight dispatcher and the result-bridge) consumes
`persistent://infernix/system/model.bootstrap.request`:

1. Receive bootstrap request carrying `modelId`.
2. Re-check `infernix-models/<modelId>/.ready` in MinIO (idempotent
   guard against duplicate work after Failover handoff).
   - If present, publish `model.bootstrap.ready.<modelId>` and ack.
3. Otherwise, look up the upstream `downloadUrl` for `modelId` in the
   active substrate's staged `.dhall` catalog.
4. HTTP `GET` the upstream URL (this is the only point in the
   supported daemon topology that reaches the public internet — Hugging
   Face, GitHub releases, etc.).
5. `PUT` each file under `infernix-models/<modelId>/<filename>`.
6. `PUT infernix-models/<modelId>/.ready` last; this sentinel marks
   the upload as atomically visible.
7. Publish `model.bootstrap.ready.<modelId>` on the corresponding
   ready-event topic family.
8. Ack the bootstrap request.

**Exactly-once semantics** come from:

- Pulsar named `Failover` subscription on the request topic — exactly
  one coordinator replica processes a given `modelId` at a time.
- Producer dedup on the request topic keyed by `modelId` — concurrent
  retries from multiple engine pods collapse to one queued request.
- The `.ready` sentinel written last — partial uploads are not
  visible to engines because the sentinel is the gate.

**Failure mode**: if the active coordinator dies mid-upload, Pulsar
redelivers the unacked request to a surviving coordinator replica.
The replica re-checks MinIO (idempotent guard) and either notices the
upload is already complete (`.ready` present) and publishes the ready
event, or restarts the download from scratch. Producer dedup on the
inference result topic and the `.ready` sentinel guarantee at most
one effective publication.

## Daemon Disk Posture

**No daemon has a PVC.** The engine pod uses a single ephemeral
`emptyDir` volume mounted at `/model-cache` with hard `sizeLimit`
(default `32Gi`, chart values knob `engine.modelCache.sizeLimit`).
Kubelet enforces the limit so the pod cannot exhaust node disk; the
adapter helper enforces LRU eviction inside the quota. On the Apple
on-host engine daemon, an equivalent host-local cache lives under
`./.data/runtime/model-cache/`; it is purgeable host state on the
operator's machine, not durable cluster state.

Browsers fetch generated artifacts exclusively through `/api/objects`-
minted presigned URLs against the `infernix-demo-objects` MinIO
bucket.

## Routed Surface

The `/api/objects` HTTP endpoint on the demo backend (demo-only,
JWT-validated) mints presigned PUT and GET URLs scoped to the
authenticated user's prefix in `infernix-demo-objects`. Artifact bytes
flow directly between the browser and MinIO; the demo backend never
proxies artifact bytes on the durable-context path. The supported
MIME contract for browser-rendered artifacts (image, audio, video,
text/JSON preview, browser-native PDF, MIDI / MusicXML download-only,
and generic-binary download) lives in
[../architecture/demo_app_design.md](../architecture/demo_app_design.md)
and [../tools/minio.md](../tools/minio.md); model-weight or runtime
formats are not upload MIME families.

The routed Linux GPU E2E flow validates the server-side
`/api/objects/download` grant disposition for those MIME classes.

## Validation

- `infernix lint docs` enforces this doc's metadata block and
  cross-reference resolution.
- `infernix test integration` covers the model-bootstrap workflow:
  first-use download triggers the coordinator's bootstrap subscription,
  `.ready` sentinel appears exactly once even under concurrent
  bootstrap requests from N engine pods.
- `infernix test integration` covers the `emptyDir` LRU eviction
  policy in the adapter helper: sustained load does not exhaust
  ephemeral storage and does not restart the engine pod.
- `infernix test e2e` covers `/api/objects` grant minting from a real
  Keycloak JWT, same-user routed presigned MinIO PUT/GET byte equality,
  and cross-user object-prefix isolation for two Keycloak users with
  the same context id and display name.
- Production-shape test (`demo_ui = false`) confirms `infernix-models`
  is present, `infernix-demo-objects` is absent, and no daemon has a
  PVC.

## Cross-References

- [edge_routing.md](edge_routing.md)
- [model_lifecycle.md](model_lifecycle.md)
- [implementation_boundaries.md](implementation_boundaries.md)
- [k8s_storage.md](k8s_storage.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../tools/minio.md](../tools/minio.md)
- [../tools/pulsar.md](../tools/pulsar.md)
