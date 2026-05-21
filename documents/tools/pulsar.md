# Pulsar

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported production topic contract and the current daemon
> implementation.

## Rules

- the supported default Pulsar tenant/namespace is `infernix/demo`; every supported demo and
  production topic name uses the `persistent://infernix/demo/...` prefix unless an explicit
  staged `.dhall` value overrides it, and `cluster up` reconciles that tenant and namespace
  before topics are produced or subscribed
- Pulsar is the durable event-transport shape for the production inference surface: the active
  `.dhall` names the daemon role, request topics, result topic, and any Apple host batch topic
  that the production daemons own, and `infernix service` keeps those daemons on a no-HTTP surface
- repo-owned `.proto` schemas define the payload contract for request and result topics; the same
  schemas feed both `proto-lens`-generated Haskell bindings and auto-generated Python protobuf
  modules consumed by the active substrate adapter package
- when `INFERNIX_PULSAR_WS_BASE_URL` and `INFERNIX_PULSAR_ADMIN_URL` are set, the production
  daemon uses Pulsar's WebSocket producer or consumer endpoints plus the admin schema API for the
  configured topics
- when those endpoints are intentionally absent in unit-level harnesses, the daemon can exercise
  the repo-local topic spool rooted at `./.data/runtime/pulsar/`: request topics and the result
  topic become directories, and schema registration is mirrored as marker files under
  `./.data/runtime/pulsar/schemas/`
- result payloads remain protobuf messages in both cases: over Pulsar topics on supported cluster
  paths, and as `.pb` files under the harness-local `result_topic` directory on the repo-local
  topic spool. Apple host batch payloads reuse the inference-request protobuf while moving through
  the configured host batch topic.
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
- `clusterDaemon` - cluster-role metadata, including request topics, result topic, location, and,
  on Apple, the host batch topic used for handoff
- `hostDaemon` - Apple host-role metadata, including the host batch topic to consume, result
  topic, and publication-edge auto-discovery mode for routed Pulsar connection details
- `request_topics : List Text` - topic names the cluster daemon watches for inbound inference
  requests
- `result_topic : Text` - the topic that completed results are written to
- `engines : List EngineBinding` - the engines available to the worker dispatch layer; Python-native
  bindings execute through the named adapter entrypoints in the active substrate project
- the optional `demo_ui : Bool` flag toggles the `infernix-demo` workload (production deployments
  leave it off)

On `linux-cpu` and `linux-gpu`, cluster daemons consume `request_topics`, execute inference, and
publish directly to `result_topic`. On `apple-silicon`, cluster daemons consume `request_topics`
and publish batches to `hostDaemon.request_topics`; same-binary host daemons consume that batch
topic, execute Apple-native inference, and publish completed results to `result_topic`.

## Demo Conversation and Metadata Topics (Planned)

When the durable-context demo lands (Phase 7), the demo backend uses three additional Pulsar
topic families. They are demo-gated and absent when `demo_ui = false`.

| Topic family | Pattern | Partition | Retention | Compaction |
|---|---|---|---|---|
| Per-context conversation log | `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` | 1 | full retention with tiered storage offload to MinIO | off |
| Per-user context metadata | `persistent://infernix/demo/demo.user.<userId>.contexts` | 1 | full | on (key: `contextId`) |
| Per-user drafts | `persistent://infernix/demo/demo.user.<userId>.drafts` | 1 | full | on (key: `contextId`) |

Rules:

- the conversation log topic is append-only and append-by-broker-order — single-partition gives
  total order over messages from any number of producers; the broker-assigned `MessageId` is
  the canonical sequence identifier
- typed event variants on the conversation log are `UserPrompt`, `UserUpload`, `UserCancel`,
  and `InferenceResult`; schemas are registered via the Pulsar admin API at `infernix-demo`
  startup
- Pulsar producer-side deduplication (`enableProducerDeduplication = true`) is enabled on
  conversation, `inference.request.<mode>`, and `inference.result.<mode>` topics; named
  producers carry dedup sequence IDs derived from upstream `MessageId`s or
  `ClientIdempotencyKey`s so retry paths are idempotent at the broker level
- the compacted metadata topics are read by the demo backend with the compacted-reader API to
  drive the SPA's left-rail context list and draft restore; namespace-level compaction policy
  is reconciled on `cluster up`
- the demo backend's per-WS Pulsar **Reader** subscriptions on conversation and metadata
  topics give pod-failover-safe fan-out without sticky sessions; the per-context inference
  dispatcher uses a named **Failover** subscription so exactly one pod is the active dispatcher
  per context at a time
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
