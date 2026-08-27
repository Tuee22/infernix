# Phase 4: Inference Service and Durable Runtime

**Status**: Done — every sprint is implemented and validated. Sprints 4.37 through 4.42 close the
host half of Bounded Engine Launch on the selected `apple-silicon` accelerator plus its paired
`linux-cpu` lane: the Apple full suite passes against all seven materialized native-engine roots,
the paired Linux CPU full-suite evidence remains current, and no Phase 4 cohort residual remains.
**Current implementation state**: Sprints 4.37 through 4.42 landed in numerical order, each building
on the one before: a breach names the resource it breached, the requirement becomes resource-indexed,
the requirement is derived from the artifact's own bytes, three sampling loops become one, a kernel
ceiling is installed before the engine's first allocation on the lane that can install one, and the
admitted quantities plus the execution shape reach the engine on the message it already reads. The
architecture's device half is Phase 6 Sprint 6.51 and is not owned here. Sprints 4.31, 4.32, 4.34,
and 4.35 were the last four before this group, and each closed on that shared cohort. Sprint 4.35 (native runner front-end correction
and failure diagnosability) was opened by a `linux-cpu` cohort failure found while executing Phase 3
Sprint 3.16's gate: post-split llama.cpp made `llama-cli` an interactive chat front-end, so a
*successful* run published chat chrome as the model's answer — a realness-contract violation on the
success path — while a failed one published one bit, because the argv silenced the only channel
carrying the reason. Both lanes now run the completion front-end, each corrected against the binary
that lane actually executes. The scope boundary around member identity is drawn where the resource
is: this phase owns the machine-local, fail-closed identity a daemon establishes about itself, while
excluding a *second machine* that claims the same identity is a fleet-wide property of the broker and
belongs to the fleet topology subject rather than here. Sprint 4.34 is complete against the former and
never depended on the latter. Sprint 4.36 is `Done` by supersession: the per-engine Python producer is
implemented in Phase 1 Sprint 1.23, so strict Phase 1 validation has no forward dependency on this
phase for that prerequisite.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Define the Haskell service runtime, the shared Python engine-adapter contract, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the shared Linux substrate image, the
> substrate-generated `.dhall` role contract, and the Apple host inference bootstrap that together
> make the runtime model honest and durable.

## Phase Status

The selected `apple-silicon` full suite passes against the materialized `llama-cpp-cli`,
`whisper-cpp-cli`, `coreml-native`, `ctranslate2-native`, `mlx-native`, `onnx-runtime-native`, and
`jvm-native` roots. All three derivable LLM rows return real output; artifact families outside the
landed safetensors and GGUF readers fail closed as typed `ModelRequirementUnderivable` outcomes.
The full unit, integration, retained-state recovery, and 16-test routed browser surfaces pass, and
the paired `linux-cpu` full-suite evidence is current against the same Phase 4 implementation.

> **Closure receipt (2026-08-17).** The four open surfaces were worked in numerical order and each
> validated before the next: Sprint 4.31's claimable-pool/toolchain-occupant model, Sprint 4.32's Apple
> observer and adversarial breach proof, Sprint 4.34's Apple cohort, and Sprint 4.35's Apple
> runner/front-end half. Their phase-specific acceptance criteria were reconciled against evidence
> produced for this phase rather than inherited: the earlier receipts predate three of the
> corrections below and are not read as discharging them. Two defects the cohort itself surfaced are
> part of the closure — a native runner could reach its engine with an unhydrated model cache because
> its cache miss was invisible to the retry classifier, and the integration suite's routed probes were
> single-shot behind a retry helper that classified on a string it never receives. The broker-side
> member claim is a fleet-wide broker property rather than a machine-local one, so it is not a
> Phase 4 residual.

Phase 4 closes around the staged-substrate runtime contract, the shared Python adapter boundary, the
Pulsar-driven request and result contract, the explicit engine-runner dispatch, the mounted
`/opt/infernix/cluster.dhall` cluster-wiring contract, and the substrate-neutral engine-pool routing
contract. Sprints 4.1–4.20 established those typed contracts — typed dispatch, catalog, pool
routing, cache, and object storage — and they stand; later sprints replaced engine internals and the
memory model without undoing them. The worker resolves the selected engine entrypoint for every
supported matrix row and publishes the typed per-family result surface: inline text for the LLM and
speech families, and a typed `infernix-demo-objects` object reference for the source-separation,
audio-to-MIDI, music-transcription, image, video, audio-generation, and OMR artifact families.

**Realness by construction.** An audit established that an earlier "real per-family output"
closure was, for several catalog rows, satisfied by silent fabrication rather than real model
execution: the Apple native engine layer was a validation wrapper, and on Linux the
source-separation, audio-to-MIDI (ONNX run on `np.zeros`), and OMR rows returned constant
artifacts while whisper.cpp and CTranslate2 masked runtime failures. Sprints 4.21–4.23 replaced
those internals so the engine code is structurally incapable of returning a fabricated result:
every missing-weights, load, or engine failure raises and becomes `status=failed`. Real Linux
engines, fixed weight provisioning, ONNX adoption where it is the mature free choice, and modern
PyTorch rebinds for the music-transcription rows landed with it, and a realness lint owned with
[phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md) enforces the
guarantee mechanically. The architectural contracts from Sprints 4.1–4.20 were not undone; only
the faked engine internals were replaced. The removed fabrication surfaces are tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

**Music transcription.** The obsolete MT3 residual is replaced by `music-mt3-infer` and
`music-mr-mt3`. Both bind through `mt3-infer` on the PyTorch adapter, stage weights through the
model-cache contract, disable upstream auto-downloads, and are generated for `linux-cpu`,
`linux-gpu`, and `apple-silicon`; Apple uses the PyTorch CPU path and no MPS claim is made.

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
`CompiledPlacement` / `CompiledDaemon`. The device-lane RAM/VRAM construction and the generated wire
schema are separate subjects with their own homes, and this phase's closure does not wait on either.
Canonical doctrine:
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
sentinel. Both closed on the selected accelerator plus `linux-cpu`. Canonical doctrine:
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
Cabal dependency compilation, image export, registry push, and Helm/Pulsar readiness waits rather than
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
  contract; it is replaced by the durable-context Chat surface

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
- Apple cohort validation closed on the selected accelerator plus `linux-cpu`; CUDA Linux validation closed on the selected accelerator plus `linux-cpu` with full
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
- Phase 4 closing prose for Sprint 4.13 keeps its cohort references without dated
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
- re-validated through the `linux-gpu` plus `linux-cpu` attestation

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

### Remaining Work

None.

---

## Sprint 4.17: Per-Engine Engine Images and Batch Routing [Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `src/Infernix/Models.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Runtime/Pulsar.hs`, `chart/templates/deployment-engine.yaml`, `chart/values.yaml`, `bootstrap/linux-gpu.sh`
**Docs to update**: `DEVELOPMENT_PLAN/system-components.md`, `documents/architecture/daemon_topology.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Sprint 4.16 bakes every engine's CUDA framework venv into one image, which on linux-gpu produces a
~121 GB monolith — fine for `docker run --gpus all` but impractical to push through the in-cluster registry
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
  registry-first flow (`src/Infernix/Cluster.hs` `clusterWorkloadImageRef` becomes a per-engine set).
- **Linux native-engine materialization lane** (folds in former Task 9):
`src/Infernix/Engines/LinuxNative.hs` owns the allowlisted Linux native adapter ids and `infernix
internal materialize-linux-native-engines` writes typed manifests plus smoke-validated entrypoints
into image-owned `/opt/infernix/engines/<id>/bin/` roots for the native-process-runner rows
(speech, gguf-LLM, audio-to-MIDI, CTranslate2 transcription, OMR); the worker checks the repo data
root first and then this Linux image root. The Apple equivalent is the Sprint 1.14 headless
Metal/Core ML materialization lane.
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
- update `src/Infernix/Models.hs` and generated catalog docs to match the researched matrix:
  Apple CTranslate2 is viable CPU, vLLM CPU is not a portable `linux-cpu` default, MT3-PyTorch and
  MR-MT3 use `mt3-infer`, Omnizart uses the maintained ByteDance PyTorch piano row, Wan Apple MPS
  remains residual, and Basic Pitch TensorFlow stays residual behind ONNX/Core ML fallback lanes
- keep CUDA framework stacks image-owned or pre-materialized; they are never installed on a user
  request path
- Apple real-native-payload ownership sits with

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

**Status**: Done — MT3 catalog replacement proven on the selected accelerator plus `linux-cpu`.
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

**Status**: Done — implemented and validated.
**Implementation**: `src/Infernix/Engines/LinuxNative.hs`,
`python/native-runners/apple_native_runner.py`, `src/Infernix/Models.hs`, `README.md` **Docs to
update**: `README.md` (matrix Notes), `documents/architecture/model_catalog.md`

**Docs to update**: `README.md` (matrix Notes), `documents/architecture/model_catalog.md`

### Objective

Make every matrix cell accurate for the substrate its README column advertises, and close two
substrate-divergence defects the matrix review surfaced.

### Deliverables

- Row 11 (basic-pitch ONNX) CUDA lane: **relabeled** the README cell `ONNX Runtime (CPU)` and the
  matching `Models.hs` ModeBinding (`requiresGpu = False`), because `LinuxNative.hs` runs
  `CPUExecutionProvider` and only the CPU `onnxruntime` wheel is installed. The supported cell is
  therefore the CPU ONNX Runtime path, proven on the selected accelerator plus `linux-cpu`.
- Rows 4/6 (llama.cpp GGUF, whisper.cpp speech) CUDA lane: **documented** that the CUDA column runs the
- Row 14 (`piano_transcription`): corrected the stale `Models.hs` "test is red until the adapter binding
- Row 17 (Wan2.1-T2V) Apple: kept as the documented Apple residual
  (`residualMatrixRowIdsForMode AppleSilicon`), with the union-coverage invariant satisfied by the real
  CUDA cell and stated in the README Note.
- Substrate-divergence guards: **added** the divide-by-zero guard to the Linux basic-pitch onset path
  that the Apple runner already has; the Apple smoke now fails closed when the engine runtime does not
  import.

### Validation

- Code-side: `cabal build all`, `infernix lint docs`, and the Python `check-code` AST/realness gate
  all pass.
- Cohort: Apple routed Playwright passes on the selected accelerator plus `linux-cpu`, and the rebuilt
  `linux-cpu` and `linux-gpu` full suites pass on the selected accelerator plus `linux-cpu`.

### Remaining Work

None.

---

## Sprint 4.26: Apple-Silicon Inference RAM Admission and Bounded Peak (Fail-Clean, Never OOM) [Done]

**Status**: Done — implemented and validated.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs`,
`src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs`, `src/Infernix/HostConfig.hs`,
`src/Infernix/HostTools.hs`, `src/Infernix/ProjectInit.hs`, `src/Infernix/Cluster.hs`,
`src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Web/Contracts.hs`, `docker/Dockerfile` **Docs to
update**: `documents/architecture/realness_contract.md`,
`documents/architecture/daemon_topology.md`, `documents/architecture/runtime_modes.md`,
`documents/engineering/object_storage.md`, `documents/operations/apple_silicon_runbook.md`,
`README.md`

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
  a full per-model `test integration` completed every
  admitted row and no admitted row was terminated by the host. Per Sprint 4.33 that is evidence the
  admission and ceiling behaved, not that host exhaustion is unrepresentable.
- Linux CPU: closed on the selected accelerator plus `linux-cpu` through the full
  `./bootstrap/linux-cpu.sh test` suite, where host-RAM admission is a no-op by design because the
  engines run in Kubernetes-bounded pods.

### Remaining Work

None.

---

## Sprint 4.27: Typed Resource Memory Admission and Inference Errors [Done]

**Status**: Done — implemented and validated.
Phase 1 Sprint 1.19 supersedes that runtime path with indexed compile/refine/executable
capabilities, and Linux GPU plan compilation consumes Phase 6 Sprint 6.44's verified dual RAM/VRAM
enforcement.
**Implementation**: `src/Infernix/Types.hs`,
`src/Infernix/DemoConfig.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`,
`src/Infernix/Storage.hs`, `proto/infernix/runtime/inference.proto`,
`src/Infernix/Bridge/Result.hs`, `src/Infernix/Cluster.hs`, and the substrate budget-resolution
helpers used by generated config and runtime admission.
**Docs to update**: `README.md`,
`documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`,
`documents/architecture/daemon_topology.md`, `documents/architecture/engine_pool_routing.md`,
`documents/architecture/realness_contract.md`, `documents/engineering/testing.md`,
`documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`,
`documents/operations/apple_silicon_runbook.md`, and this plan.

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

**Status**: Done — implemented and validated.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/Engines/AppleSilicon.hs`, `python/native-runners/apple_native_runner.py` **Blocked
by**: Sprint 1.16, 3.14
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
and the phase's existing engineering/reference docs

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

**Status**: Done — implemented and validated.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`
**Blocked by**: Sprint 1.17, 4.28 **Docs to
update**: `documents/architecture/managed_state_transitions.md`,
`documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, and the
phase's existing engineering/reference docs

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

### Remaining Work

None.

---

## Sprint 4.30: Memory-Grant Admission and Capped-Engine Kernel [Done]

**Status**: Done — implemented and validated.
**Current-API note**: the signatures and implementation account below are the historical Sprint
4.30 surface. Phase 1 Sprint 1.19 removed `admitModelMemory` and the public bare-grant launch
shape; current compilation mints an indexed grant, live refinement produces `ExecutableModel`, and
only the package-internal capped-engine region receives its derived command and watchdogs.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Runtime/Pulsar.hs`,
`src/Infernix/Engines/AppleSilicon.hs`, `python/native-runners/apple_native_runner.py` **Blocked
by**: Sprint 4.27, 4.28
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

