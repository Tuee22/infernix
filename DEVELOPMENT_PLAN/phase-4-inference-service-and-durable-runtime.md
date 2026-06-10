# Phase 4: Inference Service and Durable Runtime

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Define the Haskell service runtime, the shared Python engine-adapter contract, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the shared Linux substrate image, the
> substrate-generated `.dhall` role contract, and the Apple host inference bootstrap that together
> make the runtime model honest and durable.

## Phase Status

Phase 4 closes around the staged-substrate runtime contract, the shared Python
adapter boundary, the Pulsar-driven request or result contract, the explicit engine-runner
dispatch, and the mounted `InfernixCluster.dhall` cluster-wiring contract. The runtime,
catalog, cache, object-storage, daemon-role, and substrate-file contracts are closed in the
worktree and were validated in Wave A (Apple) and Wave C (CUDA Linux). The phase is `Active`
because the inference contract itself is being completed: the worker resolves the real engine
for every supported matrix row and publishes a real per-family result. The reopened sprints
(4.1, 4.2, 4.3, 4.7, 4.8, 4.10, 4.11, 4.12, 4.14) and the new Sprint 4.15 carry that remaining
work; Apple-native real inference also depends on the tart Metal-engine artifacts built by
[Phase 1](phase-1-repository-and-control-plane-foundation.md) Sprint 1.13. The real per-family
inference contract is re-validated on both cohorts in
[Wave I](cohort-validation-waves.md), and the phase cannot return to `Done` until that wave
closes. The phase narrative describes the supported MinIO-backed shape directly through the
runtime, cache, and object storage contracts.

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
daemons run inference directly and publish results; Apple cluster daemons publish work to a
dedicated host batch topic consumed by same-binary host daemons that run Apple-native inference
and publish the completed results. The
runtime worker dispatches supported Python-native and native adapters through explicit harness
branches and invokes the real engine for the selected binding: the Python adapter `transform`
over a prebuilt host wheel for `python-stdio` bindings, or the real native runner binary resolved
from a typed `HostConfig` absolute path for `native-process-runner` bindings. The worker fetches
model weights lazily from the `infernix-models` MinIO bucket (`adapters.model_cache.get_model_path`
on the Python side; the coordinator model-bootstrap path on the native side) and publishes a
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

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Active]

**Status**: Active
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

Add the closed `ResultFamily` sum type and `resultFamilyForDescriptor` (derived from `family` +
`artifactType` + `matrixRowId`), export `allMatrixRowIds`, and schedule the non-text input
object-ref field on `InferenceRequest`/`WorkerRequest`; the output `ResultPayload.object_ref`
already exists on the wire. Tracked for [Wave I](cohort-validation-waves.md).

---

## Sprint 4.2: Inference Request Pipeline Over the Durable Object Store and Pulsar Contract [Active]

**Status**: Active
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

Replace the `src/Infernix/Runtime/Worker.hs` stub returns with real engine output:
`runInferenceWorker` carries the real `WorkerResponse` for `python-stdio` bindings, and the
`native-process-runner` branch invokes the real engine binary resolved from a typed `HostConfig`
absolute path instead of `renderNativeRunnerOutput`. Tracked for
[Wave I](cohort-validation-waves.md).

---

## Sprint 4.3: Honest Apple Host-Native and Linux Container Runtime Parity [Active]

