# CLI Surface

**Status**: Authoritative source
**Referenced by**: [cli_reference.md](cli_reference.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Provide the short-form overview of the supported `infernix` command families.

## Binaries

The repository ships two Haskell executables sharing one Cabal library `infernix-lib`:

- `infernix` - production daemon and operator workflow
- `infernix-demo` - demo UI HTTP host (gated by `.dhall` `demo_ui`; absent from production
  deployments)

Both ship in the same runtime image on the real cluster path; the entrypoint selects which
executable runs.

<!-- infernix:family-overview:start -->
## `infernix` Families

- `service` - starts the long-running production daemon that consumes Pulsar work and binds no HTTP port
- `cluster` - reconciles or reports cluster state, generated config publication, and routed surfaces
- `cache` - inspects or reconciles manifest-backed derived cache state for the active runtime mode
- `kubectl` - proxies upstream Kubernetes access through the repo-local kubeconfig
- `lint` - runs the focused Haskell-owned static checks for files, docs, `.proto`, and chart assets
- `test` - runs the aggregate validation entrypoints for lint, unit, integration, routed E2E, and the full suite
- `docs` - validates the governed documentation suite and the development-plan shape
- `internal` - runs build-time helpers for contract generation, chart discovery, demo-config inspection, and Pulsar round-trip validation
<!-- infernix:family-overview:end -->

## `infernix-demo` Families

- `serve --dhall PATH --port N` starts the demo HTTP API host

## Cross-References

- [cli_reference.md](cli_reference.md)
- [api_surface.md](api_surface.md)
- [../development/testing_strategy.md](../development/testing_strategy.md)
