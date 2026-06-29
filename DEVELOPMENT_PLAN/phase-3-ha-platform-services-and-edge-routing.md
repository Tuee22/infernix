# Phase 3: HA Platform Services and Edge Routing

**Status**: Done — reopened and re-closed
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, operator-managed PostgreSQL, and
> Pulsar deployments; the Envoy Gateway installation that owns all browser-visible routing on one
> localhost listener; the publication contract; and the route-registry cleanup that removes route
> duplication across Haskell, Helm, route-oriented docs, and route-aware validation.

## Phase Status

Phase 3 closes around the mandatory HA service set, the shared routed edge, and the
Haskell-owned route registry implemented in this worktree. Sprints 3.1-3.12 are `Done` after
Apple cohort validation in Waves A/A.2, CUDA Linux cohort validation in Wave C, and native arm64
`linux-cpu` validation in Wave F. Sprint 3.12 closed on the recorded validation through the already selected
native arm64 Docker daemon on this Apple Silicon machine: Docker reported `server=linux/arm64`,
the Linux runtime probe reported `aarch64` / `arm64`, and the full Linux CPU outer-container
validation suite passed without cross-architecture emulation, Docker-context switching, or VM
creation. The clarified Apple daemon-role model is
implemented in Phase 6 Sprint 6.25 and separates cluster daemon location from host inference
executor location in publication metadata.

Phase 3 reopened and re-closed for Sprint 3.13, which de-exposes the `/minio/s3` external gateway
route so the `infernix-demo` webapp becomes the **sole** externally routed file-storage service: the
browser reaches MinIO only through the webapp object-proxy (Phase 7 Sprint 7.25), never through a
gateway route or a presigned MinIO URL. This realizes the
[../documents/architecture/object_access_doctrine.md](../documents/architecture/object_access_doctrine.md).
Sprints 3.1–3.13 are `Done`; Sprint 3.13 is code-side closed (2026-06-24, machine-independent gates
green) and cohort-closed by [Wave M](cohort-validation-waves.md) on 2026-06-29 with the selected
`linux-gpu` accelerator plus `linux-cpu` full-suite evidence. The route-inventory prose below now
reflects the de-exposed surface (no `/minio/s3` route, no `presignPublicEndpoint`).

## HA Reconcile Surface

- `infernix cluster up` is the declarative and idempotent entrypoint for the mandatory local HA topology
- the supported cluster path always deploys the local HA topology
- no service-specific HA bootstrap command family exists outside the supported cluster reconcile surface

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

The supported cluster path runs the HA platform services and the optional demo HTTP host on the
Kind substrate. Publication metadata originates from `./.data/runtime/publication.json`, exposes
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
native Linux arm64 to `arm64` while keeping `linux-gpu` amd64-only. Wave F validated the native
arm64 publication path through the selected native arm64 Docker daemon on the recorded validation.

## Sprint 3.1: HA MinIO Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/object_storage.md`, `documents/tools/minio.md`

### Objective

Provide the HA MinIO deployment and routed object-store surfaces required by Harbor and the
reserved cluster object-store path.

### Deliverables

- MinIO always deploys as a four-node distributed cluster with manual PV backing
- repo-owned values suppress hard pod anti-affinity that would block local Kind scheduling
- MinIO console and S3 API are both exposed through the shared edge
- the chart reserves MinIO as the Kind-backed object-store target for Harbor and cluster-routed
  object-store access, while durable object-store state lives only in the MinIO buckets
  `infernix-models` (always-on platform model weights),
  `infernix-engine-artifacts` (always-on engine software payloads), and
  `infernix-demo-objects` (demo-gated user uploads and engine-generated artifacts), the on-disk
  `./.data/object-store/` tree having been retired by Phase 7 Sprint 7.7

### Validation

- `infernix cluster up` creates a healthy four-node distributed MinIO deployment
- MinIO PVCs bind via `infernix-manual`
- routed MinIO console and S3 surfaces respond on the shared edge port

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

