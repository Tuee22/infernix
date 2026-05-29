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
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and the Apple cluster-to-host inference bridge for routed demo traffic |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, cluster-daemon request consumption, Apple host inference execution, staged `.dhall` role control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, Apple host-backed browser dispatch, and Playwright ownership |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, README-matrix-driven single-substrate validation, Apple cluster-to-host daemon split coverage, root-doc closure, HA validation, and false-negative doctrine hardening |
| [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) | Multi-user durable-context demo: Keycloak auth, WebSocket transport, Pulsar-backed conversation history, MinIO artifact upload/download/render-or-download, Haskell-first logic via purescript-bridge, and the three-role daemon split (stateless frontend, stateless coordinator, one-per-node engine) with an HA-first chart |
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
2. The listed validation gates pass on the supported execution path or matrix, with Apple Silicon
   and CUDA Linux cohort evidence both recorded when substrate-aware behavior is in scope.
3. The governed docs named in `Docs to update` match the implementation.
4. No remaining cleanup or compatibility surface is left unstated.
5. Cleanup promised by the sprint is reflected in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Current Repo Assessment

Phases 0 through 6 close around the implemented worktree. The repository implements the
staged-substrate architecture, the baked Linux outer-container launcher,
the mandatory HA platform services, the Gateway-owned routed edge, the shared Python adapter
project, the Haskell-owned browser-contract generation path, the substrate-specific validation
surface, and the final Apple split-executor topology described below. The Apple lane deploys
cluster `infernix service` daemons for
request-topic consumption and host-batch handoff while same-binary host daemons consume the
configured host batch topic, execute Apple-native inference, and publish completed results.

