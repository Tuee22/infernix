# Managed State Transitions

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [realness_contract.md](realness_contract.md), [../development/haskell_style.md](../development/haskell_style.md), [../engineering/storage_and_state.md](../engineering/storage_and_state.md)

> **Purpose**: Define the code-level "evidence, not hope" invariant — every operation that acts on a
> system state consumes typed evidence that the state's transition actually completed — so that races
> and flakes (unmanaged state transitions) are structurally unrepresentable.

## TL;DR

- A **flake is an unmanaged state transition**: code that observes or acts on a system state `S` on
  hope — a fixed timeout, a proxy signal, a derived value, a residue, a readiness sentinel written
  without proof, a filesystem scrub against a still-live writer — rather than on a value that could
  only exist if `S` had truly been reached.
- The invariant: for every state `S` there is a transition `T` that reaches it and typed **evidence
  `E(S)`** that witnesses it. Every operation that acts on `S` **requires** `E(S)` as an argument, and
  the only producer of `E(S)` is the real transition `T`. Acting on a state whose transition was never
  managed does not typecheck.
- This is the same shape as the [realness contract](realness_contract.md) — "real output or a visible
  failure" — generalized from inference **results** to state **transitions**. The typed
  [per-substrate memory admission](runtime_modes.md) (`InferenceMemoryBudget` /
  `ModelMemoryLimitExceeded`, closed ADTs rather than integer sentinels) is the in-repo precedent this
  doctrine generalizes; [bounded inference memory](bounded_inference_memory.md) carries the same
  bounded-primitive shape to the inference subprocess itself — an opaque `ExecutableModel` carrying
  a matching resource-indexed grant/enforcer pair and a measured, watchdog-terminated
  `MemoryCeiling`, the memory analog
  of `runBoundedCommand` under a `Timeout`. The analogy has one limit worth stating: a deadline is a
  property of a single process and composes trivially, whereas a ceiling on one process says nothing
  about the host, so memory additionally needs a declared budget and an admission rule over
  concurrent claims — owned by [bounded host memory](bounded_host_memory.md).
- Enforcement rides on **GHC module export lists plus `-Wall -Werror`** — the sound, compile-checked
  lever. The governed lints are line-based and cannot see scope; the type system does. Line-based
  capability-gating lints back the raw primitives that have no type-level chokepoint: `unboundedExecViolations`
  forbids raw process spawn outside `runBoundedCommand`, and `unboundedHttpViolations` forbids raw
  `withResponse` outside the bounded upstream-download wrapper. Repository-owned native
  implementation is not an allowed escape hatch: `infernix lint files` rejects native sources,
  including C/C++/Objective-C headers and implementation, CUDA, assembly, Metal, Swift, C2HS, HSC,
  and C--, plus
  Cabal `c-sources:`, `cxx-sources:`, `asm-sources:`, and `cmm-sources:` declarations and CPP
  definitions that synthesize native tokens. Embedded native source, native-source writers, and
  direct compiler invocations in other implementation languages are the same forbidden boundary.
  The internal wrappers may use only public `filelock`, `process`, and `unix` APIs, never direct
  FFI, inline C, `System.Process.Internals`, or a relocated equivalent. Direct `foreign import` is
  forbidden throughout repository-owned Haskell. Darwin process-birth identity is implemented by a
  registry-backed Haskell boundary protected by `filelock`; the Apple engine-footprint observer is
  a fixed, total-deadline kernel over absolute `/usr/bin/top` and `/usr/bin/footprint`, with no
  caller-supplied executable, arguments, environment, or cleanup authority.
- Apple engine provisioning is a second package-internal consumer of the bounded-command kernel,
  not a raw process exception. `withProvisioningGrant` encloses an opaque nominal
  `ProvisioningGrant s` and an indexed `ProvisioningSession s result` in one rank-2 region.
  Constructors and the session interpreter are hidden; callers can select only closed adapter and
  operation identities, positive total deadlines, and typed path operands. Poetry install/setup,
  protobuf generation, Python probing and venv hydration, exact pinned-package installation,
  Audiveris download/mount/copy/detach, installed `--smoke`, and provenance queries all compile
  through the same self-exec anchor/supervisor/pin kernel and return the exhaustive
  `ProvisioningOutcome` sum.

## The law

For every state `S`: a transition `T` reaches it, evidence `E(S)` witnesses it. Evidence has two kinds.

- **Monotone (latching) states** — once true, stay true (`ModelBootstrapReady`, `PayloadVerified`,
  `DemoBucketsProvisioned`, `HarborRegistryReady`). Evidence is an **opaque newtype with a hidden
  constructor**, minted by exactly one honest transition that consumes a real artifact. Provenance is
  truth here because the property never un-happens.
