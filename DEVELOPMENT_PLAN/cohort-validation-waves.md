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
| R7 | 7 | `apple-silicon` | `linux-cpu` | Sprints 7.30–7.33; `infernix test all` on both lanes | Code-side gates passed; full suites pending |
| R8 | 8 | `apple-silicon` | `linux-cpu` | Sprints 8.15; `infernix test all` on both lanes | Code-side gates passed; full suites pending |
| R9 | 9 | `apple-silicon` | `linux-cpu` | Sprints 9.12; `infernix test all` on both lanes | Code-side gates passed; full suites pending |

All rows are open obligations, not scheduled or completed runs. The paired CPU lane is native arm64
or amd64 as recorded by the actual run; emulated Apple/Linux execution does not qualify. Hardware
sign-off remains independent from the next phase's implementation gate.

## Recorded Attestations

Retain one row per accelerator lane a phase closed on. Preserve historical attestation facts;
correct errors transparently. Machine-local receipt paths are optional references, not required
for a fresh checkout.

The table carries tuples, never prose. A cell holds an identifier, a lane name, a gate name, a
commit, or an outcome — the account of how a run went belongs to nothing in this plan.

| Phase | Accelerator | Gate | Commit | Outcome |
|-------|-------------|------|--------|---------|
| 1 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `0db34b0ee1ff47cc6868b1d59327179e66c47221` + uncommitted code-patch SHA-256 `e17b0176723d0c7c0876ec9dee86c9c3fcf610a5d0d6200565724dd73713f1c4` | PASS; exit 0 and 16/16 browser tests per lane |
| 4 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `0db34b0ee1ff47cc6868b1d59327179e66c47221` + uncommitted code-patch SHA-256 `e17b0176723d0c7c0876ec9dee86c9c3fcf610a5d0d6200565724dd73713f1c4` | PASS; exit 0 and 16/16 browser tests per lane |
| 6 | `linux-gpu` | `infernix test all` + native-amd64 `linux-cpu` full suite | `2687b50de9b9d4cdaa879e0421c3186e1c796331` + uncommitted code-patch SHA-256 `201533827a747598838260794ae7a1da02bbd6a0a805ef16929c278db3d84075` | PASS; exit 0 and 16/16 browser tests per lane |
| 8 | `linux-gpu` | `infernix test all` + native-amd64 `linux-cpu` full suite | `2687b50de9b9d4cdaa879e0421c3186e1c796331` + uncommitted code-patch SHA-256 `201533827a747598838260794ae7a1da02bbd6a0a805ef16929c278db3d84075` | PASS; exit 0 and 16/16 browser tests per lane |
| 9 | `linux-gpu` | `infernix test all` + native-amd64 `linux-cpu` full suite | `2687b50de9b9d4cdaa879e0421c3186e1c796331` + uncommitted code-patch SHA-256 `201533827a747598838260794ae7a1da02bbd6a0a805ef16929c278db3d84075` | PASS; exit 0 and 16/16 browser tests per lane |
| 1 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea`; source inventory SHA-256 `28dd0cd5e9468425669f19051cdd1deac58b658884ef771add4afe41f886dea0` | PASS; `Apple receipt`; `Linux receipt`; `source preimage` |

| 2 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea`; source inventory SHA-256 `28dd0cd5e9468425669f19051cdd1deac58b658884ef771add4afe41f886dea0` | PASS; `Apple receipt`; `Linux receipt`; `source preimage` |

| 3 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea`; source inventory SHA-256 `28dd0cd5e9468425669f19051cdd1deac58b658884ef771add4afe41f886dea0` | PASS; `Apple receipt`; `Linux receipt`; `source preimage` |

| 2 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea` + uncommitted changes; Apple source inventory SHA-256 `d8c727ebd0a090e9a66f9acbc0557c08b31a62cb7d05dcb30a91cce3db05e55f`; Linux source inventory SHA-256 `99c79695898a695e84ac4c2884fd600c31f4a8137b3d1608b49b12c63d1465f6` | PASS; `Apple receipt`; `Linux receipt` |

| 4 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea` + uncommitted changes; source inventory SHA-256 `41b02982c4d46e90196030ace41210a2dfb6c50973da0d0cfee4e22c776163d5` | PASS; `Apple receipt`; `Linux receipt` |
| 5 | `apple-silicon` | `infernix test all` + native-arm64 `linux-cpu` full suite | `64b4126f9390eaa1737939be4cdafcdf5a69d9ea` + uncommitted changes; source inventory SHA-256 `027ae4d21e98f40403485ebfed895fe4f1d59947b6fefc5bbc3c38028ed41c8b` | PASS; `Apple receipt`; `Linux receipt`; `source preimage` |

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

Phase 7 has no closure tuple in Recorded Attestations. Its wave requires a reliable record of
the required checks or fresh runs; existing rows do not establish that its remediation criteria passed.

For new closure evidence, append a compact attestation recording the tested source or build, lane and device context, checks performed, and outcomes. Agents rebuild packages and images as appropriate before testing each lane. A skipped required check blocks closure. Detailed receipts and logs are optional after the run; an attestation depends on trust in the runner.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
| 6 | `linux-gpu` | `infernix test all` + native-amd64 `linux-cpu` full suite | `97c560d1d83fa6ff75a68eb004e47c51ff0e092f` + uncommitted changes; code-patch SHA-256 `ff1374ea88b3edb4e47794aa2c9bf5e00083fb48532366235fa8bb52eccbd155` | PASS; exit 0 per lane; GPU run `run-9xWddG` (Integration, Browser, NvidiaValidation passed); CPU run `run-lxzVpV` (Integration, Browser passed); code-side gates `lint files/docs/chart/proto`, `docs check`, `test lint`, `test unit` exit 0 |
