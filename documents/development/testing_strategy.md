# Testing Strategy

**Status**: Supporting reference
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md)

> **Purpose**: Describe operator-facing validation-lane detail and matrix coverage that support the canonical testing doctrine.

The canonical validation entrypoints, fail-fast rules, and supported boundaries live in
[../engineering/testing.md](../engineering/testing.md). This page defines the
mode-specific coverage, matrix behavior, and operator detail behind those canonical entrypoints.

## TL;DR

- host-native validation is supported only on the `apple-silicon` lane; `linux-cpu` and
  `linux-gpu` validate through the Linux outer-container control plane
- development and validation are native-only: `linux-cpu` evidence comes from native Linux amd64
  or native Linux arm64 hosts, never from cross-architecture emulation
- the initialized repo-root runtime config remains the source of truth for validation scope,
  generated catalog selection, and routed demo-surface expectations
- each validation gate selects one accelerator (`apple-silicon` or `linux-gpu`) plus `linux-cpu`;
  a cross-accelerator claim requires corresponding evidence from both accelerators
- the auxiliary routed-prefix checks require the live Harbor, MinIO, and Pulsar upstream
  responses on the shared edge

## Lane Ownership

The validation surface is split by what only a real machine can prove:

- machine-independent gates — build, unit, style, lint, docs, the web unit suite, and the Python
  quality gate — run on whichever machine is present and gate ordinary work;
- hardware-specific full-suite runs are the gate for claims about that accelerator;
- resource-safety governance is not a testing-strategy concern: the memory contract's enforcement
  points are owned by [../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md)
  and [../architecture/bounded_host_memory.md](../architecture/bounded_host_memory.md), and this
  document defers to them rather than restating their gates.

This document is a supporting reference. It narrows and operationalizes the canonical testing
doctrine in [../engineering/testing.md](../engineering/testing.md); it does not duplicate it.

## Validation Layers

- **Test-harness config lifecycle.** `infernix test integration|e2e|all` own
  `./infernix.dhall` for the duration of a run: each reads `./infernix.test.dhall` (fail fast →
  `infernix test init`), backs up any existing `./infernix.dhall` (an operator config or the
  image-baked empty-models config), generates `./infernix.dhall` from the test config's substrate +
  demo-ui selection, runs the suites, and restores the backup (or removes the generated file when
  there was none). The swap is crash-safe by construction: the backup lives at
  `./infernix.dhall.harness-backup` and `withTestHarnessConfig` reconciles a leftover backup on
  **entry** (a SIGKILL bypasses the `finally` restore), so a killed run cannot leave the operator's
  runtime config clobbered by the test config. Reservation and teardown are owner-atomic over the
  all-Haskell lock and supervision boundary; canonical home
  [Configuration Doctrine](../architecture/configuration_doctrine.md). The Linux launcher image bakes
  both `./infernix.dhall` and `./infernix.test.dhall`
  at build time so the containerized `docker compose run --rm infernix infernix test all` finds them.
  The integration suite's per-variant `internal materialize-substrate` keeps rewriting that same
  harness-owned path across substrate variants. `infernix test lint` and `infernix test unit` remain
  config-independent (fixtures only).
- `infernix docs check` validates governed docs, README or plan cross-references, required CLI
  registry coverage in `documents/reference/cli_reference.md`, phase-document documentation
  sections, and forbidden legacy-doctrine phrases
- `infernix lint docs` validates governed-doc metadata and generated sections, and fails when the
  README model matrix cells drift from the generated runnable catalog, explicit residual rows, or
  `Not recommended` states
- `infernix lint files` rejects repository-owned
  C/C++/Objective-C/CUDA/assembly/Metal/Swift/C2HS/HSC/C-- sources and headers, Cabal native-source fields and
  native-token CPP definitions, and embedded native source/writers/compiler invocations in another
  implementation language; native implementation in upstream `filelock`, `process`, `unix`, MLX,
  or coremltools packages is outside repository ownership and remains allowed
