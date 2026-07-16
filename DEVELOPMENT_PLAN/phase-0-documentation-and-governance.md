# Phase 0: Documentation and Governance

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Establish the governed `documents/` suite, the standards that keep the plan and
> docs aligned, and the documentation-first baseline that all later implementation phases depend on.

## Documentation-First Gate

Phase 0 closes the documentation bootstrap only. Later phases still own follow-on documentation
work whenever the implementation direction changes, but they do so on top of the governed suite and
lint rules established here.

> **Realness reopen (governed-doc reconciliation).** The realness-by-construction program (Phases
> 1/4/6) changed the model bindings and replaced the "real-output proof remains a substrate
> cohort gate" softener with a code-enforced realness invariant. Phase 0 reopened under Sprint 0.11
> to reconcile the governed docs — the README matrix + Coverage Closure Rules
> (in lockstep with `Models.hs` and `model_catalog.md`), `model_catalog.md` / `testing_strategy.md` /
> `python_policy.md`, a new realness doctrine home, and the forbidden-phrase purge — and to review
> `README.md` / `AGENTS.md` / `CLAUDE.md` together, then **re-closed**. This was machine-independent
> (Axis-1 only: `infernix lint docs` / `docs check`); it had no accelerator gate and blocked no
> accelerator phase.

## Current Repo Assessment

Phase 0 is closed around the governed `documents/` suite and the canonical root-document posture
that the repository actually uses today. The governed docs, root docs, and development plan
describe the same staged-substrate mechanics and the Phase 6 Apple split-executor product shape.
The repository and README matrix still point at `apple-silicon` as the Apple-native
inference lane, and the plan now records the clarified contract explicitly: Apple host workflows stage
`./.build/infernix.dhall` through `./.build/infernix internal materialize-substrate
apple-silicon`, Linux outer-container workflows stage
`/workspace/.build/outer-container/build/infernix.dhall` inside the launcher image through
`docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`,
and the routed Apple path is clustered service orchestration plus host-native inference execution:
cluster daemons remain present, and Apple inference batches move
through Pulsar into same-binary host daemons.
`infernix lint docs` and `infernix docs check` remain the governed validation entrypoints for
that closure.

Phase 0 remains closed because the governance baseline, canonical topic ownership, and docs-lint
contract are all in place. The governed runbooks, testing docs, CLI references, and plan describe
the supported first-run convergence windows in `cluster up` and `cluster down`, name the
long-running Docker build, Harbor publication, Harbor-backed final-image preload, and Apple
teardown data-sync phases explicitly, and use inactivity-aware language instead of treating
wall-clock duration alone as product failure.

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

### Remaining Work

