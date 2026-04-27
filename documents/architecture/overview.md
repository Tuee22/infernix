# Architecture Overview

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md)

> **Purpose**: Describe the supported local platform topology and the repository shape it drives.

## Platform Shape

`infernix` is a Kind-first local inference platform built around two repo-owned Haskell
executables sharing one Cabal library, an optional PureScript demo UI, and one governed
documentation suite.

- two Haskell executables share `infernix-lib`: `infernix` owns the production daemon, cluster
  lifecycle, validation, docs checks, and the no-HTTP production daemon; `infernix-demo` owns the
  demo HTTP API host
- production deployments accept inference work by topic subscription only; `infernix service`
  binds no HTTP listener and the cluster has no `infernix-demo` workload when the active `.dhall`
  `demo_ui` flag is off
- when the demo UI is enabled, the browser entrypoint is the shared routed surface on one
  localhost port and the demo UI is served by `infernix-demo`
- Python is restricted to per-substrate adapter packages under `python/<substrate>/adapters/`;
  the canonical quality gate is `poetry run check-code`, and all custom platform logic is Haskell
- the demo UI is PureScript built with `spago`, tested with `purescript-spec`, with generated
  frontend contracts emitted by `infernix internal generate-purs-contracts` through
  `purescript-bridge` from dedicated browser-contract ADTs
- chart assets target Harbor, MinIO, Pulsar, Envoy Gateway, and operator-managed PostgreSQL on the
  real Kind path; when the required platform commands are unavailable, `cluster up` falls back to a
  simulated substrate that still publishes the demo and portal route inventory for validation
- Harbor is always the first deployed service on a pristine cluster, and only Harbor plus
  Harbor-required backend services such as MinIO and PostgreSQL may pull from public container
  repositories before Harbor is ready
- every in-cluster PostgreSQL dependency, including services that could self-deploy PostgreSQL,
  uses an operator-managed Patroni cluster instead of a chart-managed standalone PostgreSQL path
- every PVC-backed Helm workload uses `infernix-manual`, which is backed by
  `kubernetes.io/no-provisioner`, with manually created PVs explicitly bound to the intended PVCs
- durable local state is rooted under `./.data/`

## Repository Shape

The supported repository layout is described in
[../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md) and uses these
major roots:

- `app/` and `src/` for the Haskell control plane and `infernix-lib` library
- `python/` for per-substrate adapter packages and per-substrate `pyproject.toml` files
- `web/` for the PureScript demo application built with `spago` and the Playwright E2E assets
- `chart/` and `kind/` for cluster reconciliation inputs, including the locked Harbor, Pulsar,
  MinIO, Percona PostgreSQL operator, and Envoy Gateway Helm dependency declarations
- `test/` for repository-owned validation
- `documents/` for governed documentation

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
- [../tools/postgresql.md](../tools/postgresql.md)
