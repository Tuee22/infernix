# Phase 0: Documentation and Governance

**Status**: Active — Sprint 0.22 formatter-stable source has governed Apple rebuild GREEN for
compile/install only, and the docs-only monitoring-stance correction has whole aggregate lint GREEN
for style/policy/compile. Full unit is genuinely RED before test suites at bounded Python project
provisioning. Diagnose the owned-kernel failure and residue next. Independent final review remains
CLEAN with no High or Medium finding.
Strict numerical execution pauses every code-writing phase until its remaining validation closes.
**Suspended prior state**: Done — Sprint 0.21 re-closed this phase on 2026-08-08 after the bounded-host-memory
doctrine named the co-resident VM pledge and the then-missing Darwin toolchain intersection. The
current implementation now routes both toolchain and inference accounting through one fixed-path,
conservative Colima observation and subtracts the active pledge from Darwin effective memory.
Sprint 0.20 reopened and re-closed this phase for the per-machine
fleet doctrine on 2026-08-05. Sprint 0.19 reopened and re-closed it for the bounded-host-memory
doctrine and its governance surface on 2026-08-04. Sprint 0.18 closed the
no-repo-owned-native-source doctrine, governed workflow mirror, and correction evidence reset on
2026-07-27; Sprint 0.17 and Sprints 0.1-0.16 retain their recorded narrower closure.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Establish the governed `documents/` suite, the standards that keep the plan and
> docs aligned, and the documentation-first baseline that all later implementation phases depend on.

> **Correction evidence reset (2026-07-26).** Every affected Phase 0/1/2/4 source/binary digest,
> final review, Stage 1, and current-cohort statement below that predates the
> no-repo-owned-native-source correction is historical GREEN-as-run evidence only, superseded and
> nonreusable for the correction. This includes Apple bridge/materialization, lifecycle/subprocess,
> and Apple footprint-sampler evidence. A fresh final review and complete machine-independent
> correction Stage 1 passed on 2026-07-27 for the exact identity recorded under Sprint 0.18.
> Correction-dependent Apple and `linux-cpu` evidence remains open. The interrupted
> Apple attempt 5 partial gates, replay/build/registry observations, `user interrupt`, lifecycle
> contention diagnostic (`errno 35`), and supported recovery are diagnostic history, not closure.

## Documentation-First Gate

Phase 0 closes the documentation bootstrap only. Later phases still own follow-on documentation
work whenever the implementation direction changes, but they do so on top of the governed suite and
lint rules established here.

