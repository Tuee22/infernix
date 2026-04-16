# Phase 4: Inference Service and Durable Runtime

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the Haskell service runtime, the model and artifact contracts, the
> comprehensive matrix registry, and the stable API surface that both automation and the web UI
> depend on.

## Current Repo Assessment

The repository already has typed request or response shapes, a small seeded model catalog, and a
manual inference API path. The missing closure work is that the service does not yet own the full
README matrix, the final generated mode-specific demo-config contract, or the final `.proto`-based
manifest and Pulsar payload contract.

## Matrix Ownership Contract

This phase owns the conversion from README-scale planning matrix to runtime-consumable catalog.

- the service owns the typed registry that represents matrix rows
- the active runtime mode selects the engine column for each supported row
- `cluster up` emits that active-mode selection as `infernix-demo-<mode>.dhall` staging content and
  publishes it into `ConfigMap/infernix-demo-config`
- in containerized execution contexts, the service, web UI, integration suite, and E2E suite
  consume that exact generated catalog from the watched `/opt/build/` mount next to the binary

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`

### Objective

Make the service runtime strongly typed before the transport and UI surfaces accumulate logic.

### Deliverables

- Haskell-owned ADTs for service config, cluster mode, model catalog entries, inference request shapes, and inference result shapes
- one canonical model catalog surface that lists every registered model the UI may target
- explicit distinction between authoritative durable metadata and derived local cache state
- repo-owned `.proto` schemas under `proto/` define durable runtime manifests and Pulsar-carried
  inference lifecycle payloads
- generated `proto-lens` modules are the supported Haskell boundary for those protobuf contracts

### Validation

- `infernix test unit` covers config decoding, model-catalog parsing, and route or request ADTs
- `infernix test unit` covers protobuf encode or decode round-trips for durable manifests and
  Pulsar payload types through the generated `proto-lens` bindings
- the service rejects invalid model-catalog entries with typed errors
- the webapp Docker build can derive frontend contract modules from the Haskell SSOT without hand patches

### Remaining Work

None. Matrix-scale catalog expansion is tracked in Sprint 4.6.

---

## Sprint 4.2: Inference Request Pipeline Over Pulsar and MinIO [Active]

**Status**: Active
**Implementation**: `src/Infernix/Runtime.hs`, `tools/service_server.py`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`

### Objective

Use MinIO as the durable artifact home and Pulsar as the durable event transport without letting
derived local cache state become authoritative.

### Deliverables

- the service consumes inference requests from Pulsar or internal API submissions that share the same domain logic
- MinIO holds authoritative model artifacts, protobuf runtime manifests, and large outputs
- the service writes large outputs to MinIO and returns typed references when payloads exceed inline limits
- durable runtime manifests serialize from repo-owned `.proto` schemas through generated
  `proto-lens` bindings
- Pulsar topics carrying requests, results, and coordination events use Pulsar's built-in
  protobuf schema support rather than untyped payloads
- local materialization is idempotent and cache-oriented, not authoritative

### Validation

- `infernix test integration` proves request receipt, model resolution, MinIO access, and result publication
- `infernix test integration` proves manifest round-trips through the protobuf contract and verifies
  Pulsar topic publication or consumption against protobuf-backed schemas
- repeated artifact materialization does not corrupt or duplicate local cache state
- deleting local cache state does not destroy authoritative MinIO state

### Remaining Work

- replace the current repo-local filesystem transport with real Pulsar and object-store backends
- preserve the current typed request and result semantics across that backend swap
- thread active-mode catalog selection through the final transport-backed request pipeline
- replace ad hoc manifest and event serialization with the repo-owned `.proto` contract everywhere

---

## Sprint 4.3: Host-Native Apple Runtime and Cluster Runtime Parity [Active]

**Status**: Active
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/Config.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Keep one service binary and one runtime contract while allowing Apple host-native execution and
cluster-resident execution to coexist.

### Deliverables

- `infernix service` supports host-native Apple execution for direct local model runtimes
- the same executable can run in a cluster container on the Linux-supported path
- runtime config selects the correct MinIO and Pulsar access path without changing the API contract
- in containerized execution contexts, the service consumes the active mode's ConfigMap-backed
  mounted `.dhall` from `/opt/build/`, next to the binary it watches for changes
