# Infernix Development Plan

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md)

> **Purpose**: Provide the single execution-ordered development plan for `infernix`, including
> phase status, repository-shape decisions, validation gates, and documentation obligations.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Common-Shape Reopen (Pulsar ML-Workflow convergence)

`infernix` and the `jitML` sister project are converging on one shared contract,
[../documents/architecture/pulsar_ml_workflow.md](../documents/architecture/pulsar_ml_workflow.md)
(Engine / Coordinator / Webapp roles, a derived topic algebra, the `Work*` envelope
family, the artifact + `.ready` readiness contract, websocket snapshot/patch, and a
reflected-Dhall-schema one-binary role model). This tracks three surfaces, each
tracked in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md):

- **Phase 4** — the **Coordinator** now owns explicit topic-lifecycle
  reconciliation from the typed runtime graph, and the binary emits its own
  reflected Dhall schema through `infernix internal dhall-schema
  host|cluster|secrets|substrate`. Per Phase 8, there are **no version-controlled
  `.dhall` files**: the schema exists only as the reflected output of the Haskell
  decoder types, emitted on demand.
- **Phase 6** — phase validation moves to **single-accelerator-per-phase** (standards
  §Q): one of `apple-silicon` or `linux-gpu` plus `linux-cpu`, never both;
  `cohort-validation-waves.md` is repurposed as per-accelerator attestation ledgers.
- **Phase 7** — the demo frontend now runs as the one-binary **Webapp** role through
  `infernix service --role webapp`; the former two-binary split is closed in the cleanup ledger.

Any still-present compatibility or consolidation surfaces are listed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) rather than hidden in phase
status prose.

## June 2026 Audit Follow-On Reopen

A full documentation/code audit reopened three bounded follow-ons without disturbing the prior
validation record for the already-closed work:

- **Phase 4 Sprint 4.24** — replace the duplicated Pulsar result timestamp `show` / partial `read`
  conversion with the same safe ISO-8601 codec used by `Storage.hs`.
- **Phase 6 Sprint 6.34** — close documentation-lint coverage gaps and no-env/no-PATH enforcement
  drift in pre-manifest or lint-owning code.
- **Phase 7 Sprint 7.28** — make generated artifact object ownership Haskell-derived from
  `userId` + `contextId` so adapter/native outputs cannot bypass the per-user
  `users/<sub>/contexts/<ctx>/generated/` layout. Closed 2026-06-30 by the full selected
  `linux-gpu` plus `linux-cpu` cohort gate.

The legacy or duplicate surfaces targeted by those sprints are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## MT3 Catalog Replacement (closed by Wave P)

The 2026-06-30 replacement of the obsolete MT3 residual with `music-mt3-infer` and
`music-mr-mt3` reopened **Phase 4 Sprint 4.22** and **Phase 6 Sprint 6.35** (the Wave O follow-on).
Both rows bind through `mt3-infer` on the PyTorch adapter, use model-cache staged weights, disable
upstream auto-downloads, and are generated for `linux-cpu`, `linux-gpu`, and `apple-silicon` (Apple
uses PyTorch CPU; no MPS claim is made). The old `music-mt3-jax` residual is removed and recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

Wave O is **closed** — proven by [Wave P](cohort-validation-waves.md) on 2026-07-04: rebuilt
`linux-gpu` **and** `linux-cpu` full-suite `infernix test all` both GREEN with routed Playwright
**9/9** over the expanded catalogs, including `music-mt3-infer`, `music-mr-mt3`, and the 27 GB
`video-wan21-t2v` row (the clean `linux-gpu` 9/9 landed once Phase 8 Sprint 8.5 eager model-cache
staging shipped). The per-attempt CPU dependency-resolution chronology is recorded in the Wave O row
of [cohort-validation-waves.md](cohort-validation-waves.md).

## Resource Admission Doctrine Reopen (2026-07-09)

The FIFO/serialized RAM guard added in Phase 4 Sprint 4.26 was the right direction, but the
implementation made capacity a catalog-wide startup failure and encoded the runtime failure as
stringly successful inline output. The current doctrine reopens Phases 4, 5, and 6:

- **Phase 4 Sprint 4.27** — replace the Apple-only integer budget and config-time fail-fast with a
  pure `InferenceMemoryBudget` / `InferenceError` model. One oversized model must not invalidate the
  daemon; runtime admission rejects only that request with typed `ModelMemoryLimitExceeded` carrying
  `requiredMib` and `availableMib`.
- **Phase 5 Sprint 5.11** — thread typed inference errors through browser contracts and render the
  demo-app capacity message from the ADT fields, not from parsed text.
- **Phase 6 Sprint 6.38** — validate the doctrine across substrates: Apple unified host RAM without
  hardcoded floors, Linux CPU engine pod memory limit, Linux GPU VRAM, and classifier assertions by
  constructor and MiB quantities.

The superseded fail-fast and stringly-result surfaces are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

