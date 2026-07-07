# Tenant Isolation Doctrine

**Status**: Authoritative source
**Referenced by**: [demo_app_design.md](demo_app_design.md), [daemon_topology.md](daemon_topology.md), [object_access_doctrine.md](object_access_doctrine.md), [../tools/keycloak.md](../tools/keycloak.md), [../tools/minio.md](../tools/minio.md), [../engineering/object_storage.md](../engineering/object_storage.md), [../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](../../DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

> **Purpose**: Define how each authenticated user's content — MinIO objects and chat conversations — is
> isolated from every other user: the Keycloak `sub` is the canonical identity, all namespacing is derived
> server-side from it, and a single server-side trust boundary authorizes every operation.

## TL;DR

- The Keycloak JWT `sub` claim is the canonical per-user identity. It is extracted from a
  cryptographically verified token and is the only source of caller identity — the client never names its
  own user.
- Every per-user resource is namespaced by `sub`, **derived server-side**: MinIO objects under
  `users/<sub>/contexts/<ctx>/…`; Pulsar topics `demo.conversation.<sub>.<ctx>` and
  `demo.user.<sub>.{contexts,drafts}`.
- Isolation is enforced at a single server-side trust boundary (the webapp / coordinator), on every
  operation, via `pathBelongsToUser` (objects) and `topicBelongsToUser` (chat). Cross-user access is
  impossible by construction, not by browser-side discipline.
- This doctrine governs the **per-user** dimension only. The orthogonal **admin vs. user** dimension —
  which cluster-wide surfaces require the `infernix-admin` realm role — is owned by
  [access_control_doctrine.md](access_control_doctrine.md).

## Identity

The webapp validates the Keycloak JWT (`Infernix.Auth.Jwt.verifyAndParseJwt`: RS256 + JWKS, plus issuer,
audience, expiry, and not-before) and takes `UserId` from the `sub` claim. `sub` is stable across login,
logout, and credential changes, so it is the durable namespacing key. No endpoint trusts a client-supplied
user id, full object key, or topic name.

## Namespacing (derived server-side from `sub`)

| Resource | Key / topic | Derivation | Authorization |
|---|---|---|---|
| MinIO objects | `users/<sub>/contexts/<ctx>/{uploads,generated}/<name>` | `Infernix.Objects.Layout.uploadObjectKey` for uploads; generated-object targets derived by the coordinator/worker from the same verified `sub` + context | `pathBelongsToUser` (trailing-slash prefix `users/<sub>/`) |
| Conversation | `demo.conversation.<sub>.<ctx>` | `Infernix.Conversation.Topic.conversationTopicName` | `topicBelongsToUser` |
| Context / draft metadata | `demo.user.<sub>.{contexts,drafts}` | `Infernix.Conversation.Topic.{contextsMetadataTopicName,draftsMetadataTopicName}` | `topicBelongsToUser` |

The `users/<sub>/` prefix carries a trailing slash, so a user whose `sub` is a prefix of another's (e.g.
`userA` vs `userAB`) cannot match the other's objects.

## Enforcement — single trust boundary

- **Objects**: the webapp derives the key from `sub` server-side and rejects any out-of-scope key with
  HTTP 403 before any MinIO operation (upload, download, and the Sprint 7.26 `DELETE`). The Sprint
  7.26 `GET /api/objects/list` enumerates only the caller's `users/<sub>/` prefix, derived
  server-side — the caller never names a prefix. The browser reaches MinIO only through the webapp
  (see [object_access_doctrine.md](object_access_doctrine.md)). Engine-generated artifacts must use a
  Haskell-supplied generated-object target under the same user/context prefix; adapter-local or native
  generated keys are not a supported isolation boundary.
- **Chat**: the browser reaches Pulsar only through the webapp's own WebSocket (`/ws`); topic names embed
  the authenticated `sub`, so a request for another user's `contextId` resolves to the caller's own
  (empty) topic — never the other user's data.
- **Lifecycle**: account deletion reaps strictly per-`sub` — MinIO under `userPrefix`, Pulsar via
  `topicBelongsToUser`.

Phase 9 Sprint 9.7 adds an orthogonal **IAM-layer** boundary behind this server-side check: when
`cluster.minio.stsPerUser` is enabled, the object-proxy exchanges the shared root MinIO credential
for a short-lived MinIO STS credential scoped by an inline session policy to the caller's
`users/<sub>/` prefix before each object operation, so the shared root credential is no longer the
sole isolation. `pathBelongsToUser` on the verified `sub` stays the first-line gate; the scoped
credential is a second, defense-in-depth boundary. See
[access_control_doctrine.md](access_control_doctrine.md).

## Current Status

Chat isolation is already sound (the webapp mediates Pulsar; topics embed the verified `sub`). Browser
object isolation now has the same single-door shape: **Phase 7 Sprint 7.25** made the webapp
object-proxy the only browser path to MinIO (the browser-direct presigned-URL path and the `/minio/s3`
gateway route are removed), and `Infernix.Objects.Layout.sanitizeFilename` neutralizes the
client-supplied display name before it becomes part of a server-derived key. Every browser object
operation re-authorizes through `pathBelongsToUser` on the verified `sub`, so browser-originated
cross-user access is rejected by construction.

The June 2026 audit reopened generated artifact isolation as **Phase 7 Sprint 7.28**. Closure now
threads a generated-object target derived from the verified `sub` and `contextId` before
dispatch, makes Python adapters and native process runners consume only that target, and makes the
result bridge reject raw or cross-user generated object refs. Wave N closed the full selected
`linux-gpu` plus `linux-cpu` cohort validation on 2026-06-30.

## Validation

- Phase 7 Sprint 7.25 integration and e2e prove a user's JWT receives HTTP 403 on another user's object
  prefix (list / get / put / delete) and cannot read another user's chat context.
- Phase 7 Sprint 7.28 unit and integration-build validation proves generated artifact output-prefix
  derivation and cross-user result-bridge rejection; Wave N closes the full selected `linux-gpu` plus
  `linux-cpu` routed real-output gate.
