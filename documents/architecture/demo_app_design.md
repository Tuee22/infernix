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
  dispatcher, prefix-hash chain, presigned object storage, JWT
  validation, stateless WS coordination — lives in
  [durable_context_design.md](durable_context_design.md). This doc names
  the demo's concrete choices.
- IdP binding: Keycloak with self-signup on, email verification off,
  username/password only. The Keycloak realm issuer is the demo's
  `<jwtIssuer>`; the public SPA client is the `<jwtAudience>`. `userId =
  sub`.
- Routes: `/auth` for the Keycloak login surface, `/ws` for authenticated
  session traffic, `/api/objects` for presigned MinIO PUT/GET URLs.
- Topic and bucket bindings: `<topicNamespace> = infernix/demo`;
  `<objectsBucket> = infernix-demo-objects`.
- SPA views: Chat (left rail, conversation pane, drafts, cancel, queued
  indicator), Artifacts (per-context list, per-user library, MIME-family
  rendering), Model picker (catalog from the active substrate's
  generated `.dhall`).
- Every demo surface is gated by the active substrate's generated `.dhall`
  `demo_ui` flag. When `demo_ui = false`, the Keycloak release, demo
  Pulsar topic namespaces, demo MinIO bucket, and all demo routes are
  absent.

## Current Status

The current `infernix-demo` workload ships the routed PureScript SPA,
the catalog and cache HTTP API surface, and the clustered demo
deployment. The durable-context contract is implemented over Phase 7
([../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)),
which retires the previous single-form manual-inference handlers from the
supported demo contract; that retirement is tracked in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## Identity and Authentication

The demo's IdP binding is a Keycloak release deployed in the HA cluster
with its own Patroni Postgres cluster managed by the Percona operator.
The Keycloak realm is pre-seeded by an in-binary reconcile path on
`cluster up`.

- Realm configuration: registration enabled (self-signup), email
  verification disabled, username/password authentication only, public
  SPA client at the SPA route. No federation, no social login, no MFA in
  the supported demo contract.
- The browser obtains a JWT by completing the standard OIDC code flow
  against the Keycloak client. The JWT is held in memory (no
  localStorage persistence is required for correctness) and presented as
  a `Bearer` token on HTTP and as a subprotocol parameter on the
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
- **`/api/objects` (HTTP, same JWT).** Artifact upload and download via
  presigned MinIO PUT/GET URLs minted by the demo backend. Binary bytes
  never traverse the demo backend; the browser uploads directly to MinIO
  and downloads directly from MinIO via the presigned URL.
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
  and SPA asset serving. Stateless, replicas ≥ 2 by default.
- **Coordinator.** The `infernix-coordinator` Deployment runs the
  single-flight dispatcher and the result-bridge on the demo's
  conversation and result topics. Stateless, replicas ≥ 2 by default;
  Pulsar `Failover` provides leader election.
- **Engine.** The `infernix-engine` Deployment (Linux) or the
  existing on-host daemon (Apple) runs the inference engine. Strict
  one-per-node policy on every substrate.

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

Three primary views in the SPA, all consuming the same generated
PureScript contract module and the same WS envelope.

- **Chat.** Left rail context list (derived from `ContextListState` +
  `ContextListPatch`). Active conversation pane (derived from
  `ConversationState` + `ConversationStatePatch`). Draft text box per
  context (derived from `DraftMapState` + `DraftMapPatch`). Cancel
  button on in-flight prompts. Two-prompt-in-a-row queued indicator.
- **Artifacts.** Per-context artifact list and per-user library. Upload
  via presigned PUT with progress indicator. Download via presigned GET.
  Inline rendering via `<img>`, `<audio>`, `<video>` against presigned
  URLs. Generic-binary download fallback.
- **Model picker.** Modal opened on new-context creation. Catalog
  sourced from the active substrate's generated `.dhall`. Selection pins
  the model on context creation; switching models mid-context is not
  supported.

All views are renderers. They apply patches mechanically and render.
They call no business-rule code. User actions produce typed
`WsClientMessage`s; the server interprets them.

## Artifacts View Contract

Supported MIME families:

- `image/*` — rendered via `<img>` against presigned GET URL.
- `audio/*` — rendered via `<audio>` against presigned GET URL.
- `video/*` — rendered via `<video>` against presigned GET URL.
- arbitrary binary — generic download via presigned GET URL with the
  browser's native save dialog.

Upload flow:

1. User selects a file in the Artifacts view.
2. Browser sends a typed `WsClientMessage` requesting an upload grant.
3. Backend returns an `ArtifactUploadGrant` via WS with a presigned PUT
   URL plus the canonical object key.
4. Browser performs the multipart PUT directly to MinIO with progress
   events.
5. On completion, browser publishes a `UserUpload` event over the WS;
   backend writes the event to the conversation topic with its
   idempotency key.
6. Reducer emits an `AppendArtifact` patch; every connected client
   renders the new artifact.

Download flow:

1. User clicks an artifact in the Artifacts view.
2. Browser sends a typed `WsClientMessage` requesting a download grant.
3. Backend returns an `ArtifactDownloadGrant` via WS with a presigned GET
   URL.
4. Browser renders inline (image/audio/video) or initiates a generic
   download.

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
[../development/demo_app_test_plan.md](../development/demo_app_test_plan.md);
the surface is split across three sprints:

- **Sprint 7.12 (Unit)** — Haskell unit and property tests for the
  shared primitives (covered in
  [durable_context_design.md § Validation](durable_context_design.md#validation));
  PureScript `purescript-spec` view-model tests scoped to patch
  application and rendering for the demo's three SPA views; WS envelope
  codec roundtrip across the demo's `WsClientMessage` and
  `WsServerMessage` variants.
- **Sprint 7.13 (Integration)** — real Pulsar / MinIO / Keycloak
  round-trips against the demo bindings; producer-dedup verification
  across simulated dispatcher restart; Failover handoff; cross-user
  presigned URL negative; chaos tests; multi-user throughput / fan-in
  batching / fan-out test (N users × K contexts × P prompts on one
  model) asserting per-context ordering, no duplicates or losses,
  cross-context independence, batching gain, bounded p95 latency, dedup
  correctness.
- **Sprint 7.14 (E2E)** — Playwright flows for auth, context,
  conversation (including two-in-a-row and cancel), draft, artifact
  upload/download/render per MIME family, generated-artifact lifecycle,
  multi-tab convergence, client reconstitution via Browser Context
  storage-clear, pod-failover-from-browser, plus the **per-model smoke
  matrix** driven by the active substrate's generated `.dhall` catalog
  (every non-`Not recommended` row gets one passing flow). The
  Playwright source is identical across `apple-silicon`, `linux-cpu`,
  and `linux-gpu`.

## Cross-References

- [durable_context_design.md](durable_context_design.md) — product-agnostic primitives (authoritative for the reusable shape)
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
