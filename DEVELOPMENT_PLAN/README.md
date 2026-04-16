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
| [00-overview.md](00-overview.md) | Architecture baseline, hard constraints, and canonical repository shape |
| [system-components.md](system-components.md) | Authoritative component inventory and state-location map |
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite creation, documentation standards, and doc-validation governance |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, single-binary CLI, and host or container operator modes |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Helm lifecycle, and Harbor-backed image flow |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA Harbor, MinIO, Pulsar, unified edge routing, and cluster-resident webapp service |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell service runtime, model contracts, and durable artifact lifecycle |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript UI, Haskell-owned frontend contracts, and manual inference workbench |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Unit, integration, Playwright E2E, HA failure coverage, and lifecycle validation |
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

This repository is defined by an authoritative `DEVELOPMENT_PLAN/`, with implementation beginning
only after the governed documentation suite is in place. Under the documentation-first rule,
Phase 0 is the only phase currently `Planned`; every code-writing phase remains `Blocked` until
Phase 0 closes.

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Planned | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Blocked | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Blocked | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Blocked | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Blocked | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Blocked | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Blocked | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |

## Canonical Outcome

At closure, `infernix` is constructed around these non-negotiable rules:

- one repo-owned Haskell executable named `infernix`, used for service runtime, tests, and Kind lifecycle
- one governed `documents/` suite written before any code-writing phase begins
- one Kind-backed deployment path using Helm
- one mandatory local HA topology: 3x Harbor and Pulsar replicas plus 4x MinIO replicas, with hard pod anti-affinity suppressed for Kind scheduling
- one manual local persistence doctrine rooted at `./.data/`
- one repo-owned `cabal.project` that encodes the default host-native Cabal build doctrine under
  `./.build/`, with explicit `/opt/build/infernix` overrides for container and Dockerfile Cabal
  invocations
- one reverse-proxied localhost edge port exposing the UI, API, Harbor, MinIO, and Pulsar browser surfaces
- one PureScript web application deployed as a cluster service in all supported modes
- one Haskell static-quality gate using `fourmolu`, `cabal-fmt`, `hlint`, and strict compiler warnings
- one README that stays an orientation document rather than the primary home of deep architecture rules

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes the governed documents suite and documentation standards before code writing |
| 1 | 0 | repository and CLI work begins only after the docs phase closes |
| 2 | 0-1 | cluster lifecycle depends on the documented repo shape and CLI contract |
| 3 | 0-2 | stateful services and edge routing depend on documented storage and cluster doctrine plus the implemented cluster substrate |
| 4 | 0-3 | service runtime depends on the documented and implemented platform substrate |
| 5 | 0-4 | UI and shared contracts depend on the documented and implemented service API |
| 6 | 0-5 | validation depends on the completed service and web surfaces plus their governed docs |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
