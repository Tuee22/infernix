# Infernix Development Plan

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md)

> **Purpose**: Provide the single execution-ordered development plan for `infernix`, including
> phase status, repository-shape decisions, validation gates, and documentation obligations.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Maintenance rules for the development plan |
| [00-overview.md](00-overview.md) | Architecture baseline, hard constraints, runtime-mode contract, and canonical repository shape |
| [system-components.md](system-components.md) | Authoritative component inventory and state-location map |
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite creation, documentation standards, and docs-suite alignment with the three-mode matrix |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, single-binary CLI, Cabal build doctrine and container artifact isolation, execution-context contract, and runtime-mode selection baseline |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Helm lifecycle, Harbor-backed image flow, GPU-enabled `linux-cuda` cluster reconcile, and mode-aware ConfigMap-backed demo-config generation |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA Harbor, MinIO, Pulsar, unified edge routing, and mode-stable browser and API publication |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell service runtime, comprehensive matrix registry, protobuf manifest and Pulsar payload contracts, ConfigMap-backed generated demo `.dhall`, and durable artifact lifecycle |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | Browser workbench target, Haskell-owned frontend contracts, and mode-driven manual inference UI |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Unit, integration, routed Playwright coverage, per-mode matrix coverage, HA failure coverage, and lifecycle validation |
| [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) | Explicit cleanup and removal ledger |

## Status Vocabulary

| Status | Meaning |
|--------|---------|
| `Done` | Implemented, validated, docs aligned, no remaining work |
| `Active` | Partially implemented; remaining work is explicit |
| `Blocked` | Waiting on named prerequisites |
| `Planned` | Not started yet, but dependencies are already satisfied |

## Definition of Done

A phase or sprint can move to `Done` only when all of the following are true:

1. The deliverables exist in the repository worktree.
2. The listed validation gates pass on the supported execution path or matrix.
3. The future governed docs named in `Docs to update` have been created or updated to match the implementation.
4. No `Remaining Work` section remains open.
5. Cleanup promised by the sprint is reflected in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Current Repo Assessment

The repository has a governed `documents/` suite and a materially broader final-substrate
implementation than the plan previously recorded.

- Phase 0 documentation realignment is closed: the governed docs now distinguish execution context
  from runtime mode, document `infernix-demo-<mode>.dhall`, `ConfigMap/infernix-demo-config`,
  `/opt/build/`, `9090`-first edge-port selection, and active-mode exhaustive validation, and the
  docs validator enforces those phrases directly
- the current implementation now includes explicit runtime-mode selection, a comprehensive
  README-matrix-backed catalog registry, mode-specific generated demo-config staging, a real
  ConfigMap publication plus repo-local inspection mirror, a Haskell-owned service launcher that
  selects the active demo-config source before delegating routed HTTP handling to
  `tools/service_server.py`, publication state plus a routed `/api/publication` surface,
  build-root-isolated frontend contract staging, Apple host prerequisite detection for repo-owned
  Python manifests, the repo-owned `./cabalw` host build wrapper, repo-owned `ormolu` or `hlint`
  or `cabal format` checks, Harbor-first image publication, GPU-enabled `linux-cuda` Kind
  reconciliation, node-reachable Kind registry mirror configuration for Harbor-backed pulls, a
  repo-built bootstrap registry for pre-Harbor MinIO and Pulsar image pulls, and a host-native
  Kind bootstrap path that no longer depends on Kind's brittle boot-log wait; `infernix test
  lint`, `infernix test unit`, `infernix test integration`, and `infernix test e2e` now pass
  again on the supported host-native and outer-container validation lanes, including the default
  runtime-mode matrix
- `compose.yaml` and `docker/infernix.Dockerfile` now close the documented outer-container
  compatibility launcher, while `web/Dockerfile`, `chart/`, `kind/`, and `proto/` now back the
  validated Kind or Helm or Harbor or MinIO or Pulsar substrate on the Apple host-native lane
- the web build now stages generated JavaScript contract output under the active build root
  (`./.build/web-generated/` on the host, `/opt/build/infernix/web-generated/` in the
  outer-container path) before copying the runtime asset into `web/dist/` through atomic staging,
  so tracked-path frontend contract artifact isolation is closed and concurrent web builds no
  longer expose partial `dist/` output
- the host-native final-substrate lane now also reuses the Harbor-published web runtime image
  across `apple-silicon`, `linux-cpu`, and `linux-cuda`, and the remaining compatibility
  distinctions are intentional current-state contracts rather than open phase work

## Execution Contexts and Runtime Modes

The plan uses two separate concepts and keeps them distinct:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Runtime mode | `apple-silicon`, `linux-cpu`, `linux-cuda` | which engine column from the README matrix governs the generated demo catalog, service runtime, and test coverage |

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Done | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Done | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Done | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Done | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Done | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Done | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Done | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |

## Canonical Outcome

At closure, `infernix` is constructed around these non-negotiable rules:

- one repo-owned Haskell executable named `infernix`, used for service runtime, tests, and Kind lifecycle
- one governed `documents/` suite that stays aligned with the plan and the updated root README
- one Kind-backed deployment path using Helm, including GPU-enabled Kind behavior for `linux-cuda`
- one mandatory local HA topology: 3x Harbor and Pulsar replicas plus 4x MinIO replicas, with hard pod anti-affinity suppressed for Kind scheduling
- one manual local persistence doctrine rooted at `./.data/`
- one repo-owned build-artifact doctrine that keeps host-native Cabal output under `./.build/`,
  through the repo-owned `./cabalw` wrapper and `./.build/infernix` materialization, with
  explicit `/opt/build/infernix` overrides for container and Dockerfile Cabal invocations
- one reverse-proxied localhost edge port exposing the UI, API, Harbor, MinIO, and Pulsar browser surfaces
- one repo-owned web application deployed as a cluster service in all supported modes
- three supported runtime modes: `apple-silicon`, `linux-cpu`, and `linux-cuda`
- one comprehensive model or format or engine matrix whose mode columns select the engine binding
  for each runtime mode
- one generated mode-specific demo `.dhall` catalog per runtime mode, staged ephemerally during
  `cluster up` and published into `ConfigMap/infernix-demo-config` for cluster-resident consumers
- one repo-owned `.proto` contract for durable runtime manifests and Pulsar topic payloads, with
  `proto-lens`-generated Haskell bindings and Pulsar built-in protobuf schema support
- one edge-port selection rule that tries `9090` first, increments by 1 until open, records the
  chosen port under `./.data/runtime/edge-port.json`, and prints it during `cluster up`
- one canonical static-quality gate surfaced as `infernix test lint`, using repo-owned lint, docs,
  and strict compiler-warning checks until a richer formatter or linter stack is actually adopted
- one integration and E2E contract that exercises every generated catalog entry for the active mode
  rather than a hand-picked subset

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes and realigns the governed docs suite before phase closure claims continue |
| 1 | 0 | repository and CLI work can continue to close only after docs capture the runtime-mode direction correctly |
| 2 | 0-1 | cluster lifecycle depends on the documented repo shape, CLI contract, ConfigMap-backed demo-config contract, and GPU-capable `linux-cuda` Kind rules |
| 3 | 0-2 | stateful services and edge routing depend on documented storage and cluster doctrine plus the implemented cluster substrate |
| 4 | 0-3 | service runtime depends on the documented and implemented platform substrate plus the mode-matrix and ConfigMap publication contract |
| 5 | 0-4 | UI and shared contracts depend on the documented and implemented service API and generated demo catalog |
| 6 | 0-5 | validation depends on the completed service and web surfaces plus their governed docs and mode-aware catalog contract |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
