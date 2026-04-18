# Model Catalog

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the authoritative model catalog contract that the service and UI both consume.

## Contract

The model catalog is Haskell-owned typed configuration derived from the README matrix.

- the service registry owns one entry for every README matrix row
- `cluster up` selects the active runtime mode, chooses the selected engine for each supported row,
  and emits `infernix-demo-<mode>.dhall`
- the generated file is then published into `ConfigMap/infernix-demo-config` for cluster-resident consumers

## Entry Shape

Each generated entry includes:

- matrix-row identity
- stable model identifier
- display label and workload family
- artifact or format type
- reference model metadata and download URL
- selected engine for the active runtime mode
- request shape metadata used by the API, UI, and tests
- runtime-lane metadata such as GPU requirement and lane identifier

## Rules

- the generated catalog, not a hidden UI-only allowlist, is the source of truth for the browser-visible catalog
- the generated catalog records the selected engine exactly as chosen from the README matrix
- runtime-local caches derive from generated catalog and durable artifact metadata
- switching runtime modes changes the generated catalog and selected engine bindings without changing route structure

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../reference/api_surface.md](../reference/api_surface.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
