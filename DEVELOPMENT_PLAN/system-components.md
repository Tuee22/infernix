# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, supported
> substrates, and durable state locations in `infernix`.

## Current Repo Assessment

- the repo ships the two-binary Haskell topology, Envoy Gateway assets, the PureScript demo UI,
  the split runtime modules under `src/Infernix/Runtime/`, the shared Python project, the shared
  Linux substrate Dockerfile that bakes the source-snapshot manifest used by git-less
  `infernix lint files` runs, the route registry, and the snapshot launcher
- the supported CLI reads the active substrate from `infernix-substrate.dhall` once that file has
  been staged, without a user-facing runtime-mode flag
- the current implemented staging path is explicit:
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]` on
  Apple and
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  on the Linux outer-container path, which writes
  `/workspace/.build/outer-container/build/infernix-substrate.dhall` inside the launcher image
- substrate-file preflight is binary-owned for lifecycle and validation commands, leaving
  `infernix internal materialize-substrate ...` as the direct restaging or inspection helper
  rather than a shell bootstrap responsibility
- lifecycle and validation preflight materializes or validates the active substrate file before
  relying on it, while focused `infernix lint ...` and `infernix docs check` remain
  substrate-file independent
- the Linux substrate image also materializes a build-arg-selected substrate file inside the image
  overlay during image build, and supported Compose runs keep that active build root image-local;
  lifecycle preflight is binary-owned inside the launcher
- the staged substrate file, `cluster status`, publication JSON, demo config, and generated
  browser contracts still expose that active substrate through `runtimeMode` field names
- cluster publication mirrors the cluster-role payload locally as `infernix-substrate.dhall`, and
  the rendered chart mounts that same filename inside cluster workloads at
  `/opt/build/infernix-substrate.dhall`
- the implemented Apple product shape is a split-executor lane: `apple-silicon` keeps Apple-native
  inference execution host-side for Apple GPU and unified-memory access while Kind continues to host
  Harbor, MinIO, Pulsar, PostgreSQL, Envoy Gateway, the cluster coordinator daemon, and the
  optional routed demo surface
- the final daemon-role contract is implemented: on every substrate cluster daemons own Pulsar
  request-topic consumption; on Linux they forward to the Linux batch topic consumed by the
  in-cluster engine Deployment, while on Apple they hand work to a dedicated host batch topic
  consumed by same-binary host daemons, which execute inference and publish results.
  Publication metadata distinguishes `daemonLocation: cluster-pod` from the Apple
  `inferenceExecutorLocation: control-plane-host`. Existing workers use typed Python or native
  adapter harnesses whose current implementations emit deterministic engine-family output from
  durable metadata; unsupported adapter ids fail fast instead of returning a generic success
  payload
- Linux operator workflows close around Compose-driven outer containers, validation reports the
  active built substrate for the complete selected-substrate suite, and the supported
  materialization path can emit `demo_ui = false`
- validation evidence is recorded by hardware cohort: Apple Silicon and CUDA-capable Linux each
  run local full-suite validation for the substrate they own, and phase closure batches the
  counterpart cohort run instead of requiring host switching after every sprint
- direct `infernix-demo` execution no longer doubles as a compatibility target for Harbor, MinIO,
  or Pulsar tool-route probes; those checks now require the real Gateway-backed upstream behavior
- real cluster and routed validation paths use Pulsar's WebSocket and admin surfaces, while the
  repo-local topic spool under `./.data/runtime/pulsar/` remains only a harness-oriented surface
  for unit-level or intentionally endpoint-absent daemon checks
- the Linux bootstrap entrypoints install Docker or CUDA prerequisites and enter
  `docker compose run --rm infernix infernix <command>`; substrate preflight belongs to the
  binary command. `cluster up` persists repo-local cluster state before later rollout phases so
  `cluster status` and cleanup can still observe an in-progress Linux reconciliation
- the supported `linux-cpu` and `linux-gpu` surfaces use the stricter real-upstream route
  assertions, the restaged Linux substrate flow, and the single project `ghc-9.12.4` toolchain
  baked into the substrate image
- the supported Linux launcher bakes a reusable `/opt/infernix/chart/charts/` cache into the
  image and links `/workspace/chart/charts` to it for Helm dependency lookup, the MinIO
  dependency hydrates through the supported direct tarball path, and `cluster up` repairs the
  known stale retained Pulsar or ZooKeeper epoch mismatch by resetting only the Pulsar claim roots
  and retrying once
- the Apple clean-host bootstrap verifies same-process ghcup-managed `ghc` and `cabal`
  resolution before direct `cabal install`, reconciles Homebrew `protoc`, and lets Apple adapter
  setup or validation paths reconcile the Homebrew-managed `python@3.12` formula and
  `python3.12` command plus a user-local Poetry bootstrap on demand. The native-only workflow
  doctrine now requires Docker-backed Apple work to use the current native arm64 Docker daemon and
  forbids Docker-context creation or switching, Colima VM creation, and cross-architecture
  emulation; Phase 1 Sprint 1.12 replaced the previous Colima reconciliation path with selected
  Docker-context and daemon-architecture validation and closed on the recorded validation with positive
  lifecycle/full-test evidence plus negative no-daemon boundary evidence. The Poetry bootstrap
  may reuse an already available compatible Python 3.12+ executable when one passes the
  implemented version check
- routed Apple Playwright validation runs host-native `npm exec` against the published
  `127.0.0.1` edge port, and retained Kind state is replayed into and out of the worker rather
  than bind-mounted
- Linux outer-container lifecycle runs forward the host repo root so generated Kind or `nvkind`
  node configs mount host-resolved `./.data/kind/<runtime-mode>/` and
  `./.build/kind/<runtime-mode>/registry/` directories directly into node containers instead of
  replaying retained state with `docker cp`; runtime-scoping prevents a CPU and GPU lane from
  clobbering each other's `localhost:<harborPort>` mirror target
- the shared lifecycle now exposes `lifecycleStatus`, `lifecyclePhase`, `lifecycleDetail`, and
  heartbeat timestamps during monitored Docker build, Harbor publication, Harbor-backed final-image
  preload, and Apple retained-state replay work; staged substrate materialization is atomic for
  concurrent readers; and retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
  replicas from the current Patroni leader when timeline drift leaves replicas unready after
  promotion
- the shared lifecycle skips broad pre-Harbor support-image preloads; shell scripts never pull or
  publish images, Linux lanes may hydrate and stream only the narrow Harbor warmup dependency set
  into Kind before Helm warmup, only Harbor-required services may pull upstream before Harbor is
  responsive, and every remaining image, including the active `infernix` runtime image, is loaded
  into Harbor before final rollout
- legacy validation proof points are inventoried in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Legacy Historical
  Validation Evidence"; current replacement evidence is tracked by
  [cohort-validation-waves.md](cohort-validation-waves.md), with the Apple cohort closed in Wave A
  and the native Linux/CUDA cohort closed in Wave C; Wave F closed the native arm64 `linux-cpu`
  publication and full-suite validation path on the recorded validation through the selected native arm64 Docker
  daemon
- Monitoring is not a supported first-class surface.

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix` plus direct `cabal` materialization against operator-installed ghcup | host-native | canonical operator surface on Apple Silicon; host-native cluster lifecycle owner; host-side Apple inference-daemon owner; repo-local kubeconfig owner; uses a host-local scratch kubeconfig under system temp for Kind create or delete before publishing the durable repo-local kubeconfig | `./.build/`, `./.data/` |
| Linux outer-container control plane | `docker compose --project-name <lane> --file compose.yaml ... run --rm infernix infernix ...` | Linux container | only supported Linux CLI surface for `linux-cpu` and `linux-gpu`; the GPU lane prefixes the same single Compose file with `LAUNCHER_IMAGE=infernix-linux-gpu:local` to select the CUDA snapshot, forwards the Docker socket, and bind-mounts only `./.data/` while the build root, source snapshot, and chart archives stay in the image overlay; uses a launcher-local scratch kubeconfig under system temp for Kind or `nvkind` create or delete before publishing the durable repo-local kubeconfig | `./.data/`, `./.data/runtime/infernix.kubeconfig` |
| Bootstrap shell entrypoints | `bootstrap/*.sh` | host shell | bounded stage-0 prerequisite and launcher builders; Apple builds the host binary, Linux installs Docker or CUDA prerequisites and enters `docker compose run --rm infernix infernix <command>`; lifecycle, validation, Kind, Kubernetes manifests, cluster workload image pulls, Harbor publication, and teardown behavior are delegated to `infernix` | preserves `./.build/`, `./.data/`, host-level images, Apple host binaries, and installed prerequisites |
| Command registry | Haskell command registry | host or outer container | owns the supported command inventory, `--help` output, and the generated CLI-reference sections that docs lint enforces | none |
| Substrate configuration | staged typed Dhall record at `infernix-substrate.dhall`, decoded in-process by the `dhall` Haskell library | host or outer container | primary source of truth for active substrate, generated catalog content, daemon role, inference placement, Pulsar request/result/batch topics, active engine dispatch, routed Apple bridge behavior, and test scope once the file has been staged; materialization writes the staged file atomically so concurrent readers never observe a partial payload | `./.build/infernix-substrate.dhall` on Apple carries host-role metadata; `/workspace/.build/outer-container/build/infernix-substrate.dhall` on the Linux outer-container path carries cluster-role metadata; cluster pods mount the cluster-role payload at `/opt/build/infernix-substrate.dhall` |
| Route registry | Haskell-owned route inventory | host or outer container during render or reconcile | records public prefixes, backend identity, rewrite rules, visibility, and publication metadata | none |
| Automation entry documents | `AGENTS.md`, `CLAUDE.md`, and their governed canonical-home links into `documents/` | repo source | point assistant users at canonical workflow rules without turning root entry docs into competing topic homes | none |
| Frontend contract generator | `infernix internal generate-purs-contracts` | host or outer container during web build | emits generated PureScript contracts from handwritten Haskell browser-contract ADTs | `web/src/Generated/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, runtime state, config publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | explicit Cabal builddir or installdir flags plus generated artifacts | host or outer container | keeps compiled output and generated files out of tracked source paths | `./.build/` on Apple; image-local `/workspace/.build/outer-container/` on the Linux outer-container path |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Linux substrate image definition | `docker/linux-substrate.Dockerfile` | one shared build definition produces the Linux control-plane image and the Linux daemon image family while owning ghcup, Poetry, Node.js 22.5+ for the demo bundle, Playwright runtime packages, Docker buildx for nested Docker operations, npm update-notifier suppression, and the Kind toolbelt; materializes a build-arg-selected substrate file inside the image overlay before web build and Python quality checks; cabal-home and the cabal builddir live at the toolchain's natural in-image locations rather than under any bind-mounted host path; the image uses `tini` as its `ENTRYPOINT` for clean signal handling and zombie reaping | none |
| Playwright runtime | baked into `docker/linux-substrate.Dockerfile` (Node, the Playwright runtime, and the three browsers) and invoked from inside the outer container via `npm --prefix web exec -- playwright test --config web/playwright.config.js` on Linux substrates; on Apple Silicon the host-native lane invokes `npm --prefix web exec -- playwright test` from the host CLI against the published localhost edge port using the same typed fixture. Apple routed Playwright validation closed in Waves A.1/A.2, and the rebuilt Linux GPU launcher passed 7/7 routed E2E in Wave C on the recorded validation. | none |
| Compose launcher | `compose.yaml` | outer-container launcher for supported Linux workflows; the file defines exactly the `infernix` service with two bind mounts (`./.data` and `/var/run/docker.sock`), no `environment:` block, no `build:` block, and a one-shot image selector that defaults to `infernix-linux-cpu:local` while allowing the GPU lane to choose `infernix-linux-gpu:local`. The Phase 3 Sprint 3.10 `playwright` service removal landed on the recorded validation — Playwright now runs inside the same substrate image | none |
| Shared Python adapter project | `python/pyproject.toml`, `python/adapters/` | single dependency boundary and adapter tree for Python-native engines | none in the supported operator contract |
| Apple host prerequisite bootstrap | governed docs plus Haskell bootstrap logic | minimize Apple pre-existing host installs and let `infernix` reconcile supported Homebrew-managed tools and Poetry bootstrap while requiring any Docker-backed work to use the already selected native arm64 Docker daemon; Docker readiness validation reports the current context and daemon architecture without creating or switching contexts or creating a VM | none |
| Testing doctrine docs | `documents/engineering/testing.md` and `documents/development/testing_strategy.md` | keep one canonical testing doctrine together with one operator-facing detail layer | none |
| Browser-contract source | `src/Infernix/Web/Contracts.hs`, `web/package.json` | keeps handwritten Haskell contract source out of `Generated/` while preserving generated PureScript output there | none |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | hold repo-owned workloads, ConfigMaps, Gateway resources, and third-party chart dependencies | none |
| Kind topology reference assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml` | tracked topology references and chart-lint inputs for the substrate-specific Kind shapes; the supported lifecycle renders the active runtime config from Haskell into `./.build/kind/cluster-<runtime-mode>.generated.yaml` before invoking Kind or nvkind. The `linux-cpu` reference and renderer use two worker nodes so the local CPU lane can exercise two engine pods, pod replacement, node drain, and anti-affinity; `linux-gpu` stays single-worker for the single-GPU host shape | none |
| Protobuf contract assets | `proto/infernix/...` plus on-demand generated `tools/generated_proto/` stubs under a `tools/` directory that may be absent in a clean checkout | define canonical runtime, manifest, and event schema boundaries | generated stubs must stay untracked |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native Apple CLI or Linux outer container | create or reuse Kind, reset StorageClasses, reconcile PVs, deploy Harbor first, publish the cluster-role substrate payload, perform Harbor-first image preparation, deploy the final chart including the role-specific coordinator and engine daemon Deployments, expose in-progress lifecycle phase, detail, and heartbeat state for status observers, retry once with a targeted Pulsar claim-root reset when retained ZooKeeper state is self-inconsistent, and reinitialize stopped retained Harbor PostgreSQL replicas from the current Patroni leader when timeline drift leaves replicas unready after promotion | `./.data/runtime/cluster-state.state`, `./.data/kind/<runtime-mode>/...` |
| Harbor image preparation | Harbor plus Haskell image publication flow | Kind cluster plus control plane | bootstrap Harbor, allow only Harbor-required support services to pull upstream before Harbor readiness, then mirror every remaining third-party image and publish the active `infernix` runtime image before final rollout; Docker pushes wait for registry readiness before each attempt, re-tag the source image before each bounded retry, and use capped backoff so transient Harbor resets or missing transient target tags during large-image publication do not fail the lifecycle prematurely | Harbor state under `./.data/kind/<runtime-mode>/...` |
| PostgreSQL substrate | Percona Kubernetes operator plus Patroni PostgreSQL | Kind cluster | only supported in-cluster PostgreSQL contract for Harbor and later services; retained-state reruns may trigger targeted Patroni replica reinitialization from the current leader when stopped replicas need a fresh base backup after timeline advancement | `./.data/kind/<runtime-mode>/...` |
| Publication state | repo-local JSON plus routed `/api/publication` surface | repo-local state and demo API | reports control-plane context, cluster daemon location, host inference executor presence when the active substrate is Apple, the routed demo API upstream mode, the active inference dispatch mode, the configured host/batch inference handoff topic when present, the active substrate through its current `runtimeMode` field, routes, and upstream health metadata | `./.data/runtime/publication.json` |
| Edge Gateway controller | Helm-installed Envoy Gateway controller | Kind cluster | owns all browser-visible and host-consumed routing | none |
| Cluster Gateway resource | `GatewayClass/infernix-gateway` plus `Gateway/infernix-edge` | Kind cluster | single localhost-bound HTTP listener on the chosen edge port | none |
| HTTPRoute rendering | data-driven `chart/templates/httproutes.yaml` from the Haskell route registry | Kind cluster | publishes the route inventory for demo, Harbor, MinIO, and Pulsar surfaces | none |
| Substrate-file publication | generated `ConfigMap/infernix-demo-config` plus repo-local mirror | Kind cluster and repo-local state | republishes the cluster-role substrate payload for cluster consumers and local inspection tooling through the shared `infernix-substrate.dhall` filename; Apple host daemons read the host-role payload under `./.build/` | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime daemons | `infernix service` plus `src/Infernix/Runtime/{Daemon,Cache,KVCache,Worker,Pulsar}.hs`, `src/Infernix/Dispatch/SingleFlight.hs`, `src/Infernix/Bridge/Result.hs`, `src/Infernix/Bootstrap/Models.hs` | cluster pods on every substrate plus host process for Apple inference execution | the supported three-role daemon model (see [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)) splits Pulsar coordination from engine execution. The coordinator role (`infernix-coordinator` Deployment, stateless, replicas ≥ 2, soft anti-affinity, **no PVC**) runs the single-flight dispatcher, the result-bridge, and the model-bootstrap worker under Pulsar named `Failover` subscriptions when the demo surface is enabled; the engine role (`infernix-engine` Deployment on Linux substrates with **required** one-per-node anti-affinity, **no PVC**, single `emptyDir` `model-cache` mount with hard `sizeLimit`; on-host daemon on Apple silicon with `flock(2)` singleton on `engine.lock`) consumes `inference.batch.<mode>`, pulls weights from the `infernix-models` MinIO bucket into ephemeral pod storage via the shared adapter helper, runs the adapter, owns the node's KV cache (in-memory), and publishes `inference.result.<mode>`. `Infernix.Runtime.Daemon` owns process role orchestration and the process-local engine KV-cache handle; `Infernix.Runtime.Pulsar` owns shared Pulsar transport helpers and runtime loops. Worker execution uses typed Python or native adapter harnesses, with unsupported adapter ids failing fast instead of returning a generic success payload. When Pulsar endpoints are intentionally absent in unit-level harnesses, the same daemon code can use the repo-local topic spool under `./.data/runtime/pulsar/`; that harness path is not routed cluster evidence. The chart ships `chart/templates/deployment-{coordinator,engine,demo}.yaml`, `clusterServiceEnabled` returns `False` on every substrate, and `finalPhaseDeployments` waits on `deployment/infernix-engine` plus demo-gated `deployment/infernix-{coordinator,demo,keycloak}`. The LinuxCpu HA lane renders two workers, two engine replicas, and two demo replicas so the integration suite validates pod replacement, node drain, and one-engine-per-node anti-affinity in a real local cluster; LinuxGpu runs one engine on the single-GPU host. Production-shaped `demo_ui = false` deployments run only the engine among infernix-owned daemons. The coordinator's runtime loops (`runResultBridgeLoop` for the per-context result writeback, `runModelBootstrapLoop` for the lazy `infernix-models` upload) are forked by `runProductionDaemon` when `daemonRole == Coordinator`; the engine config has `daemonConfigHostBatchTopic = Nothing` so it executes the worker inline and publishes results. | none on cluster daemons (Pulsar cursors are broker-side; KV cache is in-memory); the engine pod's `emptyDir` `model-cache` is ephemeral per-pod storage capped by `sizeLimit` and rebuilds from the `infernix-models` MinIO bucket on every pod start |
| Demo UI host | `infernix-demo` deployment | cluster pod | serves `/`, `/api`, `/api/publication`, `/api/demo-config`, `/api/models`, `/api/cache`, `/api/objects/{upload,download}`, and `/ws` when demo is enabled; routed manual inference closes through the durable-context Chat surface, where the `infernix-demo` Pulsar-fronted dispatcher publishes inference work and (on Apple) hands batches off to host inference daemons; direct `infernix-demo` execution intentionally exposes only the demo-owned HTTP surface outside the intended HTTPRoute mapping | none |
| Web runtime executor | PureScript bundle plus Playwright runtime (Node, the Playwright executor, and the three browsers) both baked into `docker/linux-substrate.Dockerfile` | substrate image runs cluster-resident as the demo app; routed E2E runs in-container on Linux substrates via `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private `kind` network. Apple host-native E2E uses host `npm exec` with the same typed fixture against the published localhost edge port and is covered by Apple cohort validation batches | serves the browser bundle from the clustered demo app and runs routed E2E coverage from the same substrate image | test artifacts under `./.data/` |
| Engine adapter set | `python/adapters/` invoked via `poetry run` from the Haskell worker | host child process or cluster child process | Python-native engine boundary over typed protobuf-over-stdio | optional Apple venv under `python/.venv/` |
| Python quality gate | `poetry run check-code` | host or Linux outer-container image | runs `mypy --strict`, `black --check`, and `ruff check` against the shared adapter tree | none |
| Keycloak identity | Keycloak Helm release | Kind cluster, demo-gated | OIDC identity provider for the durable-context demo: self-signup on, email verification off, public SPA client reconciled for the routed edge URL; the local demo runs one Keycloak application pod until proxy-affinity or clustered-cache validation lands, and is absent when `demo_ui = false`; see [../documents/tools/keycloak.md](../documents/tools/keycloak.md) | Keycloak Patroni Postgres state under `./.data/kind/<runtime-mode>/...` |
| Keycloak Patroni Postgres | Percona PostgreSQL operator | Kind cluster, demo-gated | dedicated HA Patroni cluster backing Keycloak per the per-service rule in [../documents/tools/postgresql.md](../documents/tools/postgresql.md); absent when `demo_ui = false` | `./.data/kind/<runtime-mode>/...` |
| Demo artifact bucket | MinIO bucket `infernix-demo-objects` | Kind cluster, demo-gated | single shared bucket holding per-user prefix trees `users/<userId>/contexts/<contextId>/{uploads,generated}/`; presigned PUT/GET URLs minted by `/api/objects` with per-user scope; absent when `demo_ui = false`; see [../documents/tools/minio.md](../documents/tools/minio.md) | MinIO durable state under `./.data/kind/<runtime-mode>/...` |
| Demo conversation Pulsar topics | Pulsar topic family `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` | Pulsar broker, demo-gated | per-context append-only conversation log; single-partition, broker-assigned `MessageId` is the canonical sequence; producer-side dedup enabled; the integration suite validates real publish + Reader decode, duplicate frontend publish collapse, completed result writeback from a non-chaos dispatcher/result-bridge prompt roundtrip, and exactly-one request/batch/result/conversation-result counts through frontend, coordinator, engine, and node-drain chaos paths; absent when `demo_ui = false` | Pulsar BookKeeper state plus tiered storage offload to MinIO |
| Demo per-user metadata topics | Pulsar topic families `demo.user.<userId>.contexts` and `demo.user.<userId>.drafts` | Pulsar broker, demo-gated | compacted per-user metadata for the left-rail context list and drafts; broker message key is `contextId`; the integration suite validates real publish + Reader decode with key assertions, admin compaction threshold readback, explicit topic compaction, compacted-reader latest-per-key behavior, and duplicate draft publish collapse; absent when `demo_ui = false` | Pulsar BookKeeper state |
| Inference batch topics | Pulsar topic family `persistent://infernix/demo/inference.batch.<mode>` plus Apple host-native handoff topic `persistent://infernix/demo/inference.batch.apple-silicon.host` | Pulsar broker | coordinator role forwards or publishes pre-batched inference work to the configured batch topic with producer dedup keyed by `batchId`; engine role consumes that topic. Linux defaults use `inference.batch.linux-cpu` / `inference.batch.linux-gpu`; Apple keeps the `.host` suffix for the on-host engine daemon | Pulsar BookKeeper state |
| Platform model bucket | MinIO bucket `infernix-models` | Kind cluster, always-on (not demo-gated) | platform-owned model weights, tokenizers, and configs; populated lazily on first use by the coordinator's bootstrap Failover subscription; per-model `.ready` sentinel object written last marks an atomic publish; engine pods pull from here into their `emptyDir` model cache | MinIO durable state under `./.data/kind/<runtime-mode>/...` |
| Model bootstrap topic | Pulsar topic `persistent://infernix/system/model.bootstrap.request` plus the `model.bootstrap.ready.<modelId>` family | Pulsar broker, always-on | exactly-once model population workflow: engine sees an uncached model → publishes a bootstrap request with producer dedup keyed by `modelId` → coordinator's Failover subscription downloads from the upstream URL in the substrate `.dhall` → uploads to `infernix-models/<modelId>/` → writes `.ready` sentinel last → publishes ready event keyed by `modelId`; the integration suite validates real ready-topic publish + Reader decode with key assertion, and publishes duplicate bootstrap requests around coordinator replacement asserting exactly one ready event; the coordinator is the only daemon with outbound-internet egress to upstream model hosts | Pulsar BookKeeper state |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | reconcile Kind, storage, Harbor-first bootstrap, image publication, staged substrate-file publication, publication state, edge port, and repo-local kubeconfig publication while recording the active lifecycle phase, child operation, and heartbeat for supported status observers; uses scratch kubeconfig state under system temp for Kind or `nvkind` create or delete so transient lock files stay off the durable repo-local paths; retained-state Apple reruns may automatically repair stopped Harbor PostgreSQL replicas from the current Patroni leader when timeline drift leaves replicas unready |
| Cluster status | `infernix cluster status` | report cluster presence, the active substrate through its current `runtimeMode` line, publication state including `publicationInferenceDispatchMode`, `publicationHostInferenceBatchTopic` when configured, and upstream mode, build or data roots, route inventory, and the active in-progress lifecycle action, phase, detail, and heartbeat fields without mutating Kubernetes resources, publication state, or authoritative repo-local state; on Linux outer-container paths it may idempotently attach the fresh launcher container to Docker's private `kind` network for observation |
| Kubernetes wrapper | `infernix kubectl ...` | scoped wrapper around upstream `kubectl` against the repo-local kubeconfig |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or reconcile derived runtime cache state without mutating authoritative sources |
| Focused lint | `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart` | run the repo-owned focused lint entrypoints for files, docs, `.proto`, and chart assets |
| Aggregate static validation | `infernix test lint` | validate the active staged substrate at command entry, then run the focused lint entrypoints together with Haskell style/build and Python quality checks |
| Docs validation | `infernix docs check` | validate the governed docs suite and phase-plan shape through the canonical docs linter |
| Service runtime | `infernix service` | consume the staged substrate file at startup and own inference for the active substrate through real Pulsar transport on supported cluster paths, with a repo-local topic-spool harness available only when Pulsar endpoints are intentionally absent |
| Demo UI runtime | `infernix-demo` deployment | serve the demo-only HTTP surface against the active generated substrate catalog |
| Frontend contract generation | `infernix internal generate-purs-contracts` | generate the supported PureScript contract module from Haskell source |
| Unit validation | `infernix test unit` | validate the active staged substrate at command entry, then run Haskell runtime behavior checks plus PureScript unit suites without claiming cluster matrix coverage |
| Integration validation | `infernix test integration` | validate the built substrate's published catalog contract through one substrate-aware integration suite that traverses the README matrix rows, selects the active engine from the generated `.dhall`, covers every generated active-substrate catalog entry, and carries the supported real-cluster HA or lifecycle assertions |
| Routed E2E validation | `infernix test e2e` | exercise the real routed browser surface for the built substrate through a substrate-agnostic Playwright suite that relies on `infernix-demo` to read the generated `.dhall` and dispatch the correct engine |
| Cross-hardware phase closure | Apple Silicon full-suite run plus CUDA Linux `linux-gpu` full-suite run | record paired cohort evidence for a coherent phase state while allowing day-to-day development to stay on one machine until the closure batch |
| Style toolchain bootstrap | `src/Infernix/Lint/HaskellStyle.hs` | install `ormolu` and `hlint` through `cabal install` against the project `ghc-9.12.4` compiler into `./.build/haskell-style-tools/bin/` and run `ormolu`, `hlint`, and `cabal format` checks |

