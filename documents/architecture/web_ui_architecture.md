# Web UI Architecture

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define the demo UI topology, the contract boundary between the routed demo HTTP
> surface owned by `infernix-demo` and the PureScript browser application, and the gating model
> that keeps the demo surface absent from production deployments.

## Topology

The demo UI is a separate workload (`infernix-demo`) gated by the active `.dhall` `demo_ui` flag.
When the flag is off, the cluster has no `infernix-demo` pod and no demo HTTP surface at all.

When the flag is on:

- the browser loads `/` from the `infernix-demo` workload through the published routed surface
- the browser calls `/api`, `/api/publication`, `/api/cache`, and `/objects/<key>` on the same
  routed edge port; all of them are served by `infernix-demo`
- the visible catalog comes from the generated active-mode demo catalog rather than a
  hand-maintained UI allowlist

## Image Topology

`infernix` and `infernix-demo` share one Cabal library `infernix-lib` and ship in the same runtime
image on the real cluster path. The chart workload entrypoint selects which executable runs.

On Linux, the substrate image also owns the web build prerequisites and the routed Playwright
executor. There is no separate web-only image on the supported path. On Apple Silicon, the host
CLI orchestrates the same container-owned Playwright executor against the clustered routed surface.

## PureScript Application

- repo-owned browser application code lives under `web/src/*.purs`
- `npm --prefix web run build` regenerates `web/src/Generated/Contracts.purs`, runs `spago build`,
  and emits `web/dist/app.js`
- handwritten PureScript modules import generated modules from `web/src/Generated/` for shared
  types; they do not declare their own request or response types
- frontend tests use `purescript-spec` under `web/test/*.purs` and run via `spago test`
- `infernix test unit` invokes `spago test` alongside the Haskell unit suites

## Shared Contracts

- dedicated browser-contract ADTs in `src/Infernix/Web/Contracts.hs` are the source of truth for the
  PureScript request, response, engine-binding, and error types consumed by the demo UI
- `infernix internal generate-purs-contracts` emits `web/src/Generated/Contracts.purs`
- `npm --prefix web run build` invokes that codegen entrypoint before `spago build`
- the generator appends active runtime constants, catalog constants, and explicit `Simple.JSON`
  instances used by routed `/api` decoding

## Testing

- `purescript-spec` suites cover the generated contract module shape plus the workbench view-model
  logic for selection, catalog parity, publication summary rendering, family-aware request
  guidance, and result-state rendering
- E2E coverage exhaustively hits every generated catalog entry through the routed surface and
  separately exercises browser UI interaction for publication-detail rendering, model selection,
  submission, object-reference results, and daemon-location reporting
- supported routed E2E uses a container-owned Playwright executor on Apple and Linux alike

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/purescript_policy.md](../development/purescript_policy.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
