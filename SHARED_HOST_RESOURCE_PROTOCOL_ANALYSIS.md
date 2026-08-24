# Shared Host Resource Protocol Analysis

**Status**: Non-authoritative analysis
**Analyzes**: [documents/engineering/shared_host_resource_protocol.md](documents/engineering/shared_host_resource_protocol.md)
**Canonical homes**: [documents/README.md](documents/README.md), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

> **Purpose**: Record a constructive review of the proposed Finite Resource Execution Authority
> Protocol, identify questions that must be resolved before implementation, and propose an
> Infernix-specific implementation and migration plan.

This file is a review artifact, not a second architecture specification. The protocol document and
the governed `documents/` suite own target architecture. `DEVELOPMENT_PLAN/` owns implementation
status and validation receipts. Nothing in this analysis confers protocol conformance or reports
that the proposed implementation exists.

## Executive Summary

The proposal has a sound central idea: independently implemented projects should coordinate finite
host resources through one semantic ABI, one immutable host catalog, kernel-backed lifetime locks,
durable recovery records, applied/read-back resource walls, and an execution capability that cannot
be constructed before those facts agree.

This is a good fit for Infernix because it supplies the machine-global layer its existing controls
deliberately lack. Infernix already has strong inner boundaries:

- model requirements are derived from model artifacts and execution shape;
- host, pod, and NVIDIA resources are kept distinct in the types;
- the engine launch boundary requires admitted grants and matching enforcers;
- toolchain concurrency and Haskell heap use are derived and bounded;
- cluster mutation and teardown consume typed ownership evidence;
- bounded subprocess creation, activity publication, cleanup, and recovery are closed behind
  internal interpreters; and
- repository-local locks serialize several state transitions.

Those controls do not arbitrate with another checkout or another participating project. The
protocol can provide that outer authority without weakening them. Existing Infernix grants, locks,
and launch capabilities should become children of one held host cell rather than being replaced by
flat protocol quantities.

The proposal is not sufficiently frozen to implement safely yet. The most important blockers are:

1. the text relies on per-cell lifetime ownership but does not define a permanent cell lock or a
   `CellLockKey` capability;
2. the exact POSIX lock ABI cannot be implemented through Infernix's current `filelock` API;
3. the proposed POSIX directory permissions permit replacement of supposedly permanent lock
   objects;
4. the persistent anchor and guest/container delegation protocols are not specified precisely;
5. a clean clone cannot acquire a lease through an Infernix binary that has not been built yet;
6. the Linux outer-container workflow cannot retain a Darwin host lease after an ephemeral launcher
   container exits;
7. eternal spent-key tombstones create an unbounded metadata obligation;
8. the canonical encoding, lock corpus, ABI upgrade procedure, and cross-repository ownership of
   conformance vectors need an explicit release process; and
9. several guarantee statements are stronger than the `AdmissionOnly`, `DetectionOnly`, or
   `Reactive` mechanisms later permitted by the proposal.

The recommended migration is therefore:

```text
freeze and correct the semantic ABI
  -> implement pure layout and workload laws
  -> implement exact locks, journals, and recovery
  -> implement a persistent same-binary Infernix anchor
  -> derive complete Infernix workload envelopes
  -> make toolchain, cluster, and engine controls children of the host lease
  -> validate Apple and CUDA in separate plan phases
  -> perform one fail-closed production cutover
```

## What Makes Sense for Infernix

### One outer authority, stronger inner authorities

The proposal correctly avoids treating cross-project standardization as a reason to remove
project-specific types. Infernix should keep ownership of:

- artifact parsing and model requirement derivation;
- the typed execution plan and placement refinement boundary;
- toolchain claimant arithmetic and closed invocation vocabulary;
- cluster owner, checkout identity, reservation, mutation, and teardown evidence;
- model-cache and engine-artifact transaction protocols;
- per-resource enforcers and their strength declarations; and
- the capped engine and bounded subprocess launch kernels.

The host protocol should answer only the outer questions:

- Which immutable cell may this Infernix workload use?
- Does the complete workload fit that cell?
- Are the parent, cell, and physical-domain locks held for the whole lifetime?
- Were required walls applied to the exact domains and read back?
- Can a closed Infernix child authority be minted from that lease?
- Did cleanup and durable retirement finish before the locks were released?

### Static partitioning rather than optimistic free-memory races

The immutable cell catalog is stronger than Infernix's current toolchain admission observation.
Today, available-memory observation plus a foreign-toolchain census is an observation at an instant,
not a cross-process reservation. Static cells and lifetime locks make cooperating projects unable to
admit the same reserved capacity independently.

Live observations remain necessary. Static fit cannot prove that an ungoverned process, foreign
container, stale cgroup, retained VM, or unreconciled device effect is absent. The proposal is right
to require observation before lock acquisition and re-observation after the complete lock bundle is
held.

### Parent scope separate from retry identity

The distinction between `ParentScopeId` and `ClaimKey` is important. A retry identifier must not be
able to create a new schedulable slot. A finite catalog-registered parent scope gives the operator a
reviewable upper bound on independent Infernix reservations, while a claim key supplies idempotency
inside that scope.

