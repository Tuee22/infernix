# Phase 2: Kind Cluster Storage and Lifecycle

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported Kind bootstrap path, the manual storage doctrine, the Helm
> umbrella deployment model, the Harbor bootstrap and Harbor-backed image preparation flow embedded
> in `cluster up`, and the mode-aware generated-demo-config behavior tied to cluster reconcile.

## Phase Status

Sprints 2.1, 2.2, 2.4, 2.5, 2.6, and 2.7 stay `Done`: the storage doctrine, Kind bootstrap, GPU
lane, manual PV reconciliation, Harbor image-preparation flow, idempotency surface, and the
mode-aware demo-config staging are all in place. Sprint 2.3 (Helm Umbrella Chart and Repo
Workload Layout) remains `Active`: the chart inventory now targets Envoy Gateway plus HTTPRoute
assets and per-substrate runtime-image coordinates, but that final rendered shape still needs
renewed Helm or Kind acceptance on a host with the full cluster toolchain available.

## Storage Doctrine

These rules close in this phase and remain mandatory afterward:

- cluster bootstrap deletes every default StorageClass present on the supported Kind path
- the only supported persistent StorageClass is `infernix-manual` using `kubernetes.io/no-provisioner`
- every PVC-backed Helm workload, including repo-owned services, third-party chart dependencies,
  and operator-managed durable claims reconciled from a repo-owned Helm release, explicitly sets
  `storageClassName: infernix-manual`
- durable PVs are created manually only by the storage-reconciliation step embedded in
  `infernix cluster up`
- no PVC-backed Helm deployment relies on dynamic provisioning or an implicit default storage class
- each durable PV maps to `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- `infernix cluster down` never deletes or mutates anything under `./.data/`
- explicit PV-to-PVC binding is required so repeat `cluster down` and `cluster up` cycles rebind
  workloads to the same durable paths automatically
- there is no standalone storage-reconcile operator command; storage reconciliation is part of
  `cluster up`

## Mode-Aware Cluster Input Contract

This phase also owns the rule that `cluster up` prepares the active runtime mode's demo catalog.

- `cluster up` accepts or resolves the active runtime mode before cluster-side reconciliation begins
- the active runtime mode selects the corresponding engine column from the README matrix
- the generated `infernix-demo-<mode>.dhall` file contains every matrix row supported by that mode
- the generated file is emitted as staging content, then published into `ConfigMap/infernix-demo-config`
- in containerized execution contexts, the ConfigMap is mounted at `/opt/build/`, where the daemon
  watches the `.dhall` next to its binary
- the mounted ConfigMap-backed file becomes the source of truth for the demo-visible catalog and
  later integration or E2E enumeration

## Current Repo Assessment

The storage doctrine, Helm rollout, and generated demo-config publication are implemented on the
current Kind path. The Harbor image-flow contract is now closed on the supported Apple lane: the
bootstrap-registry helper is gone, warmup and bootstrap only bring up Harbor and the support or
storage services Harbor needs before readiness, the Harbor chart values pin the chart-generated
secret material and registry credentials that must remain stable across the `harbor-final` and
`final` phases, the Kind registry-host config now only rewrites `localhost:30002`, `cluster up`
preloads the Harbor-backed final image refs onto the Kind worker before the final non-Harbor
rollout begins, fresh clean-cluster reruns preload the Harbor bootstrap-support image set onto
new Kind nodes before Helm warmup begins, and both clean and repeat Apple reruns complete without
the old transient MinIO first-pull `502 Bad Gateway`. The Linux outer-container path now keeps the Kind API server and
routed host-port mappings on `127.0.0.1`, joins the private Docker `kind` network for
cluster-backed commands, writes the repo-local kubeconfig from `kind get kubeconfig --internal`,
pins Kind nodes to `kindest/node:v1.34.0`, and primes Kind node-local registry or storage state
after cluster creation instead of bind-mounting repo-owned Kind paths into those nodes. The
`linux-cuda` path now creates `RuntimeClass/nvidia` before the device-plugin rollout depends on it
and carries a repo-owned fallback for the current upstream `nvkind` configmap-persistence bug. The
supported outer-container validation lane now revalidates that `linux-cuda` path on the current
NVIDIA host through the full integration and routed E2E matrix, including repeat reconcile or
teardown and real `nvidia.com/gpu` visibility. The
validated Linux outer-container lane also requires host inotify capacity high enough for
mount-bearing Kind nodes; on the current Ubuntu host, `fs.inotify.max_user_instances >= 1024`
keeps the repeated worker bootstrap and claim-sync lifecycle stable. The Harbor bootstrap slice now
keeps the same Harbor-first image flow while the supported platform provisions Harbor's PostgreSQL
backend through operator-managed Patroni claims that still follow the same manual-storage and
explicit-binding doctrine under `./.data/kind/...`. That storage doctrine remains mandatory for
later phases as well: later Helm rollouts with PVCs still use `infernix-manual` plus manually
created, explicitly bound PVs.

## Sprint 2.1: Kind Bootstrap and StorageClass Reset [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`

