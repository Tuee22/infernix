# Docker Policy

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define the supported outer-container control-plane workflow.

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
- cluster-backed outer-container commands keep host-published Kind API and routed ports on
  `127.0.0.1`
- cluster-backed outer-container commands join the private Docker `kind` network and use
  `kind get kubeconfig --internal` plus control-plane container DNS for Kubernetes access instead
  of `host.docker.internal`
- the Linux substrate images carry the runtime and validation dependencies needed to launch the
  control plane, build the web bundle, run `poetry install`, regenerate protobuf stubs, and execute
  `poetry run check-code`
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

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../development/local_dev.md](../development/local_dev.md)
