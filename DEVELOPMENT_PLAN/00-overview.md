# Infernix Development Plan - Overview

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [system-components.md](system-components.md)

> **Purpose**: Capture the architecture baseline, hard constraints, control-plane topology,
> substrate contract, and canonical repository shape that every `infernix` phase depends on.

## Architecture Baseline

The repository target closes around the explicit-init runtime-config architecture: the one-binary role model,
single-node platform services, registry-first image flow, manual storage doctrine, Pulsar-only
production surface, Gateway-owned routing, Haskell-owned frontend contracts, substrate-specific
validation, and a daemon-role model where the coordinator owns Pulsar routing while
substrate-neutral engine pools run inference on Kubernetes workloads or Apple host daemons.

The host toolchain is an account admitted against the host rather than an unmodelled draw on
headroom. It is drawn from the same claimable pool the inference partition divides, so the two are
alternative occupants admitted one at a time rather than independent declarations, and minting the
account consumes an observation of available host memory plus a census finding no toolchain claimant
outside its own process tree. `Infernix.BuildMemory` makes `deriveBuildMemoryPlan` the only mint of a `BuildMemoryPlan`,
so a per-process ceiling has no inhabitant that was not divided by the job count it is multiplied
by, and the built executable declares a bounded runtime address-space reservation, without which
lowering the process's own `RLIMIT_AS` succeeds and then kills it on its next allocation. The host
manifest carries a measured `memory` record — `/proc/meminfo` intersected with the cgroup maximum on
Linux, `hw.memsize` on Darwin — from which `infernix init` derives the untracked per-machine
`cabal.project.local`, while `cabal.project` carries a calibrated floor for a fresh clone. The
repository-owned CLI spawn boundary is a closed toolchain invocation vocabulary with no
caller-supplied command list, and the Haskell-style lint rejects a raw `HostCabal` spawn that omits
the complete owned lifecycle. The mechanism is resolved per lane and fails closed when it is
unavailable; it is neither a universal `System.Process` guarantee nor a host-global lease. Canonical
doctrine:
[../documents/architecture/bounded_host_memory.md](../documents/architecture/bounded_host_memory.md).

Repository-owned native implementation source is forbidden — in native files, in Cabal
native-source declarations, and in embedded or generated payloads alike. Apple engine
materialization reaches Metal and Core ML through upstream package APIs inside a hidden rank-2
bounded provisioning and session region: a candidate root is hydrated, relocated, authoritatively
smoke-validated, provenance-recorded, and digested from its actual payload before the fsynced
sibling activation transaction, and failure, cancellation, or crash reconciliation preserves a
complete prior root or fails closed. The lifecycle lock, bounded subprocess creation, and
capped-engine process-group custody are all-Haskell over public `filelock`, `process`, and `unix`
APIs with no FFI boundary. Phase 1 Sprint 1.20 owns the removal of the former embedded
Objective-C/C/Metal bridge and its Clang topology; evidence recorded against that bridge describes a
surface the repository no longer has.

## Current Repo Assessment

Phases 0 through 9 are `Done`; no execution gate is open. Phase 4's selected Apple accelerator plus
`linux-cpu` validate the Bounded Engine Launch
host half: Apple declares detection-only, calibrated `linux-cpu` declares prevention, and a
prevention-required production readiness contract consumes the declaration and refuses weaker
strength. Phase 6 closes the device-side correction and Linux GPU host calibration on the selected
CUDA accelerator plus same-host `linux-cpu`; a phase's status
describes only the scope it owns, so an earlier phase gaining work does not revert a later one, and
every phase remains completable using only equal-or-lower-numbered phases.

Phase 6 Sprint 6.51 forms the device half: Linux GPU pod RAM is calibrated prevention, while NVIDIA
device memory remains admission, arena sizing, and detection because no supported kernel mechanism
bounds it.

[cohort-validation-waves.md](cohort-validation-waves.md) holds no open wave, while
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) inventories only surfaces that
still require removal. [README.md](README.md) holds the plan's single phase-status table.

The repository implements the runtime-config architecture, bootstrap responsibility boundary, and
registry-first image-boundary doctrine described in this overview. The governed validation surface
splits cleanly between focused config-independent lint or docs checks and test commands that
validate the initialized runtime config before running: `infernix lint docs` and
`infernix docs check` validate documentation without reading the runtime config,
`infernix test unit` validates module behavior once command-level substrate context is present, and
`infernix test integration`, `infernix test e2e`, and `infernix test all` run the complete relevant
suites for the configured substrate instead of implying a default cross-substrate rerun. Bootstrap
shell entrypoints build or enter the active launcher only; `infernix init` creates repo-root
`./infernix.dhall`; ordinary config-dependent binary commands validate it and fail fast naming the
required init when it is absent. The worktree carries no direct tool-route compatibility payload,
and `cluster down` preserves Linux cluster state under `./.data/` across lifecycle cycles.

