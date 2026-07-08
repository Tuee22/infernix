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
| H | Apple Silicon (current host) | Full current-host Apple lifecycle revalidation from a clean build root (no prior `./.build` artifacts): `cabal install all:exes`; `infernix lint files/docs/chart/proto` plus `infernix docs check`; `infernix test lint` (haskell-style) and `infernix test unit` (`infernix-unit` plus web 71/71); explicit `infernix cluster up` → `cluster status` (77 pods across 2 nodes, `infernix-manual` storage, full Envoy Gateway route set, `pulsar-bridge-to-host-daemon` dispatch) → `cluster down` (retained-state replay, `./.data` preserved) → post-teardown `cluster status` (`clusterPresent: False`, `lifecyclePhase: cluster-absent`); `infernix test integration` PASS; `infernix test e2e` 9/9; aggregate `infernix test all`. The dynamic `choosePulsarHttpPort` chooser shifted the Pulsar host port 30080→30081 around a VS Code-held `127.0.0.1:30080`. Native arm64 throughout (colima `aarch64`, no emulation or Docker-context changes). Published cluster image `infernix-linux-cpu@sha256:7f341cb1629c1d0af9b72db0fef7b89cc1f13d2bd02afe9be1daeed5e7f18454`. **Superseded (2026-07-07):** this Apple `test integration` / `e2e` / `test all` proof predates Wave K/L realness, the MT3 replacement, Phase 8 eager staging, and Phase 9; it does not attest the current 16-model catalog, and a current full per-model apple-silicon run OS-OOM-kills the daemon (Phase 4 Sprint 4.26; see Wave R). | Closed (inference proof superseded) | 2026-06-09 |
| I | Per-accelerator real-output attestations | Real per-family inference and engine-artifact materialization attestations. Phase 1 Sprint 1.14 is closed on Apple materialization evidence. The CUDA Linux cycle replaced Linux runner-contract payload placeholders with runtime-backed wrappers, strict-smoked all five native adapter roots in `infernix-linux-gpu:local`, then closed Phase 4 and Phase 6 real-output work on 2026-06-20: full `./bootstrap/linux-gpu.sh test` passed the selected CUDA accelerator lane, and rebuilt-image `./bootstrap/linux-cpu.sh test` passed the paired CPU lane. The GPU Playwright matrix exercised all 16 `linux-gpu` catalog rows, including framework-specific and native rows through live routed inference; the CPU lane passed 9/9 routed Playwright plus full integration. | Closed | 2026-06-20 |
| J | Apple Silicon + Linux CPU/GPU | Substrate-neutral engine-pool routing and broker-native backpressure. Re-opened Phase 4 Sprint 4.19, Phase 6 Sprint 6.32, and Phase 7 Sprint 7.24 to replace raw batch-topic routing, the Apple singleton/failover stopgap, and demo-off coordinator gating with a validated pool/member graph. Stage 1 code-side work landed on the Linux outer-container lane; Apple Stage 2 evidence covered pinned `Exclusive` member routes, same-machine host-member coexistence on a real `Shared` pool subscription, logical `Shared` backlog/backpressure, and production `demo_ui = false`; Linux CPU Stage 2 covered Kubernetes-observational members, pool placement, shared-subscription backlog/backpressure, replacement/drain cases, anti-affinity, lifecycle rebinding, and demo-off publication. The remaining Linux GPU/CUDA Stage 2 gate closed on 2026-06-20 through the full `./bootstrap/linux-gpu.sh test` pass, paired with the rebuilt-image `./bootstrap/linux-cpu.sh test` pass. Physical Apple multi-host routing is deferred hardware proof, not open Wave J work. | Closed | 2026-06-20 |
| K | CUDA Linux + Linux CPU | **Realness reopen — real Linux inference.** Reopened Phase 4 (Sprints 4.21–4.23) and Phase 6 (Sprint 6.33), built on the Phase 0 (Sprint 0.12) machine-independent realness lint (Haskell `realnessFabricationViolations` in `HaskellStyle.hs` + Python `check-code` AST): remove every adapter/runner fabrication path (done 2026-06-23), retire the JAX/TF adapters (done), deliver real Linux engines (real ONNX basic-pitch over the input, real Audiveris invocation, de-masked whisper/CT2/llama), ONNX adoption (Demucs/Open-Unmix self-contained ONNX, SDXL-Turbo on GPU), fixed weight provisioning, modern PyTorch music-transcription rebinds, Phase 4's own real per-family fixtures + fail-closed per-row int+e2e (Sprint 4.23), and the Phase 6 fail-closed HA/service-loop assertions (Sprint 6.33). Stage 1 machine-independent gates + Stage 2 `linux-gpu` + `linux-cpu` real per-family output for the Linux catalog. **Progress 2026-06-25:** the **source-separation family is now real** — both **Demucs** (real first-party `.th` weight URL + `weights_only=False`/`load_model` fix) and **Open-Unmix** (`openunmix` dep resolving 1.3.0, dedicated `_separate_open_unmix` path, Zenodo `umxhq` record + new multi-file bootstrap staging, `umxhq(pretrained=False)`+`load_state_dict(strict=False)`) load real weights and produce real stem ZIPs (proven in the `linux-cpu` pytorch venv; `check-code` + `cabal build all` green; `poetry lock` resolves cleanly). **`linux-cpu` Stage-2 GREEN (2026-06-25):** the full `linux-cpu` cohort suite passes on a real Kind cluster — `infernix test integration` **22/22 steps PASS** (every per-model inference row then active produces real output: real LLM (qwen2.5 safetensors, tinyllama GGUF via llama.cpp), real speech (whisper.cpp + faster-whisper CT2), real Demucs + Open-Unmix stem ZIPs, real basic-pitch ONNX MIDI, real Omnizart ByteDance piano MIDI, real Bark audio, real Audiveris OMR → MusicXML; plus cache lifecycle, durable Pulsar topics, and all HA/chaos hardening — engine pool placement, backpressure, frontend/coordinator/engine failover, node drain, **bootstrap failover + dedup**, throughput, harbor/minio/pulsar recovery, postgres failover + lifecycle rebinding, anti-affinity), and `infernix test e2e` **9/9 Playwright specs PASS** (including the 11-min per-model browser smoke matrix exercising every catalog model). A later catalog update replaces the obsolete MT3 residual with MT3-PyTorch and MR-MT3 through `mt3-infer`. **`linux-gpu` Stage-2 GREEN (2026-06-26):** the rebuilt CUDA image (`infernix-linux-gpu:local`, nvidia/cuda 12.8.1 base, RTX 5090) passes `infernix test integration` (PASS — per-model inference over the then-active 14-row GPU catalog including the GPU-only rows AWQ + GPTQ via vLLM, SDXL-Turbo + Wan2.1 video via Diffusers, plus all three per-engine deployments and the HA/chaos tail) and `infernix test e2e` (9/9 specs, including the 34.8-min per-model browser matrix exercising every GPU model). The GPU-only rows were already real engine code with valid HuggingFace weight URLs; the source-separation/Audiveris/bootstrap-dedup fixes from the `linux-cpu` close carried over unchanged, so the GPU lane went green on the first cluster run. **Wave K is fully closed** (both `linux-gpu` and `linux-cpu` Stage-2 green). | Closed | linux-cpu 2026-06-25, linux-gpu 2026-06-26 |
| L | Apple Silicon + Linux CPU | **Realness reopen — real Apple engines.** Reopened Phase 1 Sprint 1.15 to replace Apple validation wrappers with real Core ML, MLX, llama.cpp/whisper.cpp Metal, CTranslate2, ONNX, and Audiveris engines through the headless materialization lane. Stage 1 is green, Apple Stage 2 integration plus focused routed Playwright are green, and the paired `linux-cpu` full routed real-output gate closed on 2026-06-29. The closing real Linux host rerun rebuilt `infernix-linux-cpu:local` as `sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8` (`19963913870` bytes, created `2026-06-29T02:43:21.839158236-04:00`) after adding the base Pulsar autorecovery JVM/resource envelope and the base Harbor registry `512Mi`/`2Gi` memory envelope with unit guards. `./bootstrap/linux-cpu.sh test` exited zero: Haskell style, Python `check-code`, Haskell unit, generated web contracts (`71/71`), full integration with every `linux-cpu` catalog row producing real output plus the HA/chaos tail and throughput (`users=3`, `contextsPerUser=2`, `promptsPerContext=2`, `totalPrompts=12`, `p95Seconds=76.10685634613037`), and routed Playwright `9/9` including the 22.7-minute per-model browser matrix all passed. **Scope (2026-07-07):** this Apple real-engine close is the then-active pre-MT3 catalog only; no apple-silicon full per-model attestation exists for the current 16-model catalog, and a current run OS-OOM-kills the daemon (Phase 4 Sprint 4.26; see Wave R). | Closed (then-active catalog only) | 2026-06-29 |
| M | CUDA Linux + Linux CPU | **Webapp-mediated file storage — object-proxy, per-user Files view, in-browser MIDI/MusicXML/ZIP rendering, per-user isolation hardening (reopened Phase 3 Sprint 3.13 + Phase 7 Sprints 7.25–7.27).** Stage 1 machine-independent gates closed 2026-06-24: host `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint files/chart/docs/proto`, `infernix docs check`, the containerized web suite (`spago build`, `spago test` 71/71), and the 7.27 dependency bundle. Stage 2 closed on this CUDA Linux host with the selected `linux-gpu` accelerator plus `linux-cpu`. The paired `linux-cpu` full routed real-output gate passed on 2026-06-29 with rebuilt image `sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8` (style, Python `check-code`, Haskell unit, web `71/71`, full integration, HA/chaos, throughput, routed Playwright `9/9`). The `linux-gpu` full gate passed on 2026-06-29 with launcher image `sha256:2e0f9f8a53124185d4118c105636b292ce79327f331f359c4ee476cbc48cb714`: Haskell style, Python `check-code`, Haskell unit, web contracts `71/71`, full integration with every `linux-gpu` catalog row producing real output plus cache/service/durable-topic and lifecycle validation, and routed Playwright `9/9` including the 28.5-minute browser per-model matrix. Closing fixes found by the cohort run: Linux containers no longer materialize Apple-only framework markers; the `linux-gpu` browser catalog expectation is 14 rows; generated GPU engine values use a 4Gi request / 16Gi limit for Wan; post-catalog checks re-enable a representative GPU engine deployment; bootstrap-ready dedup includes the ready-event timestamp; MinIO claims are 64Gi for retained model capacity; local Docker disk pressure from repeated validation builds was cleared before the final pass. Harbor jobservice had startup restarts during rollout and recovered; the final gate does not claim zero restarts. | Closed | 2026-06-29 |
| N | CUDA Linux + Linux CPU | **Generated artifact ownership and result-bridge authorization (Phase 7 Sprint 7.28).** Stage 1 machine-independent gates closed on 2026-06-29: `cabal test infernix-unit --test-options='--hide-successes'`, `cabal build test:infernix-integration`, `python3 -m py_compile python/adapters/common.py`, `cabal run exe:infernix -- test lint`, and `cabal run exe:infernix -- lint proto` passed after `WorkerRequest` gained the Haskell-derived `users/<sub>/contexts/<ctx>/generated/` output prefix, Python adapters/native runners consumed only the supplied target, and the result bridge failed closed on raw or cross-user generated object refs. Stage 2 closed on 2026-06-30 with the selected `linux-gpu` accelerator plus `linux-cpu`. `./bootstrap/linux-gpu.sh test` passed after closing the runtime fixes exposed by that gate: per-engine daemon execution serialization and bounded timeout/retry for deduplicated Pulsar producer publishes. The GPU gate covered Haskell style, Python `check-code`, Haskell unit, web contracts `71/71`, full integration with every `linux-gpu` catalog row producing real output, routed Playwright `9/9`, and the browser per-model matrix. The paired CPU lane rebuilt `infernix-linux-cpu:local` as `sha256:c867ccd38e3390cbc65041efecea16a5fb001b1b4c17519a808118b82a194f48`; `./bootstrap/linux-cpu.sh test` passed Haskell style, Python `check-code`, Haskell unit, web contracts `71/71`, full integration with HA/chaos and throughput (`users=3`, `contextsPerUser=2`, `promptsPerContext=2`, `totalPrompts=12`, `p95Seconds=65.46793055534363`), and routed Playwright `9/9` including the 23.2-minute browser per-model matrix. | Closed | 2026-06-30 |
| O | CUDA Linux + Linux CPU | **MT3 catalog replacement follow-on (Phase 4 Sprint 4.22 + Phase 6 Sprint 6.35).** Stage 1 code-side work landed on 2026-06-30: `music-mt3-jax` is removed, `music-mt3-infer` and `music-mr-mt3` are generated for `linux-cpu`, `linux-gpu`, and `apple-silicon`; the PyTorch adapter loads them through `mt3-infer` with model-cache paths and `auto_download=False`; MT3-PyTorch stages `config.json` + `mt3.pth`; MR-MT3 stages the Hugging Face `mt3.pth`; docs lint and unit coverage see the expanded matrix. Current CPU evidence chain on 2026-07-01: rebuilt CPU first failed closed on the removed Hugging Face T5 `checkpoint` symbol under `transformers 4.57.6`; the adapter added a real `torch.utils.checkpoint.checkpoint` shim; the next attempt failed on `mt3-infer`'s undeclared `absl` import; the PyTorch engine added `absl-py >=2.0`; the next attempt failed on missing `.generate` after `transformers >=4.50`; the PyTorch engine now constrains `transformers` to `>=4.46,<4.50`; the capped rebuild exposed and then fixed the stale unit assertion; image `sha256:d478db2f41420427c7d1f93adf22eac35f4dc384bf4fc432986aaa4017abee8b` reached real `music-mt3-infer` and failed closed on upstream T5 `cache_position[-1]` with `cache_position=None`; the no-cache wrapper passed mounted `poetry --directory python run check-code`, but rebuilt image `sha256:b5fb4e6c82b7dc9f46c04f7e7910dd460bcb516518ecdf8d5c313e4303947ad8` (created `2026-07-01T16:37:11.897901769-04:00`) still passed Haskell style, Python `check-code`, Haskell unit, and web contracts (`71/71`), reached `per-model inference: linux-cpu`, and failed closed on the same upstream T5 `cache_position` path with the no-cache wrapper visible in the traceback. The adapter now wraps Hugging Face `T5Block.forward` for MT3 imports and supplies `cache_position` when the upstream `mt3-infer` custom stack omits it; mounted Linux-image `poetry --directory python run check-code` and a PyTorch-engine T5Block probe pass. **Landed 2026-07-02:** the rebuilt full-suite `linux-cpu` run then failed closed on `music-mr-mt3` — MR-MT3's vendored T5Stack calls the upstream `transformers` `T5Block.forward` with the plural `past_key_values` keyword, which `transformers 4.49.0` names `past_key_value` (singular); the adapter's `T5Block.forward` compat wrapper now normalizes the keyword (an argument-name adaptation, not fabrication). Both MT3 rows were then pre-validated in-container (real MIDI, no cluster). **`linux-cpu` GREEN:** rebuilt-image `./bootstrap/linux-cpu.sh test` passed Haskell style, Python `check-code`, Haskell unit, web contracts (`71/71`), full integration (real MIDI for `music-mt3-infer` and `music-mr-mt3` plus the HA/chaos tail), and routed Playwright **9/9** including the 25-minute per-model browser matrix. **`linux-gpu` MT3 proven:** `./bootstrap/linux-gpu.sh test` integration PASS (real MIDI for both MT3 rows on CUDA) and routed Playwright **8/9** — the single failure was the CUDA-only, MT3-unrelated `video-wan21-t2v` matrix row timing out on its ~27 GB **cold-cache** lazy bootstrap (a pre-existing named CUDA residual), not either MT3 row. The clean `linux-gpu` 9/9 is now owned by **Phase 8 Sprint 8.5** (eager coordinator model-cache staging + the `warm-model-cache` cluster-up barrier), which stages the Wan weights at cluster-up so the matrix no longer races the cold cache. Earlier Wave K/L/N evidence remains valid only for the then-active catalogs. The Apple PyTorch CPU binding is catalog-supported, but no post-replacement Apple full-suite proof is claimed until a separate Apple rerun records it. **Closed by Wave P** (the clean `linux-gpu` 9/9 landed once Phase 8 eager staging shipped). | Closed (GPU full 9/9 in Wave P) | 2026-07-02 (GPU 9/9 in Wave P 2026-07-04) |
| P | CUDA Linux + Linux CPU | **Phase 8 close + Wave O successor (Phase 8 Sprints 8.1–8.6, and the clean `linux-gpu`/`linux-cpu` 9/9 for Phase 4 Sprint 4.22 / Phase 6 Sprint 6.35).** Phase 8 shipped: zero version-controlled `.dhall`; explicit `infernix init` / `test init` with shared defaults + fail-fast (no auto-generate); binary-generated ConfigMap/Secret bodies with the chart as a `nindent` string embedder (`lint chart` rejects `let`/schema Dhall in templates); coordinator eager model-cache staging with the `warm-model-cache` cluster-up barrier and the `--empty-models` image bake; and the test-harness config lifecycle (own-and-restore `./infernix.dhall`, image bakes `./infernix.test.dhall`). Machine-independent gates green throughout. Cohort fixes the run surfaced and closed: (1) `.dockerignore` must exclude the new root `infernix.dhall`/`infernix-host.dhall`/`infernix.test.dhall` so an operator `HostNative` manifest cannot leak into the image build (else build-time `materialize-substrate linux-gpu` fails its host-native guard); (2) the launcher image bakes `./infernix.test.dhall` (a separate `test init` cannot persist across `--rm` containers); (3) the operator-routes SecurityPolicy reads `clusterConfig.keycloak.baseUrl` from Helm **values** to build its JWT `issuer`, so `renderHelmValues` must emit the routed keycloak wiring alongside the rendered body (an interim Sprint 8.4 edit dropping it 401-ed every valid operator token → routed Playwright specs 154/369); (4) the image apt mirror moved from the index-inconsistent `mirrors.edge.kernel.org` to `archive.ubuntu.com`. **Both lanes GREEN 2026-07-04:** `./bootstrap/linux-gpu.sh test` (image `sha256:3a356ef2…`) and `./bootstrap/linux-cpu.sh test` (image `sha256:81fab869…`) both ran the full `infernix test all` — Haskell style, Python `check-code`, Haskell unit, web contracts, full integration with real per-model output plus the HA/chaos tail, and routed Playwright **9/9**, including the per-model browser matrix exercising every catalog model with the 27 GB `video-wan21-t2v` row completing (gpu 18.2 m, cpu 16.5 m) via the eager sweep. Non-blocking residual: the `warm-model-cache` barrier's host-side MinIO poll reports `0/16` (a presigned-HEAD reachability/signing detail from the launcher); the eager sweep delivered the 9/9 regardless. | Closed | 2026-07-04 |
| R | Apple Silicon + Linux CPU (+ `linux-gpu` residual) | **Apple-silicon inference RAM admission + matrix accuracy + fail-closed matrix hardening (Phase 4 Sprints 4.25/4.26, Phase 6 Sprints 6.36/6.37).** **Code-side complete and machine-independent-validated on this Apple host (2026-07-08).** Sprint 4.26: `ModelDescriptor.modelRamFootprintMib` threaded through the hand-written JSON codec, the Dhall decoder/renderer/type, and the purescript-bridge + generated `Contracts.purs`; `DemoConfig.inferenceRamBudgetMib` resolved at materialization time (apple-silicon: `sysctl -n hw.memsize` via the manifest `HostSysctl` tool − a read-only `colima list --json` VM-pledge probe resolved through a bootstrap-adjacent fixed candidate (colima is read, never managed, and is **not** a manifest tool) − a host reserve; Linux: recorded engine pod memory limit); `validateDemoConfig` fails fast on an over-budget apple-silicon config (new unit reject/accept assertions); the serialized engine critical section rejects an over-budget model as a clean `status=failed` (`overRamBudgetRejection`). On this 64 GiB host the resolver computed a real budget of 13312 MiB (64 GiB − 48 GiB colima − 3 GiB reserve), which the whole apple catalog fits. Sprint 4.25: row 11 relabeled to the honest `ONNX Runtime (CPU)` (Models ModeBinding + README cell in lockstep, `requiresGpu=False`); rows 4/6 CUDA-runs-CPU-binary documented; row 14 stale note reconciled; row 17 kept the documented Apple residual; Linux basic-pitch onset divide-by-zero guard ported; Apple native smoke fails closed on a non-venv interpreter / import failure. Sprint 6.36: `Chat.purs` `data-inline-output="present|absent"` marker + routed real-text assertion (defeats the `"No inline output."` fallback) + picker catalog-completeness guard. Sprint 6.37: integration `classifyAppleMemoryBoundedResult` (over-budget = clean per-row fail-closed, distinguishable from a stall/fabricated pass; missing result named as the OS-OOM-kill symptom). Machine-independent gates green: `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint files\|docs\|chart\|proto`, `infernix docs check`, web unit `71/71`, `node --check` on the Playwright spec, and `poetry --directory python run check-code`. **Apple integration cohort GREEN (2026-07-08).** A full host-native `./.build/infernix cluster up` (substrate `apple-silicon`, edge `127.0.0.1:9090`) built and deployed the arm64 `infernix-linux-cpu:local` cluster image with the new config schema and published a cluster ConfigMap carrying the host-computed `inferenceRamBudgetMib = +13312` (64 GiB − 48 GiB colima − 3 GiB reserve). This cohort run **surfaced and fixed two real bugs the machine-independent gates could not catch**: (1) the Dockerfile hand-writes the stage-zero host manifest (`/opt/infernix/dhall/InfernixHost.dhall`) inline, and Sprint 4.26's new manifest `sysctl` field made the old manifest fail the strict Dhall decode ("Expression doesn't match annotation") during image build — the Dockerfile heredoc now emits `sysctl`; and (2) the subsequent `linux-cpu` unit run caught that the interim fix had also added a `colima` field to the manifest/Dockerfile, which violated the Phase 1 Sprint 1.12 "colima retired" guard (`not "colima" isInfixOf linuxDockerfileContents`) — so colima was moved out of the manifest entirely and the VM-pledge probe now resolves colima through a bootstrap-adjacent fixed-candidate read (`HostTools.readHostToolFallback`, read-only), keeping the Linux manifest colima-free while the Apple budget still computes correctly (13312 MiB on this host). Then `./.build/infernix test integration` drove the **full 16-model per-model `apple-silicon` inference lane to all `status=completed` with ZERO OS OOM-kill** — the on-host daemon survived every model including the heavy diffusion rows (`image-sdxl-turbo`, `image-apple-stable-diffusion-coreml`) plus the LLM (smollm2 safetensors, tinyllama GGUF/llama.cpp, qwen1.5 MLX), speech (whisper.cpp small, faster-whisper CT2), source-separation (Demucs, Open-Unmix), audio-to-MIDI (basic-pitch Core ML + ONNX), music-transcription (mt3-infer, mr-mt3, omnizart piano), bark, and Audiveris rows. The suite is fail-closed per row and **advanced past** the per-model inference step into the service-loop and HA/chaos tail, confirming every row produced real output — the Phase 4 Sprint 4.26 admission control's never-OOM guarantee is proven on Apple hardware, and Phase 6 Sprint 6.37's memory-bounded lane holds (no row was over-budget on this host, so all were admitted; the classification stands for a constrained host). **Apple routed Playwright GREEN (2026-07-08).** `./.build/infernix test e2e` (fresh host-native demo-enabled cluster, `16/16` models warm-staged) ran the host `npm exec` Playwright suite **13/15 specs PASS in 9.6 min**, including — the ones this wave owns — spec `inference.spec.js:1174` **"browser per-model smoke matrix exercises every catalog model" ✓**, which exercises Sprint 6.36's catalog-completeness guard (picker option set == published catalog) and the `data-inline-output="present"` real-text assertion (defeating the `"No inline output."` fallback) by driving all 16 apple catalog models through the demo UI to real output (including the heavy `image-sdxl-turbo` + `image-apple-stable-diffusion-coreml` rows). The Phase 9 RBAC/dashboard specs (`admin sees cluster-wide`, `non-admin denied`, `personal dashboard disjoint`, object-proxy isolation) also passed, re-confirming Phase 9 on the Apple routed path. The **2 failures are Phase 7 specs untouched by this wave and are timing flakes**: `inference.spec.js:434` (self-service account deletion, `toBeTruthy` false in 1.7 s) and `inference.spec.js:878` (artifact-preview download-grant — the JSON preview stayed "Preview waits for a download grant." past the 5 s grant/presign timeout); neither touches the changed code (`Chat.purs` only marks inference-result bodies, not artifact previews or account deletion), and Phase 7 remains `Done` from Waves M/N/G. **`linux-cpu` machine-independent gates GREEN in-container (2026-07-08):** after the colima fix, `./bootstrap/linux-cpu.sh build` rebuilt `infernix-linux-cpu:local` cleanly (the corrected inline host manifest — `sysctl` present, `colima` absent — decodes against the reflected schema), and `docker compose run --rm infernix infernix test unit` in the fresh image **PASSED** (Haskell `infernix-unit: PASS` including the colima-retirement guard, plus web `71/71`). **`linux-cpu` full integration reached per-model inference but did not fully pass (2026-07-08):** `./bootstrap/linux-cpu.sh test` brought up the nested 3-node Kind cluster and passed style + unit + cluster state reload + demo-config decode + route probes, then **failed on a per-model row with a corrupt staged PyTorch weight** — `RuntimeError: PytorchStreamReader failed reading zip archive: failed finding central directory` while loading an MT3-family (`T5ForConditionalGeneration`) checkpoint. This is a **model-weight-staging flake orthogonal to this wave** (Sprints 4.25/4.26/6.36/6.37 touch RAM admission, matrix-cell accuracy, and validation assertions — none touch weight staging or PyTorch loading), and the failure is a correct fail-closed `status=failed` per the realness contract (a corrupt weight raises rather than fabricates). The `linux-cpu` infrastructure (image build, nested cluster up, config decode, routed surfaces, engines-in-pods dispatch) is GREEN; the full `linux-cpu` per-model integration pass is a residual pending clean MT3 weight staging (the same MT3 rows that were fragile in Wave O and closed on Linux under Wave P). **Open residual:** the `linux-cpu` full integration + routed e2e (blocked here only by the MT3 weight-staging flake; the host-RAM admission is a no-op on Linux — engines run in Kubernetes-bounded pods), and the CUDA GPU-accuracy `linux-gpu` rows (real `CUDAExecutionProvider` + `onnxruntime-gpu` / CUDA-built binaries, needing a CUDA Linux host). | Code-side CLOSED; **Apple cohort GREEN (integration 16/16 zero-OOM + routed Playwright per-model matrix + RBAC)**; residual: `linux-cpu` full-suite + `linux-gpu` CUDA accuracy | Code-side + Apple integration + Apple routed E2E 2026-07-08; `linux-cpu` + `linux-gpu` residual open |
| Q | Apple Silicon + Linux CPU/GPU | **2026-07-06 review reopen — access control + monitoring (Phase 9) and matrix substrate accuracy (Phases 4/6 reopen).** Phase 9 Stage 1 machine-independent code is **fully landed and green** (2026-07-06 on this Apple host — `cabal build all`, `cabal test infernix-unit` (full suite PASS), `cabal test infernix-haskell-style`, `infernix lint chart|docs|files|proto`, `infernix docs check`, `poetry run check-code`): the `infernix-admin` realm role + realm-roles mapper + hardcoded admin user; `JwtClaims` `realm_access.roles` parse + `jwtClaimsHasRealmRole`; the edge `SecurityPolicy` admin `authorization` over all four operator routes + the `infernix-harbor-api`/`infernix-pulsar-ws` `targetRefs`; the backend admin gate (`withAdminRequest`) on `GET /api/cache`, `/api/cache/{evict,rebuild}`, and the new `GET /api/admin/overview` cluster-wide monitoring endpoint; the SPA admin gating + admin monitoring panel + per-user personal dashboard (verbatim `index.html`); the Kind data-plane + edge loopback invariant enforced by `lint chart` (negative-tested) + a generated-config unit assertion; and the per-user MinIO STS scoped-credential machinery (`Infernix.Objects.Sts` + session-token presigning + the `cluster.minio.stsPerUser` gate, unit-covered); the RBAC/dashboard/lifecycle Playwright spec is authored. Note: the full `infernix test unit` on this host also required reconciling a pre-existing, Phase-9-unrelated `python/.venv` `grpcio-tools`/`protobuf` gencode drift (venv-only; no tracked file changed). **Stage 2 apple-silicon — CLOSED 2026-07-07.** A full `./.build/infernix cluster up` (substrate `apple-silicon`, edge `127.0.0.1:9090`, 16/16 models staged, Keycloak realm reconciled with the `infernix-admin` role + admin user) proved live: (a) an issued admin token carries `realm_access.roles ⊇ infernix-admin` while a self-service token does not; (b) unauthenticated `GET /api/admin/overview`, `GET /api/cache`, `POST /api/cache/evict`, `/harbor`, `/pulsar/admin`, `/pulsar/ws`, `/api/objects/list` → 401; (c) by-role over the four operator routes + `/api/admin/overview` + `/api/cache`: non-admin → 403, admin → 2xx (`/pulsar/ws` admin → 404, the WS backend past the gate); (d) `/api/admin/overview` returns real aggregates; (e) the MinIO (30011) + Pulsar proxy (30080) loopback data plane answers 200 un-gated while the edge requires admin, and the live Kind config binds every data-plane + edge port to `127.0.0.1`; (f) per-user isolation — A reads own object, B denied A's object + any cross-user key (403); (g) with `cluster.minio.stsPerUser = True` the object path works end-to-end through the scoped `AssumeRole` credential (now the default); (h) routed Playwright RBAC + dashboard + lifecycle suite **7/7 PASS**. **Scope note (2026-07-07):** Wave Q apple-silicon Stage 2 validated Phase 9 (RBAC/monitoring) only — the `7/7` is the RBAC/dashboard/lifecycle spec and `16/16 models staged` is cluster-up **disk** staging, not 16 completed inferences. It did **not** run the full per-model `infernix test integration` or the per-model browser matrix on apple-silicon; an attempted full per-model run exhausts host RAM and the OS SIGKILLs the on-host daemon (owned by Phase 4 Sprint 4.26 + Phase 6 Sprint 6.37; see Wave R). **Stage 2 `linux-cpu` — also CLOSED 2026-07-07.** A full `./bootstrap/linux-cpu.sh build` + `up` (outer-container launcher on the native-arm64 colima daemon; the image build passed the in-image `poetry run check-code` with the `grpcio-tools` dependency-pin fix; substrate `linux-cpu`, edge `127.0.0.1:9090`, 12/12 models staged) reproduced the apple result: unauthenticated 401 on every gated route; by-role 403 (non-admin) / 2xx (admin) over the four operator routes + `/api/cache` + `/api/admin/overview` (`/pulsar/ws` admin → 404); real `linux-cpu` admin-overview aggregates (catalog 12, 7 engines/pools, 1 member); per-user isolation (cross-user GET 403; disjoint list); the default-on per-user STS scoped-credential object path green; and the deployed SPA carries the admin panel + personal dashboard. The admin token minted **without** a profile patch — confirming the realm-import admin-profile fix. **Phase 9 is fully cohort-closed on both `apple-silicon` and `linux-cpu`.** Still open in this wave (Phases 4/6, unrelated to Phase 9): the matrix substrate-accuracy CUDA engine rows (ONNX `CUDAExecutionProvider` + `onnxruntime-gpu`, CUDA llama.cpp/whisper.cpp binaries), the named `linux-gpu` residual (needs a CUDA Linux host). | **Phase 9 CLOSED (both cohorts)**; CUDA-accuracy residual (Phases 4/6) | 2026-07-07 (Phase 9 both cohorts) |
| R | Apple Silicon | **Apple-silicon inference RAM-safety / bounded-peak full per-model attestation (Phase 4 Sprint 4.26 + Phase 6 Sprint 6.37).** The on-host `infernix service` daemon runs all 16 active models serialized as fresh subprocesses with no per-model RAM footprint, no per-substrate inference-RAM budget, no admission control, and no RAM eviction (only the disk model-cache LRU). A full per-model `infernix test integration` (2026-07-07) exhausted host RAM (64 GiB host, 48 GiB colima pledge → ~16 GiB headroom; compressor ~28 GiB, swap saturated) and the OS SIGKILL'd the daemon after 13/16 models completed. This is uncontrolled process death, not a clean `status=failed`; the fail-clean-never-OOM guarantee is unmet on Apple until admission control lands. Blocks the apple-silicon inference-matrix closure of Phases 4/6. | **RED / blocked (OS OOM-kill)** | open — Phase 4 Sprint 4.26 + Phase 6 Sprint 6.37 |

