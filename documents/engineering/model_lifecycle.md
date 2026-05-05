# Model Lifecycle

**Status**: Authoritative source
**Referenced by**: [../architecture/model_catalog.md](../architecture/model_catalog.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define how model manifests, artifacts, outputs, and derived caches move through the
> platform.

## Rules

- the current validated runtime persists durable artifacts, protobuf runtime manifests, and large
  outputs under the repo-local object-store root `./.data/object-store/`, while protobuf-backed
  runtime-result records live under `./.data/runtime/results/*.pb`
- the Haskell worker layer (`src/Infernix/Runtime/{Pulsar,Worker,Cache}.hs`) stores engine-specific
  runtime artifact bundles under `artifacts/<runtime-mode>/<model-id>/bundle.json` and durable
  source-artifact manifests under `source-artifacts/<runtime-mode>/<model-id>/source.json`
- those durable bundles also record engine-adapter id, type, locator, and availability together
  with the authoritative source-artifact URI or kind selected for the current worker path
- the current validated runtime records source-selection metadata in
  `source-artifacts/<runtime-mode>/<model-id>/source.json`; it does not publish a separate
  `payload.bin` compatibility file on the supported path
- repo-owned `.proto` schemas define the contract for durable manifests and topic payloads;
  Haskell consumes them through `proto-lens`-generated bindings, and the shared Python adapter
  project consumes them through matching auto-generated Python protobuf modules in
  `tools/generated_proto/`
- the production daemon (`infernix service`) keeps the topic-shaped request or result contract and
  uses the Pulsar transport configured for the active substrate; unit-level harnesses can still
  exercise the repo-local topic spool under `./.data/runtime/pulsar/` when those endpoints are
  intentionally absent
- engine workers are Haskell processes; for Python-native engines, the worker forks the named
  adapter entrypoint and exchanges typed protobuf worker messages over stdio. The worker passes the
  durable artifact bundle, source manifest, cache manifest, and engine install root into that
  adapter boundary so the shared Python modules can derive engine-family-specific behavior from
  authoritative runtime metadata
- per-adapter bootstrap state lives under `./.data/engines/<adapter-id>/bootstrap.json`; the
  Apple host path and the cluster or worker path both treat that bootstrap manifest as the
  idempotent setup-ready marker
- derived cache state is keyed by runtime mode and model identity and is always rebuildable
- the demo `/api/cache` surface operates on the manifest-backed durable contract exposed by the
  Haskell worker, including engine-runner metadata and selected-artifact inventory derived from the
  durable bundle
- the service returns typed object references when outputs exceed inline limits

## Cross-References

- [object_storage.md](object_storage.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/api_surface.md](../reference/api_surface.md)
