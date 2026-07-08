# Kubernetes Storage

**Status**: Authoritative source
**Referenced by**: [k8s_native_dev_policy.md](k8s_native_dev_policy.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Define the manual PV doctrine for durable local state.

## Storage Doctrine

- default storage classes are deleted during bootstrap
- `infernix-manual` is the only supported persistent storage class and uses `kubernetes.io/no-provisioner`
- every PVC-backed Helm workload explicitly sets `storageClassName: infernix-manual`
- durable PVCs come only from Helm-owned durable workloads, including operator-managed claims
  reconciled from repo-owned Helm releases
- durable PVs are created manually only by `infernix cluster up` and bind explicitly to their
  intended claims
- no PVC-backed Helm workload relies on dynamic provisioning or an implicit default storage class
- `cluster up` renders the Helm release shape, discovers the durable PVC inventory from that owned
  chart or operator input, and prepares one matching PV per durable claim before workload rollout
- durable PV paths follow `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- the durable claim inventory includes Harbor, MinIO, Pulsar, and any operator-managed
  PostgreSQL claims under the path doctrine above; **no `infernix` daemon (frontend,
  coordinator, or engine) has a PVC**. The coordinator's Pulsar subscription cursors are
  broker-side durable. The engine pod has no PVC and uses a single ephemeral `emptyDir`
  volume mounted at `/model-cache` with hard `sizeLimit` (default `64Gi`, chart values knob
  `engine.modelCache.sizeLimit`); the adapter helper runs LRU eviction inside that quota.
  The engine's KV cache is in-memory and rebuilds from the Pulsar conversation log on
  restart via `prefixHash`. The `sizeLimit`/LRU quota bounds only the on-disk `emptyDir`
  cache; in-memory inference RAM — resident model weights plus the in-memory KV cache — has no
  per-model or per-substrate budget, so peak resident memory is unbounded and the disk cache alone
  is not a complete resource-safety story. On the `apple-silicon` substrate models run on the on-host
  `infernix service` daemon (no in-cluster engine pod), where a full per-model `infernix test
  integration` over the current catalog exhausts host RAM and the OS SIGKILLs the daemon — an
  uncontrolled process death, not a clean `status=failed`. Inference-RAM admission and a bounded peak
  are a known open gap, targeted by
  [Phase 4 Sprint 4.26](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md) and
  [Phase 6 Sprint 6.37](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md).
  Model weights themselves live in the `infernix-models` MinIO
  bucket on the four `64Gi` MinIO data claims and are streamed into the engine pod's `emptyDir` from
  the eagerly pre-staged bucket (the coordinator stages every mounted-config model at startup via the
  `warm-model-cache` cluster-up barrier) as documented in
  [object_storage.md](object_storage.md) and
  [../architecture/daemon_topology.md](../architecture/daemon_topology.md).

## Cross-References

- [storage_and_state.md](storage_and_state.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
