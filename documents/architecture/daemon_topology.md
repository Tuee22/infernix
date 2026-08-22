# Daemon Topology

**Status**: Authoritative source
**Referenced by**: [durable_context_design.md](durable_context_design.md), [demo_app_design.md](demo_app_design.md), [runtime_modes.md](runtime_modes.md), [overview.md](overview.md), [web_ui_architecture.md](web_ui_architecture.md), [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md), [../engineering/portability.md](../engineering/portability.md), [../engineering/k8s_storage.md](../engineering/k8s_storage.md), [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md), [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md), [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md), [../tools/pulsar.md](../tools/pulsar.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md), [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md)

> **Purpose**: Define the supported three-role daemon model — stateless
> frontend, stateless coordinator, and pooled stateful engine execution —
> used by every durable-context application on every supported
> substrate, including fleet topology and member identity, delivery
> semantics, per-substrate placement, library footprint per role, and
> failure semantics.

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

## Compiled Startup Contract

Service startup compiles the mounted runtime config into opaque placements and `CompiledDaemon`
capabilities. Coordinators route through that compiled graph; engine members additionally refine it
against live host and cgroup observations and launch only `ExecutableModel` values. An engine member
that cannot verify its declared enforcer never becomes ready.

The three-role contract is the supported shape. It uses
`chart/templates/deployment-{coordinator,engine,demo}.yaml`, keeps `clusterServiceEnabled` false on
every substrate, and implements the engine-pool model defined in
[engine_pool_routing.md](engine_pool_routing.md). Coordinator handoff derives pool and model topics
from compiled placements and matching daemon capabilities rather than from raw routing metadata; the
demo frontend runs as the `Webapp` role through `infernix service --role webapp`. Apple silicon runs
the `Coordinator` role in cluster with engine members as on-host daemons; Linux substrates run
coordinator and engine members as separate in-cluster workloads.

The coordinator's Pulsar wiring is the per-context dispatcher Failover subscription, the
result-bridge Failover subscription, the model-bootstrap Failover subscription against
`infernix-models`, and WebSocket-originated event publication. `Infernix.Runtime.KVCache` backs the
engine runtime and native worker harness with reducer and hash-backed prefix-verification decisions,
and `Infernix.Runtime.Daemon` owns daemon-role orchestration. Failover consumer names stay
process-qualified under stable subscription names via `Infernix.Runtime.Pulsar.Failover`.

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
  [tenant_isolation_doctrine.md](tenant_isolation_doctrine.md)). The
  `/minio/s3` gateway route and browser-direct presigned URL grants are
  outside the supported surface
- SPA asset serving
- Per-WS Pulsar `Reader` subscriptions on the user's conversation,
  contexts, and drafts topics; forwards events as typed
  `WsServerMessage`s
- App-specific bootstrap (IdP realm wiring, first-run seeds)

The Webapp role is stateless and free of business rules. It applies
patches mechanically and translates between WS envelopes and Pulsar
topics. Any additional SPA-style application reuses the entire shared
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
Pulsar Failover guarantees exactly one active subscriber per topic at a
time under a stable broker-side ownership key. The supported topology
runs one coordinator process per machine; `Failover` is broker
coordination, not standby-replica availability. A process-qualified
consumer name distinguishes successive or fleet consumers without
changing that ownership boundary.

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
  weights or reading/writing object storage; direct native artifact targets receive only non-secret
  cache/bucket hints plus an invocation-owned output directory. The bounded Haskell kernel
  descriptor-validates the single expected regular output and the worker owns the credentialed
  upload.
- **Model weight cache** under `/model-cache/<modelId>/` (ephemeral
  `emptyDir` mount with hard `sizeLimit`); populated from the
  `infernix-models` MinIO bucket via the shared adapter helper
  (`python/adapters/model_cache.py`) on first use. Every
  engine, every model, goes through the same helper — no per-engine
  bytes-loading code. LRU eviction inside the cache keeps usage under
  `sizeLimit`. This bounds only the on-disk weight footprint; it is not
  a model-memory bound. Resident memory during model execution is governed separately by typed
  runtime admission (see **Failure Semantics per Role** and
  [bounded_inference_memory.md](bounded_inference_memory.md)).
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

The style gate also enforces the shared-library boundary for the
conversation primitives, dispatcher helpers, result bridge helper, and
bootstrap helper so those modules cannot import demo, runtime, auth,
object-presign, or WebSocket modules.

