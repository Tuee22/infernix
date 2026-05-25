# Infernix Development Plan - Overview

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [system-components.md](system-components.md)

> **Purpose**: Capture the architecture baseline, hard constraints, control-plane topology,
> substrate contract, and canonical repository shape that every `infernix` phase depends on.

## Architecture Baseline

The repository target closes around the staged-substrate architecture: the two-binary topology,
mandatory local HA platform services, Harbor-first image flow, manual storage doctrine, Pulsar-only
production surface, Gateway-owned routing, Haskell-owned frontend contracts, substrate-specific
validation, and a daemon-role model where cluster `infernix service` daemons always exist while
Apple-native inference execution can be delegated to same-binary host daemons.

## Current Repo Assessment

The repository implements the substrate-file architecture, bootstrap responsibility boundary, and
Harbor-first image-boundary doctrine described in this overview. The governed validation surface
now splits cleanly between focused substrate-file-independent lint or
docs checks and test commands that validate the active staged substrate before running:
`infernix lint docs` and `infernix docs check` validate documentation without reading the staged
substrate file, `infernix test unit` validates module behavior after command-level substrate
context is present, and `infernix test integration`, `infernix test e2e`, and `infernix test all`
run the complete relevant suites for the currently staged substrate instead of implying a default
cross-substrate rerun.
The worktree omits the direct tool-route compatibility payloads and persists Linux cluster state
before later rollout phases. Bootstrap shell entrypoints build or enter the active launcher only;
the binary command materializes or verifies the active substrate file before lifecycle and
validation commands rely on it. The final Apple product shape described by this plan is
implemented:
`apple-silicon` keeps Apple-native inference execution host-side for performance while Kind
continues to host Harbor, MinIO, Pulsar, PostgreSQL, Envoy Gateway, the optional routed demo
surface, and the cluster `infernix service` Deployment. The generated final-phase Helm values run
one cluster service replica by default; explicit chart values can scale that Deployment through
`service.replicaCount`. On Linux substrates, cluster daemons read from Pulsar, run inference
directly, and publish results; on Apple, cluster daemons read from Pulsar and publish requests to a
dedicated host batch topic consumed by same-binary host daemons, which execute Apple-native
inference and publish the completed result. The staged `.dhall` tells
each daemon the substrate, whether it is running in the cluster or on the host, and, for host
daemons, the Pulsar connection mode plus the batch and result topics it uses. Publication now
reports the cluster daemon location separately from the Apple host inference executor location and
batch topic. The runtime worker uses explicit Python or native adapter
harnesses selected from the staged substrate file. Those adapters currently produce deterministic
engine-family output from durable metadata rather than claiming universal production model-binary
execution. The Apple clean-host bootstrap
hardening is present in code: the stage-0 entrypoint verifies same-process ghcup-managed `ghc`
and `cabal` resolution before direct `cabal install`, reconciles Homebrew `protoc`, reconciles
Colima to the supported `8 CPU / 16 GiB` profile before Docker-backed work, and lets Apple
adapter setup or validation paths reconcile the Homebrew-managed `python@3.12` formula and
`python3.12` command plus a user-local Poetry bootstrap on demand. The Poetry bootstrap may reuse
an already available compatible Python 3.12+ executable when one passes the implemented version
check. Routed Apple
Playwright readiness probes `127.0.0.1` from the host while
the browser container joins the private Docker `kind` network and targets the Kind control-plane
DNS. The shared cluster lifecycle persists explicit phase, child-operation detail, and heartbeat
data in `cluster status` during monitored Docker build, Harbor publication, Harbor-backed
final-image preload, and Apple retained-state replay steps; explicit substrate-file
materialization is atomic so concurrent readers do not observe truncated payloads; and
retained-state Apple reruns
automatically reinitialize stopped Harbor PostgreSQL replicas from the current Patroni leader when
timeline drift leaves replicas unready after promotion. The shared lifecycle skips broad
pre-Harbor support-image preloads and performs binary-owned Harbor-first image preparation, where
only Harbor-required services may pull upstream before Harbor is responsive and every remaining
image, including the active `infernix` runtime image, is loaded into Harbor before final rollout.
Phase 6 records clean governed
bootstrap reruns for the supported Linux and Apple lifecycle surfaces, including Apple reruns
on May 15, 2026 and May 17, 2026 through `doctor`, `build`, `up`, `status`, `test`, `down`, and
final `status`, plus the May 19, 2026 post-warning-cleanup `linux-gpu` rerun through `doctor`,
forced image refresh, `build`, `up`, `status`, `test`, `down`, `purge`, and final `status`; those
reruns validated the split daemon topology, host-batch Pulsar handoff, routed Playwright E2E,
repeated retained-state cluster bring-up or teardown cycles inside the governed `test` lane, and
final post-teardown status returning `clusterPresent: False`, `lifecycleStatus: idle`, and
`lifecyclePhase: cluster-absent`. Those reruns also validate the Harbor publication closure
for repo-owned local images: publication pushes the `infernix-linux-cpu:local` payload before
third-party chart dependencies and re-tags the source image before each bounded push retry, so
retry recovery does not depend on a previously retained target tag. The earlier May 13 lifecycle
investigation remains the proof point that Apple `build-cluster-images` can stay healthy well past
thirty minutes before Harbor publication begins and that Harbor image pushes are readiness-gated
with bounded retries across transient registry resets.

