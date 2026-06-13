# Research Question

**Status**: Recovered working note

This file preserves the interrupted research task so a future Codex run can
continue without loading the full prior transcript. It is not an authoritative
architecture document and should not be treated as implementation status.

## Recovered Prompt

Run a comprehensive planning and architecture review of the Infernix
model-engine matrix.

The core question is:

> Have we actually chosen the right engine for each model under each supported
> substrate, and what should the installation/materialization strategy be for
> each engine?

The recovered request had these explicit requirements:

- review every row in the Comprehensive Model / Format / Engine Matrix in
  `README.md`
- verify the chosen engine for each model on `apple-silicon`, `linux-cpu`, and
  `linux-gpu`
- re-check every `Not recommended` cell and decide whether there really is no
  suitable engine choice
- for each viable engine, decide whether Infernix should use prebuilt wheels or
  binaries, build from source, use a controlled materializer, or bake the engine
  into an image
- prefer smaller upfront installs where possible, including on-demand engine
  materialization cached through MinIO, instead of giant Apple installs or giant
  Docker images
- review `~/jitML` for the pattern the user wants to adapt: typed artifact
  keys, content-addressed cache artifacts, MinIO-backed state, local
  materialization, ack-after-success, and redelivery on failure
- revisit the current `flock` singleton assumption; the user prefers running
  only one worker and relying on Pulsar ownership semantics to avoid races

## Current Repo Context

The current matrix lives in `README.md` under
`Comprehensive Model / Format / Engine Matrix`. The generated catalog mapping
lives in `src/Infernix/Models.hs`; rows with `Nothing` for a substrate are the
generated-catalog equivalent of `Not recommended`.

The repo currently draws a hard line between model weights and engine software:

- model weights, tokenizers, and configs are lazily bootstrapped into the
  `infernix-models` MinIO bucket and then cached in `/model-cache` or
  `./.data/runtime/model-cache`
- engine software is documented as prebuilt or baked ahead of inference, not
  installed during a user request
- Linux GPU Python engines use per-engine Poetry projects under
  `python/engines/<engine>/` and are intended to be baked into per-engine images
- Linux native binaries are expected under
  `/opt/infernix/engines/<adapterId>/`
- Apple uses a host-native daemon; `python/.venv` is currently framework-free.
  Phase 1 Sprint 1.14 has removed the Sprint 1.13 `tart` materialization lane
  from the host-tool schema and prerequisite path. Metal/Core ML native
  artifacts should be materialized on the Apple host through a Tart-free bridge
  and typed engine manifests under `./.data/engines/<adapterId>/`.

The previous investigation identified that the README matrix is partly ahead of
the concrete installer/materializer surface. Known gaps to keep in view:

- Apple-specific Python framework wheels for MLX, PyTorch MPS, Diffusers MPS,
  `jax-metal`, and related engines are not fully expressed as concrete install
  groups
- native-runner adapters such as `mlx-native`, `onnx-runtime-native`, and
  `jvm-native` need concrete materializers or binary acquisition plans
- Core ML bindings currently collapse to a generic `coreml-native` adapter id,
  while the legacy tart plan names row-specific artifacts
- live Linux validation has recently failed on missing native binaries such as
  `llama-cli` in the base engine pod
- docs still describe an Apple host `flock(2)` singleton, which conflicts with
  the user's preferred Pulsar-owned one-worker model

## Questions To Answer

1. For each matrix row, what is the best engine per substrate today?

   Check the README row, the generated catalog row, and current upstream
   support. Confirm whether the current choice is still appropriate for
   `apple-silicon`, `linux-cpu`, and `linux-gpu`.

2. Are the `Not recommended` cells still correct?

   Re-evaluate at least these categories:

   - AWQ and GPTQ LLM rows on CPU and Apple
   - MLX artifacts on Linux CPU and Linux CUDA
   - CTranslate2 / faster-whisper on Apple
   - TensorFlow Basic Pitch on Apple versus Core ML or ONNX
   - Core ML rows on Linux
   - SDXL Turbo and Wan2.1 on Linux CPU
   - any TensorFlow, JAX, or music-transcription rows with stale dependency
     assumptions

3. What is the right acquisition strategy for every accepted engine?

   Classify each engine as one of:

   - prebuilt Python wheel
   - prebuilt native binary
   - source build in a controlled materializer
   - Tart-free Apple Metal/Core ML host artifact
   - baked Linux image layer
   - JVM/tool runtime
   - not supported

   Record why, including platform support, dependency risk, first-use latency,
   image size, reproducibility, and validation cost.

