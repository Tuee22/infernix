# Phase 6: Validation, E2E, and HA Hardening

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported static-quality and test matrix for the single-binary CLI, the
> service runtime, the browser workbench, the per-mode generated demo catalog, and the mandatory HA
> behavior of Harbor, MinIO, and Pulsar.

## Current Repo Assessment

The repository already has lint, unit, integration, and Playwright entrypoints. Those surfaces
remain the canonical validation contract across the supported host-native and outer-container
control-plane lanes, and they now validate the process-isolated engine-worker adapter contract plus
durable runtime artifact bundles and direct-upstream source-artifact manifests, with the repo-owned
default engine probe path exercised whenever no adapter-specific override is configured. The default validation matrix now
auto-includes `linux-cuda` only when the active control-plane surface passes the NVIDIA preflight contract, but
final closure still requires those same suites to validate supported-host final engine workers and
the supported-host GPU matrix, including a supported NVIDIA host that satisfies the worker-device
volume-mount preflight required by the Kind-backed CUDA lane.

- `infernix test lint` and `infernix test unit` are the canonical host-side static-quality and
  unit gates
- `infernix test integration` and `infernix test e2e` exercise `apple-silicon`, `linux-cpu`, and
  automatically include `linux-cuda` when no explicit runtime-mode override is supplied and the
  active control-plane surface passes the NVIDIA preflight contract
- the routed Playwright path waits for routed publication, demo-config, and inference readiness
  before it launches the browser suite
- final closure remains open until those same suites run against real runtime workers and a real
  NVIDIA-backed `linux-cuda` substrate

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
- `test e2e` exercises every demo-visible generated catalog entry for the active runtime mode
- in containerized execution contexts, the engine binding asserted by integration and E2E comes
  from the ConfigMap-backed mounted `.dhall` under `/opt/build/`, which in turn must match the
  appropriate mode column in the README matrix
- full repository closure requires repeating active-mode validation across `apple-silicon`,
  `linux-cpu`, and `linux-cuda`

## Sprint 6.1: Haskell Static Quality Gates and Extensive Unit Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `tools/lint_check.py`, `tools/haskell_style_check.py`, `test/unit/Spec.hs`, `web/test/contracts.test.mjs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/reference/cli_reference.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the single-binary control
plane, shared contracts, and matrix-rendering logic.

### Deliverables

- `infernix test lint` as the canonical static-quality entrypoint for repo-owned Haskell code
- the current repo-owned lint layer enforces whitespace, newline, and tab discipline for tracked sources
- `infernix test lint` also validates the repo-owned chart, Kind, and `.proto` asset inventory
- `infernix docs check` remains part of the canonical static-quality gate
- the repo-owned Haskell style stack bootstraps `ormolu` and `hlint` binaries under
  `./.build/haskell-style-tools/` and checks `infernix.cabal` with `cabal format`
- strict compiler-warning validation with warnings treated as errors on supported paths
- Haskell unit coverage for runtime-mode resolution, model catalog logic, generated demo-config
  rendering, invalid generated-catalog startup handling, and service domain types
- frontend unit coverage for build-generated contracts, catalog rendering, and view logic
- `infernix test unit` as the canonical unit-suite entrypoint

### Validation

- `infernix test lint` passes when the repo-owned lint, docs, and compiler-warning policy are satisfied
- removing a required chart, Kind, or `.proto` asset fails `infernix test lint`
- Haskell formatting or lint drift fails `python3 tools/haskell_style_check.py` and therefore
  fails `infernix test lint`
- trailing whitespace, tab characters, missing trailing newlines, docs regressions, or warning regressions fail `infernix test lint`
- `infernix test unit` runs both Haskell and frontend unit suites
- breaking generated shared types, generated catalog counts, representative catalog membership, or
  invalid demo-config startup handling causes a unit failure
- unit tests run without requiring a fully reconciled Kind cluster unless a specific unit fixture explicitly needs one

### Remaining Work

None.

---

## Sprint 6.2: Extensive Integration Suites [Active]

**Status**: Active
**Implementation**: `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`, `tools/runtime_backend.py`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Exercise the generated demo-config and service integration path, and carry that coverage
forward onto the final Kind, Helm, Harbor, MinIO, and Pulsar substrate.

### Deliverables