The Apple split-executor shape is implemented, and routing uses a substrate-neutral engine-pool
graph rather than single Apple host-topic routing or Linux-only per-engine topic special cases.
`apple-silicon` keeps Apple-native inference execution host-side for performance while Kind hosts
the registry, MinIO, Pulsar, PostgreSQL, Envoy Gateway, the optional routed demo surface, and the
production `infernix-coordinator` Deployment. Linux substrates run Kubernetes engine-pool workloads;
Apple uses same-binary host daemons identified by stable host ids. The generated Helm values use
role-specific coordinator and engine knobs rather than a `service.replicaCount` surface. The
coordinator publishes batch work to topics derived from `(runtimeMode, pool id, model id, optional
member id)`: normal pools use Pulsar `Shared` subscriptions and broker-native backpressure, while
pinned routes use derived per-member topics with `Exclusive`. The initialized `.dhall` tells each
daemon its substrate and whether its role is `Coordinator`, `Engine`, or `Webapp`; host-role Apple
metadata additionally carries the Pulsar connection mode and pool membership. Publication reports
the cluster coordinator location separately from the inference executor location.

The runtime worker uses explicit Python or native adapter harnesses selected from the runtime
config. Each harness dispatches to the selected engine entrypoint after the coordinator eagerly
stages every configured model in the `infernix-models` MinIO bucket behind the `warm-model-cache`
barrier, and publishes the typed per-family result surface. Readiness observation is three-valued —
the kernel `PollOutcome`, the tri-state `SentinelObservation`, and the Python `CacheValidity`
verdict — so a transient MinIO fault cannot masquerade as a definitive absence and stall that
barrier. Realness is guaranteed by construction: the engine code cannot fabricate a result, and the
realness lint is the regression tripwire that keeps it that way.

Memory safety rests on the generated typed execution plan. `compileRuntimePlan` mints
resource-indexed grants and retains oversized rows as `UnavailableModel`; package-owned live
observations refine matching grant and enforcer pairs into `RuntimePlan` and `ExecutableModel`;
coordinators route through compiled placements and daemon capabilities; and engine launch accepts
only the opaque executable and derives its command from the compiled binding. An oversized request
returns `ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` while smaller
configured models stay runnable, no hardcoded Apple budget floor remains, and the Linux lanes use
the pod-memory and reported GPU-VRAM quantities. Admission is only half of the guarantee: the
capped-engine kernel bounds the running process's actual resident memory to the `MemoryCeiling` its
grant names, and a measured breach ends the request as a typed `status=failed`
`ModelMemoryLimitExceeded` rather than a fabricated result. Apple and Linux CPU observers enforce
resident-memory ceilings, and Linux GPU execution requires independently indexed RAM and VRAM
grants and observers. Coordinator and engine request handling returns a
terminal failed result for unavailable, empty, unknown, wrong-route, and malformed input before
source removal or acknowledgement. Cluster state is owned the same way: the typed `ClusterOwner`
(`OperatorOwned | HarnessOwned`) gates seizure with evidence, and the first-class `ClusterMutating`
lifecycle position makes a killed `infernix test all` leave a detectable, reconcilable dirty cluster
instead of a false `steady-state`.

On Apple Silicon the Haskell binaries build host-native and run on the host against Metal. The
headless materialization target uses no Tart VM, no user keychain dependency, no host Xcode UI flow,
and no request-time toolchain installation: Sprint 1.14 removed the `tart` / `hostTart` /
`AppleTart` implementation and retargeted the retained `materialize-metal-engines` command to typed
engine-artifact manifests, and Sprint 1.15 materializes real Apple native runner roots for Core ML,
MLX, llama.cpp/whisper.cpp Metal, CTranslate2, ONNX Runtime, and Audiveris and validates their
installed smokes on the Apple host. The stage-0 entrypoint verifies same-process ghcup-managed `ghc`
and `cabal` resolution before its fixed authority-derived build and install; operators use
`./bootstrap/apple-silicon.sh build` and then the generated `./.build/infernix` command surface,
never bare host Cabal. Sprint 1.24 deletes the Custom Setup path and consumes an exact tracked
Haskell protobuf snapshot, so Darwin installs and starts no standalone compiler or plugin. Apple
adapter setup reconciles the Homebrew-managed `python@3.12` formula and `python3.12` command plus a
user-local Poetry bootstrap on demand, reusing an already available compatible Python 3.12+
executable when one passes the implemented version check. Routed Apple Playwright validation runs
host-native `npm exec` against the published `127.0.0.1` edge port.

The native-only workflow doctrine forbids Apple Docker-context creation or switching, Colima VM
creation, and cross-architecture emulation. Sprint 1.12 replaced the previous Colima reconciliation
path with a prerequisite check that reports the selected Docker context and daemon architecture and
then stops before cluster work when the daemon is absent or non-native, and its recorded Apple
validation closed both the positive lifecycle gate and the negative no-daemon boundary without
changing Docker contexts or Colima VM state.

The shared cluster lifecycle persists explicit phase, child-operation detail, and heartbeat data in
`cluster status` during monitored Docker build, registry publication, registry-backed final-image
preload, and Apple retained-state replay steps; runtime-config writes are atomic, so concurrent
readers never observe a truncated payload. The former Patroni replica-reinitialization path is
retired together with the replicated topology. On detached snapshot lanes, the explicit rebuildable
registry/Keycloak scrub set is removed only from the local retained copy after Kind deletion under
`WriterQuiesced`. The lifecycle skips broad pre-registry support-image preloads and performs
binary-owned registry-first image preparation: supported lanes hydrate and stream only the narrow
registry warmup dependency set into Kind before Helm warmup, only the storage the registry needs may pull
upstream before the registry is responsive, and every remaining image, including the active `infernix`
runtime image, is loaded into the registry before final rollout. Repo-owned cluster images carry a source
fingerprint, host-native Apple reuse is allowed only when that fingerprint, runtime mode,
architecture, and pushable manifest shape all match, and the Dockerfile dependency layer is split so
that ordinary source edits do not redownload Cabal, NPM, or Poetry dependencies.

