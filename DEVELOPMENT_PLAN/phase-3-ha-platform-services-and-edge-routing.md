# Phase 3: HA Platform Services and Edge Routing

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, and Pulsar deployments plus the
> unified edge routing model that makes every portal reachable on one localhost port.

## HA Reconcile Surface

- `infernix cluster up` is the declarative and idempotent entrypoint for the mandatory local HA topology.
- The supported cluster path always deploys the local HA topology; there is no optional non-HA mode.
- No service-specific HA bootstrap command family exists outside the supported cluster reconcile surface.

## Sprint 3.1: HA MinIO Deployment [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.4`, `2.1-2.5`
**Docs to update**: `documents/engineering/object_storage.md`, `documents/tools/minio.md`

### Objective

Make MinIO the durable object store for manifests, artifacts, large outputs, and Harbor image blobs.

### Deliverables

- MinIO always deploys as a four-node distributed cluster with manual PV backing
- repo-owned Helm values suppress hard pod anti-affinity and equivalent hard scheduling constraints
  so the four MinIO replicas can schedule on local Kind
- MinIO console and S3 API are both exposed through edge routes
- repo-owned services treat MinIO as the durable artifact source of truth

### Validation

- `infernix cluster up` creates a healthy four-node distributed MinIO deployment
- `infernix kubectl get pvc -n <namespace>` shows MinIO claims bound via `infernix-manual`
- the rendered MinIO manifests show four replicas and no hard pod anti-affinity that would block
  local Kind scheduling
- `curl http://127.0.0.1:<port>/minio/console/` and `curl http://127.0.0.1:<port>/minio/s3/` both reach the expected edge paths

---

## Sprint 3.2: HA Pulsar Deployment [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.4`, `2.1-2.5`
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
- the service can use cluster-local Pulsar networking in cluster mode and edge-routed access in Apple host mode

### Validation

- `infernix cluster up` produces a healthy Pulsar deployment with the expected three-replica chart components
- Pulsar PVCs bind through `infernix-manual`
- the rendered Pulsar manifests show the required replica counts and no hard pod anti-affinity that
  would block local Kind scheduling
- `curl http://127.0.0.1:<port>/pulsar/admin/` reaches the routed Pulsar admin surface

---

## Sprint 3.3: HA Harbor Deployment [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.4`, `2.1-2.5`
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

---

## Sprint 3.4: Unified Edge Proxy and Localhost Port Allocation [Active]

**Status**: Active
**Implementation**: `src/Infernix/Cluster.hs`, `tools/service_server.py`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`

### Objective

Route every browser-visible portal and host-consumed service path through one chosen localhost port.

### Deliverables

- the CLI chooses an available localhost port during cluster startup
- the chosen port is recorded under `./.data/runtime/edge-port.json`
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

### Validation

- `infernix cluster status` prints the chosen port and every supported route prefix
- all browser portals load through the same localhost port
- Apple host-native `infernix service` can reach MinIO and Pulsar through the edge routes on that port

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

### Validation

- the UI loads from the cluster on both Apple and Linux-supported development paths
- a manual inference request from the UI reaches the active daemon location without the browser changing its base URL
- switching between host-daemon and cluster-daemon modes does not require changing the documented browser entrypoint

### Remaining Work

- separate the browser host from the API process so the web surface is not served from the same local runtime
- reintroduce the host-bridge behavior once a real cluster-resident service path exists

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - single-port routing and upstream selection
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/tools/minio.md` - MinIO deployment and route surfaces
- `documents/tools/pulsar.md` - Pulsar deployment and route surfaces
- `documents/tools/harbor.md` - Harbor deployment and image-registry rules

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup and bridge behavior

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when route prefixes or daemon-location rules change
