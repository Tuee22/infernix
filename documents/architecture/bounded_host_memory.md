# Bounded Host Memory

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [bounded_inference_memory.md](bounded_inference_memory.md), [managed_state_transitions.md](managed_state_transitions.md), [typed_execution_plan.md](typed_execution_plan.md), [../development/local_dev.md](../development/local_dev.md)

> **Purpose**: Define the host-memory capacity ledger and the declared-ceiling invariant — every
> memory-consuming process this repository starts runs under a ceiling derived from measured
> physical RAM — and state precisely which host out-of-memory conditions that does and does not
> make unrepresentable.

## TL;DR

- **The capacity ledger has one entry, and the process that took the machine down was not in it.**
  [bounded_inference_memory.md](bounded_inference_memory.md) partitions physical RAM into
  `vmReserve + headroom + inferenceCapacity` and names exactly one claimant: a single serialized
  inference. `minHostHeadroomMib` documents who `headroom` covers — the OS, the control-plane
  binary, the routed end-to-end browser, and worst-case watchdog overshoot. The Haskell toolchain
  is not among them. So `headroom` is not a budget; it is a residual that every unmodelled
  consumer draws from anonymously.
- **The consequence, stated once:** a host-side `cabal build` from this checkout reached
  109.46 GiB resident on a 124.94 GiB host, wedged the machine for five and a half hours, and was
  never selected by the kernel — it ran at `oom_score_adj` 0 while every cluster pod sat at
  996–1000. It did not exceed its budget. **It had no account it could exceed.**
- **The invariant**: every host toolchain process runs under a ceiling derived from measured
  physical RAM, and a ceiling that was never divided by the concurrency it will be multiplied by
  cannot be constructed as a value. A per-process cap is not a host bound: with `jobs` at the
  host's core count, the real worst case is `jobs × cap`.
- **Three legs, in descending strength**: a declared ceiling the type system requires; an operating
  system mechanism that enforces it, resolved per lane and failing closed when unavailable; and a
  victim rank that decides who dies when the first two are not enough. Only the first is by
  construction, and this document says so wherever it matters.
