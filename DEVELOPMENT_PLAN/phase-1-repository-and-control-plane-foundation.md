# Phase 1: Repository and Control-Plane Foundation

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the canonical repository scaffold, the single `infernix` Haskell
> executable, the supported control-plane execution contexts, and the runtime-mode selection
> baseline that all later phases build on.

## Current Repo Assessment

The repository has a Haskell project, a single executable, repo-local build and data roots,
explicit runtime-mode selection, generated mode-specific demo-config staging, Apple host
prerequisite detection for repo-owned Python manifests, a repo-owned `./cabalw` wrapper that keeps
host Cabal output under `./.build/cabal`, build-root-isolated frontend contract staging, and a
repo-owned `ormolu` or `hlint` or `cabal format` style gate wired into `infernix test lint`. The
outer-container launcher, `/opt/build/infernix` artifact doctrine, and frontend contract artifact
isolation are validated, so this phase is closed.

## Runtime-Mode Foundation

This phase owns the baseline distinction between execution context and runtime mode.

- execution context answers where `infernix` runs
- runtime mode answers which README-matrix engine column is active
- the canonical runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-cuda`
- later phases consume those ids when staging and publishing `infernix-demo-<mode>.dhall`,
  building UI catalog state, selecting runtime bindings, and reporting test results

## Sprint 1.1: Canonical Repository Scaffold [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `src/Infernix/`, `compose.yaml`, `docker/`, `web/`, `chart/`, `kind/`, `proto/`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/overview.md`

### Objective

Create the repository skeleton described in [00-overview.md](00-overview.md).

### Deliverables

- root Haskell project files: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `src/Infernix/...`
- the repo-owned build doctrine keeps host-native artifacts under `./.build/`; the current
  implementation does this through the repo-owned `./cabalw` wrapper plus `./.build/infernix`
  materialization
- `proto/`, `chart/`, `kind/`, `docker/`, `test/`, and `web/` implementation directories, with `documents/` already supplied by Phase 0
- `proto/` is the authoritative home for repo-owned `.proto` schemas covering durable runtime
  manifests and Pulsar topic payloads
- root `.gitignore` and `.dockerignore` files that ignore `./.data/`, `./.claude/`, `./.build/`,
  generated mode-specific `.dhall` build artifacts, and repo build artifacts
- no competing `docs/` tree or alternate layout guide in the root README
- one obvious home for service code, one for frontend code, and one for governed docs

### Validation

- `find . -maxdepth 2 -type d | sort` shows the planned top-level directories
- `.gitignore` and `.dockerignore` both exclude `.data/`, `.claude/`, `.build/`,
  `infernix-demo-*.dhall`, and compiled output paths
- `cabal --builddir=.build/cabal build exe:infernix` succeeds on Apple Silicon and materializes
  `./.build/infernix`
- `docker compose run --rm infernix infernix --help` succeeds and materializes the supported
  outer-container launcher contract without creating repo-tree build output

### Remaining Work

None.

---

## Sprint 1.2: Single Haskell Binary and CLI Contract [Done]

**Status**: Done
**Implementation**: `app/Main.hs`, `src/Infernix/CLI.hs`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Make `infernix` the only supported repo-owned Haskell executable.

### Deliverables

The canonical supported CLI surface is:

| Command | Contract |
|---------|----------|
| `infernix service` | long-running daemon entrypoint for the Haskell service |
| `infernix cluster up` | declaratively reconcile the supported cluster and mandatory local HA topology |
| `infernix cluster down` | declaratively reconcile cluster absence while preserving `./.data/` |
| `infernix cluster status` | read-only cluster and route status |
| `infernix kubectl ...` | scoped `kubectl` wrapper that automatically targets the repo-local kubeconfig |
| `infernix test lint` | canonical static-quality entrypoint |
| `infernix test unit` | canonical unit-validation entrypoint |
| `infernix test integration` | canonical integration-validation entrypoint |
| `infernix test e2e` | canonical browser-validation entrypoint |
| `infernix test all` | canonical full-validation entrypoint aggregating lint, unit, integration, and E2E |
| `infernix docs check` | canonical documentation-validation entrypoint |

Additional rules:

- tests do not ship as standalone Haskell executables
- cluster helpers do not ship as standalone Haskell executables
- the service and CLI logic share one Cabal executable target
- the webapp, when split into its own runtime image or process surface, is not introduced as a
  second Haskell executable