### Objective

Create or reuse the Kind cluster and establish the manual storage-class baseline.

### Deliverables

- `infernix cluster up` reconciles the Kind cluster to the requested state, creating or reusing it as needed
- `cluster up` is the supported test-cluster bring-up command rather than the canonical production runtime path
- bootstrap deletes default storage classes before any durable workload is reconciled
- bootstrap applies `infernix-manual` with `kubernetes.io/no-provisioner`
- bootstrap creates baseline namespaces and ingress prerequisites
- on Apple host mode, bootstrap writes `./.build/infernix.kubeconfig` and does not mutate
  `$HOME/.kube/config`
- bootstrap auto-generates the active runtime mode's demo `.dhall` file and enables every
  README-matrix row supported by that mode
- bootstrap chooses the edge port by trying `9090` first and incrementing by 1 until an open port is found
- bootstrap prints the chosen edge port to the operator during `cluster up`

### Validation

- `./.build/infernix cluster up` creates or reuses the Kind cluster on Apple Silicon
- `docker compose run --rm infernix infernix cluster up` does the same on the Linux outer path
- `./.build/infernix kubectl get storageclass` shows `infernix-manual` and no default class after bootstrap on Apple
- `docker compose run --rm infernix infernix kubectl get storageclass` shows the same on the Linux outer path
- the generated demo `.dhall` file exists in the build-output location for the active execution context
- `infernix kubectl get configmap infernix-demo-config -n <namespace>` shows the published demo catalog
- the repo-local kubeconfig exists in the build-output location for the active execution context

### Remaining Work

None.

---

## Sprint 2.2: Manual PV Reconciliation During Cluster Up [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Models.hs`, `chart/templates/workloads-platform-portals.yaml`
**Docs to update**: `documents/engineering/k8s_storage.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Make local persistence explicit and deterministic as part of `cluster up` before Helm install or
upgrade runs.

### Deliverables

- `infernix cluster up` templates the chart, discovers expected durable PVCs, and creates matching
  PVs ahead of workload rollout
- PV directory policy is
  `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- storage reconciliation runs automatically during `cluster up`; no separate
  `infernix cluster storage reconcile` command is introduced
- reconciliation rejects workloads that request implicit storage classes or omit
  `storageClassName: infernix-manual`
- reconciliation rejects hand-authored standalone durable PVC manifests outside chart ownership
- PV manifests bind explicitly to their intended claims so down/up cycles automatically reattach the
  same claims to the same `./.data/` paths

### Validation

- `./.build/infernix test lint` passes `infernix lint chart`, which renders the chart and rejects
  PVCs missing `storageClassName: infernix-manual` or chart-ownership labels through the
  Haskell-owned claim-discovery path
- repeated `infernix cluster up` runs perform idempotent storage reconciliation
- `helm template` plus the `cluster up` storage step creates one PV per expected durable PVC
- `infernix kubectl get pv,pvc -A` shows all durable claims bound through `infernix-manual`
- `cluster down` followed by `cluster up` rebinds durable claims to the same PVs without manual
  storage repair

### Remaining Work

None.

---

## Sprint 2.3: Helm Umbrella Chart and Repo Workload Layout [Active]

**Status**: Active
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: `documents/architecture/overview.md`, `documents/engineering/k8s_native_dev_policy.md`

### Objective

Put repo-owned and third-party workloads behind one Helm deployment model.