- **Revocable (leased) states** — can lapse after `T` (`WriterQuiesced`, `AdminTokenValid`,
  `ClusterReachable`, `StsLive`, a held lock). Evidence is a **rank-2 region lease**
  `withLease :: Acquire p -> (forall s. Lease s p -> IO r) -> IO r` whose `forall s.` region tag makes
  the evidence inseparable from the scope in which the runtime actively holds the condition — it cannot
  be returned, stashed, or mixed across regions. A capability that must be spent exactly once is
  additionally consumed linearly (`%1 ->`) so it cannot be reused after it is spent.

The raw destructive, commit, and spawn primitives are **not exported**; the only public path takes
evidence:

- the retained-state scrub takes a `WriterQuiesced` lease, so a scrub against a live writer is not a
constructible term; - cluster teardown consumes an opaque `ClusterTeardownAuthority s` minted from
`Lease s ClusterMutationLocked`, persisted owner, requested runtime, exact reservation access, and
global live-runtime inventory. `PreWorkloadKindRecovery s` and `KindDeleteAuthorization s` retain
the same region, so authority cannot escape or be reused under another lifecycle-lock acquisition;
nominal roles on the lease and authorization types prevent `Data.Coerce` from erasing the region.
The effect-adjacent check rereads reservation access and requires the exact captured record,
including owner PID, process group, and birth identity, before revalidating owner/runtime. nominal
nominal`. `PreWorkloadKindRecovery` and `KindDeleteAuthorization` carry the same index. The owner
field is now the singleton `SClusterOwner owner` rather than a bare value, so the index and the
value it stands for cannot drift, and `requireClusterOwnership` — still the sole mint — takes the
singleton and returns the correspondingly indexed authority. A fourth compile-fail fixture,
`fail-cannot-substitute-cluster-teardown-owner`, shares the region variable so the *only* thing GHC
rejects is the owner, and rejects it with `Couldn't match type 'HarnessOwned' with 'OperatorOwned'`.

  Be equally precise about what the index does **not** buy, because that is the over-claim this work
  exists to retire. Substituting one owner's authority for the other's is now a type error. Deciding
  who owns a *live* cluster is not, and cannot be: that is discovered at run time by rereading the
  persisted record and the Kind inventory under the held lease, so tearing down an `OperatorOwned`
  cluster from the harness is still refused by a checked `ioError`, not by the type checker. No
  runtime check was weakened to add the index. Where the owner is only known at run time —
  `withPersistedClusterMutation`, which reads it inside the lock — a rank-2
  `withClusterOwnerSingleton` selects the singleton *from the owner just read*, so no index is
  fabricated.

  The defect was that ownership evidence did not travel with the resource:
  `clusterLifecycleLockPath`, `harnessReservationPath`, and `clusterStatePath` all derive from the
  per-checkout `runtimeRoot`, while `kindClusterName` drops its `dataRoot` discriminator for the
  default `.data` layout that every ordinary checkout uses — so two checkouts locked different
  inodes while contending for one machine-global Kind cluster, and each authorized against the
  *other's* live inventory using its *own* state file. A killed harness run leaves a `HarnessOwned`
  state file behind, so a second checkout starting `infernix test all` could observe the operator's
  live cluster, match it against that leftover record, and delete it.

  Both mechanisms the sprint originally proposed were rejected on analysis, and the reason is worth
  keeping: neither works in *both* supported execution contexts. Relocating the lock to a
  machine-scoped path is unreachable from inside a launcher container, and the container's baked
  manifest gives every checkout `hostRepoRoot = /workspace` and `hostDataRoot = /workspace/.data`,
  so a path-derived identity actively *collides* there — which also means the cluster-name
  discriminator does not discriminate on the lane where contention is most likely. What the two
  contexts genuinely share is the Docker daemon, so the identity lives on the protected resource:
  `stampClusterSlotIdentity` records the creating checkout's **host-side** repository root inside the
  control-plane node at `/etc/infernix/cluster-checkout-identity`, and `readClusterSlotIdentity`
  reads it back through the same closed `ClusterCommand` catalog. No new command constructor and no
  new host-manifest field were needed, so an operator's already-generated `./infernix-host.dhall`
  keeps decoding.

  `localClusterCheckoutIdentity` **fails closed** rather than reusing `resolveHostRepoRoot`'s
  fallback. Answering `/workspace` is the right conservative answer when *rendering a path* and the
  worst possible answer for an *identity*, because every launcher container would then claim the
  same one. `authorizeClusterOwnership` consumes the local identity and the observed slot identity
  alongside the inventory and the persisted record, and returns a `ClusterSlotAdmission` rather than
  `()`. `requireClusterOwnership` — still the sole mint — reads both under the held lease, so every
  authority is minted from evidence gathered inside one critical section.

  The two owners are deliberately asymmetric on a cluster that predates the identity. The operator
  may **adopt** it, because refusing would strand a running cluster behind a manual `kind delete`;
  adoption stamps this checkout's identity under the same lease that authorized it, so the next
  authorization is a positive match. The harness may **not**: it is the destructive actor in the
  defect above — an unattended `infernix test all` that tears down whatever it finds — so it must
  prove the slot is its own, and an unidentified slot is exactly the proof it lacks. An unreadable
  control-plane node is treated as unidentified for the same reason. Adoption itself is reported
  and not fatal, because it upgrades evidence on a cluster that already passed the ownership check;
  aborting there would put a damaged node ahead of the bring-up path's own recovery, and leaving the
  slot unidentified keeps the harness fenced, which is the property that matters;
