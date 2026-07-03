# Infernix Development Plan

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md)

> **Purpose**: Provide the single execution-ordered development plan for `infernix`, including
> phase status, repository-shape decisions, validation gates, and documentation obligations.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

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

## MT3 Catalog Replacement Reopen

The 2026-06-30 replacement of the obsolete MT3 residual with `music-mt3-infer` and
`music-mr-mt3` reopened **Phase 4 Sprint 4.22** and **Phase 6 Sprint 6.35**. Code-side work is
landed: both rows bind through `mt3-infer` on the PyTorch adapter, use model-cache staged weights,
disable upstream auto-downloads, and are generated for `linux-cpu`, `linux-gpu`, and
`apple-silicon` (Apple uses PyTorch CPU; no MPS claim is made). The old `music-mt3-jax` residual is
removed and recorded in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

Earlier Wave K/Wave L/Wave N evidence remains valid for the catalogs that existed when those waves
ran. It does not prove rows added on 2026-06-30. The post-replacement full-suite proof is
[Wave O](cohort-validation-waves.md): rebuilt `linux-cpu` plus the selected `linux-gpu`
accelerator must run full integration and routed E2E over the expanded catalogs before Phases 4 and
6 return to `Done`.

Current Wave O status: the first 2026-07-01 rebuilt `linux-cpu` full-suite attempt reached real
catalog inference and failed closed on `music-mt3-infer` because `mt3-infer 0.1.3` imports a
`transformers` T5 internal removed by the unbounded `transformers 4.57.6` solve. Since
`mt3-infer 0.1.3` requires `transformers >=4.35.0`, the adapter now installs a narrow shim that
exposes the real `torch.utils.checkpoint.checkpoint` function at the expected T5 module attribute.
The follow-up rebuilt CPU attempt advanced past that error and failed closed on `mt3-infer`'s
undeclared `absl` import; the PyTorch engine now declares `absl-py >=2.0`, and rebuilt CPU/GPU
proof remains pending. A third rebuilt CPU attempt (`infernix-linux-cpu:local` manifest
`sha256:bc7c8735e72f7fd03b1f76808020b796779e91f52d4bc6d0971bd5d07406c89d`) passed Haskell
style, Python `check-code`, Haskell unit, and web contracts (`71/71`), reached
catalog-driven `music-mt3-infer`, and failed closed on the next `transformers >=4.50`
compatibility break: MT3's custom T5 wrapper no longer inherited `GenerationMixin`, so `.generate`
was absent. The PyTorch engine dependency now caps `transformers` to `>=4.46,<4.50` across CPU,
CUDA, and Apple PyTorch groups while retaining the checkpoint shim and `absl-py` dependency. The
fourth rebuilt CPU image (`sha256:ecc7e1b68ee8194cdac7633a607a481ab40e3a645038c4b0f5c60b213f4c89bf`)
selected `transformers 4.49.0`, passed Haskell style and Python `check-code`, then failed in
`infernix-unit` because the Sprint 4.16 framework-venv assertion still expected the old unbounded
PyTorch `transformers >=4.46` line. Unit coverage now asserts the bounded PyTorch dependency block;
a mounted capped-image `infernix-unit` rerun passes with that fix. Rebuilt CPU/GPU proof remains
pending. The next rebuilt CPU image
(`sha256:d478db2f41420427c7d1f93adf22eac35f4dc384bf4fc432986aaa4017abee8b`, created
`2026-07-01T15:35:30.229849055-04:00`) selected `transformers 4.49.0`, `absl-py 2.4.0`,
`mt3-infer 0.1.3`, and `piano-transcription-inference 0.0.6`; its full-suite run passed Haskell
style, Python `check-code`, Haskell unit, and web contracts (`71/71`), published to Harbor, reached
real catalog-driven `music-mt3-infer`, and failed closed inside MT3 generation because the upstream
custom T5 attention path dereferenced `cache_position[-1]` while `cache_position` was `None`. The
adapter now disables generation caching for `music-mt3-infer`, matching the upstream MR-MT3
adapter's no-cache generation strategy; mounted Linux-image `poetry --directory python run
check-code` is green. The rebuilt CPU image
(`sha256:b5fb4e6c82b7dc9f46c04f7e7910dd460bcb516518ecdf8d5c313e4303947ad8`, created
`2026-07-01T16:37:11.897901769-04:00`) passed Haskell style, Python `check-code`, Haskell unit,
and web contracts (`71/71`), reached `per-model inference: linux-cpu`, and failed closed on the
same upstream T5 `cache_position` path with the no-cache wrapper visible in the traceback. A deeper
MT3 compatibility fix now wraps Hugging Face `T5Block.forward` for MT3 imports and supplies
`cache_position` when the upstream `mt3-infer` custom stack omits it; mounted Linux-image
`poetry --directory python run check-code` and a PyTorch-engine T5Block probe are green. Rebuilt
full-suite CPU proof is pending.

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
| [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md) | Adopt the hostbootstrap Dhall doctrine: zero version-controlled `.dhall`, the binary as sole generator of every `.dhall` (incl. ConfigMap/Secret bodies; Helm only embeds a string), explicit `init` / `test init` creation with fail-fast-if-missing, a test harness that generates/runs/deletes the runtime config, and eager coordinator model-cache staging from the mounted `infernix.dhall` (replacing the lazy per-inference bootstrap) |
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
`linux-cpu` cohort gate and matching deletion-ledger move. Phase 4 Sprint 4.22 and Phase 6 Sprint
6.35 are active again for the MT3 catalog replacement proof named in Wave O.

Prior closure evidence closes around the implemented worktree. Phase 3 Sprint 3.12 and
[Wave F](cohort-validation-waves.md) closed on the recorded validation after native `linux/arm64` validation
through the already selected arm64 Docker daemon on this Apple Silicon machine. The repository implements the
staged-substrate architecture, the baked Linux outer-container launcher,
the mandatory HA platform services, the Gateway-owned routed edge, the shared Python adapter
project, the Haskell-owned browser-contract generation path, the substrate-specific validation
surface, and the current Apple split-executor topology described below. The runtime-routing
code-side target has landed around substrate-neutral engine pools: the coordinator remains the
production router, normal pools use Pulsar `Shared` plus broker-native backpressure, pinned routes
use derived per-member topics with `Exclusive`, Linux members are Kubernetes workloads, and Apple
members are same-binary host daemons selected by stable host id. Legacy raw-topic compatibility
surfaces and the demo-off coordinator gate have been removed; the remaining tracked cleanup is the
one-binary Webapp role consolidation.

The repository implements the substrate-file doctrine described by this plan. Supported flows
stage one `infernix.dhall` beside the active build root through the `infernix` command
that needs it; the explicit
`infernix internal materialize-substrate ...` helpers remain the direct restaging or inspection
surface. The Linux substrate Dockerfile materializes a build-arg-selected substrate file inside
the image overlay during image build, and supported Compose runs keep that active build root
image-local instead of bind-mounting the host `./.build/` tree. Focused `infernix lint ...` and
`infernix docs check` remain substrate-file independent. The final substrate payload also
distinguishes cluster and host daemon
roles: cluster-role configs name the substrate, request and result topics, and the engine-pool graph,
while host-role Apple configs include the routed Pulsar connection details and the host member's pool
membership. Cluster publication mirrors the
cluster-role payload locally under
`./.data/runtime/configmaps/infernix-demo-config/infernix.dhall` and mounts the same
filename inside cluster workloads at `/opt/build/infernix.dhall`, while the Apple host
file under `./.build/` remains host-role metadata for the same substrate. The file is a typed
Dhall record at `infernix.dhall`, decoded in-process by the `dhall` Haskell library.
`infernix test all`
runs the full supported validation suite for the active built substrate; full repository substrate
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
inference, and result publication. The worker dispatches through the selected engine binding,
fetches model weights lazily from `infernix-models`, and publishes the typed per-family result
surface; the selected `linux-gpu` plus `linux-cpu` real-output proof closed on 2026-06-20, while
unsupported adapter ids fail fast instead of falling through to a generic success path. The
A prior Apple Wave L rerun passed the machine-independent front-loaded gates and reached
Harbor publication after the PyPI torch-source and music-transcription catalog fixes; the later
Apple lifecycle remediation treated Harbor's MinIO-backed `harbor-registry` bucket and registry
scratch metadata as rebuildable cache on both retained-state replay directions so failed large
image pushes do not exhaust MinIO free-drive thresholds on the next run. The follow-on validation
confirmed that retained-state scrub, then hit current-daemon capacity during the fresh runtime
image push; stale local Harbor-tagged runtime image ids were removed from the already selected
native arm64 Docker daemon before rerunning the Apple gate. The rerun then passed Harbor
publication, Harbor-backed preload, final rollout, and the first seven routed Apple model rows
before exposing a Basic Pitch Core ML package-backed bootstrap gap; current source writes only the
`.ready` sentinel for that package-backed native row. The next rerun built and published runtime
image `sha256-16c5933770efe6b3700ab084f6402f8c11074a88be255d8a318f80092895284c`, cleared route
probes and per-model rows through `audio-basic-pitch-coreml` and `audio-basic-pitch-onnx`, then
failed on `music-omnizart` because the Apple PyTorch engine venv lacked `librosa` and
`piano_transcription_inference`; current source adds those Apple PyTorch dependencies and makes
framework-venv readiness markers track the engine `pyproject.toml`/`poetry.lock` digest. The
follow-on Apple rerun built and published runtime image
`sha256-0c9d518848f85bbb5f8384b36c1d03e405ed863fe276db1acc559f5c039758cd`, passed routed
inference through `image-sdxl-turbo`, then failed on `image-apple-stable-diffusion-coreml`
because the Core ML pipeline defaulted to `CompVis/stable-diffusion-v1-4` while the hydrated
Apple snapshot contains `runwayml/stable-diffusion-v1-5` packages; current source passes the
matching Core ML `--model-version` and uses `CPU_AND_GPU` to avoid the unneeded ANE compile path.
Focused Core ML rerun produced a PNG artifact and passed after current source accepted the Apple
pipeline's artifact-only stdout behavior and bounded the command with a 900s timeout. The next full
Apple rerun built and published runtime image
`sha256-8a2ea20aebd2c112122da8062885dc618ff5f3fa8fd591f063c814ce14da18e0`, completed cluster-up
and route probes, completed all 14 routed Apple model rows in the host daemon log, and advanced
through cache lifecycle, service runtime loop, and durable Pulsar topic checks before the pinned
Apple host-engine `Exclusive` guard stalled because the temporary Dhall config omitted explicit
`engineDaemons` and decoded back to default full-catalog daemon topics. Current source serializes
explicit Dhall `engineDaemons` and adds a pinned-topic roundtrip unit regression. The next Apple
rerun with that fix built and published
`sha256-e48b4476fb68228c40bb0dde68c25cd3b4209c7e37c45af5ab973fa4aae52e8a`, passed lint/unit,
reached final rollout, and exposed retained Pulsar BookKeeper/ZooKeeper cookie split-brain
(`InvalidCookieException` plus missing `/ledgers/cookies`); current source extends the dirty Pulsar
bootstrap detector so the existing claim-root reset/retry path handles that retained-state failure.
A 2026-06-27 rerun reproduced the same retained-state failure during the first Pulsar bookie
rollout; current source now probes Pulsar stateful-set rollouts in 30-second windows and raises the
same dirty-state repair signal before the 20-minute rollout timeout elapses. The follow-on Apple
aggregate built and published runtime image
`sha256-4cd135d393b11e395ef482b2707677520f56604cb03ce4f09aeb2d2d064ea570`, proved the targeted
Pulsar claim-root reset/retry loop, and passed integration through all 14 routed Apple model rows,
cache/service/durable-topic checks, pinned/shared Apple host subscription guards, and lifecycle
recovery tails. It failed only at routed Playwright startup because the local Chromium headless
shell was not installed. After installing the Chromium payload, a focused
`./.build/infernix test e2e` rerun rebuilt and published runtime image
`sha256-a4fd54b1ef2d7e9d65fb3f8028e01f1973e19669d2afef73b0065ca6bda0f44e`, ran the real browser
suite, and passed seven of nine specs. The remaining failures are now the artifact-upload
queued-prompt submit path and the `image-sdxl-turbo` browser-matrix result timeout. Current source
adds the missing draft echo wait before the artifact queued submit, and the next focused
`./.build/infernix test e2e` rerun rebuilt and published runtime image
`sha256-560ef859c7463f2d32d2362b845f1d7437fb46597ffddea863f2ac8ae015526d`. That run passed the
artifact-upload spec, recovered from an initially low Apple Docker VM disk-headroom condition
(`XMinioStorageFull` during SDXL snapshot upload, cleared by pruning unused Docker build cache and
images), and completed routed Playwright with `9 passed (21.1m)`, including the full Apple
per-model browser matrix. Stage 2 remains open for the paired `linux-cpu` full routed
real-output gate: rebuilt service-consumer redelivery image
`sha256:451c214fd55aacbe6a67e5e5bf11907ffc9ad7d23a993df90268d3d7d470f6cd` passed the front gates
and full integration, then reached routed E2E and passed eight Playwright specs before the browser
per-model matrix hit node-level `SystemOOM` with both coordinator replicas OOMKilled before
attaching Pulsar service consumers. Rebuilt local-pressure image
`sha256:fbbb0af5bb59366c6144c28e5bd70dd90185e52519e21a5cb136bbf94b1d02a9` contained the
coordinator/demo resource blocks and one-generic-engine browser remediation after the cold
build/materialization/web/Python/Playwright/CLI-help smoke path, then exposed an over-tight
coordinator `512Mi` memory limit during final rollout. Current source raises the coordinator
request/limit to `256Mi`/`1Gi`; rebuilt image
`sha256:0f3555612d15b8278e145d6711512642baf6ff08d4b11457e514c7b0ff274ff8` contains that
remediation after the cold in-image build/materialization/web/Python/Playwright/CLI-help smoke
path and Docker cleanup reclaimed `23.95GB` of BuildKit cache. The rebuilt full `linux-cpu` rerun
on that image reached real per-model inference (`llm-smollm2-safetensors` and
`llm-tinyllama-gguf` completed), then exposed coordinator-side direct single-file model bootstrap
memory pressure: all Kind nodes recorded `SystemOOM`, and both coordinators were OOMKilled at the
`1Gi` limit. Current source streams direct single-file downloads through a temporary file into
MinIO instead of retaining the whole model payload in coordinator memory. Rebuilt image
`sha256:20b1146c267046b4c5fbe3f4dbb1168bba161a99040ccce734a5fccb7ad7dceb` contains that
streaming remediation after the cold in-image build/materialization/web/Python/Playwright/CLI-help
smoke path; image inspection reported size `5132188633` bytes, and Docker cleanup reclaimed
`23.95GB` of BuildKit cache, leaving images `186.9GB`, build cache `0B`, no containers, and no
volumes before the full rerun. That `./bootstrap/linux-cpu.sh test` attempt passed the front
gates, completed real per-model inference past the previous direct-bootstrap OOM point, advanced
through cache lifecycle, service runtime loop, durable Pulsar topic checks, Linux pool placement,
shared backlog, frontend/coordinator/engine failover, and engine pod replacement, then failed in
`engine node drain preserves durable prompt result` with a Pulsar WebSocket `Connection refused`.
Live diagnostics showed the local one-broker/one-proxy Apple-hosted `linux-cpu` topology had
drained an engine node that also hosted the single Pulsar ingress/broker path. Current source now
prepares the drain target by selecting a ready engine node that does not host drain-sensitive
Pulsar stateful pods, or cordoning the candidate and relocating the Pulsar zookeeper/bookie/broker/
proxy pods before the drain; local `cabal build all`, `cabal test infernix-haskell-style`, and
`cabal test infernix-unit` are green for that remediation. Rebuilt image
`sha256:68afca38e206d8b4c99561909bb878b3c17c7592f43829efe7e28a5b5cc8c349` now contains both
the streaming and drain-target remediations after the cold in-image build/materialization/web/
Python/Playwright/CLI-help smoke path; image inspection reported size `5132193167` bytes. The
full gate on that image passed the front gates, recovered through Harbor push retries, cleared
Docker overlay pressure by pruning `23.95GB` of BuildKit cache plus `45.15GB` of unused images,
completed cluster-up and route probes, then failed during `speech-faster-whisper-ct2` because the
native engine's internal MinIO input-object GET hit `ResponseTimeout`. Current source gives the
shared MinIO object wrapper an explicit 120-second timeout and retries native input downloads with
a fresh presigned URL; local `cabal build all`, `cabal test infernix-haskell-style`, and
`cabal test infernix-unit` are green. Rebuilt image
`sha256:7f3bea81330bf0cafb5f0bb0024276e23ec7b53a41cae958aa83a4781a694a74` now contains the
streaming, drain-target, and input-fetch remediations after the cold in-image
build/materialization/web/Python/Playwright/CLI-help smoke path; image inspection reported size
`5132214799` bytes and the launcher CLI-help smoke passed. Post-build Docker usage is `41.91GB`
of images with `18.5GB` reclaimable, `23.95GB` of build cache with `2.118GB` reclaimable, and no
containers or volumes. The full gate on that image passed the front gates, completed full
integration including the repaired drain and `speech-faster-whisper-ct2` rows, then failed only in
routed E2E: eight Playwright specs passed and the browser per-model matrix timed out waiting for
the `speech-faster-whisper-ct2` conversation result after the single browser engine pod had
restarted several times. Current source extends the browser-matrix result envelope through one full
Pulsar service-consumer redelivery window plus a second execution window. The next full rerun used
rebuilt image
`sha256:0feec8141c67aa4879d9ecc6fb0c955afe907121488ac48b5561bf4d70d23ed3`, which contains the
browser-matrix redelivery-envelope remediation after the cold in-image build/materialization/web/
Python/Playwright/CLI-help smoke path; image inspection reported size `5132239400` bytes and the
launcher CLI-help smoke passed. Focused validation for that remediation is green:
`node --check web/playwright/inference.spec.js` and `./.build/infernix lint docs`. Disposable
BuildKit cache cleanup reclaimed `34.7GB`, leaving images `45.04GB`, build cache `0B`, no
containers, and no volumes before the full rerun.
That full `linux-cpu` rerun passed the front gates, rebuilt cluster-up, and reached real
`per-model inference: linux-cpu`, then was interrupted after live diagnostics showed both engine
replicas in `CrashLoopBackOff` from OOM at the generated Apple-hosted `linux-cpu` `3Gi` engine
limit and the single local Pulsar broker OOMKilled at its `512Mi` limit during repeated
published-result reader polling. `./bootstrap/linux-cpu.sh down` completed cleanly. Rebuilt image
`sha256:06d4057472ac977bc1538ec4c6e0e49beb2fd25abc4e40b940d4b934cc63f8bb` now contains that
Apple-hosted `linux-cpu` local remediation after the cold in-image build/materialization/web/
Python/Playwright/CLI-help smoke path; image inspection reported size `5132256620` bytes, created
`2026-06-28T21:28:43.772069153-04:00`, and the launcher CLI-help smoke passed. Post-build
disposable builder cleanup reclaimed `23.92GB`, leaving images `99.19GB`, build cache `17.2GB`,
no containers, and no volumes before the full rerun. The full `linux-cpu` rerun on that image
passed Haskell style, Python `check-code`, Haskell unit, web contracts (`71/71`), cluster-up,
final rollout, Keycloak realm reconciliation, and routed publication probing, then reached
`per-model inference: linux-cpu`. It was interrupted after live diagnostics showed the request path
could not recover under aggregate Apple-hosted `linux-cpu` pressure: all three Kind nodes reported
`SystemOOM` events with `java` and `infernix` victims, and the single local Pulsar proxy had been
`OOMKilled` at its `512Mi` limit. Rebuilt image
`sha256:f5e3ba564b4f431815fce4ed3452f39f944003075fedc965e3a31705b4bbbfb7` now
contains the tightened Apple-hosted `linux-cpu` local profile after the cold in-image
build/materialization/web/Python/Playwright/CLI-help smoke path; image inspection reported size
`5132264989` bytes, created `2026-06-28T22:43:14.163322221-04:00`, and the launcher CLI-help
smoke passed. Post-build disposable builder cleanup reclaimed `23.95GB`, leaving images
`128.6GB` with `8.489GB` reclaimable, build cache `0B`, no containers, and no volumes before the
full rerun. The baked local generated values are demo `96Mi` request / `384Mi` limit,
coordinator `192Mi` / `768Mi`, engine `768Mi` / `3584Mi`, broker `256Mi` / `768Mi`, and explicit
Pulsar heap/direct-memory caps with SerialGC. The full rerun on that image passed Haskell style,
Python `check-code`, Haskell unit, generated web contracts (`71/71`), Harbor publication,
Harbor-backed preload, and reached final rollout before live diagnostics showed
`infernix-infernix-pulsar-proxy-0` in `CrashLoopBackOff`. Proxy logs showed startup failure, not
OOM: Jetty rejected the local `httpNumThreads: "4"` cap with `Insufficient configured threads:
required=4 < max=4`. `./bootstrap/linux-cpu.sh down` completed cleanly. Current source keeps the
tightened memory profile and raises the local Pulsar proxy `httpNumThreads` to `8`; local
`cabal build all`, serial `cabal test infernix-haskell-style`, and serial
`cabal test infernix-unit` are green. The follow-on real Linux host rebuild and full
`./bootstrap/linux-cpu.sh test` rerun closed Wave L on 2026-06-29 with image
`sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`.
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
plus indexed native snapshot hydration for Core ML Stable Diffusion. Phase 1 is fully closed by
Wave L: Apple Stage 2 integration/focused routed Playwright are green, and the paired
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
rebuilt-image `./bootstrap/linux-cpu.sh test` passed the matching CPU full-suite lane. Wave O owns
the post-replacement proof for the MT3 rows added on 2026-06-30.
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

Monitoring is not a supported first-class surface.

## Execution Contexts and Substrates

The plan keeps these concepts separate:

| Concept | Values | Meaning |
|---------|--------|---------|
| Control-plane execution context | Apple host-native, Linux outer-container | where `infernix` runs |
| Supported substrate | `apple-silicon`, `linux-cpu`, `linux-gpu` | which staged `infernix.dhall` payload the active build root carries |

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

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Documentation and Governance | Done — reopened and re-closed (Sprints 0.1-0.12 done; Sprint 0.11 reconciled the governed docs — README matrix, `model_catalog`, `testing_strategy`, `python_policy`, realness doctrine — to the code-enforced realness invariant in lockstep with the Phase 4 catalog change, and Sprint 0.12 added the machine-independent realness lint enforcement (Python `check-code` AST + Haskell `realnessFabricationViolations`, scope extended per accelerator phase); validated 2026-06-23, machine-independent) | [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md) |
| 1 | Repository and Control-Plane Foundation | Done — reopened and re-closed (Sprints 1.1-1.14 remain closed for the scaffold/topology/materialization-lane foundation; Sprint 1.15 is closed for real Apple native runner materialization and native snapshot hydration. Apple Stage 2 integration plus focused routed Playwright are green, and the paired `linux-cpu` full gate closed on 2026-06-29 with rebuilt image `sha256:f243cf3a7c5199746321bffba87639e30fda959e2be80c7d3b15a413fb9e9ca8`: `./bootstrap/linux-cpu.sh test` passed style, Python `check-code`, unit, web `71/71`, full integration with all real `linux-cpu` model outputs plus the HA/chaos tail, and routed Playwright `9/9`.) | [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md) |
| 2 | Kind Cluster Storage and Lifecycle | Done (Sprints 2.10-2.13 lifecycle, retained-state, bootstrap-boundary, and host-manifest closure validated by Apple Wave A and CUDA Linux Wave C) | [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md) |
| 3 | HA Platform Services and Edge Routing | Done — reopened and re-closed (Sprints 3.1-3.12 remain closed — Sprint 3.12 native `linux-cpu` architecture selector and native arm64 publication path closed in Wave F, Sprints 3.10-3.11 validated by Apple Wave A/A.2 and CUDA Linux Wave C; Sprint 3.13 de-exposes the `/minio/s3` external gateway route + `infernix-minio-s3` SecurityPolicy + `presignPublicEndpoint` so the webapp object-proxy is the sole external file-storage service. Sprint 3.13 is code-side closed and validated machine-independent on 2026-06-24, then cohort-closed by [Wave M](cohort-validation-waves.md) on 2026-06-29 with `linux-cpu` plus the selected `linux-gpu` full-suite gates.) | [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md) |
| 4 | Inference Service and Durable Runtime | Active — Sprint 4.22 reopened for the 2026-06-30 MT3 catalog replacement. Code-side bindings for `music-mt3-infer` and `music-mr-mt3` are landed across `linux-cpu`, `linux-gpu`, and `apple-silicon`; Wave O still owns full rebuilt-image `linux-cpu` plus selected `linux-gpu` integration/e2e proof. Sprints 4.1-4.21/4.23/4.24 remain closed for their original scopes. | [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md) |
| 5 | Web UI and Shared Types | Done (Sprints 5.1-5.10 closed with demo backend, Python adapter, and web/Node no-env-var path validated by Apple Wave A/A.2 and CUDA Linux Wave C) | [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) |
| 6 | Validation, E2E, and HA Hardening | Active — Sprint 6.35 reopened for the expanded MT3 catalog integration/e2e gate. The catalog-driven coverage code is in place, but Wave O must rerun full rebuilt-image `linux-cpu` plus selected `linux-gpu` integration and routed Playwright over the new MT3 rows. Sprints 6.1-6.34 remain closed for their original scopes. | [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md) |
| 7 | Demo App Multi-User Durable Context | Done — Sprint 7.28 closed generated artifact object ownership and result-bridge authorization on 2026-06-30 with full selected `linux-gpu` plus `linux-cpu` cohort validation. Prior durable-context, engine-pool, object-proxy, Files view, in-browser rendering, and Wave M closure evidence remains recorded for Sprints 7.1-7.27. Desired-state hot reload remains future work. | [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md) |

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

- two repo-owned Haskell executables share the default Cabal library exposed by the `infernix`
  package (declared in `infernix.cabal` without an explicit library name and depended on as
  `infernix`): `infernix` for the production daemon, cluster lifecycle, validation, and internal
  helpers; `infernix-demo` for the routed demo HTTP host
- one Haskell command registry owns parsing, help text, and the
  canonical CLI reference, but it no longer exposes `--runtime-mode` or any equivalent substrate
  override
- the product contract standardizes three substrates:
  `apple-silicon`, `linux-cpu`, and `linux-gpu`
- the active substrate is read from the staged `infernix.dhall` file beside the active
  build root, and that staged payload is the primary source of truth for substrate identity,
  generated catalog content, daemon role, inference placement, Pulsar topics, and test scope
- Apple host-native lifecycle and validation commands materialize or verify
  `./.build/infernix.dhall`; the explicit helper
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`
  remains available for direct restaging or inspection