## Fleet Topology and Member Identity

The supported shape is a **fleet of machines, each running exactly one engine process**, all
consuming the same pool topic through a `Shared` subscription. A machine is the unit of capacity, of
model cache, and of configuration. There is no within-role replication: every role runs one process
per machine, and horizontal scale is adding a machine, not adding a replica.

| Role | Deployment kind | Processes | Node resource shape | Persistent state |
|---|---|---|---|---|
| Frontend | `Deployment` | one | no special resources | **no PVC** |
| Coordinator | `Deployment` | one | no GPU | **no PVC** (Pulsar subscription cursors are broker-side durable) |
| Engine | Linux: `Deployment`; Apple: host daemon member | **one per machine** | linux-cpu: explicit `engine.resources` CPU/memory requests and limits; the executing machine admits against its own observed capacity and refinement verifies a process-group RSS sampler plus the live outer cgroup envelope; linux-gpu retains its pod/GPU placement shape; apple-silicon: no in-cluster engine pod, so active compiled placements run on the on-host `infernix service` daemon after checked host-partition refinement. Oversized catalog entries remain explicit unavailable models instead of invalidating the whole daemon. | **no PVC**; Linux uses a single `emptyDir` volume `model-cache` mounted at `/model-cache`, and Apple uses a derived host-local model cache; both are rebuilt from `infernix-models` |

**One engine per machine.** Two engines on one machine would mean:

1. Two KV caches indexed by the same `(contextId, prefixHash)` space, competing for memory.
2. Two copies of every loaded model's weights in memory.
3. Two adapter processes contending for the same accelerator handles.

None of these costs translate to throughput gain on the supported adapters, and a second engine
additionally asserts the machine's whole observed capacity twice — each process resolves the same
physical RAM and admits against it independently, so both can pass admission for work that together
exceeds the box. The rule is therefore a correctness rule, not a scheduling preference.

**What enforces the rule on the deployed topology, and what does not.** Be exact here, because the
mechanism a reader assumes decides what they may safely change. The deployed platform is
single-node: `kindWorkerCount` is `1` for every runtime mode, and the engine workload's replica
count in the *generated* Helm overlay — `repoEngineReplicaCount`, which supersedes
`chart/values.yaml` on every render — is `1`. One engine per machine holds today because the
cluster has one machine and the overlay asks for one engine pod, and that pairing is pinned by the
`overReplicatedRoles` property over every count the overlay emits. That is a placement-and-count
mechanism, and naming it plainly is what lets a reader see that raising a replica count is a
correctness defect rather than a capacity knob.

The host-local engine lock is a second, narrower guard: it excludes a second engine process
started from the *same repository checkout*, because it is `runtimeRoot </> "engine.lock"`. It is
repo-local, not machine-global, so it does not exclude two checkouts on one host and it cannot
exclude a second machine.

**Member identity fails closed.** A daemon that cannot establish which member it is refuses to
start. It does not adopt a default, and it does not select the first entry of a catalog: two
machines that both resolved the same identity would each assert the other's capacity as their own,
and nothing downstream would detect it — the broker sees two ordinary `Shared` consumers with
distinct process-qualified names.

**A fleet of more than one engine machine is bounded by a different mechanism than a single-node
deployment.** The two enforcement mechanisms above are both local to one machine: a replica count
is a property of one cluster's overlay, and the engine lock is a property of one checkout's runtime
root. Neither can see a second machine, so neither scales past the single-node topology. The
mechanism for a fleet is a machine contract naming exactly one engine identity, plus a claim for
that identity held against the broker — the broker being the only place N machines meet. Which of
those is in force is what the deployed topology decides, and the supported fleet size is whatever
the mechanism actually in force can bound.

**How a fleet is declared, placed, and identified.** The fleet is a count of machines in the system
contract: `infernix init --engine-machines N` expands each single-machine member into `N` members
(`<member>-m1 … -mN`) serving the same pools on the same `Shared` topic, and changes nothing else
about the graph. `N = 1` reproduces the single-machine contract exactly, which is what the deployed
platform runs. On the cluster lanes a fleet grows one Kind worker node per machine, and the engine
is deployed as one generated `Deployment` per machine — `infernix-engine-m<slot>`, pinned to its own
node by the `infernix.fleet/slot` label, started with `--engine-name <member>`, and mounting its own
binary-generated machine contract at the manifest path discovery already prefers.

