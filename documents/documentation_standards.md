# Documentation Standards

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [../DEVELOPMENT_PLAN/development_plan_standards.md](../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define how the governed `documents/` suite is structured, updated, and kept aligned
> with `DEVELOPMENT_PLAN/`, `README.md`, and the repository implementation.

## TL;DR

- `documents/` is the only canonical documentation root.
- Governed docs require metadata, relative links, and clear topic ownership.
- Broad doctrine docs use stronger structure: summary first, explicit current-status notes when
  current and target behavior mix, and validation sections when tests or lint prove the contract.
- `src/Infernix/Lint/Docs.hs` is the mechanical enforcement point for the governed docs suite.

## Metadata Block

Every governed Markdown document under `documents/` starts with this block:

```markdown
# Title

**Status**: Authoritative source | Supporting reference | Draft
**Referenced by**: [relative/link.md](relative/link.md)

> **Purpose**: One-sentence summary.
```

Rules:

- the `# Title` line is the first non-empty line in the file
- `**Status**:` is required
- `**Referenced by**:` is required, even when there is only one cross-reference
- the purpose quote block is required

## Broad Doctrine Structure

Broad governed docs that define repository doctrine use stronger structure than a short reference
page.

Rules:

- include `## TL;DR` or `## Executive Summary` when the topic is broad
- include `## Current Status` when implemented behavior and target direction appear in the same doc
- include `## Validation` when tests or lint prove the contract
- use explicit tables or matrices when a plan sprint calls for ownership, durability, or matrix
  detail as a closure condition
- answer these questions directly when relevant: what is the rule, what is current versus target,
  how is it validated, and what is local substrate detail versus the true platform contract

## Governed Root Documents

The governed root documents use a parallel metadata block so readers and automation can distinguish
orientation or entry guidance from canonical topic ownership.

```markdown
# Title

**Status**: Governed orientation document | Governed entry document
**Supersedes**: short statement describing the root-level duplication this file replaces
**Canonical homes**: [documents/...](documents/...), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

> **Purpose**: One-sentence summary.
```

Rules:

- `README.md` uses `**Status**: Governed orientation document`
- `AGENTS.md` and `CLAUDE.md` use `**Status**: Governed entry document`
- every governed root doc carries both `**Supersedes**:` and `**Canonical homes**:` lines
- root docs summarize and link; they do not become parallel canonical homes for workflow or
  architecture topics

## Taxonomy

The canonical suite layout is:

```text
documents/
├── README.md
├── documentation_standards.md
├── architecture/
├── development/
├── engineering/
├── operations/
├── reference/
├── tools/
└── research/
```

Rules:

- `documents/` is the only canonical documentation root
- `docs/` is not introduced
- new top-level categories require an update to this file and `documents/README.md`

## Source Of Truth

- `DEVELOPMENT_PLAN/` owns phase order, current implementation status, and closure criteria.
- `documents/` owns architecture and operator guidance once the relevant document exists.
- `README.md` is a governed orientation layer and points to canonical documents instead of
  duplicating them.
- `AGENTS.md` and `CLAUDE.md` are governed entry documents and must stay aligned with workflow
  guidance when repository-level rules change.
- `documents/development/assistant_workflow.md` is the canonical repository-level assistant
  workflow document; `AGENTS.md` and `CLAUDE.md` summarize and link to it.
- supporting-reference docs may narrow or operationalize a topic already owned elsewhere, but they
  point back to the canonical owner instead of presenting a second authoritative home.

## Naming And Linking

- file names are lowercase snake_case with a `.md` suffix
- relative Markdown links are required for in-repo references
- each governed doc links to at least one other governed source
- route names, commands, paths, and binaries use backticks

## Content Rules

- write current-state declarative guidance, not migration diaries
- keep one canonical home per topic
- move implementation status discussion into `DEVELOPMENT_PLAN/`
- keep examples aligned with the supported `infernix` CLI surface
- document the supported `bootstrap/*.sh` stage-0 entrypoints together with the direct `cabal`,
  `docker compose`, and `infernix` commands they drive; do not add extra wrapper layers beyond
  that bounded bootstrap surface

## Update Rules

- when the CLI surface changes, update `documents/reference/cli_reference.md`,
  `documents/reference/cli_surface.md`, their generated command-registry sections, and any
  impacted runbooks in the same change
- when storage rules change, update `documents/engineering/k8s_storage.md`,
  `documents/engineering/storage_and_state.md`, and the relevant phase document in the same change
- when PostgreSQL topology changes, update `documents/tools/postgresql.md`,
  `documents/tools/harbor.md`, `documents/engineering/k8s_storage.md`, and the relevant phase
  document in the same change
- when route prefixes change, update `documents/engineering/edge_routing.md`,
  `documents/reference/web_portal_surface.md`, and the relevant phase document in the same change
- when assistant-facing repository workflow rules change, update
  `documents/development/assistant_workflow.md`, `AGENTS.md`, and `CLAUDE.md` in the same change
- when the root workflow changes, review `README.md`, `AGENTS.md`, and `CLAUDE.md` in the same change

## Validation

The repo-local documentation validator checks:

- required metadata lines for governed `documents/` content
- required structure for the named broad doctrine docs whose headings are part of the supported
  contract
- governed root-document metadata lines (`Status`, `Supersedes`, `Canonical homes`, purpose)
- governed document existence for the canonical bootstrap set
- relative link resolution for governed docs, governed root docs, and phase-plan docs
- root README references to both `documents/` and `DEVELOPMENT_PLAN/`
- registry-generated CLI sections in `documents/reference/cli_reference.md` and
  `documents/reference/cli_surface.md`
- registry-generated route sections in the governed route docs and the route summary block in
  `README.md`
- the explicit monitoring stance across governed docs, plan docs, and chart values
- `DEVELOPMENT_PLAN/` phase documents retaining their `## Documentation Requirements` section
