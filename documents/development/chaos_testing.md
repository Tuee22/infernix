# Chaos Testing

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

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

When the durable-context demo lands, the supported integration suite gains three additional
chaos cases that exercise the failure semantics described in
[../architecture/demo_app_design.md](../architecture/demo_app_design.md). Each case asserts
exactly-once outcome and full state preservation through Pulsar Failover redelivery, Pulsar
producer-side deduplication, and projection-layer idempotency:

- **WS-hosting demo pod kill mid-session.** Open a WS, exchange a few messages, kill the pod
  holding the WS, assert the client transparently reconnects to a surviving replica and
  resumes state from Pulsar with no losses.
- **Dispatcher pod kill mid-prompt.** Submit a prompt, kill the active dispatcher pod between
  the `UserPrompt` publish and the inference-request publish, assert Pulsar Failover promotes
  a surviving pod, the new dispatcher reaches the same decision via the pure-fold rule, and
  Pulsar producer dedup on `inference.request.<mode>` (keyed by `userPromptMessageId`)
  prevents a duplicate dispatch.
- **Cluster daemon kill mid-inference.** Submit a prompt, kill the cluster daemon pod
  mid-inference, assert Pulsar redelivers the unacked inference request to a surviving pod,
  that engine rebuilds the KV cache from the conversation log via the shared reducer + hash
  modules, and Pulsar producer dedup on `inference.result.<mode>` (keyed by
  `userPromptMessageId`) prevents a duplicate result.

These cases land in Sprint 7.13 alongside the existing Harbor / MinIO / Patroni / Pulsar HA
coverage. See [demo_app_test_plan.md](demo_app_test_plan.md) for the full validation contract.

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../tools/harbor.md](../tools/harbor.md)
- [../tools/minio.md](../tools/minio.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../tools/pulsar.md](../tools/pulsar.md)
- [demo_app_test_plan.md](demo_app_test_plan.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
