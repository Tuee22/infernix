# Phase 0: Documentation and Governance

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the governed `documents/` suite, the standards that keep the plan and
> docs aligned, and the documentation-first baseline that all later implementation phases depend on.

## Documentation-First Gate

Phase 0 closes the documentation bootstrap only. Later phases still own follow-on documentation
work whenever the implementation direction changes, but they do so on top of the governed suite and
lint rules established here.

## Current Repo Assessment

The governed `documents/` suite, root docs, and development plan now describe the same
staged-substrate mechanics and the same final Apple product shape. The repository and README
matrix still point at `apple-silicon` as the Apple-native inference lane, and the governed docs
now match that contract explicitly: Apple host workflows stage `./.build/infernix-substrate.dhall`
through `./.build/infernix internal materialize-substrate apple-silicon`, Linux outer-container
workflows stage `./.build/outer-container/build/infernix-substrate.dhall` on the host through
`docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`,
and the routed Apple path is described consistently as host-native inference plus clustered support
services and an optional clustered demo surface that bridges into the host daemon. `infernix lint docs`
and `infernix docs check` remain the governed validation entrypoints for that closure.

## Sprint 0.1: `documents/` Suite Scaffold [Done]

**Status**: Done
**Implementation**: `documents/README.md`, `documents/architecture/overview.md`
**Docs to update**: `README.md`, `documents/README.md`

### Objective

Create the governed `documents/` suite and make it the canonical home for repository
documentation.

### Deliverables

- `documents/` exists as a governed docs root with architecture, development, engineering,
  operations, reference, tools, and research sections
- `documents/README.md` acts as the docs-suite index
- root `README.md` points readers into the governed docs suite rather than acting as the only doc home

### Validation

- the `documents/` tree exists in the repository
- `documents/README.md` indexes the governed docs sections

### Remaining Work

None.

---

## Sprint 0.2: Documentation Standards and Suite Rules [Done]

**Status**: Done
**Implementation**: `documents/documentation_standards.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `documents/documentation_standards.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Define how governed docs, root workflow guidance, and later plan updates stay aligned.

### Deliverables

- `documents/documentation_standards.md` defines canonical topic ownership and summary-versus-source rules
- root automation guidance is explicitly governed instead of ad hoc
- the repo has a documentation-maintenance rule set that later phases can rely on

### Validation

- governed-doc standards exist in the worktree
- root workflow docs refer to the governed standards

### Remaining Work

None.

---

## Sprint 0.3: Canonical Documentation Set [Done]

**Status**: Done
**Implementation**: `documents/`
**Docs to update**: `documents/architecture/overview.md`, `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`, `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, `documents/engineering/storage_and_state.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/postgresql.md`, `documents/tools/pulsar.md`

### Objective

Create the initial canonical document set for the supported platform contract.

### Deliverables

- core architecture, development, engineering, operations, reference, and tool docs exist
- the docs suite covers the supported CLI, substrate contract, generated catalog, cluster
  lifecycle, storage doctrine, routing, model catalog, and demo UI surface
- later phases can update one canonical document per topic instead of inventing new topic homes

### Validation

- the listed governed docs exist
- the docs suite covers the supported architecture and workflow topics

### Remaining Work

None.

---

## Sprint 0.4: Documentation Validation and Plan Harmony [Done]

**Status**: Done
**Implementation**: `src/Infernix/Lint/Docs.hs`, `README.md`
**Docs to update**: `documents/documentation_standards.md`, `documents/README.md`, `README.md`

### Objective

Make documentation drift mechanically visible and keep the plan aligned with the governed docs.

### Deliverables

- the repo-local docs validator exists
- documentation standards, the docs index, and the development plan are cross-linked
- documentation changes can be checked through a canonical repo-local validation path

### Validation

- the docs validator runs on the supported path
- governed docs and the plan cross-reference one another

### Remaining Work

None.

---

## Sprint 0.5: Substrate Matrix Documentation Realignment [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/model_lifecycle.md`, `documents/tools/pulsar.md`, `documents/reference/web_portal_surface.md`

### Objective

Align the plan and docs around the substrate matrix and generated catalog contract.

### Deliverables

- the plan distinguishes execution context from supported substrate
- the README matrix is treated as the source of truth for generated catalog selection
- the governed docs reference the staged substrate file, its generated catalog, and the current
  `runtimeMode`-labeled publication surfaces

### Validation

- the plan and governed docs use aligned substrate vocabulary while acknowledging the current
  `runtimeMode` serialization used by generated payloads
- the generated demo-config contract is described consistently across the listed docs

### Remaining Work

None.

---

## Sprint 0.6: Doctrine Realignment Across Documentation Suite [Done]

