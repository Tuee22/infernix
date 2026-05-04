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
| [00-overview.md](00-overview.md) | Architecture baseline, hard constraints, substrate contract, and canonical repository shape |
| [system-components.md](system-components.md) | Authoritative component inventory and state-location map |
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite bootstrap plus the reopened substrate-doctrine documentation reset |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, CLI contract, build-root doctrine, launcher ownership, and substrate-selection closure |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Harbor-first image flow, substrate `.dhall` publication, and Linux launcher closure |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and cluster-resident demo routing |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, substrate-owned daemon placement, reloadable `.dhall` control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, and Playwright ownership |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, README-matrix-driven single-substrate validation, root-doc closure, and HA validation |
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

The repository now implements the substrate-file doctrine described by this plan. Supported flows
stage one `infernix-substrate.dhall` beside the active build root through explicit
`infernix internal materialize-substrate ...` helpers: Apple operators run
`./.build/infernix internal materialize-substrate apple-silicon`, and Linux substrate images stage
`/opt/build/infernix/infernix-substrate.dhall` during Docker build with
`infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`. Supported
runtime, cluster, and validation entrypoints fail fast if the staged file is absent instead of
falling back to host detection or `INFERNIX_SUBSTRATE_ID`. Cluster publication mirrors the exact
payload locally under `./.data/runtime/configmaps/infernix-demo-config/infernix-substrate.dhall`
and mounts that same filename in cluster workloads at
`/opt/build/infernix/infernix-substrate.dhall`. The file keeps the legacy `.dhall` filename even
though the payload is banner-prefixed JSON. Validation already reports only the active built
substrate instead of implying a default cross-substrate matrix, and the generated file,
`cluster status`, publication JSON, and generated browser contracts still serialize that active
substrate under `runtimeMode` field names. The supported Linux outer-container validation stack
rerun now passes component-by-component: `infernix lint docs`, the Haskell and PureScript unit
suites, `infernix test integration`, and `infernix test e2e` all passed, so the reopened plan
items are closed.

Monitoring is not a supported first-class surface.

## Execution Contexts and Substrates

The plan keeps these concepts separate:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Supported substrate | `apple-silicon`, `linux-cpu`, `linux-gpu` | which staged `infernix-substrate.dhall` payload the active build root carries |

### Naming Note

The canonical NVIDIA-backed Linux substrate id is `linux-gpu`, and the implementation plus docs
now use that id consistently.

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

The supported platform now closes around these rules:

- two repo-owned Haskell executables still share one Cabal library `infernix-lib`: `infernix` for
  the production daemon, cluster lifecycle, validation, and internal helpers; `infernix-demo` for
  the routed demo HTTP host
- one structured Haskell command registry owns parsing, help text, and the canonical CLI
  reference, but it no longer exposes `--runtime-mode` or any equivalent substrate override
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from the staged `infernix-substrate.dhall` file beside the active
  build root, and that staged payload is the primary source of truth for substrate identity,
  generated catalog content, daemon placement, and test scope
- Apple host-native workflows stage or restage `./.build/infernix-substrate.dhall` explicitly with
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
- Linux substrate images stage `/opt/build/infernix/infernix-substrate.dhall` during image build
  with `infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
- supported runtime, cluster, and validation entrypoints fail fast if the staged substrate file is
  absent instead of regenerating it on first command execution or falling back to env or host
  detection
- the staged substrate file retains the legacy `.dhall` filename even though the current payload is
  banner-prefixed JSON produced by Haskell runtime helpers
- Apple host-native operation is the only supported host build path outside a container
- on Apple Silicon, the host-built `./.build/infernix` binary manages Kind, deploys the clustered
  demo workloads, and still owns the direct host-side `infernix service` lane; the routed demo and
  Playwright paths do not manage a separate host daemon in the current code path
- on Apple Silicon, Compose is not a user-facing launcher for ordinary CLI work; the host CLI may
  still invoke a direct `docker run` of the Playwright-capable Linux substrate image internally
  for routed Playwright E2E
- on Linux substrates, all supported CLI commands run through
  `docker compose run --rm infernix infernix ...`; there is no supported Linux host-native build or
  CLI surface outside the outer container
- `linux-cpu` is the only substrate that remains meaningfully portable across unrelated host
  hardware; Apple operators may exercise it through Colima's amd64 VM, and arm64 Linux is treated
  as a first-class CPU-only host shape
- `linux-gpu` assumes an amd64 Linux environment paired with a CUDA-capable device, but the outer
  control-plane container itself does not require the NVIDIA runtime
- for `linux-gpu`, the outer control-plane image is still built from the CUDA base image, and that
  same built image is the artifact pushed to Harbor and deployed as the cluster daemon
- the staged substrate file lives under the active build root:
  `./.build/infernix-substrate.dhall` on Apple and `/opt/build/infernix/infernix-substrate.dhall`
  in the outer container; Linux cluster deployment republishes that payload through
  `ConfigMap/infernix-demo-config` and mounts the same filename inside cluster workloads at
  `/opt/build/infernix/infernix-substrate.dhall`
- the binary watches its substrate `.dhall` and reloads or restarts on changes; reload purges any
  running inference-engine state
- the supported materialization path can emit `demo_ui = false` with
  `--demo-ui false`; omitting that flag keeps the default demo-enabled output
- the routed demo app is cluster-resident across substrates; the interim Apple host bridge is not
  part of the final contract
- simulation is removed completely from supported runtime and validation paths; there are no
  simulated cluster, route, transport, or inference fallbacks on a supported substrate
- integration coverage is driven by the comprehensive model, format, and engine matrix in
  `README.md`: one substrate-aware integration suite reads the active substrate from `.dhall`,
  chooses the corresponding engine binding for each supported row or reference, and runs at least
  one assertion for every such row
- Playwright E2E remains substrate-agnostic at the browser layer and relies on `infernix-demo` to
  read the same `.dhall` and dispatch the correct engine for the active substrate
- Harbor-first bootstrap, mandatory local HA platform services, Gateway-owned routing, operator-run
  Patroni PostgreSQL, manual `infernix-manual` storage, Haskell-owned frontend contracts, the
  shared Python adapter project, and untracked generated outputs all remain mandatory doctrine
- supported validation becomes substrate-specific: integration, E2E, and `test all` exercise only
  the built and deployed substrate, and test reports name that substrate explicitly instead of
  implying matrix-wide coverage

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | realigns the governed docs suite and root guidance before later substrate-closure work can honestly claim implementation or validation completion |
| 1 | 0 | launcher ownership, substrate selection, and CLI flag removal depend on the reopened documentation baseline |
| 2 | 0-1 | cluster lifecycle and generated substrate-file publication depend on the updated launcher and substrate-selection contract |
| 3 | 0-2 | cluster-resident demo routing depends on the new cluster lifecycle and generated substrate-file publication |
| 4 | 0-3 | daemon placement, reload behavior, and transport closure depend on the settled cluster and routing substrate |
| 5 | 0-4 | demo-host and Playwright ownership depend on the daemon-placement and routed demo-surface contract |
| 6 | 0-5 | validation depends on the settled launcher, daemon, UI, and routed substrate contracts |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
