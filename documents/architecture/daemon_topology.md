# Daemon Topology

**Status**: Authoritative source
**Referenced by**: [durable_context_design.md](durable_context_design.md), [demo_app_design.md](demo_app_design.md), [runtime_modes.md](runtime_modes.md), [overview.md](overview.md), [web_ui_architecture.md](web_ui_architecture.md), [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md), [../engineering/portability.md](../engineering/portability.md), [../engineering/k8s_storage.md](../engineering/k8s_storage.md), [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md), [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md), [../development/chaos_testing.md](../development/chaos_testing.md), [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md), [../tools/pulsar.md](../tools/pulsar.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md), [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md)

> **Purpose**: Define the supported three-role daemon model — stateless
> frontend, stateless coordinator, and one-per-node stateful engine —
> used by every durable-context application on every supported
> substrate, including HA replica policy, per-substrate placement,
> library footprint per role, and failure semantics.

## TL;DR

- Every durable-context application deploys against three daemon
  roles: **frontend** (per-app pod), **coordinator** (shared,
  stateless), and **engine** (shared, stateful, one-per-node).
- Frontend and coordinator are normal Kubernetes Deployments. They
  scale horizontally with replicas ≥ 2 by default, and they may run on
  any node. Pulsar named `Failover` subscriptions provide automatic
  leader election for coordinator work, so multiple replicas are an
  HA primitive, not a coordination problem.
- The engine is a Deployment with **required** pod anti-affinity, one
  engine per node. Multiple engines on the same node would mean
  redundant KV caches and redundant model-weight allocations with
  zero performance gain. One engine per node owns every local
  accelerator.
- A Linux node with multiple NVIDIA devices runs **one** engine pod
  that owns all local devices; the active substrate's `.dhall`
  decides whether different models load on different devices
  (multi-model serving) or the same model loads on multiple devices
  (throughput scaling).
- The three-role split applies symmetrically. Apple silicon runs the
  `Coordinator` role in cluster and the `Engine` role on host. Linux
  substrates run both roles as separate in-cluster Deployments.
- Production deployments (`demo_ui = false`) run only the engine
  Deployment.

## Current Status

The three-role contract is the supported shape. The chart ships
`chart/templates/deployment-{coordinator,engine,demo}.yaml`,
`clusterServiceEnabled` returns `False` on every substrate, and
`finalPhaseDeployments` waits on
`deployment/infernix-{coordinator,engine,demo}`. Apple silicon runs the
two roles as the in-cluster `Coordinator` and the on-host `Engine`; the
cluster-coordinator-to-host-engine batch bridge handles Apple-native
inference handoff. The coordinator's runtime Pulsar wiring (per-context
dispatcher Failover subscription, result-bridge Failover subscription,
model-bootstrap Failover subscription against `infernix-models`, and
WebSocket-originated event publication) is implemented. `Infernix.Runtime.KVCache`
backs the engine runtime and native worker harness with reducer/hash-backed
prefix verification decisions, and `Infernix.Runtime.Daemon` owns daemon-role
orchestration. Failover consumer names stay process-qualified under stable
subscription names via `Infernix.Runtime.Pulsar.Failover`. Unit coverage
proves runtime rebuild/reuse decisions; the integration suite validates
the coordinator/engine durable prompt flow, engine pod replacement, engine
node drain, exact broker counts, throughput, and production-shape
deployment.

## Roles and Responsibilities

### Frontend (`<appWorkload>`, e.g. `infernix-demo`)

The per-app pod. Owns the user-facing surface:

- WebSocket upgrade on `<wsPath>` plus JWT validation on handshake via
  `Infernix.Auth.Jwt`
- HTTP route handlers for `<authPath>` (OIDC) and `<objectsApiPath>`
  (presigned URL minting)
- SPA asset serving
- Per-WS Pulsar `Reader` subscriptions on the user's conversation,
  contexts, and drafts topics; forwards events as typed
  `WsServerMessage`s
- App-specific bootstrap (IdP realm wiring, first-run seeds)

The frontend is stateless and free of business rules. It applies
patches mechanically and translates between WS envelopes and Pulsar
topics. A future SPA-style application reuses the entire shared
library and writes only its renderer plus the WS envelope variants it
needs.

