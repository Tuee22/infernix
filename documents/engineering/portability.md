# Portability

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Separate the portable platform contract from substrate-specific execution detail.

## Executive Summary

- The product contract is portable across three runtime modes: `apple-silicon`, `linux-cpu`, and
  `linux-gpu`.
- The execution context is not the same thing as the runtime mode: Apple uses a host-native
  control plane, while Linux uses baked outer-container launchers.
- Harbor-first bootstrap, manual storage, operator-managed Patroni PostgreSQL, Gateway API
  routing, generated catalog behavior, and Pulsar-only production inference are platform invariants.
- Tool bootstrap, build-root paths, Docker setup, launcher build mechanics, and CUDA device access
  are substrate detail; Kind, Kubernetes manifests, image preparation, validation, and teardown
  remain binary-owned.

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
between `./.data/kind/apple-silicon/` and the worker instead of being bind-mounted. The lifecycle
also uses one cross-substrate kubeconfig policy: Kind and `nvkind` create or delete clusters
against execution-local scratch kubeconfig state under system temp, while the published
operator-facing kubeconfig remains repo-local in the active execution context.

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
| Control-plane launcher | `infernix` owns lifecycle and validation behavior | use `./bootstrap/apple-silicon.sh <command>` as the supported stage-0 entrypoint; the direct reference surface remains `./.build/infernix ...` after host build into `./.build/` | use `./bootstrap/linux-cpu.sh <command>` or `./bootstrap/linux-gpu.sh <command>` as the supported stage-0 entrypoint; the direct reference surface uses `docker compose --project-name infernix-linux-cpu --file compose.yaml ...` for CPU and adds `--file compose.linux-gpu.yaml` for GPU |
| Host prerequisites | keep prerequisites minimal and explicit | Homebrew plus ghcup before build; Colima is the only supported Apple Docker environment | Docker Engine plus Docker buildx and Compose plugins for `linux-cpu`; NVIDIA driver plus container toolkit in addition for `linux-gpu` |
| Bootstrap activation boundary | stage-0 bootstrap surfaces continue in the current process only after they can verify the executable they need next, and they stop for explicit rerun when a new shell or reboot is required | the bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables plus Homebrew `protoc` before direct `cabal install`, so the supported clean-host first run does not depend on a second bootstrap invocation | Linux bootstraps stop for Docker group-membership re-entry and NVIDIA-driver reboot, then continue through the same bootstrap surface on rerun |
| Tool bootstrap after the binary exists | supported commands may reconcile remaining operator tooling | Homebrew-managed Docker CLI, `kind`, `kubectl`, `helm`, Node.js, the Homebrew-managed `python@3.12` formula and `python3.12` command, and Poetry bootstrap may be installed on demand; Poetry may reuse an already available compatible Python 3.12+ executable | the substrate image already carries the supported toolchain; runtime install is not part of the contract |
| Apple Docker profile | Docker-backed lifecycle and validation work uses one supported local Docker envelope | Colima is the only supported Apple Docker environment, and Apple lifecycle code reconciles it to at least `8 CPU / 16 GiB` before Kind- or Playwright-backed work proceeds | not applicable |
| Build roots and kubeconfig location | outputs stay repo-local and untracked, while Kind or `nvkind` create or delete uses transient execution-local scratch kubeconfig outside repo mounts | `./.build/`, published `./.build/infernix.kubeconfig`, and binary-owned substrate-file materialization or validation under the Apple build root | image-local outer-container build root and binary-owned substrate-file materialization there, plus published `./.data/runtime/infernix.kubeconfig` for durable outer-container reuse |
| Python adapter environment | use the shared Poetry project only | `python/.venv/` may materialize on demand after Apple adapter paths reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command plus a user-local Poetry bootstrap, or reuse an already available compatible Python 3.12+ executable for that bootstrap | adapter dependencies are installed in the shared substrate image build |
| Browser E2E runner | exercise the routed surface for the active generated catalog | the Apple host-native routed-E2E executor refactor is deferred and surfaces an explicit diagnostic until the Apple validation pass | the outer container runs `npm --prefix web exec -- playwright test` inside the substrate image against the routed cluster on Docker's private `kind` network |
| Inference executor placement | the supported three-role daemon model splits Pulsar coordination (`infernix-coordinator`) from engine execution (`infernix-engine`); coordinator daemons own request fan-in, batching, result publication, and the lazy model-weight bootstrap workflow; engine daemons own adapter execution and the node's in-memory KV cache under a strict one-per-node policy uniform across substrates. No daemon has a PVC; engine pods use ephemeral `emptyDir` for the model-weight cache only. See [../architecture/daemon_topology.md](../architecture/daemon_topology.md) and [object_storage.md](object_storage.md). | the cluster-side `infernix-coordinator` Deployment runs the coordinator role and hands batches to the on-host engine daemon over Pulsar; the host daemon enforces one-per-node via `flock(2)` on `engine.lock`, pulls weights from MinIO `infernix-models`, runs Apple-native engines, and publishes results | the cluster-side `infernix-coordinator` Deployment runs the coordinator role, and a separate cluster-side `infernix-engine` Deployment runs the engine role with required one-per-node anti-affinity; on `linux-gpu` the engine pod claims all local NVIDIA devices; both pods are PVC-free |
| CUDA path | supported only when the host actually satisfies the NVIDIA contract | not applicable | `linux-gpu` requires the Compose-selected baked image, forwarded Docker socket, GPU visibility, and in-image `nvkind` |

## Unsupported Shortcuts

- ad hoc repo-owned scripts or wrapper layers beyond the supported `bootstrap/*.sh` stage-0
  entrypoints
- bootstrap shell code that directly manages Kind clusters, Kubernetes manifests, Helm rollout,
  cluster workload image pulls, Harbor publication, validation internals, or destructive artifact
  cleanup
- `docker compose up` or `docker compose exec` as operator entrypoints
- per-substrate Python projects, handwritten source under `Generated/`, or a separate web runtime image
- pretending Apple host-native inference and Linux outer-container inference are interchangeable
  substrate shapes when the underlying bootstrap and hardware contracts differ

## Cross-References

- [docker_policy.md](docker_policy.md)
- [implementation_boundaries.md](implementation_boundaries.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)

## Validation

- `infernix docs check` fails if this document loses its required structure or governed metadata.
- `infernix test integration` and `infernix test e2e` validate the generated active-mode catalog
  and routed surface against the active built substrate instead of silently substituting another
  substrate.
- the full repository closes only when `apple-silicon`, `linux-cpu`, and `linux-gpu` all pass on
  their supported lanes.
