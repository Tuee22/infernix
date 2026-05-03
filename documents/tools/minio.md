# MinIO

**Status**: Authoritative source
**Referenced by**: [../engineering/object_storage.md](../engineering/object_storage.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported MinIO role in the local platform.

## Rules

- MinIO is the chart-owned object-store target on the supported Kind path
- the current validated runtime persists durable object-store data under `./.data/object-store/`
- MinIO runs as a four-node distributed cluster on the supported Kind path
- on a pristine cluster, MinIO may pull from public container repositories only when it is one of
  Harbor's required backend services before Harbor becomes pull-ready
- the chart values reserve the `infernix-runtime` and `infernix-results` buckets for the real
  cluster path
- the real non-simulated `linux-cpu` integration lane writes a sentinel file through the MinIO
  data volume, replaces one MinIO pod, and asserts the sentinel remains readable afterward

## Routed Surfaces

<!-- infernix:route-registry:minio:start -->
- `/minio/console` -> `infernix-minio-console:9090`; rewrites to upstream `/`
- `/minio/s3` -> `infernix-minio:9000`; rewrites to upstream `/`
<!-- infernix:route-registry:minio:end -->
- on the real cluster path, `/minio/console/browser` returns the live MinIO console HTML and
  `/minio/s3/...` reaches the live S3 surface

## Cross-References

- [pulsar.md](pulsar.md)
- [harbor.md](harbor.md)
- [postgresql.md](postgresql.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
