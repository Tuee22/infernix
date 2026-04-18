# Phase 4: Inference Service and Durable Runtime

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the Haskell service runtime, the model and artifact contracts, the
> comprehensive matrix registry, and the stable API surface that both automation and the web UI
> depend on.

## Current Repo Assessment

The repository already has typed request or response shapes, typed runtime result metadata, a
README-matrix-backed generated catalog, and a manual inference API path served by
`tools/service_server.py` behind the Haskell CLI. The cluster-resident service path now mounts the
real `ConfigMap/infernix-demo-config` and publication ConfigMap on the Kind substrate, stores
protobuf manifests and results in MinIO, registers Pulsar protobuf schemas for request or result
or coordination topics, exposes explicit cache status or eviction or rebuild flows through both the
CLI and routed API, and can run host-native on the Apple control-plane path while the routed edge
keeps `/api` stable through the host bridge.

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
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Storage.hs`, `web/build.mjs`, `proto/infernix/...`, `tools/generated_proto/`, `tools/proto_check.py`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`

### Objective

Make the service runtime strongly typed before the transport and UI surfaces accumulate logic.

### Deliverables

- Haskell-owned ADTs for cluster state, generated demo config, model catalog entries, inference
  request shapes, and inference result shapes
- one canonical model catalog surface that lists every registered model the UI may target
- explicit distinction between authoritative durable metadata and derived local cache state
- the supported web build derives frontend contract modules from those Haskell-owned types rather
  than maintaining duplicate DTO definitions
- repo-owned `.proto` schemas under `proto/` now define the canonical durable runtime-manifest,
  inference-payload, and service-RPC message names
- generated `proto-lens` modules are the supported Haskell boundary for those protobuf contracts

### Validation

- `infernix test unit` covers runtime-mode selection, representative catalog membership or
  omission, generated demo-config rendering, invalid generated-catalog startup handling, and
  protobuf runtime-manifest round-trip coverage
- `infernix test lint` passes `tools/proto_check.py` against the repo-owned `.proto` contract set
- the current compatibility runtime rejects unsupported runtime modes and invalid request payloads
  with typed errors
- the supported web build can derive frontend contract modules from the Haskell SSOT without hand patches

### Remaining Work

None.

---

## Sprint 4.2: Inference Request Pipeline Over Pulsar and MinIO [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/Storage.hs`, `tools/runtime_backend.py`, `tools/service_server.py`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`

### Objective

Use MinIO and Pulsar for the routed service path without letting derived local cache state become
authoritative.

### Deliverables

- the routed service path consumes internal API submissions and stores durable results or large outputs through MinIO
- the same routed service path consumes inference requests and publishes results or coordination messages through Pulsar-backed topics
- MinIO holds authoritative model artifacts, protobuf runtime manifests, and large outputs for the routed service path
- the service writes large outputs to durable object storage and returns typed references when
  payloads exceed inline limits
- durable runtime manifests serialize from repo-owned `.proto` schemas through generated `proto-lens` bindings or the matching generated Python protobuf modules, depending on which service helper owns the boundary
- Pulsar topics carrying requests, results, and coordination events use Pulsar's built-in protobuf schema support rather than untyped payloads
- local materialization is idempotent and cache-oriented, not authoritative

### Validation

- `infernix test integration` proves cluster reconcile publishes the generated catalog, that
  per-entry inference execution succeeds on the final Kind and Helm substrate, that Pulsar topic
  schemas are published as protobuf, and that MinIO stores runtime results or manifests or large-output payloads
- `infernix test unit` proves large outputs return typed object references and that protobuf manifests or results round-trip through the supported storage helpers
- the routed service path persists runtime results in MinIO and exposes durable cache manifests through the routed cache lifecycle API

### Remaining Work

None.

---

## Sprint 4.3: Host-Native Apple Runtime and Cluster Runtime Parity [Done]

**Status**: Done
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/CLI.hs`, `tools/service_server.py`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
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

None.

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

- `infernix test e2e` proves routed model listing and manual inference submission through the same
  `/api` surface the workbench uses
- direct API calls to `/api/models/<id>` and `/api/inference/<id>` return typed model metadata and
  stored results on the current compatibility path
- invalid requests are rejected with typed user-facing errors rather than transport-level crashes
- at least one end-to-end path exercises browser submission through the same service API later used by Phase 6 Playwright coverage

### Remaining Work

None. Mode-scale catalog expansion is tracked in Sprint 4.6.

---

## Sprint 4.5: Durable Service Cache and Reconcile Semantics [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `tools/service_server.py`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/model_lifecycle.md`, `documents/engineering/storage_and_state.md`

### Objective

Make derived runtime state reproducible from durable sources and keep lifecycle cleanup explicit.

### Deliverables

- local service cache roots live under `./.data/runtime/`
- cache directories are keyed by model identity and runtime mode
- the current compatibility path materializes cache on demand from inference execution and keeps it
  derived rather than authoritative
- the current compatibility runtime writes durable cache manifests under
  `./.data/object-store/manifests/` and treats those manifests as the rebuild source for derived
  cache directories
- `infernix cache status`, `infernix cache evict`, and `infernix cache rebuild` provide explicit
  operator cache lifecycle flows without mutating unrelated runtime state
- the routed compatibility API now exposes `GET /api/cache`, `POST /api/cache/evict`, and
  `POST /api/cache/rebuild` so service-path cache semantics are testable through the same routed
  surface used by the browser and integration layers

### Validation

- `infernix test unit` proves inference execution materializes runtime cache under the runtime-mode
  and model-keyed cache root, writes durable cache manifests, and can evict or rebuild cache state
  from those manifests
- `infernix test integration` proves the routed service cache API can materialize, evict, and
  rebuild a representative cache entry without changing the generated catalog contract
- `infernix cluster status` distinguishes runtime result counts, object-store object counts,
  durable-manifest counts, and model-cache entry counts while reporting the relevant roots
- `infernix cache status` reports the active runtime mode, cache root, durable manifest root, and
  manifest-backed cache entry inventory

### Remaining Work

None. The final MinIO-backed durability swap remains tracked in Sprint 4.2.

---

## Sprint 4.6: Comprehensive Matrix Registry, Generated Demo `.dhall`, and ConfigMap Publication [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/test/contracts.test.mjs`
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

- unit tests prove generated catalog counts, representative row inclusion or omission, and
  runtime-mode rendering remain stable
- frontend contract checks prove the generated active-mode contract carries selected engines,
  runtime lanes, and mode-specific catalog counts
- integration fixtures prove the published `ConfigMap/infernix-demo-config` content matches the
  generated active-mode catalog byte-for-byte before the service consumes it and that serialized
  model ids and selected engines remain aligned with the typed registry
- service startup fails when the generated catalog contains missing required metadata or a
  mismatched runtime mode

### Remaining Work

None.

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
