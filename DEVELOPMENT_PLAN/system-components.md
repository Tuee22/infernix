# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, cluster
> services, runtime binaries, trust boundaries, and durable state locations in `infernix`.

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable State |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix`, host-installed `kind`, `kubectl`, `helm`, Docker, and host runtime prerequisites as needed | host-native on Apple Silicon | canonical local operator surface for Apple Silicon development; `infernix` may install missing supported prerequisites such as Homebrew `poetry` and other required Python dependencies | `./.data/` plus `./.build/` for build output |
| Linux outer control plane | Docker Compose `run --rm` launcher | ephemeral outer container | canonical local operator surface for containerized Linux development | bind-mounted repo plus `./.data/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for local cluster PVs, caches, port allocations, and build artifacts | `./.data/` |
| Build artifact root | Cabal and web build outputs | host or outer container | keep compiled output out of the source tree; the repo-owned `cabal.project` makes `./.build/` the host-native Cabal default, and container workflows isolate build output under `/opt/build/infernix` via explicit `--builddir` | `./.build/` on host; `/opt/build/infernix` in outer container |

## Cluster and Edge Components

| Component | Technology | Deployment | Purpose | Durable State |
|-----------|------------|------------|---------|---------------|
| Local cluster | Kind | Docker-backed Kubernetes | hosts the service, web UI, and stateful dependencies | host-backed volumes under `./.data/` |
| Edge proxy | ingress-nginx plus repo-owned route config | Helm release pulled from local Harbor after bootstrap mirroring | one localhost port and stable route prefixes for UI, API, Harbor, MinIO, and Pulsar | none |
| Haskell service | `infernix service` container | Helm workload in cluster; optional host-native daemon on Apple | inference control plane and API surface | model cache and service state under `./.data/` or cluster PVs as appropriate |
| Webapp service | PureScript app plus a separate webapp runtime, its own `web/Dockerfile`, and Playwright | repo-owned Helm workload in cluster | browser UI and E2E execution environment | test artifacts and browser cache under mounted work dirs only |
| Harbor | official Harbor Helm chart | cluster service with mandatory three-replica application-plane deployment where the chosen chart supports it, with hard pod anti-affinity suppressed for Kind scheduling; only supported bootstrap exception for direct upstream pulls | local image registry and browser portal | chart-managed persistence plus MinIO-backed image blobs |
| MinIO | official or Bitnami Helm chart mirrored into local Harbor | mandatory four-node distributed cluster with hard pod anti-affinity suppressed for Kind scheduling | durable object store for manifests, artifacts, and large outputs | manual-PV-backed volumes under `./.data/` |
| Pulsar | Apache Pulsar Helm chart mirrored into local Harbor | cluster StatefulSets and services with mandatory three-replica HA surfaces where the chosen chart exposes them, with hard pod anti-affinity suppressed for Kind scheduling | durable event transport for inference lifecycle | manual-PV-backed volumes under `./.data/` |
| Manual storage policy | repo-owned `infernix-manual` StorageClass plus CLI-created PVs | cluster bootstrap plus reconcile path | explicit local persistence contract | `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>` |
| Host bridge for Apple mode | repo-owned Service or route adapter | cluster edge path | keeps `/api` stable when the daemon runs on the host instead of in-cluster | none |

## Runtime and Application Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Service runtime | `infernix service` | start the Haskell inference service |
| Cluster reconcile and deploy | `infernix cluster up` via `./.build/infernix` on Apple or `docker compose run --rm infernix infernix` on Linux | declaratively and idempotently reconcile the Kind test cluster, mandatory local HA service topology, auto-generate the test Dhall config, reconcile manual storage, mirror or build required images, and deploy Helm workloads |
| Cluster teardown | `infernix cluster down` | declaratively and idempotently reconcile cluster absence without deleting authoritative repo data by default |
| Cluster status | `infernix cluster status` | report cluster state, chosen edge port, and exposed routes without mutation |
| Kubernetes wrapper | `infernix kubectl ...` | run `kubectl` against the repo-local kubeconfig in the active build-output location without relying on global kubeconfig state |
| Haskell static-quality validation | `infernix test lint` | run `fourmolu`, `cabal-fmt`, `hlint`, and strict compiler-warning checks for repo-owned Haskell code |
| Webapp image build | `web/Dockerfile`, invoked automatically by `cluster up` | generate frontend contract modules from Haskell SSOT, build the separate webapp binary, install Playwright dependencies, and assemble the image used by Helm and E2E |
| Unit and integration validation | `infernix test unit`, `infernix test integration`, `infernix test all` | declaratively execute Haskell and service-level validation, with `test all` aggregating lint, unit, integration, and E2E checks |
| Browser validation | `infernix test e2e` | declaratively run Playwright from the web image |
| Docs validation | `infernix docs check` | declaratively validate the future governed docs and development-plan cross-references |

## Browser and API Surface

