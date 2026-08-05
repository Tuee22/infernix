# Phase 6: Validation, E2E, and HA Hardening

**Status**: Active — Validation Only. Sprint 6.44 (verified NVIDIA enforcement and raw-spawn
exemption reduction) is **code-side closed on 2026-08-02** and is no longer blocked: Phase 4 Sprint
4.32's code-side closure landed the shared resource-indexed execution boundary it consumes. The
`linux-gpu` lane compiles an execution plan for the first time — a device-using model now carries two
independently indexed grants and two live watchdogs — and the NVIDIA per-process-group VRAM observer
is a fixed bounded public-tool kernel whose namespace-local attribution was measured on real hardware
rather than assumed. Sprint 6.43 remains reopened for the owner-atomic harness teardown correction
found while executing Phase 2 in numerical order; its implementation is landed and its final
cross-phase review is recorded below. Wave X remains valid for the narrower
ownership/state representation it exercised, but it did not prove that the ownership decision and
destructive teardown share one lifecycle lease. The owner-atomic implementation is landed with
Phase 2 Sprint 2.15. Phase 2's fp16 Bark correction is also implemented with focused checks GREEN,
and its renewed final review plus complete Stage 1 passed against `eae424…` / `a0d1…` as
historical GREEN-as-run evidence only. The no-repo-owned-native-source correction supersedes every
pre-correction Phase 2 source/binary digest, review, Stage 1, and cohort assertion. There is no
reusable pre-correction evidence. Phase 0's current correction review and complete Stage 1 are
green; Apple and `linux-cpu` evidence remain open. The lifecycle
replacement and accepted nested supervisor/pin custody-handshake redesign are present, and the
obsolete C/Cabal boundary is removed. Phase 6's own ordered review, machine-independent, and Wave Y
behavioral gates remain.
Phase 6 behavioral sign-off
here starts only after Phase 2 and Phase 4 close. The
memory-safety-by-construction
reopen (2026-07-21) — Sprint 6.42 (`unboundedEngineSpawnViolations` capability-gating lint) on the
Phase 4 Sprint 4.30 capped-engine kernel — is closed under [Wave W](cohort-validation-waves.md)
(2026-07-24) with apple-silicon plus linux-cpu behavioral sign-off (code-side closed 2026-07-21 on the
machine-independent gate set). The apple-silicon behavioral lane ran the per-model integration suite
with zero host OOM (13 real completions, 2 pre-admission typed-rejections, 1 live watchdog
resident-ceiling breach) and routed Playwright passed 16/16 (the browser matrix rendering all three
capacity rejections), and the `linux-cpu` clean `test all` passed integration and Playwright 16/16 —
see [Wave W](cohort-validation-waves.md) (frozen workload image
`sha256-bcf88c23fda211a4b5f3701c1c1c66ab223462f40d709be795e8f7b2d44ccee0`). Two Playwright cohort fixes
landed here (the budget-schema migration in `expectedModelMemoryLimitExceeded` and the browser matrix's
then-temporary runtime-ceiling-breach tolerance); Phase 2 later removed that tolerance after
recalibrating Bark to 8192 MiB. The earlier lifecycle-rebinding warm-cache flake that once blocked
the clean run was diagnosed as a representable invalid state (a fault-vs-absence collapse in the
readiness observation) and **fixed by construction** in the Observable-Readiness reopen (Phase 1 Sprint
1.18 + Phase 8 Sprint 8.8, code-side closed 2026-07-22). Prior Done — the
Bounded-Command Application & Bounded-HTTP reopen (Sprint 6.40 `unboundedExec`/
`unboundedHttp` lint rules; Sprint 6.41 ProcessMonitor retirement + shared retryCommandOutput
primitive + eager-cache barrier + the full twelve-wait individual bounded-wait migration onto
`awaitReadiness`/`budgetDeadline` + the `threadDelayViolations` lint gate) and the prior
Managed-State-Transition Doctrine reopen (Sprint 6.39) are all code-side closed (machine-independent,
adversarially reviewed) and their single-accelerator (apple-silicon) plus linux-cpu full-suite
sign-off is closed by [Wave V](cohort-validation-waves.md) (2026-07-20). Sprint 6.38 is closed for
typed resource memory-admission validation across
Apple unified host RAM, Linux CPU pod RAM, and Linux GPU VRAM. Wave T closed on 2026-07-12 with
`linux-cpu` plus the selected `linux-gpu` accelerator. Sprints 6.36 and 6.37 remain closed for their
original evidence from Waves R/S, and the prior Wave O MT3 reopen (Sprint 6.35) is closed by Wave P
(2026-07-04).
Note: the routed Playwright suite grew from **9** specs to **15** when the Phase 9
auth/RBAC/dashboard/lifecycle specs landed, so pre-Phase-9 waves record `9/9` and later waves record
`15/15`.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/development/no_env_vars.md](../documents/development/no_env_vars.md)

> **Purpose**: Define the supported static-quality and single-substrate validation contract for the
> one-binary role topology, the README-matrix-driven integration suite, the Pulsar-driven production
> inference surface, the demo UI host, the substrate-generated catalog, the mandatory HA behavior
> of Harbor, MinIO, operator-managed PostgreSQL, and Pulsar, and the repository-hardening plus
> false-negative-doctrine closure that keeps governed root docs,
> route-aware docs, and the CLI surface mechanically aligned with implementation.

## Phase Status

