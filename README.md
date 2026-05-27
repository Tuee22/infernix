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
  ground for the control plane, including Harbor, MinIO, Pulsar, Prometheus, Grafana, and
  per-service Patroni PostgreSQL clusters where durable PostgreSQL state is required; the demo UI
  (served by the `infernix-demo` binary) is a demo surface on that substrate, gated by the active
  `.dhall` config

## Highlights

- two Haskell executables sharing the default Cabal library exposed by the `infernix` package:
  `infernix` (production daemon, cluster lifecycle, Pulsar inference dispatcher, static-quality
  gate, internal helpers) and `infernix-demo` (demo UI HTTP host). Routing is owned by the
  Helm-installed Envoy Gateway controller plus repo-owned HTTPRoute manifests; `infernix` itself
  is no longer a routing process
- production deployments accept inference work by Pulsar subscription only; the production
  `infernix service` binds no HTTP listener and the cluster has no `infernix-demo` workload when
  the demo UI is off
- Python is restricted to the shared Poetry project at `python/pyproject.toml` and the shared
  adapter tree under `python/adapters/`; the canonical quality entrypoint is
  `poetry run check-code`, which runs mypy strict, black check, and ruff strict in sequence
- one Kind and Helm workflow for the HA testing and demo ground
- one mandatory local HA topology: Harbor, MinIO, Pulsar, Prometheus, Grafana, and per-service
  operator-managed PostgreSQL on Kind
- one Prometheus metrics plane that every other platform, control-plane, and inference service
  syncs with, plus one Grafana visualization surface that can use its own PostgreSQL backend under
  the same PostgreSQL rules
- one local Harbor registry as the image source for every non-Harbor pod
- one manual persistent-storage doctrine rooted at `./.data/`
- one PureScript demo UI built with spago, tested with `purescript-spec`, with frontend contracts
  emitted by `infernix internal generate-purs-contracts` through `purescript-bridge` from
  dedicated Haskell browser-contract ADTs plus active-mode catalog metadata
- one browser-based PureScript demo SPA covering manual inference for any registered model,
  served by `infernix-demo`
- three runtime targets: Apple Silicon or Metal, Ubuntu 24.04 CPU, and Ubuntu 24.04 NVIDIA CUDA
  containers
- one validation surface spanning repo-owned Haskell `ormolu`/`cabal format`/`hlint`,
  `poetry run check-code` against `python/adapters/`, unit tests, integration tests,
  `purescript-spec` view and contract tests, and Linux Playwright launched from inside the
  substrate image
- one shared Linux substrate build definition (`docker/linux-substrate.Dockerfile`) emits
  `infernix-linux-cpu` and `infernix-linux-gpu`, each with ghcup-pinned GHC 9.14.1 + Cabal
  3.16.1.0, Python 3 + Poetry, node, the demo UI build toolchain, `nvkind`, and the
  Kind/kubectl/Helm/Docker toolbelt baked in. Apple Silicon has no Dockerfile; the operator
  pre-installs ghcup and the host binary reconciles adapter setup through the shared Poetry project
- repo-owned shell is limited to the `bootstrap/*.sh` stage-0 host bootstrap entrypoints: those
  scripts build or enter the substrate-specific `infernix` launcher and then hand lifecycle work
  to the binary instead of managing Kind, Kubernetes manifests, or cluster workload image pulls
  directly; no committed built artifacts (`poetry.lock`, generated proto, `.mypy_cache`,
  `.ruff_cache`, `*.pyc`, `web/dist/`, `web/spago.lock`, `web/src/Generated/`)

## What Infernix Does

Infernix does not reimplement model kernels. It coordinates them.

The active substrate configuration lives in `infernix-substrate.dhall`, a typed Dhall record decoded
in-process by the `dhall` Haskell library; the schema is defined at `dhall/InfernixSubstrate.dhall`.

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

