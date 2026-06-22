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
- E2E covers Playwright flows through the routed demo surface for every primary lifecycle, the
  pre-auth landing entry points, and a per-model smoke matrix driven by the active substrate's
  generated demo catalog. The browser layer asserts the per-family rendered result for every
  demo-visible row — inline text, audio player, image, video, or MIDI/MusicXML download — and
  stays substrate-agnostic, with the demo app selecting the engine binding from the active
  `.dhall`. The `ResultFamily` and inline-vs-object-ref mapping lives in the model catalog.
- The reducer lives only in Haskell; PureScript tests cover patch application and rendering,
  not reducer logic.
- The Playwright source is identical across `apple-silicon`, `linux-cpu`, and `linux-gpu`;
  substrate selection lives only in the generated `.dhall` the demo app reads.

## Current Status

The durable-context surface this test plan covers is implemented over
[../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md).
The integration suite validates the real-cluster coordinator-to-engine request → batch →
result handoff through publication JSON, `cluster status`, generated demo config, and the
active service runtime loop; publishes and reads real Pulsar records for the conversation,
compacted contexts, compacted drafts, and bootstrap-ready topic families, including broker
message-key assertions for the compacted and bootstrap-ready records; reads the `infernix/demo`
compaction threshold from Pulsar admin, explicitly compacts the contexts and drafts topics, and
uses a Java Pulsar client compacted reader to prove one latest record per `contextId`; publishes
duplicate frontend conversation and draft messages with the same mutation-scoped producer name
and WebSocket `initialSequenceId`-backed sequence id and proves the broker stores exactly one
message for each duplicate set; and drives a real durable-context prompt through the
dispatcher, request/batch handoff, engine, result bridge, and conversation-log writeback. The
LinuxCpu integration suite carries the chaos and throughput block: two-worker CPU Kind
topology, two engine replicas, frontend/coordinator/engine pod replacement checks, engine node
drain, model-bootstrap deduplication across coordinator replacement, Linux engine
anti-affinity, and a compact multi-user durable prompt throughput matrix. The top-level
PureScript shell mounts the durable-context Chat and Artifacts renderers. The routed Keycloak
browser self-registration smoke reaches `/auth`, creates an account without email verification,
and returns to the SPA with an OIDC authorization code. The routed Playwright suite exchanges
that code for a real access token, proves malformed bearer rejection on
`/api/objects/upload`, proves the backend accepts the real token for scoped `/api/objects`
upload/download grant minting, then PUTs and GETs bytes through the routed presigned MinIO URLs
with exact content equality. The suite opens `/ws` with a real Keycloak access token and
verifies a malformed token does not open a browser WebSocket; the valid connection returns a
tagged `ServerError` for a malformed frame. The suite registers a second Keycloak user for the
same context id and display name, proves the second user's grant points at a distinct
`users/<sub>/...` prefix, observes `404` before the second user uploads, then verifies each
user reads only that user's bytes by default. It also validates the routed
`/api/objects/download` render-disposition matrix for inline image/audio/video, browser-native
PDF, bounded JSON/text preview, and download-only MIDI / MusicXML / generic-binary grants. The
browser artifact flow starts from the routed SPA login button, completes the app-owned PKCE
redirect through Keycloak self-registration, creates a context, uploads supported browser
artifact classes through the rendered Artifacts form, and validates bounded text/JSON previews,
inline image/audio/video routed media URLs, browser-native PDF URL wiring, and MIDI / MusicXML
/ generic-binary download-only states through routed presigned grants. The routed Playwright
suite also asserts the pre-auth landing shows exactly two CTAs (`Sign in` and `Create account`),
hides the app shell, routes each CTA to the matching Keycloak login or registration form, and
asserts the themed Keycloak titles (`Sign in to Infernix` and
`Create your Infernix account`).
The auth lifecycle test also asserts the signed-in operator ribbon links and the
`infernix_operator_token` cookie lifecycle, while the routed WebSocket/JWT test checks that
anonymous requests to `/harbor`, `/pulsar/admin`, and `/minio/s3` receive the edge JWT rejection
and the same routes progress to their upstreams when the request carries the real Keycloak token.
The routed Playwright run passes the per-model smoke matrix across every active catalog row; the full gate also
covers the durable-context browser flow with frontend pod replacement: the test deletes all
`infernix-demo` pods, waits for replacements, verifies reconnect plus active-context
resubscribe, and submits another prompt. The startup MinIO bucket repair, real wrong-realm
Keycloak token rejection for `/api/objects` and `/ws`, throughput matrix parameterization, and
extracted Playwright artifact fixtures under `web/test/fixtures/artifactSamples.js` are part of
the supported surface.