## Browser and API Surface

| Route | Upstream | Purpose | Notes |
|-------|----------|---------|-------|
| `/` | HTTPRoute -> `infernix-demo` Service | demo browser UI | absent when `demo_ui` is false |
| `/api` | HTTPRoute -> `infernix-demo` Service | demo API prefix for models, publication, demo-config, and cache discovery | absent when `demo_ui` is false |
| `/api/publication` | `GET` endpoint on the `/api` route -> `infernix-demo` Service | routed publication metadata | absent when `demo_ui` is false |
| `/api/cache` | `GET` and `POST` endpoints on the `/api` route -> `infernix-demo` Service | demo cache lifecycle API | absent when `demo_ui` is false |
| `/auth` | HTTPRoute -> Keycloak Service | Keycloak login pages and OIDC endpoints for the durable-context demo; routed E2E covers self-registration to OIDC authorization-code redirect | absent when `demo_ui` is false |
| `/ws` | HTTPRoute -> `infernix-demo` Service | WebSocket endpoint for authenticated durable-context sessions; carries chat, drafts, context list, progress, and artifact-ready notifications | absent when `demo_ui` is false |
| `/api/objects` | HTTPRoute -> `infernix-demo` Service | HTTP endpoint that mints presigned MinIO PUT/GET URLs scoped per user; artifact bytes never traverse the demo backend | absent when `demo_ui` is false |
| `/harbor/api` | HTTPRoute -> Harbor core Service | Harbor API surface | always published |
| `/harbor` | HTTPRoute -> Harbor portal Service | Harbor browser portal | always published |
| `/minio/console` | HTTPRoute -> MinIO console Service | MinIO console | always published |
| `/minio/s3` | HTTPRoute -> MinIO S3 Service | MinIO S3 API | always published |
| `/pulsar/admin` | HTTPRoute -> Pulsar admin Service | Pulsar admin surface | always published |
| `/pulsar/ws` | HTTPRoute -> Pulsar HTTP or WebSocket Service | Pulsar browser-facing HTTP surface | always published |

