# Phase 1: Repository and Control-Plane Foundation

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the canonical repository scaffold, the two-binary topology
> (`infernix` plus `infernix-demo` sharing `infernix-lib`), the supported control-plane execution
> contexts, the substrate-selection baseline, generated-artifact hygiene, and the repository
> ownership rules that later phases build on.

## Phase Status

Sprints 1.1 through 1.9 remain `Done` as the current implementation baseline, but Phase 1 is
reopened by Sprint 1.10. The worktree still closes around runtime-mode flags, per-mode generated
`.dhall` filenames, a user-facing direct `linux-cuda` launcher, and a Linux host build story that
the new substrate-generated `.dhall` doctrine rejects.

## Current Repo Assessment

The repo still matches the broad Phase 1 ownership contract: the control plane has a Haskell-owned
command registry, the governed root docs point at canonical `documents/` topics with explicit
metadata, the Linux launcher uses a baked image snapshot, and Playwright workflows no longer
depend on `npx`. The remaining Phase 1 gap is doctrinal rather than absent ownership: the CLI and
launcher contract still let the operator think in terms of runtime-mode overrides instead of one
compile-time generated substrate `.dhall`.

## Substrate Foundation

This phase owns the baseline distinction between execution context and substrate.

- execution context answers where `infernix` runs
- the built substrate answers which README matrix engine column is active
- the target substrate ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the current worktree still uses `apple-silicon`, `linux-cpu`, and `linux-cuda` as runtime-mode
  ids until Sprint 1.10 and its follow-ons land

## Remaining Work

- close Sprint 1.10 so build-time substrate selection, launcher ownership, and CLI behavior stop
  depending on `--runtime-mode` and `INFERNIX_RUNTIME_MODE`

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
- both executables link one shared Cabal library `infernix-lib`
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
**Implementation**: `compose.yaml`, `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Service.hs`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`

### Objective

Support Apple host-native operation and containerized Linux operation without creating two
different products.

### Deliverables

- Apple Silicon runs `./.build/infernix` directly on the host and shells out to host-installed
  `kind`, `kubectl`, `helm`, and Docker
- `cluster up` writes `./.build/infernix.kubeconfig` on Apple and does not mutate
  `$HOME/.kube/config`
- `cluster up` writes `./.data/runtime/infernix.kubeconfig` on the Linux outer-container path so
  fresh launcher containers reuse the same durable cluster handle
- `infernix kubectl ...` automatically targets the repo-local kubeconfig on supported paths
- Linux uses Compose only as a one-command launcher:
  `docker compose run --rm infernix infernix <subcommand>`
- `docker compose up` and `docker compose exec` are not supported operator workflows

### Validation

- `./.build/infernix cluster status` executes without an outer container on Apple Silicon
- `./.build/infernix kubectl get nodes` works without manually setting `KUBECONFIG`
- `docker compose run --rm infernix infernix cluster status` executes on the Linux outer path

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
- outer-container build output stays under `/opt/build/infernix/`
- `cluster up` stages `infernix-demo-<mode>.dhall` under the active build root
- the supported web build regenerates frontend contracts, runs `spago build`, and emits
  `web/dist/app.js`
- repo-owned Haskell validation enables strict compiler warnings and treats warnings as errors
- `infernix test lint` and `infernix test unit` are the canonical static-quality and unit entrypoints

### Validation

- `find . -maxdepth 2 -name dist-newstyle` returns no repo-owned build tree on supported paths
- `npm --prefix web run build` regenerates frontend contracts and emits `web/dist/app.js`
- `infernix test lint` fails on docs drift, warning regressions, or build-artifact policy drift

### Remaining Work

None.

---

## Sprint 1.5: Initial Runtime-Mode Selection Baseline [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Types.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Make the current runtime-mode selection baseline explicit so the later substrate-generated `.dhall`
follow-on can replace one clearly named contract instead of inheriting hidden flag behavior.

### Deliverables

- the canonical runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-cuda`
- runtime mode is selected independently of control-plane execution context
- unsupported runtime modes fail with typed user-facing errors
- runtime-mode selection flows into `cluster up`, `service`, and the validation commands

### Validation

- supported host-native and outer-container workflows resolve the active runtime mode correctly
- `cluster status` reports the active runtime mode and publication targets
- unsupported runtime modes fail before reconcile or validation begins

### Remaining Work

None.

---

## Sprint 1.6: Haskell-Owned Control-Plane Tooling [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `src/Infernix/`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Lint/`, `src/Infernix/Python.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Retire custom control-plane Python tooling in favor of Haskell modules under `infernix-lib`.

### Deliverables

- chart discovery, image publication, demo-config loading, docs lint, file lint, proto lint, and
  chart lint are Haskell-owned
- `tools/` no longer carries repo-owned custom-logic Python on the supported path
- Python remains only as the engine-adapter boundary governed by later runtime phases
- the repo carries no repo-owned `.sh` wrappers on the supported path

### Validation

