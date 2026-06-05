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
- `GET /api/cache` returns manifest-backed cache status for the active runtime mode
- `POST /api/cache/evict` removes derived cache directories while retaining the durable manifest
- `POST /api/cache/rebuild` rebuilds derived cache directories from the durable manifest set
- `POST /api/objects/upload` and `POST /api/objects/download` mint a presigned MinIO URL for
  the authenticated user and the requested context. The bearer JWT is verified against the
  cached Keycloak JWKS, `userId` is derived from the `sub` claim, the request body names the
  target `contextId` plus artifact metadata (kind, MIME/content type, display name, byte count
  for uploads), the requested object key is scoped against
  `users/<userId>/contexts/<contextId>/{uploads,generated}/`, and the response carries the
  presigned URL plus the canonical MinIO object reference and a typed render disposition
  (`RenderInline`, `BoundedTextPreview`, `BrowserNativePdf`, or `DownloadOnly`). The routed E2E
  suite validates the disposition matrix for image/audio/video, PDF, JSON, text, MIDI, MusicXML,
  and generic binary MIME cases. The route derives the object path from the authenticated `sub`,
  so another user with the same context/display name receives a distinct `users/<sub>/...`
  prefix. Presigned URLs are bearer capabilities until expiry. The browser E2E flow exercises
  bounded text/JSON preview, inline image/audio/video media URLs, browser-native PDF URL wiring,
  and MIDI / MusicXML / generic-binary download-only states through these presigned grants.
  Demo-gated and absent when `demo_ui = false`. See
  [../tools/minio.md](../tools/minio.md) and
  [../architecture/demo_app_design.md](../architecture/demo_app_design.md).

## Rules

- the demo API surface is implemented in Haskell as `src/Infernix/Demo/Api.hs` and exposed by the
  `infernix-demo` binary; production `infernix service` does not bind any HTTP port and never
  serves these endpoints
- request validation uses Haskell-owned model metadata; the same Haskell typed runtime contract is
  shared with the non-HTTP production daemon
- invalid requests return typed user-facing errors
- large outputs from generative engines (image, audio, video, large structured-text) are
  PUT by the engine adapter directly to the `infernix-demo-objects` MinIO bucket at the
  appropriate per-user prefix; the inference result message carries an `ObjectRef`, and the
  browser fetches the bytes via presigned GET URLs minted at `/api/objects`. Text outputs
  ride inline in the result message
- cache-eviction and cache-rebuild flows only affect derived cache state; they do not rewrite the
  generated catalog or publication contract
- cache status exposes the supported `minio://infernix-models/<modelId>/` durable
  source URIs, engine-runner metadata including engine-adapter availability, and selected
  engine-binding details derived from the staged substrate `.dhall`. Cache manifests sit
  beside the cached weights at
  `./.data/runtime/model-cache/<runtime-mode>/<model-id>/manifest.pb` and are rebuildable
  via `infernix cache rebuild`
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
