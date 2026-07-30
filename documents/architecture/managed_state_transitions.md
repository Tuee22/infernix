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
  a matching resource-indexed grant/enforcer pair and OS-enforced `MemoryCeiling`, the memory analog
  of `runBoundedCommand` under a `Timeout`.
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
  constructible term;
- cluster teardown consumes an opaque `ClusterTeardownAuthority s` minted from
  `Lease s ClusterMutationLocked`, persisted owner, requested runtime, exact reservation access, and
  global live-runtime inventory. `PreWorkloadKindRecovery s` and `KindDeleteAuthorization s` retain
  the same region, so authority cannot escape or be reused under another lifecycle-lock
  acquisition; nominal roles on the lease and authorization types prevent `Data.Coerce` from
  erasing the region. The effect-adjacent check rereads reservation access and requires the exact
  captured record, including owner PID, process group, and birth identity, before revalidating
  owner/runtime; tearing down an `OperatorOwned` cluster from the harness does not typecheck;
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
The exported chaos-mutation bracket does not trust the caller's previously loaded `ClusterState`.
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
| Files (lint) | `infernix lint files` native-source, Cabal, and embedded-source scan | repository-owned C/C++/Objective-C/CUDA/assembly/Metal/Swift/C2HS/HSC/C-- source or headers; Cabal native-source fields or native-token CPP definitions; embedded native source/writers/compiler invocations in another implementation language |

Two residual review-obligations remain and are minimized to a small audit surface: **probe honesty**
(each evidence type has exactly one mint, co-located with its hidden constructor, that must consume a
real artifact — a probe that fabricates is the same forbidden mask the [realness
contract](realness_contract.md) rejects), and **bottom** (every operation forces its evidence, so a
`undefined`-forge is an immediate loud crash, never a silent unmanaged action).

## Current Status

