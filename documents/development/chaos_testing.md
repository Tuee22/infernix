# Chaos Testing

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Record the supported HA-failure coverage for Harbor, MinIO, operator-managed
> PostgreSQL, and Pulsar.

## Current Status

- the real-cluster `linux-cpu` integration lane now includes supported automated HA-failure
  checks for Harbor, MinIO, Patroni PostgreSQL, and Pulsar
- Harbor coverage deletes one `infernix-harbor-core` pod, waits for the deployment rollout, then
  proves a fresh `imagePullPolicy: Always` pod can still pull the Harbor-backed `infernix-service`
  image
- MinIO coverage writes a sentinel file to the mounted MinIO data volume, deletes one MinIO pod,
  waits for that pod to return, and asserts the sentinel remains readable afterward
- Pulsar coverage publishes one routed request or result before replacing a broker pod and a second
  routed request or result after that broker is ready again
- PostgreSQL coverage deletes the Harbor Patroni primary, waits for a different primary pod to
  become ready, and separately compares the deterministic Harbor PostgreSQL PV inventory plus
  host-path mapping across `cluster down` plus `cluster up`
- the fresh outer-container `linux-cpu` rerun of that HA coverage passed on April 29, 2026
- HA-failure ownership lives on the real Kind-backed lane rather than a separate Apple-only matrix:
  the Apple host-native workflow reuses the same routed Harbor, MinIO, Patroni PostgreSQL, and
  Pulsar cluster services while keeping inference host-native
- route, publication, cache, and service-loop coverage that does not require pod-failure injection
  remains owned by the ordinary unit, integration, and routed E2E entrypoints

## Durable-Context Demo Chaos Cases (Planned, Phase 7)

When the durable-context demo lands, the supported integration suite gains chaos cases that
exercise the failure semantics described in
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
  `.ready` sentinel; assert a surviving coordinator replica resumes (producer dedup on
  `infernix/system/model.bootstrap.request` prevents a duplicate upstream download), the
  `.ready` sentinel appears exactly once, and waiting engine pods observe the ready event
  and proceed.
- **Concurrent model-bootstrap requests.** N engine pods request the same uncached model
  simultaneously; assert producer dedup + Pulsar Failover guarantees exactly one upstream
  download, the `.ready` sentinel appears exactly once, and all N engine pods observe it
  and proceed.
- **One-engine-per-node enforcement.** On Linux,
  `kubectl scale deployment/infernix-engine --replicas=N+1` (where N = engine-capable nodes)
  leaves one replica `Pending` with the anti-affinity rejection message; on Apple,
  launching a second `infernix service` on the same host while one is already running exits
  non-zero with the `engine.lock held by PID …` diagnostic.

These cases land in Sprint 7.14 (post-renumber) alongside the existing Harbor / MinIO /
Patroni / Pulsar HA coverage. See [demo_app_test_plan.md](demo_app_test_plan.md) for the
full validation contract.

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