### Deliverables

- one umbrella chart under `chart/`
- repo-owned workloads for the Haskell service, the `infernix-demo` surface, the Gateway API
  resources, and the publication ConfigMaps exist as chart templates and values
- chart dependencies for Harbor, MinIO, Pulsar, Envoy Gateway, and the Percona PostgreSQL operator
- repo-owned workloads mount `ConfigMap/infernix-demo-config` in the watched runtime directory used by the daemon and UI
- chart defaults encode the mandatory local HA topology: three-replica Harbor and Pulsar surfaces
  where supported by the chosen charts, and a four-replica distributed MinIO deployment
- repo-owned Helm values explicitly suppress hard pod anti-affinity and equivalent hard scheduling
  constraints that would otherwise block the mandatory replicas from scheduling on local Kind
- no alternate single-replica dev chart profile is introduced

### Validation

- `./.build/infernix test lint` passes `infernix lint chart`
- the chart templates mount `ConfigMap/infernix-demo-config` at `/opt/build/` for the service, web, and `infernix-demo` workloads
- `chart/values.yaml` records the mandatory HA replica targets and the stable routed edge inventory
- `helm lint chart` and `helm template infernix chart` succeed through the repo-owned dependency bootstrap path
- `./.build/infernix --runtime-mode apple-silicon test integration` and
  `docker compose run --rm infernix infernix --runtime-mode apple-silicon test e2e` both reconcile
  the chart through Helm on the current host-native and outer-container control-plane paths

### Remaining Work

- the chart now carries the Gateway API surface and the substrate-image value schema, but the
  current host environment has not rerun `helm lint chart`, `helm template infernix chart`, or
  real Kind reconcile against that final shape because the host toolchain lane is unavailable and
  the substrate-image validation work from Phases 4 and 5 is still in progress

---

## Sprint 2.4: Automatic Harbor Image Preparation and Helm Pull Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `chart/values.yaml`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/harbor.md`

### Objective

Use Harbor as the source of truth for post-bootstrap cluster image pulls, with Harbor bootstrap and
image preparation handled automatically during `cluster up`.

### Deliverables

- `infernix cluster up` deploys Harbor itself through the Helm chart before the post-bootstrap
  Harbor-backed rollout begins
- the Harbor bootstrap slice, including Harbor's required backend services such as MinIO and the
  PostgreSQL surface Harbor needs, pulls from public container repositories while Harbor is not yet available
- Harbor's chart-generated secret material and registry credentials remain stable across the
  `harbor-final` and `final` Helm phases so repeat `cluster up` runs do not invalidate Harbor
  login or image publication state
- no repo-owned workload and no non-Harbor platform workload that is not required for Harbor
  bootstrap rolls out before Harbor is reachable enough to serve pulls
- once Harbor is ready, `infernix cluster up` mirrors all non-Harbor third-party images into
  Harbor and builds then publishes repo-owned images to Harbor before any later non-Harbor Helm
  rollout, add-on rollout, or PostgreSQL-backed service rollout
- `infernix cluster up` builds the repo-owned runtime images required by the active chart and
  uploads them to Harbor before the post-bootstrap rollout
- Helm values reference Harbor image coordinates for every non-Harbor cluster pod in the final rollout
- after Harbor reaches its final rollout shape, `cluster up` preloads the Harbor-backed final image
  refs onto the Kind worker before the remaining non-Harbor workloads are scaled
- publication is idempotent and compares local versus remote digests where possible
- interrupted Harbor bootstrap state is repaired during repeat `cluster up` runs before the final
  Harbor-backed rollout proceeds
- no compatibility bootstrap registry remains for MinIO or Pulsar or other non-Harbor workloads

### Validation

- `infernix cluster up` first produces a healthy Harbor bootstrap slice through Helm using public
  image references for Harbor and the services Harbor needs during bootstrap
- `infernix cluster up` does not begin the remaining non-Harbor rollout until Harbor is reachable
  enough for image publication and pulls
- `infernix cluster up` publishes the service and webapp images before the final non-Harbor deploy
- `infernix kubectl get pods -A -o jsonpath=...` shows every post-bootstrap non-Harbor pod pulling
  from Harbor-managed references
