# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, supported
> substrates, and durable state locations in `infernix`.

## Current Repo Assessment

- the repo ships the two-binary Haskell topology, Envoy Gateway assets, the PureScript demo UI,
  the split runtime modules under `src/Infernix/Runtime/`, the shared Python project, the shared
  Linux substrate Dockerfile, the baked source-snapshot manifest used by git-less
  `infernix lint files` runs, the route registry, and the snapshot launcher
- the supported CLI reads the active substrate from `infernix-substrate.dhall` once that file has
  been staged, without a user-facing runtime-mode flag
- the supported staging path is explicit:
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]` on
  Apple and
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  on the Linux outer-container path, which writes
  `./.build/outer-container/build/infernix-substrate.dhall` on the host through the bind-mounted
  build tree
- supported runtime, cluster, and validation entrypoints fail fast if the staged substrate file is
  absent
- the staged substrate file, `cluster status`, publication JSON, demo config, and generated
  browser contracts still expose that active substrate through `runtimeMode` field names
- cluster publication mirrors the staged payload locally as `infernix-substrate.dhall`, and the
  rendered chart mounts that same filename inside cluster workloads at
  `/opt/build/infernix-substrate.dhall`
- the intended Apple product shape is a hybrid lane: `apple-silicon` keeps inference host-native
  for Apple GPU and unified-memory access while Kind continues to host Harbor, MinIO, Pulsar,
  PostgreSQL, Envoy Gateway, and the optional routed demo surface
- the current worktree closes that Apple hybrid lane: `cluster up` no longer deploys
  `infernix-service` on `apple-silicon`, routed manual inference bridges from the clustered demo
  surface into the host daemon, publication exposes `inferenceDispatchMode`, and unsupported
  engine adapters fail fast instead of returning synthetic inference success
- Linux operator workflows close around Compose-driven outer containers, validation reports only
  the active built substrate, and the supported materialization path can emit `demo_ui = false`
- direct `infernix-demo` execution no longer doubles as a compatibility target for Harbor, MinIO,
  or Pulsar tool-route probes; those checks now require the real Gateway-backed upstream behavior
- the supported Linux bootstrap entrypoints now restage the active substrate before lifecycle and
  test commands, and `cluster up` persists repo-local cluster state before later rollout phases so
  `cluster status` and cleanup can still observe an in-progress Linux reconciliation
- the full supported `linux-cpu` lifecycle now reruns cleanly on the governed bootstrap surface,
  including the stricter real-upstream route assertions, the restaged Linux substrate flow, and
  the dedicated `ghc-9.12.4` formatter toolchain that the style gate now uses beside the project
  `ghc-9.14.1` compiler
- the governed `linux-gpu` lifecycle now also reruns cleanly, the supported Linux launcher keeps a
  reusable `chart/charts/` cache on the host instead of reconstructing Helm archives inside
  ephemeral containers, the MinIO dependency hydrates through the supported direct tarball path,
  and `cluster up` now repairs the known stale retained Pulsar or ZooKeeper epoch mismatch by
  resetting only the Pulsar claim roots and retrying once
- the Apple clean-host bootstrap now verifies same-process ghcup-managed `ghc` and `cabal`
  resolution before direct `cabal install`, reconciles Homebrew `protoc`, reconciles Colima to
  the supported `8 CPU / 16 GiB` profile before Docker-backed work, and lets Apple adapter setup
  or validation paths reconcile Homebrew `python@3.12` plus a user-local Poetry bootstrap on
  demand
- on May 11, 2026, the governed Apple lifecycle reran cleanly through `doctor`, `build`, `up`,
  `status`, `test`, and `down`; routed Apple Playwright readiness probes `127.0.0.1` from the
  host while the browser container joins the private Docker `kind` network and targets the Kind
  control-plane DNS, and retained Kind state is replayed into and out of the worker rather than
  bind-mounted
- on May 12, 2026, a cold Apple lifecycle investigation confirmed that the shared `cluster up`
  and `cluster down` paths do converge, but they still expose false-negative risk because the
  current operator surfaces do not report enough progress during Docker build finalization,
  Harbor publication, Kind-worker image preload, or retained-state replay
- Monitoring is not a supported first-class surface.

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix` plus direct `cabal` materialization against operator-installed ghcup | host-native | canonical operator surface on Apple Silicon; host-native cluster lifecycle owner; host-native Apple inference-daemon owner; repo-local kubeconfig owner | `./.build/`, `./.data/` |
| Linux outer-container control plane | `docker compose run --rm infernix infernix ...` | Linux container | only supported Linux CLI surface for `linux-cpu` and `linux-gpu`; selects the active `infernix-linux-<mode>:local` snapshot through `INFERNIX_COMPOSE_*` launcher variables, forwards the Docker socket, and bind-mounts `./.data/`, `./.build/`, `./chart/charts/`, and the host `compose.yaml` so the staged substrate file under `./.build/outer-container/build/` is visible from the host while reusable Helm chart archives survive fresh launcher containers and cabal package state stays in the image overlay at the toolchain's natural locations | `./.data/`, `./.data/runtime/infernix.kubeconfig`, `./.build/outer-container/build/infernix-substrate.dhall`, `./chart/charts/` |
| Command registry | structured Haskell parser or dispatcher registry | host or outer container | owns the supported command inventory, `--help` output, and the generated CLI-reference sections that docs lint enforces | none |
| Substrate configuration | staged banner-prefixed JSON payload at the legacy `infernix-substrate.dhall` path | host or outer container | primary source of truth for active substrate, generated catalog content, daemon placement, active engine dispatch, routed Apple bridge behavior, and test scope once the file has been staged | `./.build/infernix-substrate.dhall` on Apple; `./.build/outer-container/build/infernix-substrate.dhall` on the Linux outer-container path; cluster pods mount the same payload at `/opt/build/infernix-substrate.dhall` |
| Route registry | Haskell-owned route inventory | host or outer container during render or reconcile | records public prefixes, backend identity, rewrite rules, visibility, and publication metadata | none |
| Automation entry documents | `AGENTS.md`, `CLAUDE.md`, and their governed canonical-home links into `documents/` | repo source | point assistant users at canonical workflow rules without turning root entry docs into competing topic homes | none |
| Frontend contract generator | `infernix internal generate-purs-contracts` | host or outer container during web build | emits generated PureScript contracts from handwritten Haskell browser-contract ADTs | `web/src/Generated/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, runtime state, config publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | explicit Cabal builddir or installdir flags plus generated artifacts | host or outer container | keeps compiled output and generated files out of tracked source paths | `./.build/` on Apple; `./.build/outer-container/` on the host through the outer-container bind mount |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Linux substrate image definition | `docker/linux-substrate.Dockerfile` | one shared build definition produces the Linux control-plane image and the Linux daemon image family while owning ghcup, Poetry, Node.js 22+ for the demo bundle, and the Kind toolbelt; carries no browser-runtime weight; cabal-home and the cabal builddir live at the toolchain's natural in-image locations rather than under any bind-mounted host path; the image uses `tini` as its `ENTRYPOINT` for clean signal handling and zombie reaping | none |
| Playwright image definition | `docker/playwright.Dockerfile` | dedicated single-purpose image (`infernix-playwright:local`) that owns Node, the Playwright runtime, and the three browsers, used by every substrate for routed E2E through `docker compose run --rm playwright` | none |
| Compose launcher | `compose.yaml` | env-configurable outer-container launcher for supported Linux workflows; defines the `infernix` service for the control plane and the `playwright` service for routed Playwright execution | none |
| Shared Python adapter project | `python/pyproject.toml`, `python/adapters/` | single dependency boundary and adapter tree for Python-native engines | none in the supported operator contract |
| Apple host prerequisite bootstrap | governed docs plus Haskell bootstrap logic | minimize Apple pre-existing host installs and let `infernix` reconcile supported Homebrew-managed tools and Poetry bootstrap | none |
| Testing doctrine docs | `documents/engineering/testing.md` and `documents/development/testing_strategy.md` | keep one canonical testing doctrine together with one operator-facing detail layer | none |
| Browser-contract source | `src/Infernix/Web/Contracts.hs`, `web/package.json` | keeps handwritten Haskell contract source out of `Generated/` while preserving generated PureScript output there | none |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | hold repo-owned workloads, ConfigMaps, Gateway resources, and third-party chart dependencies | none |
| Kind topology assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml` | substrate-specific Kind shapes, including the GPU-enabled `linux-gpu` lane | none |
| Protobuf contract assets | `proto/infernix/...` plus on-demand generated `tools/generated_proto/` stubs | define canonical runtime, manifest, and event schema boundaries | generated stubs must stay untracked |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native Apple CLI or Linux outer container | create or reuse Kind, reset StorageClasses, reconcile PVs, deploy Harbor first, publish the staged substrate payload, publish images, deploy the final chart, and retry once with a targeted Pulsar claim-root reset when retained ZooKeeper state is self-inconsistent; current open gap: the supported operator surface does not yet expose enough in-progress phase detail to prevent false-negative failure classification during cold-start image build, publication, or preload work | `./.data/runtime/cluster-state.state`, `./.data/kind/<runtime-mode>/...` |
| Harbor image preparation | Harbor plus Haskell image publication flow | Kind cluster plus control plane | bootstrap Harbor, mirror required images, and publish repo-owned images before later rollout | Harbor state under `./.data/kind/<runtime-mode>/...` |
| PostgreSQL substrate | Percona Kubernetes operator plus Patroni PostgreSQL | Kind cluster | only supported in-cluster PostgreSQL contract for Harbor and later services | `./.data/kind/<runtime-mode>/...` |
| Publication state | repo-local JSON plus routed `/api/publication` surface | repo-local state and demo API | reports control-plane context, the direct `infernix service` daemon location, the routed demo API upstream mode, any Apple host-inference bridge mode, the active substrate through its current `runtimeMode` field, routes, and upstream health metadata | `./.data/runtime/publication.json` |
| Edge Gateway controller | Helm-installed Envoy Gateway controller | Kind cluster | owns all browser-visible and host-consumed routing | none |
| Cluster Gateway resource | `GatewayClass/infernix-gateway` plus `Gateway/infernix-edge` | Kind cluster | single localhost-bound HTTP listener on the chosen edge port | none |
| HTTPRoute rendering | data-driven `chart/templates/httproutes.yaml` from the Haskell route registry | Kind cluster | publishes the route inventory for demo, Harbor, MinIO, and Pulsar surfaces | none |
| Substrate-file publication | generated `ConfigMap/infernix-demo-config` plus repo-local mirror | Kind cluster and repo-local state | republishes the staged substrate payload for cluster consumers and local inspection tooling through the shared `infernix-substrate.dhall` filename | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime host | `infernix service` plus `src/Infernix/Runtime/{Cache,Worker,Pulsar}.hs` | direct host process or cluster pod | the supported Apple contract keeps `infernix service` host-native on `apple-silicon`, while Linux daemon workloads run in cluster pods on `linux-cpu` and `linux-gpu`; the host daemon auto-discovers the routed Pulsar edge on Apple when the publication state records a live cluster, and unsupported engine adapters fail fast instead of returning synthetic success | `./.data/runtime/`, object-store state under `./.data/object-store/` |
| Demo UI host | `infernix-demo` deployment | cluster pod | serves `/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/` when demo is enabled; on Apple, routed manual inference stays browser-visible through the clustered demo surface but bridges into the host-native daemon rather than running in a cluster-resident Apple service workload; direct `infernix-demo` execution intentionally exposes only the demo-owned HTTP surface outside the intended HTTPRoute mapping | none |
| Web runtime executor | PureScript bundle baked into the Linux substrate image plus the dedicated `infernix-playwright:local` Playwright image | substrate image runs cluster-resident as the demo app; Playwright image is invoked via `docker compose run --rm playwright`, directly from the host CLI on Apple Silicon and from inside the outer container against the host docker daemon on Linux substrates. On Apple, host-side readiness probes `127.0.0.1:<edge-port>` while the browser container joins the `kind` network and targets the Kind control-plane DNS on port `30090` | serves the browser bundle from the clustered demo app and runs routed E2E coverage from the dedicated Playwright executor | test artifacts under `./.data/` |
| Engine adapter set | `python/adapters/` invoked via `poetry run` from the Haskell worker | host child process or cluster child process | Python-native engine boundary over typed protobuf-over-stdio | optional Apple venv under `python/.venv/` |
| Python quality gate | `poetry run check-code` | host or Linux outer-container image | runs mypy strict, black check, and ruff strict against the shared adapter tree | none |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | reconcile Kind, storage, Harbor-first bootstrap, image publication, staged substrate-file publication, publication state, and edge port; current open gap: cold-start progress is still too opaque during long Docker build, Harbor publication, and Kind-worker preload phases |
| Cluster status | `infernix cluster status` | report cluster presence, the active substrate through its current `runtimeMode` line, publication state, build or data roots, and route inventory without mutation; current open gap: it does not yet expose the active in-progress lifecycle phase or long-running child operation |
| Kubernetes wrapper | `infernix kubectl ...` | scoped wrapper around upstream `kubectl` against the repo-local kubeconfig |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or reconcile derived runtime cache state without mutating authoritative sources |
| Focused lint | `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart` | run the repo-owned focused lint entrypoints for files, docs, `.proto`, and chart assets |
| Aggregate static validation | `infernix test lint` | run the focused lint entrypoints together with Haskell style/build and Python quality checks |
| Docs validation | `infernix docs check` | validate the governed docs suite and phase-plan shape through the canonical docs linter |
| Service runtime | `infernix service` | consume the staged substrate file at startup and own inference for the active substrate |
| Demo UI runtime | `infernix-demo` deployment | serve the demo-only HTTP surface against the active generated substrate catalog |
| Frontend contract generation | `infernix internal generate-purs-contracts` | generate the supported PureScript contract module from Haskell source |
| Unit validation | `infernix test unit` | validate Haskell runtime behavior plus PureScript unit suites |
| Integration validation | `infernix test integration` | validate the built substrate's published catalog contract through one substrate-aware integration suite that traverses the README matrix rows, selects the active engine from the generated `.dhall`, covers every generated active-substrate catalog entry, and carries the supported real-cluster HA or lifecycle assertions |
| Routed E2E validation | `infernix test e2e` | exercise the real routed browser surface for the built substrate through a substrate-agnostic Playwright suite that relies on `infernix-demo` to read the generated `.dhall` and dispatch the correct engine |
| Style toolchain bootstrap | `src/Infernix/Lint/HaskellStyle.hs` | bootstrap the dedicated formatter compiler under `.build/haskell-style-tools/bin/` and run `ormolu`, `hlint`, and `cabal format` checks |

