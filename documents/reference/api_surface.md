# API Surface

**Status**: Authoritative source
**Referenced by**: [cli_reference.md](cli_reference.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the stable browser-facing API surface.

## Endpoints

- `GET /api/models` lists registered models
- `GET /api/models/:modelId` returns model metadata and request-shape information
- `POST /api/inference` submits a manual inference request
- `GET /api/inference/:requestId` returns the latest result

## Rules

- request validation uses Haskell-owned model metadata
- invalid requests return typed user-facing errors
- large outputs are returned as typed object references

## Cross-References

- [web_portal_surface.md](web_portal_surface.md)
- [../architecture/model_catalog.md](../architecture/model_catalog.md)
- [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md)
