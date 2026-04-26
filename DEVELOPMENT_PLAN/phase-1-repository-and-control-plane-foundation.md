# Phase 1: Repository and Control-Plane Foundation

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the canonical repository scaffold, the two-binary topology
> (`infernix` plus `infernix-demo` sharing `infernix-lib`), the supported control-plane execution
> contexts, the runtime-mode selection baseline, the PureScript web build path, and the Python
> adapter quality gate that all later phases build on.

## Phase Status

Sprints 1.1, 1.3, 1.4, 1.5, and 1.6 are now `Done`: the repository scaffold, two-binary build
roots, web build-generation path, runtime-mode naming contract, and Haskell-owned tooling
migration are all in place. Sprint 1.2 remains `Active` because `infernix service` still
advertises the final Pulsar-consumer contract while `src/Infernix/Runtime/Pulsar.hs` remains a
placeholder loop.

## Current Repo Assessment

The Haskell project, repo-local build and data roots, runtime-mode selection, generated demo-config
staging, direct `cabal` host install path, Apple-host kubeconfig contract, Haskell-owned lint and
internal helpers, Haskell chart discovery and publication, Haskell edge and gateway entrypoints,
the Haskell demo HTTP surface, and the PureScript build or test path under `web/` are
implemented. The repo now ships two executables (`infernix` plus `infernix-demo`), exposes the
broader CLI surface through those executables, carries a repo-root `python/` Poetry scaffold, and
keeps `tools/` narrowed to the adapter quality shim. The remaining work in this phase is the
final production `infernix service` consumer behavior from Phase 4.

## Runtime-Mode Foundation

This phase owns the baseline distinction between execution context and runtime mode.

- execution context answers where `infernix` runs
- runtime mode answers which README-matrix engine column is active
- the canonical runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-cuda`
- later phases consume those ids when staging and publishing `infernix-demo-<mode>.dhall`,
  building UI catalog state, selecting runtime bindings, and reporting test results

## Sprint 1.1: Canonical Repository Scaffold [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `app/Demo.hs`, `src/Infernix/`, `compose.yaml`, `docker/`, `python/`, `tools/python_quality.sh`, `web/`, `chart/`, `kind/`, `proto/`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/overview.md`

### Objective

Create the repository skeleton described in [00-overview.md](00-overview.md).

### Deliverables

- root Haskell project files: `infernix.cabal`, `cabal.project`, `app/Main.hs` (entry for
  `infernix`), `app/Demo.hs` (entry for `infernix-demo`), `src/Infernix/...` organized as a single
  `infernix-lib` Cabal library shared by both executables
- the repo-owned build doctrine keeps host-native artifacts under `./.build/`; the current
  implementation does this through direct `cabal` host installs with explicit
  `--builddir=.build/cabal` and `--installdir=./.build` plus `./.build/infernix` and
  `./.build/infernix-demo` materialization
- `proto/`, `chart/`, `kind/`, `docker/`, `test/`, and `web/` implementation directories, with `documents/` already supplied by Phase 0
- `python/` directory under repo root holding `python/pyproject.toml`, `python/poetry.lock`, and
  `python/adapters/<engine>/` (one directory per Python-native inference engine)
- `web/` carries `web/package.json`, `web/package-lock.json`, `web/spago.yaml`,
  `web/src/*.purs` source modules, `web/src/Generated/` (output of
  `infernix internal generate-purs-contracts`), `web/test/*.purs` (`purescript-spec` suites),
  `web/playwright/`, and `web/Dockerfile` (npm-managed PureScript toolchain plus Playwright)
