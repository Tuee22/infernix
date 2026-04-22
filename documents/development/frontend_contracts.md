# Frontend Contracts

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define how the web application consumes Haskell-owned shared contracts.

## Contract Ownership

- Haskell ADTs own the browser-facing DTO surface and the generated demo catalog shape
- the web build invokes `infernix internal generate-web-contracts` and keeps Haskell ownership of
  the generated JavaScript contract module
- generated frontend contracts are staged under `./.build/web-generated/Generated/contracts.js` on
  the host path and `/opt/build/infernix/web-generated/Generated/contracts.js` on the supported
  outer-container path
- the build copies the runtime contract asset into `web/dist/generated/contracts.js`
- no tracked `web/generated/Generated/contracts.js` artifact remains on the supported path
- no standalone public frontend codegen command exists outside the build-owned `infernix internal generate-web-contracts` surface

## Validation

- `infernix test unit` runs the generated-contract, catalog-parity, request-shape, and result-state tests
- the web build fails when generated contracts drift from Haskell-owned source
- generated contracts expose the active runtime mode and every generated catalog entry for that mode
- catalog loading uses routed `/api/models` data rather than a generated browser-only fallback catalog
- publication-summary rendering uses the routed `/api/publication` payload rather than a hidden browser-only publication model
- host-native and outer-container build flows both regenerate the same contract module deterministically

## Cross-References

- [local_dev.md](local_dev.md)
- [testing_strategy.md](testing_strategy.md)
- [../reference/api_surface.md](../reference/api_surface.md)
