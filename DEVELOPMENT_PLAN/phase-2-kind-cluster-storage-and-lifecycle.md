# Phase 2: Kind Cluster Storage and Lifecycle

**Status**: Done — all 16 sprints are implemented and validated.
**Current state**: Sprints 2.1–2.16 are `Done`. After Phase 1 closed, Phase 2's settled-source review
found no implementation residual. The explicit post-prerequisite governed lint and unit aggregates
exited 0, and the already-frozen current-source Apple Silicon plus paired `linux-cpu` Wave Y
cohorts supply the required behavioral evidence for the same source identity.

The landed correction set is a global cross-runtime cluster inventory, lifecycle-region-indexed
owner/runtime teardown authority, a harness reservation established before config takeover,
writer-frozen transactional Apple snapshots, durable pre-workload retained-replay intent with
proof-gated interrupted-create recovery, effect-adjacent authority and replay-intent revalidation
for every Kind deletion, collision-safe target-exec provenance, detached parent-death supervision,
parent-side process-group termination, real monotonic readiness deadlines, stale-state mutation
publication, claim-permission repair, operator-kubectl mutation-bypass refusal, closed operand
validation at the subprocess compiler, single-deadline generated retries, observed post-failure
absence, and stdin/protected-file credential transport. Phase 2 closed on 2026-08-16 after its
explicit review and machine-independent gates, using the uninterrupted Apple Silicon `test all`
plus the source-matched `linux-cpu` build and uninterrupted `test` already recorded by
[Wave Y](cohort-validation-waves.md).
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the supported Kind bootstrap path, the manual storage doctrine, the Helm
> deployment model, the Harbor bootstrap and Harbor-backed image flow embedded in `cluster up`,
> the generated substrate `.dhall` publication behavior tied to cluster reconcile, and the Linux
> GPU lifecycle closure together with the lifecycle-progress and retained-state hardening closure.

## Phase Status

Sprints 2.1–2.16 are closed. The reopened lifecycle, ownership, retained-state, and bounded-command
implementation passed its settled-source review and explicit post-Phase-1 machine-independent
gates. The frozen Wave Y Apple cohort and its source-matched paired `linux-cpu` cohort had already
run in the required order and both exited 0, so no Phase 2 validation residual remains.

The Kind bootstrap, manual PV doctrine, Harbor-first image flow,
shared substrate publication path, Linux outer-container launcher contract, lifecycle progress
surface, retained-state repair behavior, narrowed bootstrap responsibility boundary, and teardown
preservation contract are implemented in this worktree. Sprint 2.13 (Cluster Lifecycle
Host-Manifest Retirement) closed the Linux cluster lifecycle path so it no longer consumes
`INFERNIX_HOST_KIND_ROOT`, `INFERNIX_HOST_REPO_ROOT`, or `HOSTNAME`, no longer inherits the parent
process environment in the shared cluster/process-monitor helpers, and routes known cluster tools
through the `HostConfig`-backed HostTool resolver. The Apple setup path in
`src/Infernix/Engines/AppleSilicon.hs` no longer inherits the parent environment; it invokes the
Poetry setup entrypoint with an explicit `--install-root` argument and an empty process
environment. [Wave A](cohort-validation-waves.md) and [Wave C](cohort-validation-waves.md) retain
historical evidence for that Sprint 2.13 source, but do not close the reopened Phase 2 correction.
The obsolete C/Cabal boundary is removed. The focused all-Haskell replacement proofs, renewed
review, fresh machine-independent gates, and ordered Apple/`linux-cpu` cohorts are complete.

## Storage Doctrine

These rules close in this phase and remain mandatory afterward:

- bootstrap deletes every default StorageClass present on the supported Kind path
- `infernix-manual` is the only supported persistent StorageClass
- every PVC-backed workload explicitly sets `storageClassName: infernix-manual`
- durable PVs are created only by the storage-reconciliation step embedded in
  `infernix cluster up`
- each durable PV maps to `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- `infernix cluster down` preserves durable retained claim data. On Apple/non-bind lanes it may
  stage and atomically rename the typed `.incoming` / `.previous` snapshot transaction under
  `./.data/kind/`, and after writer quiescence it removes only the explicitly rebuildable Patroni
  and Harbor scrub set from the committed snapshot. Outside that explicit rebuildable set, retained
  durable claim paths inside the committed snapshot are never selectively scrubbed; incomplete
  `.incoming` and superseded `.previous` transaction roots may be removed as whole trees during
  commit or recovery

## Current Generated Demo-Config Baseline

- the operator runtime-config authority is the repo-root `./infernix.dhall`, created explicitly by
  `infernix init`; the test harness creates its temporary runtime config from
  `./infernix.test.dhall`, which is created by `infernix test init`
- ordinary config-dependent commands, including `cluster up`, fail fast and name the required init
  when their config is absent; the Apple stage-0 `up` wrapper explicitly runs
  `./.build/infernix init --if-missing` before delegation
- `cluster up` derives and publishes the cluster-role payload into
  `ConfigMap/infernix-demo-config`; the ConfigMap mount is a deployment mirror, not a second
  operator-config authority
- generated deployment inputs are not committed as static blobs in `chart/values.yaml`

## Current Repo Assessment

The storage doctrine, Helm rollout, Harbor-first image flow, route de-duplication, generated
values overlay path, in-image `nvkind` path, shared substrate-publication filename, and bootstrap
responsibility boundary are implemented on the supported Kind substrate. `cluster up`, `cluster
down`, and `cluster status` expose the active lifecycle action, phase, child-operation detail, and
heartbeat during the monitored Docker build, Harbor publication, Harbor-backed Kind-worker
preload, and Apple retained-state replay windows. [Wave X](cohort-validation-waves.md) proved the
earlier Sprint 2.15 typed-state scope, which extends this surface with the persisted `ClusterOwner`
and a `ClusterMutating` (mutation-incomplete)
lifecycle position, so a killed test's cluster is reported dirty and reconciled on the next
`cluster up` rather than read as a false `steady-state`. Bootstrap shells build or enter the active
launcher only and then delegate lifecycle, validation, image preparation, and teardown to
`infernix`; the shared lifecycle skips broad pre-Harbor support-image preloads, may hydrate and
stream only the narrow
Harbor warmup dependency set into Kind workers before Helm warmup, and loads every remaining
image, including the active runtime image, into Harbor after Harbor is responsive. Repo-root
runtime-config generation and deployment-mirror publication are atomic so concurrent status
readers do not observe truncated payloads, and retained-state Apple reruns automatically
reinitialize stopped Harbor PostgreSQL replicas from the current Patroni leader when timeline
drift leaves replicas unready after promotion. Legacy lifecycle proof points are inventoried in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) rather than repeated in the
current phase narrative. [Wave A](cohort-validation-waves.md) and
[Wave C](cohort-validation-waves.md) remain historical evidence for the earlier storage, Helm,
Harbor-first, retained-state, and lifecycle-progress source identity. Reopened Phase 2 carries
landed implementation only: the registry-only Harbor verification correction is implemented with
closed-command, redaction, and path coverage; the all-Haskell lifecycle correction and the
bounded-subprocess replacement are implemented; and the obsolete C/Cabal boundary is removed.
Phase 2's ordered closure after Phase 1 and both Wave Y behavioral lanes completed on 2026-08-16.

## Current Closure Receipt (2026-08-16)

- settled-source review found the Sprint 2.14–2.16 implementation present and no remaining code or
  documentation residual
- the explicit post-Phase-1 `./.build/infernix test lint` exited 0: Haskell style/policy, isolated
  Cabal formatting, Python typing/format/lint, and the bounded all-component build passed
- the explicit post-Phase-1 `./.build/infernix test unit` exited 0: compile-time capabilities passed
  6 positive/92 negative fixtures; artifact transactions passed 48 cases; Apple materialization
  passed 16 cases; capped-observer, execution-plan, and main Haskell suites passed; web passed 83/83
- the frozen Apple full suite used source fingerprint `bf22a3ad…` and runtime image
  `sha256:189d25e6b24e7699c87dff3e0c194e1bcd3b96a42b158e2b895dd3ca2a7e2400`; real inference,
  registry-only publication, lifecycle/recovery variants, and Playwright 16/16 passed before clean
  teardown
- the paired current-source `linux-cpu` launcher image
  `sha256:4f46299ee0b45b9c3a5ecc2b7543d8174c5323e57ea6eac7b7355a5edcee155f` passed the complete
  bootstrap test: aggregate gates, live integration, real inference and typed pod-memory refusals,
  retained-state/topology cycles, and Playwright 16/16; governed status then reported an absent idle
  cluster with zero nodes, pods, results, and cache entries
- current `lint plan`, `lint docs`, `docs check`, and repo-wide diff validation are rerun after the
  closure-record edits below; Phase 3 does not begin until they are green

## Sprint 2.1: Kind Bootstrap and StorageClass Reset [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`

