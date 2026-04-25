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
| `tools/service_server.py` | Demo HTTP API surface moves into `src/Infernix/Demo/Api.hs` exposed by the new `infernix-demo` binary; production accepts inference work via Pulsar only and binds no HTTP listener | Phase 3, Sprint 3.6; Phase 4, Sprint 4.2; Phase 4, Sprint 4.4 |
| `tools/edge_proxy.py` | Edge proxy reimplemented in Haskell as `src/Infernix/Edge.hs` and deployed via the same `infernix` image with entrypoint `infernix edge` | Phase 3, Sprint 3.5 |
| `tools/portal_surface.py` | Harbor, MinIO, and Pulsar gateway workloads reimplemented in Haskell under `src/Infernix/Gateway/{Harbor,Minio,Pulsar}.hs` and deployed via the same `infernix` image | Phase 3, Sprint 3.8 |
| `tools/runtime_backend.py` | Runtime backend reimplemented in Haskell under `src/Infernix/Runtime/{Pulsar,Worker,Cache}.hs`; engine-specific Python remains only inside `python/adapters/` | Phase 4, Sprint 4.2; Phase 4, Sprint 4.5 |
| `tools/runtime_worker.py` | Worker supervision reimplemented in Haskell as `src/Infernix/Runtime/Worker.hs`; the worker forks a Python adapter only when the bound engine is Python-native | Phase 4, Sprint 4.7 |
| `tools/runtime_fixture_backend.py` | Test fixture path moves to Haskell under `test/unit/` once the Haskell runtime owns the runtime contract | Phase 4, Sprint 4.5 |
| `tools/final_engine_runner.py` | Replaced by the Haskell worker plus per-engine Python adapter under `python/adapters/<engine>/` | Phase 4, Sprint 4.7 |
| `tools/demo_config.py` | Demo-config parsing reimplemented in Haskell under `src/Infernix/DemoConfig.hs`; no external Python tool consumes the demo config | Phase 1, Sprint 1.6 |
| `tools/discover_chart_images.py` | Replaced by `infernix internal discover images` under `src/Infernix/Cluster/Discover.hs` | Phase 1, Sprint 1.6 |
| `tools/discover_chart_claims.py` | Replaced by `infernix internal discover claims` under `src/Infernix/Cluster/Discover.hs` | Phase 1, Sprint 1.6 |
| `tools/list_harbor_overlay_images.py` | Replaced by `infernix internal discover harbor-overlay` under `src/Infernix/Cluster/Discover.hs` | Phase 1, Sprint 1.6 |
| `tools/helm_chart_check.py` | Replaced by `infernix lint chart` under `src/Infernix/Lint/Chart.hs` | Phase 1, Sprint 1.6 |
| `tools/platform_asset_check.py` | Folded into `infernix lint chart` under `src/Infernix/Lint/Chart.hs` | Phase 1, Sprint 1.6 |
| `tools/proto_check.py` | Replaced by `infernix lint proto` under `src/Infernix/Lint/Proto.hs` | Phase 1, Sprint 1.6 |
| `tools/lint_check.py` | Replaced by `infernix lint files` under `src/Infernix/Lint/Files.hs` (or a Cabal test target where trivial) | Phase 1, Sprint 1.6 |
| `tools/docs_check.py` | Replaced by `infernix lint docs` under `src/Infernix/Lint/Docs.hs`, extended to forbid retired-doctrine phrases outside `legacy-tracking-for-deletion.md` | Phase 0, Sprint 0.6; Phase 1, Sprint 1.6 |
| `tools/haskell_style_check.py` | Replaced by a Cabal test target plus a `scripts/install-formatter.sh` shell shim that downloads `ormolu` and `hlint`; no Python remains in the Haskell-style gate | Phase 1, Sprint 1.6 |
| `tools/publish_chart_images.py` | Replaced by `infernix internal publish-chart-images` under `src/Infernix/Cluster/PublishImages.hs`; folds into the existing cluster lifecycle in `src/Infernix/Cluster.hs` | Phase 1, Sprint 1.6 |
| `tools/requirements.txt` | No build-time Python remains on the supported path; replaced by `python/pyproject.toml` (Poetry) for engine-adapter Python only | Phase 1, Sprint 1.6; Phase 4, Sprint 4.7 |
| `web/build.mjs` | Replaced by `spago bundle-app` invoked from `web/Dockerfile` and the `infernix-lib` build; PureScript replaces JavaScript as the supported web language | Phase 1, Sprint 1.4; Phase 5, Sprint 5.2 |
| `web/src/app.js`, `web/src/workbench.js`, `web/src/index.html` JavaScript bits | Replaced by PureScript modules under `web/src/*.purs` plus a generated `index.html` template | Phase 5, Sprint 5.1; Phase 5, Sprint 5.4; Phase 5, Sprint 5.6 |
| `web/test/contracts.test.mjs` | Replaced by `purescript-spec` suites under `web/test/*.purs` | Phase 5, Sprint 5.3 |
| `web/test/run_playwright_matrix.mjs` | Re-implemented in Haskell test orchestration under `test/integration/` | Phase 6, Sprint 6.3 |
| `web/package.json` | Replaced by `web/spago.yaml` plus the PureScript toolchain installed by `web/Dockerfile` | Phase 1, Sprint 1.4; Phase 5, Sprint 5.1 |
| `web/playwright.config.js` | Replaced by Haskell-orchestrated Playwright invocation; the Playwright binary stays bundled in the web image | Phase 5, Sprint 5.5; Phase 6, Sprint 6.3 |
| Homebrew-Poetry-as-host-prereq language across `documents/operations/apple_silicon_runbook.md`, `documents/development/local_dev.md`, `00-overview.md` Hard Constraint 2, and `phase-1` Sprint 1.3 | Poetry installation is a user choice, only relevant for the engine-adapter test surface; `infernix` does not install it as a generic platform prerequisite | Phase 0, Sprint 0.6; Phase 1, Sprint 1.3 |
| "Single Haskell binary" language across `00-overview.md` Hard Constraint 1, `README.md`, `AGENTS.md`, `CLAUDE.md`, and the canonical-shape diagram | Replaced by the two-executable-one-library topology: `infernix` (production daemon) and `infernix-demo` (demo UI host) sharing `infernix-lib`, both shipped in the same image | Phase 0, Sprint 0.6; Phase 1, Sprint 1.2 |

