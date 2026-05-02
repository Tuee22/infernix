# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, supported
> substrates, and durable state locations in `infernix`.

## Current Repo Assessment

- the repo already ships the two-binary Haskell topology, Envoy Gateway assets, the PureScript
  demo UI, the split runtime modules under `src/Infernix/Runtime/`, the shared Python project,
  the shared Linux substrate Dockerfile, the baked source-snapshot manifest used by git-less
  `infernix lint files` runs, the route registry, and the snapshot launcher
- the current worktree still exposes runtime-mode flags, per-mode generated `.dhall` filenames,
  simulated cluster, route, and filesystem-Pulsar fallback behavior, the Apple host bridge, and
  the direct `linux-cuda` launcher as part of the implemented baseline
- this plan now targets a compile-time generated substrate `.dhall` single-source-of-truth model,
  a clustered demo app across substrates, Compose-only Linux CLI launchers, and substrate-specific
  validation reporting
- the governed root docs and `documents/` suite outside `DEVELOPMENT_PLAN/` have not yet been
  updated in this turn, so the broader documentation reset remains an explicit open dependency
- Monitoring is not a supported first-class surface.

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix` plus direct `cabal` materialization against operator-installed ghcup | host-native | canonical operator surface on Apple Silicon; host-native cluster lifecycle owner; host-native inference daemon owner; repo-local kubeconfig owner | `./.build/`, `./.data/` |
| Linux outer-container control plane | `docker compose run --rm infernix infernix ...` | Linux container | only supported Linux CLI surface for `linux-cpu` and `linux-gpu`; forwards Docker socket and bind-mounts only `./.data/` on the supported path | `./.data/`, `./.data/runtime/infernix.kubeconfig`, `/opt/build/infernix/`, `/root/.cabal` |
| Command registry | structured Haskell parser or dispatcher registry | host or outer container | owns the supported command inventory, `--help` output, and the generated CLI-reference sections that docs lint enforces | none |
| Substrate configuration | compile-time generated `.dhall` beside the built binary | host or outer container | single source of truth for active substrate, generated catalog content, daemon placement, active engine dispatch, and test scope | `./.build/infernix-substrate.dhall`, `/opt/build/infernix/infernix-substrate.dhall` |
| Route registry | Haskell-owned route inventory | host or outer container during render or reconcile | records public prefixes, backend identity, rewrite rules, visibility, and publication metadata | none |
| Automation entry documents | `AGENTS.md`, `CLAUDE.md`, and their governed canonical-home links into `documents/` | repo source | point assistant users at canonical workflow rules without turning root entry docs into competing topic homes | none |
| Frontend contract generator | `infernix internal generate-purs-contracts` | host or outer container during web build | emits generated PureScript contracts from handwritten Haskell browser-contract ADTs | `web/src/Generated/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, runtime state, config publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | explicit Cabal builddir or installdir flags plus generated artifacts | host or outer container | keeps compiled output and generated files out of tracked source paths | `./.build/` on Apple; `/opt/build/infernix/` in the outer-container control plane |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Linux substrate image definition | `docker/linux-substrate.Dockerfile` | one shared build definition produces the Linux control-plane image and the Linux daemon image family while owning ghcup, Poetry, Node.js 22+, Playwright, and the Kind toolbelt | the current repo still expresses the GPU lane as `linux-cuda` and still treats direct GPU launch as supported |
| Compose launcher | `compose.yaml` | one-command outer-container launcher for supported Linux workflows | the target doctrine still needs the launcher and docs reset that removes any user-facing direct GPU path |
| Shared Python adapter project | `python/pyproject.toml`, `python/adapters/` | single dependency boundary and adapter tree for Python-native engines | the current adapter contract is deterministic and metadata-driven; later phases still need to remove the remaining simulation implementation paths from the supported runtime and validation contract |
| Apple host prerequisite bootstrap | governed docs plus Haskell bootstrap logic | minimize Apple pre-existing host installs and let `infernix` reconcile supported Homebrew-managed tools and Poetry bootstrap | the current docs still need to align Apple host bootstrap with the clustered demo-app and container-owned Playwright doctrine |
| Testing doctrine docs | `documents/engineering/testing.md` and `documents/development/testing_strategy.md` | keep one canonical testing doctrine together with one operator-facing detail layer | the docs still describe cross-substrate matrix coverage, substrate-specific test branching, and simulated fallback behavior as part of the supported story |
| Browser-contract source | `src/Infernix/Web/Contracts.hs`, `web/package.json` | keeps handwritten Haskell contract source out of `Generated/` while preserving generated PureScript output there | no material ownership gap remains beyond the reopened substrate-doctrine docs reset |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | hold repo-owned workloads, ConfigMaps, Gateway resources, and third-party chart dependencies | the target contract still needs the cluster-resident demo-app-only Apple story and the build-generated substrate-file publication closure |
| Kind topology assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-cuda.yaml` | substrate-specific Kind shapes, including the current GPU-enabled `linux-cuda` lane | the target doctrine still needs the `linux-gpu` naming migration and the removal of cross-substrate simulation assumptions |
| Protobuf contract assets | `proto/infernix/...` plus on-demand generated `tools/generated_proto/` stubs | define canonical runtime, manifest, and event schema boundaries | generated stubs must stay untracked |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native Apple CLI or Linux outer container | create or reuse Kind, reset StorageClasses, reconcile PVs, deploy Harbor first, publish the built substrate `.dhall`, publish images, and deploy the final chart | `./.data/runtime/cluster-state.state`, `./.data/kind/...` |
| Harbor image preparation | Harbor plus Haskell image publication flow | Kind cluster plus control plane | bootstrap Harbor, mirror required images, and publish repo-owned images before later rollout | Harbor state under `./.data/kind/...` |
| PostgreSQL substrate | Percona Kubernetes operator plus Patroni PostgreSQL | Kind cluster | only supported in-cluster PostgreSQL contract for Harbor and later services | `./.data/kind/...` |
| Publication state | repo-local JSON plus routed `/api/publication` surface | repo-local state and demo API | reports control-plane context, daemon location, active substrate, routes, and upstream health metadata | `./.data/runtime/publication.json` |
| Edge Gateway controller | Helm-installed Envoy Gateway controller | Kind cluster | owns all browser-visible and host-consumed routing | none |
| Cluster Gateway resource | `GatewayClass/infernix-gateway` plus `Gateway/infernix-edge` | Kind cluster | single localhost-bound HTTP listener on the chosen edge port | none |
| HTTPRoute rendering | data-driven `chart/templates/httproutes.yaml` from the Haskell route registry | Kind cluster | publishes the route inventory for demo, Harbor, MinIO, and Pulsar surfaces | none |
| Substrate `.dhall` publication | generated `ConfigMap/infernix-demo-config` plus repo-local mirror | Kind cluster and repo-local state | republishes the built substrate `.dhall` for cluster consumers and local inspection tooling | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime host | `infernix service` plus `src/Infernix/Runtime/{Cache,Worker,Pulsar}.hs` | host process on `apple-silicon`; cluster pod on `linux-cpu` and `linux-gpu` | Pulsar consumer, durable cache owner, and engine-worker supervisor | `./.data/runtime/`, object-store state under `./.data/object-store/` |
| Demo UI host | `infernix-demo` deployment | cluster pod | serves `/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/` when demo is enabled | none |
| Web runtime executor | PureScript bundle plus Playwright in the Linux outer-container image | Linux outer container | serves the browser bundle from the clustered demo app and runs routed E2E coverage from the containerized Playwright executor | test artifacts under `./.data/` |
| Engine adapter set | `python/adapters/` invoked via `poetry run` from the Haskell worker | host child process or cluster child process | Python-native engine boundary over typed protobuf-over-stdio | optional Apple venv under `python/.venv/` |
| Python quality gate | `poetry run check-code` | host or Linux outer-container image | runs mypy strict, black check, and ruff strict against the shared adapter tree | none |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | reconcile Kind, storage, Harbor-first bootstrap, image publication, built substrate-file publication, publication state, and edge port |
| Cluster status | `infernix cluster status` | report cluster presence, active substrate, publication state, build or data roots, and route inventory without mutation |
| Kubernetes wrapper | `infernix kubectl ...` | scoped wrapper around upstream `kubectl` against the repo-local kubeconfig |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or reconcile derived runtime cache state without mutating authoritative sources |
| Focused lint | `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart` | run the repo-owned focused lint entrypoints for files, docs, `.proto`, and chart assets |
| Aggregate static validation | `infernix test lint` | run the focused lint entrypoints together with Haskell style/build and Python quality checks |
| Docs validation | `infernix docs check` | validate the governed docs suite and phase-plan shape through the canonical docs linter |
| Service runtime | `infernix service` | consume the substrate `.dhall`, watch it for reloads, and own inference for the active substrate |
| Demo UI runtime | `infernix-demo` deployment | serve the demo-only HTTP surface against the active generated substrate catalog |
| Frontend contract generation | `infernix internal generate-purs-contracts` | generate the supported PureScript contract module from Haskell source |
| Unit validation | `infernix test unit` | validate Haskell runtime behavior plus PureScript unit suites |
| Integration validation | `infernix test integration` | validate the built substrate's published catalog contract through one substrate-aware integration suite that traverses the README matrix rows, selects the active engine from the generated `.dhall`, covers every generated active-substrate catalog entry, and carries the supported real-cluster HA or lifecycle assertions |
| Routed E2E validation | `infernix test e2e` | exercise the real routed browser surface for the built substrate through a substrate-agnostic Playwright suite that relies on `infernix-demo` to read the generated `.dhall` and dispatch the correct engine |

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
| Apple Silicon / Metal | `apple-silicon` | host-native control plane and host-native inference daemon, clustered demo app, shared config and route contracts | the current repo still relies on runtime-mode overrides and the interim host bridge |
| Linux / CPU | `linux-cpu` | containerized Linux lane built from the shared substrate Dockerfile and driven entirely through Compose | the current repo still defaults validation to a cross-substrate matrix rather than a substrate-specific run |
| Linux / NVIDIA GPU | `linux-gpu` | GPU-enabled Kind lane built from the shared substrate Dockerfile and deployed from the same CUDA-based image used by the outer container | the current repo still names the lane `linux-cuda` and still treats the direct launcher as supported |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Matrix registry -> generated substrate file | local build boundary | `.dhall` derived from typed Haskell data | Haskell config or catalog modules | Apple staging lives under `./.build/`; Linux staging lives under `/opt/build/infernix/`; the built substrate selects engine bindings consumed unchanged by `infernix service`, `infernix-demo`, and the integration suite |
| Generated substrate file -> ConfigMap publication | control plane | real ConfigMap data plus repo-local mirror | `infernix cluster up` | Linux cluster workloads mount the published file beside the binary under `/opt/build/infernix/` |
| Browser <-> demo API | external (demo only) | JSON over HTTP | handwritten Haskell browser-contract ADTs plus generated PureScript bindings | production deployments do not expose this surface |
| Inference requester <-> Pulsar | external | protobuf over Pulsar topics | repo-owned `.proto` schemas with Haskell and Python generated bindings | production inference surface |
| Haskell worker <-> Python adapter | internal child-process boundary | protobuf over stdio | `src/Infernix/Runtime/Worker.hs` plus `python/adapters/` | invoked only through `poetry run` |

## State and Artifact Locations

| State class | Authority | Durable home | Notes |
|-------------|-----------|--------------|-------|
| Durable PV directories | storage reconciliation in `cluster up` | `./.data/kind/...` | deterministic host path layout for every PVC-backed workload |
| Generated Apple substrate file | Cabal build outside the outer container | `./.build/infernix-substrate.dhall` | Apple host path beside the built binary |
| Generated Apple kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` on Apple |
| Generated Linux substrate file | Cabal build inside the outer container | `/opt/build/infernix/infernix-substrate.dhall` | outer-container path beside the built binary |
| Generated Linux kubeconfig | `cluster up` | `./.data/runtime/infernix.kubeconfig` | durable repo-local kubeconfig reused across fresh outer-container invocations |
| Cluster-mounted substrate file | Helm deployment plus ConfigMap mount | `/opt/build/infernix/infernix-substrate.dhall` | cluster-resident `infernix service` and `infernix-demo` read the mounted substrate file from this path |
| Outer-container build root | containerized build or runtime | `/opt/build/infernix/` | baked-image build root used by the outer-container control plane |
| Source snapshot manifest | Linux outer-container image build | `/opt/build/infernix/source-snapshot-files.txt` | sorted source snapshot captured from the baked image context before later generated outputs so git-less image runs of `infernix lint files` validate only the baked source tree |
| Durable runtime artifact bundles | service runtime and cache materialization | `./.data/object-store/artifacts/<substrate>/<model-id>/bundle.json` | durable worker input metadata |
| Durable source-artifact manifests | service runtime and cache materialization | `./.data/object-store/source-artifacts/<substrate>/<model-id>/source.json` | authoritative artifact-selection metadata |
| Publication state | `cluster up`, `cluster down`, `infernix service` | `./.data/runtime/publication.json` | route inventory and substrate metadata |
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
