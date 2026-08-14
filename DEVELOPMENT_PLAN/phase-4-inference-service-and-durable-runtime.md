# Phase 4: Inference Service and Durable Runtime

**Status**: Blocked — strict numerical execution waits for Phase 3.
**Blocked by**: Phase 3
**Implementation state behind the blocker**: Active — three sprints carry open work.
Sprint 4.35 (native runner front-end correction and failure diagnosability) was opened by a
`linux-cpu` cohort failure found while executing Phase 3 Sprint 3.16's gate: llama.cpp b9704 split
`llama-cli` into an interactive chat front-end, so a *successful* Linux run published chat chrome as
the model's answer — a realness-contract violation on the success path — while a failed one
published one bit, because the argv silenced the only channel carrying the reason. Both are
corrected on the Linux lanes, and the same probable Apple defect is named as
[Wave Y](cohort-validation-waves.md) work. Sprint 4.34 (machine-local admission and fail-closed
member identity) has closed the admission move code-side, which unblocks Phase 8 Sprints 8.10 and
8.11; only the broker-side member claim remains, named in that sprint's `Remaining Work` with its
behavioural proof owned by the cohort wave. Sprint 4.32 (verified Apple and Linux CPU execution
enforcers and executable-model routing) has closed its exact-source `linux-cpu` half and waits on
selected Apple hardware for the observer and adversarial-breach proof. Sprint 4.36 is `Done` by
supersession and re-home: Phase 1 Sprint 1.23 owns and implements the per-engine Python producer, so
strict Phase 1 validation has no forward dependency on this phase for that prerequisite. Every other
sprint in this phase is `Done`.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Define the Haskell service runtime, the shared Python engine-adapter contract, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the shared Linux substrate image, the
> substrate-generated `.dhall` role contract, and the Apple host inference bootstrap that together
> make the runtime model honest and durable.

## Phase Status

Phase 4 closes around the staged-substrate runtime contract, the shared Python adapter boundary, the
Pulsar-driven request and result contract, the explicit engine-runner dispatch, the mounted
`/opt/infernix/cluster.dhall` cluster-wiring contract, and the substrate-neutral engine-pool routing
contract. Sprints 4.1–4.20 established those typed contracts — typed dispatch, catalog, pool
routing, cache, and object storage — and they stand; later sprints replaced engine internals and the
memory model without undoing them. The worker resolves the selected engine entrypoint for every
supported matrix row and publishes the typed per-family result surface: inline text for the LLM and
speech families, and a typed `infernix-demo-objects` object reference for the source-separation,
audio-to-MIDI, music-transcription, image, video, audio-generation, and OMR artifact families.

**Realness by construction.** An audit established that an earlier "real per-family output" closure
was, for several catalog rows, satisfied by silent fabrication rather than real model execution: the
Apple native engine layer was a validation wrapper, and on Linux the source-separation, audio-to-MIDI
(ONNX run on `np.zeros`), and OMR rows returned constant artifacts while whisper.cpp and CTranslate2
masked runtime failures. Sprints 4.21–4.23 replaced those internals so the engine code is
structurally incapable of returning a fabricated result: every missing-weights, load, or engine
failure raises and becomes `status=failed`. Real Linux engines, fixed weight provisioning, ONNX
adoption where it is the mature free choice, and modern PyTorch rebinds for the music-transcription
rows landed with it, and a realness lint owned with
[phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md) enforces the
guarantee mechanically. The architectural contracts from Sprints 4.1–4.20 were not undone; only the
faked engine internals were replaced. The Linux real-output gate closed under
[Wave K](cohort-validation-waves.md) and the Apple real-engine gate under
[Wave L](cohort-validation-waves.md), owned by
[phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md).
The removed fabrication surfaces are tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

**Music transcription.** The obsolete MT3 residual is replaced by `music-mt3-infer` and
`music-mr-mt3`. Both bind through `mt3-infer` on the PyTorch adapter, stage weights through the
model-cache contract, disable upstream auto-downloads, and are generated for `linux-cpu`,
`linux-gpu`, and `apple-silicon`; Apple uses the PyTorch CPU path and no MPS claim is made.
[Wave O](cohort-validation-waves.md) proved both rows and [Wave P](cohort-validation-waves.md)
closed the full suite, including the 27 GB `video-wan21-t2v` row that Phase 8 eager model-cache
staging unblocked.

**Memory safety.** Inference is admitted before it runs and bounded while it runs. Sprint 4.26
introduced per-model RAM footprints, a per-substrate inference budget, and serialized runtime
admission, after an unbounded full-catalog `test integration` drove the Apple host into memory
exhaustion and the OS killed the daemon. Sprint 4.27 generalized that into a pure typed model —
`InferenceMemoryBudget` and `InferenceError`, with request-time rejection rather than a
daemon-startup veto — replacing the Apple-only integer budget, the catalog-wide fail-fast, the
hardcoded floor, and the stringly runtime failure payload. Sprint 4.30 replaced the proof-free
`admitModelMemory :: … -> Maybe InferenceError` with `Either InferenceError MemoryGrant` and routed
the sole engine spawn through a grant-gated capped-engine kernel, because a `Nothing` carries no
evidence that admission ran and a raw unbounded spawn makes a host out-of-memory condition a
representable outcome. Sprint 4.31 added the checked `HostMemoryPartition`, the required
`ModelMemoryFootprint`, and the budget that names its enforcer, dropping `UnenforcedMemoryBudget`.
Sprint 4.33 narrows what those closures claim: completing a run without exhausting the host is a
sample of the inference lane as run, not a bound. Phase 1 Sprint 1.19 supersedes the public
admission surface with resource-indexed `compileRuntimePlan`, package-owned live refinement, and
`RuntimePlan` / `ExecutableModel` for engine launch, while coordinator routing projects
`CompiledPlacement` / `CompiledDaemon`. Phase 6 owns the currently fail-closed Linux GPU RAM/VRAM
construction and Phase 8 owns the final wire schema. Canonical doctrine:
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
and [../documents/architecture/typed_execution_plan.md](../documents/architecture/typed_execution_plan.md).

**Managed state transitions.** Sprint 4.28 gates the readiness-sentinel commit on a
`PayloadVerified` witness minted by a real bounded probe, returns typed evidence from
`awaitModelBootstrapReady`, capability-gates the raw commit and spawn primitives, and gives native
runners a real environment carrying `HOME` and `TMPDIR`. Sprint 4.29 makes the coordinator's
upstream model fetch bounded and classified: a descriptive `User-Agent` (a UA-less request tripped
the origin WAF), a `Retry-After`-honoring bounded redelivery, an ack on permanent failure so a
rate-limited origin is not re-hammered forever, and a `PayloadVerified` minted only when the
uploaded object's byte length matches the download, so a truncated upload cannot mint a lying
sentinel. Both closed under [Wave V](cohort-validation-waves.md). Canonical doctrine:
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

**Common shape.** The coordinator owns explicit Pulsar topic-lifecycle reconciliation derived from
the typed runtime graph, replacing implicit broker auto-create reliance, and the binary emits its
own decoder-reflected Dhall schema through
`infernix internal dhall-schema host|cluster|secrets|substrate`. Per Phase 8 there are no
version-controlled schema files; the schema exists only as the reflected output of the Haskell
decoder types, emitted on demand.

**Result timestamps.** Durable and Pulsar result timestamps share one total ISO-8601 conversion
contract: the result-topic protobuf path uses the `Infernix.Storage` `formatTimestamp` /
`parseTimestamp` pair, and a malformed `createdAt` returns `Nothing` instead of throwing from a
partial `read`.

**Matrix accuracy.** The README matrix and the generated catalog describe the active CUDA cells
honestly: `ONNX Runtime (CPU)` for basic-pitch, and CPU Ubuntu-release binaries for the llama.cpp
and whisper.cpp rows. The Apple transformers framework path is covered by the active safetensors LLM
row `llm-smollm2-safetensors`. Wan2.1-T2V remains the documented Apple residual, with union coverage
supplied by the real CUDA cell.

Routed Apple `infernix test e2e` preserves prompt upload refs through single-flight dispatch,
object-input catalog families carry an `inputObjectRef`, and the engine-side model-bootstrap
readiness wait uses a 3600-second cold-start envelope aligned with the browser result wait so a cold
upstream snapshot for the safetensors LLM row is not treated as a failure. The cluster image path
uses source-fingerprint image reuse and dependency-layer caching, so a long Docker interval reflects
Cabal dependency compilation, image export, Harbor push, and Helm/Pulsar readiness waits rather than
a Docker daemon deadlock. Per-lane attestations live in
[cohort-validation-waves.md](cohort-validation-waves.md).

## Current Repo Assessment

The repository has typed request or response shapes, typed runtime result metadata, a
README-matrix-backed generated catalog, protobuf-backed manifest and result helpers, explicit
cache status or eviction or rebuild flows, a shared Python adapter project whose setup entrypoints
write idempotent bootstrap manifests, explicit initialization/materialization helpers, and daemon
behavior driven by the effective runtime-config file. Durable model artifact storage lives in the
`infernix-models` MinIO bucket. The operator runtime config is a typed Dhall record at repo-root
`./infernix.dhall`, created by `infernix init` and decoded in-process by the `dhall` Haskell library.
Cluster deployment derives a cluster-role mirror for mounted consumers. The runtime
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
`get_model_path()` or uploads an artifact. The coordinator eagerly stages every configured model
into the `infernix-models` MinIO bucket behind the `warm-model-cache` barrier; workers hydrate their
derived local cache from those staged objects through `adapters.model_cache.get_model_path`, with
the per-inference bootstrap path retained only for unexpected loss. The worker publishes a
per-family real result: inline text for the LLM and speech families, and a typed
`infernix-demo-objects` object reference for the source-separation, audio-to-MIDI,
music-transcription, image, video, audio-generation, and OMR artifact families. Unsupported adapter
ids fail fast with typed errors instead of returning a generic success payload. The effective runtime
config, runtime result metadata, publication surface,
and browser contracts still expose the active substrate through `RuntimeMode` or `runtimeMode`
identifiers, while the final publication contract also distinguishes cluster daemon location from
host inference executor location.

## Substrate Config Ownership Contract

This phase owns the conversion from the README-scale matrix to runtime-consumable substrate state.

