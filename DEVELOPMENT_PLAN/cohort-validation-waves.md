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
> Closed evidence is retained as a row in Recorded Attestations.

> **Open gates are deleted on close; the evidence they produced is not.** A wave that has closed
> leaves the Wave Table, and its accelerator evidence is appended to Recorded Attestations as a
> row. Section D keeps the narrative that produced a closure out of the plan; it does not delete
> the tuple a `Done` rests on, because a status whose evidence has been destroyed cannot be
> checked by anyone.

## Wave Table

No cohort validation waves are open.

## Recorded Attestations

Append-only. One row per accelerator lane a phase closed on. Rows are never edited and never
deleted: this table is the artifact Section Q's `Done` cites, so a removed row retroactively
unsupports a status that still reads `Done`.

The table carries tuples, never prose. A cell holds an identifier, a lane name, a gate name, a
commit, or an outcome — the account of how a run went belongs to nothing in this plan.

| Phase | Accelerator | Gate | Commit | Outcome |
|-------|-------------|------|--------|---------|
| — | — | — | — | No attestation is recorded. Phases 1-9 closed before this table existed and are not re-validated; their evidence is the git history of the sprints that closed them. |

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
| 6 | No open disposition |
| 7 | No open disposition |
| 8 | No open disposition |
| 9 | No open disposition |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