For Infernix, one default parent scope per physical host is the strongest and simplest target. A
toolchain run, operator platform, harness run, or engine-only daemon is a workload/claim under that
scope, not a new scope. Any additional independently reserving scope should require a demonstrated
need and catalog arithmetic that charges its possible concurrency.

### Persistent anchors for persistent effects

The proposal correctly rejects borrowing an invoking CLI's lifetime for a Kind cluster, engine
daemon, VM, or other persistent effect. `cluster up` returns while Docker containers remain live,
so the resource locks must remain held by a project-owned anchor whose identity is recorded with the
cluster and enforcement domains.

This is especially important for the Linux outer-container workflow. The current launcher is an
ephemeral `docker compose run --rm` container and mounts only `./.data` plus the Docker socket. It
cannot retain a host-global lease after exit, and on Apple it runs in a Linux VM whose kernel locks
cannot arbitrate Darwin lock objects. A host-side anchor is therefore an architectural requirement,
not an implementation detail.

### Resource-specific mechanisms and honest strength

The protocol's separation between resource capacity, lock domain, wall mechanism, and strength is
compatible with Infernix's existing doctrine:

- a Linux cgroup can prevent some host-memory growth;
- a sampled resident-set observer covers only the quantity it actually observes;
- Apple host-memory enforcement is reactive/detection-oriented rather than a hard kernel ceiling;
- no current Infernix lane has a kernel device-memory ceiling;
- whole-device CUDA exclusivity is a lock and exposure rule, not a byte ceiling; and
- MIG or MPS must not be described as equivalent to whole-device exclusivity.

The protocol should preserve those distinctions in the authority type and terminal receipt.

## Concerns That Must Be Resolved

### 1. A cell lock is described but not defined

The proposal says that per-cell locks carry lifetime ownership, but the coordination-root inventory
defines only:

- `epoch.lock`;
- `admission.lock`;
- parent-scope locks; and
- physical-resource locks.

The capability sketch similarly defines `ParentLockKey` and physical `LockKey`, but no
`CellLockKey`. This is not only a naming omission. Two allowlisted projects can contend for a
logical serialized cell whose CPU/RAM quantities do not correspond to an exclusive physical leaf.
Without a cell lock, both could acquire shared physical ancestors and separately treat the scalar
capacity as theirs.

Recommended resolution:

- add immutable `locks/cells/<digest>.lock` objects;
- add `CellLockKey host boot epoch cell` with nominal roles;
- derive it only from a validated catalog cell;
- acquire it exclusively during the admission join;
- hold it until the record is retired and cleanup is proven; and
- include it in the canonical lock order between the parent lock and physical-domain locks, or
  explicitly define another globally consistent position.

### 2. The current Haskell lock dependency cannot implement the ABI

`Infernix.Cluster.LifecycleLock` uses `System.FileLock.tryLockFile`, which accepts a path, may create
the file, and returns an opaque token. The proposal requires:

- opening an existing permanent object relative to a verified directory descriptor;
- `O_NOFOLLOW` and `O_CLOEXEC`;
- read/write access;
- file and filesystem identity checks before and after acquisition;
- BSD `flock` on that exact descriptor;
- noninheritance by children; and
- one explicit unlock/close transition.

The public `unix` `setLock` API uses the `fcntl` record-lock namespace, which the proposal explicitly
forbids for protocol locks. Infernix also forbids repo-owned FFI and native implementation source, so
it cannot bridge this gap locally.

Recommended resolution: select and pin a reviewed upstream Haskell package exposing the exact
descriptor-aware BSD `flock` operations, or change the protocol ABI. Do not implement the protocol
through the current `filelock` path API and claim equivalence.

### 3. POSIX permissions contradict permanent lock identity

The proposed root mode is `0770` with a shared participant group. Directory write permission allows
a participant to unlink or replace entries even when the regular files are `0660`. That undermines
the permanent-inode invariant and can split old and new binaries into separate lock namespaces.

Recommended resolution:

- keep the coordination root, catalog, and lock directories installer-owned and nonreplaceable by
  ordinary participants;
- give participants open/read/write access to existing lock files without directory replacement
  authority;
- give each project a separately protected allocation directory for its journal records;
- define exact owner, group, ACL, mode, and mutation authority for every directory class; and
- require privileged/offline catalog mutation for additions to the immutable lock set.

### 4. The persistent anchor protocol is underspecified

The document says an anchor starts first, acquires its own locks, owns effects, and survives the
invoking CLI. It does not freeze:

- how the initial CLI starts or discovers it;
- how a retry authenticates to it;
- the transport and canonical message framing;
- how request identity is bound to `ProjectId`, parent, claim, epoch, and lease nonce;
- how status, child execution, teardown, and receipt retrieval are authorized;
- what happens if the client dies during a request;
- how the anchor proves it is the process recorded in durable state;
- how a replaced socket or endpoint is rejected;
- how a container or VM reaches a host anchor without treating a guest-local endpoint as authority;
- how output and errors are bounded; and
- which process owns reconciliation after anchor death.

This must be part of the semantic ABI. Infernix can reuse design principles from its bounded
subprocess framed protocol, but the persistent anchor is a different lifetime and needs its own
closed state machine and crash schedule.

### 5. Clean-clone bootstrap is circular