- Pulsar deploys through the Helm chart with HA settings where the chart exposes them
- durable Pulsar components use manual PVs under `./.data/`
- the edge exposes browser- and host-consumable Pulsar HTTP or WebSocket surfaces
- inference-request, result, and coordination payloads are defined by repo-owned `.proto` schemas

### Validation

- `infernix cluster up` produces a healthy Pulsar deployment
- Pulsar PVCs bind through `infernix-manual`
- routed Pulsar admin and WebSocket surfaces respond on the shared edge port

### Remaining Work

None.

---

## Sprint 3.4: HA Harbor Deployment [Done]

**Status**: Done
**Implementation**: `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/tools/harbor.md`

### Objective

Provide the mandatory local HA image registry and browser portal for cluster images.

### Deliverables

- Harbor deploys through its Helm chart
- Harbor stores image blobs in MinIO and uses an operator-managed Patroni PostgreSQL backend
- Harbor application-plane workloads use the mandatory HA topology where the chart exposes it
- the Harbor portal is exposed through the shared edge

### Validation

- `infernix cluster up` produces a healthy Harbor release with the expected HA shape
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

## Sprint 3.6: Demo HTTP Host (`infernix-demo`) and Host-Demo Bridge Retirement [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Provide the current demo HTTP API surface through the `infernix-demo` Haskell binary while keeping
one stable clustered browser entrypoint across substrates.

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
- the recorded validation (legacy hardware): clean-env `linux-gpu` compose-run `infernix test e2e` had
  passed via the in-container Playwright path (`1 passed`). That proof point was on the legacy
  Linux/CUDA host and no longer counts as current evidence.
- the recorded validation (legacy hardware): Apple host-native E2E runner code landed; `cabal build all`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and `node --check` for
  `web/playwright.config.js` and `web/playwright/inference.spec.js` had passed. Those are
  retried trivially on the new host but the historical pass is no longer cited as current proof.
- Apple host-native Playwright validation closed in Waves A.1/A.2, and Linux in-container
  Playwright validation closed in Wave C.

### Remaining Work

Landed the recorded validation:

- `docker/playwright.Dockerfile` deleted.
- `compose.yaml` `playwright` service block deleted; the file now
  declares only the `infernix` service with its two supported bind
  mounts.
- `docker/Dockerfile` gains a dedicated `RUN` step that
  invokes
  `apt-get update && npm --prefix web exec -- playwright install --with-deps chromium firefox webkit && rm -rf /var/lib/apt/lists/*`
  so the launcher image carries Chromium / Firefox / WebKit plus their
  system dependencies.
- `src/Infernix/CLI.hs.runRuntimeModeE2E` routes the outer-container
  path through the new `runInContainerPlaywright` helper that writes a
  typed JSON fixture (`<runtimeRoot>/playwright-fixture.json`) and
  then runs `npm --prefix web exec -- playwright test playwright/inference.spec.js`
  inside the launcher container. The legacy
  `runPlaywrightImage`/`docker compose run --rm playwright` path is
  gone. The Apple host-native branch now writes the same fixture and
  runs the same Playwright suite via host-native `npm exec` against
  the published localhost edge port.
- `web/playwright.config.js` (new) reads the repo-relative
  `.data/runtime/playwright-fixture.json` and exposes the
  expected daemon location / executor location / dispatch mode /
  upstream mode through Playwright's `use:` block under the
  `infernix-e2e` project.
- `web/playwright/inference.spec.js` rewritten: the per-test handler
  receives the typed `infernixFixture` Playwright option instead of reading any
  `process.env.INFERNIX_*` field or a hardcoded `/workspace` fixture
  path.
