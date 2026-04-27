# Phase 3: HA Platform Services and Edge Routing

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, operator-managed PostgreSQL, and
> Pulsar deployments; the Envoy Gateway API installation that owns all browser-visible and
> host-consumed routing on one localhost port; the HTTPRoute manifest set that makes Harbor,
> MinIO, Pulsar, and the optional demo surface reachable through that single Gateway; and the
> demo HTTP surface served exclusively by the `infernix-demo` binary when the active `.dhall`
> `demo_ui` flag is on.

## Phase Status

Sprints 3.1 (HA MinIO), 3.2 (Patroni PostgreSQL), 3.3 (HA Pulsar), 3.4 (HA Harbor), 3.6 (Demo
HTTP Host and Apple Host Bridge), and 3.7 (Mode-Stable Publication Contract) are `Done`. Sprints
3.5 (Envoy Gateway API installation and localhost listener) and 3.8 (Mode-Stable Route Inventory
via HTTPRoute manifests) are `Active`: the worktree now carries the Gateway API chart dependency,
the `GatewayClass` plus `Gateway` manifests, the HTTPRoute set, and rendered-chart route discovery
for publication state, while the legacy Haskell routing modules and templates are deleted from
the worktree. The remaining work is real-cluster Gateway or HTTPRoute acceptance and final
tracked-index cleanup for the removed legacy files.

## HA Reconcile Surface

- `infernix cluster up` is the declarative and idempotent entrypoint for the mandatory local HA topology.
- The supported cluster path always deploys the local HA topology; there is no optional non-HA mode.
- No service-specific HA bootstrap command family exists outside the supported cluster reconcile surface.

## PostgreSQL Doctrine

- Every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes operator.
- A service may use a dedicated PostgreSQL cluster, but it still uses the Percona plus Patroni model rather than a chart-managed standalone PostgreSQL deployment.
- Services or add-ons that can self-deploy PostgreSQL, such as Grafana or similar charted workloads, disable that embedded PostgreSQL path and point at an operator-managed cluster instead.
- PostgreSQL claims use `infernix-manual` and explicit PV binding from Phase 2.
- This doctrine remains mandatory for every later phase and add-on; later work does not reintroduce chart-managed standalone PostgreSQL.
- On a pristine cluster, Harbor stays the first deployed service; only Harbor and Harbor-required backend services such as MinIO and PostgreSQL may pull from public container repositories before Harbor is ready, and every later non-Harbor workload pulls from Harbor.

## Mode-Stable Route Contract

This phase owns the rule that runtime-mode changes do not fork the browser entrypoint.

- `/`, `/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` remain the published edge-route inventory
- `/api/publication` remains a stable routed metadata endpoint layered on top of the `/api` surface
- Apple host-native runtime mode switching never changes the browser base URL
- Linux CPU and Linux CUDA runtime modes still publish the same browser and API route inventory
- `cluster status` ultimately reports the active runtime mode alongside the routed surfaces that expose it

## Current Repo Assessment

The supported cluster path runs the HA platform services (Harbor, MinIO, operator-managed
Patroni PostgreSQL, Pulsar) and the demo HTTP host (`infernix-demo`, gated by the active `.dhall`
`demo_ui` flag) on the final Kind and Helm substrate. The demo HTTP surface is served by
`src/Infernix/Demo/Api.hs`, and on the Apple host-native control-plane path `infernix-demo serve`
can repoint `/api` through a host daemon bridge without changing the browser entrypoint;
publication metadata originates from `./.data/runtime/publication.json` and reports API-upstream
mode plus routed upstream health and backing-state details. Because Pulsar is first enabled
during the final Harbor-backed Helm phase, the supported chart values force the upstream Pulsar
initialization jobs there so clean and repeat `cluster up` runs still create the required
BookKeeper and cluster metadata before the proxy and broker readiness gates apply. The same
supported cluster path installs the Percona PostgreSQL operator through Helm, disables Harbor's
chart-managed standalone database path, keeps later PostgreSQL-backed services on that same
operator-managed Patroni contract even when their upstream charts can self-deploy PostgreSQL,
reconciles Harbor's Patroni PVCs through `infernix-manual`, repairs Harbor database migration
state through the current Patroni primary, and keeps repeat `cluster down` plus `cluster up`
cycles bound to the same manually managed PostgreSQL host paths.

