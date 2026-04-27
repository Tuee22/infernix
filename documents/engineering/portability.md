# Portability

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Separate the portable platform contract from substrate-specific execution detail.

## Portable Invariants

- the supported runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-cuda`
- Harbor-first bootstrap, manual `infernix-manual` storage, operator-managed Patroni PostgreSQL,
  Gateway API routing, and Pulsar-only production inference do not vary by substrate
- the generated active-mode catalog, publication contract, route inventory, and browser-visible
  base URL stay stable across supported runtime modes
- Python-native adapters always run through the shared `python/` Poetry project

## Apple Silicon Rules

- Apple Silicon is the only supported host-native inference lane
- the canonical Apple operator workflow runs `./.build/infernix ...` directly after a `cabal`
  install into `./.build/`
- Apple engine setup is daemon-driven and may use Homebrew, system `clang`, and `python/.venv/`
- Apple does not rely on a Linux runtime image for inference

## Linux Rules

- `linux-cpu` and `linux-cuda` are containerized lanes built from `docker/linux-substrate.Dockerfile`
- the supported Linux control-plane launcher is a baked image snapshot, not a live repo mount
- the Linux runtime path does not install dependencies at runtime with `apt`, `pip`, or `cabal build`

## CUDA-Specific Rules

- `linux-cuda` requires a supported NVIDIA host plus the NVIDIA Container Toolkit
- the supported CUDA cluster lifecycle requires `nvkind` from the baked substrate image
- host-visible `nvkind` rebuild or handoff paths are not part of the supported contract

## Unsupported Shortcuts

- repo-owned scripts or wrapper layers for supported workflows
- `docker compose up` or `docker compose exec` as operator entrypoints
- per-substrate Python projects, handwritten source under `Generated/`, or a separate web runtime image

## Cross-References

- [docker_policy.md](docker_policy.md)
- [implementation_boundaries.md](implementation_boundaries.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
