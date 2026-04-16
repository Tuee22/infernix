# Web UI Architecture

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define the cluster-resident browser topology and the contract boundary between the
> Haskell service and the web UI.

## Topology

- the browser loads `/` from the cluster-resident webapp service
- the browser calls `/api` on the edge proxy
- the same `/api` route remains stable whether the service runs in-cluster or on the Apple host

## Shared Contracts

- Haskell types are the source of truth for request and response DTOs
- the web build generates frontend contract modules during `web/Dockerfile` execution
- the PureScript application imports generated modules rather than maintaining duplicate DTOs

## Testing

- `purescript-spec` covers generated codecs and view behavior
- Playwright runs from the same image that serves the web UI

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
