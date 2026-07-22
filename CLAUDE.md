# CLAUDE.md

**Status**: Governed entry document
**Supersedes**: older root-level workflow duplication for LLM coding assistants
**Canonical homes**: [documents/README.md](documents/README.md), [documents/documentation_standards.md](documents/documentation_standards.md), [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md), [documents/development/local_dev.md](documents/development/local_dev.md), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

> **Purpose**: Provide a thin automation-oriented entry document that points Claude-style agents at
> the canonical workflow and implementation-status docs.

Instructions for Claude and other LLM-based coding assistants working in this repository.

Read first:

- [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md)
- [documents/development/local_dev.md](documents/development/local_dev.md)
- [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md)
- [documents/development/no_env_vars.md](documents/development/no_env_vars.md)
- [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- [documents/architecture/bounded_inference_memory.md](documents/architecture/bounded_inference_memory.md)
- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

## Non-Negotiable Rules

> These hard-stops are the inline operational mirror of the canonical list in
> [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md); keep the
> mirror and the canonical list in sync when a rule changes.

- never run `git add`
- never run `git commit`
- never run `git push`
- keep `DEVELOPMENT_PLAN/` aligned with the current implementation state
- realness by construction: inference engine adapters (`python/adapters/*_python.py`) and native
  runners (`src/Infernix/Engines/{LinuxNative,AppleSilicon}.hs`) must return only real model output or
  raise / exit non-zero (→ `status=failed`). No fabricated results — no
  `_validation_*`/`*_smoke*`/`*_fallback*` helpers, no hardcoded artifact/base64 constants, no
  `np.zeros`→`session.run`, no print-and-`exit 0` failure masks, no `infernix_emit_validation_result`
  wrapper. The realness lint (`realnessFabricationViolations` in `Infernix.Lint.HaskellStyle` plus the
  `check-code` AST pass), owned by Phase 0 Sprint 0.12 with its per-runner scope extended by Phases 1/4,
  enforces this. Canonical doctrine:
  [documents/architecture/realness_contract.md](documents/architecture/realness_contract.md)
- evidence-gated state transitions: every operation that acts on a system state consumes typed
  evidence that its transition completed. The raw destructive, commit, and spawn primitives — the
  retained-state `rm` scrub, the readiness-sentinel commit, and unbounded
  `readCreateProcessWithExitCode` — are unexported, so acting on an unmanaged state (a race or flake)
  does not typecheck; enforcement is GHC export lists plus `-Wall -Werror`. Raw unbounded process
  spawn is forbidden in production `src/Infernix/` outside
  `Infernix.Cluster.Subprocess.runBoundedCommand` (every cluster subprocess runs under a required
  `Timeout`), enforced by the `unboundedExecViolations` lint. Canonical doctrine:
  [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- no raw unbounded HTTP for upstream model download: the coordinator's upstream model fetch runs only
  through the bounded-HTTP wrapper in `Infernix.Runtime.Pulsar` (a required response timeout and a
  classified `DownloadOutcome`), and raw `withResponse` is forbidden in production `src/Infernix/`
  outside that wrapper, enforced by the `unboundedHttpViolations` lint. Canonical doctrine:
  [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- memory-safety by construction: an inference engine subprocess runs only under a typed `MemoryGrant`
  minted by the `admitModelMemory` admission policy, and the capped-engine kernel bounds its actual
  resident memory to the admitted `MemoryCeiling`. The raw engine spawn
  (`readCreateProcessWithExitCode` / `createProcess`) is unexported, so launching an engine without an
  admission proof does not typecheck; a ceiling breach is a clean `status=failed`
  `ModelMemoryLimitExceeded` rather than a host OOM-kill (`apple-silicon` enforces the ceiling with a
  `proc_pid_rusage` physical-footprint watchdog plus process-group kill, `linux-cpu`/`linux-gpu` by the
  pod cgroup / VRAM limit). Physical host RAM is a checked `HostMemoryPartition` (no oversubscription;
  headroom covers the OS and the routed-E2E browser), every model declares a required positive
  `ModelMemoryFootprint`, and every `InferenceMemoryBudget` names its enforcer. Raw engine spawn outside
  the capped-engine kernel is forbidden, enforced by the `unboundedEngineSpawnViolations` lint.
  Canonical doctrine:
  [documents/architecture/bounded_inference_memory.md](documents/architecture/bounded_inference_memory.md)
- review `README.md`, `AGENTS.md`, and `CLAUDE.md` together when repository workflow guidance or
  the supported bootstrap entrypoints change
- run `infernix lint docs` before closing documentation changes, using the active execution
  context: direct `./.build/infernix` only on Apple Silicon, and the Linux outer-container
  launcher for `linux-cpu` or `linux-gpu`
- do not use host `cabal` builds for Linux or CUDA validation; direct
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  is the Apple Silicon host-native reference path only
- do not install Xcode on the Apple host and do not rely on Tart for new Apple engine work. The
  target Apple Metal/Core ML materialization path is headless without VM startup, user keychain
  state, or Xcode UI flows: use the host Metal runtime bridge and typed engine-artifact manifests
  described in
  [documents/engineering/apple_silicon_metal_headless_builds.md](documents/engineering/apple_silicon_metal_headless_builds.md).
  The legacy `tart` / `hostTart` / `AppleTart` implementation has been removed; the retained
  `materialize-metal-engines` helper is the Tart-free manifest materialization surface, with Apple
  hardware smoke evidence still tracked under Phase 1 Sprint 1.14
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
  `os.environ` reads in web / Python code. The supported configuration substrate is typed `.dhall`
  documented in [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md);
  the lint enforcement rejects violations
- **zero version-controlled `.dhall`**: never commit a `.dhall` file. The `infernix` binary is the
  sole generator of every `.dhall` — including the ConfigMap/Secret bodies (Helm only `nindent`s a
  binary-produced string, never renders/parses Dhall). Schemas are reflected from the Haskell
  decoder types. Operators create config with `infernix init` (runtime `./infernix.dhall` + host
  manifest) and `infernix test init` (`./infernix.test.dhall`); ordinary `infernix` commands fail
  fast if config is missing, naming the init to run, while `./bootstrap/apple-silicon.sh up`
  explicitly runs `./.build/infernix init --if-missing` before `cluster up`. The test harness generates
  `./infernix.dhall` from `./infernix.test.dhall`, runs, and deletes it. The model set is whatever
  the mounted runtime `infernix.dhall` lists (the `src/Infernix/Models.hs` matrix is a demo-only
  generator); the coordinator eager-stages that set at startup. Canonical doctrine:
  [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md)

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
