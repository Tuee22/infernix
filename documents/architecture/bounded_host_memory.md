# Bounded Host Memory

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [bounded_inference_memory.md](bounded_inference_memory.md), [managed_state_transitions.md](managed_state_transitions.md), [typed_execution_plan.md](typed_execution_plan.md), [../development/local_dev.md](../development/local_dev.md)

> **Purpose**: Define the host-memory capacity ledger and the toolchain claimant invariant — every
> Haskell toolchain image carries an authority-derived heap ceiling, every compiler worker carries a
> declared helper/native-auxiliary slot, and the complete concurrency arithmetic is checked against
> measured host RAM — while stating precisely which host out-of-memory conditions remain possible.

## TL;DR

- **The capacity ledger has separate inference and toolchain accounts.**
  [bounded_inference_memory.md](bounded_inference_memory.md) partitions physical RAM into
  `vmReserve + headroom + inferenceCapacity` for a serialized inference. The Haskell toolchain uses
  its own authority-derived account, and governed workflows serialize the accounts rather than
  funding their simultaneous overlap from inference headroom.
- **Measurement anchors the toolchain account.** A host-side `cabal build` from this checkout
  reached 109.46 GiB resident on a 124.94 GiB host while running at `oom_score_adj` 0 and therefore
  demonstrated why compiler concurrency, heap, helper slots, and victim rank must travel together.
- **The invariant**: the normal compiler phase is accounted as
  `jobs × compilerHeap + (jobs + 1) × controlHeap`. The extra claims are the live Cabal driver plus
  one helper/native-auxiliary slot per worker. A per-process cap is not a host bound, and Darwin's
  claimant sum is arithmetic and sampled evidence rather than an enforced aggregate.
- **Single-flight is authority-local, not host-global.** One opaque authority serializes calls to
  its package-owned child lifecycle. Independent CLI images, checkouts, and stage-0 bootstrap
  processes do not share that token, are unsupported concurrent toolchain claimants, and must be
  serialized by the governed workflow. The 50% account does not fund their overlap.
- **Three legs, in descending strength**: a declared ceiling the type system requires; an operating
  system mechanism that enforces it, resolved per lane and failing closed when unavailable; and a
  victim rank that decides who dies when the first two are not enough. Only the first is by
  construction, and this document says so wherever it matters.
