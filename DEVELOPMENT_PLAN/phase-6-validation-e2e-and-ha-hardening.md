# Phase 6: Validation, E2E, and HA Hardening

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported static-quality and test matrix for the two-binary topology,
> the Pulsar-driven production inference surface, the demo UI host, the per-mode generated
> catalog, the mandatory HA behavior of Harbor, MinIO, operator-managed PostgreSQL, and Pulsar,
> and the remaining repository-hardening follow-ons that keep governed root docs, route-aware
> docs, and the CLI surface mechanically aligned with implementation.

## Phase Status

Sprints 6.1 through 6.12 are `Done`. Sprints 6.13 and 6.14 are `Planned`. The validation
entrypoints, active-mode catalog coverage, clean-host bootstrap logic, governed-root-document
metadata closure, structured CLI-registry closure, route-aware docs, assistant-workflow
canonicalization, and shared workflow-helper reuse are all present in the current worktree. The
remaining open work imported from `INFERNIX_IMPROVEMENTS_FROM_MATTANDJAMES.md` is doctrinal rather
than runtime: the broad engineering docs still need stronger structure, deeper boundary or state
coverage, a fuller Haskell-guide split, and an explicit monitoring stance.

## Current Repo Assessment

The repository already has lint, unit, integration, and Playwright entrypoints. The canonical
testing, boundary, portability, storage, and Haskell-style docs are landed, and the baked Linux
substrate image now carries the source-snapshot manifest needed for git-less `infernix lint
files` runs. The routed Playwright suite exhaustively exercises every demo-visible generated
catalog entry, the integration suite enumerates every generated active-mode catalog entry while
also carrying Harbor, MinIO, Pulsar, and Harbor PostgreSQL recovery or lifecycle checks in code,
the Apple host-native path now reconciles its remaining supported prerequisites from the
Homebrew-plus-ghcup baseline, the governed root docs now carry the stricter metadata model, and
the structured Haskell command registry now owns parsing, help output, and the generated
CLI-reference sections that docs lint enforces. The route-oriented docs now consume
registry-backed generated sections, the root assistant entry docs point at one canonical
assistant-workflow document under `documents/`, and the cluster path reuses the shared
web-dependency readiness helper instead of reimplementing it. The remaining gap inside this phase
is documentation-depth closure: the broad engineering docs still need the stronger summary or
current-status or validation structure described in `development_plan_standards.md`,
`documents/engineering/implementation_boundaries.md` and `documents/engineering/storage_and_state.md`
still need deeper ownership and lifecycle treatment, `documents/development/haskell_style.md`
still needs the editor-only and typed-control-flow review doctrine, and the repository still needs
an explicit monitoring decision tied to the dormant `victoria-metrics-k8s-stack` chart setting.

## Validation Surface

The supported validation entrypoints are:

- `infernix lint files`
- `infernix lint docs`
- `infernix lint proto`
- `infernix lint chart`
- `infernix docs check`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`

These commands are declarative and idempotent validation entrypoints. Re-running them rechecks the
same contract and may reconcile supported prerequisites instead of depending on alternate setup
commands.

## Mode-Matrix Validation Contract

- `test unit` proves matrix typing, generated catalog rendering, and contract-generation logic
- `test integration` validates the active runtime mode's published catalog contract, routed
  surfaces, and routed inference execution for every generated active-mode catalog entry
- `test e2e` exercises every demo-visible generated catalog entry for the active runtime mode
- the full repository closes only when Apple, Linux CPU, and Linux CUDA runs all pass on their
  supported lanes

## Sprint 6.1: Static Quality Gates, Testing Doctrine, and Unit Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Files.hs`, `test/haskell-style/Spec.hs`, `test/unit/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`, `documents/engineering/storage_and_state.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the control plane, shared
contracts, and generated-catalog logic, and put the validation doctrine in canonical docs.

### Deliverables

- `infernix test lint` is the canonical static-quality entrypoint
- the repo-owned lint layer enforces whitespace, newline, tab, docs, chart, proto, and tracked-file policy
- the Haskell style guide clearly separates:
  - hard gates enforced mechanically
  - review guidance that remains human doctrine
  - the enforcement model implemented in `src/Infernix/Lint/HaskellStyle.hs`
- the Haskell style guide states the fail-fast rule explicitly: validation fails on hard-gate
  violations and does not silently rewrite tracked source
- `documents/engineering/testing.md` becomes the canonical testing doctrine
- `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`,
  and `documents/engineering/storage_and_state.md` are expanded so boundary, portability, and
  durability rules are canonical and testable
- `infernix test unit` remains the canonical unit-suite entrypoint for Haskell and PureScript

### Validation

- `infernix test lint` passes when repo-owned lint, docs, and compiler-warning policy are satisfied
- Haskell formatting or lint drift fails `cabal --builddir=.build/cabal test infernix-haskell-style`
- `infernix test unit` runs both Haskell and frontend unit suites
- docs validation fails if canonical testing or boundary docs drift from the supported implementation

### Remaining Work

None.

---

## Sprint 6.2: Extensive Integration Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Exercise the generated demo-config and service integration path on the final Kind, Helm, Harbor,
MinIO, Pulsar, and operator-managed PostgreSQL substrate.

### Deliverables

- integration coverage for `cluster up`, generated demo-config publication, and routed inference
  execution for every generated active-mode catalog entry
- host-native integration coverage proves the routed API can move to the Apple host bridge without
  changing the browser-visible entrypoint
- dedicated `linux-cuda` integration coverage proves device-plugin rollout, GPU resources, and
  service GPU visibility
- integration coverage proves routed cache mutation and publication surfaces stay aligned with the
  generated catalog contract

### Validation

- `infernix test integration` reconciles or reuses supported cluster prerequisites
- integration tests fail when publication state, generated catalog publication, per-entry routed
  inference execution, service-loop schema publication, or CUDA scheduling assertions regress

### Remaining Work

None.

---

## Sprint 6.3: Routed Playwright E2E Coverage [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `web/playwright/inference.spec.js`, `web/test/run_playwright_matrix.mjs`, `web/package.json`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`

### Objective

Keep routed Playwright validation on the supported final execution paths while exercising the real
browser surface through the shared edge.

### Deliverables

- Playwright suites live under the UI-owned `web/playwright/` surface
- `infernix test e2e` exercises the routed browser surface launched from the substrate image on Linux
  or the host install on Apple Silicon
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`
- E2E covers publication details, model selection, manual inference submission, and result rendering

### Validation

- `infernix test e2e` hits the routed path rather than bypassing the edge
- the routed Playwright suite fails if any active-mode catalog entry is skipped
- Apple host E2E and Linux substrate-image E2E both pass on their supported lanes

### Remaining Work

None.

---

## Sprint 6.4: HA Failure and Recovery Coverage For Harbor, MinIO, and Pulsar [Done]

**Status**: Done
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/chaos_testing.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Back the HA claims with concrete failure coverage.

### Deliverables

- pod-deletion and rolling-restart coverage for Harbor application-plane workloads
- durability and failover coverage for MinIO on the mandatory HA topology
- message continuity and restart coverage for Pulsar on the mandatory HA topology

### Validation

- supported HA subsets prove single-pod failure does not permanently break the supported path
- data written before MinIO or Pulsar restarts remains available afterward
- Harbor-backed image pulls continue to work after supported Harbor pod replacement

### Remaining Work

None.

---

## Sprint 6.5: Cluster Lifecycle and Environment-Matrix Validation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `compose.yaml`, `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-cuda.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Verify the same product contract across Apple host-native and Linux outer-container workflows.

### Deliverables