Gates (closed on the selected accelerator plus `linux-cpu`):

- `cabal build all` (`-Wall -Werror`) compiles the grant-gated kernel with the raw engine-spawn path
  removed
- `cabal test infernix-unit` covers grant mint on in-budget admission, `Left ModelMemoryLimitExceeded`
  on over-budget admission, and ceiling-breach classification for both the macOS watchdog and the Linux
  OOM-exit paths
- `cabal test infernix-haskell-style` passes, including the Phase 6 Sprint 6.42
  `unboundedEngineSpawnViolations` lint that keeps new engine-spawn call sites off the raw primitives
- `infernix test all` on apple-silicon plus linux-cpu drives a full over-capacity catalog with every
Per Sprint 4.33 this is evidence that admission and the ceiling behaved, not that a host
out-of-memory condition is unrepresentable

### Remaining Work

None.

---

## Sprint 4.31: Host Memory Partition, Required Footprint, and Budget-Enforcer Split [Done]

**Status**: Done — implemented and validated.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Substrate.hs`,
`src/Infernix/Models.hs`, `src/Infernix/Web/Contracts.hs`
**Blocked by**: Sprint 4.30 **Docs to
update**: `documents/architecture/bounded_inference_memory.md`,
`documents/architecture/model_catalog.md`, `documents/operations/apple_silicon_runbook.md`, and
this plan

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
- **One claimable pool, two alternative occupants.** `HostClaimablePool` is an opaque quantity minted
  once from physical RAM less the memory reserved away from it — the active Colima pledge on Darwin,
  whatever the cgroup maximum withholds on Linux. `mkHostMemoryPartition` derives the inference
  capacity from that pool, and `buildMemoryBudgetForPool` derives the toolchain account from the same
  value, so neither is computed from a figure blind to the other. The retired shape was two
  independent derivations that agreed only numerically: the partition divided physical RAM less the
  virtual-machine pledge, while `buildMemoryBudgetForPhysicalMib` took whatever effective figure its
  caller held, and nothing checked that the two described one quantity.
- **A concurrent claim over both occupants is not a constructible term.**
  `hostPartitionToolchainAccountMib` is the partition's term for the other occupant, and
  `ConcurrentHostPoolClaim` — hidden constructor, minted only by `mkConcurrentHostPoolClaim` — is the
  only way to assert the pool funds both at once. On the supported development host it refuses and
  names the overcommitment: a 16384 MiB pool that the partition spends entirely (6144 MiB headroom
  plus 10240 MiB capacity) has no residue for the 8192 MiB account, so the claim overcommits by
  8192 MiB. The occupants are alternatives admitted one at a time against a held host claim, and that
  is now a compile-time distinction rather than a comment.
- the resolved inference capacity on the supported development host is unchanged at 10240 MiB and the
  toolchain account unchanged at 8192 MiB, so the recorded admit and typed-refusal outcomes for the
  catalog do not move

### Validation

Gates (closed on the selected accelerator plus `linux-cpu`):

- `cabal build all` (`-Wall -Werror`) compiles with the required footprint newtype and the
  enforcer-named budget across every mirror
- `cabal test infernix-unit` covers a `HostMemoryPartition` accepting a fitting split and rejecting an
  oversubscribing one, and a `ModelDescriptor` decode that fails closed when the footprint is absent
- `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, `infernix docs check`,
  and the web unit suite pass with the regenerated contracts
- `infernix test all` on apple-silicon plus linux-cpu proves the checked partition admits the fitting
- the claimable-pool correction is pinned by unit assertions: the pool refuses an unmeasured host, a
  negative reserve, and a reserve that leaves nothing; it reports 16384 MiB and an 8192 MiB account
  for the supported development-host figures; the partition carries both beside an unchanged
  10240 MiB capacity; and the concurrent claim is refused with the overcommitment named
- the claimable-pool correction's selected `apple-silicon` plus `linux-cpu` sign-off is recorded in
Both lanes proved the resolved inference capacity unchanged at 10240 MiB: every fitting catalog
row completed, and both 12288 MiB image rows were typed `ModelMemoryLimitExceeded` refusals naming
`host-memory-partition-inference-capacity`

### Remaining Work

None.

---

## Remaining Work

None. Every sprint in this phase is `Done` and their per-lane attestations are recorded in
[cohort-validation-waves.md](cohort-validation-waves.md). The last four — Sprint 4.31's
claimable-pool/toolchain-occupant correction, Sprint 4.32's verified Apple and Linux CPU execution
enforcers, Sprint 4.34's Apple cohort, and Sprint 4.35's native runner front-end correction — closed
together on one frozen source state validated on `apple-silicon` plus `linux-cpu`. The broker-side
member claim is a fleet-wide broker property rather than a machine-local one, and is not a residual
here.

---

## Sprint 4.32: Verified Apple And Linux CPU Execution Enforcers [Done]

