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
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-gpu` | `Best Linux CUDA engine` |

The active runtime mode is encoded in `infernix-substrate.dhall` beside the built binary.
Apple host builds stage that file explicitly with
`./.build/infernix internal materialize-substrate apple-silicon`, and Linux outer-container
workflows stage `./.build/outer-container/build/infernix-substrate.dhall` on the host through the
bind-mounted build tree with
`docker compose run --rm infernix infernix internal materialize-substrate <substrate> --demo-ui <true|false>`.
`cluster up` republishes that exact file into the repo-local publication mirror and
`ConfigMap/infernix-demo-config`.

## Generated Demo Config Contract

The generated demo catalog is the source of truth for the active runtime mode.

- `infernix-substrate.dhall` records every README matrix row supported by that mode and omits
  rows whose selected engine is `Not recommended`
- each generated entry records the selected engine, request shape, runtime lane, and workload
  metadata
- `infernix internal materialize-substrate <runtime-mode>` is the supported staging command, and
  `--demo-ui false` emits a demo-off config without hand-editing the file
- in containerized execution contexts, `ConfigMap/infernix-demo-config` is mounted read-only
  beside the binary, and the watched file lives at `/opt/build/infernix-substrate.dhall`
- `infernix test integration` and `infernix test e2e` enumerate every generated catalog entry for
  the active runtime mode rather than using a smoke subset

## Service Placement

Service placement is a separate concept from runtime mode.

- Apple host-native execution context means the supported `cluster up`, `cluster status`, and
  validation commands run through `./.build/infernix` on the host; it does not mean the supported
  clustered service daemon stays host-resident after reconcile
- `cluster up` deploys `infernix-demo` whenever `demo_ui` is enabled, deploys
  `infernix-service` only on `linux-cpu` and `linux-gpu`, and leaves the Apple daemon host-native
- on `apple-silicon`, the clustered `infernix-demo` path still runs from the
  `infernix-linux-cpu:local` image family while reading the staged `apple-silicon` substrate file
- the direct `infernix service` command remains available as a manual Apple host daemon entrypoint
  outside the clustered lifecycle and consumes the same generated `request_topics`,
  `result_topic`, and `engines` fields from the active `.dhall`
- `/api/publication` keeps `apiUpstream.mode: cluster-demo` for the stable routed browser host,
  reports `daemonLocation: control-plane-host` on Apple, and distinguishes the daemon lane with
  `inferenceDispatchMode: pulsar-bridge-to-host-daemon` on Apple versus
  `pulsar-bridge-to-cluster-daemon` on Linux
- when Pulsar endpoint env vars are present, the daemon uses the real Pulsar WebSocket or admin
  transport for those topic fields; on Apple host-native runs, the daemon also auto-discovers the
  routed Pulsar edge from the published cluster state when the env vars are absent and the cluster
  is present; unit-level harnesses can still exercise the repo-local topic spool under
  `./.data/runtime/pulsar/` when those endpoints are intentionally absent
- direct host runs and cluster-resident placements both launch the same process-isolated
  engine-worker contract and honor the same adapter-specific command overrides
- switching runtime modes changes generated catalog content and engine bindings, not the service
  placement contract

## Cross-References

- [overview.md](overview.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [model_catalog.md](model_catalog.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
