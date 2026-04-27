# Phase 3: HA Platform Services and Edge Routing

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, operator-managed PostgreSQL, and
> Pulsar deployments; the Envoy Gateway installation that owns all browser-visible routing on one
> localhost listener; the publication contract; and the route-registry cleanup that removes route
> duplication across Haskell, Helm, lint, and docs.

## Phase Status

Sprints 3.1, 3.2, 3.3, 3.4, 3.6, and 3.7 are `Done`. Sprint 3.5 remains `Active` because the
Gateway controller and listener still need refreshed real-cluster acceptance on the current final
chart shape. Sprint 3.8 is `Planned` because the route registry and data-driven HTTPRoute
rendering are not landed yet.

## HA Reconcile Surface

- `infernix cluster up` is the declarative and idempotent entrypoint for the mandatory local HA topology
- the supported cluster path always deploys the local HA topology
- no service-specific HA bootstrap command family exists outside the supported cluster reconcile surface

## PostgreSQL Doctrine

- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes operator
- services or add-ons that can self-deploy PostgreSQL disable that path and point at an operator-managed cluster instead
- PostgreSQL claims use `infernix-manual` and explicit PV binding from Phase 2
- Harbor remains the first deployed service on a pristine cluster

## Mode-Stable Route Contract

- runtime-mode changes do not fork the browser entrypoint
- `/`, `/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws`
  remain the published route inventory
- `/api/publication` remains the routed metadata endpoint for publication state
- Apple host-native mode switching never changes the browser base URL

## Current Repo Assessment

The supported cluster path already runs the HA platform services and the optional demo HTTP host on
the final Kind and Helm substrate. Publication metadata originates from
`./.data/runtime/publication.json`, and Envoy Gateway assets are present in the worktree. The
remaining Phase 3 cleanup is specifically about route ownership:

- the current route inventory is still duplicated across `src/Infernix/Models.hs`,
  `chart/templates/httproutes/*.yaml`, `src/Infernix/Lint/Chart.hs`, and `chart/values.yaml`
- Gateway resources still need refreshed real-cluster acceptance on the current final chart shape

## Sprint 3.1: HA MinIO Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/object_storage.md`, `documents/tools/minio.md`

### Objective

Make MinIO the durable object store for runtime manifests, artifacts, large outputs, and Harbor
image blobs.

### Deliverables

- MinIO always deploys as a four-node distributed cluster with manual PV backing
- repo-owned values suppress hard pod anti-affinity that would block local Kind scheduling
- MinIO console and S3 API are both exposed through the shared edge
- repo-owned services treat MinIO as the durable artifact source of truth

### Validation

- `infernix cluster up` creates a healthy four-node distributed MinIO deployment
- MinIO PVCs bind via `infernix-manual`
- routed MinIO console and S3 surfaces respond on the shared edge port

### Remaining Work

None.

---

## Sprint 3.2: Operator-Managed Patroni PostgreSQL [Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/Lint/Chart.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/harbor.md`, `documents/tools/postgresql.md`

### Objective

Standardize every in-cluster PostgreSQL dependency on one HA operator-managed contract.

### Deliverables

- the supported cluster path installs the Percona operator through the repo-owned Helm workflow
- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by that operator
- services that can self-deploy PostgreSQL disable that path and use operator-managed clusters instead
- operator-managed PostgreSQL claims bind through `infernix-manual`

### Validation

- `infernix cluster up` produces ready Percona and Patroni members for Harbor's PostgreSQL backend
- rendered Helm values disable embedded standalone PostgreSQL deployments where applicable
- repeat `cluster down` plus `cluster up` cycles rebind PostgreSQL claims to the same PVs

### Remaining Work

None.

---

## Sprint 3.3: HA Pulsar Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/tools/pulsar.md`

### Objective

Provide the durable event transport for inference requests, results, and service coordination.

### Deliverables

- Pulsar deploys through the Helm chart with HA settings where the chart exposes them
- durable Pulsar components use manual PVs under `./.data/`
- the edge exposes browser- and host-consumable Pulsar HTTP or WebSocket surfaces
- inference-request, result, and coordination payloads are defined by repo-owned `.proto` schemas

### Validation

- `infernix cluster up` produces a healthy Pulsar deployment
- Pulsar PVCs bind through `infernix-manual`
- routed Pulsar admin and WebSocket surfaces respond on the shared edge port

### Remaining Work

None.

---

## Sprint 3.4: HA Harbor Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/tools/harbor.md`

### Objective

Provide the mandatory local HA image registry and browser portal for cluster images.

### Deliverables

- Harbor deploys through its Helm chart
- Harbor stores image blobs in MinIO and uses an operator-managed Patroni PostgreSQL backend
- Harbor application-plane workloads use the mandatory HA topology where the chart exposes it
- the Harbor portal is exposed through the shared edge

### Validation

