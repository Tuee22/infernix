# Testing Doctrine

**Status**: Authoritative source
**Referenced by**: [../development/testing_strategy.md](../development/testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-and-e2e-hardening.md)

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
- Integration and routed E2E coverage derive their exercised set from the active generated catalog,
  so changing the initialized runtime config changes the exercised entries automatically.
- A validation gate selects one accelerator (`apple-silicon` or `linux-gpu`) plus `linux-cpu`.
  A cross-accelerator claim additionally requires the corresponding evidence from each accelerator.
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
  registry-backed rollout, and Pulsar BookKeeper durability
- hardware-specific validation runs on the machine that owns the changed path; a cross-hardware
  claim requires both Apple Silicon and CUDA Linux to run the relevant full-suite gates against the
  same source state
- `linux-cpu` validation may be used as a portable CPU-only check, but it does not substitute for
  `linux-gpu` when GPU behavior is in scope
- emulated validation is unsupported; `linux-cpu` evidence must come from native Linux rather than
  amd64 Linux under Apple Silicon emulation

## Lifecycle Failure Classification

- Each supported lifecycle state carries typed evidence rather than an assumed pass. The canonical
  contract is [Managed State Transitions](../architecture/managed_state_transitions.md).
- Long Docker build finalization, registry publication, Kind-worker image preload, and retained-state
  replay are healthy convergence while `lifecycleHeartbeatAt` keeps moving. Elapsed wall time alone
  does not classify `cluster up`, `cluster down`, `test integration`, `test e2e`, or `test all` as
  failed.
- `infernix cluster status` is the supported progress surface. While it reports
  `lifecycleStatus: in-progress`, a heartbeat refreshed roughly every 30 seconds during a monitored
  subprocess phase is progress. A non-zero owning command or a heartbeat that stops across multiple
  monitor intervals is a stall/failure signal. The same rule applies to internal bring-up and
  teardown rounds owned by `infernix test all`.
- A SIGKILLed harness during active mutation is a distinct dirty state, not a stall or clean
  failure. `ClusterLifecycle` persists `ClusterMutating`; `cluster status` reports
  mutation-incomplete rather than `steady-state`; and the next `cluster up` reconciles drained nodes
  and deployment scale.
- Resource exhaustion is distinct from both stall and clean lifecycle failure. Every active model's
  memory requirement is derived from its own artifact rather than authored — weight bytes from the
  tensor table in a bounded header read, cache bytes from the declared geometry plus the execution
  shape the engine will run under — and it is derived once per physical resource, because host
  residency and device residency are different formulas rather than one scalar reused. Each
  substrate resolves a typed `InferenceMemoryBudget` naming an enforcer per resource before launch.
  Compilation mints a resource-indexed grant only for a fitting model and retains an oversized row
  as `UnavailableModel`; live refinement must pair each grant with the enforcer for the same
  resource before producing `ExecutableModel`. An artifact that misdescribes itself yields no
  requirement rather than a small one, so a derivation refusal is a capacity refusal and never a
  quiet admission.
- A Linux GPU plan without independent host-RAM and GPU-VRAM enforcement fails compilation with
  `GpuDualResourceBudgetRequired`. An over-budget model publishes a real terminal `status=failed`
  `InferenceResult` carrying
  `InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` without
  launching the engine. Smaller rows remain usable and must honor their per-family real-output
  contract. Canonical doctrine:
  [Bounded Inference Memory](../architecture/bounded_inference_memory.md).
- The classifier separates **four** outcomes, and conflating any two of them is exactly the confusion
  the [realness contract](../architecture/realness_contract.md) forbids. A **typed capacity refusal**
  is decided before launch: the row never ran, and the published result names the resource and the
  quantities that refused it. An **in-run allocation refusal** is decided inside a live engine on a
  lane that prevents: the process started, the kernel ceiling installed before its first allocation
  refused an allocation, and the row ends as a clean terminal `status=failed` naming the resource it
  breached and the footprint it observed. A **missing result** — including an OS out-of-memory kill,
  and any stall that publishes no terminal event at all — is the pipeline failing rather than a
  decision the pipeline made. A **fabricated pass** is a realness violation whatever memory did.
  Reading the second class as a crash is the specific error to avoid: an allocation the kernel
  refused is the mechanism doing its job, while a row that dies with no terminal event is the
  mechanism absent.

## Canonical Entry Points

| Entry point | Responsibility |
|-------------|----------------|
| `infernix lint files` | validate tracked-file hygiene and generated-artifact placement |
| `infernix lint docs` | run the governed documentation validator directly |
| `infernix lint proto` | validate schema/package/symbol shape plus the exact two-schema/four-module Haskell binding snapshot inventory and hashes, without invoking a generator |
| `infernix lint chart` | validate Helm chart ownership and route-registry alignment |
| `infernix lint plan` | validate the development plan's status vocabulary, remaining-work agreement, forward-only dependency edges, single-accelerator validation gates, declarative language, removal-ledger exclusivity, and single current-state table |
| `infernix docs check` | validate the governed docs suite, metadata, required doctrine structure, generated sections, phase-plan shape, and monitoring-stance alignment |
| `infernix test lint` | run repo hygiene, chart, docs, proto, plan-standards, Haskell style, build, and Python quality checks |
| `infernix test unit` | own Haskell and PureScript unit coverage, including generated-catalog logic and the protobuf-over-stdio worker boundary |
| `infernix test integration` | validate cluster lifecycle, publication state, routed auxiliary surfaces, cache flows, service-loop behavior, and every generated active-mode catalog entry — the per-model traversal is bounded by substrate-specific resource admission, classifying an over-budget model as typed `ModelMemoryLimitExceeded` (see Lifecycle Failure Classification) |
| `infernix test e2e` | validate the routed browser surface and every demo-visible generated catalog entry through Playwright |
| `infernix test all` | run every supported validation layer in order for the active initialized substrate. The layers are ordered, not mutually isolated: the cluster-owned validation encloses the toolchain-authority stage, so the toolchain account and the inference partition are claimed within one bracket and the exclusive host claim owned by [../architecture/bounded_host_memory.md](../architecture/bounded_host_memory.md) is what keeps them from being resident together |

