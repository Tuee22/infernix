# Apple Silicon Metal Headless Builds

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define the target Apple Silicon Metal and Core ML engine materialization model that
> stays headless without Tart, user keychain state, Xcode UI flows, or per-request toolchain work.

## TL;DR

- Apple inference runs on the host against the real Metal and Core ML runtime.
- Runtime inference and cache misses must not start a VM, unlock a keychain, accept an Xcode
  license, invoke SwiftPM for generated glue, or depend on the offline `metal` compiler.
- Runtime smoke uses public upstream package APIs: MLX performs and synchronizes a real GPU array
  operation, while coremltools reports the compute devices visible to Core ML.
- The repository does not own, embed, generate, or compile native implementation source. Native
  implementation remains inside the upstream MLX, coremltools, and engine packages.
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
1.15 replaced the former Apple validation-wrapper payloads with real runner roots:
`llama-cpp-cli` and `whisper-cpp-cli` copy the manifest-declared Homebrew Metal-capable CLIs into
their candidate payloads and invoke only those artifact-local copies, `ctranslate2-native`
and `onnx-runtime-native` hydrate Apple arm64 venvs, `mlx-native` hydrates `mlx-lm`, `coreml-native`
hydrates Basic Pitch plus Apple Stable Diffusion Core ML support, and `jvm-native` downloads and
installs the Audiveris macOS arm64 app from the pinned release DMG. Missing model payloads or failed
native execution return non-zero; the realness lint forbids reintroducing fabricated Apple runner
output.

Phase 0's no-repo-owned-native-source correction gate closed on 2026-07-27. Sprint 1.20 has deleted
the later-discovered repository-owned Objective-C/C/Metal source strings, their generated
`.h`/`.m`/`.c` files, Clang scripts, and the standalone bridge artifact. The replacement smokes call
public upstream APIs: MLX 0.32.0 has locally executed and synchronized `41 + 1` on
`Device(gpu, 0)`, and coremltools 9.0 has reported Neural Engine, GPU, and CPU devices. The latter is
a runtime/device observation, not model-inference evidence.

The code-side materialization correction is now implemented. Every process operation is selected
from a closed adapter/operation language and runs through an opaque `ProvisioningGrant s` inside an
indexed rank-2 `ProvisioningSession s result`; that facade compiles to the existing all-Haskell
self-exec bounded-command kernel. Candidate roots are hydrated with exact direct pins, relocated,
smoked through their authoritative manifest `--smoke`, assigned exact resolved provenance, hashed
from their actual payload tree, and only then activated by the fsynced sibling transaction.
Synchronous failure, asynchronous cancellation, and recoverable crash residue preserve or restore
the prior complete root.

Sprint 1.20 remains Active. Its fresh final source review, exact-source complete Stage 1, real Apple
rematerialization and installed runtime smokes, and correction-dependent Apple cohort have not yet
passed. The direct local MLX/coremltools observations are preflight only.

All earlier generated-bridge, bridge-load, runtime-compiled-kernel, and Objective-C Core ML smoke
evidence is superseded because it depended on a now-forbidden implementation boundary. Wave L
remains historical routed real-output proof for its then-active catalog; correction-dependent
Apple closure is not claimed until a fresh Apple rerun records it in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).

## Materialization Architecture

The Apple build path separates execution from materialization:

1. Haskell owns model selection, adapter ids, artifact manifests, cache keys, and result
   publication.
2. Upstream packages own their native implementation. The MLX runner selects `mx.gpu`, executes a
   real array operation, evaluates and synchronizes it, and verifies the result. The Core ML runner
   uses coremltools to require at least one available compute device.
3. The exposed `Infernix.Engines.AppleSilicon` facade carries abstract artifact values and the
   whole-plan materializer. The per-artifact installer, artifact transaction, provisioning facade,
   semantic command constructors, and session interpreter are Cabal-hidden modules.
4. `withProvisioningGrant` creates a nominal `ProvisioningGrant s` inside
   `forall s. ProvisioningSession s result`. Only closed Poetry, Python/venv, exact requirement,
   Audiveris image, installed-smoke, and provenance operations can consume it; callers cannot
   construct an executable, argv, raw process specification, or unbounded outcome.
5. The provisioning facade interprets those operations through
   `Infernix.Cluster.Subprocess.runBoundedCommand`. Each operation therefore inherits the explicit
   environment, positive total deadline, bounded capture, target-exec provenance, process-group
   containment, and exhaustive cleanup of the self-exec anchor/supervisor/pin kernel.
6. Each artifact is built entirely under the owned sibling
   `./.data/engines/<adapterId>.tmp`. Package-backed roots use exact direct requirements, then record
   the full resolved Python environment; host-binary roots record the exact version reported by
   their installed smoke; Audiveris records the release version, URL, and fixed DMG SHA-256.
7. A source-specific smoke operation selected by the hidden provisioning language is
   authoritative. It invokes the candidate's exact direct CLI, interpreter/module, or application
   target and must report a nonempty exact `version=` value before the manifest is created. The
   manifest cannot supply executable text or arguments, and metadata-only or post-activation help
   checks cannot mint a valid artifact.