- `find tools -name '*.py' -not -path 'tools/generated_proto/*'` returns no supported
  control-plane Python
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

- generated or disposable artifacts are ignored and rejected from the tracked source set:
  - `python/poetry.lock`
  - `web/spago.lock`
  - everything under `tools/generated_proto/`
  - all `*.pyc` and `__pycache__/` directories
  - `web/src/Generated/`
- `.gitignore` and `.dockerignore` mirror the generated-artifact policy
- `documents/engineering/build_artifacts.md` documents what is source of truth and what is
  regenerated
- `src/Infernix/Lint/Files.hs` fails when tracked generated artifacts return

### Validation

- `git ls-files | grep -E '(poetry\\.lock|generated_proto/|\\.pyc$|__pycache__/|spago\\.lock|web/src/Generated/)'`
  returns nothing
- `infernix test lint` fails when ignored generated paths are re-added to git

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

- one Haskell command-registry foundation owns the supported command inventory, parser entrypoint,
  `--help` output, and CLI-reference lint coverage
- a shared Haskell workflow-helper foundation exists for:
  - npm invocation resolution
  - platform command availability checks
  - shared web-dependency readiness used by both CLI and cluster paths
- later hardening phases may still collapse any remaining helper consumers or literals without
  changing the Phase-1 ownership boundary
- `documents/reference/cli_surface.md` becomes a short family overview that links to the canonical
  CLI reference instead of repeating it
- `README.md`, `AGENTS.md`, and `CLAUDE.md` gain governed metadata and canonical-home links back
  into `documents/`, and the automation entry docs stay thin by pointing at one canonical
  assistant-workflow home under `documents/`

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command families
- `infernix lint docs` fails if the canonical CLI reference drops a supported registry command line
- root-doc workflow summaries point readers at canonical `documents/` topics and carry the governed
  metadata or canonical-home markers needed for later thinning

### Remaining Work

None.

---

## Sprint 1.9: Outer-Container Snapshot Launcher and Playwright Invocation Cleanup [Done]

**Status**: Done
**Implementation**: `compose.yaml`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `web/package.json`, `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`
**Docs to update**: `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `README.md`

### Objective

Move the Linux outer-container story to an image-snapshot launcher model and remove `npx` from the
supported browser workflow.

### Deliverables

- `compose.yaml` runs against a baked image snapshot and bind-mounts only `./.data/`
- the Linux launcher keeps named volumes for `/opt/build` and `/root/.cabal`
- the repo-wide `.:/workspace` bind mount and `web/node_modules` runtime volume are removed
- operators rebuild the image when source changes instead of relying on live repo mounts
- supported Playwright workflows use `npm --prefix web exec -- playwright ...` rather than `npx`

### Validation

- `docker compose run --rm infernix infernix cluster status` works without a repo bind mount
- the launcher container sees `./.data/`, `/opt/build`, `/root/.cabal`, and the Docker socket only
- `npm --prefix web exec -- playwright --version` succeeds on supported paths
- `rg -n 'npx playwright' README.md documents src web/package.json` returns no supported workflow references

### Remaining Work

None.

---

## Sprint 1.10: Build-Time Substrate Selection, Flag Removal, and Launcher Reset [Blocked]

**Status**: Blocked
**Blocked by**: Sprint 0.8
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace user-selected runtime-mode overrides with one compile-time generated substrate `.dhall`
and collapse the launcher story onto the requested Apple-host-native and Linux-Compose doctrines.

### Deliverables

- the supported CLI removes `--runtime-mode` and all use of `INFERNIX_RUNTIME_MODE`
- the build emits one substrate `.dhall` beside the binary and the CLI reads that file as the
  single source of truth for active substrate
- Cabal build rules derive the substrate from build context:
  host build outside the outer container means `apple-silicon`; container build on a
  `nvidia:cuda` base image means `linux-gpu`; every other container build means `linux-cpu`
- Apple Silicon remains the only supported host build path outside a container
- Linux host-native `infernix` execution is not a supported operator surface
- Linux outer-container commands use Compose as the only supported launcher for both `linux-cpu`
  and `linux-gpu`
- Apple operators do not use Compose as a user-facing launcher for ordinary CLI work; Apple E2E
  orchestration may still invoke Compose internally for the Playwright executor
- the NVIDIA-backed Linux substrate is standardized as `linux-gpu`, with the current `linux-cuda`
  naming retired as an explicit compatibility cleanup item

### Validation

- `./.build/infernix --help` no longer documents `--runtime-mode`
- supported Apple host-native commands run without any runtime-mode flag or environment override
- supported Linux containerized commands run through `docker compose run --rm infernix infernix ...`
  without any runtime-mode flag or environment override

### Remaining Work

- Phase 2 still owns ConfigMap publication from the built substrate file
- Phase 4 still owns daemon behavior that consumes and watches that substrate file

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
  when runtime-mode ids, build-root rules, launcher doctrine, or command-registry ownership change
