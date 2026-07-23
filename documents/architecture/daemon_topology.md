# Daemon Topology

**Status**: Authoritative source
**Referenced by**: [durable_context_design.md](durable_context_design.md), [demo_app_design.md](demo_app_design.md), [runtime_modes.md](runtime_modes.md), [overview.md](overview.md), [web_ui_architecture.md](web_ui_architecture.md), [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md), [../engineering/portability.md](../engineering/portability.md), [../engineering/k8s_storage.md](../engineering/k8s_storage.md), [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md), [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md), [../development/chaos_testing.md](../development/chaos_testing.md), [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md), [../tools/pulsar.md](../tools/pulsar.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md), [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md)

> **Purpose**: Define the supported three-role daemon model — stateless
> frontend, stateless coordinator, and pooled stateful engine execution —
> used by every durable-context application on every supported
> substrate, including HA replica policy, per-substrate placement,
> library footprint per role, and failure semantics.

## TL;DR

- Every durable-context application deploys against three daemon roles:
  **frontend** — the **Webapp** role (`infernix service --role webapp`; `DaemonRole = Webapp`, id
  `webapp`; "Frontend" is the informal name used in the tables and diagram below) — plus
  **coordinator** (shared, stateless) and **engine** (shared, stateful execution members).
- Frontend and coordinator are normal Kubernetes Deployments. The frontend is
  demo-gated; the coordinator remains production infrastructure because it owns
  request-topic fan-in, batching, model routing, result bridging, and model
  bootstrap.
- Engine execution is organized into typed **engine pools**. Coordinators publish
  to derived pool/model topics; eligible engine members subscribe with Pulsar
  `Shared` subscriptions so broker-native backpressure distributes work.
- Linux engine members are Kubernetes workloads constrained by Kubernetes
  placement rules. Apple engine members are host daemons with stable host ids.
  Kubernetes pod names are never durable routing identities.
- Pinned routes use derived per-member topics plus `Exclusive` subscriptions.
  Normal scalable pools do not use `Failover` for Apple work fanout.
- Production deployments (`demo_ui = false`) omit the frontend and demo-only
  surfaces, not the coordinator.

## Current Status

The three-role contract is the supported shape. The implementation uses
`chart/templates/deployment-{coordinator,engine,demo}.yaml`, keeps `clusterServiceEnabled` false on
every substrate, and has code-side support for the engine-pool model defined in
[engine_pool_routing.md](engine_pool_routing.md). Coordinator handoff derives pool/model topics
from validated `enginePools` / `engineMembers` metadata; the demo frontend runs as the `Webapp`
role through `infernix service --role webapp`. Apple silicon runs the `Coordinator` role in
cluster and engine members as on-host daemons; Linux substrates run coordinator and engine members
as separate in-cluster workloads. The coordinator's runtime Pulsar
wiring (per-context
dispatcher Failover subscription, result-bridge Failover subscription,
model-bootstrap Failover subscription against `infernix-models`, and
WebSocket-originated event publication) is implemented. `Infernix.Runtime.KVCache`
backs the engine runtime and native worker harness with reducer/hash-backed
prefix verification decisions, and `Infernix.Runtime.Daemon` owns daemon-role
orchestration. Failover consumer names stay process-qualified under stable
subscription names via `Infernix.Runtime.Pulsar.Failover`. Unit coverage
proves runtime rebuild/reuse decisions; the integration suite validates the current
coordinator/engine durable prompt flow, engine pod replacement, engine node drain, exact broker
counts, throughput, and production-shape deployment. The current Apple integration pass proves one
pinned Apple host member route with broker-enforced `Exclusive` duplicate rejection, same-machine
Apple host-member coexistence on a real `Shared` subscription, and Apple production
`demo_ui = false` route/publication assertions, and the single-host logical `Shared`
backlog/backpressure harness using real Pulsar WebSocket consumers. Current Linux CPU integration
proves Kubernetes-observed pool placement and shared-subscription backlog/backpressure. Wave J
still owns Linux GPU/CUDA cohort validation. Physical Apple multi-host membership is
hardware-deferred proof while no second Apple host is available.

