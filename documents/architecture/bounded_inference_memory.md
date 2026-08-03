# Bounded Inference Memory

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [realness_contract.md](realness_contract.md), [managed_state_transitions.md](managed_state_transitions.md), [runtime_modes.md](runtime_modes.md), [daemon_topology.md](daemon_topology.md)

> **Purpose**: Define the code-level "memory-safety by construction" invariant — an inference engine
> subprocess cannot run without typed evidence that admitted it, and its actual resident memory is
> bounded to the admitted ceiling — so that an over-budget model is a clean per-request `status=failed`
> and a host out-of-memory kill is structurally unrepresentable.

> **Reopened target contract.** The invariant below is the required end state. The current worktree
> has resource-indexed compilation/refinement plus Apple, Linux CPU, **and NVIDIA VRAM** watchdog
> implementations. Phase 6 Sprint 6.44 closed the GPU half: a `linux-gpu` model that uses the device
> now compiles two independently indexed grants, and the NVIDIA per-process-group VRAM watchdog runs
> against its own admitted ceiling through the fixed public-tool observer kernel. The Apple
> adversarial breach proof remains Phase 4 hardware work, and the CLI-passthrough plus host-tool
> modules retain raw-spawn lint exemptions (each needs a design decision rather than a mechanical
> migration; see the exemption comment in `Infernix.Lint.HaskellStyle`). The ordered correction is
> governed by [Typed Execution Plan](typed_execution_plan.md).

## TL;DR

- A **host OOM is an unmanaged resource transition**: an inference admitted on a *static estimate* but
  then run with no structural tie to an *enforced* ceiling can consume more host memory than the budget
  that admitted it and take the whole process tree down with it (a `SIGKILL` that bypasses cleanup and
  leaves the cluster orphaned).
- The invariant, the memory analog of the bounded-command kernel
  ([managed_state_transitions.md](managed_state_transitions.md): `runBoundedCommand` under a required
  `Timeout`): compilation mints a resource-indexed `MemoryGrant`, live refinement pairs it with the
  matching `Enforcer`, and engine launch **requires** the resulting opaque `ExecutableModel`.
  Running an engine from raw configuration or a bare grant does not typecheck.
- A breach of the ceiling at runtime is a **clean, typed, terminal per-request failure**
  (`status=failed` with `InferenceError.ModelMemoryLimitExceeded`) — the same fail-clean shape the
  [realness contract](realness_contract.md) gives for engine-logic failures — never a host kill and
  never a retryable transient.
- Enforcement rides on **GHC module export lists plus `-Wall -Werror`** (opaque `MemoryGrant`, the raw
  engine spawn unexported), with the `unboundedEngineSpawnViolations` line-based lint backing the raw
  spawn primitive that has no type-level chokepoint.

## The invariant

For every compiled placement there is a resource-indexed `MemoryGrant`; every executable placement
pairs that grant with a live `Enforcer` for the same resource and therefore has an enforced
`MemoryCeiling`.

- **Compilation mints positive evidence.** `compileRuntimePlan` validates the model footprint against
  its declared capacity and constructs `MemoryGrant resource` only inside a `CompiledPlacement`.
  `MemoryGrant` and `MemoryCeiling` have hidden constructors and nominal resource roles. An
  over-capacity configured model is retained as `UnavailableModel` with its typed
  `ModelMemoryLimitExceeded`; it is not silently filtered out.
- **Refinement installs the matching enforcer.** Package-owned live observations refine
  `CompiledRuntimePlan` into `RuntimePlan`. `EnforcedGrant resource` can pair only
  `Enforcer resource` with `MemoryGrant resource`, and only this refined value can inhabit an
  `ExecutableModel`.
- **Execution requires the executable capability.** The public daemon/worker launch surface accepts
  `ExecutableModel`, never a bare grant, enforcer, model descriptor, command override, or raw process
  specification. The package-internal capped-engine kernel owns the only inference spawn and a
  rank-2 bracketed handle that cannot escape its actively enforced region. Its total
  `EngineOutcome` distinguishes a measured `EngineExceededCeiling` from
  `EngineEnforcementUnavailable`; only the measured breach maps to typed
  `ModelMemoryLimitExceeded`.
