# Infernix Development Plan

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md)

> **Purpose**: Provide the single execution-ordered development plan for `infernix`, including
> phase status, repository-shape decisions, validation gates, and documentation obligations.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Common-Shape Reopen (Pulsar ML-Workflow convergence)

`infernix` and the `jitML` sister project are converging on one shared contract,
[../documents/architecture/pulsar_ml_workflow.md](../documents/architecture/pulsar_ml_workflow.md)
(Engine / Coordinator / Webapp roles, a derived topic algebra, the `Work*` envelope
family, the artifact + `.ready` readiness contract, websocket snapshot/patch, and a
reflected-Dhall-schema one-binary role model). This reopens three surfaces, each
tracked in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md):

- **Phase 4** — the **Coordinator** gains explicit topic-lifecycle ownership
  (replacing implicit broker auto-create), and the binary emits its own reflected
  Dhall schema.
- **Phase 6** — phase validation moves to **single-accelerator-per-phase** (standards
  §Q): one of `apple-silicon` or `linux-gpu` plus `linux-cpu`, never both;
  `cohort-validation-waves.md` is repurposed as per-accelerator attestation ledgers.
- **Phase 7** — the demo frontend folds into a one-binary **Webapp** role.

Each reopened phase carries the convergence work in its `Remaining Work`.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Maintenance rules for the development plan |
| [00-overview.md](00-overview.md) | Architecture baseline, hard constraints, substrate contract, and canonical repository shape |
| [system-components.md](system-components.md) | Authoritative component inventory and state-location map |
| [cohort-validation-waves.md](cohort-validation-waves.md) | Per-accelerator attestation ledgers (one per accelerator) under Section Q's single-accelerator-per-phase rule; a `linux-cpu` aggregation phase merges them |
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite bootstrap plus the substrate-doctrine documentation reset |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, CLI contract, build-root doctrine, launcher ownership, and substrate-selection closure |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Harbor-first image flow, substrate `.dhall` publication, Linux launcher closure, and lifecycle-progress hardening |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and the Apple cluster-to-host inference bridge for routed demo traffic |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, cluster-daemon request consumption, Apple host inference execution, staged `.dhall` role control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, Apple host-backed browser dispatch, and Playwright ownership |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, README-matrix-driven single-substrate validation, Apple cluster-to-host daemon split coverage, root-doc closure, HA validation, and false-negative doctrine hardening |
| [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) | Multi-user durable-context demo: Keycloak auth, WebSocket transport, Pulsar-backed conversation history, MinIO artifact upload/download/render-or-download, Haskell-first logic via purescript-bridge, and the three-role daemon split (stateless frontend, stateless coordinator, substrate-specific engine pools) with an HA-first chart |
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
2. The listed validation gates pass on the supported execution path, with the phase's **single
   chosen accelerator** cohort (`apple-silicon` **or** `linux-gpu`) plus `linux-cpu` recorded when
   substrate-aware behavior is in scope — never both accelerators against one phase.
3. The governed docs named in `Docs to update` match the implementation.
4. No remaining cleanup or compatibility surface is left unstated.
5. Cleanup promised by the sprint is reflected in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

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

All phase implementation work closes around the implemented worktree. Phase 3 Sprint 3.12 and
[Wave F](cohort-validation-waves.md) closed on the recorded validation after native `linux/arm64` validation
through the already selected arm64 Docker daemon on this Apple Silicon machine. The repository implements the
staged-substrate architecture, the baked Linux outer-container launcher,
the mandatory HA platform services, the Gateway-owned routed edge, the shared Python adapter
project, the Haskell-owned browser-contract generation path, the substrate-specific validation
surface, and the current Apple split-executor topology described below. The runtime-routing
code-side target has landed around substrate-neutral engine pools: the coordinator remains the
production router, normal pools use Pulsar `Shared` plus broker-native backpressure, pinned routes
use derived per-member topics with `Exclusive`, Linux members are Kubernetes workloads, and Apple
members are same-binary host daemons selected by stable host id. Legacy raw-topic compatibility
surfaces remain tracked for deletion while Wave J supplies real-cluster proof.

