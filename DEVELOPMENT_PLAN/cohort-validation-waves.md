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
> sprint.

## Wave Table

| Wave | Machine | Scope | Status | Closed |
|------|---------|-------|--------|--------|
| A | Apple Silicon (new host) | Apple cohort `cabal test infernix-integration` full-suite PASS; Apple cohort `infernix test e2e` 5/6 PASS; substrate-aware platform closure (engine replicaCount on Apple set to 0, `engineProcessed` trace, host-service-daemon stdout/stderr capture, Patroni retained-state filter, arm64 publication closure, dynamic Harbor host port, containerd `config_path` patch) | Closed | 2026-05-30 |
| A.1 | Apple Silicon (new host) | Sprint 7.15 artifact-upload e2e fix: chat-draft-editor form binds its own `submit` listener at construction time (via MutationObserver) instead of relying on `root` delegation, so `requestSubmit()` on a form detached by an interleaved `renderAll` still fires the handler. Closes the 6/6 e2e gate. | Closed | 2026-05-31 |
| A.2 | Apple Silicon (new host) | Sprint 7.15 per-model browser smoke matrix: `web/playwright/inference.spec.js` adds `browser per-model smoke matrix exercises every catalog model` exercising every selectable model in the demo-config catalog through context create → context-list patch → draft fill → draft-map echo → submit → engine inference → conversation-patch with `inferenceResultStatus = completed`. Closes the 7/7 e2e gate. | Closed | 2026-05-31 |
| A.3 | Apple Silicon (new host) | Sprint 7.14 Apple engine.lock chaos case: `test/integration/Spec.hs` adds `validateAppleEngineLockEnforcement` which spawns a second `infernix service` while the harness-owned first daemon holds the flock at `<runtimeRoot>/engine.lock` and asserts the second invocation exits non-zero with the `engine.lock at … is held by PID …` diagnostic on stderr. Closes the Apple-half of the "one-engine-per-node enforcement" case from `documents/development/chaos_testing.md`. The Linux equivalent (`kubectl scale deployment/infernix-engine --replicas=N+1` leaves one `Pending` with the anti-affinity rejection) is Wave C scope. | Closed | 2026-05-31 |
| B | Apple Silicon (new host) | Apple-side code-side work before the CUDA Linux switch: Sprint 7.14 Linux-owned chaos and throughput cases were intentionally carried into Wave C because they require the real Linux integration lane. | Closed | 2026-05-31 |
| C | CUDA Linux (real Linux host with CUDA hardware, plus the portable `linux-cpu` lane) | Full-suite cohort closure batch on the counterpart cohort: `./bootstrap/linux-cpu.sh` lifecycle on native Linux (portable CPU lane); `./bootstrap/linux-gpu.sh` lifecycle on real CUDA hardware; `docker compose run --rm infernix infernix test all` outer-container full-suite; routed Playwright in-container; validates every phase 1-7 code-side closure already landed on Apple. The remaining Sprint 7.14 Linux-owned code-side cases landed in `test/integration/Spec.hs` as of 2026-06-02: frontend pod replacement, coordinator pod replacement around durable prompt dispatch/writeback, engine pod replacement, engine node drain, model-bootstrap request/ready-event deduplication across coordinator replacement, Linux engine anti-affinity, and multi-user durable prompt throughput. Native `linux-cpu` full-suite validation passed on 2026-06-02 against image digest `sha256:a9f1f19aa9bb492c5186a0f6df8f864ee4e0c900c8209f0434ef64cf6cc821a7`; `linux-gpu` full-suite validation passed on 2026-06-03 against final rebuilt image digest `sha256:fd951113735f94b613a2fa014088f22e89a4df0b78193cd1ec76d6a44e191689`. | Closed | 2026-06-03 |
| D | Either | Phase status promotion sweep: Phases 0-6 move back to `Done` because their only remaining residual was the Wave C cohort gate; Phase 7 remains `Active` for the explicit non-cohort KV-cache/runtime-split/failover work. Browser-level frontend pod-kill reconnect coverage closed with mounted-source `linux-gpu` E2E and the final rebuilt-image `linux-gpu` full gate; the matching rebuilt-image `linux-cpu` residual full gate passed later on 2026-06-03. | Closed | 2026-06-03 |

## Wave A — Closed 2026-05-30

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

## Wave B — Closed 2026-05-31

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
  integration block. Compiled + lint-clean on Apple Silicon 2026-05-31;
  validated during Wave C on the native Linux/CUDA host.

## Wave C — Closed 2026-06-03

The single supported CUDA Linux cohort closure batch. Runs every phase
1-7 code-side closure that landed in Waves A-B, plus the Linux-owned
Sprint 7.14 chaos and throughput cases that required a real Kind-backed
Linux lane. This is the **one** machine change the supported cadence
permits between now and `Done`.

2026-06-02 code-side landing on a native Linux/CUDA host:

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
- First full `./bootstrap/linux-cpu.sh test` attempt on 2026-06-02
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
- The next full `./bootstrap/linux-cpu.sh test` attempt on 2026-06-02
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
  2026-06-02 passed rebuilt-image docs lint, Haskell style, Haskell
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
- The first full `./bootstrap/linux-gpu.sh test` attempt on 2026-06-03
  against rebuilt launcher image digest
  `sha256:1eb0863f8c7cbd19b4d87ab25796535ec592d19e965a1a54351d258d31c1c594`
  passed Haskell style, Haskell unit, PureScript build, web unit tests,
  full `infernix-integration`, and six of seven routed Playwright E2E
  specs. The remaining spec,
  `browser per-model smoke matrix exercises every catalog model`, failed
  after timing out waiting for an inbound WebSocket frame after frame index
  `78`. The cluster tore down cleanly; that attempt left Wave C open
  until the Playwright/runtime stall was investigated, fixed, and rerun.
