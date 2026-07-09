# Phase 6: Validation, E2E, and HA Hardening

**Status**: Done — Sprints 6.36 (real-output + matrix validation hardening) and 6.37 (apple-silicon memory-bounded validation lane, unblocked by Phase 4 Sprint 4.26 admission control) are implemented, documented, and validated. Wave R closed the Apple cohort on 2026-07-08: the 16-model per-model `test integration` all `status=completed` with zero OS OOM-kill, and `test e2e` ran the routed per-model browser matrix with the `data-inline-output` real-text and catalog-completeness assertions. Wave S closed the Linux lanes on 2026-07-09: rebuilt `linux-cpu` image `sha256:cfcd0c617a70919a1d083b43dfa66e9041b215a27a176ab82c2d806a36cf7627` passed `./bootstrap/linux-cpu.sh test`, and rebuilt `linux-gpu` image `sha256:31e076d62e5aab45d0f0894fcac86e634f1850aa46ae4611258f8ae3fab2ad66` plus engine images `pytorch` `sha256:978779650affd4490b16913216fed83c7f942112da23d152eb1acd58b26b1585`, `diffusers` `sha256:5643d7fdd17e599503328f6476d3a4d8dc1cc8d65c751fa2a1abaa5960ee25a0`, and `vllm` `sha256:9be7ac2a614e235bcb346e4f9e4ff0433e7183bed7cfc170501d86d13ea21a61` passed `./bootstrap/linux-gpu.sh test` with integration PASS and routed Playwright `15/15`. The prior Wave O MT3 reopen (Sprint 6.35) is closed — proven by Wave P (2026-07-04).
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/development/no_env_vars.md](../documents/development/no_env_vars.md)

> **Purpose**: Define the supported static-quality and single-substrate validation contract for the
> one-binary role topology, the README-matrix-driven integration suite, the Pulsar-driven production
> inference surface, the demo UI host, the substrate-generated catalog, the mandatory HA behavior
> of Harbor, MinIO, operator-managed PostgreSQL, and Pulsar, and the repository-hardening plus
> false-negative-doctrine closure that keeps governed root docs,
> route-aware docs, and the CLI surface mechanically aligned with implementation.

## Phase Status

