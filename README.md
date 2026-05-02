# Infernix

**Status**: Governed orientation document
**Supersedes**: older root-level workflow duplication; canonical contracts live under `documents/` and `DEVELOPMENT_PLAN/`
**Canonical homes**: [documents/README.md](documents/README.md), [documents/reference/cli_reference.md](documents/reference/cli_reference.md), [documents/development/local_dev.md](documents/development/local_dev.md), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md)

> **Purpose**: Orient operators and contributors to the supported product shape, quick-start flows,
> and canonical repository guidance.

Infernix is a Haskell inference control plane for running heterogeneous model runtimes behind one
typed operator surface.

It handles orchestration, model resolution, artifact delivery, request routing, runtime
supervision, and browser-facing manual inference while leaving execution kernels to the best
runtime for each model family.

This README is the operator-oriented orientation and quick-start layer, while
[DEVELOPMENT_PLAN/](DEVELOPMENT_PLAN/README.md) is the authoritative source for implementation
status, validation history, and phase-closure evidence.

This repository serves two aligned purposes:

- provide consistent binary or container build outputs for three supported runtime modes: Apple
  Silicon or Metal, Ubuntu 24.04 CPU, and Ubuntu 24.04 NVIDIA CUDA containers
- provide a local Kind cluster, running the mandatory HA service topology, as the testing and demo
  ground for the control plane; the demo UI (served by the `infernix-demo` binary) is a demo
  surface on that substrate, gated by the active `.dhall` config

## Highlights

- two Haskell executables sharing one Cabal library `infernix-lib`: `infernix` (production
  daemon, cluster lifecycle, Pulsar inference dispatcher, static-quality gate, internal helpers)
  and `infernix-demo` (demo UI HTTP host). Routing is owned by the Helm-installed Envoy Gateway
  controller plus repo-owned HTTPRoute manifests; `infernix` itself is no longer a routing
  process
- production deployments accept inference work by Pulsar subscription only; the production
  `infernix service` binds no HTTP listener and the cluster has no `infernix-demo` workload when
  the demo UI is off
- Python is restricted to the shared Poetry project at `python/pyproject.toml` and the shared
  adapter tree under `python/adapters/`; the canonical quality entrypoint is
  `poetry run check-code`, which runs mypy strict, black check, and ruff strict in sequence
- one Kind and Helm workflow for the HA testing and demo ground
- one mandatory local HA topology: Harbor, MinIO, Pulsar, and operator-managed PostgreSQL on Kind
- one local Harbor registry as the image source for every non-Harbor pod
- one manual persistent-storage doctrine rooted at `./.data/`
- one PureScript demo UI built with spago, tested with `purescript-spec`, with frontend contracts
  emitted by `infernix internal generate-purs-contracts` through `purescript-bridge` from
  dedicated Haskell browser-contract ADTs plus active-mode catalog metadata
- one browser-based manual inference demo workbench for any registered model, served by
  `infernix-demo`
- three runtime targets: Apple Silicon or Metal, Ubuntu 24.04 CPU, and Ubuntu 24.04 NVIDIA CUDA
  containers
- one validation surface spanning repo-owned Haskell `ormolu`/`cabal format`/`hlint`,
  `poetry run check-code` against `python/adapters/`, unit tests, integration tests,
  `purescript-spec` view and contract tests, and Playwright launched from the shared Linux
  substrate image or the host (Apple Silicon)
- one shared Linux substrate build definition (`docker/linux-substrate.Dockerfile`) emits
  `infernix-linux-cpu` and `infernix-linux-gpu`, each with ghcup-pinned GHC 9.14.1 + Cabal
  3.16.1.0, Python 3 + Poetry, node, Playwright, `nvkind`, and the Kind/kubectl/Helm/Docker
  toolbelt baked in. Apple Silicon has no Dockerfile; the operator pre-installs ghcup and the
  daemon installs engine deps via system `clang` and `brew`
- no `.sh` files anywhere in the repo; no committed built artifacts (`poetry.lock`, generated
  proto, `.mypy_cache`, `.ruff_cache`, `*.pyc`, `web/dist/`, `web/spago.lock`,
  `web/src/Generated/`)

