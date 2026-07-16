# Phase 5: Web UI and Shared Types

**Status**: Active — Sprint 5.11 is closed for typed inference errors in browser contracts and the
demo UI. Sprints 5.1-5.10 remain closed for their original PureScript, generated-contract, and
no-env scopes. Wave T closed on 2026-07-12 with `linux-cpu` plus the selected `linux-gpu`
accelerator.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [cohort-validation-waves.md](cohort-validation-waves.md)

> **Purpose**: Define the PureScript demo UI built with spago, the Haskell-owned frontend contract
> generator, the `purescript-spec` test framework, the cluster-resident browser SPA, and the
> generated-path cleanup that reserves `Generated/` directories for real generated outputs only.

## Phase Status

Phase 5's original PureScript demo UI, Haskell-owned browser-contract source, generated contract
path under `web/src/Generated/`, clustered demo hosting rule, container-owned routed Playwright
executor, and Phase 5.9 process-environment retirement are closed for Sprints 5.1-5.10. Sprint
5.11 is active for typed inference errors in the browser contract and demo UI.
Phase 7 extends the PureScript demo surface with the durable-context Chat, Artifacts, and Model
Picker views; the supported manual-inference path moves from a direct HTTP request/poll cycle to
WebSocket-delivered `ConversationStatePatch` deltas owned by Phase 7.

Sprint 5.11 closes the shared type boundary for runtime failures code-side: failed inference
results carry closed `InferenceError` values through the Haskell browser contracts, generated
PureScript types, WebSocket patches, and Chat rendering. `ModelMemoryLimitExceeded` is rendered from
explicit `requiredMib` and `availableMib` fields, not from a generic string or successful inline
output. Wave T's `linux-cpu` and selected `linux-gpu` routed full-suite proofs cover the live
browser capacity path.

## Current Repo Assessment

The repository ships the supported PureScript demo path: `web/src/Main.purs` and the handwritten
PureScript modules under `web/src/Infernix/Web/` own the browser SPA, `web/test/Main.purs` owns
the frontend unit suite, `src/Infernix/Web/Contracts.hs` owns the handwritten browser contract,
and `npm --prefix web run build` regenerates generated contracts and bundles the app into
`web/dist/app.js`. The generated browser contracts and SPA state still expose the active
substrate through `runtimeMode` fields. The code can honor `demo_ui = false`, and the supported
materialization path now emits that shape with `--demo-ui false`. The browser SPA now also exposes
`daemonLocation` and `inferenceDispatchMode` (`web/src/Main.purs`) alongside `runtimeMode`; the
published platform state serialized by the Haskell publication path (`src/Infernix/Models.hs`)
additionally carries `inferenceExecutorLocation`, which the integration suite asserts
(`test/integration/Spec.hs`). The routed Playwright suite (`web/playwright/inference.spec.js`)
currently asserts only `publication.runtimeMode` on the `/api/publication` payload, and the
clustered demo app closes around Apple host inference execution
without claiming cluster-resident Apple inference parity. Phase 6 Sprint 6.25 distinguishes the
always-present cluster daemon from the Apple host inference executor.

## Substrate-Driven Demo Catalog Contract

- the demo UI catalog comes only from the active substrate's generated demo catalog
- the UI does not maintain a hidden hard-coded allowlist
- the browser SPA exposes every model or workload entry present in the generated file
- substrate changes alter catalog content without changing route structure
- the generated browser contracts and routed publication payloads currently serialize the active
  substrate under `runtimeMode` field names
- the browser SPA and Playwright harness do not choose engines or branch on substrate ids;
  the `infernix` Webapp role reads the active `.dhall` and owns substrate-appropriate dispatch

## Sprint 5.1: Demo Web Application Host (PureScript) [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/`, `web/package.json`, `web/spago.yaml`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Close the current web hosting baseline while keeping one stable browser entrypoint across the
clustered routed surface on every supported substrate.

### Deliverables

- repo-owned browser application code lives under `web/src/*.purs`
- the demo HTTP host is the `infernix` Webapp role, which serves the PureScript bundle and
  exposes the demo API surface
- the `infernix-demo` workload is gated by the active generated `.dhall` `demo_ui` flag
- the shared Gateway or HTTPRoute surface routes `/` to `infernix-demo` only when the demo surface is enabled

### Validation

