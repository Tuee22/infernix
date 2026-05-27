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
- the active staged substrate remains the source of truth for validation scope, generated catalog
  selection, and routed demo-surface expectations
- the auxiliary routed-prefix checks require the live Harbor, MinIO, and Pulsar upstream
  responses on the shared edge

## Current Status

- the implemented lane matrix is host-native `apple-silicon`, outer-container `linux-cpu`, and
  real-cluster `linux-gpu`
- the routed auxiliary checks below describe current behavior precisely: `/harbor`, `/minio/s3`,
  and `/pulsar/ws` publication is required through the live upstream services only
- the implemented lifecycle progress surface now persists the active phase, child operation, and
  heartbeat in `cluster status` while supported `cluster up` or `cluster down` work is still in
  flight

## Validation Layers

- `infernix docs check` validates governed docs, README or plan cross-references, required CLI
  registry coverage in `documents/reference/cli_reference.md`, phase-document documentation
  sections, and forbidden retired-doctrine phrases
- `infernix test lint` validates repository hygiene, required chart or Kind or `.proto` assets, the
  repo-owned Haskell style stack, the Haskell build path, and the shared Python adapter quality
  gate via `poetry run check-code` from the shared `python/` project when adapters are present
- `infernix test unit` validates generated catalog counts and selection rules, demo-config encode
  or decode behavior, cache lifecycle, the
  protobuf-over-stdio Python worker path and adapter-command overrides, chart image or claim
  discovery, Harbor overlay emission, and the current PureScript generated-contract and SPA
  view-model behavior via `spago test` driven by the non-deprecated runner in `web/test/Main.purs`
- `infernix test integration` validates cluster lifecycle for the active generated substrate,
  generated demo-config publication, routed demo or tool surfaces, routed inference plus cache
  endpoints, service-path request or result publication through the active topic contract,
  `cluster status`, every generated active-mode catalog entry from the mounted demo config,
  demo-ui disablement on the `linux-cpu` lane via
  `infernix internal materialize-substrate linux-cpu --demo-ui false`, and edge-port rediscovery
  on the host-native `apple-silicon` lane
- `infernix test e2e` validates the routed browser surface by comparing `/api/models` to the
  generated demo config and exercising every routed catalog entry through the demo SPA
- `infernix test all` runs lint, unit, integration, and E2E in sequence as the complete supported
  suite for the active substrate
- the supported real-cluster `linux-gpu` integration and `test all` lanes also depend on enough
  host disk headroom for Kind image preload, Harbor-backed image publication, and Pulsar
  BookKeeper durability; low disk headroom can block `infernix-service` readiness after cluster
  creation even when the NVIDIA preflight passes

## Lifecycle Interpretation

- on May 15, 2026, and again on May 17, 2026, the supported Apple lifecycle reran cleanly through
  `doctor`, `build`, `up`, `status`, `test`, `down`, and final `status`; the `test all` lane
  completed split-daemon Apple inference, routed Playwright E2E, repeated retained-state cluster
  bring-up or teardown cycles, and final cleanup
- the May 13, 2026 lifecycle rerun remains the proof point that long waits in `cluster up` and
  `cluster down` can still be healthy when the lifecycle is building images, publishing them into
  Harbor, preloading them onto the Kind worker, or replaying retained state; the large Pulsar image
  publication path completed with readiness-gated bounded Docker-push retries in place, and the
  May 15, 2026 rerun validates repo-owned local image ordering plus source re-tagging before each
  bounded push retry
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
- on the `linux-cpu` lane, `infernix test integration` also validates
  `infernix internal materialize-substrate linux-cpu --demo-ui false`
- on the host-native `apple-silicon` lane, `infernix test integration` also validates
  `9090`-first edge-port rediscovery
- on the `linux-cpu` lane, `infernix test integration` also deletes a Harbor core pod and verifies
  Harbor-backed image pulls still work, replaces a MinIO pod after writing a sentinel file,
  restarts a Pulsar broker between two routed publish or result checks, deletes the Harbor
  PostgreSQL primary to verify failover, and compares the deterministic Harbor PostgreSQL PV
  inventory plus host-path mapping across `cluster down` plus `cluster up`
- `infernix test e2e` exercises every generated catalog entry exposed through the routed surface
  for the active substrate, compares `/api/models` against the serialized generated demo
  config, validates routed publication details from `/api/publication`, and fails if the demo
  SPA cannot render publication details, select a model, or submit one of those entries
- the Apple host-native routed E2E lane also fails if the clustered routed surface cannot keep
  `apiUpstream.mode = cluster-demo`, preserve one browser-visible base URL, match the Apple
  publication payload `daemonLocation = cluster-pod`, advertise
  `inferenceExecutorLocation = control-plane-host`, advertise
  `inferenceDispatchMode = pulsar-bridge-to-host-daemon`, and still complete routed manual
  inference through the cluster-daemon-to-host-daemon batch path
- the supported Linux routed E2E path uses Playwright from the substrate image with
  `npm --prefix web exec -- playwright test`; Apple host-native routed E2E uses host
  `npm exec` with the same typed fixture and awaits the Apple validation pass
- on the Linux lane, routed E2E targets the Kind control-plane DNS on Docker's private `kind`
  network instead of `host.docker.internal`
- supported Playwright launchers clear conflicting `NO_COLOR` and `FORCE_COLOR` values from the
  child environment before Playwright starts
- changing the active staged substrate changes the generated catalog and therefore the exercised entry
  set automatically

## Durable-Context Demo Validation (Phase 7)

The multi-user durable-context demo expands the validation surface across three sprints.
The authoritative test contract lives at
[demo_app_test_plan.md](demo_app_test_plan.md); this section names the layers and their
relationship to the existing entrypoints.

- **Unit layer** (Sprint 7.13, `infernix test unit`) — reducer property tests, idempotency
  dedup, `prefixHash` chain, dispatcher pure-fold rule, JWT validation edge cases, presigned
  URL minting, compacted topic projection, WS envelope codec, plus PureScript view-model tests
  scoped to patch application and rendering only. Reducer logic is exercised in Haskell, not
  in PureScript. The Haskell-side unit gate is landed; PureScript view-model tests follow the
  SPA view sprints.
- **Integration layer** (Sprint 7.14, `infernix test integration`) — real Pulsar / MinIO /
  Keycloak round-trips, producer-dedup verification across simulated dispatcher restart,
  Pulsar Failover handoff, cross-user presigned URL negative, chaos tests (WS pod kill,
  dispatcher kill, engine pod kill mid-inference, coordinator kill mid-bootstrap upload,
  concurrent model-bootstrap requests, one-engine-per-node enforcement), and the
  **multi-user throughput / fan-in batching / fan-out** test (N users × K contexts × P
  prompts on one model) asserting per-context ordering, no duplicates or losses,
  cross-context independence, batching gain, bounded p95 latency, and dedup correctness.
- **E2E layer** (Sprint 7.15, `infernix test e2e`) — Playwright flows for auth, context,
  conversation (including two-in-a-row and cancel), drafts, artifact upload/download plus
  render, preview, document handling, or download-only behavior per supported artifact class,
  generated-artifact lifecycle, multi-tab convergence, client reconstitution
  via Browser Context storage-clear, pod-failover-from-browser, plus the **per-model smoke
  matrix** driven by the active substrate's generated `.dhall` catalog (every non-`Not
  recommended` row gets one passing flow). The Playwright suite source is identical across
  `apple-silicon`, `linux-cpu`, and `linux-gpu`; substrate selection lives only in the
  generated `.dhall`.

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
