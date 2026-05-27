# Phase 1: Repository and Control-Plane Foundation

**Status**: Active (Sprint 1.11 Linux cohort validated; Apple cohort queued; Sprints 1.1–1.10 Done)
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md)

> **Purpose**: Establish the canonical repository scaffold, the two-binary topology
> (`infernix` plus `infernix-demo` sharing the default Cabal library exposed by the `infernix`
> package), the supported control-plane execution contexts, the substrate-selection baseline,
> generated-artifact hygiene, and the repository ownership rules that later phases build on.

## Phase Status

Phase 1 closed Sprints 1.1–1.10 around the current repository scaffold, the two-binary topology,
the staged substrate-file contract, the baked Linux launcher image, and the governed
root-document posture implemented in this worktree. Phase 1 is now Active again because Phase 0
Sprint 0.9 declared the no-env-var + absolute-path doctrine and Phase 1 owns the host-manifest
materialization that closes that doctrine for the host tool-path surface. Sprint 1.11 is retiring
`INFERNIX_BUILD_ROOT`, `INFERNIX_DATA_ROOT`, the `INFERNIX_COMPOSE_SUBSTRATE` /
`INFERNIX_COMPOSE_DEMO_UI` runtime fallbacks, `INFERNIX_BOOTSTRAP_YES`, the
`bootstrap::prepend_path` helper, and the host-side `.build` / `chart/charts` bind mounts. The
Linux launcher now selects the GPU image through the same single `compose.yaml` service using a
one-shot `LAUNCHER_IMAGE=infernix-linux-gpu:local` Compose selector, and no longer forwards the
host-repo override. It introduces `dhall/InfernixHost.dhall` + the matching `HostConfig` Haskell
record. The Linux bootstrap entrypoints now use the `PATH=/usr/bin:/bin` + `BASH_SOURCE` +
`/etc/passwd` + hardcoded absolute-path discovery convention, and the Linux launcher image bakes
the Helm dependency archive cache at `/opt/infernix/chart/charts/` with
`/workspace/chart/charts` linked to that image-local cache for Helm compatibility. The Apple
bootstrap entrypoint remains queued for the next Apple cohort validation batch so contributors do
not need to switch machines before the Linux-owned slice is complete.

## Current Repo Assessment

The repo matches the supported Phase 1 ownership contract: the control plane has a
Haskell command registry, the governed root docs point at canonical
`documents/` topics with explicit metadata, and the Linux launcher uses a baked image snapshot.
Lifecycle and validation commands
stage or verify `infernix-substrate.dhall` under the active build root through binary-owned
preflight, while explicit helper invocations remain available for direct inspection or restaging.
The Linux substrate Dockerfile also materializes a build-arg-selected copy inside the image
overlay during image build, supported Compose runs keep the Linux build root in the image
overlay rather than bind-mounting the host `./.build/` tree, and the Helm chart archive cache
lives in the image overlay at `/opt/infernix/chart/charts/`.

## Substrate Foundation

This phase owns the baseline distinction between execution context and substrate.

- execution context answers where `infernix` runs
- the built substrate answers which README matrix engine column is active
- the supported substrate ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`

## Sprint 1.1: Canonical Repository Scaffold [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `app/Demo.hs`, `src/Infernix/`, `compose.yaml`, `docker/`, `python/`, `web/`, `chart/`, `kind/`, `proto/`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/overview.md`

### Objective

Create the repository skeleton described in [00-overview.md](00-overview.md).

### Deliverables

- root Haskell project files: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `app/Demo.hs`,
  and a shared `src/Infernix/` library tree
- repo-owned implementation roots for `chart/`, `kind/`, `proto/`, `docker/`, `python/`, `web/`,
  `test/`, and `documents/`
- a repo-owned build doctrine that keeps host-native artifacts under `./.build/`
- a repo-owned durable-state doctrine rooted at `./.data/`
- one obvious home for service code, frontend code, cluster assets, and governed docs

### Validation

- `find . -maxdepth 2 -type d | sort` shows the planned top-level directories
- host builds materialize `./.build/infernix` and `./.build/infernix-demo`
- the repo carries no competing `docs/` tree or alternate root layout contract

### Remaining Work

None.

---

## Sprint 1.2: Two Haskell Binaries and CLI Contract Foundation [Done]

**Status**: Done
**Implementation**: `app/Main.hs`, `app/Demo.hs`, `src/Infernix/CLI.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Service.hs`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Make `infernix` the production daemon and operator executable and `infernix-demo` the demo HTTP
host while keeping both on one shared library.

