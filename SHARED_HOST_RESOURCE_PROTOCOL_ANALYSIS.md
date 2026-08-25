# Shared Host Resource Protocol Analysis

**Status**: Review artifact (non-authoritative)
**Subject**: [Shared Host Resource Protocol](documents/engineering/shared_host_resource_protocol.md)

> **Purpose**: Record a critical assessment of the proposed shared-host resource protocol against
> Infernix's current architecture, invariants, implementation boundaries, and development-plan
> discipline.

## Executive assessment

The proposal is directionally strong but is not ready to be frozen as a neutral interoperability
kernel or adopted by Infernix.

It addresses a real weakness in the current project. Infernix's toolchain admission is explicitly an
observation at an instant rather than a machine-global lease, and its engine lock is local to one
repository checkout. A permanent host object namespace, machine-global cell locks, durable custody
records, and honest quarantine could prevent two participating projects or checkouts from spending
the same host capacity concurrently.

The present draft does not yet close the harder parts of that transition:

1. It does not provide an operationally complete host-native rendezvous for Infernix's transient
   Linux outer containers or the Darwin/Colima split on Apple hosts.
2. Its assurance algebra does not precisely express Infernix's layered memory enforcement, where a
   partial hard ceiling and a reactive observer cover different parts of the same resource.
3. Base-plus-turn acquisition lacks the lock-ranking and slot semantics required for deadlock-free
   nested acquisition.
4. The Infernix adoption boundary is only one table row and does not map the protocol into cluster
   ownership, one-engine-per-machine enforcement, typed engine launch, or Pulsar acknowledgement
   semantics.
5. The protocol defines individually durable pages but not an interoperable crash transaction across
   its cell, project, slot, and receipt records.
6. Its proposal, migration, and ownership-cutover material is living in the governed documentation
   suite without a corresponding Infernix development-plan adoption phase.

The right disposition is therefore: preserve the design direction, do not freeze the core, and
prototype the smallest cross-boundary cooperative lease before accepting the protocol as target
architecture.

## Review scope

This assessment compares the proposal primarily with:

- [Managed State Transitions](documents/architecture/managed_state_transitions.md)
- [Bounded Host Memory](documents/architecture/bounded_host_memory.md)
- [Bounded Inference Memory](documents/architecture/bounded_inference_memory.md)
- [Typed Execution Plan](documents/architecture/typed_execution_plan.md)
- [Daemon Topology](documents/architecture/daemon_topology.md)
- [Configuration Doctrine](documents/architecture/configuration_doctrine.md)
- [Local Development](documents/development/local_dev.md)
- [Documentation Standards](documents/documentation_standards.md)
- [Development Plan](DEVELOPMENT_PLAN/README.md)
- the current toolchain admission implementation in
  [`src/Infernix/BuildMemory.hs`](src/Infernix/BuildMemory.hs)
- the current engine-lock implementation in [`src/Infernix/Service.hs`](src/Infernix/Service.hs)

The assessment concerns architectural compatibility and adoption readiness. It does not claim that
the draft has an implementation, that its proposed neutral repository exists, or that passing the
repository documentation lint constitutes protocol conformance.

## What the proposal is trying to establish

The protocol separates shared-host resource coordination into five concerns:

1. A neutral interoperability kernel defines identities, encoding, permanent lock objects, bounded
   records, lock order, lease transitions, quarantine, and core refusals.
2. Resource-family releases define physical identities, capacity dimensions, aliases, conflicts,
   and invalidators for CPU, memory, storage, CUDA, Metal, and future accelerators.
3. Mechanism-profile releases describe how a resource is excluded, bounded, partitioned, observed,
   and recovered on a particular operating-system backend.
4. Project-local adapters convert project requirements into the generic resource model and convert
   resource and lifecycle receipts back into project outcomes.
5. Project-local anchors hold kernel custody for effects that outlive a foreground CLI process,
   without introducing a shared scheduling daemon.

Admission uses a short global critical section to select a predeclared cell. The holder retains its
epoch, admission-slot, cell, and physical-domain locks for the lease lifetime. Persistent effects use
a durable recovery state machine and quarantine uncertain state instead of treating process death as
proof that an external effect is absent.

The proposal also separates:

- persistent base cells from temporary turn cells;
- cooperative exclusion from enforced and recoverable authority;
- physical resources from enforcement domains;
- resource families from mechanism implementations; and
- shared custody from project-specific lifecycle semantics.

Those separations are sound design goals and fit Infernix's general preference for narrow opaque
capabilities and evidence-gated transitions.

## Current Infernix baseline

Several existing project constraints are load-bearing for this review.

### Toolchain admission is not a host lease

`ToolchainSpawnAuthority` serializes children created through one in-process authority. Its own
documentation states that it is deliberately not machine-global. `ToolchainHostAdmission` observes
available memory and foreign toolchain claimants when minted and immediately before spawn, but its
documentation also states that the result is an instantaneous observation rather than a lease.

This is honest and materially weaker than the proposed host protocol. Another checkout or project
can begin consuming the same pool after the observation. A shared permanent cell would close that
time-of-check/time-of-use gap for participating claimants.

### The engine lock is not machine-global

The engine process holds `runtimeRoot/engine.lock`. The daemon doctrine correctly records that the
path is repository-local and cannot exclude another checkout on the same machine. The protocol's
fixed host root could replace this with a genuinely machine-global custody object, provided the
one-engine-per-machine rule remains a project invariant rather than becoming optional catalog
cardinality.

### Host and inference memory are different contracts

The host ledger has one claimable pool with toolchain and inference as alternative occupants. A
serialized inference additionally carries resource-indexed requirements and enforcement:

- Linux host memory may use a hard data-segment ceiling for private writable mappings, with reactive
  sampling for shared and pinned memory that the ceiling does not charge.
- Apple host memory is detection-only.
- Device memory is admission, arena sizing, and reactive observation; no supported lane has a kernel
  device-memory ceiling.
- Host and device requirements are different artifact-derived formulas.

A shared-host layer may govern whether one of these occupants can start, but it must not erase the
existing distinction between admission, prevention, detection, and engine conformance.

### One engine process per machine is a correctness rule

Infernix treats one machine as the unit of capacity, model cache, configuration, and engine
serialization. A second engine process can duplicate weights and KV caches and independently admit
against the same observed machine capacity. Consequently, the protocol must not interpret an
additional project admission slot as permission to run another Infernix engine process on the same
machine.

### Cluster lifecycle already has typed ownership and recovery

The project already distinguishes operator and harness ownership, protects cluster mutation with a
rank-2 lifecycle-lock lease, stamps checkout identity into the machine-global Kind slot, persists an
explicit mutating state, and fails closed when teardown evidence is incomplete.

The shared protocol must wrap or compose with that lifecycle. It must not replace project desired
state, infer cluster ownership from generic resource records, or create a second path to destructive
cleanup.

### Pulsar acknowledgement ordering is part of correctness

Inference delivery is at-least-once with an effectively-once observable result. A source message is
acknowledged only after the terminal result is published. Losing a machine mid-inference therefore
causes redelivery rather than an unanswered request.

Resource contention and resource incapacity are different outcomes in this system. Temporary cell
contention must not be translated into a terminal `ModelMemoryLimitExceeded`, while a genuinely
oversized model must not be retried as though a turn were merely busy.

## Findings

### 1. Blocker: no complete rendezvous across supported execution contexts

The protocol requires each client to resolve one fixed local-machine root and says a container, VM,
or WSL guest cannot substitute a guest-local file at the same path. This is correct: a guest-local
lock cannot arbitrate physical host memory with a process running under the host kernel.

Infernix nevertheless has three materially different execution shapes:

- Apple control-plane and Metal execution are host-native.
- Apple-hosted `linux-cpu` work runs in the existing Colima Linux VM.
- Native Linux operator commands run in short-lived `docker compose run --rm` outer containers, and
  there is no supported Linux host-native CLI workflow.

The proposal acknowledges this only by assigning Infernix a “host-native anchor across container
boundaries.” That phrase is the beginning of an adoption design, not its completion.

The Infernix adoption boundary must specify:

- which process is the anchor on Darwin and native Linux;
- how it is installed without undermining the supported stage-zero/bootstrap boundary;
- how a transient outer container discovers and authenticates it without environment variables,
  PATH discovery, arbitrary commands, or caller-selected endpoints;
