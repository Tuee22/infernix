# Phase 6: Validation, E2E, and HA Hardening

**Status**: Done
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported static-quality and single-substrate validation contract for the
> two-binary topology, the README-matrix-driven integration suite, the Pulsar-driven production
> inference surface, the demo UI host, the substrate-generated catalog, the mandatory HA behavior
> of Harbor, MinIO, operator-managed PostgreSQL, and Pulsar, and the repository-hardening plus
> false-negative-doctrine closure that keeps governed root docs,
> route-aware docs, and the CLI surface mechanically aligned with implementation.

## Phase Status

Phase 6 is done. Sprints 6.1–6.25 are `Done`: the validation entrypoints, routed coverage,
governed-root-document metadata closure, structured CLI-registry closure, route-hardening cleanup,
supported bootstrap lifecycle fixes, false-negative doctrine, Harbor publication retry closure,
and daemon-role split are present in the current worktree, and the supported test story is
substrate-specific. Sprint 6.25 closes around the implemented split topology: cluster daemons
always run, Apple cluster daemons own fan-in, batching coordination, and batch handoff, Apple
inference batches move through Pulsar to same-binary host daemons, and publication distinguishes
cluster daemon location from inference executor location.
The worktree also carries the
formatter-toolchain closure that is actually implemented today:
`src/Infernix/Lint/HaskellStyle.hs` drives `ormolu` and `hlint` through the dedicated compatible
formatter compiler `ghc-9.12.4`, and the Linux substrate image preinstalls that compiler beside
the project `ghc-9.14.1` toolchain. The supported Linux outer-container launcher reuses a
persistent `chart/charts/` archive cache, hydrates MinIO through the supported direct tarball
path instead of Docker Hub-backed OCI metadata, and repairs the known stale retained Pulsar or
ZooKeeper epoch mismatch by resetting only the Pulsar claim roots and retrying once.

## Current Repo Assessment

The repository has lint, unit, integration, and Playwright entrypoints. The canonical testing,
boundary, portability, storage, and Haskell-style docs are present, the baked Linux substrate
image definition writes the source-snapshot manifest needed for git-less `infernix lint files`
runs, the routed Playwright suite exhaustively exercises every demo-visible generated catalog
entry for the active substrate, and the integration suite enumerates every generated
active-substrate catalog entry while also carrying Harbor, MinIO, Pulsar, and Harbor PostgreSQL
recovery or lifecycle checks in code. The staged file, `cluster status`, publication JSON, and
generated browser contracts still expose the active substrate through `runtimeMode` fields or
lines. The worktree omits direct Harbor, MinIO, and Pulsar compatibility handlers from
`src/Infernix/Demo/Api.hs`, tightens `test/integration/Spec.hs` to require the real routed
upstream behavior, persists cluster state before later Linux rollout phases, restages the active
Linux substrate on each supported bootstrap invocation, reuses a persistent Linux chart-archive
cache, and performs the targeted Pulsar claim-root reset when the known retained ZooKeeper
epoch-state corruption blocks bootstrap. Recorded validation for this phase covers the governed
`linux-cpu` and `linux-gpu` bootstrap surfaces. Recorded Apple validation on May 11, 2026 reran
cleanly through `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and
`down`. On Apple, routed Playwright no longer times out on `host.docker.internal`: host-side
readiness probes `127.0.0.1:<edge-port>`, the browser container joins the private Docker `kind`
network and targets the Kind control-plane DNS on port `30090`, and the dedicated Playwright
image no longer bakes a conflicting `NO_COLOR` default. On May 13, 2026, the supported Apple
lifecycle reran cleanly through `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`,
`test`, and `down` on the patched shared lifecycle: `cluster status` reported the active
in-progress lifecycle phase, child-operation detail, and heartbeat while `up` and `down` were
still running; steady-state status reported two nodes and sixty-five pods; final post-teardown
status returned `clusterPresent: False`, `lifecycleStatus: idle`, and
`lifecyclePhase: cluster-absent`; the governed testing doctrine, operator-facing testing strategy,
lifecycle runbooks, and CLI references use the same inactivity-aware interpretation contract; and
retained-state Harbor PostgreSQL replicas recovered through the supported targeted
reinitialization path when timeline drift leaves replicas stopped after promotion. That rerun also
confirmed that Apple `build-cluster-images` can remain healthy well past thirty minutes before
Harbor publication begins, that Harbor image pushes are readiness-gated with bounded retries
across transient registry resets, and that the governed `test` lane may perform multiple internal
cluster bring-up or teardown cycles before the outer bootstrap command returns. The runtime-topology
implementation now deploys `infernix-service` on Apple and reports `daemonLocation: cluster-pod`,
`inferenceExecutorLocation: control-plane-host`, and the Apple host batch topic in publication
metadata. On May 14, 2026, the full governed Apple lifecycle reran cleanly through
`./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
`status` on the split topology. The `test` lane passed Haskell style, Haskell unit, PureScript
unit, Haskell integration, routed Playwright, repeated retained-state `cluster down` and
`cluster up` cycles, Apple host-batch inference for every active generated catalog entry, and
final retained-state teardown. Final post-teardown status returned `clusterPresent: False`,
`lifecycleStatus: idle`, `lifecyclePhase: cluster-absent`, `runtimeResultCount: 31`,
`objectStoreObjectCount: 73`, `modelCacheEntryCount: 30`, and `durableManifestCount: 15`.

## Validation Surface

The supported validation entrypoints are:

