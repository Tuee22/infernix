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
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite bootstrap and documentation-governance baseline |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, CLI contract, generated-artifact hygiene, parser-driven command registry, governed root-doc ownership, and outer-container launcher cleanup |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Harbor-first image flow, generated values material, and `linux-cuda` lifecycle closure |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and route-registry-driven HTTPRoute rendering |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, shared Linux substrate image, Apple host-native engine bootstrap, protobuf contracts, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, generated-path cleanup for browser contracts, and Playwright ownership on final execution paths |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, testing doctrine, exhaustive integration and E2E coverage, portability or boundary docs, and HA validation |
| [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) | Explicit cleanup and removal ledger |

## Status Vocabulary

| Status | Meaning |
|--------|---------|
| `Done` | Implemented, validated, docs aligned, no remaining work |
| `Active` | Partially implemented; remaining work is explicit |
| `Blocked` | Waiting on named prerequisites |
| `Planned` | Ready to start; dependencies are already satisfied |

## Definition of Done

A phase or sprint can move to `Done` only when all of the following are true:

1. The listed implementation paths exist in the current worktree.
2. The listed validation gates pass on the supported execution path or matrix.
3. The governed docs named in `Docs to update` match the implementation.
4. No remaining cleanup or compatibility surface is left unstated.
5. Cleanup promised by the sprint is reflected in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Current Repo Assessment

Phase 0 is closed. Phase 1 is now closed as well, and the major DRY-cleanup work has landed in the
current worktree: the shared Python project, the shared Linux substrate Dockerfile, the route
registry, the command registry, the browser-contract move, the snapshot launcher, and the docs
doctrine refresh are all present. Real-cluster Gateway acceptance, the routed Pulsar roundtrip,
and image-owned Playwright are now proven on the `linux-cpu` outer-container lane. The supported
`linux-cuda` rerun from April 28, 2026 now reaches real cluster creation, Harbor-backed image
publication, and Helm rollout, but low host disk headroom on that NVIDIA host leaves Pulsar
BookKeeper ledger directories non-writable and prevents `infernix-service` readiness.

The remaining open work is now the true platform work:

- deeper engine-library integration beyond the current durable-metadata-aware shared adapter
  contract
- the full Apple host-native engine bootstrap
- final supported-lane validation for `linux-cuda`, which now specifically needs a supported
  NVIDIA host with enough free disk headroom for Kind image preload, Harbor publication, and
  Pulsar or BookKeeper convergence before the remaining Linux substrate work can close

## Execution Contexts and Runtime Modes

The plan keeps these concepts separate:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Runtime mode | `apple-silicon`, `linux-cpu`, `linux-cuda` | which README matrix column selects the active engine bindings and generated demo catalog |

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Done | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Done | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Blocked | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Done | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Active | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Done | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Blocked | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |

## Canonical Outcome

The supported platform closes around these rules:

- two repo-owned Haskell executables share one Cabal library `infernix-lib`: `infernix` for the
  production daemon, cluster lifecycle, validation, and internal helpers; `infernix-demo` for the
  demo HTTP host
- one parser-driven Haskell command registry owns argument dispatch, help text, and the canonical
  CLI reference document; supporting docs summarize and link instead of copying command inventories
- Apple Silicon is the only host-native inference lane; `linux-cpu` and `linux-cuda` are the two
  containerized Linux runtime lanes; the plan no longer pretends Apple has container parity at the
  inference boundary
- the Linux image story closes through one shared `docker/linux-substrate.Dockerfile` that builds
  `infernix-linux-cpu` and `infernix-linux-cuda`; `docker/linux-base.Dockerfile` is retired
- the Linux outer-container launcher uses an image-snapshot model: rebuild the image when the repo
  changes, then run `docker compose run --rm infernix infernix ...`; the container bind-mounts
  only `./.data/` and uses named volumes for `/opt/build` and `/root/.cabal`
- Python is restricted to one shared Poetry project rooted at `python/pyproject.toml` and one
  shared adapter tree under `python/adapters/`; all adapter execution runs through `poetry run`
  and the canonical Python quality gate is `poetry run check-code`
- Haskell owns the handwritten browser-contract types in `src/Infernix/Web/Contracts.hs`; only
  generated outputs live under `web/src/Generated/`
- one Haskell-owned route registry drives the Envoy Gateway route inventory, publication state,
  Helm HTTPRoute rendering, chart lint expectations, and route-oriented docs
- `chart/values.yaml` holds stable structural defaults only; generated demo-config and publication
  payloads are deployment inputs rendered during reconcile or lint, not committed copies
- one Kind-backed cluster path owns Harbor-first bootstrap, operator-managed Patroni PostgreSQL for
  every in-cluster PostgreSQL dependency, manual `infernix-manual` storage, and Gateway API routing
- production inference is Pulsar-only; the demo UI is optional and absent when the generated
  `.dhall` disables it
- integration and E2E coverage enumerate the active runtime mode's generated demo catalog without
  silently narrowing coverage
- root guidance becomes thinner and more canonical: `README.md` remains orientation, `documents/`
  holds one canonical home per topic, and `AGENTS.md` or `CLAUDE.md` stay aligned entry documents

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes and realigns the governed docs suite before code-phase closure claims continue |
| 1 | 0 | repository and CLI cleanup depend on governed docs and the canonical plan vocabulary |
| 2 | 0-1 | cluster lifecycle depends on the repo shape, launcher contract, and generated-artifact doctrine |
| 3 | 0-2 | HA services and edge routing depend on the settled cluster substrate and generated deployment inputs |
| 4 | 0-3 | service runtime depends on the platform substrate, route contract, and generated config publication |
| 5 | 0-4 | UI and generated frontend contracts depend on the service API and runtime catalog |
| 6 | 0-5 | validation depends on the completed service and UI surfaces plus their owned docs and runtime matrix contract |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
