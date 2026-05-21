# MinIO

**Status**: Authoritative source
**Referenced by**: [../engineering/object_storage.md](../engineering/object_storage.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported MinIO role in the local platform.

## Rules

- MinIO is the chart-owned object-store target on the supported Kind path
- the current validated runtime persists durable object-store data under `./.data/object-store/`
- MinIO runs as a four-node distributed cluster on the supported Kind path
- on a pristine cluster, MinIO may pull from public container repositories only when it is one of
  Harbor's required backend services before Harbor becomes pull-ready
- the chart values reserve the `infernix-runtime` and `infernix-results` buckets for the real
  cluster path
- the real-cluster `linux-cpu` integration lane writes a sentinel file through the MinIO data
  volume, replaces one MinIO pod, and asserts the sentinel remains readable afterward

## Routed Surfaces

<!-- infernix:route-registry:minio:start -->
- `/minio/console` -> `infernix-minio-console:9090`; rewrites to upstream `/`
- `/minio/s3` -> `infernix-minio:9000`; rewrites to upstream `/`
<!-- infernix:route-registry:minio:end -->
- the supported Gateway contract targets the live MinIO console and S3 surfaces, and integration
  requires those real upstream responses on the shared edge

## Demo Artifact Bucket (Planned)

When the durable-context demo lands (Phase 7), one additional bucket is reserved for the demo
application. It is demo-gated and absent when `demo_ui = false`.

- bucket name: `infernix-demo-objects`
- per-user prefix layout inside the bucket:
  - `users/<userId>/contexts/<contextId>/uploads/<objectKey>` — user-uploaded artifacts
  - `users/<userId>/contexts/<contextId>/generated/<objectKey>` — model-generated artifacts
  - `users/<userId>/contexts/<contextId>/snapshots/...` is reserved but unused in the supported
    contract; conversation rehydration is direct Pulsar replay, not snapshot replay
- `userId` is the Keycloak `sub` claim, stable across login/logout/password change/device
- the `infernix-demo` backend mints presigned PUT and GET URLs via `/api/objects`; URLs are
  scoped to the user's prefix via MinIO scope policies, so cross-user URL access is rejected
  at the storage layer
- artifact bytes never traverse the demo backend; the browser performs multipart upload
  directly to MinIO using the presigned URL and downloads directly using the presigned GET
- bucket creation happens idempotently during `cluster up` when `demo_ui = true`
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

## Cross-References

- [pulsar.md](pulsar.md)
- [harbor.md](harbor.md)
- [postgresql.md](postgresql.md)
- [keycloak.md](keycloak.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