## Roles and Responsibilities

### Webapp (`<appWorkload>`, e.g. `infernix-demo`)

The per-app pod. Owns the user-facing surface:

- WebSocket upgrade on `<wsPath>` plus JWT validation on handshake via
  `Infernix.Auth.Jwt`
- HTTP route handlers for `<authPath>` (OIDC) and `<objectsApiPath>`
  (webapp-mediated artifact upload, download, and listing). The frontend
  is the single mediator for browser object access: it derives every
  object key server-side from the verified `sub`, authorizes it with
  `Infernix.Objects.Layout.pathBelongsToUser`, and performs the MinIO
  read/write itself over the cluster-internal endpoint, so the browser
  never holds a MinIO credential or presigned MinIO URL (see
  [object_access_doctrine.md](object_access_doctrine.md) and
  [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md)). **Current
  Status:** the present build proxies browser object bytes through the
  Webapp role; the `/minio/s3` gateway route and browser-direct presigned
  URL grants are removed
- SPA asset serving
- Per-WS Pulsar `Reader` subscriptions on the user's conversation,
  contexts, and drafts topics; forwards events as typed
  `WsServerMessage`s
- App-specific bootstrap (IdP realm wiring, first-run seeds)

The Webapp role is stateless and free of business rules. It applies
patches mechanically and translates between WS envelopes and Pulsar
topics. A future SPA-style application reuses the entire shared
library and writes only its renderer plus the WS envelope variants it
needs.

### Coordinator (`infernix-coordinator`)

The product-agnostic Pulsar coordinator. Owns three `Failover` subscriptions — the single-flight
dispatcher, the result-bridge, and the model-cache staging worker — plus a `Shared` batcher /
pool-router consumer:

- **Single-flight dispatcher** via `Infernix.Dispatch.SingleFlight`
  with a Pulsar named `Failover` subscription per per-context
  conversation topic; folds the log to apply the dispatch rule;
  publishes typed inference requests
- **Batcher and pool router** that groups requests into derived engine-pool topics. The
  implementation derives pool/model topics from the validated substrate graph, and Pulsar
  distributes within each pool through consumer permits and receiver backlog. Policy lives in
  coordinator config
  (latency budget, max batch size, model-to-pool routing)
- **Result-bridge** via `Infernix.Bridge.Result` with a Pulsar named
  `Failover` subscription on `inference.result.<mode>`; writes
  `InferenceResult` events back to the originating per-context
  conversation topic with producer dedup keyed by
  `(userPromptMessageId, kind = InferenceResult)`
- **Model-cache staging worker** via `Infernix.Bootstrap.Models`. On
  startup the coordinator eagerly stages every model listed in the
  mounted `infernix.dhall`, and a `warm-model-cache` cluster-up barrier
  blocks until all are `.ready`; a fallback Pulsar named `Failover`
  subscription on `infernix/system/model.bootstrap.request` services any
  unstaged model. Per model it fetches the upstream URL from the mounted
  `infernix.dhall`, PUTs weights to `infernix-models/<modelId>/`, writes
  the `.ready` sentinel last, and publishes
  `model.bootstrap.ready.<modelId>`. **The coordinator is the only
  daemon role with outbound-internet egress** — used solely for
  upstream model downloads at startup staging.

The coordinator never imports any application namespace; it never
runs an inference engine; it owns no GPU or Metal resources; **it
has no PVC** (Pulsar subscription cursors are broker-side durable).
Multiple replicas are an HA primitive — Pulsar Failover guarantees
exactly one active subscriber per topic at a time, so multiple
coordinator pods do not race.
Each Failover subscription keeps a stable subscription name as the
ownership key and uses a process-qualified consumer name for the member
identity, so replica promotion is observable without changing the
broker-side ownership boundary.

### Engine (`infernix-engine`, pool members, and pinned members)

The product-agnostic inference executor. Owns:

