# Access Control Doctrine

**Status**: Authoritative source
**Referenced by**: [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md), [daemon_topology.md](daemon_topology.md), [web_ui_architecture.md](web_ui_architecture.md), [../engineering/edge_routing.md](../engineering/edge_routing.md), [demo_app_design.md](demo_app_design.md), [../../DEVELOPMENT_PLAN/phase-9-access-control-and-monitoring.md](../../DEVELOPMENT_PLAN/phase-9-access-control-and-monitoring.md)

> **Purpose**: Define the role-based access-control contract for the durable-context demo — the split
> between **cluster-wide admin** surfaces (operator consoles + monitoring) and **per-user** surfaces
> (own chat, artifacts, files, personal dashboard), how the admin role travels from Keycloak to the
> enforcement points, and why the Apple host-worker data plane bypasses the admin-gated edge.

## TL;DR

- **Two dimensions of authorization.** Per-user *isolation* (a user sees only their own objects and
  chat) is owned by [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md) and is derived from the
  Keycloak `sub`. This doctrine adds the orthogonal **admin vs. user** dimension: only members of the
  `infernix-admin` realm role may see **cluster-wide** data.
- **Invariant.** Admins see cluster-wide surfaces (Harbor, Pulsar Admin, cluster-wide monitoring);
  every other authenticated user — including self-registered users — sees only their own data. A valid
  JWT is necessary but **not sufficient** for cluster-wide surfaces.
- **Admin identity is a realm role, not a user id.** Keycloak emits the `infernix-admin` role in
  `realm_access.roles`; the hardcoded `admin` account (demo app) carries it. Self-registered users
  never receive it.
- **How an operator becomes admin.** Admin is a **separate login**, not a mode of a regular account:
  sign in as the pre-seeded admin account (username `keycloak.realm.demoAdmin.username`, default
  `admin`; password `keycloak.realm.demoAdmin.password`, both in `chart/values.yaml`). That account is
  the only principal granted `infernix-admin`; a self-registered user cannot be elevated in the demo,
  so no ordinary user can reach the admin portal.

## Identity and roles

The realm import (`chart/templates/keycloak/configmap-realm-import.yaml`) declares the `infernix-admin`
realm role, an `oidc-usermodel-realm-role-mapper` that emits `realm_access.roles` into the access
token, and a hardcoded `admin` user pre-assigned the role (`chart/values.yaml`
`keycloak.realm.adminRealmRole` / `keycloak.realm.demoAdmin`). The backend decodes the roles into
`Infernix.Auth.Jwt.JwtClaims.jwtClaimRealmRoles`; `jwtClaimsHasRealmRole "infernix-admin"` is the
admin predicate. `sub`-scoped per-user surfaces never consult the role.

## Enforcement points

| Surface | Path | Gate |
|---|---|---|
| Operator consoles (Harbor `/harbor` + `/harbor/api`, Pulsar Admin `/pulsar/admin` + `/pulsar/ws`) | browser → Envoy **edge** (gateway NodePort 30090) | `SecurityPolicy/infernix-operator-routes-jwt`: JWT authentication **and** an `authorization` rule (`defaultAction: Deny`) allowing only tokens whose `realm_access.roles` include `infernix-admin` |
| Admin monitoring panel + `/api/admin/overview`; cluster-wide model-cache surface `GET /api/cache` and the `/api/cache/{evict,rebuild}` mutations | browser → `infernix-demo` webapp | backend requires `jwtClaimsHasRealmRole "infernix-admin"` (`withAdminRequest`); 401 without a token, 403 for a valid non-admin token |
| Per-user chat / artifacts / files / personal dashboard | browser → `infernix-demo` webapp | `sub`-derived, per-user (tenant isolation); no role needed |
| Per-user object storage (upload / download / list / delete) | `infernix-demo` webapp → MinIO (internal endpoint) | server-side `pathBelongsToUser` on the verified `sub` **plus** (when `cluster.minio.stsPerUser`) a per-user MinIO STS credential scoped by an inline session policy to `users/<sub>/*` — the IAM layer is a second boundary, so the shared root credential is not the sole isolation (Sprint 9.7) |
| MinIO S3 + Pulsar proxy **data plane** | Apple host worker → loopback NodePorts (MinIO 30011, Pulsar-proxy 30080) | **none at the edge** — trust-boundary-internal, `listenAddress: 127.0.0.1`, never transits the gateway. The loopback binding of every Kind data-plane + edge port mapping is enforced by `infernix lint chart` and a unit assertion over the generated Kind config (Sprint 9.4) |

