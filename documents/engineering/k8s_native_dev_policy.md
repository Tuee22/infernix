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
- `cluster up` uses Harbor as the image authority for every non-Harbor pod, mirrors required
  third-party images there, and publishes the repo-owned service and web images before the final
  Helm rollout
- `cluster up` forwards any `INFERNIX_ENGINE_COMMAND_*` environment variables from the control
  plane into the service deployment so adapter-specific engine command prefixes can be supplied on
  the cluster path without rebuilding the runtime image
- the plan contract for the `linux-cuda` Kind path requires NVIDIA container runtime support inside
  Kind plus usable `nvidia.com/gpu` resources for scheduled workloads
- the current implementation enforces host-side NVIDIA preflight checks, creates the CUDA cluster
  through `nvkind`, mounts `/var/run/nvidia-container-devices/all` into the GPU worker template,
  installs the NVIDIA device plugin through Helm, and deploys `RuntimeClass/nvidia` plus
  GPU-requesting repo-owned workloads; the remaining supported-host validation work stays open in
  [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)
- `infernix test lint` is the canonical chart gate and proves Helm dependency resolution, `helm lint`, `helm template`, and durable-claim discovery

## Cross-References

- [k8s_storage.md](k8s_storage.md)
- [edge_routing.md](edge_routing.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
