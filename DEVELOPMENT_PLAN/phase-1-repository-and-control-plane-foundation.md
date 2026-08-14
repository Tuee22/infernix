# Phase 1: Repository and Control-Plane Foundation

**Status**: Active — Sprints 1.1 through 1.19 are closed. Sprints 1.20 through 1.25 remain open
for Apple engine materialization and runtime evidence, the paired `linux-cpu` cohort, and the
[Wave Y](cohort-validation-waves.md) attestation. Per-lane attestation lives in
[cohort-validation-waves.md](cohort-validation-waves.md); superseded surfaces are listed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md)

> **Purpose**: Establish the canonical repository scaffold, the one-binary role topology
> (`infernix` sharing the default Cabal library exposed by the `infernix` package), the supported
> control-plane execution contexts, the substrate-selection baseline,
> generated-artifact hygiene, and the repository ownership rules that later phases build on.

## Phase Status

Sprints 1.1 through 1.19 retain their recorded closure. Sprints 1.20 through 1.25 are Active.
The closed foundation work establishes the current repository scaffold, the one-binary role
topology, the typed runtime-config contract, the baked Linux launcher image, the governed
root-document posture, host-manifest materialization, and the native-only Apple Docker boundary.

**No repo-owned native source.** Repository-owned native implementation is banned in every
container, including native source embedded in Haskell string literals and compiled with Clang.
Sprint 1.20 deletes that topology and uses upstream MLX GPU execution plus coremltools device
observation, with every closed provisioning and installed-smoke operation supervised through the
all-Haskell bounded self-exec kernel. A candidate is fully hydrated, relocated, authoritatively
smoke-validated, assigned exact provenance and an actual payload-tree digest, and activated through
the fsynced sibling transaction. Evidence recorded against the removed source-compiling bridge is
historical only and is not reusable for this correction.