> **Fleet-doctrine completion reopen (2026-08-09).** A read-only audit found that Sprint 0.20 did
> not complete its governed-document reconciliation and that the docs lint misses semantic
> implementation-status prose. [Sprint 0.22](#sprint-022-complete-fleet-doctrine-reconciliation-and-enforce-status-free-governed-docs-active)
> is therefore the only executable sprint. It removes stale mandatory/local-HA, replication,
> leader-election, exactly-once, surviving-coordinator, deleted Patroni-repair, and retired
> pod/node-failure-injection prose; makes the timeless contract one process per role per machine,
> at-least-once with an effectively-once observable outcome, and single-instance platform recovery;
> removes implementation status from governed docs; and adds semantic negative docs-lint tests.
> This is machine-independent governance work with no accelerator cohort. Under the strict
> numerical-order rule, Phases 1-9 are blocked until Sprint 0.22 closes; their exact prior states and
> evidence remain recorded as suspended context rather than being erased.

> **Per-machine fleet reopen (2026-08-05).** The supported architecture is a fleet: multiple
> machines, each running exactly one engine process, all consuming the same `Shared` pool topic, each
> with its own model cache and its own machine contract naming the pools it serves. Three governance
> gaps forced the reopen. The delivery contract was **at-least-once and never said so** — it was
> implied by two sentences about acknowledgement ordering, while three plan documents and four
> governed docs claimed exactly-once. One-engine-per-machine was enforced by Kubernetes anti-affinity
> rather than stated as the correctness rule it is, and the rule was **waived outright on Apple** so a
> single integration assertion could pass. And the standards mandated a topology the doctrine
> retires: replicas >= 2, required anti-affinity, PodDisruptionBudgets, and "the mandatory local HA
> topology is the only supported cluster target". Phase 0 reopens under
> [Sprint 0.20](#sprint-020-per-machine-fleet-doctrine-done) to state the doctrine, correct the
> standards, rename both HA-named phase documents, and harden two docs-lint checks that made that
> rename silently green. This is machine-independent (Axis-1 only) and **re-closes in the same
> change**, as Sprints 0.11, 0.13-0.15 and 0.19 did. The implementation is owned by Sprints 3.16,
> 4.34, 6.47, 8.10 and 8.11.

> **Bounded-host-memory reopen (2026-08-04).** A host-side `cabal build` from this checkout reached
> 109.46 GiB resident on a 124.94 GiB development host and wedged it for five and a half hours. The
> kernel destroyed 111 Kubernetes pod processes and never selected the build: `oom_badness` is
> per-process and the build ran at `oom_score_adj` 0 against pods at 996-1000. The forensic finding
> that forces a governance reopen is not the incident but its cause — the toolchain is a first-class
> claimant on host RAM that appears in no partition, no budget, and no type, so it could not exceed
> a limit it never had. The same review found `bounded_inference_memory.md` asserting in its purpose
> block that a host out-of-memory kill is structurally unrepresentable while stating the opposite
> later in the same file. Phase 0 reopens under [Sprint 0.19](#sprint-019-bounded-host-memory-doctrine-done)
> to author the capacity-ledger doctrine, register it, narrow every over-claiming statement in the
> governed suite to what is actually proven, and mirror the new non-negotiable rule. This is
> machine-independent (Axis-1 only: `infernix lint docs` / `docs check` / `cabal build all`); it has
> no accelerator gate and blocks no accelerator phase, and it **re-closes in the same change** that
> authors the doctrine, exactly as Sprints 0.11 and 0.13-0.15 did. The implementation it governs is
> owned by Phase 1 Sprint 1.21 and Phase 6 Sprint 6.46.

> **Realness reopen (governed-doc reconciliation).** The realness-by-construction program (Phases
> 1/4/6) changed the model bindings and replaced the "real-output proof remains a substrate
> cohort gate" softener with a code-enforced realness invariant. Phase 0 reopened under Sprint 0.11
> to reconcile the governed docs — the README matrix + Coverage Closure Rules
> (in lockstep with `Models.hs` and `model_catalog.md`), `model_catalog.md` / `testing_strategy.md` /
> `python_policy.md`, a new realness doctrine home, and the forbidden-phrase purge — and to review
> `README.md` / `AGENTS.md` / `CLAUDE.md` together, then **re-closed**. This was machine-independent
> (Axis-1 only: `infernix lint docs` / `docs check`); it had no accelerator gate and blocked no
> accelerator phase.

> **Bounded-command application / bounded-HTTP reopen (2026-07-19).** The 2026-07-18
> single-accelerator cohort run surfaced a Harbor `docker pull` verify hang and a rate-limited
> (403 + `Retry-After`) upstream model download that the Sprint 1.16/3.14/4.28 managed-state kernels
> shipped but did not yet guard at those sites. Phase 0 reopens under
> [Sprint 0.14](#sprint-014-bounded-commandbounded-http-doctrine-documentation-done) to record the
> governance surface of the follow-on: extend `managed_state_transitions.md` (The law / Enforcement /
> Current Status) with the bounded-HTTP download-outcome kernel, the `BlobServable` witness, and the
> two new capability-gating lints; update the three-way `README.md` / `AGENTS.md` / `CLAUDE.md`
> non-negotiable mirror plus `assistant_workflow.md`; and enter the superseded surfaces into the
> deletion ledger. This is machine-independent (Axis-1 only: `infernix lint docs` / `docs check`),
> code-side closed 2026-07-19, and closed by [Wave V](cohort-validation-waves.md) (2026-07-20) —
> apple-silicon plus linux-cpu full-suite `test all` green.
> The original closure remains historical. The 2026-07-26 Phase 2 final audit found that a cached
> Docker pull could falsely mint `BlobServable`; the current implementation instead requires bounded
> authenticated platform-selected skopeo copy from Harbor into a fresh protected `dir:` store, with
> primary-preserving cleanup and command/redaction/path coverage. Phase 2's `d578…` / `a0d1…`
> final review and Stage 1 were GREEN as run, and Apple attempt 4 proved registry-only verification for the
> workload and all support images. The attempt rejected the wider freeze on Bark's 8192 MiB live
> ceiling breach. The fp16 Bark correction is implemented with focused checks GREEN; its renewed
> review and Stage 1 were also GREEN as run before the no-native-source correction superseded them.
> The all-Haskell lifecycle replacement and nested-custody self-exec anchor/supervisor/pin
> implementation are present, and the obsolete C/Cabal boundary is removed. Focused adversarial
> proof, final review, and the complete correction Stage 1 passed on 2026-07-27. Phase-owned work and
> behavioral cohorts remain ordered after Phase 0.

## Current Repo Assessment

Phase 0 is Active for formatter-stable, SOURCE-STABLE, build-GREEN Sprint 0.22. The governed prose
reconciliation, semantic docs lint, and focused fixtures are landed; static zero scans, the body
mirror, scoped diff check, and independent review are clean, with no High or Medium finding. No Sprint 0.22 governed
unit, docs, or runtime gate has run. After 5m54s claimant-free readiness following the end of
the external Cabal owner, the overlap monitor pinned owned PID 53817 and observed zero external
claimants through settlement and its final scan. Exact `./bootstrap/apple-silicon.sh build` exited
0: 65536 MiB physical minus the 49152 MiB active Colima pledge yielded 16384 MiB effective;
`J1*H4096 + 2*C1024 = 6144 MiB`, with the `GHCRTS` driver at 1024 MiB; the sdist, all 114 GHC
9.12.4 library modules including new `Infernix.Lint.Docs` as module 63, `Main` link,
install/copy to `.build/infernix`, and corrected operator/harness postamble completed. This is
compile/install evidence only. After a clean monitored readiness window from 17:15:56 to 17:21:18
(5m22s), the monitor pinned owned PID 63879 and observed zero external claimant through settlement
and final scan. Exact `./.build/infernix test lint` exited 1: the library rebuilt
`Infernix.Lint.Docs` as module 63 and the CLI as module 114; `test/haskell-style/Spec.hs` compiled
and linked; and the test started. Its sole diagnostic was
`haskell-style-check: Ormolu formatting differs:` followed by exactly
`src/Infernix/Lint/Docs.hs`; Cabal reported 0/1 with `Error: [Cabal-7125]`. Fail-fast left
HLint/readability, the isolated Cabal formatter, Python/Black, build-all, unit, and docs unrun. This
is a genuine aggregate-lint RED with no semantic or runtime claim; the governed build GREEN remains
compile/install evidence. After a clean monitored readiness window of 17:27:50–17:33:15 = 5m25s,
the monitor pinned owned PID 68221 and found zero external claimant through its final scan. One
exact `./.build/infernix test lint` invocation exited 1 intentionally after
`user error (governed Ormolu apply completed idempotently for src/Infernix/Lint/Docs.hs)`. Only the
Haskell-style component compiled, linked, and ran; the intentional stop occurred before
HLint/readability, the isolated Cabal formatter, Python, build-all, or any later gate. The target
changed from prehash `fb929508...e4bd7` to formatted `396cac91...ce68`: linked Ormolu
canonicalized the equivalent `zipWith3 (,,)` to `zip3` and adjusted only multiline
pattern/comprehension layout; a second apply was exact. The temporary checker was restored
byte-for-byte at SHA-256 `880a2763...f37`, and scoped diff check is clean. This is diagnostic and
formatter-correction evidence only. Independent formatter-delta review is CLEAN with no High or
Medium finding: `zip3` is semantically identical here, tuple bindings and `where` scope are
preserved, and fixture wiring and controls remain coherent. The formatted source is SOURCE-STABLE
and its exact governed Apple rebuild is GREEN. The prerequisite window 17:39:56–17:45:11 was
claimant-free for 5m15s. The monitor pinned owned bootstrap PID 73643 from its start around 17:45:29
through settlement at 17:48:18–17:48:24 and found zero external claimant through post-settlement
and the independent final scan at 17:49:10. Exact `./bootstrap/apple-silicon.sh build` exited 0:
65536 - 49152 = 16384 MiB effective; `J1*H4096 + 2*C1024 = 6144 MiB`; `GHCRTS` driver 1024 MiB;
sdist; all 114 GHC 9.12.4 library modules including formatted `Infernix.Lint.Docs` module 63;
`Main` link, install/copy to `.build/infernix`, and corrected postamble. This is compile/install
evidence only. The next prerequisite window, 17:53:05–17:58:18, was claimant-free for 5m13s. The
monitor owned PID 84529 from about 17:58:30 through 18:00:34, observed settlement by 18:00:39, and
found zero external claimant through the final scan at 18:01:30. Exact
`./.build/infernix test lint` exited 1. Haskell style rebuilt `Infernix.Lint.Docs` module 63 and
`test/haskell-style`, then emitted `haskell-style-check: ok` and passed. The isolated Cabal 3.16
formatter emitted `cabal-format-check: ok` and passed; its fixture warning was expected. The exact
docs-policy failure was `user error (documents/README.md must declare the monitoring stance with
the sentence: Monitoring is not a supported first-class surface.)`, with the call stack at
`Docs.hs:1206:9`. Fail-fast left Python/Black, build-all, and every later stage unrun. This is a
genuine aggregate-lint RED and supplies no semantic or runtime GREEN. The exact cause was
`documents/README.md` expressing the doctrine with comma form `surface, and`,
so the validator's required standalone sentence was absent. The only landed change is in
`documents/README.md`: `Monitoring is not a supported first-class surface. The governed docs suite
has no canonical` followed by the existing path line. The validator and all Haskell are unchanged.
The exact sentence is now present in all five `monitoringStancePaths`; there is no `monitoring.md`
or dormant monitoring stack, and scoped document diff check is clean. Independent final review is
CLEAN with no High or Medium finding and explicitly finds no rebuild warranted. At that checkpoint,
the docs-only correction was SOURCE-STABLE and unvalidated; the formatter-stable build GREEN
remained valid.
After the 18:08:43–18:13:59 prerequisite was claimant-free for 5m16s, the monitor owned PID 92170
from about 18:14:09 through 18:21:27, observed settlement by 18:21:32, and found zero external
claimant through the final scan at 18:22:35. Exact `./.build/infernix test lint` exited 0. Haskell
style emitted `haskell-style-check: ok` and passed; isolated Cabal 3.16 emitted
`cabal-format-check: ok` and passed with its expected fixture warning. Python checking succeeded for
8 source files, Black left all 8 unchanged, and the gate emitted `All checks passed!`. Final bounded
build-all completed every declared component, linking integration 116/116 and unit 117/117. This is
style/policy/compile evidence only, not unit runtime, docs, or runtime evidence. The prior
monitoring-stance RED is closed.
The 18:25:06–18:30:40 prerequisite was claimant-free for 5m34s. The monitor owned PID 1752 from
about 18:30:50 through 18:31:25, observed settlement by 18:31:33, and found zero external claimant
through the final scan at 18:32:42. Exact `./.build/infernix test unit` exited 1 before any test
suite with `bounded Python project provisioning failed` for project
`/Users/matthewnowak/infernix/python`. The kernel failure was `anchor terminal disagreed with anchor
exit ExitFailure (-9); input InputCompleted; stdout CaptureCompleted "Installing dependencies from
lock file\n\nNo dependencies to install or update\n\nInstalling the current project: infernix-adapters
(0.1.0)\n"; stderr CaptureCompleted ""`, with call stack `Python.hs:215:13`. Aggregate lint GREEN
remains valid. This is a genuine unit RED and supplies no unit or runtime GREEN.
Before that sprint opened, Phase 0 was closed around the governed
`documents/` suite. Sprint 0.18's no-native-source rule, lint
implementation, native-boundary deletion record, evidence reset, canonical root-document posture,
focused adversarial proof, final review, and source-matched machine-independent gate are complete.
The governed docs, root docs, and development plan
describe the same explicit-init runtime-config mechanics and the Phase 6 Apple split-executor
product shape.
The repository and README matrix still point at `apple-silicon` as the Apple-native
inference lane, and the plan now records the clarified contract explicitly: `infernix init` creates
repo-root `./infernix.dhall` plus `./infernix-host.dhall`, `infernix test init` creates the harness
input, ordinary config-dependent commands fail fast rather than auto-materializing missing config,
and the routed Apple path is clustered service orchestration plus host-native inference execution:
cluster daemons remain present, and Apple inference batches move
through Pulsar into same-binary host daemons.
`infernix lint docs` and `infernix docs check` remain the governed validation entrypoints for
that closure.

That prior closure evidence remains valid for its recorded scope because the governance baseline,
canonical topic ownership, and docs-lint contract are in place. Sprint 0.22's stale fleet/status
reconciliation is SOURCE-STABLE and landed; only its ordered validation remains before Phase 0 can
close again. The governed runbooks, testing docs, CLI references, and plan describe
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

## Sprint 0.13: Managed-State-Transition Doctrine and Escape-Token Lint [Done]

**Status**: Done — the Managed-State-Transition Doctrine doc and the `unsafeCoerce` /
`unsafePerformIO` escape-token lint were code-side closed (machine-independent gates) 2026-07-16,
and the single-accelerator (apple-silicon) plus linux-cpu full-suite sign-off closed by
[Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-16 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style` (the new escape-token check is
clean on the tree and was verified to fail on a reintroduced `unsafeCoerce` / `unsafePerformIO` in
an evidence module), `infernix lint docs`, and `infernix docs check` all green on the apple-silicon
lane. No native/Python change in this sprint, so `poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
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

- code-side closed 2026-07-16 (apple-silicon lane): `cabal build all` (`-Wall -Werror`),
  `cabal test infernix-unit`, and `cabal test infernix-haskell-style` all pass. The new
  `escapeTokenViolations` check in `src/Infernix/Lint/HaskellStyle.hs` is clean on the tree and was
  verified to fail with the doctrine diagnostic on a reintroduced `unsafeCoerce` / `unsafePerformIO`
  token injected into an evidence-kernel module (reverted after the negative-test confirmation)
- `infernix lint docs` and `infernix docs check` pass, confirming the doctrine doc's metadata,
  links, and `requiredDocs` registration (the doc was authored and registered in
  `src/Infernix/Lint/Docs.hs` `requiredDocs` and `documents/README.md` on 2026-07-15; the
  escape-token lint is the code delta that lands this sprint)
- `poetry run check-code` is not applicable — no native/Python surface changed
- the linux-cpu lane rerun of the code-side gates closed under [Wave V](cohort-validation-waves.md)

### Remaining Work

- the cohort full-suite sign-off closed under [Wave V](cohort-validation-waves.md) (2026-07-20) —
  apple-silicon plus linux-cpu full-suite `test all` green; no remaining work exists

---

## Sprint 0.14: Bounded-Command/Bounded-HTTP Doctrine Documentation [Done]

**Status**: Done — the `managed_state_transitions.md` bounded-command/bounded-HTTP governance
extension and the three-way non-negotiable mirror were code-side closed (machine-independent gates)
2026-07-19, and the single-accelerator (apple-silicon) plus linux-cpu full-suite sign-off closed by
[Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-19 — this is a docs-and-governance sprint, so the applicable
machine-independent gates are `infernix lint docs` and `infernix docs check`, both green on the
apple-silicon lane; `cabal build all` (`-Wall -Werror`), `cabal test infernix-unit`, and
`cabal test infernix-haskell-style` are unaffected by the Markdown-only change. No Python/native
change, so `poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
**Implementation**: `documents/architecture/managed_state_transitions.md`, `README.md`, `AGENTS.md`,
`CLAUDE.md`, `documents/development/assistant_workflow.md`, `documents/tools/harbor.md`,
`documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`,
`documents/development/no_env_vars.md`, `documents/development/haskell_style.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Blocked by**: Sprint 0.13
**Docs to update**: `documents/architecture/managed_state_transitions.md`, the three-way non-negotiable
mirror (`README.md` / `AGENTS.md` / `CLAUDE.md` plus `documents/development/assistant_workflow.md`),
and the phase's existing engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — record the
governance surface of the follow-on that applies the Sprint 1.16/3.14/4.28 managed-state kernels at
the two flake sites the 2026-07-18 cohort run surfaced (the Harbor `docker pull` verify hang and the
rate-limited upstream model download). Governance is current-state and honest: the doctrine doc, the
non-negotiable mirror, and the deletion ledger record what the code does now (bounded publish exec,
`BlobServable` evidence, the classified download outcome, the integrity-witnessed sentinel, and the
two new capability-gating lints), while the deferred readiness-wait migration and ProcessMonitor
retirement (Sprint 6.41) are tracked as remaining, not claimed done. The doctrine is canonical at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `documents/architecture/managed_state_transitions.md` extended: the bounded-HTTP download-outcome
  kernel added to `## The law` beside the `SubprocessEnv` / `CommandOutcome` bullet, `BlobServable`
  added to the readiness-returns-evidence paragraph, the two new lints (`unboundedExecViolations`,
  `unboundedHttpViolations`) reflected in the TL;DR and `## Enforcement`, and the 2026-07-19
  sprint→phase mapping in `## Current Status`
- the three-way non-negotiable mirror updated: the `evidence-gated state transitions` bullet extended
  with the raw-unbounded-spawn / `runBoundedCommand` clause (enforced by `unboundedExecViolations`)
  and a new peer hard-stop for raw unbounded upstream-model-download HTTP (enforced by
  `unboundedHttpViolations`) in `documents/development/assistant_workflow.md` (canonical) mirrored
  byte-identically into `AGENTS.md` and `CLAUDE.md`, with `README.md` carrying the prose form
- the current-state operator-doc touch-ups (`documents/tools/harbor.md`,
  `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`,
  `documents/development/no_env_vars.md`, `documents/development/haskell_style.md`) and the
  `legacy-tracking-for-deletion.md` ledger rows

### Validation

- `infernix lint docs` and `infernix docs check` pass, confirming metadata, the broad-doctrine-doc
  structure for `managed_state_transitions.md`, root-doc metadata, link resolution, and the
  monitoring-stance alignment (ProcessMonitor is not yet retired, so the "no monitoring doc" stance
  still holds)
- the `AGENTS.md` / `CLAUDE.md` non-negotiable blocks stay byte-identical to each other and a faithful
  subset of `assistant_workflow.md`

### Remaining Work

- the cohort full-suite sign-off closed under [Wave V](cohort-validation-waves.md) (2026-07-20) —
  apple-silicon plus linux-cpu full-suite `test all` green; no remaining work exists

---

## Sprint 0.15: Bounded-Inference-Memory Doctrine and Non-Negotiable Mirror [Done]

**Status**: Done — the `bounded_inference_memory.md` memory-safety-by-construction doctrine doc, its
docs-lint registration, and the three-way non-negotiable mirror are doc-only and machine-independent;
closed on `infernix lint docs` + `infernix docs check` + `cabal build all` on the apple-silicon lane
(2026-07-21). Wave W later closed the original Phase 4 Sprints 4.30/4.31 plus Phase 6 Sprint 6.42
scope. The 2026-07-25 audit superseded that first unindexed admission API: the governed doctrine and
mirrors now describe Phase 1's indexed compile/refine/executable boundary. Phase 1 passed its
complete source-matched gate on 2026-07-25; the remaining enforcement work is owned by Phase 4
Sprint 4.32 and Phase 6 Sprint 6.44.
**Code-side closure**: closed 2026-07-21 — this is a docs-and-governance sprint, so the applicable
machine-independent gates are `infernix lint docs` and `infernix docs check` (both green: the new
doctrine doc's metadata, links, broad-doctrine-doc structure, and `requiredDocs` / `DocumentStructureRule`
registration validate), plus `cabal build all` (`-Wall -Werror`, unaffected by the Markdown-only
change). No Python/native change, so `poetry run check-code` does not apply.
**Implementation**: `documents/architecture/bounded_inference_memory.md`, `src/Infernix/Lint/Docs.hs`,
`README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/assistant_workflow.md`
**Docs to update**: `documents/architecture/bounded_inference_memory.md`, the three-way non-negotiable
mirror (`README.md` / `AGENTS.md` / `CLAUDE.md` plus `documents/development/assistant_workflow.md`),
and `documents/README.md`

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
  direct-FFI sampler and its Apple-specific evidence are superseded; Sprint 4.32 owns the current
  fixed bounded `/usr/bin/top` plus `/usr/bin/footprint` observer
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

### Remaining Work

None. The doc and governance surface are landed and machine-independent-closed. The enforcing code — the
`MemoryGrant`-gated capped-engine kernel, the checked `HostMemoryPartition`, the required
`ModelMemoryFootprint`, the budget-enforcer split, and the `unboundedEngineSpawnViolations` lint — is
code-side closed 2026-07-21 (Phase 4 Sprints 4.30/4.31 + Phase 6 Sprint 6.42), with the behavioral
[Wave W](cohort-validation-waves.md) sign-off pending, tracked there.

---

## Sprint 0.16: Cluster-Ownership Doctrine and Non-Negotiable Mirror [Done]

**Status**: Done — the Cluster-Ownership & Mutation-Position doctrine (extending the existing
`managed_state_transitions.md`), the three-way non-negotiable mirror, the new `documentation_standards.md`
Update Rule, and the operator / test-harness / persistence doc reconciliation are doc-only and
machine-independent; closed on `infernix lint docs` + `infernix docs check` + `cabal build all` on the
apple-silicon lane (2026-07-23). [Wave X](cohort-validation-waves.md) historically closes the
2026-07-23 enforcing-code scope in Phase 2 Sprint 2.15 and Phase 6 Sprint 6.43. It does not close the
2026-07-25 owner-atomic reservation/teardown correction. Phase 2's first 2026-07-26 Stage 1 and
Apple attempt were rejected for closure. The later Apple retry proved production dead-owner
recovery and exhaustive cleanup, but BuildKit diagnosed its Linux-image failure as deterministic
`-Wunused-top-binds`/`-Werror` at unguarded Darwin-only `continueIfRunning`, not resource pressure.
The later Apple result diagnosed Bark's 5120 MiB footprint under-estimate. Its 8192 MiB
recalibration, strict admitted-placement integration rule, Playwright catalog-matrix
runtime-ceiling escape-hatch removal, and exact Apple/Linux admission unit tests are implemented.
The registry-only Harbor verification correction is also implemented after the final audit.
Final review and corrected-source Stage 1 passed for `d578…` / `a0d1…`, but Apple attempt 4
rejected that freeze after Bark breached the live ceiling at 8192 MiB. The fp16 Bark correction
passed renewed final review and complete Stage 1 against `eae424…` / `a0d1…` as historical
GREEN-as-run evidence. The no-native-source correction supersedes it. The lifecycle replacement is
present, as is the bounded-subprocess replacement, and the obsolete C/Cabal boundary is removed.
Phase 0's post-correction proof passed on 2026-07-27; both Wave Y lanes remain open.
**Code-side closure**: closed 2026-07-23 — this is a docs-and-governance sprint, so the applicable
machine-independent gates are `infernix lint docs` and `infernix docs check` (both green: the extended
doctrine doc's links and structure, the new `documentation_standards.md` Update Rule, and the reconciled
operator / test-harness / persistence docs validate), plus `cabal build all` (`-Wall -Werror`, unaffected
by the Markdown-only change). No new required doc is registered (the doctrine extends the
already-registered `managed_state_transitions.md`), and no Python/native change, so `poetry run check-code`
does not apply.
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

None for this doc-and-governance sprint. The surface is landed and machine-independent-closed.
[Wave X](cohort-validation-waves.md) (2026-07-24, apple-silicon plus linux-cpu) historically closes
the 2026-07-23 enforcing-code scope: the `ClusterOwner` field, `ClusterMutating` position,
fail-closed persistence, reconcile, evidence-gated seizure, chaos-mutation transitions, and
crash-safe config swap. It does not close the 2026-07-25 owner-atomic reservation/teardown
correction. Phase 2's first 2026-07-26 Stage 1 and Apple attempt were rejected for closure. The
later Apple retry proved recovery/cleanup but exposed deterministic Linux `-Werror`; the CPP
correction invalidated that source identity. The later Bark footprint/test and registry-only
Harbor verification corrections passed final review and corrected-source Stage 1 for
`d578…` / `a0d1…`, but Apple attempt 4 rejected that freeze on Bark's 8192 MiB live-ceiling
breach. The fp16 Bark correction is implemented with focused checks GREEN; renewed full validation
was GREEN as run before the no-native-source correction superseded it. The lifecycle replacement is
present, as is the bounded-subprocess replacement, and the obsolete C/Cabal boundary is removed.
Focused correction proof and fresh review/Stage 1 passed on 2026-07-27; both Wave Y lanes remain
open.

---

## Remaining Work

Current Phase 0 remaining work is Sprint 0.22. The earlier closure record below remains historical
evidence for its narrower sprint scopes and does not override the active Sprint 0.22 gate.

Sprint 0.13 (Managed-State-Transition Doctrine and Escape-Token Lint) is Done — code-side closed
2026-07-16 (doctrine doc + `requiredDocs`/`documents/README.md` registration authored 2026-07-15;
the `unsafeCoerce` / `unsafePerformIO` escape-token lint landed and negative-tested 2026-07-16), and
its apple-silicon plus linux-cpu full-suite cohort sign-off closed by
[Wave V](cohort-validation-waves.md) (2026-07-20).

Sprint 0.14 (Bounded-Command/Bounded-HTTP Doctrine Documentation) is Done — code-side closed
2026-07-19 (the `managed_state_transitions.md` extension, the three-way non-negotiable mirror, and the
`legacy-tracking-for-deletion.md` ledger rows landed; `infernix lint docs` / `docs check` green), and
its apple-silicon plus linux-cpu full-suite cohort sign-off closed by
[Wave V](cohort-validation-waves.md) (2026-07-20).

Sprint 0.15 (Bounded-Inference-Memory Doctrine and Non-Negotiable Mirror) is Done — closed 2026-07-21
on `infernix lint docs` + `infernix docs check` + `cabal build all`. It is doc-only and
machine-independent: the `bounded_inference_memory.md` memory-safety-by-construction doctrine doc, its
`requiredDocs` + `DocumentStructureRule` registration in `src/Infernix/Lint/Docs.hs` + `documents/README.md`
index, and the new non-negotiable rule in the three-way `README.md` / `AGENTS.md` / `CLAUDE.md` mirror
plus `assistant_workflow.md` all landed. It has no cohort gate — the enforcing code is `Planned` Phase 4
(Sprints 4.30/4.31) and Phase 6 (Sprint 6.42) work, whose single-accelerator (apple-silicon) plus
`linux-cpu` sign-off is [Wave W](cohort-validation-waves.md), tracked there.

Sprint 0.16 (Cluster-Ownership Doctrine and Non-Negotiable Mirror) is Done — closed 2026-07-23 on
`infernix lint docs` + `infernix docs check` + `cabal build all`. It is doc-only and machine-independent:
the Cluster-Ownership & Mutation-Position doctrine extends the already-registered
`managed_state_transitions.md` (no new required doc), the new non-negotiable rule landed in the three-way
`README.md` / `AGENTS.md` / `CLAUDE.md` mirror plus `assistant_workflow.md`, the missing cluster-lifecycle
Update Rule landed in `documentation_standards.md`, and the operator / test-harness / persistence docs were
reconciled to the doctrine. It has no cohort gate — the enforcing code is code-side closed (2026-07-23)
for the original Phase 2 Sprint 2.15 and Phase 6 Sprint 6.43 scope, whose single-accelerator
(apple-silicon) plus `linux-cpu` sign-off is historical [Wave X](cohort-validation-waves.md)
evidence. Wave X does not close the 2026-07-25 owner-atomic reservation/teardown correction. Phase
2's first 2026-07-26 Stage 1 and Apple attempt were rejected for closure. The later Apple retry
proved recovery/cleanup but exposed deterministic Linux `-Werror`; the CPP correction invalidates
that source identity. The later Bark footprint/test and registry-only Harbor verification
corrections passed final review and corrected-source Stage 1 for `d578…` / `a0d1…`, but attempt 4
rejected that freeze on Bark's 8192 MiB live-ceiling breach. The fp16 Bark correction is
implemented with focused checks GREEN; its pre-correction full validation is historical
GREEN-as-run only. The lifecycle replacement and nested-custody self-exec
anchor/supervisor/pin implementation are present, and the obsolete C/Cabal boundary is removed.
Focused runtime proof and fresh review/Stage 1 passed on 2026-07-27; both Wave Y lanes remain open.

Phase 0 was reopened (Sprints 0.11–0.12) for the realness governed-doc reconciliation and the
machine-independent realness lint enforcement, and is **re-closed** (validated 2026-06-23 by
`infernix lint docs` + `infernix docs check` + `infernix test lint`). Sprints 0.1-0.12 are Done.
The work was machine-independent and gated nothing on hardware; the doc reconciliation landed in
lockstep with the reopened Phase 4 catalog changes (matrix↔catalog parity), and the lint mechanism's
per-runner scope is extended by the reopened Phases 1 (Apple) and 4 (Linux) as each de-stubs.

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

### Remaining Work

None. Closed 2026-07-25 in the supported `linux-cpu` container context: `infernix lint docs` and
`infernix docs check` pass after registering the doctrine in `requiredDocs` with its required
structure; the deterministic plan scans report zero backward dependency edges and zero Validation
gates invoking both accelerator lanes; and the `AGENTS.md` / `CLAUDE.md` non-negotiable blocks are
byte-identical. No enforcing code belongs to this sprint.

---

## Sprint 0.18: No-Repo-Owned Native Source Doctrine [Done]

**Status**: Done — the rule, file-lint implementation, affected doctrine/workflow/plan truth,
all-Haskell correction, focused adversarial proof, final review, and complete source-matched
machine-independent correction gate passed on 2026-07-27. No pre-correction review, Stage 1, or
cohort result was reused.
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
- Phase 2 and Wave Y status that treats every pre-correction source/binary digest, review, Stage 1,
  and cohort assertion as historical GREEN-as-run evidence only
- deletion-ledger records for the removed lifecycle and subprocess C/FFI/Cabal boundaries, kept
  separate from the focused runtime and aggregate validation evidence that closed on 2026-07-27

### Validation

- `infernix lint docs`, `infernix docs check`, and `infernix lint files`
- root/workflow mirror checks
- the complete source-matched machine-independent correction gate after the all-Haskell
  implementation and focused adversarial suites pass

Closure evidence (2026-07-27):

- base revision: `6bad4af7ea3cca1c8d22f1ec968b4d95dd13a59d`
- pre-evidence tracked-plus-untracked worktree digest:
  `sha256:93a9c053bbe5d41feaba3c10fae8f55c9c42e2c566ebcacbc187747f6b87a4d9`
- installed Apple binary digest:
  `sha256:da62304fdec82bb5e2c1a8d3d0c3fc0fe66a9aa7c77c3d1023de8572a8095fcf`
- final adversarial reviews found no High or Medium findings
- focused lifecycle-lock and bounded-subprocess adversarial tests and
  `cabal test infernix-unit` passed
- `cabal build all` and the integration compile preflight passed
- `cabal test infernix-execution-plan-internal`, `cabal test infernix-compile-fail` with the
  5-positive/50-negative fixture inventory, `cabal test infernix-capped-engine-observer`, and
  `cabal test infernix-haskell-style` passed
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  passed
- the installed binary passed `lint files`, `lint docs`, `lint chart`, `lint proto`, and
  `docs check`
- Python `poetry --directory python run check-code`, the canonical web contract/build/unit gates
  with 83/83 unit tests, and `git diff --check` passed
- recomputing the tracked-plus-untracked digest after all gates produced the same
  `sha256:93a9c053bbe5d41feaba3c10fae8f55c9c42e2c566ebcacbc187747f6b87a4d9`
- subsequent evidence-only development-plan edits record that result without changing executable
  source

### Remaining Work

None. Phase 1 Sprint 1.20 is now Active. Phase 2 remains blocked by Phase 1 and retains its own
ordered phase review, validation, Apple, and `linux-cpu` closure requirements.

---

## Sprint 0.19: Bounded Host Memory Doctrine [Done]

**Status**: Done — the capacity-ledger doctrine, its lint registration, the governed-suite scope
corrections, and the three-way non-negotiable mirror landed on 2026-08-04. Machine-independent
(Axis-1 only); no accelerator gate.
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
inference. `minHostHeadroomMib` enumerates who the residual `headroom` covers — the OS, the
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

### Validation

- `infernix lint docs` passes with the new document registered, structured, and cross-linked, and
  `cabal build all` under `-Wall -Werror` accepts the `Lint/Docs.hs` registration
- `diff CLAUDE.md AGENTS.md` differs only at the title, `Supersedes`, `Purpose`, and intro lines, so
  the mirror remains byte-identical from the non-negotiable rules onward
- the governed suite contains no remaining claim that a host out-of-memory kill is structurally
  unrepresentable; the surviving honest statements in `typed_execution_plan.md` and `README.md` are
  preserved rather than rewritten

### Remaining Work

None in this sprint. The doctrine it establishes is implemented by Phase 1 Sprint 1.21 (the
build-memory kernel, the bounded runtime reservation, and the generated ceiling) and Phase 6
Sprint 6.46 (the toolchain spawn boundary, its lint, and the per-lane mechanism resolver). The
deferred ledger rows — the partition's missing build term, the unchecked sum of cluster pod limits
against node allocatable, and the uncapped nested builds — are named in the doctrine's
`Current Status` so they are not mistaken for closed.

---

## Sprint 0.20: Per-Machine Fleet Doctrine [Done]

**Status**: Done — the fleet doctrine, the delivery-semantics contract, the config-split doctrine,
the standards corrections, the phase renames, and the two docs-lint hardening fixes landed on
2026-08-05. Machine-independent (Axis-1 only); no accelerator gate.
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

### Remaining Work

None in this sprint. The implementation it governs is owned by Sprint 4.34 (admission on the
executing machine, fail-closed identity), Sprint 3.16 (the topology collapse), Sprint 6.47 (the
validation surface), and Sprints 8.10/8.11 (the wire).

---

## Sprint 0.21: Name The Co-Resident VM In The Host Memory Doctrine [Done]

**Status**: Done — re-closed 2026-08-08 after the doctrine correction and exact-source docs gate.
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

Measured on the development host, 2026-08-08: physical **65536 MiB**; generated
`cabal.project.local` grants `jobs: 8` x `-M4096M` = **32768 MiB**; `colima list` reports the default
profile Running with a **48 GiB** pledge. The `linux-cpu` lane executes *inside* that VM, so the two
lanes are not independent claimants on one host — they are nested.

### Deliverables

- The doctrine names a co-resident VM pledge as a claimant and records the historical defect: the
  Darwin toolchain account did not subtract it, oversubscribing the measured host.
- The current implementation uses one fixed-path, deadline-bounded Colima producer/parser for both
  accounts. Toolchain effective memory subtracts the conservatively observed active pledge; an
  unavailable, failed, malformed, or exhausting observation fails closed rather than becoming zero.

### Validation

The Sprint 0.21 `infernix lint docs` gate was GREEN with the metadata block intact. The subsequent
measurement correction is implemented under Phase 1 Sprint 1.21; this sprint owns the doctrine.

### Remaining Work

None. `documents/architecture/bounded_host_memory.md` names the nested VM pledge and the historical
missing intersection; Phase 1 Sprint 1.21 now implements the shared fixed-path observation and
subtraction for current source. No cohort gate applies to this doc-only sprint; Phase 1 retains the
Apple mechanism/cohort proof.

---

## Sprint 0.22: Complete Fleet Doctrine Reconciliation and Enforce Status-Free Governed Docs [Active]

**Status**: Active — formatter-stable source governed Apple rebuild GREEN for compile/install only;
aggregate lint GREEN; full unit RED before suites at Python provisioning; diagnose next.
**Implementation**: Landed across the governed prose inventory, `src/Infernix/Lint/Docs.hs`, and
focused semantic fixtures in `test/haskell-style/Spec.hs`.
**Docs to update**: SOURCE-STABLE landed inventory — `README.md`,
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

- **Landed; formatter-stable build GREEN, later gates pending:** root `README.md` HA cleanup
- **Landed; formatter-stable build GREEN, later gates pending:** timeless topology and recovery rewrites across
  daemon, demo, durable
  context, web, object storage/access, Pulsar, PostgreSQL, testing, and runbook surfaces
- **Landed; formatter-stable build GREEN, later gates pending:** removal of unsupported Patroni replica
  reinitialization while preserving
  the supported live startup-pod recycle path
- **Landed; formatter-stable build GREEN, later gates pending:** removal of implementation status, phasing, and
  checklist prose from the
  Pulsar workflow contract
- **Landed; formatter-stable build GREEN, later gates pending:** timeless bounded-inference-memory and
  bounded-host-memory rewrites
- **Landed; formatter-stable build GREEN, later gates pending:** direct-contract rewrites in `runtime_modes.md`,
  `model_catalog.md`, and
  `k8s_storage.md`
- **Landed; formatter-stable build GREEN, later gates pending:** the timeless `typed_execution_plan.md` rewrite,
  complete governed-doc
  semantic status inventory, `src/Infernix/Lint/Docs.hs` enforcement beyond the prior exact
  phrase/Sprint/Wave/date recognition, and focused semantic negative fixtures in
  `test/haskell-style/Spec.hs`
- **SOURCE-STABLE static evidence:** exact retired/status zero scans, the governed body mirror, and
  scoped `git diff --check` are clean. Independent settled-tree review is CLEAN with no High or
  Medium finding; it confirms the focused Haskell-style fixture is executable with correct path
  guards and that the safe controls preserve Failover, Shared, drain, single-instance, code,
  runtime, and pending semantics
- **Landed; formatter-stable build GREEN, later gates pending:** the plan, overview, README current-status index,
  and cohort current
  notices remain aligned while Phase 0 is Active and every code-writing phase is blocked by this
  sprint

### Validation

Recorded chronology and remaining exact order:

1. **GREEN — governed `./bootstrap/apple-silicon.sh build`:** after 5m54s claimant-free readiness
   following the end of the external Cabal owner, the overlap monitor pinned owned PID 53817 and
   observed zero external claimants through settlement and final scan. The command exited 0 with
   65536 MiB physical - 49152 MiB active Colima = 16384 MiB effective,
   `J1*H4096 + 2*C1024 = 6144 MiB`, and `GHCRTS` driver 1024 MiB; it produced the sdist,
   compiled all 114 GHC 9.12.4 library modules including new `Infernix.Lint.Docs` module 63, linked
   `Main`, installed/copied `.build/infernix`, and emitted the corrected operator/harness postamble
2. **RED — aggregate `./.build/infernix test lint`:** after the clean monitored readiness window
   17:15:56–17:21:18 = 5m22s, the monitor pinned owned PID 63879 and observed zero external claimant
   through settlement and final scan. The command exited 1 after rebuilding
   `Infernix.Lint.Docs` module 63 and CLI module 114, compiling/linking
   `test/haskell-style/Spec.hs`, and starting the test. The sole diagnostic was
   `haskell-style-check: Ormolu formatting differs:` followed by exactly
   `src/Infernix/Lint/Docs.hs`; Cabal reported 0/1 and `Error: [Cabal-7125]`. Fail-fast left
   HLint/readability, the isolated Cabal formatter, Python/Black, build-all, unit, and docs unrun
3. **CORRECTED SOURCE — governed linked-Ormolu diagnostic:** after the clean monitored readiness
   window 17:27:50–17:33:15 = 5m25s, the monitor pinned owned PID 68221 and found zero external
   claimant through final scan. One exact `./.build/infernix test lint` invocation exited 1
   intentionally after `user error (governed Ormolu apply completed idempotently for
   src/Infernix/Lint/Docs.hs)`. Only Haskell style compiled/linked/ran; the intentional stop preceded
   HLint/readability, the isolated formatter, Python, build-all, and later gates. Target prehash
   `fb929508...e4bd7` became formatted `396cac91...ce68`; linked output canonicalized equivalent
   `zipWith3 (,,)` to `zip3` and adjusted multiline pattern/comprehension layout; second apply was
   exact. The temporary checker was restored byte-for-byte at SHA-256 `880a2763...f37`; scoped diff
   check is clean. Independent formatter-delta review is CLEAN with no High or Medium finding:
   `zip3` is semantically identical here, tuple bindings and `where` scope are preserved, and
   fixture wiring and controls remain coherent
4. **GREEN — formatter-stable governed `./bootstrap/apple-silicon.sh build`:** the prerequisite
   window 17:39:56–17:45:11 was claimant-free for 5m15s. The monitor pinned owned bootstrap PID
   73643 from its start around 17:45:29 through settlement at 17:48:18–17:48:24, with zero external
   claimant through post-settlement and the independent final scan at 17:49:10. The command exited
   0 with 65536 - 49152 = 16384 MiB effective, `J1*H4096 + 2*C1024 = 6144 MiB`, and `GHCRTS`
   driver 1024 MiB; it produced the sdist, compiled all 114 GHC 9.12.4 library modules including
   formatted `Infernix.Lint.Docs` module 63, linked `Main`, installed/copied `.build/infernix`, and
   emitted the corrected postamble. This is compile/install evidence only
5. **RED — whole aggregate `./.build/infernix test lint`:** the prerequisite window
   17:53:05–17:58:18 was claimant-free for 5m13s. The monitor owned PID 84529 from about 17:58:30
   through 18:00:34, observed settlement by 18:00:39, and found zero external claimant through the
   final scan at 18:01:30. The command exited 1. Haskell style rebuilt `Infernix.Lint.Docs` module
   63 and `test/haskell-style`, emitted `haskell-style-check: ok`, and passed. The isolated Cabal
   3.16 formatter emitted `cabal-format-check: ok` and passed; its fixture warning was expected.
   The exact docs-policy failure was `user error (documents/README.md must declare the monitoring
   stance with the sentence: Monitoring is not a supported first-class surface.)`, with call stack
   `Docs.hs:1206:9`. Fail-fast left Python/Black, build-all, and later stages unrun
6. **SOURCE-STABLE — docs-only monitoring-stance correction:** `documents/README.md` used comma
   form `surface, and`, so the exact standalone validator sentence was absent. The sole change is
   `Monitoring is not a supported first-class surface. The governed docs suite has no canonical`
   plus the existing path line. Validator/Haskell bytes are unchanged. The exact sentence is now
   present in all five `monitoringStancePaths`; no `monitoring.md` or dormant stack exists; scoped
   document diff is clean. Independent final review is CLEAN with no High or Medium finding
7. **N/A — no rebuild warranted:** the correction is docs-only and Haskell is unchanged, so the
   formatter-stable governed build GREEN remains valid
8. **GREEN — whole aggregate `./.build/infernix test lint`:** after the 18:08:43–18:13:59
   prerequisite was claimant-free for 5m16s, the monitor owned PID 92170 from about 18:14:09 through
   18:21:27, observed settlement by 18:21:32, and found zero external claimant through final
   18:22:35. The command exited 0. Haskell style emitted `haskell-style-check: ok` and passed;
   isolated Cabal 3.16 emitted `cabal-format-check: ok` and passed with its expected fixture warning;
   Python checking succeeded for 8 source files; Black left all 8 unchanged; and `All checks passed!`
   was emitted. Final bounded build-all completed every declared component, linking integration
   116/116 and unit 117/117. This is style/policy/compile evidence only
9. **RED — full `./.build/infernix test unit`:** the 18:25:06–18:30:40 prerequisite was
   claimant-free for 5m34s. The monitor owned PID 1752 from about 18:30:50 through 18:31:25,
   observed settlement by 18:31:33, and found zero external claimant through final 18:32:42. The
   command exited 1 before any test suite with `bounded Python project provisioning failed` for
   `/Users/matthewnowak/infernix/python`. Kernel failure: `anchor terminal disagreed with anchor exit
   ExitFailure (-9); input InputCompleted; stdout CaptureCompleted "Installing dependencies from lock
   file\n\nNo dependencies to install or update\n\nInstalling the current project: infernix-adapters
   (0.1.0)\n"; stderr CaptureCompleted ""`; call stack `Python.hs:215:13`
10. `./.build/infernix lint docs`
11. `./.build/infernix docs check`
12. repo-wide `git diff --check`

No accelerator cohort belongs to this machine-independent governance sprint.

### Remaining Work

Diagnose the owned-kernel failure and residue, land a correction or evidence-based disposition, run
the governed rebuild and aggregate lint as any source change requires, then rerun full unit. Docs
lint, docs check, and repo-wide diff remain strictly later. Aggregate lint GREEN remains valid for
the current identity, but the unit gate is genuinely RED before suites and supplies no unit/runtime
GREEN. No accelerator cohort applies.
Do not resume Phase 1 or any later code-writing phase until Sprint 0.22 and Phase 0 are `Done`.

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
