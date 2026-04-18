# Phase 0: Documentation and Governance

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md), [00-overview.md](00-overview.md)

> **Purpose**: Create the governed `documents/` suite, define documentation maintenance rules, and
> make the development plan and docs suite stay aligned as the repository grows.

## Documentation-First Gate

This phase closes before later phases can close.

- Phases 1-6 are no longer phase-level blocked by documentation realignment.
- The repo writes and maintains the docs suite before more implementation-closure claims continue.

## Current Repo Assessment

The repository has a governed docs suite, and the governed docs align with the runtime-mode and
generated-demo-config contract.

- the docs suite distinguishes control-plane execution context from runtime mode
- the docs suite carries the README-scale model or format or engine matrix as a first-class
  planning and validation contract
- the docs suite documents generated mode-specific demo `.dhall` staging, ConfigMap-backed
  publication, `/opt/build/`, protobuf target contracts, `9090`-first edge-port selection, and
  active-mode exhaustive integration and E2E coverage
- `tools/docs_check.py` validates those phrases directly so later drift is caught early

## Sprint 0.1: `documents/` Suite Scaffold [Done]

**Status**: Done
**Implementation**: `documents/README.md`, `documents/architecture/overview.md`
**Docs to update**: `README.md`, `documents/README.md`

### Objective

Create a documentation suite shaped like the reference repositories rather than relying on README-only guidance.

### Deliverables

- `documents/README.md`
- `documents/documentation_standards.md`
- directory taxonomy:

```text
documents/
├── README.md
├── documentation_standards.md
├── architecture/
├── development/
├── engineering/
├── operations/
├── reference/
├── tools/
└── research/
```

- `documents/` becomes the canonical documentation home; `docs/` is not introduced

### Validation

- `find documents -maxdepth 1 -type d | sort` shows the governed suite structure
- `README.md` points to `documents/` and `DEVELOPMENT_PLAN/` rather than embedding layout sketches

### Remaining Work

None.

---

## Sprint 0.2: Documentation Standards and Suite Rules [Done]

**Status**: Done
**Implementation**: `documents/documentation_standards.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `documents/documentation_standards.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Create the documentation equivalent of the reference repositories' standards files.

### Deliverables

- `documents/documentation_standards.md` defines status metadata, naming rules, cross-link rules, and suite taxonomy
- the standards file explicitly states that `DEVELOPMENT_PLAN/` owns implementation status and phase closure
- contributor guidance in `AGENTS.md` and `CLAUDE.md` stays aligned with the docs workflow

### Validation

- every governed document begins with the required metadata block
- the standards file names the canonical suite taxonomy and the SSoT rules
- root guidance files do not contradict the documentation workflow

### Remaining Work

None.

---

## Sprint 0.3: Canonical Documentation Set [Done]

**Status**: Done
**Implementation**: `documents/`
**Docs to update**: `documents/architecture/overview.md`, `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`, `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, `documents/engineering/storage_and_state.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Create the minimum governed docs needed to explain the intended product before implementation begins, without overloading the README.

### Deliverables

- architecture docs for topology, runtime modes, model catalog, and web UI
- development docs for local setup, frontend contracts, Haskell style, and testing strategy
- engineering docs for build artifacts, Docker policy, storage, edge routing, object storage, and model lifecycle
- operations docs for cluster bootstrap and Apple Silicon workflow
- reference docs for API, CLI, and browser surfaces
- tools docs for Harbor, MinIO, and Pulsar

### Validation

- each major planned topic has exactly one canonical governed document before code writing starts
- README becomes an orientation document instead of the authoritative home of deep architecture rules
- inbound and outbound links across the suite resolve correctly

### Remaining Work

None.

---

## Sprint 0.4: Documentation Validation and Plan Harmony [Done]

**Status**: Done
**Implementation**: `tools/docs_check.py`, `README.md`
**Docs to update**: `documents/documentation_standards.md`, `documents/README.md`, `README.md`

### Objective

Make doc consistency a first-class gate and keep the plan and governed docs synchronized during the
bootstrap stage before the Haskell CLI owns the same workflow.

### Deliverables

- `tools/docs_check.py` validates required headers, relative links, and plan or docs cross-references
- the plan remains authoritative for implementation status
- the docs suite remains authoritative for architecture and operator guidance once the relevant docs exist
- Phase 1 wires the same validation logic into `infernix docs check`

### Validation

