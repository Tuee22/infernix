# Testing Strategy

**Status**: Supporting reference
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe operator-facing validation-lane detail and matrix coverage that support the canonical testing doctrine.

The canonical validation entrypoints, fail-fast rules, and supported boundaries live in
[../engineering/testing.md](../engineering/testing.md). This page records the implemented
mode-specific coverage, matrix behavior, and operator detail behind those canonical entrypoints.

## TL;DR

- host-native validation is supported only on the `apple-silicon` lane; `linux-cpu` and
  `linux-gpu` validate through the Linux outer-container control plane
- development and validation are native-only: `linux-cpu` evidence comes from native Linux amd64
  or native Linux arm64 hosts, never from cross-architecture emulation
- the initialized repo-root runtime config remains the source of truth for validation scope,
  generated catalog selection, and routed demo-surface expectations
- phase work validates on the current hardware cohort first, then batches the counterpart Apple
  Silicon or CUDA Linux full-suite run at phase closure
- the auxiliary routed-prefix checks require the live Harbor, MinIO, and Pulsar upstream
  responses on the shared edge

## Current Status

The prior resource-admission and bounded-command evidence remains useful but no longer closes the
strong construction claim. The reopened validation contract is owned by
[Typed Execution Plan](../architecture/typed_execution_plan.md): schema-negative tests, plan
compiler properties, runtime-enforcer refusal tests, exact ceiling-breach tests, route exclusion for
uncompiled models, and zero raw-spawn imports or lint exemptions outside the process kernels.
The all-Haskell lifecycle-lock and bounded-command replacement is implemented, but every source
digest, review, Stage 1 result, and cohort result produced before that replacement is superseded.
Its focused adversarial suites, fresh source review, complete source-matched Stage 1, and Wave Y are
in progress.

- the implemented lane matrix is host-native `apple-silicon`, outer-container `linux-cpu` on
  native Linux, and real-cluster `linux-gpu`
- the routed auxiliary checks below describe current behavior precisely: `/harbor`
  and `/pulsar/ws` publication is required through the live upstream services only (MinIO has no
  external gateway route since Phase 3 Sprint 3.13; the webapp `/api/objects` proxy is its only
  browser-facing surface)
- the implemented lifecycle progress surface now persists the active phase, child operation, and
  heartbeat in `cluster status` while supported `cluster up` or `cluster down` work is still in
  flight
- active phase docs record hardware-cohort residuals explicitly when one machine has validated and
  the counterpart Apple Silicon or CUDA Linux closure batch remains
- resource safety is governed by the typed execution-plan doctrine: each model carries a
  conservative footprint (`modelRamFootprintMib`), and `compileRuntimePlan` either mints a
  resource-indexed grant inside a compiled placement or retains that row as an
  `UnavailableModel`. Apple compilation uses the checked host partition and Linux CPU uses the
  engine-pod memory envelope; live refinement must pair the grant with a matching enforcer before
  engine launch can receive an `ExecutableModel`. Validation must prove that a request for an
  unavailable row returns typed
  `InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` without
  blocking smaller placements. Linux GPU currently fails plan compilation closed with
  `GpuDualResourceBudgetRequired`; Phase 6 owns the dual RAM/VRAM path. Phase 1 owns compiler
  accounting and coordinator rejection delivery, while Phase 4 owns Apple/Linux CPU adversarial
  survival and encapsulated serialization. Canonical home:
  [../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md)

## Validation Layers

- **Test-harness config lifecycle (Phase 8).** `infernix test integration|e2e|all` own
  `./infernix.dhall` for the duration of a run: each reads `./infernix.test.dhall` (fail fast →
  `infernix test init`), backs up any existing `./infernix.dhall` (an operator config or the
  image-baked empty-models config), generates `./infernix.dhall` from the test config's substrate +
  demo-ui selection, runs the suites, and restores the backup (or removes the generated file when
  there was none). The swap is crash-safe by construction: the backup lives at
  `./infernix.dhall.harness-backup` and `withTestHarnessConfig` reconciles a leftover backup on
  **entry** (a SIGKILL bypasses the `finally` restore), so a killed run cannot leave the operator's
  runtime config clobbered by the test config. Wave X (2026-07-24) historically closes that
  2026-07-23 crash-safe entry-reconcile scope in Phase 6 Sprint 6.43; it does not close the
  2026-07-25 owner-atomic reservation/teardown correction. That correction remains under Phase 2
  validation and source review after the all-Haskell lock/supervision implementation; its focused
  tests, fresh source-matched Stage 1, and Wave Y remain in progress, and Phase 6 validation is
  ordered after Phases 2 and 4. The canonical contract home is
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
  WebSocket imports from the Phase 7 shared-library helpers
- `infernix test unit` validates generated catalog counts and selection rules, demo-config encode
  or decode behavior, cache lifecycle, the protobuf-over-stdio Python worker path, execution-plan
  compilation and live-enforcer refinement, executable-derived engine commands, chart image or
  claim discovery, Harbor overlay emission, and the current PureScript generated-contract and SPA
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

