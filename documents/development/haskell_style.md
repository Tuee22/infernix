# Haskell Style

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the authoritative Haskell formatting, linting, and compiler-warning policy.

## Executive Summary

- `ormolu`, `hlint`, `cabal format`, and the Haskell build warning policy are the supported
  mechanical gates for repo-owned Haskell code.
- Repository hard gates are enforced by commands; editor tooling is optional local convenience.
- Review doctrine focuses on module boundaries, small typed helpers, clear effect boundaries, and
  typed control flow instead of shell-heavy orchestration.
- Supported validation is fail-fast: it reports drift and stops; it does not silently rewrite
  tracked source.

## Hard Gates

- `ormolu` is the formatter for repo-owned Haskell source
- `cabal format` is the formatter for `infernix.cabal`
- `hlint` provides lint checks
- strict compiler warnings are enabled and treated as errors on the supported validation path
- formatting drift in repo-owned Haskell sources fails the style gate
- Cabal formatting drift fails the style gate
- `hlint` findings fail the style gate unless the repo deliberately carries a suppression

## Editor-Only Guidance

- use format-on-save, Haskell Language Server, or editor `hlint` integration if they help local
  iteration, but those editor integrations are not part of the repo contract
- local editor plugins may surface warnings earlier, yet the authoritative pass or fail result
  still comes from the repo validation commands
- do not rely on editor-specific rewrites, template expansion, or hidden generated files to satisfy
  repository policy

## Review Doctrine

- `Module shape:` keep ownership boundaries obvious; Haskell modules own the control plane, route
  registry, validation entrypoints, and service orchestration rather than delegating those concerns
  to shell wrappers or sidecar scripts. The only supported shell exception is the thin
  `bootstrap/*.sh` stage-0 host bootstrap surface.
- `Function shape:` prefer small typed helpers and explicit data flow over long imperative
  functions that interleave parsing, shell invocation, mutation, and rendering.
- `Effect boundaries:` keep `IO`, process execution, filesystem mutation, and environment probing
  near the edge so the inner domain logic stays testable and easy to reason about.
- `Typed control flow:` prefer ADTs, records, and pattern matching over stringly mode switches,
  sentinel values, or silently ignored cases.
- `Repository discipline:` treat unsupported convenience fallbacks as design debt rather than
  widening the supported contract silently, and preserve the generated-artifact hygiene rules.

## Enforcement Model

- `src/Infernix/Lint/HaskellStyle.hs` is the implementation source of truth for the style gate.
- `runHaskellStyleLint` bootstraps `ormolu` and `hlint` into `./.build/haskell-style-tools/bin/`
  and falls back to `ghcup run --ghc 9.6.7 -- cabal ...` when the active compiler is too new for
  the currently supported `hlint` release.
- the style gate checks `Setup.hs`, `app/`, `src/`, and `test/` with `ormolu --mode check` and
  `hlint`
- the style gate checks `infernix.cabal` by formatting a temporary copy with `cabal format` and
  comparing the result rather than rewriting the tracked manifest in place
- `infernix test lint` runs the Haskell style gate together with the repo-owned files, chart,
  proto, docs, Python, and build-warning checks

## Validation

- `cabal test infernix-haskell-style` is the mechanical formatter and linter gate
- `infernix test lint` is the canonical static-quality entrypoint
- supported validation is fail-fast and stops on drift instead of rewriting tracked files

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/build_artifacts.md](../engineering/build_artifacts.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
