# PureScript Policy

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [frontend_contracts.md](frontend_contracts.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define the PureScript toolchain, the test framework, and the contract derivation
> model that govern the demo UI in this repository.

## Scope

The demo UI is the only browser-facing surface in this repository. It is implemented in
PureScript. JavaScript may exist only as compiled output of `spago bundle-app` under `web/dist/`;
no source-level `.js` or `.mjs` files are part of the supported web surface.

The demo UI is served by the `infernix-demo` Haskell binary (a separate executable from
`infernix`, sharing the `infernix-lib` Cabal library) and gated by the active `.dhall` `demo_ui`
flag. Production deployments leave the flag off and the cluster has no demo UI workload at all.

## Toolchain

- `web/spago.yaml` declares the PureScript package set and dependencies
- `purs` is the PureScript compiler
- `spago build` compiles the source tree under `web/src/*.purs`
- `spago bundle-app` produces the static demo bundle in `web/dist/`
- `spago test` runs the `purescript-spec` suites under `web/test/*.purs`
- `web/Dockerfile` installs `purs` and `spago` alongside the Playwright browser dependencies; the
  same image hosts the demo UI and runs the routed Playwright E2E suite

## Source Layout

```text
web/
├── spago.yaml
├── src/
│   ├── Main.purs
│   ├── Workbench.purs
│   ├── Catalog.purs
│   ├── ...
│   └── Generated/        (purescript-bridge output, build-time generated, not tracked)
├── test/
│   ├── Spec.purs
│   ├── ContractsSpec.purs
│   ├── CatalogSpec.purs
│   └── ...
├── playwright/
└── Dockerfile
```

Rules:

- `web/src/Generated/` is not tracked in version control; it is rebuilt by
  `infernix internal generate-purs-contracts` on every web build
- handwritten PureScript modules under `web/src/*.purs` import generated modules from
  `web/src/Generated/` for shared types; they do not declare their own request or response types
- `web/test/*.purs` modules use `purescript-spec` and run via `spago test`

## Contract Derivation

Frontend types are derived from Haskell ADTs in `src/Infernix/Demo/Api.hs` via `purescript-bridge`.

- `infernix internal generate-purs-contracts` is the single supported codegen entrypoint; it is
  invoked by the `infernix-lib` build and again from `web/Dockerfile` so the web image build is
  self-contained
- the source-of-truth Haskell records live in `src/Infernix/Demo/Api.hs` (preferred over
  `proto-lens`-generated types directly so the bridge surface stays clean and free of
  protobuf-specific scaffolding)
- generated PureScript modules live in `web/src/Generated/` and carry the same record names and
  field shapes as their Haskell originators
- no standalone public frontend codegen command exists outside `infernix internal generate-purs-contracts`

## Test Framework

`purescript-spec` is the authoritative contract gate for the demo UI.

- `infernix test unit` invokes `spago test` alongside the Haskell unit suites
- contract suites assert that generated PureScript modules round-trip the same JSON shapes the
  Haskell `infernix-demo` server emits
- view-level suites assert that the rendered catalog matches the active generated demo catalog,
  that the model picker selects entries by id, that submission round-trips through the
  `infernix-demo` `/api/inference` handler, and that result rendering handles inline payloads and
  object references uniformly
- the existing Playwright DOM selectors (`web/playwright/inference.spec.js` and equivalents) are
  preserved across the PureScript views; if a selector cannot be preserved, the Playwright spec
  is updated in the same change

## Cross-References

- [python_policy.md](python_policy.md)
- [haskell_style.md](haskell_style.md)
- [frontend_contracts.md](frontend_contracts.md)
- [testing_strategy.md](testing_strategy.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