- `infernix test lint` validates repository hygiene, required chart or Kind or `.proto` assets, the
  repo-owned Haskell style stack, the Haskell build path, and the shared Python adapter quality
  gate via `poetry run check-code` from the shared `python/` project when adapters are present;
  the Haskell style layer also rejects forbidden frontend, coordinator, auth, object-presign, or
  WebSocket imports from the engine runtime modules and rejects upward demo/runtime/auth/object or
  WebSocket imports from the shared-library helpers
- `infernix test unit` validates generated catalog counts and selection rules, demo-config encode
  or decode behavior, cache lifecycle, the protobuf-over-stdio Python worker path, execution-plan
  compilation and live-enforcer refinement, executable-derived engine commands, chart image or
  claim discovery, Harbor overlay emission, and the PureScript generated-contract and SPA
  view-model behavior via `spago test` driven by the maintained runner in `web/test/Main.purs`. Its
  focused process coverage includes same-process/cross-process lifecycle-lock contention and release,
  isolated helper handles, bounded framed-protocol failures, target provenance, parent/supervisor
  death, timeout/exception/cancellation cleanup, stopped groups, descendants, reaping, and
  activity-retirement proofs
- `cabal test infernix-compile-fail` separately proves subprocess phase skipping, session escape,
  linear start-authority reuse, lifecycle authority escape/reuse, and external access to the raw
  command, subprocess, lifecycle-lock, or protocol kernels do not typecheck
- `infernix test integration` validates cluster lifecycle for the active initialized substrate,
  generated demo-config publication, routed demo or tool surfaces, routed inference plus cache
  endpoints, service-path request or result publication through the active topic contract,
  `cluster status`, every generated active-mode catalog entry from the mounted demo config,
  demo-ui disablement on the `linux-cpu` lane via
  `infernix internal materialize-substrate linux-cpu --demo-ui false`, and edge-port rediscovery
  on the host-native `apple-silicon` lane. This per-model catalog traversal is bounded by the
  resource-admission doctrine: a full run completes rows that fit the active budget or fails closed
  per row with typed `ModelMemoryLimitExceeded` and explicit MiB quantities (see
  `## Resource Memory-Bounded Validation`)
- `infernix test e2e` validates the routed browser surface through the full durable-context
  Playwright flow alongside the SPA root, the `Infernix` heading, and the published platform-state
  JSON endpoints
- `infernix test all` runs lint, unit, integration, and E2E in sequence as the complete supported
  suite for the active substrate
- the supported real-cluster `linux-gpu` integration and `test all` lanes also depend on enough
  host disk headroom for Kind image preload, Harbor-backed image publication, and Pulsar
  BookKeeper durability; low disk headroom can block `infernix-engine` readiness after cluster
  creation even when the NVIDIA preflight passes

## Hardware Cohort Cadence

The validation plan minimizes switching between the Apple Silicon and CUDA-capable Linux hosts.

The machine-independent gate set runs through `infernix test lint`, `infernix test unit`, and
`infernix docs check`. Those closed entrypoints own the bounded root build, all focused Haskell
suites, the solver-isolated Cabal-format package, `infernix lint files/docs/chart/proto`, the web
unit suite, and `poetry run check-code`; no bare Cabal command is an operator validation
instruction. The gate runs on whichever machine is present and has two declared prerequisites.
First, `infernix init` must have written the repo-root
`./infernix-host.dhall` host manifest. Second, the toolchain runs under a declared memory ceiling
([bounded_host_memory.md](../architecture/bounded_host_memory.md)), which owns what that ceiling
covers, what admits it, and what it leaves unbounded; this document does not restate those terms.

Hardware-specific validation runs on the machine that owns the changed path.

- A must-pass gate selects one accelerator plus `linux-cpu`.
- Cross-accelerator coverage requires sibling per-lane attestations or a `linux-cpu`-only
  aggregation that consumes them.
