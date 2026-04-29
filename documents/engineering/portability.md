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
- the intended Apple clean-host contract reduces pre-existing host requirements to Homebrew plus
  ghcup and treats Colima as the only supported Docker environment
- Apple engine setup is daemon-driven and may use Homebrew, the host's built-in Python,
  system `clang`, and `python/.venv/`
- Apple does not rely on a Linux runtime image for inference

Current status:

- the current worktree still expects a broader Apple host toolchain on first use than the final
  minimal-prerequisite contract; clean-host bootstrap closure is tracked in
  [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

## Linux Rules

- `linux-cpu` and `linux-cuda` are containerized lanes built from `docker/linux-substrate.Dockerfile`
- the supported Linux control-plane launcher is a baked image snapshot, not a live repo mount
- Linux CPU host prerequisites stop at Docker Engine plus the Docker Compose plugin
- the Linux runtime path does not install dependencies at runtime with `apt`, `pip`, or `cabal build`

## CUDA-Specific Rules

- `linux-cuda` requires a supported NVIDIA host plus the NVIDIA Container Toolkit
- `linux-cuda` adds only the NVIDIA host prerequisites beyond the Linux CPU Docker baseline
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
