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

The current worktree still carries `engineDaemons` and the old batch-topic helpers as compatibility
surfaces while chart/runtime cleanup is staged through
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
Current Apple integration proves pinned `Exclusive` duplicate-consumer rejection, same-machine
Apple host-member coexistence on one real `Shared` pool subscription, and production
`demo_ui = false` route/publication assertions. Current source also includes a compile-validated
single-host logical `Shared` backlog harness that holds one Pulsar WebSocket consumer unacked and
asserts a second request reaches a free consumer on the same service-shaped subscription; executing
that harness on Apple and proving Linux GPU placement remain in
[Wave J](../../DEVELOPMENT_PLAN/cohort-validation-waves.md). Physical Apple multi-host membership
is hardware-deferred proof while no second Apple host is available.

## Routing Model

The routing graph is:

```text
model id -> engine pool -> derived work topic -> eligible engine members
```

The coordinator chooses a pool topic, not a concrete node, for normal scalable work. Pulsar chooses
which eligible consumer receives the next message based on consumer permits and receiver backlog.
Busy members stop accepting new permits or keep receiver queues small; idle members continue
granting permits and naturally receive more work.

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
    , models = [ "llm-qwen25-safetensors" ]
    , members = [ "mac-studio-1", "mac-mini-2" ]
    , subscription = "shared"
    , maxInflightPerMember = 1
    }
  , { id = "linux-gpu-vllm"
    , runtimeMode = "linux-gpu"
    , models = [ "llm-qwen25-safetensors" ]
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

`dhall/InfernixSubstrate.dhall` is the exact schema. Kubernetes placement details stay in chart
values and Kubernetes scheduling primitives; the routing graph only names durable pool/member
identity. The invariants are fixed:

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
drain-and-evict operation or cache pressure requires it.

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