**Status**: Done — both lanes' enforcers are verified and the selected `apple-silicon` plus
`linux-cpu` cohort is recorded on the selected accelerator plus `linux-cpu`.
**Implementation**: `src/Infernix/Runtime/CappedEngine.hs`,
`src/Infernix/Runtime/CappedEngine/Internal.hs`,
`src/Infernix/Runtime/CappedEngine/FixedObserver.hs`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/Runtime/Pulsar.hs`, `test/unit/Spec.hs`
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
- the Apple footprint sampler carries the same vanished-member discipline as its Linux twin. A
  member can exit between the `top` snapshot that enumerates the group and the `footprint` call that
  measures it, so a failed member is rechecked through another *complete* snapshot:
  `sampleCompleteProcessGroupSnapshotWith` discards every partial byte count and restarts from the
  refreshed membership when the member has gone, preserves the footprint failure when it is still
  live, preserves it for terminal settlement when the refreshed group is empty, and fails closed
  naming both diagnostics when the recheck itself fails. The restart is bounded by the single
  `ObserverDeadline` every observation and measurement in one sample shares, so repeated turnover
  cannot extend the sample rather than being bounded by a separate retry count. Four deterministic
  regressions in `FixedObserver.hs` pin exactly those four outcomes
- the Linux RSS observer accepts a missing `VmRSS` as terminal evidence only on process
  disappearance or an explicitly terminal `Z`/`X` status, never as enforcer loss for a task that is
  still live, because Linux can discard a task's memory map before procfs exposes a terminal state.
  The fail-closed recheck loop permits four full watchdog intervals — the 50 ms figure is the pause
  between samples, not the achieved cadence — before rejecting a stable
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
- `runLinuxWatchdog` and the NVIDIA watchdog treat a no-live-member observation as a bounded
  settlement window rather than silently ending enforcement or racing the engine action's
  `ProcessHandle` reaper. Four fresh observations at the normal 50 ms interval bound the window;
  group reappearance resumes the complete sampling loop. Persistent absence is accepted only when
  the leader is terminal or absent in procfs. A stable live leader, malformed evidence, or an
  observation error terminates the group and records typed `EnforcementUnavailable`. Terminal
  tasks (`Z`, `X`, and `x`) are excluded from RSS/VRAM totals, so a zombie is never mistaken for a
  live enforceable member
- child-cgroup delegation is unavailable and is not claimed: the launcher sees the unified cgroup-v2
  hierarchy mounted read-only, and a one-model pod would leave the Haskell daemon inside the same
  OOM-kill domain. The selected construction keeps the daemon outside a fresh child group, sums
  every `/proc` group member conservatively, kills only that group on a grant breach, fails closed
  on sampler loss, and verifies live `memory.max` as a larger outer envelope with daemon and polling
  headroom

### Validation

- unit and integration tests reject ineffective/mismatched enforcers and chart/plan drift -
adversarial Apple and Linux CPU executions exceed the declared ceiling, return typed terminal
failure, and leave the host, daemon, and subsequent smaller inference alive - the adversarial
Linux CPU ceiling-breach survival regression forks a grouped child that allocates and touches 64
MiB, applies the production `/proc` process-group watchdog under a 16 MiB ceiling, and proves the
typed `EngineExceededCeiling 16` result plus a bounded non-successful POSIX reap; a smaller child
under a 512 MiB ceiling then succeeds, establishing daemon and test-process survival after the
breach. The fixture owns its child directly and does not introduce a second `ProcessHandle`
waiter. It runs in the supported `linux-cpu` image with that image's required `/usr/bin/tini`
entrypoint preserved - the adversarial **Apple** ceiling-breach survival regression is its twin
and needs no special hardware, because the fixed public-tool observer is available on every
supported Apple host. It re-execs this image as a grouped child that dirties 512 MiB, drives the
production `runAppleWatchdog` through `appleWatchdogOutcomeForTest`, and proves the typed
`EngineExceededCeiling 256` result plus a non-successful reap. Two further cases keep it from
being vacuous and prove survival: a child that allocates nothing must *not* breach the same
ceiling — which is what establishes that the breach is attributable to the allocation rather than
to the runtime carrying it — and a second such child succeeds after the breach. The Apple seam
takes the `ProcessHandle` its production loop consumes rather than dropping it as the Linux and
NVIDIA seams do, so the loop under test is the loop that runs; the breach path signals the group
without reaping, leaving the fixture the single waiter - deterministic settlement regressions
cover group reappearance, terminal/absent leader evidence, persistent absence with a live leader,
group observation failure, and leader observation failure - selected `apple-silicon` plus
`linux-cpu` full-suite sign-off passes against one frozen state, recorded on the selected
accelerator plus `linux-cpu`. The Apple lane completed every fundable catalog row through the host
engine daemon under live footprint enforcement and typed-refused both over-capacity rows; the
paired `linux-cpu` lane exercised the process-group RSS watchdog including its live adversarial
  breach.

### Remaining Work

None.

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
- The surviving honest statements are preserved rather than rewritten: the cohorts still record
  what they observed, with the scope of the observation named.

### Remaining Work

None.

---

## Sprint 4.34: Machine-Local Admission and Fail-Closed Member Identity [Done]

**Status**: Done — the admission move is closed code-side and signed off on this sprint's own
`apple-silicon` cohort, recorded on the selected accelerator plus `linux-cpu`. The broker-side member claim
this sprint once carried is a fleet-wide property rather than a machine-local one: excluding a second
machine needs an operator-declared machine identity and more than one engine machine to exclude,
neither of which is a fact about the machine this sprint bounds.
**Cohort**: apple-silicon, closed on the selected accelerator plus `linux-cpu`. The retired coexistence
case and the reinstated Apple engine lock both change Apple behaviour, so neither could be proven by
the machine-independent gates; the Apple lane's full suite exercised the single compiled host member
under the armed engine lock and completed every fundable row.
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

**The broker-side member claim is a fleet-wide property, not a residual of this sprint.** The engine lock
is host-local and provably cannot exclude a second machine claiming the same member identity; the
claim needs the Sprint 6.45 shape — stamp the identity into the protected resource and reread it at
every authorization — and the only resource two machines share is the broker. Two things it needs do
not exist in this phase and cannot be built here: an operator-declared machine identity to stamp,
which first exists in Sprint 8.11's machine contract, and more than one engine machine to exclude,
which needs a fleet validation topology. Leaving it open here would have made this phase wait on a
later one in substance while the forward-only DAG forbids declaring such an edge at all — a residual
no work in this phase could ever discharge. The owning sprint adopts it outright, in the same shape
Sprint 4.36 was re-homed into Phase 1 Sprint 1.23. This phase hands the work forward and waits on
nothing, so it is not a residual of this sprint.

**One premise this sprint corrected rather than inherited.** The objective describes the coordinator
vetoing with its own capacity. In the current single-contract world the budget the coordinator held
was the *engine's* declared budget — `resolveInferenceMemoryBudget` generates the engine pod limit on
`linux-cpu` and the host partition on `apple-silicon` — so it was applying the executing machine's
budget on its behalf, and the defect was latent rather than live. The split landed anyway, ahead of
the machine contract that makes it live, because building the reduced contract on top of a
plan-global admission is what Sprints 8.10 and 8.11 were blocked on.

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

None.

---

## Sprint 4.35: Native Runner Front-End Correction and Failure Diagnosability [Done]

**Status**: Done — code-side closed on every lane and signed off on the `linux-cpu` plus
`apple-silicon` cohort recorded on the selected accelerator plus `linux-cpu`. The `apple-silicon`
half was never assumed equivalent: the installed Apple binary was measured, reproduced the same
failure, and is corrected the same way. Opened by a `linux-cpu` cohort failure found while
executing Phase 3 Sprint 3.16's gate.
**Implementation**: `src/Infernix/Engines/Artifact/Target.hs`, `src/Infernix/Runtime/CappedEngine/Internal.hs`,
`src/Infernix/Runtime/Worker.hs`, `src/Infernix/HostTools.hs`, `src/Infernix/HostConfig.hs`,
`src/Infernix/HostPrereqs.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster/Subprocess.hs`,
`src/Infernix/Engines/Provisioning.hs`, `src/Infernix/Engines/Provisioning/Internal.hs`,
`test/unit/Spec.hs`, `test/artifact-transaction/Spec.hs`
**Docs to update**: `documents/engineering/host_tools_manifest.md`,
`documents/engineering/apple_silicon_metal_headless_builds.md` — the host manifest is the
authoritative inventory of every command the project invokes, so switching the Apple front-end
renames the declared tool. `realness_contract.md` needs no change; it already forbids publishing
anything but real model output, and this sprint makes both llama runners match what the doctrine
already declared.

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

**Each lane is corrected against the binary that lane actually runs.**
`renderNativeArtifactArguments` is keyed on adapter id rather than on platform, so an unscoped edit
would have changed Apple's argv on the strength of a Linux measurement. Apple runs a *differently
built* llama.cpp — the Homebrew `llama.cpp` formula that `materialize-metal-engines` seals under
`native/bin`, not the image-pinned b9704 payload — so the Apple half waited for its own measurement
rather than assuming equivalence. That measurement was then taken, against Homebrew build **9870**,
which is post-split and ships `llama-completion` in the same formula. It reproduced the Linux defect
exactly: `llama-cli` under the retired argv exits 1 having written 128 bytes to **stdout** — the
`--no-conversation is not supported by llama-cli / please use llama-completion instead` refusal — and
**0 bytes** to stderr; dropping `--log-disable` restores 905 bytes naming the missing GGUF; and
`llama-completion` under the corrected argv exits 1 with 1019 bytes of diagnostics and no
unsupported-flag complaint. Both front-ends emit the identical `version: 9870 (2d973636e)` banner on
stderr, so the installed-runner smoke's parser accepts the new target unchanged.
`llamaLaneSpecificArguments` therefore drops both flags on every lane and stays total over
`RuntimeMode`.

**A native runner never reaches its engine with an unhydrated cache.** A native runner is the only
reporter of its own cache miss: unlike the Python adapters it has no exit-75 protocol, so an absent
payload reaches `llama-completion` or `whisper-cli` as an ordinary open failure, which classifies as
`worker_failed` and is therefore never retried. The retired `ensureNativeRunnerContractCacheReady`
made that reachable — when the upstream `.ready` sentinel was absent it hydrated nothing, wrote no
marker, raised nothing, and returned, and the engine was then invoked against a payload that does not
exist. It now proves hydration and returns the classified `model_cache_not_populated` miss the
bootstrap-and-retry path already recognizes, so an eager-staging miss publishes a bootstrap request,
waits for the durable sentinel, and hydrates on retry. A zero-byte entry counts as absent, and a
snapshot-backed model requires its index plus every file the index lists, so a half-hydrated
generation is caught rather than run. The coordinator's eager-sweep failure message no longer claims
a fallback that could not fire.

**A routed validation probe waits as long as it claims to.**
`readProcessWithTransientCurlRetry` retried nothing: it ran `curl` through `readProcess`, which
inherits the child's standard error, and then searched the raised `IOError` for curl's own
diagnostics — strings that value never contains, because it reads
`readCreateProcess: curl … (exit 7): failed` while curl's message goes to the suite's stderr. The
predicate was constantly false, every routed probe in the integration suite was single-shot behind a
20-attempt name, and a cold-start race on any published route failed the whole lane. It now
classifies on curl's exit code — 7, 28, 52, and 56 are "not listening yet"; 22 is a real answer and is
never retried, which the absent-route assertions depend on — and reports curl's captured stderr
instead of discarding it.

**Two things this sprint deliberately does not change, recorded rather than left implied.** Native
model-cache hydration still refuses a zero-byte object permanently: `Runtime/Worker.hs` raises on an
empty object and its presence guard treats a zero-byte file as absent, so a retry re-fetches and
re-refuses rather than ever recovering. Rejecting an observed zero-byte cache entry is fail-closed and
no currently selected upstream snapshot carries a legitimate zero-byte payload; changing it requires a
typed size/digest manifest that makes an intentionally empty object distinguishable from an
interrupted write, without reopening the fail-open the atomic-rename staging replaced. And the
`--single-turn` / `--simple-io` / `--no-display-prompt` argv the completion front-end now receives is
unchanged from the retired grammar, because those three flags were never implicated in either
measurement.

**The Apple manifest names the command it invokes.** Switching the front-end is not only an argv
change: the host manifest is the authoritative inventory of every external command the project ever
runs, and Section V of the plan standards requires the field to name the command exactly. The
declared tool is now `llama-completion` (`toolPaths.llamaCompletion`, defaulting to
`/opt/homebrew/bin/llama-completion`), the Apple prerequisite reconciles the same `llama.cpp`
formula that provides it, provisioning seals it to `native/bin/llama-completion`, and both the
runtime target and the installed smoke resolve that path. An operator carrying a manifest written
before this change re-runs `infernix init`.

### Validation

- The exact Linux argv is pinned, and the two retired flags are pinned **absent** by name, so
  neither returns as a harmless tidy-up.
- Both target-path assertions pin `llama-completion`: the Linux image payload and the Apple
  `native/bin` installed target.
- `llamaLaneSpecificArguments` is total over `RuntimeMode` under `-Wall -Werror`, so a new lane
  cannot be added without deciding this question for it, and a unit assertion pins every
  constructor empty so the decision itself is the thing under test rather than one lane's rendering
  of it.
- Measured directly against the pinned payload in the launcher image, not inferred: `llama-cli` with
  the retired argv and a missing model gives `rc=1, stdout=128B, stderr=0B`; the same without
  `--log-disable` gives `stderr=893B`; `llama-completion` with the corrected argv and a missing model
  gives `rc=1, stderr=1243B` and no unsupported-flag complaint.
- Measured directly against the installed Apple binary, not inferred from the Linux payload:
  Homebrew `llama.cpp` 9870, `llama-cli` with the retired argv and a missing model gives
  `rc=1, stdout=128B, stderr=0B`; the same without `--log-disable` gives `stderr=905B`;
  `llama-completion` with the corrected argv gives `rc=1, stderr=1019B` and no unsupported-flag
  complaint; and both front-ends emit the identical `--version` banner the installed smoke parses.
- The hydration precondition is pinned by unit assertions covering an absent payload (the classified
  miss, naming the model and the file), a zero-byte payload (absent, not a cache hit), a populated
  payload, and a package-backed tool that requires none.
- **Cohort (closed):** both per-model matrices completed their llama.cpp rows with real generated text
  rather than chat chrome, recorded on the selected accelerator plus `linux-cpu`.

- The reproduction this sprint owed is discharged. The Apple lane's first attempt on the corrected
front-end failed exactly where the characterization predicted, with
`whisper_init_from_file_with_params_no_state: failed to open` against a
`speech-whisper-small/payload` the coordinator's eager sweep had skipped for a transient upstream
reason — the fail-open the hydration precondition closes. The same lane then completed every
fundable row once the precondition drove bootstrap-and-retry, and the `linux-cpu` lane surfaced
the single-shot routed probe the curl-exit-code correction closes.

### Remaining Work

None.

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

The same audit found two further open Darwin defects, each carried by the open sprint that owns its
surface: the Apple footprint sampler's missing vanished-member tolerance is stated in Sprint 4.32's
`Remaining Work` alongside the rest of the Apple execution-enforcer work, and the permanent
zero-byte refusal in native model-cache hydration is stated in Sprint 4.35's `Remaining Work`
alongside the rest of the native-runner hydration correction. Neither is an unconditional Phase 1
cohort prerequisite.

### Validation


### Remaining Work

None.

---

## Sprint 4.37: A Breach Names The Resource It Breached [Done]

**Status**: Done. This sprint is deliberately first and deliberately small. It
is the instrument every later measurement in this architecture is read off, so it lands before the
accelerator cohort rather than inside it: a run whose only failure signal was reconstructed from the
wrong resource cannot diagnose itself, and a requirement derived from an artifact has to be
calibrated against exactly the observation this sprint stops erasing.
**Code-side closure**: complete. The machine-independent gate set passes — `cabal build all
--enable-tests` under `-Wall -Werror`, `infernix-unit`, `infernix-haskell-style`,
`infernix-compile-fail`, `infernix-execution-plan-internal`, `infernix-capped-engine-observer`,
`infernix-artifact-transaction`, `infernix-apple-materializer`, `poetry run check-code`, and
`infernix lint files|chart|proto|docs|plan` plus `infernix docs check`, every scan at zero.
**Cohort validation**: the selected `apple-silicon` accelerator plus its paired `linux-cpu` lane
pass against the Phase 4 state. The unit fixtures drive the production watchdog loops directly, and
the routed live-engine matrix preserves typed resource attribution through the published terminal
result.
**Blocked by**: nothing.
**Implementation**: `src/Infernix/Runtime/CappedEngine/Internal.hs`,
`src/Infernix/Engines/Artifact/Capability.hs`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/Runtime.hs`, `src/Infernix/ExecutionPlan.hs`, `test/unit/Spec.hs`
**Docs to update**: none.
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
already declares the target — a breach names the resource it breached and the footprint it observed,
because a refusal that cannot say which resource it is about cannot be acted on. This sprint makes
the code match a contract the governed suite already states; it does not edit the suite to record
that something now works.

### Objective

Report the resource that actually breached and the footprint actually observed, so a ceiling breach
is a diagnosis rather than a bare signal that something exceeded something.

### Deliverables

The breach path erases the resource three times over, and each erasure alone is enough to publish a
wrong answer.

**The sampler knows the resource and throws it away.** `watchdogForGrant` reads a resource-indexed
`EnforcedGrant` and returns `AppleFootprintWatchdog`, `LinuxProcessGroupRssWatchdog`, or
`NvidiaVramWatchdog`, so the resource is decided at mint time from a nominal role that cannot be
relabelled and is known statically at every breach site. `CeilingBreached` then carried integers
only, so the one fact the loop is certain about was the first thing discarded. It now carries an
`InferenceMemoryResource` beside the ceiling and the observed footprint. Nothing is newly derived —
the value is carried from where it was already decided — and the observation is reported in the unit
the ceiling is declared in, rounded up, so a report never understates what was measured and a breach
never reads as equal to the ceiling it exceeded.

**Two watchdogs write one reference, and the value cannot say which wrote it.** `withCappedEngine`
allocates a single `engineTermination :: IORef (Maybe EnforcementTermination)` and forks every
watchdog against it; a `RuntimeGpuResources` placement forks two, the pod resident-set loop and the
NVIDIA VRAM loop. The single slot is correct and stays: `recordFirstTermination` is an
`atomicModifyIORef'` first-writer-wins, so the recorded value is the breach that actually terminated
the group. A second slot per resource was rejected for exactly that reason — it would let the
reporter publish a breach that did not cause the termination, which is a fabrication in the same
family as the one this sprint removes. What changes is that the written value is tagged, so one
shared slot is attributable rather than ambiguous.

**The triple survives every boundary it crosses.** `EngineOutcome`'s `EngineExceededCeiling` and
`ArtifactProcessOutcome`'s `ArtifactProcessExceededCeiling` carry the same resource, ceiling, and
observation, because a value that is complete at the sampler and lossy one frame up is not carried,
it is re-guessed. `ArtifactProcessOutcome` is deliberately first-order — it cannot contain a closure,
an `IO` action, or a validated artifact capability — and `InferenceMemoryResource` is a closed enum
in `Infernix.Types`, so widening that outcome costs none of what keeping it closed buys.

**The typed error stops being reconstructed from the executable.**
`Infernix.Runtime.ceilingBreachError` built `ModelMemoryLimitExceeded` out of the `ExecutableModel`
and nothing else: `inferenceErrorResource` was `executableModelResidentResource`, which answers
`PodRam` for every `RuntimeGpuResources` placement by construction, and `inferenceErrorRequiredMib`
and `inferenceErrorAvailableMib` were both `executableModelResidentCeilingMib`, which reads the pod
grant. A device breach was therefore published as a pod-RAM breach carrying the pod ceiling, with
required and available equal — a limit-exceeded error asserting that the requirement *is* the limit,
which is the one proposition a breach establishes is false. The payload is now built from the
measurement: the resource is the resource that breached, `availableMib` is the ceiling installed for
that resource, and `requiredMib` is the observed footprint, a lower bound on what the model actually
needed. Required strictly exceeds available on every breach, which is the shape this error should
always have had.

**The layer above stops discarding the worker's report.** `runExecutableInference` matched
`errorCode workerError == modelMemoryLimitExceededErrorCode` and then dropped `workerError` whole,
rebuilding the payload from the executable, so everything the worker measured — including the
observation `modelCeilingBreachError` renders into its message — ended at that match. It now consumes
the typed breach the worker carries. Re-parsing the rendered message was rejected twice over: the
doctrine's retry-containment obligation is that a measured breach maps directly to a typed terminal
failure and never through a string classification, and this repository has already paid for a
predicate that searched a rendered string for text that value never contains — the routed-probe retry
helper Sprint 4.35 corrected, which was constantly false and left a twenty-attempt retry single-shot.
`modelCeilingBreachError` names the resource in its operator-log message as well, so the log line and
the typed payload cannot disagree.

**What this sprint does not claim.** The NVIDIA loop's tag is pinned by unit assertions and by the
type that carries it, not by a live device breach. That is a scope boundary rather than a residual: a
live device-memory breach is a fact about a device lane, this phase's selected accelerator is
`apple-silicon`, and this sprint's closure neither produces nor consumes device evidence.

### Validation