Edge routing and per-backend portal exposure now land through Envoy Gateway API in the worktree:
`chart/Chart.yaml` depends on Envoy Gateway, `chart/templates/gatewayclass.yaml` and
`chart/templates/gateway.yaml` publish the shared listener, and `chart/templates/httproutes/`
contains the public route inventory. The legacy Haskell routing modules and legacy edge or
gateway templates are deleted from the worktree, but `src/Infernix/Cluster.hs` and
`src/Infernix/Models.hs` still duplicate the route inventory in code and the final cluster
acceptance of the Gateway resources has not yet been revalidated on the current host.

## Sprint 3.1: HA MinIO Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `chart/templates/workloads-platform-portals.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Gateway.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/object_storage.md`, `documents/tools/minio.md`

### Objective

Make MinIO the durable object store for protobuf runtime manifests, artifacts, large outputs, and
Harbor image blobs.

### Deliverables

- MinIO always deploys as a four-node distributed cluster with manual PV backing
- repo-owned Helm values suppress hard pod anti-affinity and equivalent hard scheduling constraints
  so the four MinIO replicas can schedule on local Kind
- MinIO console and S3 API are both exposed through edge routes
- runtime manifests stored in MinIO serialize from repo-owned `.proto` schemas rather than ad hoc
  JSON or handwritten binary formats
- repo-owned services treat MinIO as the durable artifact source of truth

### Validation

- `infernix cluster up` creates a healthy four-node distributed MinIO deployment
- `infernix kubectl get pvc -n <namespace>` shows MinIO claims bound via `infernix-manual`
- the rendered MinIO manifests show four replicas and no hard pod anti-affinity that would block
  local Kind scheduling
- `curl http://127.0.0.1:<port>/minio/console/` and `curl http://127.0.0.1:<port>/minio/s3/` both reach the expected edge paths

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

- the supported cluster path installs the Percona Kubernetes operator through the repo-owned Helm workflow
- every in-cluster PostgreSQL dependency, including Harbor and future service-specific databases, uses a Patroni cluster reconciled by that operator
- services or add-ons that can self-deploy PostgreSQL disable that chart-managed PostgreSQL path and target an operator-managed cluster instead
- operator-managed PostgreSQL claims use `storageClassName: infernix-manual`, rely on manually reconciled PVs under `./.data/`, and bind deterministically to named claims
- Harbor-first bootstrap on a pristine cluster deploys Harbor first and allows only Harbor plus its required backend services, including MinIO and PostgreSQL, to pull from public container repositories before Harbor becomes pull-ready
- once Harbor is ready, every remaining non-Harbor workload, including later PostgreSQL-backed services, pulls only from Harbor-backed image references

### Validation

- `infernix cluster up` produces a ready Percona operator rollout and ready Patroni members for Harbor's PostgreSQL backend
- `infernix kubectl get pvc -A` shows operator-managed PostgreSQL claims bound through `infernix-manual`
- rendered Helm values and service configuration disable embedded standalone PostgreSQL deployments for any service or add-on that can otherwise self-provision one
- repeat `cluster down` plus `cluster up` cycles rebind PostgreSQL claims to the same manually managed PVs without storage repair

### Remaining Work

None.

---

## Sprint 3.3: HA Pulsar Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `chart/templates/workloads-platform-portals.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Gateway.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/tools/pulsar.md`

### Objective

Provide the durable event transport for inference requests, results, and service coordination.

### Deliverables

- Pulsar deploys through the Apache Helm chart
- Pulsar durable HA components use three replicas where the chosen chart exposes those HA surfaces
- repo-owned Helm values suppress hard pod anti-affinity and equivalent hard scheduling constraints
  so the replicated Pulsar workloads can schedule on local Kind
- durable Pulsar components use manual PVs under `./.data/`
- the edge exposes browser- and host-consumable Pulsar HTTP or WebSocket surfaces
- inference-request, result, and coordination payloads are defined by repo-owned `.proto` schemas
  and use Pulsar's built-in protobuf schema support on the topic side
- the Haskell runtime consumes those payloads through `proto-lens`-generated modules rather than
  handwritten encoders or decoders
- the service can use cluster-local Pulsar networking in cluster mode and edge-routed access in Apple host mode
- because Pulsar first becomes enabled in the final Harbor-backed Helm phase, the supported chart
  values force the upstream bookkeeper and cluster-initialization jobs there so BookKeeper or
  broker or proxy startup does not race missing metadata on clean or repeat `cluster up` runs

### Validation

