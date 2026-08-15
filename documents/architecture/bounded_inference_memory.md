# Bounded Inference Memory

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [bounded_host_memory.md](bounded_host_memory.md), [realness_contract.md](realness_contract.md), [managed_state_transitions.md](managed_state_transitions.md), [runtime_modes.md](runtime_modes.md), [daemon_topology.md](daemon_topology.md)

> **Purpose**: Define the code-level "memory-safety by construction" invariant for the inference row
> of the host-memory capacity ledger — an inference engine subprocess cannot run without typed
> evidence that admitted it, and its actual resident memory is held to the admitted ceiling — so that
> an over-budget model is a clean per-request `status=failed` rather than an unmanaged resource
> transition.

> **Scope.** This document owns *one claimant* on physical host memory: a serialized inference. The
> ledger itself, the other claimants, and the statement of which host out-of-memory conditions are
> and are not made unrepresentable live in [bounded_host_memory.md](bounded_host_memory.md). Nothing
> here asserts that a host out-of-memory kill is impossible.

## TL;DR

- An **unenforced admission is an unmanaged resource transition**: an inference admitted on a *static
  estimate* but then run with no structural tie to an *enforced* ceiling can consume more host memory
  than the budget that admitted it and take the whole process tree down with it (a `SIGKILL` that
  bypasses cleanup and leaves the cluster orphaned). Closing that gap removes *this* claimant as a
  cause of host exhaustion; it does not remove the others, which
  [bounded_host_memory.md](bounded_host_memory.md) enumerates.
- The invariant, the memory analog of the bounded-command kernel
  ([managed_state_transitions.md](managed_state_transitions.md): `runBoundedCommand` under a required
  `Timeout`): compilation mints a resource-indexed `MemoryGrant`, live refinement pairs it with the
  matching `Enforcer`, and engine launch **requires** the resulting opaque `ExecutableModel`.
  Running an engine from raw configuration or a bare grant does not typecheck.
- A breach of the ceiling at runtime is a **clean, typed, terminal per-request failure**
  (`status=failed` with `InferenceError.ModelMemoryLimitExceeded`) — the same fail-clean shape the
  [realness contract](realness_contract.md) gives for engine-logic failures — never a kill of the
  daemon that admitted it and never a retryable transient.
- Enforcement rides on **GHC module export lists plus `-Wall -Werror`** (opaque `MemoryGrant`, the raw
  engine spawn unexported), with the `unboundedEngineSpawnViolations` line-based lint backing the raw
  spawn primitive that has no type-level chokepoint.

## The invariant

For every compiled placement there is a resource-indexed `MemoryGrant`; every executable placement
pairs that grant with a live `Enforcer` for the same resource and therefore has an enforced
`MemoryCeiling`.

- **Compilation mints positive evidence, on the machine that will execute.** `compileRuntimePlan`
  validates the model footprint against **the executing machine's own observed capacity** and
  constructs `MemoryGrant resource` only inside a `CompiledPlacement`. Admission is an observation of
  the admitting process's own machine, which is the same argument that scopes *refinement* to the
  engine role: a coordinator that admitted against its own pod limit would either veto a model a
  larger machine could run, or mint a grant no inference will ever run under.
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
- **Serialization is per machine, and it is what makes the aggregate sound.** Execution is serialized
  behind one execution authority minted with the refined plan and carried inside the private engine
  topic capability, so a caller cannot pair a plan with a foreign token or reach execution
  unguarded. One engine process per machine plus one authority per plan means the resident set on a
  machine is **one model at a time**, so the aggregate a machine must satisfy is
  `max(footprint of the models it serves)`, not their sum. Per-model admission checks that maximum,
  which is why the fleet's memory contract is sound locally and needs no
  cross-machine arithmetic. It is also why a second engine process on one machine is a correctness
  bug rather than a scaling choice: see
  [daemon_topology.md](daemon_topology.md).
