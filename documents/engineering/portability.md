# Portability

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Separate the portable platform contract from substrate-specific execution detail.

## Executive Summary

- The product contract is portable across three runtime modes: `apple-silicon`, `linux-cpu`, and
  `linux-gpu`.
- The execution context is not the same thing as the runtime mode: Apple uses a host-native
  control plane, while Linux uses baked outer-container launchers.
- Development and validation are native-only. `linux-cpu` supports native Linux amd64 and native
  Linux arm64; Apple Silicon does not run an emulated amd64 Linux lane and must not create or
  switch Docker contexts or create a Colima VM.
- Harbor-first bootstrap, manual storage, operator-managed Patroni PostgreSQL, Gateway API
  routing, generated catalog behavior, and Pulsar-only production inference are platform invariants.
- Tool bootstrap, build-root paths, Docker setup, launcher build mechanics, and CUDA device access
  are substrate detail; Kind, Kubernetes manifests, image preparation, validation, and teardown
  remain binary-owned.
- The Apple Metal/Core ML native engine materialization lane is Apple substrate detail, not part
  of the portable contract: the target path uses a host Metal runtime bridge plus typed
  engine-artifact manifests, and the old Tart helper path is removed from the current host-tool
  schema and prerequisite contract.

## Current Status

The current worktree implements the intended split directly: Apple remains the only supported
host-native inference lane, while `linux-cpu` and `linux-gpu` remain the containerized lanes, and
the repo does not claim substrate parity where the underlying hardware or launcher model differs.
The Linux bootstrap surfaces treat login-shell and reboot boundaries as explicit rerun
checkpoints, and the Apple clean-host lane verifies same-process ghcup-managed tool activation
before direct host build handoff while keeping Docker reachability and Apple-only adapter
prerequisites substrate-specific. Apple Metal/Core ML materialization doctrine now avoids Tart,
user keychain state, and Xcode UI flows; Phase 1 Sprint 1.14 has removed the old `hostTart` /
`AppleTart` helper path, while real Apple native-engine output is owned by the reopened Phase 1 (Wave L). The supported doctrine forbids cross-architecture development
or validation, and Apple Docker-backed work validates the already selected native arm64 daemon
instead of provisioning or reconciling a Docker VM. The Apple routed Playwright lane runs
host-native `npm exec` against the published host edge on `127.0.0.1`, and retained Apple Kind
state is replayed between `./.data/kind/apple-silicon/` and the worker instead of being
bind-mounted. The lifecycle
also uses one cross-substrate kubeconfig policy: Kind and `nvkind` create or delete clusters
against execution-local scratch kubeconfig state under system temp, while the published
operator-facing kubeconfig remains repo-local in the active execution context.

## Portable Platform Invariants

