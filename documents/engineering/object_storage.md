# Object Storage

**Status**: Authoritative source
**Referenced by**: [model_lifecycle.md](model_lifecycle.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the MinIO-backed durable object storage contract.

## Rules

- MinIO is the durable object authority for runtime artifact bundles, source-artifact manifests or
  payload copies or direct-upstream downloads, protobuf manifests, and large outputs
- Apple host-native runtime flows use the edge-routed `/minio/s3` path
- cluster workloads use the routed surface or cluster-local addressing selected by runtime mode

## Cross-References

- [edge_routing.md](edge_routing.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../tools/minio.md](../tools/minio.md)