- the service owns the typed registry that represents matrix rows
- the substrate selected by `infernix init` chooses the engine column for each supported row
- repo-root `./infernix.dhall` carries that selected catalog as the operator runtime authority
- host consumers use the initialized config, while cluster consumers use the cluster-role
  deployment mirror derived by `cluster up`
- `infernix-demo` and the integration suite both choose the active engine binding for a README row
  from their effective runtime config

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Done]

**Status**: Done
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

None.

---

## Sprint 4.2: Inference Request Pipeline Over the Durable Object Store and Pulsar Contract [Done]

**Status**: Done
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
- process-isolated runtime workers derive the canonical engine command from the selected binding;
  Phase 1 Sprint 1.19 later removed arbitrary adapter-command overrides from the supported surface
- local materialization remains cache-oriented and idempotent, not authoritative

### Validation

- `infernix test integration` proves generated catalog publication, per-entry routed inference
  execution for the active built substrate's catalog, Pulsar schema publication, and typed topic
  or result persistence on the validated path
- `infernix test unit` proves large outputs return typed object references and protobuf manifests
  round-trip through the supported storage helpers

### Remaining Work

None.

---

## Sprint 4.3: Honest Apple Host-Native and Linux Container Runtime Parity [Done]

**Status**: Done
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
**Implementation**: `infernix.cabal`, `src/Infernix/Webapp.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Models.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
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

None.

---

## Sprint 4.8: Pulsar-Driven Production Inference Surface [Done]

**Status**: Done
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

None.

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
  `/workspace/.build/outer-container/build/infernix.dhall` before substrate-aware work
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
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Types.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Runtime/Worker.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/development/testing_strategy.md`

### Objective

Make the per-substrate engine column in the README matrix the canonical input for catalog
generation.

### Deliverables

- each matrix row records explicit engine selection per substrate
- the active built substrate picks the appropriate engine binding when generating
  `infernix.dhall`
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

None.

## Sprint 4.12: Substrate-Owned Daemon Role, Startup Selection, and Fallback Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Service.hs`, `src/Infernix/Webapp.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `docker/Dockerfile`, `web/test/run_playwright_matrix.mjs`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
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

None.

---

## Sprint 4.13: Cluster Manifest Materialization [Done]

**Status**: Done
**Implementation**: `src/Infernix/ClusterConfig.hs` (new; the `ClusterConfig` decoder type is the schema — Phase 8 removed the version-controlled `dhall/InfernixCluster.dhall`), `src/Infernix/Service.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/templates/configmap-cluster-config.yaml` (new; Phase 8 reduces it to an `nindent` passthrough of the binary-rendered string)
**Docs to update**: `documents/engineering/cluster_config_manifest.md`, `documents/tools/pulsar.md`, `documents/architecture/daemon_topology.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the typed cluster-wiring record as the `ClusterConfig` Haskell decoder type (its
reflected schema replaces any hand-written `.dhall`; Phase 8 confirms zero version-controlled schema files).
Delete every `env:` block from `chart/templates/deployment-{coordinator,engine}.yaml`; the pods
mount the cluster `ConfigMap` at `/opt/infernix/cluster.dhall` and the Haskell daemon decodes it
at startup. Retire every Pulsar / catalog / daemon-location / engine-command env-var fallback in
favor of typed `ClusterConfig` fields.

### Deliverables

- the `ClusterConfig` decoder type (reflected schema) with the `PulsarConfig`, `MinioConfig`
  (non-credential fields), `DemoBackendConfig`, `EngineConfig`, `CoordinatorConfig` records named in
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
- the `infernix` binary generates the entire `cluster.dhall` body;
  `chart/templates/configmap-cluster-config.yaml` only `nindent`s that binary-produced string into
  the ConfigMap `data` and never renders or parses Dhall (see Phase 8).

### Validation

- `cabal build all` clean, `infernix test lint` clean, `infernix test unit` clean.
- `grep -rn '^\s*-\s*name:\s*INFERNIX_' chart/templates/deployment-{coordinator,engine}.yaml`
  returns zero matches.
- `infernix test integration` on `linux-gpu` round-trips through coordinator + engine pods that
  read from the mounted Dhall ConfigMap (proven by removing the corresponding `env:` entries
  before the test runs).
- `cabal test infernix-unit` PASSES with `assertClusterConfig`, which renders and decodes a
  `ClusterConfig` fixture through `decodeClusterConfigFile`. The historical non-empty
  `engine.commandOverrides` fixture was removed by Phase 1 Sprint 1.19 with the arbitrary command
  surface itself.
- `cabal build all`, `cabal test infernix-haskell-style`, and
  `cabal run infernix -- lint {docs,files,chart,proto}` all exit zero against the
  `ClusterConfig` renderer.
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C with full
  `linux-cpu` and `linux-gpu` gates against the mounted `ClusterConfig`.

### Remaining Work

None.

---

## Sprint 4.14: Declarative-State Phase Prose Rewrite [Done]

**Status**: Done
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

None.

---

## Sprint 4.15: Per-Family Real-Output Result Contract and Object-Ref Artifact Families [Done]

**Status**: Done
**Implementation**: `proto/infernix/runtime/inference.proto`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Storage.hs`, `python/adapters/`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
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
  [phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md))
- re-validated through the Wave I `linux-gpu` plus `linux-cpu` attestation

### Remaining Work

None.

---

## Sprint 4.16: Per-Engine Isolated Framework Venvs [Done]

**Status**: Done
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
- Apple host-native inference opts in to an `apple-silicon` group declared by the affected per-engine
  projects, so the Apple lane resolves its own framework wheels without the CUDA or Linux CPU sets.
- The Haskell worker prefers the per-engine venv (`python -m adapters.<module>`) and falls back to
  the fail-fast shared path when absent.
- The linux-gpu image build bakes each engine's `--with cuda` venv as a resilient, separate layer.
- The linux-gpu base image is aligned to CUDA 12.8 to match the supported 570 driver branch
  (Sprint 4.8 follow-on in `bootstrap/linux-gpu.sh`).
- Basic Pitch TensorFlow (its published package pins TensorFlow `<2.15.1`) and the old TF-era
  Omnizart package do not resolve on the Python 3.12 / CUDA 12.8 substrate and stay named residual
  rows; the active Omnizart, MT3-PyTorch, and MR-MT3 rows use maintained PyTorch packages.

### Validation

- `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `poetry run check-code`, and
  `infernix lint files/docs` pass as machine-independent gates.
- `poetry install --directory python/engines/transformers --with cuda` resolves the CUDA framework
  set and `torch.cuda.is_available()` is True on the selected accelerator.
- The Linux CPU image build bakes the `transformers` and `pytorch` `--with linux-cpu` venvs and
  passes `poetry --directory python run check-code`; the real per-family output those venvs carry is
  proven by the Wave K and Wave L attestations.

### Remaining Work

None.

---

## Sprint 4.17: Per-Engine Engine Images and Batch Routing [Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `src/Infernix/Models.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Runtime/Pulsar.hs`, `chart/templates/deployment-engine.yaml`, `chart/values.yaml`, `bootstrap/linux-gpu.sh`
**Docs to update**: `DEVELOPMENT_PLAN/system-components.md`, `documents/architecture/daemon_topology.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Sprint 4.16 bakes every engine's CUDA framework venv into one image, which on linux-gpu produces a
~121 GB monolith — fine for `docker run --gpus all` but impractical to push through in-cluster Harbor
and load into Kind for the routed cohort run. Split the monolith so each engine pod pulls only its
own framework, making the cluster image flow practical.

### Deliverables

- **Dockerfile multi-stage split**: a shared `builder` stage (GHC + `cabal build all` + web build +
  proto + framework-free python) produces the `infernix` binary; a slim
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
- **Native runner result contract**: a native exit 75 maps to `model_cache_not_populated`, reusing
  the Python bootstrap retry family, and an artifact-producing runner emits an
  `infernix-native-artifact-file:<path>` marker that the worker uploads to `infernix-demo-objects`
  with secret-backed MinIO credentials.

### Validation

- Machine-independent gates pass: `cabal build all`, `cabal test infernix-unit`,
  `cabal test infernix-haskell-style`, and `infernix lint docs|chart|files|proto` plus
  `infernix docs check`.
- The slim control-plane image and at least one per-engine image build, and a per-engine venv inside
  its image reports `torch.cuda.is_available()` True with `--gpus all`.

### Remaining Work

None.

---

## Sprint 4.18: Engine Artifact Manifests and Matrix Reconciliation [Done]

**Status**: Done
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
  Apple CTranslate2 is viable CPU, vLLM CPU is not a portable `linux-cpu` default, MT3-PyTorch and
  MR-MT3 use `mt3-infer`, Omnizart uses the maintained ByteDance PyTorch piano row, Wan Apple MPS
  remains residual, and Basic Pitch TensorFlow stays residual behind ONNX/Core ML fallback lanes
- keep CUDA framework stacks image-owned or pre-materialized; they are never installed on a user
  request path
