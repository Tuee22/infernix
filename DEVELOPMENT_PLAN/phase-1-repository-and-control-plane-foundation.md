# Phase 1: Repository and Control-Plane Foundation

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Establish the canonical repository scaffold, the single `infernix` Haskell
> executable, and the supported host or container operator modes that all later phases build on.

## Sprint 1.1: Canonical Repository Scaffold [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/overview.md`

### Objective

Create the repository skeleton described in [00-overview.md](00-overview.md).

### Deliverables

- root Haskell project files: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `src/Infernix/...`
- the repo-owned `cabal.project` encodes the default host-native Cabal build doctrine, including
  artifact placement under `./.build/`
- `proto/`, `chart/`, `kind/`, `docker/`, `test/`, and `web/` implementation directories, with `documents/` already supplied by Phase 0
- root `.gitignore` and `.dockerignore` files that ignore `./.data/`, `./.claude/`, `./.build/`, generated `.dhall` build artifacts, and repo build artifacts
- no competing `docs/` tree or alternate layout guide in the root README
- one obvious home for service code, one for frontend code, and one for governed docs

### Validation

- `find . -maxdepth 2 -type d | sort` shows the planned top-level directories
- `.gitignore` and `.dockerignore` both exclude `.data/`, `.claude/`, `.build/`, generated `.dhall`, and compiled output paths
- `cabal build exe:infernix` succeeds on Apple Silicon without passing `--builddir` and produces
  `./.build/infernix` via the repo-owned `cabal.project`
- `docker compose run --rm infernix cabal build exe:infernix --builddir=/opt/build/infernix` succeeds on the Linux outer-container path

---

## Sprint 1.2: Single Haskell Binary and CLI Contract [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`
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
| `infernix test lint` | canonical Haskell formatting, lint, and compiler-warning entrypoint |
| `infernix test unit` | canonical unit-validation entrypoint |
| `infernix test integration` | canonical integration-validation entrypoint |
| `infernix test e2e` | canonical browser-validation entrypoint |
| `infernix test all` | canonical full-validation entrypoint aggregating lint, unit, integration, and E2E |
| `infernix docs check` | canonical documentation-validation entrypoint |

Additional rules:

- tests do not ship as standalone Haskell executables
- cluster helpers do not ship as standalone Haskell executables
- the service and CLI logic share one Cabal executable target
- the webapp is a separate binary from `infernix`, built through its own `web/Dockerfile`, and is
  not introduced as a second Haskell executable
- every supported lifecycle, validation, and docs command except `infernix service` is declarative
  and idempotent
- `cluster up` is the only supported cluster reconcile entrypoint
- `cluster down` is the only supported cluster teardown entrypoint
- `cluster status` is read-only and never performs reconciliation side effects
- `infernix kubectl ...` is a wrapper around upstream `kubectl`, not a separate lifecycle command family
- test and docs flows do not introduce parallel imperative setup command families outside this
  surface

### Validation

- `./.build/infernix --help` prints the canonical surface on Apple Silicon
- `docker compose run --rm infernix infernix --help` prints the same surface on the Linux outer path
- `infernix test --help` and `infernix cluster --help` document the supported subcommand families
- CLI help and reference docs describe the declarative semantics of `cluster up`, `cluster down`,
  `cluster status`, `test ...`, and `docs check`, plus the repo-local kubeconfig behavior of
  `infernix kubectl ...`

---

## Sprint 1.3: Dual Operator Execution Contexts [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`

### Objective

Support Apple host-native operation and containerized Linux operation without creating two
different control-plane products.

### Deliverables

- Apple Silicon runs `./.build/infernix` directly on the host and shells out to host-installed `kind`,
  `kubectl`, `helm`, and Docker
- on Apple Silicon, `cluster up` writes `./.build/infernix.kubeconfig` and does not mutate
  `$HOME/.kube/config` or the user's global current context
- `infernix kubectl ...` automatically targets `./.build/infernix.kubeconfig` on Apple host mode and
  the active build-root kubeconfig on other supported paths
- on Apple Silicon, `infernix` may install missing supported host prerequisites including
  Homebrew-installed `poetry` and other required Python dependencies for repo-owned runtime flows
- Linux uses Compose only as a one-command launcher:
  `docker compose run --rm infernix infernix <subcommand>`
- the Compose service forwards the Docker socket and bind mounts `./.data/`
- `docker compose up` and `docker compose exec` do not appear in supported workflow docs

### Validation

