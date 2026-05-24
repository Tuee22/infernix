# Model Lifecycle

**Status**: Authoritative source
**Referenced by**: [../architecture/model_catalog.md](../architecture/model_catalog.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define how model manifests, artifacts, outputs, and derived caches move through the
> platform.

## Rules

- the supported runtime persists model weights in MinIO `infernix-models`
  (always-on, populated lazily by the coordinator's bootstrap Failover
  subscription on first use) and user-visible artifacts in MinIO
  `infernix-demo-objects` (demo-gated). Protobuf-backed runtime-result
  records live under `./.data/runtime/results/*.pb`; the previous local
  object-store tree under `./.data/object-store/` is retired (see
  [object_storage.md](object_storage.md))
- the Haskell worker layer (`src/Infernix/Runtime/{Pulsar,Worker,Cache}.hs`)
  stores cache manifests beside the cached weights at
  `./.data/runtime/model-cache/<runtime-mode>/<model-id>/manifest.pb`;
  durable artifact bundles, source-artifact manifest JSON files, and
  the `s3://infernix-runtime/...` URI scheme were retired in Phase 7
  Sprint 7.7
- the durable source URI recorded on cache manifests is now
  `minio://infernix-models/<modelId>/` rather than a synthetic local
  filesystem path
- repo-owned `.proto` schemas define the contract for durable manifests and topic payloads;
  Haskell consumes them through `proto-lens`-generated bindings, and the shared Python adapter
  project consumes them through matching auto-generated Python protobuf modules in
  `tools/generated_proto/`
- production daemons (`infernix service`) keep the topic-shaped request, host-batch, and result
  contract and use the Pulsar transport configured for the active substrate; unit-level harnesses
  can still exercise the repo-local topic spool under `./.data/runtime/pulsar/` when those
  endpoints are intentionally absent
- on `apple-silicon`, cluster daemons own inbound request consumption and batch handoff to the
  configured host topic, while same-binary host daemons execute Apple-native inference and publish
  the completed result. On Linux substrates, cluster daemons consume, execute, and publish the
  result directly.
- engine workers are Haskell processes; for Python-native engines, the worker forks the named
  adapter entrypoint and exchanges typed protobuf worker messages over stdio. The worker passes
  the model metadata (`display_name`, `family`, `artifact_type`,
  `runtime_lane`, `selected_engine`, `adapter_id`, `engine_install_root`) directly on the
  `WorkerRequest` envelope; the adapter calls
  `python/adapters/model_cache.get_model_path(model_id)` to obtain the on-disk path to the
  weights pulled lazily from MinIO `infernix-models`. The retired `artifact_bundle_path`,
  `source_manifest_path`, and `cache_manifest_path` envelope fields are gone.
- per-adapter bootstrap state lives under `./.data/engines/<adapter-id>/bootstrap.json`; the
  Apple host path and the cluster or worker path both treat that bootstrap manifest as the
  idempotent setup-ready marker
- derived cache state is keyed by runtime mode and model identity and is always rebuildable
- the demo `/api/cache` surface operates on the manifest-backed contract exposed by the Haskell
  worker; the manifest reads the supported `minio://infernix-models/<modelId>/` durable source
  URI and the engine-runner metadata derived from the staged substrate `.dhall`
- engine adapters write binary outputs directly into MinIO
  `infernix-demo-objects` at the per-user prefix and the result message carries an
  `ObjectRef` (bucket + key); text outputs always ride inline in the protobuf result message
  (the retired 80-character threshold + local object-store overflow path is gone)

## Cross-References

- [object_storage.md](object_storage.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/api_surface.md](../reference/api_surface.md)
