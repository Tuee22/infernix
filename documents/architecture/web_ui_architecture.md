# Web UI Architecture

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define the demo UI topology, the contract boundary between the routed demo HTTP
> surface owned by `infernix-demo` and the PureScript browser application, and the gating model
> that keeps the demo surface absent from production deployments.

## Topology

The demo UI is a separate workload (`infernix-demo`) gated by the active `.dhall` `demo_ui` flag.
When the flag is off, the cluster has no `infernix-demo` pod and no demo HTTP surface at all.

When the flag is on:

- the browser loads `/` from the `infernix-demo` workload through the published routed surface
- the browser calls `/api`, `/api/publication`, `/api/cache`, and `/api/objects` on the same
  routed edge port; all of them are served by `infernix-demo`
- manual inference always enters through that clustered `infernix-demo` surface, but the daemon
  lane behind it is substrate-specific: the coordinator consumes request topics and forwards to
  derived engine-pool topics; Linux engines consume through Kubernetes pool workloads, and Apple
  host-native engines consume through host-daemon pool membership
- `/api/publication` exposes that distinction through `daemonLocation`,
  `inferenceExecutorLocation`, `inferenceDispatchMode`, and engine-pool routing metadata rather
  than a single host batch topic
- the visible catalog comes from the generated active-mode demo catalog rather than a
  hand-maintained UI allowlist

## Image Topology

`infernix` and `infernix-demo` share the default Cabal library exposed by the `infernix` package
and ship in the same runtime image family on the cluster path. The chart workload entrypoint
selects which executable runs where that executable is deployed.

On Apple Silicon, the cluster deploys `infernix-demo`, `infernix-coordinator`, and the
support-service stack, while the canonical Apple inference executor remains a host-native
`infernix service` process that consumes assigned pool/model topics. On Linux substrates, the demo workload,
coordinator, and engine run from the cluster-resident substrate image.

On Linux, the substrate image owns the web build prerequisites, the baked `web/dist/` bundle,
Playwright system packages, and the browser engines. Routed Playwright execution runs inside that
same image with `npm --prefix web exec -- playwright test`. On Apple Silicon, host-native routed
E2E uses host `npm exec` with the same typed fixture and is covered by the Apple cohort
validation batch.

## Landing Surface

The app shell is gated behind a Keycloak JWT. The `body` element carries
an `auth-unknown` / `auth-signed-out` / `auth-signed-in` class set by
`Main.purs.renderAuthGate` on every render pass from `state.authenticated`; CSS toggles two
mutually-exclusive top-level subtrees against that class:

- `.app-landing` — a single centred card with the `Infernix` wordmark, the subtitle
  `"Durable-context inference console"`, and two CTAs (primary `Sign in`, secondary
  `Create account`). Rendered when the body class is `auth-signed-out`.
- `.app-shell` — the existing header (summary grid + Chat / Artifacts tabs) plus the
  workspace and routes panel. Rendered when the body class is `auth-signed-in`.

The `auth-unknown` boot state hides both subtrees so neither flashes during the bootstrap
pass that reads the in-memory `TokenStore`. The inline `.app-shell` markup itself is
preserved so the existing imperative `captureRefs` bootstrap path against hardcoded DOM IDs
keeps working; the gate is purely a CSS visibility toggle.

## Authentication Entry Points

The landing card surfaces two OIDC Application Initiated Action (AIA) entry points against
the public client `infernix-spa` on realm `infernix`:

- `Sign in` → `Infernix.Web.Auth.beginLoginRedirect defaultInfernixRealmConfig` — builds
  the standard PKCE authorization-code redirect (`?response_type=code&code_challenge=...`)
  and lands the user on Keycloak's login form.
- `Create account` → `Infernix.Web.Auth.beginRegisterRedirect defaultInfernixRealmConfig` —
  same PKCE setup, but appends `kc_action=register` so Keycloak lands the user directly on
  the registration form. The `redirect_uri` is the same for both flows, so the callback
  handler (`completeRedirectImpl`) does not branch on entry-point.

The PKCE / state / nonce generation is shared between the two redirects through a private
`beginAuthorizationCodeRedirect(config, kcAction)` helper in `web/src/Infernix/Web/Auth.js`;
there is no single-CTA `#login-button` pattern (its removal is tracked in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)).

The Keycloak forms those redirects reach use the chart-owned `infernix` login theme. The stock
Keycloak image is unchanged; the chart mounts `ConfigMap/infernix-keycloak-theme` under
`/opt/keycloak/themes/infernix`, the realm import selects `loginTheme = infernix`, and the
idempotent realm reconcile reapplies that theme on every `cluster up`. Routed Playwright asserts
the themed login and registration titles so theme fallback is visible in the auth smoke.

## Operator Console Ribbon

The authenticated app shell includes an operator ribbon with links to the always-published
operator route family:

