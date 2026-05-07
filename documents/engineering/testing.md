# Testing Doctrine

**Status**: Authoritative source
**Referenced by**: [../development/testing_strategy.md](../development/testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Define the canonical testing entrypoints, fail-fast behavior, and supported validation boundaries.

## Executive Summary

- `infernix docs check`, `infernix test lint`, `infernix test unit`, `infernix test integration`,
  `infernix test e2e`, and `infernix test all` are the only supported validation entrypoints.
- Validation is fail-fast: it reports drift or missing prerequisites and stops instead of silently
  rewriting tracked source or substituting another lane.
- Integration and routed E2E coverage derive their target set from the active generated catalog,
  so changing runtime mode changes the exercised entries automatically.
- Monitoring is not a supported first-class surface, so no validation entrypoint claims to gate
  dashboards, scrape config, or alerting behavior.

## Preflight Expectations

- supported validation starts from the supported execution context for the selected runtime mode
- supported validation expects the generated substrate file for that runtime mode to exist before
  the suite starts
- Apple host-native flows expect the built binary plus the minimal Homebrew-plus-ghcup baseline;
  supported commands may reconcile the remaining host tools on demand, and the staged host config
  comes from `./.build/infernix internal materialize-substrate apple-silicon`
- `linux-cpu` flows expect Docker Engine plus the Docker Compose plugin
- `linux-gpu` flows expect the `linux-cpu` Docker baseline plus the supported NVIDIA driver and
  container-toolkit setup
- real-cluster `linux-gpu` validation also expects enough disk headroom for Kind image preload,
  Harbor-backed rollout, and Pulsar BookKeeper durability

## Canonical Entry Points

| Entry point | Responsibility |
|-------------|----------------|
| `infernix docs check` | validate the governed docs suite, metadata, required doctrine structure, generated sections, phase-plan shape, and monitoring-stance alignment |
| `infernix test lint` | run repo hygiene, chart, docs, proto, Haskell style, build, and Python quality checks |
| `infernix test unit` | own Haskell and PureScript unit coverage, including generated-catalog logic and the protobuf-over-stdio worker boundary |
| `infernix test integration` | validate cluster lifecycle, publication state, routed auxiliary surfaces, cache flows, service-loop behavior, and every generated active-mode catalog entry |
| `infernix test e2e` | validate the routed browser surface and every demo-visible generated catalog entry through Playwright |
| `infernix test all` | run the full supported suite in sequence |

## Validation Obligations

- `infernix docs check` proves that the governed docs and the development plan still match the
  supported contract, including the required structure for broad doctrine docs.
- `infernix test lint` proves repo-owned static quality, the Haskell style gate, the Haskell build
  warning policy, and the shared Python adapter quality gate.
- `infernix test unit` proves the typed control-plane and browser-contract logic that should not
  require a live cluster, and keeps the Node-based PureScript runner on non-deprecated
  `purescript-spec` entrypoints.
- `infernix test integration` proves the active runtime mode's generated catalog, routed surfaces,
  publication state, cache contract, and the real cluster's HA or lifecycle assertions.
- `infernix test e2e` proves that the browser workbench can exercise every demo-visible generated
  catalog entry through the shared routed surface, with supported Playwright launchers sanitizing
  conflicting `NO_COLOR` and `FORCE_COLOR` pairs before the child process starts.
- `infernix test all` proves that the repository passes the supported aggregate validation flow
  without dropping any layer.

## Unsupported Paths

- ad hoc wrapper scripts or alternate validation entrypoints in place of the canonical `infernix`
  commands; the supported `bootstrap/*.sh` layer may invoke those canonical commands, but it does
  not define a second validation contract
- silently narrowing integration or E2E coverage to one representative model when the generated
  active-mode catalog contains more entries
- quietly swapping to another runtime mode when required substrate preflights are absent
- treating monitoring dashboards, metrics stacks, or scrape configuration as a supported gated
  contract in the current repository state

## Cross-References

- [implementation_boundaries.md](implementation_boundaries.md)
- [portability.md](portability.md)
- [storage_and_state.md](storage_and_state.md)
- [../development/haskell_style.md](../development/haskell_style.md)
- [../development/testing_strategy.md](../development/testing_strategy.md)

## Validation

- validation fails on hard-gate violations; supported workflows do not silently rewrite tracked
  source
- the Haskell style gate uses the dedicated compatible formatter toolchain `ghc-9.12.4` through
  `ghcup run` while the project build and runtime toolchain stays on `ghc-9.14.1`
- runtime-mode-specific tests fail when required platform preflights are absent rather than
  quietly switching to another mode
- the supported Node-based web validation paths stay warning-free by avoiding deprecated
  `runSpec` or `runSpecT` entrypoints and by clearing conflicting `NO_COLOR` or `FORCE_COLOR`
  pairs before Playwright starts
- `infernix test integration`, `infernix test e2e`, and `infernix test all` report only the
  active substrate encoded in the generated `.dhall`
- supported Apple E2E keeps the host CLI in charge of orchestration while the actual Playwright
  executor runs through `docker compose run --rm playwright` against the dedicated
  `infernix-playwright:local` image; the Linux outer-container path forwards the same compose
  invocation through the mounted host docker socket
- `infernix test e2e` requires Docker, kind, kubectl, and helm on every substrate; there is no
  host-native npm fallback path