- Running the **real per-family engine** for the selected binding —
  the Python adapter transform over a prebuilt host wheel, or a real
  native runner binary resolved from `./.data/engines/<adapterId>/`
  with a Linux image-owned `/opt/infernix/engines/<adapterId>/`
  fallback — and publishing a per-family real result: inline text for
  the LLM and speech families, and a typed `infernix-demo-objects`
  object reference for each artifact result family (source separation,
  audio-to-MIDI, music transcription, image, video, audio generation,
  and OMR)
- Consumer subscriptions on derived engine-pool topics. Normal scalable pools use `Shared`
  subscriptions and broker-native backpressure; pinned per-member topics use `Exclusive`.
- Engine adapter process management (Python or native) per
  `python/adapters/` and `src/Infernix/Runtime/Worker.hs` contracts.
  Worker requests carry the selected model metadata plus model-cache/MinIO wiring decoded from
  mounted `ClusterConfig` and secret-file-backed `SecretsConfig`
  values. Python adapter entrypoints call `adapters.model_cache.configure()` before loading
  weights or reading/writing object storage; native artifact runners receive only non-secret
  cache/bucket hints plus an optional output directory, and the Haskell worker owns the
  credentialed upload when they return a local artifact-file marker.
- **Model weight cache** under `/model-cache/<modelId>/` (ephemeral
  `emptyDir` mount with hard `sizeLimit`); populated from the
  `infernix-models` MinIO bucket via the shared adapter helper
  (`python/adapters/model_cache.py`) on first use. Every
  engine, every model, goes through the same helper — no per-engine
  bytes-loading code. LRU eviction inside the cache keeps usage under
  `sizeLimit`. This bounds only the on-disk weight footprint; it is not
  a model-memory bound. Resident memory during model execution is governed separately by typed
  runtime admission (see **Failure Semantics per Role** and the reopened
  [Phase 4 Sprint 4.27](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)).
- The node's **KV cache, in-memory only**, scoped to
  `(contextId, prefixHash)`
- `prefixHash` verification before KV-cache reuse; rebuild from
  conversation log on miss
- For binary inference outputs (images, audio, video), PUT directly
  to `infernix-demo-objects` at the appropriate per-user prefix; the
  result message carries an `ObjectRef`, never inline bytes or a
  host-filesystem path. Text outputs always ride inline.
- Result publication on `inference.result.<mode>` with producer dedup
  keyed by `userPromptMessageId`

The engine loads only the engine-side surface of the shared library
(`Infernix.Conversation.Reducer` and `.Hash` for cache-consistency
verification) plus the engine runtime modules. It never imports any
application namespace, never imports `Infernix.Objects.Presigned`,
never imports `Infernix.Auth.Jwt`, never imports
`Infernix.Dispatch.SingleFlight`, never imports
`Infernix.Bridge.Result`, never imports `Infernix.Bootstrap.Models`,
and never imports a WebSocket module. **The engine has no PVC** —
the only on-disk state is the ephemeral `emptyDir` model cache.
The Haskell style gate enforces this import boundary for
`Infernix.Runtime`, `Infernix.Runtime.Cache`,
`Infernix.Runtime.KVCache`, and
`Infernix.Runtime.Worker`. `Infernix.Runtime.Daemon` owns daemon role
orchestration and may wire coordinator and engine loops; `Infernix.Runtime.Pulsar`
owns the shared Pulsar transport helpers and loop implementations.

The style gate also enforces the Phase 7 shared-library boundary for the
conversation primitives, dispatcher helpers, result bridge helper, and
bootstrap helper so those modules cannot import demo, runtime, auth,
object-presign, or WebSocket modules.

## HA and Node-Policy Contract

