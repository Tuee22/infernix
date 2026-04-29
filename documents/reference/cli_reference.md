# CLI Reference

**Status**: Authoritative source
**Referenced by**: [cli_surface.md](cli_surface.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the supported `infernix` command surface and behavioral contract.

<!-- infernix:command-registry:start -->
## `infernix` (production daemon and operator workflow)

### `service`

- `infernix service` - starts the long-running production daemon; it binds no HTTP port and consumes the active `.dhall` request and result topics

### `cluster`

- `infernix cluster up` - reconciles Kind, Harbor-first bootstrap, generated demo config, and routed publication state
- `infernix cluster down` - tears the cluster down while leaving durable repo-local state under `./.data/` intact
- `infernix cluster status` - reports cluster presence, runtime mode, publication state, build paths, and route inventory without mutation

### `cache`

- `infernix cache status` - reports the manifest-backed cache inventory for the active runtime mode
- `infernix cache evict [--model MODEL_ID]` - evicts derived cache state for one model or for the whole active runtime mode
- `infernix cache rebuild [--model MODEL_ID]` - rebuilds derived cache state from durable manifests for one model or for the whole active runtime mode

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
- `infernix test integration` - runs the cluster-backed integration suite against the active runtime mode or matrix
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
- `infernix internal demo-config load PATH` - loads one generated demo config and prints the rendered model listing
- `infernix internal demo-config validate PATH` - validates one generated demo config file
- `infernix internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT` - publishes one inference request through Pulsar and waits for the matching result

Runtime-mode override:

- `infernix [--runtime-mode apple-silicon|linux-cpu|linux-cuda] COMMAND`
<!-- infernix:command-registry:end -->

## `infernix-demo` (demo UI HTTP host)

- `infernix-demo serve --dhall PATH --port N`

## Rules

- the `infernix` command inventory above is rendered from the Haskell command registry in
  `src/Infernix/CommandRegistry.hs`; `infernix docs check` fails if this generated section drifts
- `cluster up`, `cluster down`, `cluster status`, `cache ...`, `lint ...`, `test ...`,
  `docs check`, and `internal ...` are declarative CLI entrypoints; `infernix service` and
  `infernix-demo serve` are the only long-running daemon entrypoints
- `cluster status` is read-only and reports publication-state details together with route
  inventory and state paths
- `infernix service` is the production daemon. It binds no HTTP port, consumes the active
  `.dhall` `request_topics`, `result_topic`, and `engines` fields, uses real Pulsar
  WebSocket or admin endpoints when `INFERNIX_PULSAR_WS_BASE_URL` and
  `INFERNIX_PULSAR_ADMIN_URL` are set, and otherwise falls back to
  `filesystem-pulsar-simulation`
- `infernix-demo serve` is the only supported HTTP host in this repository; the `infernix-demo`
  cluster workload and the host-native `infernix-demo serve` invocation provide the same demo
  `/api` contract through `src/Infernix/Demo/Api.hs`
- `infernix cache status` reports the manifest-backed cache inventory for the active runtime
  mode; `cache evict` and `cache rebuild` only affect derived cache state
- `infernix kubectl ...` wraps upstream `kubectl` and injects the repo-local kubeconfig
- `cluster up` forwards any `INFERNIX_ENGINE_COMMAND_*` environment variables into the service
  deployment so adapter-specific engine command prefixes can be configured on the cluster path
  without rebuilding the image
- when Docker, Kind, Helm, or kubectl are unavailable, `cluster up` falls back to the simulated
  substrate and `cluster status` reports that explicitly
- on the Linux outer-container cluster path, `cluster up`, `cluster status`, `kubectl`, and
  routed browser checks keep host-published Kind and edge ports on `127.0.0.1` while reaching
  Kubernetes through the private Docker `kind` network and the internal kubeconfig
- `infernix lint files|docs|proto|chart` run the canonical Haskell-implemented static checks
  (`src/Infernix/Lint/*`); `infernix test lint` runs them together with the strict Haskell
  warning gate, the `ormolu` and `hlint` style stack via the Cabal test target, and the active
  substrate's Python adapter quality gate via `poetry run check-code` when adapters are present;
  `infernix lint files` uses tracked files from `.git` when available and otherwise falls back to
  the baked `/opt/build/infernix/source-snapshot-files.txt` manifest on git-less Linux image runs;
  the style gate may bootstrap `hlint` through a ghcup-managed compatible GHC when the active
  project compiler is newer than the current `hlint` release line
- `infernix test unit` runs the Haskell unit suites and the PureScript frontend unit suites via
  `npm --prefix web run test:unit`
- `infernix test e2e` launches Playwright from the host on Apple Silicon, from the active Linux
  substrate image on Linux when the platform toolchain is available, and otherwise falls back to
  the local npm runner
- `infernix internal pulsar-roundtrip ...` is an internal validation helper that publishes one
  protobuf request through the configured Pulsar endpoints and waits for the matching result
- `infernix test integration`, `infernix test e2e`, and `infernix test all` honor
  `--runtime-mode` when supplied; without it, the current integration test binary enumerates all
  three runtime modes, while E2E includes Linux CUDA only when the active control-plane surface
  passes the NVIDIA preflight contract
- pass `--runtime-mode` when a single predictable validation lane is required
- `infernix --runtime-mode linux-cuda cluster up`, `test integration`, and `test e2e` fail fast
  with a host-preflight error when the NVIDIA runtime prerequisites are absent
- `--runtime-mode` accepts `apple-silicon`, `linux-cpu`, or `linux-cuda`

## Cross-References

- [cli_surface.md](cli_surface.md)
- [api_surface.md](api_surface.md)
- [../development/local_dev.md](../development/local_dev.md)