The repository implements the substrate-file doctrine described by this plan. Supported flows
stage one `infernix-substrate.dhall` beside the active build root through the `infernix` command
that needs it; the explicit
`infernix internal materialize-substrate ...` helpers remain the direct restaging or inspection
surface. The Linux substrate Dockerfile materializes a build-arg-selected substrate file inside
the image overlay during image build, and supported Compose runs keep that active build root
image-local instead of bind-mounting the host `./.build/` tree. Focused `infernix lint ...` and
`infernix docs check` remain substrate-file independent. The final substrate payload also
distinguishes cluster and host daemon
roles: cluster-role configs name the substrate, request and result topics, and any Apple
host-inference batch topic, while host-role Apple configs include the routed Pulsar connection
details and the batch topic consumed by the host daemon. Cluster publication mirrors the
cluster-role payload locally under
`./.data/runtime/configmaps/infernix-demo-config/infernix-substrate.dhall` and mounts the same
filename inside cluster workloads at `/opt/build/infernix-substrate.dhall`, while the Apple host
file under `./.build/` remains host-role metadata for the same substrate. The file is a typed
Dhall record at `infernix-substrate.dhall`, decoded in-process by the `dhall` Haskell library.
`infernix test all`
runs the full supported validation suite for the active built substrate; full repository substrate
closure comes from separate governed reruns for `apple-silicon`, `linux-cpu`, and `linux-gpu`,
not from one implicit cross-substrate matrix invocation. The generated file, `cluster status`,
publication JSON, and generated browser contracts still serialize that active substrate under
`runtimeMode` field names. `cluster status` does not mutate Kubernetes resources, publication
state, or authoritative repo-local state; the accepted Linux outer-container exception is an
idempotent Docker network membership repair that attaches the fresh launcher container to the
private `kind` network for observation. The Apple split-executor contract
is implemented on `apple-silicon`: `cluster up` keeps Harbor, MinIO, Pulsar,
PostgreSQL, Envoy Gateway, the optional clustered `infernix-demo` surface, and cluster
`infernix service` daemons in Kind; those cluster daemons own request-topic consumption and
host-batch handoff but do not execute Apple-native inference or publish the completed result;
same-binary host daemons consume the host batch topic, run the Apple-native inference engine, and
publish the result. On `linux-cpu` and `linux-gpu`, the cluster daemons read from Pulsar, run
inference directly, and publish results. The generated final-phase Helm values currently run one
cluster `infernix service` replica; the chart template exposes `service.replicaCount` and preferred
anti-affinity for explicit multi-replica values. Pulsar-owned topics, exclusive subscriptions, and
acknowledgement handling are the ordering and ownership boundary for request handoff, inference,
and result publication if operators deliberately scale that surface. The current adapters emit
deterministic engine-family output from
typed durable metadata, while unsupported adapter ids fail
fast instead of falling through to a generic success path. The worktree omits the
direct Harbor, MinIO, and Pulsar tool-route compatibility handlers, requires the real routed
upstream behavior in integration, and persists Linux cluster state before later rollout phases.
Bootstrap shells no longer restage the active substrate payload before lifecycle commands; that
preflight belongs to the binary command that needs the file. The formatter-toolchain closure
remains in place: the Haskell style bootstrap drives `ormolu` and
`hlint` through the dedicated compatible formatter compiler `ghc-9.12.4`, while the Linux
substrate image preinstalls that compiler beside the project `ghc-9.14.1` toolchain. The
supported Linux outer-container launcher reuses the image-local
`/opt/infernix/chart/charts/` archive cache,
hydrates the MinIO dependency through the supported direct tarball path instead of Docker
Hub-backed OCI metadata, and detects the known stale Pulsar or ZooKeeper epoch mismatch by
resetting only the retained Pulsar claim roots and retrying `cluster up` once. The Apple
clean-host bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables before
direct `cabal install`, reconciles Homebrew `protoc`, reconciles Colima to the supported
`8 CPU / 16 GiB` profile before Docker-backed work, and lets Apple adapter setup or validation
paths reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command plus a
user-local Poetry bootstrap on demand. The Poetry bootstrap may reuse an already available
compatible Python 3.12+ executable when one passes the implemented version check. Routed Apple
Playwright validation runs host-native `npm exec` against the published `127.0.0.1` edge port,
and the in-image
Playwright runtime no longer bakes a conflicting `NO_COLOR` default. The shared cluster lifecycle
now surfaces explicit in-progress phase, child-operation detail, and heartbeat data through
`cluster status` during monitored Docker build, Harbor publication, Harbor-backed final-image
preload, and Apple retained-state replay steps; explicit substrate materialization writes the
staged `infernix-substrate.dhall` atomically so concurrent status readers do not observe truncated
payloads; and retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
replicas from the current Patroni leader when timeline drift leaves replicas unready after
promotion. The shared lifecycle skips broad pre-Harbor support-image preloads and follows the
stricter Harbor-first target where Linux lanes may hydrate and stream only the narrow Harbor
warmup dependency set into Kind before Helm warmup, only Harbor-required services may pull
upstream before Harbor is responsive, and every remaining image, including the active `infernix`
runtime image, is loaded into Harbor before final rollout. Phase 6 had previously recorded clean governed bootstrap reruns for `linux-cpu`, `linux-gpu`, and
the supported Apple lifecycle on the retired hardware, including Apple reruns on
May 15, 2026 and May 17, 2026 through `./bootstrap/apple-silicon.sh doctor`, `build`, `up`,
`status`, `test`, `down`, and final `status`, plus the May 19, 2026 post-warning-cleanup
`linux-gpu` rerun through `./bootstrap/linux-gpu.sh doctor`, forced image refresh, `build`, `up`,
`status`, `test`, `down`, `purge`, and final `status`. Those historical reruns originally covered
the split daemon topology, host-batch Pulsar handoff, routed Playwright E2E, repeated
retained-state cluster bring-up or teardown cycles inside the governed `test` lane, final
post-teardown status returning `clusterPresent: False`, `lifecycleStatus: idle`, and
`lifecyclePhase: cluster-absent`, and the Harbor publication closure for repo-owned local images
where publication pushes the `infernix-linux-cpu:local` payload before third-party chart
dependencies and re-tags the source image before each bounded push retry so retry recovery does
not depend on a previously retained target tag. The earlier May 13 lifecycle investigation
originally served as the proof point that `build-cluster-images` can remain healthy well past
thirty minutes before Harbor publication begins and that Harbor image pushes are readiness-gated
with bounded retries across transient registry resets. **All of those Apple Silicon and CUDA
Linux runs were performed on the retired hardware and no longer count as current proof points;
the underlying contracts they exercised still describe the supported behavior, but Apple Silicon
and CUDA Linux validation are both pending on the new Apple Silicon host before they can be
claimed again.** Sprint 6.26 closes the buildx, npm, GHCup shell-profile, Python packaging, and
Playwright script warning cleanup with the governed `linux-gpu` lifecycle rerun complete.
Sprint 6.27 closes the staged-substrate format cleanup: `infernix-substrate.dhall` is now a real
typed Dhall record decoded in-process by the `dhall` Haskell library, with the schema documented at
`dhall/InfernixSubstrate.dhall`.

