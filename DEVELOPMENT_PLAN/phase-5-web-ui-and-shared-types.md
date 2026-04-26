# Phase 5: Demo UI in PureScript and Shared Types

**Status**: Blocked
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)
**Blocked by**: Phase 1 Sprint 1.6, Phase 4 Sprint 4.4

> **Purpose**: Define the PureScript demo UI built with spago, the Haskell-owned frontend contract
> derived via `purescript-bridge`, the `purescript-spec` test framework, and the manual inference
> workbench that lets a user run inference against any registered model in the active runtime mode
> (when the demo surface is enabled).

## Phase Status

All sprints in this phase drop from `Done` to `Active` because every sprint deliverable conflicts
with the new doctrine in [00-overview.md](00-overview.md) Hard Constraint 15: the JavaScript
workbench built by `web/build.mjs` is replaced by PureScript built with spago; build-generated
JavaScript contract modules are replaced by PureScript modules generated from Haskell ADTs in
`src/Infernix/Demo/Api.hs` via `purescript-bridge`; the contracts test framework moves from
`web/test/contracts.test.mjs` to `purescript-spec` suites under `web/test/*.purs`; the manual
inference workbench is reimplemented in PureScript; the web image (`web/Dockerfile`) installs the
purs and spago toolchain alongside Playwright. The DOM surface and the Playwright assertions are
preserved as much as possible to minimize churn in the existing E2E suites.

## Current Repo Assessment

The repository already has a browser workbench, build-generated JavaScript frontend contracts, and
routed Playwright coverage. The browser workbench loads from the cluster-resident web workload on
the supported Kind path, build-root frontend contract staging is closed, and both
browser-independent and browser-driven coverage prove catalog parity, publication-detail rendering,
and result rendering through the routed cluster edge. Same-image browser execution uses the built
web image on both supported control-plane lanes, and the Apple host-native final-substrate lane
serves the UI from the Harbor-published web image. The repository now also carries `web/spago.yaml`
plus placeholder `.purs` source and test modules, but the supported web build, contract
generation, and frontend tests still run through `web/build.mjs`, `web/package.json`, and the
JavaScript workbench. The workbench renders family-aware request guidance and result framing for
every generated entry.

## Demo Catalog Contract

This phase owns the browser-side interpretation of the generated demo catalog.

- the demo UI catalog comes only from the active runtime mode's generated demo catalog; the current
  supported path proves this through generated staging, the repo-local publication mirror, and the
  mounted ConfigMap-backed `.dhall`
- the UI does not maintain a hidden hard-coded allowlist on the supported path
- the browser workbench must expose every model or workload entry present in that generated file
- mode changes alter the catalog content without changing the route structure

## Sprint 5.1: Demo Web Application Host (PureScript) [Active]

**Status**: Active
**Blocked by**: Phase 1 Sprint 1.6, Phase 3 Sprint 3.6
**Implementation**: `web/`, `web/Dockerfile`, `infernix.cabal`, `chart/templates/`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Close the web hosting contract while keeping one stable browser entrypoint across the
cluster-resident webapp service and the Apple host bridge.

### Deliverables

- repo-owned browser application code lives under `web/src/*.purs`; the supported implementation is
  a PureScript demo application built with `spago build` and `spago bundle-app` into `web/dist/`
- a cluster-resident web image, built via `web/Dockerfile`, carries the spago plus purs toolchain
  alongside Playwright browser dependencies and produces the static `web/dist/` bundle
- the demo HTTP host is the `infernix-demo` Haskell binary (Phase 4 Sprint 4.4) which serves the
  PureScript bundle from `web/dist/` and exposes the demo API surface
- the `infernix-demo` workload deployment is owned by `chart/templates/deployment-demo.yaml`,
  gated by `.Values.demo.enabled` (driven from the active `.dhall` `demo_ui` flag)
- in containerized execution contexts, the `infernix-demo` workload mounts
  `ConfigMap/infernix-demo-config` read-only at `/opt/build/` and reads the active-mode `.dhall`
  from that watched runtime directory
- the supported path does not depend on a host-only webserver for `/`; on Apple host the
  equivalent surface is `infernix-demo serve --dhall PATH --port N` against a host-side `.dhall`
- the edge proxy routes `/` to the `infernix-demo` workload when the demo surface is enabled, and
  the `/` route is absent from the edge inventory when the demo surface is disabled

### Validation

- `curl http://127.0.0.1:<port>/` returns the frontend entrypoint on the routed cluster-resident path
- the browser workbench loads through the routed surface and consumes the active generated catalog
- `infernix cluster up` deploys the `infernix-demo` workload through Helm (when `demo_ui` is on)
  and serves that same route from the cluster

### Remaining Work

- `web/src/` currently holds JavaScript files (`app.js`, `workbench.js`); these must be replaced
  by PureScript modules under `web/src/*.purs`
