# Phase 3: HA Platform Services and Edge Routing

**Status**: Active (Sprint 3.10 Linux in-container Playwright E2E validated May 27, 2026; Apple host-native E2E refactor remains deferred; Sprints 3.1–3.9 Done)
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the mandatory local HA Harbor, MinIO, operator-managed PostgreSQL, and
> Pulsar deployments; the Envoy Gateway installation that owns all browser-visible routing on one
> localhost listener; the publication contract; and the route-registry cleanup that removes route
> duplication across Haskell, Helm, route-oriented docs, and route-aware validation.

## Phase Status

Phase 3 is closed around the mandatory HA service set, the shared routed edge, and the
Haskell-owned route registry implemented in this worktree. Sprints 3.1–3.9 remain `Done` for
their original scope. The clarified Apple daemon-role model is implemented in Phase 6 Sprint 6.25
and separates cluster daemon location from host inference executor location in publication
metadata.

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
- when the demo UI is enabled, `/`, `/api`, `/objects`, `/harbor/api`, `/harbor`,
  `/minio/console`, `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` remain the published route
  inventory
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
  object-store access, while the current validated runtime keeps durable object-store state under
  `./.data/object-store/`

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
- the demo cluster remains local-only and publishes plain HTTP with no auth filter

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

## Sprint 3.10: Playwright Container Retirement and Edge Manifest Retirement [Active]

**Status**: Active
**Blocked by**: Phase 1 Sprint 1.11 (Host Manifest Materialization)
**Implementation**: `docker/playwright.Dockerfile` (deleted), `docker/linux-substrate.Dockerfile` (gains Playwright runtime), `compose.yaml` (drop `playwright` service), `src/Infernix/CLI.hs` (runEndToEnd refactor), `web/playwright/inference.spec.js`, `web/playwright.config.js` (new fixture-driven config)
**Docs to update**: `documents/engineering/host_tools_manifest.md`, `documents/development/testing_strategy.md`, `documents/development/demo_app_test_plan.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Eliminate the dedicated `infernix-playwright:local` image and the separate `playwright` compose
service. Playwright runtime (Chromium/Firefox/WebKit dependencies, fonts, gstreamer plugins, xvfb)
moves into `docker/linux-substrate.Dockerfile`. `infernix test e2e` invokes Playwright via the
in-container `npm exec --prefix web -- playwright test …` against the routed cluster on Docker's
private `kind` network. Retire `INFERNIX_EDGE_PORT`, `INFERNIX_PLAYWRIGHT_HOST`,
`INFERNIX_PLAYWRIGHT_NETWORK`, and the `INFERNIX_EXPECT_*` family in favor of substrate `.dhall`
fields plus a Dhall-driven Playwright fixture file. Apple host-native E2E is unaffected.

### Deliverables

- `docker/playwright.Dockerfile` deleted.
- `compose.yaml` `playwright` service block deleted; only the `infernix` service remains.
- `docker/linux-substrate.Dockerfile` gains the Playwright system packages and runs
  `npm exec --prefix web -- playwright install --with-deps chromium firefox webkit` at image
  build time.
- `src/Infernix/CLI.hs` `runEndToEnd` invokes `runHostTool hostConfig HostNpm
  ["exec", "--prefix", "web", "--", "playwright", "test", "playwright/inference.spec.js"]`
  inside the launcher container. The browser connects to `http://127.0.0.1:9090`.
- `INFERNIX_EDGE_PORT`, `INFERNIX_PLAYWRIGHT_HOST`, `INFERNIX_PLAYWRIGHT_NETWORK`,
  `INFERNIX_EXPECT_DAEMON_LOCATION`, `INFERNIX_EXPECT_INFERENCE_DISPATCH_MODE`,
  `INFERNIX_EXPECT_API_UPSTREAM_MODE`, `INFERNIX_EXPECT_INFERENCE_EXECUTOR_LOCATION` all
  deleted from `compose.yaml`, `src/Infernix/CLI.hs`, and `web/playwright/inference.spec.js`.
- `web/playwright.config.js` reads `/workspace/.data/runtime/playwright-fixture.json`
  (Dhall-decoded by the Haskell test driver at test start) and exposes the expectations via
  Playwright's `use:` block; the spec reads `test.info().project.use.*`.
- legacy-tracking row 3.10 moves from Pending Removal to Completed.

### Validation

- `cabal build all` clean, `infernix test lint` clean.
- `docker images` shows no `infernix-playwright:local` image after a fresh
  `./bootstrap/linux-gpu.sh build`.
