# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Current Status

- the supported Apple clean-host contract reduces pre-existing host requirements to Homebrew plus
  ghcup before the binary is built
- the Apple stage-0 bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables
  plus Homebrew `protoc` before direct `cabal install`, so the supported clean-host first run does
  not depend on rerunning the same bootstrap command after Cabal is first installed
- Docker-backed Apple work uses the operator's already selected native arm64 Docker daemon. The
  supported workflow must not create or switch Docker contexts, create a Colima VM, or use
  cross-architecture emulation
- after `./.build/infernix` exists, supported commands may reconcile Homebrew-managed `kind`,
  `kubectl`, `helm`, and Node.js on demand, and let adapter setup or validation paths reconcile
  the Homebrew-managed `python@3.12` formula and `python3.12` command plus a user-local Poetry
  bootstrap when needed; the Poetry bootstrap may reuse an already available compatible Python
  3.12+ executable when one passes the implemented version check
- the Apple bootstrap shell owns only host prerequisite reconciliation through the host binary
  build and then invokes `./.build/infernix <command>`; the host binary owns Kind, Kubernetes,
  container builds, Harbor publication, and any cluster workload image pulls needed after it exists,
  but it must not provision Docker virtualization or switch Docker contexts
- the Apple lifecycle now keeps Kind lock-taking off repo-visible paths by using a host-local
  scratch kubeconfig under the system temp directory during cluster create or delete and then
  publishing the durable repo-local kubeconfig under `./.build/`
