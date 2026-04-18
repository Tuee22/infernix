# Edge Routing

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Define the one-port edge routing contract for browser and host-consumed services.

## Route Inventory

- the published route inventory is `/`, `/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws`
- `/api/publication` is a stable routed metadata endpoint on that same edge host rather than a separately published portal prefix
- the supported Kind path serves those routes through a cluster-resident repo-owned Python edge proxy
- `/` routes to the cluster-resident web workload
- `/api` routes to the cluster-resident service workload by default and can be repointed to the Apple host bridge when `infernix service` runs host-native on the supported Apple path
- `/harbor`, `/minio/...`, and `/pulsar/...` route through dedicated cluster-resident gateway
  workloads that proxy the live chart-managed Harbor, MinIO, and Pulsar services
- `/api/publication` now reports API-upstream mode plus routed-upstream health and durable-backing-state details so the browser can surface whether `/api` is currently backed by the cluster service or the Apple host bridge

## Port Selection Rules

- `cluster up` tries `9090` first and increments by `1` until it finds an available port
- the chosen port is recorded under `./.data/runtime/edge-port.json`
- `cluster up` prints the chosen port during bring-up
- `cluster status` reports the active runtime mode together with the chosen port, the published
  route inventory, and the publication-state details that back `/api/publication`

## Cross-References

- [object_storage.md](object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [../tools/pulsar.md](../tools/pulsar.md)
