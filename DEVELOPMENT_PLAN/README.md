# Infernix Development Plan

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md)

> **Purpose**: Provide the single execution-ordered development plan for `infernix`, including
> phase status, repository-shape decisions, validation gates, and documentation obligations.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Sprint 6.44 residual closure: bounded descriptor space and the CUDA breach fixture (2026-08-03)

Execution resumed in numerical order. Phases 1, 2, and 4 are each `Active — Validation Only` with an
**Apple-hardware** residual and the active development host is a CUDA Linux box (RTX 5090), so none of
the three had an item that could be worked here; their rows say so rather than implying progress.
Phase 6 was the actionable one.

**The `close_fds` finding is resolved, and it was platform-wide rather than Sprint 6.44's alone.**
The prior session root-caused the second cohort failure to the pre-`exec` descriptor walk that
`close_fds = True` performs, left it explicitly unfixed as a doctrine decision, and named the open
question: whether the capped-engine and bounded-command kernels pay the same cost. They do. The
question was settled by measurement, not inference — a spawn through the same public
`System.Process` API inside a container started with a pod's own `--ulimit nofile=1073741816` takes
**313 s**, where the previous figure was a 4.5-minute extrapolation from 524288. The same spawn with
`close_fds = False` is 0.8 ms at every limit, so the entire cost is the walk.

Reading the `process-1.6.26.1` source settled the mechanism and the remedy together: `close_fds` is a
configuration `posix_spawn` cannot express, so the spawn always falls back to fork/exec and the child
runs `for (i = 3; i < sysconf(_SC_OPEN_MAX); i++) close(i)` — linear in a soft `RLIMIT_NOFILE` the
process *inherits* rather than chooses. So the correction bounds the resource instead of weakening
the isolation, which is what the prior session correctly declined to do. `Infernix.DescriptorSpace`
lowers the soft limit to a 16384 ceiling as the first action of every process image, before the
internal self-exec dispatch and before any descriptor is opened; because a process cannot open a
descriptor at or above its own soft limit, the child's walk still closes the **entire** descriptor
space and `close_fds` keeps its exact meaning. The ceiling was chosen from the measured table, not
picked: 16384 costs 4.9 ms, which the observer's 50 ms cadence absorbs alongside a ~27 ms
`nvidia-smi` query, while 65536 costs 17.5 ms and does not. Three guards keep it: a fail-closed
observation in each of the three kernels that turns an unbounded image into a **named refusal**
instead of a stall, a new `unboundedDescriptorSpawnViolations` lint rule, and unit assertions
covering the bound, the refusal, re-establishment, and the never-widen property.

The end-to-end evidence is the eight self-exec observer kernel tests completing in **3.7 s inside a
container at the pod's real 1073741816 limit**, against 3.2 s on the host — the same limit at which
one spawn previously cost 313 s.

**Sprint 6.44's CUDA ceiling-breach deliverable is closed.** It was the item the prior session
recorded as covered by no suite and un-closable by the cohort. `runNvidiaVramBreachAssertions` now
holds a real device allocation through `libcuda.so.1` driver-API calls under `ctypes` — no compiler,
no repo-owned native source — and drives the existing `nvidiaWatchdogOutcomeForTest` seam exactly as
Phase 4 Sprint 4.32 drives its Linux CPU counterpart. Its ceilings come from measurement: a CUDA
context is itself a 496 MiB device allocation before any `cuMemAlloc`, so ceilings were placed clear
of that floor in both directions, and the assertion was negative-tested to prove it is live rather
than vacuous.

**The raw-spawn exemption decision is made rather than deferred to a successor sprint, and the
exemption set is down from nine rows to seven.** The decision is that the bounded-command kernel's
closed operand catalog applies wherever the operand vocabulary *is* closed, and that exactly two
situations fall outside it: an operator's own passthrough invocation, and a spawn that must run
before the host manifest exists. Neither is a licence to be unbounded, so every retained non-daemon
surface gained a required deadline. Two of the sprint's premises turned out to be wrong on
inspection: `HostTools.hs` was not a generic runner — three of its five raw spawns had **no callers
at all** and are deleted, leaving two fixed-argv pre-manifest probes — and `Workflow.hs`'s generic
command runner was generic only on paper, since its sole caller passed a renderer-owned literal.
`Lint/Files.hs` and `Workflow.hs` are fully migrated to closed bounded commands that reuse existing
policy-plan fields, so no operator's generated host manifest is invalidated.

Item 4 (narrowing the engine-spawn gate) is resolved honestly as **not narrowable by a smaller
list**: both rules match the same tokens on the same lines, so separating them needs a stronger
detector rather than a shorter exemption list. No narrowing is claimed.

All three corrections are source changes, so Sprint 6.44's cohort needs an exact-source image rebuild
before it counts; the cohort is now the sprint's only remaining item. The complete machine-independent
gate set is GREEN on this source: `cabal build all --enable-tests` under `-Wall -Werror`,
`infernix-haskell-style` (`haskell-style-check: ok`), and `infernix-unit`.

## Phases 6 and 8 code-side closure (2026-08-02)

Execution resumed in numerical order over the open phases. Phases 1, 2, and 4 are each
`Active — Validation Only` with an **Apple-hardware** residual, and the active development host is a
CUDA Linux box (RTX 5090); none of those three has a code-side item left, so no work was possible on
them here and their status rows say so rather than implying progress. Phases 6 and 8 were the
actionable ones.

**Phase 6 Sprint 6.44 is code-side closed.** The starting condition was more serious than the sprint
text implied: `linux-gpu` could not compile an execution plan *at all*. `runtimeBudgetErrors`
returned `GpuDualResourceBudgetRequired` for every `LinuxGpu` config regardless of its budget,
`compileResources` had no `LinuxGpu` arm, `CompiledGpuResources` was constructed only in a test
fixture, `Infernix.Runtime.Enforcer` hardcoded NVIDIA availability to `False`, and
`watchdogForGrant` returned a hard `Left`. The lane was fail-closed end to end. It now compiles: a
device-using model carries a pod-RAM and an NVIDIA-VRAM grant admitted independently from a
`DualEnforcedBudget`, and runs under one watchdog per grant. A `linux-gpu` model that does *not* use
the device stays on the resident-set lane alone.

Two design decisions were made from measurement rather than assumption. First, whether per-process
VRAM attribution is even sound inside a pod: a CUDA process holding 1008 MiB on the host was
**invisible** to `nvidia-smi --query-compute-apps` from inside a container, while the same allocation
made *inside* a container was reported with the container-local pid. NVML resolves compute contexts
in the reading process's PID namespace and omits what it cannot resolve, so an engine pod observes
exactly its own namespace — which is the correct attribution, and the opposite of what a naive
host-pid design would have produced. Second, the observer needs no process discovery of its own,
because group membership is already available subprocess-free from `/proc/<pid>/stat`; the NVIDIA
lane therefore spawns one fixed command per sample instead of the Darwin lane's per-member pair.

`DarwinObserver` is generalized to `FixedObserver`. Duplicating a second bounded observer kernel was
rejected — this repository's review history is largely one-pattern-N-sites defects — and the
spawn/drain/deadline/cleanup kernel plus its eight self-exec kernel tests were already
platform-neutral and already running on Linux. The module now owns both closed catalogs behind an
unexported spec. `nvidia-smi` is pinned as a literal absolute path rather than resolved from the
host-tools manifest: an enforcement observer that follows a configurable path is redirectable.

The same sprint shrank the raw-spawn exemption set from twelve rows to nine. Both raw spawns in
`Runtime/Pulsar.hs` became closed bounded commands — including a Poetry-driven upstream model
download that had **no deadline at all** on the coordinator's startup path, the sharpest remaining
instance of the hang class the bounded-command doctrine exists to prevent — and a real gate hole was
closed: whole-token matching meant `withCreateProcess` never matched `createProcess`, so a
non-exempt module could bracket an unbounded spawn in plain sight. Five exemptions remain and are
named individually with the design decision each needs, rather than carried as an unqualified
residual.

**Phase 8 Sprint 8.9 is code-side closed, and its premise is corrected.** The sprint was written
against a flat text-tagged budget that no longer existed — the union and its per-arm payload records
had already landed. Rather than claim retired work, the plan records what was actually left: the
third `DualEnforced` arm Sprint 6.44 needed, one shared rendered union type replacing a literal
duplicated per arm, an assertion that pins the rendered payload against the alternatives the
reflected decoder expects (renderer/decoder drift was previously undetectable by anything), a
targeted migration diagnostic that names a retired payload's shape and the regenerating command
instead of surfacing a bare Dhall type error, and removal of the dead `legacyDhall` decoder branch.
The rest of the generated wire — text enums, `Integer`-vs-`Natural`, the zero-filled `edgePort`, and
the still-flat Aeson `kind` encoding the web UI reads — is now named explicitly as follow-on work.

**Sprint 6.43's final cross-phase review reopened scope rather than closing it.** Four independent
adversarial lenses raised seven findings; each was attacked from two further angles. Three were
refuted, four confirmed. One was fixed here: the `linux-gpu` engine-Deployment rotation ran outside
`withPersistedClusterMutation`, so a kill mid-rotation left the persisted state reading
`ClusterReady` while engine Deployments sat scaled to zero. Three opened **Sprint 6.45**, including a
High cross-checkout defect — the Kind cluster name is machine-global while the lifecycle lock,
reservation, and persisted state are repo-local, so a second checkout can authorize teardown against
the operator's live inventory using its own leftover state and delete the operator's cluster. The
review also disproved a documented by-construction claim: `ClusterTeardownAuthority` type-indexes the
lock region but not the owner, so "tearing down an `OperatorOwned` cluster does not typecheck" was an
over-claim; the refusal is a value comparison under the held lease. `CLAUDE.md`, `AGENTS.md`, and
`managed_state_transitions.md` now say what the code does, with the type-level work scheduled.

The complete machine-independent gate set is GREEN on this source: `cabal build all --enable-tests`
under `-Wall -Werror`, `infernix-unit`, `infernix-execution-plan-internal`,
`infernix-capped-engine-observer`, `infernix-compile-fail` (6 positive / 81 negative),
`infernix-haskell-style` including the realness rules, and `lint files|chart|proto|docs` plus
`docs check`. The live NVIDIA assertions ran against the real device on this host.

One further check changed a conclusion rather than confirming it, and is recorded here because it
would otherwise have become a false closure. Sprint 6.44's headline validation item — the adversarial
CUDA ceiling breach — was initially written as "owned by the `linux-gpu` cohort". It is not, and the
cohort cannot own it as things stand: `test/integration/Spec.hs` has no runtime ceiling-breach case
at all (every row is classified as compiler-unavailable or completed, and a breach of an *admitted*
ceiling is neither), and the unit suite's live NVIDIA assertions run in the outer launcher container,
which `compose.yaml` reserves no GPU for — consistent with the standing rule that the outer
control-plane container does not require the NVIDIA runtime. Inside the cohort those assertions skip
loudly. So a green `./bootstrap/linux-gpu.sh test` would **not** prove that deliverable. Sprint 6.44
and Wave Z both now say so, and Sprint 6.44's remaining work names the shape that would close it: an
integration case running inside the engine pod, where the device is.

## Active Phase 1 validation update (2026-08-02)

Sprint 1.20 is code-side closed, and its exact-source `linux-cpu` full-suite cohort is GREEN on
`sha256:51292f6f3d98560b383a4ab5cc8a1807aa5388fa5cc0ba8c99b305d90ba9ff67`.
Phase 1 remains Active only for validation-only Wave Y Apple accelerator evidence. Under the
development-plan standards' two-axis rule, Phase 2 code-side closure may now proceed in numerical
order while that hardware queue item remains open. The supported
`linux-cpu` launcher image has now built successfully through all five native artifact
materializations. The run corrected static-executable audit recognition, absolute interpreter
links in the image-owned Python venv, dependency ordering and already-loaded `DT_SONAME` reuse in
the ELF closure observer, and the cross-substrate sealed Python-prefix smoke contract. Linux
Audiveris now pre-extracts JavaCPP natives into a fixed image-owned cache and includes that cache in
its sealed closure. The Apple code path now performs the same operation through the closed
provisioning language before hashing the candidate and launches through the bundle's fixed JVM
with a candidate-local cache. The machine-independent build, artifact transaction, Apple
materializer, style, and unit gates are GREEN for that follow-on correction. The exact current-tree
`linux-cpu` image also rebuilt GREEN as
`sha256:33a0086e51e8bda30dca94c3502320e53ca3ab9c788be469709bdc88fdfbd55c`, including all five native
materializations; its file, documentation, Proto, chart, and documentation-render gates are GREEN.
Phase 1 remains Active pending corrected-root Apple rematerialization, production cancellation and
installed-runtime smokes, and the Apple full-suite cohort; the paired `linux-cpu` cohort is closed.

