# Phase 7: Demo App Multi-User Durable Context

**Status**: Active — Sprints 7.30–7.33 add implementation and validation work to this phase's existing scope. No remediation code or new validation result is claimed by this documentation update.

**Referenced by**: [README.md](README.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md),
[../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md),
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md),
[../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the multi-user, durable-context shape of the `infernix-demo` workload —
> Keycloak self-signup, WebSocket post-login transport, Pulsar-backed per-context conversation
> history, MinIO-backed artifact upload/download with audio/image/video rendering, stateless
> backend pods, single-flight per-context inference dispatch, and the validation surface that
> proves all of it under load and pod failure.

## Phase Status

Sprints 7.1–7.29 retain their closed headings and only their established scope. Durable dispatch, context reconstruction, cancellation, and media rendering require implementation work. An empty dispatcher reducer resumes an existing durable cursor; KV bookkeeping stores hashes without rebuilding or using engine state; cancellation releases a queue slot without stopping inference; text preview buffers whole objects; MIDI samples are absent. A retained Phase 7 accelerator attestation is missing.

The missing Phase 7 entry in [Recorded Attestations](cohort-validation-waves.md#recorded-attestations) remains unresolved. Preserve closed sprint headings; recover verifiable underlying evidence or rerun the required gates before phase closure.

Implementation follows the named code-side prerequisites below; pending accelerator scheduling alone does not block subsequent implementation. Remediation code-side closure is incomplete. The selected sign-off is `linux-gpu` plus native `linux-cpu`, recorded in Wave R7 in [cohort-validation-waves.md](cohort-validation-waves.md), against one frozen implementation. Neither lane has validated the new criteria. A pending wave is validation-only once the machine-independent gates pass.

## Current Repo Assessment

The conversation event types, Pulsar log, WebSocket transport, and MinIO proxy exist. Sprint 7.30 owns restart-safe dispatch, Sprint 7.31 owns actual conversation/KV reconstruction and reuse, Sprint 7.32 owns engine cancellation, and Sprint 7.33 owns bounded previews and verified MIDI/media rendering. A mounted widget, disposition attribute, hash match, or terminal-shaped event is not evidence that the corresponding operation occurred.

## Architecture

The product-agnostic design lives at
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the demo-specific bindings live at
[../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md);
the supported three-role daemon model (stateless frontend, stateless coordinator,
substrate-specific engine pools) lives at
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) and
[../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md);
this section names the load-bearing decisions so phase readers can locate the right module
boundary without re-reading the design docs.

- **Identity.** Keycloak release with self-signup on, email verification off, username/password
  only. Browser obtains a JWT and presents it on both HTTP and WS handshakes. Backend validates
  against Keycloak JWKS. `userId = sub`.
- **Transport.** WebSocket for chat, drafts, context list, progress, and artifact-ready
  notifications. HTTP (same JWT) for artifact upload/download through the webapp `/api/objects`
  proxy; binary bytes traverse the demo backend, and the browser never receives a presigned MinIO
  URL.
- **Statelessness.** Backend pods hold zero per-user state across requests. No demo-backend
  Postgres is added; the existing Keycloak Patroni cluster are
  unchanged. The browser holds no durable state — full reconstitution from server-
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
  demo backend with per-user scope checks.
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
  content hash of the deterministic projection at the dispatch offset). A prefix hash identifies
  input; it does not prove an engine constructed or reused KV state. Sprint 7.31 requires actual
  durable-prefix reconstruction, verified backend state, model/execution/user identity, and
  explicit replay when a backend cannot reuse KV state.
- **Failure semantics.** Every retry path is idempotent at the broker level via Pulsar
  broker-level deduplication plus namespace producer-dedup policies on conversation,
  context, draft, inference-request, and inference-result topics, keyed by upstream
  `MessageId`s or application mutation keys. Crashes degrade to redeliveries and cache
  misses, never data loss or duplication.

### Reuse Boundary

Phase 7 introduces four concept-named module groups, mapped onto the three daemon roles in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md),
so the durable-context primitives are reusable by any future SPA-like application built on
the inference platform:

- **Shared library** (`Infernix.Conversation.*`, `Infernix.Topic.*`, `Infernix.Dispatch.*`,
  `Infernix.Objects.*`, `Infernix.Auth.*`, `Infernix.Bridge.*`) — product-agnostic,
  parameterized in topic namespace, bucket name, and JWT issuer/audience.
- **Demo binary / frontend** (`Infernix.Demo.*`) — Keycloak realm wiring, WS upgrade, HTTP
  route handlers, WS envelope tagged-sum types, first-run bootstrap. Loads in the
  `infernix-demo` Deployment.
- **Coordinator daemon** (stateless Pulsar coordination) — loads
  `Infernix.Dispatch.SingleFlight`, `Infernix.Bridge.Result`, and the optional batcher from
  the shared library. Loads in the `infernix-coordinator` Deployment. Must not import
  `Infernix.Demo.*`, `Infernix.Objects.Presigned`, `Infernix.Auth.Jwt`, any WebSocket module,
  or `Infernix.Runtime.*`.
- **Engine daemon** (`Infernix.Runtime`, `Infernix.Runtime.Cache`,
  `Infernix.Runtime.KVCache`, `Infernix.Runtime.Worker`) — imports
  `Infernix.Conversation.Reducer` and `Infernix.Conversation.Hash` for engine-side KV-cache
  consistency only. Loads in the `infernix-engine` Deployment on Linux substrates and as the
  on-host daemon on Apple silicon. Must not import `Infernix.Demo.*`,
  `Infernix.Objects.Presigned`, `Infernix.Auth.Jwt`, `Infernix.Dispatch.SingleFlight`,
  `Infernix.Bridge.Result`, or any WebSocket module.
- **Daemon orchestration** (`Infernix.Runtime.Daemon`) — owns process role startup,
  readiness markers, coordinator-loop startup, and the process-local engine KV-cache handle.
  `Infernix.Runtime.Pulsar` owns the shared Pulsar transport helpers and runtime loops.

The discipline is documented in
[../documents/engineering/implementation_boundaries.md](../documents/engineering/implementation_boundaries.md);
the reusable shape this discipline protects is codified in
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the placement, replica policy, pool ownership, and pinned-member routing rules are codified in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) and
[../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md).

## Sprint 7.1: Keycloak Release and Realm Pre-Seed [Done]

**Status**: Done
**Implementation**: `chart/templates/keycloak/`, `chart/values.yaml`, `src/Infernix/Cluster.hs`
**Docs to update**: `documents/tools/keycloak.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/architecture/demo_app_design.md`

### Objective

Deploy Keycloak in the HA cluster with its own Patroni Postgres backend and a pre-seeded realm
that allows self-signup with username/password and skips email verification.

### Deliverables

- Helm templates under `chart/templates/keycloak/` — `deployment.yaml` (preferred anti-affinity,
  JDBC wiring to the Patroni `pgbouncer` Service, `--import-realm` from the mounted ConfigMap,
  routed `--hostname=<edge>/auth`, TCP readiness/liveness probes, bootstrap admin credentials from
  `infernix-keycloak-admin`), `service.yaml` (ClusterIP on 8080 so the routed `/auth` HTTPRoute
  reaches it without a NodePort), `configmap-realm-import.yaml`, `secret-admin.yaml` (bootstrap
  admin credentials the operator rotates through the Keycloak admin UI after first login), and
  `poddisruptionbudget.yaml` (`maxUnavailable: 1`), all gated on
  `.Values.demo.enabled && .Values.keycloak.enabled`
- `chart/Chart.yaml` declares a second `pg-db` dependency aliased to `keycloakpg`, gated on
  `upstreamCharts.keycloakpg.enabled`; `chart/values.yaml` carries the matching `keycloakpg:`
  Patroni stanza (3-instance HA, `infernix-manual` storage class, pgbackrest backups) and the
  `keycloak:` stanza with image from the registry, demo-gating tied to `demo_ui`, realm and client
  identifiers, routed external base URL, and admin/database secret names. The backing Patroni
  cluster is HA; the Keycloak application itself runs one local-demo replica. Multi-replica
  Keycloak serving is deliberately not enabled — it requires proxy affinity or a clustered cache,
  neither of which the supported local-demo shape carries
- realm definition with `registrationAllowed: true`, `verifyEmail: false`, an `infernix-spa`
  public OIDC client with PKCE, edge-aware redirect URI / web-origin defaults, and a length-only
  password policy, plus an in-binary `reconcile-keycloak-realm` lifecycle phase that patches the
  realm flags, SPA redirect URIs, web origins, and PKCE setting through the Keycloak admin API
  after final rollout so repeat `cluster up` runs do not drift
- `src/Infernix/Cluster.hs.reconcileFinalPhaseOperatorManagedPersistentVolumes` runs after the
  no-hooks FinalPhase chart apply creates the `keycloak-postgresql` PerconaPGCluster CR, waits for
  the Keycloak operator-managed PVCs, creates matching PVs, and binds them;
  the warmup-only reconcile cannot see Keycloak's claims because that CR is FinalPhase-gated
- `src/Infernix/Cluster/PublishImages.hs.pushUpstreamMultiArchViaImagetools` falls back to
  `skopeo copy --override-os=linux --override-arch=amd64` for upstream multi-arch images, derives
  content-addressed registry tags from the upstream linux/amd64 manifest when the containerd image
  store leaves the pulled tag non-inspectable, and routes non-taggable upstream tags straight
  through the fallback copy
- `/auth` route added to the Haskell route registry source so the auto-rendered registry
  emits it into README, `documents/reference/web_portal_surface.md`, and publication JSON
- `cluster up` reconciles Keycloak after the registry is responsive, before the demo workload starts
  on the durable-context surface. With `demo_ui = false`, `upstreamCharts.keycloakpg.enabled`,
  `keycloak.enabled`, the `prepare-keycloak-storage` PV reconcile, and the realm reconcile all
  follow the substrate's demo flag
- `web/playwright/inference.spec.js` carries the routed Keycloak browser smoke: an OIDC
  authorization-code plus PKCE flow at `/auth`, the registration link, a fresh username/password
  account without email verification, and the return to `/` with an authorization code and the
  original state

### Validation

- `cluster up` with `demo_ui = true` deploys Keycloak and reports readiness
- a browser at `/auth` reaches the Keycloak login page
- signup with a fresh username and password succeeds without an email-verification step
- `infernix kubectl -n platform get postgrescluster` shows the Keycloak Patroni cluster
- when the demo UI is disabled, the Keycloak release and its Patroni cluster are absent

### Remaining Work

None.

---

## Sprint 7.2: Browser-Contract ADTs and WS Envelope [Done]

**Status**: Done
**Implementation**: `src/Infernix/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`, `web/test/Infernix/Web/ContractsSpec.purs`, `src/Infernix/CLI.hs` (import normalization)
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
- the generator footer in `src/Infernix/Web/Contracts.hs` (`renderPhase7PursInstances`,
  `renderPursRecordKind`, `renderPursSum`, `renderShowInstanceIfAllNullary`) emits hand-rolled
  Simple.JSON `WriteForeign` / `ReadForeign` instances for every Phase 7 type plus `Show`
  instances for every nullary sum, and the import normalization in `src/Infernix/CLI.hs` adds
  `Foreign (ForeignError(..), fail) as Foreign` to the generated module
- the wire encoding matches Aeson's `TaggedObject "tag" "contents"` exactly: string-wrapping
  newtypes (`UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`, `ArtifactMimeType`)
  encode as bare strings, record-wrapping newtypes unwrap their inner record, nullary sums emit
  `{"tag": "ConstructorName"}`, positional sums emit `{"tag": ..., "contents": ...}`, and
  record-syntax sums spread the constructor's fields beside the `tag` key

### Validation

- `infernix internal generate-purs-contracts` produces deterministic output
- `infernix test unit` exercises encode/decode roundtrip across the new types in both the
  Haskell and PureScript suites
- repeated codegen runs produce byte-identical output

### Remaining Work

None.

---

## Sprint 7.3: WS Endpoint, JWT Validation, and Stateless Coordination [Done]

**Status**: Done (code-side closed for routed JWT, malformed-frame, expired-token, and per-context Reader browser coverage; Apple cohort gate closed on the selected accelerator plus `linux-cpu`; LinuxCpu frontend pod replacement coverage implemented in Sprint 7.14 on the recorded cohort validation and passed the native `linux-cpu` full-suite gate the same day; `linux-gpu` full-suite validation passed on the recorded cohort validation on the selected accelerator plus `linux-cpu`; browser-level pod-failover closed on the recorded cohort validation with the mounted-source `linux-gpu` routed E2E pass.)
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
- `Infernix.Demo.WebSocket` handles WS upgrade, JWT validation, framed envelope routing.
  `wsApplication` mounts on `/ws`, upgrades WAI requests through
  `Network.Wai.Handler.WebSockets.websocketsOr`, and validates the bearer JWT carried in either
  the `Authorization` header or the `?token=` query parameter — the query fallback exists because
  browsers cannot set headers on `WebSocket(...)` connects. The handshake calls
  `Infernix.Auth.Jwt.verifyAndParseJwt` and captures `UserId` from the `sub` claim
- decoded client frames are classified through the pure `classifyClientMessage` helper;
  state-changing frames route through `wsDispatchClientMessage` into
  `Infernix.Runtime.Pulsar.publishDemoClientMessage`, so prompt, cancel, draft, and context
  metadata frames publish typed JSON events to their durable Pulsar topic families. A malformed
  frame is answered with a tagged `ServerError` carrying
  `serverErrorErrorCode = "ws_frame_decode_failed"`
