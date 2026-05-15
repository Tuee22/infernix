# CLI Reference

**Status**: Authoritative source
**Referenced by**: [cli_surface.md](cli_surface.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the supported `infernix` command surface and behavioral contract.

<!-- infernix:command-registry:start -->
## `infernix` (production daemon and operator workflow)

### `service`

- `infernix service` - starts the long-running production daemon; it binds no HTTP port and consumes the active `.dhall` request and result topics

### `cluster`

- `infernix cluster up` - reconciles Kind, Harbor-first bootstrap, the generated substrate file, and routed publication state
- `infernix cluster down` - tears the cluster down while leaving durable repo-local state under `./.data/` intact
- `infernix cluster status` - reports cluster presence, lifecycle phase, active substrate, publication state, build paths, and route inventory without mutation

### `cache`

- `infernix cache status` - reports the manifest-backed cache inventory for the active substrate
- `infernix cache evict [--model MODEL_ID]` - evicts derived cache state for one model or for the whole active substrate
- `infernix cache rebuild [--model MODEL_ID]` - rebuilds derived cache state from durable manifests for one model or for the whole active substrate

### `kubectl`

- `infernix kubectl ...` - wraps upstream `kubectl` and injects the repo-local kubeconfig for the active control-plane context

### `lint`

- `infernix lint files` - runs the tracked-file and generated-artifact hygiene checks
- `infernix lint docs` - runs the governed documentation validator
- `infernix lint proto` - runs the protobuf contract validator
- `infernix lint chart` - runs the Helm and chart ownership validator

### `test`

- `infernix test lint` - runs the focused lint entrypoints together with the strict Haskell style and Python quality gates
- `infernix test unit` - runs the Haskell unit suites and the PureScript frontend unit suites
- `infernix test integration` - runs the cluster-backed integration suite against the active substrate
- `infernix test e2e` - runs routed Playwright coverage for every demo-visible generated catalog entry
- `infernix test all` - runs lint, unit, integration, and routed E2E validation in sequence

### `docs`

- `infernix docs check` - runs the canonical documentation validator

### `internal`

- `infernix internal generate-purs-contracts PATH` - emits generated PureScript browser contracts into the requested output directory
- `infernix internal discover images RENDERED_CHART` - prints the unique image references discovered in a rendered chart manifest
- `infernix internal discover claims RENDERED_CHART` - prints the persistent-claim inventory discovered in a rendered chart manifest
- `infernix internal discover harbor-overlay OVERLAY` - prints the Harbor-backed image references discovered in a rendered override payload
- `infernix internal publish-chart-images RENDERED_CHART OUTPUT` - publishes the chart image inventory into a Harbor override file
- `infernix internal materialize-substrate RUNTIME_MODE [--demo-ui true|false]` - writes the generated substrate file for one explicit substrate id into the active build root
- `infernix internal demo-config load PATH` - loads one generated demo config and prints the rendered model listing
- `infernix internal demo-config validate PATH` - validates one generated demo config file
- `infernix internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT` - publishes one inference request through Pulsar and waits for the matching result
<!-- infernix:command-registry:end -->

## `infernix-demo` (demo UI HTTP host)

- `infernix-demo serve [--dhall PATH] [--port PORT]`

## Rules

- the `infernix` command inventory above is rendered from the Haskell command registry in
  `src/Infernix/CommandRegistry.hs`; `infernix docs check` fails if this generated section drifts
- `cluster up`, `cluster down`, `cluster status`, `cache ...`, `lint ...`, `test ...`,
  `docs check`, and `internal ...` are declarative CLI entrypoints; `infernix service` and
  `infernix-demo serve` are the only long-running daemon entrypoints
- `cluster status` is read-only and reports publication-state details together with route
  inventory, state paths, and lifecycle-progress fields
- `infernix internal materialize-substrate ...` is the supported way to restage
  `infernix-substrate.dhall`; `cluster up`, `service`, and the validation entrypoints do not
  regenerate it on first command execution
- `infernix service` is the production daemon. It binds no HTTP port, consumes the active
  `.dhall` `request_topics`, `result_topic`, and `engines` fields and uses the Pulsar transport
  configured for the active substrate
- `infernix-demo serve` is the only repo-owned demo HTTP host in this repository; the routed
  cluster-resident demo workload and direct `serve` both expose the same Haskell `/api` contract
  through `src/Infernix/Demo/Api.hs`
- `infernix cache status` reports the manifest-backed cache inventory for the active runtime
  mode; `cache evict` and `cache rebuild` only affect derived cache state
- `infernix kubectl ...` wraps upstream `kubectl` and injects the repo-local kubeconfig
- `cluster up` forwards any `INFERNIX_ENGINE_COMMAND_*` environment variables into the service
  deployment so adapter-specific engine command prefixes can be configured on the cluster path
  without rebuilding the image
- on the Linux outer-container cluster path, `cluster up`, `cluster status`, and `kubectl` keep
  host-published Kind and edge ports on `127.0.0.1` while reaching Kubernetes through the private
  Docker `kind` network and the internal kubeconfig
- on the Linux outer-container routed browser path, the forwarded Playwright executor joins the
  private Docker `kind` network, targets the Kind control-plane container DNS name, and probes the
  shared edge on port `30090` instead of looping back through `127.0.0.1`
- `infernix lint files|docs|proto|chart` run the canonical Haskell-implemented static checks
  (`src/Infernix/Lint/*`); `infernix test lint` runs them together with the strict Haskell
  warning gate, the `ormolu` and `hlint` style stack via the Cabal test target, and the active
  substrate's Python adapter quality gate via `poetry run check-code` when adapters are present;
  `infernix lint files` uses tracked files from `.git` when available and otherwise falls back to
  the baked `/opt/infernix/source-snapshot-files.txt` manifest on git-less Linux image runs; the
  style gate uses the dedicated compatible formatter toolchain `ghc-9.12.4` through `ghcup run`
  while the project build and runtime toolchain stays on `ghc-9.14.1`
- `infernix test unit` runs the Haskell unit suites and the PureScript frontend unit suites via
  `npm --prefix web run test:unit`
- `infernix test integration`, `infernix test e2e`, and `infernix test all` run their complete
  supported suites against the active substrate encoded in the generated `.dhall`
- `infernix test e2e` uses the dedicated `infernix-playwright:local` container on every substrate,
  invoked via `docker compose run --rm playwright`; Apple host-native flows run that compose
  invocation directly while Linux flows forward it from the outer container through the mounted
  host docker socket; Docker is required on every substrate, there is no host-native npm fallback
  path, Apple host-native flows reconcile `kind`, `kubectl`, `helm`, Node.js, and Poetry on
  demand after `./.build/infernix` exists, and Linux flows rely on the documented outer-container
  host baseline
- `infernix internal pulsar-roundtrip ...` is an internal validation helper that publishes one
  protobuf request through the configured Pulsar endpoints and waits for the matching result
- `infernix cluster up`, `test integration`, and `test e2e` fail fast on `linux-gpu` when the
  NVIDIA runtime prerequisites are absent

## Lifecycle Progress Surface

- `infernix cluster status` reports `lifecycleStatus: idle` together with `lifecyclePhase:
  not-yet-reconciled`, `steady-state`, or `cluster-absent` when no lifecycle action is running
- while `cluster up` or `cluster down` is active, `cluster status` reports `lifecycleStatus:
  in-progress` plus `lifecycleAction`, `lifecyclePhase`, `lifecycleDetail`,
  `lifecycleHeartbeatAt`, and `lifecycleHeartbeatAgeSeconds`
- the monitored long-running subprocess phases refresh `lifecycleHeartbeatAt` roughly every 30
  seconds while they are still progressing; the current implementation applies that heartbeat
  contract to the long Docker build, Harbor image publication, Kind-worker Harbor preload, and
  Apple retained-state replay steps
- elapsed wall time alone is not treated as failure on the supported path; treat a lifecycle
  action as still progressing while the current `lifecycleHeartbeatAt` continues to refresh, and
  treat it as stalled only when the command exits non-zero or the heartbeat stops moving across
  multiple monitor intervals

## Cross-References

- [cli_surface.md](cli_surface.md)
- [api_surface.md](api_surface.md)
- [../development/local_dev.md](../development/local_dev.md)
