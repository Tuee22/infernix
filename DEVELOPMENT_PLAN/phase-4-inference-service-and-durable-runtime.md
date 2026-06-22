# Phase 4: Inference Service and Durable Runtime

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Define the Haskell service runtime, the shared Python engine-adapter contract, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the shared Linux substrate image, the
> substrate-generated `.dhall` role contract, and the Apple host inference bootstrap that together
> make the runtime model honest and durable.

## Phase Status

> **Common-shape reopen (Pulsar ML-Workflow convergence).** Phase 4's two
> common-shape deltas toward the shared contract (see [README.md](README.md) →
> Common-Shape Reopen and [development_plan_standards.md](development_plan_standards.md)
> §Q) are code-side closed: the **Coordinator** owns explicit Pulsar topic-lifecycle
> reconciliation from the typed runtime graph, replacing implicit broker
> auto-create reliance, and the binary emits its own decoder-reflected Dhall
> schema through `infernix internal dhall-schema host|cluster|secrets|substrate`.
> The checked-in `dhall/Infernix{Host,Cluster,Secrets,Substrate}.dhall` schema files now
> contain the reflected output, and `infernix lint docs` drift-checks them against the
> in-binary renderer.

Phase 4 closes around the staged-substrate runtime contract, the shared Python
adapter boundary, the Pulsar-driven request or result contract, the explicit engine-runner
dispatch, the mounted `InfernixCluster.dhall` cluster-wiring contract, and the reopened
substrate-neutral engine-pool routing contract. The runtime, catalog, cache, object-storage,
daemon-role, and substrate-file contracts have prior closure evidence from Wave A (Apple) and
Wave C (CUDA Linux), but Sprint 4.19 reopens the routing schema and runtime contract so Apple,
Linux CPU, and Linux GPU use one pool graph with derived topics and broker-native backpressure.
The inference contract itself is code-side complete for dispatch shape: the worker resolves the
selected engine entrypoint for every supported matrix row and publishes the typed per-family result
surface. The code-side closure for the reopened sprints
(4.1, 4.2, 4.3, 4.7, 4.8, 4.10, 4.11, 4.12, 4.14) and Sprint 4.15 — the typed contracts, payload
routing, proto fields, adapter and worker dispatch, the native-fallback removal, and their unit
coverage — is **Complete** and was proven by the machine-independent gate set (`cabal build all`,
`cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`,
`infernix docs check`, `poetry run check-code`) on the recorded CUDA Linux host (x86_64 + RTX 5090).
The phase is `Done` after the 2026-06-20 CUDA Linux closure on the selected `linux-gpu`
accelerator plus `linux-cpu`, per [development_plan_standards.md](development_plan_standards.md)
Section Q. The real per-family inference contract was re-validated through the Wave I
`linux-gpu` plus `linux-cpu` attestation, and the current Apple integration rerun continues to
prove the coordinator-routing/member-subscription path for the
active catalog: the coordinator loads the mounted Apple substrate config, runs with
`serviceRuntimeMode: apple-silicon`, publishes to the derived Apple pool topic, and the host engine
processes the request. The Apple transformers framework path completes
`llm-qwen25-safetensors`, and the Apple native adapter ids (including `llm-tinyllama-gguf`) resolve
to deterministic validation-wrapper payloads. The Apple integration lane completes the active Apple
model catalog through the host engine daemon, cache lifecycle, service runtime loop, durable Pulsar
topic families, pinned Apple host-engine `Exclusive` duplicate-consumer rejection through an
isolated `infernix service --config` file, same-machine Apple host-member coexistence on one derived
`Shared` pool subscription with two real Pulsar consumers and a completed request, the single-host
logical `Shared` backlog/backpressure harness, production-shape Apple `demo_ui = false`
route/publication assertions, and edge-port conflict rediscovery. The cluster image path uses
source-fingerprint image reuse and dependency-layer caching, so a long Docker interval reflects
Cabal dependency compilation, image export, Harbor push, and Helm/Pulsar readiness waits rather than
a Docker daemon deadlock. Routed Apple `./.build/infernix test e2e` passes 9/9: prompt upload refs
are preserved through single-flight dispatch, object-input catalog families (including
`audio-demucs-htdemucs`) carry an `inputObjectRef`, and the engine-side model-bootstrap readiness
wait uses a 3600-second cold-start envelope aligned with the browser result wait so a cold Hugging
Face snapshot for `llm-qwen25-safetensors` is not treated as a failure. The full Apple
`./.build/infernix test all` aggregate passes lint, unit, integration, and 9/9 routed Playwright
across every active Apple catalog row.
The 2026-06-16 Linux CPU validation rebuilt `infernix-linux-cpu:local` to digest
`sha256:ae06ba36fe1f3ffecf48aa86c34abeb0dd1c98cabb030a7da783681ac87a81df` and passed the
Kind-backed integration lane through Kubernetes-observed engine-pool placement, unique-topic
`Shared` backlog/backpressure, pod replacement, node drain, anti-affinity, lifecycle rebinding,
demo-off publication, and the Linux CPU `transformers`/`pytorch` framework-venv smoke paths.
The 2026-06-18 Linux CPU rebuilt-image validation closes the Phase 4 common-shape
topic/schema code-side scope: `./bootstrap/linux-cpu.sh build` passed, all four
`infernix internal dhall-schema host|cluster|secrets|substrate` variants emitted non-empty
schema text, and the rebuilt-image `infernix test unit` compose invocation passed the Haskell unit
suite plus the PureScript web suite (`71/71`).
The 2026-06-20 CUDA Linux pass closed that residual: `./bootstrap/linux-gpu.sh test` passed the
full Haskell style, Haskell unit, web unit, integration, and routed Playwright gates, including the
16-row `linux-gpu` per-model browser matrix over framework-specific and native rows; the matching
rebuilt `./bootstrap/linux-cpu.sh test` passed the same full lane, including Linux CPU integration
and 9/9 routed Playwright with the per-model matrix. The phase narrative describes the supported
MinIO-backed shape directly through the runtime, cache, and object storage contracts.

## Current Repo Assessment

The repository has typed request or response shapes, typed runtime result metadata, a
README-matrix-backed generated catalog, protobuf-backed manifest and result helpers, explicit
cache status or eviction or rebuild flows, a shared Python adapter project whose setup entrypoints
write idempotent bootstrap manifests, explicit substrate-materialization helpers, and daemon
behavior driven by the staged substrate file. Durable model artifact storage lives in the
`infernix-models` MinIO bucket. The staged substrate file is a typed Dhall record at
`infernix-substrate.dhall`, decoded in-process by the `dhall` Haskell library. The runtime
contract distinguishes daemon role from inference executor location:
cluster daemons exist on every substrate and own Pulsar request-topic consumption; Linux cluster
daemons run inference directly and publish results; Apple cluster daemons publish work to derived
pool/model topics consumed by same-binary host daemons that run Apple-native inference and publish
the completed results. Supported publication/status metadata exposes derived pool routing and omits
the retired host batch topic fields.
The
runtime worker dispatches supported Python-native and native adapters through explicit harness
branches and invokes the real engine for the selected binding: the Python adapter `transform`
over a prebuilt host wheel for `python-stdio` bindings, or the real native runner binary resolved
from the repo data root with an image-owned Linux fallback at `/opt/infernix/engines/<adapterId>/`
for `native-process-runner` bindings. The Python worker request carries the mounted
`ClusterConfig.engine` cache fields plus MinIO endpoint, bucket, region, and secret-file-backed
credentials to `adapters.model_cache.configure()` before the adapter calls
`get_model_path()` or uploads an artifact. The worker fetches model weights lazily from the
`infernix-models` MinIO bucket (`adapters.model_cache.get_model_path` on the Python side; the
coordinator model-bootstrap path on the native side) and publishes a
per-family real result: inline text for the LLM and speech families, and a typed
`infernix-demo-objects` object reference for the source-separation, audio-to-MIDI,
music-transcription, image, video, audio-generation, and OMR artifact families. Unsupported adapter
ids fail fast with typed errors instead of returning a generic success payload. The staged file, runtime result metadata, publication surface,
and browser contracts still expose the active substrate through `RuntimeMode` or `runtimeMode`
identifiers, while the final publication contract also distinguishes cluster daemon location from
host inference executor location.

## Substrate Config Ownership Contract

This phase owns the conversion from the README-scale matrix to runtime-consumable substrate state.

- the service owns the typed registry that represents matrix rows
- the built substrate selects the engine column for each supported row
- the staged substrate file carries that selected catalog beside the active build root
- host and cluster consumers use that same substrate file as the exact runtime catalog
- `infernix-demo` and the integration suite both choose the active engine binding for a README row
  from that same substrate file

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Done]

**Status**: Done
**Code-side closure**: Complete — the closed `ResultFamily` sum type (with `resultFamilyId`/`resultFamilyIsArtifact`) and `resultFamilyForDescriptor` landed in `src/Infernix/Types.hs`/`src/Infernix/Models.hs`, `allMatrixRowIds` is exported, and the non-text input object-ref field was added on `InferenceRequest`/`WorkerRequest` (Haskell and `proto/infernix/runtime/inference.proto`) with `WorkerResponse.object_ref` added; proven by the machine-independent gate set (`cabal build all`, `cabal test infernix-unit`, `infernix lint proto`) on the recorded CUDA Linux host
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — the selected `linux-gpu` accelerator plus `linux-cpu` asserts the per-family result contract these types drive
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Storage.hs`, `proto/infernix/manifest/runtime_manifest.proto`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`

### Objective

Make the service runtime strongly typed before transport and UI surfaces accumulate logic.

### Deliverables

- Haskell-owned ADTs for cluster state, generated demo config, model catalog entries, inference
  request shapes, and inference result shapes
- one canonical model catalog surface that lists every registered model the UI may target
- explicit distinction between authoritative durable metadata and derived local cache state
- repo-owned `.proto` schemas under `proto/` define the durable runtime-manifest, inference-payload,
  and service-event message names

### Validation

- `infernix test unit` covers generated-substrate resolution, generated catalog counts,
  per-substrate row inclusion or omission, generated demo-config rendering, invalid startup
  handling, and protobuf round-trips