- **This does not make host out-of-memory impossible**, and no wording here claims it does. See
  [What this does not bound](#what-this-does-not-bound).

## The invariant

For every Haskell toolchain image the repository starts, there is an authority-derived heap ceiling.
For every admitted compiler worker, the account additionally reserves one fixed control/helper slot
for its overlapping Haskell or native auxiliary. The operation that starts Cabal consumes the typed
plan carrying that complete claimant arithmetic.

Three clauses.

**1 — A ceiling is inseparable from its concurrency and companion claims.** The declared quantity
is a *budget* for an account, not a per-process number. The plan first reserves the fixed 1024 MiB
control heap for the live Cabal driver and one worker-associated helper per compiler job, then
divides the residual across compiler heaps. This clause exists because the obvious form of the fix
is wrong: a 48 GiB per-process heap cap under `jobs: $ncpus` on a 32-core host permits 1536 GiB before
the driver or auxiliaries are counted.

**2 — Every repository-owned toolchain spawn consumes the derived plan.** The CLI uses a closed
invocation vocabulary, and the Haskell-style lint rejects a new raw `HostCabal` spawn surface that
does not carry the complete package-owned lifecycle. This is not a universal ban on importing
`System.Process`: the opaque authority and its hidden token govern the repository-owned CLI path,
while the lint is its source-level backstop.

**3 — The mechanism is resolved, never assumed.** Each lane resolves the strongest bound its
platform actually provides, and a lane with no available mechanism is a named refusal rather than
a silent pass. What each mechanism does and does not cover is recorded below, because they are not
interchangeable: only a cgroup ceiling bounds the *sum* of a process tree.

## Enforcement

| Surface | Mechanism | Forbids |
|---|---|---|
| Types | GHC module export lists (opaque types, hidden constructors and nominal role annotations) under `-Wall -Werror` | constructing a build ceiling outside its minting module; deriving a per-process ceiling without the concurrency it is multiplied by; coercing either the spawn authority or Darwin refinement across region tags |
| Region | rank-2 `forall s.` scope plus one private `MVar` on the spawn authority | using a ceiling outside the region that established it; coercing its region tag; overlapping two package-owned child lifecycle calls through one authority |
| OS (Linux) | an existing cgroup v2 maximum when the execution context supplies one; otherwise Haskell runtime heap caps plus a temporarily inherited per-process address-space rlimit | the current cgroup bounds its aggregate when present; without it, only individual Haskell/address-space images are enforced and the claimant sum remains arithmetic |
| OS (Linux, outer container) | the container's own cgroup limit, plus the runtime heap cap and rlimit | the same, bounded by the container envelope rather than a nested scope |
| OS (Apple host-native) | Haskell runtime heap caps plus bounded concurrency | an unbounded Cabal/compiler/test Haskell heap; the native-helper reserve and aggregate are arithmetic plus sampled evidence, not enforcement |
| Victim rank | inherited `oom_score_adj` raised on the spawned child | the kernel being structurally unable to select the process holding the memory |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` rule `unboundedToolchainSpawnViolations` | a toolchain spawn surface that never observes the declared ceiling — see [Bounded build memory](#bounded-build-memory) |

### Bounded build memory

A repository that bounds every subprocess it supervises must also bound the build that produces
that repository. Every compiler spawn consumes the toolchain plan in addition to the ordinary
deadline, capture, and descriptor-space bounds. The measurement that settles the scale: the
Glasgow Haskell Compiler reserves **1024.65 GiB** of virtual address
space at startup, and a single compiler process in this checkout reached **109.46 GiB resident** on
a **124.94 GiB** host. The reservation is not the hazard — the resident set is — but the two are
routinely confused.

The doctrine answer is to bound the resource, not to abandon the build. The compiler runtime accepts
an explicit reservation size, which reduces that 1024.65 GiB to **1.15 GiB at identical resident
memory**; that is what makes an address-space rlimit installable at all, because a process cannot
lower its own address-space limit below a reservation it has already taken. With the reservation
bounded, a dedicated build image can establish a hard lower-only limit before its children, while
the long-lived operator CLI temporarily lowers only its soft limit across the complete Cabal leader
lifecycle so later non-toolchain work does not inherit the build ceiling. The package is
`build-type: Simple`: there is
no custom Setup image, setup-time nested Cabal bootstrap, native `protoc`, or Haskell generator plugin
on the Darwin build path. The runtime degrades gracefully rather than
failing: under a 4 GiB address-space limit it clamps its reservation to 3.12 GiB and compiles
normally, and usable resident memory tracks the limit linearly at roughly a third of it, because
the runtime reserves about three quarters of the limit and its copying collector needs two
semispaces. The stronger dedicated-image path lowers both soft and hard limits; the production CLI
spawn boundary documents the weaker soft-only inheritance explicitly.

The fail-closed half is an observation at the point of use: a toolchain spawn that cannot resolve a
ceiling refuses by name rather than proceeding unbounded, so a process image that forgets to
establish the bound is a loud, attributable failure instead of a machine that stops responding.
Because it is checked where the spawn happens, it holds even if a future entry point forgets. On
Darwin the observation is the complete generated `cabal.project.local` triple — exactly one
`jobs:` row, one `-M` heap cap, and one `-xr` runtime reservation, all equal to the live plan — not
the heap cap alone. The fixed control cap is carried by the same plan. This distinction is
load-bearing: a 64 GiB host with a 48 GiB active Colima pledge yields an 8192 MiB account, one worker,
two 1024 MiB control claims, and a 6144 MiB residual compiler heap. Checking only a plausible heap
value can accept stale concurrency and recreate the oversubscription. The opaque spawn authority
consumes that observation when minted, and the child boundary repeats it immediately before the fork
so a file changed inside the authority region cannot authorize a different plan.

The opt-in Darwin evidence producer is the closed
`infernix internal validate-darwin-build-memory` command. It accepts only the resolved
`UnenforcedLane DarwinHeapCapMechanism`, consumes the live plan and exact final settings
observation, and starts fresh `cabal build all --enable-tests` followed by `cabal install ...
all:exes` in an internally created scratch build root. Both children receive a leading direct Cabal
`+RTS -M1024M -RTS`, the same fixed build-only `GHCRTS` value for system Haskell tools, and the
authority-derived `--jobs` plus one ordered `--ghc-options=+RTS -M... -xr... -RTS` value for GHC.
Each invocation owns a fresh process
group whose **sampled peak aggregate physical footprint** is observed at a fixed cadence through
the existing fixed Apple observer. Observer loss fails closed. Before the leader is reaped, normal
completion proves that the fixed observer sees no live group member; exceptional cleanup first
signals the still-owned group and then performs the same live-member observation. The leader crosses
a masked nonblocking reap transition only after that observation, and no numeric PGID is probed or
signaled after reap. Its typed report records physical and effective memory,
the active Colima pledge, every plan field and the checked
`jobs × compilerHeap + (jobs + 1) × controlHeap` account, the sampling
interval/count/maximum, the fixed-point `planAccountToSampledPeakMultiple`, and invocation exits
and durations. The build must yield a positive sample. A reused install can finish before the first
one-second probe; that is reported as explicit terminal-before-first-probe evidence with zero
samples, never converted into a fabricated footprint. A final fixed proof also runs the freshly
installed operator binary with adversarial invalid `GHCRTS` and requires its `ignoreAll` linkage to
reach Haskell `main` without copying the scratch image into the repository build root. The operator
CLI parent and fixed observer tools remain in the non-toolchain host reserve and outside both the
sampled Cabal group and account. The result remains a measurement, not
an aggregate Darwin enforcement claim: fixed-cadence samples can miss a transient peak, and page
cache, kernel-owned memory, the container runtime, and processes Infernix did not start remain
outside it.

Two residual review-obligations remain and are named rather than hidden. **Aggregate honesty**: on
a lane with no cgroup, the compiler plus control/helper claimant sum is arithmetic performed by this
repository, not a bound enforced by the kernel, and a build that exceeds it is bounded only by the
honesty of the declared numbers. **Calibration honesty**: a ceiling set below what a legitimate build needs
converts a working development loop into a failing one, so the shipped value is a measured multiple
of an observed peak, and the measurement — not the number — is the thing that has to be maintained.

### What this does not bound

This section is load-bearing. The contract is deliberately narrower than a claim that host
out-of-memory is structurally unrepresentable:

> Infernix requires an enforcer for inference and a complete claimant plan for the toolchain.
> Haskell toolchain images carry runtime heap caps; worker-associated native helpers carry measured
> account slots which are not kernel-enforced on Darwin. What remains representable is a host
> out-of-memory condition caused by the sum of capped and reserved things, by an unbounded thing this
> repository does not own, or by memory the kernel attributes to no process at all. When the host
> runs out of memory anyway, this repository's obligation is immediate visible failure and honest
> evidence — not a claim that the condition can never arise.

Concretely outside the bound, and deliberately not claimed:

- **The inference partition carries no simultaneous build term.** The checked host partition and
  toolchain account are not compared as simultaneous claims because the governed workflow
  serializes them. The inference headroom does not fund toolchain overlap.
- **Authority-local serialization is not a host lease.** A second CLI image, another checkout, or a
  stage-0 bootstrap has a distinct or absent token. Running those toolchain trees concurrently is
  unsupported, their overlap is not funded by the 50% account, and governed workflows must
  serialize them. There is no crash-surviving or machine-global lease.
- **Normal Cabal completion is leader-scoped.** The trusted scheduler leader is reaped normally and
  its owned group is killed/reaped only on an exception before that point. There is no portable
  post-reap descendant proof, and a hard-killed owner may leave descendants outside this lifecycle.
- **The sum of cluster pod limits is not checked against node allocatable.** Kubernetes schedules on
  requests rather than limits, so a node can be overcommitted regardless of what this ledger says.
- **Nested toolchain work is separately accounted, not silently inherited.** The package has no
  custom Setup. Ormolu and HLint run in one pinned in-process test component, while Cabal formatting
  runs in a separate pinned in-process component because their Cabal-syntax closures are
  incompatible; style validation performs no formatter install. The serialized compile-fail child
  uses one 2048 MiB compiler plus four 1024 MiB control/auxiliary claims (outer Cabal, test runner,
  nested Cabal, and worker auxiliary): 6144 MiB inside its declared 8192 MiB outer account. The Linux
  image's pinned proto-plugin installation and byte-regeneration proof use fixed driver/helper caps;
  Darwin consumes only the tracked four-module snapshot and exact hash drift check.
- **Native compiler auxiliaries on Darwin are reserved, not heap-enforced.** A linker or other native
  helper overlaps its compiler inside the worker's 1024 MiB slot. Sampling can detect the aggregate
  it observes, but the kernel does not make that native slot a hard ceiling.
- **The operator CLI parent and fixed observer tools are outside the toolchain account.** They are
  host-reserve claimants by design and are excluded from the sampled Cabal process group. The shipped
  runtime ignores build-only `GHCRTS`; applying the 1024 MiB toolchain control cap to service or
  inference behavior would require a separate runtime calibration.
- **Memory attributed to no process** — unreclaimable kernel slab, page tables, and dirty page
  cache awaiting writeback, which is pinnable to a substantial fraction of physical memory and is
  generated by exactly the disk-backed volumes the engine pods use.
- **The container runtime itself**, which runs at a strongly negative `oom_score_adj` by design, so
  its growth is never reclaimed by the kernel's selection and the kill lands elsewhere.
- **Processes this repository did not start** — an operator's editor, browser, or a second
  checkout's cluster.
- **Kernel admission control**, which on the supported hosts is disabled: allocations succeed until
  physical exhaustion, so no reasoning here may assume commit accounting.
- **A co-resident virtual-machine pledge is observed, not enforced.** On the supported Apple host
  the container lanes run inside a Linux VM, and the memory that VM has pledged is not memory the
  toolchain account may also spend. The two supported lanes are therefore **nested, not
  independent**: `linux-cpu` executes *inside* the VM whose pledge the Apple account must already
  have subtracted. Darwin's `effectiveMemoryMib` is physical RAM minus the aggregate pledge of every
  Colima profile not explicitly reported `Stopped`, using the same fixed-path, deadline-bounded
  producer and conservative parser as the inference partition. An unavailable executable, a failed
  probe, malformed output, or a pledge that leaves no physical memory is a named refusal, never a
  zero-pledge default. The arithmetic prevents toolchain/VM double booking; it does not make the VM
  keep its pledge. After changing the VM pledge, rerun the Apple bootstrap and `infernix init` before any
  focused gate so both the stage-0 preflight and generated project file observe the new state.
- **The Apple lane has no kernel-enforced aggregate.** Darwin aliases the address-space limit to
  an advisory resident-set limit, has no cgroups, and has no equivalent global out-of-memory
  killer; unified memory means accelerator allocations draw on the same pool. Its claimant sum is
  arithmetic plus sampled evidence.

### The lane distinction is in the types, not only in this prose

`RLIMIT_AS` on Darwin is not merely advisory: the kernel reports it infinite and rejects every
finite ceiling written against it with `EINVAL`, so there is no ceiling to install and nothing for a
bound to witness. `BuildMemoryMechanism` is indexed by `AddressSpaceEnforcement`, and `BuildMemoryBound` carries
that index. `enforcedAddressCeilingMib` is defined only for `'AddressSpaceEnforced`: asking an
unenforced lane for its address-space ceiling is a type error rather than a plausible integer, and a
compile-fail fixture pins it. Each mechanism constructor fixes its own index, so the claim and the
evidence are one fact and cannot drift apart.

Be precise about what that buys. GHC cannot decide which lane a binary runs on; the index is refined
from a runtime observation by `resolveBuildMemoryMechanism`. What becomes unrepresentable is *using*
an unenforced bound as though it were enforced. And an unenforced bound still observes something
rather than asserting its own argument: it strictly re-reads the generated job count, runtime heap
cap, and runtime reservation committed to `cabal.project.local`, rejects missing or duplicate
settings, and refuses when any value disagrees with the derived plan. The production authority mint
consumes that evidence and its spawn boundary performs the final exact re-observation. It then
derives Cabal's `--jobs` plus one ordered `--ghc-options=+RTS -M... -xr... -RTS` argument from the opaque
authority and supplies them directly to the child as final-precedence configuration. Cabal can still
reopen the mutable project file, but a post-check replacement cannot override the exact command-line
concurrency or RTS caps. A test-only call to
the observer is not a substitute for wiring the observation into the only constructor that can
authorize a child.

The normal CLI child first observes the descriptor-space ceiling, closes inherited descriptors,
and starts Cabal as a fresh process-group leader. The same authority-local token remains held
through victim-rank adjustment and a fixed-cadence `getProcessExitCode` poll. The nonblocking probe
and its positive waitpid/`ProcessHandle` transition remain masked; only the delay while the leader
is still unreaped is interruptible. An exception before that leader is reaped signals the owned
group and performs a bounded leader reap. Normal completion trusts Cabal as the scheduler to wait
for its ordinary workers and returns after reaping that leader. It deliberately does **not** signal
or prove a numeric process group after the leader is reaped, because the PGID could already identify
an unrelated group. Consequently this is not a normal descendant-absence proof and does not survive
hard-killing the owning CLI.

### A note on the word "bounded"

Throughout this suite, "bounded" means **time, captured output length, and descriptor space** — the
three dimensions [managed_state_transitions.md](managed_state_transitions.md) gives the command
kernel. It does not mean memory. This document and
[bounded_inference_memory.md](bounded_inference_memory.md) are the only two places where a bound on
memory is asserted, and each says which memory it bounds. A stage-0 entrypoint described elsewhere
as "bounded" is bounded in those three dimensions and in the declared ceiling it passes to the
toolchain — not otherwise.

## Validation

- `infernix test lint` plus the negative-compilation suite exercises the closed toolchain authority
  under `-Wall -Werror` and proves a package consumer cannot construct that authority, derive a
  ceiling without its concurrency, or coerce the spawn/Darwin authority across nominal region tags.
- the Haskell-style arm of `infernix test lint` runs `unboundedToolchainSpawnViolations`, which is
  verified to fail on a reintroduced uncapped toolchain spawn and reverted after the negative-test
  confirmation.
- `infernix test unit` runs every closed machine-independent Haskell suite through the same authority.
  Its unit arm asserts that the bound holds in a spawned child, that an unresolvable
  ceiling is a named refusal rather than a silent pass, that establishing the bound never raises a
  tighter host-imposed limit, and that the limit is inherited through the compiler chain. Its Darwin
  regression uses two plans with the same residual compiler heap and runtime reservation but
  different job counts, proves authority mint refuses the stale one, mutates the file after a valid
  mint to prove the production child boundary re-observes it, deterministically blocks a second
  lifecycle call on the same authority until the first exits, proves exception release, admits the
  exact matching triple, and pins the final Cabal argument suffix to the authority-derived `--jobs`
  and ordered RTS flags.
- the Darwin unit adversary observes an active 64 MiB RTS heap cap, requests approximately twice that
  amount on the GHC heap, and requires an ordinary positive nonzero exit without multi-GiB host
  pressure. The enforced-address-space lane retains its separate clean over-allocation proof.
- `infernix internal validate-darwin-audiveris-cancellation` and
  `infernix internal validate-darwin-installed-python-source-isolation` own the two fixed Darwin-only
  Apple materializer test-option vectors; callers cannot supply an arbitrary Cabal target or option.
- On Darwin, `infernix internal validate-darwin-build-memory` is the opt-in evidence producer for a
  fresh build/install run and its sampled peak aggregate physical footprint. The command's presence
  is not execution evidence; a recorded invocation and bounded over-allocation adversary provide
  that evidence. Sampling never converts Darwin arithmetic into kernel enforcement.
- `infernix lint docs` keeps this document registered, structured, and linked.

## Cross-References

- [bounded_inference_memory.md](bounded_inference_memory.md) — the inference row of the ledger
- [managed_state_transitions.md](managed_state_transitions.md) — the evidence discipline this
  invariant instantiates, and the bounded descriptor space it is modelled on
- [typed_execution_plan.md](typed_execution_plan.md) — the compiled-plan boundary
- [realness_contract.md](realness_contract.md) — the fail-clean results discipline
- [../development/local_dev.md](../development/local_dev.md) — the operator build workflow
- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) — development status and validation receipts