### Deliverables

- `infernix` is the only supported repo-owned long-running production daemon entrypoint
- `infernix-demo` is the only supported repo-owned demo HTTP host entrypoint
- the supported operator command families close through:
  - `service`
  - `cluster up|down|status`
  - `cache status|evict|rebuild`
  - `kubectl`
  - `lint files|docs|proto|chart`
  - `test lint|unit|integration|e2e|all`
  - `docs check`
- both executables link the default Cabal library exposed by the `infernix` package
  (declared in `infernix.cabal` without an explicit library name and depended on as `infernix`)
- cluster helpers and test helpers do not become extra supported executables

### Validation

- `./.build/infernix --help` prints the supported command families
- `./.build/infernix-demo --help` prints the demo entrypoint
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

- host-native Haskell builds materialize `./.build/infernix` and `./.build/infernix-demo`
- outer-container staged substrate output stays under `/workspace/.build/outer-container/` inside
  the launcher image, while cabal package state and cabal's build directory stay in the image
  overlay
- explicit substrate materialization stages `infernix-substrate.dhall` under the active build
  root; `cluster up` consumes that staged file, republishes it for cluster consumers, and fails
  fast if it is absent
- the supported web build regenerates frontend contracts, runs `spago build`, and emits
  `web/dist/app.js`
- repo-owned Haskell validation enables strict compiler warnings and treats warnings as errors
- `infernix test lint` and `infernix test unit` are the canonical static-quality and unit entrypoints

### Validation

- direct Apple host builds install `./.build/infernix` and `./.build/infernix-demo`; any
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
**Implementation**: `compose.yaml`, `docker/linux-substrate.Dockerfile`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `web/package.json`, `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`
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
**Implementation**: `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/CLI.hs`, `docker/linux-substrate.Dockerfile`, `compose.yaml`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace user-selected runtime-mode overrides with one staged substrate file and collapse the
launcher story onto the requested Apple-host-native and Linux-Compose doctrines.

### Deliverables

- the supported CLI removes `--runtime-mode` and all use of `INFERNIX_RUNTIME_MODE`
- the build or explicit staging flow emits one substrate file under the active build root and the
  CLI reads that file as the primary source of truth for active substrate; the Linux Dockerfile's
  image-local copy is the supported outer-container copy
- Apple host-native workflows stage `./.build/infernix-substrate.dhall` with
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
- Linux outer-container workflows stage
  `/workspace/.build/outer-container/build/infernix-substrate.dhall` inside the launcher image with
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

- `./.build/infernix --help` no longer documents `--runtime-mode`
- `./.build/infernix internal materialize-substrate apple-silicon` stages the active substrate
  without any runtime-mode flag or user-facing environment override
- supported Linux containerized commands run through `docker compose run --rm infernix infernix ...`
  without any runtime-mode flag or user-facing environment override
- supported Linux lifecycle and aggregate test commands use the substrate file materialized in the
  launcher image build root, without a host `.build` bind mount

### Remaining Work

None.

---

## Sprint 1.11: Host Manifest Materialization [Active]

**Status**: Active
**Blocked by**: Phase 0 Sprint 0.9 (Configuration Doctrine declaration)
**Implementation**: `dhall/InfernixHost.dhall` (new), `src/Infernix/Substrate.hs` (extended), `src/Infernix/HostConfig.hs` (new), `src/Infernix/HostTools.hs` (new helper module), `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/DemoCLI.hs`, every `bootstrap/*.sh`, `compose.yaml`, `docker/linux-substrate.Dockerfile`
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

- `dhall/InfernixHost.dhall` schema with the `ToolPaths`, `FilesystemConventions`, and
  `HostExecutionContext` records named in `documents/engineering/host_tools_manifest.md`.
- `HostConfig` typed Haskell record in `src/Infernix/HostConfig.hs`, decoded via the `dhall`
  library at every entry point (`runProductionDaemon`, `clusterUp`, `runDemoApiServer`, every
  `infernix <command>`).
- `runHostTool :: HostConfig -> HostTool -> [String] -> IO a` helper module
  `src/Infernix/HostTools.hs`. Every Haskell external-command invocation in this phase's scope
  (`src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/DemoCLI.hs`) routes through
  this helper.
- Materialization helper extended in `src/Infernix/CLI.hs` so `infernix internal materialize-substrate`
  also writes `./.build/infernix-host.dhall` (Apple) or `/opt/infernix/dhall/InfernixHost.dhall`
  (Linux launcher).
