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
| Marker-only cache materialize/rebuild | `src/Infernix/Runtime/Cache.hs`; `src/Infernix/Demo/Api.hs` | Hydrate verified real engine artifacts on their owning machine; report only actual operations. | 4.50 |
| First-file local checkpoint estimate | `src/Infernix/Runtime/Enforcer.hs` | Use the complete supported artifact layout consistently or explicitly refuse unsupported shards. | 4.50 |
| Literal-return realness blind spot | `python/adapters/common.py` | Retain useful static heuristics but replace false proof with behavioral/mutation-negative acceptance. | 4.50 |
| Uncontained static-file path construction | `src/Infernix/Demo/Api.hs` | Constrain decoded paths and filesystem resolution to the static root; test backend and routed boundaries. | 5.13 |
| Successful mandatory GPU fixture skips | `test/unit/Spec.hs` | Require executed selected-lane assertions with explicit device-capable context and structured results. | 6.55 |
| Discarded CUDA allocation process handles | `test/unit/Spec.hs` | Own and release every fixture process on success, timeout, exception, and cancellation. | 6.55 |
| Empty dispatcher state on durable-subscription resume | `src/Infernix/Runtime/Pulsar.hs` | Reconstruct reducer state before receiving/acknowledging live work. | 7.30 |
| Unverified hash-map cache and ignored observation | `src/Infernix/Runtime/KVCache.hs`; `src/Infernix/Runtime/Worker.hs`; `src/Infernix/Dispatch/SingleFlight.hs` | Rebuild verified conversation context and real engine state; retain only demonstrated reuse. | 7.31 |
| Conversation-only cancellation | `src/Infernix/Runtime/Pulsar.hs` | Deliver cancellation to the running engine and prove terminal outcome plus resource cleanup. | 7.32 |
| Unbounded text preview and buffering | `web/src/Infernix/Web/ArtifactTransport.js`; `src/Infernix/Demo/Api.hs` | Bound backend/browser reads and rendering; expose truncation and separate streaming download. | 7.33 |
| Missing-sample MIDI success-shaped renderer | `web/src/Infernix/Web/ArtifactTransport.js`; `web/package.json`; `web/playwright/inference.spec.js` | Materialize self-hosted samples, surface errors, and assert real render/playback output. | 7.33 |
| Malformed cache request widened to all models | `src/Infernix/Demo/Api.hs` | Reject malformed bodies/selectors before effects; represent intentional all-model scope explicitly. | 9.12 |

Rows identify implementation surfaces, not whole files to delete. Keep legitimate tests and
supported behavior while removing the named shortcuts. Missing historical evidence is tracked in
the cohort waves, not as a fictitious code surface here. The orphan-backup compatibility path is
not listed because the implementation already refuses it.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [cohort-validation-waves.md](cohort-validation-waves.md)
