# Bounded Inference Memory

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [bounded_host_memory.md](bounded_host_memory.md), [realness_contract.md](realness_contract.md), [managed_state_transitions.md](managed_state_transitions.md), [runtime_modes.md](runtime_modes.md), [daemon_topology.md](daemon_topology.md), [typed_execution_plan.md](typed_execution_plan.md), [model_catalog.md](model_catalog.md), [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md), [../development/python_policy.md](../development/python_policy.md)

> **Purpose**: Define the code-level "memory-safety by construction" invariant for the inference row
> of the host-memory capacity ledger — an inference engine subprocess cannot run without typed
> evidence that admitted it, its requirement is derived from the artifact rather than authored, and a
> ceiling is installed before its first allocation on every lane that can install one — so that an
> over-budget model is a clean per-request `status=failed` rather than an unmanaged resource
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
  `Timeout`): compilation mints a resource-indexed grant from a **derived** requirement, live
  refinement pairs it with the matching enforcer for the same resource, and engine launch **requires**
  the resulting opaque executable capability. Running an engine from raw configuration or a bare grant
  does not typecheck. The analogy is exact where the ceiling is a process limit installed before the
  first allocation, because such a limit is as intrinsic to a process as a deadline is.
- **A requirement is derived, never authored.** A model's memory requirement is computed from the
  artifact's own bytes. Safetensors and GGUF expose a prefix-indexed tensor table that gives exact
  weight bytes; whisper.cpp's legacy GGML container interleaves tensor records with their payloads,
  so its fixed header establishes the family and geometry while the actual object extent is the
  conservative host-resident weight charge. Declared geometry plus the execution shape gives exact
  key/value cache bytes where that cache exists. Every reader is bounded and fails closed on a
  malformed or self-contradicting artifact. An authored per-family constant is a number that can
  disagree with the model it describes, which is the same objection that makes capacity an
  observation rather than a declaration.
- **The admitted quantity and the installed ceiling are different values, and the ceiling records
  which quantities produced it.** The artifact-derived requirement is what admission compares against
  a machine's observed capacity, and it stays authoritative wherever it is the larger number. What it
  does not model is what the engine's own execution needs beyond the terms the artifact describes:
  compute buffers, graph scratch, and backend allocation overhead, and — where a placement's declared
  load strategy and its actual invocation disagree about which memory the weights land in — the
  weights themselves. Where an engine
  family ships a tool that projects what it will need, the ceiling installed for it is the greater of
  the derived and the projected quantity, taken through a bounded pre-flight probe under a closed
  package-internal specification. Where no trustworthy projection exists, execution is bounded by
  the already-admitted per-execution lane budget: the artifact-derived quantity remains admission,
  while the budget covers runtime residency the checkpoint cannot state. A ceiling derived from
  artifact-plus-projection is not the same value as one widened to the lane budget, so the
  installation carries both quantities and its provenance rather than implying a single one. A
  projection that cannot be obtained is a typed refusal naming the model and the reason — never a
  fall back to the derived quantity and never an unbounded launch — because a derived quantity that
  is structurally incomplete refuses a model that would have run and reports it as an engine fault.
- **Host and device requirements are different formulas, not one number reused.** Where weights stream
  to a device, host residency is bounded by the staging window rather than by the model, so the
  model-size term is absent from the host formula entirely. A single scalar admitted against two
  physical resources is a category error that no amount of validation repairs.
- A measured breach of the ceiling at runtime is a **clean, typed, terminal per-request failure**
  (`status=failed` with `InferenceError.ModelMemoryLimitExceeded`) — the same fail-clean shape the
  [realness contract](realness_contract.md) gives for engine-logic failures — never a kill of the
  daemon that admitted it and never a retryable transient. A sampled overrun reports an observation
  strictly above the ceiling it breached. A kernel-refused allocation is prevented, but the generic
  parent process receives only the engine's non-zero exit: a nearby sampled peak is also produced by
  an ordinary fault after the weights are resident, so it is not evidence of refusal. Unless the
  engine reports a typed refusal on its owned protocol, that exit stays a plain engine failure and
  retains the engine's bounded diagnostic output. Standard-error matching is not evidence because it
  is an upstream format this repository does not own.
