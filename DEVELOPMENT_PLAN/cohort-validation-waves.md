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

| Wave | Phase | Chosen accelerator | Paired lane | Gate | State |
|------|-------|--------------------|-------------|------|-------|
| 6.1 | 6 | `linux-gpu` | `linux-cpu` | current-source `infernix test all` on both lanes after the fixed-observer correction and entry-document cleanup | Stage 2 validation-only: Apple and current-source native-arm64 CPU build, aggregate lint, all six Haskell unit components, and 86 web tests pass; standalone documentation gates pass. CPU full suite: INCOMPLETE, user-requested interruption during live integration, exit 1, no browser result, test cluster absent. A complete CPU rerun remains; selected `linux-gpu` sign-off requires access to a native CUDA host |
| 8.1 | 8 | `linux-gpu` | `linux-cpu` | current-source `infernix test all` on both lanes after the decoded role-contract split | Stage 2 validation-only: code-side closure passes the governed Apple build, native-arm64 `linux-cpu` build and unit suite, standalone gates, and routed `linux-cpu` integration; selected `linux-gpu` and paired full-suite sign-off remain |
| 9.1 | 9 | `linux-gpu` | `linux-cpu` | current-source `infernix test all` on both lanes after the application-owned admin-rendering correction | Stage 2 validation-only: code-side closure passes the native-arm64 `linux-cpu` build and unit suite, standalone gates, and routed `linux-cpu` browser suite; selected `linux-gpu` and paired full-suite sign-off remain |

Wave 6.1's current code identity is base commit `0db34b0ee1ff47cc6868b1d59327179e66c47221`
plus uncommitted code-patch SHA-256
`5364ba70092a95335e1675c53fca6eea5ad144a0e905a2885c6f46f03ddff8f7` over
`docker/Dockerfile`, `src/Infernix/Engines/Provisioning.hs`, `src/Infernix/Lint/Docs.hs`,
`test/unit/Spec.hs`, and `test/haskell-style/Spec.hs`. Its native-arm64 CPU image is
`sha256:eaba04e0865efd85d5203fe033bf2f3401505493218b4770a5cea2b1c8328577`.
This identifies partial validation and is not a closed-phase attestation.

## Recorded Attestations

Append-only. One row per accelerator lane a phase closed on. Rows are never edited and never
deleted: this table is the artifact Section Q's `Done` cites, so a removed row retroactively
unsupports a status that still reads `Done`.

The table carries tuples, never prose. A cell holds an identifier, a lane name, a gate name, a
commit, or an outcome — the account of how a run went belongs to nothing in this plan.

| Phase | Accelerator | Gate | Commit | Outcome |
|-------|-------------|------|--------|---------|
| — | — | — | — | No attestation is recorded. Phases 1-9 closed before this table existed and are not re-validated; their evidence is the git history of the sprints that closed them. |
| 1 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `0db34b0ee1ff47cc6868b1d59327179e66c47221` + uncommitted code-patch SHA-256 `e17b0176723d0c7c0876ec9dee86c9c3fcf610a5d0d6200565724dd73713f1c4` | PASS; exit 0 and 16/16 browser tests per lane |
| 4 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `0db34b0ee1ff47cc6868b1d59327179e66c47221` + uncommitted code-patch SHA-256 `e17b0176723d0c7c0876ec9dee86c9c3fcf610a5d0d6200565724dd73713f1c4` | PASS; exit 0 and 16/16 browser tests per lane |

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
| 1 | Closed on `apple-silicon` plus native-arm64 `linux-cpu`; see Recorded Attestations |
| 2 | No open disposition |
| 3 | No open disposition |
| 4 | Closed on `apple-silicon` plus native-arm64 `linux-cpu`; see Recorded Attestations |
| 5 | No open disposition |
| 6 | Wave 6.1 Stage 2: fixed-observer and entry-document cleanup code-side gates pass on Apple and native-arm64 CPU; the interrupted CPU full suite requires a complete rerun, and selected `linux-gpu` validation requires native CUDA host access |
| 7 | No open disposition |
| 8 | Wave 8.1 Stage 2: code-side closure passes the governed Apple build, native-arm64 `linux-cpu` build and unit suite, standalone gates, and routed `linux-cpu` integration; selected current-source `linux-gpu` plus paired `linux-cpu` full-suite sign-off remains |
| 9 | Wave 9.1 Stage 2: code-side closure passes the native-arm64 `linux-cpu` build and unit suite, standalone gates, and routed browser suite; selected current-source `linux-gpu` plus paired `linux-cpu` full-suite sign-off remains |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