- the codebase exposes `cluster up`, `cluster status`, and `cluster down` through both execution contexts
- automated coverage proves repo-local kubeconfig, generated demo-config, publication mirror, and
  publication state creation for the active runtime mode
- `cluster status` reports runtime mode, build or data roots, publication details, and chosen edge port

### Validation

- `infernix test integration` proves the host-native lane creates the expected repo-local state
- validation proves the Linux outer-container lane can reach the cluster through its supported path
- repeated `cluster up` or `cluster down` behavior and `9090`-first edge-port rediscovery remain stable

### Remaining Work

None.

---

## Sprint 6.6: Per-Mode Exhaustive Integration and E2E Coverage [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/Files.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`

### Objective

Make the README promise concrete: for the active runtime mode, validation covers every generated
catalog entry using the engine binding selected for that mode.

### Deliverables

- `infernix test integration` enumerates every active-mode catalog entry from the generated demo config
- `infernix test e2e` is specified to exercise every demo-visible active-mode entry through the
  routed browser surface
- `infernix test all` aggregates lint, unit, integration, and E2E without silently dropping catalog entries
- default matrix coverage keeps Apple and Linux CPU in scope and includes Linux CUDA on supported hosts

### Validation

- changing the active runtime mode changes the exercised catalog and engine assertions automatically
- integration fails if any generated catalog entry is skipped
- routed E2E fails if any demo-visible generated catalog entry is skipped once Sprint 6.3 closes

### Remaining Work

None.

---

## Sprint 6.7: Operator-Managed PostgreSQL Failure and Lifecycle Coverage [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/postgresql.md`

### Objective

Back the PostgreSQL doctrine with readiness, failover, and storage-rebind coverage.

### Deliverables

- integration coverage proves Percona and Patroni readiness for Harbor and later PostgreSQL-backed services
- HA-failure coverage deletes or restarts a PostgreSQL member and verifies failover
- lifecycle coverage proves `cluster down` plus `cluster up` reuses the same deterministic Harbor
  PostgreSQL PV inventory and host paths
- validation proves services do not regress to chart-managed standalone PostgreSQL deployments

### Validation

- `infernix test integration` verifies ready operator-managed PostgreSQL members, Patroni failover,
  and deterministic Harbor PV and host-path rebinding
- repeated cluster lifecycle validation fails if Harbor PostgreSQL no longer reuses the same
  deterministic PV inventory and host paths

### Remaining Work

None.

---

## Sprint 6.8: Minimal Host Prerequisites and Clean-Host Bootstrap Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Python.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Minimize host-side prerequisites and let `infernix` reconcile the remaining supported operator
toolchain from package managers instead of depending on a broad preinstalled Apple host stack.

### Deliverables

- Apple host-native flow reduces pre-existing host requirements to Homebrew plus ghcup before
  building `./.build/infernix`
- Colima is the only supported Docker environment on Apple Silicon, and the supported Apple path
  installs or starts Colima through Homebrew-managed tooling
- after the Apple binary exists, `infernix` can reconcile the remaining supported Homebrew-managed
  operator tools needed by the active path, including the Docker CLI, `kind`, `kubectl`, `helm`,
  Node.js, and Playwright prerequisites
- when Apple adapter flows first need Poetry and the `poetry` executable is absent, `infernix`
  can bootstrap Poetry through the host's built-in Python and then continue all host-side Python
  management through the shared Poetry project
- `linux-cpu` host prerequisites stop at Docker Engine plus the Docker Compose plugin
- `linux-cuda` host prerequisites stop at Docker Engine plus the supported NVIDIA driver and
  container-toolkit setup
- clean-host validation proves the supported commands reconcile prerequisites rather than relying on
  undocumented manual setup beyond those minimal host baselines

### Validation

