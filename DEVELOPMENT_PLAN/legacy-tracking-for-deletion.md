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

| Location | Why slated for removal | Owning phase or sprint |
|----------|------------------------|------------------------|
| Deleted legacy routing and image-build files still reported by `git ls-files` (`src/Infernix/Edge.hs`, `src/Infernix/Gateway.hs`, `src/Infernix/HttpProxy.hs`, `chart/templates/deployment-edge.yaml`, `chart/templates/service-edge.yaml`, `chart/templates/edge-configmap.yaml`, `chart/templates/workloads-platform-portals.yaml`, `docker/infernix.Dockerfile`, `docker/service.Dockerfile`, the six `docker/*-python.Dockerfile` files, `web/Dockerfile`, `tools/python_quality.sh`, `scripts/install-formatter.sh`) | The worktree deletions for the Envoy Gateway, substrate-container, and no-shell-shim migrations are landed, but repo policy forbids agent-owned staging, so the tracked-index cleanup is still open | Phase 1, Sprint 1.7; Phase 3, Sprints 3.5 and 3.8; Phase 4, Sprints 4.7 and 4.9; Phase 5, Sprint 5.5; Phase 6, Sprint 6.1 |
| Generated artifacts still reported by `git ls-files` (`python/poetry.lock`, `web/spago.lock`, `tools/generated_proto/**`, tracked `*.pyc` or `__pycache__/` paths under `tools/` or legacy `python/adapters/`) | Generated artifacts are deleted from the worktree, ignored by `.gitignore` plus `.dockerignore`, and rejected by the Haskell file-lint path when still tracked; only the user-owned tracked-index cleanup remains | Phase 1, Sprint 1.7 |

## Pending Removal Details

The Pending Removal entries above now reflect a narrower problem than before: the worktree
demolitions have largely landed, but the corresponding tracked-index cleanup is still open.
Once the user-owned `git rm --cached` or equivalent cleanup is complete and the Haskell file-lint
path rejects their return, these rows move to the Completed table below.

## Completed