Successive canonical `./bootstrap/linux-cpu.sh test` attempts have remained fail-closed before
cluster mutation while exposing three provisioning defects. The Docker Poetry venv now uses
`--copies`, preventing its interpreter from widening the measured closure to `/usr`. The shared
runtime resolver now selects the bounded Darwin Mach-O or Linux descriptor-derived ELF closure by
compiled host platform instead of applying Mach-O inspection on Linux. The resulting image rebuilt
GREEN as `sha256:6a8c107a0d7dd8e33cd1d3b4b7d5ffe55d8d8d6baa04311e17518d3ee09b2fdd`; its cohort passed the clean
build and style gate, then found that the anchor copied host-bound Python-home shebang launchers
which the provisioning digest intentionally excludes. The anchor snapshot now applies the same
content-based exclusion. The next image reached supervisor validation and proved that the closed
environment still modeled only the Darwin snapshot. Linux now retains and revalidates exact ELF
runtime identities without DYLD variables, while Darwin retains its copied DYLD closure. Subsequent
target starts exposed non-self-contained Poetry and project venvs, an over-broad shebang exclusion,
and rejection of valid zero-program-header relocatable ELF objects. The Linux image now constructs
both venvs with copied interpreters and dereferenced standard-library payloads; host-bound launcher
exclusion is confined to `bin/`; and the ELF parser accepts a zero entry size only when the program
header count is zero. An image-native focused rerun passes provisioning and the complete unit
cohort, including the Sprint 1.20 regressions and 83/83 web tests. The focused style and
`cabal build all --enable-tests` gates subsequently passed, and the exact-source image rebuilt
through all five native materializations, framework installs, web build, and Python checks as
`sha256:6adb3c02bad77f710ed45208f3be7253a596b4680c7aece7bcdd912d327e8a38`; only the complete
canonical cohort remains pending at this boundary.
That image's canonical cohort completed its clean test build, then failed the style gate before
cluster mutation on two Ormolu guard-layout differences introduced after the earlier focused run.
The layouts are corrected. The replacement exact-source image rebuilt GREEN as
`sha256:13e83e3e5c337f3c76f22250dc1ee5c430ab0b9a79146799f778702b637aaa2d`; its canonical cohort rerun
passed clean style, Python checks, unit, 83/83 web tests, cluster creation, Harbor publication,
final rollout, routed publication, and eager staging of all 12 models. Per-model inference then
failed closed because the worker required an Apple setup manifest in each Linux engine pod's
private data `emptyDir`. Linux now proves setup through its immutable image framework marker while
Apple retains the published bootstrap-manifest requirement. Focused build, unit, and style gates
are GREEN. The exact-source replacement subsequently rebuilt GREEN as
`sha256:d52820cc81eb90f38e3036c1fcb7ef5af24cda82e1458239745f81993f83e6a9`. Its canonical cohort
passed clean style, Python checks, unit, 83/83 web tests, cluster creation, Harbor publication,
final rollout, routed publication, and eager staging of all 12 models. Both engine replicas then
failed closed at per-model inference because the baked Linux framework markers omitted the
`projectDigest` required by runtime revalidation. The Docker producer now records the same exact
SHA-256 construction consumed by Haskell for both framework environments. The replacement rebuilt
GREEN through all five native materializations, framework installs, web build, and Python checks as
`sha256:6b93f886c299585a973221095c273f8664daf7e0dd35d97cda836b99f7f1ec1f`; an image-native probe
independently recomputed both project digests and matched their recorded marker values. Only its
complete canonical cohort remained pending at that boundary. That cohort passed every pre-cluster
gate, cluster creation/publication/rollout, eager staging, and the Python-backed inference boundary,
then failed closed on `llm-tinyllama-gguf`: OCI unpack had assigned fresh inode numbers, so runtime
comparison rejected otherwise exact persisted Linux target evidence. Descriptor-stable observation
continues to bind device/inode identity while reading; persisted image evidence now compares the
portable closed paths, types, modes, sizes, digests, ELF metadata, and loader edges. Focused
regression evidence and a replacement cohort remain pending; Phase 1 remains Active.
The exact-source focused unit and style gates are GREEN, including the OCI identity-normalization
regression. The replacement image and canonical cohort remain pending.
The replacement image subsequently rebuilt GREEN through all materialization and image checks as
`sha256:51dc9484c4327725b9b18e284afe761d37e75ec20e2909c39f02cd82c4b32e90`; its canonical cohort is
pending. That cohort passed every pre-cluster gate, cluster publication/rollout, and eager staging,
and crossed the prior Linux inode-revalidation failure, but the first
`llm-smollm2-safetensors` request produced no result within the 4,200-second deadline while both
replicas repeatedly launched CPU-bound bounded children for the unacked request. The
diagnostic rerun reproduced the request and captured `engineProcessed ... status=completed` from
both replicas, followed by Pulsar consumer `Broken pipe` failures and the proxy's explicit
`Idle timeout expired: 30000/30000 ms`. The model and capped runner therefore completed; the
consumer session was severed while real inference held its delivery. An initial correction set
`webSocketSessionIdleTimeoutMillis`, and its focused `infernix-unit` plus `lint chart` gates were
GREEN. The replacement image subsequently rebuilt GREEN through all five native
materializations, framework installs, web build, Python checks, and browser provisioning as
`sha256:75e40a2e57537834efcfbd6b89082e786bef6d019ce3ec2cdb1951ce33614bf9`
(20,125,136,372 bytes). Its canonical cohort passed all pre-cluster gates and reached per-model
inference, but live proxy inspection proved that Pulsar 4.0.9 does not project that key into
`proxy.conf`; the effective closing setting remained `httpServerIdleTimeout=30000`. The cohort was
stopped through managed teardown before the known timeout. The chart default and binary-owned
local-topology override now set the effective `httpServerIdleTimeout` to a bounded 7,200,000 ms,
above the 4,200-second result deadline, with lint and rendered-values guards. Focused validation
is GREEN (`infernix-unit`, including the rendered-value assertion, and `lint chart`). Another
replacement image/cohort remains pending; Phase 1 remains Active.
The corrected replacement then rebuilt GREEN through the complete image gate as
`sha256:7129edb66e79ece15fa73f82fa458da373abf6d45ba82752dbfc243c374b9a17`
(20,125,117,304 bytes). Its canonical cohort is pending.
The canonical cohort has passed the clean pre-cluster gates and live cluster inspection confirms
the running Pulsar 4.0.9 proxy contains `httpServerIdleTimeout=7200000` in
`/pulsar/conf/proxy.conf`. It then crossed the former missing-result boundary: retained and current
SmolLM2 requests completed and published without an idle timeout or broken pipe. The cohort next
failed cleanly on `llm-tinyllama-gguf` because Linux target revalidation still bound
`/etc/ld.so.cache`; a later Playwright dependency-install layer legitimately regenerated that
cache. A direct image-native expected/observed diff proved that some system-library edges genuinely
used the cache: resolved paths and object digests were unchanged, but the cache digest, size, and
entry indices changed. Cache identity therefore must remain bound. The loader observer now omits
cache evidence only when no edge used it (focused unit/style GREEN), while the Dockerfile installs
all Playwright system packages before native artifact materialization so cache-backed evidence is
measured from the final immutable filesystem. A new image/cohort remain pending; Phase 1 remains
Active.
The replacement image rebuilt GREEN through the complete image gate as
`sha256:5a353aa4c59ef46d3b4cef5097225bd4f55d61513db1f1cfd41914f566ab832b`
(20,125,140,109 bytes). Its canonical cohort is pending.
After moving browser/system dependency installation ahead of native materialization, the final
replacement image rebuilt GREEN as
`sha256:7211b0fe8b55d4d28b35fcf4fcfc4edf04050a6292e94d7b86bffe2d57d354df`
(20,125,135,753 bytes). A fresh image-native observation of `llama-cpp-cli` now equals its embedded
artifact manifest exactly, including the genuinely used loader-cache evidence. The replacement
canonical cohort is the next gate; Phase 1 remains Active.
That canonical cohort passed every pre-cluster gate, published the exact image to Harbor, brought
the platform up, staged all 12 models, and confirmed the live proxy setting. It nevertheless failed
cleanly at `llm-tinyllama-gguf` with `native engine artifact validation failed for llama-cpp-cli`.
Because the same final image validates under Docker but not after Kubernetes/containerd deployment,
the remaining mismatch is runtime-specific artifact observation; managed teardown completed and
Phase 1 remains Active.
An in-place diagnostic bring-up then disproved that preliminary runtime-specific hypothesis. Inside
the live engine pod, llama target evidence and the complete `/opt` manifest both validated. The
actual mint failure was the generation-lease sidecar: multi-artifact reconciliation globally
retired every preceding adapter's sidecar, leaving only the last (`jvm-native`) launchable. The
reconciliation now retains a bounded, identity-checked census of installed sibling generations.
The same live census also showed ONNX Runtime and CTranslate2 evidence had been observed before
framework Poetry installs in the same final Docker `RUN`; those installs changed their system
loader closure. Native materialization is now the last mutating command after framework installs,
web build, and Python checks. Focused compilation is GREEN; a replacement image/cohort remain
pending and Phase 1 remains Active. The combined `infernix-haskell-style`/realness and
`infernix-unit` focused gates are also GREEN for the correction.
The reordered replacement image then rebuilt GREEN as
`sha256:5898e219674bf08ab94a15701bf0f21b61e9f34b11fda9fc96b96ed2fa6cc0c1`
(20,125,337,251 bytes), and direct final-image validation passed for all five native manifests.
Its sidecar census still contained only `jvm-native`: retained missing paths were reserved from
retirement but not recreated. Reconciliation now reacquires each validated sibling generation
under exclusive materialization authority, which mints any missing real lock leaf before obsolete
retirement; a focused in-container probe recreated all five exact sidecars. One final replacement
image/cohort remain pending and Phase 1 remains Active.
The next clean image rebuilt GREEN as
`sha256:ab74cc45bb978dd96a6c5f55cf0f6562d165999bb752b10a10457dadcb2fc263`
(20,125,326,588 bytes), again with five valid manifests but only the final sidecar. The remaining
retirement site was post-publication activation: after explicitly retiring the replaced adapter's
prior generation it redundantly ran a global `[currentLease]` reconciliation, deleting every
sibling. That global sweep is removed; preparation already performs bounded all-sibling
reconciliation and commit retains the adapter-local retirement. Focused style/realness and unit
gates are GREEN; a final replacement image/cohort remain pending and Phase 1 remains Active.
The final replacement image rebuilt GREEN as
`sha256:e4e042c10c9fe7aa32c3d2eb49ecc4df392061b7095712d7dded01001cb4af0e`
(20,125,330,441 bytes). Direct validation from an untouched container proves all five native
manifests valid and all five exact generation-lease sidecars present. The canonical Linux cohort is
the next gate; Phase 1 remains Active.
The canonical cohort passed every pre-cluster gate, published the exact image, deployed all five
lease leaves into the live engine pod, staged all 12 models, and completed real SmolLM2 inference.
TinyLlama crossed the former artifact-validation boundary and launched the real native executable,
then failed cleanly because `llama-cpp-cli` rejected the closed wrapper argument `--engine`.
Managed teardown completed. The remaining defect is now the native invocation grammar rather than
artifact identity or custody; Phase 1 remains Active.
The raw-target dispatch now renders the verified real CLI grammar for llama.cpp, whisper.cpp, and
Audiveris, retains the wrapper protocol only for Python-backed native adapters, and rejects missing
operands or unregistered adapters before process creation. Focused unit coverage pins the exact
bounded argv shapes and the focused Haskell unit gate is GREEN; the style gate first rejected a
hanging-case layout, which is corrected and awaiting its rerun. No replacement image or canonical
cohort has yet validated this correction, so Phase 1 remains Active.
Audiveris success handling now performs a deterministic, depth-8/4,096-entry output-tree census,
rejects symlinks and ambiguous or absent MusicXML outputs, and emits an upload marker only for the
single real output file. This adjacent fail-closed correction compiles and the focused unit gate is
GREEN; the style gate reported one mechanical HLint suggestion, now corrected, and awaits rerun.
The corrected focused Haskell style/realness gate is GREEN. A clean replacement image and canonical
cohort are now the next evidence gates; Phase 1 remains Active.
The clean replacement image rebuilt GREEN as
`sha256:6415a72573baa4920a2197e6c8a61f65040d654be91c89d73849bf4a4ce0dcdd`
(20,125,326,520 bytes). An untouched-container census proves all five exact generation-lease
sidecars, and package-internal root revalidation proves all five native manifests valid. The
canonical Linux cohort against this exact image is the next gate; Phase 1 remains Active.
That canonical cohort passed the static/unit/web gates, published and deployed the exact image,
staged all 12 models, and completed real SmolLM2 inference. TinyLlama accepted the corrected real
CLI grammar and began native execution, then exceeded the capped standard-output capture limit;
the process group was terminated and managed teardown completed. The remaining Linux defect is now
bounded llama.cpp output, not invocation parsing, artifact identity, or custody. Phase 1 remains
Active.
The llama.cpp grammar now also selects its supported non-conversation single-turn/simple-I/O mode
and disables native diagnostic logging while retaining the 32-token, 512-context, one-thread,
zero-GPU-layer bounds. Exact argv regression coverage, focused style/realness, and focused unit
gates are GREEN. A replacement image/cohort remain pending; Phase 1 remains Active.
The replacement image rebuilt GREEN as
`sha256:3f6b8b7e45429c9b8be80bd39d6285fb6563849984fbbbb8cae045b2c18c85d9`
(20,125,341,777 bytes). An untouched-container census proves five exact generation leases and all
five package-internal manifest revalidations pass. Its canonical cohort is pending; Phase 1 remains
Active.
The canonical cohort again passed every pre-cluster gate, published the exact image, staged all 12
models, completed real SmolLM2, and advanced beyond TinyLlama to `speech-whisper-small`, proving the
bounded llama.cpp output correction behaviorally. It then failed before whisper execution because
MinIO returned HTTP 507 while uploading the integration WAV; managed teardown completed. Storage
capacity/reconciliation is now the active Linux boundary. Phase 1 remains Active.
The HTTP 507 was host-capacity pressure rather than an inference regression: ten disposable
Phase 1 diagnostic containers retained superseded image generations while the backing filesystem
was 90% full. Removing only those explicitly named task containers recovered 119 GiB and moved the
filesystem to 81% used (263 GiB available); operator state and retained cluster data were untouched.
The unchanged `3f6b8...` image is ready for the canonical cohort retry. Phase 1 remains Active.
That retry passed every machine-independent gate, published the exact image, reached typed cluster
readiness, staged all 12 models, and crossed the former MinIO and Whisper boundaries. It then failed
at `speech-faster-whisper-ct2`: the Linux RSS observer sampled a live `/proc/<pid>/stat`, raced the
process into terminal state, and treated the resulting terminal `status` file without `VmRSS` as
enforcer loss. Managed teardown completed. The observer-race correction and regression are the
active Phase 1 boundary.
The Linux observer correction now accepts missing `VmRSS` only when the same status payload
explicitly reports terminal `Z` or `X`, and continues to reject live or malformed payloads. Its
positive and fail-closed regressions compiled and ran in the focused unit command. That command did
not close the full unit gate: a later, unrelated bounded-command recovery assertion found its exact
test owner PID still live. Retained test-activity reconciliation is the next focused check; no image
has been rebuilt from this correction yet.
The supported `infernix test unit` Linux-container gate is GREEN, including the RSS terminal-state
regressions, the complete Haskell unit suite, and PureScript 83/83. The earlier exact-owner failure
was reproduced only by bypassing the harness with direct Cabal, which omits the test surface's
lifecycle preparation; it is not accepted as phase evidence and did not justify weakening custody.
The corrected image built GREEN as
`sha256:5bef020973a155137c696272231510e7f95f5ef28dfe01175d44ed5b74f68684`
(20,125,349,791 bytes), including all native-artifact checks and the image-local compile, bundle,
type, formatting, and static checks. The canonical Linux CPU cohort against this exact image is now
the active gate; Phase 1 remains Active.
That exact-image cohort passed the complete style/realness, Python, Haskell unit, and PureScript
83/83 gates; registry-only verification; typed cluster readiness; routed publication; and staging
of all 12 models. Six over-budget rows returned their expected typed admission failures. The first
remaining real artifact row, `tool-audiveris`, then returned an artifact whose type failed the
optical-music-recognition contract. Managed teardown completed. Audiveris output-type discovery is
now the active Linux boundary; Phase 1 remains Active.
The failure was a validator defect, not fabricated or malformed engine output: the runtime's closed
Audiveris collector accepts the three real MusicXML forms `.mxl`, `.musicxml`, and `.xml`, while the
integration family contract omitted compressed MusicXML (`.mxl`). The contract now recognizes the
same three forms. Focused validation and a replacement image/cohort remain pending.
The source-matched replacement image built GREEN as
`sha256:0b7a2ce5bf381f8436c32526ac8aa27a010d6cc4e40184060889b05a6b0be2ff`
(20,125,353,937 bytes), including all five native-artifact checks and the image-local compile,
bundle, type, formatting, and static checks. Its canonical Linux CPU cohort is now the active gate.
That cohort passed all machine-independent gates, exact-image registry verification, typed cluster
readiness, staging of all 12 models, the complete per-model matrix (including the corrected real
Audiveris `.mxl` artifact), cache lifecycle, service runtime loop, durable topic families, engine
pool placement/backpressure, frontend and coordinator failover, engine-pod replacement, and engine
node drain. It then failed model-bootstrap deduplication because one authorized request attempt
produced two new ready events instead of exactly one. Managed teardown completed. Bootstrap
ready-event deduplication/accounting is now the active Linux boundary; Phase 1 remains Active.
The failure exposed ambiguous validation accounting: ready events identified only the model, so the
test attributed every concurrent eager/recovery ready event for that model to the one replayed
request. The typed event now carries its causal request-attempt key (with backward-compatible decode
for retained older events), and the adversarial check still counts raw Pulsar message IDs but only
for that exact authorized attempt. Focused validation and a replacement exact-source image remain
pending.
The supported Linux-container `infernix test unit` gate is GREEN after that correction: all Haskell
unit/property coverage passed, the changed integration target compiled under `-Wall -Werror`, and
PureScript passed 83/83. The replacement exact-source image then built GREEN as
`sha256:79e746d37fdd6a8415964c9350af6346f00f1244460890cea61ffdb81648cde1`
(20,125,554,166 bytes), including all five native materializations, framework environments,
image-local Haskell and web builds, Python checks, browser provisioning, and the CLI-help smoke.
Its canonical Linux CPU cohort passed every machine-independent gate, exact-image Harbor
publication, the complete real per-model matrix, all six typed memory-admission rows, cache and
service-runtime validation, durable Pulsar families, placement/backpressure, frontend/coordinator/
engine replacement and node-drain recovery, the corrected exact-attempt model-bootstrap
deduplication gate, 12-prompt throughput (`p95Seconds = 1639.8977992534637`), Harbor/MinIO/routed
Pulsar/PostgreSQL recovery, PostgreSQL lifecycle rebinding, anti-affinity, and the
`demo_ui = false` lifecycle. Routed Playwright then passed 14/16 and failed both inference-bearing
tests before submission because their helper invoked operator-facing `infernix kubectl scale`
while the harness-owned cluster slot was reserved. Managed teardown completed. Replacing the
Playwright helper's arbitrary operator-kubectl dependency with a closed, harness-authorized
package command vocabulary is now the active Phase 1 boundary; Phase 1 remains Active.
That code-side correction is now implemented: Playwright can request only two package-owned
actions, model-specific engine preparation and fixed demo-pod replacement. Both execute inside a
harness-owned cluster region; deployment names and replica counts are derived from the generated
catalog, and the closed cluster command language owns the exact scale/list/delete/wait vocabulary.
The operator diagnostic wrapper is no longer used for these mutations. The supported Linux
container unit gate is GREEN (Haskell unit/property plus PureScript 83/83), the focused command
registry/argv/rejection regressions pass, repository lint is GREEN, `infernix lint docs` is GREEN,
and `git diff --check` is GREEN. A replacement exact-source image and its canonical Linux CPU
cohort remain the active Phase 1 gate.
The replacement image has now built GREEN as
`sha256:0415213b271d730eb8099f8414ec4d49aabc0e141c1024e247db3e55389b80c2`
(20,125,667,641 bytes), including all five native artifacts, framework environments,
image-local Haskell/PureScript/Python checks, browser provisioning, and the CLI-help smoke. Its
canonical Linux CPU cohort is now the active Phase 1 gate.
That cohort passed the Haskell style/realness gate but stopped in machine-independent preflight
because the image-baked `documents/reference/cli_reference.md` generated section omitted the two
new registry commands. The host reference is now byte-aligned with the authoritative renderer.
Because Linux validation consumes the baked source snapshot, a second replacement image is
required; the prior digest is retained only as failed evidence and Phase 1 remains Active.
The corrected source-matched image is now GREEN as
`sha256:e5ef7da5641972f7935386b1e95919f476fe861f93adc3984f364b75c767f7d3`
(20,125,654,078 bytes). Its image-local checks and an image-backed `infernix lint docs` pass. This
digest's canonical Linux CPU cohort is now the active Phase 1 gate.
That cohort passed the repaired generated-documentation gate and repository style/realness, then
stopped in `infernix-unit` because the newly added scale-renderer assertion omitted the renderer's
mandatory `--kuberc=/dev/null` argument. Production behavior was not implicated. The assertion now
pins the complete closed argv, including ambient-kuberc suppression. The replacement exact-source
image is GREEN as `sha256:6b9e7f5aada9f51e0befe7cd583ad08384ca63419f2088f074bbec048fd881aa`
(20,125,645,456 bytes). Its image-backed unit cohort is GREEN (Haskell unit/property and
PureScript 83/83), and its image-backed documentation lint is GREEN. The canonical Linux CPU
cohort on this immutable digest passed all machine-independent gates, exact registry publication
and verification, typed cluster readiness, routed publication, and staging of all 12 configured
models. It then failed during real `llm-tinyllama-gguf` inference because the Linux RSS observer
sampled a live `stat` record while the process was exiting and the following `status` record lacked
`VmRSS`; managed teardown completed. The earlier terminal-status correction was too narrow because
procfs can discard the memory map before publishing a terminal state. The observer now performs a
fixed three-retry `stat`/`status` recheck, accepts zero only after disappearance or explicit
terminal-state evidence, and still fails closed for a stable live or malformed record. Focused
regressions cover vanished, terminal, live, and malformed recheck evidence. A new exact-source
image built GREEN as
`sha256:77b89e61bf6e96bb40978a73b018ecd6c480bf83dfea1b6aaba8b8c04f2236df`
(20,125,740,478 bytes), including strict Haskell compilation, browser provisioning, web and Python
checks, and all five native-artifact validations. Its image-backed unit cohort is GREEN (Haskell
unit/property plus PureScript 83/83). The canonical Linux CPU cohort on this immutable digest is
now the active gate; Phase 1 remains Active. Its first attempt stopped before cluster mutation at
the style/realness gate: HLint required eta-reducing the new `readResidentBytes` definition. The
mechanical correction is applied; because it changes source identity, a fresh exact-source image
and complete canonical cohort are required rather than reusing this digest. The replacement image
built GREEN as
`sha256:d9cb08af957937ef5658c4b8f4b24cc97497032d5cf21958b82bd9fda6066a3f`
(20,125,766,951 bytes), including strict compilation, browser provisioning, web and Python checks,
and native substrate materialization. Its complete canonical Linux CPU cohort is now the active
gate. That cohort passed every machine-independent gate, exact Harbor publication and registry-only
verification, typed cluster readiness, routed publication, and eager staging of all 12 models, but
real `speech-faster-whisper-ct2` inference reproduced the missing-`VmRSS` exit race. The three 1 ms
rechecks were too short under the loaded cohort; managed teardown completed. The same fail-closed
terminal-evidence loop now permits four full 50 ms watchdog intervals before rejecting a stable
live task. The replacement exact-source image built GREEN as
`sha256:51292f6f3d98560b383a4ab5cc8a1807aa5388fa5cc0ba8c99b305d90ba9ff67`
(20,125,729,597 bytes), including strict compilation, browser provisioning, web and Python checks,
and all five native-artifact validations. Its complete canonical `./bootstrap/linux-cpu.sh test`
cohort is GREEN with exit status 0. The source-matched run passed the combined Haskell
style/realness gate, Python checks, Haskell unit/property suites, PureScript 83/83, exact-image
Harbor publication and registry-only verification, typed cluster readiness, routed publication,
eager staging of all 12 configured models, real per-model inference or the exact typed 4 GiB pod
capacity rejection, cache and service-loop checks, durable Pulsar topic families, placement and
backpressure, frontend/coordinator/engine/node failure recovery, bootstrap deduplication, the
12-prompt multi-user throughput gate, Harbor/MinIO/Pulsar/PostgreSQL recovery, lifecycle rebinding,
and Linux engine anti-affinity. The integration suite passed and completed managed teardown; the
outer harness then restored the operator configuration and all 12 model-cache entries. All 16
Playwright tests passed, including the full catalog per-model browser matrix (42.5 minutes), and
the final managed teardown completed before the command returned 0. This closes the current
Linux CPU frozen-identity gate; Phase 1 remains Active only for its separately governed remaining
Apple closure and hardware evidence.

## No-Repo-Owned Native Source Correction (2026-07-26)

The governed architecture now forbids repository-owned native implementation source, including C,
C++, Objective-C, CUDA, assembly, Metal, Swift, C2HS, and C-- files, embedded native-source
payloads, and Cabal native-source declarations. Phase 0 Sprint 0.18 owns the governance mirror,
Phase 1 Sprint 1.20 owns
removal of the pre-existing Objective-C/C/Metal source embedded in the Apple materializer, and
Phase 2 Sprints 2.15-2.16 own the all-Haskell lifecycle-lock and bounded-command correction. The
lifecycle C shim, its FFI declaration, and its Cabal entry are removed code-side. Focused
adversarial validation, final review with no High or Medium findings, and the complete
machine-independent correction Stage 1 passed on 2026-07-27. The rejected forked target-group
candidate has been replaced by the all-Haskell
self-exec anchor/supervisor/pin topology. The production modules compile and the ordered
compile gate passed; the inventory recorded there has since grown and is currently 6 positive and 79 negative fixtures. The prewrite activity-residue window,
unbounded recovery-record reads, and missing capture/terminal semantic bounds found by review are
corrected. The
replacement uses nested exact-identity custody
handshakes: the supervisor begins inside the anchor group and a self-exec pin begins inside the
supervisor group; neither may detach until the parent has recorded and acknowledged its provisional
birth identity. The target is not forked until after the version-3 lease containing exact
owner/anchor/supervisor/pin identities is durable and the retained pin acknowledges its one-shot
start authority. The arbitrary target is owned and reaped by the supervisor; it is not persisted as
a fabricated exact birth identity. A bounded, fsynced version-3 common-boot or version-4
distinct-boot incoming-intent filename preserves the helper identities across a crash before any
payload byte is written. The obsolete `cbits/infernix_subprocess.c` file and Cabal `c-sources:`
declaration are removed. Phase 2 remains blocked by active Phase 1 and retains its own ordered
phase review, validation, Apple, and `linux-cpu` requirements.

