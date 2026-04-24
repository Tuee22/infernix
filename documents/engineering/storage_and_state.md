# Storage And State

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Distinguish authoritative durable state from derived build and runtime state.

## Durable State

- manual PV data under `./.data/kind/...` for every PVC-backed Helm workload, with explicit
  PV-to-PVC binding through `infernix-manual`
- MinIO objects
- Pulsar ledger state
- operator-managed PostgreSQL data and WAL state for Harbor and any dedicated service-specific
  Patroni clusters
- Harbor metadata and registry content
- host-side runtime artifact bundles under `./.data/object-store/artifacts/`
- host-side source-artifact manifests and copied or downloaded payloads under
  `./.data/object-store/source-artifacts/`
- host-side cache manifests under `./.data/object-store/manifests/`

## Derived State

- host build artifacts under `./.build/`
- container build artifacts under `/opt/build/infernix`
- runtime cache under `./.data/runtime/`
- Playwright artifacts under `./.data/test-artifacts/playwright/`

## Cross-References

- [k8s_storage.md](k8s_storage.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../architecture/overview.md](../architecture/overview.md)
- [../tools/postgresql.md](../tools/postgresql.md)