Open cohort gates for the supported Linux and Apple lifecycle surfaces are tracked by
[cohort-validation-waves.md](cohort-validation-waves.md).

| Area | Supported contract | Current repo state |
|------|--------------------|--------------------|
| Root-document governance | the governed docs, root docs, and plan describe the same explicit-init runtime-config doctrine and Apple daemon-role topology | implemented; the mechanical plan-standards enforcement that keeps the corpus aligned runs inside the aggregate lint gate |
| CLI ownership | one Haskell command registry owns the supported command surface without any `--runtime-mode` override | implemented |
| Substrate selection | repo-root `./infernix.dhall`, created explicitly by `infernix init` or temporarily by the test harness from `infernix test init`, is the runtime source of truth for substrate identity and generated catalog selection | implemented; ordinary config-dependent commands fail fast naming the required init |
| Runtime-config format | the operator runtime config and its deployment mirrors use a reflected typed Dhall contract | implemented; repo-root `./infernix.dhall` is decoded in-process by the `dhall` Haskell library, while cluster publication may retain a compatibility mount filename |
| Apple split-executor lane | the host-built binary manages Kind, the cluster runs the coordinator role for Pulsar ingress and derived pool-topic handoff, and Apple-native inference batches are delegated to same-binary host engine daemons through Pulsar | implemented |
| Apple stage-0 bootstrap determinism | `./bootstrap/apple-silicon.sh build` verifies same-process tool resolution and performs the fixed authority-derived build/install; subsequent focused work uses `./.build/infernix`, never an operator bare-Cabal validation command | implemented; the Darwin build-memory mechanism is closed |
| Bootstrap responsibility boundary | shell bootstrap builds or enters the active launcher only, then delegates lifecycle, validation, image preparation, and teardown to `infernix`; registry-first image loading includes the active runtime image on every substrate after the registry is responsive | implemented; the cohort evidence for the current source is reproduced on the selected accelerator plus `linux-cpu` |
| Lifecycle false-negative protection | supported lifecycle surfaces report long-running build, publication, preload, and teardown phases clearly enough that operators do not mistake progress for failure | implemented; the all-Haskell lifecycle lock replaces the former same-process cleanup contention, and Phase 2 owns its ordered closure behind Phase 1 |
| Linux control plane | all supported Linux CLI commands run through `docker compose run --rm infernix infernix ...` | implemented |
| Linux GPU naming | the NVIDIA-backed Linux substrate is standardized as `linux-gpu` | implemented |
| Serialized substrate naming | the initialized runtime config, publication JSON, `cluster status`, and browser contracts still carry the active substrate under `runtimeMode` field names | implemented |
| Demo UI gating | the initialized runtime config can disable the clustered demo surface | implemented; `infernix init` accepts `--demo-ui false` |
| Simulation stance | no simulated cluster, route, or generic inference-success fallback remains in the supported runtime or validation contract, and routed Pulsar checks require the real Gateway-backed upstream | implemented; the repo-local topic spool is a harness-only endpoint-absent path, the realness lint remains a regression tripwire, and engine failures remain fail-closed. Phase 1 compiles resource-indexed grants, retains oversized Apple and Linux CPU rows as `UnavailableModel`, refines matching live enforcers into `ExecutableModel`, and restricts public engine launch to that capability. Phase 4 owns Apple and Linux CPU adversarial enforcement plus encapsulated serialization, Phase 6 owns the fail-closed Linux GPU RAM/VRAM path and raw-spawn exemption closure, and Phase 8 owns the final wire schema |
| Validation scope | integration uses one `.dhall`-driven suite over the README matrix, E2E stays substrate-agnostic at the browser layer, and `test all` runs every supported validation layer for one initialized substrate at a time | Phases 2-9 follow strict numerical blockers |
| Hardware cohort cadence | code-side closure (implementation plus the machine-independent gate set) is completed in natural phase order on whichever single machine is present and gates the next phase's implementation; `Done` requires exactly one chosen accelerator plus `linux-cpu`, never both accelerators in one phase gate | implemented in the plan doctrine; operationalized in [cohort-validation-waves.md](cohort-validation-waves.md), where validation-only residuals are queued as named per-accelerator attestations instead of ad hoc machine-switch requests |
| Native container architecture | Apple Silicon -> `linux/arm64`; `linux-cpu` -> native Linux host architecture (`linux/amd64` or `linux/arm64`); `linux-gpu` -> `linux/amd64`; no development or validation lane uses cross-architecture emulation | implemented and validated: `linux-cpu` publication reads the normalized native host architecture from `InfernixHost.dhall`, and the native arm64 `linux-cpu` full-suite gate closes through the selected native arm64 Docker daemon |

Beyond the Phase 9 admin overview (`/api/admin/overview`) and per-user personal dashboard, no
general observability stack (metrics, tracing, log aggregation) is deployed.
Monitoring is not a supported first-class surface.

