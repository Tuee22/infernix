# Phase 5: Demo UI in PureScript and Shared Types

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the PureScript demo UI built with spago, the Haskell-owned frontend contract
> generator, the `purescript-spec` test framework, and the manual inference workbench that lets a
> user run inference against any registered model in the active runtime mode (when the demo
> surface is enabled).

## Phase Status

Sprints 5.1, 5.2, 5.3, 5.4, and 5.6 stay `Done`. Sprint 5.5 (Web Runtime Image and Playwright
Dependency Ownership) remains `Active`: `web/Dockerfile` is gone from the worktree, the Linux
substrate Dockerfiles now own web bundling plus Playwright install, and `infernix test e2e` is
partially retargeted, but the final substrate-image build and routed-E2E validation still need to
close.

## Current Repo Assessment

The repository now ships the supported PureScript demo path: `web/src/Main.purs` and
`web/src/Infernix/Web/Workbench.purs` own the browser workbench, `web/test/Main.purs` owns the
frontend unit suite through `purescript-spec`, `npm --prefix web run build` regenerates
`web/src/Generated/Contracts.purs` and bundles the app into `web/dist/app.js`, and routed
Playwright coverage still proves catalog parity, publication-detail rendering, and result
rendering through the cluster edge. The generated contract surface is now bridge-owned:
`src/Generated/Contracts.hs` defines dedicated browser-contract ADTs, `purescript-bridge`
derives the PureScript newtypes into `web/src/Generated/Contracts.purs`, and the CLI appends the
active-mode runtime constants and `Simple.JSON` instances consumed by the demo UI. Linux
substrate-image packaging is in the worktree, while the final image-build and Playwright-executor
validation is still open.

## Demo Catalog Contract

This phase owns the browser-side interpretation of the generated demo catalog.

- the demo UI catalog comes only from the active runtime mode's generated demo catalog; the current
  supported path proves this through generated staging, the repo-local publication mirror, and the
  mounted ConfigMap-backed `.dhall`
- the UI does not maintain a hidden hard-coded allowlist on the supported path
- the browser workbench exposes every model or workload entry present in that generated file
- mode changes alter the catalog content without changing the route structure

## Sprint 5.1: Demo Web Application Host (PureScript) [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/package.json`, `web/spago.yaml`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Close the web hosting contract while keeping one stable browser entrypoint across the routed
cluster path and the Apple host bridge.

### Deliverables

- repo-owned browser application code lives under `web/src/*.purs`; the supported implementation
  is a PureScript demo application built through `npm --prefix web run build`, which runs
  `spago build` plus `spago bundle --module Main --outfile dist/app.js --platform browser --bundle-type app`
  into `web/dist/`
- the demo HTTP host is the `infernix-demo` Haskell binary (Phase 4 Sprint 4.4), which serves the
  PureScript bundle from `web/dist/` and exposes the demo API surface
- the `infernix-demo` workload deployment is owned by `chart/templates/deployment-demo.yaml`,
  gated by `.Values.demo.enabled` (driven from the active `.dhall` `demo_ui` flag)
- in containerized execution contexts, the `infernix-demo` workload mounts
  `ConfigMap/infernix-demo-config` read-only at `/opt/build/` and reads the active-mode `.dhall`
  from that watched runtime directory
- the supported path does not depend on a host-only webserver for `/`; on Apple host the
  equivalent surface is `infernix-demo serve --dhall PATH --port N` against a host-side `.dhall`
- the shared Gateway or HTTPRoute surface routes `/` to the `infernix-demo` workload when the
  demo surface is enabled, and the `/` route is absent from the edge inventory when the demo
  surface is disabled

### Validation

- `curl http://127.0.0.1:<port>/` returns the frontend entrypoint on the routed cluster-resident path
- the browser workbench loads through the routed surface and consumes the active generated catalog
- `infernix cluster up` deploys the `infernix-demo` workload through Helm (when `demo_ui` is on)
  and serves that same route from the cluster

### Remaining Work

None.

---

## Sprint 5.2: Haskell-Owned Frontend Contract via purescript-bridge [Done]

