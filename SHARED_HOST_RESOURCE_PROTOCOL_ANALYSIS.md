# Analysis: `documents/engineering/shared_host_resource_protocol.md`

**Subject**: `documents/engineering/shared_host_resource_protocol.md` (111 lines, `Status: Draft`,
added `081ee88` 2026-08-24, revised `35a5c50`, `9f670b2`, `53ad994`)

**Question asked**: critical assessment of the document as it relates to this project.

**Method**: every load-bearing claim in the document was checked against this repository's code and
governed doctrine. Citations below are `file:line` and were read directly, not inferred.

**Recommendation**: **do not adopt.** Keep the thinking, correct four errors, and move the file out
of the governed `documents/` suite. One narrow gap the document could close is real and is named in
§6 below.

---

## 1. Summary of the verdict

The prose is disciplined and the honesty about limits is well above average for this genre. Against
*this* repository it has four problems, in descending severity:

1. **Two load-bearing claims are falsified by code already in `src/`** — §3.1 and §3.2.
2. **The fixed-path rule silently does not coordinate on two of three supported runtime modes**,
   producing exactly the failure §1 of the document says the ledger exists to prevent — §3.3.
3. **Terminology collides head-on** with `bounded_host_memory.md`, where `claim`, `ledger`,
   `budget`, `reserve`, and `pool` already denote *enforced*, *intra-repository*, *non-crash-surviving*
   things — §3.4.
4. **It is a rationale document filed as governed engineering doctrine, and it specifies nothing an
   implementer could build** — §3.5 and §4.

Marginal value on Infernix's supported hosts is small, because the repository already implements the
stronger half of the mechanism the document describes as complementary. The one genuine gap is
concurrent `infernix` CLI images on a single host, and that gap is already named as unsupported in
code — §6.

---

## 2. What the document gets right

Worth stating first, because these are not cheap.

- **§3 is the strongest section.** "That is a statement about **declarations**, not about
  behaviour… A participant that declares four gibibytes and then allocates twelve is not detected."
  Most coordination specs bury this. Framing it as the design rather than an apology is correct.
- **§4 (release-directed work is always admissible)** is a real invariant with a real deadlock
  behind it, and this repository arrived at the same rule independently — teardown takes the same
  lifecycle lock as bring-up and never consults a budget (`src/Infernix/Cluster.hs:3278`,
  `src/Infernix/Cluster.hs:8287`), and a failed `kind delete` is classified `IdempotentAbsence`
  rather than refused.
- **§5's concession** — one-shot admission cannot see progressive consumption — is honest, and "a
  real limit, not a gap awaiting a patch" is the right posture.
- **Fail-to-occupied** (§2, property 2) is the correct polarity, and it matches this repository's
  own fail-closed conventions: `ClusterSlotUnidentified` (`src/Infernix/Cluster.hs:1855-1860`), the
  versioned cluster-state codec, and the Colima probe that returns `Left` rather than zero
  (`src/Infernix/DemoConfig/Colima.hs:27-29`).
