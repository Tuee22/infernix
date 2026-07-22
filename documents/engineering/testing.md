# Testing Doctrine

**Status**: Authoritative source
**Referenced by**: [../development/testing_strategy.md](../development/testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Define the canonical testing entrypoints, fail-fast behavior, and supported validation boundaries.

## Executive Summary

- the supported validation surface includes the focused `infernix lint files`, `infernix lint docs`,
  `infernix lint proto`, and `infernix lint chart` checks together with the aggregate
  `infernix docs check`, `infernix test lint`, `infernix test unit`,
  `infernix test integration`, `infernix test e2e`, and `infernix test all` entrypoints
- Validation is fail-fast for drift and missing prerequisites: it reports them and stops instead of
  silently rewriting tracked source or substituting another lane. This fail-fast guarantee is scoped
  to drift and prerequisites; model resource capacity is handled separately by runtime admission,
  which classifies an over-budget request as typed `InferenceError.ModelMemoryLimitExceeded` and does
  not fail the whole daemon — see the resource-exhaustion classification under Lifecycle Failure
  Classification.
- Integration and routed E2E coverage derive their target set from the active generated catalog,
  so changing the staged substrate changes the exercised entries automatically.
- Cross-hardware validation is cohort-based: day-to-day phase work validates on the current
  Apple Silicon or CUDA Linux machine, and the counterpart machine's full-suite run is batched at
  phase closure.
- Monitoring is not a supported first-class surface, so no validation entrypoint claims to gate
  dashboards, scrape config, or alerting behavior.

## Preflight Expectations

- supported validation starts from the supported execution context for the selected substrate
- focused static checks, including `infernix lint files`, `infernix lint docs`,
  `infernix lint proto`, `infernix lint chart`, and `infernix docs check`, are substrate-file
  independent because they validate tracked source, governed docs, schemas, and chart structure
- substrate-aware entrypoints, including runtime, cluster, cache, Kubernetes-wrapper,
  frontend-contract generation, and aggregate `infernix test ...` commands, own substrate-file
  preflight for the selected substrate before their suite starts
- Apple host-native flows expect the built binary plus the minimal Homebrew-plus-ghcup baseline;
  supported commands may reconcile the remaining host tools on demand, but they must not create or
  switch Docker contexts, create a Colima VM, or use cross-architecture emulation
- `linux-cpu` flows expect native Linux amd64 or arm64 plus Docker Engine, the Docker buildx
  plugin, and the Docker Compose plugin
- `linux-gpu` flows expect the `linux-cpu` Docker baseline plus the supported NVIDIA driver and
  container-toolkit setup
- real-cluster `linux-gpu` validation also expects enough disk headroom for Kind image preload,
  Harbor-backed rollout, and Pulsar BookKeeper durability
- phase-local validation should run on the machine that owns the changed path; full
  cross-hardware closure requires both the Apple Silicon and CUDA Linux cohorts to rerun the
  relevant full-suite gates against the same phase state
- `linux-cpu` validation may be used as a portable CPU-only check, but it does not substitute for
  `linux-gpu` when GPU behavior is in scope
- emulated validation is unsupported; `linux-cpu` evidence must come from native Linux rather than
  amd64 Linux under Apple Silicon emulation

## Lifecycle Failure Classification

- this classification is the evidence-vs-hope discipline of the managed-state-transition doctrine
  applied to lifecycle: each supported state carries typed evidence rather than an assumed pass, and
  the canonical home for that doctrine is
  [Managed State Transitions](../architecture/managed_state_transitions.md)
- the legacy-tracking ledger at
  [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
  records obsolete-surface receipts; current validation evidence lives in the active phase files
  and cohort waves
- long waits in Docker build finalization, Harbor publication, Kind-worker image preload, and
  retained-state replay are treated as real convergence when heartbeat data is moving, not as hard
  product failure
- the supported doctrine is inactivity-aware: elapsed wall time alone is not enough to classify
  `cluster up`, `cluster down`, `test integration`, `test e2e`, or `test all` as failed when the
  active path still owns cluster lifecycle
- use `infernix cluster status` as the supported progress surface before abandoning a long-running
  lifecycle action
- while `cluster status` reports `lifecycleStatus: in-progress`, treat the current action as still
  progressing when the reported `lifecycleHeartbeatAt` continues to refresh
- the current implementation refreshes that heartbeat roughly every 30 seconds during the
  long-running Docker build, Harbor image publication, Kind-worker Harbor preload, and Apple
  retained-state replay subprocess phases
- the same inactivity-aware classification applies when supported integration or E2E lanes own
  internal cluster bring-up or teardown rounds inside `infernix test all`
- treat the supported path as stalled only when the command exits non-zero or the heartbeat stops
  refreshing across multiple monitor intervals during one of those monitored phases
- resource exhaustion is a distinct third class from stall and clean failure: every active model
  carries `ModelDescriptor.modelRamFootprintMib`, and each substrate resolves an explicit
  `InferenceMemoryBudget` before launch
- the active budget is typed, not a magic integer: Apple uses unified host RAM after the Colima
  pledge and reserve, Linux CPU uses the engine pod memory limit, and Linux GPU uses GPU VRAM;
  `EnforcedMemoryBudget 0 MiB` remains enforced, while `UnenforcedMemoryBudget` is an explicit
  constructor for intentionally unlimited cases
- an over-budget model publishes a clean `status=failed` real `InferenceResult` with
  `InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` instead
  of launching the engine subprocess. The generated config must remain usable when only some models
  are over budget, so smaller rows still complete and honor their per-family real-output contract
- the integration classifier must identify memory-capacity failure by the typed error constructor
  and MiB fields, distinct from a stall (a genuinely missing result, including the historical
  OS-OOM-kill symptom) and from a fabricated pass. This is reopened as Phase 4 Sprint 4.27, Phase 5
  Sprint 5.11, and Phase 6 Sprint 6.38. Canonical doctrine for the grant-gated capped-engine
  execution invariant (a host OOM is unrepresentable):
  [../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md)

## Canonical Entry Points

| Entry point | Responsibility |
|-------------|----------------|
| `infernix lint files` | validate tracked-file hygiene and generated-artifact placement |
| `infernix lint docs` | run the governed documentation validator directly |
| `infernix lint proto` | validate the protobuf contract set |
| `infernix lint chart` | validate Helm chart ownership and route-registry alignment |
| `infernix docs check` | validate the governed docs suite, metadata, required doctrine structure, generated sections, phase-plan shape, and monitoring-stance alignment |
| `infernix test lint` | run repo hygiene, chart, docs, proto, Haskell style, build, and Python quality checks |
| `infernix test unit` | own Haskell and PureScript unit coverage, including generated-catalog logic and the protobuf-over-stdio worker boundary |
| `infernix test integration` | validate cluster lifecycle, publication state, routed auxiliary surfaces, cache flows, service-loop behavior, and every generated active-mode catalog entry — the per-model traversal is bounded by substrate-specific resource admission, classifying an over-budget model as typed `ModelMemoryLimitExceeded` (see Lifecycle Failure Classification) |
| `infernix test e2e` | validate the routed browser surface and every demo-visible generated catalog entry through Playwright |
| `infernix test all` | run every supported validation layer in sequence for the active staged substrate |

## Validation Obligations

- `infernix lint files`, `infernix lint docs`, `infernix lint proto`, and `infernix lint chart`
  provide the focused validation entrypoints for repository hygiene, governed docs, protobuf
  schemas, and chart ownership when a narrower check is the supported tool for the task at hand.
- `infernix docs check` proves that the governed docs and the development plan still match the
  supported contract, including the required structure for broad doctrine docs.
- `infernix test lint` proves repo-owned static quality, the Haskell style gate, the Haskell build
  warning policy, and the shared Python adapter quality gate.
- `infernix test unit` proves the typed control-plane and browser-contract logic that should not
  require a live cluster, and keeps the Node-based PureScript runner on maintained
  `purescript-spec` entrypoints.
- `infernix test integration` proves the active staged substrate's generated catalog, routed surfaces,
  publication state, cache contract, and the real cluster's HA or lifecycle assertions.
- One DRY substrate-aware integration suite plus one substrate-agnostic Playwright suite assert a
  per-family real-output result contract — asserting shape and type per closed `ResultFamily`, never
  golden strings. Realness is guaranteed by construction — the engine code cannot fabricate a result
  (enforced by the realness lint) — so the suites trust the result and fail closed on `status=failed`;
  the reopened Phases 1/4/6 deliver and re-attest real output per accelerator (Waves K/L). Each of the
  nine families has a result surface:
  LLM and speech yield inline text; source separation, audio-to-MIDI, music transcription, image,
  video, audio generation, and OMR yield a typed `infernix-demo-objects` object reference. Each
  suite traverses the active substrate's catalog, and the UNION across the three substrate catalogs
  covers every README matrix row, enforced as a mechanical union-coverage invariant plus a
  README-to-matrix check under `infernix lint docs`. The canonical detail home for this contract is
  [../development/testing_strategy.md](../development/testing_strategy.md).
- `infernix test e2e` proves that the demo SPA can exercise every demo-visible generated
  catalog entry through the shared routed surface, with supported Playwright launchers sanitizing
  conflicting `NO_COLOR` and `FORCE_COLOR` pairs before the child process starts. The routed browser
  matrix asserts real inline text for text families through the `data-inline-output="present"` marker
  on the result message body — rejecting the `No inline output.` placeholder so a fallback cannot
  pass — and a catalog-completeness guard asserts the model-picker option set equals the published
  demo-config catalog (README matrix rows minus active-mode residuals).
- `infernix test e2e` also proves the Phase 9 admin-vs-user access-control contract at the browser
  edge: an admin session sees the operator ribbon, cluster-wide monitoring panel, and cluster summary
  cells; a non-admin is denied the four operator routes (403) and sees only its own personal
  dashboard; and the account lifecycle (sign-in, wrong-password rejection, self-service deletion,
  post-deletion auth loop) runs end-to-end. The per-spec detail lives in
  [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md).
- `infernix test all` proves that the repository passes the supported aggregate validation flow for
  the active staged substrate without dropping any layer.
- phase closure evidence records the host cohort that ran it; one cohort passing may leave a named
  counterpart-cohort residual, but `Done` requires the relevant Apple Silicon and CUDA Linux
  closure runs.

## Unsupported Paths

- ad hoc wrapper scripts or alternate validation entrypoints in place of the canonical `infernix`
  commands; the supported `bootstrap/*.sh` layer may invoke those canonical commands, but it does
  not define a second validation contract
- silently narrowing integration or E2E coverage to one representative model when the generated
  active-mode catalog contains more entries
- quietly swapping to another runtime mode when required substrate preflights are absent
- running cross-architecture emulation as validation evidence
- creating or switching Docker contexts, or creating a Colima VM, from Apple Silicon validation
- claiming cross-hardware closure from one host cohort, or requiring developers to alternate
  machines for every sprint instead of batching counterpart validation at a phase boundary
- treating monitoring dashboards, metrics stacks, or scrape configuration as a supported gated
  contract in the current repository state

## Cross-References

- [implementation_boundaries.md](implementation_boundaries.md)
- [portability.md](portability.md)
- [storage_and_state.md](storage_and_state.md)
- [../development/haskell_style.md](../development/haskell_style.md)
- [../development/testing_strategy.md](../development/testing_strategy.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)

## Validation

- validation fails on hard-gate violations; supported workflows do not silently rewrite tracked
  source
- the Haskell style gate installs `ormolu` and `hlint` through `cabal install` against the
  project `ghc-9.12.4` toolchain into `./.build/haskell-style-tools/bin/`
- runtime-mode-specific tests fail when required platform preflights are absent rather than
  quietly switching to another mode
- the supported Node-based web validation paths stay warning-free by avoiding legacy
  `runSpec` or `runSpecT` entrypoints and by clearing conflicting `NO_COLOR` or `FORCE_COLOR`
  pairs before Playwright starts
- `infernix test integration`, `infernix test e2e`, and `infernix test all` run against and report
  the active substrate encoded in the generated `.dhall`
- supported Linux E2E keeps the outer-container CLI in charge of orchestration while Playwright
  runs from inside the substrate image with `npm --prefix web exec -- playwright test`; Apple
  host-native E2E uses host `npm exec` with the same typed fixture and awaits the Apple
  validation pass
- supported Apple integration and E2E own the host daemon lifecycle when the routed demo surface
  needs it, so the validation contract proves the cluster daemon plus host inference executor
  bridge rather than treating an in-cluster pod as the Apple-native inference executor
- `infernix test e2e` requires Docker on Linux substrates and has no host-native npm fallback
  path there; Apple host-native routed E2E uses host `npm exec` with the same typed fixture
  and is covered by the Apple cohort validation batch
- full cross-hardware validation is complete only when the Apple Silicon host-native lane and the
  CUDA Linux `linux-gpu` lane have both run their relevant closure gates; `linux-cpu` is an
  additional portable lane when CPU-specific behavior changes
