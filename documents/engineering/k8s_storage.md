# Kubernetes Storage

**Status**: Authoritative source
**Referenced by**: [k8s_native_dev_policy.md](k8s_native_dev_policy.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Define the manual PV doctrine for durable local state.

## Storage Doctrine

- default storage classes are deleted during bootstrap
- `infernix-manual` is the only supported persistent storage class
- durable PVCs come only from Helm-managed workloads
- durable PVs come only from `infernix cluster up`
- `cluster up` renders the Helm chart, discovers the PVC inventory from that output, and prepares one matching PV per durable claim before workload rollout
- durable PV paths follow `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- the current platform claim inventory prepares one service claim, three Harbor registry claims,
  four MinIO data claims, and three Pulsar ledger claims under that path doctrine

## Cross-References

- [storage_and_state.md](storage_and_state.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