- the browser SPA loads through the routed surface and consumes the active generated catalog
- `cluster up` deploys `infernix-demo` through Helm when `demo_ui` is on
- when the supported materialization path stages a file with `--demo-ui false`, `/` is absent from
  the route inventory

### Remaining Work

None.

---

## Sprint 5.2: Haskell-Owned Frontend Contract Foundation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Web/Contracts.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Models.hs`, `src/Infernix/Types.hs`, `web/src/Main.purs`, `web/src/Infernix/Web/`, `web/test/Main.purs`, `infernix.cabal`, `web/package.json`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`

### Objective

Keep Haskell types authoritative and make the web build consume generated bindings rather than
hand-maintained duplicates.

### Deliverables

- the supported web build generates PureScript contract modules from Haskell-owned DTO and catalog records
- the demo application imports the generated module from `web/src/Generated/`
- generated contract modules expose the request or response types and codec helpers the frontend needs
- no handwritten duplicate request or response type layer remains on the supported path

### Validation

- repeated web builds generate the same contract module deterministically
- `infernix test unit` fails if the web build or frontend tests detect drift from the Haskell source
- the web build succeeds using only generated PureScript shared types

### Remaining Work

None.

---

## Sprint 5.3: Frontend Contract and View-Level Coverage via `purescript-spec` [Done]

**Status**: Done
**Implementation**: `web/test/Main.purs`, `web/src/Infernix/Web/`, `web/package.json`, `src/Infernix/CLI.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Use repo-owned frontend tests to verify the browser SPA stays aligned with the Haskell-owned
contract and behaves predictably.

### Deliverables

- `purescript-spec` suites cover the generated contract constants (`apiBasePath`,
  `maxInlineOutputLength`, request/result topics, `runtimeMode`) and the generated engine/model
  catalog (per-substrate counts + metadata presence); the original manual-inference view specs are
  superseded by the Phase 7 `Chat` / `Contracts` / `Artifacts` view-model specs
- frontend tests run through the CLI-owned validation surface
- the browser-independent view model asserts the generated engine/model catalog counts and metadata
  match the active substrate

### Validation

- `infernix test unit` runs `spago test` alongside Haskell unit tests
- contract tests fail when request or response shapes drift from the Haskell-owned source
- the contract/count specs fail when the generated engine/model catalog counts or metadata drift from
  the generated catalog

### Remaining Work

None.

---

## Sprint 5.4: Manual Inference SPA For Any Registered Model [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/`, `web/src/index.html`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Deliver the browser SPA for manual inference against any model in the generated catalog. Phase
7 evolves this surface into the durable-context Chat surface; the supported manual-inference
path closes through that Phase 7 contract, not a direct HTTP request/poll cycle.

### Deliverables

- model catalog browser with search or filter support
- per-model request form derived from the model's declared request contract
- submission, progress, and result views for manual inference, surfaced as a server-driven
  view model rather than as a parallel HTTP polling client
- links to large object-store-backed outputs when the service returns references rather than inline payloads

### Validation

- the UI can search, select a catalog entry, and submit a request through the supported demo
  surface
- routed Playwright coverage proves the SPA can render object-reference result links
- every registered model remains reachable through the supported demo surface

### Remaining Work

None.

---

## Sprint 5.5: Web Runtime Image and In-Substrate Playwright Executor [Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `compose.yaml`, `web/playwright/`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Bake the packaged PureScript demo bundle into the Linux substrate image and run the routed
Playwright executor from the active substrate image on Linux.

### Deliverables

- the final Linux substrate image includes the built `web/dist/` bundle, the Node toolchain needed
  to regenerate it, and the Playwright runtime used by Linux routed E2E
- routed Playwright execution runs from the active Linux substrate image; the Playwright runtime
  is baked into `docker/Dockerfile` rather than carried in a separate image or
  sidecar service
- `infernix test e2e` invokes `npm --prefix web exec -- playwright test` inside the Linux
  launcher image; Apple host-native E2E uses host `npm exec` with the same typed fixture and
  is closed in [Wave A.2](cohort-validation-waves.md)
