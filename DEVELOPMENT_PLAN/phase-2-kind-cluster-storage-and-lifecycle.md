# Phase 2: Kind Cluster Storage and Lifecycle

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported Kind bootstrap path, the manual storage doctrine, the Helm
> deployment model, the Harbor bootstrap and Harbor-backed image flow embedded in `cluster up`,
> the generated substrate `.dhall` publication behavior tied to cluster reconcile, and the Linux
> GPU lifecycle closure.

## Phase Status

Phase 2 is complete. `cluster up` republishes the staged substrate payload into
`ConfigMap/infernix-demo-config`, the repo-local publication mirror records that payload, the
chart mounts the shared `/opt/build/infernix/infernix-substrate.dhall` path, the Linux
control-plane launcher closes around the baked-image outer-container flow, and the supported
validation rerun passed.

## Storage Doctrine

These rules close in this phase and remain mandatory afterward:

- bootstrap deletes every default StorageClass present on the supported Kind path
- `infernix-manual` is the only supported persistent StorageClass
- every PVC-backed workload explicitly sets `storageClassName: infernix-manual`
- durable PVs are created only by the storage-reconciliation step embedded in
  `infernix cluster up`
- each durable PV maps to `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- `infernix cluster down` never deletes or mutates anything under `./.data/`

## Current Generated Demo-Config Baseline

- cluster-side reconciliation reads the active substrate from the generated file beside the binary
- `cluster up` republishes that exact `infernix-substrate.dhall` payload into
  `ConfigMap/infernix-demo-config`
- generated deployment inputs are not committed as static blobs in `chart/values.yaml`

## Current Repo Assessment

The storage doctrine, Helm rollout, Harbor-first image flow, route de-duplication, generated
values overlay path, in-image `nvkind` path, and shared substrate-publication filename are
implemented on the supported Kind substrate. The supported validation rerun passed, so this phase
is done.

## Sprint 2.1: Kind Bootstrap and StorageClass Reset [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`

### Objective

Create or reuse the Kind cluster and establish the manual storage-class baseline.

### Deliverables

- `infernix cluster up` reconciles the Kind cluster to the requested state
- bootstrap deletes default StorageClasses before durable workloads are reconciled
- bootstrap applies `infernix-manual`
- bootstrap chooses the edge port by trying `9090` first and incrementing by 1 until open
- bootstrap republishes the build-selected substrate file and its generated catalog contract

### Validation

- `./.build/infernix cluster up` creates or reuses the Kind cluster on Apple Silicon
- `docker compose run --rm infernix infernix cluster up` does the same on the `linux-cpu` outer
  path
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
  current `runtimeMode` line, publication details, and storage-health summary without mutation
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

## Sprint 2.6: Build-Generated Substrate File Staging and ConfigMap Publication [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/Models.hs`, `chart/templates/configmap-demo-catalog.yaml`, `chart/templates/deployment-service.yaml`, `chart/templates/deployment-demo.yaml`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/build_artifacts.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/development/testing_strategy.md`

### Objective

Make `cluster up` the canonical point where the build-generated substrate file is republished into
the cluster and mirrored for local inspection.

### Deliverables

- `cluster up` republishes the exact build-generated `infernix-substrate.dhall` for the active
  built substrate
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

## Sprint 2.9: Build-Generated Substrate File Publication and Linux Launcher Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`, `chart/templates/configmap-demo-catalog.yaml`, `chart/templates/deployment-service.yaml`, `chart/templates/deployment-demo.yaml`, `compose.yaml`, `docker/linux-substrate.Dockerfile`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/development/testing_strategy.md`

### Objective

Publish the staged substrate payload into the cluster and close the Linux launcher contract around
one Compose-driven outer container for both Linux substrates.

### Deliverables

- `cluster up` publishes the staged substrate payload into `ConfigMap/infernix-demo-config`
- Linux cluster-resident consumers mount that ConfigMap at
  `/opt/build/infernix/infernix-substrate.dhall`
- the outer-container control plane also stages the same payload under
  `/opt/build/infernix/infernix-substrate.dhall` when it needs to know its own substrate
- the cluster publication contract uses the same stable `infernix-substrate.dhall` filename in the
  repo-local mirror and in-cluster mount
- the supported Linux control-plane launcher is Compose for both `linux-cpu` and `linux-gpu`
- the outer control-plane container never requires the NVIDIA runtime for its own process, even
  when the built image targets `linux-gpu`
- the same built `linux-gpu` image is the artifact mirrored to Harbor and deployed as the cluster
  daemon image

### Validation

- `docker compose run --rm infernix infernix cluster up` publishes the staged substrate payload
  into the ConfigMap without any runtime-mode flag
- `infernix kubectl get configmap infernix-demo-config -n platform -o yaml` shows the current
  `infernix-substrate.dhall` key and the staged payload
- supported Linux GPU lifecycle and validation flows no longer require a direct user-facing
  `docker run --gpus all ...` launcher

### Remaining Work

None.

---

## Sprint 2.7: GPU-Enabled Kind Runtime For `linux-gpu` [Done]

**Status**: Done
**Implementation**: `kind/cluster-linux-gpu.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `chart/templates/deployment-service.yaml`, `chart/templates/runtimeclass-nvidia.yaml`, `test/integration/Spec.hs`
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
- `infernix kubectl -n platform exec deployment/infernix-service -- nvidia-smi -L` reports a visible GPU on supported hosts

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
- after building `infernix-linux-gpu:local`, `docker compose run --rm infernix infernix cluster up`
  succeeds on a supported NVIDIA host without a host-visible `nvkind` handoff path
- repeated `linux-gpu` cluster lifecycle runs preserve GPU visibility and durable storage behavior

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/k8s_native_dev_policy.md` - Kind bootstrap, Harbor-first image flow, GPU-enabled `linux-gpu`, and `nvkind` closure
- `documents/engineering/k8s_storage.md` - manual PV policy, PVC ownership, and `infernix-manual`
- `documents/engineering/build_artifacts.md` - generated demo-config staging and generated input material policy
- `documents/engineering/storage_and_state.md` - durable-versus-derived state inventory for cluster assets
- `documents/tools/harbor.md` - local registry contract

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - cluster lifecycle commands
- `documents/operations/cluster_bootstrap_runbook.md` - bootstrap, reconcile, and teardown workflow
- `documents/development/testing_strategy.md` - active-substrate generated catalog and GPU-enabled `linux-gpu` contract

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when storage, image-flow, generated-input, or GPU-lifecycle assumptions change