| Role | Deployment kind | Default replicas | Anti-affinity | PodDisruptionBudget | Node resource shape | Persistent state |
|---|---|---|---|---|---|---|
| Frontend | `Deployment` | ≥ 2 | `preferredDuringSchedulingIgnoredDuringExecution` on its own label, `topologyKey: kubernetes.io/hostname` | `maxUnavailable: 1` | no special resources | **no PVC** |
| Coordinator | `Deployment` | ≥ 2 | `preferredDuringSchedulingIgnoredDuringExecution` on its own label, `topologyKey: kubernetes.io/hostname` | `maxUnavailable: 1` | no GPU | **no PVC** (Pulsar subscription cursors are broker-side durable) |
| Engine | Linux: `Deployment`; Apple: host daemon member | Linux: ≤ number of engine-capable nodes per deployment; Apple: one member per stable host id | Linux: **`requiredDuringSchedulingIgnoredDuringExecution`** on its own label, `topologyKey: kubernetes.io/hostname`; Apple: host-id uniqueness plus pinned-topic `Exclusive` ownership when exact-host routing is used | Linux: `maxUnavailable: 1`; Apple: host process supervised outside Kubernetes | linux-cpu: explicit `engine.resources` CPU/memory requests and limits (`2Gi` request / `4Gi` limit by default, `768Mi` request / `3584Mi` limit in the Apple-hosted `linux-cpu` local validation profile), and runtime memory admission uses the active engine pod limit; linux-gpu generated lifecycle values use a `4Gi` request / `16Gi` limit plus `nvidia.com/gpu: 1`, `runtimeClassName: nvidia`, and `infernix.runtime/gpu: "true"` node selection so the routed diffusers video row can load without cgroup OOM, while runtime model admission uses GPU VRAM; repo-owned single-GPU values start heavyweight deployments at zero replicas and validation scales one at a time; apple-silicon: no in-cluster engine pod, so every active model runs on the on-host `infernix service` daemon and runtime admission uses unified host RAM after the Colima pledge and reserve. Over-budget requests return typed `ModelMemoryLimitExceeded`; oversized catalog entries must not invalidate the whole daemon. | **no PVC**; Linux uses a single `emptyDir` volume `model-cache` mounted at `/model-cache` with `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}` (default `64Gi`), and Apple uses a derived host-local model cache; both are rebuilt from `infernix-models` |

**Linux engine placement rule.** Two engines from the same Linux engine Deployment on one node would
mean:

1. Two KV caches indexed by the same `(contextId, prefixHash)` space,
   competing for memory.
2. Two copies of every loaded model's weights in memory.
3. Two adapter processes contending for the same accelerator handles.

None of these costs translate to throughput gain on the supported
adapters. The required Linux anti-affinity rule lets `engine.replicaCount`
function as a "how many eligible Linux nodes do we have" knob: if the
requested replica count exceeds available engine-capable nodes, the
excess pods remain `Pending` until new nodes appear or the count is
lowered.

**Linux GPU per-engine images.** Framework-specific Linux GPU pools may still render as
`infernix-engine-<engine>` Deployments whose image contains exactly one isolated framework venv.
That split is an image and dependency-isolation boundary; pool membership and model routing are
derived from the typed engine-pool graph.

**Apple silicon symmetry.** On Apple substrates engine members are on-host `infernix service`
daemons with stable host ids, not Kubernetes pods. Normal Apple model pools use `Shared`
subscriptions across distinct host ids so broker-native permits distribute work. Broker permits
remain a concurrency/backpressure mechanism; memory capacity is checked by the shared runtime
admission policy immediately before launch and returns typed `ModelMemoryLimitExceeded` when the
model does not fit. Exact-host routes use derived per-host topics with `Exclusive`.

**No daemon has a PVC on any substrate.** The engine pod's
`emptyDir` model cache is ephemeral per-pod storage capped by
`sizeLimit`; it disappears on pod restart and rebuilds from the
eagerly pre-staged `infernix-models` MinIO bucket. The
Apple on-host engine daemon's equivalent host-local cache lives
under `./.data/runtime/model-cache/` and is purgeable; it is host
state on the operator's machine, not durable cluster state.

## Per-Substrate Placement

