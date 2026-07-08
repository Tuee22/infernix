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

## Current Status

The startup-time pool-routing code-side implementation has landed. The staged substrate Dhall record
now carries `enginePools` and `engineMembers`; generated configs derive normal pool topics and
pinned member topics from `(runtimeMode, poolId/memberId, modelId)`; coordinator handoff resolves a
model to a validated pool topic; and engine daemons select a stable member id before subscribing.
The validator rejects impossible routing states such as unknown models, duplicate pool/member ids,
empty assignments, one-sided pool/member links, raw topic-like ids, `Failover` service consumers,
and routable models with no eligible member.

The reflected substrate schema (from the substrate decoder type) carries the supported `enginePools` / `engineMembers` graph plus
explicit `engineDaemons` metadata derived from that graph for daemon startup and targeted
validation configs. Operators no longer author or receive legacy `engine`, `host_batch_topic`, or
raw batch-topic fields in the supported Dhall surface. Current Apple integration proves pinned
`Exclusive` duplicate-consumer rejection, same-machine
Apple host-member coexistence on one real `Shared` pool subscription, and production
`demo_ui = false` route/publication assertions. Current Apple integration also executes the
single-host logical `Shared` backlog harness by holding one Pulsar WebSocket consumer unacked and
asserting a second request reaches a free consumer on the same service-shaped subscription.
Current Linux CPU integration proves Kubernetes-observed pool placement and shared-subscription
backpressure on unique derived pool/model topics; Linux GPU/CUDA cohort validation remains in
[Wave J](../../DEVELOPMENT_PLAN/cohort-validation-waves.md). Physical Apple multi-host membership
is hardware-deferred proof while no second Apple host is available.

**Resource-safety scope (open gap).** The routing controls here — Pulsar consumer permits, receiver
backlog, and `maxInflightPerMember` — plus the model cache (LRU in
`python/adapters/model_cache.py`) bound in-flight request *concurrency* and *disk*, not host
inference RAM. On `apple-silicon` there are no in-cluster engine pods: every pool runs on the single
on-host `infernix service` daemon, serialized one model at a time as fresh subprocesses, with no
per-model RAM footprint, no inference-RAM budget, no admission control, and no RAM eviction. Peak
resident memory is therefore unbounded, so sustained load across the model catalog can exhaust host
RAM and let the OS SIGKILL the daemon (an uncontrolled process death, not a clean `status=failed`).
A per-model RAM budget plus an admission gate on the serialized on-host path is a known, still-open
gap reopened as Phase 4 Sprint 4.26
([phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)),
paired with the memory-bounded validation lane in Phase 6 Sprint 6.37
([phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md));
see [cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) Wave R.

## Routing Model

The routing graph is:

```text
model id -> engine pool -> derived work topic -> eligible engine members
```

The coordinator chooses a pool topic, not a concrete node, for normal scalable work. Pulsar chooses
which eligible consumer receives the next message based on consumer permits and receiver backlog.
Busy members stop accepting new permits or keep receiver queues small; idle members continue
granting permits and naturally receive more work. These controls bound in-flight request concurrency
and the disk model cache, not host inference RAM; on `apple-silicon` one serialized on-host daemon
runs all pools, so `maxInflightPerMember = 1` does not bound cumulative or peak resident memory (open
gap — see **Resource-safety scope** under Current Status and Phase 4 Sprint 4.26).

Pinned routing is explicit and separate:

```text
model id -> pinned member route -> derived member topic -> one exclusive consumer
```

Pinned routes are for exact-host or exact-placement requirements, not for ordinary load balancing.

## Typed Configuration

The staged substrate file describes engine pools and durable engine members with substrate-neutral
fields:

```dhall
enginePools =
  [ { id = "apple-llm"
    , runtimeMode = "apple-silicon"
    , models = [ "llm-smollm2-safetensors" ]
    , members = [ "mac-studio-1", "mac-mini-2" ]
    , subscription = "shared"
    , maxInflightPerMember = 1
    }
  , { id = "linux-gpu-vllm"
    , runtimeMode = "linux-gpu"
    , models = [ "llm-smollm2-safetensors" ]
    , members = [ "vllm" ]
    , subscription = "shared"
    , maxInflightPerMember = 1
    }
  ]

engineMembers =
  [ { id = "mac-studio-1"
    , runtimeMode = "apple-silicon"
    , location = "control-plane-host"
    , pools = [ "apple-llm" ]
    }
  , { id = "vllm"
    , runtimeMode = "linux-gpu"
    , location = "cluster-pod"
    , pools = [ "linux-gpu-vllm" ]
    }
  ]
```

The substrate decoder type is the exact schema (print it with `infernix internal dhall-schema substrate`). `maxInflightPerMember` caps per-member
in-flight request concurrency and disk-cache churn, not host inference RAM — on `apple-silicon` all
pools share one serialized on-host daemon, so it does not bound cumulative or peak memory (open gap;
see **Resource-safety scope** under Current Status and Phase 4 Sprint 4.26). Kubernetes placement
details stay in chart values and Kubernetes scheduling primitives; the routing graph only names
durable pool/member identity. The invariants are fixed:

- pool ids are unique
- member ids are unique within the substrate
- every model id exists in the generated catalog for that substrate
- every model that can be routed has at least one pool member
- every generated topic is derived from `(runtimeMode, pool id, model id, optional member id)`
- no operator-provided raw topic string can bypass validation
- Kubernetes pod names are never durable routing identifiers

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

## Hot Reload

The implemented contract uses startup-time assignment: change the Dhall pool/member graph, restage
or publish it, then restart or roll out affected daemon processes. Cache state is independent of
assignment state. Removing a model from a member stops new work for that model after restart and
makes the cache entry evictable; it does not immediately delete warm artifacts unless an explicit
drain-and-evict operation or disk cache pressure requires it. Here "cache" and "cache pressure" mean
the on-disk model-cache LRU (`python/adapters/model_cache.py`) only; there is no host inference-RAM
eviction concept, so this reclaims disk, not resident memory. Bounding peak RAM on the serialized
`apple-silicon` on-host path is the reopened Phase 4 Sprint 4.26 / Phase 6 Sprint 6.37 gap (see
**Resource-safety scope** under Current Status).

A future hot-reload extension may use compacted Pulsar desired-state topics:

| Topic | Key | Purpose |
|---|---|---|
| `persistent://infernix/control/engine-pool-assignments` | member id | desired pool/model assignment for one durable member |
| `persistent://infernix/control/engine-pool-status` | member id | latest observed member state for diagnostics and future policy |

Assignment records would be declarative desired state, not imperative commands. An engine member
would converge toward the latest record by subscribing to newly assigned model topics, warming or
materializing models, draining removed assignments, and marking removed model cache entries
evictable. This hot-reload path is not implemented in the current sprint.

## Validation

The pool contract is valid only when:

- generated Dhall can represent the pool graph without raw topic strings
- unit validation and substrate decoding reject a model route with no eligible members
- coordinator routing can publish only to derived topics from the validated graph
- engine members subscribe only to derived topics assigned to their pool or member id
- same-machine Apple host-member daemons can coexist on one `Shared` subscription
- single-host logical Apple pool consumers distribute work through Pulsar permits/backpressure
- Linux CPU engine pods prove pool placement and broker backpressure on derived pool/model topics
- pinned routes use `Exclusive` and reject duplicate member consumers
- `demo_ui = false` still deploys the production coordinator and engine pools while omitting only
  the demo frontend, browser API, Keycloak, and demo-only routes
- physical Apple multi-host distribution repeats the same scenario across separate hosts when
  hardware exists, but is deferred outside the current single-host validation envelope

## Cross-References

- [daemon_topology.md](daemon_topology.md)
- [runtime_modes.md](runtime_modes.md)
- [../tools/pulsar.md](../tools/pulsar.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
- [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md)
