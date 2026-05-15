# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Current Status

- the supported Apple clean-host contract reduces pre-existing host requirements to Homebrew plus
  ghcup before the binary is built
- the Apple stage-0 bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables
  plus Homebrew `protoc` before direct `cabal install`, so the supported clean-host first run does
  not depend on rerunning the same bootstrap command after Cabal is first installed
- Colima is the only supported Docker environment on Apple Silicon
- after `./.build/infernix` exists, supported commands reconcile Homebrew-managed Colima, Docker
  CLI, `kind`, `kubectl`, `helm`, and Node.js on demand, reconcile Colima to the supported
  `8 CPU / 16 GiB` profile before Docker-backed work, and let adapter setup or validation paths
  reconcile Homebrew `python@3.12` at `/opt/homebrew/opt/python@3.12/bin/python3.12` plus a
  user-local Poetry bootstrap when needed
- on May 14, 2026, the supported Apple lifecycle reran cleanly through `doctor`, `build`, `up`,
  `status`, `test`, `down`, and final `status`; that rerun validated the split daemon topology,
  host-batch Pulsar handoff, routed Playwright E2E, repeated retained-state cluster bring-up or
  teardown cycles inside `test all`, and final post-teardown status reported
  `clusterPresent: False`
- the May 13, 2026 Apple lifecycle investigation remains the proof point that long waits can still
  be healthy while the supported path is replaying retained Kind data, building the shared runtime
  image, publishing it through Harbor, or preloading Harbor-backed images onto the Kind worker;
  Harbor Docker pushes use readiness-gated bounded retries across transient registry resets
- retained-state Apple reruns may also log a targeted Harbor PostgreSQL replica reinitialization
  from the current Patroni leader when stopped replicas need a fresh base backup after timeline
  advancement; treat that as supported retained-state repair rather than an unexpected failure mode

## Supported Flow

- run `./bootstrap/apple-silicon.sh up`
- run `./bootstrap/apple-silicon.sh status`
- run `./bootstrap/apple-silicon.sh test`
- use `./.build/infernix kubectl ...` instead of mutating global
  kubeconfig
- run `./bootstrap/apple-silicon.sh down` when tearing the cluster down

The first supported host-native command that needs Docker, Kubernetes tooling, Node.js, Python, or
Poetry reconciles those prerequisites automatically.

Direct reference path:

- build both Haskell binaries with
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
- stage the active substrate file with
  `./.build/infernix internal materialize-substrate apple-silicon`
- run `./.build/infernix cluster up`
- run `./.build/infernix test all`

## Cold Start Expectations

- use `./bootstrap/apple-silicon.sh status` or `./.build/infernix cluster status` before treating
  a long `up`, `test`, or `down` run as failed
- cold or retained-state Apple runs can spend many minutes in `prepare-kind-cluster`,
  `build-cluster-images`, `publish-harbor-images`, `preload-harbor-images`, and
  `replay-retained-state`; a cold `build-cluster-images` phase can remain healthy well past
  twenty minutes before Harbor publication begins
- `publish-harbor-images` includes readiness-gated bounded retries for Docker push failures, so a
  transient registry reset during large-image publication is not a hard failure unless the retry
  budget is exhausted and the image is still neither tagged nor pullable
- `./bootstrap/apple-silicon.sh test` is not a single cluster round-trip: the governed test lane
  may perform multiple internal cluster bring-up or teardown cycles through integration and E2E
  before the outer bootstrap command returns
- when `cluster status` reports `lifecycleStatus: in-progress`, the supported surface also reports
  `lifecycleAction`, `lifecyclePhase`, `lifecycleDetail`, `lifecycleHeartbeatAt`, and
  `lifecycleHeartbeatAgeSeconds`
- the supported Apple doctrine is inactivity-aware: wall-clock duration alone is not failure
- during the monitored long-running subprocess phases, the lifecycle heartbeat refreshes roughly
  every 30 seconds; treat that as active progress, and treat the action as stalled only when the
  command exits non-zero or the heartbeat stops refreshing across multiple intervals
