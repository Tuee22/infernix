# Runtime Modes

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Describe the supported control-plane execution contexts, service placement options,
> and the three product runtime modes.

## Control-Plane Execution Contexts

The control-plane execution context answers where `infernix` runs.

- Apple host-native execution context runs `./.build/infernix` directly on the host
- Linux outer-container execution context runs `docker compose run --rm infernix infernix ...`

Both execution contexts use:

- one Kind cluster
- one repo-local kubeconfig in the active build root
- one repo-local durable state root under `./.data/`

## Runtime Modes

The runtime mode answers which engine column from the root README matrix is active for generated
demo catalog entries, service binding, and validation.

| Runtime mode | Canonical mode id | Engine column selected from the README matrix |
|--------------|-------------------|-----------------------------------------------|
| Apple Silicon / Metal | `apple-silicon` | `Best Apple Silicon engine` |
| Ubuntu 24.04 / CPU | `linux-cpu` | `Best Linux CPU engine` |
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-cuda` | `Best Linux CUDA engine` |

`cluster up` generates `infernix-demo-<mode>.dhall` for the active runtime mode in the active
build root. That generated file is the source of truth for:

- which demo-visible models or workloads appear in the UI for that mode
- which engine binding each entry uses for that mode
- which catalog entries `infernix test integration` and `infernix test e2e` must exercise for that mode

## Service Placement

Service placement is a separate concept from runtime mode.

- Apple host-native service placement runs `infernix service` on the host and reaches cluster services through the edge proxy
- cluster-resident service placement runs the same executable in a cluster workload and reaches dependent services over cluster networking

Service placement changes where the daemon runs. It does not redefine the three runtime modes.

## Cross-References

- [overview.md](overview.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [model_catalog.md](model_catalog.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
