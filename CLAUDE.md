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
- no repo-owned native implementation source: version-controlled native sources are forbidden,
  including `.c`, `.h`, `.cc`, `.cpp`, `.m`, `.mm`, `.hsc`, C/C++ header variants, CUDA, assembly,
  Metal, Swift, C2HS, and C-- sources. Cabal `c-sources:`, `cxx-sources:`, `asm-sources:`, and
  `cmm-sources:` declarations and Cabal CPP definitions that synthesize a native boundary are
  likewise forbidden.
  Embedding native implementation source or compiler invocations inside Haskell, Python, shell,
  JavaScript, configuration, or generated payload text is the same violation. `infernix lint files`
  enforces these rules; native implementation inside upstream dependencies is allowed. Lifecycle
  locking and bounded subprocess creation/control use public APIs from `filelock`, `process`, and
  `unix` behind internal Haskell modules, never direct FFI declarations, inline C,
  `System.Process.Internals`, or a cosmetic relocation of those unsafe boundaries. Direct
  `foreign import` is forbidden throughout repo-owned Haskell, including observer code. Darwin
  process birth identity is registry-backed Haskell state protected by `filelock`; Apple footprint
  observation is a fixed, bounded public-tool kernel over `/usr/bin/top` and
  `/usr/bin/footprint`, with no caller-supplied command specification. The nonblocking
  exclusive `filelock` token remains enclosed by the rank-2 `Lease s ClusterMutationLocked` region.
  For bounded commands, the parent starts one self-exec anchor through public `System.Process` with
  `close_fds = True`, `create_group = True`, an explicit environment, and ordinary standard-stream
  pipes; the anchor starts and reaps the supervisor, and a total length-bounded typed framed
  protocol plus hidden constructors, a rank-2 session region, and linear phase transitions prevent
  target start before durable activity evidence or reuse and escape of start authority. `close_fds`
  is only bounded because the descriptor space is: `Infernix.DescriptorSpace` lowers the soft
  `RLIMIT_NOFILE` to a 16384 ceiling as the first action of every process image, before the internal
  self-exec dispatch and before any descriptor is opened, because the forked child closes every
  descriptor up to that limit before `exec` — 313 s per spawn at a containerd pod's 1073741816,
  measured. Every spawn kernel observes the bound immediately before `createProcess`, and the
  `unboundedDescriptorSpawnViolations` lint keeps a new `close_fds` surface from skipping it.
  Canonical:
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
- cluster ownership and mutation-position by construction: the persisted cluster state names its owner
  (`ClusterOwner = OperatorOwned | HarnessOwned`) and the raw `clusterDown` teardown consumes typed
  ownership evidence, so a teardown outside a held lifecycle-lock lease does not typecheck and a
  teardown authority can neither escape its region nor be reused. `ClusterTeardownAuthority` is
  indexed by a promoted `ClusterOwner` as well as its lock region, so an authority minted for the
  harness is not the same type as one minted for the operator and cannot be substituted for it — a
  compile-fail fixture pins that. Be precise about what the index does *not* buy: it decides nothing
  about who owns a *live* cluster. That remains a fail-closed evidence check under the same held
  lease — the persisted owner and the live Kind inventory are reread and compared inside the lock —
  so `infernix test all` fails closed on an operator's running cluster by a checked refusal, not by
  GHC. Ownership evidence travels *with* the protected resource: the Kind cluster name is
  machine-global while the lock, reservation, and persisted state are repo-local, so the lifecycle
  records the creating checkout's host-side repo root inside the control-plane node at
  `/etc/infernix/cluster-checkout-identity` and every authorization reads it back and requires
  agreement. Relocating the lock and renaming the cluster were both rejected: neither works inside a
  launcher container, where every checkout is baked with the same in-container repo root, so a
  path-derived identity collides instead of discriminating. The identity resolver fails closed
  rather than reusing the `/workspace` fallback for that reason. A cluster created before the
  identity existed is adoptable by the operator (stamped under the same held lease) and refused to
  the harness, which must prove the slot is its own before tearing it down. The `ClusterLifecycle` machine
  carries a first-class `ClusterMutating` position, so a killed `infernix test all` leaves a persisted,
  detectable, reconcilable dirty cluster (`cluster status` reports the mutation-incomplete phase and the
  next `cluster up` uncordons drained nodes and scales deployments back) rather than a false
  `steady-state`; the test-harness `./infernix.dhall` swap reconciles a leftover `.harness-backup` on
  entry so a crash cannot leave the operator's config clobbered. Canonical doctrine:
  [documents/architecture/managed_state_transitions.md](documents/architecture/managed_state_transitions.md)
- memory-safety by construction rests on the generated typed execution plan: compilation
  mints a resource-indexed `MemoryGrant`, package-owned live observations pair it with the matching
  `Enforcer`, and an inference subprocess can launch only from the resulting opaque
  `ExecutableModel`. The capped-engine kernel bounds actual resident memory to its
  `MemoryCeiling`; a measured breach is a clean `status=failed` `ModelMemoryLimitExceeded`, not a
  fabricated result. The execution authority remains inside the opaque engine capability so
  concurrent reuse is unrepresentable; Apple/Linux CPU observers enforce resident-memory ceilings,
  and Linux GPU execution requires independently indexed RAM and VRAM grants and observers.
  Physical host RAM is a checked `HostMemoryPartition`, every model declares a required positive
  `ModelMemoryFootprint`, and every `InferenceMemoryBudget` names its enforcer.
  Canonical doctrine:
  [documents/architecture/bounded_inference_memory.md](documents/architecture/bounded_inference_memory.md)
  and [documents/architecture/typed_execution_plan.md](documents/architecture/typed_execution_plan.md)
