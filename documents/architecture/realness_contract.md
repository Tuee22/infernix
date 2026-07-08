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
  and on `apple-silicon` — where every model runs on the on-host `infernix service` daemon rather than
  an in-cluster engine pod — it now also covers *host memory*: an over-budget model is
  admission-rejected as a clean `status=failed` before its subprocess is launched, so peak resident
  memory is bounded to one admitted model and the daemon is never OS-OOM-killed. See Current Status for
  the memory-admission contract.
- Tests therefore **trust the result** and assert only the per-family contract, failing closed on
  `failed`. Realness is a property of the engine code, not of the test.
- A lint (`realnessFabricationViolations` in `Infernix.Lint.HaskellStyle` plus the Python
  `check-code` AST pass) makes the invariant mechanical so it cannot regress.

## The invariant

The single `status=completed` site (`src/Infernix/Runtime.hs`) is reached only on a real engine
`Right output`. `python/adapters/common.py` maps any adapter exception to `failed`; the Haskell worker
maps non-zero exit / empty stdout / missing artifact to `failed`. That mapping fires only when the
subprocess actually exits or returns; the one failure mode it could not catch — a host-memory OOM that
SIGKILLs the on-host `apple-silicon` daemon before any exit code exists — is now prevented up front by
RAM admission control (see Current Status), which rejects an over-budget model as a clean
`status=failed` rather than launching it. Within that scope, realness holds iff every adapter and
native runner has **no fabrication branch**:

- **Adapter** (`python/adapters/*_python.py` via `common.py` `run_*_adapter`): the only success is
  `transform()` returning real model output. Forbidden: any `return` from an `except`; any
  substrate/device-conditional synthetic return; artifact bytes from a literal/base64 constant or by
  re-encoding the *input*; any `_validation_*` / `*_smoke*` / `*_fallback*` / `*_placeholder*` helper.
  `ImportError → raise` and `ModelCacheNotPopulated` propagation are allowed (both surface as a visible
  failure or bootstrap retry).
- **Native runner** (`src/Infernix/Engines/{LinuxNative,AppleSilicon}.hs` generated shell): a success
  (exit 0) prints only a real engine continuation or `infernix-native-artifact-file:<path>` for a file
  the real binary just wrote. Every other case **exits non-zero** (no print-and-`exit 0`). Forbidden:
  hardcoded artifact/base64/MIDI/PNG/MusicXML constants, `np.zeros`→`session.run`, per-family default
  emits, failure-masking branches, and the `infernix_emit_validation_result` validation wrapper. The
  `--smoke` probes are install-time only and never an inference result.

## Enforcement (lint)

| Surface | Mechanism | Forbids |
|---|---|---|
| Haskell | `realnessFabricationViolations` in `src/Infernix/Lint/HaskellStyle.hs`, run under the `infernix-haskell-style` cabal test (`infernix test lint`), scoped via `realnessScopedFile` (`Engines/LinuxNative.hs` landed under Phase 4; `Engines/AppleSilicon.hs` added under Phase 1) | the fabrication tokens `emit_fallback_result`, `infernix_emit_validation_result`, `native-validation`, `b64decode` (constant artifact), `native fallback` (`np.zeros` is *not* token-forbidden — real engines use it for scratch buffers; the fake-input pattern is a doctrine prohibition, not a token check) |
| Python | AST pass in `python/adapters/common.py` `run_check_code` (`poetry run check-code`) | `return` inside `except`, `ArtifactResult(data=bytes([...]))` / `b64decode("...")`, and `_validation_*` / `*_smoke*` / `*_fallback*` helper definitions |
| Docs | `src/Infernix/Lint/Docs.hs` `forbiddenPhrases` | the retired fabrication-blessing wording in governed docs |

## Current Status

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

**Resolved: realness-by-construction extended to host memory (apple-silicon).** The one remaining
non-clean failure mode — a host-memory OOM that SIGKILL'd the on-host `apple-silicon` daemon instead of
mapping to `status=failed` — is now closed by construction (Phase 4 Sprint 4.26; memory-bounded
validation lane Phase 6 Sprint 6.37). On `apple-silicon` there are still no in-cluster engine pods:
every active model runs on the on-host `infernix service` daemon, serialized one model at a time as a
fresh subprocess. Four mechanisms now bound peak resident memory to a single admitted model:

- **Per-model footprint.** `ModelDescriptor` (`src/Infernix/Types.hs`) carries
  `modelRamFootprintMib`, a conservative peak host-resident footprint (MiB) for one serialized
  inference on the unified-memory / CPU path; `src/Infernix/Models.hs`
  `conservativeRamFootprintMibForRow` assigns it per family/engine, biased high until a measured
  peak-RSS pass refines it.
- **Per-substrate budget.** `DemoConfig` (`src/Infernix/Types.hs`) carries `inferenceRamBudgetMib`,
  resolved at materialization by `src/Infernix/DemoConfig.hs` `resolveInferenceRamBudgetMib`: on
  `apple-silicon` it is host physical RAM (`sysctl -n hw.memsize`) minus the colima VM pledge
  (`colima list --json`) minus a host reserve; on `linux-cpu` / `linux-gpu` it records the engine pod
  memory limit (informational — Linux engines run in Kubernetes-bounded pods, so host-RAM admission
  does not fire there).
- **Config-time hard-fail.** `validateDemoConfig` fails fast on an over-budget `apple-silicon`
  config: any model whose `modelRamFootprintMib` exceeds `inferenceRamBudgetMib` is a typed error
  naming the model, footprint, and budget. Enforced only on `apple-silicon` (where model memory is
  host RAM); a non-positive budget means unenforced.
- **Serialized admission control.** The daemon runs one inference at a time under a single MVar
  (`engineExecutionLock`, `src/Infernix/Runtime/Daemon.hs`). Inside that critical section,
  `src/Infernix/Runtime/Pulsar.hs` `overRamBudgetRejection` runs *before* the engine subprocess is
  launched: an over-budget model publishes a clean `status=failed` (a real `InferenceResult`, not a
  fabrication) instead of being launched. Because execution is serialized, peak resident memory is
  bounded to one admitted model, so the OS never OOM-kills the daemon.

Together these make an over-budget model a clean, mapped `status=failed` — the same fail-clean
guarantee the engine-logic invariant gives, now extended to host memory as realness-by-construction.
The single-accelerator sign-off (the full-catalog apple `infernix test integration` run + routed
matrix completing or failing-closed per row with zero OS OOM-kill) is tracked as Wave R in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).

## Validation

- `infernix test lint` fails on any reintroduced fabrication (the Haskell + Python passes above).
- `./bootstrap/linux-gpu.sh test` and `./bootstrap/linux-cpu.sh test` pass only on real inference for
  the active catalog; withholding weights or the engine yields a visible `status=failed`. This
  fail-closed mapping covers engine-logic failures; on `apple-silicon`, host-memory exhaustion is
  additionally covered by RAM admission control, which rejects an over-budget model as a clean
  `status=failed` rather than letting the OS SIGKILL the daemon (Current Status; Phase 4 Sprint 4.26 +
  Phase 6 Sprint 6.37).
- `infernix lint docs` rejects the retired fabrication-blessing doc phrases.

## Cross-References

- [model_catalog.md](model_catalog.md) — the generated catalog and `ResultFamily` mapping.
- [../development/testing_strategy.md](../development/testing_strategy.md) — the test contract.
- [../development/python_policy.md](../development/python_policy.md) — the shared adapter quality gate.
- [../engineering/testing.md](../engineering/testing.md) — the canonical validation doctrine.
