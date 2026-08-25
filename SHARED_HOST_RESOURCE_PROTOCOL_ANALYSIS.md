# Shared Host Resource Protocol Analysis

**Status**: Review artifact (non-authoritative)
**Subject**: [Shared Host Resource Protocol](documents/engineering/shared_host_resource_protocol.md)

> **Purpose**: Record a critical assessment of the current 98-line shared-host-resource-protocol
> record against Infernix's implementation, canonical doctrine, and development-plan history.

This file is a review artifact. It establishes no implementation status, owns no doctrine, and is
not part of the governed documentation suite — `infernix lint docs` scans `documents/`,
`DEVELOPMENT_PLAN/`, and the three governed root documents, and this file is in none of them
(`src/Infernix/Lint/Docs.hs:451-515`). Every citation below was read at `9f670b2`.

## Contents

- [Executive assessment](#executive-assessment)
- [Provenance](#provenance)
- [Method](#method)
- [Findings](#findings)
- [What the document gets right](#what-the-document-gets-right)
- [Candidate findings that did not survive verification](#candidate-findings-that-did-not-survive-verification)
- [Recommended revisions](#recommended-revisions)
- [Verification](#verification)

## Executive assessment

**The shrink was right. The residue is not yet accurate about what this project already has.**

Cutting a 1028-line cross-project protocol specification out of a product repository was correct and
is consistent with this repository's own doctrine: a Markdown copy of another project's spec confers
no semantic authority, and four divergent copies is a DRY failure by construction.

The document's central observation is real and is admitted by the source it describes.
`src/Infernix/BuildMemory.hs:1037-1040` says the toolchain single-flight token "is deliberately not a
machine-global lease: independently minted authorities in separate CLI images remain an unsupported
concurrent-claimant case named in the doctrine," and
`documents/architecture/daemon_topology.md:230-233` says the engine lock "is repo-local, not
machine-global, so it does not exclude two checkouts on one host and it cannot exclude a second
machine." Those are genuine, self-named, open gaps, and a machine-global object is a reasonable
shape for closing them.

What the current text does not yet do:

1. Its single most confidently stated sentence — one engine per **physical machine** — strengthens a
   doctrine rule in a way that would refuse a supported `--engine-machines N` configuration.
2. It proposes replacing `engine.lock` while omitting the broker-side member claim, which the
   doctrine names as the mechanism that actually expresses the one-engine-per-machine rule.
3. It names one attachment seam for three claim classes, and the seam it names carries only the one
   that least needs a lease.
4. It leads with the cluster cross-checkout defect, which is closed, and proposes as its remedy the
   option this repository analysed and rejected on the record — without citing the rejection.
5. It has no "local work worth doing regardless" section, so at least four ledger-independent
   correctness debts go unnamed, including a real race in the very mechanism it proposes to replace.

The right disposition is to keep the document, keep it short, and correct it — not to expand it back
toward a specification, and not to adopt anything on the strength of it as written.

## Provenance

| Commit | Date | Shape |
|---|---|---|
| `081ee88` | 2026-08-24 | Added as 854 lines, titled *Finite Resource Execution Authority Protocol*, defining a project-neutral protocol for `amoebius`, `infernix`, `jitML`, `hostbootstrap` |
| `35a5c50` | 2026-08-24 | Grown to 1028 lines; ownership topology, amoebius cutover, conformance, core-freeze governance |
| `9f670b2` | 2026-08-24 | Cut to 98 lines; every project name removed; companion root-level analysis deleted in the same commit |

The same filename exists in all four sibling repositories on this machine, in three mutually
incompatible states:

| Repo | Lines | Status | Declares the owner to be |
|---|---|---|---|
| `amoebius` | 869 | Authoritative source | amoebius; seeds re-derive |
| `hostbootstrap` | 854 | Draft | a separate product-neutral repository |
| `jitML` | 91 | Draft | the machine operator's installed root |
| `infernix` | 98 | Draft | the machine operator's installed root |

Revision 1 of this file (lines 208-215) named the installed root:
`/var/lib/finite-resource-authority` on Linux, `/Library/Application Support/FiniteResourceAuthority`
on Darwin, `FOLDERID_ProgramData\FiniteResourceAuthority` on Windows. The shrink removed that and
left no coordinate. No such root exists on this machine.

## Method

Three independent review lenses (factual accuracy against code, doctrine consistency, strategic
value) each produced findings against the document; every finding was then handed to an independent
adversarial verifier instructed to refute it, with the citations re-read. Forty-one candidate
findings were raised; twenty-two survived, several in narrowed form. Findings that were refuted are
recorded below rather than silently dropped.

## Findings

### 1 — HIGH: §2 ¶2 misstates the topology rule, and would refuse a supported lane

> "one engine process per **physical machine** is an Infernix correctness rule, not operator policy."

The rule is one engine per **machine**, where a machine is a fleet member, not a physical box.
`documents/architecture/daemon_topology.md:198-201`: "a fleet of machines, each running exactly one
engine process… A machine is the unit of capacity, of model cache, and of configuration."

On the Linux lanes, N fleet machines are N Kind worker nodes on **one** Docker daemon — one physical
host — each running its own `infernix-engine-m<slot>` Deployment
(`documents/architecture/daemon_topology.md:250-257`):

```haskell
-- src/Infernix/Cluster.hs:6602-6608
kindWorkerCount runtimeMode machineCount =
  case runtimeMode of
    -- Apple engine members are host daemons, so an Apple fleet is a second Mac
    -- rather than a second node: the cluster's worker count is unaffected by it.
    AppleSilicon -> 1
    _ -> max 1 (engineMachineCountValue machineCount)
```

So `infernix init --engine-machines 3` on `linux-cpu` deliberately runs three engine processes on one
physical machine, and an adapter written to this sentence would refuse a supported configuration.
The phrase "physical machine" occurs nowhere else in the repository except this document (`:47`) and
its index entry (`documents/README.md:103`). It is accurate only on Apple, where a fleet member is a
second Mac.

The underlying intent — that the ledger's slot count is policy and must never be read as permission
to run a second engine that independently admits against the same machine — is right and worth
protecting. The word "physical" is what breaks it.

### 2 — HIGH: §2 omits the broker-side member claim, which is the mechanism the doctrine relies on

§2 offers the ledger claim as "the candidate replacement for the checkout-local `engine.lock` — a
replacement, not a second authority beside it with no declared precedence." The instinct is right;
the inventory is incomplete. A second authority already exists, and the doctrine says it — not
`engine.lock` — is what expresses the rule:

- `documents/architecture/daemon_topology.md:263`: the engine Deployment's `nodeSelector` "does not
  express the one-engine-per-machine rule at all — **the broker claim does**."
- `documents/architecture/daemon_topology.md:267-278`: each member has a derived claim topic
  (`persistent://infernix/demo/fleet.member-claim.<mode>.<member>`) carrying no messages; "holding
  the only **exclusive** subscription on it is the claim." Taken after namespace/topic reconciliation
  and the contract-digest check, and **before** the readiness sentinel and every pool subscription.
  Losing it later is fatal.
- Implemented at `src/Infernix/EngineRouting.hs:65-72` and `src/Infernix/Runtime/Pulsar.hs:2645-2651`,
  wired at `src/Infernix/Runtime/Daemon.hs:311-319`.
- `src/Infernix/Service.hs:216-220` names the broker claim as `engine.lock`'s complementary
  cross-machine half.

The two bound different predicates. `documents/architecture/daemon_topology.md:280-281`: the broker
claim "bounds **one identity to one live claimant at a time**. It does not bound how many machines a
fleet has." A host-scoped ledger claim would bound something else again.

Because §2 offers the ledger claim specifically as a replacement for one half, it owes the reader
the pairing: does the other half stay, and what is the precedence? As written it proposes exactly the
undeclared-precedence third authority it says it wants to avoid. One or two sentences fix this; it is
not a rework.

For precision: the broker claim does **not** close the two-checkouts-on-one-host hole §1 is about.
`documents/architecture/daemon_topology.md:230-233` leaves that hole open. Both statements are true
and the document should carry both.

### 3 — HIGH: §3 names one attachment seam for three claim classes

§2 names three claims — a `Transient` toolchain claim, a whole-device Metal/CUDA claim, and a
`Persistent` claim for the cluster and the engine. §3 answers "where it would attach" with exactly
one seam: the toolchain host-admission seam.

That seam is `ToolchainHostAdmission` (`src/Infernix/BuildMemory.hs:1058-1064`), minted only inside
`withToolchainSpawnAuthority` (`:1201`, re-taken at the child boundary `:1272`). Its production entry
points are `src/Infernix/CLI.hs:998` and `src/Infernix/CLI.hs:1829`, and both govern the governed
Cabal invocation (`resolveCliHostTool paths HostCabal`, `CLI.hs:1291`, `:1847`), plus one non-Cabal
child, the installed-CLI RTS isolation proof (`CLI.hs:1245-1257`).

Verified **not** on that seam:

- `ClusterUpCommand` / `ClusterDownCommand` dispatch directly (`src/Infernix/CLI.hs:239-241`).
- `ServiceCommand -> runService` — the engine daemon (`src/Infernix/CLI.hs:238`).
- `TestE2ECommand -> runEndToEnd -> clusterUpHarness` (`src/Infernix/CLI.hs:268-271`, `:571-583`) —
  the path that starts the host inference daemon and runs real model inference. The heaviest
  host-memory consumer in the system traverses no host-admission seam at all.

So §3 answers the question for the claim class that least needs a lease — transient, supervised,
foreground compilation, which §2 itself concedes is honest because "when it dies, the operating
system has reclaimed what was charged" — and leaves both `Persistent` claims with no named seam.
Adoption needs three or four seam changes. The document never says so.

### 4 — MEDIUM: §1's lead motivation is closed, and §6 revives a remedy this repository rejected

§1: "the lifecycle lock, the harness reservation, and the persisted state are all repository-local,
while the Kind cluster they claim to protect is machine-global. A ledger gives those three a
machine-global object to name."

That paraphrases `documents/operations/cluster_bootstrap_runbook.md:275-277` and stops immediately
before `:277-280`, which states the landed remedy: the creating checkout's host-side repository root
recorded on the cluster itself at `/etc/infernix/cluster-checkout-identity`, read back by "every
ownership decision" (`src/Infernix/Cluster.hs:1790-1794`; `authorizeClusterOwnership` at `:1717-1762`;
harness may not adopt an unidentified cluster, `:1748-1755`).

`DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md:2720` — *"Sprint 6.45: Machine-Scoped
Cluster-Slot Ownership And Type-Indexed Teardown Owner **[Done]**"*; `:2728` "All four deliverables
are code-side closed"; Remaining Work: None. §6's "a machine-global object is what that work needs"
is therefore stale.

More pointedly, `:2793-2801` records that the ledger's shape was evaluated and **rejected**:

> *Option (a), move the lock and reservation to a machine-scoped location*, fails on the Linux lane…
> the baked host manifest gives every launcher container `hostRepoRoot = /workspace`… A
> "machine-scoped" lock path is unreachable from inside the container, and a path-derived checkout
> identity actively collides.

(Baked value confirmed at `src/Infernix/HostConfig.hs:802`.) An installed ledger root at a fixed host
path fails the identical test. §4 raises this as an open question without citing the decision that
already recorded the answer.

Two points in the document's favour, both established during verification: "already has an owner" is
accurate, and §4's same-path bind-mount requirement is a *response* to the reachability objection
rather than a repetition of it. The Apple-host-versus-Colima-VM membership question §4 raises is
genuinely unanswered in this repository.

The residual gap the document should be claiming instead: **identity closed authorization, not mutual
exclusion.** Two checkouts still take different inodes — `clusterStatePath`,
`clusterLifecycleLockPath`, `harnessReservationPath`, `harnessLifetimeLockPath` are all under the
repo-local `runtimeRoot` (`src/Infernix/Cluster.hs:183-196`; `runtimeRoot` resolved against
`repoRoot` at `src/Infernix/Config.hs:107-116`) — so concurrent mutation between two checkouts is
still unfenced even though a destructive teardown is now refused.

### 5 — MEDIUM: §2's whole-device claim has no surface, makes no lifetime decision, and collides with an existing authority

> "A claim holding the whole-device domain for a Metal or CUDA execution, so two participants cannot
> select the same physical accelerator."

Infernix performs **no device selection on any path**:

- CUDA: `python/adapters/vllm_python.py:50` hardcodes ordinal `0`
  (`torch.cuda.get_device_properties(0)`); `python/adapters/pytorch_python.py:322` uses the bare
  string `"cuda"`. No index anywhere.
- Metal: `python/adapters/pytorch_python.py:22`, `transformers_python.py:71`, `diffusers_python.py:52`
  all return the bare string `"mps"`. `mx.set_default_device(mx.gpu)` appears only in the smoke probe
  (`python/native-runners/apple_native_runner.py:289`).
- Native llama.cpp artifacts are CPU-only on every lane: `llamaExecutionGpuLayers = 0`
  (`src/Infernix/Runtime/CappedEngine/Internal.hs:1267`) and `llamaLaneSpecificArguments` returns `[]`
  for `AppleSilicon`, `LinuxCpu`, and `LinuxGpu` alike (`:1272-1277`); whisper.cpp launches
  `--no-gpu` (`:1320`).
- On multi-GPU, the engine **refuses to run**. `parseNvidiaDeviceTotalMib`
  (`src/Infernix/Runtime/CappedEngine/FixedObserver.hs:1438-1440`) returns *"NVIDIA device-memory
  output named more than one device; per-device VRAM enforcement requires exactly one"*, which
  propagates to `NvidiaEnvelopeUnavailable` and blocks readiness.

There is no selection to exclude. On Apple there is one GPU, so the claim's real content is "one
project at a time gets the Mac's GPU" — and Infernix is a serving daemon. The document never says
whether the claim is per-inference (contention on the request path, producing exactly the delivery
consequence §2's own closing paragraph warns about) or per-daemon-lifetime (no other participant
touches the GPU while Infernix serves). Both are large product decisions. The `jitML` copy states the
analogous tradeoff explicitly and says it owes a decision; this one asserts and moves on.

In-cluster device assignment is also already owned by the Kubernetes device plugin
(`nvidia.com/gpu: "1"`, `chart/templates/deployment-engine.yaml:96`), which a host-level claim would
have to be reconciled against.

Where such a claim *would* attach is already declared and unimplemented:
`documents/architecture/typed_execution_plan.md:98-106` carries `deviceIds : List Natural` in the
target `MemoryEnforcement` schema, and it does not exist in the Haskell — the implemented shape is
`DualEnforcedBudget PodMemoryLimit PodMemoryLimit` (`src/Infernix/Types.hs:1095-1103`), two scalars
with no device identity.

### 6 — MEDIUM: no "local work worth doing regardless" section

The `jitML` copy carries a section listing repo-local correctness debts that need no ledger. This one
has none, and §6 instead pushes an owned defect onto a nonexistent external dependency. Real
ledger-independent debts this document is well placed to name:

- **`engine.lock` has a test-and-set race.** `getLock` (`src/Infernix/Service.hs:251`) and `setLock`
  (`:266`) are two separate syscalls. Two engines starting simultaneously can both observe `Nothing`
  and both take the lock. Every other lock in the repository goes through atomic
  `FileLock.tryLockFile` (`src/Infernix/Cluster/LifecycleLock.hs:32-47`). Fixing the mechanism §2
  proposes to replace requires no ledger at all.
- **A contended claim has no representation.** `InferenceError`
  (`src/Infernix/Types.hs:1382-1404`) is closed over two constructors, `ModelMemoryLimitExceeded` and
  `ModelRequirementUnderivable`, both terminal. The inference nack path
  (`src/Infernix/Runtime/Pulsar.hs:3013-3026`) has **no backoff**, unlike `handleBootstrapFailure`
  (`:4296-4328`). So today a contention refusal has exactly two expressible shapes and both are the
  failure §2's closing paragraph forbids: throw (→ nack → unbounded immediate redelivery), or publish
  `ModelMemoryLimitExceeded` (→ "published as a model-capacity failure", reaching the browser as
  such). The pattern to copy already exists one module over — `DownloadOutcome` with
  `DownloadRateLimited` / `DownloadTransient` / `DownloadPermanent`
  (`src/Infernix/Runtime/Pulsar.hs:4898-4909`). **This is the document's best insight and it is
  buried as an aside.**
- **`deviceIds`** declared at `documents/architecture/typed_execution_plan.md:98-106`, absent from the
  Haskell.
- **The residual cluster exclusion gap** from Finding 4.

A change to the contended/terminal split would additionally trigger the co-update obligation at
`documents/documentation_standards.md:233` (delivery-semantics changes require the canonical homes to
move in the same change), and `documents/architecture/pulsar_ml_workflow.md` is shared verbatim with
`jitML` and must not be forked.

### 7 — MEDIUM: §2's first bullet charges a quantity this project deliberately does not model

> "A `Transient` claim for a toolchain invocation, charging host memory **and processor time**."

There is no processor-time account anywhere. `maximumBuildJobs` is capped at 8 with an explicit
rationale (`src/Infernix/BuildMemory.hs:318-321`):

> Bounded rather than `$ncpus` on purpose: the job count is what the memory budget affords, never
> what the processor count affords.

repeated in the refusal message at `:451`. `documents/architecture/bounded_host_memory.md` mentions
CPU exactly once, at `:54`, as a cautionary example of what not to derive concurrency from. Charging
processor time introduces a quantity with no derivation, and a ledger arbitrating CPU shares pulls
toward exactly the reasoning this module refuses.

### 8 — MEDIUM: §5 states a layered pair as universal; it holds on one arm, and not on the lane §4 admits

§5: "A data-segment ceiling installed before the engine's first instruction covers private writable
mappings… a fixed-cadence observer covers the shared and pinned memory that ceiling does not charge.
**Both are required**." No lane qualification. But
`src/Infernix/Runtime/CappedEngine/Ceiling.hs:203-215`:

```haskell
ceilingStrengthForLane runtimeModeValue resource =
  case (runtimeModeValue, resource) of
    (AppleSilicon, _)  -> CeilingDetectionOnly
    (_, NvidiaVram)    -> CeilingDetectionOnly
    (LinuxCpu, PodRam) -> strengthFromCalibration HostCeilingCalibrationObserved
    (LinuxGpu, PodRam) -> strengthFromCalibration HostCeilingCalibrationPending
    _                  -> CeilingDetectionOnly
```

Exactly one `(lane, resource)` arm has an installed ceiling today. On Apple Silicon the ceiling layer
is absent entirely and only the observer runs — and §4 restricts honest participation to host-native
invocations, which on this platform means Apple. The document therefore describes as required a
mechanism that is missing on the one lane it says participation is currently honest for. This erases
the doctrine's most emphatic property, `documents/architecture/bounded_inference_memory.md:149`:
"**A lane declares the strength it has.**"

Minor and editorial: `:86` calls it "the pair" while the doctrine consistently states three layers —
prevention, detection, and **conformance**, the engine reporting back the limit it actually received
(`documents/architecture/bounded_inference_memory.md:71-74`; implemented as `ceilingReadBackMatches`,
`src/Infernix/Runtime/CappedEngine/Ceiling.hs:317`). §5 is scoped to *coverage* and conformance
charges no memory, so two is the right count for that scope; "the pair" simply reads as an
enumeration of the doctrine. §5's boundary argument would also be stronger for observing that a
shared claim carries no read-back at all, so conformance is another thing that cannot cross the
boundary.

### 9 — MEDIUM: the document sits awkwardly against this repository's prescriptive-voice doctrine

`documents/documentation_standards.md:106-108` requires a governed document to state "what the system
must do, in present-tense declarative voice, whether or not the implementation has landed," and
`:133-134` forbids annotating a document with its own future: "a sprint reference inside a governed
doc is status wearing a doctrine costume." Banned vocabulary at `:136-138` includes `remains open`,
`not yet landed`, `in progress`.

The "**Not adopted.** … no phase owns the work" paragraph (`:11`) and the whole of
"## 6. Open before adoption" (`:92-95`) are status reports by that test. They pass `infernix lint
docs` only because the exact banned strings differ.

Conformance is otherwise unenforced. `src/Infernix/Lint/Docs.hs:521-522` checks only that the literal
`**Status**:` is present, never its value. Anchor-only table-of-contents links are stripped to the
empty string and skipped (`:1324-1327`, `:1306`), so a `## Contents` list may point at headings that
do not exist. Heading structure is enforced for twelve named documents and this is not one of them.
`Draft` is a legal status (`documents/documentation_standards.md:26`), but this is the only `Draft`
document among fifty-four `Authoritative source` documents. Its anchors do all resolve — checked by
hand.

### 10 — MEDIUM: the document is not actionable

Four soft decisions against five explicit deferrals, and no executable next step. §6's three items
are all "someone must decide"; §4 ends "until it is settled, participation is honest only for
host-native invocations." The one implementable slice — the contended/terminal outcome type in
Finding 6 — is never stated as one.

### 11 — LOW: naming drift in the deferred vocabulary

The preamble stakes the record's legitimacy on deferring outward: "its authority is the installed
root and the `spec-version` that root carries, never a copy of a document in any repository,
including this one." No such root exists on this machine.

The backticked tokens `spec-version`, `Transient`, and `Persistent` appear in no long-form copy of
the protocol on this machine. The 869-line `amoebius` copy uses `DomainKind`, `PhysicalDomain`,
`LockKey`, `Lease`, and `ClaimKey`; expresses claim lifetime as lowercase arithmetic
(`persistent + maximum concurrent transient`); and carries protocol version "inside the layout and
journal, never in the root or lock pathname."

This is **naming drift between the shrunk sibling template and the long-form spec, not invented
vocabulary** — the underlying claim-lifetime axis and the root-carried version concept are both
defined upstream. It is also not a legitimacy defect, since the document deliberately refuses to
treat any repository copy as its authority and no installed root exists to check spellings against.
It warrants one line in §6: reconcile the token spellings against the installed root's actual field
names at adoption time.

Related, and worth recording: revision 1 of this same file named the root
(`/var/lib/finite-resource-authority`, `/Library/Application Support/FiniteResourceAuthority`,
`FOLDERID_ProgramData\FiniteResourceAuthority`) and the shrink removed it without leaving a
coordinate. A reader cannot navigate from this file to any counterpart; `amoebius` now appears
nowhere in this working tree.

### 12 — LOW: three factual and wording slips

- **§4 misdescribes the launcher container's mount set.** "Adding one mount alongside the repository
  and Docker-socket mounts is small." `compose.yaml:5-7` mounts exactly two things,
  `./.data:/workspace/.data` and `/var/run/docker.sock`. The repository source is **baked**, not
  mounted (`docker/Dockerfile:202` `COPY . /workspace`; `documents/development/local_dev.md:283-284`).
  The mount count is right and the fix is one word — `.data` for "repository" — but the paragraph is
  reasoning about what crosses the container boundary while misstating what currently crosses it.
- **§1's "Both existing exclusion mechanisms" undercounts.** The quantifier reads as exhaustive, yet
  the document's own next paragraph names two more repo-local objects
  (`src/Infernix/Cluster.hs:186`, `:190`), and the capped-engine process-local execution authority is
  a further one (`documents/architecture/bounded_inference_memory.md:222`). "The two mechanisms
  nearest the seam" would be accurate.
- **No in-body citations.** §1 quotes `runtimeRoot </> "engine.lock"` verbatim from
  `documents/architecture/daemon_topology.md:231` and paraphrases
  `documents/operations/cluster_bootstrap_runbook.md:275-277` as "The source states the consequence
  directly," naming neither. §6 defers to an owner it does not name. In a suite whose standards
  require `Referenced by` links, arguing from unnamed sources is what allowed Finding 4's truncation
  to pass unnoticed.

## What the document gets right

- **The shrink itself.** Removing 900+ lines of another project's specification from a product
  repository was correct, and consistent with this repository's own DRY and authority doctrine.
- **§1's two mechanism descriptions are accurate to source.** The engine lock really is
  `runtimeRoot </> "engine.lock"` (`src/Infernix/Service.hs:224-225`) under a structurally
  repo-anchored `runtimeRoot` — `src/Infernix/Config.hs:115` hardcodes `resolveAgainst repoRootPath`,
  so this is a property of the code and not a manifest convention. Toolchain admission really is an
  observation at an instant re-taken at the child boundary
  (`src/Infernix/BuildMemory.hs:1267-1272`), near-verbatim from that module's own Haddock
  (`:1054-1057`).
- **§4's Linux claim is correct.** There is no supported Linux host-native command path:
  `src/Infernix/Config.hs:222-233` refuses `(HostNative, _)` by name — "The host-native
  `./.build/infernix` control plane supports only `apple-silicon`." The Apple-host-versus-Colima-VM
  membership question §4 raises is genuinely open in this repository.
- **The replacement-not-a-second-authority framing** is the right shape of question, even though
  Finding 2 shows the inventory behind it is incomplete.
- **§5's conclusion** — that coverage is a participant's own business and does not cross the
  boundary — is sound.
- **The refusal-outcome paragraph** identifies a genuine, currently unrepresentable distinction, and
  it is the most useful sentence in the document.

## Candidate findings that did not survive verification

Recorded so this review is auditable rather than one-sided.

- *"§5 labels the inference-engine ceiling 'host-memory enforcement', which is the conflation
  `bounded_host_memory.md:126-133` exists to prevent."* **Refuted.** That warning is specifically
  about merging the *toolchain* address-space row with the *inference* data-segment row. §5 never
  mentions the toolchain row, so no merge occurs, and the engine ceiling does bound host RAM.
- *"§1's 'runtimeRoot resolves against the repository' is a manifest convention, not a structural
  property."* **Refuted** — `src/Infernix/Config.hs:115` hardcodes the repo anchor; only an absolute
  manifest value escapes it (`:142-145`).
- *"§4's second sentence attributes a host-native control plane to the linux-cpu lane."* **Refuted** —
  the document's claim is accurate; `src/Infernix/Config.hs:222-233` refuses it by name.
- *"§2's `Transient` honesty argument is falsified by the toolchain lifecycle's own stated limit."*
  **Refuted** — the sentence is about OS reclamation, not a descendant-absence proof.
- *"A ledger claim is strictly weaker than `engine.lock` on crash."* **Refuted** — the only
  specification text that exists for the ledger describes kernel locks released by process death.
- *"The ledger is a second, non-Dhall admission substrate that conflicts with the configuration
  doctrine."* **Refuted** — line 13 governs which *text* is authoritative, not which configuration
  substrate is supported, and the pinned-literal rule concerns executables an observer follows.
- *"§3 and §5 contradict each other"*; *"the document never says what an absent ledger root means"*;
  *"§2's refusal-semantics paragraph is a delivery-semantics statement made outside its canonical
  homes."* All **refuted** on the cited sources.

## Recommended revisions

1. **§2 ¶2** — "physical machine" → "machine"; same in `documents/README.md:103`. Cite
   `documents/architecture/daemon_topology.md:198-207`.
2. **§2 bullet 3** — name the broker-side member claim, state its scope (one identity, one live
   claimant), and say whether it stays if the ledger replaces `engine.lock`.
3. **§1 and §6** — quote the runbook's third sentence; state that identity closed authorization and
   that the residual gap is concurrent-mutation exclusion; cite
   `DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md:2793-2801` for the already-rejected
   machine-scoped option, and reframe §4 as "decided once already, here is why it does not
   generalize."
4. **§3** — name a seam per claim class, or state plainly that the cluster, engine, and end-to-end
   paths traverse no host-admission seam (`src/Infernix/CLI.hs:238-241`, `:268-271`).
5. **§2 bullet 1** — drop "and processor time", or state that Infernix has no such quantity and why
   (`src/Infernix/BuildMemory.hs:318-321`).
6. **§2 bullet 2** — add the lifetime decision, the multi-GPU refusal
   (`src/Infernix/Runtime/CappedEngine/FixedObserver.hs:1438-1440`), the declared-but-absent
   `deviceIds`, the Kubernetes device-plugin interaction, and the serving-latency tradeoff.
7. **§5** — qualify per lane using the `ceilingStrengthForLane` table; note that the lane §4 admits
   participation for is the lane with no ceiling; soften "the pair".
8. **New section** — "Local work worth doing regardless": the `engine.lock` test-and-set race, the
   missing contended outcome with `DownloadOutcome` as the pattern, the residual cluster exclusion
   gap, and `deviceIds`.
9. **Citations and wording** — link `daemon_topology.md` and `cluster_bootstrap_runbook.md` inline;
   fix §4's mount wording and §1's "Both".

## Verification

- `./.build/infernix lint docs` after any edit to the subject document. It is a member of the
  mandatory `requiredDocs` set (`src/Infernix/Lint/Docs.hs:92`), so it must keep resolving its links
  and metadata. On Apple Silicon run `./.build/infernix` directly; use the Linux outer-container
  launcher for `linux-cpu` or `linux-gpu`.
- Re-check the table-of-contents anchors by hand — the lint does not validate them
  (`src/Infernix/Lint/Docs.hs:1306`, `:1324-1327`).
- This analysis file is outside every lint scope (`src/Infernix/Lint/Docs.hs:451-515`); it is not a
  governed document and needs no registration.
- If the "local work" section lands, re-verify each claim against its cited `file:line`.