## What Infernix Does

Infernix does not reimplement model kernels. It coordinates them.

- consumes inference requests from Pulsar request topics named in the active `.dhall` and publishes
  results to the configured result topics; this is the production inference surface
- optionally exposes a manual browser submission surface via the `infernix-demo` binary, gated by
  the active `.dhall` `demo_ui` flag, sharing the same typed service domain as the production path
- resolves logical models against durable manifest and artifact metadata
- acquires missing artifacts into MinIO idempotently when upstream acquisition policy allows it
- materializes runtime-local cache state from durable sources
- launches and supervises engine workers in Haskell; for Python-native engines (PyTorch, JAX,
  vLLM, transformers, etc.), the worker forks a Python adapter from `python/adapters/*.py`
  through `poetry run <adapter-entrypoint>` and speaks protobuf-over-stdio to it
- routes requests into per-engine, per-model, per-device lanes while leaving batching and runtime
  memory policy to the child engine
- stores large outputs in MinIO and returns references when appropriate
- exposes a demo web UI (PureScript, served by `infernix-demo`) for manually running inference
  against any registered model when the demo flag is on

## Supported Modes

The repository supports three first-class runtime modes. The local Kind cluster described later is
the HA testing and demo ground used to validate and demonstrate them.

| Mode | Build or deployment shape | Role in the repository | Intended engines |
|------|---------------------------|------------------------|------------------|
| Apple Silicon / Metal | host-native Apple binary path | direct host execution, local development, and Apple runtime parity behind the shared control-plane contract | `llama.cpp`, `MLX` or `MLX-LM`, `vllm-metal`, `PyTorch` on MPS, `Core ML`, `jax-metal` |
| Ubuntu 24.04 / CPU | containerized Linux CPU path | CPU-only validation, fallback, and non-GPU workloads under the same manifests, messaging, and runtime contract | `llama.cpp`, `whisper.cpp`, `PyTorch` CPU, `ONNX Runtime` CPU, JVM-hosted tools |
| Ubuntu 24.04 / NVIDIA CUDA Container | pinned CUDA container lane with NVIDIA runtime | high-throughput GPU execution under the same manifests, messaging, and runtime contract | `vLLM`, `PyTorch` CUDA, `Diffusers` or `ComfyUI`, `CTranslate2`, `TensorFlow` CUDA, `JAX/XLA`, `llama.cpp` when GGUF is the right artifact |

On Apple Silicon, the operator workflow has no Python prerequisite. Poetry and a repo-local
adapter virtual environment materialize only when the Python adapter validation surface is
exercised explicitly (for example `infernix test unit` or `infernix test all`).

Infernix uses one operator, artifact, and browser-demo contract across Apple, CPU, and CUDA runtime
classes.

## Local Architecture

The supported local platform is built around:

- one Kind cluster used as the HA testing and demo ground for Harbor, MinIO, Pulsar, the Envoy
  Gateway controller, operator-managed PostgreSQL, the production `infernix-service` workload,
  and the optional `infernix-demo` workload
- one Envoy-Gateway-API-owned localhost listener (`Gateway/infernix-edge`, port chosen by
  `cluster up` starting at `9090`) backed by the repo-owned `EnvoyProxy/infernix-edge` service
  shape; the route inventory stays registry-driven, the demo routes are absent when the demo
  surface is disabled, and the demo cluster runs locally without auth filters
- one manual storage class backed by repo-owned PVs under `./.data/`
- one Patroni PostgreSQL model managed by the Percona Kubernetes operator for every in-cluster
  PostgreSQL dependency
- one local Harbor registry used by every non-Harbor cluster pod after Harbor bootstrap completes
- one OCI image per Linux substrate carrying both `infernix` and `infernix-demo` plus the engine
  toolchain and Playwright; the chart workload entrypoint selects which exe runs
  (`infernix service` or `infernix-demo serve`). Apple Silicon has no Dockerfile — the daemon
  builds engines on the host via system `clang` and `brew`