- `Harbor` -> `/harbor`
- `Pulsar Admin` -> `/pulsar/admin/admin/v2/clusters`

The ribbon is part of `.app-shell`, so the existing auth gate hides it before login. The browser
auth module writes the Keycloak access token into the same-origin `infernix_operator_token` cookie
when login or refresh succeeds and clears it on logout. Envoy Gateway's
`SecurityPolicy/infernix-operator-routes-jwt` validates that cookie, or an explicit
`Authorization: Bearer ...` header, before forwarding `/harbor` or `/pulsar/admin`
to their upstream services. The same cookie authenticates browser-issued media `src` GETs against
the webapp `/api/objects/download` proxy.

There is no `MinIO S3` ribbon link: Phase 3 Sprint 3.13 removed the `/minio/s3` gateway route.
End-user artifact upload, download, and preview flow through the webapp's `/api/objects` endpoints,
which derive each object key server-side from the verified `sub` so the browser never holds a MinIO
credential or presigned MinIO URL (see
[object_access_doctrine.md](object_access_doctrine.md) and
[tenant_isolation_doctrine.md](tenant_isolation_doctrine.md)).

**Current Status.** Implemented (Phase 7 Sprint 7.25; Phase 3 Sprint 3.13 removed the `/minio/s3`
route + `presignPublicEndpoint`). The user artifact path is the webapp-mediated `/api/objects`
proxy; there is no presigned MinIO URL. The `linux-cpu` plus chosen-accelerator real per-user
attestation is the remaining [Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) residual.

## Account Deletion

The signed-in header includes `Delete account`. The browser confirms the command, sends
`DELETE /api/account` with the current in-memory bearer token, and waits for a successful cleanup
response before clearing browser auth state and starting Keycloak's `kc_action=delete_account`
Application Initiated Action.

The backend derives `userId` from the validated Keycloak `sub` claim, lists and deletes the
caller-owned `infernix-demo-objects/users/<userId>/` S3 prefix, then deletes the caller-owned
demo Pulsar topics (`demo.user.<userId>.contexts`, `demo.user.<userId>.drafts`, and
`demo.conversation.<userId>.*`). Shared inference topics are not user-owned and are left intact.

## PureScript Application

- repo-owned browser application code lives under `web/src/*.purs`
- `npm --prefix web run build` regenerates `web/src/Generated/Contracts.purs`, runs `spago build`,
  and emits `web/dist/app.js`
- handwritten PureScript modules import generated modules from `web/src/Generated/` for shared
  types; they do not declare their own request or response types
- frontend tests use `purescript-spec` under `web/test/*.purs` and run via `spago test`
- `infernix test unit` invokes `spago test` alongside the Haskell unit suites

## Shared Contracts

- dedicated browser-contract ADTs in `src/Infernix/Web/Contracts.hs` are the source of truth for the
  PureScript request, response, engine-binding, and error types consumed by the demo UI
- `infernix internal generate-purs-contracts` emits `web/src/Generated/Contracts.purs`
- `npm --prefix web run build` invokes that codegen entrypoint before `spago build`
- the generator appends active runtime constants, catalog constants, and explicit `Simple.JSON`
  instances used by routed `/api` decoding

## Testing

- `purescript-spec` suites cover the generated contract module shape plus the SPA view-model
  logic for selection, catalog parity, publication summary rendering, family-aware request
  guidance, and result-state rendering
- E2E coverage exhaustively hits every generated catalog entry through the routed surface and
  separately exercises browser UI interaction for publication-detail rendering, model selection,
  submission, object-reference results, daemon-location reporting, inference-executor reporting,
  and inference-dispatch-mode reporting
- supported routed E2E on Linux uses Playwright from the substrate image; Apple host-native E2E
  uses host `npm exec` with the same typed fixture and is covered by the Apple cohort validation
  batch

## Durable Context Surface

The `infernix-demo` workload runs the `infernix` Webapp role and serves the multi-user
durable-context application. The product-agnostic primitives this binding is built on live at
[durable_context_design.md](durable_context_design.md); the demo's concrete bindings live at
[demo_app_design.md](demo_app_design.md). Topology:

- new authenticated WebSocket endpoint at `/ws` carries chat, drafts, context list/create/delete,
  progress, and artifact-ready notifications; demo-gated
- Keycloak provides identity at `/auth`; demo-gated; see [../tools/keycloak.md](../tools/keycloak.md)
- HTTP endpoint `/api/objects` is the webapp-mediated artifact surface for upload, download, and
  listing: the demo backend derives each object key server-side from the verified `sub`, reads and
  writes MinIO itself over the cluster-internal endpoint, and the browser holds only the webapp
  origin — never a MinIO credential or presigned MinIO URL; demo-gated. See
  [object_access_doctrine.md](object_access_doctrine.md) and
  [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md). **Current Status:** implemented by
  Phase 3 Sprint 3.13 and Phase 7 Sprint 7.25, then cohort-closed under
  [Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md). Generated artifact key ownership is
  closed by Phase 7 Sprint 7.28 and [Wave N](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).
