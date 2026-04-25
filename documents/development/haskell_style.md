# Haskell Style

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the authoritative Haskell formatting, linting, and compiler-warning policy.

## Policy

- `ormolu` is the formatter for repo-owned Haskell source
- `cabal format` is the formatter for `infernix.cabal`
- `hlint` provides lint checks
- strict compiler warnings are enabled and treated as errors in repository validation
- `infernix test lint` bootstraps the repo-owned formatter and linter binaries via the Cabal
  test target plus a small `scripts/install-formatter.sh` shell shim that downloads `ormolu` and
  `hlint` into `./.build/haskell-style-tools/`

## Entry Point

Use `infernix test lint` as the canonical static-quality gate.

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../engineering/build_artifacts.md](../engineering/build_artifacts.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
