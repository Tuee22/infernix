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
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite bootstrap plus the substrate-doctrine documentation reset |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, CLI contract, build-root doctrine, launcher ownership, and substrate-selection closure |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Harbor-first image flow, substrate `.dhall` publication, Linux launcher closure, and lifecycle-progress hardening |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and the Apple host-inference bridge for routed demo traffic |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, Apple host-native inference ownership, Linux cluster daemon lanes, staged `.dhall` control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, Apple host-backed browser dispatch, and Playwright ownership |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, README-matrix-driven single-substrate validation, Apple host-daemon bridge coverage, root-doc closure, HA validation, and false-negative doctrine hardening |
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

All phases now close around the implementation that actually exists in this worktree. The
repository already implements the staged-substrate architecture, the Apple host-native inference
lane, the baked Linux outer-container launcher, the mandatory HA platform services, the
Gateway-owned routed edge, the shared Python adapter project, the Haskell-owned
browser-contract generation path, and the substrate-specific validation surface described below.

The repository already implements the substrate-file doctrine described by this plan. Supported flows
stage one `infernix-substrate.dhall` beside the active build root through explicit
`infernix internal materialize-substrate ...` helpers: Apple operators run
`./.build/infernix internal materialize-substrate apple-silicon`, and Linux outer-container
operators run
`docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
which writes `./.build/outer-container/build/infernix-substrate.dhall` on the host through the
host-anchored `./.build/` bind mount. Supported runtime, cluster, and validation entrypoints fail
fast if the staged file is absent instead of falling back to host detection or
`INFERNIX_SUBSTRATE_ID`. Cluster publication mirrors the exact payload locally under
`./.data/runtime/configmaps/infernix-demo-config/infernix-substrate.dhall` and mounts the same
filename inside cluster workloads at `/opt/build/infernix-substrate.dhall`. The file keeps the
legacy `.dhall` filename even though the payload is banner-prefixed JSON. Validation reports only
the active built substrate instead of implying a default cross-substrate matrix, and the
generated file, `cluster status`, publication JSON, and generated browser contracts still
serialize that active substrate under `runtimeMode` field names. The Apple hybrid contract is
implemented on `apple-silicon`: `cluster up` keeps Harbor, MinIO, Pulsar, PostgreSQL, Envoy
Gateway, and the optional clustered `infernix-demo` surface in Kind while leaving
`infernix service` host-native; routed manual inference enters the clustered demo surface and
bridges through Pulsar into the host daemon; `cluster up` no longer deploys `infernix-service`
on the Apple lane; publication exposes `inferenceDispatchMode: pulsar-bridge-to-host-daemon`;
and the runtime worker dispatches through explicit supported runners while unsupported adapters
fail fast instead of returning synthetic success. The worktree omits the direct Harbor, MinIO,
and Pulsar tool-route compatibility
handlers, requires the real routed upstream behavior in integration, persists Linux cluster state
before later rollout phases, and restages the active Linux substrate payload on each supported
bootstrap invocation. The formatter-toolchain closure remains in place: the Haskell style bootstrap drives `ormolu` and
`hlint` through the dedicated compatible formatter compiler `ghc-9.12.4`, while the Linux
substrate image preinstalls that compiler beside the project `ghc-9.14.1` toolchain. The
supported Linux outer-container launcher reuses a persistent `chart/charts/` archive cache,
hydrates the MinIO dependency through the supported direct tarball path instead of Docker
Hub-backed OCI metadata, and detects the known stale Pulsar or ZooKeeper epoch mismatch by
resetting only the retained Pulsar claim roots and retrying `cluster up` once. The Apple
clean-host bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables before
direct `cabal install`, reconciles Homebrew `protoc`, reconciles Colima to the supported
`8 CPU / 16 GiB` profile before Docker-backed work, and lets Apple adapter setup or validation
paths reconcile Homebrew `python@3.12` plus a user-local Poetry bootstrap on demand. Routed Apple
Playwright readiness probes `127.0.0.1` from the host while the browser container joins the
private Docker `kind` network and targets the Kind control-plane DNS, and the dedicated
Playwright image no longer bakes a conflicting `NO_COLOR` default. The shared cluster lifecycle
now surfaces explicit in-progress phase, child-operation detail, and heartbeat data through
`cluster status` during monitored Docker build, Harbor publication, Kind-worker preload, and
Apple retained-state replay steps; generated substrate publication writes the staged
`infernix-substrate.dhall` atomically so concurrent status readers do not observe truncated
payloads; and retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
replicas from the current Patroni leader when timeline drift leaves replicas unready after
promotion. Phase 6 records clean governed bootstrap reruns for `linux-cpu`, `linux-gpu`, and the
supported Apple lifecycle, including the latest Apple rerun on May 13, 2026 through
`./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down`, with
steady-state `status` returning two nodes and sixty-five pods and final post-teardown status
returning `clusterPresent: False`, `lifecycleStatus: idle`, and
`lifecyclePhase: cluster-absent`. That Apple rerun also confirmed that `build-cluster-images`
can remain healthy well past thirty minutes before Harbor publication begins, that Harbor image
pushes are readiness-gated with bounded retries across transient registry resets, and that the
governed `test` lane may perform multiple internal cluster bring-up or teardown cycles before the
outer bootstrap command returns.

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

- two repo-owned Haskell executables share the default Cabal library exposed by the `infernix`
  package (declared in `infernix.cabal` without an explicit library name and depended on as
  `infernix`): `infernix` for the production daemon, cluster lifecycle, validation, and internal
  helpers; `infernix-demo` for the routed demo HTTP host
- one structured Haskell command registry owns parsing, help text, and the canonical CLI
  reference, but it no longer exposes `--runtime-mode` or any equivalent substrate override
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from the staged `infernix-substrate.dhall` file beside the active
  build root, and that staged payload is the primary source of truth for substrate identity,
  generated catalog content, daemon placement, and test scope
- Apple host-native workflows stage or restage `./.build/infernix-substrate.dhall` explicitly with
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
- Linux outer-container workflows stage or restage `./.build/outer-container/build/infernix-substrate.dhall`
  on the host through the bind-mounted build tree with
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
- supported runtime, cluster, and validation entrypoints fail fast if the staged substrate file is
  absent instead of regenerating it on first command execution or falling back to env or host
  detection
- the staged substrate file retains the legacy `.dhall` filename even though the current payload is
  banner-prefixed JSON produced by Haskell runtime helpers
- Apple host-native operation is the only supported host build path outside a container
- on Apple Silicon, the host-built `./.build/infernix` binary manages Kind, deploys the mandatory
  cluster support services and optional routed demo workload, and owns the direct host-side
  `infernix service` lane
- on Apple Silicon, the canonical inference executor is the host-native `infernix service`
  process; clustered Apple workloads may consume the same staged substrate file and route
  contracts, but they do not replace host-native Apple inference or claim direct Metal or unified
  memory access
- when the demo UI is enabled on Apple Silicon, the routed demo surface may stay cluster-resident,
  but the supported steady-state path bridges routed inference into the host-native Apple daemon
  rather than keeping Apple inference inside a cluster-resident repo workload
- on Apple Silicon, Compose is not a user-facing launcher for ordinary CLI work; the host CLI
  invokes `docker compose run --rm playwright` against the dedicated `infernix-playwright:local`
  image for routed Playwright E2E
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
  `./.build/infernix-substrate.dhall` on Apple and `./.build/outer-container/build/infernix-substrate.dhall`
  on the host on the Linux outer-container path; cluster deployment republishes that payload
  through `ConfigMap/infernix-demo-config` whenever the active topology has cluster-resident
  consumers and mounts the same filename inside those workloads at `/opt/build/infernix-substrate.dhall`
- the current daemon reads its staged substrate `.dhall` at startup; automatic file-watching or
  reload is not part of the supported contract
- the supported materialization path can emit `demo_ui = false` with
  `--demo-ui false`; omitting that flag keeps the default demo-enabled output
- the routed demo app remains cluster-resident when enabled, but the Apple routed path closes
  around an explicit host-inference bridge rather than cluster-resident Apple service parity
- supported entrypoints no longer carry the old cross-substrate default matrix, cluster bring-up
  fallbacks, or direct tool-route compatibility handlers; routed Harbor, MinIO, and Pulsar checks
  require the real Gateway-backed upstream behavior
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
- the supported control plane keeps one Haskell-owned command registry, imperative cluster or host
  prerequisite orchestration, the current `ormolu` plus `hlint` plus `cabal format` style stack,
  and the existing files or docs or chart or proto validation entrypoints rather than layering on
  an additional architecture-doctrine backlog
- the direct `infernix service` daemon remains startup-configured and Pulsar-driven without a
  separate admin-HTTP, hot-reload, or typed-event-ledger subsystem in the supported contract
- the test surface remains the current three Cabal stanzas plus the frontend unit suite:
  `infernix-unit`, `infernix-integration`, and `infernix-haskell-style`, exercised through the
  supported `infernix test lint|unit|integration|e2e|all` command surface

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes the governed docs suite and plan-maintenance rules the remaining phases rely on |
| 1 | 0 | closes the repository scaffold, the two-binary topology, the staged-substrate contract, and the governed root-document posture |
| 2 | 0-1 | builds Kind lifecycle, manual storage, Harbor-first image flow, and Linux launcher behavior on top of the repository foundations |
| 3 | 0-2 | adds the HA platform services, routed edge, and publication contract on top of the cluster lifecycle and storage baseline |
| 4 | 0-3 | closes the runtime, adapter boundary, object-store contract, and Apple host-daemon bridge on top of the HA platform surfaces |
| 5 | 0-4 | adds the clustered demo UI, generated frontend contracts, and routed browser validation on top of the runtime and publication contract |
| 6 | 0-5 | validates the whole supported surface end to end and hardens the governed docs, routes, and lifecycle behavior around that implementation |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