- `web/build.mjs` and `web/package.json` currently drive the web build; they must be replaced by
  `web/spago.yaml` plus `spago build` plus `spago bundle-app` invoked from `web/Dockerfile`
- the demo HTTP host is currently `tools/service_server.py`; the Haskell port (`infernix-demo`)
  lands in Phase 4 Sprint 4.4
- the `chart/templates/deployment-demo.yaml` template and `.Values.demo.enabled` toggle do not
  exist yet (they land alongside the `infernix-demo` workload in Phase 3 Sprint 3.6)

---

## Sprint 5.2: Haskell-Owned Frontend Contract via purescript-bridge [Active]

**Status**: Active
**Blocked by**: Phase 1 Sprint 1.6, Sprint 5.1
**Implementation**: `src/Infernix/CLI.hs`, `web/`, `infernix.cabal`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`

### Objective

Keep Haskell types authoritative and make the webapp build consume generated bindings rather than
hand-maintained duplicates.

### Deliverables

- the supported web build generates PureScript contract modules from Haskell ADTs in
  `src/Infernix/Demo/Api.hs` via `purescript-bridge`
- the supported demo application imports those build-generated PureScript modules from
  `web/src/Generated/` for request and response shapes; no handwritten duplicate request or
  response types remain on the supported path
- the generated PureScript modules live in `web/src/Generated/` and are emitted by
  `infernix internal generate-purs-contracts`, which the `infernix-lib` build invokes; the same
  command runs from `web/Dockerfile` so the web image build stays self-contained
- the source-of-truth Haskell records live in `src/Infernix/Demo/Api.hs` (preferred over
  `proto-lens`-generated types directly to keep the bridge surface clean)
- no standalone public frontend codegen command exists outside `infernix internal generate-purs-contracts`

### Validation

- repeated web builds generate the same frontend contract modules deterministically
- `infernix test unit` fails if the web build or frontend tests detect drift from the Haskell source
- the web build succeeds using only the build-generated PureScript contract modules for shared
  types
- no tracked `web/src/Generated/` artifact remains in version control on the supported path; the
  directory is rebuilt by `infernix internal generate-purs-contracts` on every web build

### Remaining Work

- `web/build.mjs` currently emits JavaScript contract modules; the Haskell-side codegen entrypoint
  is currently `infernix internal generate-web-contracts` emitting `contracts.js`. Both must be
  replaced by `infernix internal generate-purs-contracts` emitting PureScript via
  `purescript-bridge` into `web/src/Generated/`
- `src/Infernix/Demo/Api.hs` does not exist yet (lands in Phase 4 Sprint 4.4)
- the `purescript-bridge` integration is not yet present in the Haskell build

---

## Sprint 5.3: Frontend Contract and View-Level Coverage via purescript-spec [Active]

**Status**: Active
**Blocked by**: Sprint 5.2
**Implementation**: `web/test/`, `web/src/`, `web/`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Use repo-owned frontend tests to verify the browser workbench stays aligned with the Haskell-owned
contract and behaves predictably.

### Deliverables

- `purescript-spec` test suites under `web/test/*.purs` cover generated contracts, model-list
  rendering, manual inference forms, request-shape presentation, and result presentation
- the generated codecs under test come from `web/src/Generated/` (Sprint 5.2 output of
  `infernix internal generate-purs-contracts`)
- `purescript-spec` is the authoritative contract gate for the supported demo UI; no alternative
  frontend test framework runs in parallel
- frontend tests run through the CLI-owned validation surface (`infernix test unit` invokes
  `spago test`)
- the browser-independent view model proves that the rendered catalog matches the generated
  catalog exactly

### Validation

- `infernix test unit` runs `spago test` (PureScript suites) alongside the Haskell unit tests
- contract tests fail when request or response shapes drift from the Haskell ADTs in
  `src/Infernix/Demo/Api.hs`
- view-level specs cover model selection and result rendering states
- contract and view-level specs fail when the rendered catalog order or membership drifts from the
  active generated catalog

### Remaining Work

- `web/test/contracts.test.mjs` is the current implementation and must be replaced by
  `purescript-spec` suites under `web/test/*.purs`
- `infernix test unit` does not yet invoke `spago test`

---

## Sprint 5.4: Manual Inference Workbench in PureScript For Any Registered Model [Active]

**Status**: Active
**Blocked by**: Sprint 5.1, Sprint 5.2
**Implementation**: `web/src/`, `web/`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Deliver the browser workbench the user asked for: manual inference against any model in the catalog.

### Deliverables

- model catalog browser with search or filter support
- per-model request form derived from the model's declared request contract
- submission, progress, and result views for manual inference
- links to large object-store-backed outputs when the service returns references rather than inline payloads

### Validation

- the PureScript UI can search, select a catalog entry, and submit a request through `/api`
- routed Playwright coverage proves the workbench can render object-reference result links for
  large outputs
- every registered model remains manually callable through the same `/api` surface, while richer
  per-family browser flows close in Sprint 5.6
- the demo workbench is pure UI on top of the Haskell-served `/api`; production deployments leave
  the demo flag off and the workbench is absent from the cluster

### Remaining Work

- `web/src/app.js` and `web/src/workbench.js` are the current implementation; both must be replaced
  by PureScript modules under `web/src/*.purs`
- the existing Playwright DOM selectors must be preserved in the PureScript port to minimize
  churn in the Phase 6 E2E suite (or the Playwright suite is rewritten in the same change; see
  Phase 6 Sprint 6.3)

---

## Sprint 5.5: Web Runtime Image and Playwright Dependency Ownership [Active]

**Status**: Active
**Blocked by**: Sprint 5.1
**Implementation**: `web/Dockerfile`, `web/playwright/`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Prepare the web image to be both the UI host and the E2E execution environment.

### Deliverables

- `infernix cluster up` builds the webapp image through `web/Dockerfile` as part of the canonical deploy flow
- the built webapp image is uploaded to Harbor before Helm rollout
- `web/Dockerfile` installs the purs and spago toolchain (for the PureScript build) alongside
  Chromium, WebKit, and Firefox dependencies for Playwright
- the same image carries the PureScript bundle (built into `web/dist/` by `spago bundle-app`),
  the Playwright browser binaries, and serves both as the demo UI host and the E2E executor
- `infernix test e2e` targets that same web image rather than a separate ad hoc browser image
- the outer-container control-plane image no longer carries a duplicate Playwright browser
  installation

### Validation

- the supported `web/Dockerfile` builds and serves the static PureScript bundle from `web/dist/`
  (produced by `spago bundle-app`) and carries Playwright browser dependencies
- `./.build/infernix --runtime-mode apple-silicon test e2e` passes while launching Playwright from
  the built web image
- `docker compose run --rm infernix infernix --runtime-mode apple-silicon test e2e` passes while
  delegating browser execution to the built web image
- the repository does not maintain a second dedicated Playwright-only image
- `infernix cluster up` produces a Harbor-published web image consumable by Helm and the
  host-native routed E2E lanes exercise that same final-substrate image path across the runtime
  matrix

### Remaining Work

- `web/Dockerfile` does not yet install the purs and spago toolchain; the static bundle is still
  produced by `web/build.mjs` rather than `spago bundle-app`
- `web/package.json`, `web/playwright.config.js`, and `tools/publish_chart_images.py` references
  in this sprint will be retired during Sprint 1.6 (Python tooling migration) and Sprints 5.1
  through 5.4 (PureScript port)

---

## Sprint 5.6: Mode-Driven Demo Catalog and Workbench Parity in PureScript [Active]

**Status**: Active
**Blocked by**: Sprint 5.4
**Implementation**: `web/src/`, `web/playwright/inference.spec.js`, `web/test/`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/testing_strategy.md`

### Objective

Make the browser workbench a faithful reflection of the generated catalog for the active runtime mode.

### Deliverables

- the UI catalog is derived only from `infernix-demo-<mode>.dhall` for the active runtime mode
- in containerized execution contexts, that active-mode `.dhall` arrives through
  `ConfigMap/infernix-demo-config` mounted at `/opt/build/`
- every generated catalog entry has a visible browser path covering request input, progress state,
  and result presentation appropriate to that workload family
- the UI can surface mode-specific engine or lane metadata where it materially clarifies execution
- switching runtime modes changes the rendered catalog without code changes or hard-coded model filtering

### Validation

- browser-visible catalog entries match the active generated demo config exactly across the
  repo-local publication mirror and the mounted ConfigMap-backed runtime path
- removing an entry from the generated mode config removes it from the UI without extra frontend edits
- switching from Apple to Linux CPU to Linux CUDA changes the catalog and engine metadata in the expected way
- `purescript-spec` and Playwright coverage prove the workbench renders family-aware request
  guidance, submit labels, artifact metadata, and result presentation without introducing UI-only
  catalog rules
- the existing Playwright DOM selectors (`web/playwright/inference.spec.js`) continue to match the
  PureScript views; if a selector cannot be preserved, the Playwright spec is updated in this
  sprint rather than waiting for Phase 6

### Remaining Work

- the workbench is currently implemented in `web/src/app.js`, `web/src/workbench.js`, and
  `web/src/index.html`; PureScript reimplementation lands here together with the Playwright DOM
  selector preservation work
- `web/test/contracts.test.mjs` currently covers catalog parity; the parallel `purescript-spec`
  suite under `web/test/CatalogSpec.purs` lands here

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/web_ui_architecture.md` - UI topology and cluster-hosting rule
- `documents/development/frontend_contracts.md` - build-time contract generation policy for the webapp image
- `documents/development/testing_strategy.md` - frontend unit and Playwright coverage model

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - manual inference workbench behavior, route inventory, and active-mode catalog rules

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) aligned when UI request shapes, generated-demo-config fields, or API routes change
