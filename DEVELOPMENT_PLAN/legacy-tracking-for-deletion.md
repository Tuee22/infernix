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

| Location | Why it is slated for removal | Owning phase or sprint |
|----------|-------------------------------|------------------------|
| `tools/engine_probe.py`, `tools/runtime_worker.py`, `tools/runtime_backend.py`, `src/Infernix/Runtime.hs`, `test/integration/Spec.hs` repo-owned default engine probe path | the supported runtime now launches process-isolated engine workers through configured command prefixes and falls back to `tools/engine_probe.py` when no adapter-specific override is configured; this repo-owned probe path remains transitional until supported-host validation lands for the real engines selected by the README matrix, and the routed publication plus integration surfaces currently assert `workerExecutionMode = process-isolated-engine-workers` and `workerAdapterMode = repo-owned-probe-with-command-overrides` | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3; Phase 6, Sprint 6.2; Phase 6, Sprint 6.6 |
| `tools/service_server.py` compatibility portal and gateway responses for `/harbor`, `/minio/console`, `/pulsar/admin`, `/minio/s3`, and `/pulsar/ws` | the direct service host still returns static HTML or JSON compatibility responses for the routed platform portals and gateway paths instead of proxying or delegating to the live routed Harbor, MinIO, and Pulsar gateway workloads; these responses preserve host-side route shape but are explicitly placeholder surfaces and should be removed once every supported path reaches the real routed gateways | Phase 3, Sprint 3.4; Phase 3, Sprint 3.6; Phase 6, Sprint 6.3 |
| `web/src/app.js`, `web/src/workbench.js` generated catalog or publication fallback UI | the web workbench still falls back to the build-generated contract catalog when `/api/models` fails and synthesizes publication summary values such as `generated-fallback` and `generated-contract-fallback` when `/api/publication` is unavailable; this keeps the workbench partially usable during failure, but it also masks live routed catalog or publication regressions behind a generated compatibility surface that should eventually be removed or confined to an explicit offline mode | Phase 5, Sprint 5.6; Phase 6, Sprint 6.6 |

## Pending Removal Details

### Repo-Owned Default Engine Probe Placeholder

- `tools/runtime_worker.py` now shells into configured engine command prefixes and falls back to
  `tools/engine_probe.py` when no adapter-specific override is configured so the process-isolated
  adapter contract is still exercised without requiring every final engine binary or module on the
  current host
- `tools/runtime_backend.py` supervises those workers and reports the transitional contract through
  `workerExecutionMode = process-isolated-engine-workers` and
  `workerAdapterMode = repo-owned-probe-with-command-overrides`
- `src/Infernix/Runtime.hs` still shells directly into that worker script for host-native request
  execution instead of proving supported-host Apple engine execution
- `test/integration/Spec.hs` currently treats the repo-owned probe-plus-override contract as the
  expected routed publication surface, so those assertions will need to narrow once the
  supported-host final-engine path closes

### Compatibility Portal Responses

- `tools/service_server.py` still returns explicit compatibility responses for:
- `/harbor`
- `/minio/console`
- `/pulsar/admin`
- `/minio/s3`
- `/pulsar/ws`
- the HTML responses literally describe themselves as a `Compatibility portal surface.`
- these routes preserve URL shape for host-side service execution, but they are not the same as the
  real routed gateway workloads defined and validated in the cluster path

### Generated Catalog And Publication Fallback UI

- `web/src/app.js` keeps the generated build-time catalog in memory and surfaces `Using generated catalog fallback: ...`
  when `/api/models` fails
- `web/src/workbench.js` synthesizes publication values such as:
- `controlPlaneContext = generated-fallback`
- `catalogSource = generated-contract-fallback`
- `apiUpstreamMode = unpublished`
- these fallbacks are useful during bootstrap and offline failures, but they also let the browser
  continue rendering a partially synthetic state when the live routed service is unavailable
- if this behavior remains desirable long-term, it should be recast as an explicit offline mode
  rather than a silent compatibility fallback on the main workbench path