- Bootstrap scripts (`bootstrap/common.sh`, `bootstrap/linux-cpu.sh`,
  `bootstrap/linux-gpu.sh`, `bootstrap/apple-silicon.sh`) refactored to the stage-zero convention:
  first line `PATH=/usr/bin:/bin`, repo root from `BASH_SOURCE`, home dir from `/etc/passwd`, every
  pre-binary command by absolute-path constant, post-binary delegation to `./.build/infernix`
  (Apple) or `/usr/bin/docker compose run --rm infernix infernix` (Linux).
- `INFERNIX_BOOTSTRAP_YES` env var replaced by `--yes` CLI flag on each bootstrap script.
- `compose.yaml` shrinks to one `infernix` service with two bind mounts (`./.data` and the
  Docker socket). The `INFERNIX_BUILD_ROOT` and `INFERNIX_HOST_REPO_ROOT` `environment:` entries
  are removed. The `./.build` and `./chart/charts` bind mounts are removed.
- `docker/linux-substrate.Dockerfile` bakes the Helm dependency archive cache into the image at
  `/opt/infernix/chart/charts/` (replacing the previous bind-mount surface). The `ENV
  INFERNIX_BUILD_ROOT=…` directive is removed; the binary discovers its build root via
  `getExecutablePath`.
- Test fixtures in `test/unit/Spec.hs` and `test/integration/Spec.hs` stop calling `setEnv
  "INFERNIX_BUILD_ROOT"` and `setEnv "INFERNIX_DATA_ROOT"`; they pass a typed `HostConfig`
  override instead.

### Validation

- `cabal build all` clean, `infernix test lint` clean, `infernix test unit` clean.
- `grep -rn 'lookupEnv\|getEnv' src/Infernix/{Config,CLI,DemoCLI}.hs` returns zero matches.
- `grep -rn 'INFERNIX_BUILD_ROOT\|INFERNIX_DATA_ROOT\|INFERNIX_COMPOSE_SUBSTRATE\|INFERNIX_COMPOSE_DEMO_UI\|INFERNIX_BOOTSTRAP_YES' src/ bootstrap/ compose.yaml docker/` returns zero matches.
- `./bootstrap/linux-cpu.sh doctor` runs cleanly under `env -i /usr/bin/bash` (empty starting env).
- May 27, 2026: `env -i /usr/bin/bash ./bootstrap/linux-cpu.sh doctor` and
  `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh doctor` both passed after the Linux stage-zero
  bootstrap cleanup.
- May 27, 2026: `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh status` entered the single
  `compose.yaml` launcher with `LAUNCHER_IMAGE=infernix-linux-gpu:local` and reported the
  expected `linux-gpu` `cluster-absent` status without requiring `compose.linux-gpu.yaml`.
- May 27, 2026: `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh build` produced the
  `infernix-linux-gpu:local` launcher image, ran the built-in `infernix --help` smoke check
  through the single `compose.yaml` launcher, and a direct `docker run --rm
  infernix-linux-gpu:local ...` inspection verified `/workspace/chart/charts` links to
  `/opt/infernix/chart/charts` and the expected Helm archives are present without a bind mount.
- `docker inspect <launcher-container> --format '{{json .Mounts}}'` shows exactly two mounts:
  `./.data` and `/var/run/docker.sock`.

### Remaining Work

Foundational pieces landed:

- `dhall/InfernixHost.dhall` schema with the typed `ToolPaths`,
  `FilesystemConventions`, and `HostExecutionContext` records.
- `src/Infernix/HostConfig.hs` — typed `HostConfig` Haskell record,
  Dhall decoder, renderer, and supported defaults for both Apple
  host-native and Linux outer-container execution contexts.
- `src/Infernix/HostTools.hs` — closed `HostTool` enumeration plus the
  `hostToolPath`, `runHostTool`, `runHostToolWithCwd`, `readHostTool`,
  `readHostToolWithExitCode`, and `hostToolProcess` helpers that the
  later sprints will use to route every external invocation through
  `HostConfig` instead of bare-name `proc` calls.
- `src/Infernix/DemoConfig.hs.materializeHostManifestFile` writes the
  manifest beside the substrate file on `infernix internal
  materialize-substrate`; the CLI also prints `hostManifestPath`.
- `test/unit/Spec.hs.assertHostConfig` covers decoder roundtrip +
  tool-path lookup + the absent-tool empty-path convention.

