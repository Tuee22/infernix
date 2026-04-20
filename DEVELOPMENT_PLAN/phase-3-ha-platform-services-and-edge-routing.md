# Phase 3: HA Platform Services and Edge Routing

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, and Pulsar deployments plus the
> unified edge routing model that makes every portal reachable on one localhost port and keeps the
> browser contract stable across runtime modes.

## HA Reconcile Surface

- `infernix cluster up` is the declarative and idempotent entrypoint for the mandatory local HA topology.
- The supported cluster path always deploys the local HA topology; there is no optional non-HA mode.
- No service-specific HA bootstrap command family exists outside the supported cluster reconcile surface.

## Mode-Stable Route Contract

This phase owns the rule that runtime-mode changes do not fork the browser entrypoint.

- `/`, `/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` remain the published edge-route inventory
- `/api/publication` remains a stable routed metadata endpoint layered on top of the `/api` surface
- Apple host-native runtime mode switching never changes the browser base URL
- Linux CPU and Linux CUDA runtime modes still publish the same browser and API route inventory
- `cluster status` ultimately reports the active runtime mode alongside the routed surfaces that expose it

## Current Repo Assessment

The repository serves `/`, `/api`, and `/api/publication` from the real Kind and Helm substrate
through a cluster-resident repo-owned Python edge proxy, web workload, and service pod. On the
Apple host-native control-plane path, `infernix service` can repoint `/api` through a host daemon
bridge without changing the browser entrypoint, while publication metadata continues to originate
from `./.data/runtime/publication.json` and reports API-upstream mode plus routed upstream health
and backing-state details. Harbor, MinIO, and Pulsar route through cluster-resident gateway
workloads that target the live chart-managed Harbor, MinIO, and Pulsar services. The Apple
host-native validation lane exercises Harbor-first image publication, MinIO-backed durable
artifacts, Pulsar-backed request or result transport, and HA recovery for all three platform
services on the Kind and Helm substrate. Because Pulsar is first enabled during the final
Harbor-backed Helm phase, the supported chart values force the upstream Pulsar initialization jobs
there so clean and repeat `cluster up` runs still create the required BookKeeper and cluster
metadata before the proxy and broker readiness gates apply.

## Sprint 3.1: HA MinIO Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `chart/templates/workloads-platform-portals.yaml`, `src/Infernix/Cluster.hs`, `tools/portal_surface.py`, `tools/runtime_backend.py`, `test/integration/Spec.hs`
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

## Sprint 3.2: HA Pulsar Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `chart/templates/workloads-platform-portals.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Storage.hs`, `tools/portal_surface.py`, `tools/runtime_backend.py`, `test/integration/Spec.hs`
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

## Sprint 3.3: HA Harbor Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `tools/publish_chart_images.py`, `tools/portal_surface.py`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/tools/harbor.md`

### Objective

Provide the mandatory local HA image registry and browser portal for cluster images.

### Deliverables

- Harbor deploys through its Helm chart
- Harbor stores image blobs in MinIO and uses chart-owned persistence for its remaining durable state
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

## Sprint 3.4: Unified Edge Proxy and Localhost Port Allocation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `chart/templates/edge-configmap.yaml`, `chart/templates/workloads-platform-portals.yaml`, `tools/edge_proxy.py`, `tools/portal_surface.py`, `tools/runtime_backend.py`, `test/integration/Spec.hs`
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
| `/api` | service API |
| `/harbor` | Harbor portal |
| `/minio/console` | MinIO console |
| `/minio/s3` | MinIO S3 API |
| `/pulsar/admin` | Pulsar admin HTTP surface |
| `/pulsar/ws` | Pulsar WebSocket surface |

- `/api/publication` remains a stable routed metadata endpoint sourced from
  `./.data/runtime/publication.json` and exposed by the same routed edge proxy
- Apple host-native `infernix` uses the routed MinIO and Pulsar edge paths instead of separate host ports
- the routed contract remains stable regardless of whether the active runtime mode is Apple, Linux CPU, or Linux CUDA

### Validation

- `infernix cluster status` prints the chosen port and the published route inventory
- if `9090` is free, `cluster up` uses `9090`; otherwise it reports the next open port it selected
- all browser portals load through the same localhost port
- `GET /api/publication` resolves through that same port and reports the current publication contract
- Apple host-native `infernix service` can reach MinIO and Pulsar through the edge routes on that port
- changing runtime modes does not change the documented route inventory or the `/api/publication` endpoint

### Remaining Work

None.

---

## Sprint 3.5: Cluster-Resident Webapp Service and Apple Host Bridge [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Service.hs`, `tools/service_server.py`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Keep the browser entrypoint stable across the cluster-resident webapp service and the Apple host
bridge split.

### Deliverables

- the browser workbench loads from `/` through the cluster-resident webapp service on the supported path
- the cluster-resident webapp service, built separately from `infernix`, deploys in the Kind
  cluster through the repo-owned Helm path
- `/api` points at the cluster-resident Haskell service when the service runs in cluster mode
- `/api` points at a host bridge when the Haskell daemon runs host-native on Apple Silicon
- the browser continues to use the same edge route in both cases
- the webapp consumes the active runtime mode's generated demo catalog rather than a hand-maintained
  UI-only allowlist

### Validation

- the browser workbench loads from the routed cluster-resident surface on the supported Apple path
- a manual inference request from the UI reaches the active daemon location without the browser changing its base URL
- switching between host-daemon and cluster-daemon modes does not require changing the documented browser entrypoint
- switching runtime modes changes the active catalog content without changing the browser route structure

### Remaining Work

None.

---

## Sprint 3.6: Mode-Stable Publication Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Service.hs`, `tools/service_server.py`, `web/src/app.js`, `web/src/workbench.js`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make edge-route publication, runtime-mode reporting, and demo-config publication details line up so
operators and browser clients keep one stable mode-aware entrypoint.

### Deliverables

- `cluster status` reports the active runtime mode and active demo-config publication details alongside edge routes
- route publication keeps the same browser-visible prefix inventory regardless of the active
  runtime mode or whether `/api` resolves through the Apple host bridge or the cluster-resident
  service
- the supported reconcile path writes `./.data/runtime/publication.json` and exposes the same
  publication details through `/api/publication`
- the service startup path reports control-plane context, daemon location, and catalog source in
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
- moving `/api` between the Apple host bridge and the cluster-resident service does not change the
  published browser entrypoint

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - single-port routing and upstream selection
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/tools/minio.md` - MinIO deployment and route surfaces
- `documents/tools/pulsar.md` - Pulsar deployment and route surfaces
- `documents/tools/harbor.md` - Harbor deployment and image-registry rules

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory and active-mode catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup and bridge behavior

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when route prefixes, active-mode publication, or daemon-location rules change
