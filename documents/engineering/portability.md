# Portability

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Separate the portable platform contract from substrate-specific execution detail.

## Executive Summary

- The product contract is portable across three runtime modes: `apple-silicon`, `linux-cpu`, and
  `linux-gpu`.
- The execution context is not the same thing as the runtime mode: Apple uses a host-native
  control plane, while Linux uses baked outer-container launchers.
- Harbor-first bootstrap, manual storage, operator-managed Patroni PostgreSQL, Gateway API
  routing, generated catalog behavior, and Pulsar-only production inference are platform invariants.
- Tool bootstrap, build-root paths, Docker setup, and CUDA device access are substrate detail.

## Current Status

The current worktree implements the intended split directly: Apple remains the only supported
host-native inference lane, Linux CPU and Linux CUDA remain the containerized lanes, and the repo
does not claim substrate parity where the underlying hardware or launcher model differs.

## Portable Platform Invariants

- the supported runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`
- Harbor-first bootstrap, the `infernix-manual` storage doctrine, operator-managed Patroni
  PostgreSQL, Gateway API routing, and Pulsar-only production inference do not vary by substrate
- the generated active-mode catalog, publication contract, route inventory, and browser-visible
  base URL stay stable across supported runtime modes
- Python-native adapters always run through the shared `python/` Poetry project
- supported validation entrypoints remain `infernix docs check`, `infernix test lint`,
  `infernix test unit`, `infernix test integration`, `infernix test e2e`, and `infernix test all`

## Supported Substrate Detail

| Topic | Portable contract | Apple host-native detail | Linux outer-container detail |
|-------|-------------------|--------------------------|------------------------------|
| Control-plane launcher | `infernix` owns lifecycle and validation behavior | use `./bootstrap/apple-silicon.sh <command>` as the supported stage-0 entrypoint; the direct reference surface remains `./.build/infernix ...` after host build into `./.build/` | use `./bootstrap/linux-cpu.sh <command>` or `./bootstrap/linux-gpu.sh <command>` as the supported stage-0 entrypoint; the direct reference surface remains `docker compose run --rm infernix infernix ...`, with `INFERNIX_COMPOSE_*` selecting `linux-gpu` |
| Host prerequisites | keep prerequisites minimal and explicit | Homebrew plus ghcup before build; Colima is the only supported Apple Docker environment | Docker Engine plus Compose plugin for `linux-cpu`; NVIDIA driver plus container toolkit in addition for `linux-gpu` |
| Tool bootstrap after the binary exists | supported commands may reconcile remaining operator tooling | Homebrew-managed Docker CLI, `kind`, `kubectl`, `helm`, Node.js, and Poetry bootstrap may be installed on demand | the substrate image already carries the supported toolchain; runtime install is not part of the contract |
| Build roots and kubeconfig location | outputs stay repo-local and untracked | `./.build/`, `./.build/infernix.kubeconfig`, and explicit `./.build/infernix internal materialize-substrate apple-silicon` staging | `./.build/outer-container/` on the host through the `./.build:/workspace/.build` bind mount, plus `./.data/runtime/infernix.kubeconfig` for durable outer-container reuse |
| Python adapter environment | use the shared Poetry project only | `python/.venv/` may materialize on demand through the host's built-in Python plus user-local Poetry bootstrap | adapter dependencies are installed in the shared substrate image build |
| Browser E2E runner | exercise the routed surface for the active generated catalog | the host CLI orchestrates `docker compose run --rm playwright` against the dedicated `infernix-playwright:local` image | the outer container forwards `docker compose run --rm playwright` through the mounted host docker socket against the same dedicated Playwright image |
| CUDA path | supported only when the host actually satisfies the NVIDIA contract | not applicable | `linux-gpu` requires the Compose-selected baked image, forwarded Docker socket, GPU visibility, and in-image `nvkind` |

## Unsupported Shortcuts

- ad hoc repo-owned scripts or wrapper layers beyond the supported `bootstrap/*.sh` stage-0
  entrypoints
- `docker compose up` or `docker compose exec` as operator entrypoints
- per-substrate Python projects, handwritten source under `Generated/`, or a separate web runtime image
- pretending Apple host-native inference and Linux outer-container inference are interchangeable
  substrate shapes when the underlying bootstrap and hardware contracts differ

## Cross-References

- [docker_policy.md](docker_policy.md)
- [implementation_boundaries.md](implementation_boundaries.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)

## Validation

- `infernix docs check` fails if this document loses its required structure or governed metadata.
- `infernix test integration` and `infernix test e2e` validate the generated active-mode catalog
  and routed surface against the active built substrate instead of silently substituting another
  substrate.
- the full repository closes only when Apple, Linux CPU, and Linux CUDA all pass on their
  supported lanes.
