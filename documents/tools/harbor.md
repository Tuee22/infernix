# Harbor

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported Harbor role in the local platform.

## Rules

- Harbor is the local image authority for every non-Harbor cluster workload on the real Kind path
- Harbor is always the first deployed service on a pristine cluster
- `cluster up` deploys Harbor first through Helm and allows Harbor plus only the storage or
  support services Harbor needs during bootstrap, including MinIO and PostgreSQL, to pull from
  public container repositories while Harbor is not yet available
- bootstrap shell scripts never pull or publish Harbor images directly; the `infernix` binary owns
  Harbor readiness, mirroring, runtime-image publication, and final rollout sequencing
- Harbor uses a dedicated Patroni cluster managed by the Percona Kubernetes operator for its
  PostgreSQL backend instead of a chart-managed standalone PostgreSQL deployment
- Harbor's PostgreSQL claims follow the same `infernix-manual` plus explicit PV-binding doctrine
  used by every other PVC-backed Helm workload
- the Harbor bootstrap and final Helm phases keep the chart-generated Harbor secret material and
  registry credentials stable so repeat `cluster up` runs do not invalidate Harbor login or image
  publication state
- once Harbor is ready, `cluster up` mirrors every remaining third-party image and publishes the
  active `infernix` runtime image into Harbor before the final non-Harbor rollout on every
  substrate
- after Harbor reaches its final rollout shape, `cluster up` preloads the Harbor-backed final
  image refs onto the Kind worker before the remaining non-Harbor workloads are scaled

## Host Port

Harbor's in-cluster Kubernetes NodePort is fixed at `30002` so chart references, the
containerd registry-hosts mappings inside Kind nodes, and the harbor sub-chart resolution
stay deterministic. The Kind `hostPort` mapping observed from the operator host is selected
dynamically by `cluster up` (`chooseHarborPort` in `src/Infernix/Cluster.hs`), starting at
`30002` and incrementing until an open port is found, and persisted under
`./.data/runtime/harbor-port.json`. The chosen port appears in `cluster status` as
`harborPort` alongside `edgePort`. This mirrors Section O of
`DEVELOPMENT_PLAN/development_plan_standards.md` (the edge port pattern). Operators on hosts
where unrelated processes hold port `30002` see `cluster up` select e.g. `30003`
automatically; the binary's Harbor health probe, the publication path's `docker push` /
`docker pull verify` targets, and the containerd registry-hosts namespace name all follow
the chosen port.

Containerd inside each Kind node honors the hosts.toml mappings under
`/etc/containerd/certs.d/<namespace>/hosts.toml` only when `config_path` is enabled in
`/etc/containerd/config.toml`. Kind 0.31 does not emit this by default, so `renderKindConfig`
in `src/Infernix/Cluster.hs` ships a `containerdConfigPatches` block that sets
`[plugins."io.containerd.grpc.v1.cri".registry] config_path = "/etc/containerd/certs.d"`.
The patch is part of the supported Kind config contract; see
[../engineering/docker_policy.md](../engineering/docker_policy.md) for additional context.

## Routed Surfaces

<!-- infernix:route-registry:harbor:start -->
- `/harbor/api` -> `infernix-harbor-core:80`; rewrites to upstream `/api`
- `/harbor` -> `infernix-harbor-portal:80`; rewrites to upstream `/`
<!-- infernix:route-registry:harbor:end -->

## Cross-References

- [minio.md](minio.md)
- [postgresql.md](postgresql.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