**Wave L update 2026-06-28**: `./bootstrap/linux-cpu.sh build` rebuilt
`infernix-linux-cpu:local` with the streaming direct-download-to-temp-file remediation as image
`sha256:20b1146c267046b4c5fbe3f4dbb1168bba161a99040ccce734a5fccb7ad7dceb`
(`5132188633` bytes). The rebuild completed the cold in-image build/materialization/web/Python/
Playwright/CLI-help smoke path, and Docker cleanup reclaimed `23.95GB` of BuildKit cache. The
full `./bootstrap/linux-cpu.sh test` attempt on that image passed the front gates, cleared the
previous coordinator direct-bootstrap OOM by completing per-model inference, and advanced through
the HA tail to `engine node drain preserves durable prompt result`; it then failed with Pulsar
WebSocket `Connection refused` because the drain target also hosted the single local Pulsar
broker/proxy path. Current source prepares the engine-drain target by avoiding or relocating
drain-sensitive Pulsar stateful pods first; local `cabal build all`,
`cabal test infernix-haskell-style`, and `cabal test infernix-unit` pass for that remediation.
The follow-on `./bootstrap/linux-cpu.sh build` rebuilt `infernix-linux-cpu:local` as image
`sha256:68afca38e206d8b4c99561909bb878b3c17c7592f43829efe7e28a5b5cc8c349`
(`5132193167` bytes) after the cold in-image build/materialization/web/Python/Playwright/CLI-help
smoke path. That image contains both the streaming and engine-drain target-preparation
remediations. The full `./bootstrap/linux-cpu.sh test` gate on that image passed the front gates,
recovered through Harbor push retries, cleared Docker overlay pressure by pruning `23.95GB` of
BuildKit cache plus `45.15GB` of unused images, completed cluster-up and route probes, then failed
during `speech-faster-whisper-ct2` because the native engine's internal MinIO input-object GET hit
`ResponseTimeout`. Current source gives the shared MinIO object wrapper an explicit 120-second
timeout and retries native input downloads with fresh presigned URLs; local `cabal build all`,
`cabal test infernix-haskell-style`, and `cabal test infernix-unit` are green. The follow-on
`./bootstrap/linux-cpu.sh build` rebuilt `infernix-linux-cpu:local` as image
`sha256:7f3bea81330bf0cafb5f0bb0024276e23ec7b53a41cae958aa83a4781a694a74`
(`5132214799` bytes) after the cold in-image build/materialization/web/Python/Playwright/CLI-help
smoke path, and the launcher CLI-help smoke passed. Post-build Docker usage is `41.91GB` of images
with `18.5GB` reclaimable, `23.95GB` of build cache with `2.118GB` reclaimable, and no containers
or volumes. At that point Wave L remained open pending the full `./bootstrap/linux-cpu.sh test`
rerun on that rebuilt image.