- which closed operations the container may request;
- how peer identity and the claim-bound nonce work across a VM boundary;
- how host, boot, catalog, and root identities are represented when the requesting process and the
  custody process run under different kernels;
- how the anchor is restarted and how stale custody is recovered after host reboot; and
- whether containerized Linux on Apple is always represented by the Darwin anchor rather than by a
  Linux guest kernel client.

On native Linux, a persistent container could theoretically serve as the project-local anchor and
hold bind-mounted host locks. That would still require a new supported lifecycle, because ordinary
`docker compose up` is not an Infernix operator workflow and current outer containers are ephemeral.

Until this is specified and exercised on the real supported paths, the proposal cannot establish
that all participating Infernix images meet at the same permanent object.

### 2. Blocker: mechanism strength lacks coverage and conjunction semantics

The proposal lists `AdmissionOnly`, `Exclusive`, `Reactive`, `HardCeiling`,
`HardwarePartitioned`, and `BoundedShared`. It says mechanism strength is resource-indexed, but it
does not define the coverage algebra needed when more than one mechanism jointly governs one
resource.

This matters immediately for Infernix. A Linux host-memory execution uses:

~~~text
hard data-segment ceiling over private writable mappings
  + reactive process-group observation over uncovered shared/pinned memory
  + engine readback of the installed ceiling
~~~

Calling that resource simply `HardCeiling` would overstate the coverage. Calling it simply
`Reactive` would discard a real preventive guarantee. Treating the two as alternatives would be
incorrect; both are required for the current Linux contract.

The neutral model needs at least:

- a closed set of charged fields or coverage atoms for each resource family;
- a way to require a conjunction of mechanisms for one resource;
- proof that the union of mechanism coverage satisfies the requirement;
- explicit uncovered residue when the union is intentionally incomplete;
- observer-start and observer-readiness evidence before an execution authority is minted; and
- preservation of mechanism and coverage identities in the resulting authority and receipt.

The generic `EnforcedCellLease` name is also too coarse if it can contain a detection-only resource.
The protocol says assurance profiles join resource-specific mechanisms, but the target API must make
that fact structural. A scalar profile name must not permit a caller to forget that host and device
resources have different strengths or that a Linux ceiling covers only part of host memory.

### 3. High: base-plus-turn acquisition is not yet deadlock-complete

The protocol allows an anchor to retain a base lease while acquiring one or more turns. It also says
all acquisitions use a canonical lock order, begin by taking an admission-slot lock, and forbid live
lock upgrades or unplanned expansion.

Those statements require additional laws to coexist safely.

If the anchor already holds base locks, a turn acquisition can preserve the global order only when
every lock it may add ranks after every retained lock. A catalog-provided total order is not enough;
the catalog verifier must establish this monotonic-extension property for every legal base-plus-turn
combination. Multiple simultaneous turns require the equivalent property between turns.

The admission-slot semantics are also unclear. A base lease retains its slot lock. The next turn
acquisition cannot portably “try the admission-slot lock” again unless:

- a turn has a distinct predeclared slot;
- the existing slot capability authorizes a subordinate turn without reacquiring the kernel object;
  or
- the selected native lock primitive has explicitly standardized same-holder reentrancy semantics.

The third option is particularly risky because POSIX lock families differ in whether locks are
per-process, per-open-file-description, or affected by closing a sibling descriptor. The core must
choose exact primitives and semantics rather than allow an implementation to infer them.

Required core laws include:

- base locks precede every legal subordinate turn lock;
- a child authority cannot acquire a sibling or ancestor cell outside the installed graph;
- a failed turn acquisition releases only its partial turn set, never the retained base set;
- turn-slot and attempt identities cannot create additional base concurrency; and
- recovery can distinguish retained base custody from a failed, running, or quarantined turn.

### 4. High: the Infernix adapter boundary does not map existing authorities or outcomes

The proposal gives Infernix one adoption-table row: retain artifact-derived demand, toolchain
arithmetic, cluster ownership, typed plans, and capped engine launch; make their authorities children
of base or turn leases; use a host-native anchor; and bind exact device identity.

That is insufficient for an implementation plan. At minimum, an Infernix-specific adoption record
must decide the following.