- the readiness-sentinel commit takes a `PayloadVerified`, so a sentinel written without proof does not
  typecheck;
- the lifecycle lock is acquired only through the library-internal
  `Infernix.Cluster.LifecycleLock` wrapper around `filelock`'s nonblocking exclusive lock. The
  package token and raw lock/unlock operations are hidden, while the public lifecycle operation
  encloses the held token in the existing rank-2 `Lease s ClusterMutationLocked` region. Contention
  therefore applies across threads and processes, and the kernel releases the lock after normal
  return, synchronous or asynchronous exception, or process death;
- production cluster execution starts from the abstract `ClusterCommand` language in the
  library-internal `Infernix.Cluster.Command` module. Its semantic builders own verbs, option
  ordering, scripts, manifests, stdin, redacted labels, working-directory intent, and the Kind
  scratch `KUBECONFIG`. The sole operator-token compatibility surface is a different abstract type,
  `OperatorKubectlCommand`; its constructor rejects target-changing kubectl flags and it has a
  separate compiler. Neither this command module nor the subprocess kernel is exposed by the
  library, so an external caller cannot compose a destructive builder, compiler, and runner around
  the lifecycle evidence boundary.
- `compileBoundedCommand` accepts only a `ClusterCommand` and hidden-constructor `SubprocessEnv`.
  It resolves the rendered command's exact domain-tool set from `HostConfig`, rejecting each empty,
  nonabsolute, missing, or nonexecutable path. Nested requirements are explicit: the fixed Bash
  pipelines declare Bash and Docker, while commands that use neither do not require them. Through
  public `System.Process.createProcess`, the parent self-execs one command anchor with
  `close_fds = True`, `create_group = True`, an explicit environment, and `CreatePipe` for ordinary
  stdin/stdout/stderr. The freshly executed anchor uses the same public API to create and reap the
  supervisor with `close_fds = True`, an explicit environment, ordinary standard streams, and
  `create_group = False`, so it begins inside the recorded anchor group. The anchor forwards the
  provisional supervisor PID, current group, and birth identity to the parent. Only after the
  parent reobserves that exact identity and spends an opaque custody acknowledgement may the
  supervisor detach into its own PID-led group. This closes the stop-or-death window before the
  parent has cleanup authority.
- The supervisor self-execs its retained group pin through the same public `System.Process` surface,
  initially with `create_group = False` inside the supervisor group. Its provisional PID, current
  group, and birth identity are forwarded through the anchor to the parent; the pin cannot detach
  until the parent reobserves and acknowledges custody. The final ready transition requires the
  same PID/birth identity to be observed as its own process-group leader. Parent/anchor,
  anchor/supervisor, and supervisor/pin traffic uses total JSON messages inside an eight-hex-digit
  length prefix, newline delimiter, and fixed maximum frame size over ordinary standard streams.
  Command input and captured output are base64 fields inside those bounded frames; malformed,
  truncated, oversized, out-of-order, or invalid messages are kernel failures. A pin that receives
  its post-durability retain authority acknowledges entry into a self-retained state with no
  lifetime writer or inherited private descriptor.
- The parent verifies the final live owner, anchor, supervisor, and self-exec pin identities by
  exact PID, process group, and process birth identity before publishing activity. The opaque
  `SessionProgram` admits only the linear, rank-2 sequence `AnchorReady -> SupervisorReady ->
  LeaseDurable -> TargetRunning`; its constructors are hidden, and the session token cannot escape,
  be reused, or skip durable publication. A version-3 activity lease is fsynced and renamed under a
  directory fsync before the one-shot start authority can be spent. It persists the anchor under
  legacy `command*` keys, the supervisor under legacy `watchdog*` keys, and the exact pin under
  compatibility `targetGroupLeader*` keys; those keys name the retained group leader, not the
  arbitrary target. Recovery continues to decode version-1 command-only and version-2 dual-group
  records. It reads at most 64 KiB per final activity document and rejects an oversized or
  structurally invalid document before acting on it. Before any payload byte is written, the kernel
  fsyncs a bounded incoming-intent
  basename that encodes the exact owner/anchor/supervisor/pin identities. The common-boot encoding
  uses `.incoming-activity-v3.*`; the fixed-width distinct-boot encoding uses
  `.incoming-activity-v4.i*`. Recovery parses and validates that filename, refuses malformed,
  colliding, or oversized entries, and can clean an empty or truncated prewrite without PID-only
  inference.
