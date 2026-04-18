# Phase 2: Kind Cluster Storage and Lifecycle

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported Kind bootstrap path, the manual storage doctrine, the Helm
> umbrella deployment model, the Harbor-backed image preparation flow embedded in `cluster up`, and
> the mode-aware generated-demo-config behavior tied to cluster reconcile.

## Storage Doctrine

These rules close in this phase and remain mandatory afterward:

- cluster bootstrap deletes every default StorageClass present on the supported Kind path
- the only supported persistent StorageClass is `infernix-manual` using `kubernetes.io/no-provisioner`
- durable PVCs come only from Helm-managed StatefulSets or chart-owned persistence templates
- durable PVs come only from the storage-reconciliation step embedded in `infernix cluster up`
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
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`, `tools/discover_chart_claims.py`, `tools/helm_chart_check.py`, `chart/templates/workloads-platform-portals.yaml`
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
- reconciliation rejects workloads that request implicit storage classes
- reconciliation rejects hand-authored standalone durable PVC manifests outside chart ownership
- PV manifests bind explicitly to their intended claims so down/up cycles automatically reattach the
  same claims to the same `./.data/` paths

### Validation

- `./.build/infernix test lint` passes `tools/helm_chart_check.py`, which renders the chart and
  rejects PVCs missing `storageClassName: infernix-manual` or chart-ownership labels through
  `tools/discover_chart_claims.py`
- repeated `infernix cluster up` runs perform idempotent storage reconciliation
- `helm template` plus the `cluster up` storage step creates one PV per expected durable PVC
- `infernix kubectl get pv,pvc -A` shows all durable claims bound through `infernix-manual`
- `cluster down` followed by `cluster up` rebinds durable claims to the same PVs without manual
  storage repair

### Remaining Work

None.

---

## Sprint 2.3: Helm Umbrella Chart and Repo Workload Layout [Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/Chart.lock`, `chart/values.yaml`, `chart/templates/`, `src/Infernix/Cluster.hs`, `tools/platform_asset_check.py`, `tools/helm_chart_check.py`
**Docs to update**: `documents/architecture/overview.md`, `documents/engineering/k8s_native_dev_policy.md`

### Objective

Put repo-owned and third-party workloads behind one Helm deployment model.

### Deliverables

- one umbrella chart under `chart/`
- repo-owned workloads for the Haskell service, the webapp service, the edge-routing configuration, and the current Harbor or MinIO or Pulsar portal surfaces now exist as chart templates and values
- chart dependencies for Harbor, MinIO, Pulsar, and ingress-nginx
- the webapp service is deployed through repo-owned Helm chart templates and values, not ad hoc manifests
- repo-owned workloads mount `ConfigMap/infernix-demo-config` in the watched runtime directory used by the daemon and UI
- chart defaults encode the mandatory local HA topology: three-replica Harbor and Pulsar surfaces
  where supported by the chosen charts, and a four-replica distributed MinIO deployment
- repo-owned Helm values explicitly suppress hard pod anti-affinity and equivalent hard scheduling
  constraints that would otherwise block the mandatory replicas from scheduling on local Kind
- no alternate single-replica dev chart profile is introduced

### Validation

- `./.build/infernix test lint` passes `tools/platform_asset_check.py` and `tools/helm_chart_check.py`
- the chart templates mount `ConfigMap/infernix-demo-config` at `/opt/build/` for both the service and web workloads
- `chart/values.yaml` records the mandatory HA replica targets and the stable routed edge inventory
- `helm lint chart` and `helm template infernix chart` succeed through the repo-owned dependency bootstrap path
- `./.build/infernix --runtime-mode apple-silicon test integration` and
  `docker compose run --rm infernix infernix --runtime-mode apple-silicon test e2e` both reconcile
  the chart through Helm on the current host-native and outer-container control-plane paths

### Remaining Work

None.

---

## Sprint 2.4: Automatic Harbor Image Preparation and Helm Pull Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `tools/publish_chart_images.py`, `web/Dockerfile`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/tools/harbor.md`

### Objective

Use Harbor as the source of truth for cluster image pulls, with image preparation handled
automatically during `cluster up`.

### Deliverables

- `infernix cluster up` mirrors all non-Harbor third-party images into Harbor and builds then
  publishes repo-owned images to Harbor before Helm rollout
