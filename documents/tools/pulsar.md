# Pulsar

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported production topic contract and the current daemon
> implementation.

## Rules

- Pulsar is the durable event-transport shape for the production inference surface: the active
  `.dhall` names the request and result topics that the production daemon owns, and
  `infernix service` keeps that daemon on a no-HTTP surface
- repo-owned `.proto` schemas define the payload contract for request and result topics; the same
  schemas feed both `proto-lens`-generated Haskell bindings and auto-generated Python protobuf
  modules consumed by the active substrate adapter package
- when `INFERNIX_PULSAR_WS_BASE_URL` and `INFERNIX_PULSAR_ADMIN_URL` are set, the production
  daemon uses Pulsar's WebSocket producer or consumer endpoints plus the admin schema API for the
  configured topics
- when those endpoints are intentionally absent in unit-level harnesses, the daemon can exercise
  the repo-local topic spool rooted at `./.data/runtime/pulsar/`: request topics and the result
  topic become directories, and schema registration is mirrored as marker files under
  `./.data/runtime/pulsar/schemas/`
- result payloads remain protobuf messages in both cases: over Pulsar topics on supported cluster
  paths, and as `.pb` files under the harness-local `result_topic` directory on the repo-local
  topic spool
- because Pulsar is first enabled in the final Harbor-backed Helm phase, `cluster up` forces the
  upstream bookkeeper and cluster-initialization jobs there on the real Kind path
- the final chart keeps `pulsar.proxy.configData.webSocketServiceEnabled: "true"` so the internal
  daemon transport and the routed `/pulsar/ws` surface both terminate on Pulsar's real WebSocket
  endpoints
- when the daemon starts before Pulsar admin is fully ready, schema registration retries until the
  admin API accepts the requested topic schemas

## Routed Surfaces

<!-- infernix:route-registry:pulsar:start -->
- `/pulsar/admin` -> `infernix-infernix-pulsar-proxy:80`; rewrites to upstream `/`
- `/pulsar/ws` -> `infernix-infernix-pulsar-proxy:80`; rewrites to upstream `/ws`
<!-- infernix:route-registry:pulsar:end -->

- the supported Gateway contract targets Pulsar's real `/admin/v2` and `/ws` surfaces; current
  integration still accepts the direct `infernix-demo` `rewrittenPath` compatibility payloads for
  these probes when they appear, and Phase 6 tracks tightening that validation to the real
  upstream-only behavior

## Production Inference Subscription Contract

The active `.dhall` config carries the production inference fields consumed by `infernix service`:

- `request_topics : List Text` - topic names the production daemon watches for inbound inference
  requests
- `result_topic : Text` - the topic the production daemon writes results to
- `engines : List EngineBinding` - the engines available to the worker dispatch layer; Python-native
  bindings execute through the named adapter entrypoints in the active substrate project
- the optional `demo_ui : Bool` flag toggles the `infernix-demo` workload (production deployments
  leave it off)

## Cross-References

- [minio.md](minio.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
