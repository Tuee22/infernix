# Phase 0: Documentation and Governance

**Status**: Done. Sprint 0.36 closes this phase. Sprints 0.34 and 0.35 precede it: the first gives
the phase a closing sprint and bounds the mechanical governance set by name, the second retains the
attestation evidence a `Done` cites. Sprint 0.36 returns the phases carrying verified defects to
`Active`, corrects the claims that misdirect a reader, and states in the plan's entry document how
open work is identified. The phase is machine-independent throughout and carries no accelerator
cohort, so it blocks no accelerator phase and takes no `Done` away from one.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Establish the governed `documents/` suite, the standards that keep the plan and
> docs aligned, and the documentation-first baseline that all later implementation phases depend on.

## Documentation-First Gate

Phase 0 closes the documentation bootstrap only. Later phases still own follow-on documentation
work whenever the implementation direction changes, but they do so on top of the governed suite and
lint rules established here.

Phase 0 closes at Sprint 0.36 and does not reopen. A prose-only doctrine defect is recorded in
the sprint that finds it and is not scheduled as work of its own. A defect in a mechanism claim —
a document naming a construct that does not enforce what the document says it enforces — is a bug
in the phase that owns that code, and the documentation edit travels with the code fix rather than
becoming a governance sprint. This phase is machine-independent throughout: it carries no
accelerator cohort and blocks no accelerator phase.

## Current Repo Assessment

Every sprint is closed on the machine-independent plan/docs gates. The governed `documents/`
suite, the documentation standards, the docs validator, and the
plan-standards validator are in place. `infernix lint docs` and `infernix docs check` are the
governed validation entrypoints for documentation change; `infernix lint plan` is the mechanical
half of the plan standards, reports zero against the corpus, and runs inside the aggregate
`infernix test lint` gate. The governed-doc inventory contains no retired target, broken index link,
or orphaned conformance probe.

The governed docs, the root documents, and the development plan describe the same explicit-init
runtime-config mechanics and the Apple split-executor product shape. `infernix init` creates
repo-root `./infernix.dhall` plus `./infernix-host.dhall`, `infernix test init` creates the harness
input, ordinary config-dependent commands fail fast rather than auto-materializing missing config,
and the routed Apple path is clustered service orchestration plus host-native inference execution:
cluster daemons remain present, and Apple inference batches move through Pulsar into same-binary
host daemons. The repository and README matrix name `apple-silicon` as the Apple-native inference
lane.

The governed runbooks, testing docs, CLI references, and plan describe the supported first-run
convergence windows in `cluster up` and `cluster down`, name the long-running Docker build, registry
publication, registry-backed final-image preload, and Apple teardown data-sync phases explicitly, and
use inactivity-aware language instead of treating elapsed duration alone as product failure.

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
**Docs to update**: `documents/architecture/overview.md`, `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`, `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, `documents/engineering/storage_and_state.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/reference/web_portal_surface.md`, `documents/tools/registry.md`, `documents/tools/minio.md`, `documents/tools/postgresql.md`, `documents/tools/pulsar.md`

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
- the validator compares each marker-delimited generated section against the Haskell renderer that
  owns it, so a registry change that is not transcribed into the governed reference is a drift
  failure rather than a silent divergence

### Validation

- the docs validator runs on the supported path
- governed docs and the plan cross-reference one another
- the generated CLI-reference section byte-matches the command-registry renderer. The supported
  Linux lane validates the baked source snapshot rather than a working tree, so a section that
  drifts from the renderer cannot be repaired in place for that lane — the byte-match is a
  precondition of the lane's documentation gate, not a formatting preference

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

Bring the governed docs into alignment with the single `infernix` binary role topology, Pulsar
production surface, demo-only HTTP surface, and generated-catalog architecture baseline.

### Deliverables

- the docs suite describes `infernix` as the supported binary topology with Coordinator, Engine,
  and Webapp roles
- production inference is documented as Pulsar-only
- demo HTTP, browser SPA, and generated frontend contracts are documented as demo-only surfaces
- later implementation phases inherit a coherent docs baseline instead of mixed prior language

### Validation

- the listed docs no longer describe the prior Python-HTTP product shape or the retired
  two-binary Webapp split as current
- documentation validation catches the prior-doctrine vocabulary tracked in the cleanup ledger

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

- the listed docs use the Gateway, registry-first, manual-storage, and generated-artifact vocabulary
- later phases can reference these docs without redefining the same governance baseline

### Remaining Work

None.

---

## Sprint 0.8: Substrate Doctrine Documentation Reset [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/architecture/overview.md`, `documents/architecture/runtime_modes.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`

### Objective

Realign the governed docs around the substrate-generated `.dhall` doctrine that later
implementation follow-ons close against.

### Deliverables

- the governed docs describe substrates rather than user-selected runtime-mode flags as the final
  supported selection contract
- Apple operator docs distinguish Apple host-native control-plane execution from clustered support
  services and use the Phase 6 Sprint 6.25 cluster-daemon plus host-inference-executor wording
- Apple docs distinguish the prior direct host `infernix-demo serve` story from the supported
  Apple host-inference bridge used when the routed demo surface stays in the cluster
- Apple docs do not describe Kind, Docker, or other containerized Apple workloads as having
  Metal or unified-memory parity with the host inference daemon
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
  for active substrate, generated catalog, daemon behavior, and validation scope; Phase 6 Sprint
  6.25 extends that rule with explicit daemon role, inference placement, and Pulsar batch-topic
  wiring

### Validation

- `infernix lint docs` passes after the governed docs and root docs are updated to describe the
  current staged-substrate flow honestly
- `infernix docs check` fails if the governed docs or root docs claim Cabal compile-time substrate
  generation, first-command auto-generation, file-absent fallback, or runtime-specific in-cluster
  substrate filenames that the code no longer uses
- `infernix docs check` fails if the governed docs still describe Apple clustered repo workloads
  as having Apple-native inference parity or describe the prior direct host
  `infernix-demo serve` path as the final routed demo contract
- `infernix docs check` fails if the governed docs still describe browser-side substrate selection,
  separate per-substrate integration suites, or any simulated fallback as part of the supported
  contract

### Remaining Work

None.

---

## Sprint 0.9: Configuration Doctrine [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/development_plan_standards.md` (Sections T+U), `documents/architecture/configuration_doctrine.md` (new), `documents/engineering/host_tools_manifest.md` (new), `documents/engineering/cluster_config_manifest.md` (new), `documents/development/no_env_vars.md` (new), `documents/documentation_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: every doc named above

### Objective

Declare the no-env-var, absolute-path, three-Dhall-file configuration doctrine as the supported
contract, and enumerate the per-phase cleanup work (Sprints 1.11, 2.13, 3.10, 4.13, 5.9, 6.28,
7.17) that operationalizes it. Phase 0 owns the doctrine; the matching code changes land in the
later-phase cleanup sprints. The three configuration decoder types (`HostConfig`,
`ClusterConfig`, `SecretsConfig`; reflected to Dhall, none version-controlled per Phase 8) are
distinct from the pre-existing substrate schema implemented in Phase 6 Sprint 6.27.

### Deliverables

- `DEVELOPMENT_PLAN/development_plan_standards.md` gains Sections T (No Environment Variables, No
  PATH) and U (Host Tools Manifest). Both name the three Dhall files (`InfernixHost`,
  `InfernixCluster`, `InfernixSecrets`), the secret-file convention, the bootstrap stage-zero
  discovery convention (`BASH_SOURCE`, `/etc/passwd`, hardcoded pre-binary paths), and the
  third-party-upstream exception list (Keycloak `KC_DB_*`).
- `documents/architecture/configuration_doctrine.md` is the canonical home declaring the doctrine.
- `documents/engineering/host_tools_manifest.md` defines the `InfernixHost.dhall` schema and the
  per-tool absolute-path table.
- `documents/engineering/cluster_config_manifest.md` defines the `InfernixCluster.dhall` schema
  and the ConfigMap+Secret mount contract.
- `documents/development/no_env_vars.md` defines the developer-facing rules (no `lookupEnv`,
  no `proc "<bare-name>"`, no `process.env`, no `os.environ`, no `env:` blocks in
  infernix-owned chart templates).
- `documents/documentation_standards.md` adds a content rule rejecting `$INFERNIX_*` / `$PATH`
  mentions in governed docs outside the prior-tracking ledger and the documented Keycloak
  third-party exception.
- `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` records the cleanup rows for the seven
  per-phase cleanup sprints, naming the specific env vars / PATH-resolved commands /
  chart-template `env:` blocks each sprint owns.
- `DEVELOPMENT_PLAN/README.md` Phase Overview table reflects the closed phase state.
- `README.md`, `AGENTS.md`, `CLAUDE.md` link to
  `documents/architecture/configuration_doctrine.md` and
  `documents/development/no_env_vars.md` as canonical homes; the no-env-var + absolute-path
  rules are surfaced in the assistant non-negotiable rules section.

