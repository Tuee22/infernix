# Object Storage

**Status**: Authoritative source
**Referenced by**: [model_lifecycle.md](model_lifecycle.md), [../architecture/runtime_modes.md](../architecture/runtime_modes.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Define the supported object-storage contract: which MinIO
> buckets exist, what they hold, who reads and writes them, and how the
> coordinator's eager model-cache staging workflow populates platform model
> weights (on startup from the mounted `infernix.dhall`, with exactly-once semantics) while engine
> software artifacts stay separate from model weights.

## Current Status

The implemented object-storage contract uses three MinIO buckets:
`infernix-models` for platform model weights, `infernix-engine-artifacts` for immutable
content-addressed engine software payloads, and `infernix-demo-objects` for user uploads and
engine-generated demo artifacts. Engine software payloads are distinct from model weights and
from user-visible generated artifacts.
`src/Infernix/Runtime/Cache.hs` is structured around
`modelCacheRoot/<runtimeMode>/<modelId>/manifest.pb` so manifests sit
beside the cached weights, and the durable-source URI shape used by
the cache-status payload and the `RuntimeManifest` proto is
`minio://infernix-models/<modelId>/`. Engines pull weights from MinIO;
no on-host filesystem path pretends to be S3.

## Bucket Inventory

The supported shape uses three MinIO buckets and nothing else:

| Bucket | Gating | Key layout | Purpose |
|---|---|---|---|
| `infernix-models` | Always-on (not demo-gated) | `<modelId>/<filename>` plus a per-model `<modelId>/.ready` sentinel object | Platform-owned model weights, tokenizers, and configs. Eagerly staged by the coordinator on startup from the mounted `infernix.dhall` model set (a `warm-model-cache` cluster-up barrier blocks until every model is `.ready`). Read by Linux engine pods and by Apple host engine members. |
| `infernix-engine-artifacts` | Always-on (not demo-gated) | `sha256/<digest>` plus optional adapter pointers such as `<substrate>/<adapterId>/<version>/manifest.pb` | Immutable engine software payloads: wheelhouses, native binaries, Core ML compiled models, JVM tools, and reusable Apple or Linux materialization payloads. Model weights never live here. |
| `infernix-demo-objects` | Demo-gated (absent when `demo_ui = false`) | `users/<userId>/contexts/<contextId>/uploads/<objectKey>` and `users/<userId>/contexts/<contextId>/generated/<objectKey>` | User uploads and non-text INPUTS — audio and image references (browser → webapp object proxy) on the `uploads/` prefix — plus real per-family engine-generated ARTIFACT results (source-separation stems, audio-to-MIDI / music-transcription MIDI and MusicXML, generated images, video, and audio) written server-side to the `generated/` prefix. Read by the browser only through `/api/objects`; the browser never receives a presigned MinIO URL. This is the only demo/user artifact bucket; the retired `infernix-runtime` and `infernix-results` buckets are not part of the supported contract. |

## Bucket Scope Policies

- `infernix-models` is read by every engine and the coordinator's
  bootstrap worker; only the coordinator's service account has PUT
  permission. The bucket is not browser-addressable directly; weights
  never leave the cluster.
- `infernix-engine-artifacts` is read by controlled materialization
  commands and engine pods that need reusable software payloads. Writes
  are content-addressed and immutable; mutable adapter pointers, when
  present, are compare-and-swap style publication records rather than
  payload overwrites.
- `infernix-demo-objects` restricts every object path to the authenticated user's `sub`-derived
  prefix. The `infernix-demo` webapp is the single server-side mediator
  for these objects: the browser uploads and downloads through the webapp's `/api/objects`
  endpoints, the key is derived server-side from the verified `sub`, and the browser is never handed
  a presigned MinIO URL. See
  [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md) for the
  single-mediator contract and
  [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md) for
  the per-user `sub`-prefix isolation rule, and [../tools/minio.md](../tools/minio.md) for the
  bucket layout. **Current Status**: browser upload/download proxying is implemented (Phase 7 Sprint
  7.25 webapp object-proxy; Phase 3 Sprint 3.13 removed the `/minio/s3` route +
  `presignPublicEndpoint`). Sprint 7.28 makes the engine/coordinator path derive every generated
  output target under `users/<sub>/contexts/<ctx>/generated/`; Wave N closes the full selected
  `linux-gpu` plus `linux-cpu` cohort validation.
- Phase 9 Sprint 9.7 adds an IAM-layer defense-in-depth for per-user `infernix-demo-objects`
  operations: when `cluster.minio.stsPerUser` is enabled, the object-proxy first exchanges the
  shared root credential for a short-lived MinIO STS credential scoped to `users/<sub>/*` (an inline
  `AssumeRole` session policy), in addition to the server-side `pathBelongsToUser` check. The
  presigned-URL minter supports an optional STS session token threaded into the signed S3 query as
  `X-Amz-Security-Token`. See
  [../architecture/access_control_doctrine.md](../architecture/access_control_doctrine.md).
- Cross-bucket access is not part of the supported contract.

## Engine Software Artifacts

Engine software artifacts are not model weights. They use their own
content-addressed contract so the platform can cache expensive engine payloads
without confusing them with Hugging Face checkpoints, GitHub release model
files, or user-visible generated artifacts.

The materialization flow is:

1. Resolve a typed engine-artifact manifest for `(substrate, adapterId,
   artifactKind, version, architecture)`.
2. If the manifest names a MinIO object key, fetch the immutable payload from
   `infernix-engine-artifacts`.
3. Materialize into a temporary local directory under the active engine-install
   root.
4. Validate the manifest contract and run the manifest's smoke/load command before rename.
5. Rename atomically into `./.data/engines/<adapterId>/` on Apple or into the
   image-owned `/opt/infernix/engines/<adapterId>/` root on Linux.
6. Ack the materialization work only after the local root is complete.

Failed materialization leaves no partial final root and is retryable. Pulsar
redelivery or negative acknowledgement owns retry semantics for asynchronous
materialization work.

## Engine Model-Weight Loading

Every Python engine adapter loads model weights through one shared helper:
`python/adapters/model_cache.py`, exposing the function
`get_model_path(model_id) -> filesystem path`. The Haskell worker passes
model-cache and MinIO wiring on the private worker request, and the Python
stdio harness configures the helper before invoking adapter logic. Every
Python adapter calls it regardless of underlying engine family; there is no
bytes-loading branch.

The helper:

1. Checks `/model-cache/<modelId>/.ready` on the engine pod's
   `emptyDir` mount. If present, returns the path immediately.
2. If absent, checks `infernix-models/<modelId>/.ready` in MinIO. Under eager staging the
   coordinator has already populated the bucket at startup, so `.ready` is normally present; the
   helper downloads every file under `infernix-models/<modelId>/` to `/model-cache/<modelId>/`,
   enforcing the cache's LRU eviction policy if the `emptyDir` `sizeLimit` is being approached.
   - Fallback only: if a model is somehow not yet staged, the helper publishes a request to
     `infernix/system/model.bootstrap.request` (producer dedup key = `modelId`) and subscribes to
     `model.bootstrap.ready.<modelId>` with a bounded timeout — the same coordinator worker services
     it. This is a safety net, not the hot path.
3. Returns the local filesystem path.

The model cache is ephemeral: a pod restart wipes `/model-cache/` and
the next load repopulates from MinIO. Aggressive eviction is by
design — the user explicitly accepted repeated MinIO pulls as the
price of true daemon statelessness. This LRU policy bounds the on-DISK
model cache only; it places no bound on resident inference RAM. On the
`apple-silicon` substrate there are no in-cluster engine pods — all
active models run serialized one-at-a-time as fresh subprocesses on the
on-host `infernix service` daemon, with no per-model RAM footprint, no
inference-RAM budget, no admission control, and no RAM eviction, so peak
resident memory is UNBOUNDED. A full per-model `infernix test integration`
run over the current 16-model catalog exhausted host RAM and the daemon
was OS-OOM-killed (an uncontrolled SIGKILL, not a clean `status=failed`).
Closing this host-memory gap is reopened as Phase 4 Sprint 4.26
(apple-silicon inference RAM admission + bounded peak) with Phase 6
Sprint 6.37 (apple-silicon memory-bounded validation lane).

**RAM admission is a distinct bound from the disk cache quota.** The
`emptyDir` `/model-cache` `sizeLimit` (`engine.modelCache.sizeLimit` /
`engineModelCacheQuotaBytes`) LRU quota bounds DISK — how many staged
model weights sit on the cache mount before least-recently-used weights
are evicted — and does not govern resident MEMORY. Resident inference
memory is bounded separately by a RAM-admission contract: each
`ModelDescriptor` carries a conservative peak host-resident footprint
`modelRamFootprintMib`, and each substrate resolves an
`inferenceRamBudgetMib` (on `apple-silicon`, host physical RAM minus the
colima VM pledge minus a host reserve). The RAM budget governs whether an
inference is ADMITTED — the serialized on-host apple engine publishes a
clean `status=failed` for an over-budget model before launching the
engine subprocess — while the disk quota governs LRU EVICTION of staged
weights; the two are orthogonal (a model can be cache-resident on disk
yet refused admission on RAM, or admitted on RAM while its weights were
just evicted from disk and must be re-pulled). Because execution is
serialized to one admitted model under a single lock, peak resident
memory is bounded, so the former host-RAM gap noted above is now closed:
the daemon fails cleanly and is never OS-OOM-killed by construction
(Phase 4 Sprint 4.26, validated by Phase 6 Sprint 6.37).

For real per-family artifact inference outputs (source-separation
stems, audio-to-MIDI and music-transcription MIDI / MusicXML,
generated images, video, and audio), the supported target is a
server-derived object under
`infernix-demo-objects/users/<sub>/contexts/<ctx>/generated/`. The result
payload carries an `ObjectRef` (bucket + key) resolved on browser read
through the webapp `/api/objects` proxy. These artifacts are always
written to `infernix-demo-objects` — never to the retired
`infernix-runtime` or `infernix-results` buckets, which are not part of
the supported contract. Text outputs from the LLM and speech families
ride inline in the protobuf result message and never touch object
storage.

Sprint 7.28 makes this target Haskell-owned:
`WorkerRequest` carries the generated-output prefix derived from
`userId` + `contextId`, Python adapters reject missing or invalid
generated-output targets, native-process-runner artifact uploads use the
same prefix, and the result bridge rejects raw or cross-user generated
object refs. Wave N closes the full selected `linux-gpu` plus
`linux-cpu` cohort validation.

Non-text INPUTS are carried the same way: an audio or image input is
staged into `infernix-demo-objects` under the per-user `uploads/`
prefix and referenced on the request as a typed object reference,
rather than inlined. `ResultPayload` carries the
`oneof {inline_output, object_ref}` discriminant on the wire, and
`buildPayload` routes text families to inline output and artifact
families to object references. The newer proto fields are a non-text
INPUT object reference on `InferenceRequest` / `WorkerRequest` and an
object-reference OUTPUT on `WorkerResponse` for the artifact adapters.
For native-process-runner artifact families, the child process may return a local artifact-file
marker instead of doing its own MinIO write; the Haskell worker uploads that file to the same
Haskell-derived generated-object target using secret-backed presigned PUT credentials and publishes
the same object-reference output shape.

## Coordinator Model-Cache Staging Workflow

On startup the coordinator eagerly stages every model listed in the mounted `infernix.dhall`,
iterating the model set and running the staging steps below for each; the `warm-model-cache`
cluster-up barrier blocks until all are `.ready`. The same steps also service the fallback
`persistent://infernix/system/model.bootstrap.request` Failover subscription (alongside the
single-flight dispatcher and the result-bridge) when an engine hits an unstaged model. Per model:

1. Take the `modelId` (from the mounted config's model set, or a fallback bootstrap request).
2. Re-check `infernix-models/<modelId>/.ready` in MinIO (idempotent
   guard against duplicate work after restart or Failover handoff).
   - If present, publish `model.bootstrap.ready.<modelId>` and continue.
3. Otherwise, look up the upstream `downloadUrl` for `modelId` in the
   mounted `infernix.dhall` catalog.
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
- Producer dedup on the request topic uses an attempt-scoped
  `modelId@requestedAt` sequence id while the Pulsar message key stays
  `modelId` — exact request replays collapse, but later retry attempts
  can enqueue work if readiness never appears.
- The `.ready` sentinel written last — partial uploads are not
  visible to engines because the sentinel is the gate.

**Failure mode**: if the active coordinator dies mid-upload, Pulsar
redelivers the unacked request to a surviving coordinator replica.
The replica re-checks MinIO (idempotent guard) and either notices the
upload is already complete (`.ready` present) and publishes the ready
event, or restarts the download from scratch. The Failover subscription,
attempt-scoped request dedup, and the `.ready` sentinel guarantee at most
one effective publication.

## Daemon Disk Posture

**No daemon has a PVC.** The engine pod uses a single ephemeral
`emptyDir` volume mounted at `/model-cache` with hard `sizeLimit`
(default `64Gi`, chart values knob `engine.modelCache.sizeLimit`).
Kubelet enforces the limit so the pod cannot exhaust node DISK; the
adapter helper enforces LRU eviction inside the quota. On the Apple
on-host engine daemon, an equivalent host-local cache lives under
`./.data/runtime/model-cache/`; it is purgeable host state on the
operator's machine, not durable cluster state. This posture bounds DISK
only: neither kubelet nor the adapter helper bounds resident inference
RAM, and the `apple-silicon` on-host daemon has no RAM budget, admission
control, or eviction at all — so this is not a complete resource-safety
story. See the host inference-RAM gap under Engine Model-Weight Loading
and Validation (reopened as Phase 4 Sprint 4.26 + Phase 6 Sprint 6.37).

Browsers fetch generated artifacts exclusively through the webapp's
`/api/objects` endpoints against the `infernix-demo-objects` MinIO
bucket. Those endpoints stream the bytes
server-side and the browser never receives a presigned MinIO URL (see
[../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)).
**Current Status**: implemented for browser reads (Phase 7 Sprint 7.25; Phase 3 Sprint 3.13 removed
the `/minio/s3` route). Sprint 7.28 now also derives generated-artifact write targets under the same
user/context prefix, and Wave N closes the full selected `linux-gpu` plus `linux-cpu` cohort
validation.

## Routed Surface

The `/api/objects` HTTP endpoints on the demo backend (demo-only,
JWT-validated) are the single mediator for browser artifact I/O against
the authenticated user's `sub`-derived prefix in `infernix-demo-objects`.
The webapp reads and writes MinIO server-side
over the cluster-internal endpoint and streams artifact bytes through
its own `/api/objects/{upload,download}` surface; the browser holds only
the webapp origin and never a presigned MinIO URL (see
[../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)).
**Current Status**: implemented for browser-originated object operations (Phase 7 Sprint 7.25; Phase 3
Sprint 3.13 removed the `/minio/s3` route + `presignPublicEndpoint`); generated engine artifact
prefix ownership is closed by Phase 7 Sprint 7.28 and Wave N. The supported
MIME contract for browser-rendered artifacts (image, audio, video,
text/JSON preview, browser-native PDF, MIDI / MusicXML / ZIP-stem
rendering, and generic-binary download) lives in
[../architecture/demo_app_design.md](../architecture/demo_app_design.md)
and [../tools/minio.md](../tools/minio.md); model-weight or runtime
formats are not upload MIME families.

The routed Linux GPU E2E flow validates the server-side
`/api/objects/download` grant disposition for those MIME classes.

## Validation

- `infernix lint docs` enforces this doc's metadata block and
  cross-reference resolution.
- `infernix test integration` covers the model-cache staging workflow:
  the coordinator eagerly stages the mounted config's models at startup so `infernix-models` is
  populated before serving, and the `.ready` sentinel appears exactly once even under concurrent
  staging (and under the fallback path's concurrent requests from N engine pods).
- `infernix test integration` covers the `emptyDir` DISK LRU eviction
  policy in the adapter helper on the Linux engine pod: sustained load
  does not exhaust ephemeral storage and does not restart the engine pod.
  This validated bound is DISK-only. Host inference RAM on the
  `apple-silicon` substrate is UNBOUNDED — active models run serialized as
  fresh subprocesses on the on-host `infernix service` daemon with no RAM
  budget, admission control, or eviction, and a full per-model
  `infernix test integration` run over the current 16-model catalog
  exhausted host RAM and the daemon was OS-OOM-killed (an uncontrolled
  SIGKILL, not a clean `status=failed`). This is a known, still-open gap:
  the realness "fail cleanly, never crash" contract is not yet satisfied
  for host memory on `apple-silicon`. It is reopened as Phase 4 Sprint 4.26
  (apple-silicon inference RAM admission + bounded peak) with Phase 6
  Sprint 6.37 (apple-silicon memory-bounded validation lane).
- `infernix test e2e` covers `/api/objects` upload/download through the webapp proxy from a real
  Keycloak JWT, same-user routed byte equality, and cross-user object-prefix isolation for two
  Keycloak users with the same context id and display name.
- Phase 7 Sprint 7.28 unit and integration-build validation covers Haskell-derived generated-output
  prefixes for Python adapters, native process runners, and the result bridge so artifact outputs
  cannot bypass the `users/<sub>/contexts/<ctx>/generated/` layout; Wave N closes the full selected
  `linux-gpu` plus `linux-cpu` routed real-output validation.
- Production-shape test (`demo_ui = false`) confirms `infernix-models`
  and `infernix-engine-artifacts` are present, `infernix-demo-objects`
  is absent, and no daemon has a PVC.

## Cross-References

- [edge_routing.md](edge_routing.md)
- [model_lifecycle.md](model_lifecycle.md)
- [implementation_boundaries.md](implementation_boundaries.md)
- [k8s_storage.md](k8s_storage.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)
- [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../tools/minio.md](../tools/minio.md)
- [../tools/pulsar.md](../tools/pulsar.md)
