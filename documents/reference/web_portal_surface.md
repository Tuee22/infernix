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

The routed surface stays registry-driven. The `/api` prefix covers the demo endpoints documented in
[api_surface.md](api_surface.md), including `/api/publication` and `/api/cache`.

<!-- infernix:route-registry:web-portal:start -->
Demo-only prefixes:

| Routed prefix | Purpose | Notes |
|---------------|---------|-------|
| `/` | Demo workbench | PureScript manual inference workbench served by `infernix-demo`. |
| `/api` | Demo API | Covers `/api/publication`, `/api/cache`, `/api/models`, `/api/demo-config`, and `/api/inference`. |
| `/objects` | Demo object store | Serves `GET /objects/:objectRef` for large outputs. |

Always-published operator prefixes:

| Routed prefix | Purpose | Notes |
|---------------|---------|-------|
| `/harbor/api` | Harbor API | Rewrites to upstream `/api` before forwarding to `infernix-harbor-core:80`. |
| `/harbor` | Harbor portal | Rewrites to upstream `/` before forwarding to `infernix-harbor-portal:80`. |
| `/minio/console` | MinIO console | Rewrites to upstream `/` before forwarding to `infernix-minio-console:9090`. |
| `/minio/s3` | MinIO S3 API | Rewrites to upstream `/` before forwarding to `infernix-minio:9000`. |
| `/pulsar/admin` | Pulsar admin surface | Rewrites to upstream `/` before forwarding to `infernix-infernix-pulsar-proxy:80`. |
| `/pulsar/ws` | Pulsar websocket surface | Rewrites to upstream `/ws` before forwarding to `infernix-infernix-pulsar-proxy:80`. |
<!-- infernix:route-registry:web-portal:end -->

On the real Kind path those routes are published by `Gateway/infernix-edge`,
`EnvoyProxy/infernix-edge`, and the repo-owned HTTPRoute set.

## Workbench Behavior

- the workbench is implemented in PureScript, built into `web/dist/` by
  `npm --prefix web run build`, and served by the `infernix-demo` Haskell binary
- frontend contract modules are emitted into `web/src/Generated/` by
  `infernix internal generate-purs-contracts`
- the visible catalog comes from the generated demo catalog for the active runtime mode
- the generated catalog is published by `cluster up` as `infernix-substrate.dhall`, mounted into
  the `infernix-demo` workload through `ConfigMap/infernix-demo-config`, and mirrored under the
  active build root for inspection
- the browser workbench renders the generated catalog exactly rather than maintaining a separate
  browser-only subset
- the routed Playwright contract cross-checks `/api/models` against the serialized generated demo
  config returned by `GET /api/demo-config` and separately validates publication details from
  `/api/publication`
- supported routed E2E uses the dedicated `infernix-playwright:local` container, invoked via
  `docker compose run --rm playwright`; Apple host-native flows run that compose invocation
  directly while Linux flows forward it from the outer container through the mounted host docker
  socket
- the workbench surfaces the active runtime mode, control-plane context, daemon location, inference
  executor location in the publication payload, catalog source, chosen edge port, inference
  dispatch mode, demo-config path, and routed publication inventory through
  `/api/publication`
- the user can browse any generated model entry, inspect its selected engine and request shape,
  and submit a manual inference request through the demo `/api`
- manual inference requests always enter through the clustered `infernix-demo` workload, but the
  routed deployment bridges them through Pulsar into the active daemon lane: Apple enters the
  cluster daemon first and then hands host batches to the host-native daemon, while Linux uses the
  cluster-resident daemon for both orchestration and inference execution
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
