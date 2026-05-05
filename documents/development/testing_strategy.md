# Testing Strategy

**Status**: Supporting reference
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe operator-facing validation-lane detail and matrix coverage that support the canonical testing doctrine.

The canonical validation entrypoints, fail-fast rules, and supported boundaries live in
[../engineering/testing.md](../engineering/testing.md). This page records the implemented
mode-specific coverage, matrix behavior, and operator detail behind those canonical entrypoints.

## Validation Layers

- `infernix docs check` validates governed docs, README or plan cross-references, required CLI
  registry coverage in `documents/reference/cli_reference.md`, phase-document documentation
  sections, and forbidden retired-doctrine phrases
- `infernix test lint` validates repository hygiene, required chart or Kind or `.proto` assets, the
  repo-owned Haskell style stack, the Haskell build path, and the shared Python adapter quality
  gate via `poetry run check-code` from the shared `python/` project when adapters are present
- `infernix test unit` validates generated catalog counts and selection rules, demo-config encode
  or decode behavior, cache lifecycle, the
  protobuf-over-stdio Python worker path and adapter-command overrides, chart image or claim
  discovery, Harbor overlay emission, and the current PureScript generated-contract or workbench
  behavior via `spago test` driven by the non-deprecated runner in `web/test/Main.purs`
- `infernix test integration` validates cluster lifecycle for the active generated substrate,
  generated demo-config publication, routed demo or tool surfaces, routed inference plus cache
  endpoints, service-path request or result publication through the active topic contract,
  `cluster status`, every generated active-mode catalog entry from the mounted demo config,
  demo-ui disablement on the `linux-cpu` lane via
  `infernix internal materialize-substrate linux-cpu --demo-ui false`, and edge-port rediscovery
  on the host-native control-plane `linux-cpu` lane
- `infernix test e2e` validates the routed browser surface by comparing `/api/models` to the
  generated demo config and exercising every routed catalog entry through both the HTTP inference
  endpoint and the browser workbench
- `infernix test all` runs lint, unit, integration, and E2E in sequence for the active substrate
- the supported real-cluster `linux-gpu` integration and `test all` lanes also depend on enough
  host disk headroom for Kind image preload, Harbor-backed image publication, and Pulsar
  BookKeeper durability; low disk headroom can block `infernix-service` readiness after cluster
  creation even when the NVIDIA preflight passes

## Active-Mode Coverage Rules

- unit coverage proves generated catalog shape, selected engine metadata, request-shape helpers,
  publication-summary rendering, and object-reference result formatting for the active generated
  contract module
- `infernix test integration` serializes the active runtime mode into the generated demo config and
  publication state, then validates the routed demo API, auxiliary routed prefixes, every
  generated active-mode catalog entry, cache mutation endpoints, and the daemon request or result
  loop for the active substrate
- `infernix test integration` also validates `cluster status`, `cluster down`, and repeated
  `cluster up` behavior for the active substrate
- `infernix test integration` also validates the routed `GET /api/cache`,
  `POST /api/cache/evict`, and `POST /api/cache/rebuild` contract against manifest-backed durable
  state
- `infernix test integration` also validates that `/harbor`, `/minio/s3`, and `/pulsar/ws`
  resolve through the shared routed surface and preserve the expected rewritten-path contract
- those routed auxiliary checks prove the live Harbor, MinIO, and Pulsar routed surfaces that the
  supported Kind path publishes
- the `/pulsar/ws` contract is specific: the public prefix rewrites to Pulsar's real `/ws`
  upstream context root so routed `/pulsar/ws/v2/...` requests terminate on the WebSocket servlet
- `infernix test integration` validates the service loop by publishing a typed request through the
  configured topic helper and asserting a matching typed result appears on the configured result
  topic
- on the `linux-cpu` lane, `infernix test integration` also validates
  `infernix internal materialize-substrate linux-cpu --demo-ui false` and `9090`-first
  edge-port rediscovery on host-native control planes
- on the `linux-cpu` lane, `infernix test integration` also deletes a Harbor core pod and verifies
  Harbor-backed image pulls still work, replaces a MinIO pod after writing a sentinel file,
  restarts a Pulsar broker between two routed publish or result checks, deletes the Harbor
  PostgreSQL primary to verify failover, and compares the deterministic Harbor PostgreSQL PV
  inventory plus host-path mapping across `cluster down` plus `cluster up`
- `infernix test e2e` exercises every generated catalog entry exposed through the routed surface
  for the active substrate, compares `/api/models` against the serialized generated demo
  config, validates routed publication details from `/api/publication`, and fails if the browser
  workbench cannot render publication details, select a model, or submit one of those entries
- the Apple host-native routed E2E lane also fails if the clustered routed surface cannot keep
  `apiUpstream.mode = cluster-demo`, preserve one browser-visible base URL, and still report the
  direct Apple service lane separately through `daemonLocation = control-plane-host`
- the supported routed E2E path uses the dedicated `infernix-playwright:local` image invoked via
  `docker compose run --rm playwright`; Apple host-native flows run that compose invocation
  directly from the host CLI while Linux flows forward it from the outer container through the
  mounted host docker socket
- supported Playwright launchers clear conflicting `NO_COLOR` and `FORCE_COLOR` values from the
  child environment before Playwright starts
- changing the active runtime mode changes the generated catalog and therefore the exercised entry
  set automatically

## Cross-References

- [frontend_contracts.md](frontend_contracts.md)
- [haskell_style.md](haskell_style.md)
- [python_policy.md](python_policy.md)
- [purescript_policy.md](purescript_policy.md)
- [../engineering/testing.md](../engineering/testing.md)
- [../engineering/implementation_boundaries.md](../engineering/implementation_boundaries.md)
- [../engineering/portability.md](../engineering/portability.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
