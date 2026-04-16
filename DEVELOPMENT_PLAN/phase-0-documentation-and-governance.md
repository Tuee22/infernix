# Phase 0: Documentation and Governance

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md), [00-overview.md](00-overview.md)

> **Purpose**: Create the governed `documents/` suite, define documentation maintenance rules, and
> make the development plan and docs suite stay aligned as the repository grows.

## Documentation-First Gate

This phase closes before any code-writing phase begins.

- Phases 1-6 remain blocked until these documentation sprints close.
- The repo writes the docs suite before the implementation tree grows around it.

## Sprint 0.1: `documents/` Suite Scaffold [Planned]

**Status**: Planned
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

---

## Sprint 0.2: Documentation Standards and Suite Rules [Planned]

**Status**: Planned
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

---

## Sprint 0.3: Canonical Documentation Set [Planned]

**Status**: Planned
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

---

## Sprint 0.4: Documentation Validation and Plan Harmony [Planned]

**Status**: Planned
**Docs to update**: `documents/documentation_standards.md`, `documents/README.md`, `README.md`

### Objective

Make doc consistency a first-class gate and keep the plan and governed docs synchronized.

### Deliverables

- `infernix docs check` validates required headers, relative links, and plan or docs cross-references
- the plan remains authoritative for implementation status
- the docs suite remains authoritative for architecture and operator guidance once the relevant docs exist

### Validation

- `infernix docs check` passes after documentation edits
- changing a canonical route, storage rule, or CLI command requires updating the plan and the owning docs in the same change
- stale references to disallowed README-only architecture guidance fail the docs validation path

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - suite governance and SSoT rules
- `documents/architecture/overview.md` - implemented topology
- `documents/development/local_dev.md` - supported local workflows
- `documents/development/frontend_contracts.md` - Haskell-owned frontend contract and webapp build-time generation rules
- `documents/development/haskell_style.md` - Haskell formatter, lint, and compiler-warning policy
- `documents/development/testing_strategy.md` - supported validation matrix
- `documents/engineering/build_artifacts.md` - builddir and generated-artifact isolation
- `documents/engineering/docker_policy.md` - outer-container rules
- `documents/engineering/k8s_storage.md` - manual PV doctrine
- `documents/engineering/edge_routing.md` - one-port route policy
- `documents/engineering/k8s_native_dev_policy.md` - Kind and Helm workflow
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/engineering/model_lifecycle.md` - artifact lifecycle and local materialization
- `documents/engineering/storage_and_state.md` - durable versus derived state
- `documents/architecture/model_catalog.md` - model registration and selection
- `documents/architecture/runtime_modes.md` - host and cluster daemon modes
- `documents/architecture/web_ui_architecture.md` - cluster-resident webapp service and UI topology
- `documents/reference/cli_reference.md` - CLI surface
- `documents/reference/cli_surface.md` - CLI summary surface
- `documents/reference/api_surface.md` - typed API contract
- `documents/reference/web_portal_surface.md` - browser surface
- `documents/tools/harbor.md` - Harbor notes
- `documents/tools/minio.md` - MinIO notes
- `documents/tools/pulsar.md` - Pulsar notes

**Product or reference docs to create/update:**
- `documents/README.md` - suite index and navigation

**Cross-references to add:**
- keep [README.md](README.md), [development_plan_standards.md](development_plan_standards.md), and [00-overview.md](00-overview.md) aligned once the documentation suite exists