- clean and repeat Apple-host reruns show the Kind worker image store contains the Harbor-backed
  final image refs before the remaining non-Harbor workloads begin their final rollout
- clean and repeat Apple-host reruns show the Harbor-retagged MinIO StatefulSet transition
  completes from Harbor-backed refs without a transient first-pull `502 Bad Gateway`
- repeated `infernix cluster up` runs avoid unnecessary pushes when digests match
- repeated `infernix cluster up` runs can repair interrupted Harbor migration state before the
  final Harbor-backed rollout
- the generated Kind registry-host config no longer needs a `localhost:30001` helper-registry namespace

### Remaining Work

None.

---

## Sprint 2.5: Kind Lifecycle Idempotency and Status Surface [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `compose.yaml`, `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-cuda.yaml`, `test/integration/Spec.hs`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Make cluster reconcile, status, and teardown predictable.

### Deliverables

- `cluster up` is a reconcile operation for the supported test cluster, not a throwaway bootstrap script
- `cluster up` is declarative and idempotent on repeated runs
- `infernix cluster status` reports cluster existence, route status, chosen edge port, active
  runtime mode, demo-config publication details, and storage-health summary without side effects
- `infernix cluster down` declaratively tears down Kind while never deleting or mutating `./.data/`
- explicit destructive cleanup, if later added, is opt-in and separate from ordinary teardown
- on the Linux outer-container lane, cluster-backed commands keep host-published Kind API and
  routed edge ports on `127.0.0.1` while the launcher reaches the cluster through the private
  Docker `kind` network and the repo-local kubeconfig generated from
  `kind get kubeconfig --internal`
- the repo-owned Kind configs pin `kindest/node:v1.34.0` across the static asset set and the
  rendered cluster lifecycle path

### Validation

- `./.build/infernix cluster up`, `./.build/infernix cluster status`, `./.build/infernix cluster down`, and repeat `./.build/infernix cluster up` work in sequence on Apple without manual cleanup
- repeated `./.build/infernix cluster down` succeeds without requiring manual cluster cleanup
- `infernix lint chart` passes and enforces the loopback-only Kind config plus pinned
  `kindest/node:v1.34.0` node images across the repo-owned Kind asset set
- a clean outer-container Kind probe shows `docker port <control-plane>` reports
  `127.0.0.1:...` host bindings, `kind get kubeconfig --internal` records the internal
  `<cluster>-control-plane:6443` endpoint, and `kubectl --kubeconfig ... get nodes` succeeds
  after the launcher container joins the private Docker `kind` network
- durable volumes rebind to the same `./.data/` paths after teardown and redeploy
- `cluster up` output displays the chosen localhost port
- if `9090` is free, `cluster up` chooses `9090`; if not, it chooses the next open port by incrementing by 1
- status output includes the active localhost port, runtime mode, demo-config publication details, and browser route prefixes

### Remaining Work

None.

---

## Sprint 2.6: Mode-Aware `cluster up` Demo Config Staging and ConfigMap Publication [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/Models.hs`, `chart/templates/configmap-demo-catalog.yaml`, `chart/templates/deployment-service.yaml`, `chart/templates/deployment-demo.yaml`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/build_artifacts.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/development/testing_strategy.md`

### Objective

Make `cluster up` the canonical point where the active runtime mode's generated demo catalog is
materialized and published for later service, UI, and test flows.

### Deliverables

- `cluster up` emits `infernix-demo-apple-silicon.dhall`, `infernix-demo-linux-cpu.dhall`, or
  `infernix-demo-linux-cuda.dhall` according to the active runtime mode
- the generated file contains every README-matrix row supported by that mode and no unsupported rows
- the generated file records the selected engine binding from the corresponding README matrix column
- `cluster up` creates or updates `ConfigMap/infernix-demo-config` from that generated content
- in containerized execution contexts, the published ConfigMap is mounted at `/opt/build/`, where
  the daemon watches the `.dhall` next to its binary
- the mounted ConfigMap-backed file becomes the exact source of truth later consumed by the service,
  web UI, `test integration`, and `test e2e`

### Validation

- switching runtime modes changes the generated filename, catalog entries, and engine bindings deterministically
- unsupported rows are absent from the active mode's generated demo catalog
- generated files live only under the active build root and never land in tracked source paths
- `infernix kubectl get configmap infernix-demo-config -n <namespace> -o yaml` shows the active mode's published catalog