**Status**: Done
**Implementation**: `src/Generated/Contracts.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Models.hs`, `src/Infernix/Types.hs`, `web/src/Generated/Contracts.purs`, `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/test/Main.purs`, `infernix.cabal`, `web/package.json`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`

### Objective

Keep Haskell types authoritative and make the webapp build consume generated bindings rather than
hand-maintained duplicates.

### Deliverables

- the supported web build generates PureScript contract modules from Haskell-owned DTO and catalog
  records
- the supported demo application imports those build-generated PureScript modules from
  `web/src/Generated/` for request and response shapes; no handwritten duplicate request or
  response types remain on the supported path
- the generated PureScript module lives in `web/src/Generated/Contracts.purs` and is emitted by
  `infernix internal generate-purs-contracts`; `npm --prefix web run build` invokes the same
  command before `spago build`
- the bridge-owned Haskell contract surface lives in `src/Generated/Contracts.hs`, while the
  generated runtime constants and catalog values are sourced from `src/Infernix/Models.hs`,
  `src/Infernix/Types.hs`, and the routed API domain in `src/Infernix/Demo/Api.hs`
- the generated PureScript module exposes `newtype` wrappers plus explicit helper functions that
  unwrap record views for frontend code and frontend tests
- the generated PureScript module also carries explicit `Simple.JSON` `ReadForeign` and
  `WriteForeign` instances so the frontend can decode routed `/api` payloads without hand-written
  duplicate codecs
- no standalone public frontend codegen command exists outside `infernix internal generate-purs-contracts`

### Validation

- repeated web builds generate the same `Generated.Contracts` module deterministically
- `infernix test unit` fails if the web build or frontend tests detect drift from the Haskell source
- the web build succeeds using only the build-generated PureScript contract module for shared
  types
- no tracked `web/src/Generated/` artifact remains in version control on the supported path; the
  directory is rebuilt by `infernix internal generate-purs-contracts` on every web build

### Remaining Work

None.

---

## Sprint 5.3: Frontend Contract and View-Level Coverage via purescript-spec [Done]

**Status**: Done
**Implementation**: `web/test/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/src/Generated/Contracts.purs`, `src/Infernix/CLI.hs`
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
- contract tests fail when request or response shapes drift from the Haskell-owned source
- view-level specs cover model selection and result rendering states
- contract and view-level specs fail when the rendered catalog order or membership drifts from the
  active generated catalog

### Remaining Work

None.

---

## Sprint 5.4: Manual Inference Workbench in PureScript For Any Registered Model [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/src/index.html`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Deliver the browser workbench the user asked for: manual inference against any model in the
catalog.

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

None.

---

## Sprint 5.5: Web Runtime Image and Playwright Dependency Ownership [Active]

**Status**: Active
**Blocked by**: Phase 4 Sprint 4.9
**Implementation**: `docker/linux-base.Dockerfile`, `docker/linux-cpu.Dockerfile`, `docker/linux-cuda.Dockerfile`, `web/playwright/`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/deployment-service.yaml`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Fold the packaged PureScript demo bundle and the Playwright executor into the per-substrate
container (Phase 4 Sprint 4.9). One custom container per Linux substrate carries the built web
bundle, the PureScript toolchain (only when the bundle is rebuilt during the image build), and
Playwright + browser dependencies; on Apple Silicon the operator runs Playwright from the host
through `infernix test e2e` against the host node install.

### Deliverables

- the per-substrate Linux Dockerfile (Phase 4 Sprint 4.9) installs `purescript`, `spago`, and
  the npm dependencies long enough to bundle the demo UI into `web/dist/`, then installs
  Chromium, WebKit, and Firefox plus Playwright system deps; the built `web/dist/` bundle is
  copied into `/srv/web/` and is served by the in-cluster `infernix-demo` workload mounting the
  same image
- `infernix test e2e --runtime-mode linux-cpu|linux-cuda` launches Playwright from the
  substrate container; on Apple Silicon, `infernix test e2e --runtime-mode apple-silicon`
  launches Playwright from the operator's host node install
- the chart no longer deploys a separate `infernix-web` workload or Service; the routed `/`
  surface is served only by `infernix-demo`
- `web/Dockerfile` is deleted; the corresponding entry in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) Pending Removal moves to
  Completed when the deletion lands

### Validation

- a substrate-container build produces a working Playwright runner (`docker run --rm <substrate-image>
  npx playwright --version`) without a separate web image
- `./.build/infernix --runtime-mode apple-silicon test e2e` passes against the host's
  Playwright install
- `docker compose run --rm <substrate-image> infernix --runtime-mode linux-cpu test e2e` passes
  with Playwright launched from inside the substrate container
- the repository ships no `web/Dockerfile` after the migration; `infernix lint chart` rejects
  any chart manifest reusing the legacy `infernix-web` image coordinate

### Remaining Work

- `web/Dockerfile` is deleted from the worktree, the Linux substrate Dockerfiles now build the
  bundle and install Playwright, and `infernix test e2e` is retargeted toward the substrate image
  on Linux and the host install on Apple Silicon
- this sprint still needs successful substrate-image builds and routed Playwright runs on those
  final execution paths before it can close

---

## Sprint 5.6: Mode-Driven Demo Catalog and Workbench Parity in PureScript [Done]

**Status**: Done
**Implementation**: `web/src/Main.purs`, `web/src/Infernix/Web/Workbench.purs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/development/testing_strategy.md`

### Objective

Make the browser workbench a faithful reflection of the generated catalog for the active runtime
mode.

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

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/web_ui_architecture.md` - UI topology and cluster-hosting rule
- `documents/development/frontend_contracts.md` - build-time contract generation policy for the webapp image
- `documents/development/testing_strategy.md` - frontend unit and Playwright coverage model

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - manual inference workbench behavior, route inventory, and active-mode catalog rules

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) aligned when UI request shapes, generated-demo-config fields, or API routes change
