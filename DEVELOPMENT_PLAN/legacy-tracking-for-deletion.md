# Infernix Legacy Tracking For Deletion

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Provide the explicit ledger of obsolete paths, duplicate guidance, and outstanding
> cleanup work in `infernix`.

## Scope
- this ledger tracks implementation placeholders, compatibility shims, duplicate definitions, and
  stale guidance that still exists in the worktree or tracked index
- ordinary UI placeholder copy is not tracked here unless it preserves a fallback behavior or
  masks a live platform failure

## Pending Removal

Every row below names a surface that **still exists** and must be removed. When a removal lands
the row is deleted, not moved: per Section D of
[development_plan_standards.md](development_plan_standards.md) the plan carries no history, and a
surface that no longer exists is not something a reader of this plan needs told about.

| Location | Why it is slated for removal | Owning phase or sprint |
|----------|------------------------------|------------------------|
| The duplicated `## Non-Negotiable Rules` section carried by both `CLAUDE.md` and `AGENTS.md`, the `mirrorRuleDivergenceViolations` check in `src/Infernix/Lint/Docs.hs` that holds the two copies equal, and the absent assertion over Section Q's frozen mechanical set. | One rules section stated once removes the divergence the check exists to catch, and retires the check with it. Section Q enumerates the mechanical governance set by name but nothing holds the enumeration equal to the dispatch, so the list can go stale silently. Recorded rather than scheduled: the entry documents are the surface a reader loads first, and a change to them is worth making deliberately rather than as a governance sprint. | Phase 6 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [cohort-validation-waves.md](cohort-validation-waves.md)
