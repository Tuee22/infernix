# Phase 8: Zero-Tracked-Dhall Config and Eager Model Cache

**Status**: Active — the Observable-Readiness reopen (Sprint 8.8, the fault-vs-absence fix in the warm-model-cache barrier: tri-state `SentinelObservation` probe + `SentinelCensus` + Python `CacheValidity`) is **code-side closed (2026-07-22)** on the machine-independent gate set, with the behavioral single-accelerator (apple-silicon) plus `linux-cpu` cohort sign-off pending [Wave W](cohort-validation-waves.md). Sprints 8.1-8.7 are closed: machine-independent gates pass; the single-accelerator cohort gate closed 2026-07-04 (Wave P): `./bootstrap/linux-gpu.sh test` and `./bootstrap/linux-cpu.sh test` both ran the full `infernix test all` suite green — Haskell style, Python `check-code`, unit, web contracts, full integration with real per-model `linux-gpu`/`linux-cpu` output, and routed Playwright **9/9** including the per-model matrix's 27 GB `video-wan21-t2v` row (gpu image `sha256:3a356ef2…`, cpu image `sha256:81fab869…`). The Managed-State-Transition reopen (Sprint 8.7) is closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus linux-cpu full-suite `test all` green. Sprint 8.8 supersedes the earlier documented non-blocking residual (the `warm-model-cache` barrier's host-side MinIO poll observability, Sprint 8.5): that poll's fault-vs-absence collapse is now the diagnosed root cause of the retained-second-`cluster up` "11/16" stall and is fixed by construction.
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
**Code-side closure**: `cabal build all`, `infernix test unit` (new `defaultClusterConfig` decode + `renderHelmValues` body/manifest assertions), `infernix test lint`/`lint chart`/`lint files`/`lint docs`/`lint proto`, `docs check` all pass (machine-independent, 2026-07-03).
**Cohort gate**: the in-pod decode of the binary-rendered `cluster.dhall` / `InfernixSecrets.dhall` is covered by the same `linux-cpu` plus selected `linux-gpu` full-suite that closes Phase 8 (Wave O successor).
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

None (code-side); cohort full-suite decode-in-pod tracked with the Phase 8 cohort gate.

## Sprint 8.5: Coordinator Eager Model-Cache Staging [Done]

**Status**: Done — cohort gate closed 2026-07-04 (see [cohort-validation-waves.md](cohort-validation-waves.md) Wave P). The `linux-gpu` and `linux-cpu` full-suite `infernix test all` both passed with routed Playwright **9/9**, including the browser per-model smoke matrix exercising every catalog model — the 27 GB `video-wan21-t2v` row that previously timed out cold now completes (gpu 18.2 m, cpu 16.5 m) because the coordinator's eager sweep begins staging at cluster-up. gpu image `sha256:3a356ef2…`, cpu image `sha256:81fab869…`.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs` (`sweepEagerModelCache`, `waitForEagerModelCacheReady`), `src/Infernix/Runtime/Daemon.hs` (`startCoordinatorLoops`), `src/Infernix/Cluster.hs` (`warmModelCache` + `warm-model-cache` lifecycle phase, `resolveWarmModelCacheMinioHost` via `kindControlPlaneIpv4`), `src/Infernix/DemoConfig.hs` (`materializeEmptyModelsDemoConfigFile`), `src/Infernix/CommandRegistry.hs` (`--empty-models`), `src/Infernix/Models.hs` (demo-only-generator doc), `docker/Dockerfile`
**Docs to update**: `documents/engineering/model_lifecycle.md`, `documents/architecture/daemon_topology.md`