### Validation

- `infernix lint docs` exits zero against the new + updated docs.
- `infernix lint files` and the existing repo-wide checks remain clean (this sprint is purely
  declarative — no code changes).
- The seven cleanup rows in `legacy-tracking-for-deletion.md` each name a specific later
  sprint as the owning sprint (1.11, 2.13, 3.10, 4.13, 5.9, 6.28, 7.17).
- the seven cleanup sprints are implemented; the Apple cohort closed under

### Remaining Work

None.

---

## Sprint 0.10: Declarative-State Documentation Reconciliation [Done]

**Status**: Done
**Implementation**: `README.md`, `documents/**/*.md`, `DEVELOPMENT_PLAN/**/*.md` (prose only)
**Docs to update**: `README.md`, every file in `documents/` carrying sprint-history attributions, dated validation evidence, or prior-entity name references in body prose, plus `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, the per-phase Phase 4/5/6/7 editorial sprints (4.14, 5.10, 6.29, 7.18), and `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make every prose surface in `README.md`, `documents/`, and `DEVELOPMENT_PLAN/` present-tense and
declarative against the supported shape defined by the canonical architecture documents, and
seed `legacy-tracking-for-deletion.md` with any still-extant obsolete surfaces surfaced during
the pass. The supported shape is anchored on
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
(daemon vocabulary: `Coordinator` / `Engine` / `Frontend`; deployments: `infernix-coordinator` /
`infernix-engine` / `infernix-demo`),
[../documents/architecture/runtime_modes.md](../documents/architecture/runtime_modes.md)
(substrates: `apple-silicon`, `linux-cpu`, `linux-gpu`),
[../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)
(three typed Dhall files, no env vars), and
[../documents/engineering/object_storage.md](../documents/engineering/object_storage.md)
(MinIO buckets `infernix-models`, `infernix-engine-artifacts`, and `infernix-demo-objects`).

### Deliverables

- `README.md` prose drops the "updated under Phase 7 Sprint 7.7" parenthetical at lines 190–203
  and any `still`/`today`/`currently` hedges in the architectural prose blocks, and uses the
  canonical three-role daemon vocabulary directly.
- Every `documents/` file carrying sprint-history attributions (e.g. "Sprint 7.7 implemented",
  "Phase 6 Sprint 6.28 added"), dated validation evidence (e.g. "the recorded cohort validation Linux GPU run"), or
  prior-entity names used as current (`infernix-service`, `ClusterDaemon`/`HostDaemon`,
  `./.data/object-store/`, `infernix-runtime`/`infernix-results` buckets, `/objects/:objectRef`,
  `objectStoreRoot`) is rewritten in present-tense declarative voice.
- `DEVELOPMENT_PLAN/system-components.md` removes the "current; prior by Phase 7 Sprint 7.7"
  rows at lines 196, 241, 242, 247 and rewrites the daemon-cell paragraph at line 154 in
  present-tense voice using the canonical three-role vocabulary.
- The per-phase editorial sprints (Phase 4 Sprint 4.14, Phase 5 Sprint 5.10, Phase 6 Sprint 6.29,
  Phase 7 Sprint 7.18) land their scoped rewrites so phase-internal prose carries no cross-phase
  retirement narrative.
- `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` gains a Pending Removal row for any
  still-extant obsolete surface surfaced during the pass that is not already in the ledger.
- `DEVELOPMENT_PLAN/README.md` Phase Overview row recorded this sprint's Phase 0 scope as `Done`;
  later governance changes may reopen the phase with a new numbered sprint.

### Validation

- `infernix lint docs` exits zero against the rewritten prose surfaces.
- The README/doc lexical guard for unsupported historical-state and time-relative terms returns
  zero matches.
- Sprint 0.10 editorial-pass gates (one-time, not enduring lint checks): at the 0.10 close,
  `grep -rEn "Sprint [0-9]+\.[0-9]+|[A-Z][a-z]+ [0-9]+, 202[0-9]|202[0-9]-[0-9]{2}-[0-9]{2}" README.md documents/`
  and
  `grep -rEn "infernix-service|ClusterDaemon|HostDaemon|\./.data/object-store|infernix-runtime|infernix-results|/objects/:objectRef|objectStoreRoot" README.md documents/`
  returned zero body-prose matches. They were a one-time editorial sweep, not enduring gates:
  reopened phases (4/6/7/9) and the validation-status matrix have since intentionally added factual
  dated **Wave/Sprint evidence citations** to `README.md` status prose and some governed docs'
  `## Current Status` sections, so the raw greps no longer return zero. The enduring
  machine-enforced guard is the lint lexical check above (`infernix lint docs`), which still forbids
  unsupported historical-state and time-relative *narrative* terms.
- The development-plan lexical guard for unsupported historical-state terms returns matches only
  inside `legacy-tracking-for-deletion.md`.
- Read-through of `phase-0` → `phase-7` end-to-end: a fresh reader can follow the development
  narrative without encountering language that retires, renames, or supersedes anything inside
  `DEVELOPMENT_PLAN/` proper.

### Remaining Work

None.

---

## Sprint 0.11: Realness Doctrine and Matrix Reconciliation [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/development/python_policy.md`, `documents/architecture/realness_contract.md`, `src/Infernix/Lint/Docs.hs`, `src/Infernix/Models.hs`
**Docs to update**: as above

### Objective

Make the governed docs state the realness invariant and the new model bindings, mechanically consistent
with the generated catalog and lint.

### Deliverables

- README matrix + Coverage Closure Rules updated in lockstep with `Models.hs` + `model_catalog.md`
- `model_catalog.md` / `testing_strategy.md` / `python_policy.md` rewritten to realness; new realness
  doctrine home; forbidden-phrase additions + purge
- `README.md` / `AGENTS.md` / `CLAUDE.md` reviewed together

### Validation

- `infernix lint docs` + `infernix docs check` pass (metadata, links, README route block,
  matrix↔catalog parity, forbidden phrases purged)
- the matrix↔catalog lockstep (`Models.hs` + README + `model_catalog.md`), the

### Remaining Work

None.

---

## Sprint 0.12: Realness Lint Enforcement Infrastructure [Done]

**Status**: Done
**Implementation**: `python/adapters/common.py`, `src/Infernix/Lint/HaskellStyle.hs`
**Docs to update**: `documents/architecture/realness_contract.md`, `documents/development/python_policy.md`

### Objective

Give the realness invariant a machine-independent enforcement mechanism so neither accelerator phase has
to own — or wait on — the lint, and any reintroduced fabrication fails the quality gate.

### Deliverables

- the Python `check-code` AST realness guard and the Haskell `realnessFabricationViolations` lint, both
  machine-independent, with a per-runner `realnessScopedFiles` extended by the accelerator phases

### Validation

- `infernix test lint` + `poetry run check-code` pass and fail on any reintroduced fabrication token

### Remaining Work

None.

---

## Sprint 0.13: Managed-State-Transition Doctrine and Escape-Token Lint [Done]

**Status**: Done — implemented and validated.
**Implementation**: `documents/architecture/managed_state_transitions.md`,
`src/Infernix/Lint/Docs.hs`, `src/Infernix/Lint/HaskellStyle.hs`
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase — author the
`managed_state_transitions.md` doctrine doc, register it (`requiredDocs` in
`src/Infernix/Lint/Docs.hs` plus `documents/README.md`), and add an `unsafeCoerce` /
`unsafePerformIO` escape-token check to `src/Infernix/Lint/HaskellStyle.hs` (the two escapes the
type system cannot close) — encoding evidence, not hope. For every system state S there is a
transition T and typed evidence E(S); every operation acting on S requires E(S). The doctrine
generalizes the results-side realness contract to state transitions and is canonical at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `documents/architecture/managed_state_transitions.md` authored as the canonical doctrine home,
  declaring typed evidence `E(S)` for every state `S`, unexported raw destructive/commit/spawn
  primitives, evidence-returning readiness waits, and the typed `ClusterLifecycle` machine plus
  fail-closed versioned persistence that replace `clusterPresent::Bool` + `lifecyclePhase::String`
  + `Show`/`Read`
- the doctrine doc registered as a required doc in `requiredDocs` (`src/Infernix/Lint/Docs.hs`) and
  indexed in `documents/README.md`
- an `unsafeCoerce` / `unsafePerformIO` escape-token check added to
  `src/Infernix/Lint/HaskellStyle.hs`, covering the two escapes the type system cannot close

### Validation

- on the apple-silicon lane: `cabal build all` (`-Wall -Werror`),
  `cabal test infernix-unit`, and `cabal test infernix-haskell-style` all pass. The new
  `escapeTokenViolations` check in `src/Infernix/Lint/HaskellStyle.hs` is clean on the tree and was
  verified to fail with the doctrine diagnostic on a reintroduced `unsafeCoerce` / `unsafePerformIO`
  token injected into an evidence-kernel module (reverted after the negative-test confirmation)
