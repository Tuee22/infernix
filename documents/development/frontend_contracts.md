# Frontend Contracts

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define how the web application consumes Haskell-owned shared contracts.

## Contract Ownership

- Haskell ADTs own the browser-facing DTO surface
- build-generated PureScript modules are the only supported shared-type path
- no standalone `infernix codegen purescript` command exists

## Validation

- `infernix test unit` runs the PureScript contract and view tests
- the web build fails when generated contracts drift from Haskell-owned source

## Cross-References

- [local_dev.md](local_dev.md)
- [testing_strategy.md](testing_strategy.md)
- [../reference/api_surface.md](../reference/api_surface.md)