- **Every live breach fixture asserts the reported observation is strictly above the ceiling it
  breached**, on the Apple footprint loop and the Linux process-group RSS loop. That is stronger than
  the assertion it replaces, and the difference is precisely the defect being fixed: comparing the
  reported ceiling against the expected ceiling is satisfied by an implementation that reports its
  own ceiling back, which is what the retired path did, so in the failing case the old assertion was
  vacuous — it passed on the one output that carried no information. `breachOutcomeExceeds` pins the
  ceiling, the strict inequality, and the resource together.
- **The reported resource is pinned against the loop that terminated the group** — `unified-host-ram`
  for the Apple footprint watchdog, `pod-ram` for the Linux process-group RSS watchdog, and
  `gpu-vram` for the NVIDIA watchdog. This is the only assertion that distinguishes the two writers
  of one shared termination reference, so it is the one that fails on the retired shape rather than
  passing on it.
- **The non-breaching control keeps the breach attributable**: a grouped child that allocates nothing
  must *not* breach the same ceiling, which is what establishes that the breach is attributable to
  the allocation rather than to the runtime carrying it. Carried forward from Sprint 4.32 and
  extended to the resource assertion, because a control that cannot fail proves nothing.
- **The published payload is built from the measurement, not from the executable**: a
  `RuntimeGpuResources` executable driven through a VRAM breach publishes `gpu-vram` and the VRAM
  ceiling. Under the retired reconstruction the same fixture would publish `pod-ram` and the pod
  ceiling — the measured failing case this sprint exists to remove, and the reason a cohort run could
  not be read from its own output.
- **`requiredMib` strictly exceeds `availableMib` on every runtime breach payload**, so the
  self-contradicting equal pair cannot return unnoticed under a later edit.
- **Nothing re-derives what the worker already reported**: an assertion pins that the resource and
  observation in the published result equal the ones the worker returned, so a future caller cannot
  recompute either from the `ExecutableModel` and get a plausible wrong answer instead of a loud one.
- machine-independent gates at zero, as recorded in the header.
- selected `apple-silicon` plus `linux-cpu` full suites pass against the Phase 4 state.

### Remaining Work

None.

---

## Sprint 4.38: The Memory Requirement Is Resource-Indexed [Done]

**Status**: Done. The promoted resource kind and the indexed requirement form the type-layer half
of the bounded-engine-launch architecture and pass on the selected `apple-silicon` plus `linux-cpu`
cohort.
**Code-side closure**: complete. `cabal build all --enable-tests` under `-Wall -Werror`,
`infernix-unit`, `infernix-compile-fail`, `infernix-execution-plan-internal`,
`infernix-haskell-style`, `poetry run check-code`, `infernix lint files|chart|proto|docs|plan`, and
`infernix docs check`.
**Cohort validation**: the host half of bounded engine launch passes on this phase's selected
`apple-silicon` accelerator plus `linux-cpu`.
**Blocked by**: Sprint 4.37.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/ExecutionPlan.hs`,
`src/Infernix/ExecutionPlan/Internal.hs`, `src/Infernix/Runtime.hs`,
`src/Infernix/Substrate/Internal.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Runtime/Pulsar.hs`,
`src/Infernix/Web/Contracts.hs`, `test/compile-fail/Main.hs`, `test/unit/Spec.hs`
**Docs to update**: none.
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
and [../documents/architecture/model_catalog.md](../documents/architecture/model_catalog.md) already
declare that the requirement is resource-indexed with a hidden constructor and that host and device
residency are separate terms with different formulas. This sprint makes the code match a target the
governed suite already states.

### Objective

Make a memory requirement say which physical resource it is a requirement for, in its type, and
reduce the two enumerations that name the same three resources to one promoted kind.

### Deliverables

**One resource kind, with the value-level mirror deleted.** The repository names its three physical
resources twice. `Infernix.ExecutionPlan.Internal` promotes `Resource = HostRam | PodRam |
NvidiaVram` and indexes `MemoryCeiling`, `MemoryGrant`, `EnforcerPlan`, `Enforcer`, and
`EnforcedGrant` by it with `type role … nominal`. `Infernix.Types` separately carries
`InferenceMemoryResource = UnifiedHostRam | PodRam | GpuVram` as an ordinary value, with the wire
codec — `inferenceMemoryBudgetResourceText`, `parseInferenceMemoryResource`, and the `ToJSON` /
`FromJSON` pair — hanging off it. The value-level enumeration is deleted and its codec is merged
onto the promoted kind, which is the only remaining name for a resource. Two enumerations for one
concept are two chances to disagree, and the disagreement is silent because both compile.

**The four hand-written bridges disappear with it.** Today the two enumerations are joined by
functions that must agree with one another by inspection: `witnessInferenceResource` maps a
`ResourceWitness` to a value, `placementShapeEnforcedResources` maps an enforcement shape to a list
of values, `inferenceMemoryBudgetResource` projects a budget to a value, and
`executableModelResidentResource` maps live resources to a value. Nothing checks that the four
agree, because there is nothing for a checker to compare them against — each is total over its own
input. `executableModelResidentResource` is the one that matters: its `RuntimeGpuResources _ _ ->
Types.PodRam` arm is where a device placement acquires a host name, and it is the value Sprint
4.37's error constructor reads when it fills in the resource for a breach. Sprint 4.37 corrects the
breach site; this sprint deletes the shape that made the wrong answer writable in the first place.

**The requirement becomes resource-indexed.** `ModelMemoryFootprint` — one `Int` behind a smart
constructor rejecting non-positive values — is replaced by `ModelMemoryRequirement (resource ::
Resource)`, hidden constructor, nominal role, minted only by the derivation. A host quantity handed
to a device admission stops being a term rather than a review obligation. Be precise about what this
changes: the pipeline downstream of the requirement was **already** indexed, and the compile-fail
fixtures `CannotCoerceMemoryCeilingResource.hs`, `CannotCoerceMemoryGrantResource.hs`,
`CannotCoerceEnforcerResource.hs`, and `CannotCoerceEnforcerPlanResource.hs` already pin that a
grant, ceiling, enforcer, or plan cannot be relabelled from one resource to another. The requirement
was the one un-indexed quantity feeding both admission arms — `admitGrant` compares the same
`modelMemoryFootprintMib` against a host capacity and against a device capacity, and the result is a
correctly indexed grant either way. The type system was enforcing non-substitutability at the far
end of a pipe whose input was a single scalar.

**A device-using placement carrying no device requirement stops being constructible.** The
descriptor carries `requiresGpu :: Bool` beside its single footprint, so "this model uses the
device" and "this model has stated what it needs from the device" are two independent fields that
can disagree. They become one fact: the descriptor carries a closed indexed requirement whose arms
are host-only and host-plus-device, so the Bool is derived from the requirement's own shape rather
than written beside it. `admitPlacementResources` then reads the device arm from a value that is
present by construction instead of consulting a flag and hoping a number was authored to match.

**The shared kind moves down, not the requirement up.** `Infernix.Types` imports nothing from this
project — it is the dependency leaf, and `Infernix.ExecutionPlan.Internal` imports it. A kind that
indexes the requirement therefore has to sit at or below the module holding the requirement, so
`Resource` moves into the leaf and the plan compiler keeps importing it from there. The alternative
— lifting the requirement up to where the kind already lives — inverts the graph: the descriptor,
the Dhall decoder and renderer in `src/Infernix/Substrate.hs`, the hand-written JSON codec, and the
purescript-bridge mirror would all have to move above the plan compiler, and the result is a
configuration decoder that depends on an execution planner.

**Constructor names are preserved.** `HostRam`, `PodRam`, and `NvidiaVram` keep the spellings the
promoted kind already gives them, and `UnifiedHostRam` / `GpuVram` are the names that disappear.
This is not a coin flip: `test/compile-fail/Main.hs` pins its expected diagnostics by substring —
the `MemoryGrant` relabel fixture is accepted only when GHC's message contains `HostRam`, `PodRam`,
and `coerce`, and the VRAM enforcer fixtures on `NvidiaVram` — so renaming a constructor makes every
one of those fixtures pass or fail on whether the new name happens to appear in an unrelated part of
the error text. `PodRam` is already spelled identically in both enumerations, which is exactly why
the pair reads as consistent at a glance while the other two do not.

**The wire spelling does not move.** The merged codec keeps `unified-host-ram`, `pod-ram`, and
`gpu-vram` as the rendered and parsed text, so the `resource` field on the result-topic protobuf,
the persisted result in `Infernix.Storage`, the `parseInferenceMemoryResource` call site in
`Infernix.Runtime.Pulsar`, and the generated `web/src/Generated/Contracts.purs` mirror are
unchanged. The rename is a Haskell-side rename; a wire rename would be a separate contract change
with its own regeneration, and bundling one into the other is how a type cleanup becomes a
compatibility break.

### Validation

- `cabal build all --enable-tests` under `-Wall -Werror` compiles with `InferenceMemoryResource` and
  all four bridge functions absent. Their deletion is checkable rather than asserted: a bridge that
  survived would have no type to return.
- `infernix-compile-fail` gains a fixture rejecting a host requirement supplied where a device
  requirement is demanded, and a fixture rejecting a `coerce` between the two indexed requirements,
  each with the matching positive control that the correctly indexed pairing compiles. A negative
  fixture that would fail for an unrelated reason proves nothing, which is why the controls are part
  of the deliverable rather than an extra.
- `infernix-compile-fail` still passes with its existing four resource-coercion fixtures unmodified,
  which is the concrete evidence that the constructor names were preserved rather than merely
  intended to be.
- `infernix-unit` covers the merged codec round-tripping every constructor, rejecting an unknown
  resource string, and rendering the three unchanged wire spellings; and covers a descriptor decode
  that fails closed when a device-using row carries no device requirement.
- `infernix-execution-plan-internal` covers that admission mints a grant whose index equals the
  requirement's index for every arm, so the compiler cannot admit one resource's quantity against
  another's capacity.
- `infernix lint files|chart|proto|docs|plan` and `infernix docs check` stay at zero.
- **Cohort:** the full per-model matrix passes on `apple-silicon` plus `linux-cpu`; indexed
  requirements admit derivable rows and typed refusals retain their resource and source.

### Landed Decision

One of the four named bridges survives, and it is recorded here rather than left to be rediscovered.
`inferenceMemoryBudgetResource` is not a bridge between two enumerations — after the merge it is a
budget's projection to its own resource, and its only hand-written arm states that a host-enforced
budget bounds host RAM, which is that arm's definition rather than a correspondence that could
disagree with anything. Deleting the name would inline the same statement at two call sites. The
three that were genuinely bridges are gone: `witnessInferenceResource` and
`executableModelResidentResource` are replaced by the single `KnownResource` demotion, whose method
takes the already-indexed value so the index and the reported value cannot disagree, and
`placementShapeEnforcedResources` folded into its one caller.

### Remaining Work

None.

---

## Sprint 4.39: Requirements Derived From Artifact Bytes [Done]

**Status**: Done. The derivation replaces the authored constant table and passes on the selected
`apple-silicon` plus `linux-cpu` cohort.
**Code-side closure**: complete. `cabal build all --enable-tests` under `-Wall -Werror`,
`infernix-unit`,
`infernix-compile-fail`, `infernix-execution-plan-internal`, `infernix-haskell-style`, `poetry run
check-code`, `infernix lint files|chart|proto|docs|plan`, and `infernix docs check`.
**Cohort validation**: the selected `apple-silicon` plus `linux-cpu` cohort derives requirements
from the exact staged artifacts, while underivable or malformed formats yield typed refusals rather
than small requirements.
**Blocked by**: Sprint 4.38.
**Implementation**: `src/Infernix/Models/Artifact.hs` (new), `src/Infernix/Models/Requirement.hs`
(new), `src/Infernix/Models.hs`, `src/Infernix/ExecutionPlan.hs`, `src/Infernix/ExecutionPlan/Internal.hs`,
`src/Infernix/Substrate/Internal.hs`, `src/Infernix/Runtime/Enforcer.hs`,
`src/Infernix/Objects/Upload.hs`, `src/Infernix/Types.hs`, `src/Infernix/Storage.hs`,
`proto/infernix/runtime/inference.proto`, `src/Proto/`, `proto/haskell-bindings.sha256`,
`test/unit/Spec.hs`
**Docs to update**: none.
[../documents/architecture/model_catalog.md](../documents/architecture/model_catalog.md) already
declares that no catalog entry carries a hand-written memory number and that the derivation fails
closed on an artifact that misdescribes itself; this sprint makes the catalog match it.

### Objective

Compute a model's memory requirement from the model's own bytes, and delete the per-family constant
table rather than keeping it as a fallback.

### Deliverables

**The weight term is read from a bounded prefix of the artifact.** `Infernix.Models.Artifact` reads
a checkpoint's header without loading the checkpoint: for a safetensors artifact, eight
little-endian bytes of header length followed by exactly that many bytes of tensor table; for a GGUF
artifact, the magic, version, tensor count, and metadata count followed by the tensor-info block.
The weight term is then the sum over the table of each tensor's element count times its element
width. Nothing about this is an estimate — the table states, per tensor, the dtype, the shape, and
the byte range, and those are the bytes the loader will map.

**The measured numbers, on the catalog's own smallest real checkpoint.** Against
`llm-smollm2-safetensors` (SmolLM2-135M-Instruct), the prefix read is 29.8 KiB — 0.0113% of the file
— and yields 272 tensor entries summing to exactly 256.6 MiB of weights. The largest single tensor
is 54.0 MiB, the tied embedding matrix; that is the staging bound a streamed load has to hold at
once, and it is a different quantity from the total, which is why the derivation reports both. At
the row's 2048-token context the closed cache function gives exactly 45.0 MiB from the declared
geometry — thirty layers, three key/value heads, sixty-four-wide heads, two bytes per element, keys
and values counted separately. The derived requirement is therefore roughly 302 MiB. The constant it
replaces, `conservativeRamFootprintMibForRow`'s `"llm" … otherwise -> 4096`, is 4096 MiB: over by a
factor of about thirteen and a half. An over-declaration is not harmless: admission compares the
declared number against the executing machine's observed capacity, so an inflated constant is
exactly what decides that a machine cannot run a model it can obviously run. The same table's
`"image" -> 12288` branch is why both image rows are typed `ModelMemoryLimitExceeded` refusals
against the 10240 MiB inference capacity Sprint 4.31 resolved on the supported development host, and
neither of those numbers was ever compared against the artifact it describes.

**The cache term is a closed function, not a fudge factor.** Key/value cache bytes are `2 × layers ×
keyValueHeads × headWidth × contextLength × elementWidth`, evaluated from the model's declared
geometry and the execution shape the engine will actually run under. It is closed in both senses:
total over its inputs, and taking no input that is not already a term in the plan. Nothing
multiplies the result by a safety margin, because a margin is an authored number wearing a derived
number's clothes.

**Six fail-closed invariants, each of which yields no requirement rather than a small one.**

- the header parses within a self-imposed byte budget, so a header length the file *claims* cannot
  be turned into an unbounded read of a file this process was never going to load
- the header length plus the payload extent equals the file size, so an artifact that overruns or
  undershoots its own container is refused
- every tensor's byte extent equals the product of its declared shape and its element width
- the tensor offsets tile densely from zero with no gap and no overlap, so a table that describes a
  smaller file than it occupies — or the same bytes twice — is refused rather than summed
- the declared geometry agrees with the header: the layer count, head counts, and hidden width the
  cache term is computed from are cross-checked against the tensor names and shapes the header
  actually contains
- the prefix the derivation read hashes to the digest recorded beside the requirement, so a
  requirement is a statement about one exact header rather than about whatever currently sits at a
  path. This digest covers the bytes actually read and explicitly not the payload: digesting the
  whole artifact to avoid reading the whole artifact is circular, and saying so is cheaper than
  letting a reader assume otherwise.

**The constant table is deleted, not demoted.** `conservativeRamFootprintMibForRow` and
`conservativeModelMemoryFootprint` in `src/Infernix/Models.hs` are removed, along with the `error`
guard that existed only because the table's branches were unchecked positive literals. Keeping the
table as a fallback would be worse than keeping it as the primary: a fallback constant is consulted
exactly when the derivation failed, which is the one moment the artifact is known not to describe
itself, and a code path reached only on failure is a code path nothing validates. It is the same
objection that makes a machine's capacity an observation rather than a declaration, applied to the
other side of the comparison.

**An artifact with no introspectable header fails closed.** Two readers land here — safetensors,
including the index-backed multi-file snapshot form, and GGUF — because those two cover every
catalog row whose engine loads a tensor checkpoint directly. A row whose payload is not a checkpoint
the readers understand yields no requirement, and the compiler retains it as an explicit
`UnavailableModel` naming the artifact family whose reader is absent. That narrows the admissible
catalog until the remaining readers land, and the narrowing is the deliverable rather than a
regression: a row that cannot state what it needs is not a row that can be safely admitted, and an
explicit unavailable placement is visible and actionable where a constant is neither.

### Validation

- `infernix-unit` builds artifacts in the test rather than checking in binary fixtures, then mutates
  one property at a time: a header length exceeding the file, a tensor extent disagreeing with its
  shape, an offset overlapping its neighbour, a gap between offsets, a geometry disagreeing with the
  tensor names, and a prefix digest mismatch. Each mutation is refused with the invariant named, and
  each carries the positive control that the unmutated artifact derives cleanly.
- `infernix-unit` pins the closed cache function against the declared geometry above: exactly 45.0
  MiB at a 2048-token context, and exact linearity in context length, so a future shape change moves
  the number by arithmetic rather than by coincidence.
- `infernix-unit` pins that the prefix read never requests more bytes than the declared budget,
  including on an artifact whose header length field is adversarially large.
- `cabal build all --enable-tests` under `-Wall -Werror` compiles with the constant table absent,
  and `infernix lint files` keeps a replacement literal from reappearing under another name.
- `infernix-execution-plan-internal` covers a row with no derivable requirement compiling to an
  `UnavailableModel` rather than to a placement, and covers that the whole catalog is never failed
  by one such row.
- **Cohort:** on `apple-silicon` plus `linux-cpu`, derivation runs against the artifacts the
  coordinator actually staged; every derivable row completes or fails under its typed enforcement
  result, and every unsupported family remains explicitly underivable.

### Landed Decisions

Three decisions inside this sprint are recorded rather than left implicit, because each widened its
own stated implementation list and each would otherwise be rediscovered by whoever hits it next.

**A refusal that cannot say why is not a refusal.** An underivable requirement is a distinct terminal
outcome from a limit being exceeded, and publishing it as a `ModelMemoryLimitExceeded` carrying zeros
would be a fabrication in the same family as the one Sprint 4.37 removed. `InferenceError` therefore
gains a second arm, `ModelRequirementUnderivable`, carrying the model, the artifact family whose
reader is absent, and the derivation's own reason — and no quantity at all, because the quantity is
exactly what could not be established. The arm crosses the result-topic protobuf, so the tracked
Haskell bindings and their inventory were regenerated and re-pinned with it on the container lane.

**The derivation reads a bounded prefix of the /staged object/ when the local cache is cold.** A
worker hydrates its local model cache per request, so at daemon start that cache is empty; deriving
only from local files would have made every model underivable at startup and refused the daemon
outright. The coordinator has already staged the object, and a tensor table lives in an artifact's
first few kilobytes, so a ranged read fetches exactly those and reports the object's own total size
alongside them. The extent invariant still compares the header against the artifact's size rather
than against the prefix that was fetched, so a truncated fetch is refused rather than treated as a
smaller artifact.

**Which staged object it reads is selected, not assumed** — corrected after a live cluster lane
showed the cost of assuming. A model is staged one of two ways: a single upstream file becomes one
`payload` object, and a multi-file repository is mirrored under the upstream repository's own file
names. The retired form asked for `\<modelId>/payload` and stopped, so every snapshot-layout model
reported having no staged object at all — a refusal that named the wrong proposition, because the
object was there under a name the reader never asked for, and it took every safetensors row out of
the admissible set this sprint counts. The cold-cache read now enumerates the model's staged objects
through a bounded listing — a page cap and a page-count cap, so an unexpected prefix is truncated
rather than followed — and selects the checkpoint among them. The selection is fail-closed in both
directions a guess could be wrong: a prefix holding no checkpoint the two readers understand yields
the family-absent refusal, and a prefix holding *more than one* checkpoint is a sharded snapshot,
which is refused by name rather than under-derived from one shard's tensor table.

**One codec, not two.** The result-payload error codec existed twice — once in `Infernix.Storage` and
once in `Infernix.Runtime.Pulsar` — and the second copy was already one arm behind. The duplicate is
deleted and the shared codec imported, which is the same objection that collapsed the two resource
enumerations in Sprint 4.38.

### Scope Boundaries

- Readers for the artifact families outside safetensors and GGUF are absent, so those rows compile
  to explicit unavailable placements. Each family's reader is a separate, independently validatable
  addition, and no row is admitted on a constant in the meantime. On the current catalog that is one
  GGUF row and roughly six safetensors rows admissible across the three lanes, against eleven rows
  whose payload is a PyTorch archive, an ONNX graph, a CTranslate2 blob, a Core ML package, or a
  pre-GGUF GGML file. The narrowing is the deliverable rather than a regression, and it is large.
- **A sharded snapshot is refused rather than under-derived**, so a repository mirrored as several
  checkpoint files is outside the admissible set until the readers sum a tensor table across shards.
  That is the same fail-closed direction as an absent reader and is stated here because it is a
  narrowing this sprint chose rather than one it inherited.

### Remaining Work

None.

---

## Sprint 4.40: One Resource-Parameterised Sampling Kernel [Done]

**Status**: Done. The detection layer is one loop instead of three, and its host behavior passes on
the selected `apple-silicon` plus `linux-cpu` cohort.
**Code-side closure**: complete. `cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`,
`infernix-capped-engine-observer`, `infernix-compile-fail`, `infernix-haskell-style`, `poetry run
check-code`, `infernix lint files|chart|proto|docs|plan`, and `infernix docs check`.
**Cohort validation**: the Apple process-group footprint lane and Linux anonymous-residency lane
drive the same loop and pass their full suites.
**Blocked by**: Sprint 4.38.
**Implementation**: `src/Infernix/Runtime/CappedEngine/Internal.hs`,
`src/Infernix/Runtime/CappedEngine/FixedObserver.hs`, `test/unit/Spec.hs`
**Docs to update**: none.
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
already declares one resource-parameterised sampling kernel rather than one loop per platform, and
declares the Linux lane's observation to be anonymous residency; this sprint makes the code match.

### Objective

Replace three near-identical watchdog loops with one loop parameterised by the resource it samples,
and correct the two things about the Linux sampler that the duplication was hiding.

### Deliverables

**Three loops become one, and the three names become adapters.** `runAppleWatchdog`,
`runLinuxWatchdog`, and `runNvidiaWatchdog` in
`src/Infernix/Runtime/CappedEngine/Internal.hs` were the same program written three times: sample,
compare against a ceiling, terminate the group on a breach, settle an exit window on an absent
group, fail closed on unreadable evidence. They differ only in which quantity the sample reports.
The three names survive — each is now a thin function supplying its lane's sampler and target to the
one shared loop, and each still carries the conditional-compilation arm that makes the other
platform's absence a named refusal. What is deleted is the algorithm's duplication, not the entry
points; stating it as a symbol-level deletion would claim more than happened.
That module carries sixteen conditional-compilation regions, so each copy is invisible to the gate
set on the other platform, and three copies of one algorithm behind three `#if` walls is how the
copies drift apart without any gate noticing. One loop takes the sampler as a parameter and keeps
every decision once.