- `infernix test lint` passes `infernix lint proto` against the repo-owned `.proto` set

### Remaining Work

- **Code (machine-independent — DONE):** the closed `ResultFamily` sum type and
  `resultFamilyForDescriptor` (derived from `family` + `artifactType` + `matrixRowId`) landed,
  `allMatrixRowIds` is exported, and the non-text input object-ref field was added on
  `InferenceRequest`/`WorkerRequest` (the output `ResultPayload.object_ref` already exists and
  `WorkerResponse.object_ref` was added). Proven by `cabal test infernix-unit` and `infernix lint
  proto` on the recorded CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** the per-family result contract
  these types drive is asserted on cohort hardware (Apple Metal with headless materialization;
  CUDA `linux-cpu`/`linux-gpu`).

---

## Sprint 4.2: Inference Request Pipeline Over the Durable Object Store and Pulsar Contract [Done]

**Status**: Done
**Code-side closure**: Complete — the `src/Infernix/Runtime/Worker.hs` native-process-runner branch now invokes the real engine binary resolved by absolute path under `./.data/engines/<adapterId>/bin/...` or the Linux image-owned `/opt/infernix/engines/<adapterId>/bin/...` fallback (via `nativeRunnerBinaryRelPath` + `nativeRunnerArgs`), replacing the removed `renderNativeRunnerOutput` debug string, and python-stdio carries the real `WorkerResponse`; proven by the machine-independent gate set (`cabal build all`, `cabal test infernix-unit`) on the recorded CUDA Linux host. The real engine *output* still requires real weights and engines on cohort hardware
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` runs the real engines and asserts real per-family output
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Cache.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Demo/Api.hs`, `python/adapters/`, `infernix.cabal`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`

### Objective

Use the repo-local durable object store and the topic-shaped Pulsar contract without letting
derived local cache state become authoritative.

### Deliverables

- durable model artifacts live in the `infernix-models` MinIO bucket; the per-pod `emptyDir`
  model cache holds the ephemeral on-disk weight copy used by the engine adapter
- the service runtime consumes inference requests and publishes results through the topic-shaped
  Pulsar contract, using the configured transport on supported cluster paths and the repo-local
  topic spool only in harness-oriented flows that intentionally omit those endpoints
- the durable artifact contract records engine-adapter identity, source-artifact metadata, and
  selected engine-ready artifacts
- process-isolated runtime workers honor adapter-specific command overrides when configured and
  otherwise use the canonical engine runner contract
- local materialization remains cache-oriented and idempotent, not authoritative

### Validation

- `infernix test integration` proves generated catalog publication, per-entry routed inference
  execution for the active built substrate's catalog, Pulsar schema publication, and typed topic
  or result persistence on the validated path
- `infernix test unit` proves large outputs return typed object references and protobuf manifests
  round-trip through the supported storage helpers

### Remaining Work

- **Code (machine-independent — DONE):** `runInferenceWorker` now carries the real `WorkerResponse`
  for `python-stdio` bindings and the `native-process-runner` branch invokes the real engine binary
  resolved by absolute path under `./.data/engines/<adapterId>/bin/...` or the Linux image-owned
  `/opt/infernix/engines/<adapterId>/bin/...` fallback instead of `renderNativeRunnerOutput`.
  Proven by `cabal build all` and `cabal test infernix-unit` on the recorded CUDA Linux host, with
  the fallback covered by the current mounted linux-gpu unit run.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** real engine output requires real
  weights and engines; `linux-gpu` plus `linux-cpu` run them and assert real per-family output.

---

## Sprint 4.3: Honest Apple Host-Native and Linux Container Runtime Parity [Done]

**Status**: Done
**Code-side closure**: Complete — the host-side service wiring that loads engine artifacts from `./.data/engines/<adapterId>/` and publishes the per-family result is in place; proven by the machine-independent gate set (`cabal build all`, `cabal test infernix-unit`) on the recorded CUDA Linux host. The real Apple-native Metal engine path depends on Sprint 1.14's headless Metal/Core ML materialization and runs only on Apple
**Cohort gate**: Closed — Sprint 1.14's headless Apple Metal/Core ML materialization lane is closed, and current Apple integration/e2e/all evidence proves the host-side bridge with validation-wrapper payloads. Real payload fidelity is not a Phase 4.3 blocker under the Section Q single-accelerator gate.
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/object_storage.md`, `documents/operations/apple_silicon_runbook.md`, `documents/engineering/portability.md`

### Objective

Keep one service contract while telling the truth about execution context and inference
placement: Apple control-plane commands are host-native, Apple cluster daemons own request-topic
consumption and derived pool-topic handoff, Apple inference execution and result publication are
host-side, and Linux inference execution and result publication remain cluster-resident.

### Deliverables

- `infernix service` supports direct host-side Apple inference execution for the `apple-silicon`
  substrate when operators invoke it as a host daemon
- on `apple-silicon`, routed cluster surfaces bridge into host-side inference execution instead of
  treating a containerized Apple workload as having Metal or unified-memory inference parity
- the same executable runs in cluster pods for Linux and, under the final Phase 6 contract, for the
  Apple cluster daemon role as well
- daemon role changes only publication context, generated-config source, batch-topic wiring, and
  optional transport-endpoint wiring, not the request or result or catalog contract
- the durable object storage contract uses the `infernix-models` MinIO bucket on every substrate;
  real Pulsar transport is enabled either through the configured Pulsar endpoint inputs or, on
  the host-side lanes (Apple host-native and the Linux outer-container launcher), by discovering
  Pulsar's direct un-gated proxy NodePort transport — the real `/admin/v2` and `/ws/v2` surfaces,
  not the JWT-gated `/pulsar/admin` edge — from publication state or the control-plane node IPv4,
  while the filesystem topic spool remains a harness-oriented fallback when no endpoint is
  intentionally present
- the shared abstraction lives at the control plane, publication, config, Pulsar, protobuf, and
  routed API or UI levels rather than a false claim of identical image layout across all lanes
- startup reports whether the daemon is running host-side or cluster-side and which role it owns
- the current generated file, publication surface, and runtime result payloads still serialize the
  active substrate under `runtimeMode` identifiers

### Validation

- Apple host-side `infernix service` reports host inference-executor metadata and consumes the same
  generated catalog contract as the cluster-daemon paths
- routed Apple demo and transport flows reach the host inference daemon through the supported Apple
  bridge instead of a cluster-resident Apple inference workload
- cluster-resident `infernix service` on `linux-cpu` and `linux-gpu` consumes the same generated
  catalog contract and route-or-publication semantics on the cluster path
- rebuilding for a different substrate changes generated catalog content and engine bindings, not
  the browser base URL

### Remaining Work

None.

---

## Sprint 4.4: Demo Catalog and Cache HTTP API Surface [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Models.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`

### Objective

Expose the stable demo HTTP API surface that the browser consumes for catalog, publication, and
cache discovery, while keeping production inference Pulsar-only. Routed manual inference
dispatch closes through the durable-context surface introduced by Phase 7 rather than a direct
HTTP request/poll cycle owned by this sprint.

### Deliverables

- typed handlers for listing models, inspecting model request shape, reporting publication
  metadata, and observing or mutating derived cache state, all exposed by `infernix-demo`
- request validation uses the same Haskell-owned model metadata used by the production path
- the demo surface dispatches into the same Haskell runtime contract that production
  `infernix service` uses for any auxiliary discovery surfaces
- the demo HTTP surface does not carry a direct manual-inference handler in the supported final
  contract; Phase 7 owns the durable-context Chat surface that replaces it

### Validation

- `infernix test e2e` proves routed model listing, publication discovery, and cache lifecycle
  through `/api`
- direct API calls return typed model metadata, publication metadata, and cache state
- invalid requests fail with typed user-facing errors

### Remaining Work

None.

---

## Sprint 4.5: Durable Service Cache and Reconcile Semantics [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Storage.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/model_lifecycle.md`, `documents/engineering/storage_and_state.md`

### Objective

Make derived runtime state reproducible from durable sources and keep lifecycle cleanup explicit.

### Deliverables

- local service cache roots live under `./.data/runtime/`
- cache directories are keyed by model identity and substrate identifier, with current durable
  payloads still serializing that identifier as `runtimeMode`
- cache rebuildability comes from MinIO-backed weights and the Pulsar conversation log via
  `prefixHash`; cache manifests sit beside the cached weights at
  `./.data/runtime/model-cache/<runtime-mode>/<model-id>/manifest.pb`
- `cache status`, `cache evict`, and `cache rebuild` are explicit operator flows

### Validation

- `infernix test unit` proves cache materialization, eviction, and rebuild behavior
- `infernix test integration` proves the routed cache API can materialize and rebuild cache entries
- `cluster status` reports model-cache state and MinIO `infernix-models` bucket counts

### Remaining Work

None.

---

## Sprint 4.6: Comprehensive Matrix Registry and Initial Generated Demo `.dhall` Baseline [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`

### Objective

Turn the README matrix into the typed source of truth that drives the runtime binding and
substrate-generated demo-catalog baseline.

### Deliverables

- the service owns a typed registry for every row in the README matrix
- each row records workload identity, artifact or format family, reference model metadata, and
  per-substrate engine bindings
- rows whose selected engine for a substrate is `Not recommended` are absent from that substrate's
  generated catalog
- across `apple-silicon`, `linux-cpu`, and `linux-gpu`, the generated catalogs cover every README
  row that names a real engine

### Validation

- unit tests prove generated catalog counts and per-substrate row inclusion or omission
- frontend contract checks prove the generated active-substrate contract carries selected engines
  and runtime metadata
- integration fixtures prove the published ConfigMap matches the generated active-substrate catalog

### Remaining Work

None.

---

## Sprint 4.7: Shared Python Adapter Project and Poetry-Driven Quality Gate [Done]

