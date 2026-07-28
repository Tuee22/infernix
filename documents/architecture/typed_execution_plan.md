# Typed Execution Plan

**Status**: Authoritative source
**Referenced by**: [configuration_doctrine.md](configuration_doctrine.md), [bounded_inference_memory.md](bounded_inference_memory.md), [managed_state_transitions.md](managed_state_transitions.md), [runtime_modes.md](runtime_modes.md), [../development/assistant_workflow.md](../development/assistant_workflow.md), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md)

> **Purpose**: Define the generated-Dhall execution language and runtime-evidence refinement that
> make an unbounded command, unenforced inference, or unroutable model structurally unrepresentable.

## TL;DR

- The target generated Dhall describes a closed execution plan, not a bag of descriptive settings.
  Phase 8 Sprint 8.9 owns the remaining migration from the transitional descriptive wire shape to
  proper Dhall unions and `Natural` quantities.
- The current Haskell capability core already models resource and enforcer alternatives as indexed
  ADTs; text tags plus zeroed inapplicable fields are forbidden in the final generated language.
- Decoding proves structural validity. Runtime probes refine the decoded plan into opaque
  capabilities proving that the declared enforcer exists now.
- Coordinator routing consumes only compiled placements and daemon/topic capabilities. Engine
  subscription and process launch consume only runtime-refined `ExecutableModel` capabilities.
- Coordinator and engine handling is total: unavailable, empty-model, unknown-model, wrong-route,
  and malformed requests become terminal failed results before source removal or acknowledgement.
- There is no supported constructor for an unenforced execution plan and no launch function that
  accepts raw decoded configuration.

## The Rule

The supported execution path has four boundaries:

```text
binary-generated Dhall
  -> decoded plan
  -> validated and runtime-refined plan
  -> capability-gated execution
```

| Boundary | Input | Output | Invalid states rejected |
|---|---|---|---|
| Dhall typecheck (Phase 8 target) | generated expression | structurally typed expression | missing union payloads, fields from the wrong alternative, negative quantities |
| Haskell decode and compile | `RawRuntimeConfig` | `CompiledRuntimePlan` | zero quantities, dangling pool/member references, resource/enforcer mismatch, capacity oversubscription, unroutable models |
| Runtime refinement | `CompiledRuntimePlan` + live observations | `RuntimePlan` | unavailable process-group RSS sampler, ineffective outer cgroup envelope, unavailable Apple footprint probe, unavailable NVIDIA accounting, chart/config limit drift |
| Capability-gated routing/execution | coordinator projections from `CompiledRuntimePlan`; engine projections from `RuntimePlan` | total outcomes | raw unbounded command spawn, coordinator routing without compiled placement/daemon authority, engine launch without a matching grant and enforcer |

Dhall cannot prove a live OS fact. A Dhall alternative names the only permitted enforcement
mechanism; an opaque Haskell capability proves that the named mechanism was observed and installed.
Neither proof substitutes for the other.

## Closed Dhall Language

The final reflected schema uses proper alternatives. Phase 8 Sprint 8.9 owns the remaining
generated-Dhall migration from text/bool alternatives and `Integer` quantities; the Haskell
compiler already models resource/enforcer alternatives as indexed ADTs. The target memory shape is
equivalent to:

```dhall
let HostPartition =
      { physicalMib : Natural
      , vmReserveMib : Natural
      , headroomMib : Natural
      }

let MemoryEnforcement =
      < ApplePhysicalFootprintWatchdog : HostPartition
      | LinuxProcessGroupRssWatchdog :
          { pollingIntervalMicros : Natural
          , outerCgroupHeadroomMib : Natural
          }
      | NvidiaPerProcessWatchdog :
          { deviceIds : List Natural
          , pollingIntervalMicros : Natural
          }
      >
```

The exact expression remains owned by the Haskell decoder types and is emitted by `infernix
internal dhall-schema substrate`; this document owns its semantics. The schema must not encode
alternatives as `kind : Text`, arbitrary `resource : Text`, or one record containing fields for
every alternative. `Natural` removes negative values; Haskell smart constructors reject zero and
enforce relationships Dhall cannot express.

Each executable placement binds the model, pool, resource requirements, and enforcer:

```dhall
{ model : ModelDescriptor
, pool : Text
, resources :
    { residentMemoryMib : Natural
    , accelerator : < None | Nvidia : { vramMib : Natural } >
    }
, enforcement : MemoryEnforcement
}
```

## Compile And Refinement Boundary

