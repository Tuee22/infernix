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
- [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md)
- [documents/development/no_env_vars.md](documents/development/no_env_vars.md)
- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

## Non-Negotiable Rules

- never run `git add`
- never run `git commit`
- never run `git push`
- keep `DEVELOPMENT_PLAN/` aligned with the current implementation state
- review `README.md`, `AGENTS.md`, and `CLAUDE.md` together when repository workflow guidance or
  the supported bootstrap entrypoints change
- run `infernix lint docs` before closing documentation changes
- no Haskell `lookupEnv` / `getEnv` / `setEnv` calls in new code; no `proc "<bare-name>"`
  external invocations; no `env:` blocks in infernix-owned chart templates; no `process.env` or
  `os.environ` reads in web / Python code. The supported configuration substrate is the typed
  `.dhall` files documented in [documents/architecture/configuration_doctrine.md](documents/architecture/configuration_doctrine.md);
  the lint enforcement (Phase 6 Sprint 6.28) rejects violations

## Scope

The canonical assistant workflow lives in
[documents/development/assistant_workflow.md](documents/development/assistant_workflow.md). This
root file is only the entry point. Supported stage-0 host bootstrap entrypoints live under
`bootstrap/` and are documented in [README.md](README.md) and
[documents/development/local_dev.md](documents/development/local_dev.md). Those bootstrap
entrypoints are restartable prerequisite reconcilers: they verify same-process tool activation
before continuing, stop at explicit rerun boundaries when a new shell or reboot is required, and
delegate cluster lifecycle, Kubernetes manifests, cluster workload image pulls, Harbor
publication, validation, and teardown behavior to the `infernix` binary.