> **Implement in natural phase order on whichever single machine is present. The cohort gate is a
> batched wave — the only supported machine switch — not a per-sprint or per-phase trigger.** Every
> open phase and sprint has two independent axes. *Code-side closure* (Axis 1) is the implementation
> plus the machine-independent gate set — `cabal build all`, `cabal test infernix-unit`,
> `cabal test infernix-haskell-style`, `infernix lint files/docs/chart/proto`, `infernix docs
> check`, the web unit suite, and `poetry run check-code`; completed in natural order on one
> machine, it is the gate to begin the *next* phase's implementation. *Cohort sign-off* (Axis 2) is
> the hardware-specific full-suite — Apple Metal including headless Metal/Core ML materialization,
> and CUDA GPU runs — batched once per closure cycle against frozen code and tracked in
> `cohort-validation-waves.md`; it is the gate for `Done` and never the gate for moving on. **The
> next action for any open phase is always its remaining code-side closure on the machine you
> already have; do not switch machines to "validate the open phase." The machine switch happens only
> at a scheduled wave boundary, once per cohort.** A deliverable that is intrinsically
> hardware-bound — for example the upstream MLX GPU-operation and coremltools/materialized-root
> smoke of Phase 1 Sprint 1.20 after its fresh exact-source complete Stage 1 — is named as
> such in its `Code-side closure` field and is exercised inside its cohort's wave, never pre-claimed
> as machine-independent.

- Work validates on the machine that owns the changed path, then records the phase's chosen
  accelerator plus `linux-cpu` evidence in the relevant wave.
- The other accelerator does not block that phase's `Done` state. Cross-accelerator coverage is
  split into sibling phases or merged later by a `linux-cpu`-only aggregation phase that consumes
  committed per-lane attestations.
- A validation-only residual runs after a coherent phase slice is ready, not after every small
  sprint.
- `linux-cpu` remains a portable check and a fallback substrate on native Linux amd64 or native
  Linux arm64, but it is not the CUDA Linux cohort for GPU-sensitive work and is not exercised
  through Apple Silicon emulation.
- The active cycle's batched-switch boundaries — which work runs on which machine in which
  validation wave — are tracked in
  [../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).
  Operators picking up validation work should check the active wave before bringing up a cluster
  on either substrate.

## Lifecycle Interpretation