That shape is chosen over a `DaemonSet` because a DaemonSet cannot carry a *declared* identity here:
every pod of a DaemonSet is identical, so a pod could only learn which machine it is from the
downward API — an `env:` block, which
[no_env_vars.md](../development/no_env_vars.md) forbids in infernix-owned templates — or from a
Kubernetes API read, which would make identity discovered and contradict the fail-closed rule above.
The `nodeSelector` those Deployments carry is not the retired anti-affinity in another form: it does
not express the one-engine-per-machine rule at all — the broker claim does — it places a declared
machine on the node that *is* that machine, so a slot whose node is gone leaves that machine's
engine `Pending`, which is the honest rendering of a machine being down.

**The broker-side member claim.** Each member has a derived claim topic
(`persistent://infernix/demo/fleet.member-claim.<mode>.<member>`) that carries no messages; holding
the only **exclusive** subscription on it is the claim. It is a topic of its own rather than a
subscription on a pool topic because a pool topic is consumed `Shared` by the whole pool, so an
exclusive claim taken there would exclude the fleet instead of one identity. An engine takes the
claim after namespace and topic reconciliation and after the contract-digest check, and before its
readiness sentinel and every pool subscription: a refused machine never reports ready and never
takes a message a second machine might answer too. A refusal names the identity, the claim topic,
and the incumbent's consumer name and address. Losing the claim later is fatal, because a machine
that can no longer prove it is the only holder of its identity must not keep consuming.

Be exact about what the claim bounds. It bounds **one identity to one live claimant at a time**. It
does not bound how many machines a fleet has. It cannot distinguish a restarting incumbent from an
impostor inside the reacquisition window — Pulsar holds an exclusive slot for the life of the
WebSocket session, so a claim that refused immediately would turn every engine restart into an
outage; the claim therefore waits a bounded wall-clock window first, which makes the common case
survivable rather than making the two cases distinguishable. The bound is measured rather than
counted in retries, because the broker's session timeout it is sized against is measured. And it depends on the broker being the fleet's
single meeting point: a second Pulsar cluster would partition the claim exactly as it would
partition the contract digest.

**Linux GPU per-engine images.** Framework-specific Linux GPU pools may still render as
`infernix-engine-<engine>` Deployments whose image contains exactly one isolated framework venv.
That split is an image and dependency-isolation boundary; pool membership and model routing are
derived from the typed engine-pool graph.

Because that split is per image rather than per machine, one `linux-gpu` machine contract declares
more than one engine member — one per framework image, plus the member the shared
`infernix-engine` Deployment is. The shared Deployment therefore names its own member with
`--engine-name` exactly as the fleet Deployments do: it runs the launcher image, which carries the
native payloads and none of the framework virtual environments, so the member it names is the one
with no per-engine Deployment of its own. Identity is declared on every engine Deployment on every
lane, never left to be resolved by counting.

**Apple silicon symmetry.** On Apple substrates engine members are on-host `infernix service`
daemons with stable host ids, not Kubernetes pods. Normal Apple model pools use `Shared`
subscriptions across distinct host ids so broker-native permits distribute work. Broker permits
remain a concurrency/backpressure mechanism; memory capacity is checked by the executing machine's
runtime admission policy immediately before launch and returns typed `ModelMemoryLimitExceeded`
when the model does not fit. Exact-host routes use derived per-host topics with `Exclusive`.

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
| `apple-silicon` | `true` | `infernix-demo` in cluster | `infernix-coordinator` in cluster | the on-host `infernix service` engine, one per machine, selected by member id |
| `apple-silicon` | `false` | absent | `infernix-coordinator` in cluster | the on-host `infernix service` engine, one per machine, selected by member id |
| `linux-cpu` | `true` | `infernix-demo` in cluster | `infernix-coordinator` in cluster | Kubernetes engine pools, one engine process per machine |
| `linux-cpu` | `false` | absent | `infernix-coordinator` in cluster | Kubernetes engine pools, one engine process per machine |
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

- **Reader** (frontend): cursor-based, with independent state per
  connection; the one frontend process on a machine may host any WS session.
- **Failover** (coordinator): exactly one active subscriber per topic
  at a time; after the owning coordinator process restarts and resubscribes,
  Pulsar redelivers unacknowledged messages from the durable cursor.
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

## Delivery Semantics

**The contract is at-least-once delivery with an effectively-once observable outcome.** This is
stated here rather than left implied, because every recovery property in the failure table below
depends on it and a future change that moved the acknowledgement would silently delete them.

