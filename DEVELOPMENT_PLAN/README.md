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
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, two-binary CLI surface, Cabal build doctrine and container artifact isolation, execution-context contract, and runtime-mode selection baseline |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine and explicit PV-to-PVC binding for every PVC-backed Helm workload, Harbor bootstrap-first and post-bootstrap Harbor-backed image flow, GPU-enabled `linux-cuda` cluster reconcile, and mode-aware ConfigMap-backed demo-config generation |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA Harbor, MinIO, operator-managed Patroni PostgreSQL, Pulsar, unified edge routing, and mode-stable browser and API publication |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell Pulsar-driven production inference service, Python engine-adapter contract under `python/adapters/`, comprehensive matrix registry, protobuf manifest and Pulsar payload contracts, ConfigMap-backed generated demo `.dhall`, and durable artifact lifecycle |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI built with spago, `purescript-spec` test framework, Haskell-owned frontend contracts via `purescript-bridge`, and mode-driven demo workbench served by `infernix-demo` |
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
3. The governed docs named in `Docs to update` have been created or updated to match the implementation.
4. No `Remaining Work` section remains open.
5. Cleanup promised by the sprint is reflected in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Current Repo Assessment

The repository has a governed `documents/` suite and a closed cluster-substrate baseline. The new
doctrine declared in [00-overview.md](00-overview.md) (two-binary topology, Pulsar-only production
inference surface, demo HTTP only via `infernix-demo`, Python restricted to engine adapters under
`python/adapters/`, frontend in PureScript with types from Haskell via `purescript-bridge`) is
being landed across phases 1, 3, 4, and 5.

- the cluster substrate, Kind or Helm assets, Harbor-first bootstrap flow, manual storage doctrine,
  operator-managed Patroni PostgreSQL contract, and `linux-cuda` GPU lane are implemented and
  doctrine-aligned; their phase (Phase 2) is `Blocked` only because lifecycle code still calls
  custom-logic Python tooling that Phase 1 Sprint 1.6 retires
- the repository now ships `infernix` plus `infernix-demo`, broader CLI wrapper entrypoints for
  edge or gateway or lint or internal flows, a repo-root `python/` scaffold, and a placeholder
  `spago` tree under `web/`; the production inference surface (Pulsar subscription via
  `infernix service`), the Haskell demo HTTP host, the Haskell edge proxy and platform gateways,
  the `purescript-bridge` integration, the canonical `spago test` path, and the strict Python
  adapter quality gate in `infernix test lint` are still not fully implemented, and the previous
  Python-served HTTP surface, JavaScript workbench, and custom-logic `tools/*.py` scripts remain
  on disk and are tracked for removal in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- the `documents/` tree, root README, AGENTS, and CLAUDE are now aligned with the retired-doctrine
  removals from Phase 0; the remaining open work is implementation migration rather than docs-suite
  realignment

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
| 1 | Repository and Control-Plane Foundation | Active | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Blocked | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Blocked | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Blocked | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Blocked | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Blocked | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |

## Canonical Outcome

The current supported platform is constructed around these non-negotiable rules:

- two repo-owned Haskell executables sharing one Cabal library `infernix-lib`: `infernix` for the
  production daemon, cluster lifecycle, edge proxy, gateway pods, Pulsar inference dispatcher,
  static-quality gate, and internal helpers; and `infernix-demo` for the demo UI HTTP host gated by
  the active `.dhall` `demo_ui` flag
- production deployments accept inference work by Pulsar subscription only; the production
  `infernix service` binds no HTTP listener and the cluster has no `infernix-demo` workload when the
  demo flag is off
- Python is restricted to `python/adapters/<engine>/` (Poetry-managed; mypy strict, black check,
  and ruff strict run in every adapter container build); all custom platform logic is Haskell
- the demo UI is PureScript built with spago, tested with `purescript-spec`, and consumes
  PureScript modules generated from Haskell ADTs in `src/Infernix/Demo/Api.hs` via
  `purescript-bridge`
- one governed `documents/` suite that stays aligned with the plan and the updated root README
- one Kind-backed deployment path using Helm, including GPU-enabled Kind behavior for `linux-cuda`
- one Harbor-first cluster bootstrap that deploys Harbor first on a pristine cluster, lets Harbor
  plus only Harbor-required backend services such as MinIO and PostgreSQL pull from public
  container repositories until Harbor is ready, then requires every remaining cluster workload to
  pull from Harbor
- one mandatory local HA topology: 3x Harbor and Pulsar replicas plus 4x MinIO replicas, with
  hard pod anti-affinity suppressed for Kind scheduling, and operator-managed Patroni PostgreSQL
  clusters for every in-cluster PostgreSQL need
- one manual local persistence doctrine rooted at `./.data/`, with explicit PV-to-PVC binding for
  every PVC-backed Helm workload including operator-managed PostgreSQL claims
- one repo-owned build-artifact doctrine that keeps host-native Cabal output under `./.build/`,
  through direct `cabal --builddir=.build/cabal ...` host installs and `./.build/infernix` plus
  `./.build/infernix-demo` materialization, with explicit `/opt/build/infernix` runtime build roots
  on the outer-container path and no repo-owned scripts or wrapper layers
- one reverse-proxied localhost edge port exposing the demo UI, demo API, Harbor, MinIO, and Pulsar
  browser surfaces; the demo routes are absent when the demo surface is disabled
- the edge proxy and platform gateways are Haskell modules in `infernix-lib`, deployed as separate
  cluster workloads using the same OCI image with `infernix edge` or `infernix gateway <kind>` as
  entrypoint
- three supported runtime modes: `apple-silicon`, `linux-cpu`, and `linux-cuda`
- one comprehensive model or format or engine matrix whose mode columns select the engine binding
  for each runtime mode
- one generated mode-specific demo `.dhall` catalog per runtime mode, staged ephemerally during
  `cluster up` and published into `ConfigMap/infernix-demo-config` for cluster-resident consumers;
  the same `.dhall` carries the Pulsar `request_topics`, `result_topic`, and `engines` fields used
  by the production daemon
- one repo-owned `.proto` contract for durable runtime manifests and Pulsar topic payloads, with
  `proto-lens`-generated Haskell bindings, Python `protobuf`-generated bindings under
  `python/adapters/`, and Pulsar built-in protobuf schema support
- one edge-port selection rule that tries `9090` first, increments by 1 until open, records the
  chosen port under `./.data/runtime/edge-port.json`, and prints it during `cluster up`
- one canonical static-quality gate surfaced as `infernix test lint`, including the strict Python
  quality gate (mypy, black, ruff) for `python/adapters/`
- one integration and E2E contract that exercises every generated catalog entry for the active mode
  rather than a hand-picked subset

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes and realigns the governed docs suite before phase closure claims continue |
| 1 | 0 | repository and CLI work can continue to close only after docs capture the runtime-mode direction correctly |
| 2 | 0-1 | cluster lifecycle depends on the documented repo shape, CLI contract, ConfigMap-backed demo-config contract, and GPU-capable `linux-cuda` Kind rules |
| 3 | 0-2 | stateful services, operator-managed PostgreSQL, and edge routing depend on documented storage and cluster doctrine plus the implemented cluster substrate |
| 4 | 0-3 | service runtime depends on the documented and implemented platform substrate plus the mode-matrix and ConfigMap publication contract |
| 5 | 0-4 | UI and shared contracts depend on the documented and implemented service API and generated demo catalog |
| 6 | 0-5 | validation depends on the completed service and web surfaces plus their governed docs and mode-aware catalog contract |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
