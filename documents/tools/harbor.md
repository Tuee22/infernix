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
- Harbor uses a dedicated Patroni cluster managed by the Percona Kubernetes operator for its
  PostgreSQL backend instead of a chart-managed standalone PostgreSQL deployment
- Harbor's PostgreSQL claims follow the same `infernix-manual` plus explicit PV-binding doctrine
  used by every other PVC-backed Helm workload
- the Harbor bootstrap and final Helm phases keep the chart-generated Harbor secret material and
  registry credentials stable so repeat `cluster up` runs do not invalidate Harbor login or image
  publication state
- once Harbor is ready, `cluster up` mirrors third-party images and publishes the active runtime
  image into Harbor before the final non-Harbor rollout
- after Harbor reaches its final rollout shape, `cluster up` preloads the Harbor-backed final
  image refs onto the Kind worker before the remaining non-Harbor workloads are scaled
- the Harbor portal is exposed through `/harbor`
- on the simulated substrate, `/harbor` remains published as a compatibility route for validation
  even though no live Harbor deployment exists

## Cross-References

- [minio.md](minio.md)
- [postgresql.md](postgresql.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