- the legacy-tracking ledger at
  [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
  records obsolete-surface receipts; current validation evidence is tracked by the active phase
  files and cohort waves
- long waits in `cluster up` and `cluster down` can still be healthy when the lifecycle is
  building images, publishing them into Harbor, preloading Harbor-backed images onto the Kind
  worker, or replaying retained state
- the supported operator check during those waits is `infernix cluster status`
- when that status surface reports `lifecycleStatus: in-progress`, use `lifecyclePhase`,
  `lifecycleDetail`, and `lifecycleHeartbeatAt` to distinguish real progress from a stale wait
- the current implementation refreshes the heartbeat roughly every 30 seconds during the monitored
  long-running subprocess phases, so a heartbeat that keeps moving is treated as progress rather
  than failure even when the wall-clock duration is large
- `infernix test all` may perform multiple internal cluster bring-up or teardown cycles before the
  outer Apple bootstrap `test` command returns; apply the same progress interpretation to those
  managed internal rounds
- those internal rounds run against the operator's single cluster slot: the harness resolves the
  operator's cluster name, `./.data`, and `infernix.dhall` through the same `findRepoRoot`, so it
  must not silently destroy an operator's cluster. The target shape gives the persisted cluster a
  typed `ClusterOwner` (`OperatorOwned | HarnessOwned`) and gates teardown on typed ownership
  evidence: a `HarnessOwned` `infernix test all` seizes the slot and **fails closed** on an
  `OperatorOwned` running cluster instead of tearing it down. Wave X (2026-07-24) historically
  closes the 2026-07-23 evidence-gated seizure, `ClusterOwner`, and fail-closed persistence scope in
  Phase 6 Sprint 6.43 and Phase 2 Sprint 2.15. It does not close the 2026-07-25 owner-atomic
  reservation/teardown correction or its all-Haskell lock/supervision replacement. The
  implementation is present, while focused validation, fresh source review, source-matched Stage 1,
  and Wave Y remain open; Phase 6 validation is ordered after Phases 2 and 4. Wave Y requires an explicit
  integration-test build and installed Apple binary before freezing, then a source-matched
  `linux-cpu` launcher build and recorded image digest before its uninterrupted full-suite run.
  Canonical home:
  [Managed State Transitions](../architecture/managed_state_transitions.md)
- a typed `ClusterLifecycle` machine with phase-resume is the target shape of the
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
- the target `/pulsar/ws` contract remains specific: the public prefix rewrites to Pulsar's real
  `/ws` upstream context root so routed `/pulsar/ws/v2/...` requests terminate on the WebSocket
  servlet
- `infernix test integration` validates the service loop by publishing a typed request through the
  configured topic helper and asserting a matching typed result appears on the configured result
  topic
- `infernix test integration` also validates publication and status handoff metadata for the active
  coordinator-to-engine path. The target assertion is that routed publication JSON and
  `cluster status` expose the validated engine-pool routing graph, and the generated substrate
  config routes coordinator request topics to derived pool/model topics without an engine
  self-forward loop. The integration suite also asserts that the old `hostInferenceBatchTopic` and
  `publicationHostInferenceBatchTopic` compatibility fields are absent
- on the `linux-cpu` lane, `infernix test integration` also validates
  `infernix internal materialize-substrate linux-cpu --demo-ui false`
- on the host-native `apple-silicon` lane, `infernix test integration` also validates
  `9090`-first edge-port rediscovery
- on the `linux-cpu` lane, `infernix test integration` also deletes a Harbor core pod and verifies
  Harbor-backed image pulls still work, replaces a MinIO pod after writing a sentinel file,
  restarts a Pulsar broker between two routed publish or result checks, deletes the Harbor
  PostgreSQL primary to verify failover, and compares the deterministic Harbor PostgreSQL PV
  inventory plus host-path mapping across `cluster down` plus `cluster up`
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
  `npm exec` with the same typed fixture and is covered by the Apple cohort validation batch
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
closed on `status=failed`. That fail-closed guarantee extends to model memory through the reopened
resource-admission doctrine: an over-budget request publishes typed `ModelMemoryLimitExceeded`
before launch, while rows that fit the active budget still run. The Phases 1/4/6 work delivers and
re-attests real output per accelerator, and not-yet-real rows are explicit residuals. When a catalog
row is added after a cohort wave, that older wave remains valid only for its then-active catalog;
the new row is not considered proven until the active wave reruns the catalog-driven integration and
browser matrices.

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
current cohort run required to prove newly added runnable rows.

## Resource Memory-Bounded Validation

For Apple and Linux CPU, per-model integration traversal must exercise the compiled/refined
execution plan. Every model carries `modelRamFootprintMib`; compilation retains both available and
unavailable rows, refinement promotes only matching grant/enforcer pairs to `ExecutableModel`, and
the normal coordinator path now rejects only the unavailable request without engine launch. Empty,
unknown, wrong-route, and malformed coordinator/engine inputs also have terminal failed-result
paths before source removal/acknowledgement. The current daemon supplies caller-owned
serialization; Phase 4 must encapsulate it and prove the Apple/Linux CPU enforcement behavior.
Linux GPU intentionally fails plan compilation closed with
`GpuDualResourceBudgetRequired` until Phase 6 provides independent RAM and VRAM enforcement.

The 2026-07-25 Phase 1 gate historically proved an Apple/Linux CPU per-model run has exactly two
per-row outcomes and no third. It predates the all-Haskell lifecycle/subprocess correction and must
be rerun in the fresh complete Stage 1 before it is current-worktree evidence:

- **completes** — the model fits the active enforced budget, runs, and honors its per-family
  real-output contract
- **fails closed** — the model's footprint exceeds the active budget, so the row is a clean per-row
  `status=failed` with typed `ModelMemoryLimitExceeded` and explicit MiB quantities

The Phase 1 suite also proved cross-family topic collisions are rejected, bootstrap
model/URL/timestamp drift fails before side effects, the raw publisher is absent, and non-ASCII
substrate metadata round-trips through explicit UTF-8 Dhall emission. The validation classifier
must distinguish a typed memory-capacity failure from the two disallowed
outcomes: a **stall** (a genuinely missing result, including the historical OS-OOM-kill symptom) and
a **fabricated pass**. Phase 4 owns Apple/Linux CPU adversarial proof, Phase 6 owns GPU enforcement,
and Phase 8 owns the final wire migration. Canonical doctrine:
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
  round-trips, producer-dedup verification across simulated dispatcher restart, Pulsar Failover
  handoff, cross-user object-key 403 negative through the webapp object-proxy, chaos tests (WS pod kill, dispatcher kill, engine
  pod kill mid-inference, coordinator kill mid-bootstrap upload, concurrent model-bootstrap
  requests, one-engine-per-node enforcement), and the **multi-user throughput / fan-in batching
  / fan-out** test (N users × K contexts × P prompts on one model) asserting per-context
  ordering, no duplicates or losses, cross-context independence, batching gain, bounded p95
  latency, and dedup correctness. The Linux GPU integration suite covers the
  coordinator-to-engine request/batch/result service loop plus real Reader roundtrips for
  conversation, compacted contexts, compacted drafts, and bootstrap-ready topic families. The
  LinuxCpu integration suite carries the chaos/throughput block: two-worker CPU Kind topology,
  frontend/coordinator/engine pod replacement, engine node drain, model-bootstrap deduplication
  across coordinator replacement, Linux engine anti-affinity, and compact multi-user prompt
  throughput.
- **E2E layer** (`infernix test e2e`) — Playwright flows for auth, context, conversation
  (including two-in-a-row and cancel), drafts, artifact upload/download plus render, preview,
  document handling, or download-only behavior per supported artifact class, generated-artifact
  lifecycle, multi-tab convergence, client reconstitution via Browser Context storage-clear,
  pod-failover-from-browser, plus the **per-model smoke matrix** driven by the active
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
- [chaos_testing.md](chaos_testing.md)
- [../architecture/model_catalog.md](../architecture/model_catalog.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