- Linux outer-container lifecycle and validation commands materialize or verify
  `/workspace/.build/outer-container/build/infernix.dhall` inside the launcher image;
  the explicit helper
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  remains available for direct restaging or inspection
- the Linux substrate Dockerfile materializes a build-arg-selected copy inside the image overlay,
  and the supported outer-container command surface keeps that copy image-local before doing
  substrate-aware work
- supported runtime, cluster, cache, Kubernetes-wrapper, frontend-contract generation, and
  aggregate `infernix test ...` entrypoints fail fast with a "run `infernix init`" reminder when
  their `infernix.dhall` is missing (Phase 8; no auto-materialize backstop); focused
  `infernix lint ...` and `infernix docs check` remain substrate-file independent
- the runtime substrate file is a typed Dhall record at `infernix.dhall`, created by `infernix init`
  (or the test harness) and decoded in-process by the `dhall` Haskell library; the schema is
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
- the staged substrate file lives under the active build root:
  `./.build/infernix.dhall` on Apple and
  `/workspace/.build/outer-container/build/infernix.dhall` inside the Linux launcher
  image; cluster deployment republishes that payload
  through `ConfigMap/infernix-demo-config` whenever the active topology has cluster-resident
  consumers and mounts the same filename inside those workloads at `/opt/build/infernix.dhall`
- each daemon reads its staged substrate `.dhall` at startup; automatic file-watching or reload is
  not part of the supported contract
- the supported materialization path can emit `demo_ui = false` with
  `--demo-ui false`; omitting that flag keeps the default demo-enabled output
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

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