- `infernix cluster up` produces a healthy Pulsar deployment with the expected three-replica chart components
- Pulsar PVCs bind through `infernix-manual`
- the rendered Pulsar manifests show the required replica counts and no hard pod anti-affinity that
  would block local Kind scheduling
- clean and repeat `infernix cluster up` runs show `infernix-infernix-pulsar-bookie-init` and
  `infernix-infernix-pulsar-pulsar-init` completing before the final Pulsar proxy or broker
  readiness gates are satisfied
- topic or schema inspection shows the supported inference payload topics are using protobuf schema
  registration rather than opaque bytes
- `curl http://127.0.0.1:<port>/pulsar/admin/` reaches the routed Pulsar admin surface

### Remaining Work

None.

---

## Sprint 3.4: HA Harbor Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/Gateway.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/tools/harbor.md`

### Objective

Provide the mandatory local HA image registry and browser portal for cluster images.

### Deliverables

- Harbor deploys through its Helm chart
- Harbor stores image blobs in MinIO and uses a dedicated operator-managed Patroni PostgreSQL
  cluster for its database backend while the remaining durable chart-owned state keeps the same
  manual PV doctrine
- Harbor application-plane workloads use three replicas where the chosen chart exposes those
  replicated surfaces
- repo-owned Helm values suppress hard pod anti-affinity and equivalent hard scheduling constraints
  so the replicated Harbor workloads can schedule on local Kind
- the Harbor portal is exposed through the edge proxy on the shared localhost port
- Harbor and only the storage or support services Harbor needs during bootstrap are the supported
  upstream-pull exception before the Harbor-backed pull contract from Phase 2 takes over

### Validation

- `infernix cluster up` produces a healthy Harbor release with the expected replicated application-plane workloads
- `curl http://127.0.0.1:<port>/harbor/` reaches the Harbor portal through the edge
- the rendered Harbor manifests show the required replica counts and no hard pod anti-affinity that
  would block local Kind scheduling
- deleting a single Harbor application pod on the supported topology does not permanently break
  portal access or image pulls

### Remaining Work

None.

---

## Sprint 3.5: Envoy Gateway API Installation and Localhost Listener [Active]

