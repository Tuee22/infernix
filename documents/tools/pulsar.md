# Pulsar

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported Pulsar role in the local platform.

## Rules

- Pulsar is the durable event transport for inference lifecycle events on the routed service path
- repo-owned `.proto` schemas define the payload contract for Pulsar topics
- Pulsar topic payloads use protobuf schema support rather than opaque byte arrays
- the routed service path uses cluster-local Pulsar networking in cluster mode and edge-routed
  access in the Apple host-bridge mode
- because Pulsar is first enabled in the final Harbor-backed Helm phase, `cluster up` forces the
  upstream bookkeeper and cluster-initialization jobs there so the required metadata exists before
  broker and proxy readiness gates apply on clean or repeat reconciles
- the admin surface is exposed through `/pulsar/admin`
- the WebSocket surface is exposed through `/pulsar/ws`

## Cross-References

- [minio.md](minio.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../engineering/storage_and_state.md](../engineering/storage_and_state.md)