| Location | Why it was slated for removal | Owning phase or sprint |
|----------|-------------------------------|------------------------|
| `chart/templates/service-api.yaml`, the `containerPort` surface in `chart/templates/deployment-service.yaml`, and the `infernix service --port` compatibility flag in `src/Infernix/CLI.hs` or `src/Infernix/Service.hs` | the production daemon is now consistently no-HTTP on the supported path; the chart no longer publishes a fake `infernix-service` HTTP Service or port, and the CLI no longer advertises or accepts an ignored service port | Phase 4, Sprint 4.8 |
| `tools/service_server.py` | the Python HTTP API host has been removed; the supported demo surface now lives in `src/Infernix/Demo/Api.hs` and is exposed through the Haskell binaries instead of a repo-owned Python server | Phase 3, Sprint 3.6; Phase 4, Sprint 4.4 |
| `web/build.mjs` | the repo no longer uses the legacy JavaScript bundler entrypoint; the supported browser build now runs through `npm --prefix web run build` with `spago build` plus `spago bundle` | Phase 1, Sprint 1.4; Phase 5, Sprint 5.2 |
| `web/src/app.js`, `web/src/catalog.js`, `web/src/workbench.js`, and `web/test/contracts.test.mjs` | the supported browser implementation and frontend unit suites now live under `web/src/*.purs` and `web/test/Main.purs`; the JavaScript workbench and contract test files are removed | Phase 5, Sprint 5.1; Phase 5, Sprint 5.3; Phase 5, Sprint 5.4; Phase 5, Sprint 5.6 |
| `web/playwright.config.js` | Playwright configuration now lives in the explicit CLI-owned invocation and the matrix runner; the separate config file is removed from the supported path | Phase 5, Sprint 5.5; Phase 6, Sprint 6.3 |
| `tools/runtime_backend.py`, `tools/runtime_worker.py`, `tools/runtime_fixture_backend.py`, `tools/final_engine_runner.py` | the monolithic Python runtime helpers have been removed from `tools/`; remaining runtime work now lands only through Haskell modules plus `python/<substrate>/adapters/<engine>/` | Phase 4, Sprint 4.2; Phase 4, Sprint 4.5; Phase 4, Sprint 4.7 |
| `tools/demo_config.py`, `tools/discover_chart_images.py`, `tools/discover_chart_claims.py`, `tools/list_harbor_overlay_images.py`, `tools/helm_chart_check.py`, `tools/platform_asset_check.py`, `tools/proto_check.py`, `tools/lint_check.py`, `tools/docs_check.py`, `tools/haskell_style_check.py`, `tools/publish_chart_images.py`, `tools/requirements.txt` | Phase 1 Sprint 1.6 has landed: custom-logic Python tooling is gone from `tools/`, the Haskell-owned lint or discovery or publication paths are live, and no build-time Python remains on the supported control-plane path | Phase 0, Sprint 0.6; Phase 1, Sprint 1.6; Phase 4, Sprint 4.7 |
| Homebrew-Poetry-as-host-prereq language across `documents/operations/apple_silicon_runbook.md`, `documents/development/local_dev.md`, `00-overview.md` Hard Constraint 2, and `phase-1` Sprint 1.3 | Poetry installation is now documented as an adapter-only user choice; `infernix` no longer installs it as a generic host prerequisite | Phase 0, Sprint 0.6; Phase 1, Sprint 1.3 |
| "Single Haskell binary" language across `00-overview.md` Hard Constraint 1, `README.md`, `AGENTS.md`, `CLAUDE.md`, and the canonical-shape diagram | the repository guidance now consistently describes the two-executable-one-library topology (`infernix` plus `infernix-demo`) | Phase 0, Sprint 0.6; Phase 1, Sprint 1.2 |
| `chart/Chart.yaml`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `test/integration/Spec.hs` Harbor chart-managed PostgreSQL path (`infernix-harbor-database`) | Harbor no longer deploys the chart-managed standalone PostgreSQL StatefulSet; the supported cluster path now installs the Percona operator, reconciles Harbor's Patroni claims through `infernix-manual`, repairs migration state through the current Patroni primary, and validates readiness, failover, and repeat lifecycle rebinding through integration coverage | Phase 3, Sprint 3.2; Phase 6, Sprint 6.7 |
| `tools/edge_proxy.py` | the Python edge proxy has been removed; the supported routing path now relies on the Helm-installed Envoy Gateway controller plus repo-owned Gateway or HTTPRoute manifests rather than a repo-owned proxy process | Phase 3, Sprint 3.5 |
| `tools/portal_surface.py` | the Python platform gateways have been removed; Harbor, MinIO, and Pulsar portal routing now rides the same Envoy-Gateway-owned HTTPRoute surface as the demo publication path rather than repo-owned gateway processes | Phase 3, Sprint 3.8 |
| `tools/service_server.py` compatibility portal and gateway responses for `/harbor`, `/minio/console`, `/pulsar/admin`, `/minio/s3`, and `/pulsar/ws` | the direct service host no longer returns static compatibility responses for routed platform portals or gateway paths; unsupported direct-service requests now fail closed instead of masking the real gateway workloads behind placeholder HTML or JSON | Phase 3, Sprint 3.5; Phase 3, Sprint 3.7; Phase 6, Sprint 6.3 |
| `web/src/app.js`, `web/src/workbench.js` generated catalog or publication fallback UI | the workbench no longer falls back to the build-generated contract catalog or synthesize publication summary values when `/api/models` or `/api/publication` fail; routed catalog or publication failures now surface as unavailable live state instead of a browser-only compatibility layer | Phase 5, Sprint 5.6; Phase 6, Sprint 6.6 |
| `chart/templates/deployment-web.yaml`, `chart/templates/service-web.yaml`, and the matching `infernix-web` compatibility deployment in `src/Infernix/Cluster.hs` | the routed `/` surface is served only by `infernix-demo`; Playwright now runs from the per-substrate substrate image on Linux or the host install on Apple Silicon, and there is no separate `web/Dockerfile`-based workload or executor image | Phase 5, Sprint 5.5 |
| `chart/README.md` scaffold-only wording | the file described the chart as a future scaffold and said `cluster up` was driven by a compatibility layer even though the current implementation renders and deploys the repo-owned chart on the supported Kind path | Phase 2, Sprint 2.3 |
| `kind/README.md` compatibility-layer wording | the file said the Kind assets were not applied automatically even though `cluster up` renders per-mode Kind configs from repo-owned assets on the supported path | Phase 2, Sprint 2.1; Phase 2, Sprint 2.7 |
| `proto/README.md` filesystem-only compatibility wording | the file framed protobuf contracts as future-only and described durability as filesystem-backed even though the current implementation publishes protobuf schemas and stores protobuf manifests or results through MinIO and Pulsar-backed flows | Phase 4, Sprint 4.1; Phase 4, Sprint 4.2 |
| `chart/Chart.yaml` scaffold-only description | the chart metadata still described the supported Helm deployment asset as a scaffold after `cluster up` began rendering and deploying it on the real Kind path | Phase 2, Sprint 2.3 |
| `web/generated/Generated/contracts.js` checked-in generated contract module | the web build now stages generated frontend contract output under the active build root and copies only the built runtime artifact into `web/dist/generated/contracts.js` | Phase 1, Sprint 1.4; Phase 5, Sprint 5.2 |
| `src/Infernix/Models.hs` seeded toy model list plus generic `infernix-test-config.dhall` rendering path | the repository now uses the full README matrix, mode-specific `infernix-demo-<mode>.dhall` generation, ConfigMap compatibility publication, and active-mode exhaustive validation enumeration | Phase 4, Sprint 4.6; Phase 6, Sprint 6.6 |
| `src/Infernix/Runtime.hs`, `tools/runtime_backend.py`, `tools/runtime_worker.py` unknown-engine `fallback-template` or `builtin-fallback` adapter path | the runtime no longer synthesizes fallback adapter ids for unmatched engines; it now maps the current catalog case-insensitively and fails fast on unsupported engine labels instead of hiding missing ownership behind synthetic success output | Phase 4, Sprint 4.1; Phase 4, Sprint 4.2 |
| `src/Infernix/Runtime.hs`, `test/unit/Spec.hs` host-native `bundle.json` placeholder metadata | the host-side unit helper path no longer writes metadata-only bundles; it now materializes durable bundle metadata through the Haskell runtime fixture path and asserts explicit source-artifact materialization instead of `local-bundle-only` placeholder markers | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3 |
| `tools/runtime_backend.py`, `tools/service_server.py` implicit filesystem fallback backend mode | the supported Haskell service and demo surfaces no longer publish an implicit Python fallback backend as a supported runtime state | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3 |
| `tools/engine_adapter.py` transitional engine probe path | the generic engine-adapter probe entrypoint has been removed; the supported repository no longer carries a generic Python engine probe on the control-plane path | Phase 4, Sprint 4.2; Phase 6, Sprint 6.2 |
| `tools/final_engine_runner.py`, `tools/runtime_worker.py`, `tools/runtime_backend.py`, `src/Infernix/Runtime.hs`, `test/integration/Spec.hs` engine-specific default runner | the separate Python default-runner compatibility path has been removed from the worktree; the remaining open worker split is Haskell-owned and tracked in Phase 4 | Phase 4, Sprint 4.2; Phase 4, Sprint 4.3; Phase 6, Sprint 6.2; Phase 6, Sprint 6.6 |
| `src/Infernix/Cluster.hs`, `tools/publish_chart_images.py`, `./.build/kind/registry/localhost:30001/hosts.toml` bootstrap-registry helper path | `cluster up` no longer mirrors MinIO or Pulsar through a helper registry on `localhost:30001`; the supported path now bootstraps Harbor and only the services Harbor needs from upstream image coordinates, rewrites only `localhost:30002`, and preloads Harbor-backed final image refs onto the Kind worker before the remaining non-Harbor rollout | Phase 2, Sprint 2.4 |
| `tools/engine_fixture.py`, `src/Infernix/CLI.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `chart/templates/deployment-service.yaml` global engine-fixture command path | the runtime and validation flows no longer inject a single global fixture command; they now default to the engine-specific runner and only forward adapter-specific `INFERNIX_ENGINE_COMMAND_*` overrides when explicitly configured | Phase 4, Sprint 4.2; Phase 6, Sprint 6.2 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
