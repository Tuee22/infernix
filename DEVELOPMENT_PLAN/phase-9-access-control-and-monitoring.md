# Phase 9: Access Control and Monitoring Surfaces

**Status**: Active. Sprints 9.1 through 9.10 are `Done`, and Sprint 9.11 is code-side complete: the
admin dimension, cluster overview, and personal dashboard render from application state while the
HTML shell remains static. The current-source native-arm64 `linux-cpu` build, governed unit suite,
and routed browser suite pass. Wave 9.1 retains the selected current-source `linux-gpu` plus paired
`linux-cpu` full-suite sign-off.

**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/access_control_doctrine.md](../documents/architecture/access_control_doctrine.md), [../documents/architecture/tenant_isolation_doctrine.md](../documents/architecture/tenant_isolation_doctrine.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)

> **Purpose**: Define the supported role-based access-control contract for the durable-context demo —
> the split between **cluster-wide admin** surfaces (operator consoles + monitoring) and **per-user**
> surfaces (own chat, artifacts, files, and personal dashboard) — plus the Apple host-worker
> loopback data-plane posture that keeps trust-boundary-internal traffic off the Keycloak-gated edge.

## Phase Status

Per-user *object and chat* isolation already exists and is unchanged (Phase 7:
`pathBelongsToUser`/`topicBelongsToUser`, `users/<sub>/` prefix — see
[../documents/architecture/tenant_isolation_doctrine.md](../documents/architecture/tenant_isolation_doctrine.md)).
This phase adds the missing **admin vs. user** dimension: before it, the Keycloak realm declared zero
roles, `JwtClaims` could not parse a role claim, and the operator consoles (the registry, Pulsar Admin) plus
several cluster routes were reachable by any authenticated — including self-registered — user.

**Invariant**: only members of the `infernix-admin` realm role may see cluster-wide data (operator
consoles, cluster-wide monitoring); every other authenticated user sees only their own data. Admin
credentials are hardcoded (demo app). Enforcement is at two points: the Envoy **edge**
`SecurityPolicy` (browser path, gateway NodePort 30090) and the backend for `/api/*`. The Apple
host-worker **data plane** (MinIO NodePort 30011, Pulsar-proxy NodePort 30080) is loopback-only and
trust-boundary-internal — it never transits the admin-gated edge.

All eleven sprints are code-side complete and the machine-independent gate set is clean through the
governed native-arm64 `linux-cpu` build and `infernix test unit`, including the admin-claim, STS
scoped-credential / session-token, generated-Kind-config loopback, and compiled PureScript
application-state assertions. The standalone files, docs, chart, and protobuf lints plus the docs
check pass. The HTML shell contains only static markup and the compiled application module; admin
role decoding and both dashboard transports live in the PureScript application boundary.


- **Unauthenticated** `GET /api/admin/overview`, `GET /api/cache`, `POST /api/cache/evict`, `/registry`,
  `/pulsar/admin`, `/pulsar/ws`, `/api/objects/list` all return **401**; `/api/publication` returns 200.
- **By role** over `/api/admin/overview`, `/api/cache`, `/registry`, `/pulsar/admin`, `/pulsar/ws`:
  non-admin token → **403**, admin token → **2xx** (`/pulsar/ws` admin → 404, the WS backend's own
  non-auth response — past the edge gate). The admin token carries `realm_access.roles ⊇ infernix-admin`;
  a self-service token does not. The admin access token mints without any profile patch, because the
  realm import carries the admin account's complete profile.
- `GET /api/admin/overview` returns real cluster-wide aggregates (substrate, dispatch mode, catalog
  and engine/pool sizes, member count) for the substrate actually running.
- **Loopback data plane**: MinIO S3 (`127.0.0.1:30011`) and the Pulsar proxy (`127.0.0.1:30080`) answer
  200 un-gated while the browser edge (`/registry`) requires admin; the live generated Kind config binds
  every data-plane + edge port to `127.0.0.1`.
- **Per-user isolation**: user A reads its own object (200); user B is denied A's object and any
  cross-user key (403); B's `/api/objects/list` is empty and scoped to `users/<B>/`.
- **Per-user STS (9.7)**: with the default-on `cluster.minio.stsPerUser` the object path works
  end-to-end through the scoped `AssumeRole` credential.
