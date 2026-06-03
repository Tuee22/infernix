# Pulsar

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported production topic contract and the current daemon
> implementation.

## Rules

- the supported default Pulsar tenant/namespace is `infernix/demo`; every supported demo and
  production topic name uses the `persistent://infernix/demo/...` prefix unless an explicit
  staged `.dhall` value overrides it, and `cluster up` reconciles that tenant and namespace
  before topics are produced or subscribed
- Pulsar is the durable event-transport shape for the production inference surface: the active
  `.dhall` names the daemon role, request topics, result topic, and any configured batch handoff
  topic that the production daemons own, and `infernix service` keeps those daemons on a no-HTTP
  surface
- repo-owned `.proto` schemas define the payload contract for request and result topics; the same
  schemas feed both `proto-lens`-generated Haskell bindings and auto-generated Python protobuf
  modules consumed by the active substrate adapter package
- the production daemon reads `ClusterConfig.pulsar.wsBaseUrl` and
  `ClusterConfig.pulsar.adminUrl` from the mounted cluster manifest, then uses Pulsar's WebSocket
  producer or consumer endpoints plus the admin schema API for the configured topics
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

The active `.dhall` config carries the production inference fields consumed by `infernix service`:

- `daemonRole : Text` - the role selected by the colocated file for the daemon process
- `coordinator` - coordinator-role metadata, including request topics, result topic, location,
  and the configured batch handoff topic when the coordinator forwards requests to an engine
- `engine` - engine-role metadata, including the batch topic to consume, result topic, and
  publication-edge auto-discovery mode for Apple host daemons
- `request_topics : List Text` - topic names the cluster daemon watches for inbound inference
  requests
- `result_topic : Text` - the topic that completed results are written to
- `engines : List EngineBinding` - the engines available to the worker dispatch layer; Python-native
  bindings execute through the named adapter entrypoints in the active substrate project
- the optional `demo_ui : Bool` flag toggles the `infernix-demo` workload (production deployments
  leave it off)

