# Web Portal Surface

**Status**: Authoritative source
**Referenced by**: [api_surface.md](api_surface.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md)

> **Purpose**: Describe the browser-visible routes and PureScript demo SPA behavior exposed
> through the published routed surface.

## Scope

The `/` and demo-related routes (`/`, `/api*`, `/auth`, `/ws`, `/api/objects`) are demo-only and absent from
production deployments. Production deployments leave the active `.dhall` `demo_ui` flag off, the
cluster has no `infernix-demo` workload, and the demo routes are not bound. The registry, MinIO,
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
| `/api/objects` | Demo webapp object-proxy (upload/download/list/delete) | Registry-defined route. |

Always-published operator prefixes:

| Routed prefix | Purpose | Notes |
|---------------|---------|-------|
| `/registry` | Image registry API | Rewrites to upstream `/v2` before forwarding to `infernix-registry:5000`. |
| `/pulsar/admin` | Pulsar admin surface | Rewrites to upstream `/` before forwarding to `infernix-infernix-pulsar-proxy:80`. |
| `/pulsar/ws` | Pulsar websocket surface | Rewrites to upstream `/ws` before forwarding to `infernix-infernix-pulsar-proxy:80`. |
<!-- infernix:route-registry:web-portal:end -->

On the real Kind path those routes are published by `Gateway/infernix-edge`,
`EnvoyProxy/infernix-edge`, and the repo-owned HTTPRoute set.

When the demo UI is enabled, the three operator routes (`/registry`, `/pulsar/admin`, and
`/pulsar/ws`) are **admin-gated** by
`SecurityPolicy/infernix-operator-routes-jwt`. The policy validates the same Keycloak JWT
the SPA uses for `/ws` and `/api/objects` — accepting either the `infernix_operator_token` cookie
written by the SPA after login / refresh or an `Authorization: Bearer ...` header — **and** requires
the `infernix-admin` realm role (`authorization: defaultAction: Deny` plus an `allow-infernix-admins`
rule over the `realm_access.roles` claim). A valid JWT is therefore necessary but not sufficient: a
self-registered (non-admin) token is denied **403**, and anonymous traffic is denied **401**.
[../architecture/access_control_doctrine.md](../architecture/access_control_doctrine.md) is the
canonical contract for the admin-vs-user split. There is no `/minio/s3` edge route: MinIO is reachable only through the webapp `/api/objects` proxy.

## Durable Context Surface

The routed registry contains three durable-context prefixes. They are demo-gated and absent
when the active substrate's generated `.dhall` carries `demo_ui = false`:

- `/auth` — Keycloak login pages and OIDC endpoints. Backs the SPA's signup, login, and JWT
  issuance flow. See [../tools/keycloak.md](../tools/keycloak.md).
- `/ws` — authenticated WebSocket endpoint for the durable-context session. Carries chat
  send/receive, context list/create/delete, draft sync, inference progress, and artifact-ready
  notifications. JWT is presented on the WS handshake; envelope wire format is
  `purescript-bridge`-generated typed sums (`WsClientMessage` / `WsServerMessage`).
- `/api/objects` — webapp-mediated HTTP endpoint for browser artifact I/O. The
  `infernix-demo` webapp is the single mediator for every artifact upload and download: the
  browser POSTs upload bytes to `/api/objects/upload` and GETs download bytes from
  `/api/objects/download`, and the webapp reads and writes
  MinIO server-side over the cluster-internal endpoint. The browser holds only the webapp origin
  and an `ObjectRef`; it never receives a MinIO credential or a presigned MinIO URL, and never
  reaches MinIO through the gateway. Per-user isolation is enforced at this one server-side choke
  point on every request. See [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md),
  [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md),
  [api_surface.md](api_surface.md), and [../tools/minio.md](../tools/minio.md).

  The webapp object proxy is the only browser artifact path. There is no
  `/minio/s3` route, no SecurityPolicy target for it, and no
  `presignPublicEndpoint` field.

