# AGENTS.md

**Status**: Governed entry document
**Supersedes**: older root-level workflow duplication for automated agents
**Canonical homes**: [documents/README.md](documents/README.md), [documents/documentation_standards.md](documents/documentation_standards.md), [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md), [documents/development/local_dev.md](documents/development/local_dev.md), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

> **Purpose**: Provide a thin automation-oriented entry document that points agents at the
> canonical workflow and implementation-status docs.

Repository instructions for automated agents and LLMs.

Read first:

- [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md)
- [documents/development/local_dev.md](documents/development/local_dev.md)
- [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md)
- [documents/development/no_env_vars.md](documents/development/no_env_vars.md)
- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

## Non-Negotiable Rules

- never run `git add`
- never run `git commit`
- never run `git push`
- keep `DEVELOPMENT_PLAN/` truthful as implementation status changes
- update `README.md`, `AGENTS.md`, and `CLAUDE.md` together when root workflow guidance or the
  supported bootstrap entrypoints change
- run `infernix lint docs` before closing documentation changes, using the active execution
  context: direct `./.build/infernix` only on Apple Silicon, and the Linux outer-container
  launcher for `linux-cpu` or `linux-gpu`
- do not use host `cabal` builds for Linux or CUDA validation; direct
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  is the Apple Silicon host-native reference path only
- never use cross-architecture emulation for development or validation. Do not run amd64 Linux
  through Apple Silicon emulation, and do not create or switch Docker contexts or create a Colima
  VM on Apple Silicon
- on Apple Silicon, the `linux-cpu` and `linux-gpu` outer-container lanes run normally through the
  operator's already-running native arm64 Docker daemon — the Colima Linux VM. Docker schedules the
  launcher container on the Colima VM's native `linux/arm64` kernel (real Linux, not emulation), so
  exercising those lanes from an Apple host via the launcher image and the documented `docker compose`
  reference commands is supported. Keep using the existing daemon: do not create or switch contexts
  or provision a new VM. The `bootstrap/linux-cpu.sh` entrypoint runs directly on Apple Silicon — on
  macOS it resolves the Homebrew Docker CLI and drives the lane through the existing Colima daemon,
  without installing an engine, creating or switching a context, or provisioning a VM. The
  `bootstrap/linux-gpu.sh` entrypoint still targets native Ubuntu 24.04 Linux hosts (NVIDIA driver
  prerequisites); from an Apple host, exercise the GPU container lane through the `docker compose`
  reference path against the existing Colima daemon
- no Haskell `lookupEnv` / `getEnv` / `setEnv` calls in new code; no `proc "<bare-name>"`
  external invocations; no `env:` blocks in infernix-owned chart templates; no `process.env` or
  `os.environ` reads in web / Python code. The supported configuration substrate is the typed
  `.dhall` files documented in [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md);
  the lint enforcement (Phase 6 Sprint 6.28) rejects violations

## Scope

The canonical assistant workflow lives in
[documents/development/assistant_workflow.md](documents/development/assistant_workflow.md). This
root file is only the entry point. Supported stage-0 host bootstrap entrypoints live under
`bootstrap/` and are documented in [README.md](README.md) and
[documents/development/local_dev.md](documents/development/local_dev.md). Those bootstrap
entrypoints are restartable prerequisite reconcilers: they verify same-process tool activation
before continuing, stop at explicit rerun boundaries when a new shell or reboot is required, and
delegate cluster lifecycle, Kubernetes manifests, cluster workload image pulls, Harbor
publication, validation, and teardown behavior to the `infernix` binary.
