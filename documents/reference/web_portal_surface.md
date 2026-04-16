# Web Portal Surface

**Status**: Authoritative source
**Referenced by**: [api_surface.md](api_surface.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the browser-visible routes and workbench behavior exposed through the edge proxy.

## Routes

- `/` loads the manual inference workbench
- `/harbor` loads the Harbor portal
- `/minio/console` loads the MinIO console
- `/pulsar/admin` loads the Pulsar admin surface

## Workbench Behavior

- the user can browse any registered model
- the user can submit a manual inference request through `/api`
- the UI renders typed validation and result states

## Cross-References

- [api_surface.md](api_surface.md)
- [../engineering/edge_routing.md](../engineering/edge_routing.md)
- [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md)
