# PureScript Policy

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [frontend_contracts.md](frontend_contracts.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define the PureScript toolchain, the test framework, and the contract derivation
> model that govern the demo UI in this repository.

## Scope

The demo UI is the only browser-facing surface in this repository. It is implemented in
PureScript. JavaScript exists as compiled output under `web/dist/`; source-level `.js` or `.mjs`
files are not part of the supported browser application. The remaining `.js` or `.mjs` files under
`web/playwright/` and `web/test/run_playwright_matrix.mjs` are test-harness assets.

The demo UI is served by the `infernix-demo` Haskell binary and gated by the active `.dhall`
`demo_ui` flag. Production deployments leave the flag off and the cluster has no demo UI workload.

## Toolchain

- `web/package.json` owns the npm-distributed toolchain and scripts
- Node.js 22 or newer is required for the supported PureScript or Playwright toolchain
- `web/spago.yaml` declares the PureScript package set and dependencies
- `purs` is the PureScript compiler
- `spago build` compiles the source tree under `web/src/*.purs`
- `spago bundle --module Main --outfile dist/app.js --platform browser --bundle-type app` produces
  the static demo bundle in `web/dist/`
- `spago test` runs the `purescript-spec` suites under `web/test/*.purs`
- `web/test/Main.purs` uses the non-deprecated `purescript-spec` runner APIs and preserves
  non-zero exits explicitly instead of relying on deprecated `runSpec` entrypoints
- the npm-managed PureScript toolchain is installed either in `web/node_modules/` on the host
  path or in the active Linux substrate image build, both on Node.js 22+
- routed Playwright E2E runs from the host on Apple Silicon, from the active Linux substrate image
  when the platform toolchain is available, and otherwise through the local npm runner; supported
  Playwright launchers sanitize conflicting `NO_COLOR` and `FORCE_COLOR` values before spawning
  the child process

## Source Layout

```text
web/
├── package.json
├── spago.yaml
├── src/
│   ├── Main.purs
│   ├── Infernix/Web/Workbench.purs
│   └── Generated/        (build-time generated contracts, not tracked)
├── test/
│   └── Main.purs
├── playwright/
└── package-lock.json
```

Rules:

- `web/src/Generated/` is not tracked in version control; it is rebuilt by
  `infernix internal generate-purs-contracts` on every web build
- handwritten PureScript modules under `web/src/*.purs` import generated modules from
  `web/src/Generated/` for shared types; they do not declare their own request or response types
- `web/test/*.purs` modules use `purescript-spec` and run via `spago test`

## Contract Derivation

Frontend types are generated from Haskell-owned DTO and catalog records.

- `infernix internal generate-purs-contracts` is the single supported codegen entrypoint
- generated PureScript modules live in `web/src/Generated/` and carry the request, response,
  engine-binding, and catalog constants needed by the current demo UI
- the codegen path derives the PureScript contract types through `purescript-bridge` from
  dedicated browser-contract ADTs in `src/Infernix/Web/Contracts.hs`
- the generated module also appends the active runtime constants, catalog constants, helper
  unwrappers for the bridge-generated `newtype` surface, and explicit `Simple.JSON` instances

## Test Framework

`purescript-spec` is the authoritative contract gate for the demo UI.

- `infernix test unit` invokes `spago test` alongside the Haskell unit suites
- contract suites assert that generated PureScript modules expose the active runtime constants and
  generated catalog expected by the routed demo surface
- contract suites also prove that the bridge-generated `newtype` surface stays aligned with the
  handwritten workbench helpers that unwrap record views
- view-level suites assert catalog order, selection, publication summary rendering, and result
  rendering behavior
- the Node-based unit-test path stays on non-deprecated runner entrypoints and fails explicitly
  when the `purescript-spec` summary reports a failing suite
- the existing Playwright DOM selectors are preserved across the PureScript views; if a selector
  cannot be preserved, the Playwright spec is updated in the same change

## Cross-References

- [python_policy.md](python_policy.md)
- [haskell_style.md](haskell_style.md)
- [frontend_contracts.md](frontend_contracts.md)
- [testing_strategy.md](testing_strategy.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