**The index is already in scope at the site that discards it.** `watchdogForGrant` matches an
`EnforcedGrant resource` — the resource is right there in the type — and then returns a
`WatchdogSpec` whose three flat constructors re-encode by hand what the index already said, at which
point the loop has to be selected by matching on the re-encoding. The specification becomes indexed
by the same `Resource` kind, so the sampler is chosen by the index rather than by a parallel
enumeration, and a breach carries the resource it breached because it never stopped carrying it.

**The host sampler moves to the field the kernel limit charges.** The Linux loop reads `VmRSS` from
`/proc/<member>/status`. `VmRSS` counts file-backed and shared resident pages, and the data-segment
ceiling this lane installs charges neither. Kernel and sampler were therefore bounding two different
quantities and agreeing only because the difference was usually small; the mapped weight file is
exactly the case where it is not small, and streaming a model from a mapped artifact is exactly what
this lane does. The sampler reads `RssAnon` instead, which is the anonymous residency the ceiling
charges, so prevention and detection agree by construction rather than by coincidence. A `status`
block carrying `VmRSS` but no `RssAnon` is an enforcement failure, not a reason to fall back to the
old field.

**Summing a residency field across a process group double-counts shared pages.** Every member
reports a shared page in full, so the group total is an upper bound whose error grows with member
count, and a two-process engine consequently appeared to hold far more than it did — the loop's own
arithmetic manufacturing an overshoot the machine never saw. Moving to the anonymous field removes
the largest shared component. What it does not remove is copy-on-write pages a member shares with
its own forked child, so the residual double-count is stated as what it is: the group total is a
declared upper bound, not a measurement, and the doctrine's per-process ceiling plus checked member
count is the claim rather than a kernel aggregate.

**A checked member count, so the tree arithmetic is a refusal rather than an unstated premise.** The
placement declares how many processes its engine may run, the loop counts live members on every
complete sample, and a group holding more members than the placement declared terminates as an
enforcement failure naming both numbers. Summing per-process residency into a tree total is sound
only against a bounded member count; today that bound exists in nobody's head and in no value, which
means the arithmetic has a premise it never states. Stating it converts a silent assumption into a
fail-closed check.

**The loop body becomes platform-independent, and therefore testable.** With the sampler supplied as
a parameter, the loop's decisions — breach above the ceiling, continue at or below it, settle the
exit window across four fresh observations at the sampling interval, resume on a member reappearing,
complete on a terminal or absent leader, and fail closed on a stable live leader or unreadable
evidence — are exercised against a scripted sequence of samples on either platform. None of that was
reachable from a unit suite while it lived inside conditional compilation, which is the mechanical
reason the three copies were allowed to differ. The platform-specific parts shrink to producing one
sample: the fixed public-tool observers in `FixedObserver` for the Apple and device lanes, and the
`/proc` walk for the Linux lane. Neither gains a caller-supplied command specification and neither
uses direct foreign imports.

### Validation

- `infernix-capped-engine-observer` drives the shared loop over scripted sample sequences covering
  every decision above, with no platform branch in the test, so both lanes' gate sets run the same
  assertions.
