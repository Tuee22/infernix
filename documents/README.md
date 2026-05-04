# Infernix Documents

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../DEVELOPMENT_PLAN/phase-0-documentation-and-governance.md](../DEVELOPMENT_PLAN/phase-0-documentation-and-governance.md)

> **Purpose**: Provide the governed documentation suite for architecture, development, engineering,
> operations, reference material, tools, and research notes.

## Suite Map

- [documentation_standards.md](documentation_standards.md) defines metadata, taxonomy, and SSoT rules
- [architecture/overview.md](architecture/overview.md) captures the supported platform topology
  (two-binary `infernix` + `infernix-demo` doctrine, Pulsar-only production surface, demo HTTP
  via `infernix-demo`)
- [architecture/runtime_modes.md](architecture/runtime_modes.md) defines the supported
  control-plane execution contexts, runtime-mode ids, and generated substrate-file contract
- [architecture/model_catalog.md](architecture/model_catalog.md) defines the generated model-catalog
  contract derived from the README matrix
- [architecture/web_ui_architecture.md](architecture/web_ui_architecture.md) describes the
  PureScript demo UI topology and the two-binary cluster image layout
- [development/local_dev.md](development/local_dev.md) describes the supported local workflows
- [development/assistant_workflow.md](development/assistant_workflow.md) defines the canonical
  repository-level workflow rules for automated agents and LLM coding assistants
- [development/haskell_style.md](development/haskell_style.md) defines the enforced Haskell
  formatter, linter, and compiler-warning gate
- [development/python_policy.md](development/python_policy.md) defines when Python is allowed
  (shared adapter modules under `python/adapters/` only), the Poetry
  workflow, and the strict mypy/black/ruff quality gate surfaced as `poetry run check-code`
- [development/purescript_policy.md](development/purescript_policy.md) defines the PureScript
  toolchain (purs, spago), the `purescript-spec` test framework, and the Haskell-owned generated
  contract derivation consumed by the demo UI
- [development/frontend_contracts.md](development/frontend_contracts.md) records the Haskell-owned
  PureScript contract-generation path and browser-visible catalog contract
- [development/testing_strategy.md](development/testing_strategy.md) records operator-facing
  validation-lane detail, active-substrate selection, and implemented coverage beneath the canonical testing
  doctrine
- [development/chaos_testing.md](development/chaos_testing.md) records the current HA-failure
  validation status and the Phase 6 ownership for that coverage
- [engineering/build_artifacts.md](engineering/build_artifacts.md) defines build-output isolation
- [engineering/docker_policy.md](engineering/docker_policy.md) defines the supported
  outer-container control-plane workflow
- [engineering/edge_routing.md](engineering/edge_routing.md) defines the registry-owned public
  route contract and edge-port behavior
- [engineering/implementation_boundaries.md](engineering/implementation_boundaries.md) defines
  the ownership boundaries across Haskell, Python, chart assets, and generated outputs
- [engineering/k8s_native_dev_policy.md](engineering/k8s_native_dev_policy.md) records the
  supported real Kind workflow and the lack of a simulated Kubernetes path
- [engineering/k8s_storage.md](engineering/k8s_storage.md) defines the manual PV/PVC doctrine and
  operator-managed claim ownership
- [engineering/model_lifecycle.md](engineering/model_lifecycle.md) records the generated catalog,
  durable artifact, and runtime-cache lifecycle contract
- [engineering/object_storage.md](engineering/object_storage.md) defines how MinIO-backed objects
  surface through the demo API
- [engineering/portability.md](engineering/portability.md) defines the portable contract versus
  Apple- or Linux-specific execution details
- [engineering/storage_and_state.md](engineering/storage_and_state.md) records the authoritative
  durable-versus-derived state map
- [engineering/testing.md](engineering/testing.md) defines the canonical validation doctrine and
  fail-fast behavior
- [operations/apple_silicon_runbook.md](operations/apple_silicon_runbook.md) describes the
  supported Apple host-native operator path
- [operations/cluster_bootstrap_runbook.md](operations/cluster_bootstrap_runbook.md) describes the
  supported cluster bring-up and teardown path
- [reference/api_surface.md](reference/api_surface.md) records the demo-only routed HTTP API
  surface served by `infernix-demo`
- [reference/cli_surface.md](reference/cli_surface.md) provides the short-form binary and command
  family overview
- [tools/postgresql.md](tools/postgresql.md) records the supported operator-managed PostgreSQL
  contract
- [tools/pulsar.md](tools/pulsar.md) records the production inference subscription and dispatch
  contract (`request_topics`, `result_topic`, `engines` in the active `.dhall`) together with the
  repo-local topic-spool harness used by unit-level validation
- [reference/cli_reference.md](reference/cli_reference.md) records the canonical CLI surface for
  both `infernix` and `infernix-demo`
- [reference/web_portal_surface.md](reference/web_portal_surface.md) records the browser-visible
  routed demo and operator surface
- [tools/harbor.md](tools/harbor.md) records the Harbor-first bootstrap and routed Harbor contract
- [tools/minio.md](tools/minio.md) records the durable object-storage and routed MinIO contract
- [research/README.md](research/README.md) reserves the non-authoritative research subtree used for
  exploratory notes

## Taxonomy

- `architecture/` explains platform structure and supported runtime shapes
- `development/` explains day-to-day contributor workflows and validation
- `engineering/` explains implementation contracts and storage, routing, and build policy
- `operations/` explains supported operational runbooks
- `reference/` explains stable user-facing surfaces
- `tools/` explains third-party systems that `infernix` manages
- `research/` holds non-authoritative investigation notes

## Source Of Truth Rules

- `DEVELOPMENT_PLAN/` owns implementation status, phase order, and closure criteria.
- `documents/` owns architecture guidance, operator workflow guidance, and reference material.
- `documents/development/assistant_workflow.md` owns the canonical assistant-facing repository
  workflow rules.
- Monitoring is not a supported first-class surface. The governed docs suite intentionally has no
  canonical `documents/engineering/monitoring.md` until the supported platform contract changes.
- `README.md` stays an orientation document and links into this suite instead of becoming the deep
  architecture source of truth.
- `AGENTS.md` and `CLAUDE.md` stay as governed entry documents with explicit `Canonical homes`
  links back into this suite and into `development/assistant_workflow.md`.

## Maintenance

- Update the owning document when CLI surfaces, storage rules, PostgreSQL topology, routes, or runtime modes change.
- Update linked documents in the same change when a contract crosses boundaries.
- When root workflow guidance changes, update the governed metadata and canonical-home links in
  `README.md`, `AGENTS.md`, and `CLAUDE.md` in the same change.
- If monitoring ever becomes a supported first-class surface, add the canonical doctrine doc,
  update this index, update the plan, and update docs lint in the same change.
- Supported workflow docs describe the bounded `bootstrap/*.sh` stage-0 entrypoints and the direct
  `cabal`, `docker compose`, and `infernix` commands those entrypoints invoke.
- Run the docs validator before handing off changes.