- Apple real-native-payload ownership sits with
  [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  Sprint 1.15 and [Wave L](cohort-validation-waves.md); no Phase 4 work remains for that Apple lane

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
  native payload smoke now passes in the CUDA image. The Apple lane's historical bridge/source
  smoke evidence is superseded; active Sprint 1.20 requires upstream
  MLX/coremltools installed-root evidence
- failed materialization leaves no partial final root and redelivers or negatively acknowledges
  work when asynchronous
- `infernix internal materialize-linux-native-engines` on the baked Linux image, followed by
  `infernix test unit`, `infernix test lint`, `infernix lint files|docs|proto|chart`, and
  `infernix docs check`, proves the image-owned native wrapper surface, model-cache argument
  plumbing, and the worker's marker/upload wiring. Direct baked-runner checks exercise the normal
  invocation shapes for `llama-cpp-cli` inline text, ONNX image `.png` object refs, ONNX Basic Pitch
  `.mid` object refs, and the `--output-dir` marker path
- the generated runners keep their cache contract: a model-cache-aware invocation fails with exit 75
  until `<model-cache-root>/<model-id>/.ready` exists, then proceeds normally. The unit suite
  executes the generated `llama-cpp-cli` runner on both the missing-cache and ready-cache paths,
  proving the native cache-miss boundary the worker maps to `model_cache_not_populated`

### Remaining Work

None.

---

## Sprint 4.19: Substrate-Neutral Engine Pool Routing [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs` (substrate decoder type = reflected schema; no tracked `.dhall`), `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
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
- service consumer validation rejects every illegal subscription state: `Failover` for service
  consumers, ambiguous model ownership, raw topic-like ids, unknown models, missing bidirectional
  pool/member links, empty pools or members, and a routable model with no eligible member
- the supported schema emits `enginePools`, `engineMembers`, and the explicit `engineDaemons`
  metadata derived from that graph
- physical Apple multi-host member routing stays hardware-deferred proof while no second Apple host
  is available; the single-host logical backlog/backpressure gate stands in its place

### Validation

- unit coverage rejects duplicate pool ids, unknown model ids, no-member model routes, unknown
  Apple host ids, and raw topic strings
- unit coverage proves topic derivation and member subscription selection for Apple, Linux CPU, and
  Linux GPU
- integration coverage proves coordinator publication to derived pool/model topics and engine
  consumption from assigned topics
- Linux CPU integration proves Kubernetes-observed pool/member placement and broker-native
  backpressure on unique derived pool/model topics
- same-machine Apple host-member daemon coexistence on one `Shared` subscription is refused rather
  than proven: one engine process per machine is a correctness rule, so the host-local engine lock
  is armed on every substrate and no test asserts two host engine daemons sharing a subscription.
  Sprint 4.34 owns that reversal — it deletes the coexistence case with its exclusively-owned
  helpers and removes the Apple engine-lock waiver the case required
- a Pulsar-backed single-host logical multi-member test proves backlog/backpressure distribution
  across available Apple pool members while pinned routes use `Exclusive`

### Remaining Work

None.

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
- `infernix lint docs` rejects schema drift against the in-binary renderer, and no `.dhall` schema
  is version-controlled

### Validation

- `./bootstrap/linux-cpu.sh build`
- the rebuilt-image schema commands for `host`, `cluster`, `secrets`, and `substrate` emit
  non-empty schema text
- the rebuilt-image `infernix test unit` compose invocation passes the Haskell unit suite and the
  PureScript web suite (`71/71`)

### Remaining Work

None.

---

## Sprint 4.21: Realness by Construction and Real Linux Engines [Done]

**Status**: Done
**Implementation**: `python/adapters/{pytorch_python,diffusers_python,transformers_python,common}.py`, `src/Infernix/Engines/LinuxNative.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `python/adapters/model_bootstrap.py`, `docker/Dockerfile`
**Docs to update**: `README.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/development/python_policy.md`, `documents/engineering/model_lifecycle.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the inference engine code structurally incapable of returning a fabricated result, and deliver
real Linux inference for every Linux-catalog row.

### Deliverables

- remove every adapter/runner fabrication branch; the sole success is a real `transform()` return or a
  real native-runner artifact, with all other cases raising / exiting non-zero
- real ONNX basic-pitch over the user input; real Audiveris invocation; de-masked whisper.cpp/CT2/llama
- real source separation (Demucs/Open-Unmix) and SDXL-Turbo on `linux-gpu`, fixing the broken
  github-`payload` weight staging
- `common.py` empty-artifact guard; single-file weight naming for GGUF/whisper-ggml/basic-pitch-onnx
- keep each row declared-runnable on its intended engine (declarative-target; no reclassification); not-yet-real rows fail closed until their real engine lands
- basic-pitch runs a no-TensorFlow `soundfile` + `scipy` + `mido` + `onnxruntime` pipeline in the
  `onnx-runtime-native` runner: it decodes and resamples the actual input audio, windows it, runs the
  baked `nmp.onnx` over that real audio rather than zeros, reproduces the upstream
  posteriorgram→MIDI note creation, and writes a real `.mid`; every failure exits non-zero
- source separation resolved in favor of PyTorch plus the real first-party single-file weight rather
  than an unproven ONNX export. The htdemucs row's `downloadUrl` is the canonical first-party
  checkpoint — a single binary `.th` that passes the weight guard and stages as `payload` — and
  `_separate_sources` loads the trusted package dict with `weights_only=False` before handing it to
  `demucs.states.load_model`, because torch ≥ 2.6 defaults `weights_only=True` (which rejects the
  pickled demucs model classes) and `demucs.pretrained.get_model` cannot load a directory
- Open-Unmix has its own `_separate_open_unmix` path rather than routing through the Demucs loader,
  because it is not a demucs checkpoint: the `openunmix` package joins the pytorch engine venv, the
  `audio-open-unmix` row points at the first-party `umxhq` record, a multi-file bootstrap path
  stages the four per-target state dicts as `<target>.pth`, and the adapter rebuilds the `umxhq`
  architecture and loads them with `strict=False` before running the `Separator`
- the weight-staging realness guard (`bodyLooksLikeHtml` / `_looks_like_html`) rejects an HTML or
  otherwise non-binary download response, so a repository landing-page URL fails closed as
  `status=failed` instead of staging the page as the weight
- the generated `linux-native` Audiveris runner passes a writable per-invocation `HOME` to just the
  Audiveris child, because the JVM tool aborts at class init without one and derives its data and
  config folders from it. That is a tool-invocation requirement rather than configuration-via-env,
  so it is compatible with the no-env-var doctrine and the env lint

### Validation

- `./bootstrap/linux-gpu.sh test` plus rebuilt `./bootstrap/linux-cpu.sh test` pass only on real
  inference for every Linux-catalog row; withholding weights/engine yields a visible `status=failed`
- the realness lint (Phase 6) blocks any reintroduced fabrication

### Remaining Work

None.

---

## Sprint 4.22: Modern Music-Transcription Models and JAX/TF Retirement [Done]

**Status**: Done — MT3 catalog replacement proven by [Wave P](cohort-validation-waves.md).
**Implementation**: `src/Infernix/Models.hs`, `python/adapters/pytorch_python.py`, `python/adapters/model_bootstrap.py`, `python/engines/pytorch/pyproject.toml`, `docker/Dockerfile`
**Docs to update**: `README.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the music-transcription rows real on all substrates using modern maintained models on adapters
already supported, eliminating the JAX/ancient-TF stacks.

### Deliverables

- MT3-PyTorch and MR-MT3 → `openmirlab/mt3-infer`; Omnizart → the maintained ByteDance
  `piano_transcription_inference` CRNN over the real input audio; basic-pitch → its official ONNX
  runtime; all on `pytorch-python` / `onnx-runtime-native`
- the `jax_python` and `tensorflow_python` adapters, their `python/engines/{jax,tensorflow}` venv
  projects and `pyproject.toml` scripts, and the corresponding `Models.hs`
  `engineBindingForSelectedEngine` cases are deleted. The resolved "support all mainstream formats"
  decision dropped TF/JAX coverage rather than binding new real rows
- the bootstrap worker stages MT3-PyTorch as a two-file pretrained directory (`config.json`,
  `mt3.pth`) and MR-MT3 as the Hugging Face `mt3.pth` payload, so the adapter calls
  `mt3_infer.load_model(..., auto_download=False)` and never downloads behind the model-cache
  contract
- the adapter pins the upstream compatibility surface — bounded `transformers >=4.46,<4.50`, the
  real `torch.utils.checkpoint` T5 shim, the `absl-py` dependency, and the MT3 / MR-MT3
  `T5Block.forward` `cache_position` / `past_key_value` wrappers — so both rows produce real MIDI
- keep the README matrix ↔ generated catalog ↔ `model_catalog.md` in parity for `infernix lint docs`

### Validation

- Code-side: `./bootstrap/linux-cpu.sh build`, `poetry --directory python run check-code`, the
  PyTorch engine dependency dry-run, Linux-image `infernix lint docs`, and `cabal test infernix-unit`
  pass for the MT3 bindings.
- Cohort: rebuilt `./bootstrap/linux-cpu.sh test` and `./bootstrap/linux-gpu.sh test` both pass with
  both MT3 rows producing real MIDI output, closed under [Wave O](cohort-validation-waves.md) and
  [Wave P](cohort-validation-waves.md); the per-rebuild `transformers` / `mt3-infer` compatibility
  history is recorded in [cohort-validation-waves.md](cohort-validation-waves.md).

### Remaining Work

None.

---

## Sprint 4.23: Real Input Fixtures and Fail-Closed Per-Row Tests [Done]

**Status**: Done
**Implementation**: `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/fixtures/artifactSamples.js`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/demo_app_test_plan.md`

### Objective

Make Phase 4's real-engine validation self-contained: real per-family inputs + fail-closed per-row int/e2e
that exercise the real Linux engines, so no Phase-4 validation is blocked by a later phase.

### Deliverables

- real per-family input fixtures shared across substrates, replacing the degenerate silence-WAV and
  1x1-PNG inputs with a real speech utterance, a real music mixture, a real instrument phrase, and a
  real single-staff score image; the OMR input-type defect that fed `musicXmlBuffer()` instead of a
  score image is fixed
- the fixtures are generated programmatically — a real RIFF/PCM WAV encoder for the speech,
  separation, and instrument-phrase inputs, and a real grayscale-PNG encoder with hand-computed
  Adler-32/CRC-32 for the score image — so no new Cabal dependency is introduced
- fail-closed per-row int+e2e (trust the result, fail on `status=failed`, assert the per-family
  contract plus a light object-ref existence and non-empty presigned fetch with magic-byte probing)
- the speech fixture is a synthesized formant sweep rather than an intelligible utterance; a
  genuinely spoken mono 16 kHz sample is still owed for the speech row's real-output proof

### Validation

- `./bootstrap/linux-gpu.sh test` plus rebuilt `./bootstrap/linux-cpu.sh test` per-row suites fail when a
  Linux engine is withheld or returns a non-real result

### Remaining Work

None.

---

## Sprint 4.24: Pulsar Result Timestamp Canonicalization [Done]

**Status**: Done
**Cohort gate**: Not required; the change is a machine-independent serialization/parsing closure with
no transport or live engine behavior change.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Storage.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/object_storage.md`, `documents/development/testing_strategy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make durable and Pulsar result timestamps share one total, ISO-8601 conversion contract.

### Deliverables

- export or otherwise share the existing safe timestamp codec instead of duplicating `show` / `read`
- make malformed result-proto `createdAt` values return `Nothing` / a typed failure path without
  crashing the result bridge
- add a roundtrip regression for canonical timestamps and a malformed-timestamp regression

### Validation

- `cabal test infernix-unit`, `cabal build test:infernix-integration`, and
  `cabal run exe:infernix -- lint docs` all pass; unit coverage proves canonical wire timestamps,
  roundtrips through the shared parser, and malformed-input failure

### Remaining Work

None.

---

## Sprint 4.25: Matrix Substrate-Accuracy Closure [Done]

**Status**: Done — code-side complete and machine-independent-validated; Wave R proved the Apple routed per-model matrix, and Wave S proved the current `linux-cpu` and `linux-gpu` full-suite lanes against the honest supported matrix cells.
**Implementation**: `src/Infernix/Engines/LinuxNative.hs`, `python/native-runners/apple_native_runner.py`, `src/Infernix/Models.hs`, `README.md`
**Docs to update**: `README.md` (matrix Notes), `documents/architecture/model_catalog.md`

### Objective

Make every matrix cell accurate for the substrate its README column advertises, and close two
substrate-divergence defects the matrix review surfaced.

### Deliverables

- Row 11 (basic-pitch ONNX) CUDA lane: **relabeled** the README cell `ONNX Runtime (CPU)` and the
  matching `Models.hs` ModeBinding (`requiresGpu = False`), because `LinuxNative.hs` runs
  `CPUExecutionProvider` and only the CPU `onnxruntime` wheel is installed. The supported cell is
  therefore the CPU ONNX Runtime path, proven under [Wave S](cohort-validation-waves.md).
- Rows 4/6 (llama.cpp GGUF, whisper.cpp speech) CUDA lane: **documented** that the CUDA column runs the
  CPU Ubuntu-release binaries today (README Notes); those supported cells are proven under
  [Wave S](cohort-validation-waves.md).
- Row 14 (`piano_transcription`): corrected the stale `Models.hs` "test is red until the adapter binding
  lands" note — the binding is landed (`pytorch_python.py`) and the real-output evidence is closed
  under [Wave R](cohort-validation-waves.md) and [Wave S](cohort-validation-waves.md).
- Row 17 (Wan2.1-T2V) Apple: kept as the documented Apple residual
  (`residualMatrixRowIdsForMode AppleSilicon`), with the union-coverage invariant satisfied by the real
  CUDA cell and stated in the README Note.
- Substrate-divergence guards: **added** the divide-by-zero guard to the Linux basic-pitch onset path
  that the Apple runner already has; the Apple smoke now fails closed when the engine runtime does not
  import.

### Validation

- Code-side: `cabal build all`, `infernix lint docs`, and the Python `check-code` AST/realness gate
  all pass.
- Cohort: Apple routed Playwright passes under [Wave R](cohort-validation-waves.md), and the rebuilt
  `linux-cpu` and `linux-gpu` full suites pass under [Wave S](cohort-validation-waves.md).

### Remaining Work

None.

---

## Sprint 4.26: Apple-Silicon Inference RAM Admission and Bounded Peak (Fail-Clean, Never OOM) [Done]

**Status**: Done — the Apple integration and routed per-model matrix closed under
[Wave R](cohort-validation-waves.md), and the rebuilt `linux-cpu` full suite closed under
[Wave S](cohort-validation-waves.md).
**Supersession note**: Sprint 4.27 keeps the serialized runtime-admission idea but supersedes this
sprint's catalog-wide fail-fast, integer sentinel/floor, Apple-only budget scope, and stringly result
payload.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs`, `src/Infernix/HostConfig.hs`, `src/Infernix/HostTools.hs`, `src/Infernix/ProjectInit.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Web/Contracts.hs`, `docker/Dockerfile`
**Docs to update**: `documents/architecture/realness_contract.md`, `documents/architecture/daemon_topology.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/object_storage.md`, `documents/operations/apple_silicon_runbook.md`, `README.md`

### Objective

Make on-host (`apple-silicon`) inference RAM-safe by construction: peak resident memory is bounded
against an explicit per-substrate budget, and the only legitimate hard-fail is a single model whose
footprint exceeds the total available inference RAM — surfaced as a clean `status=failed`, never an
OS OOM-kill.

### Deliverables

- **Done.** Per-model RAM footprint (`modelRamFootprintMib`) on `ModelDescriptor` and every mirror
  layer (JSON codec, Dhall decoder/renderer/type, PureScript contract), from a conservative
  per-engine default until a measured peak-RSS pass refines it.
- **Done.** Per-substrate available-inference-RAM budget (`inferenceRamBudgetMib`) on `DemoConfig`,
  computed per substrate (apple-silicon: host physical RAM − colima pledge − host reserve via
  `sysctl`/`colima`; linux-cpu/gpu: recorded engine pod memory limit).
- **Done.** Config-time hard-fail in `validateDemoConfig`: an over-budget model is a typed error
  naming the model, its footprint, and the budget (enforced on `apple-silicon`, where model memory is
  host RAM; Linux engines run in Kubernetes-bounded pods).
- **Done.** Runtime admission control at the serialized engine-execution critical section
  (`overRamBudgetRejection`) so an over-budget model fails cleanly instead of being launched;
  serialization bounds peak resident memory to one admitted model at a time.
- The retired unbounded on-host inference path is recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

- Unit: `validateDemoConfig` rejects an over-budget config and accepts an in-budget one, under
  `cabal test infernix-unit` and `cabal test infernix-haskell-style`.
- Cohort (apple-silicon, paired with Phase 6 Sprint 6.37): closed under
  [Wave R](cohort-validation-waves.md) — a full per-model `test integration` completed every
  admitted row and no admitted row was terminated by the host. Per Sprint 4.33 that is evidence the
  admission and ceiling behaved, not that host exhaustion is unrepresentable.
- Linux CPU: closed under [Wave S](cohort-validation-waves.md) through the full
  `./bootstrap/linux-cpu.sh test` suite, where host-RAM admission is a no-op by design because the
  engines run in Kubernetes-bounded pods.

### Remaining Work

None.

---

## Sprint 4.27: Typed Resource Memory Admission and Inference Errors [Done]

**Status**: Done — code-side complete and Wave T closed on `linux-cpu` plus the selected `linux-gpu`
accelerator.
**Historical-scope note**: this sprint and its Wave T evidence describe the pre-audit
`InferenceMemoryBudget` admission path. Phase 1 Sprint 1.19 supersedes that runtime path with
indexed compile/refine/executable capabilities, and Linux GPU now fails plan compilation closed
until Phase 6 Sprint 6.44 supplies verified dual RAM/VRAM enforcement.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/DemoConfig.hs`,
`src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`,
`src/Infernix/Storage.hs`, `proto/infernix/runtime/inference.proto`,
`src/Infernix/Bridge/Result.hs`, `src/Infernix/Cluster.hs`, and the substrate budget-resolution
helpers used by generated config and runtime admission.
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`,
`documents/architecture/model_catalog.md`, `documents/architecture/daemon_topology.md`,
`documents/architecture/engine_pool_routing.md`, `documents/architecture/realness_contract.md`,
`documents/engineering/testing.md`, `documents/development/testing_strategy.md`,
`documents/development/chaos_testing.md`, `documents/operations/apple_silicon_runbook.md`,
and this plan.

### Objective

Generalize the FIFO/serialized RAM guard into a pure, DRY resource-admission model across
substrates without making capacity a daemon-startup veto. Runtime admission rejects only the
oversized request, and the result payload carries a typed error with explicit quantities.

### Deliverables

- `InferenceMemoryBudget` is a closed type: `EnforcedMemoryBudget` carries `resource`, `source`,
  and `availableMib`, while `UnenforcedMemoryBudget` is explicit and never inferred from
  non-positive integers.
- `InferenceError` is a closed ADT with `ModelMemoryLimitExceeded` carrying at least `modelId`,
  `requiredMib`, `availableMib`, budget resource, and budget source. Other failure classes remain
  typed rather than generic strings.
- `ResultPayload` / protobuf / storage / Pulsar conversion support a typed error branch distinct
  from successful `inline_output` and `object_ref`.
- `validateDemoConfig` no longer fails the entire daemon solely because one model exceeds the active
  memory budget. It may emit capacity diagnostics, but runtime admission owns rejection.
- Apple budget resolution removes the hardcoded floor. An over-pledged host computes an enforced
  `0 MiB` budget instead of accidentally disabling the guard.
- `linux-cpu` admission uses the cluster engine pod memory limit. `linux-gpu` admission uses GPU
  VRAM, because supported GPU models allocate there.

### Validation

- Unit tests cover pure admission decisions for in-budget, over-budget, enforced zero, and explicit
  unenforced budgets.
- Unit tests prove config validation accepts mixed catalogs where at least one model is too large.
- Proto/storage/Pulsar roundtrips preserve typed `ModelMemoryLimitExceeded` fields.
- Substrate tests prove Apple, Linux CPU, and Linux GPU resolve the intended budget resource/source.

### Remaining Work

None.

---

## Sprint 4.28: Evidence in Runtime and Engines [Done]

**Status**: Done — the Managed-State-Transition Doctrine reopen (gate the readiness-sentinel commit on
a `PayloadVerified` witness, typed `awaitModelBootstrapReady` evidence, capability-gated commit/spawn
primitives, and a real native-runner environment) is code-side closed on the machine-independent
gates, and the single-accelerator (apple-silicon) plus `linux-cpu` full-suite sign-off closed under
[Wave V](cohort-validation-waves.md).
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `python/native-runners/apple_native_runner.py`
**Blocked by**: Sprint 1.16, 3.14
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase — gate the
readiness-sentinel commit on a `PayloadVerified` witness minted by a real bounded probe (closing the
unconditional package-backed `.ready` path); return typed evidence from `awaitModelBootstrapReady`;
capability-gate the raw commit and spawn primitives; and give native runners a real environment
carrying `HOME` and `TMPDIR` — encoding evidence, not hope. The doctrine generalizes the
results-side realness contract to state transitions: for every state there is a transition and typed
evidence, and every operation acting on that state requires the evidence. See the canonical doctrine
at [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- the readiness-sentinel commit is gated on a `PayloadVerified` witness whose constructor is
  unexported and which is minted only by a real bounded MinIO HEAD probe (`verifyUploadedPayload`)
  for downloaded payloads or by the package-backed recognition probe
  (`packageBackedPayloadVerified`); `commitReadySentinel` requires it, closing the previously
  unconditional package-backed sentinel write
- `awaitModelBootstrapReady` returns typed `ModelBootstrapReady` evidence minted from a real
  matching ready event, and `waitForModelBootstrapReady` becomes the derived boolean wrapper
- the raw commit and spawn primitives are capability-gated so callers cannot invoke them without the
  corresponding evidence
- native runners receive a real environment carrying `HOME` and `TMPDIR`: `workerProcessEnvironment`
  is built from the typed `Infernix.Cluster.Subprocess.SubprocessEnv` rather than the previous empty
  `env = Just []`, the Apple setup spawn routes through the same typed env, and the Apple payload
  smoke and the Python native-runner child spawns (`_native_runner_child_env`) carry both

### Validation

- the code-side gate set (`cabal build all`, `cabal test infernix-unit`,
  `cabal test infernix-haskell-style`, `infernix lint docs`, and `poetry run check-code` for the
  native-runner change) is exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

None.

---

## Sprint 4.29: Classified Model Download & Integrity-Witnessed Sentinel [Done]

**Status**: Done — the Bounded-Command Application & Bounded-HTTP reopen (the UA-bearing,
`Retry-After`-honoring classified `DownloadOutcome` download fold and the integrity-witnessed
`PayloadVerified` sentinel) is code-side closed on the machine-independent gates, and the
single-accelerator (apple-silicon) plus `linux-cpu` full-suite sign-off closed under
[Wave V](cohort-validation-waves.md).
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`
**Blocked by**: Sprint 1.17, 4.28
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
`documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, and the phase's
existing engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — consume the
Sprint 1.17 bounded-HTTP download kernel at the coordinator model-bootstrap site a cohort run hit (a
rate-limited 403 on `music-omnizart`), and make the `.ready` sentinel witness integrity,
not existence. It encodes evidence, not hope: "retried forever with no backoff" and "a sentinel that
lies about a truncated upload" become terms that do not typecheck. It applies the
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
doctrine to the durable-runtime download and sentinel surface.

### Deliverables

- `handleBootstrapMessage`'s failure path (`handleBootstrapFailure`) folds on the typed
  `DownloadOutcome`: `DownloadRateLimited` / `DownloadTransient` → a bounded backoff (honoring
  `Retry-After`) then a negative-ack that redelivers; `DownloadPermanent` → an ack that STOPS the
  redeliver-immediately-forever loop, so Pulsar can no longer re-hammer a rate-limited origin
- `downloadUpstreamModelToFile` returns the downloaded byte count; `verifyUploadedPayload` takes the
  expected byte count and mints `PayloadVerified` only when the uploaded object's Content-Length
  matches (new `minioObjectContentLength`), replacing the HEAD-existence-only check — a truncated
  upload can no longer mint a lying `.ready` sentinel
- unit coverage for the `classifyDownloadStatus` fold and the integrity-witnessed mint

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint files/docs/proto/chart`, and `infernix docs check` are exercised on both the
  apple-silicon and linux-cpu lanes
- the end-to-end proof is a model-bootstrap wave including `music-omnizart`: the UA-bearing request
  succeeds, and a fault-injected 403 + `Retry-After` backs off per the header and fails as
  `status=failed` on a permanent classification rather than redelivering forever — closed under
  [Wave V](cohort-validation-waves.md)

### Remaining Work

None.

---

## Sprint 4.30: Memory-Grant Admission and Capped-Engine Kernel [Done]

**Status**: Done — the grant-gated capped-engine kernel is the foundation half of the
memory-safety-by-construction reopen; it is code-side closed on the machine-independent gate set, and
the single-accelerator (apple-silicon) plus `linux-cpu` behavioral sign-off closed under
[Wave W](cohort-validation-waves.md).
**Current-API note**: the signatures and implementation account below are the historical Sprint
4.30 surface. Phase 1 Sprint 1.19 removed `admitModelMemory` and the public bare-grant launch shape;
current compilation mints an indexed grant, live refinement produces `ExecutableModel`, and only
the package-internal capped-engine region receives its derived command and watchdogs.
**Supersession note**: this sprint supersedes Sprint 4.27's proof-free
`admitModelMemory :: InferenceMemoryBudget -> ModelDescriptor -> Maybe InferenceError` (a `Nothing`
carries no evidence that admission ran) with an `Either InferenceError MemoryGrant` that mints a typed
grant, and supersedes the raw unbounded engine spawn from Sprint 4.28
(`readCreateProcessWithExitCode` / `createProcess` in `runNativeWorker` / `runWorkerInvocation`) with a
capped-engine kernel that consumes the grant and bounds actual resident memory to the admitted ceiling.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Engines/AppleSilicon.hs`,
`python/native-runners/apple_native_runner.py`
**Blocked by**: Sprint 4.27, 4.28
**Docs to update**: `documents/architecture/bounded_inference_memory.md`,
`documents/architecture/runtime_modes.md`, `documents/architecture/realness_contract.md`,
`documents/operations/apple_silicon_runbook.md`, and this plan

### Objective

Make on-host and in-pod inference memory-safe by construction: an inference engine subprocess runs only
under a typed `MemoryGrant` minted by `admitModelMemory`, and the capped-engine kernel bounds its
actual resident memory to the admitted `MemoryCeiling`. The only legitimate hard-fail is a model whose
footprint exceeds the admitted capacity — surfaced as a clean `status=failed`
`ModelMemoryLimitExceeded`, never an OS OOM-kill. This is the foundation the checked-partition /
required-footprint / budget-enforcer-split work in Sprint 4.31 builds on. See the canonical doctrine at
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md).

### Deliverables

- `admitModelMemory` returns `Either InferenceError MemoryGrant` (replacing the proof-free
  `Maybe InferenceError`); `MemoryGrant` is an opaque newtype whose constructor is unexported, carrying
  the admitted `MemoryCeiling`, minted only on a successful admission decision
- a capped-engine kernel that is the sole engine-spawn path and requires a `MemoryGrant`, so an
  inference subprocess launched without an admission grant is not a constructible term
- historical macOS ceiling enforcement: the now-superseded `proc_pid_rusage` physical-footprint
  watchdog that SIGKILLed the engine process group when the resident footprint breached the
  admitted `MemoryCeiling`
- Linux ceiling enforcement: classification of the pod-cgroup / VRAM OOM exit into a typed
  `ModelMemoryLimitExceeded` rather than an opaque non-zero exit
- the raw `readCreateProcessWithExitCode` / `createProcess` engine spawns in `runNativeWorker` /
  `runWorkerInvocation` retired in favor of the grant-gated kernel
- the superseded proof-free admission and the raw engine spawns are recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Validation

Gates (closed under [Wave W](cohort-validation-waves.md)):

- `cabal build all` (`-Wall -Werror`) compiles the grant-gated kernel with the raw engine-spawn path
  removed
- `cabal test infernix-unit` covers grant mint on in-budget admission, `Left ModelMemoryLimitExceeded`
  on over-budget admission, and ceiling-breach classification for both the macOS watchdog and the Linux
  OOM-exit paths
- `cabal test infernix-haskell-style` passes, including the Phase 6 Sprint 6.42
  `unboundedEngineSpawnViolations` lint that keeps new engine-spawn call sites off the raw primitives
- `infernix test all` on apple-silicon plus linux-cpu drives a full over-capacity catalog with every
  over-budget row cleanly typed-rejected and no admitted row terminated by the host — closed under
  [Wave W](cohort-validation-waves.md). Per Sprint 4.33 this is evidence that admission and the
  ceiling behaved, not that a host out-of-memory condition is unrepresentable

### Remaining Work

None.

---

## Sprint 4.31: Host Memory Partition, Required Footprint, and Budget-Enforcer Split [Done]

**Status**: Done — the checked host partition, the required footprint newtype, and the
budget-that-names-its-enforcer split are the model half of the memory-safety-by-construction reopen;
implemented on top of Sprint 4.30, code-side closed on the machine-independent gate set, with the
single-accelerator (apple-silicon) plus `linux-cpu` behavioral sign-off closed under
[Wave W](cohort-validation-waves.md).
**Supersession note**: this sprint supersedes Sprint 4.26's bare-`Int` `modelRamFootprintMib` (a
default-0 footprint silently disables admission) with a required `ModelMemoryFootprint` newtype (no
bare-`Int`, no default-0); supersedes the hard-coded `appleHostReserveMib = 3072` reserve in
`resolveAppleInferenceRamBudgetMib` with a checked `HostMemoryPartition` (physical = vmReserve +
hostHeadroom + inferenceCapacity, rejecting oversubscription, headroom covering OS + routed-E2E
browser); and supersedes Sprint 4.27's `UnenforcedMemoryBudget` arm — "a budget enforced by nobody" is
no longer representable — with a budget that names its enforcer
(`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit`).
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Substrate.hs`,
`src/Infernix/Models.hs`, `src/Infernix/Web/Contracts.hs`
**Blocked by**: Sprint 4.30
**Docs to update**: `documents/architecture/bounded_inference_memory.md`,
`documents/architecture/model_catalog.md`, `documents/operations/apple_silicon_runbook.md`, and this
plan

### Objective

Make the memory model total and honest: every model carries a required `ModelMemoryFootprint` (no
bare-`Int` default-0 that silently disables admission), every budget names the enforcer that will
actually bound it (`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit`,
so "enforced by nobody" is unrepresentable), and the Apple host budget is a checked `HostMemoryPartition`
in which physical RAM = vmReserve + hostHeadroom + inferenceCapacity and oversubscription fails
construction rather than accidentally disabling the guard. This is the model layer atop the Sprint 4.30
grant-gated kernel. See the canonical doctrine at
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md).