- current Apple validation evidence is recorded in
  [../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md);
  the legacy-tracking ledger at
  [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
  records obsolete-surface receipts
- long waits can be healthy while the supported path is replaying retained Kind data, building
  the shared runtime image, publishing it through Harbor, or preloading Harbor-backed images
  onto the Kind worker; Harbor Docker pushes use readiness-gated bounded retries across
  transient registry resets
- retained-state Apple reruns may also log a targeted Harbor PostgreSQL replica reinitialization
  from the current Patroni leader when stopped replicas need a fresh base backup after timeline
  advancement, or a non-waiting recycle of unready Harbor PostgreSQL startup pods when Patroni
  readiness does not converge; treat those as supported retained-state repair rather than
  unexpected failure modes
- Apple Metal/Core ML engine materialization uses a Tart-free headless host lane. The retained
  `materialize-metal-engines` helper name now writes typed engine-artifact manifests; the Apple
  cohort still owns the host Metal runtime bridge smoke and native artifact load evidence named in
  [../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

## Supported Flow

- run `./bootstrap/apple-silicon.sh up`
- run `./bootstrap/apple-silicon.sh status`
- run `./bootstrap/apple-silicon.sh test`
- use `./.build/infernix kubectl ...` instead of mutating global
  kubeconfig
- run `./bootstrap/apple-silicon.sh down` when tearing the cluster down

The first supported host-native command that needs Kubernetes tooling, Node.js, Python, or Poetry
may reconcile those prerequisites automatically. Docker is different: the current Docker context
must already point at a native arm64 daemon before Docker-backed cluster work begins.

Direct reference path:

- build both Haskell binaries with
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
- run `./.build/infernix cluster up`
- run `./.build/infernix test all`

## Cold Start Expectations

- use `./bootstrap/apple-silicon.sh status` or `./.build/infernix cluster status` before treating
  a long `up`, `test`, or `down` run as failed
- cold or retained-state Apple runs can spend many minutes in `prepare-kind-cluster`,
  `build-cluster-images`, `publish-harbor-images`, `preload-harbor-images`, and
  `replay-retained-state`; a cold `build-cluster-images` phase can remain healthy well past
  twenty minutes before Harbor publication begins
- on host-native Apple, `build-cluster-images` reuses `infernix-linux-cpu:local` only when the local
  image carries the current source fingerprint, runtime-mode label, architecture, and pushable
  manifest shape; the first run after source changes may rebuild, while unchanged-source reruns
  should reuse the stamped image before Harbor publication
- `infernix test integration` may perform several internal cluster cycles. A source edit changes
  the fingerprint and forces one rebuild; subsequent cycles in the same run should print
  `reusing cluster image for linux-cpu: infernix-linux-cpu:local` when source is unchanged. The
  2026-06-15 Apple integration rerun exercised that pattern and completed successfully.
- `publish-harbor-images` includes readiness-gated bounded retries for Docker push failures, so a
  transient registry reset during large-image publication is not a hard failure unless the retry
  budget is exhausted and the image is still neither tagged nor pullable; repo-owned local images
  are published before third-party chart dependencies and are re-tagged from their source image
  before each retry so recovery does not depend on a retained target tag
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
- if warmup logs a Harbor PostgreSQL startup-pod recycle, the delete is intentionally non-waiting;
  StatefulSet recreation and final readiness are owned by the surrounding lifecycle wait loop

## Rules

- the Apple host operator workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter validation or setup path is
  exercised explicitly
- supported Apple host shell is limited to `./bootstrap/apple-silicon.sh`; the direct `cabal`
  command lets cabal use its natural `dist-newstyle` builddir at the project root and only
  overrides `--installdir=./.build` so the materialized `./.build/infernix`
  binary lands where the supported CLI surface expects it
- after the host binary exists, the bootstrap shell does not call `kind`, `kubectl`, `helm`, apply
  manifests, pull images, build the cluster runtime image, or publish to Harbor directly; it calls
  `./.build/infernix <command>` and lets the binary own those lifecycle responsibilities
- supported Apple bootstrap commands are restartable stage-0 entrypoints: when host prerequisite
  reconciliation crosses a real new-shell or reboot boundary, rerun the same
  `./bootstrap/apple-silicon.sh <command>` surface rather than jumping straight to a later direct
  command; same-process tool installation continues only after the bootstrap verifies the required
  executable explicitly
- supported Apple lifecycle and validation commands materialize or verify
  `./.build/infernix-substrate.dhall` through the binary-owned substrate path;
  `./.build/infernix internal materialize-substrate apple-silicon` remains the direct helper when
  an operator intentionally needs to restage or inspect that file
- Kind create or delete uses a host-local scratch kubeconfig under the system temp directory, and
  `cluster up` publishes `./.build/infernix.kubeconfig` afterward
- supported flows do not mutate `$HOME/.kube/config`
- the Apple host-native path describes where the Haskell build, control-plane commands,
  cluster-side coordinator orchestration, and on-host engine executor run. The three-role
  daemon model in [../architecture/daemon_topology.md](../architecture/daemon_topology.md) maps
  to Apple as: cluster-side `infernix-coordinator` Deployment plus on-host `Engine`-role daemon
  (the `infernix service` process). `cluster up` adds `infernix-demo` when `demo_ui` is enabled
  and always deploys the cluster `infernix-coordinator` Deployment
- on `apple-silicon`, the clustered demo and coordinator workloads run from the
  `infernix-linux-cpu:local` image family while reading the staged `apple-silicon` substrate file;
  the coordinator role owns request fan-in and batch handoff, not Apple-native inference
  execution, and the host-native `infernix` binary builds or freshness-reuses that image family and
  publishes it to Harbor after Harbor is responsive
- `/api/publication` keeps the routed demo API on `apiUpstream.mode: cluster-demo`, reports
  `daemonLocation: cluster-pod`, reports `inferenceExecutorLocation: control-plane-host`, and
  publishes `inferenceDispatchMode: pulsar-bridge-to-host-daemon` so the routed demo surface can
  advertise the coordinator-plus-host-engine split explicitly
- the direct `infernix service` host run carries the engine daemon role: it consumes the generated
  engine-pool membership for its Apple host id, auto-discovers Pulsar's direct un-gated proxy
  NodePort transport (the `/admin/v2` and `/ws/v2` surfaces, not the JWT-gated `/pulsar/admin`
  edge) from published cluster state when needed, and forks Python adapters from `python/adapters/`
  only when the bound engine is Python-native. Normal Apple pools use Pulsar `Shared`
  subscriptions across distinct host ids so broker-native backpressure assigns work to available
  hosts; exact-host routes use derived per-host topics with `Exclusive`. Current Apple integration
  evidence includes two same-machine host-member daemons on one `Shared` subscription; physical
  multi-host distribution is hardware-deferred, and the current Wave J backlog/backpressure gate is
  a single-host logical multi-member Pulsar harness.
- model weights for the host engine come from the `infernix-models` MinIO bucket via the
  same lazy bootstrap workflow the in-cluster Linux engine pods use. The host daemon caches
  weights under `./.data/runtime/model-cache/<modelId>/`; this cache is host-local ephemeral
  state on the operator's machine (not a Kubernetes PVC, not durable cluster state) and is
  purgeable. First-use of a model triggers the cluster-side coordinator's bootstrap
  subscription; subsequent uses are local-cache hits
- the Apple host bootstrap uses Homebrew-managed `kind`, `kubectl`, `helm`, Node.js, and related
  operator tools rather than a broader manual prerequisite list
- Docker-backed lifecycle or validation work on Apple requires an already selected native arm64
  Docker daemon; the repo must not create a Docker context, switch the active context, create a
  Colima VM, or use emulation
- routed Apple E2E uses host `npm exec` with the same typed fixture and awaits the Apple
  validation pass; the Linux lane already targets the Kind control-plane DNS instead of
  `host.docker.internal`
- retained Apple Kind state under `./.data/kind/apple-silicon/` is replayed into and out of the
  worker instead of being bind-mounted, so large retained state can make `up`, `test`, and
  `down` noticeably slower than Linux
- `./bootstrap/apple-silicon.sh down` delegates to `./.build/infernix cluster down` and preserves
  `./.build/`, `./.data/`, the host-built `./.build/infernix` binaries, any host-level runtime
  container image, Docker state, and Homebrew-managed prerequisites
- `infernix service` runs `ensureAppleSiliconRuntimeReady` before the daemon loop. That flow
  ensures the shared `python/` project is installed, creates repo-local engine roots under
  `./.data/engines/`, and invokes each `poetry run setup-*` entrypoint for the active mode's
  Python-native engine bindings
- the Apple bootstrap also reconciles the Homebrew-managed `python@3.12` formula and `python3.12`
  command plus a user-local Poetry bootstrap when the `poetry` executable is absent; the Poetry
  bootstrap may reuse an already available compatible Python 3.12+ executable, after which the
  shared `python/.venv/` still materializes only on demand
- the current `setup-*` entrypoints remain idempotent preflight hooks layered on top of that
  prerequisite bootstrap and shared-project install flow

## Apple Silicon Native Architecture

The supported Apple Silicon control plane runs cluster workloads natively as `linux/arm64`.
The publication path does not depend on Rosetta, QEMU, or any other cross-architecture emulation
layer.
`clusterWorkloadArchitecture AppleSilicon` returns `"arm64"` in `src/Infernix/Cluster.hs`,
and every Harbor `docker pull --platform linux/<arch>` and `skopeo copy --override-arch=<arch>`
invocation reads from that mapping. The chart's MinIO sub-chart uses upstream multi-arch
images (`minio/minio`, `minio/mc`, `busybox`) — not single-architecture amd64-only packaging.
Operators must not enable an emulated Linux lane for Infernix validation, and the Apple
workflow must not create or switch Docker contexts or create a Colima VM.

The canonical home for the substrate → container architecture mapping is
[../architecture/runtime_modes.md](../architecture/runtime_modes.md) (see the "Substrate
Architecture" subsection); the MinIO image inventory is at
[../tools/minio.md](../tools/minio.md).

## Apple Metal/Core ML Materialization

On Apple Silicon the `infernix` and `infernix-demo` Haskell binaries build host-native through the
ghcup/cabal toolchain and run on the host against Metal. The supported engine materialization
target avoids Tart, user keychain state, Xcode UI flows, and request-time toolchain work:

- Metal source compilation uses a fixed host bridge that calls the OS Metal runtime compiler.
- Core ML models and native runner payloads materialize under `./.data/engines/<adapterId>/` with
  typed engine-artifact manifests.
- Prebuilt host wheels or binaries remain preferred for MLX / MLX-LM, ONNX Runtime, CTranslate2,
  PyTorch MPS paths, and Audiveris.
- Runtime inference consumes already materialized artifacts; it must not start virtualization,
  unlock a keychain, accept an Xcode license, invoke SwiftPM for generated glue, or install
  frameworks on a request path.

The legacy `tart` / `hostTart` / `AppleTart` implementation has been removed from the current
host-tool schema and prerequisite path. The retained
`infernix internal materialize-metal-engines` helper is the Tart-free manifest materialization
surface; the current Apple host materializes the real runner roots, proves the fixed Metal runtime
bridge, and smoke-loads the installed native artifacts. The remaining Sprint 1.15 cohort gate is
full routed real output for the Apple catalog plus `linux-cpu`.
The authoritative replacement design is
[../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

For host-native Apple validation, generated Helm values use a local fit-for-host topology on the
operator's already selected native arm64 Docker daemon: one Harbor application replica, one Pulsar
replica per role, one coordinator replica, and one demo replica. The static chart and Linux
generated values remain HA-shaped; the Linux lanes carry the HA proof. On a constrained Colima VM,
capacity failures before routed inference are real environment failures, not acceptable skips:
`XMinioStorageFull` from Harbor's MinIO backend means the Docker VM disk needs reclaimable cache
space freed. Check for stale local Harbor-tagged runtime image ids such as
`localhost:30002/library/infernix-linux-cpu:sha256-*` in the already selected Docker daemon before
assuming retained MinIO state is still the cause. `Insufficient memory` scheduling events or
Keycloak `OOMKilled` events mean the Apple local topology or Docker VM memory envelope must be
reconciled before the Wave L gate can be claimed.

## Harbor Host-Port Conflicts

`cluster up` selects Harbor's host-side Kind hostPort dynamically. The chooser
(`chooseHarborPort` in `src/Infernix/Cluster.hs`) probes `127.0.0.1:30002` first and
increments until an open port is found, persists the selection to
`./.data/runtime/harbor-port.json`, and re-uses it on subsequent `cluster up` runs when the
stored port is still free. Operators read the chosen port from `cluster status`
(`harborPort` alongside `edgePort`) or directly from `harbor-port.json`.

The typical conflict source on Apple Silicon developer hosts is an editor's debug adapter
or language-server worker binding `127.0.0.1:30002` deliberately (the port falls outside
macOS's ephemeral range `49152-65535`, so any process holding it asked for that exact port).
The dynamic selection unblocks `cluster up` without touching the editor or its extensions;
the in-cluster Kubernetes NodePort and chart references stay fixed at `30002` so cluster-
internal wiring is unaffected.

See [../tools/harbor.md](../tools/harbor.md) for the supported Harbor surface and
[../engineering/docker_policy.md](../engineering/docker_policy.md) for the containerd
registry-hosts patch.

## Cohort Validation Cadence

Apple cohort validation work is batched into the active wave named in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).
Operators running an Apple Silicon validation pass should check the active wave's scope before
bringing up a cluster; the waves doc names which work runs locally on this host and which work
batches into the counterpart CUDA Linux pass.

## Cross-References

- [cluster_bootstrap_runbook.md](cluster_bootstrap_runbook.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../tools/harbor.md](../tools/harbor.md)
- [../tools/minio.md](../tools/minio.md)
- [../engineering/portability.md](../engineering/portability.md)
- [../engineering/docker_policy.md](../engineering/docker_policy.md)
- [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md)
- [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md)
- [../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