| Area | Supported contract | Current repo state |
|------|--------------------|--------------------|
| Root-document governance | the governed docs, root docs, and plan describe the same staged-substrate doctrine and Apple daemon-role topology | implemented and validated |
| CLI ownership | one Haskell command registry owns the supported command surface without any `--runtime-mode` override | implemented |
| Substrate selection | one staged substrate file beside the active build root is the primary source of truth for substrate identity and generated catalog selection | implemented |
| Staged substrate-file format | the substrate file and its mirrors use one explicit and consistent file format and filename contract | implemented; the current contract is a shared `infernix-substrate.dhall` filename carrying a typed Dhall record on local and cluster-mounted paths, decoded in-process by the `dhall` Haskell library |
| Apple split-executor lane | the host-built binary manages Kind, the cluster always runs `infernix service` daemons, and Apple-native inference batches are delegated to same-binary host daemons through Pulsar | implemented |
| Apple stage-0 bootstrap determinism | a first-run Apple bootstrap verifies newly installed same-process tool resolution before handing off to direct `cabal` work | implemented and validated through the governed Apple `doctor`, `build`, `up`, `status`, `test`, and `down` lifecycle |
| Bootstrap responsibility boundary | shell bootstrap builds or enters the active launcher only, then delegates lifecycle, validation, image preparation, and teardown to `infernix`; Harbor-first image loading includes the active runtime image on every substrate after Harbor is responsive | implemented and validated |
| Lifecycle false-negative protection | supported lifecycle surfaces report long-running build, publication, preload, and teardown phases clearly enough that operators do not mistake progress for failure | implemented and validated; `cluster status` now reports in-progress lifecycle phase, detail, and heartbeat fields during the monitored long-running phases, and the governed docs use the same inactivity-aware interpretation contract |
| Linux control plane | all supported Linux CLI commands run through `docker compose run --rm infernix infernix ...` | implemented and validated through the supported `linux-cpu` and `linux-gpu` bootstrap lifecycles |
| Linux GPU naming | the NVIDIA-backed Linux substrate is standardized as `linux-gpu` | implemented |
| Serialized substrate naming | the generated substrate file, publication JSON, `cluster status`, and browser contracts still carry the active substrate under `runtimeMode` field names | implemented |
| Demo UI gating | the staged substrate file can disable the clustered demo surface | implemented; the supported materialization path accepts `--demo-ui false` |
| Simulation stance | no simulated cluster, route, or generic inference-success fallback remains in the supported runtime or validation contract, and routed Pulsar checks require the real Gateway-backed upstream | implemented and validated; inference execution goes through typed adapter harnesses, unsupported adapters fail fast, and the remaining repo-local topic spool under `./.data/runtime/pulsar/` is a harness-only path for unit-level or intentionally endpoint-absent daemon checks |
| Validation scope | integration uses one `.dhall`-driven suite over the README matrix, E2E stays substrate-agnostic at the browser layer, and `test all` runs every supported validation layer for one built substrate at a time | implemented and validated across the governed Linux and Apple lifecycle reruns |

Monitoring is not a supported first-class surface.