- one direct host Cabal install path on Apple Silicon (operator-installed ghcup pinned to GHC
  9.14.1 + Cabal 3.16.1.0) that keeps host-native artifacts under `./.build/` without
  repo-owned scripts
- one repo-local kubeconfig managed under the active build-output location rather than the user's
  global kubeconfig

<!-- infernix:route-registry:readme:start -->
- always-published routed prefixes: `/harbor/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, `/pulsar/ws`
- demo-only routed prefixes (present when `.dhall` `demo_ui = True`): `/`, `/api`, `/objects`
- registry-owned rewrites: `/harbor/api` -> `/api`; `/harbor` -> `/`; `/minio/console` -> `/`; `/minio/s3` -> `/`; `/pulsar/admin` -> `/`; `/pulsar/ws` -> `/ws`
<!-- infernix:route-registry:readme:end -->

The optional demo UI runs in the cluster as the `infernix-demo` workload when the active `.dhall`
`demo_ui` flag is on, even when the production `infernix service` daemon runs host-native on Apple
Silicon. Production deployments leave the demo flag off and accept inference work via Pulsar
subscription only. The local Kind and HA substrate is the validation and operator baseline for
Apple, CPU, and CUDA runtime targets.

## System Prerequisites

Use the host package manager or installer that matches the supported execution context:

- on Apple Silicon, the intended pre-existing host prerequisites are only Homebrew plus `ghcup`
- on Linux CPU, the intended host prerequisites stop at Docker Engine plus the Docker Compose plugin
- on Linux CUDA, the intended host prerequisites stop at Docker Engine plus the supported NVIDIA
  driver and container-toolkit setup

Current status:

- after `./.build/infernix` exists on Apple Silicon, supported host-native commands reconcile
  Colima, Docker CLI, `kind`, `kubectl`, `helm`, and Node.js through Homebrew when the active path
  needs them
- Apple host-native adapter setup and validation paths bootstrap a user-local `poetry` executable
  through the host's built-in Python when it is absent and then materialize `python/.venv/` on
  demand
- `linux-cpu` keeps its host prerequisites at Docker Engine plus the Docker Compose plugin, and
  `linux-gpu` adds the documented NVIDIA driver and container-toolkit requirements on top of that

The Linux install examples below assume an Ubuntu 24.04 host.

### Apple Silicon host prerequisites

Required before building `./.build/infernix` on the host:

- Homebrew
- `ghcup` with `ghc 9.14.1` and `cabal 3.16.1.0` active

Supported install path:

```bash
# Homebrew (official installer).
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Userland tools managed by Homebrew.

# Haskell toolchain managed by ghcup rather than Homebrew.
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
ghcup install ghc 9.14.1
ghcup set ghc 9.14.1
ghcup install cabal 3.16.1.0
ghcup set cabal 3.16.1.0
```

Notes:

- `ghcup` is the supported manual install because the Apple host-native workflow depends on an
  explicitly selected GHC and Cabal pair
- Colima is the only supported Docker environment on Apple Silicon; once `./.build/infernix`
  exists, supported commands install it from Homebrew together with the Docker CLI, `kind`,
  `kubectl`, `helm`, Node.js, and any other operator-facing tools needed by the active path
- Apple adapter setup and validation commands bootstrap Poetry through the host's built-in Python
  when `poetry` is absent, after which all host-side Python configuration continues through Poetry

### Linux CPU host prerequisites

Required on the host:

- Docker Engine
- Docker Compose plugin
- permission to access `/var/run/docker.sock`

Not required on the host for the supported outer-container path:

- `kind`
- `kubectl`
- `helm`
- Node.js
- GHC or Cabal

Supported install path:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
newgrp docker
docker version
docker compose version
```

Notes:

- prefer Docker's official apt repository over Ubuntu's older `docker.io` package so the supported
  Compose plugin and current engine features stay aligned with the Linux substrate images
- the Linux CPU workflow does not need host-installed Kubernetes or Haskell tooling because the
  baked `infernix-linux-cpu:local` image carries the repo-supported toolchain
