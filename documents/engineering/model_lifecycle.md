# Model Lifecycle

**Status**: Authoritative source
**Referenced by**: [../architecture/model_catalog.md](../architecture/model_catalog.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define how model manifests, artifacts, outputs, and derived caches move through the
> platform.

## Rules

- MinIO is the authoritative home for durable artifacts, protobuf runtime manifests, runtime
  results, and large outputs on both the production Pulsar-driven and demo HTTP-driven service
  paths
- the Haskell worker layer (`src/Infernix/Runtime/{Pulsar,Worker,Cache}.hs`) stores engine-specific
  runtime artifact bundles under `artifacts/<runtime-mode>/<model-id>/bundle.json` in the runtime
  bucket and uses those bundles to point at durable source-artifact manifests under
  `source-artifacts/<runtime-mode>/<model-id>/source.json`
- those durable bundles also record engine-adapter id or type or locator or availability together
  with the authoritative source-artifact URI or kind selected for the current worker path
- when the source URL is a local file, the worker layer copies the payload into
  `source-artifacts/<runtime-mode>/<model-id>/payload.bin`; when the source URL is remote, the
  worker layer materializes direct upstream payloads or provider metadata into the same
  durable prefix through direct HTTP downloads or Hugging Face or GitHub metadata fetches while
  recording engine-specific authoritative artifact selection plus the selected artifact inventory in
  the manifest
- repo-owned `.proto` schemas define the contract for durable manifests and Pulsar payloads;
  Haskell consumes them through `proto-lens`-generated bindings; per-engine Python adapters under
  `python/adapters/<engine>/` consume them through the matching auto-generated Python protobuf
  modules in `tools/generated_proto/`
- the production daemon (`infernix service`) registers protobuf schemas on Pulsar topics for
  requests, results, and coordination messages and consumes those topics directly
- engine workers are Haskell processes; for Python-native engines, the worker now forks the named
  adapter path and exchanges typed protobuf worker messages over stdio. The current adapters keep
  the process boundary and quality gate in place but still return stub output rather than loading
  real engine libraries. Adapters do not open network sockets, write to MinIO, or subscribe to
  Pulsar themselves (see [../development/python_policy.md](../development/python_policy.md))
- derived cache state is keyed by runtime mode and model identity and is always rebuildable
- the demo `/api/cache` surface (served by `infernix-demo` when the demo flag is on) operates on
  the manifest-backed durable contract exposed by the Haskell worker, including engine-runner
  metadata, authoritative source-artifact selection, and selected-artifact inventory derived from
  the durable bundle
- the host-side test helpers keep protobuf manifest fixtures under
  `./.data/object-store/manifests/` for local rebuild or unit coverage and materialize the same
  durable bundle plus source-artifact-manifest contract through Haskell test fixtures under
  `test/unit/`
- the service returns typed object references when outputs exceed inline limits

## Cross-References

- [object_storage.md](object_storage.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/api_surface.md](../reference/api_surface.md)
