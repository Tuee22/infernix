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
- the active staged substrate remains the source of truth for validation scope, generated catalog
  selection, and routed demo-surface expectations
- phase work validates on the current hardware cohort first, then batches the counterpart Apple
  Silicon or CUDA Linux full-suite run at phase closure
- the auxiliary routed-prefix checks require the live Harbor, MinIO, and Pulsar upstream
  responses on the shared edge

## Current Status

- the implemented lane matrix is host-native `apple-silicon`, outer-container `linux-cpu` on
  native Linux, and real-cluster `linux-gpu`
- the routed auxiliary checks below describe current behavior precisely: `/harbor`, `/minio/s3`,
  and `/pulsar/ws` publication is required through the live upstream services only
- the implemented lifecycle progress surface now persists the active phase, child operation, and
  heartbeat in `cluster status` while supported `cluster up` or `cluster down` work is still in
  flight
- active phase docs record hardware-cohort residuals explicitly when one machine has validated and
  the counterpart Apple Silicon or CUDA Linux closure batch remains

## Validation Layers

- `infernix docs check` validates governed docs, README or plan cross-references, required CLI
  registry coverage in `documents/reference/cli_reference.md`, phase-document documentation
  sections, and forbidden legacy-doctrine phrases
- `infernix test lint` validates repository hygiene, required chart or Kind or `.proto` assets, the
  repo-owned Haskell style stack, the Haskell build path, and the shared Python adapter quality
  gate via `poetry run check-code` from the shared `python/` project when adapters are present;
  the Haskell style layer also rejects forbidden frontend, coordinator, auth, object-presign, or
  WebSocket imports from the engine runtime modules and rejects upward demo/runtime/auth/object or
  WebSocket imports from the Phase 7 shared-library helpers
- `infernix test unit` validates generated catalog counts and selection rules, demo-config encode
  or decode behavior, cache lifecycle, the
  protobuf-over-stdio Python worker path and adapter-command overrides, chart image or claim
  discovery, Harbor overlay emission, and the current PureScript generated-contract and SPA
  view-model behavior via `spago test` driven by the maintained runner in `web/test/Main.purs`
- `infernix test integration` validates cluster lifecycle for the active generated substrate,
  generated demo-config publication, routed demo or tool surfaces, routed inference plus cache
  endpoints, service-path request or result publication through the active topic contract,
  `cluster status`, every generated active-mode catalog entry from the mounted demo config,
  demo-ui disablement on the `linux-cpu` lane via
  `infernix internal materialize-substrate linux-cpu --demo-ui false`, and edge-port rediscovery
  on the host-native `apple-silicon` lane
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

- Work that is naturally Apple-owned validates locally with the Apple host-native bootstrap and
  direct `./.build/infernix` commands, then queues the CUDA Linux cohort for the next phase
  closure batch.
- Work that is naturally Linux, CUDA, chart, or outer-container owned validates locally with the
  `linux-gpu` bootstrap and Compose-launched `infernix`, then queues the Apple Silicon cohort for
  the next phase closure batch.
- The counterpart cohort runs after a coherent phase slice is ready, not after every small sprint.
- Full phase closure requires both cohorts to run the relevant complete gates against the same
  phase state; one cohort passing leaves an explicit residual instead of silently claiming full
  cross-hardware evidence.
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

## Active-Mode Coverage Rules

- unit coverage proves generated catalog shape, selected engine metadata, request-shape helpers,
  publication-summary rendering, and object-reference result formatting for the active generated
  contract module
- `infernix test integration` serializes the active staged substrate into the generated demo config and
  publication state, then validates the routed demo API, auxiliary routed prefixes, every
  generated active-mode catalog entry, cache mutation endpoints, and the daemon request or result
  loop for the active substrate
- `infernix test integration` also validates `cluster status`, `cluster down`, and repeated
  `cluster up` behavior for the active substrate
- `infernix test integration` also validates the routed `GET /api/cache`,
  `POST /api/cache/evict`, and `POST /api/cache/rebuild` contract against manifest-backed durable
  state
- `infernix test integration` also validates that `/harbor`, `/minio/s3`, and `/pulsar/ws`
  resolve through the shared routed surface through the live Harbor, MinIO, and Pulsar upstreams
- the target `/pulsar/ws` contract remains specific: the public prefix rewrites to Pulsar's real
  `/ws` upstream context root so routed `/pulsar/ws/v2/...` requests terminate on the WebSocket
  servlet
- `infernix test integration` validates the service loop by publishing a typed request through the
  configured topic helper and asserting a matching typed result appears on the configured result
  topic
- `infernix test integration` also validates the publication and status handoff metadata for the
  active coordinator-to-engine path: routed publication JSON carries the configured
  `hostInferenceBatchTopic`, `cluster status` carries `publicationHostInferenceBatchTopic` when
  present, and the generated demo config routes coordinator request topics to the engine batch
  topic without an engine self-forward loop
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
  error validation, real-Keycloak-JWT `/api/objects` grant validation, same-user routed presigned
  MinIO PUT/GET byte equality, cross-user object-prefix isolation, and the routed download-grant
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
- changing the active staged substrate changes the generated catalog and therefore the exercised entry
  set automatically

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
  handoff, cross-user presigned URL negative, chaos tests (WS pod kill, dispatcher kill, engine
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
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
