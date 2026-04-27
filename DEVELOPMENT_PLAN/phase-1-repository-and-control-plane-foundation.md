# Phase 1: Repository and Control-Plane Foundation

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the canonical repository scaffold, the two-binary topology
> (`infernix` plus `infernix-demo` sharing `infernix-lib`), the supported control-plane execution
> contexts, the runtime-mode selection baseline, generated-artifact hygiene, and the repository
> ownership rules that later phases build on.

## Phase Status

Sprints 1.1 through 1.6 are closed: the repository scaffold, two-binary topology, build-root
discipline, execution-context split, runtime-mode naming contract, and Haskell-owned
control-plane tooling all exist in the worktree. Sprint 1.7 remains `Active` because tracked-index
cleanup is still open. Sprints 1.8 and 1.9 are `Planned` follow-on work that incorporate the DRY
cleanup proposals without changing the earlier foundation narrative.

## Current Repo Assessment

The repo already has the Haskell project, repo-local build and data roots, runtime-mode selection,
generated demo-config staging, direct `cabal` host install path, Haskell-owned chart discovery and
publication, the Haskell demo HTTP surface, and the PureScript build or test path under `web/`.
The open foundation gaps are now the cleanup gaps:

- tracked generated files and deleted legacy paths still appear in `git ls-files`
- the CLI surface, help text, and command docs still have multiple maintenance points
- `compose.yaml` still uses a live repo bind mount and a `web/node_modules` volume
- Playwright workflows still include `npx`
- root guidance is still more repetitive than the governed-doc model wants

## Runtime-Mode Foundation

This phase owns the baseline distinction between execution context and runtime mode.

- execution context answers where `infernix` runs
- runtime mode answers which README matrix engine column is active
- the canonical runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-cuda`
- later phases consume those ids when staging `infernix-demo-<mode>.dhall`, selecting engine
  bindings, building runtime images, and reporting test results

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
**Implementation**: `src/Infernix/CLI.hs`, `src/Generated/Contracts.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `web/`, `test/haskell-style/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`

### Objective

Keep compiled artifacts out of tracked source paths, establish the web build path, and make
static quality enforceable through canonical entrypoints.

### Deliverables

- host-native Haskell builds materialize `./.build/infernix` and `./.build/infernix-demo`
- containerized build output stays under `/opt/build/`
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

## Sprint 1.5: Runtime-Mode Selection and Naming Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Types.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Make runtime-mode selection explicit so later phases can build the active mode's catalog, engine
bindings, and validation matrix deterministically.

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

## Sprint 1.7: Repository Hygiene and Generated-Artifact Doctrine [Active]

**Status**: Active
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

- ignore rules and file-lint enforcement are landed
- repo policy forbids agent-owned staging, so the remaining work is user-owned tracked-index
  cleanup for stale generated artifacts and deleted legacy files

---

## Sprint 1.8: Command Registry, Root Guidance Canonicalization, and Shared Workflow Helpers [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/Workflow.hs`, `documents/reference/cli_reference.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Make the CLI surface derive from one Haskell-owned command registry and reduce root-document drift
by giving each workflow topic one canonical home.

### Deliverables

- one Haskell command registry owns supported command parsing, dispatch, `--help` output, and the
  canonical CLI reference document
- shared Haskell workflow helpers own:
  - web toolchain presence checks
  - `npm --prefix web ci` readiness
  - platform command availability checks
  - shared generated-file banner literals
- `documents/reference/cli_surface.md` becomes a short family overview that links to the canonical
  CLI reference instead of repeating it
- `README.md`, `AGENTS.md`, and `CLAUDE.md` become thinner governed entry docs with explicit
  status or supersession metadata and links into `documents/`

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command families
- changing a command description in the registry changes generated help and the reference doc in
  the same implementation path
- `infernix test lint` fails if root-doc workflow summaries drift from their canonical documents

### Remaining Work

- implementation has not started

---

## Sprint 1.9: Outer-Container Snapshot Launcher and Playwright Invocation Cleanup [Planned]

**Status**: Planned
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

- implementation has not started

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