- **Routed Playwright RBAC + dashboard + lifecycle suite passes** on current-source native-arm64
  `linux-cpu` (admin
  sees ribbon/panel/cluster cells; non-admin denied; personal dashboard disjoint;
  logout/re-login/token-refresh; returning-user sign-in; wrong-password rejected; deleted-account
  auth loop). Browser rendering is substrate-independent: every lane deploys the identical baked
  SPA carrying the application-owned admin panel and personal dashboard.

Sprint 9.9 owns the logout/session-switching contract and its routed authentication-lifecycle
coverage. Wave 9.1 owns the current-source selected `linux-gpu` plus paired `linux-cpu` full-suite
closure for the phase.

## Remaining Work — UAT auth residual [Done]

Both repo-root `notes.txt` items are resolved code-side:

1. **UAT auth issue diagnosed.** The failure mode was local-only Sign out: the SPA cleared its
   in-memory access token and `infernix_operator_token` cookie but left the Keycloak SSO browser
   session alive, so a user who signed out of a self-registered non-admin account and then attempted
   the separate admin credentials could be silently signed back in as the old non-admin session and
   continue receiving 403s for admin surfaces. Sprint 9.9 implements the Keycloak OIDC logout
   redirect and adds routed Playwright coverage for switching from user to admin.
2. **Admin-access documentation gap answered.** Admin is a **separate login**: a single hardcoded
   `admin` account (`keycloak.realm.demoAdmin.username` / `.password`) is the only principal granted
   the `infernix-admin` realm role. Self-registered users are non-admin **by construction** and are
   denied at both the edge `SecurityPolicy` and the backend `withAdminRequest` gate — no ordinary
   user can reach the admin portal.

**Remaining Work:** None.

## Sprint 9.1: Keycloak admin realm role, mapper, and hardcoded admin user [Done]

**Status**: Done
**Implementation**: `chart/templates/keycloak/configmap-realm-import.yaml`, `chart/values.yaml`
**Docs to update**: `documents/tools/keycloak.md`, `documents/architecture/access_control_doctrine.md`

### Objective
Give the realm a cluster-wide admin role and a hardcoded admin account; self-registered users are
non-admin by construction.

### Deliverables
- `infernix-admin` realm role + protocol mapper emitting `realm_access.roles` into the access token
- hardcoded `admin` account (username/password in values; demo-only) pre-assigned the admin role

### Validation
- realm JSON body well-formed; `infernix lint chart` green (live import + token-claim check)

### Remaining Work
None.

## Sprint 9.2: Backend realm-role claim parsing [Done]

**Status**: Done
**Implementation**: `src/Infernix/Auth/Jwt.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/access_control_doctrine.md`

### Objective
Let the backend read the caller's realm roles so `/api/*` handlers can distinguish admins.

### Deliverables
- optional `realm_access.roles` parse (absent → empty; per-user `sub` surfaces never consult it)
- `jwtClaimsHasRealmRole :: Text -> JwtClaims -> Bool`

### Validation
- unit tests: no-role token → no admin; role token → admin (green host-native)

### Remaining Work
None.

## Sprint 9.3: Edge admin authorization + ungated-route closure [Done]

**Status**: Done
**Implementation**: `chart/templates/securitypolicy-operator-routes.yaml`, `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/architecture/web_ui_architecture.md`

### Objective
Make a valid JWT necessary but not sufficient for cluster-wide surfaces; require the admin role at the
edge, and close the routes that had no gate at all.

### Deliverables
- edge admin `authorization` on the four operator routes (30090 only) — **landed** (`infernix lint chart` green)
- backend admin gate on the `/api/cache/*` **mutations** (`evict`, `rebuild`) via `withAdminRequest` /
  `authenticateAdminRequest` (`jwtClaimsHasRealmRole "infernix-admin"`) — **landed** (`cabal build all` green)
- backend admin gate on the read-only cluster-wide `GET /api/cache` status too — **landed**; the
  integration assertion (`test/integration/Spec.hs`) now proves the gate by asserting an
  unauthenticated read is rejected 401, matching how the registry / Pulsar Admin operator routes are
  asserted in the same suite (the admin-authenticated 2xx read is proven by routed Playwright, 9.8)

### Validation
- `infernix lint chart` green; realm-role authz shape per Envoy Gateway `v1alpha1`; the admin gate
  compiles and reuses the JWT role predicate; unit suite + integration-compile green