Phase 7 adds the multi-user durable-context demo application on top of this platform. The
product-agnostic primitives live at
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the demo's concrete bindings live at
[../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md);
the supported three-role daemon model (stateless frontend, stateless coordinator, substrate-specific
engine pools) lives at
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) and
[../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md);
the execution-ordered build out lives at
[phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md). Phase 7 introduces
a Keycloak release with its own Patroni Postgres, a per-context Pulsar conversation log topic
family, compacted per-user metadata and drafts topics, a shared MinIO bucket with per-user
prefixes, stateless WebSocket coordination via Pulsar `Reader` subscriptions, and a chart
refactor that replaces the fused `infernix-service` Deployment with role-specific, single-replica
`infernix-coordinator` and `infernix-engine` Deployments. The
durable-context surface, including Keycloak, the WS endpoint, the `/auth` and `/api/objects`
routes, and the demo MinIO bucket, is gated by the same `demo_ui` flag that gates the rest
of the `infernix-demo` browser surface. Phase 7 supersedes the previous single-form manual
inference path: routed manual inference closes through the durable-context Chat surface and
WebSocket-delivered `ConversationStatePatch` deltas rather than a direct HTTP request/poll
cycle. Production deployments leave `demo_ui = false`, the Phase 7 demo surface is absent, and the
production coordinator plus engine pools remain present.

Phase 9 adds role-based access control and monitoring on top of the demo. Per-user object and chat
isolation (Phase 7) is unchanged; Phase 9 adds the orthogonal admin-vs-user dimension: only
members of the `infernix-admin` Keycloak realm role reach the cluster-wide operator consoles (the
registry, Pulsar Admin) and cluster-wide monitoring, while every other authenticated user —
including self-registered users — sees only their own data (chat, artifacts, files, and a personal
dashboard). Enforcement is at the Envoy edge `SecurityPolicy` (admin authorization on all four
operator routes, gateway NodePort 30090) and the backend (`withAdminRequest` on `GET /api/cache`,
`/api/cache/{evict,rebuild}`, and the `GET /api/admin/overview` cluster-wide monitoring endpoint);
the Apple host-worker loopback data plane (MinIO NodePort 30011, Pulsar-proxy NodePort 30080,
`127.0.0.1`) is trust-boundary-internal, never transits the admin-gated edge, and its loopback
binding is enforced by `infernix lint chart` plus a generated-Kind-config unit assertion. Per-user
object isolation additionally gains a MinIO STS defense-in-depth layer (a scoped credential keyed
to `users/<sub>/`, gated by `cluster.minio.stsPerUser`, now default on). Sprint 9.9 code-side
closes the reported UAT auth issue: Sign out clears the upstream Keycloak SSO session through OIDC
logout, so a user can switch from a self-registered account to the separate admin login. The
doctrine lives at
[../documents/architecture/access_control_doctrine.md](../documents/architecture/access_control_doctrine.md);
the execution-ordered buildout lives at
[phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md).

## Supported Outcome

`infernix` targets these rules:

- one repo-owned Haskell executable, `infernix`, sits on top of the default Cabal library exposed
  by the `infernix` package (declared in `infernix.cabal` without an explicit library name and
  depended on as `infernix`): it owns the production daemon, cluster lifecycle, validation, internal
  helpers, and the routed demo HTTP host (served by the long-running `Webapp` daemon role selected
  through typed Dhall and `infernix service --role webapp`)
- one Haskell command registry owns parsing, help text, and the
  canonical CLI reference, and the final command surface carries no `--runtime-mode` override
- the product standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the initialized repo-root `./infernix.dhall` is the primary source of
  truth for substrate identity, generated catalog content, daemon role, inference placement,
  Pulsar topics, and validation scope
- the initialized runtime config, routed publication surface, `cluster status` output, and generated
  browser contracts currently serialize that active substrate under `runtimeMode` field names even
  though the supported selection contract is substrate-based
- the supported operator config flow is explicit and binary-owned: `infernix init` creates
  `./infernix.dhall` plus `./infernix-host.dhall`, `infernix test init` creates
  `./infernix.test.dhall`, and ordinary config-dependent commands fail fast naming the required
  init rather than auto-materializing a missing file
- the Apple stage-0 `up` wrapper is the deliberate convenience exception: it calls
  `./.build/infernix init --if-missing` before `cluster up`; the Linux image build may use internal
  binary generation for its image-local defaults, but that is not an operator preflight path
- repo-owned shell is limited to the `bootstrap/*.sh` stage-0 host bootstrap surface, which may
  reconcile supported host prerequisites and build or enter the active substrate launcher before
  handing off to the direct `infernix` command surface; shell code must not own Kind, Kubernetes
  manifests, cluster workload image pulls, registry publication, validation internals, or lifecycle
  teardown beyond invoking the binary command
- supported stage-0 bootstrap entrypoints are restartable prerequisite reconcilers: they continue
  in the current process only after verifying the required executable they just installed or
  selected, and they stop at explicit new-shell or reboot boundaries so the operator reruns the
  same bootstrap command instead of jumping ahead to a later direct command
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints validate the initialized runtime config and fail fast
  naming the required init if it is absent; focused `infernix lint ...` and `infernix docs check`
  remain config-independent
- the runtime config is a typed Dhall record named `infernix.dhall`, generated by
  `infernix init` or the reservation-gated test harness and decoded in-process by the `dhall`
  library; the schema is reflected from the
  substrate decoder type (`infernix internal dhall-schema substrate`)
- Apple Silicon is the only supported host-native build path outside a container
- on Apple Silicon, the host-built binary manages Kind, deploys the mandatory cluster support
  services, the cluster coordinator daemon, and optional routed demo workload, and still owns the
  host-side same-binary engine daemon lane
