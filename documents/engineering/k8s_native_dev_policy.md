# Kubernetes-Native Development Policy

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Define the supported Kind and Helm workflow for local validation.

## Rules

- Kind is the supported local cluster substrate
- `infernix cluster up` is the only supported cluster reconcile entrypoint
- `infernix cluster down` is the only supported teardown entrypoint
- `infernix cluster status` is read-only
- repo-owned Kind configs live under `kind/` and define the Apple, CPU, and CUDA cluster shapes that `cluster up` renders into the supported local Kind clusters
- repo-owned Helm charts and values live under `chart/`, self-bootstrap the declared Helm repositories, and deploy the repo-owned edge, web, service, publication, and PVC workloads on that cluster path
- every PVC-backed Helm workload on that path explicitly uses `storageClassName: infernix-manual`,
  and `cluster up` manually creates and pre-binds the matching PVs before rollout
- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona
  Kubernetes operator through that same Helm-owned workflow
- services or add-ons that can self-deploy PostgreSQL disable that embedded chart path and target
  an operator-managed cluster instead
- `cluster up` bootstraps Harbor first through Helm on a pristine cluster, allowing Harbor and
  only the storage or
  support services Harbor needs during bootstrap, including MinIO and PostgreSQL, to pull from
  public container repositories
- the Harbor bootstrap and final Helm phases preserve stable Harbor-generated secret material and
  registry credentials so repeat `cluster up` runs do not invalidate Harbor login or image
  publication state
- after Harbor is ready, `cluster up` uses Harbor as the image authority for every remaining
  non-Harbor pod, mirrors required third-party images there, and publishes the repo-owned service
  and web images before the final Helm rollout
- after Harbor is ready, every later Helm-managed workload or add-on also pulls from Harbor-backed
  image references rather than public upstream registries
- after Harbor reaches its final rollout shape, `cluster up` preloads the Harbor-backed final
  image refs onto the Kind worker before the remaining non-Harbor workloads are scaled
- because Pulsar is first enabled in the final Harbor-backed Helm phase, `cluster up` forces the
  upstream Pulsar initialization jobs there before the final broker or proxy readiness gates are
  allowed to close
- `cluster up` forwards any `INFERNIX_ENGINE_COMMAND_*` environment variables from the control
  plane into the service deployment so adapter-specific engine command prefixes can be supplied on
  the cluster path without rebuilding the runtime image
- the plan contract for the `linux-cuda` Kind path requires NVIDIA container runtime support inside
  Kind plus usable `nvidia.com/gpu` resources for scheduled workloads
- `cluster up` enforces host-side NVIDIA preflight checks, creates the CUDA cluster through
  `nvkind`, mounts `/var/run/nvidia-container-devices/all` into the GPU worker template, creates
  `RuntimeClass/nvidia` before the device-plugin rollout depends on it, installs the NVIDIA device
  plugin through Helm, and deploys GPU-requesting repo-owned workloads
- `infernix test lint` is the canonical chart gate and proves Helm dependency resolution, `helm lint`, `helm template`, and durable-claim discovery

## Cross-References

- [k8s_storage.md](k8s_storage.md)
- [edge_routing.md](edge_routing.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