None. The seven cleanup sprints (1.11, 2.13, 3.10, 4.13, 5.9, 6.28, 7.17)
implemented, the Apple cohort closed in Wave A, and the CUDA Linux cohort closed in Wave C with
`linux-cpu` passing on the recorded cohort validation and `linux-gpu` passing on the recorded cohort validation.

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
- `DEVELOPMENT_PLAN/README.md` Phase Overview row for Phase 0 is `Done`.

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
**Code-side closure**: Complete (machine-independent; validated 2026-06-23 on the rebuilt `linux-cpu` image by `infernix lint docs` + `infernix docs check`) — recorded the realness-by-construction program in the
governed docs: update the README "Comprehensive Model / Format / Engine Matrix" + Coverage Closure Rules
(the latter from "real-output proof remains a substrate cohort gate" to the realness invariant) in
lockstep with `Models.hs` and `model_catalog.md` so the `infernix lint docs` matrix↔catalog parity holds;
rewrite `model_catalog.md`, `testing_strategy.md`, and `python_policy.md` to the realness invariant; add
the new realness doctrine home (a dedicated `documents/architecture/realness_contract.md` or a canonical
`model_catalog.md` section); add the retired wordings ("real-output proof remains", "Wave I still
owns replacing") to `src/Infernix/Lint/Docs.hs` `forbiddenPhrases` and purge them
from the governed docs; and review `README.md` + `AGENTS.md` + `CLAUDE.md` together for the new
prerequisites and the realness lint gate. Validated by `infernix lint docs` + `infernix docs check`.
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

### Remaining Work

None. The matrix↔catalog lockstep (`Models.hs` + README + `model_catalog.md`), the
`testing_strategy.md` / `python_policy.md` rewrites, the `realness_contract.md` doctrine home, and the
`forbiddenPhrases` additions (`real-output proof remains`, `Wave I still owns replacing`) all landed
and validated 2026-06-23.

---

## Sprint 0.12: Realness Lint Enforcement Infrastructure [Done]

**Status**: Done
**Code-side closure**: Complete (machine-independent; validated 2026-06-23 on the rebuilt `linux-cpu`
image by `infernix test lint` + `poetry run check-code`) — the realness-by-construction invariant
([../documents/architecture/realness_contract.md](../documents/architecture/realness_contract.md)) is
mechanically enforced by two machine-independent lints owned here as governance: the Python
`_run_realness_ast_check` in `python/adapters/common.py` `run_check_code` (forbids `return` inside
`except`, `bytes([...])` / `b64decode` constant artifacts, and `_validation_*` / `*_smoke*` /
`*_fallback*` helper definitions across the `*_python.py` transform modules) and the Haskell
`realnessFabricationViolations` in `src/Infernix/Lint/HaskellStyle.hs` (run under the
`infernix-haskell-style` cabal test; forbids `emit_fallback_result`, `infernix_emit_validation_result`,
`native-validation`, `b64decode`, `native fallback` — `np.zeros` is intentionally not token-forbidden
since real engines use it for scratch buffers). The lint **mechanism** is Phase 0
governance; its **per-runner scope** (`realnessScopedFiles`) is extended by each accelerator phase as it
de-stubs — Phase 4 adds `Engines/LinuxNative.hs`, Phase 1 adds `Engines/AppleSilicon.hs` — so the lint
is green at every phase's closure and no accelerator phase waits on another.
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

## Sprint 0.13: Managed-State-Transition Doctrine and Escape-Token Lint [Planned]

**Status**: Planned
**Code-side closure**: `cabal build all`, `cabal test infernix-unit`,
`cabal test infernix-haskell-style`, `infernix lint docs`, and — for the native/Python surface if
touched — `poetry run check-code`; all machine-independent.
**Cohort gate**: pending — apple-silicon plus linux-cpu full-suite, owning wave TBD
**Implementation**: `documents/architecture/managed_state_transitions.md`, `src/Infernix/Lint/Docs.hs`, `src/Infernix/Lint/HaskellStyle.hs`
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing engineering/reference docs

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

- `cabal build all`, `cabal test infernix-unit`, and `cabal test infernix-haskell-style` pass on
  both the apple-silicon and linux-cpu lanes, with the new escape-token check failing on a
  reintroduced `unsafeCoerce` / `unsafePerformIO`
- `infernix lint docs` passes on both lanes, confirming the doctrine doc's metadata, links, and
  `requiredDocs` registration
- `poetry run check-code` passes on both lanes if the native/Python surface is touched

### Remaining Work

- the cohort full-suite sign-off is the residual: apple-silicon plus linux-cpu full-suite
  validation is pending, owning wave TBD

---

## Remaining Work

Sprint 0.13 (Managed-State-Transition Doctrine and Escape-Token Lint) is Planned; its
apple-silicon plus linux-cpu full-suite cohort sign-off is the outstanding residual.

Phase 0 was reopened (Sprints 0.11–0.12) for the realness governed-doc reconciliation and the
machine-independent realness lint enforcement, and is **re-closed** (validated 2026-06-23 by
`infernix lint docs` + `infernix docs check` + `infernix test lint`). Sprints 0.1-0.12 are Done.
The work was machine-independent and gated nothing on hardware; the doc reconciliation landed in
lockstep with the reopened Phase 4 catalog changes (matrix↔catalog parity), and the lint mechanism's
per-runner scope is extended by the reopened Phases 1 (Apple) and 4 (Linux) as each de-stubs.

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
  and [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
  aligned when the supported docs suite changes how operators classify slow convergence versus
  real lifecycle failure