The last row is the reason admin-gating the edge is safe: the Apple host-native engine daemon reaches
the cluster data plane directly on loopback (see
[daemon_topology.md](daemon_topology.md) and `src/Infernix/Runtime/Pulsar.hs`), so it is unaffected by
the Keycloak+admin gate on the browser edge (30090).

> **Known residual (UAT).** A later UAT pass surfaced an unresolved authentication issue, so Phase 9
> is `Active` (see the plan's
> [Remaining Work — UAT auth residual](../../DEVELOPMENT_PLAN/phase-9-access-control-and-monitoring.md)).
> One candidate lead to investigate — not a confirmed root cause — is that the edge admin access token
> is written to a JS-readable, non-`Secure` cookie (`infernix_operator_token`, `SameSite=Lax`) in
> `web/src/Infernix/Web/Auth.js` and consumed verbatim by the edge `SecurityPolicy`; a role-bearing
> token near the ~4 KB cookie limit could be silently dropped and 401 a real admin.

## Current Status

The admin/user role model is implemented under
[Phase 9](../../DEVELOPMENT_PLAN/phase-9-access-control-and-monitoring.md). Code-side closed
(2026-07-06, machine-independent gates green — `cabal build all`, `cabal test infernix-unit`,
`cabal test infernix-haskell-style`, `infernix lint chart|docs|files|proto`, `infernix docs check`,
`poetry run check-code`):

- the realm role + mapper + hardcoded admin user, the `JwtClaims` role parse + `jwtClaimsHasRealmRole`
  (unit-covered), and the edge `SecurityPolicy` admin `authorization` over all four operator routes;
- the backend admin gate (`withAdminRequest`) on `GET /api/cache`, `POST /api/cache/{evict,rebuild}`,
  and the new `GET /api/admin/overview` cluster-wide monitoring endpoint;
- the SPA admin gating in `web/src/index.html` — the operator ribbon, the five infrastructure
  summary cells, and the `#admin-panel` cluster monitoring card are admin-only, while every
  authenticated user sees the per-user `#personal-dashboard`;
- the Kind data-plane + edge loopback invariant enforced by `infernix lint chart` and a unit
  assertion over the generated Kind config;
- the per-user MinIO STS scoped-credential machinery (`Infernix.Objects.Sts` + session-token
  presigning), gated by `cluster.minio.stsPerUser` and wired into the object-proxy, unit-covered
  for the policy document, the signed `AssumeRole` request, response parsing, and session-token
  presigning.

Phase 9 is **Done**: [Wave Q](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) cohort-validated live
on **both `apple-silicon` and `linux-cpu`** (2026-07-07). Each cohort's full `cluster up` proved
unauthenticated 401 on every gated route; by-role 403 (non-admin) / 2xx (admin) over the four operator
routes + `/api/cache` + `/api/admin/overview`; the admin `realm_access.roles ⊇ infernix-admin` claim; the
loopback data-plane split; per-user isolation; and the now-default-on per-user STS scoped-credential
object path. The apple-silicon cohort additionally ran the routed Playwright RBAC / dashboard /
lifecycle suite 7/7 (substrate-independent SPA).

## Validation

- `infernix lint chart` proves the rendered `SecurityPolicy` carries the admin `authorization` rule and
  targets all four operator routes, and that every Kind data-plane + edge port mapping binds to
  `127.0.0.1`; `infernix lint docs` keeps this doctrine's metadata consistent.
- Unit coverage proves `realm_access.roles` decode and the admin predicate, the STS session policy
  scopes to `users/<sub>/*`, the signed `AssumeRole` request and its response parse, session-token
  presigning threads `X-Amz-Security-Token`, and the generated Kind config is loopback-bound
  (`test/unit/Spec.hs`).
- Wave Q proves, on the selected accelerator plus `linux-cpu`, that a non-admin token receives HTTP 403
  on every operator route (and on `GET /api/cache`, `/api/cache/*`, `/api/admin/overview`) while an
  admin token receives 2xx, that per-user surfaces stay scoped to the caller, that the Apple
  host-worker loopback data plane keeps working while the edge is admin-gated, and — with
  `cluster.minio.stsPerUser` enabled — that a cross-user prefix is denied at the MinIO IAM layer.
