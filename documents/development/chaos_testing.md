# Chaos Testing

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Record the supported HA-failure coverage for Harbor, MinIO, operator-managed
> PostgreSQL, and Pulsar.

## Current Status

- the real-cluster `linux-cpu` integration lane now includes supported automated HA-failure
  checks for Harbor, MinIO, Patroni PostgreSQL, and Pulsar
- Harbor coverage deletes one `infernix-harbor-core` pod, waits for the deployment rollout, then
  proves a fresh `imagePullPolicy: Always` pod can pull the Harbor-backed `infernix-engine` image
- MinIO coverage writes a sentinel file to the mounted MinIO data volume, deletes one MinIO pod,
  waits for that pod to return, and asserts the sentinel remains readable afterward
- Pulsar coverage publishes one routed request or result before replacing a broker pod and a second
  routed request or result after that broker is ready again
- PostgreSQL coverage deletes the Harbor Patroni primary, waits for a different primary pod to
  become ready, and separately compares the deterministic Harbor PostgreSQL PV inventory plus
  host-path mapping across `cluster down` plus `cluster up`
- HA-failure ownership lives on the real Kind-backed lane rather than a separate Apple-only matrix:
  the Apple host-native workflow reuses the same routed Harbor, MinIO, Patroni PostgreSQL, and
  Pulsar cluster services while keeping inference host-native
- route, publication, cache, and service-loop coverage that does not require pod-failure injection
  is owned by the ordinary unit, integration, and routed E2E entrypoints
- the integration suite covers the non-chaos coordinator-to-engine handoff contract through
  publication JSON, `cluster status`, generated demo config, and the active service runtime loop
- the integration suite covers the non-chaos durable-context prompt path through dispatcher,
  request/batch handoff, engine, result bridge, and conversation-log writeback
- the `linux-cpu` integration lane covers frontend pod replacement, coordinator pod replacement,
  engine pod replacement, engine node drain, model-bootstrap deduplication across coordinator
  replacement, Linux engine anti-affinity, compact multi-user durable prompt throughput, exact
  broker counts, production-shape deployment, and clean teardown

## Durable-Context Demo Chaos Cases