- `python3 tools/docs_check.py` passes after documentation edits
- changing a canonical route, storage rule, or CLI command requires updating the plan and the owning docs in the same change
- stale references to disallowed README-only architecture guidance fail the docs validation path

### Remaining Work

None. Runtime-mode matrix and generated-demo-config expansion lives in Sprint 0.5.

---

## Sprint 0.5: Runtime-Mode Matrix Documentation Realignment [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/model_lifecycle.md`, `documents/tools/pulsar.md`, `documents/reference/web_portal_surface.md`

### Objective

Realign the governed docs and plan around the updated README direction before more implementation
closure claims continue.

### Deliverables

- the plan and governed docs explicitly distinguish the two control-plane execution contexts from
  the three runtime modes
- the README matrix is reflected as the authoritative target coverage envelope in the plan and the
  owning governed docs
- the governed docs explain that `cluster up` stages `infernix-demo-<mode>.dhall` for the active
  runtime mode and publishes it into `ConfigMap/infernix-demo-config`
- the governed docs explain that the mounted ConfigMap-backed `.dhall` file is the exact source of
  truth for cluster-resident demo-visible models and their engine binding in that mode
- the governed docs explain that, in containerized execution contexts, the mounted `.dhall` lives
  at `/opt/build/` because the daemon watches the file next to its binary
- the governed docs explain that durable runtime manifests and Pulsar payloads are defined by
  repo-owned `.proto` schemas, with `proto-lens`-generated Haskell bindings and Pulsar built-in
  protobuf schema support
- the governed docs explain that `linux-cuda` requires a GPU-enabled Kind path with NVIDIA runtime
  support and `nvidia.com/gpu` advertising
- the governed docs explain that integration and E2E enumerate every generated catalog entry for
  the active mode and use the engine binding encoded in that file
- the governed docs explain that `cluster up` chooses the edge port by trying `9090` first,
  increments by 1 until open, records the result, and prints the chosen port to the operator
- the docs validator and documentation standards name these relationships clearly enough that later
  drift is caught quickly

### Validation

- runtime-mode, model-catalog, build-artifact, and testing-strategy docs all use the same runtime
  mode names and describe the same generated demo-config contract
- the plan, README, and docs suite all state that integration and E2E coverage are active-mode
  exhaustive rather than smoke-only when no explicit exception is called out
- `python3 tools/docs_check.py` passes after the alignment updates

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - suite governance and SSoT rules
- `documents/architecture/overview.md` - implemented topology
- `documents/development/local_dev.md` - supported local workflows
- `documents/development/frontend_contracts.md` - Haskell-owned frontend contract and webapp build-time generation rules
- `documents/development/haskell_style.md` - Haskell formatter, lint, and compiler-warning policy
- `documents/development/testing_strategy.md` - supported validation matrix and active-mode exhaustive coverage rules
- `documents/engineering/build_artifacts.md` - builddir, generated-demo-config staging, watched mount path, and artifact isolation
- `documents/engineering/docker_policy.md` - outer-container rules
- `documents/engineering/k8s_storage.md` - manual PV doctrine
- `documents/engineering/edge_routing.md` - `9090`-first one-port route policy and operator display
- `documents/engineering/k8s_native_dev_policy.md` - Kind, Helm, and GPU-enabled `linux-cuda` workflow
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/engineering/model_lifecycle.md` - artifact lifecycle and local materialization
- `documents/engineering/storage_and_state.md` - durable versus derived state
- `documents/architecture/model_catalog.md` - model registration, matrix row ownership, and generated catalog contract
- `documents/architecture/runtime_modes.md` - execution contexts versus runtime modes
- `documents/architecture/web_ui_architecture.md` - cluster-resident webapp service and UI topology
- `documents/reference/cli_reference.md` - CLI surface
- `documents/reference/cli_surface.md` - CLI summary surface
- `documents/reference/api_surface.md` - typed API contract
- `documents/reference/web_portal_surface.md` - browser surface and active-mode catalog behavior
- `documents/tools/harbor.md` - Harbor notes
- `documents/tools/minio.md` - MinIO notes
- `documents/tools/pulsar.md` - Pulsar notes

**Product or reference docs to create/update:**
- `documents/README.md` - suite index and navigation

**Cross-references to add:**
- keep [README.md](README.md), [development_plan_standards.md](development_plan_standards.md), [00-overview.md](00-overview.md), and the governed docs aligned on runtime-mode names, ConfigMap-backed generated demo-config semantics, the watched `/opt/build/` mount path, GPU-enabled `linux-cuda` rules, and active-mode test coverage
