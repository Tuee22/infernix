# Docker Policy

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define the supported outer-container control-plane workflow.

## Supported Usage

- `docker compose build infernix` refreshes the supported outer-container control-plane image
- `docker compose run --rm infernix infernix ...` is the supported Linux outer control-plane entrypoint
- the launcher container forwards the Docker socket
- the launcher container bind mounts repo state and `./.data/`
- the launcher container sets `/opt/build/infernix` as the supported outer build root
- cluster-backed outer-container commands keep host-published Kind API, edge, Harbor, MinIO, and Pulsar ports on `127.0.0.1`
- cluster-backed outer-container commands join the private Docker `kind` network and use `kind get kubeconfig --internal` plus control-plane container DNS for Kubernetes access instead of `host.docker.internal`
- the launcher image carries the repo-owned runtime and validation dependencies needed to compile and launch the control plane, including Node, Python, and `protoc`
- routed Playwright execution is delegated to the built web image rather than carrying duplicate browser binaries in the launcher image
- repo-root discovery works from the repo root and from nested working directories inside the bind-mounted workspace

## Unsupported Usage

- `docker compose up`
- `docker compose exec`
- unqualified containerized `cabal` flows that write into the mounted repository tree

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../development/local_dev.md](../development/local_dev.md)
