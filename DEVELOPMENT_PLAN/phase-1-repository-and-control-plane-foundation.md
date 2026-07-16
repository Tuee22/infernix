# Phase 1: Repository and Control-Plane Foundation

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md)

> **Purpose**: Establish the canonical repository scaffold, the one-binary role topology
> (`infernix` sharing the default Cabal library exposed by the `infernix` package), the supported
> control-plane execution contexts, the substrate-selection baseline,
> generated-artifact hygiene, and the repository ownership rules that later phases build on.

## Phase Status

> **Real Apple native engines (Sprint 1.15 reopen).** Sprint 1.14 established the headless Apple
> Metal/Core ML materialization lane but populated it with deterministic validation-wrapper runners
> (`AppleSilicon.hs` `infernix_emit_validation_result`) that loaded no model; the Phase 4 realness
> audit confirmed the Apple native engine layer was fake. Phase 1 reopened Sprint 1.15 to
> materialize **real** Apple native engines (Core ML, MLX, llama.cpp/whisper.cpp Metal, CTranslate2,
> ONNX, Audiveris) on the existing runner contract — the scaffold, one-binary role topology, and
> host-manifest contracts from Sprints 1.1–1.14 stand; only the wrapper payloads were replaced.
> Sprint 1.15 and its Apple real-output cohort gate [Wave L](cohort-validation-waves.md) are closed:
> Apple host smoke, Apple Stage 2 integration, and focused routed Playwright pass on real Apple
> inference, and the paired `linux-cpu` full routed real-output gate passed on a real Linux host on
> 2026-06-29 (`infernix test all` green: Haskell style, Python `check-code`, Haskell unit, generated
> web contracts `71/71`, full integration with all real `linux-cpu` outputs and the HA/chaos tail,
> and routed Playwright `9/9`). The removed validation wrappers are tracked in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md); the full attempt chronology
> lives in [cohort-validation-waves.md](cohort-validation-waves.md).

Phase 1 defines and closes Sprints 1.1 through 1.15 (all Done) around the current repository scaffold, the one-binary role topology,
the staged substrate-file contract, the baked Linux launcher image, the governed
root-document posture, host-manifest materialization, and the native-only Apple Docker boundary
implemented in this worktree. Sprint 1.12 removes the Colima-oriented Apple prerequisite path and
validates the already selected Docker context plus daemon architecture before Docker-backed Apple
work. The supported Apple path must use an already selected native arm64 Docker daemon, must not
create or switch Docker contexts, must not create a Colima VM, and must not use cross-architecture
emulation. The Linux CPU path must support native Linux amd64 and native Linux arm64 without any
non-native compatibility lane.
Sprint 1.11 removes
`INFERNIX_BUILD_ROOT`, `INFERNIX_DATA_ROOT`, the `INFERNIX_COMPOSE_SUBSTRATE` /
`INFERNIX_COMPOSE_DEMO_UI` runtime fallbacks, `INFERNIX_BOOTSTRAP_YES`, the
`bootstrap::prepend_path` helper, and the host-side `.build` / `chart/charts` bind mounts. The
Linux launcher now selects the GPU image through the same single `compose.yaml` service using a
one-shot `LAUNCHER_IMAGE=infernix-linux-gpu:local` Compose selector, and no longer forwards the
host-repo override. It introduces the `HostConfig` decoder type (reflected schema; no tracked `.dhall`) as the Haskell
record. The Linux bootstrap entrypoints now use the `PATH=/usr/bin:/bin` + `BASH_SOURCE` +
`/etc/passwd` + hardcoded absolute-path discovery convention, and the Linux launcher image bakes
the Helm dependency archive cache at `/opt/infernix/chart/charts/` with
`/workspace/chart/charts` linked to that image-local cache for Helm compatibility. Apple cohort
validation closed in Wave A, and the CUDA Linux cohort closed in Wave C with full `linux-cpu` and
`linux-gpu` gates.

Sprint 1.14 closes the Apple build lane reset. It removes the Sprint 1.13 Tart
implementation (`hostTart`, `AppleTart`, and Tart argument builders) from the current host-tool
schema and retargets the retained `infernix internal materialize-metal-engines` command to typed
engine-artifact manifest materialization. The supported Apple Metal/Core ML materialization target
uses a fixed host Metal runtime bridge, typed engine-artifact manifests, and no Tart VM, user
keychain dependency, Xcode UI flow, or request-time toolchain install. The code-side cleanup is
closed for the machine-independent bridge source, manifest, and install-root contract. The
2026-06-16 Apple host refresh built `./.build/infernix`, staged `apple-silicon`, materialized the
typed Metal/Core ML engine manifests, proved the generated Metal bridge smoke
(`Metal runtime probe passed on Apple M1 Max`), proved the installed `coreml-native` runtime-load
smoke (`Core ML runtime probe passed`), and reran the local unit, lint, docs, focused
`lint files/docs/proto/chart`, routed e2e, and aggregate `test all` gates against the former
validation-wrapper state. Sprint 1.15 replaces those wrapper payloads with real Apple native runner
roots and is closed by Wave L; Sprint 1.14 remains `Done` as the Tart-free
manifest-materialization reset.

