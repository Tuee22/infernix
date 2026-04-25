# Testing Strategy

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe the canonical validation surface and the responsibility of each test layer.

## Validation Layers

- `infernix docs check` validates governed docs, plan metadata, and required cross-document phrases
- `infernix test lint` validates repository hygiene, chart or Kind or `.proto` asset presence,
  Helm dependency or lint or render or claim-discovery closure, the repo-owned Haskell style
  stack, the Haskell build path, and (when `python/adapters/` is present) the strict Python
  adapter quality gate via `tools/python_quality.sh` (mypy strict, black check, ruff strict)
- `infernix test unit` validates matrix rendering, deterministic runtime behavior, protobuf schema
  round-trip coverage, engine-runner metadata, engine command-override behavior, authoritative
  source-artifact selection, local-file plus direct-upstream source-artifact materialization, and
  PureScript demo UI behavior via `spago test` (`purescript-spec` suites under `web/test/*.purs`)
  covering generated contracts, catalog parity, request-shape rendering, and result-state
  rendering
- the host-side test helpers materialize the durable bundle plus source-artifact-manifest
  contract through Haskell test fixtures under `test/unit/`
- `infernix test integration` validates lifecycle, generated demo-config publication,
  serialized-catalog execution, routed publication metadata (when the demo surface is enabled),
  Haskell-worker execution dispatching to per-engine Python adapters where the bound engine is
  Python-native, service-path cache lifecycle, Pulsar schema publication, the production Pulsar
  inference subscription contract (no HTTP listener bound on the production daemon), MinIO
  durability, operator-managed PostgreSQL readiness or primary failover or PVC rebinding, HA
  recovery, edge-port rediscovery, and real `linux-cuda` device visibility on supported hosts
- `infernix test e2e` validates the demo-only browser-facing surface (when the demo flag is on)
  through exhaustive catalog coverage, serialized-catalog cross-checks, and browser UI interaction
  against the real cluster edge while launching Playwright from the same web image that serves
  the demo UI
- `infernix test all` runs the complete repository suite; the default validation matrix exercises
  Apple and Linux CPU when no explicit runtime-mode override is supplied and auto-includes Linux
  CUDA when the active control-plane surface passes the NVIDIA preflight contract, while the
  host-native final-substrate lane reuses the Harbor-published web runtime image across the
  runtime matrix
- the supported validation contract exercises the Haskell worker dispatch layer, the
  engine-specific runner defaults plus any adapter-specific command overrides, durable runtime
  bundles, engine-specific source-artifact manifests, and the `linux-cuda` Kind path when the
  host satisfies the documented NVIDIA preflight contract
- the outer-container integration and E2E lanes also assume the host exposes enough inotify
  instances for mount-bearing Kind nodes; the validated Ubuntu flow uses
  `fs.inotify.max_user_instances >= 1024`

## Active-Mode Coverage Rules

- unit coverage proves the generated catalog shape, selected engine bindings, request-shape rendering, publication-summary rendering, and object-reference result formatting for the active runtime mode
- `infernix test integration` exercises every generated catalog entry from the serialized generated demo config for the active runtime mode, validates the in-cluster `ConfigMap`, and separately validates `cluster status`, `cluster down`, repeated `cluster up`, and `9090`-first edge-port rediscovery on both supported control-plane contexts
- `infernix test integration` also validates the routed `GET /api/cache`, `POST /api/cache/evict`, and `POST /api/cache/rebuild` contract against manifest-backed durable state
- `infernix test integration` also validates that `/harbor`, `/minio/s3`, and `/pulsar/ws` resolve through the current cluster-resident gateway workloads on the shared edge port
- `infernix test integration` also validates that any operator-managed PostgreSQL cluster required by
  the active platform release reports ready Patroni members, elects a replacement primary after
  pod deletion, and keeps its claims bound through `infernix-manual` across repeat cluster
  lifecycle runs, including Harbor bootstrap self-healing when one startup replica remains
  `Running` but fails Patroni readiness beyond the supported grace window
- `infernix test integration` also validates that `/api/publication` reports `workerExecutionMode = process-isolated-engine-workers`, `workerAdapterMode = engine-specific-runner-defaults`, `artifactAcquisitionMode = engine-ready-artifact-manifests`, and that `/api/cache` exposes durable artifact-bundle URIs plus durable source-artifact manifest URIs rooted in the runtime bucket together with engine-adapter availability, authoritative source-artifact URI or kind metadata, and the selected artifact inventory used by the current durable bundle
- the host-native integration lane also validates that `/api` can move to the Apple host bridge without changing the browser-visible edge entrypoint
- the outer-container integration lane keeps host-published Kind and edge ports on `127.0.0.1`
  while reaching the cluster through the private Docker `kind` network and the internal kubeconfig
- `infernix test integration` on the Apple host-native final substrate validates Pulsar protobuf schema registration, MinIO-persisted runtime results or manifests, and Harbor or MinIO or Pulsar or PostgreSQL HA recovery, including Harbor portal continuity after Patroni primary replacement
- `infernix test e2e` exercises every generated catalog entry exposed through the routed surface for the active runtime mode, compares `/api/models` against the serialized generated demo config returned by `GET /api/demo-config`, validates routed publication details from `/api/publication`, and fails if the browser workbench cannot render publication details, select a model, or submit one of those entries through the routed cluster edge
- the host-native routed E2E lane also fails if the workbench cannot stay on the same base URL while `/api` resolves through the Apple host bridge
- the host-native and outer-container control-plane paths both delegate `infernix test e2e` browser execution to the same web image that serves `/` rather than the control-plane image, and the host-native final-substrate lane reuses the Harbor-published web runtime image for that browser execution path across `apple-silicon`, `linux-cpu`, and `linux-cuda`
- on the outer-container E2E lane, that web image runs on the private Docker `kind` network and
  targets the control-plane node's routed edge port `30090` instead of a host-gateway alias
- the automated unit, integration, and E2E entrypoints exercise the engine-specific worker runner
  defaults when no adapter-specific override is configured, and they can still forward
  `INFERNIX_ENGINE_COMMAND_*` overrides when supported-host engine commands are installed
- changing the active runtime mode changes the generated catalog and therefore the exercised entry set automatically
- when no explicit runtime-mode override is supplied, the default validation path repeats the exhaustive integration and E2E path across `apple-silicon` and `linux-cpu` and auto-includes `linux-cuda` on hosts whose active control-plane surface satisfies the NVIDIA preflight contract
- the supported host-native final-substrate and outer-container control-plane lanes reuse that same exhaustive coverage contract rather than a reduced smoke subset

## Cross-References

- [frontend_contracts.md](frontend_contracts.md)
- [haskell_style.md](haskell_style.md)
- [python_policy.md](python_policy.md)
- [purescript_policy.md](purescript_policy.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