### Deliverables

- `ModelMemoryFootprint`, a required newtype replacing bare-`Int` `modelRamFootprintMib` (default-0
  removed), threaded through the JSON codec, the Dhall decoder/renderer/type, and the purescript-bridge
  + generated `Contracts.purs`
- `InferenceMemoryBudget` as `HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget
  PodMemoryLimit`, with `UnenforcedMemoryBudget` dropped
- a checked `HostMemoryPartition` where physical RAM = vmReserve + hostHeadroom + inferenceCapacity, a
  constructor that rejects a partition oversubscribing physical RAM, and headroom that covers the OS
  plus the routed-E2E browser
- the hard-coded `appleHostReserveMib = 3072` reserve in `resolveAppleInferenceRamBudgetMib` replaced
  by the checked partition's `hostHeadroom`
- the superseded bare-`Int` footprint, the hard-coded reserve, and the `UnenforcedMemoryBudget` arm
  are recorded in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Validation

Gates (closed under [Wave W](cohort-validation-waves.md)):

- `cabal build all` (`-Wall -Werror`) compiles with the required footprint newtype and the
  enforcer-named budget across every mirror
- `cabal test infernix-unit` covers a `HostMemoryPartition` accepting a fitting split and rejecting an
  oversubscribing one, and a `ModelDescriptor` decode that fails closed when the footprint is absent
