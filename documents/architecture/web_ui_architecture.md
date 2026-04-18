# Web UI Architecture

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md](../../DEVELOPMENT_PLAN/phase-5-web-ui-and-shared-types.md)

> **Purpose**: Define the browser topology and the contract boundary between the Haskell service
> and the web UI.

## Topology

- the browser loads `/` from the routed web surface
- the browser calls `/api` on the same routed edge port
- the browser calls `/api/publication` on that same edge port to surface mode-stable publication details, including API-upstream mode and routed-upstream health
- on the supported Kind path, `/` is served by the cluster-resident web workload and `/api` is served by the cluster-resident service workload through the repo-owned Python edge proxy by default
- on the supported Apple host-native path, the same `/api` route can be repointed to the host bridge while the browser stays on the same edge base URL
- the visible catalog comes from the generated active-mode demo catalog rather than a hand-maintained UI allowlist
- the browser workbench renders the generated catalog in generated order and does not maintain a hidden filtered subset on the supported path

## Shared Contracts

- Haskell types are the source of truth for request and response DTOs
- the web build generates frontend contract modules during the build flow
- generated frontend contracts stage under the active build root and are copied into `web/dist/generated/contracts.js` for runtime use
- the build stages generated contracts and the final `web/dist/` bundle atomically so frontend unit and E2E flows can build concurrently without partial output races
- generated contracts expose the active runtime mode and the generated catalog entries for that mode

## Testing

- unit tests prove the generated contract module shape plus the workbench view-model logic for selection, catalog parity, publication summary rendering, family-aware request guidance, and result-state rendering
- E2E coverage exhaustively hits every generated catalog entry through routed Playwright HTTP
  coverage against the real cluster edge and separately exercises browser UI interaction for
  publication-detail rendering, model selection, submission, object-reference results, and the
  host-bridge-versus-cluster-service daemon-location switch on the supported Apple host path
- the host-native and outer-container validation paths launch that Playwright suite from the same
  built web image that serves the UI, and the host-native final-substrate lane serves
  that UI from the Harbor-published web runtime image across `apple-silicon`, `linux-cpu`, and
  `linux-cuda`

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