Raw decoded records are confined to hidden configuration modules. Coordinator routing consumes a
compiled plan; engine subscription and worker launch consume its runtime-refined form:

```haskell
compileRuntimePlan
  :: RawRuntimeConfig
  -> Either ConfigErrors CompiledRuntimePlan

refineRuntimePlan
  :: RuntimeObservation
  -> CompiledRuntimePlan
  -> Either RefinementErrors RuntimePlan
```

Compilation validates at least:

- every model has exactly one legal execution placement for the active runtime mode;
- every referenced pool and member exists and has a compatible location and resource class;
- every daemon has the exact role, member, location, derived topics, result topic, subscription,
  and connection mode required by that graph, producing an opaque `CompiledDaemon`;
- CPU work cannot select a VRAM enforcer and GPU-required work cannot select a RAM-only enforcer;
- every model promoted to a compiled placement fits the declared capacity, while an oversized
  structurally valid model is classified explicitly as unavailable;
- runtime refinement compares the declared Linux outer envelope with live `memory.max` and the
  configured Apple partition with a fresh host observation;
- every compiled route is authorized by an exact `CompiledDaemon`; every engine-executed model has a
  successfully refined executable capability.
- no topic is reused across coordinator-request, result, model-bootstrap-request,
  model-bootstrap-ready, or engine-route families.

`CompiledRuntimePlan` exposes validated placements and daemon capabilities for coordinator routing.
`RuntimePlan` exposes a `Map ModelId ExecutableModel`, not a raw catalog, for engine consumption and
launch. A model cannot enter a compiled route unless its placement compiled, and cannot launch unless
its enforcer refined successfully.

Capacity rejection is request-local rather than a whole-daemon startup failure. The compiler
accounts for every input model in exactly one of two disjoint maps: a `CompiledPlacement` that may
advance to live refinement, or an explicit `UnavailableModel` carrying the compiler-produced
`InferenceError` (normally `ModelMemoryLimitExceeded`). It never
uses filtering or `mapMaybe` to lose an over-capacity model. Only the placement map feeds routing;
the unavailable map is the required source of the typed terminal rejection for an explicitly
requested configured model. The coordinator now emits that rejection without attempting to derive
a nonexistent engine route; the 2026-07-25 Phase 1 gate historically proved that behavior for its
source. The all-Haskell lifecycle/subprocess correction supersedes that gate as current-worktree
evidence, so the fresh complete Stage 1 must prove it again.

Request consumption is likewise total on both coordinator and engine paths. An empty model id,
unknown model, or route/capability mismatch produces a failed `InferenceResult`; malformed protobuf
produces a typed malformed failed result. On the file-spool harness path, the terminal result is
written before the source file is removed. On Pulsar, the terminal result is published before the
source message is acknowledged. No invalid request is silently dropped, indefinitely redelivered,
or allowed to reach an engine through a fallback route.

The supported raw topic publisher is removed. Model-bootstrap publication accepts only an opaque
`ModelBootstrapRequestCapability` prepared from the compiled plan. The consumer revalidates the
exact model identity, compiled download URL, and canonical UTC request timestamp before download,
upload, or ready-event side effects. `TopicFamilyCollision` rejects any cross-family reuse among
coordinator request, result, bootstrap request, bootstrap ready, and derived engine-route topics.
Generated substrate Dhall is converted to bytes with explicit UTF-8 encoding.

## Resource-Indexed Execution

Admission capacity and execution enforcement are distinct. Admission capacity answers whether work
may start; the execution ceiling is the exact quantity the launched process is prevented from
exceeding.

```haskell
executeExecutableInferenceWithKVCache
  :: Paths
  -> Maybe EngineKVCache
  -> Maybe KVCacheRequest
  -> ExecutableModel
  -> InferenceRequest
  -> IO (Either ErrorResponse InferenceResult)
```

An Apple unified-memory grant cannot be consumed by a Linux cgroup enforcer; a VRAM grant cannot be
consumed by a RAM enforcer. Constructors for `Enforcer resource`, `MemoryGrant resource`, and
`ExecutableModel` remain hidden. The package-internal worker derives the only legal process command
from the engine binding carried by that same executable value; arbitrary shell or cluster-config
command overrides are absent.

The implemented/target substrate split is:

- `apple-silicon`: a package-internal observer runs only fixed, absolute `/usr/bin/top` and
  `/usr/bin/footprint` commands under one total deadline and bounded captures, then the watchdog
  kills the child process group on a measured breach. No direct FFI or caller-supplied observer
  command exists; Phase 4 owns adversarial behavioral proof;