Verified end-to-end on the host: `infernix internal materialize-substrate
apple-silicon` writes `./.build/infernix-host.dhall` with the Apple
defaults. `infernix test lint`, `infernix test unit` (70/70 tests),
`infernix lint files|chart|docs|proto` all exit zero.

Haskell-side env-var retirement landed (May 24, 2026):

- `src/Infernix/Config.hs` `discoverPaths` now consumes an optional
  `HostConfig` (loaded via the new `tryLoadHostManifest` candidate-list
  walk: `<repo>/.build/infernix-host.dhall`, the Linux outer-container
  bind-mount location, and `/opt/infernix/dhall/InfernixHost.dhall`).
  Convention defaults still apply when the manifest is absent so
  first-run bootstrap remains workable. `INFERNIX_BUILD_ROOT` and
  `INFERNIX_DATA_ROOT` env reads removed.
- `src/Infernix/Config.hs.targetRuntimeModeForExecutionContext`
  no longer reads `INFERNIX_COMPOSE_SUBSTRATE`. The outer-container
  branch decodes the active substrate from the staged
  `infernix-substrate.dhall` file (the Dockerfile bakes that file at
  image build time) or fails with the supported `missingGeneratedSubstrateFileError`
  diagnostic.
- `src/Infernix/CLI.hs.configuredRuntimeMode` collapses to a direct
  call into `targetRuntimeModeForExecutionContext`; the duplicate
  `INFERNIX_COMPOSE_SUBSTRATE` read and the `INFERNIX_COMPOSE_DEMO_UI`
  read in `defaultDemoUiEnabled` are deleted. The supported flow
  exposes the demo-UI selector via the
  `infernix internal materialize-substrate --demo-ui true|false`
  flag, not an env override.
- `src/Infernix/CLI.hs.ensureActiveSubstrateFile` no longer
  auto-materializes the substrate file on first run; it reads the
  staged file and surfaces a typed diagnostic when absent. The
  Dockerfile's `infernix internal materialize-substrate` build step
  and the Apple bootstrap script keep the file present on the
  supported paths.
- `src/Infernix/Config.discoverPathsWithHostManifest` exposes
  fixture-driven discovery for tests; Sprint 6.28 codifies the lint
  gate that forbids new `setEnv`/`unsetEnv` regressions.
- `test/unit/Spec.hs` replaces the `withOptionalEnv "INFERNIX_BUILD_ROOT"`
  and `withTestRoot` `setEnv "INFERNIX_DATA_ROOT"` patterns with two
  typed `HostConfig` fixtures (`hostNativeUnitTestFixture`,
  `linuxOuterContainerUnitTestFixture`) that route every test-time
  `Paths` value through `discoverPathsWithHostManifest`.

Infra-side cleanup landed (May 24, 2026; Linux compose-image selection tightened May 27, 2026):

- `compose.yaml` shrunk: the `infernix` service drops the previous
  `build:` block, the `environment:` block, and the `./.build` /
  `./chart/charts` / `./compose.yaml` bind mounts. The service now
  defaults to the CPU launcher image, and bind-mounts exactly
  `./.data:/workspace/.data` and `/var/run/docker.sock`. The GPU lane
  selects `infernix-linux-gpu:local` by setting `LAUNCHER_IMAGE` for
  the Docker Compose process only, keeping CPU hosts on the smaller
  Ubuntu-based snapshot without adding a second Compose file. Sprint
  3.10 deleted the old Playwright sidecar service together with its
  Dockerfile and the matching `runEndToEnd` refactor.
- `docker/linux-substrate.Dockerfile`: removed the
  `ENV INFERNIX_BUILD_ROOT=/workspace/.build/outer-container/build`
  directive. The supported in-image build root is now the convention
  default `/workspace/.build`, discovered by `discoverPaths` via the
  cwd-walk plus the optional host-manifest lookup. The `mkdir -p`
  before the materialize-substrate step targets `/workspace/.build`
  directly.
- `bootstrap/common.sh`: replaced `INFERNIX_BOOTSTRAP_YES` env
  consumption with a typed `BOOTSTRAP_ASSUME_YES` script-local flag,
  set via the new `bootstrap::parse_yes_flag` helper that pops a
  leading `--yes` from each entrypoint's argv.