- **Serialization is a remaining capability obligation.** The supported daemon currently serializes
  execution with a process-local `MVar`, but the lock is supplied outside the opaque launch
  capability and `ExecutableModel` is reusable. Phase 4 must encapsulate one execution authority so
  callers cannot create independent locks or concurrently reuse one admitted placement. Until then,
  resource/enforcer coherence is construction-safe but aggregate one-model-at-a-time capacity is an
  operational invariant, not a type-level one.
- **The ceiling is OS-enforced behind one typed interface.** On `apple-silicon` (host-native, no
  cgroups) a package-internal observer discovers exact process-group membership with fixed
  `/usr/bin/top` output and measures each member's physical bytes with fixed
  `/usr/bin/footprint`, all under one total deadline and bounded captures; the watchdog `SIGKILL`s
  the process group when the measured total exceeds the ceiling. Callers cannot supply a command
  specification, and no direct FFI is used. An address-space rlimit is *not* used, because Metal
  and Python reserve large virtual ranges unrelated to resident memory. On `linux-cpu`, a verified
  `/proc` sampler conservatively sums RSS for every process in the fresh child process group and
  kills only that group on breach; the pod cgroup remains a larger outer envelope for the daemon,
  admitted child ceiling, and sampling overshoot. A bare exit `137` / `SIGKILL` is not classified as
  a memory breach without watchdog evidence. On `linux-gpu`, the same resident-RAM proof is paired
  with independent NVIDIA process-group VRAM accounting. Every substrate returns one total outcome,
  and the daemon remains outside the child execution group.

The budget these grants draw from is itself a checked partition, and the model's footprint is required,
so the related unmanaged states are also unbuildable:

- **The budget names its enforcer.** `InferenceMemoryBudget` is `HostEnforcedBudget HostMemoryPartition
  | SubstrateEnforcedBudget PodMemoryLimit | DualEnforcedBudget PodMemoryLimit PodMemoryLimit` —
  there is no "enforced by nobody" arm. `apple-silicon` is host-enforced by the grant plus the
  watchdog; `linux-cpu` is enforced by its process-group RSS watchdog under a verified outer pod
  envelope; `linux-gpu` carries the dual arm, whose pod RAM limit comes first and whose NVIDIA VRAM
  limit comes second. Both halves of a dual budget are required and independently enforced: the
  compiler mints one resource-indexed grant per limit and the capped-engine kernel runs one watchdog
  per grant, so a GPU model can never be admitted against RAM alone or VRAM alone. A `linux-gpu`
  budget that names only one resource is a hard config error (`GpuDualResourceBudgetRequired`), and a
  dual budget whose halves name the wrong resources is rejected by `InvalidMemoryEnforcer`.
- **Physical RAM is a checked partition.** `HostMemoryPartition` is minted by a smart constructor that
  splits physical RAM into `vmReserve + hostHeadroom + inferenceCapacity`, **rejects oversubscription**,
  and forces `hostHeadroom` to be large enough to cover the OS, the control-plane binary, the routed
  end-to-end browser, and the worst-case inter-poll watchdog overshoot. A partition whose pieces exceed
  physical, or whose headroom cannot cover its co-tenants, is not a constructible term.
- **Every model declares a positive footprint.** `ModelDescriptor` carries a `ModelMemoryFootprint`
  (a newtype behind a hidden constructor, rejecting a non-positive value) rather than a bare `Int` that
  decodes to `0` when absent; a model admitted on an absent or zero footprint is unrepresentable.

Because the ceiling is the model footprint (not the whole budget) and the partition reserves real
headroom, a host whose pledged co-tenant reserve leaves less inference capacity than a model's footprint
**fail-closes that model cleanly at admission** rather than admitting it and racing the watchdog — the
type makes the capacity tradeoff explicit (running an oversized model requires enlarging
`inferenceCapacity`, i.e. shrinking the co-tenant reserve, not silently over-committing physical RAM).

## Enforcement

