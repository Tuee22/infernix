# Phase 4: Inference Service and Durable Runtime

**Status**: Done — the memory-safety-by-construction reopen (2026-07-21) is closed under
[Wave W](cohort-validation-waves.md) (2026-07-24) with apple-silicon plus `linux-cpu` behavioral
sign-off: Sprint 4.30 (Memory-Grant admission + capped-engine kernel) and Sprint 4.31 (host memory
partition, required footprint, budget-enforcer split) are code-side closed on the machine-independent
gate set (2026-07-21: `cabal build all` `-Wall -Werror`, `cabal test infernix-unit`,
`cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, `infernix docs check`,
`poetry run check-code`), and both behavioral lanes are GREEN. On apple-silicon `infernix test
integration` drove the full per-model lane with zero host OOM (13 real completions;
`image-sdxl-turbo`/`image-apple-stable-diffusion-coreml` pre-admission typed-rejected at 12288 > 10240;
`audio-bark-small` a live `proc_pid_rusage` watchdog resident-ceiling breach) and `infernix test e2e`
passed routed Playwright 16/16, and the `linux-cpu` clean `test all` passed integration and Playwright
16/16 with typed rejections via the pod-cgroup enforcer — see [Wave W](cohort-validation-waves.md)
(frozen workload image `sha256-bcf88c23fda211a4b5f3701c1c1c66ab223462f40d709be795e8f7b2d44ccee0`). The
earlier lifecycle-rebinding warm-cache flake that once blocked the clean run was diagnosed as a
representable invalid state (a fault-vs-absence collapse in the readiness observation) and **fixed by
construction** in the Observable-Readiness reopen (Phase 1 Sprint 1.18 + Phase 8 Sprint 8.8, code-side
closed 2026-07-22). Prior Done — the Managed-State-Transition Doctrine reopen
(Sprint 4.28) and the Bounded-Command
Application & Bounded-HTTP reopen (Sprint 4.29) are closed by [Wave V](cohort-validation-waves.md)
(2026-07-20, apple-silicon plus linux-cpu full-suite). Sprint
4.27 is closed for typed resource memory admission and typed inference
errors. The Apple-only integer budget, config-time over-budget fail-fast, hardcoded floor, and
stringly runtime failure payload are replaced by pure `InferenceMemoryBudget` / `InferenceError`
types. Wave T closed on 2026-07-12 with `linux-cpu` plus the selected `linux-gpu` accelerator.
Earlier Sprints 4.25 and 4.26 remain closed for their original evidence: Wave R closed the Apple
cohort on 2026-07-08, and Wave S closed the Linux lanes on 2026-07-09. The prior Wave O MT3 reopen
(Sprint 4.22) is closed — proven by Wave P (2026-07-04).
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Define the Haskell service runtime, the shared Python engine-adapter contract, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the shared Linux substrate image, the
> substrate-generated `.dhall` role contract, and the Apple host inference bootstrap that together
> make the runtime model honest and durable.

## Phase Status

> **Memory-safety-by-construction reopen (2026-07-21).** Sprint 4.27's request-time admission returned
> a proof-free `admitModelMemory :: … -> Maybe InferenceError` — a `Nothing` carries no evidence that
> admission actually ran — and the Sprint 4.28 engine spawn was raw and unbounded
> (`readCreateProcessWithExitCode` / `createProcess` in `runNativeWorker` / `runWorkerInvocation`), so a
> **host OOM was a representable outcome and a full-suite run proved it**: an over-budget model could
> exhaust host memory instead of failing cleanly. This phase reopens under
> [Sprint 4.30](#sprint-430-memory-grant-admission-and-capped-engine-kernel-done) — the grant-gated
> capped-engine kernel (`admitModelMemory` returns `Either InferenceError MemoryGrant`; the only
> engine-spawn path requires the grant and bounds resident memory to the admitted `MemoryCeiling`; a
> macOS `proc_pid_rusage` physical-footprint watchdog + process-group SIGKILL and a Linux
> pod-cgroup/VRAM-OOM exit classifier make an over-budget model a clean `status=failed`
> `ModelMemoryLimitExceeded`) — and under
> [Sprint 4.31](#sprint-431-host-memory-partition-required-footprint-and-budget-enforcer-split-done)
> — the checked `HostMemoryPartition`, the required `ModelMemoryFootprint`, and the budget-enforcer
> split dropping `UnenforcedMemoryBudget`. Both are now **code-side closed** (implementation landed and
> the machine-independent gate set GREEN on 2026-07-21): `admitModelMemory` returns
> `Either InferenceError MemoryGrant`, the capped-engine kernel `Infernix.Runtime.CappedEngine` owns the
> sole grant-gated engine spawn (`withCappedEngine` + the `proc_pid_rusage` watchdog on `apple-silicon`
> / the OOM-exit classifier on `linux-*`), the raw `readCreateProcessWithExitCode` / `createProcess`
> engine spawns are retired from `runNativeWorker` / `runWorkerInvocation`, and the budget /
> partition / footprint types are threaded through every codec mirror. The doctrine is documented in
> [../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
> (Phase 0 Sprint 0.15), and single-accelerator (apple-silicon) plus `linux-cpu` cohort sign-off closed
> under [Wave W](cohort-validation-waves.md) (2026-07-24).

> **Bounded-command application / bounded-HTTP reopen (2026-07-19).** The 2026-07-18
> single-accelerator cohort run surfaced a rate-limited upstream model download — the coordinator's
> in-pod fetch of `music-omnizart` returned HTTP 403 (a UA-less request tripping the origin WAF, which
> also carried `Retry-After`), and the Sprint 4.28 kernels shipped but did not yet classify that
> outcome or bound the fetch. This phase addressed the gap under
> [Sprint 4.29](#sprint-429-classified-model-download--integrity-witnessed-sentinel-done) to send a
> descriptive `User-Agent`, consume the Sprint 1.17 `DownloadOutcome` with a `Retry-After`-honoring
> bounded redelivery (permanent failures ack to stop the redeliver-forever loop instead of hammering
> the origin), and strengthen the `.ready` sentinel: `PayloadVerified` is now minted only when the
> uploaded object's byte length matches the download, so a truncated upload can no longer mint a lying
> sentinel. Code-side closed 2026-07-19 on the machine-independent gate set (apple-silicon), and the
> single-accelerator (apple-silicon) plus `linux-cpu` cohort full-suite closed under
> [Wave V](cohort-validation-waves.md) (2026-07-20).

> **Realness reopen (real per-family inference).** A multi-agent audit established that the prior
> "real per-family output" closure was, for several catalog rows, satisfied by silent fabrication
> rather than real model execution: the Apple native engine layer (`AppleSilicon.hs`
> `infernix_emit_validation_result`) is entirely a validation wrapper, and on Linux the
> source-separation (Demucs/Open-Unmix), audio-to-MIDI (basic-pitch ONNX run on `np.zeros`), and OMR
> (Audiveris, never invoked) rows return constant/placeholder artifacts while whisper.cpp/CTranslate2
> mask runtime failures. Phase 4 therefore **reopened** Sprints 4.21–4.23 to deliver
> realness by construction — the engine code is made structurally incapable of returning a fabricated
> result (every missing-weights/load/engine failure raises → `status=failed`; host-memory exhaustion
> on `apple-silicon` was a separate gap, now **closed** by Sprint 4.26 admission control and
> [Wave R](cohort-validation-waves.md) (2026-07-08, full 16-model Apple lane with zero OS OOM-kill)),
> with real Linux engines,
> fixed weight provisioning, ONNX adoption where it is the mature free choice, and modern PyTorch
> rebinds for the music-transcription rows. The guarantee is mechanically enforced by a new realness
> lint owned with [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md).
> The architectural contracts (typed dispatch, catalog, pool routing, cache, object storage) from
> Sprints 4.1–4.20 stand and are **not** undone; only the faked engine internals are replaced. The
> Linux real-output cohort gate is [Wave K](cohort-validation-waves.md) (`linux-gpu` + `linux-cpu`);
> the Apple real-engine gate is [Wave L](cohort-validation-waves.md), owned by the reopened
> [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md),
> and closed on 2026-06-29. The removed fabrication surfaces are tracked in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

> **RAM-safety reopen (apple-silicon, 2026-07-07; code-side closed 2026-07-08).** The
> realness-by-construction guarantee above — every failure raises → `status=failed`, never a
> fabricated or silent result — held for engine *logic* but **not** for host memory on
> `apple-silicon`: all active models run on the on-host `infernix service` daemon serialized
> one-model-at-a-time as fresh subprocesses, and before Sprint 4.26 there was no per-model RAM
> footprint, per-substrate inference-RAM budget, or admission control, so a full per-model
> `test integration` drove the host into memory exhaustion and the OS SIGKILLed the daemon.
> **Sprint 4.26 closed that code-side gap for its original scope**: `ModelDescriptor` now carries a conservative
> `modelRamFootprintMib`, `DemoConfig` carries a host-computed `inferenceRamBudgetMib`,
> `validateDemoConfig` fails fast on an over-budget apple-silicon config, and the serialized engine
> critical section rejects an over-budget model as a clean `status=failed` (`overRamBudgetRejection`).
> The full-catalog Apple never-OOM cohort proof closed in [Wave R](cohort-validation-waves.md)
> (paired with Phase 6 Sprint 6.37), and the current Linux full-suite reruns closed in
> [Wave S](cohort-validation-waves.md). The retired unbounded path is tracked in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). Sprint 4.27 supersedes the
> config-wide fail-fast and stringly-result pieces of that implementation.

> **Resource-admission doctrine reopen (2026-07-09).** Sprint 4.26 proved the value of serialized
> runtime admission, but its catalog-wide fail-fast and stringly result payload are too restrictive.
> Sprint 4.27 is code-side complete for request-time admission with a pure budget and error model:
> a generated catalog may contain models larger than the daemon's current budget, smaller models
> must still run, and an oversized request returns typed
> `InferenceError.ModelMemoryLimitExceeded` with explicit `requiredMib` and `availableMib`. The
> Apple hardcoded floor is replaced by an explicit `EnforcedMemoryBudget 0 MiB` when the computed
> host budget is zero or negative; Linux CPU admits against the cluster engine pod memory limit;
> Linux GPU admits against GPU VRAM. Wave T closed on 2026-07-12 with `linux-cpu` plus the selected
> `linux-gpu` accelerator.

> **Common-shape reopen (Pulsar ML-Workflow convergence).** Phase 4's two
> common-shape deltas toward the shared contract (see [README.md](README.md) →
> Common-Shape Reopen and [development_plan_standards.md](development_plan_standards.md)
> §Q) are code-side closed: the **Coordinator** owns explicit Pulsar topic-lifecycle
> reconciliation from the typed runtime graph, replacing implicit broker
> auto-create reliance, and the binary emits its own decoder-reflected Dhall
> schema through `infernix internal dhall-schema host|cluster|secrets|substrate`.
> Per Phase 8, there are no version-controlled schema files; the schema exists only as the reflected
> output of the Haskell decoder types, emitted on demand.

> **Audit follow-on reopen (result timestamp safety).** Phase 4 reopened Sprint 4.24 after the June
> 2026 audit found a duplicate result-protobuf timestamp codec in `src/Infernix/Runtime/Pulsar.hs`:
> `resultToProto` serializes `UTCTime` with `show`, and `protoResultToDomain` parses it with partial
> `read`, while `src/Infernix/Storage.hs` already owns a safe ISO-8601
> `formatTimestamp` / `parseTimestamp` pair. Sprint 4.24 is closed: the Pulsar result-topic codec now
> uses the shared storage timestamp helpers, malformed `createdAt` values return `Nothing` instead of
> throwing, and the unit regression covers canonical roundtrip plus malformed input.

> **MT3 catalog replacement reopen.** The 2026-06-30 replacement of the obsolete MT3 residual with
> `music-mt3-infer` and `music-mr-mt3` reopened Sprint 4.22. The code-side implementation is landed:
> both rows bind through `mt3-infer` on the PyTorch adapter, stage weights through the model-cache
> contract, disable upstream auto-downloads, and are generated for `linux-cpu`, `linux-gpu`, and
> `apple-silicon` (Apple uses the PyTorch CPU path; no MPS claim is made). Earlier Wave K/Wave L
> evidence remains valid only for the catalogs that existed when those waves ran. The post-replacement
> full-suite proof is **closed**: [Wave O](cohort-validation-waves.md) proved both MT3 rows and
> [Wave P](cohort-validation-waves.md) (2026-07-04) closed the full suite (including the 27 GB
> `video-wan21-t2v` row).

Phase 4 closes around the staged-substrate runtime contract, the shared Python
adapter boundary, the Pulsar-driven request or result contract, the explicit engine-runner
dispatch, the mounted `/opt/infernix/cluster.dhall` cluster-wiring contract, and the reopened
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
The phase is `Done` for the current supported matrix substrate-accuracy closure: the README and
generated catalog now honestly describe the active CUDA cells (`ONNX Runtime (CPU)` for basic-pitch,
and CPU Ubuntu-release binaries for the llama.cpp / whisper.cpp rows), Apple RAM admission is
fail-clean by construction, and the current Apple, `linux-cpu`, and `linux-gpu` full-suite gates are
green. The prior Wave O MT3 catalog-replacement reopen (Sprint 4.22) is closed — proven
by [Wave P](cohort-validation-waves.md) (2026-07-04). The 2026-06-20 CUDA
Linux closure on the selected `linux-gpu` accelerator plus `linux-cpu`, per
[development_plan_standards.md](development_plan_standards.md) Section Q, remains valid for the
then-active catalog. The real per-family inference contract was re-validated through the Wave I
`linux-gpu` plus `linux-cpu` attestation, and the recorded Apple integration rerun continues to
prove the coordinator-routing/member-subscription path for the pre-replacement
active catalog: the coordinator loads the mounted Apple substrate config, runs with
`serviceRuntimeMode: apple-silicon`, publishes to the derived Apple pool topic, and the host engine
processes the request. The Apple transformers framework path is covered by the active safetensors
LLM row; earlier Apple evidence completed the predecessor `llm-qwen25-safetensors`, and current
source uses `llm-smollm2-safetensors` for the constrained CPU/Apple row. That Apple evidence was
recorded before Sprint 1.15 replaced the native wrapper payloads; Wave L records green Apple
integration and focused routed Playwright evidence for the real Apple native engines, plus the
paired `linux-cpu` full gate closed on 2026-06-29. The Apple
integration lane completes the active Apple model catalog through the host engine daemon,
cache lifecycle, service runtime loop, durable Pulsar
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
Face snapshot for the active safetensors LLM row is not treated as a failure. The full Apple
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
The 2026-07-09 Wave S rerun closes the current catalog after the Sprint 4.25/4.26 reopen: CPU image
`sha256:cfcd0c617a70919a1d083b43dfa66e9041b215a27a176ab82c2d806a36cf7627` passed style, Python
`check-code`, Haskell unit, web contracts (`71/71`), full integration (all real `linux-cpu`
per-model rows plus the HA/chaos tail), and routed Playwright `15/15`; GPU image
`sha256:31e076d62e5aab45d0f0894fcac86e634f1850aa46ae4611258f8ae3fab2ad66` plus engine images
`pytorch` `sha256:978779650affd4490b16913216fed83c7f942112da23d152eb1acd58b26b1585`, `diffusers`
`sha256:5643d7fdd17e599503328f6476d3a4d8dc1cc8d65c751fa2a1abaa5960ee25a0`, and `vllm`
`sha256:9be7ac2a614e235bcb346e4f9e4ff0433e7183bed7cfc170501d86d13ea21a61` passed style, Python
`check-code`, Haskell unit, web contracts (`71/71`), full GPU integration, and routed Playwright
`15/15` with the browser per-model matrix completing every catalog row.

## Current Repo Assessment

The repository has typed request or response shapes, typed runtime result metadata, a
README-matrix-backed generated catalog, protobuf-backed manifest and result helpers, explicit
cache status or eviction or rebuild flows, a shared Python adapter project whose setup entrypoints
write idempotent bootstrap manifests, explicit substrate-materialization helpers, and daemon
behavior driven by the staged substrate file. Durable model artifact storage lives in the
`infernix-models` MinIO bucket. The staged substrate file is a typed Dhall record at
`infernix.dhall`, decoded in-process by the `dhall` Haskell library. The runtime
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
**Cohort gate**: Closed — Sprint 1.14's headless Apple Metal/Core ML materialization lane is closed, and recorded Apple integration/e2e/all evidence proves the host-side bridge. Sprint 1.15 / Wave L owns routed real-output proof for the real Apple native payloads, so that evidence is not a Phase 4.3 blocker under the Section Q single-accelerator gate. Apple closure here reflects the then-active pre-MT3 / pre-Phase-8-eager catalog; the current 16-model catalog full per-model `test integration` was proven OOM-free on Apple by Sprint 4.26 admission control ([Wave R](cohort-validation-waves.md), 2026-07-08).
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
**Code-side closure**: Complete — the host daemon native worker consumes engine artifacts from `./.data/engines/<adapterId>/` and fails fast with `engine_binary_missing` when absent; proven by the machine-independent gate set (`cabal build all`, `cabal test infernix-unit`) on the recorded CUDA Linux host. The real Apple Metal artifacts themselves depend on Sprint 1.14's headless Apple materialization lane
**Cohort gate**: Closed — Sprint 1.14's headless Apple Metal/Core ML materialization lane is closed, and recorded Apple integration/e2e/all evidence proves the host daemon bootstrap. Sprint 1.15 / Wave L owns routed real-output proof for the real Apple native payloads.
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

- **Code (machine-independent — DONE):** the `src/Infernix/Runtime/Worker.hs`
  `renderNativeRunnerOutput` / `nativeRunnerLabel` debug-metadata native fallback was removed now
  that real native dispatch (Sprint 4.2) is in place, preserving the fail-fast-on-unsupported-adapter
  contract. Proven by `cabal build all` and `cabal test infernix-unit` on the recorded CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** `linux-gpu` plus `linux-cpu`
  confirm no generic-success or debug-metadata fallback path remains under real dispatch.

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
integration run. That early Linux CPU pass used framework-readiness checks rather than full
per-family inference for the predecessor Qwen and Bark rows; later Wave K/L work supersedes those
proof points with real per-family output for the then-active catalogs.
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md), Stage 2 (`linux-gpu` plus `linux-cpu`) — the
full per-engine `--with cuda` image bake and the real per-family output for every active-substrate
row. The Apple transformers engine project now declares an Apple-specific group and the Apple
rerun covers the active safetensors LLM row; the recorded Apple aggregate `test all` proved the
host-routing path before Sprint 1.15 real Apple native payload replacement, and the selected
`linux-gpu` plus `linux-cpu` real-output gate closed on 2026-06-20 through full-suite reruns. Basic Pitch
TensorFlow (published package pins TensorFlow `<2.15.1`) and the old TF-era Omnizart package do not
resolve on the Python 3.12 / CUDA 12.8 substrate and are named cohort residuals; the active Omnizart,
MT3-PyTorch, and MR-MT3 rows use maintained PyTorch packages.
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
  integration run exercised the Linux CPU framework readiness paths that were later superseded by
  Wave K/L real-output proof for the then-active catalogs.

### Remaining Work

- **Code (machine-independent) — DONE:** per-engine projects, worker resolution, Dockerfile bake,
  gitignore, base-image alignment, and Linux CPU framework venv groups for `transformers` and
  `pytorch`; validated by the gate set above on the recorded CUDA Linux host and the 2026-06-16
  Linux CPU image/integration lane.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** the full linux-gpu image bake of
  all engine venvs, live model-weight provisioning, runtime-backed native payload consumption
  (llama.cpp / whisper.cpp / ONNX Runtime / CTranslate2 / Audiveris), and real per-family output
  for every active-substrate row on `linux-gpu` plus `linux-cpu`; Basic Pitch TensorFlow and MT3
  are named residuals pending maintained equivalents or fallback-lane proof, while Omnizart is the
  maintained ByteDance PyTorch piano row.

---

## Sprint 4.17: Per-Engine Engine Images and Batch Routing [Done]

**Status**: Done
**Code-side closure**: Complete for the machine-independent scope. `docker/Dockerfile` is the slim
control-plane/coordinator image (**22.4 GB**, no framework venvs) and `docker/engine.Dockerfile`
builds per-engine images (CUDA-runtime base + binary + one engine's `--with cuda` venv, the
`transformers` per-engine image GPU-validated with `torch.cuda.is_available()` True under `--gpus
all`, `vllm` pinned `0.11.0`). The cluster-side wiring is implemented: generated `linux-gpu`
substrate files carry the `enginePools` / `engineMembers` graph plus derived `engineDaemons`
metadata, the coordinator routes Python-native requests to derived pool/model topics,
`infernix service --role engine --engine-name NAME` selects the matching stable member id, the chart
renders `infernix-engine-<engine>` Deployments and PDBs, and the lifecycle builds/publishes/overlays
per-engine images through Harbor. Linux native runners resolve image-baked artifacts from
`/opt/infernix/engines/<adapterId>/bin/...` after checking the repo data root, `infernix internal
materialize-linux-native-engines` writes typed manifests and smoke-validated entrypoints baked by
`docker/Dockerfile`, native exit 75 maps to `model_cache_not_populated` (reusing the Python
bootstrap retry family), and artifact-producing runners emit an `infernix-native-artifact-file:<path>`
marker the worker uploads to `infernix-demo-objects` with secret-backed MinIO credentials. The Linux
payloads are runtime-backed wrappers over image-baked `llama.cpp`, `whisper.cpp`, ONNX
Runtime/CTranslate2, Basic Pitch ONNX, faster-whisper, and Audiveris. The per-rebuild Harbor
registry/multipart scrub and native-root debugging history lives in
[cohort-validation-waves.md](cohort-validation-waves.md).
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
  Models engine→name/image mapping, substrate-neutral pool/member topic derivation, explicit
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
  routed E2E for the then-active GPU browser matrix. The same then-current source passed
  rebuilt-image `./bootstrap/linux-cpu.sh test`. Basic Pitch TensorFlow remains outside the active
  runtime catalog; MT3-PyTorch, MR-MT3, and Omnizart are maintained PyTorch music-transcription rows,
  with post-replacement MT3 proof closed by Waves O/P (2026-07-04).

---

## Sprint 4.18: Engine Artifact Manifests and Matrix Reconciliation [Done]

**Status**: Done
**Code-side closure**: Complete for the machine-independent scope — `src/Infernix/Models.hs` now reflects the researched runnable/residual matrix (Apple CTranslate2 runnable as CPU, Basic Pitch TensorFlow residual rather than runnable, Wan Apple MPS residual, Omnizart rebound to the maintained ByteDance PyTorch piano row, and MT3-PyTorch/MR-MT3 routed through `mt3-infer`), `residualMatrixRowIdsForMode` records named residual rows without promoting them into runtime catalogs, `infernix-engine-artifacts` is an explicit bucket in object layout, demo bucket repair, and chart MinIO provisioning, and the Apple manifest materializer from Sprint 1.14 supplies typed engine-artifact manifests. `src/Infernix/Engines/LinuxNative.hs` now adds the Linux image-owned materialization surface: typed manifests, smoke-validated runner roots for `llama-cpp-cli`, `whisper-cpp-cli`, `onnx-runtime-native`, `ctranslate2-native`, and `jvm-native`, a generated CLI command, a `docker/Dockerfile` bake step, and runtime-backed wrappers that parse the native worker argument shape, can emit worker-upload artifact markers, delegate to the image-baked native payload layer, and return per-family result shapes instead of failing normal invocation. `src/Infernix/Runtime/Worker.hs` now hydrates native model cache files and input-object refs from MinIO, passes non-secret model-cache hints and optional artifact output directories to native runners, uploads `infernix-native-artifact-file:<path>` outputs to `infernix-demo-objects` with worker-owned MinIO credentials, and maps native exit 75 to `model_cache_not_populated`, preserving the bootstrap retry family for future real native cache misses. At Sprint 4.18 closure, `src/Infernix/Engines/AppleSilicon.hs` also materialized deterministic Apple validation-runner payloads for `llama-cpp-cli`, `whisper-cpp-cli`, `ctranslate2-native`, `mlx-native`, `onnx-runtime-native`, and `jvm-native`; Phase 1 Sprint 1.15 now supersedes those placeholders with real Apple native runner roots, with routed proof tracked in Wave L. The shared engine-root installer now handles Docker overlay image-layer reruns by replacing a generated final root when the existing-root backup rename is rejected as a cross-device operation, while keeping rollback behavior on ordinary filesystems. The generated Linux native wrappers use `/bin/sh`; strict image smoke with `--require-native-payload` now validates the baked llama.cpp, whisper.cpp, ONNX Runtime/CTranslate2, Basic Pitch ONNX, faster-whisper, and Audiveris payload presence on the native CUDA Linux image, while unit/temp materialization keeps a non-strict portable fallback. The 2026-06-18 native CUDA Linux validation rebuilt `infernix-linux-gpu:local` with `./bootstrap/linux-gpu.sh build`, strict-smoked all five baked Linux native adapter roots with `--require-native-payload`, and passed rebuilt-image `infernix test unit` (Haskell plus PureScript 71/71). Earlier validation passed through the Linux outer-container lane with mounted live source by `cabal run exe:infernix -- internal materialize-linux-native-engines`, `cabal run exe:infernix -- test unit` (Haskell unit plus PureScript 71/71), `cabal run exe:infernix -- lint docs`, `cabal run exe:infernix -- docs check`, and `cabal run exe:infernix -- test lint`; rechecked on the Apple host with `cabal build all`, `./bootstrap/apple-silicon.sh build`, `./.build/infernix internal materialize-metal-engines`, direct validation-runner output checks, `./.build/infernix test unit`, `./bootstrap/linux-cpu.sh build`, and a fresh-container `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix internal materialize-linux-native-engines` rerun over baked `/opt/infernix/engines/<adapterId>/` roots.
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md), Stage 2 — the selected `linux-gpu` plus `linux-cpu` full-suite gates passed on 2026-06-20, so routed integration and E2E consume the runtime-backed Linux native payloads through live MinIO-backed model/input hydration. Apple headless `coreml-native` runtime-load smoke has passed, Apple transformers covers the active safetensors LLM row, and the recorded Apple full integration rerun passed on the Apple Silicon host before Sprint 1.15 real Apple native payload replacement: the source-fingerprint image freshness path rebuilt once for source changes, reused the stamped image during later edge-port validation cluster cycles, completed the active Apple catalog through the host engine daemon, and validated pinned Apple host-engine `Exclusive` duplicate rejection. Focused Apple e2e passes after preserving prompt upload refs, sending input-object refs only to object-input model families, and extending the model-bootstrap ready wait to a 900-second cold-start envelope; the latest focused pass used rebuilt image digest `sha256-ed34da86992bb1a4d285f00feb77051d12eb4fa594b7bb34ed73561a027b1a71`. The subsequent full Apple `./.build/infernix test all` aggregate passed lint, unit (Haskell plus web 71/71), integration, and 9/9 routed Playwright against rebuilt cluster image digest `sha256-f4a30f4e177206b64ce5a0d3abea8d72a8bdbe637148530e1619bdf5ce8ae7c3`, including the safetensors LLM, object-input audio/tool rows, and every active Apple catalog row. Sprint 1.15 / Wave L records green Apple real-payload integration and focused routed Playwright evidence, plus the paired `linux-cpu` full gate closed on 2026-06-29.
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

- Apple real-native-payload evidence moved to Phase 1 Sprint 1.15 / Wave L; no Phase 4 work remains
  for that Apple lane.
- Keep Basic Pitch TensorFlow and Wan Apple MPS as residual rows until compatibility spikes prove
  maintained runnable lanes.

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
`linux-cpu` validation. The supported schema emits `enginePools`, `engineMembers`, and explicit
`engineDaemons` metadata derived from that graph. Physical Apple multi-host routing is
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

None. The coordinator topic-lifecycle owner and reflected-schema command are closed; the schema is
emitted on demand by `infernix internal dhall-schema host|cluster|secrets|substrate` from the Haskell
decoder types (no `.dhall` schema is version-controlled), and `infernix lint docs` now rejects schema
drift against the in-binary renderer.

---

## Sprint 4.21: Realness by Construction and Real Linux Engines [Done]

**Status**: Done
**Code-side closure**: Complete and validated 2026-06-23 (rebuilt `linux-cpu` image:
`poetry run check-code` AST realness guard, `infernix-haskell-style` realness check, `infernix test unit`,
`infernix lint docs`): the fabrication removal, the two realness lints, and the `common.py`
empty-artifact guard. Removed so the sole `status=completed` outcome is real model output and every
missing-weights / load / engine failure raises — Python adapters (`pytorch_python`
`_validation_source_separation_archive` / `_validation_audio_generation` /
`_has_bootstrap_placeholder_payload` / `_uses_portable_bark_validation_artifact`; `diffusers_python`
`_validation_image` / `_uses_apple_validation_artifact`; the `transformers_python` `device=="cpu"` smoke
branch) and the Linux native runner (`LinuxNative.hs` ONNX basic-pitch `np.zeros`→constant-MIDI, the
Audiveris constant-MusicXML branch, the whisper.cpp/CTranslate2 failure-masks, the empty-result canned
strings, and `emit_fallback_result` / `emit_artifact_ref` + the `payload_missing` `exit 0` mask). Per the
declarative-target principle the matrix keeps each row **declared-runnable on its intended engine** (no
reclassification-to-residual); not-yet-real artifact engines honest-fail (`exit 70`) and turn green
per-row as each real engine lands. **Landed code-side 2026-06-23** (build + `infernix lint docs` / `test unit` / `test lint`): the real
Audiveris `-batch -export` OMR invocation (replacing the honest-fail), and the **weight-staging realness
guard** — `downloadUpstreamModel` (`Pulsar.hs`, the live path) and `_download_single_payload`
(`model_bootstrap.py`) now reject an HTML / non-binary response (`bodyLooksLikeHtml` / `_looks_like_html`)
so a github repo-landing-page URL fails closed (`status=failed`) instead of staging the HTML page as the
weight; this makes the broken-URL Demucs/Open-Unmix rows honest (red) rather than silently corrupt.
SDXL-Turbo already runs real on `linux-gpu` via Diffusers.

**basic-pitch → MIDI landed code-side 2026-06-23** (build + `infernix lint docs` / `test unit` /
`test lint` green): a real, no-TensorFlow `soundfile`+`scipy`+`mido`+`onnxruntime` pipeline in the
LinuxNative `onnx-runtime-native` runner — it decodes/resamples the actual input audio, windows it, runs
the baked `nmp.onnx` over the real audio (not zeros), reproduces the upstream posteriorgram→MIDI
note-creation, and writes a real `.mid` (every failure exits non-zero). Its real-MIDI output is the
cohort-gate residual.

**Demucs → real, landed code-side 2026-06-25.** The decision resolved in favor of **PyTorch + the real
first-party single-file weight** (not the unproven ONNX export). The htdemucs row's `downloadUrl` now
points at the canonical first-party checkpoint
`https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/955717e8-8726e21a.th` (a single binary `.th`
that passes the weight guard and stages as `payload`), and `_separate_sources` loads it correctly:
torch≥2.6 defaults `weights_only=True`, which rejects the demucs model classes pickled in the package, so
the adapter loads the trusted package dict with `weights_only=False` and hands it to
`demucs.states.load_model` (the prior `demucs.pretrained.get_model(dir)` failed — `get_model` cannot load
a directory). Proven end-to-end in the `infernix-linux-cpu:local` pytorch venv: `load_model(package)` →
`HTDemucs` (sources drums/bass/other/vocals), `apply_model` on CPU over a real stereo mixture in ~1.5 s →
a real ~1 MB stem ZIP (`PK` magic, one `.wav` per source). Machine-independent gates green
(`cabal build all`, `poetry run check-code` mypy/black/ruff/realness).

**Open-Unmix → real, landed code-side 2026-06-25.** It now has a dedicated `_separate_open_unmix`
adapter path (it is not a demucs checkpoint, so it no longer routes through the Demucs loader): the
`openunmix` PyTorch package is added to the pytorch engine venv (`openunmix>=1.2`, resolves to 1.3.0 via
`poetry lock`), the `audio-open-unmix` row's `downloadUrl` is the first-party Zenodo `umxhq` record
(`zenodo.org/records/3370489`), and a new multi-file bootstrap path stages the four per-target state dicts
as `<target>.pth` (Haskell `isMultiFileModelRepoUrl` routes the record to the snapshot helper; Python
`_download_open_unmix_umxhq` downloads each target). The adapter rebuilds the `umxhq` architecture
(`openunmix.umxhq(pretrained=False)`) and loads the staged state dicts with `strict=False` (mirroring
`umxhq_spec`), then runs the `Separator` over the input → stem ZIP. Proven in the `infernix-linux-cpu:local`
pytorch venv: all 4 targets load, `Separator(wav)` → real 4-stem ZIP (`PK`, ~1 MB) in ~0.1 s.
Machine-independent gates green (`cabal build all`, `poetry run check-code`).

**MT3 music-transcription replacement (2026-06-30):** the obsolete MT3 residual is removed.
The catalog now carries two real PyTorch music-transcription rows: `music-mt3-infer`
(MT3-PyTorch through `mt3-infer`) and `music-mr-mt3` (MR-MT3 through `mt3-infer`). Both rows are
runnable on `linux-cpu`, `linux-gpu`, and `apple-silicon`; Apple uses the PyTorch CPU path until an
upstream MPS path is validated. The bootstrap worker stages MT3-PyTorch as a two-file pretrained
directory (`config.json`, `mt3.pth`) and MR-MT3 as the Hugging Face `mt3.pth` payload, so the
adapter calls `mt3_infer.load_model(..., auto_download=False)` and never downloads behind the
model-cache contract.

**Audiveris OMR fix (2026-06-25):** the `tool-audiveris` JVM runner aborted at class init with
`HOME environment variable is not set` (the worker runs with a minimal environment, and Audiveris derives
its data/config folders from `HOME`). The generated `linux-native` runner now passes a writable
per-invocation `HOME` (`mktemp -d`) to just the Audiveris child — a tool-invocation requirement, not
configuration-via-env, so it is compatible with the no-env-var doctrine and the env lint.

With Demucs + Open-Unmix real and the Audiveris fixes (per-invocation
`HOME` + uncompressed `.musicxml`/`.xml` export fed a real Verovio-engraved score fixture), the
**`linux-cpu` per-model inference step is fully green on a real Kind cluster (2026-06-25)** — the then-active ten
linux-cpu rows produce real output: qwen2.5 (safetensors), tinyllama (GGUF/llama.cpp), whisper-small
(whisper.cpp), faster-whisper-ct2 (CTranslate2), demucs + open-unmix (stem ZIPs), basic-pitch-onnx (MIDI),
omnizart (ByteDance piano MIDI), bark (audio), and audiveris (OMR → MusicXML). The full
`infernix test integration` (22/22 steps) and `infernix test e2e` (9/9 specs, including the per-model
browser matrix) pass. **The `linux-gpu` lane (2026-06-26) is also green** on the rebuilt CUDA image
(RTX 5090): integration PASS over the then-active 14-row GPU catalog — the GPU-only rows (AWQ + GPTQ via vLLM,
SDXL-Turbo + Wan2.1 video via Diffusers) were already real engine code with valid HuggingFace weight URLs,
so the CPU-lane fixes carried over and the GPU lane went green on the first cluster run — plus 9/9 e2e
specs. [Wave K](cohort-validation-waves.md) is therefore **fully closed** for that then-active Linux
catalog (both Linux accelerators). The later 2026-06-30 MT3 replacement is tracked by Sprint 4.22 and
was proven by Waves O/P (2026-07-04); Wave K does not claim full-suite evidence for rows added after it ran. Wave L closed the Apple
real-engine residual on 2026-06-29 for the then-active Apple catalog; the current-catalog Apple full
16-model per-model attestation closed under Sprint 4.26 admission control + [Wave R](cohort-validation-waves.md)
(2026-07-08) with zero OS OOM-kill. Machine-independent gates (`cabal build all`,
`cabal test infernix-unit`, `infernix-haskell-style`, `infernix lint files/docs/proto/chart`,
`infernix docs check`, `poetry run check-code`) are green.
**Cohort gate**: Closed [Wave K](cohort-validation-waves.md) — `linux-gpu` + `linux-cpu` real
per-family output for the Linux catalog, with the realness lint passing.
**Implementation**: `python/adapters/{pytorch_python,diffusers_python,transformers_python,common}.py`, `src/Infernix/Engines/LinuxNative.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `python/adapters/model_bootstrap.py`, `docker/Dockerfile`
**Docs to update**: `README.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/development/python_policy.md`, `documents/engineering/model_lifecycle.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the inference engine code structurally incapable of returning a fabricated result, and deliver
real Linux inference for every Linux-catalog row.

### Deliverables

- remove every adapter/runner fabrication branch; the sole success is a real `transform()` return or a
  real native-runner artifact, with all other cases raising / exiting non-zero
- real ONNX basic-pitch over the user input; real Audiveris invocation; de-masked whisper.cpp/CT2/llama
- ONNX source separation (Demucs/Open-Unmix) and SDXL-Turbo on `linux-gpu`, fixing the broken
  github-`payload` weight staging
- `common.py` empty-artifact guard; single-file weight naming for GGUF/whisper-ggml/basic-pitch-onnx
- keep each row declared-runnable on its intended engine (declarative-target; no reclassification); not-yet-real rows fail closed until their real engine lands

### Validation

- `./bootstrap/linux-gpu.sh test` plus rebuilt `./bootstrap/linux-cpu.sh test` pass only on real
  inference for every Linux-catalog row; withholding weights/engine yields a visible `status=failed`
- the realness lint (Phase 6) blocks any reintroduced fabrication

### Remaining Work

None.

---

## Sprint 4.22: Modern Music-Transcription Models and JAX/TF Retirement [Done]

**Status**: Done — MT3 catalog replacement proven by Wave P (2026-07-04)
**Code-side closure**: Complete. The music-transcription rows are rebound to maintained PyTorch/ONNX
models on existing adapters: MT3-PyTorch and MR-MT3 run through `openmirlab/mt3-infer` on the
`pytorch-python` adapter (explicit model-cache paths, `auto_download=False`; MT3-PyTorch staged as a
two-file pretrained directory from `kunato/mt3-pytorch`, MR-MT3 as the Hugging Face `mt3.pth`),
Omnizart runs the maintained ByteDance `piano_transcription_inference` CRNN over the real input
audio, and basic-pitch uses its official ONNX runtime. The dead `jax_python` / `tensorflow_python`
adapters, their `python/engines/{jax,tensorflow}` venv projects and `pyproject.toml` scripts, and the
corresponding `Models.hs` `engineBindingForSelectedEngine` cases were **retired (deleted) 2026-06-23**
(the resolved "support all mainstream formats" decision dropped TF/JAX coverage rather than binding
new real rows). The generated catalogs include both MT3 rows on all three substrates: `linux-cpu` and
`apple-silicon` use the PyTorch CPU path (no MPS claim), `linux-gpu` uses PyTorch CUDA. The adapter
pins the upstream `transformers`/`mt3-infer` compatibility surface — bounded `transformers
>=4.46,<4.50`, the real `torch.utils.checkpoint` T5 shim, the `absl-py` dependency, and the MT3 /
MR-MT3 `T5Block.forward` `cache_position` / `past_key_value` wrappers — so both rows produce real
MIDI. The per-rebuild dependency-resolution history lives in
[cohort-validation-waves.md](cohort-validation-waves.md).
**Cohort gate**: Closed — [Wave O](cohort-validation-waves.md) proved both MT3 rows real
(`music-mt3-infer`, `music-mr-mt3`) and [Wave P](cohort-validation-waves.md) (2026-07-04) closed the
full suite: both `linux-gpu` and `linux-cpu` `infernix test all` are GREEN with routed Playwright
`9/9` including the per-model matrix and the 27 GB `video-wan21-t2v` row (unblocked by Phase 8 eager
model-cache staging). The `apple-silicon` binding runs the PyTorch CPU route; no post-replacement
Apple full-suite proof is claimed until an Apple cohort rerun records it.
**Implementation**: `src/Infernix/Models.hs`, `python/adapters/pytorch_python.py`, `python/adapters/model_bootstrap.py`, `python/engines/pytorch/pyproject.toml`, `docker/Dockerfile`
**Docs to update**: `README.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the music-transcription rows real on all substrates using modern maintained models on adapters
already supported, eliminating the JAX/ancient-TF stacks.

### Deliverables

- MT3-PyTorch and MR-MT3 → `openmirlab/mt3-infer`; Omnizart → modern PyTorch transcription;
  basic-pitch → ONNX; all on `pytorch-python` / `onnx-runtime-native`
- retire or repoint `jax_python` / `tensorflow_python`; update bindings/URLs; promote rows out of residuals
- keep the README matrix ↔ generated catalog ↔ `model_catalog.md` in parity for `infernix lint docs`

### Validation

- Code-side: `./bootstrap/linux-cpu.sh build`, `poetry --directory python run check-code`, PyTorch
  engine dependency dry-run, Linux-image `infernix lint docs`, and `cabal test infernix-unit` are
  green for the MT3 bindings.
- Cohort: rebuilt `./bootstrap/linux-cpu.sh test` and `./bootstrap/linux-gpu.sh test` both pass with
  both MT3 rows producing real MIDI output (closed by Waves O/P; the per-rebuild
  `transformers`/`mt3-infer` compatibility history is recorded in
  [cohort-validation-waves.md](cohort-validation-waves.md)).

### Remaining Work

None. Closed by [Wave P](cohort-validation-waves.md) (2026-07-04), which recorded the
`music-mt3-infer` and `music-mr-mt3` real-output proof on both Linux accelerators.

---

## Sprint 4.23: Real Input Fixtures and Fail-Closed Per-Row Tests [Done]

**Status**: Done
**Code-side closure**: Done + validated 2026-06-24 (code-side: the rebuilt `linux-cpu` image compiles
`test:infernix-integration`, and `infernix lint docs` / `test unit` / `test lint` are green). Gave Phase 4
its own real-output validation inputs so it validates self-contained on `linux-gpu` without waiting on a
later phase. Replaced the degenerate silence-WAV /
1×1-PNG inputs with real per-family fixtures shared across substrates (a real speech utterance, a real
music mixture, a real instrument phrase, a real single-staff score image), and fix the OMR input-type bug
feeding `musicXmlBuffer()` instead of a score image (`sampleInputForModel` in `test/integration/Spec.hs`,
`browserInputArtifactForModel` in `web/playwright/inference.spec.js`,
`web/test/fixtures/artifactSamples.js`). Keep the one substrate-agnostic per-row int+e2e dispatch but make
it **fail-closed on `status=failed`** (trust the result; assert only the per-family `ResultFamily`
contract plus a light object-ref existence/non-empty fetch). The Phase 0 realness lint already guarantees
the result is real or a visible failure; this sprint owns the real *inputs* that exercise the real Linux
engines. The `Engines/LinuxNative.hs` entry was added to the Phase 0 `realnessScopedFile` here (landed
2026-06-23 with the Sprint 4.21 de-stub). The fixtures are generated programmatically (a real RIFF/PCM
WAV encoder for the speech / separation / instrument-phrase inputs and a real grayscale-PNG encoder with
hand-computed Adler-32/CRC-32 for the score image — no new cabal dep), and the per-row int+e2e plus the
playwright per-model smoke now fail closed on `status=failed` with a real presigned object-ref byte fetch
(magic-bytes probed). Caveat: the speech fixture is a synthesized formant-sweep, not an intelligible
utterance — a genuinely-spoken mono 16 kHz sample should be sourced for the speech row's cohort-gate
real-output proof. Machine-independent gates gate the next step.
**Cohort gate**: Closed [Wave K](cohort-validation-waves.md) — `linux-gpu` + `linux-cpu`; the same
substrate-agnostic fixtures re-run on `apple-silicon` under [Wave L](cohort-validation-waves.md), which
closed on 2026-06-29 for the then-active pre-MT3 catalog; the current-catalog Apple full 16-model
per-model attestation closed under Sprint 4.26 admission control + [Wave R](cohort-validation-waves.md)
(2026-07-08) with zero OS OOM-kill.
**Implementation**: `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/fixtures/artifactSamples.js`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/demo_app_test_plan.md`

### Objective

Make Phase 4's real-engine validation self-contained: real per-family inputs + fail-closed per-row int/e2e
that exercise the real Linux engines, so no Phase-4 validation is blocked by a later phase.

### Deliverables

- real per-family input fixtures shared across substrates; OMR input-type fix
- fail-closed per-row int+e2e (trust the result, fail on `status=failed`, assert the per-family contract)

### Validation

- `./bootstrap/linux-gpu.sh test` plus rebuilt `./bootstrap/linux-cpu.sh test` per-row suites fail when a
  Linux engine is withheld or returns a non-real result

### Remaining Work

None.

---

## Sprint 4.24: Pulsar Result Timestamp Canonicalization [Done]

**Status**: Done
**Code-side closure**: Complete on 2026-06-29. `src/Infernix.Storage` exports the shared
`formatTimestamp` / `parseTimestamp` ISO-8601 helpers, `src/Infernix.Runtime.Pulsar` uses them for
result-topic protobuf serialization and parsing, and malformed result-proto `createdAt` values now fail
as `Nothing` instead of process exceptions. Unit coverage proves canonical wire timestamps,
roundtrips through the shared parser, and malformed-input failure.
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

- `cabal test infernix-unit --test-options='--hide-successes'` — passed 2026-06-29
- `cabal build test:infernix-integration` — passed 2026-06-29
- `cabal run exe:infernix -- lint docs` — passed 2026-06-29

### Remaining Work

None.

---

## Sprint 4.25: Matrix Substrate-Accuracy Closure [Done]

**Status**: Done — code-side complete and machine-independent-validated; Wave R proved the Apple routed per-model matrix, and Wave S proved the current `linux-cpu` and `linux-gpu` full-suite lanes against the honest supported matrix cells.
**Code-side closure**: Complete (2026-07-08). Row 11 relabeled to the honest `ONNX Runtime (CPU)` on the `linux-gpu` lane (`Models.hs` ModeBinding + README cell in lockstep, `requiresGpu` flipped to `False` so the row is no longer GPU-scheduled — the runner runs `CPUExecutionProvider` with the CPU `onnxruntime` wheel); rows 4/6 keep their `llama.cpp` / `whisper.cpp` cells and the README notes now document that the CUDA column runs the CPU Ubuntu binary today; row 14 (`music-omnizart` / `piano_transcription`) `Models.hs` note reconciled to "binding landed and wired" and proven by Wave R/Wave S; row 17 (Wan2.1-T2V) kept as the documented Apple residual with union coverage named; the Linux basic-pitch onset divide-by-zero guard was ported from the Apple runner (`LinuxNative.hs`); the Apple native smoke now fails closed (raises `RunnerFailure`) when run off the engine venv or when the engine runtime cannot import (`apple_native_runner.py`). Proven by `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint docs`, and `poetry --directory python run check-code` on this Apple host.
**Cohort gate**: Closed by [Wave R](cohort-validation-waves.md) and [Wave S](cohort-validation-waves.md) — Apple routed Playwright proved the affected rows on 2026-07-08, and rebuilt `linux-cpu` / `linux-gpu` full-suite `./bootstrap/* test` lanes proved the current supported matrix cells on 2026-07-09.
**Implementation**: `src/Infernix/Engines/LinuxNative.hs`, `python/native-runners/apple_native_runner.py`, `src/Infernix/Models.hs`, `README.md`
**Docs to update**: `README.md` (matrix Notes), `documents/architecture/model_catalog.md`

### Objective

Make every matrix cell accurate for the substrate its README column advertises, and close two
substrate-divergence defects surfaced by the 2026-07-06 review.

### Deliverables

- Row 11 (basic-pitch ONNX) CUDA lane: **relabeled** the README cell `ONNX Runtime (CPU)` and the
  matching `Models.hs` ModeBinding (`requiresGpu = False`), because `LinuxNative.hs` runs
  `CPUExecutionProvider` and only the CPU `onnxruntime` wheel is installed. The supported cell is
  therefore the CPU ONNX Runtime path and is proven by Wave S.
- Rows 4/6 (llama.cpp GGUF, whisper.cpp speech) CUDA lane: **documented** that the CUDA column runs the
  CPU Ubuntu-release binaries today (README Notes); those supported cells are proven by Wave S.
- Row 14 (`piano_transcription`): corrected the stale `Models.hs` "test is red until the adapter binding
  lands" note — the binding is landed (`pytorch_python.py`) and the cohort real-output evidence is
  closed by Wave R/Wave S.
- Row 17 (Wan2.1-T2V) Apple: kept as the documented Apple residual
  (`residualMatrixRowIdsForMode AppleSilicon`), with the union-coverage invariant satisfied by the real
  CUDA cell and stated in the README Note.
- Substrate-divergence guards: **added** the divide-by-zero guard to the Linux basic-pitch onset path
  that the Apple runner already has; the Apple smoke now fails closed when the engine runtime does not
  import.

### Validation

- Code-side: `cabal build all`, `infernix lint docs`, and the Python `check-code` AST/realness gate — all green (2026-07-08).
- Cohort: Apple routed Playwright is green in [Wave R](cohort-validation-waves.md) (2026-07-08), and the rebuilt `linux-cpu` + `linux-gpu` full suites are green in [Wave S](cohort-validation-waves.md) (2026-07-09).

### Remaining Work

None.

---

## Sprint 4.26: Apple-Silicon Inference RAM Admission and Bounded Peak (Fail-Clean, Never OOM) [Done]

**Status**: Done — code-side complete and machine-independent-validated; the Apple integration and routed per-model matrix are GREEN ([Wave R](cohort-validation-waves.md), 2026-07-08), and the rebuilt `linux-cpu` full-suite rerun is GREEN ([Wave S](cohort-validation-waves.md), 2026-07-09).
**Supersession note**: Sprint 4.27 keeps the serialized runtime-admission idea but supersedes this
sprint's catalog-wide fail-fast, integer sentinel/floor, Apple-only budget scope, and stringly result
payload.
**Code-side closure**: Complete (2026-07-08). `ModelDescriptor` gained `modelRamFootprintMib` threaded through every mirror (hand-written JSON codec in `Types.hs`, the Dhall decoder/renderer/type in `Substrate.hs`, and the purescript-bridge `ModelDescriptor` + generated `Contracts.purs`); `Models.conservativeRamFootprintMibForRow` assigns conservative per-family/per-engine footprints (biased high) until a measured peak-RSS pass. `DemoConfig` gained `inferenceRamBudgetMib`, resolved at materialization time by `DemoConfig.resolveInferenceRamBudgetMib`: on `apple-silicon` it is host physical RAM (`sysctl -n hw.memsize`, via the new manifest-owned `HostSysctl` tool) − the colima VM pledge (a **read-only** `colima list --json` probe resolved through a bootstrap-adjacent fixed candidate path — `HostTools.readHostToolFallback`; colima is read, never managed, and is deliberately **not** a manifest-owned tool, so the Linux launcher manifest carries no colima field) − a host reserve; on Linux it records the engine pod memory limit. `validateDemoConfig` adds an `apple-silicon`-scoped config-time hard-fail naming any over-budget model, its footprint, and the budget. The serialized engine-execution critical section in `Runtime/Pulsar.hs` (already single-inference-at-a-time under `engineExecutionLock`) now runs `overRamBudgetRejection` before launching a subprocess: an over-budget model publishes a clean `status=failed` instead of being launched. Proven by `cabal build all`, `cabal test infernix-unit` (with the new `validateDemoConfig` reject/accept assertions), `cabal test infernix-haskell-style`, `infernix lint files|docs|chart|proto`, `infernix docs check`, the web unit suite (`71/71`), and `poetry --directory python run check-code`. On this host the resolver computes a real budget of 13312 MiB (64 GiB − 48 GiB colima − 3 GiB reserve), which the whole apple catalog fits.
**Cohort gate**: Closed by [Wave R](cohort-validation-waves.md) apple-silicon and [Wave S](cohort-validation-waves.md) Linux — **GREEN**: a full host-native `cluster up` (edge `127.0.0.1:9090`, published `inferenceRamBudgetMib = +13312`) then `./.build/infernix test integration` drove all 16 apple catalog models to `status=completed` with **zero** OS OOM-kill, including the heavy diffusion rows; routed Apple Playwright then exercised the per-model matrix. The 2026-07-09 `linux-cpu` full suite passed in Kubernetes-bounded engine pods, where host-RAM admission is a no-op by design. The Apple cohort run also surfaced and fixed the Dockerfile stage-zero host-manifest schema drift (the hand-written `/opt/infernix/dhall/InfernixHost.dhall` now emits the new `sysctl` tool path and keeps colima out of the manifest).
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

### Validation

- Unit: `validateDemoConfig` rejects an over-budget config and accepts an in-budget one — **green**
  (`cabal test infernix-unit`, `cabal test infernix-haskell-style`, 2026-07-08).
- Cohort (apple-silicon, paired with Phase 6 Sprint 6.37): **GREEN ([Wave R](cohort-validation-waves.md), 2026-07-08)** —
  a full 16-model per-model `test integration` completed with all `status=completed` and **zero** OS
  OOM-kill on this Apple host.
- Linux CPU: **GREEN ([Wave S](cohort-validation-waves.md), 2026-07-09)** — rebuilt image
  `sha256:cfcd0c617a70919a1d083b43dfa66e9041b215a27a176ab82c2d806a36cf7627` passed the full
  `./bootstrap/linux-cpu.sh test` suite.

### Remaining Work

None. The retired unbounded on-host inference path is recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

---

## Sprint 4.27: Typed Resource Memory Admission and Inference Errors [Done]

**Status**: Done — code-side complete and Wave T closed on `linux-cpu` plus the selected `linux-gpu`
accelerator.
**Code-side closure**: Complete on 2026-07-09 in the Linux outer-container lane. `DemoConfig`
now carries typed `InferenceMemoryBudget` instead of an integer RAM budget; `Types.hs` owns
`InferenceMemoryResource`, `InferenceMemoryBudget`, `InferenceError`, and pure
`admitModelMemory`; `validateDemoConfig` accepts mixed catalogs instead of failing daemon startup
for one oversized row; Apple resolves enforced unified-host-RAM budgets without a hardcoded floor,
Linux CPU resolves pod RAM, and Linux GPU resolves GPU VRAM; `ResultPayload`, protobuf, storage,
Pulsar conversion, the result bridge, browser contracts, and CLI printing carry typed
`ModelMemoryLimitExceeded` rather than successful inline-output text. Validated by
`./bootstrap/linux-cpu.sh build`, `docker compose --project-name infernix-linux-cpu --file
compose.yaml run --rm infernix infernix test lint`, `docker compose --project-name
infernix-linux-cpu --file compose.yaml run --rm infernix infernix test unit` (Haskell unit plus web
`73/73`), `infernix lint files|docs|proto|chart`, `infernix docs check`, and a source-bound
`cabal build test:infernix-integration` compile preflight.
**Cohort gate**: Closed [Wave T](cohort-validation-waves.md) — full `linux-cpu` integration/e2e
evidence and selected `linux-gpu` full-suite evidence are recorded on 2026-07-12.
**Latest Wave T evidence**: The 2026-07-10 `linux-cpu` full-suite rerun on rebuilt image
`sha256:05e0aadf5ea0feb98f25e82ab196f23893be0441e59f5e91f9fec346bfa6d8c0` passed the full live
integration lane and proved runtime admission emits typed `ModelMemoryLimitExceeded` for each
over-budget CPU row without stopping smaller-model execution. The cohort gate remained open after this attempt because
the routed browser phase still failed before closure, including the visible capacity-message check
for one typed over-budget matrix row. Rebuilt image
`sha256:c01a9a070ca842b973543301dcbaaa039811492f707fdc20c804aa30bd5f40ee` now passes
`./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web `76/76`; its full
`./bootstrap/linux-cpu.sh test` rerun passed the full live integration lane again, including typed
admission and smaller-model continuity. The cohort gate remained open after this attempt because routed Playwright ended
`15/16` on the browser-visible capacity-message race; current source fixes the stale-displayed-context
append path and focused mounted-source PureScript validation passes `77/77`. Rebuilt image
`sha256:84e3915260e5fd7684b817bf520e9eaca4f40946665d86ae2afb5276b1eedfcb` then passed the live
integration path through typed admission, smaller-model continuity, HA/chaos, throughput, platform
recovery, lifecycle rebinding, and anti-affinity before failing a later lifecycle cluster-up on the
one-shot retained Pulsar repair limit. Current source bounded that repair loop, and rebuilt image
`sha256:0bf82aba452b2bee8f5de6c4ee136c7d72537ac0dbd4377ee52ee3718d77c0aa` passed the full live
integration lane, including repeated retained-data cluster-ups without the dirty-metadata failure;
routed Playwright reached `15/16` and failed only the visible capacity-message matrix assertion.
Current source adds a same-rendered-context reducer guard plus raw Haskell-wire decode regression,
with focused mounted-source PureScript validation at `79/79`. Rebuilt image
`sha256:4e2e2a9f642ecc15635df849539b82a847d350db19e161cf6517d56a29ea6b62`
contains that fix and passed `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` with web `79/79`. Its full `linux-cpu` rerun passed the live
integration lane again, including typed admission, smaller-model continuity, throughput
(`totalPrompts = 12`, `p95Seconds = 65.4941475391388`), platform recovery, lifecycle rebinding,
anti-affinity, and the `demo_ui = false` lifecycle; routed Playwright reached `15/16` and failed
only the visible capacity-message matrix assertion. Rebuilt image
`sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306`
now contains the submitted-prompt pinning fix, passed `./bootstrap/linux-cpu.sh build` plus the
CLI-help smoke, and passed rebuilt-image `infernix test unit` with web `80/80`. Its full
`linux-cpu` rerun passed Haskell style, Python `check-code`, Haskell unit, web `80/80`, and the
full live integration lane, including typed CPU admission, smaller-model continuity, platform
recovery, lifecycle rebinding, anti-affinity, and the `demo_ui = false` lifecycle; routed Playwright
reached `15/16` and failed only the visible capacity-message DOM assertion after receiving the
typed terminal payload. Current source now keeps a per-context browser conversation cache so
inactive or transiently stale terminal patches are retained without displacing the rendered pane;
focused mounted-source PureScript validation passes `81/81`. Rebuilt Linux CPU image
`sha256:5ccdac2c89b435c1452f63c7fc5df41ca07893bfabc581134aef95db0468ace9` contains that fix and
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image `infernix test
unit` with web `81/81`. Its full rerun reached PostgreSQL lifecycle rebinding after typed
admission, HA, throughput, and platform-recovery checks, then hung inside the second `cluster up`
warm-cache path with an idle MinIO NodePort connection. Current source bounds the MinIO
warm-cache/model-bootstrap HTTP calls in `Infernix.Runtime.Pulsar` (`HEAD` sentinel probes 15s,
write responses 300s), and focused mounted-source Haskell validation passes
`cabal test infernix-unit`. Rebuilt Linux CPU image
`sha256:f0276a2efcae1fa7b2d33a7bb7a0e442b9d4c2be5687515c439f9cb75bf909ec` contains the timeout fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `81/81`. Its full `linux-cpu` rerun failed before runtime validation
on a Haskell style import-order diff in `Infernix.Runtime.Pulsar`; current source applies the
style-only reorder, and focused mounted-source validation passes `cabal test infernix-haskell-style`.
Rebuilt Linux CPU image
`sha256:5d423bd3d988103e6777fcfa80b92da07684263af056f7e6c9395e4802176cec` contains that style fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `81/81`. Its full rerun passed the front gates and progressed through
typed CPU admission, HA/recovery, model-bootstrap deduplication, throughput (`totalPrompts = 12`,
`p95Seconds = 65.50490140914917`), Harbor/MinIO/Pulsar recovery, and PostgreSQL failover before
stalling in the lifecycle-rebinding second `cluster up` while republishing Harbor images;
diagnostics showed the integration process sleeping with a direct `[docker] <defunct>` child.
Current source replaces the monitored subprocess waiter in `Infernix.ProcessMonitor` with a
blocking reaper plus heartbeat loop; focused mounted-source validation passes
`cabal test infernix-haskell-style` and `cabal test infernix-unit`. Rebuilt Linux CPU image
`sha256:ab2f12cd81a094ffc267eacfb637ae055c8b3c8cd31e364dfc2f54cbcdf21597` contains the monitor fix
and passes `./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web
`81/81`. Its full `linux-cpu` rerun validated the monitor fix by advancing past the previous
lifecycle-rebinding publish stall, then failed in the model-bootstrap failover/deduplication
integration step after timing out on the ready topic for
`integration-bootstrap-chaos-1783761854482798`. Current source carries the bootstrap-failover
remediation: exact bootstrap request replays remain publishable across uncertain coordinator
failover, ready-event deduplication is scoped to the request attempt, and bootstrap
credential-load failures nack rather than acking a no-ready path; focused mounted-source
`cabal test infernix-haskell-style` and `cabal test infernix-unit` pass. Rebuilt Linux CPU image
`sha256:534f631468380d9e59df713e4e8c78b976e17b17e0c64eb09be4eff8d6f41388` contains the remediation
and passes `./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web
`81/81`. Its full `linux-cpu` rerun passed the front gates, full live integration, the previous
model-bootstrap failover/deduplication gate, lifecycle rebinding, anti-affinity, and the
`demo_ui = false` lifecycle; routed Playwright passed `15/16` and failed only the browser matrix
visible capacity-result assertion after receiving the typed terminal `ModelMemoryLimitExceeded`
payload. Current source projects the rendered chat pane from the active context id plus the
per-context conversation cache so a stored terminal result for the selected context cannot be hidden
behind a stale `activeConversation` pane. Focused mounted-source PureScript validation passes
`82/82`, and `node --check web/playwright/inference.spec.js` passes. Rebuilt Linux CPU image
`sha256:e09f824b06b489a574288dbafcf1c8cc5920ae0bcb1a96cea91306a6cd57221c` contains that
render-projection fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun
passed the front gates and full live integration, including typed CPU admission, throughput
(`totalPrompts = 12`, `p95Seconds = 86.15112495422363`), lifecycle rebinding, anti-affinity, and
the `demo_ui = false` lifecycle; routed Playwright reached `15/16` and failed only the
`audio-demucs-htdemucs` visible capacity-result assertion after proving the target context was
active. Current source hardens stale WebSocket generation handling and subscription readiness.
Focused mounted-source validation passes `cabal test infernix-haskell-style infernix-unit` with
`src/Infernix/Demo/WebSocket.hs` mounted, web unit `82/82`, and
`node --check web/playwright/inference.spec.js`. Rebuilt Linux CPU image
`sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d` contains this fix and
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front
gates and full live integration, including typed CPU admission for the six over-budget rows,
model-bootstrap failover/deduplication, throughput (`totalPrompts = 12`, `p95Seconds =
65.46250057220459`), lifecycle rebinding, anti-affinity, and `demo_ui = false`; routed Playwright
reached `15/16` and failed only the `audio-demucs-htdemucs` visible capacity-result assertion after
observing and validating the typed terminal payload. Current source gives browser-facing Pulsar
readers unique per-stream names and tags Playwright-observed WebSocket frames by browser socket
generation, so the matrix waits for live-generation snapshots and terminal patches instead of
accepting frames from superseded sockets. `node --check web/playwright/inference.spec.js` passes for
that helper change, `git diff --check` is clean for the touched files, and mounted-source Haskell
validation passes `cabal test infernix-haskell-style infernix-unit` with
`src/Infernix/Runtime/Pulsar.hs` mounted into the Linux CPU launcher image. Rebuilt Linux CPU image
`sha256:eeb58064f9eca14c008b9c976380c5c7745a4c6079a5bd8885b3935c864532a5`
(`20070858505` bytes, created `2026-07-11T14:49:26.455414736-04:00`) contains the unique
browser-facing Pulsar reader names and Playwright socket-generation filtering change and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, including typed Linux CPU admission for all six over-budget rows with
`availableMib = 4096`, smaller-model continuity, throughput (`totalPrompts = 12`,
`p95Seconds = 65.51375341415405`), lifecycle rebinding, anti-affinity, and `demo_ui = false`.
Routed Playwright reached `14/16` and failed on the artifact download-button replacement race plus
the remaining `audio-demucs-htdemucs` visible capacity-result assertion after typed terminal-payload
validation. Current source fixes the routed browser harness by waiting for upload-record echo before
artifact downloads, retrying against a re-resolved artifact card until the webapp-proxy download
grant is ready, and waiting for the exact typed capacity text with a resubscription fallback.
`node --check web/playwright/inference.spec.js` and `git diff --check` pass for the touched files.
Rebuilt Linux CPU image
`sha256:d49b4799375df7a0e5726d16717ab6dc4e09fc8baa685969484099027f81c4c8`
(`20070886873` bytes, created `2026-07-11T17:27:02.378037428-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, including typed Linux CPU admission for all six over-budget rows with
`availableMib = 4096`, smaller-model continuity, throughput (`totalPrompts = 12`,
`p95Seconds = 69.06893110275269`), lifecycle rebinding, anti-affinity, and `demo_ui = false`.
Routed Playwright reached `15/16`: artifact upload/preview/download coverage passed, but the
browser matrix still failed the `audio-demucs-htdemucs` visible capacity-result assertion after
resubscription. The next Wave T gate is the capacity-result render fix and a clean full
`linux-cpu` rerun. Current source now correlates the matrix terminal result to the exact submitted
prompt's server conversation message id before asserting the typed capacity payload; focused
`node --check web/playwright/inference.spec.js` and `git diff --check` pass for that follow-up.
Rebuilt Linux CPU image
`sha256:30d597efe4284a74c606860d7a0ef6d4fd5123076de11ad0c8e3da476925190e`
(`20070997197` bytes, created `2026-07-11T20:08:36.089424841-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration (`totalPrompts = 12`, `p95Seconds = 65.60747718811035`) with the known
`music-omnizart` warm-cache HTTP 403 warning, then routed Playwright reached `15/16`: Sprint 9.9
auth/RBAC/logout switching and artifact coverage were green, but the matrix still failed the
`audio-demucs-htdemucs` visible capacity-result assertion after resubscription. Current source
strengthens that fallback to require a new-socket conversation snapshot or patch containing the
matching typed capacity result before asserting the DOM; `node --check web/playwright/inference.spec.js`
and `git diff --check` pass. Rebuilt Linux CPU image
`sha256:681420399273889da1e64ce6e43576ffe8a06ad87114b8e069903ab79d3d92f9`
(`20070973633` bytes, created `2026-07-11T22:49:09.072629435-04:00`) contains that
fallback and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). The next validation gate is a clean full
`linux-cpu` rerun on this image, then the selected `linux-gpu` accelerator gate. The full rerun on
that image passed the front gates and live integration (`totalPrompts = 12`, `p95Seconds =
70.42682695388794`) with the known `music-omnizart` warm-cache warning, then routed Playwright
reached `15/16`: Sprint 9.9 auth/RBAC/logout switching and artifact coverage were green, but the
matrix still failed the `audio-demucs-htdemucs` visible capacity-result assertion even after a
result-bearing resubscription attempt.

Rebuilt Linux CPU image
`sha256:c911771090115baa928d6bf43f14ef804cfcdc8706bc96ab3fe6b62f48a19a6f`
(`20088000300` bytes, created `2026-07-12T02:30:27.200982353-04:00`) contains the explicit tagged
`InferenceError` WebSocket contract fix. It passed `./bootstrap/linux-cpu.sh build`, the CLI-help
smoke, rebuilt-image `infernix test unit` (Haskell unit plus web `83/83`), and rebuilt-image
`infernix test e2e`. The live integration portion again proved typed Linux CPU admission and
smaller-model continuity; routed Playwright passed `16/16` in 3.6 minutes, including the per-model
browser matrix in 2.5 minutes, Sprint 9.9 auth/RBAC/logout/account-switching, and artifact
coverage. This closes Sprint 4.27's Wave T `linux-cpu` evidence.

Selected accelerator closure followed on rebuilt `linux-gpu` image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896`
(`6306647890` bytes, created `2026-07-12T03:52:10.703037529-04:00`). `./bootstrap/linux-gpu.sh test`
passed Haskell style, Python checks, Haskell unit, web `83/83`, full live integration, HA/recovery,
and routed Playwright `16/16` in 17.1 minutes. The run published/pulled the control-plane image and
per-engine images (vLLM
`sha256:a104965a23de389f8da6a86da9fe20c15fdf20c8cfb0c2c85c245d601bdae6f4`, PyTorch
`sha256:c00fa185f82644efa9270e528a4f5b82b02746160709dbea6365b29393432769`, Diffusers
`sha256:a4a5064a2937a155ef881bc9410cb3c2340cec2d8a32fca598a5016cfe0d6fd0`) through Harbor. The
integration and browser matrix proved typed GPU VRAM admission (`availableMib = 4096`) for the
over-budget rows while smaller rows continued. Warm-cache warnings stayed non-blocking: Omnizart
failed its upstream Zenodo download with HTTP 403, and the remaining large rows used the documented
lazy fallback path. This closes Sprint 4.27's selected `linux-gpu` evidence and Wave T.
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
primitives, and a real native-runner environment) is code-side closed (machine-independent gates) plus
the single-accelerator (apple-silicon) plus linux-cpu full-suite sign-off closed by
[Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-16 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style` (realness lint clean on the touched
`Engines/AppleSilicon.hs`), `infernix lint docs`, and `poetry run check-code` (`native-runners`
realness guard + `adapters` black/ruff/mypy) all green on the apple-silicon lane.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
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

- the readiness-sentinel commit is gated on a `PayloadVerified` witness minted by a real bounded
  probe, closing the unconditional package-backed `.ready` path
- `awaitModelBootstrapReady` returns typed evidence rather than a bare success signal
- the raw commit and spawn primitives are capability-gated so callers cannot invoke them without the
  corresponding evidence
- native runners receive a real environment carrying `HOME` and `TMPDIR`

### Validation

- the code-side gate set (`cabal build all`, `cabal test infernix-unit`,
  `cabal test infernix-haskell-style`, `infernix lint docs`, and `poetry run check-code` for the
  native-runner change) is exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

- code-side closed 2026-07-16. Landed this sprint (in `src/Infernix/Runtime/Pulsar.hs`,
  `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Engines/AppleSilicon.hs`,
  `python/native-runners/apple_native_runner.py`):
  - the `.ready` sentinel commit is capability-gated on a `PayloadVerified` witness. The opaque
    witness (constructor unexported) is minted only by a real bounded MinIO HEAD probe
    (`verifyUploadedPayload`) for downloaded payloads or the package-backed recognition probe
    (`packageBackedPayloadVerified`); `commitReadySentinel` requires it, closing the previously
    unconditional package-backed sentinel write
  - `awaitModelBootstrapReady` returns typed `ModelBootstrapReady` evidence minted from a real
    matching ready event; `waitForModelBootstrapReady` is now the derived boolean wrapper
  - native runners receive a real environment carrying `HOME`/`TMPDIR`: `workerProcessEnvironment`
    is built from the typed `Infernix.Cluster.Subprocess.SubprocessEnv` (the previous empty
    `env = Just []`); the Apple setup spawn routes through the same typed env; the Apple payload
    smoke and the Python native-runner child spawns (`_native_runner_child_env`) carry `HOME`/`TMPDIR`
- validated with `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint files/docs/proto/chart`, and `poetry run check-code`. Apple cohort validation
  (2026-07-18) additionally caught that the `_native_runner_child_env` docstring contained the literal
  `os.environ`, which the `infernix lint files` text scanner rejects; the docstring was reworded to
  "the process environment" (the helper itself never reads it). The native-runner `HOME`/`TMPDIR`
  change is proven live: real Apple inference on the native-engine models (`llm-tinyllama-gguf`
  llama.cpp, `llm-qwen15-mlx` MLX, `speech-whisper-small` whisper.cpp, `speech-faster-whisper-ct2`
  CTranslate2) completes end-to-end
- the cohort full-suite sign-off closed under [Wave V](cohort-validation-waves.md) (2026-07-20):
  apple-silicon plus linux-cpu full-suite proof of the bounded-probe witness and native-runner
  environment against live MinIO is complete, and no remaining work exists

---

## Sprint 4.29: Classified Model Download & Integrity-Witnessed Sentinel [Done]

**Status**: Done — the Bounded-Command Application & Bounded-HTTP reopen (the UA-bearing,
`Retry-After`-honoring classified `DownloadOutcome` download fold and the integrity-witnessed
`PayloadVerified` sentinel) is code-side closed (machine-independent gates) plus the single-accelerator
(apple-silicon) plus linux-cpu full-suite sign-off closed by [Wave V](cohort-validation-waves.md) on
2026-07-20.
**Code-side closure**: closed 2026-07-19 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit` (the `classifyDownloadStatus` classification assertions pass),
`cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, and
`infernix docs check` all green on the apple-silicon lane. No Python/native change in this sprint, so
`poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`
**Blocked by**: Sprint 1.17, 4.28
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
`documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, and the phase's
existing engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — consume the
Sprint 1.17 bounded-HTTP download kernel at the coordinator model-bootstrap site the 2026-07-18 cohort
run hit (a rate-limited 403 on `music-omnizart`), and make the `.ready` sentinel witness integrity,
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
  [Wave V](cohort-validation-waves.md) (2026-07-20)

### Remaining Work

- the cohort full-suite sign-off closed under [Wave V](cohort-validation-waves.md) (2026-07-20):
  apple-silicon plus linux-cpu full-suite validation of the classified download fold and the
  integrity-witnessed sentinel against a live upstream and MinIO is complete, and no remaining work
  exists

---

## Sprint 4.30: Memory-Grant Admission and Capped-Engine Kernel [Done]

**Status**: Done — the grant-gated capped-engine kernel is the foundation half of the
memory-safety-by-construction reopen; it is code-side closed 2026-07-21 on the machine-independent gate
set, and the single-accelerator (apple-silicon) plus `linux-cpu` behavioral cohort sign-off closed under
[Wave W](cohort-validation-waves.md) on 2026-07-24 with no remaining work.
**Supersession note**: this sprint supersedes Sprint 4.27's proof-free
`admitModelMemory :: InferenceMemoryBudget -> ModelDescriptor -> Maybe InferenceError` (a `Nothing`
carries no evidence that admission ran) with an `Either InferenceError MemoryGrant` that mints a typed
grant, and supersedes the raw unbounded engine spawn from Sprint 4.28
(`readCreateProcessWithExitCode` / `createProcess` in `runNativeWorker` / `runWorkerInvocation`) with a
capped-engine kernel that consumes the grant and bounds actual resident memory to the admitted ceiling.
**Code-side closure**: complete (2026-07-21). Landed: `admitModelMemory` returns
`Either InferenceError MemoryGrant`, where `MemoryGrant` is an opaque newtype (constructor unexported in
`src/Infernix/Types.hs`) carrying the admitted `MemoryCeiling`, minted only on a successful admission
decision; the new capped-engine kernel `Infernix.Runtime.CappedEngine` is the only path that spawns an
inference subprocess (`withCappedEngine :: MemoryGrant -> CreateProcess -> (forall s. EngineHandle s ->
IO r) -> IO r`, rank-2, `bracket` teardown) and requires a `MemoryGrant`, and it does not re-export the
raw `createProcess` / `waitForProcess` primitives, so spawning an engine without admission does not
typecheck; macOS enforces the ceiling with a parent-side `proc_pid_rusage` physical-footprint watchdog
(a Haskell FFI thread that samples the child and SIGKILLs its process group on breach — no
`apple_native_runner.py` change was needed), and Linux classifies the pod-cgroup / VRAM OOM exit; an
over-budget model is a clean `status=failed` `ModelMemoryLimitExceeded`, and a runtime ceiling breach is
rebuilt into the same typed terminal failure (`Infernix.Runtime.runAdmittedInference`), never a host
OOM. The raw engine spawns in `runNativeWorker` / `runWorkerInvocation` now route through the kernel
(`runCappedProcess` / `runCappedStdioEngine`). Gate set (GREEN 2026-07-21): `cabal build all`
(`-Wall -Werror`), `cabal test infernix-unit` (grant-mint / partition / footprint assertions),
`cabal test infernix-haskell-style` (incl. the Sprint 6.42 `unboundedEngineSpawnViolations` lint,
negative-tested), `infernix lint files/docs/proto/chart`, `infernix docs check`, and
`poetry run check-code`.
**Cohort gate**: apple-silicon + linux-cpu, [Wave W](cohort-validation-waves.md) — the behavioral proof
that a full-suite `infernix test all` drives an over-capacity catalog with zero host OOM and every
over-budget row cleanly typed-rejected as `ModelMemoryLimitExceeded`. Closed 2026-07-24.
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
- macOS ceiling enforcement: a `proc_pid_rusage` physical-footprint watchdog that SIGKILLs the engine
  process group when the resident footprint breaches the admitted `MemoryCeiling`
- Linux ceiling enforcement: classification of the pod-cgroup / VRAM OOM exit into a typed
  `ModelMemoryLimitExceeded` rather than an opaque non-zero exit
- the raw `readCreateProcessWithExitCode` / `createProcess` engine spawns in `runNativeWorker` /
  `runWorkerInvocation` retired in favor of the grant-gated kernel

### Validation

Gates (closed under [Wave W](cohort-validation-waves.md), 2026-07-24):

- `cabal build all` (`-Wall -Werror`) compiles the grant-gated kernel with the raw engine-spawn path
  removed
- `cabal test infernix-unit` covers grant mint on in-budget admission, `Left ModelMemoryLimitExceeded`
  on over-budget admission, and ceiling-breach classification for both the macOS watchdog and the Linux
  OOM-exit paths
- `cabal test infernix-haskell-style` passes, including the Phase 6 Sprint 6.42
  `unboundedEngineSpawnViolations` lint that keeps new engine-spawn call sites off the raw primitives
- `infernix test all` on apple-silicon plus linux-cpu proves no host OOM under a full over-capacity
  catalog, with every over-budget row cleanly typed-rejected — closed under
  [Wave W](cohort-validation-waves.md)

### Remaining Work

None. The implementation is complete (code-side closed 2026-07-21): `admitModelMemory` mints an
`Either InferenceError MemoryGrant`, the `MemoryGrant`/`MemoryCeiling` opaque newtypes and the
capped-engine kernel `Infernix.Runtime.CappedEngine` (`withCappedEngine`, the `proc_pid_rusage`
watchdog, the Linux OOM-exit classifier) are landed, the raw engine spawns are retired from
`runNativeWorker` / `runWorkerInvocation`, and unit coverage asserts grant mint on in-budget admission
and typed rejection on over-budget. The apple-silicon plus linux-cpu behavioral cohort sign-off closed
under [Wave W](cohort-validation-waves.md) on 2026-07-24 (a full-suite `infernix test all` completes an
over-capacity catalog with zero host OOM and every over-budget row cleanly typed-rejected); no remaining
work exists. The superseded proof-free admission and raw engine spawns are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

---

## Sprint 4.31: Host Memory Partition, Required Footprint, and Budget-Enforcer Split [Done]

**Status**: Done — the checked host partition, the required footprint newtype, and the
budget-that-names-its-enforcer split are the model half of the memory-safety-by-construction reopen;
implemented on top of Sprint 4.30 and code-side closed 2026-07-21 on the machine-independent gate set,
and the single-accelerator (apple-silicon) plus `linux-cpu` behavioral cohort sign-off closed under
[Wave W](cohort-validation-waves.md) on 2026-07-24 with no remaining work.
**Supersession note**: this sprint supersedes Sprint 4.26's bare-`Int` `modelRamFootprintMib` (a
default-0 footprint silently disables admission) with a required `ModelMemoryFootprint` newtype (no
bare-`Int`, no default-0); supersedes the hard-coded `appleHostReserveMib = 3072` reserve in
`resolveAppleInferenceRamBudgetMib` with a checked `HostMemoryPartition` (physical = vmReserve +
hostHeadroom + inferenceCapacity, rejecting oversubscription, headroom covering OS + routed-E2E
browser); and supersedes Sprint 4.27's `UnenforcedMemoryBudget` arm — "a budget enforced by nobody" is
no longer representable — with a budget that names its enforcer
(`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit`).
**Code-side closure**: complete (2026-07-21). Landed: `InferenceMemoryBudget` is now
`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit` (`UnenforcedMemoryBudget`
dropped); `ModelDescriptor.modelRamFootprintMib :: Int` is now a required `ModelMemoryFootprint` newtype
`modelRamFootprint` threaded through every mirror (hand-written JSON codec, Dhall
decoder/renderer/type, and the browser contract projection — the wire field stays `modelRamFootprintMib :
Integer` but decode fails closed on absent/non-positive); the Apple budget resolves a checked
`HostMemoryPartition` where physical RAM = vmReserve (colima pledge) + hostHeadroom (`minHostHeadroomMib`
= 6144 MiB, covering OS + control-plane + routed-E2E browser) + inferenceCapacity, a partition that
oversubscribes physical RAM fails construction, and a discovery failure / over-pledge fails closed to a
conservative-fallback / zero-capacity partition. On a 64 GiB / 48 GiB-colima host the resolved capacity
is 10240 MiB, so `image-*` / `video-*` rows now fail-close cleanly at admission on apple-silicon. Gate
set (GREEN 2026-07-21): `cabal build all` (`-Wall -Werror`), `cabal test infernix-unit`
(partition-oversubscription reject/accept + headroom-floor reject + footprint-non-positive reject),
`cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, `infernix docs check`, and
the web unit suite (browser contract unchanged — the footprint remains a plain `Int` at the JS wire).
**Cohort gate**: apple-silicon + linux-cpu, [Wave W](cohort-validation-waves.md) — the behavioral proof
that the checked partition admits the fitting catalog with zero host OOM while over-capacity rows are
cleanly typed-rejected as `ModelMemoryLimitExceeded`. Closed 2026-07-24.
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

### Validation

Gates (closed under [Wave W](cohort-validation-waves.md), 2026-07-24):

- `cabal build all` (`-Wall -Werror`) compiles with the required footprint newtype and the
  enforcer-named budget across every mirror
- `cabal test infernix-unit` covers a `HostMemoryPartition` accepting a fitting split and rejecting an
  oversubscribing one, and a `ModelDescriptor` decode that fails closed when the footprint is absent
- `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, `infernix docs check`,
  and the web unit suite pass with the regenerated contracts
- `infernix test all` on apple-silicon plus linux-cpu proves the checked partition admits the fitting
  catalog with zero host OOM and cleanly typed-rejects over-capacity rows — closed under
  [Wave W](cohort-validation-waves.md)

### Remaining Work

None. The implementation is complete (code-side closed 2026-07-21): the required `ModelMemoryFootprint`
newtype replaced the bare-`Int` default-0 footprint, `InferenceMemoryBudget` names its enforcer
(`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit`, `UnenforcedMemoryBudget`
dropped), and the checked `HostMemoryPartition` (`minHostHeadroomMib` = 6144) replaced the hard-coded
`appleHostReserveMib = 3072`, all threaded through the JSON/Dhall/browser mirrors with unit coverage.
The apple-silicon plus linux-cpu behavioral cohort sign-off closed under
[Wave W](cohort-validation-waves.md) on 2026-07-24; no remaining work exists. The superseded bare-`Int`
footprint, the hard-coded reserve, and the `UnenforcedMemoryBudget` arm are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

---

## Remaining Work

Sprint 4.27 is closed for typed resource memory admission and typed inference error payloads by
Wave T's `linux-cpu` plus selected `linux-gpu` evidence. The MT3 catalog-replacement reopen (Sprint
4.22) is **closed** — proven by [Wave P](cohort-validation-waves.md) (2026-07-04).
**Sprint 4.25** (matrix substrate-accuracy closure) and **Sprint 4.26** (apple-silicon inference
RAM admission + bounded peak) are closed by [Wave R](cohort-validation-waves.md) and
[Wave S](cohort-validation-waves.md) for their original scopes.
**Sprint 4.28** (Evidence in Runtime and Engines) — the Managed-State-Transition Doctrine reopen for
this phase — is closed by [Wave V](cohort-validation-waves.md) (2026-07-20).
**Sprint 4.29** (Classified Model Download & Integrity-Witnessed Sentinel) — the Bounded-Command
Application & Bounded-HTTP reopen for this phase, the UA-bearing, `Retry-After`-honoring download fold
and the integrity-witnessed `PayloadVerified` — is closed by [Wave V](cohort-validation-waves.md)
(2026-07-20).
**Sprint 4.30** (Memory-Grant admission + capped-engine kernel) and **Sprint 4.31** (host memory
partition, required footprint, budget-enforcer split) — the memory-safety-by-construction reopen for
this phase (2026-07-21) — are closed under [Wave W](cohort-validation-waves.md) (2026-07-24) with
apple-silicon plus `linux-cpu` behavioral sign-off (code-side closed 2026-07-21 on the
machine-independent gate set): they replaced Sprint 4.27's proof-free
`admitModelMemory :: … -> Maybe` and Sprint 4.28's raw unbounded engine spawn, and Sprint 4.26's
bare-`Int` `modelRamFootprintMib` default-0, hard-coded `appleHostReserveMib = 3072`, and Sprint 4.27's
`UnenforcedMemoryBudget`. No remaining Phase 4 reopen work remains.

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
