# Runtime Modes

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Describe the supported control-plane execution contexts, service placement options,
> and the three product runtime modes.

## Control-Plane Execution Contexts

The control-plane execution context answers where `infernix` runs.

- Apple host-native execution context runs `./.build/infernix` directly on the host
- Linux outer-container execution context runs `docker compose run --rm infernix infernix ...`

Both execution contexts use the same runtime-mode ids, generated demo-config contract, and
repo-local durable state root under `./.data/`.

## Runtime Modes

The runtime mode answers which engine column from the root README matrix is active for generated
demo catalog entries, service binding, and validation.

| Runtime mode | Canonical mode id | Engine column selected from the README matrix |
|--------------|-------------------|-----------------------------------------------|
| Apple Silicon / Metal | `apple-silicon` | `Best Apple Silicon engine` |
| Ubuntu 24.04 / CPU | `linux-cpu` | `Best Linux CPU engine` |
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-cuda` | `Best Linux CUDA engine` |

`cluster up` resolves the active runtime mode before reconciliation begins, renders
`infernix-demo-<mode>.dhall`, and publishes that exact content into the repo-local publication
mirror or `ConfigMap/infernix-demo-config`.

## Generated Demo Config Contract

The generated demo catalog is the source of truth for the active runtime mode.

- `infernix-demo-<mode>.dhall` records every README matrix row supported by that mode and omits
  rows whose selected engine is `Not recommended`
- each generated entry records the selected engine, request shape, runtime lane, and workload
  metadata
- in containerized execution contexts, `ConfigMap/infernix-demo-config` is mounted read-only at
  `/opt/build/`, and the watched file lives at `/opt/build/infernix-demo-<mode>.dhall`
- `infernix test integration` and `infernix test e2e` enumerate every generated catalog entry for
  the active runtime mode rather than using a smoke subset

## Service Placement

Service placement is a separate concept from runtime mode.

- Apple host-native service placement runs `infernix service` on the host and can repoint the
  routed `/api` surface through the Apple host bridge while the browser stays on the shared edge URL
- the same production daemon runs in every placement and consumes the same generated
  `request_topics`, `result_topic`, and `engines` fields from the active `.dhall`
- when Pulsar endpoint env vars are present, the daemon uses the real Pulsar WebSocket or admin
  transport for those topic fields; otherwise it falls back to the filesystem simulation under
  `./.data/runtime/pulsar/`
- host-native and cluster-resident placements both launch the same process-isolated engine-worker
  contract and honor the same adapter-specific command overrides
- switching runtime modes changes generated catalog content and engine bindings, not the service
  placement contract

## Cross-References

- [overview.md](overview.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [model_catalog.md](model_catalog.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