- May 27, 2026: clean-env `linux-gpu` compose-run `infernix test e2e` passed via the
  in-container Playwright path (`1 passed`).

### Remaining Work

Landed May 24, 2026:

- `docker/playwright.Dockerfile` deleted.
- `compose.yaml` `playwright` service block deleted; the file now
  declares only the `infernix` service with its two supported bind
  mounts.
- `docker/linux-substrate.Dockerfile` gains a dedicated `RUN` step that
  invokes
  `apt-get update && npm --prefix web exec -- playwright install --with-deps chromium firefox webkit && rm -rf /var/lib/apt/lists/*`
  so the launcher image carries Chromium / Firefox / WebKit plus their
  system dependencies.
- `src/Infernix/CLI.hs.runRuntimeModeE2E` routes the outer-container
  path through the new `runInContainerPlaywright` helper that writes a
  typed JSON fixture (`<runtimeRoot>/playwright-fixture.json`) and
  then runs `npm --prefix web exec -- playwright test playwright/inference.spec.js`
  inside the launcher container. The retired
  `runPlaywrightImage`/`docker compose run --rm playwright` path is
  gone. The Apple host-native branch surfaces a typed deferral
  diagnostic — host-native E2E lands together with the Apple bootstrap
  refactor.
- `web/playwright.config.js` (new) reads
  `/workspace/.data/runtime/playwright-fixture.json` and exposes the
  expected daemon location / executor location / dispatch mode /
  upstream mode through Playwright's `use:` block under the
  `infernix-e2e` project.
- `web/playwright/inference.spec.js` rewritten: the per-test handler
  pulls `testInfo.project.use.infernixFixture` instead of reading any
  `process.env.INFERNIX_*` field.
- The seven retired env vars
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
pass, `infernix lint {files,chart,docs,proto}` exit zero. The
Sprint 3.10 grep gate
(`grep -rEn 'INFERNIX_EDGE_PORT|INFERNIX_PLAYWRIGHT_*|INFERNIX_EXPECT_*' src/ compose.yaml docker/ web/`)
returns only the two retirement doc comments
(`src/Infernix/CLI.hs:344`, `web/playwright.config.js:4`).

Pending closure (deferred to a follow-on turn):

- **Linux in-container Playwright E2E closed May 27, 2026.** The
  clean-env compose-run command
  `env -i /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml --file compose.linux-gpu.yaml run --rm infernix infernix test e2e`
  reconciled the live `linux-gpu` cluster, ran Playwright inside the
  launcher image, reported `1 passed`, then executed its teardown
  cleanup. This validates the replacement for the retired
  `infernix-playwright:local` lane on the Linux CUDA host.
- Apple host-native E2E refactor. The current Apple branch in
  `runRuntimeModeE2E` surfaces an explicit deferral diagnostic so the
  Linux closure is honest about the gap. The Apple replacement (a
  host-side `npm exec` Playwright invocation fed by the same typed
  fixture) lands together with the deferred `bootstrap/apple-silicon.sh`
  stage-zero refactor.
- `documents/engineering/host_tools_manifest.md` and
  `documents/development/testing_strategy.md` reference touch-ups for
  the new fixture-driven path. The shape is consistent with the
  existing docs (the doc-update list in this sprint's header already
  names the targets); the per-doc reword lands in a Sprint 7.16
  documentation-closure pass.

---

## Remaining Work

Sprint 3.10 substantively landed May 24, 2026. The Linux in-container
Playwright path was validated on `linux-gpu` May 27, 2026. Apple
host-native E2E refactor remains the only Sprint 3.10 residual.
Sprints 3.1–3.9 closed.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/edge_routing.md` - Envoy Gateway installation, single listener, route-registry ownership, and no-auth demo-cluster posture
- `documents/engineering/object_storage.md` - repo-local object-store rules plus reserved MinIO path and routed access
- `documents/engineering/k8s_storage.md` - manual PV doctrine and PostgreSQL claim binding
- `documents/tools/minio.md` - MinIO deployment and routed surfaces
- `documents/tools/postgresql.md` - Percona operator and Patroni deployment rules
- `documents/tools/pulsar.md` - Pulsar deployment and routed surfaces
- `documents/tools/harbor.md` - Harbor deployment and routed portal or API split
- no monitoring engineering doc is created while monitoring remains unsupported; Monitoring is not
  a supported first-class surface.

**Product or reference docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser-visible route inventory and active-substrate catalog behavior
- `documents/operations/apple_silicon_runbook.md` - Apple host-mode startup and host-inference bridge behavior

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when route prefixes, publication fields, or daemon-location rules change
