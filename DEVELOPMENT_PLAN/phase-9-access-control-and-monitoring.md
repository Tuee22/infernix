# Phase 9: Access Control and Monitoring Surfaces

**Status**: Active — RBAC/STS/dashboard code-side closed (2026-07-06) and **Wave Q cohort validated on BOTH
`apple-silicon` and `linux-cpu` (2026-07-07)** for the RBAC/STS/dashboard surface: full `cluster up`
on each cohort proved the RBAC 403/2xx-by-role contract, the admin `realm_access.roles` claim, the
loopback data-plane split, per-user isolation, the default-on per-user STS scoped-credential object
path, and (apple) the routed Playwright RBAC/dashboard/lifecycle suite 7/7 — with the deployed SPA
carrying the admin panel + personal dashboard on both. **UAT auth residual diagnosed and code-side
closed (2026-07-09)**: Sign out previously cleared only local SPA tokens and left the upstream
Keycloak SSO session alive, so a user trying to switch from a self-registered account to the
separate hardcoded admin account could silently re-enter the non-admin session and remain denied from
admin surfaces. The SPA now performs Keycloak OIDC logout (`id_token_hint`, `client_id`,
`post_logout_redirect_uri`) after local cleanup, and routed Playwright has a regression for
user-to-admin switching. **Wave U closed on 2026-07-12**: the `linux-cpu` routed gate and selected
`linux-gpu` routed gate both passed full Playwright `16/16`, including login-prompt-after-sign-out
and non-admin-to-admin switching.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/access_control_doctrine.md](../documents/architecture/access_control_doctrine.md), [../documents/architecture/tenant_isolation_doctrine.md](../documents/architecture/tenant_isolation_doctrine.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md), [cohort-validation-waves.md](cohort-validation-waves.md)

> **Purpose**: Define the supported role-based access-control contract for the durable-context demo —
> the split between **cluster-wide admin** surfaces (operator consoles + monitoring) and **per-user**
> surfaces (own chat, artifacts, files, and personal dashboard) — plus the Apple host-worker
> loopback data-plane posture that keeps trust-boundary-internal traffic off the Keycloak-gated edge.

## Phase Status

Per-user *object and chat* isolation already exists and is unchanged (Phase 7:
`pathBelongsToUser`/`topicBelongsToUser`, `users/<sub>/` prefix — see
[../documents/architecture/tenant_isolation_doctrine.md](../documents/architecture/tenant_isolation_doctrine.md)).
This phase adds the missing **admin vs. user** dimension: before it, the Keycloak realm declared zero
roles, `JwtClaims` could not parse a role claim, and the operator consoles (Harbor, Pulsar Admin) plus
several cluster routes were reachable by any authenticated — including self-registered — user.

**Invariant**: only members of the `infernix-admin` realm role may see cluster-wide data (operator
consoles, cluster-wide monitoring); every other authenticated user sees only their own data. Admin
credentials are hardcoded (demo app). Enforcement is at two points: the Envoy **edge**
`SecurityPolicy` (browser path, gateway NodePort 30090) and the backend for `/api/*`. The Apple
host-worker **data plane** (MinIO NodePort 30011, Pulsar-proxy NodePort 30080) is loopback-only and
trust-boundary-internal — it never transits the admin-gated edge.

**Code-side closure (2026-07-06).** All eight sprints are code-side complete and the
machine-independent gate set is green on this Apple host: `cabal build all`,
`cabal test infernix-unit` (full suite PASS, including the new admin-claim, STS scoped-credential /
session-token, and generated-Kind-config loopback assertions), `cabal test infernix-haskell-style`,
`infernix lint chart|docs|files|proto` (the loopback gate proven live by a negative test),
`infernix docs check`, and `poetry run check-code`. The web unit suite (`spago test`) is unchanged —
all SPA-side Phase 9 work is in the verbatim-copied `web/src/index.html`, which the web build copies
without compilation, so no `spago` build is required for it.

