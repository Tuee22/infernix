# Edge Routing

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Define the one-port routing contract for browser and host-consumed services.

## TL;DR

- One Haskell-owned route registry defines the supported public prefixes, rendered HTTPRoutes,
  route-aware docs, and route validation expectations.
- The routed surface always publishes Harbor and Pulsar, and publishes the demo routes
  only when the active generated config enables the demo UI. MinIO has no external gateway route.
- When the demo UI is enabled, `SecurityPolicy/infernix-operator-routes-jwt` both **authenticates and
  admin-authorizes** direct browser access to the operator route family — `/harbor`, `/harbor/api`,
  `/pulsar/admin`, and `/pulsar/ws` (Phase 9): it accepts the SPA's `infernix_operator_token` cookie or
  a direct `Authorization: Bearer ...` header, then requires the `infernix-admin` realm role
  (`defaultAction: Deny`). A valid non-admin token is rejected with HTTP 403. See
  [../architecture/access_control_doctrine.md](../architecture/access_control_doctrine.md).
- The `/minio/s3` edge route is removed (Phase 3 Sprint 3.13): the `infernix-demo`
  webapp is the sole externally routed surface for file storage, mediating every browser
  artifact upload and download server-side through its `/api/objects` endpoints, and the browser
  never reaches MinIO through the gateway. See
  [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md) for the
  webapp-mediated single-mediator contract.
- That admin gate governs browser/operator access through the Envoy edge only. Trusted in-cluster
  daemons and the Apple host-worker data plane reach Pulsar through the proxy Service
  (`ClusterConfig.pulsar.adminUrl`) or its un-gated loopback NodePort directly (Pulsar-proxy `30080`,
  MinIO `30011`, `listenAddress: 127.0.0.1`), not through the gated edge routes — see
  [../tools/pulsar.md](../tools/pulsar.md). The loopback binding of every Kind data-plane + edge
  port mapping (MinIO S3 `30011`, Pulsar proxy `30080`/`30650`, Envoy edge `30090`) is now ENFORCED
  by `infernix lint chart` (a scanner over the `kind/cluster-*.yaml` files) plus a unit assertion
  over the binary-generated Kind config (Sprint 9.4). `/pulsar/ws` is now **inside** the operator policy
  (Phase 9 added it to `targetRefs`), so the browser websocket surface is admin-gated at the edge while
  the host worker's loopback data plane is unaffected.
- Gateway owns the supported routed surface, and direct `infernix-demo` execution intentionally
  exposes only the demo-owned HTTP surface outside the intended HTTPRoute mapping.

## Current Status

The current worktree uses the registry-backed route contract directly: the generated route table in
this document comes from the Haskell route registry, `cluster status` and `/api/publication`
publish the same routed surface, and the Harbor-first bootstrap path no longer carries a separate
helper-registry route or namespace. Integration now requires the real Harbor, MinIO, and Pulsar
upstream responses on the tool-route probes rather than any direct `infernix-demo`
compatibility payload.
The auth-UX surface adds an Envoy Gateway `SecurityPolicy` for the operator console route family
when Keycloak is present. The routes remain in the always-published inventory, but browser access
to `/harbor` and `/pulsar/admin` is JWT-gated whenever the demo surface is enabled.

Phase 3 Sprint 3.13 removed the `/minio/s3` gateway route, the `infernix-minio-s3` SecurityPolicy
target, and the `presignPublicEndpoint` cluster-config field. MinIO is no longer browser-reachable;
the `infernix-demo` webapp `/api/objects` proxy is the only external file-storage surface, per
[../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md). The
generated route-inventory table below reflects the de-exposed surface (no `/minio/s3` row). The
browser object-proxy evidence closed in Wave M; generated artifact object ownership remains active
under Phase 7 Sprint 7.28.

## Route Inventory

- the chart-owned route contract lives in `GatewayClass/infernix-gateway`,
  `Gateway/infernix-edge`, `EnvoyProxy/infernix-edge`, and the HTTPRoute inventory rendered by
  `chart/templates/httproutes.yaml`

<!-- infernix:route-registry:edge-routing:start -->
| Public prefix | Visibility | Purpose | Backend | Rewrite |
|---------------|------------|---------|---------|---------|
| `/` | demo-only | Demo SPA | `infernix-demo:80` | no rewrite |
| `/api` | demo-only | Demo API | `infernix-demo:80` | no rewrite |
| `/harbor/api` | always published | Harbor API | `infernix-harbor-core:80` | `/harbor/api` -> `/api` |
| `/harbor` | always published | Harbor portal | `infernix-harbor-portal:80` | `/harbor` -> `/` |
| `/pulsar/admin` | always published | Pulsar admin surface | `infernix-infernix-pulsar-proxy:80` | `/pulsar/admin` -> `/` |
| `/pulsar/ws` | always published | Pulsar websocket surface | `infernix-infernix-pulsar-proxy:80` | `/pulsar/ws` -> `/ws` |
| `/auth` | demo-only | Keycloak SSO | `infernix-keycloak:8080` | no rewrite |
| `/ws` | demo-only | Demo durable-context WebSocket | `infernix-demo:80` | no rewrite |
| `/api/objects` | demo-only | Demo webapp object-proxy (upload/download/list/delete) | `infernix-demo:80` | no rewrite |
<!-- infernix:route-registry:edge-routing:end -->

- when the demo surface is enabled, `/`, the demo `/api*` routes, `/auth`, `/ws`, and
  `/api/objects` target the `infernix-demo` workload (or the routed Keycloak release in the
  `/auth` case); that workload runs `infernix service --role webapp --config ...` and exposes the
  same Haskell demo API surface through the routed cluster path. The supported routed Apple story
  keeps that HTTP host cluster-resident and bridges manual inference through Pulsar into the host
  daemon
- `/api/publication` reports daemon location, `inferenceDispatchMode`, and routed-upstream health
  plus backing-state details
- when the demo surface is enabled, the operator route family keeps its existing HTTPRoute
  backends but is protected by `SecurityPolicy/infernix-operator-routes-jwt`; the SPA writes the
  `infernix_operator_token` cookie after login and refresh so normal browser navigation to the
  operator links passes the edge JWT check

## Gateway Ownership

- `cluster up` applies the Gateway API and Envoy Gateway CRDs from the bundled `gateway-helm`
  dependency before the controller rollout because Helm does not install dependency-chart CRDs on
  the supported path
- `EnvoyProxy/infernix-edge` customizes the managed Envoy Service to use the repo-owned
  `NodePort` contract on `30090` with `externalTrafficPolicy: Cluster`
- that pinned Envoy Service shape keeps the host-native and Linux outer-container routed surfaces
  on the same shared edge contract

## Port Selection Rules

- `cluster up` tries `9090` first and increments by `1` until it finds an available port
- the chosen port is recorded under `./.data/runtime/edge-port.json`
- `cluster up` prints the chosen port during bring-up
- `cluster status` reports the active runtime mode together with the chosen port, the published
  route inventory, and the publication-state details that back `/api/publication`

## Validation

- `infernix docs check` fails if this document loses its governed metadata, required structure, or
  the registry-generated route-inventory section.
- `infernix test integration` exercises the published Harbor, MinIO, Pulsar, publication, and
  demo routes and requires the real Harbor, MinIO, and Pulsar upstream responses on the
  tool-route probes.
- `infernix test e2e` verifies the routed demo surface through the shared edge port when the demo
  UI is enabled for the selected runtime mode, including the JWT-gated operator route checks.

## Cross-References

- [object_storage.md](object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [../tools/pulsar.md](../tools/pulsar.md)