## Browser and API Surface

| Route | Upstream | Purpose | Notes |
|-------|----------|---------|-------|
| `/` | HTTPRoute -> `infernix-demo` Service | demo browser UI | absent when `demo_ui` is false |
| `/api` | HTTPRoute -> `infernix-demo` Service | demo API prefix for models, publication, cache, and manual inference | absent when `demo_ui` is false |
| `/api/publication` | `GET` endpoint on the `/api` route -> `infernix-demo` Service | routed publication metadata | absent when `demo_ui` is false |
| `/api/cache` | `GET` and `POST` endpoints on the `/api` route -> `infernix-demo` Service | demo cache lifecycle API | absent when `demo_ui` is false |
| `/objects/<objectRef>` | HTTPRoute -> `infernix-demo` Service | demo object-store fixture access | absent when `demo_ui` is false |
| `/harbor/api` | HTTPRoute -> Harbor core Service | Harbor API surface | always published |
| `/harbor` | HTTPRoute -> Harbor portal Service | Harbor browser portal | always published |
| `/minio/console` | HTTPRoute -> MinIO console Service | MinIO console | always published |
| `/minio/s3` | HTTPRoute -> MinIO S3 Service | MinIO S3 API | always published |
| `/pulsar/admin` | HTTPRoute -> Pulsar admin Service | Pulsar admin surface | always published |
| `/pulsar/ws` | HTTPRoute -> Pulsar HTTP or WebSocket Service | Pulsar browser-facing HTTP surface | always published |