| Substrate | `demo_ui` | Frontend pod | Coordinator pod | Engine placement |
|---|---|---|---|---|
| `apple-silicon` | `true` | `infernix-demo` in cluster (single replica — HA-sized-down for Colima) | `infernix-coordinator` in cluster (single replica — HA-sized-down for Colima) | Apple host-daemon pool members selected by host id |
| `apple-silicon` | `false` | absent | `infernix-coordinator` in cluster | Apple host-daemon pool members selected by host id |
| `linux-cpu` | `true` | `infernix-demo` in cluster (replicas >= 2) | `infernix-coordinator` in cluster (replicas >= 2) | Kubernetes engine pools; the supported local HA lane renders two workers and two engines |
| `linux-cpu` | `false` | absent | `infernix-coordinator` in cluster | Kubernetes engine pools |
| `linux-gpu` | `true` | `infernix-demo` in cluster | `infernix-coordinator` in cluster | Kubernetes GPU engine pools, including framework-specific Deployments when configured |
| `linux-gpu` | `false` | absent | `infernix-coordinator` in cluster | Kubernetes GPU engine pools, including framework-specific Deployments when configured |

## Topic Flow

```
Browser
  └─[WsClientMessage]──> Frontend pod
                          └─[append]──> conversation topic
                                        (per-context, persistent)

Coordinator pod (Failover sub per conversation topic)
  └─[reads conversation]──> dispatcher rule (Infernix.Dispatch.SingleFlight)
  └─[publish, dedup by userPromptMessageId]──> inference.request.<mode>
  └─batcher / pool router
  └─[publish, dedup by batchId]──> inference.batch.<mode>.pool.<poolId>.model.<modelId>
                                      or inference.batch.<mode>.member.<memberId>.model.<modelId>

Engine pod or host daemon (consumer sub on assigned pool/member topic)
  └─[check MinIO infernix-models/<modelId>/.ready]
       ├─ present: load weights from /model-cache (populating from
       │           MinIO if not yet cached); run adapter
       └─ absent:
            └─[publish, key modelId, dedup by modelId@requestedAt]──> model.bootstrap.request
            └─[await]──> model.bootstrap.ready.<modelId>
            └─ load weights via the shared adapter helper, run adapter
  └─[publish, dedup by userPromptMessageId]──> inference.result.<mode>
  └─[for binary outputs]──> PUT to infernix-demo-objects under the
                            per-user prefix; result payload carries
                            ObjectRef

Coordinator pod (Failover sub on model.bootstrap.request)
  └─ fetch upstream URL from active substrate .dhall
  └─ HTTP download to memory
  └─ PUT to infernix-models/<modelId>/<filename>
  └─ PUT infernix-models/<modelId>/.ready  (sentinel, written LAST)
  └─[publish]──> model.bootstrap.ready.<modelId>

Coordinator pod (Failover sub on inference.result.<mode>)
  └─[writeback via Infernix.Bridge.Result]──> conversation topic

Frontend pod (Pulsar Reader sub on conversation topic)
  └─[WsServerMessage]──> Browser
```

Subscription primitives used at each hop:

- **Reader** (frontend): cursor-based, no shared subscription state
  across pods; any pod hosts any WS session.
- **Failover** (coordinator): exactly one active subscriber per topic
  at a time; Pulsar promotes a surviving replica on crash and
  redelivers unacked messages.
- **Shared** (engine pools): Pulsar distributes pool work to eligible members according to permits
  and receiver backlog. Messages are acknowledged only after materialization, inference, and result
  publication succeed.
- **Exclusive** (pinned engine member): exact-member routes reject duplicate consumers at the broker
  boundary.
- **Producer-side dedup** with broker-level
  `brokerDeduplicationEnabled = true` plus namespace dedup policies on
  the conversation, context, draft, inference-request,
  inference-batch, and inference-result topics with named producers and
  dedup sequence IDs derived from upstream `MessageId`s. Frontend
  mutation retries use mutation-scoped one-message producers with the
  WebSocket `initialSequenceId` baseline set from the mutation key.

## Library Footprint per Role

