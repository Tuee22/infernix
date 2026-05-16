# Testing Doctrine

**Status**: Authoritative source
**Referenced by**: [../development/testing_strategy.md](../development/testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Define the canonical testing entrypoints, fail-fast behavior, and supported validation boundaries.

## Executive Summary

- the supported validation surface includes the focused `infernix lint files`, `infernix lint docs`,
  `infernix lint proto`, and `infernix lint chart` checks together with the aggregate
  `infernix docs check`, `infernix test lint`, `infernix test unit`,
  `infernix test integration`, `infernix test e2e`, and `infernix test all` entrypoints
- Validation is fail-fast: it reports drift or missing prerequisites and stops instead of silently
  rewriting tracked source or substituting another lane.
- Integration and routed E2E coverage derive their target set from the active generated catalog,
  so changing the staged substrate changes the exercised entries automatically.
- Monitoring is not a supported first-class surface, so no validation entrypoint claims to gate
  dashboards, scrape config, or alerting behavior.

## Preflight Expectations

- supported validation starts from the supported execution context for the selected substrate
- focused static checks, including `infernix lint files`, `infernix lint docs`,
  `infernix lint proto`, `infernix lint chart`, and `infernix docs check`, are substrate-file
  independent because they validate tracked source, governed docs, schemas, and chart structure
- substrate-aware entrypoints, including runtime, cluster, cache, Kubernetes-wrapper,
  frontend-contract generation, and aggregate `infernix test ...` commands, expect the generated
  substrate file for the selected substrate to exist before their suite starts
- Apple host-native flows expect the built binary plus the minimal Homebrew-plus-ghcup baseline;
  supported commands may reconcile the remaining host tools on demand, and the staged host config
  comes from `./.build/infernix internal materialize-substrate apple-silicon`
- `linux-cpu` flows expect Docker Engine plus the Docker Compose plugin
- `linux-gpu` flows expect the `linux-cpu` Docker baseline plus the supported NVIDIA driver and
  container-toolkit setup
- real-cluster `linux-gpu` validation also expects enough disk headroom for Kind image preload,
  Harbor-backed rollout, and Pulsar BookKeeper durability

## Lifecycle Failure Classification

- on May 15, 2026, the supported Apple lifecycle reran cleanly through `doctor`, `build`, `up`,
  `status`, `test`, `down`, and final `status`; the full `test all` lane completed lint, unit,
  integration, split-daemon Apple inference, routed browser coverage, repeated retained-state
  cluster bring-up or teardown cycles, and final cleanup. The May 13 lifecycle investigation
  remains the proof point that long waits in Docker build finalization, Harbor publication,
  Kind-worker image preload, and retained-state replay are real convergence when heartbeat data is
  moving, not hard product failure. The May 15 lifecycle rerun also validates repo-owned local
  image publication ordering and source re-tagging before each bounded Harbor push retry.
- the supported doctrine is inactivity-aware: elapsed wall time alone is not enough to classify
  `cluster up`, `cluster down`, `test integration`, `test e2e`, or `test all` as failed when the
  active path still owns cluster lifecycle
- use `infernix cluster status` as the supported progress surface before abandoning a long-running
  lifecycle action
- while `cluster status` reports `lifecycleStatus: in-progress`, treat the current action as still
  progressing when the reported `lifecycleHeartbeatAt` continues to refresh
- the current implementation refreshes that heartbeat roughly every 30 seconds during the
  long-running Docker build, Harbor image publication, Kind-worker Harbor preload, and Apple
  retained-state replay subprocess phases
- the same inactivity-aware classification applies when supported integration or E2E lanes own
  internal cluster bring-up or teardown rounds inside `infernix test all`
- treat the supported path as stalled only when the command exits non-zero or the heartbeat stops
  refreshing across multiple monitor intervals during one of those monitored phases

## Canonical Entry Points

| Entry point | Responsibility |
|-------------|----------------|
| `infernix lint files` | validate tracked-file hygiene and generated-artifact placement |
| `infernix lint docs` | run the governed documentation validator directly |
| `infernix lint proto` | validate the protobuf contract set |
| `infernix lint chart` | validate Helm chart ownership and route-registry alignment |
| `infernix docs check` | validate the governed docs suite, metadata, required doctrine structure, generated sections, phase-plan shape, and monitoring-stance alignment |
| `infernix test lint` | run repo hygiene, chart, docs, proto, Haskell style, build, and Python quality checks |
| `infernix test unit` | own Haskell and PureScript unit coverage, including generated-catalog logic and the protobuf-over-stdio worker boundary |
| `infernix test integration` | validate cluster lifecycle, publication state, routed auxiliary surfaces, cache flows, service-loop behavior, and every generated active-mode catalog entry |
| `infernix test e2e` | validate the routed browser surface and every demo-visible generated catalog entry through Playwright |
| `infernix test all` | run every supported validation layer in sequence for the active staged substrate |

## Validation Obligations

- `infernix lint files`, `infernix lint docs`, `infernix lint proto`, and `infernix lint chart`
  provide the focused validation entrypoints for repository hygiene, governed docs, protobuf
  schemas, and chart ownership when a narrower check is the supported tool for the task at hand.
- `infernix docs check` proves that the governed docs and the development plan still match the
  supported contract, including the required structure for broad doctrine docs.
- `infernix test lint` proves repo-owned static quality, the Haskell style gate, the Haskell build
  warning policy, and the shared Python adapter quality gate.
- `infernix test unit` proves the typed control-plane and browser-contract logic that should not
  require a live cluster, and keeps the Node-based PureScript runner on non-deprecated
  `purescript-spec` entrypoints.
- `infernix test integration` proves the active staged substrate's generated catalog, routed surfaces,
  publication state, cache contract, and the real cluster's HA or lifecycle assertions.
- `infernix test e2e` proves that the browser workbench can exercise every demo-visible generated
  catalog entry through the shared routed surface, with supported Playwright launchers sanitizing
  conflicting `NO_COLOR` and `FORCE_COLOR` pairs before the child process starts.
- `infernix test all` proves that the repository passes the supported aggregate validation flow for
  the active staged substrate without dropping any layer.

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
- `infernix test integration`, `infernix test e2e`, and `infernix test all` run against and report
  the active substrate encoded in the generated `.dhall`
- supported Apple E2E keeps the host CLI in charge of orchestration while the actual Playwright
  executor runs through `docker compose run --rm playwright` against the dedicated
  `infernix-playwright:local` image; the Linux outer-container path forwards the same compose
  invocation through the mounted host docker socket
- supported Apple integration and E2E own the host daemon lifecycle when the routed demo surface
  needs it, so the validation contract proves the cluster daemon plus host inference executor
  bridge rather than treating an in-cluster pod as the Apple-native inference executor
- `infernix test e2e` requires Docker on every substrate and has no host-native npm fallback
  path; on Apple host-native flows the supported command reconciles `kind`, `kubectl`, `helm`,
  Node.js, and Poetry on demand after `./.build/infernix` exists, while Linux flows rely on the
  documented outer-container host baseline