- `tools/` carries only auto-generated `tools/generated_proto/` stubs and a small
  `tools/python_quality.sh` shell shim used by the adapter Dockerfiles; no custom-logic Python
  remains
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
- `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
  succeeds on Apple Silicon and materializes `./.build/infernix` and `./.build/infernix-demo`
- `docker compose run --rm infernix infernix --help` succeeds and materializes the supported
  outer-container launcher contract without creating repo-tree build output

### Remaining Work

None.

---

## Sprint 1.2: Two Haskell Binaries and CLI Contract [Active]

**Status**: Active
**Implementation**: `app/Main.hs`, `app/Demo.hs`, `src/Infernix/CLI.hs`, `src/Infernix/DemoCLI.hs`, `chart/templates/deployment-edge.yaml`, `chart/templates/workloads-platform-portals.yaml`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Make `infernix` the production daemon and operator workflow exe and `infernix-demo` the demo UI
HTTP host exe; keep both as the only supported repo-owned Haskell executables and make them share
one Cabal library `infernix-lib`.

### Deliverables

The canonical supported CLI surface for `infernix` is:

| Command | Contract |
|---------|----------|
| `infernix service` | long-running daemon entrypoint; in production it is a Pulsar consumer that subscribes to request topics named in the active `.dhall` and dispatches each request through the Haskell worker; binds no HTTP port |
| `infernix edge` | long-running entrypoint for the Haskell edge proxy cluster workload |
| `infernix gateway harbor`, `infernix gateway minio`, `infernix gateway pulsar` | long-running entrypoints for the Haskell platform gateway cluster workloads |
| `infernix cluster up` | declaratively reconcile the supported cluster and mandatory local HA topology |
| `infernix cluster down` | declaratively reconcile cluster absence while preserving `./.data/` |
| `infernix cluster status` | read-only cluster and route status |
| `infernix cache status` | read-only manifest-backed derived cache report for the active runtime mode |
| `infernix cache evict` | declaratively remove derived cache state without mutating durable manifests, generated catalog state, or publication state |
| `infernix cache rebuild` | declaratively rebuild derived cache state from durable manifests for the active runtime mode |
| `infernix kubectl ...` | scoped `kubectl` wrapper that automatically targets the repo-local kubeconfig |
| `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart` | canonical static-check entrypoints (Haskell modules under `src/Infernix/Lint/`) |
| `infernix test lint` | canonical static-quality entrypoint, including the Python adapter quality gate (mypy strict, black, ruff strict) |
| `infernix test unit` | canonical unit-validation entrypoint, including `spago test` for `purescript-spec` |
| `infernix test integration` | canonical integration-validation entrypoint |
| `infernix test e2e` | canonical browser-validation entrypoint |
| `infernix test all` | canonical full-validation entrypoint aggregating lint, unit, integration, and E2E |
| `infernix docs check` | canonical documentation-validation entrypoint |
| `infernix internal generate-purs-contracts` | emit the build-generated PureScript contract module into `web/src/Generated/` from the dedicated bridge-owned Haskell contract surface |
| `infernix internal discover {images,claims,harbor-overlay}` | declaratively discover container image references, persistent volume claims, and Harbor overlay images from chart templates |
| `infernix internal publish-chart-images` | declaratively build and publish repo-owned images to Harbor; folds into `infernix cluster up` |
| `infernix internal demo-config {load,validate}` | declaratively load and validate the active mode's `.dhall` demo config |

The canonical supported CLI surface for `infernix-demo` is:

| Command | Contract |
|---------|----------|
| `infernix-demo serve --dhall PATH --port N` | long-running entrypoint for the demo HTTP API host; gated by the `.dhall` `demo_ui` flag and absent from production deployments |

Additional rules:

- tests do not ship as standalone Haskell executables
- cluster helpers do not ship as standalone Haskell executables
- both `infernix` and `infernix-demo` link the shared Cabal library `infernix-lib`
- no third repo-owned Haskell executable may be added without standards revision
- every supported lifecycle, validation, and docs command except `infernix service` and
  `infernix-demo serve` is declarative and idempotent
- `cluster up` is the only supported cluster reconcile entrypoint
- `cluster down` is the only supported cluster teardown entrypoint
- `cluster status` is read-only and never performs reconciliation side effects
- `infernix cache status`, `infernix cache evict`, and `infernix cache rebuild` operate only on
  manifest-backed derived cache state and do not rewrite the generated catalog or publication contract
- `infernix kubectl ...` is the supported Kubernetes-access wrapper; it preserves the repo-local
  kubeconfig contract while delegating the remaining arguments to upstream `kubectl`
- test and docs flows do not introduce parallel imperative setup command families outside this
  surface

### Validation

- `./.build/infernix --help` prints the canonical surface on Apple Silicon
- `infernix test --help`, `infernix cluster --help`, and `infernix cache --help` document the supported subcommand families
- CLI help and reference docs describe the declarative semantics of `cluster up`, `cluster down`,
  `cluster status`, `cache ...`, `test ...`, and `docs check`, plus the repo-local kubeconfig
  behavior and pass-through scope of `infernix kubectl ...`

### Remaining Work

- `infernix service` still resolves the final CLI surface and runtime config contract, but the real
  Pulsar consumer loop owned by `src/Infernix/Runtime/Pulsar.hs` remains open

---

## Sprint 1.3: Dual Operator Execution Contexts [Done]

**Status**: Done
**Implementation**: `compose.yaml`, `docker/infernix.Dockerfile`, `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Service.hs`
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
- on Apple Silicon, the operator workflow has no Python prerequisite. Poetry and a local
  virtual environment materializes only when the Python adapter validation surface is exercised
  explicitly (for example `infernix test unit` or `infernix test all`). `infernix` does not install Poetry as a generic
  platform prerequisite
- supported workflows do not ship repo-owned launcher scripts; Apple host builds use direct
  `cabal` commands and Compose runs the image-installed `infernix` binary
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
**Implementation**: `src/Infernix/CLI.hs`, `src/Generated/Contracts.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `scripts/install-formatter.sh`, `web/`, `test/haskell-style/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`