### Objective

Create or reuse the Kind cluster and establish the manual storage-class baseline.

### Deliverables

- `infernix cluster up` reconciles the Kind cluster to the requested state
- `cluster up` deletes default StorageClasses before durable workloads are reconciled
- `cluster up` applies `infernix-manual`
- `cluster up` chooses the edge port by trying `9090` first and incrementing by 1 until open
- `cluster up` requires the explicitly initialized repo-root runtime config and republishes its
  generated catalog contract

### Validation

- after `./.build/infernix init`, `./.build/infernix cluster up` reads
  `./infernix.dhall` and creates or reuses the Kind cluster on Apple Silicon
- `docker compose run --rm infernix infernix cluster up` reads the launcher repo-root
  `./infernix.dhall` and does the same on the `linux-cpu` outer path
- `infernix kubectl get storageclass` shows `infernix-manual` and no default class after bootstrap

### Remaining Work

None.

---

## Sprint 2.2: Manual PV Reconciliation During Cluster Up [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: `documents/engineering/k8s_storage.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Make local persistence explicit and deterministic as part of `cluster up`.

### Deliverables

- `cluster up` discovers expected durable PVCs and creates matching PVs ahead of workload rollout
- reconciliation rejects workloads that request implicit storage classes
- reconciliation rejects hand-authored standalone durable PVC manifests outside chart ownership
- explicit PV-to-PVC binding makes repeat `cluster down` or `cluster up` cycles reattach the same
  deterministic durable PV inventory to the same `./.data/` paths, even when an operator recreates
  opaque claim names

### Validation

- `infernix test lint` rejects PVCs missing `storageClassName: infernix-manual`
- repeated `infernix cluster up` runs perform idempotent storage reconciliation
- `cluster down` followed by `cluster up` reuses the same deterministic durable PVs and `./.data/`
  host paths without repair

### Remaining Work

None.

---

## Sprint 2.3: Helm Umbrella Chart, Stable Defaults, and Generated Input Material [Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: `documents/architecture/overview.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/edge_routing.md`

### Objective

Put repo-owned and third-party workloads behind one Helm deployment model while keeping
`chart/values.yaml` focused on stable structural defaults rather than generated runtime payloads.

### Deliverables

- one umbrella chart under `chart/`
- repo-owned workloads for the Haskell service, `infernix-demo`, Gateway resources, and ConfigMap
  publications exist as chart templates
- chart dependencies cover Harbor, MinIO, Pulsar, Envoy Gateway, the Percona PostgreSQL operator,
  and operator-managed PostgreSQL clusters where required
- repo-owned workloads mount `ConfigMap/infernix-demo-config` in the runtime config mount
  directory
- chart defaults encode the supported single-instance platform topology
- `chart/values.yaml` holds stable defaults only; generated demo-config or publication payloads
  are rendered as reconcile-time or lint-time inputs instead of committed blobs

### Validation

- `infernix test lint` passes `infernix lint chart`
- `helm lint chart` and `helm template infernix chart` succeed with generated input material
- the rendered chart mounts `ConfigMap/infernix-demo-config` at `/opt/build/` for cluster consumers

### Remaining Work

None.

---

## Sprint 2.4: Automatic Harbor Image Preparation and Helm Pull Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `chart/values.yaml`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/harbor.md`

### Objective

Use Harbor as the source of truth for post-bootstrap cluster image pulls.

### Deliverables

- `cluster up` deploys Harbor itself through Helm before the post-bootstrap rollout begins
- only Harbor and Harbor-required backend services may pull from public registries before Harbor is ready
- once Harbor is ready, `cluster up` mirrors non-Harbor images into Harbor and publishes
  repo-owned images there before later rollout
- the bootstrap helper registry path is gone

### Validation

- `infernix cluster up` does not begin the remaining non-Harbor rollout until Harbor is pull-ready
- post-bootstrap non-Harbor pods pull from Harbor-managed references
- repeated `cluster up` runs repair interrupted Harbor state before the final rollout proceeds

### Remaining Work

None.

---

## Sprint 2.5: Kind Lifecycle Idempotency and Status Surface [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `compose.yaml`, `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml`, `test/integration/Spec.hs`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Make cluster reconcile, status, and teardown predictable.

### Deliverables

- `cluster up` is declarative and idempotent
- `cluster status` reports cluster existence, chosen edge port, the active substrate through its
  current `runtimeMode` line, publication details, and storage-health summary without mutating
  Kubernetes resources, publication state, or authoritative repo-local state; the Linux
  outer-container observer may idempotently attach its fresh launcher container to Docker's
  private `kind` network
- `cluster down` tears down Kind while preserving `./.data/`
- the repo-owned Kind configs pin `kindest/node:v1.34.0`

### Validation

- `cluster up`, `cluster status`, `cluster down`, and repeat `cluster up` work in sequence
- status output includes the active edge port, the current `runtimeMode` line, and publication
  details
- durable volumes rebind to the same `./.data/` paths after teardown and redeploy

### Remaining Work

None.

---

## Sprint 2.6: Explicit Substrate File Staging and ConfigMap Publication [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/Models.hs`, `chart/templates/configmap-demo-catalog.yaml`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/templates/deployment-demo.yaml`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/build_artifacts.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/development/testing_strategy.md`

### Objective

Make `cluster up` the canonical point where the active substrate metadata is republished as a
cluster-role substrate file into the cluster and mirrored for local inspection.

### Deliverables

- `cluster up` republishes a cluster-role payload for the active substrate, preserving catalog
  content and `demo_ui` from the initialized repo-root `./infernix.dhall` while using cluster daemon
  metadata for cluster consumers
- the generated file contains every README-matrix row supported by that substrate and no
  unsupported rows
- `cluster up` creates or updates `ConfigMap/infernix-demo-config` from that generated content
- cluster consumers use the mounted ConfigMap-backed file as their exact catalog source

### Validation

- initializing for a different substrate changes catalog entries and engine bindings
  deterministically while preserving the repo-root `./infernix.dhall` filename
- generated `.dhall` files remain gitignored and no `.dhall` file is version-controlled
- `infernix kubectl get configmap infernix-demo-config -n <namespace> -o yaml` shows the active published catalog

### Remaining Work

None.

---

## Sprint 2.7: GPU-Enabled Kind Runtime For `linux-gpu` [Done]