### Remaining Work
None.

## Sprint 9.4: Apple host-worker loopback data-plane invariant [Done]

**Status**: Done
**Implementation**: `src/Infernix/Lint/Chart.hs`, `test/unit/Spec.hs`, `kind/cluster-*.yaml`
**Docs to update**: `documents/architecture/daemon_topology.md`, `documents/engineering/edge_routing.md`, `documents/architecture/access_control_doctrine.md`

### Objective
Make the existing posture an enforced, documented invariant: the Apple host worker reaches MinIO
(NodePort 30011) and the Pulsar proxy (NodePort 30080) directly on loopback (`listenAddress: 127.0.0.1`),
un-gated and trust-boundary-internal, and keeps working while the browser edge is admin-gated.

### Deliverables
- lint + unit assertion that every data-plane + edge NodePort host mapping is `127.0.0.1` — **landed**
  (chart-lint scanner over the committed configs + a generated-Kind-config unit assertion; gate
  negative-tested)
- doc statement of the edge (30090, Keycloak+admin) vs. data-plane (30011/30080, loopback) split — **landed**
- the live host-worker loopback path succeeding while the edge requires an admin token

### Validation
- `infernix lint chart` rejects a non-loopback Kind binding (negative-tested) and passes on the committed
  configs; unit suite green; host-worker service-loop green while a non-admin edge request is denied

### Remaining Work
None.

## Sprint 9.5: Admin operator-ribbon gating + cluster-wide monitoring panel [Done]

**Status**: Done
**Implementation**: `web/src/index.html`, `src/Infernix/Demo/Api.hs`, `web/src/Main.purs`,
`web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/DashboardTransport.purs`,
`web/src/Infernix/Web/Router.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`

### Objective
Hide cluster-wide surfaces from non-admins and give admins an in-app cluster-wide panel (engine/pod
health, catalog size, all-user counts, runtime/substrate/dispatch).

### Deliverables
- SPA hides the operator ribbon from non-admins through `AppState.isAdmin` and the application
  renderer; the shell marks the surface hidden before the compiled module mounts
- admin-gated `GET /api/admin/overview` endpoint (`withAdminRequest`) returning real cluster-wide
  aggregates (substrate, dispatch mode, catalog/engine-pool sizes, coordinator-visible model-cache
  manifest count, and the count of distinct `users/<sub>/` object prefixes), covered by the
  governed unit suite
- admin cluster-wide panel (`#admin-panel`, reads `/api/admin/overview`) plus the platform summary
  grid are rendered from the same state transition as the signed-in gate: Runtime, Control Plane,
  Daemon, Dispatch, Edge, and `#admin-panel` are admin-only, while Catalog, Connection, and the
  personal dashboard remain visible to every authenticated user
- the in-memory access token derives the presentation-only admin dimension; the edge
  `SecurityPolicy` and backend `withAdminRequest` remain the authorization boundaries

### Validation
- unit + build green; admin sees panel/ribbon and the cluster-summary cells; non-admin does not
  (e2e, Sprint 9.8)

### Remaining Work
None.