- every supported lifecycle, validation, and docs command except `infernix service` is declarative
  and idempotent
- `cluster up` is the only supported cluster reconcile entrypoint
- `cluster down` is the only supported cluster teardown entrypoint
- `cluster status` is read-only and never performs reconciliation side effects
- `infernix kubectl ...` is the supported Kubernetes-access wrapper; it preserves the repo-local
  kubeconfig contract while delegating the remaining arguments to upstream `kubectl`
- test and docs flows do not introduce parallel imperative setup command families outside this
  surface

### Validation

- `./.build/infernix --help` prints the canonical surface on Apple Silicon
- `infernix test --help` and `infernix cluster --help` document the supported subcommand families
- CLI help and reference docs describe the declarative semantics of `cluster up`, `cluster down`,
  `cluster status`, `test ...`, and `docs check`, plus the repo-local kubeconfig behavior and
  pass-through scope of `infernix kubectl ...`

### Remaining Work

None. Runtime-mode selection and generated demo-config semantics are expanded in Sprint 1.5.

---

## Sprint 1.3: Dual Operator Execution Contexts [Done]

**Status**: Done
**Implementation**: `cabalw`, `compose.yaml`, `docker/infernix.Dockerfile`, `docker/infernix`, `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Service.hs`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`

### Objective

Support Apple host-native operation and containerized Linux operation without creating two
different control-plane products.

### Deliverables

- Apple Silicon runs `./.build/infernix` directly on the host and shells out to host-installed
  `kind`, `kubectl`, `helm`, and Docker without changing the supported CLI surface
- on Apple Silicon, `cluster up` writes `./.build/infernix.kubeconfig` and does not mutate
  `$HOME/.kube/config` or the user's global current context
- `infernix kubectl ...` automatically targets `./.build/infernix.kubeconfig` on Apple host mode and
  the active build-root kubeconfig on other supported paths
- on Apple Silicon, `infernix` may install missing supported host prerequisites including
  Homebrew-installed `poetry` and other required Python dependencies for repo-owned runtime flows;
  the current implementation detects repo-owned Python manifests, installs `poetry` through
  Homebrew when those manifests require it, and installs the declared dependencies on the
  supported Apple host path
- Linux uses Compose only as a one-command launcher:
  `docker compose run --rm infernix infernix <subcommand>`
- the Compose service forwards the Docker socket and bind mounts the repo working tree, including
  `./.data/`
- `docker compose up` and `docker compose exec` do not appear in supported workflow docs

### Validation

- `./.build/infernix cluster status` executes without an outer container on Apple Silicon
- `./.build/infernix cluster up` creates `./.build/infernix.kubeconfig` without mutating
  `$HOME/.kube/config`
- `./.build/infernix kubectl get nodes` works without manually setting `KUBECONFIG`
- `docker compose run --rm infernix infernix cluster status` executes on the Linux outer path
- `docker compose run --rm infernix infernix kubectl get nodes` works without manually setting
  `KUBECONFIG`
- `docker compose run --rm --workdir /workspace/web infernix infernix kubectl get nodes` resolves
  the repo root correctly from a nested working directory
- the Linux launcher container sees the Docker socket, repo-mounted working tree, and durable
  `./.data/` root

### Remaining Work

None.

---

## Sprint 1.4: Build Artifact Isolation, Haskell Quality Gates, and Web Build Generation Path [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `tools/lint_check.py`, `tools/haskell_style_check.py`, `web/build.mjs`, `cabalw`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`

### Objective

Keep compiled artifacts out of tracked source paths, establish the webapp build path that generates
frontend contracts without a standalone public CLI codegen command, and make repo-owned static
quality and compiler hygiene enforceable through one canonical validation path.

### Deliverables

- host-native Haskell builds use the repo-owned `./cabalw ...` wrapper, which injects
  `--builddir=./.build/cabal` unless a supported workflow explicitly passes its own builddir, and
  materialize `./.build/infernix`
- Apple host-native command execution uses `./.build/infernix ...`
- Linux outer-container Haskell builds use `/opt/build/infernix` through the supported
  `compose.yaml` plus `docker/infernix` launcher path
- supported container Cabal entrypoints and Dockerfile `cabal` invocations must inject or enforce
  `--builddir=/opt/build/infernix`