Code-side closure landed on 2026-07-09 and was tightened on 2026-07-10 after the live CPU browser
matrix exposed fast failed-result reducer races around snapshots, patches, rendered-context
staleness, and locally submitted prompts. Rebuilt Linux CPU image
`sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306`
contains the current reducer fixes and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke,
and rebuilt-image `infernix test unit` (Haskell unit plus web `80/80`). Its full `linux-cpu`
rerun passed Haskell style, Python `check-code`, Haskell unit, web `80/80`, and the full live
integration lane, then routed Playwright reached `15/16` and failed only the visible
capacity-message assertion after the typed terminal payload. Current source adds a per-context
conversation cache so inactive or transiently stale patches are retained without displacing the
rendered pane; focused mounted-source PureScript validation passes `81/81`. Rebuilt image
`sha256:5ccdac2c89b435c1452f63c7fc5df41ca07893bfabc581134aef95db0468ace9` contains that cache fix
and passes rebuilt-image `infernix test unit` (Haskell unit plus web `81/81`). Its full rerun
reached PostgreSQL lifecycle rebinding after the typed-admission, HA, throughput, and
platform-recovery checks, then hung inside the second `cluster up` warm-cache path with an idle
MinIO NodePort connection. Current source bounds the MinIO warm-cache/model-bootstrap HTTP calls in
`Infernix.Runtime.Pulsar` (`HEAD` sentinel probes 15s, write responses 300s), and focused
mounted-source Haskell validation passes `cabal test infernix-unit`. Rebuilt image
`sha256:f0276a2efcae1fa7b2d33a7bb7a0e442b9d4c2be5687515c439f9cb75bf909ec` contains the timeout
fix and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun failed before
runtime validation on a Haskell style import-order diff in `Infernix.Runtime.Pulsar`; current
source applies the style-only reorder, and focused mounted-source validation passes
`cabal test infernix-haskell-style`. Rebuilt image
`sha256:5d423bd3d988103e6777fcfa80b92da07684263af056f7e6c9395e4802176cec` contains that style fix
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full rerun passed the front gates and
advanced through typed CPU admission, HA/recovery, model-bootstrap deduplication, throughput
(`totalPrompts = 12`, `p95Seconds = 65.50490140914917`), Harbor/MinIO/Pulsar recovery, and
PostgreSQL failover before stalling in the lifecycle-rebinding second `cluster up` while
republishing Harbor images; diagnostics showed the integration process sleeping with a direct
`[docker] <defunct>` child. Current source replaces the monitored subprocess waiter in
`Infernix.ProcessMonitor` with a blocking reaper plus heartbeat loop; focused mounted-source
validation passes `cabal test infernix-haskell-style` and `cabal test infernix-unit` with that
module mounted into the Linux CPU launcher image. Rebuilt Linux CPU image
`sha256:ab2f12cd81a094ffc267eacfb637ae055c8b3c8cd31e364dfc2f54cbcdf21597` contains the monitor fix
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun advanced past the
previous monitored-publish stall and through typed CPU admission, HA replacement/drain, and clean
cluster teardown, but failed in the model-bootstrap failover/deduplication integration step after
timing out on the ready topic for `integration-bootstrap-chaos-1783761854482798`.
Current source carries the bootstrap-failover remediation: exact bootstrap request replays remain
publishable across uncertain coordinator failover, ready-event deduplication is scoped to the
request attempt, and bootstrap credential-load failures nack rather than acking a no-ready path.
Focused mounted-source validation passes `cabal test infernix-haskell-style` and
`cabal test infernix-unit` for that remediation. Rebuilt Linux CPU image
`sha256:534f631468380d9e59df713e4e8c78b976e17b17e0c64eb09be4eff8d6f41388` contains the remediation
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun passed the front
gates, full live integration, the previous model-bootstrap failover/deduplication gate, PostgreSQL
lifecycle rebinding, anti-affinity, and the `demo_ui = false` lifecycle. Routed Playwright passed
`15/16`, including the Sprint 9.9 logout/account-switching specs and artifact coverage, then failed
only the browser matrix visible capacity-result assertion after receiving the typed terminal
`ModelMemoryLimitExceeded` payload. Current source now projects the rendered chat pane from the
active context id plus the per-context conversation cache so a stored terminal result for the
selected context cannot remain hidden behind a stale `activeConversation` pane, and the Playwright
assertion now names the model/context if this path regresses again. Focused mounted-source
PureScript validation passes `82/82`, and `node --check web/playwright/inference.spec.js` passes for
the diagnostic assertion. Rebuilt Linux CPU image
`sha256:e09f824b06b489a574288dbafcf1c8cc5920ae0bcb1a96cea91306a6cd57221c` now contains that
render-projection fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun
passed Haskell style, Python `check-code`, Haskell unit, web `82/82`, and full live integration
after inactive Docker build-cache cleanup recovered the host from `0` bytes free; throughput
recorded `totalPrompts = 12`, `p95Seconds = 86.15112495422363`, retained lifecycle rebinding,
anti-affinity, and the `demo_ui = false` lifecycle all passed. Routed Playwright again reached
`15/16` and failed only the browser matrix capacity-result render assertion for
`audio-demucs-htdemucs`; the new diagnostic showed the target context was active before the DOM
result wait. Current source now ignores stale WebSocket messages from superseded connection
generations, keeps one live per-context stream per WebSocket session, and waits for the subscribed
conversation snapshot before matrix submissions. Focused mounted-source validation now passes
`cabal test infernix-haskell-style infernix-unit` with `src/Infernix/Demo/WebSocket.hs` mounted,
web unit `82/82` with `web/src/Main.purs` and `web/playwright/inference.spec.js` mounted, and
`node --check web/playwright/inference.spec.js`. Rebuilt Linux CPU image
`sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d`
(`20070899656` bytes, created `2026-07-11T11:57:16.110576974-04:00`) contains this fix and passes
`./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`).
Its full `linux-cpu` rerun passed the front gates and full live integration, including typed
admission for the six over-budget rows, HA/recovery, model-bootstrap failover/deduplication,
throughput (`totalPrompts = 12`, `p95Seconds = 65.46250057220459`), PostgreSQL lifecycle rebinding,
anti-affinity, and `demo_ui = false`. Routed Playwright reached `15/16`: auth/RBAC/logout switching
and artifact upload/preview/download were green, and the matrix observed the typed terminal
`ModelMemoryLimitExceeded` payload for `audio-demucs-htdemucs`, but the visible capacity-result DOM
assertion still failed. Current source now gives browser-facing Pulsar readers unique per-stream
names and tags Playwright-observed WebSocket frames by browser socket generation, so the matrix waits
for live-generation snapshots and terminal patches instead of accepting stale frames from a
superseded socket. `node --check web/playwright/inference.spec.js` passes for that helper change,
`git diff --check` is clean for the touched files, and mounted-source Haskell validation passes
`cabal test infernix-haskell-style infernix-unit` with `src/Infernix/Runtime/Pulsar.hs` mounted
into the Linux CPU launcher image.
Earlier machine-independent gates also passed `infernix test lint`,
`infernix lint files|docs|proto|chart`, `infernix docs check`, and an integration-suite compile
preflight. The reopened sprints are closed by [Wave T](cohort-validation-waves.md): `linux-cpu`
passed full routed evidence on image
`sha256:c911771090115baa928d6bf43f14ef804cfcdc8706bc96ab3fe6b62f48a19a6f`, and the selected
`linux-gpu` accelerator passed `./bootstrap/linux-gpu.sh test` on image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896` with full live
integration and routed Playwright `16/16`.

## Phase 9 UAT Auth Residual (2026-07-09)

A later UAT pass surfaced a Phase 9 admin-vs-user access issue recorded in repo-root `notes.txt`.
The issue is now diagnosed and code-side closed: local-only Sign out left the Keycloak SSO browser
session alive, so switching from a self-registered user to the separate admin login could silently
reuse the non-admin session. Sprint 9.9 adds a real Keycloak logout redirect and a routed browser
regression for user-to-admin switching. Phase 9 is closed by [Wave U](cohort-validation-waves.md),
which recorded routed `linux-cpu` evidence and selected `linux-gpu` evidence for the new
logout/account-switching behavior.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Maintenance rules for the development plan |
| [00-overview.md](00-overview.md) | Architecture baseline, hard constraints, substrate contract, and canonical repository shape |
| [system-components.md](system-components.md) | Authoritative component inventory and state-location map |
| [cohort-validation-waves.md](cohort-validation-waves.md) | Per-accelerator attestation ledgers (one per accelerator) under Section Q's single-accelerator-per-phase rule; a `linux-cpu` aggregation phase merges them |
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite bootstrap plus the substrate-doctrine documentation reset |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, CLI contract, build-root doctrine, launcher ownership, and substrate-selection closure |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Harbor-first image flow, substrate `.dhall` publication, Linux launcher closure, and lifecycle-progress hardening |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and the Apple cluster-to-host inference bridge for routed demo traffic |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, cluster-daemon request consumption, Apple host inference execution, staged `.dhall` role control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, Apple host-backed browser dispatch, and Playwright ownership |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, README-matrix-driven single-substrate validation, Apple cluster-to-host daemon split coverage, root-doc closure, HA validation, and false-negative doctrine hardening |
| [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) | Multi-user durable-context demo: Keycloak auth, WebSocket transport, Pulsar-backed conversation history, MinIO artifact upload/download/render-or-download, Haskell-first logic via purescript-bridge, and the three-role daemon split (stateless frontend, stateless coordinator, substrate-specific engine pools) with an HA-first chart |
| [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) | Adopt the hostbootstrap Dhall doctrine: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (incl. ConfigMap/Secret bodies; Helm only embeds a string), explicit `init` / `test init` creation with ordinary commands failing fast when config is missing and Apple bootstrap `up` explicitly running `init --if-missing`, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging from the mounted `infernix.dhall` (replacing the lazy per-inference bootstrap) |
| [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md) | Role-based access control and monitoring: the admin (cluster-wide operator consoles + monitoring) vs. user (own chat/artifacts/files + personal dashboard) split, Keycloak admin role + JWT role claim, edge admin authorization with ungated-route closure, admin/personal dashboards, per-user MinIO STS defense-in-depth, and the Apple host-worker loopback data-plane invariant |
| [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) | Explicit cleanup and removal ledger |

## Status Vocabulary

| Status | Meaning |
|--------|---------|
| `Done` | Implemented, validated, docs aligned, no remaining work |
| `Active` | Partially implemented; remaining work is explicit |
| `Blocked` | Waiting on named prerequisites |
| `Planned` | Ready to start; dependencies are already satisfied |

## Definition of Done

A phase or sprint can move to `Done` only when all of the following are true:

1. The listed implementation paths exist in the current worktree.
2. The listed validation gates pass on the supported execution path, with the phase's **single
   chosen accelerator** cohort (`apple-silicon` **or** `linux-gpu`) plus `linux-cpu` recorded when
   substrate-aware behavior is in scope — never both accelerators against one phase.
3. The governed docs named in `Docs to update` match the implementation.
4. No remaining cleanup or compatibility surface is left unstated.
5. Cleanup promised by the sprint is reflected in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

`Done` is the single-accelerator sign-off gate (item 2's one-accelerator-plus-`linux-cpu` evidence).
It is distinct from *code-side closure* — the implementation plus the machine-independent gate set —
which is completed in natural phase order on a single machine and is the gate to begin the *next*
phase's implementation. A phase whose code-side closure is complete but whose single chosen
accelerator full-suite is still pending stays `Active` with a named `Cohort gate` residual; that
residual does not block the next phase's implementation. See the single-accelerator execution rule in
[development_plan_standards.md](development_plan_standards.md) Section Q, and the shared
[../documents/architecture/pulsar_ml_workflow.md](../documents/architecture/pulsar_ml_workflow.md)
contract.

## Current Repo Assessment

The June 2026 audit reopened Phase 4, Phase 6, and Phase 7 for the bounded follow-ons listed above.
Earlier sprint closure evidence remains valid for its original scope. Phase 4 Sprint 4.24 is now
re-closed, Phase 6 Sprint 6.34 is now re-closed for no-env/docs-lint coverage, and Phase 7 Sprint
7.28 is now re-closed for generated-artifact ownership after the full selected `linux-gpu` plus
`linux-cpu` cohort gate and matching deletion-ledger move. The MT3 catalog-replacement follow-on
(Phase 4 Sprint 4.22 and Phase 6 Sprint 6.35) closed under [Wave P](cohort-validation-waves.md) on
2026-07-04. The later 2026-07-06 Wave Q review cohort-validated the Phase 9 access-control/monitoring
RBAC/STS/dashboard surface on both `apple-silicon` and `linux-cpu`, and reopened Phases 4 and 6 for
the matrix substrate-accuracy hardening (Sprints 4.25 and 6.36) plus the 2026-07-07 apple-silicon
inference RAM-safety gap (Sprints 4.26 and 6.37). [Wave R](cohort-validation-waves.md) (2026-07-08)
and [Wave S](cohort-validation-waves.md) (2026-07-09) closed those sprints for their implemented
scope.

On 2026-07-09, the resource-admission doctrine reopened **Phase 4 Sprint 4.27**, **Phase 5 Sprint
5.11**, and **Phase 6 Sprint 6.38**. Code-side closure is now complete: serialized/FIFO runtime
admission remains, the catalog-wide fail-fast is removed, hardcoded budget floors are replaced with
typed `InferenceMemoryBudget` semantics, admission extends to Linux CPU pod memory and Linux GPU
VRAM, and capacity failures publish typed `InferenceError.ModelMemoryLimitExceeded` payloads with
explicit MiB quantities. Wave T's `linux-cpu` full live-suite gate closed on 2026-07-12 with a
rebuilt image carrying the explicit tagged `InferenceError` WebSocket contract fix; the selected
`linux-gpu` accelerator gate also closed on 2026-07-12 with full `./bootstrap/linux-gpu.sh test`.
A later UAT pass also surfaced Phase 9's
logout/account-switching issue (repo-root `notes.txt`); Sprint 9.9 diagnoses and closes it
code-side, with Wave U's `linux-cpu` and selected `linux-gpu` routed evidence now green.

Wave T chronology (2026-07-10 onward): rebuilt image
`sha256:05e0aadf5ea0feb98f25e82ab196f23893be0441e59f5e91f9fec346bfa6d8c0` passed the `linux-cpu`
full live integration lane and web unit `75/75`, but the full `linux-cpu` gate remained open after
routed Playwright ended `14/16` on the known artifact-preview grant timing case plus the typed
capacity-message render race. Current source has a focused `76/76` PureScript pass for the
cross-context snapshot fix and an artifact-helper readiness fix. Rebuilt image
`sha256:c01a9a070ca842b973543301dcbaaa039811492f707fdc20c804aa30bd5f40ee` now passes
`./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web `76/76`, and its
full-suite rerun passed integration plus routed Playwright `15/16`. The remaining matrix failure is
the visible capacity message after an active-context switch; current source now seeds the active
context from a matching patch when the stored conversation still belongs to a previous context, and
focused mounted-source PureScript validation passes `77/77`. Rebuilt image
`sha256:84e3915260e5fd7684b817bf520e9eaca4f40946665d86ae2afb5276b1eedfcb` now contains this latest
fix and passed the `./bootstrap/linux-cpu.sh build` CLI-help smoke plus rebuilt-image
`infernix test unit` (Haskell unit plus web `77/77`). Its full-suite rerun passed the front gates
and the live integration path through typed CPU admission, smaller-model continuity, HA/chaos,
throughput, platform recovery, lifecycle rebinding, and anti-affinity, then failed in the later
lifecycle cluster-up after the retained Pulsar repair path reset claim roots once and the same
dirty-metadata signal recurred. Current source now allows a bounded number of retained Pulsar claim
root resets per `cluster up`. Rebuilt image
`sha256:0bf82aba452b2bee8f5de6c4ee136c7d72537ac0dbd4377ee52ee3718d77c0aa` contains that fix and
passed `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `77/77`). Its full-suite rerun passed the front gates
and full live integration, including typed CPU admission, smaller-model continuity, HA/chaos,
throughput (`totalPrompts = 12`, `p95Seconds = 82.15346002578735`), platform recovery, lifecycle
rebinding, anti-affinity, and the `demo_ui = false` lifecycle; repeated retained-data cluster-ups no
longer hit the prior dirty Pulsar metadata failure. Routed Playwright reached `15/16` and passed the
Sprint 9.9 auth/RBAC/account-switching specs plus artifact upload/download grants; the remaining
failure is the browser matrix visible capacity message after receiving a typed terminal
`ModelMemoryLimitExceeded` payload. Current source now keeps applying same-context patches when the
rendered conversation already targets that context even if `activeContextId` is transiently stale,
adds a raw Haskell-wire `ModelMemoryLimitExceeded` WebSocket decode regression, and passes focused
mounted-source PureScript validation at `79/79`. Rebuilt image
`sha256:4e2e2a9f642ecc15635df849539b82a847d350db19e161cf6517d56a29ea6b62`
contains that reducer/decode fix and passed `./bootstrap/linux-cpu.sh build` plus the CLI-help
smoke and rebuilt-image `infernix test unit` (Haskell unit plus web `79/79`). Its full-suite rerun
again passed Haskell style, Python `check-code`, Haskell unit, web `79/79`, full live integration,
throughput (`totalPrompts = 12`, `p95Seconds = 65.4941475391388`), platform recovery, lifecycle
rebinding, anti-affinity, and the `demo_ui = false` lifecycle, then routed Playwright reached
`15/16` and failed only the same visible capacity-message assertion after receiving the typed
terminal payload. Current source now pins the submitted prompt into the active conversation before
the fast terminal result can arrive and adds a stale-active-id rendered-context reducer regression.
Rebuilt image `sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306`
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `80/80`). Its full `linux-cpu` rerun passed Haskell
style, Python `check-code`, Haskell unit, web `80/80`, and full live integration, including typed
CPU admission, smaller-model continuity, platform recovery, lifecycle rebinding, anti-affinity, and
the `demo_ui = false` lifecycle; routed Playwright again reached `15/16` and failed only the
visible capacity-message DOM assertion after receiving the typed terminal payload. Current source
now stores conversations per context and preserves inactive/stale terminal patches for later
rendering; focused mounted-source PureScript validation passes `81/81`. Rebuilt Linux CPU image
`sha256:5ccdac2c89b435c1452f63c7fc5df41ca07893bfabc581134aef95db0468ace9` contains that cache fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full rerun passed the front gates and
progressed through PostgreSQL lifecycle rebinding, then hung in the second `cluster up` warm-cache
path with an idle MinIO NodePort connection. Current source bounds the MinIO
warm-cache/model-bootstrap HTTP calls in `Infernix.Runtime.Pulsar`, and focused mounted-source
Haskell validation passes `cabal test infernix-unit`. Rebuilt image
`sha256:f0276a2efcae1fa7b2d33a7bb7a0e442b9d4c2be5687515c439f9cb75bf909ec` contains the timeout
fix and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun failed before
runtime validation on a Haskell style import-order diff in `Infernix.Runtime.Pulsar`; current
source applies the style-only reorder, and focused mounted-source validation passes
`cabal test infernix-haskell-style`. Rebuilt image
`sha256:5d423bd3d988103e6777fcfa80b92da07684263af056f7e6c9395e4802176cec` contains that style fix
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). A later full `linux-cpu` rerun on
`sha256:534f631468380d9e59df713e4e8c78b976e17b17e0c64eb09be4eff8d6f41388` passed the front gates
and full live integration, then routed Playwright reached `15/16` and failed only the visible
capacity-result assertion after receiving the typed terminal payload. Current source projects the
rendered chat pane from the active context id plus the per-context conversation cache; rebuilt Linux
CPU image `sha256:e09f824b06b489a574288dbafcf1c8cc5920ae0bcb1a96cea91306a6cd57221c` contains that
fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front
gates and full live integration, including typed CPU admission, throughput
(`totalPrompts = 12`, `p95Seconds = 86.15112495422363`), lifecycle rebinding, anti-affinity, and
the `demo_ui = false` lifecycle; routed Playwright reached `15/16` and failed only the
`audio-demucs-htdemucs` visible capacity-result assertion after proving the target context was
active. Current source hardens stale WebSocket generation handling and subscription readiness. The
focused mounted-source gates now pass: Haskell style/unit for `src/Infernix/Demo/WebSocket.hs`, web
unit `82/82`, and `node --check web/playwright/inference.spec.js`. Rebuilt Linux CPU image
`sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d` contains the fix and
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front
gates and full live integration, then routed Playwright reached `15/16` and failed only the
`audio-demucs-htdemucs` visible capacity-result assertion after the matrix observed the typed
terminal payload. Current source now gives browser-facing Pulsar readers unique per-stream names
and tags Playwright-observed WebSocket frames by socket generation, so waits are tied to the live
browser connection. Rebuilt Linux CPU image
`sha256:eeb58064f9eca14c008b9c976380c5c7745a4c6079a5bd8885b3935c864532a5`
(`20070858505` bytes, created `2026-07-11T14:49:26.455414736-04:00`) contains that fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, including typed CPU admission for the six over-budget rows, smaller-model continuity,
throughput (`totalPrompts = 12`, `p95Seconds = 65.51375341415405`), lifecycle rebinding,
anti-affinity, and the `demo_ui = false` lifecycle. Routed Playwright reached `14/16`: the artifact
spec hit a download-button replacement race after `data-download-status="pending"`, and the matrix
still failed the `audio-demucs-htdemucs` visible capacity-result assertion after validating the
typed terminal payload. Current source waits for the artifact upload record echo before Download,
retries against a re-resolved artifact card until the download grant is ready and the URL is the
webapp proxy, and scopes the capacity-result DOM wait to the exact typed memory message with a
resubscription fallback. `node --check web/playwright/inference.spec.js` and `git diff --check` pass
for this follow-up. Rebuilt Linux CPU image
`sha256:d49b4799375df7a0e5726d16717ab6dc4e09fc8baa685969484099027f81c4c8`
(`20070886873` bytes, created `2026-07-11T17:27:02.378037428-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, including typed CPU admission for the six over-budget rows, smaller-model continuity,
throughput (`totalPrompts = 12`, `p95Seconds = 69.06893110275269`), lifecycle rebinding,
anti-affinity, and the `demo_ui = false` lifecycle. Routed Playwright reached `15/16`: the artifact
upload/preview/download spec passed, but the browser matrix still failed the
`audio-demucs-htdemucs` visible capacity-result assertion after resubscription. The next Wave T gate
is the capacity-result render fix, a clean full `linux-cpu` rerun, and the selected `linux-gpu`
accelerator gate. Current source now correlates the matrix terminal result to the server prompt
message id for the exact submitted prompt; `node --check web/playwright/inference.spec.js` and
`git diff --check` pass for that follow-up. The next validation gate is rebuilt-image unit evidence
and a clean full `linux-cpu` rerun with this correlation fix. Rebuilt Linux CPU image
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

