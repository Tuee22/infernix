# CLI Reference

**Status**: Authoritative source
**Referenced by**: [cli_surface.md](cli_surface.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the supported `infernix` command surface and behavioral contract.

<!-- infernix:command-registry:start -->
## `infernix` (production daemon and operator workflow)

### `init`

- `infernix init [--runtime-mode apple-silicon|linux-cpu|linux-gpu] [--demo-ui true|false] [--force] [--if-missing]` - writes the runtime config `./infernix.dhall` and host manifest `./infernix-host.dhall`. Fails fast if `./infernix.dhall` already exists unless `--force`; `--if-missing` makes an existing config a no-op. No other command auto-generates config.

### `service`

- `infernix service [--role coordinator|engine|webapp] [--engine-name NAME] [--config PATH]` - starts one long-running role from the single infernix binary. Coordinator and engine roles consume the effective runtime-config request and result topics; the webapp role serves the demo HTTP/WebSocket surface. The optional `--role` arg overrides the runtime config's `daemonRole` field for split Deployments, `--engine-name` selects a stable engine member id, and `--config` points the daemon at an explicit runtime config.

### `cluster`

- `infernix cluster up` - requires the initialized repo-root runtime config, then reconciles Kind, Harbor-first bootstrap, its cluster deployment mirror, and routed publication state
- `infernix cluster down` - tears the cluster down while leaving durable repo-local state under `./.data/` intact
- `infernix cluster status` - reports cluster presence, lifecycle phase, active substrate, publication state, build paths, and route inventory; on Linux outer-container paths it may attach the launcher to Docker's `kind` network for observation
- `infernix cluster reclaim-slot [--force-owner-pid PID]` - reports the typed evidence for an interrupted harness cluster-slot reservation and retires it only after owner-death or an exact operator-transcribed PID premise, bounded-command quiescence, and config-transaction recovery

### `cache`

- `infernix cache status` - reports the manifest-backed cache inventory for the active substrate
- `infernix cache evict [--model MODEL_ID]` - evicts derived cache state for one model or for the whole active substrate
- `infernix cache rebuild [--model MODEL_ID]` - rebuilds derived cache state from durable manifests for one model or for the whole active substrate

### `kubectl`

- `infernix kubectl ...` - wraps an allowlisted read-only subset of upstream `kubectl` and injects the repo-local kubeconfig for the active control-plane context

### `lint`

- `infernix lint files` - runs the tracked-file and generated-artifact hygiene checks
- `infernix lint docs` - runs the governed-documentation and development-plan-shape validator (`runDocsLint`)
- `infernix lint proto` - runs the protobuf contract validator
- `infernix lint chart` - runs the Helm and chart ownership validator
- `infernix lint plan` - runs the development-plan standards scans for status vocabulary, dependency direction, accelerator scope, declarative language, and the removal ledger

### `test`

- `infernix test init [--runtime-mode apple-silicon|linux-cpu|linux-gpu] [--demo-ui true|false]` - writes the thin `./infernix.test.dhall` the test harness reads to generate the run's `./infernix.dhall`
- `infernix test lint` - runs the focused lint entrypoints together with the strict Haskell/Cabal style and Python quality gates
- `infernix test unit` - runs all machine-independent Haskell suites (compile-fail, artifact transaction, Apple materializer, capped observer, execution-plan, and unit) plus the PureScript frontend unit suite
- `infernix test integration` - runs the cluster-backed integration suite against the active substrate
- `infernix test e2e` - runs routed Playwright coverage for every demo-visible generated catalog entry
- `infernix test all` - runs lint, unit, integration, and routed E2E validation in sequence

### `docs`

- `infernix docs check` - alias of `lint docs` (same `runDocsLint`); runs the governed-documentation and development-plan-shape validator

### `internal`

- `infernix internal generate-purs-contracts PATH` - emits generated PureScript browser contracts into the requested output directory
- `infernix internal validate-darwin-build-memory` - runs the closed Darwin-only fresh toolchain build and reports sampled peak aggregate physical footprint evidence
- `infernix internal validate-darwin-audiveris-cancellation` - runs the fixed Darwin production Audiveris cancellation-recovery cohort gate
- `infernix internal validate-darwin-installed-python-source-isolation` - runs the fixed Darwin installed-Python source-isolation cohort gate
- `infernix internal discover images RENDERED_CHART` - prints the unique image references discovered in a rendered chart manifest
- `infernix internal discover claims RENDERED_CHART` - prints the persistent-claim inventory discovered in a rendered chart manifest
- `infernix internal discover harbor-overlay OVERLAY` - prints the Harbor-backed image references discovered in a rendered override payload
- `infernix internal publish-chart-images RENDERED_CHART OUTPUT` - publishes the chart image inventory into a Harbor override file
- `infernix internal materialize-substrate RUNTIME_MODE [--demo-ui true|false] [--empty-models]` - writes the generated runtime config and prepares the closed per-engine Python framework plan for one explicit substrate id
- `infernix internal materialize-metal-engines` - materializes the allowlisted Apple Metal/Core ML engine manifests under `./.data/engines/<adapterId>/` and prepares the canonical Apple per-engine Python framework plan through the Tart-free headless host lane (Apple-only; mirrors `internal materialize-substrate`)
- `infernix internal materialize-linux-native-engines` - materializes the allowlisted Linux native runner roots under `/opt/infernix/engines/<adapterId>/` for substrate images
- `infernix internal demo-config load PATH` - loads one generated demo config and prints the rendered model listing
- `infernix internal demo-config validate PATH` - validates one generated demo config file
- `infernix internal dhall-schema host|cluster|secrets|substrate` - prints the Dhall type expression reflected from the binary's decoder for one packaged schema
- `infernix internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT` - publishes one inference request through Pulsar and waits for the matching result
- `infernix internal playwright prepare-engine MODEL_ID` - selects the generated model's closed engine deployment under harness ownership
<!-- infernix:command-registry:end -->

## Rules

- the `infernix` command inventory above is rendered from the command metadata exposed by the
  Haskell command registry in `src/Infernix/CommandRegistry.hs`; `infernix docs check` fails if this
  generated section drifts
- `infernix internal materialize-metal-engines` remains in the generated inventory as the explicit
  Apple materialization helper. Its implementation is Tart-free and writes typed engine-artifact
  manifests under `./.data/engines/<adapterId>/`; it emits no repository-owned native source.
  The Apple hardware gate requires the upstream MLX GPU operation, coremltools device observation,
  materialized-artifact load, and routed real-output evidence named in
  [../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md)
- `cluster up`, `cluster down`, `cluster status`, `cluster reclaim-slot`, `cache ...`, `lint ...`,
  `test ...`, `docs check`, and `internal ...` are declarative CLI entrypoints; `infernix service`
  is the long-running daemon entrypoint for the Coordinator, Engine, and Webapp roles
- `cluster status` does not mutate Kubernetes resources, publication state, or authoritative
  repo-local state; reporting the persisted `clusterOwner` or a `mutation-incomplete` phase is an
  owner/state read, not a mutation; on the Linux outer-container path it may idempotently run
  `docker network connect kind <launcher-container>` so the fresh launcher can observe the Kind
  control plane over Docker's private `kind` network
- `cluster reclaim-slot` is the explicit interrupted-harness recovery boundary. It reports the
  recorded PID, process group, birth identity, PID-namespace relation, lifetime-lock observation,
  and resulting owner classification. An exact `--force-owner-pid` supplies only the operator's
  owner-death premise; it cannot bypass the kernel lifetime lock, bounded-command quiescence proof,
  or config-transaction recovery.
- operator config is created explicitly by `infernix init` at repo-root `./infernix.dhall`;
  ordinary substrate-aware entrypoints such as `cluster up`, `service`, `cache ...`, `kubectl ...`,
  frontend-contract generation, and aggregate `infernix test ...` commands do not auto-materialize
  it and fail fast naming the required init when config is absent. `infernix test init` creates the
  harness input `./infernix.test.dhall`.
- `infernix service` starts the selected role. Coordinator and engine roles bind no HTTP port,
  consume the active `.dhall` request/result topics, engine bindings, and engine-pool assignment
  metadata, and use the Pulsar transport configured for the active substrate. `--engine-name NAME`
  selects a stable engine member id from the derived pool/member graph; `--config PATH` is the
  supported explicit substrate-file override for targeted daemon validation and diagnostics. The
  Webapp role serves the demo HTTP/WebSocket surface through `src/Infernix/Demo/Api.hs` and is
  normally deployed as the demo-gated `infernix-demo` workload
- `infernix cache status` reports the manifest-backed cache inventory for the active runtime
  mode; `cache evict` and `cache rebuild` only affect derived cache state
- `infernix kubectl ...` wraps the allowlisted read-only diagnostic subset of upstream `kubectl`
  and injects the repo-local kubeconfig; mutating verbs and `exec` are rejected
- `cluster up` publishes the closed engine bindings generated in `infernix.dhall`; engine
  commands are derived from each compiled binding, and the cluster manifest has no arbitrary
  command-override field
- on the Linux outer-container cluster path, `cluster up`, `cluster status`, and `kubectl` keep
  host-published Kind and edge ports on `127.0.0.1` while reaching Kubernetes through the private
  Docker `kind` network and the internal kubeconfig
- on the Linux outer-container routed browser path, the forwarded Playwright executor joins the
  private Docker `kind` network, targets the Kind control-plane container DNS name, and probes the
  shared edge on port `30090` instead of looping back through `127.0.0.1`
- `infernix lint files|docs|proto|chart|plan` run the canonical Haskell-implemented static checks
  (`src/Infernix/Lint/*`); `infernix test lint` runs them together with the strict Haskell
  warning gate, the `ormolu` and `hlint` Haskell-style target, the Cabal 3.16 manifest-format target,
  and the active substrate's Python adapter quality gate via `poetry run check-code` when adapters are present;
  `infernix lint files` uses tracked files from `.git` when available and otherwise falls back to
  the baked `/opt/infernix/source-snapshot-files.txt` manifest on git-less Linux image runs; the
  the root Haskell-style component and solver-isolated Cabal-format package link their compatible
  pinned libraries and invoke their APIs in-process through sequential closed top-level toolchain
  children, without a runtime install or nested style-tool process
- `infernix test unit` runs every closed machine-independent Haskell suite — compile-fail,
  artifact transaction, Apple materializer, capped observer, execution-plan, and unit — through
  the live build-memory authority, then runs the PureScript frontend suite via
  `npm --prefix web run test:unit`; no focused Haskell gate requires a bare host Cabal command
- `infernix test integration`, `infernix test e2e`, and `infernix test all` run their complete
  supported suites against the active substrate encoded in the generated `.dhall`
- `infernix test e2e` uses the Playwright runtime baked into the Linux launcher image on Linux
  substrates and invokes `npm --prefix web exec -- playwright test` from inside the outer
  container against Docker's private `kind` network; the Apple host-native npm lane must pass its
  routed E2E gate. Apple host-native flows reconcile `kind`, `kubectl`,
  `helm`, Node.js, and Poetry on demand after `./.build/infernix` exists, and Linux flows rely on
  the documented outer-container
  host baseline
- `infernix internal pulsar-roundtrip ...` is an internal validation helper that publishes one
  protobuf request through the configured Pulsar endpoints and waits for the matching result
- `infernix cluster up`, `test integration`, and `test e2e` fail fast on `linux-gpu` when the
  NVIDIA runtime prerequisites are absent

## Lifecycle Progress Surface

- When no lifecycle action is running, `infernix cluster status` reports
  `lifecycleStatus: idle`, a `clusterOwner` (`OperatorOwned` or `HarnessOwned`), and one
  `lifecyclePhase`: `not-yet-reconciled`, `steady-state`, `mutation-incomplete`, or
  `cluster-absent`.
- `mutation-incomplete` means a killed harness left its `HarnessOwned` cluster mid-mutation rather
  than at `steady-state`; the next `cluster up` reconciles it.
- While `cluster up` or `cluster down` is active, `cluster status` reports
  `lifecycleStatus: in-progress` plus `lifecycleAction`, `lifecyclePhase`, `lifecycleDetail`,
  `lifecycleHeartbeatAt`, and `lifecycleHeartbeatAgeSeconds`.
- Long Docker builds, Harbor image publication, Kind-worker Harbor preload, and Apple retained-state
  replay refresh `lifecycleHeartbeatAt` roughly every 30 seconds while progressing. Elapsed wall
  time alone is not failure; a non-zero owning command or a heartbeat that stops across multiple
  monitor intervals is a stall/failure signal.
- The status fields are projections of the typed `ClusterLifecycle` machine, whose
  `ClusterMutating LifecyclePhase` position produces the `mutation-incomplete` reading alongside
  persisted `ClusterOwner`. Canonical contract: [Managed State
  Transitions](../architecture/managed_state_transitions.md).

## Cross-References

- [cli_surface.md](cli_surface.md)
- [api_surface.md](api_surface.md)
- [../development/local_dev.md](../development/local_dev.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
