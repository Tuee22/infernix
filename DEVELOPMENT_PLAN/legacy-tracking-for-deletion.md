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

| Existing surface | Location | Removal condition | Owning sprint |
|------------------|----------|-------------------|---------------|

The table is empty: no shortcut surface is currently tracked for removal. That is a statement about
the ledger, not a claim that the repository is free of everything a future sprint may name.

Rows identify implementation surfaces, not whole files to delete. Keep legitimate tests and
supported behavior while removing the named shortcuts. Missing historical evidence is tracked in
the cohort waves, not as a fictitious code surface here. The orphan-backup compatibility path is
not listed because the implementation already refuses it.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [cohort-validation-waves.md](cohort-validation-waves.md)
