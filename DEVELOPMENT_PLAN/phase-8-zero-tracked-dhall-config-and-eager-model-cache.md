# Phase 8: Zero-Tracked-Dhall Config and Eager Model Cache

**Status**: Active — reopened for the hostbootstrap-aligned config doctrine
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

## Sprint 8.2: `init` / `test init` Commands and Shared Defaults [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/ProjectInit.hs` (new), `src/Infernix/CommandRegistry.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`

### Objective

Make config creation explicit and DRY: one defaults owner shared by `init` and the test harness.

### Deliverables

- `Infernix.ProjectInit` owns the single default builder (`projectInitSubstrate` emitting an
  **empty-models** base config, `projectInitHostConfig`, `projectTestConfig`) and one atomic
  `writeProjectConfigFile`
- top-level `infernix init [--runtime-mode M] [--demo-ui B] [--force] [--if-missing]` writes the
  runtime `./infernix.dhall` (substrate) and host manifest `./infernix-host.dhall`; it fails fast if
  `./infernix.dhall` exists unless `--force`
- top-level `infernix test init` writes the thin `./infernix.test.dhall` and needs no pre-existing config
- `Config.hs` exposes `runtimeConfigPath` (`./infernix.dhall`) and `testConfigPath`
  (`./infernix.test.dhall`); existing readers follow the relocated path

### Validation

- `infernix init` then `infernix test init` produce the two files; `docs check` sees the new
  command-registry entries; unit registry/help assertions updated

### Remaining Work

Author the module + commands; relocate the runtime-config path.

## Sprint 8.3: Fail-Fast, No Auto-Generate Backstops [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/CLI.hs` (`discoverCliCommandPaths`), `src/Infernix/DemoConfig.hs`, `src/Infernix/Config.hs` (`tryLoadHostManifest`), `src/Infernix/Runtime/Worker.hs` (`ensureHostWorkerSecrets`), `src/Infernix/Cluster.hs` (`requireGeneratedDemoConfigFile`)

### Objective

Remove every auto-generate-if-absent path so a missing config is a loud, actionable error.

### Deliverables

- `discoverCliCommandPaths` fails fast (naming `infernix init`) instead of auto-materializing the host
  manifest; `ensureGeneratedDemoConfigFile` is deleted; `materializeHostManifestFile` loses its
  early-return backstop; `ensureHostWorkerSecrets` no longer `writeFileIfMissing`
- every binary/test command that needs a config names the exact init to run when it is absent

### Validation

- deleting `./infernix.dhall` then any command fails fast with the init reminder; `infernix test unit`

### Remaining Work

All of the above.

## Sprint 8.4: Binary-Generated ConfigMap + Secret Bodies [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/ClusterConfig.hs` (`defaultClusterConfig`), `src/Infernix/Cluster.hs` (`renderHelmValues`), `chart/templates/configmap-cluster-config.yaml`, `chart/templates/secret-cluster-secrets.yaml`, `chart/values.yaml`, `src/Infernix/Lint/Chart.hs`

### Objective

Move all remaining Dhall generation out of Helm into the binary; Helm becomes a string embedder.

### Deliverables

- `defaultClusterConfig` carries the wiring values formerly in `chart/values.yaml`; `renderHelmValues`
  emits the `cluster.dhall` and secrets bodies as strings
- `configmap-cluster-config.yaml` + `secret-cluster-secrets.yaml` contain only `{{ … | nindent }}`
  passthroughs of the binary-produced strings — no `let …`/schema Dhall inside any chart template
- `infernix lint chart` rejects any Dhall `let`/schema body inside a chart template

### Validation

- `infernix lint chart`; `helm template` renders valid `cluster.dhall`; integration decodes it in-pod

### Remaining Work

All of the above.

## Sprint 8.5: Coordinator Eager Model-Cache Staging [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/Runtime/Pulsar.hs` (`sweepEagerModelCache`), `src/Infernix/Runtime/Daemon.hs` (`startCoordinatorLoops`), `src/Infernix/Cluster.hs` (`warm-model-cache` phase)

### Objective

Replace the lazy per-inference model bootstrap with eager staging driven by the mounted config, so no
inference races a cold cache.

### Deliverables

- the coordinator eagerly stages every model listed in the mounted `infernix.dhall` on startup
  (reusing the idempotent download/upload/`.ready` logic), failing fast if no config is present
- a `warm-model-cache` cluster-up barrier blocks completion until every listed model has its `.ready`
  sentinel (progress-based deadline)
- the model set is the mounted `infernix.dhall` (the source of truth); `src/Infernix/Models.hs`
  `matrixRows`/`catalogForMode` is documented and used as a **demo-only** generator of that list, not
  a core dependency
- the image-baked `infernix.dhall` lists no models (safe for `docker run --rm`); the ConfigMap-mounted
  config overrides it at deploy
- the lazy engine bootstrap remains only as a fallback

### Validation

- `cluster up` populates `infernix-models/<modelId>/.ready` for every configured model before it
  reports complete; the `linux-gpu` per-model browser matrix reaches 9/9 (the 27GB Wan row stages at
  cluster-up, outside the test window)

### Remaining Work

All of the above.

## Sprint 8.6: Test-Harness Config Lifecycle [Planned]

**Status**: Planned
**Implementation**: `src/Infernix/CLI.hs` (`test` dispatch), `test/integration/Spec.hs`
**Docs to update**: `documents/development/testing_strategy.md`, `documents/development/local_dev.md`

### Objective

Make the test harness own the runtime config for the duration of a run.

### Deliverables

- `infernix test …` reads `./infernix.test.dhall` (fail fast → `infernix test init`), fails fast if
  `./infernix.dhall` already exists, generates `./infernix.dhall` from the test overrides, runs the
  suites, and deletes it via a self-created-only guard
- the integration suite's per-variant substrate materialization keeps rewriting the harness-owned path

### Validation

- with `./infernix.dhall` present, `infernix test all` refuses; without `./infernix.test.dhall`, it
  names `infernix test init`; after a run, `./infernix.dhall` is gone

### Remaining Work

All of the above.

## Documentation Requirements

### Engineering docs

- [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md) — the authoritative doctrine (zero-tracked-Dhall, binary-generated, init/test-init, fail-fast, harness lifecycle, model SSoT, eager staging).
- [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md) and [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md) — reflected-schema + binary-rendered ConfigMap/Secret contract.

### Product or reference docs

- [../documents/reference/cli_reference.md](../documents/reference/cli_reference.md) and [../documents/reference/cli_surface.md](../documents/reference/cli_surface.md) — gain `infernix init` and `infernix test init` alongside their `CommandRegistry.hs` entries (Sprint 8.2).
- [../documents/development/testing_strategy.md](../documents/development/testing_strategy.md), [../documents/development/local_dev.md](../documents/development/local_dev.md) — init-first workflow and harness create/delete lifecycle.

### Cross-references

- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — the retired tracked-schema, Helm-rendered-cluster-config, and lazy-model-bootstrap surfaces.
- [development_plan_standards.md](development_plan_standards.md) Sections U (configuration substrate) and V (host tools manifest).
