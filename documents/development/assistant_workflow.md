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
  `cabal` for Linux or CUDA validation — use the containerized outer-control-plane path. Every host
  `cabal` invocation runs under the declared build ceiling
  ([../architecture/bounded_host_memory.md](../architecture/bounded_host_memory.md))
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
- evidence-gated state transitions are the target construction: every operation that acts on a system state consumes typed
  evidence that its transition completed; the raw destructive, commit, and spawn primitives (the
  retained-state `rm` scrub, the readiness-sentinel commit, and unbounded
  `readCreateProcessWithExitCode`) are unexported, so acting on an unmanaged state does not
  typecheck. Enforcement is GHC export lists plus `-Wall -Werror`. Raw unbounded process spawn is
  routed through `Infernix.Cluster.Subprocess.runBoundedCommand`; the named exemptions are declared
  carve-outs, not gaps. Canonical:
  [../architecture/managed_state_transitions.md](../architecture/managed_state_transitions.md)
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
  target start before durable activity evidence or reuse and escape of start authority. Canonical:
  [../architecture/managed_state_transitions.md](../architecture/managed_state_transitions.md)
- Apple engine materialization is not a process-spawn exemption: all Poetry, Python/venv,
  package-install, Audiveris image, installed-smoke, and provenance operations must use the closed
  package-internal provisioning language. An opaque nominal `ProvisioningGrant s` and indexed
  `ProvisioningSession s result` stay inside a rank-2 region, and only the provisioning facade may
  invoke the bounded self-exec kernel. The candidate root must be fully hydrated, relocated,
  smoke-validated, provenance-recorded, and hashed before the fsynced sibling activation
  transaction; synchronous failure, asynchronous cancellation, or crash reconciliation must
  preserve a complete prior root or fail closed. Canonical:
  [../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md)
- no raw unbounded HTTP for upstream model download: the coordinator's upstream model fetch runs only
  through the bounded-HTTP wrapper in `Infernix.Runtime.Pulsar` (a required response timeout and a
  classified `DownloadOutcome`), and raw `withResponse` is forbidden in production `src/Infernix/`
  outside that wrapper, enforced by the `unboundedHttpViolations` lint. Canonical:
  [../architecture/managed_state_transitions.md](../architecture/managed_state_transitions.md)
- cluster ownership and mutation-position by construction: the persisted cluster state names its
  `ClusterOwner` (`OperatorOwned | HarnessOwned`) and `clusterDown` consumes typed ownership evidence, so
  tearing down an `OperatorOwned` cluster does not typecheck (`infernix test all` fails closed on an
  operator cluster instead of destroying it); the `ClusterLifecycle` machine carries a first-class
  `ClusterMutating` position, so a killed `infernix test all` leaves a detectable, reconcilable dirty
  cluster rather than a false `steady-state`, and the test-harness `./infernix.dhall` swap reconciles a
  leftover `.harness-backup` on entry. Canonical:
  [../architecture/managed_state_transitions.md](../architecture/managed_state_transitions.md)
- memory-safety by construction rests on the generated typed execution plan: compilation
  mints a resource-indexed `MemoryGrant`, package-owned live observations pair it with the matching
  `Enforcer`, and an inference subprocess can launch only from the resulting opaque
  `ExecutableModel`. The capped-engine kernel OS-bounds actual resident memory to its
  `MemoryCeiling`; a measured breach is a clean typed `ModelMemoryLimitExceeded`. Apple and Linux CPU
  watchdog implementations are present, but their adversarial proof and an execution authority that
  makes concurrent reuse unrepresentable remain Phase 4 work. NVIDIA enforcement and broad raw-spawn
  exemption removal remain Phase 6 work. Physical RAM is a checked `HostMemoryPartition`, every model
  declares a required `ModelMemoryFootprint`, and every `InferenceMemoryBudget` names its enforcer.
  Canonical:
  [../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md) and
  [../architecture/typed_execution_plan.md](../architecture/typed_execution_plan.md)
- bounded host memory: every host toolchain process runs under a declared ceiling derived from
  measured physical RAM, and a ceiling is inseparable from the concurrency it is multiplied by — a
  per-process cap under `jobs: $ncpus` bounds the host at `jobs × cap`, not at `cap`. Inference is
  one claimant on host RAM; the toolchain is another, and an uncapped `cabal build` exhausted a
  124.94 GiB development host. The compiler runtime reserves 1024.65 GiB of address
  space by default, so the built executable declares a bounded reservation before any memory limit
  is installable. The mechanism is resolved per lane and fails closed when unavailable: a cgroup
  scope bounds the aggregate on Linux, while Darwin has neither cgroups nor an enforced
  address-space limit and gets a runtime heap cap plus bounded concurrency only. This does **not**
  make a host out-of-memory condition impossible; the doctrine names what it does not bound.
  Canonical:
  [../architecture/bounded_host_memory.md](../architecture/bounded_host_memory.md)
- `close_fds` is only bounded because the descriptor space is: `Infernix.DescriptorSpace` lowers the
  soft `RLIMIT_NOFILE` to a 16384 ceiling as the first action of every process image, before the
  internal self-exec dispatch and before any descriptor is opened, because the forked child closes
  every descriptor up to that limit before `exec` — 313 s per spawn at a containerd pod's
  1073741816, measured. Every spawn kernel observes the bound immediately before `createProcess`,
  and the `unboundedDescriptorSpawnViolations` lint keeps a new `close_fds` surface from skipping
  it. Canonical:
  [../architecture/managed_state_transitions.md](../architecture/managed_state_transitions.md)

## Supported Build And Operator Workflows

- prefer the supported stage-0 bootstrap entrypoints:
  `./bootstrap/apple-silicon.sh`, `./bootstrap/linux-cpu.sh`, and `./bootstrap/linux-gpu.sh`
- use direct host builds only for the Apple Silicon host-native control plane:
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`,
  under the declared build ceiling
  ([../architecture/bounded_host_memory.md](../architecture/bounded_host_memory.md))
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
- keep the three-runtime build direction and the Kind testing or demo-ground direction aligned
- treat the demo UI (served by `infernix-demo`) as a demo surface on that substrate while
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
- [../../DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md)
