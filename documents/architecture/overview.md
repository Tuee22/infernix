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

- `app/` and `src/` for the Haskell control plane
- `web/` for the web application and E2E assets
- `chart/` and `kind/` for cluster reconciliation inputs, including the locked Harbor, Pulsar,
  Bitnami MinIO, Percona PostgreSQL operator, and ingress-nginx Helm dependency declarations
- `test/` for repository-owned validation
- `documents/` for governed documentation

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
- [../tools/postgresql.md](../tools/postgresql.md)