Phase 7 (`Active`) adds the multi-user durable-context demo application on top of this
validated platform. The product-agnostic primitives live at
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the demo's concrete bindings live at
[../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md);
the supported three-role daemon model (stateless frontend, stateless coordinator, one-per-node
stateful engine) lives at
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md);
the execution-ordered build out lives at
[phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md). Phase 7 introduces
a Keycloak release with its own Patroni Postgres, a per-context Pulsar conversation log topic
family, compacted per-user metadata and drafts topics, a shared MinIO bucket with per-user
prefixes, stateless WebSocket coordination via Pulsar `Reader` subscriptions, and a chart
refactor that replaces the fused `infernix-service` Deployment with role-specific
`infernix-coordinator` and `infernix-engine` Deployments under HA defaults. The
durable-context surface, including Keycloak, the WS endpoint, the `/auth` and `/api/objects`
routes, and the demo MinIO bucket, is gated by the same `demo_ui` flag that gates the rest
of the `infernix-demo` browser surface. Phase 7 supersedes the previous single-form manual
inference path: routed manual inference closes through the durable-context Chat surface and
WebSocket-delivered `ConversationStatePatch` deltas rather than a direct HTTP request/poll
cycle. Production deployments leave `demo_ui = false`, the Phase 7 surface is absent, and
the only daemon Deployment present is `infernix-engine`.

## Supported Outcome

`infernix` targets these rules:

- two repo-owned Haskell executables share the default Cabal library exposed by the `infernix`
  package (declared in `infernix.cabal` without an explicit library name and depended on as
  `infernix`): `infernix` for the production daemon, cluster lifecycle, validation, and internal
  helpers; `infernix-demo` for the routed demo HTTP host
- one Haskell command registry owns parsing, help text, and the
  canonical CLI reference, and the final command surface carries no `--runtime-mode` override
- the product standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the staged `infernix-substrate.dhall` file beside the active build root is the primary source of
  truth for substrate identity, generated catalog content, daemon role, inference placement,
  Pulsar topics, and validation scope
- the generated substrate file, routed publication surface, `cluster status` output, and generated
  browser contracts currently serialize that active substrate under `runtimeMode` field names even
  though the supported selection contract is substrate-based
- the supported operator staging flow is binary-owned rather than shell-owned:
  Apple host-native lifecycle and validation commands materialize or verify
  `./.build/infernix-substrate.dhall`, Linux outer-container lifecycle and validation commands
  materialize or verify `./.build/outer-container/build/infernix-substrate.dhall` on the host
  through the bind-mounted build tree, and `infernix internal materialize-substrate ...` remains
  the explicit restaging or inspection helper
- the Linux substrate Dockerfile also materializes a build-arg-selected substrate file inside the
  image overlay during image build; supported Compose runs bind-mount the host `./.build/` tree
  over that location, so lifecycle and aggregate test commands rely on binary-owned
  host-visible preflight
- repo-owned shell is limited to the `bootstrap/*.sh` stage-0 host bootstrap surface, which may
  reconcile supported host prerequisites and build or enter the active substrate launcher before
  handing off to the direct `infernix` command surface; shell code must not own Kind, Kubernetes
  manifests, cluster workload image pulls, Harbor publication, validation internals, or lifecycle
  teardown beyond invoking the binary command
- supported stage-0 bootstrap entrypoints are restartable prerequisite reconcilers: they continue
  in the current process only after verifying the required executable they just installed or
  selected, and they stop at explicit new-shell or reboot boundaries so the operator reruns the
  same bootstrap command instead of jumping ahead to a later direct command
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints own substrate-file preflight and fail if the file
  cannot be materialized or validated for the active execution context; focused `infernix lint ...`
  and `infernix docs check` remain substrate-file independent
- the staged file is a typed Dhall record named `infernix-substrate.dhall`, materialized by
  Haskell helpers and decoded in-process by the `dhall` library; the schema lives at
  `dhall/InfernixSubstrate.dhall`
- Apple Silicon is the only supported host-native build path outside a container
- on Apple Silicon, the host-built binary manages Kind, deploys the mandatory cluster support
  services, cluster `infernix service` daemons, and optional routed demo workload, and still owns
  the host-side same-binary inference daemon lane
- on Apple Silicon, cluster daemons are canonical for Pulsar ingress and host-batch handoff; host
  daemons are canonical for Apple-native inference execution and result publication and consume a
  dedicated Pulsar batch topic using their `.dhall` role metadata plus published edge state
- on Linux substrates, cluster daemons read from Pulsar, run inference directly, and publish
  results
- on Linux substrates, all supported CLI commands run through
  `docker compose run --rm infernix infernix ...`; there is no supported Linux host-native CLI
  story outside the outer container