- everything beyond Docker happens inside the shared Linux substrate image build or runtime path

### Linux CUDA host prerequisites

Required on the host:

- everything from the Linux CPU host prerequisites
- an NVIDIA GPU visible to the host OS
- a working NVIDIA driver on the host
- the NVIDIA Container Toolkit configured for Docker

Supported install path:

```bash
# First complete the Linux CPU host setup above.

# Manual host-driver step: use Ubuntu Additional Drivers, your fleet's GPU-driver automation,
# or NVIDIA's distro guidance so nvidia-smi works on the host before continuing.
nvidia-smi -L

# NVIDIA Container Toolkit from NVIDIA's apt repository.
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify both the host GPU and Docker GPU handoff.
nvidia-smi -L
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L
```

Notes:

- the NVIDIA driver is the main manual step because the right installation path depends on the
  host kernel, Secure Boot posture, and fleet policy; the repo assumes that driver is already
  working before `linux-gpu` validation starts
- the supported `linux-gpu` lane does not need host-installed `kind`, `kubectl`, `helm`, Node.js,
  or GHC because the baked `infernix-linux-gpu:local` image carries them
- plan for substantial free disk space before `cluster up` or `test all`; the Kind preload plus
  Harbor-backed rollout is materially heavier than the CPU lane
- everything beyond Docker plus the NVIDIA host prerequisites happens inside the shared Linux
  substrate image build or runtime path

## Demo and Validation Quick Start

The local HA Kind cluster is the supported demo ground and full-suite validation ground for all
three runtime modes. `cluster up` owns the bring-up path, `cluster status` prints the chosen
edge port plus the published route inventory, and the demo UI is available at
`http://127.0.0.1:<edge-port>/` whenever the active generated `.dhall` enables `demo_ui`.

`infernix test all` is the canonical aggregate suite on every substrate:

- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`

### Apple Silicon (host-native)

Apple Silicon has no Dockerfile. The operator pre-installs `ghcup` with GHC 9.14.1 + Cabal
3.16.1.0 active, and the host toolchain owns the `apple-silicon` runtime lane directly.

**Prerequisites**: complete the Apple Silicon host setup in [System Prerequisites](#system-prerequisites).

```bash
# Build both Haskell binaries directly into ./.build/.
cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo

# Bring up the Kind HA demo ground.
./.build/infernix cluster up

# Print the edge port, route inventory, and publication details, then open
# http://127.0.0.1:<edge-port>/ in a browser.
./.build/infernix cluster status

# Run the full suite.
./.build/infernix test all

# Or run each suite directly.
./.build/infernix test lint
./.build/infernix test unit
./.build/infernix test integration
./.build/infernix test e2e

# Tear down while preserving authoritative data under ./.data.
./.build/infernix cluster down
```

`cluster up` writes `./.build/infernix.kubeconfig` and never touches `$HOME/.kube/config`. On
the supported minimal-prerequisites path, the binary reconciles Colima plus the remaining
Homebrew-managed operator tools and bootstraps Poetry through the host's built-in Python before an
adapter setup or validation path first needs the shared `python/.venv/`.

### Linux CPU (outer container)

The `linux-cpu` substrate ships one baked image snapshot, `infernix-linux-cpu:local`, built from
`docker/linux-substrate.Dockerfile` with `BASE_IMAGE=ubuntu:24.04`. The same image acts as the
launcher, the in-cluster workload image source, and the routed Playwright executor.

**Prerequisites**: complete the Linux CPU host setup in [System Prerequisites](#system-prerequisites).

```bash
# Build the shared Linux substrate image snapshot.
docker compose build infernix

# Bring up the Kind HA demo ground.
docker compose run --rm infernix infernix cluster up

# Print the edge port, route inventory, and publication details, then open
# http://127.0.0.1:<edge-port>/ in a browser.
docker compose run --rm infernix infernix cluster status

# Run the full suite.
docker compose run --rm infernix infernix test all