- `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, `infernix docs check`,
  and the web unit suite pass with the regenerated contracts
- `infernix test all` on apple-silicon plus linux-cpu proves the checked partition admits the fitting
  catalog and cleanly typed-rejects over-capacity rows — closed under
  [Wave W](cohort-validation-waves.md)

### Remaining Work

None.

---

## Remaining Work

Sprints 4.1 through 4.31, Sprint 4.33, and Sprint 4.36 are closed; their per-lane attestations are
recorded in [cohort-validation-waves.md](cohort-validation-waves.md). The open work is Sprint 4.32
(verified Apple and Linux CPU execution enforcers), Sprint 4.34 (the broker-side member claim), and
Sprint 4.35 (the Apple half of the native runner front-end correction). Each names what remains in
its own `Remaining Work`.

---

## Sprint 4.32: Verified Apple And Linux CPU Execution Enforcers [Active]

**Status**: Active
**Blocked by**: None for machine-independent implementation; Apple hardware validation remains gated
on an available selected Apple host
**Code-side closure**: Complete. The no-repo-owned-native-source audit rejected the direct
`proc_pid_rusage` FFI exemption, so the Apple observer is now a package-internal bounded public-API
observer over fixed `/usr/bin/top` and `/usr/bin/footprint` commands. Phase 1 owns the
resource-indexed compiler and the live-enforcer refinement boundary: coordinators project compiled
placements and daemon capabilities, engine subscription and launch receive `RuntimePlan` /
`ExecutableModel`, and raw presentation decoders, routing constructors, and process commands are
hidden. This phase's opaque single-flight authority, Linux sampler-loss fail-closed path, and live
adversarial Linux breach regression are implemented and source-matched, and the exact-source
`linux-cpu` cohort has passed. Only the selected Apple hardware proof remains.
**Cohort gate**: selected `apple-silicon` plus `linux-cpu`, on a new typed-execution-plan wave
**Implementation**: `src/Infernix/Runtime/CappedEngine.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Docs to update**: `documents/architecture/typed_execution_plan.md`, `documents/architecture/bounded_inference_memory.md`, `documents/architecture/runtime_modes.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Verify the exact Apple and Linux CPU execution enforcers, keep engine launch restricted to
successfully refined capabilities, and make coordinator handling total for both available and
unavailable compiled placements.

### Deliverables

- startup acquisition fails closed when Apple footprint sampling is unavailable
- Apple process-group footprint sampling uses fixed absolute public `/usr/bin/top` plus
  `/usr/bin/footprint` operations behind one private bounded Haskell observer; its explicit
  environment, close-fds process group, standard-stream caps, total deadline, exhaustive cleanup,
  exact byte accounting, and parser have no direct FFI or caller-constructible raw process spec
- Linux CPU uses a verified process-group RSS watchdog that sums every child-group member and kills
  only that group on breach; the live pod `memory.max` is verified as a larger daemon + grant +
  polling-headroom envelope
- the Linux RSS observer accepts a missing `VmRSS` as terminal evidence only on process
  disappearance or an explicitly terminal `Z`/`X` status, never as enforcer loss for a task that is
  still live, because Linux can discard a task's memory map before procfs exposes a terminal state.
  The fail-closed recheck loop permits four full 50 ms watchdog intervals before rejecting a stable
  live task: three 1 ms rechecks are too short to separate an exit race from a live sample under
  cohort load. Stable live and malformed records still fail closed, and regressions cover vanished,
  terminal, live, and malformed recheck evidence
- public engine launch continues to accept only `ExecutableModel`, which contains the matching
  resource-indexed `Enforcer` and `MemoryGrant`
- coordinator subscriptions derive only from `CompiledPlacement` / `CompiledDaemon`; engine
  subscriptions derive only from `RuntimePlan` / `ExecutableModel`
- the single-flight execution authority is encapsulated with the executable capability so callers
  cannot reuse one executable concurrently under independent locks. `EngineExecutionAuthority` is an
  opaque newtype in the capped-engine kernel, minted only by `refineCompiledRuntimePlan` and
  returned paired with the `RuntimePlan` it serializes, so there is no second mint site.
  `EngineTopicCapability` carries it beside the refined plan behind a private constructor, and
  `publishedResultFromRequest` — the single choke point the websocket and filesystem-spool paths
  share — requires it and wraps execution in `withSerializedEngineExecution`. The retired shape was
  a bare `MVar ()` created in `Runtime/Daemon.hs` and passed through a public signature, so any
  caller could mint a second token and run one `RuntimePlan` concurrently, and the
  filesystem-spool drain reached the same execution call with no lock in scope at all. Serialization
  is what bounds *total* resident memory to one admitted grant at a time, so a second token lets two
  admitted models exceed the budget their admission was decided against. The authority stays one per
  plan rather than one per executable, deliberately: per-model tokens would reintroduce that
  overrun. `fail-cannot-construct-engine-topic-capability` pins the private constructor
- `runLinuxWatchdog`'s no-live-member observation discharges through `failSamplerIfRunning` rather
  than returning and silently ending enforcement for the rest of the execution: it returns quietly
  if the engine really exited and fails closed with a typed `EnforcementUnavailable` if it has not,
  matching what the startup probe already did with the same observation
- child-cgroup delegation is unavailable and is not claimed: the launcher sees the unified cgroup-v2
  hierarchy mounted read-only, and a one-model pod would leave the Haskell daemon inside the same
  OOM-kill domain. The selected construction keeps the daemon outside a fresh child group, sums
  every `/proc` group member conservatively, kills only that group on a grant breach, fails closed
  on sampler loss, and verifies live `memory.max` as a larger outer envelope with daemon and polling
  headroom

### Validation

- unit and integration tests reject ineffective/mismatched enforcers and chart/plan drift
- adversarial Apple and Linux CPU executions exceed the declared ceiling, return typed terminal
  failure, and leave the host, daemon, and subsequent smaller inference alive
- the adversarial Linux CPU ceiling-breach survival regression self-execs a grouped child that
  allocates and touches 64 MiB, applies the production `/proc` process-group watchdog under a 16 MiB
  ceiling, and proves the typed `EngineExceededCeiling 16` result plus a non-successful child reap;
  a smaller child under a 512 MiB ceiling then succeeds, establishing daemon and test-process
  survival after the breach. It runs in the supported `linux-cpu` image with that image's required
  `/usr/bin/tini` entrypoint preserved — a launcher that replaces the entrypoint has a process 1
  that does not reap orphan descendants, and that topology is not closure evidence
- selected `apple-silicon` plus `linux-cpu` full-suite gate passes against one frozen state

### Remaining Work

The exact-source `linux-cpu` half is complete and must not be rerun merely to compensate for absent
Apple hardware. What is open is Apple:

- **The adversarial Apple ceiling-breach survival test.** An execution that exceeds its declared
  ceiling must return a typed terminal failure and leave the host, the daemon, and a subsequent
  smaller inference alive.
- **Apple-hardware validation of the bounded fixed-command public-tool observer.** The humanized
  `top` ledger is discovery evidence, not an exact-byte breach: exact group-member footprint
  evidence must be collected before returning `EngineExceededCeiling`. Normal completion, timeout,
  synchronous exception, asynchronous cancellation, a stopped observer, output overflow, and parser
  corruption must each leave the observer group absent and its direct child reaped. The Apple probe
  is restricted to host-engine placement, and any later sampler failure must terminate the execution
  path rather than silently reading zero.
- **The Apple footprint sampler has no vanished-member tolerance.**
  `Runtime/CappedEngine/FixedObserver.hs` returns `Left` for the whole group when one member's
  `footprint` call fails, and `CappedEngine/Internal.hs` turns that into a terminal
  `EngineEnforcementUnavailable` — so a member exiting between group enumeration and sampling ends
  a healthy execution as enforcer loss. The Linux twin hardens the same race with a skip, a
  terminal-state check, and a bounded retry. Closing this means giving the Apple sampler the same
  discipline: skip a member that has vanished, require disappearance or terminal evidence for it,
  retry under a bound, and keep failing closed for a stable live member it cannot sample. It is a
  probabilistic watchdog defect rather than a deterministic blocker, so it surfaces as an Apple
  cohort failure rather than as a startup refusal.
- **The Apple half of the selected `apple-silicon` plus `linux-cpu` gate**, run against one frozen
  state on [Wave Y](cohort-validation-waves.md).

Every Apple footprint or watchdog result produced by the superseded FFI sampler is historical
evidence only and discharges none of the above. This phase's strict numerical execution begins after
Phase 2 Sprint 2.16 closes.

---

## Sprint 4.33: Inference Memory Scope Correction [Done]

**Status**: Done — documentation and validation-criteria scope only; no runtime behavior change, so
there is no cohort gate.
**Implementation**: `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`,
`DEVELOPMENT_PLAN/cohort-validation-waves.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/architecture/bounded_inference_memory.md`,
`documents/architecture/runtime_modes.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Bring this phase's memory claims and validation criteria into line with what its implementation
actually proves.