**Status**: Done
**Implementation**: `kind/cluster-linux-gpu.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `chart/templates/deployment-engine.yaml`, `chart/templates/runtimeclass-nvidia.yaml`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/architecture/runtime_modes.md`, `documents/development/testing_strategy.md`

### Objective

Make `linux-gpu` a real GPU-backed cluster mode rather than a nominal matrix column.

### Deliverables

- `cluster up` in `linux-gpu` fails fast unless the host passes the NVIDIA preflight contract
- the cluster installs the NVIDIA device plugin so nodes expose allocatable `nvidia.com/gpu`
- repo-owned CUDA workloads request `nvidia.com/gpu` and use the required runtime configuration
- cluster-resident CUDA workloads can schedule on the GPU-capable Kind substrate

### Validation

- `infernix kubectl get nodes -l infernix.runtime/gpu=true` shows allocatable `nvidia.com/gpu`
- the NVIDIA device plugin rollout is ready on GPU-capable nodes
- the `linux-gpu` integration lane completes real catalog inference through the GPU-requesting
  engine workloads on supported hosts

### Remaining Work

None.

---

## Sprint 2.8: `linux-gpu` Toolchain Closure Without Host-Visible `nvkind` Handoff [Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `src/Infernix/Cluster.hs`, `kind/cluster-linux-gpu.yaml`, `documents/engineering/k8s_native_dev_policy.md`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Remove the host-visible `nvkind` workaround and make the `linux-gpu` cluster lifecycle
self-contained in the final `linux-gpu` image.

### Deliverables

- `nvkind` is built in a multi-stage Docker build and copied into the `linux-gpu` substrate image
- `cluster up` does not spawn a secondary `golang` builder container through the host Docker socket
- no host-visible `.build/tools/nvkind` bridge remains on the supported path
- the `linux-gpu` launcher image supplies the `nvkind` binary it needs for the supported cluster lifecycle

### Validation

- the `linux-gpu` substrate image build produces a runnable `nvkind` binary
- `LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu
  --file compose.yaml run --rm infernix infernix cluster up` succeeds on a supported NVIDIA host
  without a host-visible `nvkind` handoff path or a shell-owned substrate staging step
- repeated `linux-gpu` cluster lifecycle runs preserve GPU visibility and durable storage behavior

### Remaining Work

None.

## Sprint 2.9: Staged Substrate File Publication and Linux Launcher Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`, `chart/templates/configmap-demo-catalog.yaml`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/templates/deployment-demo.yaml`, `compose.yaml`, `docker/Dockerfile`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/development/testing_strategy.md`

### Objective

Publish the cluster-role substrate payload into the cluster and close the Linux launcher contract
around one Compose-driven outer container for both Linux substrates.

### Deliverables

- `cluster up` publishes the cluster-role substrate payload into `ConfigMap/infernix-demo-config`
- cluster-resident consumers mount that ConfigMap at
  `/opt/build/infernix-substrate.dhall`
- the outer-container control plane reads its repo-root `./infernix.dhall`; ordinary commands do not
  auto-materialize a missing runtime config
- the cluster publication contract writes its repo-local deployment mirror under
  `./.data/runtime/configmaps/infernix-demo-config/` and mounts the ConfigMap in-cluster under the
  `infernix-substrate.dhall` compatibility filename (the key rendered from
  `demoConfig.fileName`)
- the supported Linux control-plane launcher is Compose for both `linux-cpu` and `linux-gpu`
- `compose.yaml` defines the single launcher service and defaults to the CPU snapshot; the GPU lane
  selects the active `infernix-linux-gpu:local` snapshot through a one-shot Compose image selector
  while keeping the supported Compose service surface unchanged
- the outer control-plane container never requires the NVIDIA runtime for its own process, even
  when the built image targets `linux-gpu`
- the same built `linux-gpu` image is the artifact mirrored to Harbor and deployed as the cluster
  daemon image

### Validation

- `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix
  cluster up` reads the initialized Linux CPU runtime config and publishes the derived cluster-role
  payload into the ConfigMap without any runtime-mode flag
- `infernix kubectl get configmap infernix-demo-config -n platform -o yaml` shows the current
  `infernix-substrate.dhall` key and the cluster-role payload
- `LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu
  --file compose.yaml run --rm infernix infernix cluster up` exercises the same supported launcher
  surface for `linux-gpu` without shell-owned substrate staging

### Remaining Work

None.

---