- **Acknowledgement follows the terminal event, never precedes it.** An engine acknowledges a pool
  message only after materialization, inference, and durable result publication succeed. A domain
  failure is itself a terminal event: an adapter error, an unknown model, a malformed request, or an
  admission rejection each publish a `status=failed` result and *then* acknowledge, so a request that
  cannot succeed is answered rather than redelivered forever.
- **The exposure this leaves is duplicate compute, not lost work.** If a machine dies mid-inference
  the message is unacknowledged, the broker redelivers it to another `Shared` consumer, and the
  request is executed a second time. That is the intended trade.
- **Duplicates are collapsed at the effect, not at the delivery.** Producer-side broker
  deduplication and the conversation bridge's per-context cursor mean a redelivered request produces
  no second conversation event, so at-least-once delivery is observed as effectively-once output.
- **Redelivery is the only recovery path.** Request publishes carry a deduplicating sequence id
  derived from the originating prompt, so a re-dispatch from a recovered process is dropped by the
  broker by design. Nothing else in the pipeline can replace an unacknowledged message.

At-most-once was considered and rejected. Prompt resolution requires a terminal event; there is no
client-side deadline and no server-side reaper, so a request discarded before its result is published
leaves a prompt that never resolves and no error the user can see. Acknowledging early would also
delete the recovery path above, on which the fleet's tolerance of a machine loss entirely rests.

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
| Frontend process crash | WS connections drop | The frontend process restarts; clients reconnect, the process re-derives Readers from each JWT, and state replays from Pulsar. Pending submits replay via `clientIdempotencyKey`; reducer dedup catches duplicates. The frontend acknowledges a client submit only after Pulsar confirms the publish, so "acked then crashed" implies "already on the log." |
| Coordinator process crash | The Failover subscription's active consumer is unreachable | The owning process restarts and resubscribes under the stable Failover name; Pulsar then redelivers unacknowledged conversation events to the dispatcher and unacknowledged inference results to the result bridge. Producer dedup on `inference.request.<mode>` and on the conversation topic prevents duplicate dispatch and duplicate writeback. `Failover` supplies broker coordination, not a standby coordinator. |
| Engine member crash | Active engine member disappears | Pulsar redelivers the unacked pool-topic message to another eligible member when the route is a `Shared` pool. The receiving engine has a KV-cache miss on that request's `prefixHash` and rebuilds from the conversation log; producer dedup on `inference.result.<mode>` prevents a duplicate result if the original engine had partially published. |
| Engine machine unavailable | Its engine member disappears | Pulsar redelivers an unacknowledged pool-topic message to another eligible fleet member when one exists for a `Shared` route; otherwise the message remains pending until an eligible member returns. The receiving engine rebuilds a missing KV cache from the conversation log. |
| Engine model-memory admission failure | Plan refinement on the executing machine classifies a placed model above that machine's own resource capacity for one of the resources it consumes as `UnavailableModel` | The engine publishes a per-request `status=failed` result with typed `InferenceError.ModelMemoryLimitExceeded`, including `requiredMib`, `availableMib`, and the `resource` the model did not fit, without launching an engine process; the coordinator forwards the request to its pool rather than vetoing it, because a machine that will not run the work has no verdict to give. Smaller admitted placements continue serving; a machine that admits none of its placements refuses to start. |
| Invalid inference request | A coordinator or engine receives an empty model id, unknown model, wrong-route model, or malformed protobuf | Empty/unknown/wrong-route requests publish a terminal failed `InferenceResult`; malformed bytes publish a typed malformed failed result. File-spool sources are removed and Pulsar messages acknowledged only after terminal result persistence/publication. |
| Pulsar broker / MinIO / IdP outage | A platform dependency is unavailable | Frontend caches JWKS with short TTL so brief IdP outages do not break existing sessions. The platform services are deployed single-node on the supported substrate, so an outage is an outage: recovery is restart, and durability comes from their own storage rather than from replication. |

## Apple Silicon Mapping

The Apple substrate runs the split with the coordinator in cluster and engine members on hosts.

- `infernix-coordinator` in cluster consumes `inference.request.apple-silicon`, runs the dispatch,
  result-bridge, and model-bootstrap work, and publishes through plan-derived capabilities to
  derived Apple pool/model topics. The raw topic publisher is not a supported API.
