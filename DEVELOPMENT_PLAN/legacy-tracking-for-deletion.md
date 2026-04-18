# Infernix Legacy Tracking For Deletion

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Provide the explicit ledger of obsolete paths, duplicate guidance, and future
> cleanup work in `infernix`.

## Pending Removal

None.

## Completed

| Location | Why it was slated for removal | Owning phase or sprint |
|----------|-------------------------------|------------------------|
| `web/generated/Generated/contracts.js` checked-in generated contract module | the web build now stages generated frontend contract output under the active build root and copies only the built runtime artifact into `web/dist/generated/contracts.js` | Phase 1, Sprint 1.4; Phase 5, Sprint 5.2 |
| `src/Infernix/Models.hs` seeded toy model list plus generic `infernix-test-config.dhall` rendering path | the repository now uses the full README matrix, mode-specific `infernix-demo-<mode>.dhall` generation, ConfigMap compatibility publication, and active-mode exhaustive validation enumeration | Phase 4, Sprint 4.6; Phase 6, Sprint 6.6 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