- `infernix lint files`
- `infernix lint docs`
- `infernix lint proto`
- `infernix lint chart`
- `infernix docs check`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`

These commands are declarative and idempotent validation entrypoints. Re-running them rechecks the
same contract and may reconcile supported prerequisites instead of depending on alternate setup
commands.

## Current Validation Baseline

- `test unit` proves matrix typing, generated catalog rendering, and contract-generation logic
- supported `test lint` and `test unit` commands still require a staged substrate file for
  command-level execution-context validation, while their assertions remain static or unit scoped
  and do not claim real-cluster matrix coverage
- `test integration` validates the active substrate's published catalog contract, routed surfaces,
  and routed inference execution for every generated active-substrate catalog entry
- `test e2e` exercises every demo-visible generated catalog entry for the active substrate
- `test all` reports only the active built substrate instead of implying cross-substrate coverage
- `test integration`, `test e2e`, and `test all` own cluster lifecycle around each test phase:
  the supported entrypoint runs `cluster down` first, executes the test action, and runs
  `cluster down` again unconditionally afterwards so reruns start from a clean cluster state
  without depending on prior operator setup

## Sprint 6.1: Static Quality Gates, Testing Doctrine, and Unit Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Files.hs`, `test/haskell-style/Spec.hs`, `test/unit/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`, `documents/engineering/storage_and_state.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the control plane, shared
contracts, and generated-catalog logic, and put the validation doctrine in canonical docs.

### Deliverables

- `infernix test lint` is the canonical static-quality entrypoint
- the repo-owned lint layer enforces whitespace, newline, tab, docs, chart, proto, and tracked-file policy
- the Haskell style guide clearly separates:
  - hard gates enforced mechanically
  - review guidance that remains human doctrine
  - the enforcement model implemented in `src/Infernix/Lint/HaskellStyle.hs`
- the Haskell style guide states the fail-fast rule explicitly: validation fails on hard-gate
  violations and does not silently rewrite tracked source
- `documents/engineering/testing.md` becomes the canonical testing doctrine
- `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`,
  and `documents/engineering/storage_and_state.md` are expanded so boundary, portability, and
  durability rules are canonical and testable
- `infernix test unit` remains the canonical unit-suite entrypoint for Haskell and PureScript

### Validation

- `infernix test lint` passes when repo-owned lint, docs, and compiler-warning policy are satisfied
- Haskell formatting or lint drift fails `cabal test infernix-haskell-style`
- `infernix test unit` runs both Haskell and frontend unit suites
- docs validation fails if canonical testing or boundary docs drift from the supported implementation

### Remaining Work

None.

---

## Sprint 6.2: Extensive Integration Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Exercise the generated demo-config and service integration path on the final Kind, Helm, Harbor,
MinIO, Pulsar, and operator-managed PostgreSQL substrate.

### Deliverables

- integration coverage for `cluster up`, generated demo-config publication, and routed inference
  execution for every generated active-substrate catalog entry
- host-native integration coverage proves the routed API can keep one browser-visible entrypoint
  while Apple inference remains host-native
- dedicated `linux-gpu` integration coverage proves device-plugin rollout, GPU resources, and
  service GPU visibility
- integration coverage proves routed cache mutation and publication surfaces stay aligned with the
  generated catalog contract

### Validation

- `infernix test integration` reconciles or reuses supported cluster prerequisites
- integration tests fail when publication state, generated catalog publication, per-entry routed
  inference execution, service-loop schema publication, or CUDA scheduling assertions regress

### Remaining Work

None.

---

## Sprint 6.3: Routed Playwright E2E Coverage [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `web/playwright/inference.spec.js`, `web/src/Infernix/Web/Workbench.purs`, `web/src/Main.purs`, `web/src/index.html`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`, `web/package.json`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`

### Objective

Keep routed Playwright validation on the supported final execution paths while exercising the real
browser surface through the shared edge.

### Deliverables

- Playwright suites live under the UI-owned `web/playwright/` surface
- `infernix test e2e` exercises the routed browser surface through `docker compose run --rm playwright`,
  using the same `infernix-playwright:local` image on every substrate; on Apple Silicon the host
  CLI runs it directly, on Linux substrates the outer container runs it against the host docker
  daemon
- `INFERNIX_PLAYWRIGHT_NETWORK`, `INFERNIX_EDGE_PORT`, `INFERNIX_PLAYWRIGHT_HOST`,
  `INFERNIX_EXPECT_DAEMON_LOCATION`, `INFERNIX_EXPECT_INFERENCE_DISPATCH_MODE`, and
  `INFERNIX_EXPECT_API_UPSTREAM_MODE` flow into the playwright service through compose env so the
  same spec covers Apple, `linux-cpu`, and `linux-gpu` without branching in browser code
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`
- E2E covers publication details, model selection, manual inference submission, and result rendering

### Validation

- `infernix test e2e` hits the routed path rather than bypassing the edge
- the routed Playwright suite fails if any active-substrate catalog entry is skipped
- Apple and Linux routed E2E both pass through the same compose-driven Playwright service

### Remaining Work

None.

---

## Sprint 6.4: HA Failure and Recovery Coverage For Harbor, MinIO, and Pulsar [Done]

**Status**: Done
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/chaos_testing.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Back the HA claims with concrete failure coverage.

### Deliverables

- pod-deletion and rolling-restart coverage for Harbor application-plane workloads
- durability and failover coverage for MinIO on the mandatory HA topology
- message continuity and restart coverage for Pulsar on the mandatory HA topology

### Validation

- supported HA subsets prove single-pod failure does not permanently break the supported path
- data written before MinIO or Pulsar restarts remains available afterward
- Harbor-backed image pulls continue to work after supported Harbor pod replacement

### Remaining Work

None.

---

## Sprint 6.5: Cluster Lifecycle and Environment-Matrix Validation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `compose.yaml`, `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Verify the same product contract across Apple host-native and Linux outer-container workflows.

### Deliverables

- the codebase exposes `cluster up`, `cluster status`, and `cluster down` through both execution contexts
- automated coverage proves repo-local kubeconfig, generated demo-config, publication mirror, and
  publication state creation for the active built substrate
- `cluster up` persists repo-local cluster state before later rollout phases so `cluster status`
  and supported cleanup continue to observe an in-progress Linux reconcile
- `cluster status` reports the active substrate through its current `runtimeMode` line together
  with build or data roots, publication details, and the chosen edge port
- `infernix test integration`, `infernix test e2e`, and `infernix test all` own cluster lifecycle
  around each test phase: the supported entrypoint runs `cluster down`, executes the test action,
  and runs `cluster down` again unconditionally afterwards so reruns start from a clean cluster
  state without depending on prior operator setup

### Validation

- validation closes when `infernix test integration` proves the host-native lane creates the
  expected repo-local state
- validation closes when the Linux outer-container lane reaches the cluster successfully through
  its supported path
- validation closes when repeated `cluster up` or `cluster down` behavior and `9090`-first
  edge-port rediscovery remain stable
- validation closes when supported `infernix test ...` reruns leave behind no residual cluster
  state because each phase is bracketed by `cluster down` even when the test action fails partway
  through

### Remaining Work

None.

---

## Sprint 6.6: Generated-Catalog Exhaustive Integration and E2E Coverage Baseline [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/Files.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`

### Objective

