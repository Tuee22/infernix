# Model Lifecycle

**Status**: Authoritative source
**Referenced by**: [../architecture/model_catalog.md](../architecture/model_catalog.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define how model manifests, artifacts, outputs, and derived caches move through the
> platform.

## Rules

- MinIO is the authoritative home for durable artifacts, protobuf runtime manifests, runtime
  results, and large outputs on the routed service path
- repo-owned `.proto` schemas define the contract for durable manifests and Pulsar payloads
- the routed service path registers protobuf schemas on Pulsar topics for requests, results, and
  coordination messages
- derived cache state is keyed by runtime mode and model identity and is always rebuildable
- the routed `/api/cache` surface operates on the manifest-backed durable contract exposed by the
  service runtime
- the host-side CLI cache helpers still keep protobuf manifest fixtures under
  `./.data/object-store/manifests/` for local rebuild or unit coverage
- the service returns typed object references when outputs exceed inline limits

## Cross-References

- [object_storage.md](object_storage.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/api_surface.md](../reference/api_surface.md)
