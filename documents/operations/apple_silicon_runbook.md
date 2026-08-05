# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Current Status

The existing host-memory partition and fixed, bounded `/usr/bin/top` plus
`/usr/bin/footprint` watchdog remain operational defense-in-depth without direct FFI. The stronger
guarantee is reopened under
[Typed Execution Plan](../architecture/typed_execution_plan.md): startup must verify the footprint
probe and refine the generated execution plan into an opaque Apple enforcer before an engine member
becomes ready.

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
  `materialize-metal-engines` helper name writes typed engine-artifact manifests without emitting
  or compiling repository-owned native source; the Apple cohort owns upstream MLX GPU-operation,
  coremltools device-observation, native artifact load, and routed real-output evidence named in
  [../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

## Supported Flow

- run `./bootstrap/apple-silicon.sh build`
- run `./bootstrap/apple-silicon.sh up`; it runs `./.build/infernix init --if-missing` before
  `cluster up`
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
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`,
  which runs under the declared build ceiling
  ([bounded host memory](../architecture/bounded_host_memory.md)) — the toolchain is a named account
  on host RAM, and an uncapped build is what exhausted a development host on 2026-08-03
- run `./.build/infernix init` if `./infernix.dhall` and `./infernix-host.dhall` are not present
- run `./.build/infernix cluster up`
- run `./.build/infernix test all`

## Cold Start Expectations

- use `./bootstrap/apple-silicon.sh status` or `./.build/infernix cluster status` before treating
  a long `up`, `test`, or `down` run as failed
- cold or retained-state Apple runs can spend many minutes in `prepare-kind-cluster`,
  `build-cluster-images`, `publish-harbor-images`, `preload-harbor-images`, and
  `replay-retained-state`; a cold `build-cluster-images` phase can remain healthy well past
  twenty minutes before Harbor publication begins
- Apple teardown freezes every workload-capable Kind worker, rechecks claim placement, stages a
  complete detached snapshot in `.incoming`, and atomically commits it with `.previous` recovery
  before Kind deletion. Retained MinIO model/demo-object and Pulsar data stay durable; the
  post-delete `WriterQuiesced` scrub may remove only the rebuildable Harbor/Keycloak Patroni,
  Harbor Redis, and MinIO `harbor-registry` subset.
- Apple bring-up reconciles interrupted `.incoming` / `.previous` roots before claim preparation,
  then keeps the exact `replay-retained-state-into-kind` lifecycle intent from before Kind creation
  through worker copy and claim preparation. A live pre-workload cluster resumes only with matching
  owner/runtime intent; ambiguous state fails closed. An unreadable kubeconfig authorizes
  delete/recreate only for that exact pending pre-workload intent, never for an ordinary live
  cluster. Do not manually alter these transaction roots while a lifecycle command is active.
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
- these operator lifecycle fields are moving under a typed `ClusterLifecycle` machine per the
  canonical [Managed State Transitions](../architecture/managed_state_transitions.md) doctrine
- if a `./bootstrap/apple-silicon.sh test` run is externally killed (SIGKILL) mid-mutation, the next
  `cluster status` reports a `mutation-incomplete` (dirty) `lifecyclePhase` — not `steady-state` —
  because the harness left its `HarnessOwned` cluster mid-mutation (a drained node, an over-scaled
  deployment); the next `cluster up` reconciles it (uncordons the drained node, scales deployments
  back) through the same reconcile-on-next-start repair, so treat a dirty read as a repairable
  leftover rather than a corrupt cluster
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
- `./.build/infernix init` creates the operator runtime config at repo-root
  `./infernix.dhall` and the host manifest at `./infernix-host.dhall`; ordinary lifecycle and
  validation commands validate that config and fail fast naming `infernix init` when it is absent
- `./.build/infernix test init` creates `./infernix.test.dhall`; the test harness uses it to
  generate and own a temporary `./infernix.dhall` for the run
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
  `infernix-linux-cpu:local` image family while reading the cluster-role deployment mirror derived
  from the initialized `apple-silicon` runtime config; the coordinator role owns request fan-in and
  batch handoff, not Apple-native inference execution, and the host-native `infernix` binary builds
  or freshness-reuses that image family and publishes it to Harbor after Harbor is responsive
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
  multi-host distribution is hardware-deferred. The single-host logical multi-member Pulsar
  backlog/backpressure gate closed in Wave J (2026-06-20); validation evidence lives in
  [../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).
- model weights for the host engine come from the `infernix-models` MinIO bucket, which the
  coordinator eagerly stages at startup from the mounted `infernix.dhall` (the same `warm-model-cache`
  staging the in-cluster Linux engine pods rely on). The host daemon caches
  weights under `./.data/runtime/model-cache/<modelId>/`; this cache is host-local ephemeral
  state on the operator's machine (not a Kubernetes PVC, not durable cluster state) and is
  purgeable. The `warm-model-cache` barrier requires every configured model's `.ready` sentinel
  before cluster bring-up completes; the per-inference bootstrap subscription remains only a
  fallback for unexpected cache loss. The on-host `infernix service` daemon runs
  each active model serialized as a fresh subprocess under a single execution lock
  (`engineExecutionLock`) and admits each inference against the typed `InferenceMemoryBudget`
  (see the "Inference Memory Budget and Host-Memory Admission" section): an over-budget model
  publishes a clean `status=failed` real `InferenceResult` with typed `ModelMemoryLimitExceeded`
  quantities instead of launching, so peak *inference* resident memory is held to one admitted
  model. The host's other claimants — most notably the toolchain that runs the direct reference
  build above — are owned by
  [bounded host memory](../architecture/bounded_host_memory.md).
  This disk cache (LRU in `python/adapters/model_cache.py`) remains a separate bounded host-daemon
  resource and is purgeable; disk-cache purging is independent of the RAM budget, which is resolved
  from a checked `HostMemoryPartition` splitting host physical RAM into the colima VM pledge, the
  `minHostHeadroomMib` headroom, and the remaining `inferenceCapacity`
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
  installs the shared `python/` project through the exact configured Poetry launcher, resolves the
  installed project interpreter for direct protobuf generation, and creates repo-local binding
  roots under `./.data/engines/`. The `setup-*` values remain closed binding identities, but no
  setup subprocess is launched; readiness is a canonical, fsynced manifest publication under the
  engine writer. Project installation and protobuf generation remain closed operations through the
  opaque bounded provisioning region
- the Apple bootstrap also reconciles the Homebrew-managed `python@3.12` formula and `python3.12`
  command plus a user-local Poetry bootstrap when the `poetry` executable is absent; the Poetry
  bootstrap uses the exact configured Python 3.12 executable, after which the shared
  `python/.venv/` still materializes only on demand
- the generated Apple host manifest records
  `${HOME}/.local/share/pypoetry/venv/bin/poetry`; a missing default is created under its dedicated
  kernel lock by closed, deadline-bounded Python probe, venv, and pinned-install operations.
  Manifestless discovery retains `/opt/homebrew/bin/poetry` as a fixed absolute fallback. A
  configured non-default missing Poetry path is a hard prerequisite failure rather than permission
  to search ambient `PATH`
- the current `setup-*` identifiers select idempotent canonical binding manifests layered on top of
  that prerequisite bootstrap and shared-project install flow; they are not executable names

## Apple Silicon Native Architecture

The supported Apple Silicon control plane runs cluster workloads natively as `linux/arm64`.
The publication path does not depend on Rosetta, QEMU, or any other cross-architecture emulation
layer.
`clusterWorkloadArchitectureForHostArchitecture AppleSilicon` returns `"arm64"` in `src/Infernix/Cluster.hs`,
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

- MLX smoke selects `mx.gpu`, executes and evaluates a real operation, synchronizes it, and verifies
  the result through the public upstream package API.
- Core ML smoke uses coremltools to require a nonempty compute-device observation. It is not a
  substitute for routed Core ML model-inference evidence.
- Core ML models and native runner payloads materialize under `./.data/engines/<adapterId>/` with
  typed engine-artifact manifests.
- the only exposed materialization surface is the whole-plan Apple facade. Per-artifact
  installation, artifact transaction, provisioning commands, and the provisioning interpreter are
  package-internal
- every Poetry, Python/venv, exact requirement, Audiveris image, installed `--smoke`, and
  provenance subprocess is selected from a closed language and executed under an opaque nominal
  `ProvisioningGrant s` inside the rank-2 `ProvisioningSession s result`. Each operation uses an
  explicit environment, positive total deadline, bounded capture, and the all-Haskell self-exec
  subprocess kernel's process-group cleanup
- the configured Poetry launcher itself is the exact executable authority for project installation;
  its shebang interpreter and package/runtime closure are immutable supporting evidence. Protobuf
  generation executes the exact installed `python/.venv/bin/python` directly with fixed
  repository-relative operands rather than starting a nested Poetry child
- each `.tmp` sibling is fully hydrated before activation. A source-specific direct smoke selected
  by the hidden catalog is authoritative; it must return a nonempty exact version before the
  candidate records Python/source/runtime provenance and the deterministic digest of its actual
  payload tree. The manifest cannot provide executable text or arguments, and no generated
  `bin/*` wrapper is created
- each candidate receives a fixed regular `venv/bin/infernix-python` target. Candidate venv
  scripts/config are rewritten to the final root and any remaining candidate-root bytes reject
  installation. Audiveris uses its fixed release URL and SHA-256; cleanup detaches an image only
  after the mount path is observed on a different kernel device id
- activation fsyncs the complete candidate and parent directory around sibling renames, retains
  `.previous` through final-path validation, rolls back on failure or cancellation, and
  reconciles only exact complete crash residue
- Prebuilt host wheels or binaries remain preferred for MLX / MLX-LM, ONNX Runtime, CTranslate2,
  PyTorch MPS paths, and Audiveris.
- Runtime inference consumes already materialized artifacts; it must not start virtualization,
  unlock a keychain, accept an Xcode license, invoke SwiftPM for generated glue, or install
  frameworks on a request path.
- Materialization must not own, embed, generate, or compile C/C++/Objective-C/Metal source and must
  not replace that boundary with direct FFI.

The legacy `tart` / `hostTart` / `AppleTart` implementation has been removed from the current
host-tool schema and prerequisite path. The retained
`infernix internal materialize-metal-engines` helper is the Tart-free manifest materialization
surface. Sprint 1.20 deleted the former repository-owned bridge and Clang/Core ML source-smoke
topology. Its all-Haskell bounded candidate-root replacement and focused suites remain under active
correction after five rejected source reviews; every earlier suite count and result is superseded.
Sprint 1.20 remains Active because settled focused proof, final source review, a fresh exact-source
complete Stage 1, real Apple
rematerialization and installed runtime smokes, and routed Apple cohort evidence remain required.
The Sprint 1.15 gate remains historical full routed output for its then-active Apple catalog plus
`linux-cpu`; current cohort validation evidence lives in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).
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
assuming retained MinIO state is still the cause. Cluster-side `Insufficient memory` scheduling
events or Keycloak `OOMKilled` events mean the Apple local topology or Docker VM memory envelope
must be reconciled before an Apple cohort validation pass can be claimed.

Host-daemon inference RAM is a separate concern and must not be conflated with the Docker VM
envelope. The on-host `infernix service` daemon serializes inference under a single execution lock
and admits each model against the Apple `InferenceMemoryBudget` — a `HostEnforcedBudget` over a
checked `HostMemoryPartition` (host physical RAM split into the Colima VM pledge, the
`minHostHeadroomMib` headroom, and the remaining `inferenceCapacity`; see the "Inference Memory Budget
and Host-Memory Admission" section). A full per-model `infernix test integration` run over the current
catalog either completes or fails cleanly per model: an over-budget model publishes typed
`ModelMemoryLimitExceeded` with `requiredMib` and `availableMib`. That clean failure is a
product-contract outcome, not a VM-envelope reconcile — growing the Docker VM memory envelope does not
change host-RAM admission. To admit a larger model, raise the resolved `inferenceCapacity` by freeing
host headroom (for example, lowering the Colima memory pledge, which shrinks `vmReserve`), then re-run
`infernix init` / `cluster up` to re-resolve it.

## Inference Memory Budget and Host-Memory Admission

On `apple-silicon`, model weights load into host physical RAM (the unified-memory / CPU path),
so the on-host `infernix service` daemon admits inference against a resolved memory budget.
`infernix init` and `cluster up` compute that budget from live host measurements: the
`resolveAppleHostMemoryPartitionBudget` resolver (`src/Infernix/DemoConfig.hs`) builds a
`HostEnforcedBudget` over a checked `HostMemoryPartition` minted by
`mkHostMemoryPartition physicalMib vmReserveMib headroomMib`. Physical RAM (`sysctl -n hw.memsize`) is
split into `vmReserve` (the Colima VM's pledged memory, `colima list --json`), a `hostHeadroom` fixed
at `minHostHeadroomMib` = 6144 MiB (covering the OS, the control-plane binary, the routed end-to-end
Playwright browser, and worst-case watchdog overshoot), and the remaining `inferenceCapacity` =
physical − vmReserve − headroom. The smart constructor **rejects** oversubscription (capacity < 0) and
a headroom below `minHostHeadroomMib`, so an over-pledged host or a browser-starving headroom (the
exact gap a routed-E2E run OOMed on) is not constructible. This replaced the fixed
`appleHostReserveMib = 3072` reserve, which did not cover the routed browser and allowed a host OOM.
`headroom` covers the four co-tenants named above and **not** the Haskell toolchain, which is a
separate declared account under
[bounded host memory](../architecture/bounded_host_memory.md). On
a 64 GiB host with a 48 GiB Colima pledge, `inferenceCapacity` = 65536 − 49152 − 6144 = 10240 MiB, so
the heavy diffusion rows (`image-*` footprint 12288, `video-*` footprint 28672) fail-close cleanly at
admission rather than racing the watchdog.

- `validateDemoConfig` may report capacity diagnostics, but it must not fail the daemon solely
  because one catalog model's declared `ModelMemoryFootprint` (wire field `modelRamFootprintMib`, now
  required and positive) exceeds the resolved Apple `inferenceCapacity`. Smaller configured models
  must still serve.
- At startup, `compileRuntimePlan` classifies each configured model against the resolved partition.
  A model that exceeds the available capacity remains in the compiled plan as an
  `UnavailableModel`; smaller placements remain routable. Live Apple observations then pair each
  admitted, resource-indexed grant with its matching enforcer inside an opaque `ExecutableModel`.
  Public engine launch accepts only that complete capability and derives the process command from
  its compiled binding. The Apple capped-engine kernel discovers exact process-group members with
  fixed `/usr/bin/top`, samples exact physical bytes with fixed `/usr/bin/footprint`, and kills the
  child process group on a ceiling breach. Both commands run under one total deadline, bounded
  captures, an explicit environment, and exhaustive group cleanup; callers cannot provide a raw
  observer specification. The supported daemon
  currently supplies a caller-owned process-local execution lock; Phase 4 must encapsulate that
  single-flight authority and prove adversarial breach survival before the construction is closed.
  The normal coordinator path now publishes a clean `status=failed`
  `InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` for an
  unavailable model rather than attempting engine launch; the complete source-matched Phase 1 gate
  passed on 2026-07-25.
  Canonical home:
  [../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md).
- To run a larger model whose footprint exceeds the current budget, free host headroom so the
  resolved `inferenceCapacity` rises. The most direct lever is lowering the Colima VM memory pledge,
  which raises host physical RAM minus Colima pledge; re-run `infernix init` / `cluster up` afterward
  to re-resolve the partition from the new measurements. The partition makes this the *explicit*
  choice: a host cannot both pledge most of its RAM to the VM and admit a model larger than the
  remaining capacity — it fails that model closed rather than over-committing physical RAM.

Linux CPU uses the same compile/refine boundary with the engine pod memory limit as its declared
outer envelope; Phase 4 owns the verified per-invocation process-group RSS construction and
adversarial proof. Linux GPU currently fails compilation closed with
`GpuDualResourceBudgetRequired`; Phase 6 owns the dual host-RAM/GPU-VRAM grant and enforcement path.

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
- [Managed State Transitions](../architecture/managed_state_transitions.md)