- on a clean Apple Silicon host with only Homebrew plus ghcup present,
  `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
  succeeds, and `./.build/infernix --runtime-mode apple-silicon cluster up` reconciles the
  remaining supported Apple host prerequisites through the supported package-manager path
- Apple host validation proves the supported flow can bootstrap Poetry when absent and then run the
  adapter setup path without manual Poetry installation
- on a clean Linux CPU host with Docker only,
  `docker compose build infernix` plus `docker compose run --rm infernix infernix --runtime-mode linux-cpu test all`
  passes
- on a clean Linux CUDA host with Docker plus the supported NVIDIA host prerequisites,
  `docker build -f docker/linux-substrate.Dockerfile --build-arg RUNTIME_MODE=linux-cuda --build-arg BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04 -t infernix-linux-cuda:local .`
  plus the direct `linux-cuda` `test all` lane passes

### Remaining Work

None.

---

## Sprint 6.9: Governed Root-Document Metadata Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `documents/README.md`

### Objective

Close the stricter governed-root-document metadata model so the root entry documents match the
standards they already cite.

### Deliverables

- `README.md` carries the governed root-document metadata block appropriate for an orientation
  document and makes its canonical-home links explicit
- `AGENTS.md` and `CLAUDE.md` carry the explicit supersession or canonical-home markers required
  for governed entry documents and now stay thin while linking to the canonical assistant-workflow
  document under `documents/`
- `documents/documentation_standards.md` describes the root-document metadata contract in the same
  terms the repo actually enforces
- the docs linter grows root-document checks strong enough to catch missing root-document metadata
  markers rather than relying on convention alone

### Validation

- `infernix docs check` fails when `README.md`, `AGENTS.md`, or `CLAUDE.md` are missing the
  required governed metadata markers for their declared role
- root docs carry the governed metadata and canonical-home links needed for the canonical
  assistant-workflow entrypoint without losing the canonical topic entrypoints

### Remaining Work

None.

---

## Sprint 6.10: True Single-Definition CLI Registry Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Lint/Docs.hs`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `test/unit/Spec.hs`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `README.md`

### Objective

Collapse the supported CLI surface into one structured Haskell definition so parsing, help text,
and the canonical CLI reference stop drifting independently.

### Deliverables

- one structured Haskell registry owns supported command parsing, help text, and command-family
  metadata
- the canonical CLI reference derives from that same structured registry or from a mechanically
  equivalent generated artifact rather than a separate handwritten command inventory
- `documents/reference/cli_surface.md` remains a short family overview that summarizes and links to
  the canonical CLI reference
- docs lint validates the stronger CLI-registry contract instead of only checking that registry
  command lines appear somewhere in the reference document

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command
  families from the same structured registry source
- changing a supported command in the structured registry changes parsing, help output, and CLI
  reference material through one implementation path
- `infernix docs check` fails when the CLI reference drifts from the structured command registry

### Remaining Work

None.

---

## Sprint 6.11: Registry-Backed Route Docs and Lint Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Routes.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Lint/Docs.hs`, `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining route or publication DRY cleanup so the Haskell route registry drives
route-aware docs and validation, not only runtime rendering and Helm values.

### Deliverables

- the Haskell route registry remains the source of truth for rendered HTTPRoutes, publication
  state, and route-aware documentation summaries
- route-oriented docs consume registry-backed rendered content or a mechanically equivalent
  generated section instead of independent handwritten route inventories
- docs lint and chart lint validate the route-aware contract from registry-backed expectations
  rather than ad hoc phrase checks
- the cleanup ledger records no remaining handwritten route-inventory or route-aware lint
  duplication once the sprint closes

### Validation

- `GET /api/publication` still reports the exact route inventory produced by the registry
- `infernix docs check` fails when a registry-owned route summary drifts from the corresponding docs
  section
- `infernix test lint` fails when route-aware lint or chart expectations diverge from the
  registry-backed route contract
- routed Harbor, MinIO, Pulsar, and demo probes continue to pass on the shared edge

### Remaining Work

None.

---

## Sprint 6.12: Assistant Workflow Canonicalization and Workflow-Helper Deduplication [Done]