## Substrate Inventory

| Substrate | Canonical substrate id | Supported contract | Current repo gap |
|-----------|------------------------|--------------------|------------------|
| Apple Silicon / Metal | `apple-silicon` | host-native control plane, cluster `infernix-coordinator` daemon for request-topic consumption and host-batch handoff, same-binary host engine daemons consuming Apple batch topics and publishing results, and clustered support services plus optional routed demo workloads sharing the same substrate file and route contracts | none |
| Linux / CPU | `linux-cpu` | containerized Linux lane built from the shared substrate Dockerfile and driven entirely through Compose on native Linux amd64 or native Linux arm64; publication selects the normalized native host architecture from `InfernixHost.dhall`; native arm64 publication and full-suite validation closed in Wave F on the recorded validation through the selected native arm64 Docker daemon | none |
| Linux / NVIDIA GPU | `linux-gpu` | GPU-enabled Kind lane built from the shared substrate Dockerfile and deployed from the same CUDA-based image used by the outer container | none |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Matrix registry -> staged substrate file | local staging boundary | typed Dhall record at `infernix-substrate.dhall`, schema at `dhall/InfernixSubstrate.dhall` | `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs` | Apple staging lives under `./.build/`; Linux outer-container staging lives under `/workspace/.build/outer-container/build/` in the launcher image; the active substrate selects engine bindings and daemon roles consumed by cluster daemons, Apple host daemons, `infernix-demo`, and the integration suite |
| Staged substrate file -> ConfigMap publication | control plane | real ConfigMap data plus repo-local mirror | `infernix cluster up` | the repo-local mirror stores the cluster-role `infernix-substrate.dhall`, and cluster-resident consumers, including Apple and Linux cluster daemons plus the routed demo surface, mount the same filename at `/opt/build/infernix-substrate.dhall`; Apple host daemons read a host-role config from the host build root |
| Browser <-> demo API | external (demo only) | JSON over HTTP | handwritten Haskell browser-contract ADTs plus generated PureScript bindings | production deployments do not expose this surface |
| Inference requester <-> Pulsar | external | protobuf over Pulsar topics | repo-owned `.proto` schemas with Haskell and Python generated bindings | production inference surface |
| Coordinator -> engine | internal production path on every substrate | protobuf batches over the dedicated `inference.batch.<mode>` Pulsar topic family plus Apple `inference.batch.apple-silicon.host` | `src/Infernix/Runtime/Pulsar.hs` plus coordinator-role and engine-role `.dhall` config | the coordinator role publishes pre-batched inference work to the configured batch handoff topic with producer dedup; the engine role consumes from it. On Apple the engine role is the on-host daemon and the topic is `inference.batch.apple-silicon.host`; on Linux substrates both daemons run as separate in-cluster Deployments and use `inference.batch.linux-cpu` / `inference.batch.linux-gpu`. Pulsar-owned topics, exclusive subscriptions, and acknowledgement handling keep batch ownership unambiguous |
| Haskell worker <-> Python adapter | internal child-process boundary | protobuf over stdio | `src/Infernix/Runtime/Worker.hs` plus `python/adapters/` | invoked only through `poetry run` |
| Browser <-> demo WebSocket | external (demo only) | typed framed envelopes (JSON via `Simple.JSON`) carrying server-sent `ConversationState`/`*Patch` snapshots/deltas and client-sent typed actions | handwritten Haskell browser-contract ADTs in `src/Infernix/Web/Contracts.hs` plus generated PureScript bindings via purescript-bridge | absent when `demo_ui = false`; business logic stays Haskell-only |

