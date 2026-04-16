# Edge Routing

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Define the one-port edge routing contract for browser and host-consumed services.

## Route Inventory

- `/` serves the web UI
- `/api` serves the Haskell API
- `/harbor` serves the Harbor portal
- `/minio/console` serves the MinIO console
- `/minio/s3` serves the MinIO S3 API
- `/pulsar/admin` serves the Pulsar admin surface
- `/pulsar/ws` serves the Pulsar WebSocket surface

## Rules

- the CLI chooses one available localhost port during cluster bring-up
- the chosen port is recorded under `./.data/runtime/edge-port.json`
- Apple host-native runtime flows use edge-routed MinIO and Pulsar access

## Cross-References

- [object_storage.md](object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [../tools/pulsar.md](../tools/pulsar.md)
