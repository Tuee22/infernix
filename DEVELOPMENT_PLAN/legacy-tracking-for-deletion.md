# Infernix Legacy Tracking For Deletion

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Provide the explicit ledger of obsolete paths, duplicate guidance, and future
> cleanup work in `infernix`.

## Pending Removal

| Location | Why it is slated for removal | Owning phase or sprint |
|----------|------------------------------|------------------------|
| `tools/service_server.py` single-process compatibility server | the repo target is a real edge proxy plus service runtime and mode-aware deployment topology, not a single-process compatibility shim | Phase 3, Sprint 3.4; Phase 4, Sprint 4.2 |
| `src/Infernix/Models.hs` seeded toy model list plus generic `infernix-test-config.dhall` rendering path | the README contract now requires the comprehensive matrix to drive mode-specific `infernix-demo-<mode>.dhall` generation, ConfigMap-backed publication at `/opt/build/` for containerized execution contexts, and per-mode exhaustive test enumeration | Phase 4, Sprint 4.6; Phase 6, Sprint 6.6 |

## Completed

None.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
