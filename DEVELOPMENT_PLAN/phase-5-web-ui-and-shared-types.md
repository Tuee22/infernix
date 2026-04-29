# Phase 5: Web UI and Shared Types

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the PureScript demo UI built with spago, the Haskell-owned frontend contract
> generator, the `purescript-spec` test framework, the browser workbench, and the generated-path
> cleanup that reserves `Generated/` directories for real generated outputs only.

## Phase Status

Sprints 5.1 through 5.7 are `Done`. The final Linux substrate image now owns the demo bundle,
Playwright toolchain, and routed `linux-cpu` E2E execution path. Ordered plan closure still
depends on Phase 4's remaining supported `linux-cuda` rerun.

## Current Repo Assessment

The repository ships the supported PureScript demo path: `web/src/Main.purs` and
`web/src/Infernix/Web/Workbench.purs` own the browser workbench, `web/test/Main.purs` owns the
frontend unit suite, `src/Infernix/Web/Contracts.hs` owns the handwritten browser contract, and
`npm --prefix web run build` regenerates generated contracts and bundles the app into
`web/dist/app.js`. No remaining Phase 5 implementation gap remains in the current worktree, but
the ordered phase chain still depends on the remaining Phase 4 supported `linux-cuda` closure.

## Demo Catalog Contract

- the demo UI catalog comes only from the active runtime mode's generated demo catalog
- the UI does not maintain a hidden hard-coded allowlist
- the browser workbench exposes every model or workload entry present in the generated file
- mode changes alter catalog content without changing route structure

## Sprint 5.1: Demo Web Application Host (PureScript) [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/package.json`, `web/spago.yaml`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Close the web hosting contract while keeping one stable browser entrypoint across the routed
cluster path and the Apple host bridge.

### Deliverables

- repo-owned browser application code lives under `web/src/*.purs`
- the demo HTTP host is the `infernix-demo` Haskell binary, which serves the PureScript bundle and
  exposes the demo API surface
- the `infernix-demo` workload is gated by the active generated `.dhall` `demo_ui` flag
- the shared Gateway or HTTPRoute surface routes `/` to `infernix-demo` only when the demo surface is enabled

### Validation

- the browser workbench loads through the routed surface and consumes the active generated catalog
- `cluster up` deploys `infernix-demo` through Helm when `demo_ui` is on
- when `demo_ui` is off, `/` is absent from the route inventory

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

Use repo-owned frontend tests to verify the browser workbench stays aligned with the Haskell-owned
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

## Sprint 5.4: Manual Inference Workbench in PureScript For Any Registered Model [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/src/index.html`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Deliver the browser workbench for manual inference against any model in the generated catalog.

### Deliverables

- model catalog browser with search or filter support
- per-model request form derived from the model's declared request contract
- submission, progress, and result views for manual inference
- links to large object-store-backed outputs when the service returns references rather than inline payloads

### Validation

- the UI can search, select a catalog entry, and submit a request through `/api`
- routed Playwright coverage proves the workbench can render object-reference result links
- every registered model remains manually callable through the same `/api` surface

### Remaining Work

None.

---

## Sprint 5.5: Web Runtime Image and Playwright Dependency Ownership [Done]

**Status**: Done
**Implementation**: `docker/linux-substrate.Dockerfile`, `web/playwright/`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/deployment-service.yaml`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Fold the packaged PureScript demo bundle and the Playwright executor into the final Linux
substrate image and remove `npx` from the supported workflow.

### Deliverables

- the final Linux substrate image includes the built `web/dist/` bundle and Playwright plus browser deps
- `infernix test e2e --runtime-mode linux-cpu|linux-cuda` launches Playwright from the substrate image
- `infernix test e2e --runtime-mode apple-silicon` launches Playwright from the Apple host install
- the chart does not deploy a separate web workload or web image
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`

### Validation

- a substrate-image build produces a working Playwright runner without a separate web image
- Apple host E2E still passes against the host Playwright install
- Linux E2E passes with Playwright launched from the substrate image
- `rg -n 'npx playwright' README.md documents src web/package.json` returns no supported workflow references

### Remaining Work

None.

---

## Sprint 5.6: Mode-Driven Demo Catalog and Workbench Parity in PureScript [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/testing_strategy.md`

### Objective

Make the browser workbench a faithful reflection of the generated catalog for the active runtime mode.

### Deliverables

- the UI catalog is derived only from the active generated demo catalog
- every generated catalog entry has a visible browser path covering request input, progress, and
  result presentation appropriate to that workload family
- switching runtime modes changes the rendered catalog without frontend code changes

### Validation

- browser-visible catalog entries match the generated demo config exactly
- removing an entry from the generated config removes it from the UI without extra frontend edits
- switching runtime modes changes catalog and engine metadata in the expected way

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
- `find src/Generated -type f` returns no handwritten source files on the supported path

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/web_ui_architecture.md` - UI topology, hosting rule, and generated-catalog consumption
- `documents/development/frontend_contracts.md` - build-time contract generation policy and handwritten-versus-generated ownership
- `documents/development/purescript_policy.md` - PureScript project structure and supported toolchain usage
- `documents/development/testing_strategy.md` - frontend unit and Playwright coverage model
- `documents/engineering/implementation_boundaries.md` - browser-contract ownership and generated-output boundaries

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - manual inference workbench behavior, route inventory, and active-mode catalog rules

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when UI request shapes, generated demo-config fields, or routed API assumptions change
