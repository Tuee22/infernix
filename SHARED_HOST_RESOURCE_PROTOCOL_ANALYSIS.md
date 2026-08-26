# Shared Host Resource Protocol — Critical Analysis

**Subject**: [documents/engineering/shared_host_resource_protocol.md](documents/engineering/shared_host_resource_protocol.md)
**Analysis date**: 2026-08-26
**Analysis host**: `Darwin 25.5.0 arm64`, plus the existing Colima guest `Linux 6.8.0-100-generic aarch64`

> This file is deliberately **not** part of the governed `documents/` suite. It carries measurement
> dates, adoption status, and a verdict, all of which
> [documents/documentation_standards.md](documents/documentation_standards.md) assigns to
> `DEVELOPMENT_PLAN/` rather than to doctrine. It is an analysis artifact, not a contract.

## Verdict

The document is unusually strong as engineering writing and a poor fit for this repository at
present. Every load-bearing measurement in it reproduces here. Its recommendation does not follow
for this project: keep it unadopted, repair two gate violations, and act on exactly one finding it
surfaces — a real weakness in `src/Infernix/Service.hs`.

## 1. Method

Rather than reading the claims, each was re-derived on this machine:

- the two committed artifacts, `documents/engineering/hostgrant_probe.py` and
  `documents/engineering/crash_harness.py`, were run as shipped;
- the 3x3 lock matrix was run on Darwin directly and on the Colima guest kernel through the
  operator's existing `colima` Docker context (native `linux/arm64`, no context created or switched,
  no VM provisioned);
- the Haskell lock-family question the document raises but leaves open was settled by compiling a
  probe against GHC 9.6.7 inside `haskell:9.6-slim` and contending it against `flock(1)` and the
  `unix` package's classic `fcntl` record lock;
- `./.build/infernix lint docs` and `./.build/infernix lint files` were run against the document as
  committed.

## 2. Claims that reproduce

| Claim | Section | Result here |
|---|---|---|
| Darwin arbitrates all three mechanisms | 6.2 | **Confirmed.** 9/9 cells BLOCKED, errno 35, negative control ACQUIRED in every cell |
| Linux has two families, `{flock}` and `{fcntl, OFD}` | 6.2 | **Confirmed cell for cell** on `Linux 6.8.0-100-generic aarch64`, errno 11 |
| `FD_CLOEXEC` clear leaks a grant to a spawned child | 6.2 | **Confirmed.** clear → BLOCKED after the holder is SIGKILLed; set → ACQUIRED |
| The file set never grows | 7.3 | **Confirmed.** `10 -> 10`, `grants=300 standing-claims=64 simulated-crashes=80` |
| The claim algebra's conflict and validity vectors | 5.1 | **Confirmed.** All assertions pass, including `("gpu:0","gpu:01")` and the trailing-newline trap |

The falsification table in §1, the willingness to invert its own version-1 `MUST` on evidence, and
the explicit non-guarantees in §10 and §11 are the document's best features. Its sharpest insight is
correct and matters directly here: **Darwin arbitrates all three mechanisms against each other, so a
non-conforming participant passes on the platform this project is developed on and fails silently on
the platform it deploys to.**

## 3. Conflicts with this repository

### 3.1 The document fails this repository's own documentation gate, twice

`./.build/infernix lint docs` rejects the file as committed:

1. line 4's `it is superseded` matches `forbiddenPhrases` (`src/Infernix/Lint/Docs.hs:109`, raised at
   `Docs.hs:614`);
2. the seven `2026-08-2x` lines trip the dated-evidence rule (`Docs.hs:707`).

Both were neutralized in a local scratch edit to confirm nothing else fails — the run then exits `0`
— and the edit was reverted; the working tree is unchanged.

The phrase is a one-word repair. The dates are not cosmetic.
`documents/documentation_standards.md:107` states that a governed document "never reports schedule,
sprint ownership, **validation dates**, or wave evidence." The document's entire epistemic strategy
is dated measurement, so the property that makes it credible is the property `documents/` forbids.
Retaining the platform identifiers (`Measured on Linux 6.8.0-100-generic aarch64`) and dropping the
calendar dates satisfies both. Section 1's adoption status and §11's "no project implements this
policy" are genuinely status and belong in `DEVELOPMENT_PLAN/`, as the document's own closing line
concedes.