- `linux-cpu`: the implemented `/proc` process-group RSS watchdog sums every member conservatively and
  kills only the child execution group on breach; the pod cgroup is a larger verified outer
  envelope covering the daemon, admitted child ceiling, and polling overshoot, never the
  per-request breach classifier; Phase 4 owns adversarial behavioral proof;
- `linux-gpu`: the target pairs RAM enforcement with per-process-group NVIDIA accounting. That
  accounting is not implemented; compilation/refinement fails closed instead of treating a pod
  limit or CUDA exit as VRAM evidence, and Phase 6 owns the correction.

If a mechanism cannot be verified, refinement fails and the engine member never becomes ready. A
pod-wide capacity value or CUDA OOM classification is not evidence that an individual model ceiling
is enforced.

## Bounded Command Language

Cluster and provisioning operations use closed command constructors paired with generated policies:

```dhall
let RetryPolicy =
      < Never
      | Bounded : { attempts : Natural, backoffMicros : Natural }
      >

let CommandPolicy =
      { timeoutMicros : Natural
      , retry : RetryPolicy
      , failureClass : < Fatal | TransientThenFatal | IdempotentAbsence >
      }

let CommandPolicies =
      { kindRead : CommandPolicy
      , kindCreate : CommandPolicy
      , kindDelete : CommandPolicy
      , nvkindCreate : CommandPolicy
      , kubectlRead : CommandPolicy
      , kubectlApply : CommandPolicy
      , kubectlDelete : CommandPolicy
      , kubectlWait : CommandPolicy
      , kubectlExec : CommandPolicy
      , helmUpgrade : CommandPolicy
      , helmDependency : CommandPolicy
      , helmRepository : CommandPolicy
      , helmRender : CommandPolicy
      , dockerExec : CommandPolicy
      , dockerProbe : CommandPolicy
      , dockerBuild : CommandPolicy
      , dockerInspect : CommandPolicy
      , dockerPull : CommandPolicy
      , dockerTag : CommandPolicy
      , dockerCopy : CommandPolicy
      , dockerStreamImport : CommandPolicy
      , dockerNetwork : CommandPolicy
      , containerRuntimePull : CommandPolicy
      , hostProbe : CommandPolicy
      , hostMutation : CommandPolicy
      , curlProbe : CommandPolicy
      , archiveRead : CommandPolicy
      , gpuUserspaceSync : CommandPolicy
      , imagePublicationLogin : CommandPolicy
      , imagePublicationInspect : CommandPolicy
      , imagePublicationPull : CommandPolicy
      , imagePublicationVerify : CommandPolicy
      , imagePublicationTag : CommandPolicy
      , imagePublicationPush : CommandPolicy
      , imagePublicationRemove : CommandPolicy
      , imagePublicationCopy : CommandPolicy
      }
```

The generated record has exactly these 36 production fields. Test-only kernel probes are not
operator-configurable. `Natural` excludes negative values; `compileCommandPolicyPlan` rejects zero
or machine-overflowing timeouts and rejects zero or overflowing `Bounded` attempts/backoffs. Its
opaque record shape gives `commandPolicyFor` an exhaustive field for every `ClusterOperation`
instead of a partial text-keyed lookup.

The library-internal `Infernix.Cluster.Command` module defines abstract `ClusterCommand` values
through semantic builders. The renderer owns executable selection, CLI verbs and option order,
fixed scripts/manifests, stdin, redacted labels, repository-working-directory intent, and the typed
scratch `KUBECONFIG` required by Kind create/delete and nvkind create. It also records the exact
required `HostTool` set. The command module and `Infernix.Cluster.Subprocess` are not exposed, so
external callers cannot compose their builders, compiler, and runner around lifecycle evidence.
The two fixed Bash pipelines explicitly require both Bash and Docker; selecting an unrelated
command does not require unsupported tools. Bash is a domain dependency of those pipelines, not a
universal subprocess-kernel dependency.

Raw operator kubectl tokens do not reopen `ClusterCommand`. They inhabit the separate
`OperatorKubectlCommand` type, whose smart constructor rejects an empty command and target-changing
target, identity, credential, impersonation, and trust flags (including `-s` and split/equals long
forms). It is compiled through the separate `compileOperatorKubectlCommand` entry point and uses the
bounded kubectl-read policy.