- Only after the durable transition and retained-pin acknowledgement may the supervisor use the
  kernel's sole public `System.Posix` fork/exec boundary. The target child begins inside the
  supervisor group behind a private inner gate; both child and supervisor attempt the atomic move
  into the recorded pin group, and the gate opens only after the supervisor reobserves the
  supervisor-owned target PID in that exact group. The target has no persisted birth-identity
  claim: its authority is the designated supervisor's still-unreaped child ownership plus PID,
  while the exact persisted pin identity protects group-level recovery against PID reuse. A stop at
  any point is therefore contained in either the exact supervisor group or the exact pin group. The
  child closes inherited helper handles before
  `executeFile`; a close-on-exec report pipe distinguishes setup/exec failure from a genuine target
  exit, including genuine exits 126 and 127. Report-write failure and any malformed/nonempty report
  remain kernel failures, never exit-code inference. The renderer selects repository cwd where
  required; callers cannot supply cwd or arbitrary environment entries.
- Parent EOF before publication cannot leave a target because target fork is post-durability; the
  parent-held provisional supervisor and pin custody identities authorize cleanup across each
  single allowed containing-group-to-PID-group move. After publication, the persisted final
  identities authorize recovery. On target terminal, the supervisor continues and kills the
  pin-led group before any output drain can wait on pipe-inheriting descendants, then reaps its
  target and pin and proves the group absent. The anchor reaps the supervisor and the parent reaps
  the anchor. Activity retirement occurs only after every recorded group is proven absent.
- `SubprocessEnv` owns the manifest-derived `PATH` and absolute `HOME`, `TMPDIR`,
  `HELM_CONFIG_HOME`, `HELM_CACHE_HOME`, and `HELM_DATA_HOME`. The opaque compiler produces
  `BoundedCommand command`, the only input accepted by `runBoundedCommand`, which returns the total
  `CommandOutcome`
  (`CommandSucceeded | CommandFailedFatal | CommandFailedKernel | CommandTimedOut`). Transient
  failures are internal retry decisions and cannot escape as a terminal result. Setup, compilation,
  capture, and target-exec failures remain kernel failures and bypass command retry and
  idempotent-absence classification; a Kind-delete postcondition may discharge only a completed
  target's `CommandFailedFatal`. One required deadline encloses all attempts and retry backoffs. For
  each attempt, bracketed cleanup closes the parent protocol endpoint, forcibly terminates and boundedly
  reaps every owned child, proves the anchor, supervisor, and pin-led target groups absent, and
  only then removes its activity lease after success, failure, exception, or timeout. Dead-owner
  recovery accepts legacy version-1 command-only, version-2 dual-group, and current version-3
  three-group leases and
  cannot restore config or release the reservation until every recorded group is proven absent;
  malformed or unverifiable leases fail closed. The compatibility field names do not describe the
  current helper roles.
- The Apple artifact facade is the only exposed engine-materialization module. Its raw artifact
  transaction, provisioning facade, provisioning command constructors, and per-artifact installer
  remain package-internal. A caller submits one closed materialization request to a runner-owned
  indexed session; it cannot obtain, skip, duplicate, or retain an intermediate phase authority.
  The private kernel advances through candidate custody, source-specific provisioning, smoke,
  manifest publication, activation, final revalidation, and terminal cleanup. Materialization
  hydrates an owned sibling `.tmp` root completely before activation: exact direct package pins are
  installed, a closed source-specific smoke operation is authoritative, Python/source/runtime
  provenance is resolved from the candidate, and the actual sorted payload tree is hashed by path,
  type, mode, file bytes, and safe symlink target. The manifest is excluded from that digest to
  avoid a circular hash, then records the resulting digest and resolved provenance.
- A Cabal-hidden direct-target catalog, rather than manifest command text, owns the executable,
  interpreter/module or JRE/classpath prefix, immutable runtime-closure roots, and target-specific
  invocation grammar. Linux manifests record exact descriptor-derived executable and closure
  identities and digests; Apple targets are inside the installed payload digest. Runtime
  revalidates the target observation under the shared artifact lease before the start gate can
  open. Generated `bin/*` wrappers are not part of the supported topology.
- Candidate Python environments are created with copied launchers and without bytecode generation.
  Owned activation scripts, console-script shebangs, and `pyvenv.cfg` are rewritten from the
  sibling candidate path to the final root before smoke and hashing; any residual candidate-root
  byte sequence anywhere in a regular payload file rejects the transaction. Audiveris is fetched
  from one pinned release URL and accepted only at its fixed SHA-256; mounted-image cleanup checks
  the kernel device identity before issuing the closed detach operation.
- Activation synchronizes the complete candidate tree, moves only sibling directories, fsyncs the
  parent after each rename, retains the previous exact root until final-path revalidation, and
  rolls back on synchronous failure or asynchronous cancellation. Startup reconciliation gives a
  valid final root priority, restores a valid `.previous` root when needed, promotes `.tmp` only
  when no final or rollback root exists and its exact manifest/digest validate, discards
  unambiguous invalid residue, and fails closed when recovery evidence is ambiguous.
