# CLAUDE.md

**Status**: Governed entry document
**Supersedes**: older root-level workflow duplication for LLM coding assistants
**Canonical homes**: [documents/README.md](documents/README.md), [documents/documentation_standards.md](documents/documentation_standards.md), [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md), [documents/development/local_dev.md](documents/development/local_dev.md), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

> **Purpose**: Provide a thin automation-oriented entry document that points Claude-style agents at
> the canonical workflow and implementation-status docs.

Instructions for Claude and other LLM-based coding assistants working in this repository.

Read first:

- [documents/development/assistant_workflow.md](documents/development/assistant_workflow.md)
- [documents/development/local_dev.md](documents/development/local_dev.md)
- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

## Non-Negotiable Rules

- never run `git add`
- never run `git commit`
- never run `git push`
- keep `DEVELOPMENT_PLAN/` aligned with the current implementation state
- review `README.md`, `AGENTS.md`, and `CLAUDE.md` together when repository workflow guidance or
  the supported bootstrap entrypoints change
- run `infernix lint docs` before closing documentation changes

## Scope

The canonical assistant workflow lives in
[documents/development/assistant_workflow.md](documents/development/assistant_workflow.md). This
root file is only the entry point. Supported stage-0 host bootstrap entrypoints live under
`bootstrap/` and are documented in [README.md](README.md) and
[documents/development/local_dev.md](documents/development/local_dev.md).