- The seven legacy env vars
  (`INFERNIX_EDGE_PORT`, `INFERNIX_PLAYWRIGHT_HOST`,
  `INFERNIX_PLAYWRIGHT_NETWORK`,
  `INFERNIX_EXPECT_DAEMON_LOCATION`,
  `INFERNIX_EXPECT_INFERENCE_EXECUTOR_LOCATION`,
  `INFERNIX_EXPECT_INFERENCE_DISPATCH_MODE`,
  `INFERNIX_EXPECT_API_UPSTREAM_MODE`) are gone from `src/`,
  `compose.yaml`, `docker/`, and `web/playwright/`; only retirement
  doc-comments remain.

Verified end-to-end on the host: `cabal build all` clean,
`cabal test infernix-unit` and `cabal test infernix-haskell-style`
pass, `node --check web/playwright.config.js`,
`node --check web/playwright/inference.spec.js`, and
`infernix lint {files,chart,docs,proto}` exit zero after the May 27
documentation refresh. The Sprint 3.10 grep gate
(`grep -rEn 'INFERNIX_EDGE_PORT|INFERNIX_PLAYWRIGHT_*|INFERNIX_EXPECT_*' src/ compose.yaml docker/ web/`)
returns only retirement doc-comments (in `src/Infernix/CLI.hs`,
`web/playwright.config.js`, and the Phase 5 Sprint 5.9 binary-resolution note in
`web/test/run_playwright_matrix.mjs`); no live INFERNIX_EDGE_PORT /
INFERNIX_PLAYWRIGHT_* / INFERNIX_EXPECT_* reads remain.

Closed validation:

- **Linux in-container Playwright E2E proof point on the recorded validation (legacy hardware).** The
  clean-env compose-run command
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix test e2e`
  had reconciled the live `linux-gpu` cluster, ran Playwright inside the
  launcher image, reported `1 passed`, then executed its teardown
  cleanup on the legacy Linux/CUDA host. That proof point is no longer current; CUDA Linux
  cohort rerun closed in Wave C on the native Linux/CUDA host.
- Apple host-native E2E validation closed in Waves A.1/A.2 using the same typed fixture path.

---

## Sprint 3.11: Apple Silicon Native Architecture, Bitnamilegacy Retirement, Harbor Port Dynamic Discovery [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs` (`clusterWorkloadArchitecture`, `chooseHarborPort`, `currentKindHarborPort`, `clusterSubprocessBaseEnvFor`, `renderKindConfig`, `renderHelmValues`, `harborApiHost`, `publishClusterImages`, `prepareKindNodeRuntimePaths`, `writeRegistryHostsConfig`), `src/Infernix/Cluster/PublishImages.hs` (`HarborPublishOptions.harborTargetArchitecture`, `pinLocalImageToTargetArchitecture`, `extractDigestForArchitecture`, `contentAddressTagFromManifestPayload`, `pushUpstreamMultiArchViaImagetools`, `recoverOriginalTag`, the MinIO overlay), `src/Infernix/ProcessMonitor.hs` (`processMonitorBaseEnvFor`), `src/Infernix/Storage.hs` (`harborPortPath`, `readHarborPortMaybe`), `src/Infernix/Types.hs` (`ClusterState.harborPort`), `src/Infernix/HostConfig.hs` (`defaultAppleHostNativeHostConfig`), `src/Infernix/DemoConfig.hs` (`materializeHostManifestFile`, `resolveOperatorHomeDirectory`), `app/Main.hs` (`hSetBuffering LineBuffering`), `chart/values.yaml` (MinIO overrides + console disabled), `test/unit/Spec.hs` (`samplePublishedImages`, overlay assertions, `contentAddressTagFromManifestPayload` arch fixture).
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
- **`bitnamilegacy/*` retirement.** `chart/values.yaml` overrides
  `minio.image.repository → minio/minio`,
  `minio.clientImage.repository → minio/mc`,
  `minio.defaultInitContainers.volumePermissions.image.repository → busybox`,
  and sets `minio.console.enabled: false`. The Harbor overlay code in
  `PublishImages.hs` drops the `console` block. `hostCachedWarmupImageRefs`
  tracks the new image inventory.
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

### Validation