> **Known residual (non-blocking):** the coordinator's forked eager sweep is the mechanism that
> delivers the outcome (Wan staged in time → 9/9 on both lanes). The `warm-model-cache` `cluster up`
> barrier is wired in and best-effort, but its host-side MinIO poll from the Linux launcher currently
> reports `0/16` (a presigned-HEAD reachability/signing detail against the node-port endpoint at
> `<kindControlPlaneIpv4>:30011`), so it logs a warning and proceeds rather than truly blocking. This
> did not affect the 9/9 result. Making the barrier's poll observe the sentinels (so it deterministically
> blocks) is a follow-up; the eager sweep + lazy fallback already guarantee correctness.

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
  context. That poll is non-observing today (reports `0/16` and warns-and-proceeds rather than truly
  blocking); the eager sweep still stages the weights, and making the poll observe the sentinels so it
  deterministically blocks is the tracked follow-on
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
- cohort (closed 2026-07-04, Wave P): the `linux-gpu` **and** `linux-cpu` full-suite `infernix test all`
  both passed with routed Playwright **9/9**; the per-model browser matrix (spec 945) exercises every
  catalog model and the 27 GB `video-wan21-t2v` row completes (gpu 18.2 m, cpu 16.5 m) because the
  eager sweep starts staging at cluster-up

### Remaining Work