- upstream model download takes the same bounded-outcome shape: the fetch carries a required
  `responseTimeout` and a descriptive `User-Agent`, and its HTTP status is classified by the pure
  `classifyDownloadStatus :: Int -> Maybe Int -> DownloadOutcome` into a total `DownloadOutcome`
  (`DownloadSucceeded | DownloadRateLimited RetryAfterSeconds | DownloadTransient | DownloadPermanent`).
  "Every non-200 collapses to one opaque failure retried forever" and "an unbounded transfer" stop
  being constructible terms; the consumer folds on the outcome — honoring `Retry-After` with a bounded
  backoff for the rate-limited/transient cases and acking a permanent failure to stop the redeliver
  loop.

Readiness waits **return evidence**, generalizing the `HarborBootstrapOutcome` pattern: a value proving
`S`, or a total not-ready / expired outcome carrying progress, with the **deadline as a required data
field**. The Harbor publish/verify surface mints an opaque `BlobServable` — proof that a specific image
ref is actually pullable from the registry — only after a bounded authenticated platform-selected
`skopeo copy` reads the selected manifest, config, and every referenced layer from the Harbor API
authority into a fresh empty `dir:` store. That store lives under a birth-identity-owned mode-0700
directory and is independent of Docker's shared content cache. Tag-metadata presence
(`harborTagMetadataPresent`), a measured reachable-registry observation (`observeRegistryApi`), or
a Docker pull that can reuse cached content may shortcut work or gate polling but can never stand
in for blob-servability; the terminal "done" of a publish requires the `BlobServable`, not a `Bool`.
A client deadline is derived from its server ceiling in one definition, so a client that waits
less than the server can take is not expressible. Cluster lifecycle is a typed `ClusterLifecycle`
machine — a closed sum with a consumed, resumable phase — replacing the `clusterPresent :: Bool` plus
`lifecyclePhase :: String` pair; its persistence is a **fail-closed** versioned codec, so an
unrecognized on-disk document blocks a destructive action instead of decoding to a silent "absent".
The machine also carries a first-class `ClusterMutating LifecyclePhase` position, so a cluster a test
suite is actively mutating (a drained node, an over-scaled deployment) is not the same term as an
operator's idle `ClusterReady`: an interrupted (SIGKILLed) `infernix test all` leaves `ClusterMutating`
persisted, so `cluster status` reports a mutation-incomplete (dirty) phase rather than a false
`steady-state`, and the next `cluster up` reconciles it — uncordoning drained nodes and scaling
deployments back — through the same reconcile-on-next-start repair the interrupted-bring-up path uses.
The exported cluster-mutation bracket does not trust the caller's previously loaded `ClusterState`.
While holding the lifecycle lock it rereads the state, complete Kind inventory, and owner
reservation; only an exact live `ClusterReady` owner/runtime match may publish `ClusterMutating`.
The body receives that freshly validated state, and `ClusterReady` is restored from it only after
the dirty marker, inventory, and exact reservation identity are revalidated. A stale caller,
missing state or live cluster, already-dirty lifecycle, owner mismatch, body failure, or changed
postcondition therefore cannot publish a false ready state.
Detached retained-state bring-up has its own reserved lifecycle intent,
`replay-retained-state-into-kind`. It is persisted before first Kind creation and remains current
through every worker copy and claim-preparation command. A live non-bind cluster can resume replay
only when that exact phase, owner, runtime, and bring-up transition still match; a legacy
provisioning marker or missing/mismatched state is ambiguous and fails closed instead of starting
workloads over a partial snapshot. If Kind exists but its kubeconfig is unreadable, only a private
pre-workload recovery proof that revalidates the exact pending intent and teardown authority under
the lifecycle lock permits delete/recreate without copy-back. Every ordinary live/idempotent
bring-up leaves an unreadable cluster untouched.
Normal teardown and unreadable pre-workload recovery carry distinct private authorizations into the
same Kind-delete boundary. That boundary consumes the matching lifecycle-lock lease, rereads and
requires the exact captured reservation record, and rechecks the global three-runtime inventory,
recorded owner, and runtime beside the effect; recovery additionally rechecks the exact pending
replay intent. The generated Kind-delete policy owns one ten-minute total deadline, three
attempts, a two-second backoff, and `IdempotentAbsence` classification, with no caller retry loop.
A recognized absence succeeds immediately; an unrecognized failure remains bounded; a
setup/compile/exec/capture `CommandFailedKernel` or `CommandTimedOut` fails immediately; and after a
completed target's `CommandFailedFatal`, only a live observation that the cluster is absent converts
the transition to success.
The test-harness `./infernix.dhall` swap is crash-safe in the same spirit: a leftover
`.harness-backup` from a killed current-format run is reconciled on entry only after the dead
reservation's bounded-command activity leases prove every recorded process group absent, so a crash cannot
leave the operator's runtime config clobbered by the test config. A scoped pre-v2 compatibility path
also restores a backup for which no reservation identity was ever recorded; it runs under the
lifecycle lock, cannot claim activity-quiescence evidence, and is tracked for deletion rather than
being included in the current-format proof.

