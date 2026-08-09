# Kubernetes Storage

**Status**: Authoritative source
**Referenced by**: [k8s_native_dev_policy.md](k8s_native_dev_policy.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Define the manual PV doctrine for durable local state.

## Storage Doctrine

- default storage classes are deleted during bootstrap
- `infernix-manual` is the only supported persistent storage class and uses
  `kubernetes.io/no-provisioner`
- every PVC-backed Helm workload explicitly sets `storageClassName: infernix-manual`
- PVCs come only from Helm-owned stateful workloads, including operator-managed claims reconciled
  from repo-owned Helm releases
- PVs are created manually only by `infernix cluster up` and bind explicitly to their intended claims
- no PVC-backed Helm workload relies on dynamic provisioning or an implicit default storage class
`cluster up` renders the Helm release shape, discovers the PVC inventory from that owned chart or
operator input, and prepares one matching PV per claim before workload rollout - PV paths follow
`./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` - the claim
inventory includes Harbor, MinIO, Pulsar, and operator-managed PostgreSQL claims under the path
doctrine above. Retained MinIO model/demo-object data and Pulsar data are durable. Harbor and
Keycloak Patroni roots, Harbor Redis, and the MinIO `harbor-registry` bucket internals are the
narrow rebuildable exception: they may be removed only after a `WriterQuiesced` lease proves Kind
absent under the lifecycle lock, and `cluster up` rebuilds them. **No `infernix` daemon (frontend,
coordinator, or engine) has a PVC**. The coordinator's Pulsar subscription cursors are broker-side
durable. The engine pod has no PVC and uses a single ephemeral `emptyDir` volume mounted at
`/model-cache` with hard `sizeLimit` (default `64Gi`, chart values knob
`engine.modelCache.sizeLimit`); the adapter helper runs LRU eviction inside that quota. The engine's
KV cache is in-memory and rebuilds from the Pulsar conversation log on restart via `prefixHash`. The
`sizeLimit`/LRU quota bounds only the on-disk `emptyDir` cache; model memory is governed separately
by runtime admission. Each model's `modelRamFootprintMib` is compiled against the active Apple host
or Linux CPU pod capacity. Oversized rows remain explicit `UnavailableModel` values; fitting rows
receive indexed grants and must pass live-enforcer refinement before engine launch accepts an
`ExecutableModel`. A Linux GPU plan without independently indexed RAM/VRAM enforcement fails closed
with `GpuDualResourceBudgetRequired` (canonical home
[../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md)). Model
weights themselves live in the `infernix-models` MinIO bucket on the four `64Gi` MinIO data claims
and are streamed into the engine pod's `emptyDir` from the eagerly pre-staged bucket (the
coordinator stages every mounted-config model at startup via the `warm-model-cache` cluster-up
barrier) as documented in [object_storage.md](object_storage.md) and
[../architecture/daemon_topology.md](../architecture/daemon_topology.md).

## Cross-References

- [storage_and_state.md](storage_and_state.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