# Or run each suite directly.
docker compose run --rm infernix infernix test lint
docker compose run --rm infernix infernix test unit
docker compose run --rm infernix infernix test integration
docker compose run --rm infernix infernix test e2e

# Tear down.
docker compose run --rm infernix infernix cluster down
```

The Linux launcher bind-mounts only `./.data/`, the Docker socket, and named build caches. The
baked image owns the full toolchain, so the supported runtime path does not install anything via
`apt`, `pip`, or ad hoc host-side `cabal build`.

### Linux CUDA (substrate container)

The `linux-gpu` substrate ships one baked image snapshot, `infernix-linux-gpu:local`, built
from `docker/linux-substrate.Dockerfile` with a CUDA base image. The image includes `nvkind` and
the GPU validation toolchain needed by the supported `linux-gpu` cluster lifecycle.

**Prerequisites**: complete the Linux CUDA host setup in [System Prerequisites](#system-prerequisites).

```bash
# Build the linux-gpu substrate image.
docker build -f docker/linux-substrate.Dockerfile \
  --build-arg RUNTIME_MODE=linux-gpu \
  --build-arg BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04 \
  -t infernix-linux-gpu:local .

# Bring up the GPU-enabled Kind HA demo ground.
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix cluster up

# Print the edge port, route inventory, and publication details, then open
# http://127.0.0.1:<edge-port>/ in a browser.
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix cluster status

# Confirm GPU visibility from the cluster service deployment.
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix kubectl -n platform exec deployment/infernix-service -- nvidia-smi -L

# Run the full suite.
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix test all

# Or run each suite directly.
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix test lint
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix test unit
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix test integration
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix test e2e

# Tear down.
docker run --rm --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.data:/workspace/.data" \
  infernix-linux-gpu:local infernix cluster down
```

The CUDA substrate image bundles CUDA-aware engine builds such as `llama.cpp` CUDA and `vLLM` at
image build time. `cluster up` installs the Envoy Gateway controller, the NVIDIA device plugin,
and `RuntimeClass/nvidia` before scheduling the GPU-requesting service workload.

## CLI Surface

The canonical supported CLI surfaces are split between the two binaries.

`infernix` (production daemon and operator workflow):

- `infernix service` — production Pulsar consumer; binds no HTTP listener. Routing is owned
  by the Helm-installed Envoy Gateway controller plus repo-owned HTTPRoute manifests
- `infernix cluster up`
- `infernix cluster down`
- `infernix cluster status`
- `infernix cache status`
- `infernix cache evict`
- `infernix cache rebuild`
- `infernix kubectl ...`
- `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`
- `infernix docs check`
- `infernix internal generate-purs-contracts`
- `infernix internal discover {images,claims,harbor-overlay}`
- `infernix internal publish-chart-images`
- `infernix internal demo-config {load,validate}`

`infernix-demo` (demo UI HTTP host, gated by `.dhall` `demo_ui` flag):

- `infernix-demo serve --dhall PATH --port N`

Every repo-owned lifecycle, cache, validation, and docs command other than `infernix service` and
`infernix-demo serve` is declarative and idempotent. `infernix kubectl ...` is a scoped wrapper
around upstream `kubectl`, not a parallel lifecycle surface.

## Runtime and Image Flow

- `cluster up` is the supported HA testing and demo-ground bring-up command
- `cluster up` declaratively reconciles Kind, manual storage, Harbor-backed images, Helm workloads,
  repo-local kubeconfig, and generated mode-specific demo configuration
- `cluster up` generates the mode-specific demo `.dhall` file that defines the demo catalog and the
  engine binding for each demo-visible model on the active mode
- `cluster up` bootstraps Harbor first through Helm and allows Harbor plus only the storage or
  support services Harbor needs during bootstrap, including MinIO and PostgreSQL, to pull from
  public container repositories
- `cluster up` mirrors required third-party images into Harbor before deploying the remaining
  non-Harbor workloads
- `cluster up` publishes the active Linux runtime image to Harbor before the final Helm rollout.
  On the supported Linux outer-container path it reuses the already-built baked
  `infernix-linux-<mode>:local` snapshot rather than rebuilding it again inside the launcher. On
  Apple Silicon no image build occurs
- every non-Harbor pod pulls from local Harbor
- Harbor and only the storage or support services Harbor needs are the allowed direct-upstream
  bootstrap exception before the Harbor-backed pull contract takes over
- `cluster up` always deploys the mandatory local HA topology: 3x Harbor application-plane services
  where the selected chart supports them, 4x MinIO, 3x Pulsar HA surfaces where the selected
  chart supports them, and operator-managed Patroni PostgreSQL for every in-cluster PostgreSQL need
- services that can self-deploy PostgreSQL still disable that embedded database path and target a
  dedicated operator-managed cluster instead
- repo-owned Helm values suppress hard pod anti-affinity and equivalent hard scheduling constraints
  as needed for local Kind scheduling
- `cluster down` removes cluster state without deleting authoritative data under `./.data/`
- MinIO is the durable source of truth for manifests, durable model artifacts, and large outputs
- Pulsar is the durable transport for inference requests, status, cancellation, and result
  publication
- artifact flow uses two stages: upstream acquisition into MinIO, then local materialization from
  MinIO into runtime cache
- engine workers remain process-isolated and own their own batching, execution scheduling, and
  backpressure behavior
- the HA demo ground exercises and demonstrates the control plane contract across the three
  supported runtime modes

## Storage Model

Local durability is explicit.

- default storage classes are deleted during cluster bootstrap
- the only supported persistent storage class is the repo-owned `kubernetes.io/no-provisioner`
  class, tentatively named `infernix-manual`
- PVCs are created only by Helm-owned durable workloads, including operator-managed claims
  reconciled from repo-owned Helm releases
- PVs are created only by `infernix` lifecycle logic and bind explicitly to their intended claims
- PVs bind deterministically into `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- explicit PV-to-PVC binding guarantees clean `cluster down` and `cluster up` rebinding behavior
- storage reconciliation is part of `cluster up`; there is no separate storage reconcile command
- every in-cluster PostgreSQL deployment uses a Patroni cluster managed by the Percona Kubernetes operator