### Coordinator (`infernix-coordinator`)

The product-agnostic Pulsar coordinator. Owns three Failover
subscription types:

- **Single-flight dispatcher** via `Infernix.Dispatch.SingleFlight`
  with a Pulsar named `Failover` subscription per per-context
  conversation topic; folds the log to apply the dispatch rule;
  publishes typed inference requests
- **Optional batcher** that groups requests into
  `inference.batch.<mode>`; policy lives in coordinator config
  (latency budget, max batch size)
- **Result-bridge** via `Infernix.Bridge.Result` with a Pulsar named
  `Failover` subscription on `inference.result.<mode>`; writes
  `InferenceResult` events back to the originating per-context
  conversation topic with producer dedup keyed by
  `(userPromptMessageId, kind = InferenceResult)`
- **Model-bootstrap worker** via `Infernix.Bootstrap.Models` with a
  Pulsar named `Failover` subscription on
  `infernix/system/model.bootstrap.request`; consumes bootstrap
  requests, fetches the upstream URL from the active substrate
  `.dhall`, PUTs weights to `infernix-models/<modelId>/`, writes the
  `.ready` sentinel last, and publishes
  `model.bootstrap.ready.<modelId>`. **The coordinator is the only
  daemon role with outbound-internet egress** — used solely for
  upstream model downloads on first use.

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

### Engine (`infernix-engine`)

The product-agnostic inference executor. Owns:

- Consumer subscription on `inference.batch.<mode>` (post-batcher) or
  `inference.request.<mode>` (no batcher)
- Engine adapter process management (Python or native) per
  `python/adapters/` contract
- **Model weight cache** under `/model-cache/<modelId>/` (ephemeral
  `emptyDir` mount with hard `sizeLimit`); populated from the
  `infernix-models` MinIO bucket via the shared adapter helper
  (`python/adapters/common/model_cache.py`) on first use. Every
  engine, every model, goes through the same helper — no per-engine
  bytes-loading code. LRU eviction inside the cache keeps usage under
  `sizeLimit`.
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
| Engine | `Deployment` | ≤ number of engine-capable nodes | **`requiredDuringSchedulingIgnoredDuringExecution`** on its own label, `topologyKey: kubernetes.io/hostname` | `maxUnavailable: 1` | linux-gpu: `nvidia.com/gpu = engine.gpu.devicesPerNode`, `runtimeClassName: nvidia`, `nodeSelector: infernix.runtime/gpu: "true"`; linux-cpu: full node CPU up to pod limits; apple-silicon: no in-cluster pod | **no PVC**; single `emptyDir` volume `model-cache` mounted at `/model-cache` with `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}` (default `32Gi`), used as ephemeral staging for weights pulled from `infernix-models` |

**Engine one-per-node rule.** Two engines on the same node would
mean:

1. Two KV caches indexed by the same `(contextId, prefixHash)` space,
   competing for memory.
2. Two copies of every loaded model's weights in memory.
3. Two adapter processes contending for the same accelerator handles.

None of these costs translate to throughput gain on the supported
adapters. The required anti-affinity rule lets `engine.replicaCount`
function as a "how many engine nodes do we have" knob: if the
requested replica count exceeds available engine-capable nodes, the
excess pods remain `Pending` until new nodes appear or the count is
lowered.

**Multi-device nodes.** On a Linux node with multiple NVIDIA devices,
the single engine pod requests
`nvidia.com/gpu = engine.gpu.devicesPerNode` and the engine adapter
inside that pod owns every local device. The active substrate's
`.dhall` decides per-device model assignment:

- one engine, N devices, M ≤ N models loaded on M distinct devices
  (multi-model serving on the node)
- one engine, N devices, one model loaded on N devices (throughput
  scaling for one model on the node)

Both are configured at the engine adapter layer, not by deploying
more engine pods.

**Apple silicon symmetry.** On Apple substrates the engine role is
the on-host `infernix service` daemon (one process per host
machine), not a Kubernetes pod. The one-per-node rule is enforced
symmetrically via an exclusive `flock(2)` on
`./.data/runtime/engine.lock` acquired at daemon startup; a second
`infernix service` invocation on the same host exits non-zero with a
diagnostic naming the PID holding the lock. The Linux
engine pod acquires the same lock inside its `emptyDir` (no-op in
practice because pod anti-affinity already guarantees uniqueness,
but the contract is uniform across substrates).