The audit also found complete Objective-C/C/Metal source literals and `.h`/`.m`/`.c` writers in
`AppleSilicon.hs`; extension-only enforcement would have missed that cosmetic container. Sprint
1.20 has removed that implementation, its compiler scripts, and the standalone bridge artifact.
The replacement MLX 0.32.0 GPU-operation and coremltools 9.0 device-observation preflights are
green. The first Phase 1 adversarial review rejected the follow-on materializer/runtime source with
three High, six Medium, and two Low findings: raw executable and raw-IO lift authority remained
representable; copied host CLIs did not yet carry a closed dynamic runtime; runtime launch did not
consume exact artifact evidence; and smoke selection, manifest validation, cleanup proof, child
deadlines, Poetry locking, and payload hashing needed further correction. Focused transaction
results remain provisional and are not Phase 1 closure evidence. A
second review rejected the subsequent artifact boundary with two High, two Medium, and one Low
finding: the rank-2 artifact token could escape its shared-lock callback; writer locking was not
authority-coupled; stale self-consistent recipes remained admissible; and pathname traversal could
hash a mixed snapshot. A third focused runtime review rejected the next draft with one High and two
Medium findings: generic package-level capped-launch authority still accepted arbitrary executable,
argument, working-directory, and environment values; the artifact runtime token remained reusable
rather than encoding a one-shot transition; and actual lock-through-reap/cancellation enforcement
evidence was absent. Full Apple materializer
failure/cancellation, recursive-closure, obsolete bridge retirement, and mount-death recovery
evidence is also still missing. A fourth materializer review rejected the next source with two High
and two Medium findings: exact resolved-tool identity was discarded before pathname execution,
Audiveris mount evidence was inert and not owner-death recoverable, Mach-O provenance could name
bytes other than the copied destination, and malformed dyld audit output could be admitted as
version evidence. The malformed-dyld correction passes its focused Python contract, but the
attempted selector-based nested-runner supervisor is rejected: a blocking post-`SIGKILL` wait
cannot provide both a hard total deadline and exact designated-owner reap. The nested-child
implementation has now been deleted. Native CLI and JVM routes fail closed into direct
Haskell-owned helper supervision, the Python runner retains only in-process package APIs, and its
AST ownership contract plus the complete Python `check-code` gate passed on 2026-07-27. Direct
Haskell target dispatch and helper-owned cleanup remain open, and the superseded selector result is
not evidence.
Focused direct `ghc -fno-code -Wall -Werror` checks on 2026-07-27 proved that the then-current Apple
candidate/mount authority fields participated in the ordered and negative fixtures. A later
compiler check invalidated the callback-shaped positive as final evidence: ordinary `IO` bind
cannot retain a linear success continuation without an unsafe multiplicity cast or a linear-effect
runtime. Sprint 1.20 now requires hidden, runner-owned indexed phase sequencing plus fresh
production-dependent construction/import/skip/escape/reuse fixtures; the aggregate compile-fail
suite remains pending. The audit also found that generated `bin/*` shell wrappers and their
wrapper-shaped manifest contract remained, while the direct-target catalog fingerprinted path text
rather than exact executable/interpreter/script/runtime-closure observations. Wrapper retirement
has landed in the worktree, but the next audit found that the first Linux image-target record
covered only selected `/opt` roots and therefore did not bind the system loader, resolution
metadata, or recursively loaded system libraries used by ELF, Python, and JVM targets. That is a
High-severity incomplete-closure defect, not executable provenance. **That blocker is now closed**
(2026-07-29): `Infernix.Engines.Artifact.Loader` produces descriptor-derived ELF loader-closure
evidence — `PT_INTERP`, the recursive `DT_NEEDED` chain, and `/etc/ld.so.cache` — and
`runClosedLinuxNativeArtifactSmoke` revalidates the complete recorded closure before launch and
fails closed on a manifest carrying none. `LD_LIBRARY_PATH` is deliberately never consulted, since
reading it would violate the no-env doctrine and make the generation irreproducible.
The related claim that the Linux lease identity "derives from only the metadata-root payload digest"
was **stale**: `engineArtifactGenerationFingerprint` already binds payload digest, recipe, target
contract, and evidence fingerprint together on `linux-native`. The real residual is one level down —
every production generation-leased helper takes the Apple-shaped candidate branch, so
`validateEngineArtifactHelperLease` is unreachable in production, and runtime launch consumes no
generation lease at all, so generation identity does not yet authorize shared execution anywhere.
The root-bound provisioning writer draft also remains rejected: it revalidated an authorized root
around pathname effects, but direct writes/create/rename/retirement and external venv, package,
download, mount, and copy tools could still be redirected by swapping an intermediate parent at the
effect boundary. Phase 1 requires a retained exact parent descriptor through every direct effect,
descriptor-derived working directories plus safe relative operands for external mutators, and
deterministic swap-at-effect coverage. `/dev/fd/<directory-fd>/...` is not a portable substitute
because Darwin does not permit descendant traversal through that namespace. The Audiveris download
cache must use a separate fixed-root lock/writer authority rather than widening EngineWriter beyond
`dataRoot/engines`.
The Apple installed-Python closure is also not yet self-contained: although the venv target is made
with `--copies`, `pyvenv.cfg` still names the source Homebrew home and executable. The structured
record must name the final artifact-local Python home, residual source paths must be rejected, and a
source-unavailable execution test must pass. Installed-target validation must also reject any
canonical executable outside the sealed artifact root.
The current correction audit also found that the capped-engine kernel reaped its process-group
leader before later numeric process-group cleanup. That ordering leaves a PID/PGID-reuse window
and is not exact lifecycle evidence; Sprint 1.20 now requires the bounded helper topology to retain
an exact live group owner through signal, group-absence proof, and designated-owner reap.
The latest convergence audit also rejected caller-supplied effectful completion/transaction
callbacks while live writer authority was in scope and a helper order that could acquire a
generation read lease before its recoverable identities were durable. The Apple-owned callback
surface is now a private first-order fixture language; the remaining provisioning boundary and
supervisor order are still being corrected. A generation must be hashed and its exact sidecar
minted under exclusive authority before smoke; the already-born anchor, supervisor, and pin
identities must then be durably published before the one-shot start authority is spent and the
supervisor acquires shared generation authority. Shared authority must remain through exact group
absence and designated-owner reap, followed by a rehash and exclusive revalidation before
publication. This draft has no accepted review or validation evidence.
The focused subprocess-test audit also found PID-only target disappearance and stopped-state
assertions. They are not lifecycle evidence: each owned target fixture must publish the target birth
identity and use exact-identity absence plus designated-owner reap evidence rather than numeric PID
reuse assumptions.
The **complete machine-independent gate set is now GREEN** on one identified Sprint 1.20 worktree,
`sha256:9f75c2deaa3086f7aa018e5c5fdf421c8e059b83223cf106f81045e3f326a132`, with installed Apple
binary `sha256:2a1e8262bbdbb840fc303e142e2c60baa8fcfadbd512f81744a8d8377bb49f6e`: the production and
integration build, `infernix-unit`, `infernix-haskell-style`, `infernix-compile-fail` (6 positive,
78 negative), `infernix-artifact-transaction` (44 cases), `infernix-apple-materializer`,
`infernix-capped-engine-observer`, `infernix-execution-plan-internal`, Python `check-code`, web unit
83/83, `infernix lint files/docs/proto/chart`, `infernix docs check`, and `git diff --check`. The
previously red `infernix-unit` and `infernix-haskell-style` suites are green for the first time on
this correction. Reaching them exposed and closed the anchor/group-owner lifecycle defect this
section records, the leaderless-group signal race, a synchronous-exception record that decoded
non-leader group members as leaders, and — behind the `hlint` stage that had always failed first —
thirty repo-owned readability and governed-boundary violations no recorded gate result had ever
covered, including two forbidden `.Internal` writer-authority imports in the bounded-command kernel
and an empty subprocess environment. The subprocess-test audit item above is closed for the anchor,
supervisor, pin, and target-group fixtures, which now execute against exact birth identities.
The first Apple cohort attempt then ran against that green tree and **rejected it**, which is
precisely what a cohort gate is for. Ten further defects, none reachable by any machine-independent
gate, were found and corrected: a Mach-O identity comparison that could never hold for a
symlinked tool (so no Homebrew-Python materialization was reachable), unconditional candidate-venv
relocation (so no native-binary or JVM artifact could activate), an installed smoke that never set
`DYLD_PRINT_LIBRARIES` yet required the resulting provenance, two environment validators that
rejected the sealed-artifact runtime environment, an owned-root derivation that named the final
install root while the smoke runs pre-activation on the candidate sibling, two macOS 26 dyld frame
families the audit parser mis-handled, a two-valued audit classification that made loader
bookkeeping look like application output, an executable-authority guard that recognised only one of
the kernel's two authority forms, and a closure walk that required weak and lazy dylib references to
resolve. **Six of the seven Apple artifacts now materialize, smoke, and activate end to end** —
`llama-cpp-cli`, `whisper-cpp-cli`, `coreml-native`, `ctranslate2-native`, `mlx-native`, and
`onnx-runtime-native` — the first Apple artifact activations of this correction, and the first
Python-backed sealed generations proven to load only from themselves. The most consequential finding
came last: the Python home was never scanned for its own runtime closure, so `lib-dynload` extension
modules (`_lzma`, `_ssl`, `_decimal`) are `dlopen`ed rather than linked and no dependency edge
reached them, leaving the artifact silently dependent on host Homebrew formulae while every
machine-independent gate stayed green.

Two further kernel-level findings came from the Audiveris artifact. First, **the executable snapshot
cannot be applied to an operating-system platform binary**: on Apple Silicon such a binary is
validated against the kernel trust cache rather than an embedded signature, so a copy is killed at
exec — measured directly, `/usr/bin/curl` exits 0 while a byte-identical copy exits 137. That
affects every configured system tool, including the `/usr/bin/top` and `/usr/bin/footprint` observer
Phase 4 Sprint 4.32 specifies. Platform binaries are now executed in place, which is stronger than a
private copy since a SIP-protected path cannot be swapped at all. Second, **the Mach-O universal
magic `0xCAFEBABE` is byte-identical to the Java class file magic**, so the closure scan admitted
Audiveris's `.class` files as Mach-O images; candidacy now requires a structurally credible fat
header.

That attempt is still **not closure evidence**: the Audiveris artifact now reaches its installed
smoke and correctly reports that JavaCPP extracts Leptonica and Tesseract into the operator's
`~/.javacpp/cache` at run time and loads them from outside the sealed generation — a real violation
needing an explicit design decision, not a bound to raise. The closure bounds also remain provisional
pending final measurement, several corrections still have no machine-independent regression coverage,
and no integration, routed, or `linux-cpu` lane has started.

**Part of that load-sensitivity was a real defect, and it is now corrected** (2026-07-30). A frozen
gate run failed with `the cancelled protocol-isolation command published an invalid descendant pid`,
and elimination is exact: the "never published" branch did not fire, so the file existed, and the
only writer for it emits a valid integer. Every fixture publishes with `printf ... > "$path"`, whose
redirection creates and truncates the file *before* `printf` runs, so a zero-length window is
guaranteed by the shell's evaluation order rather than produced by scheduling. `waitForFileContents`
returned the first read after `doesFileExist` and so could return an empty record. It now treats an
empty file as not-yet-published, which makes the deadline the only way a publication wait can fail
and removes that whole class from the load-sensitivity bucket — across roughly thirty call sites,
several of which already asserted `published empty evidence` immediately afterwards, i.e. caught this
race and reported it as a failure. The bucket is not retired: the deadline-shaped symptoms below are
a separate question and repeated green runs on a genuinely quiet host are still owed.

A further finding is that `infernix-unit` is **load-sensitive**. On a host carrying sustained
background CPU load it failed repeatedly with several different deadline symptoms on unchanged
source, then passed. Every symptom was a missed deadline rather than a wrong result, and the pattern
is consistent: the assertions that fail are the ones whose command completes a full target lifecycle,
while the short-circuiting cases in the same assertion pass. One symptom deserves independent
follow-up regardless — an `EPERM` from `signalProcessGroup` during forced cleanup is the same Darwin
zombie-group behaviour already corrected on the test side, and whether every production cleanup path
discharges it is unproven. The suite is green on the current tree, but it should not be treated as a
reliable gate on a loaded host.

Sprint 1.20 therefore remains Active. The Linux ELF/loader closure producer and its helper-side
revalidation landed on 2026-07-29 with machine-independent fixture coverage. The writer-effect
residual was larger than "roughly fifteen": a full audit found 21 pathname-resolving writer functions
across 34 effect sites in `Engines/Provisioning.hs`, 4 absolute external-tool operands in
`Cluster/Subprocess.hs`, a missing kernel symlink primitive, and a still-pathname-resolving
activation transaction.

**Enumerated writer items 1-10 are now closed** (2026-07-29), and a repeat audit finds no remaining
pathname-resolving write effect on any production path in either `Engines/Provisioning.hs` or
`Engines/Artifact/Internal.hs`. Every surviving raw `openFd` in the provisioning module is
`ReadOnly`, and the `Directory` create/remove/rename/permissions writers, `writeFile`, and
`Posix.createSymbolicLink` no longer appear in it. The pathname
`synchroniseProvisioningDirectory` is deleted in favour of a descriptor-taking form, which forced
each of its thirteen callers to hold the parent it had mutated through; the mutation kernel gained a
symbolic-link constructor with the same containment rule the package-closure walk applies, plus an
atomic regular-file replace so a durable-record replacement stays one step.

**Item 10, the activation transaction, is closed via a closed first-order root-mutation language.**
The kernel lives in `Cluster.Subprocess`, which already imports the public `Engines.Artifact` and
`Engines.MaterializationLock` facades, so `Artifact/Internal.hs` cannot import it without closing a
cycle. The transaction therefore requests two named effects — `RenameArtifactRootSibling` and
`RemoveArtifactRootSibling` — and the provisioning facade, the only holder of both the writer root
and the kernel, interprets them; the interpreter type is never re-exported by the public facade, and
it is retained on the activation token so a rollback cannot be handed a different interpreter than
the forward transaction used. The conversion also removed a pathname write *above* the authority root
(`createDirectoryIfMissing`, now an exact-identity check against the authority's recorded engines
root), every pathname directory fsync, and — a defect the enumeration had not identified — a
per-entry pathname `removeDirectory` inside the recursive retirement walk, which is now one bounded
descriptor-anchored kernel call rather than one subprocess per directory entry.

The complete machine-independent gate set is GREEN on worktree
`sha256:b23b282ce15b1741130cef08f15ac69745512c290633878c521704772010acd0` with installed binary
`sha256:823675470cfaae700bca4fcd32e3e0ae01034828a9f80bc870af2552c017a7e3`.

**Item 11, the closure-bound reachability obligation, and the Linux sealed-run loader observation
closed on 2026-07-30**, with the complete machine-independent gate set green, run serially, against
worktree `sha256:570ed8fabb8d356acffc32966f76a64ce76b97985c87afeecea04c4992a7d79d` and installed
binary `sha256:5ca4cb99251f84b623ca4a4bb6b9c0b7c747444309fa4ba48d37423c44b46b49`. Item 11 gives the
production root-mutation interpreter its first coverage, and its direct-boundary fixture carries a
pathname control so the descriptor assertion cannot pass vacuously. The four closure bounds are now
reachable through exported accessors and pure folds that production itself runs.

The loader-observation work exposed a High-severity defect no machine-independent gate could reach:
the exact-capture classifier applied the `dyld` audit to **every** smoke, so the Linux native
artifact smoke could not pass on any input. The audit is now selected from the command's closed
provisioning operation, and the ELF frame grammar was measured from a native `linux/arm64` container
rather than assumed. Correcting it surfaced a **design contradiction in the Linux lane** — the smoke
is built on the Apple installed-artifact shape while the `linux-native` catalog names absolute image
targets — which is now decided in favour of binding the smoke to the image target, with the
implementation enumerated but deliberately not landed.

**The Linux image-target binding and the generation-lease consumer residual closed on 2026-07-30**,
and closing the latter exposed two further High-severity defects that no machine-independent gate
could reach. First, both closed Linux sealed-run environment contracts named `LD_DEBUG` alone while
every rendered command also carries the renderer's fixed bytecode guard, so the Linux native artifact
smoke was refused as an unsupported command environment on every input — a second layer behind the
wrong-audit defect recorded above. Second, and larger, **the runtime inference launch never rendered
the closed catalog's leading arguments**: wrapper retirement rebuilt argument rendering only on the
smoke path, so all four installed Python-runner artifacts reached `apple_native_runner.py` without
the `--adapter-id`/`--engine-name` pair it requires, and the Linux JVM target reached `java` without
its classpath. Both are corrected, and every new assertion was measured against the pre-correction
source rather than argued. Runtime launch now also holds the exact generation's shared read lease
through reap and refuses a generation no writer minted.

Still required: the raw-CLI runtime argument translation the leading-argument correction exposed
(`llama-cpp-cli` and `whisper-cpp-cli` carry no argument prefix, so the direct binaries are still
handed a protocol they do not parse — a design decision of the same kind as the JavaCPP question),
the JavaCPP pre-extraction chosen for Audiveris, final closure *values* (blocked on the `jvm-native`
measurement), the remaining impure-surface regression coverage, a fresh final review, exact-source
Stage 1 on a genuinely quiet host, the completed Apple cohort, and its paired `linux-cpu` cohort.
Machine-independent green is the gate to begin Phase 2 implementation, not Phase 1 closure. The old
fixed-bridge/Clang topology has no accepted correction evidence.

The same source review rejected the remaining direct `proc_pid_rusage` FFI exemption. The source
now implements Phase 4 Sprint 4.32's fixed-command, total-deadline public `/usr/bin/top` plus
`/usr/bin/footprint` observer behind the package-internal capped-engine kernel; focused and aggregate
validation remain open. Humanized `top`
values may discover the exact engine process-group membership, but only exact bounded footprint
evidence may classify `EngineExceededCeiling`. All pre-replacement Apple watchdog evidence is
historical and nonreusable for current Sprint 4.32 closure.

This correction reset every affected Phase 0/1/2/4 evidence claim. Every source digest,
installed-binary digest, final-review result, Stage 1 result, and cohort assertion recorded before
the interjection is historical **GREEN-as-run** evidence only for the correction surfaces and is
superseded and nonreusable. This includes Phase 1 Apple bridge/materialization, Phase 2
lifecycle/subprocess, and Phase 4 Apple footprint-sampler evidence. The first accepted
post-correction identity is the 2026-07-27 Phase 0 closure: base
`6bad4af7ea3cca1c8d22f1ec968b4d95dd13a59d`, pre-evidence tracked-plus-untracked worktree
`sha256:93a9c053bbe5d41feaba3c10fae8f55c9c42e2c566ebcacbc187747f6b87a4d9`, and installed Apple
binary `sha256:da62304fdec82bb5e2c1a8d3d0c3fc0fe66a9aa7c77c3d1023de8572a8095fcf`. The source digest was
unchanged after the complete machine-independent gate; subsequent evidence-only plan edits record
the result without changing executable source. No correction-dependent Apple or `linux-cpu`
cohort evidence exists.

The interrupted Apple attempt 5 passed style, Python, Haskell unit, and web 83/83; replayed retained
state; built workload tag `sha256-12e0ab1c2288a8629b8e9949977c6b784d188da2d79ae01475bd5fdb8c66cc1e`;
registry-only verified that workload; and was publishing registry-verified support images when the
interjection invalidated its freeze. Cancellation preserved the primary `user interrupt` and
exposed same-process lifecycle-lock cleanup contention (`errno 35`). Supported recovery staged all
retained claims, observed Kind absent, retired the harness reservation, and restored the operator
config. Those partial observations do not close Phase 2 or Wave Y.

## Accelerator Availability Inverted On The Current Host (2026-07-30)

Work moved to the CUDA Linux development host — native Ubuntu amd64, 32 cores, 124 GiB RAM, one
RTX 5090 (driver 570.211.01, CUDA 12.8), GHC 9.12.4, cabal 3.14.2.0. This inverts the hardware
assumptions every open phase was written against, in both directions:

- **`apple-silicon` is now the unavailable accelerator.** Sprint 1.20's Apple materializer,
  cohort, and `jvm-native` measurement obligations, and the Apple halves of the Phase 2 and Phase 4
  cohort gates, cannot be run here at all. Per the operator decision below they are recorded as
  explicit outstanding obligations rather than claimed, which is exactly the treatment this plan
  already applies to Sprint 6.44's `linux-gpu` gate.
- **`linux-gpu` is now available.** Sprint 6.44's selected `linux-gpu` cohort gate was recorded as
  hardware-blocked because "the operator host is Apple Silicon with no CUDA device". That blocker no
  longer holds. `nvidia-ctk` and the `nvidia` Docker runtime are installed and registered; `nvkind`
  is not yet on `PATH` and its bootstrap installs it.
- **`linux-cpu` remains available** and `./bootstrap/linux-cpu.sh doctor` passes here with no
  package installation triggered.

Section Q's single-accelerator rule is unchanged by this: a phase still selects exactly one of
`{apple-silicon, linux-gpu}` plus `linux-cpu`. What changed is which one a phase can actually
select on the machine in front of it. A deliverable that is intrinsically Apple-bound — the Apple
materializer, Core ML, the Audiveris DMG — keeps `apple-silicon` and waits for that hardware; the
rest may select `linux-gpu`.

The host is not idle: the `jitml` sister project runs here concurrently, including a four-node Kind
cluster. Sustained load averages of 25-35 were observed throughout this session's gate runs. That is
the same condition this plan already records as making `infernix-unit` load-sensitive, and it means
no run recorded from this session is a Stage 1 result.

## Typed Execution Plan Doctrine Reopen (2026-07-25)

The documentation/code audit found that the existing Dhall budget is descriptive rather than a
closed execution language, Linux pod capacity does not enforce each admitted model ceiling, GPU
VRAM lacks a verified per-process enforcer, and raw process-spawn lints exempt production modules.
The repository therefore reopens this execution-ordered work:

- **Phase 0 Sprint 0.17** — canonical doctrine, root/workflow reconciliation, plan reopens, and
  deletion-ledger ownership.
- **Phase 1 Sprint 1.19** — resource-indexed Haskell ADTs,
  `RawRuntimeConfig -> CompiledRuntimePlan -> RuntimePlan` compilation/refinement, opaque daemon and
  placement capabilities, and executable-model-only engine launch.
- **Phase 2 Sprint 2.16** — generated semantic command policies and complete cluster migration to
  the bounded-command kernel.
- **Phase 4 Sprint 4.32** — verified Apple and Linux CPU per-execution memory enforcers, an
  encapsulated serialized-execution authority, and behavioral proof that compiled coordinator
  routing reaches only engine work executable under `ExecutableModel`.
- **Phase 6 Sprint 6.44** — verified NVIDIA VRAM enforcement, adversarial selected-`linux-gpu` plus
  `linux-cpu` gates, import-boundary enforcement, and removal of raw-spawn lint exemptions.