**Status**: Done
**Implementation**: `documents/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/architecture/overview.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/development/python_policy.md`, `documents/development/purescript_policy.md`, `documents/engineering/edge_routing.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/model_lifecycle.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`, `documents/tools/pulsar.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Bring the governed docs into alignment with the two-binary topology, Pulsar production surface,
demo-only HTTP surface, and generated-catalog architecture baseline.

### Deliverables

- the docs suite describes `infernix` and `infernix-demo` as the supported binary topology
- production inference is documented as Pulsar-only
- demo HTTP, browser workbench, and generated frontend contracts are documented as demo-only surfaces
- later implementation phases inherit a coherent docs baseline instead of mixed legacy language

### Validation

- the listed docs no longer describe the retired single-binary or Python-HTTP product shape
- documentation validation catches the retired-doctrine vocabulary tracked in the cleanup ledger

### Remaining Work

None.

---

## Sprint 0.7: Doctrine Realignment for Gateway API, Honest Runtime Model, and Hygiene [Done]

**Status**: Done
**Implementation**: `documents/engineering/edge_routing.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/development/python_policy.md`, `documents/development/purescript_policy.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/web_portal_surface.md`, `documents/architecture/overview.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/development/python_policy.md`, `documents/development/purescript_policy.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/web_portal_surface.md`, `documents/architecture/overview.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Realign the documentation suite around Envoy Gateway routing, the honest Apple-versus-Linux runtime
model, build-artifact hygiene, and the later DRY cleanup direction.

### Deliverables

- routing docs describe Gateway API ownership instead of repo-owned proxy processes
- build-artifact docs describe generated outputs as disposable and untracked
- operator docs distinguish Apple host-native execution from Linux outer-container execution
- later phases inherit explicit documentation obligations for the shared Linux substrate image, the
  shared Python adapter project, the command registry, and the route registry

### Validation

- the listed docs use the Gateway, Harbor-first, manual-storage, and generated-artifact vocabulary
- later phases can reference these docs without redefining the same governance baseline

### Remaining Work

None.

---

## Sprint 0.8: Substrate Doctrine Documentation Reset [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/architecture/overview.md`, `documents/architecture/runtime_modes.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`

### Objective

Realign the governed docs around the substrate-generated `.dhall` doctrine before the later
implementation follow-ons claim closure against it.

### Deliverables

- the governed docs describe substrates rather than user-selected runtime-mode flags as the final
  supported selection contract
- Apple operator docs describe the Apple lane as a hybrid topology: host-native control plane,
  host-native inference daemon, cluster-resident support services, and an optional cluster-resident
  routed demo surface
- Apple docs distinguish the retired direct host `infernix-demo serve` story from the supported
  Apple host-inference bridge used when the routed demo surface stays in the cluster
- Apple docs do not describe Kind, Docker, or other containerized Apple workloads as having
  Metal or unified-memory parity with the host daemon
- Linux operator docs describe Compose as the single supported outer-container launcher for both
  `linux-cpu` and `linux-gpu`, with no supported Linux host-native build or CLI flow
- validation docs describe single-substrate integration and E2E ownership rather than default
  cross-substrate matrix coverage or simulated fallback evidence
- validation docs describe the comprehensive model, format, and engine matrix in `README.md` as the
  authoritative integration-test coverage ledger, with one `.dhall`-driven integration suite that
  chooses the active engine per supported row or reference
- validation docs describe Playwright as substrate-agnostic at the browser layer and make
  `infernix-demo` responsible for reading the active `.dhall` and dispatching the correct engine
- governed docs describe simulation as removed from the supported runtime and validation contract,
  not merely unsupported evidence
- root guidance names the explicitly materialized substrate `.dhall` as the single source of truth
  for active substrate, generated catalog, daemon placement, and validation scope

### Validation

- `infernix lint docs` passes after the governed docs and root docs are updated to describe the
  current staged-substrate flow honestly
- `infernix docs check` fails if the governed docs or root docs claim Cabal compile-time substrate
  generation, first-command auto-generation, file-absent fallback, or runtime-specific in-cluster
  substrate filenames that the code no longer uses
- `infernix docs check` fails if the governed docs still describe Apple clustered repo workloads
  as the canonical Apple inference executor or describe the retired direct host
  `infernix-demo serve` path as the final routed demo contract
- `infernix docs check` fails if the governed docs still describe browser-side substrate selection,
  separate per-substrate integration suites, or any simulated fallback as part of the supported
  contract

### Remaining Work

None.

## Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - canonical ownership and summary-versus-source rules
- `documents/README.md` - docs-suite index and entry points
- `documents/engineering/build_artifacts.md` - build-artifact and generated-output doctrine
- `documents/engineering/edge_routing.md` - routing ownership baseline

**Product or reference docs to create/update:**
- `README.md` - orientation layer aligned with the governed docs
- `AGENTS.md` - governed automation entry document
- `CLAUDE.md` - governed automation entry document

**Cross-references to add:**
- keep [DEVELOPMENT_PLAN/README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) aligned when documentation governance or
  architecture-baseline language changes
