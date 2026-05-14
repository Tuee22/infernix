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
host-native inference lane, while `linux-cpu` and `linux-gpu` remain the containerized lanes, and
the repo does not claim substrate parity where the underlying hardware or launcher model differs.
The Linux bootstrap surfaces treat login-shell and reboot boundaries as explicit rerun
checkpoints, and the Apple clean-host lane now verifies same-process ghcup-managed tool activation
before direct host build handoff while still keeping Colima sizing, Docker reachability, and
Apple-only adapter prerequisites substrate-specific. The Apple routed Playwright lane probes the
published host edge on `127.0.0.1` but runs the dedicated browser container on the private Docker
`kind` network against the Kind control-plane DNS, and retained Apple Kind state is replayed
between `./.data/kind/apple-silicon/` and the worker instead of being bind-mounted.

## Portable Platform Invariants

- the supported runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`
- Harbor-first bootstrap, the `infernix-manual` storage doctrine, operator-managed Patroni
  PostgreSQL, Gateway API routing, and Pulsar-only production inference do not vary by substrate
- the generated active-mode catalog, publication contract, route inventory, and browser-visible
  base URL stay stable across supported runtime modes
- every substrate deploys cluster `infernix-service` daemons; Apple differs only by delegating
  Apple-native inference execution from the cluster daemon to same-binary host daemons through
  Pulsar host batches
- Python-native adapters always run through the shared `python/` Poetry project
- supported validation surfaces remain `infernix lint files`, `infernix lint docs`,
  `infernix lint proto`, `infernix lint chart`, `infernix docs check`, `infernix test lint`,
  `infernix test unit`, `infernix test integration`, `infernix test e2e`, and `infernix test all`

## Supported Substrate Detail

| Topic | Portable contract | Apple host-native detail | Linux outer-container detail |
|-------|-------------------|--------------------------|------------------------------|
| Control-plane launcher | `infernix` owns lifecycle and validation behavior | use `./bootstrap/apple-silicon.sh <command>` as the supported stage-0 entrypoint; the direct reference surface remains `./.build/infernix ...` after host build into `./.build/` | use `./bootstrap/linux-cpu.sh <command>` or `./bootstrap/linux-gpu.sh <command>` as the supported stage-0 entrypoint; the direct reference surface remains `docker compose run --rm infernix infernix ...`, with `INFERNIX_COMPOSE_*` selecting `linux-gpu` |
| Host prerequisites | keep prerequisites minimal and explicit | Homebrew plus ghcup before build; Colima is the only supported Apple Docker environment | Docker Engine plus Compose plugin for `linux-cpu`; NVIDIA driver plus container toolkit in addition for `linux-gpu` |
| Bootstrap activation boundary | stage-0 bootstrap surfaces continue in the current process only after they can verify the executable they need next, and they stop for explicit rerun when a new shell or reboot is required | the bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables plus Homebrew `protoc` before direct `cabal install`, so the supported clean-host first run does not depend on a second bootstrap invocation | Linux bootstraps stop for Docker group-membership re-entry and NVIDIA-driver reboot, then continue through the same bootstrap surface on rerun |
| Tool bootstrap after the binary exists | supported commands may reconcile remaining operator tooling | Homebrew-managed Docker CLI, `kind`, `kubectl`, `helm`, Node.js, Homebrew `python@3.12`, and Poetry bootstrap may be installed on demand | the substrate image already carries the supported toolchain; runtime install is not part of the contract |
| Apple Docker profile | Docker-backed lifecycle and validation work uses one supported local Docker envelope | Colima is the only supported Apple Docker environment, and Apple lifecycle code reconciles it to at least `8 CPU / 16 GiB` before Kind- or Playwright-backed work proceeds | not applicable |
| Build roots and kubeconfig location | outputs stay repo-local and untracked | `./.build/`, `./.build/infernix.kubeconfig`, and explicit `./.build/infernix internal materialize-substrate apple-silicon` staging | `./.build/outer-container/` on the host through the `./.build:/workspace/.build` bind mount, plus `./.data/runtime/infernix.kubeconfig` for durable outer-container reuse |
| Python adapter environment | use the shared Poetry project only | `python/.venv/` may materialize on demand after Apple adapter paths reconcile Homebrew `python@3.12` plus a user-local Poetry bootstrap | adapter dependencies are installed in the shared substrate image build |
| Browser E2E runner | exercise the routed surface for the active generated catalog | the host CLI probes routed readiness on `127.0.0.1:<edge-port>` and then orchestrates `docker compose run --rm playwright` on the private Docker `kind` network against the Kind control-plane DNS using the dedicated `infernix-playwright:local` image | the outer container forwards `docker compose run --rm playwright` through the mounted host docker socket against the same dedicated Playwright image |
| Inference executor placement | cluster daemons always own request fan-in and result publication semantics | Apple cluster daemons hand batches to host daemons over Pulsar so Apple-native engines can run on the host | Linux cluster daemons perform fan-in, batching, inference, and result publication directly |
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
- the full repository closes only when `apple-silicon`, `linux-cpu`, and `linux-gpu` all pass on
  their supported lanes.