The raw cluster spawn primitive is now confined to `Infernix.Cluster.Subprocess`, and both that
module and `Infernix.Cluster.Command` are library-internal `other-modules`; `Cluster.hs` no longer
owns a raw `System.Process` helper. The integration suite reaches only a non-destructive
unit-returning quiescence check exported by `Infernix.Cluster`, while the unit component compiles the
two internal source modules directly. Compile-fail fixtures prove that an external component cannot
import either capability module. The closed command language, separate read-only operator-kubectl
type (an allowlist rejects mutating verbs, mutating grouped subcommands, plugins, `exec`, and
kubectl global profile/cache flags capable of caller-selected local writes),
36-field generated command-policy record, opaque `CommandPolicyPlan` / `BoundedCommand` compilers,
total deadline, retry fold, and process-group cleanup are implemented. Production call-site
migration in `Cluster.hs` and `Cluster.PublishImages` is complete. Operand validation runs before
rendering; generated
publication policy owns all retry attempts under one total deadline. Kind delete likewise owns its
generated ten-minute/three-attempt/two-second-backoff policy without a caller loop, performs
same-lock-region effect-adjacent authority revalidation with an exact reservation reread, and
accepts a terminal non-zero only after observed absence. Spawn failures cannot mint
idempotent-absence success; passwords travel through stdin or a mode-0600 temporary auth file
rather than argv. Harbor registry verification is a closed `PublishVerifyRegistry` command whose
generated policy bounds the authenticated platform-selected skopeo `docker://` -> `dir:` copy.
Each empty verification destination and auth file is below a fresh birth-identity-owned mode-0700
directory. Primary-preserving brackets remove every protected path on normal return, failure, and
asynchronous cancellation; a later publication reconciles a SIGKILL-stranded directory only after
the recorded owner birth identity is absent. Unit coverage fixes the command/tool/argv/platform,
redaction, absolute destination, permission, concurrency, and cleanup boundaries. The final Sprint
2.16 adversarial audit reopened target-exec provenance, parent-death supervision, parent-side
forced cleanup, and the real readiness-deadline kernel before source freeze. It later removed the
cached-Docker-pull `PublishVerifyPull` witness described above. The subsequent all-Haskell
architectural correction removed the repository-owned lifecycle-lock C shim and replaced it with
the internal `filelock` wrapper. The public `System.Process` helper topology, bounded
standard-stream framing, and typed session protocol described above are implemented, and the
obsolete subprocess C file and Cabal declaration are removed. All source review, digest, Stage 1,
and cohort evidence from before that replacement remains superseded. Focused adversarial
validation, final source review, and the complete source-matched correction gate closed Phase 0
Sprint 0.18 on 2026-07-27. Sprint 2.16 remains blocked by active Phase 1, then retains its own
ordered final review, complete Stage 1, and Wave Y evidence.
The Harbor `/v2/` startup observation is also folded through `awaitReadinessObservable` under an
explicit 120-second stall and ceiling deadline with five-second polls. HTTP `200`, `401`, and `403`
are measured API-ready; every other HTTP response is measured non-ready; and a transport exception
is unobservable, so it can neither mint readiness nor masquerade as a measured response. The `/v2/`
probe and authenticated artifact-metadata request each carry a required five-second response
timeout. The handwritten publication `threadDelay` loop is retired, and
`Cluster/PublishImages.hs` is no longer exempt from the raw-delay lint.
The Linux launcher's inline `InfernixHost` payload includes the same complete 36-field default policy
record; unit coverage extracts and strictly decodes that actual Dockerfile payload so launcher
schema drift cannot reach `materialize-substrate`.
Apple artifact provisioning now uses its separate opaque rank-2 grant/session boundary over the
same bounded self-exec kernel. The Apple facade, artifact transaction, and provisioning modules
cannot import `System.Process`, invoke raw process primitives, delegate to the legacy unbounded
Poetry helpers, or call `runBoundedCommand` outside the provisioning facade; the
`appleArtifactProvisioningViolations` style rule enforces that boundary. Sprint 1.20 is actively
correcting the one-shot runtime capability, exact executable and package snapshot, current-recipe
binding, descriptor-anchored artifact traversal, recursive Mach-O closure, and crash-recoverable
Audiveris mount transaction. Its focused suite and compile-fixture inventories are therefore
work-in-progress, and no earlier case count or result is reusable. Final source review, a fresh
exact-source complete Stage 1, and Apple plus paired `linux-cpu` cohort evidence remain mandatory.

This is the governing contract, and its code-side implementation has landed across the ten reopened
phases tracked in
[../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) (Managed-State-Transition Doctrine
Reopen), each code-side closed 2026-07-16 on the machine-independent gate set with its
single-accelerator cohort full-suite the remaining wave residual. The doctrine and the escape-token
lint are **Phase 0** (Sprint 0.13); the evidence and command kernels are **Phase 1** (Sprint 1.16);
the typed `ClusterLifecycle` machine plus fail-closed versioned aeson persistence plus the
`WriterQuiesced` lease-gated teardown are **Phase 2** (Sprint 2.14); the readiness kernel and typed
subprocess-env seam are **Phase 3** (Sprint 3.14); the `PayloadVerified` sentinel gating, typed
`awaitModelBootstrapReady`, and native-runner `HOME`/`TMPDIR` are **Phase 4** (Sprint 4.28); the
single-sourced client-side readiness contract is **Phase 5** (Sprint 5.12); the capability-gating lint
plus routed managed-transition coverage is **Phase 6** (Sprint 6.39); the `ClusterState` /
`LifecycleProgress` field retirement plus the `DemoBucketsProvisioned` object-proxy gate and proven
`.ready` sentinel are **Phase 7** (Sprint 7.29); the typed `WarmModelCacheOutcome` readiness plus
fail-closed config-side reads are **Phase 8** (Sprint 8.7); and the `withValidAdminToken` region lease
and typed `StsSession` leased value are **Phase 9** (Sprint 9.10). The superseded surfaces are recorded
in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

