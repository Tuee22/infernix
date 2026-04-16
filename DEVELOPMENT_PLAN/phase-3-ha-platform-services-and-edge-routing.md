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

- `/`, `/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` remain stable route prefixes
- Apple host-native runtime mode switching never changes the browser base URL
- Linux CPU and Linux CUDA runtime modes still publish the same browser and API route inventory
- `cluster status` ultimately reports the active runtime mode alongside the routed surfaces that expose it

## Sprint 3.1: HA MinIO Deployment [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.5`, `2.1-2.6`
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

- close the real HA MinIO deployment path
- validate routed MinIO behavior on the final Kind and Helm substrate

---

## Sprint 3.2: HA Pulsar Deployment [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.5`, `2.1-2.6`
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

### Validation

- `infernix cluster up` produces a healthy Pulsar deployment with the expected three-replica chart components
- Pulsar PVCs bind through `infernix-manual`
- the rendered Pulsar manifests show the required replica counts and no hard pod anti-affinity that
  would block local Kind scheduling
- topic or schema inspection shows the supported inference payload topics are using protobuf schema
  registration rather than opaque bytes
- `curl http://127.0.0.1:<port>/pulsar/admin/` reaches the routed Pulsar admin surface

### Remaining Work

- close the real HA Pulsar deployment path
- validate host-routed and cluster-local Pulsar access on the final substrate
- wire the final `.proto` payload set through `proto-lens` generation and Pulsar schema registration

---

## Sprint 3.3: HA Harbor Deployment [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.5`, `2.1-2.6`
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
- Harbor is the only supported workload allowed to bootstrap directly from Docker Hub or another upstream registry

### Validation

- `infernix cluster up` produces a healthy Harbor release with the expected replicated application-plane workloads
- `curl http://127.0.0.1:<port>/harbor/` reaches the Harbor portal through the edge
- the rendered Harbor manifests show the required replica counts and no hard pod anti-affinity that
  would block local Kind scheduling
- deleting a single Harbor application pod on the supported topology does not permanently break
  portal access or image pulls

### Remaining Work

- close the real HA Harbor deployment path
- validate Harbor-backed image pulls and browser access on the final substrate

---

## Sprint 3.4: Unified Edge Proxy and Localhost Port Allocation [Active]

**Status**: Active
**Implementation**: `src/Infernix/Cluster.hs`, `tools/service_server.py`
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
| `/` | PureScript UI |
| `/api` | service API |
| `/harbor` | Harbor portal |
| `/minio/console` | MinIO console |
| `/minio/s3` | MinIO S3 API |
| `/pulsar/admin` | Pulsar admin HTTP |
| `/pulsar/ws` | Pulsar WebSocket path |

- Apple host-native `infernix` uses the routed MinIO and Pulsar edge paths instead of separate host ports
- the routed contract remains stable regardless of whether the active runtime mode is Apple, Linux CPU, or Linux CUDA

### Validation

- `infernix cluster status` prints the chosen port and every supported route prefix
- if `9090` is free, `cluster up` uses `9090`; otherwise it reports the next open port it selected
- all browser portals load through the same localhost port
- Apple host-native `infernix service` can reach MinIO and Pulsar through the edge routes on that port
- changing runtime modes does not change the documented route inventory

### Remaining Work

- split the current single-process compatibility surface into a dedicated edge proxy plus upstream services
- validate route behavior against real Harbor, MinIO, and Pulsar workloads

---

## Sprint 3.5: Cluster-Resident Webapp Service and Apple Host Bridge [Active]

**Status**: Active
**Implementation**: `web/src/`, `web/build.mjs`, `tools/service_server.py`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Keep the webapp service cluster-resident while preserving a stable browser API route when the
daemon runs on the host.

### Deliverables

- the PureScript webapp service, built as a separate binary from `infernix`, always deploys in the Kind cluster
- `/api` points at the cluster-resident Haskell service when the service runs in cluster mode
- `/api` points at a host bridge when the Haskell daemon runs host-native on Apple Silicon
- the browser continues to use the same edge route in both cases
- the webapp consumes the active runtime mode's generated demo catalog rather than a hand-maintained
  UI-only allowlist

### Validation

- the UI loads from the cluster on both Apple and Linux-supported development paths
- a manual inference request from the UI reaches the active daemon location without the browser changing its base URL
- switching between host-daemon and cluster-daemon modes does not require changing the documented browser entrypoint
- switching runtime modes changes the active catalog content without changing the browser route structure

### Remaining Work

- separate the browser host from the API process so the web surface is not served from the same local runtime
- reintroduce the host-bridge behavior once a real cluster-resident service path exists
- wire the UI to the final generated mode-specific demo catalog

---

## Sprint 3.6: Mode-Stable Publication Contract [Blocked]

**Status**: Blocked
**Blocked by**: `2.6`, `3.5`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make edge-route publication, runtime-mode reporting, and demo-config publication details line up so
operators and browser clients keep one stable mode-aware entrypoint.

### Deliverables

- `cluster status` reports the active runtime mode and active demo-config publication details alongside edge routes
- route publication keeps the same browser-visible prefix inventory regardless of the active
  runtime mode or whether `/api` resolves through the Apple host bridge or the cluster-resident
  service
- Apple host bridge behavior preserves the same browser entrypoint and published route inventory
  used by the cluster-resident path

### Validation

- `cluster status` reports the active runtime mode, demo-config publication details, and edge
  routes from the current reconcile state
- switching runtime modes changes publication details without changing route prefixes or the
  documented browser base URL
- moving `/api` between the Apple host bridge and the cluster-resident service does not change the
  published browser entrypoint

### Remaining Work

- surface the same publication details inside the service and webapp consumers once Sprints `4.6`
  and `5.6` land
- align downstream validation and UI behavior with this mode-stable publication contract

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
