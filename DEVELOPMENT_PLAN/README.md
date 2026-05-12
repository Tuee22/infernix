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
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Harbor-first image flow, substrate `.dhall` publication, and Linux launcher closure |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and the Apple host-inference bridge for routed demo traffic |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, Apple host-native inference ownership, Linux cluster daemon lanes, reloadable `.dhall` control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, Apple host-backed browser dispatch, and Playwright ownership |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, README-matrix-driven single-substrate validation, Apple host-daemon bridge coverage, root-doc closure, and HA validation |
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

All phases 0–6 are reopened to adopt the Haskell CLI tool doctrine (`HASKELL_CLI_TOOL.md`, root).
The doctrine reset adds Sprint 0.9 for documentation distribution, Sprints 1.11–1.17 for the
standard stack and architectural patterns (toolchain pin, full `CommandSpec`, typed `Subprocess`,
Prerequisites DAG, `AppError`, Plan/Apply, forbidden-path registry), Sprint 2.10 for the
reconciler restatement and smart constructors, Sprints 3.10–3.11 for capability classes and
first-class `RetryPolicy`, Sprints 4.13–4.19 for the daemon lifecycle scaffold, health endpoints,
co-log logging, Dhall daemon config with SIGHUP hot reload, typed `Env`, at-least-once event
processing, and a GADT-indexed inference state machine, Sprint 5.9 for the unified
`GeneratedSectionRule` plus `trackedGeneratedPathRegistry` discipline, and Sprints 6.23–6.27 for
the `fourmolu` switch, committed `.hlint.yaml`, paired `--write` semantics, daemon-lifecycle test
stanza, and Pulumi exception. The doctrine adoption ports the closures named below onto the new
architecture rather than replacing them. Because Phase 0 Sprint 0.9 remains open, Phases 1–6 are
`Blocked` per the plan standards even though their earlier completed sprints remain `Done`.

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
serialize that active substrate under `runtimeMode` field names. The Apple hybrid contract is now
closed in code and validation: on `apple-silicon`, `cluster up` keeps Harbor, MinIO, Pulsar,
PostgreSQL, Envoy Gateway, and the optional clustered `infernix-demo` surface in Kind while
leaving `infernix service` host-native; routed manual inference enters the clustered demo surface
and bridges through Pulsar into the host daemon; `cluster up` no longer deploys
`infernix-service` on the Apple lane; publication exposes
`inferenceDispatchMode: pulsar-bridge-to-host-daemon`; and the runtime worker dispatches through
explicit supported runners while unsupported adapters fail fast instead of returning synthetic
success. The worktree removes the direct Harbor, MinIO, and Pulsar tool-route compatibility
handlers, requires the real routed upstream behavior in integration, persists Linux cluster state
before later rollout phases, and restages the active Linux substrate payload on each supported
bootstrap invocation. The governed `linux-cpu`, `linux-gpu`, and Apple host-native bootstrap
lifecycles now all rerun cleanly through `doctor`, `build`, `up`, `status`, `test`, and `down`.
The formatter-toolchain closure remains in place: the Haskell style bootstrap drives `ormolu` and
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
Playwright image no longer bakes a conflicting `NO_COLOR` default.

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
| 0 | Documentation and Governance | Active | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Blocked | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Blocked | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Blocked | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Blocked | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Blocked | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Blocked | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |

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
- the binary watches its substrate `.dhall` and reloads or restarts on changes; reload purges any
  running inference-engine state
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
- the Haskell CLI architecture doctrine is adopted: typed `Command` ADT plus first-class
  `CommandSpec` registry as the single source of truth, GADT-indexed state machines for the
  inference request lifecycle, typed `Subprocess` values with a two-function interpreter, smart
  constructors for paired Kubernetes resources, Plan/Apply discipline with `--dry-run` and
  `--plan-file` on every state-changing command, Prerequisites as a typed effect DAG, capability
  classes plus `AsServiceError` plus generic retry, first-class `RetryPolicy` values, an
  `AppError` ADT with `ErrorKind = Recoverable | Fatal`, reconciler discipline as the canonical
  mutation entrypoint, the `GeneratedSectionRule` plus `trackedGeneratedPathRegistry` two-category
  generated-artifacts split, and a `forbiddenPathRegistry` negative-space lint
- the daemon discipline is adopted: the seven-step lifecycle load → prereq → acquire → ready →
  serve → drain → exit through nested `bracket` and `withAsync`, `/healthz` / `/readyz` /
  `/metrics` HTTP endpoints on a dedicated admin port, structured JSON logging on stderr via
  `co-log` with typed `field` helpers, a daemon Dhall config with `BootConfig` / `LiveConfig`
  split and SIGHUP-driven hot reload through a dedicated `TBQueue` worker, a typed `Env` record
  with test hooks, and at-least-once event processing through a `processed_at` column with
  idempotent handlers
- the lint, format, and code-quality stack standardizes on `fourmolu` (with a committed
  `fourmolu.yaml` pinning `column-limit: 100`), `hlint` with `--with-group=default` plus
  `--with-group=extra` plus a committed `.hlint.yaml`, `cabal format` round-trip checks, and
  paired `--write` semantics on every validator
- the test surface adds an `infernix-daemon-lifecycle` Cabal `test-suite` stanza alongside
  `infernix-unit`, `infernix-integration`, and `infernix-haskell-style`; `infernix` does not
  adopt the doctrine's Pulumi-orchestrated infrastructure tests because supported substrates are
  local Kind clusters owned by `infernix cluster up` itself

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | distributes the Haskell CLI doctrine across the governed docs suite before later phases claim closure against its architectural patterns; also continues to anchor the prior substrate-closure documentation baseline |
| 1 | 0 | the standard library stack pin, full `CommandSpec`, typed `Subprocess`, Prerequisites DAG, `AppError`, Plan/Apply scaffold, and forbidden-path registry depend on the distributed documentation baseline; later phases consume these foundations |
| 2 | 0-1 | reconciler discipline restatement and smart constructors for paired resources depend on the Plan/Apply scaffold and typed `Subprocess` interpreter from Phase 1 |
| 3 | 0-2 | capability classes and `RetryPolicy` depend on the typed boundaries from Phase 1 and the cluster reconcile pattern from Phase 2 |
| 4 | 0-3 | daemon lifecycle, health endpoints, co-log logging, Dhall daemon config with SIGHUP reload, typed `Env`, at-least-once event processing, and the GADT-indexed inference state machine depend on the capability classes and `RetryPolicy` from Phase 3 plus the foundations from Phases 0-2 |
| 5 | 0-4 | the unified `GeneratedSectionRule` plus `trackedGeneratedPathRegistry` discipline depends on the forbidden-path registry from Phase 1 and the daemon contract from Phase 4 |
| 6 | 0-5 | the `fourmolu` switch, `.hlint.yaml`, paired `--write` semantics, daemon-lifecycle test stanza, and Pulumi exception depend on the settled daemon, generated-artifacts, and lint-stack contracts from earlier phases |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