Make the README promise concrete for the generated-catalog coverage machinery so the later
single-substrate validation closure rests on explicit per-substrate catalog enumeration rather than
hard-coded lane lists.

### Deliverables

- `infernix test integration` enumerates every generated catalog entry from the active staged
  demo config
- `infernix test e2e` is specified to exercise every demo-visible generated catalog entry through
  the routed browser surface
- `infernix test all` aggregates lint, unit, integration, and E2E without silently dropping catalog entries
- the coverage machinery derives its exercised catalog from the generated substrate file instead of
  hard-coded per-lane model lists

### Validation

- changing the built substrate changes the exercised catalog and engine assertions automatically
- integration fails if any generated catalog entry is skipped
- routed E2E fails if any demo-visible generated catalog entry is skipped once Sprint 6.3 closes

### Remaining Work

None.

---

## Sprint 6.7: Operator-Managed PostgreSQL Failure and Lifecycle Coverage [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/postgresql.md`

### Objective

Back the PostgreSQL doctrine with readiness, failover, and storage-rebind coverage.

### Deliverables

- integration coverage proves Percona and Patroni readiness for Harbor and later PostgreSQL-backed services
- HA-failure coverage deletes or restarts a PostgreSQL member and verifies failover
- lifecycle coverage proves `cluster down` plus `cluster up` reuses the same deterministic Harbor
  PostgreSQL PV inventory and host paths
- validation proves services do not regress to chart-managed standalone PostgreSQL deployments

### Validation

- `infernix test integration` verifies ready operator-managed PostgreSQL members, Patroni failover,
  and deterministic Harbor PV and host-path rebinding
- repeated cluster lifecycle validation fails if Harbor PostgreSQL no longer reuses the same
  deterministic PV inventory and host paths

### Remaining Work

None.

---

## Sprint 6.8: Minimal Host Prerequisites and Clean-Host Bootstrap Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Python.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Minimize host-side prerequisites and let `infernix` reconcile the remaining supported operator
toolchain from package managers instead of depending on a broad preinstalled Apple host stack.

### Deliverables

- Apple host-native flow reduces pre-existing host requirements to Homebrew plus ghcup before
  building `./.build/infernix`
- Colima is the only supported Docker environment on Apple Silicon, and the supported Apple path
  installs or starts Colima through Homebrew-managed tooling
- after the Apple binary exists, `infernix` can reconcile the remaining supported Homebrew-managed
  operator tools needed by the active path, including the Docker CLI, `kind`, `kubectl`, `helm`,
  and Node.js
- when Apple adapter flows first need Poetry and the `poetry` executable is absent, `infernix`
  can reconcile Homebrew `python@3.12`, bootstrap Poetry into a user-local environment, and then
  continue all host-side Python management through the shared Poetry project
- `linux-cpu` host prerequisites stop at Docker Engine plus the Docker Compose plugin
- `linux-gpu` host prerequisites stop at Docker Engine plus the supported NVIDIA driver and
  container-toolkit setup
- clean-host validation proves the supported commands reconcile prerequisites rather than relying on
  undocumented manual setup beyond those minimal host baselines

### Validation

- validation closes when, on a clean Apple Silicon host with only Homebrew plus ghcup present,
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
  succeeds, `./.build/infernix internal materialize-substrate apple-silicon` stages the active
  substrate, and `./.build/infernix cluster up` reconciles the remaining supported Apple host
  prerequisites through the supported package-manager path
- validation closes when Apple host validation proves the supported flow can bootstrap Poetry when
  absent and then run the adapter setup path without manual Poetry installation
- validation closes when, on a clean Linux CPU host with Docker only,
  `docker compose build infernix`,
  `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  and `docker compose run --rm infernix infernix test all` pass
- validation closes when, on a clean Linux GPU host with Docker plus the supported NVIDIA host
  prerequisites, exporting `INFERNIX_COMPOSE_IMAGE=infernix-linux-gpu:local`,
  `INFERNIX_COMPOSE_SUBSTRATE=linux-gpu`, and
  `INFERNIX_COMPOSE_BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04`, then running
  `docker compose build infernix`,
  `docker compose run --rm infernix infernix internal materialize-substrate linux-gpu --demo-ui true`,
  and `docker compose run --rm infernix infernix test all` pass

### Remaining Work

None.

---

## Sprint 6.9: Governed Root-Document Metadata Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `documents/README.md`

### Objective

Close the stricter governed-root-document metadata model so the root entry documents match the
standards they already cite.

### Deliverables

- `README.md` carries the governed root-document metadata block appropriate for an orientation
  document and makes its canonical-home links explicit
- `AGENTS.md` and `CLAUDE.md` carry the explicit supersession or canonical-home markers required
  for governed entry documents and stay thin while linking to the canonical assistant-workflow
  document under `documents/`
- `documents/documentation_standards.md` describes the root-document metadata contract in the same
  terms the repo actually enforces
- the docs linter grows root-document checks strong enough to catch missing root-document metadata
  markers rather than relying on convention alone

### Validation

- `infernix docs check` fails when `README.md`, `AGENTS.md`, or `CLAUDE.md` are missing the
  required governed metadata markers for their declared role
- root docs carry the governed metadata and canonical-home links needed for the canonical
  assistant-workflow entrypoint without losing the canonical topic entrypoints

### Remaining Work

None.

---

## Sprint 6.10: True Single-Definition CLI Registry Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Lint/Docs.hs`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `test/unit/Spec.hs`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `README.md`

### Objective

Collapse the supported CLI surface into one structured Haskell definition so parsing, help text,
and the canonical CLI reference stop drifting independently.

### Deliverables

- one structured Haskell registry owns supported command parsing, help text, and command-family
  metadata
- the canonical CLI reference derives from that same structured registry or from a mechanically
  equivalent generated artifact rather than a separate handwritten command inventory
- `documents/reference/cli_surface.md` remains a short family overview that summarizes and links to
  the canonical CLI reference
- docs lint validates the stronger CLI-registry contract instead of only checking that registry
  command lines appear somewhere in the reference document

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command
  families from the same structured registry source
- changing a supported command in the structured registry changes parsing, help output, and CLI
  reference material through one implementation path
- `infernix docs check` fails when the CLI reference drifts from the structured command registry

### Remaining Work

None.

---

## Sprint 6.11: Registry-Backed Route Docs and Lint Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Routes.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Lint/Docs.hs`, `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining route or publication DRY cleanup so the Haskell route registry drives
route-aware docs and validation, not only runtime rendering and Helm values.

