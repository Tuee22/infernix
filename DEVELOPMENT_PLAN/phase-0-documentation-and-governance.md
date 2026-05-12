# Phase 0: Documentation and Governance

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the governed `documents/` suite, the standards that keep the plan and
> docs aligned, and the documentation-first baseline that all later implementation phases depend on.

## Documentation-First Gate

Phase 0 closes the documentation bootstrap only. Later phases still own follow-on documentation
work whenever the implementation direction changes, but they do so on top of the governed suite and
lint rules established here.

## Current Repo Assessment

Phase 0 is reopened to distribute the Haskell CLI tool doctrine
(`HASKELL_CLI_TOOL.md`, root) across the governed `documents/` suite and to retire that root file
once the distribution lands. Sprints 0.1–0.8 remain `Done`. Sprint 0.9 owns the doctrine
distribution: the canonical homes are `documents/development/haskell_style.md`,
`documents/development/testing_strategy.md`, `documents/engineering/implementation_boundaries.md`,
`documents/engineering/build_artifacts.md`, `documents/engineering/k8s_storage.md`,
`documents/engineering/storage_and_state.md`, the new
`documents/engineering/daemon_lifecycle.md`, `documents/reference/cli_reference.md`,
`documents/architecture/runtime_modes.md`, and `documents/operations/cluster_bootstrap_runbook.md`.

Earlier phase 0 closure remains accurate: the governed `documents/` suite, root docs, and
development plan describe the same staged-substrate mechanics and the same final Apple product
shape. The repository and README matrix still point at `apple-silicon` as the Apple-native
inference lane, and the governed docs match that contract explicitly: Apple host workflows stage
`./.build/infernix-substrate.dhall` through `./.build/infernix internal materialize-substrate
apple-silicon`, Linux outer-container workflows stage
`./.build/outer-container/build/infernix-substrate.dhall` on the host through
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

---

## Sprint 0.9: Haskell CLI Doctrine Documentation Distribution [Planned]

**Status**: Planned
**Implementation**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/k8s_storage.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/daemon_lifecycle.md` (new), `documents/reference/cli_reference.md`, `documents/architecture/runtime_modes.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/k8s_storage.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/daemon_lifecycle.md`, `documents/reference/cli_reference.md`, `documents/architecture/runtime_modes.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Distribute every section of the root `HASKELL_CLI_TOOL.md` design notes into the canonical
governed-doc homes listed below, then retire the root file. The doctrine becomes plural homes
within the existing `documents/` suite rather than a single new canonical file.

### Distribution Map

| Doctrine area | Canonical home |
|---|---|
| Standard library stack, toolchain pin (GHC 9.14.1 / Cabal 3.16.1.0), `exitcode-stdio-1.0` | `documents/engineering/implementation_boundaries.md` |
| Library-first layout, thin `Main.hs`, typed `Command` ADT, `CommandSpec` SoT | `documents/engineering/implementation_boundaries.md` |
| GADT-indexed state machines plus singleton witnesses | `documents/engineering/implementation_boundaries.md` |
| Subprocesses as Typed Values (two-function interpreter `runStreaming` / `capture`) | `documents/engineering/implementation_boundaries.md` |
| Smart constructors for paired resources (PV+PVC) plus DNS-1123 naming helpers | `documents/engineering/k8s_storage.md` |
| Plan/Apply discipline with `--dry-run` and `--plan-file` | `documents/engineering/implementation_boundaries.md` |
| Prerequisites as Typed Effects (DAG, registry, transitive closure, error-message contract) | `documents/engineering/implementation_boundaries.md` |
| Output rules (stdout primary, stderr diagnostics, `--format` and `--color` flags) | `documents/reference/cli_reference.md` |
| `AppError` ADT plus boundary rendering plus `ErrorKind = Recoverable \| Fatal` | `documents/engineering/implementation_boundaries.md` |
| Capability classes, `ServiceError`, `AsServiceError`, generic retry combinator | `documents/engineering/implementation_boundaries.md` |
| `RetryPolicy` as first-class values, pure backoff, error classification | `documents/engineering/implementation_boundaries.md` |
| Daemon lifecycle (load → prereq → acquire → ready → serve → drain → exit), bracket discipline, structured concurrency, `forkIO` ban, `TMVar` shutdown | `documents/engineering/daemon_lifecycle.md` (new) |
| `/healthz`, `/readyz`, `/metrics` HTTP endpoints | `documents/engineering/daemon_lifecycle.md` (cross-link from `documents/architecture/runtime_modes.md`) |
| `co-log` structured JSON logging plus typed `field` helpers | `documents/engineering/daemon_lifecycle.md` |
| `Env` record (boot / live / logger / metrics / shutdown / resources plus test hooks) | `documents/engineering/daemon_lifecycle.md` |
| Dhall daemon config, `BootConfig` / `LiveConfig` split, SIGHUP via `TBQueue` worker, `schemaVersion` | `documents/engineering/daemon_lifecycle.md` |
| At-least-once event processing (`processed_at`, idempotent handlers, `created_at ASC`) | `documents/engineering/storage_and_state.md` |
| Reconcilers as canonical mutation entrypoint (no install / upgrade / repair / force split) | `documents/engineering/implementation_boundaries.md` (cross-link from `documents/operations/cluster_bootstrap_runbook.md`) |
| Generated Artifacts discipline (markers, `GeneratedSectionRule`, paired check/write, determinism, extension protocol, project-level standards subsection) | `documents/engineering/build_artifacts.md` |
| Forbidden Surfaces / Negative-Space Lint, `forbiddenPathRegistry` | `documents/engineering/build_artifacts.md` |
| Lint / format / code-quality stack: `fourmolu`, `fourmolu.yaml`, `hlint`, `.hlint.yaml`, `cabal format` round-trip, pinned formatter compiler under `.build/<project>-style-tools/`, paired `--write`, style as Cabal `test-suite` | `documents/development/haskell_style.md` |
| Test categories, separate Cabal `test-suite` stanzas (`infernix-unit`, `infernix-integration`, `infernix-haskell-style`, `infernix-daemon-lifecycle`), explicit Pulumi exception | `documents/development/testing_strategy.md` |
| Daemon Lifecycle Tests category | `documents/development/testing_strategy.md` |
| CLI introspection (`tool commands`, `--tree`, `--json`, `help <command>`) | `documents/reference/cli_reference.md` |