MinIO is authoritative for durable artifacts and large outputs. Local cache state is derived and
rebuildable.

## Configuration and Runtime Contract

- a `.dhall` configuration defines the runtime contract for supported service flows; the active
  `.dhall` names `request_topics : List Text`, `result_topic : Text`, `engines : List EngineBinding`,
  and the optional `demo_ui : Bool` flag that gates the `infernix-demo` workload
- `cluster up` produces a mode-specific demo `.dhall` file as a build artifact for the active mode
- the generated demo `.dhall` file enumerates the demo-visible models and workloads for that mode
  and binds each one to its engine or runtime lane
- the generated demo `.dhall` file is the exact source of truth for which models and engine bindings
  appear in the demo UI for that mode (when the demo UI is enabled)
- the set of generated mode-specific demo `.dhall` files must cover every model or workload row in
  the comprehensive model, format, and engine matrix
- the service contract includes hot-reloadable configuration with safe worker drain, cache
  eviction, and route or device remapping semantics
- the production inference surface is Pulsar subscription only: `infernix service` consumes
  protobuf requests from configured request topics, dispatches them through the Haskell worker, and
  publishes results to the configured result topic; no HTTP listener is bound
- local cache state is never authoritative; it is reconstructed from durable metadata and durable
  artifacts

## Messaging and Lane Model

- Pulsar topic families remain in scope: `inference.request.*`, `inference.cancel.*`,
  `inference.result.*`, `inference.status.*`, `inference.failure.*`, and
  `inference.control.*`
- request routing is lane-oriented: one engine, one model, one device class or allocation, one
  runtime-owned execution stream
- engine-specific workers remain responsible for batching and execution internals after Infernix
  selects the target lane
- browser-driven manual inference and transport-driven automated inference are expected to converge
  on the same typed request, result, and object-reference semantics

## Web UI and Testing

The browser surface is a repo-owned PureScript demo application with Haskell-generated shared
contracts.