The authoritative ownership wall is codified in
[../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md);
this table lists which shared modules each role loads at runtime.

| Module | Frontend | Coordinator | Engine |
|---|:---:|:---:|:---:|
| `Infernix.Conversation.Event` | ✓ | ✓ | ✓ |
| `Infernix.Conversation.Reducer` | ✓ | ✓ | ✓ |
| `Infernix.Conversation.Idempotency` | ✓ | ✓ | — |
| `Infernix.Conversation.Hash` | — | ✓ | ✓ |
| `Infernix.Conversation.Topic` | ✓ | ✓ | — |
| `Infernix.Topic.Metadata` | ✓ | ✓ | — |
| `Infernix.Topic.Drafts` | ✓ | ✓ | — |
| `Infernix.Dispatch.SingleFlight` | — | ✓ | — |
| `Infernix.Bridge.Result` | — | ✓ | — |
| `Infernix.Bootstrap.Models` | — | ✓ | — |
| `Infernix.Objects.Layout` | ✓ | — | ✓ |
| `Infernix.Objects.Presigned` | ✓ | — | — |
| `Infernix.Auth.Jwt` | ✓ | — | — |
| `Infernix.Runtime`, `.Cache`, `.Worker` | — | — | ✓ |
| `Infernix.Runtime.Daemon` role orchestration | — | ✓ | ✓ |
| `Infernix.Runtime.Pulsar` transport and runtime loops | — | ✓ | ✓ |
| `<appNamespace>.*` (e.g. `Infernix.Demo.*`) | ✓ | — | — |

## Batching and Routing Ownership

Batching and routing policy live in the coordinator, behind the validated engine-pool graph. The
coordinator reads from `inference.request.<mode>`, groups by routing key (model id, selected pool,
and any batching-compatible request shape constraints), publishes batches to derived pool/model
topics with producer dedup keyed by `batchId`, and eligible engine members consume according to
their pool assignment.

The engine adapter's intra-engine continuous batching (e.g. vLLM,
TensorRT-LLM) is unchanged by this contract — it operates inside the
engine pod on whatever the batch topic delivers.

When a deployment does not need broker-level batching, the coordinator still owns the routing
decision and publishes one request per batch message. Engines do not bypass the validated pool graph.

## Failure Semantics per Role

Recovery in every failure mode relies on three primitives that all
three roles share access to:

- **Pulsar named Failover subscriptions** on coordinator-owned dispatcher and result-bridge work,
  plus `Shared` or `Exclusive` subscriptions on engine-pool work topics according to the validated
  route type
- **Pulsar producer-side deduplication** on every topic the role
  writes, backed by broker-level dedup and namespace policies
- **Projection-layer dedup** in the reducer on `(contextId,
  clientIdempotencyKey)` for browser-driven retries

Per-role readiness gating and failure recovery follow the managed-state-transition doctrine: every
readiness wait returns typed evidence for the state it gates rather than a bare boolean, and
[Managed State Transitions](managed_state_transitions.md) is the canonical home for that rule.

