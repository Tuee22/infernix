# Pulsar ML-Workflow Contract

**Status**: Authoritative source
**Referenced by**: [../../README.md](../../README.md), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: The cross-project contract — shared verbatim with the `jitML`
> sister project — for ML workflows (training and inference) over Pulsar: the
> three-role split (Engine / Coordinator / Webapp), the derived topic algebra,
> the `Work*` envelope family, the artifact + readiness contract, the websocket
> snapshot/patch surface, and the coordination primitives shared by `infernix` and `jitML`.

## Why this contract exists

`infernix` (Pulsar-driven model **inference serving**) and `jitML` (JIT-compiled,
multi-substrate **training + inference**) share one Pulsar-based
ML-workflow shape. This document is the authoritative, **project-neutral**
contract; the identical text lives at `documents/engineering/pulsar_ml_workflow.md`
in `jitML`. Where a project specializes the contract, it does so only in the
project-specific surfaces noted inline (runtime-mode identifiers, engine
adapters, topic namespace), never by diverging from the role split, envelope
family, or phasing rules.

## The three roles

One binary; the role is selected by the typed Dhall config it is given. There
are no separate per-role executables: `infernix` exposes Engine, Coordinator,
and Webapp roles. Every role runs
the same lifecycle skeleton — `Load → Prereq → Acquire → Ready → Serve → Drain →
Exit` — with role-specific `acquire`/`serve`/`drain` callbacks.

| Role | Resides | Sole responsibility | Talks to |
|------|---------|---------------------|----------|
| **Engine** | cluster **or** host | ML **compute only** — inference (and, where a project implements it, training); substrate/lane-specific execution | **Pulsar + MinIO only** |
| **Coordinator** | cluster only | **Owns Pulsar topic lifecycle**; batching, fan-in/fan-out, routing; **readiness gating** (derivation/model-bootstrap completion → serveable) | Pulsar + MinIO + cluster API |
| **Webapp** | cluster | **Thin websocket server** for the browser; work dispatch + result/event streaming + static-artifact serving; **no ML compute** | **Pulsar + MinIO only** + browser (websocket) |

Invariants:

- The **Engine is the only role that computes.** No inference or training runs in
  the Webapp or Coordinator.
- The **Webapp is substrate-agnostic.** It publishes work and renders results off
  Pulsar topics; it never knows whether an Apple-native engine, a CUDA engine, or
  a CPU engine computed the result.
- The **Coordinator owns topic lifecycle.** Topics are created/validated/torn down
  by the coordinator from a typed topology descriptor — never auto-created
  implicitly by the broker and never hardcoded in a static list. (In `infernix`
  this replaces the implicit broker auto-create on first publish/subscribe.)

## Topic algebra

Every topic name is **derived** from a typed descriptor and a **validated routing
graph**; hand-written topic strings are forbidden.

```
topicFor :: Tenant -> Namespace -> Workflow -> Phase -> Lane -> TopicName
  Workflow = < Train | Infer | Tune | Rl | … >          -- project supplies its set
  Phase    = < Command | Event | Result | Batch >        -- Batch = coordinator→engine routing
  Lane     = project routing key                          -- infernix: (mode,pool,model); jitML: substrate
```

The coordinator validates the routing graph (reject unroutable models / one-sided
pool↔member links — `infernix` already derives `enginePoolTopicForMode`) and
reconciles the exact derived topic set at startup. A new workflow or lane changes
the descriptor, not a hand-edited topic list.

## The `Work*` envelope family

Training and inference are the **same** request → events → result shape,
correlated by `callId`:

```
WorkCommand { callId, workflow, lane, subjectRef, artifactRef?, payload, replyTopic }
WorkEvent   { callId, workflow, progress }   -- Infer: token/batch/none; Train: epoch/loss
WorkResult  { callId, status, outputRefs }   -- Infer: output refs; Train: checkpoint refs
```

- `subjectRef` is the durable subject a result routes back to (`infernix`: a
  `(userId, contextId)` conversation; `jitML`: an experiment/run).
