# Docker Policy

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define the supported outer-container control-plane workflow.

## TL;DR

- Apple host-native flows use the operator's already selected native arm64 Docker daemon when
  Docker-backed work is required, but they must not create or switch Docker contexts or create a
  Colima VM. Linux control-plane execution runs through baked substrate images instead of live
  repo-mounted containers.
- `docker compose --project-name <lane> --file compose.yaml ... run --rm infernix infernix ...`
  is the supported Linux control-plane launcher shape for both `linux-cpu` and `linux-gpu`; the
  GPU lane uses the same single `compose.yaml` with an explicit one-shot `LAUNCHER_IMAGE`
  selector to choose the CUDA snapshot. Bootstrap scripts invoke that same shape after building
  the required launcher image.
- Routed Playwright execution on Linux runs inside the same substrate image with
  `npm --prefix web exec -- playwright test`.
- Buildx support is part of the supported Docker toolchain. Host bootstraps install the Docker
  buildx plugin, and the Linux substrate image installs `docker-buildx` for nested Compose builds
  that happen during routed E2E.
- Outer-container build state lives in the baked launcher image overlay; no docker-managed named
  volumes or host bind mounts back the outer-container build root or cabal package cache.
- The outer-container contract does not include `docker compose up`, `docker compose exec`, or a
  bootstrap helper-registry sidecar.
- Linux bootstrap scripts install Docker or the CUDA host stack only; they do not call Kind, Helm,
  Kubernetes manifest tooling, cluster workload image-pull orchestration, or image publication
  directly.
- Cross-architecture emulation is not part of the Docker policy. `linux-cpu` supports native
  Linux amd64 and native Linux arm64; Apple Silicon does not run an emulated amd64 Linux lane.

## Current Status

The current worktree follows the substrate-image policy directly: the image family
(`infernix-linux-cpu:local` and `infernix-linux-gpu:local`) comes from
`docker/Dockerfile` and owns the control plane, the baked `web/dist/` bundle, and
the Linux Playwright runtime. `compose.yaml` defines the single `infernix` service for both Linux
lanes, defaults to the CPU image, and accepts `LAUNCHER_IMAGE=infernix-linux-gpu:local` for the
GPU Docker Compose invocation. The service bind-mounts only `./.data/` and the Docker socket. The
Harbor-first bootstrap path does not depend on any helper-registry container cleanup.
Kind and `nvkind` cluster create or delete uses launcher-local scratch kubeconfig state under the
container temp directory, and the durable operator-facing kubeconfig is published afterward to
`./.data/runtime/infernix.kubeconfig`. The host Linux bootstrap installs `docker-buildx-plugin`,
and the Linux substrate image installs Ubuntu's `docker-buildx` package so nested Docker image
operations have a buildx-capable CLI when needed.

## Host Prerequisite Boundary

- on Apple Silicon, Docker-backed work requires the current Docker context to already target a
  native arm64 Docker daemon
- on the Apple host-native control-plane path, `./.build/infernix` must not create or switch
  Docker contexts, create a Colima VM, or use emulation before it attempts real cluster work
- on `linux-cpu`, host prerequisites stop at Docker Engine plus the Docker buildx and Compose
  plugins on native Linux amd64 or arm64
- on `linux-gpu`, host prerequisites stop at the `linux-cpu` Docker baseline plus the supported
  NVIDIA driver and container-toolkit setup
- the supported Linux host Docker baseline includes the Docker buildx plugin because Compose may
  select Bake-backed build behavior on current Docker installations
- every remaining control-plane, web, Poetry, Kubernetes, and Playwright dependency for Linux
  lives inside the shared substrate image

## Supported Usage

- `docker build -f docker/Dockerfile ...` is the manual image refresh surface;
  bootstrap scripts call that build before entering the launcher.
- `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix
  infernix ...` is the direct Linux CPU outer control-plane entrypoint.
- `LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu
  --file compose.yaml run --rm infernix infernix ...` is the direct Linux GPU outer control-plane
  entrypoint.
- the `infernix` launcher container forwards the Docker socket and bind-mounts only `./.data/`
  into `/workspace/.data`
- the `infernix` launcher container sets `/workspace/.build/outer-container/build` as the
  supported outer build root for the staged substrate file, while the source snapshot manifest
  lives separately at `/opt/infernix/source-snapshot-files.txt` in the image overlay and
  cabal-home plus the cabal builddir stay at the toolchain's natural in-image locations
  (`/root/.cabal/`, `dist-newstyle/`) rather than on any bind-mounted host path
- the supported Linux launcher reuses the chart archive cache baked into the image at
  `/opt/infernix/chart/charts/`; `/workspace/chart/charts` links to that image-local cache so
  Helm finds the top-level Harbor, PostgreSQL, Pulsar, MinIO, and Envoy Gateway dependencies
- the substrate image uses `tini` as its `ENTRYPOINT` so PID 1 forwards signals cleanly and reaps
  zombie processes for cluster lifecycle commands
- the baked launcher binaries under `/usr/local/bin/` are authoritative
- the shared substrate images bake `/opt/infernix/source-snapshot-files.txt` before later
  generated outputs are created so git-less image runs of `infernix lint files` validate the
  source snapshot rather than the mutated runtime tree; the manifest stays in the image overlay
