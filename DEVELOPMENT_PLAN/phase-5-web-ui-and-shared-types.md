# Phase 5: Web UI and Shared Types

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the browser workbench target, the Haskell-owned frontend contract, and the
> manual inference workbench that lets a user run inference against any registered model in the
> active runtime mode.

## Current Repo Assessment

The repository already has a browser workbench, build-generated JavaScript frontend contracts, and
routed Playwright coverage. The current browser workbench now loads from the cluster-resident web
workload on the supported Kind path, build-root frontend contract staging is closed, and both
browser-independent and browser-driven coverage prove catalog parity, publication-detail rendering,
and result rendering through the routed cluster edge. Same-image browser execution now passes from
the built web image on both current control-plane lanes, and the Apple host-native final-substrate
lane now also passes while serving the UI from the Harbor-published web image. The workbench now
renders family-aware request guidance and result framing for every generated entry.

## Demo Catalog Contract

This phase owns the browser-side interpretation of the generated demo catalog.

- the demo UI catalog comes only from the active runtime mode's generated demo catalog; the current
  supported path proves this through generated staging, the repo-local publication mirror, and the
  mounted ConfigMap-backed `.dhall`
- the UI does not maintain a hidden hard-coded allowlist on the supported path
- the browser workbench must expose every model or workload entry present in that generated file
- mode changes alter the catalog content without changing the route structure

## Sprint 5.1: Web Application Host and Cluster Webapp Service [Done]

**Status**: Done
**Implementation**: `web/src/`, `web/dist/`, `tools/service_server.py`, `web/Dockerfile`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Close the web hosting contract while keeping one stable browser entrypoint across the
cluster-resident webapp service and the Apple host bridge.

### Deliverables

- repo-owned browser application code lives under `web/src/`; the current implementation is a
  JavaScript workbench built from generated contracts
- a cluster-resident webapp image, built via `web/Dockerfile`, serves the built frontend on the
  supported Kind path
- the webapp service deployment is owned by repo Helm chart templates and values
- in containerized execution contexts, the webapp workload mounts
  `ConfigMap/infernix-demo-config` read-only at `/opt/build/` and reads the active-mode `.dhall`
  from that watched runtime directory
- the supported path does not depend on a host-only webserver for `/`
- the edge proxy routes `/` to this service on every supported path

### Validation

- `curl http://127.0.0.1:<port>/` returns the frontend entrypoint on the routed cluster-resident path
- the browser workbench loads through the routed surface and consumes the active generated catalog
- `infernix cluster up` deploys the webapp service through Helm and serves that same route from the cluster

### Remaining Work

None.

---

## Sprint 5.2: Haskell-Owned Frontend Contract and Build-Time Generation [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `web/build.mjs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`

### Objective

Keep Haskell types authoritative and make the webapp build consume generated bindings rather than
hand-maintained duplicates.

### Deliverables

- the supported web build generates the API and domain contract modules from Haskell-owned types
- the current browser application imports those build-generated JavaScript modules for request and
  response shapes
- the generated contract module is staged under the active build root and copied into
  `web/dist/generated/contracts.js` for runtime use
- no handwritten duplicate API DTO modules remain on the supported path
- no standalone public frontend codegen command exists

### Validation

- repeated web builds generate the same frontend contract modules deterministically
- `infernix test unit` fails if the webapp build or frontend tests detect drift from the Haskell source
- the web build succeeds using only the build-generated contract modules for shared types
- no tracked `web/generated/Generated/contracts.js` artifact remains on the supported path

### Remaining Work

None.

---

## Sprint 5.3: Frontend Contract and View-Level Coverage [Done]

**Status**: Done
**Implementation**: `web/test/contracts.test.mjs`, `web/src/workbench.js`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Use repo-owned frontend tests to verify the browser workbench stays aligned with the Haskell-owned
contract and behaves predictably.

### Deliverables

- frontend unit suites for generated contracts, model-list rendering, manual inference forms,
  request-shape presentation, and result presentation
- the generated codecs under test come from the webapp build-time contract generation path
- no alternative frontend test framework is the authoritative contract gate
- frontend tests run through the CLI-owned validation surface
- the browser-independent view model proves that the rendered catalog matches the generated catalog exactly

### Validation

- `infernix test unit` runs the frontend unit suites alongside Haskell unit tests
- contract tests fail when request or response shapes drift
- view-level specs cover model selection and result rendering states
- contract and view-level specs fail when the rendered catalog order or membership drifts from the
  active generated catalog

### Remaining Work

None.

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
- links to large object-store-backed outputs when the service returns references rather than inline payloads

### Validation

- the UI can search, select a catalog entry, and submit a request through `/api`
- routed Playwright coverage proves the workbench can render object-reference result links for
  large outputs
- every registered model remains manually callable through the same `/api` surface, while richer
  per-family browser flows close in Sprint 5.6

### Remaining Work

None. Active-mode exhaustive catalog parity is closed in Sprint 5.6.

---

## Sprint 5.5: Web Runtime Image and Playwright Dependency Ownership [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `tools/publish_chart_images.py`, `web/package.json`, `web/playwright.config.js`, `web/playwright/`, `web/Dockerfile`, `docker/infernix.Dockerfile`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/architecture/web_ui_architecture.md`

### Objective

Prepare the web image to be both the UI host and the E2E execution environment.

### Deliverables

- `infernix cluster up` now builds the webapp image through `web/Dockerfile` as part of the canonical deploy flow
- the built webapp image is uploaded to Harbor before Helm rollout
- the current `web/Dockerfile` installs Chromium, WebKit, and Firefox dependencies for Playwright
- browser binaries live in the same image that serves the UI
- `infernix test e2e` now targets that same web image rather than a separate ad hoc browser image
- the outer-container control-plane image no longer carries a duplicate Playwright browser installation

### Validation

- the current `web/Dockerfile` can build and serve the static web bundle and carries Playwright browser dependencies
- `./.build/infernix --runtime-mode apple-silicon test e2e` passes while launching Playwright from the built web image
- `docker compose run --rm infernix infernix --runtime-mode apple-silicon test e2e` passes while delegating browser execution to the built web image
- the repository does not maintain a second dedicated Playwright-only image
- `infernix cluster up` produces a Harbor-published web image consumable by Helm and the host-native routed E2E lanes exercise that same final-substrate image path across the runtime matrix

### Remaining Work

None.

---

## Sprint 5.6: Mode-Driven Demo Catalog and Workbench Parity [Done]

**Status**: Done
**Implementation**: `web/src/app.js`, `web/src/workbench.js`, `web/src/index.html`, `web/playwright/inference.spec.js`, `web/test/contracts.test.mjs`
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
- frontend unit and Playwright coverage prove the workbench renders family-aware request guidance,
  submit labels, artifact metadata, and result presentation without introducing UI-only catalog rules

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
