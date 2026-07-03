# CLI Surface

**Status**: Authoritative source
**Referenced by**: [cli_reference.md](cli_reference.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Provide the short-form overview of the supported `infernix` command families.

## Binaries

The repository ships one Haskell executable:

- `infernix` - operator workflow plus the long-running Coordinator, Engine, and Webapp roles

The runtime image carries that executable. Chart workload args select the role with
`infernix service --role coordinator|engine|webapp`; the demo-gated `infernix-demo` Kubernetes
workload runs the Webapp role.

<!-- infernix:family-overview:start -->
## `infernix` Families

- `init` - creates the operator runtime config `./infernix.dhall` and host manifest `./infernix-host.dhall`
- `service` - starts one long-running role from the single infernix binary: coordinator, engine, or webapp
- `cluster` - reconciles or reports cluster state, lifecycle progress, generated substrate publication, and routed surfaces
- `cache` - inspects or reconciles manifest-backed derived cache state for the active substrate
- `kubectl` - proxies upstream Kubernetes access through the repo-local kubeconfig
- `lint` - runs the focused Haskell-owned static checks for files, docs, `.proto`, and chart assets
- `test` - runs the aggregate validation entrypoints for lint, unit, integration, routed E2E, and the full suite
- `docs` - validates the governed documentation suite and the development-plan shape
- `internal` - runs build-time helpers for contract generation, chart discovery, substrate materialization, demo-config inspection, and Pulsar round-trip validation
<!-- infernix:family-overview:end -->

## Lifecycle Status

- `cluster status` is the supported progress check during `cluster up` and `cluster down`
- when a lifecycle action is active, the status surface reports the current phase, the current
  child operation, and a heartbeat timestamp instead of leaving Apple bring-up or teardown in an
  opaque wait state

## Cross-References

- [cli_reference.md](cli_reference.md)
- [api_surface.md](api_surface.md)
- [../development/testing_strategy.md](../development/testing_strategy.md)
