# Pulsar

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../architecture/engine_pool_routing.md](../architecture/engine_pool_routing.md), [../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported production topic and daemon contract.

## Rules

- the supported default Pulsar tenant/namespace is `infernix/demo`; every supported demo and
  production topic name uses the `persistent://infernix/demo/...` prefix unless an explicit
  staged `.dhall` value overrides it, and `cluster up` reconciles that tenant and namespace
  before topics are produced or subscribed
- Pulsar is the durable event-transport shape for the production inference surface: the active
  `.dhall` names the daemon role, request topics, result topic, and the validated engine-pool graph
  that production daemons own, and `infernix service` keeps those daemons on a no-HTTP surface
- repo-owned `.proto` schemas define the payload contract for request and result topics; the same
  schemas feed both `proto-lens`-generated Haskell bindings and auto-generated Python protobuf
  modules consumed by the active substrate adapter package
- the production daemon reads `ClusterConfig.pulsar.wsBaseUrl` and
  `ClusterConfig.pulsar.adminUrl` from the mounted cluster manifest, then uses Pulsar's WebSocket
  producer or consumer endpoints plus the admin schema API for the configured topics
- trusted tooling that runs outside a cluster pod — the Apple host-native daemon and the Linux
  outer-container `cluster up` / `infernix test` flows — reaches Pulsar's real `/admin/v2` and
  `/ws/v2` surfaces directly on the un-gated Pulsar-proxy HTTP NodePort (in-cluster `30080`), not
  through the Keycloak-JWT-gated `/pulsar/admin` Envoy edge route on the gateway NodePort (`30090`).
  The operator-routes `SecurityPolicy` gates browser/operator access to `/pulsar/admin` only, so
  routing trusted launcher admin-v2 reconcile or topic-compaction calls through the edge fails closed
  with `401 Jwt is missing`; the launcher joins the private `kind` Docker network and so reaches the
  proxy NodePort on the control-plane node IPv4 exactly as it reaches the gateway NodePort
- when those endpoints are intentionally absent in unit-level harnesses, the daemon can exercise
  the repo-local topic spool rooted at `./.data/runtime/pulsar/`: request topics and the result
  topic become directories, and schema registration is mirrored as marker files under
  `./.data/runtime/pulsar/schemas/`
- result payloads remain protobuf messages in both cases: over Pulsar topics on supported cluster
  paths, and as `.pb` files under the harness-local `result_topic` directory on the repo-local
  topic spool. Batch payloads reuse the inference-request protobuf while moving through the
  configured batch handoff topic.
- because Pulsar is first enabled in the final Harbor-backed Helm phase, `cluster up` forces the
  upstream bookkeeper and cluster-initialization jobs there on the real Kind path
- the final chart keeps `pulsar.proxy.configData.webSocketServiceEnabled: "true"` so the internal
  daemon transport and the routed `/pulsar/ws` surface both terminate on Pulsar's real WebSocket
  endpoints
- when the daemon starts before Pulsar admin is fully ready, schema registration retries until the
  admin API accepts the requested topic schemas

## Routed Surfaces

<!-- infernix:route-registry:pulsar:start -->
- `/pulsar/admin` -> `infernix-infernix-pulsar-proxy:80`; rewrites to upstream `/`
- `/pulsar/ws` -> `infernix-infernix-pulsar-proxy:80`; rewrites to upstream `/ws`
<!-- infernix:route-registry:pulsar:end -->

- the supported Gateway contract targets Pulsar's real `/admin/v2` and `/ws` surfaces, and
  integration requires those real upstream responses on the shared edge

## Production Inference Subscription Contract

Delivery is **at-least-once with an effectively-once observable outcome**: an engine acknowledges a
pool message only after the terminal result is published, so a machine lost mid-inference costs a
redelivery and duplicate compute rather than an unanswered request, and producer-side dedup collapses
the duplicate at the effect. Redelivery is the only recovery path the pipeline has, because request
publishes carry a deduplicating sequence id that makes re-dispatch a no-op. The canonical statement
and its rationale live in
[../architecture/daemon_topology.md](../architecture/daemon_topology.md).

The active `.dhall` config carries the production inference fields consumed by `infernix service`:

- the **system contract** carries the substrate and the validated pool record whose values are the
  model descriptors; every publish and subscribe topic is *derived* from
  `(runtimeMode, pool id, model id, optional member id)` rather than written down, so two machines
  cannot spell one topic differently
- the **machine contract** carries this box's `node` block — its role, its required member id, and
  the pools it serves — selected out of the system contract by field access
- `engines : List EngineBinding` - the engines available to the worker dispatch layer; Python-native
  bindings execute through the named adapter entrypoints in the active substrate project
- the optional `demo_ui : Bool` flag toggles the `infernix-demo` workload (production deployments
  leave it off)

The three-role daemon model in
[../architecture/daemon_topology.md](../architecture/daemon_topology.md) and
[../architecture/engine_pool_routing.md](../architecture/engine_pool_routing.md) maps to Pulsar
subscriptions as follows. The coordinator role (`infernix-coordinator` Deployment on every
substrate) consumes `request_topics`, applies dispatch, batching, and pool-routing rules, and
publishes to a derived pool/model topic. Engine members consume their assigned derived topics,
execute the engine adapter, and publish results to `result_topic`. Normal scalable pools use
`Shared` subscriptions so Pulsar's permits and receiver backlog provide broker-native
backpressure. Pinned routes use derived per-member topics with `Exclusive` subscriptions. `Failover`
provides stable single-active broker coordination for dispatcher, result-bridge, and model-bootstrap
work; it is not standby-replica availability or the Apple work-fanout model.

The topic family is derived from the validated pool graph:

```text
persistent://infernix/demo/inference.batch.<mode>.pool.<poolId>.model.<modelId>
persistent://infernix/demo/inference.batch.<mode>.member.<memberId>.model.<modelId>
```

The first form is the scalable pool path; the second form is the pinned-member path. Coordinator
pool handoff and engine subscriptions derive from this graph. The
`inference.batch.<mode>`, `inference.batch.<mode>.<engine>`, and
`inference.batch.apple-silicon.host` helper topics are outside supported routing.

Validation rejects invalid graphs and checks derived topic selection. Apple broker validation
exercises pinned-member `Exclusive` ownership, `Shared` backlog distribution, inference completion,
and the production `demo_ui = false` shape. Linux CPU validation checks Kubernetes-observed pool
placement and `Shared` backlog/backpressure on isolated derived pool/model topics. A claim of
physical multi-host Apple routing additionally requires evidence from distinct Apple hosts.

All inference and model-bootstrap publication topology is plan-derived. There is no supported raw
topic publisher; bootstrap publication consumes an opaque capability prepared from the
compiled plan, and the consumer revalidates model identity, compiled download URL, and canonical
timestamp before download/upload/ready-event side effects. Compilation rejects cross-family topic
reuse among coordinator requests, results, bootstrap requests, bootstrap ready events, and engine
routes. Coordinator and engine consumers publish terminal failed results for unavailable,
empty-model, unknown-model, wrong-route, and malformed inputs before acknowledging the source
message.

## Demo Conversation and Metadata Topics

The durable-context demo uses three additional Pulsar topic families. They are
demo-gated and absent when `demo_ui = false`.

| Topic family | Pattern | Partition | Retention | Compaction |
|---|---|---|---|---|
| Per-context conversation log | `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` | 1 | full retention | off |
| Per-user context metadata | `persistent://infernix/demo/demo.user.<userId>.contexts` | 1 | full | on (key: `contextId`) |
| Per-user drafts | `persistent://infernix/demo/demo.user.<userId>.drafts` | 1 | full | on (key: `contextId`) |

Rules:

- the conversation log topic is append-only and append-by-broker-order — single-partition gives
  total order over messages from any number of producers; the broker-assigned `MessageId` is
  the canonical sequence identifier
- conversation events are published without a Pulsar message key; compacted context metadata
  and draft events are published with message key `contextId` so broker compaction has a real
  key to collapse
- typed event variants on the conversation log are `UserPrompt`, `UserUpload`, `UserCancel`,
  and `InferenceResult`; schemas are registered via the Pulsar admin API at `infernix-demo`
  startup
- Pulsar producer-side deduplication is enabled at the broker level with
  `brokerDeduplicationEnabled = true` and on the demo namespace, covering conversation,
  contexts, drafts, `inference.request.<mode>`, `inference.batch.<mode>`, and
  `inference.result.<mode>` topics; long-lived daemon producers carry monotonic sequence IDs
  derived from upstream `MessageId`s or `batchId`s, while frontend mutation producers scope the
  producer name by user/context plus mutation key and pass the WebSocket `initialSequenceId`
  baseline for that one-message producer so arbitrary `ClientIdempotencyKey`, context, and draft
  keys cannot create non-monotonic false-positive drops
- the compacted metadata topics are read by the demo backend with the compacted-reader API to
  drive the SPA's left-rail context list and draft restore; namespace-level compaction policy
  is reconciled on `cluster up`
- `DELETE /api/account` lists `persistent://infernix/demo` and deletes only topics owned by the
  caller's `sub`: `demo.user.<userId>.contexts`, `demo.user.<userId>.drafts`, and
  `demo.conversation.<userId>.*`. Shared inference request/batch/result topics remain intact.
- the frontend process's per-WS Pulsar **Reader** subscriptions on conversation and metadata
  topics give restart-safe fan-out without sticky sessions; the per-context inference
  dispatcher in the coordinator process uses a named **Failover** subscription so exactly one
  coordinator process is the active dispatcher per context at a time; the result-bridge in
  the coordinator pod uses a named **Failover** subscription on `inference.result.<mode>`
  with the same semantics. `Failover` is retained as a *subscription type* because it is how
  Pulsar provides that single-active-consumer coordination; it is not a claim that a second
  coordinator is standing by. One process per role per machine means a single-machine
  deployment has exactly one coordinator, and its loss is a restart
- engine-pool messages are acknowledged only after engine materialization, inference, and durable
  result publication succeed, while failed materialization leaves the message unacked or negatively
  acknowledged for redelivery
- Failover ownership uses stable subscription names; individual
  consumers use process-qualified names via `Infernix.Runtime.Pulsar.Failover`
  so coordinators on different machines do not present identical member names or
  collide with a restarted process
- the integration suite publishes `ClientCreateContext`, `ClientUpdateDraft`, and
  `ClientCancelPrompt` through the real broker, reads them back with Pulsar Readers, asserts
  the expected broker keys, decodes the typed JSON payloads, and verifies that duplicate
  frontend publishes with the same mutation-scoped producer name and WebSocket-sequenced dedup
  ID store exactly one conversation or draft message
- the same suite reads the `infernix/demo` namespace compaction threshold through Pulsar admin,
  asserts the supported 100 MiB policy, explicitly compacts the contexts and drafts topics, and
  verifies with a Java Pulsar `readCompacted(true)` reader that the broker returns exactly one
  latest payload per `contextId`
- the same integration layer submits a real durable-context prompt and observes a completed
  `ConversationInferenceResultEvent` on the conversation log after the dispatcher,
  request/batch handoff, engine, and result bridge run; the browser E2E layer also proves a
  forced WebSocket disconnect reconnects, resubscribes, and continues prompt submission

## Model-Bootstrap Topic

A third Failover subscription type in the coordinator pod backs eager model-weight staging: the
coordinator stages every model in the mounted `infernix.dhall` to MinIO on startup with at-least-once
delivery and an effectively-once observable publication, and the same subscription services fallback bootstrap requests for any unstaged model. The supported `infernix` tenant plus the
`infernix/system` and `infernix/demo` namespaces (with deduplication enabled) are reconciled on
daemon startup by `reconcileSupportedNamespaces` (`src/Infernix/Runtime/Pulsar.hs`); the
`persistent://infernix/system/model.bootstrap.request` topic is created during the same
reconcile pass. The coordinator's bootstrap consumer + downloader + MinIO uploader runtime loop
is exercised on a real cluster by the integration suite:

| Topic | Pattern | Purpose |
|---|---|---|
| Model bootstrap request | `persistent://infernix/system/model.bootstrap.request` | Engine pods publish a request with message key `modelId` when a model is not yet present in `infernix-models`. Producer dedup uses the attempt-scoped `modelId@requestedAt` key so exact request replays collapse while later retry attempts can enqueue work if readiness never appears. |
| Model bootstrap ready | `persistent://infernix/system/model.bootstrap.ready.<modelId>` | Coordinator's bootstrap worker publishes a ready event after `infernix-models/<modelId>/.ready` has been written. The ready record is keyed by `modelId`. Engine pods that published a request subscribe with a 900-second bounded timeout. |

Rules:

- the `infernix/system` namespace is **always-on** (not demo-gated) — model weights are a
  platform-level concern, present even in production where `demo_ui = false`
- the coordinator's bootstrap subscription is a Pulsar named **Failover** subscription —
  exactly one coordinator processes a given `modelId` at a time. On crash the unacked request is
  redelivered: to another machine's coordinator if the fleet has one, and otherwise to the same
  coordinator once it restarts. Redelivery is the recovery path; promotion is not guaranteed to
  find a survivor
- the coordinator is the only daemon role with outbound-internet egress; the request
  carries no upstream URL itself — the worker reads the URL from the active substrate's
  staged `.dhall` catalog, keyed by `modelId`
- the integration suite publishes a real `ModelBootstrapReadyEvent` to
  `model.bootstrap.ready.<modelId>`, reads it back with a Pulsar Reader, asserts broker key
  `modelId`, and decodes the typed payload
- the `infernix-models/<modelId>/.ready` sentinel object in MinIO is written **last** so the
  upload is atomically visible; engines observe `.ready` and only then load weights
- failure mode: if the coordinator dies mid-upload, its restarted process resubscribes under the
  stable Failover name and re-checks MinIO after redelivery; if the `.ready` sentinel is already
  present (idempotent guard), it publishes the ready event; otherwise the download restarts from
  scratch
- conversation topics retain full ledger history on BookKeeper-backed local PVs; tiered MinIO
  offload is not configured
- inference dispatch reuses the existing shared `inference.request.<mode>` and
  `inference.result.<mode>` topics described above; the demo envelope carries
  `(userId, contextId, causalRef, conversationLogOffset, prefixHash)` so engines can verify
  KV-cache consistency against the Pulsar SSoT

See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) for the full
event model, reducer, dispatcher rule, and failure semantics.

## Cross-References

- [minio.md](minio.md)
- [keycloak.md](keycloak.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