- **Phase 8 Sprint 8.9** — binary generation, reflection, round-trip, and migration of the proper
  Dhall execution-plan unions.

Phase 0 Sprints 0.17 and 0.18 are `Done`; Sprint 0.18 closed the no-native-source governance
correction on 2026-07-27. Phase 1 Sprint 1.19 closed on 2026-07-25 after its complete source-matched
machine-independent gate and final adversarial source review passed: resource indices survive
refinement and launch, live observations are required before `ExecutableModel` construction, raw
decoders are hidden, and launch plus daemon-topic routing consume coherent opaque capabilities.
The gate included the production/integration build, unit/internal/compile-fail/style suites (4
positive and 27 negative compile fixtures), installed files/docs/chart/proto lints and docs check,
Python `check-code`, web contract/build/bundle coverage with 83/83 unit tests, and
`git diff --check`. Sprint 1.20 is now Active. Reopened Phase 2 Sprints 2.14–2.16 are blocked by
Phase 1 in numerical order: the first source identity
passed its source review and machine-independent gate on 2026-07-26, but the first Apple behavioral
run exposed a pod-derived claim/node gap during partial-cluster teardown and cleanup exception
masking, rejecting that identity before `linux-cpu` started. The lifecycle now uses
global runtime
inventory and owner/runtime authority, retained snapshots freeze their sources, the harness reserves
the slot before config takeover, and the semantic command compiler closes operands, deadlines,
process groups, and credential transport. Kind deletion now owns its generated bounded
idempotent-absence policy, revalidates normal/recovery authority beside the effect, rechecks exact
replay intent for recovery, and accepts a terminal non-zero only after observing actual absence.
The podless-PVC binding correction infers ownership only from the sole paused workload-capable
worker. Preserving and exhaustive synchronous/asynchronous cleanup now covers lifecycle, daemon,
snapshot, protected-credential, temporary-path, and descriptor boundaries; bounded parent/internal
supervisor acquisition is masked while interruptible waits remain interruptible; activity-lease
retirement requires exact reap and anchor-, supervisor-, and target-group absence proofs; and
cleanup failures retain protocol, terminal-status, stdout, and stderr evidence. Final
combined-source review and the complete
Apple-host Stage 1 gate initially passed on 2026-07-26 against pre-evidence worktree digest
`sha256:63ab2dd3ff12d266db337464ec272335f3bd72acf7c0ab86a98291da7a4e746f`.
The subsequent result-block edits were evidence-only. An Apple retry then recovered
the dead-owner state through production, staged every retained claim, deleted the stale cluster,
and passed Haskell unit plus web 83/83. It remained a failed behavioral attempt: the live
integration `DockerBuildOperation` reached 77/87 compiling `Infernix.Runtime.Cache` in the Linux
image, then Cabal returned `Cabal-7125` without an underlying diagnostic. Exhaustive cleanup staged
every retained claim, deleted the harness cluster, and preserved that primary failure. BuildKit
records beginning `5v09...` and `gcy...` then exposed deterministic Linux
`-Wunused-top-binds` under `-Werror` at the unguarded Darwin-only `continueIfRunning` helper in
`Runtime/CappedEngine/Internal.hs`; the visible `Runtime.Cache` line was parallel drain, and
resources were not the cause. The helper is now CPP-guarded to Darwin. A then-current final review
and complete Stage 1 passed against the now-superseded digest
`sha256:c4090b07c3b566b01d81fa8ce71153f1f61b725d09163e00536db7e7036e4a97`.
The next Apple attempt built Linux workload image
`sha256:503a3be849a0dd4692edcbe3096d3f1ebc9962e45b8f0dff91d7226349d3abeb`, passed Harbor,
16-model staging, routes, and platform startup, then exposed a new contract mismatch:
`audio-bark-small` was admitted at required=available=5120 MiB but the live footprint watchdog
returned typed `ModelMemoryLimitExceeded` while integration expected completion. The diagnosed
correction is implemented: Bark's footprint is recalibrated from 5120 to 8192 MiB, the strict
integration rule still requires every admitted catalog placement to complete, the Playwright
catalog-matrix runtime-ceiling escape hatch is removed, and exact Apple/Linux admission unit tests
cover Apple admission at 8192 <= 10240 MiB and `linux-cpu` rejection at 8192 > 4096 MiB. Final
adversarial review then found that a cached host Docker pull could falsely mint `BlobServable`
without independently reading Harbor. The implemented correction replaces `PublishVerifyPull`
with a bounded authenticated platform-selected `skopeo copy` from the Harbor API authority into a
fresh empty `dir:` store under a birth-identity-owned mode-0700 directory. It reads the selected
manifest, config, and every layer independently of Docker's shared store, preserves the primary
failure while cleaning protected auth/verification paths, retains dead-owner auth-directory
reconciliation, and adds closed-command, credential-redaction, and absolute-path unit coverage.
Final combined-source review was GREEN with no High/Medium findings after Bark's exact 10240 MiB
test and the Harbor correction. The complete Stage 1 gate was GREEN against pre-evidence worktree
digest `sha256:d57823179d2749a884dfa5b8258070ec2579023fc5b12bd14274c2a6b5f7a487` and installed
binary `sha256:a0d1b9fbaa8335363759e4ec5479852b63bcfcf57973f989649ffa00d9c70c7c`; the skopeo auth
scratch root was empty afterward. Apple attempt 4 rejects that freeze for closure: registry-only
skopeo verification passed for the workload and all support images, cluster/routes and 16-model
cache staging passed, and both 12288>10240 MiB image rows were correctly unavailable, but Bark
again breached the live capped-engine ceiling at required=available=8192 MiB. Exhaustive claim
staging and cluster deletion passed while preserving the primary diagnostic. The implemented
follow-on loads Bark weights as fp16 on MPS/CUDA and fp32 on CPU, runs evaluation under
`torch.inference_mode()`, and converts generated audio to CPU fp32 before WAV serialization.
`poetry --directory python run check-code` and
`cabal test infernix-unit --test-show-details=direct` are GREEN for this focused correction.
Renewed final review found no High/Medium issues, and complete Stage 1 was GREEN against worktree
`sha256:eae424db7dec765ab89f3c73f4dbd1f282d5ee342e7bc1aa5c01e8ef6ac10228` and installed binary
`sha256:a0d1b9fbaa8335363759e4ec5479852b63bcfcf57973f989649ffa00d9c70c7c`.
The governed no-repo-owned-native-source correction now supersedes that identity and interrupted
Apple attempt 5. The lifecycle C boundary is removed code-side; the
subprocess C shim and its Cabal entry are also removed code-side. The all-Haskell lock and typed
anchor-owned supervision protocol are implemented. Focused adversarial proof, final review, and the
complete correction Stage 1 passed on 2026-07-27 against the exact Phase 0 identity above. No
post-correction Apple
attempt or `linux-cpu` lane has started. Phase 4 and later enforcing phases remain `Blocked` in forward
numerical order until Phase 2 closes.
Earlier validation remains valid for its original narrower scope but does not prove the reopened
construction. The canonical target is
[Typed Execution Plan](../documents/architecture/typed_execution_plan.md).

## Common-Shape Reopen (Pulsar ML-Workflow convergence)

`infernix` and the `jitML` sister project are converging on one shared contract,
[../documents/architecture/pulsar_ml_workflow.md](../documents/architecture/pulsar_ml_workflow.md)
(Engine / Coordinator / Webapp roles, a derived topic algebra, the `Work*` envelope
family, the artifact + `.ready` readiness contract, websocket snapshot/patch, and a
reflected-Dhall-schema one-binary role model). This tracks three surfaces, each
tracked in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md):

- **Phase 4** — the **Coordinator** now owns explicit topic-lifecycle
  reconciliation from the typed runtime graph, and the binary emits its own
  reflected Dhall schema through `infernix internal dhall-schema
  host|cluster|secrets|substrate`. Per Phase 8, there are **no version-controlled
  `.dhall` files**: the schema exists only as the reflected output of the Haskell
  decoder types, emitted on demand.
- **Phase 6** — phase validation moves to **single-accelerator-per-phase** (standards
  §Q): one of `apple-silicon` or `linux-gpu` plus `linux-cpu`, never both;
  `cohort-validation-waves.md` is repurposed as per-accelerator attestation ledgers.
- **Phase 7** — the demo frontend now runs as the one-binary **Webapp** role through
  `infernix service --role webapp`; the former two-binary split is closed in the cleanup ledger.

Any still-present compatibility or consolidation surfaces are listed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) rather than hidden in phase
status prose.

## June 2026 Audit Follow-On Reopen

A full documentation/code audit reopened three bounded follow-ons without disturbing the prior
validation record for the already-closed work:

- **Phase 4 Sprint 4.24** — replace the duplicated Pulsar result timestamp `show` / partial `read`
  conversion with the same safe ISO-8601 codec used by `Storage.hs`.
- **Phase 6 Sprint 6.34** — close documentation-lint coverage gaps and no-env/no-PATH enforcement
  drift in pre-manifest or lint-owning code.
- **Phase 7 Sprint 7.28** — make generated artifact object ownership Haskell-derived from
  `userId` + `contextId` so adapter/native outputs cannot bypass the per-user
  `users/<sub>/contexts/<ctx>/generated/` layout. Closed 2026-06-30 by the full selected
  `linux-gpu` plus `linux-cpu` cohort gate.

The legacy or duplicate surfaces targeted by those sprints are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## MT3 Catalog Replacement (closed by Wave P)

The 2026-06-30 replacement of the obsolete MT3 residual with `music-mt3-infer` and
`music-mr-mt3` reopened **Phase 4 Sprint 4.22** and **Phase 6 Sprint 6.35** (the Wave O follow-on).
Both rows bind through `mt3-infer` on the PyTorch adapter, use model-cache staged weights, disable
upstream auto-downloads, and are generated for `linux-cpu`, `linux-gpu`, and `apple-silicon` (Apple
uses PyTorch CPU; no MPS claim is made). The old `music-mt3-jax` residual is removed and recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

Wave O is **closed** — proven by [Wave P](cohort-validation-waves.md) on 2026-07-04: rebuilt
`linux-gpu` **and** `linux-cpu` full-suite `infernix test all` both GREEN with routed Playwright
**9/9** over the expanded catalogs, including `music-mt3-infer`, `music-mr-mt3`, and the 27 GB
`video-wan21-t2v` row (the clean `linux-gpu` 9/9 landed once Phase 8 Sprint 8.5 eager model-cache
staging shipped). The per-attempt CPU dependency-resolution chronology is recorded in the Wave O row
of [cohort-validation-waves.md](cohort-validation-waves.md).

## Resource Admission Doctrine Reopen (2026-07-09)

The FIFO/serialized RAM guard added in Phase 4 Sprint 4.26 was the right direction, but the
implementation made capacity a catalog-wide startup failure and encoded the runtime failure as
stringly successful inline output. The current doctrine reopens Phases 4, 5, and 6:

- **Phase 4 Sprint 4.27** — replace the Apple-only integer budget and config-time fail-fast with a
  pure `InferenceMemoryBudget` / `InferenceError` model. One oversized model must not invalidate the
  daemon; runtime admission rejects only that request with typed `ModelMemoryLimitExceeded` carrying
  `requiredMib` and `availableMib`.
- **Phase 5 Sprint 5.11** — thread typed inference errors through browser contracts and render the
  demo-app capacity message from the ADT fields, not from parsed text.
- **Phase 6 Sprint 6.38** — validate the doctrine across substrates: Apple unified host RAM without
  hardcoded floors, Linux CPU engine pod memory limit, Linux GPU VRAM, and classifier assertions by
  constructor and MiB quantities.

The superseded fail-fast and stringly-result surfaces are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

Code-side closure landed on 2026-07-09 and was tightened on 2026-07-10 after the live CPU browser
matrix exposed fast failed-result reducer races around snapshots, patches, rendered-context
staleness, and locally submitted prompts. Rebuilt Linux CPU image
`sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306`
contains the current reducer fixes and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke,
and rebuilt-image `infernix test unit` (Haskell unit plus web `80/80`). Its full `linux-cpu`
rerun passed Haskell style, Python `check-code`, Haskell unit, web `80/80`, and the full live
integration lane, then routed Playwright reached `15/16` and failed only the visible
capacity-message assertion after the typed terminal payload. Current source adds a per-context
conversation cache so inactive or transiently stale patches are retained without displacing the
rendered pane; focused mounted-source PureScript validation passes `81/81`. Rebuilt image
`sha256:5ccdac2c89b435c1452f63c7fc5df41ca07893bfabc581134aef95db0468ace9` contains that cache fix
and passes rebuilt-image `infernix test unit` (Haskell unit plus web `81/81`). Its full rerun
reached PostgreSQL lifecycle rebinding after the typed-admission, HA, throughput, and
platform-recovery checks, then hung inside the second `cluster up` warm-cache path with an idle
MinIO NodePort connection. Current source bounds the MinIO warm-cache/model-bootstrap HTTP calls in
`Infernix.Runtime.Pulsar` (`HEAD` sentinel probes 15s, write responses 300s), and focused
mounted-source Haskell validation passes `cabal test infernix-unit`. Rebuilt image
`sha256:f0276a2efcae1fa7b2d33a7bb7a0e442b9d4c2be5687515c439f9cb75bf909ec` contains the timeout
fix and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun failed before
runtime validation on a Haskell style import-order diff in `Infernix.Runtime.Pulsar`; current
source applies the style-only reorder, and focused mounted-source validation passes
`cabal test infernix-haskell-style`. Rebuilt image
`sha256:5d423bd3d988103e6777fcfa80b92da07684263af056f7e6c9395e4802176cec` contains that style fix
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full rerun passed the front gates and
advanced through typed CPU admission, HA/recovery, model-bootstrap deduplication, throughput
(`totalPrompts = 12`, `p95Seconds = 65.50490140914917`), Harbor/MinIO/Pulsar recovery, and
PostgreSQL failover before stalling in the lifecycle-rebinding second `cluster up` while
republishing Harbor images; diagnostics showed the integration process sleeping with a direct
`[docker] <defunct>` child. Current source replaces the monitored subprocess waiter in
`Infernix.ProcessMonitor` with a blocking reaper plus heartbeat loop; focused mounted-source
validation passes `cabal test infernix-haskell-style` and `cabal test infernix-unit` with that
module mounted into the Linux CPU launcher image. Rebuilt Linux CPU image
`sha256:ab2f12cd81a094ffc267eacfb637ae055c8b3c8cd31e364dfc2f54cbcdf21597` contains the monitor fix
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun advanced past the
previous monitored-publish stall and through typed CPU admission, HA replacement/drain, and clean
cluster teardown, but failed in the model-bootstrap failover/deduplication integration step after
timing out on the ready topic for `integration-bootstrap-chaos-1783761854482798`.
Current source carries the bootstrap-failover remediation: exact bootstrap request replays remain
publishable across uncertain coordinator failover, ready-event deduplication is scoped to the
request attempt, and bootstrap credential-load failures nack rather than acking a no-ready path.
Focused mounted-source validation passes `cabal test infernix-haskell-style` and
`cabal test infernix-unit` for that remediation. Rebuilt Linux CPU image
`sha256:534f631468380d9e59df713e4e8c78b976e17b17e0c64eb09be4eff8d6f41388` contains the remediation
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun passed the front
gates, full live integration, the previous model-bootstrap failover/deduplication gate, PostgreSQL
lifecycle rebinding, anti-affinity, and the `demo_ui = false` lifecycle. Routed Playwright passed
`15/16`, including the Sprint 9.9 logout/account-switching specs and artifact coverage, then failed
only the browser matrix visible capacity-result assertion after receiving the typed terminal
`ModelMemoryLimitExceeded` payload. Current source now projects the rendered chat pane from the
active context id plus the per-context conversation cache so a stored terminal result for the
selected context cannot remain hidden behind a stale `activeConversation` pane, and the Playwright
assertion now names the model/context if this path regresses again. Focused mounted-source
PureScript validation passes `82/82`, and `node --check web/playwright/inference.spec.js` passes for
the diagnostic assertion. Rebuilt Linux CPU image
`sha256:e09f824b06b489a574288dbafcf1c8cc5920ae0bcb1a96cea91306a6cd57221c` now contains that
render-projection fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and
rebuilt-image `infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun
passed Haskell style, Python `check-code`, Haskell unit, web `82/82`, and full live integration
after inactive Docker build-cache cleanup recovered the host from `0` bytes free; throughput
recorded `totalPrompts = 12`, `p95Seconds = 86.15112495422363`, retained lifecycle rebinding,
anti-affinity, and the `demo_ui = false` lifecycle all passed. Routed Playwright again reached
`15/16` and failed only the browser matrix capacity-result render assertion for
`audio-demucs-htdemucs`; the new diagnostic showed the target context was active before the DOM
result wait. Current source now ignores stale WebSocket messages from superseded connection
generations, keeps one live per-context stream per WebSocket session, and waits for the subscribed
conversation snapshot before matrix submissions. Focused mounted-source validation now passes
`cabal test infernix-haskell-style infernix-unit` with `src/Infernix/Demo/WebSocket.hs` mounted,
web unit `82/82` with `web/src/Main.purs` and `web/playwright/inference.spec.js` mounted, and
`node --check web/playwright/inference.spec.js`. Rebuilt Linux CPU image
`sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d`
(`20070899656` bytes, created `2026-07-11T11:57:16.110576974-04:00`) contains this fix and passes
`./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`).
Its full `linux-cpu` rerun passed the front gates and full live integration, including typed
admission for the six over-budget rows, HA/recovery, model-bootstrap failover/deduplication,
throughput (`totalPrompts = 12`, `p95Seconds = 65.46250057220459`), PostgreSQL lifecycle rebinding,
anti-affinity, and `demo_ui = false`. Routed Playwright reached `15/16`: auth/RBAC/logout switching
and artifact upload/preview/download were green, and the matrix observed the typed terminal
`ModelMemoryLimitExceeded` payload for `audio-demucs-htdemucs`, but the visible capacity-result DOM
assertion still failed. Current source now gives browser-facing Pulsar readers unique per-stream
names and tags Playwright-observed WebSocket frames by browser socket generation, so the matrix waits
for live-generation snapshots and terminal patches instead of accepting stale frames from a
superseded socket. `node --check web/playwright/inference.spec.js` passes for that helper change,
`git diff --check` is clean for the touched files, and mounted-source Haskell validation passes
`cabal test infernix-haskell-style infernix-unit` with `src/Infernix/Runtime/Pulsar.hs` mounted
into the Linux CPU launcher image.
Earlier machine-independent gates also passed `infernix test lint`,
`infernix lint files|docs|proto|chart`, `infernix docs check`, and an integration-suite compile
preflight. The reopened sprints are closed by [Wave T](cohort-validation-waves.md): `linux-cpu`
passed full routed evidence on image
`sha256:c911771090115baa928d6bf43f14ef804cfcdc8706bc96ab3fe6b62f48a19a6f`, and the selected
`linux-gpu` accelerator passed `./bootstrap/linux-gpu.sh test` on image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896` with full live
integration and routed Playwright `16/16`.

## Phase 9 UAT Auth Residual (2026-07-09)

A later UAT pass surfaced a Phase 9 admin-vs-user access issue recorded in repo-root `notes.txt`.
The issue is now diagnosed and code-side closed: local-only Sign out left the Keycloak SSO browser
session alive, so switching from a self-registered user to the separate admin login could silently
reuse the non-admin session. Sprint 9.9 adds a real Keycloak logout redirect and a routed browser
regression for user-to-admin switching. Phase 9 is closed by [Wave U](cohort-validation-waves.md),
which recorded routed `linux-cpu` evidence and selected `linux-gpu` evidence for the new
logout/account-switching behavior.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Maintenance rules for the development plan |
| [00-overview.md](00-overview.md) | Architecture baseline, hard constraints, substrate contract, and canonical repository shape |
| [system-components.md](system-components.md) | Authoritative component inventory and state-location map |
| [cohort-validation-waves.md](cohort-validation-waves.md) | Per-accelerator attestation ledgers (one per accelerator) under Section Q's single-accelerator-per-phase rule; a `linux-cpu` aggregation phase merges them |
| [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) | `documents/` suite bootstrap plus the substrate-doctrine documentation reset |
| [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) | Repository scaffold, CLI contract, build-root doctrine, launcher ownership, and substrate-selection closure |
| [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) | Kind bootstrap, manual PV doctrine, Harbor-first image flow, substrate `.dhall` publication, Linux launcher closure, and lifecycle-progress hardening |
| [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) | Mandatory local HA platform services, Envoy Gateway ownership, publication contract, and the Apple cluster-to-host inference bridge for routed demo traffic |
| [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) | Haskell runtime, shared Python adapter project, cluster-daemon request consumption, Apple host inference execution, staged `.dhall` role control, and Pulsar production inference |
| [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) | PureScript demo UI, generated frontend contracts, clustered demo hosting, Apple host-backed browser dispatch, and Playwright ownership |
| [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) | Static quality, README-matrix-driven single-substrate validation, Apple cluster-to-host daemon split coverage, root-doc closure, HA validation, and false-negative doctrine hardening |
| [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) | Multi-user durable-context demo: Keycloak auth, WebSocket transport, Pulsar-backed conversation history, MinIO artifact upload/download/render-or-download, Haskell-first logic via purescript-bridge, and the three-role daemon split (stateless frontend, stateless coordinator, substrate-specific engine pools) with an HA-first chart |
| [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) | Adopt the hostbootstrap Dhall doctrine: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (incl. ConfigMap/Secret bodies; Helm only embeds a string), explicit `init` / `test init` creation with ordinary commands failing fast when config is missing and Apple bootstrap `up` explicitly running `init --if-missing`, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging from the mounted `infernix.dhall` (replacing the lazy per-inference bootstrap) |
| [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md) | Role-based access control and monitoring: the admin (cluster-wide operator consoles + monitoring) vs. user (own chat/artifacts/files + personal dashboard) split, Keycloak admin role + JWT role claim, edge admin authorization with ungated-route closure, admin/personal dashboards, per-user MinIO STS defense-in-depth, and the Apple host-worker loopback data-plane invariant |
| [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) | Explicit cleanup and removal ledger |

