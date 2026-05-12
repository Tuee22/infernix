# Phase 1: Repository and Control-Plane Foundation

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the canonical repository scaffold, the two-binary topology
> (`infernix` plus `infernix-demo` sharing the default Cabal library exposed by the `infernix`
> package), the supported control-plane execution contexts, the substrate-selection baseline,
> generated-artifact hygiene, and the repository ownership rules that later phases build on.

## Phase Status

Phase 1 is reopened to adopt the Haskell CLI architecture doctrine items it owns, but it is
currently blocked on Phase 0 Sprint 0.9 because the doctrine-distribution docs gate has not
closed yet. Sprints 1.1–1.10 remain `Done`; Sprints 1.11–1.17 stay blocked until that Phase 0
documentation baseline lands.

## Current Repo Assessment

The repo matches the prior Phase 1 ownership contract: the control plane has a Haskell-owned
command registry, the governed root docs point at canonical `documents/` topics with explicit
metadata, the Linux launcher uses a baked image snapshot, and `infernix-substrate.dhall` is staged
under the build root through explicit helper invocations instead of file-absent fallback logic.

What is still missing relative to the new doctrine: the formatter pin and standard library stack
are not present in `infernix.cabal`; `CommandSpec` in `src/Infernix/CommandRegistry.hs` only carries
`commandUsageSuffix` / `commandDescription` / `commandParse` rather than the full doctrine field
set; `System.Process` is called directly from `src/Infernix/Cluster.hs`,
`src/Infernix/HostPrereqs.hs`, `src/Infernix/Lint/*`, and `src/Infernix/Workflow.hs` rather than
through a typed `Subprocess` interpreter; prerequisite checks are imperative inside
`ensureAppleHostPrerequisites`; errors are stringly-typed; Plan/Apply exists only as a localized
`appleSetupPlan`; and `src/Infernix/Lint/Files.hs` enforces forbidden surfaces via hardcoded
lists rather than a `forbiddenPathRegistry`. Sprints 1.11–1.17 close those gaps once Phase 0
Sprint 0.9 clears.

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
- outer-container build output stays under `./.build/outer-container/` through a host-anchored bind mount
- `cluster up` stages `infernix-substrate.dhall` under the active build root
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
- `tools/` no longer carries repo-owned custom-logic Python on the supported path
- Python remains only as the engine-adapter boundary governed by later runtime phases
- repo-owned shell is limited to the supported `bootstrap/*.sh` stage-0 host bootstrap surface

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
**Implementation**: `compose.yaml`, `docker/linux-substrate.Dockerfile`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `web/package.json`, `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`
**Docs to update**: `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `README.md`

### Objective

Move the Linux outer-container story to an image-snapshot launcher model and remove `npx` from the
supported browser workflow.

### Deliverables

- `compose.yaml` runs against a baked image snapshot and bind-mounts `./.data/`, `./.build/`, and `./compose.yaml` together with the Docker socket
- the only outer-container build state surfaced on the host through `./.build/outer-container/build/` is the staged substrate file; the source snapshot manifest lives separately at `/opt/infernix/source-snapshot-files.txt` in the image overlay, and cabal-home plus the cabal builddir stay at the toolchain's natural in-image locations (`/root/.cabal/`, `dist-newstyle/`) and are not bind-mounted, so the supported CLI never overrides cabal's default builddir or `CABAL_DIR`
- the substrate image uses `tini` as its `ENTRYPOINT` for clean signal handling and zombie reaping rather than running a custom launcher wrapper script
- the repo-wide `.:/workspace` bind mount and `web/node_modules` runtime volume are removed
- operators rebuild the image when source changes instead of relying on live repo mounts
- supported Playwright workflows use `npm --prefix web exec -- playwright ...` rather than `npx`

### Validation

- `docker compose run --rm infernix infernix cluster status` works against the host-anchored `./.build/` and `./.data/` bind mounts
- the launcher container sees `./.data/`, `./.build/`, the live `./compose.yaml`, and the Docker socket only
- `docker volume ls` lists no `infernix-build` or `infernix-cabal-home` named volumes
- `docker compose down -v` leaves `./.build/` and `./.data/` intact on the host
- `docker run --rm --entrypoint=cat infernix-linux-cpu:local /etc/os-release` and similar smoke probes show `tini` runs as PID 1 and forwards signals to the wrapped process
- a fresh `docker compose run --rm infernix infernix test unit` against an empty `./.build/outer-container/` succeeds because cabal-home and the cabal builddir live at the toolchain's natural in-image locations and survive the bind mount untouched
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
  CLI reads that file as the primary source of truth for active substrate
- Apple host-native workflows stage `./.build/infernix-substrate.dhall` with
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
- Linux outer-container workflows stage `./.build/outer-container/build/infernix-substrate.dhall`
  through the host-anchored `./.build/` bind mount with
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
- supported runtime, cluster, and validation entrypoints fail fast when the staged file is absent
- Apple Silicon remains the only supported host build path outside a container
- Linux host-native `infernix` execution is not a supported operator surface
- Linux outer-container commands use Compose as the only supported launcher for both `linux-cpu`
  and `linux-gpu`
- Apple operators do not use Compose as a user-facing launcher for ordinary CLI work; Apple E2E
  orchestration invokes `docker compose run --rm playwright` against the dedicated
  `infernix-playwright:local` image during routed E2E validation
- the NVIDIA-backed Linux substrate is standardized as `linux-gpu`, with the old `linux-cuda`
  naming retired as an explicit compatibility cleanup item

### Validation

- `./.build/infernix --help` no longer documents `--runtime-mode`
- `./.build/infernix internal materialize-substrate apple-silicon` stages the active substrate
  without any runtime-mode flag or user-facing environment override
- supported Linux containerized commands run through `docker compose run --rm infernix infernix ...`
  without any runtime-mode flag or user-facing environment override

### Remaining Work

None.

---

## Sprint 1.11: Toolchain Pin and Standard Stack Dependencies [Blocked]

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Implementation**: `infernix.cabal`, `cabal.project`
**Docs to update**: `documents/engineering/implementation_boundaries.md`, `documents/development/local_dev.md`

### Objective

Pin the canonical GHC plus Cabal toolchain and the standard Haskell CLI dependency stack so every
later doctrine item compiles against the same closure.

### Deliverables

- `cabal.project` carries `with-compiler: ghc-9.14.1` as the verified active pin
- `infernix.cabal` declares `tested-with: ghc ==9.14.1` and a `cabal-version` consistent with
  `Cabal 3.16.1.0`
- `infernix.cabal` `build-depends` add the standard stack: `optparse-applicative`, `dhall`,
  `prettyprinter`, `prettyprinter-ansi-terminal`, `ansi-terminal`, `path`, `path-io`,
  `typed-process`, `safe-exceptions`, `co-log` (or `co-log-core`), `async`, `stm`, `tasty`,
  `tasty-hunit`, `tasty-quickcheck`, `tasty-golden`, `temporary`; existing dependencies stay

### Validation

- `cabal build all` resolves the full doctrine dependency set and compiles with the pinned
  compiler
- `cabal test` runs every supported test-suite stanza with the same pin

### Remaining Work

As listed in deliverables until landed.

---

## Sprint 1.12: Typed Command + CommandSpec as Single Source of Truth [Blocked]

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Implementation**: `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`, `documents/reference/cli_reference.md`

### Objective

Extend the existing `CommandSpec` in `src/Infernix/CommandRegistry.hs` to be the single source of
truth for parser generation, help text, generated documentation, JSON command schema, command
tree, and shell completion metadata.

### Deliverables

- `CommandSpec` carries the doctrine's full field set: `name`, `summary`, `description`,
  `children`, `options` (`OptionSpec` with `longName`, `shortName`, `metavar`, `description`,
  `required`), `examples`. The existing `commandUsageSuffix` / `commandDescription` /
  `commandParse` fields fold into the new shape; `commandParse` remains, and the others derive
  from metadata.
- `optparse-applicative` parser, Markdown documentation, `infernix commands --json` JSON command
  schema, `infernix commands --tree` rendering, and shell-completion output all derive from one
  registry.
- `src/Infernix/CLI.hs` hand-built dispatch is replaced by a parser generated from the spec.

### Validation

- `tasty-golden` tests cover `infernix --help`, every subcommand `--help`, `infernix commands
  --tree`, and `infernix commands --json`

### Remaining Work

As listed in deliverables until landed.

---

## Sprint 1.13: Typed Subprocess Values [Blocked]

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Implementation**: `src/Infernix/Subprocess.hs` (new), `src/Infernix/Cluster.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Lint/Files.hs`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Docs.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Lint/Proto.hs`, `src/Infernix/Workflow.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`

