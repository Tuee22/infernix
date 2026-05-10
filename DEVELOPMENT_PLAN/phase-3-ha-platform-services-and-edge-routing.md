# Phase 3: HA Platform Services and Edge Routing

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, operator-managed PostgreSQL, and
> Pulsar deployments; the Envoy Gateway installation that owns all browser-visible routing on one
> localhost listener; the publication contract; and the route-registry cleanup that removes route
> duplication across Haskell, Helm, route-oriented docs, and route-aware validation.

## Phase Status

Phase 3 is done. The route registry, publication-state rendering, `/pulsar/ws -> /ws` rewrite
contract, shared in-cluster substrate filename, explicit demo-off staging path, and Apple route or
publication closure are all represented and validated in the current worktree. The supported
tool-route contract depends on the real Harbor, MinIO, and Pulsar upstreams rather than direct
`infernix-demo` compatibility handlers outside the intended HTTPRoute mapping, and the routed
Apple path now keeps the demo surface clustered while bridging manual inference into the
host-native daemon.

## HA Reconcile Surface

- `infernix cluster up` is the declarative and idempotent entrypoint for the mandatory local HA topology
- the supported cluster path always deploys the local HA topology
- no service-specific HA bootstrap command family exists outside the supported cluster reconcile surface

## PostgreSQL Doctrine

- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes operator
- services or add-ons that can self-deploy PostgreSQL disable that path and point at an operator-managed cluster instead
- PostgreSQL claims use `infernix-manual` and explicit PV binding from Phase 2
- Harbor remains the first deployed service on a pristine cluster

## Substrate-Stable Route Contract

- substrate changes do not fork the browser entrypoint
- when the demo UI is enabled, `/`, `/api`, `/objects`, `/harbor/api`, `/harbor`,
  `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` remain the published route
  inventory
- `/api/publication` and `/api/cache` remain stable routed demo endpoints under the `/api` prefix
- the final Apple hybrid path keeps the same browser base URL while allowing routed cluster
  surfaces to bridge into the host-native Apple inference daemon

## Current Repo Assessment

The supported cluster path runs the HA platform services and the optional demo HTTP host on the
Kind substrate. Publication metadata originates from `./.data/runtime/publication.json`, exposes
the active substrate through current `runtimeMode` fields, derives the route inventory from one
Haskell-owned registry plus one data-driven HTTPRoute template, and now reports
`inferenceDispatchMode` beside the direct `infernix service` daemon location and the routed demo
API upstream. On `apple-silicon`, the routed Apple path keeps the demo surface in-cluster while
bridging manual inference into the host-native daemon instead of executing that work inside a
cluster-resident Apple repo workload, and `cluster up` no longer deploys `infernix-service` on
that lane. Demo-off routing is supported through the explicit substrate-materialization helper with
`--demo-ui false`. Direct `infernix-demo` execution is limited to the demo-owned HTTP surface when
used intentionally outside the routed cluster path, so Harbor, MinIO, and Pulsar probes depend on
the intended HTTPRoute mapping.

## Sprint 3.1: HA MinIO Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/object_storage.md`, `documents/tools/minio.md`

### Objective

Provide the HA MinIO deployment and routed object-store surfaces required by Harbor and the future
real cluster object-store path.

### Deliverables

- MinIO always deploys as a four-node distributed cluster with manual PV backing
- repo-owned values suppress hard pod anti-affinity that would block local Kind scheduling
- MinIO console and S3 API are both exposed through the shared edge
- the chart reserves MinIO as the Kind-backed object-store target for Harbor and the future real
  cluster runtime path, while the current validated runtime keeps durable object-store state under
  `./.data/object-store/`

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
- repeat `cluster down` plus `cluster up` cycles rebind operator-managed PostgreSQL storage onto the
  same deterministic PV inventory and host paths

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

## Sprint 3.5: Envoy Gateway API Installation and Localhost Listener [Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/gatewayclass.yaml`, `chart/templates/gateway.yaml`, `chart/templates/envoyproxy.yaml`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
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
- `infernix kubectl get gatewayclass,gateway -n platform` shows the GatewayClass `Accepted` and
  `Gateway/infernix-edge` programmed on the chosen listener port
- `infernix kubectl get httproute -n platform` shows the published route set in `Accepted` state
- routed `/pulsar/admin` and `/pulsar/ws` probes prove the Envoy data plane forwards the final
  Gateway route set on the Kind-plus-Helm path

### Remaining Work

None.

---

## Sprint 3.6: Demo HTTP Host (`infernix-demo`) and Host-Demo Bridge Retirement [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Provide the current demo HTTP API surface through the `infernix-demo` Haskell binary while keeping
one stable clustered browser entrypoint across substrates.