- `linux-cpu` remains a portable check and a fallback substrate on native Linux amd64 or native
  Linux arm64, but it is not the CUDA Linux lane for GPU-sensitive work and is not exercised
  through Apple Silicon emulation.

## Lifecycle Interpretation

- long waits in `cluster up` and `cluster down` can still be healthy when the lifecycle is
  building images, publishing them into Harbor, preloading Harbor-backed images onto the Kind
  worker, or replaying retained state
- the supported operator check during those waits is `infernix cluster status`
- when that status surface reports `lifecycleStatus: in-progress`, use `lifecyclePhase`,
  `lifecycleDetail`, and `lifecycleHeartbeatAt` to distinguish real progress from a stale wait
- the lifecycle refreshes the heartbeat roughly every 30 seconds during the monitored
  long-running subprocess phases, so a heartbeat that keeps moving is treated as progress rather
  than failure even when the wall-clock duration is large
- `infernix test all` may perform multiple internal cluster bring-up or teardown cycles before the
  outer Apple bootstrap `test` command returns; apply the same progress interpretation to those
  managed internal rounds
- those internal rounds run against the operator's single cluster slot: the harness resolves the
  operator's cluster name, `./.data`, and `infernix.dhall` through the same `findRepoRoot`, so it
  must not silently destroy an operator's cluster. The persisted cluster has a
  typed `ClusterOwner` (`OperatorOwned | HarnessOwned`) and gates teardown on typed ownership
  evidence: a `HarnessOwned` `infernix test all` seizes the slot and **fails closed** on an
  `OperatorOwned` running cluster instead of tearing it down. Seizure is evidence-gated, the cluster
  names its `ClusterOwner`, persistence is fail-closed, and reservation and teardown are
  owner-atomic. Canonical home:
  [Managed State Transitions](../architecture/managed_state_transitions.md)
- a typed `ClusterLifecycle` machine with resumable positions defines the
  lifecycle-interpretation surface this section describes, and its canonical home is
  [Managed State Transitions](../architecture/managed_state_transitions.md)

## Active-Mode Coverage Rules

- unit coverage proves generated catalog shape, selected engine metadata, request-shape helpers,
  publication-summary rendering, and object-reference result formatting for the active generated
  contract module
- `infernix test integration` projects the active initialized runtime config into the generated demo
  config and publication state, then validates the routed demo API, auxiliary routed prefixes, every
  generated active-mode catalog entry, cache mutation endpoints, and the daemon request or result
  loop for the active substrate. This per-model traversal is bounded by runtime memory admission and
  either completes or fails closed per row with typed `ModelMemoryLimitExceeded` (see
  `## Resource Memory-Bounded Validation`)
- `infernix test integration` also validates `cluster status`, `cluster down`, and repeated
  `cluster up` behavior for the active substrate
- `infernix test integration` also validates the routed `GET /api/cache`,
  `POST /api/cache/evict`, and `POST /api/cache/rebuild` contract against manifest-backed durable
  state
- `infernix test integration` also validates that `/harbor` and `/pulsar/ws`
  resolve through the shared routed surface through the live Harbor and Pulsar upstreams (MinIO is
  reached only through the webapp `/api/objects` proxy, not a gateway route)
- the `/pulsar/ws` contract is specific: the public prefix rewrites to Pulsar's real
  `/ws` upstream context root so routed `/pulsar/ws/v2/...` requests terminate on the WebSocket
  servlet
- `infernix test integration` validates the service loop by publishing a typed request through the
  configured topic helper and asserting a matching typed result appears on the configured result
  topic
- `infernix test integration` also validates publication and status handoff metadata for the active
  coordinator-to-engine path. The assertion is that routed publication JSON and
  `cluster status` expose the validated engine-pool routing graph, and the generated substrate
  config routes coordinator request topics to derived pool/model topics without an engine
  self-forward loop. The integration suite also asserts that the
  `hostInferenceBatchTopic` and
  `publicationHostInferenceBatchTopic` compatibility fields are absent