`compileBoundedCommand` accepts only `ClusterCommand` plus hidden-constructor `SubprocessEnv`; it
does not accept executable paths, argv, cwd, or environment overrides. It resolves every exact
required tool through `HostConfig.hostToolPath` and rejects empty or nonabsolute values before
minting the opaque `BoundedCommand ClusterCommand`. `SubprocessEnv` owns manifest-derived `PATH`,
absolute `HOME`/`TMPDIR`, and the three repo-local Helm homes. Repository cwd and Kind
`KUBECONFIG` are projections of the closed rendered command, not caller choices.

Only `BoundedCommand command` reaches `runBoundedCommand`. One required total deadline encloses
session acquisition, every attempt, and retry backoff. Through public
`System.Process.createProcess`, the parent self-execs one anchor with `close_fds = True`,
`create_group = True`, an explicit environment, and ordinary `CreatePipe` standard streams. That
freshly executed anchor starts and reaps the supervisor through the same public API. The supervisor
begins inside the anchor group and the self-exec pin begins inside the supervisor group; each
provisional PID/group/birth identity is forwarded to and reobserved by the parent before an opaque
custody acknowledgement permits that helper to detach. The isolation point is inside the helper,
so concurrently executing parent commands cannot inherit each other's protocol handles. All helper
links carry total JSON messages in fixed-maximum, eight-hex-digit length-prefixed frames over
standard streams; input and output bytes are base64 inside those bounded frames.

Hidden `SessionProgram` constructors and a rank-2, linearly consumed session allow only
`AnchorReady` -> `SupervisorReady` -> `LeaseDurable` -> `TargetRunning`. The parent durably
publishes a version-3 activity lease with exact final anchor, supervisor, and pin identities before
spending the one-shot start authority. It records the anchor under legacy `command*`, the supervisor
under legacy `watchdog*`, and the exact self-exec pin under compatibility
`targetGroupLeader*` keys; version-1 and version-2 records remain decode-only recovery inputs.
Before writing that payload, a bounded, fsynced incoming-intent filename records the same exact
owner/anchor/supervisor/pin identities. Its common-boot encoding is version 3 and its fixed-width
distinct-boot encoding is version 4, so recovery can classify an empty/truncated prewrite without
PID-only inference. After the pin acknowledges its retained state, the supervisor owns the sole
public `System.Posix` private-pipe and fork boundary. The target begins in the supervisor group
behind an inner gate, moves into the recorded pin group, and cannot execute until its
supervisor-owned PID is observed in that group. The arbitrary target is retained and reaped by its
designated supervisor; it is not misrepresented as a persisted birth identity. The target then
calls `executeFile` directly. A close-on-exec
report pipe makes exec success observable independently of exit status, so target setup/exec failure is
`CommandFailedKernel` while a real target exit 126 or 127 remains `CommandFailedFatal`. Parent EOF,
timeout, exception, cancellation, and dead-owner recovery force cleanup, boundedly reap every owned
child through its designated owner, and prove the recorded anchor, supervisor, and pin-led target groups
absent before removing the lease. Malformed or unverifiable state fails closed.
Provisioning and smoke work use a separate `ProvisioningGrant` with a timeout, resident-memory
ceiling, and output bound; they do not receive a module-wide exemption from inference or command
enforcement.

## Current Status