- `infernix-unit` covers the `RssAnon` parse against a real-shaped `status` block, covers that a
  block offering only `VmRSS` fails closed, and covers the member-count refusal naming the declared
  and observed counts.
- `infernix-unit` pins that a breach observation is strictly greater than the ceiling it breached,
  so the loop cannot report the ceiling back as the observation.
- `cabal build all --enable-tests` under `-Wall -Werror` compiles with the three per-platform loop
  bodies replaced by one, and the conditional-compilation region count in that module drops rather
  than merely moving.
- `infernix-haskell-style` and `infernix lint files|chart|proto|docs|plan` stay at zero.
- **Cohort:** on `apple-silicon` the loop samples
  process-group physical footprint through the fixed public-tool observer, on `linux-cpu` it samples
  anonymous residency through `/proc`, and both reach the same terminal classifications for the same
  situations.

### Landed Decision

The declared member count is **derived from the engine binding**, not written on the wire. A native
runner is one process image; a Python stdio adapter is the interpreter plus the bounded set of
workers a framework starts under it. Putting the number on the descriptor would have added a
memory-shaping wire field that Sprint 4.42's execution-shape message deliberately does not carry, and
the binding already states the fact. A group that grows past the bound is an enforcement failure
naming both numbers, not a larger sum quietly accepted.

### Scope Boundaries

- The device-memory arm of the shared loop is compiled and unit-exercised here but samples no device
  on this phase's accelerator; its live behavior is proved under a different wave against a
  different accelerator.

### Remaining Work

None.

---

## Sprint 4.41: The Installed Ceiling [Done]

**Status**: Done. The installation mechanism, read-back, lint, calibration-gated lane strength, and
production readiness consumer pass on the selected `apple-silicon` plus `linux-cpu` cohort.
**Code-side closure**: complete. The lane declaration consumes a closed calibration source,
uncalibrated Linux host lanes declare detection-only, a prevention-required contract refuses that
strength, and runtime refinement performs the readiness check before executable capability minting.
The governed exact-image build, lint, compile-fail, observer, execution-plan, artifact,
materializer, Haskell unit, and web unit gates pass.
**Cohort validation**: Apple declares detection-only by construction and passes its full suite; the
paired calibrated `linux-cpu` lane declares prevention and its full-suite evidence remains current.
**Blocked by**: Sprint 4.38, Sprint 4.40.
**Implementation**: `src/Infernix/Runtime/CappedEngine/Ceiling.hs` (new),
`src/Infernix/Runtime/CappedEngine/Internal.hs`, `src/Infernix/Lint/HaskellStyle.hs`,
`test/compile-fail/Main.hs`, `test/unit/Spec.hs`
**Docs to update**: none.
[../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md)
already registers `/usr/bin/prlimit` as a pinned enforcement literal outside the operator manifest,
and
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
already declares the launch prefix, the read-back, and the per-lane strength table. This sprint
makes the code match both.

### Objective

Install a kernel ceiling before an engine's first allocation on the lane that can install one, prove
it from inside the process it binds, and make `apple-silicon` resolve detection-only by construction
rather than by omission.

### Deliverables

**The launch prefix is a closed constructor.** `Infernix.Runtime.CappedEngine.Ceiling` exposes an
opaque installation value and no way to build a command. On the Linux lanes it renders
`/usr/bin/prlimit --data=<soft>:<hard> -- <engine executable> <argv>`, where the two quantities are
rendered from a `MemoryCeiling 'PodRam` and the executable and argument vector come from the
already-closed `DirectEngineCommand` the worker derived from the executable model. There is no
exported function taking an executable, an argument vector, an environment, or a working directory,
so the surface a caller could misuse does not exist rather than being guarded.

**The installation region is what the spawn accepts.** `withCappedEngine` stops accepting an engine
command and accepts only a value produced by the installation region, so an engine that never passed
through the region is not a term. This is the same move the repository already makes for grants: the
authority to start something is a value someone had to mint, not a convention someone had to follow.

**Ordered operations, before the first allocation.** The descriptor-space bound is established
first, because every spawn kernel sets `close_fds` and the pre-`exec` descriptor walk is linear in
the soft descriptor limit; then the ceiling is rendered from the quantity the plan installs for
that resource; then `prlimit`
lowers both the soft and the hard data-segment limit; then it replaces itself with the engine image.
The limit is in force before the engine's first instruction and cannot be raised back by the process
it binds. Because `prlimit` replaces itself rather than forking, it leaves no live process: the
engine keeps its own process identity, its own group, and its own exit status, so the sampling
kernel's group walk and the worker's exit classification are unchanged.

**The proof comes from inside the process that will allocate.** After image replacement and before
any weight loads, the engine reads its own data-segment soft and hard values back and reports both,
and the worker compares them against the quantity the plan installed. A limit that was set and a
limit the running image fits under are different claims, and only the second is evidence that this
execution is bounded. Nothing else in the pipeline can produce it, because nothing else is the
process the limit binds.

**Why not a child control group.** Measured inside the engine pod, three independent refusals, any
one of which is sufficient: the cgroup hierarchy is mounted read-only, so nothing can be created in
it; the capability that would permit the mount to be rewritten is absent from the container's
effective set; and the container's own scope already holds processes with an empty subtree-control
file, so under cgroup v2's no-internal-process rule that scope could not delegate to a child even if
the first two obstacles were removed. A ceiling that requires the pod to be started differently is
not a ceiling this code can install.

**Why not an address-space limit.** A live device process holds 1038.4 GiB of address space, 12.8
GiB of it merely reserved and never touched, so any address-space ceiling small enough to be
meaningful refuses the runtime before it reaches the model. An address-space limit also charges
file-backed mappings at their full mapped size, which would defeat streaming weights from a mapped
artifact — the one loading strategy that keeps host residency below model size. A data-segment limit
charges neither: measured, a 512 MiB mapped file charges 4.7 MiB against it.

**Why not an in-process limit set by the daemon.** Lowering only the soft limit produces a ceiling
the bound process can raise back to its hard limit whenever it likes, which is advice rather than
enforcement. Lowering the hard limit is one-way and inherited, so a long-lived daemon that lowered
its own would bind every later inference, every observer child, and itself, permanently, from the
first model that needed the smallest ceiling. Both properties push the operation into a process
image dedicated to a single execution, which is what the prefix is. `Infernix.DescriptorSpace` is
this repository's own precedent and differs in exactly that respect: it lowers only the *soft*
`RLIMIT_NOFILE`, in process, as the first action of every image, and that is sound there because the
bound exists to cap the cost of the descriptor walk rather than to constrain a process that would
prefer more.

**The enforcement tool is a pinned literal.** `/usr/bin/prlimit` is written as an absolute constant
in Haskell and is not a `toolPaths` field. A manifest field is operator-editable by design, and an
enforcement path that the configuration of the thing being bounded can repoint is not an enforcement
path. This is the same argument that pins the device observer's `/usr/bin/nvidia-smi` and the Apple
footprint observer's `/usr/bin/top` and `/usr/bin/footprint`. The read-only-probe carve-out that
covers `ps` and `vm_stat` deliberately does not transfer: `prlimit` is not read-only, it installs
kernel state and then becomes the engine.

**A new lint keeps a future spawn surface from skipping the installation.**
`unboundedCeilingInstallViolations` in `Infernix.Lint.HaskellStyle` is the sibling of
`unboundedDescriptorSpawnViolations` and exists for the same reason that one does: the bound is
established at one site and required at another, and a new spawn surface added later would compile
perfectly while observing neither. The lint requires every engine-spawn site to reach the
installation region, so the omission is loud at the gate rather than silent until a cohort run.

**`apple-silicon` resolves detection only by construction, and that is a deliverable.** Darwin has
no cgroups, and its address-space limit is aliased to an advisory limit that rejects every finite
ceiling, so there is nothing on that lane to install. The Apple arm of the installation region is
therefore a *total* function returning the detection-only value — not an unimplemented case, not a
silent fall-through to the Linux path, and not a claim of prevention that the mechanism does not
provide. The lane declares the strength it has in its type, and a contract requiring prevention
refuses readiness there rather than accepting the weaker mechanism under the stronger word.

**Prevention is claimed only after calibration.** `linux-cpu` declares detection only until a real
engine on that lane has been observed to have an over-budget allocation refused cleanly under an
installed ceiling. This sprint ships the mechanism and the gate; the observation is what converts
the declaration, and an uncalibrated ceiling installed low enough to refuse a legitimate allocation
would convert a capacity question into a redelivery loop.

### Validation

- `infernix-unit` pins the rendered argument vector for a given ceiling and engine command exactly,
  and pins that no exported function of the ceiling module accepts an executable, argument vector,
  environment, or working directory.
- The spawn boundary is package-internal by design, and `infernix-compile-fail` already pins that:
  `fail-raw-capped-launch` rejects any import of `Infernix.Runtime.CappedEngine` from outside the
  package. A dedicated fixture passing an un-bounded command to the spawn would have to re-export the
  boundary first, which is the thing being prevented, so no such fixture is added. Inside the package
  the property is proved by the build itself — `withCappedEngine` accepts only a
  `BoundedEngineLaunch`, whose constructor only the region mints, so every call site reaching the
  spawn compiles only because it passed through the region.
- `infernix-unit` pins that the Apple arm resolves to detection only and that no input makes it
  claim prevention. The production readiness consumer rejects that weaker declaration when a
  contract requires prevention, before runtime refinement can mint executable capabilities.
- `infernix test lint` runs `unboundedCeilingInstallViolations` with a negative fixture that skips
  the region and a positive control that does not.
- `infernix-unit` covers the read-back comparison: matching soft and hard values proceed, either
  value disagreeing with the installed quantity is a typed terminal failure and never a retryable
  transient.
- On `linux-cpu`, a real native engine completes under the fitted installed ceiling and refuses an
  over-budget allocation cleanly under a lower installed ceiling, so that calibrated lane declares
  prevention. The read-back remains part of the routed full-suite contract.
- The `linux-cpu` full suite passes with real SmolLM2 and TinyLlama output, typed fail-closed
  unsupported artifact outcomes, durable throughput, lifecycle rebinding, and the routed browser
  matrix.
- **Cohort:** on the Apple lane the observed
  outcome is a *declared* detection-only lane, which is a pass rather than a failure. The selected
  accelerator runs against the same code state as the paired `linux-cpu` evidence.

### Scope Boundaries

- What this sprint does not make impossible, stated so it is not read as more: shared and pinned
  host mappings are outside the installed ceiling, and a per-process limit says nothing about a tree
  total. Both residues are the sampling kernel's, and the host ledger's scope statement is
  unchanged.

### Remaining Work

None.

---

## Sprint 4.42: The Execution Shape Reaches The Engine [Done]