- bounded host memory: the governed Cabal invocation runs under an authority-derived heap ceiling,
  and a ceiling is inseparable from the claimant arithmetic it participates in. The normal
  compiler phase is `jobs × compilerHeap + (jobs + 1) × controlHeap`: one fixed control/helper slot
  per compiler worker plus the live Cabal driver. Native compiler helpers occupy those declared
  slots; on Darwin that reserve is arithmetic and sampled evidence, not a kernel-enforced native
  heap bound. The web dependency install and unit run, the routed end-to-end browser, the Python
  provisioning and adapter images, and the host inference daemon are started by the same validation
  surface and carry no toolchain ceiling; they are host-reserve claimants.
  Inference is one claimant on host RAM; the toolchain is another, and an uncapped `cabal build`
  exhausted a 124.94 GiB development host while the kernel, which selects per process
  and ranked the build below every cluster pod, destroyed 111 pod processes and never touched it.
  Three interactive compiler images this repository never started, holding 44.1, 29.9, and 27.4 GiB,
  later exhausted a 64 GiB host that no account could see them on.
  The compiler runtime reserves 1024.65 GiB of address space by default, so the built executable
  declares a bounded reservation before any memory limit is installable at all. The mechanism is
  resolved per lane and fails closed when unavailable: an existing cgroup maximum bounds the
  aggregate on the Linux container lane, while Darwin has no cgroups and no installable
  address-space ceiling, so no operating-system bound is engaged on that lane at all and what
  remains is Haskell heap caps, bounded concurrency, claimant arithmetic, and sampled evidence.
  The shipped operator CLI and its fixed observer tools are not
  toolchain claimants; they remain in the host reserve and outside the sampled Cabal group. One
  opaque authority serializes its own package-owned child lifecycles, which is narrower than the
  host, so the account is admitted against an observation of available host memory and a census
  finding no toolchain claimant outside this authority's own process tree; either observation
  failing is a refusal naming what it found, and a claimant the census names is refused rather than
  killed. Normal completion trusts and reaps the Cabal scheduler leader;
  only exceptional cleanup signals its still-owned process group, so no normal descendant-absence
  or hard-kill-survival proof is claimed. This does **not** make a host out-of-memory condition
  impossible — native-helper growth beyond its measured
  slot, page cache, kernel slab, the OOM-protected container runtime, and every process infernix did
  not start remain outside the enforced bound, a named foreign claimant is attributed rather than
  measured, and a transient peak between samples is unobserved — and the doctrine names what it does
  not bound rather than overstating the guarantee. Canonical doctrine:
  [documents/architecture/bounded_host_memory.md](documents/architecture/bounded_host_memory.md)
- per-machine fleet topology: the supported shape is multiple machines, each running **exactly one**
  engine process, all consuming the same Pulsar `Shared` pool topic, each with its own model cache
  and its own machine contract naming the pools it serves. One engine per machine is a correctness
  rule, not a scheduling preference — two engines on one box hold two KV caches and two copies of
  every loaded weight, and each independently admits work against the machine's whole observed
  capacity. Member identity fails closed: a daemon that cannot establish which member it is refuses
  to start rather than adopting a default. Memory admission happens on the machine that will
  execute, never on the coordinator, and the capacity it admits against is **observed, never declared**; what that observation reports is the machine's capacity, and availability under a competing claimant is a separate observation owned by the host-memory ledger. Delivery is
  **at-least-once with an effectively-once observable outcome**: acknowledgement follows the terminal
  result, so a machine lost mid-inference costs a redelivery and duplicate compute rather than an
  unanswered request — redelivery is the only recovery path the pipeline has, and no change may
  acknowledge before the terminal event. There is no within-role replication and no repo-owned HA
  topology; `Failover` as a Pulsar *subscription type* survives because it is how Pulsar provides the
  coordination this relies on. Canonical doctrine:
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
  sole generator of every `.dhall` — including the ConfigMap/Secret bodies (Helm only `nindent`s a
  binary-produced string, never renders/parses Dhall). Schemas are reflected from the Haskell
  decoder types. Operators create config with `infernix init` (runtime `./infernix.dhall` + host
  manifest) and `infernix test init` (`./infernix.test.dhall`); help and init are config-independent
  so `init --force` can replace a stale host schema through the closed writer. Ordinary `infernix`
  commands still fail fast if config is missing, naming the init to run;
  `./bootstrap/apple-silicon.sh up` explicitly runs `./.build/infernix init --if-missing` before
  `cluster up`, while its `test` command runs the runtime-mode-specific `init --if-missing` before
  test initialization and `test all`. The test harness generates
  `./infernix.dhall` from `./infernix.test.dhall`, runs, and deletes it. The two files are a
  **contract pair**: `./infernix.dhall` is the system contract every machine holds identically
  (substrate mode plus the pool graph, each pool carrying its own model descriptors), and the
  `machine` block of `./infernix-host.dhall` is this box's contract (default role, engine member
  identities, model-cache quota, and the content digest of the system contract it was generated
  against). The generator writes both together, so a system-contract change moves the digest and
  re-stamps the manifest; a daemon paired with a contract it has never seen refuses to start and
  names `infernix init --force`. The same digest is registered in the Pulsar topic's own
  properties by the coordinator, and a daemon that verifies a disagreeing value is refused. The model set is whatever
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
