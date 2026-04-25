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
- [architecture/web_ui_architecture.md](architecture/web_ui_architecture.md) describes the
  PureScript demo UI topology and the two-binary cluster image layout
- [development/local_dev.md](development/local_dev.md) describes the supported local workflows
- [development/python_policy.md](development/python_policy.md) defines when Python is allowed
  (engine adapters under `python/adapters/<engine>/` only), the Poetry workflow, and the strict
  mypy/black/ruff quality gate integrated into every adapter container build
- [development/purescript_policy.md](development/purescript_policy.md) defines the PureScript
  toolchain (purs, spago), the `purescript-spec` test framework, and the `purescript-bridge`
  contract derivation from Haskell ADTs in `src/Infernix/Demo/Api.hs`
- [engineering/build_artifacts.md](engineering/build_artifacts.md) defines build-output isolation
- [operations/cluster_bootstrap_runbook.md](operations/cluster_bootstrap_runbook.md) describes the
  supported cluster bring-up and teardown path
- [tools/postgresql.md](tools/postgresql.md) records the supported operator-managed PostgreSQL
  contract
- [tools/pulsar.md](tools/pulsar.md) records the production inference subscription and dispatch
  contract (`request_topics`, `result_topic`, `engines` in the active `.dhall`)
- [reference/cli_reference.md](reference/cli_reference.md) records the canonical CLI surface for
  both `infernix` and `infernix-demo`
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
- `README.md` stays an orientation document and links into this suite instead of becoming the deep
  architecture source of truth.

## Maintenance

- Update the owning document when CLI surfaces, storage rules, PostgreSQL topology, routes, or runtime modes change.
- Update linked documents in the same change when a contract crosses boundaries.
- Supported workflow docs use direct `cabal`, `docker compose`, and `infernix` commands rather
  than repo-owned scripts or wrapper layers.
- Run the docs validator before handing off changes.