### Objective

Keep compiled artifacts out of tracked source paths, establish the webapp build path that generates
frontend contracts without a standalone public CLI codegen command, and make repo-owned static
quality and compiler hygiene enforceable through one canonical validation path.

### Deliverables

- host-native Haskell builds use direct
  `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix`
  and materialize `./.build/infernix`
- Apple host-native command execution uses `./.build/infernix ...`
- Linux outer-container Haskell builds use `/opt/build/infernix` through the supported
  `compose.yaml` plus the image-installed `infernix` launcher path
- supported container runtime Cabal entrypoints inject `--builddir=/opt/build/infernix`
- manual bare `cabal` invocations inside the launcher container are unsupported and are not part of
  the governed workflow used to keep build artifacts out of the mounted repo tree
- the supported host and container workflow does not introduce repo-owned scripts or wrappers
- `cluster up` auto-generates `./.build/infernix-demo-<mode>.dhall` on the host path and reports
  the intended `/opt/build/` watched-path contract for later containerized execution contexts
- the daemon looks for the active-mode `.dhall` in the same folder as its binary and actively
  watches it there for changes
- `cluster up` writes `./.build/infernix.kubeconfig` on Apple and reserves
  `/opt/build/infernix/infernix.kubeconfig` for the outer-container path, which the validated
  Compose launcher materializes
- the generated demo config enables every README-matrix row appropriate for the active runtime mode
- the supported web build stages generated PureScript contracts under `web/src/Generated/` and
  writes the runtime asset into `web/dist/app.js`
- repo-owned Haskell validation enables strict compiler warnings and treats warnings as errors
- `infernix test lint` runs `infernix lint files`, `infernix lint chart`, `infernix lint proto`,
  `infernix lint docs`, the Cabal-owned Haskell style gate for `ormolu` or `hlint` or
  `cabal format`, and the compiler-warning gate through `cabal --builddir=.build/cabal build all`
- `web/Dockerfile` is the canonical packaging entrypoint for the separate web image
- the web build generates frontend contract modules from Haskell SSOT during build
- no standalone public frontend codegen command is introduced
- repo validation fails if the web build cannot regenerate frontend contract modules from the
  Haskell SSOT or if those contracts drift from the frontend expectations

### Validation

- `find . -maxdepth 2 -name dist-newstyle` returns no repo-owned build tree on the supported paths
- Apple host-native
  `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix`
  followed by `./.build/infernix --help` succeeds
- `docker compose run --rm infernix infernix --help` succeeds with build output rooted under
  `/opt/build/infernix`
- `cluster up` produces the generated demo `.dhall` file and repo-local kubeconfig in the host
  build-output location for the active runtime mode
- `docker compose run --rm infernix infernix --runtime-mode linux-cpu cluster up` produces
  `/opt/build/infernix/infernix-demo-linux-cpu.dhall` and
  `/opt/build/infernix/infernix.kubeconfig`
- `cabal --builddir=.build/cabal test infernix-haskell-style` passes on the supported host path
- `infernix test lint` passes when repo-owned lint, docs, and compiler-warning checks are satisfied
- intentionally introducing trailing whitespace, docs drift, or warning regressions causes
  `infernix test lint` to fail
