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
  snapshot when the default CPU lane is not in play. Bootstrap scripts invoke that same shape and
  rely on Compose to build a missing launcher image instead of running a separate lifecycle
  builder path.
- Routed Playwright execution closes through the dedicated `infernix-playwright:local` image
  invoked via `docker compose run --rm playwright`; the substrate image carries no
  browser-runtime weight.
- Buildx support is part of the supported Docker toolchain. Host bootstraps install the Docker
  buildx plugin, and the Linux substrate image installs `docker-buildx` for nested Compose builds
  that happen during routed E2E.
- Outer-container build state lives under `./.build/outer-container/` on the host through a
  single `./.build:/workspace/.build` bind mount; no docker-managed named volumes back the
  outer-container build root or cabal package cache.
- The outer-container contract does not include `docker compose up`, `docker compose exec`, or a
  bootstrap helper-registry sidecar.
- Linux bootstrap scripts install Docker or the CUDA host stack only; they do not call Kind, Helm,
  Kubernetes manifest tooling, cluster workload image-pull orchestration, or image publication
  directly.

## Current Status

The current worktree follows the two-image-family policy directly: the substrate image family
(`infernix-linux-cpu:local` and `infernix-linux-gpu:local`) comes from
`docker/linux-substrate.Dockerfile` and owns the control plane plus the baked `web/dist/` bundle;
the dedicated `infernix-playwright:local` image comes from `docker/playwright.Dockerfile` and owns
routed E2E execution for every substrate. `compose.yaml` defines an `infernix` service for the
control plane and a `playwright` service for routed E2E, and bind-mounts `./.data/`, `./.build/`,
`./chart/charts/`, and the host `compose.yaml` into the `infernix` service together with the
Docker socket. The Harbor-first bootstrap path no longer depends on any retired helper-registry
container cleanup. Kind and `nvkind` cluster create or delete uses launcher-local scratch
kubeconfig state under the container temp directory, and the durable operator-facing kubeconfig is
published afterward to `./.data/runtime/infernix.kubeconfig`. The host Linux bootstrap installs
`docker-buildx-plugin`, and the Linux substrate image installs Ubuntu's `docker-buildx` package so
nested Playwright image builds have a buildx-capable Docker CLI when Compose selects Bake-backed
build behavior.

## Host Prerequisite Boundary

- on Apple Silicon, Colima is the only supported Docker environment
- on the Apple host-native control-plane path, `./.build/infernix` reconciles Homebrew-managed
  Colima and the Docker CLI before it attempts real cluster work
- on `linux-cpu`, host prerequisites stop at Docker Engine plus the Docker buildx and Compose
  plugins
- on `linux-gpu`, host prerequisites stop at the `linux-cpu` Docker baseline plus the supported
  NVIDIA driver and container-toolkit setup
- the supported Linux host Docker baseline includes the Docker buildx plugin because Compose may
  select Bake-backed build behavior on current Docker installations
- every remaining control-plane, web, Poetry, and Kubernetes toolchain dependency for Linux lives
  inside the shared substrate image; the Playwright runtime and browsers live inside the dedicated
  `infernix-playwright:local` image instead of the substrate image

## Supported Usage

- `docker compose build infernix` remains an optional manual refresh for the default Linux CPU
  outer-container image, but the supported bootstrap lifecycle enters through
  `docker compose run --rm infernix infernix <command>` and lets Compose build the image when it
  is absent
- `docker compose build playwright` remains an optional manual refresh for the dedicated
  Playwright image; lifecycle and validation ownership still belongs to the `infernix` command
  that needs routed E2E execution
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
  `./.build/`, `./chart/charts/`, and the host `./compose.yaml` (read-only) into `/workspace/`
- the `infernix` launcher container sets `/workspace/.build/outer-container/build` as the
  supported outer build root for the staged substrate file, while the source snapshot manifest
  lives separately at `/opt/infernix/source-snapshot-files.txt` in the image overlay and
  cabal-home plus the cabal builddir stay at the toolchain's natural in-image locations
  (`/root/.cabal/`, `dist-newstyle/`) rather than on any bind-mounted host path
