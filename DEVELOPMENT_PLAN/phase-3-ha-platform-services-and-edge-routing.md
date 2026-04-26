# Phase 3: HA Platform Services and Edge Routing

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, operator-managed PostgreSQL, and
> Pulsar deployments; the Haskell-implemented unified edge routing model that makes every portal
> reachable on one localhost port; the Haskell-implemented Harbor, MinIO, and Pulsar gateway
> workloads; and the demo HTTP surface served exclusively by the `infernix-demo` binary when the
> active `.dhall` `demo_ui` flag is on.

## Phase Status

Sprints 3.1 through 3.5 (HA MinIO, Patroni PostgreSQL, HA Pulsar, HA Harbor, and the unified edge
proxy), 3.6 (Demo HTTP Host and Apple Host Bridge), 3.7 (Mode-Stable Publication Contract), and
3.8 (Haskell-Implemented Portal Gateways) are now `Done`. The phase remains `Active` because the
later production-runtime work in Phase 4 is still open, but the supported edge, gateway, demo
workload, and host-bridge routing contracts are now Haskell-owned and validated.

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

The repository serves `/`, `/api`, and `/api/publication` from the supported simulated Kind and
Helm substrate through Haskell-owned edge and demo surfaces: `src/Infernix/Edge.hs` owns the
shared routed proxy, `src/Infernix/Demo/Api.hs` owns the demo HTTP API, and `src/Infernix/Gateway.hs`
owns the Harbor, MinIO, and Pulsar gateway workloads. On the Apple host-native control-plane path,
`infernix-demo serve` can repoint `/api` through a host daemon bridge without changing the browser
entrypoint, while publication metadata continues to originate from
`./.data/runtime/publication.json` and reports API-upstream mode plus routed upstream health and
backing-state details. The Haskell edge and gateway entrypoints are covered both indirectly
through the current simulated-cluster integration path and directly through process-level proxy
tests against mock upstream services. The Apple host-native validation lane continues to exercise
Harbor-first image publication, MinIO-backed durable artifacts, Pulsar-backed request or result
transport, and HA recovery for all three platform services on the Kind and Helm substrate. Because
Pulsar is first enabled during the final Harbor-backed Helm phase, the supported chart values
force the upstream Pulsar initialization jobs there so clean and repeat `cluster up` runs still
create the required BookKeeper and cluster metadata before the proxy and broker readiness gates
apply. The same supported cluster path now installs the Percona PostgreSQL operator through Helm,
disables Harbor's chart-managed standalone database path, keeps later PostgreSQL-backed services on
that same operator-managed Patroni contract even when their upstream charts can self-deploy
PostgreSQL, reconciles Harbor's Patroni PVCs through `infernix-manual`, repairs Harbor database
migration state through the current Patroni primary, and keeps repeat `cluster down` plus
`cluster up` cycles bound to the same manually managed PostgreSQL host paths.

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

## Sprint 3.5: Unified Edge Proxy and Localhost Port Allocation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `chart/templates/edge-configmap.yaml`, `chart/templates/deployment-edge.yaml`, `infernix.cabal`, `src/Infernix/Edge.hs`, `src/Infernix/HttpProxy.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`

### Objective

Route every browser-visible portal and host-consumed service path through one chosen localhost port.

### Deliverables

- the CLI tries `9090` first and increments by 1 until it finds an available localhost port during cluster startup
- the chosen port is recorded under `./.data/runtime/edge-port.json`
- `cluster up` prints the chosen port to the operator during bring-up
- the edge proxy exposes stable route prefixes:

| Route | Purpose |
|-------|---------|
| `/` | browser workbench |
| `/api` | demo API |
| `/harbor` | Harbor portal |
| `/minio/console` | MinIO console |
| `/minio/s3` | MinIO S3 API |
| `/pulsar/admin` | Pulsar admin HTTP surface |
| `/pulsar/ws` | Pulsar WebSocket surface |