- on Apple Silicon, cluster daemons are canonical for Pulsar ingress and derived pool-topic handoff; host
  daemons are canonical for Apple-native inference execution and result publication and consume a
  dedicated Pulsar batch topic using their `.dhall` role metadata plus published edge state
- on Linux substrates, cluster daemons read from Pulsar, run inference directly, and publish
  results
- on Linux substrates, all supported CLI commands run through
  `docker compose run --rm infernix infernix ...`; there is no supported Linux host-native CLI
  story outside the outer container
- `linux-cpu` remains the only substrate meaningfully portable across unrelated native Linux host
  hardware; native amd64 Linux and native arm64 Linux are first-class CPU-only host shapes, while
  Apple Silicon emulation is not a supported build or validation path
- `linux-gpu` assumes an amd64 Linux environment paired with a CUDA-capable device, but the outer
  control-plane container itself never requires the NVIDIA runtime
- supported entrypoints no longer use simulated cluster bring-up, direct tool-route compatibility
  handlers, generic inference-success fallback, or cross-substrate default validation reruns; the
  remaining repo-local topic spool is a harness-only path and does not replace real Pulsar
  transport on the routed cluster validation path
- one substrate-aware integration suite traverses the comprehensive model, format, and engine
  matrix in `README.md`, reads the active substrate from `.dhall`, and chooses the corresponding
  engine binding for every supported row or reference
- Playwright E2E is substrate-agnostic at the browser layer and relies on `infernix-demo` reading
  the active `.dhall` to dispatch the correct engine behind the routed demo API
- the routed demo app remains cluster-resident when enabled, and the Apple routed path closes
  around an explicit cluster-daemon-to-host-daemon inference batch bridge rather than
  cluster-resident Apple inference execution
- `infernix init --demo-ui false` can emit `demo_ui = false`; omitting that flag keeps the default
  demo-enabled output
- registry-first bootstrap, Gateway-owned routing, single-node platform services,
  operator-managed Patroni PostgreSQL, manual `infernix-manual` storage, Haskell-owned frontend
  contracts, the shared Python adapter project, and untracked generated outputs all remain
  mandatory doctrine
- supported validation is substrate-specific: integration, E2E, and `test all` run the complete
  supported suites against the built and deployed substrate and report that substrate explicitly
- phase validation is single-accelerator: code-side closure (implementation plus the
  machine-independent gate set) is completed in natural phase order on whichever single machine is
  present and gates the next phase's implementation, while the hardware full-suite for the phase's
  **one** chosen accelerator (`apple-silicon` **or** `linux-gpu`) plus `linux-cpu` gates `Done`; no
  phase requires both accelerators, and cross-accelerator coverage is a `linux-cpu`-only aggregation
  phase that merges committed per-accelerator attestations (see
  [development_plan_standards.md](development_plan_standards.md) Section Q)
- the supported control plane keeps one Haskell command registry,
  imperative cluster or host prerequisite orchestration, root-package in-process Ormolu/HLint plus
  the solver-isolated Cabal-format package,
  and the existing files or docs or chart or proto validation entrypoints rather than layering on
  an additional architecture-doctrine backlog
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
- when `demo_ui = true`, Phase 7 adds a multi-user durable-context surface served by the
  existing `infernix-demo` workload: Keycloak self-signup, WebSocket post-login transport,
  per-context Pulsar conversation log topics, compacted per-user metadata and drafts topics,
  a shared MinIO `infernix-demo-objects` bucket with per-user prefixes, and `/auth` and
  `/api/objects` routes registered through the Haskell route registry source; business
  logic — reducer, idempotency dedup, `prefixHash` chain, dispatcher rule, event
  construction — lives only in the shared `infernix` library and surfaces to the SPA via
  `purescript-bridge`, with the browser receiving typed state snapshots and patches rather
  than raw events

## Topology Baseline

```mermaid
flowchart TB
    appleCli["Apple host-native infernix CLI"]
    appleHostDaemon["Apple host infernix service (inference executor)"]
    linuxCli["Linux outer-container infernix CLI"]
    data["Host .data"]
    requester["Inference requester (Pulsar publisher)"]

    subgraph kind["Kind cluster"]
        gateway["Envoy Gateway controller + Gateway/infernix-edge"]
        routes["HTTPRoute set rendered from Haskell route registry"]
        demo["infernix-demo"]
        coordinator["infernix-coordinator"]
        engine["infernix-engine (Linux only)"]
        enginePoolTopics["Derived engine-pool topics"]
        registry["In-cluster registry (registry:2)"]
        minio["MinIO"]
        pgop["Percona PostgreSQL operator"]
        postgres["Patroni PostgreSQL"]
        pulsar["Pulsar"]
    end

    appleCli --> gateway
    appleCli --> appleHostDaemon
    linuxCli --> gateway
    requester --> pulsar
    gateway --> routes
    routes --> demo
    routes --> registry
    routes --> minio
    routes --> pulsar
    demo --> coordinator
    pulsar --> coordinator
    coordinator --> enginePoolTopics
    enginePoolTopics --> appleHostDaemon
    appleHostDaemon --> pulsar
    coordinator --> engine
    engine --> pulsar
    pgop --> postgres
    data --> kind
```

Current code nuance: the topology above is the implemented supported path. Linux runs both
coordinator and engine roles in-cluster, while Apple runs the coordinator in-cluster and hands
batches to same-binary host engine daemons through derived Pulsar pool topics.

## Canonical Repository Shape

