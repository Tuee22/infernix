# MinIO

**Status**: Authoritative source
**Referenced by**: [../engineering/object_storage.md](../engineering/object_storage.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported MinIO role in the local platform.

## Rules

- MinIO is the authoritative object store
- MinIO runs as a four-node distributed cluster on the supported Kind path
- the routed service runtime stores runtime artifact bundles, source-artifact manifests or payload
  previews, and protobuf manifests in the `infernix-runtime` bucket and stores runtime results in
  the `infernix-results` bucket
- the MinIO console is exposed through `/minio/console`
- the MinIO S3 API is exposed through `/minio/s3`

## Cross-References

- [pulsar.md](pulsar.md)
- [harbor.md](harbor.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
