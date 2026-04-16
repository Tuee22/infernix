# Architecture Overview

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md)

> **Purpose**: Describe the supported local platform topology and the repository shape it drives.

## Platform Shape

`infernix` is a Kind-first local inference platform built around one repo-owned control plane, one
cluster-resident web application, and one governed documentation suite.

- the Haskell executable `infernix` owns service runtime, cluster lifecycle, validation, and docs checks
- the browser entrypoint is always the edge proxy on one localhost port
- the web UI is always served from a cluster workload
- Harbor, MinIO, and Pulsar are mandatory local platform services
- durable storage is rooted under `./.data/`

## Repository Shape

The supported repository layout is described in
[../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md) and uses these
major roots:

- `app/` and `src/` for the Haskell control plane
- `web/` for the web application and E2E assets
- `chart/` and `kind/` for cluster reconciliation inputs
- `test/` for repository-owned validation
- `documents/` for governed documentation

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