None (code-side and cohort closed). The best-effort `warm-model-cache` barrier's host-side poll
observability is the documented non-blocking residual above.

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
single-accelerator (apple-silicon) plus linux-cpu full-suite sign-off closed by
[Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-16 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit` (typed warm-cache outcome consumption and the port-file fail-closed
assertions pass), `cabal test infernix-haskell-style`, and `infernix lint docs` all green on the
apple-silicon lane. No native/Python change, so `poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus linux-cpu full-suite `test all` green.
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

- the `warm-model-cache` barrier's readiness wait in `src/Infernix/Runtime/Pulsar.hs` returns typed
  readiness evidence `E(S)` for the cache-ready state, generalizing the existing progress-based poll
  rather than returning a bare boolean
- `src/Infernix/Cluster.hs` consumes that typed evidence at the `warm-model-cache` lifecycle phase so
  the barrier's transition is gated on evidence of the observed sentinels
- the config-side state files adopt fail-closed versioned persistence — an unknown or unversioned
  on-disk state fails closed rather than being silently reinterpreted

### Validation

- code-side gates exercised on both the apple-silicon and linux-cpu lanes: `cabal build all`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint docs`, and (for any
  native/Python change) `poetry run check-code`
- the readiness wait is asserted to surface typed evidence, and the versioned persistence is asserted
  to fail closed on an unknown version

### Remaining Work

- code-side closed 2026-07-16. Landed this sprint:
  - `waitForEagerModelCacheReady` (`src/Infernix/Runtime/Pulsar.hs`) returns a typed
    `WarmModelCacheOutcome` — `WarmModelCacheAllStaged` carries an opaque `WarmModelCacheReady`
    witness minted only when every configured model's `.ready` sentinel was observed, while
    `WarmModelCacheStillPending` carries the still-unstaged ids — generalizing the previous bare
    pending list
  - `src/Infernix/Cluster.hs` (`runWarmModelCacheBarrier`) consumes the typed evidence: the
    "all staged" declaration is gated on the `WarmModelCacheAllStaged` witness, and a pending outcome
    logs the non-blocking warning
  - the config-side port state files (`readPortFileMaybe` in `src/Infernix/Storage.hs`) read
    fail-closed — absent/blank is `Nothing`, but a present-but-undecodable file is a loud error rather
    than a silent `Nothing` that would re-choose a port; the authoritative config-side cluster-state
    file already uses the Sprint 2.14 fail-closed versioned aeson codec
- validated with `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  and `infernix lint docs`
- the cohort full-suite sign-off closed under [Wave V](cohort-validation-waves.md) (2026-07-20) —
  apple-silicon plus linux-cpu full-suite `test all` green; no remaining work exists

---

## Sprint 8.8: Fault-vs-Absence in the Warm-Model-Cache Barrier [Active — code-side closed]

**Status**: Active — code-side closed (2026-07-22). The warm-model-cache observation surface is now
three-valued end to end (Haskell sentinel probe + Python cache revalidation), so a transport fault can
no longer masquerade as a definitive absence and stall the retained-second-`cluster up` barrier; the
behavioral single-accelerator (apple-silicon) plus `linux-cpu` cohort sign-off is the one residual,
pending [Wave W](cohort-validation-waves.md).
**Supersession note**: this sprint supersedes Sprint 8.7's `IO Bool` sentinel observation
(`sentinelReady = try @SomeException (minioObjectExists ...) >>= either (const (pure False)) pure`,
coercing any transport fault into the same `False` as a genuine 404) and the Python
`_mt3_pytorch_objects_are_valid :: … -> bool` fail-open revalidation (an `except Exception: return
False` that deleted a valid retained `.ready` sentinel on a fallible read). Sprint 8.7's typed
`WarmModelCacheOutcome` witness stands; this sprint fixes the observation feeding it.
**Code-side closure**: complete (2026-07-22). Landed: (a) `SentinelObservation = SentinelPresent |
SentinelAbsent | SentinelUnobservable Text` with a pure, exported `classifyHeadOutcome :: Either
SomeException Int -> SentinelObservation` (only a genuine 404 mints `SentinelAbsent`; a transport
exception, a `5xx` "server not ready", or a `403` "IAM not ready" are `SentinelUnobservable`) and
`observeMinioObject` in `src/Infernix/Runtime/Pulsar.hs`; (b) a `SentinelCensus` and the barrier probe
rewritten onto Sprint 1.18's `awaitReadinessObservable` — a census with any unobservable sentinel
yields a kernel `Readiness.Unobservable` poll (retried within budget), never a fabricated `Progress`
count, so a present-but-momentarily-faulting cache is observed present on a later poll instead of
stalling at "11/16"; (c) the Python `CacheValidity = VALID | CORRUPT | UNVERIFIABLE` verdict in
`python/adapters/model_bootstrap.py` — `_delete_model_prefix` is reachable only through the `CORRUPT`
arm (a deterministic HEAD-size mismatch), so a fallible MinIO read is `UNVERIFIABLE` and the retained
sentinel is kept. The barrier stays non-fatal. Gate set (GREEN 2026-07-22): `cabal build all`
(`-Wall -Werror`), `cabal test infernix-unit` (`classifyHeadOutcome` table + `tallyCensus` partition +
the kernel transient-fault/persistent-unobservable cases), `cabal test infernix-haskell-style`,
`infernix lint files/docs/proto/chart`, `infernix docs check`, and `poetry run check-code`.
**Cohort gate**: apple-silicon + linux-cpu, [Wave W](cohort-validation-waves.md) — the behavioral proof
that a retained second `cluster up` warms the cache without the "11/16" stall.
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

- `SentinelObservation` tri-state + pure exported `classifyHeadOutcome` + `observeMinioObject`
- `SentinelCensus` + a barrier probe on `awaitReadinessObservable` that reports `Unobservable` (retry)
  when any sentinel is unobservable, `Ready` only when every sentinel is present, and an honest
  `Progress` count only over a fully-observed census with genuine absences
- Python `CacheValidity = VALID | CORRUPT | UNVERIFIABLE`; `_delete_model_prefix` gated on `CORRUPT`
- unit coverage for the classifier table, the census partition, and (with Sprint 1.18) the kernel
  retry/give-up behavior

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `infernix lint files/docs/proto/chart`, `infernix docs check`, and `poetry run check-code` — all
  green on the apple-silicon lane (2026-07-22)
- `infernix test all` on apple-silicon plus `linux-cpu` proves a retained second `cluster up` warms the
  cache without the "11/16" stall — closed under [Wave W](cohort-validation-waves.md)

### Remaining Work

The implementation is complete and code-side closed (2026-07-22): the tri-state Haskell probe + census,
the observable-poll barrier, and the Python `CacheValidity` gate are landed with unit coverage. The one
residual is the Wave W behavioral proof, paired with
[Sprint 1.18](phase-1-repository-and-control-plane-foundation.md). The superseded `IO Bool` sentinel
probe, the `sentinelReady` error-to-`False` coercion, and the Python fail-open delete are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

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