The three-role daemon model in
[../architecture/daemon_topology.md](../architecture/daemon_topology.md) maps to Pulsar
subscriptions as follows. The coordinator role (`infernix-coordinator` Deployment on every
substrate; today's in-cluster Apple daemon plays this role) consumes `request_topics`, applies
the dispatch and batching rules, and publishes to the configured batch handoff topic. Linux
defaults use `inference.batch.<mode>`; Apple host-native handoff uses
`inference.batch.apple-silicon.host`. The engine role (`infernix-engine` Deployment on Linux;
on-host daemon on Apple) consumes that topic, executes the engine adapter, and publishes results
to `result_topic`. The coordinator then writes the result back to the originating per-context
conversation topic via the result-bridge.

The Sprint 7.7 daemon split is landed:
`chart/templates/deployment-service.yaml` is gone, the chart ships
`deployment-{coordinator,engine}.yaml` instead, and the
`inference.batch.<mode>` topic family is now defined on every substrate
(see `src/Infernix/Models.hs.canonicalBatchTopicForMode`). Apple silicon
already ran the supported two-process shape and was renamed cleanly
under Sprint 7.7's `Coordinator` / `Engine` vocabulary.

The May 27, 2026 Linux GPU integration extension validates the batch
handoff contract on a real cluster: routed publication JSON exposes the
configured `hostInferenceBatchTopic`, `cluster status` prints
`publicationHostInferenceBatchTopic`, the generated demo config routes the
coordinator from `inference.request.linux-gpu` to `inference.batch.linux-gpu`,
and the engine config consumes that batch topic without forwarding again.

## Demo Conversation and Metadata Topics

Phase 7's durable-context demo uses three additional Pulsar topic families. They are
demo-gated and absent when `demo_ui = false`.

| Topic family | Pattern | Partition | Retention | Compaction |
|---|---|---|---|---|
| Per-context conversation log | `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` | 1 | full retention with tiered storage offload to MinIO | off |
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
- the frontend pod's per-WS Pulsar **Reader** subscriptions on conversation and metadata
  topics give pod-failover-safe fan-out without sticky sessions; the per-context inference
  dispatcher in the coordinator pod uses a named **Failover** subscription so exactly one
  coordinator replica is the active dispatcher per context at a time; the result-bridge in
  the coordinator pod uses a named **Failover** subscription on `inference.result.<mode>`
  with the same semantics
- the May 28, 2026 Linux GPU integration pass publishes `ClientCreateContext`,
  `ClientUpdateDraft`, and `ClientCancelPrompt` through the real broker, reads them back with
  Pulsar Readers, asserts the expected broker keys, decodes the typed JSON payloads, and
  verifies that duplicate frontend publishes with the same mutation-scoped producer name and
  WebSocket-sequenced dedup ID store exactly one conversation or draft message
- the same pass reads the `infernix/demo` namespace compaction threshold through Pulsar admin,
  asserts the supported 100 MiB policy, explicitly compacts the contexts and drafts topics, and
  verifies with a Java Pulsar `readCompacted(true)` reader that the broker returns exactly one
  latest payload per `contextId`
- the same integration layer submits a real durable-context prompt and observes a completed
  `ConversationInferenceResultEvent` on the conversation log after the dispatcher,
  request/batch handoff, engine, and result bridge run; the browser E2E layer also proves
  frontend pod replacement reconnects, resubscribes, and continues prompt submission

## Model-Bootstrap Topic

Phase 7 Sprint 7.7 added a third Failover subscription type in the coordinator pod for
lazy model-weight population to MinIO with exactly-once semantics. The supported
`infernix` tenant plus the `infernix/system` and `infernix/demo` namespaces (with
deduplication enabled) are reconciled on daemon startup by
`reconcileSupportedNamespaces` (`src/Infernix/Runtime/Pulsar.hs`); the
`persistent://infernix/system/model.bootstrap.request` topic is created during the same
reconcile pass. The coordinator's bootstrap consumer + downloader + MinIO uploader
runtime loop is implemented; Sprint 7.14's remaining chaos validation proves failover and
exactly-once behavior on a real cluster:

| Topic | Pattern | Purpose |
|---|---|---|
| Model bootstrap request | `persistent://infernix/system/model.bootstrap.request` | Engine pods publish a request keyed by `modelId` when a model is not yet present in `infernix-models`. Producer dedup on `modelId` collapses concurrent retries. |
| Model bootstrap ready | `persistent://infernix/system/model.bootstrap.ready.<modelId>` | Coordinator's bootstrap worker publishes a ready event after `infernix-models/<modelId>/.ready` has been written. The ready record is keyed by `modelId`. Engine pods that published a request subscribe with bounded timeout. |

Rules:

- the `infernix/system` namespace is **always-on** (not demo-gated) — model weights are a
  platform-level concern, present even in production where `demo_ui = false`
- the coordinator's bootstrap subscription is a Pulsar named **Failover** subscription —
  exactly one coordinator replica processes a given `modelId` at a time; on crash, Pulsar
  promotes a surviving replica and redelivers the unacked request
- the coordinator is the only daemon role with outbound-internet egress; the request
  carries no upstream URL itself — the worker reads the URL from the active substrate's
  staged `.dhall` catalog, keyed by `modelId`
- the May 28, 2026 Linux GPU integration pass publishes a real `ModelBootstrapReadyEvent` to
  `model.bootstrap.ready.<modelId>`, reads it back with a Pulsar Reader, asserts broker key
  `modelId`, and decodes the typed payload
- the `infernix-models/<modelId>/.ready` sentinel object in MinIO is written **last** so the
  upload is atomically visible; engines observe `.ready` and only then load weights
- failure mode: if the worker dies mid-upload, the surviving replica re-checks MinIO; if
  the `.ready` sentinel is already present (idempotent guard), the worker simply publishes
  the ready event; otherwise the download restarts from scratch
- conversation topics opt into Pulsar's tiered storage so cold ledgers offload to MinIO; hot
  read paths stay broker-resident
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