## Status Vocabulary

| Status | Meaning |
|--------|---------|
| `Done` | Implemented, validated, docs aligned, no remaining work |
| `Active` | Partially implemented; remaining work is explicit |
| `Blocked` | Waiting on named prerequisites |
| `Planned` | Ready to start; dependencies are already satisfied |

## Definition of Done

A phase or sprint can move to `Done` only when all of the following are true:

1. The listed implementation paths exist in the current worktree.
2. The listed validation gates pass on the supported execution path, with the phase's **single
   chosen accelerator** cohort (`apple-silicon` **or** `linux-gpu`) plus `linux-cpu` recorded when
   substrate-aware behavior is in scope — never both accelerators against one phase.
3. The governed docs named in `Docs to update` match the implementation.
4. No remaining cleanup or compatibility surface is left unstated.
5. Cleanup promised by the sprint is reflected in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

`Done` is the single-accelerator sign-off gate (item 2's one-accelerator-plus-`linux-cpu` evidence).
It is distinct from *code-side closure* — the implementation plus the machine-independent gate set —
which is completed in natural phase order on a single machine and is the gate to begin the *next*
phase's implementation. A phase whose code-side closure is complete but whose single chosen
accelerator full-suite is still pending stays `Active` with a named `Cohort gate` residual; that
residual does not block the next phase's implementation. See the single-accelerator execution rule in
[development_plan_standards.md](development_plan_standards.md) Section Q, and the shared
[../documents/architecture/pulsar_ml_workflow.md](../documents/architecture/pulsar_ml_workflow.md)
contract.

## Current Repo Assessment

The June 2026 audit reopened Phase 4, Phase 6, and Phase 7 for the bounded follow-ons listed above.
Earlier sprint closure evidence remains valid for its original scope. Phase 4 Sprint 4.24 is now
re-closed, Phase 6 Sprint 6.34 is now re-closed for no-env/docs-lint coverage, and Phase 7 Sprint
7.28 is now re-closed for generated-artifact ownership after the full selected `linux-gpu` plus
`linux-cpu` cohort gate and matching deletion-ledger move. The MT3 catalog-replacement follow-on
(Phase 4 Sprint 4.22 and Phase 6 Sprint 6.35) closed under [Wave P](cohort-validation-waves.md) on
2026-07-04. The later 2026-07-06 Wave Q review cohort-validated the Phase 9 access-control/monitoring
RBAC/STS/dashboard surface on both `apple-silicon` and `linux-cpu`, and reopened Phases 4 and 6 for
the matrix substrate-accuracy hardening (Sprints 4.25 and 6.36) plus the 2026-07-07 apple-silicon
inference RAM-safety gap (Sprints 4.26 and 6.37). [Wave R](cohort-validation-waves.md) (2026-07-08)
and [Wave S](cohort-validation-waves.md) (2026-07-09) closed those sprints for their implemented
scope.

On 2026-07-09, the resource-admission doctrine reopened **Phase 4 Sprint 4.27**, **Phase 5 Sprint
5.11**, and **Phase 6 Sprint 6.38**. Code-side closure is now complete: serialized/FIFO runtime
admission remains, the catalog-wide fail-fast is removed, hardcoded budget floors are replaced with
typed `InferenceMemoryBudget` semantics, admission extends to Linux CPU pod memory and Linux GPU
VRAM, and capacity failures publish typed `InferenceError.ModelMemoryLimitExceeded` payloads with
explicit MiB quantities. Wave T's `linux-cpu` full live-suite gate closed on 2026-07-12 with a
rebuilt image carrying the explicit tagged `InferenceError` WebSocket contract fix; the selected
`linux-gpu` accelerator gate also closed on 2026-07-12 with full `./bootstrap/linux-gpu.sh test`.
A later UAT pass also surfaced Phase 9's
logout/account-switching issue (repo-root `notes.txt`); Sprint 9.9 diagnoses and closes it
code-side, with Wave U's `linux-cpu` and selected `linux-gpu` routed evidence now green.

The 2026-07-15 Managed-State-Transition Doctrine reopen (Sprints 0.13, 1.16, 2.14, 3.14, 4.28, 5.12,
6.39, 7.29, 8.7, 9.10) and the 2026-07-19 Bounded-Command Application & Bounded-HTTP reopen (Sprints
0.14, 1.17, 3.15, 4.29, 6.40, 6.41) are now **closed by [Wave V](cohort-validation-waves.md)**
(2026-07-20): the `apple-silicon` accelerator plus `linux-cpu` full-suite `infernix test all` both ran
GREEN over one frozen worktree — apple integration 16/16 real per-model inference plus routed
Playwright `16/16`, and `linux-cpu` integration (real inference for the in-budget rows, typed
`ModelMemoryLimitExceeded` admission for the six over-budget rows, full HA/throughput/lifecycle) plus
routed Playwright `16/16`. Sprint 6.41's twelve-wait readiness migration onto
`awaitReadiness`/`budgetDeadline` and the `threadDelayViolations` lint gate were completed and
adversarially reviewed under Wave V. With Wave V, all ten phases are `Done`. The run surfaced and Wave V
records four cohort fixes: the Apple `materialize-metal-engines` prerequisite, the pytorch-engine
`mt3-infer <0.2` and linux-arm64 `demucs <4.1` dependency-drift caps, and the `docker/Dockerfile`
engine-venv fail-fast (a silently-masked venv-install failure now fails the build).
Post-closure current-source verification on 2026-07-20 also found and closed one Phase 7 artifact UI
timing race: the Apple aggregate rerun passed lint/unit/integration before failing only the routed
artifact upload/preview/download spec, `web/src/Infernix/Web/ArtifactTransport.js` now updates the
matching current artifact preview before marking the download grant ready, and focused Apple routed
E2E passed `16/16` plus web unit `83/83` on rebuilt image
`sha256:69c488b775e3f2d896f037e4856543799882994be51bbfb902f57e81815d167a`.

Wave T chronology (2026-07-10 onward): rebuilt image
`sha256:05e0aadf5ea0feb98f25e82ab196f23893be0441e59f5e91f9fec346bfa6d8c0` passed the `linux-cpu`
full live integration lane and web unit `75/75`, but the full `linux-cpu` gate remained open after
routed Playwright ended `14/16` on the known artifact-preview grant timing case plus the typed
capacity-message render race. Current source has a focused `76/76` PureScript pass for the
cross-context snapshot fix and an artifact-helper readiness fix. Rebuilt image
`sha256:c01a9a070ca842b973543301dcbaaa039811492f707fdc20c804aa30bd5f40ee` now passes
`./bootstrap/linux-cpu.sh build` plus rebuilt-image `infernix test unit` with web `76/76`, and its
full-suite rerun passed integration plus routed Playwright `15/16`. The remaining matrix failure is
the visible capacity message after an active-context switch; current source now seeds the active
context from a matching patch when the stored conversation still belongs to a previous context, and
focused mounted-source PureScript validation passes `77/77`. Rebuilt image
`sha256:84e3915260e5fd7684b817bf520e9eaca4f40946665d86ae2afb5276b1eedfcb` now contains this latest
fix and passed the `./bootstrap/linux-cpu.sh build` CLI-help smoke plus rebuilt-image
`infernix test unit` (Haskell unit plus web `77/77`). Its full-suite rerun passed the front gates
and the live integration path through typed CPU admission, smaller-model continuity, HA/chaos,
throughput, platform recovery, lifecycle rebinding, and anti-affinity, then failed in the later
lifecycle cluster-up after the retained Pulsar repair path reset claim roots once and the same
dirty-metadata signal recurred. Current source now allows a bounded number of retained Pulsar claim
root resets per `cluster up`. Rebuilt image
`sha256:0bf82aba452b2bee8f5de6c4ee136c7d72537ac0dbd4377ee52ee3718d77c0aa` contains that fix and
passed `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `77/77`). Its full-suite rerun passed the front gates
and full live integration, including typed CPU admission, smaller-model continuity, HA/chaos,
throughput (`totalPrompts = 12`, `p95Seconds = 82.15346002578735`), platform recovery, lifecycle
rebinding, anti-affinity, and the `demo_ui = false` lifecycle; repeated retained-data cluster-ups no
longer hit the prior dirty Pulsar metadata failure. Routed Playwright reached `15/16` and passed the
Sprint 9.9 auth/RBAC/account-switching specs plus artifact upload/download grants; the remaining
failure is the browser matrix visible capacity message after receiving a typed terminal
`ModelMemoryLimitExceeded` payload. Current source now keeps applying same-context patches when the
rendered conversation already targets that context even if `activeContextId` is transiently stale,
adds a raw Haskell-wire `ModelMemoryLimitExceeded` WebSocket decode regression, and passes focused
mounted-source PureScript validation at `79/79`. Rebuilt image
`sha256:4e2e2a9f642ecc15635df849539b82a847d350db19e161cf6517d56a29ea6b62`
contains that reducer/decode fix and passed `./bootstrap/linux-cpu.sh build` plus the CLI-help
smoke and rebuilt-image `infernix test unit` (Haskell unit plus web `79/79`). Its full-suite rerun
again passed Haskell style, Python `check-code`, Haskell unit, web `79/79`, full live integration,
throughput (`totalPrompts = 12`, `p95Seconds = 65.4941475391388`), platform recovery, lifecycle
rebinding, anti-affinity, and the `demo_ui = false` lifecycle, then routed Playwright reached
`15/16` and failed only the same visible capacity-message assertion after receiving the typed
terminal payload. Current source now pins the submitted prompt into the active conversation before
the fast terminal result can arrive and adds a stale-active-id rendered-context reducer regression.
Rebuilt image `sha256:1374398c498e4fd38e27991c2fe5cc5d4b1b9c19c1f9ace01b23e0722f3ff306`
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `80/80`). Its full `linux-cpu` rerun passed Haskell
style, Python `check-code`, Haskell unit, web `80/80`, and full live integration, including typed
CPU admission, smaller-model continuity, platform recovery, lifecycle rebinding, anti-affinity, and
the `demo_ui = false` lifecycle; routed Playwright again reached `15/16` and failed only the
visible capacity-message DOM assertion after receiving the typed terminal payload. Current source
now stores conversations per context and preserves inactive/stale terminal patches for later
rendering; focused mounted-source PureScript validation passes `81/81`. Rebuilt Linux CPU image
`sha256:5ccdac2c89b435c1452f63c7fc5df41ca07893bfabc581134aef95db0468ace9` contains that cache fix
and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full rerun passed the front gates and
progressed through PostgreSQL lifecycle rebinding, then hung in the second `cluster up` warm-cache
path with an idle MinIO NodePort connection. Current source bounds the MinIO
warm-cache/model-bootstrap HTTP calls in `Infernix.Runtime.Pulsar`, and focused mounted-source
Haskell validation passes `cabal test infernix-unit`. Rebuilt image
`sha256:f0276a2efcae1fa7b2d33a7bb7a0e442b9d4c2be5687515c439f9cb75bf909ec` contains the timeout
fix and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). Its full `linux-cpu` rerun failed before
runtime validation on a Haskell style import-order diff in `Infernix.Runtime.Pulsar`; current
source applies the style-only reorder, and focused mounted-source validation passes
`cabal test infernix-haskell-style`. Rebuilt image
`sha256:5d423bd3d988103e6777fcfa80b92da07684263af056f7e6c9395e4802176cec` contains that style fix
and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `81/81`). A later full `linux-cpu` rerun on
`sha256:534f631468380d9e59df713e4e8c78b976e17b17e0c64eb09be4eff8d6f41388` passed the front gates
and full live integration, then routed Playwright reached `15/16` and failed only the visible
capacity-result assertion after receiving the typed terminal payload. Current source projects the
rendered chat pane from the active context id plus the per-context conversation cache; rebuilt Linux
CPU image `sha256:e09f824b06b489a574288dbafcf1c8cc5920ae0bcb1a96cea91306a6cd57221c` contains that
fix and passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front
gates and full live integration, including typed CPU admission, throughput
(`totalPrompts = 12`, `p95Seconds = 86.15112495422363`), lifecycle rebinding, anti-affinity, and
the `demo_ui = false` lifecycle; routed Playwright reached `15/16` and failed only the
`audio-demucs-htdemucs` visible capacity-result assertion after proving the target context was
active. Current source hardens stale WebSocket generation handling and subscription readiness. The
focused mounted-source gates now pass: Haskell style/unit for `src/Infernix/Demo/WebSocket.hs`, web
unit `82/82`, and `node --check web/playwright/inference.spec.js`. Rebuilt Linux CPU image
`sha256:3161a3846bbc42a97febb186f5fbe063ca0a407cdab5bc888a798e170ef23e3d` contains the fix and
passes `./bootstrap/linux-cpu.sh build` plus the CLI-help smoke and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front
gates and full live integration, then routed Playwright reached `15/16` and failed only the
`audio-demucs-htdemucs` visible capacity-result assertion after the matrix observed the typed
terminal payload. Current source now gives browser-facing Pulsar readers unique per-stream names
and tags Playwright-observed WebSocket frames by socket generation, so waits are tied to the live
browser connection. Rebuilt Linux CPU image
`sha256:eeb58064f9eca14c008b9c976380c5c7745a4c6079a5bd8885b3935c864532a5`
(`20070858505` bytes, created `2026-07-11T14:49:26.455414736-04:00`) contains that fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, including typed CPU admission for the six over-budget rows, smaller-model continuity,
throughput (`totalPrompts = 12`, `p95Seconds = 65.51375341415405`), lifecycle rebinding,
anti-affinity, and the `demo_ui = false` lifecycle. Routed Playwright reached `14/16`: the artifact
spec hit a download-button replacement race after `data-download-status="pending"`, and the matrix
still failed the `audio-demucs-htdemucs` visible capacity-result assertion after validating the
typed terminal payload. Current source waits for the artifact upload record echo before Download,
retries against a re-resolved artifact card until the download grant is ready and the URL is the
webapp proxy, and scopes the capacity-result DOM wait to the exact typed memory message with a
resubscription fallback. `node --check web/playwright/inference.spec.js` and `git diff --check` pass
for this follow-up. Rebuilt Linux CPU image
`sha256:d49b4799375df7a0e5726d16717ab6dc4e09fc8baa685969484099027f81c4c8`
(`20070886873` bytes, created `2026-07-11T17:27:02.378037428-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration, including typed CPU admission for the six over-budget rows, smaller-model continuity,
throughput (`totalPrompts = 12`, `p95Seconds = 69.06893110275269`), lifecycle rebinding,
anti-affinity, and the `demo_ui = false` lifecycle. Routed Playwright reached `15/16`: the artifact
upload/preview/download spec passed, but the browser matrix still failed the
`audio-demucs-htdemucs` visible capacity-result assertion after resubscription. The next Wave T gate
is the capacity-result render fix, a clean full `linux-cpu` rerun, and the selected `linux-gpu`
accelerator gate. Current source now correlates the matrix terminal result to the server prompt
message id for the exact submitted prompt; `node --check web/playwright/inference.spec.js` and
`git diff --check` pass for that follow-up. The next validation gate is rebuilt-image unit evidence
and a clean full `linux-cpu` rerun with this correlation fix. Rebuilt Linux CPU image
`sha256:30d597efe4284a74c606860d7a0ef6d4fd5123076de11ad0c8e3da476925190e`
(`20070997197` bytes, created `2026-07-11T20:08:36.089424841-04:00`) contains the fix and passes
`./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image `infernix test unit`
(Haskell unit plus web `82/82`). Its full `linux-cpu` rerun passed the front gates and full live
integration (`totalPrompts = 12`, `p95Seconds = 65.60747718811035`) with the known
`music-omnizart` warm-cache HTTP 403 warning, then routed Playwright reached `15/16`: Sprint 9.9
auth/RBAC/logout switching and artifact coverage were green, but the matrix still failed the
`audio-demucs-htdemucs` visible capacity-result assertion after resubscription. Current source
strengthens that fallback to require a new-socket conversation snapshot or patch containing the
matching typed capacity result before asserting the DOM; `node --check web/playwright/inference.spec.js`
and `git diff --check` pass. Rebuilt Linux CPU image
`sha256:681420399273889da1e64ce6e43576ffe8a06ad87114b8e069903ab79d3d92f9`
(`20070973633` bytes, created `2026-07-11T22:49:09.072629435-04:00`) contains that
fallback and passes `./bootstrap/linux-cpu.sh build`, the CLI-help smoke, and rebuilt-image
`infernix test unit` (Haskell unit plus web `82/82`). The next validation gate is a clean full
`linux-cpu` rerun on this image, then the selected `linux-gpu` accelerator gate. The full rerun on
that image passed the front gates and live integration (`totalPrompts = 12`, `p95Seconds =
70.42682695388794`) with the known `music-omnizart` warm-cache warning, then routed Playwright
reached `15/16`: Sprint 9.9 auth/RBAC/logout switching and artifact coverage were green, but the
matrix still failed the `audio-demucs-htdemucs` visible capacity-result assertion even after a
result-bearing resubscription attempt.

Latest Wave T update (2026-07-12): rebuilt Linux CPU image
`sha256:c911771090115baa928d6bf43f14ef804cfcdc8706bc96ab3fe6b62f48a19a6f`
(`20088000300` bytes, created `2026-07-12T02:30:27.200982353-04:00`) contains the
explicit tagged `InferenceError` WebSocket contract fix. It passed `./bootstrap/linux-cpu.sh build`,
the CLI-help smoke, rebuilt-image `infernix test unit` (Haskell unit plus web `83/83`), and
rebuilt-image `infernix test e2e`: the full routed suite passed `16/16` in 3.6 minutes, including
the per-model browser matrix in 2.5 minutes, Sprint 9.9 auth/RBAC/logout/account-switching, and
artifact upload/preview/download coverage. The live integration portion again proved typed Linux CPU
capacity admission, smaller-model continuity, HA/chaos, lifecycle, and throughput behavior with the
known non-blocking `music-omnizart` warm-cache warning. This closes Wave T's `linux-cpu` Stage 2
evidence. The selected `linux-gpu` accelerator gate also closed on rebuilt image
`sha256:0b238faa40e6edea9907408f426d25c2a1ec9810e17fcc65b770f51fbb34b896`: `./bootstrap/linux-gpu.sh test`
passed full live integration and routed Playwright `16/16`, including the per-model browser
matrix and typed GPU capacity-message path.

Prior closure evidence closes around the implemented worktree. Phase 3 Sprint 3.12 and
[Wave F](cohort-validation-waves.md) closed on the recorded validation after native `linux/arm64` validation
through the already selected arm64 Docker daemon on this Apple Silicon machine. The repository implements the
explicit-init runtime-config architecture, the baked Linux outer-container launcher,
the mandatory HA platform services, the Gateway-owned routed edge, the shared Python adapter
project, the Haskell-owned browser-contract generation path, the substrate-specific validation
surface, and the current Apple split-executor topology described below. The runtime-routing
code-side target has landed around substrate-neutral engine pools: the coordinator remains the
production router, normal pools use Pulsar `Shared` plus broker-native backpressure, pinned routes
use derived per-member topics with `Exclusive`, Linux members are Kubernetes workloads, and Apple
members are same-binary host daemons selected by stable host id. Legacy raw-topic compatibility
surfaces, the demo-off coordinator gate, and the two-binary `infernix` / `infernix-demo` split have
all been removed; the supported topology is the one-binary model with the demo frontend served by
the `Webapp` role through `infernix service --role webapp`.

The repository implements the runtime-config doctrine described by this plan. `infernix init`
creates the operator's repo-root `./infernix.dhall` and `./infernix-host.dhall`;
`infernix test init` creates the harness input `./infernix.test.dhall`. Ordinary
config-dependent commands validate the initialized file and fail fast naming the required init
instead of auto-materializing it. The Linux substrate image uses binary-owned generation for its
image-local defaults, not an ordinary-command preflight path. Focused `infernix lint ...` and
`infernix docs check` remain config-independent. The final runtime payload also
distinguishes cluster and host daemon
roles: cluster-role configs name the substrate, request and result topics, and the engine-pool graph,
while host-role Apple configs include the routed Pulsar connection details and the host member's pool
membership. Cluster publication mirrors the cluster-role payload locally under
`./.data/runtime/configmaps/infernix-demo-config/` and mounts it inside cluster workloads at the
compatibility path `/opt/build/infernix-substrate.dhall`, while Apple host daemons read repo-root
`./infernix.dhall`. The file is a typed Dhall record decoded in-process by the `dhall` Haskell
library.
`infernix test all`
runs the full supported validation suite for the active initialized substrate; full repository substrate
closure comes from separate governed reruns for `apple-silicon`, `linux-cpu`, and `linux-gpu`,
not from one implicit cross-substrate matrix invocation. The generated file, `cluster status`,
publication JSON, and generated browser contracts still serialize that active substrate under
`runtimeMode` field names. `cluster status` does not mutate Kubernetes resources, publication
state, or authoritative repo-local state; the accepted Linux outer-container exception is an
idempotent Docker network membership repair that attaches the fresh launcher container to the
private `kind` network for observation. The Apple split-executor contract is implemented on
`apple-silicon`: `cluster up` keeps Harbor, MinIO, Pulsar, PostgreSQL, Envoy Gateway, the optional
clustered `infernix-demo` surface, and cluster `infernix-coordinator` Deployment in Kind; Apple
inference execution remains host-native. The pool target replaces the single Apple host topic and
Linux-specific per-engine topic special cases with topics derived from `(runtimeMode, pool id, model
id, optional member id)`. The generated final-phase Helm values use role-specific
coordinator and engine knobs; Apple sets the cluster engine replica count to 0 because Apple engine
members are host-native. Pulsar-owned topics, `Shared` pool subscriptions, `Exclusive` pinned routes,
and acknowledgement handling are the ordering and ownership boundary for request handoff,
inference, and result publication. The coordinator eagerly stages the configured model set in
`infernix-models` behind the `warm-model-cache` barrier; workers hydrate their derived local caches
from those staged objects and publish the typed per-family result surface. The selected `linux-gpu`
plus `linux-cpu` real-output proof closed on 2026-06-20, while
unsupported adapter ids fail fast instead of falling through to a generic success path.

Phase 1's real-Apple-engine reopen (Sprint 1.15) and the paired `linux-cpu` full-suite gate closed
under Wave L on 2026-06-29 (rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`): Haskell style, Python
`check-code`, unit, web `71/71`, full integration with every real `linux-cpu` output plus the
HA/chaos tail, and routed Playwright `9/9`; Apple Stage 2 integration and focused routed Playwright
are green. The per-rebuild image-digest chronology for that cohort's local-topology, memory-profile,
drain-target, and MinIO input-timeout remediations is recorded in the Wave L row of
[cohort-validation-waves.md](cohort-validation-waves.md).
The worktree omits the
direct Harbor, MinIO, and Pulsar tool-route compatibility handlers, requires the real routed
upstream behavior in integration, and persists Linux cluster state before later rollout phases.
Bootstrap shells no longer restage the active substrate payload before lifecycle commands; that
preflight belongs to the binary command that needs the file. The Haskell style bootstrap
installs `ormolu` and `hlint` through `cabal install` against the project `ghc-9.12.4`
toolchain into `./.build/haskell-style-tools/bin/`; the Linux substrate image installs a single
`ghc-9.12.4` toolchain. The
supported Linux outer-container launcher reuses the image-local
`/opt/infernix/chart/charts/` archive cache,
hydrates the MinIO dependency through the supported direct tarball path instead of Docker
Hub-backed OCI metadata, and detects the known stale Pulsar or ZooKeeper epoch mismatch by
resetting only the retained Pulsar claim roots and retrying `cluster up` once. The Apple
clean-host bootstrap verifies the selected ghcup-managed `ghc` and `cabal` executables before
direct `cabal install`, reconciles Homebrew `protoc`, and lets Apple adapter setup or validation
paths reconcile the Homebrew-managed `python@3.12` formula and `python3.12` command plus a
user-local Poetry bootstrap on demand. The supported doctrine now requires Docker-backed Apple
work to use an already selected native arm64 Docker daemon and forbids creating or switching
Docker contexts, creating Colima VMs, or using cross-architecture emulation; Phase 1 Sprint 1.12
replaced the previous Colima reconciliation path with selected Docker-context and
daemon-architecture validation and closed on the recorded validation with both the positive Apple lifecycle
gate and the negative no-daemon boundary gate. Phase 1 Sprint 1.14 closes the Apple Metal/Core ML
materialization lane under the Section Q single-accelerator rule: it removes the prior Sprint 1.13
`tart` / `hostTart` /
`AppleTart` implementation from the current host-tool schema and retargets the retained
`materialize-metal-engines` command to typed engine-artifact manifests. Phase 1 Sprint 1.15 builds
on that lane by replacing the former validation-wrapper payloads with real Apple native runner
roots for Core ML, MLX, llama.cpp/whisper.cpp Metal, CTranslate2, ONNX Runtime, and Audiveris,
plus indexed native snapshot hydration for Core ML Stable Diffusion. That Phase 1 native-engine
scope is closed by Wave L: Apple Stage 2 integration/focused routed Playwright are green, and the paired
`linux-cpu` full gate passed on the real Linux host on 2026-06-29 with rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`.
The target has no Tart VM, user
keychain dependency, host Xcode UI flow, or request-time toolchain install. The
Poetry bootstrap may reuse an already available
compatible Python 3.12+ executable when one passes the implemented version check. Routed Apple
Playwright validation runs host-native `npm exec` against the published `127.0.0.1` edge port,
and the in-image
Playwright runtime no longer bakes a conflicting `NO_COLOR` default. The shared cluster lifecycle
now surfaces explicit in-progress phase, child-operation detail, and heartbeat data through
`cluster status` during monitored Docker build, Harbor publication, Harbor-backed final-image
preload, and Apple retained-state replay steps; explicit substrate materialization writes the
staged `infernix.dhall` atomically so concurrent status readers do not observe truncated
payloads; retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
replicas from the current Patroni leader when timeline drift leaves replicas unready after
promotion; and all lanes scrub operator-managed Patroni claim roots before recreating claim
directories and after retained-state sync so regenerated database credentials are not paired with
stale Harbor or Keycloak data directories. The shared lifecycle skips broad pre-Harbor support-image
preloads and follows the
stricter Harbor-first target where supported lanes hydrate and stream only the narrow Harbor
warmup dependency set into Kind before Helm warmup, only Harbor-required services may pull
upstream before Harbor is responsive, and every remaining image, including the active `infernix`
runtime image, is loaded into Harbor before final rollout. Legacy validation proof points are
kept only in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md); current
replacement proof points are recorded by the Wave A Apple cohort closure and the Wave C native
Linux/CUDA cohort closure below. Sprint 6.26 closes the buildx, npm, GHCup shell-profile,
Python packaging, and
Playwright script warning cleanup with the governed `linux-gpu` lifecycle rerun complete.
Sprint 6.27 closes the staged-substrate format cleanup: `infernix.dhall` is now a real
typed Dhall record decoded in-process by the `dhall` Haskell library, with the schema reflected from
the substrate decoder type (`infernix internal dhall-schema substrate`; Phase 8 removed the tracked schema file).

**Cohort validation status (present development host = CUDA Linux).** The current workspace is a
real Linux CUDA host. Consistent with the Section Q single-accelerator doctrine, the remaining
Phase 1 Wave L paired `linux-cpu` gate was validated here before moving to the next open phase:
`./bootstrap/linux-cpu.sh test` passed on 2026-06-29 with rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`, covering Haskell style,
Python `check-code`, Haskell unit, web `71/71`, full integration with all real `linux-cpu` catalog
outputs and the HA/chaos tail, and routed Playwright `9/9`. The Apple-side Sprint 1.15 evidence
remains the prior Apple host validation: `./bootstrap/apple-silicon.sh build`,
`./.build/infernix internal materialize-substrate apple-silicon`, `./.build/infernix internal
materialize-metal-engines`, installed Metal/Core ML/CTranslate2/MLX/ONNX/Audiveris smokes, direct
Core ML imports for Basic Pitch plus Apple's Stable Diffusion pipeline, `./.build/infernix test
unit`, `./.build/infernix test lint`, Apple integration, and focused routed Playwright. The first
Stage 2 retries on the Apple host exposed, and the current source remediates, the native arm64
llama.cpp/whisper.cpp payload-selection bug and the default 8 GiB Apple Docker-daemon rollout
pressure by generating a single-replica Apple host-native local topology for Harbor, Pulsar,
coordinator, and demo while preserving the Linux HA-shaped defaults. Later Apple reruns advanced
past rebuilt-image build, Harbor publication, final memory scheduling, and Pulsar startup under
the single-replica topology. They exposed, and the current source remediates, the matching
single-bookie Pulsar quorum gap plus a real TinyLlama GGUF execution-time regression: the lazy
model-cache bootstrap now hydrates the real payload, and the Apple llama.cpp runner now uses a
bounded single-turn invocation with explicit context/thread/GPU-layer settings. The latest rerun
cleared TinyLlama and then exposed the `llm-qwen15-mlx` cache path as an indexed native snapshot
rather than a single `payload`; the worker now treats that MLX model id as a native snapshot
cache. The next Apple rerun completed the LLM and speech rows through MLX, whisper.cpp, and
CTranslate2, then exposed two catalog/dependency corrections: Apple PyTorch/Diffusers/Transformers
framework venvs now pin Darwin arm64 torch-family wheels to PyPI instead of the CUDA source, and the
multi-instrument music-transcription rows now use MT3-PyTorch and MR-MT3 through `mt3-infer`.
Linux values keep the HA-shaped quorum. The
earlier Apple integration/e2e/all evidence still proves the host-daemon routing, Pulsar transport,
engine-pool behavior, production `demo_ui = false` route posture, and image rebuild/reuse path, but
it was recorded before Sprint 1.15 replaced the validation-wrapper payloads and therefore does not
close the Wave L real-output gate. The CUDA Linux Wave K cycle closed the selected Phase 4/6
real-output proof for the then-active catalogs: `./bootstrap/linux-gpu.sh test` passed style, unit,
web unit, integration, and routed Playwright with the then-current `linux-gpu` browser matrix, and
rebuilt-image `./bootstrap/linux-cpu.sh test` passed the matching CPU full-suite lane. The
post-replacement MT3 proof for the rows added on 2026-06-30 closed under Wave P on 2026-07-04.
The legacy dated proof points (the recorded validation) are inventoried in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical
Validation Evidence"; the underlying contracts they exercised still describe supported behavior,
but the proof points themselves are not current. Revalidation is tracked by
[cohort-validation-waves.md](cohort-validation-waves.md). [Wave A](cohort-validation-waves.md)
(Apple cohort) closed on the recorded validation with `cabal test infernix-integration` full PASS plus 5/6
Playwright e2e PASS; Waves A.1 and A.2 subsequently closed the routed
Playwright residuals with 7/7 e2e PASS, and Wave A.3 closed Apple engine-lock chaos.
[Wave H](cohort-validation-waves.md) then re-confirmed the full Apple cohort lifecycle on the
Apple cohort host on 2026-06-09 from a clean build root: the build, lint/style/unit gates, the
explicit `cluster up` → `cluster status` → `cluster down` lifecycle with retained-state replay,
`infernix test integration`, `infernix test e2e` 9/9, and aggregate `infernix test all`.
[Wave C](cohort-validation-waves.md) closed on the recorded validation on a native Linux/CUDA host: the
portable `linux-cpu` full-suite gate passed on the recorded validation and the real `linux-gpu`
full-suite gate passed on the recorded validation. [Wave F](cohort-validation-waves.md) closed on the recorded validation
with native `linux/arm64` `linux-cpu` validation through the selected Docker daemon
(`server=linux/arm64`, runtime probe `aarch64` / `arm64`) and a full
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all`
PASS.

