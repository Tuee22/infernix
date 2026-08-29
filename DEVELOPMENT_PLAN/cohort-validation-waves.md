# Cohort Validation Waves

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md)

> **Purpose**: Operationalize Section Q of
> [development_plan_standards.md](development_plan_standards.md) by naming the per-accelerator
> validation gates that are **still open**. Phase docs reference an open wave instead of restating
> cohort residual narrative per sprint. Validation-only proof points that require a different
> physical host are queued here and do not trigger ad hoc machine switches outside their named wave.
> Each open wave runs in two stages: **Stage 1** lands the machine-independent code-side closure in
> natural phase order on whichever single machine is present, and **Stage 2** records the chosen
> accelerator plus `linux-cpu` full-suite evidence. No phase waits on both accelerators as one
> must-pass-together gate.

> **This file holds open gates only.** A wave that has closed is deleted, and the phase it validated
> simply reads `Done`. Per Section D the plan carries no history: a closed wave has no reader.

## Wave Table

| Wave | Phase / sprint | Stage 1: code-side closure | Stage 2: selected cohort gate |
|------|----------------|----------------------------|-------------------------------|
| 4.45 | Phase 4 Sprint 4.45 | Complete: governed Apple rebuild, aggregate lint, unit aggregate, 7 positive / 96 negative capability fixtures, 84/84 PureScript tests, standalone lints, and docs check pass | Partially complete: the current-source `linux-cpu` full suite passes aggregate lint, 7 positive / 96 negative capability fixtures, unit, integration, 84/84 PureScript, 16/16 routed Playwright, retained-state replay, and clean teardown. The selected `apple-silicon` full suite remains pending because no available validation host supplies a constructible native Apple lane; validation neither emulates Apple nor resizes or reprovisions Colima |

## Cadence Rule

Wave numbering operationalizes Section Q of
[development_plan_standards.md](development_plan_standards.md). The doctrinal rule is:

> A phase may stay `Active` with an explicit validation-only residual after code-side closure, but
> it cannot move to `Done` until its one chosen accelerator plus `linux-cpu` have supplied the
> required full-suite evidence. A validation-only residual is queued as a wave and does not require
> ad hoc machine switching before that wave is scheduled.

The operational form of that rule — identical to the copy in Section Q of
[development_plan_standards.md](development_plan_standards.md) — is:

> **Implement in natural phase order on whichever single machine is present, and validate each phase
> on exactly one accelerator plus `linux-cpu` — never both accelerators.** Every open phase has two
> independent axes. *Code-side closure* (Axis 1) is the implementation plus the machine-independent
> gate set — `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
> `infernix lint files/docs/chart/proto`, `infernix docs check`, the web unit suite, and
> `poetry run check-code`; completed in natural order on one machine, it is the gate to begin the
> *next* phase's implementation. *Single-accelerator sign-off* (Axis 2) is the hardware-specific
> full-suite for the phase's one chosen accelerator (`apple-silicon` Metal/Core ML, or `linux-gpu`
> CUDA) plus `linux-cpu`; it is the gate for `Done`. A phase never requires the other accelerator.
> Cross-accelerator contracts are split across sibling per-accelerator phases or merged by a later
> `linux-cpu`-only aggregation phase that re-runs no accelerator lane.

Waves enforce that boundary explicitly. Contributors and assistants land code on the locally
available cohort during the active wave and record only the phase's chosen accelerator plus
`linux-cpu` evidence for `Done`.

## Phase Cohort Disposition Index

| Phase | Current cohort disposition |
|-------|----------------------------|
| 0 | No accelerator cohort; machine-independent throughout, and it blocks no accelerator phase |
| 1 | No open disposition |
| 2 | No open disposition |
| 3 | No open disposition |
| 4 | Wave 4.45 open: code-side closure and current `linux-cpu` full suite complete; selected `apple-silicon` full suite pending on a host with a constructible native Apple lane |
| 5 | No open disposition |
| 6 | No open disposition |
| 7 | No open disposition |
| 8 | No open disposition |
| 9 | No open disposition |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
