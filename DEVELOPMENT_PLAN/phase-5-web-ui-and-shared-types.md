# Phase 5: Web UI and Shared Types

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the PureScript demo UI built with spago, the Haskell-owned frontend contract
> generator, the `purescript-spec` test framework, the browser workbench, and the generated-path
> cleanup that reserves `Generated/` directories for real generated outputs only.

## Phase Status

Phase 5 is closed around the PureScript demo UI, the Haskell-owned browser-contract source, the
generated contract path under `web/src/Generated/`, the clustered demo hosting rule, and the
container-owned routed Playwright executor implemented in this worktree. Sprints 5.1–5.8 remain
`Done` and there is no additional open Phase 5 backlog.

## Current Repo Assessment

The repository ships the supported PureScript demo path: `web/src/Main.purs` and
`web/src/Infernix/Web/Workbench.purs` own the browser workbench, `web/test/Main.purs` owns the
frontend unit suite, `src/Infernix/Web/Contracts.hs` owns the handwritten browser contract, and
`npm --prefix web run build` regenerates generated contracts and bundles the app into
`web/dist/app.js`. The generated browser contracts and workbench state still expose the active
substrate through `runtimeMode` fields. The code can honor `demo_ui = false`, and the supported
materialization path now emits that shape with `--demo-ui false`. The browser workbench and routed
Playwright suite now also expose `daemonLocation`, `inferenceExecutorLocation`, and
`inferenceDispatchMode`, and the clustered demo app closes around Apple host inference execution
without claiming cluster-resident Apple inference parity. Phase 6 Sprint 6.25 distinguishes the
always-present cluster daemon from the Apple host inference executor.

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

## Sprint 5.5: Web Runtime Image and Dedicated Playwright Container [Done]

**Status**: Done
**Implementation**: `docker/linux-substrate.Dockerfile`, `docker/playwright.Dockerfile`, `compose.yaml`, `web/playwright/`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/deployment-service.yaml`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Bake the packaged PureScript demo bundle into the Linux substrate image and home the routed
Playwright executor in a dedicated single-purpose image used by every substrate.

### Deliverables

- the final Linux substrate image includes the built `web/dist/` bundle and the Node toolchain
  needed to regenerate it; it carries no browser-runtime weight
- routed Playwright execution runs from the dedicated `infernix-playwright:local` image built by
  `docker/playwright.Dockerfile`, which owns Node, the Playwright runtime, and the three browsers
- `infernix test e2e` invokes that Playwright image through `docker compose run --rm playwright`
  on every substrate; on Apple Silicon the host CLI runs it directly, on Linux substrates the
  outer container runs it through the mounted host docker socket
- the chart does not deploy a separate web workload or web image
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`

### Validation

- `docker compose build infernix && docker compose build playwright` succeeds and produces both
  images on supported Linux paths
- Apple routed E2E passes with `docker compose run --rm playwright` invoked from the host CLI
- Linux routed E2E passes with `docker compose run --rm playwright` invoked from the outer
  container against the host docker daemon
- `rg -n 'npx playwright' README.md documents src web/package.json` returns no supported workflow references

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
- Apple host-native E2E orchestration runs from the host CLI and invokes
  `docker compose run --rm playwright` for the dedicated `infernix-playwright:local` image
- Linux outer-container E2E orchestration runs `docker compose run --rm playwright` from inside
  the outer container against the host docker daemon mounted through `/var/run/docker.sock`
- Docker is a hard prerequisite for `infernix test e2e` on every substrate; the CLI no longer
  carries a host-native npm fallback
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

- Apple routed E2E passes from the host CLI through `docker compose run --rm playwright` against
  the clustered routed surface
- Linux routed E2E passes through the same compose-driven Playwright executor without any host
  daemon management
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

## Remaining Work

None.

---

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