| Surface | Mechanism | Forbids |
|---|---|---|
| Types | GHC module export lists (opaque `CompiledRuntimePlan`, `RuntimePlan`, `ExecutableModel`, and resource-indexed grant/enforcer types) under `-Wall -Werror` | constructing or relabeling a grant; refining from caller-fabricated observations; launching from a raw model/config record; a bare-`Int`/absent-zero footprint; a budget with no named enforcer |
| Region | package-internal rank-2 capped-engine region with `bracket` teardown, entered only from an `ExecutableModel`-gated worker launch | an engine handle that escapes its capped region; a subprocess that runs or persists without the executable's ceiling and watchdog |
| Serialization (Phase 4 target) | one opaque process-local execution authority owned inside the engine API | concurrent reuse of independently admitted footprints that collectively exceed the host/pod partition |
| OS | physical-footprint watchdog + process-group `SIGKILL` (`apple-silicon`); process-group RSS watchdog under a larger pod envelope (`linux-cpu`); independent RSS + NVIDIA process-group VRAM accounting (`linux-gpu`) | actual resident memory exceeding the admitted ceiling without a clean, typed, terminal per-request failure — i.e. a host OOM |
| Partition | `HostMemoryPartition` smart constructor | `vmReserve + hostHeadroom + inferenceCapacity` oversubscribing physical RAM; a headroom too small to cover the OS and the routed end-to-end browser |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` `unboundedEngineSpawnViolations` | raw `readCreateProcessWithExitCode` / `createProcess` / `withCreateProcess` / `waitForProcess` engine spawn outside the capped-engine kernel — the raw primitives that have no type-level chokepoint. Sprint 6.44 added `withCreateProcess` after finding that whole-token matching had let a bracketed unbounded spawn through |

The residual review obligations are deliberately explicit: **compiler honesty**
(`compileRuntimePlan` is the only grant mint and compares the required footprint with the declared
capacity), **refinement honesty** (only live package-owned observations mint enforcers),
**serialization containment** (Phase 4 moves the single-flight authority inside the opaque execution
API), and **retry containment** (an `EngineExceededCeiling` maps directly to a typed terminal failure,
never a string-classified retryable outcome).

## Current Status

The full invariant is **reopened and not yet satisfied**, but the Phase 1 capability correction is
present in the current worktree. Grants, ceilings, enforcers, and enforced grants retain a nominal
resource index; only live refinement mints `RuntimePlan` / `ExecutableModel`; raw configuration,
plain-grant launch, arbitrary command overrides, exit-137 breach fabrication, and unavailable-sampler
fallback-to-zero are removed from the engine execution path. Raw configuration and topic derivation
helpers live in hidden package modules. The late Phase 1 messaging closure is also present:
unavailable/empty/unknown/wrong-route/malformed inputs receive terminal failed results before
source removal or acknowledgement; the raw publisher is removed; bootstrap publication requires a
plan-derived capability whose consumer revalidates model/URL/timestamp; cross-family topic
collisions fail compilation; and substrate Dhall emission uses explicit UTF-8.

Phase 1 Sprint 1.19 is `Done` for this narrower capability scope: its source-matched
machine-independent gate and final adversarial source review passed on 2026-07-25, including 4
positive and 27 negative compile fixtures and the focused terminal-result coverage. Phase 1 as a
whole remains Active for Sprint 1.20's bounded artifact provisioning/runtime correction; that
later source and evidence do not reuse Sprint 1.19's gate. Phase 4 owns the Apple/Linux CPU
adversarial breach-and-survival proof,
verification of the outer pod envelope under live workloads, and moving the process-local
serialization authority inside the opaque execution API. Phase 6 Sprint 6.44 landed NVIDIA
per-process-group VRAM enforcement and shrank the raw-spawn exemption set; the remaining exempt
modules are the CLI passthrough and the host-tool surfaces, which need a design decision rather than
a mechanical migration. Phase 8 owns the final proper-union generated-Dhall wire.

### The NVIDIA VRAM observer (Phase 6 Sprint 6.44)

The device sampler is the same shape as the Apple footprint observer: a fixed, bounded public-tool
kernel in `Infernix.Runtime.CappedEngine.FixedObserver` whose request vocabulary is a closed enum and
whose `FixedObserverSpec` is unexported, so no caller can supply an executable, argument vector,
environment, or working directory. Enforcement pins `/usr/bin/nvidia-smi` as a literal absolute path
rather than resolving it from the host-tools manifest: an enforcement observer that follows a
configurable path is redirectable, which is exactly what the closed catalog exists to prevent.

Two properties make per-process attribution sound inside an engine pod, and both were measured
rather than assumed:

- NVML resolves each compute context against the **reading process's** PID namespace and omits the
  contexts it cannot resolve. A pod therefore observes its own namespace's compute applications with
  namespace-local process ids, and never another container's. A CUDA process running outside the
  namespace is invisible to the query — correctly, because it is not ours.
- Membership comes from the same `/proc` walk the resident-set lane already uses, so the NVIDIA lane
  spawns exactly one fixed command per sample and performs no process discovery of its own. Compute
  applications outside the engine's process group are deliberately not attributed to it.

Every failure is fail-closed and typed: a spawn, deadline, parse, overflow, or `/proc` enumeration
failure becomes `EngineEnforcementUnavailable`, which kills the group and exits `70`. A live group
member holding no CUDA context attributes zero bytes — an ordinary early-execution observation, not a
loss — while *no* live group member observed for a still-running engine is the same loss class as a
sampler error and also fails closed. A measured breach is `EngineExceededCeiling`, reported as the
typed `ModelMemoryLimitExceeded` per-request failure. The device's total VRAM is the outer envelope a
grant must fit inside, the GPU analogue of the cgroup memory limit read for the resident-set lane;
an absent or non-positive envelope is a refinement rejection (`NvidiaEnvelopeUnavailable` /
`NvidiaEnvelopeTooSmall`), never an assumed value.
Until the later behavioral/enforcement work passes, a host OOM remains representable despite the
landed resource/enforcer type coherence.

The superseded surfaces — `admitModelMemory :: … -> Maybe`, the unenforced budget arm, the bare-`Int`
footprint, the raw unbounded engine spawns, and the fixed `appleHostReserveMib = 3072` host reserve —
are recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
Wave W is historical evidence for the narrower pre-audit implementation; it is not closure evidence
for the indexed/refined capability boundary or the remaining Phase 4 serialization and adversarial
proof. With the checked `minHostHeadroomMib` partition on a 64 GiB / 48 GiB-Colima-pledge host, the
resolved inference capacity is 10240 MiB, so the heavy diffusion rows remain explicit unavailable
models rather than invalidating the whole catalog.

## Validation

- `cabal build all` under `-Wall -Werror` plus the negative-compilation suite proves external callers
  cannot construct or relabel grants/enforcers, refine a plan from raw observations, import hidden
  decoder/routing modules, or launch an engine from a raw model/config record.
- `cabal test infernix-haskell-style` (`infernix test lint`) runs the `unboundedEngineSpawnViolations`
  capability-gating lint and keeps the style gate clean; `cabal test infernix-unit` covers the
  `HostMemoryPartition` oversubscription rejection, `ModelMemoryFootprint` non-positive rejection,
  exhaustive compiler placement-or-unavailable accounting, and live-refinement failures.
- The Phase 4 cohort full-suite (`infernix test all` on the selected `apple-silicon` accelerator plus
  `linux-cpu`) is the CPU/Apple behavioral
  proof: the full per-model real-inference lane completes with zero host OOM, and an over-capacity model
  produces a typed `status=failed` `ModelMemoryLimitExceeded` rather than a `SIGKILL`.
- `infernix lint docs` keeps this document registered and its cross-references resolving; the reopened
  phase and sprint status is tracked in `DEVELOPMENT_PLAN/`.

## Cross-References

- [managed_state_transitions.md](managed_state_transitions.md) — the sibling doctrine this generalizes
  from cluster subprocesses to inference subprocesses; the `MemoryGrant`/`MemoryCeiling` shapes mirror
  its `PayloadVerified`/`Timeout` templates.
- [realness_contract.md](realness_contract.md) — the results-side sibling; the typed admission it
  describes is the pre-execution half of this contract.
- [runtime_modes.md](runtime_modes.md) — the per-substrate budget resolution and the `HostMemoryPartition`
  partition sources.
- [daemon_topology.md](daemon_topology.md) — the Engine-role serialized execution and the engine
  memory-admission failure semantics.
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md) — the host-memory
  partition on Apple Silicon and the colima-pledge capacity tradeoff.
