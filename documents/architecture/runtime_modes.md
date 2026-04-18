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

`cluster up` resolves the active runtime mode before cluster-side reconciliation begins, renders
`infernix-demo-<mode>.dhall`, and publishes that exact content into
`ConfigMap/infernix-demo-config`.

## Generated Demo Config Contract

The generated demo catalog is the source of truth for the active runtime mode.

- `infernix-demo-<mode>.dhall` records every README matrix row supported by that mode and omits
  rows whose selected engine is `Not recommended`
- each generated entry records the selected engine, request shape, runtime lane, and workload metadata
- in containerized execution contexts, `ConfigMap/infernix-demo-config` is mounted read-only at
  `/opt/build/`, and the watched file lives at `/opt/build/infernix-demo-<mode>.dhall`
- `infernix test integration` and `infernix test e2e` enumerate every generated catalog entry for
  the active runtime mode rather than using a smoke subset

## GPU-Enabled `linux-cuda`

`linux-cuda` is a distinct runtime mode, not a generic alias for "Linux".

- the plan contract requires `cluster up` in `linux-cuda` to reconcile a Kind path that exposes
  NVIDIA container runtime support inside Kind and usable `nvidia.com/gpu` resources to cluster
  workloads
- the current implementation still uses a shim-backed CUDA Kind path that labels the GPU worker,
  installs the NVIDIA runtime shim inside Kind nodes, and synthetically advertises allocatable
  `nvidia.com/gpu`; the remaining real-device gap stays tracked in
  [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)
- the cluster deploys `RuntimeClass/nvidia`, and the CUDA service workload requests
  `nvidia.com/gpu: 1` while selecting the GPU-labeled node
- CUDA-bound generated catalog rows carry runtime-lane metadata that the service and test surfaces
  consume for placement and scheduling assertions
- real device-backed NVIDIA execution inside Kind remains required for final plan closure even
  though the current implementation has not closed that gap yet
- switching from `linux-cpu` to `linux-cuda` changes the selected engine bindings and may change
  the generated entry set

## Service Placement

Service placement is a separate concept from runtime mode.

- Apple host-native service placement runs `infernix service` on the host and repoints the routed
  `/api` surface through the Apple host bridge while the browser stays on the shared edge URL
- the host-native and cluster-resident service placements both supervise the same engine-aware
  managed subprocess worker contract and consume durable runtime artifact bundles plus
  durable source-artifact manifests through their respective MinIO or Pulsar access path
- cluster-resident service placement consumes the same active runtime mode and the same generated
  demo catalog from `/opt/build/`

Service placement changes where the daemon runs. It does not redefine the three runtime modes.

## Cross-References

- [overview.md](overview.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [model_catalog.md](model_catalog.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