## Unit Layer

The unit layer runs through the `infernix-unit` Cabal stanza and the PureScript
`purescript-spec` suite under `web/test/`.

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

The integration layer runs through the `infernix-integration` Cabal stanza.

Coverage:

- **Coordinator-to-engine-pool handoff.** The integration suite should assert routed publication
  and `cluster status` report the validated engine-pool routing graph, and the generated substrate
  config routes the coordinator from request topics to derived pool/model topics while engine
  members consume only assigned topics without forwarding again. The old Linux per-engine and Apple
  host-topic metadata is absent from supported publication/status outputs.
- **Linux GPU service-loop round-trip.** The same run exercises cluster up, routed API
  probes, per-model inference, cache lifecycle, service runtime loop, and clean cluster down
  from the rebuilt CUDA launcher image.
- **Durable Pulsar topic-family round-trip.** The integration suite
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
- **LinuxCpu durable-context chaos block.** The `linux-cpu` validation topology renders with
  two workers and two engine replicas, and the suite validates frontend pod replacement,
  coordinator pod replacement, engine pod replacement, engine node drain, model-bootstrap
  request/ready-event deduplication across coordinator replacement, and engine anti-affinity.
  Each prompt-oriented case asserts completed conversation writeback plus exactly-one
  request/batch/result/conversation-result broker counts.
- **Compact multi-user throughput.** The suite submits the default `ThroughputMatrix`
  (3 users x 2 contexts x 2 prompts) through the durable prompt path, asserts exact per-context
  prompt/result counts with no extras, and reports p95 completion latency for the full-suite
  smoke gate. The suite also exposes `validateMultiUserDurablePromptThroughputWith` so larger
  matrices can run without changing the test body.
- **Runtime KV-cache path.** `Infernix.Runtime.KVCache` flows through
  `executeInferenceWithKVCache`. Unit coverage asserts native-runtime rebuild, reuse, and
  divergent prefix rebuild behavior; integration covers durable dispatcher, engine pod
  replacement, engine node drain, exact broker counts, throughput, platform recovery,
  production-shape deployment, and clean teardown.

## E2E Layer

Linux Playwright suites run inside the substrate image with
`npm --prefix web exec -- playwright test`; Apple host-native E2E uses host `npm exec` with the
same typed fixture.

