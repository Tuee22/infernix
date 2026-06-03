# Phase 2: Kind Cluster Storage and Lifecycle

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the supported Kind bootstrap path, the manual storage doctrine, the Helm
> deployment model, the Harbor bootstrap and Harbor-backed image flow embedded in `cluster up`,
> the generated substrate `.dhall` publication behavior tied to cluster reconcile, and the Linux
> GPU lifecycle closure together with the lifecycle-progress and retained-state hardening closure.

## Phase Status

Sprints 2.1–2.13 are closed. The Kind bootstrap, manual PV doctrine, Harbor-first image flow,
shared substrate publication path, Linux outer-container launcher contract, lifecycle progress
surface, retained-state repair behavior, narrowed bootstrap responsibility boundary, and teardown
preservation contract are implemented in this worktree. Sprint 2.13 (Cluster Lifecycle
Host-Manifest Retirement) closed the Linux cluster lifecycle path so it no longer consumes
`INFERNIX_HOST_KIND_ROOT`, `INFERNIX_HOST_REPO_ROOT`, or `HOSTNAME`, no longer inherits the parent
process environment in the shared cluster/process-monitor helpers, and routes known cluster tools
through the `HostConfig`-backed HostTool resolver. The Apple setup path in
`src/Infernix/Engines/AppleSilicon.hs` no longer inherits the parent environment; it invokes the
Poetry setup entrypoint with an explicit `--install-root` argument and an empty process
environment. The Apple lane closed in Wave A, and the CUDA Linux lane closed in Wave C with
full `linux-cpu` and `linux-gpu` gates on the native Linux/CUDA host.

## Storage Doctrine

These rules close in this phase and remain mandatory afterward:

- bootstrap deletes every default StorageClass present on the supported Kind path
- `infernix-manual` is the only supported persistent StorageClass
- every PVC-backed workload explicitly sets `storageClassName: infernix-manual`
- durable PVs are created only by the storage-reconciliation step embedded in
  `infernix cluster up`