The integration chaos suite covers the durable-context demo. The cases below exercise the
failure semantics described in
[../architecture/daemon_topology.md § Failure Semantics per Role](../architecture/daemon_topology.md#failure-semantics-per-role)
and [../architecture/durable_context_design.md](../architecture/durable_context_design.md).
Each case asserts exactly-once outcome and full state preservation through Pulsar Failover
redelivery, Pulsar producer-side deduplication, and projection-layer idempotency:

- **Frontend (WS-hosting) pod kill mid-session.** Open a WS, exchange a few messages, kill the
  `infernix-demo` pod holding the WS, assert the client transparently reconnects to a surviving
  replica and resumes state from Pulsar with no losses.
- **Coordinator pod kill mid-dispatch.** Submit a prompt, kill the active
  `infernix-coordinator` replica between the `UserPrompt` publish and the inference-request
  publish, assert Pulsar Failover promotes a surviving replica, the new dispatcher reaches
  the same decision via the pure-fold rule, and Pulsar producer dedup on
  `inference.request.<mode>` (keyed by `userPromptMessageId`) prevents a duplicate dispatch.
- **Coordinator pod kill mid-result-bridge.** Submit a prompt that returns a result, kill the
  active `infernix-coordinator` replica between the inference-result arrival and the conversation
  topic writeback, assert Pulsar Failover promotes a surviving replica that writes the result
  exactly once via producer dedup on the conversation topic (keyed by
  `(userPromptMessageId, kind = InferenceResult)`).
- **Engine pod kill mid-inference.** Submit a prompt, kill the active `infernix-engine` pod
  mid-inference, assert Pulsar redelivers the unacked batch message to a surviving engine pod
  on another node, that engine rebuilds the KV cache from the conversation log via the shared
  reducer + hash modules, and Pulsar producer dedup on `inference.result.<mode>` (keyed by
  `userPromptMessageId`) prevents a duplicate result.
- **Engine node drain.** Drain a node hosting an engine pod, assert the engine PDB blocks the
  drain until at least one other engine pod is available cluster-wide, and the cluster keeps
  serving inference throughout.
- **Coordinator pod kill mid-bootstrap upload.** Submit an inference request for a model
  that is not yet present in `infernix-models`, kill the active `infernix-coordinator`
  replica after some weight files have PUT to `infernix-models/<modelId>/` but before the
  `.ready` sentinel; assert a surviving coordinator replica resumes (the Failover subscription,
  attempt-scoped request dedup, and MinIO `.ready` guard prevent duplicate effective population),
  the `.ready` sentinel appears exactly once, and waiting engine pods observe the ready event and
  proceed.
- **Concurrent model-bootstrap requests.** N engine pods request the same uncached model
  simultaneously; assert Pulsar Failover plus the MinIO `.ready` guard guarantees exactly one
  effective population, the `.ready` sentinel appears exactly once, and all N engine pods observe it
  and proceed.
- **Engine placement and pool ownership.** On Linux, scaling a pool beyond its legal placement leaves
  the extra replica unschedulable with the expected Kubernetes placement diagnostic. On Apple,
  multiple distinct host ids may subscribe to a shared model pool and broker backpressure distributes
  work to members with capacity; pinned host routes use `Exclusive` and reject duplicate consumers.
- **Engine model-memory admission failure (clean-fail by construction).** Every active substrate
  resolves an explicit `InferenceMemoryBudget`: Apple unified host RAM after the Colima pledge and
  host reserve, Linux CPU engine pod RAM, or Linux GPU VRAM. Every model carries
  `ModelDescriptor.modelRamFootprintMib`. Immediately before the engine launches, the shared
  admission policy compares the footprint against the active enforced budget. A model whose
  footprint exceeds the budget publishes a clean per-row `status=failed` with typed
  `InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` and is
  not launched. Configuration validation may surface capacity diagnostics, but it must not fail the
  whole daemon solely because one catalog model is too large; smaller models must continue to run.
  Tests classify this constructor as clean capacity failure, distinct from a missing result/stall or
  fabricated pass. This is owned by reopened Phase 4 Sprint 4.27, Phase 5 Sprint 5.11, and Phase 6
  Sprint 6.38. The target invariant — a grant-gated capped engine (admitted `MemoryGrant`, OS-bounded
  ceiling) makes a host OOM structurally unrepresentable — is owned canonically by
  [../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md).
- **Test-harness SIGKILL mid-mutation (dirty-cluster reconcile).** A `HarnessOwned`
  `infernix test all` that is externally killed while it is actively mutating the cluster — mid
  node-drain or mid pool over-scale (the **Engine node drain** and **Engine placement and pool
  ownership** cases above are the mutation exemplars) — leaves a first-class `ClusterMutating`
  position persisted rather than an operator-idle `ClusterReady`. `cluster status` reports a
  mutation-incomplete (dirty) phase, not a false `steady-state`, and the next `cluster up` reconciles
  it — uncordoning the drained node and scaling the over-scaled deployment back — through the
  reconcile-on-next-start repair. Code-side closed (2026-07-23): the `ClusterMutating` position and
  reconcile (Phase 2 Sprint 2.15) and the harness's evidence-gated `HarnessOwned` seizure (Phase 6
  Sprint 6.43) are implemented and closed under Wave X (2026-07-24). Canonical home:
  [Managed State Transitions](../architecture/managed_state_transitions.md).

The `linux-cpu` integration lane implements these cases as pod replacement, node-drain, and
deduplicated bootstrap replay checks against the real Kind cluster. They run alongside the
existing Harbor / MinIO / Patroni / Pulsar HA coverage. See
[demo_app_test_plan.md](demo_app_test_plan.md) for the full validation contract.

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../tools/harbor.md](../tools/harbor.md)
- [../tools/minio.md](../tools/minio.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../tools/pulsar.md](../tools/pulsar.md)
- [demo_app_test_plan.md](demo_app_test_plan.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