### Deliverables

- the Haskell route registry remains the source of truth for rendered HTTPRoutes, publication
  state, and route-aware documentation summaries
- route-oriented docs consume registry-backed rendered content or a mechanically equivalent
  generated section instead of independent handwritten route inventories
- docs lint and chart lint validate the route-aware contract from registry-backed expectations
  rather than ad hoc phrase checks
- the cleanup ledger records no remaining handwritten route-inventory or route-aware lint
  duplication once the sprint closes

### Validation

- `GET /api/publication` still reports the exact route inventory produced by the registry
- `infernix docs check` fails when a registry-owned route summary drifts from the corresponding docs
  section
- `infernix test lint` fails when route-aware lint or chart expectations diverge from the
  registry-backed route contract
- routed Harbor, MinIO, Pulsar, and demo probes continue to pass on the shared edge

### Remaining Work

None.

---

## Sprint 6.12: Assistant Workflow Canonicalization and Workflow-Helper Deduplication [Done]

**Status**: Done
**Implementation**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `src/Infernix/Workflow.hs`, `src/Infernix/Cluster.hs`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining REPO_DRY_CLEANUP follow-ons for assistant-facing root guidance and shared
workflow-helper closure.

### Deliverables

- repo-level assistant workflow doctrine moves into one canonical governed document under
  `documents/`
- `AGENTS.md` and `CLAUDE.md` become thin governed entry docs that summarize and link to that
  canonical assistant-workflow doc instead of carrying long parallel rule sets
- `src/Infernix/Workflow.hs` owns shared web-dependency readiness, npm invocation resolution,
  platform-command availability checks, and shared generated-file banner constants; cluster and CLI
  paths reuse it instead of re-declaring their own readiness probes
- the cleanup ledger no longer tracks duplicated assistant guidance or duplicated web-dependency
  readiness logic once the sprint closes

### Validation

- `infernix docs check` fails if the canonical assistant-workflow doc or the root-doc links drift
- `rg -n "webBuildToolchainPresent|ensureWebBuildDependencies" src/Infernix` shows one supported
  readiness implementation path rather than parallel cluster-local copies
- supported CLI, docs, and outer-container flows still install web dependencies through the shared
  helper

### Remaining Work

None.

---

## Sprint 6.13: Engineering Doctrine Depth and Haskell Guide Completion [Done]

**Status**: Done
**Implementation**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `documents/documentation_standards.md`

### Objective

Finish the remaining `mattandjames`-inspired doctrine-depth work so the broad engineering docs and
the Haskell guide match the stronger structure already required by
`development_plan_standards.md`.
That import is explicitly about repository governance and doctrine shape, not about adopting
`mattandjames` product-specific features or runtime assumptions.

### Deliverables

- broad governed engineering docs that define supported contracts add the stronger structure from
  `development_plan_standards.md`: `TL;DR` or `Executive Summary` when the topic is broad,
  explicit `Current Status` notes when current behavior and target direction mix, and explicit
  `Validation` sections when tests or lint prove the contract
- `documents/engineering/implementation_boundaries.md` gains an ownership matrix for Haskell,
  Python, chart, and generated surfaces together with adapter-local-versus-shared-contract type
  boundaries, instance placement rules, and module-boundary doctrine
- `documents/engineering/storage_and_state.md` gains an owner or durability table plus
  failure-mode, rebuild, and cleanup rules for durable and derived state
- `documents/engineering/portability.md` explicitly separates portable platform invariants from
  local harness detail and names which differences are supported product contract versus substrate
  implementation detail
- `documents/engineering/testing.md` keeps the canonical testing doctrine in the stronger
  structure and explicitly calls out preflight expectations, unsupported paths, and per-layer
  validation obligations
- `documents/development/haskell_style.md` points directly at `src/Infernix/Lint/HaskellStyle.hs`,
  separates repository hard-gate inputs from editor-only guidance, and adds review doctrine for
  module shape, function shape, effect-boundary clarity, and typed control flow
- the plan states explicitly that this `mattandjames`-derived follow-on imports repository
  governance, CLI, launcher-boundary, and doctrine-structure practices only; it does not adopt
  offline-browser or Keycloak flows, a single-runtime `llama-server` model, IndexedDB-specific
  docs, checked-in generated PureScript policy, or a container-only execution rule
- `src/Infernix/Lint/Docs.hs` enforces the required broad-doctrine sections for the docs whose
  structure is part of the supported contract

### Validation

- `infernix docs check` fails when the named doctrine docs lose their required
  summary-or-current-status-or-validation structure or contradict their enforced metadata contract
- `infernix test lint` passes with the deeper doc structure and Haskell-guide references in place
- `cabal test infernix-haskell-style` remains the implementation-aligned
  Haskell style gate described by the guide

### Remaining Work

None.

---

## Sprint 6.14: Monitoring Stance Resolution and Final Doctrine Closure [Done]

**Status**: Done
**Implementation**: `documents/README.md`, `documents/engineering/testing.md`, `chart/values.yaml`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/README.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Resolve the supported monitoring stance explicitly and remove the dormant monitoring placeholder
from the supported contract.

### Deliverables

- the repository carries one explicit supported-contract decision for monitoring instead of a
  dangling placeholder