- Enforcement has three layers, and they are not interchangeable. **Prevention** is a kernel limit
  installed before the engine's first allocation, so an over-budget allocation is refused rather than
  observed. **Detection** is the sampled backstop over the residue that limit provably does not cover.
  **Conformance** is the engine reporting back the limit it actually received. The type layer rides on
  GHC module export lists plus `-Wall -Werror` (opaque grants, the raw engine spawn unexported), with
  line-based lint rules backing the raw primitives that have no type-level chokepoint.
- **What this makes impossible is an unbounded launch, per lane and per resource — not a host
  out-of-memory condition.** A lane that cannot install a ceiling declares itself detection-only and
  says so in its own type; it does not quietly claim prevention. The residue each mechanism leaves is
  named as a term below rather than as a footnote, and the host ledger's scope statement in
  [bounded_host_memory.md](bounded_host_memory.md) is unaffected.

## The invariant

For every compiled placement there is a resource-indexed grant per physical resource that placement
consumes; every executable placement pairs each grant with a live enforcer for the same resource, and
therefore carries an enforced ceiling for every resource it can consume. A placement that names a
device but carries no device grant is not a constructible term.

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
- **The ceiling is installed before the first allocation where a lane can install one.** On the Linux
  lanes the engine is started through a fixed public-tool launch prefix that lowers both the soft and
  the hard data-segment limit and then replaces itself with the engine image, so the limit is in force
  before the engine's first instruction and cannot be raised back by the process it binds. Lowering
  both limits is one-way, which is why it belongs to a process image dedicated to a single execution
  and not to the long-lived daemon; the prefix leaves no live process, so the engine keeps its own
  process identity, group, and exit status. An **address-space** limit is unusable for this: a device
  runtime reserves hundreds of gigabytes of address space unrelated to resident memory, and an
  address-space limit also charges file-backed mappings in full, which would defeat streaming a model
  into a device from a mapped artifact. A **data-segment** limit charges neither.
- **What the installed ceiling covers, and what it does not.** It bounds private writable anonymous and
  private writable file-backed mappings of one process. It does not bound shared mappings, and a device
  driver's pinned and managed host memory is mapped shared — that memory is unswappable and charged to
  the enclosing cgroup, so it is named as its own term in the account and left to the backstop. It is a
  per-process limit, so a multi-process engine is bounded per process and its tree total is arithmetic
  plus a checked member count, not a kernel aggregate. Nothing bounds device memory on any lane by a
  kernel mechanism at all; the device half is admission plus arena sizing plus detection.
- **The backstop measures the residue behind one resource-parameterised kernel.** One sampling loop is
  parameterised by the resource it observes rather than duplicated per platform: process-group physical
  footprint on `apple-silicon` through fixed public tools, process-group anonymous residency on the
  Linux lanes through `/proc`, and per-process device bytes through a fixed device query. Callers
  cannot supply a command specification, and no direct FFI is used. Terminal procfs tasks are not live
  members. If a complete sample sees no live member, four fresh observations at the sampling interval
  bound the exit window; reappearance resumes the loop, while persistent absence is ordinary completion
  only when the leader is terminal or absent. A stable live leader or unreadable evidence terminates the
  group as typed enforcement loss. The watchdog never waits on the engine's process handle, so the
  engine action remains its sole reaper, and a bare `SIGKILL` exit is not classified as a memory breach
  without evidence. A breach names the resource it breached and the footprint it observed, because a
  refusal that cannot say which resource it is about cannot be acted on. Each fixed-tool invocation is
  total: the NVIDIA query retains a five-second deadline, while Darwin's full-host `top` plus per-member
  `footprint` sample has a fifteen-second deadline. The wider Darwin bound is deliberate detection-only
  latency: the selected Apple cohort observed a healthy full-host snapshot exceed five seconds while a
  real model loaded, and treating scheduler pressure as enforcement loss killed a valid execution.
