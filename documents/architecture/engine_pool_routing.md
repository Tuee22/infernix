# Engine Pool Routing

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [daemon_topology.md](daemon_topology.md), [runtime_modes.md](runtime_modes.md), [../tools/pulsar.md](../tools/pulsar.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Define the substrate-neutral engine-pool routing model that uses Pulsar broker
> backpressure for work distribution while keeping model placement typed and statically validated.

## TL;DR

- The durable routing unit is an **engine pool**, not a Kubernetes pod and not a single Apple host.
- Coordinators publish to model-derived pool topics; eligible engine members subscribe to those
  topics and let Pulsar distribute work through broker-native backpressure.
- Operators declare model capability and placement in typed Dhall. They do not hand-write arbitrary
  batch topic strings.
- Illegal routing states are rejected before rollout: every routable model must have at least one
  eligible engine member, and every declared model must exist in the generated catalog.
- Apple host daemons are durable members because the host identity is stable. Kubernetes pods are
  ephemeral members of a Deployment, StatefulSet, DaemonSet, or logical pool; pod names are
  observational only.
- Normal scalable pools use Pulsar `Shared` subscriptions. Explicitly pinned routes use derived
  per-member topics and `Exclusive` subscriptions.

## Routing Authority

The runtime config carries the pool graph; generated configs derive normal pool topics and pinned
member topics from `(runtimeMode, poolId/memberId, modelId)`; coordinator handoff resolves a model to
a validated pool topic; and an engine daemon establishes its member identity before subscribing. The
validator rejects impossible routing states: unknown models, duplicate pool/member ids, empty
assignments, one-sided pool/member links, raw topic-like ids, `Failover` service consumers, and
routable models with no eligible member.

Operators do not author raw topic strings. There is no legacy `engine`, `host_batch_topic`, or raw
batch-topic field in the supported Dhall surface.

**Resource-safety scope.** The routing controls here — Pulsar consumer permits and receiver backlog,
with each consumer holding a single permit — plus the model cache (LRU in
`python/adapters/model_cache.py`) bound in-flight request *concurrency* and *disk*. Model memory is
bounded separately by the typed execution-plan refiner, on the machine that will execute, against a
requirement derived from the model's artifact rather than from anything a route declares. Each lane
declares the enforcement strength it has: Apple sizes against a checked unified-host partition and
declares detection, because no kernel ceiling is installable there; Linux CPU adds a ceiling
installed before the engine's first allocation once that ceiling is calibrated on the lane, over pod
capacity plus live RSS and cgroup refinement; Linux GPU requires independently indexed pod-RAM and
VRAM enforcement and fails closed without it, and its device half is admission and arena sizing plus
detection, because no kernel mechanism bounds device memory anywhere. Capacity failures remain
explicit unavailable models carrying a typed `ModelMemoryLimitExceeded` that names the resource it
breached and the footprint it observed, so one oversized entry does not invalidate smaller
placements. A machine that places models and admits none of them refuses to start rather than
reporting ready and rejecting every request. A fitting model launches only through
`ExecutableModel`, whose matching indexed grant/enforcer pair installs that ceiling where the lane
can install one and drives the capped-engine sampler over the residue everywhere.
Canonical home: [bounded_inference_memory.md](bounded_inference_memory.md).

**Closed messaging authority.** Compilation rejects a `TopicFamilyCollision` when any topic is
reused across coordinator requests, results, model-bootstrap requests, model-bootstrap ready
events, or engine routes. Coordinator and engine consumers use plan-derived topic capabilities;
there is no supported raw publisher. Unavailable, empty-model, unknown-model, wrong-route, and
malformed requests become terminal failed results before their source is removed or acknowledged.
Model-bootstrap publication additionally requires an opaque plan-derived capability, and the
consumer revalidates model identity, compiled URL, and canonical timestamp before side effects.

## Routing Model

The routing graph is:

```text
model id -> engine pool -> derived work topic -> eligible engine members
```

The coordinator chooses a pool topic, not a concrete node, for normal scalable work. Pulsar chooses
which eligible consumer receives the next message based on consumer permits and receiver backlog.
Busy members stop accepting new permits or keep receiver queues small; idle members continue
granting permits and naturally receive more work. These controls bound in-flight request concurrency
and the disk model cache, not model memory capacity. Memory capacity is handled on the executing
machine by the admission policy described in **Resource-safety scope**; the coordinator forwards a
placed model to its pool rather than vetoing it, because a machine that will not run the work has no
verdict to give.

Pinned routing is explicit and separate:

```text
model id -> pinned member route -> derived member topic -> one exclusive consumer
```

Pinned routes are for exact-host or exact-placement requirements, not for ordinary load balancing.

## Typed Configuration

The **system contract** describes engine pools and their models; the **machine contract** names which
of those pools a given box serves. **The example below is illustrative of the field *shape* across
substrates, not a valid single-substrate pair:** a real initialized system contract carries exactly
one substrate's pools and gives each pool a distinct model id, and a real machine contract selects
its pools out of that record by field access — so a pool a machine names but the contract does not
define is a Dhall type error at decode, not a subscription to a topic nobody publishes to.

`runtimeMode` and `subscription` are Dhall unions rather than `Text`, so an
alternative is written as a label selected from the union type, not as a quoted string.

```dhall
let RuntimeMode = < AppleSilicon | LinuxCpu | LinuxGpu >

let Subscription = < Shared | Exclusive | Failover >

in  { enginePools =
        [ { id = "apple-llm"
          , runtimeMode = RuntimeMode.AppleSilicon
          , models = [ "llm-smollm2-safetensors" ]
          , members = [ "mac-studio-1", "mac-mini-2" ]
          , subscription = Subscription.Shared
          }
        , { id = "linux-gpu-vllm"
          , runtimeMode = RuntimeMode.LinuxGpu
          , models = [ "llm-smollm2-safetensors" ]
          , members = [ "vllm" ]
          , subscription = Subscription.Shared
          }
        ]
    , engineMembers =
        [ { id = "mac-studio-1"
          , runtimeMode = RuntimeMode.AppleSilicon
          , location = "control-plane-host"
          , pools = [ "apple-llm" ]
          }
        , { id = "vllm"
          , runtimeMode = RuntimeMode.LinuxGpu
          , location = "cluster-pod"
          , pools = [ "linux-gpu-vllm" ]
          }
        ]
    }
```

The binary writes the union type inline at every field rather than binding a `let`; the bindings
above are only to keep the illustration readable.

The substrate decoder type is the exact schema (print it with `infernix internal dhall-schema
substrate`). Per-consumer in-flight is **one**: each engine consumer requests a single permit, and
execution is additionally serialized behind the machine's execution authority, so a machine holds one
model at a time. Concurrency is therefore a property of the fleet's size, not of a configured number
— which is why no in-flight knob appears on the wire. It never bounds model memory; that is handled
separately by the typed resource-admission policy (see **Resource-safety scope**). Kubernetes
placement details stay in chart values and Kubernetes scheduling primitives; the routing graph only
names durable pool/member identity. The invariants are fixed:

- pool ids are unique, and a pool is named by selecting it from the system contract, never by
  spelling it as free text
- member ids are unique within the substrate, and a member id is required — a daemon that cannot
  establish its identity refuses to start rather than adopting a default
- every model id exists in the generated catalog for that substrate
- every generated topic is derived from `(runtimeMode, pool id, model id, optional member id)`
- no operator-provided raw topic string can bypass validation
- Kubernetes pod names are never durable routing identifiers

One invariant deliberately **does not** hold fleet-wide: "every routable model has at least one
eligible member" is not checkable from the system contract alone, because eligibility is the union of
what every machine independently declares it serves. A model that no machine serves is a published
message with no consumer — persisted, unanswered, and silent. The fleet's own membership is the
authority for that property, and the system contract cannot substitute for it.

## Topic Derivation

Normal pool topics are derived from model and pool identity:

```text
persistent://infernix/demo/inference.batch.<mode>.pool.<poolId>.model.<modelId>
```

Pinned member topics are derived from member identity:

```text
persistent://infernix/demo/inference.batch.<mode>.member.<memberId>.model.<modelId>
```

The names above are the contract shape; implementation may apply escaping or hashing for ids that
need Pulsar-safe normalization. The normalized topic remains derived, never hand-maintained.

## Substrate Placement

| Substrate | Durable placement identity | Runtime member identity |
|---|---|---|
| Apple Silicon | Apple host id declared in Dhall | host daemon process label |
| Linux CPU | Kubernetes workload or logical pool | pod name, pod UID, or hostname for status only |
| Linux GPU | Kubernetes workload or logical pool plus GPU placement rules | pod name, pod UID, or hostname for status only |

Kubernetes placement details stay in Kubernetes-native mechanisms: Deployment replica counts,
DaemonSets where appropriate, node selectors, affinity, taints, tolerations, and resource requests.
The routing graph does not depend on a specific pod surviving.

## Assignment Reload

The contract uses startup-time assignment: change the Dhall pool/member graph, restage
or publish it, then restart or roll out affected daemon processes. Cache state is independent of
assignment state. Removing a model from a member stops new work for that model after restart and
makes the cache entry evictable; it does not immediately delete warm artifacts unless an explicit
drain-and-evict operation or disk cache pressure requires it. Here "cache" and "cache pressure" mean
the on-disk model-cache LRU (`python/adapters/model_cache.py`) only; there is no resident-memory
eviction concept, so this reclaims disk, not resident memory. A model either fits the active memory
budget for that request or returns typed `ModelMemoryLimitExceeded`.

Hot reload through Pulsar desired-state topics is outside the supported contract. Assignment changes
take effect only after the affected daemon process restarts with the updated typed graph.

## Validation

The pool contract is valid only when:

- generated Dhall can represent the pool graph without raw topic strings
- unit validation and substrate decoding reject a model route with no eligible members
- coordinator routing can publish only to derived topics from the validated graph
- engine members subscribe only to derived topics assigned to their pool or member id
- a second engine process on a machine that already runs one is refused, because one engine process
  per machine is a correctness rule rather than a scheduling preference (see
  [daemon_topology.md](daemon_topology.md)); the host-local engine lock names the holding process
- single-host logical Apple pool consumers distribute work through Pulsar permits/backpressure
- Linux CPU engine pods prove pool placement and broker backpressure on derived pool/model topics
- pinned routes use `Exclusive` and reject duplicate member consumers
- `demo_ui = false` still deploys the production coordinator and engine pools while omitting only
  the demo frontend, browser API, Keycloak, and demo-only routes
- a physical Apple multi-host distribution claim requires the same scenario to pass across distinct
  hosts; single-host logical-pool evidence cannot satisfy that gate

## Cross-References

- [daemon_topology.md](daemon_topology.md)
- [runtime_modes.md](runtime_modes.md)
- [../tools/pulsar.md](../tools/pulsar.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
- [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md)
- [Managed State Transitions](managed_state_transitions.md)
