# Frontend Contracts

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [purescript_policy.md](purescript_policy.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define how the demo PureScript application consumes Haskell-owned shared contracts.

## Contract Ownership

- dedicated browser-contract ADTs in `src/Generated/Contracts.hs` own the browser-facing contract
  surface
- `infernix internal generate-purs-contracts` emits `web/src/Generated/Contracts.purs`
- `npm --prefix web run build` invokes that codegen entrypoint before `spago build`
- handwritten PureScript modules under `web/src/*.purs` import generated modules from
  `web/src/Generated/` for shared types; they do not declare their own request or response types
- `web/src/Generated/` is rebuilt on every web build and is not tracked in version control
- no standalone public frontend codegen command exists outside `infernix internal generate-purs-contracts`
- `infernix internal generate-purs-contracts` derives those PureScript types through
  `purescript-bridge`
- the generated module also appends the active runtime constants, catalog constants, helper
  record-unwrapping functions, and explicit `Simple.JSON` instances consumed by the frontend

## Validation

- `infernix test unit` runs `spago test` (`purescript-spec`) for the generated-contract,
  catalog-parity, request-shape, and result-state suites alongside the Haskell unit suites
- the web build fails when generated contracts drift from the Haskell-owned source
- generated contracts expose the active runtime mode and every generated catalog entry for that
  mode
- the frontend decodes routed `/api` payloads through the generated `Simple.JSON` instances rather
  than through hand-authored duplicate codecs
- catalog loading uses routed `/api/models` data served by `infernix-demo` rather than a generated
  browser-only fallback catalog
- publication-summary rendering uses the routed `/api/publication` payload served by
  `infernix-demo` rather than a hidden browser-only publication model
- host-native and outer-container build flows both regenerate the same contract module
  deterministically

## Cross-References

- [purescript_policy.md](purescript_policy.md)
- [local_dev.md](local_dev.md)
- [testing_strategy.md](testing_strategy.md)
- [../reference/api_surface.md](../reference/api_surface.md)
