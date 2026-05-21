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
- the Keycloak workload image is mirrored into Harbor before deployment and pulled from
  Harbor at runtime; no other registries are used after Harbor is ready
- the realm definition is pre-seeded by an in-binary reconcile path during `cluster up`; the
  realm allows self-signup with username and password, has email verification disabled, has
  no MFA, no federation, and no social login
- the realm includes a public OIDC client for the SPA at the demo SPA route; the JWT
  audience claim and issuer URL are stable across `cluster up` re-runs
- the routed `/auth` prefix forwards to the Keycloak service; this route is added to the
  Haskell-owned route registry source so README, the web portal surface doc, and
  publication JSON all carry it via the auto-rendered route registry markers
- the `infernix-demo` backend validates JWTs against the Keycloak JWKS endpoint and caches
  the JWKS with a short TTL so transient Keycloak unavailability does not break existing
  sessions
- the Keycloak `sub` claim is the canonical per-user identifier and is stable across login,
  logout, password change, and device change; demo backend code derives Pulsar topic
  namespaces and MinIO prefixes from `sub`, not from username
- when `demo_ui = false`, the Keycloak release, its Patroni cluster, the `/auth` route, and
  the demo MinIO bucket are absent from the cluster

## Bootstrap Order

`cluster up` brings up Keycloak after Harbor is responsive and after the Keycloak Patroni
cluster reports readiness. Order:

1. Harbor + Harbor-required services (MinIO, Harbor's own Patroni cluster) start with public
   registry pulls allowed only for them
2. Operator-managed Patroni Postgres for Keycloak is created and reports ready
3. Keycloak Deployment is created from a Harbor-mirrored image
4. Realm pre-seed runs idempotently; subsequent `cluster up` runs verify the realm matches
   without rewriting it
5. `/auth` HTTPRoute is created; route registry rendering picks it up

## JWT Validation Surface

The `infernix-demo` binary uses `Infernix.Auth.Jwt` (shared library) parameterized in:

- the Keycloak issuer URL
- the audience claim expected for the SPA client
- the JWKS endpoint URL

Validation rules: standard OIDC `iss`, `aud`, `exp`, `nbf`, `iat`, signature against JWKS;
`sub` extracted as the canonical user id. Failed validation closes the WS or rejects the HTTP
request with a typed error.

## Reconstitution Contract

Because `sub` is stable, a user can clear all browser storage, sign in again on a different
device, change their password, or be issued a fresh JWT, and the demo backend's Pulsar topic
namespaces and MinIO prefixes resolve to the same locations. The browser holds no durable
state. See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) for the
full reconstitution sequence.

## Cross-References

- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [postgresql.md](postgresql.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
