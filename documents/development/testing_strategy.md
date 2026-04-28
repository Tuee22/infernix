# Testing Strategy

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe the canonical validation surface and the responsibility of each test layer.

## Validation Layers

- `infernix docs check` validates governed docs, README or plan cross-references, required CLI
  registry coverage in `documents/reference/cli_reference.md`, phase-document documentation
  sections, and forbidden retired-doctrine phrases
- `infernix test lint` validates repository hygiene, required chart or Kind or `.proto` assets, the
  repo-owned Haskell style stack, the Haskell build path, and the shared Python adapter quality
  gate via `poetry run check-code` from the shared `python/` project when adapters are present
- `infernix test unit` validates runtime-mode catalog counts and selection rules, CLI
  `--runtime-mode` parsing, demo-config encode or decode behavior, cache lifecycle, the
  protobuf-over-stdio Python worker path and adapter-command overrides, chart image or claim
  discovery, Harbor overlay emission, and the current PureScript generated-contract or workbench
  behavior via `spago test`
- `infernix test integration` validates cluster lifecycle across the selected runtime-mode set,
  generated demo-config publication, routed demo or tool surfaces, routed inference plus cache
  endpoints, service-path request or result publication through the filesystem-backed Pulsar
  simulation, `cluster status`, every generated active-mode catalog entry from the mounted demo
  config, demo-ui disablement on the `linux-cpu` lane, and edge-port rediscovery on the
  host-native `linux-cpu` lane
- `infernix test e2e` validates the routed browser surface by comparing `/api/models` to the
  generated demo config and exercising every routed catalog entry through both the HTTP inference
  endpoint and the browser workbench
- `infernix test all` runs lint, unit, integration, and E2E in sequence; without an explicit
  `--runtime-mode`, the current integration test binary enumerates all three runtime modes, while
  E2E includes `linux-cuda` only when the NVIDIA preflight contract passes
- the supported real-cluster `linux-cuda` integration and `test all` lanes also depend on enough
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
  loop for each selected runtime mode
- `infernix test integration` also validates `cluster status`, `cluster down`, and repeated
  `cluster up` behavior for the selected runtime modes
- `infernix test integration` also validates the routed `GET /api/cache`,
  `POST /api/cache/evict`, and `POST /api/cache/rebuild` contract against manifest-backed durable
  state
- `infernix test integration` also validates that `/harbor`, `/minio/s3`, and `/pulsar/ws`
  resolve through the shared routed surface and preserve the expected rewritten-path contract
- those routed auxiliary checks accept either the simulated rewrite payloads or the live upstream
  Harbor, MinIO, and Pulsar responses when the suite is running on a real Kind cluster
- the `/pulsar/ws` contract is specific: the public prefix rewrites to Pulsar's real `/ws`
  upstream context root so routed `/pulsar/ws/v2/...` requests terminate on the WebSocket servlet
- `infernix test integration` validates the filesystem-backed topic simulation by publishing a
  protobuf request file and asserting a protobuf result appears on the configured result topic
- on the `linux-cpu` lane, `infernix test integration` also validates `INFERNIX_DEMO_UI=false`
  and `9090`-first edge-port rediscovery on host-native control planes
- on the non-simulated `linux-cpu` lane, `infernix test integration` also deletes a Harbor core
  pod and verifies Harbor-backed image pulls still work, replaces a MinIO pod after writing a
  sentinel file, restarts a Pulsar broker between two routed publish or result checks, deletes the
  Harbor PostgreSQL primary to verify failover, and compares the deterministic Harbor PostgreSQL PV
  inventory plus host-path mapping across `cluster down` plus `cluster up`
- `infernix test e2e` exercises every generated catalog entry exposed through the routed surface
  for each selected runtime mode, compares `/api/models` against the serialized generated demo
  config, validates routed publication details from `/api/publication`, and fails if the browser
  workbench cannot render publication details, select a model, or submit one of those entries
- the Apple host-native routed E2E lane also fails if the workbench cannot stay on the same base
  URL while `/api` resolves through the host-native `infernix-demo serve` bridge
- the Apple host-native validation path launches routed Playwright from the host install; the Linux
  path launches it from the active substrate image when the platform toolchain is available and
  otherwise falls back to the local npm runner
- changing the active runtime mode changes the generated catalog and therefore the exercised entry
  set automatically
- pass `--runtime-mode` when a single predictable validation lane is required

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