- Haskell-owned DTO and catalog records remain the source of truth for the frontend contract;
  PureScript modules in `web/src/Generated/` are emitted by
  `infernix internal generate-purs-contracts` through `purescript-bridge`
- the demo UI host is the `infernix-demo` Haskell binary (separate executable from `infernix`,
  shares `infernix-lib`, ships in the same per-substrate OCI image on Linux); it serves
  `web/dist/` produced by `spago bundle`
- on Linux substrates, the substrate container also carries the spago plus purs toolchain
  (used at image build time to bundle the demo UI) plus Playwright browser dependencies
  (Chromium, Firefox, WebKit) for routed E2E execution. There is no separate web-only image
- on Apple Silicon, `infernix test e2e` runs Playwright from the operator's host node install
  (`npm --prefix web exec -- playwright install --with-deps chromium firefox webkit` is the
  one-time setup step)
- the `infernix-demo` workload is deployed through repo-owned Helm chart templates and values, and
  is gated by the `.dhall` `demo_ui` flag; production deployments leave it off
- the demo UI catalog is derived from the generated mode-specific demo `.dhall` file for the active
  mode
- repo-owned `purescript-spec` suites under `web/test/` cover generated contracts, publication
  rendering, and view behavior; `infernix test unit` runs `spago test` alongside the Haskell unit
  suites
- Playwright runs from the per-substrate container on Linux substrates and from the host node
  install on Apple Silicon; the test orchestration lives in the Haskell integration test suite
- the demo UI can submit manual inference requests against any registered model in the active demo
  catalog; the production inference surface remains Pulsar topics named in the active `.dhall`
- the demo UI, demo API surface, generated PureScript contracts, and validation suites must expand
  until every supported model, format, and engine combination has a browser-visible and testable
  path under the demo surface

## Comprehensive Model / Format / Engine Matrix

The platform targets the following model, format, and engine coverage envelope. The Kind HA demo
ground and demo webapp provide the shared operator and demo substrate for this matrix.

