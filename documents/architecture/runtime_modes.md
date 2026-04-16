# Runtime Modes

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Describe the supported control-plane and service runtime modes.

## Control Plane Modes

- Apple host-native mode runs `./.build/infernix` directly on the host
- containerized Linux mode runs `docker compose run --rm infernix infernix ...`

Both modes use:

- one Kind cluster
- one repo-local kubeconfig in the active build root
- one repo-local durable state root under `./.data/`

## Service Runtime Modes

- host-native Apple mode runs `infernix service` on the host and reaches cluster services through the edge proxy
- cluster mode runs the same executable in a cluster workload and reaches dependent services over cluster networking

## Cross-References

- [overview.md](overview.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