The authoritative repository shape closes toward the layout below. Generated-only paths such as
`web/src/Generated/` and `tools/generated_proto/` materialize on demand and stay untracked even
though they are part of the supported shape; a clean checkout may omit `tools/` until Python
protobuf generation runs.

```text
infernix/
├── DEVELOPMENT_PLAN/
├── documents/
│   ├── README.md
│   ├── documentation_standards.md
│   ├── architecture/
│   ├── development/
│   ├── engineering/
│   ├── operations/
│   ├── reference/
│   ├── tools/
│   └── research/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── compose.yaml
├── infernix.cabal
├── cabal.project
├── app/
│   └── Main.hs
├── src/
│   ├── Infernix/
│       ├── Auth/
│       ├── Bootstrap/
│       ├── Bridge/
│       ├── CLI.hs
│       ├── Cluster/
│       ├── Cluster.hs
│       ├── ClusterConfig.hs
│       ├── CommandRegistry.hs
│       ├── Config.hs
│       ├── Conversation/
│       ├── Demo/
│       ├── DemoConfig.hs
│       ├── Dispatch/
│       ├── Engines/
│       ├── Error.hs
│       ├── HostConfig.hs
│       ├── HostPrereqs.hs
│       ├── HostTools.hs
│       ├── Internal/
│       ├── Lint/
│       ├── Models.hs
│       ├── Objects/
│       ├── ProcessMonitor.hs
│       ├── Python.hs
│       ├── Routes.hs
│       ├── Runtime/
│       ├── Runtime.hs
│       ├── SecretsConfig.hs
│       ├── Service.hs
│       ├── Storage.hs
│       ├── Substrate.hs
│       ├── Topic/
│       ├── Types.hs
│       ├── Web/
│       │   └── Contracts.hs
│       └── Workflow.hs
│   └── Proto/                 # four tracked byte-exact proto-lens generator outputs
├── proto/
│   ├── README.md
│   ├── haskell-bindings.sha256
│   └── infernix/
├── python/
│   ├── pyproject.toml
│   └── adapters/
├── web/
│   ├── spago.yaml
│   ├── package.json
│   ├── src/
│   │   ├── *.purs
│   │   └── Generated/
│   ├── test/
│   ├── scripts/
│   └── playwright/
├── chart/
│   ├── Chart.yaml
│   ├── README.md
│   ├── values.yaml
│   └── templates/
│       ├── configmap-cluster-config.yaml
│       ├── configmap-demo-catalog.yaml
│       ├── configmap-publication-state.yaml
│       ├── deployment-coordinator.yaml
│       ├── deployment-demo.yaml
│       ├── deployment-engine.yaml
│       ├── envoyproxy.yaml
│       ├── gatewayclass.yaml
│       ├── gateway.yaml
│       ├── httproutes.yaml
│       ├── keycloak/
│       ├── minio/
│       ├── poddisruptionbudget-coordinator.yaml
│       ├── poddisruptionbudget-demo.yaml
│       ├── poddisruptionbudget-engine.yaml
│       ├── runtimeclass-nvidia.yaml
│       ├── secret-cluster-secrets.yaml
│       ├── securitypolicy-operator-routes.yaml
│       └── service-demo.yaml
├── kind/
│   ├── README.md
│   ├── cluster-apple-silicon.yaml
│   ├── cluster-linux-cpu.yaml
│   └── cluster-linux-gpu.yaml
├── docker/
│   └── Dockerfile
├── tools/
│   └── generated_proto/
├── test/
├── .build/
│   ├── infernix
│   ├── infernix.dhall
│   └── outer-container/
│       └── build/
│           └── infernix.dhall
└── .data/
```

## Execution Contexts and Substrates

The plan keeps control-plane execution context separate from substrate.

### Control-Plane Execution Contexts

| Context | Canonical launcher | Purpose |
|---------|--------------------|---------|
| Apple host-native control plane | `./.build/infernix ...` | canonical operator surface on Apple Silicon |
| Linux outer-container control plane | `docker compose run --rm infernix infernix ...` | image-snapshot launcher for Linux CPU and Linux GPU workflows |

### Supported Substrates

| Substrate | Canonical substrate id | Typical role |
|-----------|------------------------|--------------|
| Apple Silicon / Metal | `apple-silicon` | cluster daemon plus host inference executor lane |
| Linux / CPU | `linux-cpu` | containerized CPU lane |
| Linux / NVIDIA GPU | `linux-gpu` | containerized CUDA-backed lane |

## Hard Constraints

### 0. Documentation-First Construction Rule

- Sprints 0.1-0.10 are the closed documentation and governance baseline. The configuration
  doctrine and per-phase cleanup ledger are declared, and the later cleanup sprints
  (1.11, 2.13, 3.10, 4.13, 5.9, 6.28, 7.17) are closed.
- New documentation gaps land as explicit follow-on work in later phases.
- `README.md` stays an orientation layer.
- governed root docs carry explicit status, supersession, and canonical-home markers when they
  distinguish canonical guidance from entry-document summaries
- the canonical topic ownership under `documents/` remains in place, and
  `documents/architecture/runtime_modes.md` remains the current runtime or substrate architecture
  home despite the legacy filename and `runtimeMode` field names

### 1. One Haskell Executable With Shared Role Dispatch

- `infernix` is the only supported repo-owned Haskell executable
- it links the default Cabal library exposed by the `infernix` package (declared in
  `infernix.cabal` without an explicit library name and depended on as `infernix`)
