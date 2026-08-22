# Realness Contract

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [model_catalog.md](model_catalog.md)

> **Purpose**: Define the code-level "realness by construction" invariant — an inference result is
> always real model output or a visible failure, never a fabricated value — and the lint that enforces
> it across every substrate.

## TL;DR

- The inference engine code is **structurally incapable** of returning a fabricated result. Every
  successful (`status=completed`) result is the output of a real model run; every missing-weights,
  model-load, or engine-runtime failure **raises / exits non-zero** and surfaces as `status=failed`.
  This is an *engine-logic* guarantee for in-band failures the adapter/runner can raise or exit on,
  and it extends to model-memory capacity in two places rather than one: an over-capacity model
  remains `UnavailableModel` and its request must become a clean `status=failed`
  `InferenceError.ModelMemoryLimitExceeded` before any subprocess or worker launch, **and an
  allocation refused by an installed ceiling inside a launched engine must become that same typed
  failure** rather than a generic non-zero exit. The enforcement half is owned by
  [bounded_inference_memory.md](bounded_inference_memory.md).
- **A capacity refusal, a fabrication, and an ordinary model bug are three different facts.** A
  failure mapping that collapses them reports the first as the third and leaves the second
  unfalsifiable, so realness depends on the memory classification being typed rather than inferred
  from an exit status.
- Tests therefore **trust the result** and assert only the per-family contract, failing closed on
  `failed`. Realness is a property of the engine code, not of the test.
- A lint (`realnessFabricationViolations` in `Infernix.Lint.HaskellStyle` plus the Python
  `check-code` AST pass) is a mechanical regression tripwire on a fixed set of named fabrication
  tokens and AST shapes. It catches the known fabrication patterns rather than proving the absence of
  every conceivable one; the invariant ultimately rests on the fail-closed engine code plus review.
- The [Managed State Transitions](managed_state_transitions.md) doctrine is the canonical home for
  generalizing this "real output or a visible failure" contract from inference results to system
  state transitions.

## The invariant

The single `status=completed` site (`src/Infernix/Runtime.hs`) is reached only on a real engine
`Right output`. `python/adapters/common.py` maps any adapter exception to `failed`; the Haskell worker
maps non-zero exit / empty stdout / missing artifact to a *generic* `failed`. Model-memory capacity is
checked before launch by the typed resource-admission policy below, which rejects an over-budget model
as typed `ModelMemoryLimitExceeded` rather than launching it.

Pre-launch admission is not the whole of it, because an installed ceiling changes the *shape* of the
dominant memory failure. Under a kernel limit that binds before the engine's first allocation, an
over-budget engine dies from **an allocation refused inside itself**, not from an external kill, and
that refusal arrives at the worker looking exactly like a model crash: a non-zero exit and no output.
The worker therefore classifies it as a typed memory failure that **names the resource it breached
and the footprint it observed**, using the ceiling the launch recorded and the limit the engine
reported back from inside the process that allocates. This classification is load-bearing for
realness rather than for tidiness: if a capacity refusal is indistinguishable from a bug, then "the
engine failed" stops being evidence about the engine, and the pressure to paper over an unexplained
non-zero exit with a synthesized result is exactly the pressure this contract exists to remove.
Within that scope, realness holds iff every adapter and native runner has **no fabrication branch**:

- **Adapter** (`python/adapters/*_python.py` via `common.py` `run_*_adapter`): the only success is
  `transform()` returning real model output. Forbidden: any `return` from an `except`; any
  substrate/device-conditional synthetic return; artifact bytes from a literal/base64 constant or by
  re-encoding the *input*; any `_validation_*` / `*_smoke*` / `*_fallback*` / `*_placeholder*` helper.
  `ImportError → raise` and `ModelCacheNotPopulated` propagation are allowed (both surface as a visible
  failure or bootstrap retry).
- **Native target** (the hidden Haskell catalog plus an upstream CLI, in-process Python runner, or
  JVM application): a success (exit 0) contains only real engine output or names the single
  descriptor-validated regular artifact written beneath the invocation-owned output directory.
  Every other case **exits non-zero** (no print-and-`exit 0`). Generated `bin/*` command wrappers are
  forbidden. Forbidden:
  hardcoded artifact/base64/MIDI/PNG/MusicXML constants, `np.zeros`→`session.run`, per-family default
  emits, failure-masking branches, and the `infernix_emit_validation_result` validation wrapper.
  Source-specific provisioning smoke operations are install-time only and never an inference result.

## Enforcement (lint)

