# Testing Strategy

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe the canonical validation surface and the responsibility of each test layer.

## Validation Layers

- `infernix docs check` validates governed docs, plan metadata, and required cross-document phrases
- `infernix test lint` validates repository hygiene, chart or Kind or `.proto` asset presence, Helm dependency or lint or render or claim-discovery closure, the repo-owned Haskell style stack, and the Haskell build path
- `infernix test unit` validates matrix rendering, generated frontend contracts, deterministic runtime behavior, protobuf schema round-trip coverage, engine-adapter metadata, and local-file source-artifact materialization
- `infernix test integration` validates lifecycle, generated demo-config publication, serialized-catalog execution, routed publication metadata, engine-aware managed subprocess worker execution, service-path cache lifecycle, Pulsar schema publication, MinIO durability, HA recovery, and edge-port rediscovery
- `infernix test e2e` validates the routed browser-facing surface through exhaustive catalog coverage, serialized-catalog cross-checks, and browser UI interaction against the real cluster edge while launching Playwright from the same web image that serves the UI
- `infernix test all` runs the complete repository suite; the default validation matrix exercises Apple, Linux CPU, and Linux CUDA when no explicit runtime-mode override is supplied on both the Apple host-native and Linux outer-container control-plane surfaces, while the host-native final-substrate lane reuses the Harbor-published web runtime image across the runtime matrix
- the current implementation's validation contract covers the repo-owned engine-aware managed
  subprocess worker layer, durable runtime bundles, source-artifact manifests, and the shim-backed
  `linux-cuda` scheduling path
- final Phase 4 and Phase 6 closure still require those same suites to validate the final
  third-party engine execution path plus a real NVIDIA-backed Kind substrate, as tracked in
  [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)
  and
  [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

## Active-Mode Coverage Rules

- unit coverage proves the generated catalog shape, selected engine bindings, request-shape rendering, publication-summary rendering, and object-reference result formatting for the active runtime mode
- `infernix test integration` exercises every generated catalog entry from the serialized generated demo config for the active runtime mode, validates the in-cluster `ConfigMap`, and separately validates `cluster status`, `cluster down`, repeated `cluster up`, and `9090`-first edge-port rediscovery on both supported control-plane contexts
- `infernix test integration` also validates the routed `GET /api/cache`, `POST /api/cache/evict`, and `POST /api/cache/rebuild` contract against manifest-backed durable state
- `infernix test integration` also validates that `/harbor`, `/minio/s3`, and `/pulsar/ws` resolve through the current cluster-resident gateway workloads on the shared edge port
- `infernix test integration` also validates that `/api/publication` reports `workerExecutionMode = managed-subprocess-workers`, `workerAdapterMode = engine-aware`, and that `/api/cache` exposes durable artifact-bundle URIs plus durable source-artifact manifest URIs rooted in the runtime bucket
- the host-native integration lane also validates that `/api` can move to the Apple host bridge without changing the browser-visible edge entrypoint
- `infernix test integration` on the Apple host-native final substrate validates Pulsar protobuf schema registration, MinIO-persisted runtime results or manifests, and Harbor or MinIO or Pulsar HA recovery
- `infernix test e2e` exercises every generated catalog entry exposed through the routed surface for the active runtime mode, compares `/api/models` against the serialized generated catalog reported through `/api/publication`, and fails if the browser workbench cannot render publication details, select a model, or submit one of those entries through the routed cluster edge
- the host-native routed E2E lane also fails if the workbench cannot stay on the same base URL while `/api` resolves through the Apple host bridge
- the host-native and outer-container control-plane paths both delegate `infernix test e2e` browser execution to the same web image that serves `/` rather than the control-plane image, and the host-native final-substrate lane reuses the Harbor-published web runtime image for that browser execution path across `apple-silicon`, `linux-cpu`, and `linux-cuda`
- changing the active runtime mode changes the generated catalog and therefore the exercised entry set automatically
- when no explicit runtime-mode override is supplied, the default validation path repeats the exhaustive integration and E2E path across `apple-silicon`, `linux-cpu`, and `linux-cuda` on both the Apple host-native and Linux outer-container control-plane surfaces
- the supported host-native final-substrate and outer-container control-plane lanes reuse that same exhaustive coverage contract rather than a reduced smoke subset

## Cross-References

- [frontend_contracts.md](frontend_contracts.md)
- [haskell_style.md](haskell_style.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
