# Assistant Workflow

**Status**: Authoritative source
**Referenced by**: [../../AGENTS.md](../../AGENTS.md), [../../CLAUDE.md](../../CLAUDE.md)

> **Purpose**: Define the canonical repository-level workflow rules for automated agents and LLM
> coding assistants.

## Scope

This document is the canonical home for assistant-facing repository workflow rules. `AGENTS.md`
and `CLAUDE.md` stay as governed entry documents that summarize and link here instead of carrying
parallel long-form workflow contracts.

## Non-Negotiable Rules

- make requested file changes directly in the working tree
- use read-only Git inspection commands when needed
- never run `git add`
- never run `git commit`
- never run `git push`
- keep `DEVELOPMENT_PLAN/` truthful as implementation status changes
- use `documents/` as the canonical home for architecture, development, engineering, operations,
  and reference guidance
- update `README.md`, `AGENTS.md`, and `CLAUDE.md` together when root workflow guidance changes
- keep repo-owned shell limited to the supported `bootstrap/*.sh` stage-0 host bootstrap surface;
  control-plane behavior and validation remain Haskell- or Compose-owned

## Supported Build And Operator Workflows

- prefer the supported stage-0 bootstrap entrypoints:
  `./bootstrap/apple-silicon.sh`, `./bootstrap/linux-cpu.sh`, and `./bootstrap/linux-gpu.sh`
- use direct host builds:
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
- on the supported Linux outer-container path, `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding the identical runtime image inside
  the launcher
- preserve the distinction between current implementation state and the target platform contract in
  root docs

## Platform Doctrine To Preserve

- keep the Harbor-first bootstrap narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: Harbor and only Harbor-required bootstrap support services may pull upstream before
  readiness, and every remaining non-Harbor workload pulls from Harbor afterward
- keep the PostgreSQL deployment narrative aligned across `README.md`, `DEVELOPMENT_PLAN/`, and
  `documents/`: every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the
  Percona Kubernetes operator, even when a chart can self-deploy PostgreSQL, and its PVCs stay on
  the manual `infernix-manual` storage doctrine
- keep the three-runtime build direction and the Kind HA testing or demo-ground direction aligned
- treat the demo UI (served by `infernix-demo`) as a demo surface on that HA substrate while
  preserving the README-matrix coverage ledger; production deployments leave the demo UI off in
  the active `.dhall` and accept inference work via Pulsar subscription only
- routing is owned by Gateway API resources and repo-owned HTTPRoute manifests; the demo cluster is
  local-only and carries no auth filter
- custom platform logic is Haskell; Python is permitted only under `python/adapters/` and only
  when the bound inference engine has no non-Python binding
- the shared Poetry project lives at `python/pyproject.toml`; all adapter execution goes through
  `poetry run`, and the canonical quality gate is `poetry run check-code`
- on Apple Silicon, Colima is the only supported Docker environment, the minimal pre-existing host
  prerequisites are Homebrew plus ghcup, and `infernix` reconciles the remaining Homebrew-managed
  tools plus Poetry bootstrap when adapter flows need them
- Apple host paths materialize `python/.venv/` only on demand, after `infernix` bootstraps a
  user-local `poetry` executable after reconciling Homebrew `python@3.12` at
  `/opt/homebrew/opt/python@3.12/bin/python3.12` when necessary
- Linux substrate images install adapter dependencies during image build, and Linux host
  prerequisites stop at Docker plus the NVIDIA host prerequisites for `linux-gpu`
- the demo UI is PureScript; frontend contracts are emitted into `web/src/Generated/` by
  `infernix internal generate-purs-contracts`, which derives them through `purescript-bridge`
  from dedicated Haskell browser-contract ADTs in `src/Infernix/Web/Contracts.hs`
- the demo UI is built with spago and tested with `purescript-spec`
- the tracked repository limits repo-owned shell to `bootstrap/*.sh` and carries no committed
  generated artifacts such as Poetry lockfiles, generated protobuf stubs, `*.pyc`,
  `web/spago.lock`, or `web/src/Generated/`

## Validation Before Handoff

- run the repo-local docs validator via `infernix lint docs` before closing documentation changes

## Cross-References

- [local_dev.md](local_dev.md)
- [../documentation_standards.md](../documentation_standards.md)
- [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)
