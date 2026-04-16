# Testing Strategy

**Status**: Authoritative source
**Referenced by**: [local_dev.md](local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Describe the canonical validation surface and the responsibility of each test layer.

## Validation Layers

- `infernix docs check` validates governed docs and plan cross-links
- `infernix test lint` validates formatting, linting, and warning policy
- `infernix test unit` validates Haskell and PureScript units
- `infernix test integration` validates lifecycle, storage, and service integration behavior
- `infernix test e2e` validates the browser surface
- `infernix test all` runs the complete repository suite

## Rules

- the CLI owns the supported validation entrypoints
- unit coverage protects typed contracts and deterministic logic
- integration coverage protects lifecycle and durable-state behavior
- E2E coverage runs from the same image that serves the web UI

## Cross-References

- [frontend_contracts.md](frontend_contracts.md)
- [haskell_style.md](haskell_style.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
