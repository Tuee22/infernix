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

On Linux, the substrate image owns the web build prerequisites, the baked `web/dist/` bundle,
Playwright system packages, and the browser engines. Routed Playwright execution runs inside that
same image with `npm --prefix web exec -- playwright test`. On Apple Silicon, the host-native
routed-E2E executor refactor is deferred and surfaces an explicit diagnostic until the Apple
validation pass lands it.

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

- `purescript-spec` suites cover the generated contract module shape plus the SPA view-model
  logic for selection, catalog parity, publication summary rendering, family-aware request
  guidance, and result-state rendering
- E2E coverage exhaustively hits every generated catalog entry through the routed surface and
  separately exercises browser UI interaction for publication-detail rendering, model selection,
  submission, object-reference results, daemon-location reporting, inference-executor reporting,
  and inference-dispatch-mode reporting
- supported routed E2E on Linux uses Playwright from the substrate image; Apple host-native E2E
  is deferred to the Apple validation pass

## Durable Context Surface

When the durable-context demo lands (Phase 7), the same `infernix-demo` workload also serves
the multi-user durable-context application. The product-agnostic primitives this binding is
built on live at [durable_context_design.md](durable_context_design.md); the demo's concrete
bindings live at [demo_app_design.md](demo_app_design.md). Topology delta:

- new authenticated WebSocket endpoint at `/ws` carries chat, drafts, context list/create/delete,
  progress, and artifact-ready notifications; demo-gated
- Keycloak provides identity at `/auth`; demo-gated; see [../tools/keycloak.md](../tools/keycloak.md)
- HTTP endpoint `/api/objects` mints presigned MinIO PUT/GET URLs for artifact upload and
  download; bytes never traverse the demo backend; demo-gated
- the demo `Service` sets `sessionAffinity: None` so any replica can host any WS connection;
  WS pods use Pulsar `Reader` subscriptions for per-WS fan-out and named `Failover`
  subscriptions for the per-context inference dispatcher
- new handwritten PureScript modules under `web/src/Infernix/Web/`: `Chat.purs`,
  `Artifacts.purs`, `Auth.purs`, `WebSocket.purs`, `Router.purs`; all consume generated
  contracts from `web/src/Generated/` and apply server-sent state patches mechanically without
  reimplementing business rules
- the supported manual-inference dispatch closes through the durable-context Chat surface and
  WebSocket transport; the previous direct `POST /api/inference` request/poll surface is
  retired from the supported contract per
  [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
- the routed browser surface terminates at the frontend pod (`infernix-demo`); the coordinator
  and engine pods are not directly addressable from the browser. The supported per-pod
  placement is codified in [daemon_topology.md](daemon_topology.md)

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [durable_context_design.md](durable_context_design.md)
- [demo_app_design.md](demo_app_design.md)
- [daemon_topology.md](daemon_topology.md)
- [../tools/keycloak.md](../tools/keycloak.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/purescript_policy.md](../development/purescript_policy.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