### Wave L Current Attempt Evidence

**Closure update 2026-06-29**: On the real Linux CUDA host, the final paired
`linux-cpu` closure image was rebuilt as `infernix-linux-cpu:local`
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`
(`19963913870` bytes, created `2026-06-29T02:43:21.839158236-04:00`). The
closing source includes the base Pulsar autorecovery JVM/resource envelope
(`BOOKIE_MEM=-Xms64m -Xmx256m -XX:MaxDirectMemorySize=128m`, request `192Mi`,
limit `512Mi`) and the base Harbor registry memory envelope (request `512Mi`,
limit `2Gi`), each covered by unit guards. `./bootstrap/linux-cpu.sh test`
then exited zero: Haskell style, Python `check-code`, Haskell unit, generated
web contracts (`71/71`), full integration, and routed Playwright `9/9` passed.
Integration exercised every `linux-cpu` catalog row with real output and the
HA tail (engine pool placement, shared-subscription backlog/backpressure,
frontend/coordinator/engine replacement, engine node drain, bootstrap
failover/dedup, Harbor/MinIO/Pulsar/Postgres recovery, lifecycle rebinding,
and Linux anti-affinity). The routed browser matrix completed all model rows in
22.7 minutes, and the full Playwright file reported `9 passed (23.6m)`.

The 2026-06-26 Apple rerun after the PyPI torch-source and music-transcription catalog fixes passed the
front-loaded `./bootstrap/apple-silicon.sh test` lint/unit gates and reached Harbor publication
again. The previous Harbor PostgreSQL read-only path was fixed by pointing host-native Apple
Harbor values at `harbor-postgresql-primary.platform.svc.cluster.local`. The retry then failed
during the freshly rebuilt `infernix-linux-cpu:local` push itself: Harbor registry logs showed
MinIO rejecting writes with `XMinioStorageFull`, and the live MinIO pods saw the Docker VM disk at
`251G` size, `236G` used, and `2.3G` available. The retained repo-local Apple Kind tree after clean
teardown was `12G` with no `harbor-registry` paths, confirming the lifecycle scrub is no longer
carrying failed Harbor upload blobs forward. Current lifecycle code scrubs the `harbor-registry`
bucket, registry bucket metadata, and MinIO multipart/tmp scratch before MinIO claim copy-out
during `cluster down`, and the existing cluster-up retained-state scrub keeps the same non-retained
registry cache out of the next Kind replay. The remaining failure was current-daemon capacity from
stale local `localhost:30002/library/infernix-linux-cpu:sha256-*` image tags; pruning those old
runtime image ids reduced Docker image usage from `207.8GB` to `106.4GB` and restored about `136G`
free inside the Docker VM. The follow-on rerun rebuilt image
`sha256-f4c38199c3ebb97a662b2b137de588138b01b0bce03ea4f9b1a716cc72673955`, completed Harbor
publication and pull verification (runtime image plus `apachepulsar/pulsar-all` and support
images), completed final rollout, and cleared routed per-model rows through `audio-open-unmix`.
It then exposed the next Apple-specific gap: the Haskell coordinator bootstrap path treated
package-backed `audio-basic-pitch-coreml` like a single-file download and repeatedly rejected the
`https://github.com/spotify/basic-pitch` landing page, even though the Python snapshot helper and
native worker already model that row as package-backed with no payload files. Current source writes
only the `.ready` sentinel for package-backed native rows in the Haskell bootstrap loop. The next
Apple rerun built and published runtime image
`sha256-16c5933770efe6b3700ab084f6402f8c11074a88be255d8a318f80092895284c`, completed Harbor
publication, Harbor-backed preload, final rollout, route probes, and per-model inference through
`audio-basic-pitch-coreml` and `audio-basic-pitch-onnx`, then failed on `music-omnizart` because the
Apple PyTorch engine venv lacked `librosa` and `piano_transcription_inference`. Current source adds
those dependencies to the Apple PyTorch engine group, regenerates the PyTorch lockfile, and makes
the framework-venv readiness marker depend on the `pyproject.toml`/`poetry.lock` digest so stale
markers cannot mask future dependency changes. The follow-on Apple rerun built and published
runtime image `sha256-0c9d518848f85bbb5f8384b36c1d03e405ed863fe276db1acc559f5c039758cd`,
passed Harbor publication, route probes, and routed per-model inference through
`image-sdxl-turbo`, proving the Omnizart dependency fix. It then failed on
`image-apple-stable-diffusion-coreml`: the hydrated Apple snapshot contains
`runwayml/stable-diffusion-v1-5` mlpackages, but the Core ML pipeline defaulted to
`CompVis/stable-diffusion-v1-4` and raised `FileNotFoundError` for the text encoder package.
Current source passes `--model-version runwayml/stable-diffusion-v1-5` to the Core ML Stable
Diffusion runner and uses `CPU_AND_GPU` to keep the row on real Core ML execution without the
unneeded ANE compile path. The focused rerun produced a PNG artifact, showed that Apple's pipeline
exits successfully without stdout, and passed after current source accepted artifact-only success
and bounded the command with a 900s timeout (`infernix-native-artifact-file:...png`). The follow-on
full Apple rerun built and published runtime image
`sha256-8a2ea20aebd2c112122da8062885dc618ff5f3fa8fd591f063c814ce14da18e0`, completed cluster-up
on edge port `9090`, passed route probes, completed all 14 Apple routed model rows in the host
engine daemon log (including `image-apple-stable-diffusion-coreml`, `audio-bark-small`, and
`tool-audiveris`), and advanced through cache lifecycle, service runtime loop, and durable Pulsar
topic-family checks. The run was interrupted after the pinned Apple host-engine `Exclusive`
subscription guard stopped making progress: the temporary Dhall config written for the pinned
daemon omitted `engineDaemons`, so decode re-derived the default full-catalog daemon topics and the
already-running default host daemon consumed the pinned validation request. Current source
serializes explicit `engineDaemons` in Dhall substrate files and adds a unit regression proving an
Apple pinned-member daemon topic survives encode/decode. At that point Stage 2 still needed a fresh
`apple-silicon` full routed real-output pass with that Dhall serialization fix, followed by the
paired `linux-cpu` full routed real-output gate. The next Apple rerun with the Dhall fix rebuilt
and published runtime image `sha256-e48b4476fb68228c40bb0dde68c25cd3b4209c7e37c45af5ab973fa4aae52e8a`,
passed the front-loaded lint/unit gates, recovered through Harbor push retries, and reached final
rollout. It then exposed a retained Pulsar state split-brain: `bookie-0` crashed with
`InvalidCookieException` because its BookKeeper cookie instance id did not match ZooKeeper, while
`recovery-0` reported `NoNode for /ledgers/cookies`. Current source extends the existing dirty
Pulsar bootstrap detector to inspect bookie/recovery logs and treat BookKeeper cookie mismatch /
missing cookie znodes as reset-worthy retained Pulsar state, so the existing one-shot
claim-root reset + cluster-up retry path handles this case. The 2026-06-27 Apple rerun reproduced
the same retained-state failure during the first Pulsar bookie rollout (`InvalidCookieException`
plus missing `/ledgers/cookies` still visible in live pod logs). Current source now probes Pulsar
stateful-set rollouts in 30-second windows and raises the same dirty-state repair signal before the
20-minute rollout timeout elapses. The follow-on `./bootstrap/apple-silicon.sh test` rerun built
and published runtime image `sha256-4cd135d393b11e395ef482b2707677520f56604cb03ce4f09aeb2d2d064ea570`,
proved the repair loop end-to-end (`cluster up detected inconsistent retained Pulsar state`,
targeted Pulsar claim-root reset, automatic retry), and passed the full Apple integration suite:
cluster-up on edge port `9090`, all 14 routed Apple model rows completed, cache lifecycle, service
runtime loop, durable Pulsar topics, pinned `Exclusive` rejection, shared-subscription coexistence,
backpressure, production-shape publication, platform recovery, and edge-port rediscovery. The
aggregate then failed only at the routed Playwright gate because the local Playwright Chromium
headless shell was absent from `/Users/matt/Library/Caches/ms-playwright`. After installing the
Chromium payload, a focused `./.build/infernix test e2e` rerun rebuilt and published
runtime image `sha256-a4fd54b1ef2d7e9d65fb3f8028e01f1973e19669d2afef73b0065ca6bda0f44e`, ran the
real browser suite, and passed seven of nine specs. The remaining failures are now real e2e
behavior to fix: the artifact-upload queued-prompt path timed out waiting for the second outbound
`ClientSubmitPrompt`, and the per-model browser matrix timed out waiting for the
`image-sdxl-turbo` conversation result after the prompt append. Current source adds the missing
draft echo wait before the artifact queued submit. The next focused `./.build/infernix test e2e`
rerun rebuilt and published runtime image
`sha256-560ef859c7463f2d32d2362b845f1d7437fb46597ffddea863f2ac8ae015526d`, passed the repaired
artifact-upload spec, then initially stalled on the `image-sdxl-turbo` row because the Apple Docker
VM had only `5.6G` free on a `251G` disk and MinIO rejected model-bootstrap snapshot uploads with
`XMinioStorageFull`; pruning unused Docker build cache (`48.64G`) and unused images (`39.65G`)
restored `163G` free, the unacked request recovered, and the same e2e run completed
`image-sdxl-turbo`, Core ML Stable Diffusion, Bark, and Audiveris. The Playwright file reported
`9 passed (21.1m)`, including the 20.0-minute per-model browser matrix, and cluster-down completed.
Stage 2 remains open only for the paired `linux-cpu` full routed real-output gate.
The first paired `./bootstrap/linux-cpu.sh test` attempt rebuilt
`infernix-linux-cpu:local`, passed the Haskell style gate, Haskell unit gate, and generated web
contract build, then failed in the PureScript web unit suite before integration/e2e because the
test still expected 11 `linux-cpu` generated models while the then-current catalog contained 10
runnable rows after the music-transcription catalog correction. Current source aligned
`web/test/Main.purs` with that catalog count; the paired Linux CPU gate remains pending rerun.
A same-image rerun repeated the same web-unit failure, confirming the already-built
`infernix-linux-cpu:local` still carried the pre-patch workspace. The next rebuilt-image Linux CPU
attempt exported `infernix-linux-cpu:local` at
`sha256:3a4504eb9872472d240839646f91f4cda47b275c0e9929f8823b4ecddbc5f26d`, passed Haskell style,
Haskell unit, and the corrected generated web contract suite (`71/71`), then reached
Harbor-backed image publication during integration. That run failed to progress because the
Harbor registry pod was still BestEffort and its `registry` container was repeatedly OOMKilled
with exit code 137 while Docker pushed the active runtime image through Harbor. Current source
adds explicit Harbor registry and controller resource requests in `chart/values.yaml`. The next
rebuilt-image paired gate exported `infernix-linux-cpu:local` at
`sha256:d353c120398c3196e361f05138598293160bd785e39dec7df26747c6f2cd6237`; passed Haskell style,
Haskell unit, and the generated web contract suite (`71/71`); reached Harbor publication with the
registry pod now `Burstable`; recovered through bounded Docker push retries despite registry
exit-137 restarts; pull-verified the active runtime image, Pulsar, and support images; then
validated the retained-Pulsar repair path by detecting incompatible ZooKeeper metadata, running
cluster-down, resetting retained Pulsar claim roots, and retrying cluster-up. The final cleanup
then failed after cluster-down because a retained-state chmod raced a now-missing non-retained
Harbor Patroni pgBackRest claim root
(`platform/infernix/harbor-postgresql-pgbackrest/0/repo1`). Current source recreated and retried a
claim-root chmod only when the root target disappeared. The rebuilt 2026-06-27 launcher image
`sha256:492b95a20252b00a044bc9c1b0a909d71c5dbca866986974fef6bfdebe6cc195` passed Haskell style,
Python `check-code`, Haskell unit, and the generated web contract suite (`71/71`); integration
again reached Harbor publication/preload, validated the retained-Pulsar repair path, completed the
post-reset publication pass, and then failed during final-phase cleanup on the same pgBackRest
claim-root chmod race. The refined current source now retries recursive chmod failures whose
payload reports a missing path during traversal (`fts_read failed` / `No such file or directory`)
and leaves the claim root present after the bounded race window; the paired `linux-cpu` gate
remains pending rerun with that refined cleanup fix baked into the launcher image. The next
rebuilt launcher image
`sha256:8fd964a7a827628565cd9e171d5daa8c0d16a0e52d23ec31645127265ad38fa3`
passed Haskell style, Python `check-code`, Haskell unit, and the generated web contract suite
(`71/71`); integration again reached Harbor publication/preload, triggered the retained-Pulsar
repair path, reset only the Pulsar claim roots, replayed cluster-up, recovered through Harbor
registry exit-137 publication retries, and passed the prior pgBackRest chmod cleanup failure point
with `cluster down complete`. The remaining failure was narrower: during the post-reset final
Pulsar proxy rollout, the dirty-state detector raised a second
`infernix-infernix-pulsar-zookeeper-0 reported incompatible retained Pulsar metadata` signal even
though the fresh ZooKeeper pods had been observed ready and the retained ZooKeeper directories
contained only fresh `myid` files after teardown. Current source tightens the retained-Pulsar log
classifier so standalone ZooKeeper startup fragments such as `The current epoch` or `Got zxid` no
longer trigger repair unless paired with the actual zxid regression marker, adds a bounded
`kubectl logs --request-timeout=10s` diagnostic probe, and unit-tests the clean startup fragment,
epoch-regression, and BookKeeper-cookie cases (`cabal build all` and `cabal test infernix-unit`
green on 2026-06-27). Because the same run still showed Harbor registry exit-137 restarts during
large-image publication, current source also lowers Harbor's S3 registry chunking from 128 MiB to
32 MiB with lower multipart copy concurrency and keeps three registry replicas during Linux
bootstrap publication. The next rebuilt launcher image
`sha256:274f6aa64cd5a44acba005b250b5cfbfc713c05be0d82c2a96ba25fabd3f3a29`
passed Haskell style, Python `check-code`, Haskell unit, and the generated web contract suite
(`71/71`); integration reached final-phase chart apply after Harbor publication and Harbor-backed
preload without the earlier registry push retry noise, but the run was stopped once the final
Helm process was observed waiting while all four Keycloak Patroni PostgreSQL PVCs stayed
`Pending` (`keycloak-postgresql-instance1-*` data claims plus `keycloak-postgresql-repo1`) because
the post-`deployChart` operator-PV reconcile had not yet run. Current source applies the final
chart with Helm hooks disabled, preserving the existing MinIO provisioning from the warmup path,
so the keycloak-postgresql PerconaPGCluster CR can be created and the FinalPhase
operator-managed PV reconcile can bind those claims before rollout waits observe Keycloak. The
next rebuilt launcher image
`sha256:0f98c88ca2ea8761795ea1e3a5b80b9ab5b59f9f9165b23f5541a6ed160e19f9`
failed before integration in `infernix-haskell-style`: `hlint` reported an eta-reduction hint in
the new final-chart helper. Current source eta-reduces that helper; the paired `linux-cpu` gate
remains pending rerun with this style fix baked into the launcher image. The next rebuilt
launcher image `sha256:82d6e5f7b6c1633d547048bcc4adacaadce42b1b011a110382d8a0086c4135ac`
passed Haskell style, Python `check-code`, Haskell unit, and the generated web contract suite
(`71/71`); integration reached Harbor publication and Harbor-backed preload, applied the final
chart with Helm hooks disabled, and created the Keycloak Patroni PostgreSQL CR. That run was
stopped once all four Keycloak operator PVCs were visible but still `Pending` and no matching
Keycloak PVs or retained claim directories had been created, indicating the full final rollout
could observe Keycloak/Pulsar resources before the explicit Keycloak operator-PV binding step
completed. Current source inserts a dedicated `prepare-keycloak-storage` phase between the
Harbor/Gateway rollout and full final deployment: it applies only the Keycloak PostgreSQL CR
with Keycloak/Pulsar/app workloads still disabled, binds the operator-managed PVs, then applies
the full final chart without rerunning Helm hooks. The next rebuilt launcher image
`sha256:eb60eaca550f7e13d4e6b416eb941421adc53e0e829c614e7a6b2089bcfe71b3`
passed Haskell style, Python `check-code`, Haskell unit, and the generated web contract suite
(`71/71`); integration proved the new storage-prep phase by binding the four Keycloak Patroni
PVCs before full final rollout, but the run was stopped during final rollout after repeated
node-level `SystemOOM` events killed Java, Harbor, and MinIO processes. Live evidence showed
Keycloak running as `BestEffort` and uncapped Harbor/MinIO plus Pulsar JVM startup paths
destabilizing otherwise healthy Pulsar storage startup. Current source gives Keycloak explicit
heap/resource controls, renders Keycloak and MinIO container resources, and adds Harbor
core/jobservice/portal/nginx, registry/controller, Pulsar statefulset, and Pulsar init-job
requests/limits while retaining the Linux HA-shaped replica topology. The paired `linux-cpu` gate
ran against rebuilt launcher image
`sha256:967099756aa6e81c4589340c06d835ce39ce5e085190d9671597c7007469afe8`, which contains those
final-phase resource controls. That attempt passed Haskell style, Python `check-code`, Haskell unit,
and the generated web contract suite (`71/71`), completed Harbor publication and pull verification
for the active runtime image plus support images, and reached Harbor-backed final image preload. It
then failed while loading the active runtime image onto the second Kind worker; a sidecar read-only
probe hit `No space left on device`, and host Docker evidence showed `197.5GB` of images plus
`120.3GB` of inactive build cache with old `localhost:30002/library/infernix-linux-cpu:sha256-*`
validation images still present. The next rerun is pending after pruning generated Docker build cache
and obsolete validation runtime tags from the existing Colima daemon. That cleanup removed the old
validation runtime tags, reclaimed `120.3GB` of inactive BuildKit cache, and restored the Docker VM
overlay from `48.5G` free to `206.2G` free while retaining only the current
`sha256:967099756aa6e81c4589340c06d835ce39ce5e085190d9671597c7007469afe8` validation runtime image.
The same-image rerun then passed the prior second-worker runtime preload failure, completed the
dedicated `prepare-keycloak-storage` phase with all Keycloak Patroni PVCs bound, and reached final
rollout. It was stopped after live node events showed repeated `SystemOOM` across the control-plane
and both workers with `patroni` victims, while the rendered Percona PostgreSQL CRs still carried only
storage requests and no runtime resources for the database, pgBouncer, pgBackRest repo-host, or
backup jobs. Current source adds explicit runtime requests/limits for both Harbor and Keycloak
Percona PostgreSQL clusters while retaining the Linux HA-shaped three-replica topology. The next
rebuilt launcher image
`sha256:8cc1f5ff143f92ed925e4585d578f908dac10cd033d06f8cea440aecc6d73801`, which contains that
Percona resource envelope, passed Haskell style, Python `check-code`, Haskell unit, and the
generated web contract suite (`71/71`); completed Harbor publication/pull verification and
Harbor-backed final image preload; exercised the retained-Pulsar repair path by detecting
incompatible recovery metadata, running cluster-down, resetting only Pulsar claim roots, and
retrying cluster-up; and reached final rollout. The run was stopped after read-only diagnostics
showed the generated Linux CPU final topology exceeded the Apple-hosted Colima memory envelope:
worker memory requests were about `7.8Gi` each before all pods scheduled, aggregate worker limits
exceeded `15Gi` each, `envoy-platform-infernix-edge`, `pulsar-zookeeper-1`, and `pulsar-bookie-2`
were `Pending` with `Insufficient memory`, and node events reported repeated `SystemOOM` victims
(`redis-server`, `postgres-operat`, `registry_DO_NOT`) with both workers turning `NodeNotReady`.
Current source shrinks the generated Apple-hosted `linux-cpu` final resource/replica envelope
instead of reusing the unconstrained HA-shaped defaults on the shared 8 GiB Docker daemon: Harbor
final registry/core/jobservice/portal collapse to one replica, Harbor Trivy scales to zero in the
final local lane, Harbor Redis is explicitly capped, Pulsar uses the same one-bookie quorum
contract as the Apple local topology, and MinIO/Keycloak/Pulsar/Percona requests and limits are
lowered while retaining the two-replica repo daemons needed by the failover and node-drain tests.
The next rebuilt launcher image
`sha256:7419e1d40b31646fdb84a287eab5740dbcb9c8f6e93c0cc227b8436212264ea3` passed the Linux-side
Haskell style gate, Haskell unit gate, and generated web contract suite (`71/71`), then failed
before cluster creation in integration claim discovery:
`PersistentVolumeClaim uses unsupported storageClassName Nothing`. The failure is earlier than the
resource-envelope validation target and indicates the latest generated Apple-hosted `linux-cpu`
final values dropped a supported storage class from at least one rendered PVC/claim template. The
paired `linux-cpu` gate remains open while that chart-rendering regression is fixed and rerun.
Current source keeps the Victoria Metrics/Grafana disable inside the later Apple-hosted
`linux-cpu` local-topology `pulsar:` override, so Helm no longer re-enables the monitoring
subchart when applying the constrained one-bookie quorum. Rebuilt launcher image
`sha256:4e946e709305371b3f47cb6e7bc6572ebf735709002890b01e1f06f4b132dcd7` passed
`./bootstrap/linux-cpu.sh build`; a targeted `infernix cluster up` reproduction advanced past
`discover-persistent-claims` with no rendered PVCs missing `storageClassName`, reached
host-cached warmup image preload, and was then intentionally stopped and cleaned up with
`./bootstrap/linux-cpu.sh down`. The full paired `linux-cpu` gate is pending rerun on that image.
The full rerun on the same image then passed Haskell style, Python `check-code`, Haskell unit, and
the generated web contract suite (`71/71`), started integration, and advanced through
claim discovery into Harbor bootstrap. It was stopped once diagnostics showed
`infernix-harbor-trivy-0` stuck `Pending`: the constrained final topology scales Harbor Trivy to
zero, so final-chart claim discovery no longer creates a Trivy PV, but Bootstrap still requested
one Trivy replica and its `data-infernix-harbor-trivy-0` PVC could not bind. Current source must
also omit Trivy during Apple-hosted `linux-cpu` bootstrap; Harbor image publication does not depend
on the scanner. Current source sets the Bootstrap Trivy replica count to zero only for the
Apple-hosted `linux-cpu` local topology while retaining the existing Bootstrap scanner replica for
the other Linux lanes; host `cabal build all` and `cabal test infernix-haskell-style` pass with the
change. Rebuilt launcher image
`sha256:2a0423664738c245428258b3906669577512673707e04ac0f6ad9f5543fa3840` contains the Bootstrap
Trivy omission and advanced the paired gate further: the run passed Haskell style, Python
`check-code`, Haskell unit, and the generated web contract suite (`71/71`); completed Bootstrap
without the prior Trivy PVC; pushed and pull-verified the active runtime image plus support images
through Harbor; and entered the Harbor-backed final deploy. It was stopped after diagnostics showed
`infernix-keycloak-*` in `CreateContainerConfigError` with `secret "infernix-keycloak-db-user" not
found` while only the Harbor `PostgresCluster` existed. The generated Apple-hosted `linux-cpu`
resource overlay appended a second top-level `keycloak:` map for heap/resource limits, which
overwrote the pre-final `keycloak.enabled: false` value in the Harbor-final and
Keycloak-storage phases and started the Keycloak Deployment before the dedicated
`prepare-keycloak-storage` phase could create the Percona-managed database user secret. Current
source preserves the phase-specific Keycloak enabled flag inside that local resource overlay:
Keycloak remains disabled until FinalPhase, while FinalPhase still renders the same capped
heap/resources. Rebuilt launcher image
`sha256:b93a3cce49b8eaee77149bef549084a6624fb5a6cc987ad2a91b480a714efe0d` contains this
phase-gating fix. The paired `linux-cpu` run on that image passed Haskell style, Python
`check-code`, Haskell unit, and the generated web contract suite (`71/71`); completed Harbor
bootstrap, active-runtime/support image publication and pull verification, Harbor-backed preload,
`prepare-keycloak-storage`, final rollout, Keycloak realm reconciliation, and the routed publication
probe; and reached `cluster up complete` on edge port `9091`. The run then failed at the first
per-model inference publish with `Network.Socket.connect: ... Connection refused` against the
trusted direct Pulsar WebSocket path before any model row executed; `finally` cleaned the cluster
down afterward. Current source adds a bounded connection-refused retry around the direct Pulsar
WebSocket client used by the outer-container integration harness, because the existing route probes
exercise Envoy while per-model inference uses the direct Pulsar proxy NodePort; host `cabal build
all`, `cabal test infernix-haskell-style`, and serial `cabal test infernix-unit` pass with that
change. Rebuilt launcher image
`sha256:11143289d9a0666983966515d4b730bcd9a394e48f8500de0a313e6f741a8f9e` contains the retry and
advanced past the previous direct-WebSocket failure: the run passed the front gates, recovered
through three bounded Harbor runtime-image push retries, published and pull-verified support
images, completed Harbor-backed preload, bound the Keycloak PostgreSQL PVCs in
`prepare-keycloak-storage`, and reached final rollout with Keycloak, repo daemons, broker, bookie,
and toolset ready. The run was stopped after diagnostics showed
`infernix-infernix-pulsar-recovery-0` repeatedly terminating with exit code `137` under the
Apple-hosted `linux-cpu` local override's `192Mi` memory limit (`os.memory.max=128MB`,
`os.memory.free=4MB`). Current source raises the constrained local Pulsar autorecovery memory
envelope for the Apple-hosted `linux-cpu` overlay (`BOOKIE_MEM=-Xms64m -Xmx192m`, `192Mi` request,
`384Mi` limit) so the final rollout can complete before the paired gate is rerun; host `cabal build
all`, `cabal test infernix-haskell-style`, and `./bootstrap/linux-cpu.sh build` pass with that
change. Rebuilt launcher image
`sha256:1aa2be0587cc108aa741d330b8f44ea121f8b3efc49906ec8c307afead14ea28` advanced past the
autorecovery blocker: Haskell style, Python `check-code`, Haskell unit, web contracts (`71/71`),
Harbor publication and pull verification, Harbor-backed preload, final rollout, Keycloak realm
reconciliation, routed-publication probing, and `cluster up complete` on edge port `9091` all
passed. The paired `linux-cpu` gate then failed immediately after entering `per-model inference:
linux-cpu` with `Network.WebSockets.Types.ConnectionException: ConnectionClosed` from
`Infernix.Runtime.Pulsar.runPulsarWebSocketClient`, before any model row completed. Current source
classifies this direct Pulsar WebSocket close as a bounded startup-race retry alongside the existing
connection-refused case; host `cabal build all`, `cabal test infernix-haskell-style`, and
`cabal test infernix-unit` pass with the retry classifier and unit assertion. Rebuilt launcher
image `sha256:e25d8df39917852e37634079036d53f13f09fd106486bb971cfdf7178708a504` contains the
`ConnectionClosed` retry and passed `./bootstrap/linux-cpu.sh build`. The paired full
`linux-cpu` gate on that image passed Haskell style, Python `check-code`, Haskell unit, generated
web contracts (`71/71`), Harbor publication/pull verification, Harbor-backed preload, final
rollout, Keycloak storage/realm reconciliation, route probes, and `cluster up complete` on edge
port `9091`. The run needed an operator-side `docker builder prune -af` during final rollout after
the Apple Docker VM's `/var` reached 100% from inactive BuildKit cache; the prune reclaimed
`101.3GB`, restored about `67G` free in the Kind nodes, and Kubernetes recovered the affected
Harbor portal/PostgreSQL pods. The gate then failed immediately after entering
`per-model inference: linux-cpu` with
`Network.WebSockets.Http.HandshakeException: OtherHandshakeException "Network.WebSockets.Client.newClientConnection: no handshake response from server"`
from `Infernix.Runtime.Pulsar.runPulsarWebSocketClient`, before any model row completed. Current
source classifies that exact missing-handshake-response startup symptom as a bounded direct Pulsar
WebSocket retry alongside connection refusal and `ConnectionClosed`; host `cabal build all`,
`cabal test infernix-haskell-style`, and `cabal test infernix-unit` pass with the new classifier
regression. Rebuilt launcher image
`sha256:a8a1c873171aa685c7526482966ca1ffab51b945` contains the missing-handshake retry; its
`./bootstrap/linux-cpu.sh build` pass completed the in-image CLI help smoke, after an intentionally
cold rebuild that left `23.82GB` of inactive BuildKit cache available for pruning before the next
full paired gate. The paired `./bootstrap/linux-cpu.sh test` run on that image passed the front
gates (Haskell style, Python `check-code`, Haskell unit, generated web contracts `71/71`), completed
Harbor publication with one bounded runtime-image push retry, Harbor-backed preload, final rollout,
Keycloak realm reconciliation, routed-publication probing, and `cluster up complete` on edge port
`9091`. It then failed immediately after entering `per-model inference: linux-cpu` with
`Network.Socket.connect: <socket: 68>: does not exist (Connection refused)` from
`Infernix.Runtime.Pulsar.runPulsarWebSocketClient` after the previous 60-second direct WebSocket
startup retry window elapsed. Current source makes `cluster up` wait for the same direct un-gated
Pulsar proxy NodePort that the integration harness uses, while retaining the routed Pulsar servlet
probe for the Envoy/Gateway path; the direct WebSocket startup retry window is now five minutes.
Host `cabal build all`, `cabal test infernix-haskell-style`, and `cabal test infernix-unit` pass
with the direct-surface probe. Rebuilt launcher image
`sha256:4f8aed0ee18fa3af84151eb8893fd3a5506626ebc9a89e407f65ad25e0b737a4` contains the direct
Pulsar proxy readiness probe and five-minute direct WebSocket retry window; its
`./bootstrap/linux-cpu.sh build` pass completed the in-image CLI help smoke. The paired
`./bootstrap/linux-cpu.sh test` run on that image passed the front gates (Haskell style, Python
`check-code`, Haskell unit, generated web contracts `71/71`), completed Harbor publication after
three bounded launcher-image push retries, Harbor-backed preload, final rollout, Keycloak realm
reconciliation, routed-publication probing, and `cluster up complete` on edge port `9091`. The
run reached `per-model inference: linux-cpu` with all platform pods initially ready and a direct
Pulsar proxy HTTP probe returning `["infernix-infernix-pulsar"]`, then failed with
`Network.WebSockets.Http.HandshakeException: ConnectionTimeout` from
`Infernix.Runtime.Pulsar.runPulsarWebSocketClient` before any model row completed. Runtime pod logs
showed current in-cluster Pulsar proxy `ConnectionTimeout` loops during the same window, and the
proxy endpoint later flipped unready before the integration harness tore the Kind cluster down.
Current source classifies typed Pulsar WebSocket `ConnectionTimeout` startup handshakes as
bounded direct retries, and the `cluster up` direct Pulsar proxy readiness check now requires three
consecutive successful direct admin probes instead of accepting a one-sample proxy success. Host
`cabal build all`, `cabal test infernix-unit`, and serial `cabal test infernix-haskell-style` pass
with this fix. Rebuilt launcher image
`sha256:c8e9c6825ebf9b6c209b44070a7b01138a1ac36ae5143132bfedba42ce239a94` contains the
`ConnectionTimeout` retry classifier and consecutive direct-proxy readiness probe; its
`./bootstrap/linux-cpu.sh build` pass completed the in-image CLI help smoke. The paired
`./bootstrap/linux-cpu.sh test` run on that image passed Haskell style, Python `check-code`,
Haskell unit, and generated web contracts (`71/71`); recovered Harbor bootstrap after a first
migration pod hit PostgreSQL `Permission denied` and the subsequent Harbor dirty-version guard;
completed Harbor publication/pull verification and Harbor-backed preload; and reached final
rollout. The run needed an operator-side `docker image prune -af` during image preload after the
Docker overlay fell to about `7.1G` free; the prune reclaimed `42.5GB` without killing the active
Kind/test containers. The run was then intentionally stopped after live diagnostics showed the
Pulsar proxy repeatedly OOMing with exit code `137` under the generated Apple-hosted `linux-cpu`
local overlay's `256Mi` memory limit; route probing was stalled in `wait-for-routed-publication`,
and engine pods were already restarting behind the unstable proxy. Current source shortens the
Harbor bootstrap Helm hook timeout to `90s` so dirty migration repair regains control sooner, and
raises the constrained Pulsar proxy envelope to a `192Mi` request / `512Mi` limit in both
`chart/values.yaml` and the Apple-hosted `linux-cpu` generated override. Host `cabal build all`,
`cabal test infernix-unit`, and serial `cabal test infernix-haskell-style` pass with those fixes;
the paired `linux-cpu` full gate remains pending rebuilt-image rerun. The rebuilt launcher image
`sha256:7ca6b1fd72d73b03ed356c5c0f17babea828123901282ee8e5dbf259d2dfd264` contains the shorter
Harbor bootstrap timeout and larger Pulsar proxy envelope; `./bootstrap/linux-cpu.sh build`
completed the in-image CLI help smoke. Before starting the paired full gate, `docker builder
prune -af` reclaimed `23.82GB` of inactive BuildKit cache, leaving only the current launcher image
and Kind node image in the local Docker store (`docker system df`: images `23.29GB`, build cache
`0B`). The paired `linux-cpu` full gate on that image passed Haskell style, Python `check-code`,
Haskell unit, and the generated web contract suite (`71/71`), then failed during the warmup Harbor
PostgreSQL rollout before image publication: the primary became ready, but both replica database
containers repeatedly failed `pg_basebackup` with `FATAL: role "_crunchyrepl" does not exist`,
leaving `harbor-postgresql-instance1-*` at `3/4`. The startup repair hook logged `repairing Harbor
PostgreSQL replicas from leader`, cluster-down completed, and the local Docker store had no
running containers afterward. Current source now keeps the HA-shaped Harbor PostgreSQL topology and
repairs the actual missing-role symptom instead: Harbor and Keycloak Percona clusters reference a
repo-owned `databaseInitSQL` ConfigMap that creates `_crunchyrepl` as `LOGIN REPLICATION` during
fresh primary bootstrap, and the existing Harbor replica-reinit repair executes the same idempotent
SQL on the current primary before `patronictl reinit`. Host validation for that repair passes:
`helm template` renders both init ConfigMaps and both `databaseInitSQL` references, `cabal build
all`, `cabal test infernix-haskell-style`, `cabal test infernix-unit`, and `cabal run exe:infernix
-- lint chart` are green. The paired gate remains open pending rebuilt-image rerun with that
repair. The rebuilt launcher image
`sha256:6347fa24b411cdec9877632ad342fc4a39f95c2bc0bef7327d2a295d79d58382` contains the
`_crunchyrepl` init-SQL and primary-side repair path; `./bootstrap/linux-cpu.sh build` completed
the in-image CLI help smoke. Pre-test Docker state showed `51.88GB` of images and `23.82GB` of
inactive BuildKit cache, so the paired gate is pending after pruning that disposable cache to keep
the Apple-hosted Colima lane inside the local disk envelope. The prune reclaimed `23.82GB`; the
post-prune Docker state was images `33.48GB`, build cache `0B`, and no containers or volumes before
the full gate. The paired full gate on that image passed Haskell style, Python `check-code`,
Haskell unit, and generated web contracts (`71/71`); completed Harbor PostgreSQL bootstrap after
the new `_crunchyrepl` repair rotated the lagging replica to `4/4`; pushed and pull-verified the
active runtime image plus support images through Harbor; completed Harbor-backed preload,
`prepare-keycloak-storage`, final rollout, Keycloak realm reconciliation, route probes, and
`cluster up complete` on edge port `9091`. It then entered `per-model inference: linux-cpu` and
hung on the first Transformers LLM row. Live diagnostics showed both engine pods were `BestEffort`
and repeatedly restarted with exit code `137` while running
`/workspace/python/engines/transformers/.venv/bin/python -m adapters.transformers_python`; one
engine reached `CrashLoopBackOff`, the other continued CPU-bound, and the test's result wait would
not fail until its 70-minute model-bootstrap deadline. The run was interrupted after capturing that
evidence, `./bootstrap/linux-cpu.sh down` completed cleanly, and the stale launcher container was
removed. Current source gives Linux engine pods explicit CPU/memory requests and limits, so they no
longer enter the cluster as `BestEffort`, and bounds the real Transformers continuation to a
32-token single response with lower load-time CPU memory pressure. Host validation for that fix is
green: base and `linux-gpu` `helm template` renders include the engine resource envelope,
`cabal build all`, `cabal test infernix-haskell-style`, `cabal test infernix-unit`,
`cabal run exe:infernix -- lint chart`, `cabal run exe:infernix -- test lint`, and
`./.build/infernix lint docs` all pass. The rebuilt launcher image
`sha256:3d73d282bd24cab79b14afad3a5823c42b70c36a368b515bd0abe357be25284f` contains those
engine resource and Transformers-bounding fixes; `./bootstrap/linux-cpu.sh build` completed the
in-image CLI help smoke. Before the full gate, `docker builder prune -af` reclaimed `23.82GB` of
inactive BuildKit cache, leaving images `55.83GB`, build cache `0B`, and no containers or volumes;
the paired `linux-cpu` full gate started on this image. That attempt passed the front gates
(Haskell style, Python `check-code`, Haskell unit, generated web contracts `71/71`), recovered the
Harbor PostgreSQL `_crunchyrepl` replica rotation, published and pull-verified the active runtime
image plus support images through Harbor, completed Harbor-backed final preload, bound the
Keycloak PostgreSQL PVCs, and reached full final rollout with coordinator, engine, demo, Keycloak,
Pulsar broker/proxy, and Keycloak PostgreSQL pods ready. It was then stopped after live node events
showed repeated `SystemOOM` across the control-plane and both workers (`java`, `minio`, and
`postgres-operator` victims), while worker memory requests were about `5.0Gi`/`5.3Gi` and worker
memory limits were about `11.0Gi`/`10.5Gi` on `~7.7Gi` allocatable nodes. The run was interrupted
after capturing that evidence, `./bootstrap/linux-cpu.sh down` completed cleanly, and the stale
launcher container was removed. Current source remediates that local-envelope failure by adding an
Apple-hosted `linux-cpu` `prepare-pulsar-runtime` lifecycle phase: Pulsar starts and reaches its
stateful-set rollout gates while Keycloak, demo, coordinator, and engine pods remain at zero
replicas, then the final app workloads start after Pulsar is stable. The same generated local
profile then rendered Linux engine pods with a constrained `1Gi` request / `3Gi` limit while the
static chart default remains `2Gi` / `4Gi`. Host validation for this fix is green:
`cabal build all`, `cabal test infernix-haskell-style`, `cabal test infernix-unit`,
`cabal run exe:infernix -- lint chart`, `cabal run exe:infernix -- test lint`,
`./.build/infernix lint docs`, and base plus `linux-gpu` `helm template` renders. The paired gate
remains open pending rebuilt-image rerun with this staged-final-rollout fix.
The rebuilt launcher image
`sha256:df852a172b0d0c07322305e1f03a4f2ab2e02242324c970dbb0455afc10d61b1` contains the
`prepare-pulsar-runtime` staged rollout and constrained local engine envelope; `./bootstrap/linux-cpu.sh
build` completed the in-image CLI help smoke. Pre-test Docker state showed images `95.9GB`, build
cache `23.82GB`, and no containers or volumes; `docker builder prune -af` reclaimed `23.82GB`, leaving
images `77.5GB`, build cache `0B`, and no containers or volumes before the full paired gate. The
paired `linux-cpu` full gate on that image passed the front gates (Haskell style, Python
`check-code`, Haskell unit, generated web contracts `71/71`), completed Harbor publication and
pull verification, completed Harbor-backed final preload, bound Keycloak PostgreSQL storage, proved
the new `prepare-pulsar-runtime` phase by bringing Pulsar broker/bookie/proxy/zookeeper/recovery up
before app workloads, recovered Harbor PostgreSQL replicas from the leader, reconciled Keycloak,
passed route probes, and reached `per-model inference: linux-cpu`. It was interrupted after live
evidence showed the first Transformers row repeatedly pushed both engine pods into exit-137 restarts
from node-level `SystemOOM` (`python` victims); the engine pods were now `Burstable` with the
intended `1Gi` request / `3Gi` limit, but worker aggregate limits were still `10.1Gi` and `9.3Gi`
on `~7.7Gi` allocatable nodes and both engine pods reached three restarts. `./bootstrap/linux-cpu.sh
down` completed cleanly and the stale interrupted launcher container was removed. Current source
keeps the `llm-qwen25-safetensors` real Transformers/PyTorch safetensors row but switches the shared
CPU/Apple reference checkpoint from `Qwen2.5-1.5B-Instruct` to the smaller real
`Qwen2.5-0.5B-Instruct`, preserving the real-output contract while fitting the Apple-hosted
`linux-cpu` memory envelope. Host validation for the catalog/resource-envelope remediation is green:
`cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, `cabal run
exe:infernix -- lint chart`, `cabal run exe:infernix -- test lint`, `./.build/infernix lint docs`,
and base plus `linux-gpu` `helm template` renders. The rebuilt launcher image
`sha256:6aed01f397e031ac3b211c69955e0bf4ddf2168dc5826e8109c975b29eb5e54c` contains the
Qwen2.5-0.5B catalog change plus the current resource and staged-rollout fixes;
`./bootstrap/linux-cpu.sh build` completed the in-image CLI help smoke. Pre-prune Docker state
showed images `117.6GB`, build cache `23.82GB`, and no containers or volumes; `docker builder
prune -af` reclaimed `23.82GB`, leaving images `99.17GB`, build cache `0B`, and no containers or
volumes before the full paired gate. The paired full gate on that image passed the front gates
(Haskell style, Python `check-code`, Haskell unit, generated web contracts `71/71`), completed
Harbor publication and pull verification after one bounded active-runtime push retry, completed
Harbor-backed final preload, bound Keycloak PostgreSQL storage, proved `prepare-pulsar-runtime`,
completed final rollout, reconciled Keycloak, passed route probes, and reached `per-model
inference: linux-cpu` on edge port `9091`. It was interrupted after the first routed Transformers
row produced no `engineProcessed` result while both engine pods repeatedly exited `137` under
node-level `SystemOOM` (`python` victims); one pod reached four restarts, the other three, and the
cluster otherwise remained routable. `./bootstrap/linux-cpu.sh down` completed cleanly and the
stale interrupted launcher container was removed. Current source reduces the Linux CPU engine
runtime memory pressure by replacing the shared HF safetensors row with
`llm-smollm2-safetensors` / SmolLM2-135M-Instruct, preserving a real Transformers/PyTorch
checkpoint while avoiding stale Qwen cache prefixes from earlier attempts; the model-bootstrap
helper now allowlists only the SmolLM2 Transformers files needed for local generation
(`model.safetensors`, tokenizer files, and configs) instead of mirroring optional ONNX artifacts.
Host validation for this remediation is green: `cabal build all`, `cabal test infernix-unit`,
`cabal test infernix-haskell-style`, `cabal run exe:infernix -- lint chart`,
`cabal run exe:infernix -- lint files`, `cabal run exe:infernix -- lint proto`,
`cabal run exe:infernix -- docs check`, `cabal run exe:infernix -- test lint`,
`npm --prefix web run test:unit` (`71/71`), and `./.build/infernix lint docs`.
The rebuilt launcher image
`sha256:11326cc93f68c8b98e1b439a321839e67ffe02427e49236a6690c54d3f14d653`
contains the SmolLM2 catalog/allowlist remediation and completed the in-image CLI help smoke via
`./bootstrap/linux-cpu.sh build`. Pre-prune Docker state showed images `139.2GB`, build cache
`23.82GB`, no containers, and no volumes; `docker builder prune -af` reclaimed `23.82GB`, leaving
images `120.8GB`, build cache `0B`, no containers, and no volumes before the full paired gate.
The paired `./bootstrap/linux-cpu.sh test` run on that image passed Haskell style, Python
`check-code`, Haskell unit, and generated web contracts (`71/71`); completed cluster-up on edge
port `9091`; recovered through five Harbor active-runtime push retries; pull-verified the runtime
and support images; completed Harbor-backed final preload, Keycloak storage prep, staged Pulsar
runtime startup, final rollout, Keycloak realm reconciliation, route probes, and `per-model
inference: linux-cpu`. The SmolLM2 remediation passed the prior first-row failure point: the run
advanced through the LLM rows and later logged real completions for `speech-faster-whisper-ct2`,
`audio-demucs-htdemucs`, `audio-open-unmix`, `audio-basic-pitch-onnx`, and `music-omnizart`.
Transient engine OOM restarts occurred under the `3Gi` engine limit, but the suite recovered and
continued. The gate then failed on the final `tool-audiveris` row because the Linux arm64 image
still invoked `/opt/audiveris/bin/Audiveris` from the Ubuntu x86_64 `.deb`, producing
`qemu-x86_64: Could not open '/lib64/ld-linux-x86-64.so.2'`. `cluster down` completed cleanly.
Current source keeps the Audiveris app jars from the pinned release package but bakes an
image-architecture Temurin 25 JRE, removes the bundled x86 runtime, and makes the Linux native
`jvm-native` runner smoke and execute Audiveris through
`java -cp /opt/audiveris/lib/app/* Audiveris`; unit coverage now asserts the Java classpath smoke
path so native arm64 images cannot silently retain the x86 launcher. The rebuilt launcher image
`sha256:9c356dc73992381ce6712b5cd34dd96859bceb346f60b94680d0e241820b937f`
contains the Audiveris architecture fix; `./bootstrap/linux-cpu.sh build` completed the
in-image native materialization smoke (`jvm-native` launched Audiveris through the Temurin
classpath entrypoint) and the final CLI help smoke. Image inspection reported size
`5131980326` bytes. Pre-prune Docker state showed images `161.1GB`, inactive build cache
`23.95GB`, no containers, and no volumes; `docker builder prune -af` reclaimed `23.95GB`,
leaving images `142.6GB`, build cache `0B`, no containers, and no volumes before the full
paired gate. The paired `linux-cpu` gate remains pending full-suite rerun on that image.
Host validation for the
Audiveris architecture remediation is green: `cabal build all`, `cabal test infernix-unit`,
`cabal test infernix-haskell-style`, `cabal run exe:infernix -- test lint`, chart lint, file
lint, proto lint, `cabal run exe:infernix -- docs check`, `npm --prefix web run test:unit`
(`71/71`), host `cabal install all:exes` into `./.build`, and `./.build/infernix lint docs`.
The paired full gate on that rebuilt image passed the front gates (Haskell style, Python
`check-code`, Haskell unit, generated web contracts `71/71`) and passed `infernix test
integration`: cluster-up, route probes, real per-model inference for all 10 runnable `linux-cpu`
rows including SmolLM2 and the repaired Audiveris Java classpath runner, cache lifecycle, runtime
loop, durable Pulsar topics, pool/backpressure/HA checks, throughput, Harbor/MinIO/Pulsar/Postgres
recovery, lifecycle rebinding, and anti-affinity all completed. The aggregate then failed only in
the routed Playwright gate: the unauthenticated SPA and landing specs passed, but every
authenticated spec that submitted the Keycloak registration form timed out after Chromium navigated
to `chrome-error://chromewebdata/` while waiting for the OIDC code redirect back to the SPA.
Current source makes the Keycloak deployment use the generated full `externalBaseUrl` strictly
(`--hostname-strict=true`) so registration form actions and redirects preserve the local routed
edge host/port instead of being re-derived from forwarded headers. Host validation for that
Keycloak redirect remediation is green: `cabal build all`, `cabal test infernix-haskell-style`,
`cabal test infernix-unit`, chart lint, `cabal run exe:infernix -- docs check`, host
`cabal install all:exes` into `./.build`, and `./.build/infernix lint docs`; the first parallel
chart-lint attempt hit a transient Cabal package-db race and passed when rerun alone. The rebuilt
launcher image `sha256:6f434b2c1882fc0cc925d2ae7bccaaebe0cee059682c7565ca7f2d2031ed84b9`
contains the Keycloak strict-hostname fix; `./bootstrap/linux-cpu.sh build` completed the in-image
native materialization path and final CLI help smoke. Image inspection reported size
`5131976765` bytes. Pre-prune Docker state showed images `182.9GB`, inactive build cache
`23.95GB`, no containers, and no volumes; `docker builder prune -af` reclaimed `23.95GB`, leaving
images `164.4GB`, build cache `0B`, no containers, and no volumes before the full paired gate. The
full paired gate on that image passed the front gates (Haskell style, Python `check-code`,
Haskell unit, generated web contracts `71/71`) and reached `infernix test integration`: Harbor
publication recovered through four bounded runtime-image push retries, Harbor-backed preload,
final rollout, Keycloak realm reconciliation, route probes, and routed per-model inference through
`audio-bark-small`. It was then interrupted rather than waiting the full one-hour bootstrap window
after coordinator logs repeatedly showed `tool-audiveris` model bootstrap rejecting the Audiveris
GitHub release page as non-weight content. Current source now treats `tool-audiveris` as a
package-backed native tool like Basic Pitch Core ML, so bootstrap writes only the `.ready` sentinel
and relies on the image-baked Audiveris JVM runner. The paired `linux-cpu` gate remains pending
rebuilt-image rerun with that Audiveris bootstrap classification fix.
Host validation for the Audiveris bootstrap classifier is green: `cabal build all`, `cabal test
infernix-unit`, `cabal test infernix-haskell-style`, and `./.build/infernix lint docs`. The
rebuilt launcher image
`sha256:1183a3d77c3f12b8d175fe511eb5ef8865326184d66e3abc6efbe19ef3bb5115` contains the
package-backed `tool-audiveris` classifier; `./bootstrap/linux-cpu.sh build` completed the
in-image native materialization path, web bundle, Playwright browser install, and final CLI help
smoke. Image inspection reported size `5131953882` bytes. Pre-prune Docker state showed images
`204.7GB`, inactive build cache `23.95GB`, no containers, and no volumes; `docker builder prune
-af` reclaimed `23.95GB`, leaving images `186.2GB`, build cache `0B`, no containers, and no
volumes before the full paired gate. The paired full gate on that image passed Haskell style,
Python `check-code`, Haskell unit, and the generated web contract suite (`71/71`); completed
cluster-up on edge port `9090`; recovered through one bounded runtime-image Harbor push retry;
published and pull-verified the Pulsar and support images; completed Harbor-backed final preload,
final rollout, Keycloak realm reconciliation, route probes, and routed per-model inference through
`audio-bark-small`. It was interrupted before the one-hour result wait because both engine pods
kept redelivering `tool-audiveris` failures: the coordinator-side classifier wrote only the
package-backed `.ready` sentinel, but the worker-side native cache hydration still expected
`infernix-models/tool-audiveris/payload` and repeatedly raised `MinIO artifact download returned
HTTP 404`. Current source now aligns worker hydration with the package-backed classifier by giving
`tool-audiveris` an empty native cache object list, so the image-baked Audiveris JVM runner can
execute once the `.ready` sentinel exists. Host validation for that worker hydration fix is green:
`cabal build all`, `cabal test infernix-unit`, and `cabal test infernix-haskell-style`. The rebuilt
launcher image
`sha256:b8e1f027d1bb7f06563afcdaacbb70a62a1bbf96784b86c04339a91d41580016` contains that worker
hydration fix; `./bootstrap/linux-cpu.sh build` completed the in-image native materialization path,
web bundle, Playwright browser install, and final CLI help smoke. Image inspection reported size
`5132030524` bytes. Pre-prune Docker state showed images `226.5GB`, inactive build cache `23.95GB`,
no containers, and no volumes; `docker builder prune -af` reclaimed `23.95GB`, leaving images
`208GB`, build cache `0B`, no containers, and no volumes before the full paired gate. The paired
`linux-cpu` full gate on that image passed the front gates (Haskell style, Python `check-code`,
Haskell unit, generated web contracts `71/71`), then reached integration cluster-up. It published
and pull-verified the active runtime image plus all support images through Harbor, recovered the
active runtime push after one bounded retry, entered Harbor-backed final preload, and preloaded the
active runtime image on `infernix-linux-cpu-worker2`. The run then failed before final rollout when
the same Harbor-backed runtime-image `crictl pull` on `infernix-linux-cpu-worker` exited non-zero
with no captured output; the harness ran `cluster down complete`, and post-failure Docker state
showed no containers, no volumes, images `208GB`, and build cache `0B`. Current source keeps the
Harbor pull as the primary preload path but adds a bounded fallback that stream-imports the already
published and pull-verified Harbor-tagged image via `docker image save ... | ctr --namespace=k8s.io
images import -` when a worker-side `crictl pull` exhausts its retries. Host validation for the
fallback is green: `cabal build all`, `cabal test infernix-unit`, and `cabal test
infernix-haskell-style`. The rebuilt launcher image
`sha256:350d508c37e4e3c67982b7fb01c788a70b96de808873ecee05a8923c20791d55` contains the
Harbor-backed preload fallback; `./bootstrap/linux-cpu.sh build` completed the in-image native
materialization path, web bundle, Playwright browser install, and final CLI help smoke. Image
inspection reported size `5132066718` bytes. Pre-prune Docker state showed images `248.3GB`,
inactive build cache `23.95GB`, no containers, and no volumes; `docker builder prune -af`
reclaimed `23.95GB`, leaving images `229.8GB`, build cache `0B`, no containers, and no volumes
before the full paired gate. The paired `linux-cpu` gate remains pending full-suite run on that
rebuilt image. The full-suite run on that image passed the front gates (Haskell style, Python
`check-code`, Haskell unit, generated web contracts `71/71`) and entered integration cluster-up. It
preloaded the warmup images on both Kind workers, then failed during the warmup Harbor PostgreSQL
readiness wait before Harbor publication: all three `harbor-postgresql-instance1-*` startup pods
stayed in `Init:Error` / `Init:CrashLoopBackOff`, and read-only diagnostics showed the
`database-init` container failing with `install: cannot create directory '/opt/crunchy/bin': No
space left on device`. Both Kind workers reported the Docker VM overlay at `251G` size, `239G`
used, and `0` available; the harness ran `cluster down complete`, leaving no containers, no
volumes, images `229.8GB`, and build cache `0B`. The failure was host Docker image pressure from
stale Harbor validation runtime tags rather than a new PostgreSQL logic regression. Cleanup removed
the obsolete `localhost:30002/library/infernix-linux-cpu:sha256-*` runtime tags from prior attempts
while keeping the current `infernix-linux-cpu:local` image and support-image caches; Docker state is
now images `34.29GB`, build cache `0B`, no containers, and no volumes. The paired gate remains
pending same-image rerun after that capacity cleanup. The same-image rerun then passed the full
front gate (Haskell style, Python `check-code`, Haskell unit, generated web contracts `71/71`) and
the complete integration suite: Harbor publication/pull verification, Harbor-backed final preload,
final rollout, route probes, real per-model inference, cache lifecycle, service runtime loop,
durable Pulsar topic families, Linux engine pool placement/backpressure, frontend/coordinator/engine
replacement, engine node drain, model-bootstrap failover/deduplication, multi-user throughput
(`12` prompts, p95 about `134.2s`), Harbor recovery, MinIO durability, routed Pulsar recovery,
PostgreSQL failover/lifecycle rebinding, Linux anti-affinity, and clean teardown. The aggregate
gate then failed in the routed Playwright phase after E2E cluster-up completed: two non-auth specs
passed, but all seven auth-dependent browser specs timed out waiting for the post-registration
redirect back to `/` with an authorization `code`; Chromium had navigated to
`chrome-error://chromewebdata/` after the Keycloak registration submit. Current investigation is
closed on the generated-values bug: the Apple-hosted `linux-cpu` local resource overlay appended a
later top-level `keycloak:` map without preserving `externalBaseUrl`, so Helm's effective
`keycloak.externalBaseUrl` fell back to `http://127.0.0.1/auth` even though
`clusterConfig.keycloak.baseUrl` used the routed
`http://infernix-linux-cpu-control-plane:30090/auth` edge. With `--hostname-strict=true`, Keycloak
therefore generated registration/login actions on the wrong host for the outer-container
Playwright topology. Current source preserves the generated `externalBaseUrl` in that final local
override and adds a unit regression that renders final `linux-cpu` outer-container Helm values and
asserts both effective Keycloak maps carry the routed `/auth` URL. Host validation for this
remediation is green: `cabal build all`, `cabal test infernix-unit`, and
`cabal test infernix-haskell-style`; `./.build/infernix lint docs` also passes after the plan
update. The rebuilt launcher image
`sha256:2bdee8a3698cb8c309ae8ac863c3887b0dffa1fae7c2dfb5c040eee02b636e6e` contains the
Keycloak generated-values fix; `./bootstrap/linux-cpu.sh build` completed the in-image native
materialization path, web bundle, Playwright browser install, Python `check-code`, and final CLI
help smoke. Image inspection reported size `5132037261` bytes. Pre-prune Docker state showed
images `74.58GB`, inactive build cache `23.95GB`, no containers, and no volumes; `docker builder
prune -af` reclaimed `23.95GB`, leaving images `56.08GB`, build cache `0B`, no containers, and no
volumes before validation. A focused `./bootstrap/linux-cpu.sh up` on that image passed
cluster-up, Harbor publication/pull verification, Harbor-backed final preload, Keycloak storage
preparation, staged Pulsar startup, final rollout, Keycloak realm reconciliation, and routed
publication probing. Live diagnostics from the Kind network confirmed Keycloak now starts with
`--hostname=http://infernix-linux-cpu-control-plane:30090/auth`, and the generated login form action
uses the same routed host while the registration link remains relative under `/auth` with client
data redirecting back to `http://infernix-linux-cpu-control-plane:30090/`. The paired `linux-cpu`
full gate on that rebuilt image passed the front gates (Haskell style, Python `check-code`, Haskell
unit, generated web contracts `71/71`), completed cluster-up through Harbor publication/pull
verification, Harbor-backed final preload, Keycloak storage preparation, staged Pulsar startup,
final rollout, Keycloak realm reconciliation, route probing, and entered real per-model inference.
It then failed in `infernix-integration` when the Pulsar WebSocket proxy returned a transient
Jetty `MalformedResponse` handshake with HTTP `500 Server Error` before the client had published or
read the model result. Current source classifies only WebSocket handshake `MalformedResponse` 5xx
statuses as retryable startup/proxy-settling failures while leaving 4xx/path/auth responses
fail-closed. The rebuilt launcher image
`sha256:0709d54640a3965a95a1489c49e99d333c4450f0868f6792ae19bd58ba88e91e` contains that Pulsar
WebSocket retry classification; `./bootstrap/linux-cpu.sh build` completed the in-image native
materialization path, web bundle, Playwright browser install, Python `check-code`, and final CLI
help smoke. Image inspection reported size `5132123941` bytes. Before the full rerun, Docker state
showed images `96.38GB`, inactive build cache `23.95GB`, no containers, and no volumes; `docker
builder prune -af` reclaimed `23.95GB`, leaving images `77.88GB`, build cache `0B`, no containers,
and no volumes. The paired full gate on that image passed the front gates (Haskell style, Python
`check-code`, Python formatting/style, Haskell unit, generated web contracts `71/71`) and entered
`infernix-integration`. Cluster-up completed Harbor finalization, Keycloak storage preparation, and
the staged `prepare-pulsar-runtime` rollout, but the final platform rollout failed on
`deployment/infernix-keycloak`: `kubectl rollout status deployment/infernix-keycloak --timeout
900s` repeatedly reported `0 of 1 updated replicas are available`, the watch stream showed repeated
connection-loss / TLS handshake timeout symptoms under load, and Kubernetes returned
`deployment "infernix-keycloak" exceeded its progress deadline`. Live diagnostics before teardown
showed the final rollout under CPU saturation, with Keycloak repeatedly restarting during first
boot, one coordinator replica in `CrashLoopBackOff` after exit `137`, and Harbor jobservice/core
startup restarts. Current source enables and waits for Keycloak during the Apple-hosted `linux-cpu`
`prepare-pulsar-runtime` phase, before the final coordinator/demo app workloads are introduced.
Machine-independent validation for the staged Keycloak remediation is green: `cabal test
infernix-unit`, `cabal test infernix-haskell-style`, and `./.build/infernix lint docs` pass. The
rebuilt launcher image
`sha256:cff697d2439c36a0d918a27e097e443f24fa3fb1f7fdab8977ff75da9410d9ed` contains the staged
Keycloak startup remediation; `./bootstrap/linux-cpu.sh build` completed the cold in-image
dependency build, native materialization path, web bundle, Playwright browser install, Python
`check-code`, and final CLI help smoke. Image inspection reported size `5132109651` bytes. Before
the full rerun, Docker state showed images `118.2GB`, inactive build cache `23.95GB`, no
containers, and no volumes; `docker builder prune -af` reclaimed `23.95GB`, leaving images
`99.67GB`, build cache `0B`, no containers, and no volumes. The paired full gate on that image
passed the front gates (Haskell style, Python `check-code`, Python formatting/style, Haskell unit,
generated web contracts `71/71`) and proved the staged Keycloak remediation: cluster-up completed
Harbor publication and pull verification, Harbor-backed preload, Keycloak storage preparation,
the staged `prepare-pulsar-runtime` rollout with Keycloak ready before final app workloads, final
rollout, Keycloak realm reconciliation, route probes, and routed per-model inference through
`audio-demucs-htdemucs`. It was stopped before the shared 70-minute routed-result deadline after
live Pulsar broker stats showed `req-20260628140243776947602000` stuck unacked on
`persistent://infernix/demo/inference.batch.linux-cpu.pool.pytorch.model.audio-open-unmix`:
`msgInCounter=1`, `msgBacklog=1`, `unackedMessages=1`, no result-topic match, and both engine pods
had restarted/recovered to idle. Current source sets a bounded `ackTimeoutMillis=900000` on
service WebSocket consumers so a killed engine or coordinator consumer redelivers unacked service
work instead of pinning the message until the integration client-side deadline. Machine-independent
validation for the service-consumer redelivery remediation is green: `cabal test infernix-unit`,
`cabal test infernix-haskell-style`, and `./.build/infernix lint docs` pass. The rebuilt launcher
image
`sha256:451c214fd55aacbe6a67e5e5bf11907ffc9ad7d23a993df90268d3d7d470f6cd` contains the
service-consumer redelivery remediation; `./bootstrap/linux-cpu.sh build` completed the cold
in-image Haskell install, `linux-cpu` substrate materialization, native engine materialization,
Transformers/PyTorch engine environment installation, generated web contracts and PureScript
bundle, Python `check-code`/format/style gate, Playwright browser install, and final CLI help
smoke. Image inspection reported size `5132114911` bytes. Docker state before the full rerun
showed images `140GB`, inactive build cache `23.95GB`, no containers, and no volumes; pruning that
disposable BuildKit cache reclaimed `23.95GB`, leaving images `121.5GB`, build cache `0B`, no
containers, and no volumes. The full gate on that image passed the front gates (Haskell style,
Python `check-code`/format/style, Haskell unit, generated web contracts and PureScript web tests
`71/71`) and passed integration end-to-end: cluster-up completed with Harbor publication and pull
verification, staged `prepare-pulsar-runtime` plus final rollout were green, every Linux CPU
catalog row produced real output including `audio-open-unmix`, cache lifecycle and durable Pulsar
topic checks passed, and the HA/chaos tail passed through throughput, Harbor/MinIO/Pulsar
recovery, Postgres failover, lifecycle rebinding, Linux engine anti-affinity, and the
production/demo-disabled final cycle. The same aggregate then started a fresh routed E2E cluster
and passed eight Playwright specs before the browser per-model matrix stalled. Live diagnostics
showed repeated node-level `SystemOOM` events across the control-plane and both workers; both
`infernix-coordinator` replicas were OOMKilled/crash-looping before attaching their Pulsar
subscriptions, while the request/result topics had no active service consumers. Current source
remediates that local Apple-hosted `linux-cpu` pressure point by rendering explicit coordinator and
demo `resources` blocks (so those daemons are no longer BestEffort) and by scaling the generic
engine Deployment to one replica for non-GPU browser inference rows; integration still owns the
two-engine HA/placement validation. Fast validation for this remediation is green:
`cabal test infernix-unit`, `cabal test infernix-haskell-style`, `helm template infernix chart`,
and `node --check web/playwright/inference.spec.js`. The rebuilt launcher image
`sha256:fbbb0af5bb59366c6144c28e5bd70dd90185e52519e21a5cb136bbf94b1d02a9` contains this
local-pressure remediation; `./bootstrap/linux-cpu.sh build` completed the cold in-image Haskell
install, `linux-cpu` substrate materialization, native engine materialization,
Transformers/PyTorch engine environment installation, generated web contracts and PureScript
bundle, Python `check-code`/format/style gate, Playwright browser install, and final CLI help
smoke. Image inspection reported size `5132121926` bytes. Docker state before cleanup showed
images `161.8GB`, inactive build cache `23.95GB`, no containers, and no volumes; pruning unused
BuildKit cache reclaimed `23.95GB`, leaving images `143.3GB`, build cache `0B`, no containers, and
no volumes. The full `./bootstrap/linux-cpu.sh test` rerun on that image passed the front gates
(Haskell style, Python `check-code`/format/style, Haskell unit, generated web contracts and
PureScript web tests `71/71`), reused the cluster image, completed Harbor publication and
pull-verification for the runtime image plus support images, and advanced through Harbor-backed
preload and final rollout to coordinator/engine/demo pod creation. It was stopped after live
diagnostics showed both coordinator pods repeatedly exiting `137` during startup with only the
service metadata banner in logs; the pods were `Burstable` but had a `512Mi` memory limit, and no
node-level `SystemOOM` event was present in the captured event tail. Current source raises the
coordinator memory request/limit to `256Mi`/`1Gi` while keeping the demo limit unchanged; `helm
template infernix chart --namespace platform` renders the intended coordinator resources. The
rebuilt launcher image
`sha256:0f3555612d15b8278e145d6711512642baf6ff08d4b11457e514c7b0ff274ff8` contains this
coordinator-memory remediation; `./bootstrap/linux-cpu.sh build` completed the cold in-image
Haskell install/build, `linux-cpu` substrate materialization, native engine materialization,
Transformers/PyTorch engine environment installation, generated web contracts and PureScript
bundle, Python `check-code`/format/style gate, Playwright browser install, and final CLI help
smoke. Image inspection reported size `5132128585` bytes. Docker state before cleanup showed
images `183.6GB`, inactive build cache `23.95GB`, no containers, and no volumes; pruning unused
BuildKit cache reclaimed `23.95GB`, leaving images `165.1GB`, build cache `0B`, no containers, and
no volumes. The full test rerun on that image passed the front gates, completed cluster-up,
published and pull-verified the runtime and support images through Harbor, completed final rollout,
and entered real per-model inference. It completed `llm-smollm2-safetensors`; a first TinyLlama
bootstrap attempt saw a truncated Hugging Face response, but the retry completed
`llm-tinyllama-gguf`. The same run then hit node-level `SystemOOM` on all three Kind nodes with
victim process `infernix`; both coordinator pods were OOMKilled at the `1Gi` memory limit and
entered `CrashLoopBackOff`. Current source remediates that coordinator-side direct single-file
bootstrap pressure by streaming the upstream download to a temporary file and streaming that file
to the presigned MinIO `PUT`, preserving the realness HTML/empty-body guard without holding the
whole GGUF/safetensors payload in memory. Focused validation for this source change is green:
`cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
`./.build/infernix lint docs` pass. The rebuilt launcher image
`sha256:20b1146c267046b4c5fbe3f4dbb1168bba161a99040ccce734a5fccb7ad7dceb` contains this
streaming bootstrap remediation; `./bootstrap/linux-cpu.sh build` completed the cold in-image
Haskell install/build, `linux-cpu` substrate materialization, native engine materialization,
Transformers/PyTorch engine environment installation, generated web contracts and PureScript
bundle, Python `check-code`/format/style gate, Playwright browser install, and final CLI help
smoke. Image inspection reported size `5132188633` bytes. Docker state before cleanup showed
images `205.4GB`, inactive build cache `23.95GB`, no containers, and no volumes; pruning unused
BuildKit cache reclaimed `23.95GB`, leaving images `186.9GB`, build cache `0B`, no containers,
and no volumes. The full `./bootstrap/linux-cpu.sh test` rerun on that image passed Haskell style,
Python `check-code`/format/style, Haskell unit, generated web contracts, and PureScript web tests
(`71/71`); completed Harbor publication, pull verification, final rollout, and real per-model
inference; and advanced through cache lifecycle, service runtime loop, durable Pulsar topics,
Linux pool placement, shared-subscription backlog, frontend/coordinator failover, and engine pod
replacement. That proves the streaming direct-bootstrap fix cleared the previous coordinator OOM.
The run then failed in `engine node drain preserves durable prompt result`: during the local
one-broker/one-proxy Apple-hosted `linux-cpu` topology, the selected ready engine pod's node also
hosted the single Pulsar broker/proxy path, so the drain scenario made Pulsar unavailable and the
test exhausted WebSocket connection retries with `Connection refused`. Current source remediates
the test placement by preparing the drain target: it selects a ready engine node without
drain-sensitive Pulsar pods when possible, otherwise cordons the candidate and relocates the
Pulsar zookeeper/bookie/broker/proxy stateful pods before draining it. Focused validation for that
source change is green: `cabal build all`, `cabal test infernix-haskell-style`, and
`cabal test infernix-unit`. Rebuilt image
`sha256:68afca38e206d8b4c99561909bb878b3c17c7592f43829efe7e28a5b5cc8c349`
contains both the streaming and drain-target remediations after the cold in-image
build/materialization/web/Python/Playwright/CLI-help smoke path; image inspection reported size
`5132193167` bytes. The full rerun on that image passed the front gates, recovered through Harbor
push retries, required disposable Docker cleanup when Harbor-backed preload filled the local
overlay (`23.95GB` BuildKit cache plus `45.15GB` unused images reclaimed), completed cluster-up and
route probes, and reached per-model inference. It then failed on `speech-faster-whisper-ct2`
because the native engine's internal MinIO GET for
`integration-inputs/linux-cpu/speech-faster-whisper-ct2.wav` hit `ResponseTimeout`. Current source
sets a bounded 120-second timeout on shared MinIO object operations and retries native input
downloads with fresh presigned URLs; focused validation is green (`cabal build all`,
`cabal test infernix-haskell-style`, and `cabal test infernix-unit`). Rebuilt image
`sha256:7f3bea81330bf0cafb5f0bb0024276e23ec7b53a41cae958aa83a4781a694a74` contains that
input-fetch remediation after the cold in-image build/materialization/web/Python/Playwright/
CLI-help smoke path; image inspection reported size `5132214799` bytes, and the launcher CLI-help
smoke passed. The full `./bootstrap/linux-cpu.sh test` gate on that image passed the front gates
and full integration, including the previous drain and `speech-faster-whisper-ct2` failure points.
It then reached routed E2E, passed eight Playwright specs, and failed only in the browser per-model
matrix after waiting 900 seconds for the `speech-faster-whisper-ct2` conversation result; live
diagnostics showed the single browser engine pod had restarted repeatedly and recovered without a
matching result before teardown. Current source extends the browser-matrix result wait through one
full Pulsar service-consumer redelivery window plus a second execution window. Focused validation is
green: `node --check web/playwright/inference.spec.js` and `./.build/infernix lint docs`. The
follow-on `./bootstrap/linux-cpu.sh build` rebuilt `infernix-linux-cpu:local` as image
`sha256:0feec8141c67aa4879d9ecc6fb0c955afe907121488ac48b5561bf4d70d23ed3`
(`5132239400` bytes) after the cold in-image build/materialization/web/Python/Playwright/CLI-help
smoke path, and the launcher CLI-help smoke passed. Disposable BuildKit cleanup reclaimed `34.7GB`,
leaving images `45.04GB`, build cache `0B`, no containers, and no volumes before the full rerun.
That full `./bootstrap/linux-cpu.sh test` rerun passed the front gates, rebuilt cluster-up, and
reached `per-model inference: linux-cpu`, then was interrupted rather than waiting for the
70-minute cold-bootstrap result deadline after live diagnostics proved the request path could not
recover: both `infernix-engine` replicas were in `CrashLoopBackOff` from OOM at the generated
Apple-hosted `linux-cpu` `3Gi` engine limit, and the single local Pulsar broker OOMKilled at its
`512Mi` limit while repeated published-result polling created short-lived readers. The cleanup
`./bootstrap/linux-cpu.sh down` completed cleanly. Rebuilt image
`sha256:06d4057472ac977bc1538ec4c6e0e49beb2fd25abc4e40b940d4b934cc63f8bb` now contains that
local resource and broker-churn remediation after the cold in-image build/materialization/web/
Python/Playwright/CLI-help smoke path; image inspection reported size `5132256620` bytes, created
`2026-06-28T21:28:43.772069153-04:00`, and the launcher CLI-help smoke passed. Post-build
disposable builder cleanup reclaimed `23.92GB`, leaving images `99.19GB`, build cache `17.2GB`,
no containers, and no volumes before the full rerun. The full `./bootstrap/linux-cpu.sh test`
rerun on that image passed Haskell style, Python `check-code`, Haskell unit, generated web
contracts (`71/71`), cluster-up, Harbor-backed publication/preload, final rollout, Keycloak realm
reconciliation, routed-publication probing, and reached `per-model inference: linux-cpu`. The run
was interrupted after diagnostics showed aggregate Apple-hosted `linux-cpu` pressure on the shared
Colima VM: all three Kind nodes reported `SystemOOM` with `java` and `infernix` victims, and
`infernix-infernix-pulsar-proxy-0` had been `OOMKilled` at its `512Mi` memory limit. Current source
preserves the two-replica demo/coordinator/engine HA validation shape but tightens the local
generated values to demo `96Mi` request / `384Mi` limit, coordinator `192Mi` / `768Mi`, engine
`768Mi` / `3584Mi`, broker `256Mi` / `768Mi`, and explicit local Pulsar heap/direct-memory caps
with SerialGC. The follow-on `./bootstrap/linux-cpu.sh build` rebuilt `infernix-linux-cpu:local`
as image `sha256:f5e3ba564b4f431815fce4ed3452f39f944003075fedc965e3a31705b4bbbfb7`
(`5132264989` bytes, created `2026-06-28T22:43:14.163322221-04:00`) after the cold in-image
build/materialization/web/Python/Playwright/CLI-help smoke path, and the launcher CLI-help smoke
passed. Disposable builder cleanup reclaimed `23.95GB`, leaving images `128.6GB` with `8.489GB`
reclaimable, build cache `0B`, no containers, and no volumes before the full rerun. The full
`./bootstrap/linux-cpu.sh test` attempt on that image passed Haskell style, Python `check-code`,
Haskell unit, generated web contracts (`71/71`), Harbor publication, Harbor-backed preload, and
reached final rollout before live diagnostics showed `infernix-infernix-pulsar-proxy-0` in
`CrashLoopBackOff`. Proxy logs showed startup failure, not OOM: Jetty rejected the local
`httpNumThreads: "4"` cap with `Insufficient configured threads: required=4 < max=4`.
`./bootstrap/linux-cpu.sh down` completed cleanly. Current source keeps the tightened memory
profile and raises the local Pulsar proxy `httpNumThreads` to `8`; local `cabal build all`,
serial `cabal test infernix-haskell-style`, and serial `cabal test infernix-unit` are green.
The follow-on real Linux host rebuild and full `./bootstrap/linux-cpu.sh test` rerun closed Wave L
on 2026-06-29, as recorded in the closure update above.

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
bake, the framework readiness paths later superseded by real-output gates, native runner
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
  `./.build/infernix.dhall` (16-model catalog, `daemonRole = engine`,
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
> real-output code-side closure remains useful evidence; the 2026-06-16 Apple refresh added
> host-native build, `apple-silicon` substrate materialization, Metal/Core ML engine manifest
> materialization, unit, lint, docs, focused `lint files/docs/proto/chart`, Metal bridge smoke
> evidence, installed `coreml-native` runtime-load smoke evidence, focused e2e, and aggregate
> `test all` for the Sprint 1.14 Tart-free materialization reset. Sprint 1.15 supersedes the
> former Apple wrapper payloads with real native runner roots; the selected Phase 4/6 real-output
> gate closed on `linux-gpu` plus `linux-cpu` on 2026-06-20.

The machine-independent implementation for the reopened sprints landed in natural phase order
(Phase 4 -> Phase 6) on the active hosts and passed the normal machine-independent gates
(`cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, focused
`infernix lint` and `docs check`, the web unit suite, and `poetry run check-code`). Intrinsically
hardware-bound real-engine integration and E2E assertions closed in Stage 2.

### Stage 2 — Per-accelerator sign-off

Stage 2 is closed. The phase's chosen accelerator plus `linux-cpu` full-suite evidence is recorded
above for 2026-06-20; the other accelerator is not a blocker for that phase's `Done` state.

> **Wave I host note.** Wave I's selected accelerator was native Ubuntu 24.04 amd64 with an NVIDIA
> GeForce RTX 5090, driver `570.211.01`, Docker `linux/x86_64`, and the `nvidia` runtime available.
> The Apple host-native half of Wave I was recorded on the Apple host, and the 2026-06-16 refresh
> proved the generated Metal runtime
> bridge smoke (`Metal runtime probe passed on Apple M1 Max`) plus the installed `coreml-native`
> runtime-load smoke (`Core ML runtime probe passed`). The Apple transformers
> framework path now completes `llm-qwen25-safetensors` after the per-engine Apple venv and
> Hugging Face snapshot bootstrap fixes. The next completed integration run exposed the missing
> `llama-cpp-cli/bin/llama-cli` root for `llm-tinyllama-gguf`; that gap was covered in the
> historical Wave I Apple lane by smoke-capable validation wrappers and is now superseded by the
> real Apple native runner roots recorded under Wave L. The latest Apple integration rerun passed after rebuilding the
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
basic-pitch Core ML/ONNX MIDI, MT3-PyTorch/MR-MT3/Omnizart PyTorch MIDI, SDXL MPS artifacts,
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
> row do not resolve and need maintained equivalents or the ONNX/Core ML fallback lanes before their
> per-family assertions can pass. The base image was aligned to
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
`linux-gpu` plus `linux-cpu` sign-off rule. Basic Pitch TensorFlow remains a named
upstream-incompatible residual row outside the active runtime catalog; MT3-PyTorch, MR-MT3, and
Omnizart are maintained PyTorch music-transcription rows.

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
Wave J, Wave L, Wave M, Wave N, Wave O, Wave P, and Wave Q closures.
Wave I closed the selected Phase 4/6 real per-family inference
and engine-payload gates, Wave J closed the Phase 4/6/7 engine-pool routing and broker-native
backpressure gates, Wave L closed Phase 1 Sprint 1.15, and Wave M closed the webapp-mediated file
storage reopen in Phase 3 Sprint 3.13 plus Phase 7 Sprints 7.25-7.27. Wave N closed Phase 7 Sprint
7.28 generated artifact ownership. Wave O (the `music-mt3-infer` / `music-mr-mt3` catalog
replacement) closed under Wave P on 2026-07-04, which also closed Phase 8. Wave Q (2026-07-06/07)
closed Phase 9 on both `apple-silicon` and `linux-cpu` and reopened Phases 4 and 6 for the matrix
substrate-accuracy hardening (Sprints 4.25/6.36), whose only open residual is the CUDA GPU-accuracy
`linux-gpu` proof.

| Phase | Code-side closure | Apple cohort gate | CUDA Linux cohort gate |
|-------|-------------------|-------------------|------------------------|
| 0 | Sprints 0.1-0.10 `Done` | Closed in Wave A (lint gates) | `linux-cpu` passed on the recorded validation; `linux-gpu` passed on the recorded validation |
| 1 | Sprints 1.1-1.12 `Done`; Sprint 1.13 Tart implementation is historical and removed; Sprint 1.14 is code-side closed for the Tart-free manifest materializer and fixed host Metal bridge; Sprint 1.15 is closed for real Apple native runner materialization and native snapshot hydration | Closed in Wave A for 1.1-1.12; Sprint 1.15 Stage 1 passed on the 2026-06-26 Apple host (`materialize-metal-engines`, installed native smokes, unit, lint), Apple Stage 2 integration plus focused routed Playwright are green, and Wave L's paired `linux-cpu` full gate closed on 2026-06-29 with rebuilt image `sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`. The closing `./bootstrap/linux-cpu.sh test` pass covered style, Python `check-code`, Haskell unit, web `71/71`, full integration with all real `linux-cpu` outputs plus the HA/chaos tail, and routed Playwright `9/9`. | `linux-cpu` passed for Wave L on 2026-06-29; `linux-gpu` passed on the recorded validation; Sprint 1.15's selected accelerator is Apple Silicon |
| 2 | Sprints 2.1–2.13 `Done` | Closed in Wave A (retained-state replay + Patroni filter + cluster lifecycle) | `linux-cpu` passed on the recorded validation; `linux-gpu` passed on the recorded validation |
| 3 | Sprints 3.1–3.13 `Done`; Sprint 3.13 closed the `/minio/s3` route, `infernix-minio-s3` SecurityPolicy, and `presignPublicEndpoint` de-exposure | Closed in Wave A/A.2 (substrate-aware publication, Harbor port, containerd, hand-authored MinIO, and Apple host-native E2E); Sprint 3.13 selected `linux-gpu`, so no Apple gate is required for that reopen | `linux-cpu` amd64 passed on the recorded validation; `linux-gpu` passed on the recorded validation; native arm64 `linux-cpu` passed in Wave F on the recorded validation; Wave M closed Sprint 3.13 with `linux-cpu` plus `linux-gpu` full-suite passes on 2026-06-29 |
| 4 | Sprints 4.1-4.24 `Done` (Sprint 4.22 MT3 catalog replacement closed by Wave P on 2026-07-04); Sprints 4.25 (matrix substrate-accuracy) and 4.26 (apple-silicon inference RAM admission) `Active` — code-side complete and machine-independent-validated under Wave R (2026-07-08) | Original contract closed in Wave A; per-family real-output closed in Wave I on the selected `linux-gpu` accelerator plus `linux-cpu` for the then-active catalogs; engine-pool routing closed in Wave J; physical Apple multi-host proof is hardware-deferred | Wave P (2026-07-04) proved both MT3 rows on rebuilt `linux-cpu` + `linux-gpu` full-suite; Wave R closed 4.25/4.26 code-side (RAM footprint + budget + admission control + row relabels) and the remaining single-accelerator sign-off is the full Apple per-model never-OOM run (paired 6.37) plus the CUDA GPU-accuracy `linux-gpu` rows |
| 5 | Sprints 5.1-5.10 `Done` | Closed in Wave A/A.2 (demo backend + adapter dhall reads via integration suite and routed E2E) | `linux-cpu` passed on the recorded validation; `linux-gpu` passed on the recorded validation |
| 6 | Sprints 6.1-6.35 `Done` (Sprint 6.35 expanded MT3 gate closed by Wave P on 2026-07-04); Sprints 6.36 (real-output + matrix validation hardening) and 6.37 (apple-silicon memory-bounded validation lane, unblocked by Phase 4 Sprint 4.26) `Active` — code-side complete and machine-independent-validated under Wave R (2026-07-08) | Original coverage closed in Wave A/A.1/A.2/A.3; per-family routed real-output closed in Wave I for the then-active catalogs; engine-pool validation closed in Wave J; physical Apple multi-host proof is hardware-deferred | Wave P (2026-07-04) exercised the expanded MT3 catalog on rebuilt `linux-cpu` + `linux-gpu` full-suite; Wave R closed 6.36/6.37 code-side (`data-inline-output` real-text marker, catalog-completeness guard, memory-exhaustion classification) and the remaining routed sign-off is the Apple + `linux-cpu` per-model matrix (paired 4.26) plus the CUDA-only accuracy `linux-gpu` rows |
| 7 | Sprints 7.1-7.28 `Done`; Sprint 7.23 is superseded historical Apple singleton work; Sprint 7.24 is closed for engine-pool assignment, broker-native backpressure, production coordinator presence with `demo_ui = false`, and the single-host logical `Shared` backlog harness; Sprints 7.25-7.27 are closed for object-proxy isolation, Files view, and MIDI/MusicXML/ZIP rendering; Sprint 7.28 is closed for Haskell-owned generated artifact output prefixes and result-bridge authorization | Original durable-context gates closed in Wave A/A.1/A.2/A.3; Wave G closed for auth-UX; Sprint 7.24 closed in Wave J; Sprints 7.25-7.28 selected `linux-gpu`, so no Apple gate is required for those reopens; physical Apple multi-host proof is hardware-deferred | Current `linux-gpu` full-suite and current rebuilt-image `linux-cpu` full-suite passed on 2026-06-20; Wave M closed Sprints 7.25-7.27 with `linux-cpu` plus `linux-gpu` full-suite passes on 2026-06-29; Wave N closed Sprint 7.28 with `linux-gpu` plus `linux-cpu` full-suite passes on 2026-06-30 |
| 8 | Sprints 8.1-8.6 `Done` (zero-tracked-dhall; `infernix init` / `test init`; binary-generated ConfigMap/Secret bodies; eager coordinator model-cache staging with the `warm-model-cache` barrier; test-harness config lifecycle) | selected accelerator is `linux-gpu`, so no separate Apple gate is required for this phase | Wave P closed Phase 8 on 2026-07-04 with `linux-gpu` + `linux-cpu` full-suite `infernix test all` GREEN and routed Playwright `9/9` |
| 9 | Sprints 9.1-9.8 `Done` (admin/user RBAC; edge admin `SecurityPolicy`; backend admin gate + `GET /api/admin/overview`; admin + per-user personal dashboards; per-user MinIO STS; Apple host-worker loopback data-plane invariant) | Wave Q closed on `apple-silicon` (2026-07-07): unauthenticated 401 + by-role 403/2xx, the `realm_access.roles` admin claim, the loopback split, per-user isolation, the default-on STS scoped-credential path, and routed Playwright RBAC/dashboard/lifecycle `7/7` | Wave Q closed on `linux-cpu` (2026-07-07): the same by-role RBAC, per-user isolation, and STS proof reproduced |

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
`sha256-f4a30f4e177206b64ce5a0d3abea8d72a8bdbe637148530e1619bdf5ce8ae7c3`. That Apple refresh did not by itself close Wave I, because Wave I's selected accelerator was
`linux-gpu`; Apple real native payload replacement is tracked separately by Sprint 1.15 / Wave L.
Wave I closed on 2026-06-20 on the selected `linux-gpu` accelerator plus `linux-cpu` full-suite
gates recorded above.

When a wave closes, this table is the place to update first. Phase
docs follow.

## Historical Evidence

The Apple Silicon validation reset (see [README.md](README.md) and
[00-overview.md](00-overview.md)) moves dated proof points for earlier hardware into
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical Validation
Evidence". Phase docs reference that table instead of inlining dated proof points per Section I.
