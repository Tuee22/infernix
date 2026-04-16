# Phase 6: Validation, E2E, and HA Hardening

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported static-quality and test matrix for the single-binary CLI, the
> service runtime, the PureScript UI, the per-mode generated demo catalog, and the mandatory HA
> behavior of Harbor, MinIO, and Pulsar.

## Current Repo Assessment

The repository already has lint, unit, integration, and Playwright entrypoints. The missing closure
work is that integration and E2E still need to scale from baseline smoke coverage to the README's
stated active-mode exhaustive coverage contract.

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

## Mode-Matrix Validation Contract

This phase owns the rule that validation follows the generated demo catalog for the active runtime mode.

- `test unit` proves matrix typing, generated catalog rendering, and contract generation logic
- `test integration` exercises every generated catalog entry for the active runtime mode
- `test e2e` drives the browser against every demo-visible generated catalog entry for the active runtime mode
- in containerized execution contexts, the engine binding asserted by integration and E2E comes
  from the ConfigMap-backed mounted `.dhall` under `/opt/build/`, which in turn must match the
  appropriate mode column in the README matrix
- full repository closure requires repeating active-mode validation across `apple-silicon`,
  `linux-cpu`, and `linux-cuda`

## Sprint 6.1: Haskell Static Quality Gates and Extensive Unit Suites [Active]

**Status**: Active
**Implementation**: `src/Infernix/CLI.hs`, `tools/lint_check.py`, `test/unit/Spec.hs`, `web/test/contracts.test.mjs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/reference/cli_reference.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the single-binary control
plane, shared contracts, and matrix-rendering logic.

### Deliverables

- `infernix test lint` as the canonical static-quality entrypoint for repo-owned Haskell code
- `fourmolu --mode check` validation for repo-owned Haskell source
- `cabal-fmt --check` validation for `.cabal` and `cabal.project` files
- `hlint` validation for repo-owned Haskell modules
- strict compiler-warning validation with warnings treated as errors on supported paths
- Haskell unit and property coverage for CLI parsing, storage reconciliation, route selection, model catalog logic, generated demo-config rendering, and service domain types
- Haskell unit coverage for repo-owned protobuf manifest and Pulsar payload schemas through the
  generated `proto-lens` bindings
- PureScript `purescript-spec` coverage for build-generated contracts and view logic
- `infernix test unit` as the canonical unit-suite entrypoint

### Validation

- `infernix test lint` passes when formatting, lint, and compiler-warning policy are satisfied
- formatting drift, HLint regressions, or warning regressions fail `infernix test lint`
- `infernix test unit` runs both Haskell and PureScript unit suites
- breaking a route contract, storage rule, generated shared type, or generated-demo-config rule causes a unit failure
- breaking a protobuf manifest or Pulsar payload schema round-trip causes a unit failure
- unit tests run without requiring a fully reconciled Kind cluster unless a specific unit fixture explicitly needs one

### Remaining Work

- swap the current repo-owned lint compatibility gate for the planned external formatter and linter stack once toolchain support lands
- deepen Haskell unit coverage around lifecycle, storage, and matrix-rendering edge cases

---

## Sprint 6.2: Extensive Integration Suites [Active]

**Status**: Active
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Exercise the real Kind, Helm, Harbor, MinIO, Pulsar, generated demo-config, and service integration path.

### Deliverables

- integration coverage for `cluster up` reconciliation, embedded storage reconciliation, automatic image mirroring and publication, mandatory HA replica topology, anti-affinity-suppressed chart scheduling, service deploy, model listing, and inference request execution
- integration coverage for Apple host-mode connectivity to edge-routed MinIO and Pulsar
- integration coverage for cluster-resident service mode on the Linux-supported path
- integration coverage that the active mode's generated demo `.dhall` is published into
  `ConfigMap/infernix-demo-config`, mounted at `/opt/build/` for cluster-resident consumers, and
  consumed by later runtime flows
- integration coverage that durable runtime manifests round-trip through repo-owned protobuf schemas
  and that Pulsar topics use protobuf schema registration rather than opaque payloads
- dedicated `linux-cuda` integration coverage proves the GPU-enabled Kind path exposes
  `nvidia.com/gpu` resources and schedules CUDA-bound workloads with the correct runtime metadata

### Validation

- `infernix test integration` reconciles or reuses the supported cluster prerequisites
- integration tests prove the manual PV doctrine in practice
- integration tests fail when automatic Harbor image preparation, replica counts, anti-affinity
  suppression, MinIO access, Pulsar access, ConfigMap-backed generated-demo-config production, or
  GPU runtime exposure regress

### Remaining Work

- replace file-existence-only checks with real per-entry integration assertions
- expand integration coverage from baseline cluster and API smoke checks to full active-mode catalog coverage
- validate Linux CPU and Linux CUDA runtime lanes separately rather than treating them as one generic cluster path
- add protobuf schema inspection and manifest round-trip assertions to the final integration suite

---

## Sprint 6.3: Playwright E2E From the Web Image [Active]

**Status**: Active
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

### Remaining Work

- validate E2E execution from the final Harbor-published web image rather than only local scaffolding
- expand browser coverage from one smoke flow to every active-mode demo-catalog entry
- assert engine-binding and catalog content against the ConfigMap-backed mounted mode-specific `.dhall`

---

## Sprint 6.4: HA Failure and Recovery Coverage For Harbor, MinIO, and Pulsar [Blocked]

**Status**: Blocked
**Blocked by**: `1.1-1.5`, `2.1-2.6`, `3.1-3.6`, `4.1-4.6`, `5.1-5.6`
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

### Remaining Work

- implement HA failure coverage on the final HA substrate
- wire those assertions into the canonical integration surface or a documented HA subset

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
- coverage that `cluster up` auto-generates the active runtime mode's demo `.dhall`, publishes the
  ConfigMap, and mounts it at `/opt/build/` in containerized execution contexts
- coverage that `cluster up` tries `9090` first, increments by 1 until open, records the chosen
  port, and prints it to the user during bring-up
- validation that the chosen edge port is rediscovered correctly after restart

### Validation

- Apple host-native lifecycle commands via `./.build/infernix` pass on the supported path
- Linux outer-container lifecycle commands pass on the supported path
- the generated demo `.dhall` and published ConfigMap content are correct for the active runtime
  mode on both execution contexts
- lifecycle validation proves `cluster up` selects `9090` when available and otherwise reports the
  next open port
- restarting the cluster preserves durable state and repopulates the edge-port record correctly

### Remaining Work

- add the outer-container matrix lane
- re-run the lifecycle matrix against the final Kind-backed implementation once it replaces the current compatibility layer
- report runtime mode, generated-demo-config publication details, watched mount path, and chosen
  edge port consistently in lifecycle validation output

---

## Sprint 6.6: Per-Mode Exhaustive Integration and E2E Coverage [Blocked]

**Status**: Blocked
**Blocked by**: `0.5`, `2.6`, `4.6`, `5.6`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`

