# Phase 8: Zero-Tracked-Dhall Config and Eager Model Cache

**Status**: Active — Sprints 8.11 and 8.12 both closed on 2026-08-18. 8.12 dissolved the last
blocker a single engine machine could not reach rather than waiting it out: the fleet validation
topology is a `linux-cpu` multi-worker Kind cluster the lifecycle generates from the system
contract's own machine count, not a second physical host, and it closed on a live two-machine fleet
plus the paired single-machine run. Three sprints remain open — 8.9, 8.10, and 8.13 — all code-side
closed, all consuming Phase 6 Sprint 6.44's `linux-gpu` plus `linux-cpu` wave rather than a wave of
their own. Sprint 8.13 was **found by executing that wave**: the shared engine Deployment carried no
`--engine-name`, which is invisible on `linux-cpu` (one declared member resolves with no selection)
and refuses by name on `linux-gpu` (four declared members, one per framework engine image plus
`native`). Sprint 8.12's fail-closed identity was working; the shared Deployment simply never
declared one.

**Historical implementation state (superseded by the header above).** Active. Sprint 8.9 and Sprint 8.10 are both
validation-only, sharing the `linux-gpu` plus `linux-cpu` rebuild. Sprint 8.10 (delete the derivable
wire fields) is code-side closed: Phase 4 Sprint 4.34's admission move discharged its blocker, and
the reflected substrate schema went from 110 lines to 54 with every retired field absent rather than
merely rejected. Executing 8.10 established
that the machine contract it specifies — "the existing host manifest plus a `node` block" — has no
home on the Linux lanes, where a pod's only host manifest is the one baked identically into every
image, and where nothing yet makes two machines different members. That finding stands, and Sprint
8.12 is where it is discharged: the fleet's pods no longer read the baked manifest at all. Treating
it as a blocker on 8.11 had made that sprint depend on demonstrating something Phase 3 Sprint 3.16's
single-node platform decision makes undemonstrable — the plan contradicting itself rather than a real
design gap. The two
topologies are now separated: 3.16 governs what the platform deploys, a fleet lane is a validation
topology, and the work that genuinely needs more than one engine machine is Sprint 8.12. Sprint 8.9
(proper-union generated execution-plan schema migration) is code-side closed:
the budget wire carries the third `DualEnforced` union arm Phase 6 Sprint 6.44's dual RAM/VRAM
capability needed, the renderer emits one shared union type whose agreement with the reflected
decoder is asserted, a retired flat payload fails with a targeted migration diagnostic naming the
regenerating command, and the dead `legacyDhall` decoder residue is removed. Its behavioral evidence
is consumed from the Phase 6 Sprint 6.44 `linux-gpu` plus `linux-cpu` wave rather than a wave of its
own, per its own validation rule. Sprints 8.1–8.8 are closed.

**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Adopt the `~/hostbootstrap` Dhall doctrine — no version-controlled `.dhall`, the
> binary as the sole generator of every `.dhall` (including ConfigMap/Secret bodies), explicit
> `init` / `test init` creation, ordinary commands failing fast when config is missing, Apple
> bootstrap `up` explicitly running `init --if-missing`, and a test harness that generates the
> runtime config, runs, and deletes it — and replace the lazy per-inference model bootstrap with eager
> coordinator model-cache staging driven by the mounted `infernix.dhall`.

## Phase Status

