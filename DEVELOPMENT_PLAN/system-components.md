# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, runtime modes,
> and durable state locations in `infernix`.

## Current Repo Assessment

- the repo already ships the two-binary Haskell topology, Envoy Gateway assets, the PureScript
  demo UI, the split runtime modules under `src/Infernix/Runtime/`, the shared Python project,
  the shared Linux substrate Dockerfile, the baked source-snapshot manifest used by git-less
  `infernix lint files` runs, the route registry, and the snapshot launcher
- the remaining open gaps are now the adapter-depth and supported-lane validation-closure gaps:
  deeper engine-library integration beyond the current durable-metadata-aware shared adapters,
  supported `linux-cuda` closure on a NVIDIA host with enough free disk headroom for Harbor
  publication plus Pulsar BookKeeper durability, and the still-partial Apple host-native engine
  bootstrap

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix` plus direct `cabal` materialization against operator-installed ghcup | host-native | canonical operator surface on Apple Silicon; host-native inference lane; repo-local kubeconfig owner | `./.build/`, `./.data/` |
| Linux outer-container control plane | `docker compose run --rm infernix infernix ...` for `linux-cpu` plus direct `docker run --gpus all ... infernix-linux-cuda:local infernix ...` for `linux-cuda` | Linux container | image-snapshot launcher for Linux workflows; forwards Docker socket and bind-mounts only `./.data/` on the supported path | `./.data/`, `/opt/build`, `/root/.cabal` |
| Command registry | Haskell parser or dispatcher registry | host or outer container | single source of truth for supported commands, help text, and CLI reference docs | none |
| Runtime-mode selector | CLI flag or `INFERNIX_RUNTIME_MODE` | host or outer container | resolves `apple-silicon`, `linux-cpu`, or `linux-cuda` independently of execution context | build-root config artifacts only |
| Route registry | Haskell-owned route inventory | host or outer container during render or reconcile | records public prefixes, backend identity, rewrite rules, visibility, and publication metadata | none |
| Frontend contract generator | `infernix internal generate-purs-contracts` | host or outer container during web build | emits generated PureScript contracts from handwritten Haskell browser-contract ADTs | `web/src/Generated/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, runtime state, config publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | explicit Cabal builddir or installdir flags plus generated artifacts | host or outer container | keeps compiled output and generated files out of tracked source paths | `./.build/` on host; `/opt/build/` in container |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Linux substrate image definition | `docker/linux-substrate.Dockerfile` | one shared build definition produces the two real Linux runtime images and owns ghcup, Poetry, Node.js 22+, Playwright, and the Kind toolbelt | the `linux-cpu` lane is validated, the image now bakes `/opt/build/infernix/source-snapshot-files.txt` for git-less `lint files` runs, and final `linux-cuda` closure remains blocked on a supported NVIDIA host with enough free disk headroom |
| Compose launcher | `compose.yaml` | one-command `linux-cpu` launcher against the baked substrate image | `cluster up` now reuses the already-built baked runtime image instead of rebuilding it inside the launcher; `cluster up`, routed Pulsar, image-owned Playwright, and the fresh exhaustive integration or HA rerun are validated on `linux-cpu` |
| Direct CUDA launcher | baked `infernix-linux-cuda:local` image plus `docker run --gpus all` | supported `linux-cuda` control-plane entrypoint against the baked substrate image | the image-owned `nvkind` path is landed; the supported rerun from April 28, 2026 reaches real cluster creation, Harbor-backed image publication, and Helm rollout before low host disk headroom makes BookKeeper ledger directories non-writable |
| Shared Python adapter project | `python/pyproject.toml`, `python/adapters/*.py` | single dependency boundary and adapter tree for Python-native engines | the worker, setup entrypoints, and durable metadata path are landed; the remaining depth gap is real heavyweight engine-library integration |
| Browser-contract source | `src/Infernix/Web/Contracts.hs` and `web/src/Generated/Contracts.purs` | keeps handwritten Haskell contract source out of `Generated/` while preserving generated PureScript output there | no material ownership gap remains in the worktree |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | hold repo-owned workloads, ConfigMaps, Gateway resources, and third-party chart dependencies | no material HA-route gap remains on the final chart shape |
| Kind topology assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-cuda.yaml` | mode-specific Kind shapes, including GPU-enabled `linux-cuda` | the topology and in-image `nvkind` path are landed; final `linux-cuda` closure still needs a supported NVIDIA host with enough free disk headroom for Harbor publication and Pulsar BookKeeper durability |
| Protobuf contract assets | `proto/infernix/...`, generated `tools/generated_proto/` stubs | define canonical runtime, manifest, and event schema boundaries | generated stubs must stay untracked |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native CLI or outer container | create or reuse Kind, reset StorageClasses, reconcile PVs, deploy Harbor first, render generated values material, publish images, and deploy the final chart | `./.data/runtime/cluster-state.state`, `./.data/kind/...` |
| Harbor image preparation | Harbor plus Haskell image publication flow | Kind cluster plus control plane | bootstrap Harbor, mirror required images, and publish repo-owned images before later rollout | Harbor state under `./.data/kind/...` |
| PostgreSQL substrate | Percona Kubernetes operator plus Patroni PostgreSQL | Kind cluster | only supported in-cluster PostgreSQL contract for Harbor and later services | `./.data/kind/...` |
| Publication state | repo-local JSON plus routed `/api/publication` surface | repo-local state and optional demo API | reports control-plane context, daemon location, runtime mode, routes, and upstream health metadata | `./.data/runtime/publication.json` |
| Edge Gateway controller | Helm-installed Envoy Gateway controller | Kind cluster | owns all browser-visible and host-consumed routing | none |
| Cluster Gateway resource | `GatewayClass/infernix-gateway` plus `Gateway/infernix-edge` | Kind cluster | single localhost-bound HTTP listener on the chosen edge port | none |
| HTTPRoute rendering | data-driven `chart/templates/httproutes.yaml` from the Haskell route registry | Kind cluster | publishes the route inventory for demo, Harbor, MinIO, and Pulsar surfaces | none |
| Demo-config publication | generated `ConfigMap/infernix-demo-config` plus repo-local mirror | Kind cluster and repo-local state | publishes the active-mode generated demo catalog to cluster consumers and local inspection tooling | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime host | `infernix service` plus `src/Infernix/Runtime/{Cache,Worker,Pulsar}.hs` | host process or cluster pod | Pulsar consumer, durable cache owner, and engine-worker supervisor | `./.data/runtime/`, object-store state under `./.data/object-store/` |
| Demo UI host | `infernix-demo serve --dhall PATH --port N` | host process or cluster pod | serves `/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/` when demo is enabled | none |
| Web runtime executor | PureScript bundle plus Playwright in the final Linux substrate image; host install on Apple | Linux substrate image or Apple host | serves the browser bundle and runs E2E coverage on the supported surface | test artifacts under `./.data/` |
| Engine adapter set | `python/adapters/*.py` invoked via `poetry run` from the Haskell worker | host child process or cluster child process | Python-native engine boundary over typed protobuf-over-stdio | optional Apple venv under `python/.venv/` |
| Python quality gate | `poetry run check-code` | host or Linux substrate image | runs mypy strict, black check, and ruff strict against the shared adapter tree | none |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | reconcile Kind, storage, Harbor-first bootstrap, image publication, generated demo-config, publication state, and edge port |
| Cluster status | `infernix cluster status` | report cluster presence, runtime mode, publication state, build or data roots, and route inventory without mutation |
| Kubernetes wrapper | `infernix kubectl ...` | scoped wrapper around upstream `kubectl` against the repo-local kubeconfig |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or reconcile derived runtime cache state without mutating authoritative sources |
| Focused lint | `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart` | run the repo-owned focused lint entrypoints for files, docs, `.proto`, and chart assets |
| Aggregate static validation | `infernix test lint` | run the focused lint entrypoints together with Haskell style/build and Python quality checks |
| Docs validation | `infernix docs check` | validate the governed docs suite and phase-plan shape through the canonical docs linter |
| Service runtime | `infernix service` | validate the active generated catalog and consume Pulsar work without binding HTTP in production |
| Demo UI runtime | `infernix-demo serve --dhall PATH --port N` | serve the demo-only HTTP surface against the active generated catalog |
| Frontend contract generation | `infernix internal generate-purs-contracts` | generate the supported PureScript contract module from Haskell source |
| Unit validation | `infernix test unit` | validate Haskell runtime behavior plus PureScript unit suites |
| Integration validation | `infernix test integration` | validate the published active-mode catalog contract, routed surfaces, cache flows, service-loop behavior, every generated active-mode catalog entry, and the supported real-cluster HA or lifecycle assertions |
| Routed E2E validation | `infernix test e2e` | exercise every demo-visible generated catalog entry through the real routed browser surface using Playwright |

## Browser and API Surface

| Route | Upstream | Purpose | Notes |
|-------|----------|---------|-------|
| `/` | HTTPRoute -> `infernix-demo` Service | demo browser UI | absent when `demo_ui` is false |
| `/api` | HTTPRoute -> `infernix-demo` Service | demo API for model listing and manual inference | absent when `demo_ui` is false |
| `/api/publication` | HTTPRoute -> `infernix-demo` Service | routed publication metadata | absent when `demo_ui` is false |
| `/api/cache` | HTTPRoute -> `infernix-demo` Service | demo cache lifecycle API | absent when `demo_ui` is false |
| `/objects/<key>` | HTTPRoute -> `infernix-demo` Service | demo object-store fixture access | absent when `demo_ui` is false |
| `/harbor` | HTTPRoute -> Harbor portal or API Service | Harbor browser and API surface | always published |
| `/minio/console` | HTTPRoute -> MinIO console Service | MinIO console | always published |
| `/minio/s3` | HTTPRoute -> MinIO S3 Service | MinIO S3 API | always published |
| `/pulsar/admin` | HTTPRoute -> Pulsar admin Service | Pulsar admin surface | always published |
| `/pulsar/ws` | HTTPRoute -> Pulsar HTTP or WebSocket Service | Pulsar browser-facing HTTP surface | always published |

## Runtime Mode Inventory

| Runtime mode | Canonical mode id | Supported contract | Current repo gap |
|--------------|-------------------|--------------------|------------------|
| Apple Silicon / Metal | `apple-silicon` | host-native control plane and host-native inference lane; shared config, route, and Pulsar contracts | engine bootstrap is still partial |
| Ubuntu 24.04 / CPU | `linux-cpu` | containerized Linux lane built from the shared substrate Dockerfile | no material linux-cpu substrate-validation gap remains in the worktree after the fresh outer-container integration rerun passed on April 28, 2026 |
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-cuda` | GPU-enabled Kind lane built from the shared substrate Dockerfile and in-image `nvkind` toolchain | the supported rerun from April 28, 2026 reaches real cluster creation, Harbor-backed image publication, and Helm rollout, but low host disk headroom makes BookKeeper non-writable before `infernix-service` becomes ready |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Matrix registry -> generated demo-config staging | local build boundary | `.dhall` derived from typed Haskell data | Haskell config or catalog modules | active runtime mode selects engine bindings |
| Generated demo-config -> ConfigMap publication | control plane | real ConfigMap data plus repo-local mirror | `infernix cluster up` | cluster workloads mount the published file at `/opt/build/` |
| Browser <-> demo API | external (demo only) | JSON over HTTP | handwritten Haskell browser-contract ADTs plus generated PureScript bindings | production deployments do not expose this surface |
| Inference requester <-> Pulsar | external | protobuf over Pulsar topics | repo-owned `.proto` schemas with Haskell and Python generated bindings | production inference surface |
| Haskell worker <-> Python adapter | internal child-process boundary | protobuf over stdio | `src/Infernix/Runtime/Worker.hs` plus `python/adapters/*.py` | invoked only through `poetry run` |

## State and Artifact Locations

| State class | Authority | Durable home | Notes |
|-------------|-----------|--------------|-------|
| Durable PV directories | storage reconciliation in `cluster up` | `./.data/kind/...` | deterministic host path layout for every PVC-backed workload |
| Generated host demo-config staging | `cluster up` | `./.build/infernix-demo-<mode>.dhall` | host path for active-mode catalog staging |
| Generated host kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` |
| Outer-container build root | containerized build or runtime | `/opt/build/` | baked-image build root and ConfigMap mount point |
| Source snapshot manifest | Linux substrate image build | `/opt/build/infernix/source-snapshot-files.txt` | sorted tracked-source snapshot captured before later generated outputs so git-less image runs of `infernix lint files` validate only the baked source tree |
| Durable runtime artifact bundles | service runtime and cache materialization | `./.data/object-store/artifacts/<runtime-mode>/<model-id>/bundle.json` | durable worker input metadata |
| Durable source-artifact manifests | service runtime and cache materialization | `./.data/object-store/source-artifacts/<runtime-mode>/<model-id>/source.json` | authoritative artifact-selection metadata |
| Publication state | `cluster up`, `cluster down`, `infernix service` | `./.data/runtime/publication.json` | route inventory and runtime metadata |
| ConfigMap publication mirror | `cluster up` | `./.data/runtime/configmaps/infernix-demo-config/` | mirrored generated `.dhall` plus rendered YAML |
| Chosen edge port record | cluster lifecycle | `./.data/runtime/edge-port.json` | records the `9090`-first chosen port |
| Service model cache | service runtime | `./.data/runtime/model-cache/<runtime-mode>/<model-id>/default/` | derived cache keyed by mode and model |
| Host-side cache durability manifests | service runtime and tests | `./.data/object-store/manifests/<runtime-mode>/<model-id>/default.pb` | rebuild source for derived cache |
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