### 3.2 Declared capacity against observed capacity

`<root>/capacity` is an operator-written integer per domain, and admission is
`held + reserved + demand <= capacity`. This project decided the opposite way:
`documents/architecture/bounded_host_memory.md:30` admits "against a live host claim and a census of
foreign toolchain claimants rather than against declared capacity alone," and the daemon-topology
doctrine requires that admitted capacity be observed, never declared.

Adopting `capacity` and `reserved` would introduce a second, drift-prone source of truth for
`host:memory` and for the Colima pledge that the Apple stage-0 preflight already measures live. The
protocol's arithmetic is also strictly weaker for the risk this project actually carries: it charges
participants only, so the sum can sit well under capacity on a machine that is out of memory.

### 3.3 Configuration substrate and operator steps

The rendezvous adds three line-oriented, schema-less, operator-edited files
(`protocol-version`, `capacity`, `reserved`) outside the repository, in a project whose rule is typed
`.dhall` produced solely by the `infernix` binary. Establishment is
`sudo mkdir -p /var/lib/hostgrant && sudo chmod 1777`, an operator step no `infernix` command can
reconcile, in a bootstrap model built on restartable prerequisite reconcilers.

This repository already solved the same problem differently.
`src/Infernix/ProcessIdentity/Internal.hs:733` self-establishes
`/tmp/infernix-process-identities-<uid>` at `0700`, owner-checked and `lstat`-checked, with no `sudo`
step and no world-writable directory that §6.1 concedes any local user can wedge. The document's
version-1 falsification killed `$HOME` as a *path source*; version 2 discarded the *per-user
partition* along with it, even though `getuid()` is a syscall rather than an environment variable —
and §6.1 then disclaims the cross-user capability that `1777` was paying for.

### 3.4 Python policy