The repository implements the substrate-file doctrine described by this plan. Supported flows
stage one `infernix-substrate.dhall` beside the active build root through the `infernix` command
that needs it; the explicit
`infernix internal materialize-substrate ...` helpers remain the direct restaging or inspection
surface. The Linux substrate Dockerfile materializes a build-arg-selected substrate file inside
the image overlay during image build, and supported Compose runs keep that active build root
image-local instead of bind-mounting the host `./.build/` tree. Focused `infernix lint ...` and
`infernix docs check` remain substrate-file independent. The final substrate payload also
distinguishes cluster and host daemon
roles: cluster-role configs name the substrate, request and result topics, and the engine-pool graph,
while host-role Apple configs include the routed Pulsar connection details and the host member's pool
membership. Cluster publication mirrors the
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
private `kind` network for observation. The Apple split-executor contract is implemented on
`apple-silicon`: `cluster up` keeps Harbor, MinIO, Pulsar, PostgreSQL, Envoy Gateway, the optional
clustered `infernix-demo` surface, and cluster `infernix-coordinator` Deployment in Kind; Apple
inference execution remains host-native. The pool target replaces the single Apple host topic and
Linux-specific per-engine topic special cases with topics derived from `(runtimeMode, pool id, model
id, optional member id)`. The generated final-phase Helm values use role-specific
coordinator and engine knobs; Apple sets the cluster engine replica count to 0 because Apple engine
members are host-native. Pulsar-owned topics, `Shared` pool subscriptions, `Exclusive` pinned routes,
and acknowledgement handling are the ordering and ownership boundary for request handoff,
inference, and result publication. The worker dispatches through the selected engine binding,
fetches model weights lazily from `infernix-models`, and publishes the typed per-family result
surface; hardware proof for real output remains in cohort gates, while unsupported adapter ids fail
fast instead of falling through to a generic success path. The worktree omits the
direct Harbor, MinIO, and Pulsar tool-route compatibility handlers, requires the real routed
upstream behavior in integration, and persists Linux cluster state before later rollout phases.
Bootstrap shells no longer restage the active substrate payload before lifecycle commands; that
preflight belongs to the binary command that needs the file. The Haskell style bootstrap
installs `ormolu` and `hlint` through `cabal install` against the project `ghc-9.12.4`
toolchain into `./.build/haskell-style-tools/bin/`; the Linux substrate image installs a single
`ghc-9.12.4` toolchain. The
supported Linux outer-container launcher reuses the image-local
`/opt/infernix/chart/charts/` archive cache,
hydrates the MinIO dependency through the supported direct tarball path instead of Docker
Hub-backed OCI metadata, and detects the known stale Pulsar or ZooKeeper epoch mismatch by
resetting only the retained Pulsar claim roots and retrying `cluster up` once. The Apple
clean-host bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables before
direct `cabal install`, reconciles Homebrew `protoc`, and lets Apple adapter setup or validation
paths reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command plus a
user-local Poetry bootstrap on demand. The supported doctrine now requires Docker-backed Apple
work to use an already selected native arm64 Docker daemon and forbids creating or switching
Docker contexts, creating Colima VMs, or using cross-architecture emulation; Phase 1 Sprint 1.12
replaced the previous Colima reconciliation path with selected Docker-context and
daemon-architecture validation and closed on the recorded validation with both the positive Apple lifecycle
gate and the negative no-daemon boundary gate. Phase 1 reopens the Apple Metal/Core ML
materialization lane: Sprint 1.14 removes the prior Sprint 1.13 `tart` / `hostTart` /
`AppleTart` implementation from the current host-tool schema and retargets the retained
`materialize-metal-engines` command to typed engine-artifact manifests. The materializer now writes
the fixed host Metal runtime bridge source and smoke command plus the `coreml-native` runner source
and smoke command; the current Apple host pass executes both installed smoke commands from
`./.data/engines/<adapterId>/` and passes integration, routed e2e, and aggregate `test all` against
the validation-wrapper state. Wave I still owns real native-payload replacement on the reopened
real-output surface. The target has no Tart VM, user keychain dependency, host Xcode UI flow, or
request-time toolchain install. The
Poetry bootstrap may reuse an already available
compatible Python 3.12+ executable when one passes the implemented version check. Routed Apple
Playwright validation runs host-native `npm exec` against the published `127.0.0.1` edge port,
and the in-image
Playwright runtime no longer bakes a conflicting `NO_COLOR` default. The shared cluster lifecycle
now surfaces explicit in-progress phase, child-operation detail, and heartbeat data through
`cluster status` during monitored Docker build, Harbor publication, Harbor-backed final-image
preload, and Apple retained-state replay steps; explicit substrate materialization writes the
staged `infernix-substrate.dhall` atomically so concurrent status readers do not observe truncated
payloads; retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
replicas from the current Patroni leader when timeline drift leaves replicas unready after
promotion; and all lanes scrub operator-managed Patroni claim roots before recreating claim
directories and after retained-state sync so regenerated database credentials are not paired with
stale Harbor or Keycloak data directories. The shared lifecycle skips broad pre-Harbor support-image
preloads and follows the
stricter Harbor-first target where supported lanes hydrate and stream only the narrow Harbor
warmup dependency set into Kind before Helm warmup, only Harbor-required services may pull
upstream before Harbor is responsive, and every remaining image, including the active `infernix`
runtime image, is loaded into Harbor before final rollout. Legacy validation proof points are
kept only in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md); current
replacement proof points are recorded by the Wave A Apple cohort closure and the Wave C native
Linux/CUDA cohort closure below. Sprint 6.26 closes the buildx, npm, GHCup shell-profile,
Python packaging, and
Playwright script warning cleanup with the governed `linux-gpu` lifecycle rerun complete.
Sprint 6.27 closes the staged-substrate format cleanup: `infernix-substrate.dhall` is now a real
typed Dhall record decoded in-process by the `dhall` Haskell library, with the schema documented at
`dhall/InfernixSubstrate.dhall`.