## Current Repo Assessment

The repo matches the supported Phase 1 ownership contract: the control plane has a
Haskell command registry, the governed root docs point at canonical
`documents/` topics with explicit metadata, and the Linux launcher uses a baked image snapshot.
Lifecycle and validation commands
stage or verify `infernix.dhall` under the active build root through binary-owned
preflight, while explicit helper invocations remain available for direct inspection or restaging.
The Linux substrate Dockerfile also materializes a build-arg-selected copy inside the image
overlay during image build, supported Compose runs keep the Linux build root in the image
overlay rather than bind-mounting the host `./.build/` tree, and the Helm chart archive cache
lives in the image overlay at `/opt/infernix/chart/charts/`. Sprint 1.12 removes the Colima tool
field from the `HostConfig` decoder type and the matching Haskell records, removes `AppleColima`
planning and profile start/stop/restart behavior from `src/Infernix/HostPrereqs.hs`, and adds
unit-level Docker-boundary coverage for native arm64 versus non-native daemon architectures.
The Wave A Apple Silicon validation closed the full positive lifecycle and negative
no-daemon boundary gates named below. The Sprint 1.13 Tart helper, `hostTart` field, and
`AppleTart` prerequisite are no longer part of the current host-tool schema or prerequisite path.
The supported Apple build contract keeps the host free of Xcode and moves Metal/Core ML
materialization to the Sprint 1.14 headless host bridge and typed engine-artifact manifest model.

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

None. The Tart-specific implementation is removed by Sprint 1.14 and recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) as completed cleanup.

---

## Sprint 1.14: Apple Headless Metal/Core ML Materialization Reset [Done]

**Status**: Done
**Code-side closure**: Complete for the machine-independent scope — the `hostTart` host-manifest field, `HostTool.HostTart`, `AppleTart` prerequisite, and Tart argument builders are removed; the retained `infernix internal materialize-metal-engines` command writes typed engine-artifact manifests under `./.data/engines/<adapterId>/` through temp-root write, smoke-manifest validation, Darwin payload-smoke validation for materialized Apple payloads, and atomic rename; the `apple-metal-runtime-bridge` artifact materializes the fixed Objective-C/C bridge source plus `bin/infernix-apple-metal-bridge-smoke`, which compiles the bridge with `/usr/bin/clang`, links Metal/Foundation at materialization-smoke time, calls `MTLCreateSystemDefaultDevice`, compiles MSL through `newLibraryWithSource`, dispatches a tiny kernel, and returns a typed diagnostic; and `coreml-native` materializes `bin/coreml-runner` plus Objective-C smoke source that links Foundation/CoreML and instantiates `MLModelConfiguration`. Proven by `./bootstrap/linux-cpu.sh build`, rebuilt-image `infernix test unit`, and mounted live-source `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `cabal run exe:infernix -- lint docs`, and `cabal run exe:infernix -- docs check` through the Linux outer-container lane; the 2026-06-16 Apple host refresh also proves `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`, `./.build/infernix internal materialize-substrate apple-silicon`, `./.build/infernix internal materialize-metal-engines`, installed Metal and Core ML smoke commands, direct Apple native validation-runner output for `llama-cpp-cli` and `jvm-native`, `./.build/infernix test unit` (Haskell unit plus PureScript 71/71), `./.build/infernix test lint`, `./.build/infernix docs check`, and focused `./.build/infernix lint files/docs/proto/chart`. The former deterministic Apple native runner payloads are superseded by Sprint 1.15.
**Cohort gate**: Closed under the Section Q single-accelerator rule — the chosen accelerator is `apple-silicon`, and the 2026-06-16 Apple host evidence proves Tart-absent manifest materialization, generated Metal bridge smoke, installed `coreml-native` runtime-load smoke, focused e2e, and aggregate `./.build/infernix test all` for the Sprint 1.14 reset scope. The native `linux-cpu` lane supplies the non-accelerator support evidence for the foundation surface; Sprint 1.14 has no `linux-gpu` Metal/Core ML validation surface. Real Apple native payloads and routed real-output proof are owned by Sprint 1.15 / Wave L.
**Implementation**: `documents/engineering/apple_silicon_metal_headless_builds.md`, `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/HostConfig.hs`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/build_artifacts.md`, `documents/operations/apple_silicon_runbook.md`, `documents/architecture/configuration_doctrine.md`, `documents/engineering/host_tools_manifest.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace the Sprint 1.13 Tart VM build target with a truly headless Apple materialization lane.
The replacement path must not require Tart, user keychain state, host Xcode UI flows, the offline
`metal` compiler, or request-time SwiftPM/package builds.

### Deliverables

- add a fixed host Metal runtime bridge that can probe `MTLCreateSystemDefaultDevice`, compile MSL
  through `MTLDevice.makeLibrary(source:options:)`, dispatch a small kernel, and return a typed
  diagnostic
- add typed engine-artifact manifests for Apple native payloads under `./.data/engines/<adapterId>/`
  with digest, source reference, runtime fingerprint, entrypoint, and smoke command fields
- change Apple materialization so it writes into a temporary root, smoke-validates the manifest
  contract, and atomically renames into the final engine root
- remove `AppleTart` prerequisite reconciliation, `hostTart` as a supported host-tool field, and
  the Tart-backed `materialize-metal-engines` implementation while retaining the command as the
  new headless materialization surface
- keep full Xcode out of the host runtime path; any artifact that still truly requires full Xcode
  remains an explicit residual rather than a supported headless claim

### Validation

- unit coverage for manifest rendering, atomic install-root selection, and failure cleanup
- Apple cohort probe proving the Metal bridge compiles and dispatches MSL from source without Tart
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
**Code-side closure**: Complete and validated 2026-06-26 on the Apple host. The
`infernix_emit_validation_result` validation-wrapper fabrication is deleted; generated Apple runners
preserve the full native worker contract, enforce model-cache readiness, and return only real native
engine output or non-zero failure. `llama-cpp-cli` and `whisper-cpp-cli` delegate to the Homebrew
Metal-capable CLIs; `ctranslate2-native`, `onnx-runtime-native`, and `mlx-native` hydrate per-engine
Apple arm64 venvs; `coreml-native` hydrates Basic Pitch plus Apple's Core ML Stable Diffusion
pipeline; `jvm-native` downloads the pinned Audiveris macOS arm64 DMG and installs `Audiveris.app`;
`audio-basic-pitch-coreml` is package-backed; and the Core ML Stable Diffusion row uses a Hugging Face
Core ML snapshot plus an indexed native snapshot hydration path. Proven by
`./bootstrap/apple-silicon.sh build`, `./.build/infernix internal materialize-substrate apple-silicon`,
`./.build/infernix internal materialize-metal-engines`, installed runner smokes (Metal bridge, Core ML,
CTranslate2, MLX, ONNX Runtime, Audiveris), direct Core ML package imports, `./.build/infernix test unit`,
and `./.build/infernix test lint`.
**Cohort gate**: [Wave L](cohort-validation-waves.md) closed 2026-06-29 — Apple integration and
focused routed Playwright real-output gates are green, and the paired `linux-cpu` full routed
real-output gate passed on the real Linux host with rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`. The closing
`./bootstrap/linux-cpu.sh test` run passed Haskell style, Python `check-code`, Haskell unit,
generated web contracts (`71/71`), full integration with all real `linux-cpu` catalog outputs and
the HA/chaos tail, and routed Playwright `9/9` including the 22.7-minute per-model browser matrix.

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

