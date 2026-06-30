# MinIO

**Status**: Authoritative source
**Referenced by**: [../engineering/object_storage.md](../engineering/object_storage.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported MinIO role in the local platform.

## Rules

- MinIO is the chart-owned object-store target on the supported Kind path and the only
  supported durable home for binary blobs
- MinIO runs as a four-node distributed cluster on the supported Kind path; each MinIO drive
  requests `64Gi` so the retained `infernix-models` bucket can hold the linux-gpu full-catalog
  lazy-bootstrap set without hitting MinIO's low-free-space guard during later model rows
- on a pristine cluster, MinIO may pull from public container repositories only when it is one of
  Harbor's required backend services before Harbor becomes pull-ready
- the supported durable target shape uses **three MinIO buckets**:
  - `infernix-models` — always-on (not demo-gated); platform model weights, tokenizers, and
    configs at `<modelId>/<filename>` plus a `<modelId>/.ready` sentinel object; populated
    lazily on first use by the coordinator's bootstrap subscription on
    `infernix/system/model.bootstrap.request`; read by every engine pod (Linux) and the
    on-host engine daemon (Apple)
  - `infernix-engine-artifacts` — always-on (not demo-gated); immutable content-addressed engine
    software payloads such as wheelhouses, native binaries, Core ML compiled models, JVM tools,
    and reusable Apple or Linux materialization payloads; model weights never live here
  - `infernix-demo-objects` — demo-gated; user uploads and engine-generated artifacts at
    `users/<userId>/contexts/<contextId>/{uploads,generated}/<objectKey>`; absent when
    `demo_ui = false`
- Harbor also uses a MinIO bucket named `harbor-registry` as its rebuildable registry backing
  store. That bucket is not product-durable state: lifecycle cleanup may remove the bucket
  contents, the matching MinIO bucket metadata, and stale multipart/tmp working sets before
  startup or during `cluster down`; the matching Harbor Redis registry-cache claim is also
  rebuildable and is scrubbed with the registry bucket so fresh Harbor database state never points
  at stale image upload fragments or cached blob-existence keys. The durable model and demo-object
  buckets remain retained.
- the **`.ready` sentinel pattern** on `infernix-models`: the coordinator's bootstrap
  worker PUTs each weight file first, then PUTs `<modelId>/.ready` last, then publishes
  `model.bootstrap.ready.<modelId>`. Engines treat the presence of `.ready` as the atomic
  signal that the model is loadable; partial uploads are invisible to readers
- the real-cluster `linux-cpu` integration lane writes a sentinel file through the MinIO data
  volume, replaces one MinIO pod, and asserts the sentinel remains readable afterward

## Routed Surfaces

<!-- infernix:route-registry:minio:start -->
- MinIO has no external gateway route; the browser reaches objects only through the `infernix-demo` webapp `/api/objects` proxy.
<!-- infernix:route-registry:minio:end -->
- the supported Gateway contract targets the live MinIO console and S3 surfaces, and integration
  requires those real upstream responses on the shared edge

## Demo Artifact Bucket

The `infernix-demo-objects` bucket lives alongside the always-on `infernix-models` and
`infernix-engine-artifacts` buckets and is demo-gated; it is absent when `demo_ui = false`.

- bucket name: `infernix-demo-objects`
- per-user prefix layout inside the bucket:
  - `users/<userId>/contexts/<contextId>/uploads/<objectKey>` — user-uploaded artifacts
  - `users/<userId>/contexts/<contextId>/generated/<objectKey>` — model-generated artifacts
  - `users/<userId>/contexts/<contextId>/snapshots/...` is reserved but unused in the supported
    contract; conversation rehydration is direct Pulsar replay, not snapshot replay
- `userId` is the Keycloak `sub` claim, stable across login/logout/password change/device; the
  `users/<sub>/` prefix is derived server-side from the verified token and is the per-user
  isolation boundary. The client never names its own user id or full object key. See
  [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md) for
  the canonical `sub`-derived isolation rule.
- the `infernix-demo` webapp is the single server-side mediator for
  every browser upload and download via `/api/objects`: it derives the key from the verified `sub`,
  authorizes it with `pathBelongsToUser`, and performs the MinIO read/write itself over the
  cluster-internal endpoint, so the browser never receives a presigned MinIO URL. See
  [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md) for the
  single-mediator contract. **Current Status**: implemented (Phase 7 Sprint 7.25; Phase 3
  Sprint 3.13 removed the `/minio/s3` route + `presignPublicEndpoint`). Wave M closed the browser
  object-proxy evidence; Wave N closed Phase 7 Sprint 7.28 generated artifact object ownership.
- artifact bytes always traverse the demo backend: the browser POSTs upload bytes to
  `/api/objects/upload` and GETs download bytes from `/api/objects/download`, and the webapp signs
  internal presigned URLs and performs the PUT/GET against MinIO server-side
- `DELETE /api/account` lists `infernix-demo-objects` with an S3 ListObjectsV2 query scoped to
  `users/<userId>/` and deletes each returned object before the browser starts Keycloak account
  deletion
- bucket creation happens idempotently during `cluster up` when `demo_ui = true`; the
  `infernix-demo` backend also runs a startup repair pass from mounted `ClusterConfig` /
  `SecretsConfig` and creates the required buckets with presigned bucket-level PUTs when
  chart-time provisioning was bypassed or raced
- `infernix test e2e` validates `/api/objects` byte upload/download through the webapp proxy with a
  real Keycloak access token, verifies malformed bearer rejection, and performs a same-user routed
  upload/download byte roundtrip with exact content equality. A second Keycloak user registered for
  the same context/display name reads only that user's bytes, and a request for another user's
  object key is rejected with HTTP 403 at the server-side trust boundary. The routed download-grant
  MIME disposition matrix covers inline image/audio/video, browser-native PDF, bounded JSON/text
  preview, and the in-browser MIDI / MusicXML / ZIP render dispositions (Phase 7 Sprint 7.27). The
  account-deletion smoke verifies the previously readable object returns `404` through the webapp
  proxy after the backend cleanup succeeds.
- supported artifact MIME families on the UI side: `image/*`, playable `audio/*`, `video/*`,
  text/structured-text artifacts (`text/*`, `application/json`), PDF documents
  (`application/pdf`), MIDI variants (`audio/midi`, `audio/x-midi`, `application/x-midi`),
  MusicXML/MXL notation variants (`application/vnd.recordare.musicxml+xml`,
  `application/vnd.recordare.musicxml`, `application/vnd.recordare.musicxml-compressed`), and
  arbitrary binary downloads
- in-browser rendering uses raw `<img>`, `<audio>`, and `<video>` elements against presigned
  URLs where the artifact is actually browser-renderable; text/JSON uses bounded preview,
  PDF uses browser-native document handling, and MIDI, MusicXML/MXL, unknown, or generic
  binary artifacts are download-only by default

See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) for the full
storage contract and [../engineering/object_storage.md](../engineering/object_storage.md) for
the presigned-URL contract.