**Status**: Active
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/gatewayclass.yaml`, `chart/templates/gateway.yaml`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace the Haskell-implemented unified edge proxy with the Envoy Gateway API controller and a
single `Gateway` resource that owns one localhost-bound HTTP listener for every browser-visible
and host-consumed cluster surface. The demo cluster runs locally and has no auth, so the
Gateway listener publishes plain HTTP without any auth filter.

### Deliverables

- the Helm chart pulls the Envoy Gateway controller as a chart dependency (Harbor-mirrored once
  Harbor is ready, per the Harbor-first contract); the controller owns the Gateway API CRDs
- one `GatewayClass` named `infernix-gateway` and one `Gateway` named `infernix-edge` in the
  `platform` namespace; the `Gateway` defines a single HTTP listener bound to the chosen
  localhost port
- the CLI continues to try `9090` first and increments by 1 until it finds an available
  localhost port during `cluster up`; the chosen port is still recorded under
  `./.data/runtime/edge-port.json` and printed during bring-up; the chart Gateway listener uses
  that same port
- the Apple host-native control plane reaches Harbor, MinIO, Pulsar, and the demo HTTP host
  through that same Gateway listener; the prior Apple-side `infernix edge` daemon path is
  removed
- `src/Infernix/Edge.hs`, `src/Infernix/HttpProxy.hs`, `chart/templates/edge-configmap.yaml`,
  `chart/templates/deployment-edge.yaml`, and `chart/templates/service-edge.yaml` are deleted;
  the `infernix edge` CLI subcommand is removed from `src/Infernix/CLI.hs`
- the chart no longer renders any Haskell-implemented edge workload

### Validation

- `infernix cluster status` prints the chosen port and the published route inventory (the route
  set lands in Sprint 3.8)
- if `9090` is free, `cluster up` uses `9090`; otherwise it reports the next open port it
  selected
- `infernix kubectl get gatewayclass,gateway -n platform` shows the `infernix-gateway`
  GatewayClass and the `infernix-edge` Gateway in `Accepted` state with the chosen listener port
- `infernix lint chart` rejects any reintroduced reference to the deleted edge workload
  templates or the `infernix edge` subcommand
- `infernix test integration` proves the Envoy data-plane pod backing the `infernix-edge`
  Gateway is ready before the HTTPRoute manifests from Sprint 3.8 land

### Remaining Work

- the chart change and worktree deletions are landed, but this sprint still needs real-cluster
  validation that the Envoy Gateway controller and `Gateway/infernix-edge` reach `Accepted` on
  the supported Kind substrate
- the deleted legacy files still appear in `git ls-files` until user-owned index cleanup lands
  under Phase 1 Sprint 1.7

---

## Sprint 3.6: Demo HTTP Host (`infernix-demo`) and Apple Host Bridge [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Edge.hs`, `src/Infernix/Models.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Provide the demo HTTP API surface (and only the demo HTTP API surface) through the
`infernix-demo` Haskell binary, deployed as a separate cluster workload gated by the active
`.dhall` `demo_ui` flag. Keep the browser entrypoint stable when the demo surface is on, and keep
the cluster free of any HTTP API surface when the demo flag is off.

### Deliverables

- the `infernix-demo` Haskell binary is the single repo-owned source of the demo HTTP API surface
  (`/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/`); production `infernix service`
  binds no HTTP listener
- `infernix-demo` is built from the same `infernix-lib` Cabal library as `infernix`, ships in the
  same OCI image, and is invoked as `infernix-demo serve --dhall PATH --port N`
- the demo surface is implemented in `src/Infernix/Demo/Api.hs` (servant-based) and reuses the
  same Haskell typed runtime contracts owned by the production daemon
- the chart template `chart/templates/deployment-demo.yaml` deploys the `infernix-demo` workload
  conditionally on `.Values.demo.enabled` (driven from the active `.dhall` `demo_ui` flag); when
  disabled, no `infernix-demo` pod exists and the demo routes are absent from the edge
- the Apple host bridge becomes an `infernix-demo serve --dhall PATH` invocation against a
  host-side `.dhall`; the cluster-resident pod is the equivalent invocation inside the Kind
  cluster
- the demo UI catalog is consumed only from the active runtime mode's generated demo catalog (no
  UI-only allowlist)

### Validation

- the demo browser workbench loads from the routed `infernix-demo` workload on the supported Apple
  and outer-container paths when `demo_ui` is on
- a manual inference request from the demo UI reaches `infernix-demo`'s `/api/inference` handler
  and that handler dispatches into the same Haskell runtime contract that production `infernix
  service` consumes from Pulsar
- switching between host-native `infernix-demo serve` and the cluster-resident `infernix-demo`
  workload does not change the documented browser entrypoint
- switching runtime modes changes the active catalog content without changing the browser route
  structure
- when `demo_ui` is off in the active `.dhall`, no `infernix-demo` pod exists, the cluster has no
  HTTP API surface, and `/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/` are absent
  from the edge route inventory

### Remaining Work

None.

---

## Sprint 3.7: Mode-Stable Publication Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make edge-route publication, runtime-mode reporting, and demo-config publication details line up so
operators and browser clients keep one stable mode-aware entrypoint.

### Deliverables

- `cluster status` reports the active runtime mode and active demo-config publication details alongside edge routes
- route publication keeps the same browser-visible prefix inventory regardless of the active
  runtime mode or whether `/api` resolves through the Apple host bridge or the cluster-resident
  `infernix-demo` workload
- the supported reconcile path writes `./.data/runtime/publication.json` and exposes the same
  publication details through `/api/publication`
- the demo-surface startup path reports control-plane context, daemon location, and catalog source in
  host-versus-container terms rather than only by selected demo-config path
- the browser workbench renders the routed publication details alongside the active catalog
- Apple host bridge behavior preserves the same browser entrypoint and published route inventory
  used by the cluster-resident path

### Validation

- `cluster status` reports the active runtime mode, demo-config publication details, and edge
  routes from the current reconcile state
- `GET /api/publication` returns the same routed publication details consumed by the browser workbench
- Playwright coverage proves the browser renders the routed publication details without changing its base URL
- switching runtime modes changes publication details without changing route prefixes or the
  documented browser base URL
- moving `/api` between the Apple host bridge and the cluster-resident `infernix-demo` workload
  does not change the published browser entrypoint

### Remaining Work

None.

---

## Sprint 3.8: Mode-Stable Route Inventory via HTTPRoute Manifests [Active]

**Status**: Active
**Implementation**: `chart/templates/httproutes/`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Models.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Publish the stable browser-visible and host-consumed route inventory through Envoy Gateway API
HTTPRoute manifests attached to the `infernix-edge` Gateway from Sprint 3.5. The HTTPRoute set
is the canonical route contract; runtime-mode changes never alter it. The demo cluster is
local-only, so no auth filters are applied.

### Deliverables

- one HTTPRoute manifest per public path under `chart/templates/httproutes/`, each one
  attached as a child of `Gateway/infernix-edge`:

| Path prefix | Backend | Filter |
|-------------|---------|--------|
| `/` | `infernix-demo` Service | none; rendered only when `.Values.demo.enabled` is true |
| `/api` | `infernix-demo` Service | none; rendered only when `.Values.demo.enabled` is true |
| `/objects` | `infernix-demo` Service | none; rendered only when `.Values.demo.enabled` is true |
| `/harbor` | Harbor portal Service | `URLRewrite` strips `/harbor`; routes whose path starts `/harbor/api` go to the Harbor API Service instead of the portal |
| `/minio/console` | MinIO console Service | `URLRewrite` strips `/minio/console` |
| `/minio/s3` | MinIO S3 Service | `URLRewrite` strips `/minio/s3` |
| `/pulsar/admin` | Pulsar admin Service | `URLRewrite` strips `/pulsar/admin` |
| `/pulsar/ws` | Pulsar broker HTTP base Service | `URLRewrite` strips `/pulsar/ws` |

- when the active `.dhall` `demo_ui` flag is off, the HTTPRoutes for `/`, `/api`,
  `/api/publication`, `/api/cache`, and `/objects/` are absent from the rendered chart and the
  cluster has no demo API surface at all
- no `RequestHeaderModifier` injects credentials anywhere; the Harbor admin Basic-auth header
  the prior Haskell gateway stamped is dropped (demo cluster only)
- `infernix-publication-state` ConfigMap renders the `routes` list directly from the rendered
  HTTPRoute manifests on the supported cluster path; the route inventory is not duplicated in
  code there
- `chart/templates/workloads-platform-portals.yaml` loses its `infernix-harbor-gateway`,
  `infernix-minio-gateway`, and `infernix-pulsar-gateway` entries; `src/Infernix/Gateway.hs` and
  `src/Infernix/HttpProxy.hs` are deleted; the `infernix gateway harbor|minio|pulsar` CLI
  subcommands are removed from `src/Infernix/CLI.hs`
- runtime-mode changes (`apple-silicon`, `linux-cpu`, `linux-cuda`) never alter this HTTPRoute set

### Validation

- `infernix kubectl get httproute -n platform` shows the expected route set; each HTTPRoute is
  in `Accepted` state
- `curl http://127.0.0.1:<port>/harbor/`, `curl http://127.0.0.1:<port>/minio/console/`,
  `curl http://127.0.0.1:<port>/minio/s3/`, `curl http://127.0.0.1:<port>/pulsar/admin/`, and
  `curl http://127.0.0.1:<port>/pulsar/ws` all reach their backends through the shared port