`web/src/Main.purs` and `web/src/index.html` mount the durable-context Chat and Artifacts panes.
`infernix test e2e` runs a routed smoke that checks the typed Playwright fixture,
`/api/publication`, `/api/demo-config`, `/api/models` parity, and the routed SPA root heading.
The same Playwright file verifies the anonymous landing card exposes exactly the `Sign in` and
`Create account` buttons, keeps the summary grid and Chat / Artifacts shell hidden before auth,
routes `Sign in` to the Keycloak login form, and routes `Create account` directly to the
Keycloak registration form through `kc_action=register`. The same assertions check that the
repo-owned Keycloak theme is active by looking for the Infernix-specific login and registration
titles.
After login, the auth lifecycle smoke checks the operator ribbon links to `/harbor`,
`/pulsar/admin/admin/v2/clusters`, and `/minio/s3`; it also verifies the same access token is
written to the `infernix_operator_token` cookie on login/refresh and cleared on logout. The routed
JWT smoke probes the three gated operator route prefixes without a token and with the real bearer
token.
The account-deletion smoke creates a real user, writes a draft and a MinIO object, verifies the
user's demo Pulsar topics are present, clicks `Delete account`, accepts the browser confirmation,
and asserts `DELETE /api/account` reports deleted MinIO objects and Pulsar topics before the next
Keycloak request carries `kc_action=delete_account`.
The routed Keycloak self-registration smoke verifies the `/auth` browser surface, account
creation without email verification, and OIDC authorization-code redirect back to the SPA. The
suite exchanges that code through the routed token endpoint and validates `/api/objects` with
both malformed and real bearer tokens, proving JWT-backed grant minting and per-user object-key
scoping; it PUTs bytes through the minted routed MinIO upload URL, GETs them through the minted
download URL, and asserts exact content equality. The suite opens `/ws` with the real token and
verifies a malformed token does not open a browser WebSocket; a token minted from the Keycloak
admin realm does not open `/ws`, and the same wrong-realm token receives `401` from
`/api/objects/upload`. A malformed frame on the valid connection yields the tagged `ServerError`.
The object-grant flow registers a second user, proves the same context/display name maps to that
second user's prefix, gets `404` before the second upload, then verifies each user's grant reads
that user's own bytes. The object-grant flow validates the server-side download-grant render
disposition for image, audio, video, PDF, JSON, text, MIDI, MusicXML, and generic binary MIME
cases. The browser artifact flow covers the app-owned PKCE login path, local context creation,
bounded text/JSON previews, inline image/audio/video media URL wiring, browser-native PDF URL
wiring, and MIDI / MusicXML / generic-binary download-only states. The canonical browser
artifact payloads live in `web/test/fixtures/artifactSamples.js` and are imported by the
Playwright suite. The browser flow asserts the initial `ClientHello`, inbound context-list and
draft snapshots, context-create `ServerContextListPatch`, draft-upsert `ServerDraftMapPatch`,
prompt submit `ClientSubmitPrompt.promptUserUploads`, inbound prompt `ServerConversationPatch`,
and draft-remove `ServerDraftMapPatch` after submit clears the durable draft. The flow
force-closes the live WebSocket, verifies `ClientHello` and active `ClientSubscribeContext` are
resent, observes a fresh `ServerConversationSnapshot`, and submits another prompt through the
reconnected socket. The flow clicks the browser cancel control for the canonical prompt id from
the prompt append patch, asserts outbound `ClientCancelPrompt`, observes the inbound
`ConversationCancelEvent` append patch, and verifies the rendered cancel entry. The flow keeps
only the active context id/model id in browser session storage, asserts an in-progress draft
returns after forced WebSocket reconnect, reloads the page, signs in again through Keycloak,
observes the restored `ClientSubscribeContext`, and verifies the broker draft replay restores
the textarea value.

- **Auth lifecycle.** Login; logout; re-login with same credentials; JWT refresh. Signup,
  authorization-code redirect, token exchange, backend `/api/objects` JWT acceptance, and routed
  WebSocket valid/malformed-token handshake plus expired-token rejection and typed malformed-frame
  error behavior are covered by the current routed smoke. The browser app now also covers local
  logout, same-browser re-login, and refresh-token WebSocket re-auth through a new `ClientHello`
  after the refresh grant. The pre-auth landing smoke asserts the anonymous shell exposes exactly
  the two supported CTA entry points, that each lands on the matching Keycloak form, and that the
  mounted `infernix` Keycloak theme is active. The same auth lifecycle checks cover the operator
  ribbon and the cookie that Envoy Gateway's JWT policy reads for `/harbor`, `/pulsar/admin`, and
  `/minio/s3`. Account deletion coverage verifies the backend state reap happens before the
  Keycloak `delete_account` action begins.
- **Context lifecycle.** New-context dialog open/close without backend state; create; rename;
  soft-delete; select context. The browser now opens and closes the new-context dialog without
  sending `ClientCreateContext` or adding a local context, then selects a supported model, asserts
  the outbound `ClientCreateContext`, observes the context-create patch from the broker-backed
  stream, and verifies the active context rail preserves that model id. It also sends
  `ClientRenameContext` and `ClientSoftDeleteContext`, observes the broker-backed
  `ServerContextListPatch` upserts, and verifies the active context rail shows the updated title
  plus soft-deleted state. The backend `ContextModelMap` path is covered by integration, and the
  routed WebSocket test now sends an absent catalog model id and asserts typed `ServerError` code
  `unknown-model`.
- **Conversation lifecycle.** Submit; see response; two-prompts-in-a-row "queued" state;
  cancel-mid-inference; order preservation across reload. The browser now covers submitted prompt
  visibility, the two-prompt queued indicator, and cancel request visibility through routed
  WebSocket frames, patches, and the rendered Chat DOM. Completed response rendering is covered by
  the per-model smoke matrix; reload coverage is scoped to active-context resubscribe and durable
  draft restoration in the Phase 7 closure gate.
- **Draft lifecycle.** Type draft; refresh page; draft restored per context; submit clears
  draft. Browser draft upsert, submit-clear, forced-reconnect restore, and page-reload restore
  are covered through routed WebSocket frames and broker-backed draft patches.