The proposal requires the outer cell before toolchain work. A clean checkout has no current
Infernix binary with which to acquire the cell. The Apple seed build and Linux launcher-image build
therefore cannot be made self-governing merely by refactoring the new binary.

There are two coherent choices:

1. require a preinstalled conforming launcher, such as a prior Infernix release, before any source
   build; or
2. declare the first seed build an explicit stage-zero exception outside the cross-project
   guarantee, keep it single-worker and operator-quiesced, and require all post-seed toolchain work
   to use the protocol.

The second choice preserves Infernix's supported clean-clone posture and is the recommended one.
The documentation must not describe that seed as protocol-bounded.

### 6. Linux outer-container delegation changes the operator workflow

On native Linux, a separate persistent anchor container or host-native Infernix process could hold
the host lock objects while ephemeral command containers run. On Apple, a lock taken inside Colima
is a Linux-VM lock and cannot arbitrate the Darwin host root. The Apple host-native Infernix binary
must hold the Darwin lease and launch or authorize the Linux outer command.

Consequences:

- direct `docker compose run --rm infernix infernix ...` cannot remain a supported bypass;
- the bootstrap scripts need to ensure a host-native Infernix authority process exists after the
  seed build;
- `compose.yaml` becomes an internal child-launch detail rather than an independent operator
  authority surface;
- long-lived Kind state must be bound to the host anchor's durable claim;
- status and down commands must attach to that anchor; and
- the current “only `./.data` plus Docker socket” mount contract must be revised deliberately,
  without pretending a mounted lock pathname across a VM is the same kernel object.

### 7. Colima and VM accounting need a precise model

The proposal allows VM realization and guest delegation but does not make the shared-Colima case
concrete. The active Colima pledge is host RAM committed to a Linux VM, while several projects may
currently use the same daemon.

Questions that require one answer:

- Is the whole Colima VM a serialized physical domain granted to one project at a time?
- Is the complete Colima pledge part of the Darwin host reserve while nested Linux cells arbitrate
  only inside it?
- Can one host cell span host-native Apple engine memory and an existing VM domain without double
  charging the VM pledge?
- What live evidence proves that no foreign container in the VM is consuming a cell before
  Infernix starts?
- Who owns cleanup if a Darwin anchor survives but the VM reboots or changes identity?

The conservative Infernix choice is to serialize use of the existing Colima VM as an exact domain
for governed platform operations. More concurrent sharing requires a formally nested host/guest
catalog and must not be inferred from container cgroups alone.

### 8. Receipt and tombstone storage is not bounded

The document requires old claim keys never to become new and says terminal detail may compact to a
spent-key tombstone. Random durable keys plus unlimited intentional reruns require unbounded
tombstone growth.

Recommended resolution: use a bounded per-parent logical attempt sequence with a durable
high-water mark and explicit retry identity, or impose a finite per-epoch claim budget that requires
offline epoch rotation after all effects are reconciled. Storage accounting alone does not turn an
unbounded set into a finite protocol.

### 9. Layout policy is executable even though Markdown is not

The proposal correctly says its Markdown is not executable policy. `layout.cbor`, however, decides
project allowlists, capacities, mechanism strengths, domain identities, and parent registrations.
It is executable host policy state even if it is not a repository configuration file.

For Infernix:

- it should not be copied into `infernix.dhall` or `infernix-host.dhall`;
- the fixed coordination root should not become an operator-editable `HostConfig` field;
- runtime must validate the installed canonical layout rather than synthesize a fallback;
- an installer or privileged mutation command owns creation and catalog change;
- ordinary commands should provide read-only status and typed refusal diagnostics; and
- the docs should distinguish shared host policy from Infernix's generated system and machine
  contracts.

### 10. The interoperability release process is missing

The proposal lists what the ABI includes but not who releases a revision or how four independent
repositories agree that the bytes are frozen.

The release process should define:

- one canonical vector corpus and immutable release digest;
- how each repository vendors and independently implements it without importing code;
- review requirements for a new version;
- the exact flag-day order for catalog upgrade;
- behavior while old and new binaries share the permanent epoch object;
- how all parent effects are proven absent before mutation;
- how failed mutation rolls back or quarantines; and
- which cross-project live matrix is required before the conformance label is used.

Permissive compatible-version ranges would weaken the central invariant and should remain
forbidden.

### 11. Guarantee language needs resource-specific qualification

The TL;DR says work launches only after every required wall is applied and read back, while later
sections permit admission-only and reactive mechanisms. A lock can supply exclusivity, and a
sampler can supply detection, but neither is a hard scalar wall.

Recommended resolution: define launchability per resource as satisfaction of the exact requested
mechanism strength. A request for `Hard` refuses on a reactive Apple profile; a request that accepts
`Reactive` may launch but receives only that claim. “Finite authority” should never be summarized as
“hard bound” across all lanes.

### 12. Complete Infernix demand is broader than model memory

The proposal says the requirement is complete, but the Infernix adoption paragraph emphasizes its
existing memory grants. A complete Infernix workload also includes:

- the Cabal driver, compiler workers, native helpers, link, and test processes;
- Poetry and Python environment provisioning;
- npm dependency installation, PureScript build, unit tests, and Playwright;
- launcher and engine image construction;
- Kind or nvkind control-plane and worker containers;
- platform-service pod limits and persistent volume sizes;
- local registry and image retention;
- model-cache quota and eager staging;
- host coordinator, webapp, and engine daemon baselines;
- one serialized inference peak per engine machine;
- recovery, snapshot, cleanup, and evidence-retention stages; and
- Docker/Colima or native container-runtime overhead that belongs to the selected domain rather
  than the general host reserve.