- `cabal build all`, `cabal test infernix-haskell-style`, and
  `cabal test infernix-unit` all exit zero on the new Apple Silicon host
  (the recorded validation).
- `infernix lint files|chart|docs|proto` all exit zero.
- `rg -n 'bitnamilegacy' chart/ src/` returns matches only inside the
  retirement comments documenting what was removed; no active code refs.
- `rg -n '"--platform","linux/amd64"' src/Infernix/Cluster/` returns zero
  matches; all `--platform` flags now read from
  `harborTargetArchitecture` or `clusterWorkloadArchitecture`.
- the recorded validation Apple cohort lifecycle proof point (`./.build/infernix`
  on the new Apple Silicon host):
  - `chooseHarborPort` selected `30003` when an unrelated host process
    held `127.0.0.1:30002` — proof that the bind-test + increment loop
    fires correctly.
  - Substrate-aware publication ran every upstream image through
    `docker pull --platform linux/arm64` and `skopeo` paths with
    `--override-arch=arm64` (verified in the streamed phase output).
    All 9 platform images (`infernix-linux-cpu`, `apachepulsar/pulsar-all`,
    `busybox`, `envoyproxy/gateway`, `minio/mc`, `minio/minio`,
    `percona/percona-distribution-postgresql`,
    `percona/percona-pgbackrest`, `percona/percona-pgbouncer`,
    `percona/percona-postgresql-operator`, `quay.io/keycloak/keycloak`)
    published as native arm64 through Harbor at `localhost:30003`.
  - Kind workers pulled and ran every Harbor-mirrored image natively;
    the previous `Fatal glibc error: CPU does not support x86-64-v3`
    Percona operator crash is gone — the operator runs as
    `linux/arm64` and reports `Running 1/1`.
  - The hand-authored MinIO StatefulSet (`chart/templates/minio/`)
    reached `Running 4/4` and the `infernix-minio-provisioning` Job
    completed (`mc mb --ignore-existing local/harbor-registry
    local/infernix-models local/infernix-engine-artifacts local/infernix-demo-objects`) without
    bitnami chart wrapper interference.
  - Containerd `config_path = "/etc/containerd/certs.d"` patch
    honored — Kind workers resolved `localhost:30003/library/*` via
    the rendered registry-hosts mapping.
  - **Full lifecycle:** `cluster up` reached
    `lifecyclePhase: steady-state` with `kubernetesPodCount: 76` and
    `storageHealth: 26 chart-owned claim roots prepared`;
    `cluster down` completed; final `cluster status` reported
    `clusterPresent: False`, `lifecycleStatus: idle`,
    `lifecyclePhase: cluster-absent`.

- **`infernix test all` Apple cohort residual.** The recorded-validation
  Apple `cluster up → status → cluster down → status` cycle above is
  the validated platform proof point. The full `test all` integration
  layer additionally exercises a clean-state cluster down + cluster
  up replay; that pattern surfaced a retained-state Keycloak Patroni
  corruption issue (the previous instance's partial `/pgdata/pg18`
  tree, when copied back from the retained host directory into a
  fresh Kind worker, causes `postgres-startup` to crash with an
  initialization error). The supported fix landed on the recorded validation in
  `src/Infernix/Cluster.hs`: `isPatroniManagedClaim` filters operator-
  managed Patroni claims (`harbor-postgresql-*`,
  `keycloak-postgresql-*`) out of `syncClaimDirectoriesFromOwningNodes`
  so retained Patroni trees are no longer copied back to the host on
  `cluster down`, and `scrubStalePatroniDirectories` defensively removes
  any pre-existing trees from `<kindRuntimeRoot>/platform/infernix/`
  on the next `cluster up`'s `prepare-kind-cluster` phase. Apple
  cohort revalidation closed in Wave A after the integration replay
  scenario exercised the retained-state fix.