- on the `linux-cpu` lane, `infernix test integration` also validates
  `infernix internal materialize-substrate linux-cpu --demo-ui false`
- on the host-native `apple-silicon` lane, `infernix test integration` also validates
  `9090`-first edge-port rediscovery
- on the `linux-cpu` lane, `infernix test integration` compares the deterministic Harbor
  PostgreSQL PV inventory and host-path mapping across `cluster down` plus `cluster up`; platform
  services are single-instance and recover through their ordinary restart or restore contracts,
  not standby-promotion failure injection
- `infernix test e2e` loads the routed SPA root, checks the `Infernix` heading, and validates
  platform-state JSON parity (`/api/publication`, `/api/demo-config`, `/api/models`); inference
  correctness is covered by the integration layer's per-model Pulsar roundtrip. The routed
  Playwright suite also covers the Keycloak self-registration auth-code smoke, routed WebSocket
  valid/malformed-token handshake validation, expired-token rejection, typed malformed-frame
  error validation, real-Keycloak-JWT `/api/objects` grant validation, same-user webapp
  `/api/objects` proxy upload/download byte equality (no presigned MinIO URL),
  cross-user object-prefix isolation, and the routed download-grant
  MIME disposition matrix. The browser artifact path covers app-owned PKCE login, local context
  creation, bounded text/JSON previews, inline image/audio/video media URL wiring, browser-native
  PDF URL wiring, MIDI / MusicXML / generic-binary download-only states, and the per-model smoke
  matrix across every active catalog row. The browser flow asserts each uploaded artifact's
  `ClientRecordUpload`, inbound `ConversationUserUploadEvent` patch, and rendered Chat upload
  message, plus new-context dialog close-negative behavior, model-picker selection through
  `ClientCreateContext` plus the broker-backed context summary, context rename/soft-delete
  through `ClientRenameContext` / `ClientSoftDeleteContext` and `ServerContextListPatch`, and a
  routed unknown-model `ClientCreateContext` backend rejection with typed `ServerError`. Browser
  artifact payloads live in `web/test/fixtures/artifactSamples.js`.
- the Apple host-native routed E2E lane also fails if the clustered routed surface cannot keep
  `apiUpstream.mode = cluster-demo`, preserve one browser-visible base URL, match the Apple
  publication payload `daemonLocation = cluster-pod`, advertise
  `inferenceExecutorLocation = control-plane-host`, advertise
  `inferenceDispatchMode = pulsar-bridge-to-host-daemon`, and still complete routed manual
  inference through the cluster-daemon-to-host-daemon batch path
- the supported Linux routed E2E path uses Playwright from the substrate image with
  `npm --prefix web exec -- playwright test`; Apple host-native routed E2E uses host
  `npm exec` with the same typed fixture and is covered by the Apple selected-accelerator gate
- on the Linux lane, routed E2E targets the Kind control-plane DNS on Docker's private `kind`
  network instead of `host.docker.internal`
- supported Playwright launchers clear conflicting `NO_COLOR` and `FORCE_COLOR` values from the
  child environment before Playwright starts
- changing the active initialized runtime config changes the generated catalog and therefore the
  exercised entry set automatically

## Per-Family Result Contract

The per-family result contract is the canonical substrate-aware integration plus
substrate-agnostic browser layer that asserts the real-output surface for every demo-visible row. The
model-to-`ResultFamily` and inline-vs-object-ref mapping lives at
[../architecture/model_catalog.md](../architecture/model_catalog.md); this section is the canonical
home for the test contract itself.