- integration coverage for `cluster up` reconciliation, repo-local kubeconfig and publication
  artifact creation, generated demo-config publication, and per-entry inference request execution
- the Haskell integration suite also proves the routed Harbor, MinIO, and Pulsar gateway
  surfaces resolve through the cluster-resident edge topology while browser-interaction coverage
  remains owned by Phase 6.3 Playwright
- integration coverage enumerates every generated catalog entry for the active runtime mode
- integration coverage that the active mode's generated demo `.dhall` is published into
  `ConfigMap/infernix-demo-config` and mirrored byte-for-byte through the repo-local publication mirror
- integration coverage that publication state is written for routed consumers
- host-native integration coverage proves the routed API can move to the Apple host bridge without
  changing the browser-visible edge entrypoint
- dedicated `linux-cuda` integration coverage proves NVIDIA device-plugin rollout, positive
  `nvidia.com/gpu` allocatable resources, `RuntimeClass/nvidia`, GPU requests, and
  `nvidia-smi -L` visibility from the service deployment on the Kind-backed CUDA lane

### Validation

- `infernix test integration` reconciles or reuses the supported cluster prerequisites
- integration tests prove per-entry catalog execution, generated-demo-config publication, Pulsar
  protobuf schema inspection, MinIO result or manifest persistence, and Harbor or MinIO or Pulsar
  HA recovery on the Apple host-native final substrate
- integration tests fail when publication state no longer records the active runtime mode and routed API publication
- integration tests fail when generated catalog publication, per-entry inference execution,
  persisted-result durability, schema publication, HA recovery, or CUDA scheduling assertions regress

### Remaining Work

- replace the current fixture-command adapter assertions with validations against supported-host
  final engine workers, the final engine-ready direct-upstream artifact contract, and durable
  runtime state
- rerun the `linux-cuda` coverage on a supported NVIDIA-backed Kind substrate so this sprint closes
  with supported-host validation rather than host-gated implementation only
- keep the current Harbor, MinIO, and Pulsar HA assertions while extending runtime execution
  checks beyond the current repo-owned worker layer

---

## Sprint 6.3: Routed Playwright E2E Coverage [Done]