8. Python venvs use copied launchers and disable bytecode generation. Activation scripts,
   console-script shebangs, and `pyvenv.cfg` are rewritten to the final sibling path before smoke;
   any remaining candidate-root byte sequence in a regular payload file rejects materialization.
9. The deterministic payload digest covers sorted relative paths, file types, modes, regular-file
   bytes, and safe relative symlink targets. It excludes only `engine-artifact.json`, avoiding a
   circular digest while binding all runtime payload bytes.
10. The complete candidate tree and parent directory are fsynced around sibling renames. The prior
    root remains as `.previous` until the replacement validates at its final path. Failure or
    cancellation rolls back; startup reconciliation selects only an exact complete final,
    `.previous`, or otherwise unambiguous `.tmp` root and fails closed on ambiguous residue.
11. Runtime inference consumes already materialized artifacts and never installs toolchains or
   starts virtualization on a request path.

No repository-owned native bridge is permitted. Direct FFI, inline native source, generated native
source, direct compiler scripts, and relocation into another implementation language are not
alternative implementations of this lane.

## Prerequisites

| Prerequisite | Required for | Verification |
|---|---|---|
| Upstream MLX package and Metal runtime | MLX execution | Select `mx.gpu`, evaluate and synchronize a real operation, and verify its value. |
| Upstream coremltools package and Core ML runtime | Core ML observation and execution | Require a nonempty `MLModel.get_available_compute_devices()` result; real catalog inference remains separate cohort evidence. |
| Materialized engine package or binary | Adapter execution | Run the hidden catalog's direct target smoke from its final install root and revalidate the target observation. |

The core runtime path does not require Tart, a repository bridge, full Xcode, the offline `metal`
compiler, Clang, or Swift during inference or materialization.

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
| `resolvedProvenance` | Exact resolved package, interpreter, release-source, checksum, and authoritative-smoke records. |
| `recipeFingerprint` | Versioned fingerprint of the closed materialization recipe. |
| `digest` | Content digest of the immutable payload. |
| `minioObjectKey` | Optional content-addressed MinIO key for reusable payloads. |
| `localInstallRoot` | Local materialization root such as `./.data/engines/<adapterId>/`. |
| `targetContractFingerprint` | Fingerprint of the hidden direct-target catalog entry and invocation-prefix shape. |
| `imageTargetEvidence` | Linux-only exact executable and immutable-closure identities and digests; Apple records `null` because the complete target closure is inside the payload digest. |

The current materializer writes this manifest only after candidate hydration and authoritative
smoke. Executable paths and argv are never decoded from it. Python provenance is parsed from the
exact frozen environment, the interpreter version is queried from the candidate venv, host tools
derive their engine/runtime versions from real smoke output, and the copied
`llama-cli`/`whisper-cli` bytes carry their own SHA-256 provenance within the whole-tree content
digest. Audiveris is accepted only after the pinned
`sha256:727c46b4ca4766349be1f582b67cc5aa0d7306113dcf4a18be169d75959f4288`
release image is observed. A mount is treated as live only when its kernel device id differs from
the parent candidate filesystem; the bounded detach operation runs in the primary-preserving
release path.

Apple integration and e2e real-output proof for the then-active Apple catalog closed historically
in Wave L. A post-correction Apple rerun is still required before claiming current materialization
or full-suite proof.

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

- the installed upstream MLX package executes, evaluates, and synchronizes a real GPU operation;
- the installed upstream coremltools package observes at least one Core ML compute device, while
  routed Core ML model inference is validated separately;
- materialized trees and repository scans contain no owned native source, embedded equivalent, or
  direct native-compiler path;
- validation still passes when `tart` is absent or unusable;
- validation still passes without an unlocked `login.keychain-db`;
- validation does not require `xcrun`, Clang, the offline `metal` compiler, or direct FFI;
- a materialized engine artifact writes a manifest, passes its smoke command, and loads from
  `./.data/engines/<adapterId>/`;
- request-time inference never invokes Tart, SwiftPM, Xcode, or package installation;
- failed materialization leaves no partial final install root and is retryable.

The focused `infernix-artifact-transaction`, full-materializer, and compile-boundary suites are
being expanded against the active Sprint 1.20 correction. Their earlier inventories and results
are superseded and nonreusable. `appleArtifactProvisioningViolations` continues to enforce that
artifact modules cannot import `System.Process`, use raw spawn/wait primitives, delegate to the
legacy unbounded Poetry helpers, or bypass the provisioning facade to call the bounded kernel
directly.

Sprint 1.20 stays Active until the final reviewed source identity passes those focused gates, the
complete Stage 1 gate, and real Apple
rematerialization, installed upstream smokes, runtime loading, and the selected cohort are green
against that same source.

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [host_tools_manifest.md](host_tools_manifest.md)
- [object_storage.md](object_storage.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
- [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)
- [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
