# Architecture Overview

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md)

> **Purpose**: Describe the supported local platform topology and the repository shape it drives.

## Platform Shape

`infernix` is a Kind-first local inference platform built around two repo-owned Haskell
executables that share the default Cabal library exposed by the `infernix` package, an optional
PureScript demo UI, and one governed documentation suite.

- two Haskell executables share the default Cabal library exposed by the `infernix` package:
  `infernix` owns the production daemon, cluster lifecycle, validation, docs checks, and the
  no-HTTP production daemon; `infernix-demo` owns the demo HTTP API host
- production deployments accept inference work by topic subscription only; `infernix service`
  binds no HTTP listener and the cluster has no `infernix-demo` workload when the active `.dhall`
  `demo_ui` flag is off
- when the demo UI is enabled, the browser entrypoint is the shared routed surface on one
  localhost port and the demo UI is served by `infernix-demo`
- the reusable durable-context primitives that shape the demo UI and any future SPA-style app
  on the platform — event-sourced state, deterministic reducer, single-flight dispatcher,
  prefix-hash chain, presigned object storage, JWKS-backed JWT, and stateless WebSocket
  coordination — are defined in [durable_context_design.md](durable_context_design.md). The
  demo's concrete bindings (Keycloak as the IdP, `infernix/demo` topic namespace,
  `infernix-demo-objects` bucket, `/auth` / `/ws` / `/api/objects` routes, SPA views) are
  defined in [demo_app_design.md](demo_app_design.md). The supported per-pod placement —
  stateless frontend and coordinator Deployments plus a one-per-node engine Deployment — is
  codified in [daemon_topology.md](daemon_topology.md). All three are built out through
  [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
- the runtime executor produces REAL per-family output: the engine worker invokes the real engine
  for the selected binding — the Python adapter transform over a prebuilt host wheel, or a real
  native runner binary resolved from a typed `HostConfig` absolute path — fetches model weights
  lazily from the `infernix-models` MinIO bucket, and publishes a per-family real result, inline
  text for the LLM and speech families and a typed `infernix-demo-objects` object reference for the
  artifact families. Inference work still flows only over Pulsar topics across the two repo-owned
  Haskell binaries; see [daemon_topology.md](daemon_topology.md) for the role split and topic flow.
- Python is restricted to the shared adapter project under `python/`; the canonical quality gate
  is `poetry run check-code`, and all custom platform logic is Haskell
- the demo UI is PureScript built with `spago`, tested with `purescript-spec`, with generated
  frontend contracts emitted by `infernix internal generate-purs-contracts` through
  `purescript-bridge` from dedicated browser-contract ADTs
- chart assets target Harbor, MinIO, Pulsar, Envoy Gateway, and operator-managed PostgreSQL on the
  real Kind path; supported workflows fail fast when the required platform commands are unavailable
- `bootstrap/*.sh` entrypoints are substrate launchers only: they reconcile host prerequisites and
  build or enter the active `infernix` launcher, while the binary owns Kind, Kubernetes, manifest
  deployment, cluster workload image pulls, Harbor publication, and lifecycle status
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

- `app/` and `src/` for the Haskell control plane and the default library exposed by the
  `infernix` package
- `python/` for the shared adapter package and shared `pyproject.toml`
- `web/` for the PureScript demo application built with `spago` and the Playwright E2E assets
- `chart/` and `kind/` for cluster reconciliation inputs, including the locked Harbor, Pulsar,
  MinIO, Percona PostgreSQL operator, and Envoy Gateway Helm dependency declarations
- `test/` for repository-owned validation
- `documents/` for governed documentation

Platform images carry native Linux container architecture end to end: Apple Silicon publishes and
runs `linux/arm64` natively, `linux-cpu` publishes and runs the native Linux host architecture
(`linux/amd64` or `linux/arm64`), and `linux-gpu` publishes and runs `linux/amd64`. Development
and validation do not use cross-architecture emulation. See
[runtime_modes.md](runtime_modes.md) for the canonical substrate → architecture mapping.

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [durable_context_design.md](durable_context_design.md)
- [demo_app_design.md](demo_app_design.md)
- [daemon_topology.md](daemon_topology.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
- [../tools/postgresql.md](../tools/postgresql.md)
