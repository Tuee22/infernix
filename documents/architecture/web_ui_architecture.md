# Web UI Architecture

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define the demo UI topology, the contract boundary between the routed demo HTTP
> surface owned by `infernix-demo` and the PureScript browser application, and the gating model
> that keeps the demo surface absent from production deployments.

## Topology

The demo UI is a separate cluster workload (`infernix-demo`) gated by the active `.dhall`
`demo_ui` flag. When the flag is off, the cluster has no `infernix-demo` pod and no demo HTTP
surface at all; production deployments leave the flag off and accept inference work via Pulsar
subscription only.

When the flag is on:

- the browser loads `/` from the `infernix-demo` workload through the Haskell edge proxy
- the browser calls `/api`, `/api/publication`, `/api/cache`, and `/objects/<key>` on the same
  routed edge port; all of them are served by `infernix-demo`
- on the supported Apple host-native path, the same surface is provided by
  `infernix-demo serve --dhall PATH --port N` against a host-side `.dhall`; the browser stays on
  the same edge base URL whether the demo host runs in the cluster or on the host
- the visible catalog comes from the generated active-mode demo catalog rather than a hand-maintained
  UI allowlist
- the browser workbench renders the generated catalog in generated order and does not maintain a
  hidden filtered subset on the supported path
- routed catalog or publication failures surface as unavailable live state rather than browser-only
  fallback data

## Two-Binary Image Topology

`infernix` and `infernix-demo` share one Cabal library `infernix-lib` and ship in the same OCI
image. The chart workload entrypoint selects which executable runs; the same image powers
`infernix-service` (production), `infernix-edge`, the Harbor, MinIO, and Pulsar gateway pods, and
`infernix-demo`. The PureScript bundle lives in a separate web image built from `web/Dockerfile`
that also carries Playwright browser dependencies; the `infernix-demo` workload mounts that
bundle from `web/dist/`.

## PureScript Application

- repo-owned browser application code lives under `web/src/*.purs` and is built by `spago build`
  plus `spago bundle-app` into `web/dist/`
- handwritten PureScript modules import generated modules from `web/src/Generated/` for shared
  types; they do not declare their own request or response types
- `web/Dockerfile` installs `purs` and `spago` alongside the Playwright browser dependencies
- frontend tests use `purescript-spec` under `web/test/*.purs` and run via `spago test`
- `infernix test unit` invokes `spago test` alongside the Haskell unit suites

## Shared Contracts

- Haskell ADTs in `src/Infernix/Demo/Api.hs` are the source of truth for request and response
  types
- the `infernix-lib` build invokes `infernix internal generate-purs-contracts`, which uses
  `purescript-bridge` to emit PureScript modules into `web/src/Generated/`
- `web/Dockerfile` invokes the same codegen entrypoint so the web image build is self-contained
- generated contracts expose the active runtime mode and the generated catalog entries for that
  mode

## Testing

- `purescript-spec` suites cover the generated contract module shape plus the workbench view-model
  logic for selection, catalog parity, publication summary rendering, family-aware request
  guidance, and result-state rendering
- E2E coverage exhaustively hits every generated catalog entry through routed Playwright HTTP
  coverage against the real cluster edge, cross-checks routed `/api/models` against the serialized
  generated demo config, and separately exercises browser UI interaction for publication-detail
  rendering, model selection, submission, object-reference results, and the
  host-bridge-versus-cluster-service daemon-location switch on the supported Apple host path
- the host-native and outer-container validation paths launch that Playwright suite from the same
  built web image that serves the demo UI, and the host-native final-substrate lane serves that UI
  from the Harbor-published web runtime image across `apple-silicon`, `linux-cpu`, and `linux-cuda`

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/purescript_policy.md](../development/purescript_policy.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