The requirement must be derived from a closed phase DAG. Adding today's maximum figures by hand
would recreate the drift the protocol is intended to eliminate.

## Ambiguities and Questions

The following points should receive normative answers before the ABI is considered frozen.

### Catalog and identity

- Is a cell itself always lockable, and exactly where is its lock in canonical order?
- Are cell names semantic identities or display labels derived from canonical cell bytes?
- Can a catalog contain cells for projects unknown to an older binary if that binary never selects
  them, or must every participant understand every cell/profile tag?
- Is one `ProjectId` assigned forever, and what authority allocates new project identifiers?
- How are parent scopes named without allowing user configuration to manufacture concurrency?
- Which layout fields participate in the epoch digest and which are nonsemantic metadata?
- Are retired lock objects retained forever even after a coordination-root migration?

### Admission and lock ordering

- Is the parent lock retained during a bounded contention refusal, or immediately released?
- Does cell selection occur before or after the cell lock is attempted?
- May the interpreter try several admitted alternative cells while holding `admission.lock`, and
  what deterministic order applies?
- Which observations are repeated after the entire bundle is held?
- What exact evidence distinguishes an unlocked clean domain from an unlocked stale effect?
- How are partial resource-lock acquisitions rolled back if observation or wall creation fails?

### Workload and child authority

- What is the exact distinction between `Scope`, `ParentScopeId`, workload brand, and claim?
- Can one persistent parent execute an unbounded sequence of checked sequential children, or is the
  sequence itself finite and pre-derived?
- How is a child split durably accounted so an anchor restart cannot mint it twice?
- Do child authorities have terminal receipts, and how are their peaks folded into the parent
  receipt?
- Can a failed child be retried inside the same parent claim, and what identifies that retry?

### Enforcement

- Does upward rounding mean any effective wall greater than requested is a refusal even when it
  remains below offered cell capacity?
- Which fields distinguish requested, offered, applied, and effective rounded quantities?
- What is the exact Apple CPU/RAM reactive policy and terminal outcome?
- Which storage mechanisms are supported on APFS and on ext4/XFS, and what is the refusal when a
  project directory cannot receive an enforceable quota?
- Is CPU represented as cpuset identity, quota/period, weight, or a typed combination?
- How are page cache, shared mappings, pinned host mappings, kernel memory, and device-driver
  overhead assigned between the cell and host reserve?

### Accelerator identity

- Is Infernix required to decode MIG/MPS cells before it advertises those mechanisms?
- How is a granted CUDA UUID forced through Docker, Kind/nvkind, the NVIDIA device plugin, the
  execution plan, and the adapter process without an arbitrary selector appearing later?
- Is a Compute Instance identity observational metadata only, or part of the execution authority?
- What event invalidates an MPS service identity and forces a new epoch?
- How is Apple Metal device identity stabilized across the boot while unified memory aliases host
  RAM?

### Anchor, recovery, and operations

- What endpoint does an anchor expose, and how is endpoint replacement detected?
- Can an operator inspect an anchor without possessing a mutable execution capability?
- What is the bounded procedure for stopping an anchor whose workload is already absent?
- Who may clear quarantine, and what evidence must that command consume?
- How are host reboot, VM reboot, Docker daemon restart, and Kind cluster recreation distinguished?
- What state is safe for read-only `status` when layout or journal decoding fails?

### Scope of conformance

- Does an Infernix implementation need Windows code despite Infernix having no supported Windows
  lane, or may it advertise only Darwin/Linux rows?
- Does conformance require every optional profile, or only the rows a project advertises?
- Is `ParticipatingProjects` the default Infernix claim while `WholeHost` is unavailable on an open
  development workstation?
- Must all four named projects pass every pairwise live test before any one calls itself conformant?

## Recommended Infernix Decisions

Unless the frozen ABI decides otherwise, the Infernix adapter should make these conservative
choices:

1. Implement Darwin and Linux only. Do not introduce a Windows product lane as part of this work.
2. Advertise `ParticipatingProjects`; advertise `WholeHost` only if a later closed-world observer can
   prove every material claimant is contained.
3. Register one default Infernix parent scope per host. Treat additional scopes as an explicit
   operator-reviewed weakening.
4. Use one persistent operator-platform claim for the cluster plus engine peak on a shared host.
5. Refuse toolchain work while that platform claim is live unless a future catalog explicitly
   admits and charges independent concurrency.
6. Keep all current Infernix inner capabilities and require them to descend from a host-cell child
   authority.
7. Support whole-device CUDA exclusivity first. Decode but do not advertise MIG or MPS launchability
   until Infernix implements exact binding and live validation for those rows.
8. Treat Apple GPU working memory as an alias of host unified memory, never as an independent byte
   pool.
9. Treat the first clean-clone seed build as an explicit exception; govern every post-seed command.
10. Make Linux operator commands pass through a host-side Infernix launcher/anchor. Remove direct
    Compose invocation from the supported surface at cutover.