### Deliverables

- `infernix-demo` is the single repo-owned source of the demo HTTP surface
- the chart deploys `infernix-demo` only when the active generated `.dhall` enables `demo_ui`
- production `infernix service` binds no HTTP listener
- the Apple host-native control plane stays distinct from the clustered browser entrypoint without
  introducing a host-side demo bridge

### Validation

- the routed demo workbench loads from `infernix-demo` when `demo_ui` is on
- keeping the Apple host-native control plane does not change the browser base URL
- when `demo_ui` is off, the cluster has no demo routes

### Remaining Work

None.

---

## Sprint 3.9: Clustered Demo Surface and Apple Host-Inference Bridge [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `chart/templates/deployment-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `README.md`, `documents/architecture/web_ui_architecture.md`, `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Keep the routed demo surface cluster-resident while making the Apple host-inference bridge an
explicit part of the supported Apple contract.

### Deliverables

- when `demo_ui` is enabled, the routed demo app always runs from the cluster deployment
- Apple host-native operators still use the same browser base URL, and the routed demo surface
  keeps its clustered HTTP host instead of swinging back to a host-side `infernix-demo serve`
  process
- on `apple-silicon`, routed manual inference bridges from the clustered `infernix-demo` surface
  into the host-native `infernix service` daemon instead of remaining inside cluster-resident repo
  workloads
- publication metadata reports the Apple host-inference bridge explicitly and distinguishes it from
  the Linux cluster-daemon upstream modes
- route-oriented docs and validation stop accepting cluster-resident Apple service parity as the
  final Apple inference doctrine

### Validation

- `cluster up` deploys the demo app on the cluster for Apple and Linux substrates whenever
  `demo_ui` is enabled
- routed Apple integration and E2E flows keep one browser base URL while using the Apple
  host-inference bridge instead of in-cluster Apple service execution
- `infernix docs check` and route-oriented validation fail if the docs still describe direct host
  `infernix-demo serve` or cluster-resident Apple service parity as the final routed Apple
  contract

### Remaining Work

None.

---

## Sprint 3.7: Substrate-Stable Publication Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make edge-route publication, current `runtimeMode`-labeled status reporting, and demo-config
publication details line up so operators and browser clients keep one stable substrate-aware
entrypoint.

### Deliverables

- `cluster status` reports the active substrate through its current `runtimeMode` line together
  with publication details and edge routes
- the supported reconcile path writes `./.data/runtime/publication.json`
- `/api/publication` exposes the routed publication details consumed by the browser workbench
- the publication contract preserves the same browser entrypoint used by the cluster-resident path

### Validation

- `cluster status` reports its current `runtimeMode` line, demo-config publication details, and
  edge routes
- `GET /api/publication` returns the routed publication details consumed by the browser
- rebuilding for a different substrate changes publication details without changing route prefixes

### Remaining Work

None.

---

## Sprint 3.8: Canonical Route Registry and Data-Driven HTTPRoute Rendering [Done]

**Status**: Done
**Implementation**: `src/Infernix/Routes.hs`, `chart/templates/httproutes.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Models.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Collapse the route and publication contract to one Haskell-owned source of truth that drives the
rendered HTTPRoute set, publication metadata, and chart-facing route inputs.

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
- the runtime or chart route inventory is no longer duplicated across `src/Infernix/Models.hs`,
  `chart/templates/httproutes.yaml`, and generated Helm values
- route-oriented docs and route-aware validation consume registry-backed generated sections
  derived from that same route registry

### Validation

- `infernix kubectl get httproute -n platform` shows the expected route set in `Accepted` state
- `GET /api/publication` reports the exact route inventory produced by the registry
- `infernix test lint` fails if the data-driven HTTPRoute template or required route-aware docs
  structure disappears from the supported shape
- routed Harbor, MinIO, Pulsar, and demo probes continue to work through the shared listener

### Remaining Work

None.

## Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - Envoy Gateway installation, single listener, route-registry ownership, and no-auth demo-cluster posture
- `documents/engineering/object_storage.md` - repo-local object-store rules plus reserved MinIO path and routed access
- `documents/engineering/k8s_storage.md` - manual PV doctrine and PostgreSQL claim binding
- `documents/tools/minio.md` - MinIO deployment and routed surfaces
- `documents/tools/postgresql.md` - Percona operator and Patroni deployment rules
- `documents/tools/pulsar.md` - Pulsar deployment and routed surfaces
- `documents/tools/harbor.md` - Harbor deployment and routed portal or API split
- `documents/engineering/monitoring.md` - required if monitoring remains a supported first-class surface after route or service closure

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory and active-substrate catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup and host-inference bridge behavior

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when route prefixes, publication fields, or daemon-location rules change
