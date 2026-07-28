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
  and it extends to model-memory capacity through the typed execution plan: an over-capacity model
  remains `UnavailableModel` and its request must become a clean `status=failed`
  `InferenceError.ModelMemoryLimitExceeded` before any subprocess or worker launch. That normal
  coordinator result path passed the complete Phase 1 source-matched gate on 2026-07-25. The
  enforcement half and its remaining proof obligations are owned by
  [bounded_inference_memory.md](bounded_inference_memory.md).
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
maps non-zero exit / empty stdout / missing artifact to `failed`. That mapping fires only when the
subprocess actually exits or returns; model-memory capacity is therefore checked before launch by
the shared admission policy (see Current Status), which rejects an over-budget model as typed
`ModelMemoryLimitExceeded` rather than launching it. Within that scope, realness holds iff every adapter and
native runner has **no fabrication branch**:

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
| Haskell | `realnessFabricationViolations` in `src/Infernix/Lint/HaskellStyle.hs`, run under the `infernix-haskell-style` cabal test (`infernix test lint`), scoped via `realnessScopedFiles` (`Engines/LinuxNative.hs` landed under Phase 4; `Engines/AppleSilicon.hs` added under Phase 1) | the fabrication tokens `emit_fallback_result`, `infernix_emit_validation_result`, `native-validation`, `b64decode` (constant artifact), `native fallback` (`np.zeros` is *not* token-forbidden — real engines use it for scratch buffers; the fake-input pattern is a doctrine prohibition, not a token check) |
| Python | AST passes in `python/adapters/common.py` `run_check_code` (`poetry run check-code`) | **`python/adapters/*_python.py`**: `return` inside `except`, `bytes([...])` / `b64decode("...")` constant-artifact bytes, and `_validation_*` / `*_smoke*` / `*_fallback*` helper definitions. **`python/native-runners/*.py`**: the module-agnostic constant-artifact signals only (`bytes([...])` / decoded literal) — the name/except heuristics do not transfer because a native runner is a CLI with a legitimate `smoke` subcommand and fail-closed error-code `return`s; its realness otherwise rests on the exit-non-zero fail-closed structure plus review |
| Docs | `src/Infernix/Lint/Docs.hs` `forbiddenPhrases` | the retired fabrication-blessing wording in governed docs |

## Current Status

Real-output failure semantics remain implemented. Resource-exhaustion safety is a reopened sibling
contract: a real engine can still be launched under a descriptive Linux capacity that does not
enforce its individual grant. [Typed Execution Plan](typed_execution_plan.md) makes the resource
precondition part of executability, so an unenforced model is not routable.

The invariant is the governing contract now; its delivery is in flight under the reopened Phases:
**Phase 0** (the realness doctrine plus the machine-independent realness lint mechanism, Sprint 0.12),
**Phase 4** (the Linux adapter/runner de-stub — landed — plus the real Linux engines and Phase 4's own
real fixtures + fail-closed per-row tests), **Phase 6** (the fail-closed HA / service-loop assertions on
top), and **Phase 1** (real Apple native engines replacing the validation wrappers). Real output is attested per accelerator in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) —
Wave K (`linux-gpu` + `linux-cpu`) and Wave L (`apple-silicon` + `linux-cpu`) for their then-active
catalogs, with Wave O owning post-replacement proof for the MT3 rows added on 2026-06-30. A row whose
real engine is not yet landed is an explicit residual in `residualMatrixRowIdsForMode`, never a
fabricated pass.

**Reopened: realness-by-construction extends to typed resource admission.** Phase 4 Sprint 4.27,
Phase 5 Sprint 5.11, and Phase 6 Sprint 6.38 generalized the earlier Apple host-RAM guard into a DRY
admission doctrine across substrates. The Phase 1 capability correction now makes
`compileRuntimePlan` the only grant mint: a fitting placement carries `MemoryGrant resource`, while
an oversized configured model remains an explicit `UnavailableModel` with
`InferenceError.ModelMemoryLimitExceeded { modelId, requiredMib, availableMib, resource, source }`.
Package-owned live observations pair the grant with its matching enforcer inside
`ExecutableModel`; public engine launch accepts only that capability. The typed rejection is a
closed ADT branch in `ResultPayload`, not successful inline output or a parsed string, and must be
published without launching the engine while smaller compiled placements continue to run.

The **enforcement half** targets making an admitted request's actual resident memory and aggregate
execution authority incapable of causing a host OOM-kill. It is owned by
[bounded_inference_memory.md](bounded_inference_memory.md): compilation and live refinement create an
`ExecutableModel` carrying a matching resource-indexed grant/enforcer pair, and the package-internal
capped-engine kernel OS-bounds its `MemoryCeiling`, over a checked `HostMemoryPartition` with a
required `ModelMemoryFootprint` and an enforcer-typed budget. Phase 4 retains adversarial
Apple/Linux CPU proof and encapsulated serialization; Phase 6 retains GPU enforcement.

## Validation

- `infernix test lint` fails on any reintroduced fabrication (the Haskell + Python passes above).
- `./bootstrap/linux-gpu.sh test` and `./bootstrap/linux-cpu.sh test` pass only on real inference for
  the active catalog; withholding weights or the engine yields a visible `status=failed`. This
  fail-closed mapping covers engine-logic failures; model-memory capacity is additionally covered by
  typed resource admission, which rejects an over-budget request as `ModelMemoryLimitExceeded`
  before launch (Current Status; Phase 4 Sprint 4.27 + Phase 5 Sprint 5.11 + Phase 6 Sprint 6.38).
- `infernix lint docs` rejects the retired fabrication-blessing doc phrases.

## Cross-References

- [model_catalog.md](model_catalog.md) — the generated catalog and `ResultFamily` mapping.
- [../development/testing_strategy.md](../development/testing_strategy.md) — the test contract.
- [../development/python_policy.md](../development/python_policy.md) — the shared adapter quality gate.
- [../engineering/testing.md](../engineering/testing.md) — the canonical validation doctrine.
- [Managed State Transitions](managed_state_transitions.md) — the sibling doctrine that generalizes
  this contract from inference results to system state transitions.
- [bounded_inference_memory.md](bounded_inference_memory.md) — the enforcement half of the memory
  contract: an executable capability carries the matching indexed grant/enforcer pair; Phases 4 and
  6 own the remaining behavioral proof required to make a host OOM unrepresentable.
