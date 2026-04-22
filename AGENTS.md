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
- Use direct `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix`
  host builds unless a supported workflow requires different explicit output paths.
- Preserve the distinction between current implementation state and target platform contract in root
  docs.
- Keep the Harbor-first bootstrap narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: Harbor and only Harbor-required bootstrap support services may pull upstream before
  readiness, and every remaining non-Harbor workload pulls from Harbor afterward.
- Keep the three-runtime build direction and the Kind HA testing or demo-ground direction aligned.
- Treat the webapp as a demo surface on that HA substrate while carrying forward the matrix-wide
  coverage goal.
- Run the repo-local docs validator before closing documentation changes.
