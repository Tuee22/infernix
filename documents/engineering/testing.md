# Testing Doctrine

**Status**: Authoritative source
**Referenced by**: [../development/testing_strategy.md](../development/testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Define the canonical testing entrypoints, fail-fast behavior, and supported validation boundaries.

## Canonical Entry Points

- `infernix docs check` validates the governed docs suite and plan shape
- `infernix test lint` is the canonical static-quality gate
- `infernix test unit` owns Haskell and PureScript unit coverage
- `infernix test integration` owns cluster, publication, cache, object-store, routed auxiliary
  surfaces, and runtime-path integration coverage for the generated active-mode catalog
- `infernix test e2e` owns routed browser validation through the shared edge
- `infernix test all` aggregates the full supported suite

## Fail-Fast Rules

- validation fails on hard-gate violations; supported workflows do not silently rewrite tracked source
- `infernix test lint` stops on repo hygiene, chart, docs, proto, formatter, linter, compiler-warning, or Python quality failures
- the Haskell style gate may bootstrap `hlint` through a ghcup-managed compatible GHC when the
  active project compiler is newer than the currently supported `hlint` release
- runtime-mode-specific tests fail when required platform preflights are absent rather than quietly switching to another mode

## Matrix Rules

- integration and E2E coverage derive their target catalog from the generated active-mode demo config
- changing runtime mode changes the exercised catalog automatically
- the integration suite now enumerates every generated active-mode catalog entry rather than
  narrowing itself to one representative routed request
- the default E2E matrix always covers Apple and Linux CPU; Linux CUDA joins E2E when the
  supported NVIDIA preflight passes
- the current integration test binary enumerates Apple, Linux CPU, and Linux CUDA unless
  `--runtime-mode` or `INFERNIX_RUNTIME_MODE` narrows the lane
- `infernix test all` inherits that current split between the integration and E2E default matrices

## Boundary Rules

- browser E2E prefers the supported final path: host Playwright on Apple Silicon and the baked
  Linux substrate image on Linux when platform tooling is available; otherwise it falls back to
  the local npm runner
- production-path tests validate `infernix service` as a no-HTTP daemon
- the non-simulated `linux-cpu` integration lane also owns the current Harbor, MinIO, Pulsar, and
  Harbor PostgreSQL failure or lifecycle assertions
- the real-cluster `linux-cuda` lane also depends on enough host disk headroom for Kind image
  preload, Harbor-backed rollout, and Pulsar BookKeeper durability; low disk headroom is an
  environment failure, not a substitute for narrower matrix coverage
- adapter tests validate the Haskell-to-Python protobuf-over-stdio contract rather than an alternate ad hoc transport

## Cross-References

- [implementation_boundaries.md](implementation_boundaries.md)
- [portability.md](portability.md)
- [storage_and_state.md](storage_and_state.md)
- [../development/haskell_style.md](../development/haskell_style.md)
- [../development/testing_strategy.md](../development/testing_strategy.md)