| Surface | Mechanism | Forbids |
|---|---|---|
| Haskell | `realnessFabricationViolations` in `src/Infernix/Lint/HaskellStyle.hs`, run under the `infernix-haskell-style` cabal test (`infernix test lint`), scoped via `realnessScopedFiles` to `Engines/LinuxNative.hs` and `Engines/AppleSilicon.hs` | the fabrication tokens `emit_fallback_result`, `infernix_emit_validation_result`, `native-validation`, `b64decode` (constant artifact), `native fallback` (`np.zeros` is *not* token-forbidden — real engines use it for scratch buffers; the fake-input pattern is a doctrine prohibition, not a token check) |
| Python | AST passes in `python/adapters/common.py` `run_check_code` (`poetry run check-code`) | **`python/adapters/*_python.py`**: `return` inside `except`, `bytes([...])` / `b64decode("...")` constant-artifact bytes, and `_validation_*` / `*_smoke*` / `*_fallback*` helper definitions. **`python/native-runners/*.py`**: the module-agnostic constant-artifact signals only (`bytes([...])` / decoded literal) — the name/except heuristics do not transfer because a native runner is a CLI with a legitimate `smoke` subcommand and fail-closed error-code `return`s; its realness otherwise rests on the exit-non-zero fail-closed structure plus review |
| Docs | `src/Infernix/Lint/Docs.hs` `forbiddenPhrases` | the retired fabrication-blessing wording in governed docs |

## Resource Admission Is Part Of Realness

Realness-by-construction extends to typed resource admission: a real engine must not be launched
under a descriptive capacity that does not enforce its individual grant.
[Typed Execution Plan](typed_execution_plan.md) makes the resource precondition part of
executability, so an unenforced model is not routable.

`compileRuntimePlan` is the only grant mint. A fitting placement carries `MemoryGrant resource`,
while an oversized configured model remains an explicit `UnavailableModel` with
`InferenceError.ModelMemoryLimitExceeded { modelId, requiredMib, availableMib, resource, source }`.
Package-owned live observations pair the grant with its matching enforcer inside `ExecutableModel`,
and public engine launch accepts only that capability. The typed rejection is a closed ADT branch in
`ResultPayload` — not successful inline output and not a parsed string — and is published without
launching the engine, while smaller compiled placements continue to run.

The **enforcement half** removes an admitted request's actual resident memory and aggregate
execution authority as a cause of host exhaustion. It is owned by
[bounded_inference_memory.md](bounded_inference_memory.md): a requirement **derived from the
artifact's own bytes and the execution shape the engine will run under** mints one resource-indexed
grant per physical resource the placement consumes, live refinement pairs each grant with its
matching enforcer inside `ExecutableModel`, and the package-internal capped-engine kernel installs a
`MemoryCeiling` before the engine's first allocation on the lanes that can install one and samples
the residue that ceiling does not charge everywhere else — over a checked `HostMemoryPartition` with
a resource-indexed `ModelMemoryRequirement` derived from the model's own artifact and an
enforcer-typed budget. A lane carries the strength its
mechanism actually provides in its own type, so a lane that can only sample cannot present itself as
one that prevents, and a refusal on either lane names its resource.

A row is an explicit residual in `residualMatrixRowIdsForMode` only when its *achievability* is
uncertain. A row that is merely unbuilt stays declared-runnable and fails closed — never a
fabricated pass.

## Validation

- `infernix test lint` fails on any reintroduced fabrication (the Haskell + Python passes above).
- `./bootstrap/linux-gpu.sh test` and `./bootstrap/linux-cpu.sh test` pass only on real inference for
  the active catalog; withholding weights or the engine yields a visible `status=failed`. This
  fail-closed mapping covers engine-logic failures; model-memory capacity is additionally covered by
  typed resource admission, which rejects an over-budget request as `ModelMemoryLimitExceeded`
  before launch.
- The adversarial memory gate changes shape with the mechanism the lane has, and the two shapes prove
  different things. On a lane that installs a ceiling it is **attempt, then observe the refusal**: the
  gate drives a launched engine at an over-budget allocation and requires a clean typed
  `ModelMemoryLimitExceeded` naming the resource, a live daemon, and smaller placements still serving.
  On a lane that can only sample it remains **exceed, then observe the kill**, and the pass condition
  is that the sampled backstop terminated the group and produced the same typed failure rather than a
  `SIGKILL` reported as an engine bug. Neither shape may be satisfied by a fabricated result, which is
  why both assert the typed constructor rather than the absence of a crash.
- `infernix lint docs` rejects the retired fabrication-blessing doc phrases.

## Cross-References

- [model_catalog.md](model_catalog.md) — the generated catalog and `ResultFamily` mapping.
- [../development/testing_strategy.md](../development/testing_strategy.md) — the test contract.
- [../development/python_policy.md](../development/python_policy.md) — the shared adapter quality gate.
- [../engineering/testing.md](../engineering/testing.md) — the canonical validation doctrine.
- [Managed State Transitions](managed_state_transitions.md) — the sibling doctrine that generalizes
  this contract from inference results to system state transitions.
- [bounded_inference_memory.md](bounded_inference_memory.md) — the enforcement half of the memory
  contract: an executable capability carries the matching indexed grant/enforcer pair per physical
  resource; adversarial gates prove that an *admitted inference* cannot exceed its ceiling without a
  typed failure naming the resource it breached — by refusal where a ceiling is installed, and by the
  sampled backstop where one is not.
- [bounded_host_memory.md](bounded_host_memory.md) — the capacity ledger that inference is one row
  of, and the canonical statement of which host out-of-memory conditions are not bounded by any
  phase.