Latest Wave T update (2026-07-12): rebuilt Linux CPU image
`sha256:c911771090115baa928d6bf43f14ef804cfcdc8706bc96ab3fe6b62f48a19a6f`
(`20088000300` bytes, created `2026-07-12T02:30:27.200982353-04:00`) contains the
explicit tagged `InferenceError` WebSocket contract fix. It passed `./bootstrap/linux-cpu.sh build`,
the CLI-help smoke, rebuilt-image `infernix test unit` (Haskell unit plus web `83/83`), and
rebuilt-image `infernix test e2e`: the full routed suite passed `16/16` in 3.6 minutes, including
the per-model browser matrix in 2.5 minutes, Sprint 9.9 auth/RBAC/logout/account-switching, and
artifact upload/preview/download coverage. The live integration portion again proved typed Linux CPU
capacity admission, smaller-model continuity, HA/chaos, lifecycle, and throughput behavior with the
known non-blocking `music-omnizart` warm-cache warning. This closes Wave T's `linux-cpu` Stage 2
evidence. The selected `linux-gpu` accelerator gate also closed on rebuilt image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896`: `./bootstrap/linux-gpu.sh test`
passed full live integration and routed Playwright `16/16`, including the per-model browser
matrix and typed GPU capacity-message path.

Prior closure evidence closes around the implemented worktree. Phase 3 Sprint 3.12 and
[Wave F](cohort-validation-waves.md) closed on the recorded validation after native `linux/arm64` validation
through the already selected arm64 Docker daemon on this Apple Silicon machine. The repository implements the
staged-substrate architecture, the baked Linux outer-container launcher,
the mandatory HA platform services, the Gateway-owned routed edge, the shared Python adapter
project, the Haskell-owned browser-contract generation path, the substrate-specific validation
surface, and the current Apple split-executor topology described below. The runtime-routing
code-side target has landed around substrate-neutral engine pools: the coordinator remains the
production router, normal pools use Pulsar `Shared` plus broker-native backpressure, pinned routes
use derived per-member topics with `Exclusive`, Linux members are Kubernetes workloads, and Apple
members are same-binary host daemons selected by stable host id. Legacy raw-topic compatibility
surfaces, the demo-off coordinator gate, and the two-binary `infernix` / `infernix-demo` split have
all been removed; the supported topology is the one-binary model with the demo frontend served by
the `Webapp` role through `infernix service --role webapp`.

The repository implements the substrate-file doctrine described by this plan. Supported flows
stage one `infernix.dhall` beside the active build root through the `infernix` command
that needs it; the explicit
`infernix internal materialize-substrate ...` helpers remain the direct restaging or inspection
surface. The Linux substrate Dockerfile materializes a build-arg-selected substrate file inside
the image overlay during image build, and supported Compose runs keep that active build root
image-local instead of bind-mounting the host `./.build/` tree. Focused `infernix lint ...` and
`infernix docs check` remain substrate-file independent. The final substrate payload also
distinguishes cluster and host daemon
roles: cluster-role configs name the substrate, request and result topics, and the engine-pool graph,
while host-role Apple configs include the routed Pulsar connection details and the host member's pool
membership. Cluster publication mirrors the
cluster-role payload locally under
`./.data/runtime/configmaps/infernix-demo-config/infernix.dhall` and mounts the same
filename inside cluster workloads at `/opt/build/infernix-substrate.dhall`, while the Apple host
file under `./.build/` remains host-role metadata for the same substrate. The file is a typed
Dhall record at `infernix.dhall`, decoded in-process by the `dhall` Haskell library.
`infernix test all`
runs the full supported validation suite for the active built substrate; full repository substrate
closure comes from separate governed reruns for `apple-silicon`, `linux-cpu`, and `linux-gpu`,
not from one implicit cross-substrate matrix invocation. The generated file, `cluster status`,
publication JSON, and generated browser contracts still serialize that active substrate under
`runtimeMode` field names. `cluster status` does not mutate Kubernetes resources, publication
state, or authoritative repo-local state; the accepted Linux outer-container exception is an
idempotent Docker network membership repair that attaches the fresh launcher container to the
private `kind` network for observation. The Apple split-executor contract is implemented on
`apple-silicon`: `cluster up` keeps Harbor, MinIO, Pulsar, PostgreSQL, Envoy Gateway, the optional
clustered `infernix-demo` surface, and cluster `infernix-coordinator` Deployment in Kind; Apple
inference execution remains host-native. The pool target replaces the single Apple host topic and
Linux-specific per-engine topic special cases with topics derived from `(runtimeMode, pool id, model
id, optional member id)`. The generated final-phase Helm values use role-specific
coordinator and engine knobs; Apple sets the cluster engine replica count to 0 because Apple engine
members are host-native. Pulsar-owned topics, `Shared` pool subscriptions, `Exclusive` pinned routes,
and acknowledgement handling are the ordering and ownership boundary for request handoff,
inference, and result publication. The worker dispatches through the selected engine binding,
fetches model weights lazily from `infernix-models`, and publishes the typed per-family result
surface; the selected `linux-gpu` plus `linux-cpu` real-output proof closed on 2026-06-20, while
unsupported adapter ids fail fast instead of falling through to a generic success path.

Phase 1's real-Apple-engine reopen (Sprint 1.15) and the paired `linux-cpu` full-suite gate closed
under Wave L on 2026-06-29 (rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`): Haskell style, Python
`check-code`, unit, web `71/71`, full integration with every real `linux-cpu` output plus the
HA/chaos tail, and routed Playwright `9/9`; Apple Stage 2 integration and focused routed Playwright
are green. The per-rebuild image-digest chronology for that cohort's local-topology, memory-profile,
drain-target, and MinIO input-timeout remediations is recorded in the Wave L row of
[cohort-validation-waves.md](cohort-validation-waves.md).
The worktree omits the
direct Harbor, MinIO, and Pulsar tool-route compatibility handlers, requires the real routed
upstream behavior in integration, and persists Linux cluster state before later rollout phases.
Bootstrap shells no longer restage the active substrate payload before lifecycle commands; that
preflight belongs to the binary command that needs the file. The Haskell style bootstrap
installs `ormolu` and `hlint` through `cabal install` against the project `ghc-9.12.4`
toolchain into `./.build/haskell-style-tools/bin/`; the Linux substrate image installs a single
`ghc-9.12.4` toolchain. The
supported Linux outer-container launcher reuses the image-local
`/opt/infernix/chart/charts/` archive cache,
hydrates the MinIO dependency through the supported direct tarball path instead of Docker
Hub-backed OCI metadata, and detects the known stale Pulsar or ZooKeeper epoch mismatch by
resetting only the retained Pulsar claim roots and retrying `cluster up` once. The Apple
clean-host bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables before
direct `cabal install`, reconciles Homebrew `protoc`, and lets Apple adapter setup or validation
paths reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command plus a
user-local Poetry bootstrap on demand. The supported doctrine now requires Docker-backed Apple
work to use an already selected native arm64 Docker daemon and forbids creating or switching
Docker contexts, creating Colima VMs, or using cross-architecture emulation; Phase 1 Sprint 1.12
replaced the previous Colima reconciliation path with selected Docker-context and
daemon-architecture validation and closed on the recorded validation with both the positive Apple lifecycle
gate and the negative no-daemon boundary gate. Phase 1 Sprint 1.14 closes the Apple Metal/Core ML
materialization lane under the Section Q single-accelerator rule: it removes the prior Sprint 1.13
`tart` / `hostTart` /
`AppleTart` implementation from the current host-tool schema and retargets the retained
`materialize-metal-engines` command to typed engine-artifact manifests. Phase 1 Sprint 1.15 builds
on that lane by replacing the former validation-wrapper payloads with real Apple native runner
roots for Core ML, MLX, llama.cpp/whisper.cpp Metal, CTranslate2, ONNX Runtime, and Audiveris,
plus indexed native snapshot hydration for Core ML Stable Diffusion. Phase 1 is fully closed by
Wave L: Apple Stage 2 integration/focused routed Playwright are green, and the paired
`linux-cpu` full gate passed on the real Linux host on 2026-06-29 with rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`.
The target has no Tart VM, user
keychain dependency, host Xcode UI flow, or request-time toolchain install. The
Poetry bootstrap may reuse an already available
compatible Python 3.12+ executable when one passes the implemented version check. Routed Apple
Playwright validation runs host-native `npm exec` against the published `127.0.0.1` edge port,
and the in-image
Playwright runtime no longer bakes a conflicting `NO_COLOR` default. The shared cluster lifecycle
now surfaces explicit in-progress phase, child-operation detail, and heartbeat data through
`cluster status` during monitored Docker build, Harbor publication, Harbor-backed final-image
preload, and Apple retained-state replay steps; explicit substrate materialization writes the
staged `infernix.dhall` atomically so concurrent status readers do not observe truncated
payloads; retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
replicas from the current Patroni leader when timeline drift leaves replicas unready after
promotion; and all lanes scrub operator-managed Patroni claim roots before recreating claim
directories and after retained-state sync so regenerated database credentials are not paired with
stale Harbor or Keycloak data directories. The shared lifecycle skips broad pre-Harbor support-image
preloads and follows the
stricter Harbor-first target where supported lanes hydrate and stream only the narrow Harbor
warmup dependency set into Kind before Helm warmup, only Harbor-required services may pull
upstream before Harbor is responsive, and every remaining image, including the active `infernix`
runtime image, is loaded into Harbor before final rollout. Legacy validation proof points are
kept only in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md); current
replacement proof points are recorded by the Wave A Apple cohort closure and the Wave C native
Linux/CUDA cohort closure below. Sprint 6.26 closes the buildx, npm, GHCup shell-profile,
Python packaging, and
Playwright script warning cleanup with the governed `linux-gpu` lifecycle rerun complete.
Sprint 6.27 closes the staged-substrate format cleanup: `infernix.dhall` is now a real
typed Dhall record decoded in-process by the `dhall` Haskell library, with the schema reflected from
the substrate decoder type (`infernix internal dhall-schema substrate`; Phase 8 removed the tracked schema file).

**Cohort validation status (present development host = CUDA Linux).** The current workspace is a
real Linux CUDA host. Consistent with the Section Q single-accelerator doctrine, the remaining
Phase 1 Wave L paired `linux-cpu` gate was validated here before moving to the next open phase:
`./bootstrap/linux-cpu.sh test` passed on 2026-06-29 with rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`, covering Haskell style,
Python `check-code`, Haskell unit, web `71/71`, full integration with all real `linux-cpu` catalog
outputs and the HA/chaos tail, and routed Playwright `9/9`. The Apple-side Sprint 1.15 evidence
remains the prior Apple host validation: `./bootstrap/apple-silicon.sh build`,
`./.build/infernix internal materialize-substrate apple-silicon`, `./.build/infernix internal
materialize-metal-engines`, installed Metal/Core ML/CTranslate2/MLX/ONNX/Audiveris smokes, direct
Core ML imports for Basic Pitch plus Apple's Stable Diffusion pipeline, `./.build/infernix test
unit`, `./.build/infernix test lint`, Apple integration, and focused routed Playwright. The first
Stage 2 retries on the Apple host exposed, and the current source remediates, the native arm64
llama.cpp/whisper.cpp payload-selection bug and the default 8 GiB Apple Docker-daemon rollout
pressure by generating a single-replica Apple host-native local topology for Harbor, Pulsar,
coordinator, and demo while preserving the Linux HA-shaped defaults. Later Apple reruns advanced
past rebuilt-image build, Harbor publication, final memory scheduling, and Pulsar startup under
the single-replica topology. They exposed, and the current source remediates, the matching
single-bookie Pulsar quorum gap plus a real TinyLlama GGUF execution-time regression: the lazy
model-cache bootstrap now hydrates the real payload, and the Apple llama.cpp runner now uses a
bounded single-turn invocation with explicit context/thread/GPU-layer settings. The latest rerun
cleared TinyLlama and then exposed the `llm-qwen15-mlx` cache path as an indexed native snapshot
rather than a single `payload`; the worker now treats that MLX model id as a native snapshot
cache. The next Apple rerun completed the LLM and speech rows through MLX, whisper.cpp, and
CTranslate2, then exposed two catalog/dependency corrections: Apple PyTorch/Diffusers/Transformers
framework venvs now pin Darwin arm64 torch-family wheels to PyPI instead of the CUDA source, and the
multi-instrument music-transcription rows now use MT3-PyTorch and MR-MT3 through `mt3-infer`.
Linux values keep the HA-shaped quorum. The
earlier Apple integration/e2e/all evidence still proves the host-daemon routing, Pulsar transport,
engine-pool behavior, production `demo_ui = false` route posture, and image rebuild/reuse path, but
it was recorded before Sprint 1.15 replaced the validation-wrapper payloads and therefore does not
close the Wave L real-output gate. The CUDA Linux Wave K cycle closed the selected Phase 4/6
real-output proof for the then-active catalogs: `./bootstrap/linux-gpu.sh test` passed style, unit,
web unit, integration, and routed Playwright with the then-current `linux-gpu` browser matrix, and
rebuilt-image `./bootstrap/linux-cpu.sh test` passed the matching CPU full-suite lane. The
post-replacement MT3 proof for the rows added on 2026-06-30 closed under Wave P on 2026-07-04.
The legacy dated proof points (the recorded validation) are inventoried in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical
Validation Evidence"; the underlying contracts they exercised still describe supported behavior,
but the proof points themselves are not current. Revalidation is tracked by
[cohort-validation-waves.md](cohort-validation-waves.md). [Wave A](cohort-validation-waves.md)
(Apple cohort) closed on the recorded validation with `cabal test infernix-integration` full PASS plus 5/6
Playwright e2e PASS; Waves A.1 and A.2 subsequently closed the routed
Playwright residuals with 7/7 e2e PASS, and Wave A.3 closed Apple engine-lock chaos.
[Wave H](cohort-validation-waves.md) then re-confirmed the full Apple cohort lifecycle on the
Apple cohort host on 2026-06-09 from a clean build root: the build, lint/style/unit gates, the
explicit `cluster up` → `cluster status` → `cluster down` lifecycle with retained-state replay,
`infernix test integration`, `infernix test e2e` 9/9, and aggregate `infernix test all`.
[Wave C](cohort-validation-waves.md) closed on the recorded validation on a native Linux/CUDA host: the
portable `linux-cpu` full-suite gate passed on the recorded validation and the real `linux-gpu`
full-suite gate passed on the recorded validation. [Wave F](cohort-validation-waves.md) closed on the recorded validation
with native `linux/arm64` `linux-cpu` validation through the selected Docker daemon
(`server=linux/arm64`, runtime probe `aarch64` / `arm64`) and a full
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all`
PASS.