- Monitoring is not a supported first-class surface.
- governed docs and the plan say so explicitly, the dormant `victoria-metrics-k8s-stack` value is
  removed from repo-owned `chart/values.yaml`, the Haskell cluster renderer keeps only an explicit
  disabled upstream Pulsar override so generated Helm values cannot imply monitoring support, and
  the cleanup is recorded in `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
- the docs index and system component inventory point at the chosen monitoring stance so readers do
  not infer support from leftover config alone
- `src/Infernix/Lint/Docs.hs` checks that the governed docs, plan docs, and chart values stay
  aligned on the unsupported monitoring stance

### Validation

- `infernix docs check` fails if the plan, docs index, and unsupported-surface statement diverge
- `infernix docs check` fails if dormant monitoring configuration returns to `chart/values.yaml`
- the cleanup ledger records the retired monitoring-stack placeholder

### Remaining Work

None.

---

## Sprint 6.15: Validation Warning Hygiene For PureScript And Playwright [Done]

**Status**: Done
**Implementation**: `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`, `src/Infernix/CLI.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/development/purescript_policy.md`

### Objective

Remove the known non-failing warning noise from the supported web-validation path so `test unit`,
`test e2e`, and `test all` stay future-proof and produce clean supported output.

### Deliverables

- the PureScript unit suite no longer relies on deprecated `runSpec`
- the supported Node-based PureScript test runner preserves non-zero exits without relying on the
  deprecated `runSpec` or `runSpecT` entrypoints
- the Playwright matrix launcher sanitizes its child-process environment so supported runs do not
  pass both `NO_COLOR` and `FORCE_COLOR`
- the Apple host-native containerized Playwright path avoids forwarding conflicting `NO_COLOR` and
  `FORCE_COLOR` values into the executor
- the governed testing docs describe the supported runner and env-sanitization posture for the web
  test path

### Validation

- `infernix test unit` passes without the PureScript `runSpec` deprecation warning
- `infernix test e2e` passes without the Node warning about `NO_COLOR` being ignored because
  `FORCE_COLOR` is set
- `infernix test all` continues to pass with the warning cleanup in place

### Remaining Work

None.

---

## Sprint 6.16: Residual Canonical-Home and Workflow-Helper Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `documents/engineering/testing.md`, `documents/development/testing_strategy.md`, `documents/README.md`, `src/Infernix/Workflow.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Lint/Docs.hs`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/engineering/testing.md`, `documents/development/testing_strategy.md`, `documents/README.md`, `documents/architecture/runtime_modes.md`, `documents/documentation_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Close the last residual DRY and canonical-topic gaps surfaced by the repo review so the runtime
model, testing doctrine, and shared workflow-helper contract stop overclaiming closure.

### Deliverables

- the root README uses the same honest runtime-language contract as the governed docs and plan:
  one Apple split-executor lane plus two containerized Linux lanes
- `documents/engineering/testing.md` remains the sole canonical testing doctrine, and
  `documents/development/testing_strategy.md` is reduced to supporting operator-detail guidance
  instead of a second authoritative canonical validation surface
- the obsolete root-level `HASKELL_CLI_TOOL.md` imported-doctrine note is removed so CLI,
  style-guide, generated-section, and non-adoption guidance lives only in governed documents and
  implementation-owned registries
- `src/Infernix/Workflow.hs` owns the demo-config generated-banner constant and
  `src/Infernix/DemoConfig.hs` consumes that shared literal instead of keeping a parallel copy
- docs lint and the cleanup ledger both record the closure so those stale guidance or duplicate
  helper surfaces do not quietly return

### Validation

- `infernix docs check` fails if the governed testing-doc metadata or purpose text reintroduce a
  second canonical testing home or if the root runtime-language contract drifts from the governed
  honest-runtime model
- `infernix test unit` continues to pass once demo-config generation and decoding consume one
  shared banner literal
- `infernix test lint` continues to pass after the ledger and docs-lint rules are updated for the
  final canonical-home cleanup

### Remaining Work

None.

---

## Sprint 6.17: Residual Compatibility-Shim Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Cache.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `documents/development/frontend_contracts.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Retire the last compatibility shims that keep obsolete result, generated-contract, and helper-registry
state alive in supported code paths so Phase 6 can close without hidden cleanup work.

### Deliverables

- `src/Infernix/Runtime.hs` and `src/Infernix/Runtime/Cache.hs` read only the supported
  protobuf-backed inference-result and cache-manifest files and stop accepting retired
  `*.state` fallbacks
- `src/Infernix/CLI.hs` stops deleting the retired `web/src/Infernix/Web/Contracts.purs` path
  during contract generation, leaving `web/src/Generated/Contracts.purs` as the only supported
  generated frontend-contract output
- `src/Infernix/Cluster.hs` stops removing the retired `infernix-bootstrap-registry` container and
  `./.build/kind/registry/localhost:30001` namespace as part of supported Harbor-first bootstrap
- unit, integration, and docs validation cover the shim-free behavior, and the cleanup ledger
  records those surfaces as fully closed

### Validation

- `infernix test unit` fails if runtime result IO, cache-manifest reloads, or PureScript
  contract generation still depends on the retired `*.state`, `default.state`, or
  `web/src/Infernix/Web/Contracts.purs` compatibility paths
- `infernix test integration` fails if the supported cluster bootstrap flow still depends on the
  retired helper-registry cleanup shims
- `infernix docs check` fails if the plan, cleanup ledger, or supporting docs overclaim full
  closure before those compatibility surfaces are removed

### Remaining Work

None.

---

## Sprint 6.18: Remaining Broad Engineering-Doc Structure Closure [Done]

**Status**: Done
**Implementation**: `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `documents/documentation_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Close the remaining doctrine-depth gap for broad engineering contract docs so the plan stops
overclaiming full structure closure and `infernix docs check` enforces the same stronger shape
consistently across the remaining governed engineering surfaces.

### Deliverables

- `documents/engineering/build_artifacts.md` adds the stronger broad-doctrine structure expected
  by `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `documents/engineering/docker_policy.md` adds the stronger broad-doctrine structure expected by
  `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `documents/engineering/edge_routing.md` adds the stronger broad-doctrine structure expected by
  `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `src/Infernix/Lint/Docs.hs` extends its document-structure rules so `infernix docs check`
  enforces the required broad-doctrine sections for those remaining engineering docs
- the plan and governed docs claim broader engineering-doc structure closure only with the
  required docs and lint rules in place

### Validation

- `infernix docs check` fails if `documents/engineering/build_artifacts.md`,
  `documents/engineering/docker_policy.md`, or `documents/engineering/edge_routing.md` lose the
  required broad-doctrine sections
- `infernix docs check` fails if the plan or governed docs overclaim doctrine-depth closure
  without the required structure and lint enforcement
- `infernix test lint` continues to pass with the broadened docs-lint structure rules in place

### Remaining Work

None.

---

## Sprint 6.19: Single-Substrate Validation Closure and Simulation Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `web/test/run_playwright_matrix.mjs`, `docker/linux-substrate.Dockerfile`, `test/integration/Spec.hs`, `test/unit/Spec.hs`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md`, `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`, `DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `documents/engineering/testing.md`, `documents/engineering/portability.md`, `documents/engineering/edge_routing.md`, `documents/reference/cli_reference.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Make every supported test command exercise only the built and deployed substrate, remove
simulation from the supported runtime and validation contract completely, and describe integration
and E2E ownership in the final `.dhall`-driven terms.

### Deliverables

- `infernix test integration`, `infernix test e2e`, and `infernix test all` exercise only the
  substrate encoded in the generated `.dhall`