The coordinator eagerly stages the configured model set in the `infernix-models` MinIO bucket
behind the `warm-model-cache` barrier. The runtime worker dispatches through the selected engine
binding, hydrates its derived local cache from those staged objects via
`adapters.model_cache.get_model_path`, and publishes the typed per-family result surface. Realness is
guaranteed by construction — the engine code cannot
return a fabricated result (enforced by the realness lint), so the suites trust the result and fail
closed on `status=failed`. That fail-closed guarantee extends to model memory through the
resource-admission doctrine: an over-budget request publishes typed `ModelMemoryLimitExceeded`
before launch, while rows that fit the active budget still run. Runnable rows require real-output
evidence on each claimed accelerator, and rows without that evidence are explicit residuals. Adding
a catalog row requires rerunning the catalog-driven integration and browser matrices before making
a support claim for that row.

### One DRY substrate-aware suite

There is exactly one DRY substrate-aware integration suite — never per-substrate suites. It reads
the active substrate `.dhall`, traverses the README matrix rows that substrate selects, and asserts
a per-family result contract by **shape and type, never golden strings**. A closed `ResultFamily`
sum type is resolved from `family` + `artifactType` +
`matrixRowId`; the coarse `family` field collapses source-separation, audio-to-MIDI, and
audio-generation under `audio`, so `ResultFamily` is the authoritative discriminator. One
substrate-agnostic Playwright suite asserts the rendered side of the same contract.

### Per-family ResultFamily dispatch table

The integration suite dispatches each row to its `ResultFamily` assertion:

- **LLM** (SmolLM2 safetensors, qwen2.5 AWQ, tinyllama GPTQ/GGUF, qwen1.5 MLX): text prompt -> non-empty
  continuation; `inline_output`.
- **Speech transcription** (whisper.cpp, faster-whisper CT2): audio input -> transcript text;
  `inline_output`.
- **Source separation** (Demucs, Open-Unmix): audio -> `>= 2` stem object refs; `object_ref`.
- **Audio-to-MIDI** (basic-pitch Core ML/ONNX; TensorFlow remains a named residual): audio -> valid
  MIDI bytes; `object_ref`.
- **Music transcription** (MT3-PyTorch and MR-MT3 through `mt3-infer`, plus the maintained
  ByteDance PyTorch piano row): audio -> MIDI or MusicXML; `object_ref`.
- **Image generation** (SDXL-Turbo, Apple SD Core ML): text -> valid image (magic + dims);
  `object_ref`.
- **Video generation** (Wan2.1 on CUDA; Apple MPS remains a named residual): text -> valid video
  container; `object_ref`.
- **Audio generation / TTS** (bark): text -> valid audio; `object_ref`.
- **OMR tool** (Audiveris): image/PDF -> MusicXML; `object_ref`.

`ResultPayload` carries successful payloads as `inline_output` or `object_ref` and failed payloads
as a typed `InferenceError` branch. `buildPayload` routes LLM and speech successes to inline output
while artifact successes return object references. Runtime admission failures use
`InferenceError.ModelMemoryLimitExceeded` with explicit `required_mib` and `available_mib`
quantities plus budget resource/source; tests must assert those fields directly rather than parsing
human text. The newer proto fields are a non-text **input** object-ref on `InferenceRequest` /
`WorkerRequest` and an object-ref **output** on `WorkerResponse` for artifact adapters. Artifact
results always use the always-on infernix-demo-objects bucket, never the retired infernix-runtime /
infernix-results buckets.

### Substrate-agnostic Playwright layer

The Playwright suite source is identical across `apple-silicon`, `linux-cpu`, and `linux-gpu`. The
infernix-demo app chooses the engine binding from the active `.dhall`; the browser does not branch
on substrate or engine. The browser layer asserts the per-family rendered result for every
demo-visible row — inline text for LLM and speech, an audio player for audio-generation and
playable-stem output, an image for image generation, a video for video generation, and a
MIDI/MusicXML download for the transcription and OMR families.

### Union-coverage invariant

