# Docker Policy

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define the supported outer-container control-plane workflow.

## TL;DR

- Apple host-native flows use Colima plus the host Docker CLI, but Linux control-plane execution
  runs through baked substrate images instead of live repo-mounted containers.
- `docker compose run --rm infernix infernix ...` is the supported Linux control-plane launcher
  shape for both `linux-cpu` and `linux-gpu`; `INFERNIX_COMPOSE_IMAGE`,
  `INFERNIX_COMPOSE_SUBSTRATE`, and `INFERNIX_COMPOSE_BASE_IMAGE` select the active built
  snapshot when the default CPU lane is not in play.
- Routed Playwright execution closes through the dedicated `infernix-playwright:local` image
  invoked via `docker compose run --rm playwright`; the substrate image carries no
  browser-runtime weight.
- Outer-container build state lives under `./.build/outer-container/` on the host through a
  single `./.build:/workspace/.build` bind mount; no docker-managed named volumes back the
  outer-container build root or cabal package cache.
- The outer-container contract does not include `docker compose up`, `docker compose exec`, or a
  bootstrap helper-registry sidecar.

## Current Status

The current worktree follows the two-image-family policy directly: the substrate image family
(`infernix-linux-cpu:local` and `infernix-linux-gpu:local`) comes from
`docker/linux-substrate.Dockerfile` and owns the control plane plus the baked `web/dist/` bundle;
the dedicated `infernix-playwright:local` image comes from `docker/playwright.Dockerfile` and owns
routed E2E execution for every substrate. `compose.yaml` defines an `infernix` service for the
control plane and a `playwright` service for routed E2E, and bind-mounts `./.data/`, `./.build/`,
and the host `compose.yaml` into the `infernix` service together with the Docker socket. The
Harbor-first bootstrap path no longer depends on any retired helper-registry container cleanup.

## Host Prerequisite Boundary

- on Apple Silicon, Colima is the only supported Docker environment
- on the Apple host-native control-plane path, `./.build/infernix` reconciles Homebrew-managed
  Colima and the Docker CLI before it attempts real cluster work
- on `linux-cpu`, host prerequisites stop at Docker Engine plus the Docker Compose plugin
- on `linux-gpu`, host prerequisites stop at the `linux-cpu` Docker baseline plus the supported
  NVIDIA driver and container-toolkit setup
- every remaining control-plane, web, Poetry, and Kubernetes toolchain dependency for Linux lives
  inside the shared substrate image; the Playwright runtime and browsers live inside the dedicated
  `infernix-playwright:local` image instead of the substrate image

## Supported Usage

- `docker compose build infernix` refreshes the default Linux CPU outer-container image
- `docker compose build playwright` refreshes the dedicated Playwright image
- `docker compose run --rm infernix infernix ...` is the supported Linux outer control-plane
  entrypoint for both `linux-cpu` and `linux-gpu`
- `docker compose run --rm playwright` is the supported routed E2E executor invocation; the same
  service definition serves Apple Silicon (host-direct invocation) and the Linux substrates (the
  outer container forwards the call through the mounted host docker socket)
- exporting `INFERNIX_COMPOSE_IMAGE=infernix-linux-gpu:local`,
  `INFERNIX_COMPOSE_SUBSTRATE=linux-gpu`, and
  `INFERNIX_COMPOSE_BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04` before
  `docker compose build infernix` prepares the supported `linux-gpu` snapshot for that same
  Compose-driven control plane
- the `infernix` launcher container forwards the Docker socket and bind-mounts `./.data/`,
  `./.build/`, and the host `./compose.yaml` (read-only) into `/workspace/`
- the `infernix` launcher container sets `/workspace/.build/outer-container/build` as the
  supported outer build root for the staged substrate file and the source snapshot manifest,
  while cabal-home and the cabal builddir live at the toolchain's natural in-image locations
  (`/root/.cabal/`, `dist-newstyle/`) and are not bind-mounted to the host
- the substrate image uses `tini` as its `ENTRYPOINT` so PID 1 forwards signals cleanly and reaps
  zombie processes for cluster lifecycle commands
- when the outer container shells out to `docker compose run --rm playwright`, it forwards
  `INFERNIX_HOST_REPO_ROOT` so the host docker daemon resolves the playwright service's bind
  mounts against the host repo root
- the baked launcher binaries under `/usr/local/bin/` are authoritative; any compatibility copies
  refreshed under `${INFERNIX_BUILD_ROOT}` do not take precedence on `PATH`
- the shared substrate images bake `/opt/infernix/source-snapshot-files.txt` before later
  generated outputs are created so git-less image runs of `infernix lint files` validate the
  source snapshot rather than the mutated runtime tree; the manifest sits outside the bind-mounted
  `./.build/` tree so it stays in the image overlay
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

## Image Set

- `docker/linux-substrate.Dockerfile` is the shared Linux substrate image definition; it produces
  the control-plane and cluster-resident daemon images and bakes the demo bundle but carries no
  browser-runtime weight
- `RUNTIME_MODE=linux-cpu` with `BASE_IMAGE=ubuntu:24.04` produces `infernix-linux-cpu:local`
- `RUNTIME_MODE=linux-gpu` with
  `BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04` produces
  `infernix-linux-gpu:local`
- the substrate image installs Node.js 22+, the shared Poetry project, generated protobuf stubs,
  the built `web/dist/` bundle, and the `nvkind` binary during image build, and regenerates
  `web/package-lock.json` through `npm install` rather than tracking it under version control
- `docker/playwright.Dockerfile` is the dedicated Playwright image definition; it produces
  `infernix-playwright:local` from `mcr.microsoft.com/playwright:v1.57.0-noble` and owns the
  Playwright runtime, browsers, and browser-runtime libs
- Apple Silicon has no substrate Dockerfile; the host-native workflow builds and runs the
  `./.build/infernix` and `./.build/infernix-demo` binaries directly, and routed Playwright still
  comes from the shared `infernix-playwright:local` image through `docker compose run --rm playwright`

## Unsupported Usage

- `docker compose up`
- `docker compose exec`
- unqualified containerized `cabal` flows that write into the mounted repository tree

## Validation

- `infernix docs check` fails if this governed Docker-policy document loses its required structure
  or metadata contract.
- `docker compose build infernix` and `docker compose build playwright` succeed on supported hosts
  and produce both image families.
- `docker volume ls` lists no `infernix-build` or `infernix-cabal-home` named volumes after a
  supported `compose down -v` sequence; outer-container build state stays under `./.build/outer-container/`
  on the host instead.
- `infernix test integration` and `infernix test e2e` exercise the supported outer-container
  launchers, routed surfaces, and image-reuse behavior on the Linux lanes when those lanes are
  selected; routed E2E closes through `docker compose run --rm playwright` on every substrate.
- `infernix test all` reruns the full supported matrix entrypoints without reintroducing a live
  repo-mounted or helper-registry-based container workflow.

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../development/local_dev.md](../development/local_dev.md)