- on the supported outer-container path, `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot selected by the launcher and publishes that image into
  Harbor before final rollout instead of asking the shell bootstrap to build or push images
  directly
- cluster-backed outer-container commands keep host-published Kind API and routed ports on
  `127.0.0.1`
- cluster-backed outer-container commands join the private Docker `kind` network and use
  `kind get kubeconfig --internal` plus control-plane container DNS for Kubernetes access instead
  of `host.docker.internal`
- on the supported outer-container path, Kind and `nvkind` create or delete the cluster against a
  launcher-local scratch kubeconfig under the container temp directory; the lifecycle publishes
  the durable operator-facing kubeconfig afterward to `./.data/runtime/infernix.kubeconfig`,
  keeping transient lock files off the bind-mounted repo tree
- on the Linux lane, in-container Playwright targets the Kind control-plane DNS on Docker's
  private `kind` network instead of `host.docker.internal`
- the Linux substrate images carry the runtime and validation dependencies needed to launch the
  control plane, build the web bundle, run `poetry install`, regenerate protobuf stubs, and execute
  `poetry run check-code`
- the Linux substrate images preinstall the project `ghc-9.12.4` toolchain; `ormolu` and `hlint`
  install through `cabal install` against that compiler into `./.build/haskell-style-tools/bin/`
- the Linux substrate image leaves GHCup shell-profile adjustment disabled and owns the toolchain
  `PATH` through Docker `ENV`; `Couldn't figure out login shell!` is therefore a regression if it
  appears in a freshly built image
- the Linux substrate image disables npm's update notifier; npm version changes must come through
  explicit image toolchain updates rather than lifecycle log notices

## Image Set

- `docker/Dockerfile` is the shared Linux substrate image definition; it produces
  the control-plane and cluster-resident daemon images, bakes the demo bundle, and carries the
  Linux Playwright runtime
- `RUNTIME_MODE=linux-cpu` with `BASE_IMAGE=ubuntu:24.04` produces `infernix-linux-cpu:local`
- `RUNTIME_MODE=linux-gpu` with
  `BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04` produces
  `infernix-linux-gpu:local`
- the substrate image installs Node.js 22.5+, the shared Poetry project, generated protobuf stubs,
  the built `web/dist/` bundle, Playwright browsers, and the `nvkind` binary during image build,
  and regenerates `web/package-lock.json` through `npm install` rather than tracking it under
  version control
- Apple Silicon has no substrate Dockerfile; the host-native workflow builds the
  `./.build/infernix` and `./.build/infernix-demo` binaries locally, uses `./.build/infernix` for
  ordinary operator commands and the host inference daemon, keeps the routed demo workload
  cluster-resident when `demo_ui` is enabled, and runs host-native routed E2E through host
  `npm exec` with the same typed fixture during Apple cohort validation batches

## Kind Containerd Registry Resolution

`renderKindConfig` in `src/Infernix/Cluster.hs` emits a `containerdConfigPatches` block in
the generated Kind config that enables containerd's hosts.toml-driven registry resolution:

```toml
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
```

Kind 0.31 does not emit this `config_path` by default. Without the patch, containerd inside
each Kind node ignores the `localhost:<harborPort>/hosts.toml` file that `writeRegistryHostsConfig`
provisions (via the `extraMounts` entry mapping
`./.build/kind/<runtime-mode>/registry` → `/etc/containerd/certs.d`), and kubelet dials
`localhost:<harborPort>` literally inside the node — where nothing listens — so every
Harbor-mirrored image pull fails with `connect: connection refused`. The registry-hosts root is
runtime-scoped so a CPU and GPU validation lane cannot overwrite each other's
`localhost:<harborPort>` mirror target. The patch is therefore part of the supported Kind config
contract; the binary owns it (operators do not hand-author Kind config).

## Unsupported Usage

- `docker compose up`
- `docker compose exec`
- unqualified containerized `cabal` flows that write into the mounted repository tree

## Validation

- `infernix docs check` fails if this governed Docker-policy document loses its required structure
  or metadata contract.
- direct `docker build -f docker/Dockerfile ...` commands produce the selected
  Linux substrate image.
- `docker volume ls` lists no `infernix-build` or `infernix-cabal-home` named volumes after a
  supported `compose down -v` sequence; outer-container build state stays in the launcher image
  overlay instead.
- `infernix test integration` and `infernix test e2e` exercise the supported outer-container
  launchers, routed surfaces, and image-reuse behavior on the Linux lanes when those lanes are
  selected; routed E2E closes through in-container Playwright on Linux.
- `infernix test all` runs every supported validation layer for the selected Linux substrate
  without reintroducing a live repo-mounted or helper-registry-based container workflow.
- routed E2E should not emit a Docker Compose Bake/buildx warning; if the warning returns after a
  substrate image rebuild, treat it as a tooling regression rather than nonfatal background noise.
- routed E2E should not fail with a missing `web/scripts/install-purescript.mjs`; if that error
  returns, the substrate Dockerfile has drifted from the web toolchain contract and must copy the
  web scripts before npm `postinstall`.

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../development/local_dev.md](../development/local_dev.md)