- `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`:
  `compose_run` passes `--project-name` and explicit `--file`
  arguments to Docker Compose instead of setting compose-control env
  vars; the substrate is fed exclusively via the `build_launcher_image`
  helper that invokes `docker build --build-arg RUNTIME_MODE=…`
  directly (compose.yaml has no `build.args:` block per the standards).
  `command_build` calls `build_launcher_image` before the smoke-test
  `infernix --help`. Both scripts parse `--yes` as the first argument.
- `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, and
  `bootstrap/common.sh`: Linux entrypoints now reset
  `PATH=/usr/bin:/bin` before any setup work, resolve the script root
  from `BASH_SOURCE`, derive the effective user/home from
  `/etc/passwd` via `getent`, and route Docker / apt / sudo / dpkg /
  NVIDIA / file-utility calls through explicit `/usr/bin` or
  `/usr/sbin` constants. They no longer depend on `$USER`, `$HOME`,
  `$PATH`, or `command -v` on the Linux lane.

Verified end-to-end on the host: `cabal build all`, `cabal test
infernix-unit`, `cabal test infernix-haskell-style`, and
`cabal run infernix -- lint {files,chart,docs,proto}` all exit zero.
The single-file Compose selector renders `infernix-linux-cpu:local`
by default and `infernix-linux-gpu:local` when `LAUNCHER_IMAGE` is set
for the Compose process.
The Sprint 1.11 forbidden-env grep gate
(`grep -rEn 'INFERNIX_BUILD_ROOT|INFERNIX_DATA_ROOT|INFERNIX_COMPOSE_SUBSTRATE|INFERNIX_COMPOSE_DEMO_UI|INFERNIX_BOOTSTRAP_YES' src/ bootstrap/ compose.yaml docker/`)
returns only documented-retirement comment references. The live Linux
launcher path also passes the targeted grep for the removed compose
selection and host-repo override env names across `bootstrap/`,
`compose.yaml`, `docker/`, and `src/`.

Linux residuals landed and validated May 27, 2026:

- **Move `chart/charts/` cache into the launcher image at
  `/opt/infernix/chart/charts/` — landed and validated May 27, 2026.**
  `docker/linux-substrate.Dockerfile` now fetches Harbor, Percona
  PostgreSQL operator, Percona PostgreSQL database, Pulsar, MinIO, and
  Envoy Gateway archives into `/opt/infernix/chart/charts/` during
  image build, then links `/workspace/chart/charts` to that image-local
  cache so Helm continues to find dependency archives through the
  chart-standard path without a host bind mount.
- **In-image host-manifest baking at
  `/opt/infernix/dhall/InfernixHost.dhall` — landed May 25, 2026.**
  `docker/linux-substrate.Dockerfile` now writes the supported Linux
  outer-container `HostConfig` Dhall manifest to that path before the
  `infernix internal materialize-substrate` invocation. The manifest
  declares `controlPlaneContext = outer-container`, the absolute path
  table for every external tool, and the supported filesystem
  conventions (`buildRoot = /workspace/.build/outer-container/build`,
  `kindRoot = /workspace/.data/runtime/kind`, etc). Without this,
  the binary's `discoverPaths` `tryLoadHostManifest` walk falls
  through to the convention default `buildRoot = repoRoot/.build`,
  the `controlPlaneContext` path-heuristic mis-classifies the
  container as `HostNative`, and the `linux-gpu`
  materialize-substrate step is rejected by
  `ensureSupportedRuntimeModeForExecutionContext`. The fix replaces
  the previously-retired `ENV INFERNIX_BUILD_ROOT=...` directive
  with the typed Dhall manifest the doctrine actually demands.

Pending closure (queued for the Apple cohort validation batch, named so closure status stays
honest):

- **Apple bootstrap script (`bootstrap/apple-silicon.sh`).** Queued
  for the Apple cohort closure batch per the hardware-cohort cadence.
  The shared `bootstrap/common.sh` `--yes` flag wiring already covers
  the Apple lane when that batch runs.

---

## Remaining Work

Sprint 1.11 partially landed (foundational schema + decoder + helper +
materializer + unit tests). The Linux residuals named above are landed and validated; the only
pending closure is the Apple bootstrap script queued for the Apple cohort validation batch.
Sprints 1.1–1.10 closed.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/build_artifacts.md` - build roots, generated-artifact doctrine, and snapshot launcher expectations
- `documents/engineering/docker_policy.md` - host versus outer-container rules and image-snapshot launcher contract
- `documents/engineering/implementation_boundaries.md` - ownership boundaries across Haskell, Python, chart assets, and generated outputs
- `documents/engineering/portability.md` - portable platform rules versus substrate-specific behavior
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
