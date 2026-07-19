# Assistant Workflow

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md)

> **Purpose**: Define the canonical repository-level workflow rules for automated agents and LLM
> coding assistants.

## Scope

This document is the canonical home for assistant-facing repository workflow rules, including the
full Non-Negotiable Rules list below. `AGENTS.md` and `CLAUDE.md` stay as governed entry documents:
they carry an inline operational mirror of that list (they are auto-loaded by assistant tooling) and
link here, rather than carrying parallel long-form workflow narrative. When a rule changes, update
this list and the two entry-doc mirrors in the same change, and keep the mirrors a faithful subset of
this canonical list.

## Non-Negotiable Rules

**Workflow and Git**

- make requested file changes directly in the working tree; use read-only Git inspection when needed
- never run `git add`, `git commit`, or `git push`
- keep `DEVELOPMENT_PLAN/` truthful as implementation status changes
- use `documents/` as the canonical home for architecture, development, engineering, operations, and
  reference guidance; the root entry docs summarize and link here
- update `README.md`, `AGENTS.md`, and `CLAUDE.md` together when root workflow guidance or the
  supported bootstrap entrypoints change
- run `infernix lint docs` before closing documentation changes, in the active execution context
  (direct `./.build/infernix` on Apple Silicon; the Linux outer-container launcher for `linux-cpu` /
  `linux-gpu`)

**Build and validation**

- keep repo-owned shell limited to the supported `bootstrap/*.sh` stage-0 host bootstrap surface:
  scripts may reconcile prerequisites and build or enter the active launcher, while cluster
  lifecycle, Kubernetes manifests, cluster workload image pulls, Harbor publication, validation,
  and teardown remain `infernix`-owned
- use direct host `cabal` only for the Apple Silicon host-native control plane; do not use host
  `cabal` for Linux or CUDA validation — use the containerized outer-control-plane path
- never use cross-architecture emulation for development or validation; do not create or switch
  Docker contexts or provision a Colima VM on Apple Silicon (the existing native arm64 daemon is used)
- do not install Xcode or rely on Tart for Apple engine work; the Apple Metal/Core ML path is
  headless — see
  [../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md)

**Code invariants (lint-enforced — see the linked doctrine)**

- realness by construction: adapters (`python/adapters/*_python.py`) and native runners
  (`src/Infernix/Engines/{LinuxNative,AppleSilicon}.hs`) return only real model output or raise /
  exit non-zero (→ `status=failed`); no fabrication helpers or failure masks. Canonical:
  [../architecture/realness_contract.md](../architecture/realness_contract.md)
- no environment or PATH reads: no Haskell `lookupEnv`/`getEnv`/`setEnv`, no `proc "<bare-name>"`
  external invocations, no `env:` blocks in infernix-owned chart templates, no `process.env` /
  `os.environ` reads in web/Python code. Canonical: [no_env_vars.md](no_env_vars.md) and
  [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md)
- zero version-controlled `.dhall`: the `infernix` binary is the sole generator of every `.dhall`;
  operators create config with `infernix init` / `infernix test init`; ordinary `infernix`
  commands fail fast if config is missing, while `./bootstrap/apple-silicon.sh up` explicitly runs
  `./.build/infernix init --if-missing` before `cluster up`.
  Canonical: [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md)
- evidence-gated state transitions: every operation that acts on a system state consumes typed
  evidence that its transition completed; the raw destructive, commit, and spawn primitives (the
  retained-state `rm` scrub, the readiness-sentinel commit, and unbounded
  `readCreateProcessWithExitCode`) are unexported, so acting on an unmanaged state does not
  typecheck. Enforcement is GHC export lists plus `-Wall -Werror`. Raw unbounded process spawn is
  forbidden in production `src/Infernix/` outside `Infernix.Cluster.Subprocess.runBoundedCommand`
  (every cluster subprocess runs under a required `Timeout`), enforced by the `unboundedExecViolations`
  lint. Canonical:
  [../architecture/managed_state_transitions.md](../architecture/managed_state_transitions.md)