- **This does not make host out-of-memory impossible**, and no wording here claims it does. See
  [What this does not bound](#what-this-does-not-bound).

## The invariant

For every process this repository starts that can consume unbounded host memory, there is a
declared ceiling, and the operation that starts it consumes that ceiling as typed evidence.

Three clauses.

**1 — A ceiling is inseparable from its concurrency.** The declared quantity is a *budget* for an
account, not a per-process number. The per-process ceiling is derived from the budget and the job
count together, in one place, so a budget stated without its concurrency has no inhabitant. This
clause exists because the obvious form of the fix is wrong: a 48 GiB per-process heap cap under
`jobs: $ncpus` on a 32-core host permits 1536 GiB.

**2 — A toolchain spawn requires the derived plan.** The raw spawn is unexported and the closed
invocation vocabulary is the only way to name `cabal`. Starting a build from a bare command list
does not typecheck. This is the same shape as the unexported raw cluster teardown consuming typed
ownership evidence in [managed_state_transitions.md](managed_state_transitions.md), and the same
shape as engine launch requiring an opaque `ExecutableModel` in
[bounded_inference_memory.md](bounded_inference_memory.md).

**3 — The mechanism is resolved, never assumed.** Each lane resolves the strongest bound its
platform actually provides, and a lane with no available mechanism is a named refusal rather than
a silent pass. What each mechanism does and does not cover is recorded below, because they are not
interchangeable: only a cgroup ceiling bounds the *sum* of a process tree.

## Enforcement

| Surface | Mechanism | Forbids |
|---|---|---|
| Types | GHC module export lists (opaque types, hidden constructors) under `-Wall -Werror` | constructing a build ceiling outside its minting module; deriving a per-process ceiling without the concurrency it is multiplied by; starting a toolchain process without the derived plan |
| Region | rank-2 `forall s.` scope on the spawn authority | using a ceiling outside the region that established it, or reusing a spent one |
| OS (Linux, host-native) | cgroup v2 scope with a memory maximum, plus a runtime heap cap and an address-space rlimit | a build tree whose *aggregate* resident memory exceeds the account's budget |
| OS (Linux, outer container) | the container's own cgroup limit, plus the runtime heap cap and rlimit | the same, bounded by the container envelope rather than a nested scope |
| OS (Apple host-native) | runtime heap cap plus bounded concurrency only | an unbounded per-process heap; the aggregate is arithmetic, not enforcement, and this document says so |
| Victim rank | inherited `oom_score_adj` raised on the spawned child | the kernel being structurally unable to select the process holding the memory |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` rule `unboundedToolchainSpawnViolations` | a toolchain spawn surface that never observes the declared ceiling — see [Bounded build memory](#bounded-build-memory) |

### Bounded build memory

A repository that bounds every subprocess it supervises is not bounded if the build that produces
that repository is unbounded, and until this doctrine it was not. Every spawn kernel here carries a
required deadline, a capture limit, and a bounded descriptor space; none of them carries a memory
ceiling, and the one spawn path that runs the compiler carries none of the three. The measurement
that settles the scale: the Glasgow Haskell Compiler reserves **1024.65 GiB** of virtual address
space at startup, and a single compiler process in this checkout reached **109.46 GiB resident** on
a **124.94 GiB** host. The reservation is not the hazard — the resident set is — but the two are
routinely confused, and the incident report that first recorded this failure misread one as the
other.

The doctrine answer is to bound the resource, not to abandon the build. The compiler runtime accepts
an explicit reservation size, which reduces that 1024.65 GiB to **1.45 GiB at identical resident
memory**; that is what makes an address-space rlimit installable at all, because a process cannot
lower its own address-space limit below a reservation it has already taken. With the reservation
bounded, the ceiling is established as the first action of a process image and inherited across
`fork` and `exec` — verified through the real chain of launcher, `cabal`, its setup helper, and the
compiler itself, each carrying the identical limit. The runtime degrades gracefully rather than
failing: under a 4 GiB address-space limit it clamps its reservation to 3.12 GiB and compiles
normally, and usable resident memory tracks the limit linearly at roughly a third of it, because
the runtime reserves about three quarters of the limit and its copying collector needs two
semispaces. Both the soft and the hard limit are lowered, which remains unprivileged and one-way;
lowering only the soft limit would leave a bound any child could raise back.

The fail-closed half is an observation at the point of use: a toolchain spawn that cannot resolve a
ceiling refuses by name rather than proceeding unbounded, so a process image that forgets to
establish the bound is a loud, attributable failure instead of a machine that stops responding.
Because it is checked where the spawn happens, it holds even if a future entry point forgets.

Two residual review-obligations remain and are named rather than hidden. **Aggregate honesty**: on
a lane with no cgroup, `jobs × cap` is arithmetic performed by this repository, not a bound
enforced by the kernel, and a build that exceeds it is bounded only by the honesty of the two
declared numbers. **Calibration honesty**: a ceiling set below what a legitimate build needs
converts a working development loop into a failing one, so the shipped value is a measured multiple
of an observed peak, and the measurement — not the number — is the thing that has to be maintained.

### What this does not bound

This section is load-bearing. The predecessor doctrine claimed in its own purpose block that a host
out-of-memory kill was structurally unrepresentable, and contradicted itself later in the same
file. The correct statement is narrower and is the one this suite uses:

> Infernix bounds the memory of the processes it starts. What is unrepresentable is an *unbounded
> infernix-started process*: an engine launched without an enforcer, or a toolchain process
> spawned without a declared ceiling, does not typecheck. What remains representable is a host
> out-of-memory condition caused by the sum of bounded things, by an unbounded thing this
> repository does not own, or by memory the kernel attributes to no process at all. When the host
> runs out of memory anyway, this repository's obligation is that its own processes are the ones
> the kernel selects first, and that the failure is immediate and visible — not that the condition
> never arises.

Concretely outside the bound, and deliberately not claimed:

- **The partition carries no build term.** The ledger names the toolchain account, but the checked
  host partition does not yet include it, so the sum of declared claims is not compared against
  physical memory. Naming a claimant is not the same as booking it.
- **The sum of cluster pod limits is not checked against node allocatable.** Kubernetes schedules on
  requests rather than limits, so a node can be overcommitted regardless of what this ledger says.
- **The nested builds are outside the ceiling.** The setup helper's own compilation, the formatter
  tool install, and the per-fixture compile-fail builds each carry their own job count.
- **Memory attributed to no process** — unreclaimable kernel slab, page tables, and dirty page
  cache awaiting writeback, which is pinnable to a substantial fraction of physical memory and is
  generated by exactly the disk-backed volumes the engine pods use.
- **The container runtime itself**, which runs at a strongly negative `oom_score_adj` by design, so
  its growth is never reclaimed by the kernel's selection and the kill lands elsewhere.
- **Processes this repository did not start** — an operator's editor, browser, or a second
  checkout's cluster. Another tenant's cluster was resident during the incident.
- **Kernel admission control**, which on the supported hosts is disabled: allocations succeed until
  physical exhaustion, so no reasoning here may assume commit accounting.
- **A co-resident virtual-machine pledge.** On the supported Apple host the container lanes run
  inside a Linux VM, and the memory that VM has pledged is not memory the toolchain account may also
  spend. The two supported lanes are therefore **nested, not independent**: `linux-cpu` executes
  *inside* the VM whose pledge the Apple account must already have subtracted. The Darwin account
  does not currently intersect that pledge — it sets effective memory equal to physical, where the
  Linux account intersects the cgroup maximum — so on a host whose VM is running, the declared
  toolchain budget and the VM's reservation can together exceed physical memory. The doctrine's own
  rule is what this violates: a ceiling multiplied by a job count is only a bound if the budget it
  divides is memory that is actually available. Note that the *inference* budget already performs
  this intersection on Darwin while the toolchain account does not, so two subsystems in this
  repository presently disagree about the same RAM; the intersecting one is right.
- **The Apple lane**, until its cohort wave measures it. Darwin aliases the address-space limit to
  an advisory resident-set limit, has no cgroups, and has no equivalent global out-of-memory
  killer; unified memory means accelerator allocations draw on the same pool.

### The lane distinction is in the types, not only in this prose

Saying "the mechanism is resolved per lane" and then writing one platform-independent bound type is
how the sentence above got contradicted in code. `RLIMIT_AS` on Darwin is not merely advisory — the
kernel reports it infinite and **rejects every finite ceiling written against it** with `EINVAL`, so
there is no ceiling to install and nothing for a bound to witness. A spawn wrapper that assumed one
threw before its child ever started, taking `infernix test lint`, `test unit`, `test integration`
and `test all` down on that lane.

So `BuildMemoryMechanism` is indexed by `AddressSpaceEnforcement`, and `BuildMemoryBound` carries
that index. `enforcedAddressCeilingMib` is defined only for `'AddressSpaceEnforced`: asking an
unenforced lane for its address-space ceiling is a type error rather than a plausible integer, and a
compile-fail fixture pins it. Each mechanism constructor fixes its own index, so the claim and the
evidence are one fact and cannot drift apart.

Be precise about what that buys. GHC cannot decide which lane a binary runs on; the index is refined
from a runtime observation by `resolveBuildMemoryMechanism`. What becomes unrepresentable is *using*
an unenforced bound as though it were enforced. And an unenforced bound still observes something
rather than asserting its own argument: it re-reads the runtime heap cap committed to
`cabal.project.local` and refuses when that disagrees with the derived plan, which is the same act
as the enforced lane's post-write re-observation.

### A note on the word "bounded"

Throughout this suite, "bounded" means **time, captured output length, and descriptor space** — the
three dimensions [managed_state_transitions.md](managed_state_transitions.md) gives the command
kernel. It does not mean memory. This document and
[bounded_inference_memory.md](bounded_inference_memory.md) are the only two places where a bound on
memory is asserted, and each says which memory it bounds. A stage-0 entrypoint described elsewhere
as "bounded" is bounded in those three dimensions and, once this doctrine lands, in the declared
ceiling it passes to the toolchain — not otherwise.

## Validation

- `cabal build all` under `-Wall -Werror` plus the negative-compilation suite proves a toolchain
  process cannot be started without a derived ceiling, and that a ceiling cannot be derived without
  its concurrency.
- `cabal test infernix-haskell-style` runs `unboundedToolchainSpawnViolations`, which is verified to
  fail on a reintroduced uncapped toolchain spawn and reverted after the negative-test confirmation.
- `cabal test infernix-unit` asserts that the bound holds in a spawned child, that an unresolvable
  ceiling is a named refusal rather than a silent pass, that establishing the bound never raises a
  tighter host-imposed limit, and that the limit is inherited through the compiler chain.
- An adversarial over-allocation under the ceiling exits non-zero and cleanly, with no global
  out-of-memory condition — the same fail-clean shape the resident-set and accelerator-memory
  breach fixtures give for the inference lane.
- `infernix lint docs` keeps this document registered, structured, and linked.
- The Apple lane's mechanism is proven by its cohort wave, not by this gate set. Until that wave
  records a result, no claim in this suite covers it.

## Cross-References

- [bounded_inference_memory.md](bounded_inference_memory.md) — the inference row of the ledger
- [managed_state_transitions.md](managed_state_transitions.md) — the evidence discipline this
  invariant instantiates, and the bounded descriptor space it is modelled on
- [typed_execution_plan.md](typed_execution_plan.md) — the compiled-plan boundary
- [realness_contract.md](realness_contract.md) — the fail-clean results discipline
- [../development/local_dev.md](../development/local_dev.md) — the operator build workflow
- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) — sprint ownership
