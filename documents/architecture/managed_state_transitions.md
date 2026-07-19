# Managed State Transitions

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md), [realness_contract.md](realness_contract.md), [../development/haskell_style.md](../development/haskell_style.md), [../engineering/storage_and_state.md](../engineering/storage_and_state.md)

> **Purpose**: Define the code-level "evidence, not hope" invariant — every operation that acts on a
> system state consumes typed evidence that the state's transition actually completed — so that races
> and flakes (unmanaged state transitions) are structurally unrepresentable.

## TL;DR

- A **flake is an unmanaged state transition**: code that observes or acts on a system state `S` on
  hope — a fixed timeout, a proxy signal, a derived value, a residue, a readiness sentinel written
  without proof, a filesystem scrub against a still-live writer — rather than on a value that could
  only exist if `S` had truly been reached.
- The invariant: for every state `S` there is a transition `T` that reaches it and typed **evidence
  `E(S)`** that witnesses it. Every operation that acts on `S` **requires** `E(S)` as an argument, and
  the only producer of `E(S)` is the real transition `T`. Acting on a state whose transition was never
  managed does not typecheck.
- This is the same shape as the [realness contract](realness_contract.md) — "real output or a visible
  failure" — generalized from inference **results** to state **transitions**. The typed
  [per-substrate memory admission](runtime_modes.md) (`EnforcedMemoryBudget` /
  `ModelMemoryLimitExceeded`, a closed ADT rather than integer sentinels) is the in-repo precedent this
  doctrine generalizes.
- Enforcement rides on **GHC module export lists plus `-Wall -Werror`** — the sound, compile-checked
  lever. The governed lints are line-based and cannot see scope; the type system does.

## The law

For every state `S`: a transition `T` reaches it, evidence `E(S)` witnesses it. Evidence has two kinds.

- **Monotone (latching) states** — once true, stay true (`ModelBootstrapReady`, `PayloadVerified`,
  `DemoBucketsProvisioned`, `HarborRegistryReady`). Evidence is an **opaque newtype with a hidden
  constructor**, minted by exactly one honest transition that consumes a real artifact. Provenance is
  truth here because the property never un-happens.
- **Revocable (leased) states** — can lapse after `T` (`WriterQuiesced`, `AdminTokenValid`,
  `ClusterReachable`, `StsLive`, a held lock). Evidence is a **rank-2 region lease**
  `withLease :: Acquire p -> (forall s. Lease s p -> IO r) -> IO r` whose `forall s.` region tag makes
  the evidence inseparable from the scope in which the runtime actively holds the condition — it cannot
  be returned, stashed, or mixed across regions. A capability that must be spent exactly once is
  additionally consumed linearly (`%1 ->`) so it cannot be reused after it is spent.

The raw destructive, commit, and spawn primitives are **not exported**; the only public path takes
evidence:

- the retained-state scrub takes a `WriterQuiesced` lease, so a scrub against a live writer is not a
  constructible term;
- the readiness-sentinel commit takes a `PayloadVerified`, so a sentinel written without proof does not
  typecheck;
- process execution takes a total `SubprocessEnv` — `HOME` and `TMPDIR` are required fields behind a
  hidden constructor, so an empty or minimal environment is unbuildable — and returns a total
  `CommandOutcome` (`CommandSucceeded | CommandFailedTransient | CommandFailedFatal | CommandTimedOut`),
  retiring the success-or-fatal collapse and making an unbounded exec unrepresentable.

Readiness waits **return evidence**, generalizing the `HarborBootstrapOutcome` pattern: a value proving
`S`, or a total not-ready / expired outcome carrying progress, with the **deadline as a required data
field**. A client deadline is derived from its server ceiling in one definition, so a client that waits
less than the server can take is not expressible. Cluster lifecycle is a typed `ClusterLifecycle`
machine — a closed sum with a consumed, resumable phase — replacing the `clusterPresent :: Bool` plus
`lifecyclePhase :: String` pair; its persistence is a **fail-closed** versioned codec, so an
unrecognized on-disk document blocks a destructive action instead of decoding to a silent "absent".