- the session starts per-user context-list/draft Reader streams after `ClientHello` and
  per-context conversation Reader streams after `ClientSubscribeContext`; outbound frames are
  serialized behind a per-session send lock
- chart Service for `infernix-demo` sets `sessionAffinity: None`; no client-IP or cookie
  affinity on the HTTPRoute either
- `/ws` route added to the Haskell route registry source
- per-WS state holds only the WS handle, the authenticated `UserId`, and Pulsar Reader
  cursors/projections; no per-user identity cache
- the mounted `ClusterConfig.keycloak` wiring the handshake reads is the routed issuer base at
  `/auth`, the public SPA client id `infernix-spa`, and the in-cluster Keycloak service URL on
  port `8080` with the `/auth/realms/.../certs` JWKS path

### Validation

- WS connection with a valid JWT succeeds; invalid/expired JWT closes the WS with a typed
  error
- `infernix kubectl -n platform get service/infernix-demo -o yaml | grep sessionAffinity`
  reports `None`
- a chaos test (Sprint 7.14) kills the WS-hosting pod and asserts the client reconnects to a
  different replica with no state loss

### Remaining Work

None.

---

## Sprint 7.4: Conversation Primitives in Shared Library [Done]

**Status**: Done
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
- conversation events ride the Pulsar WebSocket transport as JSON payloads base64-encoded into
  the producer envelope. The supported wire format is the Aeson instances in
  `Infernix.Web.Contracts`; a parallel protobuf schema for `ConversationEvent` is deliberately
  not part of the supported contract
- broker-side dedup is enabled both at the Pulsar broker config layer
  (`brokerDeduplicationEnabled = true` in `chart/values.yaml`) and at namespace scope, where
  `reconcileSupportedNamespaces` POSTs `true` to `/admin/v2/namespaces/<ns>/deduplication` for
  `infernix/demo` and `infernix/system`. The WebSocket publisher uses mutation-scoped
  one-message producer names plus `initialSequenceId` baselines derived from client idempotency,
  prompt, draft, or context keys; the dispatcher uses stable per-context producer scoping with
  monotonic broker `MessageId`-derived sequence ids
- the Haskell style gate rejects demo, runtime, auth, object-presign, and WebSocket imports from
  the conversation primitive modules

### Validation

- Haskell property tests cover reducer determinism, idempotency dedup, hash chain
  monotonicity, and patch-stream equivalence to state-snapshot equality
- integration test (Sprint 7.14) round-trips a conversation through a real Pulsar topic with
  producer dedup verified via simulated double-publish
- no module under `Infernix.Demo.*` is imported by these shared modules

### Remaining Work

None.

---

## Sprint 7.5: Compacted Metadata Patterns in Shared Library [Done]

**Status**: Done
**Implementation**: `src/Infernix/Topic/Metadata.hs`, `src/Infernix/Topic/Drafts.hs`, `src/Infernix/Runtime/Pulsar.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`

### Objective

Land the compacted-topic projection patterns used by the contexts metadata topic and the
drafts topic, plus the namespace-level compaction policy required by the broker.

### Deliverables

- `Infernix.Topic.Metadata` — generic compacted-topic projection pattern with keyed-event fold
  helpers
- `Infernix.Topic.Drafts` — generic compacted-keyed-mutable-state pattern with
  upsert-by-key and clear-by-key fold helpers
- namespace-level compaction policy reconciled on `cluster up` for the `infernix/demo`
  namespace that owns `demo.user.*` metadata topics

### Validation

- unit tests publish N events to the shared compacted projection fold with M distinct keys and
  assert the projection yields exactly M latest values
- the Linux GPU integration suite publishes multiple context and draft records per key, reads the
  `infernix/demo` namespace compaction threshold from Pulsar admin, explicitly compacts the live
  contexts and drafts topics, and uses a Java Pulsar client with `readCompacted(true)` to assert
  exactly one latest record per `contextId`
- validation commands passed on the recorded cohort validation:
  `cabal build exe:infernix test:infernix-unit test:infernix-integration`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `cabal test infernix-integration` inside the Linux GPU outer container

### Remaining Work

None.

---

## Sprint 7.6: Single-Flight Dispatcher in Shared Library [Done]

**Scope boundary**: Pure reducer coverage does not restore acknowledged history at a durable cursor. Sprint 7.30 owns runtime reconstruction; Sprint 7.32 owns engine cancellation.

**Status**: Done
**Implementation**: `src/Infernix/Dispatch/SingleFlight.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`

### Objective

Land the per-context single-flight inference dispatcher as a pure fold over the conversation
log. Subscribe to each active conversation topic with a Pulsar named `Failover` subscription
so exactly one pod is the active dispatcher per context at a time.

### Deliverables

- `Infernix.Dispatch.SingleFlight` — pure dispatch rule, cancellation handling, inference
  request envelope construction including `prefixHash`, `conversationLogOffset`, `causalRef`,
  `userId`, `contextId`
- Pulsar producer dedup enabled on `inference.request.<mode>` keyed by `userPromptMessageId`
- failover-subscription wiring per conversation topic. `Runtime/Pulsar.hs.runDispatcherLoop`
  polls the supported demo namespace through Pulsar admin
  `GET /admin/v2/persistent/<tenant>/<namespace>`, extracts `(UserId, ContextId)` pairs from any
  topic matching the `demo.conversation.<userId>.<contextId>` shape, and forks one per-context
  worker keyed by `ContextId` (tracked in a process-local set so repeated discovery cycles do not
  start duplicates). The worker subscribes Failover with subscription name
  `dispatcher-<contextId>` and `subscriptionInitialPosition=Earliest` so a recovered replica
  replays from the start of the log, folds each decoded `ConversationEvent` through
  `Conversation.Reducer.stepReducer`, and on `DispatchPrompt` publishes the `InferenceRequest`
  envelope with producer name `dispatcher-<contextId>` and a sequence id derived from the prompt
  `MessageId`, so the broker dedup gate collapses retries from a recovered replica
- the dispatcher acks each message immediately after stepping the reducer, so a recovered replica
  resumes at the cursor with empty in-memory state. Producer dedup prevents duplicate dispatches;
  the single-flight queue guard ("hold prompt 2 until prompt 1 resolves") covers only the case
  where the recovered replica observes both prompts in the same session, and crash-tolerant state
  recovery rests on the coordinator-replacement validation rather than on in-memory continuity
- the daemon log reports `serviceDispatcherMode: per-context-failover` when the daemon role is
  `Coordinator`
- the dispatcher is instantiated in the `infernix-coordinator` Deployment, not in the engine
  pod or any app pod, per the daemon role assignment in
  [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md);
  shared-library modules in this sprint must not import `Infernix.Runtime.*`,
  `Infernix.Demo.*`, `Infernix.Objects.Presigned`, `Infernix.Auth.Jwt`, or any WebSocket
  module

### Validation

- unit property test exercises the pure-fold rule across arbitrary log prefixes including
  cancels, two-in-a-row prompts, and out-of-order results
- integration chaos test (Sprint 7.14) kills the active dispatcher mid-prompt; asserts
  Failover promotes a surviving pod and producer dedup prevents a duplicate dispatch
- two prompts in a row in the same context produce exactly two inference requests in the
  correct order

### Remaining Work

None.

---

## Sprint 7.7: Truly Stateless Daemon Topology and HA Chart [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime/Pulsar.hs` (batch forwarding + bootstrap subscription wiring), `src/Infernix/Models.hs` (`inference.batch.<mode>` for every substrate; `infernix/system/model.bootstrap.request` topic family), `src/Infernix/DemoConfig.hs` (split `cluster` role into `coordinator` + `engine`; add `modelsBucket` and `modelBootstrapTopic` fields), `src/Infernix/Runtime/Cache.hs` (prior `objectStoreRoot`, `localPathFromUri`, `cacheManifestProtoPath`, `durableArtifactPathFor`, `sourceManifestPathFor`, and the `s3://infernix-runtime/` URI scheme; replaced by a MinIO-backed model loader and an `emptyDir`-backed LRU eviction manager), `src/Infernix/Runtime.hs` (prior the 80-char `buildPayload` branch; text outputs always inline, binary outputs carry a MinIO `ObjectRef`), `src/Infernix/Demo/Api.hs` (prior `serveObject` and the `/objects/:objectRef` route), `src/Infernix/Routes.hs` (prior the `/objects` route entry), `src/Infernix/Service.hs` (retained `engine.lock` safety check for non-Apple engine roles; Apple uniqueness is superseded by stable host-id pool membership and pinned `Exclusive` routing), `src/Infernix/Cluster.hs` (Helm rollout for the new Deployments + buckets + `infernix/system` namespace + `model.bootstrap.request` topic), `src/Infernix/Bootstrap/Models.hs` (coordinator's bootstrap Failover subscription, download-from-upstream + upload-to-MinIO with `.ready` sentinel), `src/Infernix/Bridge/Result.hs` (shared-library result-bridge, replaces the previously planned `Infernix.Demo.ResultBridge`), `python/adapters/model_cache.py` (shared adapter helper exposing `get_model_path(model_id) -> path`, MinIO client + LRU eviction rooted at `/model-cache`, uniform across every engine), `python/adapters/common.py`, `python/adapters/diffusers_python.py`, `python/adapters/pytorch_python.py`, `python/adapters/transformers_python.py`, `python/adapters/vllm_python.py` (adapter integration with typed cache/config helpers), `chart/templates/deployment-coordinator.yaml` (no PVC), `chart/templates/deployment-engine.yaml` (no PVC; single `emptyDir` volume `model-cache` with `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}`, default `64Gi`, and explicit CPU/memory resources), `chart/templates/poddisruptionbudget-coordinator.yaml`, `chart/templates/poddisruptionbudget-engine.yaml`, `chart/templates/poddisruptionbudget-demo.yaml`, `chart/values.yaml` (`infernix-models` and `infernix-engine-artifacts` always-on; `infernix-demo-objects` demo-gated; `coordinator`/`engine`/`demo` HA stanzas; `engine.modelCache.sizeLimit` and `engine.resources` knobs), `src/Infernix/Substrate.hs` (substrate decoder type — reflected schema, no tracked `.dhall`: coordinator + engine role schemas; `modelsBucket : Text`; `modelBootstrapTopic : Text`; per-model `downloadUrl : Text`), `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` (prior fused Deployment, service-data PVC, object-store URI, and placeholder-bucket cleanup ledger)
**Docs to update**: `documents/architecture/daemon_topology.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/durable_context_design.md`, `documents/engineering/object_storage.md`, `documents/engineering/portability.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/k8s_storage.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `README.md`

### Objective

Land the supported three-role daemon topology — stateless frontend, stateless coordinator,
stateful engine — with **no PVC on any daemon**, **MinIO + Pulsar as the only durable state**,
and a **uniform one-engine-per-node policy on every substrate**. Retire the fused
`infernix-service` Deployment with role-specific `infernix-coordinator` and `infernix-engine`
Deployments; retire `./.data/object-store/`, the `s3://infernix-runtime/` URI scheme, the
80-char inline-payload threshold, the `/objects/:objectRef` route, and the chart-reserved
`infernix-runtime` + `infernix-results` placeholder buckets. Model weights are pulled from
the new `infernix-models` MinIO bucket through a coordinator-owned at-least-once bootstrap
workflow whose producer dedup and terminal sentinel collapse duplicates at the effect; engine pods
stage weights into a bounded `emptyDir` cache. See
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
and [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md)
for the authoritative target shape.

### Deliverables

- **No PVC on any daemon.** The coordinator and demo Deployments are PVC-free; the engine
  Deployment mounts a single `emptyDir` volume `model-cache` with
  `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}` (default `64Gi`) at `/model-cache`,
  enforced by kubelet so the pod cannot exhaust node disk
