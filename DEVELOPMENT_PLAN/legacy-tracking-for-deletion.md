# Infernix Legacy Tracking For Deletion

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Provide the explicit ledger of obsolete paths, duplicate guidance, and future
> cleanup work in `infernix`.

## Scope

- this ledger tracks implementation placeholders, compatibility shims, and fallback execution
  paths that still exist in the worktree and are expected to be removed or narrowed as the plan closes
- ordinary HTML or form-input placeholder copy is not tracked here unless it preserves a fallback
  behavior or masks a live platform failure

## Pending Removal

None.

## Pending Removal Details

None.

## Completed

| Location | Why it was slated for removal | Owning phase or sprint |
|----------|-------------------------------|------------------------|
| `chart/Chart.yaml`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs` Harbor chart-managed PostgreSQL path (`infernix-harbor-database`) | Harbor no longer deploys the chart-managed standalone PostgreSQL StatefulSet; the supported cluster path now installs the Percona operator, reconciles Harbor's Patroni claims through `infernix-manual`, repairs migration state through the current Patroni primary, and validates readiness, failover, and repeat lifecycle rebinding through integration coverage | Phase 3, Sprint 3.2; Phase 6, Sprint 6.7 |
| `tools/service_server.py` compatibility portal and gateway responses for `/harbor`, `/minio/console`, `/pulsar/admin`, `/minio/s3`, and `/pulsar/ws` | the direct service host no longer returns static compatibility responses for routed platform portals or gateway paths; unsupported direct-service requests now fail closed instead of masking the real gateway workloads behind placeholder HTML or JSON | Phase 3, Sprint 3.5; Phase 3, Sprint 3.7; Phase 6, Sprint 6.3 |
| `web/src/app.js`, `web/src/workbench.js` generated catalog or publication fallback UI | the workbench no longer falls back to the build-generated contract catalog or synthesize publication summary values when `/api/models` or `/api/publication` fail; routed catalog or publication failures now surface as unavailable live state instead of a browser-only compatibility layer | Phase 5, Sprint 5.6; Phase 6, Sprint 6.6 |
| `chart/README.md` scaffold-only wording | the file described the chart as a future scaffold and said `cluster up` was driven by a compatibility layer even though the current implementation renders and deploys the repo-owned chart on the supported Kind path | Phase 2, Sprint 2.3 |
| `kind/README.md` compatibility-layer wording | the file said the Kind assets were not applied automatically even though `cluster up` renders per-mode Kind configs from repo-owned assets on the supported path | Phase 2, Sprint 2.1; Phase 2, Sprint 2.7 |
| `proto/README.md` filesystem-only compatibility wording | the file framed protobuf contracts as future-only and described durability as filesystem-backed even though the current implementation publishes protobuf schemas and stores protobuf manifests or results through MinIO and Pulsar-backed flows | Phase 4, Sprint 4.1; Phase 4, Sprint 4.2 |
| `chart/Chart.yaml` scaffold-only description | the chart metadata still described the supported Helm deployment asset as a scaffold after `cluster up` began rendering and deploying it on the real Kind path | Phase 2, Sprint 2.3 |
| `web/generated/Generated/contracts.js` checked-in generated contract module | the web build now stages generated frontend contract output under the active build root and copies only the built runtime artifact into `web/dist/generated/contracts.js` | Phase 1, Sprint 1.4; Phase 5, Sprint 5.2 |
| `src/Infernix/Models.hs` seeded toy model list plus generic `infernix-test-config.dhall` rendering path | the repository now uses the full README matrix, mode-specific `infernix-demo-<mode>.dhall` generation, ConfigMap compatibility publication, and active-mode exhaustive validation enumeration | Phase 4, Sprint 4.6; Phase 6, Sprint 6.6 |
| `src/Infernix/Runtime.hs`, `tools/runtime_backend.py`, `tools/runtime_worker.py` unknown-engine `fallback-template` or `builtin-fallback` adapter path | the runtime no longer synthesizes fallback adapter ids for unmatched engines; it now maps the current catalog case-insensitively and fails fast on unsupported engine labels instead of hiding missing ownership behind synthetic success output | Phase 4, Sprint 4.1; Phase 4, Sprint 4.2 |
| `src/Infernix/Runtime.hs`, `test/unit/Spec.hs` host-native `bundle.json` placeholder metadata | the host-side unit helper path no longer writes metadata-only bundles; it now materializes the same durable bundle plus source-artifact-manifest contract through `tools/runtime_fixture_backend.py`, and the unit suite asserts explicit source-artifact materialization instead of `local-bundle-only` placeholder markers | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3 |
| `tools/runtime_backend.py`, `tools/service_server.py` implicit filesystem fallback backend mode | the supported service surface no longer drops into an implicit filesystem backend when no MinIO or Pulsar or bridge configuration is present; `RuntimeBackend` now requires explicit fixture ownership for `filesystem-fixture` mode, and `tools/service_server.py` exits with a user-facing error instead of publishing that fallback as a supported runtime state | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3 |
| `tools/engine_adapter.py` transitional engine probe path | the generic engine-adapter probe entrypoint has been removed; the supported runtime now defaults to `tools/final_engine_runner.py`, which keeps engine-specific runner metadata and source-artifact selection semantics in one place | Phase 4, Sprint 4.2; Phase 6, Sprint 6.2 |
| `tools/final_engine_runner.py`, `tools/runtime_worker.py`, `tools/runtime_backend.py`, `src/Infernix/Runtime.hs`, `test/integration/Spec.hs` engine-specific default runner | the engine-specific default runner is no longer tracked as a transitional compatibility path; the supported runtime now treats the process-isolated worker contract plus `INFERNIX_ENGINE_COMMAND_*` overrides as the canonical adapter-validation surface, records authoritative source-artifact selection and engine-adapter availability in durable bundles or routed cache entries, and validates that contract through unit plus integration coverage | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3; Phase 6, Sprint 6.2; Phase 6, Sprint 6.6 |
| `src/Infernix/Cluster.hs`, `tools/publish_chart_images.py`, `./.build/kind/registry/localhost:30001/hosts.toml` bootstrap-registry helper path | `cluster up` no longer mirrors MinIO or Pulsar through a helper registry on `localhost:30001`; the supported path now bootstraps Harbor and only the services Harbor needs from upstream image coordinates, rewrites only `localhost:30002`, and preloads Harbor-backed final image refs onto the Kind worker before the remaining non-Harbor rollout | Phase 2, Sprint 2.4 |
| `tools/engine_fixture.py`, `src/Infernix/CLI.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `chart/templates/deployment-service.yaml` global engine-fixture command path | the runtime and validation flows no longer inject a single global fixture command; they now default to the engine-specific runner and only forward adapter-specific `INFERNIX_ENGINE_COMMAND_*` overrides when explicitly configured | Phase 4, Sprint 4.2; Phase 6, Sprint 6.2 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