The production and routed validation path uses real Pulsar transport. The repository still keeps
the repo-local topic spool under `./.data/runtime/pulsar/` as a deliberate harness surface when
unit-level checks or manually isolated daemon runs intentionally omit Pulsar endpoint
configuration; that harness does not count as routed cluster evidence and does not replace the
Gateway-backed Pulsar assertions in integration or E2E validation.

Beyond the Phase 9 admin overview (`/api/admin/overview`) and per-user personal dashboard, no
general observability stack (metrics, tracing, log aggregation) is deployed.
Monitoring is not a supported first-class surface.

## Execution Contexts and Substrates

The plan keeps these concepts separate:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Supported substrate | `apple-silicon`, `linux-cpu`, `linux-gpu` | which substrate the initialized repo-root `./infernix.dhall` selects |

### Naming Note

The canonical NVIDIA-backed Linux substrate id is `linux-gpu`, and the implementation plus docs
now use that id consistently.

## Hardware Cohort Validation Cadence

Development and validation are organized around two physical host cohorts:

- **Apple Silicon cohort:** `./bootstrap/apple-silicon.sh ...` and direct
  `./.build/infernix ...` commands.
- **CUDA Linux cohort:** `./bootstrap/linux-gpu.sh ...` and the Compose-launched
  `docker compose run --rm infernix infernix ...` command surface.

> **Implement in natural phase order on whichever single machine is present, and validate each phase
> on exactly one accelerator plus `linux-cpu` — never both accelerators.** Every open phase has two
> independent axes. *Code-side closure* (Axis 1) is the implementation plus the machine-independent
> gate set — `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
> `infernix lint files/docs/chart/proto`, `infernix docs check`, the web unit suite, and
> `poetry run check-code`; completed in natural order on one machine, it is the gate to begin the
> *next* phase's implementation. *Single-accelerator sign-off* (Axis 2) is the hardware-specific
> full-suite for the phase's one chosen accelerator (`apple-silicon` Metal/Core ML, or `linux-gpu`
> CUDA) plus `linux-cpu`, recorded in `cohort-validation-waves.md`; it is the gate for `Done` and
> never the gate for moving on. A phase never requires the other accelerator; cross-accelerator
> coverage is split across sibling phases or merged by a later `linux-cpu`-only aggregation phase.

Phase work should stay on the current cohort until a coherent slice is ready. Validation-only
hardware residuals are queued in [cohort-validation-waves.md](cohort-validation-waves.md), but a
phase closes only on its chosen accelerator plus `linux-cpu`, not by alternating between Apple and
CUDA after each sprint. `linux-cpu` remains a portable CPU-only lane for native Linux amd64 and
native Linux arm64 hosts, but it does not run through Apple Silicon emulation and does not replace
the CUDA Linux cohort when a phase explicitly chooses `linux-gpu` for GPU behavior, CUDA image
construction, `nvkind`, or NVIDIA scheduling.

## Managed-State-Transition Doctrine Reopen (2026-07-15)

The teardown race, the CoreML unconditional-`.ready` failure, and the three routed-Playwright "flakes"
(Keycloak admin-token expiry, artifact-not-visible, and the smollm2 warm-proxy timeout) are one class:
**unmanaged state transitions** — code acting on a state whose transition it never managed, on hope
rather than on typed evidence. The new
[managed state transitions doctrine](../documents/architecture/managed_state_transitions.md)
generalizes the results-side realness contract to state transitions: for every state there is typed
evidence that only the real transition can mint, required by every operation that acts on the state;
revocable states use rank-2 region leases and spend-once capabilities use surgical linear types; the raw
destructive, commit, and spawn primitives are unexported. This reopens every phase with one bounded
follow-on sprint, foundation-first so the forward-only DAG holds. **All ten follow-on sprints are
code-side closed as of 2026-07-16** — each passes its machine-independent gate set (`cabal build all`
under `-Wall -Werror`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint
docs`, plus `poetry run check-code` / `node --check` where the native or Playwright surface changed) on
the apple-silicon lane — with each sprint's single-accelerator cohort full-suite (apple-silicon plus
`linux-cpu`) the residual now closed by [Wave V](cohort-validation-waves.md) (2026-07-20):

- **Phase 0 Sprint 0.13** — the doctrine document, its governance registration, and the `unsafeCoerce` /
  `unsafePerformIO` escape-token lint.
- **Phase 1 Sprint 1.16** — the foundation kernels `Infernix.Evidence.Readiness`,
  `Infernix.Evidence.Lease`, and `Infernix.Cluster.Subprocess` (`SubprocessEnv` / `CommandOutcome` /
  bounded, child-reaping `runBoundedCommand`); the opaque-newtype-via-export-list discipline.
- **Phase 2 Sprint 2.14** — the typed `ClusterLifecycle` machine with phase-resume, the fail-closed
  versioned persistence replacing `Show` / `Read`, and the lease-gated teardown (quiesce → scrub →
  delete).
- **Phase 3 Sprint 3.14** — the readiness kernel generalizing `HarborBootstrapOutcome`, and the
  subprocess-env seam.
- **Phase 4 Sprint 4.28** — evidence in the runtime and engines: `PayloadVerified` sentinel gating,
  `awaitModelBootstrapReady`, capability-gated commit and spawn, and native-runner `HOME` / `TMPDIR`.
- **Phase 5 Sprint 5.12** — the shared client contract that single-sources the bootstrap deadline, and
  the Playwright executor awaiting evidence rather than a proxy.
- **Phase 6 Sprint 6.39** — the capability-gating lint rules and the routed managed-transition coverage.
- **Phase 7 Sprint 7.29** — the `ClusterState` / `LifecycleProgress` field retirement, object-proxy
  bucket-evidence gating, and bootstrap `.ready` sentinel proof.
- **Phase 8 Sprint 8.7** — the warm-model-cache readiness-returns-evidence.
- **Phase 9 Sprint 9.10** — the admin-token lease and the object-storage session lease.

**Cohort live-path validation (2026-07-18).** A single-machine cohort run on Apple Silicon exercised
the reopen work in a live cluster, proving the managed-state changes end-to-end and catching two of
their own bugs (both fixed):

- **apple-silicon** — a full host-native `cluster up` brought the HA platform up cleanly (52 pods,
  `clusterPresent: True` / `lifecycleStatus: idle` / `lifecyclePhase: steady-state`), exercising the
  Sprint 2.14 typed `ClusterLifecycle` machine + versioned persistence, the Sprint 8.7 warm-model-cache
  typed evidence (its `WarmModelCacheStillPending` non-blocking path fired for the known upstream-403
  `music-omnizart`), the Sprint 9.10 `withValidAdminToken` lease (Keycloak realm reconcile), and the
  Sprint 7.29 status projections. After the required `internal materialize-metal-engines` step, live
  inference completed for models across every native-engine family — `llm-tinyllama-gguf` (llama.cpp),
  `llm-qwen15-mlx` (MLX), `speech-whisper-small` (whisper.cpp), `speech-faster-whisper-ct2`
  (CTranslate2) — plus the PyTorch and safetensors models, exercising the Sprint 4.28 native-runner
  `HOME`/`TMPDIR` env and the Sprint 7.29 sentinel path; the Sprint 2.14 lease-gated teardown ran on
  real retained state. The run caught (1) a Sprint 7.29 host-vs-coordinator bug —
  `proveModelReadySentinel` used the coordinator-only `loadBootstrapPresignedConfig`, blocking the
  Apple host retry; now it defers to the host's sentinel-gated hydration — and (2) a Sprint 4.28
  `lint files` violation — the literal `os.environ` in a docstring; both are fixed and all
  machine-independent gates (build `-Wall -Werror`, unit, style, `lint files/docs/proto/chart`,
  `docs check`, `check-code`, `node --check`) are green.
