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
- the browser calls `/api`, `/api/publication`, `/api/cache`, and `/api/objects` on the same
  routed edge port; all of them are served by `infernix-demo`
- manual inference always enters through that clustered `infernix-demo` surface, but the daemon
  lane behind it is substrate-specific: the coordinator consumes request topics and forwards to
  the configured batch topic; Linux engines consume in-cluster `inference.batch.<mode>` topics,
  while Apple host-native engines consume `inference.batch.apple-silicon.host`
- `/api/publication` exposes that distinction through `daemonLocation`,
  `hostInferenceBatchTopic`, and `inferenceDispatchMode`
- the visible catalog comes from the generated active-mode demo catalog rather than a
  hand-maintained UI allowlist

## Image Topology

`infernix` and `infernix-demo` share the default Cabal library exposed by the `infernix` package
and ship in the same runtime image family on the cluster path. The chart workload entrypoint
selects which executable runs where that executable is deployed.

On Apple Silicon, the cluster deploys `infernix-demo`, `infernix-coordinator`, and the
support-service stack, while the canonical Apple inference executor remains a host-native
`infernix service` process that consumes host batches. On Linux substrates, the demo workload,
coordinator, and engine run from the cluster-resident substrate image.

On Linux, the substrate image owns the web build prerequisites, the baked `web/dist/` bundle,
Playwright system packages, and the browser engines. Routed Playwright execution runs inside that
same image with `npm --prefix web exec -- playwright test`. On Apple Silicon, host-native routed
E2E uses host `npm exec` with the same typed fixture and is covered by the Apple cohort
validation batch.

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
  uses host `npm exec` with the same typed fixture and is covered by the Apple cohort validation
  batch

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
  `Artifacts.purs`, `ArtifactTransport.purs`, `Auth.purs`, `Browser.purs`,
  `DomEvents.purs`, `WebSocket.purs`, `Router.purs`; all consume generated contracts from
  `web/src/Generated/` and apply server-sent state patches mechanically without reimplementing
  business rules
- `Chat.purs` and `Artifacts.purs` include DOM renderer functions for the durable-context shell;
  `Main.purs` mounts those renderers from the routed SPA root. Playwright now covers the routed
  Keycloak self-registration path through the OIDC authorization-code redirect, routed WebSocket
  valid/malformed-token handshake behavior, expired-token rejection, typed malformed-frame
  `ServerError` handling, and `/api/objects` grant plus same-user MinIO byte roundtrip on the
  clean rebuilt Linux GPU launcher. The browser shell also owns the PKCE redirect completion,
  local context creation,
  browser upload to MinIO, bounded text/JSON previews, inline image/audio/video rendering,
  browser-native PDF URL wiring, and MIDI / MusicXML / generic download-only states through
  presigned grants. Successful browser uploads now send `ClientRecordUpload` so the backend
  appends a typed `ConversationUserUploadEvent` to the conversation log. The Chat form now sends
  `ClientSubmitPrompt` over the active WebSocket and includes the current context's uploaded
  `ObjectRef`s in `promptUserUploads`; `ClientHello` starts per-user context/draft streams;
  the active context sends `ClientSubscribeContext`; and submitted prompts return through inbound
  `ServerConversationPatch` append frames. Playwright asserts the rendered new-context dialog can
  open and close without sending `ClientCreateContext` or adding a local context, then select a
  supported catalog row before context creation; the outbound `ClientCreateContext` carries that
  model id, and the broker-backed context-list patch plus active left-rail item preserve it.
  The routed WebSocket test also sends a `ClientCreateContext` with an absent catalog model id
  and asserts the backend returns typed `ServerError` code `unknown-model`.
  The full browser flow now also sends `ClientRenameContext` and `ClientSoftDeleteContext`,
  asserts the broker-backed `ServerContextListPatch` upserts, and verifies the left rail renders
  the renamed title plus soft-deleted state.
  Playwright also asserts browser-uploaded artifacts
  return through inbound `ConversationUserUploadEvent` append patches and render in the active
  Chat conversation with display name plus MIME type. Playwright now also asserts context-list
  snapshots/patches, draft upsert/remove patches, local logout, same-browser re-login, and
  refresh-token WebSocket re-auth through a new `ClientHello`. The SPA session layer reconnects
  after unexpected WebSocket close, resends `ClientHello` and the active
  `ClientSubscribeContext`, receives a fresh conversation snapshot, and Playwright submits a
  prompt through the reconnected socket. Cancel events now resolve their target prompt in the
  queued-count projection; the browser cancel action sends `ClientCancelPrompt` for the latest
  unresolved server-backed prompt id, and Playwright verifies the inbound cancel append patch plus
  rendered cancel entry. The SPA stores only the active context id/model id in session storage,
  resubscribes that context after a reload login, and Playwright proves draft text is restored
  after both forced WebSocket reconnect and full page reload through the broker-backed draft
  stream. The routed flow also submits a second prompt before the first unresolved prompt
  resolves, asserts the rendered `2 queued prompts` warning, and targets the second canonical
  prompt id in the cancel lifecycle.
  The remaining Sprint 7.15 browser work is Playwright coverage for the per-model smoke matrix
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