- the supported default test story no longer runs a cross-substrate Apple or CPU or GPU matrix from
  one invocation
- the comprehensive model, format, and engine matrix in `README.md` is the authoritative
  integration-test coverage ledger
- one integration suite traverses those README rows or references, reads the active substrate from
  `.dhall`, chooses the corresponding engine binding for each supported row, and carries at least
  one assertion for every such row
- the repository does not maintain separate integration suites per substrate; substrate choice
  happens only through the generated `.dhall`
- Apple host-native `test integration` is launched directly from the host CLI, validates the
  cluster daemon, and manages the host inference daemon for the duration of the test when that
  daemon is needed
- Apple host-native `test e2e` is launched from the host CLI while the actual Playwright executor
  runs through `docker compose run --rm playwright` against the dedicated `infernix-playwright:local`
  image
- Linux substrate test commands all run through `docker compose run --rm infernix infernix ...`,
  and those flows do not manage a host daemon because fan-in, batching, inference, and fan-out all
  run from cluster daemons
- Playwright remains substrate-agnostic at the browser layer: the browser suite does not branch on
  substrate id or engine family, and it relies on `infernix-demo` to read `.dhall` and dispatch
  the correct engine behind the routed demo API
- test results report the built substrate unambiguously and never imply matrix-wide coverage they
  did not execute
- supported runtime and validation code carry no simulated cluster, route, transport, or generic
  inference-success fallback behavior on the supported path; inference assertions go through the
  typed adapter harness selected by the active substrate file
- supported Linux bootstrap entrypoints restage the active substrate file before lifecycle and
  test commands so lane switches cannot reuse a stale staged payload

### Validation

- Apple host-native `test all` reports `apple-silicon` only, validates the cluster daemon, starts
  the host inference daemon as needed, and delegates Playwright execution to the compose-driven
  `playwright` service without changing the reported substrate
- Linux `test all` reports only the built Linux substrate and runs entirely through the outer
  container launcher
- for any given built substrate, integration validation fails if a README row or reference whose
  substrate column names a real engine is not covered by at least one integration assertion using
  the engine selected from `.dhall`
- routed tool-route validation fails if Harbor, MinIO, or Pulsar probes succeed only through the
  direct `infernix-demo` compatibility payloads instead of the real Gateway-backed upstream
  surfaces
- E2E validation fails if browser-side test code branches on substrate id or engine family instead
  of relying on the demo app's `.dhall`-driven dispatch
- docs and test output fail if validation still claims Apple, CPU, and GPU coverage from one
  default matrix invocation or keeps simulation in the supported contract

### Remaining Work

None.

---

## Sprint 6.20: Haskell Style Toolchain Compatibility Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Lint/HaskellStyle.hs`, `docker/linux-substrate.Dockerfile`, `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`
**Docs to update**: `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`, `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Restore the supported Haskell style gate on the governed bootstrap surfaces now that the current
`ormolu` and `hlint` releases still target `ghc-9.12` while the project build and runtime
toolchain have moved to `ghc-9.14.1`.

### Deliverables

- `src/Infernix/Lint/HaskellStyle.hs` bootstraps `ormolu` and `hlint` with a dedicated compatible
  formatter toolchain instead of assuming the project compiler can build those tools
- the Linux substrate image carries whatever additional formatter-toolchain prerequisite the
  supported `bootstrap/linux-cpu.sh test` and `bootstrap/linux-gpu.sh test` surfaces need so the
  governed runtime path does not redownload that compiler on every ephemeral container run
- the Haskell-style, CLI-reference, testing, and Docker-policy docs describe the final
  formatter-toolchain rule honestly instead of claiming the style gate uses the project compiler
- the plan and component inventory stop overclaiming full lifecycle rerun closure before the
  supported `linux-cpu` and `linux-gpu` `test` surfaces pass again

### Validation

- `bootstrap/linux-cpu.sh test` passes on the supported outer-container path
- `bootstrap/linux-gpu.sh test` passes on the supported outer-container path
- `infernix lint docs` fails if the Haskell-style, CLI-reference, testing, or Docker-policy docs
  drift from the implemented formatter-toolchain contract

### Remaining Work

None.

---

## Sprint 6.21: Linux Bootstrap Determinism Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `compose.yaml`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md`
**Docs to update**: `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Close the last Linux bootstrap determinism gap by persisting the supported Helm dependency archive
cache across fresh outer-container invocations, removing the Docker Hub-backed MinIO OCI
indirection from that cache-fill path, and repairing the known stale retained Pulsar or
ZooKeeper epoch mismatch without requiring manual lane cleanup.

### Deliverables

- the supported Linux outer-container launcher bind-mounts a reusable host cache for
  `chart/charts/` so fresh `docker compose run --rm infernix ...` invocations can reuse the same
  chart dependency archives
- `src/Infernix/Cluster.hs` stops relying on `helm dependency build` to discover the MinIO chart
  through Docker Hub-backed OCI metadata and instead hydrates the governed archive cache with the
  supported direct MinIO tarball URL together with the remaining top-level chart archives
- `cluster up` detects the known stale retained Pulsar or ZooKeeper epoch mismatch, resets only
  the retained Pulsar claim roots for the affected runtime lane, and retries once so governed
  reruns do not depend on manual local cleanup
- the governed local-development, Docker-policy, and plan docs describe the reusable chart-archive
  cache honestly instead of implying every outer-container rerun reconstructs the same dependency
  bundle from the network, and the storage plus bootstrap docs record the targeted Pulsar repair
  path as explicit durability repair rather than cache cleanup
- the final governed `linux-cpu` and `linux-gpu` bootstrap lifecycle reruns pass without depending
  on a cached Docker Hub OCI allowance for the MinIO chart or manual Pulsar state cleanup

### Validation

- `bootstrap/linux-cpu.sh doctor`, `build`, `up`, `status`, `test`, and `down` pass on the
  supported outer-container path
- `bootstrap/linux-gpu.sh doctor`, `build`, `up`, `status`, `test`, and `down` pass on the
  supported outer-container path, including the targeted Pulsar repair path when stale retained
  ZooKeeper epoch state is present
- `infernix lint docs` fails if the governed local-development, Docker-policy, storage, bootstrap,
  or plan docs drift from the supported Linux bootstrap determinism contract

### Remaining Work

None.

---

## Sprint 6.22: Apple Bootstrap Lifecycle Closure [Done]

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/common.sh`, `src/Infernix/CLI.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Python.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Workflow.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`, `docker/playwright.Dockerfile`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/assistant_workflow.md`, `documents/development/local_dev.md`, `documents/development/python_policy.md`, `documents/development/testing_strategy.md`, `documents/engineering/docker_policy.md`, `documents/engineering/portability.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the remaining Apple clean-host lifecycle gaps so the governed stage-0 entrypoint can carry a
supported Apple host through first-run tool activation, host prerequisite reconciliation,
cluster-backed validation, and teardown without relying on the earlier rerun workaround or
substrate-mismatched compatibility shims.

