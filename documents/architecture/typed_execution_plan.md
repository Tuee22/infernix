# Typed Execution Plan

**Status**: Authoritative source
**Referenced by**: [configuration_doctrine.md](configuration_doctrine.md), [bounded_inference_memory.md](bounded_inference_memory.md), [managed_state_transitions.md](managed_state_transitions.md), [runtime_modes.md](runtime_modes.md), [../development/assistant_workflow.md](../development/assistant_workflow.md), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md)

> **Purpose**: Define the generated-Dhall execution language and runtime-evidence refinement that
> make an unbounded command, unenforced inference, or unroutable model structurally unrepresentable.

## TL;DR

- Generated Dhall describes a closed execution plan, not a bag of descriptive settings. The wire
  uses proper Dhall unions and `Natural` quantities and carries no transitional descriptive shape.
- The Haskell capability core carries one requirement and one enforcement mechanism per physical
  resource a placement consumes, as resource-indexed ADTs. The strength of that mechanism — a ceiling
  installed before the engine's first allocation, or sampling alone — is part of the type rather than
  a remark beside it; text tags plus zeroed inapplicable fields are forbidden in the generated
  language.
- Decoding proves structural validity. Runtime probes refine the decoded plan into opaque
  capabilities proving that the declared mechanism exists now, on this machine, at the strength the
  plan claims for it.
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
| Dhall typecheck | generated expression | structurally typed expression | missing union payloads, fields from the wrong alternative, negative quantities |
| Haskell decode and compile | `RawRuntimeConfig` | `CompiledRuntimePlan` | zero quantities, dangling pool/member references, resource/enforcer mismatch, capacity oversubscription, unroutable models |
| Runtime refinement | `CompiledRuntimePlan` + live observations | `RuntimePlan` | an unavailable sampler for any resource the placement consumes, ineffective outer cgroup envelope, unavailable Apple footprint probe, unavailable NVIDIA accounting, chart/config limit drift, a lane that declares an installed ceiling its mechanism cannot install, a ceiling never calibrated against a real engine on that lane |
| Capability-gated routing/execution | coordinator projections from `CompiledRuntimePlan`; engine projections from `RuntimePlan` | total outcomes | raw unbounded command spawn, coordinator routing without compiled placement/daemon authority, engine launch without a matching grant and enforcer |

Dhall cannot prove a live OS fact. A Dhall alternative names the only permitted enforcement
mechanism; an opaque Haskell capability proves that the named mechanism was observed and installed.
Neither proof substitutes for the other, and neither lets a lane spell a mechanism stronger than the
one it can install.

## Closed Dhall Language

The reflected schema uses proper alternatives: every enum-like choice in the substrate wire is a
Dhall union rather than `Text` refined after decode, and every quantity is `Natural` rather than
`Integer`. The union-typed fields are `runtimeMode`, engine-pool `subscription`, and request-shape `fieldType`.
The role union moved with the contract split: a daemon role is a fact about one box, so it is spelled
on the machine contract (`machine.role`) rather than on the system contract every box shares.

`adapterType` and `source` use domain types (`EngineAdapterType`, `PodMemoryLimitSource`) rather than
raw `Text` refined by membership or non-blank checks. An unsupported adapter type and a blank
enforcer source are therefore not constructible terms.

`configEdgePort` is not part of the execution language. The routed port is
`ClusterState.edgePort`, chosen during `cluster up`; it does not travel through this wire format.

Two mechanical facts are load-bearing. A Dhall union alternative is a **label**, so the wire spelling
is `AppleSilicon`, not `"apple-silicon"`; invalid legacy spellings receive a targeted diagnostic
instead of a bare structural type error, and so does every field the language has since retired —
including `daemonRole`, whose invalid aliases (`frontend`, `cluster`, `host`) are values a union
cannot express at all.
`genericAutoWith` dispatches on a datatype's GHC-Generics shape, so a
**single-constructor** mirror derives as a record rather than as a one-alternative union;
`fieldType` needs an explicitly built union decoder, which the generate-then-decode round trip is
what catches.