- **Strict engine placement.** On Linux substrates this is enforced by
  `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity on the engine Deployment's own
  label with `topologyKey: kubernetes.io/hostname`; the retained `engine.lock` is only a
  non-Apple engine-role safety check. Apple silicon uses stable host ids in the engine-pool graph:
  normal Apple pools use `Shared` subscriptions across host members, and exact-host routes use
  derived pinned topics with `Exclusive` broker ownership.
- **Batch handoff topic family.** `src/Infernix/Runtime/Pulsar.hs:drainTopic` forwards to
  `daemonConfigHostBatchTopic` whenever that field is set, irrespective of `runtimeMode`, and
  `inference.batch.<mode>` topic definitions exist for `linux-cpu` and `linux-gpu`
- **Introduce the `infernix/system` Pulsar namespace** carrying the
  `model.bootstrap.request` topic; request message key `modelId` plus
  attempt-scoped producer dedup keyed by `modelId@requestedAt`
- **Lazy model-weight population to MinIO with an effectively-once observable outcome.** Engine sees an
  uncached model → publishes a bootstrap request; the coordinator's third Failover
  subscription (alongside dispatcher and result-bridge) downloads from the upstream URL
  carried in the active substrate `.dhall`, PUTs each file under
  `infernix-models/<modelId>/<filename>`, PUTs the `.ready` sentinel last, then publishes
  `model.bootstrap.ready.<modelId>`. Engines wait on the ready event with a 900-second bounded
  cold-bootstrap timeout and load from MinIO
- **Three MinIO buckets, drop the placeholders.** `infernix-models` is always-on and holds
  platform model weights, tokenizers, and configs under `<modelId>/<filename>` with a
  `.ready` sentinel; `infernix-engine-artifacts` is always-on and holds optional immutable
  engine payloads; `infernix-demo-objects` is demo-gated and holds user uploads plus
  engine-generated artifacts under `users/<userId>/contexts/<contextId>/{uploads,generated}/`.
  The chart-reserved `infernix-runtime` and `infernix-results` placeholders are removed
- **Uniform model-cache adapter helper.** `python/adapters/model_cache.py` defines
  `get_model_path(model_id) -> filesystem path`, the boto3 MinIO download client, and the
  LRU eviction logic. The contract is that every adapter routes through this helper,
  regardless of whether the underlying engine library supports bytes-loading; the first
  call populates `/model-cache/<modelId>/` from `infernix-models`, subsequent calls reuse
  the local copy, and eviction runs when the directory tree approaches `sizeLimit`.
  `model_cache.py` carries the boto3 MinIO download client, the eviction logic, and the
  `get_model_path(model_id) -> path` contract, and the adapters call it. The size-limited
  `/model-cache` `emptyDir` is mounted by `chart/templates/deployment-engine.yaml`, and the
  engine's cache root is read from the cluster contract
- **Result-payload topology simplified.** Delete the 80-char threshold branch in
  `Runtime.hs:75-91`; text outputs always ride inline in the protobuf result message; binary
  outputs are written by the adapter directly to `infernix-demo-objects` at the
  appropriate per-user prefix and the result message carries an `ObjectRef` (bucket + key),
  not host-filesystem path nor inline bytes
- **Delete prior surfaces:** `./.data/object-store/` tree, `objectStoreRoot` plumbing in
  `Runtime/Cache.hs`, the `s3://infernix-runtime/` URI scheme + `localPathFromUri` mapping,
  the `/objects/:objectRef` HTTP route handler in `Demo/Api.hs`, and the route registry
  entry in `Routes.hs`. `Runtime/Cache.hs` operates on
  `modelCacheRoot/<runtimeMode>/<modelId>/` with manifests at `manifest.pb` beside the cached
  weight files, and `Demo/Api.hs.sourceArtifactManifestUri` plus
  `Storage.hs.cacheManifestToProto` name `minio://infernix-models/…` and
  `minio://infernix-demo-objects/…` prefixes
- **Worker envelope carries model metadata, not paths.** The `WorkerRequest` proto envelope drops
  `artifact_bundle_path` / `source_manifest_path` / `cache_manifest_path` and carries
  `display_name` / `family` / `artifact_type` / `runtime_lane` read straight from the daemon's
  already-loaded substrate catalog; `python/adapters/common.py.load_adapter_context` reads them
  off the wire instead of synthesising JSON files
- **Producer-dedup plumbing.** `publishTopicPayload` takes
  `PublishOptions { publishProducerName, publishSequenceId }`, `buildProducerSocketPath` appends
  a stable `producerName` plus optional `initialSequenceId` to the WebSocket producer URL, and
  the daemon's request consumer derives a per-message sequence id from the envelope's
  `userPromptMessageId` via `inferenceRequestSequenceId`, which packs a Pulsar
  `<ledgerId>:<entryId>:...` MessageId into a 64-bit value
- **Move the planned `Infernix.Demo.ResultBridge` to `src/Infernix/Bridge/Result.hs`**
  (shared library; loaded by coordinator). The demo binary carries no result-bridge module
- **Three Deployments + PDBs**: `infernix-coordinator` (replicas ≥ 2 default, preferred
  anti-affinity, production infrastructure), `infernix-engine` (Linux engine-pool workload with
  operator-set replicas and GPU resource shape on `linux-gpu`; Apple engine members run on host),
  `infernix-demo` (replicas ≥ 2 default; preferred anti-affinity; demo-gated). PodDisruptionBudgets
  `maxUnavailable: 1` on Kubernetes workloads. Earlier Sprint 7.7 wording that demo-gated the
  coordinator is superseded by Sprint 7.24.
- **Production (`demo_ui = false`) keeps coordinator plus engine pools.** Frontend/demo API,
  identity, and demo-owned routes or buckets are demo-gated; production bootstrap semantics for lazy
  model population live in the coordinator.
- **Readiness probes** match the role: coordinator probes Pulsar subscription readiness;
  engine probes adapter startup; demo probes HTTP listener
- **Coordinator pod owns the only outbound-internet egress** in the supported daemon
  topology — used solely for upstream weight downloads on first use of a model.
  NetworkPolicy may scope egress to the catalog's listed download hosts; documented in
  governed docs

### Validation

- `infernix kubectl get pvc -A` returns empty (no daemon has a PVC) on `linux-cpu`,
  `linux-gpu`, and the cluster side of `apple-silicon`
- Integration test on `linux-cpu`: first inference request for an uncached model triggers
  a bootstrap, coordinator downloads from upstream and uploads to `infernix-models`,
  engine populates `/model-cache/<modelId>/`, inference completes; second request for the
  same model bypasses bootstrap; third request from a different engine node also bypasses
  bootstrap and pulls weights from `infernix-models` (not from upstream)
- Integration test on `linux-gpu`: round trip on a node with multiple NVIDIA devices;
  assert exactly one engine pod scheduled per node even when
  `engine.replicaCount > #engine-capable-nodes` (excess replicas stay `Pending`)
- Concurrency test: N engine pods request the same uncached model simultaneously; producer
  dedup + Pulsar Failover guarantees exactly one upstream download; all N engines observe
  the `.ready` sentinel and proceed
- Eviction test: trigger model loads until `/model-cache` size pressure exists; assert the
  adapter helper evicts LRU entries and continues to serve requests; the engine pod is
  never restarted by kubelet for ephemeral-storage exhaustion
- Pod-restart test: kill an engine pod after it has cached several models; new engine pod
  starts with empty `/model-cache`; the next request repopulates from `infernix-models`
  (not from upstream); inference completes
- Chaos: kill the active coordinator pod mid-bootstrap; the rescheduled coordinator resumes;
  duplicate `.ready` sentinel publications collapse at the effect through producer dedup;
  no duplicate upstream download
- Chaos: kill an engine pod mid-inference; Pulsar redelivers the unacked batch; a surviving
  engine on another node rebuilds the KV cache from the conversation log via `prefixHash`;
  producer dedup on `inference.result.<mode>` prevents a duplicate result
- Chaos: drain a node hosting an engine pod; the engine PDB blocks the drain until another
  engine pod is available cluster-wide; the cluster keeps serving inference
- Engine placement enforcement: on Linux,
  `kubectl scale deployment/infernix-engine --replicas=N+1` (where N = engine-capable
  nodes) leaves one replica `Pending` with the anti-affinity rejection message. The older Apple
  `engine.lock` duplicate-daemon diagnostic is historical and is superseded by stable host-id pool
  membership plus pinned `Exclusive` routing in Sprint 7.24
- Production-shape test: deploy with `demo_ui = false`;
  `infernix kubectl -n platform get deployments` returns coordinator plus engine-pool workloads;
  `infernix-models` and `infernix-engine-artifacts` buckets are present;
  `infernix-demo-objects` bucket is absent;
  `/objects/:objectRef` route is not registered
- Per-engine smoke matrix: for every non-`Not recommended` row in the README matrix,
  confirm each adapter produces a valid deterministic harness result (text or binary
  `ObjectRef`) on the appropriate substrate
- `infernix lint chart`, `infernix lint docs`, `infernix lint files`,
  `infernix docs check` all exit zero

### Remaining Work

None.

---

## Sprint 7.8: Engine Prefix-Hash Cache Consistency and Result Writeback [Done]

**Scope boundary**: This heading retains envelope/hash-bookkeeping and bridge scope only. Actual log reconstruction and backend KV reuse remain Sprint 7.31 work; engine cancellation remains Sprint 7.32 work.

**Status**: Done
**Implementation**: `src/Infernix/Runtime/*`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/Runtime/KVCache.hs`, `src/Infernix/Runtime/Pulsar/Failover.hs`, `tools/generated_proto/` (or upstream `.proto`), `src/Infernix/Bridge/Result.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Make the engine's KV cache consistency with the Pulsar SSoT provable and crash-tolerant. Land
the result-to-conversation bridge that writes `InferenceResult` events back to the per-context
conversation topic, instantiated in the `infernix-coordinator` Deployment per the daemon role
assignment in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md).

### Deliverables

- inference request envelope (proto + Haskell records) extended with `prefixHash`,
  `conversationLogOffset`, `causalRef`, `userId`, `contextId`
- inference result envelope extended with `causalRef` and a `Cancelled` status variant. The
  `InferenceResult` proto carries `user_id` and `context_id` alongside `causal_ref`, and the
  `Infernix.Types.InferenceResult` domain record carries the matching
  `resultUserId` / `resultContextId` / `resultCausalRef` fields with Aeson `omitempty` defaults
  so prior callers round-trip unchanged. `publishedResultFromRequest` propagates
  `user_id` / `context_id` / `user_prompt_message_id` from the request so the bridge has the
  routing fields it needs, and results missing those fields (the Phase 4 manual-inference path)
  are skipped cleanly without ack failure rather than breaking that path
- engine adapter / runtime reuses `Infernix.Conversation.Reducer` and
  `Infernix.Conversation.Hash` to verify `prefixHash` before reusing any KV cache; rebuild on
  miss. `src/Infernix/Runtime/KVCache.hs` owns `EngineKVCache`, `KVCacheRequest`,
  `KVCacheObservation`, `observeKVCachePrefix`, `verifyKVCachePrefix`, and
  `rebuildPrefixHashFromLog`; `executeInferenceWithKVCache` threads observations through the
  worker path, and native worker output surfaces `kv-cache=reuse|rebuild` plus `kv-prefix-hash`
  when the durable-context envelope carries cache metadata
- `src/Infernix/Runtime/Daemon.hs` owns production daemon role orchestration: it allocates one
  process-local engine KV cache per daemon process, threads it into filesystem and WebSocket
  Pulsar engine request consumption, and starts coordinator loops only for the `Coordinator`
  role, leaving `Infernix.Runtime.Pulsar` as the shared transport/loop module
- `src/Infernix/Runtime/Pulsar/Failover.hs` centralizes Failover consumer naming:
  `runResultBridgeLoop`, `runDispatcherForContext`, `runContextsMetadataConsumer`, and
  `runModelBootstrapLoop` keep stable subscription names but use process-qualified consumer names
  so multiple coordinator replicas do not present identical member names during broker promotion
- the Haskell style boundary covers `src/Infernix/Runtime/KVCache.hs` alongside `Runtime.hs`,
  `Runtime/Cache.hs`, and `Runtime/Worker.hs`, so the engine-side cache consistency helper cannot
  import demo, coordinator, auth, object-presign, bootstrap, or WebSocket modules
- `Infernix.Bridge.Result` (shared library; replaces the previously planned
  `Infernix.Demo.ResultBridge` so the result-bridge is product-agnostic) — Pulsar
  Failover-subscribed consumer on `inference.result.<mode>` that writes typed `InferenceResult`
  events to the conversation topic with producer dedup keyed by
  `(userPromptMessageId, kind = InferenceResult)`; instantiated in the `infernix-coordinator`
  Deployment, not in any app pod or the engine pod
- Pulsar producer dedup enabled on `inference.result.<mode>` keyed by `userPromptMessageId`
- the engine daemon does **not** import `Infernix.Demo.*`, `Infernix.Bridge.Result`, or
  `Infernix.Dispatch.SingleFlight`

### Validation

- unit tests establish prefix-hash bookkeeping only; they do not establish engine KV construction
  or equivalent model behavior after a rebuild
- Sprint 7.31 adds the production log-reconstruction and backend-reuse/replay assertions; a
  process-local hash match cannot substitute for those results
- E2E: prompt → response cycle works end-to-end against a real model

### Remaining Work

None.

---

## Sprint 7.9: Demo MinIO Bucket and Presigned URL Minting [Done]

**Status**: Done — runtime bucket repair, the presigned/proxied grant path, and the Sprint 7.8 blocker are closed on both rebuilt-image Linux lanes.
**Implementation**: `chart/values.yaml`, `src/Infernix/Objects/Layout.hs`, `src/Infernix/Objects/Presigned.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Demo/Bootstrap.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/minio.md`, `documents/engineering/object_storage.md`, `documents/reference/api_surface.md`

### Objective

Land the demo's user-facing MinIO bucket `infernix-demo-objects` plus per-user prefix layout
and the `/api/objects` HTTP endpoint that mints presigned PUT and GET URLs scoped to the
authenticated user. The bucket is the demo-gated member of the supported three-bucket model
defined in Sprint 7.7 (`infernix-models` always-on platform weights and
`infernix-engine-artifacts` always-on engine payloads are the other two).

### Deliverables

- `infernix-demo-objects` bucket added to `chart/values.yaml` MinIO bucket list (demo-gated)
- `Infernix.Objects.Layout` — bucket and prefix conventions
  (`users/<userId>/contexts/<contextId>/{uploads,generated}/`); per-user scope helpers
- `Infernix.Objects.Presigned` — presigned URL minting helpers parameterized in the MinIO
  client config and grant-time scope check
- `Infernix.Demo.Api` — `/api/objects` HTTP route that consumes JWT, validates per-user
  scope, and returns presigned PUT or GET URLs. The handlers read the
  `Authorization: Bearer …` header, fetch the Keycloak JWKS from mounted
  `ClusterConfig.keycloak.*` through a bounded HTTP fetch so a bad JWKS route reports as a backend
  failure instead of hanging until the edge proxy timeout, call
  `Infernix.Auth.Jwt.verifyAndParseJwt`, derive `UserId` from `sub`, scope the requested object to
  `users/<userId>/contexts/<contextId>/{uploads,generated}/`, and validate that scope through
  `pathBelongsToUser`. Sprint 7.25 replaces the presigned-URL grant body with a webapp byte proxy;
  the typed disposition carried on the download grant survives that change