This doctrine is the target contract opened by the Typed Execution Plan refactor. Phase 1 Sprint
1.19 historically closed its own source-matched scope on 2026-07-25. That result predates the
all-Haskell lifecycle-lock and subprocess correction and is not current-worktree Stage 1 evidence;
a fresh source review and complete source-matched Stage 1 are in progress. The current worktree has
resource-indexed grants/enforcers, exhaustive placement-or-unavailable accounting, a
`CompiledRuntimePlan -> RuntimePlan` live-refinement boundary, exact host-partition drift checks,
opaque compiled daemon wiring, hidden raw Dhall decoders and routing helpers, nominal resource
roles, exact runtime-scoped engine bindings, canonical identifiers, and engine commands derived
only from an executable model's compiled binding. The launch boundary also derives runtime and
model identity from that executable capability and rejects a mismatched request before side
effects. The normal coordinator and engine paths now return terminal failed results for unavailable,
empty-model, unknown-model, wrong-route, and malformed requests before source removal or
acknowledgement. Opaque plan-derived bootstrap publication, consumer-side
model/URL/timestamp revalidation, cross-family topic-collision rejection, removal of the raw topic
publisher, and explicit UTF-8 substrate emission are also present. The closing gate covered the
production/integration build, unit/internal/compile-fail/style suites (4 positive and 27 negative
compile fixtures), installed files/docs/chart/proto lints and docs check, Python `check-code`, web
contract/build/bundle coverage with 83/83 unit tests, and `git diff --check`; that historical gate
must not be reused for this correction. Phase 0's accepted correction review and complete Stage 1
closed on 2026-07-27. Phase 2 Sprint 2.16 is blocked by active Phase 1 in numerical order. Its
implemented all-Haskell lifecycle-lock and typed supervision replacement are present, while its
phase-owned focused adversarial gate, fresh final review, complete source-matched Stage 1, and both
Wave Y cohort lanes remain open. The
in-review implementation includes the proper
command-policy unions and all 36 generated
fields, the closed command/operator-kubectl split, opaque policy and command compilers, exact
required-tool resolution, renderer-owned cwd/Kind environment, kernel-owned base environment,
total deadline/retry fold, process-group cleanup, pre-render operand validation, structured
manifest encoding, and secret-safe stdin/protected-auth-file transport. `Cluster.hs` no
longer owns a raw process-spawn helper, and all production `Cluster.hs` and `Cluster.PublishImages`
call sites use the semantic builders. Its pre-audit machine-independent result is superseded, and
Phase 2 must finish focused validation and source review before the source freezes, the full proof
gate runs, and both cohort lanes close. The
broader implementation also does not yet satisfy the full execution-plan contract:

- Linux CPU execution has a process-group RSS watchdog plus an exact larger cgroup envelope, but
  still awaits the Phase 4 adversarial breach/survival proof;
- process-local serialization is still supplied by caller-owned daemon locking rather than an
  opaque execution authority, so Phase 4 must make concurrent reuse of one executable capability
  unrepresentable;
- GPU VRAM does not have a verified per-process enforcer;
- engine materialization and smoke modules retain raw-spawn exemptions;
- the generated Dhall execution alternatives still await the proper-union/`Natural` migration
  owned by Phase 8 Sprint 8.9.

Implementation status and ordered closure gates live in
[DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md). Until those sprints close, existing
limits remain defense-in-depth, not proof that resource exhaustion is unrepresentable.

## Validation

The completed implementation must prove:

- Phase 8 reflected-schema tests reject the retired flat/tagged representation and round-trip every
  generated execution union;
- property tests reject zero quantities, incompatible resource/enforcer pairs, dangling graph
  references, oversubscription, live-envelope drift, coordinator routing without a compiled
  placement/daemon capability, and engine launch without `ExecutableModel`;
- coordinator integration coverage proves a requested `UnavailableModel` publishes its
  compiler-produced typed terminal error without batch-topic derivation or engine launch;
- coordinator and engine coverage proves empty, unknown, wrong-route, and malformed requests write
  or publish one terminal failed result before source removal/acknowledgement;
- bootstrap capability tests reject model identity, compiled URL, and timestamp drift before side
  effects, while API/negative tests prove no supported raw publisher remains;
- compiler properties reject cross-family topic reuse, and non-ASCII substrate metadata
  round-trips through explicit UTF-8 emission and Dhall decode;
- negative compile fixtures cannot call routing or launch functions with raw configuration;
- generated host-schema tests round-trip the proper retry and failure unions plus every one of the
  36 command-policy fields;
- command-policy refinement rejects zero and overflow, while negative compile fixtures cannot
  construct `BoundedCommand` directly or pass executable/argv/cwd/environment data to its compiler;
- command-kernel tests prove exact required-tool validation, total-deadline retry behavior,
  allowlisted read-only operator kubectl compatibility, and process-group descendant
  cleanup/reaping;
- runtime tests refuse readiness when the selected enforcer is absent or ineffective;
- adversarial Apple, Linux CPU, and CUDA tests exceed each declared ceiling and observe a typed,
  terminal per-request failure while the host and daemon remain alive;
- Phase 6 confines production `System.Process` imports to the bounded command, capped engine, and
  bounded provisioning kernels;
- Phase 6 removes raw-spawn lint exemptions outside those kernels;
- the machine-independent gates and each owning phase's selected accelerator plus `linux-cpu` gate
  pass.

## Cross-References

- [Configuration Doctrine](configuration_doctrine.md)
- [Bounded Inference Memory](bounded_inference_memory.md)
- [Managed State Transitions](managed_state_transitions.md)
- [Runtime Modes](runtime_modes.md)
- [Daemon Topology](daemon_topology.md)
- [Realness Contract](realness_contract.md)