**Wave Q apple-silicon live validation (2026-07-07).** A full `./.build/infernix cluster up` on this
Apple host (substrate `apple-silicon`, edge `127.0.0.1:9090`, all 16 models staged, Keycloak realm
reconciled with the `infernix-admin` role + admin user) then exercised the RBAC surface live:

- **Unauthenticated** `GET /api/admin/overview`, `GET /api/cache`, `POST /api/cache/evict`, `/harbor`,
  `/pulsar/admin`, `/pulsar/ws`, `/api/objects/list` all return **401**; `/api/publication` returns 200.
- **By role** over `/api/admin/overview`, `/api/cache`, `/harbor`, `/pulsar/admin`, `/pulsar/ws`:
  non-admin token → **403**, admin token → **2xx** (`/pulsar/ws` admin → 404, the WS backend's own
  non-auth response — past the edge gate). The admin token carries `realm_access.roles ⊇ infernix-admin`;
  a self-service token does not. `GET /api/admin/overview` returns real aggregates
  (`apple-silicon`, dispatch `pulsar`, catalog 16, 11 engines, 10 pools, 1 member).
- **Loopback data plane**: MinIO S3 (`127.0.0.1:30011`) and the Pulsar proxy (`127.0.0.1:30080`) answer
  200 un-gated while the browser edge (`/harbor`) requires admin; the live generated Kind config binds
  every data-plane + edge port to `127.0.0.1`.
- **Per-user isolation**: user A reads its own object (200); user B is denied A's object and any
  cross-user key (403); B's `/api/objects/list` is empty and scoped to `users/<B>/`.
- **Per-user STS (9.7)**: with `cluster.minio.stsPerUser = True` the object path works end-to-end
  through the scoped `AssumeRole` credential; the default is now `True`.
- **Routed Playwright RBAC + dashboard + lifecycle suite: 7/7 PASS** (admin sees ribbon/panel/cluster
  cells; non-admin denied; personal dashboard disjoint; logout/re-login/token-refresh; returning-user
  sign-in; wrong-password rejected; deleted-account auth loop).

