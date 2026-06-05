# Phase 5: Web UI and Shared Types

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the PureScript demo UI built with spago, the Haskell-owned frontend contract
> generator, the `purescript-spec` test framework, the cluster-resident browser SPA, and the
> generated-path cleanup that reserves `Generated/` directories for real generated outputs only.

## Phase Status

Phase 5 closes around the PureScript demo UI, the Haskell-owned browser-contract
source, the generated contract path under `web/src/Generated/`, the clustered demo hosting rule,
the container-owned routed Playwright executor, and the Phase 5.9 process-environment retirement
in the demo backend, Python adapter layer, and web/Node helper scripts. Sprints 5.1-5.10 have
their deliverables closed in the worktree; Apple cohort validation closed in Waves A/A.2, and
CUDA Linux cohort validation closed in Wave C.
Phase 7 extends the PureScript demo surface with the durable-context Chat, Artifacts, and Model
Picker views; the supported manual-inference path moves from a direct HTTP request/poll cycle to
WebSocket-delivered `ConversationStatePatch` deltas owned by Phase 7.

## Current Repo Assessment

The repository ships the supported PureScript demo path: `web/src/Main.purs` and the handwritten
PureScript modules under `web/src/Infernix/Web/` own the browser SPA, `web/test/Main.purs` owns
the frontend unit suite, `src/Infernix/Web/Contracts.hs` owns the handwritten browser contract,
and `npm --prefix web run build` regenerates generated contracts and bundles the app into
`web/dist/app.js`. The generated browser contracts and SPA state still expose the active
substrate through `runtimeMode` fields. The code can honor `demo_ui = false`, and the supported
materialization path now emits that shape with `--demo-ui false`. The browser SPA and routed
Playwright suite now also expose `daemonLocation`, `inferenceExecutorLocation`, and
`inferenceDispatchMode`, and the clustered demo app closes around Apple host inference execution
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
  `infernix-demo` reads the active `.dhall` and owns substrate-appropriate dispatch

## Sprint 5.1: Demo Web Application Host (PureScript) [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/package.json`, `web/spago.yaml`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Close the current web hosting baseline while keeping one stable browser entrypoint across the
clustered routed surface on every supported substrate.

### Deliverables

- repo-owned browser application code lives under `web/src/*.purs`
- the demo HTTP host is the `infernix-demo` Haskell binary, which serves the PureScript bundle and
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
**Implementation**: `src/Infernix/Web/Contracts.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Models.hs`, `src/Infernix/Types.hs`, `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/test/Main.purs`, `infernix.cabal`, `web/package.json`
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
**Implementation**: `web/test/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/package.json`, `src/Infernix/CLI.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Use repo-owned frontend tests to verify the browser SPA stays aligned with the Haskell-owned
contract and behaves predictably.

### Deliverables

- `purescript-spec` suites cover generated contracts, model-list rendering, manual inference forms,
  request-shape presentation, and result presentation
- frontend tests run through the CLI-owned validation surface
- the browser-independent view model proves that rendered catalog membership matches the generated catalog

### Validation

- `infernix test unit` runs `spago test` alongside Haskell unit tests
- contract tests fail when request or response shapes drift from the Haskell-owned source
- view-level specs fail when rendered catalog membership or ordering drifts from the generated catalog

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

## Sprint 5.5: Web Runtime Image and Dedicated Playwright Container [Done]

**Status**: Done
**Implementation**: `docker/linux-substrate.Dockerfile`, `compose.yaml`, `web/playwright/`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Bake the packaged PureScript demo bundle into the Linux substrate image and run the routed
Playwright executor from the active substrate image on Linux.

### Deliverables

- the final Linux substrate image includes the built `web/dist/` bundle, the Node toolchain needed
  to regenerate it, and the Playwright runtime used by Linux routed E2E
- routed Playwright execution runs from the active Linux substrate image; the Playwright runtime
  is baked into `docker/linux-substrate.Dockerfile` rather than carried in a separate image or
  sidecar service
- `infernix test e2e` invokes `npm --prefix web exec -- playwright test` inside the Linux
  launcher image; Apple host-native E2E uses host `npm exec` with the same typed fixture and
  is queued for the Apple cohort validation batch
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
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `web/playwright/inference.spec.js`, `web/src/Infernix/Web/Workbench.purs`, `web/src/Main.purs`, `web/src/index.html`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `README.md`, `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`

### Objective

Keep the demo app clustered on Apple while making the Apple browser path explicitly host-backed
for inference execution and retaining a containerized Linux image as the only supported Playwright
executor. Under the final Phase 6 split, the browser enters the cluster daemon path first and only
the inference batch execution moves to host daemons.

### Deliverables

- the routed demo app remains cluster-resident on Apple and Linux substrates alike
- Apple host-native E2E orchestration uses host `npm exec` with the same typed fixture and is
  queued for the Apple cohort validation batch
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

- Apple routed E2E runner code is landed and queued for the Apple cohort validation batch
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
**Implementation**: `src/Infernix/DemoCLI.hs`, `python/adapters/common.py`, `python/adapters/model_cache.py`, every engine adapter under `python/adapters/*.py`, `web/scripts/install-purescript.mjs`, `web/test/run_playwright_matrix.mjs`
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

- `src/Infernix/DemoCLI.hs` reads `bindHost`, `bridgeMode`, `publicationStatePath` from
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
- Apple cohort validation closed in Waves A/A.2; CUDA Linux validation closed in Wave C with
  full `linux-cpu` and `linux-gpu` gates.

### Remaining Work

None. Apple cohort validation closed in [Wave A/A.2](cohort-validation-waves.md), and CUDA Linux
cohort validation closed in [Wave C](cohort-validation-waves.md).

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
  directly, without referencing the prior sidecar.
- Sprint 5.9 Validation prose uses cohort closure markers and keeps `Wave A/A.2`
  and `Wave C` references for cohort closure.

### Validation

- the phase-specific lexical guard for dated hardware proof-point prose returns zero matches.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

None.

---

## Remaining Work

None. Sprints 5.1-5.10 are `Done`; Apple cohort validation closed in Waves A/A.2 and CUDA Linux
cohort validation closed in Wave C.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/web_ui_architecture.md` - UI topology, hosting rule, and generated-catalog consumption
- `documents/development/frontend_contracts.md` - build-time contract generation policy and handwritten-versus-generated ownership
- `documents/development/purescript_policy.md` - PureScript project structure and supported toolchain usage
- `documents/development/testing_strategy.md` - frontend unit and Playwright coverage model
- `documents/engineering/implementation_boundaries.md` - browser-contract ownership and generated-output boundaries

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - manual inference SPA behavior, route inventory, and active-substrate catalog rules

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when UI request shapes, generated demo-config fields, or routed API assumptions change