**Status**: Done
**Code-side closure**: Complete — the six adapter `transform` bodies in `python/adapters/{transformers,vllm,pytorch,tensorflow,jax,diffusers}_python.py` now make real framework calls behind lazy guarded imports (per the Machine-Independent Gate Invariant), load weights via `adapters.model_cache.get_model_path`, `common.render_engine_output` was removed, the artifact-adapter seam (`run_artifact_adapter` + `ArtifactResult` + `_upload_demo_object`/`download_demo_object` to/from `infernix-demo-objects`) was added, and `WorkerRequest` now carries model-cache/MinIO wiring so `run_context_adapter` and `run_artifact_adapter` call `adapters.model_cache.configure()` before invoking engine logic; proven by the machine-independent gate set (`poetry run check-code` — mypy `--strict`/black/ruff — with no frameworks installed, plus mounted linux-gpu `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and `cabal build test:infernix-integration`) on the recorded CUDA Linux host. Producing real output still needs real weights/engines on cohort hardware
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` run the real adapters and assert real per-family output
**Implementation**: `python/pyproject.toml`, `python/adapters/`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Models.hs`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`
**Docs to update**: `documents/development/python_policy.md`, `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Collapse the Python runtime boundary to one shared project and one shared adapter tree while
keeping `poetry run` as the only supported execution path.

### Deliverables

- one shared `python/pyproject.toml` owns Python dependencies for the supported adapter set
- one shared `python/adapters/` tree contains the repo-owned adapter modules
- runtime-specific behavior stays inside the shared tree only where engine logic genuinely diverges
- per-engine setup entrypoints and adapter entrypoints are declared as Poetry console scripts
- `src/Infernix/Runtime/Worker.hs` forks `poetry run <entrypoint>` rather than raw `python`
- `poetry run check-code` is the canonical Python quality gate and runs `mypy --strict`,
  `black --check`, and `ruff check` in sequence
- the duplicated `python/apple-silicon/`, `python/linux-cpu/`, and `python/linux-gpu/` project
  layout is removed from the supported architecture

### Validation

- `poetry run check-code` passes against the shared `python/` tree
- intentionally introducing a type, format, or ruff failure under `python/adapters/` causes the
  quality gate to fail
- `infernix test unit` exercises the Haskell worker plus a Python adapter handshake end to end
- `find python -name '*.py' -type f` returns only files under `python/adapters/`

### Remaining Work

- **Code (machine-independent — DONE):** `common.render_engine_output` was removed and the six
  adapter `transform` bodies now make real framework calls behind lazy guarded imports over prebuilt
  host wheels that load weights through `adapters.model_cache.get_model_path`, and the
  artifact-adapter seam (`run_artifact_adapter` + `ArtifactResult` + the `infernix-demo-objects`
  upload/download helpers) returns an object reference. `WorkerRequest` now carries the mounted
  model-cache and MinIO wiring, and the shared adapter entrypoints call
  `adapters.model_cache.configure()` before any `get_model_path`, input-object download, or
  artifact upload. Proven by mounted linux-gpu `poetry run check-code`, `cabal test infernix-unit`,
  `cabal test infernix-haskell-style`, and `cabal build test:infernix-integration` on the present
  CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** producing real per-family output
  requires real weights and engines; `linux-gpu` plus `linux-cpu` run the adapters and assert it.

---

## Sprint 4.8: Pulsar-Driven Production Inference Surface [Done]

**Status**: Done
**Code-side closure**: Complete — per-family result publication flows through the shared `executeInferenceWithKVCache`/`buildPayload` path (inline text for the LLM/speech families, `infernix-demo-objects` `object_ref` for the artifact families) over the production Pulsar surface, emitting no generic-success payload and failing fast on unsupported adapters; proven by the machine-independent gate set (`cabal build all`, `cabal test infernix-unit`) on the recorded CUDA Linux host
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` publish and observe real per-family results end to end
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/values.yaml`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/tools/pulsar.md`, `documents/architecture/runtime_modes.md`, `documents/reference/cli_reference.md`

### Objective

Make the Pulsar-driven production inference surface the canonical way to request inference in any
non-demo deployment.

### Deliverables

- the active `.dhall` schema includes `request_topics`, `result_topic`, daemon-role metadata, and
  engine-binding metadata; the final Apple role schema also includes member assignment and Pulsar
  connection-mode metadata
- `src/Infernix/Runtime/Pulsar.hs` subscribes to request topics, dispatches work through the
  worker or derived pool-topic handoff path, and publishes typed protobuf responses to the configured
  result topic
- production `infernix service` binds no HTTP port
- the production chart deploys the role-specific engine daemon without a Kubernetes HTTP Service
  and without a fake compatibility listener

### Validation

- the `infernix internal pulsar-roundtrip` helper publishes a request through Pulsar's real
  `/admin/v2` and `/ws/v2` surfaces — reached on the un-gated Pulsar-proxy NodePort from the
  host-side launcher, not the JWT-gated `/pulsar/admin` edge — and observes the result end to end
- production pods bind no Infernix-owned HTTP listener
- repeat `cluster up` runs preserve the production inference surface

### Remaining Work

- **Code (machine-independent — DONE):** per-family result publication is wired over the production
  Pulsar surface through the shared `buildPayload` path — inline text for the LLM and speech
  families, an `infernix-demo-objects` object reference for the artifact families — emitting no
  generic-success payload. Proven by `cabal build all` and `cabal test infernix-unit` on the present
  CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** `linux-gpu` plus `linux-cpu`
  publish and observe real per-family results end to end.

---

## Sprint 4.9: Shared Linux Substrate Image Build and Snapshot Runtime [Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `compose.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Files.hs`, `chart/values.yaml`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `.dockerignore`
**Docs to update**: `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/development/python_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace the current multi-file Linux Docker story with one shared substrate build definition that
produces the two real Linux runtime images and supports the image-snapshot launcher model.

### Deliverables

- one shared `docker/Dockerfile` builds `infernix-linux-cpu` and
  `infernix-linux-gpu`
- build arguments cover at least the base image and the substrate-selecting `RUNTIME_MODE` value;
  shared build stages own the common toolchain, and `compose.yaml` selects the already-built
  launcher image through a one-shot Compose image selector without changing the supported
  `docker compose run --rm infernix infernix ...` surface
- `docker/linux-base.Dockerfile` is removed from the supported architecture
- the shared substrate image definition owns ghcup-pinned GHC or Cabal, Python, Poetry, the
  Node-based web bundle build, the Kind toolbelt, and the Linux Playwright runtime
- on the supported Linux outer-container path, `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding the identical runtime image inside
  the launcher
- the CUDA image bakes in the `nvkind` binary through a multi-stage build rather than a host
  handoff path
- the baked image captures `/opt/infernix/source-snapshot-files.txt` before later generated
  outputs appear so git-less image runs of `infernix lint files` validate only the source
  snapshot; the manifest is intentionally outside the bind-mounted `./.build/` tree so it stays in
  the image overlay
- the baked image materializes a build-arg-selected substrate file inside the image overlay during
  image build, and supported Compose-launched operator commands restage the image-local
  `/workspace/.build/outer-container/build/infernix-substrate.dhall` before substrate-aware work
- inside the Linux runtime image, the daemon does not run `apt`, `pip`, `cabal build`, or compiler
  toolchains at runtime

### Validation

- `docker build -f docker/Dockerfile --provenance=false -t infernix-linux-cpu:local --build-arg
  RUNTIME_MODE=linux-cpu --build-arg BASE_IMAGE=ubuntu:24.04 --build-arg DEMO_UI=true .`
  succeeds on supported Linux CPU hosts and produces the default snapshot
- `docker build -f docker/Dockerfile --provenance=false -t infernix-linux-gpu:local --build-arg
  RUNTIME_MODE=linux-gpu --build-arg BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04
  --build-arg DEMO_UI=true .` succeeds on supported Linux GPU hosts and produces the CUDA snapshot
- smoke probes from the built images confirm the expected `infernix`, `ghc`, `cabal`, `python`,
  and Node toolchain
- `infernix lint files` succeeds inside the baked Linux image without `.git` metadata by using the
  captured source-snapshot manifest
- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  `docker compose run --rm infernix infernix cluster up` uses the active built substrate image on
  the supported path

### Remaining Work

None.

---

## Sprint 4.10: Apple Silicon Daemon-Driven Engine Bootstrap [Done]

**Status**: Done
**Code-side closure**: Complete — the host daemon native worker consumes engine artifacts from `./.data/engines/<adapterId>/` and fails fast with `engine_binary_missing` when absent; proven by the machine-independent gate set (`cabal build all`, `cabal test infernix-unit`) on the recorded CUDA Linux host. The real Apple Metal artifacts themselves depend on Sprint 1.14's headless Apple materialization lane
**Cohort gate**: Closed — Sprint 1.14's headless Apple Metal/Core ML materialization lane is closed, and current Apple integration/e2e/all evidence proves the host daemon bootstrap with validation-wrapper payloads.
**Implementation**: `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `python/pyproject.toml`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/operations/apple_silicon_runbook.md`, `documents/development/local_dev.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`

### Objective

On Apple Silicon, keep inference execution host-native and let the host daemon own engine setup
without inventing fake container parity.

### Deliverables

- `src/Infernix/Engines/AppleSilicon.hs` provides typed engine-setup steps for the host inference
  executor lane
- the host daemon currently ensures the shared Poetry project, repo-local engine roots, and
  per-engine setup entrypoints on Apple Silicon
- the operator remains responsible for the host prerequisites documented in governed docs,
  including ghcup and the supported toolchain installs
- Apple adapter dependencies materialize on demand in `python/.venv/`
- the daemon uses the same per-engine Poetry entrypoints as the Linux runtime lanes

### Validation

- on a clean Apple Silicon host with ghcup installed,
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  succeeds without extra supported wrapper scripts
- after `./.build/infernix internal materialize-substrate apple-silicon`, the
  `./.build/infernix cluster up` command brings up the cluster and runs the current Apple setup
  entrypoints before host-side inference execution
- `infernix test integration` exercises the Apple column of the README matrix against the
  host inference executor lane when the active substrate is `apple-silicon`

### Remaining Work

None.

---

## Sprint 4.11: Per-Substrate Engine Selection in the Catalog [Done]

**Status**: Done
**Code-side closure**: Complete — per-substrate engine selection resolves each row to its real adapter via `engineBindingForSelectedEngine` (Python wheel or native binary) and fails fast on unsupported adapter types or missing model metadata; proven by the machine-independent gate set (`cabal test infernix-unit`) on the recorded CUDA Linux host
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` dispatch the resolved real adapters and assert real output
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Types.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Runtime/Worker.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/development/testing_strategy.md`

### Objective

Make the per-substrate engine column in the README matrix the canonical input for catalog
generation.

### Deliverables

- each matrix row records explicit engine selection per substrate
- the active built substrate picks the appropriate engine binding when generating
  `infernix-substrate.dhall`
- the generated demo config and demo-visible surfaces expose each row through the selected engine
  for that substrate while still serializing the active substrate under `runtimeMode` fields
- daemon startup fails when the active substrate references an engine binding whose adapter
  metadata is missing

### Validation

- rebuilding for a different substrate changes per-row selected engine bindings deterministically
- the generated demo-config and routed API surfaces publish the selected engine bindings for the
  active substrate
- demo-config validation fails when the active substrate references a selected engine with no
  matching binding metadata

### Remaining Work

- **Code (machine-independent — DONE):** per-substrate engine selection resolves each row to its
  real adapter (Python wheel or native binary) via `engineBindingForSelectedEngine` and fails fast
  on unsupported adapter types or missing model metadata rather than dispatching a placeholder.
  Proven by `cabal test infernix-unit` on the recorded CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** `linux-gpu` plus `linux-cpu`
  dispatch the resolved real adapters and assert real output.

## Sprint 4.12: Substrate-Owned Daemon Role, Startup Selection, and Fallback Removal [Done]

**Status**: Done
**Code-side closure**: Complete — the `renderNativeRunnerOutput` / `nativeRunnerLabel` debug-metadata native fallback was removed (real native dispatch from Sprint 4.2 now stands in its place) while the fail-fast-on-unsupported-adapter contract is preserved; proven by the machine-independent gate set (`cabal build all`, `cabal test infernix-unit`) on the recorded CUDA Linux host
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` confirm no fallback path remains under real dispatch
**Implementation**: `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Service.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `docker/Dockerfile`, `web/test/run_playwright_matrix.mjs`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make daemon behavior derive entirely from the staged substrate file at startup and remove the
remaining file-absent substrate-selection fallback from the runtime contract. Phase 6 Sprint 6.25
extends this startup contract with explicit cluster and host daemon roles.

### Deliverables

- `infernix service` derives its active substrate and daemon role from the staged substrate file
  when present and no longer accepts `--runtime-mode` or `INFERNIX_RUNTIME_MODE`
- `infernix-demo` and any runtime-owned manual inference entrypoint choose the engine binding for a
  given README row only from the colocated or ConfigMap-backed substrate `.dhall`
- Apple host workflows stage that substrate file through
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`, Linux
  outer-container workflows stage it through
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  under `/workspace/.build/outer-container/build/` inside the launcher image, and supported runtime
  entrypoints fail fast if it is absent
- the direct `infernix service` entrypoint remains host-side for Apple inference execution, while
  the routed clustered demo app reads the same staged `.dhall` and enters the cluster daemon path
  before Apple batches move to the host daemon
- cluster-resident Apple workloads consume the mounted staged substrate file for cluster daemon
  behavior, catalog behavior, and route behavior; they do not stand in for the canonical Apple
  inference executor
- Linux `linux-cpu` and `linux-gpu` daemons run as cluster-resident workloads on their deployed
  substrate images and perform request consumption, inference, and result publication there
- each daemon reads the staged substrate `.dhall` at startup to select the active substrate, daemon
  role, engine catalog, and any Pulsar topic wiring; automatic file-watching or reload is not part
  of the supported contract
- the supported steady-state runtime removes simulated cluster, route, transport, and generic
  inference-success fallback code paths from the final contract rather than merely refusing to
  count them as evidence
- startup and publication reporting name substrate, daemon role, cluster daemon location, inference
  executor location, and any routed Apple batch bridge mode unambiguously

### Validation

- Apple host-side `infernix service` reports `apple-silicon` from the generated substrate file and
  the host daemon role, and routed manual inference continues to succeed through the clustered
  `infernix-demo` surface by entering the cluster daemon path before reaching host inference
- Linux substrate daemons read the mounted ConfigMap-backed substrate file at
  `/opt/build/infernix-substrate.dhall` and do not rely on runtime-mode flags
- manual inference through `infernix-demo` and service-loop execution both use the engine binding
  selected in `.dhall` for the active README row
- runtime validation fails if the service or demo app falls back to simulated route, transport, or
  substrate behavior or to a generic engine-success path that ignores the selected adapter metadata

### Remaining Work

- **Code (machine-independent — DONE):** the `src/Infernix/Runtime/Worker.hs`
  `renderNativeRunnerOutput` / `nativeRunnerLabel` debug-metadata native fallback was removed now
  that real native dispatch (Sprint 4.2) is in place, preserving the fail-fast-on-unsupported-adapter
  contract. Proven by `cabal build all` and `cabal test infernix-unit` on the recorded CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** `linux-gpu` plus `linux-cpu`
  confirm no generic-success or debug-metadata fallback path remains under real dispatch.

---

## Sprint 4.13: Cluster Manifest Materialization [Done]

**Status**: Done
**Implementation**: `dhall/InfernixCluster.dhall` (new), `src/Infernix/ClusterConfig.hs` (new), `src/Infernix/Service.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/templates/configmap-cluster-config.yaml` (new)
**Docs to update**: `documents/engineering/cluster_config_manifest.md`, `documents/tools/pulsar.md`, `documents/architecture/daemon_topology.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the `InfernixCluster.dhall` typed cluster-wiring record + matching Haskell decoder.
Delete every `env:` block from `chart/templates/deployment-{coordinator,engine}.yaml`; the pods
mount the cluster `ConfigMap` at `/opt/infernix/cluster.dhall` and the Haskell daemon decodes it
at startup. Retire every Pulsar / catalog / daemon-location / engine-command env-var fallback in
favor of typed `ClusterConfig` fields.

### Deliverables

- `dhall/InfernixCluster.dhall` schema with the `PulsarConfig`, `MinioConfig` (non-credential
  fields), `DemoBackendConfig`, `EngineConfig`, `CoordinatorConfig` records named in
  `documents/engineering/cluster_config_manifest.md`.
- `ClusterConfig` typed record + decoder; threaded through every coordinator + engine entry
  point.
- `INFERNIX_DEMO_CONFIG_PATH`, `INFERNIX_DAEMON_ROLE`, `INFERNIX_DAEMON_LOCATION`,
  `INFERNIX_CATALOG_SOURCE`, `INFERNIX_CONTROL_PLANE_CONTEXT`, `INFERNIX_PULSAR_*`
  (admin/ws/http/service/tenant/namespace), `INFERNIX_ENGINE_COMMAND_<NAME>` env reads deleted
  from `src/Infernix/Service.hs`, `src/Infernix/Runtime/Pulsar.hs`,
  `src/Infernix/Runtime/Worker.hs`.
- `chart/templates/deployment-coordinator.yaml` and
  `chart/templates/deployment-engine.yaml` lose every `env:` entry except any third-party
  upstream exception explicitly enumerated; they gain `cluster-config` volume mount at
  `/opt/infernix/cluster.dhall`.
- `chart/templates/configmap-cluster-config.yaml` renders the staged cluster Dhall into a
  ConfigMap.

### Validation

- `cabal build all` clean, `infernix test lint` clean, `infernix test unit` clean.
- `grep -rn '^\s*-\s*name:\s*INFERNIX_' chart/templates/deployment-{coordinator,engine}.yaml`
  returns zero matches.
- `infernix test integration` on `linux-gpu` round-trips through coordinator + engine pods that
  read from the mounted Dhall ConfigMap (proven by removing the corresponding `env:` entries
  before the test runs).
- `cabal test infernix-unit` PASSES with `assertClusterConfig`, which renders a
  `ClusterConfig` fixture with a non-empty `engine.commandOverrides` list and decodes it back
  through `decodeClusterConfigFile`.
- `cabal build all`, `cabal test infernix-haskell-style`, and
  `cabal run infernix -- lint {docs,files,chart,proto}` all exit zero against the
  `ClusterConfig` renderer.
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C with full
  `linux-cpu` and `linux-gpu` gates against the mounted `ClusterConfig`.

### Remaining Work

None. Apple cohort validation closed in [Wave A](cohort-validation-waves.md), and CUDA Linux
cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 4.14: Declarative-State Phase Prose Rewrite [Done]

**Status**: Done
**Code-side closure**: Complete — the declarative-state prose rewrite that describes real per-family engine dispatch as the always-intended steady state landed across this phase document; proven by the machine-independent gate set (`infernix lint docs`, `infernix docs check`) on the recorded CUDA Linux host. Fully machine-independent
**Cohort gate**: None — documentation only; no accelerator full-suite. It rides the Wave I cycle because it describes the real-inference steady state
**Implementation**: `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md` (prose only)
**Docs to update**: this file

### Objective

Rewrite Phase 4 deliverables and validation prose for Sprints 4.2, 4.3, and 4.5 so the supported
MinIO-backed object storage contract, the ephemeral `emptyDir` model cache, and the
`prefixHash`-driven cache rebuildability are described directly, without parenthetical retirement
notes pointing forward to Phase 7. The phase narrative reads forward into Phase 7 instead of
being contradicted by it.

### Deliverables

- Sprint 4.2 Deliverables and Validation prose describes the supported MinIO-backed durable
  artifact contract directly.
- Sprint 4.3 Deliverables prose describes the supported `infernix-models` MinIO bucket as the
  object storage substrate, with the Pulsar transport path and the filesystem topic spool
  retained as the harness-oriented fallback.
- Sprint 4.5 Deliverables and Validation prose describes the supported cache-rebuild contract
  in terms of MinIO weights and `prefixHash`.
- Phase 4 Current Repo Assessment uses present-tense vocabulary anchored on
  [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
  and [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md).
- Phase 4 closing prose for Sprint 4.13 keeps `Wave A` and `Wave C` references without dated
  hardware proof-point prose.

### Validation

- the phase-specific lexical guard for legacy object storage paths, placeholder buckets, and dated
  proof-point prose returns zero matches outside the legacy ledger.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

- **Code (machine-independent — DONE):** the closing declarative prose was revised so real
  per-family engine dispatch (not deterministic metadata output) is the always-intended steady state
  read forward into Phases 5-7. Documentation only. Proven by `infernix lint docs` and `infernix
  docs check` on the recorded CUDA Linux host.
- **Cohort gate:** none — this sprint carries no accelerator full-suite; it rides the Wave I
  cycle only because it describes the real-inference steady state.

---

## Sprint 4.15: Per-Family Real-Output Result Contract and Object-Ref Artifact Families [Done]

**Status**: Done
**Code-side closure**: Complete — `buildPayload :: ResultFamily -> Text -> ResultPayload` now routes text families to `inlineOutput` and artifact families to `objectRef` (no longer hardcoding `objectRef = Nothing`), the `WorkerResponse` object-ref output field was added, `resultFamilyForDescriptor` covers all 19 rows, and the unit tests assert the routing and resolution; proven by the machine-independent gate set (`cabal test infernix-unit`) on the recorded CUDA Linux host. It built on the Sprint 4.1 types and the Sprint 4.7 adapter seam
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` assert the per-family result contract per active-substrate row (exercised by Phase 6)
**Implementation**: `proto/infernix/runtime/inference.proto`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Storage.hs`, `python/adapters/`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Blocked by**: 4.1, 4.7
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/engineering/object_storage.md`, `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`

### Objective

Give every README matrix row a typed per-family result contract so the runtime publishes a real,
family-appropriate output and the validation suite can assert it. Text families return inline text;
artifact families return a typed MinIO object reference.

### Deliverables

- a closed `ResultFamily` sum type (LLM, speech transcription, source separation, audio-to-MIDI,
  music transcription, image generation, video generation, audio generation, OMR) resolved from
  each descriptor by `resultFamilyForDescriptor`, shared by the runtime and the test suite
- `ResultPayload.object_ref` (already present on the wire) is populated for the artifact families;
  `src/Infernix/Runtime.hs` `buildPayload` no longer hardcodes `objectRef = Nothing`
- `WorkerResponse` gains an object-ref output field so an artifact adapter can return a reference,
  and `InferenceRequest`/`WorkerRequest` gain a non-text input object-ref field for the audio and
  image input families; the existing `input_text` field stays for the text families
- artifact results are written to the always-on `infernix-demo-objects` MinIO bucket through the
  existing presigned PUT/GET helpers, never the retired `infernix-runtime` or `infernix-results`
  buckets (see [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) and
  [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md))
- the 19-row to `ResultFamily` and inline-versus-object-ref mapping is published in
  [../documents/architecture/model_catalog.md](../documents/architecture/model_catalog.md)

### Validation

- `infernix test unit` proves `resultFamilyForDescriptor` resolves every catalog row and that
  `buildPayload` routes text to `inline_output` and artifacts to `object_ref`
- `infernix test integration` and `infernix test e2e` assert the per-family result contract per
  active-substrate row (see
  [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md))
- re-validated through the Wave I `linux-gpu` plus `linux-cpu` attestation

### Remaining Work

- **Code (machine-independent — DONE):** the `ResultFamily` mapping, `buildPayload`
  text→inline / artifact→object_ref routing, the `WorkerResponse` object-ref output field, and the
  19-row→`ResultFamily` mapping doc are implemented, building on the Sprint 4.1 type and proto-field
  work and the Sprint 4.7 adapter seam. Proven by `cabal test infernix-unit` on the present CUDA
  Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** `linux-gpu` plus `linux-cpu`
  assert the per-family result contract per active-substrate row (exercised by Phase 6).

---

## Sprint 4.16: Per-Engine Isolated Framework Venvs [Done]

**Status**: Done
**Code-side closure**: Complete — the per-engine venv mechanism is built and validated on the
recorded CUDA Linux host. The shared `python/` project stays framework-free (the machine-independent
`check-code` gate); each framework engine has its own Poetry project at `python/engines/<engine>/`
(`package-mode = false`, in-project venv) that path-depends on the shared `infernix-adapters`
package and declares its framework wheels in an optional `cuda` group; `src/Infernix/Runtime/Worker.hs`
resolves and runs the per-engine venv (`python -m adapters.<module>`) when present and falls back to
the fail-fast shared path when absent. Proven by the Stage 1 machine-independent gates:
`cabal build all` + `cabal test infernix-unit` + `cabal test infernix-haskell-style`;
`poetry run check-code` still green (machine-independence preserved, no framework in the shared
venv). An early Stage 2 cohort proof on this host (a CUDA GPU run, not part of code-side closure):
`poetry install --directory python/engines/transformers --with cuda` resolving torch `2.7.1+cu128`
+ transformers `5.11.0` with `torch.cuda.is_available()` True on the RTX 5090, and a real
Qwen2.5-1.5B generation on the GPU via the transformers adapter's exact `AutoModelForCausalLM` +
`generate` path. Current source also adds Linux CPU `--with linux-cpu` groups for the
`transformers` and `pytorch` engine projects, gates worker use to actual Linux runtimes, bakes
those venvs into the Linux CPU image, and validates them through the 2026-06-16 Linux CPU
integration run. The Linux CPU Qwen row is a deterministic tokenizer/config smoke response rather
than full generation, and the Linux CPU Bark row emits a deterministic WAV validation artifact.
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md), Stage 2 (`linux-gpu` plus `linux-cpu`) — the
full per-engine `--with cuda` image bake and the real per-family output for every active-substrate
row. The Apple transformers engine project now declares an Apple-specific group and the Apple
rerun completes `llm-qwen25-safetensors`; the current Apple aggregate `test all` is green against
the validation-wrapper state, and the selected `linux-gpu` plus `linux-cpu` real-output gate closed
on 2026-06-20 through full-suite reruns. Basic Pitch
TensorFlow (published package pins TensorFlow `<2.15.1`), Omnizart (TF1-era), and MT3
(unmaintained JAX) do not resolve on the Python 3.12 / CUDA 12.8 substrate and are named cohort
residuals.
**Implementation**: `python/engines/<engine>/pyproject.toml`, `python/engines/<engine>/poetry.toml`, `src/Infernix/Runtime/Worker.hs`, `docker/Dockerfile`, `.gitignore`
**Docs to update**: `documents/development/python_policy.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Make real per-family inference installable without breaking the machine-independent quality gate.
The Sprint 4.7 single-shared-venv assumption cannot hold the real frameworks (vLLM, PyTorch-CUDA,
TensorFlow, JAX-CUDA, Diffusers) in one environment — their pins conflict and one Poetry lock cannot
resolve `torch` from two indices.

### Deliverables

- The shared `python/` project remains framework-free; `poetry run check-code` stays
  machine-independent (default install pulls no framework).
- One isolated Poetry project + in-project venv per framework engine under `python/engines/<engine>/`,
  path-depending on the shared `infernix-adapters` package, with framework wheels in an optional
  `cuda` group (cu128 torch for Blackwell on linux-gpu).
- Linux CPU substrate builds opt in to `--with linux-cpu` for `transformers` and `pytorch`, baking
  CPU framework venvs for validation while preserving the shared framework-free gate.
- The Haskell worker prefers the per-engine venv (`python -m adapters.<module>`) and falls back to
  the fail-fast shared path when absent.
- The linux-gpu image build bakes each engine's `--with cuda` venv as a resilient, separate layer.
- The linux-gpu base image is aligned to CUDA 12.8 to match the supported 570 driver branch
  (Sprint 4.8 follow-on in `bootstrap/linux-gpu.sh`).

### Validation

- `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `poetry run check-code`,
  `infernix lint files/docs` all pass on the recorded CUDA Linux host (machine-independent gates).
- `poetry install --directory python/engines/transformers --with cuda` resolves the CUDA framework
  set and `torch.cuda.is_available()` is True on the RTX 5090.
- The 2026-06-16 Linux CPU image build bakes the `transformers` and `pytorch` `--with linux-cpu`
  venvs, passes `poetry --directory python run check-code`, and the subsequent Linux CPU
  integration run exercises the deterministic Transformers CPU smoke path and Bark validation WAV.

### Remaining Work

- **Code (machine-independent) — DONE:** per-engine projects, worker resolution, Dockerfile bake,
  gitignore, base-image alignment, and Linux CPU framework venv groups for `transformers` and
  `pytorch`; validated by the gate set above on the recorded CUDA Linux host and the 2026-06-16
  Linux CPU image/integration lane.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** the full linux-gpu image bake of
  all engine venvs, live model-weight provisioning, runtime-backed native payload consumption
  (llama.cpp / whisper.cpp / ONNX Runtime / CTranslate2 / Audiveris), and real per-family output
  for every active-substrate row on `linux-gpu` plus `linux-cpu`; Basic Pitch TensorFlow, Omnizart,
  and MT3 are named residuals pending maintained equivalents or fallback-lane proof.

---

## Sprint 4.17: Per-Engine Engine Images and Batch Routing [Done]

**Status**: Done
**Code-side closure**: Complete for the machine-independent scope on the recorded Linux outer-container lane. The foundation
is still present — `docker/Dockerfile` is the slim control-plane/coordinator image (**22.4 GB**, down
from 121 GB, no framework venvs), `docker/engine.Dockerfile` builds per-engine images (CUDA-runtime
base + binary + one engine's `--with cuda` venv), the `transformers` per-engine image is
GPU-validated (`torch.cuda.is_available()` True + adapter import inside it with `--gpus all`), and the
`vllm` pin is `0.11.0`. Current June 11, 2026 validation also proves the `vllm` and `pytorch`
per-engine images build from the split Dockerfile before the TensorFlow/Basic Pitch dependency
residual was exposed; the TensorFlow engine image now installs only the maintained TensorFlow CUDA
stack while Basic Pitch TensorFlow is tracked as a named residual. The follow-up routed run passed
Haskell style, Haskell unit, and web unit gates, then exposed the Linux outer-container retained
Harbor Patroni scrub gap; the lifecycle now scrubs non-retained Patroni claim roots before claim
directory creation and after retained-state sync on all lanes. The cluster-side wiring is now code-side implemented: generated linux-gpu substrate files include
the validated `enginePools` / `engineMembers` graph, internal daemon metadata is derived from that
graph during decode, the coordinator routes Python-native requests to derived pool/model topics,
`infernix service --role engine --engine-name NAME` selects the matching stable member id, the chart
renders `infernix-engine-<engine>` Deployments and PDBs, and the lifecycle
builds/publishes/overlays per-engine images through the Harbor path. Current validation
evidence on June 11, 2026: temp-copy Linux GPU launcher `cabal build all` PASS,
`cabal test infernix-unit` PASS, and `cabal test infernix-haskell-style` PASS; current-source
`cabal run exe:infernix -- lint docs`, `docs check`, `lint chart`, `lint files`, and `lint proto`
all exit 0; current-source `internal materialize-substrate linux-gpu --demo-ui true` plus
`internal demo-config validate` renders and validates the engine-pool/member graph and derived
linux-gpu pool/model batch topics. The first governed rerun after the single-GPU scheduling fix passed
style/unit/web gates but failed during Harbor publication with a retained `harbor-registry` MinIO
bucket / fresh Harbor database blob mismatch. The rerun after the initial bucket reset still passed
style/unit/web gates but failed during Harbor publication of `infernix-engine-diffusers-linux-gpu`
with `blob sha256:05ec76e31584... not found`; investigation found stale MinIO
`.minio.sys/multipart` registry-upload metadata plus a Linux host-bind teardown path that skipped
the non-retained scrub. Lifecycle code now scrubs the Harbor registry bucket, registry bucket
metadata, MinIO multipart/tmp working sets, and non-retained Patroni roots on startup and
`cluster down`, leaving model and demo object buckets durable. The governed rerun after that
cleanup again passed style/unit/web gates and proved teardown leaves no stale registry/multipart/tmp
directories, but still failed on the first diffusers image push with
`blob sha256:4614b301... not found`. Investigation found the local repo-owned images were Docker 29
/ BuildKit OCI indexes with attestation metadata. Bootstrap and lifecycle builds now pass
`--provenance=false`, and lifecycle reuse rejects local image-index descriptors so stale index tags
are rebuilt as plain single-platform images before pushing to Harbor. The governed rerun with that
fix rebuilt all five per-engine images as plain Docker manifests (`vllm`, `pytorch`, `tensorflow`,
`jax`, and `diffusers`) and again passed style/unit/web gates, but Harbor publication still failed
while pushing `infernix-engine-diffusers-linux-gpu` after 8 retries with
`blob sha256:05ec76e31584... not found`. The retained Harbor Redis dump contains stale
repository blob-cache keys for the missing digests while the MinIO registry bucket is scrubbed;
lifecycle cleanup now also removes the Harbor Redis claim root with the rebuildable registry
bucket/cache state. The next governed rerun passed Haskell style, Haskell unit, and web unit
gates; push/pull-verified all five per-engine images, the slim control-plane image, and chart
upstream images through Harbor; deployed the final chart; and completed `cluster up`. It then
failed in per-model inference at `audio-basic-pitch-onnx` because the native ONNX Runtime
audio-to-MIDI lane produced a failed/inline result where the `AudioToMidi` contract requires an
`infernix-demo-objects/*.mid` object reference. After the integration harness input/status
follow-up, the governed `./bootstrap/linux-gpu.sh build` passed and produced the plain Docker
manifest launcher image `sha256:2d6cfd42ca59ee7fbd9669a8c32738ed0ba44ef09706b469d12c8803b520e030`.
The latest governed `./bootstrap/linux-gpu.sh test` rerun again passed Haskell style, Haskell unit,
and web unit gates, push/pull-verified all five per-engine images plus the control-plane and chart
upstream images through Harbor, completed final chart rollout and route probes, then failed at the
first native-process-runner row, `llm-tinyllama-gguf`, because the base engine pod had no
`/workspace/.data/engines/llama-cpp-cli/bin/llama-cli`. Current source closes that missing-root
surface: native runners resolve image-baked Linux artifacts from
`/opt/infernix/engines/<adapterId>/bin/...` after checking the repo data root,
`infernix internal materialize-linux-native-engines` writes typed manifests and smoke-validated
entrypoints for the runnable Linux native adapter ids, and `docker/Dockerfile` bakes those roots
into the substrate image. Current source also threads non-secret model-cache hints to native
runners and maps native exit 75 to `model_cache_not_populated` so future native cache misses use
the same bootstrap retry family as Python adapters; artifact-producing native runners can receive
a worker-owned `--output-dir`, return an `infernix-native-artifact-file:<path>` marker, and let the
Haskell worker upload the file to `infernix-demo-objects` with secret-backed MinIO credentials. The
current CUDA Linux cycle replaces the runner-contract placeholders with runtime-backed wrappers
over image-baked `llama.cpp`, `whisper.cpp`, ONNX Runtime/CTranslate2, Basic Pitch ONNX,
faster-whisper, and Audiveris payloads. The remaining CUDA Linux blocker is rerunning serialized
per-engine validation so the native rows consume those payloads through live MinIO-backed
model/input hydration. Current source also passes typed model-cache/MinIO fields to
Python adapters; mounted linux-gpu validation passes `cabal test infernix-unit`, `cabal test
infernix-haskell-style`, `cabal build test:infernix-integration`,
`poetry --directory python run check-code`, `cabal run exe:infernix -- lint docs`, `docs check`,
`lint files`, `lint proto`, and `lint chart`; current validation also passes
`cabal run exe:infernix -- internal materialize-linux-native-engines`,
`cabal run exe:infernix -- lint docs`, `cabal run exe:infernix -- docs check`,
`cabal run exe:infernix -- test unit`, and `cabal run exe:infernix -- test lint` with mounted live
source after adding the Linux native runner-root materializer. The 2026-06-16 Apple host refresh
rechecks the machine-independent Phase 4 gate slice with `poetry run check-code` from `python/`,
`cabal build test:infernix-integration`, `cabal build all`, `./.build/infernix test unit`,
`./.build/infernix test lint`, `./.build/infernix docs check`, and focused
`./.build/infernix lint files/docs/proto/chart`.
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md), Stage 2 (CUDA Linux).
**Implementation**: `docker/Dockerfile`, `src/Infernix/Models.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Runtime/Pulsar.hs`, `chart/templates/deployment-engine.yaml`, `chart/values.yaml`, `bootstrap/linux-gpu.sh`
**Docs to update**: `DEVELOPMENT_PLAN/system-components.md`, `documents/architecture/daemon_topology.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Sprint 4.16 bakes every engine's CUDA framework venv into one image, which on linux-gpu produces a
~121 GB monolith — fine for `docker run --gpus all` but impractical to push through in-cluster Harbor
and load into Kind for the routed cohort run. Split the monolith so each engine pod pulls only its
own framework, making the cluster image flow practical.

### Deliverables

- **Dockerfile multi-stage split**: a shared `builder` stage (GHC + `cabal build all` + web build +
  proto + framework-free python) produces the `infernix`/`infernix-demo` binaries; a slim
  **control-plane / coordinator image** (`infernix-linux-gpu:local`) carries the binaries + the
  framework-free `python/` project + the cluster toolbelt, with **no** framework venvs; one
  **per-engine image** per framework engine (`infernix-engine-<engine>-linux-gpu:local` =
  CUDA-runtime base + python + the binary + only that engine's `--with cuda` venv).
- **Per-engine engine Deployments**: `chart/templates/deployment-engine.yaml` templates one engine
  Deployment per deployed framework engine, each referencing its per-engine image, keeping the
  Linux `required` anti-affinity per engine label and the GPU resource request.
- **Coordinator→per-engine routing**: the coordinator publishes batch work to
  `inference.batch.<mode>.<engine>` keyed on the model's `selectedEngine`→engine name; each
  per-engine engine subscribes only to its own topic. `Infernix.Models` owns the
  engine→image/topic mapping.
- **Lifecycle**: `infernix cluster up` builds/pushes/loads each per-engine image through the same
  Harbor-first flow (`src/Infernix/Cluster.hs` `clusterWorkloadImageRef` becomes a per-engine set).
- **Linux native-engine materialization lane** (folds in former Task 9):
  `src/Infernix/Engines/LinuxNative.hs` owns the allowlisted Linux native adapter ids and
  `infernix internal materialize-linux-native-engines` writes typed manifests plus smoke-validated
  entrypoints into image-owned `/opt/infernix/engines/<id>/bin/` roots for the
  native-process-runner rows (speech, gguf-LLM, audio-to-MIDI, CTranslate2 transcription, OMR);
  the worker checks the repo data root first and then this Linux image root. The current Linux
  payloads are runtime-backed wrappers over image-baked native payloads, and strict image smoke
  validates those payloads before the root is accepted; Wave I keeps the full routed service-path
  proof.
  The Apple equivalent is the Sprint 1.14 headless Metal/Core ML materialization lane.

### Validation

- Machine-independent gates on the recorded CUDA Linux host: temp-copy Linux GPU launcher
  `cabal build all`, `cabal test infernix-unit`, and `cabal test infernix-haskell-style` pass;
  current-source `cabal run exe:infernix -- lint docs`, `docs check`, `lint chart`, `lint files`, and
  `lint proto` all exit 0.
- The slim control-plane image and at least one per-engine image build, and a per-engine venv inside
  its image reports `torch.cuda.is_available()` True with `--gpus all`.

### Remaining Work

- **Code (machine-independent) — DONE:** the Dockerfile split (slim
  22.4 GB control-plane + `engine.Dockerfile` per-engine images, transformers GPU-validated), the
  Models engine→name/image mapping, substrate-neutral pool/member topic derivation, internal
  daemon metadata derived from `enginePools` and `engineMembers`, coordinator pool-topic routing,
  member-id service selection, chart Deployments/PDBs, lifecycle image builds, and
  Harbor per-engine image overlays. The temp-copy Linux GPU launcher has passed `cabal build all`,
  `cabal test infernix-unit`, and `cabal test infernix-haskell-style`; current-source lint/docs/chart
  gates also exit 0, and the Linux native runner-root materializer now passes command-level smoke
  validation plus `infernix test unit` and `infernix test lint` through the mounted Linux
  outer-container lane.
- **Live cluster cohort validation — DONE:** the 2026-06-20 full `./bootstrap/linux-gpu.sh test`
  gate built the selected per-engine images, brought up the routed `linux-gpu` cluster, exercised
  framework-specific and native rows through live MinIO-backed model/input hydration, and passed
  routed E2E including the 16-row GPU browser matrix. The same current source passed rebuilt-image
  `./bootstrap/linux-cpu.sh test`. Basic Pitch TensorFlow, Omnizart, and MT3 remain named residual
  rows outside the active runtime catalog.

---

## Sprint 4.18: Engine Artifact Manifests and Matrix Reconciliation [Done]

**Status**: Done
**Code-side closure**: Complete for the machine-independent scope — `src/Infernix/Models.hs` now reflects the researched runnable/residual matrix (Apple CTranslate2 runnable as CPU, Basic Pitch TensorFlow / MT3 / Omnizart residual rather than runnable, Wan Apple MPS residual), `residualMatrixRowIdsForMode` records named residual rows without promoting them into runtime catalogs, `infernix-engine-artifacts` is an explicit bucket in object layout, demo bucket repair, and chart MinIO provisioning, and the Apple manifest materializer from Sprint 1.14 supplies typed engine-artifact manifests. `src/Infernix/Engines/LinuxNative.hs` now adds the Linux image-owned materialization surface: typed manifests, smoke-validated runner roots for `llama-cpp-cli`, `whisper-cpp-cli`, `onnx-runtime-native`, `ctranslate2-native`, and `jvm-native`, a generated CLI command, a `docker/Dockerfile` bake step, and runtime-backed wrappers that parse the native worker argument shape, can emit worker-upload artifact markers, delegate to the image-baked native payload layer, and return per-family result shapes instead of failing normal invocation. `src/Infernix/Runtime/Worker.hs` now hydrates native model cache files and input-object refs from MinIO, passes non-secret model-cache hints and optional artifact output directories to native runners, uploads `infernix-native-artifact-file:<path>` outputs to `infernix-demo-objects` with worker-owned MinIO credentials, and maps native exit 75 to `model_cache_not_populated`, preserving the bootstrap retry family for future real native cache misses. `src/Infernix/Engines/AppleSilicon.hs` now also materializes deterministic Apple validation-runner payloads for `llama-cpp-cli`, `whisper-cpp-cli`, `ctranslate2-native`, `mlx-native`, `onnx-runtime-native`, and `jvm-native`; those runners satisfy the substrate result-shape contract for validation but remain explicit Wave I placeholders for Apple real native payloads. The shared engine-root installer now handles Docker overlay image-layer reruns by replacing a generated final root when the existing-root backup rename is rejected as a cross-device operation, while keeping rollback behavior on ordinary filesystems. The generated Linux native wrappers use `/bin/sh`; strict image smoke with `--require-native-payload` now validates the baked llama.cpp, whisper.cpp, ONNX Runtime/CTranslate2, Basic Pitch ONNX, faster-whisper, and Audiveris payload presence on the native CUDA Linux image, while unit/temp materialization keeps a non-strict portable fallback. The 2026-06-18 native CUDA Linux validation rebuilt `infernix-linux-gpu:local` with `./bootstrap/linux-gpu.sh build`, strict-smoked all five baked Linux native adapter roots with `--require-native-payload`, and passed rebuilt-image `infernix test unit` (Haskell plus PureScript 71/71). Earlier validation passed through the Linux outer-container lane with mounted live source by `cabal run exe:infernix -- internal materialize-linux-native-engines`, `cabal run exe:infernix -- test unit` (Haskell unit plus PureScript 71/71), `cabal run exe:infernix -- lint docs`, `cabal run exe:infernix -- docs check`, and `cabal run exe:infernix -- test lint`; rechecked on the Apple host with `cabal build all`, `./bootstrap/apple-silicon.sh build`, `./.build/infernix internal materialize-metal-engines`, direct validation-runner output checks, `./.build/infernix test unit`, `./bootstrap/linux-cpu.sh build`, and a fresh-container `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix internal materialize-linux-native-engines` rerun over baked `/opt/infernix/engines/<adapterId>/` roots.
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md), Stage 2 — the selected `linux-gpu` plus `linux-cpu` full-suite gates passed on 2026-06-20, so routed integration and E2E consume the runtime-backed Linux native payloads through live MinIO-backed model/input hydration. Apple headless `coreml-native` runtime-load smoke has passed, Apple transformers now completes `llm-qwen25-safetensors`, and current source closes the previously missing `llama-cpp-cli/bin/llama-cli` root for `llm-tinyllama-gguf` with validation-wrapper payloads. The latest Apple full integration rerun passed on the Apple Silicon host: the source-fingerprint image freshness path rebuilt once for source changes, reused the stamped image during later edge-port validation cluster cycles, completed the active Apple catalog through the host engine daemon, and validated pinned Apple host-engine `Exclusive` duplicate rejection. Focused Apple e2e now passes after preserving prompt upload refs, sending input-object refs only to object-input model families, and extending the model-bootstrap ready wait to a 900-second cold-start envelope; the latest focused pass used rebuilt image digest `sha256-ed34da86992bb1a4d285f00feb77051d12eb4fa594b7bb34ed73561a027b1a71`. The subsequent full Apple `./.build/infernix test all` aggregate passed lint, unit (Haskell plus web 71/71), integration, and 9/9 routed Playwright against rebuilt cluster image digest `sha256-f4a30f4e177206b64ce5a0d3abea8d72a8bdbe637148530e1619bdf5ce8ae7c3`, including Qwen, object-input audio/tool rows, and every active Apple catalog row.
**Implementation**: `README.md`, `docker/Dockerfile`, `src/Infernix/Engines/LinuxNative.hs`, `src/Infernix/Models.hs`, `src/Infernix/Objects/Layout.hs`, `src/Infernix/Objects/Upload.hs`, `src/Infernix/Demo/Bootstrap.hs`, `chart/values.yaml`, `chart/templates/minio/job-provisioning.yaml`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Bootstrap/Models.hs`, `proto/infernix/manifest/runtime_manifest.proto`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/object_storage.md`, `documents/engineering/model_lifecycle.md`
**Docs to update**: `README.md`, `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/object_storage.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Apply the model/engine research findings to the runtime catalog and artifact lifecycle. Engine
software, model weights, and user-visible generated artifacts must be three distinct artifact
classes, and the README matrix must stop promoting residual or unproven engine cells.

### Deliverables

- add a typed engine-artifact manifest model with adapter id, engine name, substrate, architecture,
  artifact kind, source reference, versions, digest, optional MinIO key, install root, entrypoint,
  and smoke command
- add the `infernix-engine-artifacts` MinIO bucket contract for immutable content-addressed engine
  payloads, separate from `infernix-models` weights and `infernix-demo-objects` user/demo artifacts
- materialize engine payloads through validated temp roots and final-root rename into
  `./.data/engines/<adapterId>/` on Apple or image-owned
  `/opt/infernix/engines/<adapterId>/` on Linux; Docker image-layer reruns use the explicit
  replace-after-validation fallback when the existing-root backup rename is rejected; the current
  Linux payloads are runtime-backed wrappers over image-baked native payloads; Wave I keeps the
  full routed service-path proof
- update `src/Infernix/Models.hs` and generated catalog docs to match the researched matrix:
  Apple CTranslate2 is viable CPU, vLLM CPU is not a portable `linux-cpu` default, MT3/JAX and
  Omnizart remain residual until compatibility spikes pass, Wan Apple MPS remains residual, and
  Basic Pitch TensorFlow stays residual behind ONNX/Core ML fallback lanes
- keep CUDA framework stacks image-owned or pre-materialized; they are never installed on a user
  request path

### Validation

- unit coverage for manifest key derivation, digest handling, install-root selection, and missing
  native runner diagnostics
- `infernix lint docs` proves README matrix and model catalog docs agree with the generated model
  catalog
- materialization smoke coverage for the Linux native runner roots is unit-covered locally, and the
  generated Linux wrappers use a portable `/bin/sh` shebang so Apple host-native unit validation can
  exercise the manifest/root contract without a Linux-only `/usr/bin/bash` dependency; the native
  arm64 Docker lane also proves a fresh-container rerun can replace image-layer baked
  `/opt/infernix/engines/<adapterId>/` roots without a cross-device rename failure; strict Linux
  native payload smoke now passes in the CUDA image, and the Apple headless lane now has installed
  Metal bridge plus `coreml-native` runtime-load smoke evidence
- failed materialization leaves no partial final root and redelivers or negatively acknowledges
  work when asynchronous
- The 2026-06-15 native CUDA Linux host pass built the governed GPU launcher with
  `./bootstrap/linux-gpu.sh build`, then validated the baked image through
  `infernix test unit`, `infernix test lint`, `infernix lint files`, `infernix lint docs`,
  `infernix lint proto`, `infernix lint chart`, `infernix docs check`, and
  `infernix internal materialize-linux-native-engines`. Direct baked-runner checks also exercised
  normal invocation shapes for `llama-cpp-cli` LLM inline text, ONNX image `.png` object refs, and
  ONNX Basic Pitch `.mid` object refs, and the `--output-dir` marker path that produced
  `infernix-native-artifact-file:/tmp/infernix-native-output-check/audio-basic-pitch-onnx.mid`
  with the file present. These gates prove the image-owned native wrapper surface, model-cache
  argument plumbing, and marker/upload wiring in the worker; the 2026-06-20 full-suite reruns then
  supplied routed native-output evidence through the service path.
- The current 2026-06-18 follow-up replaces the generated Linux runner-contract placeholders with
  runtime-backed wrappers over image-baked native payloads and keeps their cache contract:
  model-cache-aware invocations fail with exit 75 until `<model-cache-root>/<model-id>/.ready`
  exists, then proceed normally once the ready sentinel is present. Mounted current-source
  linux-gpu validation passes `infernix test unit`, `infernix test lint`, `infernix lint files`,
  `infernix lint docs`, `infernix lint proto`, `infernix lint chart`, `infernix docs check`, and
  `infernix internal materialize-linux-native-engines`; the unit suite executes the generated
  `llama-cpp-cli` runner on both missing-cache and ready-cache paths, proving the native cache-miss
  boundary that the worker maps to `model_cache_not_populated`.

### Remaining Work

- Add any follow-up Apple real-native-payload evidence under Wave I; Apple validation-wrapper roots
  remain explicit placeholders until that lane is scheduled.
- Keep Basic Pitch TensorFlow, MT3/JAX, Omnizart, and Wan Apple MPS as residual rows until
  compatibility spikes prove maintained runnable lanes.

---

## Sprint 4.19: Substrate-Neutral Engine Pool Routing [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded Linux outer-container lane — the staged Dhall schema
now carries `enginePools` and `engineMembers`, Haskell encode/decode/render paths preserve that
graph, generated configs derive normal pool topics and pinned member topics from
`(runtimeMode, poolId/memberId, modelId)`, coordinator batch routing resolves model → pool from the
validated graph, engine-role startup selects member assignments by stable member id first, and
service consumer validation rejects illegal subscription states (`Failover` for service consumers,
ambiguous model ownership, raw topic-like ids, unknown models, missing bidirectional pool/member
links, empty pools or members, and routable models with no eligible member). Proven by
`./bootstrap/linux-cpu.sh build`; rebuilt-image
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test unit`;
and mounted live-source `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
`cabal run exe:infernix -- lint files/docs/proto/chart`, `cabal run exe:infernix -- docs check`,
and `cabal run exe:infernix -- test lint`. Current source also adds the single-host logical
`Shared` backlog harness in `test/integration/Spec.hs`: it opens two real Pulsar WebSocket
consumers on an isolated derived pool/model topic with service-shaped subscription names and
`receiverQueueSize=1`, holds the first request unacked, publishes a second request, and asserts the
free consumer receives that second request by decoding the request id from the Pulsar payload. The
harness is compile-validated on the present Linux outer-container lane by
a mounted-source linux-gpu Compose launcher run of `cabal build test:infernix-integration`. The
2026-06-16 Apple integration rerun executed the harness against the live Apple Pulsar lane. The
same current-source mounted linux-gpu validation also passes `infernix test lint`,
`infernix test unit`, focused `infernix lint files/docs/proto/chart`, `infernix docs check`, and
`git diff --check`. The 2026-06-16 Apple host refresh also compile-validates this integration
target with `cabal build test:infernix-integration`. The 2026-06-16 Linux CPU rebuilt-image
integration pass then exercised the Kubernetes side of the same contract: two-worker engine-pool
placement, unique-topic `Shared` backlog/backpressure, engine pod replacement, engine node drain,
anti-affinity, lifecycle rebinding, demo-off coordinator/engine publication, and pool-topic
exactly-once accounting.
**Cohort gate**: Closed [Wave J](cohort-validation-waves.md) — real Pulsar cluster validation
has now proved pinned `Exclusive` member routes, process-qualified service consumer names,
same-machine Apple host-member coexistence on a `Shared` pool subscription, Apple single-host
logical `Shared` backlog/backpressure, Apple production `demo_ui = false` assertions, and Linux
CPU pool placement/backpressure in the Kind topology. Wave J closed the Linux GPU/CUDA cohort
gate on 2026-06-20, so the sprint is `Done`; physical Apple multi-host member routing remains
hardware-deferred proof while no second Apple host is available.
**Implementation**: `dhall/InfernixSubstrate.dhall`, `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `README.md`, `documents/architecture/engine_pool_routing.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`, `documents/architecture/runtime_modes.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace substrate-specific batch-topic special cases with one typed engine-pool graph. The
coordinator routes to model-derived pool topics, Pulsar distributes normal pool work through broker
backpressure, and pinned routes use explicit per-member topics.

### Deliverables

- add a typed `enginePools` / `engineMembers` schema to the staged substrate Dhall record
- derive every legal batch topic from `(runtimeMode, poolId, modelId, optional memberId)` rather
  than accepting operator-authored topic strings
- validate that every routable model has at least one eligible member and every member-declared model
  exists in the active generated catalog
- replace the single Apple `inference.batch.apple-silicon.host` lane with Apple host-daemon members
  selected by stable host id
- preserve Linux GPU framework isolation as pool placement, not as a separate routing doctrine
- keep model cache state independent from assignment state; removed assignments become evictable
  rather than immediately deleting warm artifacts

### Validation

- unit coverage rejects duplicate pool ids, unknown model ids, no-member model routes, unknown
  Apple host ids, and raw topic strings
- unit coverage proves topic derivation and member subscription selection for Apple, Linux CPU, and
  Linux GPU
- integration coverage proves coordinator publication to derived pool/model topics and engine
  consumption from assigned topics
- Linux CPU integration proves Kubernetes-observed pool/member placement and broker-native
  backpressure on unique derived pool/model topics
- a Pulsar-backed test proves same-machine Apple host-member daemons can coexist on one `Shared`
  subscription for an isolated derived pool/model topic
- a Pulsar-backed single-host logical multi-member test proves backlog/backpressure distribution
  across available Apple pool members while pinned routes use `Exclusive`

### Remaining Work

None. Dhall schema, Haskell decoder/renderer, topic derivation, coordinator pool-topic handoff,
member-id selection, and invalid-graph rejection have landed. Wave J closed the Linux GPU/CUDA
pool-placement and full cohort validation on 2026-06-20, paired with rebuilt-image
`linux-cpu` validation. The supported schema emits only `enginePools` and `engineMembers`; runtime
daemon metadata is derived internally from that graph. Physical Apple multi-host routing is
hardware-deferred proof, not a blocker for the current single-host logical backpressure gate.

---

## Sprint 4.20: Coordinator Topic Lifecycle and Reflected Dhall Schema [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/DhallSchema.hs`, `src/Infernix/DhallSchema/Reflection.hs`, `src/Infernix/HostConfig.hs`, `src/Infernix/ClusterConfig.hs`, `src/Infernix/SecretsConfig.hs`, `src/Infernix/Substrate.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `test/unit/Spec.hs`, `infernix.cabal`
**Docs to update**: `README.md`, `documents/architecture/pulsar_ml_workflow.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Close Phase 4's common-shape runtime gap: the coordinator owns explicit topic
creation/reconciliation before consumers and schema registration run, and the binary exposes the
Dhall type expressions its decoders accept.

### Deliverables

- derive the startup topic set from `DemoConfig`, including coordinator request topics, engine
  pool/member request topics, result-like topics, the model-bootstrap request topic, and per-model
  bootstrap-ready topics
- run startup-topic reconciliation after namespace reconciliation and before schema registration in
  the service daemon startup path
- register schemas for every request-like and result-like topic derived from the active topology
- expose `infernix internal dhall-schema host|cluster|secrets|substrate` backed by the binary's
  Dhall decoder expectations
- cover the command parser, schema output shape, packaged schema-file presence, and startup-topic
  derivation in unit tests

### Validation

- `./bootstrap/linux-cpu.sh build`
- the rebuilt-image schema commands for `host`, `cluster`, `secrets`, and `substrate` emit
  non-empty schema text
- the rebuilt-image `infernix test unit` compose invocation passes the Haskell unit suite and the
  PureScript web suite (`71/71`)

### Remaining Work

None. The coordinator topic-lifecycle owner and reflected-schema command are closed, the checked-in
`dhall/Infernix*.dhall` files are the reflected output, and `infernix lint docs` now rejects schema
drift against the in-binary renderer.

---

## Remaining Work

None. Phase 4 returned to `Done` on 2026-06-20 after the selected `linux-gpu` accelerator plus
`linux-cpu` full-suite gates passed against current source. The closure evidence is recorded in
[cohort-validation-waves.md](cohort-validation-waves.md): the GPU lane reached real routed
framework and native rows after the vLLM memory-release/browser-session fixes, and the CPU lane
passed the rebuilt-image `./bootstrap/linux-cpu.sh test` gate end to end. The supported substrate
schema now emits reflected `enginePools` / `engineMembers` only, with runtime daemon metadata
derived internally during decode.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/runtime_modes.md` - honest runtime model, host-native Apple control-plane, cluster-daemon role, Apple host inference executor behavior, and Linux substrate lanes
- `documents/architecture/model_catalog.md` - per-substrate engine binding and generated catalog contract
- `documents/architecture/engine_pool_routing.md` - substrate-neutral engine-pool graph, derived
  topic contract, and broker-native backpressure model
- `documents/engineering/docker_policy.md` - shared Linux substrate image doctrine and snapshot launcher expectations
- `documents/engineering/build_artifacts.md` - build roots, generated proto handling, and image-owned toolchain contract
- `documents/engineering/apple_silicon_metal_headless_builds.md` - Apple headless Metal/Core ML materialization and engine manifest rules
- `documents/engineering/model_lifecycle.md` - durable artifacts, bundle metadata, and cache semantics
- `documents/engineering/object_storage.md` - MinIO model, engine-artifact, and demo-object bucket rules plus service-placement access notes
- `documents/engineering/storage_and_state.md` - durable-versus-derived state inventory
- `documents/engineering/implementation_boundaries.md` - Haskell versus Python versus chart ownership
- `documents/engineering/portability.md` - portable platform rules versus Apple or Linux substrate detail
- `documents/development/python_policy.md` - shared Python project, `poetry run` contract, and `check-code` gate
- `documents/development/testing_strategy.md` - per-substrate integration coverage and engine-binding parity
- `documents/operations/apple_silicon_runbook.md` - ghcup prerequisites and daemon-driven Apple engine setup

**Product or reference docs to create/update:**
- `documents/reference/api_surface.md` - browser and operator API contract
- `documents/reference/web_portal_surface.md` - manual inference user surface

**Cross-references to add:**
- keep [00-overview.md](00-overview.md), [system-components.md](system-components.md), and
  [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) aligned when the API,
  model catalog, or generated demo-config contract changes
- the per-family result contract (the 19-row to `ResultFamily` and inline-versus-object-ref
  mapping) is owned by [../documents/architecture/model_catalog.md](../documents/architecture/model_catalog.md)
  and [../documents/development/testing_strategy.md](../documents/development/testing_strategy.md);
  artifact object references land in the `infernix-demo-objects` bucket described in
  [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md)
- Apple-native real inference depends on the headless Apple Metal/Core ML materialization lane
  owned by [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  Sprint 1.14 and documented in
  [../documents/engineering/apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md)
