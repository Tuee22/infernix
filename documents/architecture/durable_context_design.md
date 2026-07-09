# Durable Context Design

**Status**: Authoritative source
**Referenced by**: [demo_app_design.md](demo_app_design.md), [overview.md](overview.md), [web_ui_architecture.md](web_ui_architecture.md), [daemon_topology.md](daemon_topology.md), [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Define the product-agnostic durable-context primitives —
> event-sourced state, deterministic reducer plus prefix-hash chain,
> single-flight dispatcher, compacted metadata projections, webapp-mediated
> object storage (server-side proxy — the browser never holds a presigned URL),
> JWKS-backed JWT validation, and stateless WebSocket coordination —
> that any SPA-style application built on the Infernix inference platform
> reuses verbatim.

## TL;DR

- Durable-context applications hold zero per-user state in their pods.
  Conversation logs live in Pulsar; binary artifacts live in MinIO;
  identity lives in a JWKS-backed issuer. The browser holds no durable
  state and reconstitutes from server state on every login.
- All business logic — reducer, idempotency dedup, `prefixHash` chain,
  dispatcher rule, event construction, projection — is Haskell-owned.
  `purescript-bridge` generates every wire ADT. The browser is a thin
  renderer that applies typed patches.
- Pulsar carries an append-only per-context conversation log plus compacted
  per-user metadata topics keyed by `contextId`. The shared
  `inference.request.<mode>` and `inference.result.<mode>` topics carry dispatch.
- Each application binds the primitives by choosing concrete values for the
  parameters in [§ Parametricity Surface](#parametricity-surface).
  [demo_app_design.md](demo_app_design.md) is the first such binding;
  future apps follow the same pattern.
- Pulsar `Reader` subscriptions are the inter-pod fan-out path on the
  WebSocket side; Pulsar named `Failover` subscriptions are the
  per-context single-flight dispatcher. No Redis, no NATS, no in-cluster
  session broker.
- Crashes degrade to redelivery plus cache miss. Pulsar producer-side
  deduplication on the conversation, inference-request, and inference-result
  topics makes every retry idempotent.

## Current Status

The durable-context primitives live in the shared library and are
exercised by Phase 7
([../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)).
The Pulsar, MinIO, Keycloak-capable, and routed edge foundations are in
place; the shared library modules listed in
[§ Module Layout](#module-layout) make these primitives reusable by any
future application. The integration suite validates the compacted
metadata broker contract with live Pulsar admin compaction, a Java
compacted reader, latest-per-`contextId` assertions for context and
draft topics, duplicate frontend publish collapse through broker
producer deduplication, the normal dispatcher → request/batch → engine
→ result-bridge → conversation-log writeback path for one
durable-context prompt, and engine-side prefix-hash cache decisions
through `Infernix.Runtime.KVCache`, `Infernix.Runtime`, and the native
worker harness. The browser E2E layer covers active-context WebSocket
re-subscribe, draft restoration after both reconnect and reload login,
and frontend pod replacement by deleting all `infernix-demo` pods
during the routed flow and submitting another prompt after reconnect.
The Pulsar Failover transport keeps stable subscription names while
process-qualifying consumer names for clearer coordinator promotion
membership.

## Parametricity Surface

A concrete application binds these parameters:

| Parameter | First binding (demo) | Used by |
|---|---|---|
| `<topicNamespace>` | `infernix/demo` | conversation, contexts, drafts topics |
| `<objectsBucket>` | `infernix-demo-objects` | per-user prefix layout |
| `<wsPath>` | `/ws` | WS endpoint |
| `<authPath>` | `/auth` | IdP login surface |
| `<objectsApiPath>` | `/api/objects` | webapp-mediated object upload/download endpoint |
| `<jwtIssuer>` / `<jwtAudience>` | demo Keycloak realm issuer / public SPA client | JWT validation |
| `<appNamespace>` (Haskell) | `Infernix.Demo.*` | application-specific glue modules |
| `<appWorkload>` | `infernix-demo` | the Webapp workload deployed to host the surface |

All shared-library code is parametric in these values. Concrete bindings
live next to the application workload, not inside the shared modules.

## Module Layout

The shared library splits cleanly into product-agnostic primitives, an
application-specific glue layer, and an engine-side reuse path. The
authoritative ownership wall is codified in
[../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md);
this section names the surface so primitives-doc readers can locate it.

- **Shared library (product-agnostic).** Free of HTTP/WS specifics and SPA
  assumptions. Parameterized in topic namespace, bucket name, issuer, and
  audience:
  - `Infernix.Conversation.{Event,Reducer,Idempotency,Hash,Topic}` — event
    ADT, deterministic fold and patch emitter,
    `(contextId, clientIdempotencyKey)` dedup, Merkle-style `prefixHash`
    chain, topic naming and schema registration helpers
  - `Infernix.Topic.{Metadata,Drafts}` — compacted-topic projection
    patterns for append-event and keyed-mutable-state shapes
  - `Infernix.Dispatch.SingleFlight` — per-context dispatcher rule and
    inference request envelope construction
  - `Infernix.Objects.{Layout,Presigned}` — bucket/prefix layout and
    server-side SigV4 signing (against the cluster-internal endpoint) behind
    the webapp object-proxy, with per-user scope checks — the browser never
    receives a presigned URL
  - `Infernix.Auth.Jwt` — JWKS-backed JWT validation parametric in
    `<jwtIssuer>` and `<jwtAudience>`
- **Application glue (`<appNamespace>.*`).** Concrete IdP wiring, WS
  upgrade, HTTP route handlers, WS envelope tagged-sum wire schema,
  first-run bootstrap, application-specific views. May import any shared
  module.
- **Daemon orchestration (`Infernix.Runtime.Daemon`).** Owns
  process startup, role selection, readiness markers, and the
  process-local engine KV-cache handle. It starts coordinator loops only
  for the `Coordinator` role and threads the engine cache into the
  engine request-consumption path.
- **Engine runtime (`Infernix.Runtime`, `Infernix.Runtime.Cache`,
  `Infernix.Runtime.KVCache`, `Infernix.Runtime.Worker`).** Imports
  `Infernix.Conversation.Reducer` and `Infernix.Conversation.Hash`
  through `Infernix.Runtime.KVCache` for engine-side KV-cache
  consistency decisions only. Must not import any application namespace,
  must not import `Infernix.Objects.Presigned`, must not import
  `Infernix.Auth.Jwt`, must not import any WebSocket module.

Dependency arrows are strict: shared library has no upward dependencies;
application glue, daemon orchestration, and engine runtime all depend on
shared library; application glue and engine runtime never depend on each
other.

Adding a second similar app follows the same pattern: a new
`Infernix.<AppName>.*` namespace reuses every shared module verbatim and
the new app writes only its renderer plus the WS envelope variants it
needs. The reusable surface is roughly 80% of the new code by line count.

### Daemon Layout

The three module groups above map onto three daemon roles at deploy
time: the frontend loads in the per-app pod (`<appWorkload>`); the
shared library minus engine-specific paths loads in the stateless
**coordinator** Deployment (which additionally runs the model-cache staging
worker that eagerly populates the `infernix-models` MinIO bucket at startup from
upstream); the engine-side surface plus `Infernix.Runtime.*` loads in
assigned **engine** pool members. Linux engine Deployments use
Kubernetes placement rules; Apple engine members are host daemons with
stable host ids. **No daemon has a PVC** — the only durable state
is in MinIO (binary blobs) and Pulsar (event streams). The engine
pod uses an ephemeral `emptyDir` mount with hard `sizeLimit` for
model-weight staging only. The supported per-pod placement, replica
policy, pool ownership, and no-PVC posture are codified in
[daemon_topology.md](daemon_topology.md) and
[engine_pool_routing.md](engine_pool_routing.md).

## Stateless Transport Coordination

The application Service has `sessionAffinity: None`. Any WS connection
lands on any replica. There is no sticky session, no client-IP affinity,
no cookie affinity on the HTTPRoute.

- On WS connect, the pod validates the JWT, extracts `userId`, and opens
  Pulsar **Reader** subscriptions (cursor-based, no shared subscription
  state across pods) on the user's compacted contexts topic, the compacted
  drafts topic, and each context's conversation topic as the user opens
  it.
- Events the Reader yields are forwarded to the WS as typed
  `WsServerMessage`s carrying projected state snapshots and patches.
- On WS receive, the pod publishes to the appropriate Pulsar topic.
  Pulsar's broker fans the event out to every pod with a Reader on that
  topic — other tabs, other pods, the dispatcher, the cluster daemon.
- The per-context dispatcher uses a Pulsar named **Failover**
  subscription on each conversation topic, so exactly one pod is the
  active dispatcher per context at a time. Different concern, different
  Pulsar primitive.

**No Redis, no NATS, no in-cluster session broker.** Pulsar is the
inter-pod fan-out path because the platform already deeply depends on it,
the per-user state is already in Pulsar topics, and adding a second
pub/sub system would compete with Pulsar's role.

## Server-Side Durability and Client Reconstitution

The browser holds no durable state. The Pulsar log and MinIO bucket are
the SSoT; the IdP's `sub` claim is the stable per-user identifier.

Reconstitution sequence after a fresh login from any device:

1. Browser obtains a JWT from the IdP; opens `<wsPath>` with the JWT; sends `ClientHello`.
2. Pod validates JWT, extracts `sub`, then starts per-user Readers on
   `<topicNamespace>.user.<sub>.contexts` and
   `<topicNamespace>.user.<sub>.drafts`.
3. Server forwards `ContextListState` and `DraftMapState` snapshots;
   browser renders the left rail and draft restore.
4. On user click into a context, server opens conversation Reader on
   `<topicNamespace>.conversation.<sub>.<contextId>` from the start;
   forwards a `ConversationState` snapshot.
5. Subsequent events on any of those topics yield typed patches over the
   WS; browser applies them.
6. Artifacts render by fetching bytes through the webapp object-proxy at
   `<objectsApiPath>` (which signs SigV4 server-side against the
   cluster-internal endpoint); the browser never receives a presigned MinIO URL.

Survives:

| Event | Identity | Contexts | Drafts | Transcripts | Artifacts |
|---|---|---|---|---|---|
| Logout + login (same browser) | survives | survives | survives | survives | survives |
| Clear all browser data | survives | survives | survives | survives | survives |
| Different device, same account | survives | survives | survives | survives | survives |
| Password change | survives | survives | survives | survives | survives |
| Different account | new `sub` → new namespace | — | — | — | — |
| IdP account deletion | gone | unreachable (retained in Pulsar/MinIO until janitor sweep) | unreachable | unreachable | unreachable |

Client-side caching (IndexedDB, service-worker) is an opt-in performance
feature, never a correctness requirement.

## Haskell-First Logic Boundary

All business logic lives only in Haskell:

- the reducer that projects `ConversationEvent` streams into
  `ConversationState` snapshots and a `ConversationStatePatch` delta stream
- idempotency dedup keyed by `(contextId, clientIdempotencyKey)`
- `prefixHash` chain construction and verification
- the dispatcher rule
- event construction and validation
- topic naming, schema registration, and producer dedup configuration
- presigned URL minting and per-user grant-time scope checks
- JWT validation against a JWKS endpoint

`purescript-bridge` generates every wire-crossing ADT and JSON instance
from `src/Infernix/Web/Contracts.hs` to `web/src/Generated/Contracts.purs`.
The browser receives typed `ConversationState` snapshots and
`ConversationStatePatch` deltas over WS and applies patches via trivial
mechanical helpers. The browser does **not** import the reducer; the
reducer is not codegen'd.

This discipline is what keeps a second similar app cheap: vendoring the
shared library pulls in every business rule, and the new app writes only
its renderer plus the WS envelope variants it needs.

## Event Model and Reducer

Typed events on the per-context conversation topic:

- `UserPrompt { idempotencyKey :: ClientIdempotencyKey, text :: Text, attachments :: [ObjectRef] }`
- `UserUpload { idempotencyKey :: ClientIdempotencyKey, object :: ObjectRef, kind :: ArtifactKind }`
- `UserCancel { targetMessageId :: MessageId }`
- `InferenceResult { causalRef :: MessageId, status :: ResultStatus, text :: Maybe Text, artifacts :: [ObjectRef] }`

Each event also carries its broker-assigned `MessageId` (the canonical
sequence) on read.

The Haskell reducer is a deterministic fold:

```
state_n = foldl reduce initialState (log[0..n])
```

`reduce` is total, pure, and deterministic. Given the same log prefix,
every backend pod and every browser computes the same projection — that
is the reproducibility proof. Idempotency, cancellation outcomes, and
ordering are consequences of the reducer's definition, not of operational
behavior.

The reducer's projection-layer dedup rule: the first event with a given
`(contextId, clientIdempotencyKey)` is canonical; subsequent duplicates
are dropped. The raw log may contain duplicates from retries; the
projected state never does.

The reducer also emits a `ConversationStatePatch` for each new event. The
patch has two mechanical variants — `AppendMessage` (one message plus the new
prefix hash) and `ReplaceSnapshot` (a full state replace) — that the browser
applies by folding messages by id, without business logic. The reducer emits
`AppendMessage` per event; `ReplaceSnapshot` carries the first-connect snapshot.
The patch stream is what flows over the WS; the snapshot is what flows on
first connect.

## Pulsar Topology

The application's topics sit under `persistent://<topicNamespace>/`.

| Topic | Pattern | Partition | Retention | Compaction |
|---|---|---|---|---|
| Conversation log | `persistent://<topicNamespace>/conversation.<userId>.<contextId>` | 1 | full retention | off |
| Context metadata | `persistent://<topicNamespace>/user.<userId>.contexts` | 1 | full | on (key: `contextId`) |
| Drafts | `persistent://<topicNamespace>/user.<userId>.drafts` | 1 | full | on (key: `contextId`) |
| Inference request | `persistent://<topicNamespace>/inference.request.<runtimeMode>` | 1 | full | off |
| Inference result | `persistent://<topicNamespace>/inference.result.<runtimeMode>` | 1 | full | off |

The patterns above are the product-agnostic template. A concrete app namespaces the durable-context
local topic names with an application segment: the demo binds them as
`demo.conversation.<userId>.<contextId>`, `demo.user.<userId>.contexts`, and
`demo.user.<userId>.drafts` (see [demo_app_design.md](demo_app_design.md)), while the shared
`inference.{request,result}.<runtimeMode>` topics keep their plain names.

Single-partition topics give total broker order over messages from any
number of producers. Schemas are registered via the Pulsar admin API at
application startup. Producer-side deduplication is enabled at the broker level
and on the demo namespace's conversation, contexts, drafts, inference-request,
and inference-result topics with named producers and dedup sequence IDs derived
from upstream `MessageId`s or mutation-scoped one-message frontend producers. Frontend
publishers include the mutation key in the producer scope and set the WebSocket
`initialSequenceId` baseline so arbitrary client keys remain idempotent without violating
Pulsar's monotonic sequence rule inside a producer.
Conversation events are unkeyed append-log entries; context metadata
and draft records carry Pulsar message key `contextId` so broker compaction collapses by
the same key the reducers use. See [../tools/pulsar.md](../tools/pulsar.md) for the
broker-level contract. The integration suite validates the live
`infernix/demo` namespace compaction threshold, explicitly compacts
context and draft metadata topics, proves the compacted reader returns
one latest payload per `contextId`, and publishes duplicate frontend
conversation/draft messages to prove broker producer dedup stores one
message for each duplicate mutation-scoped producer/sequence pair. It
also submits a real durable-context prompt and observes the completed
result event on the conversation log after the dispatcher, engine, and
result bridge run.

The demo binding sets `<topicNamespace> = infernix/demo` and reuses the
existing shared `inference.request.<mode>` and `inference.result.<mode>`
topics at the platform level; per-application topic names follow this
shape exactly.

## Object Storage Layout

One shared application bucket: `<objectsBucket>`.

Per-user prefixes inside the bucket:

```
users/<userId>/contexts/<contextId>/uploads/<objectKey>
users/<userId>/contexts/<contextId>/generated/<objectKey>
```

`<objectsApiPath>` reads and writes objects **server-side**: it derives the
object prefix from the authenticated user's `sub` claim, authorizes it with
`pathBelongsToUser`, and signs SigV4 against the cluster-internal endpoint to
issue the PUT/GET itself. The browser holds only the webapp origin and never
receives a presigned MinIO URL, so a user cannot reach another user's prefix by
construction. See [../tools/minio.md](../tools/minio.md) for the bucket contract.

The demo binding sets `<objectsBucket> = infernix-demo-objects` and
`<objectsApiPath> = /api/objects`.

## Per-Context Single-Flight Dispatch

The dispatcher is a pure fold over the conversation log. The dispatch
rule:

> Dispatch inference for a `UserPrompt` iff every prior `UserPrompt` in
> the log is resolved — i.e. has a matching `InferenceResult` **or** a
> matching `UserCancel`.

That decision is a deterministic function of the log prefix.
Implementation: a Pulsar named `Failover` subscription per conversation
topic — exactly one pod is the active dispatcher per context at a time.
On crash, Pulsar promotes a surviving pod automatically and redelivers
unacked messages; the new dispatcher reaches the same decision because
it folds the same log.

**Two prompts in a row.** Permitted. UI renders the second prompt as
"queued" until the first completes. State is derived from the same fold.

**Cancellation.** `UserCancel` is an event on the log. It resolves the
target prompt in the projection immediately — the reducer's `isResolving`
treats `UserCancel` as a resolver — so the single-flight slot is freed and
the next queued prompt can dispatch even before the engine responds. The
engine still produces an `InferenceResult` with `status = Cancelled` (or
ignores the cancel if a Completed result was already published) so the
engine-side lifecycle stays consistent. Replay is deterministic.

## Engine Cache Consistency

Inference request envelopes carry `prefixHash`, a Merkle-style content
hash of the deterministic projection at the dispatch offset. The engine's
KV cache is keyed by `(contextId, prefixHash)`:

- **Hit**: cached KV state is provably consistent with the SSoT; reuse.
- **Miss** (engine restart, cancelled-then-replaced prompt, interleaved
  tab activity): rebuild from scratch by folding the conversation log up
  to `conversationLogOffset` and verifying `prefixHash` matches.

Pulsar is append-only and never retracts, so a cached `prefixHash` can
never become silently invalid. The cache cannot lie: either it matches
the SSoT exactly, or it's a miss. There is no "stale but plausible"
mode.

## Failure Semantics

Per-role failure modes (frontend, coordinator, engine) are documented
in [daemon_topology.md § Failure Semantics per Role](daemon_topology.md#failure-semantics-per-role).
This section names the platform-level recovery primitives.

No application pod holds authoritative state. Recovery relies on three
primitives:

- **Pulsar named Failover subscriptions** on the dispatcher, the
  result-to-conversation bridge, and the cluster daemon's inference
  request consumer. Failover is automatic and unacked messages are
  redelivered to the new active consumer.
- **Pulsar producer-side deduplication** (`enableProducerDeduplication =
  true`) on the conversation, inference-request, and inference-result
  topics. Named producers plus dedup sequence IDs derived from upstream
  `MessageId`s make every retry path idempotent at the broker level.
- **Projection-layer dedup** in the reducer on `(contextId,
  clientIdempotencyKey)` catches duplicates Pulsar can't dedup at the
  producer level (e.g., browser-side double-submits across reconnect).

Failure modes:

- **WS-hosting pod crash.** WS drops; client reconnects to any replica;
  new pod re-derives Readers from the JWT; state replays from Pulsar.
  Pending submits replay via `clientIdempotencyKey` retry; reducer dedup
  catches duplicates. The WS pod acks a client submit only after Pulsar
  confirms the publish, so "acked then crashed" implies "already on the
  log."
- **Dispatcher pod crash.** Pulsar Failover redelivers unacked
  `UserPrompt`; new dispatcher applies the same pure-fold rule; producer
  dedup on `inference.request.<mode>` (keyed by `userPromptMessageId`)
  prevents duplicate dispatches.
- **Result-to-conversation bridge crash.** Same Failover + producer-dedup
  pattern on `inference.result.<mode>` → conversation topic writeback
  (dedup keyed by `(userPromptMessageId, kind = InferenceResult)`).
- **Cluster daemon crash mid-inference.** Pulsar redelivers the unacked
  inference request; new engine has KV-cache miss for the request's
  `prefixHash`; rebuilds by folding the conversation log; runs inference;
  producer dedup on the result topic prevents a duplicate result if the
  original pod had partially published.
- **Pulsar broker / MinIO / IdP outages.** Covered by the existing HA
  topology (3-broker Pulsar, 4-replica MinIO, HA-deployed IdP).
  Applications should cache JWKS with a short TTL so brief IdP outages
  don't break existing sessions.

## Validation

The primitives are exercised by the Phase 7 validation surface
([../development/demo_app_test_plan.md](../development/demo_app_test_plan.md))
through the first concrete binding. The primitives themselves are
covered by:

- reducer property tests (determinism, idempotency dedup, hash chain
  monotonicity, patch-stream equivalence to snapshot equality)
- dispatcher pure-fold rule tests across arbitrary log prefixes including
  cancels, two-in-a-row prompts, and out-of-order results
- topic name derivation tests for every `<topicNamespace>` shape
- JWT validation edge cases parameterized in `<jwtIssuer>` and
  `<jwtAudience>` (expired, wrong issuer, wrong audience, malformed,
  valid)
- server-side object-proxy authorization tests (upload / download / list scoped
  to `users/<sub>/`, cross-user prefix rejected with HTTP 403) with arbitrary
  `<objectsBucket>` variants
- compacted-topic projection tests with synthetic in-memory broker plus live Pulsar compaction
  validation for the demo binding
- non-chaos live Pulsar prompt roundtrip through the demo binding's dispatcher, engine, result
  bridge, and conversation-log writeback

A second application reuses every test above by binding the same
parameters to its own concrete values; only the application-specific
glue layer requires new tests.

`infernix lint docs` enforces this doc's metadata block and link
resolution.

## Cross-References

- [demo_app_design.md](demo_app_design.md) — first concrete binding (the
  `infernix-demo` workload)
- [daemon_topology.md](daemon_topology.md) — three-role daemon model and per-substrate placement
- [overview.md](overview.md) — platform topology
- [web_ui_architecture.md](web_ui_architecture.md) — PureScript topology
  for SPA-style bindings
- [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md) — module ownership boundary (authoritative)
- [../tools/pulsar.md](../tools/pulsar.md) — Pulsar topic contract
- [../tools/minio.md](../tools/minio.md) — MinIO bucket and presigned URL contract
- [../development/frontend_contracts.md](../development/frontend_contracts.md) — Haskell-owned contract generation
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md) — execution-ordered build out
