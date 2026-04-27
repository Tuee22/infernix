# Haskell Style

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the authoritative Haskell formatting, linting, and compiler-warning policy.

## Policy

- `ormolu` is the formatter for repo-owned Haskell source
- `cabal format` is the formatter for `infernix.cabal`
- `hlint` provides lint checks
- strict compiler warnings are enabled and treated as errors in repository validation
- `infernix test lint` bootstraps the repo-owned formatter and linter binaries through the Cabal
  test target into `./.build/haskell-style-tools/`

## Hard Gates

- formatting drift in repo-owned Haskell sources fails the style gate
- Cabal formatting drift fails the style gate
- `hlint` findings fail the style gate unless the repo deliberately carries a suppression
- compiler warnings are treated as errors on the supported validation path

## Review Guidance

- keep module boundaries explicit and prefer small typed helpers over ad hoc shell-heavy orchestration
- treat unsupported convenience fallbacks as design debt rather than silently broadening the supported contract
- preserve the repo rule that generated artifacts stay out of tracked source

## Enforcement Model

- `cabal --builddir=.build/cabal test infernix-haskell-style` is the mechanical formatter and linter gate
- `infernix test lint` runs that gate together with the repo-owned files, chart, proto, docs, and Python checks
- supported validation is fail-fast: it reports drift and stops; it does not silently rewrite tracked files

## Entry Point

Use `infernix test lint` as the canonical static-quality gate.

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/build_artifacts.md](../engineering/build_artifacts.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
