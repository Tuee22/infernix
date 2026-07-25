# Typed Execution Plan

**Status**: Authoritative source
**Referenced by**: [configuration_doctrine.md](configuration_doctrine.md), [bounded_inference_memory.md](bounded_inference_memory.md), [managed_state_transitions.md](managed_state_transitions.md), [runtime_modes.md](runtime_modes.md), [../development/assistant_workflow.md](../development/assistant_workflow.md), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md)

> **Purpose**: Define the generated-Dhall execution language and runtime-evidence refinement that
> make an unbounded command, unenforced inference, or unroutable model structurally unrepresentable.

## TL;DR

- Generated Dhall describes a closed execution plan, not a bag of descriptive settings.
- Alternatives are Dhall unions mirrored by Haskell ADTs; text tags plus zeroed inapplicable fields
  are forbidden.
- Decoding proves structural validity. Runtime probes refine the decoded plan into opaque
  capabilities proving that the declared enforcer exists now.
- Routing consumes only compiled `ExecutableModel` values. Process launch consumes only a bounded
  command capability or a resource-indexed engine capability.
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
| Runtime refinement | `CompiledRuntimePlan` + live observations | `RuntimePlan` | unavailable cgroup controller, ineffective limit, unavailable Apple footprint probe, unavailable NVIDIA accounting, chart/config limit drift |
| Execution | `RuntimePlan` projections | total outcomes | raw unbounded command spawn, engine launch without a matching grant and enforcer, routing without an executable placement |

Dhall cannot prove a live OS fact. A Dhall alternative names the only permitted enforcement
mechanism; an opaque Haskell capability proves that the named mechanism was observed and installed.
Neither proof substitutes for the other.

## Closed Dhall Language

The reflected schema uses proper alternatives. The target memory shape is equivalent to:

```dhall
let HostPartition =
      { physicalMib : Natural
      , vmReserveMib : Natural
      , headroomMib : Natural
      }

let MemoryEnforcement =
      < ApplePhysicalFootprintWatchdog : HostPartition
      | LinuxCgroupV2PerInvocation : { cgroupRoot : Text }
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

Raw decoded records are confined to the configuration module. Runtime, routing, and worker modules
consume only a compiled plan:

```haskell
compileRuntimePlan
  :: RuntimeFacts
  -> RawRuntimeConfig
  -> Either ConfigErrors RuntimePlan
```

Compilation validates at least:

- every model has exactly one legal execution placement for the active runtime mode;
- every referenced pool and member exists and has a compatible location and resource class;
- CPU work cannot select a VRAM enforcer and GPU-required work cannot select a RAM-only enforcer;
- every positive model ceiling fits the declared capacity;
- a per-pod limit strategy cannot place multiple independently capped models in the same pod;
- chart-rendered limits and the mounted runtime plan agree;
- every routed model has a successfully refined executable capability.

`RuntimePlan` exposes a `Map ModelId ExecutableModel`, not a raw catalog. A model cannot enter the
active picker, routing table, or request subscription unless its placement compiled and its
enforcer refined successfully.

## Resource-Indexed Execution

Admission capacity and execution enforcement are distinct. Admission capacity answers whether work
may start; the execution ceiling is the exact quantity the launched process is prevented from
exceeding.

```haskell
launchEngine
  :: Enforcer resource
  -> MemoryGrant resource
  -> EngineCommand
  -> IO EngineOutcome
```

An Apple unified-memory grant cannot be consumed by a Linux cgroup enforcer; a VRAM grant cannot be
consumed by a RAM enforcer. Constructors for `Enforcer resource`, `MemoryGrant resource`, and
`ExecutableModel` remain hidden.

Substrate enforcement is:

- `apple-silicon`: a verified `proc_pid_rusage` physical-footprint watchdog and process-group kill;
- `linux-cpu`: a per-invocation delegated cgroup-v2 `memory.max`, or a compiler-validated
  one-model-per-pod placement whose pod limit equals that model's ceiling;
- `linux-gpu`: RAM enforcement as above plus verified per-process-group NVIDIA memory accounting
  for the declared VRAM ceiling.

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
```

Policies are keyed by semantic operations such as Kind create/delete, Helm upgrade, kubectl apply,
image pull/push, native-engine materialization, and engine smoke. The DSL does not accept arbitrary
executable strings. Absolute executables still come from the typed host manifest; arguments are
constructed by closed Haskell command ADTs.

Only `BoundedCommand command` reaches the command kernel. Provisioning and smoke work use a
separate `ProvisioningGrant` with a timeout, resident-memory ceiling, and output bound; they do not
receive a module-wide exemption from inference or command enforcement.

## Current Status

This doctrine is the target contract opened by the Typed Execution Plan refactor. Phase 1 Sprint
1.19 has landed the proper memory-budget union, opaque raw decode boundary, graph compiler,
`CompiledRuntimePlan` / `ExecutableModel`, and resource-indexed enforcer/grant core. Phase 2 Sprint
2.16 has migrated cluster lifecycle and image publication onto hidden-constructor
`BoundedCommand` values with closed operation, retry, and failure policies. The remaining
implementation does not yet satisfy the full contract:

- Linux execution relies on a pod-wide limit rather than enforcing each `MemoryGrant` ceiling;
- GPU VRAM does not have a verified per-process enforcer;
- engine materialization and smoke modules retain raw-spawn exemptions;
- routing consumes decoded model configuration before a single compiled/refined-plan boundary.

Implementation status and ordered closure gates live in
[DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md). Until those sprints close, existing
limits remain defense-in-depth, not proof that resource exhaustion is unrepresentable.

## Validation

The completed implementation must prove:

- reflected-schema tests reject the retired flat/tagged representation and round-trip every union;
- property tests reject zero quantities, incompatible resource/enforcer pairs, dangling graph
  references, oversubscription, chart/plan drift, and a routed model without `ExecutableModel`;
- negative compile fixtures cannot call routing or launch functions with raw configuration;
- runtime tests refuse readiness when the selected enforcer is absent or ineffective;
- adversarial Apple, Linux CPU, and CUDA tests exceed each declared ceiling and observe a typed,
  terminal per-request failure while the host and daemon remain alive;
- production `System.Process` imports are confined to the bounded command, capped engine, and
  bounded provisioning kernels;
- the raw-spawn lints have no production exemptions outside those kernels;
- the machine-independent gates and each owning phase's selected accelerator plus `linux-cpu` gate
  pass.

## Cross-References

- [Configuration Doctrine](configuration_doctrine.md)
- [Bounded Inference Memory](bounded_inference_memory.md)
- [Managed State Transitions](managed_state_transitions.md)
- [Runtime Modes](runtime_modes.md)
- [Daemon Topology](daemon_topology.md)
- [Realness Contract](realness_contract.md)