| Model / workload type | Artifact / format type | Reference model | Download URL | Best Linux CPU engine | Best Linux CUDA engine | Best Apple Silicon engine | Notes |
|---|---|---|---|---|---|---|---|
| LLM (general text) | HF safetensors | Qwen2.5-1.5B-Instruct | https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct | Transformers + PyTorch CPU | vLLM | Transformers + PyTorch MPS | Canonical source format for many open-weight LLMs |
| LLM (quantized, CUDA-focused) | AWQ | Qwen2.5-1.5B-Instruct-AWQ | https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-AWQ | Not recommended | vLLM | Not recommended | GPU-oriented quantized checkpoint |
| LLM (quantized, CUDA-focused) | GPTQ | TinyLlama-1.1B-Chat-v1.0-GPTQ | https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GPTQ | Not recommended | vLLM | Not recommended | Older but useful quantized checkpoint family |
| LLM (local / edge) | GGUF | TinyLlama-1.1B-Chat-v1.0-GGUF | https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF | llama.cpp | llama.cpp | llama.cpp (Metal) | Best cross-platform local runtime path |
| LLM (Apple-native) | MLX | Qwen1.5-1.8B-Chat-4bit (MLX) | https://huggingface.co/mlx-community/Qwen1.5-1.8B-Chat-4bit | Not recommended | Not recommended | MLX / MLX-LM | Apple-native converted artifact family |
| Speech transcription | whisper.cpp model set / GGML-style | whisper-small | https://github.com/ggml-org/whisper.cpp/tree/master/models | whisper.cpp | whisper.cpp | whisper.cpp (Metal) | Best compact or native path |
| Speech transcription | CTranslate2 | faster-whisper-small | https://huggingface.co/Systran/faster-whisper-small | CTranslate2 | CTranslate2 | Not recommended | Best throughput-oriented Whisper path on CUDA |
| Source separation | PyTorch checkpoint | htdemucs | https://github.com/facebookresearch/demucs | PyTorch CPU | PyTorch CUDA | PyTorch MPS | Canonical Demucs execution path |
| Source separation | PyTorch checkpoint | Open-Unmix | https://github.com/sigsep/open-unmix-pytorch | PyTorch CPU | PyTorch CUDA | PyTorch MPS | Alternate separation path |
| Audio-to-MIDI / pitch transcription | TensorFlow model family | basic-pitch | https://github.com/spotify/basic-pitch | TensorFlow CPU or default package runtime | TensorFlow CUDA | Not recommended | TensorFlow is the preferred production lane when used on CUDA |
| Audio-to-MIDI / pitch transcription | Core ML | basic-pitch | https://github.com/spotify/basic-pitch | Not recommended | Not recommended | Core ML | Preferred Apple production lane for Basic Pitch |
| Audio-to-MIDI / pitch transcription | ONNX | basic-pitch release artifacts | https://github.com/spotify/basic-pitch/releases | ONNX Runtime CPU | ONNX Runtime CUDA | ONNX Runtime | Useful portable fallback artifact |
| Multi-instrument music transcription | JAX checkpoint / codebase | MT3 | https://github.com/magenta/mt3 | JAX CPU | JAX/XLA on NVIDIA | jax-metal | JAX is the canonical execution model |
| Music transcription / MIR family | TensorFlow model family | Omnizart | https://github.com/Music-and-Culture-Technology-Lab/omnizart | TensorFlow CPU | TensorFlow CUDA | Core ML (exported path owned by deployment) | Apple support likely requires an owned export path |
| Image generation | Diffusers / safetensors pipeline | SDXL Turbo | https://huggingface.co/stabilityai/sdxl-turbo | Not recommended | Diffusers or ComfyUI | Diffusers on MPS | Standard open image-generation stack |
| Image generation | Core ML | Apple Stable Diffusion conversion toolchain | https://github.com/apple/ml-stable-diffusion | Not recommended | Not recommended | Core ML | Best Apple-native exported path when available |
| Video generation | Diffusers / safetensors pipeline | Wan2.1-T2V-1.3B | https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B | Not recommended | Diffusers or ComfyUI | Diffusers on MPS (if viable) | Small reference text-to-video model |
| Audio generation / TTS-style | PyTorch / HF | bark-small | https://huggingface.co/suno/bark-small | PyTorch CPU | PyTorch CUDA | PyTorch MPS | Representative audio-generation family |
| OMR / notation extraction tool | JVM application | Audiveris | https://github.com/Audiveris/audiveris | JVM | JVM | JVM | Treat as tool runtime, not a separately managed ANN kernel family |

## Coverage Closure Rules

- each supported mode must generate a mode-specific demo `.dhall` file whose entries define the
  demo-visible models and engine bindings for that mode
- across Apple, CPU, and CUDA demo `.dhall` generation, every row in the comprehensive matrix must
  be represented by an explicit model or workload entry
- the model catalog, manifests, and runtime registration surface must grow until every matrix row is
  representable by a registered model and a typed request contract
- the manual inference workbench must present a usable browser path for every supported matrix row,
  including request forms, progress states, result rendering, and object-reference handling where
  needed
- the validation surface must cover every supported matrix row through the appropriate mix of unit,
  integration, and Playwright or browser-driven checks
- Apple, CPU, and CUDA runtime lanes must be validated as first-class targets rather than narrowing
  the matrix to only the local Kind demo-ground launcher paths

## Documentation

- `documents/` is the canonical home for governed architecture, development, engineering,
  operations, reference, tools, and research documentation
- `DEVELOPMENT_PLAN/` contains the execution-ordered buildout plan and phase closure criteria
- start with [documents/README.md](documents/README.md) for the suite index
- use [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md) for phase order and closure rules

## Contributing

Contributions should keep implementation, tests, and docs aligned in the same change.

- use `documents/` for architecture, operator, and development guidance
- use `DEVELOPMENT_PLAN/` for phase ordering, scope, and closure criteria
- run `infernix lint docs`,
  `infernix test lint`, and the relevant `infernix test ...` targets before opening changes

## License

[MIT](LICENSE)
