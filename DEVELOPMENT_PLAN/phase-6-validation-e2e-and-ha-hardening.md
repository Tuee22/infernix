# Phase 6: Validation, E2E, and HA Hardening

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported static-quality and test matrix for the single-binary CLI, the
> service runtime, the PureScript UI, and the mandatory HA behavior of Harbor, MinIO, and Pulsar.

## Validation Surface

The supported validation entrypoints are:

- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`

These commands are declarative and idempotent validation entrypoints. Re-running them rechecks the
same contract and may reconcile supported prerequisites instead of depending on alternate
imperative setup commands. `infernix test all` is the aggregate entrypoint for lint, unit,
integration, and E2E coverage. All additional helper commands are subordinate to these entrypoints.

## Sprint 6.1: Haskell Static Quality Gates and Extensive Unit Suites [Active]

**Status**: Active
**Implementation**: `src/Infernix/CLI.hs`, `tools/lint_check.py`, `test/unit/Spec.hs`, `web/test/contracts.test.mjs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/reference/cli_reference.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the single-binary control
plane and shared contracts.

### Deliverables

- `infernix test lint` as the canonical static-quality entrypoint for repo-owned Haskell code
- `fourmolu --mode check` validation for repo-owned Haskell source
- `cabal-fmt --check` validation for `.cabal` and `cabal.project` files
- `hlint` validation for repo-owned Haskell modules
- strict compiler-warning validation with warnings treated as errors on supported paths
- Haskell unit and property coverage for CLI parsing, storage reconciliation, route selection, model catalog logic, and service domain types
- PureScript `purescript-spec` coverage for build-generated contracts and view logic
- `infernix test unit` as the canonical unit-suite entrypoint

### Validation

- `infernix test lint` passes when formatting, lint, and compiler-warning policy are satisfied
- formatting drift, HLint regressions, or warning regressions fail `infernix test lint`
- `infernix test unit` runs both Haskell and PureScript unit suites
- breaking a route contract, storage rule, or build-generated shared type causes a unit failure
- unit tests run without requiring a fully reconciled Kind cluster unless a specific unit fixture explicitly needs one

### Remaining Work

- swap the current repo-owned lint compatibility gate for the planned external formatter and linter stack once toolchain support lands
- deepen Haskell unit coverage around lifecycle and storage edge cases

---

## Sprint 6.2: Extensive Integration Suites [Done]

**Status**: Done
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Exercise the real Kind, Helm, Harbor, MinIO, Pulsar, and service integration path.

### Deliverables

- integration coverage for `cluster up` reconciliation, embedded storage reconciliation, automatic image mirroring and publication, mandatory HA replica topology, anti-affinity-suppressed chart scheduling, service deploy, model listing, and inference request execution
- integration coverage for Apple host-mode connectivity to edge-routed MinIO and Pulsar
- integration coverage for cluster-resident service mode on the Linux-supported path

### Validation

- `infernix test integration` reconciles or reuses the supported cluster prerequisites
- integration tests prove the manual PV doctrine in practice
- integration tests fail when automatic Harbor image preparation, replica counts, anti-affinity
  suppression, MinIO access, or Pulsar access regress

---

## Sprint 6.3: Playwright E2E From the Web Image [Done]

**Status**: Done
**Implementation**: `web/playwright.config.js`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`

### Objective

Run browser validation only from the same image that serves the UI.

### Deliverables

- Playwright suites live under `web/playwright/` or an equivalent UI-owned path
- `infernix test e2e` runs the suite from the web image
- E2E covers the routed UI, model selection, manual inference submission, and result rendering

### Validation

- `infernix test e2e` launches Chromium, WebKit, and Firefox from the web image
- browser tests hit the routed cluster path rather than bypassing the edge
- no supported workflow depends on host-installed Playwright or host browser binaries

---

## Sprint 6.4: HA Failure and Recovery Coverage For Harbor, MinIO, and Pulsar [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.4`, `2.1-2.5`, `3.1-3.5`, `4.1-4.5`, `5.1-5.5`
**Docs to update**: `documents/development/chaos_testing.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Back the HA claims with concrete failure coverage.

### Deliverables

- pod-deletion and rolling-restart coverage for Harbor application-plane workloads
- durability and failover coverage for MinIO on the supported mandatory HA topology
- message continuity and restart coverage for Pulsar on the supported mandatory HA topology
- clear test assertions for what survives and what is expected to reset

### Validation

- `infernix test integration` or a dedicated HA subset proves single-pod failure does not permanently break the supported path
- data written before a MinIO or Pulsar pod restart remains available afterward
- Harbor-backed image pulls continue to work after supported Harbor application-pod replacement

---

## Sprint 6.5: Cluster Lifecycle and Environment-Matrix Validation [Active]

**Status**: Active
**Implementation**: `src/Infernix/Cluster.hs`, `.build/infernix`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Verify the same product contract across Apple host-native and Linux outer-container workflows.

### Deliverables

- matrix coverage for Apple host-native `infernix` and Linux outer-container `infernix`
- lifecycle coverage for `cluster up`, `cluster status`, `cluster down`, and repeat `cluster up`
- coverage that `cluster up` auto-generates the test Dhall config and enables all mode-appropriate models for validation
- validation that the chosen edge port is rediscovered correctly after restart

### Validation

- Apple host-native lifecycle commands via `./.build/infernix` pass on the supported path
- Linux outer-container lifecycle commands pass on the supported path
- the generated test Dhall config is correct for the active mode on both execution contexts
- restarting the cluster preserves durable state and repopulates the edge-port record correctly

### Remaining Work

- add the outer-container matrix lane
- re-run the lifecycle matrix against the final Kind-backed implementation once it replaces the current compatibility layer

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/development/testing_strategy.md` - unit, integration, E2E, and environment matrix
- `documents/development/haskell_style.md` - formatter, lint, and compiler-warning policy
- `documents/development/chaos_testing.md` - HA failure and recovery coverage
- `documents/operations/cluster_bootstrap_runbook.md` - test prerequisites and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations

**Cross-references to add:**
- keep [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) aligned when HA claims or route assumptions change