- `infernix lint docs` and `infernix docs check` pass, confirming the doctrine doc's metadata,
  links, and `requiredDocs` registration; the escape-token lint is the code delta that lands this
  sprint
- `poetry run check-code` is not applicable — no native/Python surface changed
- the linux-cpu lane rerun of the code-side gates closed on the selected accelerator plus `linux-cpu`

### Remaining Work

None.

---

## Sprint 0.14: Bounded-Command/Bounded-HTTP Doctrine Documentation [Done]

**Status**: Done — implemented and validated.
**Implementation**: `documents/architecture/managed_state_transitions.md`, `README.md`,
`AGENTS.md`, `CLAUDE.md`, `documents/development/assistant_workflow.md`,
`documents/tools/registry.md`, `documents/engineering/model_lifecycle.md`,
`documents/engineering/object_storage.md`, `documents/development/no_env_vars.md`,
`documents/development/haskell_style.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Blocked by**: nothing — Sprint 0.13 is closed.
**Docs to update**: `documents/architecture/managed_state_transitions.md`, the three-way non-negotiable mirror
(`README.md` / `AGENTS.md` / `CLAUDE.md` plus `documents/development/assistant_workflow.md`), and
the phase's existing engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — record the
governance surface of the follow-on that applies the Sprint 1.16/3.14/4.28 managed-state kernels at
the two flake sites a single-accelerator cohort run surfaced (the registry `docker pull` verify hang
and the rate-limited upstream model download). Governance is current-state and honest: the doctrine
doc, the non-negotiable mirror, and the deletion ledger record what the code does now
(bounded publish exec,
`BlobServable` evidence, the classified download outcome, the integrity-witnessed sentinel, and the
two new capability-gating lints), while the deferred readiness-wait migration and ProcessMonitor
retirement (Sprint 6.41) are tracked as remaining, not claimed done. The doctrine is canonical at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `documents/architecture/managed_state_transitions.md` extended: the bounded-HTTP download-outcome
  kernel added to `## The law` beside the `SubprocessEnv` / `CommandOutcome` bullet, `BlobServable`
  added to the readiness-returns-evidence paragraph, the two new lints (`unboundedExecViolations`,
  `unboundedHttpViolations`) reflected in the TL;DR and `## Enforcement`, and the sprint-to-phase
  mapping in `## Current Status`
- the three-way non-negotiable mirror updated: the `evidence-gated state transitions` bullet extended
  with the raw-unbounded-spawn / `runBoundedCommand` clause (enforced by `unboundedExecViolations`)
  and a new peer hard-stop for raw unbounded upstream-model-download HTTP (enforced by
  `unboundedHttpViolations`) in `documents/development/assistant_workflow.md` (canonical) mirrored
  byte-identically into `AGENTS.md` and `CLAUDE.md`, with `README.md` carrying the prose form
- the current-state operator-doc touch-ups (`documents/tools/registry.md`,
  `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`,
  `documents/development/no_env_vars.md`, `documents/development/haskell_style.md`) and the
  `legacy-tracking-for-deletion.md` ledger rows

### Validation

- `infernix lint docs` and `infernix docs check` pass, confirming metadata, the broad-doctrine-doc
  structure for `managed_state_transitions.md`, root-doc metadata, link resolution, and the
  monitoring-stance alignment (monitoring is unsupported, so the "no monitoring doc" stance holds)
- the `AGENTS.md` / `CLAUDE.md` non-negotiable blocks stay byte-identical to each other and a faithful
  subset of `assistant_workflow.md`

### Remaining Work

None.

---

## Sprint 0.15: Bounded-Inference-Memory Doctrine and Non-Negotiable Mirror [Done]

**Status**: Done — the `bounded_inference_memory.md` memory-safety-by-construction doctrine doc,
its docs-lint registration, and the three-way non-negotiable mirror are doc-only and
machine-independent; closed on `infernix lint docs` + `infernix docs check` + `cabal build all` on
the apple-silicon lane. A later audit superseded that first unindexed admission API: the governed
doctrine and mirrors describe Phase 1's indexed compile/refine/executable boundary, and the
enforcement work that follows from it belongs to Phase 4 Sprint 4.32 and Phase 6 Sprint 6.44.
**Implementation**: `documents/architecture/bounded_inference_memory.md`,
`src/Infernix/Lint/Docs.hs`, `README.md`, `AGENTS.md`, `CLAUDE.md`,
`documents/development/assistant_workflow.md`
**Docs to update**: `documents/architecture/bounded_inference_memory.md`, the three-way non-negotiable mirror
(`README.md` / `AGENTS.md` / `CLAUDE.md` plus `documents/development/assistant_workflow.md`), and
`documents/README.md`

### Objective

This sprint originally recorded the governance surface of the memory-safety-by-construction
doctrine — author the
`bounded_inference_memory.md` doctrine doc, register it (`requiredDocs` plus a `DocumentStructureRule`
in `src/Infernix/Lint/Docs.hs`, and `documents/README.md`), and add the new non-negotiable rule to the
three-way `README.md` / `AGENTS.md` / `CLAUDE.md` mirror plus `assistant_workflow.md` — encoding
evidence, not hope. An inference engine subprocess runs only under a typed `MemoryGrant` minted by
`admitModelMemory`, the capped-engine kernel measures its resident memory against the admitted
`MemoryCeiling` and terminates on breach, and an over-budget model is a clean `status=failed`
`ModelMemoryLimitExceeded` rather than an unmanaged resource transition. That scope is one claimant
on host memory; the ledger and the host toolchain account are owned by Sprint 0.19.
Governance is honest current-state: the doc and mirror record the target while naming the enforcing code
as `Planned` Phase 4/6 work. The doctrine is canonical at
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md).

### Deliverables

- `documents/architecture/bounded_inference_memory.md` authored as the canonical doctrine home,
  declaring the typed `MemoryGrant` minted by `admitModelMemory`, the capped-engine kernel bounding
  resident memory to the admitted `MemoryCeiling`, the required `ModelMemoryFootprint` newtype (no
  bare-`Int` default-0), the budget that names its enforcer
  (`HostEnforcedBudget HostMemoryPartition | SubstrateEnforcedBudget PodMemoryLimit`, dropping
  `UnenforcedMemoryBudget`), the checked `HostMemoryPartition` (physical = vmReserve + hostHeadroom +
  inferenceCapacity, rejecting oversubscription; headroom covering OS + routed-E2E browser), the
  historical macOS `proc_pid_rusage` physical-footprint watchdog + process-group SIGKILL and the
  Linux pod-cgroup/VRAM-OOM exit classifier, and the `unboundedEngineSpawnViolations` lint. The
  direct-FFI sampler and its Apple-specific evidence are superseded by the fixed bounded
  `/usr/bin/top` plus `/usr/bin/footprint` observer that replaced them
- the doctrine doc registered as a required doc in `requiredDocs` with a `DocumentStructureRule`
  (`src/Infernix/Lint/Docs.hs`) and indexed in `documents/README.md`
- the new non-negotiable rule added to `documents/development/assistant_workflow.md` (canonical),
  mirrored byte-identically into `AGENTS.md` and `CLAUDE.md`, with `README.md` carrying the prose form

### Validation

- `infernix lint docs` and `infernix docs check` pass, confirming the doctrine doc's metadata, links,
  broad-doctrine-doc structure, and `requiredDocs` / `DocumentStructureRule` registration
- the `AGENTS.md` / `CLAUDE.md` non-negotiable blocks stay byte-identical to each other and a faithful
  subset of `assistant_workflow.md`
- `cabal build all` (`-Wall -Werror`) is unaffected by the Markdown-only change; `poetry run check-code`
  is not applicable — no native/Python surface changed

The enforcing code — the `MemoryGrant`-gated capped-engine kernel, the checked
`HostMemoryPartition`, the required `ModelMemoryFootprint`, the budget-enforcer split, and the
`unboundedEngineSpawnViolations` lint — belongs to Phase 4 Sprints 4.30/4.31 and Phase 6 Sprint
6.42, whose behavioral sign-off closed on the selected accelerator plus `linux-cpu`.

### Remaining Work

None.

---

## Sprint 0.16: Cluster-Ownership Doctrine and Non-Negotiable Mirror [Done]

