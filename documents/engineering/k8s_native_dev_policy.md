# Kubernetes-Native Development Policy

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Define the supported Kind and Helm workflow for local validation.

## Rules

- Kind is the supported local cluster substrate
- `infernix cluster up` is the only supported cluster reconcile entrypoint
- `infernix cluster down` is the only supported teardown entrypoint
- `bootstrap/*.sh` entrypoints may prepare host prerequisites and build or enter the active
  launcher, but they must not directly create Kind clusters, apply Kubernetes manifests, invoke
  Helm, pull cluster workload images, or publish images; those responsibilities belong to
  `infernix cluster up` and `infernix cluster down`
- `infernix cluster status` does not mutate Kubernetes resources or repo-local authoritative
  state; on the Linux outer-container path it may idempotently attach the fresh launcher container
  to Docker's private `kind` network so it can observe the Kind control plane
- when Docker, Kind, Helm, or kubectl are unavailable, `cluster up` fails fast instead of
  simulating another substrate
- repo-owned Kind configs live under `kind/` and define the Apple, CPU, and `linux-gpu` cluster
  shapes
- repo-owned Helm charts and values live under `chart/`, self-bootstrap the declared Helm
  repositories, and deploy the repo-owned Gateway API, demo, service, publication, and PVC
  workloads on the real cluster path
- every PVC-backed Helm workload on that path explicitly uses `storageClassName: infernix-manual`,
  and `cluster up` manually creates and pre-binds the matching PVs before rollout
- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes
  operator through that same Helm-owned workflow
- `cluster up` bootstraps Harbor first through Helm on a pristine cluster, allowing Harbor and only
  the support services Harbor needs during bootstrap to pull from public container repositories
- after Harbor is ready, `cluster up` uses Harbor as the image authority for every remaining
  non-Harbor pod, mirrors third-party images, and publishes the active `infernix` runtime image
  before the final Helm rollout on every substrate
- because Pulsar is first enabled in the final Harbor-backed Helm phase, `cluster up` forces the
  upstream Pulsar initialization jobs there before final broker or proxy readiness gates close
- `cluster up` renders adapter-specific engine command prefixes from
  `ClusterConfig.engine.commandOverrides` into the cluster ConfigMap so the cluster path can
  supply adapter wrappers without rebuilding the runtime image
- the plan contract for the `linux-gpu` Kind path requires NVIDIA container runtime support
  inside Kind plus usable `nvidia.com/gpu` resources for scheduled workloads
- the supported real-cluster `linux-gpu` path also requires enough host disk headroom for Kind
  image preload, Harbor-backed image publication, and Pulsar BookKeeper durability during final
  rollout

## Cross-References

- [k8s_storage.md](k8s_storage.md)
- [edge_routing.md](edge_routing.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
