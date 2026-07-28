# Build Artifacts

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define where generated artifacts live and keep them out of tracked source paths.

## TL;DR

- Host-native builds write repo-local outputs under `./.build/`; supported outer-container flows
  keep build artifacts inside the launcher image overlay and write durable repo-local state under
  `./.data/`.
- Native engine artifacts and engine install roots live under `./.data/engines/<adapterId>/`,
  never `./.build/`; the Haskell binaries still build host-native to `./.build/`.
- Apple Metal/Core ML engine materialization uses a Tart-free headless host lane and typed
  engine-artifact manifests; the old `hostTart` / `AppleTart` helper path is removed. All
  provisioning and installed-smoke processes run through the opaque bounded provisioning region,
  and a root becomes visible only after candidate hydration, smoke, provenance capture, actual
  payload hashing, and the fsynced sibling activation transaction.
- Generated frontend contracts live only under `web/src/Generated/`, and generated browser bundles
  live under `web/dist/`.
- Runtime inference results reload only from protobuf-backed `./.data/runtime/results/*.pb`
  records.
- Operator config is not a build artifact: `infernix init` owns the gitignored repo-root
  `./infernix.dhall` and `./infernix-host.dhall`, while `infernix test init` owns
  `./infernix.test.dhall`.

## Current Status

The worktree follows the supported artifact layout directly: the host path stages
`./.build/infernix`, the Linux substrate images own
`/usr/local/bin/infernix*` and image-local outer-container build state, generated frontend
contracts stay under `web/src/Generated/`, and runtime result or cache-manifest state uses
protobuf-backed `*.pb` files.
Kind and `nvkind` cluster create or delete uses transient scratch kubeconfig state under the
execution context's temp directory, and only the published repo-local kubeconfig paths are part
of the supported artifact contract.

## Build Roots

