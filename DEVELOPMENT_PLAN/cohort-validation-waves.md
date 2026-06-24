# Cohort Validation Waves

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md),
[phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md),
[phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md),
[phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md),
[phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md),
[phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md),
[phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md),
[phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

> **Purpose**: Operationalize Section Q of
> [development_plan_standards.md](development_plan_standards.md) by
> recording the per-accelerator validation attestations required by the single-accelerator phase
> rule. Phase docs reference the active wave and pending waves instead of restating cohort residual
> narrative per sprint. Validation-only proof points that require a different physical host are
> queued here and do not trigger ad hoc machine switches outside their named wave. Each open wave
> runs in two stages: **Stage 1** lands the machine-independent code-side closure for the reopened
> phases in natural order on whichever single machine is present, and **Stage 2** records the chosen
> accelerator plus `linux-cpu` full-suite evidence for each phase. No phase waits on both
> accelerators as one must-pass-together gate.

## Wave Table

| Wave | Machine | Scope | Status | Closed |
|------|---------|-------|--------|--------|
| A | Apple Silicon (new host) | Apple cohort `cabal test infernix-integration` full-suite PASS; Apple cohort `infernix test e2e` 5/6 PASS; substrate-aware platform closure (engine replicaCount on Apple set to 0, `engineProcessed` trace, host-service-daemon stdout/stderr capture, Patroni retained-state filter, arm64 publication closure, dynamic Harbor host port, containerd `config_path` patch) | Closed | the recorded validation |
| A.1 | Apple Silicon (new host) | Sprint 7.15 artifact-upload e2e fix: chat-draft-editor form binds its own `submit` listener at construction time (via MutationObserver) instead of relying on `root` delegation, so `requestSubmit()` on a form detached by an interleaved `renderAll` still fires the handler. Closes the 6/6 e2e gate. | Closed | the recorded validation |
| A.2 | Apple Silicon (new host) | Sprint 7.15 per-model browser smoke matrix: `web/playwright/inference.spec.js` adds `browser per-model smoke matrix exercises every catalog model` exercising every selectable model in the demo-config catalog through context create → context-list patch → draft fill → draft-map echo → submit → engine inference → conversation-patch with `inferenceResultStatus = completed`. Closes the 7/7 e2e gate. | Closed | the recorded validation |
| A.3 | Apple Silicon (new host) | Historical Sprint 7.14 Apple `engine.lock` chaos case: `test/integration/Spec.hs` added `validateAppleEngineLockEnforcement` for the former host-singleton design. This evidence remains historical only; the current target is Sprint 7.24 engine-pool assignment, where normal Apple pool membership uses distinct host ids on `Shared` subscriptions and exact-host routes use pinned `Exclusive` topics. | Closed | the recorded validation |
| B | Apple Silicon (new host) | Apple-side code-side work before the CUDA Linux switch: Sprint 7.14 Linux-owned chaos and throughput cases were intentionally carried into Wave C because they require the real Linux integration lane. | Closed | the recorded validation |
| C | CUDA Linux (real Linux host with CUDA hardware, plus the portable `linux-cpu` lane) | Full-suite cohort closure batch on the counterpart cohort: `./bootstrap/linux-cpu.sh` lifecycle on native Linux (portable CPU lane); `./bootstrap/linux-gpu.sh` lifecycle on real CUDA hardware; `docker compose run --rm infernix infernix test all` outer-container full-suite; routed Playwright in-container; validates every phase 1-7 code-side closure already landed on Apple. The remaining Sprint 7.14 Linux-owned code-side cases landed in `test/integration/Spec.hs` as of the recorded validation: frontend pod replacement, coordinator pod replacement around durable prompt dispatch/writeback, engine pod replacement, engine node drain, model-bootstrap request/ready-event deduplication across coordinator replacement, Linux engine anti-affinity, and multi-user durable prompt throughput. Native `linux-cpu` full-suite validation passed on the recorded validation against image digest `sha256:a9f1f19aa9bb492c5186a0f6df8f864ee4e0c900c8209f0434ef64cf6cc821a7`; `linux-gpu` full-suite validation passed on the recorded validation against final rebuilt image digest `sha256:fd951113735f94b613a2fa014088f22e89a4df0b78193cd1ec76d6a44e191689`. | Closed | the recorded validation |
| D | Either | Phase status promotion sweep: Phases 0-6 returned to `Done` after their Wave C cohort gate; Phase 7 carried the remaining runtime KV-cache/runtime-split/failover work into Wave E. Browser-level frontend pod-kill reconnect coverage closed with mounted-source `linux-gpu` E2E and the final rebuilt-image `linux-gpu` full gate; the matching rebuilt-image `linux-cpu` residual full gate passed later on the recorded validation. | Closed | the recorded validation |
| E | Linux CPU mounted worktree | Sprint 7.8 closure: process-local runtime KV-cache path wired through `Infernix.Runtime.KVCache`, `executeInferenceWithKVCache`, native worker output, filesystem-topic drain, and WebSocket Pulsar consumption; daemon role orchestration moved into `Infernix.Runtime.Daemon`. Mounted Linux CPU validation passed `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and `cabal test infernix-integration`, including durable dispatcher/result writeback, engine pod replacement, engine node drain, throughput, platform recovery, production-shape deployment, and clean teardown. | Closed | the recorded validation |
| F | Native arm64 Linux CPU execution | Validation-only Phase 3 Sprint 3.12 closure: native `linux/arm64` `linux-cpu` validation through the already selected arm64 Docker daemon on this Apple Silicon machine. Proved Harbor publication, warmup hydration, final Harbor-backed preload, integration, and routed E2E on the native ARM publication path without cross-architecture emulation or Docker-context changes. | Closed | the recorded validation |
| G | Apple Silicon (current host) | Phase 7 auth-UX quad closure: Sprint 7.19 auth-gated landing with dual Keycloak entry points, Sprint 7.20 themed Keycloak login surface, Sprint 7.21 operator console ribbon with edge JWT gating for `/harbor`, `/pulsar/admin`, and `/minio/s3`, and Sprint 7.22 self-service account deletion with MinIO + Pulsar per-user state reaping before Keycloak account removal. | Closed | the recorded Apple host-native validation |
| H | Apple Silicon (current host) | Full current-host Apple lifecycle revalidation from a clean build root (no prior `./.build` artifacts): `cabal install all:exes`; `infernix lint files/docs/chart/proto` plus `infernix docs check`; `infernix test lint` (haskell-style) and `infernix test unit` (`infernix-unit` plus web 71/71); explicit `infernix cluster up` → `cluster status` (77 pods across 2 nodes, `infernix-manual` storage, full Envoy Gateway route set, `pulsar-bridge-to-host-daemon` dispatch) → `cluster down` (retained-state replay, `./.data` preserved) → post-teardown `cluster status` (`clusterPresent: False`, `lifecyclePhase: cluster-absent`); `infernix test integration` PASS; `infernix test e2e` 9/9; aggregate `infernix test all`. The dynamic `choosePulsarHttpPort` chooser shifted the Pulsar host port 30080→30081 around a VS Code-held `127.0.0.1:30080`. Native arm64 throughout (colima `aarch64`, no emulation or Docker-context changes). Published cluster image `infernix-linux-cpu@sha256:7f341cb1629c1d0af9b72db0fef7b89cc1f13d2bd02afe9be1daeed5e7f18454`. | Closed | 2026-06-09 |
| I | Per-accelerator real-output attestations | Real per-family inference and engine-artifact materialization attestations. Phase 1 Sprint 1.14 is closed on Apple materialization evidence. The CUDA Linux cycle replaced Linux runner-contract payload placeholders with runtime-backed wrappers, strict-smoked all five native adapter roots in `infernix-linux-gpu:local`, then closed Phase 4 and Phase 6 real-output work on 2026-06-20: full `./bootstrap/linux-gpu.sh test` passed the selected CUDA accelerator lane, and rebuilt-image `./bootstrap/linux-cpu.sh test` passed the paired CPU lane. The GPU Playwright matrix exercised all 16 `linux-gpu` catalog rows, including framework-specific and native rows through live routed inference; the CPU lane passed 9/9 routed Playwright plus full integration. | Closed | 2026-06-20 |
| J | Apple Silicon + Linux CPU/GPU | Substrate-neutral engine-pool routing and broker-native backpressure. Re-opened Phase 4 Sprint 4.19, Phase 6 Sprint 6.32, and Phase 7 Sprint 7.24 to replace raw batch-topic routing, the Apple singleton/failover stopgap, and demo-off coordinator gating with a validated pool/member graph. Stage 1 code-side work landed on the Linux outer-container lane; Apple Stage 2 evidence covered pinned `Exclusive` member routes, same-machine host-member coexistence on a real `Shared` pool subscription, logical `Shared` backlog/backpressure, and production `demo_ui = false`; Linux CPU Stage 2 covered Kubernetes-observational members, pool placement, shared-subscription backlog/backpressure, replacement/drain cases, anti-affinity, lifecycle rebinding, and demo-off publication. The remaining Linux GPU/CUDA Stage 2 gate closed on 2026-06-20 through the full `./bootstrap/linux-gpu.sh test` pass, paired with the rebuilt-image `./bootstrap/linux-cpu.sh test` pass. Physical Apple multi-host routing is deferred hardware proof, not open Wave J work. | Closed | 2026-06-20 |
| K | CUDA Linux + Linux CPU | **Realness reopen — real Linux inference.** Reopened Phase 4 (Sprints 4.21–4.23) and Phase 6 (Sprint 6.33), built on the Phase 0 (Sprint 0.12) machine-independent realness lint (Haskell `realnessFabricationViolations` in `HaskellStyle.hs` + Python `check-code` AST): remove every adapter/runner fabrication path (done 2026-06-23), retire the JAX/TF adapters (done), deliver real Linux engines (real ONNX basic-pitch over the input, real Audiveris invocation, de-masked whisper/CT2/llama), ONNX adoption (Demucs/Open-Unmix self-contained ONNX, SDXL-Turbo on GPU), fixed weight provisioning, modern PyTorch music-transcription rebinds, Phase 4's own real per-family fixtures + fail-closed per-row int+e2e (Sprint 4.23), and the Phase 6 fail-closed HA/service-loop assertions (Sprint 6.33). Stage 1 machine-independent gates + Stage 2 `linux-gpu` + `linux-cpu` real per-family output for the Linux catalog. | Open | — |
| L | Apple Silicon + Linux CPU | **Realness reopen — real Apple engines.** Reopened Phase 1 (Sprint 1.15): replace the Apple validation-wrapper runners with real Core ML, MLX, llama.cpp/whisper.cpp Metal, CTranslate2, ONNX, and Audiveris engines through the headless materialization lane; the same DRY substrate-agnostic suite runs on `apple-silicon`. Stage 1 machine-independent + Stage 2 `apple-silicon` + `linux-cpu` real per-family output for the Apple catalog. Does not block Wave K. | Open | — |

### Correction — Waves C, I, and J inference evidence superseded by Waves K/L

A multi-agent audit established that the per-family **inference** evidence recorded in Waves C, I, and J
was, for several catalog rows, satisfied by silent fabrication rather than real model execution: the
Apple native engine layer (`AppleSilicon.hs` `infernix_emit_validation_result`) is entirely a validation
wrapper, and on `linux-gpu`/`linux-cpu` the source-separation (Demucs/Open-Unmix), audio-to-MIDI
(basic-pitch ONNX run on `np.zeros`), and OMR (Audiveris, never invoked) rows returned constant/
placeholder artifacts while whisper.cpp/CTranslate2 masked failures. The **architectural** closures in
those waves (typed dispatch, catalog, pool routing, cache, object storage, HA/backpressure) stand. The
**real per-family output** claims — including Wave I's "all 16 `linux-gpu` catalog rows … through live
routed inference" — are **superseded** by **Wave K** (Linux real inference) and **Wave L** (Apple real
engines) for the affected rows, which deliver realness-by-construction and re-attest real output on a
single accelerator each (`linux-gpu` + `linux-cpu` for K; `apple-silicon` + `linux-cpu` for L). The
removed fabrication surfaces are tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Wave J Stage 1 — Code-Side Complete; Apple and Linux CPU Stage 2 Partial Closure

On 2026-06-13, the Linux outer-container lane landed the machine-independent pool-routing slice for
Phase 4 Sprint 4.19, Phase 6 Sprint 6.32, and Phase 7 Sprint 7.24. Current evidence:

- `./bootstrap/linux-cpu.sh build` rebuilt the `infernix-linux-cpu:local` launcher image and
  exercised Haskell build/install, Linux CPU substrate materialization, Linux native engine
  materialization, web build, Python quality checks, and Playwright/browser dependency setup.
- `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test unit`
  passed the Haskell unit suite and the PureScript web unit suite (71/71).
- The 2026-06-15 native arm64 Docker rerun rebuilt `infernix-linux-cpu:local` through
  `./bootstrap/linux-cpu.sh build` to image digest
  `sha256:1231b46fef9caa98034985921f5db45b6fac5cc043b842c4fc4badab30c5b5db`, including Haskell
  build/install, Linux CPU substrate materialization, Linux native runner-root materialization, web
  build, Python checks, and Playwright dependency setup. A fresh launcher container then passed
  `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix internal materialize-linux-native-engines`,
  proving the shared engine-root installer handles reruns over image-layer baked
  `/opt/infernix/engines/<adapterId>/` roots without the earlier cross-device rename failure.
- Mounted live-source Linux outer-container validation also passed `git diff --check`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
  `cabal run exe:infernix -- lint files`, `lint docs`, `lint proto`, `lint chart`,
  `cabal run exe:infernix -- docs check`, and `cabal run exe:infernix -- test lint`.
- The current source adds a single-host logical `Shared` backlog harness in
  `test/integration/Spec.hs`: two real Pulsar WebSocket consumers join one isolated service-shaped
  subscription with `receiverQueueSize=1`, the first request is held unacked on the busy consumer,
  and the second published request is decoded from the free consumer's Pulsar payload. The present
  Linux outer-container lane compile-validates the harness with a mounted-source linux-gpu Compose
  launcher run of `cabal build test:infernix-integration`. The same current-source pass also
  validates `infernix test lint`, `infernix test unit`, focused
  `infernix lint files/docs/proto/chart`, `infernix docs check`, and `git diff --check`; Apple
  execution is recorded below.

The 2026-06-16 Apple `./.build/infernix test integration` rerun now covers
additional Stage 2 slices: the source-fingerprint image freshness path rebuilt once for source
changes, later edge-port validation cycles reused the stamped image, the active Apple catalog
completed through the host engine daemon, and the pinned-member guard proved `Exclusive`
duplicate-consumer rejection against a real Pulsar broker by launching two daemons with an
isolated `infernix service --config` substrate file. The same pass also proved process-qualified
service consumer names by launching two same-machine Apple host-member daemons on one isolated
derived pool/model topic, observing two real Pulsar consumers on the `Shared` subscription through
the admin stats endpoint, and completing an inference request. It executed the logical `Shared`
backlog/backpressure harness by holding the first service-shaped WebSocket consumer unacked and
proving the second request reached the free consumer. The Apple integration also covered production
`demo_ui = false` route/publication assertions and edge-port conflict/rediscovery.

The 2026-06-16 Linux CPU native arm64 Docker rerun rebuilt `infernix-linux-cpu:local` to image
digest `sha256:ae06ba36fe1f3ffecf48aa86c34abeb0dd1c98cabb030a7da783681ac87a81df`. The image
build passed Haskell build/install, Linux CPU substrate materialization, Linux native runner-root
materialization, `poetry --directory python run check-code`, web build, Playwright browser
dependency setup, and CLI help smoke. The rebuilt-image
`docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test integration`
then passed the Kind-backed Linux CPU integration lane, including Kubernetes-observed engine-pool
placement across two workers, unique-topic `Shared` backlog/backpressure, frontend and engine pod
replacement, coordinator failover, engine node drain, model-bootstrap failover/deduplication,
multi-user durable prompt throughput, Harbor/MinIO/Pulsar/Postgres recovery, lifecycle rebinding,
anti-affinity enforcement, cluster status checks, demo-ui-disabled validation, and final cluster
teardown. The same pass validates the Linux CPU `transformers`/`pytorch` `--with linux-cpu` venv
bake, the deterministic Transformers CPU smoke path, the Bark validation WAV, native runner
ready-sentinel cache handoff, Kind hostPort retry, transport-derived Pulsar stats URLs, unique
shared-pool topics, and pool-topic exactly-once accounting. Wave J and Wave I Linux GPU/CUDA
closure both completed on 2026-06-20 through the full `./bootstrap/linux-gpu.sh test` lane, paired
with the rebuilt-image `./bootstrap/linux-cpu.sh test` lane.
Physical Apple multi-host routing is tracked as deferred hardware proof and is not required to
close the single-host logical Wave J Apple routing/backpressure gate while no second Apple host is
available.

The 2026-06-16 **native amd64** Linux CPU run executed on the actual CUDA Linux cohort host
(Ubuntu 24.04 amd64, NVIDIA RTX 5090, native `nvidia` Docker runtime) rather than through an Apple
arm64 daemon. `./bootstrap/linux-cpu.sh build` produced launcher image
`infernix-linux-cpu:local` (image id
`sha256:826300f10bd05ab2327d9d7cc201c1b9c563a5c45a4c21b8d73d7f25a3f0a7fe`). The first
`infernix test all` attempt surfaced a code-side regression introduced by the most recent HEAD
`refactor` commit: `src/Infernix/Runtime/Worker.hs` had begun importing
`Infernix.Objects.Presigned` directly, which the `infernix-haskell-style` engine-runtime-boundary
gate rejects (`forbiddenEngineRuntimeImports`). The fix moved the presigned-GET object-existence
probe behind the allowed object-access wrapper as
`Infernix.Objects.Upload.objectExistsViaPresignedGet`, dropping the direct `Presigned` import and
the now-unused HTTP imports from `Worker.hs`. Mounted-source `cabal build all` (warnings-as-errors),
`cabal test infernix-haskell-style`, and `cabal test infernix-unit` then passed, the launcher image
was rebuilt with the fix, and the full `./bootstrap/linux-cpu.sh test` (`infernix test all`) passed
end to end: `infernix-haskell-style` PASS, `infernix-unit` PASS plus web unit 71/71,
`infernix-integration` PASS (per-model inference over the active `linux-cpu` catalog, pool
placement, unique-topic `Shared` backlog/backpressure, frontend/coordinator/engine pod replacement,
engine node drain, model-bootstrap failover/deduplication, multi-user durable prompt throughput at
`p95Seconds=96.69`, Harbor/MinIO/Pulsar/Postgres recovery, lifecycle rebinding, anti-affinity, and
production `demo_ui = false` assertions), and routed Playwright e2e `9 passed (5.4m)` including the
per-model browser smoke matrix. This is fresh native-amd64 evidence for the Wave J Linux CPU
pool-routing gate and the Wave I `linux-cpu` full-suite re-validation against current source; the
subsequent 2026-06-20 `linux-gpu` full-suite rerun closed the paired Linux GPU/CUDA gate on the
same host.

### Wave J Apple Logical Multi-Member Criteria

Until a second Apple host is available, the Apple shared-pool distribution gate is satisfied by a
single-host logical multi-member harness that uses real Pulsar transport and separate service
subscription identities:

- launch at least two Apple engine daemon processes on the same Apple host with distinct member ids,
  process-qualified consumer names, isolated runtime roots, and one isolated derived
  `Shared` pool/model topic
- prove Pulsar admin stats report both consumers on the same `Shared` subscription
- create a real backlog with one member intentionally busy or permit-limited, then prove new work is
  assigned to an available member; the current source performs this broker-permit proof with direct
  service-shaped WebSocket consumers and combines it with the existing same-machine daemon
  completion check for the same `Shared` subscription shape
- keep pinned member routes on derived per-member topics with `Exclusive` duplicate-consumer
  rejection
- keep production-shape `demo_ui = false` assertions proving coordinator and engine-pool surfaces
  remain present without demo-only workloads

This closes the Apple `Shared` distribution and broker-backpressure behavior for the current
single-host hardware envelope. When physical Apple multi-host hardware becomes available, the same
scenario should be repeated across at least two Apple hosts to collect network and independent-host
failure evidence; that follow-up is tracked as hardware-deferred proof rather than a prerequisite
for the current Wave J closure.

## Wave A — Closed the recorded validation

The Apple cohort closure batch on the new Apple Silicon host. Validated
the substrate-aware platform layer, the cluster lifecycle, and the
integration-suite proof points. Specific gates:

- `cabal test infernix-haskell-style` — PASS
- `cabal test infernix-unit` — PASS
- `cabal test infernix-integration` — PASS (full suite: every model
  inference assertion, durable-context prompt roundtrip with
  `inferenceResultStatus = completed`, edge-port conflict
  rediscovery, retained-state replay across cluster lifecycle, Harbor
  arm64 publication of all 9 platform images, dynamic Harbor host
  port `30003`, containerd hosts.toml registry resolution).
- `infernix test e2e` — 5/6 Playwright specs PASS (routed edge surface,
  Keycloak self-registration, auth lifecycle, WebSocket JWT validation,
  cross-user object grant isolation). 1 spec fails — artifact-upload +
  reconnect submit — and rolls into Wave B.
- `infernix lint files / docs / chart / proto` — all exit zero.

Sprint 3.11 follow-on code-side closures that landed in Wave A and
made the closure batch possible:
- `repoEngineReplicaCount` substrate-aware (`FinalPhase + AppleSilicon
  -> 0`) in `src/Infernix/Cluster.hs` — eliminates the in-cluster
  engine pod that competed with the host engine daemon on the Pulsar
  Shared subscription.
- `engineProcessed: request=… model=… status=…` trace in
  `consumeTopicSession` in `src/Infernix/Runtime/Pulsar.hs` — one
  diagnostic line per consumed inference.
- Host service daemon stdout/stderr captured to
  `<runtimeRoot>/service/host-service-daemon.log` with 5-minute
  readiness envelope in `test/integration/Spec.hs`.
- Playwright trace + video + screenshot retained on failure in
  `web/playwright.config.js`.
- Patroni retained-state filter (`isPatroniManagedClaim` +
  `scrubStalePatroniDirectories`).
- Apple host manifest defaults (`/opt/homebrew/bin/docker`, libc-derived
  operator home, `/opt/homebrew/bin/skopeo`).
- Subprocess PATH from `HostConfig.toolPaths.*`; curl `-m 30` Harbor
  probe; `LineBuffering` stdout/stderr.
- Substrate-aware Harbor publication (Apple Silicon → arm64; Linux
  substrates → amd64).
- Hand-authored MinIO StatefulSet replacing bitnamilegacy.
- Dynamic Harbor host port via `chooseHarborPort` + `harbor-port.json`.
- Containerd `config_path = "/etc/containerd/certs.d"` patch in
  rendered Kind config.

## Wave B — Closed the recorded validation

Apple-side code-side work has closed. The remaining Sprint 7.14
chaos cases (frontend pod kill, coordinator dispatcher Failover,
coordinator result-bridge Failover, engine pod kill, engine node
drain, coordinator bootstrap-upload Failover, concurrent
model-bootstrap deduplication, Linux engine anti-affinity) and
throughput suites named in `documents/development/chaos_testing.md`
are real-Kind-backed cases that the chaos doctrine assigns to the
LinuxCpu integration lane. They will be implemented and validated as
part of Wave C on the CUDA Linux cohort.

The Apple-half of "one-engine-per-node enforcement" closed in
Wave A.3 via `validateAppleEngineLockEnforcement`.

### Wave C code work landed on Apple Silicon before the lane switch

- Sprint 7.14 Linux engine anti-affinity chaos case
  (`validateLinuxEngineAntiAffinityEnforcement` in
  `test/integration/Spec.hs`) — scales `deployment/infernix-engine` to
  `replicas=2`, waits for one `Pending` pod, asserts a
  `FailedScheduling` event naming pod anti-affinity, then scales back
  to `1` and waits for the deployment to roll out ready again. Gated
  on `runtimeMode == LinuxCpu` so it runs only inside the LinuxCpu
  integration block. Compiled + lint-clean on Apple Silicon the recorded validation;
  validated during Wave C on the native Linux/CUDA host.

## Wave C — Closed the recorded validation

The single supported CUDA Linux cohort closure batch. Runs every phase
1-7 code-side closure that landed in Waves A-B, plus the Linux-owned
Sprint 7.14 chaos and throughput cases that required a real Kind-backed
Linux lane. This is the **one** machine change the supported cadence
permits between now and `Done`.

the recorded validation code-side landing on a native Linux/CUDA host:

- `linux-cpu` generated Kind topology now has two worker nodes. Warmup
  and final Harbor-backed image preloads target all workers, and the
  reference `kind/cluster-linux-cpu.yaml` mirrors the two-worker shape.
- final Helm values render `demo.replicaCount = 2`; `linux-cpu` renders
  `engine.replicaCount = 2` so pod replacement, node drain, and
  anti-affinity checks exercise real HA. `linux-gpu` stays at one engine
  for the single-GPU host shape.
- `test/integration/Spec.hs` adds the LinuxCpu durable-context chaos
  block for frontend pod replacement, coordinator pod replacement,
  engine pod replacement, engine node drain, model-bootstrap
  deduplication across coordinator replacement, and multi-user prompt
  throughput.
- `src/Infernix/Runtime/Pulsar.hs` exposes integration helpers for
  publishing model-bootstrap requests and decoding raw broker
  request/result prompt ids without exposing generated proto modules.
- Containerized compile gate passed:
  `env LAUNCHER_IMAGE=infernix-linux-cpu:local docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm --volume /home/matt/infernix:/workspace infernix cabal build test:infernix-integration`.
- First full `./bootstrap/linux-cpu.sh test` attempt on the recorded validation
  passed the rebuilt-image docs lint, Haskell style suite, Haskell unit
  suite, PureScript build, and web unit suite, then failed before the
  integration scenarios during Harbor publication of the Envoy Gateway
  image. The failure was the outer-container `skopeo copy` fallback
  dialing `127.0.0.1:30002` from inside the launcher container instead
  of the Kind control-plane NodePort address. `src/Infernix/Cluster/PublishImages.hs`
  now rewrites only the `skopeo` destination transport ref to
  `harborApiHost` while preserving the Docker push/rendered Harbor refs;
  the next linux-cpu rerun progressed through publication and into Helm
  readiness.
- The next full `./bootstrap/linux-cpu.sh test` attempt on the recorded validation
  passed docs lint, Haskell style, Haskell unit, PureScript build, web
  unit, and Harbor publication, then stalled in `helm upgrade --wait`
  because the host-mounted containerd registry-hosts file still targeted
  a stale `infernix-linux-gpu-80707-control-plane:30002` mirror. The
  failure exposed that CPU and GPU lanes shared `./.build/kind/registry`
  mount. `src/Infernix/Cluster.hs` now scopes registry-hosts roots by
  runtime mode (`./.build/kind/<runtime-mode>/registry`) and always
  primes every Kind node's mounted `/etc/containerd/certs.d` namespace
  from the launcher-local hosts file after cluster create or reuse;
  `kind/*.yaml`, `README.md`, `kind/README.md`,
  `documents/engineering/docker_policy.md`, and this plan were updated
  to match. The following rebuilt-image rerun verified the repaired
  hosts file on the CPU control-plane and both workers, completed
  `cluster up`, and reached the durable prompt integration assertions.
- The latest full `./bootstrap/linux-cpu.sh test` attempt on
  the recorded validation passed rebuilt-image docs lint, Haskell style, Haskell
  unit, PureScript build, web unit, Harbor publication, final Helm
  readiness, and `cluster up`, then failed in the legacy durable-context
  prompt roundtrip because the first result written for that prompt was
  not `completed`. The code-side fix makes that roundtrip use the newer
  durable context helper that waits for the contexts metadata topic,
  waits one dispatcher-discovery cycle, captures the submitted prompt
  message id, and waits for the result payload for that exact prompt.
  The following rebuilt-image rerun passed the durable prompt roundtrip,
  frontend pod replacement, and coordinator pod replacement checks, then
  failed at `integration-step: engine pod replacement preserves durable
  prompt result` because the exact prompt's conversation result payload
  was present but not `completed` (the old assertion did not print the
  payload). The code-side fix removes a dispatcher race that could publish
  an empty-model-id inference request before the contexts-metadata
  consumer hydrated `ContextModelMap`, and also commits dispatcher reducer
  state only after the outbound inference request publish succeeds. Chaos
  assertions now include the full result payload on any non-`completed`
  status. The rebuilt-image rerun against this dispatcher fix passed
  docs lint, Haskell style, Haskell unit, PureScript build, web unit,
  Harbor publication, final Helm readiness, `cluster up`, the durable
  prompt roundtrip, and reached `integration-step: frontend pod
  replacement preserves durable state`, then failed because the frontend
  post-replacement prompt produced exactly one request and one batch but
  two raw inference results and two conversation results:
  `PromptPipelineCounts {promptPipelineRequestCount = 1,
  promptPipelineBatchCount = 1, promptPipelineResultCount = 2,
  promptPipelineConversationResultCount = 2}` for Pulsar WebSocket
  message id `CNgBEAEwAA==`. The root cause is that
  `parseMessageIdToSequenceId` only understood colon-form Pulsar ids, so
  the WebSocket base64 message id yielded no producer sequence id and
  broker dedup could not collapse duplicate engine/result-bridge
  publishes. The code-side fix now parses Pulsar WebSocket base64
  message ids, keeps the colon parser for compatibility, scopes the
  coordinator batch and engine result producer names by context id, and
  adds unit coverage for the failed id shape. Mounted Linux outer-container
  `cabal build test:infernix-unit test:infernix-integration`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `infernix lint docs` pass. The rebuilt-image `./bootstrap/linux-cpu.sh
  test` rerun then passed Haskell style, Haskell unit, PureScript build,
  web unit tests, full integration, all Sprint 7.14 LinuxCpu chaos and
  throughput scenarios, platform recovery checks, and the routed
  Playwright E2E suite (7/7). Multi-user throughput reported
  `users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12
  p95Seconds=78.95681428909302`. The passing launcher image digest was
  `sha256:a9f1f19aa9bb492c5186a0f6df8f864ee4e0c900c8209f0434ef64cf6cc821a7`.
- The first full `./bootstrap/linux-gpu.sh test` attempt on the recorded validation
  against rebuilt launcher image digest
  `sha256:1eb0863f8c7cbd19b4d87ab25796535ec592d19e965a1a54351d258d31c1c594`
  passed Haskell style, Haskell unit, PureScript build, web unit tests,
  full `infernix-integration`, and six of seven routed Playwright E2E
  specs. The remaining spec,
  `browser per-model smoke matrix exercises every catalog model`, failed
  after timing out waiting for an inbound WebSocket frame after frame index
  `78`. The cluster tore down cleanly; that attempt left Wave C open
  until the Playwright/runtime stall was investigated, fixed, and rerun.
- The recorded-validation Playwright follow-on keeps the per-model browser matrix
  strict on `inferenceResultStatus = completed` but stops using the
  10-second generic WebSocket-frame helper for routed inference results.
  The matrix now waits up to five minutes for each completed conversation
  result, matching the integration-layer first-run inference budget, and
  fails early with the actual result payload if the backend returns
  `failed`. The rebuilt `infernix-linux-gpu:local` launcher image carries
  manifest-list digest
  `sha256:0cbd34f71a3a39b96e17740843b06d08a5c5e55096fd3f42f9f4e565d2a196a5`.
  The fixed full `./bootstrap/linux-gpu.sh test` rerun then passed
  rebuilt-image docs lint, Haskell style, Haskell unit, PureScript build,
  web unit tests, full integration, platform recovery checks, and routed
  Playwright E2E (7/7). The per-model browser matrix completed all 16
  `linux-gpu` catalog rows in 7.9 minutes; the full Playwright file
  reported `7 passed (8.7m)`, and cluster teardown returned cleanly.
- The final recorded-validation `linux-gpu` closure rerun rebuilt the launcher
  after the browser-level frontend pod-replacement fixture landed. The
  rebuilt image carries manifest-list digest
  `sha256:fd951113735f94b613a2fa014088f22e89a4df0b78193cd1ec76d6a44e191689`.
  `infernix lint docs` passed from that image, then
  `./bootstrap/linux-gpu.sh test` passed Haskell style, Haskell unit,
  PureScript build, 71/71 web unit tests, full integration, and routed
  Playwright E2E. The browser artifact/chat flow deleted all
  `infernix-demo` pods, waited for replacements, reconnected,
  resubscribed, and submitted another prompt in 40.4 seconds. The
  per-model browser matrix completed all 16 `linux-gpu` catalog rows in
  2.2 minutes; the full Playwright file reported `7 passed (3.5m)`, and
  cluster teardown returned cleanly.

Execution surfaces:

- `./bootstrap/linux-cpu.sh doctor / build / up / status / test / down /
  status` — portable CPU lane on native Linux for the HA chaos cases.
- `./bootstrap/linux-gpu.sh doctor / build / up / status / test / down /
  status` — CUDA-capable Linux substrate on real NVIDIA hardware.
- `docker compose run --rm infernix infernix test all` — outer-container
  full-suite covering `infernix-integration` + routed Playwright +
  worker validation.
- Phase-specific cohort gates that referenced "CUDA Linux cohort
  validation pending" are closed by the `linux-cpu` and `linux-gpu`
  full-suite passes above.

Wave C closed when `linux-gpu` passed its full-suite gate against the
same worktree state as the `linux-cpu` gate that passed on the recorded validation above.

## Wave D — Closed the recorded validation

Phase status promotion sweep performed after Waves A-C closed:

- Phases 0-6 returned to `Done`; their remaining cohort-validation residual closed by Wave C.
- Phase 7 carried explicit non-cohort residuals into Wave E: real runtime KV-cache validation and
  the wider coordinator transport split. Those residuals closed in Wave E on the recorded
  validation.
- Browser-level frontend pod-kill reconnect coverage closed after the Wave C
  full gates with a mounted-source `linux-gpu` E2E rerun and then the final
  rebuilt-image full `linux-gpu` gate: the browser test deleted all
  `infernix-demo` pods, waited for replacements, reconnected, resubscribed,
  submitted another prompt, and the final full-gate Playwright file reported
  `7 passed (3.5m)`.
- The matching rebuilt-image `linux-cpu` residual full gate passed later on
  the recorded validation against launcher image digest
  `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`.
  The run passed Haskell style, Python checks, Haskell unit, PureScript build,
  71/71 web unit tests, full integration, platform recovery checks, and routed
  Playwright E2E (7/7); the Playwright file reported `7 passed (2.1m)`.
- `DEVELOPMENT_PLAN/README.md`, phase headers, `00-overview.md`, and
  `system-components.md` now record the closed cohort status.

### the recorded validation residual CPU checkpoint

After the Wave D promotion sweep, the matching rebuilt-image `linux-cpu`
launcher build completed against digest
`sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`.
The subsequent `./bootstrap/linux-cpu.sh test` run passed Haskell style,
Python checks, Haskell unit, PureScript build, 71/71 web unit tests, and the
full integration suite, including the LinuxCpu chaos/throughput block. The
throughput matrix reported `users=3 contextsPerUser=2 promptsPerContext=2
totalPrompts=12 p95Seconds=74.05106592178345`. The run was paused at operator
request during the following browser/e2e cluster bootstrap before Playwright
executed, and `./bootstrap/linux-cpu.sh down` removed the partially bootstrapped
CPU Kind cluster.

The resumed rebuilt-image `./bootstrap/linux-cpu.sh test` run on the recorded validation
passed the same residual against digest
`sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`.
Integration included the LinuxCpu chaos/throughput block plus Harbor recovery,
MinIO durability, routed Pulsar recovery, PostgreSQL failover, and PostgreSQL
lifecycle rebinding. The compact throughput matrix reported
`users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12
p95Seconds=76.06613969802856`, and routed Playwright E2E reported
`7 passed (2.1m)`.

This waves document remains as the historical record for the recorded validation
host reset and the staged Apple/CUDA closure batches.

## Wave E: the recorded validation Phase 7 Runtime KV-Cache Closure

Wave E closed Phase 7's non-cohort residuals after the cohort gates had already
validated the durable-context surface. The follow-on split moved production
role orchestration into `Infernix.Runtime.Daemon`, kept Pulsar transport and
runtime loops in `Infernix.Runtime.Pulsar`, and wired a process-local
`EngineKVCache` through the engine daemon, filesystem spool loop, WebSocket
consumer loop, runtime boundary, and native worker harness.

Validation ran from the Linux x86_64 execution context against the mounted
worktree through the Linux CPU outer-container launcher. The passing gates were
`cabal build all`, `cabal test infernix-unit`, `cabal test
infernix-haskell-style`, and `cabal test infernix-integration` after
restaging the generated substrate. Integration covered the coordinator and
engine runtime loops, KV-cache rebuild/reuse path, per-context persistence,
frontend pod replacement, coordinator failover, engine pod replacement, engine
node drain, model bootstrap deduplication, multi-user durable prompt
throughput, and platform recovery checks. The compact throughput matrix
reported `users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12
p95Seconds=67.22616362571716`.

## Wave F: Native arm64 Linux CPU Publication Closure

Wave F closed Phase 3 Sprint 3.12 on the recorded validation. Validation ran on this Apple Silicon machine
through the already selected native arm64 Docker daemon, without cross-architecture emulation,
Docker-context switching, or VM creation. The execution substrate reported `client=darwin/arm64`
and `server=linux/arm64`; the Linux runtime probe reported `uname -m = aarch64` and
`dpkg --print-architecture = arm64`.

Validation used the supported Linux outer-container command:

```bash
docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix test all
```

The passing run proved native `linux/arm64` Harbor publication, warmup-image hydration,
authenticated Harbor-backed final-image preload before final Helm wait, full integration, and
routed Playwright E2E. The rebuilt image was
`infernix-linux-cpu:local@sha256:aae535e31b79b403a3878063371dfc6fd1160baf60a7ce69232c459baebd83e9`.
The test run passed Haskell style, Python quality, Haskell unit/property, PureScript build and
71/71 web unit tests, full `infernix-integration`, and routed Playwright E2E `7 passed (1.7m)`.
Integration evidence included Harbor recovery, MinIO durability, routed Pulsar recovery,
PostgreSQL failover and lifecycle rebinding, Linux engine anti-affinity enforcement, frontend pod
replacement, coordinator failover, engine pod replacement, engine node drain, model-bootstrap
failover/deduplication, and multi-user durable prompt throughput
(`users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12 p95Seconds=71.37436628341675`).

The closure rule is now explicit: native arm64 `linux-cpu` validation may run from an Apple
Silicon host only when it uses an already selected native arm64 Docker daemon and the Linux runtime
itself reports arm64. Cross-architecture emulation, Docker-context creation or switching, and VM
creation remain unsupported.

## Wave G: Phase 7 Auth-UX Quad Closure

Wave G closed the reopened Phase 7 browser-auth surface on the current Apple Silicon host. The
wave covers Sprint 7.19's auth-gated landing, Sprint 7.20's chart-owned `infernix` Keycloak login
theme, Sprint 7.21's signed-in operator console ribbon with JWT-gated `/harbor`, `/pulsar/admin`,
and `/minio/s3`, and Sprint 7.22's account deletion flow. The SPA root remains a single routed
page, but anonymous visitors see only the landing card with `Sign in` and `Create account`, while
the summary grid, Chat / Artifacts shell, and operator console ribbon render only after a Keycloak
JWT is present. The Playwright source adds routed auth-UX smokes that assert the two CTA buttons,
verify `Sign in` lands on the themed Keycloak login form, verify `Create account` lands directly on
the themed registration form through Keycloak's `registrations` endpoint, and probe the JWT policy
on the operator route family.

Wave G closed on the recorded Apple host-native validation. The closure run passed:

- `npm --prefix web run test:unit` (71/71 cases).
- `cabal test infernix-haskell-style`.
- `cabal test infernix-unit`.
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`.
- `./.build/infernix test e2e` with 9/9 routed Playwright tests passing.

## Wave H: 2026-06-09 Current-Host Full Apple Lifecycle Revalidation

Wave H is the current-host full Apple-cohort revalidation. The Apple Silicon machine
described by the validation reset had no built artifacts under `./.build`, so every gate
below was exercised from a clean build root on the current host. Docker was the already
selected native arm64 colima daemon (`server=linux/arm64`, runtime probe `aarch64`); no
cross-architecture emulation, Docker-context creation or switching, or VM creation was used.

Static and build gates (host-native, run directly against the freshly built
`./.build/infernix`):

- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes` — both binaries built clean.
- `infernix lint files`, `infernix lint docs`, `infernix lint chart`, `infernix lint proto`, and `infernix docs check` — all exit zero.
- `infernix test lint` — `infernix-haskell-style` PASS (the `ormolu` + `hlint` style tools were rebuilt into `./.build/haskell-style-tools/bin/` on first run).
- `infernix test unit` — `infernix-unit` PASS plus the web unit suite at 71/71.
- `infernix internal materialize-substrate apple-silicon` staged the demo-enabled
  `./.build/infernix-substrate.dhall` (16-model catalog, `daemonRole = engine`,
  `demo_ui = True`); aggregate `infernix test ...` entrypoints require this staged file,
  while `infernix lint ...` and `infernix docs check` remained substrate-file independent.

Cluster lifecycle gate (Phases 2-3), exercised as an explicit standalone cycle:

- `infernix cluster up` completed with `edgePort: 9090`, `harborPort: 30002`, and Pulsar
  host port `30081`. The dynamic `choosePulsarHttpPort` chooser incremented past a
  VS Code-held `127.0.0.1:30080` to 30081 (the in-cluster pulsar-proxy NodePort stays
  30080; only the operator-host hostPort shifts), confirming the dynamic host-port doctrine
  on this host. All nine platform images published to Harbor as native `linux/arm64`; the
  cluster image carried digest
  `infernix-linux-cpu@sha256:7f341cb1629c1d0af9b72db0fef7b89cc1f13d2bd02afe9be1daeed5e7f18454`.
- `infernix cluster status` while up reported `clusterPresent: True`,
  `lifecyclePhase: steady-state`, 77 pods across 2 nodes, `storageClass: infernix-manual`,
  `storageHealth: 26 chart-owned claim roots prepared`,
  `publicationInferenceDispatchMode: pulsar-bridge-to-host-daemon`, and the full Envoy
  Gateway route set (`/`, `/api`, `/api/objects`, `/auth`, `/harbor`, `/harbor/api`,
  `/minio/s3`, `/pulsar/admin`, `/pulsar/ws`, `/ws`).
- `infernix cluster down` ran the retained-state replay (MinIO, Harbor jobservice, Pulsar
  bookie journal/ledger, and ZooKeeper claims copied from the worker back to the host) and
  preserved durable state under `./.data`, then deleted the Kind cluster. Post-teardown
  `infernix cluster status` reported `clusterPresent: False`, `lifecycleStatus: idle`, and
  `lifecyclePhase: cluster-absent` with zero nodes and pods and no leftover containers.

Routed validation gates (Phases 4-7), each managing its own cluster lifecycle and spawning
the on-host engine daemon automatically:

- `infernix test integration` — PASS (`infernix-integration: PASS`, 1 of 1 test cases).
  Apple-lane scenarios: per-model inference over the 16-row catalog, durable Pulsar topic
  families, route probes, service runtime loop, cache lifecycle, cluster-state reload, and the
  historical `apple engine.lock` host-singleton enforcement case. That singleton case is
  superseded by the Sprint 7.24 engine-pool routing target. The multi-user throughput and
  pod-replacement/node-drain chaos block remains `runtimeMode == LinuxCpu`-gated and is the CUDA
  Linux cohort's scope.
- `infernix test e2e` — 9/9 routed Playwright specs PASS (1.8m): routed edge/SPA, Keycloak
  self-registration, pre-auth landing entry points, auth lifecycle (logout/re-login/token
  refresh), routed WebSocket JWT validation, cross-user object-grant isolation, self-service
  account deletion reaping demo state before the Keycloak account action, artifact upload
  with preview/media/PDF/download-only grants, and the per-model browser smoke matrix across
  every catalog model.
- `infernix test all` — the aggregate gate ran lint, `infernix-unit` plus web 71/71,
  `infernix-integration`, and routed Playwright e2e end to end on the same worktree.

At the time of Wave H the CUDA Linux cohort hardware was unavailable, so the
`linux-cpu` and `linux-gpu` gates were not part of Wave H and retain their prior recorded
closure; Wave H re-confirmed the Apple cohort only. The current workspace is the native CUDA Linux
host (Ubuntu 24.04 amd64, NVIDIA RTX 5090, Docker `linux/x86_64` with the `nvidia` runtime), and
the scheduled Wave I/J Linux probes closed here on 2026-06-20 while the Apple evidence remains the
recorded Apple-host attestation.

## Wave I: Real Per-Family Inference and Engine Payload Attestations (Closed)

Wave I records the real per-family inference contract and engine-payload attestations for the
runtime/output phases. Phase 1 Sprint 1.14's headless Apple Metal/Core ML materialization lane is
closed under Section Q. Phase 4 and Phase 6 closed their selected accelerator plus `linux-cpu`
real-output gates on 2026-06-20.

### Closure Evidence — 2026-06-20 CUDA Linux

- `./bootstrap/linux-gpu.sh test` passed the full CUDA Linux lane: Haskell style, Haskell unit,
  web unit (`71/71`), integration, and routed Playwright `9 passed`, including the full per-model
  browser matrix across all 16 `linux-gpu` catalog rows.
- The GPU run reached framework-specific and native rows after the vLLM cleanup/session fixes:
  vLLM memory release lowers per-row GPU pressure, adapter backend log tails preserve failure
  diagnostics, and the browser matrix refreshes/re-subscribes before upload rows.
- `./bootstrap/linux-cpu.sh build` rebuilt `infernix-linux-cpu:local`, and
  `./bootstrap/linux-cpu.sh test` passed the full rebuilt-image CPU lane: Haskell style, Haskell
  unit, web unit (`71/71`), integration, and routed Playwright `9 passed`, including the CPU
  per-model browser matrix.

### Stage 1 — Code-side closure (single machine, natural order, no machine switch)

> **Stage 1 status: closed and revalidated across the active hosts.** The reopened sprints' code-side
> closure (Phase 4's
> `ResultFamily` + object-ref plumbing, real native-binary + Python-adapter dispatch, `buildPayload`
> family routing, fail-fast-on-unsupported, plus Sprint 4.18's engine-artifact manifests and matrix
> reconciliation; Phase 6's `ResultFamily`-dispatched assertions, Playwright artifact rendering,
> code-side-closed matrix drift lint, and headless Apple validation gates) passed the
> machine-independent gate set on the host that owns the active work. The prior CUDA Linux
> real-output code-side closure remains useful evidence; the 2026-06-16 Apple refresh adds
> host-native build, `apple-silicon` substrate materialization, Metal/Core ML engine manifest
> materialization, unit, lint, docs, focused `lint files/docs/proto/chart`, Metal bridge smoke
> evidence, installed `coreml-native` runtime-load smoke evidence, focused e2e, and aggregate
> `test all` against validation-wrapper payloads. Those Apple materialization facts are Phase 1
> closure evidence; the selected Phase 4/6 real-output gate closed on `linux-gpu` plus `linux-cpu`
> on 2026-06-20.

The machine-independent implementation for the reopened sprints landed in natural phase order
(Phase 4 -> Phase 6) on the active hosts and passed the normal machine-independent gates
(`cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, focused
`infernix lint` and `docs check`, the web unit suite, and `poetry run check-code`). Intrinsically
hardware-bound real-engine integration and E2E assertions closed in Stage 2.

### Stage 2 — Per-accelerator sign-off

Stage 2 is closed. The phase's chosen accelerator plus `linux-cpu` full-suite evidence is recorded
above for 2026-06-20; the other accelerator is not a blocker for that phase's `Done` state.

> **Present-host note.** The present development host is native Ubuntu 24.04 amd64 with an NVIDIA
> GeForce RTX 5090, driver `570.211.01`, Docker `linux/x86_64`, and the `nvidia` runtime available.
> The Apple host-native half of Wave I was recorded on the Apple host, and the 2026-06-16 refresh
> proved the generated Metal runtime
> bridge smoke (`Metal runtime probe passed on Apple M1 Max`) plus the installed `coreml-native`
> runtime-load smoke (`Core ML runtime probe passed`). The Apple transformers
> framework path now completes `llm-qwen25-safetensors` after the per-engine Apple venv and
> Hugging Face snapshot bootstrap fixes. The next completed integration run exposed the missing
> `llama-cpp-cli/bin/llama-cli` root for `llm-tinyllama-gguf`; current source materializes
> smoke-capable Apple native validation wrappers for `llama-cpp-cli`, `whisper-cpp-cli`,
> `ctranslate2-native`, `mlx-native`, `onnx-runtime-native`, and `jvm-native`, plus the
> `coreml-native` runtime smoke. The latest Apple integration rerun passed after rebuilding the
> changed repo-owned image once, then reusing the stamped `infernix-linux-cpu:local` image on later
> edge-port validation cluster cycles. It completed the active Apple model catalog through the host
> engine daemon, cache lifecycle, service runtime loop, durable Pulsar topic families, pinned Apple
> host-engine `Exclusive` duplicate-consumer rejection through an isolated
> `infernix service --config` file, same-machine Apple `Shared` subscription coexistence through
> real Pulsar admin stats, Apple production `demo_ui = false` assertions, and edge-port conflict
> rediscovery. The follow-up plain-progress probe for the earlier long Docker interval showed
> active Cabal dependency compilation, image export, Harbor push, and Helm/Pulsar readiness waits,
> not a Docker daemon deadlock. Current source stamps repo-owned cluster images with a source
> fingerprint, permits host-native Apple reuse only when the fingerprint/runtime/architecture and
> pushable manifest shape match, and splits the Dockerfile dependency layer so repeated source-only
> edits do not redownload Cabal/NPM/Poetry dependencies.
> A following Apple aggregate `./.build/infernix test all` attempt reached Playwright and failed
> because `audio-demucs-htdemucs` received an empty input-object reference. Current source fixes
> that dispatch path by preserving prompt upload refs in the single-flight envelope and passing an
> `inputObjectRef` only for catalog families that consume uploaded objects; the browser matrix now
> uploads tiny input fixtures for those rows. The focused Apple `./.build/infernix test e2e` rerun
> then passed 9/9 against cluster image digest
> `sha256-02a55163c0c5f6ae640cb768a5e67c196c56ad921cddec926e3a2748cb220e29`, including the full
> active Apple catalog. A later aggregate rerun validated lint/unit and the first Apple integration
> cluster cycle, then exposed a lifecycle gap in the edge-port rediscovery cycle: Apple warmup did
> not stream host-cached warmup images into the new Kind worker, so MinIO and pgbouncer fell through
> to Docker Hub and hit unauthenticated `429 Too Many Requests`. Current source removes the
> Apple-only skip and preloads the same narrow warmup image set on every supported Kind lane. The
> next focused Apple `./.build/infernix test e2e` rerun reached the Playwright matrix and completed
> all 9 tests against rebuilt cluster image digest
> `sha256-ed34da86992bb1a4d285f00feb77051d12eb4fa594b7bb34ed73561a027b1a71`, including
> `llm-qwen25-safetensors` and every active Apple catalog row. The aggregate rerun immediately
> before that focused pass had exposed a separate cold-start envelope bug: the engine waited only
> 60 seconds for model-bootstrap readiness after publishing a bootstrap request, which is too short
> for a real Hugging Face snapshot. Current source names that bound as a 900-second backend wait and
> aligns the browser result wait with the same envelope. The subsequent full Apple
> `./.build/infernix test all` aggregate passed lint, unit (Haskell plus web 71/71), integration,
> and 9/9 routed Playwright against rebuilt cluster image digest
> `sha256-f4a30f4e177206b64ce5a0d3abea8d72a8bdbe637148530e1619bdf5ce8ae7c3`; the aggregate matrix
> completed Qwen, object-input audio/tool rows, and every active Apple catalog row, then replayed
> retained state and deleted the Kind cluster cleanly. These facts close the Phase 1 headless
> materialization foundation. The selected Wave I gate for Phase 4/6 then closed on 2026-06-20
> through `./bootstrap/linux-gpu.sh test` plus rebuilt-image `./bootstrap/linux-cpu.sh test`;
> Linux native payload placeholder replacement itself is strict-smoke validated in the CUDA Linux
> image and exercised through the routed service path.

**Apple cohort.** Run the headless Metal runtime bridge probe; materialize an allowlisted
Metal/Core ML or native-runner artifact with a typed engine manifest into
`./.data/engines/<adapterId>/`; prove no Tart invocation, keychain unlock, offline `metal`
compiler, host Xcode UI flow, or request-time toolchain install is required; then run
`infernix test integration`, `infernix test e2e`, and `infernix test all` asserting the per-family
real-output result contract for every row in the `apple-silicon` catalog column (LLM continuation,
whisper transcript, CTranslate2 CPU transcript, PyTorch-MPS source-separation stems,
basic-pitch Core ML/ONNX MIDI, residual MT3/Omnizart cells as named residuals, SDXL MPS artifacts,
bark MPS audio, and Audiveris MusicXML).

**CUDA Linux cohort.** Re-validate the `linux-cpu` and `linux-gpu` catalog columns' per-family real
inference (vLLM, `llama.cpp`, CTranslate2, PyTorch CPU/CUDA, TensorFlow, ONNX Runtime, JAX,
Diffusers, Audiveris) minus the Apple-Core-ML-only rows, through
`docker compose run --rm infernix infernix test all`.

> **CUDA Linux cohort — prior in-progress findings (RTX 5090 / driver 570 / CUDA 12.8).**
> The bleeding-edge linchpin is **proven**: `torch 2.7.1+cu128` reports `cuda available: True` on the
> Blackwell GPU (capability `(12,0)` / sm_120), and a real Qwen2.5-1.5B generation runs on the GPU
> through the transformers adapter's exact `AutoModelForCausalLM` + `generate` path. The Sprint 4.16
> per-engine isolated framework-venv mechanism is built and validated (transformers engine: real
> `--with cuda` install + worker resolution + machine-independent gate set green). Enabling work
still required before the full `infernix test all` per-family run closes on this host: (1) bake
> every engine's `--with cuda` venv into the linux-gpu image (large, multi-hour); (2) the **Linux
> native-engine binary lane** — llama.cpp / whisper.cpp / ONNX Runtime / CTranslate2 binaries under
> image-owned `/opt/infernix/engines/<id>/bin/` roots; (3) real model-weight
> provisioning into `infernix-models`; (4) the cluster bring-up and per-family assertions.
>
> **Image-build result (`infernix-linux-gpu:local`, 121 GB).** The build succeeded with **5 of 6**
> framework engine venvs resolving their CUDA stacks on Blackwell: `transformers`, `vllm`, `pytorch`,
> `jax`, `diffusers` all OK; `tensorflow` (Basic Pitch audio-to-MIDI + Omnizart music) **FAILED** to
> resolve — a named cohort residual. A per-engine venv inside the built image reports
> `torch.cuda.is_available() == True` on the RTX 5090 with `--gpus all`, so the deployable image's
> engines reach the GPU. **Practicality finding:** baking 5 multi-GB CUDA framework venvs into one
> image yields a 121 GB monolith that is impractical to push through Harbor and load into Kind for
> the routed cluster cohort run; the cluster path likely needs a per-engine-image (or shared-base +
> framework-layer) redesign before `infernix test all` is feasible on the cluster. Direct
> `docker run --gpus all` per-family inference works against the image today.
> **Named cohort residuals (incompatible with the Python 3.12 / CUDA 12.8 substrate):** the Basic
> Pitch TensorFlow row (published package pins TensorFlow `<2.15.1`), the Omnizart (TF1-era) music
> row, and the MT3 (unmaintained JAX/T5X) music row do not resolve and need maintained equivalents
> or the ONNX/Core ML fallback lanes before their per-family assertions can pass. The base image was aligned to
> `nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04` to match the 570 driver (a CUDA-13 base needs driver
> >= 580).
>
> **Sprint 4.17 per-engine-image split — code-side implementation complete.** The monolith was
> split: the control-plane / coordinator image (`infernix-linux-gpu:local`, `docker/Dockerfile`) is now
> **22.4 GB** (down from 121 GB — no framework venvs), and per-engine images build from
> `docker/engine.Dockerfile` (CUDA-runtime base + the control-plane binary/python + one engine's
> `--with cuda` venv). The `transformers` per-engine image builds and, with `--gpus all`, reports
> `torch 2.7.1+cu128`, `cuda available: True`, and imports `adapters.transformers_python`; `vllm` is
> pinned to `0.11.0`. A June 11, 2026 routed-cluster validation run built the `vllm` and `pytorch`
> per-engine images and then exposed the TensorFlow/Basic Pitch dependency conflict, so the
> TensorFlow engine image now owns only the maintained TensorFlow CUDA stack while Basic Pitch
> TensorFlow is tracked as a named residual. A follow-up June 11, 2026 `./bootstrap/linux-gpu.sh test`
> run passed Haskell style, Haskell unit, and web unit gates before failing in `bootstrap-harbor`
> because Linux outer-container bind-mounted Kind paths skipped the Patroni claim-root scrub and
> replayed stale Harbor PostgreSQL data against a regenerated `infernix-harbor-db-user` secret. The
> lifecycle now scrubs non-retained Patroni roots before claim directory creation and after
> retained-state sync on all lanes. The next routed-cluster run built, published, and verified the
> `diffusers`, `jax`, `pytorch`, `tensorflow`, and `vllm` per-engine images plus the slim control-plane
> image, then exposed the single-GPU scheduling gap: the generated final chart tried to run the base
> engine and every per-engine Deployment concurrently, so the extra pods were rejected with
> `Insufficient nvidia.com/gpu`. The lifecycle values now keep per-engine replicas at zero on the
> repo-owned `linux-gpu` lane, and integration/Playwright scale exactly one per-engine deployment
> during per-model validation. The code-side wiring now includes `enginePools` / `engineMembers`,
> derived pool/model batch topics, `infernix service --engine-name`, per-engine chart
> Deployments/PDBs, lifecycle per-engine image builds, and Harbor per-engine overlays. The first governed rerun after the single-GPU fix
> passed Haskell style, Haskell unit, and web unit gates, then failed during Harbor publication of
> `infernix-engine-diffusers-linux-gpu` with a registry `blob ... not found` error after the Harbor
> PostgreSQL scrub succeeded; this points at retained `harbor-registry` MinIO bucket contents getting
> out of sync with the fresh Harbor database. The lifecycle then reset only the Harbor registry
> bucket mirror before cluster startup, preserving `infernix-models`,
> `infernix-engine-artifacts`, and `infernix-demo-objects`.
> The next governed rerun again passed Haskell style, Haskell unit, and web unit gates, then failed
> during the same image publication with `blob sha256:05ec76e31584... not found`. The remaining
> issue was stale MinIO `.minio.sys/multipart` registry-upload metadata plus the Linux host-bind
> teardown path skipping the non-retained scrub. Lifecycle cleanup now covers the Harbor registry
> bucket, registry bucket metadata, MinIO multipart/tmp working sets, and non-retained Patroni roots
> on startup and `cluster down`. The following governed rerun again passed style/unit/web gates and
> proved teardown leaves no stale registry/multipart/tmp directories, but the first diffusers image
> push still failed with `blob sha256:4614b301... not found`. Investigation found the reused
> repo-owned images were Docker 29 / BuildKit OCI indexes with attestation metadata; bootstrap and
> lifecycle builds now pass `--provenance=false`, and lifecycle reuse rejects local image-index
> descriptors. The next governed rerun rebuilt all five per-engine images as plain Docker manifests
> and again passed style/unit/web gates, but Harbor publication still failed on
> `infernix-engine-diffusers-linux-gpu` after 8 retries with
> `blob sha256:05ec76e31584... not found`. Investigation then found stale Harbor Redis
> repository blob-cache keys for those missing digests; lifecycle cleanup now removes the Harbor
> Redis claim root with the rebuildable registry bucket/cache state. The next governed
> `./bootstrap/linux-gpu.sh test` rerun passed Haskell style, Haskell unit, and web unit gates,
> push/pull-verified all five per-engine images plus the slim control-plane image through Harbor,
> push/pull-verified the chart upstream image set, deployed the final chart, and completed
> `cluster up`. That run then failed in per-model inference at `audio-basic-pitch-onnx`: the
> `AudioToMidi` result-family assertion required an `infernix-demo-objects/*.mid` object reference,
> but the native ONNX Runtime lane produced a failed/inline result. Follow-up code-side validation
> compiles the integration target and passes Haskell style after adding canonical uploaded input
> objects for audio/image input rows and asserting `status = completed` before result-family shape.
> The governed `./bootstrap/linux-gpu.sh build` after that follow-up passes and produces the plain
> Docker manifest launcher image
> `sha256:2d6cfd42ca59ee7fbd9669a8c32738ed0ba44ef09706b469d12c8803b520e030`. The latest full
> governed rerun again passed style/unit/web gates, push/pull-verified all five per-engine images
> plus the control-plane and chart upstream images through Harbor, completed final chart rollout and
> route probes, then failed at `llm-tinyllama-gguf`: the Linux base engine pod had no
> `/workspace/.data/engines/llama-cpp-cli/bin/llama-cli`. Current source closes the missing-root
> surface by baking smoke-validated `/opt/infernix/engines/<adapterId>/bin/...` roots through
> `infernix internal materialize-linux-native-engines`; the current CUDA Linux cycle then replaced
> those runner-contract placeholders with runtime-backed wrappers over image-baked native payloads.
> The first remaining CUDA Linux blocker is a full routed rerun that exercises the native rows
> through live MinIO-backed model/input hydration. Current linux-gpu validation also includes the
> 2026-06-15 governed
> `./bootstrap/linux-gpu.sh build`, baked-image `infernix test unit`, `infernix test lint`, focused
> `infernix lint files/docs/proto/chart`, `infernix docs check`, and
> `infernix internal materialize-linux-native-engines`, plus direct baked-runner checks for LLM
> inline text, image `.png` object refs, and Basic Pitch `.mid` object refs. That evidence proves
> the worker model-cache argument plumbing and image-owned native fallback; the current
> follow-up also executes the generated `llama-cpp-cli` runner on missing-cache and ready-cache
> paths, proving exit 75 before `<model-cache-root>/<model-id>/.ready` exists. Mounted
> current-source linux-gpu validation passes `infernix test unit`, `infernix test lint`, focused
> `infernix lint files/docs/proto/chart`, `infernix docs check`, and
> `infernix internal materialize-linux-native-engines`. The current pass also validated the
> `--output-dir` marker path by producing
> `infernix-native-artifact-file:/tmp/infernix-native-output-check/audio-basic-pitch-onnx.mid` and
> verifying the file existed, which proves the local marker/upload wiring. The later 2026-06-20
> full `linux-gpu` plus `linux-cpu` reruns supplied the routed native-output service-path evidence.

**2026-06-16 CUDA Linux cohort host (native amd64 Ubuntu 24.04, NVIDIA RTX 5090, driver 570 /
CUDA 12.8) — real per-family GPU output progress and two code-side fixes.** A governed
`./bootstrap/linux-gpu.sh build` rebuilt the slim control-plane image (`infernix-linux-gpu:local`,
22.2 GB), and `./bootstrap/linux-gpu.sh test` built the three framework per-engine images
(`vllm`, `pytorch`, `diffusers`) from `docker/engine.Dockerfile`, push/pull-verified every per-engine
and chart image through Harbor, completed final chart rollout, and brought the routed `linux-gpu`
cluster up. Integration then passed config decode, route probes, the native runner rows,
and reached the per-engine GPU deployments, where the first real diffusion row `image-sdxl-turbo`
failed with `service daemon did not publish a result`. Root-causing surfaced two real defects in the
machine-independent code, now fixed:

- **GPU artifact adapters never moved models to the accelerator.** `python/adapters/diffusers_python.py`
  (`DiffusionPipeline.from_pretrained(weights_dir)`) and `python/adapters/pytorch_python.py` (Bark
  `BarkModel.from_pretrained(...)` and Demucs `apply_model(...)`) loaded in fp32 on CPU, while only
  `transformers_python.py` selected `cuda`/`mps` and called `model.to(device)`. On the GPU lane this
  ran SDXL/Bark/Demucs on CPU, which cannot finish inside the routed result-publish budget. All three
  adapters now mirror the transformers `_preferred_torch_device` pattern: half precision plus
  `.to(device)` on `cuda`/`mps`, validated by `poetry run check-code` (ruff/mypy/black) keeping the
  lazy-import machine-independent invariant. A direct `docker run --gpus all` probe against the
  diffusers engine image confirmed the fixed path on Blackwell: SDXL-Turbo loaded in fp16 **on CUDA**
  in 5.7 s (`torch 2.11.0+cu128`, `cuda available: True`, `NVIDIA GeForce RTX 5090`).
- **The integration result-wait was shorter than the cold model-bootstrap envelope.** The same probe
  measured the SDXL-Turbo Hugging Face snapshot fetch at ~14.5 min on this host, but
  `test/integration/Spec.hs` `waitForPublishedResult` waited only ~5 min (3000 × 100 ms) — a budget
  whose own comment accounted only for adapter bootstrap plus the Pulsar two-hop handoff, never a
  multi-GB weight download. The wait is now a 25-minute wall-clock deadline that comfortably exceeds
  the engine's own 900 s bootstrap envelope plus the MinIO pull and on-GPU inference, while a
  genuinely failed bootstrap still fast-fails on the engine's published failed-status result. The
  change compiles and links clean under warnings-as-errors.

Both fixes were baked into a fresh `linux-gpu` launcher rebuild and the routed
`./bootstrap/linux-gpu.sh test` re-run reached real GPU inference. **Milestone: the diffusers
`image-sdxl-turbo` row produced real per-family GPU output and the assertion `inference completes
for image-sdxl-turbo` passed** — the first real diffusion artifact generated on the RTX 5090 through
the routed coordinator → engine-pool → result path, confirming the adapter device-placement fix and
the cold-bootstrap wait fix end to end. (The fixed adapters were delivered into the per-engine
images with a fast COPY-overlay of the two `.py` files, because the lifecycle's per-engine image
reuse check keys on Harbor-push manifest shape and did not detect the adapter source change on its
own — a follow-on cleanup item: the per-engine reuse predicate should also compare the cluster
source fingerprint.)

The same run then failed at the next diffusers row `video-wan21-t2v`: `DiffusionPipeline.from_pretrained`
reported `no file named model_index.json` because the catalog pointed at the raw-weights repo
`Wan-AI/Wan2.1-T2V-1.3B` rather than the diffusers-format `Wan-AI/Wan2.1-T2V-1.3B-Diffusers` variant
(which does carry `model_index.json`). The catalog URL in `src/Infernix/Models.hs` and the README
matrix row are corrected to the `-Diffusers` repo. A direct `docker run --gpus all` probe of the
fixed path then proved the whole Wan2.1 generation end to end on the RTX 5090: the `-Diffusers`
snapshot downloaded, `DiffusionPipeline.from_pretrained` resolved `WanPipeline` in fp16 on CUDA, the
generic `pipeline(prompt)` adapter call generated frames in 168 s, and `export_to_video` wrote a
401 KB mp4 (`WAN_EXIT=0`) — so no Wan-specific adapter arguments are needed.

The follow-on routed rerun then surfaced a third defect, a **resource/config** one: the diffusers
engine pods were `Evicted` (exit 137) with `Usage of EmptyDir volume "model-cache" exceeds the limit
"32Gi"`. The diffusers engine caches both the SDXL repo and the large Wan2.1 `-Diffusers` repo (which
bundles the multi-GB umt5-xxl text encoder) in one `/model-cache` `emptyDir`; together they overflow
the 32 GiB ceiling and kubelet evicts the pod mid-bootstrap (the Wan inference itself works, as the
probe showed). `chart/values.yaml` now raises `engine.modelCache.sizeLimit` to `64Gi` and the matched
`clusterConfig.engine.modelCacheQuotaBytes` to `68719476736`. The 64 GiB headroom resolved the
eviction, after which a fourth issue surfaced — a retained-state one: the lazy model bootstrap keys
its MinIO `.ready` sentinel on the model id, not on the repo identity, so when the catalog repo for
`video-wan21-t2v` changed from the raw-weights repo to the `-Diffusers` variant, the bootstrap saw
the stale `.ready` over the old original-format snapshot (no `model_index.json`) and skipped
re-downloading. Clearing the stale `infernix-models/video-wan21-t2v` retained state forces a fresh
`-Diffusers` fetch; a follow-on robustness item is to key the bootstrap `.ready` sentinel on repo
identity/content so a catalog repo change busts the cache automatically.

With the cleared state, the rerun then hit a fifth issue and the controlling constraint for this row:
`Timed out waiting for model bootstrap readiness for video-wan21-t2v`. The routed lazy bootstrap
(coordinator Hugging Face download → MinIO upload → engine pull) of the large Wan2.1 `-Diffusers`
snapshot exceeds the engine's `modelBootstrapReadyWaitMaxSeconds = 900` envelope
(`src/Infernix/Runtime/Pulsar.hs`) on this host's HF throughput — even though the model itself runs
(the direct probe generated a valid mp4 in 168 s). **`video-wan21-t2v` is therefore recorded as a
named CUDA Linux residual for the routed lazy-bootstrap path:** the real-output capability is proven,
but routed closure needs either a larger coupled bootstrap/result-wait envelope (raise
`modelBootstrapReadyWaitMaxSeconds` above ~30 min and the integration `waitForPublishedResult`
deadline above it) or pre-staged Wan weights, on a faster link than this host provides. The catalog
already flags Wan as an Apple-MPS residual; this extends the residual to the CUDA routed path for the
same large-model reason. The diffusers **image** family (`image-sdxl-turbo`) remains fully proven
routed; the PyTorch Bark/Demucs and vLLM rows sit behind the Wan blocker in per-engine order and have
not yet been routed-validated this cycle.

**Follow-on fix landed for the Wan bootstrap envelope.** Root-causing the repeated Wan failures
showed the controlling defect was the engine-side bootstrap envelope, not the model: the coordinator
`snapshot_download` has no hard wall, but the engine gave up after
`modelBootstrapReadyWaitMaxSeconds = 900`, and when the cluster then tore down the partial download
was left under a premature `.ready` sentinel (missing `model_index.json`), which the next run trusted
and served incomplete. `src/Infernix/Runtime/Pulsar.hs` now raises that engine envelope to `3600`
seconds and `test/integration/Spec.hs` raises the `waitForPublishedResult` deadline to `4200`
seconds (above the envelope plus the MinIO pull and on-GPU inference), so a fresh large-model
download completes fully before the engine gives up and a genuine failure still surfaces as a
failed-status result. Both compile clean under warnings-as-errors. A follow-on robustness item
remains: the bootstrap should only write `.ready` after a verified-complete snapshot (and key it on
repo identity), so an interrupted download cannot leave a `.ready` over partial weights.

Even with the 3600 s envelope and a cleared cache, the routed Wan bootstrap still timed out: the
coordinator HF → MinIO download of the ~27 GB `-Diffusers` snapshot exceeded 60 minutes. The cause
is **not** Hugging Face throttling — a direct host-side `snapshot_download` of the same repo
completed in 440 s (~62 MB/s, full 27 GB). The gap is **in-cluster egress**: the coordinator runs the
download inside a Kind pod, whose nested-Docker network path to the internet is far slower than the
host's, compounded by the four-replica MinIO erasure write. The model's real output is proven (probe
mp4) and the engine/integration envelopes are now sized for large models; the remaining gap is purely
getting 27 GB of weights into `infernix-models` without the slow in-cluster fetch.

The supported way to close this is **pre-staging**: seed the `infernix-models/video-wan21-t2v/`
objects (plus the `.ready` sentinel) directly into MinIO from the fast host download, so the engine
streams them cluster-internally instead of the coordinator pulling them over the slow Kind-pod path.
That seed-and-replay path was exercised on this host (host `snapshot_download` of the 27 GB
`-Diffusers` repo in 440 s → boto3 upload to the cluster `infernix-minio` service → retained-state
replay → routed `test`) and **closed the Wan row: the diffusers engine cleared both `image-sdxl-turbo`
and `video-wan21-t2v` routed, so the full diffusers image+video family is now proven real-output on
the RTX 5090.** The seeding bypassed the slow in-cluster fetch entirely — the engine streamed the
27 GB from MinIO cluster-internally.

That run then advanced to the PyTorch engine and timed out on `audio-bark-small`. **In-cluster
diagnosis on a live cluster pinned the cause to a transient external rate-limit, not a code or infra
defect.** From the running coordinator pod: direct file egress is healthy (an 80 MB Hugging Face
object pulled at 7.8 MB/s — Bark's ~5 GB would land in ~11 min, far under the 3600 s envelope), and
MTU is a uniform 1500 across host/docker0/kind. But the model bootstrap's `snapshot_download` failed
with `LocalEntryNotFoundError`, and a direct probe of `https://huggingface.co/api/models/...` from
the pod returned **HTTP 429** — Hugging Face is rate-limiting this host's IP after the night's heavy
repeated model fetches. The metadata/API path is throttled while the CDN file path is not, so every
in-cluster `snapshot_download` errors; this is also the most likely real cause of the earlier Wan
routed "timeout" (the coordinator erroring on the 429, not a slow download), which the direct MinIO
seed bypassed. The rate-limit is self-inflicted and transient (per-IP, clears over time).

Net state of the GPU integration this cycle: the diffusers engine (SDXL + Wan) is fully
routed-validated; the runtime, adapters, lifecycle, 64 GiB cache, bootstrap envelopes, and pod
network are all proven sound.

**Root cause and fix for the remaining-row block (definitive).** A focused in-image reproduction
isolated the 429 to Hugging Face's **Xet** large-file transport: `huggingface_hub` ships the optional
`hf_xet` client, which routes weight downloads through the Hub's `xet-read-token` API, and HF
rate-limits that endpoint hard per source IP (`429 ... We had to rate limit your IP ... pass a
HF_TOKEN`) under a busy cohort run — while the ordinary `resolve` -> CDN HTTP path stays healthy
(measured 7.8 MB/s from a pod, MTU uniform 1500). Two fixes land, both doctrine-compliant (no env
var): `docker/Dockerfile` removes `hf_xet` from the coordinator's base venv so its
`snapshot_download` falls back to the un-throttled HTTP path, and `adapters/model_bootstrap.py` wraps
the download in retry-with-backoff for any residual transient error. With `hf_xet` disabled and the
Wave I adapter device fix, a direct GPU reproduction downloaded `suno/bark-small` cleanly and
generated real audio (`GENERATE_OK`), confirming the PyTorch Bark model path end to end. The routed
rerun with the fix baked confirmed the unblock: the coordinator downloaded Bark without a 429 (the
xet-429 blocker is resolved) and the diffusers engine cleared again. The first PyTorch row then
exposed a separate, narrower defect: the engine failed to load Bark from the MinIO-round-tripped
`/model-cache` with `stat: path should be string ... not NoneType`. The live engine-pod traceback
localized it to `AutoProcessor.from_pretrained` -> Bark's `BertTokenizer.__init__` ->
`os.path.isfile(vocab_file=None)`: the cached snapshot was **a stale partial** — config, weights, and
all 502 speaker-embedding files were present, but every tokenizer file (`vocab.txt`,
`tokenizer.json`, `tokenizer_config.json`, `special_tokens_map.json`) was missing, with `.ready`
already set (a historical artifact from a pre-fix run; the bootstrap's `_sentinel_exists`
early-return then propagated it forward). It was not a defect in the current download/round-trip
code: clearing the stale prefix and re-running the **real coordinator bootstrap** (`hf_xet`-removed
build, with the retry recovering a transient CDN read-timeout) re-uploaded the complete snapshot
including the tokenizer files (`HAS_VOCAB=True`), and the in-pod adapter then loaded Bark from the
real MinIO `/model-cache` and generated a 1.44 MB WAV (`BARK_OK`). The integration rerun confirmed it
end to end: the **diffusers (SDXL + Wan) and PyTorch (Bark + Demucs + Open-Unmix) rows both passed
routed**.

That rerun then exposed the **vLLM Qwen** row failing with `Unable to decode worker response:
WorkerResponse: Unknown wire type 7`. The diagnosis took several layers and ended up uncovering a
*real engine defect that the error had been masking*:

1. **Stdio framing.** The adapter harness transmits the serialized `WorkerResponse` protobuf over
   the adapter's **stdout** (the Haskell worker reads the frame from fd 1) and captures the adapter's
   **stderr** on a pipe it does not drain until the response arrives. vLLM logs copiously to *both*
   fds while constructing the engine, so leaving either on its pipe either corrupts the frame
   (`Unknown wire type`) or, once a 64 KB pipe buffer fills, deadlocks the engine on
   `anon_pipe_write` mid-init (confirmed via `/proc/<pid>/wchan` + matching `fd1=fd2=pipe`). The fix
   in `python/adapters/common.py` (`_isolate_protobuf_stdout()`, called after `_decode_request` in
   both adapter seams) duplicates the real stdout to a private fd that `_write_response` targets,
   then redirects **both fd 1 and fd 2 to `/dev/null`** so no backend chatter — Python or native
   C/CUDA — can reach either pipe. Doctrine-compliant (no `VLLM_LOGGING_LEVEL` env toggle); enforced
   structurally at the fd boundary. (Two earlier iterations — discard stdout only, then redirect
   stdout→stderr — were rejected: the first left stderr corrupting, the second moved the deadlock
   onto the undrained stderr pipe.)
2. **Engine core init (the masked defect).** With the frame clean, the response decoded to an
   *error* `WorkerResponse`: `RuntimeError: Engine core initialization failed` →
   `torch._inductor InductorError: Failed to find C compiler`. vLLM V1's default path runs
   `torch.compile` (inductor + triton), which JIT-compiles kernels through a **host C compiler the
   framework-free engine image deliberately does not ship**, so the engine core never initialized —
   and the original `wire type 7` was *that* error response getting shredded by the stdout pollution.
   Fixed in `python/adapters/vllm_python.py` with `LLM(..., enforce_eager=True)`, which runs the same
   real GPU inference without the compile/toolchain dependency.

Both fixes validated **end-to-end in-pod** against the live cluster: the vLLM adapter, driven through
a worker-faithful boundary (request on stdin, stdout drained, **stderr left undrained**), loaded
`llm-qwen25-safetensors` and returned a clean `WorkerResponse` with real text
(`"...Paris and the largest city is London..."`, empty `error_code`). `check-code` clean.

Two infrastructure blockers were also resolved along the way, both environmental rather than code
defects: (a) the Harbor engine-image push (~44 GB of fresh CUDA layers, ~20 GB for vLLM alone) hung
under **host disk pressure** — the retained `.data` MinIO cache had grown to 182 GB and the disk sat
at 94%, so the MinIO-backed registry could not ingest the fresh blobs; clearing stale retained models
(disk → 82%) let the push complete with zero retries, and `pushAttempts` in
`src/Infernix/Cluster/PublishImages.hs` was widened 8→30 as defensive hardening. (b) The
`infernix-unit` suite hung invoking `poetry install --with apple-silicon` for the transformers
engine: poetry deadlocked on the **keyring/dbus** backend in the headless container; fixed in
`docker/Dockerfile` with `poetry config keyring.enabled false` (config file, not an env var) —
verified by a probe that completed the install in 2m42s with keyring disabled vs. an indefinite hang.

Net: the **xet-429 download blocker, the Bark stale-partial-cache load defect, the vLLM
stdio-framing + engine-core defects, the Harbor large-layer push (disk), and the poetry keyring hang
are all fixed and validated**. The earlier resume point is superseded by the 2026-06-20 full
CUDA Linux rerun: `./bootstrap/linux-gpu.sh test` carried the sequence through the vLLM,
framework-specific, native, pool-routing/backpressure/chaos/recovery, and routed Playwright E2E
steps with the fixes baked into the images. The same current source also passed rebuilt-image
`./bootstrap/linux-cpu.sh test`. Wave I is therefore closed for Phases 4 and 6 under the selected
`linux-gpu` plus `linux-cpu` sign-off rule. Basic Pitch TensorFlow, Omnizart, and MT3 remain named
upstream-incompatible residual rows outside the active runtime catalog.

## Cadence Rule

Wave numbering operationalizes Section Q of
[development_plan_standards.md](development_plan_standards.md). The
doctrinal rule remains unchanged:

> A phase may stay `Active` with an explicit validation-only residual after code-side closure, but
> it cannot move to `Done` until its one chosen accelerator plus `linux-cpu` have supplied the
> required full-suite evidence. A validation-only residual is queued as a wave and does not require
> ad hoc machine switching before that wave is scheduled.

The operational form of that rule — identical to the copy in Section Q of
[development_plan_standards.md](development_plan_standards.md) — is:

> **Implement in natural phase order on whichever single machine is present, and validate each phase
> on exactly one accelerator plus `linux-cpu` — never both accelerators.** Every open phase has two
> independent axes. *Code-side closure* (Axis 1) is the implementation plus the machine-independent
> gate set — `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
> `infernix lint files/docs/chart/proto`, `infernix docs check`, the web unit suite, and
> `poetry run check-code`; completed in natural order on one machine, it is the gate to begin the
> *next* phase's implementation. *Single-accelerator sign-off* (Axis 2) is the hardware-specific
> full-suite for the phase's one chosen accelerator (`apple-silicon` Metal/Core ML, or `linux-gpu`
> CUDA) plus `linux-cpu`, recorded here as committed per-lane evidence; it is the gate for `Done`.
> A phase never requires the other accelerator. Cross-accelerator contracts are split across sibling
> per-accelerator phases or merged by a later `linux-cpu`-only aggregation phase that re-runs no
> accelerator lane.

Waves enforce that boundary explicitly. Contributors and assistants
land code on the locally available cohort during the active wave and record only the phase's chosen
accelerator plus `linux-cpu` evidence for `Done`.

## Wave J: Engine Pool Routing and Broker-Native Backpressure (Closed)

Wave J records the engine-pool routing and broker-native backpressure attestations. It is separate
from Wave I because it changes routing topology rather than engine payload fidelity. It closed on
2026-06-20 after the Linux GPU/CUDA full-suite gate passed, paired with the rebuilt-image
`linux-cpu` full-suite gate.

### Stage 1 — Code-side closure (single machine, natural order, no machine switch)

Land the reopened work in phase order: Phase 4 Sprint 4.19 adds the typed pool/member graph,
topic derivation, and illegal-state rejection; Phase 6 Sprint 6.32 adds lint, unit, and integration
gates for the graph; Phase 7 Sprint 7.24 wires coordinator routing, engine member subscriptions,
broker-native backpressure, pinned member routes, and the production `demo_ui = false` topology.

The machine-independent gate set is the normal focused lint, unit, and docs validation suite.
Hardware-specific proof is deferred to Stage 2.

### Stage 2 — Closure Evidence

- Apple Silicon proves stable host-id membership and `Shared` work distribution across distinct
  logical host identities on the same Apple machine, including execution of the newly added
  backlog/backpressure harness and the documented restart/reconcile boundary. Exact-host
  `Exclusive` duplicate rejection, same-machine `Shared` coexistence, and production
  `demo_ui = false` assertions are already covered on the Apple host integration lane. Physical
  multi-host distribution is hardware-deferred proof while no second Apple host is available.
- Linux CPU proves Kubernetes member placement is observational rather than a durable routing id
  and that backlog on one member lets Pulsar deliver new work to another available member through
  broker backpressure.
- Linux GPU/CUDA closure passed on 2026-06-20 through `./bootstrap/linux-gpu.sh test`; the same
  current source also passed rebuilt-image `./bootstrap/linux-cpu.sh test`.
- Linux GPU/CUDA proves the same pool contract while preserving framework-specific GPU isolation as
  a placement concern.
- Both cohorts prove production `demo_ui = false` keeps the coordinator and engine pools while
  omitting only demo/frontend/identity/routes.

## Phase Cohort Status Index

This index records the final cohort status after the Wave C, Wave E, Wave F, Wave G, Wave H, Wave I,
and Wave J closures. Wave I closed the selected Phase 4/6 real per-family inference and
engine-payload gates, while Wave J closed the Phase 4/6/7 engine-pool routing and broker-native
backpressure gates.

| Phase | Code-side closure | Apple cohort gate | CUDA Linux cohort gate |
|-------|-------------------|-------------------|------------------------|
| 0 | Sprints 0.1-0.10 `Done` | Closed in Wave A (lint gates) | `linux-cpu` passed on the recorded validation; `linux-gpu` passed on the recorded validation |
| 1 | Sprints 1.1-1.12 `Done`; Sprint 1.13 Tart implementation is historical and removed; Sprint 1.14 is code-side closed for the manifest materializer, fixed host Metal bridge, `coreml-native` source/smoke commands, and Apple native validation-wrapper roots | Closed in Wave A for 1.1-1.12; Sprint 1.14 Tart-free manifest materialization, generated Metal bridge smoke, installed Core ML runtime-load smoke, native validation-wrapper materialization, integration, focused e2e, and aggregate `test all` passed on the current Apple host against the validation-wrapper state | `linux-cpu` passed on the recorded validation; `linux-gpu` passed on the recorded validation; Sprint 1.14 has no CUDA Linux Metal surface |
| 2 | Sprints 2.1–2.13 `Done` | Closed in Wave A (retained-state replay + Patroni filter + cluster lifecycle) | `linux-cpu` passed on the recorded validation; `linux-gpu` passed on the recorded validation |
| 3 | Sprints 3.1–3.12 `Done` | Closed in Wave A/A.2 (substrate-aware publication, Harbor port, containerd, hand-authored MinIO, and Apple host-native E2E) | `linux-cpu` amd64 passed on the recorded validation; `linux-gpu` passed on the recorded validation; native arm64 `linux-cpu` passed in Wave F on the recorded validation |
| 4 | Sprints 4.1-4.20 `Done`; Sprint 4.18 is closed for engine-artifact manifests, Linux runtime-backed native roots, the Haskell-owned native artifact marker/upload bridge, Apple native validation-wrapper roots, and matrix reconciliation; Sprint 4.19 is closed for typed engine-pool routing and the single-host logical `Shared` backlog harness | Original contract closed in Wave A; per-family real-output closed in Wave I on the selected `linux-gpu` accelerator plus `linux-cpu`; engine-pool routing closed in Wave J; physical Apple multi-host proof is hardware-deferred | Current `linux-gpu` full-suite passed the routed framework and native rows, and current rebuilt-image `linux-cpu` full-suite passed integration plus routed Playwright on 2026-06-20 |
| 5 | Sprints 5.1-5.10 `Done` | Closed in Wave A/A.2 (demo backend + adapter dhall reads via integration suite and routed E2E) | `linux-cpu` passed on the recorded validation; `linux-gpu` passed on the recorded validation |
| 6 | Sprints 6.1-6.32 `Done`; per-family real-output coverage, README/generated-catalog matrix drift linting, and engine-pool routing validation gates are closed | Original coverage closed in Wave A/A.1/A.2/A.3; per-family routed real-output closed in Wave I; engine-pool validation closed in Wave J; physical Apple multi-host proof is hardware-deferred | Current `linux-gpu` full-suite and current rebuilt-image `linux-cpu` full-suite passed on 2026-06-20 |
| 7 | Sprints 7.1-7.24 `Done`; Sprint 7.23 is superseded historical Apple singleton work; Sprint 7.24 is closed for engine-pool assignment, broker-native backpressure, production coordinator presence with `demo_ui = false`, and the single-host logical `Shared` backlog harness | Original durable-context gates closed in Wave A/A.1/A.2/A.3; Wave G closed for auth-UX; Sprint 7.24 closed in Wave J; physical Apple multi-host proof is hardware-deferred | Current `linux-gpu` full-suite and current rebuilt-image `linux-cpu` full-suite passed on 2026-06-20 |

Every Apple cohort gate above was additionally re-confirmed end to end on the Apple cohort host by
Wave H (2026-06-09) from a clean build root: `cabal install all:exes`, the lint/style/unit
gates, the explicit `infernix cluster up` → `cluster status` → `cluster down` lifecycle with
retained-state replay, `infernix test integration` PASS, `infernix test e2e` 9/9, and the
aggregate `infernix test all`. The CUDA Linux cohort hardware was unavailable at Wave H, so the
`linux-cpu` and `linux-gpu` columns retain their prior recorded closure and were out of Wave H
scope. The 2026-06-16 Apple host refresh adds Wave I evidence for host-native build, typed
engine-manifest materialization, `apple-silicon` substrate staging, unit/lint/docs gates, focused
`lint files/docs/proto/chart`, the generated Metal runtime bridge smoke
(`Metal runtime probe passed on Apple M1 Max`), installed `coreml-native` runtime-load smoke
(`Core ML runtime probe passed`), and smoke-capable Apple native validation runner roots. The
2026-06-16 Apple integration rerun completed the active Apple catalog through the
host engine daemon, validated the source-fingerprint rebuild/reuse path, proved pinned
`Exclusive` duplicate rejection against a real broker, proved same-machine Apple `Shared`
subscription coexistence through real Pulsar admin stats, executed the single-host logical
`Shared` backlog/backpressure harness, and covered Apple `demo_ui = false` route/publication
assertions. Focused Apple `./.build/infernix test e2e` reruns passed 9/9 after the object-input
dispatch fix, browser upload fixtures, and the 900-second cold-bootstrap readiness envelope. The
latest focused pass used rebuilt cluster image digest
`sha256-ed34da86992bb1a4d285f00feb77051d12eb4fa594b7bb34ed73561a027b1a71`. The subsequent full
Apple `./.build/infernix test all` aggregate passed lint, unit, integration, and 9/9 routed
Playwright against rebuilt cluster image digest
`sha256-f4a30f4e177206b64ce5a0d3abea8d72a8bdbe637148530e1619bdf5ce8ae7c3`. That Apple refresh did not by itself close Wave I, because the materialized native runners are
validation wrappers rather than real Apple native payloads; Wave I closed on 2026-06-20 on the
selected `linux-gpu` accelerator plus `linux-cpu` full-suite gates recorded above.

When a wave closes, this table is the place to update first. Phase
docs follow.

## Historical Evidence

The Apple Silicon validation reset (see [README.md](README.md) and
[00-overview.md](00-overview.md)) moves dated proof points for earlier hardware into
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical Validation
Evidence". Phase docs reference that table instead of inlining dated proof points per Section I.