On Apple Silicon, the operator workflow has no generic Python prerequisite before the host build.
When Apple adapter setup or validation paths are exercised, `infernix` reconciles the
Homebrew-managed `python@3.12` formula and `python3.12` command when needed, bootstraps a
user-local `poetry` executable if needed, and materializes the repo-local `python/.venv/` on
demand. The Poetry bootstrap may reuse an already available compatible Python 3.12+ executable
when one passes the implemented version check; the supported path does not depend on an
unversioned `python` executable.

Infernix uses one operator, artifact, and browser-demo contract across Apple, CPU, and CUDA runtime
classes.

## Local Architecture

The supported local platform is built around:

- one Kind cluster used as the HA testing and demo ground for Harbor, MinIO, Pulsar, the Envoy
  Gateway controller, Prometheus, Grafana, per-service operator-managed PostgreSQL clusters, the
  production `infernix-engine` workload (stateful, one-per-node), and (when the demo UI is
  enabled) the stateless `infernix-coordinator` Deployment plus the optional `infernix-demo`
  workload per the supported three-role daemon model in
  [documents/architecture/daemon_topology.md](documents/architecture/daemon_topology.md)
- one Envoy-Gateway-API-owned localhost listener (`Gateway/infernix-edge`, port chosen by
  `cluster up` starting at `9090`) backed by the repo-owned `EnvoyProxy/infernix-edge` service
  shape; the route inventory stays registry-driven, the demo routes are absent when the demo
  surface is disabled, and the demo cluster runs locally without auth filters
- one manual storage class backed by repo-owned PVs under `./.data/`
- each service that requires durable PostgreSQL storage deploys its own Patroni PostgreSQL cluster
  managed by the Percona Kubernetes operator; chart-embedded PostgreSQL paths stay disabled
- one first-class Prometheus deployment receives metrics from the other platform, control-plane,
  and inference services, and one first-class Grafana deployment reads from Prometheus for
  dashboards and operational visibility
- Grafana may use its own durable PostgreSQL backend, but that backend follows the same
  per-service Patroni and Percona-operator rules as every other PostgreSQL dependency
- one local Harbor registry used by every non-Harbor cluster pod after Harbor bootstrap completes
- one OCI image per Linux substrate carrying both `infernix` and `infernix-demo` plus the engine
  toolchain and the demo UI build toolchain; the chart workload entrypoint selects which exe runs
  (`infernix service` or `infernix-demo serve`). Apple Silicon has no Dockerfile: the host daemon
  uses the same Haskell worker and shared Poetry adapter setup path as the rest of the runtime
- substrate bootstrap entrypoints under `bootstrap/` that reconcile only the host prerequisites
  needed to build or enter the active `infernix` launcher, then invoke the matching binary command
  for cluster lifecycle, validation, and teardown
- one repo-local kubeconfig published under the active build-output location rather than the
  user's global kubeconfig; Kind and `nvkind` use a transient scratch kubeconfig during cluster
  create or delete so lifecycle-owned lock files never become part of the supported repo contract

<!-- infernix:route-registry:readme:start -->
- always-published routed prefixes: `/harbor/api`, `/harbor`, `/minio/console`, `/minio/s3`, `/pulsar/admin`, `/pulsar/ws`
- demo-only routed prefixes (present when `.dhall` `demo_ui = True`): `/`, `/api`, `/auth`, `/ws`, `/api/objects`
- registry-owned rewrites: `/harbor/api` -> `/api`; `/harbor` -> `/`; `/minio/console` -> `/`; `/minio/s3` -> `/`; `/pulsar/admin` -> `/`; `/pulsar/ws` -> `/ws`
<!-- infernix:route-registry:readme:end -->

