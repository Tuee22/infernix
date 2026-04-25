# Object Storage

**Status**: Authoritative source
**Referenced by**: [model_lifecycle.md](model_lifecycle.md), [../architecture/runtime_modes.md](../architecture/runtime_modes.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Describe the MinIO-backed durable object storage contract.

## Rules

- MinIO is the durable object authority for runtime artifact bundles, source-artifact manifests or
  payload copies or direct-upstream downloads, protobuf manifests, and large outputs
- Apple host-native service placement uses the edge-routed `/minio/s3` path
- cluster-resident service placement uses cluster-local MinIO networking on the supported Kind path
- switching runtime modes changes engine bindings and generated catalog content, not the MinIO
  access path

## Cross-References

- [edge_routing.md](edge_routing.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../tools/minio.md](../tools/minio.md)
