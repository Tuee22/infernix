# Harbor

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported Harbor role in the local platform.

## Rules

- Harbor is the local image authority for every non-Harbor cluster workload
- Harbor may bootstrap from upstream before the local registry is available
- `cluster up` mirrors third-party images and publishes repo-owned service and web images into
  Harbor before the final Helm rollout
- repeated `cluster up` runs compare local and remote digests where available and skip unnecessary
  pushes
- `cluster up` waits for Harbor to be pull-ready before final non-Harbor rollout continues
- Harbor application-plane workloads run with the chart-managed HA replica inventory on the
  supported Kind path
- the Harbor portal is exposed through `/harbor`

## Cross-References

- [minio.md](minio.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
