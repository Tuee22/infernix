# Phase 8: Zero-Tracked-Dhall Config and Eager Model Cache

**Status**: Done — all sprints (8.1-8.6) closed. Machine-independent gates pass, and the single-accelerator cohort gate closed 2026-07-04 (Wave P): `./bootstrap/linux-gpu.sh test` and `./bootstrap/linux-cpu.sh test` both ran the full `infernix test all` suite green — Haskell style, Python `check-code`, unit, web contracts, full integration with real per-model `linux-gpu`/`linux-cpu` output, and routed Playwright **9/9** including the per-model matrix's 27 GB `video-wan21-t2v` row (gpu image `sha256:3a356ef2…`, cpu image `sha256:81fab869…`). One documented non-blocking residual remains: the `warm-model-cache` barrier's host-side MinIO poll observability (Sprint 8.5).
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Adopt the `~/hostbootstrap` Dhall doctrine — no version-controlled `.dhall`, the
> binary as the sole generator of every `.dhall` (including ConfigMap/Secret bodies), explicit
> `init` / `test init` creation, fail-fast-if-missing, and a test harness that generates the runtime
> config, runs, and deletes it — and replace the lazy per-inference model bootstrap with eager
> coordinator model-cache staging driven by the mounted `infernix.dhall`.

## Phase Status

> Phase 8 reconciles the configuration substrate to the doctrine in
> [configuration_doctrine.md](../documents/architecture/configuration_doctrine.md). It supersedes the
> earlier "checked-in decoder-reflected `dhall/Infernix*.dhall` schema files + `lint docs` file-drift
> check" mechanism (Phase 4 Sprint 4.13 follow-ons) and the Helm-rendered cluster-config ConfigMap
> (Phase 4), and it retires the lazy per-inference model-bootstrap workflow
> (`src/Infernix/Bootstrap/Models.hs` + the `model.bootstrap.request` topic family) in favour of
> eager startup staging. The retired surfaces are recorded in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Sprint 8.1: Zero Version-Controlled Dhall [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `docker/Dockerfile`, `src/Infernix/Lint/Docs.hs`, `test/unit/Spec.hs`, `src/Infernix/DhallSchema.hs`, `src/Infernix/DhallSchema/Reflection.hs`

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

### Validation

- `infernix init` then `infernix test init` produce the config files; `docs check` sees the new
  command-registry entries; `infernix test unit` covers the registry/help assertions

### Remaining Work

None.

## Sprint 8.3: Fail-Fast, No Auto-Generate Backstops [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs` (`discoverCliCommandPaths`), `src/Infernix/DemoConfig.hs` (`materializeHostManifestFile`, `materializeHostSecrets`; `ensureGeneratedDemoConfigFile` deleted), `src/Infernix/Runtime/Worker.hs` (`loadHostWorkerSecrets`), `src/Infernix/Cluster.hs` (`requireGeneratedDemoConfigFile`, `discoverClusterCommandPaths`)

### Objective

Remove every auto-generate-if-absent path so a missing config is a loud, actionable error.

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

> **Known residual (non-blocking):** the coordinator's forked eager sweep is the mechanism that
> delivers the outcome (Wan staged in time → 9/9 on both lanes). The `warm-model-cache` `cluster up`
> barrier is wired in and best-effort, but its host-side MinIO poll from the Linux launcher currently
> reports `0/16` (a presigned-HEAD reachability/signing detail against the node-port endpoint at
> `<kindControlPlaneIpv4>:30011`), so it logs a warning and proceeds rather than truly blocking. This
> did not affect the 9/9 result. Making the barrier's poll observe the sentinels (so it deterministically
> blocks) is a follow-up; the eager sweep + lazy fallback already guarantee correctness.

> **Apple-silicon cohort not run (2026-07-07).** This sprint's cohort gate is Wave P (`linux-gpu` +
> `linux-cpu`) only; no apple-silicon full-suite ran. The eager-stage-**all** behavior here is the
> trigger that surfaces the apple-silicon inference RAM gap: on `apple-silicon` every staged model
> runs on the single on-host daemon, so a full per-model `test integration` attempts all 16 and
> exhausts host RAM (OS OOM-kill). The zero-tracked-Dhall + disk-cache-staging contract stays `Done`;
> the RAM-safety fix is owned by Phase 4 Sprint 4.26 (paired with Phase 6 Sprint 6.37). If that fix
> changes Apple staging to bounded/lazy, this sprint reopens.

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

## Documentation Requirements

**Engineering docs to create/update:**
- [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md) — the authoritative doctrine (zero-tracked-Dhall, binary-generated, init/test-init, fail-fast, harness lifecycle, model SSoT, eager staging).
- [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md) and [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md) — reflected-schema + binary-rendered ConfigMap/Secret contract.

**Product or reference docs to create/update:**
- [../documents/reference/cli_reference.md](../documents/reference/cli_reference.md) and [../documents/reference/cli_surface.md](../documents/reference/cli_surface.md) — gain `infernix init` and `infernix test init` alongside their `CommandRegistry.hs` entries (Sprint 8.2).
- [../documents/development/testing_strategy.md](../documents/development/testing_strategy.md), [../documents/development/local_dev.md](../documents/development/local_dev.md) — init-first workflow and harness create/delete lifecycle.

**Cross-references to add:**
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — the retired tracked-schema, Helm-rendered-cluster-config, and lazy-model-bootstrap surfaces.
- [development_plan_standards.md](development_plan_standards.md) Sections U (configuration substrate) and V (host tools manifest).