- each durable PV maps to `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- `infernix cluster down` never deletes or mutates anything under `./.data/`

## Current Generated Demo-Config Baseline

- cluster-side reconciliation reads the active substrate from the generated file beside the binary
- `cluster up` republishes a cluster-role `infernix-substrate.dhall` payload into
  `ConfigMap/infernix-demo-config`; on Apple this is rendered from the active staged substrate
  metadata and `demo_ui` setting rather than copying the host-role file verbatim
- generated deployment inputs are not committed as static blobs in `chart/values.yaml`

## Current Repo Assessment

The storage doctrine, Helm rollout, Harbor-first image flow, route de-duplication, generated
values overlay path, in-image `nvkind` path, shared substrate-publication filename, and bootstrap
responsibility boundary are implemented on the supported Kind substrate. `cluster up`, `cluster
down`, and `cluster status` expose the active lifecycle action, phase, child-operation detail, and
heartbeat during the monitored Docker build, Harbor publication, Harbor-backed Kind-worker
preload, and Apple retained-state replay windows. Bootstrap shells build or enter the active
launcher only and then delegate lifecycle, validation, image preparation, and teardown to
`infernix`; the shared
lifecycle skips broad pre-Harbor support-image preloads, may hydrate and stream only the narrow
Harbor warmup dependency set into Linux Kind workers before Helm warmup, and loads every remaining
image, including the active runtime image, into Harbor after Harbor is responsive. Staged
`infernix-substrate.dhall` writes are atomic so concurrent status readers do not observe truncated
payloads, and retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
replicas from the current Patroni leader when timeline drift leaves replicas unready after
promotion. Phase 6 had previously recorded clean supported `./bootstrap/apple-silicon.sh` lifecycle reruns
from May 15, 2026 and May 17, 2026 through `doctor`, `build`, `up`, `status`, `test`, `down`, and
final `status` covering the split daemon topology, host-batch Pulsar handoff, repeated
retained-state cluster bring-up or teardown cycles inside the governed `test` lane, and final
post-teardown status returning `clusterPresent: False`, `lifecycleStatus: idle`, and
`lifecyclePhase: cluster-absent`; the May 17, 2026 rerun additionally exercised the
shell-to-rebuilt-binary delegation, Harbor publication of the active runtime image before final
rollout, and the absence of broad pre-Harbor support-image preload; the earlier May 13, 2026
lifecycle investigation originally served as the proof point that Apple `build-cluster-images`
can stay healthy well past thirty minutes before Harbor publication begins and that Harbor image
pushes are readiness-gated with bounded retries across transient registry resets. **Apple
Silicon validation reset (2026-05-29).** All of those reruns were performed on the retired Apple
Silicon hardware (no longer available) and no longer count as current proof points. The storage
doctrine, Helm rollout, Harbor-first image flow, retained-state replay, and lifecycle-progress
contracts are now covered by the current Apple cohort closure in Wave A and native Linux/CUDA
cohort closure in Wave C.

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
- `cluster up` materializes or verifies, then republishes, the build-selected substrate file and
  its generated catalog contract

### Validation

- `./.build/infernix cluster up` materializes or verifies the Apple substrate file and creates or
  reuses the Kind cluster on Apple Silicon
- `docker compose run --rm infernix infernix cluster up` materializes or verifies the Linux
  substrate file and does the same on the `linux-cpu` outer path
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
- chart defaults encode the mandatory local HA topology
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

- `cluster up` republishes a cluster-role `infernix-substrate.dhall` payload for the active
  substrate, preserving catalog content and `demo_ui` from the staged file while using cluster
  daemon metadata for cluster consumers
- the generated file contains every README-matrix row supported by that substrate and no
  unsupported rows
- `cluster up` creates or updates `ConfigMap/infernix-demo-config` from that generated content
- cluster consumers use the mounted ConfigMap-backed file as their exact catalog source

### Validation

- rebuilding for a different substrate changes catalog entries and engine bindings deterministically
  while preserving the fixed `infernix-substrate.dhall` filename
- generated files live only under the active build root and never land in tracked source paths
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
- `infernix kubectl -n platform exec deployment/infernix-engine -- nvidia-smi -L` reports a visible GPU on supported hosts

### Remaining Work

None.

---

## Sprint 2.8: `linux-gpu` Toolchain Closure Without Host-Visible `nvkind` Handoff [Done]

**Status**: Done
**Implementation**: `docker/linux-substrate.Dockerfile`, `src/Infernix/Cluster.hs`, `kind/cluster-linux-gpu.yaml`, `documents/engineering/k8s_native_dev_policy.md`
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
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`, `chart/templates/configmap-demo-catalog.yaml`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/templates/deployment-demo.yaml`, `compose.yaml`, `docker/linux-substrate.Dockerfile`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/development/testing_strategy.md`

### Objective

Publish the cluster-role substrate payload into the cluster and close the Linux launcher contract
around one Compose-driven outer container for both Linux substrates.

### Deliverables

- `cluster up` publishes the cluster-role substrate payload into `ConfigMap/infernix-demo-config`
- cluster-resident consumers mount that ConfigMap at
  `/opt/build/infernix-substrate.dhall`
- the outer-container control plane stages the Linux cluster-role payload at the image-local
  `/workspace/.build/outer-container/build/infernix-substrate.dhall` path when it needs to know
  its own substrate
