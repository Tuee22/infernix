# AGENTS.md

Repository instructions for automated agents and LLMs.

## Git Policy

Agents are not allowed to perform Git staging or publishing actions.

- Never run `git add`.
- Never run `git commit`.
- Never run `git push`.

These actions belong to the user only.

## Working Rules

- Make requested file changes directly in the working tree.
- Use read-only Git inspection commands when needed.
- Stop short of staging, creating commits, or pushing changes.
- Keep `DEVELOPMENT_PLAN/` truthful as implementation status changes.
- Treat `documents/` as the canonical home for architecture and operator guidance.
- Update `README.md`, `AGENTS.md`, and `CLAUDE.md` together when root workflow guidance changes.
- Do not add repo-owned scripts or wrappers for supported workflows.
- Use direct `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
  host builds unless a supported workflow requires different explicit output paths.
- Preserve the distinction between current implementation state and target platform contract in root
  docs.
- Keep the Harbor-first bootstrap narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: Harbor and only Harbor-required bootstrap support services may pull upstream before
  readiness, and every remaining non-Harbor workload pulls from Harbor afterward.
- Keep the PostgreSQL deployment narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the
  Percona Kubernetes operator, even when a chart can self-deploy PostgreSQL, and its PVCs stay on
  the manual `infernix-manual` storage doctrine.
- Keep the three-runtime build direction and the Kind HA testing or demo-ground direction aligned.
- Treat the demo UI (served by `infernix-demo`) as a demo surface on that HA substrate while
  carrying forward the matrix-wide coverage goal. Production deployments leave the demo UI off in
  the active `.dhall` and accept inference work via Pulsar subscription only.
- Custom platform logic is Haskell. Python is permitted only under `python/adapters/<engine>/` and
  only when the bound inference engine has no non-Python binding. Repo-owned Python is governed by
  `python/pyproject.toml` and Poetry; outside the cluster, Poetry materializes a repo-local
  adapter virtual environment on demand; inside the engine container, Poetry installs
  system-wide. Every adapter container build runs
  `tools/python_quality.sh` (mypy strict, black check, ruff strict) and fails on any check failure.
- The demo UI is PureScript. Frontend contracts are emitted into `web/src/Generated/` by
  `infernix internal generate-purs-contracts`, which derives them through `purescript-bridge`
  from dedicated Haskell browser-contract ADTs in `src/Generated/Contracts.hs`; the demo UI is
  built with spago and tested with `purescript-spec`.
- Run the repo-local docs validator via `infernix lint docs` before closing documentation changes.
