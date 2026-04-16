# Phase 2: Kind Cluster Storage and Lifecycle

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported Kind bootstrap path, the manual storage doctrine, the Helm
> umbrella deployment model, and the Harbor-backed image preparation flow embedded in `cluster up`.

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

## Lifecycle Command Contract

- `infernix cluster up` is the declarative and idempotent cluster reconcile entrypoint.
- `infernix cluster down` is the declarative and idempotent cluster teardown entrypoint.
- `infernix cluster status` is read-only and never mutates cluster or repo state.
- `infernix kubectl ...` is the supported wrapper for Kubernetes access and automatically uses the
  repo-local kubeconfig created by `cluster up`.
- No separate imperative storage, image-publication, or deploy command family exists outside
  `cluster up`.

## Sprint 2.1: Kind Bootstrap and StorageClass Reset [Active]

**Status**: Active
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
- bootstrap auto-generates the Dhall config required by supported test workflows and enables all models appropriate for the active mode under test

### Validation

- `./.build/infernix cluster up` creates or reuses the Kind cluster on Apple Silicon
- `docker compose run --rm infernix infernix cluster up` does the same on the Linux outer path
- `./.build/infernix kubectl get storageclass` shows `infernix-manual` and no default class after bootstrap on Apple
- `docker compose run --rm infernix infernix kubectl get storageclass` shows the same on the Linux outer path
- the generated test Dhall config exists in the build-output location for the active execution context
- the repo-local kubeconfig exists in the build-output location for the active execution context

### Remaining Work

- replace the current cluster-state compatibility layer with real Kind lifecycle integration
- validate the reset behavior against a real Kubernetes storage-class inventory

---

## Sprint 2.2: Manual PV Reconciliation During Cluster Up [Active]

**Status**: Active
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`
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

- repeated `infernix cluster up` runs perform idempotent storage reconciliation
- `helm template` plus the `cluster up` storage step creates one PV per expected durable PVC
- `infernix kubectl get pv,pvc -A` shows all durable claims bound through `infernix-manual`
- `cluster down` followed by `cluster up` rebinds durable claims to the same PVs without manual
  storage repair

### Remaining Work

- template expected durable claims from chart-owned manifests instead of the current seeded compatibility inventory
- bind real PV and PVC objects once the Kind and Helm path is closed

---

## Sprint 2.3: Helm Umbrella Chart and Repo Workload Layout [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.4`
**Docs to update**: `documents/architecture/overview.md`, `documents/engineering/k8s_native_dev_policy.md`

### Objective

Put repo-owned and third-party workloads behind one Helm deployment model.

### Deliverables

- one umbrella chart under `chart/`
- repo-owned workloads for the Haskell service, the webapp service, and edge-routing configuration
- chart dependencies for Harbor, MinIO, Pulsar, and ingress-nginx
- the webapp service is deployed through repo-owned Helm chart templates and values, not ad hoc manifests
- chart defaults encode the mandatory local HA topology: three-replica Harbor and Pulsar surfaces
  where supported by the chosen charts, and a four-replica distributed MinIO deployment
- repo-owned Helm values explicitly suppress hard pod anti-affinity and equivalent hard scheduling
  constraints that would otherwise block the mandatory replicas from scheduling on local Kind
- no alternate single-replica dev chart profile is introduced

### Validation

- `helm lint chart` passes
- `helm template infernix chart` renders the repo-owned and third-party workloads together
- rendered manifests show the mandatory replica counts and do not enforce hard pod anti-affinity
  that would block Kind scheduling
- `cluster up` deploys through Helm rather than checked-in static manifests

---

## Sprint 2.4: Automatic Harbor Image Preparation and Helm Pull Contract [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.4`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/tools/harbor.md`

### Objective

Use Harbor as the source of truth for cluster image pulls, with image preparation handled
automatically during `cluster up`.

### Deliverables

- `infernix cluster up` mirrors all non-Harbor third-party images into Harbor and builds then
  publishes repo-owned images to Harbor before Helm rollout
- `infernix cluster up` builds the separate webapp image through `web/Dockerfile` and uploads it to Harbor
- Helm values reference Harbor image coordinates for every cluster pod except Harbor's own bootstrap path
- publication is idempotent and compares local versus remote digests where possible
- workload rollout waits until Harbor is reachable enough to pull published images

### Validation

- `infernix cluster up` publishes the service and webapp images before deploy
- `infernix kubectl get pods -A -o jsonpath=...` shows every non-Harbor pod pulling from Harbor-managed references
- repeated `infernix cluster up` runs avoid unnecessary pushes when digests match

---

## Sprint 2.5: Kind Lifecycle Idempotency and Status Surface [Active]

**Status**: Active
**Implementation**: `src/Infernix/Cluster.hs`, `.build/infernix`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Make cluster reconcile, status, and teardown predictable.

### Deliverables

- `cluster up` is a reconcile operation for the supported test cluster, not a throwaway bootstrap script
- `cluster up` is declarative and idempotent on repeated runs
- `infernix cluster status` reports cluster existence, route status, chosen edge port, and storage-health summary without side effects
- `infernix cluster down` declaratively tears down Kind while never deleting or mutating `./.data/`
- explicit destructive cleanup, if later added, is opt-in and separate from ordinary teardown

### Validation

- `./.build/infernix cluster up`, `./.build/infernix cluster status`, `./.build/infernix cluster down`, and repeat `./.build/infernix cluster up` work in sequence on Apple without manual cleanup
- repeated `./.build/infernix cluster down` succeeds without requiring manual cluster cleanup
- `docker compose run --rm infernix infernix cluster up`, `cluster status`, `cluster down`, and repeat `cluster up` work in sequence on the Linux outer path without manual cleanup
- repeated `docker compose run --rm infernix infernix cluster down` succeeds without requiring manual cluster cleanup
- durable volumes rebind to the same `./.data/` paths after teardown and redeploy
- status output includes the active localhost port and the browser route prefixes

### Remaining Work

- validate the same lifecycle sequence on the outer-container path
- extend status output from repo-local state summaries to real cluster health once Kind rollout is wired in

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/k8s_native_dev_policy.md` - Kind bootstrap and Helm lifecycle
- `documents/engineering/k8s_storage.md` - manual PV policy, PVC ownership, and `infernix-manual`
- `documents/tools/harbor.md` - local registry contract

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - cluster lifecycle commands
- `documents/operations/cluster_bootstrap_runbook.md` - bootstrap, reconcile, and teardown workflow

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when storage or image-flow assumptions change
