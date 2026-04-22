# Web Portal Surface

**Status**: Authoritative source
**Referenced by**: [api_surface.md](api_surface.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the browser-visible routes and workbench behavior exposed through the edge proxy.

## Routes

- `/` loads the manual inference workbench
- `/objects/:objectRef` loads large-output payloads referenced by the workbench
- `/harbor` loads the Harbor portal surface
- `/minio/console` loads the MinIO console surface
- `/minio/s3` exposes the routed MinIO S3 API surface
- `/pulsar/admin` loads the Pulsar admin surface
- `/pulsar/ws` exposes the routed Pulsar WebSocket surface

## Workbench Behavior

- the visible catalog comes from the generated demo catalog for the active runtime mode
- the generated catalog is published by `cluster up` as `infernix-demo-<mode>.dhall`, mounted into the cluster-resident workloads through `ConfigMap/infernix-demo-config`, and mirrored under the active build root for inspection
- the browser workbench renders the generated catalog exactly rather than maintaining a separate browser-only subset
- the routed Playwright contract cross-checks `/api/models` against the serialized generated demo config returned by `GET /api/demo-config`, while separately validating publication details from `/api/publication` through the real routed cluster edge
- the host-native and outer-container validation paths launch that routed Playwright contract from the same web image that serves `/`, and the host-native final-substrate lane serves `/` from the Harbor-published web runtime image across `apple-silicon`, `linux-cpu`, and `linux-cuda`
- on the outer-container validation path, that web image reaches the routed surface over the
  private Docker `kind` network by targeting the control-plane node on port `30090`, while the
  host-published edge port remains loopback-only on `127.0.0.1`
- the workbench surfaces the active runtime mode, control-plane context, daemon location, catalog source, chosen edge port, demo-config path, API-upstream mode, and routed publication inventory through `/api/publication`
- the workbench also renders routed-upstream health and durable-backing-state details for the Harbor, MinIO, and Pulsar route surfaces
- the user can browse any generated model entry, inspect its selected engine and request shape, and submit a manual inference request through `/api`
- the workbench treats routed catalog or publication failures as unavailable live state rather than synthesizing a browser-only fallback catalog or publication summary
- manual inference requests execute through process-isolated engine-worker adapters backed by durable runtime artifact bundles and direct-upstream source-artifact manifests
- the workbench renders family-aware request guidance, artifact metadata, submit labels, and result framing without introducing a browser-only catalog
- large outputs surface as object-reference results with browser-visible links that resolve through `GET /objects/:objectRef`
- switching runtime modes changes the generated catalog and selected engine bindings without changing the browser route structure

## Cross-References

- [api_surface.md](api_surface.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