- **GPU cohort full-suite validation closed on the native Linux/CUDA
  host:** the Apple cohort full-suite rerun passed on the recorded validation, the
  native `linux-cpu` full-suite rerun passed on the recorded validation, and the
  matching `linux-gpu` full-suite rerun passed on the recorded validation.

### Remaining Work

None. Apple cohort validation closed in Waves A/A.2, including the
`repoEngineReplicaCount FinalPhase + AppleSilicon -> 0` follow-on that
removed the competing in-cluster Apple engine. CUDA Linux full-suite
revalidation closed in Wave C.

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
- `./bootstrap/linux-cpu.sh test` passes on a native amd64 Linux host; the recorded validation run passed
  Haskell style, Python quality, Haskell unit, PureScript build, 71/71 web unit tests, full
  integration, and routed Playwright E2E (7/7) against launcher image digest
  `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`, while Harbor
  publication and warmup-image hydration emitted `docker pull --platform linux/amd64` and
  `skopeo --override-arch=amd64`
- Wave F native `linux/arm64` `linux-cpu` validation passes through an already selected native
  arm64 Docker daemon, without cross-architecture emulation or Docker-context changes
- `rg -n '"amd64".*LinuxCpu|LinuxCpu.*"amd64"' src test` has no unsupported hardcode after the
  selector lands
- `infernix lint docs` passes through the active execution context
- the recorded validation Apple local gate: `cabal test infernix-unit` passed the LinuxCpu amd64/arm64
  selector assertions, and `rg -n '"amd64".*LinuxCpu|LinuxCpu.*"amd64"' src test`
  returned no matches.
- the recorded validation ordered follow-up from a Linux x86_64 host confirmed the amd64
  `linux-cpu` lane remained healthy but did not exercise the native arm64 publication path:
  `./bootstrap/linux-cpu.sh doctor` passed, the mounted-source Linux CPU
  `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `cabal test infernix-integration` gates passed, and
  `rg -n '"amd64".*LinuxCpu|LinuxCpu.*"amd64"' src test` returned no matches.
- the recorded validation Apple Silicon follow-up on this host confirmed the local selector and documentation
  gates remain healthy:
  `./bootstrap/apple-silicon.sh build` produced `./.build/infernix` and
  `./.build/infernix-demo`, `/opt/homebrew/bin/cabal test infernix-unit` passed, and
  `rg -n '"amd64".*LinuxCpu|LinuxCpu.*"amd64"' src test` returned no matches.
  `./.build/infernix lint docs` passed after the documentation-status update.
- the recorded validation Wave F closure validated the native arm64 Linux CPU publication path through the
  already selected native arm64 Docker daemon on this Apple Silicon machine. Docker reported
  `client=darwin/arm64` and `server=linux/arm64`; a Linux runtime probe reported
  `uname -m = aarch64` and `dpkg --print-architecture = arm64`. The rebuilt
  `infernix-linux-cpu:local` image reported `os=linux arch=arm64` and digest
  `sha256:aae535e31b79b403a3878063371dfc6fd1160baf60a7ce69232c459baebd83e9`.
  `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all`
  passed Haskell style, Python quality, Haskell unit/property, PureScript build and 71/71 web unit
  tests, full `infernix-integration`, and routed Playwright E2E `7 passed (1.7m)`. The run emitted
  native `docker pull --platform linux/arm64` publication, Harbor-backed final-image preload
  before final Helm wait, and clean cluster teardown. Integration covered Harbor recovery, MinIO
  durability, routed Pulsar recovery, PostgreSQL failover and lifecycle rebinding, Linux engine
  anti-affinity, frontend pod replacement, coordinator failover, engine pod replacement, engine
  node drain, model-bootstrap failover/deduplication, and multi-user durable prompt throughput
  (`users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12 p95Seconds=71.37436628341675`).

### Remaining Work

None.

---

## Sprint 3.13: MinIO Gateway De-Exposure [Done]

**Status**: Done
**Code-side closure**: Done (2026-06-24, machine-independent). The `infernix-minio-s3` `RouteSpec`
is removed from `src/Infernix/Routes.hs` (so the rendered `chart/templates/httproutes.yaml`
`.Values.routes` loop and its generated registry comment carry no `/minio/s3`), the
`infernix-minio-s3` SecurityPolicy target is dropped from
`chart/templates/securitypolicy-operator-routes.yaml` (and from the `infernix lint chart`
required-phrase set), and `clusterConfig.minio.presignPublicEndpoint` is retired from the typed
cluster config (`dhall/InfernixCluster.dhall` regenerated from the decoder-reflected schema,
`ClusterConfig.hs`, `chart/templates/configmap-cluster-config.yaml`, `chart/values.yaml`, and the
`Cluster.hs` Helm-values renderer). The route registry, generated route summaries (README,
`edge_routing.md`, `web_portal_surface.md`, `tools/minio.md`, `cluster_bootstrap_runbook.md`), and
rendered chart expose no `/minio/s3` route and no `presignPublicEndpoint`. Gates green:
`cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
`infernix lint files/chart/docs/proto`, and `infernix docs check` all exit zero on the host
toolchain. Implemented jointly with [Phase 7 Sprint 7.25](phase-7-demo-app-durable-context.md) (the
webapp object-proxy) because the `presignPublicEndpoint` field's only consumer was the presigned-URL
grant handler that 7.25 replaces.
**Cohort gate**: Closed by [Wave M](cohort-validation-waves.md) on 2026-06-29 — `linux-cpu` plus the
chosen `linux-gpu` accelerator.
**Implementation**: `chart/templates/httproutes.yaml`, `chart/templates/securitypolicy-operator-routes.yaml`, `dhall/InfernixCluster.dhall`
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
  summaries name no `/minio/s3` route and no `presignPublicEndpoint` — both pass (2026-06-24).
  `rg -n 'minio-s3|presignPublicEndpoint' src chart dhall` returns only retirement comments and
  legacy-tracking references.
