# API Surface

**Status**: Authoritative source
**Referenced by**: [cli_reference.md](cli_reference.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the stable browser-facing API surface.

## Endpoints

- `GET /api/publication` returns the active runtime mode, control-plane context, daemon location, catalog source, API-upstream mode, worker-execution mode, worker-adapter mode, artifact-acquisition mode, routed-upstream health or backing-state details, and published route inventory
- `GET /api/models` lists generated catalog entries for the active runtime mode
- `GET /api/models/:modelId` returns model metadata, selected engine, and request-shape information
- `POST /api/inference` submits a manual inference request
- `GET /api/inference/:requestId` returns the latest result, including the active runtime mode and selected engine
- `GET /api/cache` returns manifest-backed cache status for the active runtime mode
- `POST /api/cache/evict` removes derived cache directories while retaining the durable manifest
- `POST /api/cache/rebuild` rebuilds derived cache directories from the durable manifest set

## Rules

- request validation uses Haskell-owned model metadata
- invalid requests return typed user-facing errors
- large outputs are returned as typed object references
- cache-eviction and cache-rebuild flows only affect derived cache state; they do not rewrite the generated catalog or publication contract
- cache status exposes durable runtime-artifact bundle URIs, engine-adapter metadata, and durable source-artifact manifest URIs while keeping derived cache directories rebuildable
- publication details stay mode-stable even though the implementation still sources them from the repo-local publication-state file
- `/api` remains stable even when the active upstream changes between the cluster-resident service and the Apple host bridge
- the API surface is stable even when switching runtime modes because only the generated catalog content changes

## Cross-References

- [web_portal_surface.md](web_portal_surface.md)
- [../architecture/model_catalog.md](../architecture/model_catalog.md)
- [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md)
