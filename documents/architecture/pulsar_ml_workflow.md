# Pulsar ML-Workflow Contract

**Status**: Authoritative source
**Referenced by**: [../../README.md](../../README.md), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: The cross-project contract — shared verbatim with the `jitML`
> sister project — for ML workflows (training and inference) over Pulsar: the
> three-role split (Engine / Coordinator / Webapp), the derived topic algebra,
> the `Work*` envelope family, the artifact + readiness contract, the websocket
> snapshot/patch surface, and the coordination primitives. `infernix` and `jitML`
> both implement this shape so the eventual migration onto the shared
> `hostbootstrap` base is a lift-and-shift rather than two divergent rewrites.

## Why this contract exists

`infernix` (Pulsar-driven model **inference serving**) and `jitML` (JIT-compiled,
multi-substrate **training + inference**) are converging on one Pulsar-based
ML-workflow shape. This document is the authoritative, **project-neutral**
contract; the identical text lives at `documents/engineering/pulsar_ml_workflow.md`
in `jitML`. Where a project specializes the contract, it does so only in the
project-specific surfaces noted inline (runtime-mode identifiers, engine
adapters, topic namespace), never by diverging from the role split, envelope
family, or phasing rules.

## The three roles

One binary; the role is selected by the typed Dhall config it is given (no
separate per-role executables — `infernix` retires the two-binary
`infernix` + `infernix-demo` split in favour of a Webapp role). Every role runs
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
- Per-subject Pulsar **Readers**; **no session affinity** (any webapp pod serves
  any connection).
- Static artifacts (SPA bundle, uploads, result blobs) move via MinIO **presigned
  URLs**.
- Inference is **asynchronous to the browser**: the panel publishes a request and
  renders the streamed result; it does not block on a synchronous compute response.

## Coordination primitives

- **Failover subscriptions** for every single-owner coordinator loop (dispatch,
  result-bridge, readiness/bootstrap): stable subscription name = ownership,
  process-qualified consumer name = replica observability. HA with no external
  consensus system. (`infernix`'s coordinator Failover loops are the reference.)
- **Producer-side broker dedup** keyed by `callId` → at-least-once becomes
  effectively-once; the dedup decision stays a pure fold over the work log.
- **Single-flight / batching** expressed as pure reducers over the work log
  (testable offline without a broker).

## Configuration and roles

- One binary; `activeRole : Role = < Engine | Coordinator | Webapp >` plus
  per-role config is read from typed Dhall at startup (no env-var role selection —
  consistent with `infernix`'s no-env-var doctrine).
- **Reflected Dhall schema**: the binary emits the schema its decoders accept
  (so the schema cannot drift from the types). This is the convention both repos
  adopt now and the lever for the eventual `hostbootstrap` lift.

## Phasing rules (both repos)

These two rules govern every phase in both repos' `DEVELOPMENT_PLAN/`:

1. **Forward-only DAG.** Every `Blocked by` / dependency edge references an
   equal-or-lower-numbered phase. No earlier phase is blocked by an incomplete
   later phase. The plan is workable strictly in numerical order.
2. **Single-accelerator per phase.** A phase that needs an accelerator validates on
   **exactly one** of `{apple-silicon, the GPU lane}` plus `linux-cpu` (which runs
   on both hardware sets and is the common lane). No phase's validation gate
   requires both accelerators. Cross-accelerator aggregation is a `linux-cpu`-only
   phase that merges committed per-lane attestations. (This replaces `infernix`'s
   prior two-axis cohort-wave model that batched Apple Metal and CUDA together.)

> The GPU lane is `linux-gpu` in `infernix` and `linux-cuda` in `jitML`; substrate
> identifiers stay per-repo and are not renamed.

## Conformance checklist

A project conforms to this contract when all hold:

- [ ] One binary; role ∈ `{Engine, Coordinator, Webapp}` selected by typed Dhall.
- [ ] Engine is the only role that computes; Webapp and Coordinator run no ML.
- [ ] Webapp is substrate-agnostic (talks to Pulsar + MinIO only).
- [ ] Coordinator owns explicit topic lifecycle; no implicit auto-create, no
      hardcoded topic list.
- [ ] Every topic is derived from the typed descriptor + validated routing graph.
- [ ] Training and inference use the `WorkCommand → WorkEvent* → WorkResult`
      family, correlated by `callId`.
- [ ] A serveable `ArtifactRef` is mintable only from a completed derivation; a
      `.ready` sentinel is written last.
- [ ] The browser receives snapshot + patch frames over websocket; inference is
      asynchronous to the browser.
- [ ] Failover subscriptions + producer dedup provide HA and effectively-once.
- [ ] The binary emits its own (reflected) Dhall schema.
- [ ] Every phase obeys forward-only DAG + single-accelerator-per-phase.

## Related Documents

- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md)
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> Architecture docs that elaborate the project-specific surfaces of this contract
> (`daemon_topology.md`, `engine_pool_routing.md`, `configuration_doctrine.md`,
> `web_ui_architecture.md`, `../tools/pulsar.md`) cross-reference it as the
> convergence work lands; the `documents/` suite map lists it for discovery.