**No daemon has a PVC on any substrate.** The engine pod's
`emptyDir` model cache is ephemeral per-pod storage capped by
`sizeLimit`; it disappears on pod restart and rebuilds from the
`infernix-models` MinIO bucket via the lazy bootstrap workflow. The
Apple on-host engine daemon's equivalent host-local cache lives
under `./.data/runtime/model-cache/` and is purgeable; it is host
state on the operator's machine, not durable cluster state.

## Per-Substrate Placement

| Substrate | `demo_ui` | Frontend pod | Coordinator pod | Engine placement |
|---|---|---|---|---|
| `apple-silicon` | `true` | `infernix-demo` in cluster (replicas ≥ 2) | `infernix-coordinator` in cluster (replicas ≥ 2) | `infernix service` engine process on host, one per host machine |
| `apple-silicon` | `false` | absent | absent | on host only |
| `linux-cpu` | `true` | `infernix-demo` in cluster (replicas >= 2) | `infernix-coordinator` in cluster (replicas >= 2) | `infernix-engine` in cluster, one per worker node; the supported local HA lane renders two workers and two engines |
| `linux-cpu` | `false` | absent | absent | `infernix-engine` in cluster, one per worker node |
| `linux-gpu` | `true` | `infernix-demo` in cluster | `infernix-coordinator` in cluster | `infernix-engine` in cluster, one per GPU-capable node, all local NVIDIA devices |
| `linux-gpu` | `false` | absent | absent | `infernix-engine` in cluster, one per GPU-capable node |

## Topic Flow

