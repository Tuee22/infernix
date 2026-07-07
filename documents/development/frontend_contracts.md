# Frontend Contracts

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [purescript_policy.md](purescript_policy.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define how the demo PureScript application consumes Haskell-owned shared contracts.

## Contract Ownership

- dedicated browser-contract ADTs in `src/Infernix/Web/Contracts.hs` own the browser-facing contract
  surface
- `infernix internal generate-purs-contracts` emits `web/src/Generated/Contracts.purs`
- `npm --prefix web run build` invokes that codegen entrypoint before `spago build`
- handwritten PureScript modules under `web/src/*.purs` import generated modules from
  `web/src/Generated/` for shared types; they do not declare their own request or response types
- `web/src/Generated/` is rebuilt on every web build and is not tracked in version control
- no standalone public frontend codegen command exists outside `infernix internal generate-purs-contracts`
- `infernix internal generate-purs-contracts` derives those PureScript types through
  `purescript-bridge`
- the generated module also appends the active runtime constants, catalog constants, helper
  record-unwrapping functions, and explicit `Simple.JSON` instances consumed by the frontend

## Haskell-First Logic Discipline

The durable-context demo's contract-generation pipeline carries every demo ADT (the type set
in `src/Infernix/Web/Contracts.hs` is emitted through `infernix internal generate-purs-contracts`),
and the discipline that PureScript is a thin renderer is a governed contract:

- the reducer, idempotency dedup, `prefixHash` chain, dispatcher rule, event construction, and
  all projection logic live only in Haskell, in the shared `infernix` library
- the browser receives typed `ConversationState` snapshots and `ConversationStatePatch` deltas
  over the WS and applies patches via trivial mechanical helpers; PureScript code never folds
  raw events
- the reducer is not codegen'd; the browser does not import it
- browser-contract ADTs defined in
  [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)
  flow through the same `purescript-bridge` pipeline as the rest of the contracts:
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
- object-access grant minting is Haskell-owned and stays on the server side of the trust
  boundary. The presigned-URL helpers and the `pathBelongsToUser` scope check live in the
  `infernix` library, never in PureScript; the browser holds no MinIO credential and mints no
  grant of its own. The browser receives typed object references (`ObjectRef`) and
  drives upload/download through the webapp's `/api/objects` endpoints rather than receiving a
  presigned MinIO URL — the webapp reads and writes MinIO server-side. See
  [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md) and
  [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md).
- generated `Simple.JSON` instances stay in lockstep with Haskell `ToJSON`/`FromJSON` instances
  so both sides agree on wire format mechanically
- the generator pipeline extends this lockstep to every Phase 7 sum and newtype:
  string-wrapped newtypes (`UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`,
  `ArtifactMimeType`) encode as bare strings on the wire, matching the Haskell side's
  `deriving newtype (ToJSON)`; record-wrapped newtypes unwrap to their inner record;
  nullary sums emit `{"tag": "ConstructorName"}`; positional sums emit
  `{"tag": "...", "contents": ...}`; record-syntax sums spread their constructor's fields
  beside the `tag` key (matching Aeson's `TaggedObject "tag" "contents"` behavior). The
  PureScript roundtrip suite at `web/test/Infernix/Web/ContractsSpec.purs` exercises
  encode/decode roundtrips and wire-shape assertions across every Phase 7 type to keep the
  lockstep mechanically enforced.

**Current Status.** Implemented (Phase 7 Sprint 7.25; Phase 3 Sprint 3.13 removed the `/minio/s3`
route + `presignPublicEndpoint`). The browser receives only object refs and the webapp performs
every MinIO read/write server-side; the grant carries no presigned URL. Wave M closed the browser
object-proxy evidence; Wave N closed Phase 7 Sprint 7.28 generated artifact object ownership.

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
- [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)
- [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md)