**Status**: Done
**Implementation**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `src/Infernix/Workflow.hs`, `src/Infernix/Cluster.hs`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining REPO_DRY_CLEANUP follow-ons for assistant-facing root guidance and shared
workflow-helper closure.

### Deliverables

- repo-level assistant workflow doctrine moves into one canonical governed document under
  `documents/`
- `AGENTS.md` and `CLAUDE.md` become thin governed entry docs that summarize and link to that
  canonical assistant-workflow doc instead of carrying long parallel rule sets
- `src/Infernix/Workflow.hs` owns shared web-dependency readiness, npm invocation resolution,
  platform-command availability checks, and shared generated-file banner constants; cluster and CLI
  paths reuse it instead of re-declaring their own readiness probes
- the cleanup ledger no longer tracks duplicated assistant guidance or duplicated web-dependency
  readiness logic once the sprint closes

### Validation

- `infernix docs check` fails if the canonical assistant-workflow doc or the root-doc links drift
- `rg -n "webBuildToolchainPresent|ensureWebBuildDependencies" src/Infernix` shows one supported
  readiness implementation path rather than parallel cluster-local copies
- supported CLI, docs, and outer-container flows still install web dependencies through the shared
  helper

### Remaining Work

None.

---

## Sprint 6.13: Engineering Doctrine Depth and Haskell Guide Completion [Planned]

**Status**: Planned
**Implementation**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `documents/documentation_standards.md`

### Objective

Finish the remaining `mattandjames`-inspired doctrine-depth work so the broad engineering docs and
the Haskell guide match the stronger structure already required by
`development_plan_standards.md`.

### Deliverables

- broad governed engineering docs that define supported contracts add the stronger structure from
  `development_plan_standards.md`: `TL;DR` or `Executive Summary` when the topic is broad,
  explicit `Current Status` notes when current behavior and target direction mix, and explicit
  `Validation` sections when tests or lint prove the contract
- `documents/engineering/implementation_boundaries.md` gains an ownership matrix for Haskell,
  Python, chart, and generated surfaces together with adapter-local-versus-shared-contract type
  boundaries, instance placement rules, and module-boundary doctrine
- `documents/engineering/storage_and_state.md` gains an owner or durability table plus
  failure-mode, rebuild, and cleanup rules for durable and derived state
- `documents/engineering/portability.md` explicitly separates portable platform invariants from
  local harness detail and names which differences are supported product contract versus substrate
  implementation detail
- `documents/engineering/testing.md` keeps the canonical testing doctrine in the stronger
  structure and explicitly calls out preflight expectations, unsupported paths, and per-layer
  validation obligations
- `documents/development/haskell_style.md` points directly at `src/Infernix/Lint/HaskellStyle.hs`,
  separates repository hard-gate inputs from editor-only guidance, and adds review doctrine for
  module shape, function shape, effect-boundary clarity, and typed control flow
- `src/Infernix/Lint/Docs.hs` enforces the required broad-doctrine sections for the docs whose
  structure is part of the supported contract

### Validation

- `infernix docs check` fails when the named doctrine docs lose their required
  summary-or-current-status-or-validation structure or contradict their enforced metadata contract
- `infernix test lint` still passes once the deeper doc structure and Haskell-guide references land
- `cabal --builddir=.build/cabal test infernix-haskell-style` remains the implementation-aligned
  Haskell style gate described by the guide

### Remaining Work

- rewrite the named doctrine docs to the stronger structure and depth
- add the targeted docs-lint checks for the required sections
- rerun `infernix docs check` and `infernix test lint` after the documentation rewrite lands

---

## Sprint 6.14: Monitoring Stance Resolution and Final Doctrine Closure [Planned]