The optional demo UI runs in the cluster as the `infernix-demo` workload when the active `.dhall`
`demo_ui` flag is on. The supported deployment shape splits inference work across three daemon
roles (see [documents/architecture/daemon_topology.md](documents/architecture/daemon_topology.md)):
the stateless frontend Deployment (`infernix-demo`), the stateless coordinator Deployment
(`infernix-coordinator`, owning Pulsar dispatch, batching, result writeback, and the lazy
model-weight bootstrap workflow), and the stateful engine role (`infernix-engine` Deployment on
Linux substrates with strict one-per-node anti-affinity; the on-host `./.build/infernix service`
daemon on Apple silicon, with the same one-per-node rule enforced via an exclusive `flock(2)`).
The frontend and coordinator Deployments scale horizontally with replicas ≥ 2 under HA defaults;
the engine role runs at most one pod per node because multiple engines per node would duplicate
KV cache and model-weight memory with no performance gain. On a Linux node with multiple NVIDIA
devices, the single engine pod owns all local devices and the active `.dhall` decides per-device
model assignment. **No daemon has a PVC** — durable state lives only in MinIO and Pulsar. Model
weights are pulled from the `infernix-models` MinIO bucket on first use (lazy bootstrap via a
Pulsar Failover subscription owned by the coordinator with exactly-once semantics) and staged
into the engine pod's ephemeral `emptyDir` model cache with a hard `sizeLimit`; pod restart
wipes the cache and the next request repopulates from MinIO. User uploads and engine-generated
artifacts (images, audio, video) live in the demo-gated `infernix-demo-objects` bucket; the
browser reads and writes them through presigned URLs minted at `/api/objects`. On Apple, `./.build/infernix` still builds and drives the control plane from the
host, `cluster up` keeps Harbor, MinIO, Pulsar, PostgreSQL, Envoy Gateway, `infernix-demo`, and
`infernix-coordinator` (today's in-cluster Apple `infernix-service` daemon, renamed under
Phase 7 Sprint 7.7) in Kind, and routed manual inference enters the coordinator before
Apple-native batches move through Pulsar to the host-side `./.build/infernix service` engine
executor. On Linux, the same routed demo surface bridges through Pulsar into the coordinator
Deployment, which hands batches off to the engine Deployment. `/api/publication` now keeps
`apiUpstream.mode: cluster-demo` for the stable browser base URL, reports
`daemonLocation: cluster-pod` for every substrate, adds `inferenceExecutorLocation`, and keeps
`inferenceDispatchMode` so Apple can advertise `pulsar-bridge-to-host-daemon` while Linux
advertises `pulsar-bridge-to-cluster-daemon`. Production deployments leave the demo flag off,
accept inference work via Pulsar subscription only, and run only the engine Deployment. The
local Kind and HA substrate is the validation and operator baseline for Apple, CPU, and CUDA
runtime targets.

## Getting Started

Use the substrate bootstrap that matches the host you actually want to run:

```bash
# Apple Silicon / Metal host-native lane.
./bootstrap/apple-silicon.sh up

# Ubuntu 24.04 CPU lane.
./bootstrap/linux-cpu.sh up

# Ubuntu 24.04 NVIDIA lane.
./bootstrap/linux-gpu.sh up
```

Each bootstrap entrypoint is designed to be safe to rerun. It probes the current host state,
installs only the missing supported prerequisites for that substrate, verifies any same-process
tool it just installed before continuing, builds or enters the supported launcher path, and then
runs the requested `infernix` command. The shell entrypoints do not directly create Kind
clusters, deploy Kubernetes manifests, or pull container images; those responsibilities live in
the Haskell control plane.

After a successful run, each script prints the next commands for that substrate, including:

- `doctor` to re-check prerequisites
- `status` to print the edge port and route inventory
- `test` to run `infernix test all`
- `down` to delete the cluster while preserving repo-local durable state, build artifacts,
  substrate images, host binaries, and host prerequisites

On `linux-gpu`, if `nvidia-smi` does not already work on the host, the bootstrap installs the
recommended Ubuntu compute driver, stops, and tells you to reboot and run the same command again.