- **The ceiling is measured and terminated behind one typed interface.** On `apple-silicon` (host-native, no
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
  there is no "enforced by nobody" arm. The budget's **capacity terms are observed, never declared**:
  physical RAM from
  the host, the VM pledge from the co-tenant runtime, the pod ceiling from the live cgroup, and the
  device envelope from the accelerator. A capacity an operator can write down is a capacity that can
  disagree with the machine, and the code would have to re-check it anyway. Observed capacity is what
  the machine contains, which is not what it has left: availability is a separate observation, owned
  by [bounded_host_memory.md](bounded_host_memory.md), and admission of a competing claimant against
  it belongs there rather than here. `apple-silicon` is host-enforced by the grant plus the
  watchdog; `linux-cpu` is enforced by its process-group RSS watchdog under a verified outer pod
  envelope; `linux-gpu` carries the dual arm, whose pod RAM limit comes first and whose NVIDIA VRAM
  limit comes second. Both halves of a dual budget are required and independently enforced: the
  compiler mints one resource-indexed grant per limit and the capped-engine kernel runs one watchdog
  per grant, so a GPU model can never be admitted against RAM alone or VRAM alone. A `linux-gpu`
  budget that names only one resource is a hard config error (`GpuDualResourceBudgetRequired`), and a
  dual budget whose halves name the wrong resources is rejected by `InvalidMemoryEnforcer`.
- **Physical RAM is a checked partition.** `HostMemoryPartition` is minted by a smart constructor over
  observed quantities that splits physical RAM into `vmReserve + hostHeadroom + inferenceCapacity`,
  **rejects oversubscription and a non-positive inference capacity**,
  and forces `hostHeadroom` to be large enough to cover the OS, the control-plane binary, the routed
  end-to-end browser, and the worst-case inter-poll watchdog overshoot. A partition whose pieces exceed
  physical, or whose headroom cannot cover its co-tenants, is not a constructible term. The headroom
  covers those co-tenants and not the Haskell toolchain, which draws on the same pool as a competing
  occupant rather than as a headroom tenant; the exclusive host claim that keeps the two from being
  resident together is owned by [bounded_host_memory.md](bounded_host_memory.md).
- **Every model declares a positive footprint.** `ModelDescriptor` carries a `ModelMemoryFootprint`
  (a newtype behind a hidden constructor, rejecting a non-positive value) rather than a bare `Int` that
  decodes to `0` when absent; a model admitted on an absent or zero footprint is unrepresentable.

Because the ceiling is the model footprint (not the whole budget) and the partition reserves real
headroom, a host whose pledged co-tenant reserve leaves less inference capacity than a model's footprint
**fail-closes that model cleanly at admission** rather than admitting it and racing the watchdog — the
type makes the capacity tradeoff explicit (running an oversized model requires a machine with more
headroom, or a smaller co-tenant pledge, not silently over-committing physical RAM). A partition that
leaves *no* inference capacity is rejected outright rather than compiled into a plan with no
admissible placement: a daemon that starts and answers nothing is a worse failure than one that
refuses to start.

**The asymmetry is the whole doctrine in one line: the model's footprint is a system fact and stays on
the wire; the machine's capacity is a local observation and does not.**

## Enforcement

| Surface | Mechanism | Forbids |
|---|---|---|
| Types | GHC module export lists (opaque `CompiledRuntimePlan`, `RuntimePlan`, `ExecutableModel`, and resource-indexed grant/enforcer types) under `-Wall -Werror` | constructing or relabeling a grant; refining from caller-fabricated observations; launching from a raw model/config record; a bare-`Int`/absent-zero footprint; a budget with no named enforcer |
| Region | package-internal rank-2 capped-engine region with `bracket` teardown, entered only from an `ExecutableModel`-gated worker launch | an engine handle that escapes its capped region; a subprocess that runs or persists without the executable's ceiling and watchdog |
| Serialization | one opaque process-local execution authority owned inside the engine API | concurrent reuse of independently admitted footprints that collectively exceed the host/pod partition |
| OS | physical-footprint watchdog + process-group `SIGKILL` (`apple-silicon`); process-group RSS watchdog under a larger pod envelope (`linux-cpu`); independent RSS + NVIDIA process-group VRAM accounting (`linux-gpu`) | actual resident memory of an admitted engine exceeding its ceiling without a clean, typed, terminal per-request failure. This is sample-and-kill on a fixed cadence, not a kernel-imposed allocation ceiling: a breach is detected and terminated, not prevented |
| Partition | `HostMemoryPartition` smart constructor | `vmReserve + hostHeadroom + inferenceCapacity` oversubscribing physical RAM; a headroom too small to cover the OS and the routed end-to-end browser |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` `unboundedEngineSpawnViolations` | raw `readCreateProcessWithExitCode` / `createProcess` / `withCreateProcess` / `waitForProcess` engine spawn outside the capped-engine kernel — the raw primitives that have no type-level chokepoint. `withCreateProcess` is included because whole-token matching alone lets a bracketed unbounded spawn through |

The residual review obligations are deliberately explicit: **compiler honesty**
(`compileRuntimePlan` is the only grant mint and compares the required footprint with the declared
capacity), **refinement honesty** (only live package-owned observations mint enforcers),
**serialization containment** (the single-flight authority remains inside the opaque execution
API), and **retry containment** (an `EngineExceededCeiling` maps directly to a typed terminal failure,
never a string-classified retryable outcome).

**Declared exemption.** The operator CLI passthrough and the pre-manifest host-tool probes are named
exemptions from the raw-spawn gate: their executable and argv come
from the operator's own invocation, or they run before the manifest a closed command would need
exists. The exemption list is enumerated in `Infernix.Lint.HaskellStyle` and is part of the
contract, not a gap in it.

### The NVIDIA VRAM observer

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
A host out-of-memory condition remains representable for the reasons enumerated in
[bounded_host_memory.md](bounded_host_memory.md), including memory outside this repository's
process groups and resources the kernel does not attribute to a process.

With the checked `minHostHeadroomMib` partition on a 64 GiB / 48 GiB-Colima-pledge host, the
resolved inference capacity is 10240 MiB, so the heavy diffusion rows remain explicit unavailable
models rather than invalidating the whole catalog.

## Validation

A request for an unavailable row publishes a clean per-row `status=failed` carrying typed
`InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` and is not
launched. Configuration validation may surface capacity diagnostics, but it must not fail the whole
daemon because one catalog model is too large — smaller models continue to run, and the suite
classifies this constructor as a clean capacity failure, distinct from a missing result, a stall, or
a fabricated pass.


- `cabal build all` under `-Wall -Werror` plus the negative-compilation suite proves external callers
  cannot construct or relabel grants/enforcers, refine a plan from raw observations, import hidden
  decoder/routing modules, or launch an engine from a raw model/config record.
- `cabal test infernix-haskell-style` (`infernix test lint`) runs the `unboundedEngineSpawnViolations`
  capability-gating lint and keeps the style gate clean; `cabal test infernix-unit` covers the
  `HostMemoryPartition` oversubscription rejection, `ModelMemoryFootprint` non-positive rejection,
  exhaustive compiler placement-or-unavailable accounting, and live-refinement failures.
- The CPU/Apple behavioral suite (`infernix test all` on `apple-silicon` plus `linux-cpu`) is the
  proof: the full per-model real-inference lane completes without exhausting the host, and an
  over-capacity model produces a typed `status=failed` `ModelMemoryLimitExceeded` rather than a
  `SIGKILL`. Completing without exhaustion is a sample of this lane's behaviour, not evidence that a
  bound exists; the bound is proved by the typed gates above.
- `infernix lint docs` keeps this document registered and its cross-references resolving.

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
