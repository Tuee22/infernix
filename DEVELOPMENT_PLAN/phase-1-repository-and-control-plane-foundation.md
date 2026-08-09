# Phase 1: Repository and Control-Plane Foundation

**Status**: Active — **no longer Validation Only as of 2026-08-08.** The
[Apple/`linux-cpu` evidence reset](cohort-validation-waves.md) surfaced two code-side defects inside
Sprint 1.20's own surface (the bounded-command target-environment allowlist, which blocks `test lint`
and `cluster up` on both lanes, and the Audiveris installed-smoke path drift), and a measurement
residual in Sprint 1.21 (the Darwin toolchain account does not intersect the co-resident VM pledge).
Sprint 1.22 landed the lane-resolved build-memory correction and is code-side closed. The
validation-only text that follows describes the position as of 2026-08-02 and is retained for that
recorded scope. Sprint 1.20's `linux-cpu` cohort closed on exact image
`sha256:51292f6f3d98560b383a4ab5cc8a1807aa5388fa5cc0ba8c99b305d90ba9ff67` and its remaining half is
Apple accelerator evidence. Sprint 1.21 (bounded host build-memory kernel) is code-side closed on
2026-08-06 and `Active` only for the Apple lane's unmeasured mechanism, which its cohort wave owns.

## Current validation run (2026-07-31)

Sprint 1.20 remains Active, but the previously RED supported `linux-cpu` launcher build is now
GREEN through image construction and all five native artifact materializations. This run closed
four defects that were hidden behind the earlier recorded machine-independent gates: static
ELF executables now contribute their absolute `initialize program:` audit frame; the image-owned
Python venv is created with copied rather than host-absolute interpreter links; ELF closure walking
follows queued dependencies before unrelated scan seeds and reuses a unique already-observed
`DT_SONAME`; and Python native smoke receives the catalog-derived sealed interpreter prefix instead
of assuming the Apple installed-venv layout. The Docker build separates binary installation from
artifact materialization so a failed fail-closed observation is independently diagnosable.

The Linux image now invokes the pinned Audiveris version probe at build time with JavaCPP's cache
fixed under `/opt/infernix`, includes that exact cache as an immutable target closure, and passes
the real sealed-loader smoke. The installed Apple path now has the corresponding code-side
construction: the closed provisioning language invokes the bundle's own fixed JVM before candidate
hashing, extracts into `<candidate>/javacpp-cache`, and the runtime catalog uses the same bundled
JVM, classpath, and candidate-local cache. Containerized `cabal build all --enable-tests`,
`infernix-artifact-transaction` (48 cases), `infernix-apple-materializer` (12 cases), and
`infernix-unit` are GREEN on this correction; the unit suite's earlier bounded-command owner-live
failure did not reproduce on the isolated rerun. The exact current-tree `linux-cpu` image then
rebuilt GREEN with manifest
`sha256:33a0086e51e8bda30dca94c3502320e53ca3ab9c788be469709bdc88fdfbd55c` and all five native
artifacts materialized. From that image, `lint files`, `lint docs`, `lint proto`, `lint chart`, and
`docs check` are GREEN; `git diff --check` is also GREEN. Phase 1 still requires the remaining
frozen-identity gates, final Apple closure measurements, and real Apple hardware
materialization/runtime evidence. No Phase 2 implementation may begin before those Phase 1 gates.

The canonical `./bootstrap/linux-cpu.sh test` cohort then exposed three successive fail-closed
provisioning defects before cluster mutation. First, the Poetry venv interpreter canonicalized to
`/usr/bin/python3.12`, widened the inferred Python home to `/usr`, and reached the absolute
alternatives link `/usr/bin/awk`; the image now creates that venv with `--copies`. Second, the
shared Python runtime resolver unconditionally applied the Darwin Mach-O walk on Linux; it now
selects by the compiled host platform, retaining the bounded Mach-O closure on Darwin and deriving
Linux subprocess authority from the existing descriptor-observed recursive ELF loader closure.
The corrected image rebuilt GREEN as
`sha256:6a8c107a0d7dd8e33cd1d3b4b7d5ffe55d8d8d6baa04311e17518d3ee09b2fdd`, and its cohort passed the
clean build and style gate before exposing the third defect: the provisioning digest excluded
Python-home console scripts whose absolute shebang binds the source installation, while the anchor
snapshot still copied them. The anchor copy walk now applies the identical content-derived
exclusion. The next exact image passed clean build and style, then exposed the serialized target
environment still admitting only the Darwin snapshot shape. Linux snapshots now retain and
revalidate their exact observed ELF libraries in place, inject only `PYTHONHOME` and `PYTHONPATH`,
and have an explicit closed supervisor environment shape; Darwin keeps its copied DYLD closure.
The ensuing target start proved that ordinary Linux venvs do not contain their standard library and
that the project venv still canonicalized through a system-interpreter symlink. Both image-owned
venvs are now created with copied interpreters and a dereferenced standard-library payload before
Poetry populates them. Snapshot/digest exclusion of host-bound console launchers is confined to
`bin/`, preserving importable standard-library modules with absolute shebangs, and the ELF parser
now admits valid relocatable objects whose program-header count and entry size are both zero.

An image-native focused rerun on the corrected source passes provisioning and the complete unit
cohort, including the Sprint 1.20 regressions and 83/83 web tests. The focused style and
`cabal build all --enable-tests` gates are GREEN, and the exact-source image rebuilt through all
five native materializations, framework installs, web build, and Python checks as
`sha256:6adb3c02bad77f710ed45208f3be7253a596b4680c7aece7bcdd912d327e8a38`. This is not yet canonical
cohort evidence: the complete `linux-cpu` cohort rerun remains pending.

The canonical cohort from that image completed its clean test build, then failed the style gate
before cluster mutation on two Ormolu guard-layout differences introduced after the earlier focused
style run. Those mechanical layouts are corrected; because the cohort consumes the baked source
snapshot, another exact-source image rebuild was required. That replacement rebuilt GREEN as
`sha256:13e83e3e5c337f3c76f22250dc1ee5c430ab0b9a79146799f778702b637aaa2d`; its canonical cohort rerun
passed clean style, Python checks, unit, 83/83 web tests, cluster creation, Harbor publication,
final rollout, routed publication, and eager staging of all 12 configured models. Per-model
inference then failed closed because the worker required an Apple setup `bootstrap.json` inside a
Linux engine pod's private `/workspace/.data` `emptyDir`. Linux framework environments are already
immutable image payloads proven by the baked per-engine marker, so that retained manifest is now
required only for Apple; Linux CPU/GPU retain the existing exact marker/venv validation. Focused
build, unit, and style gates are GREEN for this correction. The exact-source image subsequently rebuilt GREEN as
`sha256:d52820cc81eb90f38e3036c1fcb7ef5af24cda82e1458239745f81993f83e6a9`. Its canonical cohort
passed clean style, Python checks, unit, 83/83 web tests, cluster creation, Harbor publication,
final rollout, routed publication, and eager staging of all 12 models. Both engine replicas then
failed closed at per-model inference because the baked Linux framework markers omitted the
`projectDigest` line required by runtime revalidation. The Docker producer now hashes the exact
`pyproject.toml`, separator newline, and `poetry.lock` bytes with the same SHA-256 construction as
the Haskell consumer and records that digest for both Transformers and PyTorch. A replacement image
rebuilt GREEN through all five native materializations, framework installs, web build, and Python
checks as `sha256:6b93f886c299585a973221095c273f8664daf7e0dd35d97cda836b99f7f1ec1f`.
An image-native equality probe confirms the recorded and independently recomputed project digests
match for both environments. Its canonical cohort passed every pre-cluster gate, full cluster
creation/publication/rollout, eager staging, and the Python-backed inference boundary, then failed
closed on `llm-tinyllama-gguf`: persisted Linux target evidence compared build-container inode
numbers with the fresh inode numbers assigned when OCI unpacked the runtime rootfs. Descriptor-open
observation still uses device/inode identity to prove stable reads, but persisted Linux image
evidence now compares its portable identity—closed paths, types, modes, sizes, digests, ELF
metadata, and loader edges—without treating non-portable OCI inode allocation as provenance. A
focused regression and replacement cohort remain pending; Phase 1 remains Active.
The exact-source focused unit and style gates are now GREEN, including a regression that proves an
OCI device/inode reassignment normalizes to the same portable image evidence while retaining every
content and loader field. The replacement image and cohort remain pending.
The replacement image subsequently rebuilt GREEN through all materialization and image checks as
`sha256:51dc9484c4327725b9b18e284afe761d37e75ec20e2909c39f02cd82c4b32e90`; its canonical cohort is
pending. That cohort passed every pre-cluster gate, cluster publication/rollout, and eager staging,
and crossed the prior Linux inode-revalidation failure, but did not publish any result for the first
`llm-smollm2-safetensors` request within the 4,200-second integration deadline. Both replicas
repeatedly launched CPU-bound bounded children while the request remained unacked, so this is a
real missing-result/redelivery defect rather than closure evidence. A short diagnostic rerun then
captured both replicas completing real inference (`engineProcessed ... status=completed`) before
their consumer sessions failed with `Broken pipe`; the proxy reported
`Idle timeout expired: 30000/30000 ms`. The bounded child was healthy, but the upstream Pulsar
WebSocket session expired while inference retained the message. An initial correction set
`webSocketSessionIdleTimeoutMillis`; exact-source focused `infernix-unit` and `lint chart` were
GREEN. The replacement image subsequently rebuilt GREEN through all five native materializations,
framework installs, web build, Python checks, and browser provisioning as
`sha256:75e40a2e57537834efcfbd6b89082e786bef6d019ce3ec2cdb1951ce33614bf9`
(20,125,136,372 bytes). Its cohort passed every pre-cluster gate and reached per-model inference,
but live inspection showed that Pulsar 4.0.9 did not project that key into `proxy.conf`; the
effective setting was still `httpServerIdleTimeout=30000`, exactly matching the observed closure.
The cohort was stopped through managed teardown. The chart default and binary-generated local
override now set the effective `httpServerIdleTimeout` to 7,200,000 ms—above the 4,200-second result
deadline—with lint and rendered-values guards. The focused `infernix-unit` and `lint chart` gates
are GREEN for the effective proxy key. Another exact-source image/cohort remains pending; Phase 1
remains Active.
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
That code-side correction is now implemented. The browser helper exposes only package-owned
model-engine preparation and fixed demo-pod replacement actions. The Haskell side requires the
harness reservation and persisted harness ownership, derives every deployment and replica count
from the generated runtime mode/catalog, and routes scale/list/delete/wait through the closed
cluster command language. Focused regressions cover registry parsing, exact scale argv ownership,
and negative-replica rejection. The supported Linux-container unit gate is GREEN (Haskell
unit/property plus PureScript 83/83), repository lint is GREEN, `infernix lint docs` is GREEN, and
`git diff --check` is GREEN. The replacement exact-source image and canonical Linux CPU cohort are
still pending, so this phase remains Active.
The replacement image subsequently built GREEN as
`sha256:0415213b271d730eb8099f8414ec4d49aabc0e141c1024e247db3e55389b80c2`
(20,125,667,641 bytes), including all five native artifacts, framework environments,
image-local Haskell/PureScript/Python checks, browser provisioning, and the CLI-help smoke. Its
canonical Linux CPU cohort is now the active gate.
Its cohort passed Haskell style/realness but stopped during machine-independent preflight when
`lint docs` found that the image-baked CLI-reference generated section omitted the two new registry
commands. The host reference now byte-matches the registry renderer. Since the supported Linux
lane validates the baked source snapshot, a second replacement image is pending; the prior digest
is failed evidence, not a closure identity.
The corrected source-matched image is GREEN as
`sha256:e5ef7da5641972f7935386b1e95919f476fe861f93adc3984f364b75c767f7d3`
(20,125,654,078 bytes), with image-local validation and an image-backed `infernix lint docs`
GREEN. Its canonical Linux CPU cohort is now the active gate.
The cohort passed repaired docs lint and style/realness, then failed the new unit assertion because
its expected scale argv omitted the closed renderer's mandatory `--kuberc=/dev/null`. The
production renderer was correct; the assertion now covers the complete ambient-kuberc-suppressed
argv. The next exact-source image is GREEN as
`sha256:6b9e7f5aada9f51e0befe7cd583ad08384ca63419f2088f074bbec048fd881aa`
(20,125,645,456 bytes). Its image-backed unit cohort is GREEN (Haskell unit/property plus
PureScript 83/83), and image-backed documentation lint is GREEN. The canonical Linux CPU cohort
on this immutable digest passed the complete machine-independent gates, exact Harbor publication
and registry-only verification, typed cluster readiness, routed publication, and staging of all 12
configured models. It then failed during real `llm-tinyllama-gguf` inference because a live
`/proc/<pid>/stat` sample raced process exit and the next `status` payload lacked `VmRSS`; managed
teardown completed. The prior terminal-status correction was insufficient because Linux can
discard the task memory map before procfs exposes a terminal state. The observer now performs a
fixed three-retry `stat`/`status` recheck, accepts zero only for disappearance or explicit terminal
state, and continues to fail closed for stable live or malformed records. Focused regressions cover
vanished, terminal, live, and malformed recheck evidence. A new exact-source image and canonical
cohort were produced as
`sha256:77b89e61bf6e96bb40978a73b018ecd6c480bf83dfea1b6aaba8b8c04f2236df`
(20,125,740,478 bytes). The image build passed strict Haskell compilation, browser provisioning,
web and Python checks, and all five native-artifact validations. Its image-backed unit cohort is
GREEN (Haskell unit/property plus PureScript 83/83). The canonical Linux CPU cohort on this
immutable digest is now the active gate. Its first attempt stopped before cluster mutation at the
style/realness gate because HLint required eta-reducing the new `readResidentBytes` definition.
That mechanical correction is applied; its source-identity change requires a fresh exact-source
image and complete canonical cohort instead of accepting evidence from this digest. The
replacement image built GREEN as
`sha256:d9cb08af957937ef5658c4b8f4b24cc97497032d5cf21958b82bd9fda6066a3f`
(20,125,766,951 bytes), including strict compilation, browser provisioning, web and Python checks,
and native substrate materialization. Its complete canonical Linux CPU cohort is now active.
That cohort passed every machine-independent gate, exact Harbor publication and registry-only
verification, typed cluster readiness, routed publication, and eager staging of all 12 models, but
real `speech-faster-whisper-ct2` inference reproduced the missing-`VmRSS` exit race. The three 1 ms
rechecks were too short under cohort load; managed teardown completed. The fail-closed
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

**Status**: Active — code-side closed on 2026-08-02; Apple accelerator sign-off remains a
validation-only blocker under Wave Y. Five earlier Sprint 1.20 adversarial reviews rejected their reviewed source. The
first found three High, six Medium, and two Low issues. After the initial authority and runtime
artifact corrections, the second review still found two High, two Medium, and one Low issue:
artifact evidence could escape its shared-lock region, writer locking was conventional rather than
authority-coupled, a stale self-consistent recipe remained admissible, and pathname traversal could
hash a mixed tree. A third focused runtime review found one additional High and two Medium issues:
the package-level capped-engine facade still admitted arbitrary executable/argv/cwd/environment
construction, the draft artifact runtime token remained reusable, and actual
lock-through-reap/cancellation enforcement evidence was absent. A fourth materializer review found
two High and two Medium issues: resolved tool identity was discarded before pathname execution,
Audiveris mount evidence was neither consumed nor recoverable after owner death, Mach-O provenance
could describe bytes other than the copied destination, and malformed `dyld[...]` output could be
accepted as version evidence. Those findings and the missing full-materializer cleanup proof are
under active correction. The malformed-dyld parser correction passes its focused Python contract,
but the attempted selector-based nested-runner supervisor is rejected: a blocking post-`SIGKILL`
wait cannot provide both a hard total deadline and exact designated-owner reap. The Python runner
now retains only in-process package APIs and rejects native CLI and JVM routes for direct
Haskell-owned helper supervision; its AST ownership contract and the complete Python `check-code`
gate passed on 2026-07-27. This is focused code-side evidence only: direct Haskell target dispatch
and helper-owned cleanup remain open, and the superseded selector result is not evidence. A fifth
review rejected the escaping writer/lock
boundary, arbitrary activation callback, pathname-recursive closure identity/scan paths, and
remaining unbounded snapshot, package-discovery, and nested-capture paths. The focused artifact and
compile-fail inventories are still growing with those corrections; no intermediate count is
accepted Phase 1 evidence. A subsequent direct-target audit found one further High issue: the
initial Linux image evidence hashed selected `/opt` payload roots but omitted the system loader,
loader-resolution metadata, and recursively loaded system libraries. The corrected topology must
bind and helper-revalidate the complete fixed ELF/Python/JVM loader closure; immutable-image path
text is not evidence. The Linux generation identity must also bind that complete image-owned target
evidence: a digest of only the metadata root cannot distinguish two image byte sets and therefore
cannot key the generation lease. The same live audit found another High issue in the root-bound
writer draft:
it retained and revalidated the authorized root but converted the authority back to a pathname
before `writeFile`, directory creation, rename, retirement, and the venv/pip/Poetry/protoc/curl/
hdiutil/ditto external mutations. An adversary can swap an intermediate parent after validation and
redirect the effect before the final root recheck. The correction must retain the exact
destination-parent descriptor through each direct effect, use only a validated single leaf at that
boundary, and run external mutators from an exact descriptor-derived working directory with safe
relative operands. Deterministic tests must reject a parent swap at both direct and external-tool
effect boundaries. Darwin does not support traversing `/dev/fd/<directory-fd>/...`, so that pathname
spelling is not portable descriptor-relative evidence. The Audiveris download cache is outside the
engine root and therefore requires its own exact-root lock/writer authority; widening EngineWriter
to all of `dataRoot` is not accepted. The installed-target audit also found that the copied
Python venv's `pyvenv.cfg` still names the source Homebrew home and executable. The venv target itself
is created with `--copies`, but Python hydration must rewrite the structured configuration to the
final artifact-local Python home, reject every residual source path, and prove execution after the
source runtime is unavailable. Independently, installed targets whose canonical executable escapes
the sealed artifact root must be rejected. Fresh final review, exact-source Stage 1, Apple
rematerialization/runtime smokes, the Apple cohort, and the paired `linux-cpu` cohort remain.
A later convergence audit found two additional High-severity construction defects in the
work-in-progress source. The completion and transaction boundaries still admitted caller-supplied
effectful callbacks while live writer/session authority was in scope, and the generation read lease
could be acquired before the helper identities needed to recover a stopped anchor were durably
published. The Apple-owned callbacks have been replaced by private first-order fixture actions; the
remaining provisioning callback and helper ordering are under correction. The accepted order is:
hash the retained candidate, acquire generation-exclusive authority and mint its exact sidecar,
durably publish the already-born anchor/supervisor/pin identities, spend the one-shot start
authority, acquire generation-shared authority in the supervisor, validate the exact generation,
run and reap the target group, rehash, reacquire generation-exclusive authority, and only then
publish the artifact. No review, Stage 1, or cohort evidence is accepted for this draft.
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/host_tools_manifest.md](../documents/engineering/host_tools_manifest.md)

> **Purpose**: Establish the canonical repository scaffold, the one-binary role topology
> (`infernix` sharing the default Cabal library exposed by the `infernix` package), the supported
> control-plane execution contexts, the substrate-selection baseline,
> generated-artifact hygiene, and the repository ownership rules that later phases build on.

## Phase Status

> **No-repo-owned-native-source reopen (2026-07-26).** The correction audit found that
> `src/Infernix/Engines/AppleSilicon.hs` embeds complete Objective-C/C/Metal implementation source
> as Haskell string literals, writes `.h`, `.m`, and `.c` payloads, and compiles them with Clang.
> That is repository-owned, version-controlled native implementation despite its `.hs` container
> and violates the explicit ban on inline or cosmetically relocated native source. Sprint 1.20 has
> deleted that topology and now uses upstream MLX GPU execution plus coremltools device observation,
> with every closed provisioning and installed-smoke operation supervised through the all-Haskell
> bounded self-exec kernel. The candidate is fully hydrated, relocated, authoritatively smoked,
> assigned exact provenance and an actual payload-tree digest, and activated through the fsynced
> sibling transaction. Phase 0 closed on 2026-07-27, so Sprint 1.20 is Active; final review, fresh
> Stage 1, and Apple rematerialization/runtime/cohort evidence must pass before Phase 2 starts. The old
> Sprint 1.14 bridge/source-smoke evidence and every later Apple claim that depends on that bridge
> are historical GREEN-as-run only and nonreusable for this correction.