- no raw unbounded HTTP for upstream model download: the coordinator's upstream model fetch runs only
  through the bounded-HTTP wrapper in `Infernix.Runtime.Pulsar` (a required response timeout and a
  classified `DownloadOutcome`), and raw `withResponse` is forbidden in production `src/Infernix/`
  outside that wrapper, enforced by the `unboundedHttpViolations` lint. Canonical:
  [../architecture/managed_state_transitions.md](../architecture/managed_state_transitions.md)

## Supported Build And Operator Workflows

- prefer the supported stage-0 bootstrap entrypoints:
  `./bootstrap/apple-silicon.sh`, `./bootstrap/linux-cpu.sh`, and `./bootstrap/linux-gpu.sh`
- use direct host builds only for the Apple Silicon host-native control plane:
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
- on supported Linux and CUDA paths, do not build or validate with host `cabal`; use the
  containerized Linux outer-control-plane path through `./bootstrap/linux-cpu.sh`,
  `./bootstrap/linux-gpu.sh`, or
  `docker compose run --rm infernix infernix <command>`; the bootstrap does not manage Kind or
  images directly
- never use cross-architecture emulation for development or validation. `linux-cpu` validation
  belongs on native Linux amd64 or native Linux arm64; Apple Silicon must not run an emulated
  amd64 Linux lane, create or switch Docker contexts, or create a Colima VM
- preserve the distinction between current implementation state and the target platform contract in
  root docs

## Platform Doctrine To Preserve

- keep the Harbor-first bootstrap narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: Harbor and only Harbor-required bootstrap support services may pull upstream before
  readiness, and every remaining non-Harbor workload pulls from Harbor afterward
- keep the PostgreSQL deployment narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the
  Percona Kubernetes operator, even when a chart can self-deploy PostgreSQL, and its PVCs stay on
  the manual `infernix-manual` storage doctrine
- keep the three-runtime build direction and the Kind HA testing or demo-ground direction aligned
- treat the demo UI (served by `infernix-demo`) as a demo surface on that HA substrate while
  preserving the README-matrix coverage ledger; production deployments leave the demo UI off in
  the active `.dhall` and accept inference work via Pulsar subscription only
- routing is owned by Gateway API resources and repo-owned HTTPRoute / SecurityPolicy manifests;
  the demo cluster remains local-only, and when the demo UI is enabled the operator route family
  (`/harbor`, `/pulsar/admin`) is protected by the Keycloak JWT edge policy while
  demo routes keep their application-level JWT checks (MinIO has no external gateway route; the
  webapp `/api/objects` proxy is its only browser-facing surface)
- custom platform logic is Haskell; Python is permitted only under `python/adapters/` and only
  when the bound inference engine has no non-Python binding
- the shared Poetry project lives at `python/pyproject.toml`; all adapter execution goes through
  `poetry run`, and the canonical quality gate is `poetry run check-code`
- on Apple Silicon, the minimal pre-existing host prerequisites are Homebrew plus ghcup. Any
  Docker-backed Apple work must use the already selected native arm64 Docker daemon and must stop
  if that daemon is not available; assistants must not create or switch Docker contexts or create
  Colima VMs
- Apple host paths materialize `python/.venv/` only on demand, after `infernix` bootstraps a
  user-local `poetry` executable after reconciling the Homebrew-managed `python@3.12` formula and
  `python3.12` command when necessary; the Poetry bootstrap may reuse an already available
  compatible Python 3.12+ executable when one passes the implemented version check
- Linux substrate images install adapter dependencies during image build, and Linux host
  prerequisites stop at Docker plus the NVIDIA host prerequisites for `linux-gpu`
- the demo UI is PureScript; frontend contracts are emitted into `web/src/Generated/` by
  `infernix internal generate-purs-contracts`, which derives them through `purescript-bridge`
  from dedicated Haskell browser-contract ADTs in `src/Infernix/Web/Contracts.hs`
- the demo UI is built with spago and tested with `purescript-spec`
- the tracked repository limits repo-owned shell to `bootstrap/*.sh` and carries no committed
  generated artifacts such as Poetry lockfiles, generated protobuf stubs, `*.pyc`,
  `web/spago.lock`, or `web/src/Generated/`

## Validation Before Handoff

- run the repo-local docs validator via `infernix lint docs` before closing documentation changes

## Cross-References

- [local_dev.md](local_dev.md)
- [../documentation_standards.md](../documentation_standards.md)
- [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)
