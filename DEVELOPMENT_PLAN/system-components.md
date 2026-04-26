# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, runtime modes,
> and durable state locations in `infernix`.

## Current Repo Assessment

- the control-plane topology now includes `infernix` plus `infernix-demo`, and the cluster
  workload entrypoints now use `infernix edge` and `infernix gateway ...`; rendered-chart
  discovery, chart image publication, lint, routed publication probes, the supported Apple host
  bridge, and the edge or gateway entrypoints are all Haskell-owned now
- the supported web build now runs through `npm --prefix web run build`, which regenerates
  `web/src/Generated/Contracts.purs`, compiles the PureScript app with `spago build`, and bundles
  it into `web/dist/app.js`; `web/test/Main.purs` now owns the frontend unit suite through
  `spago test`
- `infernix internal generate-purs-contracts` now derives the supported generated contract module
  through `purescript-bridge` from dedicated browser-contract ADTs in `src/Generated/Contracts.hs`
  and appends the active-mode runtime constants and `Simple.JSON` instances consumed by the
  frontend
- `python/adapters/` plus `tools/python_quality.sh` are now wired into `infernix test lint`, and
  the runtime split under `src/Infernix/Runtime/{Cache,Worker,Pulsar}.hs` is live; the
  Python-native worker path now resolves named adapter directories over typed
  protobuf-over-stdio, while the real engine implementations and the real Pulsar consumer loop
  remain open

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable State |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix` plus direct `cabal` materialization | host-native | canonical operator surface on Apple, with no Python prerequisite for the operator workflow; Poetry plus a repo-local adapter virtual environment materialize only when an engine-adapter test is exercised explicitly | `./.build/` plus `./.data/` |
| Linux outer control plane | `docker compose run --rm infernix infernix ...` plus the image-installed `infernix` binary | outer container | validated outer-container launcher entrypoint that reuses the single Haskell CLI from a Linux container, joins the private Docker `kind` network for cluster-backed commands, and keeps host-published Kind or routed ports on `127.0.0.1` without a repo-owned script entrypoint | bind-mounted repo plus `./.data/` and `/opt/build/infernix` |
| Runtime-mode selector | CLI flag or `INFERNIX_RUNTIME_MODE` | host or outer container | resolve `apple-silicon`, `linux-cpu`, or `linux-cuda` independently of execution context | build-root config artifacts only |
| Matrix registry and demo-config generator | Haskell-owned README matrix registry plus JSON-shaped `.dhall` renderer | host or outer container during `cluster up` | select the active-mode engine bindings and generate `infernix-demo-<mode>.dhall` | transient staging files in the active build root |
| Frontend contract generator | `infernix internal generate-purs-contracts` | host or outer container during web build | emit the supported `web/src/Generated/Contracts.purs` module from dedicated bridge-owned Haskell contract ADTs in `src/Generated/Contracts.hs` plus active-mode catalog and runtime metadata before the PureScript bundle is compiled | `web/src/Generated/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, host-side cache state, ConfigMap publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | explicit `cabal` builddir or installdir flags plus generated artifacts | host or outer container | keep compiled output and generated demo-config files out of tracked source paths without repo-owned scripts or wrapper layers | `./.build/` on host; `/opt/build/infernix` on the outer-container path |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Web runtime image asset | `web/Dockerfile` | package the built PureScript bundle, Playwright harness, and browser dependencies into the separate web image used for routed E2E execution and Harbor-published final-substrate Playwright reuse | none |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | hold the repo-owned service, demo, edge-route, publication, and platform gateway workloads deployed through Helm on the supported Kind path, with Harbor, Percona PostgreSQL operator, Percona PostgreSQL cluster, Pulsar, MinIO, and ingress-nginx dependencies bootstrapped on demand through the same release flow while every PVC-backed Helm workload stays on `infernix-manual` plus explicit PV binding | none |
| Kind topology assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-cuda.yaml` | hold the per-mode Kind shapes, including the `nvkind` template mount and GPU node labels for `linux-cuda`, that `cluster up` renders into real Kind clusters | none |
| Protobuf contract assets | `proto/infernix/...`, `tools/generated_proto/`, and `infernix lint proto` (`src/Infernix/Lint/Proto.hs`) | define canonical runtime, manifest, and API schema names under repo ownership and validate their presence across Haskell modules and Python adapters; `tools/generated_proto/` stubs are auto-generated and consumed by the engine adapters under `python/adapters/<engine>/` | none |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable State |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native CLI or outer container | create or reuse the real Kind cluster, write the repo-local kubeconfig, reset StorageClasses, bootstrap declared Helm repositories, render the Helm chart, discover durable claims, reconcile manually created PVs, deploy the Harbor bootstrap slice through Helm with stable chart-generated Harbor secret material and registry credentials across bootstrap and final phases, wait for Harbor readiness, build or load repo-owned images, publish non-Harbor images into Harbor, wait for Harbor's final rollout shape, preload the Harbor-backed final image refs onto the Kind worker, and only then deploy the final repo-owned chart while forcing the upstream Pulsar initialization jobs because Pulsar is first enabled there; the repo-owned Kind assets pin `kindest/node:v1.34.0`, and on the Linux outer-container lane the current implementation keeps host-published Kind API and routed ports on `127.0.0.1`, joins the private Docker `kind` network, writes the kubeconfig from the internal Kind control-plane endpoint, copies the Harbor registry hosts config plus repo-local Kind storage roots into live Kind nodes after cluster creation instead of bind-mounting those host paths into the nodes directly, and syncs each durable claim directory back from its owning Kind node during teardown | `./.data/runtime/cluster-state.state` plus `./.data/kind/...` |
| Kind worker Harbor image prefetch | `docker exec ... crictl pull --creds ...` from `cluster up` | host-native CLI or outer container during the final Harbor-backed reconcile | prime the Kind worker image store with the Harbor-backed final image refs before the non-Harbor rollout begins so the final repo-owned and platform workloads can start from the worker-local image cache instead of racing Harbor's first anonymous pull path | none |
| PostgreSQL substrate | Percona Kubernetes operator plus Patroni-managed PostgreSQL clusters | Kind cluster | provide the only supported in-cluster PostgreSQL contract for Harbor and any future PostgreSQL-backed services; services may use dedicated clusters, but they all follow the same operator-managed Patroni model with `infernix-manual` PV binding and PgBouncer where the chosen chart or operator requires it, including charts that would otherwise self-deploy standalone PostgreSQL | `./.data/kind/...` |
| Publication state | JSON publication inventory written by `cluster up`, `cluster down`, and host-bridge demo activation | repo-local state files | drive `cluster status` reporting plus the routed `/api/publication` metadata surface, including API-upstream mode and routed-upstream health or backing-state details | `./.data/runtime/publication.json` |
| Edge proxy | Haskell reverse proxy in `infernix-lib` (`src/Infernix/Edge.hs`); deployed as cluster workload `infernix-edge` via `chart/templates/deployment-edge.yaml` using the same OCI image with entrypoint `infernix edge` | Kind cluster | publish `/`, `/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` on one chosen localhost port without depending on upstream edge images; `/` and `/api` route to `infernix-demo` only when the demo surface is enabled | none |
| Harbor gateway workload | Haskell gateway in `infernix-lib` (`src/Infernix/Gateway.hs`); deployed as cluster workload `infernix-harbor-gateway` via `chart/templates/workloads-platform-portals.yaml` using the same OCI image with entrypoint `infernix gateway harbor` | Kind cluster | expose the routed Harbor portal and API surface by proxying the chart-managed Harbor service through the shared edge | none |
| MinIO gateway workload | Haskell gateway in `infernix-lib` (`src/Infernix/Gateway.hs`); deployed as cluster workload `infernix-minio-gateway` via `chart/templates/workloads-platform-portals.yaml` using the same OCI image with entrypoint `infernix gateway minio` | Kind cluster | expose the routed MinIO console and S3 API by proxying the chart-managed MinIO service through the shared edge | none |
| Pulsar gateway workload | Haskell gateway in `infernix-lib` (`src/Infernix/Gateway.hs`); deployed as cluster workload `infernix-pulsar-gateway` via `chart/templates/workloads-platform-portals.yaml` using the same OCI image with entrypoint `infernix gateway pulsar` | Kind cluster | expose the routed Pulsar admin and WebSocket surfaces by proxying the chart-managed Pulsar service through the shared edge | none |
| Demo config publication | real `ConfigMap/infernix-demo-config` plus repo-local mirror and rendered manifest | Kind cluster plus repo-local state files | publish the generated active-mode demo catalog to cluster workloads while keeping a repo-local inspection mirror | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime host | Haskell daemon `infernix service` plus the split runtime modules in `src/Infernix/Runtime/{Pulsar,Worker,Cache}.hs` behind the `Infernix.Runtime` facade | host process or `infernix-service` cluster pod | validate the active catalog, keep the production daemon on a no-HTTP path, and exercise the split cache or worker process boundary while the real Pulsar consumer loop remains open | runtime cache under `./.data/runtime/` |
| Demo UI host | Haskell `infernix-demo` binary (servant-based); shares `infernix-lib` with `infernix` and ships in the same OCI image | host process or `infernix-demo` cluster pod, gated by `.dhall` `demo_ui` flag | serve `/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/` for the demo workbench only; production deployments leave the flag off and the cluster has no `infernix-demo` pod and no HTTP API surface at all | none |
| Web runtime image and executor | built `web/dist/` bundle packaged by `web/Dockerfile` | `docker run` on the host-native and outer-container E2E lanes plus Harbor-published reuse on the host-native final-substrate path | provide the Playwright executor image for the routed demo surface served by `infernix-demo`; it is not a cluster workload | none |
| Engine adapter container set | Python adapters under `python/adapters/<engine>/` from one repo-root `python/pyproject.toml` (Poetry-managed); each adapter container build runs `tools/python_quality.sh` (mypy strict, black check, ruff strict) and fails on any check failure; Poetry installs system-wide inside the container, with no in-container `.venv` | per-engine cluster pod (or sidecar to the worker) | bind Python-native engines to the Haskell worker across a process boundary through typed protobuf-over-stdio; the current adapters are quality-gated stubs and the real engine libraries plus cluster scheduling remain open | none |
| Python quality gate | `tools/python_quality.sh` invoking mypy strict, black check, and ruff strict against `python/` | inside every adapter container build; on host via `infernix test lint` against the Poetry-managed adapter environment | enforce the strict typing and formatting contract on all repo-owned Python | none |
| Production inference subscription | Haskell placeholder under `src/Infernix/Runtime/Pulsar.hs` | host process or `infernix-service` cluster pod | validate the active request-topic or result-topic or engine-binding catalog and keep the no-HTTP production-daemon surface explicit while the real Pulsar request or result topic consumer remains open | none |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | choose the edge port, create or reuse Kind, reset StorageClasses, reconcile PV directories and PV objects, generate `infernix-demo-<mode>.dhall`, publish the real ConfigMap and publication state, deploy Harbor first together with only Harbor-required backend services on pristine clusters, build or load repo-owned images, preserve stable Harbor bootstrap and final credentials, preload Harbor-backed final image refs on the Kind worker, force final-phase Pulsar initialization jobs, and deploy the remaining Helm-managed workloads, add-ons, and PostgreSQL-backed services from Harbor-backed image refs only |
| Cluster status | `infernix cluster status` | report cluster presence, active runtime mode, build or data roots, generated demo-config paths, cache or durable-manifest or object inventory counts, published route inventory, and publication-state details without mutation |
| Kubernetes wrapper | `infernix kubectl ...` | pass through to upstream `kubectl` while automatically targeting the repo-local kubeconfig for the active cluster |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or clear or rebuild derived cache entries from manifest-backed durable sources without changing unrelated runtime state |
| Service runtime | `infernix service` | resolve the active generated-catalog source, validate it, report the production-daemon topic inventory, and keep the current non-HTTP production-daemon placeholder alive while the real Pulsar-consuming service loop remains open |
| Demo UI runtime | `infernix-demo serve --dhall PATH --port N` | resolve the active generated-catalog source and serve the demo HTTP API surface from the `infernix-demo` binary; gated by `.dhall` `demo_ui` flag and absent from production deployments |
| Local runtime fixture helper | Haskell test fixtures under `test/unit/` | materialize explicit filesystem-fixture durable bundles or manifests plus derived cache entries for host-side unit coverage |
| Frontend contract generation | `infernix internal generate-purs-contracts` | generate the supported `Generated.Contracts` PureScript module into `web/src/Generated/` via `purescript-bridge`, then append runtime constants and explicit `Simple.JSON` instances for the frontend |
| Unit validation | `infernix test unit` | validate Haskell runtime behavior plus the PureScript frontend unit suites under `web/test/Main.purs` through `spago test` |
| Integration validation | `infernix test integration` | exercise every generated catalog entry for the active runtime mode and verify generated demo-config publication, routed publication metadata, the real in-cluster ConfigMap, Haskell-owned edge or gateway or demo API paths, durable cache or result persistence, operator-managed PostgreSQL readiness or failover or deterministic PVC rebinding, and real `linux-cuda` GPU visibility on supported hosts |
| Routed E2E validation | `infernix test e2e` | exercise every generated catalog entry through the real routed cluster edge using Playwright launched from the same web image that packages the built demo bundle, including browser UI interaction, object-reference result rendering, and the current Haskell demo API plus runtime-simulation contract |

## Browser and API Surface

| Route | Upstream | Purpose | Notes |
|-------|----------|---------|-------|
| `/` | `infernix-demo` workload through the edge proxy | demo-only browser UI | served by `infernix-demo`; absent when the `.dhall` `demo_ui` flag is off (production) |
| `/api/publication` | `infernix-demo` workload through the edge proxy | demo-only routed publication metadata | served by `infernix-demo`; reports control-plane context, daemon location, catalog source, worker-execution mode, worker-adapter mode, artifact-acquisition mode, routed-upstream health, durable-backend state, and routes |
| `/api` | `infernix-demo` workload through the edge proxy | demo-only typed API for model listing and manual inference | served by `infernix-demo`; the production inference surface is Pulsar topics named in the active `.dhall`, not this route |
| `/api/cache` | `infernix-demo` workload through the edge proxy | demo-only cache status and lifecycle API | served by `infernix-demo`; reports manifest-backed cache entries and supports eviction or rebuild flows |
| `/objects/<key>` | `infernix-demo` workload through the edge proxy | demo-only object-store fixture access for browser-visible large outputs | served by `infernix-demo` |
| `/harbor` | `infernix-harbor-gateway` workload through the edge proxy | Harbor portal surface | proxies the chart-managed Harbor service; available in every supported deployment |
| `/minio/console` | `infernix-minio-gateway` workload through the edge proxy | MinIO console surface | proxies the chart-managed MinIO service; available in every supported deployment |
| `/minio/s3` | `infernix-minio-gateway` workload through the edge proxy | MinIO S3 API surface | proxies the chart-managed MinIO service; available in every supported deployment |
| `/pulsar/admin` | `infernix-pulsar-gateway` workload through the edge proxy | Pulsar admin surface | proxies the chart-managed Pulsar service; available in every supported deployment |
| `/pulsar/ws` | `infernix-pulsar-gateway` workload through the edge proxy | Pulsar WebSocket surface | proxies the chart-managed Pulsar service; available in every supported deployment |

## Runtime Mode Inventory

| Runtime mode | Canonical mode id | Current implementation status | Demo catalog rule |
|--------------|-------------------|-------------------------------|-------------------|
| Apple Silicon / Metal | `apple-silicon` | active host-native and Kind-backed catalog lane; request execution now uses the Haskell demo API plus the split cache or worker runtime path and the routed host bridge, while the real Pulsar consumer loop remains open | generated catalog includes every README matrix row whose Apple column names a supported engine |
| Ubuntu 24.04 / CPU | `linux-cpu` | active Kind-backed catalog lane on the host-native and outer-container control planes; request execution now uses the Haskell demo API plus the split cache or worker runtime path | generated catalog includes every README matrix row whose Linux CPU column names a supported engine |
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-cuda` | active Kind-backed catalog lane with supported-host NVIDIA preflight checks, `nvkind` cluster creation, Helm-installed NVIDIA device plugin, `RuntimeClass/nvidia`, GPU-requesting repo-owned workloads, and the same Haskell demo API plus split cache or worker runtime contract used on the other runtime modes | generated catalog includes every README matrix row whose Linux CUDA column names a supported engine and marks GPU-bound lanes |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Matrix registry -> generated demo config staging | local build boundary | JSON-shaped payload written to `.dhall` | Haskell config and catalog modules | active mode selects the engine column and entry set |
| Generated demo config staging -> ConfigMap publication | control plane | real ConfigMap data plus repo-local mirror and rendered YAML manifest | `infernix cluster up` | cluster workloads mount the active-mode catalog from this publication |
| Browser <-> demo API | external (demo-only) | JSON over HTTP | dedicated browser-contract ADTs in `src/Generated/Contracts.hs` rendered into `web/src/Generated/Contracts.purs` by `infernix internal generate-purs-contracts`, with routed handlers served through `src/Infernix/Demo/Api.hs` | demo UI only; production deployments are still moving toward a no-HTTP service surface |
| Inference requester <-> Pulsar | external | protobuf over Pulsar topics | repo-owned `.proto` schemas; Haskell `proto-lens`-generated bindings in `infernix service` (production); Python `protobuf`-generated bindings in `python/adapters/<engine>/` | this is the production inference surface; request topics and result topic are named in the active `.dhall` |
| Service runtime -> MinIO or Pulsar | internal | protobuf manifests or results plus routed object references | routed service helpers | MinIO stores runtime results or manifests or large outputs while Pulsar carries request or result or coordination topics; service placement decides whether those backends are reached through cluster-local service names or the edge-routed bridge surfaces, while runtime mode only changes engine selection and generated catalog content |