## State and Artifact Locations

| State class | Authority | Durable home | Notes |
|-------------|-----------|--------------|-------|
| Durable PV directories | storage reconciliation in `cluster up` | `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` | deterministic host path layout for every PVC-backed workload |
| Generated Apple substrate file | binary-owned lifecycle or validation preflight, with `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]` as the explicit helper | `./.build/infernix-substrate.dhall` | Apple host path beside the build root; lifecycle staging is a binary responsibility rather than a shell bootstrap responsibility |
| Generated Apple kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` on Apple; Kind create or delete uses transient scratch kubeconfig state under system temp before this file is published |
| Generated Linux substrate file | binary-owned lifecycle or validation preflight, with `docker compose --project-name <lane> --file compose.yaml ... run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>` as the explicit helper; the Dockerfile also creates an image-local build-arg-selected copy during image build | image-local `/workspace/.build/outer-container/build/infernix-substrate.dhall` | outer-container staging path; the authoritative launcher binary remains `/usr/local/bin/infernix` inside the substrate image |
| Generated Linux kubeconfig | `cluster up` | `./.data/runtime/infernix.kubeconfig` | durable repo-local kubeconfig reused across fresh outer-container invocations; Kind or `nvkind` create or delete uses transient scratch kubeconfig state under system temp before this file is published |
| Helm dependency archive cache | `cluster up`, `test integration`, `test all`, and any supported chart-reconcile path that calls `ensureHelmDependencies` | image-local `/opt/infernix/chart/charts/` on the Linux outer-container path, exposed to Helm through `/workspace/chart/charts`; `chart/charts/` in the Apple host worktree | cached top-level Helm dependency archives for Harbor, PostgreSQL, Pulsar, MinIO, and Envoy Gateway |
| Cluster-mounted substrate file | Helm deployment plus ConfigMap mount | `/opt/build/infernix-substrate.dhall` | cluster-resident consumers — `infernix-demo` (frontend), `infernix-coordinator` (Pulsar coordinator role), and `infernix-engine` (engine role on Linux substrates) — consume the cluster-role payload under the shared staged filename at `/opt/build/`; Apple on-host engine daemons read host-role config under `./.build/` |
| Outer-container build root | containerized build or runtime | image-local `/workspace/.build/outer-container/build/` in the outer container | substrate-file root used by the outer-container control plane; carries the staged substrate file only |
| Source snapshot manifest | Linux outer-container image build | `/opt/infernix/source-snapshot-files.txt` inside the substrate image | sorted source snapshot captured from the baked image context before later generated outputs so git-less image runs of `infernix lint files` validate only the baked source tree; the manifest stays in the image overlay |
| Outer-container cabal-home and builddir | Linux outer-container image overlay | the toolchain's natural in-image locations (`/root/.cabal/`, `dist-newstyle/`) | populated during `docker compose build infernix`; not bind-mounted to the host so cabal package state stays in the image overlay |
| Publication state | `cluster up`, `cluster down` | `./.data/runtime/publication.json` | route inventory and substrate metadata |
| ConfigMap publication mirror | `cluster up` | `./.data/runtime/configmaps/infernix-demo-config/` | mirrored cluster-role substrate `.dhall` plus rendered YAML |
| Chosen edge port record | cluster lifecycle | `./.data/runtime/edge-port.json` | records the `9090`-first chosen port |
| Service model cache | service runtime | `./.data/runtime/model-cache/<substrate>/<model-id>/default/` | derived cache keyed by substrate and model |
| Generated frontend contract staging | `infernix internal generate-purs-contracts` | `web/src/Generated/` | generated PureScript output only |
| Generated frontend dist | `npm --prefix web run build` | `web/dist/` | ignored static output served by `infernix-demo` |
| Apple adapter venv | Poetry on demand | `python/.venv/` | Apple-only materialized virtualenv for shared adapter project |
| Playwright and test artifacts | validation flows | `./.data/` | repo-local test output location |
| Demo artifact bucket prefixes | demo backend + presigned URL clients | MinIO bucket `infernix-demo-objects` (`users/<userId>/contexts/<contextId>/{uploads,generated}/`) | per-user prefix layout; absent when `demo_ui = false` |
| Demo conversation Pulsar topics | demo backend | Pulsar BookKeeper plus tiered MinIO offload | append-only per-context conversation logs; SSoT for sequencing and text; the integration suite validates real publish + Reader decode, duplicate frontend publish collapse, and completed result writeback from a non-chaos dispatcher/result-bridge prompt roundtrip; absent when `demo_ui = false` |
| Demo metadata Pulsar topics | demo backend | Pulsar BookKeeper | compacted per-user contexts and drafts topics keyed by `contextId`; SSoT for the left-rail list and unsubmitted drafts; the integration suite validates real publish + Reader decode with key assertions, admin compaction threshold readback, explicit topic compaction, compacted-reader latest-per-key behavior, and duplicate draft publish collapse; absent when `demo_ui = false` |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
- [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md)
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
