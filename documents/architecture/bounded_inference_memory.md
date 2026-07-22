# Bounded Inference Memory

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [realness_contract.md](realness_contract.md), [managed_state_transitions.md](managed_state_transitions.md), [runtime_modes.md](runtime_modes.md), [daemon_topology.md](daemon_topology.md)

> **Purpose**: Define the code-level "memory-safety by construction" invariant — an inference engine
> subprocess cannot run without typed evidence that admitted it, and its actual resident memory is
> bounded to the admitted ceiling — so that an over-budget model is a clean per-request `status=failed`
> and a host out-of-memory kill is structurally unrepresentable.

## TL;DR

- A **host OOM is an unmanaged resource transition**: an inference admitted on a *static estimate* but
  then run with no structural tie to an *enforced* ceiling can consume more host memory than the budget
  that admitted it and take the whole process tree down with it (a `SIGKILL` that bypasses cleanup and
  leaves the cluster orphaned).
- The invariant, the memory analog of the bounded-command kernel
  ([managed_state_transitions.md](managed_state_transitions.md): `runBoundedCommand` under a required
  `Timeout`): admission mints a `MemoryGrant`, and the engine spawn **requires** it and enforces its
  ceiling. Admission is the only producer of the grant; the capped-engine kernel is the only consumer.
  Running an engine without an admission proof does not typecheck, and its actual resident memory is
  OS-bounded to the admitted ceiling.
- A breach of the ceiling at runtime is a **clean, typed, terminal per-request failure**
  (`status=failed` with `InferenceError.ModelMemoryLimitExceeded`) — the same fail-clean shape the
  [realness contract](realness_contract.md) gives for engine-logic failures — never a host kill and
  never a retryable transient.
- Enforcement rides on **GHC module export lists plus `-Wall -Werror`** (opaque `MemoryGrant`, the raw
  engine spawn unexported), with the `unboundedEngineSpawnViolations` line-based lint backing the raw
  spawn primitive that has no type-level chokepoint.

## The invariant

For every admitted inference there is a `MemoryGrant`; for every `MemoryGrant` there is an enforced
`MemoryCeiling`.

- **Admission mints positive evidence.** `admitModelMemory :: InferenceMemoryBudget -> ModelDescriptor
  -> Either InferenceError MemoryGrant` is the single honest mint. `MemoryGrant` is an **opaque newtype
  with a hidden constructor** (the [monotone evidence](managed_state_transitions.md) shape — minted and
  consumed once, synchronously, inside the serialized engine-execution region), carrying a
  `MemoryCeiling` equal to the model's declared footprint. "Admitted" is no longer a proof-free `Nothing`
  but a value that could only exist if the footprint fit the budget.
- **Execution requires the grant and enforces the ceiling.** The capped-engine kernel exports the
  **sole** engine spawn, `withCappedEngine :: MemoryGrant -> (forall s. EngineHandle s -> IO r) -> IO r`
  — a rank-2 bracketed region whose `forall s.` handle cannot escape the scope in which the ceiling is
  actively enforced, and whose `bracket` guarantees the enforcement is torn down on every exit path
  including exception. The raw process-spawn primitives (`readCreateProcessWithExitCode` / `createProcess`
  / `waitForProcess`) are **not exported** from that module; the terminal outcome is a total
  `EngineOutcome` whose `EngineExceededCeiling` arm maps to `status=failed`
  `InferenceError.ModelMemoryLimitExceeded`. An engine spawn without a grant, or one whose resident
  memory is not bounded to its grant, is not a constructible term.
- **The ceiling is OS-enforced behind one typed interface.** On `apple-silicon` (host-native, no
  cgroups) a watchdog samples the child's physical footprint (`proc_pid_rusage`) and `SIGKILL`s its
  process group when it exceeds the ceiling — an address-space rlimit is *not* used, because Metal and
  Python reserve large virtual ranges unrelated to resident memory. On `linux-cpu` / `linux-gpu` the pod
  cgroup memory limit and the CUDA allocator already bound the process inside its own container, so host
  death is already impossible; the kernel maps the breach to the same `EngineExceededCeiling` outcome by
  classifying the OOM exit. Every substrate returns the one total outcome; only the host-native lane
  carries the host-death risk the watchdog closes.

The budget these grants draw from is itself a checked partition, and the model's footprint is required,
so the related unmanaged states are also unbuildable:

- **The budget names its enforcer.** `InferenceMemoryBudget` is `HostEnforcedBudget HostMemoryPartition
  | SubstrateEnforcedBudget PodMemoryLimit` — there is no "enforced by nobody" arm. `apple-silicon` is
  host-enforced by the grant plus the watchdog; `linux-cpu` / `linux-gpu` are substrate-enforced by the
  pod cgroup / VRAM limit the descriptive `PodMemoryLimit` records.
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
| Types | GHC module export lists (opaque `MemoryGrant`, hidden constructor) under `-Wall -Werror` | spawning an engine without a `MemoryGrant`; constructing a grant outside `admitModelMemory`; a bare-`Int`/absent-zero footprint (required `ModelMemoryFootprint`); a budget with no enforcer (no unenforced arm) |
| Region | rank-2 `withCappedEngine :: MemoryGrant -> (forall s. EngineHandle s -> IO r) -> IO r` with `bracket` teardown | an engine handle that escapes its capped region; a subprocess that runs or persists without its ceiling and watchdog |
| OS | physical-footprint watchdog + process-group `SIGKILL` (`apple-silicon`); pod-cgroup / VRAM OOM exit classification (`linux-cpu` / `linux-gpu`) | actual resident memory exceeding the admitted ceiling without a clean, typed, terminal per-request failure — i.e. a host OOM |
| Partition | `HostMemoryPartition` smart constructor | `vmReserve + hostHeadroom + inferenceCapacity` oversubscribing physical RAM; a headroom too small to cover the OS and the routed end-to-end browser |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` `unboundedEngineSpawnViolations` | raw `readCreateProcessWithExitCode` / `createProcess` / `waitForProcess` engine spawn outside the capped-engine kernel — the raw primitive that has no type-level chokepoint |

Two residual review-obligations remain and are minimized to a small audit surface: **admission honesty**
(`admitModelMemory` is the one mint of `MemoryGrant`, co-located with its hidden constructor, and must
compare the real footprint against the partition's `inferenceCapacity`), and **retry containment** (an
`EngineExceededCeiling` breach maps directly to the typed terminal failure, never to a string-classified
retryable outcome, so an over-budget kill is never bootstrap-retried into a second host-death attempt).

## Current Status

The invariant is **implemented and code-side closed** (Phase 4 Sprints 4.30/4.31, Phase 6 Sprint 6.42;
machine-independent gate set GREEN on 2026-07-21). `admitModelMemory :: InferenceMemoryBudget ->
ModelDescriptor -> Either InferenceError MemoryGrant` (`src/Infernix/Types.hs`) is the sole mint of the
opaque `MemoryGrant` (hidden constructor), carrying a `MemoryCeiling` equal to the model footprint. The
capped-engine kernel `Infernix.Runtime.CappedEngine` exports the sole engine spawn `withCappedEngine`
(rank-2, `bracket`-torn-down) and does **not** re-export `createProcess` / `waitForProcess`; on
`apple-silicon` a `proc_pid_rusage` physical-footprint watchdog SIGKILLs the child's process group on
breach, and on `linux-*` the kernel classifies the pod-cgroup OOM exit. Both surface the total
`EngineOutcome`, whose `EngineExceededCeiling` arm the runtime rebuilds into a `status=failed`
`ModelMemoryLimitExceeded`. `InferenceMemoryBudget` is now `HostEnforcedBudget HostMemoryPartition |
SubstrateEnforcedBudget PodMemoryLimit` (no unenforced arm); `HostMemoryPartition` is minted only by the
smart constructor that rejects oversubscription and a headroom below the `minHostHeadroomMib` floor
(covering the OS, control-plane binary, and routed end-to-end browser); and `ModelDescriptor` carries a
required `ModelMemoryFootprint` newtype (non-positive rejected). The `unboundedEngineSpawnViolations`
capability-gating lint (`src/Infernix/Lint/HaskellStyle.hs`) keeps a new engine spawn off the raw
primitives. A host OOM is therefore no longer representable: over-budget models fail-close cleanly at
admission, and an admitted model whose actual footprint breaches its ceiling is killed by the watchdog
and reported as a typed terminal failure.

The superseded surfaces — `admitModelMemory :: … -> Maybe`, the unenforced budget arm, the bare-`Int`
footprint, the raw unbounded engine spawns, and the fixed `appleHostReserveMib = 3072` host reserve —
are recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
The remaining gate is the behavioral proof (no host OOM; the over-capacity rows cleanly typed-rejected)
on the `apple-silicon` plus `linux-cpu` cohort wave
[Wave W](../../DEVELOPMENT_PLAN/cohort-validation-waves.md); with the honest `minHostHeadroomMib`
partition on a 64 GiB / 48 GiB-colima-pledge host the resolved inference capacity is 10240 MiB, so the
heavy diffusion rows (`image-*`, `video-*`) now fail-close cleanly at admission on `apple-silicon`
rather than racing the watchdog.

## Validation

- `cabal build all` under `-Wall -Werror` is the primary proof: an engine spawn reachable without a
  `MemoryGrant`, a grant constructed outside admission, or a raw spawn outside the capped-engine kernel
  is a build error.
- `cabal test infernix-haskell-style` (`infernix test lint`) runs the `unboundedEngineSpawnViolations`
  capability-gating lint and keeps the style gate clean; `cabal test infernix-unit` covers the
  `HostMemoryPartition` oversubscription rejection, the `ModelMemoryFootprint` non-positive rejection,
  and the `admitModelMemory` grant-versus-rejection cases.
- The cohort full-suite (`infernix test all` on `apple-silicon` and `linux-cpu`) is the behavioral
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
