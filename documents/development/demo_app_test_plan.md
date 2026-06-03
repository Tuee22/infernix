# Demo App Test Plan

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [chaos_testing.md](chaos_testing.md), [../architecture/demo_app_design.md](../architecture/demo_app_design.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

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
The validation suites described here land in Sprints 7.13 (unit), 7.14 (integration), and
7.15 (E2E). Sprint 7.14's WebSocket-to-Pulsar publish plumbing is code-complete as of
May 27, 2026, and the Linux GPU integration suite now validates the real-cluster
coordinator-to-engine request -> batch -> result handoff through publication JSON,
`cluster status`, generated demo config, and the active service runtime loop. As of
May 28, 2026, the same suite also publishes and reads real Pulsar records for the
conversation, compacted contexts, compacted drafts, and bootstrap-ready topic families,
including broker message-key assertions for the compacted and bootstrap-ready records. The same
Linux GPU validation now reads the `infernix/demo` compaction threshold from Pulsar admin,
explicitly compacts the contexts and drafts topics, and uses a Java Pulsar client compacted
reader to prove one latest record per `contextId`. The suite also publishes duplicate frontend
conversation and draft messages with the same mutation-scoped producer name and WebSocket
`initialSequenceId`-backed sequence id, then proves the broker stores exactly one message for each
duplicate set. It now also drives a real durable-context prompt through the dispatcher,
request/batch handoff, engine, result bridge, and conversation-log writeback, proving the normal
non-chaos path end to end on Linux GPU. As of 2026-06-02, the LinuxCpu integration suite also
contains the code-side Wave C chaos and throughput block: two-worker CPU Kind topology,
two engine replicas, frontend/coordinator/engine pod replacement checks, engine node drain,
model-bootstrap deduplication across coordinator replacement, Linux engine anti-affinity, and a
compact multi-user durable prompt throughput matrix. The mounted `test:infernix-integration`
compile gate passes, and the native `linux-cpu` `infernix test all` gate passed on 2026-06-02;
`linux-gpu` `infernix test all` validation passed on 2026-06-03. Sprint 7.15's
top-level PureScript shell now
mounts the durable-context Chat and Artifacts renderers
instead of the retired Workbench form, and the minimal routed SPA/publication Playwright smoke
passed on the clean rebuilt Linux GPU launcher May 28, 2026. The routed Keycloak browser
self-registration smoke now reaches `/auth`, creates a fresh account without email
verification, and returns to the SPA with an OIDC authorization code on the same clean rebuilt
Linux GPU launcher. The routed Playwright suite now also exchanges that code for a real access
token, proves malformed bearer rejection on `/api/objects/upload`, proves the backend accepts
the real token for scoped `/api/objects` upload/download grant minting, then PUTs and GETs bytes
through the routed presigned MinIO URLs with exact content equality. The same routed suite now
opens `/ws` with a real Keycloak access token and verifies a malformed token does not open a
browser WebSocket; the same valid connection returns a tagged `ServerError` for a malformed frame.
The same suite also registers a second Keycloak user for the same context id and display name,
proves the second user's grant points at a distinct `users/<sub>/...` prefix, observes `404`
before the second user uploads, then verifies each user reads only that user's bytes by default.
It also validates the routed `/api/objects/download` render-disposition matrix for inline
image/audio/video, browser-native PDF, bounded JSON/text preview, and download-only MIDI /
MusicXML / generic-binary grants. The browser artifact flow now starts from the routed SPA login
button, completes the app-owned PKCE redirect through Keycloak self-registration, creates a
context, uploads supported browser artifact classes through the rendered Artifacts form, and
validates bounded text/JSON previews, inline image/audio/video routed media URLs,
browser-native PDF URL wiring, and MIDI / MusicXML / generic-binary download-only states through
routed presigned grants.
The 2026-06-03 `linux-gpu` routed Playwright run passed the per-model smoke matrix across all 16
active LinuxGpu catalog rows, and the final rebuilt-image full gate completed the matrix in 2.2
minutes. The same final full gate passed the durable-context browser flow with frontend pod
replacement: the test deletes all `infernix-demo` pods, waits for replacements, verifies reconnect
plus active-context resubscribe, and submits another prompt. The 2026-06-03 residual sweep adds
startup MinIO bucket repair, real wrong-realm Keycloak token rejection for `/api/objects` and
`/ws`, throughput matrix parameterization, and extracted Playwright artifact fixtures under
`web/test/fixtures/artifactSamples.js`. Those residual changes passed the rebuilt-image
`linux-gpu` full gate on 2026-06-03 against launcher image digest
`sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b`; the resumed
rebuilt-image `linux-cpu` full gate passed on 2026-06-03 against launcher image digest
`sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa` with full
integration and routed Playwright E2E (7/7).

## Unit Layer

Lands in Sprint 7.13. Additions to the existing `infernix-unit` Cabal stanza and the
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
- **Engine runtime import-boundary lint.** The Haskell style gate rejects imports of
  frontend, coordinator, auth, object-presign, or WebSocket modules from the concrete engine
  runtime modules (`Infernix.Runtime`, `.Cache`, `.Worker`).
- **Shared-library import-boundary lint.** The same style gate rejects upward demo, runtime,
  auth, object-presign, or WebSocket imports from the Phase 7 conversation, dispatcher, result
  bridge, and bootstrap helper modules.

## Integration Layer

Owned by Sprint 7.14. Additions to the existing `infernix-integration` Cabal stanza.

Implemented as of May 28, 2026:

- **Linux GPU coordinator-to-engine handoff.** The integration suite asserts routed
  publication JSON reports the active `hostInferenceBatchTopic`, `cluster status` reports
  the matching `publicationHostInferenceBatchTopic`, and the generated demo config routes
  the coordinator from `inference.request.linux-gpu` to `inference.batch.linux-gpu` while
  the engine consumes the batch topic without forwarding again.
- **Linux GPU service-loop round-trip.** The same run exercises cluster up, routed API
  probes, per-model inference, cache lifecycle, service runtime loop, and clean cluster down
  from the rebuilt CUDA launcher image.
- **Durable Pulsar topic-family round-trip.** The May 28, 2026 Linux GPU integration run
  publishes `ClientCreateContext`, `ClientUpdateDraft`, `ClientCancelPrompt`, and a raw
  `ModelBootstrapReadyEvent`, reads them back with Pulsar Readers, asserts the compacted
  contexts/drafts keys are `contextId`, asserts the bootstrap-ready key is `modelId`, asserts
  conversation records are unkeyed, and decodes each typed payload.
- **Broker compaction behavior.** The same suite asserts the live `infernix/demo` namespace has
  the supported 100 MiB compaction threshold, publishes superseded and latest context/draft
  records under isolated users, triggers topic compaction, and reads with a Java Pulsar
  `readCompacted(true)` reader to assert exactly one latest payload per `contextId`.
- **Frontend producer-dedup behavior.** The same suite simulates a frontend reconnect by
  publishing duplicate `ClientCancelPrompt` and `ClientUpdateDraft` messages with the same
  mutation-scoped producer names and WebSocket `initialSequenceId`-backed sequence ids, then reads
  the isolated topics with Pulsar Readers and asserts the broker stored exactly one conversation
  event and one draft event.
- **Durable-context prompt round-trip.** The same suite publishes context metadata, creates the
  conversation topic, waits for dispatcher discovery, submits a prompt, and asserts a completed
  `ConversationInferenceResultEvent` appears on the real conversation log after the coordinator
  contexts consumer hydrates `ContextModelMap` and the dispatcher -> request/batch -> engine ->
  result-bridge path runs.
- **LinuxCpu durable-context chaos block.** The 2026-06-02 code-side landing renders the
  `linux-cpu` validation topology with two workers and two engine replicas, then validates
  frontend pod replacement, coordinator pod replacement, engine pod replacement, engine node
  drain, model-bootstrap request/ready-event deduplication across coordinator replacement, and
  engine anti-affinity. Each prompt-oriented case asserts completed conversation writeback plus
  exactly-one request/batch/result/conversation-result broker counts.
- **Compact multi-user throughput.** The same code-side landing submits the default
  `ThroughputMatrix` (3 users x 2 contexts x 2 prompts) through the durable prompt path, asserts
  exact per-context prompt/result counts with no extras, and reports p95 completion latency for
  the full-suite smoke gate. The suite also exposes
  `validateMultiUserDurablePromptThroughputWith` so larger matrices can run without changing the
  test body.

Pending integration-layer work:

- **Real KV-cache engine failover.** The current deterministic adapter layer exposes no reusable
  KV-cache surface, so cache-hit/cache-miss verification under engine failover remains owned by
  Sprint 7.8.

Resolved residual validation:

- **Rebuilt-image CPU residual validation.** The wrong-realm Keycloak token negatives and
  throughput matrix parameterization passed both rebuilt-image residual gates: `linux-gpu` on
  2026-06-03 against digest
  `sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b`, and `linux-cpu`
  on 2026-06-03 against digest
  `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`.

## E2E Layer

Lands in Sprint 7.15. Linux Playwright suites run inside the substrate image with
`npm --prefix web exec -- playwright test`; Apple host-native E2E uses host `npm exec` with the
same typed fixture and is covered by the Apple cohort validation batch.

Current partial landing: `web/src/Main.purs` and `web/src/index.html` mount the durable-context
Chat and Artifacts panes. The May 28, 2026 clean rebuilt Linux GPU
`infernix test e2e` run passed the minimal routed smoke that checks the typed Playwright
fixture, `/api/publication`, `/api/demo-config`, `/api/models` parity, and the routed SPA
root heading. A same-day follow-on added a routed Keycloak self-registration smoke that verifies
the `/auth` browser surface, fresh account creation without email verification, and OIDC
authorization-code redirect back to the SPA. A later follow-on exchanges that code through the
routed token endpoint and validates `/api/objects` with both malformed and real bearer tokens,
proving JWT-backed grant minting and per-user object-key scoping; it then PUTs bytes through the
minted routed MinIO upload URL, GETs them through the minted download URL, and asserts exact
content equality. The same suite opens `/ws` with the real token and verifies a malformed token
does not open a browser WebSocket; it also verifies a token minted from the Keycloak admin realm
does not open `/ws`, and the same wrong-realm token receives `401` from `/api/objects/upload`. It
also sends a malformed frame on the valid connection and asserts the tagged `ServerError`. The
object-grant flow also registers a second user, proves the
same context/display name maps to that second user's prefix, gets `404` before the second upload,
then verifies each user's grant reads that user's own bytes. The same object-grant flow validates
the server-side download-grant render disposition for image, audio, video, PDF, JSON, text, MIDI,
MusicXML, and generic binary MIME cases. The browser artifact flow covers the app-owned PKCE login
path, local context creation, bounded text/JSON previews, inline image/audio/video media URL
wiring, browser-native PDF URL wiring, and MIDI / MusicXML / generic-binary download-only states.
The canonical browser artifact payloads now live in
`web/test/fixtures/artifactSamples.js` and are imported by the Playwright suite.
The same browser flow now asserts the initial `ClientHello`, inbound context-list and draft
snapshots, context-create `ServerContextListPatch`, draft-upsert `ServerDraftMapPatch`, prompt
submit `ClientSubmitPrompt.promptUserUploads`, inbound prompt `ServerConversationPatch`, and
draft-remove `ServerDraftMapPatch` after submit clears the durable draft. It also force-closes
the live WebSocket, verifies `ClientHello` and active `ClientSubscribeContext` are resent,
observes a fresh `ServerConversationSnapshot`, and submits another prompt through the reconnected
socket. The same flow now clicks the browser cancel control for the canonical prompt id from the
prompt append patch, asserts outbound `ClientCancelPrompt`, observes the inbound
`ConversationCancelEvent` append patch, and verifies the rendered cancel entry.
The same browser flow now keeps only the active context id/model id in browser session storage,
asserts an in-progress draft returns after forced WebSocket reconnect, reloads the page, signs in
again through Keycloak, observes the restored `ClientSubscribeContext`, and verifies the broker
draft replay restores the textarea value.
The flows below are still the Sprint 7.15 closure target.

- **Auth lifecycle.** Login; logout; re-login with same credentials; JWT refresh. Signup,
  authorization-code redirect, token exchange, backend `/api/objects` JWT acceptance, and routed
  WebSocket valid/malformed-token handshake plus expired-token rejection and typed malformed-frame
  error behavior are covered by the current routed smoke. The browser app now also covers local
  logout, same-browser re-login, and refresh-token WebSocket re-auth through a new `ClientHello`
  after the refresh grant.
- **Context lifecycle.** New-context dialog open/close without backend state; create; rename;
  soft-delete; select context. The browser now opens and closes the new-context dialog without
  sending `ClientCreateContext` or adding a local context, then selects a supported model, asserts
  the outbound `ClientCreateContext`, observes the context-create patch from the broker-backed
  stream, and verifies the active context rail preserves that model id. It also sends
  `ClientRenameContext` and `ClientSoftDeleteContext`, observes the broker-backed
  `ServerContextListPatch` upserts, and verifies the active context rail shows the renamed title
  plus soft-deleted state. The backend `ContextModelMap` path is covered by integration, and the
  routed WebSocket test now sends an absent catalog model id and asserts typed `ServerError` code
  `unknown-model`.
- **Conversation lifecycle.** Submit; see response; two-prompts-in-a-row "queued" state;
  cancel-mid-inference; order preservation across reload. The browser now covers submitted prompt
  visibility, the two-prompt queued indicator, and cancel request visibility through routed
  WebSocket frames, patches, and the rendered Chat DOM; response rendering and reload order
  preservation remain open.
- **Draft lifecycle.** Type draft; refresh page; draft restored per context; submit clears
  draft. Browser draft upsert, submit-clear, forced-reconnect restore, and page-reload restore
  are covered through routed WebSocket frames and broker-backed draft patches.
- **Client reconnect/reconstitution.** Force-close the live WebSocket; verify the SPA keeps the
  authenticated shell mounted, resends `ClientHello` and active `ClientSubscribeContext`,
  receives a fresh `ServerConversationSnapshot`, and submits another prompt through the
  reconnected socket. It also preserves the active context id/model id across reload login so the
  active context can be resubscribed and its draft restored. Full storage-clear reconstitution
  remains open.
- **Artifact upload lifecycle** per supported artifact class (image, playable audio, video,
  text/JSON, PDF, MIDI, MusicXML/MXL notation, generic binary): open upload, select file,
  observe progress, see artifact appear in Artifacts view AND in the per-context conversation
  thread as a `UserUpload` event. Browser upload to MinIO is covered for text, JSON, PNG, WAV,
  MP4, PDF, MIDI, MusicXML, and generic binary fixtures with Artifacts view render/download
  states asserted. Browser uploads now send `ClientRecordUpload` and the backend maps it to a
  `ConversationUserUploadEvent`. Prompt submit now sends the current context's uploaded
  `ObjectRef`s in `ClientSubmitPrompt.promptUserUploads`, asserted from the outbound browser
  WebSocket frame; the active context also sends `ClientSubscribeContext`, and the prompt event is
  asserted through an inbound `ServerConversationPatch` append frame. Browser-visible upload-event
  assertions now cover the outbound `ClientRecordUpload`, inbound `ConversationUserUploadEvent`
  append patch, and rendered Chat upload message for each supported browser fixture.
- **Artifact download lifecycle.** Click an artifact; presigned GET resolves; inline render
  via `<img>` / `<audio>` / `<video>` where applicable; bounded text/JSON preview and
  browser-native PDF handling where applicable; MIDI, MusicXML/MXL, unknown, and generic
  binary artifacts download otherwise. The routed backend grant-disposition matrix for these
  MIME classes is covered; browser click/render behavior is covered for bounded text/JSON
  previews, inline image/audio/video media URL wiring, browser-native PDF URL wiring, and
  MIDI / MusicXML / generic-binary download-only states.
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

Lands in Sprint 7.15 as a parameterized Playwright flow.

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

Lands in Sprint 7.14 as `Infernix.Test.Integration.Throughput`. Real-cluster assertion that
the inference pipeline behaves correctly under concurrent load from multiple users on the
same model.

Ordinary full-suite defaults:

- N = 3 synthetic users
- K = 2 independent contexts per user
- P = 2 prompts per context, fired in rapid succession without waiting for prior responses
- model: substrate-appropriate primary LLM lane
  (`linux-cpu` → Qwen2.5-1.5B-Instruct on Transformers + PyTorch CPU; `linux-gpu` →
  Qwen2.5-1.5B-Instruct on vLLM; `apple-silicon` → Qwen1.5-1.8B-Chat-4bit on MLX-LM)

The helper is parameterized by `ThroughputMatrix`; stress runs can raise N/K/P, while the ordinary
full-suite gate keeps the compact matrix so validation remains bounded.

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
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
