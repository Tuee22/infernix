# Phase 3: Platform Services and Edge Routing

**Status**: Done — all 16 sprints are implemented and validated.
**Current state**: Sprint 3.16's current-source `linux-cpu` lifecycle cohort is complete.
Single-node topology is enforced against the text that
actually deploys: chart defaults of 1 are not sufficient, because a generated Helm overlay can
reassert a replicated count, so the rule is pinned by a negative-tested unit guard on the generated
overlay; see [Sprint 3.16](#sprint-316-single-node-platform-topology-done). The Bounded-Command
Application & Bounded-HTTP reopen (Sprint 3.15) and the Managed-State-Transition Doctrine reopen
(Sprint 3.14) are closed by [Wave V](cohort-validation-waves.md)
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the mandatory local single-instance Harbor, MinIO, operator-managed
> PostgreSQL, and Pulsar deployments; the Envoy Gateway installation that owns all browser-visible routing on one
> localhost listener; the publication contract; and the route-registry cleanup that removes route
> duplication across Haskell, Helm, route-oriented docs, and route-aware validation.

## Phase Status

> **Bounded-command application / bounded-HTTP — closed by [Wave V](cohort-validation-waves.md).**
> Every Harbor docker/skopeo exec runs through `Infernix.Cluster.Subprocess.runBoundedCommand` under
> a named `Timeout` budget, because the publish/verify site was the one place a bounded-command
> kernel had shipped without being applied and an unbounded Harbor `docker pull` verify could hang
> `publish-harbor-images` indefinitely. Blob-servability is evidence-minted: the opaque
> `BlobServable` witness comes from a real bounded pull, `harborTagExists` is demoted to the
> non-terminal `harborTagMetadataPresent` and `registryReady` to the weaker `registryApiReachable`,
> so a retained-state push-skip against an unrehydrated MinIO backing is no longer a terminal
> "done". See [Sprint 3.15](#sprint-315-harbor-blob-servable-evidence--bounded-publish-done).

Phase 3 closes around the mandatory platform service set, the shared routed edge, and the
Haskell-owned route registry implemented in this worktree. Sprint 3.16 collapses that service set
to one instance per role, so the replicated shapes Sprints 3.1, 3.3, and 3.4 originally delivered
are retired rather than current: those sprints stay `Done` for what they landed, and each names its
supersession where it claimed the retired shape. Sprints 3.1-3.12 are `Done` after
Apple cohort validation in Waves A/A.2, CUDA Linux cohort validation in Wave C, and native arm64
`linux-cpu` validation in Wave F. Sprint 3.12 is validated on the native arm64 Docker daemon
already selected on this Apple Silicon machine — Docker reports `server=linux/arm64` and the Linux
runtime probe reports `aarch64` / `arm64` — so the Linux CPU outer-container suite runs without
cross-architecture emulation, Docker-context switching, or VM creation. The Apple daemon-role model
is implemented in Phase 6 Sprint 6.25 and separates cluster daemon location from host inference
executor location in publication metadata.

Sprint 3.13 de-exposes the `/minio/s3` external gateway route so the `infernix-demo` webapp is the
**sole** externally routed file-storage service: the browser reaches MinIO only through the webapp
object-proxy (Phase 7 Sprint 7.25), never through a gateway route or a presigned MinIO URL. This
realizes the
[../documents/architecture/object_access_doctrine.md](../documents/architecture/object_access_doctrine.md).
Sprints 3.1–3.16 are `Done`; Sprint 3.13 is cohort-closed by
[Wave M](cohort-validation-waves.md) with the selected `linux-gpu` accelerator plus `linux-cpu`
full-suite evidence. Sprint 3.16 closed on the 2026-08-16 current-source `linux-cpu` full lifecycle,
which proved exactly one running engine pod and no `Pending` platform workload. The route-inventory
prose below reflects the de-exposed surface (no
`/minio/s3` route, no `presignPublicEndpoint`).

## Single-Instance Reconcile Surface

- `infernix cluster up` is the declarative and idempotent entrypoint for the supported
  single-instance platform topology
- the supported cluster path deploys one instance of each platform service and exactly one engine
  process per machine
- no service-specific bootstrap command family exists outside the supported cluster reconcile surface

## PostgreSQL Doctrine

- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes operator
- services or add-ons that can self-deploy PostgreSQL disable that path and point at an operator-managed cluster instead
- PostgreSQL claims use `infernix-manual` and explicit PV binding from Phase 2
- Harbor remains the first deployed service on a pristine cluster

## Substrate-Stable Route Contract

- substrate changes do not fork the browser entrypoint
- when the demo UI is enabled, `/`, `/api`, `/api/objects`, `/auth`, `/ws`, `/harbor/api`,
  `/harbor`, `/pulsar/admin`, and `/pulsar/ws` are the published route inventory; MinIO has no
  external gateway route (Sprint 3.13), so the webapp `/api/objects` proxy is its only
  browser-facing surface
- `/api/publication` and `/api/cache` remain stable routed demo endpoints under the `/api` prefix
- the final Apple split-executor path keeps the same browser base URL while routed cluster
  surfaces enter the cluster daemon first and Apple inference batches move through Pulsar to the
  host daemon

## Current Repo Assessment

The supported cluster path runs the single-instance platform services and optional demo HTTP host
on the Kind substrate. Publication metadata originates from `./.data/runtime/publication.json`, exposes
the active substrate through current `runtimeMode` fields, derives the route inventory from one
Haskell-owned registry plus one data-driven HTTPRoute template, and reports
`inferenceDispatchMode` beside the routed demo API upstream. The Apple publication contract
distinguishes the always-present cluster daemon from the host inference executor: routed manual
inference enters the clustered daemon path, Apple inference batches move through Pulsar to a
same-binary host daemon, and Linux substrates keep inference inside the cluster daemon. Demo-off routing is supported through the explicit substrate-materialization helper
with `--demo-ui false`. Direct `infernix-demo` execution is limited to the demo-owned HTTP surface
when used intentionally outside the routed cluster path, so Harbor, MinIO, and Pulsar probes depend
on the intended HTTPRoute mapping.
Sprint 3.12 replaces the previous `LinuxCpu -> "amd64"` publication hardcode with typed
host-architecture selection from `InfernixHost.dhall`, mapping native Linux amd64 to `amd64` and
native Linux arm64 to `arm64` while keeping `linux-gpu` amd64-only. [Wave F](cohort-validation-waves.md)
validated the native arm64 publication path through the selected native arm64 Docker daemon.

## Current Closure Receipt (2026-08-16)

- the settled-source review found Sprint 3.16 code-side complete; only its named `linux-cpu`
  lifecycle observation remained
- the post-Phase-2 governed lint/unit aggregates remained green on the unchanged source, including
  the generated-overlay guard for all emitted replica counts
- current-source launcher image
  `sha256:4f46299ee0b45b9c3a5ecc2b7543d8174c5323e57ea6eac7b7355a5edcee155f` completed the full
  `./bootstrap/linux-cpu.sh test` with integration assertions that exactly one engine pod was
  running and no platform workload was `Pending`
- the same cohort completed retained/fresh topology cycles, Playwright 16/16, and clean teardown;
  governed status reported cluster-absent/idle with zero nodes, pods, results, and cache entries
- the MinIO layout migration remains an explicitly operator-owned teardown-and-rebuild boundary,
  and Phase 6 Sprint 6.47 owns deletion of retired chaos/HA assertions; neither is Phase 3 work

## Sprint 3.1: HA MinIO Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/object_storage.md`, `documents/tools/minio.md`

### Objective

Provide the HA MinIO deployment and routed object-store surfaces required by Harbor and the
reserved cluster object-store path.

### Deliverables

- MinIO deploys with manual PV backing on the supported single-node topology; the four-node
  distributed deliverable this sprint landed is retired by Sprint 3.16
- repo-owned values suppress hard pod anti-affinity that would block local Kind scheduling
- MinIO has no external gateway route and no console route (Sprint 3.13); the browser reaches it
  only server-side through the cookie-authenticated webapp `/api/objects` proxy
- the chart reserves MinIO as the Kind-backed object-store target for Harbor and cluster-routed
  object-store access, while durable object-store state lives only in the MinIO buckets
  `infernix-models` (always-on platform model weights),
  `infernix-engine-artifacts` (always-on engine software payloads), and
  `infernix-demo-objects` (demo-gated user uploads and engine-generated artifacts), the on-disk
  `./.data/object-store/` tree having been retired by Phase 7 Sprint 7.7

### Validation

- `infernix cluster up` creates a healthy MinIO deployment; the four-node distributed shape this
  sprint validated is retired by Sprint 3.16
- MinIO PVCs bind via `infernix-manual`
- MinIO exposes no browser-facing edge route (Sprint 3.13); the webapp `/api/objects` proxy is its
  only external surface

### Remaining Work

None.

---

## Sprint 3.2: Operator-Managed Patroni PostgreSQL [Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/Lint/Chart.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/harbor.md`, `documents/tools/postgresql.md`

### Objective

Standardize every in-cluster PostgreSQL dependency on one HA operator-managed contract.

### Deliverables

- the supported cluster path installs the Percona operator through the repo-owned Helm workflow
- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by that operator
- services that can self-deploy PostgreSQL disable that path and use operator-managed clusters instead
- operator-managed PostgreSQL claims bind through `infernix-manual`

### Validation

- `infernix cluster up` produces ready Percona and Patroni members for Harbor's PostgreSQL backend
- rendered Helm values disable embedded standalone PostgreSQL deployments where applicable
- repeat `cluster down` plus `cluster up` cycles rebind operator-managed PostgreSQL storage onto the
  same deterministic PV inventory and host paths

### Remaining Work

None.

---

## Sprint 3.3: HA Pulsar Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/tools/pulsar.md`

### Objective

Provide the durable event transport for inference requests, results, and service coordination.

### Deliverables

- Pulsar deploys through the Helm chart on the supported single-node topology; the HA component and
  quorum settings this sprint landed are retired by Sprint 3.16
- durable Pulsar components use manual PVs under `./.data/`
- the edge exposes browser- and host-consumable Pulsar HTTP or WebSocket surfaces
- the proxy's effective idle bound is `httpServerIdleTimeout`, not
  `webSocketSessionIdleTimeoutMillis`: Pulsar 4.0.9 does not project the WebSocket key into
  `proxy.conf`, so setting it leaves the proxy at its default and expires a consumer session while
  inference still retains the message. The chart default and the binary-generated local override
  both set `httpServerIdleTimeout` to 7,200,000 ms — above the 4,200-second result deadline — and
  lint plus rendered-values guards hold it there
- inference-request, result, and coordination payloads are defined by repo-owned `.proto` schemas

### Validation

- `infernix cluster up` produces a healthy Pulsar deployment
- Pulsar PVCs bind through `infernix-manual`
- routed Pulsar admin and WebSocket surfaces respond on the shared edge port
- the running proxy's `/pulsar/conf/proxy.conf` carries `httpServerIdleTimeout=7200000`, and the
  chart lint plus the rendered-values guard fail if the effective key is renamed or lowered below
  the result deadline

### Remaining Work

None.

---

## Sprint 3.4: HA Harbor Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/tools/harbor.md`

### Objective

Historical objective: provide the then-replicated image registry and browser portal. Sprint 3.16
supersedes the replica outcome; the current Harbor service is single-instance.

### Deliverables

- Harbor deploys through its Helm chart
- Harbor stores image blobs in MinIO and uses an operator-managed Patroni PostgreSQL backend
- Harbor application-plane workloads use the supported single-instance topology; the former
  replicated deliverable is retired by Sprint 3.16
- the Harbor portal is exposed through the shared edge

### Validation

- `infernix cluster up` produces a healthy Harbor release in the supported single-instance shape;
  the replicated shape this sprint validated is retired by Sprint 3.16
- routed Harbor access works on the shared edge port
- deleting a single Harbor application pod does not permanently break access or image pulls

### Remaining Work

None.

---

## Sprint 3.5: Envoy Gateway API Installation and Localhost Listener [Done]

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/gatewayclass.yaml`, `chart/templates/gateway.yaml`, `chart/templates/envoyproxy.yaml`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace the old repo-owned edge process with Envoy Gateway API and one localhost-bound listener
that fronts every published surface.

### Deliverables

- the Helm chart pulls the Envoy Gateway controller as a dependency
- one `GatewayClass/infernix-gateway` and one `Gateway/infernix-edge` own the shared listener
- `cluster up` records the chosen port under `./.data/runtime/edge-port.json`
- the initial Sprint 3.5 demo route set remained local-only and published plain HTTP; later
  Phase 7 auth-UX work added repo-owned JWT policy for selected operator routes

### Validation

- `infernix cluster status` prints the chosen port and published route inventory
- `infernix kubectl get gatewayclass,gateway -n platform` shows the GatewayClass `Accepted` and
  `Gateway/infernix-edge` programmed on the chosen listener port
- `infernix kubectl get httproute -n platform` shows the published route set in `Accepted` state
- routed `/pulsar/admin` and `/pulsar/ws` probes prove the Envoy data plane forwards the final
  Gateway route set on the Kind-plus-Helm path

### Remaining Work

None.

---

## Sprint 3.6: Demo HTTP Webapp Host and Host-Demo Bridge Retirement [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `src/Infernix/Webapp.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Provide the current demo HTTP API surface through the `infernix` Webapp role while keeping one
stable clustered browser entrypoint across substrates.

### Deliverables

- `infernix-demo` is the single repo-owned source of the demo HTTP surface
- the chart deploys `infernix-demo` only when the active generated `.dhall` enables `demo_ui`
- production `infernix service` binds no HTTP listener
- the Apple host-native control plane stays distinct from the clustered browser entrypoint without
  introducing a host-side demo bridge

### Validation

- the routed demo SPA loads from `infernix-demo` when `demo_ui` is on
- keeping the Apple host-native control plane does not change the browser base URL
- when `demo_ui` is off, the cluster has no demo routes

### Remaining Work

None.

---

## Sprint 3.7: Substrate-Stable Publication Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make edge-route publication, current `runtimeMode`-labeled status reporting, and demo-config
publication details line up so operators and browser clients keep one stable substrate-aware
entrypoint.

### Deliverables

- `cluster status` reports the active substrate through its current `runtimeMode` line together
  with publication details and edge routes
- the supported reconcile path writes `./.data/runtime/publication.json`
- `/api/publication` exposes the routed publication details consumed by the browser SPA
- the publication contract preserves the same browser entrypoint used by the cluster-resident path

### Validation

- `cluster status` reports its current `runtimeMode` line, demo-config publication details, and
  edge routes
- `GET /api/publication` returns the routed publication details consumed by the browser
- rebuilding for a different substrate changes publication details without changing route prefixes

### Remaining Work

None.

---

## Sprint 3.8: Canonical Route Registry and Data-Driven HTTPRoute Rendering [Done]

**Status**: Done
**Implementation**: `src/Infernix/Routes.hs`, `chart/templates/httproutes.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Models.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Collapse the route and publication contract to one Haskell-owned source of truth that drives the
rendered HTTPRoute set, publication metadata, and chart-facing route inputs.

### Deliverables

- one Haskell route registry records:
  - path prefix
  - purpose label
  - backend service identity
  - rewrite behavior
  - demo-only versus always-on visibility
  - publication-upstream metadata
- one data-driven chart template renders the entire HTTPRoute set from that registry
- publication-state rendering and `/api/publication` derive their route inventory from the same registry
- the runtime or chart route inventory is no longer duplicated across `src/Infernix/Models.hs`,
  `chart/templates/httproutes.yaml`, and generated Helm values
- route-oriented docs and route-aware validation consume registry-backed generated sections
  derived from that same route registry

### Validation

- `infernix kubectl get httproute -n platform` shows the expected route set in `Accepted` state
- `GET /api/publication` reports the exact route inventory produced by the registry
- `infernix test lint` fails if the data-driven HTTPRoute template or required route-aware docs
  structure disappears from the supported shape
- routed Harbor, MinIO, Pulsar, and demo probes continue to work through the shared listener

### Remaining Work

None.

## Sprint 3.9: Clustered Demo Surface and Apple Host-Inference Bridge [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `chart/templates/deployment-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `README.md`, `documents/architecture/web_ui_architecture.md`, `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Keep the routed demo surface cluster-resident while making the Apple host-inference bridge an
explicit part of the supported Apple contract. Phase 6 Sprint 6.25 refines this bridge so the
route enters an always-present cluster daemon before Apple inference batches move to the host.

### Deliverables

- when `demo_ui` is enabled, the routed demo app always runs from the cluster deployment
- Apple host-native operators still use the same browser base URL, and the routed demo surface
  keeps its clustered HTTP host instead of swinging back to a host-side `infernix-demo serve`
  process
- on `apple-silicon`, routed manual inference bridges from the clustered `infernix-demo` surface
  toward host-native inference execution instead of claiming containerized Apple inference parity
- publication metadata reports the Apple host-inference bridge explicitly and distinguishes it from
  Linux cluster-local inference modes
- route-oriented docs and validation stop accepting cluster-resident Apple inference parity as the
  final Apple inference doctrine

### Validation

- `cluster up` deploys the demo app on the cluster for Apple and Linux substrates whenever
  `demo_ui` is enabled
- routed Apple integration and E2E flows keep one browser base URL while using the Apple
  host-inference bridge instead of in-cluster Apple inference execution
- `infernix docs check` and route-oriented validation fail if the docs still describe direct host
  `infernix-demo serve` or cluster-resident Apple inference parity as the final routed Apple
  contract

### Remaining Work

None.

---

## Sprint 3.10: Playwright Container Retirement and Edge Manifest Retirement [Done]

**Status**: Done
**Implementation**: `docker/playwright.Dockerfile` (deleted), `docker/Dockerfile` (gains Playwright runtime), `compose.yaml` (drop `playwright` service), `src/Infernix/CLI.hs` (runEndToEnd refactor), `web/playwright/inference.spec.js`, `web/playwright.config.js` (new fixture-driven config)
**Docs to update**: `documents/engineering/host_tools_manifest.md`, `documents/development/testing_strategy.md`, `documents/development/demo_app_test_plan.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Eliminate the dedicated `infernix-playwright:local` image and the separate `playwright` compose
service. Playwright runtime (Chromium/Firefox/WebKit dependencies, fonts, gstreamer plugins, xvfb)
moves into `docker/Dockerfile`. `infernix test e2e` invokes Playwright via the
in-container `npm exec --prefix web -- playwright test …` against the routed cluster on Docker's
private `kind` network. Apple host-native E2E invokes the same fixture-driven Playwright suite via
host `npm exec` against the published localhost edge port. Retire `INFERNIX_EDGE_PORT`,
`INFERNIX_PLAYWRIGHT_HOST`, `INFERNIX_PLAYWRIGHT_NETWORK`, and the `INFERNIX_EXPECT_*` family in
favor of substrate `.dhall` fields plus a Dhall-driven Playwright fixture file.

### Deliverables

- `docker/playwright.Dockerfile` deleted.
- `compose.yaml` `playwright` service block deleted; only the `infernix` service remains.
- `docker/Dockerfile` gains the Playwright system packages and runs
  `npm exec --prefix web -- playwright install --with-deps chromium firefox webkit` at image
  build time.
- `src/Infernix/CLI.hs` `runEndToEnd` invokes the fixture-driven Playwright path inside the
  launcher container for Linux and through host-native `npm exec` on Apple. The Linux browser
  connects to the Kind control-plane node on Docker's private network; the Apple browser connects
  to `127.0.0.1:<published-edge-port>`.
- `INFERNIX_EDGE_PORT`, `INFERNIX_PLAYWRIGHT_HOST`, `INFERNIX_PLAYWRIGHT_NETWORK`,
  `INFERNIX_EXPECT_DAEMON_LOCATION`, `INFERNIX_EXPECT_INFERENCE_DISPATCH_MODE`,
  `INFERNIX_EXPECT_API_UPSTREAM_MODE`, `INFERNIX_EXPECT_INFERENCE_EXECUTOR_LOCATION` all
  deleted from `compose.yaml`, `src/Infernix/CLI.hs`, and `web/playwright/inference.spec.js`.
- `web/playwright.config.js` reads the repo-relative `.data/runtime/playwright-fixture.json`
  (Dhall-decoded by the Haskell test driver at test start) and exposes the expectations via
  Playwright's `use:` block; the spec declares `infernixFixture` as a Playwright option fixture
  and receives it in the test callback.
- legacy-tracking row 3.10 moves from Pending Removal to Completed.

### Validation

- `cabal build all` clean, `infernix test lint` clean.
- `docker images` shows no `infernix-playwright:local` image after a fresh
  `./bootstrap/linux-gpu.sh build`.
- `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and `node --check` for
  `web/playwright.config.js` and `web/playwright/inference.spec.js` pass.
- Apple host-native Playwright validation closed in Waves A.1/A.2, and Linux in-container
  Playwright validation closed in Wave C.

### Remaining Work

None.

---

## Sprint 3.11: Apple Silicon Native Architecture, Bitnamilegacy Retirement, Harbor Port Dynamic Discovery [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs` (`clusterWorkloadArchitecture`, `chooseHarborPort`, `currentKindHarborPort`, `clusterSubprocessBaseEnvFor`, `renderKindConfig`, `renderHelmValues`, `harborApiHost`, `publishClusterImages`, `prepareKindNodeRuntimePaths`, `writeRegistryHostsConfig`), `src/Infernix/Cluster/PublishImages.hs` (`HarborPublishOptions.harborTargetArchitecture`, `pinLocalImageToTargetArchitecture`, `extractDigestForArchitecture`, `contentAddressTagFromManifestPayload`, `pushUpstreamMultiArchViaImagetools`, `recoverOriginalTag`, the MinIO overlay), `src/Infernix/ProcessMonitor.hs` (`processMonitorBaseEnvFor`), `src/Infernix/Storage.hs` (`harborPortPath`, `readHarborPortMaybe`), `src/Infernix/Types.hs` (`ClusterState.harborPort`), `src/Infernix/HostConfig.hs` (`defaultAppleHostNativeHostConfig`), `src/Infernix/DemoConfig.hs` (`materializeHostManifestFile`, `resolveOperatorHomeDirectory`), `app/Main.hs` (`hSetBuffering LineBuffering`), `chart/values.yaml` (hand-authored `infernixMinio` StatefulSet config), `test/unit/Spec.hs` (`samplePublishedImages`, overlay assertions, `contentAddressTagFromManifestPayload` arch fixture).
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/tools/minio.md`, `documents/tools/harbor.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/architecture/overview.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `README.md`.

### Objective

Close the four coupled architectural gaps that blocked Apple Silicon
`cluster up` on the new host: (a) the publication path forced amd64
end-to-end for Apple, so the substrate's Kind nodes received images that
could not run on native arm64 workers; (b) the chart's MinIO sub-chart pinned
`bitnamilegacy/*` images that are frozen amd64-only; (c) Harbor's host-side
NodePort was hardcoded to `30002` and conflicted with unrelated host
processes (e.g. an editor's debug worker); (d) the rendered Kind config
did not enable containerd's hosts.toml-driven registry resolution, so the
mounted `localhost:<harborPort>/hosts.toml` files were ignored and Kind
workers dialed `localhost` literally.

### Deliverables

- **Substrate-aware publication arch.** Sprint 3.11 introduced substrate-aware publication
  architecture selection for Apple arm64 and Linux amd64. Sprint 3.12 supersedes that first
  selector with `clusterWorkloadArchitectureForHostArchitecture`, which keeps Apple at `arm64`,
  keeps `linux-gpu` at `amd64`, and selects native `amd64` or `arm64` for `linux-cpu` from
  `InfernixHost.dhall`. The publication helpers
  (`pinLocalImageToTargetArchitecture`, `pushUpstreamMultiArchViaImagetools`,
  `extractDigestForArchitecture`, `recoverOriginalTag`,
  `contentAddressTagFromManifestPayload`) consume the substrate arch
  through `HarborPublishOptions.harborTargetArchitecture`. The
  `hydrateMissingHostWarmupImage` mirror.gcr.io fallback (formerly
  hardcoded `linux/amd64`) reads the same resolved architecture.
- **`bitnamilegacy/*` retirement.** The upstream bitnami MinIO sub-chart is
  retired in favor of a hand-authored MinIO StatefulSet under
  `chart/templates/minio/`, driven by the `infernixMinio:` block in
  `chart/values.yaml` (`image.repository: docker.io/minio/minio`,
  `clientImage.repository: docker.io/minio/mc`,
  `initImage.repository: docker.io/busybox`). There is no separate MinIO
  console workload or route. The Harbor overlay code in `PublishImages.hs`
  overrides `infernixMinio.image` / `clientImage` / `initImage` to the
  Harbor-mirrored refs. `hostCachedWarmupImageRefs` tracks the resulting
  image inventory.
- **Harbor port dynamic discovery.** `chooseHarborPort` selects a free
  host-side port starting at `30002`, persists to
  `./.data/runtime/harbor-port.json`, and is reused on subsequent
  reconciles. `ClusterState` gains `harborPort`. `renderKindConfig`,
  `renderHelmValues` (`harbor.externalURL`), `harborApiHost`, the
  registry-hosts namespace name, `currentKindHarborPort`, and
  `publishClusterImages` all consume the chosen port. The in-cluster
  Kubernetes NodePort stays fixed at `30002`; only the Kind hostPort
  observed from the operator host is dynamic. Section O of
  `DEVELOPMENT_PLAN/development_plan_standards.md` (edge port pattern)
  now applies to Harbor too.
- **Containerd `config_path` patch.** `renderKindConfig` emits a
  `containerdConfigPatches` block enabling
  `config_path = "/etc/containerd/certs.d"`. Kind 0.31 does not emit this
  by default, so the hosts.toml mappings provisioned by
  `writeRegistryHostsConfig` are only honored once the patch is in place.
- **Defensive lifecycle improvements** (Phase 2 Sprint 2.13 follow-on,
  cross-listed here):
  - `clusterSubprocessBaseEnvFor` + `processMonitorBaseEnvFor` derive
    subprocess PATH from `HostConfig.toolPaths.*` parent directories.
  - `defaultAppleHostNativeHostConfig.hostDocker` is now
    `/opt/homebrew/bin/docker` (was `/usr/local/bin/docker`).
  - `materializeHostManifestFile` resolves the operator home via
    `System.Posix.User.getEffectiveUserID` + `getUserEntryForID` (was an
    empty placeholder).
  - `waitForHarborRegistryResult` passes `-m 30` to `curl`.
  - `app/Main.hs` enables `LineBuffering` for `stdout` + `stderr`.
- **Retained-state Patroni scrub.** Operator-managed Patroni claims are excluded from host
  retention: `isPatroniManagedClaim` filters `harbor-postgresql-*` and `keycloak-postgresql-*` out
  of `syncClaimDirectoriesFromOwningNodes`, so a partial `/pgdata/pg18` tree is never copied back to
  the host on `cluster down`, and `scrubStalePatroniDirectories` removes any pre-existing tree from
  `<kindRuntimeRoot>/platform/infernix/` during the next `cluster up` `prepare-kind-cluster` phase.
  Copying a retained partial tree into a fresh Kind worker crashes `postgres-startup` with an
  initialization error, so the retention filter is a correctness rule, not an optimization.
- **No competing in-cluster Apple engine.** `repoEngineReplicaCount` maps
  `FinalPhase + AppleSilicon` to `0`, so the Apple substrate runs its engine on the host only.

### Validation

- `cabal build all`, `cabal test infernix-haskell-style`, `cabal test infernix-unit`, and
  `infernix lint files|chart|docs|proto` all exit zero.
- `rg -n 'bitnamilegacy' chart/ src/` returns matches only inside the
  retirement comments documenting what was removed; no active code refs.
- `rg -n '"--platform","linux/amd64"' src/Infernix/Cluster/` returns zero
  matches; all `--platform` flags read from
  `harborTargetArchitecture` or `clusterWorkloadArchitecture`.
- Apple cohort lifecycle proof points (`./.build/infernix` on Apple Silicon):
  - `chooseHarborPort` steps past an occupied `127.0.0.1:30002` to the next free host port, proving
    the bind-test + increment loop fires.
  - Substrate-aware publication runs every upstream image through `docker pull --platform
    linux/arm64` and `skopeo --override-arch=arm64`; the full platform image set
    (`infernix-linux-cpu`, `apachepulsar/pulsar-all`, `busybox`, `envoyproxy/gateway`, `minio/mc`,
    `minio/minio`, `percona/percona-distribution-postgresql`, `percona/percona-pgbackrest`,
    `percona/percona-pgbouncer`, `percona/percona-postgresql-operator`, `quay.io/keycloak/keycloak`)
    publishes as native arm64 through Harbor.
  - Kind workers pull and run every Harbor-mirrored image natively; the Percona operator runs as
    `linux/arm64` rather than failing with `Fatal glibc error: CPU does not support x86-64-v3`.
  - The hand-authored MinIO StatefulSet (`chart/templates/minio/`) reaches ready and the
    `infernix-minio-provisioning` Job completes (`mc mb --ignore-existing local/harbor-registry
    local/infernix-models local/infernix-engine-artifacts local/infernix-demo-objects`) without
    bitnami chart wrapper interference.
  - The containerd `config_path = "/etc/containerd/certs.d"` patch is honored — Kind workers resolve
    `localhost:<harborPort>/library/*` through the rendered registry-hosts mapping.
  - The full lifecycle runs `cluster up` to `lifecyclePhase: steady-state`, then `cluster down` to
    `clusterPresent: False`, `lifecycleStatus: idle`, `lifecyclePhase: cluster-absent`.
- Apple cohort full-suite validation, including the clean-state cluster down + cluster up replay
  that exercises the retained-state Patroni scrub, closed in
  [Waves A/A.2](cohort-validation-waves.md); the matching `linux-cpu` and `linux-gpu` full-suite
  reruns closed in [Wave C](cohort-validation-waves.md).

### Remaining Work

None.

---

## Sprint 3.12: Native arm64 Linux CPU Publication [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/HostConfig.hs`, `bootstrap/linux-cpu.sh`, `docker/Dockerfile`, `kind/cluster-linux-cpu.yaml`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/overview.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/engineering/testing.md`, `documents/development/local_dev.md`, `documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make `linux-cpu` a native Linux CPU substrate on both amd64 and arm64 hosts. The supported
publication path must select the host's native Linux architecture and must not rely on emulation,
cross-architecture `buildx`, or any non-native compatibility lane.

### Deliverables

- replace the `LinuxCpu -> "amd64"` architecture hardcode with host-native architecture discovery
  or a typed host-config field that maps native Linux amd64 to `amd64` and native Linux arm64 to
  `arm64`
- thread the selected `linux-cpu` architecture through Harbor publication, warmup-image hydration,
  local-image tagging, and Kind worker preload paths
- keep `linux-gpu` constrained to native amd64 CUDA hosts unless a future sprint explicitly adds a
  CUDA arm64 substrate
- add unit coverage for LinuxCpu architecture selection on amd64 and arm64 fixtures
- document that native Linux arm64 `linux-cpu` is a first-class substrate and that emulated Apple
  Linux is unsupported

### Validation

- `cabal test infernix-unit` proves the `LinuxCpu` architecture selector returns `amd64` and
  `arm64` for native Linux fixtures
- `./bootstrap/linux-cpu.sh test` passes on a native amd64 Linux host, with Harbor publication and
  warmup-image hydration emitting `docker pull --platform linux/amd64` and
  `skopeo --override-arch=amd64`
- `rg -n '"amd64".*LinuxCpu|LinuxCpu.*"amd64"' src test` has no unsupported hardcode after the
  selector lands
- `infernix lint docs` passes through the active execution context
- [Wave F](cohort-validation-waves.md) validates the native `linux/arm64` `linux-cpu` publication
  path through the already selected native arm64 Docker daemon, without cross-architecture
  emulation or Docker-context changes: Docker reports `client=darwin/arm64` / `server=linux/arm64`,
  the Linux runtime probe reports `uname -m = aarch64` and `dpkg --print-architecture = arm64`, and
  the rebuilt `infernix-linux-cpu:local` image reports `os=linux arch=arm64`. The reference
  `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all`
  invocation passes Haskell style, Python quality, Haskell unit/property, PureScript build and web
  unit tests, full `infernix-integration`, and routed Playwright E2E, emitting native
  `docker pull --platform linux/arm64` publication, Harbor-backed final-image preload before the
  final Helm wait, and clean cluster teardown. Integration covers Harbor recovery, MinIO durability,
  routed Pulsar recovery, PostgreSQL failover and lifecycle rebinding, Linux engine anti-affinity,
  frontend pod replacement, coordinator failover, engine pod replacement, engine node drain,
  model-bootstrap failover/deduplication, and multi-user durable prompt throughput.

### Remaining Work

None.

---

## Sprint 3.13: MinIO Gateway De-Exposure [Done]

**Status**: Done
**Code-side closure**: The `infernix-minio-s3` `RouteSpec`
is removed from `src/Infernix/Routes.hs` (so the rendered `chart/templates/httproutes.yaml`
`.Values.routes` loop and its generated registry comment carry no `/minio/s3`), the
`infernix-minio-s3` SecurityPolicy target is dropped from
`chart/templates/securitypolicy-operator-routes.yaml` (and from the `infernix lint chart`
required-phrase set), and `clusterConfig.minio.presignPublicEndpoint` is retired from the typed
cluster config (the `ClusterConfig` decoder type — Phase 8 keeps the schema reflected with no tracked
file, `ClusterConfig.hs`, `chart/templates/configmap-cluster-config.yaml`, `chart/values.yaml`, and the
`Cluster.hs` Helm-values renderer). The route registry, generated route summaries (README,
`edge_routing.md`, `web_portal_surface.md`, `tools/minio.md`, `cluster_bootstrap_runbook.md`), and
rendered chart expose no `/minio/s3` route and no `presignPublicEndpoint`. Implemented jointly with
[Phase 7 Sprint 7.25](phase-7-demo-app-durable-context.md) (the webapp object-proxy) because the
`presignPublicEndpoint` field's only consumer was the presigned-URL grant handler that 7.25
replaces.
**Cohort gate**: Closed by [Wave M](cohort-validation-waves.md) — `linux-cpu` plus the
chosen `linux-gpu` accelerator.
**Implementation**: `chart/templates/httproutes.yaml`, `chart/templates/securitypolicy-operator-routes.yaml`, `src/Infernix/ClusterConfig.hs` (`ClusterConfig` decoder type; no tracked `.dhall`)
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/architecture/object_access_doctrine.md`, `documents/reference/web_portal_surface.md`

### Objective

Make the webapp the single external file gateway by removing every browser-reachable MinIO surface:
the `/minio/s3` gateway route, its SecurityPolicy, and the public presign endpoint. The browser
reaches MinIO only via the webapp object-proxy ([Phase 7 Sprint 7.25](phase-7-demo-app-durable-context.md)),
per the [../documents/architecture/object_access_doctrine.md](../documents/architecture/object_access_doctrine.md).

### Deliverables

- removal of the `/minio/s3` HTTPRoute (`chart/templates/httproutes.yaml`)
- removal of the `infernix-minio-s3` SecurityPolicy (`chart/templates/securitypolicy-operator-routes.yaml`)
- removal of `clusterConfig.minio.presignPublicEndpoint` from the typed cluster config
- regenerated route registry, route summaries, and rendered chart that expose no `/minio/s3` route

### Validation

- `infernix lint chart` plus `infernix lint docs` confirm the rendered chart and generated route
  summaries name no `/minio/s3` route and no `presignPublicEndpoint`.
  `rg -n 'minio-s3|presignPublicEndpoint' src chart dhall` returns only retirement comments and
  legacy-tracking references.
- [Wave M](cohort-validation-waves.md) closes the `linux-cpu` plus chosen `linux-gpu` full suite:
  the paired `linux-cpu` gate and the `linux-gpu` lane both pass with full integration, routed
  Playwright, and the browser per-model matrix, proving the routed surface exposes the webapp as the
  only external file gateway and the browser never reaches MinIO directly.

### Remaining Work

None.

### Documentation Requirements

- update `documents/engineering/edge_routing.md` to drop `/minio/s3` from the route inventory and
  name the webapp `/api/objects` surface as the only external file gateway
- keep `documents/architecture/object_access_doctrine.md` and
  `documents/reference/web_portal_surface.md` aligned with the de-exposed route surface
- record the retired `/minio/s3` route, `infernix-minio-s3` SecurityPolicy, and
  `presignPublicEndpoint` in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

---

## Sprint 3.14: Readiness Kernel and Subprocess-Env Seam [Done]

**Status**: Done — the Managed-State-Transition readiness kernel plus typed subprocess-env seam:
code-side closure (machine-independent gates) plus the single-accelerator (apple-silicon) plus
linux-cpu full-suite sign-off closed by [Wave V](cohort-validation-waves.md).
**Code-side closure**: `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit` (the migrated Harbor readiness wait plus the
`clusterSubprocessEnvWithSearchPath` HOME/TMPDIR + caller-PATH assertions pass), and
`cabal test infernix-haskell-style` all pass on the apple-silicon lane; `infernix lint docs` clean.
No Python/native change, so `poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) — apple-silicon plus
linux-cpu full-suite `test all` clean.
**Implementation**: `src/Infernix/Cluster.hs`
**Blocked by**: Sprint 1.16
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: generalize
`HarborBootstrapOutcome` into the shared Readiness kernel (a wait that returns typed evidence with a
required deadline) and route the subprocess base-env seam (`clusterSubprocessBaseEnvFor`) through the
typed `SubprocessEnv`. The point is to encode evidence, not hope — every readiness wait and every
subprocess-env derivation returns a typed value that proves the transition happened, rather than a
bare boolean or an untyped environment map. It applies the
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
doctrine to this phase's cluster-lifecycle surface.

### Deliverables

- `HarborBootstrapOutcome` is generalized into the shared `Infernix.Evidence.Readiness` kernel: a
  wait primitive that takes a required deadline and returns typed evidence of readiness rather than
  a boolean
- readiness waits in `src/Infernix/Cluster.hs` run on that kernel, each carrying its own typed
  evidence value. `waitForHarborRegistryOrDirty` calls `awaitReadiness` with a required `Deadline`
  (the explicit ~120s bound that replaced a bare recursion counter) and projects the typed
  `HarborBootstrapOutcome` out of the kernel's `Readiness` value via `foldReadiness`, so readiness is
  evidence a real probe minted
- the subprocess base-env seam is routed through the typed
  `Infernix.Cluster.Subprocess.SubprocessEnv`: `clusterSubprocessEnvWithSearchPath`
  (caller-supplied cluster PATH, required `HOME`/`TMPDIR` from the host manifest) backs
  `clusterSubprocessBaseEnvIO`, which `runCommandWithInput` and `tryCommand` consume; the ad-hoc
  `[(String, String)]` base env is retired
- the change is fail-closed: a wait that cannot produce evidence surfaces a typed failure instead of
  a defaulted success, and the env seam fails closed when the host manifest is absent instead of
  falling back to an ambient minimal environment

### Validation

- `cabal build all` clean on both the apple-silicon and linux-cpu lanes
- `cabal test infernix-unit` and `cabal test infernix-haskell-style` pass on both lanes
- `infernix lint docs` passes through the active execution context on both lanes
- `poetry run check-code` passes if the change touches any Python/native surface
- readiness-kernel and `SubprocessEnv` unit coverage exercised on both the apple-silicon and
  linux-cpu lanes

### Remaining Work

None.

---

## Sprint 3.15: Harbor Blob-Servable Evidence & Bounded Publish [Done]

**Status**: Done — the bounded Harbor publish exec plus opaque `BlobServable` witness: code-side
closure (machine-independent gates) plus the single-accelerator (apple-silicon) plus linux-cpu
full-suite sign-off closed by [Wave V](cohort-validation-waves.md).
**Code-side closure**: `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`,
and `infernix docs check` all pass on the apple-silicon lane. No Python/native change in this sprint,
so `poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) — apple-silicon plus
linux-cpu full-suite `test all` clean.
**Current implementation note**: Wave V remains closure evidence for this sprint's original scope.
The Phase 2 Sprint 2.16 final audit tightened the sole `BlobServable` minter after proving
that a cached host Docker pull could succeed without independently reading Harbor. Current source
uses a bounded authenticated platform-selected skopeo copy from the Harbor API authority into a
fresh birth-identity-owned mode-0700 `dir:` store, forcing reads of the selected manifest, config,
and layers; protected cleanup preserves the primary failure, dead-owner auth directories reconcile,
and focused command/redaction/path unit coverage is landed. This
sprint remains `Done` for its recorded Wave V scope; Phase 2's post-correction machine-independent,
Apple, and paired `linux-cpu` evidence closed on 2026-08-16 under Wave Y.
**Implementation**: `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/Cluster/Command.hs`
**Blocked by**: Sprint 1.16, 3.14
**Docs to update**: `documents/architecture/managed_state_transitions.md`, `documents/tools/harbor.md`,
`documents/development/no_env_vars.md`, and the phase's existing engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — apply the
Sprint 1.16 bounded-command kernel and the Sprint 3.14 readiness kernel at the Harbor publish/verify
site a cohort run hung on. Two representable-invalid states are made unbuildable:
(1) an unbounded `docker pull` verify that never returns, and (2) tag metadata read from the Harbor
API being trusted as blob-servability on a retained-state second `cluster up` against an unrehydrated
~40 GB MinIO backing. It applies the
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
doctrine — evidence, not hope — to the publication surface.

Scope is the publish exec and the flake site. The general readiness-wait migration onto
`awaitReadiness` for the remaining Harbor/cluster waits (`waitForRegistry`,
`loginHarborWithRetries`, `pushImageWithRetries`, and peers) and the `ProcessMonitor.hs` retirement
are the broader hardening owned by
[Phase 6 Sprint 6.41](phase-6-validation-and-e2e-hardening.md).

### Deliverables

- every docker/skopeo exec in `src/Infernix/Cluster/PublishImages.hs` runs through
  `Infernix.Cluster.Subprocess.runBoundedCommand` under named `Timeout` budgets
  (`harborQuickCommandBudget`, `harborLoginBudget`, `harborUpstreamPullBudget`,
  `harborPullVerifyBudget`, `harborPushBudget`): the `CommandMonitorFactory`/`ProcessMonitor`
  heartbeat hook is replaced by a `PublishPhaseHook = String -> IO ()`, `tryRunCommand` routes
  through `runBoundedCommand`, and a `CommandTimedOut` surfaces as a `Left` so the retry counter
  advances instead of hanging (~23-min hang killed)
- an opaque `newtype BlobServable` (hidden constructor) minted only by `probeRegistryPull` (a bounded
  registry-only skopeo copy into a fresh empty `dir:` store); `verifyRegistryPull` returns
  `BlobServable` or fails, and `publishIfNeeded` falls through to a real push when the blob is not
  servable instead of terminally trusting tag metadata or a shared Docker cache
- `harborTagExists` demoted to the non-terminal `harborTagMetadataPresent` (metadata-only, may only
  shortcut the push) and `registryReady` weakened to `registryApiReachable` (may only gate polling,
  never "done"); `PublishImages.hs` added to `escapeTokenScopedFiles` so `BlobServable` cannot be
  forged

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint files/docs/proto/chart`, and `infernix docs check` are exercised on both the
  apple-silicon and linux-cpu lanes
- the end-to-end proof is the retained-state second `cluster up` of the Postgres lifecycle-rebinding
  integration step: with the bounded exec plus `BlobServable` witness it pulls a servable blob or
  fails bounded, never hangs
- the apple-silicon plus linux-cpu full-suite validation of the bounded publish plus `BlobServable`
  witness closed under [Wave V](cohort-validation-waves.md)

### Remaining Work

None.

---

## Remaining Work

None. Sprints 3.1-3.16 are `Done`; Sprint 3.13 closed in
[Wave M](cohort-validation-waves.md) with the selected `linux-gpu` accelerator plus `linux-cpu`.
Apple cohort validation for earlier Phase 3 work closed in Waves A/A.2, CUDA Linux cohort validation
closed in Wave C, and native arm64 `linux-cpu` validation closed in Wave F.

[Sprint 3.14](#sprint-314-readiness-kernel-and-subprocess-env-seam-done),
the Managed-State-Transition Doctrine reopen work, and
[Sprint 3.15](#sprint-315-harbor-blob-servable-evidence--bounded-publish-done), the Bounded-Command
Application & Bounded-HTTP reopen work that bounds the Harbor publish exec and mints `BlobServable`
evidence, are both closed by [Wave V](cohort-validation-waves.md) with apple-silicon plus
linux-cpu full-suite `test all` clean.

Sprint 3.16 closed on the current-source `linux-cpu` lifecycle receipt above.

---

## Sprint 3.16: Single-Node Platform Topology [Done]

**Status**: Done — code-side closure and the current-source `linux-cpu` lifecycle cohort are complete.
**Code-side closure**: the chart, the generated overlay, Kind topology, repair-path deletion, and
the inverted scheduling case are implemented and clean on the machine-independent gate set
(`cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`, `infernix-haskell-style`,
`infernix lint files|chart|proto|docs`).
**Cohort gate**: `linux-cpu` — complete on the 2026-08-16 current-source full lifecycle; the
integration suite proved exactly one running engine pod and no `Pending` workload.
**Implementation**: `chart/values.yaml`, `chart/templates/deployment-{coordinator,engine}.yaml`,
`chart/templates/keycloak/deployment.yaml`, `chart/templates/minio/statefulset.yaml`,
`src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Command.hs`, `kind/cluster-linux-cpu.yaml`,
`test/integration/Spec.hs`
**Docs to update**: `documents/architecture/daemon_topology.md`, `documents/tools/minio.md`,
`documents/tools/postgresql.md`, `documents/tools/pulsar.md`,
`documents/operations/cluster_bootstrap_runbook.md`

### Objective

Collapse the deployed topology to one process per role per machine and one instance per platform
service, and delete the redundancy machinery that only existed to support the retired shape.

The two existing local-topology override blocks already rendered exactly this for the Apple lanes;
this sprint promoted them from exception to default rather than inventing a new shape. Both blocks
shrank as a result: every replica and quorum line they carried is now the chart default and was
deleted from the override, because a default repeated in an override is a second place to change.

### Deliverables

All landed.

- **infernix roles**: demo / coordinator / engine replica counts are 1 **in the generated overlay as
  well as in `chart/values.yaml`**; the required engine pod anti-affinity, the preferred coordinator
  and Keycloak anti-affinity, and all five PodDisruptionBudgets are deleted; the second `linux-cpu`
  Kind worker is removed **in `renderKindConfig` as well as in `kind/cluster-linux-cpu.yaml`**.

  **The generated artifact is the authority, not the tracked reference file.** A Kind cluster is
  created from `writeGeneratedKindConfig` → `renderKindConfig` → `kindWorkerCount`, so editing
  `kind/cluster-linux-cpu.yaml` down to one worker deploys nothing on its own; `kindWorkerCount` is
  `_ -> 1` for every mode, pinned by a unit assertion over real `renderKindConfig` output for all
  three modes and negative-tested against the retired `LinuxCpu -> 2`. The same holds on the Helm
  side: `renderHelmValues` in `src/Infernix/Cluster.hs` supersedes `chart/values.yaml` on every
  phase render, so `repoWorkloadReplicaCount`, `repoCoordinatorReplicaCount`, and
  `repoEngineReplicaCount (FinalPhase, LinuxCpu)` are the values that decide the deployed topology
  and are 1. A replicated count left in the overlay puts **two engine pods on one worker**, both
  resolving the single compiled member `linux-cpu-engine` through the adoption arm in
  `requireCompiledDaemon` — two KV caches and two copies of every loaded weight, which is the exact
  correctness rule this sprint exists to enforce.

  **The topology guard is stated against the text that deploys**, because neither a chart-defaults
  assertion nor the cohort gate detects an over-replicated overlay: the integration case
  `validateNoPendingWorkloadReplicas` asserts only that no pod in `platform` is `Pending`, and with
  the anti-affinity deleted a second engine pod schedules onto the one worker without complaint, so
  a passing cohort run and an unmet deliverable are indistinguishable from there. The guard is a
  property over every count the overlay emits (`overReplicatedRoles`, `test/unit/Spec.hs`): one
  process per role per machine is cluster-wide, so a count above one is a defect wherever it
  appears. It is negative-tested by reintroducing `(FinalPhase, LinuxCpu) -> 2` alone, which fails
  it by name.
- **platform services to single-node**: Pulsar zookeeper / bookkeeper / broker / proxy /
  autorecovery are 1, and the managed-ledger ensemble, write, and ack quorums are 1 in the base
  chart rather than only in the Apple override; both Patroni instances and their pgBouncer proxies
  are 1; the Harbor bootstrap registry replica count drops from 3 to 1 — it was the last place a
  Harbor component was deliberately brought up multi-replica.
- **MinIO to a single node**, with its migration shipped first. The StatefulSet renders per-replica
  endpoints into the server command, so the CMD *shape* changes with the count: one instance is
  `minio server /data` (a plain backend directory), two or more are one `http://…/data` endpoint
  each (an erasure-coded distributed set). The layouts are not interchangeable, so this is a
  teardown-and-rebuild. `documents/tools/minio.md` and the cluster runbook carry the operator
  procedure, and both say plainly what does not survive it: `infernix-models` and
  `infernix-engine-artifacts` are repopulated automatically, and `infernix-demo-objects` — user
  uploads and generated artifacts — is lost.
- **the now-dead repair paths deleted with their topology**: `reinitializeHarborPostgresReplicasIfStuck`,
  `runHarborPostgresReplicaReinit`, `ensureHarborPostgresReplicationRole`, the
  `harborPostgresReplicaReinitGraceAttempts` window, the `KubectlReinitPostgresReplicas` command and
  its `patronictl reinit` argv, the `EnsureReplicationRole` postgres action and its SQL, and
  `chart/templates/postgresql-replication-init.yaml`. The rollout waiters are re-derived: expected
  Harbor data claims 3 → 1, and expected operator claims 4 → 2 per Patroni cluster.
- **the boundary stated explicitly**: the Percona operator remains the deployment mechanism and is
  no longer retained as a high-availability mechanism, so instance loss is restore-from-backup.
  `documents/tools/postgresql.md` says so in those words.

Two things found while deleting are worth recording, because both were conditions nothing could
meet rather than dormant capability.

**Two of the Pulsar dirty-state log markers were unsatisfiable.**
`pulsarBootstrapDirtySingleLogMarkers` matched `Cannot resolve bookieId
infernix-infernix-pulsar-bookie-1`, the same for `-2`, and `QuorumCoverage(e:2,w:2,a:2)`. A
one-bookie managed ledger cannot emit any of the three. They are deleted with the ensemble that
produced them. The same applies to `pulsarBootstrapRepairLogTargets`, which scanned zookeeper
ordinals 1 and 2: scanning a pod that does not exist returns nothing and reads as a clean scan.

**A second integration case asserted the retired topology as a floor, and is inverted with the
same reasoning.** `validateLinuxEnginePoolPlacement` required *at least two* running engine pods on
*at least two* distinct worker nodes. Stated as a floor, the collapse could not satisfy it at all —
so the sprint's own cohort gate would have failed on the corrected topology, for the correct
behaviour. Its companion line asserted that the member id held "independent of pod count", which is
the doctrine violation written down as an invariant: two engine pods sharing one member id are two
KV caches and two copies of every loaded weight, each admitting work against the whole machine's
observed capacity. The case now asserts **exactly one** running engine pod and names it; the
node-spread assertion is deleted rather than inverted, because it expressed the anti-affinity
constraint and with one pod there is nothing to spread. Sprint 6.47 retired the chaos tail but did
not reach this case, because it injects no failure.

**The anti-affinity integration case is inverted rather than retired, and it is weaker in a way
that is recorded.** The retired case scaled `infernix-engine` past the node count and required the
surplus replica to sit `Pending` with a `FailedScheduling` event naming pod anti-affinity. That
asserted the constraint this sprint deletes — and it asserted the wrong *kind* of thing: one engine
process per machine is a correctness rule about KV caches and admission, so expressing it as a
placement preference produced a `Pending` pod instead of preventing a second process. The
replacement, `validateNoPendingWorkloadReplicas`, asserts the inverse: no pod in the `platform`
namespace is `Pending`, which is the observable residue a partial collapse would leave behind. It
proves nothing about an operator who raises `engine.replicaCount` themselves, and the case says so
in its own comment rather than implying wider coverage.

### Validation

- `infernix lint chart` and `infernix lint files|proto|docs` plus `infernix docs check` pass.
- `cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`, and
  `infernix-haskell-style` pass on this source, including the base-chart autorecovery assertion.
- **The generated overlay's replica counts are pinned, and the pin was negative-tested.**
  `overReplicatedRoles` reads every `replicaCount:` the overlay emits for `linux-cpu` FinalPhase,
  `linux-gpu` FinalPhase, and a pre-final phase, and requires none above 1. A companion assertion
  requires the reader to have found at least one real count, so the guard cannot pass vacuously if
  the rendered shape changes. Reintroducing `repoEngineReplicaCount (FinalPhase, LinuxCpu) -> 2`
  alone fails it by name.
- **Cohort gate (complete):** the current-source full `linux-cpu` lifecycle ran on the one-worker
  topology; exactly one engine pod ran and every workload scheduled without a `Pending` replica.

### Remaining Work

- None.

### Closure Notes

The MinIO layout migration is operator-facing and cannot be automated by this sprint: an existing
cluster must be torn down and rebuilt, and demo-bucket contents do not survive. That is a reduction
in what an in-place upgrade can do and is recorded as such in the runbook rather than smoothed over.

The rest of the chaos / HA validation surface — the failure-injection integration tail, its
exclusively-owned helpers, and the Playwright pod-kill section — still asserts recovery properties
of the retired topology. Retiring it is Phase 6 Sprint 6.47, which this sprint unblocks.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - Envoy Gateway installation, single listener, route-registry ownership, and no-auth demo-cluster posture
- `documents/engineering/object_storage.md` - repo-local object-store rules plus reserved MinIO path and routed access
- `documents/engineering/k8s_storage.md` - manual PV doctrine and PostgreSQL claim binding
- `documents/engineering/portability.md` - arm64-native Apple Silicon posture (Sprint 3.11)
- `documents/engineering/docker_policy.md` - containerd `config_path` rendered into Kind config (Sprint 3.11)
- `documents/tools/minio.md` - MinIO deployment, routed surfaces, and the upstream-multi-arch image inventory after the `bitnamilegacy/*` retirement (Sprint 3.11)
- `documents/tools/postgresql.md` - Percona operator and Patroni deployment rules
- `documents/tools/pulsar.md` - Pulsar deployment and routed surfaces
- `documents/tools/harbor.md` - Harbor deployment, routed portal or API split, and the dynamic Kind hostPort behavior (Sprint 3.11)
- `documents/architecture/runtime_modes.md` - substrate-to-architecture mapping, including the
  native `linux-cpu` architecture selector and Wave F native arm64 validation closure for
  Sprint 3.12
- `documents/architecture/overview.md` - substrate-matched container architecture cross-link and
  native Linux CPU architecture support
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) -
  Managed State Transitions doctrine this phase now references for the Sprint 3.14 Readiness kernel
  and typed subprocess-env seam
- no monitoring engineering doc is created while monitoring remains unsupported; Monitoring is not
  a supported first-class surface.

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory and active-substrate catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup, host-inference bridge behavior, Harbor host-port conflict resolution, and the arm64-native posture (Sprint 3.11)
- `documents/operations/cluster_bootstrap_runbook.md` - Harbor port selection language alongside `edge-port.json` (Sprint 3.11)

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when route prefixes, publication fields, or daemon-location rules change