- `curl http://127.0.0.1:<port>/` returns the demo workbench when `demo_ui` is on, and 404s
  when `demo_ui` is off
- `GET /api/publication` resolves through the same port and reports the routed route inventory
  exactly as the rendered HTTPRoute set defines it
- `infernix lint chart` rejects any reintroduced reference to the deleted gateway workload
  manifests or the `infernix gateway` subcommands

### Remaining Work

- the supported cluster path now derives publication-state routes from the rendered HTTPRoute set
  and annotates each route with `infernix.io/purpose`; the remaining work is real-cluster
  validation that those HTTPRoutes reach `Accepted` and route the shared localhost listener
  correctly on the supported Kind substrate
- the simulation fallback still seeds local route inventory from `src/Infernix/Models.hs` for
  non-cluster execution, so only the supported cluster path is de-duplicated today
- the deleted gateway files and templates still appear in `git ls-files` until user-owned index
  cleanup lands under Phase 1 Sprint 1.7

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - Envoy Gateway API installation, single-Gateway listener, HTTPRoute manifest set as the canonical route contract, and demo-cluster no-auth posture
- `documents/engineering/k8s_storage.md` - manual PV doctrine and PostgreSQL claim binding
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/tools/minio.md` - MinIO deployment and HTTPRoute surfaces
- `documents/tools/postgresql.md` - Percona operator and Patroni PostgreSQL deployment rules
- `documents/tools/pulsar.md` - Pulsar deployment and HTTPRoute surfaces
- `documents/tools/harbor.md` - Harbor deployment, image-registry rules, and HTTPRoute portal/API split

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible HTTPRoute inventory and active-mode catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup and bridge behavior

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when route prefixes, active-mode publication, or daemon-location rules change