## Sprint 9.6: User personal dashboard [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/FilesTransport.purs`,
`src/Infernix/Demo/Api.hs` (existing `handleObjectsList`)
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`

### Objective
Every user gets a dashboard scoped strictly to their own data (own artifacts / objects), reusing the
existing per-user `/api/objects/list`. No cluster-wide data.

### Deliverables
- the personal dashboard is a second rendering of the Files view's application state and therefore
  uses the same authenticated `/api/objects/list` transport
- `handleObjectsList` scopes the listing server-side to the caller's verified `users/<sub>/` prefix,
  so dashboard disjointness is independent of the presentation renderer

### Validation
- routed e2e: a second user sees a disjoint set (Sprint 9.8)

### Remaining Work
None.

## Sprint 9.7: Per-user MinIO STS defense-in-depth [Done]

**Status**: Done
**Implementation**: `src/Infernix/Objects/Sts.hs`, `src/Infernix/Objects/Presigned.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/ClusterConfig.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/tools/minio.md`, `documents/architecture/tenant_isolation_doctrine.md`, `documents/engineering/object_storage.md`, `documents/engineering/cluster_config_manifest.md`

### Objective
Add a per-user MinIO STS credential keyed to `users/<sub>/` behind the object-proxy (defense-in-depth;
retire the single-shared-root-credential-as-only-isolation posture). No user-facing MinIO console
(Files-tab decision).

### Deliverables
- per-user session policy + STS `AssumeRole` scoped-credential minting + session-token presigning +
  object-proxy wiring, now **default-on** (`cluster.minio.stsPerUser = True`), so the shared root
  credential is not the sole boundary — **landed** (unit-covered) and cohort live-validated

### Validation
- unit: session policy scopes to `users/<sub>/*`, the signed `AssumeRole` request and response parse are
  correct, session-token presigning threads `X-Amz-Security-Token`; build/style/check-code green.
- with `stsPerUser = True` on the live cluster, upload / list / download succeed through the
  scoped credential and cross-user access is denied (403), on both cohorts.

### Remaining Work
None.

## Sprint 9.8: RBAC + dashboard + lifecycle e2e [Done]

**Status**: Done
**Implementation**: `web/playwright/inference.spec.js`
**Docs to update**: `documents/engineering/testing.md`, `documents/development/demo_app_test_plan.md`

### Objective
Prove the admin/user split and the account lifecycle end-to-end, and flip the existing tests that
currently assert the *old* (any-user-sees-operator-consoles) behavior.

### Deliverables
- admin token: operator ribbon + admin panel render; `/registry`, `/pulsar/admin`,
  `/pulsar/ws`, `/api/cache/*`, `/api/admin/overview` → 2xx
- non-admin token: ribbon + panel absent; same routes → 403 (replaces `expectOperatorRibbon` at
  `inference.spec.js:130` and `expectJwtGatedOperatorRoute` at `:177-178`)
- personal dashboard shows only the caller's data; cross-user 403 stays green
- lifecycle additions: returning-user password sign-in, wrong-password negative, post-deletion auth loop
- platform-state DOM assertions (`#runtime-mode`, `#edge-port`, …)

### Validation
- `node --check web/playwright/inference.spec.js` green (spec parses); routed Playwright on the
  selected accelerator plus `linux-cpu`

### Remaining Work
None.

## Sprint 9.9: Keycloak SSO logout and admin account switching [Done]

**Status**: Done — implemented and validated.
**Implementation**: `web/src/Infernix/Web/Auth.js`, `web/src/Infernix/Web/Auth.purs`,
`web/src/Main.purs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/access_control_doctrine.md`,
`documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`,
`documents/development/demo_app_test_plan.md`, `DEVELOPMENT_PLAN/README.md`, `00-overview.md`,
`system-components.md`, `cohort-validation-waves.md`

### Objective
Make Sign out terminate both local SPA state and the upstream Keycloak SSO browser session, so users
can intentionally switch from a regular self-registered account to the separate admin login.

### Deliverables
- Keycloak logout redirect from the Sign out button after local app cleanup.
- `id_token_hint` threading from the token response into the logout redirect.
- Routed Playwright regression for non-admin sign-out followed by admin sign-in.

### Validation
- Machine-independent gates: PureScript/web unit build, `node --check web/playwright/inference.spec.js`,
  `infernix test lint`, `infernix lint docs`, and `infernix docs check`.
- Cohort gate: the routed Playwright auth/RBAC lifecycle on `linux-cpu` plus the selected
  accelerator is complete.

### Remaining Work
None.

## Sprint 9.10: Admin-Token and Object-Storage Session Leases [Done]

**Status**: Done — implemented and validated.
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`
**Blocked by**: nothing — Sprints 4.28 and 7.29 are closed.
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the
phase's existing engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: model the Keycloak
admin credential as a `withValidAdminToken` region lease that re-derives the bearer at each admin
call, and model the per-user MinIO STS session as a leased `StsSession` value; capability-gate the
admin and object-proxy surfaces on these leases. For every state `S` the operation requires the
typed evidence `E(S)` produced by its transition — encoding evidence, not hope — generalizing the
results-side realness contract to state transitions. See the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `withValidAdminToken` (`src/Infernix/Cluster.hs`) is a rank-2 region lease over the Sprint 1.16
  `Infernix.Evidence.Lease` kernel: it re-derives the Keycloak admin bearer at entry and confines the
  `KeycloakAdminToken` to the continuation scope, so the raw credential is never returned, stashed,
  or held past the admin operation's validity window. The realm reconcile runs inside the lease and
  reads the bearer via `leasePayload`, re-deriving a fresh bearer on each reconcile.
- The per-user MinIO STS session is a typed leased `StsSession` value (`src/Infernix/Demo/Api.hs`):
  the constructor is unexported and the only mint is `loadUserScopedMinioPresignedConfig`, so the
  scoped credential is carried as typed evidence rather than a bare mutable token.
- Capability-gate on the admin surface and the object-proxy surface: each operation requires the
  corresponding lease evidence to be constructed before it can act. The object-proxy handlers read
  the scoped presigned config through `stsSessionPresignedConfig`, so an object operation acts only
  on an established session.

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint
  docs`, and (for any Python/native change) `poetry run check-code`, exercised on both the
  apple-silicon and linux-cpu lanes.

### Remaining Work

None.

## Sprint 9.11: The Admin Gate Renders From Application State [Active]

**Status**: Active
**Code-side closure**: Complete — the governed native-arm64 `linux-cpu` build and unit suite plus
the routed `linux-cpu` browser suite pass.
**Cohort gate**: Wave 9.1 — selected current-source `linux-gpu` plus paired `linux-cpu`
`infernix test all` remain.
**Implementation**: `web/src/Main.purs`, `web/src/index.html`, `web/src/Infernix/Web/Auth.purs`,
`web/src/Infernix/Web/Auth.js`, `web/src/Infernix/Web/Browser.purs`,
`web/src/Infernix/Web/Browser.js`, `web/src/Infernix/Web/DashboardTransport.purs`,
`web/src/Infernix/Web/DashboardTransport.js`, `web/test/Infernix/Web/AuthSpec.purs`,
`web/playwright/inference.spec.js`
**Blocked by**: nothing.
**Docs to update**: none.

### Objective

The admin dimension is application state and the same renderer owns signed-in state, the operator
ribbon, cluster summary cells, cluster monitoring, and the personal dashboard. The HTML shell is a
static mount surface. Enforcement remains at the edge authorization rule, backend admin gate, and
server-side per-user scoping boundaries.

### Deliverables

- `AppState.isAdmin` derives from the in-memory Keycloak access token and renders through the same
  path as the other authentication states
- the admin overview transport and the Files-backed personal dashboard update typed application
  state; focus, visibility restoration, and the bounded refresh loop dispatch one application action
- `index.html` contains no cookie-driven detector, panel script, or dashboard fetch
- the cleanup ledger contains no row for the retired shell gate

### Validation

- governed native-arm64 `linux-cpu` image build and `infernix test unit`, including 86/86 web tests
- routed native-arm64 `linux-cpu` `infernix test e2e`: 16/16 browser tests, including admin,
  non-admin, personal-dashboard isolation, authentication lifecycle, and every catalog model
- `infernix lint files|docs|chart|proto`, `infernix docs check`, and `infernix lint plan`
- cohort: Wave 9.1 selected `linux-gpu` plus paired `linux-cpu` full suites

### Remaining Work

Validation-only: Wave 9.1 retains selected current-source `linux-gpu` plus paired `linux-cpu`
`infernix test all` against one frozen Phase 9 state.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` — operator routes are admin-authorized; loopback data-plane NodePorts are trust-boundary-internal, localhost-only, un-gated
- `documents/engineering/testing.md` — the RBAC/dashboard/lifecycle e2e contract

**Product or architecture docs to create/update:**
- `documents/architecture/access_control_doctrine.md` (new, Authoritative source) — admin/user role model, Keycloak claim mapping, the edge-vs-data-plane enforcement split, and the "admins see cluster-wide, users see only their own data" invariant
- `documents/architecture/web_ui_architecture.md` — operator ribbon admin-gated; admin panel + personal dashboard surfaces
- `documents/architecture/daemon_topology.md` — Apple host-worker loopback data-plane path
- `documents/architecture/demo_app_design.md` — admin/personal dashboard bindings
- `../documents/architecture/managed_state_transitions.md` — the Managed-State-Transition Doctrine
  this phase now references for the Sprint 9.10 admin-token and object-storage session leases

**Cross-references to add:**
- register Phase 9 in `development_plan_standards.md` Section E, `DEVELOPMENT_PLAN/README.md`, `00-overview.md`, `system-components.md`, and root `README.md`
- add the retired auth-only-operator-gate + unconditional-ribbon posture to `legacy-tracking-for-deletion.md`