- **Client reconnect/reconstitution.** Force-close the live WebSocket; verify the SPA keeps the
  authenticated shell mounted, resends `ClientHello` and active `ClientSubscribeContext`,
  receives a fresh `ServerConversationSnapshot`, and submits another prompt through the
  reconnected socket. It also preserves the active context id/model id across reload login so the
  active context can be resubscribed and its draft restored. Full storage-clear reconstitution is a
  future browser-matrix expansion, not a Phase 7 closure gate.
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
- **Multi-tab convergence.** Future browser-matrix expansion: two tabs on the same account; send
  from one, see in the other.
- **Client reconstitution.** Clear all browser storage via the Playwright Browser Context
  API; reload; sign in again; assert full pre-wipe state. A separate browser context simulates a
  different device. This remains outside the Phase 7 closure gate.
- **Pod failover from the browser's perspective.** Kill the WS-hosting pod while the test is
  running; assert the SPA re-establishes the WS transparently and resumes state.
- **Per-Model Smoke Matrix** (see dedicated section below).

## Per-Model Smoke Matrix

The per-model smoke matrix is a parameterized Playwright flow.

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
  - Asserts the per-family rendered result. Inline-text families (LLM, speech transcription)
    render the `inline_output` continuation or transcript directly in the Chat thread; artifact
    families render or download from the typed `object_ref` into infernix-demo-objects. The
    generated artifact (if any) appears in the conversation thread AND in the Artifacts view, and
    the expected handler succeeds: inline rendering for image/playable-audio/video, bounded
    preview for text/JSON, browser-native handling for PDF, and download-only handling for MIDI,
    MusicXML/MXL, unknown, or generic binary artifacts. The browser asserts the rendered shape,
    never a golden string, and the demo app — not the browser — selects the engine binding from
    the active `.dhall`.
- **Closure rule.** Across the active substrate's catalog, every non-`Not recommended` row in
  the README "Comprehensive Model / Format / Engine Matrix" has one passing smoke flow.
  Failure on any row fails the suite. Test reports name the substrate and the catalog entry
  explicitly.
- Canonical fixtures are checked into the repo under `web/test/fixtures/` and held under a
  strict size cap; large outputs derive from these via the engines under test rather than
  being checked in.

## Multi-User Throughput / Fan-In Batching / Fan-Out Test

`Infernix.Test.Integration.Throughput` is the real-cluster assertion that the inference
pipeline behaves correctly under concurrent load from multiple users on the same model.

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

The infernix-demo app — not the browser — chooses the engine binding from the active `.dhall`.
The browser asserts only the per-family **rendered** result and never inspects the substrate or
engine. The `ResultFamily` mapping and inline-vs-object-ref result surface for each row live at
[../architecture/model_catalog.md](../architecture/model_catalog.md); the canonical per-family
test contract lives at [testing_strategy.md](testing_strategy.md). For every demo-visible row the
e2e/browser layer asserts the family-appropriate rendered surface:

- **LLM** (qwen2.5 safetensors/AWQ, tinyllama GPTQ/GGUF, qwen1.5 MLX) — rendered inline text
  continuation in the Chat thread.
- **Speech transcription** (whisper.cpp, faster-whisper CT2) — rendered inline transcript text.
- **Source separation** (Demucs, Open-Unmix) — playable audio players for the stem object refs.
- **Audio-to-MIDI** (basic-pitch TensorFlow/Core ML/ONNX) — a MIDI download-only artifact.
- **Music transcription** (MT3 JAX, Omnizart) — a MIDI or MusicXML download-only artifact.
- **Image generation** (SDXL-Turbo, Apple SD Core ML) — an inline `<img>` render.
- **Video generation** (Wan2.1) — an inline `<video>` render.
- **Audio generation / TTS** (bark) — an inline `<audio>` player.
- **OMR tool** (Audiveris) — a MusicXML download-only artifact.

The browser asserts the result surface by rendered shape (inline text, audio player, image, video,
MIDI/MusicXML download) and never by golden strings. Inline-text rows render directly from
`inline_output`; artifact rows render or download from a typed `object_ref` into the always-on
infernix-demo-objects bucket. Hardware proof that those paths exercise real engines remains a cohort
gate. The union across the three substrate catalogs covers every README matrix row even though no
single substrate carries all 19 rows (apple 15, cpu 12, gpu 16).

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
- [../architecture/model_catalog.md](../architecture/model_catalog.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