Readiness **observation** is itself three-valued, because a probe that reads a remote system does not
always get to observe it. A transport fault — a reset idle NodePort keep-alive, a HEAD timeout, a
`5xx` "server not initialized", a `403` before the object layer is ready — is neither "ready" nor "a
concrete not-ready count"; it is a failure *to measure at all*. Collapsing that third fact into a
`Bool` (or a fabricated progress count) is a representable invalid state: a present-but-momentarily-
unreachable `.ready` sentinel counted as "absent" is exactly what stalled an already-warm model cache
to its give-up deadline (the "11/16" second-`cluster up` symptom). The readiness kernel's poll outcome
is therefore `PollOutcome e = Measured (Either Progress e) | Unobservable Text`, and the
warm-model-cache sentinel probe is
`SentinelObservation = SentinelPresent | SentinelAbsent | SentinelUnobservable Text` whose only
producer of `SentinelAbsent` is a genuine `404`. An `Unobservable` poll is routed to
*retry-within-budget* — it can neither mint a `Ready` nor deflate the observed census count — so a
transient fault can never masquerade as a definitive absence. The Python model-cache revalidation
mirrors this with a `CacheValidity = VALID | CORRUPT | UNVERIFIABLE` verdict: the
retained-sentinel-destroying `_delete_model_prefix` is reachable only through a `CORRUPT` witness (a
deterministic size mismatch), never a fallible read, so a MinIO blip can no longer delete a valid
retained cache.

## Enforcement

