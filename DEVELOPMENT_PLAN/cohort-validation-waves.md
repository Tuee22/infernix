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

| Wave | Machine | Scope |
|------|---------|-------|
| AD | CUDA Linux (`linux-gpu` + `linux-cpu`) | Phase 6 Sprint 6.51 — Bounded Engine Launch, device half calibration |

Wave AD is the first open execution gate. Its device-side correction and machine-independent gate
set are complete. A current native arm64 `linux-cpu` full suite passes through the supported
Apple/Colima launcher; the paired CUDA-host cohort observations remain.

## Wave AD: Bounded Engine Launch, Device Half (Open)

**Machine**: a CUDA-capable Linux host, `linux-gpu` plus its paired `linux-cpu` lane — Phase 6's
existing selected accelerator.

**Scope**: Phase 6 Sprint 6.51 — device admission, arena sizing from the admitted quantity, the device
observer re-scoped as a backstop, and the calibration pass that decides whether any lane may claim
prevention.

**What this wave must prove, beyond an ordinary green run**:

1. A device-using row's arena is sized from the quantity it was admitted against rather than from the
   size of the installed card, and its observed device peak sits inside that quantity.
2. The calibration observation itself: a real engine started under an installed ceiling, its device
   runtime initialized, and an over-budget allocation refused cleanly rather than ending the process
   tree. This is the observation that decides whether a lane may declare prevention at all.
3. A competing tenant on the same device changes what is available without changing what is admitted,
   and that difference is observed inside the lock rather than assumed.

**What this wave explicitly does NOT prove.** That device memory is kernel-bounded. It is not, on any
lane; the device half is admission, arena sizing, and detection, and a green run here must not be read
as establishing a bound the mechanism cannot provide.

**Status**: Open. Sprint 6.51's correction and machine-independent validation are complete. This wave
runs Linux GPU host-ceiling calibration, device-peak remeasurement, the competing-tenant refusal,
and current `linux-gpu` plus its paired CUDA-host `linux-cpu` full suites; the first three are
observations an ordinary green run does not make. The current native arm64 `linux-cpu` full suite is
green, including integration, recovery, real-output, and 16/16 routed Playwright coverage, but it
ran through Apple/Colima and therefore does not replace the wave's same-host paired lane.

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
| 4 | No open disposition |
| 5 | No open disposition |
| 6 | Open: Sprint 6.51 is code-side closed and a current native arm64 `linux-cpu` supporting suite passes; Linux GPU host-ceiling calibration, device-peak remeasurement, competing-tenant refusal, and current `linux-gpu` plus paired CUDA-host `linux-cpu` suites remain under Wave AD |
| 7 | No open disposition |
| 8 | No open disposition |
| 9 | No open disposition |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
