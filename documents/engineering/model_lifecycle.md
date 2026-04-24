# Model Lifecycle

**Status**: Authoritative source
**Referenced by**: [../architecture/model_catalog.md](../architecture/model_catalog.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define how model manifests, artifacts, outputs, and derived caches move through the
> platform.

## Rules

- MinIO is the authoritative home for durable artifacts, protobuf runtime manifests, runtime
  results, and large outputs on the routed service path
- the routed worker layer stores engine-specific runtime artifact bundles under
  `artifacts/<runtime-mode>/<model-id>/bundle.json` in the runtime bucket and uses those bundles
  to point at durable source-artifact manifests under
  `source-artifacts/<runtime-mode>/<model-id>/source.json`
- those durable bundles also record engine-adapter id or type or locator or availability together
  with the authoritative source-artifact URI or kind selected for the current worker path
- when the source URL is a local file, the routed worker layer also copies the payload into
  `source-artifacts/<runtime-mode>/<model-id>/payload.bin`; when the source URL is remote, the
  routed worker layer materializes direct upstream payloads or provider metadata into the same
  durable prefix through direct HTTP downloads or Hugging Face or GitHub metadata fetches while
  recording engine-specific authoritative artifact selection plus the selected artifact inventory in
  the manifest
- repo-owned `.proto` schemas define the contract for durable manifests and Pulsar payloads
- the routed service path registers protobuf schemas on Pulsar topics for requests, results, and
  coordination messages
- derived cache state is keyed by runtime mode and model identity and is always rebuildable
- the routed `/api/cache` surface operates on the manifest-backed durable contract exposed by the
  service runtime, including engine-runner metadata, authoritative source-artifact selection, and
  selected-artifact inventory derived from the durable bundle
- the host-side CLI or unit helpers keep protobuf manifest fixtures under
  `./.data/object-store/manifests/` for local rebuild or unit coverage, and they now materialize
  the same durable bundle plus source-artifact-manifest contract through an explicit local
  fixture helper rather than writing placeholder bundle metadata
- the service returns typed object references when outputs exceed inline limits

## Cross-References

- [object_storage.md](object_storage.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/api_surface.md](../reference/api_surface.md)
