# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, runtime modes,
> and durable state locations in `infernix`.

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable State |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix` plus the repo-owned `./cabalw` wrapper and host prerequisite detection | host-native | canonical current operator surface on Apple, including repo-owned Python prerequisite installation when manifests require it | `./.build/` plus `./.data/` |
| Linux outer control plane | `docker compose run --rm infernix infernix ...` plus the repo-owned `docker/infernix` wrapper | outer container | validated outer-container launcher entrypoint that reuses the single Haskell CLI from a Linux container | bind-mounted repo plus `./.data/` and `/opt/build/infernix` |
| Runtime-mode selector | CLI flag or `INFERNIX_RUNTIME_MODE` | host or outer container | resolve `apple-silicon`, `linux-cpu`, or `linux-cuda` independently of execution context | build-root config artifacts only |
| Matrix registry and demo-config generator | Haskell-owned README matrix registry plus JSON-shaped `.dhall` renderer | host or outer container during `cluster up` | select the active-mode engine bindings and generate `infernix-demo-<mode>.dhall` | transient staging files in the active build root |
| Frontend contract generator | `infernix internal generate-web-contracts` plus `web/build.mjs` | host or outer container during web build | emit the build-generated JavaScript contract module consumed by the current browser workbench, stage it under the active build root, and copy it into the built web bundle | active build-root staging plus `web/dist/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, host-side cache state, ConfigMap publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | repo-owned host wrapper or explicit container builddir plus generated artifacts | host or outer container | keep compiled output and generated demo-config files out of tracked source paths | `./.build/` on host; `/opt/build/infernix` on the outer-container path |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Web runtime image asset | `web/Dockerfile` | build and serve the separate web image path while carrying Playwright browser dependencies in the same image and acting as the E2E executor | none |
| Helm deployment assets | `chart/Chart.yaml`, `chart/Chart.lock`, `chart/values.yaml`, `chart/templates/` | hold the repo-owned service, web, edge-route, publication, and platform gateway workloads deployed through Helm on the supported Kind path, with locked Harbor or Pulsar or MinIO or ingress-nginx dependencies bootstrapped on demand | none |
| Kind topology assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-cuda.yaml` | hold the per-mode Kind shapes, including the `nvkind` template mount and GPU node labels for `linux-cuda`, that `cluster up` renders into real Kind clusters | none |
| Protobuf contract assets | `proto/infernix/...`, `tools/generated_proto/`, and `tools/proto_check.py` | define canonical runtime, manifest, and API schema names under repo ownership and validate their presence across Haskell and Python helpers | none |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable State |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native CLI or outer container | create or reuse the real Kind cluster, write the repo-local kubeconfig, reset StorageClasses, bootstrap declared Helm repositories, render the Helm chart, discover durable claims, reconcile PVs, deploy the Harbor bootstrap slice through Helm with stable chart-generated Harbor secret material and registry credentials across bootstrap and final phases, wait for Harbor readiness, build or load repo-owned images, publish non-Harbor images into Harbor, wait for Harbor's final rollout shape, preload the Harbor-backed final image refs onto the Kind worker, and only then deploy the final repo-owned chart while forcing the upstream Pulsar initialization jobs because Pulsar is first enabled there | `./.data/runtime/cluster-state.state` plus `./.data/kind/...` |
| Kind worker Harbor image prefetch | `docker exec ... crictl pull --creds ...` from `cluster up` | host-native CLI or outer container during the final Harbor-backed reconcile | prime the Kind worker image store with the Harbor-backed final image refs before the non-Harbor rollout begins so the final repo-owned and platform workloads can start from the worker-local image cache instead of racing Harbor's first anonymous pull path | none |
| Publication state | JSON publication inventory written by `cluster up`, `cluster down`, and host-bridge service activation | repo-local state files | drive `cluster status` reporting plus the routed `/api/publication` metadata surface, including API-upstream mode and routed-upstream health or backing-state details | `./.data/runtime/publication.json` |
| Edge proxy | repo-owned Python reverse proxy in the service image, owned by `chart/templates/deployment-edge.yaml` | Kind cluster | publish `/`, `/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` on one chosen localhost port without depending on upstream edge images | none |
| Harbor gateway workload | repo-owned Python gateway in the service image | Kind cluster | expose the routed Harbor portal and API surface by proxying the chart-managed Harbor service through the shared edge | none |
| MinIO gateway workload | repo-owned Python gateway in the service image | Kind cluster | expose the routed MinIO console and S3 API by proxying the chart-managed MinIO service through the shared edge | none |
| Pulsar gateway workload | repo-owned Python gateway in the service image | Kind cluster | expose the routed Pulsar admin and WebSocket surfaces by proxying the chart-managed Pulsar service through the shared edge | none |
| Demo config publication | real `ConfigMap/infernix-demo-config` plus repo-local mirror and rendered manifest | Kind cluster plus repo-local state files | publish the generated active-mode demo catalog to cluster workloads while keeping a repo-local inspection mirror | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime host | Python HTTP server launched by `infernix service` through the Haskell CLI | host process or service pod | serve the API, routed publication metadata, and large-object references using the active generated demo catalog, repoint `/api` through the Apple host bridge when the daemon runs host-native, launch process-isolated engine-worker adapters through configured command prefixes including forwarded `INFERNIX_ENGINE_COMMAND_*` overrides, and materialize durable runtime artifact bundles plus direct-upstream source-artifact manifests into the runtime bucket without exposing implicit filesystem service fallback | runtime cache under `./.data/runtime/` |
| Web runtime host | static bundle from `web/dist/` served by `web/Dockerfile` image | web pod on the supported cluster path | expose the manual workbench through the cluster-resident web workload | none |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | choose the edge port, create or reuse Kind, reset StorageClasses, reconcile PV directories and PV objects, generate `infernix-demo-<mode>.dhall`, publish the real ConfigMap and publication state, build or load repo-owned images, preserve stable Harbor bootstrap and final credentials, preload Harbor-backed final image refs on the Kind worker, force final-phase Pulsar initialization jobs, and deploy the Helm chart |
| Cluster status | `infernix cluster status` | report cluster presence, active runtime mode, build or data roots, generated demo-config paths, cache or durable-manifest or object inventory counts, published route inventory, and publication-state details without mutation |
| Kubernetes wrapper | `infernix kubectl ...` | pass through to upstream `kubectl` while automatically targeting the repo-local kubeconfig for the active cluster |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or clear or rebuild derived cache entries from manifest-backed durable sources without changing unrelated runtime state |
| Service runtime | `infernix service` | resolve the active generated-catalog source and launch the Python HTTP host used directly on Apple or inside the service pod on the cluster path |
| Local runtime fixture helper | `tools/runtime_fixture_backend.py` | materialize explicit filesystem-fixture durable bundles or manifests plus derived cache entries for host-side unit coverage without exposing filesystem-backed service fallback as a supported runtime mode |
| Frontend contract generation | `infernix internal generate-web-contracts <dir>` | generate the active-mode contract module used by the web build |
| Unit validation | `infernix test unit` | validate Haskell runtime behavior plus generated JavaScript contracts and catalog rendering logic |
| Integration validation | `infernix test integration` | exercise every generated catalog entry for the active runtime mode and verify generated demo-config publication, routed publication metadata, the real in-cluster ConfigMap, process-isolated engine-worker execution, durable runtime artifact plus direct-upstream source-artifact persistence, engine fixture command injection, and real `linux-cuda` GPU visibility on supported hosts |
| Routed E2E validation | `infernix test e2e` | exercise every generated catalog entry through the real routed cluster edge using Playwright launched from the same web image that serves the UI, including browser UI interaction, object-reference result rendering, and the current process-isolated engine-worker adapter contract |

## Browser and API Surface

| Route | Upstream | Purpose | Notes |
|-------|----------|---------|-------|
| `/` | cluster-resident web workload through the edge proxy | browser UI | manual inference workbench |
| `/api/publication` | service pod or host-native service bridge through the edge proxy | routed publication metadata | reports control-plane context, daemon location, catalog source, API-upstream mode, worker-execution mode, worker-adapter mode, artifact-acquisition mode, routed-upstream health, durable-backend state, and routes |
| `/api` | service pod or host-native service bridge through the edge proxy | typed API for model listing and manual inference | reports the active runtime mode and selected engine while preserving one browser-visible entrypoint |
| `/api/cache` | service pod through the edge proxy | cache status and lifecycle API | reports manifest-backed cache entries and supports eviction or rebuild flows |
| `/harbor` | cluster-resident Harbor gateway workload through the edge proxy | Harbor portal surface | proxies the chart-managed Harbor service |
| `/minio/console` | cluster-resident MinIO gateway workload through the edge proxy | MinIO console surface | proxies the chart-managed MinIO service |
| `/minio/s3` | cluster-resident MinIO gateway workload through the edge proxy | MinIO S3 API surface | proxies the chart-managed MinIO service |
| `/pulsar/admin` | cluster-resident Pulsar gateway workload through the edge proxy | Pulsar admin surface | proxies the chart-managed Pulsar service |
| `/pulsar/ws` | cluster-resident Pulsar gateway workload through the edge proxy | Pulsar WebSocket surface | proxies the chart-managed Pulsar service |

## Runtime Mode Inventory

| Runtime mode | Canonical mode id | Current implementation status | Demo catalog rule |
|--------------|-------------------|-------------------------------|-------------------|
| Apple Silicon / Metal | `apple-silicon` | active host-native and Kind-backed catalog lane; request execution uses process-isolated engine-worker adapters, durable runtime bundles, direct-upstream source-artifact manifests, and engine fixture command injection in automated validation, but not yet supported-host Apple engine validation | generated catalog includes every README matrix row whose Apple column names a supported engine |
| Ubuntu 24.04 / CPU | `linux-cpu` | active Kind-backed catalog lane on the host-native and outer-container control planes; request execution uses process-isolated engine-worker adapters, durable runtime bundles, direct-upstream source-artifact manifests, and engine fixture command injection in automated validation, but not yet supported-host Linux CPU engine validation | generated catalog includes every README matrix row whose Linux CPU column names a supported engine |
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-cuda` | active Kind-backed catalog lane with supported-host NVIDIA preflight checks, `nvkind` cluster creation, Helm-installed NVIDIA device plugin, `RuntimeClass/nvidia`, and GPU-requesting repo-owned workloads; request execution uses process-isolated engine-worker adapters plus direct-upstream source-artifact manifests, but supported-host CUDA engine validation remains open | generated catalog includes every README matrix row whose Linux CUDA column names a supported engine and marks GPU-bound lanes |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Matrix registry -> generated demo config staging | local build boundary | JSON-shaped payload written to `.dhall` | Haskell config and catalog modules | active mode selects the engine column and entry set |
| Generated demo config staging -> ConfigMap publication | control plane | real ConfigMap data plus repo-local mirror and rendered YAML manifest | `infernix cluster up` | cluster workloads mount the active-mode catalog from this publication |
| Browser <-> API | external | JSON over HTTP | Haskell-owned types and generated frontend modules | active catalog entries surface selected engine and runtime mode |
| Service runtime -> MinIO or Pulsar | internal | protobuf manifests or results plus routed object references | routed service helpers | MinIO stores runtime results or manifests or large outputs while Pulsar carries request or result or coordination topics |

