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
- the current production daemon implements the topic contract as a filesystem-backed simulation
  rooted at `./.data/runtime/pulsar/`: request topics and the result topic are directories, and
  schema registration is represented by marker files under `./.data/runtime/pulsar/schemas/`
- result payloads are protobuf messages written to the configured `result_topic` directory after
  the worker finishes execution
- because Pulsar is first enabled in the final Harbor-backed Helm phase, `cluster up` forces the
  upstream bookkeeper and cluster-initialization jobs there on the real Kind path
- the admin surface is exposed through `/pulsar/admin`
- the WebSocket surface is exposed through `/pulsar/ws`

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