- `/api/publication` remains a stable routed metadata endpoint sourced from
  `./.data/runtime/publication.json` and exposed by the same routed edge proxy
- Apple host-native `infernix` uses the routed MinIO and Pulsar edge paths instead of separate host ports
- the routed contract remains stable regardless of whether the active runtime mode is Apple, Linux CPU, or Linux CUDA
- the edge proxy is implemented in Haskell as `src/Infernix/Edge.hs` (using `wai` plus
  `http-reverse-proxy` or equivalent), shipped in the same OCI image as the rest of the `infernix`
  binary, and run as the `infernix-edge` cluster workload via `infernix edge`

### Validation

- `infernix cluster status` prints the chosen port and the published route inventory
- if `9090` is free, `cluster up` uses `9090`; otherwise it reports the next open port it selected
- all browser portals load through the same localhost port
- `GET /api/publication` resolves through that same port and reports the current publication
  contract (when the demo surface is enabled)
- Apple host-native `infernix service` can reach MinIO and Pulsar through the edge routes on that port
- changing runtime modes does not change the documented route inventory or the `/api/publication` endpoint

### Remaining Work

None.

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

## Sprint 3.8: Haskell-Implemented Portal Gateways [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `src/Infernix/CLI.hs`, `src/Infernix/Gateway.hs`, `src/Infernix/HttpProxy.hs`, `chart/templates/workloads-platform-portals.yaml`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Replace the Python `tools/portal_surface.py` gateway implementation with Haskell-owned gateway
logic under `src/Infernix/Gateway.hs`, deployed via the same OCI image as `infernix`
with `infernix gateway harbor|minio|pulsar` as entrypoint. Preserve the same routes, the same
auth flows, and the same edge-routed surfaces.

### Deliverables

- `src/Infernix/Gateway.hs` exposes the routed Harbor portal and API surface by proxying
  the chart-managed Harbor service through the shared edge; deployed as cluster workload
  `infernix-harbor-gateway` via `chart/templates/workloads-platform-portals.yaml` with entrypoint
  `infernix gateway harbor`
- `src/Infernix/Gateway.hs` exposes the routed MinIO console and S3 API by proxying the
  chart-managed MinIO service through the shared edge; deployed as cluster workload
  `infernix-minio-gateway` with entrypoint `infernix gateway minio`
- `src/Infernix/Gateway.hs` exposes the routed Pulsar admin and WebSocket surfaces by
  proxying the chart-managed Pulsar service through the shared edge; deployed as cluster workload
  `infernix-pulsar-gateway` with entrypoint `infernix gateway pulsar`
- `tools/portal_surface.py` is removed; the chart template now invokes the Haskell-owned
  `infernix gateway harbor|minio|pulsar` entrypoints directly
- the Haskell gateway implementations reuse shared proxy or credential-handling code in
  `infernix-lib` rather than preserving the old Python `pulsar` and `minio` SDK call shapes

### Validation

- existing integration tests for portal flows pass against the Haskell gateway implementations
  without relaxing assertions
- `infernix kubectl get pods -n platform` shows `infernix-harbor-gateway`,
  `infernix-minio-gateway`, and `infernix-pulsar-gateway` workloads using the same OCI image as
  `infernix-service` and `infernix-edge`
- `tools/portal_surface.py` no longer exists in the worktree on the supported path
- routed `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` continue to
  resolve through the shared edge port

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - single-port routing and upstream selection
- `documents/engineering/k8s_storage.md` - manual PV doctrine and PostgreSQL claim binding
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/tools/minio.md` - MinIO deployment and route surfaces
- `documents/tools/postgresql.md` - Percona operator and Patroni PostgreSQL deployment rules
- `documents/tools/pulsar.md` - Pulsar deployment and route surfaces
- `documents/tools/harbor.md` - Harbor deployment and image-registry rules

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory and active-mode catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup and bridge behavior

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when route prefixes, active-mode publication, or daemon-location rules change
