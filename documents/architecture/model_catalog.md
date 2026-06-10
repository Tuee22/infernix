# Model Catalog

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define the authoritative model catalog contract that the service and UI both consume.

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
- request shape metadata used by the API, UI, and tests
- runtime-lane metadata such as GPU requirement and lane identifier

## Rules

- the generated catalog, not a hidden UI-only allowlist, is the source of truth for the browser-visible catalog
- the generated catalog records the selected engine exactly as chosen from the README matrix
- runtime-local caches derive from generated catalog and durable artifact metadata
- switching runtime modes changes the generated catalog and selected engine bindings without changing route structure

## ResultFamily and Result-Surface Mapping

Every README matrix row resolves to a closed `ResultFamily` sum type and a single result-surface
shape — either an inline text payload or a typed object reference into the always-on
`infernix-demo-objects` MinIO bucket. This mapping is the canonical home for the 19-row to
`ResultFamily` and inline-vs-object-ref correspondence; it is consistent with the per-family
result contract in
[../development/testing_strategy.md](../development/testing_strategy.md) and the demo validation
surface in [../development/demo_app_test_plan.md](../development/demo_app_test_plan.md).

The runtime worker invokes the real engine for the selected binding — the Python adapter transform
over a prebuilt host wheel for python-stdio bindings, or the real native runner binary resolved
from a typed `HostConfig` absolute path for native-process-runner bindings — fetches model weights
lazily from the infernix-models MinIO bucket via `adapters.model_cache.get_model_path`, and
publishes a per-family real result: inline text for the LLM and speech families, and a typed object
reference into the infernix-demo-objects MinIO bucket for the source-separation, audio-to-MIDI,
music-transcription, image, video, audio-generation, and OMR artifact families.

`ResultFamily` is resolved from `family` + `artifactType` + `matrixRowId`. The coarse `family`
field collapses source-separation, audio-to-MIDI, and audio-generation under a single `audio`
label, so the fine-grained `ResultFamily` is the authoritative discriminator the catalog, runtime,
and tests share.

### Proto facts

`ResultPayload` already carries `oneof {inline_output, object_ref}` on the wire. This is a
population gap, not a schema gap: `buildPayload` currently hardcodes `objectRef = Nothing`. The
genuinely new proto fields are a non-text **input** object-ref on `InferenceRequest` /
`WorkerRequest` and an object-ref **output** on `WorkerResponse` for the artifact adapters.
Artifact results always use the always-on `infernix-demo-objects` bucket, never the retired
`infernix-runtime` / `infernix-results` buckets.

### Row-to-ResultFamily table

The table maps every row in the README "Comprehensive Model / Format / Engine Matrix" to its
`ResultFamily` and result surface. `inline_output` rows return inline text; `object_ref` rows
return a typed object reference into `infernix-demo-objects`.

| Matrix row (reference model / format) | Workload family | `ResultFamily` | Result surface |
|---|---|---|---|
| Qwen2.5-1.5B-Instruct (HF safetensors) | LLM | `LLM` | `inline_output` |
| Qwen2.5-1.5B-Instruct-AWQ (AWQ) | LLM | `LLM` | `inline_output` |
| TinyLlama-1.1B-Chat-v1.0-GPTQ (GPTQ) | LLM | `LLM` | `inline_output` |
| TinyLlama-1.1B-Chat-v1.0-GGUF (GGUF) | LLM | `LLM` | `inline_output` |
| Qwen1.5-1.8B-Chat-4bit (MLX) | LLM | `LLM` | `inline_output` |
| whisper-small (whisper.cpp / GGML) | Speech transcription | `SpeechTranscription` | `inline_output` |
| faster-whisper-small (CTranslate2) | Speech transcription | `SpeechTranscription` | `inline_output` |
| htdemucs (Demucs) | Source separation | `SourceSeparation` | `object_ref` |
| Open-Unmix | Source separation | `SourceSeparation` | `object_ref` |
| basic-pitch (TensorFlow) | Audio-to-MIDI | `AudioToMidi` | `object_ref` |
| basic-pitch (Core ML) | Audio-to-MIDI | `AudioToMidi` | `object_ref` |
| basic-pitch (ONNX) | Audio-to-MIDI | `AudioToMidi` | `object_ref` |
| MT3 (JAX) | Music transcription | `MusicTranscription` | `object_ref` |
| Omnizart (TensorFlow / Core ML export) | Music transcription | `MusicTranscription` | `object_ref` |
| SDXL Turbo (Diffusers / safetensors) | Image generation | `ImageGeneration` | `object_ref` |
| Apple Stable Diffusion (Core ML) | Image generation | `ImageGeneration` | `object_ref` |
| Wan2.1-T2V-1.3B (Diffusers / safetensors) | Video generation | `VideoGeneration` | `object_ref` |
| bark-small (PyTorch / HF) | Audio generation / TTS | `AudioGeneration` | `object_ref` |
| Audiveris (JVM application) | OMR / notation extraction | `OmrTool` | `object_ref` |

The nine `ResultFamily` constructors — `LLM`, `SpeechTranscription`, `SourceSeparation`,
`AudioToMidi`, `MusicTranscription`, `ImageGeneration`, `VideoGeneration`, `AudioGeneration`, and
`OmrTool` — partition all 19 rows. The two inline-text families (`LLM`, `SpeechTranscription`)
return `inline_output`; the seven artifact families return an `object_ref` into
`infernix-demo-objects`.

### Substrate selection and union coverage

The active generated substrate's catalog records the selected engine per row exactly as chosen from
the README matrix. Rows whose engine cell for the active substrate is `Not recommended` are omitted
from that substrate's catalog, so the per-substrate catalog counts are apple 15, cpu 12, and gpu
16. No single substrate carries all 19 rows. The UNION across the three substrate catalogs covers
every README matrix row, enforced as a mechanical invariant: `allMatrixRowIds` is exported from
`Models.hs`, the union of `catalogForMode` over the three substrates equals 19 rows, and a
README-to-matrix cross-check runs under `infernix lint docs`.

## Cross-References

- [runtime_modes.md](runtime_modes.md)
- [../reference/api_surface.md](../reference/api_surface.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