**Status**: Done — the Cluster-Ownership & Mutation-Position doctrine (extending the existing
`managed_state_transitions.md`), the three-way non-negotiable mirror, the new
`documentation_standards.md` Update Rule, and the operator / test-harness / persistence doc
reconciliation are doc-only and machine-independent; closed on `infernix lint docs` +
`infernix docs check` + `cabal build all` on the apple-silicon lane. The enforcing code in Phase 2
Sprint 2.15 and Phase 6 Sprint 6.43 is closed on the selected accelerator plus `linux-cpu`; the later
owner-atomic reservation/teardown correction is outside that scope and is tracked with the phases
that own it.
**Implementation**: `documents/architecture/managed_state_transitions.md`, `README.md`, `AGENTS.md`,
`CLAUDE.md`, `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`
**Docs to update**: `documents/architecture/managed_state_transitions.md`, the three-way non-negotiable
mirror (`AGENTS.md` / `CLAUDE.md` plus `documents/development/assistant_workflow.md`),
`documents/documentation_standards.md`, and the operator / test-harness / persistence docs
(`documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`,
`documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`,
`documents/development/testing_strategy.md`, `documents/architecture/configuration_doctrine.md`,
`documents/development/local_dev.md`, `documents/engineering/testing.md`,
`documents/development/chaos_testing.md`, `documents/engineering/storage_and_state.md`)

### Objective

This sprint records the governance surface of the Cluster-Ownership & Mutation-Position doctrine — extend
the canonical `managed_state_transitions.md` with the ownership + mutation-position law, add the new
non-negotiable rule to the three-way `README.md` / `AGENTS.md` / `CLAUDE.md` mirror plus
`assistant_workflow.md`, add the missing cluster-lifecycle Update Rule to `documentation_standards.md`,
and reconcile the operator / test-harness / persistence docs — encoding evidence, not hope. The persisted
cluster names its `ClusterOwner`, `clusterDown` consumes that evidence (so tearing down an `OperatorOwned`
cluster does not typecheck), and a first-class `ClusterMutating` position makes a killed test's dirty
cluster detectable + reconcilable rather than a false `steady-state`. Governance is honest current-state:
the docs record the target while naming the enforcing code as `Planned` Phase 2/6 work. The doctrine is
canonical at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `managed_state_transitions.md` extended: the `ClusterOwner` evidence-gated `clusterDown` in the "not
  exported" primitives list, the `ClusterMutating` position + reconcile-on-next-`cluster up` on the
  `ClusterLifecycle` law, and a third follow-on-reopen paragraph in "Current Status"
- the new non-negotiable rule added to `documents/development/assistant_workflow.md` (canonical), mirrored
  byte-identically into `AGENTS.md` and `CLAUDE.md`
- the cluster-lifecycle / ownership / `cluster status` Update Rule added to
  `documents/documentation_standards.md`
- the operator status surface (`cli_reference.md` § Lifecycle Progress Surface, `cli_surface.md`, the two
  runbooks), the test-harness lifecycle (`testing_strategy.md`, `configuration_doctrine.md`,
  `local_dev.md`), failure classification (`engineering/testing.md`), the chaos case (`chaos_testing.md`),
  and persistence (`storage_and_state.md`) reconciled to the doctrine

### Validation

- `infernix lint docs` and `infernix docs check` pass, confirming the extended doctrine doc's links and
  structure and that all cross-references resolve
- the `AGENTS.md` / `CLAUDE.md` non-negotiable blocks stay byte-identical to each other and a faithful
  subset of `assistant_workflow.md`
- `cabal build all` (`-Wall -Werror`) is unaffected by the Markdown-only change; `poetry run check-code`
  is not applicable — no native/Python surface changed

### Remaining Work

None.

---

## Sprint 0.17: Typed Execution Plan Doctrine [Done]

**Status**: Done
**Implementation**: `documents/architecture/typed_execution_plan.md`, governed doctrine and plan documents
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/`, `DEVELOPMENT_PLAN/`

### Objective

Replace overclaimed descriptive-limit and bounded-process language with one canonical target:
generated Dhall is a closed execution plan, Haskell compiles and runtime-refines it into opaque
capabilities, and routing or process launch cannot consume raw configuration.

### Deliverables

- canonical `typed_execution_plan.md` with explicit current status and validation contract
- affected architecture, workflow, runbook, root, plan-index, component-inventory, and phase docs
  distinguish current defenses from the reopened construction
- forward-only Phase 1/2/4/6/8 reopens and deletion-ledger rows

### Validation

- `infernix lint docs` and `infernix docs check`
- phase maintenance scans report zero backward dependency edges and zero dual-accelerator gates
- `AGENTS.md` and `CLAUDE.md` keep identical non-negotiable mirrors
- the doctrine is registered in `requiredDocs` with its required structure, and the gates run in
  the supported `linux-cpu` container context. No enforcing code belongs to this sprint

### Remaining Work

None.

---

## Sprint 0.18: No-Repo-Owned Native Source Doctrine [Done]

**Status**: Done — the rule, the file-lint implementation, the affected doctrine/workflow/plan
truth, the all-Haskell correction, the focused adversarial proof, the final review, and the
complete source-matched machine-independent correction gate all passed. No pre-correction review,
Stage 1, or cohort result was reused.
**Implementation**: governed documentation, root workflow mirrors, native-source lint policy, and
the Phase 2 evidence reset
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`,
`documents/development/assistant_workflow.md`, `documents/development/haskell_style.md`,
`documents/architecture/managed_state_transitions.md`, and `DEVELOPMENT_PLAN/`

### Objective

Forbid repository-owned native implementation source and record the all-Haskell lifecycle-lock and
bounded-subprocess boundary without weakening the existing evidence-gated lifecycle, closed command
language, deadline, provenance, output-bound, or cleanup contracts.

### Deliverables

- the no-repo-owned-native-source rule mirrored through the governed workflow/root documents
- `infernix lint files` rejection of C/C++/Objective-C, CUDA, assembly, Metal, Swift, C2HS/HSC/C-- source
  extensions and Cabal `c-sources:`, `cxx-sources:`, `asm-sources:`, and `cmm-sources:`
  declarations; Cabal native-token CPP definitions; and embedded native source, writers, or
  compiler invocations in another implementation language, with unit and negative coverage
- Phase 2 status that treats every pre-correction source/binary digest, review, Stage 1,
  and cohort assertion as superseded and nonreusable for the correction
- deletion-ledger records for the removed lifecycle and subprocess C/FFI/Cabal boundaries, kept
  separate from the focused runtime and aggregate validation evidence that closed the correction

### Validation

- `infernix lint docs`, `infernix docs check`, and `infernix lint files`
- root/workflow mirror checks
- the complete source-matched machine-independent correction gate after the all-Haskell
  implementation and focused adversarial suites pass

The correction gate is complete rather than partial: the focused lifecycle-lock and
bounded-subprocess adversarial suites, `cabal test infernix-unit`, `cabal build all` with the
integration compile preflight, `cabal test infernix-execution-plan-internal`,
`cabal test infernix-compile-fail`, `cabal test infernix-capped-engine-observer`,
`cabal test infernix-haskell-style`, the install to `./.build`, the installed binary's `lint files`
/ `lint docs` / `lint chart` / `lint proto` / `docs check`, Python
`poetry --directory python run check-code`, the canonical web contract/build/unit gates, and
`git diff --check` all pass on one worktree identity whose digest is unchanged before and after the
gates. The final adversarial reviews found no High or Medium finding.

### Remaining Work

None.

---

## Sprint 0.19: Bounded Host Memory Doctrine [Done]