## Sprint 1.16: Evidence and Command Kernels [Active]

**Status**: Active — code-side closed 2026-07-16 (machine-independent); cohort gate pending
**Code-side closure**: closed 2026-07-16 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit` (the readiness / lease / subprocess kernel assertions pass), and
`cabal test infernix-haskell-style` (ormolu + hlint + cabal-format clean) all green on the
apple-silicon lane; `infernix lint docs` unaffected. No Python/native change in this sprint, so
`poetry run check-code` does not apply
**Cohort gate**: pending — apple-silicon plus linux-cpu full-suite, owning wave TBD
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
  them

### Validation

- `cabal build all`, `cabal test infernix-unit`, and `cabal test infernix-haskell-style` clean
- `infernix lint docs` clean, and `poetry run check-code` for any Python/native change
- the code-side gates above exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

- the cohort full-suite sign-off is the residual: the apple-silicon plus linux-cpu full-suite
  cohort gate is pending, with its owning wave still to be assigned
- the kernels use `RankNTypes` region leases (zero-dependency, enabled and in use); surgical
  `LinearTypes` (`%1 ->`) is applied at the spend-once consumer sites in the dependent sprints (the
  lease-gated scrub in Sprint 2.14, the sentinel commit in Sprint 4.28, and the token leases in
  Sprint 9.10), where a spent capability must not be reused — region-scoping already suffices for the
  kernel itself

---

## Remaining Work

Pending: see [Sprint 1.16](#sprint-116-evidence-and-command-kernels-active) for the open
Managed-State-Transition Doctrine reopen work and its pending cohort full-suite sign-off.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/build_artifacts.md` - build roots, generated-artifact doctrine, snapshot launcher expectations, and native engine artifacts under `./.data/engines/<adapterId>/`
- `documents/engineering/apple_silicon_metal_headless_builds.md` - Tart-free Apple Metal/Core ML materialization target, host bridge, manifest fields, and validation gates
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
