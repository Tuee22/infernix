# Phase 7: Demo App Multi-User Durable Context

**Status**: Planned
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md)

> **Purpose**: Define the multi-user, durable-context shape of the `infernix-demo` workload —
> Keycloak self-signup, WebSocket post-login transport, Pulsar-backed per-context conversation
> history, MinIO-backed artifact upload/download with audio/image/video rendering, stateless
> backend pods, single-flight per-context inference dispatch, and the validation surface that
> proves all of it under load and pod failure.

## Phase Status

Phase 7 is `Planned`. Phases 0–6 are `Done`, so the platform foundation, runtime, routed edge,
HA platform services, generated demo catalog, and validation surface this phase builds on are
all in place. Phase 7 closes only when every sprint below is `Done`, every doc named in the
sprints is aligned with the implemented behavior, `infernix test all` passes on at least one
substrate with `demo_ui = true`, and the per-model smoke matrix and multi-user throughput tests
named in [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md)
are green.

## Current Repo Assessment

The current `infernix-demo` workload ships a routed PureScript SPA, the catalog and cache
HTTP API surface from Phase 4 Sprint 4.4, and the clustered demo deployment described by
Phase 3. The Helm chart already deploys Pulsar (3-broker HA), MinIO (4-replica HA),
per-service Patroni Postgres clusters (Harbor's `harborpg` and Grafana's backend), Envoy
Gateway, and the routed edge described by Phase 3. Production inference dispatch already
flows through `inference.request.<mode>` and `inference.result.<mode>` topics per Phase 4.
The legacy direct manual-inference HTTP handlers, the matching CLI helper, the
`proto/infernix/api/inference_service.proto` schema, and the single-form manual
inference surface are tracked for explicit removal in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this phase.

Phase 7 closes the durable-context contract on top of that foundation. It does not modify
production inference dispatch; the new conversation, metadata, and drafts topics live in
demo-gated namespaces, the new Keycloak release, demo MinIO bucket, WebSocket endpoint, and
`/auth` and `/api/objects` routes are absent when `demo_ui = false`, and the supported
manual-inference path closes through the durable-context Chat surface rather than a
parallel HTTP request/poll cycle.

## Architecture

The product-agnostic design lives at
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the demo-specific bindings live at
[../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md);
this section names the load-bearing decisions so phase readers can locate the right module
boundary without re-reading the design docs.

- **Identity.** Keycloak release with self-signup on, email verification off, username/password
  only. Browser obtains a JWT and presents it on both HTTP and WS handshakes. Backend validates
  against Keycloak JWKS. `userId = sub`.
- **Transport.** WebSocket for chat, drafts, context list, progress, and artifact-ready
  notifications. HTTP (same JWT) for artifact upload/download, with presigned MinIO PUT/GET
  URLs so binary bytes never traverse the demo backend.
- **Statelessness.** Backend pods hold zero per-user state across requests. No demo-backend
  Postgres is added; existing per-service Patroni clusters (Harbor, Grafana, and Keycloak's
  own) are unchanged. The browser holds no durable state — full reconstitution from server-
  side state alone on every login.
- **Pulsar topology.** Per-context conversation log topic
  `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` under the supported
  default `infernix/demo` tenant/namespace, single-partition,
  append-only, broker-assigned `MessageId` as the canonical sequence. Compacted per-user
  metadata topics `demo.user.<userId>.contexts` (context list) and `demo.user.<userId>.drafts`
  (drafts keyed by `contextId`). Inference dispatch reuses the existing shared
  `inference.request.<mode>` / `inference.result.<mode>` topics, with envelopes carrying
  `(userId, contextId, causalRef, conversationLogOffset, prefixHash)`.
- **MinIO.** One shared `infernix-demo-objects` bucket. Per-user prefixes:
  `users/<userId>/contexts/<contextId>/{uploads,generated}/`. Presigned URL minting by the
  demo backend with per-user scope policy.