### Objective

Make the README promise concrete: for the active runtime mode, integration and browser validation
cover every generated catalog entry using the engine binding selected for that mode.

### Deliverables

- `infernix test integration` loads the active `infernix-demo-<mode>.dhall` from the generated
  staging output or the mounted `ConfigMap/infernix-demo-config` and enumerates every generated
  catalog entry
- `infernix test e2e` drives the browser against every demo-visible entry from that same generated
  catalog source
- integration and E2E assertions use the engine binding encoded in the generated `.dhall`, which
  must match the corresponding runtime-mode column from the README matrix
- `linux-cuda` exhaustive coverage also asserts the selected entries run on the GPU-enabled Kind
  substrate with the expected CUDA runtime metadata
- test reports identify the runtime mode, matrix-row id, model or workload id, and selected engine for each exercised entry
- `infernix test all` for a runtime mode aggregates lint, unit, integration, and E2E without silently dropping generated catalog entries

### Validation

- changing the active runtime mode changes the exercised catalog and engine assertions automatically
- integration or E2E fails if any generated catalog entry for the active mode is skipped
- integration or E2E fails if an entry's selected engine disagrees with the generated `.dhall`, the
  mounted ConfigMap content, or the README matrix contract
- Apple, Linux CPU, and Linux CUDA lanes all pass their own active-mode exhaustive suites before the full matrix is considered closed

### Remaining Work

- implement generated-catalog enumeration in integration and E2E layers
- close exhaustive active-mode coverage across Apple, Linux CPU, and Linux CUDA lanes
- wire failure reporting so omitted entries are obvious and actionable

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/development/testing_strategy.md` - unit, integration, E2E, environment matrix, and active-mode exhaustive coverage
- `documents/development/haskell_style.md` - formatter, lint, and compiler-warning policy
- `documents/development/chaos_testing.md` - HA failure and recovery coverage
- `documents/operations/cluster_bootstrap_runbook.md` - test prerequisites and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations and active-mode catalog behavior

**Cross-references to add:**
- keep [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) aligned when HA claims, route assumptions, or active-mode validation rules change