The active substrate's runnable catalog is traversed with `Not recommended` and named-residual rows
omitted, so the runnable per-substrate counts are apple 16, cpu 12, and gpu 16. Coverage is enforced
as a mechanical invariant: `allMatrixRowIds` is exported from `Models.hs`, the union of
`catalogForMode` over the three substrates plus `residualMatrixRowIdsForMode` equals the full
19-row README matrix, and a README-to-matrix cross-check runs under `infernix lint docs`. The
invariant proves no row is omitted from catalogs or residual accounting; it does not replace the
real-output gates required for newly added runnable rows.

## Resource Memory-Bounded Validation

For Apple and Linux CPU, per-model integration traversal must exercise the compiled/refined
execution plan. Every model carries `modelRamFootprintMib`; compilation retains both available and
unavailable rows, refinement promotes only matching grant/enforcer pairs to `ExecutableModel`, and
  the normal coordinator path rejects an unavailable request without engine launch. Empty,
unknown, wrong-route, and malformed coordinator/engine inputs also have terminal failed-result
paths before source removal/acknowledgement. The single-flight authority remains inside the opaque
engine capability, and Apple/Linux CPU adversarial breaches must leave the daemon alive.
Linux GPU compiles under independent RAM and VRAM enforcement, so a
device-using row is admitted against both limits and watched by both enforcers. A `linux-gpu` budget
that names only one resource still fails plan compilation closed with
`GpuDualResourceBudgetRequired`, and a dual budget whose halves name the wrong physical resources is
rejected by `InvalidMemoryEnforcer`.

A per-model row lands in exactly one of two supported outcomes:

- **completes** — the model fits the active enforced budget, runs, and honors its per-family
  real-output contract
- **fails closed** — the model's footprint exceeds the active budget, so the row is a clean per-row
  `status=failed` with typed `ModelMemoryLimitExceeded` and explicit MiB quantities

Validation proves cross-family topic collisions are rejected, bootstrap
model/URL/timestamp drift fails before side effects, the raw publisher is absent, and non-ASCII
substrate metadata round-trips through explicit UTF-8 Dhall emission. The validation classifier
must distinguish a typed memory-capacity failure from the two disallowed
outcomes: a **stall** (a genuinely missing result, including an OS-OOM kill) and a
**fabricated pass**. Machine-independent GPU enforcement tests cover the fixed `nvidia-smi`
observer's parsers, the group
attribution arithmetic and its overflow rejections, and a live no-CUDA-context sample that must
complete without a fabricated breach or an enforcement failure) runs in `infernix-unit` and
`infernix-capped-engine-observer`. Those live assertions require the device: they are real evidence
only where one is reachable, and **skip loudly** otherwise. Whether the outer launcher container can
reach the device is a property of the host Docker daemon's default runtime, not of `compose.yaml`, so
that coverage is host-configuration-dependent and is never recorded as unconditional. The adversarial
CUDA breach in `infernix-unit` uses `runNvidiaVramBreachAssertions`, which holds a real
device allocation made through `libcuda.so.1` driver-API calls under `ctypes` — needing no compiler
and adding no repo-owned native source — and drives the `nvidiaWatchdogOutcomeForTest` seam. The
case asserts a typed `EngineExceededCeiling`, a
non-successful group reap, and a subsequent smaller allocation completing cleanly. Its ceilings are
set from measurement rather than assumption, because a CUDA context is itself a ~500 MiB device
allocation before any `cuMemAlloc`, so a naive ceiling would be breached by context overhead and
would prove nothing about the allocation. It skips loudly and by name when the device, the pinned
interpreter, or the allocation gate is unavailable. The runtime ceiling-breach proof belongs to the
unit seam: `validateCatalogModelInference` classifies catalog rows as compiler-unavailable or
completed, while a runtime breach of an admitted ceiling is neither classification.

Every suite whose image spawns a subprocess bounds its descriptor space first
(`Infernix.DescriptorSpace`). This is not a performance nicety: `close_fds = True` makes the forked
child close every descriptor up to the soft `RLIMIT_NOFILE` before `exec`, which is 313 s per spawn
at a containerd pod's 1073741816, so an unbounded suite image reads as a hang rather than as a
resource bound. Canonical doctrine:
[../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md).

