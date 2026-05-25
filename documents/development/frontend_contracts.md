# Frontend Contracts

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [purescript_policy.md](purescript_policy.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define how the demo PureScript application consumes Haskell-owned shared contracts.

## Contract Ownership

- dedicated browser-contract ADTs in `src/Infernix/Web/Contracts.hs` own the browser-facing contract
  surface
- `infernix internal generate-purs-contracts` emits `web/src/Generated/Contracts.purs`
- the retired `web/src/Infernix/Web/Contracts.purs` path is not a supported generated output and
  is left untouched by the codegen command
- `npm --prefix web run build` invokes that codegen entrypoint before `spago build`
- handwritten PureScript modules under `web/src/*.purs` import generated modules from
  `web/src/Generated/` for shared types; they do not declare their own request or response types
- `web/src/Generated/` is rebuilt on every web build and is not tracked in version control
- no standalone public frontend codegen command exists outside `infernix internal generate-purs-contracts`
- `infernix internal generate-purs-contracts` derives those PureScript types through
  `purescript-bridge`
- the generated module also appends the active runtime constants, catalog constants, helper
  record-unwrapping functions, and explicit `Simple.JSON` instances consumed by the frontend

## Haskell-First Logic Discipline (Phase 7)

The durable-context demo's contract-generation pipeline carries every new ADT the demo
introduces (the Sprint 7.2 type set is landed in `src/Infernix/Web/Contracts.hs` and emitted
through `infernix internal generate-purs-contracts`), and the discipline that PureScript is
a thin renderer is a governed contract:

- the reducer, idempotency dedup, `prefixHash` chain, dispatcher rule, event construction, and
  all projection logic live only in Haskell, in the shared `infernix` library
- the browser receives typed `ConversationState` snapshots and `ConversationStatePatch` deltas
  over the WS and applies patches via trivial mechanical helpers; PureScript code never folds
  raw events
- the reducer is not codegen'd; the browser does not import it
- new browser-contract ADTs added in
  [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
  Sprint 7.2 flow through the same `purescript-bridge` pipeline as today's contracts:
  - `ConversationEvent` (server-side log entries; emitted to the browser only on opaque
    diagnostic paths, not on the standard render path)
  - `ContextMetadataEvent`, `DraftEvent`
  - `ConversationState`, `ConversationStatePatch`
  - `ContextListState`, `ContextListPatch`
  - `DraftMapState`, `DraftMapPatch`
  - `WsClientMessage`, `WsServerMessage` (server messages carry snapshots and patches, not raw
    events)
  - `ArtifactUploadRequest`, `ArtifactUploadGrant`, `ArtifactDownloadGrant`
  - `ObjectRef`, `ArtifactKind`, `ArtifactMimeType`, `ArtifactRenderDisposition`
  - newtypes for `UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`
- generated `Simple.JSON` instances stay in lockstep with Haskell `ToJSON`/`FromJSON` instances
  so both sides agree on wire format mechanically
- the May 24, 2026 generator pass extended this lockstep to every Phase 7 sum and newtype:
  string-wrapped newtypes (`UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`,
  `ArtifactMimeType`) encode as bare strings on the wire, matching the Haskell side's
  `deriving newtype (ToJSON)`; record-wrapped newtypes unwrap to their inner record;
  nullary sums emit `{"tag": "ConstructorName"}`; positional sums emit
  `{"tag": "...", "contents": ...}`; record-syntax sums spread their constructor's fields
  beside the `tag` key (matching Aeson's `TaggedObject "tag" "contents"` behavior). The
  PureScript roundtrip suite at `web/test/Infernix/Web/ContractsSpec.purs` covers 43 cases
  across every Phase 7 type to keep the lockstep mechanically enforced.

## Validation

- `infernix test unit` runs `spago test` (`purescript-spec`) for the generated-contract,
  catalog-parity, request-shape, and result-state suites alongside the Haskell unit suites
- the web build regenerates `web/src/Generated/Contracts.purs` from the Haskell-owned source on
  every run; codegen or PureScript compile failures stop the build
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
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
