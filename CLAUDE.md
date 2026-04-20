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
- Use the repo-owned `./cabalw ...` wrapper on the Apple host path so Cabal output stays under
  `./.build/cabal`; only pass explicit `--builddir` overrides when a supported workflow requires
  them.
- Keep root docs explicit about what is implemented today versus what remains target-state intent.
- Keep the Harbor-first bootstrap narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: Harbor and only Harbor-required bootstrap support services may pull upstream before
  readiness, and every remaining non-Harbor workload pulls from Harbor afterward.
- Keep the three-runtime build direction and the Kind HA testing or demo-ground direction aligned.
- Treat the cluster-resident webapp as a demo surface while retaining the three-runtime and
  matrix-coverage intent.