`documents/engineering/crash_harness.py` and `documents/engineering/hostgrant_probe.py` are tracked,
while `documents/development/python_policy.md:12` permits Python "only under `python/adapters/`" and
`python/native-runners/`. They escape every gate: `check-code` runs from `python/`, the environment
read lint is path-scoped to `python/` (`src/Infernix/Lint/Files.hs:360`), and `infernix lint files`
passes. The result is tracked, ungated Python that uses `ctypes.CDLL` into `libproc`, bare-name
`subprocess` invocations, `close_fds=False`, and `rm -rf` on a computed path — every one a shape this
codebase lints out elsewhere. Section 11 anticipated the conflict ("a repository whose source policy
forbids a tracked artifact in that language generates it instead") and the files were committed
regardless.

## 4. Defects in the protocol itself

- **A grant does not cover a process tree that outlives its holder.** Section 4 assigns "a build" to
  Grant; §4.3 mandates `FD_CLOEXEC` precisely so the lock dies with the holder; §9 records that as
  "No leak." But `SIGKILL` the launcher and the compiler workers keep allocating while `host:memory`
  reads free. That is this project's recorded incident shape, and
  `documents/architecture/bounded_host_memory.md` explicitly claims no hard-kill-survival proof. The
  witness machinery in §4.1 is the correct fix, and §4's own table points away from it.
- **Slot reuse can destroy a live standing claim.** A standing claim is written with the lock
  released (§4), so its only liveness signal is its witness. Nothing in §7.2 requires
  `free_slot_of_mine()` to consult the witness, so the next `acquire()` sees a lockless slot, takes
  it, and `ftruncate`s a live cluster's claim away. `crash_harness.py` exercises exactly that reuse
  path.
- **Section 7.2's prose and pseudocode contradict each other on self-conflict.** The normative `MUST`
  says "its own live slots"; the pseudocode says `s.participant == me and s.index in
  my_own_process_slots`. The prose reading means two checkouts of one project never conflict — the
  most likely contention on a developer machine. The pseudocode reading means a self-spawned second
  image blocks on its own parent, which is the failure the prose forbids. This repository self-execs
  an anchor and a supervisor, so it lands squarely on the ambiguity.
- **Admission is order-dependent.** An exclusive demand prefix-conflicts against every held claim; a
  counted demand performs exact-match arithmetic and no prefix check at all. So exclusive
  `host:memory/build` followed by counted `host:memory 8000000000` both admit, while the reverse
  order refuses — and §5.2 explicitly invites that pair as a legitimate design. The pseudocode also
  never enforces §5.2's own malformed rules, and `capacity[d]` is an unguarded lookup.
- **`Unsupported` has no defined consequence.** On any machine without the operator step every
  participant reports it, and the document never says whether the participant then proceeds
  unguarded or refuses. For a clean-clone bootstrap that difference decides everything.
- **`Malformed` is non-retryable and scope-wide.** One buggy participant's slot permanently wedges
  every build on the machine, in a directory §6.1 concedes any local user can write. Defensible as
  fail-closed, but §10 does not list it.
- **No shared amount.** `Infernix.Python.MutationLock` and `Infernix.Engines.MaterializationLock` both
  use `FileLock.Shared`; the algebra has no expression for a shared claim.

## 5. Cost of adoption here

Two hard blockers, both measured rather than assumed.

**5.1 The lock family is wrong.** The Haskell `filelock` package uses `flock(2)` on POSIX —
`foreign import ccall interruptible "flock"` in `System/FileLock/Internal/Flock.hsc` of
`filelock-0.1.1.9`, the version pinned at `infernix.cabal:171`. So `Cluster.LifecycleLock`,
`Python.MutationLock`, `Engines.MaterializationLock`, and the `ProcessIdentity` registry are all in
`{flock}`, invisible to a conforming participant on Linux.

There is a route that does not require a `foreign import`, which the document flags as unverified and
which was settled here: GHC's `hTryLock` is genuinely **OFD** on Linux. Measured on GHC 9.6.7, it
blocks a `unix`-package `setLock` prober, is invisible to `flock(1)`, and survives the
unrelated-descriptor close that releases a classic `fcntl` lock. On Darwin it selects the `Flock`
backend, which is harmless because Darwin has one family. Conforming is therefore possible without
repo-owned FFI — but it is a migration of every lock in the repository, not a flag.

**5.2 The witness is unavailable on Darwin by permitted means.** Section 4.1 requires any process's
start time in the scope. The document's own probe reaches it through `ctypes` into `libproc`. Without
FFI, `ps -o lstart` offers one-second resolution — measured against `libproc`'s
`1787712569.227899` — which fails §11's own "two processes 50 ms apart are distinguishable" bar. This
project already hit that wall: Darwin birth identity is a registry of processes `infernix` itself
started (`src/Infernix/ProcessIdentity/Internal.hs:246`), and a registry cannot evaluate a peer
participant's witness.

**5.3 Topology.** The Apple host is two scopes, so a second rendezvous is required inside the Colima
guest, established by an operator step no bootstrap owns, destroyed by `colima delete`, and reachable
by containers only through an added compose bind mount.

## 6. Value delivered here

Close to none at present. Every shared-host failure this project has recorded was caused by a
**non-participant** — which §10 places out of scope — or by **progressive consumption**, which §10
also places out of scope while calling it "the only shared-host failure these projects have actually
recorded." The document is candid that its value is proportional to participants minus one and that
it currently has none.

The one genuinely appealing fit — a machine-global standing claim for the Kind cluster, replacing the
checkout-identity stamp written into the control-plane node — depends on the item §11 lists first
among the unverified: that a container runtime's init process is a usable witness.

Credit where it is due: §8 is careful not to collide. "A granted lock is coordination, not evidence
... Existing enforcement is unaffected" is the correct boundary, and this repository already
discharges §8's obligation structurally, so that part would be nearly free.

## 7. The finding worth acting on

`Infernix.Service.acquireEngineLock` (`src/Infernix/Service.hs:240`, path at `Service.hs:225`) takes
the `unix` package's `setLock` — a **classic `fcntl` record lock**, the one mechanism whose measured
lifetime property is that closing *any* descriptor to the same file in the same process releases it.

- It is the sole enforcement of the correctness rule "one engine process per machine."
- The integration case that exercised coexistence was retired (`test/integration/Spec.hs:276`), and
  nothing now asserts the refusal.
- It is the only lock in the repository outside the `flock` family, so the natural tidy-up — moving
  it to `System.FileLock` like everything else — would silently stop excluding on Linux while
  continuing to pass on Darwin. That is this document's central warning, already instantiated in this
  codebase.
- Secondary: `getLock` followed by `setLock` leaves a time-of-check window in which the loser dies on
  a raw `errno` instead of the intended "refusing to start a second engine on this host" diagnostic.
  Exclusion still holds — `F_SETLK` is atomic — but the diagnostic does not.

## 8. Recommendation

1. Do not open a phase for adoption.
2. Repair the two `infernix lint docs` violations so the governed suite is green; move §1 and §11's
   adoption status into `DEVELOPMENT_PLAN/`.
3. Relocate the two `.py` artifacts under `python/` where the gates reach them, or generate them as
   §11 already contemplates.
4. Record in the locking doctrine that this repository's locks are deliberately `flock`-family and
   private, so a future migration is a decision rather than an accident.
5. Open a targeted item for `engine.lock`: restore an exclusion test, and decide the mechanism
   explicitly.
6. Revisit the protocol if and when a second participant on this machine actually exists.

## Appendix: raw measurements

Darwin `25.5.0 arm64`, all cells preceded by a negative control that printed `ACQUIRED`:

```console
holder=flock prober=flock  contended=BLOCKED 35
holder=flock prober=fcntl  contended=BLOCKED 35
holder=flock prober=ofd    contended=BLOCKED 35
holder=fcntl prober=flock  contended=BLOCKED 35
holder=fcntl prober=fcntl  contended=BLOCKED 35
holder=fcntl prober=ofd    contended=BLOCKED 35
holder=ofd   prober=flock  contended=BLOCKED 35
holder=ofd   prober=fcntl  contended=BLOCKED 35
holder=ofd   prober=ofd    contended=BLOCKED 35
```

`Linux 6.8.0-100-generic aarch64`:

```console
holder=flock prober=flock  contended=BLOCKED 11
holder=flock prober=fcntl  contended=ACQUIRED
holder=flock prober=ofd    contended=ACQUIRED
holder=fcntl prober=flock  contended=ACQUIRED
holder=fcntl prober=fcntl  contended=BLOCKED 11
holder=fcntl prober=ofd    contended=BLOCKED 11
holder=ofd   prober=flock  contended=ACQUIRED
holder=ofd   prober=fcntl  contended=BLOCKED 11
holder=ofd   prober=ofd    contended=BLOCKED 11
```

Grant lifetime across a spawned child, Darwin:

```console
FD_CLOEXEC=clear | holder alive: BLOCKED 35 | holder SIGKILLed: BLOCKED 35
FD_CLOEXEC=set   | holder alive: BLOCKED 35 | holder SIGKILLed: ACQUIRED
```

`crash_harness.py` as shipped, Darwin:

```console
  files after install:     10
  cycles=300 grants=300 standing-claims=64 simulated-crashes=80
  files after 300 cycles:  10
  RESULT: file count CONSTANT (10 -> 10)
```

GHC 9.6.7 lock family, `Linux 6.8.0-100-generic aarch64`. `base` is `GHC.IO.Handle.Lock.hTryLock`;
`unix` is `System.Posix.IO.setLock`; `flockcli` is `flock(1)`:

```console
holder=base  prober=flockcli contended=ACQUIRED
holder=base  prober=unix     contended=BLOCKED
holder=unix  prober=base     contended=BLOCKED
holder=flockcli prober=unix  contended=ACQUIRED

hold + unrelated fd closed, unix prober: BLOCKED   <- OFD, not classic fcntl
```

Darwin process start-time resolution:

```console
ps -o lstart : Tue Aug 25 22:49:29 2026        (1 s)
proc_pidinfo : 1787712569.227899               (1 us)
```