## Enforcement

| Surface | Mechanism | Forbids |
|---|---|---|
| Types | GHC module export lists (opaque types, hidden constructors) under `-Wall -Werror` | constructing evidence outside its minting module; acting on a state without its evidence value; an unbounded or unclassified command outcome |
| Region | rank-2 `forall s.` lease scope, plus surgical `LinearTypes` (`%1 ->`) for spend-once capabilities | using revocable evidence outside the scope that holds the condition; reusing a spent capability |
| Haskell | `Infernix.Lint.HaskellStyle` escape-token check | `unsafeCoerce` / `unsafePerformIO` in the evidence modules (the two escapes types cannot close) |

Two residual review-obligations remain and are minimized to a small audit surface: **probe honesty**
(each evidence type has exactly one mint, co-located with its hidden constructor, that must consume a
real artifact — a probe that fabricates is the same forbidden mask the [realness
contract](realness_contract.md) rejects), and **bottom** (every operation forces its evidence, so a
`undefined`-forge is an immediate loud crash, never a silent unmanaged action).

## Current Status

This is the governing contract, and its code-side implementation has landed across the ten reopened
phases tracked in
[../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) (Managed-State-Transition Doctrine
Reopen), each code-side closed 2026-07-16 on the machine-independent gate set with its
single-accelerator cohort full-suite the remaining wave residual. The doctrine and the escape-token
lint are **Phase 0** (Sprint 0.13); the evidence and command kernels are **Phase 1** (Sprint 1.16);
the typed `ClusterLifecycle` machine plus fail-closed versioned aeson persistence plus the
`WriterQuiesced` lease-gated teardown are **Phase 2** (Sprint 2.14); the readiness kernel and typed
subprocess-env seam are **Phase 3** (Sprint 3.14); the `PayloadVerified` sentinel gating, typed
`awaitModelBootstrapReady`, and native-runner `HOME`/`TMPDIR` are **Phase 4** (Sprint 4.28); the
single-sourced client-side readiness contract is **Phase 5** (Sprint 5.12); the capability-gating lint
plus routed managed-transition coverage is **Phase 6** (Sprint 6.39); the `ClusterState` /
`LifecycleProgress` field retirement plus the `DemoBucketsProvisioned` object-proxy gate and proven
`.ready` sentinel are **Phase 7** (Sprint 7.29); the typed `WarmModelCacheOutcome` readiness plus
fail-closed config-side reads are **Phase 8** (Sprint 8.7); and the `withValidAdminToken` region lease
and typed `StsSession` leased value are **Phase 9** (Sprint 9.10). The superseded surfaces are recorded
in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## Validation

- `cabal build all` under `-Wall -Werror` is the primary proof: an operation reachable without its
  evidence, or a raw hatch called outside its evidence-taking wrapper, is a build error.
- `cabal test infernix-haskell-style` (`infernix test lint`) rejects `unsafeCoerce` / `unsafePerformIO`
  in the evidence modules and keeps the style gate clean.
- `infernix lint docs` keeps this document registered and its cross-references resolving; the reopened
  phase and sprint status is tracked in `DEVELOPMENT_PLAN/`.

## Cross-References

- [realness_contract.md](realness_contract.md) — the results-side sibling this doctrine generalizes.
- [runtime_modes.md](runtime_modes.md) — the typed budget ADT precedent.
- [daemon_topology.md](daemon_topology.md) — role failure semantics and readiness gating.
- [../development/haskell_style.md](../development/haskell_style.md) — the export-list, opaque-newtype,
  and lease enforcement mechanisms.
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md) — durable-vs-derived state
  and the fail-closed versioned persistence.
- [../engineering/testing.md](../engineering/testing.md) — the canonical lifecycle failure
  classification.