- **A lane declares the strength it has.** The enforcement mechanism is part of the type, so a lane
  that can install a kernel ceiling and a lane that can only sample are different values, and a
  contract that requires prevention refuses readiness on a lane that offers only detection. The
  closed per-lane table is an authored statement of mechanism, not an observation disguised as a
  constructor. Cohort calibration is retained as validation evidence about that table's behavior;
  it is not runtime evidence minted by process-local observation.

The capacity these grants draw from is itself a checked partition, and the model's requirement is
derived rather than authored, so the related unmanaged states are also unbuildable:

- **The budget names its enforcer.** Every budget arm names the enforcer that will hold it, per
  physical resource; there is no "enforced by nobody" arm, and a lane whose models consume two
  resources carries two independent limits rather than one limit reused. The budget's **capacity terms
  are observed, never declared**:
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
- **Every model's requirement is derived from its artifact, and the derivation fails closed.** The
  weight term is the sum over the artifact's own prefix-indexed tensor table of each tensor's element
  count times its element width. The legacy Whisper GGML exception has no prefix-indexed table, so a
  validated fixed header plus the actual object extent yields a conservative host-resident charge
  without reading or trusting an authored family constant. The cache term is the closed function of
  the model's declared geometry and the execution shape the engine will actually run under. The
  derivation refuses an artifact whose header overruns its file, whose tensor extents disagree with
  their declared shapes, whose offsets do not tile densely, or whose geometry disagrees with its own
  header, so an artifact that misdescribes itself yields no requirement rather than a small one. The
  resulting quantity is resource-indexed and its constructor is hidden, so a host
  quantity cannot be admitted against a device limit; a requirement that is absent, zero, or built from
  anything but a verified artifact is unrepresentable.
- **The execution shape is one value with two consumers.** The context length, batch, generation bound,
  and load strategy that the cache term is computed from are the same values the engine is started
  with, carried to it rather than restated in it. Generation shape is part of a model's bounded
  execution kernel, not an unaccounted caller choice: an engine free to choose its own arena from the
  size of the device it happens to find is not bounded by anything the compiler reasoned about.

Because admission is against the model footprint and the partition reserves real headroom, a host
whose pledged co-tenant reserve leaves less inference capacity than a model's footprint
**fail-closes that model cleanly at admission** rather than admitting it and racing the watchdog — the
type makes the capacity tradeoff explicit (running an oversized model requires a machine with more
headroom, or a smaller co-tenant pledge, not silently over-committing physical RAM). A partition that
leaves *no* inference capacity is rejected outright rather than compiled into a plan with no
admissible placement: a daemon that starts and answers nothing is a worse failure than one that
refuses to start.

**The asymmetry is the whole doctrine in one line: what a model requires is derived from the model and
agreed fleet-wide; what a machine can offer is observed locally and never travels — and the two are
computed per physical resource, because host residency and device residency are different quantities
with different drivers.**

## Enforcement