- unqualified bare `cabal` invocations inside the supported container workflow are wrapped,
  rejected, or otherwise prevented from writing build artifacts into the mounted repo tree
- `cluster up` auto-generates `./.build/infernix-demo-<mode>.dhall` on the host path and reports
  the intended `/opt/build/` watched-path contract for later containerized execution contexts
- the daemon looks for the active-mode `.dhall` in the same folder as its binary and actively
  watches it there for changes
- `cluster up` writes `./.build/infernix.kubeconfig` on Apple and reserves
  `/opt/build/infernix/infernix.kubeconfig` for the outer-container path, which the validated
  Compose launcher materializes
- the generated demo config enables every README-matrix row appropriate for the active runtime mode
- the supported web build stages generated JavaScript contracts under the active build root
  (`./.build/web-generated/` on the host and `/opt/build/infernix/web-generated/` in the
  outer-container lane) and copies the runtime asset into `web/dist/generated/contracts.js`
- repo-owned Haskell validation enables strict compiler warnings and treats warnings as errors
- `infernix test lint` runs `tools/lint_check.py`, `tools/docs_check.py`, the repo-owned
  `tools/haskell_style_check.py` gate for `ormolu` or `hlint` or `cabal format`, and the
  compiler-warning gate through `cabal --builddir=.build/cabal build all`
- `web/Dockerfile` is the canonical build entrypoint for the separate webapp image scaffold
- the web build generates frontend contract modules from Haskell SSOT during build
- no standalone public frontend codegen command is introduced
- repo validation fails if the web build cannot regenerate frontend contract modules from the
  Haskell SSOT or if those contracts drift from the frontend expectations

### Validation

- `find . -maxdepth 2 -name dist-newstyle` returns no repo-owned build tree on the supported paths
- Apple host-native `./cabalw build exe:infernix` followed by `./.build/infernix --help` succeeds
- `docker compose run --rm infernix infernix --help` succeeds with build output rooted under
  `/opt/build/infernix`
- `cluster up` produces the generated demo `.dhall` file and repo-local kubeconfig in the host
  build-output location for the active runtime mode
- `docker compose run --rm infernix infernix --runtime-mode linux-cpu cluster up` produces
  `/opt/build/infernix/infernix-demo-linux-cpu.dhall` and
  `/opt/build/infernix/infernix.kubeconfig`
- `python3 tools/haskell_style_check.py` passes on the supported host path
- `infernix test lint` passes when repo-owned lint, docs, and compiler-warning checks are satisfied
- intentionally introducing trailing whitespace, docs drift, or warning regressions causes
  `infernix test lint` to fail
- `npm --prefix web run build` regenerates frontend contract modules from Haskell-owned source
- generated frontend contract staging lands in the active build root rather than a tracked
  `web/generated/` path
- `infernix test unit` fails when Haskell and frontend contract expectations are intentionally made
  stale

### Remaining Work

None.

---

## Sprint 1.5: Runtime-Mode Selection and Naming Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Types.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Make runtime-mode selection explicit so later phases can build the active mode's demo catalog,
engine bindings, and test matrix deterministically.

### Deliverables

- the CLI and config layers define the canonical runtime-mode ids `apple-silicon`, `linux-cpu`, and `linux-cuda`
- runtime mode is selected independently of control-plane execution context
- unsupported runtime-mode selections fail with typed, user-facing errors
- runtime-mode selection flows into `cluster up`, `service`, `test integration`, `test e2e`, and `test all`
- status output, watched config location, and generated artifact naming always report the active runtime mode explicitly

### Validation

- Apple host-native workflows resolve the active runtime mode, and
  `docker compose run --rm infernix infernix --runtime-mode linux-cpu cluster status` exposes that
  same contract on the outer-container lane
- `cluster status` reports the active runtime mode and the active demo-config publication target or watched path
- selecting an unsupported or ambiguous runtime mode fails before reconciliation or test execution begins

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - host versus outer-container control-plane rules
- `documents/engineering/build_artifacts.md` - builddir, generated-demo-config staging, watched mount path, and artifact isolation policy
- `documents/development/haskell_style.md` - formatter, lint, and compiler-warning policy
- `documents/architecture/runtime_modes.md` - execution contexts versus runtime modes

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - canonical `infernix` CLI
- `documents/reference/cli_surface.md` - subcommand overview
- `documents/README.md` - repository documentation index

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when runtime-mode ids, build-root rules, or generated-demo-config naming changes