- The 2026-06-03 Playwright follow-on keeps the per-model browser matrix
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
- The final 2026-06-03 `linux-gpu` closure rerun rebuilt the launcher
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
same worktree state as the passing 2026-06-02 `linux-cpu` gate above.

## Wave D — Closed 2026-06-03

Phase status promotion sweep performed after Waves A-C closed:

- Phases 0-6 return to `Done`; their remaining `Active` status was only
  the cohort-validation residual closed by Wave C.
- Phase 7 remains `Active` because that phase still lists explicit
  non-cohort residuals: KV-cache verification for real KV-cache engines,
  the wider coordinator transport split, and Failover-promotion refinement.
- Browser-level frontend pod-kill reconnect coverage closed after the Wave C
  full gates with a mounted-source `linux-gpu` E2E rerun and then the final
  rebuilt-image full `linux-gpu` gate: the browser test deleted all
  `infernix-demo` pods, waited for replacements, reconnected, resubscribed,
  submitted another prompt, and the final full-gate Playwright file reported
  `7 passed (3.5m)`.
- The matching rebuilt-image `linux-cpu` residual full gate passed later on
  2026-06-03 against launcher image digest
  `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`.
  The run passed Haskell style, Python checks, Haskell unit, PureScript build,
  71/71 web unit tests, full integration, platform recovery checks, and routed
  Playwright E2E (7/7); the Playwright file reported `7 passed (2.1m)`.
- `DEVELOPMENT_PLAN/README.md`, phase headers, `00-overview.md`, and
  `system-components.md` now record the closed cohort status.

### 2026-06-03 residual CPU checkpoint

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

The resumed rebuilt-image `./bootstrap/linux-cpu.sh test` run on 2026-06-03
passed the same residual against digest
`sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`.
Integration included the LinuxCpu chaos/throughput block plus Harbor recovery,
MinIO durability, routed Pulsar recovery, PostgreSQL failover, and PostgreSQL
lifecycle rebinding. The compact throughput matrix reported
`users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12
p95Seconds=76.06613969802856`, and routed Playwright E2E reported
`7 passed (2.1m)`.

This waves document remains as the historical record for the 2026-05-29
host reset and the staged Apple/CUDA closure batches.

## Cadence Rule

Wave numbering operationalizes Section Q of
[development_plan_standards.md](development_plan_standards.md). The
doctrinal rule remains unchanged:

> A phase may stay `Active` with an explicit cohort-pending residual
> after one cohort validates, but it cannot move to `Done` until both
> relevant hardware cohorts have run their full-suite gates against the
> same phase state. The paired closure batch is the preferred
> switching boundary.

Waves enforce that boundary explicitly. Contributors and assistants
land code on the locally available cohort during the active wave; the
counterpart cohort's full-suite revalidation batches in the named
follow-on wave.

## Phase Cohort Status Index

This index records the final cohort status after the Wave C closure. Phase
docs may still be `Active` only when they list non-cohort remaining work.

| Phase | Code-side closure | Apple cohort gate | CUDA Linux cohort gate |
|-------|-------------------|-------------------|------------------------|
| 0 | Sprints 0.1–0.9 `Done` | Closed in Wave A (lint gates) | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03 |
| 1 | Sprints 1.1–1.11 `Done` | Closed in Wave A (integration cluster up + lifecycle on Apple host) | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03 |
| 2 | Sprints 2.1–2.13 `Done` | Closed in Wave A (retained-state replay + Patroni filter + cluster lifecycle) | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03 |
| 3 | Sprints 3.1–3.11 `Done` | Closed in Wave A/A.2 (substrate-aware publication, Harbor port, containerd, hand-authored MinIO, and Apple host-native E2E) | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03 |
| 4 | Sprints 4.1–4.13 `Done` | Closed in Wave A (mounted ClusterConfig + SecretsConfig roundtrip via integration suite) | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03 |
| 5 | Sprints 5.1–5.9 `Done` | Closed in Wave A/A.2 (demo backend + adapter dhall reads via integration suite and routed E2E) | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03 |
| 6 | Sprints 6.1–6.28 `Done` | Closed in Wave A/A.1/A.2/A.3 (lint, style, unit, integration, routed E2E, and Apple engine-lock chaos) | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03 |
| 7 | Sprints 7.1–7.7, 7.10–7.13, and 7.17 `Done`; Sprint 7.8 remains `Active` for real KV-cache/runtime-split work, and Sprints 7.9/7.14/7.15/7.16 await only the phase-level 7.8/docs closure rules after the 2026-06-03 residual sweep | Closed in Wave A/A.1/A.2/A.3 for the listed Apple gates | `linux-cpu` passed 2026-06-02; `linux-gpu` passed 2026-06-03; residual rebuilt-image `linux-gpu` gate passed 2026-06-03 against `sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b`; residual rebuilt-image `linux-cpu` gate passed 2026-06-03 against `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa` |

When a wave closes, this table is the place to update first. Phase
docs follow.

## Retired Historical Evidence

The 2026-05-29 Apple Silicon validation reset (see
[../README.md](../README.md) and
[00-overview.md](00-overview.md)) retired every dated proof point
on the prior hardware. The full inventory of retired evidence lives in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
under "Retired Historical Validation Evidence". Phase docs reference
that table instead of inlining May 2026 dates per Section I.