A **flake-driven follow-on reopen** (2026-07-19, the Bounded-Command Application & Bounded-HTTP wave)
applies these kernels at two sites the 2026-07-18 cohort run proved unguarded — a Harbor `docker pull`
verify hang and a rate-limited upstream model download. It is code-side closed 2026-07-19 on the
machine-independent gate set (apple-silicon), and
[Wave V](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) closed the single-accelerator plus
`linux-cpu` cohort on 2026-07-20: the bounded-HTTP `DownloadOutcome` kernel is **Phase 1** (Sprint
1.17); the bounded
Harbor publish exec plus the `BlobServable` witness and the `harborTagMetadataPresent` /
`observeRegistryApi` demotion are **Phase 3** (Sprint 3.15); the classified-download consumer fold
plus the integrity-witnessed `PayloadVerified` are **Phase 4** (Sprint 4.29); and the
`unboundedExecViolations` and `unboundedHttpViolations` capability-gating lints are **Phase 6**
(Sprint 6.40). The `ProcessMonitor` retirement, the shared `retryCommandOutput` primitive, the
eager-model-cache barrier, the full individual bounded-wait migration (the twelve remaining
hand-rolled `go n` readiness loops across `Cluster.hs`, `Runtime/Pulsar.hs`, and `CLI.hs` — every one
now folded onto `awaitReadiness` under either an attempt-derived `budgetDeadline` or an explicit
wall-clock-plus-poll-cap `pollLimitedDeadline` for intentionally blocking probes), and the
`threadDelayViolations` lint gate (raw `threadDelay` is a build error outside the readiness kernel and
a deliberately shrinking backoff/heartbeat exemption list, keeping `CLI.hs` and
`Cluster/PublishImages.hs` clean) are all migrated
onto the bounded-command / `awaitReadiness` kernels (**Phase 6** Sprint 6.41, code-side closed
2026-07-19, machine-independent and adversarially reviewed). The 2026-07-25 Phase 2 audit then
corrected the readiness kernel itself: it measures a monotonic wall clock, includes probe duration,
interrupts a hung probe at the remaining stall/ceiling budget, and preserves an independent maximum
poll cap for both measured and wholly unobservable streams. The cap is not a quota: the real wall
deadline can stop a slow probe stream before every permitted poll runs, and prior advancing progress
then classifies as `NotReady`. The shared `budgetDeadline :: Int -> Int -> Deadline` bridge supplies
both that real wall budget and an exact maximum attempt cap for short probes;
`pollLimitedDeadline` requires callers with an intentional per-probe timeout to state the larger
total wall budget explicitly. An unbounded probe or bare-recursion readiness wait is therefore
unrepresentable.

A second **flake-driven follow-on reopen** (2026-07-22, the Observable-Readiness wave) closes the last
representable invalid state the readiness surface still permitted: a probe that could not *observe* a
remote system was forced to launder that fault into a definite not-ready count (or, at the observation
layer, a definite absence), which stalled the retained-second-`cluster up` warm-model-cache barrier at
"11/16" and, on the Python side, let a fallible cache-revalidation read *delete* a valid retained
`.ready` sentinel. It is code-side closed 2026-07-22 on the machine-independent gate set
(apple-silicon): the `PollOutcome` observable-poll channel on `awaitReadinessObservable` (with
`awaitReadiness` preserved as a behaviour-identical `Measured`-lift, so the sixteen existing waits are
unchanged) is **Phase 1** (Sprint 1.18); the tri-state `SentinelObservation` warm-model-cache probe,
the `SentinelCensus` that refuses to emit a readiness count while any sentinel is unobservable, and the
Python `CacheValidity` evidence-gated cache deletion are **Phase 8** (Sprint 8.8). The
single-accelerator (apple-silicon) plus `linux-cpu` behavioral cohort proof closed under
[Wave W](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) on 2026-07-24.