11. Keep layout installation external to ordinary Infernix initialization. `infernix init` continues
    to generate only the Infernix system and machine contracts.
12. Make production cutover atomic and fail closed. Never silently fall back to the legacy
    process-local admission path when the coordination root is missing or incompatible.

## Target Infernix Authority Structure

```text
Observed physical host and immutable layout
  |
  +-- RegisteredParent infernix.default
        |
        +-- one active ClaimKey
              |
              +-- selected and locked Cell
              |     +-- RAM / CPU / storage quantities
              |     +-- exact volume and VM/container domains
              |     +-- exact Metal or CUDA domain when required
              |
              +-- persistent Infernix anchor
                    |
                    +-- toolchain/test child
                    |     +-- BuildMemoryPlan
                    |     +-- ToolchainSpawnAuthority
                    |     +-- closed Cabal/npm/Poetry/browser vocabulary
                    |
                    +-- cluster child
                    |     +-- ClusterMutationLocked lease
                    |     +-- owner and checkout evidence
                    |     +-- Kind/nvkind and persistent-state identities
                    |
                    +-- engine child
                          +-- artifact-derived resource requirements
                          +-- MemoryGrant resource
                          +-- matching enforcer and effective wall
                          +-- EngineExecutionAuthority
                          +-- capped closed launcher
```

The default parent scope serializes top-level Infernix workloads on one machine. Parallelism inside
the workload is admitted through checked child splits from the one parent grant. It does not create
additional host locks or independently select cells.

### Workload variants

The same parent scope can admit different closed workload shapes:

- **Standalone toolchain**: one closed build/lint/test invocation and all descendants.
- **Full harness**: prerequisite preparation, toolchain phases, harness configuration transaction,
  temporary cluster, routed validation, teardown, recovery, and retained evidence.
- **Operator platform**: persistent cluster baseline plus the maximum valid concurrent host-engine
  transient on Apple, or cluster-resident engine baseline/peak on native Linux.
- **Engine-only machine**: daemon baseline, model-cache baseline, one serialized artifact-derived
  inference peak, cleanup, and receipt publication.

The claim key identifies the durable logical attempt; it does not encode resource quantities or a
cell choice.

## Implementation Plan

The implementation should follow repository plan governance rather than landing as an untracked
cross-cutting refactor. The exact sprint numbering belongs in `DEVELOPMENT_PLAN/`; the following is
the recommended execution order.

### 0. Close existing memory-validation work

Before changing admission boundaries:

- finish the existing device-backstop correction;
- close the recorded Apple and CUDA cohort gates against their frozen code states; and
- preserve those receipts as evidence for the inner mechanisms that the outer protocol will reuse.

This avoids combining an unresolved device-accounting defect with a new host-global authority.

### 1. Govern and freeze the target

Add a documentation-and-governance sprint that:

- resolves the blockers in this analysis;
- changes the protocol from a draft only when its semantic ABI is genuinely frozen;
- defines the canonical vector location and digest release procedure;
- states the stage-zero bootstrap exception;
- states the supported Infernix profile rows;
- adds execution-ordered implementation phases to `DEVELOPMENT_PLAN/`;
- updates `system-components.md` and the removal ledger; and
- passes `infernix lint docs` and `infernix lint plan`.

No runtime adapter should be declared active before this governance work closes.

### 2. Implement the pure semantic ABI

Add project-owned modules for:

- protocol constants and semantic ABI digest;
- bounded base-unit quantities and checked arithmetic;
- project, parent, claim, host, boot, epoch, domain, cell, resource, mechanism, and strength types;
- canonical deterministic CBOR encode/decode;
- observed-host refinement and unsupported-capability refusal;
- layout graph validation, alias closure, reserve inequality, and cell allowlists;
- sequential maximum, concurrent sum, replica multiplication, persistent-plus-transient
  composition, and child splits; and
- Infernix project/scope witnesses and raw refusal diagnostics.

Suggested internal shape:

```text
src/Infernix/ResourceAuthority.hs
src/Infernix/ResourceAuthority/ABI.hs
src/Infernix/ResourceAuthority/Arithmetic.hs
src/Infernix/ResourceAuthority/Types/Internal.hs
src/Infernix/ResourceAuthority/Layout/Internal.hs
src/Infernix/ResourceAuthority/Observation/Internal.hs
src/Infernix/ResourceAuthority/InfernixWorkload.hs
```

Only the narrow Infernix facade should be exposed. Constructors, existential backend wrappers,
raw layout proofs, and project identity constructors remain internal.

Exit gates:

- canonical golden vectors;
- every single-dimension and integer-overflow refusal;
- unified-memory aliasing laws;
- parent/child and whole-GPU/MIG conflict laws;
- unknown capability and stale-identity refusals; and
- compile-fail fixtures for construction, coercion, relabeling, and brand substitution.

### 3. Implement the POSIX lock and durable-state kernel

After the descriptor-aware upstream lock dependency is selected:

- validate the fixed coordination root and local filesystem;
- open permanent root, epoch, parent, cell, admission, ancestor, and leaf objects without following
  links;