#### Authority composition

- Does the shared-host lease enclose `Lease s ClusterMutationLocked`, or does the lifecycle-lock
  lease enclose shared-host acquisition?
- What lock ranking prevents two code paths from taking those leases in opposite order?
- Which shared capability is required before `ToolchainSpawnAuthority` can be minted?
- Which shared capability is required before `EngineExecutionAuthority` or an `ExecutableModel`
  launch can be consumed?
- Can a project receipt ever substitute for the live runtime observations currently required by plan
  refinement? It must not.

The likely safe shape is an outer shared-host custody region whose child capabilities are consumed by
the existing project-local mints. The shared layer proves custody and resource availability; the
existing project layer continues to prove cluster ownership, model derivation, enforcer readiness,
and closed launch identity.

#### Workload-to-cell mapping

A candidate mapping, requiring design validation, is:

| Infernix concern | Possible protocol representation | Required caution |
|---|---|---|
| Protocol metadata and anchor overhead | Host reserve | Charged once globally, not once per cell |
| Persistent Kind/support-service custody | Base lease with recoverable authority | Generic recovery must invoke Infernix's authenticated inner lifecycle rather than invent desired state |
| Host engine daemon overhead and model cache stock | Base lease | Must retain one-engine-per-machine and persistent storage accounting |
| One inference execution | Turn lease | Must remain subordinate to `ExecutableModel` and resource-indexed enforcement |
| Haskell toolchain invocation | Mutually exclusive turn lease | Must preserve the existing complete claimant arithmetic and live availability observation |
| Whole Metal or CUDA device | Exclusive physical-domain turn | Exact observed device identity, ancestor conflicts, and changed-subject negatives required |
| Retained model/artifact bytes | Storage stock assigned to the project | Compute completion cannot release retained storage capacity |

This mapping must preserve the host ledger's “toolchain and inference are alternative occupants”
rule. The catalog must make them contend on the same logical host-turn cell or otherwise encode an
explicit conflict. Merely checking each demand independently against scalar RAM permits the overlap
the current doctrine rejects.

#### One engine per machine

Protocol admission-slot cardinality is operator policy, but Infernix engine cardinality is not. The
adapter must enforce that exactly one engine base authority can exist for one physical machine,
regardless of how many general-purpose project slots the catalog contains. Additional slots may be
valid for non-engine operations, but cannot authorize another engine process that independently
admits against the same machine.

The new machine-global engine cell could replace the checkout-local `engine.lock`. It must not merely
sit beside it as a second authority with no declared precedence or recovery relationship.

#### Outcome mapping and Pulsar delivery

The protocol needs an explicit mapping into Infernix result semantics:

| Protocol outcome | Infernix meaning |
|---|---|
| `Busy` | Transient scheduling/custody condition; do not publish `ModelMemoryLimitExceeded` |
| `Unsupported` | Startup/refinement refusal or an explicit unavailable placement, depending on whether the unsupported fact is machine-wide or model-local |
| `Quarantined` | Lifecycle uncertainty requiring operator/recovery action; not ordinary model incapacity |
| Requirement exceeds observed cell capacity | Typed request-local capacity failure when specific to a model; machine readiness refusal when the machine can serve none of its placements |
| Runtime mechanism loss | Typed enforcement failure; terminate owned work and do not acknowledge before the terminal result path completes |
| Clean terminal resource receipt | Input to, but not a replacement for, the real Infernix terminal result |

For pool traffic, the acquisition point must be defined relative to Pulsar permits and message
receipt. Safe choices include acquiring a turn before making consumer capacity available, or keeping
an already-delivered message unacknowledged while bounded client policy retries. What is forbidden is
acknowledging because a turn is busy, fabricating a terminal capacity result, or creating an
indefinite redelivery loop for a model that can never fit.

### 5. High: individually durable pages do not define a multi-record transaction

The installed layout contains separate journals for cells, project/slot state, and receipts. Each
journal uses two fixed pages and a highest-valid-generation selection rule. This provides a plausible
single-record torn-write strategy.

The protocol also says:

- the cell current record is the machine-global recovery source;
- project and slot records point to the cell record;
- a matching attempt may attach to a live anchor or retrieve a retained terminal outcome; and
- terminal cleanup writes records before releasing locks.

