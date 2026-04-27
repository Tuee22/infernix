# Web Portal Surface

**Status**: Authoritative source
**Referenced by**: [api_surface.md](api_surface.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the browser-visible routes and PureScript demo workbench behavior exposed
> through the published routed surface.

## Scope

The `/` and demo-related routes (`/`, `/api*`, `/objects/<key>`) are demo-only and absent from
production deployments. Production deployments leave the active `.dhall` `demo_ui` flag off, the
cluster has no `infernix-demo` workload, and the demo routes are not bound. The Harbor, MinIO,
and Pulsar portal routes remain unconditional in every supported deployment.

## Routes

Demo-only (present when `.dhall` `demo_ui = True`):

- `/` loads the PureScript manual inference workbench served by `infernix-demo`
- `/objects/:objectRef` loads large-output payloads referenced by the workbench
- `/api`, `/api/publication`, and `/api/cache` are the demo HTTP API endpoints; see
  [api_surface.md](api_surface.md)

Operator portals (always present):

- `/harbor` loads the Harbor portal surface
- `/minio/console` loads the MinIO console surface
- `/minio/s3` exposes the routed MinIO S3 API surface
- `/pulsar/admin` loads the Pulsar admin surface
- `/pulsar/ws` exposes the routed Pulsar WebSocket surface and preserves Pulsar's `/ws/v2/...`
  upstream context root

On the real Kind path those routes are published by `Gateway/infernix-edge`,
`EnvoyProxy/infernix-edge`, and the repo-owned HTTPRoute set. On the simulated substrate, the same
prefixes return compatibility HTML or JSON so the route inventory and rewrite behavior remain
testable.

## Workbench Behavior

- the workbench is implemented in PureScript, built into `web/dist/` by
  `npm --prefix web run build`, and served by the `infernix-demo` Haskell binary
- frontend contract modules are emitted into `web/src/Generated/` by
  `infernix internal generate-purs-contracts`
- the visible catalog comes from the generated demo catalog for the active runtime mode
- the generated catalog is published by `cluster up` as `infernix-demo-<mode>.dhall`, mounted into
  the `infernix-demo` workload through `ConfigMap/infernix-demo-config`, and mirrored under the
  active build root for inspection
- the browser workbench renders the generated catalog exactly rather than maintaining a separate
  browser-only subset
- the routed Playwright contract cross-checks `/api/models` against the serialized generated demo
  config returned by `GET /api/demo-config` and separately validates publication details from
  `/api/publication`
- the host-native validation path launches routed Playwright from the host install; the Linux path
  launches it from the active substrate image when the platform toolchain is available
- the workbench surfaces the active runtime mode, control-plane context, daemon location, catalog
  source, chosen edge port, demo-config path, and routed publication inventory through
  `/api/publication`
- the user can browse any generated model entry, inspect its selected engine and request shape,
  and submit a manual inference request through the demo `/api`
- manual inference requests execute through the same Haskell worker dispatch used by the
  production daemon, including shared Python adapters under `python/adapters/` when the bound
  engine is Python-native
- large outputs surface as object-reference results with browser-visible links that resolve
  through `GET /objects/:objectRef`
- switching runtime modes changes the generated catalog and selected engine bindings without
  changing the browser route structure

## Cross-References

- [api_surface.md](api_surface.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
