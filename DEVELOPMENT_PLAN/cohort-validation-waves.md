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
| R6 | 6 | `linux-gpu` | `linux-cpu` | Sprints 6.55; `infernix test all` on both lanes | Code-side gates passed; full suites pending |
| R7 | 7 | `apple-silicon` | `linux-cpu` | Sprints 7.30–7.33; `infernix test all` on both lanes | Code-side gates passed; full suites pending |
| R8 | 8 | `apple-silicon` | `linux-cpu` | Sprints 8.15; `infernix test all` on both lanes | Code-side gates passed; full suites pending |
| R9 | 9 | `apple-silicon` | `linux-cpu` | Sprints 9.12; `infernix test all` on both lanes | Code-side gates passed; full suites pending |

All rows are open obligations, not scheduled or completed runs. The paired CPU lane is native arm64
or amd64 as recorded by the actual run; emulated Apple/Linux execution does not qualify. Hardware
sign-off remains independent from the next phase's implementation gate.

## Recorded Attestations

Append-only. One row per accelerator lane a phase closed on. Rows are never edited and never
deleted: this table is the artifact Section Q's `Done` cites, so a removed row retroactively
unsupports a status that still reads `Done`.

The table carries tuples, never prose. A cell holds an identifier, a lane name, a gate name, a
commit, or an outcome — the account of how a run went belongs to nothing in this plan.

| Phase | Accelerator | Gate | Commit | Outcome |
|-------|-------------|------|--------|---------|
| 1 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `0db34b0ee1ff47cc6868b1d59327179e66c47221` + uncommitted code-patch SHA-256 `e17b0176723d0c7c0876ec9dee86c9c3fcf610a5d0d6200565724dd73713f1c4` | PASS; exit 0 and 16/16 browser tests per lane |
| 4 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `0db34b0ee1ff47cc6868b1d59327179e66c47221` + uncommitted code-patch SHA-256 `e17b0176723d0c7c0876ec9dee86c9c3fcf610a5d0d6200565724dd73713f1c4` | PASS; exit 0 and 16/16 browser tests per lane |
| 6 | `linux-gpu` | `infernix test all` + native-amd64 `linux-cpu` full suite | `2687b50de9b9d4cdaa879e0421c3186e1c796331` + uncommitted code-patch SHA-256 `201533827a747598838260794ae7a1da02bbd6a0a805ef16929c278db3d84075` | PASS; exit 0 and 16/16 browser tests per lane |
| 8 | `linux-gpu` | `infernix test all` + native-amd64 `linux-cpu` full suite | `2687b50de9b9d4cdaa879e0421c3186e1c796331` + uncommitted code-patch SHA-256 `201533827a747598838260794ae7a1da02bbd6a0a805ef16929c278db3d84075` | PASS; exit 0 and 16/16 browser tests per lane |
| 9 | `linux-gpu` | `infernix test all` + native-amd64 `linux-cpu` full suite | `2687b50de9b9d4cdaa879e0421c3186e1c796331` + uncommitted code-patch SHA-256 `201533827a747598838260794ae7a1da02bbd6a0a805ef16929c278db3d84075` | PASS; exit 0 and 16/16 browser tests per lane |
| 1 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea`; source inventory SHA-256 `28dd0cd5e9468425669f19051cdd1deac58b658884ef771add4afe41f886dea0` | PASS; [Apple receipt](../.data/runtime/validation/run-KvlQcS/receipt.json); [Linux receipt](../.data/runtime/validation/run-vmpHdp/receipt.json); [source preimage](../.data/runtime/validation/run-KvlQcS/source/) |

| 2 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea`; source inventory SHA-256 `28dd0cd5e9468425669f19051cdd1deac58b658884ef771add4afe41f886dea0` | PASS; [Apple receipt](../.data/runtime/validation/run-KvlQcS/receipt.json); [Linux receipt](../.data/runtime/validation/run-vmpHdp/receipt.json); [source preimage](../.data/runtime/validation/run-KvlQcS/source/) |

| 3 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea`; source inventory SHA-256 `28dd0cd5e9468425669f19051cdd1deac58b658884ef771add4afe41f886dea0` | PASS; [Apple receipt](../.data/runtime/validation/run-KvlQcS/receipt.json); [Linux receipt](../.data/runtime/validation/run-vmpHdp/receipt.json); [source preimage](../.data/runtime/validation/run-KvlQcS/source/) |

| 2 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea` + uncommitted changes; Apple source inventory SHA-256 `d8c727ebd0a090e9a66f9acbc0557c08b31a62cb7d05dcb30a91cce3db05e55f`; Linux source inventory SHA-256 `99c79695898a695e84ac4c2884fd600c31f4a8137b3d1608b49b12c63d1465f6` | PASS; [Apple receipt](../.data/runtime/validation/run-BI4ZTC/receipt.json); [Linux receipt](../.data/runtime/validation/run-WneyCm/receipt.json) |

| 4 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea` + uncommitted changes; source inventory SHA-256 `41b02982c4d46e90196030ace41210a2dfb6c50973da0d0cfee4e22c776163d5` | PASS; [Apple receipt](../.data/runtime/validation/run-gSQPVS/receipt.json); [Linux receipt](../.data/runtime/validation/run-1F5B8L/receipt.json) |
| 5 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea` + uncommitted changes; source inventory SHA-256 `027ae4d21e98f40403485ebfed895fe4f1d59947b6fefc5bbc3c38028ed41c8b` | PASS; [Apple receipt](../.data/runtime/validation/run-jdRbDx/receipt.json); [Linux receipt](../.data/runtime/validation/run-P6BDqb/receipt.json); [source preimage](../.data/runtime/validation/run-jdRbDx/source/) |

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

The Wave Table is the sole open-cohort index. Phase 0 has no accelerator gate.
Phase status remains in [README.md](README.md#current-phase-overview).

Phase 7 has no retained closure tuple in Recorded Attestations. Its wave requires
recovery of authentic source and run artifacts or fresh runs. The historical rows are preserved
verbatim; their uncommitted-patch digests require the retained patch preimages to be reproducible,
and the rows do not establish that the new remediation criteria passed.

For new closure evidence, retain the execution receipt and referenced artifacts outside this plan, and append a compact tuple linking them here. Record the executable or image, configuration, lane and device context, required checks, outcomes, and artifact digests. Agents rebuild packages and images as appropriate before testing each lane. A skipped required check or missing artifact blocks closure. Receipt consistency depends on trust in the runner and artifact provenance described by Section Q.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