## Pending Removal Details

### `tools/service_server.py` and the Python HTTP API surface

`tools/service_server.py` currently exposes `/healthz`, `/api/publication`, `/api/models`, `/api/demo-config`, `/api/cache`, `/api/models/<id>`, `/api/inference/<id>`, `/objects/<key>`, `POST /api/inference`, and the cache evict and rebuild endpoints. The new doctrine restricts production deployments to Pulsar-driven inference: `infernix service` (production) subscribes to request topics named in the active `.dhall`, dispatches each request through the Haskell worker, and publishes results to result topics named in the same config; no HTTP listener is bound. The demo HTTP API survives only through the `infernix-demo` binary, which exposes the same endpoints behind the `.dhall` `demo_ui` flag. The Python implementation moves to `src/Infernix/Demo/Api.hs` (servant or wai-based) inside `infernix-lib`.

### `tools/edge_proxy.py` and the Python edge proxy

The current edge proxy is a stdlib `ThreadingHTTPServer` Python script that fans `/`, `/api`, `/healthz`, `/harbor`, `/minio`, and `/pulsar` to upstream services. The new doctrine reimplements the proxy in Haskell under `src/Infernix/Edge.hs` (using `wai` plus `http-reverse-proxy` or equivalent), deployed via the same `infernix` image with the entrypoint `infernix edge`. The chart template `chart/templates/deployment-edge.yaml` is preserved; only the image entrypoint and command change.

### `tools/portal_surface.py` and the Python platform gateways

The current `portal_surface.py` (598 lines) wraps `pulsar` and `minio` Python SDKs to expose `/harbor`, `/minio`, and `/pulsar` portal surfaces with credential handling. The new doctrine reimplements these gateways in Haskell under `src/Infernix/Gateway/{Harbor,Minio,Pulsar}.hs`, deployed via `chart/templates/workloads-platform-portals.yaml` using the `infernix` image with `infernix gateway harbor|minio|pulsar` as entrypoint.

