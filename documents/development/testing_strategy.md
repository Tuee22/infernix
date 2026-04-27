# Testing Strategy

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe the canonical validation surface and the responsibility of each test layer.

## Validation Layers

- `infernix docs check` validates governed docs, plan metadata, and required cross-document phrases
- `infernix test lint` validates repository hygiene, chart or Kind or `.proto` asset presence, the
  repo-owned Haskell style stack, the Haskell build path, and the active substrate's Python adapter
  quality gate via `poetry run check-code` when adapters are present
- `infernix test unit` validates matrix rendering, deterministic runtime behavior, protobuf schema
  round-trip coverage, engine-runner metadata, command-override behavior, authoritative
  source-artifact selection, local-file plus direct-upstream source-artifact materialization, the
  split cache or worker runtime modules, the typed protobuf-over-stdio adapter handshake for the
  Python-native bindings, and the current web contract or view behavior via `spago test`
- `infernix test integration` validates lifecycle, generated demo-config publication,
  serialized-catalog execution, routed publication metadata, Haskell-worker dispatch across the
  process-isolated Python adapter boundary, service-path cache lifecycle, the no-HTTP production
  daemon contract, local object-store durability, edge-port rediscovery, and the
  simulated-versus-real substrate publication surface
- `infernix test e2e` validates the demo-only browser-facing surface through exhaustive catalog
  coverage, serialized-catalog cross-checks, and browser UI interaction against the routed surface
- `infernix test all` runs the complete repository suite; the default matrix exercises Apple and
  Linux CPU when no explicit runtime-mode override is supplied and auto-includes Linux CUDA when the
  active control-plane surface passes the NVIDIA preflight contract

## Active-Mode Coverage Rules

- unit coverage proves generated catalog shape, selected engine bindings, request-shape rendering,
  publication-summary rendering, and object-reference result formatting for the active runtime mode
- `infernix test integration` exercises every generated catalog entry from the serialized generated
  demo config for the active runtime mode, validates the published config artifact, and separately
  validates `cluster status`, `cluster down`, repeated `cluster up`, and `9090`-first edge-port
  rediscovery
- `infernix test integration` also validates the routed `GET /api/cache`,
  `POST /api/cache/evict`, and `POST /api/cache/rebuild` contract against manifest-backed durable
  state
- `infernix test integration` also validates that `/harbor`, `/minio/s3`, and `/pulsar/ws`
  resolve through the shared routed surface and preserve the expected rewritten-path contract
- `infernix test integration` validates the filesystem-backed topic simulation by publishing a
  protobuf request file and asserting a protobuf result appears on the configured result topic
- the host-native integration lane also validates that `/api` can move to the Apple host bridge
  without changing the browser-visible base URL
- `infernix test e2e` exercises every generated catalog entry exposed through the routed surface
  for the active runtime mode, compares `/api/models` against the serialized generated demo config,
  validates routed publication details from `/api/publication`, and fails if the browser workbench
  cannot render publication details, select a model, or submit one of those entries
- the host-native routed E2E lane also fails if the workbench cannot stay on the same base URL
  while `/api` resolves through the Apple host bridge
- the Apple host-native validation path launches routed Playwright from the host install; the Linux
  path launches it from the active substrate image when the platform toolchain is available and
  otherwise falls back to the local npm runner
- changing the active runtime mode changes the generated catalog and therefore the exercised entry
  set automatically

## Cross-References

- [frontend_contracts.md](frontend_contracts.md)
- [haskell_style.md](haskell_style.md)
- [python_policy.md](python_policy.md)
- [purescript_policy.md](purescript_policy.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
