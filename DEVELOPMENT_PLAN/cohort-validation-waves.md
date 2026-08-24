# Cohort Validation Waves

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md),
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
| AC | Apple Silicon (`apple-silicon` + `linux-cpu`) | Phase 4 Sprints 4.37 through 4.42 — Bounded Engine Launch, host half |
| AD | CUDA Linux (`linux-gpu` + `linux-cpu`) | Phase 6 Sprint 6.51 — Bounded Engine Launch, device half calibration |

Scheduling follows numerical phase order: Wave AC is the first open execution gate, and Wave AD
cannot run until Phase 4 closes. Wave AC is code-side closed and awaits its Apple run; Wave AD
retains its own device-side correction and observations.

## Wave AC: Bounded Engine Launch, Host Half (Open)

**Machine**: the Apple accelerator plus its paired `linux-cpu` lane, which is Phase 4's existing
selected accelerator. This wave does not select `linux-gpu`, and Section Q forbids it from doing so:
the device half of the same architecture is a separate contract with its own wave below.

**Scope**: Phase 4 Sprints 4.37 through 4.42 — the resource-tagged breach, the resource-indexed
requirement, derivation from artifact bytes, the one sampling kernel, the installed ceiling, and the
execution shape reaching the engine.

**What this wave must prove, beyond an ordinary green run**:

1. The installed ceiling is read back from inside the process it binds, after the process image is
   replaced and before a weight loads, and both the soft and hard values equal what the plan
   installed. Setting a limit and fitting under it are different claims, and only the second is
   evidence.
2. A requirement derived from an artifact's own bytes matches the artifact exactly, and a malformed
   header yields no requirement rather than a small one.
3. A measured breach names the resource it breached and reports an observation strictly above the
   ceiling. Reporting the ceiling back is the defect, not the evidence.
4. On the Apple lane the outcome is a *declared* detection-only lane rather than a failure: that lane
   installs no kernel ceiling by construction, and proving it says so is the deliverable.
5. On the Linux CPU lane an uncalibrated declaration remains detection-only, a prevention-required
   readiness contract refuses it, and only the real-engine calibration observation can promote the
   declaration.

**What this wave explicitly does NOT prove.** Nothing about device memory. No lane's claim to
prevention is established for `linux-gpu` here, and no result here substitutes for the device wave.

**Status**: Open. Code-side closure is complete: `linux-cpu` prevention is calibration-gated, the
production readiness consumer refuses weaker strength when prevention is required, and the carried
execution shape reaches the native engine. The current `linux-cpu` full suite passes with real
native output, fail-closed unsupported artifacts, durable throughput, lifecycle reconciliation, and
the routed browser matrix. The required Apple Silicon host is not reachable from the current
machine, and Section Q forbids substituting `linux-gpu` for the accelerator this phase selected. The
Apple lane must resolve detection-only with artifact-alone provenance against the current code
state; repeat `linux-cpu` only if implementation changes first.

**One property this wave must read carefully.** Sprint 4.39's derivation admits only the rows whose
checkpoint header the two landed readers understand — safetensors and GGUF — and retains every other
row as an explicit unavailable placement naming the artifact family whose reader is absent. A run
that reports most of the catalog refused is this wave working, not this wave failing, and the
distinguishing evidence is the refusal's own shape: a `ModelRequirementUnderivable` payload naming
the family and the reason is the declared outcome, while a `ModelMemoryLimitExceeded` payload on a
row that should have derived cleanly is not.

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

**Status**: Open. Sprint 6.51 first needs the device-backstop code correction; this wave then runs
Linux GPU host-ceiling calibration and device-peak remeasurement, neither of which an ordinary green
run performs. It follows the Phase 4 host half.

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
| 4 | Open: the Bounded Engine Launch host half, Sprints 4.37 through 4.42, under Wave AC |
| 5 | No open disposition |
| 6 | Open: Sprint 6.51's device-backstop correction, Linux GPU host-ceiling calibration, and device-peak remeasurement under Wave AD |
| 7 | No open disposition |
| 8 | No open disposition |
| 9 | No open disposition |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
