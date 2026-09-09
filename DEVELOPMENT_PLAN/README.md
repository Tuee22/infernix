# Infernix Development Plan

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md)

> **Purpose**: Provide the single execution-ordered development plan for `infernix`, including
> phase status, repository-shape decisions, validation gates, and documentation obligations.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Current execution gate

Phase 0 remains `Done` and frozen at Sprint 0.36. Phases 1–9 are `Active` because each has
explicit implementation or evidence obligations in its own scope. Start with Sprint 1.44; the
follow-on sprints proceed in natural phase order after their named code-side prerequisites.
Closed sprint headings remain closed records of their original scope, not proof of the new work.

No remediation implementation or new cohort validation is claimed by this documentation update.
[Open waves R1–R9](cohort-validation-waves.md#wave-table) each require one selected accelerator plus
`linux-cpu`; their hardware sign-off does not block the next phase's code-side work. The
[phase table](#current-phase-overview) is the sole phase-status summary.

The retained attestation table has no closure tuples for Phases 2, 3, 5, or 7. This is an evidence
gap, not proof that historical tests never ran. Recover the actual source preimage and run records
or rerun the gates; do not reconstruct a PASS from prose. Existing tuples remain append-only and
do not certify the new remediation scopes.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Maintenance rules for the development plan |
| [00-overview.md](00-overview.md) | Architecture baseline, hard constraints, substrate contract, and canonical repository shape |
| [system-components.md](system-components.md) | Authoritative component inventory and state-location map |
| [cohort-validation-waves.md](cohort-validation-waves.md) | Open cohort gates, plus the append-only Recorded Attestations table each closed gate leaves behind: one row per phase and accelerator lane under Section Q's single-accelerator-per-phase rule |
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite bootstrap plus the substrate-doctrine documentation reset |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, CLI contract, build-root doctrine, launcher ownership, and substrate-selection closure |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, registry-first image flow, substrate `.dhall` publication, Linux launcher closure, and lifecycle-progress hardening |
| [phase-3-platform-services-and-edge-routing.md](phase-3-platform-services-and-edge-routing.md) | Single-instance local platform services, Envoy Gateway ownership, publication contract, and the Apple cluster-to-host inference bridge for routed demo traffic |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, cluster-daemon request consumption, Apple host inference execution, staged `.dhall` role control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, Apple host-backed browser dispatch, and Playwright ownership |
| [phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md) | Static quality, README-matrix-driven single-substrate validation, Apple cluster-to-host daemon split coverage, root-doc closure, single-instance lifecycle/recovery validation, and false-negative doctrine hardening |
| [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) | Multi-user durable-context demo: Keycloak auth, WebSocket transport, Pulsar-backed conversation history, MinIO artifact upload/download/render-or-download, Haskell-first logic via purescript-bridge, and the three-role daemon split (stateless frontend, stateless coordinator, substrate-specific engine pools) on the single-instance platform topology |
| [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) | Adopt the hostbootstrap Dhall doctrine: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (incl. ConfigMap/Secret bodies; Helm only embeds a string), explicit `init` / `test init` creation with ordinary commands failing fast when config is missing and Apple bootstrap `up` explicitly running `init --if-missing`, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging from the mounted `infernix.dhall` (replacing the lazy per-inference bootstrap) |
| [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md) | Role-based access control and monitoring: the admin (cluster-wide operator consoles + monitoring) vs. user (own chat/artifacts/files + personal dashboard) split, Keycloak admin role + JWT role claim, edge admin authorization with ungated-route closure, admin/personal dashboards, per-user MinIO STS defense-in-depth, and the Apple host-worker loopback data-plane invariant |
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

1. The listed implementation paths enforce the specified behavior, including adversarial and
   negative cases; path existence, status markers, or nominal type names alone are insufficient.
2. The listed validation gates pass on the supported execution path, with the phase's **single
   chosen accelerator** cohort (`apple-silicon` **or** `linux-gpu`) plus `linux-cpu` recorded when
   substrate-aware behavior is in scope — never both accelerators against one phase.
3. The governed docs named in `Docs to update` match the implementation.
4. No remaining cleanup or compatibility surface is left unstated.
5. Cleanup promised by the sprint is reflected in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
6. Retained execution evidence identifies the reconstructable source snapshot, immutable built
   artifact, lane/device context, required checks, executed/skipped counts, outcomes, and log
   artifacts. Missing evidence or a skipped mandatory check prevents closure. Section Q defines
   the trust boundary; Markdown lint does not authenticate execution.

`Done` is the single-accelerator sign-off gate (item 2's one-accelerator-plus-`linux-cpu` evidence).
It is distinct from *code-side closure* — the implementation plus the machine-independent gate set —
which is completed in natural phase order on a single machine and is the gate to begin the *next*
phase's implementation. A phase whose code-side closure is complete but whose single chosen
accelerator full-suite is still pending stays `Active` with a named `Cohort gate` residual; that
residual does not block the next phase's implementation. See the single-accelerator execution rule in
[development_plan_standards.md](development_plan_standards.md) Section Q, and the shared
[../documents/architecture/pulsar_ml_workflow.md](../documents/architecture/pulsar_ml_workflow.md)
contract.

## Current Repo Assessment

The worktree contains substantial implementations for the one-binary CLI, platform services,
Pulsar routing, engine adapters, browser application, and role-based access control. The governing
architecture describes the target contract; it is not evidence that every contract is enforced.

The outstanding findings are owned as follows:

| Owning work | Observed gap and required correction |
|------------|--------------------------------------|
| [Phase 1: 1.44–1.46](phase-1-repository-and-control-plane-foundation.md) | Source-bound validation and required-check runner, binary-owned seed generation, explicit Apple engine startup, fail-closed cgroup observation, and domain-owned lifecycle authority. |
| [Phase 2: 2.18](phase-2-kind-cluster-storage-and-lifecycle.md) | Lifecycle consumer containment and cleanup; recover or rerun missing retained lifecycle evidence. |
| [Phase 3: 3.18](phase-3-platform-services-and-edge-routing.md) | Recover or rerun source-bound platform, routed publication, and registry evidence. |
| [Phase 4: 4.50](phase-4-inference-service-and-durable-runtime.md) | Real engine-cache hydration and rebuild, complete artifact accounting, and behavioral realness checks. |
| [Phase 5: 5.13](phase-5-web-ui-and-shared-types.md) | Backend static-file containment and real Gateway negative tests; retained browser evidence. |
| [Phase 6: 6.55](phase-6-validation-and-e2e-hardening.md) | Required device checks cannot silently skip; bounded fixture-process cleanup and structured execution evidence. |
| [Phase 7: 7.30–7.33](phase-7-demo-app-durable-context.md) | Dispatcher replay, genuine conversation/KV reconstruction, engine cancellation, bounded previews, and rendered audio/playback evidence. |
| [Phase 8: 8.15](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) | Validate sole-binary configuration generation through every consumer, using the Phase 1 bootstrap boundary. |
| [Phase 9: 9.12](phase-9-access-control-and-monitoring.md) | Reject malformed cache requests before effects; validate real cache operations and admin/tenant isolation. |

Static-asset handling lacks a proven backend containment boundary; the public routed exploitability
must be measured separately because Gateway path normalization can differ. Generic rank-2 `IO`
leases do not prove nonescape through deferred effects or reminted markers; private destructive
consumers limit exposure but do not justify the stronger type claim. Static adapter checks are
heuristics, not a proof that arbitrary output came from inference.

Current launcher reuse can select stale source, mandatory GPU fixtures can report success without
executing their assertions, and retained phase evidence is incomplete. Until their owning work is
closed, an exit code, Markdown status, cache directory, prefix hash, or rendered DOM container is
insufficient evidence of the corresponding behavior. Removal of the concrete shortcut surfaces is
tracked in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Execution Contexts and Substrates

The plan keeps these concepts separate:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Supported substrate | `apple-silicon`, `linux-cpu`, `linux-gpu` | which substrate the initialized repo-root `./infernix.dhall` selects |

### Naming Note

The canonical NVIDIA-backed Linux substrate id is `linux-gpu`, and the implementation plus docs
now use that id consistently.

## Hardware Cohort Validation Cadence

Development and validation are organized around two physical host cohorts:

- **Apple Silicon cohort:** `./bootstrap/apple-silicon.sh ...` and direct
  `./.build/infernix ...` commands.
- **CUDA Linux cohort:** `./bootstrap/linux-gpu.sh ...` and the Compose-launched
  `docker compose run --rm infernix infernix ...` command surface.

> **Implement in natural phase order on whichever single machine is present, and validate each phase
> on exactly one accelerator plus `linux-cpu` — never both accelerators.** Every open phase has two
> independent axes. *Code-side closure* (Axis 1) is the implementation plus the machine-independent
> gate set — `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
> `infernix lint files/docs/chart/proto`, `infernix docs check`, the web unit suite, and
> `poetry run check-code`; completed in natural order on one machine, it is the gate to begin the
> *next* phase's implementation. *Single-accelerator sign-off* (Axis 2) is the hardware-specific
> full-suite for the phase's one chosen accelerator (`apple-silicon` Metal/Core ML, or `linux-gpu`
> CUDA) plus `linux-cpu`, recorded in `cohort-validation-waves.md`; it is the gate for `Done` and
> never the gate for moving on. A phase never requires the other accelerator; cross-accelerator
> coverage is split across sibling phases or merged by a later `linux-cpu`-only aggregation phase.

Phase work should stay on the current cohort until a coherent slice is ready. Validation-only
hardware residuals are queued in [cohort-validation-waves.md](cohort-validation-waves.md), but a
phase closes only on its chosen accelerator plus `linux-cpu`, not by alternating between Apple and
CUDA after each sprint. `linux-cpu` remains a portable CPU-only lane for native Linux amd64 and
native Linux arm64 hosts, but it does not run through Apple Silicon emulation and does not replace
the CUDA Linux cohort when a phase explicitly chooses `linux-gpu` for GPU behavior, CUDA image
construction, `nvkind`, or NVIDIA scheduling.

## How To Resume Open Work

Open work is identified by two markers and nothing else:

- a phase document's `**Status**:` field, and
- a sprint heading's bracketed status — `[Active]`, `[Blocked]` or `[Planned]`.

Read those. Do not infer open work from prose. Every closed sprint states its `Deliverables` and
`Validation` in the imperative — "replace", "add", "extend", "run" — because that is how the sprint
was written before it closed, and the status marker is the only thing that distinguishes a finished
deliverable from an outstanding one. A search for work-shaped sentences returns several hundred
false positives.

Three further conventions a reader needs:

- A `**Blocked by**` field reading `nothing` names its satisfied dependency in prose. A blocker edge
  is live only when it names a sprint whose own heading is not `[Done]`.
- Each phase document ends with a `## Documentation Requirements` block written as a list of
  documents. It records what the phase governs, not work outstanding.
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is the one forward-looking
  ledger: every row names a surface that still exists and must be removed, with the phase or sprint
  that carries it. A landed removal is deleted from the ledger rather than marked complete.

The phase-status table below is the single current-state table in the plan. Nothing mechanical holds
it equal to the phase headers it summarizes, so treat a disagreement between the two as a defect and
trust the phase document.

## Current Phase Overview

| Phase | Current status | Current gate and retained implementation state |
|-------|----------------|------------------------------------------------|
| 0 | Done | Frozen at Sprint 0.36; no new Phase 0 work. |
| 1 | Active | [Sprints 1.44–1.46](phase-1-repository-and-control-plane-foundation.md) and [Wave R1](cohort-validation-waves.md#wave-table): Source-bound validation and required-check runner, binary-owned seed generation, explicit Apple engine startup, fail-closed cgroup observation, and domain-owned lifecycle authority. |
| 2 | Active | [Sprints 2.18](phase-2-kind-cluster-storage-and-lifecycle.md) and [Wave R2](cohort-validation-waves.md#wave-table): Lifecycle consumer containment and cleanup; recover or rerun missing retained lifecycle evidence. |
| 3 | Active | [Sprints 3.18](phase-3-platform-services-and-edge-routing.md) and [Wave R3](cohort-validation-waves.md#wave-table): Recover or rerun source-bound platform, routed publication, and registry evidence. |
| 4 | Active | [Sprints 4.50](phase-4-inference-service-and-durable-runtime.md) and [Wave R4](cohort-validation-waves.md#wave-table): Real engine-cache hydration and rebuild, complete artifact accounting, and behavioral realness checks. |
| 5 | Active | [Sprints 5.13](phase-5-web-ui-and-shared-types.md) and [Wave R5](cohort-validation-waves.md#wave-table): Backend static-file containment and real Gateway negative tests; retained browser evidence. |
| 6 | Active | [Sprints 6.55](phase-6-validation-and-e2e-hardening.md) and [Wave R6](cohort-validation-waves.md#wave-table): Required device checks cannot silently skip; bounded fixture-process cleanup and structured execution evidence. |
| 7 | Active | [Sprints 7.30–7.33](phase-7-demo-app-durable-context.md) and [Wave R7](cohort-validation-waves.md#wave-table): Dispatcher replay, genuine conversation/KV reconstruction, engine cancellation, bounded previews, and rendered audio/playback evidence. |
| 8 | Active | [Sprints 8.15](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) and [Wave R8](cohort-validation-waves.md#wave-table): Validate sole-binary configuration generation through every consumer, using the Phase 1 bootstrap boundary. |
| 9 | Active | [Sprints 9.12](phase-9-access-control-and-monitoring.md) and [Wave R9](cohort-validation-waves.md#wave-table): Reject malformed cache requests before effects; validate real cache operations and admin/tenant isolation. |

## Canonical Outcome

The target platform closes around these rules; the current gaps are owned above:

- one repo-owned Haskell executable, `infernix`, links the default Cabal library exposed by the
  `infernix` package (declared in `infernix.cabal` without an explicit library name and depended on
  as `infernix`); it owns the production daemon, cluster lifecycle, validation, internal helpers, and
  the routed demo HTTP host (served by the long-running `Webapp` role selected through typed Dhall
  and `infernix service --role webapp`)
- one Haskell command registry owns parsing, help text, and the canonical CLI reference. Ordinary
  operations do not override the initialized substrate; `init` and `test init` retain their explicit
  `--runtime-mode` creation option
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from repo-root `./infernix.dhall`, and that initialized payload is
  the primary source of truth for substrate identity,
  generated catalog content, inference placement, derived Pulsar topics, and test scope. Daemon role
  and member selection belong to the machine/process contract
- `infernix init` creates the operator runtime config and host manifest; `infernix test init`
  creates the harness input from which a reservation-gated run generates its temporary runtime
  config
- the Linux substrate Dockerfile uses binary-owned config generation for image-local defaults, but
  ordinary outer-container commands do not auto-materialize missing operator or harness config
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints fail fast with a "run `infernix init`" reminder when
  their `infernix.dhall` is missing (Phase 8; no auto-materialize backstop); focused
  `infernix lint ...` and `infernix docs check` remain substrate-file independent
- the runtime substrate file is a typed Dhall record at repo-root `./infernix.dhall`, created by
  `infernix init` (or the test harness from `infernix test init`) and decoded in-process by the
  `dhall` Haskell library; the schema is
  reflected from the substrate decoder type — no `.dhall` is version-controlled
- Apple host-native operation is the only supported host build path outside a container
- on Apple Silicon, the host-built `./.build/infernix` binary manages Kind, deploys the mandatory
  cluster support services, the cluster coordinator Deployment, and optional routed demo workload,
  and owns the host-side same-binary engine daemon lane
- on Apple Silicon, the cluster coordinator is canonical for Pulsar ingress and derived pool-topic
  handoff, while host engine daemons are canonical for Apple-native inference execution and result
  publication; both roles consume `.dhall` role config from the same binary family
- when the demo UI is enabled on Apple Silicon, the routed demo surface stays cluster-resident and
  manual inference flows through the cluster daemon's batching path before Apple inference batches
  move through Pulsar to host daemons
- on Apple Silicon, Compose is not a user-facing launcher for ordinary CLI work; host-native routed
  E2E now uses host `npm exec` Playwright fed by the same typed fixture against the published
  localhost edge port and is covered by Apple cohort validation batches. Linux substrates run
  Playwright in-container inside the substrate image via
  `npm --prefix web exec -- playwright test ...`
- on Linux substrates, all supported CLI commands run through
  `docker compose run --rm infernix infernix ...`; there is no supported Linux host-native build or
  CLI surface outside the outer container
- `linux-cpu` is the only substrate that remains meaningfully portable across unrelated native
  Linux host hardware; native amd64 Linux and native arm64 Linux are the supported validation
  shapes, while Apple Silicon emulation is not a supported build or validation lane
- `linux-gpu` assumes an amd64 Linux environment paired with a CUDA-capable device, but the outer
  control-plane container itself does not require the NVIDIA runtime
- for `linux-gpu`, the outer control-plane image is still built from the CUDA base image, and that
  same built image is the artifact pushed to the registry and deployed as the cluster daemon
- the operator runtime config lives at repo-root `./infernix.dhall` on every supported execution
  context; cluster deployment derives a payload through `ConfigMap/infernix-demo-config` whenever
  the active topology has cluster-resident consumers and mounts it at the compatibility path
  `/opt/build/infernix.dhall`
- each daemon reads its runtime-config `.dhall` at startup; automatic file-watching or reload is
  not part of the supported contract
- `infernix init --demo-ui false` can disable the demo surface; omitting that flag keeps the
  default demo-enabled output
- the routed demo app remains cluster-resident when enabled, and the Apple routed path closes
  around an explicit cluster-daemon-to-host-daemon inference batch bridge rather than
  cluster-resident Apple inference execution
- supported entrypoints no longer carry the old cross-substrate default matrix, cluster bring-up
  fallbacks, direct tool-route compatibility handlers, or generic inference-success fallback;
  routed registry and Pulsar checks require real Gateway-backed upstream behavior; MinIO checks use
  the webapp object mediator or trusted internal data plane, while
  inference coverage goes through the typed adapter harness selected by the active substrate file.
  The repo-local Pulsar topic spool remains only a harness-oriented path for endpoint-absent unit
  or isolated daemon checks, not a substitute for routed cluster validation
- integration coverage is driven by the comprehensive model, format, and engine matrix in
  `README.md`: one substrate-aware integration suite reads the active substrate from `.dhall`,
  chooses the corresponding engine binding for each supported row or reference, and runs at least
  one assertion for every such row
- Playwright E2E remains substrate-agnostic at the browser layer and relies on `infernix-demo` to
  read the same `.dhall` and dispatch the correct engine for the active substrate
- registry-first bootstrap, one local instance of each platform service, Gateway-owned routing,
  operator-run single-instance Patroni PostgreSQL, manual `infernix-manual` storage, Haskell-owned frontend contracts, the
  shared Python adapter project, and untracked generated outputs all remain mandatory doctrine
- supported validation is substrate-specific: integration, E2E, and `test all` run their complete
  supported suites against the built and deployed substrate, and test reports name that substrate
  explicitly instead of implying matrix-wide coverage
- the supported control plane keeps one Haskell command registry,
  binary-owned lifecycle and validation orchestration, root-package in-process Ormolu/HLint plus
  the solver-isolated Cabal-format package, and the existing files or docs or chart or proto
  validation entrypoints; shell bootstrap responsibility is limited to prerequisite and launcher
  setup
- every `infernix service` daemon remains startup-configured and Pulsar-driven without a separate
  admin-HTTP, hot-reload, or typed-event-ledger subsystem in the supported contract
- the test surface contains eight root-package Cabal test suites, one solver-isolated Cabal-format
  package suite, and the frontend unit suite: `infernix-unit`,
  `infernix-artifact-transaction`, `infernix-apple-materializer`,
  `infernix-capped-engine-observer`, `infernix-compile-fail`,
  `infernix-execution-plan-internal`, `infernix-integration`, and
  `infernix-haskell-style` in the root package, plus `infernix-cabal-format` in its own package;
  all are exercised through the appropriate supported
  `infernix test lint|unit|integration|e2e|all` command surface

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes the governed docs suite and plan-maintenance rules the remaining phases rely on |
| 1 | 0 | closes the repository scaffold, the staged-substrate contract, the one-binary role model, and the governed root-document posture |
| 2 | 0-1 | builds Kind lifecycle, manual storage, registry-first image flow, and Linux launcher behavior on top of the repository foundations |
| 3 | 0-2 | adds the single-instance platform services, routed edge, and publication contract on top of the cluster lifecycle and storage baseline |
| 4 | 0-3 | closes the runtime, adapter boundary, object-store contract, and Apple host-daemon bridge on top of the platform surfaces |
| 5 | 0-4 | adds the clustered demo UI, generated frontend contracts, and routed browser validation on top of the runtime and publication contract |
| 6 | 0-5 | validates the whole supported surface end to end and hardens the governed docs, routes, and lifecycle behavior around that implementation |
| 7 | 0-6 | adds the multi-user durable-context demo application on top of the platform: Keycloak self-signup, WebSocket post-login transport, Pulsar-backed conversation log per context, MinIO-backed artifact upload/download/render-or-download, a Haskell-first logic boundary surfaced to PureScript via `purescript-bridge`, and the supported three-role daemon split (stateless Webapp role in the `infernix-demo` workload, stateless `infernix-coordinator`, substrate-specific engine pools). Current reconstruction, cancellation, media, and evidence obligations are owned by Sprints 7.30–7.33. |
| 8 | 0-7 | adopts the hostbootstrap Dhall doctrine on top of the whole platform: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (including ConfigMap/Secret bodies), explicit `init` / `test init` creation with ordinary commands failing fast when config is missing, the Apple bootstrap `up` wrapper explicitly running `init --if-missing`, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging (replacing the lazy per-inference bootstrap) driven by the mounted `infernix.dhall`. |
| 9 | 0-8 | adds the role-based access-control and monitoring surface on top of the whole demo platform: the Keycloak `infernix-admin` realm role + JWT `realm_access.roles` claim, the edge admin `SecurityPolicy` (a valid JWT is necessary but not sufficient for cluster-wide surfaces) plus ungated-route closure, the backend admin gate + admin cluster-wide monitoring panel, the per-user personal dashboard, per-user MinIO STS defense-in-depth, and the enforced Apple host-worker loopback data-plane invariant. Every dependency edge references an equal-or-lower-numbered phase, so the forward-only DAG holds — and since Sprint 0.25 that invariant covers ownership and evidence as well as blocker edges, checked mechanically rather than read for. |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
