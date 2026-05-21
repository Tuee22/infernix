# Demo App Test Plan

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [chaos_testing.md](chaos_testing.md), [../architecture/demo_app_design.md](../architecture/demo_app_design.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Define the unit, integration, and end-to-end validation surface for the
> multi-user durable-context demo application, including the per-model smoke matrix and the
> multi-user throughput / fan-in batching / fan-out integration test.

## TL;DR

- Validation is split into three layers: unit, integration, E2E.
- Unit covers the shared-library primitives (reducer, idempotency dedup, `prefixHash` chain,
  dispatcher rule, JWT, presigned URLs, WS envelope codec) plus PureScript view-model patch
  application and rendering.
- Integration covers real Pulsar / MinIO / Keycloak round-trips, producer-dedup verification,
  Failover handoff, chaos kills, and a multi-user throughput test.
- E2E covers Playwright flows through the routed demo surface for every primary lifecycle plus
  a per-model smoke matrix driven by the active substrate's generated demo catalog.
- The reducer lives only in Haskell; PureScript tests cover patch application and rendering,
  not reducer logic.
- The Playwright source is identical across `apple-silicon`, `linux-cpu`, and `linux-gpu`;
  substrate selection lives only in the generated `.dhall` the demo app reads.

## Current Status

The durable-context surface this test plan covers is implemented over
[../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md).
The validation suites described here land in Sprints 7.12 (unit), 7.13 (integration), and
7.14 (E2E). Until those sprints close, the supported validation surface remains the Phase 6
suite plus the catalog, publication, and cache demo-API checks already in place.

## Unit Layer

Lands in Sprint 7.12. Additions to the existing `infernix-unit` Cabal stanza and the
PureScript `purescript-spec` suite under `web/test/`.

- **Reducer property tests.** Determinism over arbitrary `ConversationEvent` logs; idempotency
  dedup; cancellation semantics; two-prompt-in-a-row ordering; equivalence of state-snapshot
  and snapshot + patch-stream evolution.
- **`prefixHash` chain tests.** Determinism; monotonicity; equality under reorder of
  independent events; mismatch on tampered event.
- **Dispatcher pure-fold tests.** Hold-vs-dispatch decisions across arbitrary log prefixes
  including cancels, queued prompts, and out-of-order results.
- **Topic naming tests.** Every `TopicNamespace` shape derives the expected per-user and
  per-context names.
- **JWT validation edge cases.** Expired, wrong issuer, wrong audience, malformed, valid,
  JWKS cache hit and miss behaviors.
- **Presigned URL minting tests.** Correct scope, correct expiration, signature shape,
  cross-user rejection at the scope-policy layer.
- **WS envelope codec roundtrip.** Every `WsClientMessage` and `WsServerMessage` variant
  encodes and decodes byte-stable on both Haskell and PureScript sides.
- **Compacted topic projection tests.** Synthetic in-memory broker yields the expected
  compacted state for the contexts and drafts topics.
- **PureScript view-model tests** (`web/test/Infernix/Web/ChatSpec.purs`, `ArtifactsSpec.purs`).
  Selection, left-rail rendering, draft restore, queued-state rendering, cancelled-result
  rendering, artifact-kind dispatch. These exercise the trivial patch-application helpers
  and rendering only; they do not test reducer logic, which is Haskell-only.

## Integration Layer

Lands in Sprint 7.13. Additions to the existing `infernix-integration` Cabal stanza.

- **Real Pulsar publish + Reader subscribe round-trip** per topic family (conversation,
  compacted contexts, compacted drafts, inference request and result).
- **Real Pulsar producer-dedup verification.** Simulate dispatcher restart mid-flight; assert
  exactly-one inference dispatch and exactly-one result.
- **Real Pulsar Failover handoff.** Kill the active dispatcher subscription consumer; assert
  the surviving consumer resumes from the same cursor.
- **Real MinIO presigned PUT/GET** with per-user scoping; cross-user negative assertion.
- **Real Keycloak signup + login + JWT validation** round-trip against a deployed Keycloak.
- **Chaos tests** for the failure semantics described in
  [../architecture/demo_app_design.md](../architecture/demo_app_design.md):
  - WS pod kill mid-session; client reconnects to a surviving replica; full state preserved.
  - Dispatcher pod kill mid-prompt; Failover + producer dedup → exactly one inference
    dispatch and exactly one result.
  - Cluster daemon kill mid-inference; engine on surviving pod rebuilds KV cache from log;
    exactly one result.
- **Multi-User Throughput / Fan-In Batching / Fan-Out test** (see dedicated section below).

## E2E Layer

Lands in Sprint 7.14. Playwright suites against the dedicated `infernix-playwright:local`
image, invoked via `docker compose run --rm playwright`.

- **Auth lifecycle.** Signup; login; logout; re-login with same credentials; JWT refresh.
- **Context lifecycle.** New-context creation defers backend state until first submit; rename;
  soft-delete; select context.
- **Conversation lifecycle.** Submit; see response; two-prompts-in-a-row "queued" state;
  cancel-mid-inference; order preservation across reload.
- **Draft lifecycle.** Type draft; refresh page; draft restored per context; submit clears
  draft.
- **Artifact upload lifecycle** per supported artifact class (image, playable audio, video,
  text/JSON, PDF, MIDI, MusicXML/MXL notation, generic binary): open upload, select file,
  observe progress, see artifact appear in Artifacts view AND in the per-context conversation
  thread as a `UserUpload` event.
- **Artifact download lifecycle.** Click an artifact; presigned GET resolves; inline render
  via `<img>` / `<audio>` / `<video>` where applicable; bounded text/JSON preview and
  browser-native PDF handling where applicable; MIDI, MusicXML/MXL, unknown, and generic
  binary artifacts download otherwise.
- **Generated artifact lifecycle.** Prompt a model that generates a non-text artifact
  (e.g., SDXL Turbo for an image, bark-small for audio, Basic Pitch for MIDI, Audiveris for
  MusicXML/PDF notation); confirm the artifact appears in the conversation AND in the
  Artifacts view; render or download succeeds according to artifact class.
- **Multi-tab convergence.** Two tabs on the same account; send from one, see in the other.
- **Client reconstitution.** Clear all browser storage via the Playwright Browser Context
  API; reload; sign in again; assert full pre-wipe state. A separate browser context
  simulates a different device.
- **Pod failover from the browser's perspective.** Kill the WS-hosting pod while the test is
  running; assert the SPA re-establishes the WS transparently and resumes state.
- **Per-Model Smoke Matrix** (see dedicated section below).

## Per-Model Smoke Matrix

Lands in Sprint 7.14 as a parameterized Playwright flow.

- Reads the active substrate's generated `.dhall` catalog — the same source the SPA uses.
- Iterates every catalog entry whose engine cell for the active substrate is not
  `Not recommended`.
  - For each entry:
  - Creates a fresh context pinned to that model.
  - Submits a family-appropriate canonical input from `web/test/fixtures/`:
    - text-family LLMs → canonical text prompt
    - speech transcription → upload `audio/short-speech.wav`; submit transcription request
    - source separation → upload `audio/short-mix.wav`; submit
    - audio-to-MIDI / MIR → upload `audio/short-pitch.wav`; submit
    - image generation → canonical text prompt
    - video generation → canonical text prompt
    - audio generation / TTS → canonical text prompt
    - OMR / notation extraction → upload `image/score-page.png`; submit
  - Waits for `InferenceResult` with `status = Completed`.
  - Asserts the generated artifact (if any) appears in the conversation thread AND in the
    Artifacts view, and that the expected handler succeeds: inline rendering for
    image/playable-audio/video, bounded preview for text/JSON, browser-native handling for
    PDF, and download-only handling for MIDI, MusicXML/MXL, unknown, or generic binary
    artifacts.
- **Closure rule.** Across the active substrate's catalog, every non-`Not recommended` row in
  the README "Comprehensive Model / Format / Engine Matrix" has one passing smoke flow.
  Failure on any row fails the suite. Test reports name the substrate and the catalog entry
  explicitly.
- Canonical fixtures are checked into the repo under `web/test/fixtures/` and held under a
  strict size cap; large outputs derive from these via the engines under test rather than
  being checked in.

## Multi-User Throughput / Fan-In Batching / Fan-Out Test

Lands in Sprint 7.13 as `Infernix.Test.Integration.Throughput`. Real-cluster assertion that
the inference pipeline behaves correctly under concurrent load from multiple users on the
same model.

Defaults:

- N = 10 Keycloak users
- K = 3 independent contexts per user
- P = 5 prompts per context, fired in rapid succession without waiting for prior responses
- model: substrate-appropriate primary LLM lane
  (`linux-cpu` → Qwen2.5-1.5B-Instruct on Transformers + PyTorch CPU; `linux-gpu` →
  Qwen2.5-1.5B-Instruct on vLLM; `apple-silicon` → Qwen1.5-1.8B-Chat-4bit on MLX-LM)

Assertions:

1. **Per-context ordering preserved.** Each context's `InferenceResult` events appear in the
   same order as its `UserPrompt` events, with matching `causalRef`s.
2. **No duplicates and no losses.** Count of `UserPrompt`s equals count of `InferenceResult`s
   per context.
3. **Cross-context independence.** Prompts from context A never appear as responses in
   context B; per-context single-flight is respected; one slow context does not block
   another's progress.
4. **Batching is observed.** For engines that support continuous batching, total throughput
   exceeds single-stream throughput by a configurable margin recorded in the assertion.
5. **Bounded p95 latency.** 95th-percentile per-prompt wall-clock latency stays under a
   substrate-specific ceiling.
6. **No producer-dedup false positives.** Every `UserPrompt` with a unique
   `clientIdempotencyKey` produces exactly one inference dispatch and exactly one result.

The test is substrate-aware: ceilings, batching assertions, and the chosen LLM differ per
substrate but the test code is one suite parameterized on the active substrate file.

## Substrate-Agnostic E2E

The Playwright suite source is identical across `apple-silicon`, `linux-cpu`, and
`linux-gpu`. The active substrate's generated `.dhall` chooses engine bindings; the test
driver iterates the catalog rows from that file and skips any row whose engine cell for the
active substrate is `Not recommended`. No substrate-specific branching lives in browser test
code.

## Validation

- `infernix test unit` includes every unit-layer suite named here.
- `infernix test integration` includes every integration-layer suite named here, including
  the chaos tests and the throughput test.
- `infernix test e2e` runs the Playwright suite including the per-model smoke matrix.
- `infernix test all` aggregates lint, unit, integration, and E2E. Phase 7 closure requires
  `infernix test all` green on at least one substrate with `demo_ui = true`.
- `infernix lint docs` must remain clean as new suites and fixtures are added.

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [chaos_testing.md](chaos_testing.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
