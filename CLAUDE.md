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
- keep implementation status and validation receipts aligned in `DEVELOPMENT_PLAN/`
- realness by construction: inference engine adapters (`python/adapters/*_python.py`) and native
  runners (`src/Infernix/Engines/{LinuxNative,AppleSilicon}.hs`) must return only real model output or
  raise / exit non-zero (→ `status=failed`). No fabricated results — no
  `_validation_*`/`*_smoke*`/`*_fallback*` helpers, no hardcoded artifact/base64 constants, no
  `np.zeros`→`session.run`, no print-and-`exit 0` failure masks, no `infernix_emit_validation_result`
  wrapper. The realness lint (`realnessFabricationViolations` in `Infernix.Lint.HaskellStyle` plus the
  `check-code` AST pass) enforces this. Canonical doctrine:
  [documents/architecture/realness_contract.md](documents/architecture/realness_contract.md)
- evidence-gated state transitions: every operation that acts on a system state consumes typed
  evidence that its transition completed. The raw destructive, commit, and spawn primitives — the
  retained-state `rm` scrub, the readiness-sentinel commit, and unbounded
  `readCreateProcessWithExitCode` — are unexported, so acting on an unmanaged state (a race or flake)
  does not typecheck; enforcement is GHC export lists plus `-Wall -Werror`. Raw unbounded process
  spawn is routed through `Infernix.Cluster.Subprocess.runBoundedCommand`; the named exemptions are
  declared carve-outs, not gaps. Canonical:
  [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- no repo-owned native implementation source: no `.c`, `.h`, `.cc`, `.cpp`, `.m`, `.mm`, `.hsc`,
  CUDA, assembly, Metal, Swift, C2HS or C-- source is version-controlled, no Cabal `c-sources:` /
  `cxx-sources:` / `asm-sources:` / `cmm-sources:` stanza declares one, and no `foreign import`,
  inline C, or `System.Process.Internals` use appears in repo-owned Haskell; embedding native source
  or a compiler invocation inside Haskell, Python, shell, JavaScript, configuration, or generated
  payload text is the same violation, while native implementation inside upstream dependencies is
  allowed. `infernix lint files` enforces it. Canonical:
  [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- Apple engine materialization is not a process-spawn exemption: every Poetry, Python/venv,
  exact-package, Audiveris image, installed-smoke, and provenance operation must use the closed
  package-internal provisioning language. Its opaque nominal `ProvisioningGrant s` and indexed
  `ProvisioningSession s result` remain inside a rank-2 region, and only that facade may invoke the
  bounded self-exec kernel. A candidate root must be hydrated, relocated, smoke-validated,
  provenance-recorded, and hashed from its actual payload before the fsynced sibling activation
  transaction; failure, cancellation, and crash reconciliation preserve a complete prior root or
  fail closed. Canonical:
  [documents/engineering/apple_silicon_metal_headless_builds.md](documents/engineering/apple_silicon_metal_headless_builds.md)
- no raw unbounded HTTP for upstream model download: the coordinator's upstream model fetch runs only
  through the bounded-HTTP wrapper in `Infernix.Runtime.Pulsar` (a required response timeout and a
  classified `DownloadOutcome`), and raw `withResponse` is forbidden in production `src/Infernix/`
  outside that wrapper, enforced by the `unboundedHttpViolations` lint. Canonical doctrine:
  [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- cluster ownership and mutation-position by construction: the persisted cluster state names its
  owner, the raw teardown consumes typed ownership evidence indexed by both owner and lock region,
  and the lifecycle machine carries a first-class mutating position, so a teardown outside a held
  lease does not typecheck and a killed run leaves a detectable, reconcilable dirty cluster rather
  than a false steady state. What the index does not decide is who owns a *live* cluster: that is a
  fail-closed evidence check under the same lease, so the harness refuses an operator's running
  cluster by a checked refusal rather than by GHC. Canonical:
  [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- memory-safety by construction: a model's requirement is derived from its artifact's own bytes and
  never authored, it is resource-indexed so host and device are different formulas, compilation
  mints one grant per resource, and an inference subprocess launches only from the resulting opaque
  capability. Enforcement is three non-interchangeable layers — a kernel limit installed before the
  engine's first allocation on the lanes that can install one, a sampled backstop over the residue,
  and the engine reporting the limit it received — and a lane declares the strength it has, with no
  kernel mechanism bounding device memory on any lane. A breach is a clean `status=failed`
  `ModelMemoryLimitExceeded`, never a fabricated result. Canonical:
  [documents/architecture/bounded_inference_memory.md](documents/architecture/bounded_inference_memory.md)
  and [documents/architecture/typed_execution_plan.md](documents/architecture/typed_execution_plan.md)
- bounded host memory: the governed Cabal invocation runs under an authority-derived heap ceiling
  whose claimant arithmetic is `jobs × compilerHeap + (jobs + 1) × controlHeap`, admitted against an
  observed available-memory reading and a census finding no toolchain claimant outside this
  authority's own process tree; either observation failing is a refusal naming what it found. The
  mechanism is resolved per lane and fails closed when unavailable — a cgroup maximum bounds the
  Linux container lane, while Darwin engages no operating-system bound and is left with Haskell heap
  caps, bounded concurrency, claimant arithmetic, and sampled evidence. This does not make a host
  out-of-memory condition impossible, and the doctrine names what it does not bound. Canonical:
  [documents/architecture/bounded_host_memory.md](documents/architecture/bounded_host_memory.md)
- per-machine fleet topology: multiple machines, each running **exactly one** engine process, all
  consuming the same Pulsar `Shared` pool topic, each with its own model cache and machine contract.
  One engine per machine is a correctness rule, not a scheduling preference — two engines on one box
  hold two KV caches and each admits work against the whole observed capacity. Member identity fails
  closed, memory admission happens on the executing machine against observed capacity, and delivery
  is at-least-once with an effectively-once observable outcome, so acknowledgement follows the
  terminal result and no change may acknowledge before it. Canonical:
  [documents/architecture/daemon_topology.md](documents/architecture/daemon_topology.md) and
  [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md)
- review `README.md`, `AGENTS.md`, and `CLAUDE.md` together when repository workflow guidance or
  the supported bootstrap entrypoints change
- run `infernix lint docs` before closing documentation changes, using the active execution
  context: direct `./.build/infernix` only on Apple Silicon, and the Linux outer-container
  launcher for `linux-cpu` or `linux-gpu`
- do not use bare host `cabal` commands for validation. Linux and CUDA use the outer-container
  launcher. Apple clean-clone/rebuild uses `./bootstrap/apple-silicon.sh build`, whose fixed stage-0
  preflight measures physical memory and the active Colima pledge as declared capacity before
  its exact seed-bound Cabal invocation; after `infernix init`, focused Haskell gates run through the closed CLI toolchain
  vocabulary and live derived authority
  ([documents/architecture/bounded_host_memory.md](documents/architecture/bounded_host_memory.md))
- do not install Xcode on the Apple host and do not rely on Tart for new Apple engine work. The
  Apple Metal/Core ML materialization path is headless without VM startup, user keychain
  state, Xcode UI flows, or repo-owned native source: use typed engine-artifact manifests and
  upstream-owned MLX/Core ML package APIs as described in
  [documents/engineering/apple_silicon_metal_headless_builds.md](documents/engineering/apple_silicon_metal_headless_builds.md).
  No `tart` / `hostTart` / `AppleTart` implementation exists; the retained
  `materialize-metal-engines` helper is the Tart-free manifest materialization surface. Validation
  requires upstream MLX GPU operation, Core ML device observation, native load, and routed real output
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
  sole generator of every `.dhall`, including the ConfigMap and Secret bodies, and schemas are
  reflected from the Haskell decoder types. Operators create config with `infernix init` and
  `infernix test init`; ordinary commands fail fast when it is missing, naming the init to run, while
  help and init stay config-independent. `./infernix.dhall` and the `machine` block of
  `./infernix-host.dhall` are a contract pair bound by a content digest, so a daemon paired with a
  contract it has never seen refuses to start. Canonical:
  [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md)

## Scope

The canonical assistant workflow lives in
[documents/development/assistant_workflow.md](documents/development/assistant_workflow.md). This
root file is only the entry point. Supported stage-0 host bootstrap entrypoints live under
`bootstrap/` and are documented in [README.md](README.md) and
[documents/development/local_dev.md](documents/development/local_dev.md). Those bootstrap
entrypoints are restartable prerequisite reconcilers: they verify same-process tool activation
before continuing, stop at explicit rerun boundaries when a new shell or reboot is required, and
delegate cluster lifecycle, Kubernetes manifests, cluster workload image pulls, registry
publication, validation, and teardown behavior to the `infernix` binary.