## System Prerequisites

The supported stage-0 entrypoints are the substrate bootstraps under `bootstrap/`:

- on Apple Silicon, run `./bootstrap/apple-silicon.sh doctor`
- on Linux CPU, run `./bootstrap/linux-cpu.sh doctor`
- on Linux GPU, run `./bootstrap/linux-gpu.sh doctor`

The manual package-manager commands below remain the reference path that those bootstrap scripts
drive or mirror.

Current status:

- after `./.build/infernix` exists on Apple Silicon, supported host-native commands reconcile
  the supported Colima `8 CPU / 16 GiB` profile, Docker CLI, `kind`, `kubectl`, `helm`, Node.js,
  the Homebrew-managed `python@3.12` formula and `python3.12` command, and Poetry through the
  supported package-manager or user-local bootstrap path when the active flow needs them
- Apple host-native adapter setup and validation paths materialize `python/.venv/` on demand after
  reconciling the Homebrew-managed `python@3.12` formula and `python3.12` command, or reusing a
  compatible Python 3.12+ executable that is already available, plus a user-local Poetry bootstrap
  when needed
- Apple routed Playwright validation now runs host-native `npm exec` against the published edge on
  `127.0.0.1`; because Apple retained Kind state is replayed into and out of the worker rather
  than bind-mounted, large `./.data/kind/apple-silicon/` trees can make `up`, `test`, and `down`
  slower than Linux
- Linux outer-container lifecycle runs pass host-resolved `./.data/kind/<runtime-mode>/` and
  `./.build/kind/registry/` paths into the generated Kind or `nvkind` node config so node-local
  PVs and registry host config are preserved by direct Docker bind mounts instead of replay copies
- `linux-cpu` keeps its host prerequisites at Docker Engine plus the Docker buildx and Compose
  plugins, and `linux-gpu` adds the documented NVIDIA driver and container-toolkit requirements on
  top of that

The Linux install examples below assume an Ubuntu 24.04 host.

### Apple Silicon host prerequisites

Preferred path:

```bash
./bootstrap/apple-silicon.sh doctor
```

Required before building `./.build/infernix` on the host:

- Homebrew
- `ghcup` with `ghc 9.14.1` and `cabal 3.16.1.0` active

Supported install path:

```bash
# Homebrew (official installer).
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install ghcup from Homebrew.
brew install ghcup

# Haskell toolchain version selection remains ghcup-managed.
ghcup install ghc 9.14.1
ghcup set ghc 9.14.1
ghcup install cabal 3.16.1.0
ghcup set cabal 3.16.1.0
```

Notes:

- Homebrew-managed `ghcup` is the supported bootstrap because the Apple host-native workflow still
  depends on an explicitly selected GHC and Cabal pair
- Colima is the only supported Docker environment on Apple Silicon; once `./.build/infernix`
  exists, supported commands install it from Homebrew together with the Docker CLI, `kind`,
  `kubectl`, `helm`, Node.js, the Homebrew-managed `python@3.12` formula and `python3.12`
  command, and any other operator-facing tools needed by the active path; Docker-backed Apple
  flows reconcile Colima to at least `8 CPU / 16 GiB`
- Apple adapter setup and validation commands reconcile the Homebrew-managed `python@3.12` formula
  and `python3.12` command plus a user-local Poetry bootstrap when `poetry` is absent; the Poetry
  bootstrap may reuse an already available compatible Python 3.12+ executable, after which all
  host-side Python configuration continues through the repo-local `python/.venv/`

### Linux CPU host prerequisites

Preferred path:

```bash
./bootstrap/linux-cpu.sh doctor
```

Required on the host:

- Docker Engine
- Docker buildx plugin
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

### Linux GPU host prerequisites

Preferred path:

```bash
./bootstrap/linux-gpu.sh doctor
```

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
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled
sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place
sudo systemctl restart docker