- the cluster publication contract uses the same stable `infernix-substrate.dhall` filename in the
  repo-local mirror and in-cluster mount
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
  cluster up` materializes or verifies the Linux CPU cluster-role substrate payload and publishes
  it into the ConfigMap without any runtime-mode flag
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
- the May 17, 2026 Apple lifecycle output had recorded the broad pre-Harbor support-image preload
  phase as skipped and then verified or loaded Harbor-backed final image refs before rollout; that
  output was produced on the retired Apple Silicon hardware and no longer counts as a current
  proof point
- the May 15, 2026 supported Apple lifecycle rerun had exercised the large Pulsar image
  publication path through Harbor, retained-state replay, split-daemon inference, and final
  teardown after the bounded Docker-push retry hardening; that rerun was also on the retired
  Apple Silicon hardware and no longer counts as a current proof point
- `./bootstrap/apple-silicon.sh down` surfaces the retained-state replay phase before Kind
  deletion when the Apple worker still owns durable cluster data
- the supported status surface shows the in-progress lifecycle phase instead of only the last
  completed steady-state snapshot during monitored lifecycle work
- `infernix lint docs` fails if the Apple or cluster runbooks or CLI references drift from the
  supported progress-surface and failure-classification contract
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C with full
  `linux-cpu` and `linux-gpu` gates.

### Remaining Work

None. Apple cohort lifecycle validation closed in [Wave A](cohort-validation-waves.md), and CUDA
Linux cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 2.11: Retained-State Harbor PostgreSQL and Atomic Staging Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/DemoConfig.hs`
**Docs to update**: `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the retained-state Apple rerun gaps discovered while validating Sprint 2.10 so supported
status reads remain reliable and retained Harbor PostgreSQL replicas recover without manual repair.

### Deliverables

- generated `infernix-substrate.dhall` staging writes are atomic, preventing concurrent
  `cluster status` readers from seeing truncated Dhall while lifecycle work is in flight
- retained-state `cluster up` detects a ready Harbor PostgreSQL leader with stopped unready
  replicas and reinitializes those replicas from the leader through Patroni
- supported Apple reruns no longer require manual Harbor PostgreSQL replica surgery when timeline
  drift leaves retained replicas stopped after promotion

### Validation

- concurrent `./bootstrap/apple-silicon.sh status` during supported `up` or `down` runs continues
  to read the staged substrate file successfully while lifecycle progress is in flight
- a retained-state `./bootstrap/apple-silicon.sh up` can log the targeted Harbor PostgreSQL
  replica repair and reach ready Harbor PostgreSQL members
- the supported Apple lifecycle reruns cleanly through `./bootstrap/apple-silicon.sh doctor`,
  `build`, `up`, `status`, `test`, and `down`
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C with full
  `linux-cpu` and `linux-gpu` gates.

### Remaining Work

None. Apple cohort validation closed in [Wave A](cohort-validation-waves.md), and CUDA Linux
cohort validation closed in [Wave C](cohort-validation-waves.md).

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
- Apple bootstrap builds `./.build/infernix` and `./.build/infernix-demo`, then invokes
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

- `bash -n bootstrap/apple-silicon.sh bootstrap/linux-cpu.sh bootstrap/linux-gpu.sh
  bootstrap/lib/common.sh` passes for the narrowed launcher scripts
- `cabal build all` passes with binary-owned substrate preflight, Harbor-first publication, and
  retained-state repair changes
- on May 17, 2026, `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`,
  `down`, and final `status` had passed on the retired Apple Silicon hardware with the shell
  script building the host binary and delegating lifecycle commands to `./.build/infernix`;
  that proof point no longer counts as current evidence
- the May 17, 2026 Apple `up` and `test all` output had shown `preload-bootstrap-images`
  skipping broad pre-Harbor support-image preload and then publishing and verifying Harbor-backed
  image refs before final rollout on the retired hardware; this is no longer a current proof
  point
- the May 17, 2026 Apple `test` lane had passed Haskell style, Haskell unit, PureScript unit,
  Haskell integration, routed Playwright E2E, split-daemon Apple inference, and repeated internal
  retained-state cluster `down` or `up` cycles on the retired hardware; this is no longer a
  current proof point
- final May 17, 2026 Apple `status` after explicit bootstrap `down` had reported
  `clusterPresent: False`, `lifecycleStatus: idle`, and `lifecyclePhase: cluster-absent`, with
  retained `./.build/`, `./.data/`, local images, and the Apple host binary still present, on
  the retired hardware; this is no longer a current proof point
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C with full
  `linux-cpu` and `linux-gpu` gates.

### Remaining Work

None. Apple cohort bootstrap + Harbor-first lifecycle validation closed in
[Wave A](cohort-validation-waves.md), and CUDA Linux cohort validation closed in
[Wave C](cohort-validation-waves.md).

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

### Validation

- `cabal build all` clean, `infernix test lint` clean.
- `grep -rEn '\bproc "(docker|kubectl|helm|kind)"' src/Infernix/Cluster.hs src/Infernix/Cluster/` returns zero matches.
- May 27, 2026 (retired hardware): `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh build` had
  passed, then `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh up` had reached
  `cluster up complete`, and `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh status` had reported
  `lifecyclePhase: steady-state`. That proof point was produced on the retired Linux/CUDA host
  and no longer counts as current evidence; CUDA Linux cohort rerun closed in Wave C.
- May 27, 2026 (retired hardware): `src/Infernix/Engines/AppleSilicon.hs` stopped importing
  `System.Environment.getEnvironment`; the setup invocation now passes `--install-root`
  explicitly and uses an empty `env = Just []` process environment. `cabal build all`,
  `cabal test infernix-unit`, and `cabal test infernix-haskell-style` had passed on the retired
  Linux host. The Apple host cohort cannot exercise `Engines/AppleSilicon.hs` until Apple cohort
  validation closed in Wave A on the new Apple Silicon host.

### Remaining Work

Env-side retirement landed (May 25, 2026):

- **`INFERNIX_HOST_KIND_ROOT` retired in `src/Infernix/Cluster.hs.resolveHostKindRoot`.**
  The supported `Paths.kindRoot` field is already derived from
  `HostConfig.hostFilesystem.hostKindRoot` in
  `Infernix.Config.discoverPaths`, so `resolveHostKindRoot` now flows
  through `resolveHostRepoPath paths (kindRuntimeRoot paths runtimeMode)`
  without consulting `lookupEnv`.
- **`INFERNIX_HOST_REPO_ROOT` retired in `Cluster.hs.resolveHostRepoRoot`
  and `kindUsesHostBindMounts`.** Both now read
  `HostConfig.hostFilesystem.hostRepoRoot` indirectly via
  `Paths.repoRoot` and the typed `Config.controlPlaneContext paths`
  check; the env-var consultation is deleted.
- **`HOSTNAME` env retired in `Cluster.hs.currentLauncherContainerName`.**
  The supported in-container hostname discovery now reads
  `/etc/hostname` directly (Docker writes the container id there at
  startup); the `hostname` binary stays as the fallback path. New
  helper `readEtcHostnameMaybe` provides the typed file-backed
  alternative.
- **`getEnvironment` whole-env captures retired in
  `Cluster.hs.runCommandWithInput`, `Cluster.hs.tryCommand`, and
  `ProcessMonitor.hs.tryCommandMonitored`.** Each now derives the
  subprocess `PATH` from the staged host manifest's `toolPaths.*`
  parent directories (`clusterSubprocessBaseEnvFor` in `Cluster.hs`,
  `processMonitorBaseEnvFor` in `ProcessMonitor.hs`) so nested
  third-party invocations (most importantly `kind` shelling out to
  `docker` via PATH lookup) resolve the same absolute binaries the
  binary itself uses, including Apple Silicon Homebrew's
  `/opt/homebrew/bin` prefix; the minimal POSIX
  `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`
  chain stays as the fallback for unit-test fixtures without a
  `HostConfig`. `LANG=C.UTF-8` + `LC_ALL=C.UTF-8` round out the
  fixed env; nothing inherits from the daemon's `environ`. The
  prior hardcoded-only PATH constant
  (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`)
  was insufficient on Apple Silicon because Homebrew installs at
  `/opt/homebrew/bin`, and was surfaced by the 2026-05-29 Apple
  cohort rerun (`kind get clusters` failed with "exec: docker:
  executable file not found in $PATH"). The manifest-derived PATH
  helper fixed it without re-introducing env-var consumption.
- **Harbor registry health probe (`waitForHarborRegistryResult` in
  `src/Infernix/Cluster.hs`) now passes `-m 30` to `curl`** so the
  bounded 60-attempt × 5s retry loop actually surfaces a typed
  "Harbor registry never became ready" error within ~30 minutes
  when the host-side NodePort target is unreachable. The 2026-05-29
  Apple cohort rerun surfaced an indefinite hang when an unrelated
  host process (a VSCode Helper plugin worker) was squatting on
  `127.0.0.1:30002`, leaving the `cluster up` Harbor publication
  step waiting forever on an `ESTABLISHED` TCP connection that
  never returned an HTTP response. The Kind hostPort mapping is
  hardcoded at `30002` today; replacing it with the same dynamic
  port-discovery contract used for the edge port (Section O) is a
  Phase 3 / Phase 7 follow-on so the supported cluster lifecycle
  remains operator-environment-agnostic.
- **`engineCommandOverridesFromEnvironment` retired.** The Sprint 4.13
  chart no longer renders per-binding `INFERNIX_ENGINE_COMMAND_*` env
  entries, so `Cluster.hs.writeHelmValuesFile` passes an empty
  override list to `renderHelmValues`. Engine command overrides now
  flow through `clusterConfig.engine.commandOverrides` in
  `chart/values.yaml` directly.
- **Imports cleaned up.** `src/Infernix/Cluster.hs` no longer imports
  from `System.Environment`; `src/Infernix/ProcessMonitor.hs` no
  longer imports `getEnvironment`. The `Data.Maybe (isJust)` import
  is removed.
- **Unit-test fixture rewiring.** `test/unit/Spec.hs` Kind-config
  rendering assertion previously injected
  `INFERNIX_HOST_REPO_ROOT=/host/infernix` via `withOptionalEnv` and
  asserted host paths under `/host/infernix/...`. The supported
  override path now flows through the
  `linuxOuterContainerUnitTestFixture` `HostConfig.hostRepoRoot`
  field directly; the assertion compares against the typed fixture's
  `realRepoRoot` instead.
- **`Engines/AppleSilicon.hs` `getEnvironment` capture retired
  (code-side).** The host setup entrypoint invocation now matches the
  supported Python worker setup path: Poetry virtualenv placement is
  owned by `python/poetry.toml`, the adapter install root is passed as
  `--install-root`, and the spawned setup process receives an empty
  environment rather than inheriting the operator process environment.

Verified end-to-end on the host: `cabal build all`, `cabal test
infernix-unit` (70/70 tests), `cabal test infernix-haskell-style`,
and `./.build/infernix lint {chart,files,docs,proto}` all exit zero.
The Phase 2 forbidden-env grep gate
(`grep -rEn 'lookupEnv|getEnv |getEnvironment|setEnv|unsetEnv' src/Infernix/Cluster.hs src/Infernix/ProcessMonitor.hs src/Infernix/Engines/AppleSilicon.hs`)
returns only documented-retirement comment references — no live
reads remain.

Pending closure (queued and named so the sprint status stays
honest):

- **Bare-name `proc "<command>"` retirement across `Cluster.hs`,
  `Cluster/PublishImages.hs`, `Cluster/Discover.hs` — Linux path
  landed.** `Infernix.Config.Paths` now carries
  `pathsHostConfig :: Maybe HostConfig`; the host manifest decoded
  during `discoverPaths` flows into every helper that already has
  `Paths` in scope. `Cluster.hs` ships four new HostTool-routed
  wrapper helpers — `runHostToolCmd`, `tryHostToolCmd`,
  `captureHostToolCmd`, plus `resolveHostToolForCluster` for path
  resolution — that look up absolute paths from
  `HostConfig.toolPaths.*` and fall through to the bare tool name
  when the manifest is absent (first-run bootstrap, unit tests
  without an explicit fixture). The HostTool enum + Dhall schema +
  Linux/Apple defaults now include `chown`, `nvidiaSmi`, `nvkind`,
  `skopeo`, and `hostname` in addition to the original tool set.
  The remaining `ClusterState`-only helper layer now flows through
  the shared `resolveClusterCommand` / `resolveClusterCommandWithPaths`
  helpers, which map known tool names (`docker`, `kubectl`, `helm`,
  `kind`, `curl`, `tar`, `chown`, `hostname`, `nvidia-smi`, `nvkind`,
  `skopeo`) to HostTool paths before spawning. This avoids widening
  the persisted `ClusterState` record while removing the helper-layer
  PATH dependency when a host manifest is present.
  `src/Infernix/Cluster/PublishImages.hs` now receives the resolved
  `docker` and `skopeo` paths through `HarborPublishOptions`, so the
  multi-arch `skopeo copy` fallback is covered by the same manifest
  inventory.
- **Sprint 2.13 follow-on lifecycle fixes landed 2026-05-29 during the
  Apple cohort revalidation.** Cross-listed with Phase 3 Sprint 3.11.
  Five Apple-Silicon-surfaced lifecycle bugs landed in code:
  - `clusterSubprocessBaseEnvFor` and `processMonitorBaseEnvFor` derive
    the subprocess PATH from `HostConfig.toolPaths.*` parent directories
    (the previous hardcoded minimal POSIX PATH
    `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` did
    not include `/opt/homebrew/bin`, so `kind` could not find `docker`
    when invoked from the binary on Apple Silicon).
  - `defaultAppleHostNativeHostConfig.hostDocker` corrected from the
    Intel-Mac path `/usr/local/bin/docker` to the Apple Silicon
    Homebrew path `/opt/homebrew/bin/docker`.
  - `materializeHostManifestFile` resolves the operator home directory
    through `System.Posix.User.getEffectiveUserID` +
    `getUserEntryForID` (which read the libc user database, no env)
    instead of passing an empty placeholder. This unblocked the
    `hostCabal` / `hostGhcup` / `hostPoetry` / `hostHomeDirectory`
    defaults that depend on `homeDir`.
  - `waitForHarborRegistryResult` now passes `-m 30` to `curl` so the
    bounded 60-attempt × 5s retry envelope surfaces a typed "Harbor
    registry never became ready" error within ~30 minutes when the
    host-side NodePort target is unreachable. The previous indefinite
    hang was surfaced by an unrelated host process squatting on
    `127.0.0.1:30002`.
  - `app/Main.hs` calls `hSetBuffering LineBuffering` on `stdout` and
    `stderr` so long-running lifecycle phases stream observably
    through pipes; previously the GHC default block-buffered stdout
    hid all phase output when the binary was invoked through a tee or
    background-launcher wrapper.
- **Clean-env `linux-gpu` lifecycle validation passed on retired hardware
  May 27, 2026; current-host validation closed in Wave C.**
  On the retired Linux/CUDA host,
  `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh build` rebuilt
  `infernix-linux-gpu:local`, and the follow-on clean-env `up`
  completed after Harbor image publication and final routed workload
  rollout. That run had exposed a launcher
  regression from the temporary
  `${HOME}/.docker/config.json:/root/.docker/config.json:ro` bind
  mount in `compose.yaml` (with an empty starting environment,
  Compose expanded `${HOME}` to blank and created
  `/root/.docker/config.json` as a directory inside the launcher,
  causing `docker login localhost:30002` to fail); removing that bind
  mount restored the documented two-bind-mount compose contract and
  the rerun reached steady state. The fix landed in the worktree, but
  the May 27, 2026 proof point is on the retired hardware and no
  longer counts as current evidence. CUDA Linux cohort rerun closed
  in Wave C on the native Linux/CUDA host.

---

## Remaining Work

None. Sprints 2.1–2.13 are `Done`. Sprint 2.13 closed the env reads and HostTool routing:
5 env reads retired in `Cluster.hs`, 1 `getEnvironment` retired in `ProcessMonitor.hs`, the
Apple setup `getEnvironment` capture retired in `Engines/AppleSilicon.hs`,
`engineCommandOverridesFromEnvironment` deleted, supporting unit-test fixture rewired, shared
cluster command helpers resolve known tools through the staged host manifest, and
`Cluster/PublishImages.hs` receives resolved `docker` + `skopeo` commands through
`HarborPublishOptions`. Apple cohort validation closed in Wave A, and CUDA Linux cohort
validation closed in Wave C.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/k8s_native_dev_policy.md` - Kind bootstrap, Harbor-first image flow, GPU-enabled `linux-gpu`, and `nvkind` closure
- `documents/engineering/k8s_storage.md` - manual PV policy, PVC ownership, and `infernix-manual`
- `documents/engineering/build_artifacts.md` - generated demo-config staging and generated input material policy
- `documents/engineering/storage_and_state.md` - durable-versus-derived state inventory for cluster assets
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
- keep [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
  aligned when lifecycle progress surfaces or failure-classification doctrine changes