Two defects, both in the criteria rather than the code. First, this phase's closure evidence
included statements that a never-out-of-memory guarantee is proven on Apple hardware and that the
catalog completes with zero host out-of-memory kill. Those are true of the inference lane as run and
false as global statements: the enforcement is a fixed-cadence sampler over an admitted engine's
process group, and the incident that motivated this correction came from a process this phase never
governed.

Second, and more important as a gate: **completing without exhausting the host is a sample, not a
bound.** The full-suite runs that produced that evidence were performed with no memory ceiling on the
largest consumer present. A criterion that asserts an absence of failure passes by luck whenever the
sample is unrepresentative, and this one was.

### Deliverables

All landed.

- The never-out-of-memory claims in `cohort-validation-waves.md` and
  `legacy-tracking-for-deletion.md` are annotated as historical for their narrower recorded inference
  scope, following the established convention of annotating prior wave evidence rather than
  rewriting it. The wave ledger carries one scope block covering every "zero host OOM" record; the
  cleanup ledger carries the retirement of the "never-OOM guarantee" wording itself.
- This phase's validation criteria are restated. Six sites changed, and the replacement wording is
  the load-bearing part: a cohort gate now claims that **every over-budget row is cleanly
  typed-rejected and no admitted row was terminated by the host**, which is an assertion about the
  ceiling behaving, rather than that no exhaustion occurred, which is an assertion about the sample.
  The Sprint 4.30 and 4.31 gate lines and the Wave R and Wave W summaries all carry the narrower
  claim.
