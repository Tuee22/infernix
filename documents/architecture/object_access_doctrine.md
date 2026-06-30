# Object Access Doctrine

**Status**: Authoritative source
**Referenced by**: [demo_app_design.md](demo_app_design.md), [daemon_topology.md](daemon_topology.md), [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md), [../engineering/object_storage.md](../engineering/object_storage.md), [../engineering/edge_routing.md](../engineering/edge_routing.md), [../tools/minio.md](../tools/minio.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Define the rule that the `infernix-demo` webapp is the single mediator for every browser
> artifact upload and download — the browser never holds a MinIO credential, never receives a presigned
> MinIO URL, and never reaches MinIO through the gateway; all artifact bytes flow through the webapp's
> `/api/objects` endpoints.

## TL;DR

- All browser artifact I/O (upload, download, generated-artifact fetch, in-browser preview) flows through
  the webapp (`infernix-demo`) `/api/objects` endpoints. The webapp reads and writes MinIO **server-side**
  over the cluster-internal endpoint. Engine-generated artifacts must land under the same
  `users/<sub>/contexts/<ctx>/generated/` layout before the browser fetches them.
- The browser is **never** handed a presigned MinIO URL and **never** talks to MinIO directly. The
  `/minio/s3` gateway route is removed; the webapp is the only externally routed gateway service for file
  storage.
- Per-user isolation (see [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md)) is therefore
  enforced at one server-side choke point on every request, not delegated to a per-object presigned grant
  the browser holds.

## The rule

- The webapp authenticates the caller (Keycloak JWT → `UserId` from the `sub` claim), derives the object
  key **server-side** from that `sub` (and, for download, accepts only a `users/<sub>/`-scoped key it
  re-authorizes), authorizes it with `Infernix.Objects.Layout.pathBelongsToUser`, and performs the MinIO
  read/write itself: it signs a SigV4 URL against the cluster-internal endpoint
  (`Demo/Api.hs.loadInternalMinioPresignedConfig`) and issues the PUT/GET server-side
  (`putMinioObjectBytes` / `getMinioObjectBytes`). The client-supplied display name is neutralized by
  `Infernix.Objects.Layout.sanitizeFilename` before it becomes part of a key.
- Upload: `POST /api/objects/upload` carries the file bytes (with `contextId` / `displayName` query
  parameters); the webapp stores them and returns the typed `ObjectRef`. Download:
  `GET /api/objects/download?key=…` streams the bytes back with the correct `Content-Type` and
  `Content-Disposition` (authenticated by the `Authorization` header or the operator cookie for
  browser-issued media `src` fetches); a companion `POST /api/objects/download` returns the typed render
  disposition. The browser holds only the webapp origin.
- The engine and coordinator continue to read inputs and write artifacts server-side over the same
  cluster-internal endpoint; they are inside the trust boundary. Generated-artifact writers must use a
  coordinator/worker-supplied target derived from the verified `UserId` and `ContextId`; adapters and
  native runners must not invent family/model/digest or `native-generated/` keys.

## Current Status

The browser-facing object-proxy doctrine is **implemented**. The webapp proxies every browser artifact
byte server-side over the cluster-internal MinIO endpoint and never hands the browser a presigned MinIO
URL. **Phase 3 Sprint 3.13** removed the external `/minio/s3` gateway route, the
`infernix-minio-s3` SecurityPolicy, and the `presignPublicEndpoint` cluster-config field, so the
`infernix-demo` webapp is the only externally routed file-storage service. **Phase 7 Sprint 7.25** made
`Demo/Api.hs` the byte proxy and dropped the browser-direct presigned-URL grant fields. The retired
presigned-browser path is recorded in
[legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

The June 2026 audit reopened a narrower generated-artifact ownership residual as **Phase 7 Sprint
7.28**. Closure now makes the Haskell request path own a typed output object target under
`users/<sub>/contexts/<ctx>/generated/`; Python adapters reject missing or invalid generated-output
targets, native process runners upload only under the supplied target, and the result bridge rejects
raw or cross-user generated object refs. Wave N closed the full selected `linux-gpu` plus
`linux-cpu` cohort validation on 2026-06-30.

## Boundary

| Surface | Who reaches it | Path |
|---|---|---|
| Webapp `/api/objects/{upload,download,list}` | the browser | external gateway — the only file surface |
| MinIO S3 | webapp, coordinator, engine (server-side only) | cluster-internal `service.minio.endpoint` |
| `/minio/s3` gateway route + `presignPublicEndpoint` | (removed) | — |

## Validation

- `infernix lint docs` keeps this doctrine's metadata and cross-references consistent.
- Phase 7 Sprint 7.25 integration and e2e prove the browser uploads/downloads only through the webapp
  and that a cross-user object key is rejected (HTTP 403); Phase 3 Sprint 3.13 proves the rendered chart
  exposes no `/minio/s3` route.
- Phase 7 Sprint 7.28 unit and integration-build validation covers generated-artifact output-prefix
  derivation plus result-bridge rejection of raw and cross-user generated refs; Wave N closes the full
  `linux-gpu` plus `linux-cpu` routed real-output gate.