- verify identities before and after nonblocking lock acquisition;
- keep a private registry keyed by observed file identity;
- reject duplicate or reentrant acquisition;
- enforce one canonical lock order and all-or-nothing rollback;
- implement `Prepared -> Applied -> Running -> Releasing -> Retired` records;
- implement `Recovering` and `Quarantined` outcomes;
- synchronize file contents, atomic replacement, and containing directories; and
- bind every record to boot, process-birth, namespace, substrate, and enforcement-domain identity.

The protocol lock backend must be separate from existing repo-local locks. Those locks may continue
to use their appropriate internal package while the host ABI uses the exact frozen backend.

Exit gates:

- two independent processes contend on the exact same object;
- symlink, replacement, remote filesystem, wrong owner/mode, and wrong file identity refuse;
- partial acquisition releases the exact acquired subset;
- a killed holder releases kernel locks but does not make stale effects reusable;
- every durable crash point either recovers or quarantines; and
- a catalog mutation cannot proceed while a shared epoch lease is live.

### 4. Implement the persistent anchor and closed program

Add a same-binary internal anchor mode and a bounded protocol supporting:

- start and durable publication;
- authenticate/attach by project, parent, claim, generation, epoch, and nonce;
- child execution requests drawn from a closed Infernix vocabulary;
- read-only status;
- orderly teardown;
- terminal receipt retrieval;
- client disconnect and retry;
- anchor death and recovery; and
- bounded messages, output, retries, timeouts, and cleanup.

The effect layer should follow the proposal's rank-2/linear shape:

```text
Lease
  -> applied and read-back envelope
  -> ExecutionAuthority
  -> closed child program
  -> RunningAuthority
  -> terminal ResourceReceipt
```

There should be no unrestricted `LiftIO`, raw command callback, caller-supplied executable, or
caller-selected container/VM/device arguments in this program.

For Linux outer commands:

- Apple bootstrap invokes the host-native Infernix authority wrapper after the seed binary exists;
- native Linux uses a host-native process or persistent anchor container that sees the exact host
  coordination objects;
- the anchor launches the ephemeral outer command as a governed child;
- `cluster up` leaves the anchor alive after the command container exits; and
- subsequent status/down requests attach to that same claim.

### 5. Derive complete Infernix workload requirements

Create one `InfernixWorkload` calculus whose inputs are existing closed configuration and generated
plans rather than new authored memory fields.

Toolchain derivation should consume:

- `BuildMemoryPlan` worker/control arithmetic;
- fixed phase concurrency for compile, link, test, npm, Poetry, browser, image build, and cleanup;
- storage requirements for build products, language dependencies, images, temporary files, and
  retained evidence; and
- CPU requirements and the exact mechanism strength each lane supplies.

Cluster derivation should consume:

- binary-rendered Kubernetes requests and limits;
- persistent claim sizes;
- Kind/nvkind node/container topology;
- registry and image retention bounds;
- model-cache quota;
- Colima pledge or native host container-domain facts; and
- recovery and snapshot stages.

Engine derivation should consume:

- the existing artifact-derived host/device requirement;
- daemon and cache baseline;
- exactly one serialized inference transient per engine machine;
- adapter arena rounding;
- sampler overshoot/headroom already declared by Infernix; and
- the exact granted Metal/CUDA identity.

The complete platform formula is conceptually:

```text
persistent cluster/daemon/cache baseline
  + maximum dependency-valid concurrent transient
```

It must not be implemented as one hand-authored scalar.

### 6. Make toolchain authority a child of the host cell

Refactor `Infernix.BuildMemory` so:

- `ToolchainSpawnAuthority` can be minted only from a matching host-cell child authority;
- its current heap, concurrency, settings-readback, single-flight, sampling, and cleanup behavior is
  retained;
- live available-memory and foreign-claimant observations move under the before/after-lock protocol
  admission checks;
- the old process-local observation is no longer described as machine-global exclusion; and
- every Cabal, npm, Poetry, Python provisioning, browser, and relevant image-build launch is inside
  the closed parent workload.

The first seed build remains outside this authority by explicit doctrine. All focused and full
validation after the seed uses it.

### 7. Make cluster lifecycle a child of a persistent platform claim

Refactor cluster entrypoints so:

- `cluster up` obtains or authenticates the parent claim before any Docker, Kind, chart, retained
  state, or config mutation;
- the host anchor retains the lease while the cluster exists;
- the existing `Lease s ClusterMutationLocked` and ownership/teardown evidence become inner child
  capabilities;
- cluster state records the outer claim and exact anchored substrate identities;
- `cluster status` can inspect the claim without mutating it;
- `cluster down` attaches to the live anchor, proves cluster effects empty, retires the record, then
  releases locks; and
- harness seizure/recovery cannot bypass parent-scope contention.

Repo-local lifecycle, materialization, Python, cache, and transaction locks remain useful for
intra-project state. They are not counted as host-resource locks.

### 8. Make engine execution a child of the same host claim

Refactor runtime refinement so:

- model requirements remain derived on the executing machine from real artifact bytes;
- each resource grant is proven to fit a child split of the held cell;
- the enforcer is selected from the exact granted resource and mechanism profile;
- applied limits and device identities are read back before `ExecutionAuthority` is minted;
- `EngineExecutionAuthority` remains the single serialized consumer of one refined runtime plan;
- only the capped closed launcher consumes the final child authority; and
- terminal resource/peak evidence is folded into the parent receipt.

