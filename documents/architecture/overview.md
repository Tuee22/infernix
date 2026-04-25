# Architecture Overview

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md)

> **Purpose**: Describe the supported local platform topology and the repository shape it drives.

## Platform Shape

`infernix` is a Kind-first local inference platform built around two repo-owned Haskell
executables sharing one Cabal library, an optional PureScript demo UI, and one governed
documentation suite.

- two Haskell executables share `infernix-lib`: `infernix` owns the production daemon, cluster
  lifecycle, edge proxy, gateway pods, Pulsar inference dispatcher, validation, and docs checks;
  `infernix-demo` owns the demo HTTP API host
- production deployments accept inference work by Pulsar subscription only; `infernix service`
  (production) binds no HTTP listener and the cluster has no `infernix-demo` workload when the
  active `.dhall` `demo_ui` flag is off
- when the demo UI is enabled, the browser entrypoint is the Haskell edge proxy on one localhost
  port and the demo UI is served by the `infernix-demo` workload
- Python is restricted to `python/adapters/<engine>/` (Poetry-managed; mypy strict, black check,
  ruff strict run in every adapter container build); all custom platform logic is Haskell
- the demo UI is PureScript built with `spago`, tested with `purescript-spec`, with frontend types
  derived from Haskell ADTs in `src/Infernix/Demo/Api.hs` via `purescript-bridge`
- Harbor, MinIO, Pulsar, and operator-managed PostgreSQL are the local platform services
- Harbor is always the first deployed service on a pristine cluster, and only Harbor plus
  Harbor-required backend services such as MinIO and PostgreSQL may pull from public container
  repositories before Harbor is ready
- once Harbor is ready, every later non-Harbor workload or add-on pulls only from Harbor-backed
  image references
- every in-cluster PostgreSQL dependency, including services that could self-deploy PostgreSQL,
  uses an operator-managed Patroni cluster instead of a chart-managed standalone PostgreSQL path
- every PVC-backed Helm workload uses `infernix-manual`, which is backed by
  `kubernetes.io/no-provisioner`, with manually created PVs explicitly bound to the intended PVCs
- durable storage is rooted under `./.data/`

## Repository Shape

The supported repository layout is described in
[../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md) and uses these
major roots:

- `app/` (entry points for `infernix` and `infernix-demo`) and `src/` for the Haskell control
  plane and `infernix-lib` library
- `python/` for engine-adapter Python under `python/adapters/<engine>/`, governed by one
  repo-root `python/pyproject.toml` with Poetry
- `web/` for the PureScript demo application built with `spago` and the Playwright E2E assets
- `chart/` and `kind/` for cluster reconciliation inputs, including the locked Harbor, Pulsar,
  Bitnami MinIO, Percona PostgreSQL operator, and ingress-nginx Helm dependency declarations
- `test/` for repository-owned validation
- `documents/` for governed documentation

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
- [../tools/postgresql.md](../tools/postgresql.md)