**Status**: Done — the capacity-ledger doctrine, its lint registration, the governed-suite scope
corrections, and the three-way non-negotiable mirror are landed, and the serialization claim they
originally carried is replaced by the one-pool/two-alternative-occupants ledger, the admission
clause, and the account's declared scope. Machine-independent (Axis-1 only); no accelerator gate.
**Implementation**: `documents/architecture/bounded_host_memory.md`, `src/Infernix/Lint/Docs.hs`,
`documents/README.md`, `documents/documentation_standards.md`, the root-document mirror
**Docs to update**: `documents/architecture/bounded_host_memory.md`,
`documents/architecture/bounded_inference_memory.md`,
`documents/architecture/managed_state_transitions.md`,
`documents/architecture/realness_contract.md`, `documents/architecture/runtime_modes.md`,
`documents/development/assistant_workflow.md`, `documents/development/local_dev.md`,
`documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`,
`documents/operations/apple_silicon_runbook.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Establish the host-memory capacity ledger as a governed doctrine, and make the suite's memory
language honest.

Infernix partitions physical host RAM and names exactly one claimant: a single serialized
inference. The claimable pool's co-tenant-headroom projection enumerates who `headroom` covers — the OS, the
control-plane binary, the routed end-to-end browser, worst-case watchdog overshoot — and the
Haskell toolchain is not among them. A ledger with one row cannot overflow on a claimant it does
not model, which is why the process that exhausted the host was never in breach of anything.

Two governance obligations follow. First, a canonical home for the ledger, the declared-ceiling
invariant, and the per-lane enforcement mechanism, stated so that the concurrency multiplier is
inseparable from the ceiling: a per-process cap under `jobs: $ncpus` bounds the host at
`jobs × cap`. Second, a scope statement strong enough that no document in the suite again claims a
host out-of-memory kill is impossible — the enforcement it would rest on is a fixed-cadence sampler
for inference, and for everything the repository does not start there is no enforcement at all.

### Deliverables

- `documents/architecture/bounded_host_memory.md` authored as the canonical home: the ledger and
  its claimants, the three-clause invariant, the per-lane enforcement table, a `Bounded build
  memory` subsection modelled on the bounded-descriptor-space section of
  [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md),
  the named residual review-obligations, and a `What this does not bound` section that is the
  suite's only home for that statement
- the doc registered in `requiredDocs` and given a `DocumentStructureRule` in
  `src/Infernix/Lint/Docs.hs`, indexed in `documents/README.md`, and added to the update-rule set in
  `documents/documentation_standards.md`
- the self-contradiction in `bounded_inference_memory.md` resolved by scoping that document to the
  inference row and moving the global statement to the parent doctrine
- every "OS-enforced" / "by construction" claim about *runtime* memory enforcement restated as what
  it is — measurement and termination on a fixed cadence — across `managed_state_transitions.md`,
  `runtime_modes.md`, `realness_contract.md`, and `apple_silicon_runbook.md`
- a glossary note recording that "bounded" elsewhere in this suite means time, captured output, and
  descriptor space, never memory
- the new non-negotiable rule mirrored byte-identically into `AGENTS.md` and `CLAUDE.md` with the
  canonical form in `documents/development/assistant_workflow.md`, and the existing host-`cabal`
  rule extended with the ceiling clause
- the `Infernix.DescriptorSpace` passage restored to the canonical
  `assistant_workflow.md` list, which the two mirrors carried but their source did not
- the ledger opening on one claimable pool with two alternative occupants: the toolchain account is
  a share of the same non-virtual-machine pool the inference partition divides, an exclusive host
  claim admits one occupant at a time, and a plan that sums both against that pool is a ledger error
- admission stated as doctrine rather than operator instruction: clause 4 of the invariant and the
  `Admission` row of the enforcement table require an observation of available host memory
  sufficient to fund the account plus a census finding no toolchain claimant outside the authority's
  own process tree, with either failure a refusal that names what it found
- the account scoped to the governed Cabal invocation, with the web dependency install and unit run,
  the routed end-to-end browser, the Python provisioning and adapter images, and the host inference
  daemon named as host-reserve claimants carrying no toolchain ceiling
- the Apple row of the enforcement table reading `none`: Darwin supplies no cgroup and no
  installable address-space ceiling, so no operating-system bound is engaged on that lane at all

### Validation

- `infernix lint docs` passes with the new document registered, structured, and cross-linked, and
  `cabal build all` under `-Wall -Werror` accepts the `Lint/Docs.hs` registration
- `diff CLAUDE.md AGENTS.md` differs only at the title, `Supersedes`, `Purpose`, and intro lines, so
  the mirror remains byte-identical from the non-negotiable rules onward
- the governed suite contains no remaining claim that a host out-of-memory kill is structurally
  unrepresentable; the surviving honest statements in `typed_execution_plan.md` and `README.md` are
  preserved rather than rewritten

The doctrine this sprint establishes is implemented by Phase 1 Sprint 1.21 (the build-memory
kernel, the bounded runtime reservation, and the generated ceiling) and Phase 6 Sprint 6.46 (the
toolchain spawn boundary, its lint, and the per-lane mechanism resolver). The deferred ledger rows
— the partition's missing build term, the unchecked sum of cluster pod limits against node
allocatable, and the uncapped nested builds — are named in the doctrine's scope statement so they
are not mistaken for closed.

### Remaining Work

None.

---

## Sprint 0.20: Per-Machine Fleet Doctrine [Done]

**Status**: Done — the fleet doctrine, the delivery-semantics contract, the config-split doctrine,
the standards corrections, the phase renames, and the two docs-lint hardening fixes are landed.
Machine-independent (Axis-1 only); no accelerator gate.
**Implementation**: `documents/architecture/daemon_topology.md`,
`documents/architecture/configuration_doctrine.md`,
`documents/architecture/bounded_inference_memory.md`,
`documents/architecture/engine_pool_routing.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`,
`src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/architecture/daemon_topology.md`,
`documents/architecture/configuration_doctrine.md`,
`documents/architecture/bounded_inference_memory.md`,
`documents/architecture/engine_pool_routing.md`, `documents/README.md`,
`documents/documentation_standards.md`, `documents/tools/pulsar.md`, `README.md`, `AGENTS.md`,
`CLAUDE.md`

### Objective

Record the supported architecture as a fleet: multiple machines, each running exactly one engine
process, all consuming the same `Shared` pool topic, each with its own model cache and its own
machine contract naming the pools it serves.

Three doctrine statements follow, and none of them existed in prose before.

**Delivery semantics.** The system is at-least-once with an effectively-once observable outcome, and
that was implied by two sentences about acknowledgement ordering rather than stated. Naming it
matters because every recovery property in the failure table depends on it: redelivery is the only
recovery path the pipeline has, since request publishes carry a deduplicating sequence id that makes
re-dispatch a no-op by design. At-most-once was considered and rejected — prompt resolution requires
a terminal event and there is neither a client deadline nor a server reaper, so a discarded request
is an unresolved prompt with no visible error.

**One engine per machine.** This is a correctness rule, not a scheduling preference. Two engines on
one box hold two KV caches and two copies of every loaded weight, and each independently admits work
against the machine's whole observed capacity — so both can pass admission for work that together
exceeds the box. Member identity therefore fails closed: a daemon that cannot establish which member
it is refuses to start rather than adopting a default.

**The config splits by scope, not by size.** Facts two machines must agree on live in the system
contract and nowhere else; facts true of one box live in its machine contract. The split is not a
reorganization — it removes the shared facts from the per-machine files so there is nothing to
reconcile, which is the same move Sprint 8.9 made when it gave each union arm only its own payload.

### Deliverables

- `daemon_topology.md` gains `## Fleet Topology and Member Identity` (replacing the retired HA and
  node-policy contract) and `## Delivery Semantics`, and becomes the canonical home for both
- `configuration_doctrine.md` gains the system/machine contract split and the content-pin
  relationship, with the explicit statement that both files remain binary-generated and untracked so
  the zero-version-controlled-`.dhall` rule is unaffected
- `bounded_inference_memory.md` states that admission happens on the executing machine and that
  capacity is observed rather than declared, and records the asymmetry in one line: the model's
  footprint is a system fact and stays on the wire; the machine's capacity is a local observation
  and does not
- `engine_pool_routing.md` records that a pool is selected by field access rather than spelled as
  text, and states plainly that "every routable model has an eligible member" is **not** checkable
  from the system contract alone — it is the union of what every machine declares
- `development_plan_standards.md` corrections: the replica/anti-affinity/PDB mandate (§L), the
  HA-only-target rule (§O), the exactly-once claim on model staging (§K), the Patroni HA mandate
  (§N), and the single-operator-config framing (§M)
- both HA-named phase documents renamed, with §E's filename inventory, `phaseDocs`, and
  `monitoringStancePaths` updated together
- two docs-lint hardening fixes that make that rename mechanically safe rather than silently green

### Validation

- `infernix lint docs` and `infernix docs check` pass; `cabal build all` under `-Wall -Werror`
  accepts the `Lint/Docs.hs` changes
- the `monitoringStancePaths` read is existence-guarded, so a stale entry is a named refusal rather
  than an uncaught `openFile: does not exist`. **Verified to fail** with the named diagnostic on a
  reverted entry, and reverted after the negative-test confirmation
- `validateRelativeLinks` now covers the six non-phase plan documents whose links were previously
  unchecked, so a phase rename that misses one is a clean lint failure instead of a green ship
- `diff CLAUDE.md AGENTS.md` differs only at the title, `Supersedes`, `Purpose`, and intro lines

The implementation this doctrine governs belongs to Sprint 4.34 (admission on the executing
machine, fail-closed identity), Sprint 3.16 (the topology collapse), Sprint 6.47 (the validation
surface), and Sprints 8.10/8.11 (the wire).

### Remaining Work

None.

---

## Sprint 0.21: Name The Co-Resident VM In The Host Memory Doctrine [Done]

**Status**: Done — the co-resident pledge is named and subtracted, and the same argument now runs
one level up: the toolchain account and the inference partition draw on the one non-virtual-machine
pool, and the doctrine records the supported-host arithmetic that leaves that pool with no residue.
**Implementation**: `documents/architecture/bounded_host_memory.md`
**Docs to update**: `documents/architecture/bounded_host_memory.md`

### Objective

[bounded_host_memory.md](../documents/architecture/bounded_host_memory.md) partitions physical RAM
into declared accounts and is careful to enumerate what it does **not** bound — page cache, kernel
slab, the OOM-protected container runtime, and every process infernix did not start. That list omits
a claimant that measurably exists on the supported Apple host and that both supported lanes run
inside: **a co-resident VM pledge**.

