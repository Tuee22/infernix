# Infernix Development Plan

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md)

> **Purpose**: Provide the single execution-ordered development plan for `infernix`, including
> phase status, repository-shape decisions, validation gates, and documentation obligations.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Current execution gate

Phase 1 is the sole open implementation gate. Sprints 1.1 through 1.19 retain their recorded
closure; Sprints 1.20 through 1.29 are `Active`. Every gate ahead of the cohort is GREEN on one
frozen identity: the governed Apple build, the whole aggregate lint, the full unit suite, the
standalone `lint files`, `lint docs`, `lint chart`, `lint proto`, `lint plan`, and `docs check`
commands, a repo-wide `git diff --check`, the Darwin build-memory measurement, a complete
`internal materialize-metal-engines` emitting all seven engine artifacts, and the fixed
`internal validate-darwin-audiveris-cancellation` and
`internal validate-darwin-installed-python-source-isolation` validators.

The cohort behind them is blocked rather than pending. `test all` reaches its `integration` stage
and the cluster image build fails while preparing the per-engine Python environment for
`python/engines/transformers`. Sprint 1.26 made that refusal name its observation, and the
measurement it produced identified the fault rather than a number to raise: a sealed bounded run
points `PYTHONHOME` at the sealed copy of Poetry's own environment, Poetry adopts that copy as the
project's environment, and the engine's whole framework payload lands in a generation that is about
to be retired — so the interpreter the readiness marker requires is never created and the retirement
exceeds the bound its creation fit. Sprint 1.27 gives the project its own environment before the
sealed run can choose one. With that correction the lane reaches
`internal materialize-linux-native-engines`, where the loader-closure producer cannot resolve a
JavaCPP cross-jar dependency that the runtime satisfies from its own namespace, which Sprint 1.28
binds. With that correction the routed image build completes and the Apple cohort reaches its
per-model inference stage, where the host engine daemon died of a heap overflow because the harness
started it by re-executing its own image, and every non-unit test component carries a baked
1024 MiB heap cap the declared ledger says that daemon must not have. Sprint 1.29 keeps the two
process images apart. Each sprint's own section in
[phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
owns the detail.

Phase 0 is `Done`. Its final sprint landed `infernix lint plan`, which implements the Section C,
D, I, J, and Q scans the standards had declared only in prose, drove the corpus to zero against
them, and wired the scans into `infernix test lint` so a plan change cannot close with them unread.
Sprints 0.19 and 0.21 re-closed on the corrected host-memory ledger: the toolchain account and the
inference partition are alternative occupants of one claimable pool, and the account is admitted
against observed availability and a foreign-claimant census rather than against declared capacity
alone. Phase 1 Sprint 1.21 owns the implementation of that admission clause.

Phase 1's machine-independent gate set — the governed Apple build, `infernix test lint`,
`infernix test unit`, the standalone `lint files`, `lint docs`, `lint chart`, `lint proto`,
`lint plan`, and `docs check` commands, and a repo-wide `git diff --check` — passes on current
source. The defect that blocked `internal materialize-metal-engines` is closed and the materializer
run itself is now GREEN: the Audiveris invocation declines JavaCPP symbolic-link creation, so the
extraction cache holds no symlink and the sealed payload is relocation-invariant, which no repair
pass could make it, and the run emits all seven engine artifacts including the previously refused
`jvm-native`. Both specialized Darwin validators and the Darwin build-memory measurement are GREEN
on the same identity. The cohort behind them is blocked by Sprint 1.29.

Phase 1 closes on one frozen source identity, gated in this order: the governed Apple build, the
whole aggregate lint, the full unit suite, the standalone `lint files`, `lint docs`, `lint chart`,
`lint proto`, and `docs check` commands, a repo-wide `git diff --check`, then
`internal materialize-metal-engines` with the specialized Darwin validators, then the cohort.
[Wave Y](cohort-validation-waves.md) owns that cohort: schema-complete Apple and paired
source-matched `linux-cpu` real-output records for `llm-smollm2-safetensors`,
`audio-demucs-htdemucs`, `audio-open-unmix`, `music-mt3-infer`, `music-mr-mt3`, `music-omnizart`,
and `audio-bark-small`, with Apple additionally owning the typed `image-sdxl-turbo` refusal and the
full `integration`, `e2e`, and `all` receipts. [Wave AA](cohort-validation-waves.md) is closed for
Sprint 1.21's Stage 1 and its Darwin build-memory proof, and is not rerun.

Phases 2 through 9 are blocked in strict numerical order, each by its immediate predecessor. Each
retains the implementation state its own phase document records behind that blocker.

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

Phase 0 owns the governed `documents/` suite, the plan standards, and the validators that enforce
both, and is `Done` with no open sprint. Phase 1 is the sole open implementation gate, at Sprints
1.20 through 1.26, and [Wave Y](cohort-validation-waves.md) owns its remaining Apple and paired
`linux-cpu` attestation. Phases 2 through 9 are blocked in strict numerical order behind it, each
keeping the implementation and evidence state its own phase document records.

The repository implements the explicit-init runtime-config architecture, the baked Linux
outer-container launcher, the single-instance platform services, the Gateway-owned routed edge, the
shared Python adapter project, the Haskell-owned browser-contract generation path, the
substrate-specific validation surface, and the Apple split-executor topology described below.
Runtime routing closes around substrate-neutral engine pools: the coordinator is the production
router, normal pools use Pulsar `Shared` plus broker-native backpressure, pinned routes use derived
per-member topics with `Exclusive`, Linux members are Kubernetes workloads, and Apple members are
same-binary host daemons selected by stable host id. Legacy raw-topic compatibility surfaces, the
demo-off coordinator gate, and the two-binary `infernix` / `infernix-demo` split are all removed;
the supported topology is the one-binary model with the demo frontend served by the `Webapp` role
through `infernix service --role webapp`.

Runtime admission is serialized and FIFO, with no catalog-wide fail-fast and no hardcoded budget
floor, and it happens on the machine that will execute the work rather than on the coordinator: the
observation admission consumes is package-owned and derived from live capacity probes, so a routing-only role
cannot reach admission at all. Budgets carry typed `InferenceMemoryBudget` semantics, admission
extends to Linux CPU pod memory and Linux GPU VRAM, and a capacity failure publishes a typed
`InferenceError.ModelMemoryLimitExceeded` payload with explicit MiB quantities from the machine that
refused the work. The Apple `materialize-metal-engines` prerequisite, the pytorch-engine
`mt3-infer <0.2` and linux-arm64 `demucs <4.1` dependency-drift caps, and the `docker/Dockerfile`
engine-venv fail-fast that turns a silently masked venv-install failure into a build failure are
part of that supported surface.

The repository implements the runtime-config doctrine described by this plan. `infernix init`
creates the operator's repo-root `./infernix.dhall` and `./infernix-host.dhall`;
`infernix test init` creates the harness input `./infernix.test.dhall`. Ordinary config-dependent
commands validate the initialized file and fail fast naming the required init instead of
auto-materializing it. The Linux substrate image uses binary-owned generation for its image-local
defaults, not an ordinary-command preflight path. Focused `infernix lint ...` and `infernix docs
check` remain config-independent. The runtime payload distinguishes cluster and host daemon roles:
cluster-role configs name the substrate, request and result topics, and the engine-pool graph, while
host-role Apple configs include the routed Pulsar connection details and the host member's pool
membership.
Cluster publication mirrors the cluster-role payload locally under
`./.data/runtime/configmaps/infernix-demo-config/` and mounts it inside cluster workloads at the
compatibility path `/opt/build/infernix-substrate.dhall`, while Apple host daemons read repo-root
`./infernix.dhall`. The file is a typed Dhall record decoded in-process by the `dhall` Haskell
library, and its schema is reflected from the substrate decoder type
(`infernix internal dhall-schema substrate`) rather than from any tracked schema file.

`infernix test all` runs the full supported validation suite for the active initialized substrate.
Full repository substrate closure comes from separate governed reruns for `apple-silicon`,
`linux-cpu`, and `linux-gpu`, not from one implicit cross-substrate matrix invocation. The generated
file, `cluster status`, publication JSON, and generated browser contracts serialize that active
substrate under `runtimeMode` field names. `cluster status` does not mutate Kubernetes resources,
publication state, or authoritative repo-local state; the accepted Linux outer-container exception
is an idempotent Docker network membership repair that attaches the fresh launcher container to the
private `kind` network for observation.

The Apple split-executor contract is implemented on `apple-silicon`: `cluster up` keeps Harbor,
MinIO, Pulsar, PostgreSQL, Envoy Gateway, the optional clustered `infernix-demo` surface, and the
cluster `infernix-coordinator` Deployment in Kind, while Apple inference execution remains
host-native. Pool topics are derived from `(runtimeMode, pool id, model id, optional member id)`
rather than from a single Apple host topic or Linux-specific per-engine special cases. The generated
final-phase Helm values use role-specific coordinator and engine knobs; Apple sets the cluster
engine replica count to 0 because Apple engine members are host-native. Pulsar-owned topics,
`Shared` pool subscriptions, `Exclusive` pinned routes, and acknowledgement handling are the
ordering and ownership boundary for request handoff, inference, and result publication. The
coordinator eagerly stages the configured model set in `infernix-models` behind the
`warm-model-cache` barrier; workers hydrate their derived local caches from those staged objects and
publish the typed per-family result surface, while unsupported adapter ids fail fast instead of
falling through to a generic success path. The selected `linux-gpu` plus `linux-cpu` real-output
proof closed under [Wave I](cohort-validation-waves.md).

The worktree omits the direct Harbor, MinIO, and Pulsar tool-route compatibility handlers, requires
the real routed upstream behavior in integration, and persists Linux cluster state before later
rollout phases. Bootstrap shells do not restage the active substrate payload before lifecycle
commands; that preflight belongs to the binary command that needs the file. The dedicated Haskell
style component links pinned `ormolu`, `hlint`, and `Cabal` libraries and invokes them in-process
over one exact source inventory; it has no runtime tool install, host-manifest formatter field, or
nested style process. The Linux substrate image installs a single `ghc-9.12.4` toolchain. The
supported Linux outer-container launcher reuses the image-local `/opt/infernix/chart/charts/`
archive cache, hydrates the MinIO dependency through the supported direct tarball path instead of
Docker Hub-backed OCI metadata, and detects the known stale Pulsar or ZooKeeper epoch mismatch by
resetting only the retained Pulsar claim roots and retrying, with a bounded number of such resets
per `cluster up`.

The Apple clean-host bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables
before its fixed stage-0 measured, seed-accounted build handoff. Phase 1 Sprint 1.24 consumes the
exact tracked Haskell protobuf snapshot, so Darwin installs and starts no standalone compiler or
plugin. Apple adapter setup and validation paths reconcile the Homebrew-managed `python@3.12`
formula and `python3.12` command plus a user-local Poetry bootstrap on demand, and that bootstrap
may reuse an already available compatible Python 3.12+ executable when one passes the implemented
version check.

Docker-backed Apple work uses an already selected native arm64 Docker daemon; creating or switching
Docker contexts, creating Colima VMs, and cross-architecture emulation are all outside the supported
doctrine. Phase 1 Sprint 1.12 replaced the previous Colima reconciliation path with selected
Docker-context and daemon-architecture validation, covering both the positive Apple lifecycle gate
and the negative no-daemon boundary gate. Phase 1 Sprint 1.14 closes the Apple Metal/Core ML
materialization lane under the Section Q single-accelerator rule: no `tart` / `hostTart` /
`AppleTart` implementation exists in the host-tool schema, and the retained
`materialize-metal-engines` command targets typed engine-artifact manifests. Phase 1 Sprint 1.15
builds on that lane with real Apple native runner roots for Core ML, MLX, llama.cpp/whisper.cpp
Metal, CTranslate2, ONNX Runtime, and Audiveris, plus indexed native snapshot hydration for Core ML
Stable Diffusion; that native-engine scope closed under [Wave L](cohort-validation-waves.md). The
target has no Tart VM, user keychain dependency, host Xcode UI flow, or request-time toolchain
install.

Routed Apple Playwright validation runs host-native `npm exec` against the published `127.0.0.1`
edge port, and the in-image Playwright runtime bakes no conflicting `NO_COLOR` default. The shared
cluster lifecycle surfaces explicit in-progress phase, child-operation detail, and heartbeat data
through `cluster status` during monitored Docker build, Harbor publication, Harbor-backed
final-image preload, and Apple retained-state replay steps; explicit substrate materialization
writes the staged `infernix.dhall` atomically so concurrent status readers do not observe truncated
payloads; retained-state Apple reruns reinitialize stopped Harbor PostgreSQL replicas from the
current Patroni leader when timeline drift leaves replicas unready after promotion; and all lanes
scrub operator-managed Patroni claim roots before recreating claim directories and after
retained-state sync, so regenerated database credentials are never paired with stale Harbor or
Keycloak data directories. The shared lifecycle skips broad pre-Harbor support-image preloads and
follows the stricter Harbor-first target: supported lanes hydrate and stream only the narrow Harbor
warmup dependency set into Kind before Helm warmup, only Harbor-required services may pull upstream
before Harbor is responsive, and every remaining image, including the active `infernix` runtime
image, is loaded into Harbor before final rollout.

Legacy validation proof points live only in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical
Validation Evidence"; the contracts they exercised still describe supported behavior, but the proof
points themselves are not current. Every current per-lane attestation lives in
[cohort-validation-waves.md](cohort-validation-waves.md), which is the only place a wave's evidence
is recorded.

The production and routed validation path uses real Pulsar transport. The repository keeps the
repo-local topic spool under `./.data/runtime/pulsar/` as a deliberate harness surface for
unit-level checks or manually isolated daemon runs that intentionally omit Pulsar endpoint
configuration; that harness is not routed cluster evidence and does not replace the Gateway-backed
Pulsar assertions in integration or E2E validation.

Beyond the Phase 9 admin overview (`/api/admin/overview`) and per-user personal dashboard, no
general observability stack (metrics, tracing, log aggregation) is deployed.
Monitoring is not a supported first-class surface.

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

## Current Phase Overview

| Phase | Current status | Current gate and retained implementation state |
|-------|----------------|----------------------------------------|
| 0 | Done | Every sprint is closed on the machine-independent gate set. Sprints 0.19 and 0.21 re-closed on the corrected host-memory ledger: one claimable pool with two alternative occupants, admission against observed availability plus a foreign-claimant census, the account scoped to the governed Cabal invocation, and an Apple lane that engages no operating-system mechanism at all. `infernix lint plan` implements the Section C, D, I, J, and Q scans mechanically, the corpus reports them at zero, and the scans run inside `infernix test lint`, so the standards are enforced rather than remembered. Machine-independent — this phase carries no accelerator cohort and blocks no accelerator phase. |
| 1 | Active | Sprints 1.1–1.19 retain their recorded closure; Sprints 1.20–1.25 are open. The open work is Apple engine rematerialization from current source plus the runtime evidence that depends on it (the production Audiveris cancellation command, installed-Python source isolation, and the authoritative installed smokes), the Darwin build-memory measurement rerun, the `linux-cpu` confirmation of the resolved build-memory lane, the pinned Linux protobuf byte-regeneration gate, and the current-source rerun of the in-process Haskell style gate. [Wave Y](cohort-validation-waves.md) owns the remaining Apple plus paired source-matched `linux-cpu` cohort for `llm-smollm2-safetensors`, `audio-demucs-htdemucs`, `audio-open-unmix`, `music-mt3-infer`, `music-mr-mt3`, `music-omnizart`, and `audio-bark-small`, with Apple additionally owning the typed `image-sdxl-turbo` refusal. [Wave AA](cohort-validation-waves.md) is closed for Sprint 1.21's Stage 1 and its Darwin build-memory proof and is not rerun. |
| 2 | Blocked | Blocked by Phase 1 Sprints 1.20–1.25. Sprints 2.1–2.13 retain their recorded closure; Sprints 2.14–2.16 carry landed implementation. Phase 2 owns its own settled-source review and machine-independent gates before one frozen Apple Silicon identity and the paired `linux-cpu` cohort. |
| 3 | Blocked | Blocked by Phase 2. Sprint 3.16 is code-side closed and owns only its `linux-cpu` lifecycle cohort gate; Sprints 3.14 and 3.15 closed under [Wave V](cohort-validation-waves.md). |
| 4 | Blocked | Blocked by Phase 3. Sprints 4.32, 4.34, and 4.35 carry open work — the Apple observer and adversarial-breach proof, the broker-side member claim, and the native runner front-end correction's Apple half. Sprint 4.36 is `Done` by supersession and re-home into Phase 1 Sprint 1.23; every other sprint is `Done`. |
| 5 | Blocked | Blocked by Phase 4. Its own implementation state is `Done` with a named open dependency: no code-side work is open and no defect is known, and its cohort evidence is reproduced under [Wave Y](cohort-validation-waves.md) after Phase 1's current-source gates. |
| 6 | Blocked | Blocked by Phase 5. Sprints 6.43, 6.44, 6.47, 6.48, and 6.49 are code-side closed and hold only their cohort or aggregate runs; Sprint 6.46 is `Done` for its original scope, with the same-authority single-flight follow-on owned by Phase 1 Sprint 1.21. Phase 6 behavioral sign-off starts after Phase 2 and Phase 4 close. |
| 7 | Blocked | Blocked by Phase 6. Its own implementation state is `Active` under the Apple/`linux-cpu` evidence reset: no defect is known in its own surface, and it re-closes when [Wave Y](cohort-validation-waves.md) records a result. |
| 8 | Blocked | Blocked by Phase 7. Sprints 8.9 and 8.10 are code-side closed and validation-only, sharing the `linux-gpu` plus `linux-cpu` rebuild. Sprint 8.11 (system and machine contracts) is `Planned` and carries no blocker: its scope is what one engine machine can carry and prove. The fleet work that genuinely needs more than one engine machine — per-node identity, the workload-shape decision, and the broker-side member claim adopted from Phase 4 Sprint 4.34 — is Sprint 8.12, `Blocked` on a fleet validation topology. That split removes a contradiction the plan carried: 8.11 had been blocked on demonstrating multi-machine identity, which Phase 3 Sprint 3.16's single-node platform topology makes undemonstrable. Sprints 8.1–8.8 are closed. |
| 9 | Blocked | Blocked by Phase 8. Its own implementation state is `Done` with a named open dependency: no code-side work is open and no defect is known, and its RBAC and dashboard cohort evidence is reproduced under [Wave Y](cohort-validation-waves.md). |

## Canonical Outcome

The supported platform now closes around these rules:

- one repo-owned Haskell executable, `infernix`, links the default Cabal library exposed by the
  `infernix` package (declared in `infernix.cabal` without an explicit library name and depended on
  as `infernix`); it owns the production daemon, cluster lifecycle, validation, internal helpers, and
  the routed demo HTTP host (served by the long-running `Webapp` role selected through typed Dhall
  and `infernix service --role webapp`)
- one Haskell command registry owns parsing, help text, and the
  canonical CLI reference, but it no longer exposes `--runtime-mode` or any equivalent substrate
  override
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from repo-root `./infernix.dhall`, and that initialized payload is
  the primary source of truth for substrate identity,
  generated catalog content, daemon role, inference placement, Pulsar topics, and test scope
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
  same built image is the artifact pushed to Harbor and deployed as the cluster daemon
- the operator runtime config lives at repo-root `./infernix.dhall` on every supported execution
  context; cluster deployment derives a payload through `ConfigMap/infernix-demo-config` whenever
  the active topology has cluster-resident consumers and mounts it at the compatibility path
  `/opt/build/infernix-substrate.dhall`
- each daemon reads its runtime-config `.dhall` at startup; automatic file-watching or reload is
  not part of the supported contract
- `infernix init --demo-ui false` can disable the demo surface; omitting that flag keeps the
  default demo-enabled output
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
- Harbor-first bootstrap, one local instance of each platform service, Gateway-owned routing,
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
| 2 | 0-1 | builds Kind lifecycle, manual storage, Harbor-first image flow, and Linux launcher behavior on top of the repository foundations |
| 3 | 0-2 | adds the single-instance platform services, routed edge, and publication contract on top of the cluster lifecycle and storage baseline |
| 4 | 0-3 | closes the runtime, adapter boundary, object-store contract, and Apple host-daemon bridge on top of the platform surfaces |
| 5 | 0-4 | adds the clustered demo UI, generated frontend contracts, and routed browser validation on top of the runtime and publication contract |
| 6 | 0-5 | validates the whole supported surface end to end and hardens the governed docs, routes, and lifecycle behavior around that implementation |
| 7 | 0-6 | adds the multi-user durable-context demo application on top of the platform: Keycloak self-signup, WebSocket post-login transport, Pulsar-backed conversation log per context, MinIO-backed artifact upload/download/render-or-download, a Haskell-first logic boundary surfaced to PureScript via `purescript-bridge`, and the supported three-role daemon split (stateless Webapp role in the `infernix-demo` workload, stateless `infernix-coordinator`, substrate-specific engine pools). The platform contract Phase 7 builds on is implemented in code; Apple plus native Linux/CUDA real-cluster validation evidence is recorded in Waves A-C, Sprint 7.8 runtime KV-cache plus `Infernix.Runtime.Daemon` closure is recorded in Wave E, Sprint 7.24 pool assignment and broker-native backpressure closed in Wave J, Sprints 7.25-7.27 object-proxy / Files / in-browser rendering closed in Wave M, and Sprint 7.28 generated artifact ownership closed in Wave N. |
| 8 | 0-7 | adopts the hostbootstrap Dhall doctrine on top of the whole platform: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (including ConfigMap/Secret bodies), explicit `init` / `test init` creation with ordinary commands failing fast when config is missing, the Apple bootstrap `up` wrapper explicitly running `init --if-missing`, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging (replacing the lazy per-inference bootstrap) driven by the mounted `infernix.dhall`. |
| 9 | 0-8 | adds the role-based access-control and monitoring surface on top of the whole demo platform: the Keycloak `infernix-admin` realm role + JWT `realm_access.roles` claim, the edge admin `SecurityPolicy` (a valid JWT is necessary but not sufficient for cluster-wide surfaces) plus ungated-route closure, the backend admin gate + admin cluster-wide monitoring panel, the per-user personal dashboard, per-user MinIO STS defense-in-depth, and the enforced Apple host-worker loopback data-plane invariant. Every dependency edge references an equal-or-lower-numbered phase, so the forward-only DAG holds. |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
