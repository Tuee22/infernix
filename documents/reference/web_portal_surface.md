# Web Portal Surface

**Status**: Authoritative source
**Referenced by**: [api_surface.md](api_surface.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the browser-visible routes and PureScript demo SPA behavior exposed
> through the published routed surface.

## Scope

The `/` and demo-related routes (`/`, `/api*`, `/auth`, `/ws`, `/api/objects`) are demo-only and absent from
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
| `/` | Demo SPA | PureScript demo SPA served by `infernix-demo`. |
| `/api` | Demo API | Covers `/api/publication`, `/api/cache`, `/api/models`, and `/api/demo-config`. |
| `/auth` | Keycloak SSO | Registry-defined route. |
| `/ws` | Demo durable-context WebSocket | Registry-defined route. |
| `/api/objects` | Demo MinIO presigned URL minting | Registry-defined route. |

Always-published operator prefixes:

| Routed prefix | Purpose | Notes |
|---------------|---------|-------|
| `/harbor/api` | Harbor API | Rewrites to upstream `/api` before forwarding to `infernix-harbor-core:80`. |
| `/harbor` | Harbor portal | Rewrites to upstream `/` before forwarding to `infernix-harbor-portal:80`. |
| `/minio/s3` | MinIO S3 API | Rewrites to upstream `/` before forwarding to `infernix-minio:9000`. |
| `/pulsar/admin` | Pulsar admin surface | Rewrites to upstream `/` before forwarding to `infernix-infernix-pulsar-proxy:80`. |
| `/pulsar/ws` | Pulsar websocket surface | Rewrites to upstream `/ws` before forwarding to `infernix-infernix-pulsar-proxy:80`. |
<!-- infernix:route-registry:web-portal:end -->

On the real Kind path those routes are published by `Gateway/infernix-edge`,
`EnvoyProxy/infernix-edge`, and the repo-owned HTTPRoute set.

## Durable Context Surface

Phase 7 added three routed prefixes to the registry above. They are demo-gated and absent
when the active substrate's generated `.dhall` carries `demo_ui = false`:

- `/auth` — Keycloak login pages and OIDC endpoints. Backs the SPA's signup, login, and JWT
  issuance flow. See [../tools/keycloak.md](../tools/keycloak.md).
- `/ws` — authenticated WebSocket endpoint for the durable-context session. Carries chat
  send/receive, context list/create/delete, draft sync, inference progress, and artifact-ready
  notifications. JWT is presented on the WS handshake; envelope wire format is
  `purescript-bridge`-generated typed sums (`WsClientMessage` / `WsServerMessage`).
- `/api/objects` — HTTP endpoint that mints presigned MinIO PUT/GET URLs scoped to the
  authenticated user. Artifact bytes are uploaded and downloaded directly to and from MinIO;
  they never traverse the demo backend. See [api_surface.md](api_surface.md) and
  [../tools/minio.md](../tools/minio.md).

The demo `Service` sets `sessionAffinity: None` and the HTTPRoute does not enable client-IP or
cookie affinity. WS pods use Pulsar `Reader` subscriptions for per-WS fan-out, so any replica
can host any session. The routed browser surface terminates at the frontend pod
(`infernix-demo`); the coordinator and engine pods named in
[../architecture/daemon_topology.md](../architecture/daemon_topology.md) are not directly
addressable from the browser.

See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) for the full
contract.

## SPA Behavior

- the SPA is implemented in PureScript, built into `web/dist/` by
  `npm --prefix web run build`, and served by the `infernix-demo` Haskell binary
- frontend contract modules are emitted into `web/src/Generated/` by
  `infernix internal generate-purs-contracts`
- the visible catalog comes from the generated demo catalog for the active runtime mode
- the generated catalog is staged under the active build root as `infernix-substrate.dhall`;
  `cluster up` publishes a cluster-role payload through `ConfigMap/infernix-demo-config`, mounts
  it into the `infernix-demo` workload, and mirrors the publication under
  `./.data/runtime/configmaps/infernix-demo-config/` for inspection; on Apple that cluster-role
  payload is rendered from the active staged substrate metadata and `demo_ui` setting while the
  host daemon keeps reading its host-role file under `./.build/`
- the browser SPA renders the generated catalog exactly rather than maintaining a separate
  browser-only subset
- the routed Playwright contract cross-checks `/api/models` against the serialized generated demo
  config returned by `GET /api/demo-config` and separately validates publication details from
  `/api/publication`
- supported routed E2E on Linux uses Playwright from the substrate image with
  `npm --prefix web exec -- playwright test`; Apple host-native routed E2E uses host
  `npm exec` with the same typed fixture and is covered by the Apple cohort validation batch
- the SPA surfaces the active runtime mode, control-plane context, daemon location, inference
  executor location in the publication payload, catalog source, chosen edge port, inference
  dispatch mode, demo-config path, and routed publication inventory through
  `/api/publication`
- the user can browse any generated model entry and inspect its selected engine and request shape
- supported manual-inference dispatch closes through the durable-context Chat surface introduced
  by Phase 7: the browser opens a WebSocket against `/ws`, sends typed
  `WsClientMessage` actions, and receives `ConversationState` snapshots plus
  `ConversationStatePatch` deltas. The coordinator daemon
  (`infernix-coordinator`) publishes Pulsar batches; the engine role (`infernix-engine` on
  Linux, on-host daemon on Apple) executes inference and publishes results, which the
  coordinator then writes back to the originating conversation topic.
- manual inference requests execute through the same Haskell worker dispatch used by the
  production daemon, including shared Python adapters under `python/adapters/` when the bound
  engine is Python-native
- large outputs surface as typed `ObjectRef` results that point into the `infernix-demo-objects`
  MinIO bucket; the browser fetches them via presigned GET URLs minted at `/api/objects`
  (the legacy `GET /objects/:objectRef` route is retired in Phase 7 Sprint 7.7)
- switching runtime modes changes the generated catalog and selected engine bindings without
  changing the browser route structure

## Cross-References

- [api_surface.md](api_surface.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../tools/keycloak.md](../tools/keycloak.md)
- [../tools/minio.md](../tools/minio.md)