This is a doctrine defect, not an implementation gap, which is why it reopens Phase 0 rather than
sitting only in Phase 1. The document's own governing sentence — a ceiling is inseparable from the
concurrency it is multiplied by — is being applied against physical memory when the memory actually
available to the toolchain is physical minus whatever the VM has pledged.

On the supported development host this is measurable rather than theoretical: physical
**65536 MiB**, a generated `cabal.project.local` granting `jobs: 8` x `-M4096M` = **32768 MiB**, and
a running Colima default profile pledging **48 GiB**. The `linux-cpu` lane executes *inside* that
VM, so the two lanes are not independent claimants on one host — they are nested.

### Deliverables

- The doctrine names a co-resident VM pledge as a claimant and records the historical defect: the
  Darwin toolchain account did not subtract it, oversubscribing the measured host.
- The current implementation uses one fixed-path, deadline-bounded Colima producer/parser for both
  accounts. Toolchain effective memory subtracts the conservatively observed active pledge; an
  unavailable, failed, malformed, or exhausting observation fails closed rather than becoming zero.
- The pledge argument is carried up one level: the toolchain account and the inference partition are
  shares of the same non-virtual-machine pool, so summing them against that pool is a ledger error
  rather than two independent declarations, and the exclusive host claim is what keeps them apart.
- The doctrine records the arithmetic on the supported development host — a `16384 MiB` pool outside
  the pledge, spent in full by `6144 MiB` of held-back headroom plus `10240 MiB` of inference
  capacity, leaving no residue the `8192 MiB` toolchain account could be drawn from.

### Validation

`infernix lint docs` passes with the metadata block intact. This sprint owns the doctrine; the
measurement correction it calls for is implemented under Phase 1 Sprint 1.21, and no cohort gate
applies to a doc-only sprint.

### Remaining Work

None.

---

## Sprint 0.22: Complete Fleet Doctrine Reconciliation and Enforce Status-Free Governed Docs [Done]

**Status**: Done — the governed Apple build, the aggregate lint, the full unit suite, the
standalone docs lint, `docs check`, and the repo-wide diff check all pass on the closing source
identity. Machine-independent (Axis-1 only); no accelerator gate.
**Implementation**: Settled across the governed prose inventory,
`documents/development/assistant_workflow.md`, `src/Infernix/Lint/Docs.hs`, focused semantic fixtures
in `test/haskell-style/Spec.hs`, and the corrected plan standard.
**Docs to update**: Sprint 0.22 inventory — `README.md`,
`documents/development/assistant_workflow.md`,
`documents/architecture/daemon_topology.md`,
`documents/architecture/demo_app_design.md`, `documents/architecture/durable_context_design.md`,
`documents/architecture/web_ui_architecture.md`,
`documents/architecture/object_access_doctrine.md`,
`documents/architecture/pulsar_ml_workflow.md`,
`documents/architecture/bounded_inference_memory.md`,
`documents/architecture/bounded_host_memory.md`,
`documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`,
`documents/architecture/typed_execution_plan.md`, `documents/engineering/k8s_storage.md`,
`documents/engineering/object_storage.md`, `documents/engineering/testing.md`,
`documents/tools/pulsar.md`, `documents/tools/postgresql.md`,
`documents/development/testing_strategy.md`, `documents/development/demo_app_test_plan.md`,
`documents/operations/cluster_bootstrap_runbook.md`, and
`documents/operations/apple_silicon_runbook.md`

### Objective

Complete the per-machine fleet doctrine reconciliation that Sprint 0.20 left partial, and make the
governed-doc rule against implementation-status prose semantic and mechanically enforced. The
timeless supported contract is one process per role per machine, at-least-once delivery with an
effectively-once observable outcome, and single-instance platform recovery. Governed docs describe
that contract without recording whether implementation or validation has landed.

### Deliverables

- the root `README.md` HA cleanup, and timeless topology and recovery rewrites across the daemon,
  demo, durable-context, web, object storage/access, Pulsar, PostgreSQL, testing, and runbook
  surfaces
- the live startup-pod recycle path is the supported recovery, and it is the only one documented
- removal of implementation status, phasing, and checklist prose from the Pulsar workflow contract
- timeless `bounded_inference_memory.md` and `bounded_host_memory.md` rewrites, and direct-contract
  rewrites in `runtime_modes.md`, `model_catalog.md`, and `k8s_storage.md`
- the timeless `typed_execution_plan.md` rewrite, the complete governed-doc semantic status
  inventory, `src/Infernix/Lint/Docs.hs` enforcement that goes beyond exact phrase, Sprint, Wave,
  and date recognition to the semantic form, and focused semantic negative fixtures in
  `test/haskell-style/Spec.hs`
- `documents/development/assistant_workflow.md` corrected: the stale bounded-host-memory paragraph
  replaced by the current canonical wording, the missing per-machine fleet paragraph added, and
  three relative doctrine links adjusted. The normalized workflow-versus-`AGENTS.md` block and the
  `AGENTS.md`/`CLAUDE.md` bodies each compare byte-for-byte (`cmp = 0`)
- `development_plan_standards.md` corrected to ask timelessly what the rule is, how it is enforced,
  and what is local substrate detail versus true platform contract, in place of the conflicting
  mandate to narrate current status against target
- the Sprint 0.22 docs field written in the validator-required `**Docs to update**:` form, which is
  the form every other sprint block already uses

### Validation

- the governed `./bootstrap/apple-silicon.sh build` compiles and installs the closing source
  identity; its scope is compile and install only
- aggregate `./.build/infernix test lint` exits 0: Haskell style, the isolated Cabal formatter, the
  docs policy and structure validators, Python type checking, and Black all pass, and the final
  bounded build-all links every declared component. This is style, policy, and compile evidence
  only
- full `./.build/infernix test unit` exits 0 across the compile-fail, artifact-transaction, Apple
  materializer, capped-engine fixed-observer, execution-plan-internal, main Haskell, and web
  suites, including the terminal-after-retirement and ownerless-recovery cases
- standalone `./.build/infernix lint docs` and `./.build/infernix docs check` each exit 0 with no
  output
- the focused Haskell-style fixtures are executable under correct path guards, and the semantic
  enforcement's safe controls keep the legitimate `Failover`, `Shared`, drain, single-instance,
  code, runtime, and pending vocabulary passing — the check rejects implementation-status prose
  without rejecting the supported contract that uses the same words
- repo-wide `git diff --check` exits 0

No accelerator cohort belongs to this machine-independent governance sprint.

### Remaining Work

None.

---

## Sprint 0.24: Plan Standards Enforcement [Done]

**Status**: Done. The scans are implemented, the corpus satisfies them, and `runPlanLint` runs
inside `runLint`, so the standards are enforced by the aggregate gate rather than by a maintenance
pass someone remembers to perform. This sprint is machine-independent and carries no accelerator
cohort.
**Implementation**: `src/Infernix/Lint/Plan.hs`, `src/Infernix/CLI.hs`,
`src/Infernix/CommandRegistry.hs`, `test/unit/Spec.hs`, `infernix.cabal`.
**Docs to update**: `development_plan_standards.md` Sections C, D, I, J, and Q;
`documents/reference/cli_reference.md`; `documents/reference/cli_surface.md`;
`documents/engineering/testing.md`; `documents/development/haskell_style.md`; `README.md`.

### Objective

Give the plan's own standards the treatment this repository already gives its source. Of the
standards' twenty-two sections, exactly one declared enforcement scans, and those two were prose
instructions to whoever ran a "maintenance pass" rather than code. The consequence was structural
rather than incidental: the section the corpus violates most severely — Section D — was precisely
the section with no scan, no threshold, and no owner.

### Deliverables

- `infernix lint plan`, a sibling of the existing focused lints, implementing seven scans across
  Sections C, D, I, J, and Q.
- Section Q's enforcement subsection rewritten to declare all seven, each with a statement of what
  it cannot decide, plus enforcement cross-references from Sections C, D, I, and J.
- The declared receipt-marker ceiling for a phase document, so Section D is measurable instead of
  a matter of taste.
- The backward-edge scan reading a blocker statement to its next field marker rather than to the
  end of a line, and reporting dependee-side phrasing separately.
- `runPlanLint` inside `runLint`, so a plan change cannot close with the scans unread. The scans
  stayed outside the aggregate gate only while they measured the backlog that preceded them;
  leaving them out once the corpus is clean is what would let that backlog silently return.
- The corpus driven to zero. Every phase document is a declarative description of its target
  again: the attempt-by-attempt chronology is deleted rather than relocated, open cohort gates
  are left to [cohort-validation-waves.md](cohort-validation-waves.md), the design decisions those
  attempts produced survive as present-tense statements in the sprint that owns each, `Done`
  sprints carry no remaining work, and one phase-status table exists across the whole plan.
- Machine-independent unit coverage for every scan, pinning both the rule and the false-positive
  class its tuning removed.

### Validation