- `runDemoApiServer` owns a process-lifetime `JwksCache` (`IORef (Maybe (UTCTime, Jwks))`)
  threaded through both the `/ws` handshake and the `/api/objects` handlers, with a 5-minute TTL
  so a JWKS rotation surfaces within one cache cycle without an upstream certs fetch per request
- `Infernix.Demo.Bootstrap` — idempotent first-run bucket creation via `requiredDemoBuckets` plus
  the pure `planDemoBucketBootstrap` missing-bucket diff. At startup with `demo_ui = true` and a
  mounted `ClusterConfig`, `repairDemoBucketsAtStartup` creates the required demo buckets with
  presigned `PUT /<bucket>` requests (`PresignedBucketRequest` / `presignedBucketUrl`), treats
  HTTP 200 and 409 as successful idempotent outcomes, retries while MinIO converges, and logs a
  host-native skip when no cluster config is mounted
- `/api/objects` route added to the Haskell route registry source

### Validation

- integration test mints a presigned PUT for user A, uploads, mints presigned GET, downloads;
  asserts content equality
- cross-user negative test: user A and user B with the same logical context/display name receive
  distinct per-`sub` object prefixes; one user's default grant path cannot read the other's object
- when `demo_ui = false`, the bucket and `/api/objects` route are absent

### Remaining Work

None.

---

## Sprint 7.10: SPA Chat View [Done]

**Status**: Done
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `web/src/Infernix/Web/WebSocket.purs`, `web/src/Infernix/Web/WebSocket.js`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Auth.js`, `web/src/Infernix/Web/Browser.purs`, `web/src/Infernix/Web/Browser.js`, `web/src/Infernix/Web/DomEvents.purs`, `web/src/Infernix/Web/DomEvents.js`, `web/src/Infernix/Web/Router.purs`, `web/spago.yaml`, `web/test/Infernix/Web/ChatSpec.purs`, `web/src/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`, `documents/development/purescript_policy.md`

### Objective

Land the Chat view: left rail of contexts, active conversation pane, draft restore, cancel
button, two-prompt queued indicator. All state changes flow from server-sent
`ConversationStatePatch` / `ContextListPatch` / `DraftMapPatch` messages applied by trivial
mechanical helpers; no business rule is reimplemented in PureScript.

### Deliverables

- `web/src/Infernix/Web/Auth.purs` — OIDC redirect handling, in-memory JWT storage, JWT
  refresh. The typed `TokenStore` keeps the access and refresh tokens in memory; only the
  temporary PKCE verifier/state pair crosses the redirect through session storage, and logout
  clears access token, refresh token, PKCE state, and timer state
- `web/src/Infernix/Web/WebSocket.purs` — WS connect with JWT handoff, framed-envelope send
  and receive against the `Web.Socket.WebSocket` browser binding, with a small `WebSocket.js`
  FFI for raw payload coercion. The socket sends a typed `ClientHello` as its first open frame
  and reports close events to the session layer
- `web/src/Infernix/Web/Chat.purs` — left rail context list, active conversation pane, draft
  text box, cancel button; renders projected state and applies patches mechanically through
  `applyConversationStatePatch`, `applyContextListPatch`, `applyDraftMapPatch`, the
  `handleServerMessage` dispatcher, and the `pendingPromptCount` queued-prompt counter, plus the
  DOM-level `renderChatView` renderer. None of these helpers reimplements a reducer rule.
  Pending prompts are computed by matching both inference-result and cancel events against their
  target prompt ids, and the browser cancel action targets the latest unresolved server-backed
  prompt id rather than creating a local optimistic entry
- `web/src/Infernix/Web/Router.purs` — SPA route table for Chat / Artifacts
- `web/src/Main.purs` extended to mount the durable-context surface when JWT is present, and to
  own generation-guarded WebSocket reconnect/reconstitution for authenticated sessions:
  an unexpected close clears only the stale connection, schedules reconnect with bounded backoff,
  resends `ClientHello`, and re-sends `ClientSubscribeContext` for the active context. Only the
  active context id and model id are stored in browser session storage — never tokens — and that
  state is cleared on logout

### Validation

- `purescript-spec` tests cover patch application + rendering correctness for each
  `ConversationStatePatch` variant; no reducer logic in PureScript
- E2E (Sprint 7.15) covers signup → context creation → prompt submission → response render
  → cancel → two-prompt queued indicator → conversation order preservation across reload

### Remaining Work

None.

---

## Sprint 7.11: SPA Artifacts View [Done]

**Scope boundary**: A preview label does not impose transfer or DOM bounds. Sprint 7.33 owns bounded preview and observed renderer behavior.

**Status**: Done
**Implementation**: `web/src/Infernix/Web/Artifacts.purs`, `web/src/Infernix/Web/ArtifactTransport.purs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/test/Infernix/Web/ArtifactsSpec.purs`
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
- `ArtifactsViewState` as the typed per-user library, contextually filtered by
  `artifactsForContext`, with `artifactEntryFromReady` (MIME inference from the object key when
  only the WS notification has arrived), `recordArtifactReady` (upsert keyed on bucket+key so
  repeated notifications collapse), `handleArtifactsServerMessage`, and `buildUploadRequest`.
  `dispositionFor` is the supported MIME-to-disposition mapping, and
  `Demo.Api.renderDispositionForMime` is the server-side matrix it must agree with
- HTTP upload helper that posts the typed upload request to `/api/objects`, then publishes a
  `ClientRecordUpload` frame over WS; `Runtime.Pulsar.planDemoClientMessagePublications` maps
  that frame to a per-context `ConversationUserUploadEvent` with producer dedup keyed by the
  uploaded `ObjectRef`, so a browser upload becomes visible in the conversation. Sprint 7.25
  replaces the browser-direct presigned PUT with the one-leg authenticated webapp proxy
- WS handler for `ArtifactReady` server messages renders the new artifact in place

### Validation

- `purescript-spec` view-model tests for artifact-kind dispatch
- E2E (Sprint 7.15) covers upload, download, render-or-download behavior for each supported
  artifact class, and the generated-artifact lifecycle (SDXL Turbo image, bark-small audio,
  Basic Pitch MIDI, Audiveris notation)

### Remaining Work

None.

---

## Sprint 7.12: SPA Model Picker Integration [Done]

**Status**: Done
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Dispatch/ContextModelMap.hs`, `src/Infernix/Runtime/Pulsar.hs` (`runContextsMetadataConsumer`, `emptyModelIdRejectionResult`)
**Docs to update**: `documents/architecture/demo_app_design.md`

### Objective

Wire the new-context flow to the active substrate's generated demo `.dhall` catalog so users
pick a model from the same set the active staged catalog exposes. Model selection pins the
context for life; switching models mid-context is out of scope.

### Deliverables

- `Chat.purs` model-picker modal sourced from the generated catalog
- WS `CreateContext` message includes the chosen `modelId`; backend validates against the
  active catalog and rejects unknown ids. `Runtime.Pulsar.publishDemoClientMessage` loads the
  active generated demo catalog before publishing `ClientCreateContext` and rejects model ids
  absent from it with typed error code `unknown-model`; `Demo.Api.mapDispatchError` preserves
  that code through the WebSocket `ServerError` response
- `src/Infernix/Dispatch/ContextModelMap.hs` owns the typed `ContextModelMap`
  (`IORef (Map Text Text)` keyed on `ContextId`) plus `newContextModelMap`, `lookupModelId`,
  `recordContextModel`, and `recordContextMetadataEvent`. `ContextCreated` pins the model id for
  the context's life; `ContextRenamed` and `ContextSoftDeleted` are no-ops for that binding
- `Runtime/Pulsar.hs.runContextsMetadataConsumer` is the per-user worker the coordinator
  dispatcher loop spawns on first sight of a userId: it subscribes Failover to
  `persistent://infernix/demo/demo.user.<userId>.contexts`, decodes each frame as a
  `ContextMetadataEvent`, and updates the shared map. `publishDispatchedInferenceRequest` takes
  the resolved `modelId` and populates the proto `request_model_id` field
- engine-side validation in `Pulsar.handleConsumerEnvelope` publishes a typed
  `emptyModelIdRejectionResult` (`status: "failed"` plus the typed error message) when the
  inbound `request_model_id` is empty, instead of delegating to the generic engine path; the
  result bridge writes it back to the conversation log so Chat renders the typed failure
- new-context dialog opening does not create backend state; closing without confirmation leaves
  no backend state

### Validation

- E2E: open new-context dialog, see catalog entries for the active substrate (skipping
  `Not recommended`), pick model, submit prompt, see context appear in left rail
- E2E negative: closing the dialog without confirmation creates no backend frame or local context

### Remaining Work

None.

---

## Sprint 7.13: Unit-Layer Validation [Done]

**Status**: Done
**Implementation**: `test/unit/*` (existing `infernix-unit` Cabal stanza), `web/test/Main.purs`, `web/test/Infernix/Web/ContractsSpec.purs`, `web/test/Infernix/Web/ChatSpec.purs`, `web/test/Infernix/Web/ArtifactsSpec.purs`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Land the unit test layer for every primitive added in Phase 7. Property-based wherever
ordering invariants matter.

### Deliverables

- reducer property tests: determinism over arbitrary `ConversationEvent` logs; idempotency
  dedup; cancellation semantics; two-prompt-in-a-row ordering. `assertConversationPropertyTests`
  in `test/unit/Spec.hs` generates arbitrary 0–8-message logs with prompt / cancel /
  inference-result / duplicate shapes and exercises three invariants — patch-stream replay
  converging to the snapshot reducer projection, `prefixHash` chain length-monotonicity plus
  determinism, and idempotency dedup dropping repeated `(contextId, key)` pairs — across
  shrinkable random cases; the `infernix-unit` stanza declares the QuickCheck dependency
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

None.

---

## Sprint 7.14: Integration-Layer Validation [Done]

**Scope boundary**: A retained phase attestation is missing. Sprints 7.30–7.33 specify independent restart, reconstruction, cancellation and media proof before phase closure.

**Status**: Done — implemented and validated.
Native `linux-cpu` `infernix test all` validation passed on the recorded cohort validation;
`linux-gpu` `infernix test all` validation passed on the recorded cohort validation on the
selected accelerator plus `linux-cpu`. The mounted Linux CPU `cabal test infernix-integration`
rerun on the recorded cohort validation passed against the Sprint 7.8 runtime KV-cache and
daemon-orchestration split worktree.)
**Implementation**: `test/integration/*` (existing
`infernix-integration` Cabal stanza), `test/integration/Spec.hs (multi-user throughput logic —
ThroughputMatrix, validateMultiUserDurablePromptThroughput/...With — lives inline in this module
Main)`
**Docs to update**: `documents/development/demo_app_test_plan.md`,
`documents/tools/pulsar.md`,
`documents/architecture/daemon_topology.md`

### Objective

Land the integration test layer covering real-cluster Pulsar / MinIO / Keycloak round-trips,
the chaos tests for the per-role failure semantics from
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md),
and the multi-user throughput / fan-in batching / fan-out test.

### Deliverables

- real Pulsar publish + Reader subscribe round-trip per topic family (conversation, compacted
  contexts, compacted drafts, inference request/batch/result).
  `src/Infernix/Runtime/Pulsar.hs.publishDemoClientMessage` maps browser `WsClientMessage` frames
  onto those durable families with mutation-scoped producer names and idempotency-derived
  WebSocket `initialSequenceId` baselines so broker dedup collapses reconnect and retry
  duplicates, and `src/Infernix/Demo/Api.hs` wires that callback through
  `WebSocketOptions.wsDispatchClientMessage`
- real Pulsar producer dedup verification across simulated coordinator restart mid-flight;
  assert exactly-one inference dispatch and exactly-one result
- real Pulsar Failover handoff: kill active coordinator replica; assert surviving consumer
  resumes
- real MinIO presigned PUT/GET byte lifecycle with per-user scoping; same-user routed byte
  equality, routed grant minting, and routed cross-user object-prefix isolation are covered by
  Sprint 7.15
- real Keycloak login + JWT validation round-trip; browser signup, auth-code exchange,
  malformed bearer rejection, backend JWT acceptance for `/api/objects`, routed WebSocket
  valid/malformed/expired-token handshake behavior, and typed malformed-frame `ServerError`
  handling are covered by Sprint 7.15
- chaos tests against the supported three-role daemon model:
  - **Frontend (WS-hosting) pod kill mid-session**: WS reconnect succeeds; no state loss
  - **Coordinator pod kill mid-dispatch**: Failover promotes a surviving coordinator;
    producer dedup on `inference.request.<mode>` and `inference.batch.<mode>` prevents
    duplicates
  - **Coordinator pod kill mid-result-bridge**: Failover promotes a surviving coordinator;
    producer dedup on the conversation topic (keyed by
    `(userPromptMessageId, kind = InferenceResult)`) prevents a duplicate writeback
  - **Engine pod kill mid-inference**: Pulsar redelivers the unacked batch; surviving engine
    on another node rebuilds KV cache via `prefixHash`; producer dedup on
    `inference.result.<mode>` prevents a duplicate result
  - **Engine node drain**: engine PDB blocks the drain until another engine pod is
    available cluster-wide; cluster keeps serving inference throughout
  - **Coordinator pod kill mid-bootstrap upload**: kill the active coordinator pod
    after some weight files have PUT to `infernix-models/<modelId>/` but before the
    `.ready` sentinel; the rescheduled coordinator resumes (the Failover subscription,
    attempt-scoped request dedup, and MinIO `.ready` guard prevent duplicate effective
    population); the `.ready`
    duplicate sentinel publications collapse at the effect; waiting engines observe ready and proceed
  - **Concurrent bootstrap requests**: N engine pods request the same uncached model
    simultaneously; producer dedup + Pulsar Failover guarantees exactly one upstream
    download; all N engines observe the `.ready` sentinel and proceed
  - **Engine placement enforcement**: on Linux,
    `kubectl scale deployment/infernix-engine --replicas=N+1` leaves the extra pod
    `Pending` with the anti-affinity rejection; the older Apple duplicate-daemon
    `engine.lock held by PID ...` diagnostic is historical and superseded by host-id pool
    membership plus pinned `Exclusive` routes
  each case asserts an effectively-once observable outcome and full state preservation