### Remaining Work

None.

---

## Sprint 2.7: GPU-Enabled Kind Runtime For `linux-cuda` [Done]

**Status**: Done
**Implementation**: `kind/cluster-linux-cuda.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `chart/templates/deployment-service.yaml`, `chart/templates/runtimeclass-nvidia.yaml`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/architecture/runtime_modes.md`, `documents/development/testing_strategy.md`

### Objective

Make `linux-cuda` a real GPU-backed cluster mode rather than a nominal matrix column.

### Deliverables

- `kind/cluster-linux-cuda.yaml` captures the GPU worker labels and the NVIDIA worker-device
  volume-mount path consumed by the supported `nvkind`-backed Kind path
- `cluster up` in `linux-cuda` fails fast unless the host passes the NVIDIA preflight contract for
  `nvidia-smi`, Docker `--gpus all`, and the Kind worker device-mount probe
- `cluster up` in `linux-cuda` reconciles the Kind cluster through `nvkind`, preserving the
  repo-local kubeconfig contract while exposing NVIDIA runtime support inside the Kind node
  containers; when the current upstream `nvkind` build hits its late configmap-persistence bug, the
  repo-owned bootstrap finishes the node-side toolkit, containerd setup, and NVIDIA userspace sync
  itself before the repo-owned device-plugin reconcile runs
- the cluster installs the NVIDIA device plugin so nodes expose allocatable `nvidia.com/gpu`
  through the real Kubernetes resource inventory rather than synthetic status patching
- repo-owned workload rules for CUDA lanes request `nvidia.com/gpu` and apply the required runtime
  configuration, such as `runtimeClassName: nvidia`, when needed by the chosen implementation, and
  the repo-owned bootstrap creates `RuntimeClass/nvidia` before the device-plugin rollout depends on it
- cluster-resident CUDA workloads can schedule on the GPU-capable Kind substrate and run
  `nvidia-smi -L` inside the service deployment on supported hosts

### Validation

- `./.build/infernix test lint` passes `infernix lint chart`, which verifies the GPU Kind config
  carries the worker-device volume mount and the GPU node label
- `infernix kubectl get nodes -l infernix.runtime/gpu=true -o jsonpath=...` on the current Kind
  path shows positive allocatable `nvidia.com/gpu` resources for `linux-cuda`
- `infernix kubectl -n nvidia get daemonset nvidia-device-plugin-daemonset -o jsonpath=...`
  shows the NVIDIA device plugin rollout is ready on the GPU-capable nodes
- `infernix kubectl get deployment -n platform infernix-service -o jsonpath=...` shows
  `runtimeClassName: nvidia`, `nvidia.com/gpu: 1`, and the GPU node selector on the CUDA service
  workload
- `infernix kubectl -n platform exec deployment/infernix-service -- nvidia-smi -L` reports at
  least one visible GPU on a supported NVIDIA host
- `docker compose run --rm infernix infernix --runtime-mode linux-cuda test integration` passes on
  the supported NVIDIA-backed outer-container path and exercises the CUDA lane through repeated
  `cluster up` or `cluster down` lifecycle checks
- `docker compose run --rm infernix infernix --runtime-mode linux-cuda test e2e` passes on the
  supported NVIDIA-backed outer-container final substrate while the `infernix-service` pod
  schedules onto the GPU-labeled worker

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/k8s_native_dev_policy.md` - Kind bootstrap, GPU-enabled `linux-cuda`, and Helm lifecycle
- `documents/engineering/k8s_storage.md` - manual PV policy, PVC ownership, and `infernix-manual`
- `documents/engineering/build_artifacts.md` - generated demo-config staging, watched mount path, and naming
- `documents/tools/harbor.md` - local registry contract

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - cluster lifecycle commands
- `documents/operations/cluster_bootstrap_runbook.md` - bootstrap, reconcile, and teardown workflow
- `documents/development/testing_strategy.md` - active-mode generated catalog and GPU-enabled `linux-cuda` contract

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when storage, image-flow, runtime-mode, watched config paths, GPU-enabled `linux-cuda`, or generated-demo-config assumptions change
