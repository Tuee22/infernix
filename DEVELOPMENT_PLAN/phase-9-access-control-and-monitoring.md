# Phase 9: Access Control and Monitoring Surfaces

**Status**: Active — Sprints 9.12 add implementation and validation work to this phase's existing scope. No remediation code or new validation result is claimed by this documentation update.

**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/access_control_doctrine.md](../documents/architecture/access_control_doctrine.md), [../documents/architecture/tenant_isolation_doctrine.md](../documents/architecture/tenant_isolation_doctrine.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)

> **Purpose**: Define the supported role-based access-control contract for the durable-context demo —
> the split between **cluster-wide admin** surfaces (operator consoles + monitoring) and **per-user**
> surfaces (own chat, artifacts, files, and personal dashboard) — plus the Apple host-worker
> loopback data-plane posture that keeps trust-boundary-internal traffic off the Keycloak-gated edge.

## Phase Status

Sprints 9.1–9.11 retain their closed headings and only their established scope. Authenticated cache mutations can broaden malformed JSON or an invalid modelId to all local entries. Existing admin checks do not make that request decoding safe, and cache status reflects the marker-based cache implementation.

The existing Phase 9 row in [Recorded Attestations](cohort-validation-waves.md#recorded-attestations) is retained for the source and assertions it records; it does not close these new criteria.

Implementation follows the named code-side prerequisites below; pending accelerator scheduling alone does not block subsequent implementation. Remediation code-side closure is incomplete. The selected sign-off is `linux-gpu` plus native `linux-cpu`, recorded in Wave R9 in [cohort-validation-waves.md](cohort-validation-waves.md), against one frozen implementation. Neither lane has validated the new criteria. A pending wave is validation-only once the machine-independent gates pass.

## Current Repo Assessment

The Keycloak role boundary, application admin renderer, and tenant-scoped object APIs exist. Sprint 9.12 owns strict cache-request decoding and admin/tenant regressions against the real cache lifecycle from Sprint 4.50. Authentication, authorization, request validity, and mutation scope are separate checks; malformed authenticated input must not select every model.

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

**Scope boundary**: Credential use consumes domain-held authority under Sprint 1.46's lifetime contract; generic rank-2 IO does not itself prove delayed-action containment.

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

## Sprint 9.11: The Admin Gate Renders From Application State [Done]

**Scope boundary**: Admin UI rendering does not prove request decoding or actual cache mutation semantics. Sprint 9.12 owns those criteria.

**Status**: Done
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
- full current-source `infernix test all` on selected `linux-gpu` plus paired native-amd64
  `linux-cpu`, including 16/16 routed browser tests for the admin, non-admin, dashboard, auth, and
  catalog paths; see the Phase 9 [attestation](cohort-validation-waves.md#recorded-attestations)

### Remaining Work

None.

---

## Sprint 9.12: Reject Malformed Cache Mutations and Verify Actual Cache Authorization [Blocked]

**Status**: Blocked
**Code-side closure**: Strict request decoding and real-cache authorization regressions pending.
**Cohort gate**: Wave R9 — selected `linux-gpu` plus native `linux-cpu`.
**Blocked by**: Sprint 8.15 code-side closure; Sprint 4.50 provides actual cache lifecycle behavior.
**Implementation targets**: `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Cache.hs`, `src/Infernix/Auth/Jwt.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/access_control_doctrine.md`, `documents/architecture/tenant_isolation_doctrine.md`, `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/reference/api_surface.md`, `documents/engineering/model_lifecycle.md`

### Objective

Validate request scope before cache mutation and prove admin operations affect only their
explicit targets.

### Deliverables

- Decode eviction/rebuild bodies into a strict typed request: exactly `{}` explicitly selects all
  configured models within the authenticated cache owner's active runtime; an object containing
  only a nonempty known string `modelId` selects one. Empty body, JSON `null`, malformed JSON,
  wrong field types, empty/unknown model identity, arrays/scalars, and unknown fields yield
  HTTP 400 before selection or mutation. Never infer all-model scope from a decode failure.
- Retain separate authentication and admin-authorization gates for cache inspection and mutation.
  Apply requests to the verified engine-consumed cache from Sprint 4.50, with truthful results.
- Keep shared model-cache administration separate from tenant-owned conversation/object access.
  Assert admin status does not silently expand unrelated tenant data access.
- Remove decode-failure-to-all-models behavior through the removal ledger.

### Validation

- Independently exercise empty body, invalid JSON, JSON `null`, scalar/array bodies, wrong-type
  `modelId`, empty/unknown identity, and unknown fields. Assert HTTP 400 and unchanged cache
  identities for every invalid body. A valid `{}` request and a valid one-model object are
  separate positive scope controls.
- Test unauthenticated, ordinary-user, and admin requests for read, single-model eviction/rebuild,
  and explicit all-model scope. Verify status/error codes and actual artifact effects: selecting
  one model leaves another verified cache intact; malformed requests touch neither.
- A valid admin operation is the positive control and verifies usable cache state or an honest
  typed operation failure. MinIO durable source artifacts and tenant-owned objects remain intact.
- Recheck object/chat cross-user denial, per-user listings, dashboard isolation, token expiry,
  logout and account switching against the real backend and routed browser.
- Run governed build, aggregate lint/unit, focused docs/plan gates and Wave R9 against one frozen
  source/image pair. Existing access-control attestations do not prove malformed-request scope
  handling or real-cache mutation behavior.

### Remaining Work

Implement strict typed selection and actual-cache regressions, then retain Wave R9 evidence.

## Remaining Work

Implement Sprints 9.12, pass their governed machine-independent gates, and retain Wave R9's `linux-gpu` plus native `linux-cpu` full-suite results for the same frozen source. No remediation implementation or new cohort result is supplied by this documentation change. Closed sprint headings retain only their established scope; the follow-on criteria are the phase's outstanding work.

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

**Remediation documentation obligations:**

- Keep the contracts named by Sprints 9.12 prescriptive in `documents/`; implementation state and validation evidence stay in this plan.
- Document positive behavior, explicit refusal/unsupported behavior, resource and trust boundaries, and the independent controls that establish each claim.
- Keep [README.md](README.md), [cohort-validation-waves.md](cohort-validation-waves.md), and [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned with actual outstanding work; delete removal rows only after the named implementation surface is gone.