- long-running Coordinator, Engine, and Webapp roles are selected through typed Dhall metadata and
  `infernix service --role ...`
- tests and helpers do not become extra supported executables

### 2. Dual Control-Plane Execution Contexts

- Apple host-native control plane is the canonical operator surface on Apple Silicon
- Linux outer-container control plane is the only supported Linux CLI surface
- Apple operators do not use Compose as a user-facing launcher for ordinary CLI work; the
  routed Apple-host E2E surface uses host `npm exec` and is covered by Apple cohort validation
  batches
- Linux host-native `infernix` execution outside a container is not a supported operator workflow

### 3. Three Supported Substrates

- `apple-silicon`, `linux-cpu`, and `linux-gpu` are the canonical substrate ids
- the substrate selected in the initialized runtime config chooses the README matrix column
- control-plane execution context and substrate remain separate concepts
- `linux-cpu` is the only substrate that remains meaningfully portable across unrelated host
  hardware

### 4. Explicit Runtime Config SSoT

- `infernix init` creates the operator runtime config at repo-root `./infernix.dhall` plus
  `./infernix-host.dhall`
- `infernix test init` creates `./infernix.test.dhall`; the harness uses it to generate and own a
  temporary `./infernix.dhall` during integration, E2E, and aggregate validation
- ordinary config-dependent commands validate the file and fail fast naming the required init when
  it is absent; focused `infernix lint ...` and `infernix docs check` remain config-independent
- the runtime config records the active substrate explicitly
- the runtime config also carries the generated demo catalog for that substrate
- the runtime config is a typed Dhall record at `infernix.dhall`, decoded in-process by the
  `dhall` Haskell library; the schema is reflected from the substrate decoder type
- the current daemon reads that file at startup; automatic file-watching or reload is not part of
  the supported contract

### 5. Manual Storage Doctrine

- all default StorageClasses are deleted during bootstrap
- `infernix-manual` is the only supported persistent StorageClass
- PVs are created only by `infernix` lifecycle code and map deterministically into `./.data/`
- hand-authored standalone durable PVC manifests outside Helm or operator ownership are forbidden

### 5a. Protobuf Manifest and Event Contract

- repo-owned `.proto` schemas define runtime manifests and Pulsar payloads
- Haskell uses generated `proto-lens` bindings
- Python adapters consume matching generated protobuf modules

### 5b. Operator-Managed PostgreSQL Doctrine

- every in-cluster PostgreSQL dependency uses Patroni under the Percona Kubernetes operator
- charts that can self-deploy PostgreSQL disable that path and point to operator-managed clusters

### 6. Cluster Daemon With Host-Owned Apple Inference

- the demo UI is served only by `infernix-demo`
- when `demo_ui` is false in the initialized runtime config, no demo UI or demo API route is
  published; `infernix init --demo-ui false` emits that production-off value
- when `demo_ui` is true, the demo app is cluster-resident across substrates
- every substrate deploys cluster `infernix` daemon Deployments under the supported three-role
  split landed by Phase 7 Sprint 7.7: `infernix-coordinator` (stateless, Pulsar coordination +
  dispatcher + result-bridge + eager model-cache staging + model-to-pool routing) and engine pools
  (`infernix-engine` on Linux substrates, plus Linux GPU framework-specific Deployments when
  configured; on-host Apple daemons selected by stable host id). The legacy fused
  `chart/templates/deployment-service.yaml` is retired together with the `service.*` chart-values
  block
- the coordinator consumes request topics and publishes inference work to derived engine-pool topics;
  engine members consume their assigned pool or pinned-member topics, execute inference, and publish
  results
- the staged `.dhall` tells each daemon its substrate, whether its `daemonRole` is `Coordinator` or
  `Engine`, and the validated pool/member assignments and derived topics it may use. Engine daemon
  metadata is derived internally from those assignments rather than exposed as a legacy projection
- the supported fleet defaults: one process per role per machine, Linux engine placement governed
  by Kubernetes scheduling, Apple engine placement governed by member ids, and per-role coordinator
  plus engine-pool knobs in `chart/values.yaml`. Horizontal scale is adding a machine, not raising a
  replica count. Pulsar-owned topics, `Shared`
  subscriptions on normal pool topics, `Exclusive` on pinned member topics, and per-context
  `Failover` subscriptions on coordinator-owned topics
  keep request handoff, inference, and result-publication ownership unambiguous

### 7. The Local Registry Is The Cluster Image Source

- the in-cluster registry and only the MinIO storage it needs may pull upstream before the registry
  is ready
- every remaining cluster workload pulls from the registry afterward

### 7a. Local Service Topology

- every supported lane runs one instance of the registry, MinIO, each Pulsar component, each Patroni
  cluster and pgBouncer, the coordinator, and the optional demo/Keycloak services; each machine runs
  exactly one engine process
- lifecycle validation proves the collapsed topology reaches readiness without a `Pending` replica
  and recovers its supported single-instance state. It does not claim replica failover, chaos
  tolerance, or a repo-owned HA topology

### 8. Stable Edge Port and Route Prefixes via Envoy Gateway API

- routing is owned by Envoy Gateway API resources and repo-owned HTTPRoute manifests
- the route inventory comes from one Haskell route registry
- `cluster up` tries port `9090` first and increments by 1 until it finds an open localhost port

### 8a. `cluster up` Is A Reconcile Flow

- `infernix cluster up` reconciles cluster, storage, image publication, generated config, and edge
  port selection