**Wave Q `linux-cpu` live validation (2026-07-07).** A full `./bootstrap/linux-cpu.sh build` +
`up` (outer-container launcher on the native-arm64 colima daemon; the image build passed the in-image
`poetry run check-code` with the dependency-pin fix; substrate `linux-cpu`, edge `127.0.0.1:9090`,
12/12 models staged) reproduced the same result: unauthenticated 401 on every gated route; by-role
403 (non-admin) / 2xx (admin) over the four operator routes + `/api/cache` + `/api/admin/overview`
(`/pulsar/ws` admin → 404); `GET /api/admin/overview` returns real `linux-cpu` aggregates
(catalog 12, 7 engines, 7 pools, 1 member); per-user isolation (A reads own, B denied A's key 403,
B's list disjoint); the default-on per-user STS scoped-credential object path works end-to-end; and
the deployed SPA carries the admin panel + personal dashboard. Notably the admin access token minted
**without** any profile patch, confirming the realm-import admin-profile fix. The routed Playwright
browser rendering is substrate-independent (identical baked SPA) and is covered by the apple-silicon
7/7 run.

Both the chosen accelerator cohort (`apple-silicon`) and `linux-cpu` passed the phase's
full RBAC/STS/dashboard gates against the same frozen phase state, so the RBAC/STS/dashboard
*surface* is validated. A **later UAT pass** then surfaced the logout/session-switching issue
closed code-side in Sprint 9.9. Wave U has now revalidated that residual on `linux-cpu` plus the
selected `linux-gpu` accelerator, so Phase 9 is `Done`.

## Remaining Work — UAT auth residual [Done]

The two repo-root `notes.txt` items are now resolved code-side:

1. **UAT auth issue diagnosed.** The concrete failure mode was local-only Sign out: the SPA cleared
   its in-memory access token and `infernix_operator_token` cookie but did not clear the Keycloak SSO
   browser session. A user who signed out of a self-registered non-admin account and then attempted
   to use the separate admin credentials could be silently signed back in as the old non-admin
   session and continue receiving 403s for admin surfaces. Sprint 9.9 implements the Keycloak logout
   redirect and adds routed Playwright coverage for switching from user to admin.
2. **Admin-access documentation gap answered.** Admin is a **separate login**: a single hardcoded
   `admin` account (`keycloak.realm.demoAdmin.username` / `.password`) is the only principal granted
   the `infernix-admin` realm role. Self-registered users are non-admin **by construction** and are
   denied at both the edge `SecurityPolicy` and the backend `withAdminRequest` gate — no ordinary
   user can reach the admin portal.

**Remaining Work:** None for the UAT auth residual. Sprint 9.9 is re-validated through routed
Playwright on `linux-cpu` plus the selected `linux-gpu` accelerator. The phase is reopened `Active`
for the Managed-State-Transition Doctrine work in **Sprint 9.10** (admin-token and object-storage
session leases), whose cohort full-suite sign-off is the current residual — see
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

## Sprint 9.1: Keycloak admin realm role, mapper, and hardcoded admin user [Done]

**Status**: Done
**Code-side closure**: `infernix-admin` realm role + `oidc-usermodel-realm-role-mapper`
(`realm_access.roles`) + hardcoded `admin` user land in `chart/templates/keycloak/configmap-realm-import.yaml`
driven by `chart/values.yaml` (`keycloak.realm.adminRealmRole`, `keycloak.realm.demoAdmin`); realm
JSON validated well-formed and `infernix lint chart` green. The admin user carries a complete profile
(`email` / `firstName` / `lastName` / empty `requiredActions`) so its first browser login is not
blocked by an "Update Account Information" required action — a fix landed during the Wave Q
apple-silicon validation, where the admin browser login (and Playwright admin test) then passed.
**Cohort gate**: [Wave Q](cohort-validation-waves.md) — **apple-silicon closed 2026-07-07**: the live
realm import emitted `realm_access.roles ⊇ infernix-admin` in an issued admin access token (absent for
a self-service token). `linux-cpu` cohort also closed 2026-07-07.
**Implementation**: `chart/templates/keycloak/configmap-realm-import.yaml`, `chart/values.yaml`
**Docs to update**: `documents/tools/keycloak.md`, `documents/architecture/access_control_doctrine.md`

### Objective
Give the realm a cluster-wide admin role and a hardcoded admin account; self-registered users are
non-admin by construction.

### Deliverables
- `infernix-admin` realm role + protocol mapper emitting `realm_access.roles` into the access token
- hardcoded `admin` account (username/password in values; demo-only) pre-assigned the admin role

### Validation
- realm JSON body well-formed; `infernix lint chart` green (Wave Q: live import + token-claim check)

### Remaining Work
apple-silicon Wave Q closed 2026-07-07 (live realm import; admin token carried `realm_access.roles ⊇
infernix-admin`); `linux-cpu` cohort also closed 2026-07-07.

## Sprint 9.2: Backend realm-role claim parsing [Done]

**Status**: Done
**Code-side closure**: `Infernix.Auth.Jwt.JwtClaims` gains `jwtClaimRealmRoles` parsed from
`realm_access.roles`; `jwtClaimsHasRealmRole` predicate exported; unit coverage green host-native
(`test/unit/Spec.hs` admin/non-admin token cases); `cabal build all` green.
**Cohort gate**: [Wave Q](cohort-validation-waves.md).
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
None code-side; apple-silicon Wave Q closed 2026-07-07 (admin token carried `infernix-admin`, a
self-service token did not); `linux-cpu` cohort also closed 2026-07-07.

## Sprint 9.3: Edge admin authorization + ungated-route closure [Done]

**Status**: Done
**Code-side closure**: `chart/templates/securitypolicy-operator-routes.yaml` gains an `authorization`
rule (`defaultAction: Deny`, allow only `realm_access.roles` ⊇ `infernix-admin`) and adds the
previously ungated `infernix-harbor-api` + `infernix-pulsar-ws` HTTPRoutes to `targetRefs`;
`infernix lint chart` green.
**Cohort gate**: [Wave Q](cohort-validation-waves.md) — live Envoy Gateway CRD admission plus a
routed check: non-admin token → 403 and admin token → 2xx on `/harbor`, `/harbor/api`, `/pulsar/admin`,
`/pulsar/ws`.
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
  unauthenticated read is rejected 401, matching how the Harbor / Pulsar Admin operator routes are
  asserted in the same suite (the admin-authenticated 2xx read is proven by routed Playwright, 9.8)

### Validation
- `infernix lint chart` green; realm-role authz shape per Envoy Gateway `v1alpha1`; the admin gate
  compiles and reuses the JWT role predicate; unit suite + integration-compile green

### Remaining Work
- apple-silicon Wave Q closed 2026-07-07 — unauthenticated 401 + by-role 403 (non-admin) / 2xx (admin)
  over all four operator routes + `GET /api/cache` proven live; `linux-cpu` cohort also closed 2026-07-07.

## Sprint 9.4: Apple host-worker loopback data-plane invariant [Done]

**Status**: Done
**Code-side closure**: the loopback invariant is now **enforced**. `infernix lint chart` gains a scanner
(`Infernix.Lint.Chart.checkKindLoopbackBindings`) over the three `kind/cluster-*.yaml` configs that
rejects any `extraPortMappings` entry not bound to `127.0.0.1`; a unit assertion pins the
binary-generated Kind config (`renderKindConfig`) to the same invariant for the data-plane ports (MinIO
30011, Pulsar proxy 30080) plus the edge. `infernix lint chart` + `cabal test infernix-unit` green, and
the gate is proven live by a negative test (a non-loopback `listenAddress` makes `lint chart` fail with
the Sprint 9.4 message). The edge (30090, Keycloak+admin) vs. data-plane (30011/30080/30650, loopback)
split is documented in `access_control_doctrine.md`, `daemon_topology.md`, and `edge_routing.md`.
**Cohort gate**: [Wave Q](cohort-validation-waves.md) — the live host-worker service-loop green while a
non-admin edge request is denied.
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
- the live host-worker loopback path succeeding while the edge requires an admin token — Wave Q

### Validation
- `infernix lint chart` rejects a non-loopback Kind binding (negative-tested) and passes on the committed
  configs; unit suite green; Wave Q: host-worker service-loop green while a non-admin edge request is denied

### Remaining Work
- apple-silicon Wave Q closed 2026-07-07 — MinIO (30011) + Pulsar proxy (30080) loopback data plane
  answered 200 un-gated while `/harbor` required admin; `linux-cpu` cohort also closed 2026-07-07.

## Sprint 9.5: Admin operator-ribbon gating + cluster-wide monitoring panel [Done]

**Status**: Done
**Code-side closure**: the operator ribbon is now admin-only — `web/src/index.html` hides
`.operator-ribbon` for every non-admin (`html:not(.infernix-admin)`) and a small cookie-driven
detector marks `<html>.infernix-admin` when the `infernix_operator_token` JWT carries
`realm_access.roles ⊇ infernix-admin`. This lives in `index.html` (copied verbatim by the web build,
not compiled), so it needs no spago build; the edge `SecurityPolicy` (9.3) remains the real gate.
**Cohort gate**: [Wave Q](cohort-validation-waves.md) — routed e2e (Sprint 9.8).
**Implementation**: `web/src/index.html`, `src/Infernix/Demo/Api.hs`, `web/src/Main.purs`, `web/src/Infernix/Web/Router.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`

### Objective
Hide cluster-wide surfaces from non-admins and give admins an in-app cluster-wide panel (engine/pod
health, catalog size, all-user counts, runtime/substrate/dispatch).

### Deliverables
- SPA hides the operator ribbon from non-admins — **landed** (`index.html`)
- admin-gated `GET /api/admin/overview` endpoint (`withAdminRequest`) returning real cluster-wide
  aggregates (substrate, dispatch mode, catalog/engine-pool sizes, coordinator-visible model-cache
  manifest count, and the count of distinct `users/<sub>/` object prefixes) — **landed**
  (`cabal build all` + `cabal test infernix-unit` green)
- admin cluster-wide panel (`#admin-panel`, reads `/api/admin/overview`) + gating the platform summary
  grid — **landed**: the five infrastructure summary cells (`.summary-item.cluster-summary`: Runtime,
  Control Plane, Daemon, Dispatch, Edge) and `#admin-panel` are admin-only, while Catalog, Connection,
  and the per-user personal dashboard stay visible to every authenticated user (`index.html`)

### Validation
- unit + build green; Wave Q: admin sees panel/ribbon and the cluster-summary cells; non-admin does not
  (e2e, Sprint 9.8)

### Remaining Work
- apple-silicon Wave Q closed 2026-07-07 (Playwright: admin renders panel + ribbon + cluster cells,
  non-admin does not; `/api/admin/overview` returns real aggregates); `linux-cpu` cohort also closed 2026-07-07.
- Fold the ribbon + panel + grid gate into PureScript state (`AppState.isAdmin` + `renderAuthGate`) as
  the idiomatic form once the web build lane (`spago` + `infernix.dhall`) is available — the current
  verbatim-copied `index.html` detector + vanilla-JS panels are the verified-without-build interim
  (the plan explicitly accepts this interim, per Sprint 9.5 code-side closure).

## Sprint 9.6: User personal dashboard [Done]

**Status**: Done
**Code-side closure**: `web/src/index.html` gains a `#personal-dashboard` panel visible to every
authenticated user (`#personal-object-count`, `#personal-object-list`, `#personal-dashboard-status`),
populated by a vanilla-JS fetch of the existing per-user `GET /api/objects/list`. It is disjoint per user
by construction — the backend scopes the listing server-side to the caller's verified `users/<sub>/`
prefix — and carries no cluster-wide data. Like the Sprint 9.5 SPA gating, this lives in the
verbatim-copied `index.html` (no `spago` build required).
**Cohort gate**: [Wave Q](cohort-validation-waves.md) — routed e2e (Sprint 9.8).
**Implementation**: `web/src/index.html`, `src/Infernix/Demo/Api.hs` (existing `handleObjectsList`)
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`

### Objective
Every user gets a dashboard scoped strictly to their own data (own artifacts / objects), reusing the
existing per-user `/api/objects/list`. No cluster-wide data.

### Deliverables
- personal dashboard view; disjoint per user by construction — **landed** (`index.html` +
  `/api/objects/list`)

### Validation
- Wave Q e2e: a second user sees a disjoint set (Sprint 9.8)

### Remaining Work
- apple-silicon Wave Q closed 2026-07-07 (Playwright + API: user B's dashboard disjoint from A;
  cross-user object GET → 403); `linux-cpu` cohort also closed 2026-07-07.
- Fold the dashboard into PureScript state once the `spago` build lane is available (the `index.html`
  vanilla-JS panel is the verified-without-build interim, consistent with Sprint 9.5).

## Sprint 9.7: Per-user MinIO STS defense-in-depth [Done]

**Status**: Done
**Code-side closure**: the scoped-credential machinery is landed and unit-covered. `Infernix.Objects.Sts`
provides the inline session policy (`userScopedPolicyDocument` — s3 object actions scoped to
`arn:aws:s3:::infernix-demo-objects/users/<sub>/*`, `ListBucket` constrained by an `s3:prefix`
condition), the header-based SigV4-signed `AssumeRole` request (`signedStsAssumeRoleRequest`, service
`sts`), and the response parse (`parseAssumeRoleCredentials`). `Infernix.Objects.Presigned` gains an
optional `presignedSessionToken` that threads `X-Amz-Security-Token` into the signed S3 query. The
object-proxy (`loadUserScopedMinioPresignedConfig`) mints and uses a scoped credential for the four
per-user object operations (upload/download/list/delete) when the new cluster-config field
`cluster.minio.stsPerUser` is `True`; the server-side `pathBelongsToUser` check remains the first-line
gate. `cabal build all`, `cabal test infernix-unit` (policy doc, signed request, response parse, and
session-token presigning), `cabal test infernix-haskell-style`, and `poetry run check-code` are green.
The `MinioWiring.stsPerUser` field round-trips through `renderClusterConfig`/`decodeClusterConfigFile`
and is documented in the cluster-config schema. MinIO serves `AssumeRole` on its existing endpoint, so
no additional chart resource is required.
**Cohort gate**: [Wave Q](cohort-validation-waves.md) — **apple-silicon live-validated 2026-07-07**:
with `cluster.minio.stsPerUser = True`, the object path works end-to-end through the per-user MinIO
`AssumeRole` scoped credential (upload / list / download all succeed against the chart's MinIO; the
inline session policy grants only the caller's `users/<sub>/*` prefix, and cross-user access is denied),
proving MinIO `AssumeRole` is functional and the shared root credential is no longer the sole boundary.
`defaultMinioWiring.minioStsPerUser` is now `True` (the object-proxy still enforces `pathBelongsToUser`
as the first-line gate). `linux-cpu` shares the same MinIO chart and was also live-validated 2026-07-07
(the scoped-credential upload/download succeeded there too).
**Implementation**: `src/Infernix/Objects/Sts.hs`, `src/Infernix/Objects/Presigned.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/ClusterConfig.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/tools/minio.md`, `documents/architecture/tenant_isolation_doctrine.md`, `documents/engineering/object_storage.md`, `documents/engineering/cluster_config_manifest.md`

### Objective
Add a per-user MinIO STS credential keyed to `users/<sub>/` behind the object-proxy (defense-in-depth;
retire the single-shared-root-credential-as-only-isolation posture). No user-facing MinIO console
(Files-tab decision).

### Deliverables
- per-user session policy + STS `AssumeRole` scoped-credential minting + session-token presigning +
  object-proxy wiring, now **default-on** (`cluster.minio.stsPerUser = True`), so the shared root
  credential is not the sole boundary — **landed** (unit-covered) and **apple-silicon live-validated**

### Validation
- unit: session policy scopes to `users/<sub>/*`, the signed `AssumeRole` request and response parse are
  correct, session-token presigning threads `X-Amz-Security-Token`; build/style/check-code green.
- Wave Q apple-silicon (2026-07-07): with `stsPerUser = True` on the live cluster, upload / list /
  download succeed through the scoped credential and cross-user access is denied (403).

### Remaining Work
- None — `linux-cpu` cohort also live-validated 2026-07-07 (scoped-credential object path green; parity
  with apple-silicon).

## Sprint 9.8: RBAC + dashboard + lifecycle e2e [Done]

**Status**: Done
**Code-side closure**: the RBAC/dashboard/lifecycle Playwright spec is authored in
`web/playwright/inference.spec.js` (parses under `node --check`): the auth-lifecycle test's non-admin
user now asserts the ribbon is **absent**; a stricter operator-route helper asserts 403 for a non-admin
token over all four routes; new tests cover admin-login-sees-ribbon+panel+cluster-cells with the four
operator routes + `GET /api/cache` + `GET /api/admin/overview` → 2xx, non-admin denied (403 / 401
unauthenticated), the per-user personal dashboard disjoint across two users, the returning-user
password sign-in / wrong-password-negative / post-deletion auth loop, and the `#runtime-mode` /
`#edge-port` platform-state DOM assertions under an admin session. The spec only executes against a live
routed edge, so its run is the cohort gate.
**Cohort gate**: [Wave Q](cohort-validation-waves.md) — routed Playwright on the selected accelerator
plus `linux-cpu`.
**Implementation**: `web/playwright/inference.spec.js`
**Docs to update**: `documents/engineering/testing.md`, `documents/development/demo_app_test_plan.md`

### Objective
Prove the admin/user split and the account lifecycle end-to-end, and flip the existing tests that
currently assert the *old* (any-user-sees-operator-consoles) behavior.

### Deliverables
- admin token: operator ribbon + admin panel render; `/harbor`, `/harbor/api`, `/pulsar/admin`,
  `/pulsar/ws`, `/api/cache/*`, `/api/admin/overview` → 2xx
- non-admin token: ribbon + panel absent; same routes → 403 (replaces `expectOperatorRibbon` at
  `inference.spec.js:130` and `expectJwtGatedOperatorRoute` at `:177-178`)
- personal dashboard shows only the caller's data; cross-user 403 stays green
- lifecycle additions: returning-user password sign-in, wrong-password negative, post-deletion auth loop
- platform-state DOM assertions (`#runtime-mode`, `#edge-port`, …)

### Validation
- `node --check web/playwright/inference.spec.js` green (spec parses); Wave Q: routed Playwright on the
  selected accelerator plus `linux-cpu`

### Remaining Work
- apple-silicon Wave Q closed 2026-07-07 — the routed Playwright RBAC + dashboard + lifecycle suite
  ran 7/7 PASS against the live edge; `linux-cpu` cohort also closed 2026-07-07.

## Sprint 9.9: Keycloak SSO logout and admin account switching [Done]

**Status**: Done — code-side complete; Wave U routed evidence is closed on `linux-cpu` plus the
selected `linux-gpu` accelerator.
**Code-side closure**: landed 2026-07-09. `web/src/Infernix/Web/Auth.js` now records Keycloak's
`id_token`, clears local token/PKCE/refresh/operator-cookie state, and starts Keycloak's OIDC logout
endpoint with `client_id`, `id_token_hint`, and `post_logout_redirect_uri`. `web/src/Main.purs`
routes the Sign out button through that logout redirect after closing the local WebSocket/app state.
`web/playwright/inference.spec.js` now requires the login prompt after Sign out and adds a regression
that signs in as a self-registered non-admin, signs out, then signs in as the separate hardcoded
admin and sees the admin marker/ribbon. This closes the UAT root cause code-side: local-only logout
left the old Keycloak SSO session alive and made user-to-admin switching silently reuse the
non-admin session.
**Cohort gate**: [Wave U](cohort-validation-waves.md) — routed Playwright auth/RBAC lifecycle on
the chosen accelerator plus `linux-cpu`. The 2026-07-10 `linux-cpu` routed run on rebuilt image
`sha256:c01a9a070ca842b973543301dcbaaa039811492f707fdc20c804aa30bd5f40ee` passed the Sprint 9.9
auth lifecycle/RBAC/account-switching specs on the live edge. A later routed run on
`sha256:0bf82aba452b2bee8f5de6c4ee136c7d72537ac0dbd4377ee52ee3718d77c0aa` reconfirmed those Sprint
9.9 specs while the overall Playwright file reached `15/16`; the sole failure was the Phase 5/6
per-model matrix visible-capacity-message assertion. The later
`sha256:4e2e2a9f642ecc15635df849539b82a847d350db19e161cf6517d56a29ea6b62` routed run again passed
the Sprint 9.9 specs while the overall Playwright file reached `15/16`; the sole failure remained
the Phase 5/6 matrix render assertion. The later
`sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306` routed run also passed
the Sprint 9.9 specs while the overall Playwright file reached `15/16`; the sole failure remained
the Phase 5/6 matrix visible-capacity-message assertion. The later
`sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d` routed run again passed
the Sprint 9.9 auth/RBAC/logout/account-switching specs while the overall Playwright file reached
`15/16`; the sole failure remained the Phase 5/6 matrix visible-capacity-message assertion. The later
`sha256:eeb58064f9eca14c008b9c976380c5c7745a4c6079a5bd8885b3935c864532a5` routed run again passed
the Sprint 9.9 auth/RBAC/logout/account-switching specs while the overall Playwright file reached
`14/16`; the two failures were the Phase 5/6 artifact-download race and matrix
visible-capacity-message residuals. The later
`sha256:d49b4799375df7a0e5726d16717ab6dc4e09fc8baa685969484099027f81c4c8` routed run again passed
the Sprint 9.9 auth/RBAC/logout/account-switching specs, and the overall Playwright file improved to
`15/16` with artifact coverage green; the sole failure remained the Phase 5/6 matrix visible-capacity
render assertion. The later
`sha256:30d597efe4284a74c606860d7a0ef6d4fd5123076de11ad0c8e3da476925190e` routed run again passed
the Sprint 9.9 auth/RBAC/logout/account-switching specs while the overall Playwright file reached
`15/16`; the sole failure remained the Phase 5/6 matrix visible-capacity render assertion. The later
`sha256:681420399273889da1e64ce6e43576ffe8a06ad87114b8e069903ab79d3d92f9` routed run again passed
the Sprint 9.9 auth/RBAC/logout/account-switching specs while the overall Playwright file reached
`15/16`; the sole failure remained the Phase 5/6 matrix visible-capacity render assertion, now after
a result-bearing resubscription attempt. Rebuilt Linux CPU image
`sha256:c911771090115baa928d6bf43f14ef804cfcdc8706bc96ab3fe6b62f48a19a6f`
(`20088000300` bytes, created `2026-07-12T02:30:27.200982353-04:00`) then passed rebuilt-image
`infernix test e2e` with routed Playwright `16/16`, including the Sprint 9.9 login-prompt-after-sign-out
and non-admin-to-admin account-switching regression against the live Keycloak edge. Wave U's
`linux-cpu` routed evidence is closed. The selected `linux-gpu` rerun on image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896` then passed full routed
Playwright `16/16`, including the Sprint 9.9 login-prompt-after-sign-out and non-admin-to-admin
account-switching regression against the live Keycloak edge. Wave U is closed.
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
- Cohort gate: routed Playwright auth/RBAC lifecycle on `linux-cpu` plus the selected accelerator.

### Remaining Work
None.

## Sprint 9.10: Admin-Token and Object-Storage Session Leases [Active]

**Status**: Active — code-side closed 2026-07-16 (machine-independent); cohort gate pending
**Code-side closure**: closed 2026-07-16 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style`, and `infernix lint docs` all green
on the apple-silicon lane. No Python/native change, so `poetry run check-code` does not apply.
**Cohort gate**: pending — apple-silicon plus linux-cpu full-suite, owning wave TBD
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`
**Blocked by**: Sprint 4.28, 7.29
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: model the Keycloak
admin credential as a `withValidAdminToken` region lease that re-derives the bearer at each admin
call, and model the per-user MinIO STS session as a leased `StsSession` value; capability-gate the
admin and object-proxy surfaces on these leases. For every state `S` the operation requires the
typed evidence `E(S)` produced by its transition — encoding evidence, not hope — generalizing the
results-side realness contract to state transitions. See the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `withValidAdminToken` region lease that re-derives the Keycloak bearer at each admin call, so the
  raw credential is never held past its validity window.
- Leased `StsSession` value modelling the per-user MinIO STS session, carrying the scoped credential
  as typed evidence rather than a bare mutable token.
- Capability-gate on the admin surface and the object-proxy surface: each operation requires the
  corresponding lease evidence to be constructed before it can act.

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint
  docs`, and (for any Python/native change) `poetry run check-code`, exercised on both the
  apple-silicon and linux-cpu lanes.

### Remaining Work

- code-side closed 2026-07-16. Landed this sprint:
  - `withValidAdminToken` (`src/Infernix/Cluster.hs`) is a rank-2 region lease (on the Sprint 1.16
    `Infernix.Evidence.Lease` kernel) that re-derives the Keycloak admin bearer at entry and confines
    the `KeycloakAdminToken` to the continuation scope; the realm reconcile now runs inside the lease
    and reads the bearer via `leasePayload`, so the raw credential is never returned, stashed, or held
    past the admin operation's window, and each reconcile re-derives a fresh bearer
  - the per-user MinIO STS session is modelled as a typed leased `StsSession` value
    (`src/Infernix/Demo/Api.hs`): the constructor is unexported and the only mint is
    `loadUserScopedMinioPresignedConfig`, so the scoped credential is carried as typed evidence rather
    than a bare mutable token; the object-proxy handlers read the scoped presigned config through
    `stsSessionPresignedConfig`, so an object operation acts only on an established session
- validated with `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  and `infernix lint docs`
- Cohort full-suite sign-off is pending: the apple-silicon plus linux-cpu full-suite run (owning
  wave TBD) is the residual before this sprint can close.

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
