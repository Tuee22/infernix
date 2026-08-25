# Analysis: `documents/engineering/shared_host_resource_protocol.md`

**Subject**: `documents/engineering/shared_host_resource_protocol.md` — 361 lines, `Status: Draft`,
current at `54463ba`. This is the rewritten revision whose §1 records the falsification of the
earlier per-user-root / claim-ledger design.

**Question asked**: critical assessment of the document as it relates to this project.

**Method**: six independent dimension reviews (lock mechanism, domain algebra, memory-doctrine fit,
non-negotiable-rule collision, operations/security, documentation governance), each followed by an
adversarial refutation pass whose default posture was to knock the finding down. Every load-bearing
platform claim in §6 and §9 was **re-measured** rather than read — the full 3×3 family matrix and
both lifetime rows on `Linux 6.8.0-100-generic aarch64` (through the existing Colima daemon) and on
`Darwin 25.5.0 arm64`, the `F_OFD_*` constants against the installed macOS SDK header, and both
`struct flock` layouts field-for-field. §5's Python was executed. Repository citations below are
`file:line` and were read directly. Findings that did not survive refutation are recorded in §8
rather than deleted.

**Recommendation**: **adopt the analysis, not the protocol.** §6.2 is the best-measured content in
the governed suite and its central insight is correct and load-bearing for this repository. §§4, 5,
and 7 have two blocking gaps that are gaps in version 1 rather than features deferred to version 2,
and the file's placement in the governed suite is not defensible in its present state. The one
narrow gap adoption would genuinely close is real, is named in §7 below, and needs almost none of
the specified protocol to close it.

---

## 1. Verdict

In descending severity, against *this* repository:

1. **The reserve model cannot express a divisible resource**, and the two families the document
   reserves at version 1 — `host:memory` and `host:cpu` — are divisible ones. There is no domain
   name that is both correct and useful for infernix's standing cluster. §4.1.
2. **§4's grant/reserve dichotomy has no arm for a per-run resource that outlives its creating
   process**, which is exactly what `infernix cluster up` leaves behind. §4.2.
3. **Run against the three host-exhaustion incidents this repository has actually recorded, it
   prevents none of them** — and §10 concedes that the failure class it does address is one nobody
   has recorded. §5.1.
4. **Its refusals name nothing, and the mandated mechanism cannot name a holder**, which is a
   straight regression against a doctrine this repository already enforces in code. §5.2.
5. **It is an orphan carrying `MUST` language**: zero plan coverage, zero implementation, one link
   in 361 lines, a conformance script that does not exist, and a second authoritative home for a
   topic `managed_state_transitions.md` already owns. §6.

What it is *not* is wrong about the mechanism. The obvious first objection — that the OFD mandate
collides with this repository's ban on repo-owned FFI — does not survive checking, and is withdrawn
in §3.

---

## 2. What the document gets right

Stated first, because none of it is cheap and most of it was verified rather than accepted.

- **Every lock measurement in §6.2 reproduces exactly.** All nine Linux cells, all nine Darwin
  cells, and both lifetime rows were re-run independently on the same two kernel strings the
  document cites. Including the three cells the mandate rests on: holder=`flock`/prober=OFD →
  ACQUIRED, holder=`fcntl`/prober=OFD → BLOCKED, holder=OFD/prober=`fcntl` → BLOCKED. Darwin: all
  nine BLOCKED. Lifetime: second-descriptor-close and `fork`+parent-exit are LOST for classic
  `fcntl`, SURVIVED for `flock` and OFD, on both platforms.
- **The platform constants are right against the real headers, not against the document.**
  `F_OFD_SETLK 90` at `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/fcntl.h:309`
  (with 91/92/93 for `SETLKW`/`GETLK`/`SETLKWTIMEOUT`), Linux 37 confirmed in-container. Darwin's
  `struct flock` declares `off_t l_start; off_t l_len; pid_t l_pid; short l_type; short l_whence` —
  exactly the document's `struct.pack("qqihh", …)`, and the Linux `"hhqqi"` variant is equally
  correct. That level of platform precision is rare and it is checkable.
- **§5's algebra executes.** Every assertion passes, including the segment-boundary case
  `not conflicts("gpu:0", "gpu:01")` that a naive string-prefix implementation gets wrong.