There is no exact transaction protocol connecting those facts. For example, a crash may occur after
a new cell generation is durable but before its project/slot pointer is updated, or after a terminal
cell state is visible but before the retained receipt is durable. Independent clients need the same
answer to each prefix.

The core specification must define:

- the authoritative record for each decision;
- write and synchronization order for `Prepared`, `Held`, terminal, receipt, and free transitions;
- the fields that link one record generation to another;
- whether a missing, old, or future pointer is repairable or quarantining;
- which locks must be held while repairing each record;
- when a terminal outcome may be returned to a repeated attempt;
- how receipt-window compaction interacts with a still-referenced attempt; and
- complete crash tables for every point between record writes and lock release.

Saying the cell is authoritative is a useful rule, but it is not enough to reconstruct an absent
receipt or authenticate an anchor attachment without a precise derivation and repair procedure.

### 6. High: documentation governance and implementation ownership are misaligned

The repository's documentation standard says governed documents declare target architecture in
prescriptive voice. Schedule, migration sequence, implementation status, and validation evidence
belong in `DEVELOPMENT_PLAN/`.

The protocol is marked `Draft`, which is a permitted metadata value, but it contains:

- proposed seed-period and later owners;
- temporary compatibility ports;
- immediate, enforced, and later recoverable adoption profiles;
- an amoebius ownership-cutover sequence;
- a statement that the repository copies remain proposals until a future release; and
- governance prerequisites and implementation order.

There is no corresponding Infernix phase or sprint in the current development plan. At the same
time, the document is registered in `requiredDocs` and described by the documentation index as the
target five-project topology.

This creates two incompatible readings:

1. If it is exploratory analysis, it belongs under `documents/research/` or outside the governed
   target suite until accepted.
2. If it is accepted target doctrine, its migration and status material belongs in a new development
   plan phase, while the governed document should be rewritten as a declarative protocol and local
   adoption contract.

`./.build/infernix lint docs` currently passes. That confirms metadata and link consistency; it does
not resolve this semantic governance conflict. If the document remains governed, the lint may need a
rule preventing proposal-disposition and staged-cutover sections from becoming an untracked plan.

### 7. Medium: the neutral repository is an operational product boundary even without a daemon

The proposal calls the neutral repository a dependency island rather than another product. That is a
useful statement about dependency direction, but it does not remove the operational surface.

Someone must own and support:

- privileged installation of the fixed root and every permanent object;
- catalog signing and verification keys;
- project enrollment and operating-system principal policy;
- resource-family and mechanism release registries;
- offline catalog and core migrations;
- quarantine inspection and audited clearing;
- saturation and decommission procedures;
- compatibility packages for seed build boundaries; and
- incident response when one participant corrupts or wedges shared state.

Those responsibilities may still belong in a neutral repository, but the first release record must
name packaging, distribution, update authority, rollback protection, and supported-host bootstrap
integration. Infernix should not silently make an external privileged installer a prerequisite while
its own supported bootstrap still claims a smaller host prerequisite set.

### 8. Medium: artifact enrollment needs concrete running-image verification

The proposal correctly rejects pathname, argument vector, and self-reported digest as artifact
identity. It permits either exact artifact digests or a trusted signer/provenance policy.

The release still needs platform-specific procedures for establishing that identity for:

- a host-native development build whose path is stable but bytes change;
- a binary running inside a container image;
- a project-local anchor and a separately built client;
- a self-executed helper image; and
- a dynamically linked executable whose signed or hashed unit must be defined precisely.

This verification must be tied to the process that acquires custody, not merely to a file observed
before launch. Development-signer enrollment is a sensible usability mechanism, but its trusted unit
and revocation behavior must be explicit.

## Strengths worth preserving

The preceding findings do not invalidate the proposal's central idea. Several parts are particularly
well aligned with Infernix.

### Machine-global custody addresses a real gap

The protocol directly improves on repo-local locks and observation-only admission. A common permanent
cell and domain namespace can make participating-project double spending a kernel-enforced exclusion
property rather than a census convention.

### Scope claims are unusually honest