## Durable-Context Demo Validation

The multi-user durable-context demo expands the validation surface across three layers.
The authoritative test contract lives at
[demo_app_test_plan.md](demo_app_test_plan.md); this section names the layers and their
relationship to the existing entrypoints.

- **Unit layer** (`infernix test unit`) — reducer property tests, idempotency dedup,
  `prefixHash` chain, dispatcher pure-fold rule, JWT validation edge cases, presigned URL
  minting, compacted topic projection, WS envelope codec, plus PureScript view-model tests
  scoped to patch application and rendering only. Reducer logic is exercised in Haskell, not
  in PureScript.
- **Integration layer** (`infernix test integration`) — real Pulsar / MinIO / Keycloak
  round-trips, producer-dedup verification and stable Pulsar Failover resubscription after a
  simulated coordinator restart, cross-user object-key 403 negative through the webapp object-proxy, and the
  **multi-user throughput / fan-in batching / fan-out** test (N users × K contexts × P prompts on
  one model) asserting per-context ordering, no duplicates or losses, cross-context independence,
  batching gain, bounded p95 latency, and dedup correctness. The Linux GPU integration suite covers
  the coordinator-to-engine request/batch/result service loop plus real Reader roundtrips for
  conversation, compacted contexts, compacted drafts, and bootstrap-ready topic families. The
  LinuxCpu integration suite carries engine-pool placement, shared-subscription backpressure,
  compact multi-user prompt throughput, PostgreSQL lifecycle rebinding, and the proof that the
  single-node topology schedules every workload with no `Pending` workload.

  There is **no failure-injection block**. The supported topology has no standby role or service
  instance to promote: one process runs per role per machine, and each platform service is
  single-instance, so instance loss recovers by restart or restore. Delivery is **at-least-once
  with an effectively-once observable outcome** —
  acknowledgement follows the terminal result — and that property is asserted at the effect layer
  (producer dedup, the `.ready` sentinel, per-context ordering) rather than by killing a process.
- **E2E layer** (`infernix test e2e`) — Playwright flows for auth, context, conversation
  (including two-in-a-row and cancel), drafts, artifact upload/download plus render, preview,
  document handling, or download-only behavior per supported artifact class, generated-artifact
  lifecycle, multi-tab convergence, client reconstitution via Browser Context storage-clear,
  forced WebSocket disconnect/reconnect, plus the **per-model smoke matrix** driven by the active
  substrate's generated `.dhall` catalog (every non-`Not recommended` row gets one passing
  flow). The Playwright suite source is identical across `apple-silicon`, `linux-cpu`, and
  `linux-gpu`; substrate selection lives only in the generated `.dhall`. The routed suite
  covers browser socket-close reconnect by force-closing the live WebSocket and verifying
  re-hello, active-context re-subscribe, a fresh snapshot, and a post-reconnect prompt submit.
  It also covers the browser cancel lifecycle by sending `ClientCancelPrompt` for the latest
  unresolved server-backed prompt id and verifying the inbound cancel append patch. Draft
  restoration is covered by forcing a WebSocket reconnect and by reloading the page, signing in
  again, resubscribing the session-stored active context, and verifying broker-backed draft
  replay restores the textarea. The routed browser flow submits a second prompt before the
  first unresolved prompt resolves and asserts the rendered `2 queued prompts` warning.

## Cross-References

- [frontend_contracts.md](frontend_contracts.md)
- [haskell_style.md](haskell_style.md)
- [python_policy.md](python_policy.md)
- [purescript_policy.md](purescript_policy.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md)
- [../engineering/portability.md](../engineering/portability.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
- [demo_app_test_plan.md](demo_app_test_plan.md)
- [../architecture/model_catalog.md](../architecture/model_catalog.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
