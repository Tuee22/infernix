# Phase 5: Web UI and Shared Types

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the PureScript demo UI built with spago, the Haskell-owned frontend contract
> generator, the `purescript-spec` test framework, the browser workbench, and the generated-path
> cleanup that reserves `Generated/` directories for real generated outputs only.

## Phase Status

All Phase 5 sprints are now `Done`. The Linux substrate image owns the demo bundle and Playwright
toolchain, the routed demo app stays cluster-resident on Apple and Linux alike, and supported E2E
uses a container-owned Playwright executor without browser-side substrate branching.

## Current Repo Assessment

The repository ships the supported PureScript demo path: `web/src/Main.purs` and
`web/src/Infernix/Web/Workbench.purs` own the browser workbench, `web/test/Main.purs` owns the
frontend unit suite, `src/Infernix/Web/Contracts.hs` owns the handwritten browser contract, and
`npm --prefix web run build` regenerates generated contracts and bundles the app into
`web/dist/app.js`. The generated browser contracts and workbench state still expose the active
substrate through `runtimeMode` fields.

## Substrate-Driven Demo Catalog Contract

- the demo UI catalog comes only from the active substrate's generated demo catalog
- the UI does not maintain a hidden hard-coded allowlist
- the browser workbench exposes every model or workload entry present in the generated file
- substrate changes alter catalog content without changing route structure
- the generated browser contracts and routed publication payloads currently serialize the active
  substrate under `runtimeMode` field names
- the browser workbench and Playwright harness do not choose engines or branch on substrate ids;
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

## Sprint 5.5: Current Web Runtime Image and Playwright Dependency Ownership Baseline [Done]

**Status**: Done
**Implementation**: `docker/linux-substrate.Dockerfile`, `web/playwright/`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/deployment-service.yaml`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Fold the packaged PureScript demo bundle and the Playwright executor into the current Linux
baseline and remove `npx` from the supported workflow.

### Deliverables

- the final Linux substrate image includes the built `web/dist/` bundle and Playwright plus browser deps
- `infernix test e2e` launches Playwright from the substrate image on Linux and from a
  container-owned executor orchestrated by the host CLI on Apple
- the chart does not deploy a separate web workload or web image
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`

### Validation

- a substrate-image build produces a working Playwright runner without a separate web image
- Apple host E2E still passes with container-owned Playwright against the clustered routed surface
- Linux E2E passes with Playwright launched from the substrate image
- `rg -n 'npx playwright' README.md documents src web/package.json` returns no supported workflow references

### Remaining Work

None.

---

## Sprint 5.8: Clustered Demo Surface on Apple and Container-Owned Playwright Closure [Done]

**Status**: Done
**Docs to update**: `README.md`, `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`

### Objective

Keep the demo app clustered on Apple while retaining the outer container as the only supported
Playwright executor.

### Deliverables

- the routed demo app remains cluster-resident on Apple and Linux substrates alike
- Apple host-native E2E orchestration runs from the host CLI while the actual Playwright executor
  runs inside `docker compose run --rm infernix infernix ...`
- user-facing Apple docs describe `cluster up` as the way to launch the demo surface instead of a
  direct host `infernix-demo serve` workflow
- Linux user-facing docs continue to describe Compose as the single launcher for demo, integration,
  and E2E workflows
- the Playwright suite and browser helpers do not branch on substrate id or engine family; they
  interact only with the routed demo surface and rely on `infernix-demo` to read `.dhall` and
  dispatch the correct engine
- README-level substrate instructions cover how to launch the demo app, how to keep the Apple host
  daemon running for inference, and how E2E execution differs between Apple and Linux

### Validation

- Apple routed E2E passes while the host inference daemon is live and the Playwright executor runs
  inside the outer container
- Linux routed E2E passes through the same container-owned Playwright executor without any host
  daemon management
- Apple and Linux routed E2E pass through the same browser-visible flows without substrate-specific
  Playwright branching; only launcher or orchestration differs
- docs validation fails if the user-facing docs still treat host `infernix-demo serve` as the final
  Apple demo-app launch story or describe browser-side substrate selection

### Remaining Work

None.

---

## Sprint 5.6: Substrate-Driven Demo Catalog and Workbench Parity in PureScript [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/testing_strategy.md`

### Objective

Make the browser workbench a faithful reflection of the generated catalog for the active built
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
- `documents/reference/web_portal_surface.md` - manual inference workbench behavior, route inventory, and active-substrate catalog rules

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when UI request shapes, generated demo-config fields, or routed API assumptions change