The production and routed validation path uses real Pulsar transport. The repository still keeps
the repo-local topic spool under `./.data/runtime/pulsar/` as a deliberate harness surface when
unit-level checks or manually isolated daemon runs intentionally omit Pulsar endpoint
configuration; that harness does not count as routed cluster evidence and does not replace the
Gateway-backed Pulsar assertions in integration or E2E validation.

Beyond the Phase 9 admin overview (`/api/admin/overview`) and per-user personal dashboard, no
general observability stack (metrics, tracing, log aggregation) is deployed.
Monitoring is not a supported first-class surface.

## Execution Contexts and Substrates

The plan keeps these concepts separate:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Supported substrate | `apple-silicon`, `linux-cpu`, `linux-gpu` | which staged `infernix.dhall` payload the active build root carries |

### Naming Note

The canonical NVIDIA-backed Linux substrate id is `linux-gpu`, and the implementation plus docs
now use that id consistently.

## Hardware Cohort Validation Cadence

Development and validation are organized around two physical host cohorts:

- **Apple Silicon cohort:** `./bootstrap/apple-silicon.sh ...` and direct
  `./.build/infernix ...` commands.
- **CUDA Linux cohort:** `./bootstrap/linux-gpu.sh ...` and the Compose-launched
  `docker compose run --rm infernix infernix ...` command surface.