> Phase 8 reconciles the configuration substrate to the doctrine in
> [configuration_doctrine.md](../documents/architecture/configuration_doctrine.md). It supersedes the
> earlier "checked-in decoder-reflected `dhall/Infernix*.dhall` schema files + `lint docs` file-drift
> check" mechanism (Phase 4 Sprint 4.13 follow-ons) and the Helm-rendered cluster-config ConfigMap
> (Phase 4), and it retires the **per-inference trigger** for the lazy model-bootstrap workflow in
> favour of eager startup staging. `src/Infernix/Bootstrap/Models.hs` and the
> `model.bootstrap.request` topic family are **retained** as the on-demand fallback — the coordinator
> still forks `runModelBootstrapLoop` at startup (`src/Infernix/Runtime/Daemon.hs`); only the lazy
> per-request trigger is retired (Sprint 8.5). The retired trigger is recorded in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Sprint 8.1: Zero Version-Controlled Dhall [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `docker/Dockerfile`, `src/Infernix/Lint/Docs.hs`, `test/unit/Spec.hs`, `src/Infernix/DhallSchema.hs`, `src/Infernix/DhallSchema/Reflection.hs`
**Docs to update**: `documents/architecture/configuration_doctrine.md`, `documents/engineering/host_tools_manifest.md`, `documents/engineering/cluster_config_manifest.md`

### Objective

Delete every version-controlled `.dhall` and prove the schema lives only in the Haskell decoder
types, reflected on demand.

### Deliverables

- the four `dhall/Infernix{Host,Cluster,Secrets,Substrate}.dhall` files and the `dhall/` directory are
  removed, along with their `infernix.cabal` `extra-source-files` entries and the `COPY dhall`
  Dockerfile step
- `validateDhallSchemaDrift` no longer reads any on-disk `.dhall`; it asserts each schema reflects to
  a non-empty expression, and the unit suite round-trips a default value of each config through
  encode → decode
- `infernix internal dhall-schema host|cluster|secrets|substrate` remains the only way to obtain a
  schema; nothing reads a schema from disk

**The retry bound did not mean what it said, and the fleet lane is what showed it.** The window was
first written as 30 attempts with a 2 s pause — nominally a minute. On the live lane the broker took
roughly fifteen seconds to answer each refused subscribe, so the real window was over eight minutes:
a bound whose length was set by broker latency rather than by the number it was documented with. It
is now a measured wall-clock deadline, because the thing it is sized against — the broker's session
timeout — is itself wall-clock. Nothing about the mechanism changed; what changed is that the number
in the doctrine is now the number the code enforces.

### Validation

- `git ls-files '*.dhall'` is empty
- `cabal build all`, `infernix test unit`, `infernix test lint`, `infernix lint docs`, `infernix docs check` pass

### Remaining Work

None.

## Sprint 8.2: `init` / `test init` Commands and Shared Defaults [Done]

**Status**: Done
**Implementation**: `src/Infernix/ProjectInit.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`

### Objective

Make config creation explicit and DRY: one defaults owner shared by `init` and the test harness.

### Deliverables

- `Infernix.ProjectInit` (`runProjectInit`, `runTestInit`) owns the explicit-creation entrypoints
  and shares the single defaults owner in `Infernix.DemoConfig`
  (`renderGeneratedDemoConfig`/`materializeGeneratedDemoConfigFile` for the substrate,
  `materializeHostManifestFile` for the host manifest, `materializeHostSecrets` for host worker
  secrets) plus the one atomic `writeProjectConfigFile`
- top-level `infernix init [--runtime-mode M] [--demo-ui B] [--force] [--if-missing]` writes the
  runtime `./infernix.dhall` (substrate), host manifest `./infernix-host.dhall`, and host worker
  secrets under `./.data/runtime/secrets/`; it fails fast if `./infernix.dhall` exists unless
  `--force` (and `--if-missing` makes an existing config a no-op)
- top-level `infernix test init` writes the thin `./infernix.test.dhall` and needs no pre-existing config
- `Config.hs` exposes `runtimeConfigPath` (`./infernix.dhall`) and `testConfigPath`
  (`./infernix.test.dhall`); existing readers follow the relocated path
- `./bootstrap/apple-silicon.sh up` is a stage-0 convenience wrapper over the explicit init surface:
  it runs `./.build/infernix init --if-missing` before `cluster up`; `infernix cluster up` itself
  still fails fast when config is missing

### Validation

- `infernix init` then `infernix test init` produce the config files; `docs check` sees the new
  command-registry entries; `infernix test unit` covers the registry/help assertions

### Remaining Work

None.

## Sprint 8.3: Fail-Fast, No Auto-Generate Backstops [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs` (`discoverCliCommandPaths`), `src/Infernix/DemoConfig.hs` (`materializeHostManifestFile`, `materializeHostSecrets`; `ensureGeneratedDemoConfigFile` deleted), `src/Infernix/Runtime/Worker.hs` (`loadHostWorkerSecrets`), `src/Infernix/Cluster.hs` (`requireGeneratedDemoConfigFile`, `discoverClusterCommandPaths`)
**Docs to update**: `documents/architecture/configuration_doctrine.md`, `documents/development/local_dev.md`

### Objective

Remove hidden auto-generate-if-absent paths so a missing config is a loud, actionable error unless
the operator enters through the Apple bootstrap wrapper, which explicitly invokes
`infernix init --if-missing`.

### Deliverables

- `discoverCliCommandPaths` and `discoverClusterCommandPaths` fail fast (naming `infernix init`)
  instead of auto-materializing the host manifest; `ensureGeneratedDemoConfigFile` is deleted;
  `requireGeneratedDemoConfigFile` fails fast naming `infernix init`/`infernix test init`;
  `materializeHostManifestFile` loses its early-return backstop and is now an unconditional writer;
  the former lazy `ensureHostWorkerSecrets`/`writeFileIfMissing` in the worker is replaced by
  `loadHostWorkerSecrets`, which fails fast, with creation moved to `infernix init`
  (`materializeHostSecrets`)
- every binary/test command that needs a config names the exact init to run when it is absent

### Validation

- deleting `./infernix.dhall` then a config-dependent command fails fast with the init reminder;
  `infernix test unit` passes (host-secret unit fixture materializes via `materializeHostSecrets`)

### Remaining Work

None.

## Sprint 8.4: Binary-Generated ConfigMap + Secret Bodies [Done]

**Status**: Done
**Code-side closure**: `cabal build all`, `infernix test unit` (`defaultClusterConfig` decode + `renderHelmValues` body/manifest assertions), `infernix test lint`/`lint chart`/`lint files`/`lint docs`/`lint proto`, `docs check` all pass (machine-independent).
**Cohort gate**: the in-pod decode of the binary-rendered `cluster.dhall` / `InfernixSecrets.dhall` is covered by the `linux-cpu` plus `linux-gpu` full-suite that closes Phase 8, under [cohort-validation-waves.md](cohort-validation-waves.md) Wave P.
**Implementation**: `src/Infernix/ClusterConfig.hs` (`defaultClusterConfig` + default wirings), `src/Infernix/Cluster.hs` (`renderHelmValues` `clusterConfig.body` / `clusterSecrets.manifest`, `resolvedKeycloakWiring`), `chart/templates/configmap-cluster-config.yaml`, `chart/templates/secret-cluster-secrets.yaml`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: `documents/engineering/cluster_config_manifest.md`, `documents/architecture/configuration_doctrine.md`

### Objective

Move all remaining Dhall generation out of Helm into the binary; Helm becomes a string embedder.

### Deliverables

- `defaultClusterConfig` (with `defaultPulsarWiring`/`defaultMinioWiring`/`defaultKeycloakWiring`/
  `defaultDemoBackendWiring`/`defaultEngineWiring`) carries the wiring values formerly interpolated
  from the `chart/values.yaml` `clusterConfig`/`service` blocks; `renderHelmValues` renders the
  `cluster.dhall` body (via `renderClusterConfig`) and the `InfernixSecrets.dhall` manifest as strings
  under `clusterConfig.body` / `clusterSecrets.manifest`. The keycloak wiring resolves to the routed
  edge base URL when the demo UI is enabled (replacing the former `finalChartOverrides`
  `clusterConfig.keycloak` block)
- `configmap-cluster-config.yaml` embeds only `{{ .Values.clusterConfig.body | nindent 4 }}`, and
  `secret-cluster-secrets.yaml` embeds `{{ .Values.clusterSecrets.manifest | nindent 4 }}` for the
  Dhall manifest (the JSON credential files stay template-rendered from the MinIO/Keycloak wiring
  values — they are not `let`/schema Dhall) — no `let …`/schema Dhall inside any chart template
- `renderHelmValues` also emits `clusterConfig.keycloak.{baseUrl,clientId,jwksUrl}` (from the same
  resolved wiring) alongside `body`, because the operator-routes SecurityPolicy template reads those
  Helm **values** (not the rendered body) to build its JWT `issuer` + `remoteJWKS`; the wiring resolves
  to the routed edge base URL so the SecurityPolicy issuer matches the operator token, guarded by the
  unit suite (`clusterConfig.keycloak.baseUrl` is the routed edge URL) and cohort-proven under
  [cohort-validation-waves.md](cohort-validation-waves.md) Wave P
- `infernix lint chart` rejects any Dhall `let`/`in {`/schema body inside a chart template
  (`dhallBodyRejectionPaths` + `isDhallBodyLine`)

### Validation

- `infernix lint chart` passes and rejects re-introduced `let` bodies; `infernix test unit` decodes
  the binary-rendered default cluster manifest and asserts the `renderHelmValues` body/manifest blocks;
  in-pod decode is proven by the Phase 8 cohort full-suite

### Remaining Work

None.

## Sprint 8.5: Coordinator Eager Model-Cache Staging [Done]

**Status**: Done — cohort gate closed under [cohort-validation-waves.md](cohort-validation-waves.md) Wave P. The `linux-gpu` and `linux-cpu` full-suite `infernix test all` both passed with routed Playwright **9/9**, including the browser per-model smoke matrix exercising every catalog model — the 27 GB `video-wan21-t2v` row that previously timed out cold completes because the coordinator's eager sweep begins staging at cluster-up.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs` (`sweepEagerModelCache`, `waitForEagerModelCacheReady`), `src/Infernix/Runtime/Daemon.hs` (`startCoordinatorLoops`), `src/Infernix/Cluster.hs` (`warmModelCache` + `warm-model-cache` lifecycle phase, `resolveWarmModelCacheMinioHost` via `kindControlPlaneIpv4`), `src/Infernix/DemoConfig.hs` (`materializeEmptyModelsDemoConfigFile`), `src/Infernix/CommandRegistry.hs` (`--empty-models`), `src/Infernix/Models.hs` (demo-only-generator doc), `docker/Dockerfile`
**Docs to update**: `documents/engineering/model_lifecycle.md`, `documents/architecture/daemon_topology.md`

> **Barrier scope.** The coordinator's forked eager sweep is the mechanism that delivers the outcome;
> the `warm-model-cache` `cluster up` barrier is a best-effort wrapper over it, and the eager sweep
> plus the lazy fallback guarantee correctness on their own. Making that barrier's host-side MinIO
> poll actually observe the `.ready` sentinels is owned by Sprint 8.7 (typed readiness evidence) and
> Sprint 8.8 (tri-state observation), not by this sprint.

> **Apple-silicon cohort note.** This sprint's cohort gate was Wave P (`linux-gpu` + `linux-cpu`)
> only; no apple-silicon full-suite ran for Phase 8. The eager-stage-**all** behavior is still a disk
> staging contract, not a memory-admission contract. The later resource-admission doctrine is owned
> by Phase 4 Sprint 4.27, Phase 5 Sprint 5.11, and Phase 6 Sprint 6.38; this phase reopens only if
> that work changes eager disk staging or the `warm-model-cache` barrier.

### Objective

Replace the lazy per-inference model bootstrap with eager staging driven by the mounted config, so no
inference races a cold cache.

### Deliverables

- the coordinator eagerly stages every model listed in the mounted `infernix.dhall` on startup via
  `sweepEagerModelCache` (forked in `startCoordinatorLoops`), reusing the idempotent
  download/upload/`.ready` logic (`processBootstrapRequest`, which short-circuits on an existing
  sentinel). The config is required upstream (`decodeDemoConfigFile` fails fast when absent)
- the eager coordinator sweep stages the mounted model set at startup; a `warm-model-cache` `cluster
  up` lifecycle phase (`warmModelCache` → `waitForEagerModelCacheReady`) wraps a best-effort host-side
  MinIO poll of the `.ready` sentinels at the host-reachable node-port endpoint per control-plane
  context. The barrier warns and proceeds rather than truly blocking; the eager sweep stages the
  weights regardless, and making the poll observe the sentinels is Sprint 8.7 and Sprint 8.8 work
- the model set is the mounted `infernix.dhall` (the source of truth); `src/Infernix/Models.hs`
  `matrixRows`/`catalogForMode` is documented as a **demo-only** generator of that list, not a core
  dependency
- the image-baked `infernix.dhall` lists no models: the Dockerfile bakes with
  `internal materialize-substrate … --empty-models` (`materializeEmptyModelsDemoConfigFile`), so
  `docker run --rm` never stages weights; the ConfigMap-mounted config (regenerated by `cluster up`
  via `renderGeneratedDemoConfigPayload`) is the source of truth at deploy
- the lazy `runModelBootstrapLoop` engine bootstrap remains only as the on-demand fallback

### Validation

- code-side: `infernix test unit` (registry `--empty-models` parse, empty-vs-full model rendering),
  `infernix lint chart`, `cabal build all`
- cohort (closed under [Wave P](cohort-validation-waves.md)): the `linux-gpu` **and** `linux-cpu`
  full-suite `infernix test all` both passed with routed Playwright **9/9**; the per-model browser
  matrix exercises every catalog model and the 27 GB `video-wan21-t2v` row completes because the
  eager sweep starts staging at cluster-up

### Remaining Work

None.

## Sprint 8.6: Test-Harness Config Lifecycle [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs` (`withTestHarnessConfig` + `restoreRuntimeConfig`, `test` dispatch for integration/e2e/all), `docker/Dockerfile` (bakes `./infernix.test.dhall` via `infernix test init`), `test/integration/Spec.hs` (`materializeGeneratedSubstrate` rewrites the harness-owned path), `test/unit/Spec.hs` (outer-preflight fixture isolation)
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/local_dev.md`

### Objective

Make the test harness own the runtime config for the duration of a run.

### Deliverables

- `infernix test integration|e2e|all` wraps the suites in `withTestHarnessConfig`, which reads
  `./infernix.test.dhall` (fail fast → `infernix test init`), **takes ownership** of `./infernix.dhall`
  by moving any existing config (an operator `infernix init` config, or the image-baked empty-models
  config) to a `.harness-backup`, generates `./infernix.dhall` from the test config's substrate +
  demo-ui selection, runs the suites, and then **restores the backup** (or removes the generated file
  when there was none) via `restoreRuntimeConfig`. Own-and-restore (rather than a hard refuse) is what
  lets the supported container `infernix test all` run against an image that must bake `./infernix.dhall`
  for the `cluster up` path, while still protecting an operator's host config.
- the Linux launcher image bakes both `./infernix.dhall` (empty-models, via `internal
  materialize-substrate --empty-models`) and `./infernix.test.dhall` (via `infernix test init`) at
  docker-build time, so the single `docker compose run --rm infernix infernix test all` invocation
  finds the test config (a separate `test init` invocation cannot persist across `--rm` containers)
- the integration suite's per-variant `internal materialize-substrate` (`materializeGeneratedSubstrate`)
  keeps rewriting the same harness-owned `./infernix.dhall` path during the run

### Validation

- code-side: `infernix test unit` passes with the outer-container preflight fixture isolated to a
  sandbox repo root (so a real `infernix init` `./infernix.dhall` no longer collides with the
  "missing staged substrate file" assertion); `cabal build all`, `infernix-haskell-style`
- behavioral: without `./infernix.test.dhall`, `infernix test all` names `infernix test init`; a run
  backs up any pre-existing `./infernix.dhall`, generates the harness config, and restores the backup
  afterward (exercised by the cohort full-suite through the launcher image)

### Remaining Work

None (code-side); exercised end-to-end by the Phase 8 cohort full-suite.

## Sprint 8.7: Warm-Model-Cache Readiness Evidence [Done]

**Status**: Done — the warm-model-cache barrier returns typed readiness evidence and the config-side
state files persist fail-closed; code-side closure (machine-independent gates) plus the
single-accelerator (apple-silicon) plus linux-cpu full-suite sign-off closed under
[Wave V](cohort-validation-waves.md).
**Code-side closure**: closed — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit` (typed warm-cache outcome consumption and the port-file fail-closed
assertions pass), `cabal test infernix-haskell-style`, and `infernix lint docs` all pass on the
apple-silicon lane. No native/Python change, so `poetry run check-code` does not apply.
**Cohort gate**: closed under [Wave V](cohort-validation-waves.md) — apple-silicon plus linux-cpu full-suite `test all` clean.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Cluster.hs`
**Blocked by**: Sprint 3.14
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: make the
warm-model-cache barrier return typed readiness evidence — generalizing the existing progress-based
wait so the readiness wait yields evidence rather than a bare success — and adopt the fail-closed
versioned persistence on the config-side state files, encoding evidence, not hope. It applies the
doctrine in
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
to this phase's `warm-model-cache` barrier and config-side persisted state.

### Deliverables

- the `warm-model-cache` barrier's readiness wait in `src/Infernix/Runtime/Pulsar.hs`
  (`waitForEagerModelCacheReady`) returns a typed `WarmModelCacheOutcome` rather than a bare boolean:
  `WarmModelCacheAllStaged` carries an opaque `WarmModelCacheReady` witness minted only when every
  configured model's `.ready` sentinel was observed, and `WarmModelCacheStillPending` carries the
  still-unstaged ids, generalizing the previous bare pending list
- `src/Infernix/Cluster.hs` (`runWarmModelCacheBarrier`) consumes that typed evidence at the
  `warm-model-cache` lifecycle phase: the "all staged" declaration is gated on the
  `WarmModelCacheAllStaged` witness, and a pending outcome logs the non-blocking warning
- the config-side state files adopt fail-closed versioned persistence — an unknown or unversioned
  on-disk state fails closed rather than being silently reinterpreted. `readPortFileMaybe`
  (`src/Infernix/Storage.hs`) treats absent/blank as `Nothing` but a present-but-undecodable file as
  a loud error rather than a silent `Nothing` that would re-choose a port; the authoritative
  config-side cluster-state file uses the Sprint 2.14 fail-closed versioned aeson codec

### Validation

- code-side gates exercised on both the apple-silicon and linux-cpu lanes: `cabal build all`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint docs`, and (for any
  native/Python change) `poetry run check-code`
- the readiness wait is asserted to surface typed evidence, and the versioned persistence is asserted
  to fail closed on an unknown version

### Remaining Work

None.

---

## Sprint 8.8: Fault-vs-Absence in the Warm-Model-Cache Barrier [Done]

**Status**: Done — the warm-model-cache observation surface is three-valued end to end (Haskell
sentinel probe + Python cache revalidation), so a transport fault can no longer masquerade as a
definitive absence and stall the retained-second-`cluster up` barrier; code-side closed on the
machine-independent gate set, and the single-accelerator (apple-silicon) plus `linux-cpu` behavioral
cohort sign-off closed under [Wave W](cohort-validation-waves.md) with no remaining work.
**Supersession note**: this sprint supersedes Sprint 8.7's `IO Bool` sentinel observation
(`sentinelReady = try @SomeException (minioObjectExists ...) >>= either (const (pure False)) pure`,
coercing any transport fault into the same `False` as a genuine 404) and the Python
`_mt3_pytorch_objects_are_valid :: … -> bool` fail-open revalidation (an `except Exception: return
False` that deleted a valid retained `.ready` sentinel on a fallible read). Sprint 8.7's typed
`WarmModelCacheOutcome` witness stands; this sprint fixes the observation feeding it.
**Code-side closure**: complete on the machine-independent gate set — `cabal build all`
(`-Wall -Werror`), `cabal test infernix-unit` (`classifyHeadOutcome` table + `tallyCensus` partition +
the kernel transient-fault/persistent-unobservable cases), `cabal test infernix-haskell-style`,
`infernix lint files/docs/proto/chart`, `infernix docs check`, and `poetry run check-code`.
**Cohort gate**: apple-silicon + linux-cpu, closed under [Wave W](cohort-validation-waves.md) — the
behavioral proof that a retained second `cluster up` warms the cache without the "11/16" stall.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`, `python/adapters/model_bootstrap.py`,
`test/unit/Spec.hs`
**Blocked by**: Sprint 1.18, Sprint 8.7
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and this plan

### Objective

Close the representable invalid state that stalled `infernix test all`: the warm-model-cache barrier
observed each model's `.ready` sentinel through an `IO Bool` HEAD that collapsed three distinct facts —
present (200), absent (404), and unobservable (a reset idle NodePort connection, a HEAD timeout, a
not-yet-ready `5xx`/`403`) — into one `False`. On the retained-state second `cluster up`, idle-NodePort
faults made present, retained sentinels read as absent, deflating the census and stalling the
already-warm cache to its give-up deadline ("11/16"). The Python cache revalidation had the mirror
defect: a fallible read deleted a valid retained sentinel. Make the observation three-valued end to end
so a fault can never masquerade as absence. This consumes the Sprint 1.18 observable-readiness kernel.

### Deliverables

- `SentinelObservation = SentinelPresent | SentinelAbsent | SentinelUnobservable Text` in
  `src/Infernix/Runtime/Pulsar.hs`, with a pure exported
  `classifyHeadOutcome :: Either SomeException Int -> SentinelObservation` — only a genuine 404 mints
  `SentinelAbsent`; a transport exception, a `5xx` "server not ready", and a `403` "IAM not ready" are
  `SentinelUnobservable` — plus `observeMinioObject`
- `SentinelCensus` + a barrier probe on Sprint 1.18's `awaitReadinessObservable` that reports
  `Unobservable` (retried within budget) when any sentinel is unobservable, `Ready` only when every
  sentinel is present, and an honest `Progress` count only over a fully-observed census with genuine
  absences, so a present-but-momentarily-faulting cache is observed present on a later poll. The
  barrier stays non-fatal
- Python `CacheValidity = VALID | CORRUPT | UNVERIFIABLE` in
  `python/adapters/model_bootstrap.py`; `_delete_model_prefix` is reachable only through the `CORRUPT`
  arm (a deterministic HEAD-size mismatch), so a fallible MinIO read is `UNVERIFIABLE` and the
  retained sentinel is kept
- unit coverage for the classifier table, the census partition, and (with Sprint 1.18) the kernel
  retry/give-up behavior
- the superseded `IO Bool` sentinel probe, the `sentinelReady` error-to-`False` coercion, and the
  Python fail-open delete are recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint files/docs/proto/chart`, `infernix docs check`, and `poetry run check-code` — all
  clean on the apple-silicon lane
- `infernix test all` on apple-silicon plus `linux-cpu` proves a retained second `cluster up` warms the
  cache without the "11/16" stall — closed under [Wave W](cohort-validation-waves.md), paired with
  [Sprint 1.18](phase-1-repository-and-control-plane-foundation.md)

### Remaining Work

None.

## Sprint 8.9: Generated Proper-Union Execution Plan [Done]

**Status**: Done. The whole generated execution-plan language is
union-typed: the budget union landed first, and the five items it named as explicit follow-on work
are closed. Behavioral evidence is consumed from the Phase 6 Sprint 6.44 cohort, per this sprint's
own validation rule that it must not create a dual-accelerator gate of its own.
**Code-side closure**: complete. The machine-independent gate set passes
(`cabal build all --enable-tests`, `infernix-unit`, `infernix-execution-plan-internal`,
`infernix-capped-engine-observer`, `infernix-compile-fail`, `infernix-haskell-style`, and
`lint files|chart|proto|docs` plus `docs check`).
**Cohort gate**: [Wave Z](cohort-validation-waves.md) — met. Both lanes exited 0 against one frozen
source, each decoding a freshly generated union payload end to end, and the browser-side over-budget
reader ran on `linux-gpu` for the first time rather than returning null for every budget on that lane.
This sprint opened no wave of its own, because its own validation rule forbids it from creating a
dual-accelerator gate; it consumed Phase 6 Sprint 6.44's.
**Blocked by**: nothing. Phase 6 Sprint 6.44's dual RAM/VRAM capability surface landed the third
union arm this sprint's language needed.
**Implementation**: `src/Infernix/Substrate/Internal.hs`, `src/Infernix/Types.hs`,
`src/Infernix/DemoConfig/Internal.hs`, `src/Infernix/DhallSchema.hs` (reflection, unchanged),
`test/unit/Spec.hs`
**Docs to update**: `documents/architecture/configuration_doctrine.md` (updated),
`documents/architecture/typed_execution_plan.md` (updated),
`documents/engineering/cluster_config_manifest.md`

### Objective

Complete the zero-tracked-Dhall doctrine by making every binary-generated runtime payload use the
proper execution-plan unions and by deleting the flat tagged compatibility representation.

### Deliverables

- `infernix init`, test-harness generation, image-baked config, and cluster ConfigMap payloads emit
  the same proper-union execution language
- reflected schemas and renderers share the Haskell ADTs without string discriminators
- old flat `DhallInferenceMemoryBudget` decoding and zeroed fields are removed
- startup compiles and refines the generated plan before publishing readiness

### Landed Implementation

The sprint's premise was partly out of date when it was reached, and the plan is corrected here
rather than left claiming work that no longer existed. The budget was **already** a proper two-arm
union with per-arm payload records — the text discriminator and zero-filled fields were removed
earlier — so this sprint's real remaining scope was the third arm, the drift surface, the migration
diagnostic, and the dead residue.

1. **Third union arm.** `DhallInferenceMemoryBudget` gains `DualEnforced DhallDualMemoryBudget`,
   whose two halves reuse the substrate limit record so they are structurally identical and the arm
   names which is which instead of encoding it in a discriminator field. The decoder path is now one
   shared `podMemoryLimitFromDhall` used by both the single and dual arms, so the positivity and
   enum checks cannot drift between them, and each diagnostic names its own field path
   (`inferenceMemoryBudget.vramLimit.limitMib`, not a generic message).
2. **One rendered union type.** The union's type annotation was a string literal duplicated once per
   arm. It is now a single `inferenceMemoryBudgetUnionType` that every arm selects from, with the
   arm payload record type factored out alongside it, so a new arm cannot be added to the ADT and the
   decoder while some renderer keeps emitting a stale union type.
3. **Drift is now asserted, not assumed.** Nothing in the type system ties the hand-written renderer
   annotation to the reflected decoder type. The schema-reflection test now renders a real generated
   payload for each of the three budget shapes through the production
   `renderGeneratedDemoConfigPayload` — the same function all four generators funnel through — and
   asserts every alternative the reflected decoder expects appears in it, in both directions.
4. **Targeted migration diagnostic.** A payload written by a pre-union generator used to surface a
   bare structural Dhall type error that said nothing about what to do. `decodeRawRuntimeConfigFile`
   now classifies the retired shapes (`inferenceRamBudgetMib`, a `kind =` discriminator, a flat
   `podLimitMib`) and prefixes the failure with the retired shape's name and the command that
   regenerates it — which is always the right fix, because no `.dhall` is version-controlled. The
   unit suite asserts the diagnostic names both the shape and `infernix init`.
5. **Dead residue removed.** The `legacyDhall` prefix branch in the field-name modifier served the
   pre-union decoder and no field carried that prefix any more.

Deliverable 1 was verified rather than re-implemented: every payload — `infernix init`, the test
harness, the image-baked config, and the cluster ConfigMap body — already funnels through
`renderGeneratedDemoConfigPayloadWithModels` → `Models.encodeDemoConfig` →
`Substrate.encodeSubstrateConfig` → `renderSubstrateConfig`, so there is one renderer and one decode
entry point for the whole generated substrate language.

### Validation

- zero tracked `.dhall` remains true — `lint files` passes; the generated `./infernix.dhall`,
  `./infernix-host.dhall`, and secrets manifest used for the style gate are removed after the run
- generated host, test, baked-image, and mounted-cluster payloads round-trip every applicable union:
  the unit suite round-trips the host-enforced and substrate-enforced arms through the real decode
  boundary and compiles a full `linux-gpu` catalog under the dual arm
- legacy flat payloads fail with a targeted migration diagnostic
- machine-independent gates pass

### Landed implementation: the generated wire language

**1. Every enum-like wire field is a Dhall union.** `runtimeMode` (four wire positions),
`daemonRole` (two), `pulsarConnectionMode`, engine-pool `subscription`, model `runtimeLane`,
request-shape `fieldType`, engine-binding `adapterType`, and the `resource` and `source` fields
inside the substrate limit record. Each has a `Dhall*` mirror in `Substrate/Internal.hs` whose
constructors carry a type-specific prefix that `dhallEnumInterpretOptions` strips, so the wire
alternative is the suffix and several mirrors can name alternatives the domain types also name.
Refinement became a total case match, so `parseEnum` is deleted along with every one of its failure
messages: an unsupported spelling is now a structural decode error, not a post-decode string
rejection. Each rendered union type is built from the same exhaustive list the value renderer uses,
so a record annotation cannot drift from the values it annotates.

**Two of the nine fields had no refiner at all**, which changed what "migrate the wire" had to mean
for them. `adapterType` and `source` were raw `Text` from wire to consumer — the first closed only
by a `Set` membership check in the compiler and string dispatch in two runtime modules, the second
only by a non-blank check — so both gained domain types (`Types.EngineAdapterType`,
`Types.PodMemoryLimitSource`) rather than only a wire union. Their guards were then **deleted, not
left unreachable**: `UnsupportedEngineAdapterType`, the runtime's `unsupported_engine_runner` arm,
and the `substrate memory enforcer source must be non-empty` check are gone, because none of them
is a constructible term any more. The unit assertions that covered them are replaced by assertions
about what is now unrepresentable, not deleted silently.

**2. Every quantity is `Natural`.** Seven fields moved off `dhallInteger`'s `+N` rendering; the
decoder converts through `naturalToInt`, which fails closed above `maxBound :: Int` rather than
wrapping a large wire value into a small positive one. `Natural` bounds the bottom only, so
positivity checks that reject zero stay. The negative-`maxInflightPerMember` unit case is rewritten
rather than removed: it used to assert a compiler error and now asserts the stronger property, that
the value is unrepresentable in the wire language and fails at the decode boundary.

**3. `configEdgePort` is removed, not refined.** It was generated as a literal `+0` on every payload
and its only two consumers were range checks on the value it was hardcoded to; the port the system
actually uses is `ClusterState.edgePort`, chosen during `cluster up`, which never travelled through
this language. Refining a field no consumer reads would have dressed up a placeholder instead of
removing one. `InvalidEdgePort` and the `validateDemoConfig` range check went with it.

**4. The Aeson budget names its alternative with a key**, `{"substrateEnforced": {...}}` rather than
`{"kind": "substrate-enforced", ...}` — the JSON analogue of the Dhall union, where an unrecognized
alternative is a structural mismatch instead of a string comparison that falls through. The dead
`inferenceRamBudgetMib` fallback is deleted; it had no producer anywhere in the repo, no test, and a
`.!= 0` default that decoded a malformed document to a silent zero-MiB budget.

*This sprint's premise for item 4 was wrong and is corrected here.* There is **no PureScript decoder
for the budget** — no budget type is in `contractSumTypes` and `web/src` never calls
`/api/demo-config` — so this was a Haskell-plus-Playwright-JS change, not a coordinated
Haskell-plus-PureScript one, and the generated-contract pipeline was not involved. What the survey
did find is a real pre-existing hole that the item's framing had hidden: `inferenceMemoryBudgetAdmission`
in `web/playwright/inference.spec.js` had **no `dual-enforced` arm at all**, so it returned null for
every `linux-gpu` budget and the caller skipped the over-budget assertion entirely — the GPU lane's
browser-side memory-limit check had been passing vacuously since Sprint 6.44 added the dual arm. The
rewritten reader handles all three alternatives and mirrors `compileResources` exactly: a model that
does not require the device is admitted against pod RAM alone, and a device-using model against pod
RAM first and VRAM second, so the pod limit is the one an error names when both are exceeded.

**5. Engine-only refinement is the intended end state**, decided rather than left open. All three
roles compile the plan; only the engine refines it. Refinement is not a stronger validation of the
same object — it is an observation of *the refining process's own machine* (live samplers, the host
partition, this process's cgroup `memory.max`, observed device VRAM), and its pod arm is an exact
match against the hosting pod's `memory.max`. Refining in a coordinator pod would therefore either
fail against a legitimately different limit or, worse, succeed against a ceiling no inference will
run under — manufacturing evidence about a resource the process does not use. The property
refinement exists to establish is discharged where launches happen: it mints the single-flight
`EngineExecutionAuthority` that `publishedResultFromRequest` requires, and neither non-engine role
launches an inference subprocess. Deliverable 4 is therefore scoped to the role that launches
inference, and reads as satisfied. Recorded in
[../documents/architecture/typed_execution_plan.md](../documents/architecture/typed_execution_plan.md).

**Two mechanical facts were found by round-tripping rather than by review**, and both are recorded
because either would have shipped silently. A Dhall alternative is a *label*, so `genericAutoWith`
on a **single-constructor** mirror derives a record, not a one-alternative union — `fieldType`
decoded as `{}` against a `< TextField >` annotation and needs an explicitly built union decoder.
And the wire spelling necessarily changes from `"apple-silicon"` to `AppleSilicon`, so
`retiredSubstrateMarkers` gained one entry per retired text spelling; `daemonRole` is the sharpest,
because its three retired aliases (`frontend`, `cluster`, `host`) are values a union cannot express
at all, so a stale payload carrying one has no other diagnosis.

**Evidence.** Beyond the gate set: the generated `./infernix.dhall` was regenerated and decoded
end-to-end through `infernix cluster status` (which is what caught the `fieldType` derivation
defect); the schema-reflection pin now asserts all 23 union alternatives appear in the reflected
decoder, plus the absence of `edgePort` and of any `Integer`; the wire assertions check the union
spelling is present and that no enum-like field is written as a quoted tag; the retired-shape
diagnostic is asserted for both a retired budget payload and two retired enum spellings, each
guarded by a prior assertion that the current spelling is really present so the fixture cannot go
vacuous; and the budget JSON is asserted to round-trip, to carry no `kind` key, and to name the
retired flat encoding when one is supplied.

### Remaining Work

None; closed by the Phase 6 Sprint 6.44 wave.

---

## Sprint 8.10: Delete The Derivable Wire Fields [Done]

**Status**: Done. Code-side closure came once Phase 4 Sprint 4.34's admission move landed and the
reduced contract could be built on the corrected shape rather than on the defect. The blocker it
carried is discharged: the substrate limit's `resource` / `source` and the partition's headroom term
are the budget's own shape, and deleting them while the coordinator still admitted from a plan-global
budget would have hidden the veto instead of removing it.
**Code-side closure**: clean on the machine-independent gate set — `cabal build all --enable-tests`
under `-Wall -Werror`, `infernix-unit`, `infernix-haskell-style`, `infernix-compile-fail`,
`infernix-execution-plan-internal`, `infernix-capped-engine-observer`,
`infernix-artifact-transaction`, `infernix-apple-materializer`, `poetry run check-code`,
`infernix lint files|chart|proto|docs`, `infernix docs check`.
**Cohort gate**: [Wave Z](cohort-validation-waves.md) — met. The shared `linux-gpu` plus `linux-cpu`
rebuild decoded the reduced payload on both lanes: every generated `.dhall` in the wave's closing run
was written by the binary at the reduced shape and read back by a cluster daemon.
**Implementation**: `src/Infernix/Substrate/Internal.hs`, `src/Infernix/Types.hs`,
`src/Infernix/EngineRouting.hs`, `src/Infernix/Models.hs`, `src/Infernix/ExecutionPlan.hs`,
`src/Infernix/DemoConfig/Internal.hs`, `test/unit/Spec.hs`
**Docs to update**: none. The governed suite describes the doctrine — binary-generated, zero
version-controlled `.dhall`, reflected schema — and never enumerated the field list, so there is
nothing in `documents/` that this deletion contradicts.

### Objective

Remove every wire field that is a second copy of a fact the binary already derives.

Dhall record types are not dependent — a field's type can never mention a sibling's value — so any
pair of fields that must agree is a permanent illegal-state generator, and no amount of validation
makes it otherwise. The equality checks that exist purely to catch such a disagreement are therefore
retired **with** their fields, not before them: they were the symptom.

This is the shape Sprint 8.9 already used when it removed a field rather than refining it.

### Deliverables

- `request_topics` / `result_topic` and their daemon-config mirrors, `engineDaemons`, `engines`, the
  per-entity `runtimeMode` / `location` / `runtimeLane`, the per-pool in-flight knob, the
  substrate-limit `resource` and `source` fields, and the partition's headroom term all leave the
  wire; each gains a retired-shape marker so a stale file gets a migration diagnostic rather than a
  bare Dhall type error
- the mismatch checks that only guarded those duplications are deleted as unreachable
- the Sprint 8.9 unit assertion that a negative in-flight value is unrepresentable is **retired with
  the field**, rather than left asserting a property of something that no longer exists

All three landed. The derivations live at the lowest module that can hold them —
`requestTopicsForMode` / `resultTopicForMode` moved into `Infernix.EngineRouting` beside the pool and
member topics, and `runtimeLaneForMode`, `engineMemberLocationForMode`, `clusterDaemonLocation`, and
`defaultMaxInflightPerMember` into `Infernix.Types` — because `Infernix.Models` imports
`Infernix.Substrate` and the decoder is the new consumer.

Twenty-six `ConfigError` constructors went with their fields. Two decisions inside are recorded
rather than left implicit. **The engine list is derived from the models' selected engines rather
than from the compiled catalog**, which is stricter than the retired generator (an `--empty-models`
bake now carries no engines either) and is what keeps `UnknownSelectedEngine` reachable: a selected
engine with no canonical binding contributes nothing, so the compiler still names the model that
asked for it. And **the retired per-entity `runtimeMode` marker matches on its leading `, `
separator**, because the top-level `runtimeMode` is still on the wire and renders as
`{ runtimeMode = ` — a bare `runtimeMode = ` marker would misfire on every current payload, which is
exactly what the classifier's contract forbids.

Two classes of check are retired as *unrepresentable* rather than merely unreached, and the
distinction is the point. The coordinator-request and result topics can no longer be pointed at
another family's topic, so two of the five `TopicFamilyCollision` fixtures had nothing left to
express; they are replaced by the model-bootstrap axis, which is still declared. And a substrate
limit claiming the wrong physical resource — a VRAM limit on `linux-cpu`, a swapped dual pair, a
limit claiming unified host RAM — is not a constructible term, so those four fixtures are retired
with the fields instead of being left asserting a property of something the wire cannot express.

### Validation

- `infernix internal dhall-schema substrate` diffed before and after: the retired fields must be
  **absent from the reflected schema**, not merely rejected. If the schema is unchanged, the sprint
  did not do what it claims
- `cabal build all` under `-Wall -Werror` — changing the decoder shape makes GHC enumerate the work
- a stale-shape file per retired field produces the migration diagnostic

The diff is the evidence: the reflected schema went from **110 lines to 54**, and a freshly generated
`./infernix.dhall` from **23074 bytes to 9943**. Every retired field is absent from the reflected
schema, and a unit fixture asserts that absence by name so a field cannot quietly return. Eleven
stale-shape fixtures inject one retired field each into a payload that is otherwise exactly what the
binary writes, and assert the migration diagnostic names that exact field. The diagnostic was also
proven on a real stale file rather than only on a fixture: the operator's already-generated
`./infernix.dhall` in this checkout failed closed naming `request_topics`, and `infernix init`
regenerated it.

### Remaining Work

None. The cohort rebuild named above landed with the wave's closing run.

---

## Sprint 8.11: System And Machine Contracts [Done]

**Status**: Done — implemented and validated on the machine-independent gate set plus the Apple
accelerator lane's schema, pin, identity, and round-trip proofs. The three layers this sprint owns
are built and proved at one engine machine; what genuinely needs a second machine is
[Sprint 8.12](#sprint-812-fleet-member-identity-and-broker-side-claim-done).

**The contradiction this sprint was blocked by, and its resolution.** The earlier blocker read: the
machine contract has no home on the Linux lanes, because the only host manifest a pod can see is the
one baked into the image at `/opt/infernix/dhall/InfernixHost.dhall`, byte identical in every pod on
every machine — the same collision Sprint 6.45 recorded for the baked `hostRepoRoot = /workspace`,
which "*collides* across checkouts rather than discriminating them". That analysis is correct, and
it is a statement about a fleet of **more than one** engine machine. It was treated as a blocker on
this sprint because the plan had conflated two different topologies:

- **the deployed platform topology**, which Phase 3 Sprint 3.16 deliberately collapsed to a single
  node — `kindWorkerCount` is `1` for every runtime mode and `repoEngineReplicaCount` is `1` in the
  generated overlay; and
- **a fleet validation topology**, which is what "two Linux machines are different members" needs in
  order to be exercised at all.

Conflating them made this sprint unresolvable by construction: it was blocked on demonstrating a
property that the platform's own topology decision makes undemonstrable. Separating them dissolves
it. Sprint 3.16 governs what the platform *deploys*; a fleet lane is a *validation topology*, and
needing one is not a proposal to re-replicate the deployed platform.

**Be exact about what one member buys.** At one engine machine the machine contract is well defined
because machine and cluster coincide, not because the placement problem was solved. The baked
manifest does not collide when there is one pod to bake it into. That is a true statement with a
short shelf life, and Sprint 8.12 owns the moment it stops being true; this sprint must not be read
as having established a per-machine surface for a fleet.

**Blocked by**: nothing.
**Implementation**: `src/Infernix/Substrate/Internal.hs`, `src/Infernix/HostConfig.hs`,
`src/Infernix/MachineContract.hs`, `src/Infernix/DhallSchema/Enums.hs`,
`src/Infernix/DemoConfig/Internal.hs`, `src/Infernix/Config.hs`, `src/Infernix/Service.hs`,
`src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/ClusterConfig.hs`,
`src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `chart/values.yaml`, `docker/Dockerfile`
**Docs to update**: `documents/architecture/configuration_doctrine.md`,
`documents/engineering/host_tools_manifest.md`, `documents/engineering/cluster_config_manifest.md`

### Objective

Split the wire into a system contract every machine holds identically and a machine contract that
describes one box, and make a fleet-wide disagreement detectable at the only place the fleet meets.

A machine selects what it serves out of the system contract rather than restating it: a pool the
pinned contract does not define is a fail-closed refusal naming the defined ids, not a subscription
to a topic nobody publishes to. The machine contract pins the system contract it was generated
against by content hash, so a machine cannot be paired with a contract it has never seen. Both files
stay binary-generated and untracked, so the pin is over generated text and the
zero-version-controlled-`.dhall` rule is untouched.

Be precise about what those two layers buy: both are **local**. They prove this machine's file
matches this machine's copy of the contract; neither can see another machine's copy. A design that
stops there has replaced several silent disagreement axes with one — a real reduction in blast
radius and no improvement in detectability. The third layer is the one that closes it: the contract
digest is registered in the Pulsar topic's own properties, and a daemon whose digest disagrees
with the registered value refuses to start. The broker is the only place N machines meet, so that is
where the check has to live.

At one engine machine that third layer cannot yet *detect* a fleet disagreement, because there is no
second machine to disagree. It is built and proved instead: the registration, the reread, and the
fail-closed refusal are one mechanism, and a registered value that disagrees exercises the refusal
exactly as a disagreeing second machine would. Building it here means Sprint 8.12 adds machines to a
check that already exists rather than adding the check and the machines at once.

### Deliverables

- **the system contract** (`./infernix.dhall`): substrate mode plus the pool graph, each pool
  carrying the model descriptors it owns. The role, the two in-cluster daemon records, the member
  list, and the top-level model catalog all left the wire
- **the machine contract** (the `machine` block of `./infernix-host.dhall`): this box's default
  role, the engine member identities it may adopt, its model-cache quota, and the digest of the
  system contract it was generated against. It is a union — `ImageDefault` for the byte-identical
  manifest the launcher image bakes, `Machine` for a real machine contract — so a machine contract
  without a pin is unrepresentable, and a daemon started against the image default is refused by
  name. The quota resolves the standing disagreement between the hard-coded 32 GiB host-path cache
  quota and the 64 GiB cluster default: both are now generated from one constant
- **the content pin, and the regeneration coupling it implies**: the digest covers a canonical
  projection of the contract — substrate mode, topic names, object bucket, and the pool graph with
  each pool's subscription, members, and models — so a contract change moves the hash, and the same
  materialization that writes the system contract re-stamps the machine contract beside it. The test
  harness owns `./infernix.dhall` for a run and re-points the pin at the operator's contract when it
  restores it, including on crash recovery
- **the contract digest registered in the topic's own properties**, with a fail-closed check at
  daemon start. Absence is not disagreement: a topic registered by a binary that predates the pin is
  registered rather than refused. The coordinator registers — including over a value it disagrees
  with, which is what a deliberate contract change is — and every other role verifies
- the existing ledger row for the deployment-mirror filename consolidation is **adopted and closed**
  by this sprint, and the two documented mount paths collapse to one name

**Two deliverables closed differently than they were specified, and the reasons are the sprint's
own findings.**

*Pools are a list keyed by an `id` field, not a Dhall record keyed by pool name.* Pool ids are
derived from the active substrate's model catalog, so the field set differs per runtime mode, and
the substrate schema is reflected from the decoder type — which is this sprint's own first
validation step. A record whose fields vary per mode is not reflectable at all, and the map encoding
that is (`List { mapKey, mapValue }`) is the same list with a renamed key field and buys no
additional check. So the promised "a pool the system contract does not define is a decode-time type
error" is delivered as a fail-closed refusal naming the defined pool ids, and the pin is what makes
that equivalent in practice: the pair was generated together, so the pool set a machine resolves
against is the one it was generated with. What the nesting *does* buy is structural: five
disagreement classes — a pool naming a model the catalog does not define, a pool naming a member
that does not exist, a member serving no pool, and a one-sided pool/member link in either direction
— now have no representation to write.

*The node block declares members, not served pools.* A pool names its members, so a declared pool
list would be a second copy of the pool graph — exactly the shape Sprint 8.10 deleted from this wire.
Served pools are derived by intersecting the declared members with the pinned graph, and a machine
whose members no pool names is refused rather than started with an empty subscription set. The
member field is a list rather than a single id because `linux-gpu` compiles one member per framework
engine image; one declared identity needs no selection, and more than one requires `--engine-name`
to name one of them.

### Validation

- `infernix internal dhall-schema substrate` and `... host` diffed before and after: the substrate
  schema loses `daemonRole`, both daemon records, `engineMembers`, and the top-level `models` list,
  and gains the descriptors inside each pool; the host schema gains the `machine` union
- a machine contract paired with a foreign system contract fails the pin, naming both digests, and
  a machine contract paired with its own is accepted
- a daemon whose registered schema-property digest disagrees refuses to start, and the refusal names
  the registered incumbent and this daemon's digest. This is the mechanism proof and it needs one
  machine; the *fleet* proof — two machines disagreeing in earnest — is Sprint 8.12's, and this
  sprint claims only the former. Absence is classified separately from disagreement
- identity is declared: one member resolves with no flag, more than one without `--engine-name` is a
  refusal rather than a default, and a name outside the declared set is refused
- round-trip: render → decode → re-render → byte-compare, on both the `apple-silicon` and
  `linux-cpu` payloads, with the digest stable across the round trip
- `infernix init` on the Apple lane writes a pair whose pin the daemon accepts, and a live
  `infernix service` run against a foreign contract, an image-default manifest, and an undeclared
  engine identity is refused by name in each case
- the Apple cluster lane brings up the platform, publishes the deployment mirror under the
  consolidated `infernix.dhall` name, stages the catalog from the mounted contract, starts the
  coordinator as the digest registrar and the Apple host engine as a verifier that agrees with it,
  and passes cluster-state reload, demo-config load, and the routed probes. It stops at the first
  native-engine model on a host whose `materialize-metal-engines` artifacts were never built — a
  documented prerequisite outside this sprint
- machine-independent gate set: `cabal build all`, `cabal run infernix-unit`,
  `cabal run infernix-haskell-style`, `infernix lint files/docs/chart/proto/plan`, `infernix docs
  check`, the web unit suite (83/83), and `poetry run check-code`

### The defect the cluster lane found

The first cluster run refused itself. The Apple host engine loaded the operator's repo-root system
contract while the coordinator had registered the digest of the *published* mirror, and the two
payloads differ in fields no machine has to agree on — the mirror names its own path, and it is
rendered for the pods that mount it. A byte digest therefore made one contract into two, and the
host engine refused to start against its own deployment, retrying the refusal in a loop.

Both halves are fixed and both are pinned by tests. The digest is now taken over a canonical
projection of the facts a fleet must agree on rather than over file bytes, so two payloads of one
contract digest alike and a changed pool member still moves the hash. And a digest disagreement is
now its own exception type that leaves the registration retry loop the way an asynchronous exception
does: it is a decision, not a transient broker condition, and retrying it produced an unbounded loop
that reprinted the same refusal forever without ever letting the daemon die.

The next cluster run found the deeper half of the same mistake, and then a third. The registered digest is **durable
broker state that outlives a cluster** — the retained-state replay carries Pulsar's own storage
across a teardown — so a check that only ever refuses does not fail closed, it *freezes*: the first
deliberate contract change would make every daemon refuse forever against a value nothing could
update, which is what a coordinator crash-looping against a previous run's digest actually
demonstrated. The authority is now split. The coordinator is the deployment's router and its
publication is the event that changes what the fleet runs, so it registers, including over a value
it disagrees with; every other role verifies and refuses on disagreement. The cost is stated rather
than hidden: two coordinators holding different contracts no longer detect each other. The deployed
topology has one, and the fleet case that needs more is Sprint 8.12's.

### Surfaces this sprint leaves standing, and why

Neither is remaining work in this sprint's scope; both are recorded so the closure is not read as
claiming more than it did.

The plan compiler keeps the graph checks the generated wire can no longer trigger. It validates any
`DemoConfig`, and the wire is one of its inputs rather than the only one. The eight unit fixtures
that drove those checks through the wire were retired rather than re-pointed, and the wire half is
asserted positively instead — the round trip must *succeed* and produce the agreeing shape.

The in-memory `DemoConfig` record still hands every role every field, with the retired wire fields
now derived. Splitting the decoded value by role is a consumer-side refactor across routing, launch,
publication, and presentation, so it is carried as its own row in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under a successor sprint.

### Remaining Work

None.

---

## Sprint 8.12: Fleet Member Identity And Broker-Side Claim [Done]

**Status**: Done — implemented, green on the machine-independent gate set, and validated on a live
two-machine `linux-cpu` fleet plus the paired single-machine run. The blocker this sprint carried
dissolved rather than being waited out: the fleet validation topology is a multi-worker Kind cluster
the lifecycle generates from the system contract's own machine count, not a second physical host.

**Code-side closure**: complete. `cabal build all --enable-tests` under `-Wall -Werror`,
`infernix-unit` (including this sprint's `runFleetMemberIdentityAssertions`), `infernix-compile-fail`,
`infernix-execution-plan-internal`, `infernix-capped-engine-observer`, `infernix-apple-materializer`,
`infernix-haskell-style` (`haskell-style-check: ok`), `infernix-cabal-format`, the web unit suite
(83/83), and `lint files|chart|proto|docs|plan` plus `docs check` all pass.

**Cohort gate**: closed. The `linux-cpu` fleet lane brought up two engine machines on one pool
topic and both served work; the second machine adopting the first's identity was refused at the
broker by name; a restart reacquired its own slot; a machine holding a contract the registrar had
moved away from refused to start naming both digests; and the paired single-machine run reproduced
the deployed topology unchanged. Recorded in [Wave AB](cohort-validation-waves.md).

**Blocked by**: nothing.

**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`,
`src/Infernix/DemoConfig/Internal.hs`, `src/Infernix/ProjectInit.hs`,
`src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `src/Infernix/EngineRouting.hs`,
`src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/Cluster.hs`,
`chart/values.yaml`, `chart/templates/deployment-engine.yaml`,
`chart/templates/configmap-machine-contracts.yaml`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/daemon_topology.md`,
`documents/architecture/configuration_doctrine.md`, `documents/reference/cli_reference.md`

### Objective

Make two engine machines genuinely different members, and make a second machine claiming the first
machine's identity a refusal rather than a silent double-admission.

### Deliverables

- **the workload shape decision, made against a lane that can show the difference**
- **per-machine identity that neither collides nor churns**
- **the broker-side member claim**, adopted from Phase 4 Sprint 4.34
- **a bounded reacquisition window before the refusal**
- **the fleet half of Sprint 8.11's digest check**

### Landed Implementation

**1. The fleet is a count of machines in the system contract, and nothing else.** `infernix init`
and `infernix test init` take `--engine-machines N`; the generated pool graph's member list is the
single-machine graph with each member expanded to `N` ids (`<member>-m1 … -mN`), and every other
property of a pool — its identity, its models, its subscription type, its per-member inflight bound
— is generated once and left alone. Writing the fleet as a rewrite of the single-machine graph
rather than as a second generator is deliberate: two generators that must agree on everything except
the member list is the permanent illegal-state shape Sprint 8.10 deleted from the wire. `N = 1`
reproduces the pre-sprint contract exactly, so the deployed single-node platform is byte-unchanged
and no existing machine contract is invalidated by the dimension merely existing.

`linux-gpu` above one machine is a **named refusal at generation**, and that is a scope decision
rather than a defect. Its member set is already per-framework-image — a python pool's member id *is*
its pool id, and the generated per-engine Deployments are named from those ids — so a fleet
dimension there renames every engine image as well as adding machines. That is a second, independent
change whose only honest proof is the CUDA Linux cohort, which this sprint's lane is not.

**2. The workload shape: generated per-machine `Deployment`s, not a `DaemonSet`.** The decision is
forced by this repository's own doctrine rather than by preference, which is why it could be made
without the lane having to arbitrate taste. A `DaemonSet` makes one pod per node true by
construction, but every pod of a DaemonSet is identical, so a pod can only learn which machine it is
from the downward API — an `env:` block, which the no-environment-variables doctrine forbids in
infernix-owned templates — or from a Kubernetes API read, which makes identity *discovered* and so
contradicts the fail-closed member-identity rule. A DaemonSet and a declared identity are not
expressible together here. Generated per-machine Deployments carry `--engine-name` as a compiled
constant and mount their own machine contract; identity stays declared.

The `Pending` failure mode Sprint 3.16 rejected for the engine pod anti-affinity is a different
thing from the `nodeSelector` these Deployments carry, and the difference is the whole reason the
selector is acceptable. Anti-affinity expressed the one-engine-per-machine **correctness rule** as a
constraint the scheduler could leave unsatisfied. Here that rule is carried by the broker-side claim
instead, and the selector only places a declared machine on the node that *is* that machine: a slot
whose node is gone leaves that machine's engine `Pending`, which is the honest rendering of a machine
being down rather than a silently unsatisfied invariant.

Deployment names are keyed on the machine's **slot** (`infernix-engine-m1`), not on its member id: a
Deployment name has to leave room for the ReplicaSet and pod suffixes Kubernetes appends, and a
member id is operator-facing text of unbounded length. The identity travels in the machine contract
and in `--engine-name`, where its length costs nothing.

**3. Per-machine identity: one contract per machine, generated by the binary.** The baked
`/opt/infernix/dhall/InfernixHost.dhall` is byte identical in every image, so with more than one
engine machine it collides rather than discriminates — the same finding Sprint 6.45 recorded for the
baked `hostRepoRoot`. `cluster up` therefore renders one machine contract per fleet member from this
deployment's own host manifest with the machine block replaced by a contract naming **exactly one**
member, publishes them in a binary-rendered `infernix-machine-contracts` ConfigMap (Helm only
`nindent`s the strings, as it does for `cluster.dhall`), and mounts each machine's own contract at
`/workspace/infernix-host.dhall` — the path manifest discovery already prefers over the baked
default. Identity does not churn, because the slot and the member id are compiled constants in the
generated overlay rather than a pod name or UID.

**4. The broker-side member claim.** Each engine member has a derived claim topic
(`persistent://infernix/demo/fleet.member-claim.<mode>.<member>`), and holding the only **exclusive**
subscription on it *is* the claim. The topic carries no messages. It needs a topic of its own rather
than a subscription on a pool topic because a pool topic is consumed `Shared` by every member of the
pool: an exclusive claim taken there would exclude the fleet rather than one identity. A refused
second claimant reads the topic's stats to name the incumbent and refuses with the identity, the
claim topic, and the incumbent's consumer name and address. Losing the claim later is fatal by
design — a machine that can no longer prove it is the only holder of its identity must not keep
consuming, because continuing is exactly the double-admission the claim exists to prevent.

**5. A bounded reacquisition window.** Pulsar does not release an exclusive slot the instant a TCP
session drops: the WebSocket proxy holds the consumer for the life of its session. Inside that
window a crash-restart of the incumbent and a genuinely second machine are the same observation, so
a claim that refused immediately would convert every engine restart into an outage. The claim
retries until a **wall-clock** deadline 90 s out, which covers the broker's 30 s keep-alive interval
with margin. Waiting does not make the two cases distinguishable — nothing at this layer can — it
makes the common one survivable and leaves the refusal for the case that is still true after the
incumbent's session could have gone. That is stated plainly rather than dressed up as detection.

**6. The fleet half of the digest check** needs no new code: Sprint 8.11 built the registration, the
reread, and the fail-closed refusal, and this sprint supplies the second machine that makes a real
disagreement possible.

### What this sprint does not claim

The claim bounds **one identity to one live claimant at a time**. It does not bound how many
machines a fleet has, it cannot tell a restarting incumbent from an impostor inside the
reacquisition window, and it depends on the broker being the fleet's single meeting point — a second
Pulsar cluster would partition the claim exactly as it would partition the digest. The claim is also
a startup-ordering bracket on the WebSocket lane rather than a constructor precondition of an engine
capability: the filesystem topic-spool lane has no broker to claim against, so making a held claim
required to *build* a capability would have made that lane unrepresentable instead of making the
fleet safe.

### Four defects, three found by construction and one by the live fleet

**A fleet pod would have refused itself over an artefact of its image.** The machine contract a
publication writes is pinned to the contract that publication produced, while every image also
carries the baked, empty-model contract at the canonical repo-root path — so `requireMachineContractPair`
compared a real pin against an unrelated file and refused the pod. The fix is not to weaken the pin
but to give the pod a genuine pair: the published system contract is now mounted at
`/workspace/infernix.dhall` as well as at its mount path, so the pod's local pair check and the
broker's registered digest agree about the same contract. Found before the cohort ran, by following
what the pod would actually read.

**A fleet machine's engine was not phase-gated, and the release timed out on it.** The shared engine
workload's replica count is held at zero until the phase that brings Pulsar up, because an engine
consumes Pulsar topics and would otherwise sit un-ready inside its own phase's rollout wait. The
first fleet Deployments carried a literal `replicas: 1`, so both machines started at the
Harbor-final phase, never became ready, and `helm upgrade` failed with `context deadline exceeded` —
a timeout that reads as an infrastructure problem and is in fact a gating one. The two counts now
come from one function, so the shared workload and a fleet machine cannot drift on when an engine
may start, and the unit suite pins that a pre-final phase asks for zero.

**The claim cannot be the first thing an engine does.** Taken before namespace and topic
reconciliation, the claim would wait on a topic nothing had created yet on a cold cluster. It now
runs after that reconcile and after the contract-digest check — so a machine that disagrees with the
fleet's registered contract refuses *before* claiming an identity inside that fleet — and still
before the readiness sentinel and every pool subscription, which is the ordering that matters.

### Validation

- generated fleet contract: `N` distinct members, every pool naming all of them on one `Shared`
  topic, and `N = 1` byte-identical to the single-machine graph — **passing** (unit)
- the fleet size is recoverable from the declared member ids, because publication regenerates the
  payload rather than copying it — **passing** (unit)
- `linux-gpu` above one machine, and a fleet of zero machines, are named refusals — **passing** (unit)
- the claim topic is per identity and is not a pool topic; the refusal names the identity, the claim
  topic, and the incumbent; a lapsed incumbent is reported as unknown rather than as absent; a 409
  and a consumer-busy response are read as a held claim and a transport failure is not; the
  reacquisition window covers the broker keep-alive — **passing** (unit)
- the Kind topology grows one worker per machine, each carrying its own slot label, and the
  single-worker topology carries the same label so the two shapes differ only in size — **passing**
  (unit)
- each machine contract names exactly one member and none names another machine's, all pinned to one
  system contract; a one-machine deployment renders none — **passing** (unit)
- the generated overlay turns the fleet on, carries each identity as a compiled constant, renders no
  shared engine workload, embeds each machine's contract as a string, and leaves the single-machine
  overlay unchanged; the rollout wait list and the browser preparation name the machines that exist
  — **passing** (unit)
- **the fleet lane brings up two engine machines on one pool topic and both serve work** —
  **passing**. Two Kind workers carrying `infernix.fleet/slot=1` and `=2`; `infernix-engine-m1` and
  `infernix-engine-m2` each `1/1` on a *different* node; each machine resolving its own declared
  identity (`linux-cpu-engine-m1` / `-m2`) out of a mounted machine contract that names exactly one
  member; both subscribed to the same twelve pool topics; all 12 configured models staged and
  `cluster up` exit 0. Four routed inference roundtrips against `llm-tinyllama-gguf` returned real
  llama.cpp output, and the broker's own `Shared` subscription stats moved from `msgOut=0, 0` to
  `msgOut=2, 2` across its two consumers — the split attributed by the broker rather than inferred
  from a log
- **a second machine started with the first machine's member identity is refused at the broker, and
  the refusal names the incumbent** — **passing**. A second replica of `infernix-engine-m1` held its
  window open, then died with `EngineMemberClaimRefused` naming the identity, the claim topic, and
  the incumbent `linux-cpu-engine-m1@b43033b0ebc7043e-1 at /10.244.1.49:48758`. It never became
  ready and never consumed. The broker's view of each claim topic is one `Exclusive` subscription
  with exactly one consumer, named for the member that holds it
- **an engine restart within the broker session timeout reacquires its own slot rather than being
  refused** — **passing**. Deleting the `infernix-engine-m2` pod produced a replacement that logged
  the wait for its own lapsing session and then rolled out successfully
- **two machines carrying disagreeing contract digests: the later refuses to start** — **passing**.
  With the fleet registered at `sha256:891e6bb9…`, the coordinator was given a contract whose pool
  graph names a different model; as registrar it re-registered `sha256:c02c1c64…`, and the engine
  machine still holding the fleet's original contract refused to start with
  `ContractDigestDisagreement` naming both digests. Restoring the registrar's contract let that
  machine roll out again
- **a `linux-cpu` single-machine run proving the deployed topology is unchanged** — **passing**. One
  Kind worker, the shared `infernix-engine` Deployment `1/1` and no per-machine ones, the unsuffixed
  `linux-cpu-engine` identity, one routed roundtrip with real output, and a clean teardown leaving
  the cluster absent

### Remaining Work

None — the fleet lane and its paired single-machine run closed on 2026-08-18 under [Wave AB](cohort-validation-waves.md).

---

## Sprint 8.13: Shared Engine Deployment Member Identity [Done]

**Status**: Done. The shared engine Deployment names the member it is on every lane. Behavioral evidence is the [Wave Z](cohort-validation-waves.md) `linux-gpu` plus
`linux-cpu` cohort this sprint's defect blocked, so it consumes that wave rather than opening one of
its own.
**Code-side closure**: complete. The machine-independent gate set passes —
`cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`,
`infernix-haskell-style` (`haskell-style-check: ok`, `cabal-format-check: ok`), and
`lint files|chart|proto|docs|plan` plus `docs check` all at zero.
**Cohort gate**: the shared `linux-gpu` plus `linux-cpu` rebuild in Wave Z — met. The
`infernix-engine` Deployment became ready on the four-member `linux-gpu` contract, which is exactly
what attempt 6 could not get past, and on the single-member `linux-cpu` contract, and both lanes then
served real inference through it.
**Blocked by**: nothing. Sprint 8.12 landed the fail-closed member identity this completes.
**Implementation**: `src/Infernix/Cluster.hs`, `chart/values.yaml`,
`chart/templates/deployment-engine.yaml`, `test/unit/Spec.hs`
**Docs to update**: [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) (updated — the per-engine-image section now states that a `linux-gpu` machine contract declares more than one member and that the shared Deployment names its own)

### Objective

Give the shared `infernix-engine` Deployment the member identity Sprint 8.12 made every engine
daemon declare.

### Deliverables

- the lifecycle renders the shared engine workload's member identity into the Helm values
- the shared engine Deployment passes `--engine-name` on every lane that deploys one
- a machine-independent guard ties that rendered identity to the machine contract the same lane
  generates

### Landed Implementation

Sprint 8.12 made engine member identity fail closed: a daemon that cannot say which member it is
refuses to start rather than adopting a default. Sprint 8.11's machine contract is what it reads
that identity from. Neither sprint gave the **shared** engine Deployment a name, and on `linux-cpu`
that was invisible, because that lane's contract declares exactly one member (`linux-cpu-engine`)
and `resolveMachineMemberId` resolves a single declared member with no selection. `linux-gpu`
declares four — `native` plus one per framework engine image — so the same template refused by name
and crash-looped:

```text
this machine contract declares 4 engine member identities
("native", "vllm", "pytorch", "diffusers"); pass `--engine-name` to name which one this process is
```

That is the fail-closed rule working, not a defect in it. The defect is the missing name.

1. **The identity is derived, not written down a third time.** `sharedEngineMemberId` in
   `Infernix.Cluster` subtracts `perEngineDeploymentNames` from the lane's declared members. Two
   lists that already exist decide it; a per-mode literal would have been a third copy of the same
   fact, which is the permanent illegal-state shape Sprint 8.10 deleted from the wire. It resolves
   to `native` on `linux-gpu` and `linux-cpu-engine` on `linux-cpu`.
2. **The subtraction is the operational rule, not a convenience.** The shared Deployment runs the
   launcher image, and that image carries the native engine payloads and **none** of the framework
   virtual environments — verified in both rebuilt images rather than assumed. The framework
   members' pools can only be served by their own per-engine images, which is why the harness
   already scales the shared Deployment to zero whenever it activates one of them.
3. **Every lane declares.** `engine.memberName` is rendered by the lifecycle on every lane and the
   template emits `--engine-name` whenever it is non-empty, so a single-member lane now names its
   member explicitly instead of relying on the count. The static chart default stays empty, so an
   operator values file for a single-member contract keeps resolving that member implicitly.

### Validation

- the rendered shared engine member is accepted by `resolveMachineMemberId` against the machine
  contract that same lane generates, asserted for **both** `linux-gpu` and `linux-cpu` — **passing**.
  Asserting acceptance rather than a literal keeps the guard alive through a later rename of either
  list
- the rendered shared engine member is **not** one of that lane's per-engine deployment names —
  **passing**. Declared is necessary but not sufficient: naming a framework member would point the
  shared Deployment at pools only the per-engine image can serve
- both halves are negative-tested and fail by name — rendering an empty identity fails
  `the linux-gpu lifecycle renders a shared engine member name`, and rendering a framework member
  fails `the linux-gpu shared engine member is the one with no per-engine Deployment of its own`
- machine-independent gates pass
- selected `linux-gpu` plus `linux-cpu` full-suite gate against one frozen state — **passed**

### Remaining Work

None; closed by the Wave Z run that cleared it.

---

## Documentation Requirements

**Engineering docs to create/update:**
- [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md) — the authoritative doctrine (zero-tracked-Dhall, binary-generated, init/test-init, fail-fast, harness lifecycle, model SSoT, eager staging).
- [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md) and [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md) — reflected-schema + binary-rendered ConfigMap/Secret contract.
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) — Managed State Transitions doctrine this phase now references for the `warm-model-cache` readiness evidence and fail-closed config-side persistence (Sprint 8.7).

**Product or reference docs to create/update:**
- [../documents/reference/cli_reference.md](../documents/reference/cli_reference.md) and [../documents/reference/cli_surface.md](../documents/reference/cli_surface.md) — gain `infernix init` and `infernix test init` alongside their `CommandRegistry.hs` entries (Sprint 8.2).
- [../documents/development/testing_strategy.md](../documents/development/testing_strategy.md), [../documents/development/local_dev.md](../documents/development/local_dev.md) — init-first workflow and harness create/delete lifecycle.

**Cross-references to add:**
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — the retired tracked-schema, Helm-rendered-cluster-config, and lazy-model-bootstrap surfaces.
- [development_plan_standards.md](development_plan_standards.md) Sections U (configuration substrate) and V (host tools manifest).