| Route | Upstream | Purpose | Notes |
|-------|----------|---------|-------|
| `/` | `infernix-web` | browser UI | manual inference workbench and operator surface |
| `/api` | `infernix service` or Apple host bridge | typed API for model listing and manual inference | stable route even when the daemon location changes |
| `/harbor` | Harbor portal | registry browser portal | browser-visible via edge |
| `/minio/console` | MinIO console | object-store administration | browser-visible via edge |
| `/minio/s3` | MinIO S3 API | service and host-native artifact access | Apple host-native daemon uses this edge path |
| `/pulsar/admin` | Pulsar admin or proxy HTTP surface | cluster admin and validation surface | browser-visible via edge |
| `/pulsar/ws` | Pulsar WebSocket proxy | host-native daemon and browser-adjacent tooling | Apple host-native daemon uses this edge path |

## Cluster Image Authority

- Local Harbor is the required image source for every non-Harbor pod on the supported cluster path.
- Harbor is the only workload allowed to bootstrap from Docker Hub or another upstream registry
  before the local registry is available.
- `infernix cluster up` is responsible for mirroring third-party images and publishing repo-owned
  images before Helm rollout.
- The webapp image is a repo-owned Harbor image built through `web/Dockerfile` during the
  `cluster up` flow, not a manually managed image outside the CLI flow.

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Browser <-> API | external | JSON over HTTP or WebSocket | Haskell-owned types with build-generated PureScript bindings | no hand-maintained duplicate DTOs |
| Service <-> MinIO | internal | S3-compatible HTTP | service runtime | edge-routed on Apple host mode; cluster-local in cluster mode |
| Service <-> Pulsar | internal | Pulsar proxy HTTP or WebSocket on host mode; cluster-native transport in cluster mode | service runtime | same domain model regardless of transport path |
| CLI <-> Kubernetes | control plane | `helm`, `kubectl`, and Kind process execution plus the `infernix kubectl` wrapper | `infernix cluster` modules | platform-dependent execution context, stable CLI contract with repo-local kubeconfig injection |
| Haskell <-> PureScript | local build boundary | generated source modules | webapp container build driven by Haskell SSOT | validated by `purescript-spec` |
| Web image <-> Playwright | local container boundary | browser automation process calls | web image | same image owns browser dependencies and UI hosting |

## State and Artifact Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Cluster PV backing data | storage reconciliation within `cluster up` | `./.data/kind/...` | deterministic host path layout for all manual PVs |
| Harbor image blobs | Harbor backed by MinIO | MinIO bucket plus Harbor metadata storage | no repo-owned image tarball cache is authoritative |
| MinIO objects | MinIO | manual-PV-backed volumes | manifests, model artifacts, and large outputs |
| Pulsar ledger state | Pulsar | manual-PV-backed volumes | bookkeeper and ZooKeeper persistence stay under the manual PV policy |
| Service model cache | service runtime | `./.data/runtime/model-cache/` or mapped equivalent | derived from MinIO; never authoritative over MinIO |
| Chosen edge port record | cluster lifecycle | `./.data/runtime/edge-port.json` | tells the host and docs which localhost port is active |
| Host build outputs | Apple host-native Cabal or frontend build | `./.build/` | keeps compiled output and generated host-side Dhall config out of tracked source paths; repo-owned `cabal.project` makes this the default Cabal build root on host |
| Generated host test Dhall config | `cluster up` on Apple host mode | `./.build/infernix-test-config.dhall` | auto-generated for supported test workflows and ignored by Git and Docker context |
| Generated host kubeconfig | `cluster up` on Apple host mode | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl`; `cluster up` must not mutate `$HOME/.kube/config` |
| Outer-container build outputs | Linux outer container | `/opt/build/infernix` | no build artifacts should land in the bind-mounted repo tree; supported container Cabal workflows and Dockerfiles use explicit `--builddir=/opt/build/infernix` or an equivalent enforced wrapper |
| Generated container test Dhall config | `cluster up` in outer-container mode | `/opt/build/infernix/infernix-test-config.dhall` | auto-generated for supported test workflows and kept out of the mounted repo tree |
| Generated container kubeconfig | `cluster up` in outer-container mode | `/opt/build/infernix/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` in the outer-container path |
| Webapp build-time generated frontend contract modules | webapp Docker build | image-build workspace only | generated from Haskell SSOT during `web/Dockerfile` execution; not a standalone CLI artifact |
| Playwright artifacts | web image test runs | `./.data/test-artifacts/playwright/` or mounted equivalent | screenshots, traces, and videos |

## Deployment Modes

| Mode | Control plane location | Service runtime location | Webapp service location | Primary use case |
|------|------------------------|--------------------------|--------------------|------------------|
| Apple local | host-native | host-native or cluster, depending phase closure | always cluster-resident | Apple Silicon development with direct host access to Kind tooling |
| Linux local | outer container | cluster-resident on supported path | always cluster-resident | containerized local development and CI-style execution |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
