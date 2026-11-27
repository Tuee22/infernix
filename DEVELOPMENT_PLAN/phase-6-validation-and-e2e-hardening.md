# Phase 6: Validation, E2E, and Hardening

**Status**: Done — Sprint 6.55 closed on `linux-gpu` plus native `linux-cpu` ([attestation](cohort-validation-waves.md#recorded-attestations)).

**Referenced by**: [README.md](README.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md),
[../documents/development/no_env_vars.md](../documents/development/no_env_vars.md)

> **Purpose**: Define the supported static-quality and single-substrate validation contract for the
> one-binary role topology, the README-matrix-driven integration suite, the Pulsar-driven production
> inference surface, the demo UI host, the substrate-generated catalog, the mandatory HA behavior
> of the registry, MinIO, operator-managed PostgreSQL, and Pulsar, and the repository-hardening plus
> false-negative-doctrine closure that keeps governed root docs,
> route-aware docs, and the CLI surface mechanically aligned with implementation.

## Phase Status

Sprints 6.1–6.54 retain their closed headings and only their established scope. Sprint 6.55 puts every fixture child under an owner that terminates, reaps once, and closes its pipes on return, failure, readiness timeout, and cancellation, and exercises that contract on the CPU lane with controlled children. The outer launcher does not itself request GPU access, so its exit code alone cannot establish GPU behavioral sign-off.

The existing Phase 6 row in [Recorded Attestations](cohort-validation-waves.md#recorded-attestations) is retained for the source and assertions it records; it does not close these new criteria.

Implementation follows the named code-side prerequisites below; pending accelerator scheduling alone does not block subsequent implementation. The engine-log selector and GPU framework budget require code-side revalidation. The selected sign-off is `linux-gpu` plus native `linux-cpu`, recorded in Wave R6 in [cohort-validation-waves.md](cohort-validation-waves.md), against one frozen implementation. Both lanes have now validated these criteria; see the Phase 6 row in Recorded Attestations.

## Current Repo Assessment

The lint, unit, integration, and browser entrypoints exist. Sprint 6.55 owns required-check accounting, actual CUDA execution in the supported engine workload, fixture cleanup, and results. Existing Phase 6 evidence is scope-limited and does not prove checks that were skipped or assertions that only accepted a refusal. Kernel prevention, sampled breach, engine failure, and missing result require distinct evidence.

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

## Current Validation Baseline

- `test unit` proves matrix typing, generated catalog rendering, and contract-generation logic
- supported `test lint` and `test unit` commands still require the initialized repo-root runtime
  config for command-level execution-context validation, while their assertions remain static or unit scoped
  and do not claim real-cluster matrix coverage
- `test integration` validates the active substrate's published catalog contract, routed surfaces,
  routed inference execution for every generated active-substrate catalog entry, and the
  service-loop roundtrip through the routed Pulsar transport; on Apple it brackets the
  same-binary host daemon and waits for the service readiness marker before publishing
- `test e2e` exercises every demo-visible generated catalog entry for the active substrate
- `test all` runs every supported validation layer for the active built substrate and reports that
  substrate instead of implying cross-substrate coverage
- `test integration`, `test e2e`, and `test all` own cluster lifecycle around each test phase:
  the supported entrypoint runs `cluster down` first, executes the test action, and runs
  `cluster down` again unconditionally afterwards so reruns start from a clean cluster state
  without depending on prior operator setup

## Sprint 6.1: Static Quality Gates, Testing Doctrine, and Unit Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Files.hs`, `test/haskell-style/Spec.hs`, `test/unit/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`, `documents/engineering/storage_and_state.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the control plane, shared
contracts, and generated-catalog logic, and put the validation doctrine in canonical docs.

### Deliverables

- `infernix test lint` is the canonical static-quality entrypoint
- the repo-owned lint layer enforces whitespace, newline, tab, docs, chart, proto, and tracked-file
  policy; mounted-source Linux container runs invoke Git with a scoped
  `safe.directory=/workspace` setting so file lint validates the bind-mounted repo without global
  Git state
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
- Haskell formatting or lint drift fails `cabal test infernix-haskell-style`
- `infernix test unit` runs both Haskell and frontend unit suites
- docs validation fails if canonical testing or boundary docs drift from the supported implementation

### Remaining Work

None. Wave R6 closed: `linux-gpu` full suite `run-9xWddG` and native-amd64 `linux-cpu` full suite `run-lxzVpV` both exited 0 against one frozen implementation, including the required real-output rows, Demucs/Torch/SoundFile provisioning on the CPU lane, and the NVIDIA validation stage on the GPU lane.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - root-document metadata contract and canonical-home markers
- `documents/engineering/build_artifacts.md` - generated-artifact locations, build-root rules, and derived-output validation expectations
- `documents/engineering/apple_silicon_metal_headless_builds.md` - validation gates for the Tart-free Apple materialization lane
- `documents/engineering/dependency_management.md` - Cabal dependency posture for the pinned
  Haskell toolchain and the Dhall dependency closure
- `documents/engineering/edge_routing.md` - route-registry ownership, generated route summaries, and route-aware validation expectations
- `documents/engineering/testing.md` - canonical testing doctrine, core principles, preflight expectations, unsupported paths, and per-layer validation obligations
- `documents/development/testing_strategy.md` - operator workflow, matrix selection, and test-entrypoint details
- `documents/development/haskell_style.md` - hard gates, review guidance, direct enforcement-model pointer, repo-hard-gate versus editor-only guidance split, and fail-fast rule
- `documents/development/assistant_workflow.md` - canonical repository-level assistant workflow doctrine for governed root entry docs
- `documents/engineering/implementation_boundaries.md` - ownership matrix, adapter-local versus shared-contract types, instance placement, and module-boundary rules
- `documents/engineering/portability.md` - portable invariants, permanent substrate limits, and validation boundaries; implementation status stays in this plan
- `documents/engineering/storage_and_state.md` - owner or durability table, failure-mode rules, and cleanup contracts
- `documents/architecture/runtime_modes.md` - daemon-role split, derived engine-pool handoff, and host-role `.dhall` fields
- `documents/architecture/engine_pool_routing.md` - invalid-state validation, shared-pool
  backpressure, pinned-route exclusivity, and production-shape expectations
- `documents/engineering/model_lifecycle.md` - batch ownership, request handoff, and result-publication runtime contract
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) - managed state-transition doctrine (typed evidence per state, unexported destructive primitives, evidence-returning readiness waits) referenced by Sprint 6.39
- no `documents/engineering/monitoring.md` exists while monitoring remains unsupported; create it
  only if monitoring becomes a supported first-class surface in a later change
- `documents/operations/cluster_bootstrap_runbook.md` - lifecycle warning classification, test
  prerequisites, and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations and cold-start lifecycle timing doctrine
- `documents/tools/postgresql.md` - PostgreSQL operator readiness and single-instance restart/restore rules
- `documents/tools/pulsar.md` - request, batch, and result topic ownership for cluster and host daemons
- `documents/engineering/docker_policy.md` - native Apple Docker boundary, minimal Linux host
  prerequisites, and buildx expectations for nested Compose builds
- `documents/development/purescript_policy.md` - PureScript npm deprecation-warning ownership,
  compiler acquisition constraints, and Spago transitive-dependency constraints
- `documents/development/python_policy.md` - Poetry bootstrap boundary for Apple hosts and the
  Linux substrate image-local Poetry virtual-environment layout

**Product or reference docs to create/update:**
- `README.md` - orientation layer with governed root-document metadata and canonical-home links
- `AGENTS.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `CLAUDE.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/cli_surface.md` - short command-family overview that links to the canonical CLI reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations and active-substrate catalog behavior
- `documents/reference/api_surface.md` - publication metadata that distinguishes cluster daemon and inference executor location

**Cross-references to add:**
- keep the frozen [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
  unchanged; ongoing governance requirements live in the standards and owning follow-on work
- keep [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  aligned when command-registry ownership, shared workflow-helper closure, or CLI-reference
  derivation rules change
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when runtime-honesty wording or README-matrix interpretation changes
- keep [phase-3-platform-services-and-edge-routing.md](phase-3-platform-services-and-edge-routing.md)
  aligned when route assumptions, single-instance recovery, or active-substrate validation rules change
- keep [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
  aligned when lifecycle progress surfaces or long-running convergence doctrine changes
- keep [system-components.md](system-components.md) aligned when testing-doctrine ownership,
  shared-helper closure, daemon-role topology, or the supported monitoring stance changes
- keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when any pending
  route-doc, route-lint, assistant-doc, workflow-helper, testing-doc, runtime-language, or
  monitoring-surface or compatibility-shim cleanup item closes

**Remediation documentation obligations:**

- Keep the contracts named by Sprints 6.55 prescriptive in `documents/`; implementation state and validation evidence stay in this plan.
- Document positive behavior, explicit refusal/unsupported behavior, resource and trust boundaries, and the independent controls that establish each claim.
- Keep [README.md](README.md), [cohort-validation-waves.md](cohort-validation-waves.md), and [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned with actual outstanding work; delete removal rows only after the named implementation surface is gone.