| Surface | Mechanism | Forbids |
|---|---|---|
| Types | GHC module export lists (opaque types, hidden constructors) under `-Wall -Werror` | constructing evidence outside its minting module; acting on a state without its evidence value; an unbounded or unclassified command outcome |
| Region | rank-2 `forall s.` lease scope, plus surgical `LinearTypes` (`%1 ->`) for spend-once capabilities | using revocable evidence outside the scope that holds the condition; reusing a spent capability |
| Haskell | `Infernix.Lint.HaskellStyle` escape-token check | `unsafeCoerce` / `unsafePerformIO` in the evidence modules (the two escapes types cannot close) |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` capability-gating rules `unboundedExecViolations` / `unboundedHttpViolations` / `appleArtifactProvisioningViolations` | raw unbounded process spawn (`readCreateProcessWithExitCode` / `createProcess` / `waitForProcess` / …) outside `Infernix.Cluster.Subprocess.runBoundedCommand`, raw Apple artifact process access or delegation to the legacy unbounded Poetry helpers outside the opaque provisioning facade, and raw `withResponse` for the upstream model download outside the bounded-HTTP wrapper — the raw primitives that have no type-level chokepoint |
| Haskell (lint) | `Infernix.Lint.HaskellStyle` rule `unboundedDescriptorSpawnViolations` | a `close_fds` spawn surface that never observes `Infernix.DescriptorSpace.requireBoundedDescriptorSpace` — see [Bounded descriptor space](#bounded-descriptor-space) |
| Files (lint) | `infernix lint files` native-source, Cabal, and embedded-source scan | repository-owned C/C++/Objective-C/CUDA/assembly/Metal/Swift/C2HS/HSC/C-- source or headers; Cabal native-source fields or native-token CPP definitions; embedded native source/writers/compiler invocations in another implementation language |

### Bounded descriptor space

A bounded command is not bounded if its own spawn is unbounded. Until this doctrine's
follow-on it was not. Every spawn kernel here sets `close_fds = True` so a child inherits nothing but
the standard streams it is handed. `close_fds` is a configuration `posix_spawn` cannot express, so
`process` falls back to fork/exec and, in the forked child, closes every descriptor from 3 up to
`sysconf(_SC_OPEN_MAX)` — the soft `RLIMIT_NOFILE` — before `exec`. The walk is linear in a limit the
process *inherits* rather than chooses, and containerd hands a pod `1073741816`. Measured at that
exact limit: **313 s per spawn**, against a 5 s observer deadline and a 50 ms sampling cadence. The
same spawn with `close_fds = False` is 0.8 ms at every limit.

The doctrine answer is to bound the resource, not to weaken the isolation.
`Infernix.DescriptorSpace.establishBoundedDescriptorSpace` lowers the soft limit to a 16384 ceiling as
the first action of a process image, before the internal self-exec dispatch and before anything opens
a descriptor. A process cannot open a descriptor numbered at or above its own soft limit, so no
descriptor above the bound can ever exist and the child's walk over `3 .. bound` still closes the
entire descriptor space: `close_fds` keeps its exact meaning, and only its cost becomes bounded. The
bound is inherited across `fork` and `exec`, so anchor, supervisor, pin, target, and engine children
are bounded by their parent. The limit is only ever lowered, so a tighter host-imposed limit is
preserved, and the hard limit is written back unchanged, so no privilege is required.

`requireBoundedDescriptorSpace` is the fail-closed half, called by each kernel immediately before
`createProcess`: an unbounded process image is a named refusal identifying the spawning kernel rather
than a stall that reads as a hang. Because it is an observation at the point of use, it holds even if
a future process image forgets to establish the bound.

Two residual review-obligations remain and are minimized to a small audit surface: **probe honesty**
(each evidence type has exactly one mint, co-located with its hidden constructor, that must consume a
real artifact — a probe that fabricates is the same forbidden mask the [realness
contract](realness_contract.md) rejects), and **bottom** (every operation forces its evidence, so a
`undefined`-forge is an immediate loud crash, never a silent unmanaged action).

### Command and lifecycle boundaries

The extracted contract, stated as requirements rather than as progress:

- The raw cluster spawn primitive is confined to `Infernix.Cluster.Subprocess`. That module and
  `Infernix.Cluster.Command` are library-internal `other-modules`, so an external component cannot
  import either capability module — proved by compile-fail fixtures. The integration suite reaches
  only a non-destructive, unit-returning quiescence check exported by `Infernix.Cluster`.
- Operator `kubectl` is a **separate read-only command type**. Its allowlist rejects mutating verbs,
  mutating grouped subcommands, plugins, `exec`, and the kubectl global profile and cache flags that
  would permit a caller-selected local write.
- Operand validation runs before rendering. Generated publication policy owns all retry attempts
  under one total deadline; there is no caller-side retry loop. Kind delete owns its generated
  policy the same way, performs same-lock-region effect-adjacent authority revalidation with an
  exact reservation reread, and accepts a terminal non-zero **only after observed absence** — a
  spawn failure can never mint idempotent-absence success.
- Credentials travel through stdin or a mode-0600 temporary auth file, never argv. Each verification
  destination and auth file sits below a fresh, birth-identity-owned mode-0700 directory.
  Primary-preserving brackets remove every protected path on normal return, failure, and
  asynchronous cancellation; a later publication reconciles a `SIGKILL`-stranded directory only once
  the recorded owner birth identity is proven absent.
- Grandchild command resolution is pinned, and the pin is **reclaimable state, not sealed state**.
  Infernix invokes every tool by absolute path from the host manifest, but the tools it spawns
  resolve *their* children by bare name against `PATH` — `cabal` → `ghc`, `helm` → `kubectl`,
  `poetry` → `python3`, `kind` → `docker`. A command-shim root holding one symlink per
  manifest-declared tool is prepended to that `PATH` so those lookups land on the manifest's binary.
  The root's leaf names its owning process (pid plus birth-identity digest) alongside the generation
  digest, so the next materialization can prove an owner gone before reclaiming it. A shared,
  content-addressed name carried no owner, so nothing could prove that no live process was still
  resolving through a root, and published roots therefore accumulated forever. Integrity is the four
  content conjuncts — entry set, symlink targets, link-not-regular-file, and the marker digest —
  rechecked on every use and repaired by republication, **not** a directory mode: a mode-`0500` root
  detected only the *possibility* of mutation, stopped no adversary at a single uid (this module
  chmods a shim root itself when reclaiming one), and made the root unremovable by ordinary tooling
  such as `git clean` and `rm -rf`. Republication vacates a corrupt root through an atomic
  rename-aside, because POSIX `rename(2)` fails with `ENOTEMPTY` against a non-empty destination and
  a root that verification rejects would otherwise be terminal — every republication failing, and
  every external command failing with it. What this does **not** bound: the shim root is *prepended
  to*, never substituted for, the tool-directory search path, so any name the manifest does not
  declare still resolves out of the host's ordinary binary directories.
- Registry verification is a closed `PublishVerifyRegistry` command whose generated policy bounds an
  authenticated, platform-selected `docker://` → `dir:` copy.
- Readiness is measured, never assumed. The Harbor `/v2/` startup observation folds through
  `awaitReadinessObservable` under an explicit stall-and-ceiling deadline: HTTP `200`, `401`, and
  `403` are measured API-ready; every other response is measured non-ready; and a transport
  exception is **unobservable**, so it can neither mint readiness nor masquerade as a measured
  response. The `/v2/` probe and the authenticated artifact-metadata request each carry a required
  response timeout, and no handwritten delay loop substitutes for the kernel.
- The Linux launcher's inline host payload carries the same complete generated command-policy
  record, and unit coverage strictly decodes that actual payload so launcher schema drift cannot
  reach substrate materialization.
- Apple artifact provisioning is a second consumer of the same bounded self-exec kernel through its
  own opaque rank-2 grant and session boundary. The Apple facade, artifact-transaction, and
  provisioning modules cannot import `System.Process`, invoke raw process primitives, delegate to
  unbounded helpers, or call `runBoundedCommand` outside the provisioning facade — enforced by the
  `appleArtifactProvisioningViolations` rule.

## Validation