- **The two-families-on-Linux / one-on-Darwin insight is the most valuable thing in the document**,
  and for this repository it is not hypothetical: `CLAUDE.md` makes Apple Silicon the development
  platform and the container lanes the deployment target, which is precisely the
  invisible-where-you-develop / broken-where-you-deploy shape §6.2 describes.
- **§8's boundary statement is the single most important sentence in the file for this codebase**:
  "A granted lock is **coordination, not evidence**. It is not typed evidence for any state
  transition, it applies no limit, and it fences no device. Existing enforcement is unaffected and
  is not replaced." It pre-empts the collision with `managed_state_transitions.md` rather than
  papering over it, and it is the correct call.
- **Two non-obvious correctness traps are correctly identified**: the no-rename rule (§7 — "a rename
  would repoint the name at a new inode and orphan the lock") and the `FD_CLOEXEC`-must-be-clear
  rule. Both are the kind of thing an implementation gets wrong once and never diagnoses.
- **§7's ordering discipline is right where it counts.** Taking the slot lock *before* publishing
  content, plus `if grant-lock on s is free: continue`, genuinely does make a crash mid-write
  invisible to other readers — a dead holder's slot is skipped rather than parsed.
- **§1's self-falsification table is technically correct on every row.** `$HOME` really is an
  environment variable; one machine really is several kernels (`Darwin 25.5.0` beside Colima's
  `Linux 6.8.0-100-generic` on this box, verified); `rename(2)` really does orphan a lock held on
  the old inode.
- **§§10 and 11 are more honest about limits than most of the suite.** Booking six Windows items as
  unknown rather than assumed is better discipline than the alternative, and
  `documentation_standards.md:110` explicitly classifies a target declaring what it does *not* cover
  as doctrine rather than status.

---

## 3. The obvious first objection, and why it is withdrawn

The immediate reading is that §6.1's OFD mandate is unreachable here: `CLAUDE.md` names
`filelock`, `process`, and `unix` as the permitted locking substrate and bans direct
`foreign import` throughout repository-owned Haskell, lint-enforced at
`src/Infernix/Lint/HaskellStyle.hs:640` ("forbidden direct foreign import; repository-owned direct
FFI is not permitted"). `managed_state_transitions.md:48` says the same. Measurement supports the
premise:

- **Haskell `filelock` is `flock(2)`.** `nm -u` on
  `~/.local/state/cabal/store/ghc-9.12.4-6f4d/fllck-0.1.1.9-7b4dd8cf/lib/libHSfllck-…​.a` prints
  object `Flock.o` with undefined symbol `_flock`; the module is `System.FileLock.Internal.Flock`.
- **Python `filelock` is also `flock(2)`** — `python/.venv/…/filelock/_unix.py` calls
  `fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)`. It is pinned `filelock==3.32.0` at
  `src/Infernix/Engines/Provisioning/Internal.hs:271`.
- **`unix` exposes no OFD API** — only classic `F_GETLK`/`F_SETLK`/`F_SETLKW`.
- **`lukko`, the one Haskell package with an OFD module, gates it behind `os(linux)`**, so it does
  not exist on the primary development platform.

The conclusion does not follow, for two reasons found by the refutation pass.

**3.1 — The four `System.FileLock` sites are not host-capacity arbitration.**
`src/Infernix/Cluster/LifecycleLock.hs`, `src/Infernix/Python/MutationLock/Internal.hs`,
`src/Infernix/Engines/MaterializationLock/Internal.hs`, and
`src/Infernix/ProcessIdentity/Internal.hs` all guard *repo-local artifacts*. The repository's one
genuinely host-scoped lock is `src/Infernix/Service.hs:240-270` — `engine.lock`, refusing "to start
a second engine on this host" — and it uses `System.Posix.IO` `getLock`/`setLock`, i.e. **classic
`fcntl` record locks, already inside `{fcntl, OFD}`**. That is verbatim the survey claim §6.2 makes:
"most of them already taking classic `fcntl` record locks at the call sites that arbitrate host
capacity — that is, already inside the `{fcntl, OFD}` family."

**3.2 — OFD is reachable from `base`, with no new dependency and no rule change.** The GHC 9.12.4
tree ships `GHC/Internal/IO/Handle/Lock/LinuxOFD.hi` alongside `Flock`, `NoOp`, and `Windows`;
`hTryLock` selects the OFD backend on Linux and `flock` on Darwin, where all three families
interoperate anyway. No FFI, no `lukko`, no amendment to `CLAUDE.md`.

So §6.2's "a change of one call" is **true for infernix at the one call site that matters**. The
mechanism half of the document is cheap and correct here. Withdraw the objection; the problems are
in §§4, 5, 7 and in the file's placement.

**3.3 — What does survive from this dimension.** §11's conformance snippet exercises only the
OFD/OFD diagonal, which a pure-`flock` participant passes on *both* platforms. The cells capable of
detecting the defect are holder=`flock`/prober=OFD and its transpose, and §6.2 tells the reader to
establish a library's family "by measurement" without naming them. As written, the document's single
verification instrument is a control test, not a conformance test.

---

## 4. Findings — the design

### 4.1 The reserve has no name that is both correct and useful for a divisible resource

§4 claims a reserve "works at version 1 because a reserve is a *domain*, not a quantity." Test that
against the document's own canonical example — a continuously-running cluster:

| Reserve written | Result under §5's prefix rule |
|---|---|
| `host:memory` | conflicts with `host:memory/*` for every participant, permanently. Nothing on the machine can ever take a host-memory grant |
| `host:memory/kind` | conflicts with nothing any other participant asks for. Inert |

There is no third name. Two participants that each take `host:memory/<project>` do not conflict, so
they do not coordinate — which is the exact failure the policy exists to prevent. The document is
aware of the boundary and states it in §5 ("a new *quantity* costs a revision"), but version 1
nonetheless reserves `host:memory` and `host:cpu` as families, and those are among the divisible
resources the algebra cannot express. `disk:<fs-id>` has the same shape.

**The indivisible half of the algebra is genuinely good.** `gpu:0` versus `gpu:0/part1`, `vm:<name>`,
a device and its partition — prefix conflict at a segment boundary is exactly right there, and the
extension asymmetry argument ("a new device family costs nothing") holds. The defect is that the
version-1 reserved-family list writes cheques the algebra cannot cash.

**In fairness**, a binary `host:memory` is coincidentally the right shape for the ledger's two
*alternative* occupants — `bounded_host_memory.md:234-236`: "the checked host partition and the
toolchain account draw on one pool, so an exclusive host claim admits one at a time" — and
`infernix test all` is sequential, so a coarse domain serializes rather than deadlocks. It is the
wrong shape for every *host-reserve claimant* the same ledger is built around, which are designed to
run concurrently within a checked budget.

### 4.2 §4 has no arm for a per-run resource that outlives its creating process

§4's dichotomy is total: a Grant's holder is "**The live process doing the work**"; a Reserve is a
domain "edited by the operator and by nobody else," held by nobody, permanently.

`infernix cluster up` returns. The Kind cluster keeps running. That standing claimant is neither —
it is per-run, it outlives its creator, and it is not permanent. §4's own decision rule ("If it
outlives the session and is expected to persist, it is a reserve; if it is per-run, it is a grant")
returns both answers for it.

This is the cleanest structural gap in the document, and it is the one that decides the adoption
case: the recorded incident is an uncapped build running *beside* a cluster that a previous command
left behind, and the standing half of that pair has no representation.

### 4.3 §9's crash table is falsified by §6.2's own measurement

§9 row 1: "`SIGKILL` of a grant holder | **No resource leaks.** The kernel releases the lock; domains
are free immediately."

§6.2 mandates that `FD_CLOEXEC` be **clear** on the grant descriptor, and measures the consequence
two paragraphs earlier: "`fork`, parent exits, child keeps the descriptor | SURVIVED." With the
descriptor inherited by a surviving `fork`+`exec` descendant, killing the holder does **not** free
the domain — and §4 has deliberately removed every reclaim path ("no reclaim rule, no time-to-live,
no boot identity and no operator escape hatch"). A leaked descriptor on `host:memory` wedges the
machine until that descendant dies.

For a project whose entire subprocess story is anchor → supervisor → target this is not a corner
case. Two mitigations the document does not mention: `lsof` on the slot file names the holding PID
directly, and the slot path `<root>/slots/<participant>/<n>` already names the owning project. So it
is diagnosable — the defect is the unqualified claim plus the missing guidance, not undiagnosability.

### 4.4 Nesting is unrepresentable

§7's `acquire` scans "each slot s in `<root>/slots/*/*`" — *including the caller's own participant
directory* — and returns `Conflicted` on any conflicting domain held by a live slot. There is no
self-exclusion and no ancestor exclusion. Combine that with §4's ban on inheriting a grant across
process creation and a participant that spawns another image of itself self-conflicts, with no way
to tell that it is its own blocker and no recovery path.

This repository already solved the same problem correctly and in the same shape:
`src/Infernix/HostClaimants.hs:400-406` excludes only rows outside the observer's own process tree
(`not (withinOwnProcessTree (processRowPid row))`), and `bounded_host_memory.md:80-82` states the
rule — "only a process that is neither ancestor nor descendant is foreign." §7 has not.

### 4.5 Non-transitive conflict makes admission order-dependent, with no fairness rule

`conflicts` is reflexive and symmetric but **not transitive**: `host:memory/a` and `host:memory/b`
do not conflict, yet both conflict with `host:memory`. The coarse claimant is therefore the one that
starves. A multi-minute Apple `cabal build` demanding `host:memory` can be blocked indefinitely by a
trickle of short-lived `host:memory/inference` and `host:memory/web` grants on a host that is never
actually full — textbook writer starvation, with no queue, no wait mode, no priority, no backoff
guidance, and no diagnostic to reveal it.

Relatedly, §7's rationale for the four refusal classes ("kept distinct because collapsing them
produces retry loops that never terminate") is sound as stated but violated internally: `Conflicted`
merges a *permanent* cause (a domain in `<root>/reserved`) with a *transient* one (a live grant),
giving one class two opposite retry semantics. That is the collapse the rationale forbids.

### 4.6 In-place writes with no truncation

§7 mandates writing content in place and explicitly reasons that "no checksum and no fixed-size
padding are needed." It never requires `ftruncate`. A slot reused for a shorter domain list leaves a
stale tail. The modal outcome is fail-closed (a malformed domain §5 requires rejecting) or
over-conservative (a phantom domain producing a spurious `Conflicted`), and the window is one
holding period rather than forever, since a free slot is skipped. Still a spec gap that undercuts
the paragraph justifying the absence of framing, and it is a one-word fix (`ftruncate` is safe on an
OFD lock, since §6.2 measured that an unrelated close does not drop it).

### 4.7 The freeness probe is unspecified

§7 says "if grant-lock on s is free" without naming the operation. The two candidates have opposite
permission requirements: `F_OFD_GETLK` works on a read-only descriptor, a trial `F_OFD_SETLK`
requires write access. That single unstated choice decides the mode every slot file must carry, and
the document specifies no mode, owner, or creator for `protocol-version`, `reserved`,
`admission.lock`, or `slots/`.

### 4.8 `admission.lock` has no hung-holder story

§9 covers `SIGKILL` of the `admission.lock` holder ("No wedge. Kernel-released"). It does not cover
a holder that is alive but hung or stopped. The exclusive-only mandate forces every participant to
write-open the file, and §7 makes acquisition non-blocking with no timeout, so one stopped process
converts every participant on the machine into a permanent `Busy` with no diagnostic and — per §4 —
no operator escape hatch.

### 4.9 No rule for malformed content read from another participant's slot

§5 mandates rejecting a malformed domain rather than parsing it loosely, but that rule is written
for a participant validating *its own* demand. §7's scan has no validation branch, no size bound,
and the four-class taxonomy has no outcome for "another participant's slot is unreadable." Both
directions are bad — fail-open makes that participant invisible and admits a second conflicting
claimant; fail-closed lets one bad byte refuse every acquire on the box — and the document picks
neither.

---

## 5. Findings — fit with this repository

### 5.1 Against the recorded incidents, it prevents none of them

| Recorded incident | Would hostgrant have prevented it? |
|---|---|
| Uncapped host `cabal build` reaching **109.46 GiB resident** on a **124.94 GiB** host, kernel destroying 111 pod processes | **No.** §8 applies no limit and sets no victim rank. A grant admits the build; it does not bound it |
| Three interactive compiler images holding **44.1 / 29.9 / 27.4 GiB** exhausting a 64 GiB host | **No.** §10: "Non-participants are unconstrained." They were not participants. The census at `src/Infernix/HostClaimants.hs` already *names* such images and refuses |
| A build started beside a running cluster | **No** — and for a reason worth stating precisely: the cluster outlives `infernix cluster up`, so under §4 it is neither a grant nor a reserve (§4.2) |

§10 then concedes: progressive consumption "is the only shared-host failure two of these projects
have actually recorded." So the adoption case rests entirely on a hazard nobody has recorded, while
the hazard everyone *has* recorded is explicitly out of scope. That is the crux of the cost/benefit
argument and the document does not engage with it.

### 5.2 The refusals are a diagnostic regression against a doctrine this repository enforces

§7's four classes carry no holder identity: `Conflicted` names no domain, no holder, and does not
distinguish a `reserved` line from a live grant. Worse, the *mandated mechanism cannot* name a
holder — `F_OFD_GETLK` returns `l_pid = -1` for an OFD holder by design, and §6.2's slot format
(byte 0 reserved, domain list from offset 1) has no PID field, which forecloses the workaround this
repository already ships.

Compare what exists today:

- `src/Infernix/Service.hs:255` — `"engine.lock held by PID " <> show holderPid`.
- `src/Infernix/HostClaimants.hs:470-482`, `renderForeignToolchainClaimants`, whose doc comment is
  "Render a census refusal so it names every claimant it found," producing
  ``pid N `image` (M MiB resident, attributed not measured)``.
- `bounded_host_memory.md:82-83` — "Either observation failing is a refusal naming what it found."

An operator whose hour-scale `infernix test all` refuses in its first second would learn only
`Conflicted`. There is also no "who holds what" surface specified at all.

### 5.3 `host:memory` as a prefix mutex versus the claimant arithmetic

`CLAUDE.md` and `bounded_host_memory.md:23-26` mandate an account of the form
`jobs × compilerHeap + (jobs + 1) × controlHeap`, admitted against *observed* availability. A
boolean domain cannot express it, and the obvious encoding is actively wrong:
`host:memory/8192` and `host:memory/4096` do not conflict, so a quantity smuggled into a segment
silently coordinates nothing. §5 forbids quantities at version 1, so this is a warning to an
implementer rather than a contradiction inside the document — but it means the protocol cannot carry
this repository's ledger, only gate it.

### 5.4 Vocabulary collision: `Reserve`

§4 defines "**Reserve** — standing capacity, declared once by the operator, held by nobody,"
expressed as a domain in `<root>/reserved`. `bounded_host_memory.md` already owns *host reserve* as
the share of host memory not charged to the toolchain account — `:45`, `:135`, `:138`, `:204`,
`:249-250`, `:273-277`, `:296` — and `CLAUDE.md`'s non-negotiable list says "host-reserve claimants"
four times. Same word, both about standing host capacity, incompatible meanings, no cross-reference
in either direction. Since §4's reserve is the mechanism for expressing "a continuously-running
cluster, a VM's memory pledge" — precisely the quantities `bounded_host_memory.md` accounts for — a
future implementer reading both cannot tell whether `<root>/reserved` is the file form of the host
reserve. It is not.

### 5.5 Container participation and the Apple lane

On native Linux this works: Kind nodes share the host kernel and `renderKindConfig` already renders
`extraMounts` hostPath/containerPath pairs (`src/Infernix/Cluster.hs:6572-6580`).

On Apple it does not work as specified. §3 correctly places the launcher container in the Colima
VM's scope, so the rendezvous must also be established *inside the VM* — a second privileged step
reached over `colima ssh`, on a VM the repository is otherwise careful not to provision or reshape.
And Docker auto-creates a missing bind-mount source, so an uninitialized `/var/lib/hostgrant`
appears inside the container as an ordinary empty directory that arbitrates with nobody. §6.1 has no
rule separating "root absent" (→ `Unsupported`, per §3) from "root present but uninitialized." An
implementer who picks `Unsupported` runs ungoverned — the silent-success outcome §3 exists to
forbid.

### 5.6 The install step is not idempotent in the way that matters

`sudo mkdir -p -m 1777 /var/lib/hostgrant` applies `-m` only to the final component **and does
nothing at all if the directory already exists**. A root created `0755` by an earlier or
differently-configured project stays `0755`, every later participant silently fails to register, and
a restartable prerequisite reconciler — which is what `CLAUDE.md` requires `bootstrap/*.sh` to be —
cannot reconcile it. The document states a `MUST` that the root be on a local filesystem and that a
participant "MUST prove its root is shared," and specifies no mechanism for either. (Both are
dischargeable on Linux via `/proc/self/mountinfo`; the document does not say so.)

---

## 6. Findings — governance and placement

This is the section that decides whether the file stays where it is.

### 6.1 It is the only `Draft` in the suite

Across `documents/`: 54 `Authoritative source`, 2 `Supporting reference`, 1 `Draft` — this file.
`Draft` is a legal status, but here it is being read as "not adopted yet," which is a schedule
statement, and there is no plan row to say what would move it off `Draft`.

### 6.2 Zero plan coverage, zero implementation, missing receipts

- `grep -rc shared_host_resource_protocol DEVELOPMENT_PLAN/` returns 0 across all 16 plan files.
  Governed peers run 14–38.
- `hostgrant`, `admission.lock`, and `F_OFD` appear nowhere in `src/`, `python/`, or `bootstrap/`.
- `hostgrant_probe.py`, named in §11's conformance procedure, does not exist in this repository.
- `/var/lib/hostgrant` does not exist on this host.

`documentation_standards.md` permits an undelivered target — but because the plan carries the gap
and a gate carries the red. Here there is neither, and the file is full of `MUST` / `MUST NOT`.

### 6.3 One link in 361 lines, and a second authoritative home

`grep -n '](' ` on the file returns exactly one hit: line 4's metadata `Referenced by`. The body
carries **zero** cross-references. Meanwhile it mandates OFD for lifecycle-shaped locking, while
`managed_state_transitions.md:48` — the canonical home for that topic — mandates "only public
`filelock`, `process`, and `unix` APIs." The two documents disagree about the mechanism and neither
names the other. `documentation_standards.md:182` is "keep one canonical home per topic."

Its only inbound repository references are `documents/README.md:99` and
`src/Infernix/Lint/Docs.hs:92`. It appears in no Update Rule trigger list, so no doc-maintenance
rule will ever fire when the surrounding doctrine moves.

### 6.4 Governed for metadata, ungoverned for shape

It is in `governedDocuments` (`src/Infernix/Lint/Docs.hs:92`) but in **no** `DocumentStructureRule`.
Every structured engineering peer — `build_artifacts`, `docker_policy`, `edge_routing`,
`implementation_boundaries`, `storage_and_state`, `portability`, `testing` — requires both
`RequireOneOfSections ["## TL;DR", "## Executive Summary"]` and `RequireSection "## Validation"`.
This file has neither, which is why an 11-section protocol specification whose §11 *is* a conformance
procedure ships with no validation section. The fix is a two-line addition to
`documentStructureRules`, which would then also mechanically force the plan linkage §6.2 is about.

### 6.5 Unnamed peers

"each project," "both projects," "two of these projects," "a survey of the programs sharing a
development host" — never named. A reader of this repository alone cannot verify conformance (there
is no counterpart to contend against), cannot audit the survey the adoption-cost argument rests on,
and is told in §10 that a failure class this repository has recorded and built a doctrine around has
never been recorded.

The repository already knows how to carry a cross-project contract correctly:
`documents/architecture/pulsar_ml_workflow.md` names the peer, gives its file path, and is protected
by an anti-fork Update Rule. This file ignores that precedent.

### 6.6 Voice

- **First person singular**: "two of my own corrections" (§1) is the only authorial first person in
  the governed suite. It is unattributable in a repository declaration — the next editor can neither
  honestly keep it nor change it.
- **§1 is a migration diary**, the form `documentation_standards.md:181` forbids outright ("write
  target-state declarative guidance, not migration diaries and not status reports"). It also
  preserves and re-teaches rejected designs (`%ProgramData%`, the `$HOME` root, atomic rename)
  inside the document that is supposed to declare the accepted one — and that record is already in
  git history, four times over (`da97d83`/`35a5c50`, `b729b02`/`9f670b2`, `be875f2`/`53ad994`,
  `a9136b2`/`54463ba`).
- **The purpose line is subjunctive** — "the host resource coordination policy Infernix **would**
  implement" — against `documentation_standards.md:106` ("present-tense declarative voice, whether
  or not the implementation has landed"), and it disagrees with `documents/README.md:99`, which
  introduces the same file in the indicative. Two-word fix.
- Numbered `## N.` headings are unique in the suite, but the document self-cites as "§6.2" and "§11"
  four times and stable numbers are what make those work. A specification is a legitimate exception.

---

## 7. What adoption would actually buy Infernix

### 7.1 The gap is real, and it is not the one the document emphasizes

Two exclusion mechanisms in this repository are narrower than the host, and both are documented as
such:

- **The toolchain single-flight is process-local.** `bounded_host_memory.md:14-19` asserts "an
  exclusive host claim admits one of them at a time," but the exclusion is
  `ToolchainSingleFlight (MVar ())` at `src/Infernix/BuildMemory.hs:1042` — one process image. What
  crosses process boundaries is the census, and a census is a point-in-time observation with a
  TOCTOU window between observing and starting.
- **The engine lock is repo-local.** `src/Infernix/Service.hs:225` is
  `runtimeRoot paths </> "engine.lock"`, and `daemon_topology.md:230-233` says plainly: "It is
  repo-local, not machine-global, so it does not exclude two checkouts on one host."

`bounded_host_memory.md:286-288` concedes the residue: processes this repository did not start are
invisible unless they are a *recognized toolchain image*, and a foreign claimant is "attributed, not
measured."

A machine-global held claim closes exactly those two holes: it replaces a point-in-time census with
a claim held for the duration, and it makes two checkouts on one host mutually visible. That is a
genuine improvement and the document deserves credit for diagnosing it.

### 7.2 The cheap increment

Closing that gap needs **none** of §5's algebra, §7's slot pool, `<root>/reserved`, the
`protocol-version` flag day, or a world-writable machine-global root:

- one grant taken at the existing spawn-authority boundary, using `hTryLock` from `base` (§3.2), so
  the lock lands in the mandated family on both lanes with no rule change;
- a rendezvous whose owner and mode are verified the way this repository already verifies lock paths
  (`src/Infernix/ProcessIdentity/Internal.hs:737-740`);
- a refusal that names the holder, which requires a PID in the slot content and therefore *not* the
  document's byte-0/offset-1 format (§5.2).

That is on the order of thirty lines and it is the whole of the demonstrated benefit.

### 7.3 What it does not buy

Everything §10 lists, and it should be read as the load-bearing part of the document rather than a
disclaimer: no limit is applied, no device is fenced, non-participants are unconstrained, a
declaration is not behaviour, and progressive consumption — the only recorded failure — is
invisible. After §§10 and 11, the residual is per-resource mutual exclusion between cooperating
programs. That is worth something. It is not worth a machine-global 1777 trust boundary, a flag-day
version gate, an unnamed-peer dependency, and a reserve model that cannot name this repository's own
standing cluster.

---

## 8. Claims examined and withdrawn

Recorded so they are not re-argued. Each was raised during review and did not survive checking.

- **"The OFD mandate is unreachable under `CLAUDE.md`'s FFI ban."** Withdrawn — `base` ships a
  `LinuxOFD` backend and `hTryLock` selects it; `unix`'s classic `setLock` is in the mandated family
  on both platforms. See §3.
- **"§6.2's adoption-cost argument is inverted for this repository."** Withdrawn — infernix's one
  host-capacity call site (`Service.hs`) is already classic `fcntl`, so the survey claim is
  literally true here. The `System.FileLock` sites it appeared to contradict guard repo-local
  artifacts, not host capacity.
- **"`Grant` collides with the repository's `MemoryGrant` vocabulary."** Withdrawn — §2 scopes its
  own definition and no reader of the document is misled. The collision that *does* bite is
  `Reserve` (§5.4).
- **"The fixed slot count is unanswerable for this project."** Withdrawn — §2 defines a participant
  as a program implementing the policy, §10 concedes non-participants are unconstrained, so `ghc`,
  `docker`, and `kind` never needed slots. A participant's slot count is its own concurrent-grant
  capacity, which for infernix is about one.
- **"Any local user can append to `<root>/reserved` and wedge the machine."** Withdrawn — the file
  is operator-created in a sticky root; neither the write nor the unlink is available to another
  uid. The surviving security finding is `admission.lock` (§4.8) and the unspecified permission
  model (§4.7).
- **"`<root>/reserved` and `<root>/protocol-version` violate the typed-`.dhall` configuration
  doctrine."** Withdrawn as a doctrine collision — `configuration_doctrine.md` scopes itself to
  infernix's own code, and `bounded_host_memory.md:305-308` shows admission already gating on
  hand-set external state (the Colima pledge) with the same fail-closed shape. The surviving defect
  is narrower: `reserved` is a hand-typed, byte-exact file with no generator, no validator, and no
  programmatic reclaim (§4.1, §5.4).
- **"The measurement receipts are unreproducible."** Reduced — §6.2 ships a complete, self-contained
  OFD taker whose constants verify against the real headers, and §5's algebra runs verbatim. What is
  missing is a committed fixture and the cross-family cells (§3.3), not the method.
- **"Windows content is dead weight."** Reduced to a nit — the document is explicitly a
  multi-project policy, §11 books every Windows item as unverified in advance, and the byte-0
  reservation costs one byte of a permanent fixture. It is inert *for this repository*, which is not
  the same as inert.

---

## 9. Recommendation

**Adopt the analysis, not the protocol.** In priority order:

1. **Fix §11 before anything else.** Name the off-diagonal cells (holder=`flock`/prober=OFD and its
   transpose) as the conformance cells, and commit `hostgrant_probe.py` as a fixture. As written the
   only verification instrument in the document cannot detect the defect it was written for.
2. **Answer the two version-1 questions**: what a reserve means for a divisible resource (§4.1), and
   what represents a per-run resource that outlives its creating process (§4.2). Both are gaps in
   version 1, not features deferred to version 2, and the second is what decides the adoption case.
3. **Make refusals name what they found** (§5.2) — a domain, a source, and a holder. This repository
   already treats that as doctrine and implements it twice. It requires abandoning the byte-0 slot
   format, so it is a design change, not an editorial one.
4. **Correct §9 row 1** to qualify "no resource leaks" with the inherited-descriptor case §6.2
   measures, and either give §4 a reclaim path or state that `lsof` plus the slot path is the
   supported diagnosis (§4.3).
5. **Add a self-or-ancestor exemption to §7's scan** (§4.4), require `ftruncate` (§4.6), name the
   freeness probe and the permission model (§4.7), give `admission.lock` a hung-holder story (§4.8),
   and state the rule for unreadable foreign slot content (§4.9).
6. **Fix the governance**, or move the file out of the governed suite. To keep it: a
   `DEVELOPMENT_PLAN/` row, a `DocumentStructureRule` requiring `## TL;DR` and `## Validation`, body
   cross-references (at minimum to `managed_state_transitions.md`, `bounded_host_memory.md`, and
   `docker_policy.md`), named peers on the `pulsar_ml_workflow.md` precedent, §1 dropped to git
   history, `Reserve` renamed away from the `bounded_host_memory.md` term, the purpose line put in
   the indicative, and promotion off `Draft`. Until then it is an orphan carrying `MUST` language.
7. **Independently of the document's fate**, the gap it diagnoses is real and worth closing on its
   own terms: the toolchain single-flight is a process-local `MVar` (`BuildMemory.hs:1042`) behind a
   doctrine sentence that promises an exclusive *host* claim, and the engine lock is repo-local by
   its own admission (`daemon_topology.md:230-233`). A machine-global held claim at the spawn
   authority boundary, taken through `hTryLock`, with a holder-naming refusal, closes both. See §7.2.