| Failure | What happens | What recovers |
|---|---|---|
| Frontend pod crash | WS connections drop | Client reconnects to any replica; new pod re-derives Readers from the JWT; state replays from Pulsar. Pending submits replay via `clientIdempotencyKey`; reducer dedup catches duplicates. The WS pod acks a client submit only after Pulsar confirms the publish, so "acked then crashed" implies "already on the log." |
| Coordinator pod crash | Failover subscription's active replica is unreachable | Pulsar promotes a surviving coordinator replica; unacked conversation events redelivered to the new active dispatcher; unacked inference results redelivered to the new active result-bridge; producer dedup on `inference.request.<mode>` and on the conversation topic prevents duplicate dispatch and duplicate writeback. |
| Engine member crash | Active engine member disappears | Pulsar redelivers the unacked pool-topic message to another eligible member when the route is a `Shared` pool. The receiving engine has a KV-cache miss on that request's `prefixHash` and rebuilds from the conversation log; producer dedup on `inference.result.<mode>` prevents a duplicate result if the original engine had partially published. |
| Engine node drain | Engine members on that node go away | Kubernetes placement and PDBs protect Linux pools; Apple host daemons stop granting permits or unsubscribe while draining. Pulsar redelivery and KV-cache rebuild are the same as the member-crash case for shared pools. A node a test harness drained is tracked as a `ClusterMutating` position and uncordoned on the next `cluster up` (Planned; see [Managed State Transitions](managed_state_transitions.md)). |
| Engine model-memory admission failure | The requested model's `modelRamFootprintMib` exceeds the active resource budget: Apple unified host RAM, Linux CPU engine pod RAM, or Linux GPU VRAM | The daemon returns a per-request `status=failed` result with typed `InferenceError.ModelMemoryLimitExceeded`, including `requiredMib` and `availableMib`. The engine subprocess is not launched, the daemon remains up, and smaller configured models continue to run. This is owned by reopened [Phase 4 Sprint 4.27](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md), [Phase 5 Sprint 5.11](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md), and [Phase 6 Sprint 6.38](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md). |
| Pulsar broker / MinIO / IdP outage | Standard HA recovery (3-broker Pulsar, 4-replica MinIO, HA-deployed IdP) | Frontend caches JWKS with short TTL so brief IdP outages do not break existing sessions; the rest of the path uses Pulsar's own HA. |

## Apple Silicon Mapping

The Apple substrate runs the split with the coordinator in cluster and engine members on hosts.

- `infernix-coordinator` in cluster consumes `inference.request.apple-silicon`, runs the dispatch,
  result-bridge, and model-bootstrap work, and publishes to derived Apple pool/model topics.
- Each on-host `infernix service --role engine` process starts with a stable Apple host id, derives
  the model topics it is responsible for from the typed engine-pool assignment, pulls model weights
  from `infernix-models` via the shared adapter helper into a host-local cache under
  `./.data/runtime/model-cache/`, runs the Apple-native adapter, owns the in-memory KV cache, and
  publishes `inference.result.apple-silicon`.
- Normal Apple pools use `Shared` across distinct host ids so Pulsar broker backpressure assigns
  work to hosts with consumer-permit availability. Receiver-queue headroom is separate from memory
  capacity; the daemon checks the active memory budget immediately before launching a model.
  Pinned Apple routes use per-host derived topics and `Exclusive`.
- The chart never deploys an in-cluster `infernix-engine` pod on `apple-silicon`; Apple engine
  membership is host-daemon membership.
- The host-local model cache under `./.data/runtime/model-cache/`
  survives across cluster restarts on the operator's machine but is
  purgeable; it is not a Kubernetes PVC and is not durable cluster
  state.
- The Apple host-worker reaches the cluster **data plane directly on loopback**, bypassing the
  Keycloak-gated browser edge: MinIO over NodePort `30011` and the Pulsar proxy over NodePort `30080`,
  both bound `listenAddress: 127.0.0.1` by the Kind config. This path is trust-boundary-internal and
  un-gated; the admin `SecurityPolicy` on the browser edge (gateway NodePort `30090`) never touches it.
  See [access_control_doctrine.md](access_control_doctrine.md).

The Apple lane is the canonical shape of the supported three-role split
(frontend + coordinator in cluster, engine as an on-host daemon), not a
special case.

### Engine Memory Admission

The daemon enforces model-memory admission at execution time using a substrate-specific
`InferenceMemoryBudget` and a shared pure admission function. The policy does not make the whole
generated config invalid when one catalog entry is too large; it rejects only the request for that
model, so smaller configured models keep serving.

The active budget is a typed value, not an integer sentinel. `EnforcedMemoryBudget` carries the
resource, source, and `availableMib`; `0 MiB` is still enforced. `UnenforcedMemoryBudget` is an
explicit constructor used only when there is intentionally no comparable limit. This replaces the
old defensive hardcoded Apple floor and prevents non-positive computed budgets from disabling the
guard.

Budget sources are:

