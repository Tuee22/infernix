# Haskell Style

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the authoritative Haskell formatting, linting, and compiler-warning policy.

## Policy

- `fourmolu` is the formatter for repo-owned Haskell source
- `cabal-fmt` formats `.cabal` and `cabal.project`
- `hlint` provides lint checks
- strict compiler warnings are enabled and treated as errors in repository validation

## Entry Point

Use `infernix test lint` as the canonical static-quality gate.

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../engineering/build_artifacts.md](../engineering/build_artifacts.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