**Bounded-HTTP download kernel.** [Sprint 1.17](#sprint-117-bounded-http-download-kernel-done) owns
the total, typed `DownloadOutcome` ADT, the opaque `RetryAfterSeconds` newtype, the pure
`classifyDownloadStatus`, and the descriptive `User-Agent` plus bounded `responseTimeout` on the
upstream fetch. That is the substrate the Sprint 4.29 consumer fold and the Sprint 6.40
`unboundedHttpViolations` lint build on. The managed-state-transition kernels (Sprint 1.16) and this
bounded-HTTP application (Sprint 1.17) are closed under [Wave V](cohort-validation-waves.md).

**Real Apple native engines.** Sprint 1.14 established the headless Apple Metal/Core ML
materialization lane but populated it with deterministic validation-wrapper runners that loaded no
model. Sprint 1.15 replaced those wrapper payloads with real Apple native engines (Core ML, MLX,
llama.cpp/whisper.cpp Metal, CTranslate2, ONNX, Audiveris) on the existing runner contract; the
scaffold, one-binary role topology, and host-manifest contracts from Sprints 1.1–1.14 stand
unchanged. Sprint 1.15 and its Apple real-output cohort gate are closed under
[Wave L](cohort-validation-waves.md). The removed validation wrappers are tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

**Apple Docker boundary.** Sprint 1.12 removes the Colima-oriented Apple prerequisite path and
validates the already selected Docker context plus daemon architecture before Docker-backed Apple
work. The supported Apple path uses an already selected native arm64 Docker daemon, must not create
or switch Docker contexts, must not create a Colima VM, and must not use cross-architecture
emulation. The Linux CPU path supports native Linux amd64 and native Linux arm64 with no non-native
compatibility lane. The supported Apple build contract keeps the host free of Xcode and moves
Metal/Core ML materialization to typed engine-artifact manifests plus public upstream MLX/Core ML
package APIs.

**Configuration and launcher substrate.** Sprint 1.11 removes `INFERNIX_BUILD_ROOT`,
`INFERNIX_DATA_ROOT`, the `INFERNIX_COMPOSE_SUBSTRATE` / `INFERNIX_COMPOSE_DEMO_UI` runtime
fallbacks, `INFERNIX_BOOTSTRAP_YES`, the `bootstrap::prepend_path` helper, and the host-side
`.build` / `chart/charts` bind mounts. The Linux launcher selects the GPU image through the same
single `compose.yaml` service using a one-shot `LAUNCHER_IMAGE=infernix-linux-gpu:local` Compose
selector and does not forward the host-repo override. It introduces the `HostConfig` decoder type
(reflected schema; no tracked `.dhall`) as the Haskell record. The Linux bootstrap entrypoints use
the `PATH=/usr/bin:/bin` + `BASH_SOURCE` + `/etc/passwd` + hardcoded absolute-path discovery
convention, and the Linux launcher image bakes the Helm dependency archive cache at
`/opt/infernix/chart/charts/` with `/workspace/chart/charts` linked to that image-local cache for
Helm compatibility. The Apple cohort closed in [Wave A](cohort-validation-waves.md) and the CUDA
Linux cohort in [Wave C](cohort-validation-waves.md).

**Tart removal.** Sprint 1.14 removed the Sprint 1.13 Tart implementation (`hostTart`, `AppleTart`,
and Tart argument builders) from the host-tool schema and retargeted the retained
`infernix internal materialize-metal-engines` command to typed engine-artifact manifest
materialization. Sprint 1.14 stands only for its Tart-removal and manifest/install-root scope;
every bridge/source/Clang-dependent claim it once carried is superseded by Sprint 1.20.

## Current Repo Assessment

The repo matches the supported Phase 1 ownership contract: the control plane has a
Haskell command registry, the governed root docs point at canonical
`documents/` topics with explicit metadata, and the Linux launcher uses a baked image snapshot.
Lifecycle and validation commands
validate the initialized repo-root `./infernix.dhall` through binary-owned preflight and fail fast
naming `infernix init` when it is absent, while explicit internal helper invocations remain
available for direct inspection.
The Linux substrate Dockerfile also materializes a build-arg-selected copy inside the image
overlay during image build, supported Compose runs keep the Linux build root in the image
overlay rather than bind-mounting the host `./.build/` tree, and the Helm chart archive cache
lives in the image overlay at `/opt/infernix/chart/charts/`. Sprint 1.12 removes the Colima tool
field from the `HostConfig` decoder type and the matching Haskell records, removes `AppleColima`
planning and profile start/stop/restart behavior from `src/Infernix/HostPrereqs.hs`, and adds
unit-level Docker-boundary coverage for native arm64 versus non-native daemon architectures.
The Sprint 1.13 Tart helper, `hostTart` field, and
`AppleTart` prerequisite are no longer part of the current host-tool schema or prerequisite path.

## Substrate Foundation

This phase owns the baseline distinction between execution context and substrate.

- execution context answers where `infernix` runs
- the built substrate answers which README matrix engine column is active
- the supported substrate ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`

## Sprint 1.1: Canonical Repository Scaffold [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `src/Infernix/`, `compose.yaml`, `docker/`, `python/`, `web/`, `chart/`, `kind/`, `proto/`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/overview.md`

### Objective

Create the repository skeleton described in [00-overview.md](00-overview.md).

### Deliverables

- root Haskell project files: `infernix.cabal`, `cabal.project`, `app/Main.hs`, and a shared
  `src/Infernix/` library tree
- repo-owned implementation roots for `chart/`, `kind/`, `proto/`, `docker/`, `python/`, `web/`,
  `test/`, and `documents/`
- a repo-owned build doctrine that keeps host-native artifacts under `./.build/`
- a repo-owned durable-state doctrine rooted at `./.data/`
- one obvious home for service code, frontend code, cluster assets, and governed docs

### Validation

- `find . -maxdepth 2 -type d | sort` shows the planned top-level directories
- host builds materialize `./.build/infernix`
- the repo carries no competing `docs/` tree or alternate root layout contract

### Remaining Work

None.

---

## Sprint 1.2: Haskell Binary and CLI Contract Foundation [Done]

**Status**: Done
**Implementation**: `app/Main.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Service.hs`, `src/Infernix/Webapp.hs`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Make `infernix` the operator executable and the shared long-running role entrypoint, including the
demo HTTP Webapp role.

### Deliverables

- `infernix` is the only supported repo-owned long-running daemon entrypoint
- the demo HTTP host is selected through `infernix service --role webapp`
- the supported operator command families close through:
  - `service`
  - `cluster up|down|status`
  - `cache status|evict|rebuild`
  - `kubectl`
  - `lint files|docs|proto|chart`
  - `test lint|unit|integration|e2e|all`
  - `docs check`
- the executable links the default Cabal library exposed by the `infernix` package
  (declared in `infernix.cabal` without an explicit library name and depended on as `infernix`)
- cluster helpers and test helpers do not become extra supported executables

### Validation

- `./.build/infernix --help` prints the supported command families
- the CLI reference docs align with the supported surface above

### Remaining Work

None.

---

## Sprint 1.3: Dual Operator Execution Contexts [Done]

**Status**: Done
**Implementation**: `compose.yaml`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/Service.hs`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`

### Objective

Support Apple host-native operation and containerized Linux operation without creating two
different products.

### Deliverables

- Apple Silicon runs `./.build/infernix` directly on the host and shells out to host-installed
  `kind`, `kubectl`, `helm`, and Docker
- `cluster up` publishes `./.build/infernix.kubeconfig` on Apple without mutating
  `$HOME/.kube/config`, while Kind create or delete uses a transient host-local scratch
  kubeconfig first
- `cluster up` publishes `./.data/runtime/infernix.kubeconfig` on the Linux outer-container path
  so fresh launcher containers reuse the same durable cluster handle, while Kind or `nvkind`
  create or delete uses a transient execution-local scratch kubeconfig off repo-visible bind
  mounts
- `infernix kubectl ...` automatically targets the repo-local kubeconfig on supported paths
- Linux uses Compose only as a one-command launcher:
  `docker compose run --rm infernix infernix <subcommand>`
- `docker compose up` and `docker compose exec` are not supported operator workflows

### Validation

- after `./.build/infernix internal materialize-substrate apple-silicon`,
  `./.build/infernix cluster status` executes without an outer container on Apple Silicon
- after the Apple cluster is present, `./.build/infernix kubectl get nodes` works without
  manually setting `KUBECONFIG`
- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  `docker compose run --rm infernix infernix cluster status` executes on the Linux outer path
- repeated supported cluster create or delete reruns do not depend on preserving repo-local
  `infernix.kubeconfig.lock` artifacts because Kind or `nvkind` operates on a scratch kubeconfig
  and the lifecycle republishes the durable repo-local kubeconfig afterward

### Remaining Work

None.

---

## Sprint 1.4: Build Artifact Isolation and Web Build Generation Path [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `web/`, `test/haskell-style/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`

### Objective

Keep compiled artifacts out of tracked source paths, establish the web build path, and make
static quality enforceable through canonical entrypoints.

### Deliverables

- host-native Haskell builds materialize `./.build/infernix`
- outer-container staged substrate output stays under `/workspace/.build/outer-container/` inside
  the launcher image, while cabal package state and cabal's build directory stay in the image
  overlay
- explicit substrate materialization stages `infernix.dhall` under the active build
  root; `cluster up` consumes that staged file, republishes it for cluster consumers, and fails
  fast if it is absent
- the supported web build regenerates frontend contracts, runs `spago build`, and emits
  `web/dist/app.js`
- repo-owned Haskell validation enables strict compiler warnings and treats warnings as errors
- `infernix test lint` and `infernix test unit` are the canonical static-quality and unit entrypoints

### Validation

- direct Apple host builds install `./.build/infernix`; any
  `dist-newstyle/` tree is Cabal's disposable untracked build cache rather than a repo-owned
  generated source path
- `npm --prefix web run build` regenerates frontend contracts and emits `web/dist/app.js`
- `infernix test lint` fails on docs drift, warning regressions, or build-artifact policy drift

### Remaining Work

None.

---

## Sprint 1.5: Initial Substrate Identifier Baseline [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Types.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Make the substrate identifier set explicit so the later substrate-generated `.dhall` closure builds
on one clearly named contract instead of hidden flag behavior.

### Deliverables

- the canonical substrate ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate remains independent of control-plane execution context
- unsupported substrate ids fail with typed user-facing errors
- the current generated file, `cluster status`, and generated browser-contract payloads serialize
  those substrate ids under `runtimeMode` field names

### Validation

- supported host-native and outer-container workflows resolve the active substrate correctly
- `cluster status` reports the active substrate and publication targets through its current
  `runtimeMode` line
- unsupported substrate ids fail before reconcile or validation begins

### Remaining Work

None.

---

## Sprint 1.6: Haskell-Owned Control-Plane Tooling [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `src/Infernix/`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Lint/`, `src/Infernix/Python.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Retire custom control-plane Python tooling in favor of Haskell modules under the shared
`infernix` Cabal library.

### Deliverables

- chart discovery, image publication, demo-config loading, docs lint, file lint, proto lint, and
  chart lint are Haskell-owned
- `tools/` carries no repo-owned custom-logic Python on the supported path; in a clean checkout it
  may be absent entirely until generated protobuf stubs materialize under `tools/generated_proto/`
- Python remains only as the engine-adapter boundary governed by later runtime phases
- repo-owned shell is limited to the supported `bootstrap/*.sh` stage-0 host bootstrap surface

### Validation

- `git ls-files tools` reports no tracked Python control-plane helpers outside the generated
  `tools/generated_proto/` stub location
- `infernix test lint` runs Haskell-owned repo checks on the supported control-plane path

### Remaining Work

None.

---

## Sprint 1.7: Repository Hygiene and Generated-Artifact Doctrine [Done]

**Status**: Done
**Implementation**: `.gitignore`, `.dockerignore`, `src/Infernix/Lint/Files.hs`, `documents/engineering/build_artifacts.md`
**Docs to update**: `documents/engineering/build_artifacts.md`

### Objective

Stop tracking generated and disposable artifacts and make the ignore contract enforceable.

### Deliverables

- generated or disposable artifacts are ignored by repository policy:
  - `python/poetry.lock`
  - `web/spago.lock`
  - `web/package-lock.json`
  - `web/dist/`
  - `web/output/`
  - `python/.venv/`
  - everything under `tools/generated_proto/`
  - `.mypy_cache/` and `.ruff_cache/`
  - all `*.pyc` and `__pycache__/` directories
  - `web/src/Generated/`
- `.gitignore` and `.dockerignore` mirror the generated-artifact policy
- `documents/engineering/build_artifacts.md` documents what is source of truth and what is
  regenerated
- `src/Infernix/Lint/Files.hs` fails when the implemented tracked generated-source set returns:
  Python cache files, Poetry or Spago lockfiles, generated protobuf stubs, generated PureScript
  contracts, and mypy or ruff cache directories

### Validation

- `git ls-files | grep -E '(poetry\\.lock|generated_proto/|\\.pyc$|__pycache__/|spago\\.lock|web/src/Generated/|\\.mypy_cache/|\\.ruff_cache/|web/package-lock\\.json|web/dist/|web/output/|python/\\.venv/)'`
  returns nothing
- `infernix test lint` fails when the implemented tracked generated-source set is re-added to git

### Remaining Work

None.

---

## Sprint 1.8: Command Registry, Root Guidance Canonicalization, and Shared Workflow Helpers [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/Workflow.hs`, `documents/reference/cli_reference.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Establish the Haskell-owned command-registry foundation and reduce root-document drift by giving
each workflow topic one canonical home.

### Deliverables

- one Haskell command-registry foundation owns the
  supported command inventory, parser entrypoint, `--help` output, and CLI-reference lint coverage
- a shared Haskell workflow-helper foundation exists for:
  - npm invocation resolution
  - platform command availability checks
  - shared web-dependency readiness used by both CLI and cluster paths
- later hardening phases collapse helper consumers or literals within the same Phase-1 ownership
  boundary
- `documents/reference/cli_surface.md` becomes a short family overview that links to the canonical
  CLI reference instead of repeating it
- `README.md`, `AGENTS.md`, and `CLAUDE.md` carry governed metadata and canonical-home links back
  into `documents/`, and the automation entry docs stay thin by pointing at one canonical
  assistant-workflow home under `documents/`

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command families
- `infernix lint docs` fails if the canonical CLI reference drops a supported registry command line
- root-doc workflow summaries point readers at canonical `documents/` topics and carry the governed
  metadata or canonical-home markers for the thin entry-document posture

### Remaining Work

None.

---

## Sprint 1.9: Outer-Container Snapshot Launcher and Playwright Invocation Cleanup [Done]

**Status**: Done
**Implementation**: `compose.yaml`, `docker/Dockerfile`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `web/package.json`, `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`
**Docs to update**: `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `README.md`

### Objective

Move the Linux outer-container story to an image-snapshot launcher model and remove `npx` from the
supported browser workflow.

### Deliverables

- `compose.yaml` runs against a baked image snapshot and bind-mounts only `./.data/` plus the
  Docker socket
- the outer-container build root, staged substrate file, and Helm chart archive cache live in the
  image overlay; the source snapshot manifest lives separately at
  `/opt/infernix/source-snapshot-files.txt`, the Helm dependency archive cache lives at
  `/opt/infernix/chart/charts/`, and cabal-home plus the cabal builddir stay at the toolchain's
  natural in-image locations (`/root/.cabal/`, `dist-newstyle/`) and are not bind-mounted, so the
  supported CLI never overrides cabal's default builddir or `CABAL_DIR`
- the substrate image uses `tini` as its `ENTRYPOINT` for clean signal handling and zombie reaping rather than running a custom launcher wrapper script
- the repo-wide `.:/workspace` bind mount and `web/node_modules` runtime volume are removed
- operators rebuild the image when source changes instead of relying on live repo mounts
- supported Playwright workflows use `npm --prefix web exec -- playwright ...` rather than `npx`

### Validation

- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  `docker compose run --rm infernix infernix cluster status` works against the image-local build
  root and the host `./.data/` bind mount
- the launcher container sees the host `./.data/` tree and the Docker socket only; build output,
  chart archives, source, and the live `compose.yaml` stay in the image overlay
- `docker volume ls` lists no `infernix-build` or `infernix-cabal-home` named volumes
- `docker compose down -v` leaves `./.data/` intact on the host and does not manage Linux
  `.build/` state
- `docker inspect infernix-linux-cpu:local --format '{{json .Config.Entrypoint}}'` shows
  `/usr/bin/tini`, and smoke probes confirm normal launched commands run through that entrypoint
- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  a fresh `docker compose run --rm infernix infernix test unit` succeeds because cabal-home and
  the cabal builddir live at the toolchain's natural in-image locations and are not hidden by a
  host bind mount
- `rg -n 'npx playwright' README.md documents src web/package.json` returns no supported workflow references

### Remaining Work

None.

---

## Sprint 1.10: Explicit Substrate Staging, Flag Removal, and Launcher Reset [Done]

**Status**: Done
**Implementation**: `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/CLI.hs`, `docker/Dockerfile`, `compose.yaml`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace user-selected runtime-mode overrides with one staged substrate file and collapse the
launcher story onto the requested Apple-host-native and Linux-Compose doctrines.

### Deliverables

- the supported CLI removes `--runtime-mode` and all use of `INFERNIX_RUNTIME_MODE`
- the build or explicit staging flow emits one substrate file under the active build root and the
  CLI reads that file as the primary source of truth for active substrate; the Linux Dockerfile's
  image-local copy is the supported outer-container copy
- Apple host-native workflows stage `./.build/infernix.dhall` with
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
- Linux outer-container workflows stage
  `/workspace/.build/outer-container/build/infernix.dhall` inside the launcher image with
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints fail fast when the staged file is absent; focused
  `infernix lint ...` and `infernix docs check` remain substrate-file independent
- Apple Silicon remains the only supported host build path outside a container
- Linux host-native `infernix` execution is not a supported operator surface
- Linux outer-container commands use Compose as the only supported launcher for both `linux-cpu`
  and `linux-gpu`
- Apple operators do not use Compose as a user-facing launcher for ordinary CLI work; Apple
  host-native routed E2E uses host `npm exec` with the same typed fixture and awaits the Apple
  validation pass, while Linux E2E runs Playwright inside the active substrate image
- the NVIDIA-backed Linux substrate is standardized as `linux-gpu`, with the old `linux-cuda`
  naming retired as an explicit compatibility cleanup item

### Validation

- `./.build/infernix --help` no longer documents `--runtime-mode` as a runtime *override* selector;
  it survives only as a config-generation flag on `infernix init` / `infernix test init` (which
  materialize a chosen substrate's `infernix.dhall`), never as a runtime substrate override
- `./.build/infernix internal materialize-substrate apple-silicon` stages the active substrate
  without any runtime-mode flag or user-facing environment override
- supported Linux containerized commands run through `docker compose run --rm infernix infernix ...`
  without any runtime-mode flag or user-facing environment override
- supported Linux lifecycle and aggregate test commands use the substrate file materialized in the
  launcher image build root, without a host `.build` bind mount

### Remaining Work

None.

---

## Sprint 1.11: Host Manifest Materialization [Done]

**Status**: Done
**Implementation**: `src/Infernix/Substrate.hs` (extended), `src/Infernix/HostConfig.hs` (new; the `HostConfig` decoder type is the reflected schema — no tracked `.dhall`), `src/Infernix/HostTools.hs` (new helper module), `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Webapp.hs`, every `bootstrap/*.sh`, `compose.yaml`, `docker/Dockerfile`
**Docs to update**: `documents/architecture/configuration_doctrine.md`, `documents/engineering/host_tools_manifest.md`, `documents/development/local_dev.md`, `documents/engineering/portability.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the `InfernixHost.dhall` typed config record for every supported execution context
(Apple host-native, Linux launcher container) and refactor every host-tool invocation and every
filesystem-convention lookup to read from `HostConfig` instead of consuming env vars or relying on
PATH. Refactor the bootstrap shell scripts to the supported stage-zero convention
(`PATH=/usr/bin:/bin` reset, `BASH_SOURCE`/`getent passwd` discovery, hardcoded absolute paths for
the small set of pre-binary commands, delegation to the launcher binary for everything else). Move
the build-artefact tree (`./.build/outer-container/build/`) and the Helm dependency archive cache
(`./chart/charts/`) inside the launcher image so the Linux container's host-bind-mount surface
shrinks to `./.data` plus the Docker socket only.

### Deliverables

- the `HostConfig` decoder type (reflected schema) with the `ToolPaths`, `FilesystemConventions`, and
  `HostExecutionContext` records named in `documents/engineering/host_tools_manifest.md`.
- `HostConfig` typed Haskell record in `src/Infernix/HostConfig.hs`, decoded via the `dhall`
  library at every entry point (`runProductionDaemon`, `clusterUp`, `runDemoApiServer`, every
  `infernix <command>`).
- `runHostTool :: HostConfig -> HostTool -> [String] -> IO a` helper module
  `src/Infernix/HostTools.hs`. Every Haskell external-command invocation in this phase's scope
  (`src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Webapp.hs`) routes through
  this helper.
- the materialization helper (`src/Infernix/DemoConfig.hs` `materializeHostManifestFile`, wired
  into `infernix internal materialize-substrate` in `src/Infernix/CLI.hs`) also stages a host
  manifest beside the active build root — on Apple host-native this writes
  `./.build/infernix-host.dhall`; on the Linux launcher the binary's effective build root is
  `/workspace/.build/outer-container/build` so the CLI writes
  `/workspace/.build/outer-container/build/infernix-host.dhall`, while the canonical in-image host
  manifest at `/opt/infernix/dhall/InfernixHost.dhall` is baked separately by `docker/Dockerfile`
  at image-build time and read by `discoverPaths`.
- Bootstrap scripts (`bootstrap/common.sh`, `bootstrap/linux-cpu.sh`,
  `bootstrap/linux-gpu.sh`, `bootstrap/apple-silicon.sh`) refactored to the stage-zero convention:
  first line `PATH=/usr/bin:/bin`, repo root from `BASH_SOURCE`, home dir from `/etc/passwd`, every
  pre-binary command by absolute-path constant, post-binary delegation to `./.build/infernix`
  (Apple) or `/usr/bin/docker compose run --rm infernix infernix` (Linux).
- `INFERNIX_BOOTSTRAP_YES` env var replaced by `--yes` CLI flag on each bootstrap script.
- `compose.yaml` shrinks to one `infernix` service with two bind mounts (`./.data` and the
  Docker socket). The `INFERNIX_BUILD_ROOT` and `INFERNIX_HOST_REPO_ROOT` `environment:` entries
  are removed. The `./.build` and `./chart/charts` bind mounts are removed.
- `docker/Dockerfile` bakes the Helm dependency archive cache into the image at
  `/opt/infernix/chart/charts/` (replacing the previous bind-mount surface). The `ENV
  INFERNIX_BUILD_ROOT=…` directive is removed; the binary discovers its build root via
  `getExecutablePath`.
- Test fixtures in `test/unit/Spec.hs` and `test/integration/Spec.hs` stop calling `setEnv
  "INFERNIX_BUILD_ROOT"` and `setEnv "INFERNIX_DATA_ROOT"`; they pass a typed `HostConfig`
  override instead.

### Validation

- `cabal build all` clean, `infernix test lint` clean, `infernix test unit` clean.
- `grep -rn 'lookupEnv\|getEnv' src/Infernix/{Config,CLI,DemoConfig}.hs` returns zero matches.
- `grep -rn 'INFERNIX_BUILD_ROOT\|INFERNIX_DATA_ROOT\|INFERNIX_COMPOSE_SUBSTRATE\|INFERNIX_COMPOSE_DEMO_UI\|INFERNIX_BOOTSTRAP_YES' src/ bootstrap/ compose.yaml docker/` returns zero matches.
- `./bootstrap/linux-cpu.sh doctor` runs cleanly under `env -i /usr/bin/bash` (empty starting env).
- Wave C closed the Linux stage-zero bootstrap proofs on the native Linux/CUDA host:
  `env -i /usr/bin/bash ./bootstrap/linux-cpu.sh doctor` and
  `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh doctor` both pass under an empty starting env;
  `./bootstrap/linux-gpu.sh status` enters the single `compose.yaml` launcher with
  `LAUNCHER_IMAGE=infernix-linux-gpu:local` and reports the expected `linux-gpu` `cluster-absent`
  status without requiring `compose.linux-gpu.yaml`; and `./bootstrap/linux-gpu.sh build` produces
  the `infernix-linux-gpu:local` launcher image, runs the `infernix --help` smoke check through
  that launcher, and a direct `docker run --rm infernix-linux-gpu:local ...` inspection confirms
  `/workspace/chart/charts` links to `/opt/infernix/chart/charts` with the expected Helm archives
  present and no bind mount.
- Apple cohort validation closed in Wave A; CUDA Linux cohort validation closed in Wave C with
  `./bootstrap/linux-cpu.sh test` and `./bootstrap/linux-gpu.sh test` full-suite passes.
- `docker inspect <launcher-container> --format '{{json .Mounts}}'` shows exactly two mounts:
  `./.data` and `/var/run/docker.sock`.

### Remaining Work

None.

---

## Sprint 1.12: Native-Only Workflow and Apple Docker Boundary [Done]

**Status**: Done
**Implementation**: `src/Infernix/HostPrereqs.hs`, `src/Infernix/HostConfig.hs`, `src/Infernix/Config.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `docker/Dockerfile`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/assistant_workflow.md`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/engineering/host_tools_manifest.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the native-only development and validation contract executable. Apple Silicon must never
create or switch Docker contexts, create a Colima VM, or run amd64 Linux through emulation.
Docker-backed Apple work requires the operator's current Docker context to already target a
native arm64 daemon. `linux-cpu` validation belongs on native Linux amd64 or native Linux arm64.

### Deliverables

- remove the supported-path dependency on `AppleColima` and the Colima start/stop/restart
  reconciliation path from Apple prerequisite handling
- replace Apple Docker bootstrap behavior with a Docker-daemon validation step that reports the
  current Docker context and daemon architecture, then fails before cluster work if the daemon is
  absent, non-native, or unavailable in the current process
- update the `HostConfig` decoder type, host-tool manifests, and unit fixtures so Colima is not a
  required supported Apple tool
- keep Linux bootstrap and validation native-only: `linux-cpu` covers native `linux/amd64` and
  native `linux/arm64`; `linux-gpu` remains native amd64 CUDA
- keep root workflow guidance, governed docs, and this plan aligned with the implementation

### Validation

- `rg -n 'AppleColima|ensureColimaDockerReady|startSupportedColima|stopColima|colima start|colima stop' src test dhall`
  returns no supported-path matches after the cleanup lands
- `cabal test infernix-unit` covers Apple host prerequisite decoding and Docker-boundary behavior
- `infernix lint docs` passes through the active execution context
- on Apple Silicon with an already selected native arm64 Docker daemon,
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
  `status` run without creating or switching Docker contexts
- on Apple Silicon with no usable native arm64 Docker daemon, the Apple bootstrap fails with a
  prerequisite error and does not create a Docker context or Colima VM
- Wave A closed Sprint 1.12: the Apple positive native-daemon lifecycle gate and the negative
  no-daemon boundary gate both passed on Apple Silicon without creating or switching Docker
  contexts, and the native Linux amd64 `linux-cpu` outer-container regression gate
  (`./bootstrap/linux-cpu.sh test`) confirmed the Colima-removal cleanup and host-manifest schema
  change do not regress the Linux lane

### Remaining Work

None.

---

## Sprint 1.13: Apple Tart Metal-Engine Build Lane [Done]

**Status**: Done
**Historical implementation**: Superseded and removed by Sprint 1.14.
**Code-side closure**: Historical record only — the prior `tart` host-manifest field (Haskell selector `hostTart`), `AppleTart` prerequisite, Tart argument builders, and Tart-backed materialization flow are removed from the current implementation by Sprint 1.14. The retained command name now belongs to the Tart-free manifest materialization lane.
**Cohort gate**: Replaced by Sprint 1.14's headless Apple materialization gate in [Wave I](cohort-validation-waves.md).
**Implementation**: `src/Infernix/HostConfig.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `bootstrap/apple-silicon.sh`, `test/unit/Spec.hs`
**Docs to update**: `documents/engineering/host_tools_manifest.md`, `documents/operations/apple_silicon_runbook.md`, `documents/engineering/build_artifacts.md`, `documents/architecture/configuration_doctrine.md`, `documents/engineering/docker_policy.md`

### Legacy Note

This sprint records the superseded implementation. It is no longer the supported Apple
materialization target because Tart VM startup can depend on macOS Virtualization.framework
host-key state and an unlocked user login keychain. Sprint 1.14 owns the replacement path and
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) records the completed removal of
`hostTart`, `AppleTart`, and the Tart-backed `materialize-metal-engines` flow.

### Objective

Record the prior attempt to keep the Apple host free of Xcode while producing Metal and Core ML
native engine artifacts. The implementation used a `tart` macOS VM for artifacts that were assumed
to need `xcrun metal`/`metallib` or `coremlc`/`coremltools`, copied outputs to the host, and ran
them against the host Metal device.

### Deliverables

- Historical deliverables were the `hostTart` field, the `AppleTart` prerequisite, a Tart-backed
  build lane in `src/Infernix/Engines/AppleSilicon.hs`, and a retained
  `infernix internal materialize-metal-engines` command surface.
- Sprint 1.14 removes those Tart-specific implementation surfaces and keeps the command name for
  the Tart-free manifest materialization contract.

### Validation

- Historical machine-independent validation covered the former `hostTart` field, `AppleTart`
  requirement, allowlist, and pure Tart argument builders.
- Current validation belongs to Sprint 1.14's headless Apple materialization lane in
  [Wave I](cohort-validation-waves.md).

### Remaining Work

None.

---

## Sprint 1.14: Apple Headless Metal/Core ML Materialization Reset [Done]

**Status**: Done
**Code-side closure**: Closure covers Tart removal, typed manifests, atomic install-root handling, and the then-current payload topology. The repository-owned Objective-C/C/Metal bridge and Core ML smoke source described by the original Sprint 1.14 closure violate the no-native-source boundary and are deleted by Sprint 1.20. Their implementation and validation details are superseded, not a current supported architecture. The former deterministic Apple native runner payloads were separately superseded by Sprint 1.15.
**Cohort gate**: Closed for the Tart-removal reset only. The generated-bridge and Objective-C Core ML smoke evidence is invalid for Sprint 1.20 and cannot close any correction-dependent Apple claim. Fresh upstream-package Apple evidence belongs to Sprint 1.20.
**Implementation**: `documents/engineering/apple_silicon_metal_headless_builds.md`, `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/HostConfig.hs`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/build_artifacts.md`, `documents/operations/apple_silicon_runbook.md`, `documents/architecture/configuration_doctrine.md`, `documents/engineering/host_tools_manifest.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace the Sprint 1.13 Tart VM build target with a truly headless Apple materialization lane.
The replacement path must not require Tart, user keychain state, host Xcode UI flows, the offline
`metal` compiler, or request-time SwiftPM/package builds.

### Deliverables

- historically, add the fixed bridge that Sprint 1.20 later deletes as an invalid repo-owned
  native-source boundary; this deliverable is superseded and is not current architecture
- historically, add typed engine-artifact manifests for Apple native payloads under
  `./.data/engines/<adapterId>/` with digest, source reference, runtime fingerprint, entrypoint, and
  smoke-command fields. Sprint 1.20 removes those command-text fields and replaces them with the
  closed recipe/target fingerprint plus exact provenance and direct-target observations
- change Apple materialization so it writes into a temporary root, smoke-validates the manifest
  contract, and atomically renames into the final engine root
- remove `AppleTart` prerequisite reconciliation, `hostTart` as a supported host-tool field, and
  the Tart-backed `materialize-metal-engines` implementation while retaining the command as the
  new headless materialization surface
- keep full Xcode out of the host runtime path; any artifact that still truly requires full Xcode
  remains an explicit residual rather than a supported headless claim

### Validation

- unit coverage for manifest rendering, atomic install-root selection, and failure cleanup
- historical Apple cohort probe for the now-deleted bridge; superseded by Sprint 1.20
- Apple cohort validation still passes when `tart` is absent or unusable and no user
  `login.keychain-db` is unlocked
- `infernix lint docs`, `infernix lint files`, `infernix lint proto`, `infernix lint chart`,
  `infernix docs check`, and `infernix test lint` pass in the active execution context
- Wave I records the Apple materialization smoke and host engine load under the new lane

### Remaining Work

None.

---

## Sprint 1.15: Real Apple Native Engine Materialization [Done]

**Status**: Done
**Code-side closure**: Complete and validated on the Apple host. The
`infernix_emit_validation_result` validation-wrapper fabrication is deleted; generated Apple runners
preserve the full native worker contract, enforce model-cache readiness, and return only real native
engine output or non-zero failure. `llama-cpp-cli` and `whisper-cpp-cli` copy the typed
host-manifest Homebrew binaries into their content-addressed candidates and invoke only those
artifact-local Metal-capable CLIs; `ctranslate2-native`, `onnx-runtime-native`, and `mlx-native`
hydrate per-engine
Apple arm64 venvs; `coreml-native` hydrates Basic Pitch plus Apple's Core ML Stable Diffusion
pipeline; `jvm-native` downloads the pinned Audiveris macOS arm64 DMG and installs `Audiveris.app`;
`audio-basic-pitch-coreml` is package-backed; and the Core ML Stable Diffusion row uses a Hugging Face
Core ML snapshot plus an indexed native snapshot hydration path. Proven by
`./bootstrap/apple-silicon.sh build`, `./.build/infernix internal materialize-substrate apple-silicon`,
`./.build/infernix internal materialize-metal-engines`, installed runner smokes (Metal bridge, Core ML,
CTranslate2, MLX, ONNX Runtime, Audiveris), direct Core ML package imports, `./.build/infernix test unit`,
and `./.build/infernix test lint`.
**Cohort gate**: closed under [Wave L](cohort-validation-waves.md) — Apple integration and focused
routed Playwright real-output gates pass, paired with the `linux-cpu` full routed real-output gate
on a real Linux host (Haskell style, Python `check-code`, Haskell unit, generated web contracts,
full integration with all real `linux-cpu` catalog outputs and the HA/chaos tail, and routed
Playwright including the per-model browser matrix).

**Implementation**: `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/HostConfig.hs`, `python/native-runners/apple_native_runner.py`, `python/adapters/model_bootstrap.py`, `README.md`
**Docs to update**: `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/host_tools_manifest.md`, `documents/operations/apple_silicon_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the Apple native engine layer run real models, replacing the deterministic validation wrappers
materialized by Sprint 1.14.

### Deliverables

- real Apple runners (llama/whisper Metal, CTranslate2/ONNX host-wheel, Audiveris macOS, MLX, Core ML)
  on the existing runner contract; delete the validation wrappers
- indexed native snapshot hydration for multi-file Core ML model snapshots
- Apple rows stay declared-runnable on their intended engines (declarative-target); each returns real
  output or fails closed

### Validation

- Apple host integration and routed e2e pass only on real Apple inference, paired with the
  `linux-cpu` full-suite gate; the realness lint forbids any reintroduced validation wrapper

### Remaining Work

None.

---

## Sprint 1.16: Evidence and Command Kernels [Done]

**Status**: Done — the Managed-State-Transition Doctrine reopen kernels
(`Infernix.Evidence.Readiness`, `Infernix.Evidence.Lease`, `Infernix.Cluster.Subprocess`) are
code-side closed on the machine-independent gates, and the single-accelerator (apple-silicon) plus
`linux-cpu` full-suite sign-off is closed under [Wave V](cohort-validation-waves.md).
**Code-side closure**: complete — `cabal build all` (`-Wall -Werror`), `cabal test infernix-unit`
(the readiness / lease / subprocess kernel assertions), and `cabal test infernix-haskell-style`
(ormolu + hlint + cabal-format) all pass on the apple-silicon lane; `infernix lint docs` is
unaffected. No Python/native change in this sprint, so `poetry run check-code` does not apply
**Cohort gate**: closed under [Wave V](cohort-validation-waves.md) — apple-silicon plus `linux-cpu`
full-suite `test all`.
**Implementation**: `src/Infernix/Evidence/Readiness.hs`, `src/Infernix/Evidence/Lease.hs`, `src/Infernix/Cluster/Subprocess.hs`
**Blocked by**: Sprint 0.13
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase — introduce the
foundation kernel modules `Infernix.Evidence.Readiness`, `Infernix.Evidence.Lease`, and
`Infernix.Cluster.Subprocess` (`SubprocessEnv` with required `HOME`/`TMPDIR`, the `CommandOutcome`
ADT, and a bounded child-reaping `runBoundedCommand`); establish the
opaque-newtype-via-export-list discipline and enable `RankNTypes` plus surgical `LinearTypes`. The
kernels encode evidence, not hope: for every system state there is a transition and typed evidence,
and every operation that acts on that state requires the evidence. See the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `Infernix.Evidence.Readiness` and `Infernix.Evidence.Lease` foundation kernels whose evidence
  types are opaque newtypes constructed only through their own module, exported via export-list
  discipline
- `Infernix.Cluster.Subprocess` with `SubprocessEnv` requiring `HOME` and `TMPDIR`, the
  `CommandOutcome` ADT, and a bounded child-reaping `runBoundedCommand`
- the `RankNTypes` extension plus surgical `LinearTypes` enabled where the kernel discipline needs
  them. The kernels themselves use `RankNTypes` region leases, which already suffice for region
  scoping; surgical `LinearTypes` (`%1 ->`) belongs at the spend-once consumer sites owned by later
  sprints, where a spent capability must not be reused

### Validation

- `cabal build all`, `cabal test infernix-unit`, and `cabal test infernix-haskell-style` clean
- `infernix lint docs` clean, and `poetry run check-code` for any Python/native change
- the code-side gates above exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

None.

---

## Sprint 1.17: Bounded-HTTP Download Kernel [Done]

**Status**: Done — the bounded-HTTP download kernel (the total `DownloadOutcome` ADT, the opaque
`RetryAfterSeconds` newtype, the pure `classifyDownloadStatus`, and the `User-Agent` + bounded
`responseTimeout` on the upstream fetch) is code-side closed on the machine-independent gates, and
the single-accelerator (apple-silicon) plus `linux-cpu` full-suite sign-off is closed under
[Wave V](cohort-validation-waves.md).
**Code-side closure**: complete — `cabal build all` (`-Wall -Werror`),
`cabal test infernix-unit` (the `classifyDownloadStatus` classification table),
`cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, and
`infernix docs check` all pass on the apple-silicon lane. No Python/native change in this sprint, so
`poetry run check-code` does not apply.
**Cohort gate**: closed under [Wave V](cohort-validation-waves.md) — apple-silicon plus `linux-cpu`
full-suite `test all`.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`
**Blocked by**: Sprint 1.16
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — introduce
the bounded-HTTP download kernel that the coordinator model-bootstrap path consumes. A cohort run
proved the Sprint 1.16 kernels exist but were not applied at the upstream download site:
`downloadUpstreamModelToFile` sent no `User-Agent` (tripping the upstream WAF's 403), set no total
`responseTimeout`, and collapsed every non-200 into one opaque failure retried forever. The kernel
half of the fix is a total, typed outcome ADT with a required classification, encoding evidence, not
hope: "retried forever with no backoff" and "an unbounded transfer" become terms that do not
typecheck. It applies the bounded-outcome shape of
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
(the `CommandOutcome` sibling) to the upstream HTTP surface.

### Deliverables

- the total `DownloadOutcome` ADT
  (`DownloadSucceeded | DownloadRateLimited RetryAfterSeconds | DownloadTransient String |
  DownloadPermanent String`) and the opaque `RetryAfterSeconds` newtype in
  `src/Infernix/Runtime/Pulsar.hs`
- the pure, exported `classifyDownloadStatus :: Int -> Maybe Int -> DownloadOutcome` mapping an HTTP
  status plus optional `Retry-After` into that outcome: 429 or 403-with-`Retry-After` →
  `DownloadRateLimited` with a clamped backoff, 5xx → `DownloadTransient`, other non-200 →
  `DownloadPermanent`, 200 → `DownloadSucceeded`
- a descriptive `User-Agent` (`infernix-model-bootstrap/1.0`) and a bounded `responseTimeout` on the
  `downloadUpstreamModelToFile` request, so a UA-less request can no longer trip the upstream WAF and
  no transfer runs unbounded

### Validation

- `cabal build all`, `cabal test infernix-unit` (the `classifyDownloadStatus` classification table),
  `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, and
  `infernix docs check` are exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

None.

---

## Sprint 1.18: Observable Readiness — Tri-State Poll Outcome [Done]

**Status**: Done — code-side closed on the machine-independent gate set, and the
single-accelerator (apple-silicon) plus `linux-cpu` behavioral cohort sign-off closed under
[Wave W](cohort-validation-waves.md) with no remaining work. The readiness kernel gains an
observable-poll channel so a probe that could not observe a remote system can no longer launder that
fault into a definite not-ready measurement.
**Supersession note**: this sprint supersedes the two-channel Sprint 1.16 kernel step contract
(`awaitReadiness :: Deadline -> IO (Either Progress e) -> IO (Readiness e)`, whose only poll outcomes
were `Right` ready and `Left` a concrete not-ready count). That type forced a probe I/O fault to
launder itself into a fabricated count fed into the kernel's stall/ceiling accounting as ground truth —
the representable invalid state behind the retained-second-`cluster up` warm-model-cache "11/16" stall.
**Code-side closure**: complete. Landed: `PollOutcome e = Measured (Either Progress e) |
Unobservable Text` and `awaitReadinessObservable :: Deadline -> IO (PollOutcome e) -> IO (Readiness e)`
in `src/Infernix/Evidence/Readiness.hs`; an `Unobservable` poll accrues stall like a non-advancing poll
and cannot advance the running maximum, so it can neither mint a `Ready` nor deflate the observed count
— it only buys another poll within the same bounded `Deadline`. `awaitReadiness` is retained as a
behaviour-identical lift (`awaitReadinessObservable deadline (Measured <$> step)`), so the sixteen
existing count-based callers and the `budgetDeadline` poll-count exactness (hardened under
[Wave V](cohort-validation-waves.md)) are unchanged. Gate set: `cabal build all`
(`-Wall -Werror`), `cabal test infernix-unit` (a scripted `Unobservable`-then-`Measured` stream
resolves `Ready`; an all-`Unobservable` stream gives up bounded `Expired`), and
`cabal test infernix-haskell-style`. No Python/native change in this sprint.
**Cohort gate**: apple-silicon plus `linux-cpu`, closed under
[Wave W](cohort-validation-waves.md) — the behavioral proof that the retained-second-`cluster up`
warm-model-cache barrier no longer stalls at "11/16".
**Implementation**: `src/Infernix/Evidence/Readiness.hs`, `test/unit/Spec.hs`
**Blocked by**: Sprint 1.16
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and this plan

### Objective

Close the last representable invalid state in the readiness kernel: a readiness probe that reads a
remote system does not always get to observe it, and the Sprint 1.16 step contract had no channel for
"I could not measure." A transport fault was forced to become a definite `Left progress` count that the
kernel fed into stall/ceiling accounting as ground truth. Make "unobservable" a first-class poll
outcome routed to retry-within-budget, so a transient fault can never masquerade as a measurement. This
is the kernel half of the Observable-Readiness reopen; the warm-model-cache observation surface that
consumes it is [Sprint 8.8](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md).

### Deliverables

- `PollOutcome e = Measured (Either Progress e) | Unobservable Text` and `awaitReadinessObservable`
- `awaitReadiness` preserved as a `Measured`-lift of `awaitReadinessObservable`, so every existing
  caller and the `budgetDeadline` poll-count exactness are byte-identical
- `Unobservable` handling: accrue stall, never advance the running maximum, retry within the deadline;
  a budget expiry while every recent poll was unobservable rides the last real `Progress`
- unit coverage: a bounded transient-fault stream still resolves `Ready`; a persistent-unobservable
  stream gives up bounded (`Expired`)

### Validation

- `cabal build all` (`-Wall -Werror`) compiles the observable kernel with `awaitReadiness` as a lift
- `cabal test infernix-unit` covers the transient-fault-then-ready and persistent-unobservable cases
- `cabal test infernix-haskell-style` passes
- `infernix test all` on apple-silicon plus `linux-cpu` proves the warm-model-cache barrier no longer
  stalls on a retained second `cluster up` — closed under [Wave W](cohort-validation-waves.md)

### Remaining Work

None.

---

## Sprint 1.19: Execution-Plan Compiler And Capability Core [Done]

**Status**: Done — the complete source-matched machine-independent gate and the final adversarial
source review both pass
**Implementation**: `src/Infernix/ExecutionPlan.hs`, `src/Infernix/ExecutionPlan/Internal.hs`,
`src/Infernix/Runtime/Enforcer.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/Runtime/Daemon.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Substrate.hs`,
hidden configuration/routing modules, and focused unit/integration/negative-compilation suites
**Docs to update**: `documents/architecture/typed_execution_plan.md`,
`documents/architecture/bounded_inference_memory.md`,
`documents/architecture/configuration_doctrine.md`, `documents/architecture/daemon_topology.md`,
and `documents/architecture/runtime_modes.md`

### Objective

Introduce resource-indexed Haskell execution alternatives, confine raw decoded configuration, compile
the validated graph into an opaque `CompiledRuntimePlan`, and allow only package-owned live
observations to refine it into `RuntimePlan` / `ExecutableModel`. Phase 8 Sprint 8.9 owns the final
proper-union generated-Dhall wire migration.

### Deliverables

- `RawRuntimeConfig -> Either ConfigErrors CompiledRuntimePlan`
- hidden constructors for executable placements, positive quantities, resource-indexed grants, and
  enforcer plans
- coordinator routing consumes only compiled placements and daemon capabilities and returns a
  typed terminal result for requests to explicit unavailable placements; engine subscription and
  launch consume only refined runtime/executable capabilities
- routing and launch APIs cannot accept raw model/config records
- unavailable, empty-model, unknown-model, wrong-route, and malformed coordinator/engine requests
  terminate as failed results before their file source is removed or Pulsar message is acknowledged
- model-bootstrap publication consumes only an opaque plan-derived capability; the consumer
  revalidates model identity, compiled download URL, and canonical request timestamp before side
  effects
- compilation rejects cross-family reuse among coordinator-request, result,
  model-bootstrap-request, model-bootstrap-ready, and engine-route topics
- substrate Dhall emission is explicit UTF-8

### Validation

- compiler/refinement properties reject zero values, resource/enforcer mismatch, oversubscription,
  dangling placement references, unavailable live enforcers, and configured/live partition drift
- an integration-focused coordinator test proves that a request for `UnavailableModel` publishes
  `status=failed` with the compiler-produced typed `ModelMemoryLimitExceeded` and never selects an
  engine batch topic or launches a worker
- coordinator and engine tests prove empty, unknown, wrong-route, and malformed messages produce
  one terminal failed result before source removal/acknowledgement
- bootstrap tests reject model/URL/timestamp drift before download or publication side effects,
  and negative/API tests prove no raw topic publisher remains
- compiler properties reject every cross-family topic collision, and a non-ASCII substrate fixture
  round-trips through UTF-8 Dhall emission and decode
- negative compile fixtures reject coordinator routing without compiled placement/daemon authority,
  engine launch without `ExecutableModel`, and imports of hidden raw decoders or routing helpers
- machine-independent gate set passes

### Remaining Work

None.

### Closure Record

The closed construction includes:

- `MemoryGrant resource`, `MemoryCeiling resource`, `Enforcer resource`, and `EnforcedGrant
  resource` keep the resource witness aligned through the launch boundary; the superseded
  unindexed grant API in `Infernix.Types` is removed
- pure compilation produces a `CompiledRuntimePlan`; only package-owned live observations can
  refine it into `RuntimePlan` / `ExecutableModel`
- model compilation and route construction are total: every configured model is represented
  exactly once as a compiled placement or explicit `UnavailableModel`, and an unexpected graph
  inconsistency returns `ConfigErrors` rather than being filtered out
- coordinator and engine request dispatch now return terminal failed results for unavailable,
  empty-model, unknown-model, and wrong-route requests; malformed protobuf produces a typed failed
  result. File-spool sources are removed and Pulsar messages acknowledged only after that terminal
  result is written or published
- each executable placement carries its validated pool/member/topic routes, engine binding, grant,
  and live enforcer; public worker and capped-engine launch APIs require the whole
  `ExecutableModel`
- daemon compilation produces opaque `CompiledDaemon` capabilities keyed by engine member, after
  proving exact role/member coverage, location, derived topics, result topic, subscription, and
  connection mode; subscription startup consumes those capabilities
- the sanctioned runtime enforcer facade probes Apple physical-footprint and the live checked host
  partition, or Linux process-group RSS plus the exact current cgroup-v2 envelope, before
  refinement; configured/live partition drift and missing observations fail closed, and
  per-execution sampling still fails closed if the mechanism later disappears
- checked `Integer` arithmetic rejects host-partition overflow, and compilation rejects model
  ceilings that cannot be represented in the watchdog byte domain; unsupported adapter types and
  GPU-required work in the `linux-cpu` lane are also structural configuration errors
- raw Dhall decoders and topic-derivation helpers now live only in hidden package modules; exported
  config validation compiles the same plan used at startup, while the generator-facing catalog API
  remains configuration-only
- Pulsar drain/consume authority is an opaque daemon-topic capability derived from one compiled or
  refined plan; runtime, daemon, and topic can no longer be mixed independently, and engine launch
  additionally proves that the decoded model's routes contain the exact daemon member/topic pair.
  The raw topic publisher is removed. Model-bootstrap publication requires an opaque
  `ModelBootstrapRequestCapability` prepared from the compiled plan, and the consumer revalidates
  the exact model identity, compiled download URL, and canonical timestamp before any download,
  upload, or ready-event side effect. Dispatcher, result, bootstrap, and eager-staging paths derive
  their topology from the same plan
- a second adversarial pass removed `Read` from opaque grants/ceilings/partitions/footprints and
  assigns nominal roles to every resource index, so neither textual construction nor
  `Data.Coerce` can relabel evidence; strict canonical identifiers close filesystem traversal, and
  `TopicFamilyCollision` rejects reuse across coordinator-request, result,
  model-bootstrap-request, model-bootstrap-ready, and engine-route topic families
- executable engine metadata now resolves through one exact runtime-scoped allowlist and the
  compiler rejects every field drift, unknown choice, and cross-runtime choice before an engine
  binding becomes executable; generated `edgePort = 0` remains the supported unpublished sentinel
- Apple Colima observation now fails closed on missing/malformed probes and conservatively counts
  every profile not explicitly `Stopped`; Linux refinement compares live `memory.max` with the
  configured child limit plus daemon/sampler headroom rather than a particular model's smaller
  grant, and non-MiB-aligned byte limits fail closed instead of being rounded into agreement
- launch APIs derive runtime, model, and binding identity only from `ExecutableModel`, reject a
  mismatched request model before side effects, and no longer accept a caller-controlled runtime
- substrate materialization encodes the generated Dhall text with explicit UTF-8 before writing
  bytes, preserving non-ASCII operator/model metadata
- the production library and executable build are clean under `-Wall -Werror`, and the complete
  source-matched gate passed after the final refinement and Pulsar-capability coherence edits

Closure evidence on the Apple Silicon development host:

- `cabal build all test:infernix-integration`
- the unit, internal-boundary, compile-fail, and Haskell-style suites; compile-fail coverage passed
  all 4 positive fixtures and all 27 negative fixtures
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
- the installed binary's `lint files`, `lint docs`, `lint chart`, `lint proto`, and `docs check`
- Python `check-code`
- web contract generation, unit tests, `spago build`, and bundle generation, including all 83/83
  web unit tests
- `git diff --check`
- a final adversarial source review with no remaining Phase 1 production blocker

Phase 4 Sprint 4.32 owns the ordered substrate implementation/behavioral proof after Phase 2
closes; NVIDIA per-process accounting remains fail-closed until its later GPU phase.

---

## Sprint 1.20: Remove Embedded Apple Native Source [Active]

**Status**: Active — validation-only. The defect that blocked the materializer is closed in current
source: the Audiveris invocation now declines JavaCPP symbolic-link creation, so the extraction cache
holds no symlink, the sealed payload is relocation-invariant, and neither smoke can perturb it. The
cache-link normalization subsystem that existed to repair the link is deleted rather than extended.
Apple engine rematerialization, the fixed production Audiveris cancellation and installed-Python
source-isolation commands, the installed authoritative smokes, the Apple cohort, and the paired
source-matched `linux-cpu` cohort remain open.
**Cohort gate**: [Wave Y](cohort-validation-waves.md).

**Implementation**: `src/Infernix/Engines/AppleSilicon.hs`,
`src/Infernix/Engines/AppleSilicon/Internal.hs`, `src/Infernix/Engines/Artifact.hs`,
`src/Infernix/Engines/Provisioning.hs`, `src/Infernix/Engines/Provisioning/Internal.hs`,
`src/Infernix/Cluster/Subprocess.hs`, `python/native-runners/apple_native_runner.py`,
`test/artifact-transaction/Spec.hs`, compile-fail fixtures, and Haskell-style enforcement
**Docs to update**: `documents/engineering/apple_silicon_metal_headless_builds.md`,
`documents/engineering/build_artifacts.md`, `documents/development/haskell_style.md`,
`documents/architecture/managed_state_transitions.md`, root workflow mirrors, and this plan

### Machine-Independent Apple Materializer Fixture Scope

The machine-independent Apple materializer boundary fixture exercises the same private indexed
runner as production, but its fixed actions write synthetic marker files. It proves transition
ordering, primary-failure-preserving cleanup, and lock release only; it is not evidence that actual
hydration, relocation, smoke, activation, or Audiveris detach cleans up under cancellation. The
private production cancellation hook is a fixed first-order `PauseAfterAudiverisMount` action
carrying only synchronization cells, so it cannot capture writer authority or inject an arbitrary
effect. A fresh Darwin cohort must cancel the real Audiveris materializer through that hook and
prove exact mount recovery, candidate cleanup, prior-root preservation, and lock reacquisition
before the full-materializer obligation can close.
The default `infernix-apple-materializer` suite remains machine-independent. Its explicit
`--darwin-production-audiveris-cancellation` mode discovers the configured repository paths,
requires a current valid prior `jvm-native` root and a clean candidate boundary, waits on the exact
post-publication mount checkpoint, cancels without a timing sleep, and then validates candidate,
mount, and activity absence, the unchanged complete prior manifest/payload, and immediate
reacquisition of all four Apple provisioning lifecycle locks. The mode is implemented but has not
been run; it is not evidence until the fresh Darwin command named in `Remaining Work` exits green.

### Objective

Delete every repo-owned Objective-C/C/Metal source literal and every `.h`/`.m`/`.c` materialization
or Clang compilation path. Preserve the headless Apple engine-artifact manifest and fail-closed
runtime-smoke contract through public APIs whose native implementation is owned by upstream
packages, without direct FFI, inline native source in another language, or a renamed unsafe bridge.

### Deliverables

- remove `appleMetalBridgeHeader`, `appleMetalBridgeSource`, `appleMetalBridgeSmokeSource`,
  `coreMlRunnerSmokeSource`, and their source-file writers/compiler scripts
- replace the fixed repo-owned bridge artifact with a typed smoke that performs a real bounded
  operation through an upstream-owned Apple runtime package already admitted by the engine lane
- keep smoke/materialization commands generated from closed adapter identities, explicit tool
  paths, explicit arguments, bounded provisioning authority, and typed artifact manifests
- retire every generated `bin/*` shell wrapper and the stale wrapper-shaped manifest contract;
  launch each native CLI, interpreter, or JVM target directly through the Haskell helper kernel
- bind Linux absolute image targets and every interpreter/library/script closure to
  descriptor-derived exact immutable-image observations; a catalog path string or recipe-policy
  fingerprint is not executable-byte evidence
- keep `ProvisioningGrant s` nominal and opaque and `ProvisioningSession s result` indexed under
  `withProvisioningGrant`'s rank-2 region. Its constructor/interpreter and all raw provisioning
  command constructors remain hidden; the public Apple facade exposes no raw per-artifact installer
- compile the closed Poetry install/setup, protobuf generation, Python probing/venv/package,
  Audiveris image, installed-smoke, and provenance operations through the self-exec
  anchor/supervisor/pin bounded-command kernel with a positive total deadline, explicit
  environment, bounded capture, typed outcome, and exhaustive cleanup
- hydrate and smoke the candidate root before its atomic swap so any provisioning/runtime failure
  preserves the prior complete root and leaves no partial final root
- pin each direct Python requirement and pip itself, record the full resolved Python/source/runtime
  provenance, and compute the manifest digest deterministically from the sorted hydrated payload
  paths, types, modes, bytes, and safe symlink targets rather than declarative metadata
- create candidate venvs with copied launchers and no bytecode, rewrite owned scripts/config to the
  final root before smoke, and fail closed if any candidate-root bytes remain
- checksum-gate the fixed Audiveris 5.10.2 release DMG, classify a live mount by kernel device id,
  and detach through the primary-preserving bounded release path
- synchronize the candidate tree and parent directories around sibling renames, retain
  `.previous` until final-path validation, roll back on synchronous/asynchronous failure, and
  reconcile only an unambiguous exact final, previous, or candidate root after a crash; classify a
  validated pre-correction declarative root only as an explicit migration predecessor or rollback
  root, never as an exact candidate or successfully activated exact root
- make an exact byte- and manifest-identical rerun a candidate-discarding no-op so immutable
  overlay lower-layer roots do not require a rename; a different candidate still follows the
  fail-closed replacement transaction
- use `${HOME}/.local/share/pypoetry/venv/bin/poetry` in the generated Apple host manifest and
  create that fixed default only through the kernel-locked, deadline-bounded bootstrap with exact
  Python and pinned Poetry requirements; retain `/opt/homebrew/bin/poetry` only in the fixed
  manifestless fallback list, and keep a configured non-default missing path a hard failure
- extend lint/unit coverage so native-source strings, native source-file materializers, direct
  compiler consumption of repo-owned source, native-source extensions, Cabal native-source fields,
  and Cabal CPP token-synthesis definitions fail
- record the removed embedded source and superseded bridge topology in the deletion ledger
- pre-extract the Audiveris JavaCPP natives into the sealed candidate at materialization time and
  point JavaCPP's cache at that sealed location, so no runtime extraction into the operator's home
  occurs on any substrate; the alternatives (per-run temporary cache, admitting `~/.javacpp` as an
  owned location) are rejected because both leave the loaded libraries outside the generation
- decline JavaCPP symbolic-link creation on every Audiveris invocation
  (`-Dorg.bytedeco.javacpp.canCreateSymbolicLink=false`), so the extraction cache is a plain tree of
  regular files and the sealed payload carries no path-dependent bytes at all. JavaCPP owns one
  cross-jar alias inside its configured cache and re-establishes it on every load — measured on
  Audiveris 5.10.2 with JavaCPP 1.5.12: a relative target is rewritten to the absolute cache path, a
  regular file is deleted and replaced by the link, an absent link is re-created, and a cache it
  cannot write is not an error but an escape to `~/.javacpp/cache`. Its only fixed point therefore
  names whichever root the payload currently occupies, and this artifact is smoked once at the
  candidate root and again after the rename onto the final root, so no single spelling satisfies
  both. The alias is not on the load path — every library loads from its own extracted jar
  directory — so declining it costs nothing and makes the payload relocation-invariant instead of
  repaired. The generic package-closure policy stays strict-relative and is now the only thing
  standing between a stray absolute link and a published artifact.
- render that invocation from one definition per lane rather than restating it. The Apple
  pre-extraction command and the Linux image build are the two runs that *create* the caches their
  consumers later load from, so both read the same executable, cache directory, classpath, and
  property set the target and smoke read; the Linux image recipe is bound to those constants by a
  source assertion. A cache populated under a different JavaCPP configuration than its consumer is a
  payload the first consumer rewrites.
- run the Apple Audiveris installed smoke as the inference target's own invocation — the bundled
  JVM, the artifact's own JavaCPP cache directory, the application classpath, and the `Audiveris`
  main class — with `-version` appended, rather than as a bare `java -version`. The smoke exists to
  prove that the thing inference runs works, and the bare JVM answers on standard error in three
  lines while the parser is bound to Audiveris's own seven-field banner and to the pinned checksum
  receipt's version. The executable and its leading arguments have one definition that both the
  target and the smoke read, because this invocation has drifted between producer and consumer
  twice. Audiveris terminates that banner with a blank line, which is admitted for this adapter
  alone: the shared no-empty-line rule is how junk is kept out of a field parser, and a second
  blank line, a blank line elsewhere, or a blank terminator on any other adapter still fails closed
- treat an Apple operating-system platform binary as executed in place on both the anchor and target
  sides of the bounded-command protocol: a platform binary is validated against the kernel trust
  cache, so a copy carries no usable signature and is killed at exec. The exemption is confined to
  the prefixes the operating system itself protects (`/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`,
  `/usr/libexec`, `/System`), which cannot be swapped without disabling System Integrity Protection;
  `/usr/local` and the Homebrew prefixes stay snapshotted, and canonical path, device, inode, mode,
  size, and content digest are still verified immediately before launch
- require a structurally credible fat header before treating `0xCAFEBABE` as Mach-O: that magic is
  also the Java class-file magic, and an Audiveris bundle is full of `.class` files. Candidacy needs
  an architecture count within the parser's own bound and a first architecture naming a CPU type
  Mach-O defines
- read Mach-O headers under a bound rather than reading the whole image: thin reads are limited to
  32 + `sizeofcmds`, a fat table and its unique arm64 range are validated against the exact image
  before the slice header is read, every descriptor read is at most 64 KiB, and the descriptor and
  path are rechecked at the end. Digest and logical-byte accounting are unchanged
- force each streaming digest context before the next descriptor read in every streaming loop, so
  hashing a multi-hundred-megabyte payload does not retain a chunk chain
- admit `@loader_path/../.dylibs/<name>` install names only while the anchoring image lives inside
  one of the package closures being walked and the collapsed target stays inside that same closure;
  that layout is what every delocated Python wheel uses, while an image outside every closure keeps
  the strict no-ascent rule and `@rpath` suffixes keep it unconditionally
- exclude, rather than rewrite, the host-shebang console scripts in the copied Python home. A
  rewritten shebang is still an absolute path, and Linux truncates a shebang at 127 bytes where
  Darwin allows 512, so a rewrite that fits on the Apple host can produce an unexecutable script on
  `linux-cpu` or `linux-gpu`. The exclusion is confined to `bin/`, preserving importable
  standard-library modules that carry absolute shebangs
- scan the Python home alongside the candidate venv when resolving the runtime closure: the
  standard-library extension modules under `lib-dynload` are `dlopen`ed by the import machinery
  rather than linked, so no dependency edge reaches them and their Homebrew dependencies were never
  vendored
- keep the residual-source policy root-aware and symmetric rather than banning absolute paths
  outright, since standard-library sources legitimately contain `/usr/local` and `/bin/sh`; retained
  versus sealed destination identity is represented explicitly and probes are bounded
- retain the already-open nofollow descriptor for an external stable copy source instead of
  relabeling it as an in-root source with the destination writer; arbitrary external paths remain
  exact-content sources and only truly owned sources are in-root
- derive the supervisor's admissible target-environment name set from the renderer-owned command,
  fixed-provisioning, Python-snapshot, and sealed-artifact vocabularies rather than restating it, and
  compare the Audiveris runtime-environment consumer against the same installed-smoke executable path
  the producer emits — both defects were a second copy of what the producer constructs
- pass `--expected-python-prefix <artifactRoot>/venv` to every installed Python smoke, so an
  installed smoke cannot silently run against a different interpreter prefix
- bind the Linux sealed-run smoke to the absolute image target rather than the Apple
  installed-artifact shape, and interpret root mutation through a closed first-order effect language
  whose interpreter is retained on the activation token, so a rollback cannot be handed a different
  one than the forward transaction used
- verify a package closure under an explicit `RetainedSource` versus `SealedSnapshot` mode: a
  retained Python home applies the identical mint/copy exclusions, every other retained role hashes
  all content, and a sealed snapshot hashes every copied or reinjected entry. Verifying a retained
  source in snapshot mode counts the launchers and base site-packages symlink the copy deliberately
  excluded and reports a deterministic phantom delta
- propagate the anchor's child root into supervisor validation and share one expected/observed
  environment validator between renderer and supervisor, so a snapshot rendered against the child
  root is not validated against the parent root
- produce the Linux loader closure from a descriptor-derived ELF inspection (`PT_INTERP`,
  `PT_DYNAMIC`, `DT_NEEDED`, `DT_SONAME`, `DT_RPATH`, `DT_RUNPATH`, with `DT_STRTAB` mapped from its
  virtual address back through the `PT_LOAD` segments rather than used as a file offset),
  `$ORIGIN`/`$LIB`/`$PLATFORM` expansion with lexical `..` collapse anchored on an already-canonical
  observed directory, both `ld.so.cache` layouts including the embedded new-after-old arrangement
  modern glibc writes, and a bounded recursive walk seeded from the entry object and from every ELF
  found by scanning the closed image roots. Each object is opened `O_NOFOLLOW`, identity-checked
  before and after, and the bytes parsed are the bytes digested. The walk follows queued
  dependencies before unrelated scan seeds, reuses a unique already-observed `DT_SONAME`, and admits
  a valid relocatable object whose program-header count and entry size are both zero
- never consult `LD_LIBRARY_PATH`, in the closure producer or in the sealed-run environment: reading
  it is the ambient environment read the configuration doctrine forbids, and a generation identity
  that depended on it would not be reproducible
- run the loader-closure producer for image targets only. An Apple installed target carries no
  loader evidence, and the manifest validator rejects an Apple manifest that carries any, because an
  Apple root's runtime closure is vendored into the payload during hydration and proven at run time
  by the installed smoke's `DYLD_PRINT_LIBRARIES` audit
- revalidate the complete recorded closure helper-side rather than only the entry executable, with
  every object and the cache file re-stat'ed and re-digested against its recorded configured and
  canonical identity, and fail closed on a manifest that carries no loader closure at all, since an
  absent closure binds none of the loader, resolution metadata, or system libraries the target loads
- select the sealed-run loader audit from the command's own closed provisioning operation, the
  installed-runner smoke to the dyld audit and the Linux native-artifact smoke to the ELF audit, so
  a smoke cannot be compiled with an audit it could never satisfy and no third command reaches an
  exact-capture audit at all; the three aggregate checks that make a loader audit meaningful
  (something was loaded, at least one object came from the sealed generation, nothing outside the
  generation and the operating system was loaded) are shared by both loaders
- render the Linux smoke with `LD_DEBUG=libs` as a fixed guard value, admitted as a closed
  environment shape by both the sealed-artifact and the supervisor environment validators: `all`
  buries the load records and a narrower setting emits none
- treat the loader frame grammar as measured rather than documented. `calling init: <path>` is the
  only load record, because `trying file=` also names candidates the loader rejected;
  `initialize program:` and `transferring control:` carry `argv[0]` rather than a path, except that
  a static ELF executable contributes its absolute `initialize program:` frame; and a load record
  legitimately carries `..`, so the path is lexically collapsed rather than banned, an ascending
  path is classified as unsealed instead of laundered into the artifact root, and an ascent past the
  filesystem root fails closed. An unrecognised frame is loader commentary carrying no path, while a
  frame that claims to be a load record and violates the shape still fails closed
- keep `/etc/ld.so.cache` bound in target evidence whenever any edge resolved through it and omit
  cache evidence only when no edge used it; install every browser and system package before native
  artifact materialization so cache-backed evidence is measured from the final immutable filesystem
- make native materialization the last mutating command of the Linux image build, after the
  framework installs, the web build, and the Python checks, because those installs change the
  observed system loader closure of anything materialized before them
- compare persisted Linux image evidence by portable identity — closed paths, types, modes, sizes,
  digests, ELF metadata, and loader edges — and never by device and inode numbers, which the OCI
  runtime reassigns when it unpacks the runtime rootfs; descriptor-open observation still uses
  device/inode identity to prove a stable read
- select the shared Python runtime resolver by compiled host platform: the bounded Mach-O closure on
  Darwin and the descriptor-observed recursive ELF loader closure on Linux
- retain and revalidate a Linux snapshot's exact observed ELF libraries in place under an explicit
  closed supervisor environment shape that injects only `PYTHONHOME` and `PYTHONPATH`, while Darwin
  keeps its copied DYLD closure; create both image-owned venvs with copied interpreters and a
  dereferenced standard-library payload before Poetry populates them, since an ordinary Linux venv
  does not contain its standard library and canonicalizes through a system-interpreter symlink
- reconcile installed generation-lease sidecars from a bounded, identity-checked census of installed
  sibling generations, reacquiring each validated sibling under exclusive materialization authority
  so a missing real lock leaf is minted before obsolete retirement, and remove the global
  post-publication reconciliation sweep, because preparation already performs bounded all-sibling
  reconciliation and commit retains the adapter-local retirement
- require the retained setup manifest only on Apple. Linux CPU and GPU framework environments are
  immutable image payloads proven by the baked per-engine marker and its `projectDigest`, which the
  Docker producer computes from the exact `pyproject.toml` bytes, a separator newline, and the
  `poetry.lock` bytes through the same SHA-256 construction as the Haskell consumer
- render the verified real CLI grammar for llama.cpp, whisper.cpp, and Audiveris in the raw-target
  dispatch, retain the native-runner wrapper protocol only for Python-backed native adapters, and
  reject a missing operand or an unregistered adapter before process creation. The llama.cpp grammar
  selects the supported non-conversation single-turn simple-I/O mode and disables native diagnostic
  logging while keeping the 32-token, 512-context, one-thread, zero-GPU-layer bounds
- census the Audiveris output tree deterministically to depth 8 and 4,096 entries, reject symlinks
  and ambiguous or absent MusicXML output, and emit an upload marker only for the single real output
  file; the family contract accepts the three real MusicXML forms `.mxl`, `.musicxml`, and `.xml`
- never convert an absent exact process-group leader into absence evidence, and never deliver a
  signal on a path where the leader can no longer vouch for the group id. An absent leader
  discharges its obligation through the bounded absence proof, where only `ESRCH` succeeds and a
  persistent `EPERM` or a persistently live group still fails closed at the deadline; `EPERM`
  consumes a poll attempt rather than aborting that proof, because Darwin reports it while a
  just-exited group still holds unreaped kernel state and Linux reports it for a surviving member
  belonging to a uid we may not signal. A leader observed as a different process still hard-refuses
  at every site. `EPERM` from an owner probe is deliberately not discharged as owner death, because
  Darwin's registry-backed birth identity reads a live but unregistered process as absent and only
  that probe distinguishes it from a dead owner

### Validation

- focused unit tests prove the materializer emits no native implementation source and still
  produces complete typed manifests and fail-closed smoke commands
- `cabal test test:infernix-artifact-transaction --test-show-details=direct` passes the complete
  settled-source deterministic identity, unsafe-payload, exact/legacy distinction, idempotent
  rerun, activation,
  smoke-bound tamper, migration, sync/async rollback, and crash-reconciliation cases
- the dedicated full Apple materializer suite passes deterministic recursive-closure,
  failure/cancellation, lock-release, obsolete-root retirement, and recovery cases
- the symlink-free JavaCPP cache is proven on both sides of the property it buys: a focused
  assertion fixes both lanes' exact argument vectors including the upstream spelling of the
  symbolic-link property, and binds the Linux image recipe to the same constants; and a materializer
  fixture publishes a symlink-free cache across the candidate-to-final rename, asserting an
  unchanged payload digest, unchanged bytes, unchanged file identity, and that an injected absolute
  link is still refused with the published payload left intact. The second half is the point: with
  nothing normalizing an absolute target any more, the strict-relative payload policy is the whole
  defence
- machine-independent synthetic boundary cases are accepted only for indexed-runner ordering and
  cleanup mechanics; actual-materializer cancellation requires a fresh Darwin run through the
  fixed post-mount hook with exact mount, candidate-root, prior-root, and lock evidence
- after a green `./.build/infernix internal materialize-metal-engines` creates the required current
  prior root, the exact opt-in cohort command is
  `./.build/infernix internal validate-darwin-audiveris-cancellation`; this command is pending
- `cabal test infernix-compile-fail --test-show-details=direct` passes every settled-source positive
  and negative fixture, including hidden Apple internal/artifact/provisioning imports and the removed raw
  per-artifact installer
- Haskell style rejects direct process access, legacy unbounded Poetry-helper delegation, and
  bounded-kernel bypass throughout the Apple artifact/provisioning modules; focused unit and Python
  `check-code` gates pass
- repository scans and `infernix lint files` find no repo-owned native implementation source,
  embedded equivalent, or Cabal native-source declaration
- the complete machine-independent Stage 1 gate passes on the exact reviewed worktree
- every closure bound is reachable through the closed bound fixture over the same folds production
  runs rather than a parallel restatement of them, covered positively at its exact measured total
  and on overflow at one unit more. `maximumExactRuntimeFileBytes` equals `maximumStableCopyBytes`
  because the bounded stable copy refuses any bound greater than the latter, so the two cannot be
  chosen independently, and a breach names the dimension exceeded and the observed value so it can
  be acted on without re-running a whole materialization
- the pure Apple cohort regressions cover both dyld scheduling-frame directions, the tightened
  load-record rule, the three-valued audit classification, the sealed-artifact runtime environment
  for the native-CLI and Audiveris target shapes including its rejection of an unfixed guard value
  and an unknown name set, the supervised target's owned-root containment with and without an
  authorized artifact install root, and the delocated-wheel ascent policy in all four directions
- the ELF surfaces are provable without a Linux host: hand-built fixtures cover a complete synthetic
  AArch64 `ET_DYN` image, a standalone new-format cache, an old-format cache, and an embedded
  new-after-old cache, and every sealed-run audit fixture line is verbatim from a captured native
  `linux/arm64` `LD_DEBUG=libs` run rather than assumed
- the Apple cohort rematerializes the affected artifacts, proves the upstream-owned runtime smoke,
  and completes the correction-dependent routed lane before any Apple closure is claimed
- the paired source-matched `linux-cpu` cohort completes before Phase 1 is marked `Done`

### Remaining Work

- rerun `./.build/infernix internal materialize-metal-engines` to completion so the Apple engine
  roots and per-engine Python environments are rematerialized from current source
- run the fixed production Audiveris cancellation command
  `./.build/infernix internal validate-darwin-audiveris-cancellation`, which is implemented but has
  never been run; it requires a current valid prior `jvm-native` root created by a green
  materializer run
- run the installed-Python source-isolation command and the installed authoritative smokes with the
  source runtimes unavailable
- require schema-complete real output for `llm-smollm2-safetensors`, `audio-demucs-htdemucs`,
  `audio-open-unmix`, `music-mt3-infer`, `music-mr-mt3`, `music-omnizart`, and `audio-bark-small`,
  and require `image-sdxl-turbo` to return the exact typed refusal derived from the same final
  current-host observation used by `init --force` and `test init`. Changed host facts must change
  the expected `availableMib` rather than preserve a recorded literal
- choose the final closure-bound values from the measured sizes of all seven artifacts and pin them
  with positive and overflow tests. The current values were raised to unblock measurement rather
  than chosen from it, and `jvm-native` is still unmeasured and changes size once the JavaCPP
  natives are pre-extracted into the artifact, so the bounds remain provisional for one more
  materialization rather than for lack of measurement
- cover the surfaces the pure regression block does not reach because they are not pure: the
  canonical-versus-configured identity comparison, the hydration-witness relocation selection, the
  dual executable-authority forms, weak and lazy dylib resolution, and closure rpath seeding
- write helper-side coverage that drives a real bounded command against a synthetic `linux-native`
  generation; until that exists the routed `linux-cpu` lane is the only place the Linux candidate
  re-derivation and a resolver-versus-loader disagreement are actually proven, and they surface
  there as a named unsealed-library or no-provenance failure rather than silently
- close the recorded generation-lease residual: an out-of-band sidecar removal between minting and
  acquisition escapes as an `IOException`, the same class as an out-of-band engines-root replacement
  during acquisition. The generation lease is finer-grained authority that the engines-root
  exclusive/shared locking already subsumes; it is recorded that way deliberately rather than
  claimed as new mutual exclusion
- close the `infernix-unit` load sensitivity rather than attributing it to host load. Every symptom
  is a missed deadline on unchanged source under sustained background CPU load, and whether every
  production cleanup path discharges the Darwin unreaped-zombie-group `EPERM` state correctly has
  not been proven; a timeout is exactly the path that would expose it
- complete the Apple `integration`, `e2e`, and `all` gates
- complete the paired source-matched `linux-cpu` cohort and record the
  [Wave Y](cohort-validation-waves.md) attestation

---

## Sprint 1.21: Bounded Host Build Memory Kernel [Active]

**Status**: Active — the bounded-host-build-memory kernel, the complete-claimant account, the
generated per-machine ceiling, the closed Darwin measurement surface, and the authority-local
single-flight child lifecycle are implemented in current source. What remains is a current-source
rerun of the Darwin measurement command on the identity Phase 1 closes on.
**Code-side closure**: the kernel, calibration, measured manifest facts, and generated per-machine
ceiling are implemented. The current source additionally subtracts the active Colima pledge;
accounts compiler, driver, and worker-helper claims; binds the final Cabal driver/GHC arguments and
build-only environment to the opaque authority; closes all focused Cabal suite vectors; gives each
authority a private serialized child-lifecycle token with nominal region roles; and implements the
typed Darwin sampler/evidence command. The operator CLI observes the descriptor ceiling, closes
inherited descriptors, owns a fresh group through exceptional cleanup, and retains the token through
trusted Cabal-leader reap.
**Cohort gate**: `apple-silicon` — closed under [Wave AA](cohort-validation-waves.md). Darwin's
mechanism is a runtime heap cap plus bounded concurrency, and Phase 1 closure does not request
another Wave AA run.
**Implementation**: `src/Infernix/BuildMemory.hs`, `src/Infernix/HostMemory.hs`, `infernix.cabal`,
`cabal.project`, `test/compile-fail/cabal.project`, `test/compile-fail/Main.hs`,
`test/integration/Spec.hs`, `bootstrap/apple-silicon.sh`, `web/package.json`,
`src/Infernix/HostConfig.hs`,
`src/Infernix/Runtime/Enforcer/Internal.hs`, `src/Infernix/DemoConfig/Internal.hs`,
`src/Infernix/ProjectInit.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`,
`src/Infernix/Evidence/Readiness.hs`,
`src/Infernix/Runtime/CappedEngine/FixedObserver.hs`, `test/unit/Spec.hs`,
`test/capped-engine-observer/Spec.hs`, `test/compile-fail/fail/CannotCoerceToolchainSpawnAuthority.hs`,
`test/compile-fail/fail/CannotCoerceDarwinBuildMemoryValidationAuthority.hs`,
`src/Infernix/Lint/HaskellStyle.hs`, `docker/Dockerfile`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/architecture/bounded_host_memory.md`,
`documents/engineering/host_tools_manifest.md`, `documents/development/local_dev.md`,
`documents/reference/cli_reference.md`

### Objective

Give the host toolchain a declared account on physical memory, and make a ceiling that was never
divided by its concurrency impossible to construct.

The declared quantity is a budget for the complete toolchain account together with the job count.
`deriveBuildMemoryPlan` is the single mint and the only producer of the hidden-constructor
`BuildMemoryPlan`. It reserves a fixed 1024 MiB control/helper claim for the live Cabal driver and
one for each compiler worker, then divides the residual across compiler heaps. The normal account is
therefore `jobs × compilerHeap + (jobs + 1) × controlHeap`; neither the compiler ceiling nor its
concurrency exists independently. This is the sprint that refuses the obvious wrong fix: a 48 GiB
per-process heap cap under `jobs: $ncpus` on a 32-core host permits 1536 GiB before the driver and
helpers are counted.

The kernel is only installable because the built executable declares a bounded runtime address-space
reservation first. Measured on the development host: the compiler runtime reserves 1024.65 GiB by
default and 1.15 GiB under `-xr1G`, at identical resident memory. Without that, lowering the
process's own address-space limit succeeds and then kills it on its next allocation, so the
establish-at-startup-and-inherit pattern that `Infernix.DescriptorSpace` uses does not otherwise
transfer.

### Deliverables

All five original deliverables are implemented. The current source also implements the Apple
measurement surface required to validate the otherwise unenforced aggregate.

- **A bounded runtime address-space reservation on the built executable.** The shipped operator
  `infernix` carries `-with-rtsopts=-xr1024M` but deliberately no toolchain `-M`: it ignores inherited
  build-only `GHCRTS`, because service/inference runtime belongs to the non-toolchain host reserve and
  has not been calibrated to the 1024 MiB control cap. Test/tool images carry their explicit
  component caps. `toolchainReservationFitsEveryPlan` pins the address-reservation invariant.
- **A calibrated clean-clone account committed to `cabal.project`.** It carries three compiler jobs
  at 4096 MiB plus four 1024 MiB control/helper claims, exactly 16384 MiB, with a 12288 MiB compiler
  address reservation. Command-line authority remains binding over project files. The serialized
  compile-fail child has a separate one-job project and final vector: one 2048 MiB nested GHC plus
  four 1024 MiB outer-Cabal/test-runner/nested-Cabal/worker-auxiliary claims, 6144 MiB inside the
  outer 8192 MiB account. A clean Apple clone has a separate fixed stage-0 seed of one 4096 MiB
  compiler plus two 1024 MiB control claims, also 6144 MiB; its fixed-path preflight first proves that
  seed fits the measured 50% share after subtracting every active Colima pledge.
- **`Infernix.BuildMemory`** exporting `BuildMemoryBudget`, `BuildConcurrency`, and `BuildMemoryPlan`
  abstractly with `deriveBuildMemoryPlan` as the only mint, following the hidden-constructor,
  lower-only, fail-closed shape of `Infernix.DescriptorSpace`. `establishBoundedBuildMemory` writes
  the hard limit as well as the soft one — a bound a child can raise back is not a bound — and
  `requireBoundedBuildMemory` is the fail-closed observation at the point of use.
- **Physical-memory facts in the host manifest, measured rather than declared.** `Infernix.HostMemory`
  reads `MemTotal` from `/proc/meminfo` and intersects it with the cgroup v2 maximum on Linux, and
  reads `sysctl -n hw.memsize` on Darwin and subtracts the aggregate pledge of every Colima profile
  not explicitly stopped. The fixed-path, deadline-bounded Colima producer and conservative parser
  are shared with inference-memory partitioning; missing, malformed, failed, or non-positive
  observations fail closed. `infernix init` refuses to write a manifest it could not measure.
- **The per-machine ceiling generated into the untracked `cabal.project.local` by `infernix init`**,
  derived from those facts, superseding the hand-written stopgap. `internal
  materialize-substrate` writes it too. The mint chooses the largest funded job count at the
  calibrated compiler floor, reserves `(jobs + 1) × 1024 MiB`, and assigns the residual to the
  compiler slots. On the measured 124.94 GiB host, a 63967 MiB account selects eight jobs, a 6843 MiB
  compiler heap, and a 20529 MiB compiler address reservation; the exact claimant sum is 63960 MiB.
  An 8192 MiB account selects one job and a 6144 MiB compiler heap after its two control claims; the
  heap floor is not silently substituted for the residual.
- **A closed opt-in Darwin evidence command.** `infernix internal
  validate-darwin-build-memory` accepts only the resolved `UnenforcedLane
  DarwinHeapCapMechanism`, consumes the live plan and exact committed jobs/heap/reservation
  observation, checks the complete claimant sum without arithmetic overflow and against the account
  before spawning, and gives fresh scratch-root build/install process groups the exact
  authority-derived vector. Cabal receives leading `+RTS -M1024M -RTS` and build-only
  `GHCRTS=-M1024M`; GHC receives final `--jobs` and one ordered
  `--ghc-options=+RTS -M... -xr... -RTS`. The existing fixed Apple observer samples each owned
  group at a fixed cadence and the typed report names the result **sampled peak aggregate physical
  footprint**, alongside physical/effective memory, active Colima pledge, complete plan/subtotals,
  interval/count/maximum, an Integer fixed-point account-to-sampled-peak multiple, exits, and
  durations. The build requires a positive sample; a reused install that terminates before the first
  fixed-cadence probe records an explicit zero-sample terminal outcome instead of inventing a
  footprint. A final adversarial invalid-`GHCRTS` self-exec proves the freshly installed operator CLI
  ignores the build-only cap. Live observer loss while a group remains live fails closed. Normal
  completion observes no live group member while the leader still pins its identity; exceptional
  cleanup signals the owned group and performs the same pre-reap observation. Both cross a masked
  nonblocking leader-reap transition afterward, with no numeric PGID probe or signal after reap. The
  operator CLI parent and fixed observer tools are explicit non-toolchain host reserve claimants
  outside the sampled Cabal group and account.
- **A closed validation vocabulary for every retained Cabal surface.** `infernix test unit` owns the
  exact compile-fail, artifact-transaction, Apple-materializer, capped-observer,
  execution-plan-internal, and unit vectors. Integration no longer discovers or re-enters Cabal, web
  contract generation invokes the installed launcher, and the bootstrap/Docker paths carry their
  own exact accounts. Two non-default Apple materializer gates are fixed commands rather than
  caller-supplied Cabal options: `infernix internal validate-darwin-audiveris-cancellation` and
  `infernix internal validate-darwin-installed-python-source-isolation`.
- **Authority-local single-flight and an owned normal child lifecycle.** The authority and Darwin
  refinement have nominal region roles, and one private token serializes complete package-owned
  lifecycle calls using the same authority. The normal child observes the descriptor bound, uses
  `close_fds` and a fresh process group, retains the token through rank and Cabal-leader reap, and
  kills/reaps the still-owned group on an exception before that reap. This is intentionally not a
  host-global or crash-surviving lease. Independent CLI images, checkouts, and stage-0 bootstraps
  are unsupported concurrent claimants; the 50% account does not fund overlap and governed
  workflows must serialize them. Normal success trusts Cabal to await its workers and makes no
  post-reap descendant/PGID-absence claim.

Two decisions inside are worth stating rather than leaving implicit.

**The account is a claim on resident memory, and the address-space ceiling is derived from it rather
than the other way round.** The runtime reserves about three quarters of an address-space limit and
its copying collector needs two semispaces, so usable heap tracks an address-space limit at roughly a
third of it. Carrying both numbers independently would let them drift; the plan therefore derives
`planProcessAddressMib` from `planRtsHeapMib` through one `heapToAddressSpaceMultiplier`.

**A stale host manifest is a named refusal for ordinary commands, while init is the closed migration
surface.** Adding a record breaks every previously generated file, and runtime/cluster/test startup
still fails closed rather than falling through to defaults that could misclassify the execution
context. Help and init alone bypass configured startup. Init derives config-independent paths and
writes under runtime-config authority, so `infernix init --force` can replace a stale schema without
making any ordinary command tolerant.

### Validation

- **The compiler floor is calibrated against a measured complete clean build.** That build compiled
  611 modules across six components and peaked at 1328 MiB in the largest compiler and 1798 MiB
  summed across the observed compiler/Cabal processes. The 4096 MiB compiler floor is 3.1 times that
  single-process observation. The calibration predates the complete claimant model, so it fixes the
  floor and is not closure evidence for the account.
- **The kernel fixtures prove inherited Linux address limits, real-GHC compilation under the limit,
  named mechanism refusal, lower-only establishment, and the generated settings.** The authority
  fixture proves that equal heaps with different job counts are not interchangeable and that a stale
  job count or reservation refuses.
- **Cabal receives the account on the command line, not through its project files.** Cabal may still
  read those files after spawn, so the binding property is final command-line precedence: one
  authority-derived `--jobs`, one plural ordered `--ghc-options=+RTS -M... -xr... -RTS`, the leading
  Cabal control cap, and the fixed build-only environment. The singular repeated `--ghc-option`
  rendering is rejected because Cabal hands `-M`/`-xr` to GHC as compiler flags.
- **Focused unit cases pin** complete-account overflow and over-budget refusal, same-heap
  different-jobs separation, the exact build/install/suite argument vectors, installed-runtime
  environment isolation, report rendering, build-positive and install-zero sampling, deterministic
  same-authority serialization and exception release, nominal-role coercion refusal, and Darwin
  normal/exceptional pre-reap live-member observation plus terminal-crossing cleanup. The normal
  lifecycle source pins descriptor precheck, `close_fds`, fresh-group spawn, masked nonblocking
  leader reap, absence of a post-reap numeric-group probe, and exceptional cleanup. A bounded Darwin
  re-exec uses a 64 MiB heap cap, verifies the active RTS maximum, allocates roughly twice it, and
  requires an ordinary positive nonzero exit.
- **Stage-0 preflight runs under the deterministic launcher PATH.** The fixed
  `/opt/homebrew/bin/colima` cannot locate its own `limactl` under the bootstrap's global
  `PATH=/usr/bin:/bin`, so it is invoked through `/usr/bin/env` with the launcher PATH and a source
  guard pins that shape. A unit source guard also pins the escaped post-install heredoc, whose
  unescaped documentation backtick was evaluated as a command.
- **Only help and init bypass configured startup.** A forced init otherwise entered configured
  startup and decoded the stale host schema before it could replace it. Init derives its paths
  without a host manifest and writes through the closed runtime-config authority; a pure unit
  assertion pins the command predicate. The generated evidence is the four generated/ignored paths
  `infernix.dhall`, `infernix-host.dhall`, `.data/runtime/secrets/InfernixSecrets.dhall`, and
  `cabal.project.local`, never version-controlled Dhall.
- **The Darwin observer tolerates member turnover.** A short-lived same-UID GHC or helper process can
  depart between the complete `/usr/bin/top` group snapshot and the sequential `/usr/bin/footprint`
  call, which reports an unanalyzable process while the group still has a live member; that made the
  CLI refuse complete sampling. One shared five-second deadline now governs a raw bounded membership
  recheck: a retained failed PID stays fatal, an empty recheck returns the original terminal
  settlement, a failed recheck reports a combined fail-closed error, and a departed PID with a
  nonempty refreshed group discards the partial total and restarts the snapshot from zero. Four
  closed kernel-enum fixtures pin turnover, retained member, empty, and recheck-failure evidence.
- **Every fixed test and specialized Darwin vector carries `--enable-tests`.** Without it Cabal's
  solver plan excludes the style component, and `ToolchainBuildAll` is the calibrated
  `build all --enable-tests` form; the exact unit vectors change in lockstep.
- **The style gate is split across two packages because one solver universe cannot hold both.**
  Ormolu 0.8.0.2's Cabal-syntax 3.14 world and Cabal 3.16.1.0's Cabal-syntax 3.16 world are
  incompatible, and merely declaring two suites in one package still shares that universe.
  `infernix-haskell-style` (Ormolu/HLint) stays in the root package and Cabal 3.16 moves to the
  genuinely separate package under `test/cabal-format/`; the closed `test lint` vocabulary selects
  both sequentially.

### Remaining Work

- rerun the closed `./.build/infernix internal validate-darwin-build-memory` measurement on the
  source identity Phase 1 closes on, so the sampled aggregate evidence matches that identity rather
  than an earlier one
- the named limit stands rather than an unfinished mechanism: Darwin has no enforced aggregate or
  address-space ceiling, fixed-cadence sampling can miss transient peaks, and every process outside
  the measured Cabal group is excluded from both the sample and the account

---

## Sprint 1.22: Resolve The Build-Memory Lane Instead Of Assuming It [Active]

**Status**: Active — code-side closed. The lane resolution is landed and the Apple gates run on it;
the `linux-cpu` confirmation of the enforced arm remains open.
**Implementation**: `src/Infernix/BuildMemory.hs`, `test/unit/Spec.hs`,
`test/compile-fail/fail/CannotClaimUnenforcedAddressSpace.hs`, `test/compile-fail/Main.hs`,
`test/compile-fail/infernix-compile-fixtures.cabal`
**Docs to update**: `documents/architecture/bounded_host_memory.md`

### Objective

Sprint 1.21 wrote one platform-independent bound type while its own doctrine said the mechanism is
resolved per lane. That gap was not academic: it took every gate command down on Apple Silicon.

`withToolchainSpawnAuthority` resolved the lane and then discarded the answer, so
`withBoundedToolchainChild` assumed an address-space rlimit on every lane. Darwin reports `RLIMIT_AS`
infinite and rejects every finite ceiling written against it with `EINVAL` — measured: soft and hard
are both `INT64_MAX`, and `setrlimit` refuses `{finite, INFINITY}`. `setResourceLimit` therefore
threw before the child was started, so `infernix test lint`, `test unit`, `test integration` and
`test all` all died at the first toolchain spawn. `BuildMemory.hs` had never run on Darwin.

### Deliverables

- **The resolved mechanism is retained rather than discarded.** `ToolchainSpawnAuthority` carries it
  alongside the plan, and `withBoundedToolchainChild` holds a ceiling only on a lane that implements
  one. This is a **runtime lane resolution, not a type-level guarantee**, and is labelled as such —
  the gates came back on this change alone.
- **The lane distinction is in the types.** `BuildMemoryMechanism` is a GADT indexed by
  `AddressSpaceEnforcement`; `BuildMemoryBound` carries that index; `enforcedAddressCeilingMib` is
  defined only for `'AddressSpaceEnforced`. Each constructor fixes its own index, so the claim and
  the evidence are one fact — a separate unindexed copy beside the index would have reintroduced the
  over-claim one line below the type forbidding it. `resolveBuildMemoryMechanism` returns the new
  `ResolvedBuildMemoryMechanism` sum, which is where the runtime fact is refined and where every
  consumer is forced to handle both arms.
- **The mints return `Either` rather than a rank-2 region.** Identical refinement, `-Werror` already
  forces both arms, and no CPS rewrite of the fixture's call sites. A `with`-shaped region in this
  repository means the capability dies at region exit, but `establishBoundedBuildMemory` installs a
  permanent, one-way, image-wide limit — the region shape would mis-signal.
- **An unenforced bound observes something.** `observeHeapCapOnlyBound` re-reads the runtime heap cap
  committed to `cabal.project.local` and refuses when it is absent, unparseable, or disagrees with
  the derived plan. Without it the Darwin arm would mint evidence from the caller's own argument,
  contradicting this module's stated principle that `requireBoundedBuildMemory` is the observation at
  the point of use. The read is strict: a lazy `readFile` holds the handle open through the refusal
  paths, and the next writer fails with `resource busy` instead of the intended diagnostic.
- **Unit coverage branches by lane.** The unenforced arm asserts the two refusals (absent cap, stale
  cap) and the agreeing case; the real compiler-chain assertion is shared, because it carries content
  on both lanes.
- **A compile-fail fixture pins the index**: `CannotClaimUnenforcedAddressSpace.hs` applies
  `enforcedAddressCeilingMib` to a `'AddressSpaceUnavailable` bound and must fail as a type mismatch.
  It carries `{-# LANGUAGE DataKinds #-}` explicitly — the fixture package is `GHC2021`, which does
  not include it, and without the pragma the fixture fails with the wrong diagnostic class.

### Validation

- `./.build/infernix test lint` reaches and passes `infernix-haskell-style` on this Mac; before the
  change it died immediately with `setResourceLimit: invalid argument`.
- `cabal test infernix-unit` is **PASS on Darwin with no local scaffold** — the criterion this sprint
  was written against.
- `cabal test infernix-compile-fail` passes its positive and negative fixtures, including the new
  one.
- `cabal test infernix-haskell-style` passes.

### Remaining Work

- confirm the enforced arm on the `linux-cpu` lane. Its behaviour is unchanged but its code moved,
  and the Apple development host cannot exercise it natively; drive it through the existing Colima
  native arm64 daemon.

---

## Sprint 1.23: Prepare Per-Engine Python Environments Before Inference [Active]

**Status**: Active — code-side complete in current source: the per-engine Python producer is
re-homed into a package-hidden facade, prior readiness is durably invalidated before Poetry mutates
anything, and a shared project read/launch lease is held from exact interpreter/marker validation
through child completion. The Apple rematerialization and the paired `linux-cpu` Wave Y cohort are
open, so neither this sprint nor Phase 1 is validation-complete.
**Implementation**: `src/Infernix/Python.hs`, `src/Infernix/Engines/Provisioning.hs`,
`src/Infernix/Python/MutationLock/Internal.hs`,
`src/Infernix/Engines/AppleSilicon/Internal.hs`, `src/Infernix/CLI.hs`,
`src/Infernix/Runtime/Worker.hs`, `src/Infernix/Runtime/CappedEngine/Internal.hs`,
`src/Infernix/CommandRegistry.hs`, `docker/Dockerfile`, `infernix.cabal`, `test/unit/Spec.hs`,
`test/compile-fail/fail/CannotImportPython.hs`,
`test/compile-fail/fail/CannotImportRawPythonWorkerLaunch.hs`
**Docs to update**: `documents/development/python_policy.md`,
`documents/development/assistant_workflow.md`, `documents/engineering/portability.md`,
`documents/engineering/implementation_boundaries.md`, `documents/engineering/model_lifecycle.md`,
`documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`,
`documents/engineering/storage_and_state.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`,
`documents/operations/apple_silicon_runbook.md`, `documents/reference/cli_reference.md`, `README.md`
**Cohort gate**: `apple-silicon` plus paired `linux-cpu` — [Wave Y](cohort-validation-waves.md)

### Objective

Make the per-engine Python environment a materialization-time product on every lane that consumes
one, with a single derivation and marker contract. This prerequisite is re-homed from superseded
Phase 4 Sprint 4.36 so strict numerical Phase 1 validation has no forward dependency on Phase 4.
Inference remains an observer: it never installs or repairs a framework environment on a request.

### Deliverables

- **One canonical plan.** `Infernix.Python` derives the closed Python-stdio set from
  `EngineBindings.canonicalEngineBindingsForMode`, not from the demo-only model matrix. Darwin
  prepares `transformers`, `pytorch`, and `diffusers` with `apple-silicon`; the Linux CPU base image
  prepares `transformers` and `pytorch` with `linux-cpu`; the Linux GPU base materializer is a no-op
  because each selected engine image owns its `cuda` environment. Adapter ids must end in the exact
  `-python` suffix and the derived engine name must be one safe path component.
- **One producer and marker contract.** Every install runs through the closed, bounded Provisioning
  language under that engine project's writer lock. Readiness requires the exact executable
  `.venv/bin/python`. A first install with stable marker absence is already fail-closed evidence and
  does not require a future `.venv` parent merely to publish a tombstone. If a marker exists, the
  writer durably replaces it with the fixed incomplete tombstone before Poetry can mutate anything;
  an interruption leaves readiness invalid, and a repeated attempt sees the tombstone as unready and
  re-enters repair. After a successful install, the producer recomputes the digest of
  `pyproject.toml` plus the optional, possibly newly created `poetry.lock`, publishes the fixed
  framework marker through the project writer, and reads it back exactly before releasing the
  project. Missing, malformed, changing, oversized, or non-executable evidence fails closed.
- **Every supported materialization boundary produces the plan.** `internal materialize-substrate`
  prepares it after publishing and reloading the host manifest; Apple runtime startup prepares it
  after the shared adapter session; and `internal materialize-metal-engines` prepares it after the
  native-artifact session. The Apple calls run outside the shared/native project locks, avoiding a
  nested-lock deadlock while keeping all repair off the request path.
- **One consumer derivation with launch custody.** `Runtime.Worker` enters the package-hidden Python
  facade, which acquires a shared lease on the exact per-project writer lock, validates the marker
  and interpreter under that lease, and carries opaque nominal read authority through the capped
  subprocess's completion. Concurrent inference readers may coexist, but the exclusive Poetry
  writer cannot tombstone or mutate the environment while a child imports from it.
  `Runtime.CappedEngine.Internal` obtains the interpreter only by consuming that authority. The
  hand-written path, group, marker-body, and digest copies and the orphaned
  `ensurePoetryProjectInstalledWithGroups` export are removed with request-time repair.
- **A package-hidden facade.** `Infernix.Python` and the mutation-lock kernel are not exposed library
  modules. Compile-fail fixtures reject an external import of the producer/read-authority surface and
  an attempted raw Python worker launch, so callers cannot bypass the locked facade by constructing
  an interpreter path themselves.
- **No shell producer.** The Linux CPU Dockerfile's direct Poetry install, `sha256sum`, and marker
  writes are deleted. Its existing `internal materialize-substrate linux-cpu` invocation is the
  sole base-image producer, so Apple and CPU cannot drift into different marker formats.

### Validation

- Unit assertions pin the exact Darwin three-engine and Linux CPU two-engine plans, the Linux GPU
  no-op, the exact suffix/path rejection, and that a newly created `poetry.lock` changes the marker
  digest.
- Filesystem fixtures prove that matching executable/digest/marker evidence passes and that a
  malformed or missing marker, project-lock drift, or missing interpreter fails closed without
  invoking Poetry. Source assertions pin deletion of the Docker hand-written producer and both
  Apple producer boundaries: runtime startup and explicit metal materialization.
- Crash-consistency fixtures prove stable first-install absence remains unready, an existing marker
  is durably tombstoned before the injected pre-Poetry interruption, and repeated interruption
  re-enters repair without reviving stale readiness. Lease fixtures prove two readers may coexist,
  the nonblocking writer is excluded throughout validation/launch custody, and the writer can enter
  after every reader releases. Compile-fail fixtures pin the package-hidden boundary. These
  additions are covered by the machine-independent gate set.
- `cabal build lib:infernix test:infernix-unit` builds under `-Wall -Werror` and
  `cabal test infernix-unit --test-options='--hide-successes'` passes.

### Remaining Work

- rematerialize the Apple per-engine Python environments through a completed materializer run
- require real inference from the exact seven in-budget Apple Python-stdio catalog rows
  (`llm-smollm2-safetensors`, `audio-demucs-htdemucs`, `audio-open-unmix`, `music-mt3-infer`,
  `music-mr-mt3`, `music-omnizart`, and `audio-bark-small`), and record each result under the
  [Wave Y](cohort-validation-waves.md) schema: source identity, lane, model id, adapter/engine
  artifact identity and manifest digest, request/result identity, terminal status, real-output
  witness, and the exact command/exit/settlement receipt
- require the eighth row, `image-sdxl-turbo`, to return the exact typed refusal derived from the
  same final host observation used by `init --force` and `test init`; a changed host observation
  changes the expected `availableMib` rather than preserving a recorded literal
- complete the paired source-matched `linux-cpu` cohort with its image/materialization identity, the
  same seven schema-complete routed real-output records, and the full cohort gate, proving the
  collapsed producer did not regress the base image

---

## Sprint 1.24: Remove Build-Time Haskell Protobuf Generation From Darwin [Active]

**Status**: Active — code-side complete in current source: the package is `Simple`, build-time
Darwin protobuf generation is removed, the exact four generated modules are tracked by an exact
manifest, and byte regeneration is confined to a pinned Linux image gate. That pinned Linux
byte-regeneration image gate has not run.
**Implementation**: `infernix.cabal`, deleted `Setup.hs`,
`proto/haskell-bindings.sha256`, `src/Proto/Infernix/Manifest/RuntimeManifest.hs`,
`src/Proto/Infernix/Manifest/RuntimeManifest_Fields.hs`,
`src/Proto/Infernix/Runtime/Inference.hs`,
`src/Proto/Infernix/Runtime/Inference_Fields.hs`, `src/Infernix/Lint/Proto.hs`,
`src/Infernix/Lint/Files.hs`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/HostConfig.hs`,
`src/Infernix/HostTools.hs`, `src/Infernix/CLI.hs`,
`src/Infernix/Cluster/Subprocess.hs`, `bootstrap/apple-silicon.sh`,
`docker/Dockerfile`, `test/haskell-style/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `proto/README.md`, `documents/development/haskell_style.md`,
`documents/development/no_env_vars.md`, `documents/development/local_dev.md`,
`documents/development/assistant_workflow.md`, `documents/engineering/build_artifacts.md`,
`documents/engineering/host_tools_manifest.md`,
`documents/engineering/implementation_boundaries.md`,
`documents/engineering/portability.md`, `documents/operations/apple_silicon_runbook.md`,
`documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Cohort gate**: paired native `linux-cpu` image build plus the ordinary Apple source gate —
[Wave Y](cohort-validation-waves.md)

### Objective

Keep the two `.proto` schemas canonical while making a normal package build consume, rather than
produce, Haskell modules. Darwin must not start Cabal, `protoc`, or a Haskell generator plugin from a
Custom Setup hook. Generated source must remain visibly generated and byte-exact rather than being
formatted or maintained as handwritten Haskell.

### Deliverables

- **A Simple package with no Setup program.** `infernix.cabal` uses `build-type: Simple`; the
  `custom-setup` and `autogen-modules` declarations are gone; `Setup.hs` is deleted; Docker and the
  style source inventory no longer name it. The four modules remain ordinary `other-modules`, so
  every library/test consumer compiles the same checked-in bytes. The setup-only
  `proto-lens-setup:Cabal` solver exceptions are retired while the lens-family exceptions required
  by the runtime remain.
- **Canonical schemas and explicitly generated Haskell.** The two files below `proto/infernix/`
  remain the only authoring surface. The four files below `src/Proto/` are byte-for-byte generator
  output, including their generator banner and layout; they are not passed through Ormolu or HLint.
  The style and generic text-hygiene exclusions are both the exact four-path manifest-backed
  predicate shared with the proto lint, so generator-owned trailing whitespace or final-newline
  layout stays byte-exact while any similarly named handwritten file remains in both gates.
- **One exact, no-spawn drift invariant.** `proto/haskell-bindings.sha256` has a fixed v1 header that
  names `proto-lens-protoc 0.9.0.1` and `libprotoc 34.1`, then exactly six ordered lowercase SHA-256
  entries: two canonical schemas and four generated modules. `infernix lint proto` recursively
  enumerates regular files below `src/Proto`, rejects a missing, extra, empty, or symbolic-link
  artifact, requires that exact four-file inventory, retains the schema/package/symbol checks, and
  verifies all six bytestrings against the manifest. The lint never starts a compiler or plugin.
- **One real Linux regeneration proof.** No Cabal component declares a generator build tool, so an
  ordinary Linux build also only consumes tracked source. The Docker gate alone runs a bounded,
  exact `cabal install proto-lens-protoc-0.9.0.1` into `/opt/infernix/proto-tools`, linking the
  plugin with `-rtsopts=ignore -with-rtsopts=-M1024M` so its fixed `GHCRTS=-M1024M` execution is
  admitted rather than rejected. It fetches official `libprotoc 34.1` archives for native
  `amd64`/`x86_64` or `arm64`/`aarch_64` and verifies their SHA-256 values
  (`af27ea66cd26938fe48587804ca7d4817457a08350021a1c6e23a27ccc8c6904` and
  `31c5e9e3c7bf013cf41fb97765ee255c140024a6b175b6cc9b64beddd7c23ba7`, respectively). After the
  complete source copy it regenerates both schemas into a temporary root, requires exactly the four
  expected outputs, and byte-compares every output with `src/Proto`. Ubuntu's unpinned
  `protobuf-compiler` package and the runtime `HostProtoc` manifest field are removed.
- **No Darwin generator prerequisite.** Apple bootstrap no longer installs or probes Homebrew
  `protobuf`; Python binding generation continues through the package-owned venv's fixed
  `python -m grpc_tools.protoc` provisioning command and does not consume a host `protoc`. A normal
  Apple build and `infernix lint proto` therefore have no raw compiler/plugin descendant.

### Validation

- Static checks confirm that the four checked-in modules match the former library, unit, and
  integration autogen copies byte-for-byte, that the governed six SHA-256 values match current
  files, that `src/Proto` contains exactly four regular non-symlink files, and that the
  non-generated patch has no whitespace errors. Focused pure tests cover a one-byte snapshot
  mutation, an unexpected fifth file, and the exact style-exclusion boundary. The Docker source
  assertion pins both `GHCRTS=-M1024M` on Cabal and protoc/plugin execution and the plugin's
  `-rtsopts=ignore -with-rtsopts=-M1024M` link flags; successful regeneration is the
  protocol-success proof that the plugin image accepts that fixed environment cap.
- **Generator-owned bytes are exempt from text hygiene, not formatted.** `infernix lint files`
  rejected generator-owned trailing whitespace and missing-final-newline bytes in the exact four
  tracked outputs, and formatting them would violate the byte-regeneration contract. The lint
  exempts only paths present in the exact generated-module manifest, with positive and
  similarly-named-negative unit guards; native-source, environment, symlink, and inventory checks
  remain active.
- **Pending generator gate:** build the native `linux-cpu` image from the same source. The Docker
  `RUN` step is the required execution evidence for both the pinned generator inventory and all four
  byte comparisons; prose or the Darwin hash lint does not substitute for it.

### Remaining Work

- run the native Linux generator gate and record its exact source and image identity with the
  result. Raw `protoc` must not be invoked on Darwin to produce that evidence: the ordinary Apple
  gate proves consumption without a generator, while the native Linux image gate owns regeneration.
- confirm in the Linux build log that the pinned plugin install and the `GHCRTS=-M1024M`
  regeneration command both execute successfully.

---

## Sprint 1.25: Run the Haskell Style Gate In-Process [Active]

**Status**: Active — code-side implementation is present: pinned Ormolu and HLint behavior runs in
the root package, pinned Cabal-format behavior runs in a genuinely separate package, and runtime
formatter installation is removed. The current-source rerun of the closed style gate on the identity
Phase 1 closes on remains open.
**Implementation**: `src/Infernix/Lint/HaskellStyle.hs`, `test/haskell-style/Spec.hs`,
`test/cabal-format/Spec.hs`, `test/cabal-format/cabal.project`,
`test/cabal-format/infernix-cabal-format.cabal`,
`src/Infernix/HostConfig.hs`, `src/Infernix/HostTools.hs`, `src/Infernix/CLI.hs`,
`test/unit/Spec.hs`, `infernix.cabal`, `docker/Dockerfile`
**Docs to update**: `documents/development/haskell_style.md`,
`documents/engineering/dependency_management.md`, `documents/engineering/testing.md`,
`documents/engineering/docker_policy.md`, `documents/engineering/host_tools_manifest.md`,
`documents/architecture/configuration_doctrine.md`, `documents/reference/cli_reference.md`,
`DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md`
**Cohort gate**: ordinary Apple source gate plus paired native `linux-cpu` source/image gate —
[Wave Y](cohort-validation-waves.md)

### Objective

Make the Haskell quality gate bounded package components rather than a runtime package installer
and process launcher. Preserve the exact Ormolu CLI configuration, HLint findings, Cabal-format
payload, repo readability rules, and generated-source boundary without relying on ambient `PATH`,
operator host-manifest state, temporary manifest rewrites, or unconstrained child toolchains.

### Deliverables

- **One lightweight source-style ownership seam.** `Infernix.Lint.HaskellStyle.runHaskellStyleLintWith` remains
  the sole owner of recursive source discovery, the exact generated-source exclusion, and all
  repo-specific readability checks. It accepts formatter and linter callbacks so only
  `infernix-haskell-style` links Ormolu and HLint.
- **Exact in-process formatter and linter behavior.** The test component pins
  `ormolu ==0.8.0.2` and `hlint ==3.10`. For each relative inventory path, the Ormolu callback
  performs Cabal component discovery, source-type detection, and `.ormolu` fixity/re-export
  refinement exactly as `ormolu --mode check` does, then byte-compares the rendered text. The HLint
  callback passes the same exact path list to its CLI-compatible library entrypoint and fails on any
  returned idea.
- **A separate versioned Cabal renderer, not a nested Cabal.** The package under
  `test/cabal-format/` links only its minimal dependencies plus `Cabal ==3.16.1.0`, and
  parses/renders both itself and `infernix.cabal` with `readGenericPackageDescription` and
  `showGenericPackageDescription`, the payload used by that Cabal line's `format` command. This
  stays deterministic when the outer build driver is cabal-install 3.14 or 3.16. A separate suite
  in the root package was rejected because it still entered the same enabled-test solver universe;
  the genuinely separate package lets Ormolu's transitive Cabal-syntax 3.14 world and Cabal 3.16's
  syntax world coexist without one solver plan or values crossing the API boundary. Neither
  package adds a direct Cabal-syntax dependency. `ToolchainCabalFormat` renders the fixed project,
  target, and absolute repo-root build directory and runs it as a sequential top-level child under
  the same build-memory authority. The isolated project fixes GHC 9.12.4, disables environment-file
  writes, carries a bounded fallback, and the pre-spawn boundary fails closed on sibling
  `cabal.project.local` or `cabal.project.freeze` overlays.
- **No generated-code formatting drift.** Discovery recurses only through `app/`, `src/`, and
  `test/`, excluding exactly the four paths in `Proto.generatedHaskellProtoFiles`. Their byte-exact
  generator layout belongs to `infernix lint proto` and `proto/haskell-bindings.sha256`; similarly
  named handwritten paths remain styled.
- **No formatter host tools.** `HostOrmolu`, `HostHlint`, `hostOrmolu`, `hostHlint`, their generated
  manifest rows/defaults, CLI parent-directory entries, and hermetic unit stubs are deleted. The
  style path contains no runtime install root, executable discovery, temporary Cabal file, or style
  subprocess.
- **Closed component RTS posture.** The production executable rejects caller-supplied RTS options
  while retaining its baked reservation. Both style processes and every other non-unit test reject caller overrides and carry
  a baked 1024 MiB heap cap; the unit suite retains its intentional `-rtsopts` surface and gains the
  same baked heap cap. There is no global project or launcher RTS override.

### Validation

- Focused source assertions retain the exact four-path Proto exclusion and prove that similarly
  named handwritten paths are not excluded.
- Focused behavioral fixtures require a deliberately unformatted Haskell module and a module with
  exactly one HLint idea to fail through `infernix-haskell-style`, while a de-formatted valid Cabal
  manifest fails through `infernix-cabal-format`.
- Live `GHC.RTS.Flags.maxHeapSize` assertions prove that both style processes entered with their
  baked 1024 MiB caps. A separate Cabal-source fixture pins the main/unit/non-unit component flag
  split and proves `cabal.project` does not inject a global `-rtsopts` surface.
- A source-only audit must show no formatter bootstrap symbol, formatter build root, Ormolu/HLint
  host-manifest field, or nested style process in current nonhistorical source/docs.

### Remaining Work

- rerun the closed `infernix test lint` style gate on the source identity Phase 1 closes on, so the
  in-process Ormolu/HLint result and the isolated Cabal-format result both belong to that identity
- no bare host `cabal` vector is a supported validation instruction for this gate; it runs only
  through the closed CLI toolchain vocabulary

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/build_artifacts.md` - build roots, generated-artifact doctrine, snapshot launcher expectations, and native engine artifacts under `./.data/engines/<adapterId>/`
- `documents/engineering/apple_silicon_metal_headless_builds.md` - Tart-free Apple Metal/Core ML materialization target, upstream package boundary, manifest fields, and validation gates
- `documents/engineering/docker_policy.md` - host versus outer-container rules, image-snapshot launcher contract, and the clarification that Apple materialization is not a Docker/Colima lane
- `documents/engineering/host_tools_manifest.md` - supported host-tool schema without `hostTart`
  plus the retained `materialize-metal-engines` manifest surface
- `documents/engineering/implementation_boundaries.md` - ownership boundaries across Haskell, Python, chart assets, and generated outputs
- `documents/engineering/portability.md` - portable platform rules versus substrate-specific behavior, including the Apple headless materialization lane
- `documents/architecture/configuration_doctrine.md` - typed engine-artifact materialization records and the no-env rule
- `documents/architecture/managed_state_transitions.md` - Managed State Transitions doctrine this phase now references, generalizing the results-side realness contract to typed evidence for every state transition
- `documents/operations/apple_silicon_runbook.md` - Apple host workflow, headless materialization expectations, and Tart-free validation gate
- `documents/development/haskell_style.md` - formatter, linter, hard-gate, and review-guidance doctrine
- `documents/development/local_dev.md` - canonical local operator workflows

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - canonical `infernix` command inventory
- `documents/reference/cli_surface.md` - short subcommand-family overview
- `README.md` - orientation layer that links to canonical docs rather than restating them
- `AGENTS.md` - governed automation entry document aligned with canonical docs
- `CLAUDE.md` - governed automation entry document aligned with canonical docs

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when substrate ids, serialized `runtimeMode` identifiers, build-root rules, launcher doctrine,
  or command-registry ownership change