## Image Inventory

The supported MinIO deployment uses upstream multi-arch images. `bitnamilegacy/*` is not part
of the supported contract.

| Component | Image | Notes |
|-----------|-------|-------|
| MinIO server | `minio/minio` | Multi-arch (`linux/amd64`, `linux/arm64`); the chart override pins a specific `RELEASE.*` tag |
| MinIO client (`mc`) | `minio/mc` | Multi-arch; used by the chart's `minio-provisioning` Job to create buckets at install time |
| Volume-permissions init container | `busybox` | Multi-arch; provides the `sh`/`chmod`/`chown` the chart's `defaultInitContainers.volumePermissions` block runs to seed PV permissions before MinIO starts |

The standalone Console deployment (`bitnamilegacy/minio-object-browser`) is disabled
(`minio.console.enabled: false`). There is no supported `/minio` browser route — at the
declarative target operators and users reach object data only through the `infernix-demo`
webapp's `/api/objects` endpoints rather than a browser console, with the webapp as the single
externally routed file surface (see
[../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)).
**Current Status**: implemented. Phase 3 Sprint 3.13 removed the `/minio/s3` gateway route and the
MinIO console; browser file access flows only through the webapp-mediated `/api/objects` path
(Phase 7 Sprint 7.25). If a future plan reintroduces the MinIO browser console, it will use a
multi-arch upstream image at a known tag and the change will land in the chart together with a new
supported route.

The substrate → container architecture mapping is owned by
[../architecture/runtime_modes.md](../architecture/runtime_modes.md); Harbor publication
pulls the substrate-matched manifest from each multi-arch upstream image and pushes the
single-platform variant into the cluster's Harbor namespace.

## Cross-References

- [pulsar.md](pulsar.md)
- [harbor.md](harbor.md)
- [postgresql.md](postgresql.md)
- [keycloak.md](keycloak.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
- [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)
- [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
