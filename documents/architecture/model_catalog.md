# Model Catalog

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the authoritative model catalog contract that the service and UI both consume.

## Contract

The model catalog is Haskell-owned typed configuration that lists every registered model the user
may target through the API or web UI.

Each entry includes:

- stable model identifier
- display label
- model family
- request schema identifier
- response schema identifier
- artifact manifest location
- runtime execution mode

## Rules

- the service rejects invalid catalog entries during startup
- the browser never carries a hand-maintained duplicate catalog schema
- runtime-local caches derive from catalog and durable artifact metadata

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../reference/api_surface.md](../reference/api_surface.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