- model-cache eviction test: trigger model loads until `/model-cache` size pressure
  exists; assert the adapter helper evicts LRU entries; assert the engine pod is not
  restarted by kubelet for ephemeral-storage exhaustion
- production-shape test: deploy `demo_ui = false` and assert
  `infernix kubectl -n platform get deployments` returns the production coordinator plus
  engine-pool workloads;
  `infernix-models` and `infernix-engine-artifacts` buckets are present;
  `infernix-demo-objects` bucket is absent;
  `infernix kubectl get pvc -A` returns empty
- **Multi-User Throughput / Fan-In Batching / Fan-Out** test: N users × K contexts × P
  prompts on one model, asserting per-context ordering, no duplicates or losses,
  cross-context independence, batching gain, bounded p95 latency, dedup correctness;
  implemented inline in `test/integration/Spec.hs` (module Main) via `validateMultiUserDurablePromptThroughput`; defaults N = 10, K = 3, P = 5

### Validation

- `infernix test integration` includes all new suites and passes on at least one substrate
  with `demo_ui = true`
- throughput test reports per-context ordering, exact result counts, p95 latency, batching
  factor, and dedup counter values
- `test/integration/Spec.hs` carries the real-broker contract as named suites: durable topic-family
  roundtrips (`validateDurableTopicFamilyRoundTrips`), compacted latest-per-key behavior
  (`validateCompactedTopicBrokerBehavior`, which also closes Sprint 7.5's compaction gate),
  producer dedup (`validateProducerDeduplicationBehavior`), the non-chaos durable-context prompt
  roundtrip (`validateDurableContextPromptRoundTrip`), the per-role chaos cases, and the
  parameterized multi-user throughput matrix (`validateMultiUserDurablePromptThroughput` /
  `...With`, integration default 3 users × 2 contexts × 2 prompts)
- per-run image digests and the attempt-by-attempt history live in
  [cohort-validation-waves.md](cohort-validation-waves.md), not here

### Remaining Work

None. The integration layer is closed.

---

## Sprint 7.15: E2E-Layer Validation [Done]

**Status**: Done — the durable-context browser flow, the fixture-backed artifact flow, and the per-model browser matrix pass on both rebuilt-image Linux lanes.
**Implementation**: `web/src/Main.purs`, `web/src/index.html`, `web/src/Infernix/Web/ArtifactTransport.purs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Auth.js`, `web/test/Main.purs`, Playwright suites under the repo's Playwright tree, run inside the active Linux substrate image; `web/test/fixtures/`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`

### Objective

Land the E2E test layer through the active substrate image's Playwright runtime. Substrate-agnostic
at the browser layer. Includes per-model smoke matrix.

### Deliverables

- Playwright flows: auth lifecycle (signup, login, logout, re-login, JWT refresh); context
  lifecycle (new-context dialog open/close/create, rename, soft-delete, select); conversation lifecycle
  (submit, response, two-in-a-row queued, cancel-mid-inference, order preservation across
  reload); draft lifecycle (type, refresh, restored, per-context isolation, submit clears
  draft); artifact upload lifecycle per supported artifact class; artifact download plus
  inline render, bounded preview, browser-native PDF handling, or download-only handling;
  generated-artifact lifecycle; multi-tab convergence; client reconstitution via Playwright
  Browser Context storage-clear; pod-reschedule-from-browser
- **Per-Model Smoke Matrix**: parameterized flow that reads the active substrate's generated
  `.dhall`, iterates every catalog entry whose engine cell for the active substrate is not
  `Not recommended`, creates a fresh context pinned to that model, submits a
  family-appropriate canonical input from `web/test/fixtures/`, asserts Completed
  `InferenceResult`, asserts artifact appearance and rendering
- `web/test/fixtures/artifactSamples.js` checked-in canonical sample payloads (inline
  text, JSON, PNG, WAV, MP4, PDF, MIDI, MusicXML, and generic-binary buffers via
  `textPreviewBody`, `jsonPreviewBody`, `tinyPngBuffer`, `tinyWavBuffer`, `tinyMp4Buffer`,
  `tinyPdfBuffer`, `tinyMidiBuffer`, `musicXmlBuffer`, `binaryArtifactBuffer`), imported by
  `web/playwright/inference.spec.js` and by the per-model smoke matrix
- `src/Infernix/CLI.hs.runPlaywrightWithFixture` invokes Playwright from the repo root with the
  explicit `web/playwright.config.js` path, and that config reads the typed fixture from
  `.data/runtime/playwright-fixture.json`
- `web/src/index.html` is the dense app shell with Chat, Artifacts, route inventory, and runtime
  summary mount points; `web/src/Main.purs` mounts the durable-context shell, loads routed
  `/api/publication` and `/api/models`, and delegates the main panes to `Chat.renderChatView` and
  `Artifacts.renderArtifactsView`. The prior manual-inference Workbench shell and its unit
  surface are gone
- browser-level pod-failover coverage deletes all `infernix-demo` pods through the typed
  `infernix kubectl` fixture hook, waits for replacements, verifies `ClientHello` plus the active
  `ClientSubscribeContext` are resent, receives a fresh `ServerConversationSnapshot`, and submits
  another prompt through the reconnected socket

### Validation

- `infernix test e2e` runs the Playwright suite via the active substrate image's Playwright
  runtime
- per-model smoke matrix has one passing flow per non-`Not recommended` row in the README
  matrix for the active substrate; failure on any row fails the suite
- the Playwright source is byte-identical across `apple-silicon`, `linux-cpu`, `linux-gpu`;
  substrate selection lives only in the `.dhall` the demo app reads

### Remaining Work

None. The per-model smoke matrix is validated on Apple, `linux-gpu`, and `linux-cpu`.

---

## Sprint 7.16: Documentation Closure [Done]

**Status**: Done (docs lint passed on the recorded cohort validation after the residual-sweep docs update and again on the recorded cohort validation after the runtime KV-cache plus `Infernix.Runtime.Daemon` realignment.)
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
- the recorded cohort validation Linux outer-container validation:
  `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix lint docs`
  exits zero after the residual-sweep docs update
- a fresh contributor can locate the canonical home for every Phase 7 topic via the suite
  index

### Remaining Work

None.

---

## Sprint 7.17: Secrets-via-Files and Demo-Surface Retirement [Done]

**Status**: Done
**Implementation**: `src/Infernix/SecretsConfig.hs` (`SecretsConfig` decoder type = reflected schema; no tracked `.dhall`), `src/Infernix/Demo/Api.hs`, `src/Infernix/Demo/Auth.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Python.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/secret-cluster-secrets.yaml`, `chart/templates/keycloak/deployment.yaml` (KC_DB_* documented exception).
**Docs to update**: `documents/architecture/configuration_doctrine.md`, `documents/engineering/cluster_config_manifest.md`, `documents/tools/keycloak.md`, `documents/tools/minio.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the `InfernixSecrets.dhall` typed paths-only schema + matching Haskell reader. Retire
every `INFERNIX_KEYCLOAK_*` and `INFERNIX_MINIO_*` env-var consumer in favor of `ClusterConfig`
fields (for non-secret values) plus file-based Secret mounts (for credentials). Retire
`INFERNIX_POETRY_*` env reads. Mount `/etc/infernix/secrets/` on the demo pod from a Kubernetes
`Secret`; Keycloak's `KC_DB_*` upstream contract stays as the documented third-party exception.

### Deliverables

- the `SecretsConfig` decoder type (reflected schema) with the `Minio`, `KeycloakAdmin`, `KeycloakDb`
  paths-only records named in
  [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md).
- `SecretsConfig` typed record + decoder; threaded through the demo backend entry point.
- The Haskell application calls `readFile (SecretsConfig.minio.credentialsPath)` and parses the
  JSON for MinIO credentials; never reads `INFERNIX_MINIO_ACCESS_KEY` / `SECRET_KEY`.
- `INFERNIX_KEYCLOAK_BASE_URL`, `INFERNIX_KEYCLOAK_REALM_NAME`, `INFERNIX_KEYCLOAK_CLIENT_ID`,
  `INFERNIX_KEYCLOAK_JWKS_URL`, `INFERNIX_MINIO_ENDPOINT`, `INFERNIX_MINIO_REGION`,
  `INFERNIX_MINIO_PRESIGN_EXPIRY_SECONDS`, `INFERNIX_MINIO_ACCESS_KEY`,
  `INFERNIX_MINIO_SECRET_KEY`, `INFERNIX_POETRY_EXECUTABLE`, `POETRY_HOME`,
  `POETRY_VIRTUALENVS_IN_PROJECT` env reads all deleted from `src/Infernix/Demo/Api.hs`,
  `src/Infernix/Demo/Auth.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Python.hs`.
- `POETRY_VIRTUALENVS_IN_PROJECT` behaviour moves to a `poetry.toml` config file at the project
  root.
- the Poetry executable comes from `HostConfig.toolPaths.hostPoetry` via `pathsHostConfig paths`
  with `onlyIfExists` guarding stale fixture paths; `bootstrapPoetryOnAppleHost` takes a `Paths`
  argument and routes through `HostConfig.hostFilesystem.hostHomeDirectory` for the install root
  and `HostConfig.toolPaths.hostPython3` for the bootstrap interpreter.
  `prependDirectoryToPath`, `activatePoetryExecutable`, and `firstCompatibleCommandOnPath` are
  deleted, and downstream callers invoke Poetry through the absolute path returned by
  `ensurePoetryExecutable`. The `Lint/HaskellStyle.hs.envFunctionExemptedFiles` row for
  `src/Infernix/Python.hs` is deleted with it; `bareNameProcExemptedFiles` never carried one.
- `chart/templates/deployment-demo.yaml` `env:` block deleted; demo pod mounts the cluster
  ConfigMap + the cluster Secret at `/opt/infernix/cluster.dhall` and `/etc/infernix/secrets/`.
- `chart/templates/secret-cluster-secrets.yaml` renders the operator-supplied credentials as a
  Kubernetes `Secret`.
- `chart/templates/keycloak/deployment.yaml` retains `KC_DB_*` env entries (Keycloak upstream
  contract) and documents the third-party exception in `documents/tools/keycloak.md` + the
  lint-gate exception list.

### Validation

- `rg -n 'lookupEnv|getEnv' src/Infernix/Demo/Api.hs src/Infernix/Demo/Auth.hs src/Infernix/Runtime/Pulsar.hs` returns zero matches.
- `grep -rn '^\s*-\s*name:\s*INFERNIX_' chart/templates/deployment-demo.yaml` returns zero
  matches.
- Apple cohort validation closed on the selected accelerator plus `linux-cpu`. CUDA Linux validation closed on the selected accelerator plus `linux-cpu` with
  `linux-cpu` passing on the recorded cohort validation and `linux-gpu` passing on the recorded cohort validation.

### Remaining Work

None.

---

## Sprint 7.18: Declarative-State Phase Prose Rewrite [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md` (prose only)
**Docs to update**: this file

### Objective

Rewrite Phase 7 prose so the supported three-role daemon split (`infernix-coordinator`,
`infernix-engine`, demo-gated `infernix-demo`) is described as the supported shape directly.
Cleanup history lives in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Deliverables

- Phase Status uses present-tense vocabulary; the runtime KV-cache and `Infernix.Runtime.Daemon`
  prose describes the supported shape directly.
- Sprint 7.7 prose describes its deliverable as introducing the supported three-role split
  (`infernix-coordinator` + substrate-specific engine pools + demo-gated `infernix-demo`) and the supported
  MinIO-backed object-storage contract, with cleanup receipts held in
  `legacy-tracking-for-deletion.md`.
- Sprint 7.8/7.14/7.15/7.17 prose is declarative current-state; open cohort gates live in
  [cohort-validation-waves.md](cohort-validation-waves.md).
- Per-sprint Validation sections retain test-name and gate references, drop daily proof points,
  and anchor on the canonical architecture documents.

### Validation

- The phase-specific lexical guard for unsupported historical-state vocabulary and dated
  proof-point prose returns no matches outside cleanup-ledger references.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

None.

---

## Sprint 7.19: Auth-Gated Landing and Dual Entry Points [Done]

**Status**: Done
**Implementation**: `web/src/index.html`, `web/src/Main.purs`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Auth.js`
**Docs to update**: [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../README.md](../README.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), [system-components.md](system-components.md)

### Objective

Move the `infernix-demo` app shell behind authentication. Pre-auth visitors see a minimal
centred landing card with the `Infernix` wordmark, a one-line subtitle, and two explicit
CTAs (`Sign in` primary, `Create account` secondary), each deep-linking the matching Keycloak
form via OIDC Application Initiated Actions (AIA). The summary grid (Runtime, Control Plane,
Daemon, Dispatch, Edge, Catalog, Connection) and the Chat / Artifacts tabs are no longer
rendered for anonymous visitors.

### Deliverables

- `web/src/index.html` carries a pre-auth `<div class="app-landing">` containing the
  landing card and the new `#register-button`; the existing `.app-shell` (header + summary
  grid + tabs + workspace) stays inline so the existing `captureRefs` bootstrap path is
  unchanged. A `body` class — `auth-unknown`, `auth-signed-in`, `auth-signed-out` — toggles
  visibility via CSS: only the landing renders when signed out, only the shell renders when
  signed in, and the `auth-unknown` boot state hides both until PureScript reads the in-memory
  JWT.
