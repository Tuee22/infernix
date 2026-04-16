# Phase 5: Web UI and Shared Types

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the PureScript web application, the Haskell-owned frontend contract, and
> the manual inference workbench that lets a user run inference against any registered model in the
> active runtime mode.

## Current Repo Assessment

The repository already has a browser workbench, generated frontend contract artifacts, and
Playwright scaffolding. The missing closure work is that the UI does not yet consume the final
generated mode-specific demo catalog or guarantee parity with every supported entry in the active
runtime mode.

## Demo Catalog Contract

This phase owns the browser-side interpretation of the generated demo catalog.

- the demo UI catalog comes only from the active runtime mode's ConfigMap-backed mounted `.dhall`
- the UI does not maintain a hidden hard-coded allowlist on the supported path
- the browser workbench must expose every model or workload entry present in that generated file
- mode changes alter the catalog content without changing the route structure

## Sprint 5.1: PureScript Web Application and Cluster Webapp Service [Active]

**Status**: Active
**Implementation**: `web/src/`, `web/dist/`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Create the cluster-resident webapp service that serves the browser UI in every supported mode.

### Deliverables

- PureScript application under `web/src/`
- cluster-resident webapp image, built from a separate webapp binary via `web/Dockerfile`, that
  serves the built frontend
- the webapp service deployment is owned by repo Helm chart templates and values
- in containerized execution contexts, the webapp workload mounts
  `ConfigMap/infernix-demo-config` read-only at `/opt/build/` and reads the active-mode `.dhall`
  from that watched runtime directory
- no supported host-only webserver path
- the edge proxy routes `/` to this service on every supported path

### Validation

- `infernix cluster up` deploys the webapp service into Kind
- the webapp service workload originates from the repo Helm chart rather than raw manifests
- the webapp workload reads the active-mode demo catalog from the ConfigMap-backed `/opt/build/`
  mount rather than an image-baked file
- `curl http://127.0.0.1:<port>/` returns the frontend entrypoint
- the same route works whether the Haskell daemon is cluster-resident or host-native

### Remaining Work

- move the current static browser workbench into its own runtime image and deployment surface
- close the remaining cluster-resident hosting rules once the Kind and Helm path lands

---

## Sprint 5.2: Haskell-Owned Frontend Contract and Build-Time Generation [Active]

**Status**: Active
**Implementation**: `src/Infernix/CLI.hs`, `web/build.mjs`, `web/generated/`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`

### Objective

Keep Haskell types authoritative and make the webapp build consume generated bindings rather than
hand-maintained duplicates.

### Deliverables

- `web/Dockerfile` generates the API and domain contract modules from Haskell-owned types during
  the webapp image build
- PureScript application code imports those build-generated modules for request and response shapes
- no handwritten duplicate API DTO modules remain on the supported path
- no standalone `infernix codegen purescript` command exists

### Validation

- repeated webapp image builds generate the same frontend contract modules deterministically
- `infernix test unit` fails if the webapp build or frontend tests detect drift from the Haskell source
- PureScript compilation succeeds using only the build-generated contract modules for shared types

### Remaining Work

- extend the current generated JavaScript contract module into the planned frontend language-specific binding set
- keep the generation entrypoint hidden behind the build flow rather than promoting it to a public CLI surface
- align generated frontend contracts with the final matrix-driven demo catalog schema

---

## Sprint 5.3: `purescript-spec` Contract and View-Level Coverage [Active]

**Status**: Active
**Implementation**: `web/test/contracts.test.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Use `purescript-spec` to verify the frontend stays aligned with the Haskell-owned contract and the
manual inference UI behaves predictably.

### Deliverables

- `purescript-spec` suites for generated codecs, model-list rendering, manual inference forms, and result presentation
- the generated codecs under test come from the webapp build-time contract generation path
- no alternative frontend test framework is the authoritative contract gate
- frontend tests run through the CLI-owned validation surface

### Validation

- `infernix test unit` runs the PureScript `purescript-spec` suites alongside Haskell unit tests
- contract tests fail when request or response shapes drift
- view-level specs cover model selection and result rendering states

### Remaining Work

- migrate the current generated-contract and view smoke tests into the planned frontend-native spec stack
- deepen browser-independent coverage for request-shape rendering and result-state transitions
- add assertions that the rendered catalog matches the active generated demo config exactly

---

## Sprint 5.4: Manual Inference Workbench For Any Registered Model [Done]

**Status**: Done
**Implementation**: `web/src/app.js`, `web/src/index.html`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Deliver the browser workbench the user asked for: manual inference against any model in the catalog.

### Deliverables

- model catalog browser with search or filter support
- per-model request form derived from the model's declared request contract
- submission, progress, and result views for manual inference
- links to large MinIO-backed outputs when the service returns references rather than inline payloads

### Validation

- the UI can select any registered model and submit a request through `/api`
- the UI shows typed validation errors when the request shape does not match the selected model
- at least one model from each initially supported family has a covered manual inference path

### Remaining Work

None. Active-mode exhaustive catalog parity is tracked in Sprint 5.6.

---

## Sprint 5.5: Web Image Owns Playwright Dependencies [Active]

**Status**: Active
**Implementation**: `web/package.json`, `web/playwright.config.js`, `web/playwright/`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Prepare the web image to be both the UI host and the E2E execution environment.

### Deliverables

- `infernix cluster up` builds the webapp image through `web/Dockerfile` as part of the canonical deploy flow
- the built webapp image is uploaded to Harbor before Helm rollout
- the webapp image installs Chromium, WebKit, and Firefox dependencies for Playwright
- browser binaries live in the same image that serves the UI
- `infernix test e2e` targets that same image rather than a separate ad hoc browser image

### Validation

- `infernix cluster up` produces a Harbor-published web image consumable by Helm
- the built web image can serve the UI and launch Playwright browsers
- `infernix test e2e` can execute inside the web image without extra host browser setup
- the repository does not maintain a second dedicated Playwright-only image

### Remaining Work

- move the current local Playwright dependency path into the eventual web runtime image
- validate E2E execution from that same runtime image on the outer-container path
- tie the final browser suite to the active generated demo catalog

---

## Sprint 5.6: Mode-Driven Demo Catalog and Workbench Parity [Blocked]

**Status**: Blocked
**Blocked by**: `3.6`, `4.6`
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

- browser-visible catalog entries match the active ConfigMap-backed generated demo config exactly
- removing an entry from the generated mode config removes it from the UI without extra frontend edits
- switching from Apple to Linux CPU to Linux CUDA changes the catalog and engine metadata in the expected way

### Remaining Work

- wire the final generated mode-specific ConfigMap-backed `.dhall` into the webapp
- expand UI states until every supported active-mode entry has a usable workbench path

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/web_ui_architecture.md` - UI topology and cluster-hosting rule
- `documents/development/frontend_contracts.md` - build-time contract generation policy for the webapp image
- `documents/development/testing_strategy.md` - PureScript and Playwright coverage model

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - manual inference workbench behavior, route inventory, and active-mode catalog rules

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) aligned when UI request shapes, generated-demo-config fields, or API routes change