- **§1's non-configurable-path argument is the same argument** `documents/engineering/host_tools_manifest.md:308-312`
  makes about enforcement executables ("a manifest field is operator-editable by design, and an
  enforcement path an operator can repoint is not an enforcement path"). Two independent derivations
  of one principle is a good sign for the principle.
- **§7's second obligation** — "derive the charge once… two independently authored figures drift,
  and the drift is silent" — is correct, and this repository contains a live instance of exactly
  that failure right now. See §7.1.

---

## 3. Findings

### 3.1 Observation *can* see a stopped virtual machine — this repository does it today

§6 reserves for the ledger:

> What it cannot see is capacity with no process to observe: an idle cluster, a **stopped virtual
> machine**, a registered guest, or retained bytes on disk.

`src/Infernix/HostMemory.hs:18-21` says the opposite and ships:

> "On Darwin, the supported container lanes consume a co-resident Colima VM pledge from the same
> physical RAM, so the host-native toolchain's effective figure subtracts the conservatively observed
> aggregate active pledge. An unavailable or malformed Colima observation fails closed."

`src/Infernix/HostTools.hs:254` records the mechanism: `colima list --json` "reads **on-disk profile
state**" — not a process table. `src/Infernix/DemoConfig/Colima.hs:60-86` charges every profile whose
status is not exactly `"Stopped"` and rounds the aggregate up.

This is not a corner case. It is the single largest capacity item on the supported Apple host:
`documents/operations/apple_silicon_runbook.md:365-379` — a 64 GiB host with a 48 GiB Colima pledge
leaves a claimable pool of 16384 MiB. The repository already observes and hard-subtracts 75% of the
machine, unilaterally, with no installed root and no agreement from anyone.

**The taxonomy in §6 is missing a category.** There are three mechanisms, not two:

| Mechanism | Reach | In this repo |
|---|---|---|
| Process observation | Bound to knowing a peer's process names; does not cross language ecosystems | `src/Infernix/HostClaimants.hs:447-467` (`isToolchainImageName`) |
| **Artifact observation** | Reads a peer's on-disk state; crosses ecosystems; sees stopped VMs and retained bytes | `src/Infernix/DemoConfig/Colima.hs:30-42` |
| Declared ledger | Anything a participant will declare | not adopted |

§6 collapses the first two, then credits the ledger with the second one's reach.

**Fix**: split §6 into process observation and artifact observation; withdraw the "stopped virtual
machine" example; state the ledger's residue as *capacity whose owning artifact you do not know how
to find* — a much smaller and much more defensible claim.

### 3.2 "Writing it creates no dependency" is false as filed

§1: "No code in this repository reads or writes the ledger, and no command depends on it… Writing it
creates no dependency on another project."

True of the other project. False of this one, and not by accident:

- `src/Infernix/Lint/Docs.hs:459-467` is a **coverage drift guard**: every markdown file present
  under `documents/` *must* be registered in `requiredDocs`, or `infernix lint docs` fails with
  "governed document not registered in requiredDocs (add it there)".
- `src/Infernix/Lint/Docs.hs:92` therefore registers it, which means `src/Infernix/Lint/Docs.hs:454-458`
  now **fails if the file is deleted**.
- `documents/README.md:99-105` gives it a seven-line index entry — the longest in that
  neighbourhood — for a mechanism with zero implementation.

Filing a document under `documents/` at all creates a lint-enforced dependency. The sentence should
either be amended or the file should move (see §5).

### 3.3 The fixed-path rule breaks on two of three supported runtime modes

This is the most serious technical finding.

§1 is emphatic:

> Every participant resolves one fixed path and no other: `$HOME/.hostclaim`… The path is never
> repository-relative, never version-suffixed, and never selected by an environment variable. Two
> participants that resolve different paths silently fail to coordinate, which is the one failure
> the ledger exists to prevent.

On `linux-cpu` and `linux-gpu`, infernix runs **inside the launcher container**
(`documents/engineering/portability.md:69`). `compose.yaml` mounts exactly two things:

```yaml
    volumes:
      - ./.data:/workspace/.data
      - /var/run/docker.sock:/var/run/docker.sock
```

No home mount. A containerized participant resolving `$HOME/.hostclaim` gets a path inside the
container's ephemeral filesystem. In order of badness:

1. It coordinates with nobody. Host-side participants have a different root.
2. It believes it *is* coordinating. Admission succeeds against an empty ledger, every time.
3. Its `Persistent` claims **evaporate on container exit while the resources they describe do not**.
   The container creates the Kind cluster on the *host's* Docker daemon through the forwarded socket
   (`compose.yaml`, `src/Infernix/Cluster/Command.hs:1547-1561`); the cluster outlives the container
   that claimed it. `Persistent` exists precisely because "the holder's death proves nothing," and
   here the record dies while the effect survives. That is the inversion the kind was introduced to
   prevent.

The Apple lane has the same boundary one level out: the Colima VM is a second filesystem.

**The spec has no container story**, and containerization is how this project ships two of its three
lanes.

**Fix**: state that the root is a property of the *kernel-visible host*; give a required mount
contract for containerized participants; and add the rule that a participant which cannot prove it
resolved the host root must **decline to participate** rather than write into a private one. Absent
that, §1's own stated failure mode is the default outcome for containerized adopters.

#### 3.3a A narrower, related risk: `$HOME` versus the passwd database

This one needs stating precisely, because the obvious version of it is wrong.

This repository does **not** ban knowing the home directory. It bans reading the environment:

- `documents/architecture/configuration_doctrine.md:64-65` — "No Haskell module calls `lookupEnv` /
  `getEnv` / `getEnvironment` / `setEnv` / `unsetEnv`", enforced by
  `src/Infernix/Lint/HaskellStyle.hs:1644-1651` with the only exemption being the lint module itself.
- The sanctioned resolver is the libc user database:
  `src/Infernix/DemoConfig/Internal.hs:844-848` — `getEffectiveUserID` + `getUserEntryForID` — whose
  own comment at `:837-843` states the rule: "operator home discovery comes from the system user
  database, not the `$HOME` env var."
- The resolved value is then a typed manifest field, `hostHomeDirectory`
  (`src/Infernix/HostConfig.hs:242`), and `SubprocessEnv` **emits** an absolute `HOME` to children
  from it (`documents/engineering/host_tools_manifest.md:416-422`).
- Shell entrypoints do the same: `documents/architecture/configuration_doctrine.md:387` — "operator
  home from `/etc/passwd` via `getent` (not `$HOME`)".

So the document's *intent* ("not configurable") is compatible with this repository. Its *literal
wording* is not, and the gap is where the risk lives: infernix would resolve via passwd, a peer would
resolve via `$HOME`, and those diverge under `sudo`, `sudo -E`, CI runners, launchers, systemd units,
and containers. Because infernix emits its own `HOME` to children, an infernix-launched participant
and a shell-launched sibling could split the ledger between them.

Note also that "never selected by an environment variable" and "`$HOME`" are contradictory on their
face. The rule the spec wants is *derived from the operating system's authoritative record of the
user's home directory* — `getent passwd` on POSIX, `SHGetKnownFolderPath` on Windows.

#### 3.3b Windows is out of scope for this repository

§1 specifies `%UserProfile%\.hostclaim`. A full-corpus grep for "windows" across `documents/`,
`README.md`, `AGENTS.md`, and `CLAUDE.md` returns **exactly one hit: line 17 of this document**.
`documents/engineering/portability.md:10-11,49` fixes the supported runtime modes at
`apple-silicon`, `linux-cpu`, `linux-gpu`. The codebase is POSIX to the bone (`System.Posix.User`,
`/proc` reads, POSIX process groups, `filelock`/`process`/`unix` only).

Recording a foreign spec's tri-platform path faithfully is defensible; an implementation branch for
it would be dead code on every supported lane. If the file stays, it should say so.

### 3.4 Terminology collision inside this documentation set

"Host claim" and "ledger" are both already taken, with precise and **opposite** properties.

`documents/architecture/bounded_host_memory.md` calls itself, in its own Purpose block, "the
host-memory capacity ledger," and its TL;DR defines:

> The capacity ledger has one claimable pool and two alternative occupants… an **exclusive host
> claim** admits one of them at a time.

That claim is:

- intra-repository, between two *infernix* occupants (the toolchain account and the inference
  partition), not between programs;
- backed by `HostClaimablePool` with a hidden constructor and a single mint
  (`src/Infernix/Types.hs:815-870`);
- and explicitly **not crash-surviving** — `bounded_host_memory.md:241`: "A host claim is released by
  process death and is not a crash-surviving lease."

The document's "host claim" is cross-program, advisory, and its `Persistent` kind is *defined by*
surviving holder death. Same two nouns, opposite properties, adjacent entries in
`documents/README.md`.

**Fix**: rename throughout — "shared host *reservation* record", "participant reservation",
"per-user reservation root". Avoid `claim`, `ledger`, `budget`, `reserve`, `admission`, and `pool`,
every one of which currently denotes something enforced in `bounded_host_memory.md`. Cheap now,
expensive later.

### 3.5 Governance: wrong status, wrong folder, wrong voice

`documents/documentation_standards.md:104-121` (Prescriptive Voice) gives the test:

> **Is this true of the target, or true only of today?**

§1's core sentence — "No code in this repository reads or writes the ledger, and no command depends
on it" — is true only of today. By the standard's own table it "belongs in the plan."
`documents/README.md:100` compounds it: "the **not-adopted** record."

Supporting observations:

- It is the **only** `Status: Draft` document in the entire governed corpus (all others are
  `Authoritative source` or `Supporting reference`). `Draft` is legal per
  `documents/documentation_standards.md:26`, but it is unique here.
- It has no `## Validation` section, which `documents/documentation_standards.md:51-52` asks of
  doctrine docs.
- No `DEVELOPMENT_PLAN/` sprint owns it, which sits badly with the CLAUDE.md rule "keep
  implementation status and validation receipts aligned in `DEVELOPMENT_PLAN/`".
- `documents/research/README.md` exists and describes exactly this file: "`research/` is for
  exploratory notes that do not define the supported platform contract… promote stabilized guidance
  out of `research/` and into its canonical governed document before treating it as source of truth."

---

## 4. Internal inconsistencies in the design as described

### 4.1 Properties 1 and 2 of §2 contradict each other

> **A participant writes only beneath its own directory.** Every record has exactly one writer, so a
> torn write is the only reachable corruption and **its cost falls on its own author**.

> **Free is a positive value a writer must deliberately produce.** A truncated file… decode[s] as
> occupied.

If a torn write decodes as occupied, it consumes **shared** budget. The cost falls on every *other*
participant seeking admission; the author is the least harmed, since its own claim reads as held.
Property 2 does not merely fail to prevent the externality — it guarantees it. The two bullets cannot
both stand as written.

### 4.2 Fail-to-occupied has no reclaim path, so the ledger leaks monotonically

"No failure of the encoding can release capacity" is the safe direction. Its converse is that
capacity is retained *indefinitely*. Combine that with `Persistent` claims surviving holder death by
design, and there is no TTL, no reaper, no liveness probe, no reconcile, and no stated operator
procedure. §4 does not help: a dead holder issues no release. Across a development machine's
lifetime of crashes and `kill -9`s, the effective budget drifts toward zero.

This is not covered by §5's disclaimer — a leaked claim is not progressive consumption.

The contrast with this repository is instructive. `ClusterMutating` exists in the `ClusterLifecycle`
machine specifically so a killed `infernix test all` leaves a **detectable, reconcilable** dirty state
rather than a false `steady-state`, and the next `cluster up` reconciles it. The harness reservation
goes further: `reclaimHarnessClusterSlot` (`src/Infernix/Cluster.hs:3126-3186`) classifies a prior
owner as `VerifiedAlive` / `DefinitelyDead` / `Unverifiable` and **refuses** the unverifiable case
without an operator-asserted override. The ledger as described has the dirty state and none of the
reconcile.

### 4.3 The identity model is weaker than the one this project already had to build

"Enrolling a participant is creating one directory named after it." Participant identity is a name
under a per-user root, so two checkouts of infernix are one participant.

This repository already paid for that lesson. Per CLAUDE.md and
`documents/architecture/managed_state_transitions.md`, the Kind cluster name is machine-global while
the lock, reservation, and persisted state are repo-local, so the lifecycle stamps the creating
checkout's repo root **inside the control-plane node** at `/etc/infernix/cluster-checkout-identity`
(`src/Infernix/Cluster.hs:1791-1913`). Relocating the lock and renaming the cluster were both
considered and rejected: neither works inside a launcher container, "where every checkout is baked
with the same in-container repo root, so a path-derived identity collides instead of discriminating."
`localClusterCheckoutIdentity` (`src/Infernix/Cluster.hs:1804-1832`) fails closed rather than reusing
the `/workspace` fallback for exactly that reason.

The ledger's name-under-a-root identity is the rejected shape, and it fails hardest in the
containerized lane — two of three supported modes.

### 4.4 Per-user root, machine-wide resource

Physical RAM is shared across users; the ledger is per-user. Two users on one host each admit against
the full budget. `bounded_host_memory.md:243-245` already flags cross-user as a known blind spot
("Cross-user physical-footprint observation is unavailable to an unprivileged process"). The per-user
root reintroduces the same blind spot one layer up — at the budget rather than at the measurement.
Unaddressed.

### 4.5 The single admission lock has no holder-death story

"Every claim is created inside one short critical section" asserts shortness rather than bounding it,
and says nothing about a holder that dies inside the section. Advisory `flock` releases on death; a
pid-file lock does not. For a machine-global serialization point this is the difference between a
hiccup and a wedged development host.

This repository's answer is `withKernelFileLock`
(`src/Infernix/Cluster/LifecycleLock.hs:32-47`): non-blocking exclusive `filelock`, contention is an
`ioError` naming the path, and the kernel drops it on process death. Note also the TOCTOU caveat
baked into `kernelFileLockIsHeld` (`:16-21`), which acquires and immediately releases — the same
hazard would apply to a ledger lock probed the same way.

### 4.6 A naive claim-on-acquire / release-on-release mapping double-releases

`clusterUpWithPulsarBootstrapRepair` (`src/Infernix/Cluster.hs:807-880`) calls `clusterDownResolved`
**from inside a bring-up**, up to three times. Any participant mapping §7's "name the seams"
mechanically onto `cluster up` / `cluster down` would emit releases for a claim it still holds.
Seam-naming is not as mechanical as §7 implies.

---

## 5. It is not a protocol

The title says Protocol. §1 says the authority is the installed root and its `spec-version`, "never a
copy of a document in any repository, including this one." Those are consistent only if this document
is deliberately *not* the spec — which is a legitimate choice, but it means the following are all
unknowable from here:

- **the "frozen set of dimensions" — not one dimension is named**, though §2 rests the entire
  cross-participant argument on them ("two participants that have never heard of each other still add
  their consumption the same way");
- the record encoding, its fixed size, and its revision field;
- the budget file's format (see below);
- the lock's mechanism and its holder-death semantics;
- the domain identifier grammar — §2 says conflicts are "a prefix test over opaque identifiers", but
  with no separator rule `gpu:0` prefix-matches `gpu:01`;
- the current `spec-version` value;
- the units charges are expressed in.

§7 asks a participant to "name the seams," "derive the charge once," and "establish release
evidence." None of the three can be **costed** without the above, so §7 reads as an obligation and
functions as a placeholder.

### 5.1 The budget file is the one element with no home in this repository's config substrate

`documents/architecture/configuration_doctrine.md:12-19` — "**Zero version-controlled `.dhall`**…
**The `infernix` binary is the sole generator of every `.dhall`**… Schemas are **reflected from the
Haskell decoder types**." `:70-72` — "one substrate (typed Dhall)". The one sanctioned operator-editing
surface is the binary-written `./infernix-host.dhall`
(`documents/engineering/host_tools_manifest.md:362-363`).

An operator-edited plain-text budget at a fixed host path is a **second configuration substrate**: not
typed Dhall, not reflected from a decoder type, not generated by the binary, and with no
fail-fast-if-missing / `init` create contract.

Two nuances matter:

- **It would not trip a lint.** `src/Infernix/Lint/Files.hs:472-492` rejects only *tracked* generated
  artifacts, and both lint walkers are rooted at `repoRoot`, so a file under the user's home is never
  seen. The conflict is doctrinal, enforced by review, not by a gate.
- **The scope is right even though the format is wrong.** `configuration_doctrine.md:130-133`
  deliberately keeps the memory budget per-machine and outside the shared contract digest, because
  "what a machine can *offer*… [is] observed per machine and never travel[s]". A per-host budget is
  categorically the correct kind of fact. Only its authoring surface conflicts.

### 5.2 What "release evidence" would have to be here

§7's third obligation is the one with the highest bar in this repository.
`documents/architecture/managed_state_transitions.md:66-80` requires either a monotone
hidden-constructor witness minted by one honest transition that consumes a real artifact, or a rank-2
region lease (`src/Infernix/Evidence/Lease.hs:14-49`, `type role Lease nominal nominal`), with
one-shot capabilities consumed linearly. `:79-80` — "The raw destructive, commit, and spawn primitives
are **not exported**; the only public path takes evidence."

A `Persistent` release for this repository would need: a rank-2 lease region enclosing the claim's
whole lifetime (a record on disk is a *residue*, and residue is what `:12-15` calls a flake); a
hidden-constructor witness whose sole mint consumes a real observation that the charged effect is
**gone**, not that the record was written; a kernel lock as the cross-namespace liveness fact
(`:342-352`); a linear spend for the one-shot release; and refusals that name the quantity, the
observed value, the compared value, and the object (`:449-461`).

---

## 6. What adoption would actually buy Infernix

### 6.1 Against this repository's recorded exhaustion incidents: nothing

| Incident | Prevented by the ledger? |
|---|---|
| Host-side `cabal build` reached 109.46 GiB on a 124.94 GiB host at `oom_score_adj` 0 (`bounded_host_memory.md:19-22`) | **No.** Infernix's own work, declared honestly, growing progressively — the shape §5 concedes. The heap ceiling fixed it. |
| Three interactive compiler images (44.1 + 29.9 + 27.4 GiB) exhausted a 64 GiB host | **No.** Human-launched `ghci`/`cabal` sessions will never enroll as participants. |
| Three orphaned `ghci` processes at 101 GiB combined, watchdog kernel panic | **No.** Same reason. |

### 6.2 Against §6's stated unique reach: three of four cases are already covered

| §6's "capacity with no process to observe" | Status here |
|---|---|
| stopped virtual machine | **Already observed** — `colima list --json` reads on-disk profile state and fails closed (`src/Infernix/HostMemory.hs:18-21`, `src/Infernix/HostTools.hs:254`) |
| idle cluster | On Apple, resident *inside* the Colima pledge, therefore already subtracted |
| retained bytes on disk | Infernix applies its own mechanism — `machineModelCacheQuotaBytes` (`src/Infernix/HostConfig.hs:196`), exactly as §5 and §7 prescribe |
| a guest or VM the fixed Colima observer does not know about | **the one genuine gap** |

### 6.3 The gap that is real, and it is not the one §6 emphasizes

`src/Infernix/BuildMemory.hs:1038-1042`:

> "This is deliberately not a machine-global lease: independently minted authorities in separate CLI
> images remain an **unsupported concurrent-claimant case named in the doctrine**."
>
> ```haskell
> newtype ToolchainSingleFlight
>   = ToolchainSingleFlight (MVar ())
> ```

The toolchain single-flight token is a **process-local `MVar`**. The only cross-process signal is
observational, and `infernix` itself is **not** in `isToolchainImageName`
(`src/Infernix/HostClaimants.hs:447-467` — the set is `cabal`, `ghc*`, `haddock`, `hsc2hs`, `runghc`,
`ghci`). So two `infernix` CLI images on one host both pass the census, and neither sees the other
until one has already forked `cabal`. The re-observation immediately before the fork
(`src/Infernix/BuildMemory.hs:1272`) narrows the window; it does not close it.
`ToolchainHostAdmission` says as much in its own haddock: "It is an observation at an instant, not a
lease."

**This is the strongest case for something ledger-shaped in this repository** — a machine-global,
crash-surviving, cross-checkout serialization point for the toolchain account. It is also the case
§6 does not emphasize, and it needs only a lock and a single claim, not a general protocol.

Note two constraints that would still bind it:

- On Linux, the census image name comes from `/proc/<pid>/status` `Name:`, which the kernel truncates
  to 15 characters. `ghc-iserv-prof` (14) fits; a longer future name would not.
- The fixed Apple observer is **strictly process-group scoped** by construction
  (`src/Infernix/Runtime/CappedEngine/FixedObserver.hs:1245-1247` retains only rows whose `PGRP`
  matches the requested group). It cannot size a foreign process at all; foreign *naming* is a
  separate `ps`/`/proc` census that reports only coarse `rss`, "attributed, never measured."

### 6.4 The complement is already adopted, and the document does not say so

`src/Infernix/HostClaimants.hs` is §6's "point-of-use observation," shipped — down to the same
reasoning:

> "It is refused rather than killed, because a repository that destroyed processes it did not start
> would be a worse failure than the one it prevents." — `src/Infernix/HostClaimants.hs:28-30`

A document about what participation *would* mean should start from what this project has already
built and state the delta.

---

## 7. Incidental defects found while checking the document's claims

These are independent of the adoption decision and worth fixing regardless.

### 7.1 A live instance of §7's own "silent drift" failure

The model-cache quota is declared three times and one has drifted:

| Site | Value |
|---|---|
| `src/Infernix/Types.hs:283` `defaultModelCacheQuotaBytes` | `68719476736` (64 GiB) |
| `chart/values.yaml:142` / `:230` | 64 GiB / `sizeLimit: 64Gi` |
| `python/adapters/model_cache.py:75` `DEFAULT_QUOTA_BYTES` | `32 * 1024 * 1024 * 1024` (**32 GiB**) |

The comment at `python/adapters/model_cache.py:72-74` still claims it "matches `chart/values.yaml`
`engine.modelCache.sizeLimit` of `32Gi`" — stale; the chart moved to 64 GiB with an explicit
rationale at `chart/values.yaml:136-141` and `:224-229` (32 GiB evicted the diffusers pod mid-bootstrap
on `linux-gpu`). The Python constant only applies when `_CONFIG is None`, i.e. a direct adapter
invocation outside the typed `ModelCacheConfig` path — so the blast radius is small, but this is
precisely "two independently authored figures drift, and the drift is silent."

### 7.2 Two host ports are hardcoded with no availability probe

`src/Infernix/Cluster.hs:6543-6558` emits `hostPort: 30011` (MinIO S3) and `hostPort: 30650` (Pulsar
binary) as literals. The other three host ports are chosen dynamically by bind-probe
(`chooseEdgePort` / `chooseRegistryPort` / `choosePulsarHttpPort`, `src/Infernix/Cluster.hs:3668-3731`).
A foreign program holding 30011 or 30650 makes `kind create` fail, and the conflict retry at
`src/Infernix/Cluster.hs:4000-4002` increments only the three *dynamic* ports, so it cannot converge.

`portIsFree` also binds `127.0.0.1` with `SO_REUSEADDR` and then closes — a TOCTOU probe that cannot
see a peer bound to `0.0.0.0:P`.

### 7.3 There is no disk-space admission anywhere in this repository

Exhaustive search for `getFileSystemStats`, `statvfs`, `blocksAvailable`, `freeSpace`,
`availableSpace`, `diskFree`, `ENOSPC`, "no space left", and "disk space" across `src/`, `app/`,
`python/`, and `bootstrap/` returns **zero hits**.

Nothing checks free disk before a `docker build`, before pulling multi-GB model weights, before a DMG
download, before materializing an engine root, before Kind's node images, or before the retained-state
snapshot copy on Apple teardown. The 64 GiB model-cache quota is the only on-disk bound of any kind,
it is per-cache rather than per-host, and it is enforced *reactively* by an LRU sweep after a write
rather than admissively before one.

### 7.4 Docker images are acquired and never released

Searches for `rmi`, `image prune`, `system prune`, and any `DockerRemoveImage` command return nothing.
No command in this repository ever deletes an image or prunes build cache. This is exactly the shape
§5 names as outside the ledger's reach ("an image set that accumulates"), so if the file survives, it
should say plainly that images are not claimable here.

---

## 8. Prior art in this repository the document should cite

If the ledger is ever revisited, these three are stronger than what §7 asks for and should be the
reference points rather than reinvented:

1. **Identity stamped on the resource, not beside it** —
   `/etc/infernix/cluster-checkout-identity` (`src/Infernix/Cluster.hs:1791-1913`). The record lives
   inside the control-plane node, so it dies with the resource, needs no release step, and cannot go
   stale. Unreadable means `ClusterSlotUnidentified`, the fail-closed arm — the same polarity as §2's
   "free is a positive value a writer must deliberately produce". The two owners are deliberately
   **asymmetric** (`:1707-1713`): the operator may adopt an unidentified cluster, the harness may not.
   A uniform ledger cannot express that.

2. **Release proven by re-observation, not by an exit code** — the Audiveris DMG mount
   (`src/Infernix/Engines/AppleSilicon/Internal.hs:1822-1953`). A durable two-phase JSON record
   captures the **device and inode** of the mountpoint; `detachAudiverisExactMountAndRetire` retires
   the record only after re-observing that the mountpoint became a placeholder again; an *unrecorded*
   mount is rejected outright. This is the best `Persistent` release model in the repository.

3. **Release ordering with quiescence evidence** — `releaseHarnessClusterSlotAt`
   (`src/Infernix/Cluster.hs:3080-3117`): caller pid matches recorded owner, config transaction in a
   terminal state, teardown succeeds, process group proven quiescent, *then* the reservation is
   removed. Plus the observed-absence fallback after a failed `kind delete`
   (`src/Infernix/Cluster.hs:8300-8310`, `:8365-8375`).

Also worth noting as precedent, because it corrects an obvious objection: a `$HOME`-rooted lock file
is **already an endorsed pattern here**. `src/Infernix/Python/MutationLock/Internal.hs:72-80` holds
`<home>/.infernix-poetry-bootstrap.lock` behind a hidden-constructor nominal authority, rank-2
quantification, and `withKernelFileLock`, and `poetryHomeFromConfig` (`src/Infernix/Python.hs:1164-1168`)
already writes `<home>/.local/share/pypoetry`. Durable state outside the repo root is not new; only
the *config substrate* question (§5.1) is genuinely novel.

---

## 9. One structural caution

Infernix's architectural vocabulary is unusually strict: "by construction," "does not typecheck,"
"unrepresentable," typed evidence, hidden constructors, rank-2 lease regions. The ledger is
**advisory between cooperating programs** — a categorically weaker guarantee. §3 is clear about that
in isolation, but the document borrows `claim`, `budget`, `reserve`, `admission`, `release`, and
`pool` from a set where every one of those words currently denotes something *enforced*.

If the file survives in any form, it should carry one explicit sentence: **a granted ledger claim is
never evidence for a `managed_state_transitions.md` transition.** It is not typed evidence, it has no
mint that consumes a real artifact, and it must never be presented as such.

---

## 10. Recommendation

**Do not adopt.** Keep the thinking; fix the file. In priority order:

1. **Move** `documents/engineering/shared_host_resource_protocol.md` to
   `documents/research/shared_host_resource_protocol.md`; update `requiredDocs`
   (`src/Infernix/Lint/Docs.hs:92`) to the new path — the drift guard at `:459-467` requires
   registration either way; reduce the `documents/README.md:99-105` entry to one line.
2. **Rename** every use of `claim` / `ledger` / `budget` / `reserve` / `pool` to non-colliding terms
   (§3.4).
3. **Correct §6**: split process observation from artifact observation; withdraw the "stopped virtual
   machine" example; cite `Infernix.HostClaimants` and the Colima observer as *already adopted* and
   state the delta (§3.1, §6.4).
4. **Correct §1**: drop the Windows path or mark it explicitly out of scope; replace "`$HOME`… never
   selected by an environment variable" with an OS-authoritative home-record rule; add the
   containerized-participant mount contract and the decline-rather-than-write-privately rule; amend
   "creates no dependency" (§3.2, §3.3, §3.3a, §3.3b).
5. **Fix §2's contradiction** between properties 1 and 2, and add the missing reclaim story for
   leaked `Persistent` claims (§4.1, §4.2).
6. **Add a section naming what is unspecified** — dimensions, encoding, lock semantics, identifier
   grammar, `spec-version` — so §7's adoption cost is visibly unknown rather than invisibly so (§5).
7. **Add** the sentence that a granted claim is never typed evidence for a managed state transition
   (§9).

If the ledger is ever revisited seriously, the precondition is not a document change — it is the other
project publishing an actual specification, plus a container and identity model at least as strong as
`/etc/infernix/cluster-checkout-identity`.

Separately, and independent of that decision: fix the model-cache quota drift (§7.1), probe or
document ports 30011 and 30650 (§7.2), and decide whether the absence of any disk-space admission
(§7.3) is intentional.