- `web/src/Main.purs.renderAuthGate` sets the body class on every `renderAll` pass from
  `state.authenticated`. The bootstrap captures the body via `HTMLDocument.body` +
  `HTMLElement.toElement`; when absent (e.g. SSR fixtures) the gate is a no-op.
- `web/src/Main.purs.bindEvents` wires the new `#register-button` to
  `beginRegisterRedirect defaultInfernixRealmConfig`.
- `web/src/Infernix/Web/Auth.purs` exports
  `beginRegisterRedirect :: RealmConfig -> Effect Unit` alongside `beginLoginRedirect`.
- `web/src/Infernix/Web/Auth.js` factors the PKCE / state / nonce setup into a shared
  `beginAuthorizationCodeRedirect(config, endpoint, kcAction)` helper; `beginLoginRedirectImpl`
  uses the `auth` endpoint and `beginRegisterRedirectImpl` uses the `registrations` endpoint so
  Keycloak lands the user on the registration form. PKCE verifier, state, nonce, and the callback
  handler are unchanged — Keycloak returns to the same `redirect_uri` after either flow.

### Validation

- `npm --prefix web run build` exits zero (Haskell + PureScript; bundle written to
  `web/dist/app.js`).
- `npm --prefix web run test:unit` exits zero (71/71 cases pass).
- `./.build/infernix lint docs` exits zero after the doc edits named in `Docs to update`.
- Manual UX check at the published edge port: pre-auth shows only the landing card with two
  buttons (no header, no summary grid, no tabs); `Sign in` redirects to Keycloak's login
  form; `Create account` redirects to Keycloak's registration form; after either flow the app
  shell renders unchanged.
- A new Playwright case in `web/playwright/inference.spec.js` asserts the splash renders
  exactly the two buttons pre-auth and that each redirect lands on the matching Keycloak
  form. Apple cohort closure recorded in [cohort-validation-waves.md](cohort-validation-waves.md).

### Remaining Work

None.

### Documentation Requirements

**Architecture docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — `## Landing Surface` (pre-auth splash composition, body-class state machine) and `## Authentication Entry Points` (dual `Sign in` / `Create account` CTAs with their AIA mapping).
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — extend the identity/auth section with the dual entry points; note that the app shell is gated on JWT presence.

**Reference docs to update:**
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — `## Pre-Auth Landing` section listing the landing card + two CTAs.

**Development docs to update:**
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — new test row: "pre-auth splash renders exactly two CTAs and routes each to the matching Keycloak form."

**Root docs to update:**
- [../README.md](../README.md) — extend the demo-UI paragraph with the dual-CTA landing.

**Plan docs to update:**
- [system-components.md](system-components.md) — record the new `#register-button` plus the body-class state machine as part of the `infernix-demo` SPA bootstrap surface.
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — retain only still-existing cleanup surfaces; delete the pre-auth shell and single-CTA rows when their removal lands.
- [cohort-validation-waves.md](cohort-validation-waves.md) — wave row for the auth-UX quad closure.

---

## Sprint 7.20: Themed Keycloak Login Surface [Done]

**Status**: Done
**Implementation**: `chart/templates/keycloak/configmap-theme.yaml`, `chart/templates/keycloak/deployment.yaml`, `chart/templates/keycloak/configmap-realm-import.yaml`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `web/playwright/inference.spec.js`
**Docs to update**: [../documents/tools/keycloak.md](../documents/tools/keycloak.md), [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../README.md](../README.md), [system-components.md](system-components.md)

### Objective

Make the routed Keycloak login and registration pages visually part of the Infernix demo without
forking or rebuilding the upstream Keycloak image. The stock Keycloak container stays in the image
inventory; the theme is a chart-owned ConfigMap selected by the realm import and preserved by the
idempotent admin reconcile.

### Deliverables

- `chart/templates/keycloak/configmap-theme.yaml` renders `ConfigMap/infernix-keycloak-theme`
  with `login/theme.properties`, `login/messages/messages_en.properties`, and
  `login/resources/css/infernix.css`.
- `chart/templates/keycloak/deployment.yaml` mounts the theme at
  `/opt/keycloak/themes/{{ .Values.keycloak.theme.name }}` and keeps the stock Keycloak image.
- `chart/templates/keycloak/configmap-realm-import.yaml` sets
  `loginTheme = {{ .Values.keycloak.theme.name }}`.
- `src/Infernix/Cluster.hs.keycloakRealmReconcilePayload` reapplies `loginTheme = infernix`
  during the post-rollout Keycloak admin reconcile so repeat `cluster up` runs do not drift back
  to the upstream default theme.
- `src/Infernix/Lint/Chart.hs` requires the theme ConfigMap and checks the key theme phrases.
- `web/playwright/inference.spec.js` asserts the themed login and registration titles in the
  routed pre-auth smoke.

### Validation

- `cabal test infernix-haskell-style` exits zero.
- `./.build/infernix lint chart` exits zero.
- `./.build/infernix lint docs` exits zero.
- `npm --prefix web run test:unit` exits zero.
- routed E2E verifies the Keycloak pages show `Sign in to Infernix` and
  `Create your Infernix account`.

### Remaining Work

None.

### Documentation Requirements

**Tools docs to update:**
- [../documents/tools/keycloak.md](../documents/tools/keycloak.md) — mounted theme ConfigMap,
  realm import, admin reconcile, and Playwright theme assertions.

**Architecture and reference docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — theme selection on the redirected Keycloak forms.
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — identity/auth section includes the themed forms.
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — user-visible `/auth` title text.

**Development docs to update:**
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — Playwright assertion for the theme.

**Root and plan docs to update:**
- [../README.md](../README.md) — demo paragraph includes the chart-owned Keycloak theme.
- [system-components.md](system-components.md) — component inventory records the theme ConfigMap.

---

## Sprint 7.21: Operator Console Ribbon and Edge JWT Gating [Done]

**Status**: Done
**Implementation**: `web/src/index.html`, `web/src/Infernix/Web/Auth.js`, `web/playwright/inference.spec.js`, `chart/templates/securitypolicy-operator-routes.yaml`, `chart/values.yaml`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: [../documents/engineering/edge_routing.md](../documents/engineering/edge_routing.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../README.md](../README.md), [system-components.md](system-components.md)

### Objective

Expose the platform's local operator consoles from the authenticated demo shell and close those
published prefixes behind the same Keycloak JWT trust boundary as the demo API / WebSocket
surface.

### Deliverables

- The signed-in app shell renders an operator console ribbon linking to `/registry`,
  `/pulsar/admin/admin/v2/clusters`, and `/minio/s3`; the ribbon stays hidden with the app shell
  before authentication.
- `web/src/Infernix/Web/Auth.js` writes the current Keycloak access token to the
  `infernix_operator_token` cookie on token receipt / refresh and clears the cookie on logout
  (with Keycloak SSO logout added later by Phase 9 Sprint 9.9).
- `chart/templates/securitypolicy-operator-routes.yaml` renders
  `SecurityPolicy/infernix-operator-routes-jwt`, targeting the registry, Pulsar Admin, and
  MinIO S3 HTTPRoutes. The policy accepts either the SPA-written cookie or a direct
  `Authorization: Bearer ...` header and validates against the configured Keycloak JWKS endpoint.
- `src/Infernix/Lint/Chart.hs` requires the new SecurityPolicy template and the chart values that
  configure operator-route JWT gating.
- The routed Playwright source asserts the ribbon links, the cookie login / refresh / logout
  lifecycle, unauthenticated operator-route rejection, and authenticated operator-route access.

### Validation

- `cabal test infernix-haskell-style` exits zero.
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  refreshes the Apple host-native `./.build/infernix` lint binary after the chart-lint change.
- `./.build/infernix lint chart` exits zero.
- `./.build/infernix lint docs` exits zero.
- `helm template infernix chart` exits zero.
- `npm --prefix web run test:unit` exits zero.
- routed E2E verifies the operator route family rejects requests without a JWT and accepts
  the real Keycloak token through the supported cookie or bearer-header paths.

### Remaining Work

None.

### Documentation Requirements

**Engineering and reference docs to update:**
- [../documents/engineering/edge_routing.md](../documents/engineering/edge_routing.md) — operator-route SecurityPolicy ownership and JWT validation contract.
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — operator console ribbon, route links, and cookie/header auth paths.

**Architecture and development docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — signed-in ribbon and token-cookie lifecycle.
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — demo identity boundary includes operator-console links.
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — Playwright assertions for ribbon visibility, cookie lifecycle, and JWT-gated operator routes.

**Root and plan docs to update:**
- [../README.md](../README.md) — demo paragraph includes the ribbon and edge JWT policy.
- [system-components.md](system-components.md) — component inventory records the SPA cookie bridge and SecurityPolicy.

---

## Sprint 7.22: Self-Service Account Deletion and State Reaping [Done]

**Status**: Done
**Implementation**: `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Conversation/Topic.hs`, `src/Infernix/Objects/Presigned.hs`, `web/src/Infernix/Web/Auth.js`, `web/src/Infernix/Web/Auth.purs`, `web/src/Main.purs`, `web/src/index.html`, `web/playwright/inference.spec.js`, `test/unit/Spec.hs`
**Docs to update**: [../documents/tools/keycloak.md](../documents/tools/keycloak.md), [../documents/tools/minio.md](../documents/tools/minio.md), [../documents/tools/pulsar.md](../documents/tools/pulsar.md), [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../README.md](../README.md), [system-components.md](system-components.md)

### Objective

Let a signed-in demo user delete their account without leaving demo-owned durable state behind.
The browser must not enter Keycloak's account-deletion action until the backend has removed the
caller's MinIO prefix and user-owned Pulsar durable-context topics.

### Deliverables

- `DELETE /api/account` validates the current Keycloak JWT, derives `UserId` from `sub`, deletes
  every object returned by S3 ListObjectsV2 under
  `infernix-demo-objects/users/<userId>/`, deletes user-owned demo Pulsar topics in bounded
  routed-safe cleanup slices, and returns a cleanup summary with `cleanupComplete` plus any
  remaining topic names.
- `Infernix.Objects.Presigned` can sign S3 ListObjectsV2 bucket queries and DELETE Object
  requests without adding an SDK dependency or changing existing PUT/GET grant behavior.
- `Infernix.Conversation.Topic.topicBelongsToUser` identifies the exact caller-owned topic set:
  `demo.user.<userId>.contexts`, `demo.user.<userId>.drafts`, and
  `demo.conversation.<userId>.*`; shared inference request/batch/result topics stay intact.
- `Infernix.Runtime.Pulsar.deleteDemoUserTopics` discovers the supported Pulsar transport,
  lists `persistent://infernix/demo`, filters by the user-topic predicate, and deletes matching
  topics with the Pulsar admin API. `deleteDemoUserTopicsWithAttemptBudget` lets the routed API
  return `202` while cleanup is still draining instead of letting Envoy time out the request.
- Browser-facing Pulsar reader retry loops let async exceptions terminate the child threads, so a
  WebSocket close during account deletion does not respawn stale per-user readers and recreate the
  deleted topics.
- The signed-in SPA shell renders `Delete account`; `web/src/Infernix/Web/Auth.js` confirms the
  command, retries `DELETE /api/account` while the backend reports `cleanupComplete = false`,
  clears local browser auth state after completion, then starts Keycloak with
  `kc_action=delete_account`.
- The routed Playwright source creates real per-user state, clicks `Delete account`, verifies the
  cleanup response, verifies the previously readable MinIO object returns `404`, verifies the
  user's topics disappear from Pulsar admin, and verifies the Keycloak request carries
  `kc_action=delete_account`.

### Validation

- `cabal test infernix-unit` exits zero, including the new pure topic-predicate and presigner
  query/DELETE assertions.
- `cabal test infernix-haskell-style` exits zero.
- `npm --prefix web run test:unit` exits zero (71/71 cases pass).
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  refreshes the Apple host-native `./.build/infernix` binary.
- `./.build/infernix test e2e` exits zero on the supported Apple host-native lane with 9/9 routed
  Playwright tests passing, including account deletion in 2.9 seconds on the final run.
- routed E2E verifies the complete browser account-deletion flow against real Keycloak,
  MinIO, Pulsar, and Envoy Gateway.

### Remaining Work

None.

### Documentation Requirements

**Tools docs to update:**
- [../documents/tools/keycloak.md](../documents/tools/keycloak.md) — `kc_action=delete_account`
  sequencing after backend cleanup.
- [../documents/tools/minio.md](../documents/tools/minio.md) — user-prefix deletion through S3
  ListObjectsV2 and DELETE Object.
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — user-owned topic deletion and
  shared-topic boundary.

**Architecture, reference, and development docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — delete button, backend cleanup, and redirect sequencing.
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — `/api/account` transport and state-reaping semantics.
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — visible `Delete account` command and endpoint contract.
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — routed account-deletion smoke.

**Root and plan docs to update:**
- [../README.md](../README.md) — demo paragraph includes account deletion.
- [system-components.md](system-components.md) — component inventory records the backend state reap
  and Keycloak action sequencing.

---

## Sprint 7.23: Apple Host Engine Pulsar Singleton [Done]

