# Infernix Legacy Tracking For Deletion

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Provide the explicit ledger of obsolete paths, duplicate guidance, and future
> cleanup work in `infernix`.

## Scope

- this ledger tracks implementation placeholders, compatibility shims, duplicate definitions, and
  stale guidance that still exists in the worktree or tracked index
- ordinary UI placeholder copy is not tracked here unless it preserves a fallback behavior or
  masks a live platform failure

## Pending Removal

None.

## Completed

| Location | Why it was slated for removal | Owning phase or sprint |
|----------|-------------------------------|------------------------|
| `--runtime-mode` parsing and `INFERNIX_RUNTIME_MODE` handling across `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, tests, and governed docs | The generated substrate `.dhall` beside the binary is the single source of truth for active substrate, so user-selected runtime overrides are obsolete in the final contract | Phase 0 Sprint 0.8; Phase 1 Sprint 1.10; Phase 4 Sprint 4.12; Phase 6 Sprint 6.19 |
| Per-mode generated catalog files and publication paths such as `infernix-substrate.dhall` | The final control contract publishes one compile-time generated `infernix-substrate.dhall` beside the binary and mirrors that exact file into the cluster ConfigMap | Phase 0 Sprint 0.8; Phase 1 Sprint 1.10; Phase 2 Sprint 2.9 |
| Apple host-demo bridge behavior, direct host `infernix-demo serve` launch guidance, and any remaining host-bridge route publication language | The final Apple doctrine keeps the demo app cluster-resident and uses the host only for the Apple inference daemon and host CLI orchestration | Phase 0 Sprint 0.8; Phase 3 Sprint 3.9; Phase 5 Sprint 5.8 |
| User-facing direct `linux-gpu` launcher guidance and any requirement for the outer control-plane container itself to request the NVIDIA runtime | Supported Linux control-plane commands must run through Compose, and the outer container does not need direct CUDA access even when the deployed substrate is GPU-backed | Phase 0 Sprint 0.8; Phase 1 Sprint 1.10; Phase 2 Sprint 2.9 |
| `linux-cuda` substrate naming across code, Kind assets, tests, and docs | The final canonical substrate id is `linux-gpu`, so the old `linux-cuda` label is legacy naming that must be retired explicitly | Phase 0 Sprint 0.8; Phase 1 Sprint 1.10; Phase 2 Sprint 2.9; Phase 6 Sprint 6.19 |
| Simulated cluster, route, transport, and inference fallback behavior | The final runtime and validation doctrine removes simulation completely from the supported contract; the only broadly portable lane is the real `linux-cpu` outer-container workflow rather than any simulated surrogate | Phase 0 Sprint 0.8; Phase 4 Sprint 4.12; Phase 6 Sprint 6.19 |
| Legacy `default.state` cache-manifest fallback in `src/Infernix/Runtime/Cache.hs` | The supported durable cache-manifest contract is protobuf-backed `default.pb` state only, so the old text-state fallback kept an obsolete cache-manifest format alive in code | Phase 6 Sprint 6.17 |
| Legacy inference-result fallback in `src/Infernix/Runtime.hs` that read `./.data/runtime/results/*.state` when the protobuf result file was absent | The supported durable result contract is protobuf-backed `*.pb` state only, so the old text-state fallback kept an obsolete result format alive in code | Phase 6 Sprint 6.17 |
| Legacy generated-contract cleanup in `src/Infernix/CLI.hs` that deleted `web/src/Infernix/Web/Contracts.purs` during PureScript contract generation | The supported handwritten Haskell contract home moved to `src/Infernix/Web/Contracts.hs`, and generated PureScript output now belongs only under `web/src/Generated/`, so the retired output path should stop participating in supported builds | Phase 6 Sprint 6.17 |
| Legacy helper-registry cleanup shims in `src/Infernix/Cluster.hs` that removed the retired `infernix-bootstrap-registry` container and `./.build/kind/registry/localhost:30001` namespace | The supported Harbor-first bootstrap path no longer uses the helper registry at all, so the remaining cleanup code was the last compatibility surface from that retired bootstrap model | Phase 6 Sprint 6.17 |
| `chart/templates/service-api.yaml`, the production HTTP service port surface, and the `infernix service --port` compatibility flag | Production `infernix service` is now consistently a no-HTTP daemon on the supported path | Phase 4 Sprint 4.8 |
| `tools/service_server.py` and the old Python HTTP API host | The demo HTTP surface now lives in `src/Infernix/Demo/Api.hs` and is served by `infernix-demo` | Phase 3 Sprint 3.6; Phase 4 Sprint 4.4 |
| `tools/runtime_backend.py`, `tools/runtime_worker.py`, `tools/runtime_fixture_backend.py`, `tools/final_engine_runner.py` | The monolithic Python runtime helpers are gone; runtime work now closes through Haskell plus the adapter boundary | Phase 4 Sprint 4.2; Phase 4 Sprint 4.5 |
| `tools/demo_config.py`, `tools/discover_chart_images.py`, `tools/discover_chart_claims.py`, `tools/list_harbor_overlay_images.py`, `tools/helm_chart_check.py`, `tools/platform_asset_check.py`, `tools/proto_check.py`, `tools/lint_check.py`, `tools/docs_check.py`, `tools/haskell_style_check.py`, `tools/publish_chart_images.py`, `tools/requirements.txt` | Control-plane tooling is Haskell-owned and no build-time Python remains on the supported control-plane path | Phase 1 Sprint 1.6 |
| Harbor chart-managed standalone PostgreSQL deployment path | Harbor and later PostgreSQL-backed services now use operator-managed Patroni clusters only | Phase 3 Sprint 3.2; Phase 6 Sprint 6.7 |
| Bootstrap helper-registry path on `localhost:30001` | Harbor-first bootstrap now mirrors only the final Harbor-backed image flow and no longer needs the helper registry | Phase 2 Sprint 2.4 |
| `docker/linux-base.Dockerfile`, `docker/linux-cpu.Dockerfile`, `docker/linux-gpu.Dockerfile` | The supported Linux image story now closes through one shared `docker/linux-substrate.Dockerfile` that produces the two real Linux runtime images | Phase 4 Sprint 4.9 |
| Live repo-mount assumptions in `compose.yaml` (`.:/workspace`, `infernix-web-node-modules`, and the live source-edit launcher posture) | The Linux launcher now uses a baked image snapshot and bind-mounts only `./.data/` plus the Docker socket and named build caches | Phase 1 Sprint 1.9 |
| `python/apple-silicon/`, `python/linux-cpu/`, and `python/linux-gpu/` project duplication | The supported Python boundary now closes through one `python/pyproject.toml` and one shared `python/adapters/` tree | Phase 4 Sprint 4.7 |
| `src/Generated/Contracts.hs` | The handwritten Haskell browser-contract source now lives under `src/Infernix/Web/Contracts.hs`; `Generated/` is reserved for generated output only | Phase 5 Sprint 5.7 |
| `chart/templates/httproutes/*.yaml`, route duplication in `src/Infernix/Models.hs`, and committed generated route or publication payload copies in `chart/values.yaml` | The supported route or publication contract now closes through one Haskell route registry, one data-driven HTTPRoute template, structural chart defaults only, and registry-backed route-doc plus route-lint derivation | Phase 2 Sprint 2.3; Phase 3 Sprint 3.8; Phase 6 Sprint 6.11 |
| `npx`-based Playwright workflow references in the supported CLI, docs, and web scripts | Supported Playwright workflows now use `npm --prefix web exec -- playwright ...` | Phase 1 Sprint 1.9; Phase 5 Sprint 5.5; Phase 6 Sprint 6.3 |
| Broad root-guidance drift across `README.md`, `AGENTS.md`, and `CLAUDE.md` | The governed metadata model, canonical-home links, and thin assistant-entry-doc posture are landed | Phase 1 Sprint 1.8; Phase 6 Sprint 6.9; Phase 6 Sprint 6.12 |
| Handwritten route inventory summaries in `README.md`, `documents/engineering/edge_routing.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, and `documents/operations/cluster_bootstrap_runbook.md` | Route-oriented docs now consume registry-backed generated sections from the Haskell route registry instead of hand-maintained inventories | Phase 6 Sprint 6.11 |
| Phrase-based route-aware lint in `src/Infernix/Lint/Chart.hs` and `src/Infernix/Lint/Docs.hs` | Route-aware validation now checks registry-backed generated sections instead of relying on handwritten route phrases alone | Phase 6 Sprint 6.11 |
| Repeated assistant workflow guidance across `AGENTS.md` and `CLAUDE.md` without one canonical `documents/` assistant-workflow home | The root automation entry docs now stay thin and point at `documents/development/assistant_workflow.md` as the canonical repository-level assistant workflow home | Phase 6 Sprint 6.12 |
| Duplicated web-dependency readiness checks in `src/Infernix/Workflow.hs` and `src/Infernix/Cluster.hs` | The cluster path now reuses `Infernix.Workflow.ensureWebDependencies` instead of maintaining its own readiness probe | Phase 6 Sprint 6.12 |
| Dormant `victoria-metrics-k8s-stack` monitoring placeholder in `chart/values.yaml` | Monitoring is not a supported first-class surface, so the stale chart toggle was removed instead of implying a supported monitoring stack | Phase 6 Sprint 6.14 |
| Root `README.md` wording that described `linux-cpu` as a native-or-containerized lane | The supported runtime model is one host-native Apple inference lane plus two containerized Linux lanes, so the remaining root-language drift item had to be removed to keep runtime honesty aligned across the plan and governed docs | Phase 6 Sprint 6.16 |
| Duplicate demo-config generated-banner literals in `src/Infernix/Workflow.hs` and `src/Infernix/DemoConfig.hs` | The shared workflow-helper closure was not complete while the demo-config banner constant still existed in parallel definitions | Phase 6 Sprint 6.16 |
| `documents/development/testing_strategy.md` metadata and purpose text that framed it as an authoritative canonical validation surface alongside `documents/engineering/testing.md` | The testing doctrine now closes through one canonical home, with `documents/development/testing_strategy.md` reduced to supporting operator detail instead of a competing authoritative source | Phase 6 Sprint 6.16 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