# Verify both the host GPU and Docker GPU handoff.
nvidia-smi -L
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L
docker run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L
```

Notes:

- the supported `linux-gpu` bootstrap can install the recommended Ubuntu compute driver when the
  host does not already satisfy `nvidia-smi`, but that path intentionally stops for a reboot
  before continuing
- the supported `linux-gpu` lane does not need host-installed `kind`, `kubectl`, `helm`, Node.js,
  or GHC because the baked `infernix-linux-gpu:local` image carries them
- plan for substantial free disk space before `cluster up` or `test all`; the Kind preload plus
  Harbor-backed rollout is materially heavier than the CPU lane
- everything beyond Docker plus the NVIDIA host prerequisites happens inside the shared Linux
  substrate image build or runtime path

### Warning guidance

The supported lifecycle treats warnings as either actionable cleanup or explicitly documented
upstream or packaging constraints. Operators should use
[the cluster bootstrap runbook](documents/operations/cluster_bootstrap_runbook.md) for the canonical
warning classification. In short:

- long image publication, final-image preload, Apple retained-state replay, and early Kubernetes
  readiness warnings can be healthy convergence while lifecycle heartbeat fields continue to update
- host resource warnings such as `SystemOOM` are environment contention and should be addressed
  before rerunning heavy lifecycle work
- buildx, npm update notices, npm deprecation warnings, Python root-pip warnings, and GHCup
  shell-profile warnings are eliminated on the current supported image and web toolchain; if they
  return, treat them as regressions unless the canonical policy doc names a new upstream constraint
- Playwright failures for a missing `web/scripts/install-purescript.mjs` are image contract
  regressions; the substrate image must copy `web/scripts/` before npm `postinstall`
- the remaining GHCup no-update message and generic PATH advice come from the upstream `get-ghcup`
  installer; accept them only when the Dockerfile-owned `PATH` works, the pinned toolchain installs,
  and the image build exits zero
- current PureScript and Spago toolchain ownership is tracked in
  [the PureScript policy](documents/development/purescript_policy.md), and Python packaging warning
  ownership is tracked in [the Python policy](documents/development/python_policy.md)

## Demo and Validation Quick Start

The local HA Kind cluster is the supported demo ground and full-suite validation ground for all
three runtime modes. `cluster up` owns the bring-up path, `cluster status` prints the chosen
edge port plus the published route inventory, and the demo UI is available at
`http://127.0.0.1:<edge-port>/` whenever the active generated `.dhall` enables `demo_ui`.

`infernix test all` is the canonical aggregate suite on every substrate. It runs every supported
validation layer for the currently staged substrate; full repository substrate closure is obtained
by restaging and rerunning the same complete suite for each supported substrate.

- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`

### Apple Silicon (host-native)

Apple Silicon has no Dockerfile. The supported entrypoint is the repo-owned bootstrap:

```bash
./bootstrap/apple-silicon.sh up
./bootstrap/apple-silicon.sh status
./bootstrap/apple-silicon.sh test
./bootstrap/apple-silicon.sh down
```

Direct reference commands:

```bash
cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes
./.build/infernix cluster up
./.build/infernix cluster status
./.build/infernix test all
./.build/infernix cluster down
```

`cluster up` publishes `./.build/infernix.kubeconfig` and never touches `$HOME/.kube/config`.
Kind create or delete uses a transient host-local scratch kubeconfig first, so the supported
repo-local kubeconfig remains the only operator-facing file under `./.build/`. On the supported
minimal-prerequisites path, the bootstrap and then the binary reconcile Homebrew-managed operator
tools and Poetry bootstrap before an adapter setup or validation path first needs the shared
`python/.venv/`.

### Linux CPU (outer container)

The `linux-cpu` substrate ships one baked image snapshot, `infernix-linux-cpu:local`, built from
`docker/linux-substrate.Dockerfile` with `BASE_IMAGE=ubuntu:24.04`. That image acts as the
Compose-launched control plane, the in-cluster workload image source, and the Linux routed-E2E
executor.

Supported bootstrap path:

```bash
./bootstrap/linux-cpu.sh up
./bootstrap/linux-cpu.sh status
./bootstrap/linux-cpu.sh test
./bootstrap/linux-cpu.sh down
```

Direct reference commands:

```bash
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster up
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster status
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix cluster down
```

The Linux launcher bind-mounts only `./.data/` and the Docker socket. The baked image owns the
full toolchain, source snapshot, build root, and `/opt/infernix/chart/charts/` chart archive
cache, so the supported runtime
path does not install anything via `apt`, `pip`, or ad hoc host-side `cabal build`. The Linux
bootstrap invokes the same Compose service shape that operators use directly, while the binary
owns substrate staging, cluster lifecycle, image preparation, and validation. On both Linux
substrates, Kind or `nvkind` create or delete uses a launcher-local scratch kubeconfig under the
container temp directory and the lifecycle publishes the durable operator-facing kubeconfig
afterward to
`./.data/runtime/infernix.kubeconfig`.

### Linux GPU (outer container)

The `linux-gpu` substrate ships one baked image snapshot, `infernix-linux-gpu:local`, built
from `docker/linux-substrate.Dockerfile` with a CUDA base image. The same single
`compose.yaml` service used on Linux CPU selects that image through an explicit one-shot
Compose image selector while keeping the outer control-plane container itself off the NVIDIA
runtime path. CPU hosts keep using `infernix-linux-cpu:local`, so they do not carry CUDA baggage.

Supported bootstrap path:

```bash
./bootstrap/linux-gpu.sh up
./bootstrap/linux-gpu.sh status
./bootstrap/linux-gpu.sh test
./bootstrap/linux-gpu.sh down
```

On a host that does not already pass `nvidia-smi -L`, the first `doctor`, `up`, or `test` run may
install the recommended Ubuntu compute driver, stop, and instruct you to reboot before rerunning
the same command.

Direct reference commands:

```bash
LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix cluster up
LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix cluster status
LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix kubectl -n platform exec deployment/infernix-engine -- nvidia-smi -L
LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix test all
LAUNCHER_IMAGE=infernix-linux-gpu:local docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix cluster down
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
- `infernix cache evict [--model MODEL_ID]`
- `infernix cache rebuild [--model MODEL_ID]`
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
- `infernix internal materialize-substrate <runtime-mode> [--demo-ui true|false]`
- `infernix internal demo-config {load,validate}`
- `infernix internal pulsar-roundtrip DEMO_CONFIG_PATH MODEL_ID INPUT_TEXT`

`infernix-demo` (demo UI HTTP host, gated by `.dhall` `demo_ui` flag):

- `infernix-demo serve [--dhall PATH] [--port PORT]`

Every repo-owned lifecycle, cache, validation, and docs command other than `infernix service` and
`infernix-demo serve` is declarative and idempotent. `infernix kubectl ...` is a scoped wrapper
around upstream `kubectl`, not a parallel lifecycle surface.

## Runtime and Image Flow

- `cluster up` is the supported HA testing and demo-ground bring-up command
- `cluster up` declaratively reconciles Kind, manual storage, Harbor-backed images, Helm workloads,
  repo-local kubeconfig publication, and publication of the active substrate configuration; Kind
  or `nvkind` create or delete uses a transient scratch kubeconfig while the published repo-local
  kubeconfig remains the supported operator surface
- `bootstrap/*.sh` commands are launchers for `infernix` commands only after host prerequisites and
  the substrate-specific binary or container launcher are ready; they do not directly manage Kind,
  Kubernetes resources, manifests, or cluster workload image pulls
- `infernix internal materialize-substrate <runtime-mode> [--demo-ui true|false]` stages the
  active demo `.dhall` file that defines the demo catalog and the engine binding for each
  demo-visible model on that substrate