- **Haskell-first logic.** purescript-bridge generates every wire-crossing ADT and JSON
  instance. The Haskell reducer, idempotency dedup, `prefixHash` chain, dispatcher rule, and
  event construction live only in Haskell, in the shared `infernix` library. PureScript code
  is a thin renderer plus input handler; it never reimplements a business rule. The browser
  receives typed `ConversationState` snapshots and `ConversationStatePatch` deltas over WS and
  applies patches via trivial mechanical helpers.
- **Stateless WebSocket coordination.** Demo `Service` has `sessionAffinity: None`. WS pods
  use Pulsar `Reader` subscriptions (cursor-based, no shared subscription state across pods)
  so any pod can host any session. The per-context dispatcher uses named `Failover`
  subscriptions so exactly one pod is active per context at a time. No Redis, no NATS, no
  Keycloak-native session broker — Pulsar is the inter-pod fan-out path.
- **Per-context single-flight inference.** The dispatcher is a pure fold over the conversation
  log: dispatch a `UserPrompt` iff every prior `UserPrompt` has a matching `InferenceResult`.
  Two prompts in a row queue cleanly; cancellation is an event whose outcome is deterministic
  in the log.
- **Engine ↔ SSoT consistency.** Inference request envelopes carry `prefixHash` (Merkle-style
  content hash of the deterministic projection at the dispatch offset). Engine KV-cache key is
  `(contextId, prefixHash)`. Cache cannot diverge: hash match means provably consistent, hash
  miss means rebuild from the log.
- **Failure semantics.** Every retry path is idempotent at the broker level via Pulsar
  producer-side deduplication (`enableProducerDeduplication = true`) on conversation,
  inference-request, and inference-result topics, keyed by upstream `MessageId`s. Crashes
  degrade to redeliveries and cache misses, never data loss or duplication.

### Reuse Boundary

Phase 7 introduces three concept-named module groups so the durable-context primitives are
reusable by any future SPA-like application built on the inference platform:

- **Shared library** (`Infernix.Conversation.*`, `Infernix.Topic.*`, `Infernix.Dispatch.*`,
  `Infernix.Objects.*`, `Infernix.Auth.*`) — product-agnostic, parameterized in topic namespace,
  bucket name, and JWT issuer/audience.
- **Demo binary** (`Infernix.Demo.*`) — Keycloak realm wiring, WS upgrade, HTTP route handlers,
  WS envelope tagged-sum types, first-run bootstrap.
- **Cluster daemon** (`Infernix.Runtime.*` engine path) — imports `Infernix.Conversation.Reducer`
  and `Infernix.Conversation.Hash` for engine-side KV-cache consistency only.

The cluster daemon never imports `Infernix.Demo.*`, `Infernix.Objects.Presigned`,
`Infernix.Auth.Jwt`, or any WebSocket module. The discipline is documented in
[../documents/engineering/implementation_boundaries.md](../documents/engineering/implementation_boundaries.md);
the reusable shape this discipline protects is codified in
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md).

## Sprint 7.1: Keycloak Release and Realm Pre-Seed [Planned]

**Status**: Planned
**Implementation**: `chart/templates/keycloak/`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Keycloak.hs`
**Docs to update**: `documents/tools/keycloak.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/architecture/demo_app_design.md`

### Objective

Deploy Keycloak in the HA cluster with its own Patroni Postgres backend and a pre-seeded realm
that allows self-signup with username/password and skips email verification.

### Deliverables

- Helm templates under `chart/templates/keycloak/` for the Keycloak Deployment plus a Patroni
  PostgreSQL cluster managed by the Percona operator
- `chart/values.yaml` Keycloak stanza with image from Harbor, demo-gating tied to `demo_ui`
- realm definition file plus an in-binary reconcile path that imports the realm with
  self-signup on, email verification off, public SPA client, and `/auth` issuer URL
- `/auth` route added to the Haskell route registry source so the auto-rendered registry
  emits it into README, `documents/reference/web_portal_surface.md`, and publication JSON
- `cluster up` reconciles Keycloak after Harbor is responsive, before the demo workload starts
  on the durable-context surface

### Validation

- `cluster up` with `demo_ui = true` deploys Keycloak and reports readiness
- a browser at `/auth` reaches the Keycloak login page
- signup with a fresh username and password succeeds without an email-verification step
- `infernix kubectl -n platform get postgrescluster` shows the Keycloak Patroni cluster
- when the demo UI is disabled, the Keycloak release and its Patroni cluster are absent

### Remaining Work

All work pending — sprint is `Planned`.

---

## Sprint 7.2: Browser-Contract ADTs and WS Envelope [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`
**Docs to update**: `documents/development/frontend_contracts.md`, `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`