- HTTP endpoint `/api/account` reaps the caller's demo-owned MinIO prefix and Pulsar topics before
  the browser starts Keycloak account deletion; demo-gated
- the demo `Service` sets `sessionAffinity: None` so any replica can host any WS connection;
  WS pods use Pulsar `Reader` subscriptions for per-WS fan-out and named `Failover`
  subscriptions for the per-context inference dispatcher
- new handwritten PureScript modules under `web/src/Infernix/Web/`: `Chat.purs`,
  `Artifacts.purs`, `ArtifactTransport.purs`, `Auth.purs`, `Browser.purs`,
  `DomEvents.purs`, `WebSocket.purs`, `Router.purs`; all consume generated contracts from
  `web/src/Generated/` and apply server-sent state patches mechanically without reimplementing
  business rules
- `Chat.purs` and `Artifacts.purs` include DOM renderer functions for the durable-context shell;
  `Main.purs` mounts those renderers from the routed SPA root. Playwright now covers the routed
  Keycloak self-registration path through the OIDC authorization-code redirect, routed WebSocket
  valid/malformed-token handshake behavior, expired-token rejection, typed malformed-frame
  `ServerError` handling, and `/api/objects` grant plus same-user MinIO byte roundtrip on the
  clean rebuilt Linux GPU launcher. The browser shell also owns the PKCE redirect completion,
  local context creation,
  browser upload to MinIO, bounded text/JSON previews, inline image/audio/video rendering,
  browser-native PDF URL wiring, and MIDI / MusicXML / generic download-only states through
  presigned grants. Successful browser uploads now send `ClientRecordUpload` so the backend
  appends a typed `ConversationUserUploadEvent` to the conversation log. The Chat form now sends
  `ClientSubmitPrompt` over the active WebSocket and includes the current context's uploaded
  `ObjectRef`s in `promptUserUploads`; `ClientHello` starts per-user context/draft streams;
  the active context sends `ClientSubscribeContext`; and submitted prompts return through inbound
  `ServerConversationPatch` append frames. Playwright asserts the rendered new-context dialog can
  open and close without sending `ClientCreateContext` or adding a local context, then select a
  supported catalog row before context creation; the outbound `ClientCreateContext` carries that
  model id, and the broker-backed context-list patch plus active left-rail item preserve it.
  The routed WebSocket test also sends a `ClientCreateContext` with an absent catalog model id
  and asserts the backend returns typed `ServerError` code `unknown-model`.
  The full browser flow now also sends `ClientRenameContext` and `ClientSoftDeleteContext`,
  asserts the broker-backed `ServerContextListPatch` upserts, and verifies the left rail renders
  the updated title plus soft-deleted state.
  Playwright also asserts browser-uploaded artifacts
  return through inbound `ConversationUserUploadEvent` append patches and render in the active
  Chat conversation with display name plus MIME type. Playwright now also asserts context-list
  snapshots/patches, draft upsert/remove patches, local logout, same-browser re-login, and
  refresh-token WebSocket re-auth through a new `ClientHello`. The SPA session layer reconnects
  after unexpected WebSocket close, resends `ClientHello` and the active
  `ClientSubscribeContext`, receives a fresh conversation snapshot, and Playwright submits a
  prompt through the reconnected socket. Cancel events now resolve their target prompt in the
  queued-count projection; the browser cancel action sends `ClientCancelPrompt` for the latest
  unresolved server-backed prompt id, and Playwright verifies the inbound cancel append patch plus
  rendered cancel entry. The SPA stores only the active context id/model id in session storage,
  resubscribes that context after a reload login, and Playwright proves draft text is restored
  after both forced WebSocket reconnect and full page reload through the broker-backed draft
  stream. The routed flow also submits a second prompt before the first unresolved prompt
  resolves, asserts the rendered `2 queued prompts` warning, and targets the second canonical
  prompt id in the cancel lifecycle.
- the supported manual-inference dispatch closes through the durable-context Chat surface and
  WebSocket transport; the legacy direct `POST /api/inference` request/poll surface is tracked
  in
  [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
- the routed browser surface terminates at the frontend pod (`infernix-demo`); the coordinator
  and engine pods are not directly addressable from the browser. The supported per-pod
  placement is codified in [daemon_topology.md](daemon_topology.md)

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [durable_context_design.md](durable_context_design.md)
- [demo_app_design.md](demo_app_design.md)
- [daemon_topology.md](daemon_topology.md)
- [object_access_doctrine.md](object_access_doctrine.md) — webapp as the single mediator for browser artifact I/O
- [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md) — per-user `sub`-derived isolation at one server-side boundary
- [../tools/keycloak.md](../tools/keycloak.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/purescript_policy.md](../development/purescript_policy.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