4. Should Infernix add an engine artifact manifest/cache layer?

   The proposal to evaluate is a typed engine-artifact manifest, separate from
   the existing model-weight cache. It would describe an engine by adapter id,
   engine name, substrate, architecture, source or package reference, version,
   digest, expected binary or Python entrypoint, local install root, MinIO cache
   key, and smoke-validation command.

   The research should decide whether this belongs in MinIO, Harbor, the local
   `.data` tree, image layers, or a hybrid split.

5. What parts of the `~/jitML` design translate cleanly?

   Extract the reusable pattern, not the exact implementation. The likely
   transferable ideas are:

   - typed cache keys
   - content-addressed artifacts
   - conditional write / compare-and-swap behavior in MinIO
   - atomic local materialization
   - success-only acknowledgement
   - negative acknowledgement or redelivery on failed materialization

   Decide where that pattern fits Infernix engine artifacts and where it does
   not, especially for CUDA framework stacks and Apple native engines.

6. Can the Apple `flock` lock be removed safely?

   Determine whether the desired "one worker only" topology can be expressed
   through Pulsar subscription semantics, chart/launcher constraints, and daemon
   configuration. If more than one worker accidentally starts, the research
   should state whether Pulsar `Exclusive`, `Failover`, or another subscription
   mode protects the engine artifact materialization path and inference
   execution path.

7. What docs and plan updates would be needed?

   If the research changes the doctrine, identify the exact files likely to
   change:

   - `README.md`
   - `src/Infernix/Models.hs`
   - `documents/architecture/model_catalog.md`
   - `documents/architecture/daemon_topology.md`
   - `documents/development/python_policy.md`
   - `documents/engineering/build_artifacts.md`
   - `documents/engineering/object_storage.md`
   - `documents/engineering/portability.md`
   - `documents/operations/apple_silicon_runbook.md`
   - `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`
   - `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md`
   - `DEVELOPMENT_PLAN/cohort-validation-waves.md`

## Expected Deliverables

The research should produce:

- a row-by-row matrix of recommended engine choices by substrate
- a row-by-row installation/materialization recommendation
- a list of matrix cells that should change, including any former
  `Not recommended` cells that now have a viable option
- a proposed engine artifact manifest/cache design, or an explicit decision to
  keep engine software build-time only
- a recommendation on replacing Apple `flock` with a Pulsar-owned one-worker
  model
- a concrete implementation plan with validation gates, separated from any
  speculative future work

## Research Discipline

Use primary sources for upstream engine facts: official docs, official GitHub
repositories, release pages, and package metadata. Because engine support,
Python wheels, CUDA versions, Apple Silicon support, and model runtime docs
change frequently, verify current upstream facts during the research instead
of relying on memory.

Keep the answer bounded. Do not load entire prior Codex transcripts or broad
web pages into context. Work from this file, the local matrix/catalog files,
and targeted upstream source checks.

## Findings So Far

These notes recover the useful state from the interrupted research session.
They are preliminary findings, not yet applied doctrine.

### Local Sources Reviewed

- `README.md` comprehensive model / format / engine matrix.
- `src/Infernix/Models.hs` generated model catalog and row metadata.
- `documents/engineering/build_artifacts.md`.
- `documents/engineering/object_storage.md`.
- `documents/architecture/daemon_topology.md`.
- `documents/engineering/model_lifecycle.md`.
- `documents/development/python_policy.md`.
- Per-engine Python projects under `python/engines/`.
- Transferable cache/daemon materialization patterns from `~/jitML`.
- `~/jitML/documents/engineering/apple_silicon_metal_headless_builds.md`,
  which rejects Tart for daemon-grade headless Apple work because
  Virtualization.framework startup can depend on unlocked user keychain state.

### Matrix Findings

| Area | Current Finding |
| --- | --- |
| LLM GPU rows | `vLLM` remains the right Linux GPU default for Llama, Qwen, and similar transformer serving rows. |
| LLM Linux CPU rows | Treat vLLM CPU support cautiously. Upstream CPU support exists, but quantized CPU support is x86-focused for common formats such as AWQ/GPTQ, while Infernix `linux-cpu` includes arm64. Keep `llama.cpp`/GGUF as the portable CPU baseline unless the row is explicitly x86-only. |
| LLM Apple rows | `mlx-lm` is the strongest Apple-native LLM direction for supported model families. PyTorch MPS remains a practical fallback for rows already tied to PyTorch stacks. |
| Apple CTranslate2 cells | The current `Not recommended` posture looks too strong. CTranslate2 publishes macOS ARM64 support, so Apple CTranslate2 is viable for CPU-style translation/Whisper paths where the model format fits. It should be documented as viable but not necessarily preferred over MLX or Core ML where those are better. |
| Basic Pitch | Repository constraints still make TensorFlow Basic Pitch a poor direct fit because the project is pinned around Python 3.12/CUDA 12.8 lanes and TensorFlow/Magenta-era app compatibility remains a residual. ONNX or Core ML remain the credible portable paths. |
| TensorFlow | Linux CUDA installation is still an official path through TensorFlow package extras, but this does not solve the residual app-stack compatibility problem for legacy audio transcription rows. macOS TensorFlow GPU should not be treated as a first-class supported lane. |
| JAX / MT3 | JAX CPU/CUDA and Apple `jax-metal` exist, but MT3-style stacks remain residual/unmaintained enough that the matrix should not promote them without a concrete compatibility spike. |
| Omnizart | Earlier confidence was overclaimed. Keep Omnizart residual unless a maintained, Python-3.12-compatible path is proven. |
| Diffusers image/video rows | Diffusers remains the correct Linux GPU baseline for SDXL and Wan-style rows. Linux CPU should stay `Not recommended` for these rows. Apple MPS for Wan/video diffusion should remain unproven/residual rather than a promised lane. |
| Audiveris | The JVM/tool runtime direction is still appropriate for optical music recognition rows. It is not a Python engine artifact problem in the same way as vLLM/Diffusers/TensorFlow. |