`infernix lint plan` exits 0 against the corpus; `infernix test lint` exits 0 with the new module
under Ormolu, HLint, and the readability rules and with the scans running inside the aggregate
gate; `infernix test unit` exits 0 with the scan assertions; `infernix lint docs` exits 0 with the
generated CLI sections hand-transcribed to match the registry renderers; repo-wide
`git diff --check` exits 0.

Each scan was tuned against sampled evidence rather than shipped at its first count. Five
false-positive classes were found and removed: a horizontal rule counted as remaining work, a
`None` discharge carrying an explanatory clause, prose reasoning about inode allocation counted as
an inode receipt, symbol overlap pairing unrelated ledger rows, and a removal-ledger row whose
first cell names the phase owning the removal counted as a second phase-status table. A scan that
cries wolf is worse than no scan, so the tuning is part of the deliverable rather than a detail of
it, and each removed class carries a unit assertion so it cannot return.

### Remaining Work

None.

---

## Sprint 0.25: Phase-Scope Independence And The Forward-Ownership Scan [Done]

**Status**: Done — machine-independent. This sprint carries no accelerator cohort and blocks no
accelerator phase.
**Implementation**: `DEVELOPMENT_PLAN/development_plan_standards.md`, `src/Infernix/Lint/Plan.hs`,
`test/unit/Spec.hs`
**Docs to update**: none. The standards file is the governed home for this rule, and it is the file
this sprint changes.

### Objective

Make an earlier phase completable and validatable without any later phase, and enforce it.

### Deliverables

- Section C states phase-scope independence: a phase's status describes only the scope that phase
  owns, and a later phase stays `Done` when an earlier one gains sprints
- Section C states the converse obligation: every phase must be completable using only
  equal-or-lower-numbered phases, and a deliverable a higher-numbered phase owns on an earlier
  phase's behalf is re-homed rather than recorded
- Sections A and Q widen the forward-only invariant from blocker edges to dependencies of every form
- Section Q gains scan 8, and `Infernix.Lint.Plan` implements it
- Section G blesses the two header fields a closed sprint uses to point forward without reopening

### Validation

- The rule was previously the other way round, and that is the defect. Section C had made a later
  phase's `Done` conditional on an earlier phase staying frozen, which meant adding scope to an
  earlier phase silently invalidated everything above it — the opposite of a plan workable in
  numerical order.
- Scan 1 reads `Blocked by` statements, so it is structurally blind to the form the violation
  actually takes: a sentence placing an obligation with a later sprint. Scan 8 reads those sentence
  forms — a deliverable another sprint owns, work re-homed forward, an implementation landed with a
  later sprint — and is the reason this sprint is enforcement rather than prose. Section Q's own
  preamble is the argument: a rule that is only prose is a rule that decays.
- **Fifteen violations across four phase documents, reduced to zero.** The scan found forward
  ownership in Phases 0, 1, 4 and 5 — five times what a reading pass had identified. Each was
  re-stated as a scope boundary or as a supersession rather than as a transfer of obligation, which
  is the distinction the rule turns on: a closed sprint naming what replaced it is Section G working,
  while an open deliverable another phase owns is the violation.
- The scan is negative-tested in both directions and for its exemption: an obligation placed with a
  later sprint is reported, the same sentence pointing at an earlier sprint is not, and a closed
  sprint's supersession field is exempt.
- `infernix lint plan` reports all eight scans at zero, and `infernix lint docs` plus `docs check`
  stay clean.

### Remaining Work

None.

---

## Sprint 0.26: Retired Governed-Document Inventory Closure [Done]

**Status**: Done — machine-independent. This sprint carries no accelerator cohort and blocks no
accelerator phase.
**Implementation**: `src/Infernix/Lint/Docs.hs`, `documents/README.md`
**Docs to update**: `documents/README.md`

### Objective

Keep the mechanically required governed-document inventory identical to the target documentation
suite after a target document is retired.

### Deliverables

- `requiredDocs` names only governed Markdown documents that exist
- the documentation index links only to target documents that the suite still owns
- the conformance probe whose sole contract was the retired document is absent rather than retained
  as an unsupported implementation surface
- missing required documents and newly added unregistered documents remain fail-closed lint errors

### Validation

- `infernix lint docs` exits zero with the retired path absent from both the inventory and the tree
- `infernix lint plan` and `infernix docs check` exit zero
- `infernix test lint` exits zero with the Haskell style, Cabal format, Python, file, chart, proto,
  docs, and plan gates running through the closed CLI surface

### Remaining Work

None.

---

## Sprint 0.27: At-Least-Once Delivery Language and Ledger Closure [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: none. The governed architecture already states the target delivery contract.

### Objective

Make every plan-level model-staging and pool-delivery claim match the supported at-least-once
transport with an effectively-once observable outcome, and remove Phase 0 ledger rows whose named
surfaces no longer exist.

### Deliverables

- model-bootstrap and result-path validation prose attributes duplicate collapse to producer dedup
  and the terminal sentinel instead of claiming exactly-once transport
- the host-memory doctrine retains the exclusive-host-claim account and contains no claim that the
  toolchain and inference partitions are serialized by one validation bracket
- the corresponding Phase 0 rows leave the pending-removal ledger

### Validation

- `./.build/infernix lint plan`
- `./.build/infernix lint docs`
- `./.build/infernix docs check`

### Remaining Work

None.

---

## Sprint 0.28: Standards Self-Consistency and the Chronology Scan [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/development_plan_standards.md`, `src/Infernix/Lint/Plan.hs`, `test/unit/Spec.hs`
**Docs to update**: none. The governed suite already states the single-instance topology and the
host-tool accessor this sprint aligns the standards to.

### Objective

Make the standards internally consistent and subject to their own Section D.

Three defects, all the same shape — a rule standing on the chronology that produced it rather than
on its own statement. Section K described `coordinator.replicaCount` and `engine.replicaCount`
knobs with "defaults ≥ 2" while Section L forbids describing replica knobs as supported surface at
all and the chart deploys one replica per role; the contradiction survived because the Section K
sentence is written as an account of what a sprint did, and an account is not read as a rule.
Section O's canonical command surface omitted `infernix lint plan` while Section Q names it the
enforcement of the standards. Section V named `runHostTool` as the canonical helper after it was
removed as dead code.

The triage verdict is **T1** throughout: each superseding decision is the current contract, so the
standards yield, not the code.

### Deliverables

- Section K states the three-role Deployment shape, the absent service-data PVC, one process per
  machine, and eager coordinator staging as present-tense rules, with no replica-count knob and no
  sprint attribution
- Section K states the three supported MinIO buckets as the whole set rather than naming the
  placeholder buckets that are gone, and states the Playwright invocation rather than the image
  whose retirement produced it
- Section L states that no fused `infernix-service` pod exists, without narrating the split
- Section O lists `infernix lint plan` in the canonical command surface
- Section V names `hostToolPath`, with `readHostTool` / `readHostToolFallback` for the pre-manifest
  `infernix init` window
- `standardsChronologyViolations` rejects any `Sprint <phase>.<number>` reference in the standards
  document. Scan 5 reads phase documents only, which is why the document that states Section D was
  the one corpus member exempt from it

### Validation

- `./.build/infernix lint plan`
- `./.build/infernix lint docs`
- `./.build/infernix docs check`
- `./.build/infernix test unit` — the negative fixture asserts the scan rejects the exact Section K
  sentence removed here, admits the rule restated without its history, and leaves phase documents to
  scan 8

### Remaining Work

None.

---

## Sprint 0.29: Governed-Suite File-Type Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Lint/Docs.hs`, `test/haskell-style/Spec.hs`
**Docs to update**: none. `documents/development/python_policy.md` already confines Python to the
adapter and native-runner surfaces.

### Objective

Close the hole that let a source file live in the documentation root governed by nothing.

The coverage-completeness guard lists `.md` files before it checks registration, so a file that is
not a document at all is invisible to it. A tracked Python measurement harness sat under
`documents/engineering/` outside every policy: not on the Python surface `python_policy.md`
permits, not in the Haskell style inventory, not in the `documents/README.md` index, referenced by
no document, and citing a section number no governed document carries.

Triage verdict **T3**: `python_policy.md` already declares the target — build helpers are Haskell —
so the doc stands and the file goes.

### Deliverables

- `documents/engineering/crash_harness.py` is deleted; Git holds the measurement it recorded
- `listAllFilesUnder` enumerates the suite without an extension filter, which the registration
  guard's own listing cannot do
- `governedSuiteFileTypeViolations` rejects any non-Markdown file under `documents/`

### Validation

- `./.build/infernix lint docs`
- `./.build/infernix docs check`
- `./.build/infernix test lint` — the negative fixture asserts the check rejects the exact path
  that sat in the suite, and admits the governed documents beside it

### Remaining Work

None.

---

## Sprint 0.31: Assistant-Workflow Guarantee Precision [Done]

**Status**: Done
**Implementation**: `documents/development/assistant_workflow.md`, `src/Infernix/Lint/Docs.hs`, `test/haskell-style/Spec.hs`
**Docs to update**: `documents/development/assistant_workflow.md`