**Status**: Done. The conformance layer is landed, the compiler-carried execution shape reaches both
Python adapters and native runners, and the selected `apple-silicon` plus `linux-cpu` cohort passes.
**Code-side closure**: complete, including the container-lane regeneration and the re-pinned binding
inventory. `cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`,
`infernix-compile-fail`, `infernix-haskell-style`, `poetry run check-code`, and `infernix lint
files|chart|proto|docs|plan` plus `infernix docs check` — with `lint proto` reading the re-pinned
binding inventory rather than the retired one.
**Cohort validation**: real rows run under the carried shape on `apple-silicon` plus `linux-cpu`,
with the acknowledged ceiling matching the installed quantity wherever a ceiling is installable.
**Blocked by**: Sprint 4.39, Sprint 4.41.
**Implementation**: `proto/infernix/runtime/inference.proto`, `proto/haskell-bindings.sha256`,
`src/Proto/`, `tools/generated_proto/`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/ExecutionPlan.hs`, `src/Infernix/Runtime/CappedEngine/Internal.hs`,
`python/adapters/common.py`,
`python/adapters/transformers_python.py`, `python/adapters/pytorch_python.py`,
`python/adapters/vllm_python.py`, `test/unit/Spec.hs`
**Docs to update**: none.
[../documents/development/python_policy.md](../documents/development/python_policy.md) already
states that an adapter receives its memory-shaping parameters rather than choosing them, that the
acknowledgement rides the response rather than adding a handshake, and that the budget and shape are
applied before any weight loads; this sprint makes the adapters match.

### Objective

Carry the admitted quantities and the execution shape to the engine on the message the engine
already reads, get the installed ceiling back on the message it already writes, and delete the
adapter literals that were standing in for both.

### Deliverables

**The acknowledgement carries two values, not three.** An earlier form of this sprint put the
resource beside the soft and hard read-back. It is not carried, and the decision is recorded here
rather than left to be rediscovered: the only consumer is the worker, which already holds the
resource in the `InstalledCeiling` it installed, and the adapter cannot produce it without
duplicating the lane's resource naming in Python — a second enumeration that can disagree with the
first, which is exactly what Sprint 4.38 deleted. A field that one side derives and the other side
never reads is a second copy of a fact, and this phase has spent four sprints removing those.

**Typed budget and acknowledgement on the worker envelope.** `WorkerRequest` in
`proto/infernix/runtime/inference.proto` gains a typed memory-budget message carrying the admitted
per-resource quantities, and a typed execution-shape message carrying context length, batch,
generation bound, key/value cache element width, and load strategy. `WorkerResponse` gains the
acknowledgement: the soft and hard ceiling values the engine read back from inside its own image,
and the resource they bound. Both are typed fields decoded from the same protobuf the worker and
adapter already exchange, not text an adapter formats and a worker parses.

**Exactly one device route is populated, never both.** The budget's resource shape is a `oneof` over
the placement's own arms — host-only, or host plus device — so a request carrying both a host-only
claim and a device quantity, or carrying neither, is not representable on the wire. Two independent
optional fields would let a caller populate both and let a decoder guess which one meant it; a
discriminated alternative makes the choice the sender already made visible to the receiver.

**The shape is carried, not restated.** The execution shape is computed once, by the compiler, as
the input to the cache term of Sprint 4.39's derivation, and travels on the executable model to the
worker and onto the request. One value, two consumers. The engine therefore runs the context length,
batch, generation bound, and load strategy the compiler admitted the model against, rather than a
number that was never compared against a machine.

**The adapter literals are deleted.** `MAX_NEW_TOKENS = 32` in
`python/adapters/transformers_python.py`, `SamplingParams(max_tokens=256)` in
`python/adapters/vllm_python.py`, and `semantic_max_new_tokens=100` in
`python/adapters/pytorch_python.py` are replaced by fields on `AdapterContext`, which gains the
decoded budget and shape. `run_context_adapter` applies them before any weight loads — earlier than
the model-cache configuration that follows — because a framework that has already sized an arena
cannot be retroactively bounded, and a ceiling read back after the first large allocation reports a
fact rather than establishing one.

**The acknowledgement rides every response, not only a successful one** — corrected after a live
cluster lane showed what the omission costs. It is a fact about the adapter process, the limit it was
started under, and it is read before the transform runs, so it is equally true when the transform
fails. The retired form attached it only to the two success responses, so a failed adapter reported no
limit at all and the worker's conformance check then replaced the adapter's own typed error with a
ceiling mismatch — the one message that says nothing about why the engine failed. Measured on both
Linux lanes: a framework row whose engine could not start under its installed ceiling published
`could not confirm its installed ceiling: the engine reported a data-segment limit of 0:0 bytes`,
which named the check rather than the cause.

**The one-request/one-response contract is preserved, deliberately.** The acknowledgement rides the
existing response rather than becoming a handshake. An adapter that announced its installed limit
and waited for permission to continue would turn a process with exactly one failure mode — it wrote
a response or it did not — into one with a protocol state machine, a second deadline, and a
partial-exchange state that neither side can classify. The conformance layer is worth having; a
second round trip to obtain it is not, and recording that as a decision keeps a later reader from
"improving" the contract into the shape this sprint rejected.

**Native projection and execution consume that same shape.** The opaque native invocation carries
the descriptor's `ModelExecutionShape`. The llama.cpp renderer takes its context length and
generation bound from that value, and the bounded pre-flight projection consumes the same
`LlamaNativeExecution`; thread count and device-layer count remain sealed properties of the
CPU-native artifact binding because they are not duplicated fields of the carried shape. A native
row therefore cannot be admitted and projected at one cache-bearing shape and invoked at another.

**A generation bound stops being a grep.** `test/unit/Spec.hs` currently asserts that the literal
text `model.generate(**inputs, semantic_max_new_tokens=100)` appears in the PyTorch adapter's
source. That assertion tests the spelling of a line rather than the value that reaches the model:
reformatting the call breaks it while changing the bound to any other literal does not. It is
retired rather than updated, and what replaces it is two ordinary assertions — that the compiler
puts the derived bound on the request, and that the adapter applies the bound it received. A value
that is passed can be checked where it is passed.

**Proto regeneration is a container-lane step with a re-pinned inventory.** The four tracked Haskell
binding modules under `src/Proto/` regenerate only on the Linux container lane, under pinned
`libprotoc 34.1` plus the Docker-only bounded install of `proto-lens-protoc 0.9.0.1`, generated into
a temporary tree and byte-compared. A Darwin checkout consumes and hashes the snapshot and cannot
produce it, so a schema edit made on an Apple host is incomplete until that lane runs. The
`proto/haskell-bindings.sha256` inventory covers the two canonical schema inputs and the four
generated modules, and `infernix lint proto` validates schema shape, the exact regular-file
inventory below `src/Proto/`, and all six hashes without spawning a compiler — so an envelope change
landed without its regeneration is a red gate rather than a silent skew. The generated Python
bindings under `tools/generated_proto/` move in the same change.

### Validation

- `infernix lint proto` passes against the re-pinned inventory, and the byte-compare regeneration on
  the container lane reproduces the four tracked modules exactly.
- `infernix-unit` pins that the execution shape the cache term was derived from is byte-identical to
  the shape placed on the request, so the two consumers of that one value cannot disagree.
- `infernix-unit` pins that a host-only placement populates the host arm of the budget alone, and
  that no encoding populates both arms.
- `infernix-unit` covers the acknowledgement path: a response whose reported soft and hard values
  match the installed quantity completes, and a mismatch is a typed terminal failure rather than a
  retryable one, so a conformance failure cannot be laundered into a redelivery.
- `poetry run check-code` stays machine-independent: the adapters gain typed fields and no top-level
  framework import, and `pyproject.toml` gains no framework dependency, so the gate stays runnable
  on a machine with no engine wheels.
- The retired source-text assertion is gone, and the two assertions replacing it are named in the
  suite so the retirement is visible rather than a deletion.
- **Cohort:** the `linux-cpu` and selected Apple full suites
  pass. `llm-tinyllama-gguf` completes through the native runner with the carried context and
  generation bound, `llm-smollm2-safetensors` completes through the framework adapter, and every
  unsupported checkpoint family fails closed as `ModelRequirementUnderivable`. The selected Apple
  lane produces real output from the same derivable rows against its materialized native roots.

### Scope Boundaries

- The proto regeneration and the inventory re-pin ran on this Linux host under the pinned
  `libprotoc 34.1` plus `proto-lens-protoc 0.9.0.1`, and the byte-compare reproduced the manifest
  module unchanged, so the four tracked modules and their six hashes are current. The image build's
  own regeneration remains the standing drift check.
- The device arm of the budget message is defined and encodable here but is populated by no
  placement this phase's accelerator compiles; its live use is validated under a different wave
  against a different accelerator.

### Remaining Work

None.

---


## Sprint 4.43: The Ceiling Is Installed Against The Engine's Own Projection [Done]

**Status**: Done. The installed host ceiling is the greater of the artifact-derived requirement and
the engine's bounded pre-flight projection, with the contributing quantities preserved as typed
provenance.
**Blocked by**: Sprint 4.39, Sprint 4.41.
**Implementation**: `src/Infernix/Runtime/CappedEngine/Projection.hs` (new),
`src/Infernix/Runtime/CappedEngine/Ceiling.hs`,
`src/Infernix/Runtime/CappedEngine/Internal.hs`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/Engines/Artifact/Capability.hs`, `src/Infernix/Engines/Artifact/Internal.hs`,
`src/Infernix/Types.hs`, `src/Infernix/ExecutionPlan/Properties.hs`, `infernix.cabal`,
`test/unit/Spec.hs`
**Docs to update**: [../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
— updated. The per-lane strength table stated that the installed ceiling is derived from the artifact
alone. It is now derived from the artifact **and**, where the engine family ships a projection tool,
that engine's own projection, which is a different provenance claim and is stated as one.

### Objective

Install a ceiling the engine can actually run under, without authoring a headroom constant.

### The defect, stated exactly

The derivation Sprint 4.39 landed is correct about what it models and silent about what it does not.
For `llm-tinyllama-gguf`, the artifact's own tensor table supplies the exact weight and largest-tensor
terms, while the compiler-carried execution shape supplies the cache term. The native invocation and
its projection consume that same shape, including the declared 2048-token context, so none of those
quantities is restated by the runner.

The two host formulas remain distinct. Where a placement declares `StreamWeightsToDevice`, the host
requirement is the staging window — the largest single tensor — because weights live on the device.
The CPU-native llama binding instead renders `--gpu-layers 0` and carries `LoadResidentHost`, so its
artifact derivation includes resident weights and its projection reports the host-resident working
set that same execution needs. `resolveEngineCeiling` takes the greater of those two quantities, and
the sampled backstop watches that installed quantity. The model-derived term therefore stays
authoritative while the engine-owned projection accounts for working memory the checkpoint header
cannot describe, without introducing an authored headroom constant.

### Deliverables

- a bounded pre-flight projection, taken through a closed package-internal specification in which the
  caller supplies no command text
- the installed ceiling is the greater of the artifact-derived requirement and that projection, never
  a replacement of one by the other
- the provenance is part of the installed value, so artifact-plus-projection and artifact-alone are
  distinguishable quantities
- a projection that cannot be obtained is a typed refusal naming the model and the reason, never a
  fall back to the derived quantity and never an unbounded launch

### Landed Implementation

**The engine answers this question about itself.** llama.cpp ships `llama-fit-params` in the same
pinned payload as the completion front-end, and `-fitp on` prints its estimated required memory
without loading the model. The projection and the engine render context length, generation bound,
thread count, and device-layer count from one `LlamaNativeExecution` value. The parser selects the
host model, context, and compute estimates for the execution that will run, and the installed ceiling
uses the greater of that sum and the artifact derivation. The quantity is therefore the engine's own
projection rather than a headroom constant.

**The probe is a closed per-family specification.** `Infernix.Runtime.CappedEngine.Projection`
exposes an opaque `EngineProjectionRequest` whose only mint takes the adapter id, the model payload
path the invocation already resolved, and the lane's execution literals. There is no exported
function taking a command, an argument vector, an environment, or a working directory. The probe
executable is a **file name**, not a path: the launcher resolves it as a sibling of the validated
entry object, inside the same sealed immutable closure root the artifact's own evidence binds, so the
probe cannot be pointed anywhere the engine itself is not.

That is why it is neither a host-manifest field nor an entry in the pinned enforcement catalog. Both
of those exist for tools the binary reaches on the *host*, where an operator-editable path would make
an instrument redirectable. This probe is a member of the engine artifact, reached the same way the
engine's own entrypoint is and bound by the same evidence, and the host-tools manifest no more
enumerates it than it enumerates `llama-completion`.

**The installed ceiling is the greater of the two quantities.** The artifact-derived requirement
remains the admission quantity — admission is still a statement about the machine's capacity and the
model's own bytes. `resolveEngineCeiling` takes an `EngineCeilingProjection` and installs
`max(derived, projected)`. Taking the maximum rather than replacing one with the other keeps the
derivation authoritative wherever it is larger, so an engine that under-reports cannot widen its own
bound below what its weights and cache provably need.

**The provenance is part of the value.** `InstalledCeiling` carries a `CeilingProvenance` —
artifact, or artifact plus a named projected quantity — beside the derived quantity it retains. A
ceiling derived from artifact-plus-projection is not the same value as one derived from the artifact
alone, so the strength table states the difference instead of implying a single provenance, and the
margin between the two is evidence a later calibration can read rather than a number that has to be
recovered by re-running.

**Projection failure is fail-closed and typed.** A probe that is absent from the sealed closure,
exits non-zero, emits an unparseable projection, reports no host row, or reports a non-positive
quantity produces `NativeArtifactProjectionRefused`, which the worker publishes as
`ModelRequirementUnderivable` naming the model, the artifact family, and the reason. It does not fall
back to the derived quantity and it does not launch unbounded, because the caller turns it into a
terminal outcome that starts no engine at all.

**A device row is read and deliberately not summed into a host ceiling.** The parser selects the
host row, because that is the quantity a data-segment ceiling charges; folding device buffers into it
would be wrong in the direction that hides a real bound.

**The sampled backstop watches the quantity that was installed.** Prevention and detection agree on
the resource the ceiling binds: a projection that widens the installed quantity widens that
resource's sampled ceiling with it. Every other resource keeps its own grant because no ceiling was
installed for it.

**The probe is not bounded by the quantity it exists to correct.** A first form ran it under the
artifact-derived ceiling, on the argument that a tool reporting what a model needs should cost less
than the model. Measured, that argument fails on the lane it matters for: the upstream projection
tool needs roughly 48 MiB of private writable memory whatever model it is asked about, while a
device-streaming placement's derived host term is the largest single tensor — 52 MiB for this row and
smaller for a smaller model. Bounding the probe by that quantity would refuse the tool that would
have corrected it, which is this sprint's own defect arriving one layer earlier. The probe therefore
installs nothing and runs no watchdog, and what bounds it is what bounds every other process in the
pod: the lane's outer envelope, a kernel limit this code neither installed nor can raise, plus the
bounded engine output capture and a closed argument grammar over an executable sealed in the
artifact's own closure.

### Landed Decisions

Four decisions inside this sprint are recorded rather than left to be rediscovered.

**The projection is asked for exactly where its answer is used.** It only ever changes an *installed*
quantity — the launch prefix and the read-back it is compared against — and reaches nothing else.
The resolver therefore resolves the lane's unprojected ceiling first and returns no projection at all
when that ceiling is detection-only. Probing an `apple-silicon` placement would spend a process to
change nothing, and would turn an engine payload that happens not to ship the projection tool into a
refused row on a lane this phase's cohort cannot exercise. The rule is derived from the lane's own
resolved strength rather than written down per lane, so a lane that later gains a mechanism gains the
projection with it.

**The probe and the engine render the same execution operands from one value.**
`LlamaNativeExecution` holds the lane's context length, generation bound, thread count, and device
layer count, and both `renderNativeArtifactArguments` and the probe render from it. Its cache-bearing
operands are constructed from Sprint 4.42's compiler-carried execution shape, so a probe asked about
one context or generation bound cannot describe an engine invocation that runs another. Thread and
device-layer values remain closed properties of the sealed CPU-native binding.

**The probe installs no per-execution ceiling.** It runs under `projectionProbeCeiling`, whose
strength is `CeilingDetectionOnly`, because bounding the projection by the quantity it exists to
correct could refuse the tool before it reports the corrected quantity. The enclosing pod envelope,
bounded output capture, closed argument grammar, and sealed artifact closure bound the probe surface.

**No supported Python engine family ships a projection tool**, and the quantity that lane installs is
therefore the lane's own per-execution budget rather than the model's derived requirement. The
argument is the same one the projection makes for llama.cpp, applied where no tool exists to ask: a
framework adapter's interpreter, framework, and device runtime are resident before a single weight is
read, and no term of them appears in a checkpoint's tensor table. Measured on both Linux lanes, a 269
MB safetensors checkpoint derives roughly 302 MiB while the framework alone needs more than that
before it loads anything, so installing the derived requirement refused a model that would have run.
The lane's budget is what the pod was provisioned for and what the retired per-family constant
approximated; the derived requirement is unchanged as the quantity admission compares against the
machine's capacity. The same correction applies to the device arena for the same reason — a CUDA
context alone is roughly half a gigabyte — and the admitted device grant is left untouched so
refinement stays checkable against it.

**A single-file model is asked for by name, and only a snapshot needs a listing.** The staged-object
read tries the `payload` key directly, because that key is known without a listing and a listing is a
capability this process may not have on every lane. Only a model that is not staged that way has its
prefix enumerated, and a listing that cannot be performed reports the HTTP status it got rather than
an empty result — an absent capability recorded as an absent object is the same defect as an absent
key recorded as an absent family.

### Validation

- `infernix-unit` pins that the probe and the engine invocation render the same execution operands
  from one value, and that the probe's remaining operands are exactly the upstream tool's
  print-estimate flag. A projection describing a different execution than the one that runs is the
  failure this assertion exists to catch.
- `infernix-unit` pins the parser against the tool's real output shape: a host row sums its three
  estimates; a device row beside a host row does not contribute to the host quantity; and an empty
  output, a non-numeric quantity, a host-less output, and a non-positive total each yield a reason
  rather than a small number.
- `infernix-unit` pins that a projection above the derived requirement widens the installed ceiling
  while retaining both quantities, that a projection **below** it leaves the installed quantity at
  the derived one, and that the rendered launch prefix lowers both limits to the quantity actually
  installed — the one site where installing a widened ceiling and rendering the narrower number would
  reintroduce the defect.
- `infernix-unit` pins that every native engine family other than llama.cpp declares no projection,
  so an absent tool is a positive statement rather than an omission.
- `infernix-unit` pins that the probe's own launch installs nothing while still carrying the quantity
  the plan would have installed, so a reader can see both facts on one value.
- `infernix-execution-plan-internal` pins that a projection widening the installed ceiling widens the
  sampled ceiling for the same resource with it, that no projection leaves the sampled ceiling at the
  artifact-derived grant, and that a host projection does not move the device backstop. This is the
  assertion the cohort's first attempt would have failed.
- `infernix-execution-plan-internal` pins that an underivable requirement renders its own error code
  and reason rather than a limit-exceeded payload with invented quantities. `workerFailureResponse`
  became a total case over `InferenceError` with this sprint; the retired form read a quantity out of
  a payload that deliberately carries none.
- machine-independent gates at zero, as recorded in the header.
- **Selected `linux-gpu` plus `linux-cpu` cohort — passed.** `llm-tinyllama-gguf` completed on the
  native lane on both lanes rather than failing to allocate its cache, and
  `llm-smollm2-safetensors` completed through the framework lane on `linux-cpu` under the quantity that
  lane provisions rather than the 302 MiB its artifact derives.

### Scope Boundaries

Two properties this sprint deliberately does not claim, recorded so a green cohort
is not read as covering them.

1. **The device backstop still watches the admitted grant while a framework adapter is sized by the
   lane's device budget.** That is the same prevention-and-detection asymmetry this sprint corrected on
   the host side, surviving on the device side, and it is why the `linux-gpu` framework row publishes a
   typed `gpu-vram` breach at 612 MiB observed against 302 MiB rather than completing. The breach is
   correct, well-formed, and exactly what the sampled backstop is for; what is wrong is that the
   quantity it watches is not the quantity the engine was sized by. Correcting it is the device half of
   the argument this sprint makes for the host and belongs to a sprint of its own.
2. **The declared load strategy and the native invocation disagree on the device lane, and this sprint
   covers the symptom rather than the disagreement.** `llm-tinyllama-gguf` compiles to
   `StreamWeightsToDevice` on `linux-gpu` because its selected engine binding declares the device,
   while `renderNativeArtifactArguments` renders `--gpu-layers 0` and the image's llama.cpp payload
   carries CPU backends only. Two consequences follow and neither is closed here: the host formula
   drops a model term the host actually holds, and a VRAM grant is admitted and watched for a process
   that allocates no device memory at all. The installed ceiling is correct after this sprint because
   the projection describes the execution that runs; the *placement's* description of that execution
   is still wrong. Correcting it moves a catalog row's declared shape, which the README matrix
   projection and the device admission arithmetic both read, so it is a separate change with its own
   validation rather than a widening of this one.


### Remaining Work

None.

---

## Sprint 4.44: A Kernel-Refused Allocation Is A Typed Breach [Done]

**Status**: Done. A kernel-refused allocation is classified as a typed memory breach independently
of whether the installed ceiling is wide enough for a particular model.
**Blocked by**: Sprint 4.37, Sprint 4.41.
**Implementation**: `src/Infernix/Runtime/CappedEngine/Internal.hs`,
`src/Infernix/Runtime/Worker.hs`, `src/Infernix/Engines/Artifact/Capability.hs`,
`src/Infernix/Engines/Artifact/Internal.hs`, `src/Infernix/Types.hs`,
`src/Infernix/ExecutionPlan/Properties.hs`, `test/unit/Spec.hs`,
`test/integration/Spec.hs`
**Docs to update**: [../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
— updated. The three-layer enforcement account states that a breach is a clean typed
`ModelMemoryLimitExceeded`. That was true of the sampled layer and false of the installed layer, and
the document now states it for both and names the two shapes the payload distinguishes.

### Objective

Make the installed layer report a breach in the same typed shape the sampled layer already does.

### The defect, stated exactly

A kernel-refused allocation must not collapse to an unclassified native-engine exit. The installed
ceiling can prevent an allocation before the sampled footprint crosses that ceiling, so the
classification consumes the ceiling-refusal evidence rather than relying on a sampled overrun.

Neither existing layer catches it. The sampled backstop watches resident footprint and the process
never exceeded its ceiling — the kernel refused the allocation, so the memory was never resident to
observe. The exit-code classifier sees a non-zero exit and has no evidence distinguishing a
ceiling-refused allocation from an ordinary engine fault. The result is the specific outcome the
memory doctrine exists to prevent: an operator cannot tell "the bound I installed was too tight"
from "the engine is broken", and the two demand opposite responses.

This is narrower than it may read. The failure was clean and real — no fabricated result, no
masqueraded output, and the realness contract held. What failed is the *classification*, and the
claim in the doctrine that a breach names the resource it breached and the footprint it observed.

### Deliverables

- a ceiling-refused exit is classified from evidence this kernel holds — the ceiling it installed and
  its own sampler's peak — never from engine standard-error text
- the observation reported is the one that was made, so a refusal at the boundary reports the ceiling
  and the peak rather than a number invented above the limit
- the payload distinguishes a refusal at the boundary from a sampled overrun above it
- an engine exit the evidence does not support stays a plain engine failure and says so

### Landed Implementation

**The loop keeps the observations it was already making.** The one sampling kernel Sprint 4.40 landed
compared each complete observation against its ceiling and then discarded it. It now merges every
complete observation into a per-resource peak record on the engine handle, keeping the larger. That
costs one reference write per sample and is the difference between a diagnosis and a bare non-zero
exit, because a kernel-refused allocation is never resident and the loop's own peak is the only
observation such a refusal leaves behind.

**A ceiling-refused exit is classified from evidence, not from a string.** After the engine is
reaped, `classifyCeilingRefusal` reads the ceiling this launch installed and the peak its own sampler
observed. A non-zero exit, on a lane whose arm installed a data-segment ceiling, whose peak for that
resource came within the accounted allocation of the ceiling, becomes `EngineRefusedAtCeiling`
carrying the resource, the ceiling, the peak, and the engine's own exit code. Nothing matches engine
standard-error text, which is an upstream format this repository does not own — and this repository
has already paid for a predicate that searched a rendered string for text that value never contains.

**The margin is derived, not authored.** It is the model's own key/value cache term — the largest
allocation the plan still accounts for once the weights are in place, and in the measured failure
exactly the allocation the engine was refused. A process whose peak came within it of the ceiling was
refused for an allocation the plan itself knew about. A model that declares no geometry has no such
term, so its margin is zero and its peak must have reached the ceiling outright.

**The observation reported is the one that was made.** `modelCeilingRefusalError` publishes the
ceiling that was installed as `availableMib` and the peak that was actually observed as
`requiredMib`, which for a refused allocation is at or below it. Sprint 4.37's invariant that required
strictly exceeds available is left attached to `modelCeilingBreachError`, the overrun shape it
describes, rather than weakened: inventing a number above the limit to satisfy it here would be the
same fabrication the breach path was corrected for. The payload distinguishes the two by naming its
own source, `capped-engine-refused-at-ceiling` against the overrun's
`capped-engine-resident-ceiling`, and the operator line renders differently for each.

**An unclassifiable engine exit stays untyped and says so.** Where the evidence does not support the
memory classification — no peak was recorded, the peak stayed clear of the ceiling, the lane installed
nothing, or the peak belongs to another resource — the failure remains a plain engine failure.
Guessing would replace a missing diagnosis with a wrong one, which is this defect pointing the other
way.

### Landed Decision

**Classification reads the ceiling this process installed rather than the engine's acknowledgement.**
An earlier form of this sprint took the acknowledgement Sprint 4.42 carries as the evidence that a
ceiling was in force. It is not the right input here for two reasons. The acknowledgement is the
Python-stdio lane's — a native runner is an upstream program that writes no worker response at all,
and the native lane is where this defect was observed. And the acknowledgement is a *conformance*
check that already has its own typed terminal failure; reusing it as classification evidence would
make one value answer two questions, which is the shape this phase has spent five sprints removing.

### Validation

- `infernix-integration` classifies a limit-exceeded refusal by its source rather than requiring the
  overrun's strict inequality of both shapes. The retired predicate would have forced this path to
  invent a number above the limit to be accepted, which is the fabrication the breach path was
  corrected for.
- `infernix-unit` pins that the shared loop retains the **highest** observation it made rather than
  the last, so a peak that has since fallen back is still reported, and that a loop which completed
  no observation records none.
- `infernix-execution-plan-internal` pins the classification against a lane that installs a ceiling:
  a peak at the ceiling and a peak exactly one accounted allocation below it are both refusals naming
  the resource and the ceiling.
- The load-bearing negative is pinned beside them: a peak one MiB clear of that boundary stays an
  ordinary engine failure. A classifier that fired on any non-zero exit would satisfy every positive
  assertion above.
- `infernix-execution-plan-internal` pins that no peak at all, a peak on another resource, a
  successful exit, and a detection-only lane each leave the outcome untouched, and that a sampled
  overrun keeps its own shape rather than being rewritten as a refusal.
- `infernix-execution-plan-internal` pins that the refusal payload reports the installed ceiling and
  the observed peak with required at or below available, that it names its own source, that the two
  shapes render operator lines a reader can tell apart, and that a refusal is still carried on the
  reserved memory-limit error code.
- machine-independent gates at zero, as recorded in the header.
- **Selected `linux-gpu` plus `linux-cpu` cohort — passed on its negative half.** Both lanes ran a
  full catalog with ceilings that fit, and no engine exit was classified as a memory refusal that was
  not one. A live engine refused by a real kernel limit is the positive the unit layer covers.

### Scope Boundaries

Three properties this sprint does not claim, each recorded because a green cohort
could otherwise be read as covering it.

1. **The adversarial positive is unit-covered, not cohort-covered.** No row on either lane was refused
   by the installed kernel limit once the ceilings were corrected, which is the outcome the corrections
   exist to produce, so the cohort exercised the classifier's refusal-to-classify rather than its
   classification. A gate that drives a launch under a deliberately insufficient ceiling would close
   that, and it is a source change with its own validation.
2. **A sampling gap remains, and it is stated rather than closed.** The peak is sampled on a fixed
   cadence, so an allocation refused between two samples is classified from the last observation
   taken rather than from the highest one reached. That widens the window in which a refusal is left
   an ordinary engine failure — the safe direction — and it does not widen the window in which an
   ordinary fault is called a memory failure.
3. **The margin is eager where the ceiling is comparable to it**, and that is stated rather than
   tuned away. The cache term is a fixed quantity while the ceiling is not, so on a placement whose
   ceiling is only a small multiple of its own cache term almost any non-zero exit falls inside the
   window. That regime is exactly the one in which a refusal is the likely cause — a ceiling that
   close to a single accounted allocation is a ceiling nothing runs under — so the eagerness is
   where it belongs. Narrowing it would mean choosing a fraction, which is an authored number wearing
   a derived number's clothes.

### Remaining Work

None.

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