The Haskell compiler expresses requirements and enforcement mechanisms as resource-indexed ADTs.
The generated memory shape is equivalent to:

```dhall
let HostPartition =
      { physicalMib : Natural
      , vmReserveMib : Natural
      , headroomMib : Natural
      }

let SamplingPolicy = { pollingIntervalMicros : Natural }

let HostEnvelope =
      < UnifiedHostPartition : HostPartition
      | OuterPodEnvelope : { outerCgroupHeadroomMib : Natural }
      >

let HostMechanism =
      < InstalledDataSegmentCeiling : { backstop : SamplingPolicy }
      | SampledFootprintOnly : { backstop : SamplingPolicy }
      >

let MemoryEnforcement =
      { host : { envelope : HostEnvelope, mechanism : HostMechanism }
      , device :
          Optional
            { deviceIds : List Natural
            , arenaMib : Natural
            , backstop : SamplingPolicy
            }
      }
```

The union names **what a lane installs**, not which loop it runs. One sampling kernel serves every
resource, so three per-platform watchdog alternatives would spell an implementation detail three
times and still leave the load-bearing distinction unsaid: `InstalledDataSegmentCeiling` claims a
kernel limit in force before the engine's first allocation, with the backstop covering the residue
that limit does not charge, while `SampledFootprintOnly` claims detection and nothing more. A lane
that can install no ceiling — and a lane whose ceiling has never been calibrated against a real
engine on it — has only the second spelling available, so an unearned claim of prevention is a
refusal at refinement rather than a sentence in a comment.

The device arm has no mechanism alternative to choose from, because no kernel mechanism bounds
device memory on any supported lane: it names the devices, the arena the admitted quantity sizes,
and the backstop's cadence. Giving it a `< Prevented | Sampled >` union would offer a strength no
platform can supply.

The exact expression remains owned by the Haskell decoder types and is emitted by `infernix
internal dhall-schema substrate`; this document owns its semantics. The schema must not encode
alternatives as `kind : Text`, arbitrary `resource : Text`, or one record containing fields for
every alternative. `Natural` removes negative values; Haskell smart constructors reject zero and
enforce relationships Dhall cannot express.

Each executable placement binds the model, pool, execution shape, a requirement per physical
resource, and the enforcement mechanism for each:

```dhall
let LoadStrategy =
      < ResidentInHost
      | StreamedToDevice : { stagingWindowMib : Natural }
      >

let ExecutionShape =
      { contextLengthTokens : Natural
      , batchSize : Natural
      , maxGenerationTokens : Natural
      , loadStrategy : LoadStrategy
      }

{ model : ModelDescriptor
, pool : Text
, shape : ExecutionShape
, requirement :
    { hostResidentMib : Natural
    , deviceResidentMib : Optional Natural
    }
, enforcement : MemoryEnforcement
}
```

Neither field of `requirement` is a copy of the other. Host residency and device residency are
different formulas with different drivers, and `StreamedToDevice` is why: under it the host term is
the staging window rather than the model, so a single `residentMemoryMib` admitted against both
resources would be wrong twice — oversized against the host and unrelated to the device. Both
quantities are derived from the artifact and the execution shape rather than authored, under the
derivation and its refusals owned by
[bounded_inference_memory.md](bounded_inference_memory.md).

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
- every model promoted to a compiled placement fits the executing machine's observed capacity for
  every resource it consumes, while an oversized structurally valid model is classified explicitly as
  unavailable;
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

**Refinement is engine-only.** All three roles compile the plan at startup. Only the engine refines
it, before publishing readiness. The coordinator publishes
readiness on the compiled plan and the webapp builds no plan beyond compilation, because refinement
is not a stronger validation of the same thing — it is an observation of *the refining process's
own machine*: the live sampler probes, the host partition, this process's own cgroup `memory.max`,
the observed device VRAM, and whether this machine's lane can install the ceiling its plan declares. Its pod arm is an exact match against the hosting pod's `memory.max`,
so refining in a coordinator pod would either fail against a limit that is legitimately different or
succeed against a ceiling no inference will ever run under — the second outcome being worse, because
it manufactures evidence about a resource the process does not use.