On Apple, the operator-platform claim includes both the Colima/cluster baseline and host-engine peak,
with Metal working memory aliased to host RAM. On an engine-only machine, the claim contains only
that machine's daemon/cache baseline plus one inference peak.

The current repo-local `engine.lock` becomes redundant once the parent anchor and closed engine
child vocabulary prevent a second engine role on the host. Its removal should be tracked in
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` until the stronger path is validated.

### 9. Bind Linux GPU execution to the granted identity

The first Infernix CUDA profile should use whole-device exclusivity:

- observe the canonical CUDA GPU UUID on the host;
- acquire the whole-device domain lock;
- expose only that device to the governed launcher/Kind node;
- carry the UUID through the refined execution plan;
- verify the adapter and NVIDIA sampler observe the same UUID;
- retain current host-memory and device-memory admission as child quantities;
- retain the device sampler as a backstop, not a kernel ceiling; and
- refuse if Docker, Kind, the device plugin, or the adapter can see a different or broader device
  set than the lease grants.

MIG and MPS should be separate follow-on profiles, not compatibility aliases. Infernix advertises no
strength row it has not validated live.

### 10. Perform an atomic production cutover

During implementation, the new adapter may be exercised through closed unit, conformance, crash,
and live validation components. Ordinary production commands should not dynamically mix legacy and
new authority.

At cutover:

- every governed toolchain, cluster, engine, container, and accelerator entrypoint requires the
  host protocol;
- missing root, incompatible ABI, stale epoch, ambiguous identity, weak mechanism, contention, or
  quarantine refuses before mutation or spawn;
- direct Compose operator commands are removed from supported documentation and bootstrap flows;
- no environment or Dhall flag enables an unsafe fallback;
- lints reject raw host-resource lock acquisition and top-level launch outside the new interpreter;
- obsolete top-level admission and redundant engine-lock surfaces are removed through the cleanup
  ledger; and
- the target docs describe only the resulting supported architecture.

## Repository Change Map

### New implementation areas

- `src/Infernix/ResourceAuthority.hs` — narrow Infernix-facing facade.
- `src/Infernix/ResourceAuthority/*` — ABI, layout, observation, lock, journal, recovery, anchor,
  program, substrate profile, and workload internals.
- `test/resource-authority/` — pure laws, canonical vectors, live POSIX locks, crash schedules, and
  recovery tests.
- `test/compile-fail/` — authority construction, coercion, escape, reuse, phase-skip, and raw-launch
  negatives.
- `src/Infernix/Lint/HaskellStyle.hs` — ownership scans for the new lock, anchor, and child-launch
  kernels.

### Existing areas to refactor

- `src/Infernix/BuildMemory.hs` — child toolchain authority rather than top-level host admission.
- `src/Infernix/HostClaimants.hs` — live protocol observation rather than exclusion substitute.
- `src/Infernix/HostMemory.hs` — observed host facts consumed by the host-layout boundary.
- `src/Infernix/ExecutionPlan.hs` and `Internal.hs` — cell-child fit and exact granted identity.
- `src/Infernix/Runtime/Enforcer.hs` — applied envelope and effective wall join.
- `src/Infernix/Runtime/CappedEngine/*` — final child authority consumption and receipt evidence.
- `src/Infernix/Runtime/Daemon.hs` — persistent platform/engine claim attachment.
- `src/Infernix/Service.hs` — anchor-aware engine startup and eventual local engine-lock removal.
- `src/Infernix/Cluster.hs` — outer claim requirement around all cluster mutations and persistence.
- `src/Infernix/Cluster/LifecycleLock.hs` — remains an inner project lock; does not implement the
  host lock ABI.
- `src/Infernix/Cluster/Subprocess*` — closed anchor launch/communication reuse where appropriate,
  without exposing raw process construction.
- `src/Infernix/ProcessIdentity*` — host-anchor birth and namespace identity integration.
- `src/Infernix/CLI.hs` and `CommandRegistry.hs` — resource status/recovery and internal anchor
  dispatch.
- `bootstrap/apple-silicon.sh`, `bootstrap/linux-cpu.sh`, and `bootstrap/linux-gpu.sh` — stage-zero
  boundary and host-authority launcher delegation.
- `compose.yaml` — internal governed-child use rather than direct authority.
- `infernix.cabal` — vetted CBOR/locking dependencies, internal modules, tests, and strict warnings.

### Existing strengths to preserve

- no repo-owned native implementation or direct FFI;
- no raw unbounded subprocess launch;
- no fabricated inference results;
- no operator-editable enforcement executable paths;
- bounded descriptor space before every process image spawns;
- generated, untracked Dhall system and machine contracts;
- artifact-derived model requirements;
- one engine process per machine;
- at-least-once delivery with terminal-result-before-acknowledgement;
- resource-indexed grants and enforcers;
- owner-indexed cluster teardown evidence; and
- exact cleanup/reap obligations for retained effects.

## Validation Plan

### Pure and serialization validation

- canonical encoding/decoding and rejection of noncanonical CBOR;
- semantic ABI digest golden test;
- checked positive arithmetic and overflow;
- sequential, concurrent, replica, persistent/transient, and child-split laws;
- resource graph aliasing and ancestor/child conflicts;
- project allowlist and registered-parent laws;
- exact strength satisfaction and weaker-mechanism refusal; and
- deterministic layout and claim-key parsing.

### Compile-fail validation

- construct a lock key without an observed physical domain;
- construct a cell lock without a validated cell;
- substitute host, boot, epoch, project, parent, claim, resource, profile, or mechanism brands;
- escape a lease or child authority from its rank-2 region;
- reuse a linear transition or execution authority;
- skip envelope application or terminal cleanup;
- relabel a receipt or resource quantity;
- acquire or grow a live host bundle from a child;
- invoke a raw process/container/device launch through the strict facade; and
- import internal lock, journal, anchor, or backend modules from an unapproved owner.

### Lock and crash validation

- same-object cross-process contention;
- shared epoch versus exclusive catalog mutation;
- parent, cell, ancestor, and leaf lock ordering;
- duplicate in-process descriptor refusal;
- partial bundle rollback;
- stale record with a live effect;
- stale record with an absent effect;
- replaced root, lock, journal, socket, process, container, VM, or device identity;
- crash before and after every durable transition;
- forced anchor exit and bounded cleanup;
- simulated boot/VM/Docker identity change; and
- quarantine preservation when absence cannot be proven.

### Infernix workflow validation

- toolchain contention across independent CLI processes;
- toolchain refusal beside a live operator-platform claim;
- full harness demand covers all process and cluster phases;
- `cluster up` retains authority after the invoking CLI exits;
- status/down attach to the same anchor and claim;
- harness cannot seize an operator platform held by another claim;
- Apple cluster and host engine fit one unified-memory cell;
- engine-only machine admission occurs on that machine;
- exact whole-device CUDA contention and UUID exposure;
- no acknowledgement before a terminal inference result;
- model ceiling breach remains a real failed result, never a fabricated success; and
- successful cleanup retires the receipt before releasing locks.

### Cross-project conformance

All participating repositories should independently pin the same semantic ABI digest and run the
same black-box matrix against the same host lock objects:

- same-cell contention;
- disjoint-cell concurrency;
- whole-GPU versus MIG conflict;
- distinct partition concurrency where supported;
- same-key retry and receipt return;
- different-key/same-parent contention;
- anchor/CLI death;
- reboot/topology invalidation;
- catalog mutation exclusion; and
- permanent tombstone identity.

Infernix should not claim four-project safety until every named participant in that claim has passed
the required matrix for the rows it advertises.

### Repository gates

Validation must use the supported Infernix execution context, never bare host Cabal:

- `infernix lint docs` and `infernix lint plan` for governance changes;
- `infernix lint files`, `lint chart`, `lint proto`, and the Haskell style suite for bypass rules;
- the unit, resource-authority, compile-fail, execution-plan, bounded-engine, and integration suites;
- `infernix test all` on the phase's selected accelerator plus `linux-cpu`; and
- separate Apple and CUDA phases under the repository's single-accelerator-per-phase rule.

## Documentation and Plan Updates

Adoption affects broad doctrine and operator workflow. The owning plan work should align:

- `documents/engineering/shared_host_resource_protocol.md`;
- `documents/architecture/bounded_host_memory.md`;
- `documents/architecture/bounded_inference_memory.md`;
- `documents/architecture/typed_execution_plan.md`;
- `documents/architecture/managed_state_transitions.md`;
- `documents/architecture/configuration_doctrine.md`;
- `documents/architecture/daemon_topology.md`;
- `documents/development/local_dev.md`;
- `documents/development/testing_strategy.md`;
- Apple and cluster operations runbooks;
- the host-tools manifest for any new fixed observer/enforcement tools;
- `DEVELOPMENT_PLAN/README.md`, `00-overview.md`, `system-components.md`, phase documents,
  cohort waves, and the removal ledger; and
- `README.md`, `AGENTS.md`, and `CLAUDE.md` together because supported bootstrap and launcher
  entrypoints change.

The governed documents should state the finished target directly. Implementation gaps, migration
order, validation receipts, and cleanup remain in `DEVELOPMENT_PLAN/`, not in the target doctrine.

## Completion Criteria

The Infernix refactor is complete only when:

1. the semantic ABI and canonical vectors are frozen and independently pinned;
2. the fixed host root, layout, locks, journals, anchor, and recovery paths pass their live and
   crash tests;
3. every governed toolchain, cluster, engine, container, and accelerator launch descends from one
   held host-cell parent authority;
4. complete workload arithmetic covers persistent baselines, concurrency peaks, storage, cleanup,
   and retained evidence;
5. Apple unified memory and CUDA device identity are enforced according to their honestly declared
   mechanism strengths;
6. the Linux outer-container workflow delegates to a host-side anchor and no direct supported
   Compose bypass remains;
7. missing or incompatible authority state refuses before spawn or mutation, with no legacy
   fallback;
8. compile-fail fixtures and lints make the principal bypasses unrepresentable or repository-illegal;
9. repository-local full suites pass on the required per-phase cohorts;
10. cross-project contention and recovery pass against the same kernel lock objects; and
11. the governed docs, plan status, component inventory, validation receipts, and removal ledger
    agree with the resulting implementation.

Until those conditions hold, the protocol remains a proposal or partially implemented adapter, not
an Infernix conformance guarantee.
