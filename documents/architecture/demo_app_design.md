# Demo App Design

**Status**: Authoritative source
**Referenced by**: [durable_context_design.md](durable_context_design.md), [overview.md](overview.md), [web_ui_architecture.md](web_ui_architecture.md), [daemon_topology.md](daemon_topology.md), [../reference/web_portal_surface.md](../reference/web_portal_surface.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Define the demo-specific bindings for the `infernix-demo`
> workload — Keycloak as the IdP, the concrete Pulsar namespace and MinIO
> bucket names, the `/auth` / `/ws` / `/api/objects` routes, the SPA view
> contract, and the `demo_ui` gating — on top of the product-agnostic
> primitives codified in [durable_context_design.md](durable_context_design.md).

## TL;DR

- The `infernix-demo` workload is the first concrete binding of the
  durable-context primitives. The reusable shape — event log, reducer,
  dispatcher, prefix-hash chain, webapp-mediated object storage, JWT
  validation, stateless WS coordination — lives in
  [durable_context_design.md](durable_context_design.md). This doc names
  the demo's concrete choices.
- IdP binding: Keycloak with self-signup on, email verification off,
  username/password only. The Keycloak realm issuer is the demo's
  `<jwtIssuer>`; the public SPA client is the `<jwtAudience>`. `userId =
  sub`.
- Routes: `/auth` for the Keycloak login surface, `/ws` for authenticated
  session traffic, `/api/objects` for webapp-mediated artifact upload and
  download. The webapp is the single mediator for all artifact I/O — the
  browser holds only the webapp origin and never receives a MinIO
  credential or presigned MinIO URL (see
  [object_access_doctrine.md](object_access_doctrine.md) and
  [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md)).
- Anonymous browser visitors see only the pre-auth landing card with
  peer `Sign in` and `Create account` actions. The durable-context app
  shell renders only after the SPA has a Keycloak JWT in memory.
- Topic and bucket bindings: `<topicNamespace> = infernix/demo`;
  `<objectsBucket> = infernix-demo-objects`.
- SPA views: Chat (left rail, conversation pane, drafts, cancel, queued
  indicator), Artifacts (per-context list, MIME-family rendering), Files
  (the signed-in user's whole per-user object library across contexts,
  scoped server-side to the caller's `sub`), Model picker (catalog from
  the active substrate's generated `.dhall`).
- Every demo surface is gated by the active substrate's generated `.dhall`
  `demo_ui` flag. When `demo_ui = false`, the Keycloak release, demo
  Pulsar topic namespaces, demo MinIO bucket, `infernix-demo` workload,
  and all demo routes are absent. The production coordinator remains
  deployed because it owns request fan-in, batching, model-to-pool routing,
  result writeback, and model bootstrap.

## Current Status

The current `infernix-demo` workload ships the routed PureScript SPA,
the catalog and cache HTTP API surface, and the clustered demo
deployment. The durable-context contract is implemented over Phase 7
([../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md));
the legacy single-form manual-inference handlers are tracked in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
The integration suite validates the demo's Pulsar contexts and drafts
metadata topics as broker-compacted streams keyed by `contextId`,
validates duplicate frontend publish collapse through Pulsar producer
deduplication on conversation and draft topics using mutation-scoped
WebSocket producers, submits a real durable-context prompt and observes
the completed result writeback on the conversation log after
`ContextModelMap` resolves the context-pinned model id and the
dispatcher, engine, and result bridge run, and exercises runtime
KV-cache rebuild/reuse decisions through the engine path. The routed
Playwright E2E suite registers a real Keycloak user, exchanges the
authorization code for an access token, verifies malformed bearer
rejection, proves the `/api/objects` webapp proxy stores and streams
user-scoped artifact bytes from that real JWT, and validates same-user
routed upload/download byte equality plus cross-user object-key
rejection (HTTP 403). The same suite opens `/ws` with the real
token, verifies a malformed token does not open a browser WebSocket,
and asserts a tagged `ServerError` for a malformed frame on the valid
connection. The browser artifact flow completes the app-owned PKCE
redirect, creates a context, uploads supported browser artifact classes
through the rendered Artifacts form, and validates bounded text/JSON
previews, inline image/audio/video routed media URLs, browser-native
PDF URL wiring, and MIDI / MusicXML / generic-binary download-only
states. The Chat form sends `ClientSubmitPrompt` with the current
context's uploaded `ObjectRef`s in `promptUserUploads`; the browser
sends `ClientHello` to start per-user context/draft streams; the active
context sends `ClientSubscribeContext`; and Playwright asserts
context-list snapshots/patches, draft snapshots/upsert/remove patches,
the outbound prompt frame, and the inbound `ServerConversationPatch`
append for that prompt. The backend validates `ClientCreateContext`
model ids against the active generated catalog and returns a typed
`ServerError` code `unknown-model` for absent ids. The browser flow
also sends `ClientRenameContext` and `ClientSoftDeleteContext`,
observes the broker-backed `ServerContextListPatch` upserts, and
verifies the context rail shows the updated title plus soft-deleted
state. Upload events return through inbound
`ConversationUserUploadEvent` append patches and render in the active
Chat conversation with display name plus MIME type. The browser auth
layer keeps the Keycloak refresh token in memory, clears local auth
state on logout, and reconnects the WebSocket after a refresh-token
grant; Playwright covers logout, same-browser re-login, and
refresh-triggered `ClientHello` re-auth. The SPA session layer
reconnects after an unexpected WebSocket close with a generation guard,
resends `ClientHello`, re-subscribes the active context, and keeps the
authenticated shell mounted. The Chat projection treats cancel events
as prompt-resolution events; the browser cancel action sends
`ClientCancelPrompt` for the latest unresolved server-backed prompt id.
The SPA stores only the active context id/model id in session storage
and resubscribes after a reload login; draft text is restored after
forced WebSocket reconnect and page reload through the broker-backed
draft stream. Anonymous visitors see only the auth-gated landing with
`Sign in` and `Create account` actions; the summary grid and Chat /
Artifacts shell render after the SPA has a Keycloak JWT. The per-model
browser smoke matrix and browser-level frontend pod replacement
reconnect coverage are part of the supported E2E surface.

## Identity and Authentication

The demo's IdP binding is a Keycloak release deployed in the HA cluster
with its own Patroni Postgres cluster managed by the Percona operator.
The Keycloak realm is pre-seeded by an in-binary reconcile path on
`cluster up`. The local demo runs one Keycloak application pod
while the backing Patroni cluster stays HA. Multi-pod Keycloak serving
is gated on routed proxy-affinity or clustered-cache validation.

- Realm configuration: registration enabled (self-signup), email
  verification disabled, username/password authentication only, public
  SPA client at the SPA route. No federation, no social login, no MFA in
  the supported demo contract.
- The browser obtains a JWT by completing the standard OIDC code flow
  against the Keycloak client. The JWT is held in memory (no
  localStorage persistence is required for correctness) and presented as
  a `Bearer` token on HTTP and as a `token` query parameter on the
  WebSocket handshake.
- The `infernix-demo` binary validates the JWT against the Keycloak JWKS
  endpoint via `Infernix.Auth.Jwt` and caches the JWKS with a short TTL
  so transient Keycloak unavailability does not break existing sessions.
- The Keycloak `sub` claim is the canonical `userId` across Pulsar topic
  namespaces and MinIO prefixes. It is stable across login, logout,
  password change, and device change.
- Identity, Keycloak, the demo MinIO bucket, the WS endpoint, and the
  `/auth` and `/api/objects` routes are all demo-gated. They are absent
  from the cluster when the active substrate's generated `.dhall` carries
  `demo_ui = false`.

### Authentication Entry Points

The SPA root is auth-gated. Before a JWT is present, `web/src/index.html`
shows a centred landing card with the `Infernix` wordmark, the
`Durable-context inference console` subtitle, and exactly two actions:

- `Sign in` calls `Infernix.Web.Auth.beginLoginRedirect` and starts the
  standard PKCE authorization-code redirect to Keycloak's login form.
- `Create account` calls `Infernix.Web.Auth.beginRegisterRedirect`,
  using the same PKCE setup plus Keycloak's `kc_action=register`
  Application Initiated Action so the browser lands directly on the
  registration form.

`Main.purs.renderAuthGate` owns the `auth-unknown` / `auth-signed-out` /
`auth-signed-in` body-class state machine. The anonymous state hides the
header summary grid, Chat tab, Artifacts tab, and workspace; the signed-in
state hides the landing card and renders the durable-context shell plus the operator console
ribbon.

The Keycloak forms use the repo-owned `infernix` login theme mounted from
`ConfigMap/infernix-keycloak-theme`. The chart selects the theme in the
realm import, and the post-rollout Keycloak admin reconcile preserves
`loginTheme = infernix` alongside the realm flags and SPA client settings.

The signed-in shell writes the current Keycloak access token to the
`infernix_operator_token` same-origin cookie. Envoy Gateway validates that cookie (or a direct
`Authorization: Bearer ...` header) before forwarding browser traffic to `/harbor` or
`/pulsar/admin`, so the operator ribbon can link to those route prefixes without
making them anonymous. There is no `/minio/s3` route (Phase 3 Sprint 3.13).

The signed-in shell also exposes `Delete account`. That command confirms in the browser, calls
`DELETE /api/account` with the in-memory bearer token, and only starts Keycloak's
`kc_action=delete_account` Application Initiated Action after the backend reports that the
caller-owned demo state was reaped.

See [../tools/keycloak.md](../tools/keycloak.md) for the deployment
contract.

## Transport Model

The demo binds the primitives' stateless WS pattern (see
[durable_context_design.md § Stateless Transport Coordination](durable_context_design.md#stateless-transport-coordination))
to these concrete routes:

- **`/ws` (WebSocket).** All authenticated session traffic after login.
  Carries: chat send/receive, context list (server-streamed snapshots
  and patches), context create, rename, soft-delete, draft updates
  (client-debounced), inference progress, artifact-ready notifications.
- **`/api/objects` (HTTP, same JWT).** Webapp-mediated artifact upload,
  download, and listing. The demo backend authenticates the caller,
  derives the object key server-side from the verified `sub`, and reads
  and writes MinIO itself over the cluster-internal endpoint; the
  artifact bytes flow through the webapp on `POST /api/objects/upload`
  and `GET /api/objects/download`. The browser holds only the webapp
  origin — never a MinIO credential and never a presigned MinIO URL.
  This is the single per-user trust boundary defined in
  [object_access_doctrine.md](object_access_doctrine.md) and
  [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md).

  **Current Status.** Implemented (Phase 7 Sprint 7.25; Phase 3 Sprint 3.13
  removed the `/minio/s3` route + `presignPublicEndpoint`). The webapp proxies
  the bytes server-side and the browser never receives a presigned MinIO URL.
  Per-user isolation holds at one server-side choke point (`pathBelongsToUser`
  on the verified `sub`). The `linux-cpu` plus chosen-accelerator real per-user
  attestation is the remaining
  [Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) residual.
- **`/api/account` (HTTP DELETE, same JWT).** Account cleanup before IdP deletion. The backend
  validates the JWT, derives `userId = sub`, removes
  `infernix-demo-objects/users/<userId>/`, deletes the user's demo Pulsar topics, and returns a
  cleanup summary before the browser enters Keycloak account deletion.
- **`/auth`.** The Keycloak login surface. The browser hits `/auth` to
  start the OIDC code flow.

The demo Service has `sessionAffinity: None`. WS pods use Pulsar
`Reader` subscriptions per the primitives doc; the per-context
dispatcher uses a Pulsar named `Failover` subscription per conversation
topic.

### Pod Layout

The demo binds the three-role daemon model in
[daemon_topology.md](daemon_topology.md) as follows:

- **Frontend.** The `infernix-demo` Deployment owns WS upgrade, JWT
  validation, route handlers for `/auth`, `/ws`, and `/api/objects`,
  and SPA asset serving. As the webapp it is the single mediator for
  browser artifact I/O: it derives each object key server-side from the
  verified `sub` and performs the MinIO read/write itself over the
  cluster-internal endpoint, so the browser never reaches MinIO
  directly (see [object_access_doctrine.md](object_access_doctrine.md)).
  Stateless, replicas ≥ 2 by default.
- **Coordinator.** The `infernix-coordinator` Deployment runs the
  single-flight dispatcher and the result-bridge on the demo's
  conversation and result topics. Stateless, replicas ≥ 2 by default;
  Pulsar `Failover` provides leader election.
- **Engine.** Linux engine pool workloads or on-host Apple daemon
  members run the inference engine. Linux placement is managed by
  Kubernetes rules; Apple placement is managed by stable host ids and
  pool assignments.

The demo binary owns only the frontend role; the coordinator and
engine pods are platform infrastructure shared with any other
durable-context application.

## Demo Pulsar and MinIO Bindings

The demo binds the primitives' parametric surface (see
[durable_context_design.md § Parametricity Surface](durable_context_design.md#parametricity-surface))
to these concrete values:

| Parameter | Demo binding |
|---|---|
| `<topicNamespace>` | `infernix/demo` |
| `<objectsBucket>` | `infernix-demo-objects` |
| `<wsPath>` | `/ws` |
| `<authPath>` | `/auth` |
| `<objectsApiPath>` | `/api/objects` |
| `<jwtIssuer>` | the demo Keycloak realm issuer URL |
| `<jwtAudience>` | the demo public SPA client id |
| `<appNamespace>` | `Infernix.Demo.*` |
| `<appWorkload>` | `infernix-demo` |

Topic and bucket shapes follow the templates in
[durable_context_design.md § Pulsar Topology](durable_context_design.md#pulsar-topology)
and [§ Object Storage Layout](durable_context_design.md#object-storage-layout).
With the demo's bindings, the concrete topic names become
`persistent://infernix/demo/conversation.<userId>.<contextId>` and
similar, and the bucket prefix root is
`<objectsBucket>/users/<userId>/contexts/<contextId>/`.

Inference dispatch reuses the existing shared
`persistent://infernix/demo/inference.request.<mode>` and
`persistent://infernix/demo/inference.result.<mode>` topics; the demo
does not add platform-level inference topics.

## SPA Views

Four primary views in the SPA, all consuming the same generated
PureScript contract module and the same WS envelope.

- **Chat.** Left rail context list (derived from `ContextListState` +
  `ContextListPatch`). Active conversation pane (derived from
  `ConversationState` + `ConversationStatePatch`). Draft text box per
  context (derived from `DraftMapState` + `DraftMapPatch`). Cancel
  button on in-flight prompts. Two-prompt-in-a-row queued indicator.
- **Artifacts.** Per-context artifact list. Upload, download, and
  inline rendering all flow through the webapp's `/api/objects`
  endpoints — `<img>`, `<audio>`, `<video>` source from the
  webapp-served bytes rather than a presigned MinIO URL, with a
  generic-binary download fallback through the same surface.
- **Files.** The signed-in user's whole per-user object library across
  every context, listed through the webapp's `/api/objects/list`
  surface. The listing is scoped server-side to the caller's `sub` (see
  [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md)), so the
  view shows only the caller's own objects; each entry renders or
  downloads through the same webapp-mediated transport as the Artifacts
  view.
- **Model picker.** Modal opened on new-context creation. Catalog
  sourced from the active substrate's generated `.dhall`. Selection pins
  the model on context creation. The frontend does not create backend
  state until the user confirms; the backend rejects absent model ids
  with `ServerError` code `unknown-model`. Switching models mid-context
  is not supported.

**Current Status.** The SPA ships Chat, Artifacts (webapp-mediated transport, Phase 7 Sprint 7.25),
the per-user Files view (Phase 7 Sprint 7.26), and the Model picker. Phase 3 Sprint 3.13 removed the
`/minio/s3` browser-direct path. The `linux-cpu` plus chosen-accelerator real per-user attestation
is the remaining [Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) residual.

All views are renderers. They apply patches mechanically and render.
They call no business-rule code. User actions produce typed
`WsClientMessage`s; the server interprets them.

## Artifacts View Contract

Supported MIME families (all sourced from the webapp's `/api/objects`
bytes, never a presigned MinIO URL):

- `image/*` — rendered via `<img>` against the webapp download surface.
- `audio/*` — rendered via `<audio>` against the webapp download surface.
- `video/*` — rendered via `<video>` against the webapp download surface.
- `application/pdf` — delegated to the browser-native PDF viewer.
- `text/*` and `application/json` — rendered through a bounded preview.
- MIDI, MusicXML/MXL notation, and ZIP archives — inline rendering
  (notation rendering for MIDI/MusicXML, in-browser archive listing for
  ZIP) rather than download-only.
- arbitrary binary — generic download through the webapp download
  surface with the browser's native save dialog.

**Current Status.** Every family is sourced through the webapp `/api/objects/download` proxy
(Phase 7 Sprint 7.25). MIDI, MusicXML/MXL, and ZIP inline rendering is delivered by Phase 7
Sprint 7.27 and closed by [Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md). Generated
artifact object ownership is closed by Phase 7 Sprint 7.28: adapter/native outputs are
forced under `users/<sub>/contexts/<ctx>/generated/`, and Wave N closes the full cohort validation.

Upload flow:

1. User selects a file in the Artifacts view.
2. Browser sends the file bytes to `POST /api/objects/upload`.
3. The webapp authenticates the caller, derives the canonical object key
   server-side from the verified `sub`, writes the bytes to MinIO over
   the cluster-internal endpoint, and returns the typed `ObjectRef`.
4. Browser records the uploaded object in the Artifacts view state after
   the webapp confirms the write.
5. Browser publishes a typed `ClientRecordUpload` frame over the WS;
   backend writes the matching `UserUpload` event to the conversation
   topic with producer dedup keyed by the uploaded `ObjectRef`.
6. Reducer emits an `AppendArtifact` patch for that log append.
7. The per-context conversation stream returns upload append patches to
   subscribed browsers, and the Chat conversation renders the uploaded
   artifact display name plus MIME type.

Download flow:

1. User clicks an artifact in the Artifacts or Files view.
2. Browser sends a typed artifact request to `GET /api/objects/download`.
3. The webapp authorizes the key against the caller's `sub`, streams the
   bytes back with the correct `Content-Type` and `Content-Disposition`,
   and the browser uses the typed render disposition.
4. Browser renders inline (image/audio/video, plus MIDI/MusicXML/ZIP at
   the target), opens the browser PDF path, renders bounded text/JSON, or
   initiates a download-only flow.

**Current Status.** Implemented (Phase 7 Sprint 7.25; Phase 3 Sprint 3.13 removed the `/minio/s3`
route). `POST /api/objects/upload` carries the bytes and returns an `ArtifactUploadGrant` with the
canonical `ObjectRef` (no URL); `POST /api/objects/download` returns an `ArtifactDownloadGrant` with
the render disposition (no URL); `GET /api/objects/download` streams the bytes server-side. The
browser never receives a presigned MinIO URL. The `linux-cpu` plus chosen-accelerator real per-user
attestation is the remaining [Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) residual.

## Gating

Every Phase 7 surface is gated by the active substrate's generated
`.dhall` `demo_ui` flag. When `demo_ui = false`:

- the Keycloak release and its Patroni Postgres cluster are absent
- the `infernix-demo` workload is absent
- the WS endpoint, the `/auth` route, the `/api/objects` route, and the
  `/` SPA route are absent from the routed surface
- the demo MinIO bucket is absent
- the `infernix/demo` Pulsar topic namespace (including the
  `conversation.*`, `user.*.contexts`, and `user.*.drafts` shapes) is
  absent

Production deployments leave `demo_ui = false` and accept inference work
via the existing `inference.request.<mode>` topic only.

## Validation

The demo binding's validation surface lives at
[../development/demo_app_test_plan.md](../development/demo_app_test_plan.md)
and covers three layers:

- **Unit** — Haskell unit and property tests for the shared primitives
  (covered in
  [durable_context_design.md § Validation](durable_context_design.md#validation));
  PureScript `purescript-spec` view-model tests scoped to patch
  application and rendering for the demo's three SPA views; WS envelope
  codec roundtrip across the demo's `WsClientMessage` and
  `WsServerMessage` variants.
- **Integration** — real Pulsar / MinIO / Keycloak round-trips against
  the demo bindings; producer-dedup verification across simulated
  dispatcher restart; Failover handoff; cross-user object-access
  negative (a caller's JWT receives HTTP 403 on another user's object
  key through the webapp object-proxy per
  [object_access_doctrine.md](object_access_doctrine.md)); chaos tests;
  multi-user throughput / fan-in batching /
  fan-out test (N users × K contexts × P prompts on one model)
  asserting per-context ordering, no duplicates or losses, cross-context
  independence, batching gain, bounded p95 latency, dedup correctness.
- **E2E** — Playwright flows for auth, context, conversation (including
  two-in-a-row and cancel), draft, artifact upload/download/render per
  MIME family, generated-artifact lifecycle, multi-tab convergence,
  client reconstitution via Browser Context storage-clear,
  pod-failover-from-browser, plus the **per-model smoke matrix** driven
  by the active substrate's generated `.dhall` catalog (every
  non-`Not recommended` row gets one passing flow). The Playwright
  source is identical across `apple-silicon`, `linux-cpu`, and
  `linux-gpu`.

## Cross-References

- [durable_context_design.md](durable_context_design.md) — product-agnostic primitives (authoritative for the reusable shape)
- [object_access_doctrine.md](object_access_doctrine.md) — webapp as the single mediator for browser artifact I/O
- [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md) — per-user `sub`-derived isolation at one server-side boundary
- [daemon_topology.md](daemon_topology.md) — three-role daemon model and per-substrate placement
- [overview.md](overview.md) — platform topology
- [web_ui_architecture.md](web_ui_architecture.md) — PureScript demo UI topology and image layout
- [../tools/keycloak.md](../tools/keycloak.md) — Keycloak deployment and realm contract
- [../tools/pulsar.md](../tools/pulsar.md) — Pulsar topic contract
- [../tools/minio.md](../tools/minio.md) — MinIO bucket and presigned URL contract
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md) — routed demo surface
- [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md) — module ownership boundary
- [../development/frontend_contracts.md](../development/frontend_contracts.md) — Haskell-owned contract generation
- [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md) — validation surface
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md) — execution-ordered build out