## Substrate Inventory

| Substrate | Canonical substrate id | Supported contract | Current repo gap |
|-----------|------------------------|--------------------|------------------|
| Apple Silicon / Metal | `apple-silicon` | host-native control plane, host-native inference daemon, and clustered support services plus optional routed demo workloads sharing the same substrate file and route contracts | none |
| Linux / CPU | `linux-cpu` | containerized Linux lane built from the shared substrate Dockerfile and driven entirely through Compose | none |
| Linux / NVIDIA GPU | `linux-gpu` | GPU-enabled Kind lane built from the shared substrate Dockerfile and deployed from the same CUDA-based image used by the outer container | none |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Matrix registry -> staged substrate file | local staging boundary | banner-prefixed JSON under a legacy `.dhall` filename | `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs` | Apple staging lives under `./.build/`; Linux outer-container staging lives under `./.build/outer-container/build/` on the host; the active substrate selects engine bindings consumed by the host-native Apple daemon, Linux cluster daemons, `infernix-demo`, and the integration suite |
| Staged substrate file -> ConfigMap publication | control plane | real ConfigMap data plus repo-local mirror | `infernix cluster up` | the repo-local mirror stores `infernix-substrate.dhall`, and any cluster-resident consumer, including the Apple routed demo surface and Linux daemon workloads, mounts the same filename at `/opt/build/infernix-substrate.dhall` |
| Browser <-> demo API | external (demo only) | JSON over HTTP | handwritten Haskell browser-contract ADTs plus generated PureScript bindings | production deployments do not expose this surface |
| Inference requester <-> Pulsar | external | protobuf over Pulsar topics | repo-owned `.proto` schemas with Haskell and Python generated bindings | production inference surface |
| Haskell worker <-> Python adapter | internal child-process boundary | protobuf over stdio | `src/Infernix/Runtime/Worker.hs` plus `python/adapters/` | invoked only through `poetry run` |