> **Realness reopen (fail-closed real-only validation).** The audit behind the Phase 4 realness
> reopen also established that this phase's suites accept fabricated results: `assertResultFamilyContract`
> checks shape/extension only and never fetches an artifact (the "deeper byte/dimension checks on cohort
> hardware" comment is unimplemented), the per-row inputs are degenerate (silence WAV, 1×1 PNG), the OMR
> row is fed `musicXmlBuffer()` instead of a score image, and `validateServiceRuntimeLoop` /
> `assertCompletedResultPayload` assert neither completion nor shape. Phase 6 therefore **reopened**
> Sprint 6.33 to strengthen the HA / chaos / service-loop assertions so they fail closed on a
> non-real or incomplete result. The machine-independent realness lint that mechanically forbids
> fabrication is owned by Phase 0 (governance, Sprint 0.12); the real per-family fixtures, the OMR
> input-type fix, and the fail-closed per-row int/e2e are owned by Phase 4 (Sprint 4.23); this phase
> builds on both rather than re-owning them. Realness is guaranteed by the engine code (reopened Phase 4
> / Phase 1); the tests trust the result and fail loudly on `status=failed`. The Linux gate is [Wave K](cohort-validation-waves.md) (`linux-gpu` + `linux-cpu`);
> the same DRY suite re-runs on `apple-silicon` under [Wave L](cohort-validation-waves.md) (reopened
> Phase 1), which closed on 2026-06-29.

> **Common-shape reopen (single-accelerator phasing).** Phase 6 reopens to adopt the
> **single-accelerator-per-phase** rule (see [README.md](README.md) → Common-Shape
> Reopen and [development_plan_standards.md](development_plan_standards.md) §Q): each
> accelerator-bearing phase validates **one** of `apple-silicon` or `linux-gpu` plus
> `linux-cpu`, never both, and cross-accelerator coverage is a `linux-cpu`-only
> aggregation phase. The prior "two-axis / batch-both-cohorts" framing and
> `cohort-validation-waves.md` are repurposed into per-accelerator attestation
> ledgers, recorded in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

> **Audit follow-on reopen (lint coverage and no-env closure).** Phase 6 reopened Sprint 6.34 after
> the June 2026 audit found that docs lint did not include several authoritative docs or Phase 7 plan
> docs, and that pre-manifest / lint-owning code carried env/PATH exceptions:
> `Setup.hs` reads `PATH` / `INFERNIX_BUILD_ROOT` and calls `setEnv`, `bootstrap/common.sh` accepts
> inherited `BOOTSTRAP_*` command overrides, `src/Infernix/Lint/HaskellStyle.hs` invokes bare `cabal`,
> and `web/scripts/install-purescript.mjs` invokes bare `mktemp` / `tar`. The target doctrine remains
> no env vars and no ambient `PATH`; Sprint 6.34 is now closed. `Setup.hs` no longer reads
> `INFERNIX_BUILD_ROOT` or inherited `PATH`, and its sole environment mutation is the mechanically
> allowed deterministic `Env.setEnv "PATH"` shim required by Cabal/proto-lens setup. Bootstrap command
> constants no longer inherit `BOOTSTRAP_*` or `PATH`, Haskell-style Cabal invocations resolve through
> `HostConfig` or fixed candidates, the PureScript compiler installer uses Node tar/gzip handling, and
> docs lint now covers the authoritative configuration/tool/realness docs plus Phase 7.

> **MT3 catalog-validation reopen (closed).** Phase 6 reopened Sprint 6.35 after the 2026-06-30
> catalog replacement added `music-mt3-infer` and `music-mr-mt3` to the generated substrate
> catalogs. The integration and routed Playwright suites enumerate the active catalog, so the
> code-side coverage surface covers the new rows. The post-replacement full-suite evidence closed
> under [Wave O](cohort-validation-waves.md) and was proven by [Wave P](cohort-validation-waves.md)
> (2026-07-04): both `linux-gpu` and `linux-cpu` full `infernix test all` are GREEN with routed
> Playwright 9/9 over the expanded catalog, including the 27 GB `video-wan21-t2v` row after Phase 8
> eager model-cache staging.

Phase 6 is `Done` for Wave Q Sprint 6.36 (real-output and matrix validation hardening, opened
2026-07-06) and Sprint 6.37 (apple-silicon memory-bounded validation lane); the prior Wave O MT3 reopen (Sprint 6.35) is closed, proven by Wave P (2026-07-04). It
otherwise closes around the validation entrypoints, routed coverage, governed-root-document
metadata closure, structured CLI-registry closure, route-hardening cleanup, supported bootstrap
lifecycle fixes, false-negative doctrine, Harbor publication retry closure, daemon-role split,
and real Dhall substrate codec implemented in the current worktree. The validation entrypoints,
routed coverage, HA hardening, governed-doc closure, and CLI-registry closure are `Done` after
Apple cohort validation in Waves A/A.1/A.2/A.3, CUDA Linux cohort validation in Wave C, and the
2026-06-20 selected `linux-gpu` plus `linux-cpu` closure in Waves I and J for the then-active
catalogs. The
inference-coverage sprints were upgraded from the metadata-echo
assertion to the per-family result contract plus cohort hardware proof: the reopened Sprints 6.2,
6.3, and 6.6 assert the typed per-family result surface for every active-substrate row, and the
union across the three substrate catalogs covers every README matrix row as a mechanically checked
invariant. The
code-side closure for that coverage upgrade is complete and validated on the present CUDA Linux
host (x86_64 + RTX 5090). The assertion and harness code for these sprints —
the `ResultFamily` dispatch in the integration suite, the per-family Playwright assertions plus
per-family web-UI artifact rendering, and the `allMatrixRowIds` coverage invariant — are written and
proven by the machine-independent gate set that ran on this host (`cabal test infernix-unit`,
`cabal build test:infernix-integration`, `infernix lint docs`, `infernix lint files`). The web unit
suite (`spago`/Node 22) could not run on this bare host (host Node 18; Node 22 makes spago segfault
— an environmental toolchain limit), so its gate is exercised in the supported Linux container lane
(Node 22) / cohort batch. The real-engine integration and routed E2E assertions closed on
2026-06-20 through the Stage 2 single-accelerator gate for `linux-gpu` plus `linux-cpu`,
re-validated in [Wave I](cohort-validation-waves.md), never a per-sprint machine switch (see
[development_plan_standards.md](development_plan_standards.md) Section Q). Apple Wave L
real-engine reruns have passed the full integration layer and the focused routed Playwright gate
(`9 passed (21.1m)`), and the paired `linux-cpu` Wave L gate closed on 2026-06-29 as recorded in
[Wave L](cohort-validation-waves.md). The current CUDA Linux image strict-smokes the
runtime-backed Linux native payload layer. The final CUDA Linux closure passed full
`./bootstrap/linux-gpu.sh test` and full rebuilt-image `./bootstrap/linux-cpu.sh test`, including
integration HA checks and routed Playwright per-model matrices.
The supported test story is substrate-specific in code. Sprint 6.25 closes around the implemented split topology: cluster daemons
always run, Apple cluster daemons own request-topic consumption and derived pool-topic handoff,
Apple inference work moves through Pulsar to same-binary host daemons, and publication distinguishes
cluster daemon location from inference executor location. Sprint 6.26 closes the lifecycle-warning
cleanup: warning classification is documented, buildx support inside the Linux substrate image is
implemented, the PureScript compiler bypasses the npm installer, Spago's `glob@11` transitive
dependency is overridden to `glob@13`, and Poetry installs through an image-local virtual
environment. The Linux substrate suppresses npm update notices and leaves GHCup shell-profile
adjustment disabled; the upstream GHCup no-update message is treated as an idempotent installer
no-op, and the upstream PATH advice is accepted because the Dockerfile owns `PATH` and the
pinned toolchain succeeds. Current CUDA Linux validation closed in Wave C on the native
Linux/CUDA host.
Sprint 6.27 closes the staged-substrate format cleanup: `infernix.dhall` is a typed
Dhall record decoded in-process by the `dhall` Haskell library, the schema is reflected from the
substrate decoder type, generated files no longer carry banner-prefixed JSON, and
`cabal.project` records the supported wildcard `allow-newer` posture against the project
`ghc-9.12.4` toolchain.

The worktree carries the formatter-toolchain closure:
`src/Infernix/Lint/HaskellStyle.hs` installs `ormolu` and `hlint` through `cabal install` against
the project `ghc-9.12.4` compiler into `./.build/haskell-style-tools/bin/`, and the Linux
substrate image installs a single `ghc-9.12.4` toolchain. The supported Linux outer-container launcher keeps its build
root and chart archive cache in the image overlay, hydrates MinIO through the supported direct
tarball path instead of Docker Hub-backed OCI metadata, and repairs the known stale retained
Pulsar or ZooKeeper epoch mismatch by resetting only the Pulsar claim roots and retrying once.
Sprint 6.32 reopens validation for the engine-pool routing target: unit gates now reject illegal
pool graphs and service-consumer subscription states, while Apple integration now proves
broker-native backpressure on `Shared` pools, `Exclusive` pinned routes, and production-shape
coordinator presence when `demo_ui = false`. Linux CPU and Linux GPU/CUDA validation now prove the
pool-routing and backpressure gates required by Wave J.

## Current Repo Assessment

The repository has lint, unit, integration, and Playwright entrypoints. The canonical testing,
boundary, portability, storage, and Haskell-style docs are present, the baked Linux substrate
image definition writes the source-snapshot manifest needed for git-less `infernix lint files`
runs, the routed Playwright suite exhaustively exercises every demo-visible generated catalog
entry for the active substrate, and the integration suite enumerates every generated
active-substrate catalog entry while also carrying Harbor, MinIO, Pulsar, and Harbor PostgreSQL
recovery or lifecycle checks in code. The per-family real-output coverage upgrade for the reopened
Sprints 6.2/6.3/6.6 is code-complete and validated on the recorded CUDA Linux host: the integration
suite dispatches a per-family result contract on `ResultFamily`, the routed Playwright suite and the
web UI render and assert per-family artifact results, and `allMatrixRowIds` plus the
README-to-matrix coverage check make full README coverage a mechanically enforced invariant, and
the Wave I cohort sign-off (real-engine integration + routed E2E on hardware) for Sprints 6.2/6.3/6.6
is closed. The staged
file, `cluster status`, publication JSON, and
generated browser contracts still expose the active substrate through `runtimeMode` fields or
lines. The worktree omits direct Harbor, MinIO, and Pulsar compatibility handlers from
`src/Infernix/Demo/Api.hs`, tightens `test/integration/Spec.hs` to require the real routed
upstream behavior, persists cluster state before later Linux rollout phases, owns active
substrate preflight in the binary command, reuses a persistent Linux chart-archive cache, and
performs the targeted Pulsar claim-root reset when the known retained ZooKeeper epoch-state
corruption blocks bootstrap. The current lifecycle skips broad pre-Harbor support-image preloads
on supported lanes, may hydrate and stream only the narrow Harbor warmup dependency set into
Kind workers before Helm warmup, and follows the stricter Harbor-first boundary where only
Harbor-required services may pull upstream before Harbor is responsive.

Validation proof points are tracked by
[cohort-validation-waves.md](cohort-validation-waves.md), and historical hardware evidence lives
only in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The Apple cohort gate
is closed in Wave A/A.1/A.2/A.3, and the CUDA Linux cohort gate is closed in Wave C.

The runtime-topology implementation deploys the `infernix-coordinator` role on Apple and reports
`daemonLocation: cluster-pod` plus `inferenceExecutorLocation: control-plane-host` in publication
metadata. Linux substrates deploy both `infernix-coordinator` and `infernix-engine`; Apple sets the
cluster engine replica count to 0 because host engine daemons own Apple-native inference execution.
Pool-routing metadata is now the supported publication/status surface, and the old Apple host batch
topic metadata is absent from supported outputs. The supported routed and cluster
validation path uses real Pulsar transport; the repo-local topic spool under
`./.data/runtime/pulsar/` remains only for unit-level or intentionally endpoint-absent harness
checks and is not accepted as routed Pulsar evidence.

## Validation Surface

The supported validation entrypoints are:

- `infernix lint files`
- `infernix lint docs`
- `infernix lint proto`
- `infernix lint chart`
- `infernix docs check`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`

These commands are declarative and idempotent validation entrypoints. Re-running them rechecks the
same contract and may reconcile supported prerequisites instead of depending on alternate setup
commands.

## Current Validation Baseline

- `test unit` proves matrix typing, generated catalog rendering, and contract-generation logic
- supported `test lint` and `test unit` commands still require a staged substrate file for
  command-level execution-context validation, while their assertions remain static or unit scoped
  and do not claim real-cluster matrix coverage
- `test integration` validates the active substrate's published catalog contract, routed surfaces,
  routed inference execution for every generated active-substrate catalog entry, and the
  service-loop roundtrip through the routed Pulsar transport; on Apple it brackets the
  same-binary host daemon and waits for the service readiness marker before publishing
- `test e2e` exercises every demo-visible generated catalog entry for the active substrate
- `test all` runs every supported validation layer for the active built substrate and reports that
  substrate instead of implying cross-substrate coverage
- `test integration`, `test e2e`, and `test all` own cluster lifecycle around each test phase:
  the supported entrypoint runs `cluster down` first, executes the test action, and runs
  `cluster down` again unconditionally afterwards so reruns start from a clean cluster state
  without depending on prior operator setup

## Sprint 6.1: Static Quality Gates, Testing Doctrine, and Unit Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Files.hs`, `test/haskell-style/Spec.hs`, `test/unit/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`, `documents/engineering/storage_and_state.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the control plane, shared
contracts, and generated-catalog logic, and put the validation doctrine in canonical docs.

### Deliverables

- `infernix test lint` is the canonical static-quality entrypoint
- the repo-owned lint layer enforces whitespace, newline, tab, docs, chart, proto, and tracked-file
  policy; mounted-source Linux container runs invoke Git with a scoped
  `safe.directory=/workspace` setting so file lint validates the bind-mounted repo without global
  Git state
- the Haskell style guide clearly separates:
  - hard gates enforced mechanically
  - review guidance that remains human doctrine
  - the enforcement model implemented in `src/Infernix/Lint/HaskellStyle.hs`
- the Haskell style guide states the fail-fast rule explicitly: validation fails on hard-gate
  violations and does not silently rewrite tracked source
- `documents/engineering/testing.md` becomes the canonical testing doctrine
- `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`,
  and `documents/engineering/storage_and_state.md` are expanded so boundary, portability, and
  durability rules are canonical and testable
- `infernix test unit` remains the canonical unit-suite entrypoint for Haskell and PureScript

### Validation

- `infernix test lint` passes when repo-owned lint, docs, and compiler-warning policy are satisfied
- Haskell formatting or lint drift fails `cabal test infernix-haskell-style`
- `infernix test unit` runs both Haskell and frontend unit suites
- docs validation fails if canonical testing or boundary docs drift from the supported implementation

### Remaining Work

None.

---

## Sprint 6.2: Extensive Integration Suites [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded CUDA Linux host (x86_64 + RTX 5090) — `validateCatalogModelInference` (`test/integration/Spec.hs`) is upgraded from the model-id + runtime-mode echo to a per-family real-output result contract dispatched on `ResultFamily` (via `resultFamilyForDescriptor`): text families (LLM, speech) assert a non-empty inline continuation and no object ref; every artifact family asserts an `infernix-demo-objects/` object reference whose key extension matches the family's artifact type (`.zip` source-separation, `.mid`/`.midi` audio-to-MIDI, `.mid`/`.midi`/`.musicxml`/`.xml` music transcription, `.png` image, `.mp4` video, `.wav` audio generation, `.musicxml`/`.xml` OMR) — shape/type, never golden strings. One DRY substrate-aware suite that reads the active `.dhall` and traverses the README rows; no per-substrate suites. Proven machine-independent by `cabal build test:infernix-integration` (compiles/typechecks) and `cabal test infernix-unit`, which pass on the recorded CUDA Linux host; the assertions themselves pass only when real engines run (Section P: results name the single substrate they exercised)
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` run the per-family real-output integration suite against their own catalog columns. The selected-lane gate passed on 2026-06-20: full `./bootstrap/linux-gpu.sh test` passed style, unit, web unit, integration, and routed Playwright against the CUDA catalog, and rebuilt-image `./bootstrap/linux-cpu.sh test` passed the matching CPU lane. Current Apple integration evidence also passes cluster-up, route probes, mounted Apple substrate loading, coordinator `serviceRuntimeMode: apple-silicon`, derived Apple pool-topic routing, host engine processing, pinned Apple host-engine `Exclusive` duplicate-consumer rejection, same-machine Apple `Shared` coexistence, Apple production `demo_ui = false` assertions, and edge-port conflict rediscovery.
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Exercise the generated demo-config and service integration path on the final Kind, Helm, Harbor,
MinIO, Pulsar, and operator-managed PostgreSQL substrate.

### Deliverables

- integration coverage for `cluster up`, generated demo-config publication, and routed inference
  execution for every generated active-substrate catalog entry
- host-native integration coverage proves the routed API can keep one browser-visible entrypoint
  while Apple inference remains host-native
- dedicated `linux-gpu` integration coverage proves device-plugin rollout, GPU resources, and
  service GPU visibility
- integration coverage proves routed cache mutation and publication surfaces stay aligned with the
  generated catalog contract

### Validation

- `infernix test integration` reconciles or reuses supported cluster prerequisites
- integration tests fail when publication state, generated catalog publication, per-entry routed
  inference execution, service-loop schema publication, or CUDA scheduling assertions regress

### Remaining Work

None. The per-family integration contract and the selected `linux-gpu` plus `linux-cpu` full-suite
gates are closed on current source. Earlier CUDA Linux failure notes are preserved in
[cohort-validation-waves.md](cohort-validation-waves.md) as historical diagnostics.

---

## Sprint 6.3: Routed Playwright E2E Coverage [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded CUDA Linux host (x86_64 + RTX 5090) — the routed Playwright suite (`web/playwright/inference.spec.js`) per-model smoke matrix now asserts the per-family rendered result for every demo-visible row (text bubble vs image/audio/video/download), staying substrate-agnostic via a JS classifier `expectedResultRenderKind` (keys on model family + matrix-row metadata, never substrate id or engine binding). The web UI renders artifact results per-family: `web/src/Infernix/Web/Chat.purs` renders `inferenceResultArtifacts` as `<img>`/`<audio>`/`<video>`/download `<a>` with `data-result-artifact-kind` keyed on the object-key extension. The PureScript + Playwright code is written and `infernix lint files` passes on the recorded CUDA Linux host. NOTE: the web unit suite (`spago`) requires Node 22 and cannot run on this bare host (host has Node 18; Node 22 makes spago segfault — an environmental toolchain limit), so 6.3's web-unit gate is exercised in the supported Linux **container** lane (Node 22) / cohort batch
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` run the routed Playwright suite against their own catalog column. Full routed Linux real-output and browser evidence closed on 2026-06-20 with `./bootstrap/linux-gpu.sh test` (`9 passed`, including the 16-row GPU browser matrix) plus rebuilt-image `./bootstrap/linux-cpu.sh test` (`9 passed`, including the CPU browser matrix). Current Apple focused e2e passes 9/9 after the browser matrix uploads object fixtures for object-input model families, asserts generated artifact refs without requiring presigned media visibility, and allows a real cold Hugging Face snapshot through the 900-second bootstrap-ready envelope; the subsequent full Apple aggregate also passed lint, unit, integration, and 9/9 routed Playwright.
**Implementation**: `src/Infernix/CLI.hs`, `web/playwright/inference.spec.js`, `web/src/Infernix/Web/Chat.purs`, `web/src/Infernix/Web/Router.purs`, `web/src/Main.purs`, `web/src/index.html`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`, `web/package.json`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`

### Objective

Keep routed Playwright validation on the supported final execution paths while exercising the real
browser surface through the shared edge.

### Deliverables

- Playwright suites live under the UI-owned `web/playwright/` surface
- `infernix test e2e` exercises the routed browser surface; Phase 3 Sprint 3.10 (landed
  the recorded validation) retired the dedicated `infernix-playwright:local` image and
  `docker/playwright.Dockerfile`, baked the Playwright system packages and the three browsers
  into `docker/Dockerfile`, and moved Linux-substrate routed E2E to in-container
  `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private
  `kind` network. The Apple host-native routed-E2E executor now uses host `npm exec` with the
  same typed fixture and is covered by Apple cohort validation batches.
- the previous `INFERNIX_PLAYWRIGHT_NETWORK`, `INFERNIX_EDGE_PORT`, `INFERNIX_PLAYWRIGHT_HOST`,
  `INFERNIX_EXPECT_DAEMON_LOCATION`, `INFERNIX_EXPECT_INFERENCE_DISPATCH_MODE`, and
  `INFERNIX_EXPECT_API_UPSTREAM_MODE` env vars were retired by Sprint 3.10; the same spec covers
  every substrate by reading typed fixture data from a Dhall-decoded JSON written to the
  repo-relative `.data/runtime/playwright-fixture.json` at test setup (resolving to
  `/workspace/.data/runtime/playwright-fixture.json` inside the Linux launcher; Playwright exposes
  it as the `infernixFixture` option fixture)
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`
- E2E covers publication details, model selection, manual inference submission, and result rendering

### Validation

- `infernix test e2e` hits the routed path rather than bypassing the edge
- the routed Playwright suite fails if any active-substrate catalog entry is skipped
- Linux routed E2E runs entirely inside the active `infernix-linux-<mode>:local` launcher image
  via `docker compose run --rm infernix infernix test e2e`, which invokes
  `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private
  `kind` network (no dedicated Playwright sidecar service; `docker/playwright.Dockerfile` and the
  `infernix-playwright:local` image are removed)
- Apple host-native routed E2E runs host `npm exec` Playwright fed by the same typed
  `.data/runtime/playwright-fixture.json` against the published localhost edge port, and is covered
  by Apple cohort validation batches

### Remaining Work

- **Code (machine-independent — validated on the recorded CUDA Linux host): DONE.** The routed
  Playwright suite (`web/playwright/inference.spec.js`) now asserts the per-family rendered result
  for every demo-visible row (inline text bubble, audio player, image, video, MIDI or MusicXML
  download) while staying substrate-agnostic via the JS classifier `expectedResultRenderKind` (keys
  on model family + matrix-row metadata, never substrate id or engine binding); `infernix-demo`
  chooses the engine binding from the active `.dhall` and the browser does not branch on substrate
  id or engine family. The web UI renders artifact results per-family in
  `web/src/Infernix/Web/Chat.purs` (`inferenceResultArtifacts` rendered as
  `<img>`/`<audio>`/`<video>`/download `<a>` with `data-result-artifact-kind` keyed on the
  object-key extension). Proven by `infernix lint files`, which passes on the present CUDA Linux
  host. The web unit suite (`spago`, Node 22) cannot run on this bare host (host Node 18; Node 22
  makes spago segfault — an environmental toolchain limit), so its gate is exercised in the
  supported Linux container lane (Node 22) / cohort batch.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** asserting the real rendered
  output needs a deployed cluster; each cohort runs the routed suite against its own catalog column
  (Apple Metal with headless materialization; CUDA `linux-cpu`/`linux-gpu`).

---

## Sprint 6.4: HA Failure and Recovery Coverage For Harbor, MinIO, and Pulsar [Done]

**Status**: Done
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/chaos_testing.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Back the HA claims with concrete failure coverage.

### Deliverables

- pod-deletion and rolling-restart coverage for Harbor application-plane workloads
- durability and failover coverage for MinIO on the mandatory HA topology
- message continuity and restart coverage for Pulsar on the mandatory HA topology

### Validation

- supported HA subsets prove single-pod failure does not permanently break the supported path
- data written before MinIO or Pulsar restarts remains available afterward
- Harbor-backed image pulls continue to work after supported Harbor pod replacement

### Remaining Work

None.

---

## Sprint 6.5: Cluster Lifecycle and Environment-Matrix Validation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `compose.yaml`, `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Verify the same product contract across Apple host-native and Linux outer-container workflows.

### Deliverables

- the codebase exposes `cluster up`, `cluster status`, and `cluster down` through both execution contexts
- automated coverage proves repo-local kubeconfig, generated demo-config, publication mirror, and
  publication state creation for the active built substrate
- `cluster up` persists repo-local cluster state before later rollout phases so `cluster status`
  and supported cleanup continue to observe an in-progress Linux reconcile
- `cluster status` reports the active substrate through its current `runtimeMode` line together
  with build or data roots, publication details, and the chosen edge port
- `infernix test integration`, `infernix test e2e`, and `infernix test all` own cluster lifecycle
  around each test phase: the supported entrypoint runs `cluster down`, executes the test action,
  and runs `cluster down` again unconditionally afterwards so reruns start from a clean cluster
  state without depending on prior operator setup

### Validation

- validation closes when `infernix test integration` proves the host-native lane creates the
  expected repo-local state
- validation closes when the Linux outer-container lane reaches the cluster successfully through
  its supported path
- validation closes when repeated `cluster up` or `cluster down` behavior and `9090`-first
  edge-port rediscovery remain stable
- validation closes when supported `infernix test ...` reruns leave behind no residual cluster
  state because each phase is bracketed by `cluster down` even when the test action fails partway
  through

### Remaining Work

None for the cluster-lifecycle contract (`cluster up`/`status`/`down` validated on both execution
contexts, apple-silicon included). The **full per-model apple-silicon environment-matrix run** is not
green — it exhausts host RAM and the OS SIGKILLs the daemon; that residual is owned by Sprint 6.37
(paired with Phase 4 Sprint 4.26) and is currently red.

---

## Sprint 6.6: Generated-Catalog Exhaustive Integration and E2E Coverage Baseline [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded CUDA Linux host (x86_64 + RTX 5090) — `allMatrixRowIds` is exported from `src/Infernix/Models.hs`; `test/unit/Spec.hs` asserts that the union of `catalogForMode` across `apple-silicon`/`linux-cpu`/`linux-gpu` equals the full README matrix row set; and a README-to-matrix coverage check was added to `infernix lint docs` (`src/Infernix/Lint/Docs.hs` `validateReadmeMatrixCoverage`) asserting every catalog `referenceModel` appears in README.md. Proven by `cabal test infernix-unit` and `infernix lint docs`, which pass on the recorded CUDA Linux host. The per-family per-entry assertions ride Sprints 6.2/6.3 on cohort hardware
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` require a per-family assertion for every active-substrate catalog entry
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/Files.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`

### Objective

Make the README promise concrete for the generated-catalog coverage machinery so the later
single-substrate validation closure rests on explicit per-substrate catalog enumeration rather than
hard-coded lane lists.

### Deliverables

- `infernix test integration` enumerates every generated catalog entry from the active staged
  demo config
- `infernix test e2e` is specified to exercise every demo-visible generated catalog entry through
  the routed browser surface
- `infernix test all` aggregates lint, unit, integration, and E2E as the complete supported suite
  without silently dropping catalog entries
- the coverage machinery derives its exercised catalog from the generated substrate file instead of
  hard-coded per-lane model lists

### Validation

- changing the built substrate changes the exercised catalog and engine assertions automatically
- integration fails if any generated catalog entry is skipped
- routed E2E fails if any demo-visible generated catalog entry is skipped once Sprint 6.3 closes

### Remaining Work

- **Code (machine-independent — validated on the recorded CUDA Linux host): DONE.** `allMatrixRowIds`
  is exported from `src/Infernix/Models.hs`; `test/unit/Spec.hs` asserts that the union of
  `catalogForMode` across `apple-silicon`, `linux-cpu`, and `linux-gpu` equals the full set of
  README matrix rows; and a README-to-matrix coverage check (`src/Infernix/Lint/Docs.hs`
  `validateReadmeMatrixCoverage`) was added under `infernix lint docs` asserting every catalog
  `referenceModel` appears in README.md. Proven by `cabal test infernix-unit` and
  `infernix lint docs`, which pass on the recorded CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** requiring a per-family assertion
  for every active-substrate catalog entry rides Sprints 6.2/6.3; each cohort runs it against its
  own catalog column (Apple Metal with headless materialization; CUDA `linux-cpu`/`linux-gpu`).

---

## Sprint 6.7: Operator-Managed PostgreSQL Failure and Lifecycle Coverage [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/postgresql.md`

### Objective

Back the PostgreSQL doctrine with readiness, failover, and storage-rebind coverage.

### Deliverables

- integration coverage proves Percona and Patroni readiness for Harbor and later PostgreSQL-backed services
- HA-failure coverage deletes or restarts a PostgreSQL member and verifies failover
- lifecycle coverage proves `cluster down` plus `cluster up` reuses the same deterministic Harbor
  PostgreSQL PV inventory and host paths
- validation proves services do not regress to chart-managed standalone PostgreSQL deployments

### Validation

- `infernix test integration` verifies ready operator-managed PostgreSQL members, Patroni failover,
  and deterministic Harbor PV and host-path rebinding
- repeated cluster lifecycle validation fails if Harbor PostgreSQL no longer reuses the same
  deterministic PV inventory and host paths

### Remaining Work

None.

---

## Sprint 6.8: Minimal Host Prerequisites and Clean-Host Bootstrap Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Python.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Minimize host-side prerequisites and let `infernix` reconcile the remaining supported operator
toolchain from package managers instead of depending on a broad preinstalled Apple host stack.

### Deliverables

- Apple host-native flow reduces pre-existing host requirements to Homebrew plus ghcup before
  building `./.build/infernix`
- the earlier Apple Docker reconciliation behavior from this sprint is replaced by Phase 1
  Sprint 1.12: Docker-backed Apple work requires an already selected native arm64 Docker daemon
  and must not create or switch Docker contexts, create a Colima VM, or use cross-architecture
  emulation
- after the Apple binary exists, `infernix` can reconcile the remaining supported Homebrew-managed
  operator tools needed by the active path, including the Docker CLI, `kind`, `kubectl`, `helm`,
  and Node.js
- when Apple adapter flows first need Poetry and the `poetry` executable is absent, `infernix`
  can reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command, or reuse an
  already available compatible Python 3.12+ executable that passes the implemented version check,
  bootstrap Poetry into a user-local environment, and then continue all host-side Python
  management through the shared Poetry project
- `linux-cpu` host prerequisites stop at Docker Engine plus the Docker buildx and Compose plugins
- `linux-gpu` host prerequisites stop at the `linux-cpu` Docker baseline plus the supported
  NVIDIA driver and container-toolkit setup
- clean-host validation proves the supported commands reconcile prerequisites rather than relying on
  undocumented manual setup beyond those minimal host baselines

### Validation

These are **independent per-host clean-host prerequisite attestations** — each closes on its own
host and none is a joint accelerator gate (§Q single-accelerator: clean-host prerequisite
reconciliation is not an inference full-suite gate spanning accelerators).

**Apple clean-host lane:**

- validation closes when, on a clean Apple Silicon host with only Homebrew plus ghcup present,
  `./bootstrap/apple-silicon.sh up` builds the host binaries, materializes or verifies the active
  substrate through the binary, reconciles the remaining non-Docker Apple host prerequisites
  through the supported package-manager path, and stops at a prerequisite boundary if the current
  Docker daemon is unavailable or non-native
- validation closes when Apple host validation proves the supported flow can bootstrap Poetry when
  absent and then run the adapter setup path without manual Poetry installation

**Linux CPU clean-host lane (the always-present lane):**

- validation closes when, on a clean Linux CPU host with Docker only,
  `./bootstrap/linux-cpu.sh test` enters the Compose-launched `infernix` binary, lets the binary
  materialize or verify the active substrate, and passes the full supported validation lane

**Linux GPU clean-host lane (its own CUDA cohort host):**

- validation closes when, on a clean Linux GPU host with Docker plus the supported NVIDIA host
  prerequisites, the Linux GPU clean-host bootstrap enters the Compose-launched `infernix` binary
  through the `linux-gpu` launcher image, lets the binary materialize or verify the active
  substrate, and passes the full supported validation lane on that CUDA cohort host

### Remaining Work

None.

---

## Sprint 6.9: Governed Root-Document Metadata Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `documents/README.md`

### Objective

Close the stricter governed-root-document metadata model so the root entry documents match the
standards they already cite.

### Deliverables

- `README.md` carries the governed root-document metadata block appropriate for an orientation
  document and makes its canonical-home links explicit
- `AGENTS.md` and `CLAUDE.md` carry the explicit supersession or canonical-home markers required
  for governed entry documents and stay thin while linking to the canonical assistant-workflow
  document under `documents/`
- `documents/documentation_standards.md` describes the root-document metadata contract in the same
  terms the repo actually enforces
- the docs linter grows root-document checks strong enough to catch missing root-document metadata
  markers rather than relying on convention alone

### Validation

- `infernix docs check` fails when `README.md`, `AGENTS.md`, or `CLAUDE.md` are missing the
  required governed metadata markers for their declared role
- root docs carry the governed metadata and canonical-home links needed for the canonical
  assistant-workflow entrypoint without losing the canonical topic entrypoints

### Remaining Work

None.

---

## Sprint 6.10: True Single-Definition CLI Registry Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Lint/Docs.hs`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `test/unit/Spec.hs`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `README.md`

### Objective

Collapse the supported CLI surface into one Haskell registry so
parsing, help text, and the canonical CLI reference stop drifting independently.

### Deliverables

- one Haskell registry owns supported command parsing, help text, and
  command-family metadata
- the canonical CLI reference derives from that same registry or from a mechanically equivalent
  generated artifact rather than a separate handwritten command inventory
- `documents/reference/cli_surface.md` remains a short family overview that summarizes and links to
  the canonical CLI reference
- docs lint validates the stronger CLI-registry contract instead of only checking that registry
  command lines appear somewhere in the reference document

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command
  families from the same Haskell registry source
- changing a supported command in the registry changes parsing, help output, and CLI reference
  material through one implementation path
- `infernix docs check` fails when the CLI reference drifts from the command registry

### Remaining Work

None.

---

## Sprint 6.11: Registry-Backed Route Docs and Lint Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Routes.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Lint/Docs.hs`, `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining route or publication DRY cleanup so the Haskell route registry drives
route-aware docs and validation, not only runtime rendering and Helm values.

### Deliverables

- the Haskell route registry remains the source of truth for rendered HTTPRoutes, publication
  state, and route-aware documentation summaries
- route-oriented docs consume registry-backed rendered content or a mechanically equivalent
  generated section instead of independent handwritten route inventories
- docs lint and chart lint validate the route-aware contract from registry-backed expectations
  rather than ad hoc phrase checks
- the cleanup ledger records no remaining handwritten route-inventory or route-aware lint
  duplication once the sprint closes

### Validation

- `GET /api/publication` still reports the exact route inventory produced by the registry
- `infernix docs check` fails when a registry-owned route summary drifts from the corresponding docs
  section
- `infernix test lint` fails when route-aware lint or chart expectations diverge from the
  registry-backed route contract
- routed Harbor, MinIO, Pulsar, and demo probes continue to pass on the shared edge

### Remaining Work

None.

---

## Sprint 6.12: Assistant Workflow Canonicalization and Workflow-Helper Deduplication [Done]

**Status**: Done
**Implementation**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `src/Infernix/Workflow.hs`, `src/Infernix/Cluster.hs`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining REPO_DRY_CLEANUP follow-ons for assistant-facing root guidance and shared
workflow-helper closure.

### Deliverables

- repo-level assistant workflow doctrine moves into one canonical governed document under
  `documents/`
- `AGENTS.md` and `CLAUDE.md` become thin governed entry docs that summarize and link to that
  canonical assistant-workflow doc instead of carrying long parallel rule sets
- `src/Infernix/Workflow.hs` owns shared web-dependency readiness, npm invocation resolution,
  platform-command availability checks, and shared generated-file banner constants; cluster and CLI
  paths reuse it instead of re-declaring their own readiness probes
- the cleanup ledger no longer tracks duplicated assistant guidance or duplicated web-dependency
  readiness logic once the sprint closes

### Validation

- `infernix docs check` fails if the canonical assistant-workflow doc or the root-doc links drift
- `rg -n "webBuildToolchainPresent|ensureWebBuildDependencies" src/Infernix` shows one supported
  readiness implementation path rather than parallel cluster-local copies
- supported CLI, docs, and outer-container flows still install web dependencies through the shared
  helper

### Remaining Work

None.

---

## Sprint 6.13: Engineering Doctrine Depth and Haskell Guide Completion [Done]

**Status**: Done
**Implementation**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `documents/documentation_standards.md`

### Objective

Finish the remaining `mattandjames`-inspired doctrine-depth work so the broad engineering docs and
the Haskell guide match the stronger structure already required by
`development_plan_standards.md`.
That import is explicitly about repository governance and doctrine shape, not about adopting
`mattandjames` product-specific features or runtime assumptions.

### Deliverables

- broad governed engineering docs that define supported contracts add the stronger structure from
  `development_plan_standards.md`: `TL;DR` or `Executive Summary` when the topic is broad,
  explicit `Current Status` notes when current behavior and target direction mix, and explicit
  `Validation` sections when tests or lint prove the contract
- `documents/engineering/implementation_boundaries.md` gains an ownership matrix for Haskell,
  Python, chart, and generated surfaces together with adapter-local-versus-shared-contract type
  boundaries, instance placement rules, and module-boundary doctrine
- `documents/engineering/storage_and_state.md` gains an owner or durability table plus
  failure-mode, rebuild, and cleanup rules for durable and derived state
- `documents/engineering/portability.md` explicitly separates portable platform invariants from
  local harness detail and names which differences are supported product contract versus substrate
  implementation detail
- `documents/engineering/testing.md` keeps the canonical testing doctrine in the stronger
  structure and explicitly calls out preflight expectations, unsupported paths, and per-layer
  validation obligations
- `documents/development/haskell_style.md` points directly at `src/Infernix/Lint/HaskellStyle.hs`,
  separates repository hard-gate inputs from editor-only guidance, and adds review doctrine for
  module shape, function shape, effect-boundary clarity, and typed control flow
- the plan states explicitly that this `mattandjames`-derived follow-on imports repository
  governance, CLI, launcher-boundary, and doctrine-structure practices only; it does not adopt
  offline-browser or Keycloak flows, a single-runtime `llama-server` model, IndexedDB-specific
  docs, checked-in generated PureScript policy, or a container-only execution rule
- `src/Infernix/Lint/Docs.hs` enforces the required broad-doctrine sections for the docs whose
  structure is part of the supported contract

### Validation

- `infernix docs check` fails when the named doctrine docs lose their required
  summary-or-current-status-or-validation structure or contradict their enforced metadata contract
- `infernix test lint` passes with the deeper doc structure and Haskell-guide references in place
- `cabal test infernix-haskell-style` remains the implementation-aligned
  Haskell style gate described by the guide

### Remaining Work

None.

---

## Sprint 6.14: Monitoring Stance Resolution and Final Doctrine Closure [Done]

**Status**: Done
**Implementation**: `documents/README.md`, `documents/engineering/testing.md`, `chart/values.yaml`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/README.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Resolve the supported monitoring stance explicitly and remove the dormant monitoring placeholder
from the supported contract.

### Deliverables

- the repository carries one explicit supported-contract decision for monitoring instead of a
  dangling placeholder
- Monitoring is not a supported first-class surface.
- governed docs and the plan say so explicitly, the dormant `victoria-metrics-k8s-stack` value is
  removed from repo-owned `chart/values.yaml`, the Haskell cluster renderer keeps only an explicit
  disabled upstream Pulsar override so generated Helm values cannot imply monitoring support, and
  the cleanup is recorded in `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
- the docs index and system component inventory point at the chosen monitoring stance so readers do
  not infer support from leftover config alone
- `src/Infernix/Lint/Docs.hs` checks that the governed docs, plan docs, and chart values stay
  aligned on the unsupported monitoring stance

### Validation

- `infernix docs check` fails if the plan, docs index, and unsupported-surface statement diverge
- `infernix docs check` fails if dormant monitoring configuration returns to `chart/values.yaml`
- the cleanup ledger records the legacy monitoring-stack placeholder

### Remaining Work

None.

---

## Sprint 6.15: Validation Warning Hygiene For PureScript And Playwright [Done]

**Status**: Done
**Implementation**: `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`, `src/Infernix/CLI.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/development/purescript_policy.md`

### Objective

Remove the known non-failing warning noise from the supported web-validation path so `test unit`,
`test e2e`, and `test all` stay future-proof and produce clean supported output.

### Deliverables

- the PureScript unit suite no longer relies on deprecated `runSpec`
- the supported Node-based PureScript test runner preserves non-zero exits without relying on the
  deprecated `runSpec` or `runSpecT` entrypoints
- the retained Playwright harness wrapper sanitizes its child-process environment and delegates to
  `infernix test e2e`, so supported runs do not pass both `NO_COLOR` and `FORCE_COLOR` and the
  Haskell CLI remains the owner of E2E lifecycle orchestration
- the Apple host-native containerized Playwright path avoids forwarding conflicting `NO_COLOR` and
  `FORCE_COLOR` values into the executor
- the governed testing docs describe the supported runner and env-sanitization posture for the web
  test path

### Validation

- `infernix test unit` passes without the PureScript `runSpec` deprecation warning
- `infernix test e2e` passes without the Node warning about `NO_COLOR` being ignored because
  `FORCE_COLOR` is set
- `infernix test all` continues to pass with the warning cleanup in place

### Remaining Work

None.

---

## Sprint 6.16: Residual Canonical-Home and Workflow-Helper Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `documents/engineering/testing.md`, `documents/development/testing_strategy.md`, `documents/README.md`, `src/Infernix/Workflow.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Lint/Docs.hs`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/engineering/testing.md`, `documents/development/testing_strategy.md`, `documents/README.md`, `documents/architecture/runtime_modes.md`, `documents/documentation_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Close the last residual DRY and canonical-topic gaps surfaced by the repo review so the runtime
model, testing doctrine, and shared workflow-helper contract stop overclaiming closure.

### Deliverables

- the root README uses the same honest runtime-language contract as the governed docs and plan:
  one Apple split-executor lane plus two containerized Linux lanes
- `documents/engineering/testing.md` remains the sole canonical testing doctrine, and
  `documents/development/testing_strategy.md` is reduced to supporting operator-detail guidance
  instead of a second authoritative canonical validation surface
- the obsolete root-level `HASKELL_CLI_TOOL.md` imported-doctrine note is removed so CLI,
  style-guide, generated-section, and non-adoption guidance lives only in governed documents and
  implementation-owned registries
- `src/Infernix/Workflow.hs` owns the demo-config generated-banner constant and
  `src/Infernix/DemoConfig.hs` consumes that shared literal instead of keeping a parallel copy
- docs lint and the cleanup ledger both record the closure so those stale guidance or duplicate
  helper surfaces do not quietly return

### Validation

- `infernix docs check` fails if the governed testing-doc metadata or purpose text reintroduce a
  second canonical testing home or if the root runtime-language contract drifts from the governed
  honest-runtime model
- `infernix test unit` continues to pass once demo-config generation and decoding consume one
  shared banner literal
- `infernix test lint` continues to pass after the ledger and docs-lint rules are updated for the
  final canonical-home cleanup

### Remaining Work

None.

---

## Sprint 6.17: Residual Compatibility-Shim Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Cache.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `documents/development/frontend_contracts.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Retire the last compatibility shims that keep obsolete result, generated-contract, and helper-registry
state alive in supported code paths so Phase 6 can close without hidden cleanup work.

### Deliverables

- `src/Infernix/Runtime.hs` and `src/Infernix/Runtime/Cache.hs` read only the supported
  protobuf-backed inference-result and cache-manifest files and stop accepting legacy
  `*.state` fallbacks
- `src/Infernix/CLI.hs` stops deleting the legacy `web/src/Infernix/Web/Contracts.purs` path
  during contract generation, leaving `web/src/Generated/Contracts.purs` as the only supported
  generated frontend-contract output
- `src/Infernix/Cluster.hs` stops removing the legacy `infernix-bootstrap-registry` container and
  `./.build/kind/registry/localhost:30001` namespace as part of supported Harbor-first bootstrap
- unit, integration, and docs validation cover the shim-free behavior, and the cleanup ledger
  records those surfaces as fully closed

### Validation

- `infernix test unit` fails if runtime result IO, cache-manifest reloads, or PureScript
  contract generation still depends on the legacy `*.state`, `default.state`, or
  `web/src/Infernix/Web/Contracts.purs` compatibility paths
- `infernix test integration` fails if the supported cluster bootstrap flow still depends on the
  legacy helper-registry cleanup shims
- `infernix docs check` fails if the plan, cleanup ledger, or supporting docs overclaim full
  closure before those compatibility surfaces are removed

### Remaining Work

None.

---

## Sprint 6.18: Remaining Broad Engineering-Doc Structure Closure [Done]

**Status**: Done
**Implementation**: `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `documents/documentation_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Close the remaining doctrine-depth gap for broad engineering contract docs so the plan stops
overclaiming full structure closure and `infernix docs check` enforces the same stronger shape
consistently across the remaining governed engineering surfaces.

### Deliverables

- `documents/engineering/build_artifacts.md` adds the stronger broad-doctrine structure expected
  by `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `documents/engineering/docker_policy.md` adds the stronger broad-doctrine structure expected by
  `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `documents/engineering/edge_routing.md` adds the stronger broad-doctrine structure expected by
  `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `src/Infernix/Lint/Docs.hs` extends its document-structure rules so `infernix docs check`
  enforces the required broad-doctrine sections for those remaining engineering docs
- the plan and governed docs claim broader engineering-doc structure closure only with the
  required docs and lint rules in place

### Validation

- `infernix docs check` fails if `documents/engineering/build_artifacts.md`,
  `documents/engineering/docker_policy.md`, or `documents/engineering/edge_routing.md` lose the
  required broad-doctrine sections
- `infernix docs check` fails if the plan or governed docs overclaim doctrine-depth closure
  without the required structure and lint enforcement
- `infernix test lint` continues to pass with the broadened docs-lint structure rules in place

### Remaining Work

None.

---

## Sprint 6.19: Single-Substrate Validation Closure and Simulation Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `web/test/run_playwright_matrix.mjs`, `docker/Dockerfile`, `test/integration/Spec.hs`, `test/unit/Spec.hs`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md`, `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`, `DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `documents/engineering/testing.md`, `documents/engineering/portability.md`, `documents/engineering/edge_routing.md`, `documents/reference/cli_reference.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Make every supported test command run its complete suite against the built and deployed substrate,
remove simulation from the supported runtime and validation contract completely, and describe
integration and E2E ownership in the final `.dhall`-driven terms.

### Deliverables

- `infernix test integration`, `infernix test e2e`, and `infernix test all` run their complete
  supported suites against the substrate encoded in the generated `.dhall`
- the supported default test story no longer runs a cross-substrate Apple or CPU or GPU matrix from
  one invocation; full substrate closure comes from restaging and rerunning the complete suite for
  each substrate
- the comprehensive model, format, and engine matrix in `README.md` is the authoritative
  integration-test coverage ledger
- one integration suite traverses those README rows or references, reads the active substrate from
  `.dhall`, chooses the corresponding engine binding for each supported row, and carries at least
  one assertion for every such row
- the repository does not maintain separate integration suites per substrate; substrate choice
  happens only through the generated `.dhall`
- Apple host-native `test integration` is launched directly from the host CLI, validates the
  cluster daemon, and manages the host inference daemon for the duration of the test when that
  daemon is needed
- Apple host-native `test e2e` is launched from the host CLI; the host-native Playwright executor
  now uses host `npm exec` fed by the same typed fixture against the published localhost edge port,
  with real execution recorded by Apple cohort validation batches
- Linux substrate test commands all run through `docker compose run --rm infernix infernix ...`,
  and those flows do not manage a host daemon because request consumption, inference, and result
  publication all run from cluster daemons
- Playwright remains substrate-agnostic at the browser layer: the browser suite does not branch on
  substrate id or engine family, and it relies on `infernix-demo` to read `.dhall` and dispatch
  the correct engine behind the routed demo API
- test results report the built substrate unambiguously and never imply matrix-wide coverage they
  did not execute
- supported runtime and validation code carry no simulated cluster, route, or generic
  inference-success fallback behavior on the supported path, and routed Pulsar checks require the
  real Gateway-backed upstream; inference assertions go through the typed adapter harness selected
  by the active substrate file. The repo-local topic spool remains a harness-only transport for
  endpoint-absent unit or isolated daemon checks
- Linux bootstrap entrypoints delegate lifecycle and test commands to the Compose-launched
  `infernix` binary, which owns active-substrate preflight so lane switches cannot reuse a stale
  staged payload

### Validation

- Apple host-native `test all` runs the full supported suite for `apple-silicon`, validates the
  cluster daemon, starts the host inference daemon as needed, and runs the host-native `npm exec`
  Playwright executor against the published localhost edge port without changing the reported
  substrate
- Linux `test all` runs the full supported suite for the built Linux substrate and runs entirely
  through the outer container launcher
- for any given built substrate, integration validation fails if a README row or reference whose
  substrate column names a real engine is not covered by at least one integration assertion using
  the engine selected from `.dhall`
- routed tool-route validation fails if Harbor, MinIO, or Pulsar probes succeed only through the
  direct `infernix-demo` compatibility payloads instead of the real Gateway-backed upstream
  surfaces
- E2E validation fails if browser-side test code branches on substrate id or engine family instead
  of relying on the demo app's `.dhall`-driven dispatch
- docs and test output fail if validation still claims Apple, CPU, and GPU coverage from one
  default matrix invocation or keeps simulation in the supported contract

### Remaining Work

None.

---

## Sprint 6.20: Haskell Style Toolchain Compatibility Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Lint/HaskellStyle.hs`, `docker/Dockerfile`, `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`
**Docs to update**: `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`, `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Restore the supported Haskell style gate on the governed bootstrap surfaces by installing
`ormolu` and `hlint` through `cabal install` against the project `ghc-9.12.4` toolchain into
`./.build/haskell-style-tools/bin/`.

### Deliverables

- `src/Infernix/Lint/HaskellStyle.hs` installs `ormolu` and `hlint` through `cabal install`
  against the project compiler into `./.build/haskell-style-tools/bin/`
- the Linux substrate image bakes the project `ghc-9.12.4` toolchain so the governed runtime
  path does not redownload it on every ephemeral container run
- the Haskell-style, CLI-reference, testing, and Docker-policy docs describe the style-gate
  bootstrap honestly
- the plan and component inventory stop overclaiming full lifecycle rerun closure before the
  supported `linux-cpu` and `linux-gpu` `test` surfaces pass again

### Validation

- `bootstrap/linux-cpu.sh test` passes on the supported outer-container path
- `bootstrap/linux-gpu.sh test` passes on the supported outer-container path
- `infernix lint docs` fails if the Haskell-style, CLI-reference, testing, or Docker-policy docs
  drift from the implemented formatter-toolchain contract

### Remaining Work

None.

---

## Sprint 6.21: Linux Bootstrap Determinism Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `compose.yaml`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md`
**Docs to update**: `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Close the last Linux bootstrap determinism gap by persisting the supported Helm dependency archive
cache across fresh outer-container invocations, removing the Docker Hub-backed MinIO OCI
indirection from that cache-fill path, and repairing the known stale retained Pulsar or
ZooKeeper epoch mismatch without requiring manual lane cleanup.

### Deliverables

- the supported Linux outer-container launcher bakes a reusable image-local cache at
  `/opt/infernix/chart/charts/` and links `/workspace/chart/charts` to it so fresh
  `docker compose run --rm infernix ...` invocations can reuse the same chart dependency archives
- `src/Infernix/Cluster.hs` stops relying on `helm dependency build` to discover the MinIO chart
  through Docker Hub-backed OCI metadata and instead hydrates the governed archive cache with the
  supported direct MinIO tarball URL together with the remaining top-level chart archives
- `cluster up` detects the known stale retained Pulsar or ZooKeeper epoch mismatch, resets only
  the retained Pulsar claim roots for the affected runtime lane, and retries once so governed
  reruns do not depend on manual local cleanup
- the governed local-development, Docker-policy, and plan docs describe the reusable chart-archive
  cache honestly instead of implying every outer-container rerun reconstructs the same dependency
  bundle from the network, and the storage plus bootstrap docs record the targeted Pulsar repair
  path as explicit durability repair rather than cache cleanup
- the final governed `linux-gpu` bootstrap lifecycle rerun passes without depending on a cached
  Docker Hub OCI allowance for the MinIO chart or manual Pulsar state cleanup. The matching
  native `linux-cpu` full-suite lifecycle rerun passed on the recorded validation.

### Validation

- `bootstrap/linux-cpu.sh doctor`, `build`, `up`, `status`, `test`, and `down` pass on the
  supported outer-container path
- `bootstrap/linux-gpu.sh doctor`, `build`, `up`, `status`, `test`, and `down` pass on the
  supported outer-container path, including the targeted Pulsar repair path when stale retained
  ZooKeeper epoch state is present
- `infernix lint docs` fails if the governed local-development, Docker-policy, storage, bootstrap,
  or plan docs drift from the supported Linux bootstrap determinism contract

### Remaining Work

None.

---

## Sprint 6.22: Apple Bootstrap Lifecycle Closure [Done]

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/common.sh`, `src/Infernix/CLI.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Python.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Workflow.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`, `docker/Dockerfile`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/assistant_workflow.md`, `documents/development/local_dev.md`, `documents/development/python_policy.md`, `documents/development/testing_strategy.md`, `documents/engineering/docker_policy.md`, `documents/engineering/portability.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the remaining Apple clean-host lifecycle gaps so the governed stage-0 entrypoint can carry a
supported Apple host through first-run tool activation, host prerequisite reconciliation,
cluster-backed validation, and teardown without relying on the earlier rerun workaround or
substrate-mismatched compatibility shims.

### Deliverables

- `bootstrap/apple-silicon.sh` stops depending on ambient `PATH` side effects to discover freshly
  installed ghcup-managed tools in the same process and instead resolves or verifies the selected
  `ghc`, `cabal`, and Homebrew `protoc` executables explicitly before direct host build handoff
- shared bootstrap helper logic defines the restartable-entrypoint rule explicitly: same-process
  tool installs continue only after the bootstrap verifies command resolution and version, while
  new-shell or reboot requirements stop with a rerun instruction for the same bootstrap command
- Apple host prerequisite reconciliation can install or verify the Homebrew-managed `python@3.12`
  formula and `python3.12` command, a user-local Poetry bootstrap, Node.js, and non-Docker
  operator tools on demand when Apple lifecycle or adapter-validation paths need them
- the Apple Docker boundary is now governed by Phase 1 Sprint 1.12: the current Docker context
  must already target a native arm64 daemon, and the supported path must stop rather than creating
  or switching Docker contexts or creating a VM
- Apple Kind lifecycle code no longer relies on unsupported host bind-mount ownership assumptions,
  does not perform broad pre-Harbor support-image preloads, preloads only Harbor-backed final
  image refs after Harbor publication, and keeps the routed demo API aligned with the active
  staged runtime mode during routed validation
- routed Apple Playwright validation runs host-native `npm exec` against the published
  `127.0.0.1:<edge-port>` edge port, so the Apple lane no longer depends on
  `host.docker.internal` or a dedicated browser container
- the Linux substrate image no longer bakes a conflicting `NO_COLOR` default back into the routed
  E2E lane
- the governed local-development, portability, Python-policy, Apple runbook, cluster-bootstrap,
  assistant-workflow, and root orientation docs describe the implemented Apple lifecycle contract
  instead of the older rerun workaround or built-in-Python bootstrap story
- the supported Apple clean-host validation lane closes without a second manual invocation after
  the first ghcup-managed `cabal 3.16.1.0` install

### Validation

- on a clean Apple Silicon host with Homebrew plus ghcup present,
  `./bootstrap/apple-silicon.sh build` reaches direct Cabal handoff on the first invocation after
  it installs or selects `cabal 3.16.1.0`
- the supported Apple lifecycle rerun closes through
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
  `status`
- on the recorded validation (legacy hardware), the supported Apple lifecycle had reran cleanly through
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down`; that
  evidence is no longer current
- legacy Apple Docker-profile compatibility evidence is not part of the current supported
  workflow contract; native-only Docker-boundary validation is tracked by Phase 1 Sprint 1.12
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C.
- the Apple bootstrap fails fast with actionable messages if the resolved ghcup-managed toolchain,
  Homebrew `protoc`, or current native arm64 Docker daemon still cannot be used in the current
  process
- the supported Apple routed Playwright lane passes without timing out on
  `host.docker.internal`, and the later substrate image rebuild does not reintroduce the prior
  `NO_COLOR`/`FORCE_COLOR` warning conflict
- `infernix lint docs` fails if the governed local-development, Python-policy, portability, or
  runbook docs drift from the implemented Apple lifecycle contract

### Remaining Work

None.

---

## Sprint 6.23: False-Negative Validation Doctrine and Documentation Closure [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/ProcessMonitor.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Close the doctrine gap that lets slow lifecycle convergence be misreported or abandoned as a hard
failure.

### Deliverables

- the governed testing and runbook docs distinguish hard failure from long-running convergence that
  is still making progress in Docker, Harbor, Harbor-backed final-image preload, or teardown
  data-sync steps
- the supported validation doctrine uses inactivity-aware language instead of elapsed-wall-time
  language alone when it describes lifecycle failure classification
- Apple and cluster runbooks describe cold-versus-warm expectations and name the concrete
  first-run phases that can take minutes without emitting steady log lines
- CLI reference docs describe the supported status or progress surfaces operators use before
  concluding that a lifecycle action actually failed
- the plan, runbooks, and testing docs had cited the recorded-validation Apple lifecycle investigation
  plus the recorded-validation split-topology reruns as proof points for the supported
  false-negative doctrine; those reruns were performed on the legacy Apple Silicon hardware and
  no longer count as current proof points. The doctrine itself, the implemented progress
  surfaces, and the docs that describe them remain accurate, but the Apple cohort re-validation
  on the new host demonstrated the same inactivity-aware behavior in Wave A.

### Validation

- `infernix lint docs` fails if the testing doctrine, Apple runbook, cluster runbook, or CLI
  reference docs drift from the supported false-negative classification contract
- the plan and governed docs describe the same long-running lifecycle phases and the same operator
  interpretation rules
- the supported Apple bootstrap lifecycle reruns cleanly through `./bootstrap/apple-silicon.sh doctor`,
  `build`, `up`, `status`, `test`, and `down` while `cluster status` reports active progress
  fields during the in-progress `up` and `down` windows
- the supported validation harness can now report timeout-while-still-progressing distinctly from
  hard lifecycle failure because the lifecycle surface exposes active phase and heartbeat data

### Remaining Work

None.

---

## Sprint 6.24: Harbor Publication Retry Hardening [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster/PublishImages.hs`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the transient Harbor Docker-push failure modes exposed by the supported Apple lifecycle when
large chart images briefly reset the registry connection during publication or when a retry would
otherwise depend on a transient target tag that no longer exists locally.

### Deliverables

- Docker pushes wait for Harbor registry readiness before every push attempt
- Harbor image publication now uses eight bounded push attempts with capped retry backoff
- repo-owned local image references are published before third-party chart dependencies so the
  locally built substrate payload cannot be displaced by later mirror work before publication
- each push attempt re-tags the source image to the target Harbor reference before pushing, so a
  retry can recover even when the prior target tag disappeared locally
- a failed push still exits successfully when the expected tag is already present or a registry
  pull proves the content became available despite the client-side push failure
- plan, testing, and runbook docs had recorded the recorded-validation Apple lifecycle proof point with
  the then-current steady-state pod count and the supported retry interpretation, plus the
  recorded-validation repo-owned-image ordering and re-tagging proof point; both proof points were on
  the legacy Apple Silicon hardware and no longer count as current evidence. The retry logic
  itself remains implemented in `src/Infernix/Cluster/PublishImages.hs`, and Apple cohort
  re-validation closed in Wave A.

### Validation

- `cabal test infernix-unit` passes on the new Apple Silicon host
- `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down` had passed
  on the recorded validation on the legacy hardware after the retry hardening; that proof point is no
  longer current
- the full `./bootstrap/apple-silicon.sh test` lifecycle had exercised the large Pulsar Harbor
  publication path, integration coverage, routed Playwright E2E, retained-state replay, and final
  cluster teardown successfully on the legacy hardware; that proof point is no longer current
- the recorded validation Apple lifecycle had validated that the repo-owned `infernix-linux-cpu:local`
  image is pushed before third-party images and remains retryable through source re-tagging on
  the legacy hardware; that proof point is no longer current
- final `./bootstrap/apple-silicon.sh status` reports `clusterPresent: False`,
  `lifecycleStatus: idle`, and `lifecyclePhase: cluster-absent`
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C.

### Remaining Work

None. Apple cohort validation closed in [Wave A](cohort-validation-waves.md), and CUDA Linux
cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.25: Cluster-Daemon and Apple Host-Inference Split [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Service.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Runtime/Pulsar.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/values.yaml`, `infernix.cabal`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md`, `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`, `DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/testing_strategy.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/portability.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `documents/tools/pulsar.md`

### Objective

Clarify and implement the final daemon-role contract: the cluster coordinator role owns Pulsar
ingress and dispatch, while the substrate decides whether the engine role runs in-cluster or in a
same-binary host daemon fed by Pulsar batches.

### Deliverables

- `cluster up` deploys the cluster coordinator role for `apple-silicon`, `linux-cpu`, and
  `linux-gpu`; Linux substrates also deploy the cluster engine role
- the role-specific chart templates expose `coordinator.replicaCount` and `engine.replicaCount`;
  Apple sets the cluster engine replica count to 0 and runs the engine role host-native
- on `linux-cpu` and `linux-gpu`, the coordinator publishes batch work, the in-cluster engine
  executes inference, and the engine publishes results
- on `apple-silicon`, the coordinator reads request topics and publishes inference work to derived
  pool/model topics
- same-binary host daemons on Apple read host-role `.dhall`, connect to Pulsar through
  auto-discovered published edge state, consume their assigned pool/member topics, execute
  Apple-native inference, and publish results back through the configured result path
- if operators explicitly scale the coordinator or engine deployments or run multiple Apple host
  executors, Pulsar subscriptions remain the ownership boundary for shared request-topic
  consumption, batch handoff, and result publication
- the staged `.dhall` distinguishes substrate, daemon role (`coordinator` or `engine`), host
  Pulsar connection mode, result topics, stable member ids, and pool/member assignments instead of
  treating Apple host execution as absence of a cluster daemon
- publication and browser-visible metadata distinguish cluster daemon location from inference
  executor location, so `daemonLocation` no longer implies that Apple lacks a cluster daemon
- Pulsar-owned topics, `Shared` pool subscriptions, `Exclusive` pinned subscriptions,
  acknowledgements, and negative acknowledgements form the ownership boundary for clean request
  handoff, inference, and result publication
- legacy plan language that says Apple `cluster up` lacks a cluster coordinator is removed

### Validation

- `infernix test unit` proves that `apple-silicon` renders both coordinator-role and host-engine
  daemon metadata
- `infernix test integration` proves that `apple-silicon` deploys the cluster coordinator,
  starts the host inference daemon when needed, moves batches through the configured Pulsar topic,
  and completes routed inference through the split executor
- Linux integration still proves that `linux-cpu` and `linux-gpu` complete request consumption,
  inference, and result publication from cluster daemons without managing a host daemon
- routed E2E readiness verifies that the browser-visible publication payload reports the cluster
  daemon and Apple host inference executor distinctly before the Playwright container exercises the
  browser surface
- docs lint fails if the plan or governed docs describe Apple cluster-daemon absence as the final
  contract
- `cabal test infernix-unit` passes on the new Apple Silicon host
- `cabal test infernix-haskell-style` passes on the new Apple Silicon host
- `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
  `status` had passed on the recorded validation on the legacy Apple Silicon hardware
  exercising the split topology; that proof point is no longer current
- the full `./bootstrap/apple-silicon.sh test` lifecycle had exercised the Apple host-batch
  topic, the host daemon, every active generated catalog entry, routed Playwright, repeated
  retained-state cluster teardown and bring-up, and final cluster teardown successfully on the
  legacy hardware; that proof point is no longer current
- Apple cohort validation closed in Waves A/A.2; CUDA Linux validation closed in Wave C.

### Remaining Work

None. Apple cohort split-topology validation closed in [Wave A/A.2](cohort-validation-waves.md),
and CUDA Linux cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.26: Lifecycle Warning Classification and Toolchain Noise Closure [Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `web/package.json`, `web/scripts/install-purescript.mjs`, `src/Infernix/Workflow.hs`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/engineering/docker_policy.md`, `documents/development/purescript_policy.md`, `documents/development/python_policy.md`, `documents/engineering/build_artifacts.md`, `README.md`, `DEVELOPMENT_PLAN/README.md`
**Docs to update**: `README.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/engineering/docker_policy.md`, `documents/development/purescript_policy.md`, `documents/development/python_policy.md`, `documents/engineering/build_artifacts.md`, `DEVELOPMENT_PLAN/README.md`

### Objective

Classify every warning observed in the supported `linux-gpu` lifecycle, eliminate warnings that the
repository owns, and document only those warning classes that currently come from upstream tools,
container-build packaging behavior, or normal Kubernetes convergence.

### Deliverables

- the cluster bootstrap runbook owns a warning-classification table that names recoverable
  lifecycle convergence, host environment failures, and toolchain warnings
- operator docs distinguish normal Harbor, MinIO, PostgreSQL, Pulsar, image-publication, preload,
  and retained-state convergence from command failure using lifecycle heartbeat and exit status
- `SystemOOM` is documented as host resource contention rather than an accepted lifecycle warning
- Docker policy records buildx as part of the supported Docker toolchain, and the substrate image
  installs `docker-buildx` for nested Compose builds
- PureScript policy records that direct npm deprecation warnings should be eliminated by migrating
  to maintained tool releases; the current implementation removes the deprecated `purescript` npm
  installer path and validates Spago 1.x with a `glob@13` override
- Python policy records that Poetry is installed into `/opt/poetry` so the substrate image no longer
  uses system pip as root
- Docker policy and the runbook record that npm update notices and GHCup shell-profile adjustment
  messages are not expected from current image builds
- the runbook explicitly documents GHCup's upstream no-update warning as accepted only when the
  pinned toolchain installs and the image build exits zero
- the runbook explicitly documents GHCup's upstream PATH advice as accepted only when the
  Dockerfile-owned `PATH` is effective in the same image build

### Validation

- `infernix docs check` passes with the warning-classification docs and plan status aligned
- a Linux substrate image refresh removes the nested Compose Bake/buildx warning
- web install/build/unit validation remains free of npm deprecation warnings after the PureScript
  compiler acquisition change and Spago `glob@13` override
- Linux substrate image build output remains free of Python root-pip warnings after the Poetry
  virtual-environment layout change
- Linux substrate image build output remains free of npm update notices and GHCup shell-profile
  adjustment messages
- supported lifecycle reruns still pass after warning cleanup and do not reclassify command failures
  as acceptable warning noise
- on the recorded validation (legacy hardware), the supported `linux-gpu` lifecycle had passed through
  `./bootstrap/linux-gpu.sh doctor`, forced `docker compose build infernix` image refresh,
  `./bootstrap/linux-gpu.sh build`, `up`, `status`, `test`, `down`, `purge`, and final `status`;
  that proof point is no longer current
- the final `./bootstrap/linux-gpu.sh test` rerun had passed Haskell style, Python checks,
  Haskell unit, PureScript unit, Haskell integration, routed Playwright E2E, retained-state
  replay, and final teardown after the substrate image copied `web/scripts/` before npm
  `postinstall`; that proof point was on the legacy Linux/CUDA host and is no longer current
- CUDA Linux cohort validation closed in Wave C with a clean `linux-gpu` full-suite lifecycle on
  the native Linux/CUDA host.

### Remaining Work

None. CUDA Linux cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.27: Real Dhall Substrate Codec Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Substrate.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Config.hs`, `src/Infernix/Models.hs`, `src/Infernix/Workflow.hs`, `src/Infernix/Types.hs`, `cabal.project`, `infernix.cabal`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/dependency_management.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace the legacy banner-prefixed JSON payload at `infernix.dhall` with a real Dhall
record while preserving the existing staged filename, generated catalog contents, daemon-role
metadata, and browser/API JSON surfaces derived from the decoded Haskell ADTs.

### Deliverables

- generated substrate materialization writes a syntactically valid Dhall record instead of JSON
- substrate readers decode through the `dhall` Haskell library and then validate the existing
  `DemoConfig` domain invariants
- the substrate decoder type records the schema for the generated substrate payload (reflected, no tracked `.dhall`)
- `cabal.project` carries the documented wildcard `allow-newer: *:base, *:template-haskell`
  dependency posture needed for the project `ghc-9.12.4` toolchain and Dhall's transitive closure
- unit coverage proves the generated payload has Dhall record syntax and still round-trips through
  the runtime decoder

### Validation

- `cabal build all:exes`
- `cabal test infernix-unit`
- `infernix lint docs`

### Remaining Work

None.

---

## Sprint 6.28: Test Fixture and Lint Gate Retirement [Done]

**Status**: Done
**Implementation**: `test/unit/Spec.hs`, `test/integration/Spec.hs`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Docs.hs`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: `documents/development/no_env_vars.md`, `documents/development/testing_strategy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Retire env-driven test isolation; land the durable lint gates that prevent future env-var or
PATH-resolved invocation regressions.

### Deliverables

- `test/unit/Spec.hs` and `test/integration/Spec.hs` replace every `setEnv`/`unsetEnv` call with
  typed fixtures or in-process fixtures. Every `getEnvironment` whole-env capture is removed from
  test code.
- `src/Infernix/Lint/HaskellStyle.hs` rejects `lookupEnv`, `getEnv`, `getEnvironment`, `setEnv`,
  and `unsetEnv` outside the remaining explicitly named non-test exceptions. After the 2026-06-06
  CLI/Files/Workflow no-env cleanup, the `envFunctionExemptedFiles` list contains only `Setup.hs`
  and the lint module itself (`src/Infernix/Lint/HaskellStyle.hs`); the `src/Infernix/Python.hs`
  and `src/Infernix/CLI.hs` rows are both gone (CLI.hs no longer performs env IO), and the closed
  CLI/Files/Workflow exemptions are recorded as Removed (2026-06-06) in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- `src/Infernix/Lint/HaskellStyle.hs` rejects any `proc "<bare-name>"` matching a known external
  tool; the non-test exemption list (`bareNameProcExemptedFiles`) now contains only
  `src/Infernix/Lint/HaskellStyle.hs` itself, and the earlier `src/Infernix/Lint/Files.hs` and
  `src/Infernix/Workflow.hs` exemptions were removed (recorded in the Completed rows of
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)).
- `src/Infernix/Lint/HaskellStyle.hs` also rejects direct `findExecutable` / `findExecutables`
  discovery outside its own forbidden-token list. `src/Infernix/Python.hs` resolves Poetry through
  `HostConfig.toolPaths.poetry` or fixed `HostTools` fallback candidates, while
  `src/Infernix/Cluster.hs` resolves `nvkind` through `HostConfig.toolPaths.nvkind` or fixed
  bootstrap fallback candidates. `Setup.hs` also avoids PATH discovery for `proto-lens-protoc` and
  uses the deterministic repo-local `.build/proto-tools/bin/proto-lens-protoc` bootstrap path.
- `src/Infernix/Lint/Docs.hs` rejects governed root and `documents/` language that reintroduces
  project-prefixed env names or shell path overrides as supported operator configuration.
- `src/Infernix/Lint/Chart.hs` rejects any `env:` block in
  `chart/templates/deployment-{coordinator,engine,demo}.yaml`.

### Validation

- The static greps and the typed lint gates themselves remain trivially re-runnable on any host:
  `rg -n "lookupEnv|getEnv|getEnvironment|setEnv|unsetEnv|withOptionalEnv|INFERNIX_DATA_ROOT|INFERNIX_PULSAR_ADMIN_URL|INFERNIX_PULSAR_WS_BASE_URL" test` must return zero matches; the
  `rg` invocation against `proc "<bare-tool>"` must return zero matches; `rg -n
  "findExecutable|findExecutables" Setup.hs src test` must return only the Haskell-style lint module's
  forbidden-token list; the Haskell-style gate must no longer exempt the test suites.
- the recorded validation (legacy hardware): `cabal build test:infernix-integration` had passed after the
  integration fixture changed from `proc "python3"` to an in-process TCP listener;
  `cabal test infernix-haskell-style` had passed after removing the test exemptions;
  `cabal test infernix-unit` had passed after updating the Compose launcher contract assertion;
  `cabal run infernix -- lint docs`, `lint files`, `lint chart`, and `lint proto` had passed
  with the docs override gate active;
  `LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu --file compose.yaml config`
  and the matching CPU compose config had rendered the expected two-bind launcher from the
  single Compose file. All of those passes were on the legacy hardware and no longer count as
  current proof points; the code paths themselves are unchanged and the same commands are
  expected to pass on the new Apple Silicon host.
- the recorded validation (legacy hardware): the governed `linux-gpu` `infernix test all` pass had been the
  real-cluster evidence for the full lint + unit + integration + Playwright E2E stack on the
  legacy Linux/CUDA host; that proof point is no longer current. CUDA Linux cohort
  `infernix test all` re-validation closed in Wave C on the native Linux/CUDA host.
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C.

### Remaining Work

None. Apple cohort lint/unit/integration validation closed in
[Wave A](cohort-validation-waves.md), and CUDA Linux cohort lint/unit/integration/`test all`
validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.29: Declarative-State Phase Prose Rewrite [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md` (prose only)
**Docs to update**: this file

### Objective

Rewrite Phase 6 prose so dated hardware proof points are replaced with present-tense
descriptions of the supported gates, and so cross-phase cleanup notes are anchored on the
canonical architecture documents.

### Deliverables

- Phase 6 Phase Status and Current Repo Assessment use present-tense vocabulary; the validation
  reset note moves to a single line referencing
  [cohort-validation-waves.md](cohort-validation-waves.md) and
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- Per-sprint Validation sections use cohort closure markers; `Wave A/A.1/A.2/A.3`
  and `Wave C` references remain as cohort closure markers.
- Sprint 6.28 `proc "<bare-name>"` and `env:` block lint descriptions stay declarative; references
  to Sprint 3.10 / 4.13 / 5.9 / 7.17 env-var cleanup work cite those sprints by name without
  reopening cleanup history inside Phase 6 prose.

### Validation

- the phase-specific lexical guard for dated hardware proof-point prose returns zero matches.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

None.

---

## Sprint 6.30: Single-Toolchain GHC 9.12.4 Closure [Done]

**Status**: Done
**Implementation**: `cabal.project`, `infernix.cabal`, `docker/Dockerfile`, `src/Infernix/Lint/HaskellStyle.hs`, `bootstrap/apple-silicon.sh`, `README.md`, `documents/engineering/dependency_management.md`, `documents/engineering/docker_policy.md`, `documents/engineering/host_tools_manifest.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: every file in `Implementation` above

### Objective

Standardize the project, the Linux substrate image, the Apple host bootstrap, the lint formatter
bootstrap, and every documentation surface on a single GHC 9.12.4 toolchain. The Linux substrate
image installs exactly one GHC; `ormolu` and `hlint` install through the same compiler the
project builds against.

### Deliverables

- `cabal.project` pins `with-compiler: ghc-9.12.4` and carries only the `allow-newer:` entries
  required for the supported dependency set.
- `infernix.cabal` declares `tested-with: ghc ==9.12.4`.
- `docker/Dockerfile`:
  - `ARG GHC_VERSION=9.12.4` is the single GHC selector.
  - the image installs and selects only `${GHC_VERSION}` through ghcup.
  - only `/opt/ghc/${GHC_VERSION}` is symlinked.
- `bootstrap/apple-silicon.sh` pins `APPLE_GHC_VERSION="9.12.4"`.
- `src/Infernix/Lint/HaskellStyle.hs`:
  - `formatterInstallArgs` is rewritten to invoke
    `cabal install ormolu hlint --installdir=./.build/haskell-style-tools/bin/ --install-method=copy --overwrite-policy=always`
    against the project compiler.
  - `installFormatterToolsWithCommand` calls `cabal` directly.
  - formatter-bootstrap errors describe the single project compiler path.
- `README.md` uses `9.12.4` in the supported toolchain sections.
- `documents/engineering/dependency_management.md`, `documents/engineering/host_tools_manifest.md`,
  `documents/engineering/docker_policy.md`, `documents/engineering/testing.md`,
  `documents/development/haskell_style.md`, and `documents/reference/cli_reference.md` describe
  the single-toolchain posture keyed on `cabal.project` and `docker/Dockerfile`.
- `DEVELOPMENT_PLAN/system-components.md` names the single `ghc-9.12.4` project toolchain.
- `DEVELOPMENT_PLAN/README.md` Phase 6 status row records Sprint 6.30 as closed.

### Validation

- `cabal build all` exits zero against GHC 9.12.4.
- `cabal test infernix-haskell-style`, `cabal test infernix-unit`, and
  `cabal test infernix-integration` all exit zero.
- `infernix test lint`, `infernix lint files`, `infernix lint docs`, `infernix lint chart`,
  `infernix lint proto` all exit zero.
- the toolchain lexical guard for unsupported compiler pins and formatter-only compiler symbols
  returns matches only inside `legacy-tracking-for-deletion.md` Completed rows.
- `docker compose --project-name infernix-linux-cpu --file compose.yaml build infernix` succeeds
  against the single-GHC substrate image.
- `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all`
  exits zero on `linux-cpu`.
- Apple cohort `./bootstrap/apple-silicon.sh up && ./.build/infernix test all` exits zero against
  GHC 9.12.4.
- The Apple cohort and CUDA Linux cohort runs are tracked in `cohort-validation-waves.md` as the
  Sprint 6.30 closure batch.

### Remaining Work

None. The four toolchain cleanup rows live in `legacy-tracking-for-deletion.md` Completed.

---

## Sprint 6.31: Matrix Drift and Headless Apple Validation Gates [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded Linux outer-container lane - `src/Infernix/Models.hs` exports `matrixRowReadmeKeys`, `src/Infernix/Lint/Docs.hs` now parses the README model matrix and fails `infernix lint docs` when a cell drifts from the generated runnable catalog, explicit residual list, or `Not recommended` state, and `test/unit/Spec.hs` proves the README lint keys are unique and cover every matrix row id. Proven by `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm ... infernix cabal run exe:infernix -- lint docs` and `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm ... infernix cabal run exe:infernix -- test unit` with live source/docs mounts.
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — the selected `linux-gpu` plus `linux-cpu` per-family full-suite reruns passed on 2026-06-20. The generated Apple Metal bridge smoke, installed `coreml-native` runtime-load smoke, recorded Apple full integration rerun, focused Apple e2e reruns, and the full Apple aggregate `./.build/infernix test all` have also passed on the Apple host for the host-routing and headless-materialization surfaces; Sprint 1.15 / Wave L records green Apple real-payload integration and focused routed Playwright evidence, plus the paired `linux-cpu` full gate closed on 2026-06-29. Linux native payload strict smoke passes in the CUDA image and the full routed service-path evidence is recorded in Wave I.
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Lint/Docs.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `README.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`
**Docs to update**: `README.md`, `documents/development/testing_strategy.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/architecture/model_catalog.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the research corrections enforceable. The docs and generated catalog must not drift on engine
recommendations, and Apple validation must prove the headless Metal/Core ML materialization lane
instead of the legacy Tart helper.

### Deliverables

- extend docs/catalog lint so README matrix cells and generated catalog cells agree on promoted,
  residual, and `Not recommended` states
- add validation that Apple headless materialization does not invoke Tart, require an unlocked
  login keychain, require `xcrun -find metal`, or install a toolchain during inference
- add integration assertions that materialization failures leave no partial final engine root and
  are redelivered or negatively acknowledged when asynchronous
- update per-family integration and routed E2E fixtures for promoted/residual cells: Apple
  CTranslate2 viability, MT3-PyTorch and MR-MT3 through `mt3-infer`, Omnizart's maintained
  PyTorch piano row, Wan Apple MPS residual, and Basic Pitch TensorFlow residual

### Validation

- `infernix lint docs` fails on README/generated-catalog engine-cell drift
- `infernix test unit` proves the exported README matrix lint keys are unique and cover every
  Haskell-owned matrix row id
- Apple cohort run records the host Metal bridge probe and one Core ML/native artifact smoke under
  the headless materialization path; the current Apple host pass records both the Metal bridge
  probe and installed `coreml-native` runtime-load smoke
- CUDA Linux cohort reruns the native engine materialization lane and per-family real-output suite
- legacy Tart references remain only in the deletion ledger or explicit historical notes; the
  generated CLI reference describes the retained Tart-free manifest materialization command

### Remaining Work

None. Wave I evidence is recorded for the selected `linux-gpu` plus `linux-cpu` gates, and the
Apple materialization/e2e/all evidence is recorded as supporting host evidence.

---

## Sprint 6.32: Engine Pool Routing Validation Gates [Done]

**Status**: Done
**Code-side closure**: Complete for unit-enforced invalid-state rejection on the present Linux
outer-container lane — generated configs and substrate decoding now reject duplicate pool/member
ids, unknown model ids, ambiguous model ownership, empty pool/member assignments, one-sided
pool/member links, raw topic-like ids, `Failover` service consumers, non-positive inflight limits,
and routable models with no eligible member. Topic derivation and service subscription selection
are covered for Apple, Linux CPU, and Linux GPU. Proven by
`./bootstrap/linux-cpu.sh build`; rebuilt-image
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test unit`;
and mounted live-source `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
`cabal run exe:infernix -- lint files/docs/proto/chart`, `cabal run exe:infernix -- docs check`,
and `cabal run exe:infernix -- test lint`. Current source also adds the real Pulsar
single-host logical `Shared` backlog harness in `test/integration/Spec.hs` and compile-validates it
on the present Linux outer-container lane with a mounted-source linux-gpu Compose launcher run of
`cabal build test:infernix-integration`; the 2026-06-16 Apple integration rerun executes it against
the live Apple Pulsar lane. The same current-source mounted linux-gpu validation also passes
`infernix test lint`, `infernix test unit`, focused `infernix lint files/docs/proto/chart`,
`infernix docs check`, and `git diff --check`. The 2026-06-16 rebuilt-image Linux CPU integration
pass exercises the Kubernetes validation side: engine-pool placement across two workers,
unique-topic `Shared` backlog/backpressure, pod replacement, node drain, anti-affinity, lifecycle
rebinding, production `demo_ui = false` publication, and pool-topic exactly-once accounting.
**Cohort gate**: Closed [Wave J](cohort-validation-waves.md) — real Pulsar integration has proved
pinned `Exclusive` duplicate-consumer rejection, same-machine Apple `Shared` subscription
coexistence, Apple single-host logical `Shared` backlog/backpressure, and Apple production
`demo_ui = false` coordinator-plus-engine-pool assertions, plus Linux CPU pool placement and
backpressure. Linux GPU/CUDA pool placement and full cohort validation closed on 2026-06-20 via full
`./bootstrap/linux-gpu.sh test` paired with rebuilt-image `./bootstrap/linux-cpu.sh test`; physical
Apple multi-host routing is hardware-deferred proof while no second Apple host is available.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs` (substrate decoder type = reflected schema; no tracked `.dhall`), `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `documents/architecture/engine_pool_routing.md`, `documents/architecture/daemon_topology.md`
**Docs to update**: `README.md`, `documents/architecture/engine_pool_routing.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`, `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the engine-pool routing contract mechanically enforceable. Invalid model placement must fail
before rollout, and scalable pools must use Pulsar backpressure rather than coordinator-side node
guessing.

### Deliverables

- generated-config and unit validation reject raw batch-topic strings in pool configuration
- unit tests reject unknown model ids, duplicate pool/member ids, routable models with no eligible
  members, and Apple host daemon startup with an unknown host id
- integration validates that `demo_ui = false` omits only demo/frontend/identity surfaces while
  retaining the coordinator and engine pools
- integration validates same-machine Apple `Shared` pool consumers can coexist on one derived
  pool/model topic
- integration validates `Shared` pool consumers with bounded permits and a backlog on one logical
  Apple member still allow free logical members on the same Apple host to receive new work
- integration validates pinned per-member routes use `Exclusive` and reject duplicate consumers
- integration validates Linux CPU Kubernetes placement and `Shared` backlog/backpressure on unique
  derived pool/model topics

### Validation

- `infernix lint docs`
- `infernix test unit`
- `infernix test integration` on the active substrate
- cohort reruns for single-host logical Apple pool behavior, Linux CPU pool placement, and Linux
  GPU/CUDA pool placement, with physical Apple multi-host proof deferred until hardware exists

### Remaining Work

None. Unit validation rejects invalid routing graphs and subscription states, and proves derived
topic/member selection for all three substrates. Wave J closed Linux GPU pool-placement and full
cohort validation on 2026-06-20, paired with rebuilt-image `linux-cpu` validation. Physical Apple
multi-host routing is tracked as hardware-deferred proof, not as a blocker for the current
single-host logical backpressure gate.

---

## Sprint 6.33: Fail-Closed HA and Service-Loop Assertions [Done]

**Status**: Done
**Code-side closure**: Complete and validated 2026-06-24 (code-side: the rebuilt `linux-cpu` image compiles
`test:infernix-integration`, with `infernix lint docs` / `test unit` / `test lint` green). Built on the
realness enforcement established by Phase 0 (the `infernix-haskell-style` realness check + the
`check-code` AST guard) and the real Linux engines + real per-family fixtures + fail-closed per-row
int/e2e owned by Phase 4, it strengthened the HA / chaos / service-loop suites so they assert a real,
completed result instead of tolerating a status-only pass (this is proven on the Linux lanes; on
apple-silicon a full per-model service-loop cannot currently assert completion because the run
OS-OOM-kills the daemon before results exist — owned by Sprint 6.37 / Phase 4 Sprint 4.26, red):
`validateServiceRuntimeLoop`
(`test/integration/Spec.hs`) now uploads the per-family input fixture and asserts completion + per-family
result shape (it previously asserted neither), and `assertCompletedResultPayload` is now family-aware via
`ConversationInferenceResultPayload.inferenceResultArtifacts` across its chaos/throughput call sites
(frontend / coordinator / engine pod replacement, engine node drain, multi-user durable throughput,
fan-in batching, fan-out). This sprint does **not** re-own the realness lint (Phase 0) or the real
per-family fixtures (Phase 4); it consumes them.
**Cohort gate**: Closed [Wave K](cohort-validation-waves.md) — `linux-gpu` + `linux-cpu`.
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/chaos_testing.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the HA / chaos / service-loop suites fail closed on a non-real or incomplete result, building on —
not duplicating — the realness enforcement (Phase 0) and the real-engine fixtures (Phase 4).

### Deliverables

- `validateServiceRuntimeLoop` asserts completion + per-family result shape
- `assertCompletedResultPayload` is family-aware across every chaos / throughput call site

### Validation

- `./bootstrap/linux-gpu.sh test` plus rebuilt `./bootstrap/linux-cpu.sh test` HA / chaos suites fail
  closed when a result is non-real or incomplete

### Remaining Work

None.

---

## Sprint 6.34: Docs-Lint Coverage and No-Env/No-PATH Enforcement Closure [Done]

**Status**: Done
**Code-side closure**: Complete 2026-06-29. `src/Infernix/Lint/Docs.hs` now includes the authoritative
configuration, no-env, host-tool, cluster-config, realness, Apple materialization, Keycloak, and Phase 7
plan docs in the governed lint set. `src/Infernix/Lint/HaskellStyle.hs` resolves formatter bootstrap and
`cabal format` through `HostConfig.toolPaths.cabal` or fixed `HostTools` candidates instead of bare
`cabal`; `HostTools.hostToolFallbackCandidates` includes the Linux launcher `/root/.ghcup/bin/{cabal,ghc}`
defaults. `Setup.hs` no longer reads `INFERNIX_BUILD_ROOT` or inherited `PATH`, resolves Cabal from fixed
absolute candidates, and keeps only the mechanically allowed deterministic `Env.setEnv "PATH"` shim for
the proto-lens custom setup. `bootstrap/common.sh`, `bootstrap/linux-cpu.sh`, and
`bootstrap/apple-silicon.sh` no longer accept inherited command overrides or inherited `PATH`, and
`web/scripts/install-purescript.mjs` extracts the PureScript archive with Node `zlib`/tar parsing instead
of bare `mktemp` / `tar`.
**Cohort gate**: Machine-independent unless bootstrap behavior changes require a clean-env lifecycle
rerun. The code-side closure changed bootstrap shell behavior but did not run a full clean-env launcher
lifecycle on this host; the shell entrypoints were syntax-checked and the machine-independent lint/unit
gates passed.
**Implementation**: `src/Infernix/Lint/Docs.hs`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/HostTools.hs`, `Setup.hs`, `bootstrap/common.sh`, `web/scripts/install-purescript.mjs`, `documents/architecture/configuration_doctrine.md`, `documents/development/no_env_vars.md`, `documents/engineering/host_tools_manifest.md`
**Docs to update**: `documents/documentation_standards.md`, `documents/architecture/configuration_doctrine.md`, `documents/development/no_env_vars.md`, `documents/engineering/host_tools_manifest.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the validation layer enforce the documented no-env/no-PATH and governed-doc coverage contracts.

### Deliverables

- expand `requiredDocs` and `phaseDocs` so every authoritative configuration, realness, tool, and
  Phase 7 document participates in `infernix lint docs`
- replace `HaskellStyle.hs` bare `cabal` invocations with manifest/fixed-candidate resolution that
  matches the host-tools doctrine
- retire `Setup.hs` process-environment mutation or document and mechanically confine any unavoidable
  Cabal setup exception outside supported runtime/configuration behavior
- remove inherited `BOOTSTRAP_*` shell command overrides or confine them to an explicit non-operator
  test harness
- replace Node bare `mktemp` / `tar` invocations with Node APIs or documented absolute tool paths
- align the host-tools manifest with the Dockerfile's `/root/.ghcup/bin/{cabal,ghc}` Linux defaults
  and the real pre-binary bootstrap tool inventory

### Validation

- `node --check web/scripts/install-purescript.mjs`
- all four bootstrap scripts (`bootstrap/common.sh` plus the three lane scripts) parse under `bash -n`
- targeted static search across `Setup.hs`, `src/`, `test/`, `web/`, `python/`, `bootstrap/`, and chart
  templates for forbidden env/PATH and bare-tool patterns; remaining hits are comments/token lists plus
  the allowed `Setup.hs` deterministic `Env.setEnv "PATH"` shim
- `cabal build all`
- `cabal build test:infernix-integration`
- `cabal test infernix-unit --test-options='--hide-successes'`
- `cabal run exe:infernix -- internal materialize-substrate apple-silicon --demo-ui true`
- `cabal run exe:infernix -- test lint`
- `cabal run exe:infernix -- lint files`
- `cabal run exe:infernix -- lint docs`
- `cabal run exe:infernix -- lint chart`
- `cabal run exe:infernix -- lint proto`

### Remaining Work

None.

---

## Sprint 6.35: Expanded MT3 Catalog Integration and E2E Gate [Done]

**Status**: Done — proven by Wave P (2026-07-04)
**Code-side closure**: Complete. The integration suite and routed Playwright suite traverse the
generated active catalog, and unit/docs lint see the expanded README/catalog matrix with
`music-mt3-infer` and `music-mr-mt3`. The PyTorch engine carries the resulting MT3 compatibility
contract: `transformers` bounded to `>=4.46,<4.50` across the CPU/CUDA/Apple groups, the real
`torch.utils.checkpoint` shim, declared `absl-py`, and no-cache MT3 generation with the
`T5Block.forward` `cache_position` wrapper. Machine-independent gates are green: Linux-image
`infernix lint docs`, Linux-image `cabal test infernix-unit`, and
`poetry --directory python run check-code`. The per-attempt image-digest failure→fix chronology
lives in [cohort-validation-waves.md](cohort-validation-waves.md).
**Cohort gate**: Closed [Wave O](cohort-validation-waves.md) → [Wave P](cohort-validation-waves.md)
(2026-07-04). Both `linux-gpu` and `linux-cpu` full `infernix test all` are GREEN with routed
Playwright `9/9` over the expanded catalog (real MIDI for both MT3 rows), including the 27 GB
`video-wan21-t2v` row once Phase 8 eager model-cache staging pre-staged the Wan weights. Apple uses
the catalog-supported PyTorch CPU binding.
**Implementation**: `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `src/Infernix/Models.hs`, `src/Infernix/Lint/Docs.hs`, `python/adapters/pytorch_python.py`, `python/engines/pytorch/pyproject.toml`
**Docs to update**: `README.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/development/demo_app_test_plan.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the post-replacement catalog proof explicit: every generated catalog row, including
`music-mt3-infer` and `music-mr-mt3`, must be exercised by integration and routed browser workflows
before the validation phase returns to `Done`.

### Deliverables

- keep README matrix, generated catalog, and docs-lint row coverage in lockstep for the two MT3 rows
- run the catalog-driven integration workflow against both new rows and fail closed on
  `status=failed`
- run the routed browser per-model workflow against both new rows through the same generated catalog
  the demo webapp exposes
- record the selected accelerator plus `linux-cpu` evidence in Wave O

### Validation

- Code-side gates: Linux-image `infernix lint docs`, Linux-image `cabal test infernix-unit`, and
  `poetry --directory python run check-code` pass.
- Cohort gate: rebuilt `./bootstrap/linux-cpu.sh test` and `./bootstrap/linux-gpu.sh test` over the
  expanded catalogs are GREEN (Wave O → Wave P), with routed Playwright `9/9` and real MIDI for both
  MT3 rows. The historical per-attempt failure→fix diagnostics are recorded in
  [cohort-validation-waves.md](cohort-validation-waves.md).

### Remaining Work

Both MT3 rows are proven: `linux-cpu` full-suite GREEN (`9/9`, 2026-07-02) and the clean `linux-gpu`
`9/9` closed by **Wave P** (2026-07-04) once Phase 8 eager model-cache staging pre-staged the
CUDA-only `video-wan21-t2v` weights. No remaining work — this sprint is closed.

---

## Sprint 6.36: Real-Output and Matrix Validation Hardening [Done]

**Status**: Done — code-side hardening landed and machine-independent-validated; Wave R proved the Apple routed per-model matrix, and Wave S proved the same substrate-agnostic browser assertions on rebuilt `linux-cpu` and `linux-gpu` full-suite lanes.
**Code-side closure**: Complete for the machine-independent-verifiable pieces (2026-07-08). Integration already asserts real, non-empty inline text for the text families and fetches every artifact row with a byte+magic-byte probe (`assertResultFamilyContract` + `assertResultObjectRefFetchable`, from Sprints 4.23/6.33). New this sprint: `Chat.purs` marks a result body with `data-inline-output="present"|"absent"` so a fabricated or empty result rendered behind the `"No inline output."` placeholder can no longer pass a real-output check; the routed browser matrix now requires `data-inline-output="present"` and rejects the placeholder for text families (defeating the fallback); and a catalog-completeness guard asserts the model-picker option set equals the published demo-config catalog (the matrix rows minus the active-mode residuals). Verified by the web unit suite (`71/71`), `node --check` on the Playwright spec, and `cabal build all` (integration compiles).
**Cohort gate**: Closed by [Wave R](cohort-validation-waves.md) and [Wave S](cohort-validation-waves.md). Apple routed Playwright was GREEN for this sprint on 2026-07-08 (`test e2e` ran the per-model browser matrix with the catalog-completeness guard + `data-inline-output` real-text assertion across all 16 apple models). Wave S then closed the rebuilt Linux lanes on 2026-07-09: `./bootstrap/linux-cpu.sh test` passed routed Playwright `15/15`, and `./bootstrap/linux-gpu.sh test` passed routed Playwright `15/15` with the browser per-model matrix completing every catalog row in 18.5 minutes.
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `web/playwright/inference.spec.js`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/testing.md`, `documents/development/demo_app_test_plan.md`

### Objective

Close the "proves less than it appears" gaps the 2026-07-06 review found in the fail-closed matrix
suites, so a shrunken catalog or an empty text result cannot pass.

### Deliverables

- **Done (prior sprints, confirmed).** Integration asserts real non-empty inline text for the text
  families and runs the per-row byte+magic-byte probe for every artifact row.
- **Done.** E2E: real-text assertion for text families via the new `data-inline-output="present"`
  marker (defeats the `"No inline output."` fallback in `Chat.purs`); a catalog-completeness guard
  (picker set equals the published catalog / matrix rows minus active-mode residuals).
- **Closed by Wave R/Wave S.** The catalog-completeness guard is the supported union check: the picker
  option set must equal the published active-substrate catalog, so active-mode residuals cannot hide a
  shrunken browser matrix. The row-14 path is real and no longer needs an xfail carve-out, and the
  integration suite owns the byte+magic-byte artifact probe for source-separation rows.
- **Done (prior sprint, confirmed).** Platform-state DOM assertions (`#runtime-mode`, `#edge-port`,
  `#control-plane-context`, `#daemon-location`, `#inference-dispatch-mode`).

### Validation

- Code-side: the web unit suite (`71/71`) compiles the `Chat.purs` change, `node --check` accepts the
  Playwright spec, and the integration suite compiles — all green (2026-07-08).
- Cohort: [Wave R](cohort-validation-waves.md) routed Playwright on Apple, and [Wave S](cohort-validation-waves.md) routed Playwright on rebuilt `linux-cpu` + `linux-gpu`.

### Remaining Work

None. The Apple routed per-model matrix (catalog-completeness guard + `data-inline-output` real-text
assertion) is **GREEN** ([Wave R](cohort-validation-waves.md), 2026-07-08), and rebuilt `linux-cpu` /
`linux-gpu` routed Playwright is **GREEN** ([Wave S](cohort-validation-waves.md), 2026-07-09).
RBAC / admin-vs-user / lifecycle / dashboard e2e is owned by
[Phase 9 Sprint 9.8](phase-9-access-control-and-monitoring.md).

---

## Sprint 6.37: Apple-Silicon Memory-Bounded Validation Lane [Done]

**Status**: Done — unblocked by Phase 4 Sprint 4.26; the memory-exhaustion classification is in the integration lane, the **Apple integration never-OOM proof is GREEN** ([Wave R](cohort-validation-waves.md), 2026-07-08: full 16-model per-model `test integration` all `status=completed`, zero OS OOM-kill), and Wave S revalidated the Linux full suites where host-RAM admission is a no-op because engines run in Kubernetes-bounded pods.
**Code-side closure**: Complete for the classification (2026-07-08). Phase 4 Sprint 4.26's admission control landed, so an over-budget apple-silicon model now publishes a clean `status=failed` instead of OS-OOM-killing the daemon. The integration lane adds `classifyAppleMemoryBoundedResult`: an over-budget model is a clean per-row `AppleMemoryBoundedFailClosed` (its message names the inference RAM budget), distinguishable from a fabricated pass (`status /= completed`) and a real engine failure; a genuinely missing result is named as the OS-OOM-kill / stall symptom. Rows that fit the budget must still complete and honor the per-family real-output contract, so behavior is unchanged on hosts where the whole catalog fits. Verified by `cabal build all` (the integration suite compiles) and `cabal test infernix-haskell-style`.
**Cohort gate**: Closed by [Wave R](cohort-validation-waves.md) apple-silicon and [Wave S](cohort-validation-waves.md) Linux. The full 16-model Apple `test integration` is **GREEN (2026-07-08)**: all 16 apple catalog models `status=completed`, **zero** OS OOM-kill, the daemon surviving every model including the heavy diffusion rows. The rebuilt Linux lanes are **GREEN (2026-07-09)**: inference runs in in-cluster engine pods, so host-RAM admission is a no-op and the full `./bootstrap/linux-cpu.sh test` / `./bootstrap/linux-gpu.sh test` suites validate the same fail-closed result handling.
**Implementation**: `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/development/demo_app_test_plan.md`, `documents/development/chaos_testing.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make the apple-silicon full per-model validation lane a first-class, memory-safe gate: with Phase 4
Sprint 4.26 admission control landed, prove the full 16-model `test integration` and the routed
per-model browser matrix either complete or fail-closed per row with **zero** OS OOM-kill.

### Deliverables

- **Done.** Memory-exhaustion classification in the apple-silicon validation lane
  (`classifyAppleMemoryBoundedResult`): an over-budget model is a clean per-row `status=failed`,
  distinguishable from a stall (missing result) or a fabricated pass; a missing result is named as the
  OS-OOM-kill symptom.
- **Done.** The full per-model Apple attestation is recorded in [Wave R](cohort-validation-waves.md);
  Linux full-suite attestation is recorded in [Wave S](cohort-validation-waves.md). The live HA/chaos
  tail ran after the fail-closed per-model step, proving the daemon survived the catalog on this host.

### Validation

- Code-side: the integration suite compiles with the classification and the style gate is green
  (2026-07-08).
- Cohort (apple-silicon, paired with Phase 4 Sprint 4.26): the full 16-model `test integration` is
  **GREEN ([Wave R](cohort-validation-waves.md), 2026-07-08)** — all `status=completed`, zero OS
  OOM-kill.
- Linux full suites: **GREEN ([Wave S](cohort-validation-waves.md), 2026-07-09)** — rebuilt
  `linux-cpu` and `linux-gpu` full `./bootstrap/* test` lanes passed integration and routed
  Playwright.

### Remaining Work

None. The apple-silicon full per-model `test integration` never-OOM proof and the routed per-model
Playwright matrix are **GREEN** ([Wave R](cohort-validation-waves.md), 2026-07-08), and the
`linux-cpu`/`linux-gpu` full suites are **GREEN** ([Wave S](cohort-validation-waves.md), 2026-07-09).
Code-side (the classification) is complete.

---

## Remaining Work

None. The MT3 catalog-validation reopen (Sprint 6.35) is **closed** — proven by
[Wave P](cohort-validation-waves.md) (2026-07-04). **Sprint 6.36** (real-output + matrix validation
hardening) and **Sprint 6.37** (apple-silicon memory-bounded validation lane) are closed by
[Wave R](cohort-validation-waves.md) and [Wave S](cohort-validation-waves.md): the
`data-inline-output` real-text marker, the catalog-completeness guard, and the integration
memory-exhaustion classification all landed and passed the full Apple, `linux-cpu`, and `linux-gpu`
validation gates.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - root-document metadata contract and canonical-home markers
- `documents/engineering/build_artifacts.md` - generated-artifact locations, build-root rules, and derived-output validation expectations
- `documents/engineering/apple_silicon_metal_headless_builds.md` - validation gates for the Tart-free Apple materialization lane
- `documents/engineering/dependency_management.md` - Cabal dependency posture for the pinned
  Haskell toolchain and the Dhall dependency closure
- `documents/engineering/edge_routing.md` - route-registry ownership, generated route summaries, and route-aware validation expectations
- `documents/engineering/testing.md` - canonical testing doctrine, core principles, preflight expectations, unsupported paths, and per-layer validation obligations
- `documents/development/testing_strategy.md` - operator workflow, matrix selection, and test-entrypoint details
- `documents/development/haskell_style.md` - hard gates, review guidance, direct enforcement-model pointer, repo-hard-gate versus editor-only guidance split, and fail-fast rule
- `documents/development/chaos_testing.md` - HA failure and recovery coverage
- `documents/development/assistant_workflow.md` - canonical repository-level assistant workflow doctrine for governed root entry docs
- `documents/engineering/implementation_boundaries.md` - ownership matrix, adapter-local versus shared-contract types, instance placement, and module-boundary rules
- `documents/engineering/portability.md` - portable invariants versus substrate-specific detail, plus explicit current-status and validation sections where target direction still appears
- `documents/engineering/storage_and_state.md` - owner or durability table, failure-mode rules, and cleanup contracts
- `documents/architecture/runtime_modes.md` - daemon-role split, derived engine-pool handoff, and host-role `.dhall` fields
- `documents/architecture/engine_pool_routing.md` - invalid-state validation, shared-pool
  backpressure, pinned-route exclusivity, and production-shape expectations
- `documents/engineering/model_lifecycle.md` - batch ownership, request handoff, and result-publication runtime contract
- no `documents/engineering/monitoring.md` exists while monitoring remains unsupported; create it
  only if monitoring becomes a supported first-class surface in a later change
- `documents/operations/cluster_bootstrap_runbook.md` - lifecycle warning classification, test
  prerequisites, and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations and cold-start lifecycle timing doctrine
- `documents/tools/postgresql.md` - PostgreSQL operator readiness and failover rules
- `documents/tools/pulsar.md` - request, batch, and result topic ownership for cluster and host daemons
- `documents/engineering/docker_policy.md` - native Apple Docker boundary, minimal Linux host
  prerequisites, and buildx expectations for nested Compose builds
- `documents/development/purescript_policy.md` - PureScript npm deprecation-warning ownership,
  compiler acquisition constraints, and Spago transitive-dependency constraints
- `documents/development/python_policy.md` - Poetry bootstrap boundary for Apple hosts and the
  Linux substrate image-local Poetry virtual-environment layout

**Product or reference docs to create/update:**
- `README.md` - orientation layer with governed root-document metadata and canonical-home links
- `AGENTS.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `CLAUDE.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/cli_surface.md` - short command-family overview that links to the canonical CLI reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations and active-substrate catalog behavior
- `documents/reference/api_surface.md` - publication metadata that distinguishes cluster daemon and inference executor location

**Cross-references to add:**
- keep [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) aligned
  when governed root-document metadata rules or canonical-home posture change
- keep [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  aligned when command-registry ownership, shared workflow-helper closure, or CLI-reference
  derivation rules change
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when runtime-honesty wording or README-matrix interpretation changes
- keep [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
  aligned when HA claims, route assumptions, or active-substrate validation rules change
- keep [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
  aligned when lifecycle progress surfaces or long-running convergence doctrine changes
- keep [system-components.md](system-components.md) aligned when testing-doctrine ownership,
  shared-helper closure, daemon-role topology, or the supported monitoring stance changes
- keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when any pending
  route-doc, route-lint, assistant-doc, workflow-helper, testing-doc, runtime-language, or
  monitoring-surface or compatibility-shim cleanup item closes