- `linux-cpu` remains the only substrate meaningfully portable across unrelated host hardware; Apple
  operators may exercise it through Colima's amd64 VM, and arm64 Linux is a first-class CPU-only
  host shape
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
- the supported materialization path can emit `demo_ui = false` with `--demo-ui false`; omitting
  that flag keeps the default demo-enabled output
- Harbor-first bootstrap, Gateway-owned routing, mandatory local HA platform services,
  operator-managed Patroni PostgreSQL, manual `infernix-manual` storage, Haskell-owned frontend
  contracts, the shared Python adapter project, and untracked generated outputs all remain
  mandatory doctrine
- supported validation is substrate-specific: integration, E2E, and `test all` run the complete
  supported suites against the built and deployed substrate and report that substrate explicitly
- the supported control plane keeps one Haskell command registry,
  imperative cluster or host prerequisite orchestration, the current `ormolu` plus `hlint` plus
  `cabal format` style stack,
  and the existing files or docs or chart or proto validation entrypoints rather than layering on
  an additional architecture-doctrine backlog
- every `infernix service` daemon remains startup-configured and Pulsar-driven without a separate
  admin-HTTP, hot-reload, or typed-event-ledger subsystem in the supported contract
- the test surface remains the current three Cabal stanzas plus the frontend unit suite:
  `infernix-unit`, `infernix-integration`, and `infernix-haskell-style`, exercised through the
  supported `infernix test lint|unit|integration|e2e|all` command surface
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
        clusterService["infernix service cluster daemon(s)"]
        appleBatchTopic["Apple host-inference batch topic"]
        harbor["Harbor"]
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
    routes --> harbor
    routes --> minio
    routes --> pulsar
    demo --> clusterService
    pulsar --> clusterService
    clusterService --> appleBatchTopic
    appleBatchTopic --> appleHostDaemon
    appleHostDaemon --> pulsar
    clusterService --> pulsar
    harbor --> postgres
    pgop --> postgres
    data --> kind
