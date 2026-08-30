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
| The lazy per-inference model-bootstrap workflow — the `persistent://infernix/system/model.bootstrap.request` topic family + `model.bootstrap.ready.<modelId>` events, `src/Infernix/Bootstrap/Models.hs` coordinator Failover bootstrap subscription, the `modelBootstrapTopic` config field, and the "engine sees uncached model → publishes bootstrap request" hot path. | Replaced by the coordinator's **eager** `warm-model-cache` staging of every model listed in the mounted `infernix.dhall` at cluster-up (a cluster-up barrier). The model set is the mounted config (source of truth); `src/Infernix/Models.hs` is a demo-only generator of that list. The download/upload/`.ready` mechanics are retained; only the per-request trigger is retired (engine lazy path kept as fallback). | Phase 8 Sprint 8.5 |
| The in-memory whole-deployment `DemoConfig` record: one Haskell record still carrying `coordinatorDaemon`, `webappDaemon`, `engineDaemons`, `enginePools`, `engineMembers`, `requestTopics`, `resultTopic`, `engines`, and `models` for every role at once. | The **wire** half of this row landed with the system/machine contract split: the generated system contract no longer carries the role, the two in-cluster daemon records, the member list, or a top-level model catalog, and the machine contract carries what is true of one box. The Haskell record survives as the decoder's output with those fields *derived*, so every role is still handed fields it must not act on — the disagreement is gone, the over-broad handoff is not. Retiring it means splitting the decoded value by role, which is a consumer-side refactor across routing, launch, publication, and presentation rather than a wire change. | Successor sprint to Phase 8 Sprint 8.11 |
| The vanilla-JS admin gate in the verbatim-copied `web/src/index.html`: the cookie-driven `<html>.infernix-admin` detector gating `.operator-ribbon`, `#admin-panel`, and the `.summary-item.cluster-summary` cells, plus the `#personal-dashboard` fetch of `GET /api/objects/list`. | Superseded in idiom rather than in function by folding the gate into PureScript state (`AppState.isAdmin` plus `renderAuthGate`), which keeps one rendering path instead of a compiled SPA plus a hand-written detector in the copied HTML shell. The `spago` build lane exists (`web/spago.yaml`, exercised by `infernix test unit`), so this is an accepted deferral rather than blocked work. Enforcement is unaffected either way — the edge `SecurityPolicy` admin `authorization` rule, the backend `withAdminRequest` gate, and the server-side `users/<sub>/` scoping in `handleObjectsList` are the boundary — so the row retires a duplicated presentation path, not a security surface. | Phase 9 Sprints 9.5 and 9.6 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [cohort-validation-waves.md](cohort-validation-waves.md)
