# Phase 4: Inference Service and Durable Runtime

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the Haskell service runtime, the model and artifact contracts, and the
> stable API surface that both automation and the web UI depend on.

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`

### Objective

Make the service runtime strongly typed before the transport and UI surfaces accumulate logic.

### Deliverables

- Haskell-owned ADTs for service config, cluster mode, model catalog entries, inference request shapes, and inference result shapes
- one canonical model catalog surface that lists every registered model the UI may target
- explicit distinction between authoritative durable metadata and derived local cache state

### Validation

- `infernix test unit` covers config decoding, model-catalog parsing, and route or request ADTs
- the service rejects invalid model-catalog entries with typed errors
- the webapp Docker build can derive frontend contract modules from the Haskell SSOT without hand patches

---

## Sprint 4.2: Inference Request Pipeline Over Pulsar and MinIO [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`

### Objective

Use MinIO as the durable artifact home and Pulsar as the durable event transport without letting
derived local cache state become authoritative.

### Deliverables

- the service consumes inference requests from Pulsar or internal API submissions that share the same domain logic
- MinIO holds authoritative model artifacts, manifests, and large outputs
- the service writes large outputs to MinIO and returns typed references when payloads exceed inline limits
- local materialization is idempotent and cache-oriented, not authoritative

### Validation

- `infernix test integration` proves request receipt, model resolution, MinIO access, and result publication
- repeated artifact materialization does not corrupt or duplicate local cache state
- deleting local cache state does not destroy authoritative MinIO state

---

## Sprint 4.3: Host-Native Apple Runtime and Cluster Runtime Parity [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Keep one service binary and one runtime contract while allowing Apple host-native execution and
cluster-resident execution to coexist.

### Deliverables

- `infernix service` supports host-native Apple execution for direct local model runtimes
- the same executable can run in a cluster container on the Linux-supported path
- runtime config selects the correct MinIO and Pulsar access path without changing the API contract
- startup clearly reports whether the daemon is running host-side or cluster-side

### Validation

- Apple host-native `infernix service` can reach MinIO and Pulsar through the shared edge port
- cluster-resident `infernix service` can reach MinIO and Pulsar through cluster-local networking
- the web UI continues to work against `/api` in both modes

---

## Sprint 4.4: Manual Inference API Surface [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`
**Docs to update**: `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`

### Objective

Expose a stable API for listing models and submitting manual inference requests from the browser.

### Deliverables

- API endpoints or typed handlers for listing models, inspecting a model's supported request shape, submitting an inference request, and retrieving results
- request validation uses the same Haskell-owned model metadata used by automated flows
- the manual inference path can target any model present in the catalog, not a hard-coded allowlist

### Validation

- `infernix test integration` proves model listing and manual inference submission through the API
- invalid requests are rejected with typed user-facing errors rather than transport-level crashes
- at least one end-to-end path exercises browser submission through the same service API later used by Phase 6 Playwright coverage

---

## Sprint 4.5: Durable Service Cache and Reconcile Semantics [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`, `1.1-1.4`, `2.1-2.5`, `3.1-3.5`
**Docs to update**: `documents/engineering/model_lifecycle.md`, `documents/engineering/storage_and_state.md`

### Objective

Make derived runtime state reproducible from durable sources and keep lifecycle cleanup explicit.

### Deliverables

- local service cache roots live under `./.data/runtime/`
- cache directories are keyed by model identity and runtime mode
- cache eviction is explicit and does not touch authoritative MinIO objects
- cluster reconcile and service startup can rebuild derived state from durable sources

### Validation

- deleting a local runtime cache followed by service startup reconstructs it without data loss
- `infernix test integration` proves the service can recover from cache loss using only durable sources
- status reporting distinguishes durable state from derived cache state

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/runtime_modes.md` - service deployment modes and parity rules
- `documents/architecture/model_catalog.md` - model registration and selection contract
- `documents/engineering/model_lifecycle.md` - MinIO authority, local materialization, and cache semantics
- `documents/engineering/storage_and_state.md` - durable versus derived state inventory

**Product or reference docs to create/update:**
- `documents/reference/api_surface.md` - browser and operator API contract
- `documents/reference/web_portal_surface.md` - manual inference user surface

**Cross-references to add:**
- keep [00-overview.md](00-overview.md), [system-components.md](system-components.md), and [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) aligned when the API or model catalog changes