- `infernix cluster down` preserves durable state under `./.data/`

### 8b. Integration and E2E Cover The Initialized Substrate Only

- `infernix test integration` validates the initialized substrate's generated catalog contract, routed
  surfaces, and routed inference execution for every generated catalog entry on that substrate
- the comprehensive model, format, and engine matrix in `README.md` is the authoritative
  integration-test coverage ledger
- one substrate-aware integration suite reads the active substrate from `.dhall`, selects the
  corresponding engine binding for each supported README row or reference, and carries at least one
  integration assertion for every such row
- `infernix test e2e` exercises the routed browser surface for that same initialized substrate without
  branching on substrate or engine in browser code
- validation reports the substrate it exercised and does not imply cross-substrate coverage from a
  single run

### 9. Haskell Types Own Frontend Contracts

- handwritten browser-contract ADTs live in `src/Infernix/Web/Contracts.hs`
- generated PureScript contract output lives in `web/src/Generated/`
- no handwritten duplicate DTO layer exists on the frontend

### 10. Playwright Runs From Inside The Linux Substrate Image

- Phase 3 Sprint 3.10 retired the dedicated `infernix-playwright:local` image and
  `docker/playwright.Dockerfile`; the Playwright system packages and the three browsers are baked
  into `docker/Dockerfile`
- on Linux substrates, routed Playwright execution runs in-container via
  `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private
  `kind` network
- on Apple Silicon, host-native E2E now uses host `npm exec` Playwright fed by the same typed
  fixture against the published localhost edge port; real execution is recorded by Apple cohort
  validation batches
- browser and Playwright code do not branch on substrate id or engine family; `infernix-demo`
  reads the active `.dhall` and owns substrate-appropriate engine dispatch
- supported workflows use `npm --prefix web exec -- playwright ...`; `npx` is not part of the
  supported final workflow

### 11. Container Build Output Stays in the Launcher Image

- Linux outer-container build output stays in the launcher image overlay; cabal builddir, cabal
  package cache, and the source snapshot manifest stay in the image overlay
- the outer-container launcher does not rely on a live repo bind mount for source code; the only
  bind mounts are `./.data/` and the Docker socket
- the launcher reads repo-root `./infernix.dhall`; `cluster up` derives a ConfigMap deployment
  mirror that remains mounted at `/opt/build/infernix.dhall` inside cluster-resident pods

### 12. Apple Host Build Output Stays Under `./.build`

- host-native compiled artifacts stay under `./.build/`
- Apple operator config stays at repo-root `./infernix.dhall` and `./infernix-host.dhall`; it is not
  a build output
- `cluster up` writes the repo-local kubeconfig to `./.build/infernix.kubeconfig`
- on every supported substrate, Kind or `nvkind` create or delete uses a transient
  execution-local scratch kubeconfig under the system temp directory, and the lifecycle publishes
  the durable repo-local kubeconfig afterward

### 13. Python Restriction

- custom platform logic is Haskell
- Python source is allowed only in the shared adapter package under `python/adapters/` and the
  declared Poetry metadata under `python/` and `python/engines/`
- the framework-free shared project owns quality/protobuf work; Python-stdio inference runs only
  through a prepared `python/engines/<engine>/.venv/bin/python` whose project digest marker matches
- the canonical Python quality gate is `poetry run check-code`
- Apple materialization prepares the shared venv plus the `transformers`, `pytorch`, and `diffusers`
  `apple-silicon` environments before inference; request-time repair and shared-venv fallback are
  forbidden

### 14. Production Surface Is Pulsar-Only

- production inference requests arrive by Pulsar topics only
- cluster daemons own production request-topic consumption on every substrate
- Linux cluster daemons execute inference and publish results directly, while Apple cluster
  daemons publish work to a host-inference Pulsar topic consumed by same-binary host daemons that
  publish the completed results
- production `infernix service` binds no HTTP listener
- the demo HTTP API is a demo-only surface owned by `infernix-demo`
- simulated cluster, route, and generic inference-success fallback behavior are not part of the
  supported final contract; real cluster paths use Pulsar transport, while the repo-local topic
  spool is retained only for unit-level or intentionally endpoint-absent harness flows

### 15. Frontend Language Is PureScript

- the demo UI is implemented in PureScript
- the supported browser test framework is `purescript-spec`
- the supported browser bundle is built with spago

## Command Surface Baseline

The supported operator surface is:

- `infernix init`
- `infernix service`
- `infernix cluster up`
- `infernix cluster down`
- `infernix cluster status`
- `infernix cache status`
- `infernix cache evict`
- `infernix cache rebuild`
- `infernix kubectl ...`
- `infernix lint files`
- `infernix lint docs`
- `infernix lint proto`
- `infernix lint chart`
- `infernix test init`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`
- `infernix docs check`

Internal helper commands may exist for image/test generation and engine materialization, but
operator runtime-config creation closes through `infernix init` and test-harness config creation
through `infernix test init`.

## Completion Rules

- later phases may refine earlier foundations, but they may not contradict them
- if a cleanup changes the supported end state, earlier phase text must be rewritten so later
  phases extend the narrative instead of undoing it
- `Done` claims require validation, aligned docs, and no hidden remaining work

## Cross-References

- [README.md](README.md)
- [system-components.md](system-components.md)
- [cohort-validation-waves.md](cohort-validation-waves.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-platform-services-and-edge-routing.md](phase-3-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md)
- [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md)
- [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md)
- [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