### Objective

Extend the Haskell-owned browser contract with every new ADT the durable-context surface
introduces, and regenerate the PureScript contract module via purescript-bridge so the browser
imports type-safe wire bindings.

### Deliverables

- new types in `src/Infernix/Web/Contracts.hs`:
  - `ConversationEvent`, `ContextMetadataEvent`, `DraftEvent`
  - `ConversationState`, `ConversationStatePatch`
  - `ContextListState`, `ContextListPatch`
  - `DraftMapState`, `DraftMapPatch`
  - `WsClientMessage`, `WsServerMessage` (tagged sums; server messages carry snapshots and
    patches, not raw events)
  - `ArtifactUploadRequest`, `ArtifactUploadGrant`, `ArtifactDownloadGrant`
  - `ObjectRef`, `ArtifactKind`, `ArtifactMimeType`, `ArtifactRenderDisposition`
  - newtypes for `UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`
- regenerated `web/src/Generated/Contracts.purs` consumed by handwritten PureScript modules

### Validation

- `infernix internal generate-purs-contracts` produces deterministic output
- `infernix test unit` exercises encode/decode roundtrip across the new types in both the
  Haskell and PureScript suites
- repeated codegen runs produce byte-identical output

### Remaining Work

All work pending.

---

## Sprint 7.3: WS Endpoint, JWT Validation, and Stateless Coordination [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/Demo/WebSocket.hs`, `src/Infernix/Demo/Auth.hs`, `src/Infernix/Auth/Jwt.hs`, `chart/templates/demo/service.yaml` (or equivalent), `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/reference/web_portal_surface.md`, `documents/tools/keycloak.md`

### Objective

Land the `/ws` endpoint with Keycloak JWT validation on handshake. Establish stateless
coordination using Pulsar `Reader` subscriptions on the WS path so any replica can host any
session.

### Deliverables

- `Infernix.Auth.Jwt` shared module with JWKS-backed validation parameterized in issuer and
  audience
- `Infernix.Demo.Auth` wires the Keycloak realm to `Infernix.Auth.Jwt`
- `Infernix.Demo.WebSocket` handles WS upgrade, JWT validation, framed envelope routing
- chart Service for `infernix-demo` sets `sessionAffinity: None`; no client-IP or cookie
  affinity on the HTTPRoute either
- `/ws` route added to the Haskell route registry source
- per-WS state holds only the WS handle and Pulsar Reader cursors; no per-user identity cache

### Validation

- WS connection with a valid JWT succeeds; invalid/expired JWT closes the WS with a typed
  error
- `infernix kubectl -n platform get service/infernix-demo -o yaml | grep sessionAffinity`
  reports `None`
- a chaos test (Sprint 7.13) kills the WS-hosting pod and asserts the client reconnects to a
  different replica with no state loss

### Remaining Work

All work pending.

---

## Sprint 7.4: Conversation Primitives in Shared Library [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/Conversation/Event.hs`, `src/Infernix/Conversation/Reducer.hs`, `src/Infernix/Conversation/Idempotency.hs`, `src/Infernix/Conversation/Hash.hs`, `src/Infernix/Conversation/Topic.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Land the product-agnostic conversation primitives in the shared library so both the demo
binary and the cluster daemon can use them. The Reducer module produces both
`ConversationState` snapshots and `ConversationStatePatch` deltas so demo backends can stream
patches to browsers without browsers ever folding raw events.