- `artifactRef` (see below) is present when a workflow consumes a derived artifact.
- `infernix`'s `InferenceRequest`/`InferenceResult` (`request_id`,
  `user_prompt_message_id`, `causal_ref`) are the `Infer` instance of this family.
- A project may leave a workflow unimplemented — **`infernix` does not implement
  `Train`** — yet the envelope family still represents it.

## Artifact + readiness contract

A **content-addressed MinIO artifact store** plus a **`.ready` sentinel written
last** is the cross-project mechanism that makes "use an underived artifact"
unrepresentable in the domain.

- A serveable `ArtifactRef` is obtainable **only** from a completed derivation:
  - `infernix`: the coordinator's model-bootstrap downloads + stages weights to
    `infernix-models/<modelId>/…`, then writes `.ready` last.
  - `jitML`: a training `WorkResult` whose checkpoint manifest has `step ≥ 1` and a
    resolvable `latest` pointer → the coordinator writes the `ready` sentinel.
- The Webapp and Coordinator reference an `ArtifactRef`, never a raw id.
- **Parse, don't validate, at the wire boundary.** A malformed command is always
  *possible* on the wire; the daemon parses it into a validated `ArtifactRef`/total
  domain value or emits a typed rejection event — never a silent bad state.

## Websocket surface (Webapp ↔ browser)

- Typed **snapshot + patch** frames. The browser applies patches mechanically; no
  business logic in the browser (`infernix`'s `purescript-bridge` snapshot/patch
  surface is the reference implementation).
- Per-subject Pulsar **Readers**; **no session affinity**. One Webapp process
  runs per machine, and a reconnect replays state through fresh Readers.
- Static artifacts (SPA bundle, uploads, result blobs) move via MinIO **presigned
  URLs**.
- Inference is **asynchronous to the browser**: the panel publishes a request and
  renders the streamed result; it does not block on a synchronous compute response.

## Coordination primitives

- **Failover subscriptions** for every single-owner coordinator loop (dispatch,
  result-bridge, readiness/bootstrap): stable subscription name = ownership,
  process-qualified consumer name = consumer observability. This is stable
  single-active broker coordination, not standby-role availability or repo-owned
  HA. (`infernix`'s coordinator Failover loops are the reference.)
- **Producer-side broker dedup** keyed by `callId` → at-least-once becomes
  effectively-once; the dedup decision stays a pure fold over the work log.
- **Single-flight / batching** expressed as pure reducers over the work log
  (testable offline without a broker).

## Configuration and roles

- One binary; `activeRole : Role = < Engine | Coordinator | Webapp >` plus
  per-role config is read from typed Dhall at startup (no env-var role selection —
  consistent with `infernix`'s no-env-var doctrine).
- **Reflected Dhall schema**: the binary emits the schema its decoders accept,
  so the schema cannot drift from the types.

## Conformance checklist

A project conforms to this contract when all hold:

- One binary selects `{Engine, Coordinator, Webapp}` through typed Dhall.
- Engine is the only role that computes; Webapp and Coordinator run no ML.
- Webapp is substrate-agnostic and talks only to Pulsar and object storage.
- Coordinator owns explicit topic lifecycle; there is no implicit auto-create or
  hardcoded topic list.
- Every topic derives from the typed descriptor and validated routing graph.
- Training and inference use the `WorkCommand → WorkEvent* → WorkResult` family,
  correlated by `callId`.
- A serveable `ArtifactRef` is mintable only from a completed derivation; a
  `.ready` sentinel is written last.
- The browser receives snapshot and patch frames over WebSocket; inference is
  asynchronous to the browser.
- Failover subscriptions provide stable single-active coordination;
  acknowledgement ordering plus producer dedup provide at-least-once delivery
  with an effectively-once observable outcome.
- The binary emits its own reflected Dhall schema.

## Related Documents

- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md)
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> Architecture docs that elaborate the project-specific surfaces of this contract
> (`daemon_topology.md`, `engine_pool_routing.md`, `configuration_doctrine.md`,
> `web_ui_architecture.md`, `../tools/pulsar.md`) cross-reference it; the
> `documents/` suite map lists it for discovery.

## Cross-References

- [Managed State Transitions](managed_state_transitions.md)