- the chart does not deploy a separate web workload or web image
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`

### Validation

- the Linux substrate image build succeeds and carries the Playwright runtime
- Apple host-native routed E2E runner code is fixture-driven and queued for the Apple cohort
  validation batch
- Linux routed E2E passes with `npm --prefix web exec -- playwright test` invoked from the outer
  container against the routed cluster
- `rg -n 'npx playwright' README.md documents src web/package.json` returns no supported workflow references

### Remaining Work

None.

---

## Sprint 5.6: Substrate-Driven Demo Catalog and SPA Parity in PureScript [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/`, `web/playwright/inference.spec.js`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/testing_strategy.md`

### Objective

Make the browser SPA a faithful reflection of the generated catalog for the active built
substrate.

### Deliverables

- the UI catalog is derived only from the active generated demo catalog
- every generated catalog entry has a visible browser path covering request input, progress, and
  result presentation appropriate to that workload family
- rebuilding for a different substrate changes the rendered catalog without frontend code changes

### Validation

- browser-visible catalog entries match the generated demo config exactly
- removing an entry from the generated config removes it from the UI without extra frontend edits
- rebuilding for a different substrate changes catalog and engine metadata in the expected way

### Remaining Work

None.

---

## Sprint 5.7: Reserve `Generated/` For Generated Outputs Only [Done]

**Status**: Done
**Implementation**: `src/Infernix/Web/Contracts.hs`, `web/package.json`, `src/Infernix/CLI.hs`, `infernix.cabal`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Move the handwritten Haskell browser-contract module out of `src/Generated/` so `Generated/`
directories mean generated output only.

### Deliverables

- the handwritten Haskell browser-contract source moves to `src/Infernix/Web/Contracts.hs`
- the code generator, imports, and docs point at the new handwritten source location
- `src/Generated/` is no longer used for handwritten Haskell source
- `web/src/Generated/` remains the generated PureScript output location

### Validation

- `npm --prefix web run build` still regenerates the PureScript contract module successfully
- Haskell or frontend tests fail if imports or codegen paths still refer to the old handwritten module location
- no tracked handwritten Haskell source remains under `src/Generated/`; the current worktree does
  not need that directory at all

### Remaining Work

None.

## Sprint 5.8: Clustered Demo Surface on Apple and Container-Owned Playwright Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `web/playwright/inference.spec.js`, `web/src/Infernix/Web/`, `web/src/Main.purs`, `web/src/index.html`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `README.md`, `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`

### Objective

Keep the demo app clustered on Apple while making the Apple browser path explicitly host-backed
for inference execution and retaining a containerized Linux image as the only supported Playwright
executor. Under the final Phase 6 split, the browser enters the cluster daemon path first and only
the inference batch execution moves to host daemons.

### Deliverables

- the routed demo app remains cluster-resident on Apple and Linux substrates alike
- Apple host-native E2E orchestration uses host `npm exec` with the same typed fixture and is
  closed in [Wave A.2](cohort-validation-waves.md)
- Linux outer-container E2E orchestration runs `npm --prefix web exec -- playwright test` from
  inside the active substrate image
- Docker is a hard prerequisite for `infernix test e2e` on Linux substrates; the Apple branch runs
  the host-native Playwright lane through `npm exec`
- user-facing Apple docs describe `cluster up` as the way to launch the demo surface instead of a
  direct host `infernix-demo serve` workflow, while also making the routed Apple inference path
  explicitly host-backed
- Linux user-facing docs continue to describe Compose as the single launcher for demo, integration,
  and E2E workflows
- the Playwright suite and browser helpers do not branch on substrate id or engine family; they
  interact only with the routed demo surface and rely on `infernix-demo` to read `.dhall` and
  dispatch the correct engine or bridge mode
- README-level substrate instructions cover how to launch the demo app, how the always-present
  cluster daemon differs from the Apple host inference executor, how the Apple batch bridge fits
  into that story, and how E2E execution differs between Apple and Linux

### Validation

- Apple routed E2E runner code is landed and closed in [Wave A.2](cohort-validation-waves.md)
- Linux routed E2E passes through the in-substrate Playwright executor without any host daemon
  management
- Apple and Linux routed E2E pass through the same browser-visible flows without substrate-specific
  Playwright branching; only launcher or orchestration differs
- `infernix test e2e` fails fast with an actionable message when Docker, kind, kubectl, or helm
  are not available on the host
- docs validation fails if the user-facing docs still treat host `infernix-demo serve` as the final
  Apple demo-app launch story, describe browser-side substrate selection, or describe clustered
  Apple repo workloads as the final Apple inference executor

### Remaining Work

None.

---

## Sprint 5.9: Web and Python Manifest Retirement [Done]

**Status**: Done
**Implementation**: `src/Infernix/Webapp.hs`, `python/adapters/common.py`, `python/adapters/model_cache.py`, every engine adapter under `python/adapters/*.py`, `web/scripts/install-purescript.mjs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/no_env_vars.md`, `documents/development/frontend_contracts.md`, `documents/development/testing_strategy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Retire env-var consumption in the demo backend CLI, the Python adapter layer, and the web/Node
scripts. Replace `INFERNIX_BIND_HOST`, `INFERNIX_DEMO_BRIDGE_MODE`,
`INFERNIX_PUBLICATION_STATE_PATH` with `ClusterConfig.demoBackend.*` fields. Replace every
Python adapter process-environment config read with typed sources: `Path(__file__)`-anchored repo
discovery, setup `--install-root` CLI args, the protobuf `WorkerRequest` envelope, and
`ModelCacheConfig` passed through `configure()`. Hardcode `PURESCRIPT_VERSION` in
`install-purescript.mjs`. Resolve `INFERNIX_PLAYWRIGHT_INFERNIX` via typed binary candidates.

### Deliverables

- `src/Infernix/Webapp.hs` reads `bindHost`, `bridgeMode`, `publicationStatePath` from
  `ClusterConfig.demoBackend.*`; the `lookupEnv` calls are deleted.
- Haskell daemon setup invocation passes `--install-root` as a typed CLI arg and the runtime
  worker sends model metadata through the protobuf `WorkerRequest` envelope.
- `python/adapters/common.py` resolves the repo root from `Path(__file__)`, reads worker requests
  from protobuf-over-stdio, and runs `check-code` with an explicit minimal environment.
- `python/adapters/model_cache.py` reads cache, MinIO, bucket, region, and quota wiring from the
  typed `ModelCacheConfig` populated via `configure()`; every `os.environ` read is deleted.
- `web/scripts/install-purescript.mjs` hardcodes the PureScript version; `PURESCRIPT_VERSION` env
  read deleted. Operators bump by editing the script.
- `web/test/run_playwright_matrix.mjs` reads the infernix binary path from the Dhall-decoded
  playwright fixture (introduced in Sprint 3.10); `INFERNIX_PLAYWRIGHT_INFERNIX` and
  `INFERNIX_BUILD_ROOT` reads deleted.

### Validation

- `grep -rn 'os.environ' python/` returns zero matches.
- `grep -rn 'process\.env' web/scripts/ web/test/ web/playwright/` returns zero matches.
- `infernix test integration` on `linux-gpu` round-trips through the demo + adapter path
  successfully.
- `poetry run check-code`, `node --check web/test/run_playwright_matrix.mjs`,
  `node --check web/scripts/install-purescript.mjs`, and the grep gates above exit zero.
- `cabal test infernix-unit` and `cabal run infernix -- lint {docs,files,chart,proto}` exit
  zero.
- Apple cohort validation closed in Waves A/A.2; the CUDA Linux `linux-cpu` and `linux-gpu` gates
  passed on the recorded validation.

### Remaining Work

None. Apple cohort validation closed in [Wave A/A.2](cohort-validation-waves.md), and the CUDA
Linux `linux-cpu` and `linux-gpu` gates passed on the recorded validation.

---

## Sprint 5.10: Declarative-State Phase Prose Rewrite [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md` (prose only)
**Docs to update**: this file

### Objective

Rewrite Phase 5 prose so cross-phase history notes and dated hardware proof points are replaced
with present-tense descriptions of the supported shape, anchored on the canonical architecture
documents. The phase narrative carries the supported PureScript, generated-contract, and routed
Playwright contract directly.

### Deliverables

- Sprint 5.5 Deliverables describe the Playwright runtime baked into the Linux substrate image
  directly.
- Sprint 5.9 Validation prose states cohort closure declaratively and points at the owning
  cohort-validation waves.

### Validation

- the phase-specific lexical guard for dated hardware proof-point prose returns zero matches.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

None.

---

## Sprint 5.11: Typed Inference Errors in Browser Contracts and Demo UI [Done]

**Status**: Done — code-side complete and routed Wave T validation is closed on `linux-cpu` plus the
selected `linux-gpu` accelerator.
**Code-side closure**: Complete on 2026-07-09 in the Linux outer-container lane.
`src/Infernix/Web/Contracts.hs` exports typed browser-facing `InferenceError` values,
`Bridge.Result` and the WebSocket result payload carry `inferenceResultError`, generated
PureScript contracts roundtrip `ModelMemoryLimitExceeded`, and `Chat.purs` renders the capacity
message from typed fields before considering inline output. `Chat.purs` also seeds the active
conversation from an append patch when the conversation snapshot races behind it, so fast
fail-closed capacity results are not dropped by the browser state reducer, and merges later
same-context snapshots with already-seen patch messages so stale snapshots cannot erase the raced
capacity result. The routed Playwright per-model matrix now treats over-budget rows as terminal
typed capacity results: it derives the expected `ModelMemoryLimitExceeded` from
`/api/demo-config.inferenceMemoryBudget`, asserts the explicit MiB fields in the WebSocket payload,
and checks the rendered capacity message while leaving in-budget rows on the existing
success/artifact assertions. The stale-snapshot merge is validated on rebuilt Linux CPU image
`sha256:05e0aadf5ea0feb98f25e82ab196f23893be0441e59f5e91f9fec346bfa6d8c0` by
`./bootstrap/linux-cpu.sh build` and
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix
test unit` (Haskell unit plus web `75/75`). Earlier gates also passed
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix
test lint`, `infernix lint files|docs|proto|chart`, and `infernix docs check`; the routed Wave T
full-suite gate closed after the later evidence below.
**Latest Wave T evidence**: The 2026-07-10 `./bootstrap/linux-cpu.sh test` rerun on
`sha256:05e0aadf5ea0feb98f25e82ab196f23893be0441e59f5e91f9fec346bfa6d8c0` passed the full live
integration lane and the Sprint 9.9 auth/RBAC routed specs, but routed Playwright still failed before
closure: the artifact preview grant timing spec timed out, and the per-model matrix received the
typed over-budget payload but did not render the visible `.chat-message.result` capacity message.
The browser reducer/render path remains the active Sprint 5.11 residual.
**Current fix**: `ServerConversationSnapshot` handling is now active-context-scoped, with unit
coverage proving snapshots for non-active contexts cannot displace the current pane; the focused
PureScript suite passes `76/76` in the Linux CPU launcher image. The artifact routed helper also now
waits for text/JSON previews to reach their own ready marker after a download grant before asserting
preview contents. Rebuilt image
`sha256:c01a9a070ca842b973543301dcbaaa039811492f707fdc20c804aa30bd5f40ee` now passes
`./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web `76/76`; the
routed full-suite rerun then passed the artifact preview/download spec and Sprint 9.9 auth/RBAC
specs but still ended `15/16`: the matrix received the typed over-budget payload, but the visible
capacity message was absent after a context switch because the append patch applied to the previously
displayed context before the active-context snapshot arrived. Current source now requires the stored
`activeConversation` context to match before applying a patch; otherwise it seeds the active context
from that patch. Focused mounted-source PureScript validation passes `77/77`; rebuilt image
`sha256:84e3915260e5fd7684b817bf520e9eaca4f40946665d86ae2afb5276b1eedfcb` now contains this fix and
passed the `./bootstrap/linux-cpu.sh build` CLI-help smoke plus rebuilt-image `infernix test unit`
with web `77/77`. The full-suite rerun passed integration through the typed capacity path and
browser-relevant smaller-model continuity, but failed before routed Playwright on a retained Pulsar
repair retry limit in a later lifecycle cluster-up. Rebuilt image
`sha256:0bf82aba452b2bee8f5de6c4ee136c7d72537ac0dbd4377ee52ee3718d77c0aa` contains the bounded
repair-loop fix and passed `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `77/77`. Its full-suite rerun passed the front gates and full live
integration, then routed Playwright reached `15/16`: the artifact preview/download spec and Sprint
9.9 auth/RBAC specs were green, but the matrix still failed the visible capacity-message assertion
after receiving the typed terminal `ModelMemoryLimitExceeded` payload. Current source now keeps
applying patches to the already rendered context when `activeContextId` is transiently stale and
adds a raw Haskell-wire `ModelMemoryLimitExceeded` WebSocket decode regression; focused
mounted-source PureScript validation passes `79/79`. Rebuilt image
`sha256:4e2e2a9f642ecc15635df849539b82a847d350db19e161cf6517d56a29ea6b62`
contains that fix and passed `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` with web `79/79`. Its full `linux-cpu` rerun passed full live
integration and routed Playwright reached `15/16`; the sole failure remained the browser matrix
visible capacity-message assertion after receiving the typed terminal payload. Current source now
pins submitted prompts into the active conversation before fast terminal results and adds a
stale-active-id rendered-context reducer regression. Rebuilt image
`sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306`
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `80/80`. Its full `linux-cpu` rerun passed the front gates and full
live integration, then routed Playwright reached `15/16` and failed only the visible
capacity-message DOM assertion after receiving the typed terminal payload. Current source now keeps
conversations cached per context, stores inactive/stale patches without displacing the rendered
pane, and seeds restored, created, selected, and locally submitted prompt conversations into that
cache; focused mounted-source PureScript validation passes `81/81`. Rebuilt Linux CPU image
`sha256:5ccdac2c89b435c1452f63c7fc5df41ca07893bfabc581134aef95db0468ace9` contains the cache fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image `infernix
test unit` with web `81/81`. Its full rerun did not reach routed Playwright because the live
integration lane hung in the post-PostgreSQL-lifecycle `cluster up` warm-cache path; current source
bounds the MinIO warm-cache/model-bootstrap HTTP calls in `Infernix.Runtime.Pulsar`, and focused
mounted-source Haskell validation passes `cabal test infernix-unit`. Rebuilt Linux CPU image
`sha256:f0276a2efcae1fa7b2d33a7bb7a0e442b9d4c2be5687515c439f9cb75bf909ec` contains the timeout fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `81/81`. Its full `linux-cpu` rerun failed before runtime validation
on a Haskell style import-order diff in `Infernix.Runtime.Pulsar`; current source applies the
style-only reorder, and focused mounted-source validation passes `cabal test infernix-haskell-style`.
Rebuilt Linux CPU image
`sha256:5d423bd3d988103e6777fcfa80b92da07684263af056f7e6c9395e4802176cec` contains that style fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `81/81`. Its full rerun passed the front gates and the live
integration lane through typed CPU admission, HA/recovery, model-bootstrap deduplication,
throughput (`totalPrompts = 12`, `p95Seconds = 65.50490140914917`), Harbor/MinIO/Pulsar recovery,
and PostgreSQL failover before stalling in the lifecycle-rebinding second `cluster up` with a
defunct monitored Docker child. Current source fixes the monitored subprocess reaper in
`Infernix.ProcessMonitor`; focused mounted-source validation passes `cabal test
infernix-haskell-style` and `cabal test infernix-unit`. Rebuilt Linux CPU image
`sha256:ab2f12cd81a094ffc267eacfb637ae055c8b3c8cd31e364dfc2f54cbcdf21597` contains the monitor fix
and passes `./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web
`81/81`. Its full `linux-cpu` rerun advanced past the previous monitored-publish stall but failed
before routed Playwright in the model-bootstrap failover/deduplication integration step, timing out
on the ready topic for `integration-bootstrap-chaos-1783761854482798`. Current source carries the
bootstrap-failover remediation, and focused mounted-source `cabal test infernix-haskell-style` plus
`cabal test infernix-unit` pass. Rebuilt Linux CPU image
`sha256:534f631468380d9e59df713e4e8c78b976e17b17e0c64eb09be4eff8d6f41388` contains the remediation
and passes `./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web
`81/81`. Its full `linux-cpu` rerun passed full live integration and routed Playwright reached
`15/16`, including Sprint 9.9 auth/RBAC/account-switching and artifact coverage, then failed only
the browser matrix visible capacity-result assertion after receiving the typed terminal
`ModelMemoryLimitExceeded` payload. Current source projects the rendered chat pane from the active
context id plus the per-context conversation cache so a stored terminal result for the selected
context cannot be hidden behind a stale `activeConversation` pane, and the Playwright capacity
assertion now names the model/context on failure. Focused mounted-source PureScript validation
passes `82/82`, and `node --check web/playwright/inference.spec.js` passes. Rebuilt Linux CPU image
`sha256:e09f824b06b489a574288dbafcf1c8cc5920ae0bcb1a96cea91306a6cd57221c` contains that
render-projection fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun
passed the front gates and full live integration, including typed CPU admission and smaller-model
continuity; routed Playwright reached `15/16` and failed only the `audio-demucs-htdemucs` visible
capacity-result assertion after proving the target context was active. Current source now ignores
stale WebSocket messages from superseded connection generations, keeps one live per-context stream
per WebSocket session, and waits for the subscribed conversation snapshot before matrix submissions.
Focused mounted-source validation passes web unit `82/82` with `web/src/Main.purs` and
`web/playwright/inference.spec.js` mounted, `node --check web/playwright/inference.spec.js`, and
Haskell style/unit for the matching WebSocket stream-replacement server change. Rebuilt Linux CPU
image `sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d` contains the
browser/server fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun
passed the front gates and full live integration, and routed Playwright reached `15/16`: auth/RBAC/
logout switching and artifact coverage were green, and the matrix observed the typed terminal
`ModelMemoryLimitExceeded` payload for `audio-demucs-htdemucs`, but the visible capacity-result DOM
assertion still failed. Current source now gives browser-facing Pulsar readers unique per-stream
names and tags Playwright-observed WebSocket frames by browser socket generation, so refresh,
subscribe, and terminal-result waits key off the live generation rather than a stale socket the SPA
correctly ignores. `node --check web/playwright/inference.spec.js` passes for that helper change.
Mounted-source Haskell validation also passes `cabal test infernix-haskell-style infernix-unit` with
`src/Infernix/Runtime/Pulsar.hs` mounted into the Linux CPU launcher image, and `git diff --check`
is clean for the touched files. Rebuilt Linux CPU image
`sha256:eeb58064f9eca14c008b9c976380c5c7745a4c6079a5bd8885b3935c864532a5`
(`20070858505` bytes, created `2026-07-11T14:49:26.455414736-04:00`) contains this fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, then routed Playwright reached `14/16`: the artifact spec hit a download-button
replacement race after `data-download-status="pending"`, and the browser matrix still failed the
`audio-demucs-htdemucs` visible capacity-result DOM assertion after validating the typed terminal
payload. Current source fixes the routed browser harness by waiting for upload-record echo before
artifact downloads, retrying against a re-resolved artifact card until the webapp-proxy download
grant is ready, and waiting for the exact typed capacity text with a resubscription fallback.
`node --check web/playwright/inference.spec.js` and `git diff --check` pass for the touched files.
Rebuilt Linux CPU image
`sha256:d49b4799375df7a0e5726d16717ab6dc4e09fc8baa685969484099027f81c4c8`
(`20070886873` bytes, created `2026-07-11T17:27:02.378037428-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, then routed Playwright reached `15/16`: the artifact upload/preview/download spec
passed, proving the download-grant retry fix, but the browser matrix still failed the
`audio-demucs-htdemucs` visible capacity-result assertion after resubscription. The next Wave T gate
is the capacity-result render fix and a clean routed-suite rerun. Current source now waits for the
server prompt patch for the exact submitted prompt and filters the terminal result by the matching
`inferenceResultUserPromptMessageId`; focused `node --check web/playwright/inference.spec.js` and
`git diff --check` pass for that follow-up. Rebuilt Linux CPU image
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
`InferenceError` WebSocket contract fix for browser-facing failed results. It passed
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, rebuilt-image `infernix test unit` (Haskell
unit plus web `83/83`), and rebuilt-image `infernix test e2e`. Routed Playwright passed `16/16` in
3.6 minutes, including the per-model browser matrix in 2.5 minutes, the live typed capacity-message
rendering path for over-budget rows, smaller-model continuity, Sprint 9.9 auth/RBAC/logout
account-switching, and artifact upload/preview/download coverage.
Selected accelerator closure followed on rebuilt `linux-gpu` image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896`; routed Playwright passed
`16/16` in 17.1 minutes, including the per-model browser matrix, typed GPU capacity messages for
over-budget rows, smaller-model continuity, Sprint 9.9 auth/RBAC/logout account-switching, and
artifact upload/preview/download coverage.
**Cohort gate**: Closed [Wave T](cohort-validation-waves.md) — routed Playwright recorded the live
`linux-cpu` and selected `linux-gpu` over-budget browser messages plus smaller-model continuity for
this typed error scope.
**Implementation**: `src/Infernix/Web/Contracts.hs`, `src/Infernix/Bridge/Result.hs`,
`web/src/Infernix/Web/Chat.purs`, `web/src/Generated/Contracts.purs`,
`web/test/Infernix/Web/ContractsSpec.purs`, `web/test/Infernix/Web/ChatSpec.purs`, and routed
Playwright assertions under `web/playwright/`.
**Docs to update**: `README.md`, `documents/development/demo_app_test_plan.md`,
`documents/reference/web_portal_surface.md`, `documents/reference/api_surface.md`,
`documents/development/frontend_contracts.md`, `documents/development/testing_strategy.md`, and this
plan.

### Objective

Expose inference failures as pure typed data in the browser contract and render memory-capacity
failures as helpful UI messages with explicit quantities.

### Deliverables

- Browser-facing result types include a typed `InferenceError` branch rather than only
  `inlineOutput` / artifact fields.
- `ModelMemoryLimitExceeded` renders the model footprint and available daemon budget in MiB.
- The UI does not parse generic strings to identify model-size errors.
- Existing successful result rendering for inline text and artifacts remains unchanged.

### Validation

- PureScript contract tests roundtrip each `InferenceError` constructor used by the backend.
- Chat/view-model tests cover `ModelMemoryLimitExceeded` rendering from fields.
- Routed Playwright covers selecting an over-budget model and seeing the capacity message while a
  smaller model remains runnable in the same daemon session.

### Remaining Work

None.

---

## Remaining Work

Sprint 5.11 is closed for typed inference errors in the browser contracts and demo UI by Wave T's
`linux-cpu` plus selected `linux-gpu` routed full-suite proof. Sprints 5.1-5.10 are `Done`; Apple
cohort validation closed in Waves A/A.2 and the CUDA Linux `linux-cpu` and `linux-gpu` gates passed
on the recorded validation.

Sprint 5.12 reopens this phase for the Managed-State-Transition Doctrine: its own `### Remaining
Work` tracks the pending cohort full-suite sign-off.

---

## Sprint 5.12: Shared Readiness Contract [Planned]

**Status**: Planned
**Code-side closure**: `cabal build all`, `cabal test infernix-unit`, `cabal test
infernix-haskell-style`, `infernix lint docs`, and `poetry run check-code` for the
Playwright-executor change.
**Cohort gate**: pending — apple-silicon plus linux-cpu full-suite, owning wave TBD
**Implementation**: `src/Infernix/Web/Contracts.hs`, `web/playwright/inference.spec.js`
**Blocked by**: Sprint 4.28
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: single-source the
model-bootstrap deadline through the shared Haskell browser contract so a client deadline below the
server ceiling is not expressible, and have the Playwright executor await the real
`ModelBootstrapReadyEvent` instead of a kubectl rollout proxy. Readiness is encoded as typed
evidence rather than a hopeful timeout, generalizing the results-side realness contract to state
transitions per [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- the model-bootstrap deadline is single-sourced through the shared Haskell browser contract in
  `src/Infernix/Web/Contracts.hs`, so a client deadline below the server ceiling cannot be
  constructed
- the Playwright executor in `web/playwright/inference.spec.js` awaits the real
  `ModelBootstrapReadyEvent` as typed readiness evidence
- the prior kubectl rollout proxy for readiness is removed from the executor path

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `infernix lint docs` exit zero on both the apple-silicon and linux-cpu lanes
- `poetry run check-code` exits zero for the Playwright-executor change on both lanes

### Remaining Work

- the cohort full-suite sign-off is pending: apple-silicon plus linux-cpu full-suite in an owning
  wave TBD is the residual before closure

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/web_ui_architecture.md` - UI topology, hosting rule, and generated-catalog consumption
- `documents/development/frontend_contracts.md` - build-time contract generation policy and handwritten-versus-generated ownership
- `documents/development/purescript_policy.md` - PureScript project structure and supported toolchain usage
- `documents/development/testing_strategy.md` - frontend unit and Playwright coverage model
- `documents/engineering/implementation_boundaries.md` - browser-contract ownership and generated-output boundaries
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) - typed state-transition evidence doctrine now referenced by Sprint 5.12

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - manual inference SPA behavior, route inventory, and active-substrate catalog rules

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when UI request shapes, generated demo-config fields, or routed API assumptions change