## State and Artifact Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Chart-owned PV directories | storage reconciliation within `cluster up` | `./.data/kind/...` | deterministic host path layout for manual PV binding |
| Generated host demo config staging | `cluster up` | `./.build/infernix-demo-<mode>.dhall` | active-mode catalog staged under the host build root |
| Generated host kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` |
| Kind registry mirror config | `cluster up` | `./.build/kind/registry/localhost:30002/hosts.toml` | the current implementation rewrites only the `localhost:30002` Harbor namespace to the active Kind control-plane node endpoint; the old `localhost:30001` helper-registry namespace has been removed from the supported path |
| Durable runtime artifact bundles | service runtime and cache materialization | `./.data/object-store/artifacts/<runtime-mode>/<model-id>/bundle.json` | repo-owned durable worker input staged locally and mirrored into the runtime bucket |
| Durable source-artifact manifests | service runtime and cache materialization | `./.data/object-store/source-artifacts/<runtime-mode>/<model-id>/source.json` plus optional `payload.bin` | durable metadata for local-file copies, direct HTTP downloads, or provider metadata fetches that the bundle points at |
| Publication state | `cluster up`, `cluster down`, `infernix service` host-bridge activation | `./.data/runtime/publication.json` | active runtime mode, published edge routes, API-upstream mode, and publication details for routed consumers |
| Generated frontend contract staging | web build | `./.build/web-generated/Generated/contracts.js` on host; `/opt/build/infernix/web-generated/Generated/contracts.js` in the outer container | build-root staging module copied into `web/dist/generated/contracts.js` for runtime use |
| Generated frontend dist | web build | `web/dist/` | ignored static build output served by the web runtime image |
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
