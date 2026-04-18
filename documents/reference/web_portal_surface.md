# Web Portal Surface

**Status**: Authoritative source
**Referenced by**: [api_surface.md](api_surface.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the browser-visible routes and workbench behavior exposed through the edge proxy.

## Routes

- `/` loads the manual inference workbench
- `/harbor` loads the Harbor portal surface
- `/minio/console` loads the MinIO console surface
- `/minio/s3` exposes the routed MinIO S3 API surface
- `/pulsar/admin` loads the Pulsar admin surface
- `/pulsar/ws` exposes the routed Pulsar WebSocket surface

## Workbench Behavior

- the visible catalog comes from the generated demo catalog for the active runtime mode
- the generated catalog is published by `cluster up` as `infernix-demo-<mode>.dhall`, mounted into the cluster-resident workloads through `ConfigMap/infernix-demo-config`, and mirrored under the active build root for inspection
- the browser workbench renders the generated catalog exactly rather than maintaining a separate browser-only subset
- the current routed Playwright contract cross-checks `/api/models` against the serialized generated catalog file reported through `/api/publication` while driving the real routed cluster edge
- the current host-native and outer-container validation paths launch that routed Playwright contract from the same web image that serves `/`, and the host-native final-substrate lane now serves `/` from the Harbor-published web runtime image across `apple-silicon`, `linux-cpu`, and `linux-cuda`
- the workbench surfaces the current runtime mode, control-plane context, daemon location, catalog source, chosen edge port, demo-config path, API-upstream mode, and routed publication inventory through `/api/publication`
- the workbench also renders routed-upstream health and durable-backing-state details for the current Harbor, MinIO, and Pulsar route surfaces
- the user can browse any generated model entry, inspect its selected engine and request shape, and submit a manual inference request through `/api`
- the workbench renders family-aware request guidance, artifact metadata, submit labels, and result framing without introducing a browser-only catalog
- large outputs surface as object-reference results with browser-visible links
- switching runtime modes changes the generated catalog and selected engine bindings without changing the browser route structure

## Cross-References

- [api_surface.md](api_surface.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