### Deliverables

- `Infernix.Conversation.Event` — `ConversationEvent` ADT, JSON and protobuf instances
- `Infernix.Conversation.Reducer` — deterministic fold; emits patches alongside state
- `Infernix.Conversation.Idempotency` — `(contextId, clientIdempotencyKey)` dedup rule
- `Infernix.Conversation.Hash` — Merkle-style `prefixHash` chain
- `Infernix.Conversation.Topic` — per-context Pulsar topic naming, schema registration,
  producer and compacted-reader helpers; parameterized in `TopicNamespace`
- Pulsar producer dedup enabled on conversation topics (`enableProducerDeduplication = true`),
  named producers, dedup sequence IDs derived from upstream `MessageId`s

### Validation

- Haskell property tests cover reducer determinism, idempotency dedup, hash chain
  monotonicity, and patch-stream equivalence to state-snapshot equality
- integration test (Sprint 7.13) round-trips a conversation through a real Pulsar topic with
  producer dedup verified via simulated double-publish
- no module under `Infernix.Demo.*` is imported by these shared modules

### Remaining Work

All work pending.

---

## Sprint 7.5: Compacted Metadata Patterns in Shared Library [Planned]

**Status**: Planned
**Blocked by**: 7.4
**Implementation**: `src/Infernix/Topic/Metadata.hs`, `src/Infernix/Topic/Drafts.hs`, `src/Infernix/Cluster.hs` (namespace compaction policy reconcile)
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`

### Objective

Land the compacted-topic projection patterns used by the contexts metadata topic and the
drafts topic, plus the namespace-level compaction policy required by the broker.

### Deliverables

- `Infernix.Topic.Metadata` — generic compacted-topic projection pattern with append-event +
  read-compacted reader helpers
- `Infernix.Topic.Drafts` — generic compacted-keyed-mutable-state pattern with
  upsert-by-key + read-compacted reader helpers
- namespace-level compaction policy reconciled on `cluster up` for `demo.user.*` namespaces

### Validation

- integration test publishes N events to a compacted topic with M distinct keys and asserts
  the compacted reader yields exactly M latest values
- pulsar admin reports compaction enabled on the demo namespaces after `cluster up`

### Remaining Work

All work pending.

---

## Sprint 7.6: Single-Flight Dispatcher in Shared Library [Planned]

**Status**: Planned
**Blocked by**: 7.4
**Implementation**: `src/Infernix/Dispatch/SingleFlight.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`

### Objective

Land the per-context single-flight inference dispatcher as a pure fold over the conversation
log. Subscribe to each active conversation topic with a Pulsar named `Failover` subscription
so exactly one pod is the active dispatcher per context at a time.

### Deliverables

- `Infernix.Dispatch.SingleFlight` — pure dispatch rule, cancellation handling, inference
  request envelope construction including `prefixHash`, `conversationLogOffset`, `causalRef`,
  `userId`, `contextId`
- Pulsar producer dedup enabled on `inference.request.<mode>` keyed by `userPromptMessageId`
- failover-subscription wiring per conversation topic

### Validation

- unit property test exercises the pure-fold rule across arbitrary log prefixes including
  cancels, two-in-a-row prompts, and out-of-order results
- integration chaos test (Sprint 7.13) kills the active dispatcher mid-prompt; asserts
  Failover promotes a surviving pod and producer dedup prevents a duplicate dispatch
- two prompts in a row in the same context produce exactly two inference requests in the
  correct order

### Remaining Work

All work pending.

---

## Sprint 7.7: Engine Prefix-Hash Cache Consistency and Result Writeback [Planned]

**Status**: Planned
**Blocked by**: 7.4, 7.6
**Implementation**: `src/Infernix/Runtime/*`, `tools/generated_proto/` (or upstream `.proto`), `src/Infernix/Demo/ResultBridge.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Make the engine's KV cache consistency with the Pulsar SSoT provable and crash-tolerant. Land
the result-to-conversation bridge that writes `InferenceResult` events back to the per-context
conversation topic.

### Deliverables

- inference request envelope (proto + Haskell records) extended with `prefixHash`,
  `conversationLogOffset`, `causalRef`, `userId`, `contextId`
- inference result envelope extended with `causalRef` and a `Cancelled` status variant
- engine adapter / runtime reuses `Infernix.Conversation.Reducer` and
  `Infernix.Conversation.Hash` to verify `prefixHash` before reusing any KV cache; rebuild on
  miss
- `Infernix.Demo.ResultBridge` — Pulsar Failover-subscribed consumer on
  `inference.result.<mode>` that writes typed `InferenceResult` events to the conversation
  topic with producer dedup keyed by `(userPromptMessageId, kind = InferenceResult)`
- Pulsar producer dedup enabled on `inference.result.<mode>` keyed by `userPromptMessageId`
- the cluster daemon does **not** import `Infernix.Demo.*`

### Validation

- unit test: tampered `prefixHash` causes cache miss; matching hash causes cache hit; rebuild
  produces identical output
- integration chaos test (Sprint 7.13) kills the cluster daemon mid-inference; surviving pod
  rebuilds KV cache from log; producer dedup prevents duplicate result
- E2E: prompt → response cycle works end-to-end against a real model

### Remaining Work

All work pending.

---

## Sprint 7.8: Demo MinIO Bucket and Presigned URL Minting [Planned]

**Status**: Planned
**Implementation**: `chart/values.yaml`, `src/Infernix/Objects/Layout.hs`, `src/Infernix/Objects/Presigned.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Demo/Bootstrap.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/minio.md`, `documents/engineering/object_storage.md`, `documents/reference/api_surface.md`

### Objective

Land the shared MinIO bucket plus per-user prefix layout and the `/api/objects` HTTP endpoint
that mints presigned PUT and GET URLs scoped to the authenticated user.

### Deliverables

- `infernix-demo-objects` bucket added to `chart/values.yaml` MinIO bucket list (demo-gated)
- `Infernix.Objects.Layout` — bucket and prefix conventions
  (`users/<userId>/contexts/<contextId>/{uploads,generated}/`); per-user scope helpers
- `Infernix.Objects.Presigned` — presigned URL minting helpers parameterized in the MinIO
  client config and scope policy
- `Infernix.Demo.Api` — `/api/objects` HTTP route that consumes JWT, validates per-user
  scope, and returns presigned PUT or GET URLs
- `Infernix.Demo.Bootstrap` — idempotent first-run bucket creation
- `/api/objects` route added to the Haskell route registry source

### Validation

- integration test mints a presigned PUT for user A, uploads, mints presigned GET, downloads;
  asserts content equality
- cross-user negative test: presigned URL minted for user A cannot be used to access user
  B's prefix
- when `demo_ui = false`, the bucket and `/api/objects` route are absent

### Remaining Work

All work pending.

---

## Sprint 7.9: SPA Chat View [Planned]

**Status**: Planned
**Blocked by**: 7.2, 7.3, 7.4, 7.5
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `web/src/Infernix/Web/WebSocket.purs`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Router.purs`, `web/src/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`, `documents/development/purescript_policy.md`

### Objective

Land the Chat view: left rail of contexts, active conversation pane, draft restore, cancel
button, two-prompt queued indicator. All state changes flow from server-sent
`ConversationStatePatch` / `ContextListPatch` / `DraftMapPatch` messages applied by trivial
mechanical helpers; no business rule is reimplemented in PureScript.

### Deliverables

- `web/src/Infernix/Web/Auth.purs` — OIDC redirect handling, in-memory JWT storage, JWT
  refresh
- `web/src/Infernix/Web/WebSocket.purs` — WS connect with JWT handoff, framed-envelope send
  and receive
- `web/src/Infernix/Web/Chat.purs` — left rail context list, active conversation pane, draft
  text box, cancel button; renders projected state and applies patches mechanically
- `web/src/Infernix/Web/Router.purs` — SPA route table for Chat / Artifacts
- `web/src/Main.purs` extended to mount the durable-context surface when JWT is present

### Validation

- `purescript-spec` tests cover patch application + rendering correctness for each
  `ConversationStatePatch` variant; no reducer logic in PureScript
- E2E (Sprint 7.14) covers signup → context creation → prompt submission → response render
  → cancel → two-prompt queued indicator → conversation order preservation across reload

### Remaining Work

All work pending.

---

## Sprint 7.10: SPA Artifacts View [Planned]

**Status**: Planned
**Blocked by**: 7.2, 7.3, 7.8, 7.9
**Implementation**: `web/src/Infernix/Web/Artifacts.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`, `documents/development/purescript_policy.md`

### Objective

Land the Artifacts view: per-context artifact list and per-user library, with upload via
presigned PUT, download via presigned GET, and in-browser rendering of image, playable audio, and
video, bounded preview for text/JSON, browser-native PDF handling, and download-only
handling for MIDI, MusicXML/MXL notation, unknown, and generic binary artifacts. Artifact
state is delivered as server-sent patches over the WS; the view is a renderer.

### Deliverables

- `web/src/Infernix/Web/Artifacts.purs` — per-context list, per-user library, upload UI
  with progress, download UI, inline rendering via `<img>` / `<audio>` / `<video>` against
  presigned URLs, bounded text/JSON preview, browser-native PDF handling, first-class
  MIDI and MusicXML/MXL notation download handling, and generic-binary download fallback
- HTTP multipart upload helper that issues a presigned PUT request to `/api/objects`, then
  uploads directly to MinIO, then publishes a `UserUpload` event via WS
- WS handler for `ArtifactReady` server messages renders the new artifact in place

### Validation

- `purescript-spec` view-model tests for artifact-kind dispatch
- E2E (Sprint 7.14) covers upload, download, render-or-download behavior for each supported
  artifact class, and the generated-artifact lifecycle (SDXL Turbo image, bark-small audio,
  Basic Pitch MIDI, Audiveris notation)

### Remaining Work

All work pending.

---

## Sprint 7.11: SPA Model Picker Integration [Planned]

**Status**: Planned
**Blocked by**: 7.9
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/demo_app_design.md`

### Objective

Wire the new-context flow to the active substrate's generated demo `.dhall` catalog so users
pick a model from the same set the active staged catalog exposes. Model selection pins the
context for life; switching models mid-context is out of scope.

### Deliverables

- `Chat.purs` model-picker modal sourced from the generated catalog
- WS `CreateContext` message includes the chosen `modelId`; backend validates against the
  active catalog and rejects unknown ids
- new-context creation defers to first prompt submission; clicking "New" + closing without
  submitting leaves no backend state

### Validation

- E2E: open new-context dialog, see catalog entries for the active substrate (skipping
  `Not recommended`), pick model, submit prompt, see context appear in left rail
- E2E negative: closing the dialog without submission creates no backend state (verified by
  listing the user's contexts topic via Pulsar admin)

### Remaining Work

All work pending.

---

## Sprint 7.12: Unit-Layer Validation [Planned]

**Status**: Planned
**Blocked by**: 7.2, 7.4, 7.5, 7.6, 7.7, 7.8
**Implementation**: `test/unit/*` (existing `infernix-unit` Cabal stanza), `web/test/*`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Land the unit test layer for every primitive added in Phase 7. Property-based wherever
ordering invariants matter.

### Deliverables

- reducer property tests: determinism over arbitrary `ConversationEvent` logs; idempotency
  dedup; cancellation semantics; two-prompt-in-a-row ordering
- reducer-to-patch tests: given an event log, the Haskell reducer emits a patch stream that,
  applied to the initial state, converges to the same projection as the snapshot reducer
- `prefixHash` chain tests: determinism, monotonicity, equality under reorder of independent
  events, mismatch on tampered event
- dispatcher pure-fold rule tests across arbitrary log prefixes
- topic name derivation tests for every `TopicNamespace` shape
- JWT validation edge cases (expired, wrong issuer, wrong audience, malformed, valid)
- presigned URL minting tests (correct scope, correct expiration, signature shape)
- WS envelope codec roundtrip tests for every `WsClientMessage` / `WsServerMessage` variant
- compacted topic projection tests with synthetic in-memory broker
- PureScript `purescript-spec` view-model tests in `web/test/Infernix/Web/ChatSpec.purs` and
  `web/test/Infernix/Web/ArtifactsSpec.purs`, scoped to patch application and rendering only

### Validation

- `infernix test unit` includes all new suites and passes
- coverage report shows every new shared-library module is exercised

### Remaining Work

All work pending.

---

## Sprint 7.13: Integration-Layer Validation [Planned]

**Status**: Planned
**Blocked by**: 7.1, 7.4, 7.5, 7.6, 7.7, 7.8
**Implementation**: `test/integration/*` (existing `infernix-integration` Cabal stanza), `test/integration/Infernix/Test/Integration/Throughput.hs`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/chaos_testing.md`, `documents/tools/pulsar.md`

### Objective

Land the integration test layer covering real-cluster Pulsar / MinIO / Keycloak round-trips,
the chaos tests for the failure semantics, and the multi-user throughput / fan-in batching /
fan-out test.

### Deliverables

- real Pulsar publish + Reader subscribe round-trip per topic family (conversation, compacted
  contexts, compacted drafts, inference request/result)
- real Pulsar producer dedup verification across simulated dispatcher restart mid-flight;
  assert exactly-one inference dispatch and exactly-one result
- real Pulsar Failover handoff: kill active dispatcher; assert surviving consumer resumes
- real MinIO presigned PUT/GET with per-user scoping; cross-user negative
- real Keycloak signup + login + JWT validation round-trip
- chaos tests: WS-pod kill mid-session; dispatcher kill mid-prompt; cluster-daemon kill
  mid-inference; each asserting exactly-once outcome and full state preservation
- **Multi-User Throughput / Fan-In Batching / Fan-Out** test: N users × K contexts × P
  prompts on one model, asserting per-context ordering, no duplicates or losses,
  cross-context independence, batching gain, bounded p95 latency, dedup correctness;
  module: `Infernix.Test.Integration.Throughput`; defaults N = 10, K = 3, P = 5

### Validation

- `infernix test integration` includes all new suites and passes on at least one substrate
  with `demo_ui = true`
- throughput test reports per-context ordering, exact result counts, p95 latency, batching
  factor, and dedup counter values

### Remaining Work

All work pending.

---

## Sprint 7.14: E2E-Layer Validation [Planned]

**Status**: Planned
**Blocked by**: 7.9, 7.10, 7.11, 7.13
**Implementation**: Playwright suites under the repo's Playwright tree, run via the existing `infernix-playwright:local` image; `web/test/fixtures/`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`

### Objective

Land the E2E test layer through `docker compose run --rm playwright`. Substrate-agnostic at
the browser layer. Includes per-model smoke matrix.

### Deliverables

- Playwright flows: auth lifecycle (signup, login, logout, re-login, JWT refresh); context
  lifecycle (new-context defers, rename, soft-delete, select); conversation lifecycle
  (submit, response, two-in-a-row queued, cancel-mid-inference, order preservation across
  reload); draft lifecycle (type, refresh, restored, per-context isolation, submit clears
  draft); artifact upload lifecycle per supported artifact class; artifact download plus
  inline render, bounded preview, browser-native PDF handling, or download-only handling;
  generated-artifact lifecycle; multi-tab convergence; client reconstitution via Playwright
  Browser Context storage-clear; pod-failover-from-browser
- **Per-Model Smoke Matrix**: parameterized flow that reads the active substrate's generated
  `.dhall`, iterates every catalog entry whose engine cell for the active substrate is not
  `Not recommended`, creates a fresh context pinned to that model, submits a
  family-appropriate canonical input from `web/test/fixtures/`, asserts Completed
  `InferenceResult`, asserts artifact appearance and rendering
- `web/test/fixtures/` checked-in canonical inputs: `audio/short-speech.wav`,
  `audio/short-mix.wav`, `audio/short-pitch.wav`, `image/score-page.png`, `prompts/*.txt`

### Validation

- `infernix test e2e` runs the Playwright suite via the dedicated container
- per-model smoke matrix has one passing flow per non-`Not recommended` row in the README
  matrix for the active substrate; failure on any row fails the suite
- the Playwright source is byte-identical across `apple-silicon`, `linux-cpu`, `linux-gpu`;
  substrate selection lives only in the `.dhall` the demo app reads

### Remaining Work

All work pending.

---

## Sprint 7.15: Documentation Closure [Planned]

**Status**: Planned
**Blocked by**: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12, 7.13, 7.14
**Implementation**: every doc named in this phase
**Docs to update**: all docs named in Documentation Requirements below

### Objective

Finalize the governed docs touched by Phase 7. Every doc is aligned with the implemented
behavior. `infernix lint docs` is clean.

### Deliverables

- every new doc named below exists with the required metadata block
- every existing doc named below is updated for the durable-context surface
- the `Application Library Boundary` extension to
  `documents/engineering/implementation_boundaries.md` codifies the shared-vs-demo-vs-daemon
  module ownership
- `infernix lint docs` passes

### Validation

- `infernix lint docs` exits zero
- a fresh contributor can locate the canonical home for every Phase 7 topic via the suite
  index

### Remaining Work

All work pending.

---

## Documentation Requirements

**Engineering docs to create/update:**
- [../documents/engineering/implementation_boundaries.md](../documents/engineering/implementation_boundaries.md) — Application Library Boundary section codifying shared-vs-demo-vs-daemon ownership
- [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md) — presigned-URL contract for the durable-context demo path

**Architecture docs to create/update:**
- [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md) — new product-agnostic primitives doc
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — demo-specific bindings on top of the primitives doc
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — durable-context surface delta and new view modules
- [../documents/architecture/overview.md](../documents/architecture/overview.md) — pointer to the new designs

**Development docs to create/update:**
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — new authoritative test plan
- [../documents/development/frontend_contracts.md](../documents/development/frontend_contracts.md) — new ADTs and Haskell-first logic discipline
- [../documents/development/testing_strategy.md](../documents/development/testing_strategy.md) — three validation layers cross-link
- [../documents/development/chaos_testing.md](../documents/development/chaos_testing.md) — demo chaos cases
- [../documents/development/purescript_policy.md](../documents/development/purescript_policy.md) — new view modules note

**Reference docs to create/update:**
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — `/auth`, `/ws`, `/api/objects` routes
- [../documents/reference/api_surface.md](../documents/reference/api_surface.md) — `/api/objects` HTTP route

**Tools docs to create/update:**
- [../documents/tools/keycloak.md](../documents/tools/keycloak.md) — new authoritative Keycloak surface
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — demo conversation and metadata topics
- [../documents/tools/minio.md](../documents/tools/minio.md) — demo artifact bucket

**Operations docs to update:**
- [../documents/operations/cluster_bootstrap_runbook.md](../documents/operations/cluster_bootstrap_runbook.md) — Keycloak addition note

**Root docs to update:**
- [../README.md](../README.md) — short orientation paragraph framing the durable-context Chat surface as the supported manual-inference path
- [README.md](README.md) — Phase 7 row in Document Index and Phase Overview
- [00-overview.md](00-overview.md) — Phase 7 in architecture baseline and dependency chain
- [system-components.md](system-components.md) — Keycloak, demo MinIO bucket, demo Pulsar topic families, new routes

**Cross-references to add:**
- align Phase 7 entries in [README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) with
  [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md) and
  [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md)