```
Browser
  └─[WsClientMessage]──> Frontend pod
                          └─[append]──> conversation topic
                                        (per-context, persistent)

Coordinator pod (Failover sub per conversation topic)
  └─[reads conversation]──> dispatcher rule (Infernix.Dispatch.SingleFlight)
  └─[publish, dedup by userPromptMessageId]──> inference.request.<mode>
  └─(optional) batcher subscription
  └─[publish, dedup by batchId]──> inference.batch.<mode>

Engine pod or host daemon (consumer sub on inference.batch.<mode>)
  └─[check MinIO infernix-models/<modelId>/.ready]
       ├─ present: load weights from /model-cache (populating from
       │           MinIO if not yet cached); run adapter
       └─ absent:
            └─[publish, dedup by modelId]──> model.bootstrap.request
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
| `Infernix.Objects.Layout` | ✓ | — | — |
| `Infernix.Objects.Presigned` | ✓ | — | — |
| `Infernix.Auth.Jwt` | ✓ | — | — |
| `Infernix.Runtime`, `.Cache`, `.Worker` | — | — | ✓ |
| `Infernix.Runtime.Daemon` role orchestration | — | ✓ | ✓ |
| `Infernix.Runtime.Pulsar` transport and runtime loops | — | ✓ | ✓ |
| `<appNamespace>.*` (e.g. `Infernix.Demo.*`) | ✓ | — | — |

## Batching Ownership

Batching policy lives in the coordinator, behind
`inference.batch.<mode>`. The coordinator reads from
`inference.request.<mode>`, groups by routing key (model id and any
batching-compatible request shape constraints), publishes batches to
`inference.batch.<mode>` with producer dedup keyed by `batchId`, and
the engine consumes batches one at a time.

The engine adapter's intra-engine continuous batching (e.g. vLLM,
TensorRT-LLM) is unchanged by this contract — it operates inside the
engine pod on whatever the batch topic delivers.

When the active deployment does not need broker-level batching, the
coordinator skips the batcher and the engine subscribes to
`inference.request.<mode>` directly. The topic + module surface is the
same in both cases; only the coordinator's wiring changes.

## Failure Semantics per Role

Recovery in every failure mode relies on three primitives that all
three roles share access to:

- **Pulsar named Failover subscriptions** on the dispatcher, the
  result-bridge, and the engine's batch consumer
- **Pulsar producer-side deduplication** on every topic the role
  writes, backed by broker-level dedup and namespace policies
- **Projection-layer dedup** in the reducer on `(contextId,
  clientIdempotencyKey)` for browser-driven retries

| Failure | What happens | What recovers |
|---|---|---|
| Frontend pod crash | WS connections drop | Client reconnects to any replica; new pod re-derives Readers from the JWT; state replays from Pulsar. Pending submits replay via `clientIdempotencyKey`; reducer dedup catches duplicates. The WS pod acks a client submit only after Pulsar confirms the publish, so "acked then crashed" implies "already on the log." |
| Coordinator pod crash | Failover subscription's active replica is unreachable | Pulsar promotes a surviving coordinator replica; unacked conversation events redelivered to the new active dispatcher; unacked inference results redelivered to the new active result-bridge; producer dedup on `inference.request.<mode>` and on the conversation topic prevents duplicate dispatch and duplicate writeback. |
| Engine pod crash | Active engine on that node is gone | Pulsar redelivers the unacked `inference.batch.<mode>` message to a surviving engine on another node. The receiving engine has a KV-cache miss on that request's `prefixHash` and rebuilds from the conversation log; producer dedup on `inference.result.<mode>` prevents a duplicate result if the original engine had partially published. |
| Engine node drain | All engine pods on that node go away | PDB blocks the drain until at least one other engine pod is available cluster-wide. Pulsar redelivery and KV-cache rebuild are the same as the per-pod crash case. |
| Pulsar broker / MinIO / IdP outage | Standard HA recovery (3-broker Pulsar, 4-replica MinIO, HA-deployed IdP) | Frontend caches JWKS with short TTL so brief IdP outages do not break existing sessions; the rest of the path uses Pulsar's own HA. |

## Apple Silicon Mapping

The Apple substrate runs the two-role split with the engine on host
and the coordinator in cluster.

- `infernix-coordinator` in cluster consumes
  `inference.request.apple-silicon`, runs the dispatch, result-bridge,
  and model-bootstrap work, and publishes to
  `inference.batch.apple-silicon.host`, the Apple host-native handoff
  topic.
- The on-host `infernix service` engine process consumes
  `inference.batch.apple-silicon.host`, pulls model weights from
  `infernix-models` via the shared adapter helper into a host-local
  cache under `./.data/runtime/model-cache/`, runs the Apple-native
  adapter, owns the in-memory KV cache, and publishes
  `inference.result.apple-silicon`. The one-per-node rule is enforced
  via an exclusive `flock(2)` on `./.data/runtime/engine.lock`
  acquired at daemon startup — the symmetrical equivalent of the
  Linux pod anti-affinity rule.
- The chart never deploys an in-cluster `infernix-engine` pod on
  apple-silicon. The one-per-node rule applies trivially to the host
  daemon — there is one host.
- The host-local model cache under `./.data/runtime/model-cache/`
  survives across cluster restarts on the operator's machine but is
  purgeable; it is not a Kubernetes PVC and is not durable cluster
  state.

The Apple lane is the canonical shape of the supported two-role split,
not a special case.

## Production Shape

When `demo_ui = false`:

- The frontend Deployment is absent (no SPA, no `<authPath>`, no
  `<wsPath>`, no `<objectsApiPath>`).
- The coordinator Deployment is absent (there are no per-context
  conversation topics to coordinate; production inference work
  arrives on `inference.request.<mode>` directly from external
  producers).
- The engine Deployment is the only daemon present. It subscribes to
  `inference.request.<mode>` (no batcher in the production path)
  and publishes to `inference.result.<mode>`.
- On apple-silicon production: the host daemon engine role is the
  only daemon present.

The supported one-per-node engine rule holds in the production shape
as well.

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
- a production-shape test that deploys `demo_ui = false` and asserts
  only `infernix-engine` Deployment is present via
  `infernix kubectl -n platform get deployments`
- a scheduling negative-test that demonstrates k8s rejects a second
  engine pod on the same node when the required anti-affinity rule
  is in force

`infernix lint docs` enforces the metadata block and cross-link
resolution of this doc.

## Cross-References

- [durable_context_design.md](durable_context_design.md) — product-agnostic durable-context primitives
- [demo_app_design.md](demo_app_design.md) — demo-specific bindings
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