- `cluster up` bootstraps Harbor first through Helm and allows Harbor plus only the storage or
  support services Harbor needs during bootstrap, including MinIO and PostgreSQL, to pull from
  public container repositories
- after Harbor is responsive, `cluster up` mirrors every remaining non-Harbor image into Harbor
  before deploying those workloads, including third-party platform images and the active
  `infernix` runtime image
- on Linux substrates the active runtime image is the same launcher-selected
  `infernix-linux-<mode>:local` image used by the outer control-plane launcher; on Apple Silicon
  the host-native `infernix` binary builds the cluster-resident runtime image and publishes it to
  Harbor after Harbor is ready
- every non-Harbor pod pulls from local Harbor
- Harbor and only the storage or support services Harbor needs are the allowed direct-upstream
  bootstrap exception before the Harbor-backed pull contract takes over
- `cluster up` always deploys the mandatory local HA topology: 3x Harbor application-plane services
  where the selected chart supports them, 4x MinIO, 3x Pulsar HA surfaces where the selected
  chart supports them, Prometheus, Grafana, and a dedicated operator-managed Patroni PostgreSQL
  cluster for each service that requires durable PostgreSQL storage
- every other platform, control-plane, and inference service with metrics syncs with Prometheus;
  Grafana reads from Prometheus and may use its own dedicated PostgreSQL backend under the same
  Patroni and Percona-operator rules
- services that can self-deploy PostgreSQL still disable that embedded database path and target a
  dedicated operator-managed cluster instead
- repo-owned Helm values suppress hard pod anti-affinity and equivalent hard scheduling constraints
  as needed for local Kind scheduling
- `cluster down` removes cluster state without deleting authoritative data under `./.data/`;
  bootstrap `down` commands preserve `./.build/`, `./.data/`, the host-level container build,
  the Apple host binary, and installed Docker or CUDA prerequisites
