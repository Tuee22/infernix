# Docker Policy

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define the supported outer-container control-plane workflow.

## TL;DR

- Apple host-native flows use Colima plus the host Docker CLI, but Linux control-plane execution
  runs through baked substrate images instead of live repo-mounted containers.
- `docker compose run --rm infernix infernix ...` is the supported `linux-cpu` launcher, and
  direct `docker run --gpus all infernix-linux-cuda:local infernix ...` is the supported
  `linux-cuda` launcher.
- The outer-container contract does not include `docker compose up`, `docker compose exec`, or a
  bootstrap helper-registry sidecar.

## Current Status

The current worktree follows the one-image-family policy directly: both supported Linux runtime
lanes come from `docker/linux-substrate.Dockerfile`, `cluster up` reuses the already-built
`infernix-linux-<mode>:local` snapshots, and the Harbor-first bootstrap path no longer depends on
any retired helper-registry container cleanup.

## Host Prerequisite Boundary

- on Apple Silicon, Colima is the only supported Docker environment
- on the Apple host-native control-plane path, `./.build/infernix` reconciles Homebrew-managed
  Colima and the Docker CLI before it attempts real cluster work
- on `linux-cpu`, host prerequisites stop at Docker Engine plus the Docker Compose plugin
- on `linux-cuda`, host prerequisites stop at the `linux-cpu` Docker baseline plus the supported
  NVIDIA driver and container-toolkit setup
- every remaining control-plane, web, Poetry, Playwright, and Kubernetes toolchain dependency for
  Linux lives inside the shared substrate images

## Supported Usage

- `docker compose build infernix` refreshes the supported Linux CPU outer-container image
- `docker compose run --rm infernix infernix ...` is the supported Linux CPU outer control-plane
  entrypoint
- `docker build -f docker/linux-substrate.Dockerfile --build-arg RUNTIME_MODE=linux-cuda --build-arg BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04 -t infernix-linux-cuda:local .`
  and `docker run --rm --gpus all ... infernix-linux-cuda:local infernix ...` are the supported
  CUDA launcher equivalents
- the launcher container forwards the Docker socket
- the launcher container bind-mounts only `./.data/`
- the launcher container sets `/opt/build/infernix` as the supported outer build root
- the baked launcher binaries under `/usr/local/bin/` are authoritative; any compatibility copies
  refreshed into `/opt/build/infernix` do not take precedence on `PATH`
- the shared substrate images bake `/opt/build/infernix/source-snapshot-files.txt` before later
  generated outputs are created so git-less image runs of `infernix lint files` validate the
  source snapshot rather than the mutated runtime tree
- on the supported outer-container path, `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding the same runtime image again inside
  the launcher
- cluster-backed outer-container commands keep host-published Kind API and routed ports on
  `127.0.0.1`
- cluster-backed outer-container commands join the private Docker `kind` network and use
  `kind get kubeconfig --internal` plus control-plane container DNS for Kubernetes access instead
  of `host.docker.internal`
- the Linux substrate images carry the runtime and validation dependencies needed to launch the
  control plane, build the web bundle, run `poetry install`, regenerate protobuf stubs, and execute
  `poetry run check-code`
- the Linux substrate images also preinstall the compatible ghcup-managed GHC used to bootstrap
  `hlint` for the Haskell style gate when the active project compiler is newer than the current
  `hlint` release line
- routed Playwright execution is delegated to the host on Apple Silicon and to the active Linux
  substrate image on Linux

## Image Set

- `docker/linux-substrate.Dockerfile` is the shared Linux image definition
- `RUNTIME_MODE=linux-cpu` with `BASE_IMAGE=ubuntu:24.04` produces `infernix-linux-cpu:local`
- `RUNTIME_MODE=linux-cuda` with
  `BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04` produces
  `infernix-linux-cuda:local`
- the shared image installs Node.js 22+, the web toolchain, Playwright browser deps, the shared
  Poetry project, generated protobuf stubs, and the `nvkind` binary during image build
- Apple Silicon has no Dockerfile; the host-native workflow builds and runs the binaries directly

## Unsupported Usage

- `docker compose up`
- `docker compose exec`
- unqualified containerized `cabal` flows that write into the mounted repository tree

## Validation

- `infernix docs check` fails if this governed Docker-policy document loses its required structure
  or metadata contract.
- `infernix test integration` and `infernix test e2e` exercise the supported outer-container
  launchers, routed surfaces, and image-reuse behavior on the Linux lanes when those lanes are
  selected.
- `infernix test all` reruns the full supported matrix entrypoints without reintroducing a live
  repo-mounted or helper-registry-based container workflow.

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../development/local_dev.md](../development/local_dev.md)