### Deliverables

- `bootstrap/apple-silicon.sh` stops depending on ambient `PATH` side effects to discover freshly
  installed ghcup-managed tools in the same process and instead resolves or verifies the selected
  `ghc`, `cabal`, and Homebrew `protoc` executables explicitly before direct host build handoff
- shared bootstrap helper logic defines the restartable-entrypoint rule explicitly: same-process
  tool installs continue only after the bootstrap verifies command resolution and version, while
  new-shell or reboot requirements stop with a rerun instruction for the same bootstrap command
- Apple host prerequisite reconciliation can install or verify Homebrew `python@3.12`, a
  user-local Poetry bootstrap, Node.js, and the supported Colima profile on demand when Apple
  lifecycle or adapter-validation paths need them
- Apple Kind lifecycle code no longer relies on unsupported host bind-mount ownership assumptions,
  no longer preloads unsupported bootstrap images onto Kind nodes on the Apple lane, and keeps the
  routed demo API aligned with the active staged runtime mode during routed validation
- routed Apple Playwright validation probes publication readiness from the host on
  `127.0.0.1:<edge-port>` but runs the browser container on the private Docker `kind` network
  against the Kind control-plane DNS on port `30090`, so the Apple lane no longer depends on
  `host.docker.internal`
- the dedicated Playwright image no longer bakes a conflicting `NO_COLOR` default back into the
  routed E2E lane
- the governed local-development, portability, Python-policy, Apple runbook, cluster-bootstrap,
  assistant-workflow, and root orientation docs describe the implemented Apple lifecycle contract
  instead of the older rerun workaround or built-in-Python bootstrap story
- the supported Apple clean-host validation lane closes without a second manual invocation after
  the first ghcup-managed `cabal 3.16.1.0` install

### Validation

- on a clean Apple Silicon host with Homebrew plus ghcup present,
  `./bootstrap/apple-silicon.sh build` reaches direct Cabal handoff on the first invocation after
  it installs or selects `cabal 3.16.1.0`
- the supported Apple lifecycle rerun closes through
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down`
- on May 11, 2026, the supported Apple lifecycle reran cleanly through
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down`
- the Apple bootstrap fails fast with actionable messages if the resolved ghcup-managed toolchain,
  Homebrew `protoc`, or supported Colima profile still cannot be used in the current process
- the supported Apple routed Playwright lane passes without timing out on
  `host.docker.internal`, and the later Playwright image rebuild does not reintroduce the prior
  `NO_COLOR`/`FORCE_COLOR` warning conflict
- `infernix lint docs` fails if the governed local-development, Python-policy, portability, or
  runbook docs drift from the implemented Apple lifecycle contract

### Remaining Work

None.

---

## Sprint 6.23: False-Negative Validation Doctrine and Documentation Closure [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/ProcessMonitor.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Close the doctrine gap that lets slow lifecycle convergence be misreported or abandoned as a hard
failure.

### Deliverables

- the governed testing and runbook docs distinguish hard failure from long-running convergence that
  is still making progress in Docker, Harbor, Kind-worker preload, or teardown data-sync steps
- the supported validation doctrine uses inactivity-aware language instead of elapsed-wall-time
  language alone when it describes lifecycle failure classification
- Apple and cluster runbooks describe cold-versus-warm expectations and name the concrete
  first-run phases that can take minutes without emitting steady log lines
- CLI reference docs describe the supported status or progress surfaces operators use before
  concluding that a lifecycle action actually failed
- the plan, runbooks, and testing docs cite the May 13, 2026 Apple lifecycle investigation and
  the May 14, 2026 split-topology rerun as proof points for the supported false-negative doctrine
  on the current worktree

### Validation

- `infernix lint docs` fails if the testing doctrine, Apple runbook, cluster runbook, or CLI
  reference docs drift from the supported false-negative classification contract
- the plan and governed docs describe the same long-running lifecycle phases and the same operator
  interpretation rules
- the supported Apple bootstrap lifecycle reruns cleanly through `./bootstrap/apple-silicon.sh doctor`,
  `build`, `up`, `status`, `test`, and `down` while `cluster status` reports active progress
  fields during the in-progress `up` and `down` windows
- the supported validation harness can now report timeout-while-still-progressing distinctly from
  hard lifecycle failure because the lifecycle surface exposes active phase and heartbeat data

### Remaining Work

None.

---

## Sprint 6.24: Harbor Publication Retry Hardening [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster/PublishImages.hs`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the transient Harbor Docker-push failure mode exposed by the supported Apple lifecycle when
large chart images briefly reset the registry connection during publication.

### Deliverables

- Docker pushes wait for Harbor registry readiness before every push attempt
- Harbor image publication now uses eight bounded push attempts with capped retry backoff
- a failed push still exits successfully when the expected tag is already present or a registry
  pull proves the content became available despite the client-side push failure
- plan, testing, and runbook docs record the May 13, 2026 Apple lifecycle proof point with the
  current steady-state pod count and the supported retry interpretation

### Validation

- `PATH=/Users/matt/.ghcup/bin:$PATH /Users/matt/.ghcup/bin/cabal test infernix-unit` passes
- `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down` pass on May
  13, 2026 after the retry hardening
- the full `./bootstrap/apple-silicon.sh test` lifecycle exercises the large Pulsar Harbor
  publication path, integration coverage, routed Playwright E2E, retained-state replay, and final
  cluster teardown successfully
- final `./bootstrap/apple-silicon.sh status` reports `clusterPresent: False`,
  `lifecycleStatus: idle`, and `lifecyclePhase: cluster-absent`

### Remaining Work

None.

---

## Sprint 6.25: Cluster-Daemon and Apple Host-Inference Split [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Service.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Runtime/Pulsar.hs`, `chart/templates/deployment-service.yaml`, `chart/values.yaml`, `infernix.cabal`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md`, `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`, `DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/testing_strategy.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/portability.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `documents/tools/pulsar.md`

