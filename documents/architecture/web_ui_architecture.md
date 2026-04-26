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

## Image Topology

`infernix` and `infernix-demo` share one Cabal library `infernix-lib` and ship in the same OCI
image. The chart workload entrypoint selects which executable runs; the same image powers
`infernix-service` (production), `infernix-edge`, the Harbor, MinIO, and Pulsar gateway pods, and
`infernix-demo`. `docker/service.Dockerfile` copies the built PureScript bundle from `web/dist/`
into that image so `infernix-demo` can serve `/`.

The repository also builds a separate web image from `web/Dockerfile`. That image packages the
same built `web/dist/` bundle together with Playwright browser dependencies and is the supported
executor for `infernix test e2e`. `infernix cluster up` still builds and Harbor-publishes that
image for the routed E2E lanes, but it is no longer deployed as a separate cluster workload
because routed `/` is served by `infernix-demo`.

## PureScript Application

- repo-owned browser application code lives under `web/src/*.purs`
- `npm --prefix web run build` regenerates `web/src/Generated/Contracts.purs`, runs `spago build`,
  and emits `web/dist/app.js` through `spago bundle --module Main --outfile dist/app.js --platform browser --bundle-type app`
- handwritten PureScript modules import generated modules from `web/src/Generated/` for shared
  types; they do not declare their own request or response types
- `web/Dockerfile` installs the npm-managed PureScript toolchain (`purescript`, `spago`, and
  `esbuild`) alongside the Playwright browser dependencies
- frontend tests use `purescript-spec` under `web/test/*.purs` and run via `spago test`
- `infernix test unit` invokes `spago test` alongside the Haskell unit suites

## Shared Contracts

- dedicated browser-contract ADTs in `src/Generated/Contracts.hs` are the source of truth for
  the PureScript request, response, engine-binding, and error types consumed by the demo UI
- `infernix internal generate-purs-contracts` emits `web/src/Generated/Contracts.purs`
- `npm --prefix web run build` invokes that codegen entrypoint before `spago build`
- generated contracts are derived through `purescript-bridge`, producing `newtype` wrappers plus
  helper functions that expose record views to handwritten frontend modules
- the generator appends the active runtime mode, request-topic, result-topic, engine-binding, and
  catalog constants together with explicit `Simple.JSON` instances used by routed `/api` decoding

## Testing

- `purescript-spec` suites cover the generated contract module shape plus the workbench view-model
  logic for selection, catalog parity, publication summary rendering, family-aware request
  guidance, and result-state rendering
- E2E coverage exhaustively hits every generated catalog entry through routed Playwright HTTP
  coverage against the real cluster edge, cross-checks routed `/api/models` against the serialized
  generated demo config, and separately exercises browser UI interaction for publication-detail
  rendering, model selection, submission, object-reference results, and the
  host-bridge-versus-cluster-demo daemon-location switch on the supported Apple host path
- the host-native and outer-container validation paths launch that Playwright suite from the same
  built web image that packages the demo bundle, and the host-native final-substrate lane reuses
  the Harbor-published web runtime image across `apple-silicon`, `linux-cpu`, and `linux-cuda`

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/purescript_policy.md](../development/purescript_policy.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