## Completed

| Location | Why it was slated for removal | Owning phase or sprint |
|----------|-------------------------------|------------------------|
| `chart/README.md` scaffold-only wording | the file described the chart as a future scaffold and said `cluster up` was driven by a compatibility layer even though the current implementation renders and deploys the repo-owned chart on the supported Kind path | Phase 2, Sprint 2.3 |
| `kind/README.md` compatibility-layer wording | the file said the Kind assets were not applied automatically even though `cluster up` renders per-mode Kind configs from repo-owned assets on the supported path | Phase 2, Sprint 2.1; Phase 2, Sprint 2.7 |
| `proto/README.md` filesystem-only compatibility wording | the file framed protobuf contracts as future-only and described durability as filesystem-backed even though the current implementation publishes protobuf schemas and stores protobuf manifests or results through MinIO and Pulsar-backed flows | Phase 4, Sprint 4.1; Phase 4, Sprint 4.2 |
| `chart/Chart.yaml` scaffold-only description | the chart metadata still described the supported Helm deployment asset as a scaffold after `cluster up` began rendering and deploying it on the real Kind path | Phase 2, Sprint 2.3 |
| `web/generated/Generated/contracts.js` checked-in generated contract module | the web build now stages generated frontend contract output under the active build root and copies only the built runtime artifact into `web/dist/generated/contracts.js` | Phase 1, Sprint 1.4; Phase 5, Sprint 5.2 |
| `src/Infernix/Models.hs` seeded toy model list plus generic `infernix-test-config.dhall` rendering path | the repository now uses the full README matrix, mode-specific `infernix-demo-<mode>.dhall` generation, ConfigMap compatibility publication, and active-mode exhaustive validation enumeration | Phase 4, Sprint 4.6; Phase 6, Sprint 6.6 |
| `src/Infernix/Runtime.hs`, `tools/runtime_backend.py`, `tools/runtime_worker.py` unknown-engine `fallback-template` or `builtin-fallback` adapter path | the runtime no longer synthesizes fallback adapter ids for unmatched engines; it now maps the current catalog case-insensitively and fails fast on unsupported engine labels instead of hiding missing ownership behind synthetic success output | Phase 4, Sprint 4.1; Phase 4, Sprint 4.2 |
| `src/Infernix/Runtime.hs`, `test/unit/Spec.hs` host-native `bundle.json` placeholder metadata | the host-side unit helper path no longer writes metadata-only bundles; it now materializes the same durable bundle plus source-artifact-manifest contract through `tools/runtime_fixture_backend.py`, and the unit suite asserts explicit source-artifact materialization instead of `local-bundle-only` placeholder markers | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3 |
| `tools/runtime_backend.py`, `tools/service_server.py` implicit filesystem fallback backend mode | the supported service surface no longer drops into an implicit filesystem backend when no MinIO or Pulsar or bridge configuration is present; `RuntimeBackend` now requires explicit fixture ownership for `filesystem-fixture` mode, and `tools/service_server.py` exits with a user-facing error instead of publishing that fallback as a supported runtime state | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3 |
| `src/Infernix/Cluster.hs`, `tools/publish_chart_images.py`, `./.build/kind/registry/localhost:30001/hosts.toml` bootstrap-registry helper path | `cluster up` no longer mirrors MinIO or Pulsar through a helper registry on `localhost:30001`; the supported path now bootstraps Harbor and only the services Harbor needs from upstream image coordinates, rewrites only `localhost:30002`, and preloads Harbor-backed final image refs onto the Kind worker before the remaining non-Harbor rollout | Phase 2, Sprint 2.4 |
| `tools/engine_fixture.py`, `src/Infernix/CLI.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `chart/templates/deployment-service.yaml` global engine-fixture command path | the runtime and validation flows no longer inject a single global fixture command; they now default to the repo-owned engine probe path and only forward adapter-specific `INFERNIX_ENGINE_COMMAND_*` overrides when explicitly configured | Phase 4, Sprint 4.2; Phase 6, Sprint 6.2 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
