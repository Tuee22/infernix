# CLI Surface

**Status**: Authoritative source
**Referenced by**: [cli_reference.md](cli_reference.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Provide the short-form overview of the supported `infernix` command families.

## Families

- `service` starts the Haskell service runtime
- `cluster` reconciles or reports cluster state
- `kubectl` proxies Kubernetes access through the repo-local kubeconfig
- `test` runs repository validation
- `docs` validates governed documentation

## Cross-References

- [cli_reference.md](cli_reference.md)
- [api_surface.md](api_surface.md)
- [../development/testing_strategy.md](../development/testing_strategy.md)
