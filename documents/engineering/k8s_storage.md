# Kubernetes Storage

**Status**: Authoritative source
**Referenced by**: [k8s_native_dev_policy.md](k8s_native_dev_policy.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

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
- the durable claim inventory includes service, Harbor, MinIO, Pulsar, and any operator-managed
  PostgreSQL claims under that same path doctrine

## Cross-References

- [storage_and_state.md](storage_and_state.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