The proposal explicitly excludes hostile administrators, hostile same-identity processes, and
nonparticipating binaries from its guarantee. It distinguishes cooperative exclusion from hard
containment and whole-host authority. That is consistent with Infernix's requirement to state what a
mechanism does not bound.

### Quarantine is the correct default for uncertain persistent effects

Process death releases a kernel lock but proves neither cgroup emptiness nor absence of a VM,
container, mount, service, device context, or delayed provider operation. Treating that state as
quarantined rather than free matches the managed-state-transition doctrine.

### Resource families and mechanisms should remain separate

CUDA memory is a resource; cgroups and device observers are mechanisms. Keeping physical capacity,
aliasing, and conflicts separate from containment/readback avoids a closed platform union and permits
future hardware without rewriting the entire lifecycle.

### Project lifecycle remains project-owned

The outer protocol should provide custody and an enclosing enforcement domain, not attempt to infer
Kind, Pulsar, model-cache, or provider desired state from generic records. The proposal states this
boundary correctly.

### Static finite registries fit the project's closed-world discipline

Private constructors, exact identifiers and digests, no runtime plugin loading, unknown-row refusal,
and closed anchor operations fit the project's prohibition on caller-selected command specifications
and stringly fallback behavior.

### Storage is treated as retained stock

The explicit stock-flow law correctly recognizes that ending compute does not release disk capacity
for retained artifacts or model caches. This is stronger than treating storage as another transient
scalar lease.

## Required design decisions before core freeze

The following decisions are prerequisites to freezing a neutral core release.

### Core protocol decisions

- Fix exact per-platform lock primitives and their ownership, inheritance, close, and crash semantics.
- Define the monotonic lock-ranking law for base-plus-turn acquisition.
- Define admission-slot and attempt semantics for subordinate and multiple turns.
- Specify the complete cross-record write, commit, recovery, and quarantine tables.
- Define catalog anti-rollback and non-ABA epoch behavior.
- Define how overlapping quarantine propagates through aliases and ancestor/child conflicts.
- Define canonical bounded encoding and signature verification vectors.

### Resource and mechanism decisions

- Add mechanism coverage atoms and conjunctive satisfaction.
- Define how a reactive observer becomes live evidence before work begins.
- Preserve distinct host and device quantities and mechanism receipts.
- State how installed physical capacity, currently available capacity, foreign claimants, and static
  reserve interact during admission.
- Specify exact identity and invalidation for unified memory, Metal, CUDA, MIG, and storage domains.

### Infernix adoption decisions

- Define the host-native anchor topology on Darwin and native Linux.
- Define the closed cross-container/VM IPC and authentication path.
- Establish lock order between shared-host custody and the current cluster lifecycle lock.
- Map base and turn cells to cluster, daemon, toolchain, inference, device, and storage lifetimes.
- Preserve one engine process per physical machine independently of general admission-slot count.
- Make shared-host custody a prerequisite of the existing typed toolchain and engine authorities,
  without replacing their project-specific evidence.
- Specify every protocol-outcome-to-Infernix-result mapping.
- Preserve Pulsar acknowledgement-after-terminal-result and redelivery behavior.
- Replace, rather than merely duplicate, the existing repo-local engine lock when the new authority is
  proven.

### Governance decisions

- Decide whether the current document is research or accepted target doctrine.
- Establish the neutral repository, package name, maintainers, release keys, and archive owner.
- Add an Infernix development-plan phase before any implementation or status claim.
- Define dependency pinning and bootstrap availability for the neutral Haskell release.
- Name who owns catalog installation, upgrade, quarantine clearing, and decommissioning.

## Recommended validation sequence

The protocol should be validated in deliberately increasing assurance layers.

### Stage 1: pure kernel model

Implement only bounded identities, canonical encoding, arithmetic, conflict closure, lock ordering,
and dual-page record state machines. Validate:

- overflow and saturation;
- alias closure;
- unknown-family refusal;
- base/turn monotonic ordering;
- changed-brand and region-substitution compile failures; and
- every single-record and cross-record crash prefix.

No project lifecycle or persistent effect should be introduced at this stage.

### Stage 2: one cooperative foreground cell

Use one preinstalled logical host-turn cell for a finite, supervised operation. Prove that:

- two independently built clients contend on the same real object;
- two checkouts cannot both acquire it;
- holder death produces quarantine before reuse;
- malformed or torn state never decodes as free; and
- no workload child inherits protocol handles.

This is the smallest experiment that improves the current Infernix toolchain admission gap.

### Stage 3: real Infernix execution boundaries

Require the cooperative lease as an input to the existing toolchain authority and to one finite engine
execution turn. Preserve all existing plan derivation, live refinement, ceiling installation,
observer, and terminal-result behavior.

Negative tests must prove neither toolchain nor engine launch is reachable from a raw cell receipt,
bare grant, or caller-fabricated observation.

### Stage 4: Apple host and Colima crossing

Run the same source fingerprint through:

- an Apple host-native client/anchor; and
- an Infernix client inside the existing native-arm64 Colima Docker daemon.

Prove both operations contend on one physical-host cell, authenticate across the boundary, and retain
the correct host/guest identities without treating a guest boot id or guest-local root as the host
object. This stage is the decisive test of the proposed Infernix anchor architecture.

### Stage 5: native Linux transient-container crossing

Prove two independent `docker compose run --rm` clients and, if required, a persistent project-local
anchor meet at the same host objects without adding a supported `docker compose up` operator path or
depending on a repository-local mount.

### Stage 6: enforced resource profiles

Add Linux CPU/RAM containment and Infernix's layered host-memory mechanism. Validate the precise
charged-field coverage and observer residue rather than awarding a scalar “hard” label.

Add Metal and whole CUDA device exclusion only after exact physical identity and changed-subject
negative tests pass on the owning hardware.

### Stage 7: recoverable persistent base

Only after finite custody is closed should the protocol own a persistent Infernix base lease. Add the
authenticated anchor, recoverable records, delayed-effect fencing, reboot reconciliation, bounded
receipts, and inner Infernix cluster recovery.

The recovery tests must prove that the generic layer never destroys an operator-owned cluster,
invents desired state, acknowledges unfinished inference, or clears quarantine from absence inferred
only from process death.

### Stage 8: cross-project evidence

Finally, test exact released artifacts from at least two independent project islands against the same
host root and catalog. Byte-identical prose or two builds of one adapter is not cross-project
conformance.

## Suggested acceptance criteria for Infernix adoption

Infernix should not adopt the neutral release until all of the following are true:

- A real neutral repository and signed release exist.
- The host catalog and permanent objects are installed through an owned, documented procedure.
- The Darwin/Colima and native-Linux container paths have live contention evidence.
- The mechanism algebra represents partial hard coverage plus reactive residue without relabelling.
- Base-plus-turn lock ordering is mechanically verified.
- Cross-record crash tables are normative and pass adversarial tests.
- The Infernix adapter preserves one engine per machine.
- Existing `ExecutableModel`, memory-grant/enforcer, and cluster-ownership constructors remain the
  only mints for their project-specific authorities.
- Busy, unsupported, capacity failure, enforcement loss, quarantine, and terminal success remain
  distinct outcomes.
- Pulsar acknowledgement still occurs only after a terminal result.
- The checkout-local engine lock and observation-only toolchain exclusion have a deliberate cutover
  or compatibility story rather than silently coexisting with contradictory authority.
- Development-plan status and validation receipts describe the adoption honestly.

## Conclusion

The protocol identifies the correct class of problem: Infernix cannot coordinate a physical host
with other projects using repository-local locks, Kubernetes declarations, VM pledges, or
instantaneous availability observations alone. A neutral daemonless custody kernel could provide a
valuable missing layer.

The current draft is best treated as an architectural research proposal. Its strongest ideas—fixed
machine-global objects, finite cells, resource/domain identity, progressive assurance, project-local
anchors, and crash quarantine—should be retained. Its core should not be frozen until the host/VM
rendezvous, mechanism-coverage algebra, nested turn ordering, multi-record transaction, and concrete
Infernix adapter are specified and validated.

The first implementation should be intentionally small: one cooperative host-turn cell, two
independently built participants, and real contention across the Apple host/Colima boundary. If that
cannot be made reliable without introducing a hidden host service, repository-local fallback, or
weaker identity claim, the larger protocol should be reconsidered before its complexity becomes a
shared dependency.