```

Current code nuance: the topology above is the implemented supported path. Cluster daemons always
run, Linux cluster daemons perform inference locally, and Apple cluster daemons hand batches to
same-binary host inference daemons through Pulsar.

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
├── Setup.hs
├── compose.yaml
├── infernix.cabal
├── cabal.project
├── app/
│   ├── Main.hs
│   └── Demo.hs
├── src/
│   └── Infernix/
│       ├── Auth/
│       ├── Bootstrap/
│       ├── Bridge/
│       ├── CLI.hs
│       ├── Cluster/
│       ├── Cluster.hs
│       ├── CommandRegistry.hs
│       ├── Config.hs
│       ├── Conversation/
│       ├── Demo/
│       ├── DemoCLI.hs
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
│       ├── Service.hs
│       ├── Storage.hs
│       ├── Substrate.hs
│       ├── Topic/
│       ├── Types.hs
│       ├── Web/
│       │   └── Contracts.hs
│       └── Workflow.hs
├── dhall/
│   ├── InfernixHost.dhall
│   └── InfernixSubstrate.dhall
├── proto/
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
│       ├── poddisruptionbudget-coordinator.yaml
│       ├── poddisruptionbudget-demo.yaml
│       ├── poddisruptionbudget-engine.yaml
│       ├── runtimeclass-nvidia.yaml
│       └── service-demo.yaml
├── kind/
│   ├── README.md
│   ├── cluster-apple-silicon.yaml
│   ├── cluster-linux-cpu.yaml
│   └── cluster-linux-gpu.yaml
├── docker/
│   └── linux-substrate.Dockerfile
├── tools/
│   └── generated_proto/
├── test/
├── .build/
│   ├── infernix
│   ├── infernix-demo
│   ├── infernix-substrate.dhall
│   └── outer-container/
│       └── build/
│           └── infernix-substrate.dhall
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

- Sprints 0.1–0.8 are the closed documentation and governance baseline. Sprint 0.9
  (Configuration Doctrine) is `Active`: the doctrine and per-phase retirement-sprint ledger are
  declared, but the seven later retirement sprints (1.11, 2.13, 3.10, 4.13, 5.9, 6.28, 7.17) are
  still open or blocked.
- New documentation gaps land as explicit follow-on work in later phases.
- `README.md` stays an orientation layer.
- governed root docs carry explicit status, supersession, and canonical-home markers when they
  distinguish canonical guidance from entry-document summaries
- the canonical topic ownership under `documents/` remains in place, and
  `documents/architecture/runtime_modes.md` remains the current runtime or substrate architecture
  home despite the legacy filename and `runtimeMode` field names

### 1. Two Haskell Executables Sharing One Library

- `infernix` and `infernix-demo` are the only supported repo-owned Haskell executables
- both link the default Cabal library exposed by the `infernix` package (declared in
  `infernix.cabal` without an explicit library name and depended on as `infernix`)
- tests and helpers do not become extra supported executables

### 2. Dual Control-Plane Execution Contexts

- Apple host-native control plane is the canonical operator surface on Apple Silicon
- Linux outer-container control plane is the only supported Linux CLI surface
- Apple operators do not use Compose as a user-facing launcher for ordinary CLI work; the
  routed Apple-host E2E surface is deferred (see Hard Constraint 10) until the host-native
  `npm exec` Playwright refactor lands
- Linux host-native `infernix` execution outside a container is not a supported operator workflow

### 3. Three Supported Substrates

- `apple-silicon`, `linux-cpu`, and `linux-gpu` are the canonical substrate ids
- the built substrate selects the README matrix column
- control-plane execution context and substrate remain separate concepts
- `linux-cpu` is the only substrate that remains meaningfully portable across unrelated host
  hardware

### 4. Staged Substrate File SSoT

- the repo stages one `infernix-substrate.dhall` file under the active build root
- the supported operator implementation materializes or verifies that file through the
  binary-owned lifecycle or validation command rather than through shell bootstrap
- `infernix internal materialize-substrate ...` remains the explicit restaging or inspection
  helper for Apple host-native and Linux outer-container workflows
- the Linux substrate image also creates a build-arg-selected copy during image build, but the
  supported Compose bind mount hides that image-local copy from host-launched operator commands
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints own substrate-file preflight; focused `infernix lint ...`
  and `infernix docs check` do not require it
- the staged file records the active substrate explicitly
- the staged file also carries the generated demo catalog for that substrate
- the staged file is a typed Dhall record at `infernix-substrate.dhall`, decoded in-process by the
  `dhall` Haskell library; the schema lives at `dhall/InfernixSubstrate.dhall`
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
- when `demo_ui` is false in the active staged file, no demo UI or demo API route is published;
  the supported materialization path can emit that production-off value with `--demo-ui false`
- when `demo_ui` is true, the demo app is cluster-resident across substrates
- every substrate deploys cluster `infernix` daemon Deployments under the supported three-role
  split landed by Phase 7 Sprint 7.7: `infernix-coordinator` (stateless, Pulsar coordination +
  dispatcher + result-bridge + model bootstrap) and `infernix-engine` (stateful adapter execution
  on Linux substrates, on-host `flock(2)`-singleton daemon on Apple Silicon). The legacy fused
  `chart/templates/deployment-service.yaml` was retired together with the `service.*` chart-values
  block on May 23, 2026
- on `linux-cpu` and `linux-gpu`, the coordinator consumes request topics and publishes
  `inference.batch.<mode>`; the engine consumes the batch topic, executes inference, and publishes
  results
- on `apple-silicon`, the coordinator role consumes request topics and publishes inference work to
  `inference.batch.apple-silicon`; the same-binary on-host engine daemon consumes that batch topic,
  executes Apple-native inference, and publishes results
- the staged `.dhall` tells each daemon its substrate, whether its `daemonRole` is `Coordinator` or
  `Engine`, and, for the Apple host engine, the Pulsar connection mode plus the batch and result
  topics it uses
- the supported HA defaults: coordinator `replicaCount >= 2` with soft anti-affinity, engine
  required pod anti-affinity keyed on its own label with `topologyKey: kubernetes.io/hostname` so
  two engine pods cannot share a node; per-role `coordinator.replicaCount` and
  `engine.replicaCount` knobs in `chart/values.yaml`. Pulsar-owned topics, `Shared` subscriptions
  on the request and batch topics, and per-context `Failover` subscriptions on the result topic
  keep request handoff, inference, and result-publication ownership unambiguous

### 7. Local Harbor Is The Cluster Image Source

- Harbor and only Harbor-required bootstrap services may pull upstream before Harbor is ready
- every remaining non-Harbor workload pulls from Harbor afterward

### 7a. Mandatory Local HA Service Topology

- Harbor, MinIO, Pulsar, and PostgreSQL close only on the mandatory local HA topology
- no alternate single-replica supported profile is introduced

### 8. Stable Edge Port and Route Prefixes via Envoy Gateway API

- routing is owned by Envoy Gateway API resources and repo-owned HTTPRoute manifests
- the route inventory comes from one Haskell route registry
- `cluster up` tries port `9090` first and increments by 1 until it finds an open localhost port

### 8a. `cluster up` Is A Reconcile Flow

- `infernix cluster up` reconciles cluster, storage, image publication, generated config, and edge
  port selection
- `infernix cluster down` preserves durable state under `./.data/`

### 8b. Integration and E2E Cover The Built Substrate Only

- `infernix test integration` validates the built substrate's generated catalog contract, routed
  surfaces, and routed inference execution for every generated catalog entry on that substrate
- the comprehensive model, format, and engine matrix in `README.md` is the authoritative
  integration-test coverage ledger
- one substrate-aware integration suite reads the active substrate from `.dhall`, selects the
  corresponding engine binding for each supported README row or reference, and carries at least one
  integration assertion for every such row
- `infernix test e2e` exercises the routed browser surface for that same built substrate without
  branching on substrate or engine in browser code
- validation reports the substrate it exercised and does not imply cross-substrate coverage from a
  single run

### 9. Haskell Types Own Frontend Contracts

- handwritten browser-contract ADTs live in `src/Infernix/Web/Contracts.hs`
- generated PureScript contract output lives in `web/src/Generated/`
- no handwritten duplicate DTO layer exists on the frontend

### 10. Playwright Runs From Inside The Linux Substrate Image

- Phase 3 Sprint 3.10 (landed May 24, 2026) retired the dedicated `infernix-playwright:local`
  image and `docker/playwright.Dockerfile`; the Playwright system packages and the three browsers
  are now baked into `docker/linux-substrate.Dockerfile`
- on Linux substrates, routed Playwright execution runs in-container via
  `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private
  `kind` network