- The enforcement table row and the `by construction` language are scoped to admission, with runtime
  enforcement described as measurement and termination on a fixed cadence. Both were already correct
  in the governed suite when this sprint ran — the doctrine's OS row already says "sample-and-kill on
  a fixed cadence, not a kernel-imposed allocation ceiling: a breach is detected and terminated, not
  prevented", and `runtime_modes.md` already scopes "by construction" to the admission. This is
  recorded as **already satisfied rather than newly done**, because claiming it as work would be the
  same kind of over-statement the sprint exists to remove.
- The partition still carries no build term, so the sum of declared claims is not checked against
  physical memory. That is deferred and named in the doctrine's `What this does not bound`; this
  sprint does not close it.

### Validation

- `infernix lint docs` passes, and no remaining claim in this phase or its owned documents asserts
  that a host out-of-memory kill is structurally unrepresentable. The one surviving sentence
  containing that phrase is this sprint's own objective, describing what was removed.
- The surviving honest statements are preserved rather than rewritten: Wave R and Wave W still record
  what they observed, with the scope of the observation named.

### Remaining Work

None.

---

## Sprint 4.34: Machine-Local Admission and Fail-Closed Member Identity [Active]

**Status**: Active — the admission move is closed code-side and only the broker-side member claim
remains, named below rather than implied.
**Code-side closure**: the zero-capacity refusal, the at-least-one-admissible-placement check, the
fail-closed member identity, the removal of the Apple engine-lock waiver, and the
placement/admission split are implemented and pass the machine-independent gate set
(`cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`, `infernix-haskell-style`,
`infernix-compile-fail`, `infernix-execution-plan-internal`, `infernix-capped-engine-observer`,
`poetry run check-code`, `infernix lint files|chart|proto|docs`).
**Cohort gate**: apple-silicon, on [Wave Y](cohort-validation-waves.md). The retired coexistence
case and the reinstated Apple engine lock both change Apple behaviour and nothing here runs on Apple
hardware.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/ExecutionPlan.hs`,
`src/Infernix/ExecutionPlan/Internal.hs`, `src/Infernix/ExecutionPlan/Properties.hs`,
`src/Infernix/Runtime/Enforcer.hs`, `src/Infernix/Runtime/Pulsar.hs`,
`src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/DemoConfig/Internal.hs`,
`src/Infernix/DemoConfig/Properties.hs`, `src/Infernix/Runtime/Daemon.hs`,
`src/Infernix/Service.hs`, `test/compile-fail/`, `test/unit/Spec.hs`,
`test/integration/Spec.hs`
**Docs to update**: `documents/architecture/bounded_inference_memory.md`,
`documents/architecture/daemon_topology.md`, `documents/architecture/engine_pool_routing.md`

### Objective

Move memory admission to the machine that will execute, and make a daemon that cannot establish its
identity refuse to start.

Admission is an observation of the admitting process's own machine. Identity is the same class of
defect one layer down: with no explicit member name a daemon took the first entry of the compiled
catalog — a `Map` keyed by member id, so the silent default was the lexicographically smallest id —
and no bootstrap path passes one, so two machines resolving the same identity was the default rather
than an edge case. Each would then assert its own physical RAM as the budget for work the other may
execute, and nothing detects it: the broker sees two ordinary `Shared` consumers with distinct
process-qualified names, and the engine lock is a host-local path that cannot exclude a second
machine.

### Deliverables

**A non-positive inference capacity is rejected at construction.** `mkHostMemoryPartition` tightened
`reservedMib > physical` to `>=`. The retired boundary accepted an exactly-equal split, which is
arithmetically valid and yields a zero-capacity partition — and a zero-capacity partition is not a
smaller budget. Every model declares a *positive* footprint, so it admits nothing: the daemon starts,
reports ready, and answers every request with a memory rejection. `hostPartitionForCapacity` stopped
normalizing a non-positive argument to zero, and the Apple budget resolver stopped substituting a
zero-capacity partition when discovery succeeded and the answer was "this host cannot fund
inference" — it now names the measurement and the remedy. The unit suite pins the exact case that
was accepted before the sprint, and one property fixture that asserted "the private validator
preserves an explicitly enforced zero capacity" is deleted rather than adjusted, because the
behaviour it preserved is the defect.

**A machine that can answer nothing refuses to start.** `NoAdmissiblePlacement` lists every rejected
model. It fires only when models were placed and none survived admission, so the deliberately empty
`--empty-models` image bake is untouched. It is a `RefinementError` rather than a `ConfigError`,
because after the admission split it is the executing machine's refusal: a catalog the coordinator's
box could not fund says nothing about the engine's box.

**Admission is performed by the machine that will execute, and by construction only by it.**
`CompiledPlacement` carries no resources, `CompiledRuntimePlan` carries no admission verdict, and
`RuntimePlan` gained `runtimeUnavailable`. `refineRuntimePlan` admits and then refines, and the way
in is a `RuntimeObservation` whose constructor is package internal and which only
`Infernix.Runtime.Enforcer` can fill from live probes — so a routing-only role cannot reach
admission at all rather than being trusted not to. `memoryAdmissionRejection` reads the refined plan
and moved to the engine request path, so the typed `ModelMemoryLimitExceeded` the browser renders
now originates on the machine that refused the work; `coordinatorAdmissionRejection` keeps only its
own two refusals (no model id, model not in the compiled graph) and forwards everything else.

Two decisions inside are worth stating rather than leaving implicit. The enforcer must choose its
samplers *before* it can admit anything, so the choice and the admission read one value:
`placementEnforcementShape` decides host/pod/GPU from the runtime mode, the declared budget, and
whether the model uses the device, and both the observation and the grant are derived from it — the
probe and the ceiling cannot name different limits. And the missing-observation check now applies to
*admitted* placements only, while the unexpected-observation check still spans every placement: the
enforcer probes before it knows the admission result, so an observation for a rejected placement is
legitimate while a bogus id is still caught.

**Member identity is required with no default.** One compiled engine daemon is a *determination*
rather than a default and is still adopted; two or more without `--engine-name` is a daemon that
cannot say which member it is, and it refuses to start, naming every candidate. The `linux-gpu` lane
already passes `--engine-name` on every per-engine Deployment, and `apple-silicon` / `linux-cpu`
compile exactly one member each, so the refusal is reachable only in the case it exists for.

**The Apple engine-lock waiver is removed, and the coexistence assertion that motivated it is retired
with it.** The waiver existed so one integration case could run two host engine daemons on the same
machine and assert that they share one `Shared` subscription. That case
(`validateAppleHostEngineSharedSubscriptionCoexistence`) and its four exclusively-owned helpers are
deleted. The Apple shared-subscription *backpressure* case survives, because it is about broker
permits rather than about two engines on one box, and `engine_pool_routing.md`'s validation bullet
now states the refusal instead of the coexistence.

### Validation

- `cabal build all --enable-tests` under `-Wall -Werror`, `cabal test infernix-unit`,
  `infernix-haskell-style`, `infernix-compile-fail`, `infernix-execution-plan-internal`, and
  `infernix-capped-engine-observer` all pass.
- A zero-capacity partition is a named refusal, and the exact accepted-today case is pinned: a split
  whose `vmReserve + headroom` meets physical exactly. The refusal message is asserted to say
  "leaves no inference capacity" rather than reporting oversubscription, because those are different
  facts.
- The `NoAdmissiblePlacement` case is pinned against a single-model over-capacity config — the same
  fixture that previously compiled into a zero-placement plan. The unavailable-model accounting is
  re-fixtured onto a two-model config so it still proves that a *fitting* model is admitted while an
  over-capacity sibling is retained with its exact typed reason.
- **The admission split is proven behaviourally, not only structurally.** Two compile-fail fixtures
  pin the construction (`RuntimeObservation`'s constructor and the retired
  `compiledPlacementEnforcedResources` projection are both absent from the public boundary).
  `infernix-execution-plan-internal` pins the refusal (`NoAdmissiblePlacement`) and the mixed case
  (one fundable model becomes an executable while its over-capacity sibling is retained with the
  exact typed error). The launch-boundary properties drive a real engine topic capability over a
  refined plan and assert the engine publishes the typed `ModelMemoryLimitExceeded`. The unit suite
  inverts the retired coordinator fixture: a placed-but-unfundable model is now **forwarded**, byte
  for byte, to its pool topic with no coordinator verdict published.
- **Not proven here:** a second engine process on one host is refused by a host-local file lock, and
  the lock is now armed on every substrate; but no machine-independent gate starts two daemons, so
  the behavioural half belongs to the cohort wave.

### Remaining Work

**The broker-side member claim is not done.** The engine lock is host-local and provably cannot
exclude a second machine claiming the same member identity; the claim needs the Sprint 6.45 shape —
stamp the identity into the protected resource and reread it at every authorization — and the only
resource two machines share is the broker. Its behavioural proof needs a real broker, so it belongs
to the cohort wave, and the registration surface it stamps into is the per-topic schema property
that the system/machine contract split introduces. The forward-only DAG forbids naming a later phase
as a blocker, so this is stated as an ordering requirement rather than as a `Blocked by` edge.

**One premise this sprint corrected rather than inherited.** The objective describes the coordinator
vetoing with its own capacity. In the current single-contract world the budget the coordinator held
was the *engine's* declared budget — `resolveInferenceMemoryBudget` generates the engine pod limit on
`linux-cpu` and the host partition on `apple-silicon` — so it was applying the executing machine's
budget on its behalf, and the defect was latent rather than live. The split landed anyway, ahead of
the machine contract that makes it live, because building the reduced contract on top of a
plan-global admission is what Sprints 8.10 and 8.11 were blocked on.

---

## Sprint 4.35: Native Runner Front-End Correction and Failure Diagnosability [Active]

**Status**: Active — code-side closed for the `linux-cpu` and `linux-gpu` lanes; the
`apple-silicon` half of the same defect is named in `Remaining Work` rather than assumed equivalent.
Opened by a `linux-cpu` cohort failure found while executing Phase 3 Sprint 3.16's gate.
**Code-side closure**: passes the machine-independent gate set (`cabal build all --enable-tests`
under `-Wall -Werror`, `infernix-unit`, `infernix-haskell-style`, `infernix-compile-fail`,
`infernix-execution-plan-internal`, `infernix-capped-engine-observer`,
`infernix-artifact-transaction`, `infernix-apple-materializer`, `poetry run check-code`,
`infernix lint files|chart|proto|docs`, `infernix docs check`).
**Cohort gate**: `linux-cpu` for the corrected front-end; `apple-silicon` — Wave Y — for the Apple
half named below.
**Implementation**: `src/Infernix/Engines/Artifact/Target.hs`,
`src/Infernix/Runtime/CappedEngine/Internal.hs`, `src/Infernix/Runtime/Worker.hs`,
`test/unit/Spec.hs`
**Docs to update**: none. `realness_contract.md` already forbids publishing anything but real model
output; this sprint makes the Linux llama runner match what the doctrine already declared.

### Objective

Stop the llama.cpp runner publishing chat-UI chrome as model output, and make a native-runner
failure say what happened.

### Deliverables

**The Linux llama target is the completion front-end, not the chat front-end.** llama.cpp b9704 split
the former single binary: `llama-cli` is now an interactive chat UI that rejects `--no-conversation`
at runtime — printing `--no-conversation is not supported by llama-cli / please use llama-completion
instead` to **stdout** — and then continues in chat mode anyway. Under the retired target a
*successful* run exited 0 and published roughly 1.1 KiB of chrome as the model's answer: the refusal
line, an ASCII banner, `build : b9704-…`, the `/exit /regen /clear /read /glob` command list, the
echoed prompt, and a `[ Prompt: … t/s | Generation: … t/s ]` footer. That is not the model's output,
and the realness contract forbids publishing it. `llama-completion` ships in the same pinned payload
and needs no manifest change.

**Two flags are retired on the Linux lanes, each for a measured reason.** `--log-disable` silenced the
runner's only failure channel: against b9704 a failed model load produces **0 bytes on both streams**
with it and **893 bytes naming the exact GGUF path** without it. `--no-conversation` is rejected by
`llama-cli` outright and, under `llama-completion`, leaks the chat-template marker into published
output.

**A native-runner failure publishes its exit code and both captured streams.** The retired
`nativeRunnerResult` catch-all discarded the exit code, discarded stdout entirely, and appended only
stderr — so exit 1, a cgroup OOM kill at 137, and a segfault at 139 produced a byte-identical
message. Combined with the `--log-disable` blindness above, a `linux-cpu` cohort failure carried
exactly one bit: that the child exited non-zero. The catch-all now binds `ExitFailure failureCode`
(total under `-Wall -Werror`, since `ExitSuccess` and the Python adapters' `ExitFailure 75`
cache-miss protocol are matched above) and appends a labelled, 4096-character-bounded slice of each
stream. Truncation is marked as truncation; absent output stays absent; nothing is synthesized.

**Model-cache hydration is atomic, and an empty object is refused rather than cached.** The retired
`downloadNativeModelCacheObject` wrote the fetched object straight to its final path and guarded the
whole download behind `doesFileExist destination`. Neither half is safe alone and together they fail
open *permanently*: `ByteString.writeFile` is not atomic, so a download interrupted by a container
restart, an OOM kill, or a timeout leaves a short or empty file at the destination — and the
existence check then treats that wreckage as a populated cache forever, because nothing re-downloads
a path that exists. `.ready` is stamped immediately after, so the cache reports itself populated
while the model file is unusable, and an `emptyDir` survives container restart within a pod, so the
wreckage outlives the crash that produced it.

The object is now staged to a `.incoming` sibling and renamed. Rename is atomic within one
directory, so a destination is either absent or complete — which is what the existence check always
assumed. An interrupted attempt leaves only the sibling, which the next attempt discards. A
zero-byte object is refused at the fetch, naming bucket, key, and destination, and a short write is
refused by comparing the staged size against the fetched length. A present-but-empty destination is
now treated as absent rather than as a cache hit.

**The correction is scoped to the lane it was measured on, deliberately.**
`renderNativeArtifactArguments` is keyed on adapter id rather than on platform, so an unscoped edit
would have silently changed Apple's argv too. Apple runs a *differently built* llama.cpp — installed
by `materialize-metal-engines` under `native/bin`, not the image-pinned b9704 payload — and nobody
has measured it. Changing an argv for a binary nobody has run is precisely how the retired grammar
became wrong, so `llamaLaneSpecificArguments` keeps both flags on `AppleSilicon` and drops them on
both Linux lanes.

### Validation

- The exact Linux argv is pinned, and the two retired flags are pinned **absent** by name, so
  neither returns as a harmless tidy-up.
- The Linux target path assertion pins `llama-completion`.
- `llamaLaneSpecificArguments` is total over `RuntimeMode` under `-Wall -Werror`, so a new lane
  cannot be added without deciding this question for it.
- Measured directly against the pinned payload in the launcher image, not inferred: `llama-cli` with
  the retired argv and a missing model gives `rc=1, stdout=128B, stderr=0B`; the same without
  `--log-disable` gives `stderr=893B`; `llama-completion` with the corrected argv and a missing model
  gives `rc=1, stderr=1243B` and no unsupported-flag complaint.
- **Cohort gate (pending):** the `linux-cpu` per-model matrix completing `llm-tinyllama-gguf` with
  real generated text rather than chat chrome.

### Remaining Work

**The Apple half is unfixed and very likely defective in the same way.** Apple's `llama-cpp-cli`
target is `native/bin/llama-cli`; if `materialize-metal-engines` installed a post-split llama.cpp —
which is likely — that lane publishes the same chat chrome as model output and is subject to the
same realness defect. Confirming it needs Apple hardware to measure the installed binary, so it
belongs to [Wave Y](cohort-validation-waves.md). It is stated as a probable defect rather than a
known one, because nobody has run it.

**The trigger for the cohort failure that opened this sprint is characterized but not confirmed.**
What is established by measurement: the upstream MinIO object is a *valid* GGUF — magic `47 47 55 46`
version 3 at offset 32 of the retained backing file, with the file's 14752-byte excess over the
published object size accounted for exactly by 461 32-byte streaming-bitrot hashes, one per MiB. So
staging and upload are correct and the defect is on the engine-side hydration. What the engine
reported is `failed to read magic` rather than `failed to open`, which means the destination existed
and held fewer than four readable bytes.

The atomic-rename and empty-object refusal above close the fail-open that best fits that evidence,
but they are landed as a correctness fix rather than as a confirmed root-cause fix, because the
`emptyDir` holding the wreckage is gone with its pod and no run has yet reproduced it under the new
diagnostics. A subsequent attempt to reproduce it against a fresh cluster did not reach the engine —
the ad-hoc `internal pulsar-roundtrip` invocation never delivered a request — so the reproduction is
owed. If the next cohort still fails here, it now fails with the bucket, key, destination, and byte
counts in the message.

**Native model-cache hydration refuses a zero-byte object permanently.** `Runtime/Worker.hs` raises
on an empty object, and its presence guard treats a zero-byte file as absent, so a retry re-fetches
and re-refuses rather than ever recovering. Only `image-apple-stable-diffusion-coreml` and
`llm-qwen15-mlx` reach it on a cold cache — both Apple-only, both in the live catalog — so it sits
outside the lanes this sprint measured. The refusal stands as written for now, because rejecting an
observed zero-byte cache entry is fail-closed and the currently selected upstream snapshots carry no
legitimate zero-byte payloads. Closing it requires a typed size/digest manifest that makes an
intentionally empty object distinguishable from an interrupted write, so a supported snapshot
containing one hydrates instead of being refused forever, without reopening the fail-open the
atomic-rename staging replaced.

---

## Sprint 4.36: Restore The Darwin Per-Engine Python Producer [Done]

**Status**: Done — superseded and re-homed. The complete producer/consumer correction is owned and
implemented by [Phase 1 Sprint 1.23](phase-1-repository-and-control-plane-foundation.md), because
strict numerical Phase 1 validation cannot depend on unfinished Phase 4 work. No Phase 4 code or
cohort dependency remains for this item.
**Implementation**: see Phase 1 Sprint 1.23
**Docs to update**: see Phase 1 Sprint 1.23

### Objective

Historical objective: give the per-engine Python environment a producer on Darwin and collapse the
code that produces and consumes its readiness evidence. Phase 1 Sprint 1.23 now owns that objective.

### Deliverables

- The audit found the Darwin producer absent, an orphaned installer export, and three independent
  copies of the interpreter/marker derivation. Eight of the 16 then-live Apple catalog rows dispatched
  to Python stdio and would fail after their separate `bootstrap.json` precondition was satisfied.
- Phase 1 Sprint 1.23 implements one canonical binding-derived plan, one project-lock-aware
  Provisioning producer with post-install project digest and marker readback, and one fail-closed
  runtime observer. Apple startup, `internal materialize-metal-engines`, and `internal
  materialize-substrate` all invoke it before inference; the Linux CPU Docker shell copy and the
  orphaned installer are removed.
- Focused `-Wall -Werror` compilation and the complete unit suite pass. The live Apple plus
  paired `linux-cpu` cohort stays open under Phase 1/Wave Y and is not claimed here.

The same audit found two further open Darwin defects, each carried by the open sprint that owns its
surface: the Apple footprint sampler's missing vanished-member tolerance is stated in Sprint 4.32's
`Remaining Work` alongside the rest of the Apple execution-enforcer work, and the permanent
zero-byte refusal in native model-cache hydration is stated in Sprint 4.35's `Remaining Work`
alongside the rest of the native-runner hydration correction. Neither is an unconditional Phase 1
cohort prerequisite.

### Validation

Validation ownership moved with the implementation to Phase 1 Sprint 1.23 and Wave Y.

### Remaining Work

None.

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
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) - managed state transition doctrine (typed evidence per state, capability-gated primitives) this phase now references for Sprint 4.28

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