**Status**: Planned
**Implementation**: `documents/engineering/monitoring.md`, `documents/README.md`, `chart/values.yaml`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/monitoring.md`, `documents/README.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Resolve the supported monitoring stance explicitly instead of leaving a conditional placeholder in
the plan and a dormant monitoring stack toggle in chart values.

### Deliverables

- the repository carries one explicit supported-contract decision for monitoring instead of a
  dangling placeholder
- if monitoring remains a first-class supported surface, `documents/engineering/monitoring.md`
  exists as the canonical doctrine and states required outcomes, low-cardinality rules, typed
  event-or-metric expectations, ownership, and launch-gate consequences
- if monitoring is not a first-class supported surface, governed docs and the plan explicitly say
  so, and dormant monitoring configuration such as the disabled `victoria-metrics-k8s-stack` chart
  value is either removed or tracked as unsupported cleanup in
  `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
- the docs index and system component inventory point at the chosen monitoring stance so readers do
  not infer support from leftover config alone
- `src/Infernix/Lint/Docs.hs` checks that the plan and governed docs agree on the chosen
  monitoring stance

### Validation

- `infernix docs check` fails if the plan, docs index, and monitoring doctrine or
  unsupported-surface statement diverge
- if monitoring is supported, the canonical monitoring doc is reachable from `documents/README.md`
  and the relevant plan docs
- if monitoring is unsupported, no governed doc claims first-class monitoring and any dormant
  compatibility config is either removed or recorded in the cleanup ledger

### Remaining Work

- choose the supported monitoring stance
- either land the monitoring doctrine doc or record the unsupported-surface cleanup and remove the
  phase placeholders

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - root-document metadata contract and canonical-home markers
- `documents/engineering/edge_routing.md` - route-registry ownership, generated route summaries, and route-aware validation expectations
- `documents/engineering/testing.md` - canonical testing doctrine, core principles, preflight expectations, unsupported paths, and per-layer validation obligations
- `documents/development/testing_strategy.md` - operator workflow, matrix selection, and test-entrypoint details
- `documents/development/haskell_style.md` - hard gates, review guidance, direct enforcement-model pointer, repo-hard-gate versus editor-only guidance split, and fail-fast rule
- `documents/development/chaos_testing.md` - HA failure and recovery coverage
- `documents/development/assistant_workflow.md` - canonical repository-level assistant workflow doctrine for governed root entry docs
- `documents/engineering/implementation_boundaries.md` - ownership matrix, adapter-local versus shared-contract types, instance placement, and module-boundary rules
- `documents/engineering/portability.md` - portable invariants versus substrate-specific detail, plus explicit current-status and validation sections where target direction still appears
- `documents/engineering/storage_and_state.md` - owner or durability table, failure-mode rules, and cleanup contracts
- `documents/engineering/monitoring.md` - required outcomes, low-cardinality or typed-event rules, and launch-gate consequences if monitoring remains a first-class supported surface
- `documents/operations/cluster_bootstrap_runbook.md` - test prerequisites and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations
- `documents/tools/postgresql.md` - PostgreSQL operator readiness and failover rules
- `documents/engineering/docker_policy.md` - Colima-only Apple Docker guidance and minimal Linux host prerequisites
- `documents/development/python_policy.md` - Poetry bootstrap boundary for Apple hosts

**Product or reference docs to create/update:**
- `README.md` - orientation layer with governed root-document metadata and canonical-home links
- `AGENTS.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `CLAUDE.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/cli_surface.md` - short command-family overview that links to the canonical CLI reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations and active-mode catalog behavior

**Cross-references to add:**
- keep [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) aligned
  when governed root-document metadata rules change
- keep [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  aligned when command-registry ownership or CLI-reference derivation rules change
- keep [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
  aligned when HA claims, route assumptions, or active-mode validation rules change
- keep [system-components.md](system-components.md) aligned when the supported monitoring stance
  changes
- keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when any pending
  route-doc, route-lint, assistant-doc, workflow-helper, or monitoring-surface cleanup item closes