- the supported Linux launcher also reuses `./chart/charts/` as the host-persisted cache for the
  top-level Harbor, PostgreSQL, Pulsar, MinIO, and Envoy Gateway chart archives so fresh
  `docker compose run --rm infernix ...` invocations do not reconstruct that dependency bundle
  from the network every time
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
  `infernix-linux-<mode>:local` snapshot selected by Compose and publishes that image into Harbor
  before final rollout instead of asking the shell bootstrap to build or push images directly
- cluster-backed outer-container commands keep host-published Kind API and routed ports on
  `127.0.0.1`
- cluster-backed outer-container commands join the private Docker `kind` network and use
  `kind get kubeconfig --internal` plus control-plane container DNS for Kubernetes access instead
  of `host.docker.internal`
- on the supported outer-container path, Kind and `nvkind` create or delete the cluster against a
  launcher-local scratch kubeconfig under the container temp directory; the lifecycle publishes
  the durable operator-facing kubeconfig afterward to `./.data/runtime/infernix.kubeconfig`,
  keeping transient lock files off the bind-mounted repo tree
- on the host-native Apple lane, the dedicated Playwright container also joins the private Docker
  `kind` network and targets the Kind control-plane DNS instead of `host.docker.internal`; only
  the host-side routed-surface readiness probe uses the published edge on `127.0.0.1`
- the Linux substrate images carry the runtime and validation dependencies needed to launch the
  control plane, build the web bundle, run `poetry install`, regenerate protobuf stubs, and execute
  `poetry run check-code`
- the Linux substrate images preinstall the project `ghc-9.14.1` toolchain together with the
  dedicated formatter-toolchain compiler `ghc-9.12.4` that the Haskell style gate uses through
  `ghcup run`
- the Linux substrate image leaves GHCup shell-profile adjustment disabled and owns the toolchain
  `PATH` through Docker `ENV`; `Couldn't figure out login shell!` is therefore a regression if it
  appears in a freshly built image
- the Linux substrate image disables npm's update notifier; npm version changes must come through
  explicit image toolchain updates rather than lifecycle log notices

## Image Set

- `docker/linux-substrate.Dockerfile` is the shared Linux substrate image definition; it produces
  the control-plane and cluster-resident daemon images and bakes the demo bundle but carries no
  browser-runtime weight
- `RUNTIME_MODE=linux-cpu` with `BASE_IMAGE=ubuntu:24.04` produces `infernix-linux-cpu:local`
- `RUNTIME_MODE=linux-gpu` with
  `BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04` produces
  `infernix-linux-gpu:local`
- the substrate image installs Node.js 22.5+, the shared Poetry project, generated protobuf stubs,
  the built `web/dist/` bundle, and the `nvkind` binary during image build, and regenerates
  `web/package-lock.json` through `npm install` rather than tracking it under version control
- `docker/playwright.Dockerfile` is the dedicated Playwright image definition; it produces
  `infernix-playwright:local` from `mcr.microsoft.com/playwright:v1.57.0-noble` and owns the
  Playwright runtime, browsers, and browser-runtime libs. It copies `web/scripts/` before running
  `npm install` so the PureScript `postinstall` compiler acquisition script is present in the
  image build.
- Apple Silicon has no substrate Dockerfile; the host-native workflow builds the
  `./.build/infernix` and `./.build/infernix-demo` binaries locally, uses `./.build/infernix` for
  ordinary operator commands and the host inference daemon, keeps the routed demo workload
  cluster-resident when `demo_ui` is enabled, and still gets routed Playwright from the shared
  `infernix-playwright:local` image through `docker compose run --rm playwright`

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
- `infernix test all` runs every supported validation layer for the selected Linux substrate
  without reintroducing a live repo-mounted or helper-registry-based container workflow.
- routed E2E should not emit a Docker Compose Bake/buildx warning; if the warning returns after a
  substrate image rebuild, treat it as a tooling regression rather than nonfatal background noise.
- routed E2E should not fail the Playwright image build with a missing
  `web/scripts/install-purescript.mjs`; if that error returns, the Playwright Dockerfile has drifted
  from the web toolchain contract and must copy the web scripts before npm `postinstall`.

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [k8s_native_dev_policy.md](k8s_native_dev_policy.md)
- [../development/local_dev.md](../development/local_dev.md)
