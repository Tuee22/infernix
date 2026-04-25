# CLAUDE.md

Instructions for Claude and other LLM-based coding assistants working in this repository.

## Git Restrictions

LLMs must not perform user-owned Git write actions.

- Do not run `git add`.
- Do not run `git commit`.
- Do not run `git push`.

Those actions are reserved for the user.

## Allowed Workflow

- You may inspect the repository and edit files locally when asked.
- You may use read-only Git commands such as `git status` and `git diff` to understand the current state.
- Leave staging, committing, and pushing to the user.
- Keep `DEVELOPMENT_PLAN/` aligned with the current implementation state.
- Use `documents/` for canonical architecture, development, engineering, operations, and reference guidance.
- Review `README.md`, `AGENTS.md`, and `CLAUDE.md` together when repository workflow guidance changes.
- Do not add repo-owned scripts or wrappers for supported workflows.
- Use direct `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
  host builds unless a supported workflow requires different explicit output paths.
- Keep root docs explicit about what is implemented today versus what remains target-state intent.
- Keep the Harbor-first bootstrap narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: Harbor and only Harbor-required bootstrap support services may pull upstream before
  readiness, and every remaining non-Harbor workload pulls from Harbor afterward.
- Keep the PostgreSQL deployment narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the
  Percona Kubernetes operator, even when a chart can self-deploy PostgreSQL, and its PVCs stay on
  the manual `infernix-manual` storage doctrine.
- Keep the three-runtime build direction and the Kind HA testing or demo-ground direction aligned.
- Treat the demo UI (served by the `infernix-demo` binary, gated by the active `.dhall` `demo_ui`
  flag) as a demo surface while retaining the three-runtime and matrix-coverage intent. Production
  deployments leave the demo UI off and accept inference work via Pulsar subscription only.
- Custom platform logic is Haskell. Python is permitted only under `python/adapters/<engine>/` and
  only when the bound inference engine has no non-Python binding. Repo-owned Python is governed by
  `python/pyproject.toml` and Poetry; outside the cluster, Poetry materializes `./.venv/`; inside
  the engine container, Poetry installs system-wide. Every adapter container build runs
  `tools/python_quality.sh` (mypy strict, black check, ruff strict) and fails on any check failure.
- The demo UI is PureScript. Frontend types are derived from Haskell ADTs in
  `src/Infernix/Demo/Api.hs` via `purescript-bridge` into `web/src/Generated/`; the demo UI is
  built with spago and tested with `purescript-spec`.