**Cohort validation status (present development host = Apple Silicon).** The current workspace is
on Apple Silicon (`Darwin arm64`) with the selected Docker daemon reporting native `linux/arm64`.
Consistent with the two-axis doctrine — implement and run code-side closure on whichever single
machine is present — Apple host-native gates proceed here without a machine switch, and CUDA Linux
Wave I work remains scheduled for a native CUDA Linux host. The current Apple-side Wave I pass
builds the host binaries, materializes the `apple-silicon` substrate and typed Metal/Core ML engine
manifests, proves the generated Metal runtime bridge smoke (`Metal runtime probe passed on Apple
M1 Max`) plus the installed `coreml-native` smoke (`Core ML runtime probe passed`), and writes
smoke-capable Apple native validation runners for the allowlisted native adapter ids. The latest
Apple `./.build/infernix test integration` rerun passed after rebuilding
the changed repo-owned image once, then reusing the stamped `infernix-linux-cpu:local` image on
the edge-port rediscovery cluster cycles. The run completed the active Apple model catalog, cache
lifecycle, service runtime loop, durable Pulsar topic families, pinned Apple host-engine
`Exclusive` duplicate-consumer rejection through an isolated `infernix service --config` file,
same-machine Apple host-member coexistence on one derived `Shared` pool subscription with two real
Pulsar consumers and a completed request, the single-host logical `Shared`
backlog/backpressure harness, production-shape Apple `demo_ui = false` route/publication
assertions, and edge-port conflict rediscovery. A following Apple
`./.build/infernix test e2e` rerun passed 9/9 routed Playwright tests after the dispatcher and
browser matrix carried uploaded input objects for speech, source-separation, audio-to-MIDI, music,
and OMR rows; an earlier aggregate `./.build/infernix test all` attempt had reached Playwright and
failed on the missing input-object reference for `audio-demucs-htdemucs`. A later aggregate rerun
then reached the Playwright matrix and failed on `llm-qwen25-safetensors` because the engine-side
bootstrap wait treated a cold Hugging Face snapshot as failed after 60 seconds; current source makes
that wait a named 900-second envelope and aligns the browser result wait with it. The follow-up
focused Apple `./.build/infernix test e2e` rerun passed 9/9 against rebuilt cluster image digest
`sha256-ed34da86992bb1a4d285f00feb77051d12eb4fa594b7bb34ed73561a027b1a71`, including completed
Qwen bootstrap/inference and every active Apple catalog row. The subsequent full Apple
`./.build/infernix test all` aggregate passed lint, unit (Haskell plus web 71/71), integration, and
9/9 routed Playwright against rebuilt cluster image digest
`sha256-f4a30f4e177206b64ce5a0d3abea8d72a8bdbe637148530e1619bdf5ce8ae7c3`; the aggregate matrix
completed Qwen, object-input audio/tool rows, and every active Apple catalog row, then replayed
retained state and deleted the Kind cluster cleanly. The native rows still use deterministic
validation-wrapper payloads while real native payloads remain Wave I work. Follow-up probing of the
earlier long Docker interval showed active Cabal dependency compilation, image export, Harbor push,
and Helm/Pulsar readiness waits rather than a Docker daemon deadlock; current source adds
source-fingerprint cluster-image reuse and Dockerfile dependency-layer caching for that path. The
2026-06-16 Linux CPU rebuilt-image integration pass on the native arm64 Docker lane proves
two-worker engine-pool placement, unique-topic `Shared` backlog/backpressure, pod replacement,
node drain, anti-affinity, lifecycle rebinding, demo-off publication, Linux CPU framework-venv
smoke paths, and clean teardown against image digest
`sha256:ae06ba36fe1f3ffecf48aa86c34abeb0dd1c98cabb030a7da783681ac87a81df`. CUDA Linux/GPU and real
native payloads still own the remaining real-output full-suite proof.
The legacy dated proof points (the recorded validation) are inventoried in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical
Validation Evidence"; the underlying contracts they exercised still describe supported behavior,
but the proof points themselves are not current. Revalidation is tracked by
[cohort-validation-waves.md](cohort-validation-waves.md). [Wave A](cohort-validation-waves.md)
(Apple cohort) closed the recorded validation with `cabal test infernix-integration` full PASS plus 5/6
Playwright e2e PASS; Waves A.1 and A.2 subsequently closed the routed
Playwright residuals with 7/7 e2e PASS, and Wave A.3 closed Apple engine-lock chaos.
[Wave H](cohort-validation-waves.md) then re-confirmed the full Apple cohort lifecycle on the
Apple cohort host on 2026-06-09 from a clean build root: the build, lint/style/unit gates, the
explicit `cluster up` → `cluster status` → `cluster down` lifecycle with retained-state replay,
`infernix test integration`, `infernix test e2e` 9/9, and aggregate `infernix test all`.
[Wave C](cohort-validation-waves.md) closed the recorded validation on a native Linux/CUDA host: the
portable `linux-cpu` full-suite gate passed on the recorded validation and the real `linux-gpu`
full-suite gate passed on the recorded validation. [Wave F](cohort-validation-waves.md) closed the recorded validation
with native `linux/arm64` `linux-cpu` validation through the selected Docker daemon
(`server=linux/arm64`, runtime probe `aarch64` / `arm64`) and a full
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all`
PASS.

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

> **Implement in natural phase order on whichever single machine is present. The cohort gate is a
> batched wave — the only supported machine switch — not a per-sprint or per-phase trigger.** Every
> open phase and sprint has two independent axes. *Code-side closure* (Axis 1) is the implementation
> plus the machine-independent gate set — `cabal build all`, `cabal test infernix-unit`,
> `cabal test infernix-haskell-style`, `infernix lint files/docs/chart/proto`, `infernix docs
> check`, the web unit suite, and `poetry run check-code`; completed in natural order on one
> machine, it is the gate to begin the *next* phase's implementation. *Cohort sign-off* (Axis 2) is
> the hardware-specific full-suite — Apple Metal including headless Metal/Core ML materialization,
> and CUDA GPU runs — batched once per closure cycle against frozen code and tracked in
> `cohort-validation-waves.md`; it is the gate for `Done` and never the gate for moving on. **The
> next action for any open phase is always its remaining code-side closure on the machine you
> already have; do not switch machines to "validate the open phase." The machine switch happens only
> at a scheduled wave boundary, once per cohort.** A deliverable that is intrinsically
> hardware-bound — for example the Apple-only Metal runtime bridge probe and Core ML materialization
> smoke of Phase 1 Sprint 1.14 — is named as
> such in its `Code-side closure` field and is exercised inside its cohort's wave, never pre-claimed
> as machine-independent.

Phase work should stay on the current cohort until a coherent slice is ready. Apple-owned changes
validate locally on Apple and queue CUDA Linux closure; Linux, CUDA, chart, and outer-container
changes validate locally on CUDA Linux and queue Apple closure. Validation-only hardware residuals
are queued in [cohort-validation-waves.md](cohort-validation-waves.md), and the counterpart run is
a scheduled closure batch, not a per-sprint machine switch.

Full phase closure requires both relevant hardware cohorts to rerun the complete gates against the
same phase state. `linux-cpu` remains a portable CPU-only lane for native Linux amd64 and native
Linux arm64 hosts, but it does not run through Apple Silicon emulation and does not replace the
CUDA Linux cohort when GPU behavior, CUDA image construction, `nvkind`, or NVIDIA scheduling is in
scope.

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Done (Sprints 0.1-0.10 closed; declarative-state documentation reconciliation complete) | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Active (Sprint 1.13's Tart implementation is historical and removed from the current host-tool schema; Sprint 1.14 is code-side closed for typed engine-artifact manifests, the fixed host Metal bridge, the `coreml-native` source/smoke command, and smoke-capable Apple native validation-runner roots. The current Apple host pass proves Tart-free manifest materialization, generated Metal bridge smoke, installed Core ML runtime-load smoke, native validation-wrapper materialization, integration, focused e2e after the object-input dispatch and cold-bootstrap wait fixes, and aggregate `test all` against the validation-wrapper state. Sprints 1.1-1.12 remain closed, including the native-only Apple Docker boundary; Wave I remains open for paired real native-payload cohort sign-off.) | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Done (Sprints 2.10-2.13 lifecycle, retained-state, bootstrap-boundary, and host-manifest closure validated by Apple Wave A and CUDA Linux Wave C) | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Done (Sprint 3.12 native `linux-cpu` architecture selector and native arm64 publication path closed in Wave F on the recorded validation through the already selected arm64 Docker daemon; Sprints 3.10–3.11 validated by Apple Wave A/A.2 and CUDA Linux Wave C) | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Active (Sprints 4.1-4.17 have prior code-side evidence for real-output, per-engine routing, and Linux image-owned native-root fallback; Sprint 4.18 reopens engine-artifact manifests and now materializes Apple native validation-wrapper roots in addition to Linux runner-contract roots, with overlay-safe fresh-container Linux native materializer reruns validated on the native arm64 Docker lane and 2026-06-15 native CUDA Linux baked-image validation covering `./bootstrap/linux-gpu.sh build`, unit/lint/docs/materializer gates, and direct runner-contract normal invocations. Current source also threads non-secret model-cache hints to native runners, makes model-cache-aware Linux runner-contract payloads exit 75 until the requested `.ready` sentinel exists, lets artifact runners return local file markers for Haskell-owned MinIO upload, maps native exit 75 to `model_cache_not_populated`, and bakes Linux CPU `transformers`/`pytorch` framework venvs for smoke validation. Sprint 4.19 is code-side closed for substrate-neutral engine pools and derived pool/model topics; Apple integration executes the single-host logical `Shared` backlog harness, and Linux CPU integration proves Kubernetes pool placement/backpressure. Wave I owns real Linux and Apple native payload replacement, routed per-engine GPU evidence, and full real-output reruns; Wave J still owns Linux GPU/CUDA cohort validation, while physical Apple multi-host evidence is hardware-deferred.) | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Done (Sprints 5.1-5.10 closed with demo backend, Python adapter, and web/Node no-env-var path validated by Apple Wave A/A.2 and CUDA Linux Wave C) | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Active (Sprints 6.1, 6.4, 6.5, and 6.7-6.30 remain closed; Sprints 6.2/6.3/6.6 carry the real-output cohort residual; Sprint 6.31 is code-side closed for README/generated-catalog matrix-drift linting; Sprint 6.32 is code-side closed for impossible pool-routing states and now has Apple evidence for pinned `Exclusive`, same-machine `Shared` coexistence, demo-off assertions, and live single-host logical `Shared` backlog/backpressure execution. Linux CPU integration proves Kubernetes placement/backpressure; Wave J still awaits Linux GPU/CUDA cohort validation, and physical Apple multi-host evidence is hardware-deferred.) | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |
| 7 | Demo App Multi-User Durable Context | Active (Sprints 7.1-7.22 remain closed; Sprint 7.23 is superseded as an Apple singleton stopgap; Sprint 7.24 is code-side closed for startup-time substrate-neutral engine pools, with pinned Apple `Exclusive` duplicate rejection, same-machine Apple `Shared` coexistence, Apple production demo-off assertions, and live single-host logical `Shared` backlog/backpressure execution. Linux CPU integration proves placement/backpressure and durable replacement/drain cases; Wave J still owns Linux GPU/CUDA cohort validation, and physical Apple multi-host evidence is hardware-deferred. Desired-state hot reload remains future work.) | [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) |

> **Note**: Phase statuses describe current repository state. Earlier governed phases may remain
> `Active` or `Blocked` for named follow-ons while later phases can be `Done` when their owned work
> and validation are complete. Validation-only hardware blockers are scheduled through
> [cohort-validation-waves.md](cohort-validation-waves.md) instead of forcing repeated machine
> switches during unrelated same-cohort work.
> Each phase 1-7 gained a cleanup sprint that eliminates the env-var fallbacks and
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
| 7 | 0-6 | adds the multi-user durable-context demo application on top of the platform: Keycloak self-signup, WebSocket post-login transport, Pulsar-backed conversation log per context, MinIO-backed artifact upload/download/render-or-download, a Haskell-first logic boundary surfaced to PureScript via `purescript-bridge`, and the supported three-role daemon split (stateless `infernix-demo`, stateless `infernix-coordinator`, substrate-specific engine pools). The platform contract Phase 7 builds on is implemented in code; Apple plus native Linux/CUDA real-cluster validation evidence is recorded in Waves A-C, Sprint 7.8 runtime KV-cache plus `Infernix.Runtime.Daemon` closure is recorded in Wave E, and Sprint 7.24 reopens pool assignment and broker-native backpressure. |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
