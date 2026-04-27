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
| `chart/templates/service-api.yaml`, the production HTTP service port surface, and the `infernix service --port` compatibility flag | Production `infernix service` is now consistently a no-HTTP daemon on the supported path | Phase 4 Sprint 4.8 |
| `tools/service_server.py` and the old Python HTTP API host | The demo HTTP surface now lives in `src/Infernix/Demo/Api.hs` and is served by `infernix-demo` | Phase 3 Sprint 3.6; Phase 4 Sprint 4.4 |
| `tools/runtime_backend.py`, `tools/runtime_worker.py`, `tools/runtime_fixture_backend.py`, `tools/final_engine_runner.py` | The monolithic Python runtime helpers are gone; runtime work now closes through Haskell plus the adapter boundary | Phase 4 Sprint 4.2; Phase 4 Sprint 4.5 |
| `tools/demo_config.py`, `tools/discover_chart_images.py`, `tools/discover_chart_claims.py`, `tools/list_harbor_overlay_images.py`, `tools/helm_chart_check.py`, `tools/platform_asset_check.py`, `tools/proto_check.py`, `tools/lint_check.py`, `tools/docs_check.py`, `tools/haskell_style_check.py`, `tools/publish_chart_images.py`, `tools/requirements.txt` | Control-plane tooling is Haskell-owned and no build-time Python remains on the supported control-plane path | Phase 1 Sprint 1.6 |
| Harbor chart-managed standalone PostgreSQL deployment path | Harbor and later PostgreSQL-backed services now use operator-managed Patroni clusters only | Phase 3 Sprint 3.2; Phase 6 Sprint 6.7 |
| Bootstrap helper-registry path on `localhost:30001` | Harbor-first bootstrap now mirrors only the final Harbor-backed image flow and no longer needs the helper registry | Phase 2 Sprint 2.4 |
| `docker/linux-base.Dockerfile`, `docker/linux-cpu.Dockerfile`, `docker/linux-cuda.Dockerfile` | The supported Linux image story now closes through one shared `docker/linux-substrate.Dockerfile` that produces the two real Linux runtime images | Phase 4 Sprint 4.9 |
| Live repo-mount assumptions in `compose.yaml` (`.:/workspace`, `infernix-web-node-modules`, and the live source-edit launcher posture) | The Linux launcher now uses a baked image snapshot and bind-mounts only `./.data/` plus the Docker socket and named build caches | Phase 1 Sprint 1.9 |
| `python/apple-silicon/`, `python/linux-cpu/`, and `python/linux-cuda/` project duplication | The supported Python boundary now closes through one `python/pyproject.toml` and one shared `python/adapters/` tree | Phase 4 Sprint 4.7 |
| `src/Generated/Contracts.hs` | The handwritten Haskell browser-contract source now lives under `src/Infernix/Web/Contracts.hs`; `Generated/` is reserved for generated output only | Phase 5 Sprint 5.7 |
| `chart/templates/httproutes/*.yaml`, route duplication in `src/Infernix/Models.hs`, route-specific expectations in `src/Infernix/Lint/Chart.hs`, and route or publication payload copies in `chart/values.yaml` | The supported route or publication contract now closes through one Haskell route registry, one data-driven HTTPRoute template, and structural chart defaults only | Phase 2 Sprint 2.3; Phase 3 Sprint 3.8 |
| `npx`-based Playwright workflow references in the supported CLI, docs, and web scripts | Supported Playwright workflows now use `npm --prefix web exec -- playwright ...` | Phase 1 Sprint 1.9; Phase 5 Sprint 5.5; Phase 6 Sprint 6.3 |
| Repeated workflow guidance across `README.md`, `AGENTS.md`, and `CLAUDE.md` | Root guidance now points to canonical documents in `documents/` instead of restating the full workflow contract in multiple places | Phase 1 Sprint 1.8 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