- **linux-cpu** — the launcher image rebuilt cleanly with both fixes; the full in-container static
  gate set passed on the native aarch64-linux substrate (`lint files/docs/proto/chart`, `test unit`
  `83/83`, `test lint` haskell-style — exercising the Sprint 0.13 escape-token and Sprint 6.39
  capability-gating lints); and `test integration` ran a full live cluster: cluster up, per-model
  inference over the linux-cpu catalog (with `music-omnizart` correctly rejected by the Sprint 4.27
  typed `ModelMemoryLimitExceeded { requiredMib = 6144, availableMib = 4096, resource = PodRam }`
  admission — the expected assertion, not a download error), and the entire HA/chaos suite:
  engine/frontend pod replacement + engine node drain preserving durable prompt results,
  **model-bootstrap failover + deduplication** (exercising the Sprint 4.28 `PayloadVerified` /
  `awaitModelBootstrapReady` and Sprint 7.29 `proveModelReadySentinel` under failover, on the Linux
  pods where the HEAD probe runs), multi-user throughput, Harbor / MinIO / routed-Pulsar recovery, and
  Postgres failover — before stalling in the *second* cluster-up of the final Postgres
  lifecycle-rebinding step on a `docker pull` verify of `percona-pgbackrest` from the local Harbor
  registry. That stall is an infrastructure flake on the many-hours-degraded Colima VM (Harbor
  registry, the known-flaky retained-state second-cluster-up the plan's Wave T record hit repeatedly),
  not a managed-state-transition defect.

A separate dependency-management fix was also completed this session: the `basic-pitch` Core ML runner
(Apple `coreml-native` venv only) crashed because `resampy` does `import pkg_resources`, which
`setuptools >= 81` removed. `setuptools < 81` is now pinned durably in that venv's inline pip list
(`src/Infernix/Engines/AppleSilicon.hs`); a from-scratch `materialize-metal-engines` re-resolve
installs `setuptools 80.10.2` and `basic_pitch.inference` imports cleanly (the `coremltools`
scikit-learn/torch messages are non-fatal warnings for a prebuilt model). The Linux `audio-basic-pitch-onnx`
path is unaffected — it runs raw onnxruntime against `nmp.onnx` with `scipy.signal.resample_poly`, no
`resampy`.

The only residual is the full `test integration` / `test e2e` green sign-off, gated now solely on
infrastructure/upstream flakes on the degraded VM (the Harbor lifecycle-rebinding `docker pull` stall
above; and the `music-omnizart` zenodo download, which returns 200 from the host but 403 from the
cluster pod's egress). Neither is a managed-state-transition defect. The sprints therefore remain
`Active` (code-side closed, cohort full-suite pending), not `Done`.

The superseded raw-hatch, stringly-state, and fail-open surfaces are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Bounded-Command Application & Bounded-HTTP Reopen (2026-07-19)

The 2026-07-18 single-accelerator cohort run (Apple Silicon) exercised the Managed-State-Transition
Doctrine reopen in a live cluster and proved the kernels *exist* but are **not applied** at two flake
sites — a Harbor `docker pull` verify that hung ~23 minutes with no timeout during the retained-state
second `cluster up` of the Postgres lifecycle-rebinding step, and a rate-limited upstream model
download (`music-omnizart` returned HTTP 403 from the pod: a UA-less request tripping the origin WAF,
carrying `Retry-After`). Both are the same shape the doctrine names: a raw primitive
(`System.Process` with no `Timeout`, `Network.HTTP.Client.withResponse` with no deadline or classified
outcome) is reachable at a production call site for which a total, evidence-minting kernel already
ships with zero production callers. Two capability-gating lints that would keep new call sites off the
kernels were also missing.

This is the **flake-driven follow-on reopen wave**: new sprints (not new phases), foundation-first so
the forward-only DAG holds. The applied fixes are code-side closed 2026-07-19 on the
machine-independent gate set on the apple-silicon lane (`cabal build all` under `-Wall -Werror`,
`cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`,
`infernix docs check`), each with its single-accelerator plus `linux-cpu` cohort full-suite the
residual now closed by [Wave V](cohort-validation-waves.md) (2026-07-20):

- **Phase 0 Sprint 0.14** — Bounded-Command/Bounded-HTTP doctrine documentation: the
  `managed_state_transitions.md` extension, the three-way non-negotiable mirror
  (`README.md` / `AGENTS.md` / `CLAUDE.md` plus `assistant_workflow.md`), and the deletion-ledger rows.
- **Phase 1 Sprint 1.17** — the bounded-HTTP download kernel: the total `DownloadOutcome` ADT, the
  opaque `RetryAfterSeconds` newtype, the pure `classifyDownloadStatus`, plus the descriptive
  `User-Agent` and bounded `responseTimeout` on `downloadUpstreamModelToFile`.
- **Phase 3 Sprint 3.15** — Harbor blob-servable evidence and bounded publish: every Harbor
  docker/skopeo exec routed through `Infernix.Cluster.Subprocess.runBoundedCommand` under named
  `Timeout` budgets (killing the hang), the opaque `BlobServable` witness minted by a real bounded
  pull, and `harborTagExists`→`harborTagMetadataPresent` / `registryReady`→`registryApiReachable` so
  tag metadata is no longer trusted as blob-servability on a retained-state second `cluster up`.
- **Phase 4 Sprint 4.29** — classified model download and integrity-witnessed sentinel: the
  `Retry-After`-honoring bounded-redelivery consumer fold (permanent failures ack to stop the
  redeliver-forever loop) and a `PayloadVerified` minted only when the uploaded object's byte length
  matches the download.
- **Phase 6 Sprint 6.40** — the `unboundedExecViolations` and `unboundedHttpViolations`
  capability-gating lints in `src/Infernix/Lint/HaskellStyle.hs`, making raw process spawn and raw
  upstream `withResponse` build errors outside their bounded wrappers.

The ProcessMonitor retirement, the shared `retryCommandOutput` primitive, and the eager-model-cache
barrier are the landed slice of **Phase 6 Sprint 6.41** (`Done`; code-side closed 2026-07-19,
machine-independent and adversarially reviewed, then behaviorally closed by Wave V on 2026-07-20):
`src/Infernix/ProcessMonitor.hs` is deleted (its ten monitored lifecycle commands rerouted through
the bounded `runCommandBounded`/`tryCommandBounded` helpers and its `unboundedExecExemptedFiles` row dropped),
`retryCommandOutput` is migrated onto `awaitReadiness` (bounding all six of its consumers), and
`waitForEagerModelCacheReady` is migrated onto the same kernel. The remaining individual
hand-rolled bounded waits and `threadDelay`-outside-kernel lint gate also closed in that sprint. The
retired module is recorded in the deletion ledger's `## Completed` under Sprint 6.41.

The superseded raw-exec, tag-metadata-as-servability, HEAD-existence-only sentinel, and
retried-forever surfaces are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Memory-Safety-by-Construction Reopen (2026-07-21)

Sprint 4.27's request-time admission returned a proof-free
`admitModelMemory :: InferenceMemoryBudget -> ModelDescriptor -> Maybe InferenceError` — a `Nothing`
carries no evidence that admission actually ran — and the Sprint 4.28 engine spawn was raw and
unbounded (`readCreateProcessWithExitCode` / `createProcess` in `runNativeWorker` /
`runWorkerInvocation`), so a **host OOM was a representable outcome and a full-suite run proved it**: an
over-budget model could exhaust host memory instead of failing cleanly. This is the same shape the
realness and managed-state doctrines name — code acting on hope (an unproven admission, an unbounded
spawn) rather than on typed evidence.

The [bounded inference memory doctrine](../documents/architecture/bounded_inference_memory.md) now
defines the stronger construction implemented by Phase 1: `compileRuntimePlan` mints a
resource-indexed `MemoryGrant` only for a model that fits the declared capacity, live refinement
pairs that grant with a matching `Enforcer`, and public engine launch accepts only the resulting
opaque `ExecutableModel`. An over-capacity row remains explicit as `UnavailableModel`; the
coordinator now publishes a clean `status=failed` `ModelMemoryLimitExceeded` for requests to that row
without attempting launch; the complete source-matched Phase 1 gate passed on 2026-07-25. The
capped-engine region applies the executable's `MemoryCeiling`, and a
required `ModelMemoryFootprint` plus checked `HostMemoryPartition` removes the former bare-`Int`,
default-zero, and unenforced-budget states. The Apple and Linux CPU enforcement implementations are
present, but Phase 4 retains adversarial survival proof and encapsulated serialization authority.
Linux GPU currently fails compilation closed with `GpuDualResourceBudgetRequired`; Phase 6 owns the
dual host-RAM/GPU-VRAM path. Phase 8 owns the final proper Dhall-union and `Natural` wire schema. The
`unboundedEngineSpawnViolations` lint keeps new engine-spawn call sites off the raw primitives.

This is a **doctrine-driven follow-on reopen wave**: new sprints (not new phases), foundation-first so
the forward-only DAG holds.

- **Phase 0 Sprint 0.15** — the `bounded_inference_memory.md` doctrine doc, its docs-lint registration
  (`requiredDocs` + `DocumentStructureRule`), and the new non-negotiable rule in the three-way
  `README.md` / `AGENTS.md` / `CLAUDE.md` mirror plus `assistant_workflow.md`. Doc-only and
  machine-independent — **Done** as of 2026-07-21 on `infernix lint docs` + `infernix docs check` +
  `cabal build all`.
- **Phase 4 Sprint 4.30** — the historical first grant-gated capped-engine kernel:
  `admitModelMemory` returned `Either InferenceError MemoryGrant`, and the internal capped-engine
  region bounded resident memory to the admitted `MemoryCeiling`, with the macOS
  `proc_pid_rusage` watchdog and Linux enforcement work. **Original code-side scope closed
  (2026-07-21); the public admission API was later replaced by Phase 1's indexed
  compile/refine/executable boundary, and the direct-FFI sampler plus its evidence are superseded by
  Sprint 4.32's fixed bounded `/usr/bin/top` plus `/usr/bin/footprint` observer.**
- **Phase 4 Sprint 4.31** — the checked `HostMemoryPartition`, the required `ModelMemoryFootprint`, and
  the budget-enforcer split dropping `UnenforcedMemoryBudget`. **Original code-side scope closed
  (2026-07-21)** (built on Sprint 4.30; retained by the Phase 1 compiler).
- **Phase 6 Sprint 6.42** — the `unboundedEngineSpawnViolations` capability-gating lint in
  `src/Infernix/Lint/HaskellStyle.hs`. **Code-side closed (2026-07-21)** (built on Phase 4 Sprint 4.30).

The original Phase 4 Sprints 4.30/4.31 and Phase 6 Sprint 6.42 scopes passed their recorded
machine-independent gates, and [Wave W](cohort-validation-waves.md) recorded apple-silicon plus
`linux-cpu` full-suite evidence on 2026-07-24. That evidence predates the Phase 1 indexed execution
plan and did not close Phase 1 Sprint 1.19; Sprint 1.19 later closed on its own source-matched
machine-independent gate on 2026-07-25. It also does not close Phase 4 Sprint 4.32 or the Phase 6
GPU construction.
The superseded proof-free admission, raw engine spawns, bare-`Int` footprint,
`UnenforcedMemoryBudget` arm, and hard-coded `appleHostReserveMib = 3072` reserve are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Observable-Readiness Reopen (2026-07-22)

A full-suite `infernix test all` could not complete a single clean run because the HA-tail
lifecycle-rebinding **second** `cluster up` stalled — apple at the `warm-model-cache` barrier ("11/16"),
linux at the `demo_ui = false` step. Wave W had recorded this as a "known Harbor/MinIO re-publish flake
orthogonal to memory-safety". Per operator directive, it was instead treated as evidence that an invalid
state is still representable and investigated as such (an adversarial multi-agent readiness/lifecycle
audit — 18 confirmed representable-invalid-states, 3 stall-capable).

**Root cause:** the warm-model-cache barrier observed each model's `.ready` sentinel through an `IO Bool`
HEAD (`minioObjectExists`, plus a `sentinelReady = try … >>= either (const (pure False)) pure`) that
collapsed three distinct facts — present (200), absent (404), and unobservable (a reset idle MinIO
NodePort keep-alive, a HEAD timeout, a not-yet-ready `5xx`/`403`) — into one `False`. On the
retained-state second `cluster up`, transient idle-NodePort faults made present, retained sentinels read
as absent, deflating the readiness census and stalling the already-warm cache to its give-up deadline.
The readiness kernel's two-channel step type (`Right` ready / `Left` count) had no channel for "could
not observe," forcing the fault to launder into a count. The Python cache revalidation had the mirror
defect: a fallible read reached `_delete_model_prefix`, deleting a valid retained `.ready` sentinel.

The [managed-state-transition doctrine](../documents/architecture/managed_state_transitions.md) closes
it by making readiness **observation** three-valued so a fault can never masquerade as a definitive
absence. This is a **doctrine-driven follow-on reopen wave**: new sprints (not new phases),
foundation-first.

- **Phase 1 Sprint 1.18** — the kernel `PollOutcome e = Measured (Either Progress e) | Unobservable Text`
  channel on `awaitReadinessObservable`, with `awaitReadiness` preserved as a behaviour-identical
  `Measured`-lift (the sixteen existing waits and `budgetDeadline` poll-count exactness unchanged). An
  `Unobservable` poll is retried within budget and can neither mint `Ready` nor deflate the count.
  **Code-side closed (2026-07-22).**
- **Phase 8 Sprint 8.8** — the three-valued `SentinelObservation` warm-model-cache probe (only a genuine
  404 mints `SentinelAbsent`) with the pure exported `classifyHeadOutcome`, the `SentinelCensus` that
  refuses to emit a readiness count while any sentinel is unobservable, and the Python
  `CacheValidity = VALID | CORRUPT | UNVERIFIABLE` verdict gating `_delete_model_prefix` on a
  deterministic-`CORRUPT` witness only. **Code-side closed (2026-07-22)** (built on Sprint 1.18).

The code is **code-side closed** (machine-independent gate set GREEN on this Apple host, 2026-07-22:
`cabal build all` `-Wall -Werror`, `cabal test infernix-unit` with the new classifier/census/kernel
invariant tests, `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`,
`infernix docs check`, `poetry run check-code`, web unit `83/83`), and the
single-accelerator (apple-silicon) plus `linux-cpu` behavioral re-run — a retained second `cluster up`
warming the cache without the "11/16" stall — **closed under [Wave W](cohort-validation-waves.md) on 2026-07-24 with apple-silicon plus linux-cpu full-suite GREEN**. The
superseded `IO Bool` sentinel probe, the `sentinelReady` error-to-`False` coercion, the two-channel-only
step contract, and the Python fail-open delete are recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Cluster-Ownership Reopen (2026-07-23)

An externally-killed `infernix test all` (stopped mid-integration by a background-task limit) exposed a
DSL smell: because `ClusterState` had no owner and `ClusterLifecycle` had no mutating position, a
test-mutated cluster (a drained node, an over-scaled deployment) was the **same term** as an operator's
idle `ClusterReady`, so a SIGKILLed run left a dirty cluster reading as a clean `steady-state`; and
`runClusterOwnedValidation`'s unconditional `clusterDown` over the shared operator cluster identity (the
test resolves the operator's `infernix.dhall` / `.data` / cluster name via `findRepoRoot`) meant even a
clean `infernix test all` **destroyed an operator's running cluster**. The `finally`-only
`withTestHarnessConfig` config swap had the same crash-hole: a SIGKILL bypasses the restore, clobbering
the operator's `./infernix.dhall`.

The [managed-state-transition doctrine](../documents/architecture/managed_state_transitions.md) closes it
by making cluster ownership and in-progress mutation representable: a cluster names its `ClusterOwner`
(`OperatorOwned | HarnessOwned`) and `clusterDown` consumes that evidence (fail closed on an operator
cluster), and a first-class `ClusterMutating` position makes a killed test's dirty cluster detectable +
reconcilable rather than a false `steady-state`. This is **documentation-first** (00-overview Hard
Constraint 0): the doctrine + governance landed first. Wave X validated the typed owner and mutation
position, but a 2026-07-25 execution audit found that harness teardown did not retain the lifecycle
lease between owner authorization and destruction. Phase 2 Sprint 2.15 and Phase 6 Sprint 6.43 are
reopened for that owner-atomic correction.

- **Phase 0 Sprint 0.16** — the doctrine extension in `managed_state_transitions.md`, the new
  non-negotiable rule in the three-way `README.md` / `AGENTS.md` / `CLAUDE.md` + `assistant_workflow.md`
  mirror, the `documentation_standards.md` cluster-lifecycle Update Rule, and the operator / test-harness
  / persistence doc reconciliation. Doc-only, **`Done`** (2026-07-23, `infernix lint docs` + `docs check`
  + `cabal build all`).
- **Phase 2 Sprint 2.15** (`Active`) — the model half preserves the `ClusterOwner` field and
  `ClusterMutating` lifecycle position while making operator/harness teardown authorization and the
  destructive transition one cross-process locked operation. Its implementation remains landed,
  and the Bark plus registry-only Harbor verification corrections are implemented. The
  `d578…` / `a0d1…` and `eae424…` / `a0d1…` review and Stage 1 results are historical
  GREEN-as-run evidence only and are superseded by the no-native-source correction. Phase 0's
  current correction review and Stage 1 are green. Phase 1 is code-side closed, so Phase 2's own
  ordered settled-source review and validation are now active; no Phase 2 Wave Y behavioral
  evidence exists.
- **Phase 6 Sprint 6.43** (`Blocked by Phase 2 and Phase 4`) — Phase 6's own ordered closure remains
  after its predecessors.

The apple-silicon plus `linux-cpu` Wave X proof remains historical evidence for its narrower scope.
It is not closure evidence for the newly found ownership window. The superseded ownerless
`ClusterReady`-as-idle, generic harness `clusterDown` cleanup, and the `finally`-only config swap are
recorded in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Current Phase Overview

| Phase | Current status | Reopened work |
|-------|----------------|---------------|
| 0 | Done | Sprint 0.18 no-repo-owned-native-source doctrine, governed mirror, focused adversarial proof, final review, and source-matched correction Stage 1 closed 2026-07-27 |
| 1 | Active — Validation Only | Superseded by the phase document's authoritative 2026-08-02 remainder: Sprint 1.20 is **code-side closed**, the complete machine-independent gate set is GREEN, and the paired source-matched `linux-cpu` full-suite cohort passed on exact image `sha256:51292f6f3d98560b383a4ab5cc8a1807aa5388fa5cc0ba8c99b305d90ba9ff67`. The final settled-source adversarial review found no High or Medium residual. The prior contents of this row enumerated a work list that the phase document explicitly retired as rejected-identity audit chronology; keeping it here contradicted the authoritative section and is corrected. Remaining: **validation only** — on an Apple Silicon host, rematerialize the corrected MLX/Core ML/native-runner roots, run the opt-in production Audiveris cancellation case and the installed upstream authoritative smokes, then complete the Apple catalog's `test integration` / `test e2e` / `test all` and record the Wave Y attestation. That half cannot run on the current CUDA Linux host at all |
| 2 | Active — Validation Only | The ordered machine-independent review is closed with no High/Medium code-side residual. The all-Haskell `filelock` and bounded self-exec kernel are implemented, and the exact Linux cohort exercised their lifecycle paths. Selected Apple Wave Y validation remains. |
| 3 | Done | No work in this reopen |
| 4 | Active — Validation Only | Sprint 4.32 code-side closure and the Linux behavioral half are GREEN. The opaque single-flight authority and fail-closed sampler-loss path are implemented; the live 64 MiB/16 MiB watchdog breach returns typed `EngineExceededCeiling`, reaps non-successfully, and a subsequent child succeeds. Exact image `sha256:dfc0e2b6251e2d7ed74712253e06d2f9fbc60b649ac162b44dac030aca43a979` (20,125,723,532 bytes) passed uninterrupted `./bootstrap/linux-cpu.sh test`: style/realness, Python, Haskell unit, web `83/83`, full integration/HA/lifecycle, and routed Playwright `16/16` (44.6 m; catalog matrix 42.9 m), with clean teardown. Apple breach/observer hardware evidence is the only remaining Phase 4 gate. |
| 5 | Done | No work in this reopen |
| 6 | Active — Validation Only | Sprint 6.44 is **code-side closed on 2026-08-02** and no longer blocked. `linux-gpu` compiled no execution plan at all before this sprint: every `LinuxGpu` config failed with `GpuDualResourceBudgetRequired`, `compileResources` had no `LinuxGpu` arm, and `watchdogForGrant` returned a hard `Left "NVIDIA per-process VRAM enforcement is unavailable"`. Now a device-using model compiles two independently indexed grants from a `DualEnforcedBudget` and runs under two live watchdogs; `DarwinObserver` is generalized to `FixedObserver`, a fixed bounded public-tool kernel owning both the Apple `/usr/bin/top` + `/usr/bin/footprint` pair and the NVIDIA `/usr/bin/nvidia-smi` pair behind an unexported spec; and per-process-group attribution was **measured, not assumed** — NVML resolves compute contexts in the reading process's PID namespace, so an engine pod sees its own namespace's pids and never another container's. Sprint 6.44 also migrated both `Runtime/Pulsar.hs` raw spawns onto bounded closed commands (including an unbounded Poetry-driven model download), deleted three raw-spawn exemption rows, and closed a real whole-token gap that had let `withCreateProcess` through. Remaining: the selected `linux-gpu` plus `linux-cpu` cohort with its adversarial CUDA breach case, and five named raw-spawn exemptions whose migration needs a doctrine decision (CLI passthrough, host tools, Apple prereqs, workflow tooling, files lint). Sprint 6.43's owner-atomic implementation is landed; its final cross-phase review is recorded in the phase document | Sprint 6.43's final cross-phase review ran on 2026-08-02 over four independent adversarial lenses with two-angle refutation: seven findings raised, three refuted, **four confirmed**. One was fixed with the review (the `linux-gpu` engine-Deployment rotation ran outside `withPersistedClusterMutation`, so a kill left a false steady-state). Three opened **Sprint 6.45**: a High cross-checkout defect — the Kind cluster name is machine-global while the lifecycle lock, reservation, and persisted state are repo-local, so a second checkout can authorize against the operator's inventory using its own leftover state and delete the operator's cluster — its reverse-direction twin, and the disproof of the documented "tearing down an `OperatorOwned` cluster does not typecheck" claim (the region is type-indexed; the owner is an ordinary field, so the refusal is a runtime check under the held lease). The doctrine wording in `CLAUDE.md`, `AGENTS.md`, and `managed_state_transitions.md` is corrected to what the code does | **Sprint 6.44's adversarial CUDA breach deliverable is not covered by any suite and the cohort cannot cover it** — the integration suite has no runtime ceiling-breach case, and the unit suite's live NVIDIA assertions skip inside the cohort because the outer launcher container has no GPU by design; closing it needs an in-engine-pod case | **Cohort attempt 1 (2026-08-03) failed and found a real Sprint 6.44 defect**: the GPU engine pod's 16 GiB cgroup limit against a reused 4 GiB `linux-cpu` child budget produced `OuterEnvelopeTooLarge 5120 16384` on every GPU placement, so no engine became ready. Invisible to every machine-independent gate because `linux-gpu` compiled no plan at all before the sprint. Fixed by deriving the GPU budget from the pod limit and guarded by a new both-lane unit assertion that was negative-tested against the original value | A second cohort defect is now root-caused by measurement: the fixed `nvidia-smi` observer stalls before `exec` because `close_fds = True` walks the containerd pod's `RLIMIT_NOFILE` of 1073741816 (~4.5 min/spawn extrapolated from 133 ms at 524288), versus 1024 in the launcher container — which is why every machine-independent gate passes. **No fix applied**: the same flag is set in the capped-engine and bounded-command kernels, so the remedy is a doctrine decision needing its own validation, and whether those kernels pay the same cost is explicitly unverified |
| 7 | Done | No work in this reopen |
| 8 | Active — Validation Only | Sprint 8.9 is **code-side closed on 2026-08-02**. Its premise was partly out of date on arrival — the budget was already a proper two-arm union — so the plan is corrected rather than left claiming retired work. Landed: the third `DualEnforced` arm Sprint 6.44's dual capability needed, one shared rendered union type replacing a literal duplicated per arm, a schema-reflection assertion that pins the rendered payload against the alternatives the decoder expects (renderer/decoder drift was previously undetectable), a targeted migration diagnostic that names a retired flat payload's shape and the regenerating command instead of surfacing a bare Dhall type error, and removal of the dead `legacyDhall` decoder branch. Remaining and now named explicitly: the generated wire's text enums, `Integer`-vs-`Natural` quantities, the zero-filled `edgePort`, the still-flat Aeson `kind` encoding the web UI reads, and the coordinator/webapp readiness-refinement question. Behavioral evidence is consumed from the Sprint 6.44 wave, per this sprint's own no-dual-accelerator-gate rule |
| 9 | Done | No work in this reopen |

## Prior Closure Evidence By Phase

The table below preserves the evidence and narrower closure claims that existed before the Typed
Execution Plan reopen. Its `Done` labels apply only to those recorded scopes; the current status
table above is authoritative.

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Done — Sprint 0.18 closed the no-repo-owned-native-source doctrine, workflow/root mirror, plan reset, focused adversarial proof, final review, and source-matched correction Stage 1 on 2026-07-27. Sprint 0.17 and earlier governance scopes retain their recorded narrower evidence. | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Active — Sprint 1.20 has removed the embedded Objective-C/C/Metal implementation and generated shell wrappers, and routes closed provisioning through the bounded self-exec kernel. Five adversarial reviews have rejected successive drafts. Review #5 rejected the escaping writer/lock boundary and arbitrary activation callback, and found remaining pathname-recursive or unbounded closure, recovery, package-discovery, and nested-capture paths. The live correction audit also requires capped-engine groups to retain an exact helper-owned group identity through termination, absence proof, and designated-owner reap instead of signaling a numeric PGID after its leader was reaped. A callback-linear-over-ordinary-`IO` design is superseded by hidden runner-owned indexed sequencing. Exact descriptor-derived target evidence is not yet complete for the Linux loader/library closure, and the root-bound writer still has a pathname effect-time parent-swap window; both are High blockers. The measured Core ML root is about 1.7 GiB, so copying a complete installed/candidate root into the bounded-command snapshot on every smoke or inference is rejected as non-viable. The replacement must execute the exact retained generation under a kernel-managed generation lease through reap; candidate/final recovery and deletion must acquire its writer side, and a new materialization writer must recover exact dead-owner activity identities before mutation authority is minted. Focused inventories remain work in progress; no accepted final review, exact-source Stage 1, Apple rematerialization/runtime/cohort, or paired `linux-cpu` cohort exists. Sprint 1.19 and earlier scopes retain only their narrower recorded evidence. | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Blocked by Phase 1 — all pre-correction digests, reviews, and Stage 1 results are historical GREEN-as-run and nonreusable. The all-Haskell lock and self-exec anchor/supervisor/pin implementation, recoverable prewrite intent, bounded activity reads, strict framed capture/terminal bounds, and obsolete C/Cabal deletion are present. Phase 0's current correction gate is green; Phase 2's ordered phase review/validation, Apple, and then `linux-cpu` remain after Phase 1. | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Done — Bounded-Command Application & Bounded-HTTP reopen (Sprint 3.15 code-side closed 2026-07-19: bounded Harbor publish exec through `runBoundedCommand` + opaque `BlobServable` witness + `harborTagMetadataPresent`/`registryApiReachable` demotion; cohort gate closed by [Wave V](cohort-validation-waves.md) (2026-07-20)); Managed-State-Transition Doctrine reopen (Sprint 3.14 code-side closed 2026-07-16: Harbor wait on the Readiness kernel + typed SubprocessEnv seam; cohort gate closed by [Wave V](cohort-validation-waves.md) (2026-07-20)); prior Done — reopened and re-closed (Sprints 3.1-3.12 remain closed — Sprint 3.12 native `linux-cpu` architecture selector and native arm64 publication path closed in Wave F, Sprints 3.10-3.11 validated by Apple Wave A/A.2 and CUDA Linux Wave C; Sprint 3.13 de-exposes the `/minio/s3` external gateway route + `infernix-minio-s3` SecurityPolicy + `presignPublicEndpoint` so the webapp object-proxy is the sole external file-storage service. Sprint 3.13 is code-side closed and validated machine-independent on 2026-06-24, then cohort-closed by [Wave M](cohort-validation-waves.md) on 2026-06-29 with `linux-cpu` plus the selected `linux-gpu` full-suite gates.) | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Prior closure only — Sprints 4.22–4.31 retain their recorded Wave P/R/S/T/V/W evidence, including the narrower Sprint 4.30/4.31 memory-safety scope closed by Wave W. Current Sprint 4.32 is blocked by Phase 2 and must behaviorally prove the landed Apple/Linux CPU enforcers, encapsulate serialized execution inside the capability boundary, and preserve the split where coordinators route through compiled placement/daemon capabilities while engine subscription and launch use refined runtime/executable capabilities before Phase 4 is current-scope `Done`. | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Done — Managed-State-Transition Doctrine reopen (Sprint 5.12 code-side closed 2026-07-16: single-sourced model-bootstrap deadline + Playwright awaits real readiness; cohort gate closed by [Wave V](cohort-validation-waves.md) (2026-07-20)); prior Done — Sprint 5.11 is closed for typed `InferenceError` browser contracts and demo-app rendering of `ModelMemoryLimitExceeded` from explicit MiB fields, not parsed inline text. Wave T closed on 2026-07-12 with `linux-cpu` plus selected `linux-gpu` routed full-suite evidence. Sprints 5.1-5.10 remain closed for their original PureScript, generated-contract, and no-env scopes. | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Prior closure only — Sprints 6.35–6.42 retain their recorded Wave P/R/S/T/V/W evidence, and Wave X remains evidence for the earlier typed owner/mutation/config scope. Sprint 6.44 is code-side closed (2026-08-02) and owns only its `linux-gpu` plus `linux-cpu` cohort with the adversarial CUDA breach case. Reopened Sprint 6.43 still requires the ordered owner-atomic cohort after Phases 2/4, and is now additionally blocked by the newly opened Sprint 6.45, which its own final review created. | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |
| 7 | Demo App Multi-User Durable Context | Done — Managed-State-Transition Doctrine reopen (Sprint 7.29 code-side closed 2026-07-16: LifecycleProgress field retirement + DemoBucketsProvisioned object-proxy gate + proven `.ready` sentinel; cohort gate closed by [Wave V](cohort-validation-waves.md) (2026-07-20)); prior Done — Sprint 7.28 closed generated artifact object ownership and result-bridge authorization on 2026-06-30 with full selected `linux-gpu` plus `linux-cpu` cohort validation. Prior durable-context, engine-pool, object-proxy, Files view, in-browser rendering, and Wave M closure evidence remains recorded for Sprints 7.1-7.27. Desired-state hot reload remains future work. | [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) |
| 8 | Zero-Tracked-Dhall Config and Eager Model Cache | Done — Observable-Readiness reopen (Sprint 8.8 — the fault-vs-absence fix in the warm-model-cache barrier: tri-state `SentinelObservation` probe + `classifyHeadOutcome` + `SentinelCensus` + Python `CacheValidity`, which supersedes the documented non-blocking MinIO-poll-observability residual by diagnosing it as the "11/16" stall root cause and fixing it by construction) closed under [Wave W](cohort-validation-waves.md) on 2026-07-24 with apple-silicon plus linux-cpu full-suite GREEN; prior Done — Managed-State-Transition Doctrine reopen (Sprint 8.7 code-side closed 2026-07-16: typed WarmModelCacheOutcome evidence + fail-closed config-side port reads; cohort gate closed by [Wave V](cohort-validation-waves.md) (2026-07-20)); prior Done — all sprints (8.1-8.6) closed. Zero-tracked `.dhall`; `infernix init` / `test init` explicit creation with shared defaults; fail-fast no-auto-generate backstops; binary-generated ConfigMap/Secret bodies with the chart as string embedder; coordinator eager model-cache staging (+ `--empty-models` image bake); test-harness config lifecycle. Cohort gate closed 2026-07-04 (Wave P): `linux-gpu` + `linux-cpu` full-suite `infernix test all` both GREEN, routed Playwright **9/9**. One documented non-blocking residual: the `warm-model-cache` barrier's host-side MinIO poll observability. | [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) |
| 9 | Access Control and Monitoring | Done — Managed-State-Transition Doctrine reopen (Sprint 9.10 code-side closed 2026-07-16: withValidAdminToken region lease + typed StsSession leased value; cohort gate closed by [Wave V](cohort-validation-waves.md) (2026-07-20)); prior Done — the original 8 RBAC/STS/dashboard sprints are code-side closed and Wave Q validated on both `apple-silicon` and `linux-cpu` (2026-07-07). Sprint 9.9 closes the UAT auth residual from `notes.txt`: Sign out previously cleared only local SPA tokens and left the Keycloak SSO browser session alive, so switching from a self-registered user to the separate hardcoded admin login could silently reuse the non-admin session. The SPA now performs Keycloak OIDC logout with `id_token_hint`, `client_id`, and `post_logout_redirect_uri`, and the routed Playwright spec has a user-to-admin switching regression. Wave U closed on 2026-07-12 with `linux-cpu` plus selected `linux-gpu` routed evidence. The implemented surface includes admin/user RBAC (Keycloak `infernix-admin` realm role + JWT `realm_access.roles` claim + hardcoded demo admin), edge admin `SecurityPolicy` over all four operator routes + ungated-route closure, backend admin gate on `GET /api/cache` + `/api/cache/{evict,rebuild}` + `GET /api/admin/overview`, admin cluster-wide monitoring panel + per-user personal dashboard, the Kind data-plane + edge loopback invariant, per-user MinIO STS defense-in-depth, and real Keycloak logout for account switching. | [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md) |

> **Note**: Phase statuses describe current repository state. Earlier governed phases may remain
> `Active` or `Blocked` for named follow-ons while later phases can be `Done` when their owned work
> and validation are complete. Validation-only hardware blockers are scheduled through
> [cohort-validation-waves.md](cohort-validation-waves.md) instead of forcing repeated machine
> switches during unrelated same-cohort work.
> Each phase 1-7 gained a cleanup sprint that eliminates the env-var fallbacks and
> PATH-resolved external commands the phase originally introduced. See
> [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)
> for the doctrine, and the per-phase sprint sections for the specific retirement scope.

## Canonical Outcome

The supported platform now closes around these rules:

- one repo-owned Haskell executable, `infernix`, links the default Cabal library exposed by the
  `infernix` package (declared in `infernix.cabal` without an explicit library name and depended on
  as `infernix`); it owns the production daemon, cluster lifecycle, validation, internal helpers, and
  the routed demo HTTP host (served by the long-running `Webapp` role selected through typed Dhall
  and `infernix service --role webapp`)
- one Haskell command registry owns parsing, help text, and the
  canonical CLI reference, but it no longer exposes `--runtime-mode` or any equivalent substrate
  override
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from repo-root `./infernix.dhall`, and that initialized payload is
  the primary source of truth for substrate identity,
  generated catalog content, daemon role, inference placement, Pulsar topics, and test scope
- `infernix init` creates the operator runtime config and host manifest; `infernix test init`
  creates the harness input from which a reservation-gated run generates its temporary runtime
  config
- the Linux substrate Dockerfile uses binary-owned config generation for image-local defaults, but
  ordinary outer-container commands do not auto-materialize missing operator or harness config
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints fail fast with a "run `infernix init`" reminder when
  their `infernix.dhall` is missing (Phase 8; no auto-materialize backstop); focused
  `infernix lint ...` and `infernix docs check` remain substrate-file independent
- the runtime substrate file is a typed Dhall record at repo-root `./infernix.dhall`, created by
  `infernix init` (or the test harness from `infernix test init`) and decoded in-process by the
  `dhall` Haskell library; the schema is
  reflected from the substrate decoder type — no `.dhall` is version-controlled
- Apple host-native operation is the only supported host build path outside a container
- on Apple Silicon, the host-built `./.build/infernix` binary manages Kind, deploys the mandatory
  cluster support services, the cluster coordinator Deployment, and optional routed demo workload,
  and owns the host-side same-binary engine daemon lane
- on Apple Silicon, the cluster coordinator is canonical for Pulsar ingress and derived pool-topic
  handoff, while host engine daemons are canonical for Apple-native inference execution and result
  publication; both roles consume `.dhall` role config from the same binary family
- when the demo UI is enabled on Apple Silicon, the routed demo surface stays cluster-resident and
  manual inference flows through the cluster daemon's batching path before Apple inference batches
  move through Pulsar to host daemons
- on Apple Silicon, Compose is not a user-facing launcher for ordinary CLI work; host-native routed
  E2E now uses host `npm exec` Playwright fed by the same typed fixture against the published
  localhost edge port and is covered by Apple cohort validation batches. Linux substrates run
  Playwright in-container inside the substrate image via
  `npm --prefix web exec -- playwright test ...`
- on Linux substrates, all supported CLI commands run through
  `docker compose run --rm infernix infernix ...`; there is no supported Linux host-native build or
  CLI surface outside the outer container
- `linux-cpu` is the only substrate that remains meaningfully portable across unrelated native
  Linux host hardware; native amd64 Linux and native arm64 Linux are the supported validation
  shapes, while Apple Silicon emulation is not a supported build or validation lane
- `linux-gpu` assumes an amd64 Linux environment paired with a CUDA-capable device, but the outer
  control-plane container itself does not require the NVIDIA runtime
- for `linux-gpu`, the outer control-plane image is still built from the CUDA base image, and that
  same built image is the artifact pushed to Harbor and deployed as the cluster daemon
- the operator runtime config lives at repo-root `./infernix.dhall` on every supported execution
  context; cluster deployment derives a payload through `ConfigMap/infernix-demo-config` whenever
  the active topology has cluster-resident consumers and mounts it at the compatibility path
  `/opt/build/infernix-substrate.dhall`
- each daemon reads its runtime-config `.dhall` at startup; automatic file-watching or reload is
  not part of the supported contract
- `infernix init --demo-ui false` can disable the demo surface; omitting that flag keeps the
  default demo-enabled output
- the routed demo app remains cluster-resident when enabled, and the Apple routed path closes
  around an explicit cluster-daemon-to-host-daemon inference batch bridge rather than
  cluster-resident Apple inference execution
- supported entrypoints no longer carry the old cross-substrate default matrix, cluster bring-up
  fallbacks, direct tool-route compatibility handlers, or generic inference-success fallback;
  routed Harbor, MinIO, and Pulsar checks require the real Gateway-backed upstream behavior, while
  inference coverage goes through the typed adapter harness selected by the active substrate file.
  The repo-local Pulsar topic spool remains only a harness-oriented path for endpoint-absent unit
  or isolated daemon checks, not a substitute for routed cluster validation
- integration coverage is driven by the comprehensive model, format, and engine matrix in
  `README.md`: one substrate-aware integration suite reads the active substrate from `.dhall`,
  chooses the corresponding engine binding for each supported row or reference, and runs at least
  one assertion for every such row
- Playwright E2E remains substrate-agnostic at the browser layer and relies on `infernix-demo` to
  read the same `.dhall` and dispatch the correct engine for the active substrate
- Harbor-first bootstrap, mandatory local HA platform services, Gateway-owned routing, operator-run
  Patroni PostgreSQL, manual `infernix-manual` storage, Haskell-owned frontend contracts, the
  shared Python adapter project, and untracked generated outputs all remain mandatory doctrine
- supported validation is substrate-specific: integration, E2E, and `test all` run their complete
  supported suites against the built and deployed substrate, and test reports name that substrate
  explicitly instead of implying matrix-wide coverage
- the supported control plane keeps one Haskell command registry,
  binary-owned lifecycle and validation orchestration, the current `ormolu` plus `hlint` plus
  `cabal format` style stack, and the existing files or docs or chart or proto validation
  entrypoints; shell bootstrap responsibility is limited to prerequisite and launcher setup
- every `infernix service` daemon remains startup-configured and Pulsar-driven without a separate
  admin-HTTP, hot-reload, or typed-event-ledger subsystem in the supported contract
- the test surface remains the current three Cabal stanzas plus the frontend unit suite:
  `infernix-unit`, `infernix-integration`, and `infernix-haskell-style`, exercised through the
  supported `infernix test lint|unit|integration|e2e|all` command surface

## Dependency Chain

| Phase | Depends on | Why |
|-------|------------|-----|
| 0 | none | establishes the governed docs suite and plan-maintenance rules the remaining phases rely on |
| 1 | 0 | closes the repository scaffold, the staged-substrate contract, the one-binary role model, and the governed root-document posture |
| 2 | 0-1 | builds Kind lifecycle, manual storage, Harbor-first image flow, and Linux launcher behavior on top of the repository foundations |
| 3 | 0-2 | adds the HA platform services, routed edge, and publication contract on top of the cluster lifecycle and storage baseline |
| 4 | 0-3 | closes the runtime, adapter boundary, object-store contract, and Apple host-daemon bridge on top of the HA platform surfaces |
| 5 | 0-4 | adds the clustered demo UI, generated frontend contracts, and routed browser validation on top of the runtime and publication contract |
| 6 | 0-5 | validates the whole supported surface end to end and hardens the governed docs, routes, and lifecycle behavior around that implementation |
| 7 | 0-6 | adds the multi-user durable-context demo application on top of the platform: Keycloak self-signup, WebSocket post-login transport, Pulsar-backed conversation log per context, MinIO-backed artifact upload/download/render-or-download, a Haskell-first logic boundary surfaced to PureScript via `purescript-bridge`, and the supported three-role daemon split (stateless Webapp role in the `infernix-demo` workload, stateless `infernix-coordinator`, substrate-specific engine pools). The platform contract Phase 7 builds on is implemented in code; Apple plus native Linux/CUDA real-cluster validation evidence is recorded in Waves A-C, Sprint 7.8 runtime KV-cache plus `Infernix.Runtime.Daemon` closure is recorded in Wave E, Sprint 7.24 pool assignment and broker-native backpressure closed in Wave J, Sprints 7.25-7.27 object-proxy / Files / in-browser rendering closed in Wave M, and Sprint 7.28 generated artifact ownership closed in Wave N. |
| 8 | 0-7 | adopts the hostbootstrap Dhall doctrine on top of the whole platform: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (including ConfigMap/Secret bodies), explicit `init` / `test init` creation with ordinary commands failing fast when config is missing, the Apple bootstrap `up` wrapper explicitly running `init --if-missing`, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging (replacing the lazy per-inference bootstrap) driven by the mounted `infernix.dhall`. |
| 9 | 0-8 | adds the role-based access-control and monitoring surface on top of the whole demo platform: the Keycloak `infernix-admin` realm role + JWT `realm_access.roles` claim, the edge admin `SecurityPolicy` (a valid JWT is necessary but not sufficient for cluster-wide surfaces) plus ungated-route closure, the backend admin gate + admin cluster-wide monitoring panel, the per-user personal dashboard, per-user MinIO STS defense-in-depth, and the enforced Apple host-worker loopback data-plane invariant. Every dependency edge references an equal-or-lower-numbered phase, so the forward-only DAG holds. |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