### Objective

Two rules in the canonical list claimed a stronger mechanism than the one that exists, and in both
cases the entry-document mirrors already carried the precise statement — the canonical list was the
weaker text. That inversion is the reason to fix it here rather than anywhere else: a mirror is
supposed to be a faithful subset of the canonical list, so a mirror that is *more* accurate means
the canonical is the copy a careful reader would be misled by.

The cluster-ownership rule said tearing down an `OperatorOwned` cluster "does not typecheck". The
type index decides the lease, not who owns a live cluster; ownership of a running cluster is a
fail-closed evidence check under the held lease, so the refusal is a checked one rather than GHC's.
The memory-safety rule said the capped-engine kernel OS-bounds resident memory and that observers
enforce ceilings, without the per-lane qualification the doctrine carries everywhere else, and
without the statement that no kernel mechanism bounds device memory on any lane.

Triage verdict **T1** for both: the doctrine documents already state the precise mechanism, so the
rule list yields to them.

### Deliverables

- the cluster-ownership rule states what the index decides and what remains a checked refusal
- the memory-safety rule states the three enforcement layers, that a lane declares the strength it
  has, and that no kernel mechanism bounds device memory on any lane
- `mirrorRuleDivergenceViolations` rejects a `## Non-Negotiable Rules` section present in one entry
  document and absent or altered in the other. The divergence is only ever observed by the reader
  who loads the stale copy, which is why it needs a gate rather than a review habit
- the check states what it does not decide: the mirrors paraphrase, so no textual comparison can
  settle whether either is a faithful subset of the canonical list

### Validation

- `./.build/infernix lint docs`
- `./.build/infernix docs check`
- `./.build/infernix test lint` — the negative fixture asserts the check rejects both a rule added
  to one mirror and a rule altered in one mirror, and admits two identical sections

### Remaining Work

None.

---

## Sprint 0.34: Charter Termination and the Frozen Mechanical Set [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-0-documentation-and-governance.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`
**Blocked by**: nothing.
**Docs to update**: none. The change is to the plan's own governing text.

### Objective

Give this phase a closing sprint and remove the two rules that made closure unreachable.

The reopen charter made a doctrine defect a mandatory sprint, and a governance sprint installs a
check whose wider net finds the defect that becomes the next sprint. The result is a phase that
audits its own audit apparatus: the implementation fields of the sprints before this one name the
lint modules, the standards, the component inventory and the cleanup ledger, and nothing else.

Section A also carried a gate — no code-writing phase marked `Active` or `Done` before this phase
closes — that Section C's scope-independence rule already repealed in practice and that the corpus
had contradicted for its whole history. Two rules answering one question differently is worse than
either answer.

### Deliverables

- the charter states that this phase closes at Sprint 0.36 and does not reopen. A prose-only
  doctrine defect is recorded in the sprint that finds it and is not scheduled as work of its own; a
  defect in a mechanism claim is a bug in the phase that carries the code, and the documentation
  edit travels with the code fix
- Section A's standing gate and Section C's `Blocked`-instead-of-`Planned` rule are deleted; Section
  C's scope-independence rule stands as the single statement on cross-phase status
- Section Q enumerates the mechanical governance set by name rather than by count, and states that a
  new check is added only by retiring a named member. `Infernix.Lint.HaskellStyle` is outside the
  set: its rules bound what the code may do, and a newly reachable unsafe construct is a reason for
  a new rule there
- the enumeration states what holds it true — a review obligation, not a mechanism — because a list
  and the dispatch it describes are two texts, and claiming a gate that does not exist is the defect
  this phase spent three sprints removing from other documents

### Validation

- `infernix lint plan`
- `infernix lint docs`
- `infernix docs check`

### Remaining Work

None.

---

## Sprint 0.35: Attestation Recording [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/cohort-validation-waves.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/README.md`
**Blocked by**: nothing.
**Docs to update**: none.

### Objective

Retain the evidence a `Done` rests on.

Section Q makes a committed per-lane attestation the gate for `Done`, and Section D deleted the
record once the gate closed. Composed, the two guaranteed that the file the plan named as its
attestation home was empty whenever the work was finished, and three documents pointed readers at it
anyway. A status whose evidence has been destroyed cannot be checked by anyone, which is the
opposite of what honest completion tracking is for.

### Deliverables

- `cohort-validation-waves.md` carries a Recorded Attestations table beside its open-gate table.
  The table is append-only and strictly tabular: a cell holds an identifier, a lane, a gate, a
  commit or an outcome, and the account of how a run went belongs to nothing in this plan
- Section D distinguishes the narrative the plan does not carry from the tuple it does: a closure is
  recorded as a row and the row is retained, while the chronology that produced it is deleted
- Section Q states that a `Done` cites a row, and the register of what a clean lint report does not
  establish names that citation, because a scan reads text on disk and cannot see when a status was
  written
- the phase and root documents that pointed at an empty file for per-lane attestation no longer
  claim it

### Validation

- `infernix lint plan`
- `infernix lint docs`
- `infernix docs check`

### Remaining Work

None.

---

## Sprint 0.36: Open-Work Rehoming and Phase 0 Closure [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/`, `documents/architecture/configuration_doctrine.md`, `documents/architecture/tenant_isolation_doctrine.md`, `CLAUDE.md`, `AGENTS.md`
**Blocked by**: nothing.
**Docs to update**: `CLAUDE.md`, `AGENTS.md`

### Objective

Make the plan answer the question an assistant actually asks it: what is open, and where do I start.

Every phase after this one read `Done` while the corpus carried verified defects, an instruction to
rerun a suite after two phases that had already closed, a dependency on a sprint that had already
discharged it, and twenty-five blocker fields naming sprints that were themselves closed. A reader
navigating that corpus finds either nothing to do or several hundred imperative bullets inside
closed sprints, and no way to tell the two apart.

### Deliverables

- Phases 4, 6, 8 and 9 return to `Active`, each header naming the sprints that carry its verified
  defects and each phase carrying a `Remaining Work` body that lists them
- every blocker field naming a closed sprint states `nothing` with the satisfied dependency in
  prose, and the four fields that ran two bold keys together on one line are separated
- the sections and sentences that asserted open work beneath a closed header are deleted, including
  a reopened-work section whose subject had no antecedent
- claims about constructs that do not exist, or that describe a wiring the code no longer has, are
  corrected against the code
- the cleanup ledger names a live owner for every row, and the row whose surface the code retains by
  design is deleted
- `README.md` states how open work is identified, because the marker and the prose disagree in
  several hundred closed sprints and only the marker is reliable
- the entry documents state each architectural invariant once and link its doctrine, rather than
  restating the doctrine at a length no reader carries into a task

### Validation

- `infernix lint plan`
- `infernix lint docs`
- `infernix docs check`

### Remaining Work

None.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - canonical ownership and summary-versus-source rules
- `documents/README.md` - docs-suite index and entry points
- `documents/engineering/testing.md` - canonical failure-classification and validation doctrine
- `documents/engineering/build_artifacts.md` - build-artifact, generated-output, and
  forbidden-surfaces doctrine
- `documents/engineering/edge_routing.md` - routing ownership baseline
- `documents/engineering/implementation_boundaries.md` - repository ownership boundaries and
  generated-output rules
- `documents/engineering/k8s_storage.md` - manual-storage doctrine and deterministic PV
  inventory rules
- `documents/engineering/storage_and_state.md` - durable-versus-derived state inventory
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) -
  managed-state-transition doctrine (typed evidence `E(S)` per state, unexported raw primitives,
  evidence-returning readiness waits, typed `ClusterLifecycle` machine) this phase now references

**Product or reference docs to create/update:**
- `README.md` - orientation layer aligned with the governed docs
- `AGENTS.md` - governed automation entry document
- `CLAUDE.md` - governed automation entry document
- `documents/development/haskell_style.md` - current `ormolu` + `hlint` + `cabal format` style
  stack
- `documents/development/testing_strategy.md` - operator-facing validation detail for the current
  lifecycle, cold-versus-warm expectations, and matrix
- `documents/reference/cli_reference.md` - canonical CLI command inventory
- `documents/reference/cli_surface.md` - short command-family overview and status-surface summary
- `documents/architecture/runtime_modes.md` - staged-substrate runtime and daemon-placement
  contract
- `documents/operations/apple_silicon_runbook.md` - Apple lifecycle expectations, long-running
  convergence phases, and teardown behavior
- `documents/operations/cluster_bootstrap_runbook.md` - supported cluster reconcile and teardown
  workflow, long-running image publication or preload phases, and false-negative guardrails

**Cross-references to add:**
- keep [DEVELOPMENT_PLAN/README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) aligned when documentation governance or
  architecture-baseline language changes
- keep [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
  and [phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md)
  aligned when the supported docs suite changes how operators classify slow convergence versus
  real lifecycle failure
