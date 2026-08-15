# Documentation Standards

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [../DEVELOPMENT_PLAN/development_plan_standards.md](../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define how the governed `documents/` suite is structured and updated as the
> prescriptive declaration of the target architecture — the statement the implementation is aligned
> *to*, not a report aligned *from* it.

## TL;DR

- `documents/` is the only canonical documentation root.
- Governed docs require metadata, relative links, and clear topic ownership.
- **`documents/` declares the target; it never reports status.** See [Prescriptive Voice](#prescriptive-voice).
- Broad doctrine docs use stronger structure: summary first, and validation sections naming the
  gates that enforce the contract.
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
- `**Referenced by**:` lists governed docs or plan sections that reference **or are closely related
  to** this document. It is a topical navigation aid, not a guarantee of a reciprocal link: an entry
  `X` need not itself link back here, and the validator checks only that each named target resolves
  to an existing file
- the purpose quote block is required

## Broad Doctrine Structure

Broad governed docs that define repository doctrine use stronger structure than a short reference
page.

Rules:

- include `## TL;DR` or `## Executive Summary` when the topic is broad
- include `## Validation` when tests or lint are the enforcement point for the contract — a gate
  that is currently red still declares the contract, and that red is the backlog
- use explicit tables or matrices when a plan sprint calls for ownership, durability, or matrix
  detail as a closure condition
- answer these questions directly when relevant: what is the rule, how is it enforced, and what is
  local substrate detail versus the true platform contract

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

## Prescriptive Voice

A governed document states **what the system must do**, in present-tense declarative voice, whether
or not the implementation has landed. It never reports schedule, sprint ownership, validation dates,
or wave evidence. Those belong to `DEVELOPMENT_PLAN/`.

**Prescriptive does not mean silent about limits.** A target may — and should — declare what it does
*not* cover. One question separates the two:

> **Is this true of the target, or true only of today?**

| Permanent property of the target — **keep** | Temporal report — **belongs in the plan** |
|---|---|
| "Darwin provides neither cgroups nor an enforced address-space limit, so the Apple bound is arithmetic rather than enforcement" | "the Apple lane is measured by its own cohort wave" |
| "a `linux-gpu` budget naming one resource fails plan compilation with `GpuDualResourceBudgetRequired`" | "the transitional wire cannot yet express both, so current compilation fails closed" |
| "page cache, kernel slab, and processes infernix did not start are outside the bound" | "Sprint 1.21 owns the build-memory kernel; Sprint 6.46 owns the spawn boundary" |
| "the fleet's membership is the authority for model eligibility; the system contract cannot substitute for it" | "code-side closed on a date; a cohort wave remains in progress" |

The left column is the target declaring its own boundaries — that is doctrine, and a doc that omits
it over-claims. The right column is status.

Consequences worth stating, because each has been got wrong:

- **A document is not edited when its target ships.** If the doc already declared the behavior, a
  sprint reaching `Done` produces no doc change. Editing docs to track what now works is the
  anti-pattern this section exists to forbid.
- **A document is not kept alive because the thing it describes still exists.** When a surface is
  retired from the target, its doc goes with it, even if the code has not been removed yet. The
  removal is the plan's job to schedule and the doc's job to stop declaring.
- **Do not annotate a doc with its own future.** A retirement notice, a "scheduled for removal"
  banner, or a sprint reference inside a governed doc is status wearing a doctrine costume.

Banned vocabulary, because each reports a schedule rather than a contract: `reopened`, `code-side`,
`superseded`, `in progress`, `implementation is present`, `remains open`, `not yet landed`,
`as it exists today`, `remains Active`.

Both halves are gates, not conventions. `infernix lint docs` rejects a `## Current Status` heading in
any governed document, including the root `README.md`, `AGENTS.md`, and `CLAUDE.md`; equivalent
audit, implementation-state, repository-status, and validation-status headings are rejected too.
The lint also rejects wave, sprint, date, and numbered-phase provenance, plus narrowly enumerated
retired topology claims: repository-owned HA or leader election, within-role replicas,
exactly-once delivery, coordinator-survivor recovery, pod/node failure injection, and Patroni
replica reinitialization. Pulsar `Failover` remains valid when it names the broker's single-active
subscription coordination. The vocabulary above is rejected through `forbiddenPhrases`. This file
is the single allowlisted exception — the standard that defines a prohibition has to be able to
spell it — which is the same carve-out the configuration-override check already uses for the
documents whose subject is that prohibition. No architecture document receives a whole-file
status exception.

## Source Of Truth

- `documents/` owns the target: the architecture and operator guidance the system must satisfy.
- `DEVELOPMENT_PLAN/` owns the gap: phase order, implementation status, and closure criteria.
- Code and tests carry reality. A declared target whose implementation has not landed keeps its
  declaration, its code fails closed rather than fabricating, and its test goes red — that red is
  the honest backlog.
- The two do not reconcile to one another, because they answer different questions. A governed doc
  disagreeing with today's behavior is not a defect in the doc; it is the gap, and the gap is
  tracked in `DEVELOPMENT_PLAN/`.
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

- write target-state declarative guidance, not migration diaries and not status reports
- keep one canonical home per topic
- move implementation status discussion into `DEVELOPMENT_PLAN/`
- keep examples aligned with the supported `infernix` CLI surface
- document the supported `bootstrap/*.sh` stage-0 entrypoints as bounded prerequisite and launcher
  builders: they may install host prerequisites and build or enter the substrate-specific
  `infernix` launcher, but cluster lifecycle, Kubernetes manifests, cluster workload image pulls,
  Harbor publication, validation, and teardown behavior must be described as binary-owned
- no governed doc may reference project-prefixed env names or shell path overrides as a supported
  operator override; the supported configuration substrate is the typed `.dhall` files named in
  [architecture/configuration_doctrine.md](architecture/configuration_doctrine.md). No governed
  document is exempt, and the validator carries no allowlist: a document that must quote a
  third-party upstream environment contract reintroduces a narrow, occupied exemption in the
  validator rather than inheriting a standing one. Mentions in
  [DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
  sit outside the governed suite the validator scans.
- the Linux launcher image selector is a narrow Compose invocation detail documented in
  [engineering/docker_policy.md](engineering/docker_policy.md), not an operator configuration
  override. It may be named when explaining direct Linux GPU reference commands.

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
- when the object-access paradigm changes (how the browser reaches MinIO — presigned URL versus
  webapp object-proxy, the external file-gateway surface), update
  `documents/architecture/object_access_doctrine.md`, `documents/architecture/durable_context_design.md`,
  `documents/engineering/edge_routing.md`, `documents/engineering/object_storage.md`, and the
  relevant phase document in the same change
- when per-user isolation rules change (the canonical identity claim, server-side namespacing, or
  the trust-boundary authorization for objects and chat), update
  `documents/architecture/tenant_isolation_doctrine.md`, `documents/architecture/object_access_doctrine.md`,
  and the relevant phase document in the same change
- when the admin/user role model changes (the admin realm role, the JWT role claim, or which surfaces
  are admin-gated versus per-user), update `documents/architecture/access_control_doctrine.md`,
  `documents/engineering/edge_routing.md`, `documents/architecture/web_ui_architecture.md`, and the
  relevant phase document in the same change
- when the config layering changes (which facts are fleet-wide versus per-machine, the pool
  selection surface, the content pin between the two contracts, or what a machine may author),
  update `documents/architecture/configuration_doctrine.md`,
  `documents/architecture/typed_execution_plan.md`,
  `documents/architecture/engine_pool_routing.md`,
  `documents/engineering/host_tools_manifest.md`, `documents/tools/pulsar.md`, and the relevant
  phase document in the same change
- when the delivery-semantics contract changes (acknowledgement ordering, redelivery, producer
  deduplication, or what "once" means at the effect layer), update
  `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`, and
  `documents/engineering/object_storage.md` in the same change; note
  `documents/architecture/pulsar_ml_workflow.md` is shared verbatim with the jitML sister project
  and must not be forked for an infernix-specific delivery statement
- when the host-memory capacity ledger changes (the declared build budget and its concurrency, the
  per-lane enforcement mechanism, the victim rank, or the statement of what is not bounded), update
  `documents/architecture/bounded_host_memory.md`, `documents/architecture/bounded_inference_memory.md`,
  `documents/development/local_dev.md`, `documents/development/testing_strategy.md`,
  `documents/engineering/build_artifacts.md`, `documents/engineering/testing.md`,
  `documents/engineering/host_tools_manifest.md`, the three-way `README.md` / `AGENTS.md` /
  `CLAUDE.md`
  mirror with `documents/development/assistant_workflow.md`, and the relevant phase document in the
  same change
- when the inference-memory-safety contract changes (the `MemoryGrant` / capped-engine chokepoint, the
  `HostMemoryPartition`, the required `ModelMemoryFootprint`, the enforcer-typed `InferenceMemoryBudget`,
  or the admission policy), update `documents/architecture/bounded_inference_memory.md`,
  `documents/architecture/bounded_host_memory.md`,
  `documents/architecture/typed_execution_plan.md`,
  `documents/architecture/runtime_modes.md`, `documents/architecture/daemon_topology.md`,
  `documents/operations/apple_silicon_runbook.md`, the `documents/architecture/realness_contract.md`
  admission cross-reference, and the relevant phase document in the same change
- when the generated execution-plan language changes (its Dhall unions, raw-to-compiled boundary,
  runtime refinement evidence, command policies, model-placement graph, or resource-indexed
  enforcers), update `documents/architecture/typed_execution_plan.md`,
  `documents/architecture/configuration_doctrine.md`,
  `documents/architecture/bounded_inference_memory.md`,
  `documents/architecture/managed_state_transitions.md`, `documents/architecture/runtime_modes.md`,
  `documents/architecture/daemon_topology.md`, `documents/architecture/realness_contract.md`,
  `documents/engineering/cluster_config_manifest.md`, `documents/development/testing_strategy.md`,
  the relevant runbook, and the owning phase documents in the same change
- when the cluster-ownership / lifecycle-state contract changes (the `ClusterOwner`, the
  `ClusterMutating` lifecycle position, the evidence-gated `clusterDown` seizure, the fail-closed
  lifecycle persistence, or the `cluster status` owner / mutation-incomplete output fields), update
  `documents/architecture/managed_state_transitions.md`, `documents/reference/cli_reference.md`,
  `documents/reference/cli_surface.md` (with their generated command-registry sections),
  `documents/development/testing_strategy.md`, `documents/engineering/storage_and_state.md`,
  `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`,
  and the relevant phase document in the same change
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