- startup clearly reports whether the daemon is running host-side or cluster-side

### Validation

- Apple host-native `infernix service` can reach MinIO and Pulsar through the shared edge port
- cluster-resident `infernix service` can reach MinIO and Pulsar through cluster-local networking
- cluster-resident `infernix service` reads the active-mode catalog from the watched `/opt/build/`
  mount rather than an image-baked static file
- the web UI continues to work against `/api` in both modes

### Remaining Work

- add the cluster-resident runtime variant
- validate runtime mode switching against a real routed platform substrate
- close explicit Linux CPU and Linux CUDA parity rather than treating them as one undifferentiated cluster mode

---

## Sprint 4.4: Manual Inference API Surface [Done]

**Status**: Done
**Implementation**: `tools/service_server.py`
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

### Remaining Work

None. Mode-scale catalog expansion is tracked in Sprint 4.6.

---

## Sprint 4.5: Durable Service Cache and Reconcile Semantics [Active]

**Status**: Active
**Implementation**: `src/Infernix/Runtime.hs`, `tools/service_server.py`
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

### Remaining Work

- surface cache and durable-state reporting through richer status commands
- replace local filesystem durability with the planned object-store-backed sources
- key cache semantics off the final matrix-driven runtime-mode catalog rather than the seeded model list

---

## Sprint 4.6: Comprehensive Matrix Registry, Generated Demo `.dhall`, and ConfigMap Publication [Blocked]

**Status**: Blocked
**Blocked by**: `0.5`, `1.5`, `2.6`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`

### Objective

Turn the README matrix into the typed source of truth that drives runtime binding, generated demo
catalogs, and later test enumeration.

### Deliverables

- the service owns a typed registry for every row in the README model or format or engine matrix
- each matrix row records workload identity, artifact or format family, reference model metadata,
  and per-mode engine bindings
- the active runtime mode selects the correct engine binding from the corresponding README matrix column
- CUDA-bound rows record the GPU runtime metadata needed for `linux-cuda` scheduling and engine
  selection on the GPU-enabled Kind substrate
- `cluster up` renders the active runtime mode's supported rows as `infernix-demo-<mode>.dhall`
  staging content and creates or updates `ConfigMap/infernix-demo-config`
- each generated `.dhall` entry records the matrix-row id, selected engine id, request or result
  contract identifiers, and runtime-lane metadata needed by the service, webapp, integration, and E2E layers
- in containerized execution contexts, cluster-resident consumers mount that ConfigMap read-only at
  `/opt/build/`, where the daemon watches the active-mode `.dhall` next to its binary
- rows whose active-mode column is `Not recommended` are absent from that mode's generated catalog
- across `apple-silicon`, `linux-cpu`, and `linux-cuda`, the generated catalogs cover every README matrix row

### Validation

- unit tests prove every supported matrix row appears in the correct generated mode catalog
- unit tests prove unsupported rows are absent from the active mode's generated catalog
- unit tests prove the engine binding encoded in `infernix-demo-<mode>.dhall` matches the
  corresponding README matrix column
- integration fixtures prove the published `ConfigMap/infernix-demo-config` content matches the
  generated active-mode catalog byte-for-byte before the service consumes it
- service startup fails when the generated catalog contains an invalid engine binding or missing contract metadata

### Remaining Work

- replace the seeded toy catalog with the comprehensive matrix registry
- implement the generated mode-specific `.dhall` renderer, ConfigMap publication path, and watched
  runtime consumers
- propagate the generated catalog to the web and validation layers

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/runtime_modes.md` - service deployment modes and parity rules
- `documents/architecture/model_catalog.md` - model registration, matrix row ownership, and generated catalog contract
- `documents/engineering/model_lifecycle.md` - MinIO authority, local materialization, and cache semantics
- `documents/engineering/storage_and_state.md` - durable versus derived state inventory
- `documents/development/testing_strategy.md` - active-mode catalog and engine-binding coverage

**Product or reference docs to create/update:**
- `documents/reference/api_surface.md` - browser and operator API contract
- `documents/reference/web_portal_surface.md` - manual inference user surface

**Cross-references to add:**
- keep [00-overview.md](00-overview.md), [system-components.md](system-components.md), and [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) aligned when the API, model catalog, or generated-demo-config contract changes
