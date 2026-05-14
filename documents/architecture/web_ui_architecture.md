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
- manual inference always enters through that clustered `infernix-demo` surface, but the daemon
  lane behind it is substrate-specific: `apple-silicon` enters the cluster `infernix-service`
  daemon first and then bridges host batches through Pulsar into the host-native
  `infernix service` executor, while `linux-cpu` and `linux-gpu` execute from the cluster daemon
- `/api/publication` exposes that distinction through `daemonLocation`,
  `inferenceExecutorLocation`, `hostInferenceBatchTopic`, and `inferenceDispatchMode`
- the visible catalog comes from the generated active-mode demo catalog rather than a
  hand-maintained UI allowlist

## Image Topology

`infernix` and `infernix-demo` share the default Cabal library exposed by the `infernix` package
and ship in the same runtime image family on the cluster path. The chart workload entrypoint
selects which executable runs where that executable is deployed.

On Apple Silicon, the cluster deploys `infernix-demo`, `infernix-service`, and the support-service
stack, while the canonical Apple inference executor remains a host-native `infernix service`
process that consumes host batches. On Linux substrates, both the demo workload and inference
execution run from the cluster-resident substrate image.

On Linux, the substrate image owns the web build prerequisites and the baked `web/dist/` bundle.
Routed Playwright execution lives in a separate dedicated `infernix-playwright:local` image built
from `docker/playwright.Dockerfile`. On Apple Silicon, the host CLI invokes
`docker compose run --rm playwright` directly against that dedicated image; on Linux substrates,
the outer container forwards the same compose invocation through the mounted host docker socket.

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
  submission, object-reference results, daemon-location reporting, inference-executor reporting,
  and inference-dispatch-mode reporting
- supported routed E2E uses the dedicated `infernix-playwright:local` container on Apple and Linux
  alike, invoked via `docker compose run --rm playwright`; Apple host-native orchestration reaches
  it directly while the Linux outer-container path forwards the call through the mounted host
  docker socket

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/purescript_policy.md](../development/purescript_policy.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
