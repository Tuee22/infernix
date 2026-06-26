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

## Identity

The webapp validates the Keycloak JWT (`Infernix.Auth.Jwt.verifyAndParseJwt`: RS256 + JWKS, plus issuer,
audience, expiry, and not-before) and takes `UserId` from the `sub` claim. `sub` is stable across login,
logout, and credential changes, so it is the durable namespacing key. No endpoint trusts a client-supplied
user id, full object key, or topic name.

## Namespacing (derived server-side from `sub`)

| Resource | Key / topic | Derivation | Authorization |
|---|---|---|---|
| MinIO objects | `users/<sub>/contexts/<ctx>/{uploads,generated}/<name>` | `Infernix.Objects.Layout.uploadObjectKey` | `pathBelongsToUser` (trailing-slash prefix `users/<sub>/`) |
| Conversation | `demo.conversation.<sub>.<ctx>` | `Infernix.Conversation.Topic.conversationTopicName` | `topicBelongsToUser` |
| Context / draft metadata | `demo.user.<sub>.{contexts,drafts}` | `Infernix.Conversation.Topic.{contextsMetadataTopicName,draftsMetadataTopicName}` | `topicBelongsToUser` |

The `users/<sub>/` prefix carries a trailing slash, so a user whose `sub` is a prefix of another's (e.g.
`userA` vs `userAB`) cannot match the other's objects.

## Enforcement — single trust boundary

- **Objects**: the webapp derives the key from `sub` server-side and rejects any out-of-scope key with
  HTTP 403 before any MinIO operation (upload, download, and the Sprint 7.26 `DELETE`). The Sprint
  7.26 `GET /api/objects/list` enumerates only the caller's `users/<sub>/` prefix, derived
  server-side — the caller never names a prefix. The browser reaches MinIO only through the webapp
  (see [object_access_doctrine.md](object_access_doctrine.md)).
- **Chat**: the browser reaches Pulsar only through the webapp's own WebSocket (`/ws`); topic names embed
  the authenticated `sub`, so a request for another user's `contextId` resolves to the caller's own
  (empty) topic — never the other user's data.
- **Lifecycle**: account deletion reaps strictly per-`sub` — MinIO under `userPrefix`, Pulsar via
  `topicBelongsToUser`.

## Current Status

Chat isolation is already sound (the webapp mediates Pulsar; topics embed the verified `sub`). Object
isolation now has the same single-door shape: **Phase 7 Sprint 7.25** made the webapp object-proxy the
only path to MinIO (the browser-direct presigned-URL path and the `/minio/s3` gateway route are removed),
and `Infernix.Objects.Layout.sanitizeFilename` neutralizes the client-supplied display name before it
becomes part of a server-derived key. Every object operation re-authorizes through `pathBelongsToUser` on
the verified `sub`, so cross-user access is impossible by construction. This is code-side closed; the
`linux-cpu` plus chosen-accelerator real per-user attestation is the remaining
[Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md) residual.

## Validation

- The reopened Phase 7 Sprint 7.25 integration and e2e prove a user's JWT receives HTTP 403 on another
  user's object prefix (list / get / put / delete) and cannot read another user's chat context. Real
  per-user attestation is recorded under
  [Wave M](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).