**Status**: Done (superseded by Sprint 7.24; no new Apple `Failover` evidence requested)
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/Service.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`
**Docs to update**: [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md), [../documents/tools/pulsar.md](../documents/tools/pulsar.md), [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Objective

Record the superseded intermediate attempt to replace the Apple host engine filesystem lock with a
single-topic Pulsar singleton. The durable target is now engine pools: `Shared` across distinct Apple
host ids for normal work distribution and `Exclusive` only for pinned host routes.

### Deliverables

- Keep the historical code-side changes visible only as retired compatibility context now that the
  Phase 4 pool-routing cleanup has removed the single-host topic surface.
- Record Apple `Failover` standby wording as removed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), not in the supported
  architecture; the single-host-topic cleanup is completed there.
- Preserve the useful invariant that pinned routes use broker-owned `Exclusive` ownership.

### Validation

- Historical unit coverage remains useful only as a migration guard for the compatibility surfaces
  tracked by Sprint 7.24 and the deletion ledger.
- No new validation should promote Apple `Failover` as a supported operator mode.

### Remaining Work

None. The superseded singleton target survives only as historical notes and ledger rows.

### Documentation Requirements

**Architecture and tools docs to update:**
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) — remove Apple singleton/failover target wording.
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — move Apple work distribution to pool topics and broker backpressure.
- [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md) — operator-facing Apple host-member pool behavior.

**Plan docs to update:**
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — no pending row for the absent `engine.lock` primary guard.

---

## Sprint 7.24: Engine Pool Assignment and Broker-Native Backpressure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Substrate.hs` (substrate decoder type = reflected schema; no tracked `.dhall`), `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: [../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md), [../documents/tools/pulsar.md](../documents/tools/pulsar.md), [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Objective

Make coordinator-to-engine routing substrate-neutral. The coordinator chooses a model/pool topic,
not a node; Pulsar assigns work to eligible members through broker backpressure; exact-host or
exact-member routes stay explicit through `Exclusive` pinned topics.

### Deliverables

- coordinator routing reads the validated engine-pool graph and publishes only to derived topics
- Apple host daemons start with a stable host id and subscribe only to assigned model-pool topics
- Linux engine workloads subscribe to the same derived pool/model topic shape as Apple members
- normal pool consumers use `Shared` with receiver permits tied to local concurrency
- pinned member consumers use `Exclusive`
- assignment is startup-time in the current supported contract. Future hot reload, if implemented,
  must use compacted desired-state records keyed by member id; assignment changes add subscriptions
  for newly assigned models, drain removed subscriptions, and mark removed model-cache entries
  evictable
- production `demo_ui = false` keeps the coordinator and engine pools while omitting only demo-only
  workloads and routes

### Validation

- unit tests for host-id/member selection and assignment-state transitions
- Pulsar integration proving two same-machine Apple host-member daemons can coexist on one derived
  `Shared` pool/model topic
- Pulsar integration proving a busy logical shared-pool Apple member stops receiving new work while
  a free logical member on the same Apple host receives new messages
- Linux CPU integration proving Kubernetes-observed pool placement and shared-subscription
  backpressure on unique derived pool/model topics
- pinned-route duplicate-consumer test proves `Exclusive` ownership on the Apple host integration
  lane
- production-shape integration proves coordinator presence with `demo_ui = false`
- regression coverage proves dispatcher, result-bridge, and model-bootstrap Failover subscriptions
  remain coordinator-only leadership mechanisms

### Remaining Work

None. Closed on the selected accelerator plus `linux-cpu`.

### Documentation Requirements

**Architecture and tools docs to update:**
- [../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md) — startup-time pool assignment, future desired-state hot reload boundaries, and cache behavior.
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) — coordinator and engine role behavior.
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — shared-pool and pinned-route subscription rules.

**Plan docs to update:**
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — no pending rows for the absent single Apple host topic, Apple `Failover`, or demo-off engine-only topology.

---

## Sprint 7.25: Webapp Object-Proxy and Per-User Isolation Hardening [Done]

**Status**: Done
**Implementation**: `src/Infernix/Demo/Api.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Objects/Layout.hs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/src/index.html`
**Docs to update**: `documents/architecture/object_access_doctrine.md`, `documents/architecture/tenant_isolation_doctrine.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `documents/architecture/demo_app_design.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace the browser-direct presigned MinIO path with a webapp object-proxy, and make one
server-side trust boundary the sole authority for every per-user object and chat operation, so
cross-user access is impossible by construction.

### Deliverables

- `Demo/Api.hs` proxies upload/download bytes over the internal MinIO endpoint
  (`loadInternalMinioPresignedConfig` plus the file-local `putMinioObjectBytes` /
  `getMinioObjectBytes` signers, not `Infernix.Objects.Upload`)
- `artifactUploadGrantPresignedUrl` and `artifactDownloadGrantPresignedUrl` removed from `Contracts.hs`
- `sanitizeFilename` applied to the client-supplied display name
- `pathBelongsToUser` plus `topicBelongsToUser` reused as the single server-side choke point

### Validation

- cross-user-403 integration: a user's JWT receives HTTP 403 on another user's object key (list /
  get / put / delete) and cannot read another user's chat context
- e2e: the browser uploads and downloads only through the webapp `/api/objects` surface, never a
  presigned MinIO URL
- the `linux-cpu` plus chosen `linux-gpu` cohort records the real
  per-user attestation, including the routed cross-user-403 e2e and proxied byte upload/download
  evidence.

### Remaining Work

None. Closed on the selected accelerator plus `linux-cpu`.

### Documentation Requirements

- keep `documents/architecture/object_access_doctrine.md` and
  `documents/architecture/tenant_isolation_doctrine.md` aligned with the implemented choke point
- update `documents/reference/api_surface.md` and `documents/reference/web_portal_surface.md` to
  describe the proxied `/api/objects` byte upload/download surface
- record the retired browser-direct presigned path (the `Demo/Api.hs` `mintAndRespond` grants, the
  `artifact*GrantPresignedUrl` contract fields, and the browser PUT/GET to the presign endpoint) in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

---

## Sprint 7.26: Per-User Files Navigational View [Done]

**Status**: Done
**Implementation**: `src/Infernix/Demo/Api.hs`, `web/src/index.html`, `web/src/Infernix/Web/Router.purs`, `web/src/Infernix/Web/Artifacts.purs`, `web/src/Infernix/Web/FilesTransport.purs`, `web/src/Infernix/Web/FilesTransport.js`, `web/src/Main.purs`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/reference/api_surface.md`, `documents/architecture/demo_app_design.md`, `documents/architecture/tenant_isolation_doctrine.md`

### Objective

Give each user a navigational Files view over their own MinIO objects, prefix-scoped to
`users/<sub>/` and authorized through the Sprint 7.25 choke point, reusing the existing render
dispositions for preview.

### Deliverables

- `GET /api/objects/list` prefix-scoped to `users/<sub>/` (derived server-side)
- `DELETE /api/objects` for a single caller-owned object
- a Files nav section in the SPA (list / upload / download / preview / delete) reusing the artifact
  render dispositions

### Validation

- scoping e2e: the Files view lists only the caller's objects, and list / download / delete on
  another user's key is rejected
- the `linux-cpu` plus chosen `linux-gpu` cohort records the attestation

### Remaining Work

None. Closed on the selected accelerator plus `linux-cpu`.

### Documentation Requirements

- update `documents/reference/web_portal_surface.md` and `documents/reference/api_surface.md` for
  the Files view and the `list` / `delete` object endpoints
- keep `documents/architecture/tenant_isolation_doctrine.md` aligned with the prefix-scoped listing
  and deletion behavior

---

## Sprint 7.27: In-Browser MIDI/MusicXML/ZIP Rendering [Done]

**Scope boundary**: Mounted renderer nodes/dispositions do not establish playable MIDI or successful media rendering. Sprint 7.33 owns sample assets and behavioral browser assertions.

**Status**: Done
**Implementation**: `src/Infernix/Web/Contracts.hs`, `src/Infernix/Demo/Api.hs`, `web/src/Infernix/Web/Artifacts.purs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/package.json`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/architecture/demo_app_design.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Render MIDI, MusicXML/`.mxl`, and ZIP-stem artifacts in the browser through new render dispositions
and self-hosted PureScript FFI, replacing the download-only fallback for those families.

### Deliverables

- new `ArtifactRenderDisposition` variants for audio/MIDI, MusicXML, and ZIP
- PureScript FFI for `fflate` (ZIP stems to inline audio), `@tonejs/midi` plus `smplr` (MIDI
  playback and piano-roll with self-hosted samples), and `opensheetmusicdisplay` (MusicXML/`.mxl` to
  SVG, code-split)
- flipped `DownloadOnly` disposition for `audio/midi`, MusicXML, and `application/zip`

### Validation

- e2e: a MIDI artifact plays and renders a piano-roll, a MusicXML/`.mxl` artifact renders SVG, and a
  ZIP stem set renders inline audio — none falls back to download-only
- the `linux-cpu` plus chosen `linux-gpu` cohort records the attestation

### Remaining Work

None. Closed on the selected accelerator plus `linux-cpu`.

### Documentation Requirements

- update `documents/reference/web_portal_surface.md` and `documents/architecture/demo_app_design.md`
  for the new render dispositions and in-browser MIDI/MusicXML/ZIP behavior
- record the retired `DownloadOnly` disposition for `audio/midi`, MusicXML, and `application/zip` in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

---

## Sprint 7.28: Generated Artifact Object Ownership and Result-Bridge Authorization [Done]

**Status**: Done
**Implementation**: `proto/infernix/runtime/inference.proto`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Objects/Layout.hs`, `python/adapters/common.py`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/object_access_doctrine.md`, `documents/architecture/tenant_isolation_doctrine.md`, `documents/engineering/object_storage.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make generated artifact object ownership derive from the authenticated user and context before work is
dispatched, so every artifact-family result is authorized through the same `users/<sub>/` prefix rule as
browser uploads and downloads.

### Deliverables

- add a typed generated output target or prefix to the worker request, derived from `userId` and
  `contextId` by Haskell code
- make Python adapters upload only to the supplied target and reject missing/invalid generated-output
  ownership data
- make native-process-runner uploads use the same supplied target instead of `native-generated/...`
- make the result bridge parse structured object refs and reject or fail closed on raw keys outside
  `users/<sub>/contexts/<ctx>/generated/`
- add tests proving generated artifacts use `users/<sub>/contexts/<ctx>/generated/` and cannot be read
  by another authenticated `sub`

### Validation

- `cabal test infernix-unit --test-options='--hide-successes'`, `cabal build
  test:infernix-integration`, `python3 -m py_compile python/adapters/common.py`,
  `cabal run exe:infernix -- test lint`, and `cabal run exe:infernix -- lint proto` exit zero
- `./bootstrap/linux-gpu.sh test` passes: Haskell style, Python `check-code`, Haskell unit, web
  contracts, full integration with every `linux-gpu` catalog row producing real output, routed
  Playwright, and the browser per-model matrix
- `./bootstrap/linux-cpu.sh build` rebuilds `infernix-linux-cpu:local`, and
  `./bootstrap/linux-cpu.sh test` passes: Haskell style, Python `check-code`, Haskell unit, web
  contracts, full integration with HA/chaos and throughput, routed Playwright, and the browser
  per-model matrix

### Remaining Work

None.

---

## Sprint 7.29: ClusterState Field Retirement and Object-Proxy Evidence [Done]

**Status**: Done — implemented and validated.
**Cohort**: closed on the 2026-08-17 apple-silicon plus `linux-cpu` full-suite `test all` pair
recorded on the selected accelerator plus `linux-cpu`. the selected accelerator's earlier pass
remains historical and is not read as current proof.
**Implementation**: `src/Infernix/Types.hs`,
`src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Blocked by**: nothing — Sprint 2.14 and Sprint 4.28 are closed.
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's
existing engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: retire the
`clusterPresent::Bool` and `lifecyclePhase`/`lifecycleAction`/`lifecycleDetail`::`String` fields from
`ClusterState`/`LifecycleProgress`; gate the object-proxy routes on a `DemoBucketsProvisioned`
readiness value; and require a proven `.ready` sentinel for bootstrap — so each operation that acts on
a system state carries typed evidence for that state rather than an untyped flag, encoding evidence,
not hope. It generalizes the results-side realness contract to state transitions per the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- retire `clusterPresent::Bool` and the `lifecyclePhase`/`lifecycleAction`/`lifecycleDetail`::`String`
  fields from `ClusterState` and `LifecycleProgress` in favor of typed transition evidence. The
  stringly `LifecycleProgress` type and its `lifecycleAction` / `lifecyclePhase` / `lifecycleDetail`
  / `lifecycleHeartbeatAt` fields are gone from `src/Infernix/Types.hs`; readers (Models.hs status
  JSON, Cluster.hs monitor/status/resume) consume the typed `LifecyclePhase` and its closed
  `LifecycleTransition` through the `lifecyclePhaseOf` accessor.
  [Sprint 2.14](phase-2-kind-cluster-storage-and-lifecycle.md) already retired
  `clusterPresent :: Bool` in favour of the authoritative `clusterLifecycle`
- gate the `Demo/Api.hs` object-proxy routes on a `DemoBucketsProvisioned` readiness value returned by
  the provisioning transition rather than an ambient boolean: the `/api/objects`
  upload/download/list/delete routes take an opaque witness minted only by
  `ensureDemoBucketsWithRetry`, and `withDemoBucketsProvisioned` forces that evidence and responds
  503 when the buckets are not provisioned