| Surface | Mechanism | Forbids |
|---|---|---|
| Types | GHC module export lists and nominal resource roles over the opaque plan, executable, requirement, and grant/enforcer types, under `-Wall -Werror` | constructing or relabeling a grant; admitting a host quantity against a device limit; refining from caller-fabricated observations; launching from a raw model/config record; a requirement built from anything but a verified artifact; a budget with no named enforcer; a device-using placement carrying no device grant |
| Region | package-internal rank-2 capped-engine region with `bracket` teardown, entered only from an `ExecutableModel`-gated worker launch | an engine handle that escapes its capped region; a subprocess that runs or persists without the executable's ceiling and watchdog |
| Serialization | one opaque process-local execution authority owned inside the engine API | concurrent reuse of independently admitted footprints that collectively exceed the host/pod partition |
| OS (prevention) | a fixed public-tool launch prefix lowering the soft and hard data-segment limit, then replacing itself with the engine image, at the greater of the artifact-derived requirement and the engine's own bounded pre-flight projection, or at the admitted lane budget when no trustworthy projection exists | one process of an admitted engine allocating private writable memory beyond its installed ceiling. Bounds neither shared mappings nor device memory, and bounds a tree only per process |
| OS (detection) | one resource-parameterised sampling kernel over process-group physical footprint, anonymous residency, or per-process device bytes | the residue prevention does not cover — pinned and shared host memory, and device memory on every lane — exceeding its ceiling without a clean, typed, terminal per-request failure. This half is sample-and-kill on a fixed cadence: a breach is detected and terminated, not prevented |
| Installation | the launch prefix is a closed constructor whose only free values are quantities rendered from indexed types; the target executable and argument vector come from the already-closed engine command; the projection probe is a closed per-family specification naming a sibling of the validated entry object inside the same sealed immutable closure, rendering the same execution operands the engine invocation renders | a caller-supplied or manifest-supplied enforcement executable; an engine spawned without passing through the installation region |
| Partition | `HostMemoryPartition` smart constructor over one checked `HostClaimablePool` | a VM reserve that empties the pool; a pool too small to retain its derived co-tenant headroom plus positive inference capacity; independently authored headroom or toolchain residuals |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` `unboundedEngineSpawnViolations`, and the sibling rule that an engine spawn is reached only through the installation region | raw `readCreateProcessWithExitCode` / `createProcess` / `withCreateProcess` / `waitForProcess` engine spawn outside the capped-engine kernel — the raw primitives that have no type-level chokepoint. `withCreateProcess` is included because whole-token matching alone lets a bracketed unbounded spawn through. The sibling rule keeps a new spawn surface from skipping the ceiling installation the way one could once skip the descriptor-space bound |

The residual review obligations are deliberately explicit: **compiler honesty** (one grant mint,
comparing a derived requirement against an observed capacity), **derivation honesty** (a requirement
comes from a verified artifact and a declared execution shape, never from a constant), **refinement
honesty** (only live package-owned observations mint enforcers), **serialization containment** (the
single-flight authority remains inside the opaque execution API), **retry containment** (a measured
breach maps directly to a typed terminal failure, never a string-classified retryable outcome), and
**mechanism honesty** (the closed lane table claims only what its installer actually provides, and
cohort calibration is recorded as validation evidence rather than represented by an authored
"observed" constructor).

### Per-lane enforcement

Each lane declares what it can install for each resource it enforces. The table is the contract; a
lane may not claim a strength its mechanism does not provide.

| Lane | Host memory | Installed-ceiling provenance | Device memory |
|---|---|---|---|
| `apple-silicon` | detection — unified memory, no cgroups, and the address-space limit is aliased to an advisory limit that rejects every finite ceiling | not applicable — this lane installs nothing, so no projection is taken | not applicable |
| `linux-cpu` | prevention over private writable mappings, under a larger pod envelope; detection over the residue | artifact plus the engine's own projection where its family ships one; otherwise artifact admission plus the admitted lane budget | not applicable |
| `linux-gpu` | prevention over private writable mappings; detection over pinned and shared host memory | artifact plus the engine's own projection where its family ships one; otherwise artifact admission plus the admitted lane budget | admission and arena sizing, plus detection. No kernel mechanism bounds device memory on any lane |

The projection is asked for exactly where its answer is used. It only ever changes an *installed*
quantity — the launch prefix and the read-back it is compared against — so a lane whose arm is
detection-only takes no projection at all: probing there would spend a process to change nothing.
Its sampled execution bound still uses the admitted lane budget when no projection is taken, and the
value records that this budget is not an artifact-derived requirement.

**Declared exemption.** The operator CLI passthrough and the pre-manifest host-tool probes are named
exemptions from the raw-spawn gate: their executable and argv come
from the operator's own invocation, or they run before the manifest a closed command would need
exists. The exemption list is enumerated in `Infernix.Lint.HaskellStyle` and is part of the
contract, not a gap in it.

### The device observer is a backstop, not a ceiling

No kernel mechanism bounds device memory on any supported lane, so the device half of a dual-resource
placement is admission plus arena sizing plus detection. A device runtime that is handed a fraction of
the card it happens to find is sized by the hardware rather than by the model, which is why the arena
is set from the admitted quantity directly and the fraction, where one exists, is an admission check
rather than a ceiling.

The device sampler is the same shape as the Apple footprint observer: a fixed, bounded public-tool
kernel in `Infernix.Runtime.CappedEngine.FixedObserver` whose request vocabulary is a closed enum and
whose `FixedObserverSpec` is unexported, so no caller can supply an executable, argument vector,
environment, or working directory. Enforcement pins `/usr/bin/nvidia-smi` as a literal absolute path
rather than resolving it from the host-tools manifest: an enforcement observer that follows a
configurable path is redirectable, which is exactly what the closed catalog exists to prevent.
The Apple and NVIDIA request catalogs, fixed specifications, samplers, probes, and watchdog seams are
ordinary Haskell values selected from `System.Info.os` at run time. There is no CPP wall around
either family: every supported build presents both arms to GHC, so the repository's `-Wall -Werror`
gate checks the whole enforcement module family even though only the host-appropriate public tools
may execute.

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

## Validation

A request for an unavailable row publishes a clean per-row `status=failed` carrying typed
`InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` and is not
launched. Configuration validation may surface capacity diagnostics, but it must not fail the whole
daemon because one catalog model is too large — smaller models continue to run, and the suite
classifies this constructor as a clean capacity failure, distinct from a missing result, a stall, or
a fabricated pass.


- `cabal build all` under `-Wall -Werror` plus the negative-compilation suite proves external callers
  cannot construct or relabel grants/enforcers, add a device quantity to a host sum, refine a plan
  from raw observations, import hidden
  decoder/routing modules, launch an engine from a raw model/config record, or reach a spawn without
  passing through the installation region. The suite carries a matching positive control for each
  such refusal, because a negative fixture that would fail for an unrelated reason proves nothing.
- `cabal test infernix-haskell-style` (`infernix test lint`) runs the capability-gating lints and keeps
  the style gate clean; `cabal test infernix-unit` covers the partition oversubscription rejection, the
  derivation's refusals against a malformed artifact header, the closed cache-size function against a
  pinned artifact fixture, exhaustive compiler placement-or-unavailable accounting, and
  live-refinement failures.
- The installed ceiling is proved by **reading it back inside the process it binds**, after the image
  is replaced and before any weight is loaded, and comparing both the soft and the hard value against
  the quantity the plan installed. A limit that was set is not the same claim as a limit the running
  image fits under, and only the process that will allocate can report the second.
- The behavioral suite for a lane is the proof that the contract holds on that lane: the full per-model
  real-inference lane completes without exhausting the host, an over-capacity model produces a typed
  `status=failed` `ModelMemoryLimitExceeded` rather than a `SIGKILL`, and each completing row's
  observed peak sits inside its derived ceiling. The last of those is what makes the run evidence
  rather than absence of evidence. Completing without exhaustion is a sample of this lane's behaviour,
  not evidence that a bound exists; the bound is proved by the typed gates above.
- Cohort calibration validates the authored mechanism table: a real engine starts under the installed
  ceiling, reads it back, initializes its runtime, and an over-budget allocation is prevented without
  killing the daemon. The receipt is behavioral evidence; no `HostCeilingCalibrationObserved`
  constructor is minted from a handwritten constant.
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
- [typed_execution_plan.md](typed_execution_plan.md) — the generated execution language these
  requirements and enforcers are expressed in.
- [model_catalog.md](model_catalog.md) — the catalog entry shape whose memory terms are derived here.
- [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md) — why the enforcement
  and observation tools are pinned literals rather than manifest fields.
- [../development/python_policy.md](../development/python_policy.md) — the worker-to-adapter contract
  that carries the execution shape and the admitted quantities to the engine.