- `./.build/infernix cluster status` executes without an outer container on Apple Silicon
- `./.build/infernix cluster up` creates `./.build/infernix.kubeconfig` without mutating
  `$HOME/.kube/config`
- `./.build/infernix kubectl get nodes` works without manually setting `KUBECONFIG`
- Apple host-mode prerequisite checks can install missing `poetry` and other declared Python
  dependencies through the supported operator flow when absent
- `docker compose run --rm infernix infernix cluster status` executes on the Linux outer path
- `docker compose run --rm infernix infernix kubectl get nodes` works without manually setting
  `KUBECONFIG`
- the Linux launcher container sees the Docker socket and the repo-mounted `./.data/` root

---

## Sprint 1.4: Build Artifact Isolation, Haskell Quality Gates, and Web Build Generation Path [Blocked]

**Status**: Blocked
**Blocked by**: `0.1-0.4`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`

### Objective

Keep compiled artifacts out of tracked source paths and establish the webapp build path that
generates frontend contracts without a standalone CLI codegen command, while making Haskell
formatting, linting, and compiler hygiene enforceable through one canonical validation path.

### Deliverables

- the repo-owned `cabal.project` encodes the default host-native Cabal build doctrine, including
  artifact placement under `./.build/`
- supported host-side bare `cabal` invocations inherit those defaults without requiring
  a host-side `--builddir` flag on every command
- Apple host-native command execution uses `./.build/infernix ...`
- Linux outer-container Haskell builds use `--builddir=/opt/build/infernix`
- supported container Cabal entrypoints and Dockerfile `cabal` invocations always inject or enforce
  `--builddir=/opt/build/infernix`
- unqualified bare `cabal` invocations inside the supported container workflow are wrapped,
  rejected, or otherwise prevented from writing build artifacts into the mounted repo tree
- `cluster up` auto-generates `./.build/infernix-test-config.dhall` on Apple and
  `/opt/build/infernix/infernix-test-config.dhall` in the outer-container path
- `cluster up` writes `./.build/infernix.kubeconfig` on Apple and
  `/opt/build/infernix/infernix.kubeconfig` in the outer-container path
- the generated Dhall config enables all models appropriate for the active mode under test
- web build caches and Playwright artifacts live under `./.data/`
- `fourmolu` is the authoritative formatter for repo-owned Haskell source
- `cabal-fmt` is the authoritative formatter for `.cabal` and `cabal.project` files
- `hlint` is configured as the authoritative Haskell lint layer
- repo-owned Haskell validation enables strict compiler warnings and treats warnings as errors
- `infernix test lint` runs `fourmolu --mode check`, `cabal-fmt --check`, `hlint`, and the
  compiler-warning gate on supported paths
- no competing Haskell formatter is introduced
- `web/Dockerfile` is the canonical build entrypoint for the separate webapp binary
- the webapp container build generates frontend contract modules from Haskell SSOT during image build
- no standalone `infernix codegen purescript` command is introduced
- repo validation fails if the webapp build cannot regenerate frontend contract modules from the
  Haskell SSOT or if those contracts drift from the frontend expectations

### Validation

- `find . -maxdepth 2 -name dist-newstyle` returns no repo-owned build tree on the supported paths
- Apple host-native `cabal build exe:infernix` without an explicit `--builddir` places the
  compiled binary under `./.build/infernix`
- a containerized `cabal build exe:infernix` launched through the supported workflow resolves to
  `/opt/build/infernix` rather than creating repo-local build output
- `cluster up` produces the generated test Dhall config in the build-output location for the active execution context
- `cluster up` produces the repo-local kubeconfig in the build-output location for the active
  execution context
- `infernix test lint` passes when formatting, Cabal file layout, lint, and compiler-warning
  checks are satisfied
- intentionally introducing formatting drift, HLint findings, or warning regressions causes
  `infernix test lint` to fail
- a supported webapp image build can regenerate frontend contract modules without writing generated
  artifacts into the tracked repo tree
- `infernix test unit` fails when Haskell and frontend contract expectations are intentionally made
  stale

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - host versus outer-container control-plane rules
- `documents/engineering/build_artifacts.md` - builddir and generated-artifact isolation policy
- `documents/development/haskell_style.md` - formatter, lint, and compiler-warning policy

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - canonical `infernix` CLI
- `documents/reference/cli_surface.md` - subcommand overview
- `documents/README.md` - repository documentation index

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned when the repo scaffold changes