**Status**: Done
**Implementation**: `web/playwright.config.js`, `web/playwright/inference.spec.js`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`

### Objective

Keep routed Playwright validation under the web-owned test surface while exercising the built web
image and the Harbor-published host-native runtime image.

### Deliverables

- Playwright suites live under `web/playwright/` or an equivalent UI-owned path
- `infernix test e2e` exercises the routed surface through Playwright-owned HTTP coverage and
  browser UI interaction coverage launched from the built web image
- the host-native final-substrate path reuses the Harbor-published web image across
  `apple-silicon`, `linux-cpu`, and `linux-cuda`
- E2E covers the routed UI contract, model selection, manual inference submission, and result rendering

### Validation

- `infernix test e2e` hits the routed path rather than bypassing the edge
- the routed Playwright suite fails if any active-mode catalog entry is skipped
- the routed Playwright suite fails if the browser workbench cannot render publication details,
  select a model, submit a request, or render an object-reference result state
- the host-native routed suite also fails if `/api` cannot move to the Apple host
  bridge while the browser stays on the same edge base URL
- `./.build/infernix --runtime-mode apple-silicon test e2e` launches Chromium, WebKit, and Firefox from the built web image without depending on host-installed Playwright or host browser binaries
- `./.build/infernix --runtime-mode linux-cpu test e2e` and
  `./.build/infernix --runtime-mode linux-cuda test e2e` do the same while reusing the
  Harbor-published web runtime image on the host-native final substrate
- `docker compose run --rm infernix infernix --runtime-mode apple-silicon test e2e` does the same without requiring those browsers in the outer control-plane image

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
- durability and failover coverage for MinIO on the supported mandatory HA topology
- message continuity and restart coverage for Pulsar on the supported mandatory HA topology
- clear test assertions for what survives and what is expected to reset

### Validation

- `infernix test integration` or a dedicated HA subset proves single-pod failure does not permanently break the supported path
- data written before a MinIO or Pulsar pod restart remains available afterward
- Harbor-backed image pulls continue to work after supported Harbor application-pod replacement

### Remaining Work

None.

---

## Sprint 6.5: Cluster Lifecycle and Environment-Matrix Validation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `compose.yaml`, `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-cuda.yaml`, `test/integration/Spec.hs`, `web/playwright.config.js`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Verify the same product contract across Apple host-native and Linux outer-container workflows.

### Deliverables

- the codebase exposes `cluster up`, `cluster status`, and `cluster down` through both the
  Apple host-native and Linux outer-container launcher surfaces
- current automated coverage proves `cluster up` creates the repo-local kubeconfig, generated demo
  `.dhall`, repo-local ConfigMap publication mirror, and publication state for the active runtime mode
- `cluster status` reports the active runtime mode, build-root or data-root paths, generated
  demo-config publication details, chosen edge port, publication state path, and cache or object
  inventory from repo-local state without mutation
- the same lifecycle closes the host-native and outer-container Kind-backed matrix validation
  contract
- on the Linux outer-container lane, cluster-backed validation keeps host-published Kind API and
  routed edge ports on `127.0.0.1` while the launcher joins the private Docker `kind` network and
  uses the repo-local kubeconfig produced from `kind get kubeconfig --internal`

### Validation

- `infernix test integration` proves the host-native lane creates the generated demo
  `.dhall`, published ConfigMap mirror, repo-local kubeconfig, and publication state for the active
  runtime mode
- `python3 tools/platform_asset_check.py` plus a clean outer-container Kind probe prove the
  loopback-only host-bind contract, the internal-kubeconfig control-plane endpoint, and the
  private `kind` network access path on the Linux outer-container lane
- `cluster status` code prints the runtime mode, build or data roots, demo-config publication
  details, chosen edge port, publication state path, and cache or object inventory without mutating
  cluster state
- current validation also proves repeated `cluster up` or `cluster down` behavior and `9090`-first
  edge-port rediscovery on both control-plane execution contexts

### Remaining Work

None.

---

## Sprint 6.6: Per-Mode Exhaustive Integration and E2E Coverage [Active]

**Status**: Active
**Implementation**: `src/Infernix/CLI.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/contracts.test.mjs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`

### Objective

Make the README promise concrete: for the active runtime mode, integration and routed Playwright
validation cover every generated catalog entry using the engine binding selected for that mode.

### Deliverables

- `infernix test integration` enumerates every active-mode catalog entry from the serialized
  generated demo config after `cluster up`, separately checks that the generated and published
  demo-config bytes match, and preserves selected-engine metadata end-to-end
- `infernix test e2e` exercises every demo-visible entry from the routed `/api/models` surface,
  cross-checks that routed catalog against the serialized generated demo config reported through
  `/api/publication`, and pairs that exhaustive HTTP coverage with browser UI interaction coverage
- the default validation matrix runs those exhaustive integration and E2E paths across
  `apple-silicon` and `linux-cpu` by default and auto-includes `linux-cuda` when no explicit
  runtime-mode override is supplied and the active control-plane surface passes the NVIDIA
  preflight contract
- `linux-cuda` exhaustive coverage asserts the generated catalog, routed publication state, and
  GPU-backed service deployment stay aligned on the Kind-backed CUDA lane
- `infernix test all` for a runtime mode aggregates lint, unit, integration, and E2E without silently dropping generated catalog entries

### Validation

- changing the active runtime mode changes the exercised catalog and engine assertions automatically
- integration or E2E fails if any generated catalog entry for the active mode is skipped
- the default validation coverage fails if publication or selected-engine metadata regress on the
  routed catalog surfaces it consumes
- the default validation coverage passes Apple and Linux CPU exhaustive suites and auto-includes
  Linux CUDA against the generated serialized catalogs when no explicit runtime-mode override is
  supplied on a host whose active control-plane surface satisfies the NVIDIA preflight contract
- the host-native final-substrate routed E2E path also passes Apple, Linux CPU, and Linux CUDA
  exhaustive suites against the Harbor-backed generated serialized catalogs

### Remaining Work

- keep exhaustive catalog enumeration while replacing the current fixture-command adapter
  assertions with checks against supported-host final engine execution and the final engine-ready
  direct-upstream artifact behavior
- rerun the default matrix against a supported `linux-cuda` substrate that exposes actual NVIDIA
  runtime support, usable GPU resources, and the worker-device volume-mount preflight that
  `nvkind` depends on
- close the Harbor-backed host-native routed E2E lane on top of the final runtime workers rather
  than the current repo-owned worker layer

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