- `infernix cluster up` builds the separate webapp image through `web/Dockerfile` and uploads it to Harbor
- before Harbor is ready, `cluster up` now also mirrors the MinIO and Pulsar bootstrap images into
  a repo-built bootstrap registry on `localhost:30001`, and Kind registry-host config rewrites that
  namespace to the helper registry on the Kind network
- Helm values reference Harbor image coordinates for every cluster pod except Harbor's own bootstrap path
- publication is idempotent and compares local versus remote digests where possible
- interrupted Harbor bootstrap state is repaired during repeat `cluster up` runs before the final
  Harbor-backed rollout proceeds
- workload rollout waits until Harbor is reachable enough to pull published images

### Validation

- `infernix cluster up` publishes the service and webapp images before deploy
- `infernix kubectl get pods -A -o jsonpath=...` shows every non-Harbor pod pulling from Harbor-managed references
- repeated `infernix cluster up` runs avoid unnecessary pushes when digests match
- repeated `infernix cluster up` runs can repair interrupted Harbor migration state before the
  final Harbor-backed rollout

### Remaining Work

None.

---

## Sprint 2.5: Kind Lifecycle Idempotency and Status Surface [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `.build/infernix`
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

### Validation

- `./.build/infernix cluster up`, `./.build/infernix cluster status`, `./.build/infernix cluster down`, and repeat `./.build/infernix cluster up` work in sequence on Apple without manual cleanup
- repeated `./.build/infernix cluster down` succeeds without requiring manual cluster cleanup
- `docker compose run --rm infernix infernix cluster up`, `cluster status`, `cluster down`, and repeat `cluster up` work in sequence on the Linux outer path without manual cleanup
- repeated `docker compose run --rm infernix infernix cluster down` succeeds without requiring manual cluster cleanup
- durable volumes rebind to the same `./.data/` paths after teardown and redeploy
- `cluster up` output displays the chosen localhost port
- if `9090` is free, `cluster up` chooses `9090`; if not, it chooses the next open port by incrementing by 1
- status output includes the active localhost port, runtime mode, demo-config publication details, and browser route prefixes

### Remaining Work

None.

---

## Sprint 2.6: Mode-Aware `cluster up` Demo Config Staging and ConfigMap Publication [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/Models.hs`, `chart/templates/configmap-demo-catalog.yaml`, `chart/templates/deployment-service.yaml`, `chart/templates/deployment-web.yaml`, `test/integration/Spec.hs`
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
**Implementation**: `kind/cluster-linux-cuda.yaml`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-service.yaml`, `chart/templates/runtimeclass-nvidia.yaml`, `test/integration/Spec.hs`, `tools/platform_asset_check.py`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/architecture/runtime_modes.md`, `documents/development/testing_strategy.md`

### Objective

Make `linux-cuda` a real GPU-backed cluster mode rather than a nominal matrix column.

### Deliverables

- `kind/cluster-linux-cuda.yaml` captures the NVIDIA container runtime patch and GPU node labels
  that the real Kind path reconciles
- `cluster up` in `linux-cuda` reconciles a Kind path that exposes NVIDIA container runtime support
  inside the Kind node containers
- the cluster reconciles an equivalent supported GPU-advertising surface so nodes expose
  allocatable `nvidia.com/gpu`
- repo-owned workload rules for CUDA lanes request `nvidia.com/gpu` and apply the required runtime
  configuration, such as `runtimeClassName: nvidia`, when needed by the chosen implementation
- cluster-resident CUDA workloads can schedule on the GPU-capable Kind substrate

### Validation

- `./.build/infernix test lint` passes `tools/platform_asset_check.py`, which verifies the GPU Kind config carries `nvidia-container-runtime` and the GPU node label
- `infernix kubectl get nodes -l infernix.runtime/gpu=true -o jsonpath=...` on the current Kind
  path shows allocatable `nvidia.com/gpu` resources for `linux-cuda`
- `infernix kubectl get deployment -n platform infernix-service -o jsonpath=...` shows
  `runtimeClassName: nvidia`, `nvidia.com/gpu: 1`, and the GPU node selector on the CUDA service
  workload
- `./.build/infernix --runtime-mode linux-cuda test integration` passes on the host-native path
  and exercises the CUDA lane through repeated `cluster up` or `cluster down` lifecycle checks
- `./.build/infernix --runtime-mode linux-cuda test e2e` passes on the host-native final
  substrate while the `infernix-service` pod schedules onto the GPU-labeled worker

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