- `apple-silicon`: unified host RAM, computed as physical memory (`sysctl -n hw.memsize`) minus the
  read-only Colima pledge and host reserve
- `linux-cpu`: the Kubernetes engine pod memory limit for the active workload
- `linux-gpu`: selected GPU VRAM, because supported GPU model allocations live in VRAM

Before launching the engine subprocess or worker, the daemon compares
`ModelDescriptor.modelRamFootprintMib` with the enforced budget. If the footprint is larger, it
publishes a `status=failed` `InferenceResult` whose payload is
`InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }`. The
failure payload is a closed typed error, not successful inline output and not a parsed string.

This pre-launch admission proves a request *fits*, but the reopened memory-safety-by-construction
target additionally bounds the admitted request's *actual* resident memory: admission mints a
`MemoryGrant` that the capped-engine kernel requires (the raw engine spawn is unexported) and OS-bounds
to its `MemoryCeiling` — on `apple-silicon` a physical-footprint watchdog plus process-group kill, on
`linux-cpu`/`linux-gpu` the pod cgroup / VRAM limit — so a ceiling breach is the same clean typed
`status=failed` rather than a host OOM. The budget becomes enforcer-typed
(`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit`) over a checked
`HostMemoryPartition`. Canonical home: [bounded_inference_memory.md](bounded_inference_memory.md).

## Production Shape

When `demo_ui = false`:

- The frontend Deployment is absent (no SPA, no `<authPath>`, no `<wsPath>`, no
  `<objectsApiPath>`).
- Keycloak and demo-only routes are absent.
- The coordinator Deployment remains present and owns production request-topic fan-in,
  model-to-pool routing, batching, result bridging, and model bootstrap.
- Engine pools remain present for the active substrate. Linux pools are Kubernetes workloads; Apple
  pools are host daemon members.

The supported engine-pool placement contract holds in the production shape
as well: Linux uses Kubernetes placement rules, and Apple uses stable host ids plus pool
assignments.

## Validation

The three-role contract is validated by:

- `infernix lint chart` against the role-specific Deployment
  templates and PodDisruptionBudgets
- `infernix test integration` for the dispatcher → engine → result-bridge
  writeback path
- `infernix test integration` chaos tests for frontend pod replacement,
  coordinator pod replacement, engine pod replacement, engine-node drain,
  bootstrap deduplication, and engine anti-affinity (defined in
  [../development/chaos_testing.md](../development/chaos_testing.md))
- a production-shape test that deploys `demo_ui = false` and asserts the coordinator plus engine-pool
  workloads are present while demo-only workloads and routes are absent
- a scheduling negative-test that demonstrates k8s rejects a second
  engine pod on the same node when the required anti-affinity rule
  is in force

`infernix lint docs` enforces the metadata block and cross-link
resolution of this doc.

## Cross-References

- [durable_context_design.md](durable_context_design.md) — product-agnostic durable-context primitives
- [demo_app_design.md](demo_app_design.md) — demo-specific bindings
- [object_access_doctrine.md](object_access_doctrine.md) — frontend as the single mediator for browser artifact I/O
- [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md) — per-user `sub`-derived isolation at one server-side boundary
- [runtime_modes.md](runtime_modes.md) — control-plane execution contexts and service placement
- [overview.md](overview.md) — platform topology
- [web_ui_architecture.md](web_ui_architecture.md) — PureScript topology and image layout
- [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md) — module ownership boundary (authoritative)
- [../engineering/portability.md](../engineering/portability.md) — per-substrate executor placement
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md) — manual-storage doctrine and PVC ownership
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md) — operator-facing pod inventory
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md) — Apple host workflow
- [../development/chaos_testing.md](../development/chaos_testing.md) — per-role chaos cases
- [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md) — validation surface
- [../tools/pulsar.md](../tools/pulsar.md) — Pulsar topic contract
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md) — phase plan for the supported three-role pod split
- [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md) — authoritative component inventory
- [Managed State Transitions](managed_state_transitions.md) — typed transitions and readiness evidence for every system state
