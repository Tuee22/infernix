# Apple Silicon Metal Headless Builds

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define the target Apple Silicon Metal and Core ML engine materialization model that
> stays headless without Tart, user keychain state, Xcode UI flows, or per-request toolchain work.

## TL;DR

- Apple inference runs on the host against the real Metal and Core ML runtime.
- Runtime inference and cache misses must not start a VM, unlock a keychain, accept an Xcode
  license, invoke SwiftPM for generated glue, or depend on the offline `metal` compiler.
- Metal source compilation uses a fixed host bridge that calls the OS Metal framework runtime
  compiler, not a per-artifact Tart VM.
- Core ML and native runner artifacts are materialized through typed, content-addressed engine
  manifests under `./.data/engines/<adapterId>/`.
- The former `tart` / `hostTart` / `AppleTart` implementation has been removed from the current
  host-tool schema and prerequisite path. `infernix internal materialize-metal-engines` is the
  retained helper name, but it now writes typed headless engine-artifact manifests.

## Current Status

Phase 1 Sprint 1.14 completed the machine-independent cleanup: `HostConfig.hostTart`,
`HostTool.HostTart`, and the `AppleTart` prerequisite are gone; the generated Linux host manifest no
longer carries a `tart` field; and `infernix internal materialize-metal-engines` writes
`engine-artifact.json` manifests under `./.data/engines/<adapterId>/` without invoking Tart. Sprint
1.15 replaces the former Apple validation-wrapper payloads with real runner roots:
`llama-cpp-cli` and `whisper-cpp-cli` delegate to the Homebrew Metal-capable CLIs, `ctranslate2-native`
and `onnx-runtime-native` hydrate Apple arm64 venvs, `mlx-native` hydrates `mlx-lm`, `coreml-native`
hydrates Basic Pitch plus Apple Stable Diffusion Core ML support, and `jvm-native` downloads and
installs the Audiveris macOS arm64 app from the pinned release DMG. Missing model payloads or failed
native execution return non-zero; the realness lint forbids reintroducing fabricated Apple runner
output.

The current Apple host evidence builds the host binaries, materializes `apple-silicon`, runs
`infernix internal materialize-metal-engines`, proves the installed Metal bridge smoke
(`Metal runtime probe passed on Apple M1`) and the installed runner smokes for Core ML, CTranslate2,
MLX, ONNX Runtime, and Audiveris, and verifies the Core ML venv imports both Basic Pitch and Apple's
Stable Diffusion pipeline. Wave L closed routed real-output proof for its then-active Apple catalog;
post-replacement Apple proof for the 2026-06-30 MT3 rows is not claimed until a separate Apple rerun
records it in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).

## Target Architecture

The target Apple build path separates execution from materialization:

1. Haskell owns model selection, adapter ids, artifact manifests, cache keys, and result
   publication.
2. A fixed Apple host bridge owns Metal framework calls such as
   `MTLCreateSystemDefaultDevice` and runtime Metal source compilation through
   `MTLDevice.makeLibrary(source:options:)`.
3. Engine artifacts are written under `./.data/engines/<adapterId>/` by a controlled
   materialization command and published with a manifest that records source identity, platform
   identity, digest, and the intended smoke command.
4. Runtime inference consumes already materialized artifacts and never installs toolchains or
   starts virtualization on a request path.

The fixed bridge may be implemented as a small Objective-C/C `.dylib` with a stable C ABI or as a
direct Haskell Objective-C runtime bridge. The pragmatic first implementation is the C ABI bridge
because it isolates Metal framework details from generated model artifacts.

## Prerequisites

| Prerequisite | Required for | Verification |
|---|---|---|
| `apple.metal-runtime` | Core execution | Probe `MTLCreateSystemDefaultDevice` and dispatch a tiny runtime-compiled Metal kernel. |
| `apple.metal-bridge` | Core execution | Build or verify the fixed bridge, then load it and call a probe symbol. |
| `apple.macos-sdk` | Source-building the bridge or optional Swift helpers | Verify an SDK path through the typed host-tool boundary. |
| `apple.swiftc` | Optional Swift helper modules only | Compile and load a Swift + Metal probe with an explicit SDK. |

The core runtime path requires the Metal runtime and bridge. It does not require Tart, full Xcode,
the offline `metal` compiler, or Swift during inference.

## Engine Artifact Manifest

Every materialized engine artifact should have a typed manifest with at least these fields:

| Field | Purpose |
|---|---|
| `adapterId` | Stable adapter binding such as `llama-cpp-cli`, `coreml-native`, or `mlx-native`. |
| `engineName` | Human-readable engine family. |
| `substrate` | `apple-silicon`, `linux-cpu`, or `linux-gpu`. |
| `architecture` | Native host or image architecture. |
| `artifactKind` | `wheelhouse`, `venv`, `native-binary`, `native-framework`, `coreml-model`, `jvm-tool`, or `container-layer`. |
| `sourceRef` | Upstream source, release, conversion tool, or model artifact reference. |
| `engineVersion` | Engine or conversion-tool version. |
| `pythonVersion` | Required only for Python artifacts. |
| `runtimeVersion` | Metal, Core ML, CUDA, JVM, or other relevant runtime version. |
| `digest` | Content digest of the immutable payload. |
| `minioObjectKey` | Optional content-addressed MinIO key for reusable payloads. |
| `localInstallRoot` | Local materialization root such as `./.data/engines/<adapterId>/`. |
| `entrypoint` | Runner binary, Python entrypoint, bridge symbol, or JVM invocation. |
| `smokeCommand` | Minimal validation command that proves the artifact can load. |

The current materializer writes the manifest through a temporary directory, verifies the manifest
contract, smoke-loads materialized payloads before install where possible, hydrates package-backed
runner roots after the atomic install, and then re-smokes the installed roots. Apple integration and
e2e real-output proof for the then-active Apple catalog closed in Wave L; the materialization lane
itself is now real-runner code-side closed. A post-replacement Apple rerun is required before
claiming Apple full-suite proof for the 2026-06-30 MT3 rows.

## Storage Boundary

- Harbor owns container images and heavyweight Linux runtime bases.
- MinIO may store immutable, content-addressed engine payloads that are expensive to reproduce.
- `infernix-models` remains the model-weight bucket; engine software and model weights are
  separate artifact classes.
- CUDA frameworks are image-owned or pre-materialized by controlled build lanes, never installed
  on a user request.
- Apple host artifacts are local under `./.data/engines/<adapterId>/` and may later reuse MinIO
  content-addressed payloads when the payload is portable enough to cache.

## Validation

The Apple headless materialization lane closes only when:

- a host probe compiles and dispatches a Metal kernel through the runtime Metal framework;
- validation still passes when `tart` is absent or unusable;
- validation still passes without an unlocked `login.keychain-db`;
- validation does not require `xcrun -find metal` to succeed;
- a materialized engine artifact writes a manifest, passes its smoke command, and loads from
  `./.data/engines/<adapterId>/`;
- request-time inference never invokes Tart, SwiftPM, Xcode, or package installation;
- failed materialization leaves no partial final install root and is retryable.

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [host_tools_manifest.md](host_tools_manifest.md)
- [object_storage.md](object_storage.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
- [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)
- [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
