# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Supported Host Contract

The host-memory partition and the fixed, bounded `/usr/bin/top` plus `/usr/bin/footprint` watchdog
are this lane's whole memory enforcement, and they use no direct FFI. This host installs **no kernel
ceiling** on an engine execution, so the lane declares detection rather than prevention — see
[Inference Memory Budget and Host-Memory Admission](#inference-memory-budget-and-host-memory-admission)
for why, and [Bounded Inference Memory](../architecture/bounded_inference_memory.md) for the contract
that makes a lane's strength part of its type. Startup verifies the footprint probe and refines the
generated execution plan into an opaque Apple enforcer before an engine member becomes ready — see
[Typed Execution Plan](../architecture/typed_execution_plan.md).

- the Apple clean-host stage-0 entrypoint reconciles Homebrew, ghcup, and fixed
  `/opt/homebrew/bin/jq`; its build path requires existing fixed `/opt/homebrew/bin/colima` and a
  nonempty, parseable Colima profile inventory. It never installs Colima or creates a Colima
  profile or VM
- the bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables and requires at
  least 12288 MiB effective memory after subtracting the active Colima pledge before direct
  `cabal install`. Haskell protobuf modules are checked-in generator output governed by an exact
  hash manifest, so the ordinary Darwin build and lint path neither installs nor starts `protoc`
  or `proto-lens-protoc`
- Docker-backed Apple work uses the operator's already selected native arm64 Docker daemon. The
  supported workflow must not create or switch Docker contexts, create a Colima VM, or use
  cross-architecture emulation
- after `./.build/infernix` exists, supported commands may reconcile Homebrew-managed `kind`,
  `kubectl`, `helm`, and Node.js on demand, and let adapter setup or validation paths reconcile
  the Homebrew-managed `python@3.12` formula and `python3.12` command plus a user-local Poetry
  bootstrap when needed; the Poetry bootstrap may reuse an already available compatible Python
  3.12+ executable when one passes the version check
- the Apple bootstrap shell owns only host prerequisite reconciliation through the host binary
  build and then invokes `./.build/infernix <command>`; the host binary owns Kind, Kubernetes,
  container builds, Harbor publication, and any cluster workload image pulls needed after it exists,
  but it must not provision Docker virtualization or switch Docker contexts
- the Apple lifecycle keeps Kind lock-taking off repo-visible paths by using a host-local
  scratch kubeconfig under the system temp directory during cluster create or delete and then
  publishing the durable repo-local kubeconfig under `./.build/`
- long waits can be healthy while the supported path is replaying retained Kind data, building
  the shared runtime image, publishing it through Harbor, or preloading Harbor-backed images
  onto the Kind worker; Harbor Docker pushes use readiness-gated bounded retries across
  transient registry resets
- retained-state Apple reruns may log a non-waiting recycle of unready Harbor PostgreSQL startup
  pods when Patroni readiness does not converge; treat that as supported retained-state repair
  while the surrounding readiness wait continues
- Apple Metal/Core ML engine materialization uses a Tart-free headless host lane. The retained
  `materialize-metal-engines` helper name writes typed engine-artifact manifests without emitting
  or compiling repository-owned native source; validation requires upstream MLX GPU operation,
  coremltools device observation, native artifact load, and routed real-output gates named in
  [../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

## Supported Flow

- run `./bootstrap/apple-silicon.sh build`
- run `./bootstrap/apple-silicon.sh up`; it runs `./.build/infernix init --if-missing` before
  `cluster up`
- run `./bootstrap/apple-silicon.sh status`
- use `./.build/infernix kubectl ...` instead of mutating global
  kubeconfig
- run `./bootstrap/apple-silicon.sh down` when tearing the cluster down
- only after the operator-owned cluster is down, run `./bootstrap/apple-silicon.sh test`; it runs
  `./.build/infernix init --runtime-mode apple-silicon --demo-ui true --if-missing`, then
  `./.build/infernix test init --runtime-mode apple-silicon --demo-ui true`, before `test all`. A
  clean workspace needs no separate config step, an existing operator config is preserved, and the
  wrapper does not run operator `cluster up`

The first supported host-native command that needs Kubernetes tooling, Node.js, Python, or Poetry
may reconcile those prerequisites automatically. Docker is different: the current Docker context
must already point at a native arm64 daemon before Docker-backed cluster work begins.

Direct reference path:

- build the Haskell host binary with `./bootstrap/apple-silicon.sh build`; that governed entrypoint
  performs the fixed-path stage-0 memory observation and supplies the complete bounded Cabal/GHC
  claimant vector described by [bounded host memory](../architecture/bounded_host_memory.md)
- run `./.build/infernix init` if `./infernix.dhall` and `./infernix-host.dhall` are not present
- run `./.build/infernix cluster up`
- run `./.build/infernix cluster status` as needed, then run `./.build/infernix cluster down`
- with no live operator-owned cluster, run
  `./.build/infernix init --runtime-mode apple-silicon --demo-ui true --if-missing`
- run `./.build/infernix test init --runtime-mode apple-silicon --demo-ui true`
- run `./.build/infernix test all`

## Cold Start Expectations

- use `./bootstrap/apple-silicon.sh status` or `./.build/infernix cluster status` before treating a
long `up`, `test`, or `down` run as failed.
- Cold or retained-state Apple runs can spend many
minutes in `prepare-kind-cluster`, `build-cluster-images`, `publish-harbor-images`,
`preload-harbor-images`, and `replay-retained-state`; a cold `build-cluster-images` phase can remain
healthy well past twenty minutes before Harbor publication begins.
- Apple teardown freezes every
workload-capable Kind worker, rechecks claim placement, stages a complete detached snapshot in
`.incoming`, and atomically commits it with `.previous` recovery before Kind deletion. Retained
MinIO model/demo-object and Pulsar data stay durable; the post-delete `WriterQuiesced` scrub may
remove only the rebuildable Harbor/Keycloak Patroni, Harbor Redis, and MinIO `harbor-registry`
subset.
- Apple bring-up reconciles interrupted `.incoming` / `.previous` roots before claim
preparation, then keeps the exact `replay-retained-state-into-kind` lifecycle intent from before
Kind creation through worker copy and claim preparation. A live pre-workload cluster resumes only
with matching owner/runtime intent; ambiguous state fails closed. An unreadable kubeconfig
authorizes delete/recreate only for that exact pending pre-workload intent, never for an ordinary
live cluster. Do not manually alter these transaction roots while a lifecycle command is active.
- On host-native Apple, `build-cluster-images` reuses `infernix-linux-cpu:local` only when the local
image carries the current source fingerprint, runtime-mode label, architecture, and pushable
manifest shape; the first run after source changes may rebuild, while unchanged-source reruns should
reuse the stamped image before Harbor publication.
- `infernix test integration` may perform several
internal cluster cycles. A source edit changes the fingerprint and forces one rebuild; subsequent
cycles in the same run should print `reusing cluster image for linux-cpu: infernix-linux-cpu:local`
when source is unchanged.
- `publish-harbor-images` includes readiness-gated bounded retries for
Docker push failures, so a transient registry reset during large-image publication is not a hard
failure unless the retry budget is exhausted and the image is still neither tagged nor pullable;
repo-owned local images are published before third-party chart dependencies and are re-tagged from
their source image before each retry so recovery does not depend on a retained target tag.
- `./bootstrap/apple-silicon.sh test` is not a single cluster round-trip: the governed test lane may
perform multiple internal cluster bring-up or teardown cycles through integration and E2E before the
outer bootstrap command returns.
- When `cluster status` reports `lifecycleStatus: in-progress`, the
supported surface also reports `lifecycleAction`, `lifecyclePhase`, `lifecycleDetail`,
`lifecycleHeartbeatAt`, and `lifecycleHeartbeatAgeSeconds`. These operator lifecycle fields are
moving under a typed `ClusterLifecycle` machine per the canonical [Managed State
Transitions](../architecture/managed_state_transitions.md) doctrine.
- If a `./bootstrap/apple-silicon.sh test` run is externally killed (SIGKILL) mid-mutation, the next
`cluster status` reports a `mutation-incomplete` (dirty) `lifecyclePhase` — not `steady-state` —
because the harness left its `HarnessOwned` cluster mid-mutation (a drained node, an over-scaled
deployment); the next `cluster up` reconciles it (uncordons the drained node, scales deployments
back) through the same reconcile-on-next-start repair, so treat a dirty read as a repairable
leftover rather than a corrupt cluster.
- The supported Apple doctrine is inactivity-aware: wall-clock duration alone is not failure.
- During the monitored long-running subprocess phases, the
lifecycle heartbeat refreshes roughly every 30 seconds; treat that as active progress, and treat the
action as stalled only when the command exits non-zero or the heartbeat stops refreshing across
multiple intervals.
- If warmup logs a Harbor PostgreSQL startup-pod recycle, the delete is intentionally non-waiting; StatefulSet
recreation and final readiness are owned by the surrounding lifecycle wait loop

## Rules

- the Apple host operator workflow has no generic Python prerequisite; Poetry and a repo-local
adapter virtual environment materialize only when an engine-adapter validation or setup path is
exercised explicitly
- supported Apple host shell is limited to `./bootstrap/apple-silicon.sh`; the
direct `cabal` command lets cabal use its natural `dist-newstyle` builddir at the project root and
only overrides `--installdir=./.build` so the materialized `./.build/infernix` binary lands where
the supported CLI surface expects it
- after the host binary exists, the bootstrap shell does not
call `kind`, `kubectl`, `helm`, apply manifests, pull images, build the cluster runtime image, or
publish to Harbor directly; it calls `./.build/infernix <command>` and lets the binary own those
lifecycle responsibilities
- supported Apple bootstrap commands are restartable stage-0 entrypoints:
when host prerequisite reconciliation crosses a real new-shell or reboot boundary, rerun the same
`./bootstrap/apple-silicon.sh <command>` surface rather than jumping straight to a later direct
command; same-process tool installation continues only after the bootstrap verifies the required
executable explicitly
- `./.build/infernix init` creates the operator runtime config at repo-root
`./infernix.dhall` and the host manifest at `./infernix-host.dhall`; ordinary lifecycle and
validation commands validate that config and fail fast naming `infernix init` when it is absent
- `./.build/infernix test init` creates `./infernix.test.dhall`; the test harness uses it to generate
and own a temporary `./infernix.dhall` for the run
- Kind create or delete uses a host-local scratch
kubeconfig under the system temp directory, and `cluster up` publishes
`./.build/infernix.kubeconfig` afterward
- supported flows do not mutate `$HOME/.kube/config`
- the Apple host-native path describes where the Haskell build, control-plane commands, cluster-side
coordinator orchestration, and on-host engine executor run. The three-role daemon model in
[../architecture/daemon_topology.md](../architecture/daemon_topology.md) maps to Apple as:
cluster-side `infernix-coordinator` Deployment plus on-host `Engine`-role daemon (the `infernix
service` process). `cluster up` adds `infernix-demo` when `demo_ui` is enabled and always deploys
the cluster `infernix-coordinator` Deployment
- on `apple-silicon`, the clustered demo and
coordinator workloads run from the `infernix-linux-cpu:local` image family while reading the
cluster-role deployment mirror derived from the initialized `apple-silicon` runtime config; the
coordinator role owns request fan-in and batch handoff, not Apple-native inference execution, and
the host-native `infernix` binary builds or freshness-reuses that image family and publishes it to
Harbor after Harbor is responsive
- `/api/publication` keeps the routed demo API on
`apiUpstream.mode: cluster-demo`, reports `daemonLocation: cluster-pod`, reports
`inferenceExecutorLocation: control-plane-host`, and publishes `inferenceDispatchMode:
pulsar-bridge-to-host-daemon` so the routed demo surface can advertise the
coordinator-plus-host-engine split explicitly
- the direct `infernix service` host run carries the
engine daemon role: it consumes the generated engine-pool membership for its Apple host id,
auto-discovers Pulsar's direct un-gated proxy NodePort transport (the `/admin/v2` and `/ws/v2`
surfaces, not the JWT-gated `/pulsar/admin` edge) from published cluster state when needed, and
forks Python adapters from `python/adapters/` only when the bound engine is Python-native. Normal
Apple pools use Pulsar `Shared` subscriptions across distinct host ids so broker-native backpressure
assigns work to available hosts; exact-host routes use derived per-host topics with `Exclusive`.
One engine process runs per machine; a physical multi-host distribution claim requires evidence
from distinct Apple hosts.
- model weights for the host engine come from the `infernix-models` MinIO bucket, which the coordinator eagerly stages at startup
from the mounted `infernix.dhall` (the same `warm-model-cache` staging the in-cluster Linux engine
pods rely on). The host daemon caches weights under `./.data/runtime/model-cache/<modelId>/`; this
cache is host-local ephemeral state on the operator's machine (not a Kubernetes PVC, not durable
cluster state) and is purgeable. The `warm-model-cache` barrier requires every configured model's
`.ready` sentinel before cluster bring-up completes; the per-inference bootstrap subscription
remains only a fallback for unexpected cache loss. The on-host `infernix service` daemon runs each
active model serialized as a fresh subprocess under a single execution lock (`engineExecutionLock`)
and admits each inference against the typed `InferenceMemoryBudget` (see the "Inference Memory
Budget and Host-Memory Admission" section): an over-budget model publishes a clean `status=failed`
real `InferenceResult` with typed `ModelMemoryLimitExceeded` quantities instead of launching, so
peak *inference* resident memory is held to one admitted model. The host's other claimants — most
notably the toolchain that runs the direct reference build above — are owned by [bounded host
memory](../architecture/bounded_host_memory.md). This disk cache (LRU in
`python/adapters/model_cache.py`) remains a separate bounded host-daemon resource and is purgeable;
disk-cache purging is independent of the RAM budget, which is resolved from a checked
`HostMemoryPartition` splitting host physical RAM into the colima VM pledge, the
`minHostHeadroomMib` headroom, and the remaining `inferenceCapacity`.
- the Apple host bootstrap uses
Homebrew-managed `kind`, `kubectl`, `helm`, Node.js, and related operator tools rather than a
broader manual prerequisite list.
- Docker-backed lifecycle or validation work on Apple requires an
already selected native arm64 Docker daemon; the repo must not create a Docker context, switch the
active context, create a Colima VM, or use emulation.
- routed Apple E2E uses host `npm exec` with
the same typed fixture against the Apple validation pass; the Linux lane already targets the Kind
control-plane DNS instead of `host.docker.internal`.
- retained Apple Kind state under
`./.data/kind/apple-silicon/` is replayed into and out of the worker instead of being bind-mounted,
so large retained state can make `up`, `test`, and `down` noticeably slower than Linux.
- `./bootstrap/apple-silicon.sh down` delegates to `./.build/infernix cluster down` and preserves
`./.build/`, `./.data/`, the host-built `./.build/infernix` binaries, any host-level runtime
container image, Docker state, and Homebrew-managed prerequisites.
- `infernix service` runs
`ensureAppleSiliconRuntimeReady` before the daemon loop. That flow installs the shared `python/`
project through the exact configured Poetry launcher, resolves the installed project interpreter for
direct protobuf generation, and creates repo-local binding roots under `./.data/engines/`. The
`setup-*` values remain closed binding identities, but no setup subprocess is launched; readiness is
a canonical, fsynced manifest publication under the engine writer. Project installation and protobuf
generation remain closed operations through the opaque bounded provisioning region.
- the Apple
bootstrap also reconciles the Homebrew-managed `python@3.12` formula and `python3.12` command plus a
user-local Poetry bootstrap when the `poetry` executable is absent; the Poetry bootstrap uses the
exact configured Python 3.12 executable. After the shared session releases its project lock, the
same startup boundary prepares `transformers`, `pytorch`, and `diffusers` with their
`apple-silicon` groups under `python/engines/<engine>/.venv/`, publishes a marker bound to the
post-install project digest, and reads it back exactly. Missing or stale evidence fails closed;
inference never invokes Poetry or repairs an environment on request.
- the generated Apple host
manifest records
`${HOME}/.local/share/pypoetry/venv/bin/poetry`; a missing default is created under its dedicated
kernel lock by closed, deadline-bounded Python probe, venv, and pinned-install operations.
Manifestless discovery retains `/opt/homebrew/bin/poetry` as a fixed absolute fallback. A configured
non-default missing Poetry path is a hard prerequisite failure rather than permission to search
ambient `PATH`.
- the `setup-*` identifiers select idempotent canonical binding manifests
layered on top of that prerequisite bootstrap and shared-project install flow; they are not
executable names

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
ghcup/cabal toolchain and run on the host against Metal. Engine materialization avoids Tart, user
keychain state, Xcode UI flows, and request-time toolchain work:

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

No `tart` / `hostTart` / `AppleTart` implementation exists in the host-tool schema or prerequisite
path. The retained
`infernix internal materialize-metal-engines` helper is the Tart-free manifest materialization
surface. After its native-artifact session releases the shared/native locks, it also prepares the
same three canonical Python-stdio environments, so the explicit materializer cannot leave
half of the Apple catalog absent. There is no repository-owned bridge and no Clang/Core ML
source-smoke topology; the candidate-root replacement is all-Haskell and bounded.
The authoritative replacement design is
[../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

For host-native Apple validation, generated Helm values use a local fit-for-host topology on the
operator's already selected native arm64 Docker daemon: one instance of each platform service, one
coordinator process, and one demo process. The static chart and Linux
generated values are single-node on every lane, matching the supported fleet topology. On a constrained Colima VM,
capacity failures before routed inference are real environment failures, not acceptable skips:
`XMinioStorageFull` from Harbor's MinIO backend means the Docker VM disk needs reclaimable cache
space freed. Check for stale local Harbor-tagged runtime image ids such as
`localhost:30002/library/infernix-linux-cpu:sha256-*` in the already selected Docker daemon before
assuming retained MinIO state is still the cause. Cluster-side `Insufficient memory` scheduling
events or Keycloak `OOMKilled` events mean the Apple local topology or Docker VM memory envelope
must be reconciled before an Apple validation pass can be claimed.

Host-daemon inference RAM is a separate concern and must not be conflated with the Docker VM
envelope. The on-host `infernix service` daemon serializes inference under a single execution lock
and admits each model against the Apple `InferenceMemoryBudget` — a `HostEnforcedBudget` over a
checked `HostMemoryPartition` (host physical RAM split into the Colima VM pledge, the
`minHostHeadroomMib` headroom, and the remaining `inferenceCapacity`; see the "Inference Memory Budget
and Host-Memory Admission" section). A full per-model `infernix test integration` run over the generated
catalog either completes or fails cleanly per model: a model whose derived requirement exceeds the
resolved capacity publishes typed `ModelMemoryLimitExceeded` carrying `requiredMib`, `availableMib`,
and the `resource` the refusal is about. That clean failure is a
product-contract outcome, not a VM-envelope reconcile — growing the Docker VM memory envelope does not
change host-RAM admission. To admit a larger model, raise the resolved `inferenceCapacity` by freeing
host headroom (for example, lowering the Colima memory pledge, which shrinks `vmReserve`), then re-run
`infernix init` / `cluster up` to re-resolve it.

## Inference Memory Budget and Host-Memory Admission

On `apple-silicon`, model weights load into host physical RAM (the unified-memory / CPU path),
so the on-host `infernix service` daemon admits inference against a resolved memory budget. There is
no separate device residency on this lane to split the account with: unified memory means the host
formula carries the weight term in full — which is precisely the term that is *absent* from the host
formula where weights stream to a device and host residency is bounded by the staging window
instead. Both formulas are owned by
[../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md).

`infernix init` and `cluster up` compute what the host offers from live host measurements: the
`resolveAppleHostMemoryPartitionBudget` resolver (`src/Infernix/DemoConfig.hs`) builds a
`HostEnforcedBudget` over a checked `HostMemoryPartition` minted by
`mkHostMemoryPartition physicalMib vmReserveMib headroomMib`. Physical RAM (`sysctl -n hw.memsize`) is
split into `vmReserve` (the Colima VM's pledged memory, `colima list --json`), a `hostHeadroom` fixed
at `minHostHeadroomMib` = 6144 MiB (covering the OS, the control-plane binary, the routed end-to-end
Playwright browser, and worst-case inter-poll watchdog overshoot), and the remaining
`inferenceCapacity` = physical − vmReserve − headroom. The smart constructor **rejects**
oversubscription (capacity < 0) and a headroom below `minHostHeadroomMib`, so an over-pledged host or
a browser-starving headroom is not constructible. A fixed reserve that omits the routed browser does
not satisfy this contract. `headroom` covers the four co-tenants named above and **not** the Haskell
toolchain. The toolchain is not a headroom tenant and is not an additional slice of this partition:
it draws its account from the same non-virtual-machine pool this partition already divides, so the
two are alternative occupants admitted one at a time by the exclusive host claim under
[bounded host memory](../architecture/bounded_host_memory.md). On a 64 GiB host with a 48 GiB Colima
pledge, `inferenceCapacity` = 65536 − 49152 − 6144 = 10240 MiB — which with the 6144 MiB headroom
accounts for the whole 16384 MiB pool, leaving no residue a concurrent toolchain account could be
drawn from.

**What a model requires is not written down anywhere.** It is derived from the model's own artifact:
the weight term is summed from the tensor table in the artifact header under a bounded prefix read,
without loading the model, and the key/value cache term is the closed function of the model's
declared geometry and the execution shape — context length, batch, generation bound, and load
strategy — the engine is actually started with. An artifact whose header overruns its file, whose
tensor extents disagree with their declared shapes, whose offsets do not tile densely, or whose
geometry disagrees with its own header yields no requirement at all rather than a small one. This is
why the operator-facing arithmetic here is a *comparison* rather than a table of per-family
constants: the left side comes from the artifact on disk and the right side comes from this machine,
and neither is a number an operator or a catalog author supplies.

So the operator's question — why is this row unavailable on this host — has one answer: **its derived
requirement exceeds the resolved `inferenceCapacity`**, and on a host that has pledged most of its
RAM to the Colima VM the heavy diffusion rows are the ones most likely to exceed it. That is a clean
classification at admission, not a launch that races the watchdog.

- `validateDemoConfig` may report capacity diagnostics, but it must not fail the daemon solely
  because one configured model's derived requirement exceeds the resolved Apple
  `inferenceCapacity`. Smaller configured models must still serve.
- At startup, `compileRuntimePlan` classifies each configured model against the resolved partition.
  A model that exceeds the available capacity remains in the compiled plan as an `UnavailableModel`;
  smaller placements remain routable. Live Apple observations then pair each admitted,
  resource-indexed grant with its matching enforcer inside an opaque `ExecutableModel`. Public engine
  launch accepts only that complete capability, derives the process command from its compiled
  binding, and carries to the engine the same execution shape the cache term was computed from
  rather than letting the adapter restate it.
- To run a larger model whose requirement exceeds the current capacity, free host headroom so the
  resolved `inferenceCapacity` rises. The most direct lever is lowering the Colima VM memory pledge,
  which raises host physical RAM minus Colima pledge; re-run `infernix init` / `cluster up`
  afterward to re-resolve the partition from the new measurements. The partition makes this the
  *explicit* choice: a host cannot both pledge most of its RAM to the VM and admit a model larger
  than the remaining capacity — it fails that model closed rather than over-committing physical RAM.

**This lane detects; it installs no kernel ceiling.** Apple Silicon puts no limit in force before the
engine's first allocation, and this runbook says so rather than implying a bound the host does not
provide: unified memory means an accelerator allocation draws on the same pool as everything else,
Darwin has no cgroups, and its address-space limit is aliased to an advisory limit that reports
itself infinite and rejects every finite ceiling written against it. With nothing installed there is
also nothing for the engine to read back from inside the process that allocates. The lane therefore
declares detection rather than prevention, and it declares it in the type: a contract that requires a
kernel ceiling refuses readiness here instead of quietly accepting a sampler in its place.

Detection is the sampled backstop, and it is the whole enforcement story on this lane. The Apple
capped-engine kernel discovers exact process-group members with fixed `/usr/bin/top`, samples exact
physical bytes with fixed `/usr/bin/footprint`, and kills the child process group when a sample
exceeds the ceiling. Both commands run under one total deadline, bounded captures, an explicit
environment, and exhaustive group cleanup; callers cannot provide a raw observer specification. The
single-flight authority remains inside the opaque engine capability, and an adversarial breach must
leave the daemon alive with a typed failure that **names the resource it breached and the footprint
it observed**, because a refusal that cannot say which resource it is about cannot be acted on.
Sampling on a fixed cadence terminates a breach rather than refusing the allocation that caused it,
so a peak between two samples is unobserved and the partition's headroom is what absorbs the
overshoot. What this makes unrepresentable is an unbounded launch on this lane; it does not make a
host out-of-memory condition impossible, and that scope statement is owned by
[bounded host memory](../architecture/bounded_host_memory.md).

Linux CPU uses the same compile/refine boundary with the engine pod memory limit as its declared
outer envelope and a verified per-invocation process-group RSS observer, and adds prevention over
private writable mappings once its ceiling has been calibrated against a real engine on that lane.
Linux GPU requires independently indexed host-RAM and GPU-VRAM grants and observers; a
single-resource plan fails compilation closed with `GpuDualResourceBudgetRequired`.

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

## Validation Selection

Apple validation follows the selected-accelerator contract in
[../engineering/testing.md](../engineering/testing.md). A cross-accelerator or multi-host claim
requires the corresponding evidence from each accelerator or distinct host.

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
- [../reference/cli_reference.md](../reference/cli_reference.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
