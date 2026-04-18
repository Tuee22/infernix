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
| `chart/README.md` scaffold-only wording | the file described the chart as a future scaffold and said `cluster up` was driven by a compatibility layer even though the current implementation renders and deploys the repo-owned chart on the supported Kind path | Phase 2, Sprint 2.3 |
| `kind/README.md` compatibility-layer wording | the file said the Kind assets were not applied automatically even though `cluster up` renders per-mode Kind configs from repo-owned assets on the supported path | Phase 2, Sprint 2.1; Phase 2, Sprint 2.7 |
| `proto/README.md` filesystem-only compatibility wording | the file framed protobuf contracts as future-only and described durability as filesystem-backed even though the current implementation publishes protobuf schemas and stores protobuf manifests or results through MinIO and Pulsar-backed flows | Phase 4, Sprint 4.1; Phase 4, Sprint 4.2 |
| `chart/Chart.yaml` scaffold-only description | the chart metadata still described the supported Helm deployment asset as a scaffold after `cluster up` began rendering and deploying it on the real Kind path | Phase 2, Sprint 2.3 |
| `web/generated/Generated/contracts.js` checked-in generated contract module | the web build now stages generated frontend contract output under the active build root and copies only the built runtime artifact into `web/dist/generated/contracts.js` | Phase 1, Sprint 1.4; Phase 5, Sprint 5.2 |
| `src/Infernix/Models.hs` seeded toy model list plus generic `infernix-test-config.dhall` rendering path | the repository now uses the full README matrix, mode-specific `infernix-demo-<mode>.dhall` generation, ConfigMap compatibility publication, and active-mode exhaustive validation enumeration | Phase 4, Sprint 4.6; Phase 6, Sprint 6.6 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
