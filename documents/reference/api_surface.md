# API Surface

**Status**: Authoritative source
**Referenced by**: [cli_reference.md](cli_reference.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the demo-only routed HTTP surface consumed by the demo browser and demo
> validation flows.

## Scope

**This is the demo HTTP surface only, served by the `infernix-demo` Haskell binary and gated by
the active `.dhall` `demo_ui` flag.** Production deployments leave the flag off, the cluster has
no `infernix-demo` workload, and none of the endpoints below are bound. The production inference
surface is Pulsar topics named in the active `.dhall`; see
[../tools/pulsar.md](../tools/pulsar.md) for the production contract.

## Endpoints

- `GET /api/publication` returns the active runtime mode, control-plane context, daemon location, catalog source, API-upstream mode, worker-execution mode, worker-adapter mode, artifact-acquisition mode, routed-upstream health or backing-state details, and published route inventory
- `GET /api/models` lists generated catalog entries for the active runtime mode
- `GET /api/models/:modelId` returns model metadata, selected engine, and request-shape information
- `GET /api/demo-config` returns the serialized generated demo config for the active runtime mode
- `POST /api/inference` submits a manual inference request
- `GET /api/inference/:requestId` returns the latest result, including the active runtime mode and selected engine
- `GET /objects/:objectRef` returns the stored large-output payload referenced by an inference result
- `GET /api/cache` returns manifest-backed cache status for the active runtime mode
- `POST /api/cache/evict` removes derived cache directories while retaining the durable manifest
- `POST /api/cache/rebuild` rebuilds derived cache directories from the durable manifest set

## Rules

- the demo API surface is implemented in Haskell as `src/Infernix/Demo/Api.hs` (servant-based)
  and exposed by the `infernix-demo` binary; production `infernix service` does not bind any HTTP
  port and never serves these endpoints
- request validation uses Haskell-owned model metadata; the same Haskell typed runtime contract
  is shared with the current no-HTTP production-daemon placeholder and the planned Pulsar consumer
- invalid requests return typed user-facing errors
- large outputs are returned as typed object references and remain retrievable through
  `GET /objects/:objectRef`
- cache-eviction and cache-rebuild flows only affect derived cache state; they do not rewrite the
  generated catalog or publication contract
- cache status exposes durable runtime-artifact bundle URIs, engine-runner metadata including
  engine-adapter availability, durable source-artifact manifest URIs, authoritative
  source-artifact URI or kind metadata, and selected-artifact inventory while keeping derived
  cache directories rebuildable
- publication details stay mode-stable and source from the repo-local publication-state file
- `GET /api/demo-config` and `GET /api/models` stay aligned with the generated active-mode demo
  catalog
- the demo `/api` remains stable even when the active upstream changes between the cluster
  `infernix-demo` workload and the Apple host bridge (`infernix-demo serve` running host-native)
- the demo API surface is stable even when switching runtime modes because only the generated
  catalog content changes

## Cross-References

- [web_portal_surface.md](web_portal_surface.md)
- [../architecture/model_catalog.md](../architecture/model_catalog.md)
- [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md)