### Objective

Move every subprocess invocation behind a typed `Subprocess` value with exactly two IO interpreter
functions.

### Deliverables

- new `src/Infernix/Subprocess.hs` exposes `data Subprocess`, `renderSubprocess :: Subprocess ->
  Text`, `runStreaming :: Subprocess -> IO (Either AppError ExitCode)`, and `capture ::
  Subprocess -> IO (Either AppError ProcessOutput)`
- every `System.Process.proc` / `readCreateProcessWithExitCode` / `readProcess` call site outside
  `Infernix.Subprocess` builds a typed `Subprocess` and hands it to one of the two interpreters
- `--dry-run` on Plan/Apply commands renders deterministic subprocess plans suitable for
  `tasty-golden`

### Validation

- the forbidden-import lint from Sprint 1.17 blocks direct `System.Process` /
  `System.Process.Typed` / `typed-process` imports outside `Infernix.Subprocess`
- golden tests cover `renderSubprocess` output for the cluster reconcile plan

### Remaining Work

As listed in deliverables until landed.

---

## Sprint 1.14: Prerequisites as Typed Effect DAG [Blocked]

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Implementation**: `src/Infernix/Prerequisites.hs` (new), `src/Infernix/HostPrereqs.hs`, command runners under `src/Infernix/CLI.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`