The demo `Service` sets `sessionAffinity: None` and the HTTPRoute does not enable client-IP or
cookie affinity. One frontend process runs per machine and uses Pulsar `Reader` subscriptions for
per-connection fan-out; it may host any session. The routed browser surface terminates at the frontend pod
(`infernix-demo`); the coordinator and engine pods named in
[../architecture/daemon_topology.md](../architecture/daemon_topology.md) are not directly
addressable from the browser.

See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) for the full
contract.

## Pre-Auth Landing

The durable-context app shell is gated behind a Keycloak JWT. Anonymous
visitors reaching the published edge port land on a minimal centred card carrying:

- the `Infernix` wordmark,
- the one-line subtitle "Durable-context inference console", and
- two explicit CTAs:
  - `Sign in` (primary) → `Infernix.Web.Auth.beginLoginRedirect` (Keycloak login form), and
  - `Create account` (secondary) → `Infernix.Web.Auth.beginRegisterRedirect` (Keycloak
    registration form via the `kc_action=register` Application Initiated Action).

The summary grid (Runtime, Control Plane, Daemon, Dispatch, Edge, Catalog, Connection) and
the Chat / Artifacts tabs are not rendered for anonymous visitors. The `body` element carries
an `auth-unknown` / `auth-signed-out` / `auth-signed-in` class set by
`Main.purs.renderAuthGate` on every render pass; CSS toggles the landing card and the app
shell against that class so neither flashes during the boot pass that reads the in-memory
JWT.

After a successful PKCE authorization-code exchange (login or registration), the JWT is
written into the in-memory `TokenStore` and the app shell renders; logout / token-clear returns the
user to the landing card.

The routed Keycloak forms use the repo-owned `infernix` login theme. The login form title is
`Sign in to Infernix`, the direct registration form title is `Create your Infernix account`, and
the theme is mounted from `ConfigMap/infernix-keycloak-theme` rather than baked into a custom
Keycloak image.

## Operator Console Ribbon

**Admin** users see an operator ribbon in the app shell with direct links to:

- `Registry` at `/registry`
- `Pulsar Admin` at `/pulsar/admin/admin/v2/clusters`

The ribbon is inside `.app-shell`, so it is hidden in the anonymous landing state, and the SPA
additionally hides it for every non-admin (a cosmetic `.infernix-admin` class set only when the
token carries the `infernix-admin` realm role). That CSS is cosmetic — the real gates are the edge
`SecurityPolicy` and the backend, which both deny a non-admin. The SPA writes the
`infernix_operator_token` cookie whenever it receives or refreshes the Keycloak access token, clears
the cookie on Sign out, and redirects through Keycloak logout to clear the SSO session. Only an
**admin** token in that cookie passes the edge authorization on
the operator routes; a non-admin token is denied 403 and anonymous traffic 401. The same cookie also
authenticates browser-issued media `src` GETs against the webapp `/api/objects/download` proxy — a
**per-user**, JWT-validated route (not admin-gated) — which `img`/`audio`/`video`/`iframe` elements
cannot set headers on. The admin cluster-wide monitoring panel reads the admin-gated
`GET /api/admin/overview`, and the backend additionally admin-gates `GET /api/cache` and
`/api/cache/{evict,rebuild}`.

The `Registry` and `Pulsar Admin` operator links are the operator ribbon's full set. MinIO is not
browser-reachable and the ribbon has no `MinIO S3` link; browser object access flows through the
webapp's `/api/objects` endpoints
(see [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)).

## Account Deletion

Authenticated users see `Delete account` beside `Sign out`. The SPA confirms the command, sends
`DELETE /api/account` with the current bearer token, and waits for that request to complete before
clearing local browser auth state and redirecting to Keycloak with `kc_action=delete_account`.