- if a retained-state rerun logs Harbor PostgreSQL replica repair from the current leader, treat
  that as an expected recovery step on the supported path and wait for the same heartbeat-driven
  progress rules instead of treating the repair itself as hard failure

## Rules

- the Apple host operator workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter validation or setup path is
  exercised explicitly
- supported Apple host shell is limited to `./bootstrap/apple-silicon.sh`; the direct `cabal`
  command lets cabal use its natural `dist-newstyle` builddir at the project root and only
  overrides `--installdir=./.build` so the materialized `./.build/infernix` and
  `./.build/infernix-demo` binaries land where the supported CLI surface expects them
- supported Apple bootstrap commands are restartable stage-0 entrypoints: when host prerequisite
  reconciliation crosses a real new-shell or reboot boundary, rerun the same
  `./bootstrap/apple-silicon.sh <command>` surface rather than jumping straight to a later direct
  command; same-process tool installation continues only after the bootstrap verifies the required
  executable explicitly
- supported Apple host workflows stage `./.build/infernix-substrate.dhall` explicitly through
  `./.build/infernix internal materialize-substrate apple-silicon`; add `--demo-ui false` when
  preparing a demo-off config
- `cluster up` writes `./.build/infernix.kubeconfig`
- supported flows do not mutate `$HOME/.kube/config`
- the Apple host-native path describes where the Haskell build, control-plane commands, cluster
  daemon orchestration, and host inference executor run; `cluster up` adds `infernix-demo` when
  `demo_ui` is enabled and always deploys the cluster `infernix-service` daemon set
- on `apple-silicon`, the clustered demo and cluster service workloads run from the
  `infernix-linux-cpu:local` image family while reading the staged `apple-silicon` substrate file;
  cluster daemons own request fan-in and batch handoff, not Apple-native inference execution
- `/api/publication` keeps the routed demo API on `apiUpstream.mode: cluster-demo`, reports
  `daemonLocation: cluster-pod`, reports `inferenceExecutorLocation: control-plane-host`, and
  publishes `inferenceDispatchMode: pulsar-bridge-to-host-daemon` so the routed demo surface can
  advertise the cluster-daemon plus host-executor split explicitly
- the direct `infernix service` host run consumes the generated host daemon metadata and host batch
  topic, auto-discovers the routed Pulsar edge from published cluster state when needed, and forks
  Python adapters from `python/adapters/` only when the bound engine is Python-native
- the Apple host bootstrap uses Homebrew-managed Colima, Docker CLI, `kind`, `kubectl`, `helm`,
  Node.js, and related operator tools rather than a broader manual prerequisite list
- the Apple host bootstrap reconciles Colima to at least `8 CPU / 16 GiB` before Docker-backed
  lifecycle or validation work proceeds
- routed Apple E2E readiness probes use the published host edge on `127.0.0.1:<edge-port>`, but
  the dedicated Playwright container joins the private Docker `kind` network and targets the Kind
  control-plane DNS instead of `host.docker.internal`
- retained Apple Kind state under `./.data/kind/apple-silicon/` is replayed into and out of the
  worker instead of being bind-mounted, so large retained state can make `up`, `test`, and
  `down` noticeably slower than Linux
- `infernix service` runs `ensureAppleSiliconRuntimeReady` before the daemon loop. That flow
  ensures the shared `python/` project is installed, creates repo-local engine roots under
  `./.data/engines/`, and invokes each `poetry run setup-*` entrypoint for the active mode's
  Python-native engine bindings
- the Apple bootstrap also reconciles Homebrew `python@3.12` at
  `/opt/homebrew/opt/python@3.12/bin/python3.12` plus a user-local Poetry bootstrap when the
  `poetry` executable is absent, after which the shared `python/.venv/` still materializes only on
  demand
- the current `setup-*` entrypoints remain idempotent preflight hooks layered on top of that
  prerequisite bootstrap and shared-project install flow

## Cross-References

- [cluster_bootstrap_runbook.md](cluster_bootstrap_runbook.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
