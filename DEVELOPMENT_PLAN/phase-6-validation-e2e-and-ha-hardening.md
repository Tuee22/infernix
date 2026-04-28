# Phase 6: Validation, E2E, and HA Hardening

**Status**: Blocked
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported static-quality and test matrix for the two-binary topology,
> the Pulsar-driven production inference surface, the demo UI host, the per-mode generated
> catalog, and the mandatory HA behavior of Harbor, MinIO, operator-managed PostgreSQL, and Pulsar.

## Phase Status

Sprints 6.1, 6.2, 6.3, 6.4, 6.5, and 6.7 are `Done`. Sprint 6.6 is now `Blocked`: the exhaustive
active-mode integration enumeration and the Harbor, MinIO, Pulsar, and PostgreSQL HA or lifecycle
assertions now pass on the fresh `linux-cpu` outer-container rerun from April 28, 2026, while the
supported `linux-cuda` rerun from April 28, 2026 is blocked later by host disk exhaustion during
the real Harbor-backed cluster rollout.

## Current Repo Assessment

The repository already has lint, unit, integration, and Playwright entrypoints. The canonical
testing, boundary, portability, and Haskell-style docs are landed, and the baked Linux substrate
image now carries the tracked-source snapshot manifest needed for git-less `infernix lint files`
runs. The baked `linux-cpu` substrate image now also proves routed Playwright plus the real
Gateway and Pulsar surfaces. The routed Playwright suite exhaustively exercises every demo-visible
generated catalog entry, and the integration suite now enumerates every generated active-mode
catalog entry while also carrying the real-cluster Harbor, MinIO, Pulsar, and Harbor PostgreSQL
recovery or lifecycle checks. The fresh outer-container `linux-cpu` rerun passed on April 28,
2026. The supported `linux-cuda` rerun from April 28, 2026 passes Haskell style, Haskell unit,
and PureScript unit, creates the real cluster, publishes Harbor-backed images, and reaches Helm
rollout, but low host disk headroom leaves BookKeeper ledger directories non-writable and blocks
`infernix-service` readiness.

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

## Sprint 6.6: Per-Mode Exhaustive Integration and E2E Coverage [Blocked]

**Status**: Blocked
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/Files.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`
**Blocked by**: supported NVIDIA host with enough free disk headroom for Harbor publication and Pulsar BookKeeper durability
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

- `test/integration/Spec.hs` now enumerates every generated active-mode catalog entry, and the
  git-less Linux image path now keeps `infernix lint files` scoped to the baked source snapshot
- the remaining supported-lane validation gap is the supported `linux-cuda` rerun: on April 28,
  2026 it passes Haskell style, Haskell unit, and PureScript unit before real cluster creation,
  Harbor-backed image publication, and Helm rollout, then stalls because low host disk headroom
  makes BookKeeper non-writable and prevents `infernix-service` readiness

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

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/testing.md` - canonical testing doctrine, preflight expectations, and unsupported paths
- `documents/development/testing_strategy.md` - operator workflow, matrix selection, and test-entrypoint details
- `documents/development/haskell_style.md` - hard gates, review guidance, enforcement model, and fail-fast rule
- `documents/development/chaos_testing.md` - HA failure and recovery coverage
- `documents/engineering/implementation_boundaries.md` - ownership boundaries that validation enforces
- `documents/engineering/portability.md` - portable invariants versus substrate-specific detail
- `documents/engineering/storage_and_state.md` - owner or durability table and cleanup rules
- `documents/engineering/monitoring.md` - required if monitoring remains a first-class supported surface
- `documents/operations/cluster_bootstrap_runbook.md` - test prerequisites and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations
- `documents/tools/postgresql.md` - PostgreSQL operator readiness and failover rules

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations and active-mode catalog behavior

**Cross-references to add:**
- keep [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
  aligned when HA claims, route assumptions, or active-mode validation rules change