**Apple Silicon validation reset (2026-05-29).** The repository was previously developed on a
Linux/CUDA host with a separate Apple Silicon machine used for the Apple cohort proof points. The
project has now moved to an Apple Silicon host as the primary development machine, and the prior
Apple Silicon hardware is no longer available. Every recorded Apple Silicon lifecycle, test, and
bootstrap validation, including the May 13, 2026 lifecycle investigation and the May 15, 2026 and
May 17, 2026 governed Apple lifecycle reruns, is therefore retired as a current proof point. The
underlying implementation has not changed, but Apple Silicon validation must be redone end to end
on the new host before any current Apple proof points can be claimed. All Apple cohort lifecycle,
bootstrap, `cluster up`/`status`/`down`, `test all`, routed Playwright E2E, split-topology
host-batch Pulsar handoff, retained-state replay, and Harbor-publication assertions on Apple
Silicon currently carry an explicit `Apple cohort validation pending on new host` residual. The
prior CUDA Linux cohort evidence on the `linux-gpu` substrate (most recently the May 26 and
May 27, 2026 reruns) remains historically accurate but was performed on the retired host, and the
plan no longer treats that evidence as a current real-cluster proof point either; CUDA Linux
cohort validation is now also pending on the new host (run through the supported
`docker compose run --rm infernix infernix ...` outer-container path inside Colima's amd64 VM, or
on a separate Linux/CUDA machine if and when one is reintroduced). The `linux-cpu` portable lane
remains pending on the new host as well and is the primary lane available from Apple Silicon
without the CUDA Linux cohort.

The production and routed validation path uses real Pulsar transport. The repository still keeps
the repo-local topic spool under `./.data/runtime/pulsar/` as a deliberate harness surface when
unit-level checks or manually isolated daemon runs intentionally omit Pulsar endpoint
configuration; that harness does not count as routed cluster evidence and does not replace the
Gateway-backed Pulsar assertions in integration or E2E validation.

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

## Hardware Cohort Validation Cadence

Development and validation are organized around two physical host cohorts:

- **Apple Silicon cohort:** `./bootstrap/apple-silicon.sh ...` and direct
  `./.build/infernix ...` commands.
- **CUDA Linux cohort:** `./bootstrap/linux-gpu.sh ...` and the Compose-launched
  `docker compose run --rm infernix infernix ...` command surface.

Phase work should stay on the current cohort until a coherent slice is ready. Apple-owned changes
validate locally on Apple and queue CUDA Linux closure; Linux, CUDA, chart, and outer-container
changes validate locally on CUDA Linux and queue Apple closure. The counterpart run is a phase
closure batch, not a per-sprint machine switch.

