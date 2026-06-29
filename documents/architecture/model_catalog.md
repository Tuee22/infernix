# Model Catalog

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the authoritative model catalog contract that the service and UI both consume.

## Current Status

The README matrix reflects the realness rebinds: the music-transcription rows are rebound to modern
PyTorch models (YourMT3+ for the MT3 row, `piano_transcription_inference` for the Omnizart row),
residual until their `pytorch-python` adapter binding lands; the redundant Basic Pitch TensorFlow row
is dropped (covered by the basic-pitch ONNX and Core ML rows); Apple CTranslate2 is a viable CPU path;
and Wan on Apple MPS is a residual rather than promoted support. The generated Haskell catalog keeps
runtime catalogs executable-only and records named residual rows separately through
`residualMatrixRowIdsForMode`: the PyTorch-rebound music-transcription rows are residual on every
substrate until their adapter binding lands, and Wan Apple MPS is residual until validated. `infernix lint docs` now mechanically
checks the README matrix cells against the generated runnable catalogs, named residual rows, and
`Not recommended` states so documentation cannot silently re-promote a residual or hide a runnable
binding. Realness for the runnable rows is enforced in the engine code by the realness lint; the
reopened Phases 1/4/6 own the per-accelerator real-output delivery (Waves K/L).

## Contract

The model catalog is Haskell-owned typed configuration derived from the README matrix.

- the service registry owns one entry for every README matrix row
- the active generated substrate file selects the engine for each supported row and carries the
  resulting catalog as `infernix-substrate.dhall`, a typed Dhall record whose schema lives at
  `dhall/InfernixSubstrate.dhall` and is decoded in-process by the `dhall` Haskell library
- `cluster up` publishes a cluster-role `infernix-substrate.dhall` payload into
  `ConfigMap/infernix-demo-config` for cluster-resident consumers; on Apple this preserves the
  active generated catalog and `demo_ui` setting while using cluster daemon metadata rather than
  the host daemon role staged under `./.build/`

## Entry Shape

Each generated entry includes:

- matrix-row identity
- stable model identifier
- display label and workload family
- artifact or format type
- reference model metadata and download URL
- selected engine for the active runtime mode
- named residual status when a researched matrix cell is intentionally not runnable
- request shape metadata used by the API, UI, and tests
- runtime-lane metadata such as GPU requirement and lane identifier

## Rules

- the generated catalog, not a hidden UI-only allowlist, is the source of truth for the browser-visible catalog
- the generated catalog records the selected engine exactly as chosen from the README matrix
- docs lint fails when a README matrix cell no longer matches the generated catalog or the explicit
  residual set
- named residual cells are excluded from the runtime catalog and tracked explicitly as residual
  row ids; they are planning and validation obligations, not executable model descriptors
- runtime-local caches derive from generated catalog and durable artifact metadata
- switching runtime modes changes the generated catalog and selected engine bindings without changing route structure

## ResultFamily and Result-Surface Mapping

Every README matrix row resolves to a closed `ResultFamily` sum type and a single result-surface
shape — either an inline text payload or a typed object reference into the always-on
`infernix-demo-objects` MinIO bucket. This mapping is the canonical home for the 18-row to
`ResultFamily` and inline-vs-object-ref correspondence; it is consistent with the per-family
result contract in
[../development/testing_strategy.md](../development/testing_strategy.md) and the demo validation
surface in [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md).

The runtime worker dispatches through the selected engine binding — the Python adapter transform
over a prebuilt host wheel for python-stdio bindings, or the native runner binary resolved from a
typed `HostConfig` absolute path for native-process-runner bindings — fetches model weights lazily
from the `infernix-models` MinIO bucket via `adapters.model_cache.get_model_path`, and publishes the
typed per-family result surface. Realness is guaranteed by construction: the engine code cannot
return a fabricated result (any missing-weights/load/engine failure raises → `failed`), enforced by
the realness lint. Per-accelerator real-output delivery is owned by the reopened Phases 1/4/6, and any
row whose real engine is not yet landed is an explicit residual in `residualMatrixRowIdsForMode`.