- `infernix cluster up` produces a healthy Harbor release with the expected HA shape
- routed Harbor access works on the shared edge port
- deleting a single Harbor application pod does not permanently break access or image pulls

### Remaining Work

None.

---

## Sprint 3.5: Envoy Gateway API Installation and Localhost Listener [Active]

**Status**: Active
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/gatewayclass.yaml`, `chart/templates/gateway.yaml`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace the old repo-owned edge process with Envoy Gateway API and one localhost-bound listener
that fronts every published surface.

### Deliverables

- the Helm chart pulls the Envoy Gateway controller as a dependency
- one `GatewayClass/infernix-gateway` and one `Gateway/infernix-edge` own the shared listener
- `cluster up` records the chosen port under `./.data/runtime/edge-port.json`
- the demo cluster remains local-only and publishes plain HTTP with no auth filter

### Validation

- `infernix cluster status` prints the chosen port and published route inventory
- `infernix kubectl get gatewayclass,gateway -n platform` shows the GatewayClass and Gateway in
  `Accepted` state with the chosen listener port
- `infernix test integration` proves the Envoy data plane is ready before routed checks run

### Remaining Work

- the chart change is landed, but this sprint still needs refreshed real-cluster validation that
  `Gateway/infernix-edge` reaches `Accepted` on the current final Kind substrate
- tracked-index cleanup for deleted legacy edge files remains part of Phase 1 Sprint 1.7

---

## Sprint 3.6: Demo HTTP Host (`infernix-demo`) and Apple Host Bridge [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Provide the demo HTTP API surface through the `infernix-demo` Haskell binary and keep the browser
entrypoint stable when the demo surface is enabled.

### Deliverables

- `infernix-demo` is the single repo-owned source of the demo HTTP surface
- the chart deploys `infernix-demo` only when the active generated `.dhall` enables `demo_ui`
- production `infernix service` binds no HTTP listener
- the Apple host bridge uses `infernix-demo serve --dhall PATH --port N` without changing the
  browser entrypoint

### Validation

- the routed demo workbench loads from `infernix-demo` when `demo_ui` is on
- switching between host-native and cluster-resident `infernix-demo` does not change the browser base URL
- when `demo_ui` is off, the cluster has no demo routes

### Remaining Work

None.

---

## Sprint 3.7: Mode-Stable Publication Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make edge-route publication, runtime-mode reporting, and demo-config publication details line up
so operators and browser clients keep one stable mode-aware entrypoint.

### Deliverables

- `cluster status` reports runtime mode and publication details alongside edge routes
- the supported reconcile path writes `./.data/runtime/publication.json`
- `/api/publication` exposes the routed publication details consumed by the browser workbench
- Apple host bridge behavior preserves the same browser entrypoint used by the cluster-resident path

### Validation

- `cluster status` reports runtime mode, demo-config publication details, and edge routes
- `GET /api/publication` returns the routed publication details consumed by the browser
- switching runtime modes changes publication details without changing route prefixes

### Remaining Work

None.

---

## Sprint 3.8: Canonical Route Registry and Data-Driven HTTPRoute Rendering [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/Routes.hs`, `chart/templates/httproutes.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Models.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Collapse the route and publication contract to one Haskell-owned source of truth that drives the
rendered HTTPRoute set, publication metadata, chart lint, and route-oriented docs.

### Deliverables

- one Haskell route registry records:
  - path prefix
  - purpose label
  - backend service identity
  - rewrite behavior
  - demo-only versus always-on visibility
  - publication-upstream metadata
- one data-driven chart template renders the entire HTTPRoute set from that registry
- publication-state rendering and `/api/publication` derive their route inventory from the same registry
- chart lint expectations derive from the same registry rather than file-by-file template assertions
- the route inventory is no longer duplicated across `src/Infernix/Models.hs`,
  `chart/templates/httproutes/*.yaml`, `src/Infernix/Lint/Chart.hs`, and `chart/values.yaml`

### Validation

- `infernix kubectl get httproute -n platform` shows the expected route set in `Accepted` state
- `GET /api/publication` reports the exact route inventory produced by the registry
- `infernix test lint` fails if a route is added in one route-aware surface without the registry update
- routed Harbor, MinIO, Pulsar, and demo probes continue to work through the shared listener

### Remaining Work

- implementation has not started

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - Envoy Gateway installation, single listener, route-registry ownership, and no-auth demo-cluster posture
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/engineering/k8s_storage.md` - manual PV doctrine and PostgreSQL claim binding
- `documents/tools/minio.md` - MinIO deployment and routed surfaces
- `documents/tools/postgresql.md` - Percona operator and Patroni deployment rules
- `documents/tools/pulsar.md` - Pulsar deployment and routed surfaces
- `documents/tools/harbor.md` - Harbor deployment and routed portal or API split
- `documents/engineering/monitoring.md` - required if monitoring remains a supported first-class surface after route or service closure

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory and active-mode catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup and bridge behavior

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when route prefixes, publication fields, or daemon-location rules change