## Validation Obligations

- `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart`, and
  `infernix lint plan` provide the focused validation entrypoints for repository hygiene, governed
  docs, protobuf schemas, chart ownership, and development-plan standards when a narrower check is
  the supported tool for the task at hand.
- `infernix docs check` proves that the governed docs and the development plan still match the
  supported contract, including the required structure for broad doctrine docs.
- `infernix test lint` proves repo-owned static quality, the development-plan standards scans, the
  Haskell style gate, the Haskell build warning policy, and the shared Python adapter quality gate.
- `infernix test unit` proves the typed control-plane and browser-contract logic that should not
  require a live cluster, and keeps the Node-based PureScript runner on maintained
  `purescript-spec` entrypoints.
- `infernix test integration` proves the active initialized substrate's generated catalog, routed surfaces,
  publication state, cache contract, and the real cluster's lifecycle assertions.
- One DRY substrate-aware integration suite plus one substrate-agnostic Playwright suite assert a
  per-family real-output result contract — asserting shape and type per closed `ResultFamily`, never
  golden strings. Realness is guaranteed by construction — the engine code cannot fabricate a result
  (enforced by the realness lint) — so the suites trust the result and fail closed on `status=failed`;
  real output is attested per accelerator. Each of the
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
- `infernix test e2e` also proves the admin-vs-user access-control contract at the browser
  edge: an admin session sees the operator ribbon, cluster-wide monitoring panel, and cluster summary
  cells; a non-admin is denied the four operator routes (403) and sees only its own personal
  dashboard; and the account lifecycle (sign-in, wrong-password rejection, self-service deletion,
  post-deletion auth loop) runs end-to-end. The per-spec detail lives in
  [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md).
- `infernix test all` proves that the repository passes the supported aggregate validation flow for
  the active initialized substrate without dropping any layer.
- validation closure follows the single-accelerator rule in
  [development-plan standards](../../DEVELOPMENT_PLAN/development_plan_standards.md): one selected
  accelerator (`apple-silicon` or `linux-gpu`) plus `linux-cpu`, never both in one must-pass gate.
  Cross-accelerator contracts use sibling attestations or a `linux-cpu`-only aggregation.

## Unsupported Paths

- ad hoc wrapper scripts or alternate validation entrypoints in place of the canonical `infernix`
  commands; the supported `bootstrap/*.sh` layer may invoke those canonical commands, but it does
  not define a second validation contract
- silently narrowing integration or E2E coverage to one representative model when the generated
  active-mode catalog contains more entries
- quietly swapping to another runtime mode when required substrate preflights are absent
- running cross-architecture emulation as validation evidence
- creating or switching Docker contexts, or creating a Colima VM, from Apple Silicon validation
- claiming cross-hardware closure from evidence produced on only one accelerator
- treating monitoring dashboards, metrics stacks, or scrape configuration as a supported gated
  contract

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
- the root Haskell-style component links pinned `ormolu` and `hlint` libraries, while a genuinely
  separate Cabal-format package links pinned `Cabal 3.16`; the closed aggregate lint command runs
  each check in-process under sequential top-level toolchain children, and neither installs nor
  starts style-tool child processes at test runtime
- runtime-mode-specific tests fail when required platform preflights are absent rather than
  quietly switching to another mode
- the supported Node-based web validation paths stay warning-free by avoiding legacy
  `runSpec` or `runSpecT` entrypoints and by clearing conflicting `NO_COLOR` or `FORCE_COLOR`
  pairs before Playwright starts
- `infernix test integration`, `infernix test e2e`, and `infernix test all` run against and report
  the active substrate encoded in the generated `.dhall`
- supported Linux E2E keeps the outer-container CLI in charge of orchestration while Playwright
  runs from inside the substrate image with `npm --prefix web exec -- playwright test`; Apple
  host-native E2E uses host `npm exec` with the same typed fixture against the Apple
  validation pass
- supported Apple integration and E2E own the host daemon lifecycle when the routed demo surface
  needs it, so the validation contract proves the cluster daemon plus host inference executor
  bridge rather than treating an in-cluster pod as the Apple-native inference executor
- `infernix test e2e` requires Docker on Linux substrates and has no host-native npm fallback
  path there; Apple host-native routed E2E uses host `npm exec` with the same typed fixture
  and is covered by the Apple selected-accelerator gate
- full cross-hardware validation is complete only when the Apple Silicon host-native lane and the
  CUDA Linux `linux-gpu` lane have both run their relevant closure gates; `linux-cpu` is an
  additional portable lane when CPU-specific behavior changes