A third **follow-on reopen** (2026-07-23, the Cluster-Ownership & Mutation-Position wave) closes a DSL
smell an externally-killed `infernix test all` exposed: because `ClusterState` had no owner and
`ClusterLifecycle` had no mutating position, a test-mutated cluster (a drained node, an over-scaled
deployment) was the same term as an operator's idle `ClusterReady`, so a killed run left a dirty cluster
reading as a clean `steady-state`; and `runClusterOwnedValidation`'s unconditional `clusterDown` plus
the shared operator cluster identity (the test resolves the operator's `infernix.dhall`/`.data`/cluster
name via `findRepoRoot`) meant even a clean `infernix test all` destroyed an operator's running cluster.
The doctrine adds the typed `ClusterOwner` (`OperatorOwned | HarnessOwned`) with an evidence-gated
seizure that fails closed on an operator cluster, the first-class `ClusterMutating` position with
reconcile-on-next-`cluster up`, and the crash-safe `withTestHarnessConfig` backup reconcile. The
doctrine doc + governance mirror landed first — **Phase 0** (Sprint 0.16, doc-only, `Done`) — and the
enforcing code was extended by the 2026-07-25 owner-atomic correction: the `ClusterOwner` field,
`ClusterMutating` position, fail-closed persistence (the `clusterOwner` field decodes to the safe
default `OperatorOwned` on a pre-migration document, so an unowned-but-present cluster is protected, not
destroyed), global three-runtime Kind inventory, and owner/runtime-indexed teardown authority are
**Phase 2** (Sprint 2.15). The harness publishes a process-group reservation with a verified,
persisted owner birth identity under the lifecycle lock before taking over `infernix.dhall`;
operator mutations and a second live harness fail closed, while an unverifiable live group remains
fenced. Each bounded command has a separately grouped anchor; the implemented replacement moves the
supervisor and self-exec pin out of their containing groups only after their provisional exact
identities reach parent custody. The parent durably publishes their final version-3 activity
identities before the typed session may spend its one-shot target-start authority. Only proven
absence of every recorded anchor, supervisor, and pin-led target group permits a later harness to reclaim
the reservation before crash-backup reconciliation.
The
evidence-gated seizure (`seizeHarnessClusterSlot` over a hidden-constructor
`ClusterTeardownAuthority` consumed by the unexported raw teardown), the chaos-mutation
`ClusterMutating` transitions (`withPersistedClusterMutation`), and the crash-safe config swap
(`reconcileInterruptedHarnessState` plus the reservation-gated config transaction) are
**Phase 6** (Sprint 6.43). The all-Haskell lifecycle and bounded-subprocess replacements are
implemented, and the obsolete subprocess C file and Cabal declaration are removed. Focused
validation, source review, the fresh complete machine-independent gate, and cohort validation
remain open. Wave X remains evidence only for the earlier scope.

An image-owned Linux engine artifact now carries loader-closure evidence as part of its generation
identity (**Phase 1**, Sprint 1.20). The payload-root digests an image target already recorded said
nothing about the loader named by `PT_INTERP`, the resolution metadata in `/etc/ld.so.cache`, or the
system libraries reached through `DT_NEEDED`, all of which live outside those roots — so two images
with different `/lib` contents produced the same generation. `Infernix.Engines.Artifact.Loader`
observes that closure through retained descriptors and
`engineArtifactGenerationFingerprint` binds it, and the Linux installed smoke revalidates the
complete recorded closure immediately before launch, failing closed on a manifest carrying none.
`LD_LIBRARY_PATH` is never consulted: reading it would be an ambient environment read the
configuration doctrine forbids, and an identity that depended on it would not be reproducible. This
is a derivation of what the loader would resolve, not yet an observation of what it did — the
`LD_DEBUG=libs` analogue of the Apple lane's `DYLD_PRINT_LIBRARIES` audit is not wired into the
Linux smoke, and that gap remains open.

## Validation

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
  complete focused and Phase 2 gates remain required before Sprint 2.16 may be marked done.
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
- `infernix lint docs` keeps this document registered and its cross-references resolving; the reopened
  phase and sprint status is tracked in `DEVELOPMENT_PLAN/`.

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
- [../development/chaos_testing.md](../development/chaos_testing.md) — the SIGKILL-mid-mutation chaos
  case the `ClusterMutating` position and reconcile-on-next-`cluster up` cover.
