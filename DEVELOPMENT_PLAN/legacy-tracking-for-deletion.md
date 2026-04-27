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

| Location | Why slated for removal | Owning phase or sprint |
|----------|------------------------|------------------------|
| Deleted legacy routing, image-build, and helper files still reported by `git ls-files` (`src/Infernix/Edge.hs`, `src/Infernix/Gateway.hs`, `src/Infernix/HttpProxy.hs`, `chart/templates/deployment-edge.yaml`, `chart/templates/service-edge.yaml`, `chart/templates/edge-configmap.yaml`, `docker/infernix.Dockerfile`, `docker/service.Dockerfile`, legacy `docker/*-python.Dockerfile`, `web/Dockerfile`, `tools/python_quality.sh`, `scripts/install-formatter.sh`) | The worktree deletions are landed, but repo policy forbids agent-owned staging, so tracked-index cleanup is still open | Phase 1 Sprint 1.7 |
| Generated artifacts still reported by `git ls-files` (`python/poetry.lock`, `web/spago.lock`, `tools/generated_proto/**`, tracked `*.pyc`, tracked `__pycache__/`) | Generated artifacts are deleted or ignored in the worktree but still need user-owned tracked-index cleanup | Phase 1 Sprint 1.7 |
| `docker/linux-base.Dockerfile`, `docker/linux-cpu.Dockerfile`, `docker/linux-cuda.Dockerfile` | The supported Linux image story closes through one shared `docker/linux-substrate.Dockerfile` that produces the two real Linux runtime images | Phase 4 Sprint 4.9 |
| Live repo-mount assumptions in `compose.yaml` (`.:/workspace`, `working_dir: /workspace`, `infernix-web-node-modules` volume) | The Linux launcher is moving to an image-snapshot model that bind-mounts only `./.data/` | Phase 1 Sprint 1.9 |
| `python/apple-silicon/`, `python/linux-cpu/`, and `python/linux-cuda/` project duplication | The supported Python boundary closes through one `python/pyproject.toml` and one shared `python/adapters/` tree | Phase 4 Sprint 4.7 |
| `src/Generated/Contracts.hs` | The handwritten Haskell browser-contract source belongs under `src/Infernix/Web/Contracts.hs`; `Generated/` is reserved for generated output only | Phase 5 Sprint 5.7 |
| `chart/templates/httproutes/*.yaml`, route duplication in `src/Infernix/Models.hs`, route-specific expectations in `src/Infernix/Lint/Chart.hs`, and route or publication payload copies in `chart/values.yaml` | The supported route or publication contract closes through one Haskell route registry and one data-driven HTTPRoute template; generated payloads do not live in stable chart defaults | Phase 2 Sprint 2.3; Phase 3 Sprint 3.8 |
| `npx playwright` workflow references in `web/package.json`, `src/Infernix/CLI.hs`, docs, and plan text | Supported Playwright workflows use `npm --prefix web exec -- playwright ...` | Phase 1 Sprint 1.9; Phase 5 Sprint 5.5; Phase 6 Sprint 6.3 |
| Repeated workflow guidance across `README.md`, `AGENTS.md`, and `CLAUDE.md` | Root guidance is moving to thinner governed entry docs that link to canonical documents in `documents/` | Phase 1 Sprint 1.8 |

## Pending Removal Details

The pending rows above fall into three categories:

- tracked-index cleanup that is blocked only by repo policy
- structural DRY cleanup where the replacement architecture is defined but not landed
- duplicate guidance cleanup where canonical ownership is defined but supporting docs still repeat it

## Completed

| Location | Why it was slated for removal | Owning phase or sprint |
|----------|-------------------------------|------------------------|
| `chart/templates/service-api.yaml`, the production HTTP service port surface, and the `infernix service --port` compatibility flag | Production `infernix service` is now consistently a no-HTTP daemon on the supported path | Phase 4 Sprint 4.8 |
| `tools/service_server.py` and the old Python HTTP API host | The demo HTTP surface now lives in `src/Infernix/Demo/Api.hs` and is served by `infernix-demo` | Phase 3 Sprint 3.6; Phase 4 Sprint 4.4 |
| `tools/runtime_backend.py`, `tools/runtime_worker.py`, `tools/runtime_fixture_backend.py`, `tools/final_engine_runner.py` | The monolithic Python runtime helpers are gone; runtime work now closes through Haskell plus the adapter boundary | Phase 4 Sprint 4.2; Phase 4 Sprint 4.5 |
| `tools/demo_config.py`, `tools/discover_chart_images.py`, `tools/discover_chart_claims.py`, `tools/list_harbor_overlay_images.py`, `tools/helm_chart_check.py`, `tools/platform_asset_check.py`, `tools/proto_check.py`, `tools/lint_check.py`, `tools/docs_check.py`, `tools/haskell_style_check.py`, `tools/publish_chart_images.py`, `tools/requirements.txt` | Control-plane tooling is Haskell-owned and no build-time Python remains on the supported control-plane path | Phase 1 Sprint 1.6 |
| Harbor chart-managed standalone PostgreSQL deployment path | Harbor and later PostgreSQL-backed services now use operator-managed Patroni clusters only | Phase 3 Sprint 3.2; Phase 6 Sprint 6.7 |
| Bootstrap helper-registry path on `localhost:30001` | Harbor-first bootstrap now mirrors only the final Harbor-backed image flow and no longer needs the helper registry | Phase 2 Sprint 2.4 |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