`ResultFamily` is resolved from `family` + `artifactType` + `matrixRowId`. The coarse `family`
field collapses source-separation, audio-to-MIDI, and audio-generation under a single `audio`
label, so the fine-grained `ResultFamily` is the authoritative discriminator the catalog, runtime,
and tests share.

### Proto facts

`ResultPayload` carries `oneof {inline_output, object_ref}` on the wire. `buildPayload` now routes
LLM and speech results to inline text and artifact families to object references. The newer proto
fields are a non-text **input** object-ref on `InferenceRequest` / `WorkerRequest` and an
object-ref **output** on `WorkerResponse` for the artifact adapters.
Artifact results always use the always-on `infernix-demo-objects` bucket, never the retired
`infernix-runtime` / `infernix-results` buckets.

### Row-to-ResultFamily table

The table maps every row in the README "Comprehensive Model / Format / Engine Matrix" to its
`ResultFamily` and result surface. `inline_output` rows return inline text; `object_ref` rows
return a typed object reference into `infernix-demo-objects`.

| Matrix row (reference model / format) | Workload family | `ResultFamily` | Result surface |
|---|---|---|---|
| SmolLM2-135M-Instruct (HF safetensors) | LLM | `LLM` | `inline_output` |
| Qwen2.5-1.5B-Instruct-AWQ (AWQ) | LLM | `LLM` | `inline_output` |
| TinyLlama-1.1B-Chat-v1.0-GPTQ (GPTQ) | LLM | `LLM` | `inline_output` |
| TinyLlama-1.1B-Chat-v1.0-GGUF (GGUF) | LLM | `LLM` | `inline_output` |
| Qwen1.5-1.8B-Chat-4bit (MLX) | LLM | `LLM` | `inline_output` |
| whisper-small (whisper.cpp / GGML) | Speech transcription | `SpeechTranscription` | `inline_output` |
| faster-whisper-small (CTranslate2) | Speech transcription | `SpeechTranscription` | `inline_output` |
| htdemucs (Demucs) | Source separation | `SourceSeparation` | `object_ref` |
| Open-Unmix | Source separation | `SourceSeparation` | `object_ref` |
| basic-pitch (Core ML) | Audio-to-MIDI | `AudioToMidi` | `object_ref` |
| basic-pitch (ONNX) | Audio-to-MIDI | `AudioToMidi` | `object_ref` |
| YourMT3+ (PyTorch) | Music transcription | `MusicTranscription` | `object_ref` |
| piano_transcription_inference (PyTorch) | Music transcription | `MusicTranscription` | `object_ref` |
| SDXL Turbo (Diffusers / safetensors) | Image generation | `ImageGeneration` | `object_ref` |
| Apple Stable Diffusion (Core ML) | Image generation | `ImageGeneration` | `object_ref` |
| Wan2.1-T2V-1.3B (Diffusers / safetensors) | Video generation | `VideoGeneration` | `object_ref` |
| bark-small (PyTorch / HF) | Audio generation / TTS | `AudioGeneration` | `object_ref` |
| Audiveris (JVM application) | OMR / notation extraction | `OmrTool` | `object_ref` |

The nine `ResultFamily` constructors — `LLM`, `SpeechTranscription`, `SourceSeparation`,
`AudioToMidi`, `MusicTranscription`, `ImageGeneration`, `VideoGeneration`, `AudioGeneration`, and
`OmrTool` — partition all 18 rows. The two inline-text families (`LLM`, `SpeechTranscription`)
return `inline_output`; the seven artifact families return an `object_ref` into
`infernix-demo-objects`.

### Substrate selection and union coverage

The generated substrate catalog records the selected runnable engine exactly as chosen from the
README matrix. Rows whose engine cell for the active substrate is `Not recommended` are omitted
from that substrate's runnable catalog. Rows whose engine cell is a named residual are omitted from
the runtime catalog and listed by `residualMatrixRowIdsForMode` so tests and planning can prove
they are deliberate unresolved support instead of accidental catalog drift.

## Cross-References

- [realness_contract.md](realness_contract.md)
- [runtime_modes.md](runtime_modes.md)
- [../reference/api_surface.md](../reference/api_surface.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