### Objective

Clarify and implement the final daemon-role contract: a cluster `infernix service` daemon always
exists, while the substrate decides whether inference runs in that cluster daemon or in a
same-binary host daemon fed by Pulsar batches.

### Deliverables

- `cluster up` deploys cluster `infernix service` daemons for `apple-silicon`, `linux-cpu`, and
  `linux-gpu`
- cluster daemon replicas can scale across nodes with anti-affinity, and the plan permits multiple
  cluster daemons in multi-node topologies
- on `linux-cpu` and `linux-gpu`, cluster daemons read from Pulsar, perform fan-in and batching,
  execute inference, and publish fan-out results
- on `apple-silicon`, cluster daemons read from Pulsar, perform fan-in and batching, publish
  inference batches to a dedicated host-consumed Pulsar topic, and fan out completed results
- same-binary host daemons on Apple read host-role `.dhall`, connect to Pulsar through the supplied
  connection details, consume the configured batch topic, execute Apple-native inference, and
  publish results back through the configured result path
- in a multi-node Apple topology, each node may run one host inference engine while the cluster
  daemon set remains responsible for shared fan-in, batching, and fan-out
- the staged `.dhall` distinguishes substrate, daemon role (`cluster` or `host`), host Pulsar
  connection details, and host batch topics instead of treating Apple host execution as absence of
  a cluster daemon
- publication and browser-visible metadata distinguish cluster daemon location from inference
  executor location, so `daemonLocation` no longer implies that Apple lacks a cluster daemon
- Pulsar-owned topics, exclusive subscriptions, acknowledgements, and negative acknowledgements
  form the ownership boundary for clean fan-in, batching, inference, and fan-out
- legacy plan language that says Apple `cluster up` does not deploy `infernix-service` is removed

### Validation

- `infernix test unit` proves that `apple-silicon` retains a cluster service claim and renders both
  cluster-role and host-role daemon metadata
- `infernix test integration` proves that `apple-silicon` deploys cluster `infernix-service`,
  starts the host inference daemon when needed, moves batches through the configured Pulsar topic,
  and completes routed inference through the split executor
- Linux integration still proves that `linux-cpu` and `linux-gpu` complete fan-in, batching,
  inference, and fan-out from cluster daemons without managing a host daemon
- routed E2E verifies that the browser-visible publication payload reports the cluster daemon and
  Apple host inference executor distinctly
- docs lint fails if the plan or governed docs describe Apple cluster-daemon absence as the final
  contract
- `PATH=/Users/matt/.ghcup/bin:$PATH /Users/matt/.ghcup/bin/cabal test infernix-unit` passes
- `PATH=/Users/matt/.ghcup/bin:$PATH /Users/matt/.ghcup/bin/cabal test infernix-haskell-style`
  passes
- `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
  `status` pass on May 14, 2026 on the split topology
- the full `./bootstrap/apple-silicon.sh test` lifecycle exercises the Apple host-batch topic,
  the host daemon, every active generated catalog entry, routed Playwright, repeated retained-state
  cluster teardown and bring-up, and final cluster teardown successfully

### Remaining Work

None.

---

## Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - root-document metadata contract and canonical-home markers
- `documents/engineering/build_artifacts.md` - generated-artifact locations, build-root rules, and derived-output validation expectations
- `documents/engineering/edge_routing.md` - route-registry ownership, generated route summaries, and route-aware validation expectations
- `documents/engineering/testing.md` - canonical testing doctrine, core principles, preflight expectations, unsupported paths, and per-layer validation obligations
- `documents/development/testing_strategy.md` - operator workflow, matrix selection, and test-entrypoint details
- `documents/development/haskell_style.md` - hard gates, review guidance, direct enforcement-model pointer, repo-hard-gate versus editor-only guidance split, and fail-fast rule
- `documents/development/chaos_testing.md` - HA failure and recovery coverage
- `documents/development/assistant_workflow.md` - canonical repository-level assistant workflow doctrine for governed root entry docs
- `documents/engineering/implementation_boundaries.md` - ownership matrix, adapter-local versus shared-contract types, instance placement, and module-boundary rules
- `documents/engineering/portability.md` - portable invariants versus substrate-specific detail, plus explicit current-status and validation sections where target direction still appears
- `documents/engineering/storage_and_state.md` - owner or durability table, failure-mode rules, and cleanup contracts
- `documents/architecture/runtime_modes.md` - daemon-role split, Apple cluster-to-host batch handoff, and host-role `.dhall` fields
- `documents/engineering/model_lifecycle.md` - batch ownership and fan-in/fan-out runtime contract
- no `documents/engineering/monitoring.md` exists while monitoring remains unsupported; create it
  only if monitoring becomes a supported first-class surface in a later change
- `documents/operations/cluster_bootstrap_runbook.md` - test prerequisites and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations and cold-start lifecycle timing doctrine
- `documents/tools/postgresql.md` - PostgreSQL operator readiness and failover rules
- `documents/tools/pulsar.md` - request, batch, and result topic ownership for cluster and host daemons
- `documents/engineering/docker_policy.md` - Colima-only Apple Docker guidance and minimal Linux host prerequisites
- `documents/development/python_policy.md` - Poetry bootstrap boundary for Apple hosts

**Product or reference docs to create/update:**
- `README.md` - orientation layer with governed root-document metadata and canonical-home links
- `AGENTS.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `CLAUDE.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/cli_surface.md` - short command-family overview that links to the canonical CLI reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations and active-substrate catalog behavior
- `documents/reference/api_surface.md` - publication metadata that distinguishes cluster daemon and inference executor location

**Cross-references to add:**
- keep [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) aligned
  when governed root-document metadata rules or canonical-home posture change
- keep [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  aligned when command-registry ownership, shared workflow-helper closure, or CLI-reference
  derivation rules change
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when runtime-honesty wording or README-matrix interpretation changes
- keep [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
  aligned when HA claims, route assumptions, or active-substrate validation rules change
- keep [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
  aligned when lifecycle progress surfaces or long-running convergence doctrine changes
- keep [system-components.md](system-components.md) aligned when testing-doctrine ownership,
  shared-helper closure, daemon-role topology, or the supported monitoring stance changes
- keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when any pending
  route-doc, route-lint, assistant-doc, workflow-helper, testing-doc, runtime-language, or
  monitoring-surface or compatibility-shim cleanup item closes