**Status**: Active
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/object_storage.md`, `documents/operations/apple_silicon_runbook.md`, `documents/engineering/portability.md`

### Objective

Keep one service contract while telling the truth about execution context and inference
placement: Apple control-plane commands are host-native, Apple cluster daemons own request-topic
consumption and host-batch handoff, Apple inference execution and result publication are
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

Apple host-native `infernix service` runs the real Apple-native Metal engine using the tart-built
artifacts under `./.data/engines/<adapterId>/` (built by
[Phase 1](phase-1-repository-and-control-plane-foundation.md) Sprint 1.13) and publishes the real
per-family result. Tracked for [Wave I](cohort-validation-waves.md).

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

## Sprint 4.7: Shared Python Adapter Project and Poetry-Driven Quality Gate [Active]

**Status**: Active
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

Replace `common.render_engine_output` and the six trivial adapter `transform` bodies with real
framework calls over prebuilt host wheels, loading weights through
`adapters.model_cache.get_model_path`, and add the artifact-adapter seam that returns an object
reference; the `run_context_adapter` protobuf-over-stdio boundary is unchanged. Tracked for
[Wave I](cohort-validation-waves.md).

---

## Sprint 4.8: Pulsar-Driven Production Inference Surface [Active]

**Status**: Active
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/values.yaml`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/tools/pulsar.md`, `documents/architecture/runtime_modes.md`, `documents/reference/cli_reference.md`

### Objective

Make the Pulsar-driven production inference surface the canonical way to request inference in any
non-demo deployment.

### Deliverables

- the active `.dhall` schema includes `request_topics`, `result_topic`, daemon-role metadata, and
  engine-binding metadata; the final Apple role schema also includes host batch-topic and Pulsar
  connection-mode metadata
- `src/Infernix/Runtime/Pulsar.hs` subscribes to request topics, dispatches work through the
  worker or host-batch handoff path, and publishes typed protobuf responses to the configured
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

Publish the real per-family inference result over the production Pulsar surface — inline text for
the LLM and speech families, an `infernix-demo-objects` object reference for the artifact families
— and emit no generic-success payload. Tracked for [Wave I](cohort-validation-waves.md).

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

- `docker build -f docker/Dockerfile -t infernix-linux-cpu:local --build-arg
  RUNTIME_MODE=linux-cpu --build-arg BASE_IMAGE=ubuntu:24.04 --build-arg DEMO_UI=true .`
  succeeds on supported Linux CPU hosts and produces the default snapshot
- `docker build -f docker/Dockerfile -t infernix-linux-gpu:local --build-arg
  RUNTIME_MODE=linux-gpu --build-arg BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04
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

## Sprint 4.10: Apple Silicon Daemon-Driven Engine Bootstrap [Active]

**Status**: Active
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

The Apple daemon-driven engine bootstrap consumes the tart-built Metal-engine artifacts copied to
`./.data/engines/<adapterId>/` ([Phase 1](phase-1-repository-and-control-plane-foundation.md)
Sprint 1.13) before the host engine runs. Tracked for [Wave I](cohort-validation-waves.md).

---

## Sprint 4.11: Per-Substrate Engine Selection in the Catalog [Active]

**Status**: Active
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

Per-substrate engine selection resolves each row to its real adapter (Python wheel or native
binary) and fails fast on missing model metadata rather than dispatching a placeholder. Tracked for
[Wave I](cohort-validation-waves.md).

## Sprint 4.12: Substrate-Owned Daemon Role, Startup Selection, and Fallback Removal [Active]

**Status**: Active
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

Remove the `src/Infernix/Runtime/Worker.hs` `renderNativeRunnerOutput` / `nativeRunnerLabel`
debug-metadata native fallback once real native dispatch lands, preserving the
fail-fast-on-unsupported-adapter contract. Tracked for [Wave I](cohort-validation-waves.md).

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

## Sprint 4.14: Declarative-State Phase Prose Rewrite [Active]

**Status**: Active
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

Revise the closing declarative prose so real per-family engine dispatch (not deterministic metadata
output) is the always-intended steady state read forward into Phases 5-7. Tracked for
[Wave I](cohort-validation-waves.md).

---

## Sprint 4.15: Per-Family Real-Output Result Contract and Object-Ref Artifact Families [Planned]

**Status**: Planned
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
- re-validated on both cohorts in [Wave I](cohort-validation-waves.md)

### Remaining Work

Implement and validate; depends on the Sprint 4.1 type and proto-field work and the Sprint 4.7
adapter seam.

---

## Remaining Work

Phase 4 is `Active`. The real per-family inference contract is in progress across the reopened
Sprints 4.1, 4.2, 4.3, 4.7, 4.8, 4.10, 4.11, 4.12, 4.14 and the new Sprint 4.15. Apple-native real
inference also depends on [Phase 1](phase-1-repository-and-control-plane-foundation.md) Sprint 1.13
(tart-built Metal engine artifacts). The phase returns to `Done` only after
[Wave I](cohort-validation-waves.md) reruns the full Apple and CUDA Linux gates against real
inference.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/runtime_modes.md` - honest runtime model, host-native Apple control-plane, cluster-daemon role, Apple host inference executor behavior, and Linux substrate lanes
- `documents/architecture/model_catalog.md` - per-substrate engine binding and generated catalog contract
- `documents/engineering/docker_policy.md` - shared Linux substrate image doctrine and snapshot launcher expectations
- `documents/engineering/build_artifacts.md` - build roots, generated proto handling, and image-owned toolchain contract
- `documents/engineering/model_lifecycle.md` - durable artifacts, bundle metadata, and cache semantics
- `documents/engineering/object_storage.md` - repo-local object storage rules plus reserved MinIO path and service-placement access notes
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
- Apple-native real inference depends on the tart-built Metal engine artifacts owned by
  [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  Sprint 1.13 and the [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md)
  tart build lane
