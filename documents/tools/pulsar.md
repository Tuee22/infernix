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
- when those endpoints are absent, the daemon falls back to the repo-local filesystem simulation
  rooted at `./.data/runtime/pulsar/`: request topics and the result topic are directories, and
  schema registration is mirrored as marker files under `./.data/runtime/pulsar/schemas/`
- result payloads remain protobuf messages in both modes: over Pulsar topics on the real path, and
  as `.pb` files under the simulated `result_topic` directory on the fallback path
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

- on the real cluster path, the public `/pulsar/admin` route preserves Pulsar's `/admin/v2`
  surface and an ordinary HTTP `GET /pulsar/ws/v2/...` reaches the real WebSocket servlet and
  returns `405 Method Not Allowed` instead of a route-miss `404`

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
