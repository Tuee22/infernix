# Edge Routing

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Define the one-port edge routing contract for browser and host-consumed services.

## Route Inventory

- the unconditional published route inventory is `/harbor`, `/minio/console`, `/minio/s3`,
  `/pulsar/admin`, and `/pulsar/ws`; these surfaces are operator portals and remain available in
  every supported deployment
- when the active `.dhall` `demo_ui` flag is on, the inventory adds `/`, `/api`, `/api/publication`,
  `/api/cache`, and `/objects/<key>`; these surfaces are demo-only and absent from production
  deployments
- the supported Kind path serves those routes through a cluster-resident Haskell edge proxy
  implemented in `src/Infernix/Edge.hs`, deployed via `chart/templates/deployment-edge.yaml` using
  the same `infernix` OCI image with entrypoint `infernix edge`
- when the demo surface is enabled, `/` and the demo `/api*`, `/objects/` routes target the
  `infernix-demo` workload (gated by `.Values.demo.enabled`); on the supported Apple host-native
  path, the same demo surface can be served by `infernix-demo serve --dhall PATH --port N` and
  reached through the same edge base URL via the host bridge
- `/harbor`, `/minio/...`, and `/pulsar/...` route through dedicated cluster-resident Haskell
  gateway workloads (`infernix-harbor-gateway`, `infernix-minio-gateway`,
  `infernix-pulsar-gateway`, all running `infernix gateway <kind>` from the same OCI image) that
  proxy the live chart-managed Harbor, MinIO, and Pulsar services
- `/api/publication` (demo-only) reports daemon location plus routed-upstream health and
  durable-backing-state details so the demo browser surface can surface whether the demo API is
  served from the `infernix-demo` cluster workload or the Apple host bridge

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
