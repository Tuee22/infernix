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
  volume mounted at `/model-cache` with hard `sizeLimit` (default `32Gi`, chart values knob
  `engine.modelCache.sizeLimit`); the adapter helper runs LRU eviction inside that quota.
  The engine's KV cache is in-memory and rebuilds from the Pulsar conversation log on
  restart via `prefixHash`. Model weights themselves live in the `infernix-models` MinIO
  bucket and are pulled into the engine pod's `emptyDir` on first use through the lazy
  bootstrap workflow documented in
  [object_storage.md](object_storage.md) and
  [../architecture/daemon_topology.md](../architecture/daemon_topology.md).

## Cross-References

- [storage_and_state.md](storage_and_state.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