> **Implement in natural phase order on whichever single machine is present, and validate each phase
> on exactly one accelerator plus `linux-cpu` — never both accelerators.** Every open phase has two
> independent axes. *Code-side closure* (Axis 1) is the implementation plus the machine-independent
> gate set — `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
> `infernix lint files/docs/chart/proto`, `infernix docs check`, the web unit suite, and
> `poetry run check-code`; completed in natural order on one machine, it is the gate to begin the
> *next* phase's implementation. *Single-accelerator sign-off* (Axis 2) is the hardware-specific
> full-suite for the phase's one chosen accelerator (`apple-silicon` Metal/Core ML, or `linux-gpu`
> CUDA) plus `linux-cpu`, recorded in `cohort-validation-waves.md`; it is the gate for `Done` and
> never the gate for moving on. A phase never requires the other accelerator; cross-accelerator
> coverage is split across sibling phases or merged by a later `linux-cpu`-only aggregation phase.

Phase work should stay on the current cohort until a coherent slice is ready. Validation-only
hardware residuals are queued in [cohort-validation-waves.md](cohort-validation-waves.md), but a
phase closes only on its chosen accelerator plus `linux-cpu`, not by alternating between Apple and
CUDA after each sprint. `linux-cpu` remains a portable CPU-only lane for native Linux amd64 and
native Linux arm64 hosts, but it does not run through Apple Silicon emulation and does not replace
the CUDA Linux cohort when a phase explicitly chooses `linux-gpu` for GPU behavior, CUDA image
construction, `nvkind`, or NVIDIA scheduling.

## Managed-State-Transition Doctrine Reopen (2026-07-15)

The teardown race, the CoreML unconditional-`.ready` failure, and the three routed-Playwright "flakes"
(Keycloak admin-token expiry, artifact-not-visible, and the smollm2 warm-proxy timeout) are one class:
**unmanaged state transitions** — code acting on a state whose transition it never managed, on hope
rather than on typed evidence. The new
[managed state transitions doctrine](../documents/architecture/managed_state_transitions.md)
generalizes the results-side realness contract to state transitions: for every state there is typed
evidence that only the real transition can mint, required by every operation that acts on the state;
revocable states use rank-2 region leases and spend-once capabilities use surgical linear types; the raw
destructive, commit, and spawn primitives are unexported. This reopens every phase with one bounded
follow-on sprint, foundation-first so the forward-only DAG holds:

- **Phase 0 Sprint 0.13** — the doctrine document, its governance registration, and the `unsafeCoerce` /
  `unsafePerformIO` escape-token lint.
- **Phase 1 Sprint 1.16** — the foundation kernels `Infernix.Evidence.Readiness`,
  `Infernix.Evidence.Lease`, and `Infernix.Cluster.Subprocess` (`SubprocessEnv` / `CommandOutcome` /
  bounded, child-reaping `runBoundedCommand`); the opaque-newtype-via-export-list discipline.
- **Phase 2 Sprint 2.14** — the typed `ClusterLifecycle` machine with phase-resume, the fail-closed
  versioned persistence replacing `Show` / `Read`, and the lease-gated teardown (quiesce → scrub →
  delete).
- **Phase 3 Sprint 3.14** — the readiness kernel generalizing `HarborBootstrapOutcome`, and the
  subprocess-env seam.
- **Phase 4 Sprint 4.28** — evidence in the runtime and engines: `PayloadVerified` sentinel gating,
  `awaitModelBootstrapReady`, capability-gated commit and spawn, and native-runner `HOME` / `TMPDIR`.
- **Phase 5 Sprint 5.12** — the shared client contract that single-sources the bootstrap deadline, and
  the Playwright executor awaiting evidence rather than a proxy.
- **Phase 6 Sprint 6.39** — the capability-gating lint rules and the routed managed-transition coverage.
- **Phase 7 Sprint 7.29** — the `ClusterState` / `LifecycleProgress` field retirement, object-proxy
  bucket-evidence gating, and bootstrap `.ready` sentinel proof.
- **Phase 8 Sprint 8.7** — the warm-model-cache readiness-returns-evidence.
- **Phase 9 Sprint 9.10** — the admin-token lease and the object-storage session lease.

The superseded raw-hatch, stringly-state, and fail-open surfaces are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Active — Managed-State-Transition Doctrine reopen (Sprint 0.13, Planned); prior Done — reopened and re-closed (Sprints 0.1-0.12 done; Sprint 0.11 reconciled the governed docs — README matrix, `model_catalog`, `testing_strategy`, `python_policy`, realness doctrine — to the code-enforced realness invariant in lockstep with the Phase 4 catalog change, and Sprint 0.12 added the machine-independent realness lint enforcement (Python `check-code` AST + Haskell `realnessFabricationViolations`, scope extended per accelerator phase); validated 2026-06-23, machine-independent) | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Active — Managed-State-Transition Doctrine reopen (Sprint 1.16 code-side closed 2026-07-16, cohort gate pending); prior Done — reopened and re-closed (Sprints 1.1-1.14 remain closed for the scaffold/topology/materialization-lane foundation; Sprint 1.15 is closed for real Apple native runner materialization and native snapshot hydration. Apple Stage 2 integration plus focused routed Playwright are green, and the paired `linux-cpu` full gate closed on 2026-06-29 with rebuilt image `sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`: `./bootstrap/linux-cpu.sh test` passed style, Python `check-code`, unit, web `71/71`, full integration with all real `linux-cpu` model outputs plus the HA/chaos tail, and routed Playwright `9/9`.) | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Active — Managed-State-Transition Doctrine reopen (Sprint 2.14 in progress: fail-closed state decode landed 2026-07-16; ClusterLifecycle / versioned persistence / lease-teardown remain); prior Done (Sprints 2.10-2.13 lifecycle, retained-state, bootstrap-boundary, and host-manifest closure validated by Apple Wave A and CUDA Linux Wave C) | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Active — Managed-State-Transition Doctrine reopen (Sprint 3.14, Planned); prior Done — reopened and re-closed (Sprints 3.1-3.12 remain closed — Sprint 3.12 native `linux-cpu` architecture selector and native arm64 publication path closed in Wave F, Sprints 3.10-3.11 validated by Apple Wave A/A.2 and CUDA Linux Wave C; Sprint 3.13 de-exposes the `/minio/s3` external gateway route + `infernix-minio-s3` SecurityPolicy + `presignPublicEndpoint` so the webapp object-proxy is the sole external file-storage service. Sprint 3.13 is code-side closed and validated machine-independent on 2026-06-24, then cohort-closed by [Wave M](cohort-validation-waves.md) on 2026-06-29 with `linux-cpu` plus the selected `linux-gpu` full-suite gates.) | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Active — Managed-State-Transition Doctrine reopen (Sprint 4.28, Planned); prior Done — Sprint 4.27 is closed for typed runtime resource admission: pure `InferenceMemoryBudget` / `InferenceError` types replace the Apple-only integer budget, config-time over-budget fail-fast, hardcoded floor, and stringly failure payload. Runtime admission rejects only the oversized request with typed `ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }`; smaller configured models keep running. Wave T closed on 2026-07-12 with `linux-cpu` plus selected `linux-gpu` full-suite evidence. Earlier Sprints 4.22/4.25/4.26 remain closed by Waves P/R/S for their original scopes. | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Active — Managed-State-Transition Doctrine reopen (Sprint 5.12, Planned); prior Done — Sprint 5.11 is closed for typed `InferenceError` browser contracts and demo-app rendering of `ModelMemoryLimitExceeded` from explicit MiB fields, not parsed inline text. Wave T closed on 2026-07-12 with `linux-cpu` plus selected `linux-gpu` routed full-suite evidence. Sprints 5.1-5.10 remain closed for their original PureScript, generated-contract, and no-env scopes. | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Active — Managed-State-Transition Doctrine reopen (Sprint 6.39, Planned); prior Done — Sprint 6.38 is closed for typed resource-admission validation across Apple unified host RAM, Linux CPU pod memory, and Linux GPU VRAM. Unit/static coverage proves no config-wide startup failure for one oversized model, enforced zero budget behavior on Apple over-pledge, constructor-based `ModelMemoryLimitExceeded` classification, and substrate budget-source selection; Wave T closed on 2026-07-12 with `linux-cpu` plus selected `linux-gpu` full live integration/e2e evidence. Earlier Sprints 6.35/6.36/6.37 remain closed by Waves P/R/S for their original scopes. | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |
| 7 | Demo App Multi-User Durable Context | Active — Managed-State-Transition Doctrine reopen (Sprint 7.29, Planned); prior Done — Sprint 7.28 closed generated artifact object ownership and result-bridge authorization on 2026-06-30 with full selected `linux-gpu` plus `linux-cpu` cohort validation. Prior durable-context, engine-pool, object-proxy, Files view, in-browser rendering, and Wave M closure evidence remains recorded for Sprints 7.1-7.27. Desired-state hot reload remains future work. | [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) |
| 8 | Zero-Tracked-Dhall Config and Eager Model Cache | Active — Managed-State-Transition Doctrine reopen (Sprint 8.7, Planned); prior Done — all sprints (8.1-8.6) closed. Zero-tracked `.dhall`; `infernix init` / `test init` explicit creation with shared defaults; fail-fast no-auto-generate backstops; binary-generated ConfigMap/Secret bodies with the chart as string embedder; coordinator eager model-cache staging (+ `--empty-models` image bake); test-harness config lifecycle. Cohort gate closed 2026-07-04 (Wave P): `linux-gpu` + `linux-cpu` full-suite `infernix test all` both GREEN, routed Playwright **9/9**. One documented non-blocking residual: the `warm-model-cache` barrier's host-side MinIO poll observability. | [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) |
| 9 | Access Control and Monitoring | Active — Managed-State-Transition Doctrine reopen (Sprint 9.10, Planned); prior Done — the original 8 RBAC/STS/dashboard sprints are code-side closed and Wave Q validated on both `apple-silicon` and `linux-cpu` (2026-07-07). Sprint 9.9 closes the UAT auth residual from `notes.txt`: Sign out previously cleared only local SPA tokens and left the Keycloak SSO browser session alive, so switching from a self-registered user to the separate hardcoded admin login could silently reuse the non-admin session. The SPA now performs Keycloak OIDC logout with `id_token_hint`, `client_id`, and `post_logout_redirect_uri`, and the routed Playwright spec has a user-to-admin switching regression. Wave U closed on 2026-07-12 with `linux-cpu` plus selected `linux-gpu` routed evidence. The implemented surface includes admin/user RBAC (Keycloak `infernix-admin` realm role + JWT `realm_access.roles` claim + hardcoded demo admin), edge admin `SecurityPolicy` over all four operator routes + ungated-route closure, backend admin gate on `GET /api/cache` + `/api/cache/{evict,rebuild}` + `GET /api/admin/overview`, admin cluster-wide monitoring panel + per-user personal dashboard, the Kind data-plane + edge loopback invariant, per-user MinIO STS defense-in-depth, and real Keycloak logout for account switching. | [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md) |

> **Note**: Phase statuses describe current repository state. Earlier governed phases may remain
> `Active` or `Blocked` for named follow-ons while later phases can be `Done` when their owned work
> and validation are complete. Validation-only hardware blockers are scheduled through
> [cohort-validation-waves.md](cohort-validation-waves.md) instead of forcing repeated machine
> switches during unrelated same-cohort work.
> Each phase 1-7 gained a cleanup sprint that eliminates the env-var fallbacks and
> PATH-resolved external commands the phase originally introduced. See
> [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)
> for the doctrine, and the per-phase sprint sections for the specific retirement scope.

## Canonical Outcome

The supported platform now closes around these rules:

- one repo-owned Haskell executable, `infernix`, links the default Cabal library exposed by the
  `infernix` package (declared in `infernix.cabal` without an explicit library name and depended on
  as `infernix`); it owns the production daemon, cluster lifecycle, validation, internal helpers, and
  the routed demo HTTP host (served by the long-running `Webapp` role selected through typed Dhall
  and `infernix service --role webapp`)
- one Haskell command registry owns parsing, help text, and the
  canonical CLI reference, but it no longer exposes `--runtime-mode` or any equivalent substrate
  override
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from the staged `infernix.dhall` file beside the active
  build root, and that staged payload is the primary source of truth for substrate identity,
  generated catalog content, daemon role, inference placement, Pulsar topics, and test scope
- Apple host-native lifecycle and validation commands materialize or verify
  `./.build/infernix.dhall`; the explicit helper
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
  remains available for direct restaging or inspection
- Linux outer-container lifecycle and validation commands materialize or verify
  `/workspace/.build/outer-container/build/infernix.dhall` inside the launcher image;
  the explicit helper
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  remains available for direct restaging or inspection
- the Linux substrate Dockerfile materializes a build-arg-selected copy inside the image overlay,
  and the supported outer-container command surface keeps that copy image-local before doing
  substrate-aware work
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints fail fast with a "run `infernix init`" reminder when
  their `infernix.dhall` is missing (Phase 8; no auto-materialize backstop); focused
  `infernix lint ...` and `infernix docs check` remain substrate-file independent
- the runtime substrate file is a typed Dhall record at `infernix.dhall`, created by `infernix init`
  (or the test harness) and decoded in-process by the `dhall` Haskell library; the schema is
  reflected from the substrate decoder type — no `.dhall` is version-controlled
- Apple host-native operation is the only supported host build path outside a container
- on Apple Silicon, the host-built `./.build/infernix` binary manages Kind, deploys the mandatory
  cluster support services, the cluster coordinator Deployment, and optional routed demo workload,
  and owns the host-side same-binary engine daemon lane
- on Apple Silicon, the cluster coordinator is canonical for Pulsar ingress and derived pool-topic
  handoff, while host engine daemons are canonical for Apple-native inference execution and result
  publication; both roles consume `.dhall` role config from the same binary family
- when the demo UI is enabled on Apple Silicon, the routed demo surface stays cluster-resident and
  manual inference flows through the cluster daemon's batching path before Apple inference batches
  move through Pulsar to host daemons
- on Apple Silicon, Compose is not a user-facing launcher for ordinary CLI work; host-native routed
  E2E now uses host `npm exec` Playwright fed by the same typed fixture against the published
  localhost edge port and is covered by Apple cohort validation batches. Linux substrates run
  Playwright in-container inside the substrate image via
  `npm --prefix web exec -- playwright test ...`
- on Linux substrates, all supported CLI commands run through
  `docker compose run --rm infernix infernix ...`; there is no supported Linux host-native build or
  CLI surface outside the outer container
- `linux-cpu` is the only substrate that remains meaningfully portable across unrelated native
  Linux host hardware; native amd64 Linux and native arm64 Linux are the supported validation
  shapes, while Apple Silicon emulation is not a supported build or validation lane
- `linux-gpu` assumes an amd64 Linux environment paired with a CUDA-capable device, but the outer
  control-plane container itself does not require the NVIDIA runtime
- for `linux-gpu`, the outer control-plane image is still built from the CUDA base image, and that
  same built image is the artifact pushed to Harbor and deployed as the cluster daemon
- the staged substrate file lives under the active build root:
  `./.build/infernix.dhall` on Apple and
  `/workspace/.build/outer-container/build/infernix.dhall` inside the Linux launcher
  image; cluster deployment republishes that payload
  through `ConfigMap/infernix-demo-config` whenever the active topology has cluster-resident
  consumers and mounts the same filename inside those workloads at `/opt/build/infernix-substrate.dhall`
- each daemon reads its staged substrate `.dhall` at startup; automatic file-watching or reload is
  not part of the supported contract
- the supported materialization path can emit `demo_ui = false` with
  `--demo-ui false`; omitting that flag keeps the default demo-enabled output
- the routed demo app remains cluster-resident when enabled, and the Apple routed path closes
  around an explicit cluster-daemon-to-host-daemon inference batch bridge rather than
  cluster-resident Apple inference execution
- supported entrypoints no longer carry the old cross-substrate default matrix, cluster bring-up
  fallbacks, direct tool-route compatibility handlers, or generic inference-success fallback;
  routed Harbor, MinIO, and Pulsar checks require the real Gateway-backed upstream behavior, while
  inference coverage goes through the typed adapter harness selected by the active substrate file.
  The repo-local Pulsar topic spool remains only a harness-oriented path for endpoint-absent unit
  or isolated daemon checks, not a substitute for routed cluster validation
- integration coverage is driven by the comprehensive model, format, and engine matrix in
  `README.md`: one substrate-aware integration suite reads the active substrate from `.dhall`,
  chooses the corresponding engine binding for each supported row or reference, and runs at least
  one assertion for every such row
- Playwright E2E remains substrate-agnostic at the browser layer and relies on `infernix-demo` to
  read the same `.dhall` and dispatch the correct engine for the active substrate
- Harbor-first bootstrap, mandatory local HA platform services, Gateway-owned routing, operator-run
  Patroni PostgreSQL, manual `infernix-manual` storage, Haskell-owned frontend contracts, the
  shared Python adapter project, and untracked generated outputs all remain mandatory doctrine
- supported validation is substrate-specific: integration, E2E, and `test all` run their complete
  supported suites against the built and deployed substrate, and test reports name that substrate
  explicitly instead of implying matrix-wide coverage
- the supported control plane keeps one Haskell command registry,
  binary-owned lifecycle and validation orchestration, the current `ormolu` plus `hlint` plus
  `cabal format` style stack, and the existing files or docs or chart or proto validation
  entrypoints; shell bootstrap responsibility is limited to prerequisite and launcher setup
- every `infernix service` daemon remains startup-configured and Pulsar-driven without a separate
  admin-HTTP, hot-reload, or typed-event-ledger subsystem in the supported contract
- the test surface remains the current three Cabal stanzas plus the frontend unit suite:
  `infernix-unit`, `infernix-integration`, and `infernix-haskell-style`, exercised through the
  supported `infernix test lint|unit|integration|e2e|all` command surface

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes the governed docs suite and plan-maintenance rules the remaining phases rely on |
| 1 | 0 | closes the repository scaffold, the staged-substrate contract, the one-binary role model, and the governed root-document posture |
| 2 | 0-1 | builds Kind lifecycle, manual storage, Harbor-first image flow, and Linux launcher behavior on top of the repository foundations |
| 3 | 0-2 | adds the HA platform services, routed edge, and publication contract on top of the cluster lifecycle and storage baseline |
| 4 | 0-3 | closes the runtime, adapter boundary, object-store contract, and Apple host-daemon bridge on top of the HA platform surfaces |
| 5 | 0-4 | adds the clustered demo UI, generated frontend contracts, and routed browser validation on top of the runtime and publication contract |
| 6 | 0-5 | validates the whole supported surface end to end and hardens the governed docs, routes, and lifecycle behavior around that implementation |
| 7 | 0-6 | adds the multi-user durable-context demo application on top of the platform: Keycloak self-signup, WebSocket post-login transport, Pulsar-backed conversation log per context, MinIO-backed artifact upload/download/render-or-download, a Haskell-first logic boundary surfaced to PureScript via `purescript-bridge`, and the supported three-role daemon split (stateless Webapp role in the `infernix-demo` workload, stateless `infernix-coordinator`, substrate-specific engine pools). The platform contract Phase 7 builds on is implemented in code; Apple plus native Linux/CUDA real-cluster validation evidence is recorded in Waves A-C, Sprint 7.8 runtime KV-cache plus `Infernix.Runtime.Daemon` closure is recorded in Wave E, Sprint 7.24 pool assignment and broker-native backpressure closed in Wave J, Sprints 7.25-7.27 object-proxy / Files / in-browser rendering closed in Wave M, and Sprint 7.28 generated artifact ownership closed in Wave N. |
| 8 | 0-7 | adopts the hostbootstrap Dhall doctrine on top of the whole platform: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (including ConfigMap/Secret bodies), explicit `init` / `test init` creation with ordinary commands failing fast when config is missing, the Apple bootstrap `up` wrapper explicitly running `init --if-missing`, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging (replacing the lazy per-inference bootstrap) driven by the mounted `infernix.dhall`. |
| 9 | 0-8 | adds the role-based access-control and monitoring surface on top of the whole demo platform: the Keycloak `infernix-admin` realm role + JWT `realm_access.roles` claim, the edge admin `SecurityPolicy` (a valid JWT is necessary but not sufficient for cluster-wide surfaces) plus ungated-route closure, the backend admin gate + admin cluster-wide monitoring panel, the per-user personal dashboard, per-user MinIO STS defense-in-depth, and the enforced Apple host-worker loopback data-plane invariant. Every dependency edge references an equal-or-lower-numbered phase, so the forward-only DAG holds. |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