### Materialization Findings

Infernix should split engine software artifacts from model weight artifacts,
but use compatible cache principles for both:

- Keep container images and heavyweight Linux runtime bases in Harbor.
- Use MinIO for immutable, content-addressed engine payloads that are expensive
  or platform-specific but should not be re-created per request.
- Keep model weights/checkpoints under the existing model lifecycle/cache
  doctrine, with explicit references from engine manifests where needed.
- Do not install CUDA frameworks at user-request time. CUDA framework stacks
  should be image-owned or pre-materialized by controlled bootstrap/materialize
  commands.
- Apple native engine artifacts are good candidates for explicit
  materialization into `./.data/engines/<adapterId>/`, but the target path must
  be Tart-free: runtime Metal framework compilation through a fixed host bridge,
  typed manifests, atomic local installs, and no keychain, Xcode UI, SwiftPM, or
  VM startup dependency on a cache miss.

Recommended engine artifact manifest fields:

- `adapterId`
- `engineName`
- `substrate`
- `architecture`
- `artifactKind` such as `wheelhouse`, `venv`, `native-binary`,
  `native-framework`, `jvm-tool`, or `container-layer`
- `sourceRef`
- `engineVersion`
- `pythonVersion` when applicable
- `cudaVersion` or native runtime version when applicable
- `digest`
- `minioObjectKey`
- `localInstallRoot`
- `entrypoint`
- `smokeCommand`

The useful `~/jitML` pattern is not "copy the implementation"; it is the
contract:

- typed keys for artifacts
- content-addressed immutable objects
- write-if-absent / compare-and-swap publication where mutable pointers are
  needed
- atomic local materialization into a temp directory followed by rename
- acknowledge work only after materialization, inference, and result publication
  have succeeded
- use negative acknowledgement or unacked-message redelivery when
  materialization fails

### Pulsar / Apple Lock Finding

The Apple `flock` should be replaceable in the target topology, but only if the
consumer model is made explicit. The recommended shape is:

- one Apple worker process per engine/materialization lane
- Pulsar `Exclusive` subscription when duplicate consumers are a configuration
  error
- intentional `Failover` only when standby workers are desired
- no `Shared` subscription for Apple native materialization or engine execution
  paths that assume single-writer local state
- acknowledgement only after local engine state and durable outputs are complete

This preserves the "one worker only" operator intent without relying on a
filesystem lock as the primary distributed coordination mechanism.

### Likely Follow-Up Edits

If these findings are promoted from research to implementation doctrine, likely
edits are needed in:

- `README.md`
- `src/Infernix/Models.hs`
- `documents/architecture/model_catalog.md`
- `documents/architecture/daemon_topology.md`
- `documents/development/python_policy.md`
- `documents/engineering/build_artifacts.md`
- `documents/engineering/object_storage.md`
- `documents/engineering/portability.md`
- `documents/operations/apple_silicon_runbook.md`
- `DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md`
- `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md`
- `DEVELOPMENT_PLAN/cohort-validation-waves.md`

Suggested first implementation slice:

1. Correct matrix cells that are already clear from upstream verification:
   Apple CTranslate2 viability, conservative vLLM CPU wording, TensorFlow/JAX
   residual notes, Omnizart residual status, and Wan Apple residual status.
2. Add an engine artifact manifest design that distinguishes model weights,
   Python engine environments, native Apple artifacts, JVM tools, and container
   images.
3. Update daemon topology docs to replace Apple `flock` as the intended
   coordination primitive with Pulsar subscription semantics plus
   ack-after-success behavior.
4. Add validation gates for each promoted cell: install/materialize smoke,
   engine startup smoke, one minimal inference fixture, cache reuse, and failed
   materialization redelivery.
