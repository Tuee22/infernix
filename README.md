# Infernix

Infernix is a Haskell inference control plane for running heterogeneous model runtimes behind one
typed operator surface.

It handles orchestration, model resolution, artifact delivery, request routing, runtime
supervision, and browser-facing manual inference while leaving execution kernels to the best
runtime for each model family.

The repository currently contains a partial implementation of that platform. This README captures
the intended product contract and operator direction, while
[DEVELOPMENT_PLAN/](DEVELOPMENT_PLAN/README.md) is the authoritative source for implementation
status, unfinished phases, and closure criteria.

This repository serves two aligned purposes:

- provide consistent binary or container build outputs for three supported runtime modes: Apple
  Silicon or Metal, Ubuntu 24.04 CPU, and Ubuntu 24.04 NVIDIA CUDA containers
- provide a local Kind cluster, running the mandatory HA service topology, as the testing and demo
  ground for the control plane; the webapp is a demo surface on that substrate

## Highlights

- one Haskell binary: `infernix`
- one Kind and Helm workflow for the HA testing and demo ground
- one mandatory local HA topology: Harbor, MinIO, and Pulsar on Kind
- one local Harbor registry as the image source for every non-Harbor pod
- one manual persistent-storage doctrine rooted at `./.data/`
- one PureScript demo webapp, deployed through Helm, with Haskell-owned frontend contracts
- one browser-based manual inference demo workbench for any registered model
- three runtime targets: Apple Silicon or Metal, Ubuntu 24.04 CPU, and Ubuntu 24.04 NVIDIA CUDA
  containers
- one validation surface spanning `fourmolu`, `cabal-fmt`, `hlint`, unit tests, integration tests,
  `purescript-spec`, and Playwright, with coverage expected to grow until the full runtime matrix is
  exercised through the demo webapp and test suite

## What Infernix Does

At full plan closure, Infernix does not reimplement model kernels. It coordinates them.

- consumes inference requests from Pulsar and manual browser or API submissions that share the same
  typed service domain
- resolves logical models against durable manifest and artifact metadata
- acquires missing artifacts into MinIO idempotently when upstream acquisition policy allows it
- materializes runtime-local cache state from durable sources
- launches and supervises engine-specific workers
- routes requests into per-engine, per-model, per-device lanes while leaving batching and runtime
  memory policy to the child engine
- stores large outputs in MinIO and returns references when appropriate
- exposes a demo web UI for manually running inference against any registered model

## Supported Modes

The repository supports three first-class runtime modes. The local Kind cluster described later is
the HA testing and demo ground used to validate and demonstrate them.

| Mode | Build or deployment shape | Role in the repository | Intended engines |
|------|---------------------------|------------------------|------------------|
| Apple Silicon / Metal | host-native Apple binary path | direct host execution, local development, and Apple runtime parity behind the shared control-plane contract | `llama.cpp`, `MLX` or `MLX-LM`, `vllm-metal`, `PyTorch` on MPS, `Core ML`, `jax-metal` |
| Ubuntu 24.04 / CPU | native or containerized Linux CPU path | CPU-only validation, fallback, and non-GPU workloads under the same manifests, messaging, and runtime contract | `llama.cpp`, `whisper.cpp`, `PyTorch` CPU, `ONNX Runtime` CPU, JVM-hosted tools |
| Ubuntu 24.04 / NVIDIA CUDA Container | pinned CUDA container lane with NVIDIA runtime | high-throughput GPU execution under the same manifests, messaging, and runtime contract | `vLLM`, `PyTorch` CUDA, `Diffusers` or `ComfyUI`, `CTranslate2`, `TensorFlow` CUDA, `JAX/XLA`, `llama.cpp` when GGUF is the right artifact |

On Apple Silicon, `infernix` may install missing supported host prerequisites through the operator
flow, including Homebrew `poetry` and other declared Python dependencies required by repo-owned
runtime paths.

Infernix uses one operator, artifact, and browser-demo contract across Apple, CPU, and CUDA runtime
classes.

## Local Architecture

The supported local platform is built around:

- one Kind cluster used as the HA testing and demo ground for Harbor, MinIO, Pulsar, edge routing,
  and the demo webapp
- one reverse-proxied localhost edge port for the demo UI, API, Harbor, MinIO, and Pulsar browser surfaces
- one manual storage class backed by repo-owned PVs under `./.data/`
- one local Harbor registry used by every cluster pod except Harbor's own bootstrap path
- one cluster-resident demo webapp image, built from a separate webapp binary via `web/Dockerfile`,
  that also owns Playwright browser dependencies
- one repo-owned `cabal.project` that keeps host-native Cabal artifacts under `./.build/`
- one repo-local kubeconfig managed under the active build-output location rather than the user's
  global kubeconfig

The demo web UI always runs in the cluster, even when the Haskell daemon runs host-native on Apple
Silicon. The local Kind and HA substrate is the validation and operator baseline for Apple, CPU,
and CUDA runtime targets.

## HA Demo Ground Quick Start

The commands below operate the local HA testing and demo ground used to exercise the control plane,
the mandatory HA services, and the cluster-resident demo webapp.

### From Apple Host

Build the binary with the repo-owned Cabal defaults, bring up the test cluster, run the full suite,
then tear it down:

```bash
# Build the infernix binary using the repo-owned Cabal defaults.
cabal build infernix
# Reconcile the Kind test cluster, storage, images, and Helm workloads.
./.build/infernix cluster up
# Report cluster health, edge routing, and durable-state status.
./.build/infernix cluster status
# Query the cluster through the repo-local kubeconfig wrapper.
./.build/infernix kubectl get pods -A
# Run lint, unit, integration, and E2E validation.
./.build/infernix test all
# Tear down the Kind cluster while preserving authoritative data under ./.data.
./.build/infernix cluster down
```

The repo-owned `cabal.project` keeps generated host-native artifacts under `./.build/`. `cluster
up` auto-generates the mode-specific demo Dhall config for the active Apple mode, writes the
repo-local kubeconfig to
`./.build/infernix.kubeconfig`, and does not mutate `$HOME/.kube/config`.

### From Outer Container

Build the outer image, bring up the test cluster, run the full suite, then tear it down:

```bash
# Build the outer control-plane image.
docker compose build infernix
# Reconcile the Kind test cluster, storage, images, and Helm workloads.
docker compose run --rm infernix infernix cluster up
# Report cluster health, edge routing, and durable-state status.
docker compose run --rm infernix infernix cluster status
# Query the cluster through the repo-local kubeconfig wrapper.
docker compose run --rm infernix infernix kubectl get pods -A
# Run lint, unit, integration, and E2E validation.
docker compose run --rm infernix infernix test all
# Tear down the Kind cluster while preserving authoritative data under ./.data.
docker compose run --rm infernix infernix cluster down
```

Containerized builds keep all generated artifacts under `/opt/build/infernix`. Supported outer
container workflows and Dockerfile `cabal` invocations pass `--builddir=/opt/build/infernix`
explicitly so build output never lands in the mounted repository tree. The generated mode-specific
demo Dhall config and repo-local kubeconfig also live under `/opt/build/infernix` on this path.

## CLI Surface

The canonical supported CLI surface is:

- `infernix service`
- `infernix cluster up`
- `infernix cluster down`
- `infernix cluster status`
- `infernix kubectl ...`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`
- `infernix docs check`

Every repo-owned lifecycle, validation, and docs command other than `infernix service` is
declarative and idempotent. `infernix kubectl ...` is a scoped wrapper around upstream `kubectl`,
not a parallel lifecycle surface.

## Runtime and Image Flow

- `cluster up` is the supported HA testing and demo-ground bring-up command
- `cluster up` declaratively reconciles Kind, manual storage, Harbor-backed images, Helm workloads,
  repo-local kubeconfig, and generated mode-specific demo configuration
- `cluster up` generates the mode-specific demo `.dhall` file that defines the demo catalog and the
  engine binding for each demo-visible model on the active mode
- `cluster up` mirrors required third-party images into Harbor before deploying non-Harbor workloads
- `cluster up` builds repo-owned images, including the demo webapp image through `web/Dockerfile`,
  and publishes them to Harbor before Helm rollout
- every non-Harbor pod pulls from local Harbor
- Harbor is the only allowed direct-upstream bootstrap exception
- `cluster up` always deploys the mandatory local HA topology: 3x Harbor application-plane services
  where the selected chart supports them, 4x MinIO, and 3x Pulsar HA surfaces where the selected
  chart supports them
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
- PVCs are created only by Helm-owned StatefulSets or chart-owned persistence templates
- PVs are created only by `infernix` lifecycle logic
- PVs bind deterministically into `./.data/kind/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- explicit PV-to-PVC binding guarantees clean `cluster down` and `cluster up` rebinding behavior
- storage reconciliation is part of `cluster up`; there is no separate storage reconcile command

MinIO is authoritative for durable artifacts and large outputs. Local cache state is derived and
rebuildable.

## Configuration and Runtime Contract

- a `.dhall` configuration defines the runtime contract for supported service flows
- `cluster up` produces a mode-specific demo `.dhall` file as a build artifact for the active mode
- the generated demo `.dhall` file enumerates the demo-visible models and workloads for that mode
  and binds each one to its engine or runtime lane
- the generated demo `.dhall` file is the exact source of truth for which models and engine bindings
  appear in the demo UI for that mode
- the set of generated mode-specific demo `.dhall` files must cover every model or workload row in
  the comprehensive model, format, and engine matrix
- the service contract includes hot-reloadable configuration with safe worker drain, cache
  eviction, and route or device remapping semantics
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

The browser surface is a PureScript demo application with Haskell-generated shared contracts.

- Haskell types remain the source of truth for the frontend contract
- the demo webapp is a separate binary from `infernix` and is built through `web/Dockerfile`
- frontend contract generation happens during the demo webapp image build
- the demo webapp is deployed through repo-owned Helm chart templates and values
- the demo UI catalog is derived from the generated mode-specific demo `.dhall` file for the active
  mode
- `purescript-spec` covers contract and view behavior
- Playwright runs from the same image that serves the demo web UI
- the demo UI can submit manual inference requests against any registered model
- the demo UI, API surface, generated contracts, and validation suites must expand until every supported
  model, format, and engine combination has a browser-visible and testable path

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
- run `python3 tools/docs_check.py`, `infernix test lint`, and the relevant `infernix test ...`
  targets before opening changes

## License

[MIT](LICENSE)
