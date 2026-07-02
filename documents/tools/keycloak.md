# Keycloak

**Status**: Authoritative source
**Referenced by**: [../architecture/demo_app_design.md](../architecture/demo_app_design.md), [postgresql.md](postgresql.md), [../reference/web_portal_surface.md](../reference/web_portal_surface.md), [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Record the supported Keycloak deployment, realm pre-seed contract, JWT
> validation surface, and demo-gated lifecycle for the multi-user demo application.

## Rules

- the cluster runs Keycloak as a Helm release deployed by `infernix cluster up` when the
  active substrate's generated `.dhall` carries `demo_ui = true`
- Keycloak runs against a dedicated Patroni Postgres cluster managed by the Percona Kubernetes
  operator, in line with [postgresql.md](postgresql.md); Keycloak's chart-embedded database
  path is disabled
- the local demo runs one Keycloak application pod while the backing Patroni Postgres cluster
  remains HA; raising the Keycloak application replica count requires routed proxy-affinity or
  clustered-cache validation
- the Keycloak workload image is mirrored into Harbor before deployment and pulled from
  Harbor at runtime; no other registries are used after Harbor is ready
- the realm definition is pre-seeded by an in-binary reconcile path during `cluster up`; the
  realm allows self-signup with username and password, has email verification disabled, has
  no MFA, no federation, and no social login
- the realm includes a public OIDC client for the SPA at the demo SPA route; `cluster up`
  reconciles browser redirect URIs and web origins for the operator-facing edge URL before the
  routed publication probe declares the cluster ready
- the login and registration pages use the repo-owned `infernix` Keycloak login theme mounted from
  `ConfigMap/infernix-keycloak-theme`; the stock Keycloak image remains unchanged, and the
  idempotent realm reconcile keeps `loginTheme = infernix`
- the routed `/auth` prefix forwards to the Keycloak service; this route is added to the
  Haskell-owned route registry source so README, the web portal surface doc, and
  publication JSON all carry it via the auto-rendered route registry markers
- the `infernix-demo` backend validates JWTs against the Keycloak JWKS endpoint and caches
  the JWKS with a short TTL so transient Keycloak unavailability does not break existing
  sessions
- the mounted `ClusterConfig.keycloak.baseUrl` is the public routed issuer base that includes
  `/auth`; the mounted `clientId` is the public SPA client `infernix-spa`; the mounted
  `jwksUrl` may use the in-cluster Keycloak Service and must include the service port plus the
  `/auth/realms/<realm>/protocol/openid-connect/certs` path
- the Keycloak `sub` claim is the canonical per-user identifier and is stable across login,
  logout, password change, and device change; demo backend code derives Pulsar topic
  namespaces and MinIO prefixes from `sub`, not from username. `sub` is the single source of
  caller identity — it is extracted server-side from a cryptographically verified token and the
  client never names its own user id, full object key, or topic name. This is the canonical
  per-user isolation key; see
  [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md)
  for the doctrine that derives every per-user MinIO prefix and Pulsar topic from `sub` and
  enforces it at a single server-side trust boundary
- when `demo_ui = false`, the Keycloak release, its Patroni cluster, the `/auth` route, and
  the demo MinIO bucket are absent from the cluster
- the production-shape integration test confirms that `demo_ui = false` omits the Keycloak
  Deployment, Service, realm ConfigMap, admin Secret, and the `keycloak-postgresql` Patroni
  cluster while keeping `infernix-engine` present

## Bootstrap Order

`cluster up` brings up Keycloak after Harbor is responsive and after the Keycloak Patroni
cluster reports readiness. Order:

1. Harbor + Harbor-required services (MinIO, Harbor's own Patroni cluster) start with public
   registry pulls allowed only for them
2. Operator-managed Patroni Postgres for Keycloak is created and reports ready
3. Keycloak Deployment is created from a Harbor-mirrored image
4. Realm pre-seed runs idempotently; subsequent `cluster up` runs reconcile the realm flags,
   `infernix` login theme, public SPA client, redirect URIs, web origins, and PKCE setting
   through the Keycloak admin API
5. `/auth` HTTPRoute is created; route registry rendering picks it up

## Login Theme

The supported Keycloak UI surface is a chart-owned theme, not a forked Keycloak image. The chart
renders `chart/templates/keycloak/configmap-theme.yaml` as `ConfigMap/infernix-keycloak-theme` and
mounts it read-only at `/opt/keycloak/themes/infernix` in the Keycloak pod. The ConfigMap provides:

- `login/theme.properties` with `parent=keycloak.v2` and `styles=css/login.css css/infernix.css`
- `login/messages/messages_en.properties` with Infernix-specific login and registration titles
- `login/resources/css/infernix.css` for the local visual treatment

The realm import declares `loginTheme = infernix`, and
`src/Infernix/Cluster.hs.keycloakRealmReconcilePayload` reapplies the same value during every
post-rollout reconcile. The routed Playwright auth smoke asserts the themed login title
(`Sign in to Infernix`) and registration title (`Create your Infernix account`) so the test fails
if Keycloak falls back to the upstream default theme.

## JWT Validation Surface

The Webapp role uses `Infernix.Auth.Jwt` (shared library) parameterized in:

- the Keycloak issuer URL
- the audience claim expected for the SPA client
- the JWKS endpoint URL

Validation rules: standard OIDC `iss`, `aud`, `exp`, `nbf`, `iat`, signature against JWKS;
`sub` extracted as the canonical user id. Failed validation closes the WS or rejects the HTTP
request with a typed error.

The routed Playwright run validates the public Keycloak path end to end for the object-grant
API: a fresh user self-registers through `/auth`, the authorization code is exchanged for a
real access token, `/api/objects/upload` rejects a malformed bearer token with `401`, the
backend accepts the real token for scoped webapp-mediated upload/download, and the same user
completes a routed `/api/objects` byte roundtrip. A second fresh user with the same
context/display name receives a different `users/<sub>/...` object prefix and cannot read the
first user's object by default. The routed suite opens `/ws` with the real token, verifies a
malformed token does not open a browser WebSocket, and asserts a typed `ServerError` for a
malformed frame on a valid connection. The browser artifact flow starts from the SPA's own
sign-in button, lets `web/src/Infernix/Web/Auth.purs` / `.js` generate the PKCE verifier and
complete the authorization-code exchange, then uses the in-memory access token for routed
artifact upload and preview calls. The account-deletion smoke clicks the SPA's `Delete account`
command, verifies `DELETE /api/account` removes the user's demo-owned MinIO and Pulsar state, and
then observes the browser enter Keycloak's `kc_action=delete_account` Application Initiated
Action.

## Reconstitution Contract

Because `sub` is stable, a user can clear all browser storage, sign in again on a different
device, change their password, or be issued a fresh JWT, and the demo backend's Pulsar topic
namespaces and MinIO prefixes resolve to the same locations. The browser holds no durable
state. Account deletion is the explicit exception: the browser asks the backend to reap the
`sub`-scoped MinIO prefix and user-owned Pulsar topics before Keycloak removes the IdP account.
See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) for the full
reconstitution sequence.

## Cross-References

- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md)
- [postgresql.md](postgresql.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
