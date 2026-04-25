# Frontend Contracts

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [purescript_policy.md](purescript_policy.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define how the demo PureScript application consumes Haskell-owned shared contracts.

## Contract Ownership

- Haskell ADTs in `src/Infernix/Demo/Api.hs` own the browser-facing DTO surface and the generated
  demo catalog shape (preferred over `proto-lens`-generated types directly so the bridge surface
  stays clean and free of protobuf-specific scaffolding)
- the `infernix-lib` build invokes `infernix internal generate-purs-contracts`, which uses
  `purescript-bridge` to emit PureScript modules into `web/src/Generated/`
- `web/Dockerfile` invokes the same codegen entrypoint so the web image build is self-contained
- handwritten PureScript modules under `web/src/*.purs` import generated modules from
  `web/src/Generated/` for shared types; they do not declare their own request or response types
- `web/src/Generated/` is rebuilt on every web build and is not tracked in version control
- no standalone public frontend codegen command exists outside `infernix internal generate-purs-contracts`

## Validation

- `infernix test unit` runs `spago test` (`purescript-spec`) for the generated-contract,
  catalog-parity, request-shape, and result-state suites alongside the Haskell unit suites
- the web build fails when generated contracts drift from the Haskell-owned source ADTs in
  `src/Infernix/Demo/Api.hs`
- generated contracts expose the active runtime mode and every generated catalog entry for that
  mode
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