- [Wave M](cohort-validation-waves.md) closed the `linux-cpu` plus chosen `linux-gpu` full suite:
  the paired `linux-cpu` gate passed on 2026-06-29, and `./bootstrap/linux-gpu.sh test` passed on
  2026-06-29 with full integration, routed Playwright `9/9`, and the browser per-model matrix
  (`28.5m`) proving the routed surface exposes the webapp as the only external file gateway and the
  browser never reaches MinIO directly.

### Remaining Work

None. Delivered jointly with [Phase 7 Sprint 7.25](phase-7-demo-app-durable-context.md) and closed
by [Wave M](cohort-validation-waves.md).

### Documentation Requirements

- update `documents/engineering/edge_routing.md` to drop `/minio/s3` from the route inventory and
  name the webapp `/api/objects` surface as the only external file gateway
- keep `documents/architecture/object_access_doctrine.md` and
  `documents/reference/web_portal_surface.md` aligned with the de-exposed route surface
- record the retired `/minio/s3` route, `infernix-minio-s3` SecurityPolicy, and
  `presignPublicEndpoint` in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

---

## Remaining Work

None. Sprints 3.1-3.13 are `Done`; Sprint 3.13 closed in
[Wave M](cohort-validation-waves.md) with the selected `linux-gpu` accelerator plus `linux-cpu`.
Apple cohort validation for earlier Phase 3 work closed in Waves A/A.2, CUDA Linux cohort validation
closed in Wave C, and native arm64 `linux-cpu` validation closed in Wave F.

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
- no monitoring engineering doc is created while monitoring remains unsupported; Monitoring is not
  a supported first-class surface.

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory and active-substrate catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup, host-inference bridge behavior, Harbor host-port conflict resolution, and the arm64-native posture (Sprint 3.11)
- `documents/operations/cluster_bootstrap_runbook.md` - Harbor port selection language alongside `edge-port.json` (Sprint 3.11)

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when route prefixes, publication fields, or daemon-location rules change