### Deliverables

- governed docs match the doctrine in every canonical home above
- `fourmolu` replaces `ormolu` language across `documents/development/haskell_style.md` and any
  governed text that still names the legacy formatter
- the toolchain pin `ghc-9.14.1` plus `Cabal 3.16.1.0` is documented in
  `documents/engineering/implementation_boundaries.md`
- the new `documents/engineering/daemon_lifecycle.md` exists and is cross-linked from
  `documents/architecture/runtime_modes.md` and
  `documents/operations/cluster_bootstrap_runbook.md`
- `documents/reference/cli_reference.md` carries the output-rules and CLI-introspection contract
- `documents/development/testing_strategy.md` lists exactly the four supported test-suite stanzas
  (`infernix-unit`, `infernix-integration`, `infernix-haskell-style`,
  `infernix-daemon-lifecycle`) and records the explicit Pulumi exception
- root `HASKELL_CLI_TOOL.md` is deleted and the deletion is ledgered in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- root `README.md`, `AGENTS.md`, and `CLAUDE.md` link into the new homes rather than duplicating
  doctrine content

### Validation

- `infernix lint docs` passes after the distributed governed docs and root docs are updated
- `infernix docs check` fails if any governed doc still names `ormolu` as canonical, omits the
  fourmolu pin, references the deleted root `HASKELL_CLI_TOOL.md`, or claims a `pulumi` stanza is
  part of the supported contract
- `src/Infernix/Lint/Docs.hs` gains validators for those drift conditions

### Remaining Work

As listed in deliverables until landed.

## Remaining Work

- Sprint 0.9 is `Planned` and not yet executed; the root `HASKELL_CLI_TOOL.md` still exists, the
  governed docs still describe the pre-doctrine formatter and test-stanza shape, and the new
  `documents/engineering/daemon_lifecycle.md` does not yet exist.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - canonical ownership and summary-versus-source rules
- `documents/README.md` - docs-suite index and entry points
- `documents/engineering/build_artifacts.md` - build-artifact, generated-output, and
  forbidden-surfaces doctrine
- `documents/engineering/edge_routing.md` - routing ownership baseline
- `documents/engineering/implementation_boundaries.md` - typed Command + CommandSpec, typed
  Subprocess, Plan/Apply, Prerequisites DAG, AppError, capability classes, RetryPolicy,
  reconciler discipline, GADT state machines
- `documents/engineering/k8s_storage.md` - smart constructors for paired resources, DNS-1123
  naming helpers
- `documents/engineering/storage_and_state.md` - at-least-once event processing with
  `processed_at` tracking
- `documents/engineering/daemon_lifecycle.md` (new) - seven-step daemon lifecycle, health
  endpoints, co-log structured logging, BootConfig/LiveConfig split, SIGHUP hot reload, Env
  record with test hooks

**Product or reference docs to create/update:**
- `README.md` - orientation layer aligned with the governed docs
- `AGENTS.md` - governed automation entry document
- `CLAUDE.md` - governed automation entry document
- `documents/development/haskell_style.md` - fourmolu + hlint + cabal format stack,
  `fourmolu.yaml` and `.hlint.yaml` pinning, paired `--write` semantics, style as Cabal
  test-suite stanza
- `documents/development/testing_strategy.md` - test-suite stanzas including
  `infernix-daemon-lifecycle`, daemon-lifecycle test category, explicit Pulumi exception
- `documents/reference/cli_reference.md` - stdout/stderr output rules, `--format` and
  `--color` flag contract, CLI introspection commands
- `documents/architecture/runtime_modes.md` - cross-link to `daemon_lifecycle.md`
- `documents/operations/cluster_bootstrap_runbook.md` - cross-link to reconciler discipline in
  `implementation_boundaries.md`

**Cross-references to add:**
- keep [DEVELOPMENT_PLAN/README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) aligned when documentation governance or
  architecture-baseline language changes