## State and Artifact Locations

| State class | Authority | Durable home | Notes |
|-------------|-----------|--------------|-------|
| Durable PV directories | storage reconciliation in `cluster up` | `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` | deterministic host path layout for every PVC-backed workload |
| Generated Apple substrate file | `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]` | `./.build/infernix-substrate.dhall` | Apple host path beside the build root; the file is staged explicitly rather than by Cabal compile rules alone |
| Generated Apple kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` on Apple |
| Generated Linux substrate file | explicit helper invocation runs `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>` | `./.build/outer-container/build/infernix-substrate.dhall` on the host through the bind mount (visible inside the outer container as `/workspace/.build/outer-container/build/infernix-substrate.dhall`) | outer-container staging path; the authoritative launcher binary remains `/usr/local/bin/infernix` inside the substrate image |
| Generated Linux kubeconfig | `cluster up` | `./.data/runtime/infernix.kubeconfig` | durable repo-local kubeconfig reused across fresh outer-container invocations |
| Helm dependency archive cache | `cluster up`, `test integration`, `test all`, and any supported chart-reconcile path that calls `ensureHelmDependencies` | `./chart/charts/` on the host for the Linux outer-container path; `chart/charts/` in the Apple host worktree | cached top-level Helm dependency archives for Harbor, PostgreSQL, Pulsar, MinIO, and Envoy Gateway so fresh launcher containers reuse the same chart bundle instead of rehydrating every dependency from the network |
| Cluster-mounted substrate file | Helm deployment plus ConfigMap mount | `/opt/build/infernix-substrate.dhall` | cluster-resident consumers such as `infernix-demo` and Linux `infernix service` workloads consume the shared staged filename under `/opt/build/`; the Apple host daemon reads the colocated host copy under `./.build/` |
| Outer-container build root | containerized build or runtime | `./.build/outer-container/build/` on the host (mapped to `/workspace/.build/outer-container/build/` in the outer container) | host-anchored substrate-file root used by the outer-container control plane; carries the staged substrate file only |
| Source snapshot manifest | Linux outer-container image build | `/opt/infernix/source-snapshot-files.txt` inside the substrate image | sorted source snapshot captured from the baked image context before later generated outputs so git-less image runs of `infernix lint files` validate only the baked source tree; the manifest is intentionally outside the bind-mounted `./.build/` tree so it stays in the image overlay |
| Outer-container cabal-home and builddir | Linux outer-container image overlay | the toolchain's natural in-image locations (`/root/.cabal/`, `dist-newstyle/`) | populated during `docker compose build infernix`; not bind-mounted to the host so cabal package state stays in the image overlay |
| Durable runtime artifact bundles | service runtime and cache materialization | `./.data/object-store/artifacts/<substrate>/<model-id>/bundle.json` | durable worker input metadata |
| Durable source-artifact manifests | service runtime and cache materialization | `./.data/object-store/source-artifacts/<substrate>/<model-id>/source.json` | authoritative artifact-selection metadata |
| Publication state | `cluster up`, `cluster down` | `./.data/runtime/publication.json` | route inventory and substrate metadata |
| ConfigMap publication mirror | `cluster up` | `./.data/runtime/configmaps/infernix-demo-config/` | mirrored substrate `.dhall` plus rendered YAML |
| Chosen edge port record | cluster lifecycle | `./.data/runtime/edge-port.json` | records the `9090`-first chosen port |
| Service model cache | service runtime | `./.data/runtime/model-cache/<substrate>/<model-id>/default/` | derived cache keyed by substrate and model |
| Host-side cache durability manifests | service runtime and tests | `./.data/object-store/manifests/<substrate>/<model-id>/default.pb` | rebuild source for derived cache |
| Generated frontend contract staging | `infernix internal generate-purs-contracts` | `web/src/Generated/` | generated PureScript output only |
| Generated frontend dist | `npm --prefix web run build` | `web/dist/` | ignored static output served by `infernix-demo` |
| Apple adapter venv | Poetry on demand | `python/.venv/` | Apple-only materialized virtualenv for shared adapter project |
| Playwright and test artifacts | validation flows | `./.data/` | repo-local test output location |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