- the supported runtime-mode ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`
- Harbor-first bootstrap, the `infernix-manual` storage doctrine, operator-managed Patroni
  PostgreSQL, Gateway API routing, and Pulsar-only production inference do not vary by substrate
- the generated active-mode catalog, publication contract, route inventory, and browser-visible
  base URL stay stable across supported runtime modes
- every substrate deploys the stateless `infernix-coordinator` Deployment for Pulsar
  coordination, single-flight dispatch, result-bridge, model-bootstrap, and model-to-pool routing;
  substrates differ only in where engine members run — Kubernetes workloads on Linux and
  same-binary on-host `infernix service` processes on Apple Silicon — with the demo-gated
  `infernix-demo` frontend deployed in-cluster on every substrate when `demo_ui = true`
- Python-native adapters always run through the shared `python/` Poetry project
- supported validation surfaces remain `infernix lint files`, `infernix lint docs`,
  `infernix lint proto`, `infernix lint chart`, `infernix docs check`, `infernix test lint`,
  `infernix test unit`, `infernix test integration`, `infernix test e2e`, and `infernix test all`

## Supported Substrate Detail

| Topic | Portable contract | Apple host-native detail | Linux outer-container detail |
|-------|-------------------|--------------------------|------------------------------|
| Control-plane launcher | `infernix` owns lifecycle and validation behavior | use `./bootstrap/apple-silicon.sh <command>` as the supported stage-0 entrypoint; the direct reference surface remains `./.build/infernix ...` after host build into `./.build/` | use `./bootstrap/linux-cpu.sh <command>` or `./bootstrap/linux-gpu.sh <command>` as the supported stage-0 entrypoint; the direct reference surface uses `docker compose --project-name infernix-linux-cpu --file compose.yaml ...` for CPU and prefixes the same Compose file with `LAUNCHER_IMAGE=infernix-linux-gpu:local` for GPU |
| Host prerequisites | keep prerequisites minimal and explicit | Homebrew plus ghcup before build; Docker-backed Apple work uses the already selected native arm64 Docker daemon and never creates or switches Docker contexts | Docker Engine plus Docker buildx and Compose plugins on native Linux amd64 or arm64 for `linux-cpu`; NVIDIA driver plus container toolkit in addition for `linux-gpu` |
| Bootstrap activation boundary | stage-0 bootstrap surfaces continue in the current process only after they can verify the executable they need next, and they stop for explicit rerun when a new shell or reboot is required | the bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables plus Homebrew `protoc` before direct `cabal install`, so the supported clean-host first run does not depend on a second bootstrap invocation | Linux bootstraps stop for Docker group-membership re-entry and NVIDIA-driver reboot, then continue through the same bootstrap surface on rerun |
| Tool bootstrap after the binary exists | supported commands may reconcile remaining operator tooling | Homebrew-managed Docker CLI, `kind`, `kubectl`, `helm`, Node.js, the Homebrew-managed `python@3.12` formula and `python3.12` command, and Poetry bootstrap may be installed on demand; Poetry may reuse an already available compatible Python 3.12+ executable | the substrate image already carries the supported toolchain; runtime install is not part of the contract |
| Native engine artifact build | engine adapters resolve from prebuilt host wheels/binaries, content-addressed engine payloads, or substrate-built native artifacts; the portable contract does not depend on any Tart lane | Apple Metal/Core ML artifacts materialize under `./.data/engines/<adapterId>/` through the headless host Metal runtime bridge and typed engine-artifact manifests described in [apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md); MLX, CTranslate2, ONNX Runtime, PyTorch MPS paths, and Audiveris prefer prebuilt host wheels or binaries. The old `hostTart` helper path is removed. | Python wheel engines need no tart; native roots come from the substrate image build under `/opt/infernix/engines/<adapterId>/`, while the worker still checks the repo data root first for parity with host-native execution. Current Linux roots are runtime-backed wrappers over image-baked native payloads; the reopened Phases 4/6 own full routed real-output delivery, with realness enforced by the realness lint. Wave K covers its then-active catalog, and Wave P closed post-replacement MT3 proof. |
| Apple Docker profile | Docker-backed lifecycle and validation work uses the operator-selected native daemon | Apple lifecycle code must not create a VM, create or switch Docker contexts, or use amd64 emulation; it stops if the current Docker daemon is unavailable or non-native | not applicable |
| Build roots and kubeconfig location | outputs stay repo-local and untracked, while Kind or `nvkind` create or delete uses transient execution-local scratch kubeconfig outside repo mounts | `./.build/`, published `./.build/infernix.kubeconfig`, and binary-owned substrate-file materialization or validation under the Apple build root | image-local outer-container build root and binary-owned substrate-file materialization there, plus published `./.data/runtime/infernix.kubeconfig` for durable outer-container reuse |
| Python adapter environment | use the shared Poetry project only | `python/.venv/` may materialize on demand after Apple adapter paths reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command plus a user-local Poetry bootstrap, or reuse an already available compatible Python 3.12+ executable for that bootstrap | adapter dependencies are installed in the shared substrate image build |
| Browser E2E runner | exercise the routed surface for the active generated catalog | host-native `npm exec` runs Playwright against the published localhost edge port using the same typed fixture; Apple evidence is recorded by the Apple cohort validation batch | the outer container runs `npm --prefix web exec -- playwright test` inside the substrate image against the routed cluster on Docker's private `kind` network |
| Inference executor placement | the supported three-role daemon model splits Pulsar coordination (`infernix-coordinator`) from engine execution pools; coordinator daemons own request fan-in, batching, model-to-pool routing, result publication, and eager model-weight staging on startup from the mounted `infernix.dhall`; engine members own adapter execution and the in-memory KV cache. No daemon has a PVC; engine pods use ephemeral `emptyDir` for the model-weight cache only. Memory admission is a shared typed policy over `modelRamFootprintMib` and `InferenceMemoryBudget`, with typed `ModelMemoryLimitExceeded` on over-budget requests. See [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../architecture/engine_pool_routing.md](../architecture/engine_pool_routing.md), and [object_storage.md](object_storage.md). | the cluster-side `infernix-coordinator` Deployment runs the coordinator role and hands batches to Apple host-daemon pool members over derived Pulsar topics; normal pools use `Shared` across distinct host ids and exact-host routes use `Exclusive`; host engines pull weights from MinIO `infernix-models`, run Apple-native engines, and publish results. The on-host executor bounds the disk model-weight cache and admits model memory against unified host RAM after the Colima pledge and reserve; one oversized model does not invalidate the whole daemon | the cluster-side `infernix-coordinator` Deployment runs the coordinator role, and separate cluster-side engine workloads run Linux pools with Kubernetes placement rules; on `linux-cpu`, admission uses the engine pod memory limit; on `linux-gpu`, admission uses GPU VRAM. Framework-specific GPU pools can render as isolated per-engine Deployments; all daemon pods are PVC-free |
| CUDA path | supported only when the host actually satisfies the NVIDIA contract | not applicable | `linux-gpu` requires the launcher-selected baked CUDA image, forwarded Docker socket, GPU visibility, and in-image `nvkind` |

## Unsupported Shortcuts

- ad hoc repo-owned scripts or wrapper layers beyond the supported `bootstrap/*.sh` stage-0
  entrypoints
- any cross-architecture development or validation run, including amd64 Linux under Apple Silicon
  emulation
- creating or switching Docker contexts, or creating a Colima VM, from the Apple Silicon workflow
- bootstrap shell code that directly manages Kind clusters, Kubernetes manifests, Helm rollout,
  cluster workload image pulls, Harbor publication, validation internals, or destructive artifact
  cleanup
- `docker compose up` or `docker compose exec` as operator entrypoints
- per-substrate Python projects, handwritten source under `Generated/`, or a separate web runtime image
- pretending Apple host-native inference and Linux outer-container inference are interchangeable
  substrate shapes when the underlying bootstrap and hardware contracts differ

## Native Architecture Contract

The Apple Silicon substrate runs cluster workloads natively as `linux/arm64`. The `linux-cpu`
substrate runs on native Linux amd64 or native Linux arm64. The supported control plane does not
depend on Rosetta, QEMU, or any other cross-architecture emulation layer; the publication path
pulls and pushes native image variants, the chart's MinIO sub-chart uses upstream multi-arch
images (no `bitnamilegacy/*`), and Kind nodes run native `kindest/node` images for the active
host architecture. The substrate → container-architecture
mapping is owned by [../architecture/runtime_modes.md](../architecture/runtime_modes.md) (see
the "Substrate Architecture" subsection); this document does not duplicate the table.

## Cross-References

- [docker_policy.md](docker_policy.md)
- [host_tools_manifest.md](host_tools_manifest.md)
- [apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md)
- [implementation_boundaries.md](implementation_boundaries.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../tools/minio.md](../tools/minio.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)

## Validation

- `infernix docs check` fails if this document loses its required structure or governed metadata.
- `infernix test integration` and `infernix test e2e` validate the generated active-mode catalog
  and routed surface against the active built substrate instead of silently substituting another
  substrate.
- the full repository closes only when `apple-silicon`, `linux-cpu`, and `linux-gpu` all pass on
  their supported lanes.
