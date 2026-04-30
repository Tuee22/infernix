# Documentation Standards

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [../DEVELOPMENT_PLAN/development_plan_standards.md](../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define how the governed `documents/` suite is structured, updated, and kept aligned
> with `DEVELOPMENT_PLAN/`, `README.md`, and the repository implementation.

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
- document direct `cabal`, `docker compose`, and `infernix` invocations rather than repo-owned
  scripts or wrapper layers

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
- governed root-document metadata lines (`Status`, `Supersedes`, `Canonical homes`, purpose)
- governed document existence for the canonical bootstrap set
- relative link resolution for governed docs, governed root docs, and phase-plan docs
- root README references to both `documents/` and `DEVELOPMENT_PLAN/`
- registry-generated CLI sections in `documents/reference/cli_reference.md` and
  `documents/reference/cli_surface.md`
- registry-generated route sections in the governed route docs and the route summary block in
  `README.md`
- `DEVELOPMENT_PLAN/` phase documents retaining their `## Documentation Requirements` section