`DELETE /api/account` validates the same Keycloak JWT as `/ws` and `/api/objects`. The cleanup
removes the caller's `infernix-demo-objects/users/<userId>/` objects and deletes the caller-owned
Pulsar topics under `persistent://infernix/demo/`: `demo.user.<userId>.contexts`,
`demo.user.<userId>.drafts`, and `demo.conversation.<userId>.*`.

## SPA Behavior

- the SPA is implemented in PureScript, built into `web/dist/` by
  `npm --prefix web run build`, and served by the `infernix` Webapp role
- frontend contract modules are emitted into `web/src/Generated/` by
  `infernix internal generate-purs-contracts`
- the visible catalog comes from the generated demo catalog for the active runtime mode
- the catalog comes from repo-root `./infernix.dhall`, created explicitly by `infernix init` or
  temporarily by the test harness from `infernix test init`; `cluster up` publishes a derived
  cluster-role payload through `ConfigMap/infernix-demo-config`, mounts it into the
  `infernix-demo` workload, and mirrors the publication under
  `./.data/runtime/configmaps/infernix-demo-config/` for inspection; Apple host daemons keep reading
  the repo-root runtime config
- the browser SPA renders the generated catalog exactly rather than maintaining a separate
  browser-only subset
- the routed Playwright contract cross-checks `/api/models` against the serialized generated demo
  config returned by `GET /api/demo-config` and separately validates publication details from
  `/api/publication`
- supported routed E2E on Linux uses Playwright from the substrate image with
  `npm --prefix web exec -- playwright test`; Apple host-native routed E2E uses host
  `npm exec` with the same typed fixture and is covered by the Apple selected-accelerator gate
- the SPA surfaces the active runtime mode, control-plane context, daemon location, inference
  executor location in the publication payload, catalog source, chosen edge port, inference
  dispatch mode, demo-config path, and routed publication inventory through
  `/api/publication`
- the user can browse any generated model entry and inspect its selected engine and request shape
- supported manual-inference dispatch closes through the durable-context Chat surface: the browser
  opens a WebSocket against `/ws`, sends typed
  `WsClientMessage` actions, and receives `ConversationState` snapshots plus
  `ConversationStatePatch` deltas. The coordinator daemon
  (`infernix-coordinator`) publishes Pulsar batches; the engine role (`infernix-engine` on
  Linux, on-host daemon on Apple) executes inference and publishes results, which the
  coordinator then writes back to the originating conversation topic.
- manual inference requests execute through the same Haskell worker dispatch used by the
  production daemon, including shared Python adapters under `python/adapters/` when the bound
  engine is Python-native
- large outputs surface as typed `ObjectRef` results that point into the `infernix-demo-objects`
  MinIO bucket; the browser fetches the bytes through the webapp-mediated
  `/api/objects/download` endpoint, which streams them server-side from MinIO with the correct
  `Content-Type` and `Content-Disposition`. The browser holds only the `ObjectRef` and the webapp
  origin — never a presigned MinIO URL. See
  [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md).
- a `Files` view lists the authenticated user's artifacts and drives webapp-mediated upload and
  download for the supported artifact classes. Like every other per-user surface, the listing is
  scoped server-side to the caller's `users/<sub>/…` object prefix derived from the verified
  Keycloak `sub`, so a user only ever sees their own files; cross-user object keys are rejected at
  the server-side trust boundary. See
  [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md).
- switching runtime modes changes the generated catalog and selected engine bindings without
  changing the browser route structure

The webapp-mediated `/api/objects` byte proxy carries every artifact byte: the SPA uploads and
downloads through the webapp, never a presigned MinIO URL. The per-user `Files` navigational view
is backed by `GET /api/objects/list` + `DELETE /api/objects`.

## Cross-References

- [api_surface.md](api_surface.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)
- [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md)
- [../tools/keycloak.md](../tools/keycloak.md)
- [../tools/minio.md](../tools/minio.md)
