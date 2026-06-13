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
> naming the explicit batched-switch boundaries between Apple Silicon
> and CUDA Linux validation. Phase docs reference the active wave and
> pending waves instead of restating cohort residual narrative per
> sprint. Validation-only proof points that require a different physical host are queued here and
> do not trigger ad hoc machine switches outside their named wave. Each open wave runs in two
> stages: **Stage 1** lands the machine-independent code-side closure for the reopened phases in
> natural order on whichever single machine is present, and **Stage 2** runs the paired
> cross-architecture full-suite once per cohort — the only supported machine switch.

## Wave Table

| Wave | Machine | Scope | Status | Closed |
|------|---------|-------|--------|--------|
| A | Apple Silicon (new host) | Apple cohort `cabal test infernix-integration` full-suite PASS; Apple cohort `infernix test e2e` 5/6 PASS; substrate-aware platform closure (engine replicaCount on Apple set to 0, `engineProcessed` trace, host-service-daemon stdout/stderr capture, Patroni retained-state filter, arm64 publication closure, dynamic Harbor host port, containerd `config_path` patch) | Closed | the recorded validation |
| A.1 | Apple Silicon (new host) | Sprint 7.15 artifact-upload e2e fix: chat-draft-editor form binds its own `submit` listener at construction time (via MutationObserver) instead of relying on `root` delegation, so `requestSubmit()` on a form detached by an interleaved `renderAll` still fires the handler. Closes the 6/6 e2e gate. | Closed | the recorded validation |
| A.2 | Apple Silicon (new host) | Sprint 7.15 per-model browser smoke matrix: `web/playwright/inference.spec.js` adds `browser per-model smoke matrix exercises every catalog model` exercising every selectable model in the demo-config catalog through context create → context-list patch → draft fill → draft-map echo → submit → engine inference → conversation-patch with `inferenceResultStatus = completed`. Closes the 7/7 e2e gate. | Closed | the recorded validation |
| A.3 | Apple Silicon (new host) | Sprint 7.14 Apple engine.lock chaos case: `test/integration/Spec.hs` adds `validateAppleEngineLockEnforcement` which spawns a second `infernix service` while the harness-owned first daemon holds the flock at `<runtimeRoot>/engine.lock` and asserts the second invocation exits non-zero with the `engine.lock at … is held by PID …` diagnostic on stderr. Closes the Apple-half of the "one-engine-per-node enforcement" case from `documents/development/chaos_testing.md`. The Linux equivalent (`kubectl scale deployment/infernix-engine --replicas=N+1` leaves one `Pending` with the anti-affinity rejection) is Wave C scope. | Closed | the recorded validation |
| B | Apple Silicon (new host) | Apple-side code-side work before the CUDA Linux switch: Sprint 7.14 Linux-owned chaos and throughput cases were intentionally carried into Wave C because they require the real Linux integration lane. | Closed | the recorded validation |
| C | CUDA Linux (real Linux host with CUDA hardware, plus the portable `linux-cpu` lane) | Full-suite cohort closure batch on the counterpart cohort: `./bootstrap/linux-cpu.sh` lifecycle on native Linux (portable CPU lane); `./bootstrap/linux-gpu.sh` lifecycle on real CUDA hardware; `docker compose run --rm infernix infernix test all` outer-container full-suite; routed Playwright in-container; validates every phase 1-7 code-side closure already landed on Apple. The remaining Sprint 7.14 Linux-owned code-side cases landed in `test/integration/Spec.hs` as of the recorded validation: frontend pod replacement, coordinator pod replacement around durable prompt dispatch/writeback, engine pod replacement, engine node drain, model-bootstrap request/ready-event deduplication across coordinator replacement, Linux engine anti-affinity, and multi-user durable prompt throughput. Native `linux-cpu` full-suite validation passed on the recorded validation against image digest `sha256:a9f1f19aa9bb492c5186a0f6df8f864ee4e0c900c8209f0434ef64cf6cc821a7`; `linux-gpu` full-suite validation passed on the recorded validation against final rebuilt image digest `sha256:fd951113735f94b613a2fa014088f22e89a4df0b78193cd1ec76d6a44e191689`. | Closed | the recorded validation |
| D | Either | Phase status promotion sweep: Phases 0-6 returned to `Done` after their Wave C cohort gate; Phase 7 carried the remaining runtime KV-cache/runtime-split/failover work into Wave E. Browser-level frontend pod-kill reconnect coverage closed with mounted-source `linux-gpu` E2E and the final rebuilt-image `linux-gpu` full gate; the matching rebuilt-image `linux-cpu` residual full gate passed later on the recorded validation. | Closed | the recorded validation |
| E | Linux CPU mounted worktree | Sprint 7.8 closure: process-local runtime KV-cache path wired through `Infernix.Runtime.KVCache`, `executeInferenceWithKVCache`, native worker output, filesystem-topic drain, and WebSocket Pulsar consumption; daemon role orchestration moved into `Infernix.Runtime.Daemon`. Mounted Linux CPU validation passed `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and `cabal test infernix-integration`, including durable dispatcher/result writeback, engine pod replacement, engine node drain, throughput, platform recovery, production-shape deployment, and clean teardown. | Closed | the recorded validation |
| F | Native arm64 Linux CPU execution | Validation-only Phase 3 Sprint 3.12 closure: native `linux/arm64` `linux-cpu` validation through the already selected arm64 Docker daemon on this Apple Silicon machine. Proved Harbor publication, warmup hydration, final Harbor-backed preload, integration, and routed E2E on the native ARM publication path without cross-architecture emulation or Docker-context changes. | Closed | the recorded validation |
| G | Apple Silicon (current host) | Phase 7 auth-UX quad closure: Sprint 7.19 auth-gated landing with dual Keycloak entry points, Sprint 7.20 themed Keycloak login surface, Sprint 7.21 operator console ribbon with edge JWT gating for `/harbor`, `/pulsar/admin`, and `/minio/s3`, and Sprint 7.22 self-service account deletion with MinIO + Pulsar per-user state reaping before Keycloak account removal. | Closed | the recorded Apple host-native validation |
| H | Apple Silicon (current host) | Full current-host Apple lifecycle revalidation from a clean build root (no prior `./.build` artifacts): `cabal install all:exes`; `infernix lint files/docs/chart/proto` plus `infernix docs check`; `infernix test lint` (haskell-style) and `infernix test unit` (`infernix-unit` plus web 71/71); explicit `infernix cluster up` → `cluster status` (77 pods across 2 nodes, `infernix-manual` storage, full Envoy Gateway route set, `pulsar-bridge-to-host-daemon` dispatch) → `cluster down` (retained-state replay, `./.data` preserved) → post-teardown `cluster status` (`clusterPresent: False`, `lifecyclePhase: cluster-absent`); `infernix test integration` PASS; `infernix test e2e` 9/9; aggregate `infernix test all`. The dynamic `choosePulsarHttpPort` chooser shifted the Pulsar host port 30080→30081 around a VS Code-held `127.0.0.1:30080`. Native arm64 throughout (colima `aarch64`, no emulation or Docker-context changes). Published cluster image `infernix-linux-cpu@sha256:7f341cb1629c1d0af9b72db0fef7b89cc1f13d2bd02afe9be1daeed5e7f18454`. | Closed | 2026-06-09 |
| I | CUDA Linux (present host) + paired Apple Silicon | Real per-family inference, engine-artifact manifest/materialization, and headless Apple Metal/Core ML validation. Apple cohort: prove the host Metal runtime bridge, materialize and smoke an Apple native/Core ML artifact without Tart or keychain dependency, assert the corrected `apple-silicon` catalog column, and run `infernix test integration`/`e2e`/`all`. CUDA Linux cohort: re-validate the `linux-cpu` and `linux-gpu` catalog columns, replace the Linux native smoke wrappers with real native payloads, and validate routed per-engine GPU rows. Re-opens Phase 1 (Sprint 1.14; Sprint 1.13 legacy deletion is code-side closed), Phase 4 (Sprints 4.17/4.18 plus the real-output residuals), Phase 6 (Sprints 6.2/6.3/6.6 plus 6.31), and Phase 7 (Sprint 7.23). They return to `Done` only after both cohorts pass their full-suite gates against the same state. **Stage 1 (code-side, single machine, natural order 1→4→6→7, no machine switch):** land the machine-independent implementation plus the machine-independent gates. **Stage 2 (paired cohort batch — the only machine switch):** Apple full-suite once (including headless Metal/Core ML materialization and the `apple-silicon` rows), then CUDA full-suite once (`linux-cpu`/`linux-gpu` rows), against frozen code. | Planned | pending |

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
- The the recorded validation Playwright follow-on keeps the per-model browser matrix
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
- The final the recorded validation `linux-gpu` closure rerun rebuilt the launcher
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
same worktree state as the passing the recorded validation `linux-cpu` gate above.

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
  families, route probes, service runtime loop, cache lifecycle, cluster-state reload, and
  the `apple engine.lock` host-singleton enforcement case. The multi-user throughput and
  pod-replacement/node-drain chaos block remains `runtimeMode == LinuxCpu`-gated and is the
  CUDA Linux cohort's scope.
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
closure; Wave H re-confirmed the Apple cohort only. The present development host is now a native
CUDA Linux host (x86_64 + NVIDIA RTX 5090), so the CUDA Linux cohort is available again for Wave I
without a machine switch — see the present-host note under [Wave I](#wave-i-real-per-family-inference-and-headless-apple-metalcore-ml-builds-planned).

## Wave I: Real Per-Family Inference and Headless Apple Metal/Core ML Builds (Planned)

Wave I is the next paired closure batch. It re-validates the real per-family inference contract and
the headless Apple Metal/Core ML materialization lane that reopens Phases 1, 4, 6, and 7. It runs
in two stages: a machine-independent code-side closure first, then a single paired cohort sign-off.

### Stage 1 — Code-side closure (single machine, natural order, no machine switch)

> **Stage 1 status: reopened on the present CUDA Linux host.** The reopened sprints' code-side
> closure (Phase 1 Sprint 1.14's headless Metal/Core ML materialization lane; Phase 4's
> `ResultFamily` + object-ref plumbing, real native-binary + Python-adapter dispatch, `buildPayload`
> family routing, fail-fast-on-unsupported, plus Sprint 4.18's engine-artifact manifests and matrix
> reconciliation; Phase 6's `ResultFamily`-dispatched assertions, Playwright artifact rendering,
> code-side-closed matrix drift lint, and headless Apple validation gates; Phase 7 Sprint 7.23's
> code-side-closed Pulsar-owned Apple singleton) must pass the machine-independent gate set on this
> host. The prior real-output
> code-side closure remains useful evidence, but it no longer closes Stage 1 after the new research
> reset.

Land the machine-independent implementation for the reopened sprints in natural phase order
(Phase 1 -> Phase 4 -> Phase 6 -> Phase 7) on whichever single machine is present, validating each with the
machine-independent gate set (`cabal build all`, `cabal test infernix-unit`,
`cabal test infernix-haskell-style`, `infernix lint files/docs/chart/proto`, `infernix docs check`,
the web unit suite, and `poetry run check-code`). Stage 1 needs no machine switch: completing one
phase's code-side closure is the gate to begin the next phase's implementation. Intrinsically
hardware-bound deliverables — the Apple-only Metal bridge/materialization smoke of Sprint 1.14, and the
real-engine integration and E2E assertions that pass only on cohort hardware — are named in their
sprints' `Code-side closure` fields and deferred to Stage 2 rather than pre-claimed as
machine-independent.

### Stage 2 — Cohort sign-off (one paired batch, the only machine switch)

After Stage 1 is complete and the code is frozen, run the cross-architecture full-suites once per
cohort against the same state.

> **Present-host note.** The present development host is a native CUDA Linux host (x86_64 + NVIDIA
> RTX 5090), so the **CUDA Linux cohort** half of Stage 2 is producible on this same host with no
> machine switch — Stage 1 plus the CUDA Linux full-suite both close here. The **only** remaining
> machine switch for Wave I is to an Apple Silicon machine for the Apple cohort half (the headless
> Metal/Core ML materialization smoke and the `apple-silicon` rows), which is deferred until that
> wave is intentionally scheduled.

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

> **CUDA Linux cohort — in-progress findings (present host, RTX 5090 / driver 570 / CUDA 12.8).**
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
> during per-model validation. The code-side wiring now includes `engineDaemons`, per-engine batch
> topics, `infernix service --engine-name`, per-engine chart Deployments/PDBs, lifecycle per-engine
> image builds, and Harbor per-engine overlays. The first governed rerun after the single-GPU fix
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
> `infernix internal materialize-linux-native-engines`; the first remaining CUDA Linux blocker is
> replacing those smoke wrappers with real native payloads before the audio-to-MIDI native rows can
> be retried. Current-source mounted linux-gpu validation after that run passes `cabal test
> infernix-unit`, `cabal test infernix-haskell-style`, `cabal build test:infernix-integration`,
> `poetry --directory python run check-code`, `cabal run exe:infernix -- lint docs`, `docs check`,
> `lint files`, `lint proto`, and `lint chart` with the worker's model-cache/MinIO protobuf wiring
> and image-owned native-runner root fallback in place.

Phases 1, 4, and 6 stay `Active` with Wave I as their cohort-pending residual and cannot return to
`Done` until both cohorts pass their full-suite gates against the same state.

## Cadence Rule

Wave numbering operationalizes Section Q of
[development_plan_standards.md](development_plan_standards.md). The
doctrinal rule remains unchanged:

> A phase may stay `Active` with an explicit cohort-pending residual
> after one cohort validates, but it cannot move to `Done` until both
> relevant hardware cohorts have run their full-suite gates against the
> same phase state. The paired closure batch is the preferred
> switching boundary. A validation-only residual is queued as a wave
> and does not require ad hoc machine switching before that wave is
> scheduled.

The operational form of that rule — identical to the copy in Section Q of
[development_plan_standards.md](development_plan_standards.md) — is:

> **Implement in natural phase order on whichever single machine is present. The cohort gate is a
> batched wave — the only supported machine switch — not a per-sprint or per-phase trigger.** Every
> open phase and sprint has two independent axes. *Code-side closure* (Axis 1) is the implementation
> plus the machine-independent gate set — `cabal build all`, `cabal test infernix-unit`,
> `cabal test infernix-haskell-style`, `infernix lint files/docs/chart/proto`, `infernix docs
> check`, the web unit suite, and `poetry run check-code`; completed in natural order on one
> machine, it is the gate to begin the *next* phase's implementation. *Cohort sign-off* (Axis 2) is
> the hardware-specific full-suite — Apple Metal including headless Metal/Core ML materialization,
> and CUDA GPU runs — batched once per closure cycle against frozen code and tracked in
> `cohort-validation-waves.md`; it is the gate for `Done` and never the gate for moving on. **The
> next action for any open phase is always its remaining code-side closure on the machine you
> already have; do not switch machines to "validate the open phase." The machine switch happens only
> at a scheduled wave boundary, once per cohort.** A deliverable that is intrinsically
> hardware-bound — for example the Apple-only Metal runtime bridge probe and Core ML materialization
> smoke of Phase 1 Sprint 1.14 — is named as
> such in its `Code-side closure` field and is exercised inside its cohort's wave, never pre-claimed
> as machine-independent.

Waves enforce that boundary explicitly. Contributors and assistants
land code on the locally available cohort during the active wave; the
counterpart cohort's full-suite revalidation batches in the named
follow-on wave.

## Phase Cohort Status Index

This index records the final cohort status after the Wave C, Wave E, Wave F, Wave G, and Wave H
closures. Wave I (Planned) reopens Phases 1, 4, 6, and 7 for real per-family inference,
engine-artifact materialization, headless Apple Metal/Core ML validation, and Apple host singleton
ownership; those rows carry a pending Wave I residual.

| Phase | Code-side closure | Apple cohort gate | CUDA Linux cohort gate |
|-------|-------------------|-------------------|------------------------|
| 0 | Sprints 0.1-0.10 `Done` | Closed in Wave A (lint gates) | `linux-cpu` passed the recorded validation; `linux-gpu` passed the recorded validation |
| 1 | Sprints 1.1-1.12 `Done`; Sprint 1.13 Tart implementation is historical and removed; Sprint 1.14 manifest materializer code-side cleanup is partially closed while the host Metal bridge remains `Active` | Closed in Wave A for 1.1-1.12; Sprint 1.14 Apple headless materialization smoke pending Wave I | `linux-cpu` passed the recorded validation; `linux-gpu` passed the recorded validation; Sprint 1.14 has no CUDA Linux Metal surface |
| 2 | Sprints 2.1–2.13 `Done` | Closed in Wave A (retained-state replay + Patroni filter + cluster lifecycle) | `linux-cpu` passed the recorded validation; `linux-gpu` passed the recorded validation |
| 3 | Sprints 3.1–3.12 `Done` | Closed in Wave A/A.2 (substrate-aware publication, Harbor port, containerd, hand-authored MinIO, and Apple host-native E2E) | `linux-cpu` amd64 passed the recorded validation; `linux-gpu` passed the recorded validation; native arm64 `linux-cpu` passed in Wave F on the recorded validation |
| 4 | Sprints 4.1-4.17 have prior code-side evidence for real-output and per-engine routing; Sprint 4.18 is code-side closed for engine-artifact manifests, `infernix-engine-artifacts`, Linux native smoke roots, and matrix reconciliation | Original contract closed in Wave A; per-family real-output plus Apple headless materialization pending Wave I | `linux-cpu`/`linux-gpu` original contract passed the recorded validation; real Linux native payload replacement and routed per-engine linux-gpu Stage 2 pending Wave I |
| 5 | Sprints 5.1-5.10 `Done` | Closed in Wave A/A.2 (demo backend + adapter dhall reads via integration suite and routed E2E) | `linux-cpu` passed the recorded validation; `linux-gpu` passed the recorded validation |
| 6 | Sprints 6.1, 6.4, 6.5, 6.7-6.30 `Done`; per-family real-output coverage has prior code-side evidence across 6.2/6.3/6.6; Sprint 6.31 is code-side closed for README/generated-catalog matrix-drift linting and remains `Active` only for cohort evidence | Original coverage closed in Wave A/A.1/A.2/A.3; per-family real-output and headless Apple validation Stage 2 pending Wave I | `linux-cpu` and `linux-gpu` original coverage passed the recorded validation; per-family real-output and real native-payload replacement Stage 2 pending Wave I |
| 7 | Sprints 7.1-7.22 `Done`; Sprint 7.23 is code-side closed for Apple host-engine singleton ownership through Pulsar `Exclusive`/intentional `Failover` | Original durable-context gates closed in Wave A/A.1/A.2/A.3; Wave G closed for auth-UX; Sprint 7.23 live duplicate-consumer Apple singleton gate pending Wave I | `linux-cpu` and `linux-gpu` durable-context gates passed the recorded validation; Sprint 7.23 has no CUDA-only residual beyond regression coverage |

Every Apple cohort gate above was additionally re-confirmed end to end on the Apple cohort host by
Wave H (2026-06-09) from a clean build root: `cabal install all:exes`, the lint/style/unit
gates, the explicit `infernix cluster up` → `cluster status` → `cluster down` lifecycle with
retained-state replay, `infernix test integration` PASS, `infernix test e2e` 9/9, and the
aggregate `infernix test all`. The CUDA Linux cohort hardware was unavailable at Wave H, so the
`linux-cpu` and `linux-gpu` columns retain their prior recorded closure and were out of Wave H
scope. The present development host is now a native CUDA Linux host (x86_64 + NVIDIA RTX 5090), so
the CUDA Linux cohort half of Wave I is producible here without a machine switch; only the Apple
cohort half remains a switch.

When a wave closes, this table is the place to update first. Phase
docs follow.

## Historical Evidence

The Apple Silicon validation reset (see [README.md](README.md) and
[00-overview.md](00-overview.md)) moves dated proof points for earlier hardware into
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical Validation
Evidence". Phase docs reference that table instead of inlining dated proof points per Section I.
