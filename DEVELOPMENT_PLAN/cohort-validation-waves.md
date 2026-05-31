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
| B | Apple Silicon (new host) | Apple-side code-side work that remains before the CUDA Linux switch: Sprint 7.15 artifact-upload e2e fix; Sprint 7.15 per-model smoke matrix; Sprint 7.14 chaos + throughput suites (or deferred to Wave E if user elects) | Active | — |
| C | CUDA Linux (Colima amd64 VM + real CUDA host) | Full-suite cohort closure batch on the counterpart cohort: `./bootstrap/linux-cpu.sh` lifecycle through Colima amd64 VM (portable CPU lane); `./bootstrap/linux-gpu.sh` lifecycle on real CUDA hardware (or separately reintroduced Linux/CUDA box); `docker compose run --rm infernix infernix test all` outer-container full-suite; routed Playwright in-container; validates every phase 1-7 code-side closure already landed on Apple | Pending | — |
| D | Either | Phase status promotion sweep: drop `Active` to `Done` on every phase whose Apple cohort gate closed in Wave A or B and whose CUDA Linux cohort gate closed in Wave C; collapse this waves doc to a historical record once all phases reach `Done` | Pending | — |

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

## Wave B — Active

Apple-side code-side work that remains before any productive CUDA Linux
switch. Each item should land and be validated on the Apple Silicon
host; Wave C revalidates the same items on the CUDA Linux cohort.

| Item | Owning phase | Scope |
|------|--------------|-------|
| Sprint 7.15 artifact-upload e2e fix | Phase 7 | `web/playwright/inference.spec.js:280` `browser artifact upload covers preview media PDF and download-only grants` spec fails with `Timed out waiting for outbound WebSocket frame` after `__infernixForceWebSocketClose` + reconnect + draft restore + `form.requestSubmit()`. Hypothesis: `renderAll`-driven chat panel re-render detaches the form between Playwright's `page.locator(...)` resolution and the submit event bubble, so `root.contains(form)` in `web/src/Infernix/Web/DomEvents.js:86-93` silently skips. Trace+video+screenshot capture is in place from Wave A; next failure produces a `playwright show-trace`-readable `trace.zip` for direct observation. Fix is a frontend reconnect/submit-handler robustness pass. |
| Sprint 7.15 per-model smoke matrix | Phase 7 | Extend the e2e suite to iterate the active demo-config model catalog (15 models on Apple Silicon per the 2026-05-30 `serviceEngineBindingCount: 15` capture) and assert each reaches `inferenceResultStatus = completed`. The integration suite already exercises this per-model (16 successful `engineProcessed` traces against the host daemon); the e2e layer mirrors it for the browser flow. |
| Sprint 7.14 chaos + throughput suites | Phase 7 | Coordinator pod-kill survives reconnect (Sprint 7.3); result-bridge Failover handoff (Sprint 7.8); bootstrap subscription replay (Sprint 7.4); per-context dispatcher Failover under concurrent prompt load (Sprint 7.6); multi-user concurrent prompt throughput (Sprint 7.14). Requires new chaos primitive (`kubectl delete pod` mid-prompt with assertion envelope) plus throughput drivers. May be deferred to Wave E (future) at the user's election; deferring leaves a permanent "chaos pending" residual on Phase 7. |

Wave B closes when all listed items pass their Apple cohort gates
locally on the new Apple Silicon host, with evidence recorded under
this section.

## Wave C — Pending

The single supported CUDA Linux cohort closure batch. Runs every phase
1-7 code-side closure that landed in Waves A-B against the counterpart
cohort. This is the **one** machine change the supported cadence
permits between now and `Done`.

Execution surfaces:

- `./bootstrap/linux-cpu.sh doctor / build / up / status / test / down /
  status` — portable CPU lane through Colima amd64 VM (operable from
  the Apple Silicon host without a separate physical machine).
- `./bootstrap/linux-gpu.sh doctor / build / up / status / test / down /
  status` — CUDA-capable Linux substrate. Requires either a separately
  reintroduced Linux/CUDA box or a CUDA-capable VM with NVIDIA
  scheduling.
- `docker compose run --rm infernix infernix test all` — outer-container
  full-suite covering `infernix-integration` + routed Playwright +
  worker validation.
- Phase-specific cohort gates that referenced "CUDA Linux cohort
  validation pending on new Apple Silicon host" in their `Remaining
  Work` blocks (every Active phase carries this residual).

Wave C closes when both `linux-cpu` and `linux-gpu` cohorts pass their
full-suite gates against the same worktree state as Wave B.

## Wave D — Pending

Phase status promotion sweep. After Waves A-C all close:

- Drop `Active` to `Done` on every phase whose listed sprints are all
  `Done` and whose cohort gates both closed.
- Move this waves doc to a historical record under
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) per
  Section I (its purpose was operational; once all phases close, the
  cadence rule in Section Q stands on its own).
- Update `DEVELOPMENT_PLAN/README.md` Phase Overview to read `Done`
  rows.
- Update `00-overview.md` Current Repo Assessment cohort paragraph to
  retire the "Apple Silicon validation reset (2026-05-29)" note.

Wave D requires no machine change; it is paperwork performed on
whichever host is convenient at the time.

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

This index points each phase at its active-wave residual without
restating cohort-pending narrative inside the phase doc. The phase
doc's `Status` header reads `Active (Sprint X.Y code-side closed;
closure pending Wave C)` and refers here.

| Phase | Code-side closure | Apple cohort gate | CUDA Linux cohort gate |
|-------|-------------------|-------------------|------------------------|
| 0 | Sprints 0.1–0.8 `Done`; Sprint 0.9 `Active` | Closed in Wave A (lint gates) | Pending Wave C |
| 1 | Sprints 1.1–1.10 `Done`; Sprint 1.11 `Active` | Closed in Wave A (integration cluster up + lifecycle on Apple host) | Pending Wave C |
| 2 | Sprints 2.1–2.9 `Done`; Sprints 2.10–2.13 `Active` | Closed in Wave A (retained-state replay + Patroni filter + cluster lifecycle) | Pending Wave C |
| 3 | Sprints 3.1–3.9 `Done`; Sprints 3.10–3.11 `Active` | Closed in Wave A (substrate-aware publication + Harbor port + containerd + hand-authored MinIO) | Pending Wave C |
| 4 | Sprints 4.1–4.12 `Done`; Sprint 4.13 `Active` | Closed in Wave A (mounted ClusterConfig + SecretsConfig roundtrip via integration suite) | Pending Wave C |
| 5 | Sprints 5.1–5.8 `Done`; Sprint 5.9 `Active` | Closed in Wave A (demo backend + adapter dhall reads via integration suite) | Pending Wave C |
| 6 | Sprints 6.1–6.21 `Done`; Sprints 6.22–6.28 `Active` | Closed in Wave A (lint gates + e2e 5/6 PASS + integration full PASS) | Pending Wave C |
| 7 | Sprints 7.2 `Done`; Sprints 7.1, 7.3–7.17 `Active` (Wave B residuals: 7.14, 7.15) | Partially closed in Wave A (integration durable-context prompt roundtrip PASS); Wave B residuals still active | Pending Wave C |

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