## State and Artifact Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Durable PV directories | storage reconciliation within `cluster up` | `./.data/kind/...` | deterministic host path layout for manual PV binding across every PVC-backed Helm workload, including direct chart-owned stateful workloads and operator-managed PostgreSQL claims; on the Linux outer-container lane those directories are synchronized into live Kind node-local paths during cluster create and copied back from the owning node during cluster delete because the current Docker or Kind substrate does not tolerate repo-path bind mounts into Kind nodes on this host |
| Generated host demo config staging | `cluster up` | `./.build/infernix-demo-<mode>.dhall` | active-mode catalog staged under the host build root |
| Generated host kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl`; on the Linux outer-container lane it records the internal Kind control-plane endpoint rather than a host-gateway alias while host-published API access remains loopback-only |
| Kind registry mirror config | `cluster up` | `./.build/kind/registry/localhost:30002/hosts.toml` | the current implementation rewrites only the `localhost:30002` Harbor namespace to the active Kind control-plane node endpoint, then copies that `hosts.toml` into live Kind nodes on the Linux outer-container lane; the old `localhost:30001` helper-registry namespace has been removed from the supported path |
| Durable runtime artifact bundles | service runtime and cache materialization | `./.data/object-store/artifacts/<runtime-mode>/<model-id>/bundle.json` | repo-owned durable worker input staged locally and mirrored into the runtime bucket |
| Durable source-artifact manifests | service runtime and cache materialization | `./.data/object-store/source-artifacts/<runtime-mode>/<model-id>/source.json` plus optional `payload.bin` | durable metadata for local-file copies, direct HTTP downloads, or provider metadata fetches, including engine-specific authoritative artifact selection that the bundle points at |
| Publication state | `cluster up`, `cluster down`, `infernix service` host-bridge activation | `./.data/runtime/publication.json` | active runtime mode, published edge routes, API-upstream mode, and publication details for routed consumers |
| Generated frontend contract staging | `infernix internal generate-purs-contracts` | `web/src/Generated/` | `Generated.Contracts.purs` emitted from dedicated browser-contract ADTs plus active-mode catalog and runtime metadata; consumed by `spago build` |
| Generated frontend dist | `npm --prefix web run build` | `web/dist/` | ignored static build output served by `infernix-demo` and packaged into the web runtime image |
| ConfigMap publication mirror | `cluster up` | `./.data/runtime/configmaps/infernix-demo-config/` | mirrored `infernix-demo-<mode>.dhall` plus rendered YAML |
| Chosen edge port record | cluster lifecycle | `./.data/runtime/edge-port.json` | records the `9090`-first chosen port |
| Service model cache | service runtime | `./.data/runtime/model-cache/<runtime-mode>/<model-id>/default/` | derived cache keyed by runtime mode and model id |
| Host-side cache durability manifests | service runtime and unit helpers | `./.data/object-store/manifests/<runtime-mode>/<model-id>/default.pb` | protobuf manifest-backed rebuild source for the host-side cache lifecycle helpers |
| Host-side large-output fixtures | service runtime and unit helpers | `./.data/object-store/results/` | local object-reference fixture root used by host-side helpers and tests |
| Playwright and test artifacts | validation flows | `./.data/` or Playwright defaults | repo-local test output location |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