- require a proven `.ready` sentinel in `Runtime/Pulsar.hs` before bootstrap-dependent work proceeds:
  the inference bootstrap retry awaits the typed `awaitModelBootstrapReady` evidence and then
  `proveModelReadySentinel`, a bounded MinIO HEAD of the sentinel, closing the
  event-without-durable-sentinel race with a typed `model_cache_bootstrap_sentinel_unproven` failure.
  `loadBootstrapPresignedConfig` is coordinator-only — it needs the cluster ConfigMap and Secret
  mounts, which the Apple **host** engine daemon does not have — so `proveModelReadySentinel` defers
  on the host, letting the retry proceed and relying on the host's own sentinel-gated hydration
  (`ensureNativeRunnerContractCacheReady` → `nativeModelReadySentinelExists`), while the coordinator
  and Linux engine pods run the real HEAD probe
- the typed `ModelBootstrapReadyEvent` carries the causal request-attempt key of the authorized
  request it answers (`readyEventRequestAttemptKey`, sourced from
  `modelBootstrapRequestAttemptKey`), and the field stays optional on decode so ready events
  retained from before the key existed still decode. A ready event identified only by model id is
  ambiguous whenever eager staging and engine recovery are in flight for the same model, so the
  adversarial deduplication check counts raw Pulsar message IDs only for that exact authorized
  attempt rather than attributing every concurrent ready event for the model to one replayed request
- `web/src/Infernix/Web/ArtifactTransport.js` updates every current artifact card matching the object
  key and stamps download readiness only after preview/render state is ready, so a download grant
  that resolves before the text-preview DOM update cannot report the card as ready early

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `infernix lint docs` exit zero, exercised on both the apple-silicon and linux-cpu lanes
- `poetry run check-code` exits zero for any Python/native change surface, on both lanes

### Remaining Work

None.

---

## Sprint 7.30: Restore Durable Dispatcher State Before Cursor Resume [Blocked]

**Status**: Blocked
**Code-side closure**: Dispatcher restoration and restart regressions pending.
**Cohort gate**: Wave R7 — selected `linux-gpu` plus native `linux-cpu`.
**Blocked by**: Sprint 6.55 code-side closure.
**Implementation targets**: `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Dispatch/SingleFlight.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`, `documents/development/testing_strategy.md`

### Objective

Recover queued and active conversation work from durable state before continuing an existing
subscription.

### Deliverables

- Reconstruct each dispatcher's reducer from retained history or a verified durable checkpoint
  plus its complete suffix before consuming beyond the restored cursor. An empty reducer cannot
  resume after acknowledged queued prompts.
- Define the snapshot/replay-to-live boundary and deduplicate overlapping observations by durable
  identity. Retention gaps, invalid checkpoint identity, and unobservable history fail visibly
  rather than discarding pending work.
- Preserve terminal-result-before-acknowledgement ordering and effectively-once visible outcomes;
  no exactly-once compute or transport guarantee is inferred.
- Recover Phase 7's missing retained evidence or rerun it as part of Wave R7, retaining each
  follow-on sprint's required behavior.

### Validation

- With real Pulsar, start prompt A and durably queue B, acknowledge the relevant conversation
  events, restart the coordinator while A is incomplete, then complete A. B must dispatch and
  reach a terminal result without resubmission.
- Separately restart at replay/live handoff and terminal/ack boundaries, redeliver an event, and
  introduce a history gap. Assert queue order, no silent loss, effectively-once user-visible
  completion, and explicit refusal when reconstruction is impossible.
- A fresh context and an ordinary unbroken session are positive controls. Assert actual engine
  dispatch/result observations, not only reconstructed reducer fields.
- Run governed build, lint/unit, focused docs/plan gates, then the phase's Wave R7 selected pair.

### Remaining Work

Implement restoration and real-broker regressions; retain Wave R7 evidence. Pending hardware
sign-off alone does not block code-side progress.

## Sprint 7.31: Reconstruct Conversation Context and Use Verified Engine KV State [Blocked]

**Status**: Blocked
**Code-side closure**: Real context reconstruction and engine-cache use pending.
**Cohort gate**: Wave R7.
**Blocked by**: Sprint 7.30 code-side closure.
**Implementation targets**: `src/Infernix/Runtime/KVCache.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Dispatch/SingleFlight.hs`, `python/adapters/`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/bounded_inference_memory.md`, `documents/engineering/model_lifecycle.md`, `documents/development/python_policy.md`

### Objective

Make durable conversation history reach the engine and make cache validity describe actual
constructed engine state.

### Deliverables

- Rebuild the canonical ordered, tenant-scoped conversation prefix from durable events and feed it
  to inference under the admitted execution shape. Sending only the latest prompt cannot count
  as context reconstruction.
- Read through the exact supplied `conversationLogOffset` and recompute its canonical projection
  hash; require agreement with the supplied `prefixHash` before engine use. Missing, unobservable,
  cross-context, or tampered history refuses visibly rather than substituting the current prompt.
- Bind cache identity to model/artifact, tokenizer/template, execution shape, tenant/context, and
  verified prefix. Publish validity only after successful engine state construction; invalidation,
  failed construction, restart, and prefix divergence cannot reuse optimistic hash bookkeeping.
- Consume cache decisions in both worker paths and invoke supported engine reuse APIs. For a
  backend without reusable KV state, reconstruct and replay the full bounded prefix and report
  replay explicitly; do not claim a cache hit.
- Charge resident KV and reconstruction buffers to the bounded execution budget. Remove the
  unused/hash-only success path through the cleanup ledger.

### Validation

- Use real multi-turn requests whose second result depends on a fact in the first turn; prove that
  the reconstructed input reaches the actual engine. A constant/context-free adapter is an
  independent negative control.
- Compare uninterrupted execution with restart and cache-loss reconstruction using a pinned
  deterministic fixture where supported and recorded engine inputs/state transitions otherwise.
  Observe reuse through the backend cache operation/state, not solely a hash-map hit or timing.
- Change model, prefix, execution shape, and user/context independently; each invalidates the
  appropriate cache. Fail construction after bookkeeping would previously be written and prove
  no valid cache is advertised or reused.
- Independently remove a retained event, alter its bytes, mismatch `conversationLogOffset`, and
  supply a foreign context with a matching-looking hash. Each fails durable-prefix verification
  before engine use; a complete matching prefix is the positive control.
- Run the common governed code-side gates and Wave R7 with explicit reuse versus replay results
  for supported backends.

### Remaining Work

Implement durable prefix reconstruction, supported engine KV integration, bounded accounting,
and independent behavioral proofs.

## Sprint 7.32: Cancel Engine Execution Before Releasing Execution Authority [Blocked]

**Status**: Blocked
**Code-side closure**: Engine cancellation propagation and race coverage pending.
**Cohort gate**: Wave R7.
**Blocked by**: Sprint 7.31 code-side closure.
**Implementation targets**: `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Runtime/CappedEngine.hs`, `src/Infernix/Dispatch/SingleFlight.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/daemon_topology.md`, `documents/architecture/managed_state_transitions.md`

### Objective

Make cancellation terminate the owned inference and publish an unambiguous durable terminal
outcome before releasing its execution authority. The conversation projection may resolve the
cancelled prompt and queue/dispatch its successor immediately; the engine must wait for the old
execution's verified cleanup before that successor starts.

### Deliverables

- Propagate a typed cancellation intent to the executing engine using the request's stable
  identity. Stop its owned computation/process tree, reap children, release artifacts/KV state
  safely, and publish the terminal cancellation result.
- Distinguish queued cancellation from running cancellation. Hold running execution authority
  until terminal cleanup is established; receiving an event alone cannot authorize concurrent
  execution even when the dispatcher has already queued the next request.
- Define the completion/cancellation winner, duplicate cancel handling, late result suppression,
  and restart/redelivery recovery without falsely claiming exactly-once computation.
- Expose cancellation progress and failure visibly through durable conversation state.

### Validation

- Cancel a real running inference, observe its actual child/engine termination and cleanup, then
  execute the queued request. Assert no overlap of conflicting execution authority and one
  visible terminal outcome for the cancelled request.
- Independently exercise queued cancel, duplicate cancel, completion winning the race,
  cancellation winning, lost consumer/restart, late result, and cleanup failure.
- A disabled cancellation consumer must fail the runtime assertion even if the browser already
  displays a cancellation event. Normal completion without cancellation is the positive control.
- Run the common governed code-side gates and Wave R7, including the routed browser cancel flow.

### Remaining Work

Implement cancellation through the engine and durable terminal boundary; prove race and cleanup
behavior on the selected phase pair.

## Sprint 7.33: Bound Artifact Preview and Verify MIDI and Media Rendering [Blocked]

**Status**: Blocked
**Code-side closure**: Bounded transfer/rendering and MIDI asset/playback work pending.
**Cohort gate**: Wave R7.
**Blocked by**: Sprint 7.32 code-side closure.
**Implementation targets**: `src/Infernix/Demo/Api.hs`, `src/Infernix/Web/Contracts.hs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/playwright/inference.spec.js`, `web/package.json`, `docker/Dockerfile`
**Docs to update**: `documents/architecture/object_access_doctrine.md`, `documents/architecture/durable_context_design.md`, `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/engineering/object_storage.md`

### Objective

Enforce preview bounds at every buffering boundary and make advertised media dispositions
produce observable rendering or playback.

### Deliverables

- Define one typed preview-byte and render-size budget shared by backend and browser. Bound
  upstream reading, response buffering, decode expansion, and DOM insertion; expose truncation
  and an explicit full-download action.
- Keep authenticated object access and cancellation of superseded preview requests intact.
  Whole-object reads followed by slicing do not satisfy a bounded preview.
- Materialize/version required MIDI sample assets in the served bundle/image, exercise actual
  decoding and audio scheduling, and report loading/playback failures visibly. Keep an explicit
  unsupported disposition where a renderer cannot operate.
- Replace mount-node/disposition-only E2E success with decoded media, visible renderer state,
  required asset loading, and playback-specific signals. Browser autoplay rules remain explicit;
  use an allowed user interaction and verify audio processing, not human audibility.

### Validation

- Serve a large or streaming object with a known prefix and multibyte boundary; observe bounded
  backend/browser transfer, decoding, and render size plus truncation. A small complete object is
  the positive control. A server that ignores a Range request must still be bounded by the proxy.
- Independently remove/corrupt MIDI samples, disable audio scheduling, and provide malformed
  MIDI/MusicXML/media. Each required render/playback case fails visibly and fails its assertion;
  widget existence cannot discharge it.
- Verify real supported MIDI/media output and a bounded text preview through the authenticated
  routed path on Wave R7, after the governed build, lint/unit and docs/plan gates.
- Retain or replace the missing Phase 7 attestation with checkable source, asset, per-case result,
  and selected accelerator/CPU identities; no result is created by this documentation update.

### Remaining Work

Implement bounds and sample provisioning, replace superficial browser assertions, and retain
Wave R7 evidence for all four follow-on sprints.

## Remaining Work

Implement Sprints 7.30–7.33, pass their governed machine-independent gates, and retain Wave R7's `linux-gpu` plus native `linux-cpu` full-suite results for the same frozen source. No remediation implementation or new cohort result is supplied by this documentation change. Closed sprint headings retain only their established scope; the follow-on criteria are the phase's outstanding work.

## Documentation Requirements

- [Durable context](../documents/architecture/durable_context_design.md), [daemon topology](../documents/architecture/daemon_topology.md), and [Pulsar](../documents/tools/pulsar.md): replay before cursor resume, queued-work recovery, typed request identity, terminal acknowledgement, and cancellation through engine cleanup.
- [Bounded inference memory](../documents/architecture/bounded_inference_memory.md), [model lifecycle](../documents/engineering/model_lifecycle.md), and [Python policy](../documents/development/python_policy.md): verified conversation input, genuine backend state reuse or explicit replay, and retained-state memory accounting.
- [Object access](../documents/architecture/object_access_doctrine.md), [tenant isolation](../documents/architecture/tenant_isolation_doctrine.md), [object storage](../documents/engineering/object_storage.md), and [MinIO](../documents/tools/minio.md): authenticated owner-scoped access, real artifact hydration, bounded previews, and streamed full downloads.
- [Demo design](../documents/architecture/demo_app_design.md), [web UI architecture](../documents/architecture/web_ui_architecture.md), [web portal](../documents/reference/web_portal_surface.md), and [API surface](../documents/reference/api_surface.md): durable UI state, explicit render/load errors, self-hosted MIDI assets, and meaningful media rendering/playback.
- [Keycloak](../documents/tools/keycloak.md), [access control](../documents/architecture/access_control_doctrine.md), and [frontend contracts](../documents/development/frontend_contracts.md): auth, user/admin boundaries, Haskell-owned snapshots and generated browser contracts.
- [Kubernetes storage](../documents/engineering/k8s_storage.md), [cluster runbook](../documents/operations/cluster_bootstrap_runbook.md), and [Apple runbook](../documents/operations/apple_silicon_runbook.md): platform-service PVCs, no daemon PVCs, one process per role per machine, and explicit Apple host-engine startup.
- [Testing strategy](../documents/development/testing_strategy.md), [demo test plan](../documents/development/demo_app_test_plan.md), and [testing doctrine](../documents/engineering/testing.md): source-bound positive and adversarial execution evidence, required-check accounting, real broker restart, history-dependent inference, cancellation, preview bounds, and media output.
- [Root README](../README.md) summarizes and links to these contracts. [Plan README](README.md), [system components](system-components.md), [cohort waves](cohort-validation-waves.md), and [deletion ledger](legacy-tracking-for-deletion.md) hold actual scope, evidence obligations, and only still-existing removal surfaces.
