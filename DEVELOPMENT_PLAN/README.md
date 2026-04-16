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
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript UI, Haskell-owned frontend contracts, and mode-driven manual inference workbench |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Unit, integration, Playwright E2E, per-mode matrix coverage, HA failure coverage, and lifecycle validation |
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

The repository has a governed `documents/` suite and a partial implementation tree. The
development plan now carries the updated product contract, but the governed docs suite still lags
parts of that direction.

- the README now makes the three runtime modes, comprehensive model or format or engine matrix,
  GPU-capable `linux-cuda` cluster behavior, generated mode-specific demo `.dhall`, ConfigMap-backed
  cluster publication, and per-mode exhaustive integration and E2E semantics first-class contract items
- the plan now reflects those same contract items, so Phase 0 stays active through explicit
  follow-on work to finish realigning the governed docs suite and docs-validation coverage
- later phases retain partial implementation, but phase closure remains blocked on that Phase 0
  realignment before more current-state closure claims are credible

## Execution Contexts and Runtime Modes

The plan uses two separate concepts and keeps them distinct:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Runtime mode | `apple-silicon`, `linux-cpu`, `linux-cuda` | which engine column from the README matrix governs the generated demo catalog, service runtime, and test coverage |

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Active | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Blocked | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Blocked | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Blocked | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Blocked | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Blocked | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Blocked | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |

Blocked in this table means phase closure is gated by the open Phase 0 docs-alignment work, not
that no implementation exists in the repository.

## Canonical Outcome

At closure, `infernix` is constructed around these non-negotiable rules:

- one repo-owned Haskell executable named `infernix`, used for service runtime, tests, and Kind lifecycle
- one governed `documents/` suite that stays aligned with the plan and the updated root README
- one Kind-backed deployment path using Helm, including GPU-enabled Kind behavior for `linux-cuda`
- one mandatory local HA topology: 3x Harbor and Pulsar replicas plus 4x MinIO replicas, with hard pod anti-affinity suppressed for Kind scheduling
- one manual local persistence doctrine rooted at `./.data/`
- one repo-owned `cabal.project` that encodes the default host-native Cabal build doctrine under
  `./.build/`, with explicit `/opt/build/infernix` overrides for container and Dockerfile Cabal
  invocations
- one reverse-proxied localhost edge port exposing the UI, API, Harbor, MinIO, and Pulsar browser surfaces
- one PureScript web application deployed as a cluster service in all supported modes
- three supported runtime modes: `apple-silicon`, `linux-cpu`, and `linux-cuda`
- one comprehensive model or format or engine matrix whose mode columns select the engine binding
  for each runtime mode
- one generated mode-specific demo `.dhall` catalog per runtime mode, staged ephemerally during
  `cluster up` and published into `ConfigMap/infernix-demo-config` for cluster-resident consumers
- one repo-owned `.proto` contract for durable runtime manifests and Pulsar topic payloads, with
  `proto-lens`-generated Haskell bindings and Pulsar built-in protobuf schema support
- one edge-port selection rule that tries `9090` first, increments by 1 until open, records the
  chosen port under `./.data/runtime/edge-port.json`, and prints it during `cluster up`
- one Haskell static-quality gate using `fourmolu`, `cabal-fmt`, `hlint`, and strict compiler warnings
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