> **Cluster-Ownership & Mutation-Position reopen (2026-07-23).** An externally-killed `infernix test all`
> exposed a DSL smell: because `ClusterState` had no owner and `ClusterLifecycle` had no mutating
> position, a test-mutated cluster (a drained node, an over-scaled deployment) read as a clean
> `steady-state`, and `runClusterOwnedValidation`'s unconditional `clusterDown` over the shared operator
> cluster identity let even a clean run destroy an operator's cluster. This phase reopens under
> [Sprint 6.43](#sprint-643-cluster-ownership-harness-seizure-and-crash-safe-config-blocked) — the harness
> half — for the evidence-gated seizure (fail closed on an `OperatorOwned` cluster), the chaos-mutation
> `ClusterMutating` transitions, and the crash-safe `withTestHarnessConfig` backup reconcile;
> [Phase 2 Sprint 2.15](phase-2-kind-cluster-storage-and-lifecycle.md) is the model half. The doctrine
> + governance landed (Phase 0 Sprint 0.16, `Done`). Wave X historically closed only the 2026-07-23
> typed owner/mutation-position/config scope, but the 2026-07-25 execution audit found that
> `runClusterOwnedValidation` released the
> lifecycle lease between owner authorization and its eventual teardown. Sprint 6.43 is therefore
> reopened until owner-specific teardown is enforced under the lifecycle lock and the Phase 6
> behavioral cohort is rerun. Canonical
> doctrine: [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

> **Memory-safety-by-construction reopen (2026-07-21).** The memory-safety-by-construction doctrine
> (Phase 0 Sprint 0.15) makes an over-budget inference engine a clean typed `ModelMemoryLimitExceeded`
> rather than a host OOM, gated by a `MemoryGrant` and a capped-engine kernel (Phase 4 Sprints
> 4.30/4.31). This phase reopens under
> [Sprint 6.42](#sprint-642-unbounded-engine-spawn-capability-gating-lint-done) to add the
> `unboundedEngineSpawnViolations` capability-gating lint to `src/Infernix/Lint/HaskellStyle.hs` — raw
> `readCreateProcessWithExitCode` / `createProcess` engine spawn becomes a build error outside the
> Phase 4 Sprint 4.30 grant-gated capped-engine kernel, mirroring the existing `unboundedExecViolations`
> (Sprint 6.40) per-rule exemption pattern. Sprint 6.42 is **code-side closed** (2026-07-21): the rule is
> wired into `checkSourceReadability`, reuses the bounded-command exemption set (the capped-engine kernel
> `Infernix.Runtime.CappedEngine` is the sole legitimate engine-spawn surface), and is negative-tested in
> `cabal test infernix-unit`. Single-accelerator (apple-silicon) plus `linux-cpu` behavioral sign-off
> closed under [Wave W](cohort-validation-waves.md) (2026-07-24).

> **Bounded-command application / bounded-HTTP reopen — closed by [Wave V](cohort-validation-waves.md)
> (2026-07-20).** The 2026-07-18
> single-accelerator cohort run surfaced two flakes the Sprint 1.16/3.14/4.28 kernels shipped but did
> not yet guard — a Harbor `docker pull` verify hang and a rate-limited upstream model download —
> together with the missing enforcement that let raw unbounded exec and raw upstream HTTP reach those
> sites. This phase reopened under
> [Sprint 6.40](#sprint-640-unbounded-exechttp-capability-gating-lints-done) to add the
> `unboundedExecViolations` and `unboundedHttpViolations` capability-gating lint rules to
> `src/Infernix/Lint/HaskellStyle.hs` (raw process spawn and raw `withResponse` become build errors
> outside their bounded wrappers), and under
> [Sprint 6.41](#sprint-641-processmonitor-retirement--readiness-wait-kernel-migration-done) for
> the deferred hardening — migrating the hand-rolled readiness waits onto `awaitReadiness`,
> retiring `src/Infernix/ProcessMonitor.hs`, and adding a `threadDelay`-outside-kernel lint gate.
> Sprint 6.40 (the two capability-gating lint rules) and Sprint 6.41 (the `ProcessMonitor` retirement,
> the shared `retryCommandOutput` primitive, the eager-model-cache barrier, the full twelve-wait
> individual bounded-wait migration onto `awaitReadiness`/`budgetDeadline`, and the
> `threadDelayViolations` lint gate) are code-side closed (machine-independent, adversarially reviewed),
> and their single-accelerator (apple-silicon) plus `linux-cpu` full-suite cohort sign-off is closed by
> [Wave V](cohort-validation-waves.md) (2026-07-20).

> **Realness reopen (fail-closed real-only validation).** The audit behind the Phase 4 realness
> reopen also established that this phase's suites accept fabricated results: `assertResultFamilyContract`
> checks shape/extension only and never fetches an artifact (the "deeper byte/dimension checks on cohort
> hardware" comment is unimplemented), the per-row inputs are degenerate (silence WAV, 1×1 PNG), the OMR
> row is fed `musicXmlBuffer()` instead of a score image, and `validateServiceRuntimeLoop` /
> `assertCompletedResultPayload` assert neither completion nor shape. Phase 6 therefore **reopened**
> Sprint 6.33 to strengthen the HA / chaos / service-loop assertions so they fail closed on a
> non-real or incomplete result. The machine-independent realness lint that mechanically forbids
> fabrication is owned by Phase 0 (governance, Sprint 0.12); the real per-family fixtures, the OMR
> input-type fix, and the fail-closed per-row int/e2e are owned by Phase 4 (Sprint 4.23); this phase
> builds on both rather than re-owning them. Realness is guaranteed by the engine code (reopened Phase 4
> / Phase 1); the tests trust the result and fail loudly on `status=failed`. The Linux gate is [Wave K](cohort-validation-waves.md) (`linux-gpu` + `linux-cpu`);
> the same DRY suite re-runs on `apple-silicon` under [Wave L](cohort-validation-waves.md) (reopened
> Phase 1), which closed on 2026-06-29.

> **Common-shape reopen (single-accelerator phasing).** Phase 6 reopens to adopt the
> **single-accelerator-per-phase** rule (see [README.md](README.md) → Common-Shape
> Reopen and [development_plan_standards.md](development_plan_standards.md) §Q): each
> accelerator-bearing phase validates **one** of `apple-silicon` or `linux-gpu` plus
> `linux-cpu`, never both, and cross-accelerator coverage is a `linux-cpu`-only
> aggregation phase. The prior "two-axis / batch-both-cohorts" framing and
> `cohort-validation-waves.md` are repurposed into per-accelerator attestation
> ledgers, recorded in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

> **Audit follow-on reopen (lint coverage and no-env closure).** Phase 6 reopened Sprint 6.34 after
> the June 2026 audit found that docs lint did not include several authoritative docs or Phase 7 plan
> docs, and that pre-manifest / lint-owning code carried env/PATH exceptions:
> `Setup.hs` reads `PATH` / `INFERNIX_BUILD_ROOT` and calls `setEnv`, `bootstrap/common.sh` accepts
> inherited `BOOTSTRAP_*` command overrides, `src/Infernix/Lint/HaskellStyle.hs` invokes bare `cabal`,
> and `web/scripts/install-purescript.mjs` invokes bare `mktemp` / `tar`. The target doctrine remains
> no env vars and no ambient `PATH`; Sprint 6.34 is now closed. `Setup.hs` no longer reads
> `INFERNIX_BUILD_ROOT` or inherited `PATH`, and its sole environment mutation is the mechanically
> allowed deterministic `Env.setEnv "PATH"` shim required by Cabal/proto-lens setup. Bootstrap command
> constants no longer inherit `BOOTSTRAP_*` or `PATH`, Haskell-style Cabal invocations resolve through
> `HostConfig` or fixed candidates, the PureScript compiler installer uses Node tar/gzip handling, and
> docs lint now covers the authoritative configuration/tool/realness docs plus Phase 7.

> **MT3 catalog-validation reopen (closed).** Phase 6 reopened Sprint 6.35 after the 2026-06-30
> catalog replacement added `music-mt3-infer` and `music-mr-mt3` to the generated substrate
> catalogs. The integration and routed Playwright suites enumerate the active catalog, so the
> code-side coverage surface covers the new rows. The post-replacement full-suite evidence closed
> under [Wave O](cohort-validation-waves.md) and was proven by [Wave P](cohort-validation-waves.md)
> (2026-07-04): both `linux-gpu` and `linux-cpu` full `infernix test all` are GREEN with routed
> Playwright 9/9 over the expanded catalog, including the 27 GB `video-wan21-t2v` row after Phase 8
> eager model-cache staging.

> **Historical resource-admission validation increment (2026-07-09).** Sprint 6.38 validated the doctrine added by
> Phase 4 Sprint 4.27 and Phase 5 Sprint 5.11. The code-side suite now proves that one over-budget
> model does not fail daemon startup, Apple zero/negative computed budgets remain enforced without
> hardcoded floors, Linux CPU uses the cluster engine pod memory limit, Linux GPU uses GPU VRAM, and
> classifiers identify capacity failures by `InferenceError.ModelMemoryLimitExceeded` plus explicit
> MiB fields. Wave T's `linux-cpu` and selected `linux-gpu` live integration/e2e evidence now proves
> smaller models kept running in the same daemon session. That evidence predates and does not close
> the current Sprint 6.44 dual RAM/VRAM enforcement construction.

Phase 6 is `Blocked`: Sprint 6.43's 2026-07-25 owner-atomic reservation/teardown correction remains
under cross-phase implementation and source review. Its behavioral validation is ordered after
Phase 2 closes under Wave Y and Phase 4 closes. Wave X remains historical closure only for the
2026-07-23 typed
owner/mutation/config scope. Sprint 6.38's selected `linux-gpu` Wave T cohort residual is closed.
Wave Q Sprint 6.36 (real-output and matrix validation hardening, opened 2026-07-06) and Sprint 6.37
(apple-silicon memory-bounded validation lane) remain closed for their original scope; the prior
Wave O MT3 reopen (Sprint 6.35) is closed, proven by Wave P (2026-07-04). The phase otherwise closes
around the validation entrypoints, routed coverage, governed-root-document
metadata closure, structured CLI-registry closure, route-hardening cleanup, supported bootstrap
lifecycle fixes, false-negative doctrine, Harbor publication retry closure, daemon-role split,
and real Dhall substrate codec implemented in the current worktree. The validation entrypoints,
routed coverage, HA hardening, governed-doc closure, and CLI-registry closure are `Done` after
Apple cohort validation in Waves A/A.1/A.2/A.3, CUDA Linux cohort validation in Wave C, and the
2026-06-20 selected `linux-gpu` plus `linux-cpu` closure in Waves I and J for the then-active
catalogs. The
inference-coverage sprints were upgraded from the metadata-echo
assertion to the per-family result contract plus cohort hardware proof: the reopened Sprints 6.2,
6.3, and 6.6 assert the typed per-family result surface for every active-substrate row, and the
union across the three substrate catalogs covers every README matrix row as a mechanically checked
invariant. The
code-side closure for that coverage upgrade is complete and validated on the present CUDA Linux
host (x86_64 + RTX 5090). The assertion and harness code for these sprints —
the `ResultFamily` dispatch in the integration suite, the per-family Playwright assertions plus
per-family web-UI artifact rendering, and the `allMatrixRowIds` coverage invariant — are written and
proven by the machine-independent gate set that ran on this host (`cabal test infernix-unit`,
`cabal build test:infernix-integration`, `infernix lint docs`, `infernix lint files`). The web unit
suite (`spago`/Node 22) could not run on this bare host (host Node 18; Node 22 makes spago segfault
— an environmental toolchain limit), so its gate is exercised in the supported Linux container lane
(Node 22) / cohort batch. The real-engine integration and routed E2E assertions closed on
2026-06-20 through the Stage 2 single-accelerator gate for `linux-gpu` plus `linux-cpu`,
re-validated in [Wave I](cohort-validation-waves.md), never a per-sprint machine switch (see
[development_plan_standards.md](development_plan_standards.md) Section Q). Apple Wave L
real-engine reruns have passed the full integration layer and the focused routed Playwright gate
(`9 passed (21.1m)`), and the paired `linux-cpu` Wave L gate closed on 2026-06-29 as recorded in
[Wave L](cohort-validation-waves.md). The current CUDA Linux image strict-smokes the
runtime-backed Linux native payload layer. The final CUDA Linux closure passed full
`./bootstrap/linux-gpu.sh test` and full rebuilt-image `./bootstrap/linux-cpu.sh test`, including
integration HA checks and routed Playwright per-model matrices.
The supported test story is substrate-specific in code. Sprint 6.25 closes around the implemented split topology: cluster daemons
always run, Apple cluster daemons own request-topic consumption and derived pool-topic handoff,
Apple inference work moves through Pulsar to same-binary host daemons, and publication distinguishes
cluster daemon location from inference executor location. Sprint 6.26 closes the lifecycle-warning
cleanup: warning classification is documented, buildx support inside the Linux substrate image is
implemented, the PureScript compiler bypasses the npm installer, Spago's `glob@11` transitive
dependency is overridden to `glob@13`, and Poetry installs through an image-local virtual
environment. The Linux substrate suppresses npm update notices and leaves GHCup shell-profile
adjustment disabled; the upstream GHCup no-update message is treated as an idempotent installer
no-op, and the upstream PATH advice is accepted because the Dockerfile owns `PATH` and the
pinned toolchain succeeds. Current CUDA Linux validation closed in Wave C on the native
Linux/CUDA host.
Sprint 6.27 closes the staged-substrate format cleanup: `infernix.dhall` is a typed
Dhall record decoded in-process by the `dhall` Haskell library, the schema is reflected from the
substrate decoder type, generated files no longer carry banner-prefixed JSON, and
`cabal.project` records the supported wildcard `allow-newer` posture against the project
`ghc-9.12.4` toolchain.

The worktree carries the formatter-toolchain closure:
`src/Infernix/Lint/HaskellStyle.hs` installs `ormolu` and `hlint` through `cabal install` against
the project `ghc-9.12.4` compiler into `./.build/haskell-style-tools/bin/`, and the Linux
substrate image installs a single `ghc-9.12.4` toolchain. The supported Linux outer-container launcher keeps its build
root and chart archive cache in the image overlay, hydrates MinIO through the supported direct
tarball path instead of Docker Hub-backed OCI metadata, and repairs the known stale retained
Pulsar or ZooKeeper epoch mismatch by resetting only the Pulsar claim roots and retrying once.
Sprint 6.32 reopens validation for the engine-pool routing target: unit gates now reject illegal
pool graphs and service-consumer subscription states, while Apple integration now proves
broker-native backpressure on `Shared` pools, `Exclusive` pinned routes, and production-shape
coordinator presence when `demo_ui = false`. Linux CPU and Linux GPU/CUDA validation now prove the
pool-routing and backpressure gates required by Wave J.

## Current Repo Assessment

The repository has lint, unit, integration, and Playwright entrypoints. The canonical testing,
boundary, portability, storage, and Haskell-style docs are present, the baked Linux substrate
image definition writes the source-snapshot manifest needed for git-less `infernix lint files`
runs, the routed Playwright suite exhaustively exercises every demo-visible generated catalog
entry for the active substrate, and the integration suite enumerates every generated
active-substrate catalog entry while also carrying Harbor, MinIO, Pulsar, and Harbor PostgreSQL
recovery or lifecycle checks in code. The per-family real-output coverage upgrade for the reopened
Sprints 6.2/6.3/6.6 is code-complete and validated on the recorded CUDA Linux host: the integration
suite dispatches a per-family result contract on `ResultFamily`, the routed Playwright suite and the
web UI render and assert per-family artifact results, and `allMatrixRowIds` plus the
README-to-matrix coverage check make full README coverage a mechanically enforced invariant, and
the Wave I cohort sign-off (real-engine integration + routed E2E on hardware) for Sprints 6.2/6.3/6.6
is closed. The staged
file, `cluster status`, publication JSON, and
generated browser contracts still expose the active substrate through `runtimeMode` fields or
lines. The worktree omits direct Harbor, MinIO, and Pulsar compatibility handlers from
`src/Infernix/Demo/Api.hs`, tightens `test/integration/Spec.hs` to require the real routed
upstream behavior, persists cluster state before later Linux rollout phases, owns active
substrate preflight in the binary command, reuses a persistent Linux chart-archive cache, and
performs the targeted Pulsar claim-root reset when the known retained ZooKeeper epoch-state
corruption blocks bootstrap. The current lifecycle skips broad pre-Harbor support-image preloads
on supported lanes, may hydrate and stream only the narrow Harbor warmup dependency set into
Kind workers before Helm warmup, and follows the stricter Harbor-first boundary where only
Harbor-required services may pull upstream before Harbor is responsive.

Validation proof points are tracked by
[cohort-validation-waves.md](cohort-validation-waves.md), and historical hardware evidence lives
only in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). The Apple cohort gate
is closed in Wave A/A.1/A.2/A.3, and the CUDA Linux cohort gate is closed in Wave C.

The runtime-topology implementation deploys the `infernix-coordinator` role on Apple and reports
`daemonLocation: cluster-pod` plus `inferenceExecutorLocation: control-plane-host` in publication
metadata. Linux substrates deploy both `infernix-coordinator` and `infernix-engine`; Apple sets the
cluster engine replica count to 0 because host engine daemons own Apple-native inference execution.
Pool-routing metadata is now the supported publication/status surface, and the old Apple host batch
topic metadata is absent from supported outputs. The supported routed and cluster
validation path uses real Pulsar transport; the repo-local topic spool under
`./.data/runtime/pulsar/` remains only for unit-level or intentionally endpoint-absent harness
checks and is not accepted as routed Pulsar evidence.

## Validation Surface

The supported validation entrypoints are:

- `infernix lint files`
- `infernix lint docs`
- `infernix lint proto`
- `infernix lint chart`
- `infernix docs check`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`

These commands are declarative and idempotent validation entrypoints. Re-running them rechecks the
same contract and may reconcile supported prerequisites instead of depending on alternate setup
commands.

## Current Validation Baseline

- `test unit` proves matrix typing, generated catalog rendering, and contract-generation logic
- supported `test lint` and `test unit` commands still require the initialized repo-root runtime
  config for command-level execution-context validation, while their assertions remain static or unit scoped
  and do not claim real-cluster matrix coverage
- `test integration` validates the active substrate's published catalog contract, routed surfaces,
  routed inference execution for every generated active-substrate catalog entry, and the
  service-loop roundtrip through the routed Pulsar transport; on Apple it brackets the
  same-binary host daemon and waits for the service readiness marker before publishing
- `test e2e` exercises every demo-visible generated catalog entry for the active substrate
- `test all` runs every supported validation layer for the active built substrate and reports that
  substrate instead of implying cross-substrate coverage
- `test integration`, `test e2e`, and `test all` own cluster lifecycle around each test phase:
  the supported entrypoint runs `cluster down` first, executes the test action, and runs
  `cluster down` again unconditionally afterwards so reruns start from a clean cluster state
  without depending on prior operator setup

## Sprint 6.1: Static Quality Gates, Testing Doctrine, and Unit Suites [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Files.hs`, `test/haskell-style/Spec.hs`, `test/unit/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`, `documents/engineering/storage_and_state.md`

### Objective

Make static-quality enforcement and unit coverage broad enough to protect the control plane, shared
contracts, and generated-catalog logic, and put the validation doctrine in canonical docs.

### Deliverables

- `infernix test lint` is the canonical static-quality entrypoint
- the repo-owned lint layer enforces whitespace, newline, tab, docs, chart, proto, and tracked-file
  policy; mounted-source Linux container runs invoke Git with a scoped
  `safe.directory=/workspace` setting so file lint validates the bind-mounted repo without global
  Git state
- the Haskell style guide clearly separates:
  - hard gates enforced mechanically
  - review guidance that remains human doctrine
  - the enforcement model implemented in `src/Infernix/Lint/HaskellStyle.hs`
- the Haskell style guide states the fail-fast rule explicitly: validation fails on hard-gate
  violations and does not silently rewrite tracked source
- `documents/engineering/testing.md` becomes the canonical testing doctrine
- `documents/engineering/implementation_boundaries.md`, `documents/engineering/portability.md`,
  and `documents/engineering/storage_and_state.md` are expanded so boundary, portability, and
  durability rules are canonical and testable
- `infernix test unit` remains the canonical unit-suite entrypoint for Haskell and PureScript

### Validation

- `infernix test lint` passes when repo-owned lint, docs, and compiler-warning policy are satisfied
- Haskell formatting or lint drift fails `cabal test infernix-haskell-style`
- `infernix test unit` runs both Haskell and frontend unit suites
- docs validation fails if canonical testing or boundary docs drift from the supported implementation

### Remaining Work

None.

---

## Sprint 6.2: Extensive Integration Suites [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded CUDA Linux host (x86_64 + RTX 5090) — `validateCatalogModelInference` (`test/integration/Spec.hs`) is upgraded from the model-id + runtime-mode echo to a per-family real-output result contract dispatched on `ResultFamily` (via `resultFamilyForDescriptor`): text families (LLM, speech) assert a non-empty inline continuation and no object ref; every artifact family asserts an `infernix-demo-objects/` object reference whose key extension matches the family's artifact type (`.zip` source-separation, `.mid`/`.midi` audio-to-MIDI, `.mid`/`.midi`/`.musicxml`/`.xml` music transcription, `.png` image, `.mp4` video, `.wav` audio generation, `.musicxml`/`.xml` OMR) — shape/type, never golden strings. One DRY substrate-aware suite that reads the active `.dhall` and traverses the README rows; no per-substrate suites. Proven machine-independent by `cabal build test:infernix-integration` (compiles/typechecks) and `cabal test infernix-unit`, which pass on the recorded CUDA Linux host; the assertions themselves pass only when real engines run (Section P: results name the single substrate they exercised)
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` run the per-family real-output integration suite against their own catalog columns. The selected-lane gate passed on 2026-06-20: full `./bootstrap/linux-gpu.sh test` passed style, unit, web unit, integration, and routed Playwright against the CUDA catalog, and rebuilt-image `./bootstrap/linux-cpu.sh test` passed the matching CPU lane. Current Apple integration evidence also passes cluster-up, route probes, mounted Apple substrate loading, coordinator `serviceRuntimeMode: apple-silicon`, derived Apple pool-topic routing, host engine processing, pinned Apple host-engine `Exclusive` duplicate-consumer rejection, same-machine Apple `Shared` coexistence, Apple production `demo_ui = false` assertions, and edge-port conflict rediscovery.
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Exercise the generated demo-config and service integration path on the final Kind, Helm, Harbor,
MinIO, Pulsar, and operator-managed PostgreSQL substrate.

### Deliverables

- integration coverage for `cluster up`, generated demo-config publication, and routed inference
  execution for every generated active-substrate catalog entry
- host-native integration coverage proves the routed API can keep one browser-visible entrypoint
  while Apple inference remains host-native
- dedicated `linux-gpu` integration coverage proves device-plugin rollout, GPU resources, and
  service GPU visibility
- integration coverage proves routed cache mutation and publication surfaces stay aligned with the
  generated catalog contract

### Validation

- `infernix test integration` reconciles or reuses supported cluster prerequisites
- integration tests fail when publication state, generated catalog publication, per-entry routed
  inference execution, service-loop schema publication, or CUDA scheduling assertions regress

### Remaining Work

None. The per-family integration contract and the selected `linux-gpu` plus `linux-cpu` full-suite
gates are closed on current source. Earlier CUDA Linux failure notes are preserved in
[cohort-validation-waves.md](cohort-validation-waves.md) as historical diagnostics.

---

## Sprint 6.3: Routed Playwright E2E Coverage [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded CUDA Linux host (x86_64 + RTX 5090) — the routed Playwright suite (`web/playwright/inference.spec.js`) per-model smoke matrix now asserts the per-family rendered result for every demo-visible row (text bubble vs image/audio/video/download), staying substrate-agnostic via a JS classifier `expectedResultRenderKind` (keys on model family + matrix-row metadata, never substrate id or engine binding). The web UI renders artifact results per-family: `web/src/Infernix/Web/Chat.purs` renders `inferenceResultArtifacts` as `<img>`/`<audio>`/`<video>`/download `<a>` with `data-result-artifact-kind` keyed on the object-key extension. The PureScript + Playwright code is written and `infernix lint files` passes on the recorded CUDA Linux host. NOTE: the web unit suite (`spago`) requires Node 22 and cannot run on this bare host (host has Node 18; Node 22 makes spago segfault — an environmental toolchain limit), so 6.3's web-unit gate is exercised in the supported Linux **container** lane (Node 22) / cohort batch
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` run the routed Playwright suite against their own catalog column. Full routed Linux real-output and browser evidence closed on 2026-06-20 with `./bootstrap/linux-gpu.sh test` (`9 passed`, including the 16-row GPU browser matrix) plus rebuilt-image `./bootstrap/linux-cpu.sh test` (`9 passed`, including the CPU browser matrix). Current Apple focused e2e passes 9/9 after the browser matrix uploads object fixtures for object-input model families, asserts generated artifact refs without requiring presigned media visibility, and allows a real cold Hugging Face snapshot through the 900-second bootstrap-ready envelope; the subsequent full Apple aggregate also passed lint, unit, integration, and 9/9 routed Playwright.
**Implementation**: `src/Infernix/CLI.hs`, `web/playwright/inference.spec.js`, `web/src/Infernix/Web/Chat.purs`, `web/src/Infernix/Web/Router.purs`, `web/src/Main.purs`, `web/src/index.html`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`, `web/package.json`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`

### Objective

Keep routed Playwright validation on the supported final execution paths while exercising the real
browser surface through the shared edge.

### Deliverables

- Playwright suites live under the UI-owned `web/playwright/` surface
- `infernix test e2e` exercises the routed browser surface; Phase 3 Sprint 3.10 (landed
  the recorded validation) retired the dedicated `infernix-playwright:local` image and
  `docker/playwright.Dockerfile`, baked the Playwright system packages and the three browsers
  into `docker/Dockerfile`, and moved Linux-substrate routed E2E to in-container
  `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private
  `kind` network. The Apple host-native routed-E2E executor now uses host `npm exec` with the
  same typed fixture and is covered by Apple cohort validation batches.
- the previous `INFERNIX_PLAYWRIGHT_NETWORK`, `INFERNIX_EDGE_PORT`, `INFERNIX_PLAYWRIGHT_HOST`,
  `INFERNIX_EXPECT_DAEMON_LOCATION`, `INFERNIX_EXPECT_INFERENCE_DISPATCH_MODE`, and
  `INFERNIX_EXPECT_API_UPSTREAM_MODE` env vars were retired by Sprint 3.10; the same spec covers
  every substrate by reading typed fixture data from a Dhall-decoded JSON written to the
  repo-relative `.data/runtime/playwright-fixture.json` at test setup (resolving to
  `/workspace/.data/runtime/playwright-fixture.json` inside the Linux launcher; Playwright exposes
  it as the `infernixFixture` option fixture)
- supported Playwright invocations use `npm --prefix web exec -- playwright ...`
- E2E covers publication details, model selection, manual inference submission, and result rendering

### Validation

- `infernix test e2e` hits the routed path rather than bypassing the edge
- the routed Playwright suite fails if any active-substrate catalog entry is skipped
- Linux routed E2E runs entirely inside the active `infernix-linux-<mode>:local` launcher image
  via `docker compose run --rm infernix infernix test e2e`, which invokes
  `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private
  `kind` network (no dedicated Playwright sidecar service; `docker/playwright.Dockerfile` and the
  `infernix-playwright:local` image are removed)
- Apple host-native routed E2E runs host `npm exec` Playwright fed by the same typed
  `.data/runtime/playwright-fixture.json` against the published localhost edge port, and is covered
  by Apple cohort validation batches

### Remaining Work

- **Code (machine-independent — validated on the recorded CUDA Linux host): DONE.** The routed
  Playwright suite (`web/playwright/inference.spec.js`) now asserts the per-family rendered result
  for every demo-visible row (inline text bubble, audio player, image, video, MIDI or MusicXML
  download) while staying substrate-agnostic via the JS classifier `expectedResultRenderKind` (keys
  on model family + matrix-row metadata, never substrate id or engine binding); `infernix-demo`
  chooses the engine binding from the active `.dhall` and the browser does not branch on substrate
  id or engine family. The web UI renders artifact results per-family in
  `web/src/Infernix/Web/Chat.purs` (`inferenceResultArtifacts` rendered as
  `<img>`/`<audio>`/`<video>`/download `<a>` with `data-result-artifact-kind` keyed on the
  object-key extension). Proven by `infernix lint files`, which passes on the present CUDA Linux
  host. The web unit suite (`spago`, Node 22) cannot run on this bare host (host Node 18; Node 22
  makes spago segfault — an environmental toolchain limit), so its gate is exercised in the
  supported Linux container lane (Node 22) / cohort batch.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** asserting the real rendered
  output needs a deployed cluster; each cohort runs the routed suite against its own catalog column
  (Apple Metal with headless materialization; CUDA `linux-cpu`/`linux-gpu`).

---

## Sprint 6.4: HA Failure and Recovery Coverage For Harbor, MinIO, and Pulsar [Done]

**Status**: Done
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/chaos_testing.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Back the HA claims with concrete failure coverage.

### Deliverables

- pod-deletion and rolling-restart coverage for Harbor application-plane workloads
- durability and failover coverage for MinIO on the mandatory HA topology
- message continuity and restart coverage for Pulsar on the mandatory HA topology

### Validation

- supported HA subsets prove single-pod failure does not permanently break the supported path
- data written before MinIO or Pulsar restarts remains available afterward
- Harbor-backed image pulls continue to work after supported Harbor pod replacement

### Remaining Work

None.

---

## Sprint 6.5: Cluster Lifecycle and Environment-Matrix Validation [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `compose.yaml`, `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Verify the same product contract across Apple host-native and Linux outer-container workflows.

### Deliverables

- the codebase exposes `cluster up`, `cluster status`, and `cluster down` through both execution contexts
- automated coverage proves repo-local kubeconfig, generated demo-config, publication mirror, and
  publication state creation for the active built substrate
- `cluster up` persists repo-local cluster state before later rollout phases so `cluster status`
  and supported cleanup continue to observe an in-progress Linux reconcile
- `cluster status` reports the active substrate through its current `runtimeMode` line together
  with build or data roots, publication details, and the chosen edge port
- `infernix test integration`, `infernix test e2e`, and `infernix test all` own cluster lifecycle
  around each test phase: the supported entrypoint runs `cluster down`, executes the test action,
  and runs `cluster down` again unconditionally afterwards so reruns start from a clean cluster
  state without depending on prior operator setup

### Validation

- validation closes when `infernix test integration` proves the host-native lane creates the
  expected repo-local state
- validation closes when the Linux outer-container lane reaches the cluster successfully through
  its supported path
- validation closes when repeated `cluster up` or `cluster down` behavior and `9090`-first
  edge-port rediscovery remain stable
- validation closes when supported `infernix test ...` reruns leave behind no residual cluster
  state because each phase is bracketed by `cluster down` even when the test action fails partway
  through

### Remaining Work

None for the cluster-lifecycle contract (`cluster up`/`status`/`down` validated on both execution
contexts, apple-silicon included). The **full per-model apple-silicon environment-matrix run** is now
**green**: Sprint 4.26 admission control makes an over-budget model fail clean (`status=failed`)
instead of OS-OOM-killing the daemon, and [Wave R](cohort-validation-waves.md) (2026-07-08) proved
the full 16-model Apple `test integration` with zero OS OOM-kill (owned by Sprint 6.37, paired with
Phase 4 Sprint 4.26).

---

## Sprint 6.6: Generated-Catalog Exhaustive Integration and E2E Coverage Baseline [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded CUDA Linux host (x86_64 + RTX 5090) — `allMatrixRowIds` is exported from `src/Infernix/Models.hs`; `test/unit/Spec.hs` asserts that the union of `catalogForMode` across `apple-silicon`/`linux-cpu`/`linux-gpu` equals the full README matrix row set; and a README-to-matrix coverage check was added to `infernix lint docs` (`src/Infernix/Lint/Docs.hs` `validateReadmeMatrixCoverage`) asserting every catalog `referenceModel` appears in README.md. Proven by `cabal test infernix-unit` and `infernix lint docs`, which pass on the recorded CUDA Linux host. The per-family per-entry assertions ride Sprints 6.2/6.3 on cohort hardware
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) — `linux-gpu` plus `linux-cpu` require a per-family assertion for every active-substrate catalog entry
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/Files.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`

### Objective

Make the README promise concrete for the generated-catalog coverage machinery so the later
single-substrate validation closure rests on explicit per-substrate catalog enumeration rather than
hard-coded lane lists.

### Deliverables

- `infernix test integration` enumerates every generated catalog entry from the active staged
  demo config
- `infernix test e2e` is specified to exercise every demo-visible generated catalog entry through
  the routed browser surface
- `infernix test all` aggregates lint, unit, integration, and E2E as the complete supported suite
  without silently dropping catalog entries
- the coverage machinery derives its exercised catalog from the generated substrate file instead of
  hard-coded per-lane model lists

### Validation

- changing the built substrate changes the exercised catalog and engine assertions automatically
- integration fails if any generated catalog entry is skipped
- routed E2E fails if any demo-visible generated catalog entry is skipped once Sprint 6.3 closes

### Remaining Work

- **Code (machine-independent — validated on the recorded CUDA Linux host): DONE.** `allMatrixRowIds`
  is exported from `src/Infernix/Models.hs`; `test/unit/Spec.hs` asserts that the union of
  `catalogForMode` across `apple-silicon`, `linux-cpu`, and `linux-gpu` equals the full set of
  README matrix rows; and a README-to-matrix coverage check (`src/Infernix/Lint/Docs.hs`
  `validateReadmeMatrixCoverage`) was added under `infernix lint docs` asserting every catalog
  `referenceModel` appears in README.md. Proven by `cabal test infernix-unit` and
  `infernix lint docs`, which pass on the recorded CUDA Linux host.
- **Cohort gate ([Wave I](cohort-validation-waves.md), Stage 2):** requiring a per-family assertion
  for every active-substrate catalog entry rides Sprints 6.2/6.3; each cohort runs it against its
  own catalog column (Apple Metal with headless materialization; CUDA `linux-cpu`/`linux-gpu`).

---

## Sprint 6.7: Operator-Managed PostgreSQL Failure and Lifecycle Coverage [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/postgresql.md`

### Objective

Back the PostgreSQL doctrine with readiness, failover, and storage-rebind coverage.

### Deliverables

- integration coverage proves Percona and Patroni readiness for Harbor and later PostgreSQL-backed services
- HA-failure coverage deletes or restarts a PostgreSQL member and verifies failover
- lifecycle coverage proves `cluster down` plus `cluster up` reuses the same deterministic Harbor
  PostgreSQL PV inventory and host paths
- validation proves services do not regress to chart-managed standalone PostgreSQL deployments

### Validation

- `infernix test integration` verifies ready operator-managed PostgreSQL members, Patroni failover,
  and deterministic Harbor PV and host-path rebinding
- repeated cluster lifecycle validation fails if Harbor PostgreSQL no longer reuses the same
  deterministic PV inventory and host paths

### Remaining Work

None.

---

## Sprint 6.8: Minimal Host Prerequisites and Clean-Host Bootstrap Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Python.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Minimize host-side prerequisites and let `infernix` reconcile the remaining supported operator
toolchain from package managers instead of depending on a broad preinstalled Apple host stack.

### Deliverables

- Apple host-native flow reduces pre-existing host requirements to Homebrew plus ghcup before
  building `./.build/infernix`
- the earlier Apple Docker reconciliation behavior from this sprint is replaced by Phase 1
  Sprint 1.12: Docker-backed Apple work requires an already selected native arm64 Docker daemon
  and must not create or switch Docker contexts, create a Colima VM, or use cross-architecture
  emulation
- after the Apple binary exists, `infernix` can reconcile the remaining supported Homebrew-managed
  operator tools needed by the active path, including the Docker CLI, `kind`, `kubectl`, `helm`,
  and Node.js
- when Apple adapter flows first need Poetry and the `poetry` executable is absent, `infernix`
  can reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command, or reuse an
  already available compatible Python 3.12+ executable that passes the implemented version check,
  bootstrap Poetry into a user-local environment, and then continue all host-side Python
  management through the shared Poetry project
- `linux-cpu` host prerequisites stop at Docker Engine plus the Docker buildx and Compose plugins
- `linux-gpu` host prerequisites stop at the `linux-cpu` Docker baseline plus the supported
  NVIDIA driver and container-toolkit setup
- clean-host validation proves the supported commands reconcile prerequisites rather than relying on
  undocumented manual setup beyond those minimal host baselines

### Validation

These are **independent per-host clean-host prerequisite attestations** — each closes on its own
host and none is a joint accelerator gate (§Q single-accelerator: clean-host prerequisite
reconciliation is not an inference full-suite gate spanning accelerators).

**Apple clean-host lane:**

- validation closes when, on a clean Apple Silicon host with only Homebrew plus ghcup present,
  `./bootstrap/apple-silicon.sh up` builds the host binaries, explicitly runs
  `./.build/infernix init --if-missing`, validates repo-root runtime config, reconciles the remaining
  non-Docker Apple host prerequisites through the supported package-manager path, and stops at a
  prerequisite boundary if the current Docker daemon is unavailable or non-native
- validation closes when Apple host validation proves the supported flow can bootstrap Poetry when
  absent and then run the adapter setup path without manual Poetry installation

**Linux CPU clean-host lane (the always-present lane):**

- validation closes when, on a clean Linux CPU host with Docker only,
  `./bootstrap/linux-cpu.sh test` enters the Compose-launched `infernix` binary, lets the binary
  validate its repo-root runtime config, and passes the full supported validation lane

**Linux GPU clean-host lane (its own CUDA cohort host):**

- validation closes when, on a clean Linux GPU host with Docker plus the supported NVIDIA host
  prerequisites, the Linux GPU clean-host bootstrap enters the Compose-launched `infernix` binary
  through the `linux-gpu` launcher image, lets the binary validate its repo-root runtime config, and
  passes the full supported validation lane on that CUDA cohort host

### Remaining Work

None.

---

## Sprint 6.9: Governed Root-Document Metadata Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/documentation_standards.md`, `documents/README.md`

### Objective

Close the stricter governed-root-document metadata model so the root entry documents match the
standards they already cite.

### Deliverables

- `README.md` carries the governed root-document metadata block appropriate for an orientation
  document and makes its canonical-home links explicit
- `AGENTS.md` and `CLAUDE.md` carry the explicit supersession or canonical-home markers required
  for governed entry documents and stay thin while linking to the canonical assistant-workflow
  document under `documents/`
- `documents/documentation_standards.md` describes the root-document metadata contract in the same
  terms the repo actually enforces
- the docs linter grows root-document checks strong enough to catch missing root-document metadata
  markers rather than relying on convention alone

### Validation

- `infernix docs check` fails when `README.md`, `AGENTS.md`, or `CLAUDE.md` are missing the
  required governed metadata markers for their declared role
- root docs carry the governed metadata and canonical-home links needed for the canonical
  assistant-workflow entrypoint without losing the canonical topic entrypoints

### Remaining Work

None.

---

## Sprint 6.10: True Single-Definition CLI Registry Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Lint/Docs.hs`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `test/unit/Spec.hs`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `README.md`

### Objective

Collapse the supported CLI surface into one Haskell registry so
parsing, help text, and the canonical CLI reference stop drifting independently.

### Deliverables

- one Haskell registry owns supported command parsing, help text, and
  command-family metadata
- the canonical CLI reference derives from that same registry or from a mechanically equivalent
  generated artifact rather than a separate handwritten command inventory
- `documents/reference/cli_surface.md` remains a short family overview that summarizes and links to
  the canonical CLI reference
- docs lint validates the stronger CLI-registry contract instead of only checking that registry
  command lines appear somewhere in the reference document

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command
  families from the same Haskell registry source
- changing a supported command in the registry changes parsing, help output, and CLI reference
  material through one implementation path
- `infernix docs check` fails when the CLI reference drifts from the command registry

### Remaining Work

None.

---

## Sprint 6.11: Registry-Backed Route Docs and Lint Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Routes.hs`, `src/Infernix/Lint/Chart.hs`, `src/Infernix/Lint/Docs.hs`, `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/operations/cluster_bootstrap_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining route or publication DRY cleanup so the Haskell route registry drives
route-aware docs and validation, not only runtime rendering and Helm values.

### Deliverables

- the Haskell route registry remains the source of truth for rendered HTTPRoutes, publication
  state, and route-aware documentation summaries
- route-oriented docs consume registry-backed rendered content or a mechanically equivalent
  generated section instead of independent handwritten route inventories
- docs lint and chart lint validate the route-aware contract from registry-backed expectations
  rather than ad hoc phrase checks
- the cleanup ledger records no remaining handwritten route-inventory or route-aware lint
  duplication once the sprint closes

### Validation

- `GET /api/publication` still reports the exact route inventory produced by the registry
- `infernix docs check` fails when a registry-owned route summary drifts from the corresponding docs
  section
- `infernix test lint` fails when route-aware lint or chart expectations diverge from the
  registry-backed route contract
- routed Harbor, MinIO, Pulsar, and demo probes continue to pass on the shared edge

### Remaining Work

None.

---

## Sprint 6.12: Assistant Workflow Canonicalization and Workflow-Helper Deduplication [Done]

**Status**: Done
**Implementation**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `src/Infernix/Workflow.hs`, `src/Infernix/Cluster.hs`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `documents/development/assistant_workflow.md`, `documents/documentation_standards.md`, `documents/README.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/local_dev.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Finish the remaining REPO_DRY_CLEANUP follow-ons for assistant-facing root guidance and shared
workflow-helper closure.

### Deliverables

- repo-level assistant workflow doctrine moves into one canonical governed document under
  `documents/`
- `AGENTS.md` and `CLAUDE.md` become thin governed entry docs that summarize and link to that
  canonical assistant-workflow doc instead of carrying long parallel rule sets
- `src/Infernix/Workflow.hs` owns shared web-dependency readiness, npm invocation resolution,
  platform-command availability checks, and shared generated-file banner constants; cluster and CLI
  paths reuse it instead of re-declaring their own readiness probes
- the cleanup ledger no longer tracks duplicated assistant guidance or duplicated web-dependency
  readiness logic once the sprint closes

### Validation

- `infernix docs check` fails if the canonical assistant-workflow doc or the root-doc links drift
- `rg -n "webBuildToolchainPresent|ensureWebBuildDependencies" src/Infernix` shows one supported
  readiness implementation path rather than parallel cluster-local copies
- supported CLI, docs, and outer-container flows still install web dependencies through the shared
  helper

### Remaining Work

None.

---

## Sprint 6.13: Engineering Doctrine Depth and Haskell Guide Completion [Done]

**Status**: Done
**Implementation**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/implementation_boundaries.md`, `documents/engineering/storage_and_state.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `documents/documentation_standards.md`

### Objective

Finish the remaining `mattandjames`-inspired doctrine-depth work so the broad engineering docs and
the Haskell guide match the stronger structure already required by
`development_plan_standards.md`.
That import is explicitly about repository governance and doctrine shape, not about adopting
`mattandjames` product-specific features or runtime assumptions.

### Deliverables

- broad governed engineering docs that define supported contracts add the stronger structure from
  `development_plan_standards.md`: `TL;DR` or `Executive Summary` when the topic is broad,
  explicit `Current Status` notes when current behavior and target direction mix, and explicit
  `Validation` sections when tests or lint prove the contract
- `documents/engineering/implementation_boundaries.md` gains an ownership matrix for Haskell,
  Python, chart, and generated surfaces together with adapter-local-versus-shared-contract type
  boundaries, instance placement rules, and module-boundary doctrine
- `documents/engineering/storage_and_state.md` gains an owner or durability table plus
  failure-mode, rebuild, and cleanup rules for durable and derived state
- `documents/engineering/portability.md` explicitly separates portable platform invariants from
  local harness detail and names which differences are supported product contract versus substrate
  implementation detail
- `documents/engineering/testing.md` keeps the canonical testing doctrine in the stronger
  structure and explicitly calls out preflight expectations, unsupported paths, and per-layer
  validation obligations
- `documents/development/haskell_style.md` points directly at `src/Infernix/Lint/HaskellStyle.hs`,
  separates repository hard-gate inputs from editor-only guidance, and adds review doctrine for
  module shape, function shape, effect-boundary clarity, and typed control flow
- the plan states explicitly that this `mattandjames`-derived follow-on imports repository
  governance, CLI, launcher-boundary, and doctrine-structure practices only; it does not adopt
  offline-browser or Keycloak flows, a single-runtime `llama-server` model, IndexedDB-specific
  docs, checked-in generated PureScript policy, or a container-only execution rule
- `src/Infernix/Lint/Docs.hs` enforces the required broad-doctrine sections for the docs whose
  structure is part of the supported contract

### Validation

- `infernix docs check` fails when the named doctrine docs lose their required
  summary-or-current-status-or-validation structure or contradict their enforced metadata contract
- `infernix test lint` passes with the deeper doc structure and Haskell-guide references in place
- `cabal test infernix-haskell-style` remains the implementation-aligned
  Haskell style gate described by the guide

### Remaining Work

None.

---

## Sprint 6.14: Monitoring Stance Resolution and Final Doctrine Closure [Done]

**Status**: Done
**Implementation**: `documents/README.md`, `documents/engineering/testing.md`, `chart/values.yaml`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/README.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Resolve the supported monitoring stance explicitly and remove the dormant monitoring placeholder
from the supported contract.

### Deliverables

- the repository carries one explicit supported-contract decision for monitoring instead of a
  dangling placeholder
- Monitoring is not a supported first-class surface.
- governed docs and the plan say so explicitly, the dormant `victoria-metrics-k8s-stack` value is
  removed from repo-owned `chart/values.yaml`, the Haskell cluster renderer keeps only an explicit
  disabled upstream Pulsar override so generated Helm values cannot imply monitoring support, and
  the cleanup is recorded in `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
- the docs index and system component inventory point at the chosen monitoring stance so readers do
  not infer support from leftover config alone
- `src/Infernix/Lint/Docs.hs` checks that the governed docs, plan docs, and chart values stay
  aligned on the unsupported monitoring stance

### Validation

- `infernix docs check` fails if the plan, docs index, and unsupported-surface statement diverge
- `infernix docs check` fails if dormant monitoring configuration returns to `chart/values.yaml`
- the cleanup ledger records the legacy monitoring-stack placeholder

### Remaining Work

None.

---

## Sprint 6.15: Validation Warning Hygiene For PureScript And Playwright [Done]

**Status**: Done
**Implementation**: `web/test/Main.purs`, `web/test/run_playwright_matrix.mjs`, `src/Infernix/CLI.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/development/purescript_policy.md`

### Objective

Remove the known non-failing warning noise from the supported web-validation path so `test unit`,
`test e2e`, and `test all` stay future-proof and produce clean supported output.

### Deliverables

- the PureScript unit suite no longer relies on deprecated `runSpec`
- the supported Node-based PureScript test runner preserves non-zero exits without relying on the
  deprecated `runSpec` or `runSpecT` entrypoints
- the retained Playwright harness wrapper sanitizes its child-process environment and delegates to
  `infernix test e2e`, so supported runs do not pass both `NO_COLOR` and `FORCE_COLOR` and the
  Haskell CLI remains the owner of E2E lifecycle orchestration
- the Apple host-native containerized Playwright path avoids forwarding conflicting `NO_COLOR` and
  `FORCE_COLOR` values into the executor
- the governed testing docs describe the supported runner and env-sanitization posture for the web
  test path

### Validation

- `infernix test unit` passes without the PureScript `runSpec` deprecation warning
- `infernix test e2e` passes without the Node warning about `NO_COLOR` being ignored because
  `FORCE_COLOR` is set
- `infernix test all` continues to pass with the warning cleanup in place

### Remaining Work

None.

---

## Sprint 6.16: Residual Canonical-Home and Workflow-Helper Closure [Done]

**Status**: Done
**Implementation**: `README.md`, `documents/engineering/testing.md`, `documents/development/testing_strategy.md`, `documents/README.md`, `src/Infernix/Workflow.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Lint/Docs.hs`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/engineering/testing.md`, `documents/development/testing_strategy.md`, `documents/README.md`, `documents/architecture/runtime_modes.md`, `documents/documentation_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Close the last residual DRY and canonical-topic gaps surfaced by the repo review so the runtime
model, testing doctrine, and shared workflow-helper contract stop overclaiming closure.

### Deliverables

- the root README uses the same honest runtime-language contract as the governed docs and plan:
  one Apple split-executor lane plus two containerized Linux lanes
- `documents/engineering/testing.md` remains the sole canonical testing doctrine, and
  `documents/development/testing_strategy.md` is reduced to supporting operator-detail guidance
  instead of a second authoritative canonical validation surface
- the obsolete root-level `HASKELL_CLI_TOOL.md` imported-doctrine note is removed so CLI,
  style-guide, generated-section, and non-adoption guidance lives only in governed documents and
  implementation-owned registries
- `src/Infernix/Workflow.hs` owns the demo-config generated-banner constant and
  `src/Infernix/DemoConfig.hs` consumes that shared literal instead of keeping a parallel copy
- docs lint and the cleanup ledger both record the closure so those stale guidance or duplicate
  helper surfaces do not quietly return

### Validation

- `infernix docs check` fails if the governed testing-doc metadata or purpose text reintroduce a
  second canonical testing home or if the root runtime-language contract drifts from the governed
  honest-runtime model
- `infernix test unit` continues to pass once demo-config generation and decoding consume one
  shared banner literal
- `infernix test lint` continues to pass after the ledger and docs-lint rules are updated for the
  final canonical-home cleanup

### Remaining Work

None.

---

## Sprint 6.17: Residual Compatibility-Shim Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Cache.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `documents/development/frontend_contracts.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Retire the last compatibility shims that keep obsolete result, generated-contract, and helper-registry
state alive in supported code paths so Phase 6 can close without hidden cleanup work.

### Deliverables

- `src/Infernix/Runtime.hs` and `src/Infernix/Runtime/Cache.hs` read only the supported
  protobuf-backed inference-result and cache-manifest files and stop accepting legacy
  `*.state` fallbacks
- `src/Infernix/CLI.hs` stops deleting the legacy `web/src/Infernix/Web/Contracts.purs` path
  during contract generation, leaving `web/src/Generated/Contracts.purs` as the only supported
  generated frontend-contract output
- `src/Infernix/Cluster.hs` stops removing the legacy `infernix-bootstrap-registry` container and
  `./.build/kind/registry/localhost:30001` namespace as part of supported Harbor-first bootstrap
- unit, integration, and docs validation cover the shim-free behavior, and the cleanup ledger
  records those surfaces as fully closed

### Validation

- `infernix test unit` fails if runtime result IO, cache-manifest reloads, or PureScript
  contract generation still depends on the legacy `*.state`, `default.state`, or
  `web/src/Infernix/Web/Contracts.purs` compatibility paths
- `infernix test integration` fails if the supported cluster bootstrap flow still depends on the
  legacy helper-registry cleanup shims
- `infernix docs check` fails if the plan, cleanup ledger, or supporting docs overclaim full
  closure before those compatibility surfaces are removed

### Remaining Work

None.

---

## Sprint 6.18: Remaining Broad Engineering-Doc Structure Closure [Done]

**Status**: Done
**Implementation**: `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `documents/documentation_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Close the remaining doctrine-depth gap for broad engineering contract docs so the plan stops
overclaiming full structure closure and `infernix docs check` enforces the same stronger shape
consistently across the remaining governed engineering surfaces.

### Deliverables

- `documents/engineering/build_artifacts.md` adds the stronger broad-doctrine structure expected
  by `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `documents/engineering/docker_policy.md` adds the stronger broad-doctrine structure expected by
  `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `documents/engineering/edge_routing.md` adds the stronger broad-doctrine structure expected by
  `development_plan_standards.md`, including summary and validation sections and any explicit
  current-status note required by its final scope
- `src/Infernix/Lint/Docs.hs` extends its document-structure rules so `infernix docs check`
  enforces the required broad-doctrine sections for those remaining engineering docs
- the plan and governed docs claim broader engineering-doc structure closure only with the
  required docs and lint rules in place

### Validation

- `infernix docs check` fails if `documents/engineering/build_artifacts.md`,
  `documents/engineering/docker_policy.md`, or `documents/engineering/edge_routing.md` lose the
  required broad-doctrine sections
- `infernix docs check` fails if the plan or governed docs overclaim doctrine-depth closure
  without the required structure and lint enforcement
- `infernix test lint` continues to pass with the broadened docs-lint structure rules in place

### Remaining Work

None.

---

## Sprint 6.19: Single-Substrate Validation Closure and Simulation Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `bootstrap/linux-cpu.sh`, `bootstrap/linux-gpu.sh`, `web/test/run_playwright_matrix.mjs`, `docker/Dockerfile`, `test/integration/Spec.hs`, `test/unit/Spec.hs`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md`, `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`, `DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `documents/engineering/testing.md`, `documents/engineering/portability.md`, `documents/engineering/edge_routing.md`, `documents/reference/cli_reference.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`

### Objective

Make every supported test command run its complete suite against the built and deployed substrate,
remove simulation from the supported runtime and validation contract completely, and describe
integration and E2E ownership in the final `.dhall`-driven terms.

### Deliverables

- `infernix test integration`, `infernix test e2e`, and `infernix test all` run their complete
  supported suites against the substrate encoded in the generated `.dhall`
- the supported default test story no longer runs a cross-substrate Apple or CPU or GPU matrix from
  one invocation; full substrate closure comes from restaging and rerunning the complete suite for
  each substrate
- the comprehensive model, format, and engine matrix in `README.md` is the authoritative
  integration-test coverage ledger
- one integration suite traverses those README rows or references, reads the active substrate from
  `.dhall`, chooses the corresponding engine binding for each supported row, and carries at least
  one assertion for every such row
- the repository does not maintain separate integration suites per substrate; substrate choice
  happens only through the generated `.dhall`
- Apple host-native `test integration` is launched directly from the host CLI, validates the
  cluster daemon, and manages the host inference daemon for the duration of the test when that
  daemon is needed
- Apple host-native `test e2e` is launched from the host CLI; the host-native Playwright executor
  now uses host `npm exec` fed by the same typed fixture against the published localhost edge port,
  with real execution recorded by Apple cohort validation batches
- Linux substrate test commands all run through `docker compose run --rm infernix infernix ...`,
  and those flows do not manage a host daemon because request consumption, inference, and result
  publication all run from cluster daemons
- Playwright remains substrate-agnostic at the browser layer: the browser suite does not branch on
  substrate id or engine family, and it relies on `infernix-demo` to read `.dhall` and dispatch
  the correct engine behind the routed demo API
- test results report the built substrate unambiguously and never imply matrix-wide coverage they
  did not execute
- supported runtime and validation code carry no simulated cluster, route, or generic
  inference-success fallback behavior on the supported path, and routed Pulsar checks require the
  real Gateway-backed upstream; inference assertions go through the typed adapter harness selected
  by the active substrate file. The repo-local topic spool remains a harness-only transport for
  endpoint-absent unit or isolated daemon checks
- Linux bootstrap entrypoints delegate lifecycle and test commands to the Compose-launched
  `infernix` binary, which owns active-substrate preflight so lane switches cannot reuse a stale
  staged payload

### Validation

- Apple host-native `test all` runs the full supported suite for `apple-silicon`, validates the
  cluster daemon, starts the host inference daemon as needed, and runs the host-native `npm exec`
  Playwright executor against the published localhost edge port without changing the reported
  substrate
- Linux `test all` runs the full supported suite for the built Linux substrate and runs entirely
  through the outer container launcher
- for any given built substrate, integration validation fails if a README row or reference whose
  substrate column names a real engine is not covered by at least one integration assertion using
  the engine selected from `.dhall`
- routed tool-route validation fails if Harbor, MinIO, or Pulsar probes succeed only through the
  direct `infernix-demo` compatibility payloads instead of the real Gateway-backed upstream
  surfaces
- E2E validation fails if browser-side test code branches on substrate id or engine family instead
  of relying on the demo app's `.dhall`-driven dispatch
- docs and test output fail if validation still claims Apple, CPU, and GPU coverage from one
  default matrix invocation or keeps simulation in the supported contract

### Remaining Work

None.

---

## Sprint 6.20: Haskell Style Toolchain Compatibility Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Lint/HaskellStyle.hs`, `docker/Dockerfile`, `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`
**Docs to update**: `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `documents/engineering/testing.md`, `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Restore the supported Haskell style gate on the governed bootstrap surfaces by installing
`ormolu` and `hlint` through `cabal install` against the project `ghc-9.12.4` toolchain into
`./.build/haskell-style-tools/bin/`.

### Deliverables

- `src/Infernix/Lint/HaskellStyle.hs` installs `ormolu` and `hlint` through `cabal install`
  against the project compiler into `./.build/haskell-style-tools/bin/`
- the Linux substrate image bakes the project `ghc-9.12.4` toolchain so the governed runtime
  path does not redownload it on every ephemeral container run
- the Haskell-style, CLI-reference, testing, and Docker-policy docs describe the style-gate
  bootstrap honestly
- the plan and component inventory stop overclaiming full lifecycle rerun closure before the
  supported `linux-cpu` and `linux-gpu` `test` surfaces pass again

### Validation

- `bootstrap/linux-cpu.sh test` passes on the supported outer-container path
- `bootstrap/linux-gpu.sh test` passes on the supported outer-container path
- `infernix lint docs` fails if the Haskell-style, CLI-reference, testing, or Docker-policy docs
  drift from the implemented formatter-toolchain contract

### Remaining Work

None.

---

## Sprint 6.21: Linux Bootstrap Determinism Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster.hs`, `compose.yaml`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md`
**Docs to update**: `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/storage_and_state.md`, `documents/operations/cluster_bootstrap_runbook.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Close the last Linux bootstrap determinism gap by persisting the supported Helm dependency archive
cache across fresh outer-container invocations, removing the Docker Hub-backed MinIO OCI
indirection from that cache-fill path, and repairing the known stale retained Pulsar or
ZooKeeper epoch mismatch without requiring manual lane cleanup.

### Deliverables

- the supported Linux outer-container launcher bakes a reusable image-local cache at
  `/opt/infernix/chart/charts/` and links `/workspace/chart/charts` to it so fresh
  `docker compose run --rm infernix ...` invocations can reuse the same chart dependency archives
- `src/Infernix/Cluster.hs` stops relying on `helm dependency build` to discover the MinIO chart
  through Docker Hub-backed OCI metadata and instead hydrates the governed archive cache with the
  supported direct MinIO tarball URL together with the remaining top-level chart archives
- `cluster up` detects the known stale retained Pulsar or ZooKeeper epoch mismatch, resets only
  the retained Pulsar claim roots for the affected runtime lane, and retries once so governed
  reruns do not depend on manual local cleanup
- the governed local-development, Docker-policy, and plan docs describe the reusable chart-archive
  cache honestly instead of implying every outer-container rerun reconstructs the same dependency
  bundle from the network, and the storage plus bootstrap docs record the targeted Pulsar repair
  path as explicit durability repair rather than cache cleanup
- the final governed `linux-gpu` bootstrap lifecycle rerun passes without depending on a cached
  Docker Hub OCI allowance for the MinIO chart or manual Pulsar state cleanup. The matching
  native `linux-cpu` full-suite lifecycle rerun passed on the recorded validation.

### Validation

- `bootstrap/linux-cpu.sh doctor`, `build`, `up`, `status`, `test`, and `down` pass on the
  supported outer-container path
- `bootstrap/linux-gpu.sh doctor`, `build`, `up`, `status`, `test`, and `down` pass on the
  supported outer-container path, including the targeted Pulsar repair path when stale retained
  ZooKeeper epoch state is present
- `infernix lint docs` fails if the governed local-development, Docker-policy, storage, bootstrap,
  or plan docs drift from the supported Linux bootstrap determinism contract

### Remaining Work

None.

---

## Sprint 6.22: Apple Bootstrap Lifecycle Closure [Done]

**Status**: Done
**Implementation**: `bootstrap/apple-silicon.sh`, `bootstrap/common.sh`, `src/Infernix/CLI.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/Python.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Workflow.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`, `docker/Dockerfile`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/assistant_workflow.md`, `documents/development/local_dev.md`, `documents/development/python_policy.md`, `documents/development/testing_strategy.md`, `documents/engineering/docker_policy.md`, `documents/engineering/portability.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the remaining Apple clean-host lifecycle gaps so the governed stage-0 entrypoint can carry a
supported Apple host through first-run tool activation, host prerequisite reconciliation,
cluster-backed validation, and teardown without relying on the earlier rerun workaround or
substrate-mismatched compatibility shims.

### Deliverables

- `bootstrap/apple-silicon.sh` stops depending on ambient `PATH` side effects to discover freshly
  installed ghcup-managed tools in the same process and instead resolves or verifies the selected
  `ghc`, `cabal`, and Homebrew `protoc` executables explicitly before direct host build handoff
- shared bootstrap helper logic defines the restartable-entrypoint rule explicitly: same-process
  tool installs continue only after the bootstrap verifies command resolution and version, while
  new-shell or reboot requirements stop with a rerun instruction for the same bootstrap command
- Apple host prerequisite reconciliation can install or verify the Homebrew-managed `python@3.12`
  formula and `python3.12` command, a user-local Poetry bootstrap, Node.js, and non-Docker
  operator tools on demand when Apple lifecycle or adapter-validation paths need them
- the Apple Docker boundary is now governed by Phase 1 Sprint 1.12: the current Docker context
  must already target a native arm64 daemon, and the supported path must stop rather than creating
  or switching Docker contexts or creating a VM
- Apple Kind lifecycle code no longer relies on unsupported host bind-mount ownership assumptions,
  does not perform broad pre-Harbor support-image preloads, preloads only Harbor-backed final
  image refs after Harbor publication, and keeps the routed demo API aligned with the active
  staged runtime mode during routed validation
- routed Apple Playwright validation runs host-native `npm exec` against the published
  `127.0.0.1:<edge-port>` edge port, so the Apple lane no longer depends on
  `host.docker.internal` or a dedicated browser container
- the Linux substrate image no longer bakes a conflicting `NO_COLOR` default back into the routed
  E2E lane
- the governed local-development, portability, Python-policy, Apple runbook, cluster-bootstrap,
  assistant-workflow, and root orientation docs describe the implemented Apple lifecycle contract
  instead of the older rerun workaround or built-in-Python bootstrap story
- the supported Apple clean-host validation lane closes without a second manual invocation after
  the first ghcup-managed `cabal 3.16.1.0` install

### Validation

- on a clean Apple Silicon host with Homebrew plus ghcup present,
  `./bootstrap/apple-silicon.sh build` reaches direct Cabal handoff on the first invocation after
  it installs or selects `cabal 3.16.1.0`
- the supported Apple lifecycle rerun closes through
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
  `status`
- on the recorded validation (legacy hardware), the supported Apple lifecycle had reran cleanly through
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down`; that
  evidence is no longer current
- legacy Apple Docker-profile compatibility evidence is not part of the current supported
  workflow contract; native-only Docker-boundary validation is tracked by Phase 1 Sprint 1.12
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C.
- the Apple bootstrap fails fast with actionable messages if the resolved ghcup-managed toolchain,
  Homebrew `protoc`, or current native arm64 Docker daemon still cannot be used in the current
  process
- the supported Apple routed Playwright lane passes without timing out on
  `host.docker.internal`, and the later substrate image rebuild does not reintroduce the prior
  `NO_COLOR`/`FORCE_COLOR` warning conflict
- `infernix lint docs` fails if the governed local-development, Python-policy, portability, or
  runbook docs drift from the implemented Apple lifecycle contract

### Remaining Work

None.

---

## Sprint 6.23: False-Negative Validation Doctrine and Documentation Closure [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/ProcessMonitor.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Close the doctrine gap that lets slow lifecycle convergence be misreported or abandoned as a hard
failure.

### Deliverables

- the governed testing and runbook docs distinguish hard failure from long-running convergence that
  is still making progress in Docker, Harbor, Harbor-backed final-image preload, or teardown
  data-sync steps
- the supported validation doctrine uses inactivity-aware language instead of elapsed-wall-time
  language alone when it describes lifecycle failure classification
- Apple and cluster runbooks describe cold-versus-warm expectations and name the concrete
  first-run phases that can take minutes without emitting steady log lines
- CLI reference docs describe the supported status or progress surfaces operators use before
  concluding that a lifecycle action actually failed
- the plan, runbooks, and testing docs had cited the recorded-validation Apple lifecycle investigation
  plus the recorded-validation split-topology reruns as proof points for the supported
  false-negative doctrine; those reruns were performed on the legacy Apple Silicon hardware and
  no longer count as current proof points. The doctrine itself, the implemented progress
  surfaces, and the docs that describe them remain accurate, but the Apple cohort re-validation
  on the new host demonstrated the same inactivity-aware behavior in Wave A.

### Validation

- `infernix lint docs` fails if the testing doctrine, Apple runbook, cluster runbook, or CLI
  reference docs drift from the supported false-negative classification contract
- the plan and governed docs describe the same long-running lifecycle phases and the same operator
  interpretation rules
- the supported Apple bootstrap lifecycle reruns cleanly through `./bootstrap/apple-silicon.sh doctor`,
  `build`, `up`, `status`, `test`, and `down` while `cluster status` reports active progress
  fields during the in-progress `up` and `down` windows
- the supported validation harness can now report timeout-while-still-progressing distinctly from
  hard lifecycle failure because the lifecycle surface exposes active phase and heartbeat data

### Remaining Work

None.

---

## Sprint 6.24: Harbor Publication Retry Hardening [Done]

**Status**: Done
**Implementation**: `src/Infernix/Cluster/PublishImages.hs`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Close the transient Harbor Docker-push failure modes exposed by the supported Apple lifecycle when
large chart images briefly reset the registry connection during publication or when a retry would
otherwise depend on a transient target tag that no longer exists locally.

### Deliverables

- Docker pushes wait for Harbor registry readiness before every push attempt
- Harbor image publication now uses eight bounded push attempts with capped retry backoff
- repo-owned local image references are published before third-party chart dependencies so the
  locally built substrate payload cannot be displaced by later mirror work before publication
- each push attempt re-tags the source image to the target Harbor reference before pushing, so a
  retry can recover even when the prior target tag disappeared locally
- a failed push still exits successfully when the expected tag is already present or a registry
  pull proves the content became available despite the client-side push failure
- plan, testing, and runbook docs had recorded the recorded-validation Apple lifecycle proof point with
  the then-current steady-state pod count and the supported retry interpretation, plus the
  recorded-validation repo-owned-image ordering and re-tagging proof point; both proof points were on
  the legacy Apple Silicon hardware and no longer count as current evidence. The retry logic
  itself remains implemented in `src/Infernix/Cluster/PublishImages.hs`, and Apple cohort
  re-validation closed in Wave A.

### Validation

- `cabal test infernix-unit` passes on the new Apple Silicon host
- `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, and `down` had passed
  on the recorded validation on the legacy hardware after the retry hardening; that proof point is no
  longer current
- the full `./bootstrap/apple-silicon.sh test` lifecycle had exercised the large Pulsar Harbor
  publication path, integration coverage, routed Playwright E2E, retained-state replay, and final
  cluster teardown successfully on the legacy hardware; that proof point is no longer current
- the recorded validation Apple lifecycle had validated that the repo-owned `infernix-linux-cpu:local`
  image is pushed before third-party images and remains retryable through source re-tagging on
  the legacy hardware; that proof point is no longer current
- final `./bootstrap/apple-silicon.sh status` reports `clusterPresent: False`,
  `lifecycleStatus: idle`, and `lifecyclePhase: cluster-absent`
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C.

### Remaining Work

None. Apple cohort validation closed in [Wave A](cohort-validation-waves.md), and CUDA Linux
cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.25: Cluster-Daemon and Apple Host-Inference Split [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Service.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Runtime/Pulsar.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/values.yaml`, `infernix.cabal`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md`, `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`, `DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/testing_strategy.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/portability.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `documents/tools/pulsar.md`

### Objective

Clarify and implement the final daemon-role contract: the cluster coordinator role owns Pulsar
ingress and dispatch, while the substrate decides whether the engine role runs in-cluster or in a
same-binary host daemon fed by Pulsar batches.

### Deliverables

- `cluster up` deploys the cluster coordinator role for `apple-silicon`, `linux-cpu`, and
  `linux-gpu`; Linux substrates also deploy the cluster engine role
- the role-specific chart templates expose `coordinator.replicaCount` and `engine.replicaCount`;
  Apple sets the cluster engine replica count to 0 and runs the engine role host-native
- on `linux-cpu` and `linux-gpu`, the coordinator publishes batch work, the in-cluster engine
  executes inference, and the engine publishes results
- on `apple-silicon`, the coordinator reads request topics and publishes inference work to derived
  pool/model topics
- same-binary host daemons on Apple read host-role `.dhall`, connect to Pulsar through
  auto-discovered published edge state, consume their assigned pool/member topics, execute
  Apple-native inference, and publish results back through the configured result path
- if operators explicitly scale the coordinator or engine deployments or run multiple Apple host
  executors, Pulsar subscriptions remain the ownership boundary for shared request-topic
  consumption, batch handoff, and result publication
- the staged `.dhall` distinguishes substrate, daemon role (`coordinator` or `engine`), host
  Pulsar connection mode, result topics, stable member ids, and pool/member assignments instead of
  treating Apple host execution as absence of a cluster daemon
- publication and browser-visible metadata distinguish cluster daemon location from inference
  executor location, so `daemonLocation` no longer implies that Apple lacks a cluster daemon
- Pulsar-owned topics, `Shared` pool subscriptions, `Exclusive` pinned subscriptions,
  acknowledgements, and negative acknowledgements form the ownership boundary for clean request
  handoff, inference, and result publication
- legacy plan language that says Apple `cluster up` lacks a cluster coordinator is removed

### Validation

- `infernix test unit` proves that `apple-silicon` renders both coordinator-role and host-engine
  daemon metadata
- `infernix test integration` proves that `apple-silicon` deploys the cluster coordinator,
  starts the host inference daemon when needed, moves batches through the configured Pulsar topic,
  and completes routed inference through the split executor
- Linux integration still proves that `linux-cpu` and `linux-gpu` complete request consumption,
  inference, and result publication from cluster daemons without managing a host daemon
- routed E2E readiness verifies that the browser-visible publication payload reports the cluster
  daemon and Apple host inference executor distinctly before the Playwright container exercises the
  browser surface
- docs lint fails if the plan or governed docs describe Apple cluster-daemon absence as the final
  contract
- `cabal test infernix-unit` passes on the new Apple Silicon host
- `cabal test infernix-haskell-style` passes on the new Apple Silicon host
- `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
  `status` had passed on the recorded validation on the legacy Apple Silicon hardware
  exercising the split topology; that proof point is no longer current
- the full `./bootstrap/apple-silicon.sh test` lifecycle had exercised the Apple host-batch
  topic, the host daemon, every active generated catalog entry, routed Playwright, repeated
  retained-state cluster teardown and bring-up, and final cluster teardown successfully on the
  legacy hardware; that proof point is no longer current
- Apple cohort validation closed in Waves A/A.2; CUDA Linux validation closed in Wave C.

### Remaining Work

None. Apple cohort split-topology validation closed in [Wave A/A.2](cohort-validation-waves.md),
and CUDA Linux cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.26: Lifecycle Warning Classification and Toolchain Noise Closure [Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `web/package.json`, `web/scripts/install-purescript.mjs`, `src/Infernix/Workflow.hs`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/engineering/docker_policy.md`, `documents/development/purescript_policy.md`, `documents/development/python_policy.md`, `documents/engineering/build_artifacts.md`, `README.md`, `DEVELOPMENT_PLAN/README.md`
**Docs to update**: `README.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/engineering/docker_policy.md`, `documents/development/purescript_policy.md`, `documents/development/python_policy.md`, `documents/engineering/build_artifacts.md`, `DEVELOPMENT_PLAN/README.md`

### Objective

Classify every warning observed in the supported `linux-gpu` lifecycle, eliminate warnings that the
repository owns, and document only those warning classes that currently come from upstream tools,
container-build packaging behavior, or normal Kubernetes convergence.

### Deliverables

- the cluster bootstrap runbook owns a warning-classification table that names recoverable
  lifecycle convergence, host environment failures, and toolchain warnings
- operator docs distinguish normal Harbor, MinIO, PostgreSQL, Pulsar, image-publication, preload,
  and retained-state convergence from command failure using lifecycle heartbeat and exit status
- `SystemOOM` is documented as host resource contention rather than an accepted lifecycle warning
- Docker policy records buildx as part of the supported Docker toolchain, and the substrate image
  installs `docker-buildx` for nested Compose builds
- PureScript policy records that direct npm deprecation warnings should be eliminated by migrating
  to maintained tool releases; the current implementation removes the deprecated `purescript` npm
  installer path and validates Spago 1.x with a `glob@13` override
- Python policy records that Poetry is installed into `/opt/poetry` so the substrate image no longer
  uses system pip as root
- Docker policy and the runbook record that npm update notices and GHCup shell-profile adjustment
  messages are not expected from current image builds
- the runbook explicitly documents GHCup's upstream no-update warning as accepted only when the
  pinned toolchain installs and the image build exits zero
- the runbook explicitly documents GHCup's upstream PATH advice as accepted only when the
  Dockerfile-owned `PATH` is effective in the same image build

### Validation

- `infernix docs check` passes with the warning-classification docs and plan status aligned
- a Linux substrate image refresh removes the nested Compose Bake/buildx warning
- web install/build/unit validation remains free of npm deprecation warnings after the PureScript
  compiler acquisition change and Spago `glob@13` override
- Linux substrate image build output remains free of Python root-pip warnings after the Poetry
  virtual-environment layout change
- Linux substrate image build output remains free of npm update notices and GHCup shell-profile
  adjustment messages
- supported lifecycle reruns still pass after warning cleanup and do not reclassify command failures
  as acceptable warning noise
- on the recorded validation (legacy hardware), the supported `linux-gpu` lifecycle had passed through
  `./bootstrap/linux-gpu.sh doctor`, forced `docker compose build infernix` image refresh,
  `./bootstrap/linux-gpu.sh build`, `up`, `status`, `test`, `down`, `purge`, and final `status`;
  that proof point is no longer current
- the final `./bootstrap/linux-gpu.sh test` rerun had passed Haskell style, Python checks,
  Haskell unit, PureScript unit, Haskell integration, routed Playwright E2E, retained-state
  replay, and final teardown after the substrate image copied `web/scripts/` before npm
  `postinstall`; that proof point was on the legacy Linux/CUDA host and is no longer current
- CUDA Linux cohort validation closed in Wave C with a clean `linux-gpu` full-suite lifecycle on
  the native Linux/CUDA host.

### Remaining Work

None. CUDA Linux cohort validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.27: Real Dhall Substrate Codec Closure [Done]

**Status**: Done
**Implementation**: `src/Infernix/Substrate.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Config.hs`, `src/Infernix/Models.hs`, `src/Infernix/Workflow.hs`, `src/Infernix/Types.hs`, `cabal.project`, `infernix.cabal`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/dependency_management.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace the legacy banner-prefixed JSON payload at `infernix.dhall` with a real Dhall
record while preserving the existing staged filename, generated catalog contents, daemon-role
metadata, and browser/API JSON surfaces derived from the decoded Haskell ADTs.

### Deliverables

- generated substrate materialization writes a syntactically valid Dhall record instead of JSON
- substrate readers decode through the `dhall` Haskell library and then validate the existing
  `DemoConfig` domain invariants
- the substrate decoder type records the schema for the generated substrate payload (reflected, no tracked `.dhall`)
- `cabal.project` carries the documented wildcard `allow-newer: *:base, *:template-haskell`
  dependency posture needed for the project `ghc-9.12.4` toolchain and Dhall's transitive closure
- unit coverage proves the generated payload has Dhall record syntax and still round-trips through
  the runtime decoder

### Validation

- `cabal build all:exes`
- `cabal test infernix-unit`
- `infernix lint docs`

### Remaining Work

None.

---

## Sprint 6.28: Test Fixture and Lint Gate Retirement [Done]

**Status**: Done
**Implementation**: `test/unit/Spec.hs`, `test/integration/Spec.hs`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/Lint/Docs.hs`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: `documents/development/no_env_vars.md`, `documents/development/testing_strategy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Retire env-driven test isolation; land the durable lint gates that prevent future env-var or
PATH-resolved invocation regressions.

### Deliverables

- `test/unit/Spec.hs` and `test/integration/Spec.hs` replace every `setEnv`/`unsetEnv` call with
  typed fixtures or in-process fixtures. Every `getEnvironment` whole-env capture is removed from
  test code.
- `src/Infernix/Lint/HaskellStyle.hs` rejects `lookupEnv`, `getEnv`, `getEnvironment`, `setEnv`,
  and `unsetEnv` outside the remaining explicitly named non-test exceptions. After the 2026-06-06
  CLI/Files/Workflow no-env cleanup, the `envFunctionExemptedFiles` list contains only `Setup.hs`
  and the lint module itself (`src/Infernix/Lint/HaskellStyle.hs`); the `src/Infernix/Python.hs`
  and `src/Infernix/CLI.hs` rows are both gone (CLI.hs no longer performs env IO), and the closed
  CLI/Files/Workflow exemptions are recorded as Removed (2026-06-06) in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- `src/Infernix/Lint/HaskellStyle.hs` rejects any `proc "<bare-name>"` matching a known external
  tool; the non-test exemption list (`bareNameProcExemptedFiles`) now contains only
  `src/Infernix/Lint/HaskellStyle.hs` itself, and the earlier `src/Infernix/Lint/Files.hs` and
  `src/Infernix/Workflow.hs` exemptions were removed (recorded in the Completed rows of
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)).
- `src/Infernix/Lint/HaskellStyle.hs` also rejects direct `findExecutable` / `findExecutables`
  discovery outside its own forbidden-token list. `src/Infernix/Python.hs` resolves Poetry through
  `HostConfig.toolPaths.poetry` or fixed `HostTools` fallback candidates, while
  `src/Infernix/Cluster.hs` resolves `nvkind` through `HostConfig.toolPaths.nvkind` or fixed
  bootstrap fallback candidates. `Setup.hs` also avoids PATH discovery for `proto-lens-protoc` and
  uses the deterministic repo-local `.build/proto-tools/bin/proto-lens-protoc` bootstrap path.
- `src/Infernix/Lint/Docs.hs` rejects governed root and `documents/` language that reintroduces
  project-prefixed env names or shell path overrides as supported operator configuration.
- `src/Infernix/Lint/Chart.hs` rejects any `env:` block in
  `chart/templates/deployment-{coordinator,engine,demo}.yaml`.

### Validation

- The static greps and the typed lint gates themselves remain trivially re-runnable on any host:
  `rg -n "lookupEnv|getEnv|getEnvironment|setEnv|unsetEnv|withOptionalEnv|INFERNIX_DATA_ROOT|INFERNIX_PULSAR_ADMIN_URL|INFERNIX_PULSAR_WS_BASE_URL" test` must return zero matches; the
  `rg` invocation against `proc "<bare-tool>"` must return zero matches; `rg -n
  "findExecutable|findExecutables" Setup.hs src test` must return only the Haskell-style lint module's
  forbidden-token list; the Haskell-style gate must no longer exempt the test suites.
- the recorded validation (legacy hardware): `cabal build test:infernix-integration` had passed after the
  integration fixture changed from `proc "python3"` to an in-process TCP listener;
  `cabal test infernix-haskell-style` had passed after removing the test exemptions;
  `cabal test infernix-unit` had passed after updating the Compose launcher contract assertion;
  `cabal run infernix -- lint docs`, `lint files`, `lint chart`, and `lint proto` had passed
  with the docs override gate active;
  `LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu --file compose.yaml config`
  and the matching CPU compose config had rendered the expected two-bind launcher from the
  single Compose file. All of those passes were on the legacy hardware and no longer count as
  current proof points; the code paths themselves are unchanged and the same commands are
  expected to pass on the new Apple Silicon host.
- the recorded validation (legacy hardware): the governed `linux-gpu` `infernix test all` pass had been the
  real-cluster evidence for the full lint + unit + integration + Playwright E2E stack on the
  legacy Linux/CUDA host; that proof point is no longer current. CUDA Linux cohort
  `infernix test all` re-validation closed in Wave C on the native Linux/CUDA host.
- Apple cohort validation closed in Wave A; CUDA Linux validation closed in Wave C.

### Remaining Work

None. Apple cohort lint/unit/integration validation closed in
[Wave A](cohort-validation-waves.md), and CUDA Linux cohort lint/unit/integration/`test all`
validation closed in [Wave C](cohort-validation-waves.md).

---

## Sprint 6.29: Declarative-State Phase Prose Rewrite [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md` (prose only)
**Docs to update**: this file

### Objective

Rewrite Phase 6 prose so dated hardware proof points are replaced with present-tense
descriptions of the supported gates, and so cross-phase cleanup notes are anchored on the
canonical architecture documents.

### Deliverables

- Phase 6 Phase Status and Current Repo Assessment use present-tense vocabulary; the validation
  reset note moves to a single line referencing
  [cohort-validation-waves.md](cohort-validation-waves.md) and
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- Per-sprint Validation sections use cohort closure markers; `Wave A/A.1/A.2/A.3`
  and `Wave C` references remain as cohort closure markers.
- Sprint 6.28 `proc "<bare-name>"` and `env:` block lint descriptions stay declarative; references
  to Sprint 3.10 / 4.13 / 5.9 / 7.17 env-var cleanup work cite those sprints by name without
  reopening cleanup history inside Phase 6 prose.

### Validation

- the phase-specific lexical guard for dated hardware proof-point prose returns zero matches.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

None.

---

## Sprint 6.30: Single-Toolchain GHC 9.12.4 Closure [Done]

**Status**: Done
**Implementation**: `cabal.project`, `infernix.cabal`, `docker/Dockerfile`, `src/Infernix/Lint/HaskellStyle.hs`, `bootstrap/apple-silicon.sh`, `README.md`, `documents/engineering/dependency_management.md`, `documents/engineering/docker_policy.md`, `documents/engineering/host_tools_manifest.md`, `documents/engineering/testing.md`, `documents/development/haskell_style.md`, `documents/reference/cli_reference.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: every file in `Implementation` above

### Objective

Standardize the project, the Linux substrate image, the Apple host bootstrap, the lint formatter
bootstrap, and every documentation surface on a single GHC 9.12.4 toolchain. The Linux substrate
image installs exactly one GHC; `ormolu` and `hlint` install through the same compiler the
project builds against.

### Deliverables

- `cabal.project` pins `with-compiler: ghc-9.12.4` and carries only the `allow-newer:` entries
  required for the supported dependency set.
- `infernix.cabal` declares `tested-with: ghc ==9.12.4`.
- `docker/Dockerfile`:
  - `ARG GHC_VERSION=9.12.4` is the single GHC selector.
  - the image installs and selects only `${GHC_VERSION}` through ghcup.
  - only `/opt/ghc/${GHC_VERSION}` is symlinked.
- `bootstrap/apple-silicon.sh` pins `APPLE_GHC_VERSION="9.12.4"`.
- `src/Infernix/Lint/HaskellStyle.hs`:
  - `formatterInstallArgs` is rewritten to invoke
    `cabal install ormolu hlint --installdir=./.build/haskell-style-tools/bin/ --install-method=copy --overwrite-policy=always`
    against the project compiler.
  - `installFormatterToolsWithCommand` calls `cabal` directly.
  - formatter-bootstrap errors describe the single project compiler path.
- `README.md` uses `9.12.4` in the supported toolchain sections.
- `documents/engineering/dependency_management.md`, `documents/engineering/host_tools_manifest.md`,
  `documents/engineering/docker_policy.md`, `documents/engineering/testing.md`,
  `documents/development/haskell_style.md`, and `documents/reference/cli_reference.md` describe
  the single-toolchain posture keyed on `cabal.project` and `docker/Dockerfile`.
- `DEVELOPMENT_PLAN/system-components.md` names the single `ghc-9.12.4` project toolchain.
- `DEVELOPMENT_PLAN/README.md` Phase 6 status row records Sprint 6.30 as closed.

### Validation

- `cabal build all` exits zero against GHC 9.12.4.
- `cabal test infernix-haskell-style`, `cabal test infernix-unit`, and
  `cabal test infernix-integration` all exit zero.
- `infernix test lint`, `infernix lint files`, `infernix lint docs`, `infernix lint chart`,
  `infernix lint proto` all exit zero.
- the toolchain lexical guard for unsupported compiler pins and formatter-only compiler symbols
  returns matches only inside `legacy-tracking-for-deletion.md` Completed rows.
- `docker compose --project-name infernix-linux-cpu --file compose.yaml build infernix` succeeds
  against the single-GHC substrate image.
- `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all`
  exits zero on `linux-cpu`.
- Apple cohort `./bootstrap/apple-silicon.sh up && ./.build/infernix test all` exits zero against
  GHC 9.12.4.
- The Apple cohort and CUDA Linux cohort runs are tracked in `cohort-validation-waves.md` as the
  Sprint 6.30 closure batch.

### Remaining Work

None. The four toolchain cleanup rows live in `legacy-tracking-for-deletion.md` Completed.

---

## Sprint 6.31: Matrix Drift and Headless Apple Validation Gates [Done]

**Status**: Done
**Code-side closure**: Complete on the recorded Linux outer-container lane - `src/Infernix/Models.hs` exports `matrixRowReadmeKeys`, `src/Infernix/Lint/Docs.hs` now parses the README model matrix and fails `infernix lint docs` when a cell drifts from the generated runnable catalog, explicit residual list, or `Not recommended` state, and `test/unit/Spec.hs` proves the README lint keys are unique and cover every matrix row id. Proven by `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm ... infernix cabal run exe:infernix -- lint docs` and `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm ... infernix cabal run exe:infernix -- test unit` with live source/docs mounts.
**Cohort gate**: Closed [Wave I](cohort-validation-waves.md) for the selected `linux-gpu` plus `linux-cpu` per-family scope. Sprint 1.15 / Wave L retains historical Apple real-payload integration and focused routed Playwright evidence for its then-active catalog, plus the paired `linux-cpu` full gate. The former generated Apple bridge and Objective-C Core ML smoke evidence is superseded by active Sprint 1.20 and cannot supply corrected-source Apple closure. Linux native payload strict smoke passes in the CUDA image and the routed service-path evidence is recorded in Wave I.
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Lint/Docs.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `README.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`
**Docs to update**: `README.md`, `documents/development/testing_strategy.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/architecture/model_catalog.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the research corrections enforceable. The docs and generated catalog must not drift on engine
recommendations, and Apple validation must prove the headless Metal/Core ML materialization lane
instead of the legacy Tart helper.

### Deliverables

- extend docs/catalog lint so README matrix cells and generated catalog cells agree on promoted,
  residual, and `Not recommended` states
- add validation that Apple headless materialization does not invoke Tart, require an unlocked
  login keychain, require `xcrun -find metal`, or install a toolchain during inference
- add integration assertions that materialization failures leave no partial final engine root and
  are redelivered or negatively acknowledged when asynchronous
- update per-family integration and routed E2E fixtures for promoted/residual cells: Apple
  CTranslate2 viability, MT3-PyTorch and MR-MT3 through `mt3-infer`, Omnizart's maintained
  PyTorch piano row, Wan Apple MPS residual, and Basic Pitch TensorFlow residual

### Validation

- `infernix lint docs` fails on README/generated-catalog engine-cell drift
- `infernix test unit` proves the exported README matrix lint keys are unique and cover every
  Haskell-owned matrix row id
- the historical Apple bridge/source-smoke validation is superseded; active Sprint 1.20 instead
  records installed upstream MLX GPU-operation and coremltools compute-device observation plus
  native-free materialized-root proof before routed model inference
- CUDA Linux cohort reruns the native engine materialization lane and per-family real-output suite
- legacy Tart references remain only in the deletion ledger or explicit historical notes; the
  generated CLI reference describes the retained Tart-free manifest materialization command

### Remaining Work

None. Wave I evidence is recorded for the selected `linux-gpu` plus `linux-cpu` gates, and the
Apple materialization/e2e/all evidence is recorded as supporting host evidence.

---

## Sprint 6.32: Engine Pool Routing Validation Gates [Done]

**Status**: Done
**Code-side closure**: Complete for unit-enforced invalid-state rejection on the present Linux
outer-container lane — generated configs and substrate decoding now reject duplicate pool/member
ids, unknown model ids, ambiguous model ownership, empty pool/member assignments, one-sided
pool/member links, raw topic-like ids, `Failover` service consumers, non-positive inflight limits,
and routable models with no eligible member. Topic derivation and service subscription selection
are covered for Apple, Linux CPU, and Linux GPU. Proven by
`./bootstrap/linux-cpu.sh build`; rebuilt-image
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test unit`;
and mounted live-source `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
`cabal run exe:infernix -- lint files/docs/proto/chart`, `cabal run exe:infernix -- docs check`,
and `cabal run exe:infernix -- test lint`. Current source also adds the real Pulsar
single-host logical `Shared` backlog harness in `test/integration/Spec.hs` and compile-validates it
on the present Linux outer-container lane with a mounted-source linux-gpu Compose launcher run of
`cabal build test:infernix-integration`; the 2026-06-16 Apple integration rerun executes it against
the live Apple Pulsar lane. The same current-source mounted linux-gpu validation also passes
`infernix test lint`, `infernix test unit`, focused `infernix lint files/docs/proto/chart`,
`infernix docs check`, and `git diff --check`. The 2026-06-16 rebuilt-image Linux CPU integration
pass exercises the Kubernetes validation side: engine-pool placement across two workers,
unique-topic `Shared` backlog/backpressure, pod replacement, node drain, anti-affinity, lifecycle
rebinding, production `demo_ui = false` publication, and pool-topic exactly-once accounting.
**Cohort gate**: Closed [Wave J](cohort-validation-waves.md) — real Pulsar integration has proved
pinned `Exclusive` duplicate-consumer rejection, same-machine Apple `Shared` subscription
coexistence, Apple single-host logical `Shared` backlog/backpressure, and Apple production
`demo_ui = false` coordinator-plus-engine-pool assertions, plus Linux CPU pool placement and
backpressure. Linux GPU/CUDA pool placement and full cohort validation closed on 2026-06-20 via full
`./bootstrap/linux-gpu.sh test` paired with rebuilt-image `./bootstrap/linux-cpu.sh test`; physical
Apple multi-host routing is hardware-deferred proof while no second Apple host is available.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs` (substrate decoder type = reflected schema; no tracked `.dhall`), `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `documents/architecture/engine_pool_routing.md`, `documents/architecture/daemon_topology.md`
**Docs to update**: `README.md`, `documents/architecture/engine_pool_routing.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`, `documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the engine-pool routing contract mechanically enforceable. Invalid model placement must fail
before rollout, and scalable pools must use Pulsar backpressure rather than coordinator-side node
guessing.

### Deliverables

- generated-config and unit validation reject raw batch-topic strings in pool configuration
- unit tests reject unknown model ids, duplicate pool/member ids, routable models with no eligible
  members, and Apple host daemon startup with an unknown host id
- integration validates that `demo_ui = false` omits only demo/frontend/identity surfaces while
  retaining the coordinator and engine pools
- integration validates same-machine Apple `Shared` pool consumers can coexist on one derived
  pool/model topic
- integration validates `Shared` pool consumers with bounded permits and a backlog on one logical
  Apple member still allow free logical members on the same Apple host to receive new work
- integration validates pinned per-member routes use `Exclusive` and reject duplicate consumers
- integration validates Linux CPU Kubernetes placement and `Shared` backlog/backpressure on unique
  derived pool/model topics

### Validation

- `infernix lint docs`
- `infernix test unit`
- `infernix test integration` on the active substrate
- cohort reruns for single-host logical Apple pool behavior, Linux CPU pool placement, and Linux
  GPU/CUDA pool placement, with physical Apple multi-host proof deferred until hardware exists

### Remaining Work

None. Unit validation rejects invalid routing graphs and subscription states, and proves derived
topic/member selection for all three substrates. Wave J closed Linux GPU pool-placement and full
cohort validation on 2026-06-20, paired with rebuilt-image `linux-cpu` validation. Physical Apple
multi-host routing is tracked as hardware-deferred proof, not as a blocker for the current
single-host logical backpressure gate.

---

## Sprint 6.33: Fail-Closed HA and Service-Loop Assertions [Done]

**Status**: Done
**Code-side closure**: Complete and validated 2026-06-24 (code-side: the rebuilt `linux-cpu` image compiles
`test:infernix-integration`, with `infernix lint docs` / `test unit` / `test lint` green). Built on the
realness enforcement established by Phase 0 (the `infernix-haskell-style` realness check + the
`check-code` AST guard) and the real Linux engines + real per-family fixtures + fail-closed per-row
int/e2e owned by Phase 4, it strengthened the HA / chaos / service-loop suites so they assert a real,
completed result instead of tolerating a status-only pass (this is proven on the Linux lanes; on
apple-silicon a full per-model service-loop cannot currently assert completion because the run
OS-OOM-kills the daemon before results exist — owned by Sprint 6.37 / Phase 4 Sprint 4.26, red):
`validateServiceRuntimeLoop`
(`test/integration/Spec.hs`) now uploads the per-family input fixture and asserts completion + per-family
result shape (it previously asserted neither), and `assertCompletedResultPayload` is now family-aware via
`ConversationInferenceResultPayload.inferenceResultArtifacts` across its chaos/throughput call sites
(frontend / coordinator / engine pod replacement, engine node drain, multi-user durable throughput,
fan-in batching, fan-out). This sprint does **not** re-own the realness lint (Phase 0) or the real
per-family fixtures (Phase 4); it consumes them.
**Cohort gate**: Closed [Wave K](cohort-validation-waves.md) — `linux-gpu` + `linux-cpu`.
**Implementation**: `test/integration/Spec.hs`
**Docs to update**: `documents/development/chaos_testing.md`, `documents/engineering/testing.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the HA / chaos / service-loop suites fail closed on a non-real or incomplete result, building on —
not duplicating — the realness enforcement (Phase 0) and the real-engine fixtures (Phase 4).

### Deliverables

- `validateServiceRuntimeLoop` asserts completion + per-family result shape
- `assertCompletedResultPayload` is family-aware across every chaos / throughput call site

### Validation

- `./bootstrap/linux-gpu.sh test` plus rebuilt `./bootstrap/linux-cpu.sh test` HA / chaos suites fail
  closed when a result is non-real or incomplete

### Remaining Work

None.

---

## Sprint 6.34: Docs-Lint Coverage and No-Env/No-PATH Enforcement Closure [Done]

**Status**: Done
**Code-side closure**: Complete 2026-06-29. `src/Infernix/Lint/Docs.hs` now includes the authoritative
configuration, no-env, host-tool, cluster-config, realness, Apple materialization, Keycloak, and Phase 7
plan docs in the governed lint set. `src/Infernix/Lint/HaskellStyle.hs` resolves formatter bootstrap and
`cabal format` through `HostConfig.toolPaths.cabal` or fixed `HostTools` candidates instead of bare
`cabal`; `HostTools.hostToolFallbackCandidates` includes the Linux launcher `/root/.ghcup/bin/{cabal,ghc}`
defaults. `Setup.hs` no longer reads `INFERNIX_BUILD_ROOT` or inherited `PATH`, resolves Cabal from fixed
absolute candidates, and keeps only the mechanically allowed deterministic `Env.setEnv "PATH"` shim for
the proto-lens custom setup. `bootstrap/common.sh`, `bootstrap/linux-cpu.sh`, and
`bootstrap/apple-silicon.sh` no longer accept inherited command overrides or inherited `PATH`, and
`web/scripts/install-purescript.mjs` extracts the PureScript archive with Node `zlib`/tar parsing instead
of bare `mktemp` / `tar`.
**Cohort gate**: Machine-independent unless bootstrap behavior changes require a clean-env lifecycle
rerun. The code-side closure changed bootstrap shell behavior but did not run a full clean-env launcher
lifecycle on this host; the shell entrypoints were syntax-checked and the machine-independent lint/unit
gates passed.
**Implementation**: `src/Infernix/Lint/Docs.hs`, `src/Infernix/Lint/HaskellStyle.hs`, `src/Infernix/HostTools.hs`, `Setup.hs`, `bootstrap/common.sh`, `web/scripts/install-purescript.mjs`, `documents/architecture/configuration_doctrine.md`, `documents/development/no_env_vars.md`, `documents/engineering/host_tools_manifest.md`
**Docs to update**: `documents/documentation_standards.md`, `documents/architecture/configuration_doctrine.md`, `documents/development/no_env_vars.md`, `documents/engineering/host_tools_manifest.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the validation layer enforce the documented no-env/no-PATH and governed-doc coverage contracts.

### Deliverables

- expand `requiredDocs` and `phaseDocs` so every authoritative configuration, realness, tool, and
  Phase 7 document participates in `infernix lint docs`
- replace `HaskellStyle.hs` bare `cabal` invocations with manifest/fixed-candidate resolution that
  matches the host-tools doctrine
- retire `Setup.hs` process-environment mutation or document and mechanically confine any unavoidable
  Cabal setup exception outside supported runtime/configuration behavior
- remove inherited `BOOTSTRAP_*` shell command overrides or confine them to an explicit non-operator
  test harness
- replace Node bare `mktemp` / `tar` invocations with Node APIs or documented absolute tool paths
- align the host-tools manifest with the Dockerfile's `/root/.ghcup/bin/{cabal,ghc}` Linux defaults
  and the real pre-binary bootstrap tool inventory

### Validation

- `node --check web/scripts/install-purescript.mjs`
- all four bootstrap scripts (`bootstrap/common.sh` plus the three lane scripts) parse under `bash -n`
- targeted static search across `Setup.hs`, `src/`, `test/`, `web/`, `python/`, `bootstrap/`, and chart
  templates for forbidden env/PATH and bare-tool patterns; remaining hits are comments/token lists plus
  the allowed `Setup.hs` deterministic `Env.setEnv "PATH"` shim
- `cabal build all`
- `cabal build test:infernix-integration`
- `cabal test infernix-unit --test-options='--hide-successes'`
- `cabal run exe:infernix -- internal materialize-substrate apple-silicon --demo-ui true`
- `cabal run exe:infernix -- test lint`
- `cabal run exe:infernix -- lint files`
- `cabal run exe:infernix -- lint docs`
- `cabal run exe:infernix -- lint chart`
- `cabal run exe:infernix -- lint proto`

### Remaining Work

None.

---

## Sprint 6.35: Expanded MT3 Catalog Integration and E2E Gate [Done]

**Status**: Done — proven by Wave P (2026-07-04)
**Code-side closure**: Complete. The integration suite and routed Playwright suite traverse the
generated active catalog, and unit/docs lint see the expanded README/catalog matrix with
`music-mt3-infer` and `music-mr-mt3`. The PyTorch engine carries the resulting MT3 compatibility
contract: `transformers` bounded to `>=4.46,<4.50` across the CPU/CUDA/Apple groups, the real
`torch.utils.checkpoint` shim, declared `absl-py`, and no-cache MT3 generation with the
`T5Block.forward` `cache_position` wrapper. Machine-independent gates are green: Linux-image
`infernix lint docs`, Linux-image `cabal test infernix-unit`, and
`poetry --directory python run check-code`. The per-attempt image-digest failure→fix chronology
lives in [cohort-validation-waves.md](cohort-validation-waves.md).
**Cohort gate**: Closed [Wave O](cohort-validation-waves.md) → [Wave P](cohort-validation-waves.md)
(2026-07-04). Both `linux-gpu` and `linux-cpu` full `infernix test all` are GREEN with routed
Playwright `9/9` over the expanded catalog (real MIDI for both MT3 rows), including the 27 GB
`video-wan21-t2v` row once Phase 8 eager model-cache staging pre-staged the Wan weights. Apple uses
the catalog-supported PyTorch CPU binding.
**Implementation**: `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `src/Infernix/Models.hs`, `src/Infernix/Lint/Docs.hs`, `python/adapters/pytorch_python.py`, `python/engines/pytorch/pyproject.toml`
**Docs to update**: `README.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/development/demo_app_test_plan.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the post-replacement catalog proof explicit: every generated catalog row, including
`music-mt3-infer` and `music-mr-mt3`, must be exercised by integration and routed browser workflows
before the validation phase returns to `Done`.

### Deliverables

- keep README matrix, generated catalog, and docs-lint row coverage in lockstep for the two MT3 rows
- run the catalog-driven integration workflow against both new rows and fail closed on
  `status=failed`
- run the routed browser per-model workflow against both new rows through the same generated catalog
  the demo webapp exposes
- record the selected accelerator plus `linux-cpu` evidence in Wave O

### Validation

- Code-side gates: Linux-image `infernix lint docs`, Linux-image `cabal test infernix-unit`, and
  `poetry --directory python run check-code` pass.
- Cohort gate: rebuilt `./bootstrap/linux-cpu.sh test` and `./bootstrap/linux-gpu.sh test` over the
  expanded catalogs are GREEN (Wave O → Wave P), with routed Playwright `9/9` and real MIDI for both
  MT3 rows. The historical per-attempt failure→fix diagnostics are recorded in
  [cohort-validation-waves.md](cohort-validation-waves.md).

### Remaining Work

Both MT3 rows are proven: `linux-cpu` full-suite GREEN (`9/9`, 2026-07-02) and the clean `linux-gpu`
`9/9` closed by **Wave P** (2026-07-04) once Phase 8 eager model-cache staging pre-staged the
CUDA-only `video-wan21-t2v` weights. No remaining work — this sprint is closed.

---

## Sprint 6.36: Real-Output and Matrix Validation Hardening [Done]

**Status**: Done — code-side hardening landed and machine-independent-validated; Wave R proved the Apple routed per-model matrix, and Wave S proved the same substrate-agnostic browser assertions on rebuilt `linux-cpu` and `linux-gpu` full-suite lanes.
**Code-side closure**: Complete for the machine-independent-verifiable pieces (2026-07-08). Integration already asserts real, non-empty inline text for the text families and fetches every artifact row with a byte+magic-byte probe (`assertResultFamilyContract` + `assertResultObjectRefFetchable`, from Sprints 4.23/6.33). New this sprint: `Chat.purs` marks a result body with `data-inline-output="present"|"absent"` so a fabricated or empty result rendered behind the `"No inline output."` placeholder can no longer pass a real-output check; the routed browser matrix now requires `data-inline-output="present"` and rejects the placeholder for text families (defeating the fallback); and a catalog-completeness guard asserts the model-picker option set equals the published demo-config catalog (the matrix rows minus the active-mode residuals). Verified by the web unit suite (`71/71`), `node --check` on the Playwright spec, and `cabal build all` (integration compiles).
**Cohort gate**: Closed by [Wave R](cohort-validation-waves.md) and [Wave S](cohort-validation-waves.md). Apple routed Playwright was GREEN for this sprint on 2026-07-08 (`test e2e` ran the per-model browser matrix with the catalog-completeness guard + `data-inline-output` real-text assertion across all 16 apple models). Wave S then closed the rebuilt Linux lanes on 2026-07-09: `./bootstrap/linux-cpu.sh test` passed routed Playwright `15/15`, and `./bootstrap/linux-gpu.sh test` passed routed Playwright `15/15` with the browser per-model matrix completing every catalog row in 18.5 minutes.
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `web/playwright/inference.spec.js`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/testing.md`, `documents/development/demo_app_test_plan.md`

### Objective

Close the "proves less than it appears" gaps the 2026-07-06 review found in the fail-closed matrix
suites, so a shrunken catalog or an empty text result cannot pass.

### Deliverables

- **Done (prior sprints, confirmed).** Integration asserts real non-empty inline text for the text
  families and runs the per-row byte+magic-byte probe for every artifact row.
- **Done.** E2E: real-text assertion for text families via the new `data-inline-output="present"`
  marker (defeats the `"No inline output."` fallback in `Chat.purs`); a catalog-completeness guard
  (picker set equals the published catalog / matrix rows minus active-mode residuals).
- **Closed by Wave R/Wave S.** The catalog-completeness guard is the supported union check: the picker
  option set must equal the published active-substrate catalog, so active-mode residuals cannot hide a
  shrunken browser matrix. The row-14 path is real and no longer needs an xfail carve-out, and the
  integration suite owns the byte+magic-byte artifact probe for source-separation rows.
- **Done (prior sprint, confirmed).** Platform-state DOM assertions (`#runtime-mode`, `#edge-port`,
  `#control-plane-context`, `#daemon-location`, `#inference-dispatch-mode`).

### Validation

- Code-side: the web unit suite (`71/71`) compiles the `Chat.purs` change, `node --check` accepts the
  Playwright spec, and the integration suite compiles — all green (2026-07-08).
- Cohort: [Wave R](cohort-validation-waves.md) routed Playwright on Apple, and [Wave S](cohort-validation-waves.md) routed Playwright on rebuilt `linux-cpu` + `linux-gpu`.

### Remaining Work

None. The Apple routed per-model matrix (catalog-completeness guard + `data-inline-output` real-text
assertion) is **GREEN** ([Wave R](cohort-validation-waves.md), 2026-07-08), and rebuilt `linux-cpu` /
`linux-gpu` routed Playwright is **GREEN** ([Wave S](cohort-validation-waves.md), 2026-07-09).
RBAC / admin-vs-user / lifecycle / dashboard e2e is owned by
[Phase 9 Sprint 9.8](phase-9-access-control-and-monitoring.md).

---

## Sprint 6.37: Apple-Silicon Memory-Bounded Validation Lane [Done]

**Status**: Done — unblocked by Phase 4 Sprint 4.26 for the original Apple-only classifier; the
memory-exhaustion classification is in the integration lane, the **Apple integration never-OOM proof
is GREEN** ([Wave R](cohort-validation-waves.md), 2026-07-08: full 16-model per-model
`test integration` all `status=completed`, zero OS OOM-kill), and Wave S revalidated the Linux full
suites for that scope. Sprint 6.38 supersedes this with typed resource-admission validation across
Apple, Linux CPU, and Linux GPU.
**Code-side closure**: Complete for the classification (2026-07-08). Phase 4 Sprint 4.26's admission control landed, so an over-budget apple-silicon model now publishes a clean `status=failed` instead of OS-OOM-killing the daemon. The integration lane adds `classifyAppleMemoryBoundedResult`: an over-budget model is a clean per-row `AppleMemoryBoundedFailClosed` (its message names the inference RAM budget), distinguishable from a fabricated pass (`status /= completed`) and a real engine failure; a genuinely missing result is named as the OS-OOM-kill / stall symptom. Rows that fit the budget must still complete and honor the per-family real-output contract, so behavior is unchanged on hosts where the whole catalog fits. Verified by `cabal build all` (the integration suite compiles) and `cabal test infernix-haskell-style`.
**Cohort gate**: Closed by [Wave R](cohort-validation-waves.md) apple-silicon and [Wave S](cohort-validation-waves.md) Linux. The full 16-model Apple `test integration` is **GREEN (2026-07-08)**: all 16 apple catalog models `status=completed`, **zero** OS OOM-kill, the daemon surviving every model including the heavy diffusion rows. The rebuilt Linux lanes are **GREEN (2026-07-09)** for the original fail-closed result-handling scope; Linux CPU pod-memory and Linux GPU VRAM admission are reopened in Sprint 6.38.
**Implementation**: `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/development/demo_app_test_plan.md`, `documents/development/chaos_testing.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make the apple-silicon full per-model validation lane a first-class, memory-safe gate: with Phase 4
Sprint 4.26 admission control landed, prove the full 16-model `test integration` and the routed
per-model browser matrix either complete or fail-closed per row with **zero** OS OOM-kill.

### Deliverables

- **Done.** Memory-exhaustion classification in the apple-silicon validation lane
  (`classifyAppleMemoryBoundedResult`): an over-budget model is a clean per-row `status=failed`,
  distinguishable from a stall (missing result) or a fabricated pass; a missing result is named as the
  OS-OOM-kill symptom.
- **Done.** The full per-model Apple attestation is recorded in [Wave R](cohort-validation-waves.md);
  Linux full-suite attestation is recorded in [Wave S](cohort-validation-waves.md). The live HA/chaos
  tail ran after the fail-closed per-model step, proving the daemon survived the catalog on this host.

### Validation

- Code-side: the integration suite compiles with the classification and the style gate is green
  (2026-07-08).
- Cohort (apple-silicon, paired with Phase 4 Sprint 4.26): the full 16-model `test integration` is
  **GREEN ([Wave R](cohort-validation-waves.md), 2026-07-08)** — all `status=completed`, zero OS
  OOM-kill.
- Linux full suites: **GREEN ([Wave S](cohort-validation-waves.md), 2026-07-09)** — rebuilt
  `linux-cpu` and `linux-gpu` full `./bootstrap/* test` lanes passed integration and routed
  Playwright.

### Remaining Work

None. The apple-silicon full per-model `test integration` never-OOM proof and the routed per-model
Playwright matrix are **GREEN** ([Wave R](cohort-validation-waves.md), 2026-07-08), and the
`linux-cpu`/`linux-gpu` full suites are **GREEN** ([Wave S](cohort-validation-waves.md), 2026-07-09).
Code-side (the classification) is complete.

---

## Sprint 6.38: Typed Resource Admission Validation Across Substrates [Done]

**Status**: Done — code-side complete and Wave T full live integration/e2e validation is closed on
`linux-cpu` plus the selected `linux-gpu` accelerator.
**Historical-scope note**: this sprint validates the pre-audit resource-admission API only. The
Phase 1 compiler/refiner supersedes that path, and Phase 6 Sprint 6.44 owns the current
independently indexed Linux GPU RAM/VRAM enforcer and its new cohort evidence.
**Code-side closure**: Complete on 2026-07-09 in the Linux outer-container lane. Unit coverage now
exercises pure admission decisions for enforced, enforced-zero, and explicit unenforced budgets;
config validation accepts mixed-size catalogs; protobuf/storage/result-bridge roundtrips preserve
typed `ModelMemoryLimitExceeded`; and `test/integration/Spec.hs` classifies per-row capacity
failures by constructor and MiB quantities instead of parsing text. Routed Playwright now records the
browser-facing half of the same contract by accepting only typed `ModelMemoryLimitExceeded` failures
for rows whose catalog footprint exceeds the active demo-config budget, while preserving
fail-closed behavior for any other failed result; the web unit suite also covers the live-discovered
append-before-snapshot race where a fast failed result arrives before the active conversation
snapshot, and the reducer now preserves already-seen append messages when a stale same-context
snapshot arrives afterward. The stale-snapshot merge is validated on rebuilt Linux CPU image
`sha256:05e0aadf5ea0feb98f25e82ab196f23893be0441e59f5e91f9fec346bfa6d8c0` by
`./bootstrap/linux-cpu.sh build` and
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix
test unit` (Haskell unit plus web `75/75`). Earlier gates also passed
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix
test lint`, `infernix lint files|docs|proto|chart`, `infernix docs check`, and a source-bound
`cabal build test:infernix-integration` compile preflight.
**Latest Wave T evidence**: The 2026-07-10 `./bootstrap/linux-cpu.sh test` rerun on
`sha256:05e0aadf5ea0feb98f25e82ab196f23893be0441e59f5e91f9fec346bfa6d8c0` passed Haskell style,
Python `check-code`, Haskell unit, web `75/75`, and the full live integration lane, including typed
`ModelMemoryLimitExceeded` classifications for the Linux CPU over-budget rows and smaller-model
continuity through the HA/chaos tail. The routed browser gate remained open in this attempt because Playwright ended
`14/16`: the pre-existing artifact preview grant timing spec failed, and the matrix row with the
typed terminal over-budget payload still did not render a visible capacity message.
**Current fix**: The browser reducer now ignores conversation snapshots whose context does not match
the active context, and the routed artifact helper waits for bounded text/JSON preview readiness
after the download grant. Focused mounted-source PureScript validation passes `76/76`; a rebuilt
`linux-cpu` image
`sha256:c01a9a070ca842b973543301dcbaaa039811492f707fdc20c804aa30bd5f40ee` passes
`./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web `76/76`. Its full
`./bootstrap/linux-cpu.sh test` rerun passed style/static/unit, web `76/76`, and the full live
integration lane including typed CPU admission and smaller-model continuity; routed Playwright ended
`15/16` on the remaining capacity-message render race. Current source fixes the stale-displayed-context
append path and focused mounted-source PureScript validation passes `77/77`; rebuilt image
`sha256:84e3915260e5fd7684b817bf520e9eaca4f40946665d86ae2afb5276b1eedfcb` now contains this fix and
passed the `./bootstrap/linux-cpu.sh build` CLI-help smoke plus rebuilt-image `infernix test unit`
with web `77/77`. The full-suite rerun then passed style/static/unit, typed CPU admission,
smaller-model continuity, HA/chaos, throughput, platform recovery, lifecycle rebinding, and
anti-affinity, but failed in a later lifecycle cluster-up after a one-shot retained Pulsar claim-root
reset was exhausted. Rebuilt image
`sha256:0bf82aba452b2bee8f5de6c4ee136c7d72537ac0dbd4377ee52ee3718d77c0aa` contains the bounded
retained Pulsar bootstrap repair-loop fix and passed `./bootstrap/linux-cpu.sh build` plus the
CLI-help smoke and rebuilt-image `infernix test unit` with web `77/77`. Its full-suite rerun passed
the front gates and full live integration, including typed CPU admission, smaller-model continuity,
HA/chaos, throughput (`totalPrompts = 12`, `p95Seconds = 82.15346002578735`), platform recovery,
lifecycle rebinding, anti-affinity, and the `demo_ui = false` lifecycle; repeated retained-data
cluster-ups no longer hit the prior dirty Pulsar metadata failure. Routed Playwright reached
`15/16` and failed only the matrix visible capacity-message assertion after receiving the typed
terminal `ModelMemoryLimitExceeded` payload. Current source adds a same-rendered-context reducer
guard for transient `activeContextId` staleness plus a raw Haskell-wire decode regression; focused
mounted-source PureScript validation passes `79/79`. Rebuilt image
`sha256:4e2e2a9f642ecc15635df849539b82a847d350db19e161cf6517d56a29ea6b62`
contains that fix and passed `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` with web `79/79`. Its full-suite rerun passed Haskell style,
Python `check-code`, Haskell unit, web `79/79`, and full live integration, including typed CPU
admission, smaller-model continuity, throughput (`totalPrompts = 12`,
`p95Seconds = 65.4941475391388`), platform recovery, lifecycle rebinding, anti-affinity, and the
`demo_ui = false` lifecycle; routed Playwright reached `15/16` and failed only the visible
capacity-message matrix assertion. Current source now pins submitted prompts into the active
conversation before fast terminal results. Rebuilt image
`sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306`
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `80/80`. The full-suite rerun on that rebuilt image passed Haskell
style, Python `check-code`, Haskell unit, web `80/80`, and full live integration, including typed
CPU admission, smaller-model continuity, platform recovery, lifecycle rebinding, anti-affinity, and
the `demo_ui = false` lifecycle; routed Playwright reached `15/16` and failed only the visible
capacity-message DOM assertion after receiving the typed terminal payload. Current source now keeps
a per-context browser conversation cache and focused mounted-source PureScript validation passes
`81/81`. Rebuilt Linux CPU image
`sha256:5ccdac2c89b435c1452f63c7fc5df41ca07893bfabc581134aef95db0468ace9` contains that fix and
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image `infernix test
unit` with web `81/81`. Its full rerun passed the front gates and progressed through the live
Linux CPU integration lane up to PostgreSQL lifecycle rebinding, then hung in the second
`cluster up` warm-cache path with an idle MinIO NodePort connection. Current source adds bounded
MinIO warm-cache/model-bootstrap HTTP calls in `Infernix.Runtime.Pulsar` (`HEAD` sentinel probes
15s, write responses 300s), and focused mounted-source Haskell validation passes
`cabal test infernix-unit`. Rebuilt Linux CPU image
`sha256:f0276a2efcae1fa7b2d33a7bb7a0e442b9d4c2be5687515c439f9cb75bf909ec` contains the timeout fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `81/81`. Its full `linux-cpu` rerun failed before runtime validation
on a Haskell style import-order diff in `Infernix.Runtime.Pulsar`; current source applies the
style-only reorder, and focused mounted-source validation passes `cabal test infernix-haskell-style`.
Rebuilt Linux CPU image
`sha256:5d423bd3d988103e6777fcfa80b92da07684263af056f7e6c9395e4802176cec` contains that style fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` with web `81/81`. Its full rerun passed the front gates and advanced through
typed CPU admission, HA/recovery, model-bootstrap deduplication, throughput (`totalPrompts = 12`,
`p95Seconds = 65.50490140914917`), Harbor/MinIO/Pulsar recovery, and PostgreSQL failover before
stalling in the lifecycle-rebinding second `cluster up` while republishing Harbor images; diagnostics
showed the integration process sleeping with a direct `[docker] <defunct>` child. Current source
replaces the monitored subprocess waiter in `Infernix.ProcessMonitor` with a blocking reaper plus
heartbeat loop; focused mounted-source validation passes `cabal test infernix-haskell-style` and
`cabal test infernix-unit`. Rebuilt Linux CPU image
`sha256:ab2f12cd81a094ffc267eacfb637ae055c8b3c8cd31e364dfc2f54cbcdf21597` contains the monitor fix
and passes `./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web
`81/81`. Its full `linux-cpu` rerun validated the monitor fix by advancing past the previous
lifecycle-rebinding publish stall and through typed CPU admission plus HA replacement/drain, then
failed in the model-bootstrap failover/deduplication integration step after timing out on the ready
topic for `integration-bootstrap-chaos-1783761854482798`. Current source carries the
bootstrap-failover remediation, and focused mounted-source `cabal test infernix-haskell-style` plus
`cabal test infernix-unit` pass. Rebuilt Linux CPU image
`sha256:534f631468380d9e59df713e4e8c78b976e17b17e0c64eb09be4eff8d6f41388` contains the remediation
and passes `./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web
`81/81`. Its full `linux-cpu` rerun passed the front gates, full live integration, the previous
model-bootstrap failover/deduplication gate, PostgreSQL lifecycle rebinding, anti-affinity, and the
`demo_ui = false` lifecycle. Routed Playwright passed `15/16`, including Sprint 9.9
auth/RBAC/account-switching and artifact coverage, then failed only the browser matrix visible
capacity-result assertion after receiving the typed terminal `ModelMemoryLimitExceeded` payload.
Current source projects the rendered chat pane from the active context id plus the per-context
conversation cache so a stored terminal result for the selected context cannot be hidden behind a
stale `activeConversation` pane. Focused mounted-source PureScript validation passes `82/82`, and
`node --check web/playwright/inference.spec.js` passes. Rebuilt Linux CPU image
`sha256:e09f824b06b489a574288dbafcf1c8cc5920ae0bcb1a96cea91306a6cd57221c` contains that
render-projection fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun
passed Haskell style, Python `check-code`, Haskell unit, web `82/82`, and full live integration,
including typed CPU admission, throughput (`totalPrompts = 12`,
`p95Seconds = 86.15112495422363`), lifecycle rebinding, anti-affinity, and the `demo_ui = false`
lifecycle. Routed Playwright reached `15/16` and failed only the `audio-demucs-htdemucs` visible
capacity-result assertion after proving the target context was active. Current source hardens stale
WebSocket generation handling and subscription readiness. Focused mounted-source validation passes
Haskell style/unit for `src/Infernix/Demo/WebSocket.hs`, web unit `82/82`, and
`node --check web/playwright/inference.spec.js`. Rebuilt Linux CPU image
`sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d` contains this fix and
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front
gates and full live integration, including typed CPU admission, model-bootstrap
failover/deduplication, throughput (`totalPrompts = 12`, `p95Seconds = 65.46250057220459`),
lifecycle rebinding, anti-affinity, and `demo_ui = false`; routed Playwright reached `15/16` and
failed only the `audio-demucs-htdemucs` visible capacity-result assertion after observing and
validating the typed terminal payload. Current source gives browser-facing Pulsar readers unique
per-stream names and tags Playwright-observed WebSocket frames by browser socket generation, so the
matrix waits for live-generation snapshots and terminal patches instead of accepting frames from
superseded sockets. `node --check web/playwright/inference.spec.js` passes for that helper change.
Mounted-source Haskell validation also passes `cabal test infernix-haskell-style infernix-unit` with
`src/Infernix/Runtime/Pulsar.hs` mounted into the Linux CPU launcher image, and `git diff --check`
is clean for the touched files. Rebuilt Linux CPU image
`sha256:eeb58064f9eca14c008b9c976380c5c7745a4c6079a5bd8885b3935c864532a5`
(`20070858505` bytes, created `2026-07-11T14:49:26.455414736-04:00`) contains this fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, proving typed Linux CPU admission, smaller-model continuity, lifecycle rebinding,
throughput (`totalPrompts = 12`, `p95Seconds = 65.51375341415405`), anti-affinity, and
`demo_ui = false`. Routed Playwright reached `14/16` and failed on the artifact download-button
replacement race plus the remaining `audio-demucs-htdemucs` visible capacity-result DOM assertion
after typed terminal-payload validation. Current source fixes the routed browser harness by waiting
for upload-record echo before artifact downloads, retrying against a re-resolved artifact card until
the webapp-proxy download grant is ready, and waiting for the exact typed capacity text with a
resubscription fallback. `node --check web/playwright/inference.spec.js` and `git diff --check` pass
for the touched files. Rebuilt Linux CPU image
`sha256:d49b4799375df7a0e5726d16717ab6dc4e09fc8baa685969484099027f81c4c8`
(`20070886873` bytes, created `2026-07-11T17:27:02.378037428-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, proving typed Linux CPU admission, smaller-model continuity, lifecycle rebinding,
throughput (`totalPrompts = 12`, `p95Seconds = 69.06893110275269`), anti-affinity, and
`demo_ui = false`. Routed Playwright reached `15/16`: artifact upload/preview/download coverage
passed, but the remaining matrix assertion still failed to render the `audio-demucs-htdemucs`
capacity result after resubscription. The next Wave T gate is the capacity-result render fix and a
clean full `linux-cpu` rerun. Current source now waits for the matching server prompt patch and
requires terminal results to reference that prompt message id; focused
`node --check web/playwright/inference.spec.js` and `git diff --check` pass for that follow-up.
Rebuilt Linux CPU image
`sha256:30d597efe4284a74c606860d7a0ef6d4fd5123076de11ad0c8e3da476925190e`
(`20070997197` bytes, created `2026-07-11T20:08:36.089424841-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration (`totalPrompts = 12`, `p95Seconds = 65.60747718811035`) with the known
`music-omnizart` warm-cache HTTP 403 warning, then routed Playwright reached `15/16`: Sprint 9.9
auth/RBAC/logout switching and artifact coverage were green, but the matrix still failed the
`audio-demucs-htdemucs` visible capacity-result assertion after resubscription. Current source
strengthens that fallback to require a new-socket conversation snapshot or patch containing the
matching typed capacity result before asserting the DOM; `node --check web/playwright/inference.spec.js`
and `git diff --check` pass. Rebuilt Linux CPU image
`sha256:681420399273889da1e64ce6e43576ffe8a06ad87114b8e069903ab79d3d92f9`
(`20070973633` bytes, created `2026-07-11T22:49:09.072629435-04:00`) contains that
fallback and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). The next validation gate is a clean full
`linux-cpu` rerun on this image, then the selected `linux-gpu` accelerator gate. The full rerun on
that image passed the front gates and live integration (`totalPrompts = 12`, `p95Seconds =
70.42682695388794`) with the known `music-omnizart` warm-cache warning, then routed Playwright
reached `15/16`: Sprint 9.9 auth/RBAC/logout switching and artifact coverage were green, but the
matrix still failed the `audio-demucs-htdemucs` visible capacity-result assertion even after a
result-bearing resubscription attempt.

Rebuilt Linux CPU image
`sha256:c911771090115baa928d6bf43f14ef804cfcdc8706bc96ab3fe6b62f48a19a6f`
(`20088000300` bytes, created `2026-07-12T02:30:27.200982353-04:00`) contains the explicit tagged
`InferenceError` WebSocket contract fix and passes `./bootstrap/linux-cpu.sh build`, the CLI-help
smoke, rebuilt-image `infernix test unit` (Haskell unit plus web `83/83`), and rebuilt-image
`infernix test e2e`. The E2E run completed live integration with typed Linux CPU admission,
smaller-model continuity, HA/chaos, lifecycle, and throughput coverage, then passed routed
Playwright `16/16` in 3.6 minutes, including the per-model browser matrix in 2.5 minutes.
Selected accelerator closure followed on rebuilt `linux-gpu` image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896`; `./bootstrap/linux-gpu.sh test`
passed Haskell style, Python checks, Haskell unit, web `83/83`, full live integration,
HA/recovery, and routed Playwright `16/16` in 17.1 minutes. The integration run classified
over-budget rows as typed `ModelMemoryLimitExceeded` with GPU VRAM budget source
(`availableMib = 4096`) while smaller rows continued, and the browser matrix verified the routed
capacity-message path.
**Cohort gate**: Closed [Wave T](cohort-validation-waves.md) — full live `linux-cpu` and selected
`linux-gpu` integration/e2e evidence is recorded for typed resource admission.
**Implementation**: `test/unit/`, `test/integration/Spec.hs`, `web/test/`, `web/playwright/`,
`src/Infernix/Lint/Docs.hs`, `src/Infernix/ProcessMonitor.hs`, and substrate-specific validation
helpers that inspect generated runtime config and live daemon results.
**Docs to update**: `README.md`, `documents/development/testing_strategy.md`,
`documents/development/chaos_testing.md`, `documents/development/demo_app_test_plan.md`,
`documents/engineering/testing.md`, `documents/architecture/realness_contract.md`, and this plan.

### Objective

Prove typed memory admission behaves correctly across substrates and cannot regress to catalog-wide
startup failure, stringly error parsing, or disabled guards on zero/negative budgets.

### Deliverables

- Unit coverage for pure admission decisions across `UnifiedHostRam`, `PodRam`, and `GpuVram`.
- Config-validation coverage proving a catalog with at least one over-budget model still validates
  when other models fit.
- Apple budget coverage proving over-pledged host calculation yields enforced `0 MiB`, not
  `UnenforcedMemoryBudget`.
- Linux CPU coverage proving admission uses the cluster engine pod memory limit.
- Linux GPU coverage proving admission uses GPU VRAM rather than CPU RAM.
- Integration and browser coverage proving `ModelMemoryLimitExceeded` reaches the result bridge and
  UI as typed data with explicit `requiredMib` / `availableMib`.

### Validation

- `infernix test unit` covers pure admission, config validation, and payload conversion.
- `infernix test integration` exercises over-budget and in-budget rows in one daemon session.
- `infernix test e2e` verifies the demo-app capacity message and smaller-model success.
- `infernix lint docs` rejects retired doctrine that says Linux memory budgets are informational or
  that config validation fails the daemon for any over-budget model.

### Remaining Work

None.

---

## Sprint 6.39: Capability-Gating Lint and Managed-Transition Coverage [Done]

**Status**: Done — the capability-gating lint rules (`rawDestructiveViolations`,
`emptySubprocessEnvViolations`) and routed-Playwright managed-transition coverage are code-side closed
(machine-independent gates), and the single-accelerator (apple-silicon) plus linux-cpu full-suite
sign-off is closed by [Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-16 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style` (the new capability-gating rules are
clean on the tree and were negative-tested: an injected `rm -rf` and `env = Just []` both fail),
`infernix lint docs`, and `node --check web/playwright/inference.spec.js` all green on the
apple-silicon lane. No Python surface changed, so `poetry run check-code` is not applicable.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
**Implementation**: `src/Infernix/Lint/HaskellStyle.hs`, `web/playwright/inference.spec.js`
**Blocked by**: Sprint 1.16, 5.12
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase — add the
capability-gating lint rules to `src/Infernix/Lint/HaskellStyle.hs` (no raw `rm` / `docker exec rm`;
require `SubprocessEnv` / `CommandOutcome`) and add routed-Playwright managed-transition coverage
that exercises the evidence-gated readiness paths — encoding evidence, not hope. It generalizes the
results-side realness contract to state transitions: every operation that acts on a system state
requires typed evidence for that state, so the tests must observe the returned evidence rather than
assume a raw primitive succeeded. Reference the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- capability-gating lint rules in `src/Infernix/Lint/HaskellStyle.hs` that reject raw `rm` and
  `docker exec rm` destructive primitives and require the `SubprocessEnv` / `CommandOutcome`
  capability-carrying wrappers
- routed-Playwright managed-transition coverage in `web/playwright/inference.spec.js` that exercises
  the evidence-gated readiness paths rather than assuming readiness from an unguarded wait
- the coverage asserts on the typed evidence returned by each managed transition, so a non-evidence
  readiness path fails closed

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `infernix lint docs` pass; `poetry run check-code` passes for the routed-Playwright surface
- the capability-gating lint fails when a raw `rm` / `docker exec rm` or a non-capability subprocess
  invocation is introduced
- the routed managed-transition Playwright coverage fails when a readiness path returns no evidence
- all gates are exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

- code-side closed 2026-07-16. Landed this sprint:
  - capability-gating lint rules in `src/Infernix/Lint/HaskellStyle.hs`: `rawDestructiveViolations`
    rejects raw `rm -rf` / `rm -fr` and `docker exec ... rm` outside the cluster-lifecycle module
    (grandfathered for its container-scoped retained-state scrub), and `emptySubprocessEnvViolations`
    rejects `env = Just []`, requiring a typed `Infernix.Cluster.Subprocess.SubprocessEnv` (which
    always carries `HOME`/`TMPDIR`). Both were negative-tested (an injected `rm -rf` and
    `env = Just []` each fail) and are clean on the current tree
  - routed-Playwright managed-transition coverage in `web/playwright/inference.spec.js`:
    `waitForTerminalConversationPatchAfter` awaits the real terminal result evidence (the Sprint 5.12
    readiness path, no rollout proxy) and now explicitly asserts the typed terminal-evidence shape
    (a decoded result with one of the two typed terminal statuses), so a non-evidence readiness path
    fails closed
- validated with `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint docs`, and `node --check web/playwright/inference.spec.js`
- the apple-silicon plus linux-cpu full-suite cohort sign-off closed under
  [Wave V](cohort-validation-waves.md) (2026-07-20); no remaining work exists

---

## Sprint 6.40: Unbounded-Exec/HTTP Capability-Gating Lints [Done]

**Status**: Done — the `unboundedExecViolations` and `unboundedHttpViolations` capability-gating lint
rules are code-side closed (machine-independent gates), and the single-accelerator (apple-silicon)
plus linux-cpu full-suite sign-off is closed by [Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-19 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style` (both new rules negative-tested: an
injected raw `createProcess` in a guarded file fails `unboundedExecViolations`, and an injected raw
`withResponse` in the download surface fails `unboundedHttpViolations`), `infernix lint files/docs/proto/chart`,
and `infernix docs check` all green on the apple-silicon lane. No Python surface changed, so
`poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
**Implementation**: `src/Infernix/Lint/HaskellStyle.hs`
**Blocked by**: Sprint 1.16, 1.17, 6.39
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
`documents/development/haskell_style.md`, and the phase's existing engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — close the
enforcement gap that let raw unbounded exec and raw upstream HTTP reach the two flake sites. It adds
two capability-gating sub-rules to `src/Infernix/Lint/HaskellStyle.hs`, mirroring the existing
`rawDestructiveViolations` / `escapeTokenViolations` per-rule exemption pattern, so a new call site
off the bounded kernels fails the build. It applies the
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
doctrine's line-based enforcement layer to the process-spawn and upstream-HTTP surfaces.

### Deliverables

- `unboundedExecViolations`: forbids raw `readCreateProcessWithExitCode` / `createProcess` /
  `waitForProcess` and peers in production `src/Infernix/` files outside a shrinking
  `unboundedExecExemptedFiles` list (kernel `Subprocess.hs`, `HaskellStyle.hs`, plus the deferred
  cluster surface `Cluster.hs` / `ProcessMonitor.hs` and the engine/runtime/host spawn surface)
- `unboundedHttpViolations`: forbids raw `withResponse` in production `src/Infernix/` outside the
  bounded download wrapper's module (`Runtime/Pulsar.hs`) and the lint module, scoped narrowly to the
  untrusted upstream-model-download surface and leaving trusted in-cluster MinIO calls untouched
- both rules wired into `checkSourceReadability` and negative-tested via the style gate

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint files/docs/proto/chart`, and `infernix docs check` are exercised on both the
  apple-silicon and linux-cpu lanes
- `unboundedExecViolations` fires on an injected raw `createProcess` in a guarded file, and
  `unboundedHttpViolations` on an injected raw `withResponse` in the download surface; both pass on
  the migrated tree

### Remaining Work

- the apple-silicon plus linux-cpu full-suite cohort sign-off of the two lint rules closed under
  [Wave V](cohort-validation-waves.md) (2026-07-20); no remaining work exists

---

## Sprint 6.41: ProcessMonitor Retirement & Readiness-Wait Kernel Migration [Done]

**Status**: Done — the `ProcessMonitor` retirement, the shared `retryCommandOutput` primitive, the
eager-model-cache barrier, the full twelve-wait individual bounded-wait migration onto
`awaitReadiness`/`budgetDeadline`, and the `threadDelayViolations` lint gate are code-side closed
(machine-independent, adversarially reviewed), and the single-accelerator (apple-silicon) plus
linux-cpu full-suite sign-off is closed by [Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-19 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style` (ormolu + hlint + the new
`threadDelayViolations` readability rule + cabal-format), `infernix lint files/docs/proto/chart`,
`infernix docs check`, and `poetry run check-code` all green on the apple-silicon lane. The migration
was adversarially reviewed (two behavior-divergence findings both resolved: `waitForHarborPostgresPodsReady`
now skips its destructive repair on the final poll exactly as the original did, and `budgetDeadline` is
exact for all `attempts >= 0`)
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Runtime/Pulsar.hs`,
`src/Infernix/Lint/HaskellStyle.hs`, `infernix.cabal` (`src/Infernix/ProcessMonitor.hs` deleted)
**Blocked by**: Sprint 1.16, 6.40
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
`documents/development/haskell_style.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, and the
phase's existing engineering/reference docs

### Objective

This sprint is the deferred hardening half of the Bounded-Command Application & Bounded-HTTP reopen —
the broad readiness-wait migration and the retirement of the lying heartbeat that the flake sites
depended on. Sprints 3.15/4.29/6.40 killed both observed flakes; this sprint removes the surrounding
hand-rolled poll loops and the `ProcessMonitor` heartbeat whose `touchLifecycleProgress` rewrite could
mask a stall, following the `waitForHarborRegistryOrDirty` precedent from Sprint 3.14. It generalizes
the [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
readiness-returns-evidence kernel across the cluster surface.

### Deliverables

Landed 2026-07-19 (code-side closed, machine-independent gates green, adversarially reviewed):

- retired `src/Infernix/ProcessMonitor.hs` entirely: its sole importer (`Cluster.hs`) now runs the ten
  monitored lifecycle commands (docker build/pull/tag/cp, crictl pull, save|import stream) through new
  bounded `runCommandBounded`/`tryCommandBounded` helpers over
  `Infernix.Cluster.Subprocess.runBoundedCommand` under named `Timeout` budgets, so a `CommandTimedOut`
  is a loud bounded failure instead of an unbounded "still running" heartbeat; deleted the module, its
  `infernix.cabal` `other-modules` entry, and its `unboundedExecExemptedFiles` row. The removed
  `touchLifecycleProgress` heartbeat had no control-flow consumer (only `cluster status` display), so
  no behavior is lost except the hang-mask
- migrated the shared `retryCommandOutput` retry primitive onto `awaitReadiness` under a `Deadline`
  derived exactly from the legacy `attempts x delayMicros` budget, bounding all six of its consumers
  (kind kubeconfig, kubernetes API, Harbor registry, Gateway CRDs, routed/direct Pulsar surfaces) at
  once; the last-non-empty error is retained in the timeout diagnostic
- migrated `waitForEagerModelCacheReady` (which re-implemented the kernel's poll/stall/ceiling inline)
  onto `awaitReadiness`, minting the `WarmModelCacheReady` witness from a real null-pending observation
- **completed the full individual bounded-wait migration** — all twelve remaining hand-rolled `go n`
  readiness loops now fold onto `awaitReadiness` under the shared
  `Infernix.Evidence.Readiness.budgetDeadline :: Int -> Int -> Deadline` bridge (encodes the legacy
  `attempts × delayMicros` budget as a required `Deadline`, exact for all `attempts >= 0`): in
  `Cluster.hs` `waitForLinuxGpuResources`, `waitForHarborPostgresPodsReady` (mid-loop repair state +
  attempt counter + last-error retention carried in `IORef`s the probe threads; the destructive repair
  is skipped on the final poll exactly as the original's give-up guard did),
  `waitForHarborPostgresPrimaryPod`, `waitForOperatorManagedPersistentClaims`,
  `waitForPersistentClaimBound`, `waitForKindClusterAbsence`, `waitForPulsarStatefulSetRollout` (a
  blocking `kubectl rollout status --timeout` poll driven as a bounded poll-counter),
  `reconcileKeycloakRealmConfiguration`; in `Runtime/Pulsar.hs`
  `waitForTopicCompactionCompleteViaPulsar` and `resolveContextModelIdForDispatch`; in `CLI.hs`
  `waitForInternalPulsarResult` and `waitForPlaywrightSurface`. `retryDeadline` now delegates to the
  shared `budgetDeadline`
- **added the `threadDelayViolations` lint gate** to `src/Infernix/Lint/HaskellStyle.hs` (wired into
  `capabilityGatingViolations`): raw `threadDelay` in production `src/Infernix/` is a build error
  outside the readiness kernel (`Evidence/Readiness.hs`), the lint module, and a deliberately shrinking
  `threadDelayExemptedFiles` backoff/heartbeat/runtime-loop-park list. `CLI.hs` is intentionally kept
  **out** of the list — its two waits migrated, so the gate now keeps it clean

### Validation

- fully code-side closed 2026-07-19 on the apple-silicon machine-independent gate set:
  `cabal build all` (`-Wall -Werror`, clean), `cabal test infernix-unit` (PASS), `cabal test
  infernix-haskell-style` (PASS — ormolu + hlint + the new `threadDelayViolations` readability rule +
  cabal-format), `infernix lint files/docs/proto/chart` and `infernix docs check` (all `EXIT=0`), and
  `poetry run check-code` (PASS, unchanged Python surface). The migration was adversarially reviewed;
  both surfaced behavior-divergence findings were resolved (`waitForHarborPostgresPodsReady` final-poll
  repair skip; `budgetDeadline` exact for `attempts <= 1`)
- the single-accelerator (apple-silicon) plus `linux-cpu` full-suite cohort sign-off closed under
  [Wave V](cohort-validation-waves.md) (2026-07-20)

### Remaining Work

Code-side closed 2026-07-19 (all deliverables above landed and machine-independent-validated), and the
single-accelerator (apple-silicon) plus `linux-cpu` full-suite cohort sign-off closed under
[Wave V](cohort-validation-waves.md) (2026-07-20). No remaining work exists.

---

## Sprint 6.42: Unbounded-Engine-Spawn Capability-Gating Lint [Done]

**Status**: Done — the `unboundedEngineSpawnViolations` capability-gating lint keeps new engine-spawn
call sites off the raw process primitives and on the Phase 4 Sprint 4.30 grant-gated capped-engine
kernel; code-side closed 2026-07-21 on the machine-independent gate set, and the single-accelerator
(apple-silicon) plus `linux-cpu` behavioral cohort sign-off closed under
[Wave W](cohort-validation-waves.md) on 2026-07-24 with no remaining work.
**Code-side closure**: complete (2026-07-21). Added the `unboundedEngineSpawnViolations` sub-rule to
`src/Infernix/Lint/HaskellStyle.hs` (wired into `checkSourceReadability`), mirroring the existing
`unboundedExecViolations` / `threadDelayViolations` per-rule exemption pattern (Sprint 6.40/6.41): raw
`readCreateProcessWithExitCode` / `createProcess` / `waitForProcess` on the engine-spawn surface in
production `src/Infernix/` is a style-gate error outside the Sprint 4.30 capped-engine kernel module
(`Infernix.Runtime.CappedEngine`) and a shrinking `unboundedEngineSpawnExemptedFiles` list (which reuses
the bounded-command exemption set so both gates shrink in lockstep), so a new engine subprocess that does
not consume a `MemoryGrant` fails the style gate. The kernel is added to `unboundedExecExemptedFiles`
(the legitimate raw engine-spawn surface) and `threadDelayExemptedFiles` (the watchdog poll). Gate set
(GREEN 2026-07-21): `cabal build all` (`-Wall -Werror`), `cabal test infernix-unit` (the new rule
negative-tested — fires on an injected raw `createProcess` in a guarded file, exempts the kernel, passes
a clean line), `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, and
`infernix docs check`.
**Cohort gate**: apple-silicon + linux-cpu, [Wave W](cohort-validation-waves.md) — the lint travels
with the Phase 4 Sprint 4.30/4.31 behavioral proof (no host OOM; over-capacity rows cleanly
typed-rejected as `ModelMemoryLimitExceeded`). Closed 2026-07-24.
**Implementation**: `src/Infernix/Lint/HaskellStyle.hs`
**Blocked by**: Sprint 4.30, 6.40
**Docs to update**: `documents/architecture/bounded_inference_memory.md`,
`documents/development/haskell_style.md`, and the phase's existing engineering/reference docs

### Objective

This sprint is the enforcement half of the memory-safety-by-construction reopen for this phase — close
the gap that would let a raw unbounded engine spawn reach a production call site off the grant-gated
capped-engine kernel. It adds one capability-gating sub-rule to `src/Infernix/Lint/HaskellStyle.hs`,
applying the
[../documents/architecture/bounded_inference_memory.md](../documents/architecture/bounded_inference_memory.md)
doctrine's line-based enforcement layer to the engine-spawn surface, exactly as Sprint 6.40's
`unboundedExecViolations` did for the cluster-subprocess surface.

### Deliverables

- `unboundedEngineSpawnViolations`: forbids raw `readCreateProcessWithExitCode` / `createProcess` and
  peers on the engine-spawn surface in production `src/Infernix/` outside the Phase 4 Sprint 4.30
  capped-engine kernel module and a shrinking `unboundedEngineSpawnExemptedFiles` list
- the rule wired into `checkSourceReadability` and negative-tested via the style gate

### Validation

Gates (closed under [Wave W](cohort-validation-waves.md), 2026-07-24):

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint files/docs/proto/chart`, and `infernix docs check` on both the apple-silicon and
  linux-cpu lanes
- `unboundedEngineSpawnViolations` fires on an injected raw `createProcess` in a guarded engine file
  and passes on the migrated tree
- the apple-silicon plus linux-cpu full-suite behavioral sign-off closes under
  [Wave W](cohort-validation-waves.md)

### Remaining Work

None. The implementation is complete (code-side closed 2026-07-21): the `unboundedEngineSpawnViolations`
sub-rule, its `checkSourceReadability` wiring, and the negative test are landed, built on the Phase 4
Sprint 4.30 capped-engine kernel as the single exempted engine-spawn path. The apple-silicon plus
linux-cpu behavioral cohort sign-off closed under [Wave W](cohort-validation-waves.md) on 2026-07-24
(shared with Phase 4 Sprints 4.30/4.31); no remaining work exists.

---

## Sprint 6.43: Cluster-Ownership Harness Seizure and Crash-Safe Config [Blocked]

**Status**: Blocked by active Phase 1, then Phases 2 and 4 in numerical order. The doctrine + governance
landed first (Phase 0 Sprint 0.16, `Done`), and Wave X remains valid for the typed
owner/mutation-position and crash-safe config scope. The 2026-07-25
execution audit found a remaining TOCTOU: harness seizure authorized teardown while holding the
lifecycle lock, then released that lock before the `finally` cleanup invoked the generic
`clusterDown`. An operator could acquire the shared cluster slot in that interval and then be torn
down by the harness. The correction makes teardown owner-specific and rechecks ownership while
holding the same cross-process lifecycle lock; Phase 6 behavioral validation remains open. It is the
harness half of the Cluster-Ownership & Mutation-Position reopen;
[Phase 2 Sprint 2.15](phase-2-kind-cluster-storage-and-lifecycle.md) is the model half that lands the
`ClusterOwner` / `ClusterMutating` types this sprint consumes.
**Implementation status**: Landed; final cross-phase review and ordered gates remain. The
2026-07-23 scope landed
`seizeHarnessClusterSlot`, `HarnessOwned` cluster bring-up, reservation-aware interrupted-config
reconcile, and `withPersistedClusterMutation`; its machine-independent gates passed on 2026-07-23.
The 2026-07-25 correction adds owner-specific `clusterDown` / `clusterDownHarness` paths, performs
owner observation, authorization, and destructive teardown under the same lifecycle lock, publishes
the harness reservation before config takeover, and makes `runClusterOwnedValidation` cleanup use the
harness-only release path. The chaos-mutation bracket now treats its caller state as an optimistic
token: under that same lock it requires an exact freshly reread `ClusterReady` state, live runtime
inventory, owner, and reservation before publishing `ClusterMutating`, passes only the fresh state
to the body, and revalidates the dirty marker and live evidence before restoring `ClusterReady`.
The owner-atomic implementation is complete. Its current machine-independent and behavioral
validation remain ordered after Phase 2 and Phase 4.
**Historical cohort evidence**: [Wave X](cohort-validation-waves.md) (2026-07-24,
apple-silicon plus linux-cpu) closes only the 2026-07-23 proof that `infernix test all` fails closed
on a running operator cluster, a killed run leaves a mutation-incomplete cluster for the next
`cluster up`, and a leftover `.harness-backup` is restored on the next `test`.
**Current cohort gate**: pending. Phase 6 owner-atomic validation is ordered after Phase 2 closes
under Wave Y and Phase 4 closes.
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs`,
`test/unit/Spec.hs`
**Blocked by**: Phase 2 Wave Y closure, Phase 4 Sprint 4.32
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
`documents/development/testing_strategy.md`, `documents/development/chaos_testing.md`,
`documents/engineering/testing.md`, `documents/architecture/configuration_doctrine.md`,
`documents/operations/cluster_bootstrap_runbook.md`, and this plan

### Objective

Make the test harness's ownership of the single cluster slot and its cluster mutations evidence-gated and
crash-safe, so a killed `infernix test all` cannot strand illegal state and a clean run cannot destroy an
operator's cluster. Today `runClusterOwnedValidation` (`src/Infernix/CLI.hs`) `clusterDown`s
unconditionally, the chaos mutations (drain / scale / cordon) leave the lifecycle at `ClusterReady`, and
`withTestHarnessConfig`'s config restore is `finally`-only (bypassed by SIGKILL). See the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- evidence-gated seizure: `runClusterOwnedValidation` reads the persisted state and **fails closed loud**
  when a present cluster is `OperatorOwned` ("an operator cluster is up at `<identity>`; `infernix cluster
  down` it before running tests"), tearing down only a `HarnessOwned` cluster; the harness brings up its
  cluster as `HarnessOwned`
- chaos-mutation `ClusterMutating` transitions: each mutation in `test/integration/Spec.hs` (node drain,
  deployment over-scale, cordon) persists `ClusterMutating <phase>` before the `kubectl` mutation and
  restores `ClusterReady` only from a fresh exact live ready-state match after revalidating the
  mutation postcondition, so a kill or stale caller leaves `ClusterMutating` for the Sprint 2.15
  status/reconcile to catch
- crash-safe `withTestHarnessConfig`: at entry, a leftover `./infernix.dhall.harness-backup` from a prior
  killed run is reconciled (the operator config restored) before the harness takes ownership, so the
  `finally` restore is no longer the only recovery path

### Validation

- `cabal build all` (`-Wall -Werror`), `cabal test infernix-unit` (a persisted `OperatorOwned`
  `ClusterReady` makes the harness seizure a loud failure; a `HarnessOwned` one proceeds;
  `withTestHarnessConfig` restores the operator config from a planted leftover `.harness-backup`), and
  `cabal test infernix-haskell-style`, on both the apple-silicon and linux-cpu lanes
- `infernix lint docs` stays clean
- [Wave X](cohort-validation-waves.md) remains historical apple-silicon plus linux-cpu evidence for
  the 2026-07-23 behavioral contract; after Phases 2 and 4 close, rerun `infernix test all` on
  apple-silicon plus linux-cpu for the 2026-07-25 owner-atomic correction

### Final cross-phase review (2026-08-02)

The review ran four independent adversarial lenses — cross-process lock atomicity, crash/kill safety,
type-level ownership evidence, and harness-seizure fail-closed behaviour — over `Cluster.hs`,
`CLI.hs`, `LifecycleLock.hs`, `MutationRecovery.hs`, the integration chaos sites, and the four
teardown compile-fail fixtures. Seven findings were raised; each was then attacked from two
independent angles (is the interleaving reachable in the real source, and would existing coverage
catch it). **Three were refuted and four survived.** The review is therefore *not* an acceptance:
it reopened the sprint's scope.

**Refuted** (recorded so they are not re-raised): the teardown authority is reusable across regions
(the compile-fail fixtures do pin region reuse); `authorizeClusterOwnership` ignores the recorded
owner on an empty inventory (a pristine checkout falls to the refusal arm); the kill-9 reservation
path aborts every subsequent command without reconciling.

**Confirmed and fixed with this sprint:**

- *(Medium)* `prepareLinuxGpuEngineDeployment` in `test/integration/Spec.hs` rotated the shared and
  per-engine `linux-gpu` engine Deployments between replica counts **outside**
  `withPersistedClusterMutation`, unlike its two sibling chaos sites whose own comments state the
  marker exists precisely so a SIGKILL mid-mutation leaves a detectable dirty cluster. A kill anywhere
  in that rotation left the persisted state reading `ClusterReady` while engine Deployments sat scaled
  to zero — the exact false steady-state the doctrine forbids. The rotation is now bracketed, loading
  a fresh state and running under the `linux-gpu-engine-deployment-rotation` marker.

**Confirmed and carried into a new sprint** (see [Sprint 6.45](#sprint-645-machine-scoped-cluster-slot-ownership-and-type-indexed-teardown-owner-planned)):

- *(High)* the Kind cluster name is machine-global while the lifecycle lock, reservation, and
  persisted state are repo-local;
- *(Medium)* the harness reservation is likewise repo-local, so the fence that should hold for the
  whole test body is invisible to a process rooted at a different checkout;
- *(Medium)* `ClusterTeardownAuthority` type-indexes only the lock region, not the owner, so the
  documented "tearing down an `OperatorOwned` cluster does not typecheck" was an over-claim. The
  refusal is a value comparison producing an `ioError` under the held lease. The doctrine wording in
  `CLAUDE.md`, `AGENTS.md`, and
  [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
  is corrected to say what the code actually does, with the type-level work scheduled.

### Remaining Work

- Sprint 6.45 owns the three carried findings. Sprint 6.43 cannot reach `Done` before it, because two
  of them contradict this sprint's own stated deliverable.
- after Phase 2 closes under Wave Y and Phase 4 closes, rerun the machine-independent gates and the
  Phase 6 apple-silicon plus linux-cpu behavioral cohort; record the new evidence without rewriting
  Wave X's narrower historical claim

---

## Remaining Work

Sprint 6.39 (capability-gating lint plus managed-transition coverage), Sprint 6.40
(Unbounded-Exec/HTTP Capability-Gating Lints — the `unboundedExecViolations` and
`unboundedHttpViolations` lint rules), and Sprint 6.41 (ProcessMonitor Retirement & Readiness-Wait
Kernel Migration — the `ProcessMonitor` retirement, the shared `retryCommandOutput` primitive bounding
its six consumers, the eager-model-cache barrier, the full twelve-wait individual bounded-wait
migration onto `awaitReadiness`/`budgetDeadline`, and the `threadDelayViolations` lint gate) are
code-side closed (machine-independent, adversarially reviewed) and their single-accelerator
(apple-silicon) plus linux-cpu full-suite cohort sign-off is closed by
[Wave V](cohort-validation-waves.md) (2026-07-20); no remaining work exists for these reopen sprints.
Sprint 6.38 is closed for typed resource admission validation across Apple, Linux CPU, and Linux GPU
by Wave T's `linux-cpu` plus selected `linux-gpu` evidence. The MT3 catalog-validation reopen (Sprint
6.35) is **closed** — proven by [Wave P](cohort-validation-waves.md) (2026-07-04). **Sprint 6.36**
(real-output + matrix validation hardening) and **Sprint 6.37**
(apple-silicon memory-bounded validation lane) are closed by [Wave R](cohort-validation-waves.md)
and [Wave S](cohort-validation-waves.md) for their original scopes.
**Sprint 6.42** (Unbounded-Engine-Spawn Capability-Gating Lint) — the enforcement half of the
memory-safety-by-construction reopen (2026-07-21), the `unboundedEngineSpawnViolations` lint that keeps
new engine-spawn call sites off the raw process primitives and on the Phase 4 Sprint 4.30 grant-gated
capped-engine kernel — is closed under [Wave W](cohort-validation-waves.md) (2026-07-24) with
apple-silicon plus `linux-cpu` behavioral sign-off (code-side closed 2026-07-21 on the
machine-independent gate set, negative-tested).
**Sprint 6.43** (Cluster-Ownership Harness Seizure and Crash-Safe Config) — Wave X (2026-07-24)
historically closes only the 2026-07-23 evidence-gated cluster seizure, chaos-mutation
`ClusterMutating` transitions, and crash-safe `withTestHarnessConfig` backup reconcile on
apple-silicon plus `linux-cpu`. The 2026-07-25 owner-atomic reservation/teardown implementation is
landed with [Phase 2 Sprint 2.15](phase-2-kind-cluster-storage-and-lifecycle.md). Phase 0's
correction review and Stage 1 are green; Phase 6's own final review and
machine-independent/behavioral gates remain, ordered after Phase 2 closes under Wave Y and Phase 4
closes.

## Sprint 6.44: Verified NVIDIA Enforcement And Capability-Gate Closure [Active — Validation Only]

**Status**: Active — code-side closed on 2026-08-02. The `linux-gpu` behavioral cohort is the only
remaining gate, and it is runnable on the current host for the first time (CUDA Linux, RTX 5090).
**Code-side closure**: Complete. The complete machine-independent gate set is GREEN:
`cabal build all --enable-tests` (`-Wall -Werror`), `infernix-unit`,
`infernix-execution-plan-internal`, `infernix-capped-engine-observer`, `infernix-compile-fail`
(6 positive / 81 negative), `infernix-haskell-style` (`haskell-style-check: ok`, including the
realness rules), and `lint files|chart|proto|docs` plus `docs check`.
**Cohort gate**: selected `linux-gpu` plus `linux-cpu`, new typed-execution-plan wave — pending, and
now the sprint's **only** remaining item. Its three prior code-side residuals — the adversarial CUDA
breach fixture, the `close_fds` descriptor stall, and the raw-spawn exemption decision — are all
closed on 2026-08-03 and are recorded in their own sections below.
**Blocked by**: nothing. Phase 4 Sprint 4.32's code-side closure landed the shared resource-indexed
execution boundary this sprint consumes.
**Implementation**: `src/Infernix/DescriptorSpace.hs` (new — the bounded descriptor space the
`close_fds` correction rests on), `src/Infernix/Runtime/CappedEngine/FixedObserver.hs` (renamed from
`DarwinObserver.hs`), `src/Infernix/Runtime/CappedEngine/Internal.hs`,
`src/Infernix/Runtime/CappedEngine.hs`, `src/Infernix/Runtime/Enforcer.hs`,
`src/Infernix/ExecutionPlan.hs`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`,
`src/Infernix/DemoConfig/Internal.hs`, `src/Infernix/Substrate/Internal.hs`,
`src/Infernix/Cluster/Invoke.hs` (new), `src/Infernix/Cluster/Command.hs`,
`src/Infernix/Cluster/Subprocess.hs`, `src/Infernix/Runtime/Pulsar.hs`,
`src/Infernix/Lint/HaskellStyle.hs`, `test/unit/Spec.hs`,
`test/capped-engine-observer/Spec.hs`, `test/compile-fail/`
**Docs to update**: `documents/architecture/typed_execution_plan.md`,
`documents/architecture/bounded_inference_memory.md`,
`documents/development/testing_strategy.md` — all three updated with this sprint.

### Objective

Install and verify per-process-group NVIDIA VRAM enforcement, prove ceiling-breach behavior on CUDA,
and reduce raw-spawn enforcement to explicit kernel import boundaries with no broad exemptions.

### Deliverables

- NVIDIA accounting/refinement fails engine readiness when device/process attribution is unavailable
- RAM and VRAM grants are independently indexed and jointly required where a model uses both
- provisioning/smoke processes use a bounded `ProvisioningGrant`
- raw-spawn lint exemptions are removed outside command, engine, and provisioning kernels

### Landed Implementation

The starting state was that **no `linux-gpu` execution plan could compile at all**:
`runtimeBudgetErrors` returned `GpuDualResourceBudgetRequired` for every `LinuxGpu` config,
`compileResources` had no `LinuxGpu` arm, `CompiledGpuResources` was constructed only in a test
fixture, `Infernix.Runtime.Enforcer` hardcoded NVIDIA availability to `False`, and
`watchdogForGrant` returned a hard `Left "NVIDIA per-process VRAM enforcement is unavailable"`.

1. **Dual budget.** `InferenceMemoryBudget` gains `DualEnforcedBudget PodMemoryLimit PodMemoryLimit`
   (pod RAM first, NVIDIA VRAM second). `resolveInferenceMemoryBudget LinuxGpu` emits it, the
   generated Dhall carries a third union arm (`DualEnforced`), and `memoryEnforcerErrors` walks every
   named limit plus pins which physical resource each half of the dual arm names — two RAM limits or
   two VRAM limits presented as dual enforcement is an `InvalidMemoryEnforcer` config error.
2. **Dual grants.** `ResourceWitness` gains `NvidiaVramWitness`, and `compileResources` gains
   `LinuxGpu` arms: a `requiresGpu` model compiles `CompiledGpuResources` with one grant admitted
   against each limit, while a shared-lane model stays on `CompiledPodResources` alone — a VRAM grant
   a model would never consume is not evidence of anything. `admitGrant` now takes the rejecting
   limit's own source, so a dual-resource rejection names *which* limit was exceeded.
3. **Fixed public-tool NVIDIA observer.** `DarwinObserver.hs` is renamed
   `FixedObserver.hs`: the spawn/drain/deadline/cleanup kernel and its eight self-exec kernel tests
   were already platform-neutral, so the module now owns both platforms' closed request vocabularies
   — the Apple `/usr/bin/top` + `/usr/bin/footprint` pair on Darwin and the NVIDIA
   `/usr/bin/nvidia-smi` pair elsewhere — with `FixedObserverSpec` still unexported. `nvidia-smi` is
   pinned as a literal absolute path rather than resolved from the host-tools manifest, because an
   enforcement observer that follows a configurable path is redirectable.
4. **Per-process-group attribution.** Two properties were **measured, not assumed**, before the
   design was fixed: NVML resolves each compute context against the reading process's PID namespace
   and omits contexts it cannot resolve (a host process holding 1008 MiB was invisible from inside a
   container, while the same allocation made *inside* the container was reported with the
   container-local pid), and group membership is already available subprocess-free from
   `/proc/<pid>/stat`. The NVIDIA lane therefore spawns exactly one fixed command per sample and
   reuses the resident-set lane's `/proc` walk for membership.
5. **Third watchdog.** `WatchdogSpec` gains `NvidiaVramWatchdog`, `watchdogForGrant` mints it, and
   `runNvidiaWatchdog` mirrors the Linux RSS loop's fail-closed discipline: a sampler error, a
   `/proc` enumeration failure, an overflow, or *no live group member for a still-running engine* is
   `EngineEnforcementUnavailable`; a live member holding no CUDA context is `Just 0`, an ordinary
   early-execution observation rather than a loss; a measured breach is `EngineExceededCeiling`.
6. **Refinement.** `Infernix.Runtime.Enforcer` probes the sampler and the device envelope when a GPU
   placement exists and wires both into `GpuPlacementObservation`, so `NvidiaSamplerUnavailable`,
   `NvidiaEnvelopeUnavailable`, and `NvidiaEnvelopeTooSmall` are now reachable from production
   observations rather than only from test fixtures.
7. **Bounded-command migration.** `Infernix.Cluster.Invoke` hoists the setup/compile/kernel
   invocation shape out of `Infernix.Cluster`, and both of `Runtime/Pulsar.hs`'s raw spawns became
   closed bounded commands: the control-plane address probe reuses the existing
   `DockerInspectContainerField … KindNetworkIpv4`, and the model-weight snapshot bootstrap — an
   unbounded `readProcessWithExitCode` over a Poetry-driven upstream download, the sharpest remaining
   instance of the hang class the doctrine exists to prevent — became
   `PoetryModelSnapshotBootstrap`, rendered with `commandSpecRedacted` so MinIO credentials are not
   written to the command label. It reuses the image-publication copy policy (40 minutes, bounded
   retry, transient-then-fatal) rather than adding a configurable field, so operators' existing
   generated host manifests keep decoding.
8. **Lint tightening.** `unboundedExecExemptedFiles` drops `Runtime/Pulsar.hs` (now clean),
   `Engines/LinuxNative.hs`, and `Python.hs` (the latter two had contained no raw spawn at all), and
   `threadDelayExemptedFiles` drops `Python.hs`. A real hole is closed: whole-token matching meant
   `withCreateProcess` never matched `createProcess`, so a non-exempt module could bracket an
   unbounded spawn in plain sight — `withCreateProcess`, `runInteractiveProcess`, `runProcess`, and
   `cleanupProcess` are now forbidden tokens, and `withCreateProcess` is forbidden by the engine-spawn
   rule too.

Deliverable 3 was already satisfied before this sprint and was re-verified rather than re-implemented:
the provisioning facade's fifteen named steps funnel through three private dispatchers that all end at
`runBoundedCommand`, and both smoke helpers go through the closed
`runClosedInstalledRunnerSmoke` / `runClosedLinuxNativeArtifactSmoke` kernels. There is no raw spawn
anywhere in the provisioning path.

### First cohort attempt found a real defect in this sprint (2026-08-03)

The first `./bootstrap/linux-gpu.sh test` run failed, and the failure was **caused by this sprint**,
not by the environment. It is recorded in full because it is the single most valuable thing the
cohort produced and because three plausible explanations were wrong before the right one was found by
measurement.

The run cleared every gate — clean in-image build, `haskell-style-check: ok`, `infernix-unit` PASS,
Kind cluster, Harbor publication of all images including the three GPU engine images, preload,
Keycloak/PostgreSQL — then `infernix-engine` timed out at `0 of 1 updated replicas are available` and
the harness tore the cluster down cleanly.

Three hypotheses were checked and refuted before the cause was found:

1. *The GPU is not schedulable* — refuted. The log shows `nvkind hit its known configmap persistence
   bug (exit 255)` with a fallback to repo-owned node setup, which looked like the culprit, and a
   first check found no `nvidia.com/gpu` capacity. That check was taken **one second** after the
   device-plugin daemonset was created and was simply premature: the plugin comes up and the worker
   advertises `nvidia.com/gpu=1`.
2. *The node label is missing* — refuted. The worker carries `infernix.runtime/gpu=true`.
3. *Four engine Deployments contend for one GPU* — refuted. The generated lifecycle values already
   set `infernix-engine` to 1 replica and every per-engine deployment to 0 at final phase precisely
   so the single device is not oversubscribed.

The actual cause was arithmetic, and was confirmed by reading the live pod rather than by inference:
the engine pod's cgroup `memory.max` is `17179869184` bytes = **16384 MiB**, while
`podRefinementErrors` requires the observed outer envelope to equal
`childBudget + linuxOuterEnvelopeHeadroomMib` **exactly**. This sprint reused the `linux-cpu` child
budget of 4096 MiB, so every GPU placement produced `OuterEnvelopeTooLarge 5120 16384`, refinement
failed, no `ExecutableModel` was ever minted, the engine never wrote its subscription-ready sentinel,
and the readiness probe never passed. The pod was `Running`, `ready=false`, `restarts=0`, with **no
log output at all** — a shape that looks nothing like a crash and is easy to misread as an
infrastructure problem.

This defect was invisible to every machine-independent gate for a structural reason worth stating:
before this sprint `linux-gpu` compiled no execution plan at all, so the pod-RAM envelope equality
had never once executed on that lane. The GPU engine pod is deliberately provisioned at 16 GiB
(framework host RAM for CUDA contexts and model loading) where the CPU engine pod gets 5 GiB.

**The fix, and the more important fix.** `linuxGpuEngineInferenceRamBudgetMib` is now *derived* as
`linuxGpuEnginePodMemoryLimitMib - linuxOuterEnvelopeHeadroomMib`, so the budget and the pod limit
cannot be written down independently. The durable correction is the guard that was missing: the unit
suite asserted the `linux-cpu` envelope relationship but had no `linux-gpu` counterpart. It now
asserts, for **both** lanes, that the child budget plus the headroom equals the engine pod memory
limit exactly, and ties the pod-limit constant to the literal the generated Helm values emit. The
guard was negative-tested by restoring the 4096 MiB budget: the unit suite fails with
`linux-gpu child-execution budget plus the daemon/watchdog headroom equals the engine pod memory
limit exactly, as runtime refinement requires`. A multi-hour cohort is no longer required to catch
this class of drift.

Consequence for evidence: the failed run also proved that the cohort consumes the **baked image
source**, because `compose.yaml` bind-mounts only `./.data` while `/workspace` is image content. Any
source change — including this fix — requires an exact-source image rebuild before its cohort counts.

### Root cause of the second cohort failure: `close_fds` against the containerd fd limit (2026-08-03)

Cohort attempts 4 and 5 failed with `infernix-engine` crash-looping on
`NvidiaSamplerUnavailable` for all five admitted GPU placements. The instrumentation added above
(`probeNvidiaVramSampler` carrying its reason) turned a multi-hour hypothesis cycle into a single
run, and the reason was:

> NVIDIA device observation failed: fixed /usr/bin/nvidia-smi device-memory observer exceeded its
> total monotonic deadline — stdout: (empty) stderr: (empty)

Empty captured streams mean the child produced nothing at all in 5 seconds, while the same command
run by hand in the same pod returns `32607` in 26-28 ms at a host load of 3.66. The child was
therefore stalling **before `exec`**, not running slowly.

The measured environmental difference is the fd limit:

| Context | `RLIMIT_NOFILE` |
|---|---|
| engine pod (containerd) | 1073741816 |
| launcher container (docker) | 1024 |

`System.Process` with `close_fds = True` closes every descriptor from 3 up to that limit before
`exec`. A direct measurement with the same library on this host gives 0 ms at rlimit 1024 and
**133 ms at rlimit 524288** — about 0.25 µs per descriptor. Extrapolated to the pod's 1,073,741,816
descriptors that is roughly **4.5 minutes per spawn**, against a 5-second observer deadline. Every
observation stalls, refinement fails, the engine never becomes ready.

This also explains why no earlier gate caught it. The unit suite's live NVIDIA assertions pass in the
launcher container, whose limit is 1024, and pass on the development host directly; only a
containerd pod carries the billion-descriptor limit.

**The finding is not confined to this sprint.** `close_fds = True` is set in three kernels:
`FixedObserver.hs` (the observer spawn), `Runtime/CappedEngine/Internal.hs` (the capped-engine
engine launch), and `Cluster/Subprocess.hs` (the bounded-command self-exec anchor). If the
measurement generalizes, every subprocess those kernels start inside a containerd pod pays the same
pre-`exec` cost. That has **not** been verified: `linux-cpu` cohorts do pass with real per-model
inference, so either they pay this cost and are simply slow, or something differs between those call
sites that has not been identified. Establishing which is the first task of the follow-on, because
the answer determines whether this is a Sprint 6.44 bug or a platform-wide one.

### The descriptor-space correction (2026-08-03)

The open question above is now **answered by measurement rather than inference, and the answer is
that the defect is platform-wide, not confined to this sprint.**

Three measurements were taken with the same public `System.Process` API and the same flags the
kernels use. The first two replace the previous extrapolation:

| soft `RLIMIT_NOFILE` | `close_fds = True` | `close_fds = False` |
|---|---|---|
| 1024 | 0.9 ms | 0.9 ms |
| 4096 | 1.8 ms | 0.6 ms |
| 16384 | 4.9 ms | 0.6 ms |
| 65536 | 17.5 ms | 0.6 ms |
| 524288 | 130 ms | 0.5 ms |
| **1073741816 (a pod's limit)** | **313 s** | **0.8 ms** |

The last row was taken inside a container started with the pod's own
`--ulimit nofile=1073741816`, so it is a measurement of the real limit rather than a linear
extrapolation from 524288 (the extrapolation predicted ~4.5 min; the measured figure is 5 min 13 s).
The entire cost is the pre-`exec` descriptor walk: at every limit, the same spawn with
`close_fds = False` is under a millisecond.

Reading the `process-1.6.26.1` source settles the mechanism and the remedy together. `close_fds` is
one of the configurations `posix_spawn` cannot express (`do_spawn_posix` returns `-2` for it), so the
spawn always falls back to fork/exec, and in the forked child `do_spawn_fork` runs
`for (int i = 3; i < get_max_fd(); i++) close(i);` where `get_max_fd()` is `sysconf(_SC_OPEN_MAX)` —
the soft `RLIMIT_NOFILE`. The loop is linear in a limit the process **inherits** rather than chooses.

**So the fix is to bound the resource, not to weaken the isolation.** The previously-obvious change —
dropping `close_fds` — was correctly rejected. `Infernix.DescriptorSpace` (new) lowers the soft limit
to a 16384 ceiling as the first action of a process image, before the internal self-exec dispatch and
before anything opens a descriptor. Because a process cannot open a descriptor numbered at or above
its own soft limit, no descriptor above the bound can ever exist afterwards, so the child's walk over
`3 .. bound` still closes the **entire** descriptor space: `close_fds` keeps its exact meaning and
only its cost becomes bounded. The bound is inherited across `fork` and `exec`, so the anchor,
supervisor, pin, target, and engine children are bounded by their parent without doing anything
themselves. The limit is only ever lowered, so a host that already imposes a tighter one keeps it,
and the hard limit is written back unchanged, so establishing the bound needs no privilege.

16384 was chosen from the table: it costs 4.9 ms, which the observer's 50 ms sampling cadence absorbs
alongside a ~27 ms `nvidia-smi` query, while the next round value up (65536, 17.5 ms) does not leave
that cadence enough room. Nothing this platform runs comes within two orders of magnitude of 16384
open descriptors.

Three guards, because a startup call that a later change silently drops would reintroduce a
five-minute stall that reads as a hang:

1. `requireBoundedDescriptorSpace` is called by all three kernels immediately before `createProcess`.
   An unbounded process image is now a **named refusal** identifying the spawning kernel, not a
   timeout with two empty captured streams.
2. A new `unboundedDescriptorSpawnViolations` lint rule makes a `close_fds` spawn surface that never
   observes the bound a build error. It is file-scoped like its sibling rules, so it does not catch a
   second unguarded spawn added to a file that already observes the bound; that limitation is stated
   rather than papered over.
3. Unit assertions pin that the bound holds in the test image, that an unbounded space is refused by
   name, that re-establishing lowers to the ceiling, and that a tighter host-imposed limit is
   preserved rather than widened.

**Evidence.** `cabal build all --enable-tests` under `-Wall -Werror`, `infernix-haskell-style`
(`haskell-style-check: ok`, including the new rule over the whole tree), and `infernix-unit` are
GREEN. End to end: the `infernix-capped-engine-observer` suite — eight self-exec kernel tests that
each spawn through `close_fds = True` — completes in **3.7 s inside a container at the pod's real
`RLIMIT_NOFILE` of 1073741816**, against 3.2 s on the host. That is the same limit at which a single
spawn previously cost 313 s.

One caveat on that container run, recorded so it is not rediscovered: the suite must not be started
as PID 1. A container init has different signal and reaping semantics, and the observer's
group-termination fixtures depend on ordinary signal defaults, so the suite hangs as PID 1 at *any*
fd limit and in any image. `docker run --init` is what makes the measurement above meaningful; the
cohort is unaffected because it enters through the launcher entrypoint.

### Validation

- negative tests reject RAM/VRAM enforcer substitution and unenforced GPU placements — **GREEN**:
  two new compile-fail fixtures (`fail-vram-enforcer-pod-grant`, `fail-pod-enforcer-vram-grant`) join
  the existing `fail-vram-enforcer-host-grant` and `fail-host-enforcer-pod-grant`, so every
  cross-resource substitution among the three indices is a type error; the unit suite rejects a
  single-resource `linux-gpu` budget, a dual budget with swapped resources on each half, and asserts
  that a placement's enforced resource set is `[PodRam, GpuVram]` exactly when the model uses the
  device
- adversarial CUDA allocation breaches the declared ceiling, yields typed terminal failure, and
  leaves the GPU worker and subsequent smaller inference healthy — **NOW COVERED (2026-08-03) and
  GREEN against the real RTX 5090.** `runNvidiaVramBreachAssertions` in `test/unit/Spec.hs` launches a
  process-group-leading child that holds a real device allocation made through `libcuda.so.1`
  driver-API calls under `ctypes` — no compiler, no repo-owned native source — and drives the
  existing `nvidiaWatchdogOutcomeForTest` seam exactly as Phase 4 Sprint 4.32's
  `runLinuxWatchdogBreachAssertions` drives its Linux CPU counterpart. A breach returns typed
  `EngineExceededCeiling`, the group is reaped non-successfully, and a subsequent smaller allocation
  completes cleanly under the same enforcer.

  The ceilings were chosen from measurement, not assumption: a CUDA context is itself a real device
  allocation of **496 MiB** on this host before any `cuMemAlloc`, so a naive small ceiling would have
  been breached by context overhead alone and would have proved nothing about the allocation. The
  breach case allocates 3072 MiB against a 1024 MiB ceiling (observed 3568 MiB attributed to the
  pid), and the clean case allocates 64 MiB against a 3072 MiB ceiling (~560 MiB). Both outcomes are
  clear of the context floor in both directions.

  The assertion was **negative-tested**, as the envelope guard above was: reducing the breach
  allocation to 64 MiB makes the suite fail with
  `a live CUDA allocation past the declared ceiling returns the typed ceiling outcome and reaps the
  grouped engine non-successfully; observed Nothing and ExitSuccess`. It is therefore live rather
  than vacuous. It skips loudly and by name when `/usr/bin/nvidia-smi` or the pinned interpreter is
  absent, or when the fixture cannot reach its allocation gate — never silently.

  The pre-existing analysis of why nothing covered this is retained below, because it is what
  identified the seam that closed it:
  - `test/integration/Spec.hs` has **no runtime ceiling-breach case at all**.
    `validateCatalogModelInference` classifies every row into exactly two outcomes — a model the
    compiler marked unavailable publishes a typed `ModelMemoryLimitExceeded`, and every other model
    must publish `completed`. A *runtime* breach of an admitted ceiling is neither, so nothing in the
    suite would observe one.
  - The unit suite **can** reach the device inside the cohort, contrary to an earlier reading of this
    sprint. `/usr/bin/nvidia-smi` and `libcuda.so.1` are both present in the launcher image, and the
    Sprint 6.44 live NVIDIA assertions **ran and passed** inside the `linux-gpu` cohort — the
    `skipping the live NVIDIA VRAM watchdog assertions` line does not appear in its log. That is a
    property of the **host Docker daemon**, not of `compose.yaml`: this development host sets
    `"default-runtime": "nvidia"` in `/etc/docker/daemon.json`, so every container gets the driver
    injected without a `--gpus` flag or a compose device reservation. On a host whose default runtime
    is `runc`, the outer container would have no device and those assertions would skip loudly
    instead. The suite is honest either way, but its coverage is host-configuration-dependent and
    must not be recorded as unconditional.
  - So the gap is not "the cohort cannot reach a GPU"; it is that **no fixture allocates device
    memory past a ceiling**. The Phase 4 Sprint 4.32 precedent for the Linux CPU breach —
    `runLinuxWatchdogBreachAssertions` driving `linuxWatchdogOutcomeForTest` against a live self-exec
    child — transfers directly: `nvidiaWatchdogOutcomeForTest` already exists and takes the same
    shape. What is missing is a child that makes a real CUDA allocation, which needs no compiler and
    no repo-owned native source: `libcuda.so.1` driver-API calls through `ctypes` from the image's
    Python are sufficient (`cuInit`, `cuDeviceGet`, `cuCtxCreate_v2`, `cuMemAlloc_v2`), and were
    verified to produce a device allocation that `nvidia-smi --query-compute-apps` attributes to the
    allocating pid.

  What *is* GREEN, and ran against the real RTX 5090 both on the development host and inside the
  `linux-gpu` cohort: the fixed observer's parsers and every rejection they encode, the
  group-attribution arithmetic and its overflow rejections, a live no-CUDA-context sample that
  completes without a fabricated breach or an enforcement failure, a positive device envelope, and an
  available startup probe.

  Note when reading cohort output: 13 of the 16 `linux-gpu` catalog rows are device-using and 3 are
  shared-lane, so both new compile arms are exercised. After the envelope correction the two limits
  are no longer equal — pod RAM is 15360 MiB and VRAM is 4096 MiB — which makes the typed rejections
  more informative than they would have been: a device-using row between those two figures (the
  6 GiB music/MLX rows, the 8 GiB Bark and Demucs rows, the 12 GiB image rows) is rejected against
  `gpu-vram`, naming the resource an operator would actually have to enlarge. Only the 28 GiB video
  row exceeds the RAM limit as well, and because the pod grant is admitted first it reports
  `pod-ram`; that is a real limit genuinely exceeded, not a sign that VRAM admission is unwired.
  Ordering the dual admission VRAM-first for `requiresGpu` models would make even that row name the
  device, and remains a small follow-on.

- import-boundary and lint scans report zero non-kernel raw process access — **GREEN, and the
  residual is now a settled scope decision rather than a backlog.** `infernix-haskell-style` passes
  with the tightened token set, and the exemption set is down from twelve rows to **seven**: four
  kernels plus three surfaces whose exemption is a recorded decision. See the exemption resolution
  below.
- selected `linux-gpu` plus `linux-cpu` full-suite gate passes against one frozen state — **pending**

### Remaining Work

1. **The `linux-gpu` behavioral cohort** (`./bootstrap/linux-gpu.sh test`) plus the paired
   `linux-cpu` cohort against one frozen state. This is the sprint's only blocking residual and is
   runnable on the current CUDA host. It has not been attempted since the descriptor-space
   correction; because the cohort consumes the **baked image source**, it needs an exact-source image
   rebuild first. The two prior blockers it failed on are now closed by construction and guarded —
   the GPU envelope arithmetic by a both-lane unit assertion, and the `close_fds` descriptor walk by
   the bound, the three kernel observations, and the new lint rule.
2. ~~**A fixture that allocates device memory past a ceiling.**~~ **CLOSED (2026-08-03)** — see the
   Validation section above. `runNvidiaVramBreachAssertions` drives a real `libcuda.so.1` allocation
   through `nvidiaWatchdogOutcomeForTest`, is GREEN against the RTX 5090, and was negative-tested. It
   is a source change, so it needs its own frozen state and is part of the item-1 rebuild.
   The original analysis is retained for the record:
   (`runLinuxWatchdogBreachAssertions`) both already exist; what is missing is a child that holds a
   real CUDA allocation. Driver-API calls through `ctypes` on `libcuda.so.1` from the image's Python
   need no compiler and add no repo-owned native source, and were verified to produce an allocation
   that `nvidia-smi --query-compute-apps` attributes to the allocating pid in the same PID namespace.
   The assertion must mirror the Linux CPU case: a breach returns typed `EngineExceededCeiling`, the
   group is reaped non-successfully, and a subsequent smaller allocation completes cleanly. It must
   skip loudly — never vacuously — when the device is absent, because outer-container GPU access
   depends on the host daemon's default runtime rather than on `compose.yaml`. **Until this exists,
   Sprint 6.44 cannot reach `Done` on any cohort result**, and because it is a source change it needs
   its own frozen state and a follow-up cohort.
3. ~~**Five raw-spawn exemptions remain**~~ **CLOSED (2026-08-03): nine rows → seven, and the
   doctrine decision is made rather than deferred.** Two rows were deleted by migration and three are
   now recorded decisions. The decision is that the bounded-command kernel's closed operand catalog
   is the right tool wherever the operand vocabulary *is* closed, and that two situations genuinely
   fall outside it — an operator's own passthrough invocation, and a spawn that must run *before* the
   host manifest exists. Neither is a licence to be unbounded, so every retained non-daemon surface
   gained a required deadline.

   Two findings changed the shape of this work relative to the sprint's description:

   - **`HostTools.hs` was not "the generic host-tool runner" — three of its five raw spawns were
     dead.** `runHostTool`, `runHostToolWithCwd`, and `readHostToolWithExitCode` had zero callers
     anywhere in the repo and are deleted. Its two live invocations, `sysctl -n hw.memsize` and
     `colima list --json`, both carry *fixed* argv. So the module is not a generic passthrough at
     all; it is the pre-manifest fixed host probe surface, and its exemption is now recorded as such.
   - **`Workflow.hs`'s `runWorkflowCommand` was generic only on paper.** Its sole caller passed a
     renderer-owned literal argv, so the genericity was an artifact rather than a requirement and was
     removed with the migration rather than preserved.

   Migrated to closed bounded commands (exemption rows deleted): `Lint/Files.hs`
   (`git -c safe.directory=… ls-files -z`, `SourceInventoryOperation`), and `Workflow.hs` (both
   `node --version` as `WebToolchainProbeOperation` and the npm install as
   `WebDependencyInstallOperation`, the latter indexed by a closed two-constructor toolchain over the
   only two argv shapes the old runner ever received). All three reuse an existing policy-plan field
   rather than adding one, so the generated host-manifest schema is unchanged and an operator's
   already-generated `./infernix-host.dhall` keeps decoding — the same constraint Sprint 6.44's
   `PoetryModelSnapshotBootstrap` respected.

   Retained as scope decisions, each with a required deadline where a deadline is the right shape:
   - `src/Infernix/CLI.hs` — two surfaces named individually. `withRuntimeServiceDaemon` starts a
     deliberately long-lived host daemon, for which a *total* deadline is the wrong shape; it is
     bounded structurally by its terminate-and-wait bracket instead.
     `runCommandWithCwdAndEnvRemovingWithPaths` is an operator passthrough that must stream to the
     operator's terminal and exit with the child's code — bounding an operator's own `cabal test`
     invocation would be wrong. The one CLI capture that is *not* a passthrough
     (`captureCliHostTool`, the demo-UI `curl`) gained a 120 s deadline.
   - `src/Infernix/HostPrereqs.hs` — the objection here is **ordering, not operands**: all three
     spawns already have fixed executables and fixed argv, but they run before any host manifest or
     Docker context exists, because reconciling those is precisely their job, and
     `clusterSubprocessEnv` fails closed without a manifest. Deadlines added (120 s for the two
     Docker probes, 45 min for `brew install`, which is a genuine long reconciliation).
   - `src/Infernix/HostTools.hs` — the pre-manifest fixed host probes, 120 s each, matching the
     `hostProbe` deadline the generated manifest gives every closed `HostProbeOperation` so the
     pre-manifest and post-manifest probes agree on one number.

   Two consequences are recorded rather than left to be discovered. `infernix lint files` now
   requires the host manifest and fails closed naming the setup failure instead of falling back to
   ambient `$PATH`; that is the intended doctrine direction but it is a real behaviour change for a
   pre-config invocation (the `.git`-absent snapshot-manifest path used in container images is
   untouched). And migrating `Lint/Files.hs` was verified end to end rather than only by gate: in a
   scratch repository, staging a `.c` file and deleting it from the working tree still produced the
   forbidden-native-source violation, which can only come from `git ls-files -z` output flowing
   through the bounded command, because the working-tree walk cannot see a deleted file.

4. **`unboundedEngineSpawnExemptedFiles` — resolved as "cannot be narrowed by a smaller list", not
   narrowed.** The redundant `cappedEngineKernelFile :` cons is removed (that file was already a
   member, so it produced a duplicate rather than a wider set), and the two sets now coincide *by
   construction*. The reason is stated plainly in the Haddock instead of being carried as a backlog
   item: both rules match the same `System.Process` tokens on the same lines, so for any file
   legitimately retaining a non-engine raw spawn, removing it from the engine set would fire the
   engine rule on a line that is not an engine spawn. Separating the two gates needs a **stronger
   detector, not a smaller list** — either a per-site intent annotation or an AST pass that resolves
   what each spawn actually executes, for which the `check-code` realness pass is the precedent. No
   narrowing is claimed, because none happened.

---

## Sprint 6.45: Machine-Scoped Cluster-Slot Ownership And Type-Indexed Teardown Owner [Active — Validation Only]

**Status**: Active — opened 2026-08-02 by Sprint 6.43's final cross-phase review, which confirmed
three findings the sprint's own deliverables claim are already closed. **All four deliverables are
code-side closed on 2026-08-03**: deliverables 3 and 4 (the type-indexed teardown owner and its
compile-fail fixture) landed first, and deliverables 1 and 2 (the cross-checkout guard) landed as
on-resource checkout identity — see [Landed implementation (deliverables 1 and 2,
2026-08-03)](#landed-implementation-deliverables-1-and-2-2026-08-03) below. The cohort is the only
remaining item.
**Code-side closure**: Complete. The machine-independent gate set is GREEN on this source:
`cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`,
`infernix-execution-plan-internal`, `infernix-capped-engine-observer`, `infernix-compile-fail`
(6 positive / 82 negative), `infernix-haskell-style` (`haskell-style-check: ok`), and
`lint files|chart|proto|docs` plus `docs check`
**Cohort gate**: selected accelerator plus `linux-cpu`
**Blocked by**: nothing — dependencies are satisfied; this is ordered after Sprint 6.43's landed
implementation and before Sprint 6.43 can reach `Done`
**Implementation**: `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/LifecycleLock.hs`,
`src/Infernix/CLI.hs`, `test/compile-fail/`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/managed_state_transitions.md`,
`documents/operations/cluster_bootstrap_runbook.md`, `CLAUDE.md`, `AGENTS.md`

### Objective

Make the cluster-slot guard cover the resource it actually protects, and make the owner
discrimination the type-level property the doctrine claims it is.

### The defect

`kindClusterName` drops its `dataRoot` discriminator whenever `dataRoot == repoRoot </> ".data"`,
which is what both shipped default host manifests generate — i.e. every ordinary checkout. The
protected resource, `infernix-<runtime>` on the shared Docker daemon, is therefore **machine-global**,
while `clusterLifecycleLockPath`, `harnessReservationPath`, and `clusterStatePath` are all derived
from the per-checkout `runtimeRoot`. Two checkouts on one host lock different inodes while contending
for one cluster, and each authorizes ownership against the *other's* live Kind inventory using its
*own* state file.

The destructive path is reachable through ordinary use, not a contrived one: a killed harness run
leaves a `HarnessOwned` state file behind (teardown persists `ClusterAbsent` but retains the owner
field, and the interrupted-state reconcile only touches the reservation). A second checkout starting
`infernix test all` with that leftover state observes the operator's live cluster in the shared
inventory, matches it against its own recorded `HarnessOwned` owner, publishes its reservation, and
deletes the operator's cluster — while the operator's process holds its own lifecycle lock and its
own persisted state still reads `OperatorOwned` / `ClusterReady`. A *pristine* second checkout fails
closed, which is why this was not caught earlier.

The reverse direction is the same scope mismatch: because the reservation is repo-local, the fence
that should hold for the entire span between `seizeHarnessClusterSlot` and
`releaseHarnessClusterSlot` — deliberately wider than the lock — is invisible to an `infernix`
process rooted elsewhere, so an operator can seize the slot *during* the harness's test body.

Separately, `ClusterTeardownAuthority s` indexes only the lifecycle-lock region. The owner is an
ordinary `teardownAuthorityOwner :: ClusterOwner` field and `ClusterOwner` is never promoted, so an
authority minted for `HarnessOwned` and one minted for `OperatorOwned` are the same type and every
consumer accepts either. The refusal is an `ioError` reached from a value comparison. The three
teardown compile-fail fixtures exercise only the region parameter, so the compile-fail suite cannot
detect regression of the property it is cited for.

### Design analysis (2026-08-03) — the two named options are both unsound as written

Before implementing, both options this sprint offered were checked against the two execution
contexts the platform actually supports. **Neither works on its own**, and the reason is worth
recording because it changes the deliverable.

*Option (b), always discriminate the cluster name by the checkout*, has a blast radius wider than the
sprint text suggests. `kindControlPlaneNodeName` is `kindClusterName <> "-control-plane"` and is
consumed at seven sites — the `linux-gpu` worker filter, the in-cluster registry-hosts target
`<name>-control-plane:30002`, retained-state node priming, the `docker port` container lookup, the
outer-container Harbor address, `clusterEdgeHost`, and the Playwright host in `CLI.hs`. Renaming also
orphans every existing operator cluster and every kubeconfig context. That is a migration, not a fix.

*Option (a), move the lock and reservation to a machine-scoped location*, fails on the Linux lane for
a reason the sprint did not consider. Two `linux-cpu`/`linux-gpu` checkouts run as two launcher
**containers** that share the host Docker daemon — `compose.yaml` mounts `/var/run/docker.sock` — and
therefore share the Kind inventory, but they do **not** share a filesystem. Worse, the baked host
manifest gives every launcher container `hostRepoRoot = /workspace` and
`hostDataRoot = /workspace/.data`, so any identity derived from an in-container path is *identical*
across checkouts. A "machine-scoped" lock path is unreachable from inside the container, and a
path-derived checkout identity actively collides. Note this also means `clusterNameHash (dataRoot)`
— the discriminator option (b) would rely on — is constant across Linux checkouts, so option (b)
does not even discriminate on the lane where the contention is most likely.

What the two contexts genuinely share is the **Docker daemon**, which is exactly what deliverable 2
already proposes: put the identity on the protected resource. That makes deliverable 2 the primary
mechanism rather than a complement to deliverable 1, and it needs an identity that is per-checkout
and machine-unique in *both* contexts. The host-side kind root is the candidate: the code already
resolves it (`resolveHostKindRoot`, `kindUsesHostBindMounts`) precisely because the container needs
to name host paths for bind mounts, so it is available in-container and differs per checkout there.
`Command.ContainerInspectField` already carries a `MountSourceAt` field, so reading a bind-mount
source back from a live container is an existing capability rather than a new one.

The migration consequence is then confined to clusters created before the identity existed: they
carry no label, and teardown must decide between refusing them (safe, but strands an operator's
running cluster until an explicit reconcile) and grandfathering them (compatible, but leaves the
defect open for exactly those clusters). That decision, and the label round-trip, are the remaining
work.

One further correction to the sprint's premise: `authorizeClusterOwnership` does **not** consult
`clusterLifecycle` at all — it checks only the present runtime and the recorded owner. So the
leftover-state exploit does not depend on the lifecycle field being `ClusterAbsent`, and a narrow
"stale state cannot authorize a present cluster" check would close the specific path the sprint
describes but not the SIGKILL-mid-run variant where the leftover state reads `ClusterReady`. It is
recorded here as insufficient rather than implemented as a partial fix.

### Deliverables

- the guard is scoped to the resource: per the analysis above, **deliverable 2 is the mechanism** and
  the choice between relocating the lock and renaming the cluster is recorded as rejected — the lock
  cannot be machine-scoped from inside a launcher container, and the cluster-name discriminator does
  not discriminate there either. The migration consequence for existing clusters, node names
  (`infernix-<runtime>-control-plane`, which the Pulsar transport probe resolves), kubeconfig
  contexts, and the chart is therefore avoided rather than paid
- ownership evidence travels **with the protected resource** rather than only in a local state file:
  the creating checkout's identity is recorded on the Kind cluster itself (a node label or container
  label) and teardown reads it back and requires agreement, so a foreign checkout cannot authorize
  against an inventory entry it did not create
- `ClusterOwner` is promoted and `ClusterTeardownAuthority` is indexed by it, so a teardown of an
  `OperatorOwned` cluster from a harness-minted authority is a type error
- a compile-fail fixture pins the owner index, alongside the existing three region fixtures

### Validation

- a unit fixture with two distinct `dataRoot`s proves a second checkout cannot authorize teardown of
  a cluster it did not create, with and without a leftover `HarnessOwned` state file
- a compile-fail fixture proves an owner-mismatched teardown does not compile
- `infernix test all` still fails closed loud on an operator's running cluster, and the harness still
  tears down only its own
- machine-independent gates plus the selected accelerator and `linux-cpu` cohorts

### Landed implementation (deliverables 3 and 4, 2026-08-03)

`ClusterOwner` is promoted and `ClusterTeardownAuthority (owner :: ClusterOwner) s` is indexed by it
with `type role ... nominal nominal`; `PreWorkloadKindRecovery` and `KindDeleteAuthorization` carry
the same index rather than leaving the recovery arm phantom, because that arm already stores an
authority. The owner field is the singleton `SClusterOwner owner` rather than a bare value, so the
index and the value cannot drift, and `requireClusterOwnership` stays the sole mint. The public
entry points (`clusterUp`/`clusterUpHarness`/`clusterDown`/`clusterDownHarness`) keep their existing
`IO ()` types and simply pass `SOperatorOwned`/`SHarnessOwned`, so `CLI.hs` is untouched.

**No runtime check was removed or weakened to add the index** — that was the explicit constraint,
because the value check is what actually protects an operator's cluster. `authorizeClusterOwnership`
is unchanged, still takes a plain `ClusterOwner`, and still runs against freshly reread state and
inventory under the held lease, as does `revalidateClusterTeardownAuthority`. Where the owner is only
known at run time — `withPersistedClusterMutation` reads it inside the lock — a rank-2
`withClusterOwnerSingleton` selects the singleton *from the owner just read*, so no index is
fabricated from a static guess.

The fourth compile-fail fixture, `fail-cannot-substitute-cluster-teardown-owner`, deliberately shares
the region type variable so the only property under test is the owner. GHC 9.12.4 rejects it with
`Couldn't match type 'HarnessOwned' with 'OperatorOwned'`, a spelling already present in
`typeMismatchDiagnostics`, so the assertion needed no weakening and no new diagnostic class. The
three pre-existing teardown fixtures were updated to the new arity with the owner left as a free type
variable, so they keep testing only the region parameter. The compile-fail suite is **6 positive /
82 negative** (was 6 / 81).

One incidental change is recorded because it was forced rather than chosen: `GADTs` implies
`MonoLocalBinds`, which de-generalized one existing local `where` binding in
`withPersistedClusterMutation`. It was given an explicit local signature rather than reaching for
`NoMonoLocalBinds`, which would have silently relaxed the whole module.

**What the index does not buy**, stated here so this sprint does not replace one over-claim with
another: substituting one owner's authority for the other's across the teardown/bring-up call graph
is now a type error and the compile-fail suite detects its regression. Deciding who owns a *live*
cluster is still a runtime evidence check under the held lease, and a teardown of a genuinely
`OperatorOwned` cluster is refused by a checked `ioError`, not by GHC.

### Landed implementation (deliverables 1 and 2, 2026-08-03)

The guard now covers the resource it protects. The identity is recorded **on the cluster**, and
`authorizeClusterOwnership` — still the sole decision function, still pure — consumes it alongside
the inventory and the persisted record.

**The identity is the checkout's host-side repository root, and resolving it fails closed.** That is
the one value that is both per-checkout and machine-unique in both supported execution contexts. On
an Apple host it is the operator's real repo path. Inside a Linux launcher container it is the
bind-mount source the host Docker daemon resolved for `/workspace`. `localClusterCheckoutIdentity`
deliberately does **not** reuse `resolveHostRepoRoot`, which answers `/workspace` when that lookup
fails: that is the right conservative answer for rendering a path and the worst possible answer for
an identity, because every launcher container would then claim the same one — which is precisely the
collision the design analysis above identified as fatal to both originally proposed options.

**The carrier needed no new command and no new manifest field.** `stampClusterSlotIdentity` writes
the identity into the control-plane node at `/etc/infernix/cluster-checkout-identity` using the
existing `dockerMakeDirectory` + `dockerWriteFile` pair, and `readClusterSlotIdentity` reads it back
with the existing `dockerCopyFromNode`. A directory rather than a bare file because the catalog's
read-back primitive is directory-contents-only (`docker cp <node>:<dir>/. <local>`); adding a
single-file primitive would have added a constructor for no gain. Because all three reuse existing
`DockerExecOperation`/`DockerCopyOperation` classifications, the generated host-manifest schema is
unchanged and an operator's already-generated `./infernix-host.dhall` keeps decoding — the same
constraint Sprint 6.44's migrations respected.

Note this supersedes the design analysis's *candidate* mechanism rather than following it.
`ContainerInspectField`'s `MountSourceAt` can only read a mount that exists, and the Kind
`extraMounts` block is emitted only when `kindUsesHostBindMounts` is true — Linux outer-container
only. Reading an incidental bind mount would therefore have identified nothing on Apple. A
deliberate marker identifies every cluster on every substrate.

**The stamp is part of creation.** `createKindCluster` now wraps the previous body
(`createKindClusterNodes`, both the `kind` and `nvkind` arms) and stamps immediately on success,
because the interval between creation returning and any later bring-up step is the only window in
which a foreign checkout could observe the cluster as unidentified.

**`authorizeClusterOwnership` returns a `ClusterSlotAdmission` instead of `()`**
(`ClusterSlotAbsent` / `ClusterSlotOwned` / `ClusterSlotAdoptable`), and `ClusterOwnershipRefusal`
gains a `ClusterOwnershipRefusalReason` (`OwnerRecordMismatch` / `ForeignCheckoutSlot` /
`UnidentifiedClusterSlot`) that the diagnostic renders with the remedy. `requireClusterOwnership`
reads both the local identity and the live slot identity under the held lease, so every mint decides
on evidence gathered inside one critical section, and the admission travels on the
`ClusterTeardownAuthority` so the bring-up path knows whether it still owes the resource a stamp.

**The grandfathering decision is made, and it is asymmetric on purpose.** A cluster created before
the identity existed carries no marker, and an unreadable control-plane node is treated identically
— the read is what proves ownership, so an unreadable resource proves nothing.

- `OperatorOwned` **adopts** it: refusing would strand a running cluster behind a manual
  `kind delete`, and the operator is acting at their own terminal on their own host.
  `adoptClusterSlotIfUnidentified` stamps under the same lease that authorized the bring-up, so the
  next authorization is a positive match rather than another adoption.
- `HarnessOwned` is **refused**. The harness is the destructive actor in the defect this sprint
  exists to close — an unattended `infernix test all` that tears down whatever it finds — so it must
  prove the slot is its own. The refusal names both remedies (`infernix cluster down` to remove,
  `infernix cluster up` to adopt). This is a one-time step per pre-existing cluster after upgrading.

Adoption itself is reported and not fatal. It upgrades evidence on a cluster that *already* passed
the ownership check, so aborting would put a damaged control-plane node — the only thing that can
fail there — ahead of the bring-up path's own recovery, which is what repairs it. Leaving the slot
unidentified keeps the harness fenced, which is the property that matters.

**Validation evidence.** Five pure assertions cover the decision surface: a second checkout refused
against both a leftover `HarnessOwned` record and an `OperatorOwned` one; the creating checkout
still authorized for either owner; the adopt/refuse asymmetry on an unidentified slot; an absent
inventory unaffected by any identity; and identity normalization (a trailing or doubled separator is
not a different checkout). Two further assertions are **behavioural**, running the real
seize/release path with a stubbed Docker daemon that serves an identity back: a harness holding a
matching `HarnessOwned` record cannot tear down a cluster another checkout created, and cannot tear
down an unidentified one — in both cases the reservation is retained and no `kind delete cluster` is
issued. The unit fixtures that simulate a live cluster now serve their own checkout identity, which
is itself evidence the guard is live: before those fixtures were updated, every one of them failed
closed.

### Remaining Work

- **Cohort**: selected accelerator plus `linux-cpu`, consumed jointly with Sprint 6.44's wave
  against one frozen source.

## Sprint 6.46: Toolchain Spawn Boundary And Capability-Gating Lint [Planned]

**Status**: Planned — consumes the kernel from Phase 1 Sprint 1.21.
**Blocked by**: Sprint 1.21
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Lint/HaskellStyle.hs`,
`test/compile-fail/`, `src/Infernix/BuildMemory.hs`
**Docs to update**: `documents/architecture/bounded_host_memory.md`,
`documents/development/haskell_style.md`, `documents/development/testing_strategy.md`

### Objective

Make a toolchain spawn without a declared ceiling fail to typecheck, and resolve the enforcement
mechanism per lane rather than assuming one.

`runCommandWithCwdAndEnvRemovingWithPaths` is the operator passthrough behind `infernix test ...`
and `infernix kubectl ...`, and it is exempt from the raw-spawn lint. That exemption is recorded as
a decision about **deadlines**, and the reasoning is sound: bounding an operator's own run with a
deadline they did not choose would be a defect. Memory is a different kind of quantity — it is a
property of the operator's own machine, derived from its measured physical RAM, and its absence is
what destroyed that machine. This sprint adds the memory dimension without touching the deadline
decision.

The victim rank is the third leg and is deliberately the weakest. `oom_badness` is per-process while
the hazard is per-tree, so a rank that leaves a build below the cluster pods is inert against the
ordinary shape of a parallel build. It is applied to the spawned child, never to the lock-holding
CLI image or a daemon it starts, and it changes who dies rather than how much is allocated.

### Deliverables

- a closed `ToolchainInvocation` vocabulary as the only way to name the toolchain, consumed by
  `runToolchainCommand` under a rank-2 spawn authority so a ceiling cannot escape its region or be
  reused; the raw spawn unexported from the passthrough path
- `unboundedToolchainSpawnViolations`, structurally a copy of `unboundedDescriptorSpawnViolations`:
  a toolchain spawn surface with no observation of the declared ceiling is a violation
- negative-compilation fixtures proving a spawn without a plan, a plan substituted across region
  tags, and a reused escaped authority all fail to compile
- the per-lane mechanism resolver: a cgroup scope bounding the aggregate on Linux host-native, the
  container's own limit in the outer container, a runtime heap cap plus bounded concurrency on
  Darwin, and a named refusal when none resolves
- the child victim rank, platform-indexed so Darwin is an explicit rather than a silent no-op

### Validation

- `cabal test infernix-haskell-style` runs the new lint, **verified to fail** with the doctrine
  diagnostic on a reintroduced uncapped toolchain spawn injected into `src/Infernix/CLI.hs` and
  reverted after the negative-test confirmation
- `cabal test infernix-compile-fail` accepts the positive fixtures and rejects all three negatives
- `cabal build all` under `-Wall -Werror`, `infernix lint files/docs/chart/proto`

### Remaining Work

The nested builds that produce the setup helper, the formatter tools, and the compile-fail fixtures
each carry their own job count and are not covered by this boundary; the committed ceiling in
`cabal.project` partially covers them, but the setup helper's own compilation is not. Named in the
doctrine's `Current Status` as deferred.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - root-document metadata contract and canonical-home markers
- `documents/engineering/build_artifacts.md` - generated-artifact locations, build-root rules, and derived-output validation expectations
- `documents/engineering/apple_silicon_metal_headless_builds.md` - validation gates for the Tart-free Apple materialization lane
- `documents/engineering/dependency_management.md` - Cabal dependency posture for the pinned
  Haskell toolchain and the Dhall dependency closure
- `documents/engineering/edge_routing.md` - route-registry ownership, generated route summaries, and route-aware validation expectations
- `documents/engineering/testing.md` - canonical testing doctrine, core principles, preflight expectations, unsupported paths, and per-layer validation obligations
- `documents/development/testing_strategy.md` - operator workflow, matrix selection, and test-entrypoint details
- `documents/development/haskell_style.md` - hard gates, review guidance, direct enforcement-model pointer, repo-hard-gate versus editor-only guidance split, and fail-fast rule
- `documents/development/chaos_testing.md` - HA failure and recovery coverage
- `documents/development/assistant_workflow.md` - canonical repository-level assistant workflow doctrine for governed root entry docs
- `documents/engineering/implementation_boundaries.md` - ownership matrix, adapter-local versus shared-contract types, instance placement, and module-boundary rules
- `documents/engineering/portability.md` - portable invariants versus substrate-specific detail, plus explicit current-status and validation sections where target direction still appears
- `documents/engineering/storage_and_state.md` - owner or durability table, failure-mode rules, and cleanup contracts
- `documents/architecture/runtime_modes.md` - daemon-role split, derived engine-pool handoff, and host-role `.dhall` fields
- `documents/architecture/engine_pool_routing.md` - invalid-state validation, shared-pool
  backpressure, pinned-route exclusivity, and production-shape expectations
- `documents/engineering/model_lifecycle.md` - batch ownership, request handoff, and result-publication runtime contract
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) - managed state-transition doctrine (typed evidence per state, unexported destructive primitives, evidence-returning readiness waits) referenced by Sprint 6.39
- no `documents/engineering/monitoring.md` exists while monitoring remains unsupported; create it
  only if monitoring becomes a supported first-class surface in a later change
- `documents/operations/cluster_bootstrap_runbook.md` - lifecycle warning classification, test
  prerequisites, and cluster reuse rules
- `documents/operations/apple_silicon_runbook.md` - Apple matrix expectations and cold-start lifecycle timing doctrine
- `documents/tools/postgresql.md` - PostgreSQL operator readiness and failover rules
- `documents/tools/pulsar.md` - request, batch, and result topic ownership for cluster and host daemons
- `documents/engineering/docker_policy.md` - native Apple Docker boundary, minimal Linux host
  prerequisites, and buildx expectations for nested Compose builds
- `documents/development/purescript_policy.md` - PureScript npm deprecation-warning ownership,
  compiler acquisition constraints, and Spago transitive-dependency constraints
- `documents/development/python_policy.md` - Poetry bootstrap boundary for Apple hosts and the
  Linux substrate image-local Poetry virtual-environment layout

**Product or reference docs to create/update:**
- `README.md` - orientation layer with governed root-document metadata and canonical-home links
- `AGENTS.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `CLAUDE.md` - thin governed automation entry document with explicit supersession or canonical-home markers
- `documents/reference/cli_reference.md` - test command reference
- `documents/reference/cli_surface.md` - short command-family overview that links to the canonical CLI reference
- `documents/reference/web_portal_surface.md` - browser coverage expectations and active-substrate catalog behavior
- `documents/reference/api_surface.md` - publication metadata that distinguishes cluster daemon and inference executor location

**Cross-references to add:**
- keep [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) aligned
  when governed root-document metadata rules or canonical-home posture change
- keep [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
  aligned when command-registry ownership, shared workflow-helper closure, or CLI-reference
  derivation rules change
- keep [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  aligned when runtime-honesty wording or README-matrix interpretation changes
- keep [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
  aligned when HA claims, route assumptions, or active-substrate validation rules change
- keep [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
  aligned when lifecycle progress surfaces or long-running convergence doctrine changes
- keep [system-components.md](system-components.md) aligned when testing-doctrine ownership,
  shared-helper closure, daemon-role topology, or the supported monitoring stance changes
- keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when any pending
  route-doc, route-lint, assistant-doc, workflow-helper, testing-doc, runtime-language, or
  monitoring-surface or compatibility-shim cleanup item closes
