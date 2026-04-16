# Infernix Documents

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../DEVELOPMENT_PLAN/phase-0-documentation-and-governance.md](../DEVELOPMENT_PLAN/phase-0-documentation-and-governance.md)

> **Purpose**: Provide the governed documentation suite for architecture, development, engineering,
> operations, reference material, tools, and research notes.

## Suite Map

- [documentation_standards.md](documentation_standards.md) defines metadata, taxonomy, and SSoT rules
- [architecture/overview.md](architecture/overview.md) captures the supported platform topology
- [development/local_dev.md](development/local_dev.md) describes the supported local workflows
- [engineering/build_artifacts.md](engineering/build_artifacts.md) defines build-output isolation
- [operations/cluster_bootstrap_runbook.md](operations/cluster_bootstrap_runbook.md) describes the
  supported cluster bring-up and teardown path
- [reference/cli_reference.md](reference/cli_reference.md) records the canonical CLI surface

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

- Update the owning document when CLI surfaces, storage rules, routes, or runtime modes change.
- Update linked documents in the same change when a contract crosses boundaries.
- Run the docs validator before handing off changes.