## Sprint 2.10: Lifecycle Progress Surfaces and False-Negative Hardening [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/ProcessMonitor.hs`
**Docs to update**: `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Make long-running lifecycle convergence observable enough that operators and test harnesses can
distinguish real failure from ongoing first-run progress.

### Deliverables

- `cluster up` surfaces explicit lifecycle phase markers for the shared image-build, Harbor
  publication, and Harbor-backed final-image preload steps instead of leaving multi-minute silent
  windows
- the removed broad pre-Harbor preload behavior is represented as an explicit skipped lifecycle
  phase, while final image availability is owned by Harbor-backed publication and preload
- Harbor image publication waits for registry readiness before Docker push attempts and retries
  transient push resets with bounded backoff before treating publication as failed
- `cluster down` surfaces retained-state replay when the active substrate needs it and surfaces
  Kind deletion explicitly instead of presenting teardown as one opaque wait
- the cluster lifecycle records enough active-phase detail that `cluster status` can report the
  current reconcile or teardown stage while work is still in progress
- lifecycle failure handling uses inactivity-aware doctrine for long-running phases rather than
  treating elapsed wall time alone as evidence of failure
- the Apple and shared-cluster runbooks describe cold-versus-warm lifecycle expectations honestly,
  including the large-image publication and Harbor-backed final-image preload phases that can
  dominate first-run timing

### Validation

- a cold `./bootstrap/apple-silicon.sh up` surfaces the image-build, Harbor-publication, and
  Harbor-backed final-image preload phases explicitly while it is still making forward progress
- the Apple lifecycle output records the broad pre-Harbor support-image preload phase as skipped and
  then verifies or loads Harbor-backed final image refs before rollout
- a supported Apple lifecycle rerun exercises the large Pulsar image publication path through
  Harbor, retained-state replay, split-daemon inference, and final teardown under the bounded
  Docker-push retry hardening
- `./bootstrap/apple-silicon.sh down` surfaces the retained-state replay phase before Kind
  deletion when the Apple worker still owns durable cluster data
- the supported status surface shows the in-progress lifecycle phase instead of only the last
  completed steady-state snapshot during monitored lifecycle work
- `infernix lint docs` fails if the Apple or cluster runbooks or CLI references drift from the
  supported progress-surface and failure-classification contract
- Apple cohort lifecycle validation closed in [Wave A](cohort-validation-waves.md); CUDA Linux
  cohort validation closed in [Wave C](cohort-validation-waves.md) with full `linux-cpu` and
  `linux-gpu` gates

### Remaining Work

None.

---

## Sprint 2.11: Retained-State Harbor PostgreSQL and Atomic Staging Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/DemoConfig.hs`
**Docs to update**: `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the retained-state Apple rerun gaps discovered while validating Sprint 2.10 so supported
status reads remain reliable and retained Harbor PostgreSQL replicas recover without manual repair.

### Deliverables

- generated `./infernix.dhall` writes are atomic, preventing concurrent
  `cluster status` readers from seeing truncated Dhall while lifecycle work is in flight
- retained-state `cluster up` detects a ready Harbor PostgreSQL leader with stopped unready
  replicas and reinitializes those replicas from the leader through Patroni
- the later Sprint 2.14 correction supersedes the original pre-replay scrub ordering: rebuildable
  Harbor and Keycloak Patroni roots may now be removed only from the post-delete detached local
  retained copy under `WriterQuiesced`
- supported Apple reruns no longer require manual Harbor PostgreSQL replica surgery when timeline
  drift leaves retained replicas stopped after promotion

### Validation

- concurrent `./bootstrap/apple-silicon.sh status` during supported `up` or `down` runs continues
  to read the repo-root runtime config successfully while lifecycle progress is in flight
- a retained-state `./bootstrap/apple-silicon.sh up` can log the targeted Harbor PostgreSQL
  replica repair and reach ready Harbor PostgreSQL members
- a retained-state Linux outer-container rerun no longer replays stale Harbor Patroni data against a
  freshly generated `infernix-harbor-db-user` secret during `bootstrap-harbor`
- the supported Apple lifecycle reruns cleanly through `./bootstrap/apple-silicon.sh doctor`,
  `build`, `up`, `status`, `test`, and `down`
- Apple cohort validation closed in [Wave A](cohort-validation-waves.md); CUDA Linux cohort
  validation closed in [Wave C](cohort-validation-waves.md) with full `linux-cpu` and `linux-gpu`
  gates

### Remaining Work

None.

---

## Sprint 2.12: Bootstrap Responsibility and Harbor-First Image Boundary Refactor [Done]

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster/PublishImages.hs`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/operations/apple_silicon_runbook.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/tools/harbor.md`

### Objective

Make bootstrap scripts narrow stage-0 launchers and move lifecycle responsibility into the
`infernix` binary on every substrate.

### Deliverables

- `bootstrap/*.sh` scripts install only substrate host prerequisites and build or enter the active
  `infernix` launcher before delegating to a binary command
- Apple bootstrap builds `./.build/infernix`, then invokes
  `./.build/infernix <command>` for `up`, `status`, `test`, and `down`
- Linux bootstraps install the Docker baseline, plus the supported NVIDIA driver and container
  toolkit on `linux-gpu`, then invoke `docker compose run --rm infernix infernix <command>` so
  Compose and the binary own launcher image creation, substrate staging, lifecycle, validation, and
  teardown
- shell scripts do not call `kind`, `kubectl`, `helm`, Kubernetes manifest application commands,
  cluster workload image pulls, image publication, or cluster image preload paths directly
- `infernix cluster up` keeps the Harbor-first deployment strategy on every substrate: Harbor and
  only Harbor-required support services may pull upstream before Harbor is responsive, and after
  Harbor is ready every remaining image, including the active `infernix` runtime image, is loaded
  into Harbor before final rollout
- on Apple Silicon, the host-native `infernix` binary builds the cluster-resident runtime image
  and publishes it into Harbor after Harbor is ready
- bootstrap `down` commands delegate to `infernix cluster down` and do not delete `./.build/`,
  `./.data/`, the host-level container build, the Apple host binary, or installed Docker or CUDA
  prerequisites

### Validation

- all four bootstrap scripts parse under `bash -n` as narrowed launcher scripts
- `cabal build all` passes with binary-owned substrate preflight, Harbor-first publication, and
  retained-state repair changes
- the narrowed bootstrap launchers delegate `doctor`, `build`, `up`, `status`, `test`, and `down`
  to the `infernix` binary, which owns Harbor-first publication, the pre-Harbor support-image
  preload skip, and retained-state teardown; the end-to-end lifecycle, full `test` lane, and
  post-`down` idle status are exercised per cohort in
  [the cohort validation waves](cohort-validation-waves.md)
- Apple cohort bootstrap and Harbor-first lifecycle validation closed in
  [Wave A](cohort-validation-waves.md); CUDA Linux cohort validation closed in
  [Wave C](cohort-validation-waves.md)

### Remaining Work

None.

---

## Sprint 2.13: Cluster Lifecycle Host-Manifest Retirement [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/ProcessMonitor.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `compose.yaml`
**Docs to update**: `documents/engineering/host_tools_manifest.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/operations/apple_silicon_runbook.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Retire the env-var fallbacks and PATH-resolved external-command invocations that the cluster
lifecycle code accumulated. Every `docker`, `kubectl`, `helm`, `kind` invocation in
`src/Infernix/Cluster.hs` and friends reads its absolute path from the `HostConfig` record
materialized in Phase 1 Sprint 1.11.

### Deliverables

- `INFERNIX_HOST_KIND_ROOT`, `INFERNIX_HOST_REPO_ROOT`, and `HOSTNAME` env reads in
  `src/Infernix/Cluster.hs` are replaced by `HostConfig.kindRoot`, `HostConfig.repoRoot`, and a
  direct `/etc/hostname` file read via `Data.ByteString.readFile`.
- Every `getEnvironment` whole-env capture in `src/Infernix/Cluster.hs`,
  `src/Infernix/ProcessMonitor.hs`, `src/Infernix/Engines/AppleSilicon.hs` is replaced with a
  fixed `[(String, String)]` list derived from `HostConfig`.
- Every `proc "<bare-name>"` invocation in `src/Infernix/Cluster.hs`,
  `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/Cluster/Discover.hs` becomes
  `runHostTool hostConfig <HostTool> args` reading the absolute path from
  `HostConfig.toolPaths.*`.
- shared cluster/monitor subprocess environments (`clusterSubprocessBaseEnvFor` in
  `src/Infernix/Cluster.hs`, `processMonitorBaseEnvFor` in `src/Infernix/ProcessMonitor.hs`) derive
  `PATH` from the staged host manifest's `toolPaths.*` parent directories — including Apple Silicon
  Homebrew's `/opt/homebrew/bin` — so nested third-party invocations resolve the same absolute
  binaries, with a minimal POSIX `PATH` as the fallback for `HostConfig`-less unit fixtures.
- the Harbor host-side port is chosen dynamically by `chooseHarborPort` (attempting `30002` first
  and incrementing until a free host TCP port is found), recorded under
  `./.data/runtime/harbor-port.json`, while the in-cluster Kubernetes NodePort stays `30002`; the
  registry health probe (`waitForHarborRegistryResult`) bounds each `curl` attempt with `-m 30`.
- the former engine-command environment override was initially moved into
  `clusterConfig.engine.commandOverrides`; Phase 1 Sprint 1.19 subsequently removed that arbitrary
  command surface entirely, so engine launch is derived only from a compiled engine binding
  (`engineCommandOverridesFromEnvironment` remains retired).

### Validation

- `cabal build all` clean, `infernix test lint` clean.
- `grep -rEn '\bproc "(docker|kubectl|helm|kind)"' src/Infernix/Cluster.hs src/Infernix/Cluster/` returns zero matches.
- under an empty host environment, `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh build` passes,
  `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh up` reaches `cluster up complete`, and
  `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh status` reports `lifecyclePhase: steady-state`
- `src/Infernix/Engines/AppleSilicon.hs` does not import `System.Environment.getEnvironment`; the
  setup invocation passes `--install-root` explicitly and uses an empty `env = Just []` process
  environment

### Remaining Work

None.

---

## Reopened Work

Sprints 2.1–2.16 are `Done`. The reopened Sprint 2.14–2.16 implementation passed its current-source
review, explicit machine-independent gates, and the closing Wave Y behavioral cohorts. Harbor
publication verification is registry-only: cached host Docker
content could satisfy the former `PublishVerifyPull` without proving remote blob servability, so the
verifier now runs a bounded authenticated platform-selected `skopeo copy` from Harbor's API
authority into a fresh empty `dir:` store under a birth-identity-owned mode-0700 directory, reads
the selected manifest, config, and every layer, and preserves primary failures while removing
protected auth and verification paths; dead-owner auth-directory reconciliation remains in force,
with focused closed-command, credential-redaction, and absolute-path unit coverage. The obsolete
C/Cabal boundary is removed. Phase 2's own ordered closure, Apple, and source-matched `linux-cpu`
evidence are complete.

Sprint 2.13 closed the env reads and HostTool routing:
5 env reads retired in `Cluster.hs`, 1 `getEnvironment` read retired in `ProcessMonitor.hs`, the
Apple setup `getEnvironment` capture retired in `Engines/AppleSilicon.hs`,
`engineCommandOverridesFromEnvironment` deleted (and its later typed cluster-config replacement
removed by Phase 1 Sprint 1.19), supporting unit-test fixture rewired, shared
cluster command helpers resolve known tools through the staged host manifest, and
`Cluster/PublishImages.hs` receives resolved `docker` + `skopeo` commands through
`HarborPublishOptions`. Apple cohort validation closed in
[Wave A](cohort-validation-waves.md), and CUDA Linux cohort validation closed in
[Wave C](cohort-validation-waves.md).

[Wave V](cohort-validation-waves.md) closed the earlier Sprint 2.14 scope. It does not close the
writer-frozen snapshot and atomic persistence correction.

Sprint 2.15 (Cluster Ownership and Mutation-Position) is the model half of the Cluster-Ownership &
Mutation-Position reopen. The doctrine + governance landed first (Phase 0 Sprint 0.16,
`Done`), and its enforcing code — the `ClusterOwner` field, the `ClusterMutating` lifecycle position,
its fail-closed persistence, and reconcile-on-next-`cluster up` — closed under
[Wave X](cohort-validation-waves.md). The later correction preserves those terms
and adds global cross-runtime inventory, owner/runtime-indexed teardown authority under one
lifecycle lock, a process-group reservation before config takeover, and crash-recoverable config
ownership. Phase 6 Sprint 6.43 is the harness half. The superseded ownerless
`ClusterReady`-as-idle surface is recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

---

## Sprint 2.14: Typed ClusterLifecycle and Lease-Gated Teardown [Done]

**Status**: Done — implementation and current-source validation are complete. The all-Haskell lifecycle implementation and the
nested-custody self-exec anchor/supervisor/pin implementation are present, and the obsolete C/Cabal
boundary is removed. The raw
live-container scrub is gone. `WriterQuiesced` is minted under the lifecycle lock, shared
runtime-root cleanup requires an all-runtime absence witness, and Apple/non-bind teardown pauses
every workload-capable Kind worker, rechecks the PVC/node binding map, stages and atomically swaps
one complete snapshot, and holds the frozen-source lease through Kind deletion.
**Implementation status**: closed on the current reviewed source with the Phase 2 lint/unit receipt
and Wave Y Apple/`linux-cpu` behavioral evidence.
**Prior cohort evidence**: [Wave V](cohort-validation-waves.md) closed the earlier scope.
**Current cohort gate**: [Wave Y](cohort-validation-waves.md), complete.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Cluster.hs`
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: replace the
`clusterPresent::Bool` + `lifecyclePhase::String` state machine with a typed `ClusterLifecycle`
closed sum carrying a consumed, resumable phase; move persistence to a fail-closed versioned aeson
codec (retiring `Show`/`Read`); and lease-gate the retained-state teardown so Apple/non-bind
copy-back stages and atomically commits a complete detached snapshot before cluster deletion, then
the scrub consumes a `WriterQuiesced` lease after absence is proved under the held lifecycle lock.
The goal is to encode evidence, not hope —
every operation acting on a system state requires typed evidence for that state, per the doctrine
at [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- a typed `ClusterLifecycle` closed sum in `src/Infernix/Types.hs`
  (`ClusterAbsent` / `ClusterProvisioning` / `ClusterActivating` / `ClusterReady` /
  `ClusterTearingDown`) carrying a consumed, resumable `LifecyclePhase` tagged by a closed
  `LifecycleTransition` replaces `clusterPresent::Bool` + `lifecyclePhase::String`, with
  `clusterPresent` and `lifecycleProgress` retained as backward-compatible projection functions so
  readers are unchanged (the vestigial `LifecycleProgress` type and the projection accessors are
  retired by [Sprint 7.29](phase-7-demo-app-durable-context.md))
- fail-closed versioned aeson persistence: `writeClusterStateFile` / `readClusterStateFile` plus a
  `VersionedClusterState` version gate in `src/Infernix/Storage.hs` retire the `Show`/`Read`
  serialization path (`writeStateFile` / `readStateFileMaybe` removed); `loadClusterState`
  (`src/Infernix/Cluster.hs`) and `loadWorkerClusterState` (`src/Infernix/Runtime/Worker.hs`) both
  read through it, and an unknown on-disk version fails closed with `ClusterStateDecodeFailure`
- retained-state teardown is lease-gated: `WriterQuiesced` (built on the Sprint 1.16
  `Infernix.Evidence.Lease` kernel) witnesses that the Kind cluster is deleted before the
  retained-state scrub runs; `scrubRetainedStateUnderLease` requires the lease, so the teardown
  scrub against a live writer is not a constructible term, and `clusterDown` runs the
  quiesce → scrub → settle ordering
- the raw destructive teardown primitive is reachable only through the lease-consuming transition
- every cluster mutation is serialized by a kernel-released nonblocking file-description lock: the
  internal Haskell lock module uses the public `filelock` nonblocking exclusive API and keeps the
  token inside the rank-2 `Lease s ClusterMutationLocked` region, with no C/FFI/Cabal boundary.
  `WriterQuiesced` can be minted only while that lock is held and cluster absence is rechecked
- Apple/non-bind copy-back stages all retained claims into a fresh `.incoming` tree, refuses cluster
  deletion when any retained claim is missing or cannot be copied, and atomically swaps the complete
  tree while preserving and recovering `.previous` across interruption; a completion marker
  distinguishes a fully staged initial `.incoming` tree from a partial copy, and absent-cluster
  bring-up reconciles both swap residues inside the freshly rechecked `WriterQuiesced` lease before
  any scrub, claim preparation, or replay
- the unique replay intent is persisted before first Kind creation and retained through every worker
  copy and claim-preparation command, so a restart with a live pre-workload cluster resumes instead
  of treating partial replay as an idempotent bring-up; a live non-bind cluster without that exact
  owner/runtime-indexed intent fails closed, while an unreadable kubeconfig permits delete/recreate
  only after the private recovery proof revalidates the exact pending intent and teardown authority
  under the lifecycle lock. The shared deletion boundary rechecks both again immediately before the
  effect, and a terminal non-zero Kind delete is accepted only after the readiness probe observes
  that the intended absence was established
- a partial rollout can leave a retained PVC with no live pod, so after the workers are paused and
  the raw binding map is proved unchanged, the freeze completes a missing retained-claim binding
  only when exactly one paused workload-capable worker exists; explicit non-worker bindings and
  every multi-worker missing-binding case fail closed, rebuildable Patroni claims remain excluded,
  and the inferred source must still pass the same complete `docker cp` before snapshot promotion or
  Kind deletion
- Pulsar repair deletions stay inside the same `WriterQuiesced` region, and ambiguous pause failures
  probe and thaw both the current worker and every worker paused earlier in the acquisition
- rebuildable Harbor and Keycloak Patroni roots are removed only from the post-delete detached local
  retained copy under `WriterQuiesced`, never from the live writer, and the raw-destructive lint has
  no `Cluster.hs` exemption

### Validation

- `cabal build all`, `cabal test infernix-unit`, and `cabal test infernix-haskell-style` pass with
  the typed `ClusterLifecycle`, versioned persistence codec, and lease-gated teardown changes
- focused deterministic tests prove same-process thread contention, cross-process contention, and
  automatic kernel release after normal exit, exception, and owner death
- compile-fail coverage rejects lock-token escape/reuse and raw lock access outside the internal
  lock kernel
- the source-review regression in `test/unit/Spec.hs` drives the exported
  `releaseHarnessClusterSlotAt` boundary through absolute fake Kind/Docker tools and injects an
  applied-then-cancelled pause behind a deterministic barrier, an applied-then-failed pause, and
  partial `docker cp` failures, asserting that every possibly paused worker thaws, Kind deletion
  remains unreachable, the committed retained tree stays byte-identical, an incomplete unmarked
  `.incoming` is never promoted, and the next attempt removes that partial tree before copying
- the Apple/non-bind integration cohort writes a unique live MinIO canary, proves the detached host
  mirror is unchanged while Kind owns the writer, kills the first recreate while an exact
  replay-phase `docker cp` activity lease is live, then requires the canary to survive the resumed
  bring-up while rebuildable Harbor storage is absent from the post-delete detached snapshot and
  freshly provisioned after replay
- `infernix lint files` rejects the governed native-source extensions, Cabal native-source fields
  and native-token CPP definitions, and embedded native source/compiler relocation;
  `infernix lint docs` stays clean, and `poetry run check-code` passes for any Python change
- the above code-side gates are exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

- None.

---

## Sprint 2.15: Cluster Ownership and Mutation-Position [Done]

**Status**: Done — implementation and current-source validation are complete. The
owner/effect-adjacent correction, stale-state mutation-helper fix,
independent region fixtures, and preserving/exhaustive synchronous and asynchronous cleanup are
implemented, as is the registry-only Harbor verification correction. The lifecycle C/FFI/Cabal
boundary is removed code-side. The all-Haskell bounded-subprocess correction is implemented after
rejection of the forked candidate's descriptor-inheritance window; its nested exact-identity
custody-handshake redesign is present, and the obsolete subprocess C file/Cabal declaration is
removed. Phase 2's own closure after Phase 1, Apple Silicon, and `linux-cpu` completed in that
order. Every create,
teardown, recovery delete, cleanup, and operator-kubectl authorization is made under the
cross-process lifecycle lock against the global three-runtime Kind inventory. The private
`ClusterTeardownAuthority s`, `PreWorkloadKindRecovery s`, and `KindDeleteAuthorization s` carry the
same lifecycle-lock region as `Lease s ClusterMutationLocked`, so authorization cannot escape or be
reused under another lock acquisition; nominal role annotations prevent `Data.Coerce` from erasing
that distinction. The authority carries the checked owner, runtime, and exact reservation access.
Normal teardown and pre-workload recovery carry distinct private deletion
authorizations into one boundary, which rereads and requires that exact reservation record
(including owner PID, process group, and birth identity), revalidates the global inventory, owner,
runtime, and, for recovery, the exact retained-replay intent immediately before destruction.
The test harness publishes a process-group reservation with a verified, persisted owner birth
identity before swapping `infernix.dhall`; operator mutations and concurrent harness seizures fail
closed until owner-specific final cleanup releases it. Each bounded command must start through one
parent-created self-exec anchor in its own process group with `close_fds = True`, an explicit
environment, and ordinary standard-stream pipes. The implemented replacement makes
the anchor start the supervisor inside the anchor group, forward its provisional PID and birth
identity to the parent, and detach it only after a parent custody acknowledgement. The supervisor
similarly self-execs a pin inside its own group and may detach that pin only after its provisional
identity has reached parent custody. The target is forked only after the parent durably publishes a
version-3 activity lease containing exact birth identities for the owner, anchor, supervisor, and
self-exec pin and the retained pin acknowledges the one-shot start authority. Compatibility
`targetGroupLeader*` fields identify that pin, not the arbitrary target. An inner gate stays closed
until the supervisor-owned target PID is observed in the exact pin group; the designated supervisor
retains and reaps that child without inventing a persisted target birth identity. The hidden
rank-2 linear session permits only
`AnchorReady -> SupervisorReady -> LeaseDurable -> TargetRunning`, so the start authority cannot be
reused or escape and the target cannot execute before that publication. Parent-liveness EOF makes
the anchor terminate and reap the supervisor; supervisor parent-liveness EOF triggers an
identity-safe target-group kill while its pin is still unreaped. Parent cleanup has the same exact
identity authority while its anchor is unreaped. Dead-owner recovery decodes legacy version-1
command-only leases, version-2 anchor/supervisor leases, and current version-3 three-group leases
and must prove every recorded group absent before restoring config or releasing the reservation.
The persisted JSON keys remain `command*` for the anchor and `watchdog*` for the supervisor solely
for format compatibility; version 3 adds `targetGroupLeaderProcessId`, `targetGroup`, and
`targetGroupLeaderBirthIdentity` for the pin. Before any payload byte is written, a bounded fsynced
incoming-intent basename persists the same exact owner/anchor/supervisor/pin identities. Common-boot
names use the version-3 encoding; fixed-width distinct-boot names use version 4. Recovery rejects
malformed, colliding, and oversized names and can retire an empty or truncated prewrite without
PID-only inference. Command cleanup therefore cannot outlive a killed reservation owner and escape
the fence.
The operator-kubectl compatibility value is additionally read-only by construction: its validator
accepts only the explicit observational command vocabulary and rejects mutating verbs, mutating
grouped subcommands, arbitrary plugins, `exec`, and kubectl global profile/cache flags that can
write caller-selected local paths, so the read command policy cannot execute an unrecorded cluster
mutation or overwrite its recorded kubeconfig.
The exported chaos-mutation bracket treats its caller state as an optimistic token: under the same
lifecycle lock it rereads and requires an exact persisted `ClusterReady` match, exact one-runtime
live inventory, owner, and reservation before publishing `ClusterMutating`. Its body receives only
that fresh state, and `ClusterReady` is restored from it only after the dirty marker, inventory, and
reservation are revalidated; stale, absent, already-dirty, or unauthorized owner cases leave the
persisted record unchanged.
**Implementation status**: closed on the current reviewed source with the Phase 2 lint/unit receipt
and Wave Y Apple/`linux-cpu` behavioral evidence. The landed
typed-state foundation is in
`src/Infernix/Types.hs`: `ClusterOwner`
(`OperatorOwned | HarnessOwned`, text JSON, fail-closed decode) plus a `clusterOwner` field on
`ClusterState` decoded with `.:? "clusterOwner" .!= OperatorOwned` (a pre-migration document without the
field decodes to the safe default `OperatorOwned`, no version bump), and the first-class
`ClusterMutating LifecyclePhase` position (tagged by a new `LifecycleMutate` transition) threaded through
`clusterLifecyclePresent`, `lifecyclePhaseOf`, and the versioned `ToJSON`/`FromJSON` codec. Landed in
`src/Infernix/Cluster.hs`: `clusterUp` mints the owner (operator CLI `OperatorOwned`), the opaque
hidden-constructor `ClusterTeardownAuthority s` minted only by consuming the matching lifecycle-lock
lease and consumed by the unexported raw teardown
(`clusterDownResolved`, which forces and revalidates the authority before the private
`deleteKindCluster` call, so an `undefined` forge crashes), while `deleteKindCluster` performs the
last inventory/owner/runtime/reservation recheck beside the effect. Recovery evidence additionally
captures the exact persisted `ClusterLifecycle` that authorized recreation and requires exact
equality with the freshly reread still-pending replay lifecycle before deletion. One unit race
regression changes the observed global inventory between the earlier authorization and that
boundary; another replaces the reservation record after earlier authorization; a focused closed
intent-check regression replaces the retained-replay lifecycle with a different value that remains
pending. Their assertions require refusal before delete and retention of the harness fence.
Four independent negative compile fixtures prove that authority coercion, lease coercion, authority
escape, and cross-lifecycle-region reuse each fail on their own rather than being masked by an
earlier compiler error. `cluster status`
renders the owner and a `ClusterMutating` as an in-progress (dirty) phase never `steady-state`, and
`reconcileInterruptedClusterMutation` uncordons drained nodes and clears the marker on the next
`cluster up` (the following chart re-apply scales over-scaled deployments back).
**Prior cohort evidence**: [Wave X](cohort-validation-waves.md) proved the earlier typed
owner/mutation-position and config-recovery scope. It does not prove the owner-atomic correction.
**Current cohort gate**: [Wave Y](cohort-validation-waves.md), complete.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
`documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`,
`documents/engineering/storage_and_state.md`, `documents/operations/apple_silicon_runbook.md`,
`documents/operations/cluster_bootstrap_runbook.md`, and this plan

### Objective

Make cluster ownership and in-progress mutation representable so a killed `infernix test all` cannot
leave an illegal state indistinguishable from a healthy operator cluster. The owner and mutation
position are already represented; the reopened requirement is that the owner authorization and the
corresponding create/delete action occur under one cross-process lifecycle lock, so a competing
operator or harness cannot invalidate the proof between check and use. See the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `ClusterOwner = OperatorOwned | HarnessOwned` (+ JSON) and a `clusterOwner` field on `ClusterState`,
  threaded through construction; `infernix cluster up` mints `OperatorOwned`, the test harness mints
  `HarnessOwned`
- a first-class `ClusterMutating LifecyclePhase` position on `ClusterLifecycle` (+ JSON codec +
  `clusterLifecyclePresent` / `lifecyclePhaseOf`), so a test-mid-mutation cluster is distinguishable
  from operator-idle `ClusterReady`
- the fail-closed versioned persistence codec (`VersionedClusterState`) carries the owner + mutation
  position; a pre-migration document missing `clusterOwner` decodes to the safe default `OperatorOwned`
  (so the harness seizure fails closed rather than destroying an unowned-but-present cluster)
- `cluster status` renders a persisted `ClusterMutating` as a mutation-incomplete (dirty) phase and
  reports the owner, never `steady-state`
- reconcile-on-next-`cluster up`: a persisted `ClusterMutating` is detected and reconciled (uncordon
  drained nodes, then continue into the ordinary chart reconciliation that scales deployments back
  to their declared replicas) before proceeding

### Validation

- `cabal build all` (`-Wall -Werror`), `cabal test infernix-unit` (a `ClusterMutating` round-trips the
  versioned codec and renders dirty, not steady-state; a pre-migration document decodes `OperatorOwned`;
  the effect-injected recovery driver proves uncordon precedes the desired-state / scale-back
  continuation and that failed uncordon blocks it), and `cabal test infernix-haskell-style`, on both
  the apple-silicon and linux-cpu lanes
- `infernix lint docs` stays clean
- `infernix test all` on apple-silicon plus linux-cpu proves the behavioral contract; Wave X covers
  only the earlier typed-state scope, so the owner-atomic correction requires a new Wave Y run
- a competing-process ownership matrix proves that an operator and harness cannot take over or tear
  down each other's actually-present cluster between seizure, bring-up, action, and cleanup
- a runtime race replaces the persisted harness reservation after initial authorization and proves
  the effect-adjacent check rereads the exact record, refuses deletion, and retains the fence; a
  negative compile fixture proves teardown authority and lifecycle leases cannot be coerced and
  authority cannot escape or cross lock regions

### Remaining Work

- None.

---

## Sprint 2.16: Bounded Semantic Command Plan [Done]

**Status**: Done — implementation and current-source validation are complete. Command-kernel exec
provenance, supervision, forced cleanup, real readiness
deadlines, and the claim-permission postcondition are implemented, as is the final publication
audit's registry-only `BlobServable` correction with focused unit coverage. The all-Haskell
self-exec anchor/supervisor/pin topology is implemented and compiles. The subprocess C shim, FFI
spawn boundary, numbered-FD topology, obsolete C file, and Cabal `c-sources:` entry are removed.
The review-required prewrite recovery and protocol-bound corrections are implemented. Phase 2's own
closure after Phase 1, Apple, and `linux-cpu` completed in that order.
**Implementation status**: closed on the current reviewed source with the Phase 2 lint/unit receipt
and Wave Y Apple/`linux-cpu` behavioral evidence. The forked target-group candidate is rejected for
its descriptor-inheritance window and supplies no evidence.
`Infernix.Cluster.Command` and
`Infernix.Cluster.Subprocess` are library-internal `other-modules`, so external callers cannot compose
the destructive builders, compiler, and runner around the lifecycle evidence boundary. The unit
suite compiles those source modules directly as home modules to retain kernel coverage, while the
integration suite receives only a non-destructive quiescence check through exposed
`Infernix.Cluster`. Negative fixtures prove that external imports of either internal module fail;
the compile-time fixture set carries 6 positive and 79 negative fixtures. The production
compiler accepts only the closed `ClusterCommand` vocabulary, validates every caller operand before
rendering, selects the generated policy exhaustively, and runs one total deadline across
acquisition, attempts, and backoff. The pre-correction kernel implemented
anchor/supervisor/target containment through the C spawn shim and specially numbered descriptors;
that boundary is superseded, and its obsolete source file and Cabal declaration are removed. The
implemented replacement uses public `System.Process`/`System.Posix` APIs behind
internal modules: the parent creates one self-exec anchor with `close_fds = True`,
`create_group = True`, an explicit environment, and ordinary standard streams; the isolated anchor
creates and reaps a supervisor that begins in the anchor group; and the supervisor creates and
reaps a retained pin that begins in the supervisor group before owning the gated target. Neither
helper detaches until the parent has reobserved and acknowledged its provisional PID, process
group, and birth identity. Total length-bounded framed messages carry the protocol over standard
streams. Hidden phase-indexed constructors, a rank-2 session region, and linear transitions make
target start before a durable version-3 lease containing exact anchor, supervisor, and target-group
pin birth identities, start-authority reuse, and session escape fail to typecheck. Target fork
is post-durability and post-retained-pin acknowledgement; a private inner gate remains closed until
the supervisor-owned target PID and containing pin group are observed. A bounded version-4
distinct-boot incoming-intent filename, paired with the bounded version-3 common-boot encoding,
preserves those helper identities even before a payload write.
Phase 2's own ordered closure and cohort proof are complete.
The finite
claim-directory chmod missing-path repair loop and the Kind/nvkind host-port reselection loops remain
higher-level workflows because they repair state or change generated command operands; every
individual command remains kernel-bounded. The claim repair's terminal missing-path branch now
recreates the directory and requires one additional bounded chmod observation to succeed before it
returns; an internal effect-injected regression proves both the success and failure boundary without
exporting an arbitrary-path chmod capability. Generated Kind delete policy owns a ten-minute total
deadline, three attempts with a two-second backoff, and `IdempotentAbsence` classification;
recognized absence succeeds immediately, unrecognized failures consume only that bounded policy,
and a terminal failure is accepted only after an independent live absence observation.
Only a completed target's `CommandFailedFatal` may use that absence postcondition;
environment/compile/setup/exec/capture `CommandFailedKernel` and `CommandTimedOut` fail immediately
and cannot become idempotent absence. PostgreSQL passwords
use stdin, skopeo uses a
birth-identified mode-0600 short-lived auth file, and Kind preload has no credential argv. The Linux
launcher image's inline `InfernixHost` payload carries the same
complete 36-field generated command-policy record as the typed default; the unit suite extracts and
strictly decodes that actual Dockerfile payload, then compares the full value to the typed
outer-container default so schema or policy drift fails before image build.
Harbor's `/v2/` startup gate now uses `awaitReadinessObservable` under an explicit 120-second total
deadline with five-second polls. HTTP `200`, `401`, and `403` are measured API-ready observations;
other HTTP statuses are measured non-ready observations, while transport failures are unobservable
and can retry only inside that deadline. Both Harbor `httpLbs` request sites carry a required
five-second response timeout, and `Cluster/PublishImages.hs` is removed from the raw-`threadDelay`
lint exemption list.
The final publication audit proved that `PublishVerifyPull` was not an honest `BlobServable`
minter: the host Docker daemon could satisfy a pull from content retained by the immediately
preceding push. The replacement closed command selects the declared Linux architecture and runs
bounded authenticated `skopeo copy --src-tls-verify=false` from a `docker://` reference rewritten
to the Harbor API authority into a fresh empty absolute `dir:` destination. Skopeo must therefore
read the selected manifest, config, and every referenced layer from Harbor without consulting
Docker's shared store. Each verification lives below the same birth-identity-owned mode-0700 root
as its mode-0600 auth file; nested preserving brackets remove the file, verification store, and
owner directory on success, failure, or asynchronous cancellation without replacing a primary
failure. The existing birth-identity check removes a SIGKILL-stranded auth directory only after
proving its owner is dead. Unit coverage fixes the rendered tool/argv/platform/auth and `dir:`
transport, secret redaction, absolute destination validation, concurrent unique auth directories,
permissions, and primary-preserving cleanup/reconciliation boundary.
The shared readiness kernel now measures monotonic wall time and interrupts each probe at the
remaining stall/ceiling budget instead of counting only configured delays. Attempt-derived waits
retain an independent exact maximum poll cap, including wholly unobservable streams; that cap is
not a quota, so a slow probe can consume the real wall deadline first. Advancing wall or cap
exhaustion classifies as `NotReady`. Lifecycle probes that intentionally block inside one poll use
an explicit `pollLimitedDeadline` whose total budget includes that inner command timeout. Focused
regressions independently cover advancing, stalled, and unobservable poll-cap exhaustion, a wall
deadline preempting the cap after measured progress, and a hung probe that cannot mint late
readiness.
**Implementation**: `infernix.cabal`, `app/Main.hs`,
removed `cbits/infernix_subprocess.c`,
`src/Infernix/Cluster/ClaimPermissions.hs`,
`src/Infernix/Cluster/Command.hs`,
`src/Infernix/Cluster/Subprocess.hs`,
`src/Infernix/Cluster/Subprocess/Protocol.hs`,
`src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/HostConfig.hs`,
`src/Infernix/CLI.hs`, `src/Infernix/Storage.hs`, `test/compile-fail/`, `test/integration/Spec.hs`,
`test/unit/Spec.hs`
**Docs to update**: `documents/architecture/typed_execution_plan.md`,
`documents/architecture/managed_state_transitions.md`,
`documents/architecture/configuration_doctrine.md`, `documents/engineering/host_tools_manifest.md`

### Objective

Compile generated timeout, retry, and failure-class policies with closed semantic cluster commands
so no cluster lifecycle path can invoke a raw or unbounded process.

### Deliverables

- proper Dhall unions for retry and failure classification plus positive timeout policies
- closed `ClusterCommand` and opaque `BoundedCommand ClusterCommand`
- complete migration of `Cluster.hs` raw helpers and all lifecycle/image publication consumers
- removed subprocess C/FFI/numbered-FD topology and Cabal `c-sources:` entry
- public-API Haskell anchor/supervisor spawning behind the internal bounded kernel
- total length-bounded typed standard-stream framing and phase-indexed start authority
- only the bounded kernel imports cluster-process primitives

### Validation

- unit tests cover timeout, bounded retry, fatal/transient/idempotent-absence classification, and
  child reaping, including immediate recognized absence, exact retry exhaustion for an unrecognized
  idempotent-class failure, distinct kernel setup/exec failure, and real target exits 126/127
- adversarial hanging and stopped-process-group commands terminate inside their declared budget
- concurrent bounded commands cannot inherit one another's protocol handles
- normal completion, timeout, synchronous exception, and asynchronous cancellation all prove
  exhaustive cleanup
- a SIGKILLed bounded-command parent or supervisor cannot leave a running, stopped, or
  terminal-first command group, descendant, anchor, pin, or supervisor alive; a stopped,
  separately grouped pre-publication supervisor is continued, terminated, and reaped by its anchor,
  with its gated target group also removed before any activity record can survive; recovery covers
  legacy version-1/version-2 and current version-3 activity leases plus bounded version-3
  common-boot/version-4 distinct-boot incoming-intent prewrites
- parent death before durable activity publication leaves no target/helper/activity record; parent
  death after publication remains recoverable from the exact recorded birth identities
- target setup/exec failure is `CommandFailedKernel`, genuine target exits 126/127 remain
  `CommandFailedFatal`, and supervisor death cannot leave the target running
- every descendant terminates, every owned child is reaped by its designated owner, and an
  activity record retires only after every recorded group is proven absent
- public Kind teardown regressions prove kernel failure and timeout cannot be laundered through a
  later absent inventory observation, while a completed terminal target failure retains that
  postcondition path
- production import-boundary scan reports no raw process import outside approved kernels
- compile-fail fixtures reject phase skipping, start-authority escape/reuse, raw-kernel access, and
  external imports of both the command language and subprocess kernel, while the unit component
  compiles their real source modules directly for positive coverage
- unit coverage classifies Harbor's measured API-ready and measured non-ready HTTP status sets;
  source/style checks keep every Harbor `httpLbs` request finite and prevent publication from
  reintroducing a handwritten `threadDelay` readiness loop
- unit coverage proves registry verification renders the bounded platform-selected authenticated
  skopeo `docker://` -> `dir:` copy, rejects a relative destination, keeps credentials out of argv
  and labels, and cleans birth-identity-owned auth/verification paths without replacing a primary
  failure
- machine-independent gate set passes

### Remaining Work

- None.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/k8s_native_dev_policy.md` - Kind bootstrap, Harbor-first image flow, GPU-enabled `linux-gpu`, and `nvkind` closure
- `documents/engineering/k8s_storage.md` - manual PV policy, PVC ownership, and `infernix-manual`
- `documents/engineering/build_artifacts.md` - generated demo-config staging and generated input material policy
- `documents/engineering/storage_and_state.md` - durable-versus-derived state inventory for cluster assets
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) - managed state-transition doctrine this phase now references for Sprint 2.14
- `documents/tools/harbor.md` - local registry contract

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - cluster lifecycle commands
- `documents/reference/cli_surface.md` - short cluster-lifecycle and status-surface overview
- `documents/operations/apple_silicon_runbook.md` - Apple first-run bootstrap and teardown timing expectations
- `documents/operations/cluster_bootstrap_runbook.md` - bootstrap, reconcile, teardown, and
  long-running image publication or preload workflow
- `documents/development/testing_strategy.md` - active-substrate generated catalog and GPU-enabled `linux-gpu` contract

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when storage, image-flow, generated-input, or GPU-lifecycle assumptions change
- keep [phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md)
  aligned when lifecycle progress surfaces or failure-classification doctrine changes