- on Apple Silicon, the host-native E2E refactor (host-side `npm exec` Playwright fed by the same
  typed fixture) is deferred; the current Apple branch in `runRuntimeModeE2E` surfaces an explicit
  deferral diagnostic so the Linux closure stays honest about the gap
- browser and Playwright code do not branch on substrate id or engine family; `infernix-demo`
  reads the active `.dhall` and owns substrate-appropriate engine dispatch
- supported workflows use `npm --prefix web exec -- playwright ...`; `npx` is not part of the
  supported final workflow

### 11. Container Build Output Stays Under `./.build/outer-container/`

- Linux outer-container build output stays under `./.build/outer-container/` on the host through
  a host-anchored bind mount; the staged substrate file lives in that tree while cabal builddir,
  cabal package cache, and the source snapshot manifest stay in the image overlay
- the outer-container launcher does not rely on a live repo bind mount for source code; the only
  bind mounts are `./.data/`, `./.build/`, the host `compose.yaml`, and the Docker socket
- the staged outer-container substrate `.dhall` sits at
  `./.build/outer-container/build/infernix-substrate.dhall` on the host and is the source material
  for cluster ConfigMap publication, which mounts the file at `/opt/build/infernix-substrate.dhall`
  inside cluster-resident pods

### 12. Apple Host Build Output Stays Under `./.build`

- host-native compiled artifacts stay under `./.build/`
- the Apple substrate `.dhall` sits beside `./.build/infernix`
- `cluster up` writes the repo-local kubeconfig to `./.build/infernix.kubeconfig`
- on every supported substrate, Kind or `nvkind` create or delete uses a transient
  execution-local scratch kubeconfig under the system temp directory, and the lifecycle publishes
  the durable repo-local kubeconfig afterward

### 13. Python Restriction

- custom platform logic is Haskell
- Python is allowed only under `python/adapters/`
- each adapter is invoked only through `poetry run`
- the canonical Python quality gate is `poetry run check-code`
- on Apple Silicon, Poetry may materialize `python/.venv/` on demand

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
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`
- `infernix docs check`

Internal helper commands may exist in the implementation, but the supported command contract closes
through the registry-backed surface above.

## Completion Rules

- later phases may refine earlier foundations, but they may not contradict them
- if a cleanup changes the supported end state, earlier phase text must be rewritten so later
  phases extend the narrative instead of undoing it
- `Done` claims require validation, aligned docs, and no hidden remaining work

## Cross-References

- [README.md](README.md)
- [system-components.md](system-components.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