> **Bounded-command application / bounded-HTTP reopen (2026-07-19).** The 2026-07-18
> single-accelerator cohort run surfaced a Harbor `docker pull` verify hang and a rate-limited
> (403 + `Retry-After`) upstream model download that the Sprint 1.16/3.14/4.28 managed-state kernels
> shipped but did not yet guard at those sites. This phase reopened under
> [Sprint 1.17](#sprint-117-bounded-http-download-kernel-done) to add the bounded-HTTP download
> kernel — the total, typed `DownloadOutcome` ADT, the opaque `RetryAfterSeconds` newtype, and the
> pure `classifyDownloadStatus` — plus the descriptive `User-Agent` and bounded `responseTimeout` on
> the upstream fetch, the substrate the Sprint 4.29 consumer fold and the Sprint 6.40
> `unboundedHttpViolations` lint build on. Both the Managed-State-Transition kernels (Sprint 1.16) and
> this bounded-HTTP application (Sprint 1.17) are closed by
> [Wave V](cohort-validation-waves.md) (2026-07-20): apple-silicon plus `linux-cpu` full-suite
> `test all` green.

> **Real Apple native engines (Sprint 1.15 reopen).** Sprint 1.14 established the headless Apple
> Metal/Core ML materialization lane but populated it with deterministic validation-wrapper runners
> (`AppleSilicon.hs` `infernix_emit_validation_result`) that loaded no model; the Phase 4 realness
> audit confirmed the Apple native engine layer was fake. Phase 1 reopened Sprint 1.15 to
> materialize **real** Apple native engines (Core ML, MLX, llama.cpp/whisper.cpp Metal, CTranslate2,
> ONNX, Audiveris) on the existing runner contract — the scaffold, one-binary role topology, and
> host-manifest contracts from Sprints 1.1–1.14 stand; only the wrapper payloads were replaced.
> Sprint 1.15 and its Apple real-output cohort gate [Wave L](cohort-validation-waves.md) are closed:
> Apple host smoke, Apple Stage 2 integration, and focused routed Playwright pass on real Apple
> inference, and the paired `linux-cpu` full routed real-output gate passed on a real Linux host on
> 2026-06-29 (`infernix test all` green: Haskell style, Python `check-code`, Haskell unit, generated
> web contracts `71/71`, full integration with all real `linux-cpu` outputs and the HA/chaos tail,
> and routed Playwright `9/9`). The removed validation wrappers are tracked in
> [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md); the full attempt chronology
> lives in [cohort-validation-waves.md](cohort-validation-waves.md).

Phase 1 Sprints 1.1 through 1.19 retain their recorded narrower closure. Sprint 1.20 is Active.
The closed foundation work establishes the current
repository scaffold, the one-binary role topology,
the typed runtime-config contract, the baked Linux launcher image, the governed
root-document posture, host-manifest materialization, and the native-only Apple Docker boundary
implemented in this worktree. Sprint 1.12 removes the Colima-oriented Apple prerequisite path and
validates the already selected Docker context plus daemon architecture before Docker-backed Apple
work. The supported Apple path must use an already selected native arm64 Docker daemon, must not
create or switch Docker contexts, must not create a Colima VM, and must not use cross-architecture
emulation. The Linux CPU path must support native Linux amd64 and native Linux arm64 without any
non-native compatibility lane.
Sprint 1.11 removes
`INFERNIX_BUILD_ROOT`, `INFERNIX_DATA_ROOT`, the `INFERNIX_COMPOSE_SUBSTRATE` /
`INFERNIX_COMPOSE_DEMO_UI` runtime fallbacks, `INFERNIX_BOOTSTRAP_YES`, the
`bootstrap::prepend_path` helper, and the host-side `.build` / `chart/charts` bind mounts. The
Linux launcher now selects the GPU image through the same single `compose.yaml` service using a
one-shot `LAUNCHER_IMAGE=infernix-linux-gpu:local` Compose selector, and no longer forwards the
host-repo override. It introduces the `HostConfig` decoder type (reflected schema; no tracked `.dhall`) as the Haskell
record. The Linux bootstrap entrypoints now use the `PATH=/usr/bin:/bin` + `BASH_SOURCE` +
`/etc/passwd` + hardcoded absolute-path discovery convention, and the Linux launcher image bakes
the Helm dependency archive cache at `/opt/infernix/chart/charts/` with
`/workspace/chart/charts` linked to that image-local cache for Helm compatibility. Apple cohort
validation closed in Wave A, and the CUDA Linux cohort closed in Wave C with full `linux-cpu` and
`linux-gpu` gates.

Sprint 1.14 historically closed the Apple build lane reset. It removed the Sprint 1.13 Tart
implementation (`hostTart`, `AppleTart`, and Tart argument builders) from the current host-tool
schema and retargets the retained `infernix internal materialize-metal-engines` command to typed
engine-artifact manifest materialization. Its then-supported Apple Metal/Core ML target used a
fixed repository-owned runtime bridge beside typed engine-artifact manifests. The
2026-06-16 Apple host refresh built `./.build/infernix`, staged `apple-silicon`, materialized the
typed Metal/Core ML engine manifests, proved the generated Metal bridge smoke
(`Metal runtime probe passed on Apple M1 Max`), proved the installed `coreml-native` runtime-load
smoke (`Core ML runtime probe passed`), and reran the local unit, lint, docs, focused
`lint files/docs/proto/chart`, routed e2e, and aggregate `test all` gates against the former
validation-wrapper state. Sprint 1.15 replaced those wrapper payloads with real Apple native runner
roots and was closed by Wave L. Sprint 1.14 remains historically `Done` only for its Tart-removal
and manifest/install-root scope; every bridge/source/Clang-dependent claim is superseded by Sprint
1.20 and is not reusable evidence.

## Current Repo Assessment

The repo matches the supported Phase 1 ownership contract: the control plane has a
Haskell command registry, the governed root docs point at canonical
`documents/` topics with explicit metadata, and the Linux launcher uses a baked image snapshot.
Lifecycle and validation commands
validate the initialized repo-root `./infernix.dhall` through binary-owned preflight and fail fast
naming `infernix init` when it is absent, while explicit internal helper invocations remain
available for direct inspection.
The Linux substrate Dockerfile also materializes a build-arg-selected copy inside the image
overlay during image build, supported Compose runs keep the Linux build root in the image
overlay rather than bind-mounting the host `./.build/` tree, and the Helm chart archive cache
lives in the image overlay at `/opt/infernix/chart/charts/`. Sprint 1.12 removes the Colima tool
field from the `HostConfig` decoder type and the matching Haskell records, removes `AppleColima`
planning and profile start/stop/restart behavior from `src/Infernix/HostPrereqs.hs`, and adds
unit-level Docker-boundary coverage for native arm64 versus non-native daemon architectures.
The Wave A Apple Silicon validation closed the full positive lifecycle and negative
no-daemon boundary gates named below. The Sprint 1.13 Tart helper, `hostTart` field, and
`AppleTart` prerequisite are no longer part of the current host-tool schema or prerequisite path.
The supported Apple build contract keeps the host free of Xcode and moves Metal/Core ML
materialization to typed engine-artifact manifests plus public upstream MLX/Core ML package APIs.

## Substrate Foundation

This phase owns the baseline distinction between execution context and substrate.

- execution context answers where `infernix` runs
- the built substrate answers which README matrix engine column is active
- the supported substrate ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`

## Sprint 1.1: Canonical Repository Scaffold [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `cabal.project`, `app/Main.hs`, `src/Infernix/`, `compose.yaml`, `docker/`, `python/`, `web/`, `chart/`, `kind/`, `proto/`
**Docs to update**: `README.md`, `documents/README.md`, `documents/architecture/overview.md`

### Objective

Create the repository skeleton described in [00-overview.md](00-overview.md).

### Deliverables

- root Haskell project files: `infernix.cabal`, `cabal.project`, `app/Main.hs`, and a shared
  `src/Infernix/` library tree
- repo-owned implementation roots for `chart/`, `kind/`, `proto/`, `docker/`, `python/`, `web/`,
  `test/`, and `documents/`
- a repo-owned build doctrine that keeps host-native artifacts under `./.build/`
- a repo-owned durable-state doctrine rooted at `./.data/`
- one obvious home for service code, frontend code, cluster assets, and governed docs

### Validation

- `find . -maxdepth 2 -type d | sort` shows the planned top-level directories
- host builds materialize `./.build/infernix`
- the repo carries no competing `docs/` tree or alternate root layout contract

### Remaining Work

None.

---

## Sprint 1.2: Haskell Binary and CLI Contract Foundation [Done]

**Status**: Done
**Implementation**: `app/Main.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Service.hs`, `src/Infernix/Webapp.hs`
**Docs to update**: `README.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`

### Objective

Make `infernix` the operator executable and the shared long-running role entrypoint, including the
demo HTTP Webapp role.

### Deliverables

- `infernix` is the only supported repo-owned long-running daemon entrypoint
- the demo HTTP host is selected through `infernix service --role webapp`
- the supported operator command families close through:
  - `service`
  - `cluster up|down|status`
  - `cache status|evict|rebuild`
  - `kubectl`
  - `lint files|docs|proto|chart`
  - `test lint|unit|integration|e2e|all`
  - `docs check`
- the executable links the default Cabal library exposed by the `infernix` package
  (declared in `infernix.cabal` without an explicit library name and depended on as `infernix`)
- cluster helpers and test helpers do not become extra supported executables

### Validation

- `./.build/infernix --help` prints the supported command families
- the CLI reference docs align with the supported surface above

### Remaining Work

None.

---

## Sprint 1.3: Dual Operator Execution Contexts [Done]

**Status**: Done
**Implementation**: `compose.yaml`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `src/Infernix/Service.hs`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`

### Objective

Support Apple host-native operation and containerized Linux operation without creating two
different products.

### Deliverables

- Apple Silicon runs `./.build/infernix` directly on the host and shells out to host-installed
  `kind`, `kubectl`, `helm`, and Docker
- `cluster up` publishes `./.build/infernix.kubeconfig` on Apple without mutating
  `$HOME/.kube/config`, while Kind create or delete uses a transient host-local scratch
  kubeconfig first
- `cluster up` publishes `./.data/runtime/infernix.kubeconfig` on the Linux outer-container path
  so fresh launcher containers reuse the same durable cluster handle, while Kind or `nvkind`
  create or delete uses a transient execution-local scratch kubeconfig off repo-visible bind
  mounts
- `infernix kubectl ...` automatically targets the repo-local kubeconfig on supported paths
- Linux uses Compose only as a one-command launcher:
  `docker compose run --rm infernix infernix <subcommand>`
- `docker compose up` and `docker compose exec` are not supported operator workflows

### Validation

- after `./.build/infernix internal materialize-substrate apple-silicon`,
  `./.build/infernix cluster status` executes without an outer container on Apple Silicon
- after the Apple cluster is present, `./.build/infernix kubectl get nodes` works without
  manually setting `KUBECONFIG`
- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  `docker compose run --rm infernix infernix cluster status` executes on the Linux outer path
- repeated supported cluster create or delete reruns do not depend on preserving repo-local
  `infernix.kubeconfig.lock` artifacts because Kind or `nvkind` operates on a scratch kubeconfig
  and the lifecycle republishes the durable repo-local kubeconfig afterward

### Remaining Work

None.

---

## Sprint 1.4: Build Artifact Isolation and Web Build Generation Path [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Lint/`, `src/Infernix/Lint/HaskellStyle.hs`, `web/`, `test/haskell-style/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`

### Objective

Keep compiled artifacts out of tracked source paths, establish the web build path, and make
static quality enforceable through canonical entrypoints.

### Deliverables

- host-native Haskell builds materialize `./.build/infernix`
- outer-container staged substrate output stays under `/workspace/.build/outer-container/` inside
  the launcher image, while cabal package state and cabal's build directory stay in the image
  overlay
- explicit substrate materialization stages `infernix.dhall` under the active build
  root; `cluster up` consumes that staged file, republishes it for cluster consumers, and fails
  fast if it is absent
- the supported web build regenerates frontend contracts, runs `spago build`, and emits
  `web/dist/app.js`
- repo-owned Haskell validation enables strict compiler warnings and treats warnings as errors
- `infernix test lint` and `infernix test unit` are the canonical static-quality and unit entrypoints

### Validation

- direct Apple host builds install `./.build/infernix`; any
  `dist-newstyle/` tree is Cabal's disposable untracked build cache rather than a repo-owned
  generated source path
- `npm --prefix web run build` regenerates frontend contracts and emits `web/dist/app.js`
- `infernix test lint` fails on docs drift, warning regressions, or build-artifact policy drift

### Remaining Work

None.

---

## Sprint 1.5: Initial Substrate Identifier Baseline [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Types.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Make the substrate identifier set explicit so the later substrate-generated `.dhall` closure builds
on one clearly named contract instead of hidden flag behavior.

### Deliverables

- the canonical substrate ids are `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate remains independent of control-plane execution context
- unsupported substrate ids fail with typed user-facing errors
- the current generated file, `cluster status`, and generated browser-contract payloads serialize
  those substrate ids under `runtimeMode` field names

### Validation

- supported host-native and outer-container workflows resolve the active substrate correctly
- `cluster status` reports the active substrate and publication targets through its current
  `runtimeMode` line
- unsupported substrate ids fail before reconcile or validation begins

### Remaining Work

None.

---

## Sprint 1.6: Haskell-Owned Control-Plane Tooling [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `src/Infernix/`, `src/Infernix/Cluster/Discover.hs`, `src/Infernix/Cluster/PublishImages.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Lint/`, `src/Infernix/Python.hs`
**Docs to update**: `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`

### Objective

Retire custom control-plane Python tooling in favor of Haskell modules under the shared
`infernix` Cabal library.

### Deliverables

- chart discovery, image publication, demo-config loading, docs lint, file lint, proto lint, and
  chart lint are Haskell-owned
- `tools/` carries no repo-owned custom-logic Python on the supported path; in a clean checkout it
  may be absent entirely until generated protobuf stubs materialize under `tools/generated_proto/`
- Python remains only as the engine-adapter boundary governed by later runtime phases
- repo-owned shell is limited to the supported `bootstrap/*.sh` stage-0 host bootstrap surface

### Validation

- `git ls-files tools` reports no tracked Python control-plane helpers outside the generated
  `tools/generated_proto/` stub location
- `infernix test lint` runs Haskell-owned repo checks on the supported control-plane path

### Remaining Work

None.

---

## Sprint 1.7: Repository Hygiene and Generated-Artifact Doctrine [Done]

**Status**: Done
**Implementation**: `.gitignore`, `.dockerignore`, `src/Infernix/Lint/Files.hs`, `documents/engineering/build_artifacts.md`
**Docs to update**: `documents/engineering/build_artifacts.md`

### Objective

Stop tracking generated and disposable artifacts and make the ignore contract enforceable.

### Deliverables

- generated or disposable artifacts are ignored by repository policy:
  - `python/poetry.lock`
  - `web/spago.lock`
  - `web/package-lock.json`
  - `web/dist/`
  - `web/output/`
  - `python/.venv/`
  - everything under `tools/generated_proto/`
  - `.mypy_cache/` and `.ruff_cache/`
  - all `*.pyc` and `__pycache__/` directories
  - `web/src/Generated/`
- `.gitignore` and `.dockerignore` mirror the generated-artifact policy
- `documents/engineering/build_artifacts.md` documents what is source of truth and what is
  regenerated
- `src/Infernix/Lint/Files.hs` fails when the implemented tracked generated-source set returns:
  Python cache files, Poetry or Spago lockfiles, generated protobuf stubs, generated PureScript
  contracts, and mypy or ruff cache directories

### Validation

- `git ls-files | grep -E '(poetry\\.lock|generated_proto/|\\.pyc$|__pycache__/|spago\\.lock|web/src/Generated/|\\.mypy_cache/|\\.ruff_cache/|web/package-lock\\.json|web/dist/|web/output/|python/\\.venv/)'`
  returns nothing
- `infernix test lint` fails when the implemented tracked generated-source set is re-added to git

### Remaining Work

None.

---

## Sprint 1.8: Command Registry, Root Guidance Canonicalization, and Shared Workflow Helpers [Done]

**Status**: Done
**Implementation**: `src/Infernix/CLI.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/Workflow.hs`, `documents/reference/cli_reference.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Establish the Haskell-owned command-registry foundation and reduce root-document drift by giving
each workflow topic one canonical home.

### Deliverables

- one Haskell command-registry foundation owns the
  supported command inventory, parser entrypoint, `--help` output, and CLI-reference lint coverage
- a shared Haskell workflow-helper foundation exists for:
  - npm invocation resolution
  - platform command availability checks
  - shared web-dependency readiness used by both CLI and cluster paths
- later hardening phases collapse helper consumers or literals within the same Phase-1 ownership
  boundary
- `documents/reference/cli_surface.md` becomes a short family overview that links to the canonical
  CLI reference instead of repeating it
- `README.md`, `AGENTS.md`, and `CLAUDE.md` carry governed metadata and canonical-home links back
  into `documents/`, and the automation entry docs stay thin by pointing at one canonical
  assistant-workflow home under `documents/`

### Validation

- `./.build/infernix --help` and the canonical CLI reference enumerate the same supported command families
- `infernix lint docs` fails if the canonical CLI reference drops a supported registry command line
- root-doc workflow summaries point readers at canonical `documents/` topics and carry the governed
  metadata or canonical-home markers for the thin entry-document posture

### Remaining Work

None.

---

## Sprint 1.9: Outer-Container Snapshot Launcher and Playwright Invocation Cleanup [Done]

**Status**: Done
**Implementation**: `compose.yaml`, `docker/Dockerfile`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Config.hs`, `web/package.json`, `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`
**Docs to update**: `documents/engineering/docker_policy.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `README.md`

### Objective

Move the Linux outer-container story to an image-snapshot launcher model and remove `npx` from the
supported browser workflow.

### Deliverables

- `compose.yaml` runs against a baked image snapshot and bind-mounts only `./.data/` plus the
  Docker socket
- the outer-container build root, staged substrate file, and Helm chart archive cache live in the
  image overlay; the source snapshot manifest lives separately at
  `/opt/infernix/source-snapshot-files.txt`, the Helm dependency archive cache lives at
  `/opt/infernix/chart/charts/`, and cabal-home plus the cabal builddir stay at the toolchain's
  natural in-image locations (`/root/.cabal/`, `dist-newstyle/`) and are not bind-mounted, so the
  supported CLI never overrides cabal's default builddir or `CABAL_DIR`
- the substrate image uses `tini` as its `ENTRYPOINT` for clean signal handling and zombie reaping rather than running a custom launcher wrapper script
- the repo-wide `.:/workspace` bind mount and `web/node_modules` runtime volume are removed
- operators rebuild the image when source changes instead of relying on live repo mounts
- supported Playwright workflows use `npm --prefix web exec -- playwright ...` rather than `npx`

### Validation

- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  `docker compose run --rm infernix infernix cluster status` works against the image-local build
  root and the host `./.data/` bind mount
- the launcher container sees the host `./.data/` tree and the Docker socket only; build output,
  chart archives, source, and the live `compose.yaml` stay in the image overlay
- `docker volume ls` lists no `infernix-build` or `infernix-cabal-home` named volumes
- `docker compose down -v` leaves `./.data/` intact on the host and does not manage Linux
  `.build/` state
- `docker inspect infernix-linux-cpu:local --format '{{json .Config.Entrypoint}}'` shows
  `/usr/bin/tini`, and smoke probes confirm normal launched commands run through that entrypoint
- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  a fresh `docker compose run --rm infernix infernix test unit` succeeds because cabal-home and
  the cabal builddir live at the toolchain's natural in-image locations and are not hidden by a
  host bind mount
- `rg -n 'npx playwright' README.md documents src web/package.json` returns no supported workflow references

### Remaining Work

None.

---

## Sprint 1.10: Explicit Substrate Staging, Flag Removal, and Launcher Reset [Done]

**Status**: Done
**Implementation**: `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/CLI.hs`, `docker/Dockerfile`, `compose.yaml`
**Docs to update**: `README.md`, `documents/development/local_dev.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/reference/cli_reference.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace user-selected runtime-mode overrides with one staged substrate file and collapse the
launcher story onto the requested Apple-host-native and Linux-Compose doctrines.

### Deliverables

- the supported CLI removes `--runtime-mode` and all use of `INFERNIX_RUNTIME_MODE`
- the build or explicit staging flow emits one substrate file under the active build root and the
  CLI reads that file as the primary source of truth for active substrate; the Linux Dockerfile's
  image-local copy is the supported outer-container copy
- Apple host-native workflows stage `./.build/infernix.dhall` with
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
- Linux outer-container workflows stage
  `/workspace/.build/outer-container/build/infernix.dhall` inside the launcher image with
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints fail fast when the staged file is absent; focused
  `infernix lint ...` and `infernix docs check` remain substrate-file independent
- Apple Silicon remains the only supported host build path outside a container
- Linux host-native `infernix` execution is not a supported operator surface
- Linux outer-container commands use Compose as the only supported launcher for both `linux-cpu`
  and `linux-gpu`
- Apple operators do not use Compose as a user-facing launcher for ordinary CLI work; Apple
  host-native routed E2E uses host `npm exec` with the same typed fixture and awaits the Apple
  validation pass, while Linux E2E runs Playwright inside the active substrate image
- the NVIDIA-backed Linux substrate is standardized as `linux-gpu`, with the old `linux-cuda`
  naming retired as an explicit compatibility cleanup item

### Validation

- `./.build/infernix --help` no longer documents `--runtime-mode` as a runtime *override* selector;
  it survives only as a config-generation flag on `infernix init` / `infernix test init` (which
  materialize a chosen substrate's `infernix.dhall`), never as a runtime substrate override
- `./.build/infernix internal materialize-substrate apple-silicon` stages the active substrate
  without any runtime-mode flag or user-facing environment override
- supported Linux containerized commands run through `docker compose run --rm infernix infernix ...`
  without any runtime-mode flag or user-facing environment override
- supported Linux lifecycle and aggregate test commands use the substrate file materialized in the
  launcher image build root, without a host `.build` bind mount

### Remaining Work

None.

---

## Sprint 1.11: Host Manifest Materialization [Done]

**Status**: Done
**Implementation**: `src/Infernix/Substrate.hs` (extended), `src/Infernix/HostConfig.hs` (new; the `HostConfig` decoder type is the reflected schema — no tracked `.dhall`), `src/Infernix/HostTools.hs` (new helper module), `src/Infernix/CLI.hs`, `src/Infernix/Config.hs`, `src/Infernix/Webapp.hs`, every `bootstrap/*.sh`, `compose.yaml`, `docker/Dockerfile`
**Docs to update**: `documents/architecture/configuration_doctrine.md`, `documents/engineering/host_tools_manifest.md`, `documents/development/local_dev.md`, `documents/engineering/portability.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the `InfernixHost.dhall` typed config record for every supported execution context
(Apple host-native, Linux launcher container) and refactor every host-tool invocation and every
filesystem-convention lookup to read from `HostConfig` instead of consuming env vars or relying on
PATH. Refactor the bootstrap shell scripts to the supported stage-zero convention
(`PATH=/usr/bin:/bin` reset, `BASH_SOURCE`/`getent passwd` discovery, hardcoded absolute paths for
the small set of pre-binary commands, delegation to the launcher binary for everything else). Move
the build-artefact tree (`./.build/outer-container/build/`) and the Helm dependency archive cache
(`./chart/charts/`) inside the launcher image so the Linux container's host-bind-mount surface
shrinks to `./.data` plus the Docker socket only.

### Deliverables

- the `HostConfig` decoder type (reflected schema) with the `ToolPaths`, `FilesystemConventions`, and
  `HostExecutionContext` records named in `documents/engineering/host_tools_manifest.md`.
- `HostConfig` typed Haskell record in `src/Infernix/HostConfig.hs`, decoded via the `dhall`
  library at every entry point (`runProductionDaemon`, `clusterUp`, `runDemoApiServer`, every
  `infernix <command>`).
- `runHostTool :: HostConfig -> HostTool -> [String] -> IO a` helper module
  `src/Infernix/HostTools.hs`. Every Haskell external-command invocation in this phase's scope
  (`src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Webapp.hs`) routes through
  this helper.
- the materialization helper (`src/Infernix/DemoConfig.hs` `materializeHostManifestFile`, wired
  into `infernix internal materialize-substrate` in `src/Infernix/CLI.hs`) also stages a host
  manifest beside the active build root — on Apple host-native this writes
  `./.build/infernix-host.dhall`; on the Linux launcher the binary's effective build root is
  `/workspace/.build/outer-container/build` so the CLI writes
  `/workspace/.build/outer-container/build/infernix-host.dhall`, while the canonical in-image host
  manifest at `/opt/infernix/dhall/InfernixHost.dhall` is baked separately by `docker/Dockerfile`
  at image-build time and read by `discoverPaths`.
- Bootstrap scripts (`bootstrap/common.sh`, `bootstrap/linux-cpu.sh`,
  `bootstrap/linux-gpu.sh`, `bootstrap/apple-silicon.sh`) refactored to the stage-zero convention:
  first line `PATH=/usr/bin:/bin`, repo root from `BASH_SOURCE`, home dir from `/etc/passwd`, every
  pre-binary command by absolute-path constant, post-binary delegation to `./.build/infernix`
  (Apple) or `/usr/bin/docker compose run --rm infernix infernix` (Linux).
- `INFERNIX_BOOTSTRAP_YES` env var replaced by `--yes` CLI flag on each bootstrap script.
- `compose.yaml` shrinks to one `infernix` service with two bind mounts (`./.data` and the
  Docker socket). The `INFERNIX_BUILD_ROOT` and `INFERNIX_HOST_REPO_ROOT` `environment:` entries
  are removed. The `./.build` and `./chart/charts` bind mounts are removed.
- `docker/Dockerfile` bakes the Helm dependency archive cache into the image at
  `/opt/infernix/chart/charts/` (replacing the previous bind-mount surface). The `ENV
  INFERNIX_BUILD_ROOT=…` directive is removed; the binary discovers its build root via
  `getExecutablePath`.
- Test fixtures in `test/unit/Spec.hs` and `test/integration/Spec.hs` stop calling `setEnv
  "INFERNIX_BUILD_ROOT"` and `setEnv "INFERNIX_DATA_ROOT"`; they pass a typed `HostConfig`
  override instead.

### Validation

- `cabal build all` clean, `infernix test lint` clean, `infernix test unit` clean.
- `grep -rn 'lookupEnv\|getEnv' src/Infernix/{Config,CLI,DemoConfig}.hs` returns zero matches.
- `grep -rn 'INFERNIX_BUILD_ROOT\|INFERNIX_DATA_ROOT\|INFERNIX_COMPOSE_SUBSTRATE\|INFERNIX_COMPOSE_DEMO_UI\|INFERNIX_BOOTSTRAP_YES' src/ bootstrap/ compose.yaml docker/` returns zero matches.
- `./bootstrap/linux-cpu.sh doctor` runs cleanly under `env -i /usr/bin/bash` (empty starting env).
- Wave C closed the Linux stage-zero bootstrap proofs on the native Linux/CUDA host:
  `env -i /usr/bin/bash ./bootstrap/linux-cpu.sh doctor` and
  `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh doctor` both pass under an empty starting env;
  `./bootstrap/linux-gpu.sh status` enters the single `compose.yaml` launcher with
  `LAUNCHER_IMAGE=infernix-linux-gpu:local` and reports the expected `linux-gpu` `cluster-absent`
  status without requiring `compose.linux-gpu.yaml`; and `./bootstrap/linux-gpu.sh build` produces
  the `infernix-linux-gpu:local` launcher image, runs the `infernix --help` smoke check through
  that launcher, and a direct `docker run --rm infernix-linux-gpu:local ...` inspection confirms
  `/workspace/chart/charts` links to `/opt/infernix/chart/charts` with the expected Helm archives
  present and no bind mount.
- Apple cohort validation closed in Wave A; CUDA Linux cohort validation closed in Wave C with
  `./bootstrap/linux-cpu.sh test` and `./bootstrap/linux-gpu.sh test` full-suite passes.
- `docker inspect <launcher-container> --format '{{json .Mounts}}'` shows exactly two mounts:
  `./.data` and `/var/run/docker.sock`.

### Remaining Work

None.

---

## Sprint 1.12: Native-Only Workflow and Apple Docker Boundary [Done]

**Status**: Done
**Implementation**: `src/Infernix/HostPrereqs.hs`, `src/Infernix/HostConfig.hs`, `src/Infernix/Config.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `docker/Dockerfile`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/development/assistant_workflow.md`, `documents/development/local_dev.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `documents/engineering/host_tools_manifest.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the native-only development and validation contract executable. Apple Silicon must never
create or switch Docker contexts, create a Colima VM, or run amd64 Linux through emulation.
Docker-backed Apple work requires the operator's current Docker context to already target a
native arm64 daemon. `linux-cpu` validation belongs on native Linux amd64 or native Linux arm64.

### Deliverables

- remove the supported-path dependency on `AppleColima` and the Colima start/stop/restart
  reconciliation path from Apple prerequisite handling
- replace Apple Docker bootstrap behavior with a Docker-daemon validation step that reports the
  current Docker context and daemon architecture, then fails before cluster work if the daemon is
  absent, non-native, or unavailable in the current process
- update the `HostConfig` decoder type, host-tool manifests, and unit fixtures so Colima is not a
  required supported Apple tool
- keep Linux bootstrap and validation native-only: `linux-cpu` covers native `linux/amd64` and
  native `linux/arm64`; `linux-gpu` remains native amd64 CUDA
- keep root workflow guidance, governed docs, and this plan aligned with the implementation

### Validation

- `rg -n 'AppleColima|ensureColimaDockerReady|startSupportedColima|stopColima|colima start|colima stop' src test dhall`
  returns no supported-path matches after the cleanup lands
- `cabal test infernix-unit` covers Apple host prerequisite decoding and Docker-boundary behavior
- `infernix lint docs` passes through the active execution context
- on Apple Silicon with an already selected native arm64 Docker daemon,
  `./bootstrap/apple-silicon.sh doctor`, `build`, `up`, `status`, `test`, `down`, and final
  `status` run without creating or switching Docker contexts
- on Apple Silicon with no usable native arm64 Docker daemon, the Apple bootstrap fails with a
  prerequisite error and does not create a Docker context or Colima VM
- Wave A closed Sprint 1.12: the Apple positive native-daemon lifecycle gate and the negative
  no-daemon boundary gate both passed on Apple Silicon without creating or switching Docker
  contexts, and the native Linux amd64 `linux-cpu` outer-container regression gate
  (`./bootstrap/linux-cpu.sh test`) confirmed the Colima-removal cleanup and host-manifest schema
  change do not regress the Linux lane

### Remaining Work

None.

---

## Sprint 1.13: Apple Tart Metal-Engine Build Lane [Done]

**Status**: Done
**Historical implementation**: Superseded and removed by Sprint 1.14.
**Code-side closure**: Historical record only — the prior `tart` host-manifest field (Haskell selector `hostTart`), `AppleTart` prerequisite, Tart argument builders, and Tart-backed materialization flow are removed from the current implementation by Sprint 1.14. The retained command name now belongs to the Tart-free manifest materialization lane.
**Cohort gate**: Replaced by Sprint 1.14's headless Apple materialization gate in [Wave I](cohort-validation-waves.md).
**Implementation**: `src/Infernix/HostConfig.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/CommandRegistry.hs`, `src/Infernix/Engines/AppleSilicon.hs`, `bootstrap/apple-silicon.sh`, `test/unit/Spec.hs`
**Docs to update**: `documents/engineering/host_tools_manifest.md`, `documents/operations/apple_silicon_runbook.md`, `documents/engineering/build_artifacts.md`, `documents/architecture/configuration_doctrine.md`, `documents/engineering/docker_policy.md`

### Legacy Note

This sprint records the superseded implementation. It is no longer the supported Apple
materialization target because Tart VM startup can depend on macOS Virtualization.framework
host-key state and an unlocked user login keychain. Sprint 1.14 owns the replacement path and
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) records the completed removal of
`hostTart`, `AppleTart`, and the Tart-backed `materialize-metal-engines` flow.

### Objective

Record the prior attempt to keep the Apple host free of Xcode while producing Metal and Core ML
native engine artifacts. The implementation used a `tart` macOS VM for artifacts that were assumed
to need `xcrun metal`/`metallib` or `coremlc`/`coremltools`, copied outputs to the host, and ran
them against the host Metal device.

### Deliverables

- Historical deliverables were the `hostTart` field, the `AppleTart` prerequisite, a Tart-backed
  build lane in `src/Infernix/Engines/AppleSilicon.hs`, and a retained
  `infernix internal materialize-metal-engines` command surface.
- Sprint 1.14 removes those Tart-specific implementation surfaces and keeps the command name for
  the Tart-free manifest materialization contract.

### Validation

- Historical machine-independent validation covered the former `hostTart` field, `AppleTart`
  requirement, allowlist, and pure Tart argument builders.
- Current validation belongs to Sprint 1.14's headless Apple materialization lane in
  [Wave I](cohort-validation-waves.md).

### Remaining Work

None. The Tart-specific implementation is removed by Sprint 1.14 and recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) as completed cleanup.

---

## Sprint 1.14: Apple Headless Metal/Core ML Materialization Reset [Done]

**Status**: Done
**Code-side closure**: Historical closure for Tart removal, typed manifests, atomic install-root handling, and the then-current payload topology. The repository-owned Objective-C/C/Metal bridge and Core ML smoke source described by the original Sprint 1.14 closure were later found to violate the no-native-source boundary and have been deleted by Sprint 1.20, which became Active after Phase 0 closed on 2026-07-27. Their implementation and validation details are superseded, not a current supported architecture. The former deterministic Apple native runner payloads were separately superseded by Sprint 1.15.
**Cohort gate**: Historical GREEN-as-run for the Tart-removal reset only. The 2026-06-16 generated-bridge and Objective-C Core ML smoke evidence is invalid for Sprint 1.20 and cannot close any correction-dependent Apple claim. Fresh upstream-package Apple evidence belongs to Sprint 1.20.
**Implementation**: `documents/engineering/apple_silicon_metal_headless_builds.md`, `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/HostPrereqs.hs`, `src/Infernix/HostConfig.hs`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `AGENTS.md`, `CLAUDE.md`, `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/build_artifacts.md`, `documents/operations/apple_silicon_runbook.md`, `documents/architecture/configuration_doctrine.md`, `documents/engineering/host_tools_manifest.md`, `documents/engineering/portability.md`, `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace the Sprint 1.13 Tart VM build target with a truly headless Apple materialization lane.
The replacement path must not require Tart, user keychain state, host Xcode UI flows, the offline
`metal` compiler, or request-time SwiftPM/package builds.

### Deliverables

- historically, add the fixed bridge that Sprint 1.20 later deletes as an invalid repo-owned
  native-source boundary; this deliverable is superseded and is not current architecture
- historically, add typed engine-artifact manifests for Apple native payloads under
  `./.data/engines/<adapterId>/` with digest, source reference, runtime fingerprint, entrypoint, and
  smoke-command fields. Sprint 1.20 removes those command-text fields and replaces them with the
  closed recipe/target fingerprint plus exact provenance and direct-target observations
- change Apple materialization so it writes into a temporary root, smoke-validates the manifest
  contract, and atomically renames into the final engine root
- remove `AppleTart` prerequisite reconciliation, `hostTart` as a supported host-tool field, and
  the Tart-backed `materialize-metal-engines` implementation while retaining the command as the
  new headless materialization surface
- keep full Xcode out of the host runtime path; any artifact that still truly requires full Xcode
  remains an explicit residual rather than a supported headless claim

### Validation

- unit coverage for manifest rendering, atomic install-root selection, and failure cleanup
- historical Apple cohort probe for the now-deleted bridge; superseded by Sprint 1.20
- Apple cohort validation still passes when `tart` is absent or unusable and no user
  `login.keychain-db` is unlocked
- `infernix lint docs`, `infernix lint files`, `infernix lint proto`, `infernix lint chart`,
  `infernix docs check`, and `infernix test lint` pass in the active execution context
- Wave I records the Apple materialization smoke and host engine load under the new lane

### Remaining Work

None.

---

## Sprint 1.15: Real Apple Native Engine Materialization [Done]

**Status**: Done
**Code-side closure**: Complete and validated 2026-06-26 on the Apple host. The
`infernix_emit_validation_result` validation-wrapper fabrication is deleted; generated Apple runners
preserve the full native worker contract, enforce model-cache readiness, and return only real native
engine output or non-zero failure. `llama-cpp-cli` and `whisper-cpp-cli` copy the typed
host-manifest Homebrew binaries into their content-addressed candidates and invoke only those
artifact-local Metal-capable CLIs; `ctranslate2-native`, `onnx-runtime-native`, and `mlx-native`
hydrate per-engine
Apple arm64 venvs; `coreml-native` hydrates Basic Pitch plus Apple's Core ML Stable Diffusion
pipeline; `jvm-native` downloads the pinned Audiveris macOS arm64 DMG and installs `Audiveris.app`;
`audio-basic-pitch-coreml` is package-backed; and the Core ML Stable Diffusion row uses a Hugging Face
Core ML snapshot plus an indexed native snapshot hydration path. Proven by
`./bootstrap/apple-silicon.sh build`, `./.build/infernix internal materialize-substrate apple-silicon`,
`./.build/infernix internal materialize-metal-engines`, installed runner smokes (Metal bridge, Core ML,
CTranslate2, MLX, ONNX Runtime, Audiveris), direct Core ML package imports, `./.build/infernix test unit`,
and `./.build/infernix test lint`.
**Cohort gate**: [Wave L](cohort-validation-waves.md) closed 2026-06-29 — Apple integration and
focused routed Playwright real-output gates are green, and the paired `linux-cpu` full routed
real-output gate passed on the real Linux host with rebuilt image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`. The closing
`./bootstrap/linux-cpu.sh test` run passed Haskell style, Python `check-code`, Haskell unit,
generated web contracts (`71/71`), full integration with all real `linux-cpu` catalog outputs and
the HA/chaos tail, and routed Playwright `9/9` including the 22.7-minute per-model browser matrix.

**Implementation**: `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/HostConfig.hs`, `python/native-runners/apple_native_runner.py`, `python/adapters/model_bootstrap.py`, `README.md`
**Docs to update**: `documents/engineering/apple_silicon_metal_headless_builds.md`, `documents/engineering/host_tools_manifest.md`, `documents/operations/apple_silicon_runbook.md`, `README.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `DEVELOPMENT_PLAN/cohort-validation-waves.md`

### Objective

Make the Apple native engine layer run real models, replacing the deterministic validation wrappers
materialized by Sprint 1.14.

### Deliverables

- real Apple runners (llama/whisper Metal, CTranslate2/ONNX host-wheel, Audiveris macOS, MLX, Core ML)
  on the existing runner contract; delete the validation wrappers
- indexed native snapshot hydration for multi-file Core ML model snapshots
- Apple rows stay declared-runnable on their intended engines (declarative-target); each returns real
  output or fails closed

### Validation

- Apple host integration and routed e2e pass only on real Apple inference, paired with the
  `linux-cpu` full-suite gate; the realness lint forbids any reintroduced validation wrapper

### Remaining Work

None.

---

## Sprint 1.16: Evidence and Command Kernels [Done]

**Status**: Done — the Managed-State-Transition Doctrine reopen kernels (`Infernix.Evidence.Readiness`,
`Infernix.Evidence.Lease`, `Infernix.Cluster.Subprocess`) are code-side closed (machine-independent
gates) plus the single-accelerator (apple-silicon) plus linux-cpu full-suite sign-off closed by
[Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-16 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit` (the readiness / lease / subprocess kernel assertions pass), and
`cabal test infernix-haskell-style` (ormolu + hlint + cabal-format clean) all green on the
apple-silicon lane; `infernix lint docs` unaffected. No Python/native change in this sprint, so
`poetry run check-code` does not apply
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
**Implementation**: `src/Infernix/Evidence/Readiness.hs`, `src/Infernix/Evidence/Lease.hs`, `src/Infernix/Cluster/Subprocess.hs`
**Blocked by**: Sprint 0.13
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase — introduce the
foundation kernel modules `Infernix.Evidence.Readiness`, `Infernix.Evidence.Lease`, and
`Infernix.Cluster.Subprocess` (`SubprocessEnv` with required `HOME`/`TMPDIR`, the `CommandOutcome`
ADT, and a bounded child-reaping `runBoundedCommand`); establish the
opaque-newtype-via-export-list discipline and enable `RankNTypes` plus surgical `LinearTypes`. The
kernels encode evidence, not hope: for every system state there is a transition and typed evidence,
and every operation that acts on that state requires the evidence. See the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- `Infernix.Evidence.Readiness` and `Infernix.Evidence.Lease` foundation kernels whose evidence
  types are opaque newtypes constructed only through their own module, exported via export-list
  discipline
- `Infernix.Cluster.Subprocess` with `SubprocessEnv` requiring `HOME` and `TMPDIR`, the
  `CommandOutcome` ADT, and a bounded child-reaping `runBoundedCommand`
- the `RankNTypes` extension plus surgical `LinearTypes` enabled where the kernel discipline needs
  them

### Validation

- `cabal build all`, `cabal test infernix-unit`, and `cabal test infernix-haskell-style` clean
- `infernix lint docs` clean, and `poetry run check-code` for any Python/native change
- the code-side gates above exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

- none — the apple-silicon plus linux-cpu full-suite cohort sign-off closed under
  [Wave V](cohort-validation-waves.md) (2026-07-20); no remaining work exists
- the kernels use `RankNTypes` region leases (zero-dependency, enabled and in use); surgical
  `LinearTypes` (`%1 ->`) is applied at the spend-once consumer sites in the dependent sprints (the
  lease-gated scrub in Sprint 2.14, the sentinel commit in Sprint 4.28, and the token leases in
  Sprint 9.10), where a spent capability must not be reused — region-scoping already suffices for the
  kernel itself

---

## Sprint 1.17: Bounded-HTTP Download Kernel [Done]

**Status**: Done — the bounded-HTTP download kernel (the total `DownloadOutcome` ADT, the opaque
`RetryAfterSeconds` newtype, the pure `classifyDownloadStatus`, and the `User-Agent` + bounded
`responseTimeout` on the upstream fetch) is code-side closed (machine-independent gates) plus the
single-accelerator (apple-silicon) plus linux-cpu full-suite sign-off closed by
[Wave V](cohort-validation-waves.md) on 2026-07-20.
**Code-side closure**: closed 2026-07-19 — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit` (the `classifyDownloadStatus` classification table passes),
`cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, and
`infernix docs check` all green on the apple-silicon lane. No Python/native change in this sprint, so
`poetry run check-code` does not apply.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus
linux-cpu full-suite `test all` green.
**Implementation**: `src/Infernix/Runtime/Pulsar.hs`
**Blocked by**: Sprint 1.16
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Bounded-Command Application & Bounded-HTTP reopen work for this phase — introduce
the bounded-HTTP download kernel that the coordinator model-bootstrap path consumes. The 2026-07-18
cohort run proved the Sprint 1.16 kernels exist but are not applied at the upstream download site:
`downloadUpstreamModelToFile` sent no `User-Agent` (tripping the upstream WAF's 403), set no total
`responseTimeout`, and collapsed every non-200 into one opaque failure retried forever. The kernel
half of the fix is a total, typed outcome ADT with a required classification, encoding evidence, not
hope: "retried forever with no backoff" and "an unbounded transfer" become terms that do not
typecheck. It applies the bounded-outcome shape of
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md)
(the `CommandOutcome` sibling) to the upstream HTTP surface.

### Deliverables

- the total `DownloadOutcome` ADT
  (`DownloadSucceeded | DownloadRateLimited RetryAfterSeconds | DownloadTransient String |
  DownloadPermanent String`) and the opaque `RetryAfterSeconds` newtype in
  `src/Infernix/Runtime/Pulsar.hs`
- the pure, exported `classifyDownloadStatus :: Int -> Maybe Int -> DownloadOutcome` mapping an HTTP
  status plus optional `Retry-After` into that outcome: 429 or 403-with-`Retry-After` →
  `DownloadRateLimited` with a clamped backoff, 5xx → `DownloadTransient`, other non-200 →
  `DownloadPermanent`, 200 → `DownloadSucceeded`
- a descriptive `User-Agent` (`infernix-model-bootstrap/1.0`) and a bounded `responseTimeout` on the
  `downloadUpstreamModelToFile` request, so a UA-less request can no longer trip the upstream WAF and
  no transfer runs unbounded

### Validation

- `cabal build all`, `cabal test infernix-unit` (the `classifyDownloadStatus` classification table),
  `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, and
  `infernix docs check` are exercised on both the apple-silicon and linux-cpu lanes

### Remaining Work

- none — apple-silicon plus linux-cpu full-suite validation of the bounded-HTTP download kernel
  closed under [Wave V](cohort-validation-waves.md) (2026-07-20); no remaining work exists

---

## Sprint 1.18: Observable Readiness — Tri-State Poll Outcome [Done]

**Status**: Done — code-side closed 2026-07-22 on the machine-independent gate set, and the
single-accelerator (apple-silicon) plus `linux-cpu` behavioral cohort sign-off closed under
[Wave W](cohort-validation-waves.md) on 2026-07-24 with no remaining work. The readiness kernel gains an
observable-poll channel so a probe that could not observe a remote system can no longer launder that
fault into a definite not-ready measurement.
**Supersession note**: this sprint supersedes the two-channel Sprint 1.16 kernel step contract
(`awaitReadiness :: Deadline -> IO (Either Progress e) -> IO (Readiness e)`, whose only poll outcomes
were `Right` ready and `Left` a concrete not-ready count). That type forced a probe I/O fault to
launder itself into a fabricated count fed into the kernel's stall/ceiling accounting as ground truth —
the representable invalid state behind the retained-second-`cluster up` warm-model-cache "11/16" stall.
**Code-side closure**: complete (2026-07-22). Landed: `PollOutcome e = Measured (Either Progress e) |
Unobservable Text` and `awaitReadinessObservable :: Deadline -> IO (PollOutcome e) -> IO (Readiness e)`
in `src/Infernix/Evidence/Readiness.hs`; an `Unobservable` poll accrues stall like a non-advancing poll
and cannot advance the running maximum, so it can neither mint a `Ready` nor deflate the observed count
— it only buys another poll within the same bounded `Deadline`. `awaitReadiness` is retained as a
behaviour-identical lift (`awaitReadinessObservable deadline (Measured <$> step)`), so the sixteen
existing count-based callers and the `budgetDeadline` poll-count exactness (hardened under
[Wave V](cohort-validation-waves.md)) are unchanged. Gate set (GREEN 2026-07-22): `cabal build all`
(`-Wall -Werror`), `cabal test infernix-unit` (a scripted `Unobservable`-then-`Measured` stream
resolves `Ready`; an all-`Unobservable` stream gives up bounded `Expired`), and
`cabal test infernix-haskell-style`. No Python/native change in this sprint.
**Cohort gate**: apple-silicon + linux-cpu, [Wave W](cohort-validation-waves.md) — the behavioral proof
that the retained-second-`cluster up` warm-model-cache barrier no longer stalls at "11/16". Closed
2026-07-24 on apple-silicon plus linux-cpu.
**Implementation**: `src/Infernix/Evidence/Readiness.hs`, `test/unit/Spec.hs`
**Blocked by**: Sprint 1.16
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and this plan

### Objective

Close the last representable invalid state in the readiness kernel: a readiness probe that reads a
remote system does not always get to observe it, and the Sprint 1.16 step contract had no channel for
"I could not measure." A transport fault was forced to become a definite `Left progress` count that the
kernel fed into stall/ceiling accounting as ground truth. Make "unobservable" a first-class poll
outcome routed to retry-within-budget, so a transient fault can never masquerade as a measurement. This
is the kernel half of the Observable-Readiness reopen; the warm-model-cache observation surface that
consumes it is [Sprint 8.8](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md).

### Deliverables

- `PollOutcome e = Measured (Either Progress e) | Unobservable Text` and `awaitReadinessObservable`
- `awaitReadiness` preserved as a `Measured`-lift of `awaitReadinessObservable`, so every existing
  caller and the `budgetDeadline` poll-count exactness are byte-identical
- `Unobservable` handling: accrue stall, never advance the running maximum, retry within the deadline;
  a budget expiry while every recent poll was unobservable rides the last real `Progress`
- unit coverage: a bounded transient-fault stream still resolves `Ready`; a persistent-unobservable
  stream gives up bounded (`Expired`)

### Validation

- `cabal build all` (`-Wall -Werror`) compiles the observable kernel with `awaitReadiness` as a lift
- `cabal test infernix-unit` covers the transient-fault-then-ready and persistent-unobservable cases
- `cabal test infernix-haskell-style` passes
- `infernix test all` on apple-silicon plus `linux-cpu` proves the warm-model-cache barrier no longer
  stalls on a retained second `cluster up` — closed under [Wave W](cohort-validation-waves.md)

### Remaining Work

None. The implementation is complete (code-side closed 2026-07-22): the observable-poll channel and the
behaviour-identical `awaitReadiness` lift are landed with unit coverage. The apple-silicon plus
`linux-cpu` behavioral cohort sign-off closed under [Wave W](cohort-validation-waves.md) on 2026-07-24,
paired with [Sprint 8.8](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md); no remaining work
exists. The superseded two-channel-only step-contract framing is recorded in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

---

## Remaining Work

[Sprint 1.16](#sprint-116-evidence-and-command-kernels-done) (the Managed-State-Transition
Doctrine reopen work) and [Sprint 1.17](#sprint-117-bounded-http-download-kernel-done) (the
Bounded-Command Application & Bounded-HTTP reopen work) are both closed by
[Wave V](cohort-validation-waves.md) (2026-07-20) — apple-silicon plus linux-cpu full-suite
`test all` green. [Sprint 1.18](#sprint-118-observable-readiness--tri-state-poll-outcome-done)
(the Observable-Readiness reopen) is closed under [Wave W](cohort-validation-waves.md) (2026-07-24) —
apple-silicon plus `linux-cpu` behavioral sign-off (code-side closed 2026-07-22 on the
machine-independent gate set); no remaining work exists for Sprints 1.16–1.18.

## Sprint 1.19: Execution-Plan Compiler And Capability Core [Done]

**Status**: Done — complete source-matched machine-independent gate and final adversarial source
review passed on 2026-07-25
**Implementation**: `src/Infernix/ExecutionPlan.hs`, `src/Infernix/ExecutionPlan/Internal.hs`,
`src/Infernix/Runtime/Enforcer.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Worker.hs`,
`src/Infernix/Runtime/Daemon.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Substrate.hs`,
hidden configuration/routing modules, and focused unit/integration/negative-compilation suites
**Docs to update**: `documents/architecture/typed_execution_plan.md`,
`documents/architecture/bounded_inference_memory.md`,
`documents/architecture/configuration_doctrine.md`, `documents/architecture/daemon_topology.md`,
and `documents/architecture/runtime_modes.md`

### Objective

Introduce resource-indexed Haskell execution alternatives, confine raw decoded configuration, compile
the validated graph into an opaque `CompiledRuntimePlan`, and allow only package-owned live
observations to refine it into `RuntimePlan` / `ExecutableModel`. Phase 8 Sprint 8.9 owns the final
proper-union generated-Dhall wire migration.

### Deliverables

- `RawRuntimeConfig -> Either ConfigErrors CompiledRuntimePlan`
- hidden constructors for executable placements, positive quantities, resource-indexed grants, and
  enforcer plans
- coordinator routing consumes only compiled placements and daemon capabilities and returns a
  typed terminal result for requests to explicit unavailable placements; engine subscription and
  launch consume only refined runtime/executable capabilities
- routing and launch APIs cannot accept raw model/config records
- unavailable, empty-model, unknown-model, wrong-route, and malformed coordinator/engine requests
  terminate as failed results before their file source is removed or Pulsar message is acknowledged
- model-bootstrap publication consumes only an opaque plan-derived capability; the consumer
  revalidates model identity, compiled download URL, and canonical request timestamp before side
  effects
- compilation rejects cross-family reuse among coordinator-request, result,
  model-bootstrap-request, model-bootstrap-ready, and engine-route topics
- substrate Dhall emission is explicit UTF-8

### Validation

- compiler/refinement properties reject zero values, resource/enforcer mismatch, oversubscription,
  dangling placement references, unavailable live enforcers, and configured/live partition drift
- an integration-focused coordinator test proves that a request for `UnavailableModel` publishes
  `status=failed` with the compiler-produced typed `ModelMemoryLimitExceeded` and never selects an
  engine batch topic or launches a worker
- coordinator and engine tests prove empty, unknown, wrong-route, and malformed messages produce
  one terminal failed result before source removal/acknowledgement
- bootstrap tests reject model/URL/timestamp drift before download or publication side effects,
  and negative/API tests prove no raw topic publisher remains
- compiler properties reject every cross-family topic collision, and a non-ASCII substrate fixture
  round-trips through UTF-8 Dhall emission and decode
- negative compile fixtures reject coordinator routing without compiled placement/daemon authority,
  engine launch without `ExecutableModel`, and imports of hidden raw decoders or routing helpers
- machine-independent gate set passes

### Remaining Work

None. Sprint 1.19 closed on 2026-07-25.

### Closure Record

The closed construction includes:

- `MemoryGrant resource`, `MemoryCeiling resource`, `Enforcer resource`, and `EnforcedGrant
  resource` keep the resource witness aligned through the launch boundary; the superseded
  unindexed grant API in `Infernix.Types` is removed
- pure compilation produces a `CompiledRuntimePlan`; only package-owned live observations can
  refine it into `RuntimePlan` / `ExecutableModel`
- model compilation and route construction are total: every configured model is represented
  exactly once as a compiled placement or explicit `UnavailableModel`, and an unexpected graph
  inconsistency returns `ConfigErrors` rather than being filtered out
- coordinator and engine request dispatch now return terminal failed results for unavailable,
  empty-model, unknown-model, and wrong-route requests; malformed protobuf produces a typed failed
  result. File-spool sources are removed and Pulsar messages acknowledged only after that terminal
  result is written or published
- each executable placement carries its validated pool/member/topic routes, engine binding, grant,
  and live enforcer; public worker and capped-engine launch APIs require the whole
  `ExecutableModel`
- daemon compilation produces opaque `CompiledDaemon` capabilities keyed by engine member, after
  proving exact role/member coverage, location, derived topics, result topic, subscription, and
  connection mode; subscription startup consumes those capabilities
- the sanctioned runtime enforcer facade probes Apple physical-footprint and the live checked host
  partition, or Linux process-group RSS plus the exact current cgroup-v2 envelope, before
  refinement; configured/live partition drift and missing observations fail closed, and
  per-execution sampling still fails closed if the mechanism later disappears
- checked `Integer` arithmetic rejects host-partition overflow, and compilation rejects model
  ceilings that cannot be represented in the watchdog byte domain; unsupported adapter types and
  GPU-required work in the `linux-cpu` lane are also structural configuration errors
- raw Dhall decoders and topic-derivation helpers now live only in hidden package modules; exported
  config validation compiles the same plan used at startup, while the generator-facing catalog API
  remains configuration-only
- Pulsar drain/consume authority is an opaque daemon-topic capability derived from one compiled or
  refined plan; runtime, daemon, and topic can no longer be mixed independently, and engine launch
  additionally proves that the decoded model's routes contain the exact daemon member/topic pair.
  The raw topic publisher is removed. Model-bootstrap publication requires an opaque
  `ModelBootstrapRequestCapability` prepared from the compiled plan, and the consumer revalidates
  the exact model identity, compiled download URL, and canonical timestamp before any download,
  upload, or ready-event side effect. Dispatcher, result, bootstrap, and eager-staging paths derive
  their topology from the same plan
- a second adversarial pass removed `Read` from opaque grants/ceilings/partitions/footprints and
  assigns nominal roles to every resource index, so neither textual construction nor
  `Data.Coerce` can relabel evidence; strict canonical identifiers close filesystem traversal, and
  `TopicFamilyCollision` rejects reuse across coordinator-request, result,
  model-bootstrap-request, model-bootstrap-ready, and engine-route topic families
- executable engine metadata now resolves through one exact runtime-scoped allowlist and the
  compiler rejects every field drift, unknown choice, and cross-runtime choice before an engine
  binding becomes executable; generated `edgePort = 0` remains the supported unpublished sentinel
- Apple Colima observation now fails closed on missing/malformed probes and conservatively counts
  every profile not explicitly `Stopped`; Linux refinement compares live `memory.max` with the
  configured child limit plus daemon/sampler headroom rather than a particular model's smaller
  grant, and non-MiB-aligned byte limits fail closed instead of being rounded into agreement
- launch APIs derive runtime, model, and binding identity only from `ExecutableModel`, reject a
  mismatched request model before side effects, and no longer accept a caller-controlled runtime
- substrate materialization encodes the generated Dhall text with explicit UTF-8 before writing
  bytes, preserving non-ASCII operator/model metadata
- the production library and executable build are clean under `-Wall -Werror`, and the complete
  source-matched gate passed after the final refinement and Pulsar-capability coherence edits

Closure evidence on the Apple Silicon development host:

- `cabal build all test:infernix-integration`
- the unit, internal-boundary, compile-fail, and Haskell-style suites; compile-fail coverage passed
  all 4 positive fixtures and all 27 negative fixtures
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
- the installed binary's `lint files`, `lint docs`, `lint chart`, `lint proto`, and `docs check`
- Python `check-code`
- web contract generation, unit tests, `spago build`, and bundle generation, including all 83/83
  web unit tests
- `git diff --check`
- a final adversarial source review with no remaining Phase 1 production blocker

Phase 4 Sprint 4.32 owns the ordered substrate implementation/behavioral proof after Phase 2
closes; NVIDIA per-process accounting remains fail-closed until its later GPU phase.

---

## Sprint 1.20: Remove Embedded Apple Native Source [Active]

**Status**: Active — **no longer validation-only as of 2026-08-08.** Two code-side defects in this
sprint's own surface were found on Darwin after the
[2026-08-08 evidence reset](cohort-validation-waves.md), so the "code-side closed" claim below is
narrowed to the scope it was true for on 2026-08-02 and does not describe the current tree. See
`Remaining Work — reopened 2026-08-08` at the end of this sprint. The prior status text follows,
retained for its recorded scope: code-side closed on 2026-08-02; Apple accelerator sign-off remains a
validation-only blocker under Wave Y. The settled source passes the complete machine-independent
gate set and the paired source-matched `linux-cpu` full-suite cohort on exact image
`sha256:51292f6f3d98560b383a4ab5cc8a1807aa5388fa5cc0ba8c99b305d90ba9ff67`.
The final settled-source adversarial review found no High or Medium residual. The historical
correction narrative below records how earlier rejected identities were repaired and must not be
read as current remaining work. The capped-engine/anchor group-owner defect recorded below **is** corrected — cleanup no
longer force-terminates an anchor that is still retiring its own snapshot generation, and a group
whose exact leader is reaped mid-signal is proven absent within a bounded window instead of being
rejected outright. Phase 0's
correction gate closed on 2026-07-27, and five Phase 1 reviews
rejected successive follow-on drafts. Native-source deletion and the exact/legacy transaction
distinction are present. The opaque tool/session boundary and smoke-bound activation are being
strengthened, while a non-escaping one-shot artifact runtime session, closed Python/native
invocation languages, writer authority, current-recipe fingerprint, descriptor-anchored tree
snapshot, recursive host-runtime closure, full-materializer failure/cancellation proof, obsolete
bridge retirement, and Audiveris mount-death recovery remain under active correction. Earlier
focused/aggregate results cannot close this sprint. Review #5 rejected the writer boundary because
an authority could escape the exclusive lock inside an `IO` closure; it also found an arbitrary
post-activation `IO` callback, pathname-recursive closure identity/scan paths, unbounded snapshot
recovery and package discovery, and unbounded nested native-runner pipe capture. The Python
nested-child topology has since been deleted: native CLI and JVM routes fail closed into direct
Haskell supervision, while the remaining Python routes use only in-process upstream APIs. The
Apple-runner AST ownership contract and the complete Python `check-code` gate passed on
2026-07-27. The remaining paths are being replaced by one lock-interpreted indexed session,
descriptor-relative bounded traversal, and a closed installed-validation action. The live
correction audit also found that the capped-engine cleanup
path reaped its process-group leader before signaling a numeric PGID, leaving a PID/PGID-reuse
window. Phase 1 cannot close until a live exact helper identity remains owned through group
termination and designated-owner reap; a PID-only recheck around `signalProcessGroup` is not
accepted. That finding is now corrected in the bounded-command kernel — the exact helper identity is
retained through control close, the bounded self-exit window, escalation, designated reap, and the
group-absence proof, and a leader reaped mid-signal never causes a bare-PGID signal — and the
`infernix-unit` group-lifecycle assertions covering it execute and pass for the first time. Focused
direct `ghc -fno-code -Wall -Werror` checks on 2026-07-27 proved that the
then-current candidate/mount authority fields participated in the ordered and negative fixtures. A
subsequent compiler check invalidated the callback-shaped positive as the final protocol design:
ordinary `IO` bind cannot retain a linear success continuation without an unsafe multiplicity cast
or a linear-effect runtime. The correction therefore uses hidden, runner-owned indexed sequencing
so a caller never receives a droppable, reusable, or skippable next-phase continuation. Fresh
production-dependent fixtures and the aggregate compile-fail suite remain pending with the
coordinated Stage 1. The latest live audit also measured the existing Core ML artifact at about
1.7 GiB (roughly 47,000 entries), which makes the then-current full-artifact package-snapshot copy
fail its 512 MiB bound and makes raising that copy bound an invalid per-command design. Candidate,
post-activation, and installed execution must instead retain an exact generation-specific kernel
lease through target reap. Every candidate/final mutation and recovery path must acquire the
writer side of that lease, and a replacement materialization writer must recover the exact durable
activities of dead owners before any root-mutation authority is minted. Pre-publication target
start remains impossible through the typed gate; post-publication cleanup is driven by the exact
persisted anchor, supervisor, and target-group identities.
The current convergence audit additionally rejects effectful completion/transaction callbacks while
live authority is in scope and any generation-read acquisition before recoverable helper identities
are durable. The Apple transaction fixtures now use a private first-order action language. The
provisioning completion and bounded-helper implementation remain in progress: generation-exclusive
authority must mint the exact sidecar before smoke, the parent must durably publish the already-born
anchor/supervisor/pin identities before spending start authority, and only then may the supervisor
hold generation-shared authority through target-group absence and designated-owner reap. Candidate
rehash and exclusive revalidation must precede publication. No evidence from this draft is accepted.
The focused adversarial-test audit also found target cleanup assertions that publish and probe only
a numeric target PID while retaining exact birth identity only for the helper group leader. Those
assertions are not accepted evidence: every owned target fixture must publish its exact birth
identity and prove absence or designated-owner reap against that identity, including stopped-group,
timeout, cancellation, and concurrent-session cases.
As of 2026-07-29 the Linux ELF/loader closure producer and its helper-side revalidation are
implemented with machine-independent fixture coverage, and the Audiveris JavaCPP question is decided
in favour of materialization-time pre-extraction. Two residuals recorded above were found to be
misstated: the Linux generation fingerprint already binds the image-owned evidence, and the
writer-effect count was an undercount — the real figure was 21 pathname-resolving writer functions
across 34 effect sites plus four external-tool operands, enumerated in
[Loader-Closure Producer and Writer-Effect Audit](#loader-closure-producer-and-writer-effect-audit-2026-07-29)
below.

**Writer-effect items 1–10 of that enumeration are now closed**, and neither
`Engines/Provisioning.hs` nor `Engines/Artifact/Internal.hs` has any remaining pathname-resolving
write effect on a production path. The pathname `synchroniseProvisioningDirectory` is deleted in
favour of a descriptor form (which forced each of its thirteen callers to hold the parent it had
mutated through); the mutation kernel gained a symbolic-link constructor and an atomic regular-file
replace; and the durable-record family, stable file copy, recursive package-closure copy, fixed
owned directory/link, candidate manifest publish, and candidate venv relocation are all anchored on
retained parent descriptors.

Item 10 was closed with a **closed first-order root-mutation language**. The mutation kernel lives in
`Cluster.Subprocess`, which already imports the public `Engines.Artifact` and
`Engines.MaterializationLock` facades, so `Artifact/Internal.hs` cannot import it without closing a
cycle; extracting the kernel into a lower module is the honest placement but entangles with the
self-exec anchor machinery. The transaction therefore requests two named effects and the provisioning
facade — the only holder of both the writer root and the kernel — interprets them. The interpreter is
retained on the activation token, so a rollback cannot be handed a different one than the forward
transaction used. Converting it also removed a pathname write *above* the authority root
(`createDirectoryIfMissing`), every pathname directory fsync, and a per-entry pathname
`removeDirectory` inside the recursive retirement walk that the enumeration had not identified —
that whole walk is now one bounded descriptor-anchored kernel call.

**Three of those closed on 2026-07-30**, with the complete machine-independent gate set green on one
frozen identity (recorded below): item 11's parent-swap tests including the first coverage of the
production root-mutation interpreter, the closure bounds' reachability through exported accessors and
pure folds, and the Linux sealed-run loader observation.

The loader-observation work exposed a **previously unrecorded High-severity defect**: the exact-capture
classifier applied the `dyld` audit to every smoke, so the Linux native artifact smoke could not pass
on any input. Correcting it then exposed a **design contradiction in the Linux lane** — the smoke is
built on the Apple installed-artifact shape while the `linux-native` catalog says its targets are
absolute image payloads. That choice has now been made explicitly (bind the smoke to the image
target) and its six enumerated steps are landed.

Closing the generation-lease consumer residual on 2026-07-30 then exposed **two further High-severity
defects, neither reachable by any machine-independent gate**. The Linux sealed-run environment
contracts named `LD_DEBUG` alone while every rendered command also carries the renderer's fixed
bytecode guard, so the Linux native artifact smoke was still refused on every input — behind, not
instead of, the wrong-audit defect. And the runtime inference launch never rendered the closed
catalog's leading arguments at all: wrapper retirement rebuilt only the smoke's argument rendering,
so every Python-runner artifact reached its runner without the `--adapter-id`/`--engine-name` pair
the runner requires. Both are corrected with regression coverage measured against the pre-correction
source. The residual the second one exposed — the two raw-CLI adapters have no runtime argument
translation at all — is a design decision and is now tracked as open.

**The generation-lease consumer residual closed on 2026-07-30**, and closing it exposed two further
High-severity defects that no machine-independent gate reached — the Linux sealed-run environment
contract could not admit the shape its own renderer produces, and the runtime launch never rendered
the closed catalog's leading arguments, so every Python-runner artifact failed at argument parsing.
Both are corrected with measured, discriminating regression coverage; all three are recorded under
[Generation-lease sub-item 2 closed](#generation-lease-sub-item-2-closed-and-two-high-findings-behind-it-2026-07-30)
below.

Still open: the raw-CLI runtime argument translation (a design decision the leading-argument
correction deliberately did not pre-empt), the JavaCPP pre-extraction, final closure *values*
(blocked on the `jvm-native` measurement), the remaining impure-surface regression coverage, a fresh
final adversarial review, an exact-source Stage 1 on a genuinely quiet host, and both cohorts. The
Apple cohort and the `jvm-native` measurement are additionally **hardware-blocked** on this host —
see [Accelerator Availability Inverted](README.md#accelerator-availability-inverted-on-the-current-host-2026-07-30).
### Current Correction State (2026-07-27, post-base-`19202a5`)

The recorded base `19202a5` **does not compile**. `cabal build all` fails with six errors in
`src/Infernix/Cluster/Subprocess.hs` (a redundant `Infernix.ExecutionPlan.Internal` import, a
redundant `Infernix.Types` import list, two shadowed bindings, a defaulted `fileSize` comparison,
and an unused `sourceEntry` match) and, past those, with a linear-multiplicity rejection at
`src/Infernix/Runtime/CappedEngine/Internal.hs:350`, a three-way arity disagreement on
`runClosedLinuxNativeArtifactSmoke`, a dangling `resolvedRunnerPythonIdentity` export, nineteen
hygiene errors in the never-typechecked `src/Infernix/Engines/Provisioning.hs`, two in
`src/Infernix/Engines/AppleSilicon/Internal.hs`, and compile errors in three test suites.
Every "the production modules compile", "the ordered compile gate passed", and per-suite result
recorded before this entry is therefore **not** evidence for this tree; the recorded
"4 positive and 27 negative" and "5 positive and 50 negative" compile-fixture inventories are both
stale.

The following corrections are landed and compiler-verified in the current worktree:

- **Runner-owned indexed sequencing replaces the unsound linear reap.** `reapArtifact`'s
  `ValidatedEngineArtifact s %1 -> IO ArtifactTerminalOutcome` transition could not be honoured by
  any ordinary `IO` consumer without an unsafe multiplicity cast, which is exactly the defect this
  sprint already recorded. `Infernix.Engines.Artifact.Capability` now exposes a hidden-constructor
  `ArtifactRun s phase`, a closed first-order `ArtifactLaunchRequest`, and an unprivileged
  `ArtifactLauncher`. `withFirstValidatedEngineArtifact` owns validate → revalidate → launch → reap
  itself, so a caller never receives a validated capability, a phase value, or a droppable,
  reusable, or skippable continuation, **and can no longer skip the use-boundary revalidation** it
  previously had to perform for itself. The use-boundary window is pinned by a private first-order
  `ArtifactPreLaunchFixture` action language rather than a caller-supplied `IO` hook.
- **The Linux native artifact smoke is reconciled onto the corrected Apple shape.**
  `runClosedLinuxNativeArtifactSmoke` now takes the generation lease, the retained
  `ProvisioningMutationRoot`, and the exact `NativeArtifactTargetEvidence`, validates the lease
  against its exact artifact root and adapter, compiles through `compileRenderedCommand` with a
  descriptor-derived working directory, revalidates the recorded target's configured entry,
  canonical entry, and canonical bytes immediately before launch, and runs under
  `runBoundedCommandExactCapture`. `activateLinuxEngineArtifactWithInstalledSmoke` derives that
  evidence from the published manifest and fails closed when the manifest carries none. The
  superseded pathname-based `runClosedProvisioningSmoke` / `closedSmokeArtifactRoot` /
  `observeClosedProvisioningExecutable` / `observeClosedArtifactRoot` path is deleted.
- **Fifteen superseded pathname-effect helpers are deleted** from
  `src/Infernix/Engines/Provisioning.hs` (`provisioningDoesPathExist`, `provisioningDoesFileExist`,
  `provisioningGetModificationTime`, `provisioningCanonicalizePath`, `provisioningPathInfo`,
  `provisioningReadBoundedNoFollow`, `provisioningFileExecutable`, `listDirectoryBoundedNoFollow`,
  `synchroniseProvisioningFile`, `digestRegularFileNoFollowExact`, `authorizeProjectPath`,
  `authorizeGeneratedBindingsPath`, `runProvisioningCommand`, `runProvisioningCommandWithIdentity`,
  `runProvisioningCommandWithExecutable`), each already superseded by its writer-scoped
  `...InWriter` replacement. The fixed runtime closure copy now checks its returned entry count
  against `maximumPoetryClosureFiles`, and the package-closure symlink copy requires its entry to be
  one validated safe leaf of the retained parent.

Current machine-independent gate state on this worktree:

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN |
| `cabal test infernix-compile-fail` | GREEN — **6 positive, 78 negative** |
| `cabal test infernix-artifact-transaction` | GREEN — 44 cases |
| `cabal test infernix-apple-materializer` | GREEN — 9 cases (default machine-independent mode) |
| `cabal test infernix-capped-engine-observer` | GREEN |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `poetry --directory python run check-code` | GREEN |
| web `npm run test:unit` | GREEN — 83/83 |
| `cabal test infernix-unit` | GREEN when it passes, but **flaky under host load** — see the load-sensitivity note below |
| `cabal test infernix-haskell-style` | GREEN — `ormolu --mode check`, `hlint`, readability rules, and the Cabal manifest check |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

The complete machine-independent gate set first went GREEN on pre-evidence tracked-plus-untracked
worktree digest `sha256:9f75c2deaa3086f7aa018e5c5fdf421c8e059b83223cf106f81045e3f326a132` with
installed Apple binary `sha256:2a1e8262bbdbb840fc303e142e2c60baa8fcfadbd512f81744a8d8377bb49f6e`,
and is GREEN again after the Apple cohort corrections recorded below, most recently on worktree
`sha256:f5e5f2e6a578c82cefc588f697856e72fe3dbc4c1456833e1c2317c80e2da32b` with installed binary
`sha256:d0efb87169124b4eb3da6f1d1dbd88ec6b4ff8898d89f4c0dffa7762131bd9c4`. Only Haskell sources and
this plan changed between those two identities, so the web and Python gate results carry forward
unchanged. This is machine-independent evidence only. It is not Sprint 1.20 closure: the
architectural residuals in `Remaining Work` below, a fresh final adversarial review, an exact-source
Stage 1, the Apple rematerialization/runtime smokes, and the paired `linux-cpu` cohort are all still
open.

**The complete machine-independent gate set is GREEN on the tree carrying the shebang correction**,
worktree `sha256:2987480c42324790842554bd0d043769984077179b9bd7848fbca6f9fe240517` with installed
binary `sha256:b6214ebcbb1e68c824e3e026bec086f2b6a36cc484386a860c8ada927ad54e10`: `infernix-unit`,
`infernix-haskell-style`, `infernix-compile-fail`, `infernix-artifact-transaction`,
`infernix-apple-materializer`, `infernix-capped-engine-observer`,
`infernix-execution-plan-internal`, `infernix lint files`, `lint docs`, and `git diff --check`. The
web and Python gates carry forward unchanged, since only Haskell sources and this plan have changed
since they last ran.

On the latest tree carrying the Audiveris corrections
(`sha256:fbd98a34b63e1757b142d628f886e6d638716dadd13e94896c7a7d5890f212e2`, installed binary
`sha256:c62ca6b863f55498024317ea788e072b913855b3d9d31a5ac1ccca414f13540d`), the six deterministic
suites, `lint files`, `lint docs`, and `git diff --check` are GREEN, and the Apple-cohort regression
block inside `infernix-unit` passes. That suite as a whole again hit the load-sensitivity below.

**`infernix-unit` is load-sensitive and this is not yet closed.** On the current tree the suite
passed cleanly, then failed three consecutive times with three *different* symptoms on unchanged
source: `bounded-snapshot-after` timing out and leaving an unreclaimed `.anchor-*` snapshot root; a
supervisor-`SIGSTOP` fixture never observing its descendant pid; a target exec failure appearing to
enter retry backoff; a `<<timeout>>` whose cleanup then reported
`signalProcessGroup: permission denied`; and `cancelled snapshot acquisition did not finish its
rollback`. Throughout, this host carried a sustained ~68% CPU background load from the system
`audiomxd` daemon.

Every symptom is a deadline being missed rather than a wrong result, and the individual bounds were
already raised above the kernel's contractual cleanup worst case, so the most likely reading is host
load. That reading is **not** established, and one observation deserves follow-up on its own merits:
the `EPERM` from `signalProcessGroup` during forced cleanup is the same Darwin behaviour recorded
below for the test helper — a process group whose only remaining member is an unreaped zombie answers
`kill(-pgid, 0)` with `EPERM`, not `ESRCH`. The test-side probe was corrected to wait through that
state; whether every production cleanup path discharges it correctly has not been proven, and a
timeout is exactly the path that would expose it. Until the suite is demonstrated repeatably green on
a quiet host, the machine-independent gate set must be treated as **not** currently green on this
tree, and the earlier all-green identities below stand only for the trees they name.

`src/Infernix/Engines/Artifact/Target.hs` was unformatted at the recorded base, so the style gate
could not have passed there either; it is formatted now.

Closing the style gate exposed that its stage order — `ormolu`, then `hlint`, then the repo-owned
readability rules, then the Cabal manifest check — had never reached the readability stage, because
`hlint` failed first. The 26 mechanical `hlint` hints (`Use when`/`unless`/`isJust`/`notElem`, eta
reductions, one redundant multi-way `if`, one `newtype`, one lambda-case, one `catMaybes`, one
`<&>`, two `Hoist not`) are corrected. Behind them the readability stage then reported 30 further
violations that no recorded gate result had ever covered: 27 hanging-`case` expressions across
`Cluster/Subprocess.hs`, `Engines/Provisioning.hs`, `Engines/AppleSilicon/Internal.hs`,
`Engines/Artifact/Activation.hs`, `Engines/MaterializationLock/Internal.hs`, `Lint/HaskellStyle.hs`,
`Python.hs`, and `test/unit/Spec.hs`, plus three governed-boundary violations. Each hanging `case`
is now a named helper. The three boundary violations were real doctrine breaches and are corrected
at the boundary rather than by widening an allowlist:

- **`Cluster/Subprocess.hs` imported `Engines/Artifact/Internal` and
  `Engines/MaterializationLock/Internal` directly.** The bounded-command kernel is a helper-side
  reader and revalidator, not an engine-root writer, so it must not hold raw transaction or
  exclusive-lock authority. The four validators it actually uses
  (`validateArtifactGenerationPayloadLease`, `validateEngineArtifactHelperLease`, and the two
  runtime expectations) are now exported from the public `Infernix.Engines.Artifact` validation
  facade, and the validated lease description plus its pure accessor
  (`artifactGenerationLease`, `artifactGenerationLeaseFields`) from the public
  `Infernix.Engines.MaterializationLock`. A lease value names a generation; it carries no authority
  over one, which still comes only from acquiring a lock around it. Neither `.Internal` module is
  imported by the kernel any more.
- **The synchronous-exception tree target spawned its descendant with `env = Just []`.** That strips
  the `HOME`/`TMPDIR` the typed `SubprocessEnv` guarantees. The target is itself executed with the
  supervisor's explicit, validated target environment, so the descendant now inherits that
  already-closed environment; reconstructing it in the child would require reading the ambient
  environment, which the no-env doctrine forbids.

Restoring the build exposed nine further production defects that no gate could previously reach.
All nine are corrected:

- **`fdRead` end-of-file is a throw, not an empty result.** `System.Posix.IO.ByteString.fdRead`
  raises an EOF `IOError` rather than returning an empty `ByteString`, so every read loop written
  as `if ByteString.null chunk then <end-of-stream>` had unreachable end-of-stream handling — and
  each loop that reads one byte past a descriptor's declared size to detect growth threw on every
  complete read. Eight loops across `Cluster/Subprocess.hs` and `Engines/Provisioning.hs` now route
  through an EOF-tolerant chunk reader; `Artifact/Internal.hs`, `Subprocess/Activity.hs`, and the
  bounded protocol readers already used the correct idiom.
- **`withGeneratedBindingsMutationLockInternal` locked inside a directory nobody creates.** The
  `<repositoryRoot>/tools` parent is untracked and is otherwise created only later inside the
  session, so every Apple provisioning session aborted with `ENOENT` on a fresh checkout. It now
  owns its parent exactly as `withEngineMaterializationLock` owns the engines root.
- **`withTryEngineArtifactReadLock` required a sidecar only a writer could create.** A reader on an
  image-baked engine root failed before acquisition. The reader now uses the same
  `ensureRealLockLeaf` the writer does, retaining every sameness check.
- **`validNormalizedAbsolutePath` admitted `..` components**, so an attacker-controlled
  `LC_LOAD_DYLIB` install name of the form `/usr/lib/../<anywhere>` was laundered through the
  `systemMachOPath` prefix allowlist and silently dropped from the vendored closure. Normalized
  absolute paths must now contain no `.` or `..` component.
- **Retirement proved detachment by a link-count decrement that Darwin does not exhibit.** APFS
  leaves a retired directory's link count unchanged when observed through the retained descriptor.
  Retirement now proves the exact retained parent no longer resolves the entry, which also rejects a
  same-name replacement created between removal and the check.
- **Legacy declarative validation required a generation fingerprint** that pre-correction roots
  cannot have, so no legacy root could ever be classified as a migration predecessor or rollback
  root. `validateManifestContract` now takes an explicit `ManifestContractMode`; the legacy mode
  requires the fingerprint's *absence*, and the decoder tolerates a manifest that omits the field.
- **Two exactness checks were applied across a legitimate mutation.**
  `stableExecutableStatus` compares size, mtime, and ctime, and was used to compare a freshly
  created zero-byte staging file against itself after the write, and a writer's parent directory
  against itself after the authorized mutation. Both now assert object identity plus mode; the
  post-write descriptor-versus-reopened-entry comparison stays exact.
- **The `infernix-apple-materializer` suite never dispatched the internal subprocess mode**, so
  every self-exec child died and the parent saw a truncated protocol frame.
- **The abandoned-snapshot recovery sweep raced the rightful owner's retirement.** The parent sweeps
  `command-executable-snapshots` while the helper that created a root is retiring it, so the sweep
  could observe a half-retired root and fail the whole cleanup. A root — or its owner record — that
  disappears under the sweep is being retired by its owner and is now skipped, leaving that owner's
  own retirement step to report.

The stale assertions corrected alongside them were the `venv/bin/python` →
`venv/bin/infernix-python` rename, a Core ML Stable Diffusion contract still asserted through the
deleted nested-subprocess flags, a relocation fixture rooted outside its authorized writer root, a
`pyvenv.cfg` fixture with no `home`/`executable` fields, and a missing-Poetry expectation that
assumed the failure surfaced inside the kernel rather than at tool resolution.

Working the `infernix-unit` tail in order then exposed four further defects that no recorded gate
result had reached. All four are corrected:

- **Cleanup force-terminated an anchor that was still retiring its own snapshot generation.**
  `cleanupSupervisedProcesses` unconditionally `SIGKILL`ed the anchor group before closing the
  anchor's control channel, so an anchor that had already delivered a correct terminal frame was
  killed mid-retirement. The attempt was then reported as `CommandFailedKernel "anchor terminal
  disagreed with anchor exit ExitFailure (-9)"` even though the target had produced exactly the
  right output, and the anchor's executable-snapshot root leaked. Cleanup now takes a typed
  `AnchorShutdownExpectation`: an attempt whose supervisor protocol reached a terminal frame closes
  the control channel first and grants the anchor the same bounded window the designated reap uses
  to exit on its own, escalating to `SIGKILL` only if it outlives that window. Every other path —
  protocol failure, expired attempt deadline, asynchronous cancellation — keeps the prompt
  kill-then-close teardown and pays no shutdown grace period, so failure teardown latency is
  unchanged.
- **`SynchronousExceptionTreeEvidence` decoded all three identities as process-group leaders.**
  Only the retained pin is a leader; `validateSynchronousExceptionTree` explicitly requires the
  target and its descendant to differ from the leader and to share its process group, so both are by
  construction non-leader members. The record now decodes them through the existing
  `parsePrefixedMemberIdentity`, which is what the sibling target-setup frame already uses. This
  resolves the previously undecided question in favour of the record contract being wrong: the
  publisher was already correct.
- **A group whose exact leader was reaped mid-signal was treated as a hard failure.**
  `signalActivityProcessGroupWith` reads the leader's birth identity, then looks up its process
  group. When the designated owner reaps the leader between those two steps while it is still
  terminating the remaining members, the lookup fails and the code demanded the whole group already
  be absent — racing the very owner doing the teardown. The bare process-group id is still never
  signalled, because a reaped leader can no longer prove the group id was not reused; instead the
  group must become absent within a bounded window, which is the same evidence the caller would
  otherwise have obtained.
- **`TestTargetSetupFailure` asserted the wrong provenance stage.** The forced fault is injected
  after the target's birth event and identity gate but before its start gate, so the supervisor
  observes it while awaiting the exact identity. The assertion named the earlier pre-birth stage's
  message and therefore could never hold.

Two test-side bounds were also raised from 7s and 8s to 20s. Both cases assert that a bounded
command returns after its own timeout (3s and 5s respectively), but the kernel's contractual cleanup
bounds — helper protocol close, designated reap, group-absence proofs, and the anchor stderr capture
— sum to roughly nine further seconds. The original bounds were below that contractual worst case,
so a loaded host reported a scheduling delay as a cleanup defect. Measured runtimes on an idle host
are 2.8s and 4.4s. Separately, `waitForProcessGroupAbsent` treated `EPERM` as fatal; Darwin answers
`kill(-pgid, 0)` with `EPERM`, not `ESRCH`, while the only remaining group member is an unreaped
zombie, which is the ordinary transient state after a group's owner is killed and its children are
reparented. `EPERM` is neither absence evidence nor a defect, so the probe now waits for the group
to disappear outright and reports a plain `False` on budget exhaustion.

### Apple Cohort Attempt 1 (2026-07-28)

The first Apple behavioural run against the machine-independent-green tree started at the required
`./.build/infernix internal materialize-metal-engines` precondition and rejected that tree. The
materializer failed immediately, before creating any artifact root, with
`resolved Mach-O executable changed before closure resolution`.

The cause is a comparison that could never hold. `resolveExactMachORuntimeLibraries` re-resolves its
subject **from that subject's canonical path**, then compared the re-resolution with
`resolvedExecutableIdentityMatches`, which requires the two *configured* paths to be equal. The
re-resolution's configured path is the canonical path by construction, so the check can only pass
when the tool was already canonical — and the Apple host manifest names
`/opt/homebrew/bin/python3.12`, a Homebrew symlink into
`/opt/homebrew/Cellar/python@3.12/.../bin/python3.12`. Every Apple materialization with a
Homebrew-managed interpreter was therefore unreachable. This is not a flake and no earlier Apple
evidence covers it: the affected path is Sprint 1.20 replacement source.

The correction adds `resolvedExecutableCanonicalIdentityMatches`, the comparison this re-resolution
shape actually needs. It keeps full exactness — same canonical path, same device, inode, mode, size,
mtime, and ctime, same content digest — and additionally requires the observed resolution to be
genuinely canonical, so a symlink swapped in at the canonical path is still rejected. It drops only
the configured-path and configured-status comparisons, which describe different objects on the two
sides by construction. Four call sites across two functions used the defective comparison after a
canonical re-resolution and are corrected: the two in `resolveExactMachORuntimeLibraries` (before
and during closure resolution) and the two in the fixed-executable copy (before and after copy). The
`resolveProjectPython` site is left unchanged: it re-resolves from the *same configured path*, so
the original comparison is correct there, and `walkMachOClosure` likewise compares configured path
against configured path.

Past that correction the run reached and completed the first artifact's hydration —
`llama-cpp-cli` copied its executable plus the complete recursive dylib and ggml plugin closure
(`libllama`, `libggml`, `libggml-base`, `libmtmd`, `libllama-common`, `libllama-cli-impl`, `libomp`,
`libssl`, `libcrypto`, and the `libggml-cpu-apple_m1`/`m2_m3`/`m4`, `libggml-metal`, and
`libggml-blas` backends) into its candidate root — and then failed with
`venv: openFdAt: does not exist`. `completeMetalEngineCandidate` called
`relocateCandidateVenvInSession` unconditionally for every artifact, but only a Python-backed
candidate owns a `venv` whose launchers and configuration must be rewritten to the final root before
smoke. A native-binary (`llama-cpp-cli`, `whisper-cpp-cli`) or Audiveris JVM candidate has no `venv`
directory at all, so a correctly hydrated candidate failed closed and no Apple artifact could ever
be activated. The relocation is now selected by the typed hydration witness
(`PythonHydration` / `HostBinaryHydration` / `AudiverisHydration`) rather than by a tolerant
filesystem probe, so an absent venv under a Python candidate remains fatal.

The next failure was `installed runner emitted no DYLD loader provenance`. The installed smoke is
the authority that proves a sealed generation actually loads its own libraries, and
`validateRetainedArtifactLoaderEvidence` requires `dyld[...]` frames on its stderr — but
`SmokeInstalledRunner` rendered through `fixedProvisioningProcess`, whose only environment entry is
`PYTHONDONTWRITEBYTECODE`. `DYLD_PRINT_LIBRARIES` was supplied only on the executable-snapshot path,
which this command explicitly disables (`renderedExecutableIdentity = Nothing`), so the smoke could
never emit the provenance its own validator demands. The rendering now carries
`artifactSnapshotRuntimeEnvironment` for the smoke's exact relative target. That function's three
cases — `native/bin/{llama,whisper}-cli`, `fixedVenvPythonRelativePath`, and
`Audiveris.app/Contents/MacOS/Audiveris` — are exactly the three values
`installedSmokeExecutableRelativePath` returns, and the resulting environments match the
`appleNativeSnapshotNames`, `applePythonSnapshotNames`, and `appleJvmSnapshotNames` closed shapes
that `validateSupervisorTargetEnvironment` already admits, so the wiring was simply absent.

Supplying that environment then exposed the last layer: `validateRenderedEnvironment`, the earlier
whitelist applied to a rendered command's *extra* environment, admitted only five literal
alternatives (empty, the bytecode guard, the bytecode plus no-user-site pair, and two `KUBECONFIG`
shapes) and rejected the sealed-artifact runtime environment as
`bounded command generated an unsupported command environment`. Because these entries name
artifact-root-relative paths, they cannot be enumerated literally, so the whitelist now delegates to
`validateSealedArtifactRuntimeEnvironment`, which validates them structurally: the name set must be
exactly one of the same three closed shapes, names must not repeat, `PYTHONDONTWRITEBYTECODE`,
`PYTHONNOUSERSITE`, and `DYLD_PRINT_LIBRARIES` must each carry their fixed value, and every element
of `DYLD_FRAMEWORK_PATH`, `DYLD_LIBRARY_PATH`, `GGML_BACKEND_PATH`, and `PYTHONHOME` must be a
non-empty absolute NUL-free path. This keeps the rendered-environment surface closed rather than
widening it to arbitrary values.

The anchor's own configuration decoder then rejected the same environment with
`bounded-command Python closure path escaped its executable snapshot`.
`validateSupervisorTargetEnvironment` required every runtime closure path to lie inside the
*executable snapshot root*, which is correct for a snapshotting command but wrong for this one: the
installed smoke deliberately carries no executable snapshot and executes the sealed artifact
directly from its generation's install root, so its closure legitimately resolves there. The
validator now takes the owned roots rather than one root — the executable snapshot root plus the
install roots the command's own lease expectations authorize — and requires each closure path to lie
within one of them. The containment requirement itself is unchanged; only the set of roots the
command actually owns is now complete, and a command with no lease is still confined to its snapshot
exactly as before.

Choosing that root correctly took two attempts and is worth recording, because it is the same
distinction the transaction doctrine turns on. `boundedArtifactLeaseExpectation` is decoder-side
only — no parent-side path populates it — so the first correction derived the root from the
*generation lease* (its engines root joined with the adapter it names). That is the **final** install
root, and it is the wrong root here: a candidate is hydrated, relocated, and smoke-validated
*before* its atomic sibling swap, so the installed smoke executes from `<installRoot>.tmp`, not
`<installRoot>`. The owned root is instead taken from the retained provisioning mutation authority
the command already carries, which names exactly the root that command may execute and mutate
within, candidate or final.

With the environment accepted end to end, the smoke finally ran and emitted loader provenance, and
the audit parser rejected it as `installed runner emitted malformed DYLD loader provenance`. On
macOS 26.5 `DYLD_PRINT_LIBRARIES` emits more than load records under the `dyld[<pid>]:` prefix. A
standalone `llama-cli --version` produces 645 load records of the form `<uuid> /absolute/path` plus
395 scheduling frames of the form `move loaded to delayed: <library name>`, and the sealed run —
which sets `GGML_BACKEND_PATH` and therefore `dlopen`s its backends — also produces the inverse
`move delayed to loaded: <library name>`. Those frames name a library, never a path, and are dyld
bookkeeping about moving an image between its loaded and delayed-initialization sets rather than
load provenance. The parser scanned every prefixed frame for its first `/` and failed closed when a
frame contained none, so these frames made the smoke unusable on this OS.

The parser's first correction enumerated those two transitions as non-load frames and failed closed
on every other unrecognised frame. That enumeration proved brittle and was itself corrected after a
third form appeared during the Core ML smoke:
`libgcc_s.1.1.dylib has weak-def (or flat lookup) symbol used by libgfortran.5.dylib, so cannot be
delayed`. Each macOS release may add more such messages, and two separate rounds of this smoke were
broken by exactly that.

The rule is therefore inverted rather than extended. **Only a frame that announces itself as a load
record is loader provenance** — a hex-and-dash `<uuid>` followed by an absolute, canonical, NUL-free
path, or the older `loaded: <path>` spelling. Every other `dyld[...]` frame is loader commentary
carrying no path. This launders nothing: a path is only ever extracted from the load-record forms,
and a frame that *claims* to be a load record while violating the shape still fails closed. The
guarantee that the smoke actually observed its own generation does not come from per-frame
strictness at all — it comes from the aggregate checks that at least one path was loaded, at least
one came from the sealed artifact, and no unsealed non-system library was loaded. A future dyld that
changed its load-record format would fail loudly there rather than pass silently, which is the
behaviour worth having. The malformed-frame error also quotes the offending frame, because the first
rounds of this diagnosis were blind without it.

Classifying those frames then exposed a second, dependent defect. `DyldAuditLine` was two-valued, so
a frame that was not a load record was necessarily *application* output, and the installed-runner
classifier falls back to the non-`dyld` stderr lines when a runner writes its version banner to
stderr — as `llama-cli --version` does. Admitting the roughly four hundred scheduling frames as
application output made that fallback a multi-kilobyte blob, and the exact runtime-version parse
rejected it as `empty, oversized, or contains NUL`. The type is now three-valued: a scheduling frame
is loader output, contributing neither loader provenance nor a line of the runner's own diagnostics.

The same parse then failed for the opposite reason — an *empty* output — which exposed that the
stdout-else-application-stderr fallback existed on only one of the two terminal classifiers. The
kernel has parallel `String` and `ByteString` paths: `classifyTargetTerminal`, used by
`runBoundedCommand`, resolves an installed runner's validated output through
`validateInstalledRunnerLoaderEvidence`, while `classifyExactCaptureTerminal`, used by the
`runBoundedCommandExactCapture` path the installed smoke actually takes, validated loader provenance
and then passed raw stdout straight through. `llama-cli --version` writes nothing to stdout and
reports `version: 9870 (2d973636e)` on stderr, so the exact-capture path handed the version parser
an empty string. `validateRetainedArtifactLoaderEvidence` now returns the runner's own diagnostics —
the stderr lines that are not `dyld` frames of either kind — and the exact-capture classifier
applies the same stdout-else-application-output rule its `String` counterpart already did. Raw
stderr is still never substituted for application output.

With real diagnostics finally reaching it, the version parse rejected them as
`llama-cli smoke must emit exactly two lines`. The sealed artifact sets `GGML_BACKEND_PATH`, which is
exactly what makes its Metal and CPU backends loadable from the generation, and ggml therefore
reports each backend it loads on stderr *before* the version banner. Both CLI parsers assumed their
banner was the only output — llama.cpp's exactly two lines, whisper.cpp's exactly one — so neither
could ever parse a correctly configured sealed runner. Both now locate their banner within the
runner's legitimate diagnostics instead of assuming it stands alone, and neither is loosened
further: llama.cpp still requires exactly one `version:` line whose immediately following line is a
valid build-provenance line, whisper.cpp still requires exactly one version line, and every
build/commit/version atom check is unchanged.

**Both native-binary artifacts then materialized and activated end to end** — `llama-cpp-cli` and
`whisper-cpp-cli` each hydrated with their complete recursive runtime closure, smoked with validated
loader provenance, parsed their exact runtime version, hashed their payload, and completed the
fsynced sibling activation. This is the first Apple artifact activation of the correction.

The first Python-backed artifact then failed at `install pinned Apple engine pip` with
`provisioning command has no exact executable authority`. A provisioning command carries that
authority in one of two forms: a target outside the mutation root keeps its resolved identity on the
rendered command, while a target *inside* that root has its authority deliberately moved by
`compileProvisioningCommandWithExecutableInMutationRoot` into
`boundedRetainedExecutableExpectation`, which the helper revalidates against the retained parent
descriptor. A candidate venv's own interpreter is necessarily the second form, but `runBoundedCommand`
recognised only the first, so every in-root provisioning target was rejected. The guard now accepts
either form and still rejects a provisioning command carrying neither.

The Core ML venv then exceeded `maximumPoetryClosureBytes`. The 512 MiB bound cannot hold a Core ML
environment this plan itself measured at about 1.7 GiB, and the 128 MiB `maximumExactRuntimeFileBytes`
is below several single shared libraries in a PyTorch-class environment. Both are raised
provisionally — to 12 GiB and 2 GiB — **specifically to obtain the per-artifact measurements this
sprint requires before the final values are chosen**; they are not yet the settled bounds. The first
two artifacts measure `llama-cpp-cli` at 19 MiB across 24 entries and `whisper-cpp-cli` at 4.8 MiB
across 19 entries, which confirms the sealed artifacts are small and it is the *source* venv closure
being scanned that is large.

With the bound raised, the Core ML environment installed and reached the recursive Mach-O closure
walk, which rejected it with `no inherited LC_RPATH resolves dependency @rpath/libjaccl.dylib`. That
library exists nowhere on the host, because it is referenced through a **weak** load command.
`machODylibLoadCommands` collects `LC_LOAD_DYLIB`, `LC_LOAD_WEAK_DYLIB`, `LC_LAZY_LOAD_DYLIB`,
`LC_REEXPORT_DYLIB`, and `LC_LOAD_UPWARD_DYLIB` and then required *every* one to resolve, but `dyld`
binds an unresolved weak or lazy dependency to null at run time — its absence is the documented
contract, not a defect. `MachOInspection` now records which dependencies came from those two
commands, and an optional dependency that no inherited `LC_RPATH` resolves contributes nothing to the
closure instead of failing it. A required dependency that does not resolve is still fatal, and every
resolved dependency — optional or not — is still walked, vendored, and validated exactly as before.

Weak-dylib tolerance was necessary but not sufficient: the same
`@rpath/libjaccl.dylib` failure recurred because that reference is a *required*
`LC_LOAD_DYLIB`, not a weak one. Naming the depending image and the searched stack in the error
located the real defect immediately — `required by …/coreml-native.tmp/venv/…/mlx/lib/libmlx.dylib;
searched []`. Direct inspection confirms the shape: MLX's `core.<abi>.so` declares
`LC_RPATH @loader_path/lib` and loads `@rpath/libmlx.dylib`; `libmlx.dylib` declares **no rpath of
its own** and loads `@rpath/libjaccl.dylib`, which sits beside it in that same directory. `dyld`
resolves it because the rpath stack accumulates down the load chain.

The closure walk seeds its queue both from real dependency edges *and* from every Mach-O found by
scanning the package closure, and the scanned roots inherited only the interpreter's rpaths — empty
here. A scanned root is not a load root: it is reached through some loader in that same closure, and
that loader supplies the stack. Scanned roots now inherit every rpath the closure itself declares,
each expanded relative to the image that declares it, bounded by the existing
`maximumMachORpathStack`. Every such path is one a real loader in this closure supplies, which is
exactly the set `dyld` could use, so this restores dyld's semantics rather than widening the search.
The seeding inspections go through `cachedMachOInspection`, so the image, byte, and metadata bounds
still account for each image exactly once.

#### Delocated-wheel install names

`requireSafeMachORelativeSuffix` rejected any install-name suffix containing `..`, which stopped the
Core ML environment at
`Mach-O install name has an unsafe relative suffix: @loader_path/../.dylibs/libopenblas64_.0.dylib`.
That form is not an anomaly: `@loader_path/../.dylibs/<name>` is the layout every delocated Python
wheel uses — NumPy, SciPy, and Pillow all vendor their shared libraries this way — so the flat ban
made every remaining Python artifact unvendorable. The rule was also already inconsistent with its
sibling: `expandMachORpath` accepts `..` in an `LC_RPATH` and collapses it through
`collapseMachORpath`, on the stated grounds that `@loader_path` and `@executable_path` are canonical
directories so a lexical collapse agrees with kernel resolution.

Relaxing it required care, because the flat ban was carrying real weight here. The containment that
looked like a backstop is not one: `materializeRuntimeLibraries` *copies* every library that is not
already inside a covered root rather than rejecting it, so with the ban simply removed a wheel could
name `@loader_path/../../../../..` and vendor an arbitrary host dylib into the sealed artifact.

The ascent is therefore admitted **only when the anchoring image lives inside one of the package
closures being walked, and only while the collapsed target stays inside that same closure**. The
closure roots are threaded from `resolvePoetryRuntimeLibraries` through the walk to
`anchoredMachOPath`. An image outside every closure — a host CLI and its own runtime closure, which
legitimately vendors from Homebrew prefixes — keeps the strict no-ascent rule unchanged, so the
already-passing `llama-cpp-cli` and `whisper-cpp-cli` paths are untouched. `@rpath` suffixes also
keep the strict rule, since they are resolved against a search stack rather than a fixed anchor.

`machOInstallNameAscentTest` in the Apple materializer suite covers all four cases: a delocated
wheel's vendored library resolves inside its closure, an install name ascending out of its closure is
refused, an image outside every closure keeps the strict rule, and a descending install name is
unaffected. The separate fixture-graph resolver keeps its own strict rule, so the existing
`@loader_path/../outside.dylib` refusal is unchanged.

Clearing the Mach-O closure exposed the venv relocation pass. `rewriteRelocationEntry` opens each
candidate entry read-write to rewrite the pre-relocation root out of it, and treats any open failure
as "this entry must be a directory or a symlink". A copied interpreter is neither:
`venv/bin/infernix-python` is a read-and-execute regular file, so the rewrite open fails with
`EACCES`, the directory probe then fails with `ENOTDIR`, and the entry was rejected as
`provisioning entry is neither openable nor a symlink`. Diagnosing this needed the underlying open
error, which the message discarded; it now carries it, because a candidate is retired before it can
be inspected by hand.

A skipped regular file is now accepted. That is safe without assuming anything about its contents:
the residual scan independently reads every regular file in the activated candidate and fails closed
if any still carries the pre-relocation root, so a file that genuinely needed rewriting cannot pass
unnoticed — only files that cannot be rewritten *and* contain nothing to rewrite survive.

The relocation then failed on
`.../coreml-native.tmp/python-home/bin/target: getSymbolicLinkStatus: does not exist`, which exposed
a defect in the bounded-command kernel rather than in provisioning.
`materializeExactExecutableSnapshot` copied the target to the fixed leaf `<snapshotRoot>/target`,
renaming the program. That is invisible to a target that does not record its own path, but
`python -m venv` writes `executable = <snapshotRoot>/target` into the new environment's
`pyvenv.cfg` — a durable record naming both an ephemeral snapshot root and a program that never
existed under that name. `rewritePyvenvConfig` then derived the interpreter leaf from that record and
looked for `python-home/bin/target`, which the copied Python home does not contain.

The snapshot now preserves the executable's own filename, validated as a single safe path component.
The integrity mechanism is unchanged — the snapshot is still an exact copy under a private
per-anchor root, still identity-checked before launch — but it no longer renames the program, so a
target that records `sys.executable`, `argv[0]`, or any equivalent records a truthful leaf.

#### Host shebangs in the copied Python home

With the snapshot leaf corrected, the Core ML candidate reaches its residual scan and is rejected
with
`Apple engine candidate retained a forbidden source path: .../python-home/bin/2to3-3.11`.

The scan is **correct** and the rejection is the doctrine working as intended: this sprint requires
that Python hydration "rewrite the structured configuration to the final artifact-local Python home"
and "reject every residual source path". `copyExactPackageClosure` copies the host Python home
wholesale, and its `bin/` console scripts (`2to3-3.11`, `idle3.11`, `pydoc3.11`, `python3.11-config`)
carry `#!/opt/homebrew/...` shebangs. The relocation pass rewrites `venv/bin/*` and `venv/pyvenv.cfg`
only, so those shebangs survive into the candidate and the artifact is not self-contained.

Two corrections were possible. **Rewriting** the shebangs to the artifact-local interpreter matches
the sprint's "rewrite owned scripts/config to the final root" wording, and `rewritePyvenvConfig`
already computes the exact mapping needed (`sourceHome` → `finalHome`). **Excluding** them removes
the files instead.

**Exclusion is the correction, chosen for cross-substrate robustness.** A rewritten shebang is still
an absolute path, and Linux truncates a shebang at 127 bytes (`BINPRM_BUF_SIZE`) where Darwin allows
512. The artifact-local interpreter path is long and depends on the operator's data root, so a
rewrite that fits on the Apple host can silently produce an unexecutable script on `linux-cpu` or
`linux-gpu` — a substrate-dependent failure in a sealed artifact, which is precisely the class this
sprint exists to remove. Rewriting also required making the copied scripts writable inside the
candidate and would have been silently defeated by the skipped-regular-file allowance recorded above.

Excluding costs nothing the artifact can legitimately use. The venv resolves its interpreter through
`pyvenv.cfg`, and interpreter binaries are not scripts, so they are unaffected. Were a host-shebang
script retained and executed, it would exec the *host* interpreter and escape the sealed generation —
the exact escape the residual scan exists to catch — so such a file is not a usable artifact member
under any substrate.

The rule is therefore: within a Python home closure, a regular file whose **shebang binds a host
installation** is not part of the closure. `excludedPythonHomeShebangFile` is applied by the digest
walk and the copy walk alike, so the source and destination closure identities continue to describe
the same payload and `packageClosurePayloadMatches` still holds.

Arriving at that predicate took two wrong rules, and both are worth recording because the distinction
they converge on is the whole point.

A first attempt excluded *every* shebang-carrying file in the Python home. It passed the residual
scan, and the sealed interpreter then started and loaded `python-home/Python` from inside the
artifact — then died with `ModuleNotFoundError: No module named 'quopri'`. Numerous CPython
standard-library modules retain a shebang, so the broad rule was silently deleting stdlib.

A second attempt confined the rule to files directly under `bin/`. That preserved the stdlib, and the
residual scan then caught `lib/python3.11/config-3.11-darwin/python-config.py` — a host-bound script
that does not live in `bin/`. Location is not the distinction.

Inspecting a real Homebrew `python@3.11` shows what is: standard-library modules carry
`#! /usr/bin/env python3`, while `bin/2to3-3.11` *and* `config-3.11-darwin/python-config.py` both
carry
`#!/opt/homebrew/Cellar/python@3.11/3.11.15_3/Frameworks/Python.framework/Versions/3.11/bin/python3.11`.
The dividing line is whether the shebang names an absolute path into a specific installation.
`/usr/bin/env` is the one absolute form that names none: it resolves through `PATH` at exec time and
exists on every substrate. Everything else binds the host.

The predicate is therefore content-derived and location-independent, which is what makes it robust
across substrates: a Linux `#!/usr/bin/python3.11` launcher is excluded for exactly the same reason as
a Homebrew one, with no per-host inventory of console-script names or directories.
`shebangHostBindingTest` in the Apple materializer suite pins all of these — the Homebrew, Linux
system, and `/usr/local` host-bound forms as excluded; the spaced and unspaced `/usr/bin/env` forms,
a file with no shebang, and a Mach-O magic prefix as retained.

#### The Python home was never scanned for its own runtime closure

With the loader audit no longer tripping on commentary, the installed smoke ran to completion and
reported the finding this whole check exists for:

`installed runner loaded an unsealed non-system library: /opt/homebrew/Cellar/xz/…/liblzma.5.dylib,
/opt/homebrew/Cellar/openssl@3/…/libcrypto.3.dylib, /opt/homebrew/Cellar/mpdecimal/…/libmpdec.4.dylib`

The sealed interpreter was loading Homebrew libraries from the **host**. Those three are dependencies
of the CPython standard-library extension modules `_lzma`, `_ssl`, and `_decimal`, which live in the
Python home's `lib-dynload`. `materializeResolvedPythonRuntimeClosure` passed only the candidate venv
as a package closure to scan, so the walk started from the interpreter and covered the venv, and
nothing ever reached `lib-dynload`: those modules are `dlopen`ed by the import machinery rather than
linked by the interpreter, so no dependency edge leads to them. Their Homebrew dependencies were
therefore never discovered and never vendored, and the artifact was silently not self-contained.

The Python home closure is now scanned alongside the candidate venv. This is precisely the class of
defect a cohort exists to find: every machine-independent gate passed throughout, and the artifact
would have been published as sealed while depending on host Homebrew formulae that an operator could
upgrade or remove at any time.

#### The Mach-O universal magic collides with the Java class file magic

Past the platform-binary corrections, the Audiveris closure scan failed with
`fat Mach-O architecture count is invalid`. `0xCAFEBABE` is simultaneously the Mach-O universal
(fat) magic and the Java class file magic, and `supportedMachOMagic` decided candidacy on those four
bytes alone. Audiveris is a JVM application whose bundle is full of `.class` files, so the scan
admitted one as a Mach-O image and the subsequent full parse failed and took the whole
materialization with it.

Candidacy now requires a structurally credible fat header: an architecture count within the same
bound the parser enforces, and a first architecture naming a CPU type Mach-O actually defines. In a
class file those same bytes are the minor and major class-format versions — Java 8 is major 52,
Java 17 is 61 — which are not plausible architecture counts. `machOFatMagicCollisionTest` pins a
genuine arm64 universal header and a thin arm64 header as candidates, and class-file headers at
majors 52, 61, and 65 plus a fat header naming an unknown CPU type as non-candidates.

#### Open design decision: JavaCPP extracts its natives outside the artifact

Audiveris now downloads its pinned DMG, mounts it, copies the bundle, scans its Mach-O closure, and
reaches its installed smoke, which reports:

`installed runner loaded an unsealed non-system library:
/Users/<user>/.javacpp/cache/leptonica-1.85.0-1.5.12-macosx-arm64.jar/org/bytedeco/leptonica/macosx-arm64/libleptonica.6.dylib,
…/libjnileptonica.dylib, …/tesseract-5.5.1-…/libtesseract.5.5.dylib`

This is not a defect in the materializer and not a bound to raise. JavaCPP ships its native libraries
inside jars and extracts them **at run time** into a per-user cache (`~/.javacpp/cache`), then loads
them from there. Audiveris therefore loads Leptonica and Tesseract from the operator's home
directory, outside the sealed generation — exactly what the unsealed-library check exists to detect,
and a real violation of the sealed-artifact contract rather than a false positive.

Three corrections are possible and they are different commitments:

1. **Pre-extract at materialization time** into the artifact and point JavaCPP's cache directory at
   that sealed location, so no runtime extraction occurs on any substrate. This is the only option
   that leaves the artifact genuinely self-contained, and it behaves identically on Apple and Linux.
   It is also the largest change: the natives must be extracted from the jars during hydration and
   the runtime must be configured to use them read-only.
2. **Redirect the cache per run** to a temporary directory. This removes the dependency on the
   operator's home directory but not the runtime extraction, and the loaded libraries would still be
   outside the generation, so the smoke's own contract would have to be weakened to accept them.
3. **Recognise the JavaCPP cache as an owned location.** Cheapest, and the weakest: it admits a
   mutable per-user directory into the trust boundary of a sealed artifact.

Option 1 is the recommendation on the same cross-substrate-robustness grounds that decided the
shebang question, but it changes what the Audiveris artifact *is* and should be chosen explicitly.

#### Attempt 1 state

Attempt 1 is **incomplete and is not closure evidence**. **Six of the seven artifacts now
materialize, smoke, and activate end to end**: `llama-cpp-cli`, `whisper-cpp-cli`, `coreml-native`,
`ctranslate2-native`, `mlx-native`, and `onnx-runtime-native`. Every Python-backed artifact is
included, each hydrating its environment, resolving its complete Mach-O closure, vendoring its
runtime libraries, relocating its candidate venv, passing its residual scan, and running an installed
smoke whose loader provenance proves it loaded from its own sealed generation.

#### The executable snapshot cannot be applied to an operating-system platform binary

The Audiveris `jvm-native` artifact failed deterministically at its first step with
`download pinned Audiveris DMG: kernel failed: runBoundedCommand supervisor: getProcessGroupIDOf:
does not exist (No such process)`.

The cause is a property of the platform, and it invalidates the snapshot mechanism for a whole class
of tools. On Apple Silicon an operating-system platform binary is validated against the kernel trust
cache rather than an embedded code signature. A *copy* of one therefore carries no usable signature
and is killed at exec. Measured directly on this host: `/usr/bin/curl --version` exits 0 and prints
412 bytes, while a byte-identical copy of the same file exits **137** — `SIGKILL` — and prints
nothing. The anchor's executable snapshot copies the target into a private root and execs the copy,
so the target died instantly and the supervisor's subsequent process-group lookup found no process.
The misleading `ESRCH` was a symptom; the target never ran at all.

This affects every configured system tool, not just `curl`: the Apple host manifest names
`/usr/bin/{git,tar,curl,install,id,cut,dirname}`, `/bin/{mkdir,chmod,ln,bash,hostname}`, and
`/usr/sbin/{chown,sysctl}`, and Phase 4 Sprint 4.32's footprint observer is specified over
`/usr/bin/top` and `/usr/bin/footprint`. Every one of them would be killed if snapshotted and
executed as a copy.

A platform binary is therefore executed in place. This is not a weakening of the snapshot's purpose.
The snapshot exists to prevent the executable being swapped between validation and exec; a
SIP-protected path cannot be swapped at all without disabling System Integrity Protection, which is a
stronger guarantee than a private copy. Every exact identity check is retained — canonical path,
device, inode, mode, size, and content digest are all still verified against the recorded expectation
immediately before launch. The exemption is confined to prefixes the operating system itself
protects (`/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`, `/usr/libexec`, `/System`); `/usr/local` and the
Homebrew prefixes are operator-writable and continue to be snapshotted.

The exemption is needed on both sides of the protocol. With only the anchor corrected, the target
started — proving the diagnosis, since the `ESRCH` disappeared — and then failed its own
`validateTargetExecutableSnapshot` with `sealed target executable escaped its anchor snapshot`,
because that check requires the executable to live inside the snapshot root. The target-side check now
admits a platform binary executed in place while still requiring its canonical path to equal the
recorded expectation; the containment requirement is lifted only for OS-protected prefixes, and a
snapshotted executable must still match its configured path *and* lie within the snapshot root. The Core ML artifact now installs its environment, scans its package closure,
seeds its rpath stack, resolves its complete Mach-O closure including delocated-wheel install names,
clears every closure bound, relocates its candidate venv, rewrites its `pyvenv.cfg` to the
artifact-local interpreter, passes its residual scan, and **starts its sealed interpreter, which
loads `python-home/Python` from inside the artifact** — the self-contained Python closure this sprint
requires, demonstrated running for the first time.

The run then stopped for an environmental reason rather than a defect:
`install pinned Apple engine pip: timed out after 600000000 microseconds`. The same host carries the
sustained background CPU load described above, and the pip install had completed inside that deadline
on every previous attempt. **No conclusion about the shebang correction can be drawn from this
attempt**: the narrowed rule reached the interpreter-start stage on the preceding run and has not yet
been observed through a complete Core ML activation. Nothing downstream of materialization — the
`infernix test all` integration lane, the routed Playwright lane, or the paired `linux-cpu` cohort —
has started.

The environment is the current blocker. A host that cannot hold a ten-minute pip deadline, and on
which `infernix-unit` fails nondeterministically in five different places, cannot validate a phase,
and this plan's `Done` rule is a validation rule. The next step for this sprint is a quiet host, not
a further code change.

Explicitly still open for this sprint, beyond the pre-existing architectural residuals:

- **The closure bounds are provisional.** `maximumPoetryClosureBytes` (512 MiB → 12 GiB),
  `maximumExactRuntimeFileBytes` (128 MiB → 2 GiB), `maximumMachOInspectionBytes` (768 MiB → 4 GiB),
  and `maximumMachORuntimeBytes` (256 MiB → 4 GiB) were raised to unblock measurement, not chosen
  from it. Final values must be set from the measured sizes of all seven artifacts and covered by
  positive and overflow tests, as this sprint already requires. Activated artifact sizes measured so
  far: `coreml-native` 1.4 GiB across 35,166 entries, `ctranslate2-native` 265 MiB across 7,378
  entries, `llama-cpp-cli` 19 MiB across 24 entries, `whisper-cpp-cli` 4.8 MiB across 19 entries. The
  Core ML Mach-O inspection totals at least 782 MiB and its vendored runtime closure at least
  471 MiB, the latter now larger since the Python home's `lib-dynload` dependencies are correctly
  included. The
  inspection total is legitimately larger than before the rpath-seeding correction, because every
  scanned closure image is now inspected rather than only the images reachable through dependency
  edges. Both combined bound errors — the per-image image/byte/metadata check and the whole-closure
  library/byte/edge/inspection/metadata check — were split so a breach names which dimension was
  exceeded and by how much; the combined messages could not be acted on without re-running the whole
  materialization, which costs tens of minutes each time.
- **Regression coverage is started, not complete.** `runAppleCohortRegressionAssertions` in the unit
  suite now covers the surfaces that are pure: both dyld scheduling-frame directions, the tightened
  load-record rule (an unrecognised frame, a non-uuid frame, and a relative or non-canonical path
  each fail closed), the three-valued audit classification through
  `installedRunnerApplicationOutputForTest`, the sealed-artifact runtime environment for both the
  native-CLI and Audiveris target shapes, that environment through the rendered-command contract
  including its rejection of an unfixed guard value and an unknown name set, and the supervised
  target's owned-root containment both with and without an authorized artifact install root. The
  scheduling-frame assertion was verified load-bearing by reverting the fix and observing it fail.
  `machOInstallNameAscentTest` in the Apple materializer suite covers the delocated-wheel ascent
  policy in all four directions. Still uncovered, because they are not pure: the
  canonical-vs-configured identity comparison, the hydration-witness relocation selection, the dual
  executable-authority forms, weak/lazy dylib resolution, and closure rpath seeding.
- The Apple materializer suite's `--darwin-production-audiveris-cancellation` mode remains unrun.

### Loader-Closure Producer and Writer-Effect Audit (2026-07-29)

Three residuals recorded above were re-examined against the source. One is now closed, and the
other two were found to be misstated in ways that matter.

#### The Linux ELF/loader closure producer is implemented

The residual was exact: `Infernix.Engines.Artifact.Target` already carried
`NativeArtifactLoaderFileEvidence`, `NativeArtifactLoaderObjectEvidence`,
`NativeArtifactLoaderResolutionEvidence`, and `NativeArtifactLoaderEvidence` with complete JSON
codecs, and `nativeArtifactTargetEvidenceFingerprint` already hashed the loader sub-record — but
`observeNativeArtifactTargetEvidence` hard-coded `targetEvidenceLoader = Nothing`, so the field was
structurally present and never populated. Every comparison over it was `Nothing == Nothing`.

`Infernix.Engines.Artifact.Loader` now produces it. The module owns a descriptor-derived ELF
inspection (`PT_INTERP`, `PT_DYNAMIC`, `DT_NEEDED`, `DT_SONAME`, `DT_RPATH`, `DT_RUNPATH`, with
`DT_STRTAB` mapped from its virtual address back through the `PT_LOAD` segments rather than used as
a file offset), `$ORIGIN`/`$LIB`/`$PLATFORM` expansion with lexical `..` collapse anchored on an
already-canonical observed directory, both `ld.so.cache` layouts including the embedded
new-after-old arrangement modern glibc writes, and a bounded recursive closure walk seeded from the
entry object and from every ELF found by scanning the closed image roots. Each object is opened
`O_NOFOLLOW`, identity-checked before and after, and the bytes parsed are the bytes digested.

Two properties are deliberate. `LD_LIBRARY_PATH` is never consulted: reading it would be an ambient
environment read the configuration doctrine forbids, and a generation identity that depended on it
would not be reproducible. And the producer runs for image targets only — an Apple installed target
keeps `Nothing`, because `validateEngineArtifactRootAt` rejects an Apple manifest carrying image
evidence at all, and an Apple root's runtime closure is vendored into the payload during hydration
and proven at run time by the installed smoke's `DYLD_PRINT_LIBRARIES` audit.

Helper-side revalidation is closed with it. `runClosedLinuxNativeArtifactSmoke` previously
revalidated only the entry executable; it now revalidates the complete recorded closure — every
object and the cache file re-stat'ed and re-digested against its recorded configured and canonical
identity — and **fails closed on a manifest that carries no loader closure**, since an absent
closure means the manifest predates this producer and its generation identity binds none of the
loader, resolution metadata, or system libraries the target will load.

`runElfLoaderClosureAssertions` in `test/unit/Spec.hs` pins the pure surfaces against hand-built
fixtures — a complete synthetic AArch64 `ET_DYN` image, a standalone new-format cache, an
old-format cache, and an embedded new-after-old cache — so the producer is provable without a Linux
host. `cabal test infernix-unit` is GREEN with them.

#### The Linux sealed-run loader observation (closed 2026-07-30)

The dependent gap this producer opened was that nothing proved a sealed Linux run actually loaded
the objects the evidence names. The Apple lane has that proof; the Linux lane had no equivalent, so
its loader evidence was a faithful *derivation* rather than an *observation*.

Closing it exposed a **previously unrecorded High-severity defect**: `classifyExactCaptureTerminal`
applied `validateRetainedArtifactLoaderEvidence` — the **dyld** audit — to *every* exact-capture
smoke, including `SmokeLinuxNativeArtifact`. A Linux smoke emits no `dyld[...]` frames, so its clean
exit was gated on provenance it could never produce. **The Linux native artifact smoke could not
pass on any input.** No machine-independent gate reached it, and the first `linux-cpu` cohort would
have read as a materialization failure rather than as this.

The audit is now selected from the command's own closed provisioning operation —
`InstalledRunnerSmokeOperation` to `DyldSealedRunAudit`, `LinuxNativeArtifactSmokeOperation` to
`ElfSealedRunAudit` — so a smoke cannot be compiled with the wrong one, and no third command reaches
an exact-capture audit at all. The three aggregate checks that make a loader audit meaningful
(something was loaded, at least one object came from the sealed generation, nothing outside the
generation and the operating system was loaded) are now shared by both loaders in
`classifySealedRunLoads`.

`SmokeLinuxNativeArtifact` renders with `LD_DEBUG=libs`, admitted as a fourth closed environment
shape by both `validateSealedArtifactRuntimeEnvironment` and `validateSupervisorTargetEnvironment`,
with `libs` as a fixed guard: `all` would bury the load records and a narrower setting would emit
none. `LD_LIBRARY_PATH` is deliberately absent, for the same reason the loader-closure producer
never reads it.

**The frame grammar is measured, not documented.** Two rounds of the Apple smoke were broken by
assuming a loader frame shape, so glibc 2.39's `LD_DEBUG=libs` output was captured from a native
`linux/arm64` container through the existing colima daemon, and every fixture line in
`runElfSealedRunAuditAssertions` is verbatim from that capture. The measurement decided three things
the documentation would not have:

- **`calling init: <path>` is the only load record.** `trying file=` also names candidates the
  loader *rejected*, so admitting it would launder paths that were never loaded.
- **`initialize program:` and `transferring control:` carry `argv[0]`, not a path** — measured as
  the bare `python3`, so neither can be a load record. This is why the entrypoint itself is proven
  by the artifact's own libraries rather than by its own frame.
- **A load record legitimately carries `..`.** A stock CPython reports
  `/usr/local/bin/../lib/libpython3.12.so.1.0`. Banning `..` would reject a correct record — the
  same mistake the delocated-wheel install-name ban made — so the path is lexically collapsed
  instead, which is also the *safe* operation for the containment test: an ascending path collapses
  to where it actually resolves and is classified as unsealed rather than laundered into the
  artifact root. An ascent past the filesystem root fails closed.

The same capture confirms the audit catches the Apple lane's most consequential finding in its Linux
form: `LD_DEBUG=libs` reports `dlopen`ed extension modules *and their transitive host dependencies*
(`_lzma` pulling `liblzma.so.5`, `_ssl` pulling `libcrypto.so.3`), which is exactly the
`lib-dynload` escape that every machine-independent Apple gate missed.

The rule is otherwise the same inversion the dyld parser settled on: an unrecognised frame is loader
commentary carrying no path, and a frame that *claims* to be a load record while violating the shape
still fails closed.

Still open: this is machine-independent evidence over a measured grammar. The first `linux-cpu`
cohort remains where a resolver-versus-loader disagreement would surface — but it now surfaces as a
named unsealed-library or no-provenance failure rather than silently.

#### The Linux generation-fingerprint residual as recorded is stale

`engineArtifactGenerationFingerprint` already binds the image-owned evidence: its
`("linux-native", Just evidence)` branch hashes payload digest, recipe fingerprint, target contract
fingerprint, and `nativeArtifactTargetEvidenceFingerprint` together, and requires the evidence's own
contract fingerprint to agree with the target contract. The residual sentence in
[README.md](README.md) describing the identity as deriving "from only the metadata-root payload
digest" describes a state the source has already left.

The real residual is one level down, in the lease **consumers**, and it is larger than the recorded
one:

- Every production generation-leased helper sets only `boundedArtifactGenerationLeaseExpectation`
  and leaves `boundedArtifactLeaseExpectation` at its `Nothing` default, so
  `validateSupervisorArtifactGenerationLease` always takes the candidate branch — which requires
  `generationFingerprint == payloadDigest` and hard-codes
  `nativeArtifactTarget identity "apple-silicon" "arm64"`. `validateEngineArtifactHelperLease` is
  therefore unreachable in production, and no Linux generation is validated through it.
- Runtime launch does not consume the lease at all: `validatedArtifactGenerationLease` is stored in
  `ValidatedEngineArtifact` and then bound as `_generationLease`, and `runArtifactLaunchRequest`
  takes no generation read lease. Generation identity does not yet authorize shared execution
  anywhere.
- `ArtifactGenerationLeaseExpectation` carries only engines root, adapter, generation fingerprint,
  and payload digest — no substrate, architecture, recipe, or evidence — so a helper structurally
  cannot re-derive the fingerprint it is handed.

##### The Linux native smoke is unreachable, and the reason is a design contradiction (2026-07-30)

Tracing the first residual to its consequence found that the Linux native artifact smoke cannot
succeed, for three independent reasons. Two are mechanical and one is a design decision that has not
been made.

1. **Wrong audit.** `classifyExactCaptureTerminal` applied the `dyld` audit to every exact-capture
   smoke, so a Linux clean exit was gated on provenance it could never emit. **Closed 2026-07-30**;
   see the sealed-run loader observation section above.
2. **Wrong lane.** `runClosedLinuxNativeArtifactSmoke` sets only
   `boundedArtifactGenerationLeaseExpectation`, so helper-side validation necessarily takes the
   candidate branch, and `validateCandidateArtifactTarget` hard-codes
   `nativeArtifactTarget identity "apple-silicon" "arm64"`. For `llama-cpp-cli` that expects
   `<root>/native/bin/llama-cli` while the command renders `<root>/bin/llama-cli`, so the target is
   rejected as disagreeing with the closed direct-target catalog.
3. **Wrong shape entirely.** `Provisioning.linuxNativeArtifactEntrypoint` is
   `Identity.nativeArtifactEntrypoint`, which returns `bin/llama-cli` — the **retired `bin/*`
   wrapper spelling**. Wrapper retirement landed on the Apple side; this Linux path still renders
   through it. And the actual `linux-native` catalog entry is not artifact-root-relative at all: it
   is an `ImageTarget` naming an absolute
   `/opt/infernix/native-payloads/llama.cpp/llama-b9704/llama-cli` in the immutable image.

Item 3 is the one that matters, because items 1 and 2 are only reachable if the underlying shape is
agreed. `runClosedLinuxNativeArtifactSmoke` is built on "a retained artifact root plus one safe
relative executable" — the Apple installed-artifact shape — while the Linux catalog says a
`linux-native` target is an absolute image path with its own declared closure roots. Those are two
different designs and the code currently contains both. Deciding between them is a design decision
of the same kind as the JavaCPP question, not a mechanical correction:

- **Bind the smoke to the image target.** The Linux lane executes the immutable image payload
  directly, and the artifact root holds only the manifest and the recorded loader closure. This
  matches the existing catalog and the loader-closure producer, which already runs for image targets
  only. The retained-root/relative-executable machinery then does not apply to the Linux lane and
  the smoke must be recompiled around the image target and its `ImageClosureRoot`s.
- **Bind the Linux lane to an installed artifact root**, as Apple does, and change the catalog's
  `linux-native` entries from `ImageTarget` to `InstalledTarget`. This unifies the two lanes but
  contradicts the immutable-image doctrine the Linux substrate is built on, and would require
  hydrating a per-artifact root inside the image.

**The first is chosen** (2026-07-30, explicit operator decision). It is what the catalog and the
loader producer already say, and it leaves the immutable image as the source of the payload. The
Linux artifact root therefore holds the manifest and the recorded loader closure; the smoke executes
the image payload directly, and its `LD_DEBUG` audit is satisfied by the target's declared
`ImageClosureRoot`s rather than by the artifact root.

That choice also settles the sealed-run audit's owned-root question for the Linux lane, which the
Apple lane answers with the artifact root: a Linux sealed run legitimately loads from its declared
image closure roots, so those are the roots its audit admits.

Sub-item 1 of the generation-lease residual follows from the same decision: with the Linux target
shape fixed, `boundedArtifactLeaseExpectation` can be populated for the Linux lane, which is what
makes `validateEngineArtifactHelperLease` reachable in production.

**The decision is recorded; the implementation is not landed.** The enumerated work, in the order it
must be done:

1. `SmokeLinuxNativeArtifact` must carry the architecture. A `linux-native` `ImageTarget` path
   depends on it (`whisper-bin-ubuntu-x64` versus `-arm64`), and the renderer must resolve the same
   catalog entry the helper revalidates against.
2. `renderProvisioningCommand` must render `nativeArtifactTargetExecutable` and
   `nativeArtifactTargetLeadingArguments` from `nativeArtifactTarget identity "linux-native"
   architecture`, replacing `artifactRoot </> linuxNativeArtifactEntrypoint identity`. This also
   retires `Identity.nativeArtifactEntrypoint` and `Identity.nativeArtifactSmokeCommand`, whose only
   remaining consumer is this path — completing the wrapper retirement that landed on the Apple side.
3. `runClosedLinuxNativeArtifactSmoke` must stop asserting an artifact-root-relative executable. The
   retained `ProvisioningMutationWorkingDirectory` keeps the artifact root — it is the generation
   whose manifest and loader closure authorize the run — but its relative executable becomes
   `Nothing`, and the target execs the absolute image path.
4. `runBoundedCommandExactCapture` and `validateCandidateArtifactTarget` both pattern-match on
   `Just relativeExecutable` and must admit the image lane. `validateCandidateArtifactTarget` must
   also stop hard-coding `"apple-silicon" "arm64"`.
5. The sealed-run audit's owned roots for the Linux lane become the target's declared
   `ImageClosureRoot`s rather than the artifact root, so `classifySealedRunLoads` needs the roots
   passed in rather than one artifact root.
6. Only then can `boundedArtifactLeaseExpectation` be populated for the Linux lane, making
   `validateEngineArtifactHelperLease` reachable and closing generation-lease sub-item 1.

An earlier in-flight attempt at steps 1–2 was reverted rather than left partial, because a
half-converted command shape is worse than a recorded decision.

**Steps 1–6 are landed (2026-07-30).** Steps 1–5 went in as one
change for the same reason the earlier attempt was reverted.

- **Step 1** — `SmokeLinuxNativeArtifact` and `LinuxNativeArtifactSmokeOperation` both carry the
  architecture, so the operand-free operation the helper retains names the lane too.
- **Step 2** — the renderer resolves `nativeArtifactTarget identity "linux-native" architecture` and
  renders that target's executable and leading arguments.
  `validateProvisioningCommand` also rejects an architecture the catalog has no entry for, so a
  command that could not render is refused at validation rather than inside the renderer.
  This retires `Identity.nativeArtifactEntrypoint`, `nativeArtifactSmokeArguments`, and
  `nativeArtifactSmokeCommand`, completing the wrapper retirement that landed on the Apple side.
  It also forced a correction the enumeration did not name: the retired `bin/*` wrappers accepted a
  uniform `--smoke` plus a payload-policy flag, and the **direct image binaries do not**, so
  `linuxNativeArtifactSmokeArguments` now renders per-target arguments the real payload understands
  — `--version` for the two CLIs, `-version` for the JVM target, and `--smoke` plus the policy flag
  only for the two Python-runner targets, which are the only ones that reach
  `apple_native_runner.py`. This mirrors the Apple `installedSmokeArguments` shape exactly.
- **Step 3** — the retained `ProvisioningMutationWorkingDirectory` keeps the artifact root and its
  relative executable is `Nothing`.
- **Step 4** — `runBoundedCommandExactCapture` admits either shape, and
  `validateCandidateArtifactTarget` no longer hard-codes `"apple-silicon" "arm64"`. Closing this
  required closing generation-lease **sub-item 3** with it: the helper structurally could not
  re-derive the catalog entry it was validating, so `ArtifactGenerationLeaseExpectation` now carries
  the substrate and architecture the parent resolved the target from. The helper checks the retained
  relative executable against `nativeArtifactTargetIsInstalled`, so an installed target must retain
  one and an image target must retain none — neither shape can pass as the other.
- **Step 5** — `classifySealedRunLoads` takes a list of owned roots, and they are derived uniformly
  through `nativeArtifactTargetImmutableClosureRoots` from the same catalog entry. The Apple lane's
  `InstalledClosureRoot "."` still resolves to the artifact root, and the Linux lane's
  `ImageClosureRoot`s resolve to the image paths, so the audit can never admit a root the target
  contract did not declare.

**Step 6 landed on 2026-07-30, and closing it found that the Linux native smoke still could not
pass on any input.** The wrong-audit correction recorded above was necessary but not sufficient:
two further independent blockers sat behind it, and neither is reachable by any machine-independent
gate. Both are now closed.

##### The candidate identity assertion was Apple-shaped (High)

`validateSupervisorArtifactGenerationLease`'s pre-manifest branch asserted
`generationFingerprint == payloadDigest`, failing otherwise with *"candidate artifact generation
fingerprint is not its complete installed payload digest"*. That equality is not a property of a
generation identity — it is literally the `apple-silicon` branch of
`engineArtifactGenerationFingerprint`, which returns `payloadDigest` verbatim. The `linux-native`
branch returns a SHA-256 over
`["infernix-engine-generation-v1", payloadDigest, recipeFingerprint, targetContractFingerprint,
evidenceFingerprint, ""]`, precisely because a Linux metadata root deliberately does not contain the
image-owned payload it executes, so its identity must bind the recipe, the closed target contract,
and the descriptor-derived image evidence as well. The two values are therefore **never** equal, and
`hashLinuxCompletionState` mints the lease with exactly those two distinct values. Every Linux
generation that could ever exist was refused.

The correction does not weaken the check; it makes it the derivation production itself runs.
`Artifact.rederiveArtifactGenerationFingerprint` rebuilds the identity helper-side from the lane the
expectation already carries, re-deriving the recipe fingerprint and target contract from the closed
catalog and **re-observing the image-target evidence through descriptors**, then requires the result
to equal the fingerprint it was handed. Nothing new crosses the wire: every input was already
derivable from the lane plus the payload digest the helper re-computes from bytes, which is what
makes this the real close of generation-lease **sub-item 3** rather than the Apple-only half of it.
Apple keeps its exact previous meaning as the `Nothing`-evidence case of the same call.

##### The retained-root resolver refused every image candidate (High)

`supervisorArtifactGenerationRoot`'s candidate pattern required the retained relative executable to
be `Just _`. A `linux-native` image candidate retains `Nothing` by construction — that is what
step 3 established — so it fell through to the catch-all and failed with *"artifact generation
helper lacks one exact retained artifact root"* before its root was even resolved. The position now
admits either shape; the shape itself is not left unchecked, because
`validateRetainedArtifactTarget` requires it to agree with `nativeArtifactTargetIsInstalled` for the
closed catalog entry, which is strictly stronger than either constructor alone.

##### Step 6 itself, and a gap it exposed

`runClosedLinuxNativeArtifactSmoke` now takes a `Maybe` manifest fingerprint. The post-activation
smoke supplies `Just` — the pending activation has already renamed the candidate onto the final
path, so the manifest is there — which populates `boundedArtifactLeaseExpectation` and makes
`Artifact.validateEngineArtifactHelperLease` reachable in production for the first time. The
pre-publication candidate smoke supplies `Nothing`, because `publishCandidateManifestFile` runs
after it. The Apple lane deliberately stays on the candidate shape: its identity *is* its payload
digest, so it gains nothing from the installed branch, and moving it would change a path no gate on
this host can exercise.

Closing it exposed one more gap: the installed branch never called the retained-target check at all,
so an activated generation was held to a *weaker* shape rule than a candidate. It now calls it too.
The lane-to-runtime-expectation mapping both branches use is also now a single function, so neither
branch can admit a lane the other refuses.

##### What is proven and what is not

`runArtifactGenerationIdentityAssertions` in `test/unit/Spec.hs` pins the lane-specific property the
defect violated: an `apple-silicon` identity is exactly its payload digest, a `linux-native` identity
never is, and the linux identity moves when the recipe or the observed evidence moves. That is
characterization of the root cause, and it locks the invariant against silent drift — but it is
**not** a discriminating regression against the superseded supervisor source, because the pure
derivation it covers is unchanged. Genuine helper-side coverage of the candidate re-derivation
requires driving a real bounded command against a synthetic `linux-native` generation, which is not
yet written. Until it is, the first `linux-cpu` cohort remains the place these three corrections are
actually proven, and they should be read as "the smoke can now pass" rather than "the smoke passes".

##### Generation-lease sub-item 2 closed, and two High findings behind it (2026-07-30)

Generation-lease **sub-item 2 is closed**: runtime launch consumes the generation lease.
`Capability.reapArtifactRun` — the single transition out of the ready phase and the only place a
launch request is derived — now takes the exact generation's shared read lease itself, from the
lease `mintValidatedEngineArtifact` derived from that generation's own manifest, and holds it across
the launcher's whole execution. There is no mint site for lease-held evidence and no path from a
ready run to a launch request that bypasses the acquisition, so the property is structural rather
than conventional. A refused lease is a `Nothing` that resolves to `ArtifactBusy`, not a wait, so a
stopped materializer still cannot turn request resolution into an unbounded one.

`mintValidatedEngineArtifact` additionally requires the generation's lease sidecar to be a real
regular file. That is the load-bearing half: **a generation no writer ever minted can no longer
execute.** It is sound at that point because the engines-root shared lock is held and lease
retirement runs only under that root's exclusive writer authority, and it keeps the failure
classification identical to every other validation failure — the caller's existing `try` turns it
into an `ArtifactRejected` naming the root.

What this does **not** yet buy is additional exclusion in production. A writer holds the
engines-root exclusive lock for the whole activation, and runtime resolution needs that root's
shared lock, so the two are already mutually exclusive; the generation lease is finer-grained
authority the current topology subsumes. It is recorded that way deliberately rather than claimed as
new mutual exclusion. One residual is also recorded rather than closed: an out-of-band sidecar
removal between minting and acquisition escapes as an `IOException`, the same class as an
out-of-band engines-root replacement during acquisition, which the pre-existing reader already
throws on.

`runtimeGenerationLeaseHeldTest` and `runtimeUnmintedGenerationTest` in
`test/artifact-transaction/Spec.hs` pin both halves, and **both were measured against the
pre-correction source**, not argued: with the acquisition and the sidecar requirement removed they
fail with `the exact generation lease was available exclusively while its artifact was running` and
`runtime resolution admitted a generation whose lease sidecar no writer minted` respectively, while
every other case in the suite passes. Closing them also exposed that `writeExactArtifactRoot` and
`refreshExactManifest` modelled a generation no writer had produced; both now mint the sidecar the
way the activation transaction does.

The sub-item-3 statement recorded above — that `ArtifactGenerationLeaseExpectation` "carries only
engines root, adapter, generation fingerprint, and payload digest — no substrate, architecture" — is
**stale**. That type carries six fields including the substrate and architecture the parent resolved
the target from; step 4 above already closed it.

###### The Linux sealed-run environment contract could not admit its own renderer (High)

Every rendered fixed provisioning process carries `PYTHONDONTWRITEBYTECODE=1`, prepended by
`fixedProvisioningProcessWithEnvironment`. The `SmokeLinuxNativeArtifact` render passes
`LD_DEBUG=libs`, so the rendered extra environment is that pair — but **both** closed contracts named
`LD_DEBUG` alone: `sealedArtifactRuntimeNameSets` carried the singleton `["LD_DEBUG"]`, and
`validateSupervisorTargetEnvironment`'s `linuxSealedRunNames` was `"LD_DEBUG"` plus the supervisor
base names. The sorted name set the renderer produces therefore matched no closed shape, and the
Linux native artifact smoke was refused as
`bounded command generated an unsupported command environment` **on every input**.

This is the fourth instance in this correction of a check that cannot pass on any valid input, and
it sat directly behind the wrong-audit defect recorded above: correcting the audit selection was
necessary but the smoke still could not compile its command. No machine-independent gate reached it,
and the first `linux-cpu` cohort would again have read it as a materialization failure.

The correction removes the drift rather than patching the constant. `provisioningFixedEnvironmentGuard`
names the guard the renderer prepends, `linuxSealedRunAuditEnvironment` names the audit the renderer
passes, and `linuxSealedRunRenderedEnvironment` is their concatenation — which is by construction the
value the renderer produces. Both contracts now derive their Linux name set from it. A regression
assertion in `runSealedArtifactEnvironmentRegressionAssertions` drives that exported value through
`renderedEnvironmentContractForTest` and `supervisorTargetEnvironmentContractForTest`, so it exercises
the shape the renderer emits rather than a restatement of it. It was **measured against the
pre-correction contracts** and fails there with
`the rendered-environment contract admits the Linux sealed-run environment`.

###### The runtime launch never rendered the closed catalog's leading arguments (High)

Wrapper retirement removed the generated per-engine shell shim and rebuilt argument rendering only on
the **smoke** path (`installedSmokeArguments`, `linuxNativeArtifactSmokeArguments`). The runtime
inference launch was left rendering the retired wrapper protocol —
`--model/--engine/--family/--install-root/--require-native-payload/--input-*/--model-cache-*` — and
`nativeArtifactTargetLeadingArguments` had exactly one production consumer, the Linux smoke render.

All seven native artifacts bind as `native-process-runner`, so every one of them reaches
`runNativeWorker → runExecutableNativeArtifact → runArtifactLaunchRequest`. The consequences were
concrete:

- The four installed Python-runner targets (`coreml-native`, `mlx-native`, `ctranslate2-native`,
  `onnx-runtime-native`) execute `venv/bin/infernix-python`, and their runner script plus its
  `--adapter-id`/`--engine-name` pair live only in the leading arguments. Both are
  `required=True` in `python/native-runners/apple_native_runner.py`, so **every inference through a
  Python-runner artifact failed at argument parsing.**
- The Linux `jvm-native` target executes `/opt/infernix/audiveris-jre/bin/java`, whose
  `-cp /opt/audiveris/lib/app/*` and main class live only in the leading arguments.

The correction carries the leading arguments on the capability itself.
`ValidatedEngineArtifact` gains `validatedArtifactLeadingArguments`, resolved by the validator from
the same closed catalog entry it validated the entrypoint against; `ArtifactLaunchRequest` gains
`artifactLaunchLeadingArguments`; and `runArtifactLaunchRequest` renders them before the invocation
arguments. A launcher still holds no capability and cannot construct a target of its own.
`runtimeLeadingArgumentsTest` drives a real `onnx-runtime-native` artifact root through
`withFirstValidatedEngineArtifact` and asserts the exact vector the launch request carries.

**The two raw-CLI adapters remain open, and this is a design decision, not a mechanical fix.**
`llama-cpp-cli` and `whisper-cpp-cli` carry `NoTargetArgumentPrefix` on both substrates, so their
leading arguments are empty and the correction above is a no-op for them: the runtime launch still
hands `llama-cli`/`whisper-cli` the native-runner protocol, which those binaries do not parse. The
retired shell wrapper was the translation layer, and its replacement — Haskell that renders each
payload's real argument vector and parses its real output — exists only for `--version` smokes. The
two options are to give the CLI adapters the installed Python-runner prefix, so
`apple_native_runner.py` translates as it already does for the other four, or to build the
per-engine Haskell argv/parse pair the direct-dispatch doctrine implies. This is the same class of
open decision as the JavaCPP question and is listed with it below.

#### Part of the recorded `infernix-unit` load-sensitivity is a real publish/observe race (2026-07-30)

The frozen-identity gate run below failed `infernix-unit` with
`the cancelled protocol-isolation command published an invalid descendant pid`. The plan's standing
reading of such a failure is host load. **That reading is wrong for this symptom**, and the
elimination is exact: the sibling `never published its descendant` branch did not fire, so the file
existed; the only writer for it is
`"$1" 30 & child_pid=$!; printf '%s\n' "$child_pid" > "$2"; wait "$child_pid"`, which emits a valid
integer. The only remaining explanation is that the observation read the file before the write.

`> "$path"` creates and truncates the file **before** `printf` runs, so a zero-length window is
guaranteed by the shell's own evaluation order rather than produced by scheduling. `waitForFileContents`
returned the first read after `doesFileExist`, so it could return `Just ""` and the caller's parse
failed. Host load widens the window, which is why the symptom looked load-shaped and why it was
recorded that way.

The window is shared by **every** fixture-publication wait in `test/unit/Spec.hs` — roughly thirty
call sites, all of which either parse the contents or compare them to a non-empty literal. Several
already carry an explicit `published empty evidence` assertion immediately afterwards, which is this
same race being reported as a failure rather than waited through.

`waitForFileContents` now treats an empty file as not-yet-published and keeps waiting, so the
deadline becomes the only way for a publication wait to fail. That is what such a wait should mean,
and it removes a whole class of failures from the load-sensitivity bucket.

The correction was then exercised under the condition that produced the failure rather than merely
argued: `infernix-unit` passed **four consecutive times** on the corrected source at sustained load
27.98–31.39, on the same host whose load-28 run had failed. It does **not** retire the
load-sensitivity bucket: the deadline-shaped symptoms recorded above are a separate question, and a
Stage 1 run on a genuinely quiet host is still owed.

#### The writer-effect residual is an undercount

"Roughly fifteen writer effects" undercounts at function granularity and badly undercounts at
effect-site granularity. The audit finds **21 pathname-resolving writer functions across 34 effect
sites** in `Engines/Provisioning.hs`, plus **4 absolute external-tool operands** in
`Cluster/Subprocess.hs`, plus two structural gaps.

The shared defect is `authorizedWriterPath`: it validates ancestry with `openFdAt`, closes every
descriptor it opened, and returns a `FilePath`. Twenty-four call sites then perform an effect on
that result, re-resolving the whole path. `withAuthorizedLeafParent` — which retains the parent
descriptor and hands the action `(parentFd, leaf)` — is the correction vocabulary and already
exists; `provisioningPublishAppleSetupManifestInternal` and `copyAudiverisDmgReceipt` are correct
reference conversions.

A hard platform constraint bounds the conversion, and it is worth recording because it removes the
obvious approach. `unix-2.8.8.0` exposes only `openFdAt` and `createFileAt` from the `*at` family —
there is no public `mkdirat`, `unlinkat`, `renameat`, or `symlinkat` — and `foreign import` is
forbidden throughout repo-owned Haskell. Darwin additionally does not permit traversing
`/dev/fd/<dirfd>/...`. There are therefore exactly two legal descriptor-anchored write mechanisms:
in-process `openFdAt` plus the fd-taking `setFdMode`/`setFdSize`/`fdWrite`/`fdSeek`/
`fileSynchronise`; and the self-exec `ProvisioningFilesystemMutation` kernel, which `fchdir`s into a
retained parent and then operates on a single CWD-relative leaf. Directory creation, unlink,
rename, and symlink creation **must** go through the kernel.

Landed in this correction:

- `writeAuthorizedRegularFile` and `setAuthorizedLeafExecutable`, both `withAuthorizedLeafParent`
  plus `openFdAt` on the retained parent, fsyncing the file and the parent descriptor. `nofollow`
  makes a symlink planted at the leaf a failure rather than a redirect; `trunc` gives
  create-or-replace without a separate unlink that would reopen the same window.
- `provisioningWriteFile`, `provisioningProjectWriteFile`, `provisioningWriteBytes`, and
  `provisioningMakeExecutable` converted onto them. This removes the module's last `writeFile` and
  `ByteString.writeFile` uses and its only `Directory.getPermissions`/`setPermissions` pair, which
  re-resolved the path twice after the probe.
- **All four absolute external-tool operands** converted to safe relative form through a new
  `safeRelativeOperand`, which requires the operand to lie inside the command's working directory
  and refuses one that would ascend. `CreatePythonVenv` now renders the bare leaf `venv`;
  `DownloadAudiverisDmg`, `MountAudiverisDmg`, and `DetachAudiverisDmg` render their operands
  relative to the working directory. The target already enters that directory by `fchdir` on a
  retained, component-validated descriptor, so an absolute operand was re-resolved from `/` and
  defeated the anchoring entirely — the cwd side of this contract was correct and the argv side
  silently was not. `provisioningVenvRoot` had exactly one call site and is deleted with it.

Items 1–10 are **closed** as of 2026-07-29. Item 11 remains open and is now the load-bearing test
obligation for this whole audit.

1. ~~**Durable-record family**~~ — closed. `publishDurableRecordBytes` now takes a typed
   `DurableRecordPublication`, writes its staging sibling through `writeAuthorizedRegularFile`, and
   publishes through the kernel's sibling rename; `reconcileDurableRecordStaging` and
   `provisioningRetireDurableRecord` remove through `removeAuthorizedLeafThroughKernel`; and
   `requireDurableRecordEntry` observes through the retained parent instead of re-resolving the
   pathname. The staging leaf is derived from the record's own validated leaf, so it is provably a
   sibling under the same retained parent rather than a string-appended pathname.
2. ~~**`copyRegularFileStable`**~~ — closed. The destination is created, written, mode-set,
   verified, fsynced, and rolled back entirely through the parent descriptor
   `withAuthorizedLeafParent` retains, and the source is now a typed `StableCopySource`: a source
   inside a writer root is read through that root's retained parent, and a source outside every
   owned root (a host CLI or runtime library, which this module holds no authority over) is bound by
   the exact content digest its caller already resolved. For a read, digest equality is the stronger
   binding — it constrains the bytes copied rather than the directory they were reached through. All
   six call sites pass an authority; the Apple runner library, which previously discarded its copy
   evidence entirely, now digests its source first and requires the copy to reproduce it.
3. ~~**Recursive closure copy**~~ — closed. A `PackageClosureCopyContext` plus a destination
   descriptor and relative-component list are threaded down the recursion; child directories are
   created through the kernel and then reopened on the retained parent, links are created through
   the new kernel symlink primitive, and each regular file uses
   `copyRegularFileStableIntoRetainedParent`, which consumes the descriptor the walk already holds
   rather than re-walking the ancestry for every one of tens of thousands of entries.
4. ~~**Fixed owned directory/link**~~ — closed. `createFixedOwnedDirectory` is **deleted**;
   `createFixedOwnedDirectoryTree` keeps the candidate-root containment check that was its only
   distinct contribution and delegates creation to `ensureAuthorizedDirectoryTree`.
   `createFixedOwnedLink` now goes through the kernel symlink primitive.
5. ~~**`publishCandidateManifestFile`**~~ — closed. It takes an `AuthorizedWriterRoot`, threaded
   from `completeLinuxCandidate`/`completeAppleCandidate` through both publish transitions, and
   publishes through `writeAuthorizedRegularFile` with a kernel-anchored rollback.
6. ~~**`relocateCandidateVenvExact`**~~ — closed. The candidate root is reached through
   `withRetainedAuthorizedDirectory`, so the traversal no longer has a swappable root above an
   otherwise descriptor-anchored interior. `rewritePyvenvConfigExact` also dropped a redundant
   pathname stat that re-resolved the ancestry its retained venv descriptor exists to pin.
7. ~~**`synchroniseProvisioningDirectory`**~~ — closed. The pathname form is **deleted** and
   replaced by `synchroniseProvisioningDescriptor :: Fd -> IO ()`. It worked exactly as the forcing
   function this audit predicted: each of the thirteen sites failed to compile until its caller held
   the descriptor it had mutated through.
8. ~~**Kernel symlink primitive**~~ — closed. `ProvisioningCreateSymbolicLinkLeaf` plus
   `safeProvisioningMutationLinkTarget`, which holds the target to the same containment rule
   `validRelativeClosureLink` applies, stated against the kernel's component vocabulary. The
   executor `fchdir`s into the retained parent, creates the link, reads it back, requires the exact
   recorded target, and only then fsyncs the parent. That read-back is the only installed-link
   confirmation available and is therefore the one relied on: a symbolic link cannot be opened
   `O_NOFOLLOW` in process, so any parent-side re-read would re-resolve the destination pathname.
   `ProvisioningReplaceSiblingRegularFile` was added alongside it, because the create-only rename
   precondition is wrong for a durable-record *replacement* — splitting that into unlink-then-rename
   would open the crash window the atomic replace exists to close.
9. ~~**External-tool operands**~~ — closed 2026-07-29; see the landed list above. Every rendered
   provisioning command now passes only relative operands under its descriptor-derived working
   directory. What remains here is coverage: no test yet asserts that `safeRelativeOperand` refuses
   an operand outside the working directory, and the deterministic external-tool parent-swap test
   this sprint requires is still item 11.
10. ~~**Activation transaction**~~ — closed 2026-07-29 via the closed first-order root-mutation
    language. The residual was a module-graph constraint rather than remaining effort: the mutation
    kernel lives in `Infernix.Cluster.Subprocess`, which already imports the public
    `Infernix.Engines.Artifact` and `Infernix.Engines.MaterializationLock` facades, so
    `Artifact/Internal.hs` importing it would close a cycle. Extracting the kernel into a module
    below both is the honest placement but entangles with the self-exec anchor machinery, so the
    language was chosen instead.

    `ArtifactRootMutation` has exactly two constructors — `RenameArtifactRootSibling` and
    `RemoveArtifactRootSibling` — and `ArtifactRootMutator w` is exported from `.Internal` only,
    never from the public facade, so only package-internal engine code can mint an interpreter and
    the transaction can express only those two effects. This is not the caller-supplied `IO` hook
    review #5 rejected. The interpreter is retained *on the activation token* rather than supplied
    again at commit or rollback, so handing a rollback a different interpreter than the forward
    transaction used is not representable. `provisioningArtifactRootMutator` is the single
    production interpreter; it revalidates both operands against the writer root beside the effect,
    requires a rename's two paths to share a parent, and re-derives the kernel components from the
    authorized path rather than trusting the caller's.

    The conversion removed more than the seven renames. `createDirectoryIfMissing True parent` — a
    pathname write *above* the very directory the authority exists to pin — is replaced by
    `requireAuthorityParent`, which proves the install root's parent is exactly the engines root the
    authority recorded with its exact device, inode, and mode. Every pathname
    `synchroniseDirectory` is gone (the interpreter fsyncs the retained parent), and
    `synchroniseDirectory`/`synchroniseOpenedPath` are deleted.

    The largest finding came last and was not in the original enumeration:
    `removeOwnedRootIfPresent` emptied its tree with a local walk that removed **each entry** with
    `removeDirectory (parentPath </> entryName)`, resolving the whole prefix once per entry. Routing
    those individually through the kernel would cost one subprocess per directory entry, which is
    not viable for a 35,000-entry artifact. The whole tree is now one
    `provisioningRemoveTreeLeaf`, which the kernel already performs as a bounded recursive
    descriptor-anchored removal in a single call — cheaper *and* strictly better anchored. The dead
    walk (`removeArtifactDirectoryContents`, `removeArtifactEntry`,
    `removeOpenedArtifactDirectory`, `removeOpenedArtifactFile`, `requireStableDeletionParent`,
    `requireEntryDetachedFromParent`, `sameFileObjectStatus`) is deleted, and with it the module's
    last `System.Posix.Directory.removeDirectory` and `System.Posix.Files.removeLink` uses.

    `Artifact/Internal.hs` now has **no pathname write on any production path**. The only
    `renameDirectory`/`removeDirectoryRecursive` left are inside `artifactRootMutatorForTest`, the
    interpreter the machine-independent `infernix-artifact-transaction` suite uses. That suite
    proves the transaction's *ordering* against synthetic roots in a temporary directory and
    deliberately requires neither a host manifest nor the self-exec kernel, so it stays
    machine-independent; its interpreter performs the two effects by pathname, which is exactly what
    the transaction did before its effects were separated from their interpretation, so **the
    suite's 44 cases cover exactly what they covered before**. The production interpreter's
    descriptor anchoring is therefore *not* proven by that suite — it is item 11's job.
11. ~~**Deterministic parent-swap tests**~~ — closed 2026-07-30.
    `runWriterEffectParentSwapAssertions` in `test/unit/Spec.hs` covers both boundaries and, for the
    first time, the production root-mutation interpreter.

    The direct boundary needed a seam, because the adversarial window is between the ancestry check
    and the leaf effect and nothing else can observe it.
    `writeAuthorizedRegularFileWithParentSwapPause` signals after
    `withAuthorizedLeafParent` has retained the destination parent and before the leaf is opened on
    it, exposed as `provisioningWriteBytesWithParentSwapPauseForTest`. It observes the same bound as
    `pauseProvisioningSessionForTest`: it can only signal and await already-created synchronization
    cells and grants no raw IO, filesystem, process, or writer authority. The fixture writes through
    that seam, renames the validated parent away, plants a fresh real directory at the same pathname,
    resumes, and requires the bytes to be in the detached original with the substitute untouched.

    The fixture carries a **pathname control** that runs the identical swap sequence against a plain
    `ByteString.writeFile` and requires the bytes to land in the substitute. That is what makes the
    descriptor assertion load-bearing: without it, "the substitute is empty" is satisfied by a write
    that never happened. It also runs every time, which is stronger than a one-off revert.

    The **production root-mutation interpreter** now has direct coverage through
    `provisioningInterpretArtifactRootMutationForTest`, which interprets exactly one
    `ArtifactRootMutation` under a real `EngineWriter`. The interpreter value never escapes the
    session and the authority still comes only from `withEngineProvisioningSession`. Covered: an
    authorized sibling rename, an authorized retirement, a non-sibling rename refused, an operand
    outside the writer root refused, and an intermediate parent swapped for a symbolic link out of
    the root refused with its target untouched.

    The external boundary is covered without a seam, because the mutation kernel's own process
    boundary supplies the window: `observeProvisioningMutationRoot` pins the exact device, inode, and
    mode, and the pathname is swapped before the isolated target opens it. The kernel refuses, and
    neither the substitute nor the detached original gains the leaf. A symlinked intermediate
    component is refused the same way. `safeRelativeOperandForTest` closes the coverage gap item 9
    left: a safe descendant is accepted, and an operand outside the working directory, one naming an
    ancestor, one naming the directory itself, an already-relative operand, and a relative working
    directory are all refused.

    Two findings came out of pinning *why* each refusal happens rather than accepting any failure.
    A symlinked intermediate parent at the direct boundary is refused by `openFdAt` on the retained
    parent with `nofollow`, which answers `ENOTDIR` on Darwin and `ELOOP` on Linux — so the assertion
    pins the mechanism and the component, not the errno text. And a symlinked intermediate parent at
    the kernel boundary is **not** caught by the writer-root containment check:
    `authorizedWriterRelativeComponents` validates containment lexically, so `linked/generation` is
    inside the root by string and passes. The escape is refused one layer down, by the isolated
    target's own `nofollow` component walk. Defence in depth holds and the descriptor-anchored kernel
    is the layer that holds it, which is what this audit item is about — but the outer check alone
    does not, and the assertion says so.

    Every negative assertion quotes the refusal it observed into its own failure message, for the
    same reason the malformed-dyld-frame error quotes its frame.

    Not covered, deliberately: a substitute that is itself a real directory *inside* the pinned root.
    Mutating there is inside the writer's authority; concurrent writers are excluded by the exclusive
    materialization lock, not by this boundary.

`ProvisioningCommand` also declares every operand as a bare `FilePath`, so nothing at the type level
distinguishes a working-directory anchor from a safe relative operand.

#### Writer-effect closure state (2026-07-29)

A repeat audit of `Engines/Provisioning.hs` and `Engines/Artifact/Internal.hs` after items 1–10 finds
**no remaining pathname-resolving write effect on any production path** in either module. In
`Artifact/Internal.hs` the only `renameDirectory` / `removeDirectoryRecursive` left are inside
`artifactRootMutatorForTest`, the deliberately machine-independent test interpreter documented under
item 10. In `Engines/Provisioning.hs`, every surviving raw `openFd` in the module is `ReadOnly`, and
`Directory.createDirectory`, `Directory.removeFile`, `Directory.renameFile`, `writeFile`,
`ByteString.writeFile`, `Directory.setPermissions`, and `Posix.createSymbolicLink` no longer appear
in it at all. The two remaining pathname uses are deliberate and are not writer effects: the
explicitly named adversarial hook `executableMutationDuringHashRejectedForTest`, whose whole purpose
is to plant a swap by pathname, and read-only validation status probes.
`validateHydratedCandidate` also stopped asking `Directory.getPermissions` for a mode it already
held in the status it had just observed, which removed one redundant re-resolution that could have
answered about a different file.

The complete machine-independent gate set is **GREEN** for this correction, run serially against
pre-evidence tracked-plus-untracked worktree digest
`sha256:b23b282ce15b1741130cef08f15ac69745512c290633878c521704772010acd0` with installed Apple binary
`sha256:823675470cfaae700bca4fcd32e3e0ae01034828a9f80bc870af2552c017a7e3`. (Writer items 1–9 first
went green at worktree `sha256:a59cedcb…` / binary `sha256:ef3a800b…`; item 10 landed on top of
that.)

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN |
| `cabal test infernix-compile-fail` | GREEN — 6 positive, 78 negative |
| `cabal test infernix-artifact-transaction` | GREEN — 44 cases |
| `cabal test infernix-apple-materializer` | GREEN — 12 cases |
| `cabal test infernix-capped-engine-observer` | GREEN standalone — see the load note below |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `cabal test infernix-unit` | GREEN |
| `cabal test infernix-haskell-style` | GREEN — `ormolu`, `hlint`, readability, Cabal manifest |
| `poetry --directory python run check-code` | GREEN — 8 source files |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

The web gates carry forward unchanged: this correction touched only Haskell sources and this plan.

**The load-sensitivity rule was exercised, not assumed.** This host carries the same sustained ~68%
`/usr/libexec/audiomxd` background load recorded above, and
`infernix-capped-engine-observer` failed during the serial run with
`closed observer fixture did not publish a process birth identity before its deadline` — the exact
message the load note below already records for that suite. It was diagnosed rather than merely
re-run: the message names a *budget* rather than a source location, and the observer is the
`/usr/bin/top` plus `/usr/bin/footprint` kernel, which no writer-effect conversion touches. It then
passed standalone on unchanged source. `infernix-unit` and `infernix-apple-materializer`, the other
two lifecycle-driving suites, both passed even under that load.

This remains machine-independent evidence only. It is not Sprint 1.20 closure: item 11, the
JavaCPP pre-extraction, final closure bounds, the generation-lease consumer residual, the absent
Linux sealed-run loader observation, a fresh final adversarial review, an exact-source Stage 1 run
serially on a genuinely quiet host, and both cohorts all remain open.

#### Closure-bound measurements

Six of the seven artifacts are materialized on the Apple host and were measured directly, which
supersedes the partial figures recorded above. `mlx-native` and `onnx-runtime-native` were listed as
unmeasured and are not.

| artifact | tree bytes | entries | Mach-O bytes | largest single file |
|----------|-----------|---------|--------------|---------------------|
| `coreml-native` | 1.345 GiB | 35,166 | 811.9 MiB | 322.3 MiB (`torch/lib/libtorch_cpu.dylib`) |
| `mlx-native` | 362.5 MiB | 9,469 | 73.0 MiB | 154.9 MiB (`mlx.metallib`) |
| `ctranslate2-native` | 250.0 MiB | 7,378 | 160.4 MiB | 36.1 MiB |
| `onnx-runtime-native` | 241.8 MiB | 7,499 | 135.4 MiB | 36.1 MiB |
| `llama-cpp-cli` | 18.7 MiB | 24 | 18.7 MiB | 4.6 MiB |
| `whisper-cpp-cli` | 4.7 MiB | 19 | 4.7 MiB | 0.8 MiB |
| `jvm-native` | not materialized | — | — | — |

`maximumExactRuntimeFileBytes` cannot be chosen independently: `provisioningCopyFileStableBounded`
refuses any bound greater than `maximumStableCopyBytes`, which is also 2 GiB, so the two must move
together. Final values still require `jvm-native`, whose size will change once the JavaCPP natives
are pre-extracted into the artifact (below), so the bounds remain provisional for one more
materialization rather than for lack of measurement.

**The bound-reachability obligation is closed** (2026-07-30). All four bounds plus
`maximumStableCopyBytes` are now reachable through `provisioningClosureBoundForTest` over a closed
`ProvisioningClosureBound`, and `runClosureBoundAssertions` in `test/unit/Spec.hs` covers each one
positively at its exact total and on overflow at one unit more.

The coverage is over the folds production actually runs, not a parallel restatement of them. Two
extractions made that possible:

- `admitPackageClosureFile` / `admitPackageClosureTotals` replace the inline `unless` guards in
  `digestPackageClosureFile` and `digestPackageClosureLink`. Both call sites now consume the fold's
  returned totals, so a bound the test admits is the bound the digest walk admits. The refusal also
  names the dimension and the observed value, which the previous single
  `"Poetry package closure exceeds its fixed size bound"` did not — and which the enclosing audit
  already recorded as necessary, since a breach that does not say what was exceeded cannot be acted
  on without re-running a materialization.
- `admitMachOClosureDimensions` over a `MachOClosureDimensions` record replaces the five-dimension
  `mapM_` in `validateMachOClosureState`. The first exceeded dimension is reported, which is what the
  `mapM_`-with-`ioError` form did.

The positive cases are the measured artifacts rather than round numbers: the largest closure entry
(`torch/lib/libtorch_cpu.dylib` at 322.3 MiB), the `coreml-native` entry count (35,166), and its
Mach-O inspection total (811.9 MiB) are each admitted. The `maximumExactRuntimeFileBytes` ==
`maximumStableCopyBytes` equality is pinned, because `provisioningCopyFileStableBounded` refuses any
bound greater than the latter, so the two cannot be chosen independently.

Each bound now carries the measurement it is chosen against in a comment at its definition.

**The final numeric values still require one more materialization.** `jvm-native` is unmeasured, and
its size changes once the JavaCPP natives are pre-extracted into the artifact, so the values stay as
recorded until that measurement exists. What has changed is that they can no longer drift silently:
the assertions pin the exact current values, so any change to one is a deliberate, visible edit.

#### JavaCPP: pre-extraction is the chosen correction

Of the three options recorded above, **option 1 is chosen**: the natives are extracted from the
bundled jars at materialization time into the sealed generation, and JavaCPP's cache is pointed at
that location, so no runtime extraction occurs on any substrate. This keeps the artifact genuinely
self-contained and behaves identically on Apple and Linux, on the same cross-substrate-robustness
grounds that decided the shebang question. It is not yet implemented.

#### Machine-independent gate state after this correction

Every machine-independent gate is GREEN. The tree digest below is the SHA-256 of the sorted
per-file SHA-256 lines over all tracked plus non-ignored untracked files, excluding `.build/` and
`dist-newstyle/`. The loader-producer and leaf-write gate set ran against
`sha256:6d62ad395288205fd94a2eaccc0aca87f31e7efbd58fb9d1b58442bc4581e467`; the external-tool operand
conversion then re-passed `infernix-unit`, `infernix-apple-materializer`, and
`infernix-haskell-style` against
`sha256:2dffbc04ebc7a62f818bbc3a9834616ef5c65c8e624626316f5366cabeafa5ed`, which is the current
identity. The gates not re-run for the operand change are unaffected by it — it touches only
rendered provisioning argv — but that is an argument, not a measurement, and a real Stage 1 must run
the complete set serially over the single frozen identity:

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN |
| `cabal test infernix-compile-fail` | GREEN — 6 positive, 78 negative |
| `cabal test infernix-artifact-transaction` | GREEN — 44 cases |
| `cabal test infernix-apple-materializer` | GREEN |
| `cabal test infernix-capped-engine-observer` | GREEN |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `cabal test infernix-unit` | GREEN — includes `runElfLoaderClosureAssertions` |
| `cabal test infernix-haskell-style` | GREEN — `ormolu --mode check`, `hlint`, readability, Cabal manifest |
| `poetry --directory python run check-code` | GREEN |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

This is machine-independent evidence only, and it is **not** a Stage 1 result: the three suites that
drive a full process lifecycle were run serially on an idle host after the loaded loop below, so the
set was not produced by one uninterrupted serial run over one frozen identity. It also does not
close this sprint — the enumerated writer items, the JavaCPP pre-extraction, final closure bounds, a
fresh adversarial review, and both cohorts remain open.

#### Suite load-sensitivity extends beyond `infernix-unit`

Three suites were observed failing on unchanged source while other work ran concurrently, and all
three failures are missed deadlines rather than wrong results:

- `infernix-capped-engine-observer` —
  `closed observer fixture did not publish a process birth identity before its deadline`, failing
  during a concurrent `cabal build` and passing standalone moments later on the same source. In a
  later run it passed *while* the rest of the suite loop was executing, so the threshold is not
  sharp.
- `infernix-apple-materializer` —
  `engine directory creation failed: timed out after 120000000 microseconds`. That budget is
  `provisioningFilesystemMutationTimeout` on the self-exec mutation kernel, reached through
  `provisioningCreateDirectory` → `ensureAuthorizedDirectoryTree`. A two-minute budget for one
  `mkdir` was exhausted while a `cabal test` loop and a Poetry gate ran concurrently.
- `infernix-unit` —
  `a supervisor parent-control failure remains out-of-band kernel provenance; observed
  CommandTimedOut (Timeout {timeoutMicros = 1000000})`, a one-second bound. It failed a second time,
  on a different tree, immediately after a `cabal build all` completed while the host was still
  settling, and passed on the quiet host with no source change. The failure text was filtered away by
  the harness grep on that run, which is its own lesson: a filter that captures only `PASS`/`FAIL`
  discards exactly the line that distinguishes load from defect.

The load-sensitivity recorded above is therefore not confined to `infernix-unit`; it is a property
of every suite that drives a full anchor/supervisor/pin/target lifecycle. **No gate result taken
while another build, test loop, or language gate is running may be recorded as evidence**, and the
Stage 1 gate must be run serially on an otherwise idle host.

The same loaded run also produced one genuine, deterministic failure that had nothing to do with
load: `infernix-haskell-style` rejected an `hlint` hint in the new loader module. Distinguishing the
two costs nothing when the failure text is read — a hint names a source location, a missed deadline
names a budget — and that distinction is why a red suite must be diagnosed rather than re-run.

#### Machine-independent gate state after the item-11, closure-bound, and ELF-audit corrections (2026-07-30)

Run serially, with no editing during the run, against pre-evidence tracked-plus-untracked worktree
digest `sha256:570ed8fabb8d356acffc32966f76a64ce76b97985c87afeecea04c4992a7d79d` and installed Apple
binary `sha256:5ca4cb99251f84b623ca4a4bb6b9c0b7c747444309fa4ba48d37423c44b46b49`.

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN |
| `cabal test infernix-compile-fail` | GREEN — 6 positive, 78 negative |
| `cabal test infernix-artifact-transaction` | GREEN — 44 cases |
| `cabal test infernix-apple-materializer` | GREEN — 12 cases |
| `cabal test infernix-capped-engine-observer` | GREEN |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `cabal test infernix-unit` | GREEN — includes `runWriterEffectParentSwapAssertions`, `runClosureBoundAssertions`, `runElfSealedRunAuditAssertions` |
| `cabal test infernix-haskell-style` | GREEN — `ormolu --mode check`, `hlint`, readability, Cabal manifest |
| `poetry --directory python run check-code` | GREEN — 8 source files |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

The web gates carry forward unchanged: this correction touched only Haskell sources and this plan.

**This is not a Stage 1 result, for a recorded reason.** The host carried the same sustained ~70%
`/usr/libexec/audiomxd` background load throughout, at load average 2.5+. The rule this plan already
states — that the Stage 1 gate must run serially on an otherwise idle host, and that no result taken
under concurrent load is evidence — is not satisfied by this machine in its current state. The
result is recorded as machine-independent evidence only.

An earlier attempt at this same gate set reported four red suites and was **discarded rather than
diagnosed**: source was being edited while it ran, so all four failures were the same missing symbol
from a half-applied refactor. That is the failure mode the no-concurrent-work rule exists to
prevent, observed from the other side — the rule applies to the operator's own edits, not only to
competing builds.

#### The machine-independent gate set was Apple-specific (2026-07-30)

Every recorded gate result above was produced on the Apple host. Running the same set on the CUDA
Linux amd64 development host for the first time found that **`cabal build all` did not compile
there at all**, so no suite in the set had ever executed on a second machine. "Machine-independent"
described the *intent* of the set, not a property any result had demonstrated. Three defects sat
behind that, each invisible to an Apple-only loop:

1. **The tree did not build.** `Runtime/CappedEngine/DarwinObserver.hs` answers unavailable from the
   non-Darwin branch of its three public entry points, which leaves the whole `/usr/bin/top` plus
   `/usr/bin/footprint` helper chain — thirteen top-level bindings and one import — unreachable, and
   `-Wunused-top-binds`/`-Wunused-imports` under `-Werror` reject the module. `CappedEngine/Internal.hs`
   and `test/capped-engine-observer/Spec.hs` then failed the same way on their now-unused
   `DarwinObserver` imports, and `test/unit/ProcessIdentitySpec.hs` used `isNothing` in unconditional
   code while importing it only in its Darwin branch. Each is corrected with the CPP idiom
   `ProcessIdentity/Internal.hs` already uses: the branch that uses a binding owns its import.

2. **The observer's "hang" fixture was not a hang.** `blockForever` was `newEmptyMVar >>= takeMVar`.
   Nothing else can reference that `MVar`, so the RTS deadlock detector delivers
   `BlockedIndefinitelyOnMVar` at the first idle GC and the fixture exits 1 — measured directly here,
   and read by `testTimedOutFixture` as *completed* rather than the timeout it exists to produce. It
   is not a Linux-only defect; it is timing luck that it ever passed, and `ObserverStoppedGroupCleanup`
   passes only because `SIGSTOP` lands before the detector can. Wrapping the same wait in `timeout`
   removes it: the pending timer is another way for the thread to become runnable, so the wait is not
   indefinite. That is also the bounded shape the readiness kernel requires — the first correction
   used `threadDelay` and was correctly rejected by `threadDelayViolations`.

3. **`writeJsonFrameFd` cannot write a regular file on Linux.** It waits on the IO manager through
   `writeFdFully`, and `epoll_ctl` answers `EPERM` for a regular file, so
   `publishSynchronousDescendantIdentity` failed before writing a byte and the synchronous-exception
   tree never published its identities. Darwin's kqueue accepts a regular-file registration, which is
   exactly why this could not surface there. The read side of this module already draws the
   distinction — `readRegularFdChunk` versus `readFdChunk`, with a comment recording the Darwin
   reason — and the write side had the same split (`writeFdFullyBlocking` versus `writeFdFully`) but
   the regular-file publication picked the pipe writer. A `writeRegularJsonFrameFd` counterpart closes
   it.

**`infernix-unit` was also not hermetic.** Its subprocess fixture built its host config from
`defaultAppleHostNativeHostConfig` and kept the Homebrew and macOS system tool paths, while command
compilation refuses a configured tool that is not an executable file. Assertions about which tools a
semantic command validates were therefore asserting about whatever the host happened to have
installed. `hermeticHostToolPaths` now redirects every configured tool onto a stub the suite creates,
leaving the deliberately empty ones empty, because "configured but unavailable" is a distinct state
other assertions rely on.

#### Linux machine-independent gate state (2026-07-30)

Run serially by one script over one frozen worktree identity, with the tree digest recomputed
afterwards and proven unchanged: pre- and post-evidence tracked-plus-untracked digest
`sha256:e8e3ed08ee37754b2a8b394ec76262a4aefc26d7ace80d28b4104c709112c367`, on native Ubuntu amd64
(GHC 9.12.4, cabal 3.14.2.0).

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN — first Linux build of this correction |
| `cabal test infernix-compile-fail` | GREEN — 6 positive, 78 negative |
| `cabal test infernix-artifact-transaction` | GREEN — 44 cases |
| `cabal test infernix-apple-materializer` | GREEN — 12 cases |
| `cabal test infernix-capped-engine-observer` | GREEN |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `cabal test infernix-unit` | RED under host load — see the residual below |
| `cabal test infernix-haskell-style` | GREEN — `ormolu --mode check`, `hlint`, readability, Cabal manifest |
| `poetry --directory python run check-code` | GREEN — 8 source files |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

The web unit suite was not re-run and is not claimed: this correction touched only Haskell sources,
their tests, and this plan.

**This is not a Stage 1 result**, for the reason this plan already requires to be stated: the host was
not idle. `jitml` at ~255% CPU, a `qemu-system-x86` guest, a Patroni cluster, and a live Kubernetes
control plane held the load average between 5 and 8 throughout.

#### Two Linux process-group lifecycle races (2026-07-30)

`infernix-unit` is green standalone on this host and fails under load, and unlike the Apple
load-sensitivity already recorded, **these two failures are not missed deadlines**. Both name a
safety refusal, and both were reproduced: three consecutive runs at load 5.14, 7.14, and 8.22 gave
PASS, PASS, and FAIL.

- `bounded-command refused to signal an unstable process-group identity`
  (`Cluster/Subprocess.hs:8899`)
- `cannot recover bounded-command command process group <pid>: live group has no exact recorded leader`
  (`Cluster/Subprocess.hs:6600`)

They are the same shape. Each site proves a group is live — by `signalProcessGroup nullSignal` or by
`getProcessGroupIDOf` — and then reads the leader's birth identity, treating an absent read as a
violation. But an absent read after a live-group probe is the ordinary outcome when the leader has
just exited while a non-leader member is still briefly alive, which is exactly what load makes
frequent. A leader birth identity that comes back *different* is the real danger the refusal exists
for, and it is correctly distinguished; a leader that is simply *gone* is conflated with it. The
adjacent branches already model the correct handling — `requireActivityGroupAbsentAfterLeaderLookupFailure`
proves group absence and returns rather than failing — so the missing case has a reference answer.

#### The leader-absence conflation is corrected (2026-07-30)

The adversarial sweep this correction required found that the two recorded sites are two instances
of one pattern with **eight** sites, and that the obvious fix would have relocated the flake rather
than closed it. The bounded absence prover both races delegate to,
`awaitUnregisteredKernelIdentityAbsent`, classified a probe into exactly two buckets — ESRCH is
absence, everything else is fatal — so routing an absent leader into it converts a refusal on one
errno into a refusal on another. The EPERM arm is therefore the **first** correction and the one the
rest depend on; it is also the Linux counterpart of the `EPERM`-from-`signalProcessGroup` follow-up
recorded above, so the two are corrected together as this plan required.

The invariant the whole family now holds is: **an absent exact leader is never converted into
absence evidence, and no signal is ever delivered on a path where the leader can no longer vouch for
the group id.** An absent leader instead discharges its obligation through the bounded proof, where
only ESRCH succeeds and a persistent EPERM or a persistently live group still fails closed at the
deadline. A leader observed as a *different* process — the recycled pid the refusal exists for —
still hard-refuses at every site, and in the delegating cases is re-checked a second time against a
fresher observation inside the helper.

The corrected sites, in the order they must land:

1. `awaitUnregisteredKernelIdentityAbsent` — EPERM consumes a poll attempt instead of aborting the
   proof. Darwin reports it while a just-exited group still holds unreaped kernel state; Linux
   reports it while one surviving member belongs to a uid we may not signal. Neither is absence.
2. `signalActivityProcessGroupWith` — both absent-leader branches (the entry read and the
   post-`getProcessGroupIDOf` re-read) route to
   `requireActivityGroupAbsentAfterLeaderLookupFailure`. The `unless` that conflated "absent" with
   "moved group" is split into an explicit case, so the two refusals are now distinguishable.
3. `observeRecoverableProcessGroup` — both absent-leader branches classify
   `RecoverableProcessGroupActive`, matching the precedent `classifyObservedActivityProcessGroup`
   already documents. `Active` is the conservative verdict: it forces the owner-death check, the
   signal sweep, and the bounded group-absence proof rather than retiring the lease.
4. `signalProvisionalProcessWith` — the same conflation existed in the provisional twin, and its
   `getProcessGroupIDOf` was unguarded, so an ESRCH there escaped as an unattributed `IOException`.
   The new `requireProvisionalAbsent` mirrors the activity helper and closes a latent bare-PGID
   assumption: the group half of the proof runs only when the recorded pid was its own group leader.
5. `requireActivityOwnerDead` and `activityExactOwnerIsLive` — EPERM classifies as the existing
   unverifiable-owner refusal rather than escaping as a bare errno. It is deliberately **not**
   discharged as owner death: on Darwin `readProcessBirthIdentity` is registry-backed, so a live but
   unregistered process reads as `Nothing`, and only this probe distinguishes it from a dead owner.
6. `cleanupSupervisorTargetResult` — EPERM from the group kill is discharged only once the
   designated reap and the exact group-absence proof have both succeeded, and the fallback signals
   go through `deferSignalFailureUntilAbsence`, which discharges only ESRCH and EPERM and leaves
   every `userError` identity refusal fatal.

The Darwin registry semantics were raised against this correction and are answered rather than
waived. Because `Nothing` there means "not in our registry" rather than "pid unallocated", a live
unrelated process occupying a recycled leader pid also reads `Nothing`. That case does not become
signallable: it reaches the bounded proof, whose group probe keeps observing a live group, and the
poll times out into `bounded-command cleanup could not prove absent`. The behaviour is fail-closed
in exactly the case the old code refused outright — the difference is a bounded grace window, not a
weakened refusal.

**Coverage was zero before this change.** Grepping `test/` for every refusal string these paths can
emit returns no hits for any of them, on either site. The regression coverage this correction adds is
recorded with the gate results below.

#### The unified owned-root derivation had a containment defect (2026-07-30)

Step 5 unified both lanes onto `nativeArtifactTargetImmutableClosureRoots`, which is the right shape
— the audit's owned roots then come from the same closed catalog entry as the target, so no lane can
admit a root its target contract never declared. It also introduced a defect of exactly the class
this correction has now hit three times: a check that cannot pass on any valid input.

An installed target's closure root is the relative `.`, so the derivation produces
`<generation>/.`, and `normalise` turns that into `<generation>/` — with a trailing separator.
`pathWithinOwnedRoot` then tests `<generation>//` as a prefix of the loaded path, which fails for
every path underneath it. The Apple installed smoke would have reported
`sealed runner loaded no library from its exact artifact generation` for a run that loaded
correctly, and no machine-independent gate would have said otherwise, because no fixture exercised
that spelling of a root.

`pathWithinOwnedRoot` now drops the trailing separator from both operands, and
`runElfSealedRunAuditAssertions` pins an owned root spelled as the generation's own relative
directory.

#### The style gate depended on undeclared operator config (2026-07-30)

A further machine-independence defect surfaced while validating the above. `infernix-haskell-style`
fails on this host with `cabal is unavailable through HostConfig.toolPaths.cabal and fixed fallback
candidates`, because `hostToolFallbackCandidates HostCabal` lists only `/root/.ghcup/bin/cabal`,
`/usr/local/bin/cabal`, and `/usr/bin/cabal` — the *container* layout. A host whose toolchain lives
under a non-root home has no fallback and depends entirely on `./infernix-host.dhall`, which
`infernix init` creates and which no gate declares as a prerequisite. The previously recorded Linux
`infernix-haskell-style` GREEN therefore silently depended on operator config being present. It is
not a code defect, but the gate set is not self-describing until the prerequisite is stated, and a
`.dhall`-less checkout cannot run the gate the plan calls machine-independent.

#### Machine-independent gate state after the process-group and image-target corrections (2026-07-30)

Run serially by one script over one frozen worktree identity, with the tree digest recomputed
afterwards and proven unchanged: pre- and post-evidence tracked-plus-untracked digest
`sha256:2e3c2f0617af4d78f4a9fcee21f1ef8539bd6694223539016eef8157f441e279`, on native Ubuntu amd64
(GHC 9.12.4, cabal 3.14.2.0).

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN |
| `cabal test infernix-unit` | GREEN — includes `runLeaderlessProcessGroupAssertions` |
| `cabal test infernix-compile-fail` | GREEN — 6 positive, 78 negative |
| `cabal test infernix-artifact-transaction` | GREEN — 44 cases |
| `cabal test infernix-apple-materializer` | GREEN — 12 cases |
| `cabal test infernix-capped-engine-observer` | GREEN |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `cabal test infernix-haskell-style` | GREEN — after the readability correction below |
| `poetry --directory python run check-code` | GREEN — 8 source files |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

The style gate **failed on the first pass of this frozen run**, and the failure is worth recording
rather than smoothing over: three `avoid hanging case` readability violations, all in the corrected
source, at `Cluster/Subprocess.hs:5042`, `Cluster/Subprocess.hs:9015`, and `test/unit/Spec.hs:14905`.
`ormolu --mode check` and `hlint` were both clean on those same files. The repo-owned readability
rules are therefore a genuinely independent gate, and a correction is not stylistically complete
because the formatter and linter accept it — the same lesson the audit already recorded when thirty
readability violations were found behind a stage that had always failed first. The three are
corrected by extracting `recoverableProcessGroupIsActive`, making the owned-roots `case` the outer
expression of its `do` block, and binding the fixture's refusal predicate before its assertion. The
gate is green on the rerun.

**This is not a Stage 1 result.** The host was not idle: the `jitml` sister project ran throughout,
with load between 27 and 32 (`LOAD_START=26.95`, `LOAD_END=32.51`). It is machine-independent
evidence only, and it does not close this sprint. The web unit suite was not re-run and is not
claimed; this correction touches only Haskell sources, their tests, and this plan.

#### Machine-independent gate state after the generation-lease and single-flight corrections (2026-07-30)

Run serially by one script over one frozen worktree identity, with the tree digest recomputed
afterwards and proven unchanged: pre- and post-evidence tracked-plus-untracked digest
`sha256:7077ab25d1f68437eb2cee8c4162591516acd22589fb09467164dd8a788831ee`, installed binary
`sha256:0c3f9d272bf378854791918e211beec8577633b05c15eb1944dfc4a92b1b1f0e`, on native Ubuntu amd64
(GHC 9.12.4, cabal 3.14.2.0).

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN |
| `cabal test infernix-unit` | GREEN — includes `runArtifactGenerationIdentityAssertions` |
| `cabal test infernix-compile-fail` | GREEN — 6 positive, 79 negative |
| `cabal test infernix-artifact-transaction` | GREEN |
| `cabal test infernix-apple-materializer` | GREEN |
| `cabal test infernix-capped-engine-observer` | GREEN |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `cabal test infernix-haskell-style` | GREEN |
| `poetry --directory python run check-code` | GREEN |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

The style gate failed twice before this run and both failures are worth recording rather than
smoothing over, because both were in the corrected source and neither was caught by the compiler: an
eta-reducible lambda `hlint` rejected, and a hanging `case` the repo-owned readability rules
rejected while `ormolu` and `hlint` were clean on the same file. A third pass then failed on
`ormolu` formatting of the `do` block the single-flight wrapper introduced. This is the same lesson
the audit already recorded twice: a correction is not stylistically complete because the compiler
accepts it.

**This is not a Stage 1 result.** The host was not idle — the `jitml` sister project ran throughout,
with load between 28.05 and 33.62. It is machine-independent evidence only. The web unit suite was
not re-run and is not claimed; this correction touches only Haskell sources, their tests, and the
plan.

#### Gate state after the generation-lease, Linux-environment, and leading-argument corrections (2026-07-30)

Run serially by one script over one frozen worktree identity, with the tree digest recomputed
afterwards and proven unchanged: pre- and post-evidence tracked-plus-untracked digest
`sha256:8c5482b1d116b47406609b3385b4bf12065caf0463669b20acac6cf65a966d62`, installed binary
`sha256:f7d2efc48a8b3680d670b94591c135b9e65cc0371586b70ab1f1502857777cf8`, on native Ubuntu amd64
(GHC 9.12.4, cabal 3.14.2.0).

| Gate | Result |
|------|--------|
| `cabal build all --enable-tests` | GREEN |
| `cabal install --installdir=./.build ... all:exes` | GREEN |
| `cabal test infernix-unit` | **RED** — the publish/observe race above |
| `cabal test infernix-compile-fail` | GREEN |
| `cabal test infernix-artifact-transaction` | GREEN — 47 cases |
| `cabal test infernix-apple-materializer` | GREEN |
| `cabal test infernix-capped-engine-observer` | GREEN |
| `cabal test infernix-execution-plan-internal` | GREEN |
| `cabal test infernix-haskell-style` | **RED** — one `ormolu` import-ordering diff in the corrected source |
| `poetry --directory python run check-code` | GREEN |
| `infernix lint files`, `lint docs`, `lint proto`, `lint chart` | GREEN |
| `infernix docs check` | GREEN |
| `git diff --check` | GREEN |

Both reds were diagnosed and corrected, and correcting the style gate took three passes — the
`ormolu` import order, then an `hlint` infix-lambda hint, then a repo-owned hanging-`case`
readability violation that `ormolu` and `hlint` both accepted. That is the **fifth** time in this
correction that a change the compiler accepted was not stylistically complete, and the third time the
repo-owned readability stage caught something the formatter and linter did not.

**The complete set is GREEN on the corrected tree**, run serially by the same script over one frozen
identity, digest recomputed afterwards and proven unchanged: pre- and post-evidence
tracked-plus-untracked digest
`sha256:d1f6423060c6ef067e859d3c0fb3347df9e9272cc534095ef8e01c345da7f010`, installed binary
`sha256:0452b20c5b09a001c3bdbc11045fe8d2ae53576bf369bf4ae6c0d9de5015b0a6`. Every row above is GREEN
on that identity, including `infernix-unit` and `infernix-haskell-style`.

**It is still not a Stage 1 result.** The host was not idle on either run — the `jitml` sister
project ran throughout, `LOAD_START=24.99`, `LOAD_END=30.31` on the green run — so Stage 1 on a quiet
host remains owed. The web unit suite was not re-run and is not claimed; these corrections touch only
Haskell sources, their tests, and this plan.

### Machine-Independent Apple Materializer Fixture Scope

The machine-independent Apple materializer boundary fixture exercises the same private indexed
runner as production, but its fixed actions write synthetic marker files. It proves transition
ordering, primary-failure-preserving cleanup, and lock release only; it is not evidence that actual
hydration, relocation, smoke, activation, or Audiveris detach cleans up under cancellation. The
private production cancellation hook is a fixed first-order `PauseAfterAudiverisMount` action
carrying only synchronization cells, so it cannot capture writer authority or inject an arbitrary
effect. A fresh Darwin cohort must cancel the real Audiveris materializer through that hook and
prove exact mount recovery, candidate cleanup, prior-root preservation, and lock reacquisition
before the full-materializer obligation can close.
The default `infernix-apple-materializer` suite remains machine-independent. Its explicit
`--darwin-production-audiveris-cancellation` mode discovers the configured repository paths,
requires a current valid prior `jvm-native` root and a clean candidate boundary, waits on the exact
post-publication mount checkpoint, cancels without a timing sleep, and then validates candidate,
mount, and activity absence, the unchanged complete prior manifest/payload, and immediate
reacquisition of all four Apple provisioning lifecycle locks. The mode is implemented but has not
been run; it is not evidence until the fresh Darwin command below exits green.
**Implementation**: `src/Infernix/Engines/AppleSilicon.hs`,
`src/Infernix/Engines/AppleSilicon/Internal.hs`, `src/Infernix/Engines/Artifact.hs`,
`src/Infernix/Engines/Provisioning.hs`, `src/Infernix/Engines/Provisioning/Internal.hs`,
`src/Infernix/Cluster/Subprocess.hs`, `python/native-runners/apple_native_runner.py`,
`test/artifact-transaction/Spec.hs`, compile-fail fixtures, and Haskell-style enforcement
**Docs to update**: `documents/engineering/apple_silicon_metal_headless_builds.md`,
`documents/engineering/build_artifacts.md`, `documents/development/haskell_style.md`,
`documents/architecture/managed_state_transitions.md`, root workflow mirrors, and this plan

### Objective

Delete every repo-owned Objective-C/C/Metal source literal and every `.h`/`.m`/`.c` materialization
or Clang compilation path. Preserve the headless Apple engine-artifact manifest and fail-closed
runtime-smoke contract through public APIs whose native implementation is owned by upstream
packages, without direct FFI, inline native source in another language, or a renamed unsafe bridge.

### Deliverables

- remove `appleMetalBridgeHeader`, `appleMetalBridgeSource`, `appleMetalBridgeSmokeSource`,
  `coreMlRunnerSmokeSource`, and their source-file writers/compiler scripts
- replace the fixed repo-owned bridge artifact with a typed smoke that performs a real bounded
  operation through an upstream-owned Apple runtime package already admitted by the engine lane
- keep smoke/materialization commands generated from closed adapter identities, explicit tool
  paths, explicit arguments, bounded provisioning authority, and typed artifact manifests
- retire every generated `bin/*` shell wrapper and the stale wrapper-shaped manifest contract;
  launch each native CLI, interpreter, or JVM target directly through the Haskell helper kernel
- bind Linux absolute image targets and every interpreter/library/script closure to
  descriptor-derived exact immutable-image observations; a catalog path string or recipe-policy
  fingerprint is not executable-byte evidence
- keep `ProvisioningGrant s` nominal and opaque and `ProvisioningSession s result` indexed under
  `withProvisioningGrant`'s rank-2 region. Its constructor/interpreter and all raw provisioning
  command constructors remain hidden; the public Apple facade exposes no raw per-artifact installer
- compile the closed Poetry install/setup, protobuf generation, Python probing/venv/package,
  Audiveris image, installed-smoke, and provenance operations through the self-exec
  anchor/supervisor/pin bounded-command kernel with a positive total deadline, explicit
  environment, bounded capture, typed outcome, and exhaustive cleanup
- hydrate and smoke the candidate root before its atomic swap so any provisioning/runtime failure
  preserves the prior complete root and leaves no partial final root
- pin each direct Python requirement and pip itself, record the full resolved Python/source/runtime
  provenance, and compute the manifest digest deterministically from the sorted hydrated payload
  paths, types, modes, bytes, and safe symlink targets rather than declarative metadata
- create candidate venvs with copied launchers and no bytecode, rewrite owned scripts/config to the
  final root before smoke, and fail closed if any candidate-root bytes remain
- checksum-gate the fixed Audiveris 5.10.2 release DMG, classify a live mount by kernel device id,
  and detach through the primary-preserving bounded release path
- synchronize the candidate tree and parent directories around sibling renames, retain
  `.previous` until final-path validation, roll back on synchronous/asynchronous failure, and
  reconcile only an unambiguous exact final, previous, or candidate root after a crash; classify a
  validated pre-correction declarative root only as an explicit migration predecessor or rollback
  root, never as an exact candidate or successfully activated exact root
- make an exact byte- and manifest-identical rerun a candidate-discarding no-op so immutable
  overlay lower-layer roots do not require a rename; a different candidate still follows the
  fail-closed replacement transaction
- use `${HOME}/.local/share/pypoetry/venv/bin/poetry` in the generated Apple host manifest and
  create that fixed default only through the kernel-locked, deadline-bounded bootstrap with exact
  Python and pinned Poetry requirements; retain `/opt/homebrew/bin/poetry` only in the fixed
  manifestless fallback list, and keep a configured non-default missing path a hard failure
- extend lint/unit coverage so native-source strings, native source-file materializers, direct
  compiler consumption of repo-owned source, native-source extensions, Cabal native-source fields,
  and Cabal CPP token-synthesis definitions fail
- record the removed embedded source and superseded bridge topology in the deletion ledger

### Validation

- focused unit tests prove the materializer emits no native implementation source and still
  produces complete typed manifests and fail-closed smoke commands
- `cabal test test:infernix-artifact-transaction --test-show-details=direct` passes the complete
  settled-source deterministic identity, unsafe-payload, exact/legacy distinction, idempotent
  rerun, activation,
  smoke-bound tamper, migration, sync/async rollback, and crash-reconciliation cases
- the dedicated full Apple materializer suite passes deterministic recursive-closure,
  failure/cancellation, lock-release, obsolete-root retirement, and recovery cases
- machine-independent synthetic boundary cases are accepted only for indexed-runner ordering and
  cleanup mechanics; actual-materializer cancellation requires a fresh Darwin run through the
  fixed post-mount hook with exact mount, candidate-root, prior-root, and lock evidence
- after a green `./.build/infernix internal materialize-metal-engines` creates the required current
  prior root, the exact opt-in cohort command is
  `cabal test infernix-apple-materializer --test-show-details=direct
  --test-options='--darwin-production-audiveris-cancellation'`; this command is pending
- `cabal test infernix-compile-fail --test-show-details=direct` passes every settled-source positive
  and negative fixture, including hidden Apple internal/artifact/provisioning imports and the removed raw
  per-artifact installer
- Haskell style rejects direct process access, legacy unbounded Poetry-helper delegation, and
  bounded-kernel bypass throughout the Apple artifact/provisioning modules; focused unit and Python
  `check-code` gates pass
- repository scans and `infernix lint files` find no repo-owned native implementation source,
  embedded equivalent, or Cabal native-source declaration
- the complete machine-independent Stage 1 gate passes on the exact reviewed worktree
- the Apple cohort rematerializes the affected artifacts, proves the upstream-owned runtime smoke,
  and completes the correction-dependent routed lane before any Apple closure is claimed
- the paired source-matched `linux-cpu` cohort completes before Phase 1 is marked `Done`

### Remaining Work

Authoritative current remainder (2026-08-02): **validation only**. On an Apple Silicon host,
rematerialize the corrected MLX/Core ML/native-runner roots, run the opt-in production Audiveris
cancellation case and installed upstream authoritative smokes with the source runtimes unavailable,
then complete `infernix test integration`, `infernix test e2e`, and `infernix test all` for the
Apple catalog and record the Wave Y attestation. The exact-source Stage 1 and paired `linux-cpu`
cohort are GREEN; no code-side item below remains open. The remainder of this section is retained
as rejected-identity audit chronology and is superseded as a work list by this paragraph.

The gate set now builds and runs on a second machine. Four machine-independence defects are closed,
and the two Linux process-group lifecycle races are **now corrected** across the eight sites the
adversarial sweep found, with the bounded absence prover's EPERM arm as the interlock the rest
depend on. Both are recorded under
[The machine-independent gate set was Apple-specific](#the-machine-independent-gate-set-was-apple-specific-2026-07-30)
and [Two Linux process-group lifecycle races](#two-linux-process-group-lifecycle-races-2026-07-30)
above, and the correction under
[The leader-absence conflation is corrected](#the-leader-absence-conflation-is-corrected-2026-07-30).
A fifth machine-independence defect surfaced while validating it and is recorded under
[The style gate depended on undeclared operator config](#the-style-gate-depended-on-undeclared-operator-config-2026-07-30):
`infernix-haskell-style` cannot find `cabal` on a host whose toolchain is not at a container path
unless `infernix init` has written `./infernix-host.dhall`, which no gate declares as a
prerequisite.

The correction ships with the first regression coverage these paths have ever had.
`runLeaderlessProcessGroupAssertions` in `test/unit/Spec.hs` builds a live process group whose exact
recorded leader has already been reaped, synchronising on pipes and a blocking reap rather than on
sleeps, and asserts its own preconditions so a platform whose birth-identity semantics changed
reports itself instead of passing vacuously. It pins three things: recovery classifies the group
active rather than refusing it; the group is never signalled by its bare process-group id once the
leader can no longer vouch for it, and an unprovable absence fails closed; and the ordinary path
completes once the group really goes away. Both assertions discriminate against the pre-correction
source, which raised `refused to signal a live group whose exact leader is absent` and
`live group has no exact recorded leader` respectively.

The enumerated, current remainder — with per-item file anchors — is in
[Loader-Closure Producer and Writer-Effect Audit](#loader-closure-producer-and-writer-effect-audit-2026-07-29)
above. That audit supersedes the "roughly fifteen writer effects" and "Linux lease identity derives
from only the metadata-root payload digest" statements in this section and in
[README.md](README.md), and closes the ELF/loader-producer item. Work the eleven numbered writer
items, the JavaCPP pre-extraction, and the bound-coverage plan from there rather than from the prose
below, which remains accurate for every other obligation.

The generation-lease consumer residual is closed there too, along with the two High findings that
came out of it. The **raw-CLI runtime argument translation** it exposed is a new open item of the
same kind as the JavaCPP decision: `llama-cpp-cli` and `whisper-cpp-cli` carry no argument prefix, so
the runtime launch still hands the real llama.cpp/whisper.cpp binaries the native-runner protocol
they do not parse. The retired shell wrapper was that translation layer and nothing replaced it
outside the `--version` smokes.

Close every finding from all five rejected reviews. Raw executable and raw-IO lift authority must
not typecheck; Python and native launches must accept only closed semantic invocations whose raw
executable, argument, working-directory, and environment representations are kernel-owned.
Generated shell-wrapper materialization must be removed completely, and the manifest/recipe
contract must describe direct targets rather than retain a logical `bin/*` wrapper facade. For
absolute Linux image targets, the artifact record must bind exact descriptor-derived target,
interpreter, script, and runtime-closure observations; hashing catalog path text alone is not
accepted as target provenance. The runtime capability must remain inside an abstract one-shot
indexed launch action interpreted only
while its shared lock is held through reap; every repo-owned writer must require lock-scoped
authority; the manifest must bind the current closed recipe; and payload traversal must use a
descriptor-anchored stable snapshot. CLI artifacts must carry and execute their recursive upstream
runtime closure, including frameworks and ggml plugins. Exact resolved-tool evidence must reach an
owned immutable execution generation rather than being discarded before pathname `exec`; Poetry
must bind its interpreter and package closure. Mach-O provenance must be minted from the exact
copied destination. Audiveris copy, detach, and owner-death recovery must consume durable exact
device evidence, and malformed dyld audit frames must fail closed. Full-materializer synchronous
failure, asynchronous cancellation, obsolete bridge retirement, deterministic recursive-closure
fixtures, macOS mount-death recovery, and capped-engine cleanup under a live exact group-owner
identity must pass. Full-root copy is not an acceptable installed-artifact execution generation:
the exact retained candidate/final root must be descriptor-custodied under its generation lease,
and dead-owner activity recovery must prove every recorded group absent before a new writer can
mutate that generation. The selected entry/byte/depth limits must be practical for all seven
measured artifacts and covered by positive and overflow tests. Then run a fresh final review and
complete source-matched
Stage 1 against one identified worktree. Only afterward may the Apple lane rematerialize every
affected artifact, run installed authoritative smokes, prove routed runtime loading, complete the
Apple and paired `linux-cpu` cohorts, and record Wave Y evidence. Phase 0's accepted all-Haskell
identity remains unchanged and closes Sprint 0.18 only.

### Remaining Work — reopened 2026-08-08

Two defects in this sprint's own surface, both found on Darwin after the
[2026-08-08 evidence reset](cohort-validation-waves.md). Both are code-side, so this sprint is no
longer validation-only.

- **The bounded-command target-environment allowlist admits no row for the Poetry snapshot
  environment any renderer produces.** `validateRenderedEnvironment`'s exact-match set at
  `src/Infernix/Cluster/Subprocess.hs:8337-8352` requires `PYTHONNOUSERSITE` on both
  `poetrySnapshotNames` (`:8278`) and `poetrySnapshotDyldNames` (`:8288`), while
  `packageClosureSnapshotEnvironment` (`:15032-15048`) emits only `PYTHONHOME`, `PYTHONPATH`, and on
  non-Linux `DYLD_FRAMEWORK_PATH`/`DYLD_LIBRARY_PATH`. Linux passes only because `:15039`
  short-circuits to a row that omits the name. **Three entry points fail on Darwin**, not one:
  `infernix test lint`, `infernix test all`, and `cluster up`
  (`Cluster.hs:689` → `Engines/AppleSilicon/Internal.hs:190 ensureBoundedPoetryProjectReady` →
  `installPoetryProject`), so `bootstrap/apple-silicon.sh up` is down. The correction is to derive
  the admissible name set from the renderer vocabulary rather than restating it — a second copy of
  what the renderers construct is what drifted. Note `validateRenderedEnvironment` (`:3623-3626`)
  treats `[PYTHONNOUSERSITE, PYTHONDONTWRITEBYTECODE]` as an **order-sensitive** list while
  `fixedProvisioningProcessWithEnvironment` (`:4250`) always prepends the guard, so re-adding the
  name through a renderer fails at a second site. The four dead rows are ledgered in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
- **Audiveris installed-smoke path drift.** `Engines/Provisioning/Internal.hs:282-283` now returns
  `Audiveris.app/Contents/runtime/Contents/Home/bin/java`, while the consumer at
  `Cluster/Subprocess.hs:15109-15119` still matches only
  `["Audiveris.app","Contents","MacOS","Audiveris"]` and falls through to `[]`, dropping
  `DYLD_PRINT_LIBRARIES`. The environment gate does not catch it — the set collapses to the
  allowlisted `pythonNoBytecodeNames` — so it fails later at the loader audit with "sealed runner
  emitted no DYLD loader provenance". Producer and consumer are again two copies of one path.

**Cohort gate**: [Wave Y](cohort-validation-waves.md).

---

## Sprint 1.21: Bounded Host Build Memory Kernel [Active]

**Status**: Active — code-side closed; the Apple lane's mechanism is validation-only and belongs to
its cohort wave.
**Code-side closure**: the kernel, the calibrated committed floor, the measured manifest facts, and
the generated per-machine ceiling are implemented and GREEN on the machine-independent gate set
(`cabal build all --enable-tests` under `-Wall -Werror`, `infernix-unit`, `infernix-haskell-style`,
`infernix lint files|chart|proto|docs`).
**Cohort gate**: `apple-silicon` — Wave Y. Darwin's mechanism is a runtime heap cap plus bounded
concurrency and nothing here measures it.
**Implementation**: `src/Infernix/BuildMemory.hs`, `src/Infernix/HostMemory.hs`, `infernix.cabal`,
`cabal.project`, `test/compile-fail/cabal.project`, `src/Infernix/HostConfig.hs`,
`src/Infernix/Runtime/Enforcer/Internal.hs`, `src/Infernix/DemoConfig/Internal.hs`,
`src/Infernix/ProjectInit.hs`, `src/Infernix/CLI.hs`, `docker/Dockerfile`
**Docs to update**: `documents/architecture/bounded_host_memory.md`,
`documents/engineering/host_tools_manifest.md`, `documents/development/local_dev.md`

### Objective

Give the host toolchain a declared account on physical memory, and make a ceiling that was never
divided by its concurrency impossible to construct.

The declared quantity is a budget for the toolchain account together with the job count it will be
multiplied by. `deriveBuildMemoryPlan` is the single mint and the only producer of the
hidden-constructor `BuildMemoryPlan`; `planRtsHeapMib` and `planProcessAddressMib` are accessors on
that type alone, so a per-process ceiling cannot exist without the budget and concurrency that
produced it. This is the sprint that refuses the obvious wrong fix: a 48 GiB per-process heap cap
under `jobs: $ncpus` on a 32-core host permits 1536 GiB.

The kernel is only installable because the built executable declares a bounded runtime address-space
reservation first. Measured on the development host: the compiler runtime reserves 1024.65 GiB by
default and 1.15 GiB under `-xr1G`, at identical resident memory. Without that, lowering the
process's own address-space limit succeeds and then kills it on its next allocation, so the
establish-at-startup-and-inherit pattern that `Infernix.DescriptorSpace` uses does not otherwise
transfer.

### Deliverables

All five are implemented.

- **A bounded runtime address-space reservation on the built executable.** The `infernix` executable
  carries `-with-rtsopts=-xr1024M`; the linked binary is verified to carry it. `toolchainReservationFitsEveryPlan`
  pins the invariant that the reservation stays below the smallest per-process ceiling the mint can
  produce, and the unit suite asserts it rather than trusting two constants to stay in agreement.
- **A calibrated ceiling and bounded job count committed to `cabal.project` and the compile-fixture
  project**, covering a fresh clone and an operator's own direct `cabal` invocation. Both files carry
  `jobs: 4` plus `ghc-options: +RTS -M4096M -xr12288M -RTS`, and both state the product rather than
  the per-process number alone. The compile-fixture project is one of the nested builds the doctrine
  names as outside the outer ceiling, so it carries its own.
- **`Infernix.BuildMemory`** exporting `BuildMemoryBudget`, `BuildConcurrency`, and `BuildMemoryPlan`
  abstractly with `deriveBuildMemoryPlan` as the only mint, following the hidden-constructor,
  lower-only, fail-closed shape of `Infernix.DescriptorSpace`. `establishBoundedBuildMemory` writes
  the hard limit as well as the soft one — a bound a child can raise back is not a bound — and
  `requireBoundedBuildMemory` is the fail-closed observation at the point of use.
- **Physical-memory facts in the host manifest, measured rather than declared.** `Infernix.HostMemory`
  reads `MemTotal` from `/proc/meminfo` and intersects it with the cgroup v2 maximum on Linux, and
  `sysctl -n hw.memsize` on Darwin, reusing the cgroup reader lifted out of
  `Infernix.Runtime.Enforcer` into `Infernix.Runtime.Enforcer.Internal`. `infernix init` refuses to
  write a manifest it could not measure.
- **The per-machine ceiling generated into the untracked `cabal.project.local` by `infernix init`**,
  derived from those facts, superseding the hand-written stopgap, which is deleted. `internal
  materialize-substrate` writes it too, so the launcher image's own build is bounded by the same
  derivation. On the 124.94 GiB development host that is a 63967 MiB account divided by 8 jobs into
  a 7995 MiB heap cap and a 23985 MiB address-space reservation.

Two decisions inside are worth stating rather than leaving implicit.

**The account is a claim on resident memory, and the address-space ceiling is derived from it rather
than the other way round.** The runtime reserves about three quarters of an address-space limit and
its copying collector needs two semispaces, so usable heap tracks an address-space limit at roughly a
third of it. Carrying both numbers independently would let them drift; the plan therefore derives
`planProcessAddressMib` from `planRtsHeapMib` through one `heapToAddressSpaceMultiplier`.

**A stale host manifest is a named refusal, not a raw Dhall type error, and the named remedy is
`delete and re-run infernix init`.** Adding a record to the manifest breaks every previously
generated file, and startup deliberately fails closed on a manifest it cannot decode rather than
falling through to convention defaults that could misclassify the execution context. Making
`infernix init` itself tolerant was considered and rejected: `init` is reached only after several
earlier startup paths have already loaded the manifest, so tolerance would have to be threaded
through all of them to buy an operator one `rm`.

### Validation

- **The calibration run.** A complete clean `cabal build all --enable-tests` — 611 module
  compilations across six components, so the largest module in `src/` is compiled six times — peaked
  at **1328 MiB** resident in the largest single compiler process and **1798 MiB** summed across every
  concurrent compiler and `cabal` process, in 8 m 13 s. The shipped 4096 MiB per-process floor is
  3.1 times the single-process peak. The measurement, not the number, is what is maintained.
- `cabal test infernix-unit` proves the bound is inherited through the compiler chain (a spawned
  child reports the identical limit, and the real `ghc` compiles a module under it), that an
  unresolvable ceiling is a named refusal, that establishing it never raises a tighter host-imposed
  limit, and that the generated `cabal.project.local` states its job count, its per-process cap, and
  their product.
- An adversarial over-allocation under the ceiling exits non-zero and cleanly, with no global
  out-of-memory condition. Every case that installs a ceiling runs in a re-exec of the suite binary
  with an explicit `+RTS -xr` reservation, because the suite's own image takes the default
  1024.65 GiB and could not lower its own limit below it.
- `cabal build all --enable-tests` under `-Wall -Werror` and `infernix lint docs` are GREEN, and the
  whole gate set above ran under the new committed floor rather than the retired stopgap.

### Remaining Work

The Apple lane's mechanism is unmeasured and is proved by its cohort wave, not by this gate set:
Darwin aliases the address-space limit to an advisory resident-set limit, has no cgroups, and has no
equivalent global out-of-memory killer, so its bound is a runtime heap cap plus bounded concurrency
and the aggregate is arithmetic rather than enforcement. Until Wave Y records a result, no claim in
this sprint covers it.

The toolchain *spawn boundary* — the closed invocation vocabulary that makes starting a build from a
bare command list not typecheck, plus the `unboundedToolchainSpawnViolations` lint and the child
victim rank — is Phase 6 Sprint 6.46 and is deliberately not claimed here. Until it lands, the
ceiling is installed by the committed and generated project files rather than by an evidence-gated
spawn.

**Reopened 2026-08-08 — the Darwin account does not intersect the co-resident VM pledge.**
`observeHostMemoryFacts` (`src/Infernix/HostMemory.hs:160-170`) sets effective memory equal to
physical on Darwin, while the Linux arm intersects the cgroup maximum at `:125`. On the supported
Apple host both lanes run inside the same Colima VM, and that VM's pledge is not physical memory the
toolchain may also spend. Measured on the development host on 2026-08-08: physical **65536 MiB**;
generated `cabal.project.local` grants `jobs: 8` x `-M4096M` = **32768 MiB**; `colima list` reports
the default profile Running with a **48 GiB** pledge. 32768 + 49152 exceeds 65536, so the account is
over-subscribed by 16 GiB and the doctrine's own "a ceiling is inseparable from the concurrency it is
multiplied by" arithmetic is being performed against the wrong denominator. The intersection
machinery already exists and the *inference* budget already applies it on Darwin
(`src/Infernix/DemoConfig/Internal.hs:428-448`), so two subsystems currently disagree about the same
RAM. The doctrine gap is owned by Phase 0; this sprint owns the measurement.

---

## Sprint 1.22: Resolve The Build-Memory Lane Instead Of Assuming It [Active]

**Status**: Active — code-side closed and GREEN on Apple Silicon; the `linux-cpu` confirmation run
is the only item left.
**Implementation**: `src/Infernix/BuildMemory.hs`, `test/unit/Spec.hs`,
`test/compile-fail/fail/CannotClaimUnenforcedAddressSpace.hs`, `test/compile-fail/Main.hs`,
`test/compile-fail/infernix-compile-fixtures.cabal`
**Docs to update**: `documents/architecture/bounded_host_memory.md`

### Objective

Sprint 1.21 wrote one platform-independent bound type while its own doctrine said the mechanism is
resolved per lane. That gap was not academic: it took every gate command down on Apple Silicon.

`withToolchainSpawnAuthority` resolved the lane and then discarded the answer, so
`withBoundedToolchainChild` assumed an address-space rlimit on every lane. Darwin reports `RLIMIT_AS`
infinite and rejects every finite ceiling written against it with `EINVAL` — measured: soft and hard
are both `INT64_MAX`, and `setrlimit` refuses `{finite, INFINITY}`. `setResourceLimit` therefore
threw before the child was started, so `infernix test lint`, `test unit`, `test integration` and
`test all` all died at the first toolchain spawn. `BuildMemory.hs` has a single commit dated
2026-08-07 and had never run on Darwin.

### Deliverables

- **The resolved mechanism is retained rather than discarded.** `ToolchainSpawnAuthority` carries it
  alongside the plan, and `withBoundedToolchainChild` holds a ceiling only on a lane that implements
  one. This is a **runtime lane resolution, not a type-level guarantee**, and is labelled as such —
  the gates came back on this change alone.
- **The lane distinction is in the types.** `BuildMemoryMechanism` is a GADT indexed by
  `AddressSpaceEnforcement`; `BuildMemoryBound` carries that index; `enforcedAddressCeilingMib` is
  defined only for `'AddressSpaceEnforced`. Each constructor fixes its own index, so the claim and
  the evidence are one fact — a separate unindexed copy beside the index would have reintroduced the
  over-claim one line below the type forbidding it. `resolveBuildMemoryMechanism` returns the new
  `ResolvedBuildMemoryMechanism` sum, which is where the runtime fact is refined and where every
  consumer is forced to handle both arms.
- **The mints return `Either` rather than a rank-2 region.** Identical refinement, `-Werror` already
  forces both arms, and no CPS rewrite of the fixture's call sites. A `with`-shaped region in this
  repository means the capability dies at region exit, but `establishBoundedBuildMemory` installs a
  permanent, one-way, image-wide limit — the region shape would mis-signal.
- **An unenforced bound observes something.** `observeHeapCapOnlyBound` re-reads the runtime heap cap
  committed to `cabal.project.local` and refuses when it is absent, unparseable, or disagrees with
  the derived plan. Without it the Darwin arm would mint evidence from the caller's own argument,
  contradicting this module's stated principle that `requireBoundedBuildMemory` is the observation at
  the point of use. The read is strict: a lazy `readFile` holds the handle open through the refusal
  paths, and the next writer fails with `resource busy` instead of the intended diagnostic.
- **Unit coverage branches by lane.** The unenforced arm asserts the two refusals (absent cap, stale
  cap) and the agreeing case; the real compiler-chain assertion is shared, because it carries content
  on both lanes.
- **A compile-fail fixture pins the index**: `CannotClaimUnenforcedAddressSpace.hs` applies
  `enforcedAddressCeilingMib` to a `'AddressSpaceUnavailable` bound and must fail as a type mismatch.
  It carries `{-# LANGUAGE DataKinds #-}` explicitly — the fixture package is `GHC2021`, which does
  not include it, and without the pragma the fixture fails with the wrong diagnostic class.

### Validation

- `./.build/infernix test lint` reaches and passes `infernix-haskell-style` on this Mac; before the
  change it died immediately with `setResourceLimit: invalid argument`.
- `cabal test infernix-unit` is **PASS on Darwin with no local scaffold** — the criterion this sprint
  was written against.
- `cabal test infernix-compile-fail`: 6 positive, 88 negative, including the new fixture.
- `cabal test infernix-haskell-style` GREEN.

### Remaining Work

- The `linux-cpu` lane run. The enforced arm is unchanged in behaviour but its code moved, and this
  host cannot exercise it natively; drive it through the existing colima native arm64 daemon.
- `infernix test lint` still does not complete on Darwin — it now reaches a **separate, unrelated**
  pre-existing failure in `Infernix.Python` provisioning: `bounded-command target environment does
  not match a closed rendered environment`, naming `DYLD_FRAMEWORK_PATH`, `DYLD_LIBRARY_PATH`,
  `PYTHONHOME`, `PYTHONPATH`, `PYTHONDONTWRITEBYTECODE`. That is an environment-closure defect, not a
  build-memory one, and is owned separately.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/build_artifacts.md` - build roots, generated-artifact doctrine, snapshot launcher expectations, and native engine artifacts under `./.data/engines/<adapterId>/`
- `documents/engineering/apple_silicon_metal_headless_builds.md` - Tart-free Apple Metal/Core ML materialization target, upstream package boundary, manifest fields, and validation gates
- `documents/engineering/docker_policy.md` - host versus outer-container rules, image-snapshot launcher contract, and the clarification that Apple materialization is not a Docker/Colima lane
- `documents/engineering/host_tools_manifest.md` - supported host-tool schema without `hostTart`
  plus the retained `materialize-metal-engines` manifest surface
- `documents/engineering/implementation_boundaries.md` - ownership boundaries across Haskell, Python, chart assets, and generated outputs
- `documents/engineering/portability.md` - portable platform rules versus substrate-specific behavior, including the Apple headless materialization lane
- `documents/architecture/configuration_doctrine.md` - typed engine-artifact materialization records and the no-env rule
- `documents/architecture/managed_state_transitions.md` - Managed State Transitions doctrine this phase now references, generalizing the results-side realness contract to typed evidence for every state transition
- `documents/operations/apple_silicon_runbook.md` - Apple host workflow, headless materialization expectations, and Tart-free validation gate
- `documents/development/haskell_style.md` - formatter, linter, hard-gate, and review-guidance doctrine
- `documents/development/local_dev.md` - canonical local operator workflows

**Product or reference docs to create/update:**
- `documents/reference/cli_reference.md` - canonical `infernix` command inventory
- `documents/reference/cli_surface.md` - short subcommand-family overview
- `README.md` - orientation layer that links to canonical docs rather than restating them
- `AGENTS.md` - governed automation entry document aligned with canonical docs
- `CLAUDE.md` - governed automation entry document aligned with canonical docs

**Cross-references to add:**
- keep [00-overview.md](00-overview.md) and [system-components.md](system-components.md) aligned
  when substrate ids, serialized `runtimeMode` identifiers, build-root rules, launcher doctrine,
  or command-registry ownership change
