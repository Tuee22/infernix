# API Surface

**Status**: Authoritative source
**Referenced by**: [cli_reference.md](cli_reference.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the demo-only routed HTTP surface consumed by the demo browser and demo
> validation flows.

## Scope

**This is the demo HTTP surface only, served by the `infernix-demo` Haskell binary and gated by
the active `.dhall` `demo_ui` flag.** Production deployments leave the flag off, the cluster has
no `infernix-demo` workload, and none of the endpoints below are bound. The production inference
surface is the `.dhall` topic contract described in [../tools/pulsar.md](../tools/pulsar.md).

## Endpoints

- `GET /api/publication` returns the active runtime mode, control-plane context, cluster daemon
  location, inference executor location, optional host batch topic, catalog source,
  API-upstream mode, worker-execution mode, worker-adapter mode, artifact-acquisition mode,
  routed-upstream health or backing-state details, and published route inventory
- `GET /api/models` lists generated catalog entries for the active runtime mode
- `GET /api/models/:modelId` returns model metadata, selected engine, and request-shape
  information
- `GET /api/demo-config` returns the serialized generated demo config for the active runtime mode
- `GET /objects/:objectRef` returns the stored large-output payload referenced by an inference
  result
- `GET /api/cache` returns manifest-backed cache status for the active runtime mode
- `POST /api/cache/evict` removes derived cache directories while retaining the durable manifest
- `POST /api/cache/rebuild` rebuilds derived cache directories from the durable manifest set
- `POST /api/objects` (Planned, Phase 7) mints a presigned MinIO URL for the authenticated user
  and the requested context. Request body carries the operation (`Upload` or `Download`), the
  target `contextId`, and the artifact metadata (kind, MIME/content type, display name, byte
  count for uploads). Response carries the presigned URL plus the canonical MinIO object key and
  render disposition (`inline-media`, `text-preview`, `browser-document`, or `download-only`).
  URLs are scoped to the user's prefix; cross-user URL requests are rejected. Demo-gated and
  absent when `demo_ui = false`. See [../tools/minio.md](../tools/minio.md) and
  [../architecture/demo_app_design.md](../architecture/demo_app_design.md).

## Rules

- the demo API surface is implemented in Haskell as `src/Infernix/Demo/Api.hs` and exposed by the
  `infernix-demo` binary; production `infernix service` does not bind any HTTP port and never
  serves these endpoints
- request validation uses Haskell-owned model metadata; the same Haskell typed runtime contract is
  shared with the non-HTTP production daemon
- invalid requests return typed user-facing errors
- large outputs are returned as typed object references and remain retrievable through
  `GET /objects/:objectRef`
- cache-eviction and cache-rebuild flows only affect derived cache state; they do not rewrite the
  generated catalog or publication contract
- cache status exposes durable runtime-artifact bundle URIs, engine-runner metadata including
  engine-adapter availability, durable source-artifact manifest URIs, authoritative
  source-artifact URI or kind metadata, and selected-artifact inventory while keeping derived cache
  directories rebuildable
- publication details stay mode-stable and source from the repo-local publication-state file
- on Apple, the supported clustered lifecycle publishes `daemonLocation: cluster-pod`,
  `inferenceExecutorLocation: control-plane-host`, `hostInferenceBatchTopic`, and
  `inferenceDispatchMode: pulsar-bridge-to-host-daemon`; on Linux, the same dispatch field
  advertises `pulsar-bridge-to-cluster-daemon` and the executor location remains `cluster-pod`
- `GET /api/demo-config` and `GET /api/models` stay aligned with the generated active-mode demo
  catalog
- the demo `/api` remains stable across Apple and Linux substrates because the routed demo surface
  is always cluster-resident
- the demo API surface is stable even when switching runtime modes because only the generated
  catalog content changes
- the supported manual-inference path closes through the durable-context Chat surface introduced
  by Phase 7: the browser opens a WebSocket against `/ws` (see
  [web_portal_surface.md](web_portal_surface.md)) and receives typed `ConversationState`
  snapshots plus `ConversationStatePatch` deltas, and artifact transfer uses presigned MinIO
  URLs minted by `POST /api/objects`

## Cross-References

- [web_portal_surface.md](web_portal_surface.md)
- [../architecture/model_catalog.md](../architecture/model_catalog.md)
- [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md)