### `tools/runtime_backend.py`, `tools/runtime_worker.py`, `tools/runtime_fixture_backend.py`, `tools/final_engine_runner.py` and the runtime path

The runtime backend (1915 lines, the largest Python file in the repo) currently owns Pulsar consumer/dispatcher logic, MinIO artifact bundle and source-artifact materialization, dynamic Python-adapter loading, and durable cache management. The new doctrine splits this responsibility: the Haskell binary owns Pulsar subscription and dispatch (`src/Infernix/Runtime/Pulsar.hs`), worker process supervision (`src/Infernix/Runtime/Worker.hs`), and durable cache management (`src/Infernix/Runtime/Cache.hs`). Engine-specific Python survives only inside `python/adapters/<engine>/` and is invoked by the Haskell worker over typed protobuf-over-stdio (or unix socket) when the bound engine is Python-native. `tools/runtime_fixture_backend.py` is replaced by Haskell test fixtures under `test/unit/`.

### `tools/*.py` build and lint helpers

Every remaining custom-logic Python script under `tools/` (`demo_config`, `discover_chart_images`, `discover_chart_claims`, `list_harbor_overlay_images`, `helm_chart_check`, `platform_asset_check`, `proto_check`, `lint_check`, `docs_check`, `haskell_style_check`, `publish_chart_images`) is replaced by Haskell modules invoked through `infernix` subcommands (`infernix lint files|docs|proto|chart`, `infernix internal discover images|claims|harbor-overlay`, `infernix internal publish-chart-images`, `infernix internal demo-config`). The `haskell_style_check` Python wrapper around `ormolu` and `hlint` becomes a Cabal test target plus a small `scripts/install-formatter.sh` shell shim that downloads the binaries; no Python is involved in validating Haskell code. `tools/requirements.txt` is removed because no build-time Python remains; the only surviving `pyproject.toml` lives at `python/pyproject.toml` and governs engine-adapter Python under Poetry.

### `web/build.mjs`, `web/src/*.js`, `web/test/*.mjs`, `web/package.json`, `web/playwright.config.js` and the JavaScript workbench

The new doctrine replaces the JavaScript workbench with PureScript built by spago, tested with `purescript-spec`, and deriving frontend types from Haskell ADTs (in `src/Infernix/Demo/Api.hs`) via purescript-bridge. Build output lands in `web/dist/` produced by `spago bundle-app`. Generated PureScript modules land in `web/src/Generated/` written by `infernix internal generate-purs-contracts`. The `web/Dockerfile` installs `purs` and `spago` alongside the existing Playwright dependencies; the same image continues to host the demo UI and serve as the Playwright runner. `web/package.json` (npm dependency manifest), `web/build.mjs` (esbuild driver), `web/src/app.js`, `web/src/workbench.js`, the JavaScript portion of `web/src/index.html`, `web/test/contracts.test.mjs`, and `web/playwright.config.js` are removed; the Playwright matrix runner is reimplemented in the Haskell integration suite.

### Two-executable topology and Hard Constraint 1

Hard Constraint 1 in `00-overview.md` previously declared "one repo-owned Haskell executable named `infernix`". The new doctrine declares two Haskell executables — `infernix` (production daemon: cluster lifecycle, edge proxy, gateway pods, Pulsar inference dispatcher) and `infernix-demo` (demo UI host: servant-based HTTP server) — sharing one Cabal library `infernix-lib`. Both ship in the same OCI image; the entrypoint selects which exe runs. No third executable may be added without standards revision. The canonical-shape diagram, the topology diagram, root `README.md`, `AGENTS.md`, and `CLAUDE.md` are updated together.

### Homebrew-installed Poetry as a host prerequisite

The previous Hard Constraint 2 wording said `infernix` may install missing Homebrew `poetry` and other declared Python dependencies for repo-owned runtime flows. The new doctrine drops Python from the operator's host workflow entirely: `infernix` does not install Poetry, and Poetry plus a local `./.venv/` materialize only when an engine-adapter test is exercised explicitly (`infernix test integration --engine pytorch` or equivalent). Inside the engine container, Poetry installs system-wide from `python/pyproject.toml`; no in-container `.venv` is used.

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
