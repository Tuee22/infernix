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