- `npm --prefix web run build` regenerates frontend contract modules from Haskell-owned source,
  runs `spago build`, and emits `web/dist/app.js`
- generated frontend contract staging lands in `web/src/Generated/` rather than a tracked
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

---

## Sprint 1.6: Custom-Logic Tooling Migrated to Haskell [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `src/Infernix/`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `scripts/install-formatter.sh`, `docker/`, `tools/python_quality.sh`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Retire every custom-logic `tools/*.py` script in favor of Haskell modules under `infernix-lib`,
exposed through `infernix lint ...` and `infernix internal ...` subcommands. Remove the build-time
Python prerequisite entirely on the supported path; Python remains only under `python/adapters/`
for engine adapters. Per Hard Constraint 13, `tools/` is left holding only auto-generated stubs in
`tools/generated_proto/` and a small `tools/python_quality.sh` shell shim used by the adapter
Dockerfiles.

### Deliverables

- `tools/lint_check.py` is removed; the file-existence and extension checks move to
  `infernix lint files` (`src/Infernix/Lint/Files.hs`) or to a Cabal test target where trivial
- `tools/docs_check.py` is removed; the documentation validation moves to `infernix lint docs`
  (`src/Infernix/Lint/Docs.hs`), extended to forbid the retired-doctrine vocabulary recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) outside that cleanup ledger
- `tools/proto_check.py` is removed; the protobuf validation moves to `infernix lint proto`
  (`src/Infernix/Lint/Proto.hs`)
- `tools/helm_chart_check.py` and `tools/platform_asset_check.py` are removed; both fold into
  `infernix lint chart` (`src/Infernix/Lint/Chart.hs`)
- `tools/discover_chart_images.py`, `tools/discover_chart_claims.py`, and
  `tools/list_harbor_overlay_images.py` are removed; their behavior moves to
  `infernix internal discover {images,claims,harbor-overlay}` under
  `src/Infernix/Cluster/Discover.hs`
- `tools/publish_chart_images.py` is removed; the registry authentication, image publication, and
  retry behavior moves to `infernix internal publish-chart-images`
  (`src/Infernix/Cluster/PublishImages.hs`); folds into the existing `buildClusterImages` and
  `publishClusterImages` flow in `src/Infernix/Cluster.hs`
- `tools/demo_config.py` is removed; demo-config loading and validation moves to
  `infernix internal demo-config {load,validate}` (`src/Infernix/DemoConfig.hs`); the existing
  Haskell config loader is the canonical implementation
- `tools/haskell_style_check.py` is removed; the Haskell style gate becomes a Cabal test target
  that invokes `ormolu`, `hlint`, and `cabal format` directly, plus a `scripts/install-formatter.sh`
  shell shim that downloads the binaries; no Python is involved in validating Haskell code
- `tools/requirements.txt` is removed; no build-time Python remains on the supported path
- `infernix.cabal` is restructured to one `library: infernix-lib` plus
  `executable infernix` plus `executable infernix-demo`, with the new lint and discover modules
  under `infernix-lib`
- `infernix test lint` runs every new Haskell-implemented check plus, when `python/adapters/` is
  present, the strict Python quality gate via `tools/python_quality.sh`

### Validation

- `find tools -name '*.py' -not -path 'tools/generated_proto/*'` returns no results in CI
- `infernix lint files`, `infernix lint docs`, `infernix lint proto`, and `infernix lint chart`
  pass against the supported repo state
- `infernix lint docs` fails when any of the forbidden retired-doctrine phrases appears outside
  `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
- `infernix internal discover images`, `infernix internal discover claims`,
  `infernix internal discover harbor-overlay`, `infernix internal publish-chart-images`, and
  `infernix internal demo-config {load,validate}` produce output equivalent to (or strictly
  preferable to) their previous Python tools on the supported chart and demo-config inputs
- the Haskell style Cabal test target succeeds when the formatter binaries are installed via
  `scripts/install-formatter.sh`
- `infernix test lint` continues to pass on the supported Apple host-native and Linux
  outer-container lanes after the migration
- a clean `infernix cluster up` followed by `infernix test all` succeeds without invoking
  `python3` for any custom-logic build, lint, or cluster lifecycle step

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