- Each on-host `infernix service --role engine` process starts with a stable Apple host id, derives
  the model topics it is responsible for from the typed engine-pool assignment, pulls model weights
  from `infernix-models` via the shared adapter helper into a host-local cache under
  `./.data/runtime/model-cache/`, runs the Apple-native adapter, owns the in-memory KV cache, and
  publishes `inference.result.apple-silicon`.
- Normal Apple pools use `Shared` across distinct host ids so Pulsar broker backpressure assigns
  work to hosts with consumer-permit availability. Receiver-queue headroom is separate from memory
  capacity; compilation accounts for capacity and live refinement verifies the enforcer before an
  engine receives `ExecutableModel`.
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

Execution-plan compilation is pure graph validation: it accounts for every configured model as a
`CompiledPlacement`, deciding where a model may run and never whether a machine can fund it.
Model-memory admission happens during plan refinement, on the machine that will execute, against
that machine's `InferenceMemoryBudget`. Refinement accounts for every placed model as either an
`ExecutableModel` or an explicit `UnavailableModel`; one oversized entry does not invalidate the
whole config or prevent smaller placements from serving, and a machine that admits none of its
placements refuses to start rather than reporting ready and rejecting every request.

The requirement admission compares against is **derived from the model's own artifact** and the
execution shape the engine will run under — never authored per family — so the quantity one machine
admits is a fact about the model rather than a number a second machine could write down differently.

The active budget is a typed value, not an integer sentinel:
`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit | DualEnforcedBudget PodMemoryLimit PodMemoryLimit`.
There is no unenforced arm, and no arm admits two physical resources against one number: the dual arm
names the pod cgroup RAM limit first and the device VRAM limit second, because host residency and
device residency are different quantities with different drivers. The checked host partition rejects
oversubscription, and a `ModelMemoryRequirement` minted only by the artifact-header derivation
prevents absent/zero requirements from disabling admission.

Budget sources are:

- `apple-silicon`: unified host RAM, computed as physical memory (`sysctl -n hw.memsize`) minus the
  read-only Colima pledge and host reserve
- `linux-cpu`: the Kubernetes engine pod memory limit for the active workload
- `linux-gpu`: the dual arm — an executable placement requires independently indexed pod-RAM and
  GPU-VRAM grants; either missing half fails closed with `GpuDualResourceBudgetRequired`

Compilation mints one resource-indexed grant per physical resource a fitting placement consumes.
Package-owned live observations pair each grant with the matching enforcer inside `ExecutableModel`;
public engine launch accepts that whole capability and derives its model, runtime, binding, command,
and execution shape from it — the same execution shape the cache term was computed from, carried to
the engine rather than restated inside it. A measured ceiling breach becomes typed
`ModelMemoryLimitExceeded` naming the resource it breached and the footprint it observed, while
sampler loss fails closed as enforcement unavailable.

The execution authority remains inside the opaque engine capability and serializes inference for
that engine member. Where a lane can install a kernel ceiling, that ceiling is installed before the
engine's first allocation and package-owned observers **corroborate** it over the residue it does not
charge; where a lane cannot, the observers are the whole mechanism, and the lane declares that
strength in its own type rather than presenting a sampled bound as a prevented one. Canonical home:
[bounded_inference_memory.md](bounded_inference_memory.md).

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

- `infernix lint chart` against the role-specific Deployment templates
- `infernix test integration` for the dispatcher → engine → result-bridge
  writeback path
- `infernix test integration` for engine-pool placement and broker-native
  shared-subscription backpressure — both properties of the pool graph rather
  than of recovery
- a production-shape test that deploys `demo_ui = false` and asserts the coordinator plus engine-pool
  workloads are present while demo-only workloads and routes are absent
- a scheduling check that every deployed workload is fully scheduled, with no `Pending` workload in
  the `platform` namespace. This check does not establish one-engine-per-machine: with the engine
  anti-affinity retired, a second engine pod schedules onto the one worker without going `Pending`,
  so a passing run and a violated rule are indistinguishable from here. The rule is carried instead
  by the `overReplicatedRoles` property over the generated overlay's counts, which is a unit
  assertion rather than a cluster observation

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
- [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md) — validation surface
- [../tools/pulsar.md](../tools/pulsar.md) — Pulsar topic contract
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md) — phase plan for the supported three-role pod split
- [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md) — authoritative component inventory
- [Managed State Transitions](managed_state_transitions.md) — typed transitions and readiness evidence for every system state
