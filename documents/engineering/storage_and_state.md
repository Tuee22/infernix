# Storage And State

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Distinguish authoritative durable state from derived build and runtime state.

## Durable State

- manual PV data under `./.data/kind/...`
- MinIO objects
- Pulsar ledger state
- Harbor metadata and registry content

## Derived State

- host build artifacts under `./.build/`
- container build artifacts under `/opt/build/infernix`
- runtime cache under `./.data/runtime/`
- Playwright artifacts under `./.data/test-artifacts/playwright/`

## Cross-References

- [k8s_storage.md](k8s_storage.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../architecture/overview.md](../architecture/overview.md)
