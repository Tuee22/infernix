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

## `infernix` Families

- `service` starts the long-running production daemon (binds no HTTP port; current topic
  consumption is filesystem-backed)
- `cluster` reconciles or reports cluster state
- `cache` inspects or clears or rebuilds manifest-backed derived cache state
- `kubectl` proxies Kubernetes access through the repo-local kubeconfig
- `lint` runs canonical Haskell-implemented static checks (`files`, `docs`, `proto`, `chart`)
- `test` runs repository validation
- `docs` validates governed documentation
- `internal` runs build-time helpers (`generate-purs-contracts`,
  `discover {images,claims,harbor-overlay}`, `publish-chart-images`,
  `demo-config {load,validate}`)

## `infernix-demo` Families

- `serve --dhall PATH --port N` starts the demo HTTP API host

## Cross-References

- [cli_reference.md](cli_reference.md)
- [api_surface.md](api_surface.md)
- [../development/testing_strategy.md](../development/testing_strategy.md)
