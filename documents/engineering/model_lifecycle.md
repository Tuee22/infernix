# Model Lifecycle

**Status**: Authoritative source
**Referenced by**: [../architecture/model_catalog.md](../architecture/model_catalog.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define how model manifests, artifacts, outputs, and derived caches move through the
> platform.

## Rules

- the current validated runtime persists durable artifacts, protobuf runtime manifests, runtime
  results, and large outputs under the repo-local object-store root `./.data/object-store/`
- the Haskell worker layer (`src/Infernix/Runtime/{Pulsar,Worker,Cache}.hs`) stores engine-specific
  runtime artifact bundles under `artifacts/<runtime-mode>/<model-id>/bundle.json` and durable
  source-artifact manifests under `source-artifacts/<runtime-mode>/<model-id>/source.json`
- those durable bundles also record engine-adapter id, type, locator, and availability together
  with the authoritative source-artifact URI or kind selected for the current worker path
- when the source URL is a local file, the worker layer copies the payload into
  `source-artifacts/<runtime-mode>/<model-id>/payload.bin`; when the source URL is remote, the
  worker layer materializes direct upstream payloads or provider metadata into the same durable
  prefix
- repo-owned `.proto` schemas define the contract for durable manifests and topic payloads;
  Haskell consumes them through `proto-lens`-generated bindings, and per-substrate Python adapters
  consume them through the matching auto-generated Python protobuf modules in `tools/generated_proto/`
- the production daemon (`infernix service`) keeps the topic-shaped request or result contract and
  uses real Pulsar WebSocket or admin endpoints when the Pulsar environment variables are present;
  without them it falls back to the filesystem simulation under `./.data/runtime/pulsar/`
- engine workers are Haskell processes; for Python-native engines, the worker forks the named
  adapter entrypoint and exchanges typed protobuf worker messages over stdio. The current adapters
  keep the process boundary and quality gate in place but still return stub output rather than
  loading real engine libraries
- derived cache state is keyed by runtime mode and model identity and is always rebuildable
- the demo `/api/cache` surface operates on the manifest-backed durable contract exposed by the
  Haskell worker, including engine-runner metadata and selected-artifact inventory derived from the
  durable bundle
- the service returns typed object references when outputs exceed inline limits

## Cross-References

- [object_storage.md](object_storage.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/api_surface.md](../reference/api_surface.md)