### Objective

Replace ad-hoc prerequisite checks with a typed effect DAG anchored on a single
`prerequisiteRegistry`.

### Deliverables

- new `src/Infernix/Prerequisites.hs` defines `data Validation`, `data PrerequisiteNode`,
  `prerequisiteRegistry :: Map Text PrerequisiteNode`, a pure `transitiveClosure :: [Text] -> Map
  Text PrerequisiteNode -> Either AppError [PrerequisiteNode]`, and `checkPrerequisites :: Env ->
  [PrerequisiteNode] -> IO (Either PrerequisiteFailure ())`
- `ensureAppleHostPrerequisites` and every inline `unless` / `when` prereq check in command
  runners migrate to registry nodes
- failure rendering names `nodeId`, `nodeDescription`, and a remedy hint per the doctrine error
  contract

### Validation

- golden tests cover missing-prereq failure output and registry-error output for stale node
  references
- the DAG gates Phase 2 reconciler pre-flight and Phase 4 daemon `acquire`

### Remaining Work

As listed in deliverables until landed.

---

## Sprint 1.15: AppError ADT, ErrorKind, and Boundary Rendering [Blocked]

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Implementation**: `src/Infernix/Error.hs` (new), `src/Infernix/CLI.hs`, parsers and command runners across `src/Infernix/`
**Docs to update**: `documents/engineering/implementation_boundaries.md`

### Objective

Replace stringly-typed errors with the doctrine's `AppError` ADT and render at the CLI boundary
only.

### Deliverables

- `data AppError = AppError { errorKind :: ErrorKind, errorMsg :: Text, errorCause :: Maybe
  SomeException }` plus `data ErrorKind = Recoverable | Fatal` live in `src/Infernix/Error.hs`
- `renderError :: AppError -> Text` is the only place errors become user-facing text
- `Left String` returns across `src/Infernix/CLI.hs` and parsers convert to typed `AppError`
  values

### Validation

- the `infernix-haskell-style` test-suite rejects `putStrLn` / `print` / `exitFailure` outside
  the CLI dispatch boundary

### Remaining Work

As listed in deliverables until landed.

---

## Sprint 1.16: Plan/Apply Discipline + `--dry-run` / `--plan-file` [Blocked]

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Implementation**: `src/Infernix/Plan.hs` (new), `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Runtime/Cache.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`, `documents/reference/cli_reference.md`

### Objective

Establish the Plan/Apply scaffold every state-changing command uses: pure builder, effectful
interpreter, deterministic renderer.

### Deliverables

- new `src/Infernix/Plan.hs` defines the pattern: pure `build :: Inputs -> Either AppError plan`,
  effectful `apply :: Env -> plan -> IO ExitCode`, and a renderer used by `--dry-run` and
  `--plan-file`
- the existing `appleSetupPlan :: Paths -> [AppleSetupStep]` plus `runAppleSetupStep` in
  `src/Infernix/HostPrereqs.hs` is the generalization seed
- state-changing commands (`cluster up`, `cluster down`, `cache rebuild`, `internal
  materialize-substrate`, and similar) become Plan/Apply pairs
- `--dry-run` and `--plan-file <path>` are required flags on every Plan/Apply command

### Validation

- `tasty-golden` plan-render targets cover every Plan/Apply command
- integration test confirms `--dry-run` exits 0 without mutating cluster or filesystem state

### Remaining Work

As listed in deliverables until landed.

---

## Sprint 1.17: Forbidden Surfaces / Negative-Space Lint [Blocked]

**Status**: Blocked
**Blocked by**: Phase 0 Sprint 0.9
**Implementation**: `src/Infernix/Lint/Files.hs`
**Docs to update**: `documents/engineering/build_artifacts.md`

### Objective

Replace hardcoded path lists in `src/Infernix/Lint/Files.hs` with a single `forbiddenPathRegistry`
and enforce the doctrine's negative-space lint.

### Deliverables

- `forbiddenPathRegistry :: [PathPattern]` in `src/Infernix/Lint/Files.hs` carries the doctrine
  defaults: `.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`,
  `pre-commit-*.yaml`, root `Makefile`, `justfile`, `Taskfile.yml`
- the registry also subsumes the existing `skipDirectories` and `isTrackedGeneratedPath` lists
- error messages name the matched file path, the matched pattern key, and the remedy hint
  (`"delete this path; the canonical equivalent is `infernix <command>`"`)

### Validation

- `infernix lint files` fails when a forbidden file is introduced and passes on the current
  worktree, which contains none of the default forbidden paths

### Remaining Work

As listed in deliverables until landed.

## Remaining Work

- Sprints 1.11–1.17 are all `Blocked` on Phase 0 Sprint 0.9. None of the standard library stack
  pin, full `CommandSpec` expansion, typed `Subprocess` interpreter, prerequisite DAG, typed
  `AppError`, Plan/Apply scaffold, or forbidden-path registry exists yet.

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