Full phase closure requires both relevant hardware cohorts to rerun the complete gates against the
same phase state. `linux-cpu` remains a portable CPU-only lane that may run from either host, but
it does not replace the CUDA Linux cohort when GPU behavior, CUDA image construction, `nvkind`, or
NVIDIA scheduling is in scope.

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Active (Sprint 0.9: Configuration Doctrine) | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Active (Sprint 1.11: Host Manifest Materialization; code landed; the prior CUDA Linux cohort validation (May 27, 2026) and Apple cohort closure batch were both performed on the retired hardware and no longer count as current proof points; Apple cohort validation pending on new host, and CUDA Linux cohort validation also pending on new host) | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Active (Sprint 2.13 code-side env capture retirement + HostTool routing landed; the prior clean-env `linux-gpu` lifecycle validation (May 27, 2026) was on the retired hardware and no longer counts as a current proof point; Apple cohort and CUDA Linux cohort validation both pending on new Apple Silicon host) | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Active (Sprint 3.10 code landed; the prior CUDA Linux cohort in-container Playwright E2E (May 27, 2026) was on the retired hardware and no longer counts as a current proof point; Apple host-native E2E runner code landed and Apple cohort closure remains pending; CUDA Linux cohort validation also pending on new host) | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Active (Sprint 4.13 code closed: `ClusterConfig` renderer + decoder roundtrip unit tests in place; MinIO endpoint / region / credential wiring reads mounted `ClusterConfig` + `SecretsConfig`; the prior `linux-gpu` `test all` PASS (May 26, 2026) that originally validated `ClusterConfig.engine.commandOverrides` threading through `Worker.hs.runInferenceWorker` against the real cluster was on the retired hardware and no longer counts as a current proof point; Apple cohort and CUDA Linux cohort `test all` validation both pending on new Apple Silicon host) | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Active (Sprint 5.9 code closed: demo backend reads `ClusterConfig.demoBackend.*`; Python adapters no longer read `os.environ`; web/Node helper scripts no longer read `process.env`; `poetry run check-code`, Node syntax checks, and grep gates are in place; the prior May 26 `linux-gpu` `test all` PASS that originally validated this closure was on the retired hardware and no longer counts as a current proof point; Apple cohort and CUDA Linux cohort `test all` validation both pending on new Apple Silicon host) | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Active (Sprint 6.28 code closed: test-suite env isolation and bare `proc "python3"` fixtures retired; Haskell-style, docs, and chart lint gates are active; the prior recorded Apple cohort lifecycle reruns and the May 26 `linux-gpu` `test all` PASS that previously formed the full real-cluster validation baseline were both on the retired hardware and no longer count as current proof points; Apple cohort and CUDA Linux cohort full-suite validation both pending on new Apple Silicon host) | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |
| 7 | Demo App Multi-User Durable Context | Active (Sprints 7.1, 7.3-7.16 partial-landed in code; Sprint 7.14 WebSocket-to-Pulsar publish plumbing, coordinator-to-engine integration, compacted-topic behavior, frontend producer-dedup validation, and non-chaos dispatcher/result-bridge durable prompt roundtrip code landed, with chaos / throughput suites still open; Sprint 7.15 code now carries the durable-context shell, routed SPA/publication smoke, routed Keycloak self-registration auth-code smoke, routed WebSocket valid/malformed JWT handshake validation plus expired-token rejection and typed malformed-frame error validation, routed real-Keycloak-JWT `/api/objects` grant validation, same-user routed presigned MinIO PUT/GET byte equality, routed cross-user object-prefix isolation, routed download-grant MIME disposition matrix, browser artifact upload-render coverage across bounded text/JSON preview, inline image/audio/video media, browser-native PDF, MIDI / MusicXML / generic download-only behavior, browser-upload `ClientRecordUpload` -> `ConversationUserUploadEvent` publication wiring, browser conversation-visible upload event assertions, browser model-select `ClientCreateContext` / context-summary assertions, browser new-context dialog close-negative assertions, browser context rename/soft-delete frame and patch assertions, backend `ClientCreateContext` unknown-model rejection, browser prompt-submit `promptUserUploads` outbound-frame coverage, per-context `ClientSubscribeContext` -> `ServerConversationPatch` prompt coverage, `ClientHello`-started context-list/draft snapshot coverage, context-create `ServerContextListPatch` coverage, draft `ServerDraftMapPatch` upsert/remove coverage, browser logout/re-login plus refresh-token WebSocket re-auth coverage, browser WebSocket reconnect/reconstitution coverage, browser cancel lifecycle coverage, draft reconnect/reload restoration coverage, two-prompt queued indicator assertions, and the Sprint 7.1 `demo_ui = false` absence check; per-model smoke matrix remains open; Sprint 7.17 schema + Haskell decoder + chart Secret + chart env stripping + Python `INFERNIX_POETRY_EXECUTABLE` retirement + full `Demo/Api.hs` / `Demo/Auth.hs` / `Runtime/Pulsar.hs.loadBootstrapPresignedConfig` `INFERNIX_KEYCLOAK_*` / `INFERNIX_MINIO_*` retirement landed in code; the prior CUDA Linux `linux-gpu` `test all` PASS (May 26, 2026) that originally validated Sprint 7.17 end-to-end was on the retired hardware and no longer counts as a current proof point; Sprint 7.17's remaining Apple-only Poetry bootstrap env-var residual in `src/Infernix/Python.hs` retired 2026-05-29, closing the full configuration-doctrine code surface with `cabal build all`, `cabal test infernix-haskell-style`, `cabal test infernix-unit`, and the four `infernix lint ...` subcommands all exiting zero on the new Apple Silicon host; Apple cohort and CUDA Linux cohort full-suite validation both pending on new Apple Silicon host) | [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) |

> **Note**: Phase statuses describe current repository state. Earlier governed phases may remain
> `Active` for named follow-ons while later phases can be `Done` when their owned work and
> validation are complete.
> Each phase 1-7 gained a retirement sprint that eliminates the env-var fallbacks and
> PATH-resolved external commands the phase originally introduced. See
> [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)
> for the doctrine, and the per-phase sprint sections for the specific retirement scope.

## Canonical Outcome

The supported platform now closes around these rules:

- two repo-owned Haskell executables share the default Cabal library exposed by the `infernix`
  package (declared in `infernix.cabal` without an explicit library name and depended on as
  `infernix`): `infernix` for the production daemon, cluster lifecycle, validation, and internal
  helpers; `infernix-demo` for the routed demo HTTP host
- one Haskell command registry owns parsing, help text, and the
  canonical CLI reference, but it no longer exposes `--runtime-mode` or any equivalent substrate
  override
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from the staged `infernix-substrate.dhall` file beside the active
  build root, and that staged payload is the primary source of truth for substrate identity,
  generated catalog content, daemon role, inference placement, Pulsar topics, and test scope
- Apple host-native lifecycle and validation commands materialize or verify
  `./.build/infernix-substrate.dhall`; the explicit helper
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
  remains available for direct restaging or inspection
- Linux outer-container lifecycle and validation commands materialize or verify
  `/workspace/.build/outer-container/build/infernix-substrate.dhall` inside the launcher image;
  the explicit helper
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  remains available for direct restaging or inspection
- the Linux substrate Dockerfile materializes a build-arg-selected copy inside the image overlay,
  and the supported outer-container command surface keeps that copy image-local before doing
  substrate-aware work
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints own substrate-file preflight for their execution
  context and fail with a substrate-specific diagnostic if the file cannot be materialized or
  validated; focused `infernix lint ...` and `infernix docs check` remain substrate-file independent
- the staged substrate file is a typed Dhall record at `infernix-substrate.dhall`, materialized by
  Haskell runtime helpers and decoded in-process by the `dhall` Haskell library; the schema lives
  at `dhall/InfernixSubstrate.dhall`
- Apple host-native operation is the only supported host build path outside a container
- on Apple Silicon, the host-built `./.build/infernix` binary manages Kind, deploys the mandatory
  cluster support services, the cluster `infernix service` Deployment, and optional routed demo
  workload, and owns the host-side same-binary inference daemon lane
- on Apple Silicon, the cluster daemon is canonical for Pulsar ingress and host-batch handoff,
  while the host daemon is canonical for Apple-native inference execution and result publication;
  both roles consume `.dhall` role config from the same binary family
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
- `linux-cpu` is the only substrate that remains meaningfully portable across unrelated host
  hardware; Apple operators may exercise it through Colima's amd64 VM, and arm64 Linux is treated
  as a first-class CPU-only host shape
- `linux-gpu` assumes an amd64 Linux environment paired with a CUDA-capable device, but the outer
  control-plane container itself does not require the NVIDIA runtime
- for `linux-gpu`, the outer control-plane image is still built from the CUDA base image, and that
  same built image is the artifact pushed to Harbor and deployed as the cluster daemon
- the staged substrate file lives under the active build root:
  `./.build/infernix-substrate.dhall` on Apple and
  `/workspace/.build/outer-container/build/infernix-substrate.dhall` inside the Linux launcher
  image; cluster deployment republishes that payload
  through `ConfigMap/infernix-demo-config` whenever the active topology has cluster-resident
  consumers and mounts the same filename inside those workloads at `/opt/build/infernix-substrate.dhall`
- each daemon reads its staged substrate `.dhall` at startup; automatic file-watching or reload is
  not part of the supported contract
- the supported materialization path can emit `demo_ui = false` with
  `--demo-ui false`; omitting that flag keeps the default demo-enabled output
- the routed demo app remains cluster-resident when enabled, and the Apple routed path closes
  around an explicit cluster-daemon-to-host-daemon inference batch bridge rather than
  cluster-resident Apple inference execution
- supported entrypoints no longer carry the old cross-substrate default matrix, cluster bring-up
  fallbacks, direct tool-route compatibility handlers, or generic inference-success fallback;
  routed Harbor, MinIO, and Pulsar checks require the real Gateway-backed upstream behavior, while
  inference coverage goes through the typed adapter harness selected by the active substrate file.
  The repo-local Pulsar topic spool remains only a harness-oriented path for endpoint-absent unit
  or isolated daemon checks, not a substitute for routed cluster validation
- integration coverage is driven by the comprehensive model, format, and engine matrix in
  `README.md`: one substrate-aware integration suite reads the active substrate from `.dhall`,
  chooses the corresponding engine binding for each supported row or reference, and runs at least
  one assertion for every such row
- Playwright E2E remains substrate-agnostic at the browser layer and relies on `infernix-demo` to
  read the same `.dhall` and dispatch the correct engine for the active substrate
- Harbor-first bootstrap, mandatory local HA platform services, Gateway-owned routing, operator-run
  Patroni PostgreSQL, manual `infernix-manual` storage, Haskell-owned frontend contracts, the
  shared Python adapter project, and untracked generated outputs all remain mandatory doctrine
- supported validation is substrate-specific: integration, E2E, and `test all` run their complete
  supported suites against the built and deployed substrate, and test reports name that substrate
  explicitly instead of implying matrix-wide coverage
- the supported control plane keeps one Haskell command registry,
  binary-owned lifecycle and validation orchestration, the current `ormolu` plus `hlint` plus
  `cabal format` style stack, and the existing files or docs or chart or proto validation
  entrypoints; shell bootstrap responsibility is limited to prerequisite and launcher setup
- every `infernix service` daemon remains startup-configured and Pulsar-driven without a separate
  admin-HTTP, hot-reload, or typed-event-ledger subsystem in the supported contract
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
| 7 | 0-6 | adds the multi-user durable-context demo application on top of the platform: Keycloak self-signup, WebSocket post-login transport, Pulsar-backed conversation log per context, MinIO-backed artifact upload/download/render-or-download, a Haskell-first logic boundary surfaced to PureScript via `purescript-bridge`, and the supported three-role daemon split (stateless `infernix-demo`, stateless `infernix-coordinator`, one-per-node `infernix-engine`) replacing today's fused `infernix-service` Deployment. The platform contract Phase 7 builds on is implemented in code; its real-cluster validation evidence is currently pending on the new Apple Silicon host (see the Apple Silicon validation reset note in the Current Repo Assessment) |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