- MinIO is the durable source of truth for manifests, durable model artifacts, and large outputs
- Pulsar is the durable transport for inference requests and result publication
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
- PVs bind deterministically into `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- explicit PV-to-PVC binding guarantees clean `cluster down` and `cluster up` rebinding behavior
- storage reconciliation is part of `cluster up`; there is no separate storage reconcile command
- each service that requires durable PostgreSQL storage deploys its own Patroni cluster managed by
  the Percona Kubernetes operator

MinIO is authoritative for durable artifacts and large outputs. Local cache state is derived and
rebuildable.

## Configuration and Runtime Contract

- a `.dhall` configuration defines the runtime contract for supported service flows; the active
  `.dhall` names `daemonRole`, `clusterDaemon`, optional `hostDaemon`, `request_topics : List Text`,
  `result_topic : Text`, `engines : List EngineBinding`, and the optional `demo_ui : Bool` flag
  that gates the `infernix-demo` workload
- Apple host lifecycle and validation commands materialize or verify that file under `./.build/`;
  `./.build/infernix internal materialize-substrate apple-silicon` remains the direct helper for
  explicit restaging or inspection
- Linux outer-container lifecycle and validation commands materialize or verify that file under
  `/workspace/.build/outer-container/build/` inside the launcher image;
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  remains the direct helper for explicit restaging or inspection
- the generated demo `.dhall` file enumerates the demo-visible models and workloads for that mode
  and binds each one to its engine or runtime lane
- the generated demo `.dhall` file is the exact source of truth for which models and engine bindings
  appear in the demo UI for that mode (when the demo UI is enabled)
- the set of generated mode-specific demo `.dhall` files must cover every model or workload row in
  the comprehensive model, format, and engine matrix
- each daemon reads the staged substrate file at startup; hot reload, admin HTTP, and route or
  device remapping are outside the supported service contract
- the production inference surface is Pulsar subscription only and runs only the engine role
  (`infernix-engine` Deployment on Linux substrates; on-host `infernix service` daemon on Apple
  silicon); when the demo UI is enabled, the stateless coordinator role
  (`infernix-coordinator` Deployment) joins the cluster to own per-context dispatch, batching,
  and result writeback. On every substrate the coordinator consumes protobuf requests from the
  configured request topics and forwards batches to `inference.batch.<mode>`; the engine role
  consumes those batches, executes inference, and publishes results to
  `inference.result.<mode>`; no HTTP listener is bound on either role
- local cache state is never authoritative; it is reconstructed from durable metadata and durable
  artifacts

## Messaging and Lane Model

- the supported production topic contract centers on the configured request topics, result topic,
  daemon role metadata, and any Apple host batch topic carried in the active `.dhall`; the
  generated defaults are one `inference.request.<runtime-mode>` topic family, one
  `inference.result.<runtime-mode>` topic family, and, on Apple, one
  `inference.batch.apple-silicon.host` topic
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
  shares the default Cabal library exposed by the `infernix` package, ships in the same
  per-substrate OCI image on Linux); it serves `web/dist/` produced by `spago bundle`
- on Linux substrates, the substrate container carries the spago plus purs toolchain, Playwright
  system packages, and the three browser engines; `infernix test e2e` runs
  `npm --prefix web exec -- playwright test` inside that same image
- the Apple Silicon host-native routed-E2E executor uses host `npm exec` with the same typed
  fixture path as Linux and awaits the Apple validation pass
- the `infernix-demo` workload is deployed through repo-owned Helm chart templates and values, and
  is gated by the `.dhall` `demo_ui` flag; production deployments leave it off
- the demo UI catalog is derived from the generated mode-specific demo `.dhall` file for the active
  mode
- repo-owned `purescript-spec` suites under `web/test/` cover generated contracts, publication
  rendering, and view behavior; `infernix test unit` runs `spago test` alongside the Haskell unit
  suites
- Playwright stays container-owned on Linux supported paths: routed E2E runs from the substrate
  image, and the test orchestration lives in the Haskell integration test suite
- the demo UI can submit manual inference requests against any registered model in the active demo
  catalog; the production inference surface remains Pulsar topics named in the active `.dhall`
- the demo UI, demo API surface, generated PureScript contracts, and validation suites must expand
  until every supported model, format, and engine combination has a browser-visible and testable
  path under the demo surface
- when the demo UI is enabled, the supported product shape is a multi-user durable-context chat
  application: Keycloak self-signup (no email verification), WebSocket post-login transport,
  per-context durable conversation history backed by Pulsar conversation topics, MinIO-backed
  artifact upload/download via presigned URLs, and a dedicated artifacts view that renders
  image, playable audio, and video artifacts inline, previews bounded text/JSON, uses
  browser-native PDF handling, and treats MIDI, MusicXML/MXL notation, unknown, and generic
  binary artifacts as download-only by default; backend pods are stateless and the browser
  holds no durable state, so signing in on any device fully reconstitutes the user's
  contexts, drafts, transcripts, and artifacts; business logic — reducer, dispatcher, prefix-
  hash, idempotency — lives only in Haskell and surfaces to the SPA as typed snapshots and
  patches via `purescript-bridge`. The product-agnostic primitives live in
  [documents/architecture/durable_context_design.md](documents/architecture/durable_context_design.md);
  the demo-specific bindings live in
  [documents/architecture/demo_app_design.md](documents/architecture/demo_app_design.md);
  the supported three-role daemon model (stateless frontend, stateless coordinator,
  one-per-node stateful engine) lives in
  [documents/architecture/daemon_topology.md](documents/architecture/daemon_topology.md);
  and the execution-ordered build out lives in
  [DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md](DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md)

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
- the demo SPA must present a usable browser path for manual inference against every supported
  matrix row, including request forms, progress states, result rendering, and object-reference
  handling where needed
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