The property refinement exists to establish is that a launch cannot happen without a matching live
enforcer, and it is discharged where launches happen: refinement returns one opaque
`EngineExecutionPlan` enclosing the refined plan and its single-flight lock, and
`publishedResultFromRequest` — the one choke point both the websocket and filesystem-spool paths
pass through — requires it. Neither non-engine role launches an
inference subprocess: the coordinator's loops are `CompiledRuntimePlan`-typed and its
`drainInferenceTopic` hard-errors on a coordinator capability, and the webapp only publishes to
Pulsar. So the requirement ("startup compiles and refines the generated plan before
publishing readiness") is scoped to the role that launches inference, and reads as satisfied.

Capacity rejection is request-local rather than a whole-daemon startup failure. The compiler
accounts for every input model in exactly one of two disjoint maps: a `CompiledPlacement` that may
advance to live refinement, or an explicit `UnavailableModel` carrying the compiler-produced
`InferenceError` (normally `ModelMemoryLimitExceeded`). It never uses filtering or `mapMaybe` to
lose an over-capacity model. Only the placement map feeds routing; the unavailable map is the
required source of the typed terminal rejection for an explicitly requested configured model.

Request consumption is likewise total on both coordinator and engine paths. An empty model id,
unknown model, or route/capability mismatch produces a failed `InferenceResult`; malformed protobuf
produces a typed malformed failed result. On the file-spool harness path, the terminal result is
written before the source file is removed. On Pulsar, the terminal result is published before the
source message is acknowledged. No invalid request is silently dropped, indefinitely redelivered,
or allowed to reach an engine through a fallback route.

There is no raw topic publisher. Model-bootstrap publication accepts only an opaque
`ModelBootstrapRequestCapability` prepared from the compiled plan. The consumer revalidates the
exact model identity, compiled download URL, and canonical UTC request timestamp before download,
upload, or ready-event side effects. `TopicFamilyCollision` rejects any cross-family reuse among
coordinator request, result, bootstrap request, bootstrap ready, and derived engine-route topics.
Generated substrate Dhall is converted to bytes with explicit UTF-8 encoding.

## Resource-Indexed Execution

Admission capacity and execution enforcement are distinct. Admission capacity answers whether work
may start; the execution ceiling is the exact quantity the launched process is held to — and *how*
it is held there differs by resource, which is the reason the two are not one number. On a host lane
whose ceiling is calibrated and installed by the launch prefix before the engine's first allocation,
the process is literally prevented from exceeding it: the over-budget allocation is refused inside
the process, and nothing observes a breach because none occurs. On the device, and on any lane that can only sample,
nothing prevents the allocation at all: the ceiling is the quantity a sampled footprint is compared
against, and a measured breach terminates the group and names the resource it breached together with
the footprint it observed. A contract that requires prevention refuses readiness on a lane offering
only detection, rather than accepting the weaker mechanism under the stronger word.

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
command overrides are absent. The execution shape the cache term was derived from travels inside
that same executable value onto the typed worker request, so the engine runs the context length,
batch, generation bound, and load strategy the compiler reasoned about instead of restating literals
of its own.

Enforcement is one ceiling installer plus one resource-parameterised sampling kernel, not one
implementation per platform. The installer is what differs between lanes; the kernel differs only in
which resource it reads:

- **the installer** — on the Linux lanes the engine starts behind a fixed public-tool launch prefix
  that lowers the soft and hard data-segment limit and then replaces itself with the engine image, so
  the ceiling binds before the first allocation and cannot be raised back by the process it binds. It
  is a closed constructor: its only free values are quantities rendered from indexed types, and the
  executable and argument vector come from the already-closed engine command, so neither a caller nor
  a manifest can supply an enforcement executable. `apple-silicon` installs nothing, because Darwin
  reports the address-space limit as infinite and rejects every finite ceiling written against it;
- **the backstop** — one sampling loop parameterised by the resource it observes: process-group
  physical footprint on `apple-silicon` through fixed, absolute `/usr/bin/top` and
  `/usr/bin/footprint` commands under one total deadline and bounded captures, process-group
  anonymous residency on the Linux lanes through `/proc`, and per-process device bytes through a
  fixed device query. No caller-supplied observer command and no direct FFI exist on any of the
  three. The polling interval belongs to this loop and to nothing else, because a prevented breach
  has no cadence — the kernel refuses the allocation at the instant it is made. Terminal procfs tasks
  are excluded from the live group; a no-live-member sample receives four fresh observations at that
  interval, reappearance resumes enforcement, and persistent absence completes normally only when the
  leader is terminal or absent. Stable-live or unreadable evidence remains typed fail-closed, and the
  loop never waits on the engine `ProcessHandle`, leaving one owner for reap;
- **conformance** — the engine reads its own installed limit back after the image is replaced and
  before it loads a weight, and reports it on the worker channel. A limit that was written and a
  limit the running image is bound by are two claims, and only the process that will allocate can
  make the second.

The pod cgroup on `linux-cpu` is a larger verified outer envelope covering the daemon, the admitted
child ceiling, and inter-sample overshoot; it is never the per-request breach classifier. On
`linux-gpu` a device-using model compiles two independently indexed grants from a
`DualEnforcedBudget`, refinement requires a live NVIDIA sampler plus a device envelope large enough
for the admitted device quantity, and the capped-engine kernel runs one backstop per grant. A pod
limit or a CUDA exit code is never accepted as device evidence: an unavailable sampler is
`NvidiaSamplerUnavailable` at refinement and `EngineEnforcementUnavailable` at run time. A
`linux-gpu` model that does *not* use the device stays on the host lane alone, because a device grant
it would never consume is not evidence of anything.

What each lane may declare is fixed by what it can install: `apple-silicon` declares detection,
`linux-cpu` and `linux-gpu` declare prevention over private writable mappings once their ceiling is
calibrated against a real engine on that lane and detection over the residue, and the device half
declares admission plus arena sizing plus detection everywhere. The per-lane table is owned by
[bounded_inference_memory.md](bounded_inference_memory.md).

If a mechanism cannot be verified at the strength the plan declares, refinement fails and the engine
member never becomes ready. A pod-wide capacity value or CUDA OOM classification is not evidence that
an individual model ceiling is enforced.

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

## Validation

The contract is proved by:

- reflected-schema tests reject flat/tagged representations and round-trip every
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
- runtime tests refuse readiness when the selected mechanism is absent, ineffective, or weaker than
  the strength the plan declares for its lane;
- the installed ceiling is proved by reading both its soft and hard values back inside the process
  the limit binds, after the image is replaced and before a weight is loaded, and comparing them with
  the quantity the plan installed; a limit that was written is a different claim from a limit the
  running image is bound by, and only the second is evidence;
- a lane claims prevention only where a real engine on that lane has been observed to refuse an
  over-budget allocation cleanly under an installed ceiling; without that observation the lane
  declares detection and the gate that would prove prevention is red;
- adversarial Apple, Linux CPU, and CUDA tests exceed each declared ceiling and observe a typed,
  terminal per-request failure naming the breached resource and the observed footprint, while the
  host and daemon remain alive;
- production `System.Process` use is confined to the bounded command, capped engine, fixed
  public-tool observer, and bounded provisioning kernels, plus the CLI-passthrough and host-tool
  surfaces that remain explicitly exempt;
- the raw-spawn exemption set remains narrow: every exempt module is named with its exact design
  decision, and whole-token matching includes `withCreateProcess`;
- the machine-independent gates plus the selected accelerator and `linux-cpu` gates pass.

## Cross-References

- [Configuration Doctrine](configuration_doctrine.md)
- [Bounded Inference Memory](bounded_inference_memory.md)
- [Managed State Transitions](managed_state_transitions.md)
- [Runtime Modes](runtime_modes.md)
- [Daemon Topology](daemon_topology.md)
- [Realness Contract](realness_contract.md)