- the repo-local operator binary lives at `./.build/infernix`
- the supported Apple host bootstrap ultimately calls
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`,
  which lets cabal use its natural `dist-newstyle` builddir at the project root while installing
  the launcher binaries under `./.build/`
- on the supported outer-container path, cabal-home and the cabal builddir live at the toolchain's
  natural in-image locations (`/root/.cabal/`, `dist-newstyle/`); they are not bind-mounted to the
  host
- on the outer-container path, the baked launcher binaries remain `/usr/local/bin/infernix` and
  `/usr/local/bin/infernix-demo`; the substrate image uses `tini` as its `ENTRYPOINT` for clean
  signal handling and zombie reaping
- on the outer-container path, the Helm dependency archive cache is baked into
  `/opt/infernix/chart/charts/`, and `/workspace/chart/charts` links to that image-local cache so
  Helm uses local archives without a host bind mount
- the substrate image captures the sorted, pruned source snapshot at
  `/opt/infernix/source-snapshot-files.txt`, which stays in the image overlay where git-less
  `infernix lint files` runs can read it
- `cluster up` publishes `./.build/infernix.kubeconfig` on the host path after Kind create or
  delete uses a transient host-local scratch kubeconfig
- `cluster up` publishes `./.data/runtime/infernix.kubeconfig` on the outer-container path after
  Kind or `nvkind` create or delete uses a transient launcher-local scratch kubeconfig under the
  container temp directory
- the active operator runtime config lives at repo-root `./infernix.dhall` in both execution
  contexts; `./infernix-host.dhall` is the operator host manifest and
  `./infernix.test.dhall` is the test-harness input
- `cluster up` writes `./.data/runtime/publication.json` as the publication inventory consumed by
  routed status surfaces
- the web build stages `web/src/Generated/Contracts.purs`, written by
  `infernix internal generate-purs-contracts`
- `spago bundle --module Main --outfile dist/app.js --platform browser --bundle-type app`
  produces the static demo bundle in `web/dist/`
- inference-result reloads use `./.data/runtime/results/*.pb`
- cache manifests sit beside the cached weights at
  `./.data/runtime/model-cache/<runtime-mode>/<model-id>/manifest.pb`
- `ensurePoetryProjectReady` regenerates Python protobuf stubs under `tools/generated_proto/` when
  they are missing

## Native Engine Artifacts

Native engine artifacts and install roots live under `./.data/engines/<adapterId>/` (the existing
engine-install root), never `./.build/`. The `infernix` and `infernix-demo` Haskell binaries still
build host-native to `./.build/`; engine payloads are separate runtime artifacts.

On `apple-silicon`, the supported target is the Tart-free headless materialization model in
[apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md): Core ML and native
runners materialize into typed engine roots; upstream MLX executes and synchronizes the GPU smoke,
and coremltools owns the compute-device observation. The repository emits or compiles no native
implementation source, and request-time inference never starts a VM, unlocks a keychain, invokes
Xcode UI flows, or installs toolchains. MLX, ONNX Runtime,
CTranslate2, PyTorch MPS paths, and Audiveris continue to prefer prebuilt host wheels or binaries
when available.

Current implementation note: Phase 1 Sprint 1.14 removed the Sprint 1.13 `hostTart` host-manifest
field, the `AppleTart` prerequisite, and the Tart VM argument builders. The retained
`infernix internal materialize-metal-engines` helper writes a typed `engine-artifact.json` manifest
for each allowlisted Apple adapter into its final engine root. Sprint 1.20 removed the standalone
bridge root, embedded native source, generated native files, and compiler scripts. Sprint 1.15
replaced the former Apple
validation-wrapper roots with real native runners: llama.cpp/whisper.cpp delegate to host CLIs,
CTranslate2/ONNX/MLX/Core ML hydrate per-engine venvs, and Audiveris installs the pinned macOS
arm64 app. The correction's focused direct upstream MLX and coremltools preflights are green, but
fresh installed-root and routed Apple evidence remains open. Historical Apple integration evidence
from the prior lane validates pinned Apple
host-engine `Exclusive` duplicate rejection, proves same-machine Apple `Shared` subscription
coexistence, and covers Apple production `demo_ui = false` assertions. It also proves the
source-fingerprint rebuild/reuse path by
rebuilding the changed repo-owned image once before reusing the stamped image on later edge-port
validation cycles. Follow-up plain-progress probing of the earlier long Docker interval showed
active Cabal dependency compilation, image export, Harbor push, and Helm/Pulsar readiness waits
rather than a Docker daemon deadlock, and current source adds source-fingerprint image reuse plus
Dockerfile dependency caching for that host-native Apple cluster-image path. The Apple-only cohort
residual is the remaining routed real-output e2e/all evidence recorded in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).

Every materialized engine root carries a typed manifest recording `adapterId`, `engineName`,
`substrate`, `architecture`, `artifactKind`, `sourceRef`, exact engine/Python/runtime versions,
`resolvedProvenance`, the current closed-recipe fingerprint, the actual payload digest, optional
MinIO object key, local install root, and the direct-target contract fingerprint. Linux manifests
also record exact descriptor-derived executable and immutable-closure evidence. Manifest text never
selects an executable or argument. Apple materialization hydrates its owned `.tmp` sibling,
relocates an embedded venv to the final-root identity, executes a source-specific direct smoke under
the rank-2 bounded provisioning session, records exact resolved provenance, and deterministically
hashes the sorted payload tree before writing the manifest. Any residual candidate-root bytes
reject the venv. Audiveris download and mount/copy operations use the same closed bounded language;
the fixed release checksum gates the cache and kernel device identity gates detach cleanup.

Activation fsyncs the complete candidate and parent directory around sibling renames, retains the
prior exact root through final-path revalidation, rolls back on synchronous failure or asynchronous
cancellation, and reconciles only unambiguous complete `.previous` / `.tmp` crash residue. The
focused transaction, full-materializer, and compile-boundary suites are being expanded with the
active Sprint 1.20 correction; no earlier inventory or result closes the current source. Fresh final
review, exact-source complete Stage 1, and real Apple rematerialization/runtime plus paired
`linux-cpu` cohort evidence remain. Linux native roots exercise runtime-backed
payload smoke over the image-baked native layer, Apple native roots exercise real runner smoke, and
Wave L closed the routed full-suite Apple real-output gate for its then-active catalog. Wave K closed
the Linux routed full-suite real-output delivery that consumes the Linux payloads through the service
path for its then-active catalog; Wave P closed proof for post-replacement MT3 rows added on 2026-06-30.

## Linux Native Engine Artifacts

On `linux-cpu` and `linux-gpu`, native-process-runner artifacts are image-owned. The worker checks
the repo data root first for parity with host-native execution and then resolves Linux-baked
artifact metadata under `/opt/infernix/engines/<adapterId>/`. The actual executable, interpreter
and module, or JRE and classpath is selected directly from the immutable image by a hidden typed
catalog. The mounted `/workspace/.data` tree remains
durable operator state and may be an `emptyDir` inside engine pods, so Linux native runners must not
depend on image content under `/workspace/.data/engines` surviving a pod mount.

`infernix internal materialize-linux-native-engines` is the image-build helper for these roots. It
writes typed `engine-artifact.json` manifests, observes each direct image target and its immutable
runtime closure through bounded descriptor-based traversal, executes a source-specific smoke, and
installs the result under
`/opt/infernix/engines/<adapterId>/` through the same exact-payload artifact transaction. The
validated sibling candidate is fsynced, the existing root is moved to `.previous`, and the new root
is renamed and revalidated before the rollback root is retired. A filesystem that cannot provide
those sibling-rename semantics fails closed; the installer does not fall back to destructive
overlay replacement. Strict image smoke requires the baked llama.cpp and whisper.cpp executables
selected for the image architecture (`linux/amd64` or `linux/arm64`), Basic Pitch ONNX model, ONNX
Runtime/CTranslate2/faster-whisper Python environment, and Audiveris app jars plus the
image-architecture Temurin 25 JRE to be present and loadable. Runtime compiles a distinct
target-specific invocation for each CLI, Python, and JVM family. Artifact-producing invocations use
an owned output directory, descriptor-bounded output discovery, and Haskell-owned credentialed
MinIO upload. The reopened Phases 4/6 own fresh full routed real-output delivery for this corrected
direct-target topology. Historical Wave K and Wave P results do not close it.

## Generated Demo Config Publication

The runtime config is a typed Dhall record at repo-root `./infernix.dhall`; the schema is reflected from the
substrate decoder type (`infernix internal dhall-schema substrate`) and decoded in-process by the
`dhall` Haskell library. Cluster pods
that consume the file link the same library through the in-cluster `infernix` binary.

- operators create `./infernix.dhall` and `./infernix-host.dhall` only through `infernix init`;
  ordinary config-dependent commands validate that file and fail fast with the init to run when it
  is absent
- `infernix test init` creates `./infernix.test.dhall`; the harness reserves the cluster slot, then
  generates and owns `./infernix.dhall` for the duration of integration, E2E, or aggregate runs
- `cluster up` mirrors the cluster-role substrate payload under
  `./.data/runtime/configmaps/infernix-demo-config/` and publishes it into
  `ConfigMap/infernix-demo-config` on the real cluster path; on Apple this cluster-role payload is
  rendered from the initialized runtime metadata and `demo_ui` setting rather than copied verbatim
- in cluster-resident execution contexts, the ConfigMap-backed file is a deployment mirror of the
  initialized runtime config, not an operator-authoritative config location
- the cluster pod's ConfigMap-backed substrate mount path is
  `/opt/build/infernix-substrate.dhall` (chart `demoConfig.mountPath=/opt/build`,
  `fileName=infernix-substrate.dhall`); the separate Phase-8 cluster-wiring `ClusterConfig`
  ConfigMap mounts at `/opt/infernix/cluster.dhall` (subPath `cluster.dhall`)

## Rules

- repo-owned shell is limited to the `bootstrap/*.sh` stage-0 host bootstrap entrypoints; build
  and launcher ownership stays with the direct `cabal`, `docker compose`, and `infernix`
  surfaces, and shell lifecycle commands preserve `./.build/`, `./.data/`, host-level container
  builds, Apple host binaries, and installed Docker or CUDA prerequisites
- generated `.dhall` files are gitignored and never tracked; operator config lives at the repo root,
  not under the build root
- `cluster up`, `service`, and other config-dependent entrypoints validate the initialized
  `./infernix.dhall` and fail fast naming `infernix init` when it is absent; the test harness names
  `infernix test init` when `./infernix.test.dhall` is absent
- kubeconfig output is repo-local and execution-context-specific: Apple host mode publishes
  `./.build/infernix.kubeconfig`, while Linux outer-container mode publishes the durable
  `./.data/runtime/infernix.kubeconfig`; Kind and `nvkind` cluster create or delete uses a
  transient scratch kubeconfig outside the repo tree and may clean stale repo-local `*.lock`
  artifacts automatically
- `infernix lint files` uses tracked files from `.git` when VCS metadata is present and otherwise
  uses `/opt/infernix/source-snapshot-files.txt` baked into the substrate image on git-less Linux
  image runs
- publication state lives under `./.data/runtime/` and is regenerated by `cluster up`,
  `cluster down`, or publication-surface refresh
- generated PureScript contract modules stage under `web/src/Generated/` and the `spago bundle`
  output lives in `web/dist/`
- runtime result and cache-manifest reload paths are protobuf-backed `*.pb` files only; supported
  flows do not read legacy `*.state` compatibility files
- generated web build output lives under `web/dist/`; Playwright validation artifacts use
  Playwright default output directories such as `test-results/` and `playwright-report/` under the
  active runner working tree when emitted, and compose-run artifacts are container-local unless
  explicitly bind-mounted
- engine-adapter Python builds use Poetry against the shared `python/` project; outside the
  cluster, `poetry install --directory python` materializes a repo-local adapter virtual
  environment at `python/.venv/`, and Linux substrate image builds run the same shared install
- the supported web build runs on Node.js 22.5+ on both the host and Linux substrate-image paths
- `.gitignore` and `.dockerignore` mirror the generated-artifact ignore set: Poetry lockfiles,
  generated protobuf stubs, Python bytecode, mypy and ruff caches, `web/spago.lock`,
  `web/package-lock.json`, `web/src/Generated/`, `web/dist/`, `web/output/`, and
  `python/.venv/` are not tracked

## Validation

- `infernix docs check` fails if this governed artifact document loses its required structure or
  metadata contract.
- `infernix test unit` covers protobuf-backed result reloads, protobuf-backed cache-manifest
  handling, and PureScript contract generation to `web/src/Generated/Contracts.purs`.
- `infernix lint files` fails if the implemented tracked generated-source set returns to tracked
  paths, including generated protobuf stubs, generated PureScript contracts, Python bytecode,
  Poetry or Spago lockfiles, and mypy or ruff cache directories.
- `git ls-files` remains the direct audit surface for ignored derived outputs such as
  `web/package-lock.json`, `web/dist/`, `web/output/`, and `python/.venv/`.

## Cross-References

- [docker_policy.md](docker_policy.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
