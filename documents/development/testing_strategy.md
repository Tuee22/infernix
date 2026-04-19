# Testing Strategy

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe the canonical validation surface and the responsibility of each test layer.

## Validation Layers

- `infernix docs check` validates governed docs, plan metadata, and required cross-document phrases
- `infernix test lint` validates repository hygiene, chart or Kind or `.proto` asset presence, Helm dependency or lint or render or claim-discovery closure, the repo-owned Haskell style stack, and the Haskell build path
- `infernix test unit` validates matrix rendering, generated frontend contracts, deterministic runtime behavior, protobuf schema round-trip coverage, engine-adapter metadata, and local-file plus direct-upstream source-artifact materialization
- the host-side unit helper path uses an explicit filesystem-fixture backend plus per-model source-artifact overrides where needed, so unit coverage exercises the durable bundle or source-artifact manifest contract without turning implicit filesystem service fallback into a supported runtime mode
- `infernix test integration` validates lifecycle, generated demo-config publication, serialized-catalog execution, routed publication metadata, process-isolated engine-worker execution, service-path cache lifecycle, Pulsar schema publication, MinIO durability, HA recovery, edge-port rediscovery, and real `linux-cuda` device visibility on supported hosts
- `infernix test e2e` validates the routed browser-facing surface through exhaustive catalog coverage, serialized-catalog cross-checks, and browser UI interaction against the real cluster edge while launching Playwright from the same web image that serves the UI
- `infernix test all` runs the complete repository suite; the default validation matrix exercises Apple and Linux CPU when no explicit runtime-mode override is supplied and auto-includes Linux CUDA when the current host passes the NVIDIA preflight contract on both the Apple host-native and Linux outer-container control-plane surfaces, while the host-native final-substrate lane reuses the Harbor-published web runtime image across the runtime matrix
- the current implementation's validation contract covers the process-isolated engine-worker
  adapter layer, repo-owned engine fixture command injection for automated validation, durable
  runtime bundles, direct-upstream source-artifact manifests, and the real `linux-cuda` Kind path
  on supported NVIDIA hosts
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
- `infernix test integration` also validates that `/api/publication` reports `workerExecutionMode = process-isolated-engine-workers`, `workerAdapterMode = configured-engine-processes`, and that `/api/cache` exposes durable artifact-bundle URIs plus durable source-artifact manifest URIs rooted in the runtime bucket
- the host-native integration lane also validates that `/api` can move to the Apple host bridge without changing the browser-visible edge entrypoint
- `infernix test integration` on the Apple host-native final substrate validates Pulsar protobuf schema registration, MinIO-persisted runtime results or manifests, and Harbor or MinIO or Pulsar HA recovery
- `infernix test e2e` exercises every generated catalog entry exposed through the routed surface for the active runtime mode, compares `/api/models` against the serialized generated catalog reported through `/api/publication`, and fails if the browser workbench cannot render publication details, select a model, or submit one of those entries through the routed cluster edge
- the host-native routed E2E lane also fails if the workbench cannot stay on the same base URL while `/api` resolves through the Apple host bridge
- the host-native and outer-container control-plane paths both delegate `infernix test e2e` browser execution to the same web image that serves `/` rather than the control-plane image, and the host-native final-substrate lane reuses the Harbor-published web runtime image for that browser execution path across `apple-silicon`, `linux-cpu`, and `linux-cuda`
- the automated unit, integration, and E2E entrypoints inject the repo-owned engine fixture command so the process-isolated adapter contract is exercised even when the supported host does not carry every final third-party engine binary or module
- changing the active runtime mode changes the generated catalog and therefore the exercised entry set automatically
- when no explicit runtime-mode override is supplied, the default validation path repeats the exhaustive integration and E2E path across `apple-silicon` and `linux-cpu` and auto-includes `linux-cuda` on hosts that satisfy the NVIDIA preflight contract on both the Apple host-native and Linux outer-container control-plane surfaces
- the supported host-native final-substrate and outer-container control-plane lanes reuse that same exhaustive coverage contract rather than a reduced smoke subset

## Cross-References

- [frontend_contracts.md](frontend_contracts.md)
- [haskell_style.md](haskell_style.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
