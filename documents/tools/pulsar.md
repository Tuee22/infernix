# Pulsar

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported Pulsar role in the local platform.

## Rules

- Pulsar is the durable event transport for inference lifecycle events and the **production
  inference request surface**: the active `.dhall` names the request and result topics that the
  production daemon will own, and `infernix service` already keeps that daemon on a no-HTTP
  surface. The real Pulsar consumer loop is still open work
- repo-owned `.proto` schemas define the payload contract for Pulsar topics; the same schemas
  feed both `proto-lens`-generated Haskell bindings and auto-generated Python protobuf modules
  consumed by `python/adapters/<engine>/`
- Pulsar topic payloads use protobuf schema support rather than opaque byte arrays
- the production daemon uses cluster-local Pulsar networking in cluster mode and edge-routed
  access in the Apple host-bridge mode
- because Pulsar is first enabled in the final Harbor-backed Helm phase, `cluster up` forces the
  upstream bookkeeper and cluster-initialization jobs there so the required metadata exists
  before broker and proxy readiness gates apply on clean or repeat reconciles
- the admin surface is exposed through `/pulsar/admin` (via the Haskell
  `infernix-pulsar-gateway` workload)
- the WebSocket surface is exposed through `/pulsar/ws` (via the Haskell
  `infernix-pulsar-gateway` workload)

## Production Inference Subscription Contract

The active `.dhall` config carries the production inference fields consumed by `infernix service`:

- `request_topics : List Text` — Pulsar topics the production daemon subscribes to for inbound
  inference requests
- `result_topic : Text` — the Pulsar topic the production daemon publishes results to
- `engines : List EngineBinding` — the engines available to the worker dispatch layer; entries
  whose binding is Python-native cause the Haskell worker to cross the Python adapter process
  boundary through the named engine-specific adapter directory and the typed
  protobuf-over-stdio worker contract
- the optional `demo_ui : Bool` flag toggles the `infernix-demo` workload (production deployments
  leave it off)

The general production use case is: deploy one or more `infernix` instances via a `.dhall`
config; request inference by publishing protobuf messages to the configured request topics;
`infernix` knows what to do with results from the same config.

## Cross-References

- [minio.md](minio.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
