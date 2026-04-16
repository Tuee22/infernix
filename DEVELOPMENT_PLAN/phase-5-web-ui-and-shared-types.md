# Phase 5: Web UI and Shared Types

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the PureScript web application, the Haskell-owned frontend contract, and
> the manual inference workbench that lets a user run inference against any registered model.

## Sprint 5.1: PureScript Web Application and Cluster Webapp Service [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`, `4.1-4.5`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/reference/web_portal_surface.md`

### Objective

Create the cluster-resident webapp service that serves the browser UI in every supported mode.

### Deliverables

- PureScript application under `web/src/`
- cluster-resident webapp image, built from a separate webapp binary via `web/Dockerfile`, that
  serves the built frontend
- the webapp service deployment is owned by repo Helm chart templates and values
- no supported host-only webserver path
- the edge proxy routes `/` to this service on every supported path

### Validation

- `infernix cluster up` deploys the webapp service into Kind
- the webapp service workload originates from the repo Helm chart rather than raw manifests
- `curl http://127.0.0.1:<port>/` returns the frontend entrypoint
- the same route works whether the Haskell daemon is cluster-resident or host-native

---

## Sprint 5.2: Haskell-Owned Frontend Contract and Build-Time Generation [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`, `4.1-4.5`
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

---

## Sprint 5.3: `purescript-spec` Contract and View-Level Coverage [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`, `4.1-4.5`
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

---

## Sprint 5.4: Manual Inference Workbench For Any Registered Model [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`, `4.1-4.5`
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

---

## Sprint 5.5: Web Image Owns Playwright Dependencies [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`, `4.1-4.5`
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

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/web_ui_architecture.md` - UI topology and cluster-hosting rule
- `documents/development/frontend_contracts.md` - build-time contract generation policy for the webapp image
- `documents/development/testing_strategy.md` - PureScript and Playwright coverage model

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - manual inference workbench behavior and route inventory

**Cross-references to add:**
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) aligned when UI request shapes or API routes change