**Harness SIGKILL mid-mutation.** A `HarnessOwned` run killed while it is actively mutating the
cluster leaves a first-class `ClusterMutating` position persisted rather than an operator-idle
`ClusterReady`. `cluster status` reports a mutation-incomplete phase, not a false `steady-state`, and
the next `cluster up` reconciles it through the reconcile-on-next-start repair.

**Bounded-command owner death and forced cleanup.** Machine-independent adversarial coverage proves
parent death both before and after durable activity publication, stopped-supervisor and
stopped-target-group cleanup, supervisor death, descendant termination, exact birth-identity
recovery, and designated-owner reaping — without timing sleeps or PID-only evidence. Activity
retires only after the anchor, supervisor, and target groups are proven absent.


- `cabal build all` under `-Wall -Werror` is the primary proof: an operation reachable without its
  evidence, or a raw hatch called outside its evidence-taking wrapper, is a build error.
- Host-schema and subprocess unit tests must round-trip the proper retry/failure unions, cover all 36
  production policy fields, reject zero or overflowing refined values, reject empty/relative required
  tool paths, and prove that one total deadline includes retry backoff. Kind-delete coverage must
  distinguish recognized absence, bounded unrecognized failure, setup/spawn
  `CommandFailedKernel`, and post-failure observed absence.
- Process-tree tests prove timeout, cancellation, parent death, supervisor death, and normal
  completion kill surviving or stopped descendants and reap the target, command-group pins, anchor,
  and supervisor. They also cover concurrent descriptor isolation, synchronous exceptions, stopped
  supervisor and stopped target-group cleanup, supervisor death, target setup/exec provenance,
  genuine target exits 126/127, designated-owner reaping, pre-publication owner death with no target,
  helper, or activity residue, and post-publication recovery from exact persisted identities. The
  complete focused and phase gates are required before that scope may be marked done.
- Lifecycle-lock tests require same-thread nesting, concurrent same-process thread contention,
  cross-process contention, normal and exceptional release, asynchronous cancellation release, and
  automatic kernel release after owner death. None may use a timing sleep as readiness evidence.
- Independent negative fixtures prove authority coercion, lifecycle-lease coercion, authority
  escape, and cross-lifecycle-region reuse separately, so one expected compiler failure cannot mask
  another missing region guarantee.
- The deletion race regression must change the global inventory after initial authorization but
  before the effect-adjacent check and prove that no delete executes and the harness reservation
  remains held.
- A second runtime race must replace the reservation record after initial authorization and prove
  that the final check rereads and rejects it before delete; negative compilation must prove a
  `ClusterTeardownAuthority s` or `Lease s` cannot be coerced across regions and authority cannot
  escape or be reused with another lifecycle-lock region.
- Compile-fail fixtures must reject external imports of `Infernix.Cluster.Command`,
  `Infernix.Cluster.Subprocess`, `Infernix.Cluster.LifecycleLock`, and raw protocol constructors.
  Separate fixtures reject skipping the durable-lease phase, escaping the rank-2 session, and
  reusing the linear start authority. Direct positive kernel coverage belongs to the unit
  component's home-module build, not the public library surface.
- Apple artifact tests must additionally reject imports of
  `Infernix.Engines.AppleSilicon.Internal`, `Infernix.Engines.Artifact`,
  `Infernix.Engines.Provisioning`, and `Infernix.Engines.Provisioning.Internal`, plus the removed
  raw per-artifact installer. The focused transaction suite must exercise actual payload-tree
  identity, unsafe symlink/special-file rejection, exact-root validation, sync/async rollback, and
  crash reconciliation without using a package installation or network call as its oracle.
- `cabal test infernix-haskell-style` (`infernix test lint`) rejects `unsafeCoerce` / `unsafePerformIO`
  in the evidence modules and keeps the style gate clean.
- `infernix lint files` rejects repository-owned C/C++/Objective-C/CUDA/assembly/Metal/Swift/C2HS/HSC/C--
  implementation and header files, Cabal native-source fields and native-token CPP definitions,
  and embedded native source/writers/compiler invocations in other implementation languages.
  Upstream packages may contain their own native implementation; this repository may not.
- `infernix lint docs` keeps this document registered and its cross-references resolving.

## Cross-References

- [realness_contract.md](realness_contract.md) — the results-side sibling this doctrine generalizes.
- [bounded_inference_memory.md](bounded_inference_memory.md) — the memory analog of the
  bounded-command kernel: a refined executable capability gates the inference subprocess and carries
  its matching indexed grant/enforcer pair.
- [runtime_modes.md](runtime_modes.md) — the typed budget ADT precedent.
- [daemon_topology.md](daemon_topology.md) — role failure semantics and readiness gating.
- [../development/haskell_style.md](../development/haskell_style.md) — the export-list, opaque-newtype,
  and lease enforcement mechanisms.
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md) — durable-vs-derived state
  and the fail-closed versioned persistence.
- [../engineering/testing.md](../engineering/testing.md) — the canonical lifecycle failure
  classification.
  case the `ClusterMutating` position and reconcile-on-next-`cluster up` cover.
