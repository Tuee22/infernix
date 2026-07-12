# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, supported
> substrates, and durable state locations in `infernix`.

## Current Repo Assessment

- the repo ships the one-binary Haskell role topology, Envoy Gateway assets, the PureScript demo UI,
  the split runtime modules under `src/Infernix/Runtime/`, the shared Python project, the shared
  Linux substrate Dockerfile that bakes the source-snapshot manifest used by git-less
  `infernix lint files` runs, the route registry, and the snapshot launcher
- the supported CLI reads the active substrate from `infernix.dhall` once that file has
  been staged, without a user-facing runtime-mode flag
- the current implemented staging path is explicit:
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]` on
  Apple and
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  on the Linux outer-container path, which writes
  `/workspace/.build/outer-container/build/infernix.dhall` inside the launcher image
- substrate-file preflight is binary-owned for lifecycle and validation commands, leaving
  `infernix internal materialize-substrate ...` as the direct restaging or inspection helper
  rather than a shell bootstrap responsibility
- lifecycle and validation preflight materializes or validates the active substrate file before
  relying on it, while focused `infernix lint ...` and `infernix docs check` remain
  substrate-file independent
- the Linux substrate image also materializes a build-arg-selected substrate file inside the image
  overlay during image build, and supported Compose runs keep that active build root image-local;
  lifecycle preflight is binary-owned inside the launcher
- the staged substrate file, `cluster status`, publication JSON, demo config, and generated
  browser contracts still expose that active substrate through `runtimeMode` field names
- cluster publication mirrors the cluster-role payload locally as `infernix.dhall`, and
  the rendered chart mounts that same filename inside cluster workloads at
  `/opt/build/infernix-substrate.dhall`
- the implemented Apple product shape is a split-executor lane: `apple-silicon` keeps Apple-native
  inference execution host-side for Apple GPU and unified-memory access while Kind continues to host
  Harbor, MinIO, Pulsar, PostgreSQL, Envoy Gateway, the cluster coordinator daemon, and the optional
  routed demo surface
- the daemon-role contract is code-side implemented around substrate-neutral engine pools: on every
  substrate the coordinator owns Pulsar request-topic consumption, batching, model-to-pool routing,
  result writeback, and model bootstrap. Linux engine members are Kubernetes workloads; Apple engine
  members are same-binary host daemons selected by stable host id. Normal pools use Pulsar `Shared`
  and broker-native backpressure, while pinned routes use derived per-member topics with
  `Exclusive`. The current code validates the pool/member graph and routes coordinator handoff
  through derived pool/model topics; current Apple integration evidence covers pinned-route
  `Exclusive` duplicate rejection, same-machine Apple host-member coexistence on one real `Shared`
  pool subscription, single-host logical `Shared` backlog/backpressure execution, and production
  `demo_ui = false` route/publication assertions. Current Linux CPU integration evidence covers
  Kubernetes-observed pool placement across the two-worker Kind topology, unique-topic shared
  backlog/backpressure, pod replacement, node drain, anti-affinity, lifecycle rebinding, and
  demo-off publication. Wave J Linux GPU/CUDA cohort proof closed on 2026-06-20.
  Physical Apple multi-host proof is hardware-deferred while no second Apple host is available.
  Existing workers use typed Python or native adapter harnesses, fetch model weights lazily from
  `infernix-models`, and publish the typed per-family result surface; the selected `linux-gpu` plus
  `linux-cpu` real-output proof closed on 2026-06-20. Unsupported adapter ids fail fast instead of
  returning a generic success payload
- Linux operator workflows close around Compose-driven outer containers, validation reports the
  active built substrate for the complete selected-substrate suite, and the supported
  materialization path can emit `demo_ui = false`
- validation follows the Section Q single-accelerator rule: code-side closure (implementation plus
  the machine-independent gate set) is completed in natural phase order on whichever single machine
  is present and gates the next phase's implementation, while `Done` requires the phase's one chosen
  accelerator (`apple-silicon` or `linux-gpu`) plus `linux-cpu`; the other accelerator is handled by
  a sibling or later aggregation phase rather than a must-pass-together gate
- direct `infernix-demo` execution no longer doubles as a compatibility target for Harbor, MinIO,
  or Pulsar tool-route probes; those checks now require the real Gateway-backed upstream behavior
- real cluster and routed validation paths use Pulsar's WebSocket and admin surfaces, while the
  repo-local topic spool under `./.data/runtime/pulsar/` remains only a harness-oriented surface
  for unit-level or intentionally endpoint-absent daemon checks
- the Linux bootstrap entrypoints install Docker or CUDA prerequisites and enter
  `docker compose run --rm infernix infernix <command>`; substrate preflight belongs to the
  binary command. `cluster up` persists repo-local cluster state before later rollout phases so
  `cluster status` and cleanup can still observe an in-progress Linux reconciliation
- the supported `linux-cpu` and `linux-gpu` surfaces use the stricter real-upstream route
  assertions, the restaged Linux substrate flow, and the single project `ghc-9.12.4` toolchain
  baked into the substrate image
- the supported Linux launcher bakes a reusable `/opt/infernix/chart/charts/` cache into the
  image and links `/workspace/chart/charts` to it for Helm dependency lookup; the cached
  top-level dependency archives are Harbor, PostgreSQL (pg-operator and pg-db), Pulsar, and Envoy
  Gateway, while MinIO is deployed from the repo-owned hand-authored StatefulSet under
  `chart/templates/minio/` rather than a Helm sub-chart tarball; and `cluster up` repairs the
  known stale retained Pulsar or ZooKeeper epoch mismatch by resetting only the Pulsar claim roots
  and retrying once
- the Apple clean-host bootstrap verifies same-process ghcup-managed `ghc` and `cabal`
  resolution before direct `cabal install`, reconciles Homebrew `protoc`, and lets Apple adapter
  setup or validation paths reconcile the Homebrew-managed `python@3.12` formula and
  `python3.12` command plus a user-local Poetry bootstrap on demand. The native-only workflow
  doctrine now requires Docker-backed Apple work to use the current native arm64 Docker daemon and
  forbids Docker-context creation or switching, Colima VM creation, and cross-architecture
  emulation; Phase 1 Sprint 1.12 replaced the previous Colima reconciliation path with selected
  Docker-context and daemon-architecture validation and closed on the recorded validation with positive
  lifecycle/full-test evidence plus negative no-daemon boundary evidence. The Poetry bootstrap
  may reuse an already available compatible Python 3.12+ executable when one passes the
  implemented version check
- routed Apple Playwright validation runs host-native `npm exec` against the published
  `127.0.0.1` edge port, and retained Kind state is replayed into and out of the worker rather
  than bind-mounted
- the `infernix-demo` SPA bootstrap now starts in `auth-unknown`, then switches the `body` to
  `auth-signed-out` or `auth-signed-in` from `Main.purs.renderAuthGate`; anonymous visitors see
  only the `.app-landing` card with `#login-button` (`Sign in`) and `#register-button`
  (`Create account`), while the summary grid and Chat / Artifacts shell render only after the
  in-memory Keycloak JWT is present
- Keycloak uses the chart-owned `infernix` login theme from
  `ConfigMap/infernix-keycloak-theme`; the realm import and idempotent admin reconcile both set
  `loginTheme = infernix`, so the routed login and registration pages carry the Infernix-specific
  titles without building a custom Keycloak image
- when the demo UI is enabled, the signed-in SPA shell exposes an operator console ribbon for
  `/harbor` and `/pulsar/admin` **only to admins** (Phase 9): `web/src/index.html` marks
  `<html>.infernix-admin` when the token carries the `infernix-admin` realm role and hides the ribbon
  otherwise. (Phase 3 Sprint 3.13 removed the `/minio/s3` route; MinIO is reached only through the
  webapp `/api/objects` proxy; Wave M closed that route surface with `linux-cpu` plus selected
  `linux-gpu` validation on 2026-06-29.) `web/src/Infernix/Web/Auth.js` mirrors the active Keycloak
  access token into the `infernix_operator_token` cookie on login and refresh, clears it during
  Sign out, then redirects through Keycloak OIDC logout so the upstream SSO session is cleared.
  `SecurityPolicy/infernix-operator-routes-jwt` now **authenticates and admin-authorizes** — it
  accepts that cookie or a direct `Authorization: Bearer ...` header and then requires the
  `infernix-admin` realm role before forwarding the four operator route prefixes (`/harbor`,
  `/harbor/api`, `/pulsar/admin`, `/pulsar/ws`); the same cookie authenticates browser-issued media
  `src` GETs against the webapp `/api/objects/download` proxy
- Phase 9 role-based access control: the `infernix-admin` Keycloak realm role (emitted in
  `realm_access.roles`, decoded by `Infernix.Auth.Jwt.jwtClaimRealmRoles` / `jwtClaimsHasRealmRole`)
  gates every cluster-wide surface. The backend (`withAdminRequest`) requires it on `GET /api/cache`,
  the `/api/cache/{evict,rebuild}` mutations, and the `GET /api/admin/overview` cluster-wide monitoring
  endpoint (real substrate / dispatch / catalog / engine-pool / model-cache / all-user aggregates); the
  SPA (`web/src/index.html`) additionally shows the admin monitoring panel + the five infrastructure
  summary cells only to admins, while ordinary users get chat / artifacts / files and a personal
  dashboard scoped to their own `sub`. The Apple host-worker data plane reaches MinIO (NodePort 30011)
  and the Pulsar proxy (NodePort 30080) directly on loopback (`127.0.0.1`), trust-boundary-internal and
  never through the admin-gated edge — the loopback binding of every Kind data-plane + edge port mapping
  is enforced by `infernix lint chart` plus a generated-Kind-config unit assertion. Per-user object
  isolation additionally carries a MinIO STS defense-in-depth layer (`Infernix.Objects.Sts`: a scoped
  credential keyed to `users/<sub>/`, gated by `cluster.minio.stsPerUser`). Doctrine:
  [../documents/architecture/access_control_doctrine.md](../documents/architecture/access_control_doctrine.md)
- the signed-in SPA shell exposes `Delete account`. The browser waits for `DELETE /api/account` to
  synchronously remove the caller's `infernix-demo-objects/users/<userId>/` prefix and user-owned
  demo Pulsar topics before redirecting to Keycloak with `kc_action=delete_account`
- Linux outer-container lifecycle runs forward the host repo root so generated Kind or `nvkind`
  node configs mount host-resolved `./.data/kind/<runtime-mode>/` and
  `./.build/kind/<runtime-mode>/registry/` directories directly into node containers instead of
  replaying retained state with `docker cp`; runtime-scoping prevents a CPU and GPU lane from
  clobbering each other's `localhost:<harborPort>` mirror target
- the shared lifecycle now exposes `lifecycleStatus`, `lifecyclePhase`, `lifecycleDetail`, and
  heartbeat timestamps during monitored Docker build, Harbor publication, Harbor-backed final-image
  preload, and Apple retained-state replay work; staged substrate materialization is atomic for
  concurrent readers; and retained-state Apple reruns automatically reinitialize stopped Harbor PostgreSQL
  replicas from the current Patroni leader when timeline drift leaves replicas unready after
  promotion
- the shared lifecycle skips broad pre-Harbor support-image preloads; shell scripts never pull or
  publish images, supported lanes hydrate and stream only the narrow Harbor warmup dependency set
  into Kind before Helm warmup, only Harbor-required services may pull upstream before Harbor is
  responsive, and every remaining image, including the active `infernix` runtime image, is loaded
  into Harbor before final rollout
- legacy validation proof points are inventoried in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical
  Validation Evidence"; current replacement evidence is tracked by
  [cohort-validation-waves.md](cohort-validation-waves.md), with the Apple cohort closed in Wave A
  and the native Linux/CUDA cohort closed in Wave C; Wave F closed the native arm64 `linux-cpu`
  publication and full-suite validation path on the recorded validation through the selected native arm64 Docker
  daemon, and Wave J closed the current Linux GPU/CUDA plus rebuilt-image `linux-cpu` engine-pool
  placement/backpressure validation on 2026-06-20; Wave M closed the webapp object-proxy reopen
  (2026-06-29), Wave N closed generated-artifact ownership (2026-06-30), Wave P closed the MT3
  catalog replacement plus Phase 8 (2026-07-04), Wave Q cohort-validated the Phase 9
  access-control/monitoring RBAC/STS/dashboard surface on both `apple-silicon` and `linux-cpu`
  (2026-07-07), and Wave U closed the `linux-cpu` plus selected `linux-gpu` Sprint 9.9
  logout/account-switching rerun after the UAT issue in repo-root `notes.txt` was diagnosed and
  closed code-side
- Beyond the Phase 9 admin overview (`/api/admin/overview`) and per-user personal dashboard, no
  general observability stack (metrics, tracing, log aggregation) is deployed.
  Monitoring is not a supported first-class surface.

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./.build/infernix` plus direct `cabal` materialization against operator-installed ghcup | host-native | canonical operator surface on Apple Silicon; host-native cluster lifecycle owner; host-side Apple inference-daemon owner; repo-local kubeconfig owner; uses a host-local scratch kubeconfig under system temp for Kind create or delete before publishing the durable repo-local kubeconfig | `./.build/`, `./.data/` |
| Apple headless Metal/Core ML materialization lane | fixed host Metal runtime bridge plus typed engine-artifact manifests; replacement for the legacy `tart` / `hostTart` / `AppleTart` implementation, with the retained `materialize-metal-engines` command as the manifest surface | host-native Apple process | materializes Apple Metal/Core ML and native runner roots without Tart, user keychain state, host Xcode UI flows, or request-time toolchain installation; Metal source compilation uses the OS Metal runtime compiler, Core ML smoke probes link Foundation/CoreML, native runner roots hydrate real host CLIs/venvs/apps, and routed real-output proof closed in Wave L with Apple Stage 2 plus the paired 2026-06-29 `linux-cpu` full gate | engine artifacts under `./.data/engines/<adapterId>/`; optional immutable payloads in `infernix-engine-artifacts` |
| Linux native engine materialization lane | `src/Infernix/Engines/LinuxNative.hs` plus `infernix internal materialize-linux-native-engines` | Linux substrate image build | writes typed engine-artifact manifests and smoke-validated native runner roots under `/opt/infernix/engines/<adapterId>/` for the runnable Linux native adapter ids; the current payloads are runtime-backed wrappers over image-baked llama.cpp, whisper.cpp, Basic Pitch ONNX, ONNX Runtime/CTranslate2/faster-whisper, and Audiveris app jars plus an image-architecture Temurin 25 JRE, parse native argv, fail with exit 75 until `<model-cache-root>/<model-id>/.ready` exists, and emit optional worker-upload artifact markers | image-owned `/opt/infernix/engines/<adapterId>/`; optional immutable payloads in `infernix-engine-artifacts` |
| Linux outer-container control plane | `docker compose --project-name <lane> --file compose.yaml ... run --rm infernix infernix ...` | Linux container | only supported Linux CLI surface for `linux-cpu` and `linux-gpu`; the GPU lane prefixes the same single Compose file with `LAUNCHER_IMAGE=infernix-linux-gpu:local` to select the CUDA snapshot, forwards the Docker socket, and bind-mounts only `./.data/` while the build root, source snapshot, and chart archives stay in the image overlay; uses a launcher-local scratch kubeconfig under system temp for Kind or `nvkind` create or delete before publishing the durable repo-local kubeconfig | `./.data/`, `./.data/runtime/infernix.kubeconfig` |
| Bootstrap shell entrypoints | `bootstrap/*.sh` | host shell | bounded stage-0 prerequisite and launcher builders; Apple builds the host binary, Linux installs Docker or CUDA prerequisites and enters `docker compose run --rm infernix infernix <command>`; lifecycle, validation, Kind, Kubernetes manifests, cluster workload image pulls, Harbor publication, and teardown behavior are delegated to `infernix` | preserves `./.build/`, `./.data/`, host-level images, Apple host binaries, and installed prerequisites |
| Command registry | Haskell command registry | host or outer container | owns the supported command inventory, `--help` output, and the generated CLI-reference sections that docs lint enforces, including the `infernix service --config` explicit substrate override for targeted daemon validation | none |
| Substrate configuration | staged typed Dhall record at `infernix.dhall`, decoded in-process by the `dhall` Haskell library | host or outer container | primary source of truth for active substrate, generated catalog content, daemon role, explicit engine daemon metadata, inference placement, Pulsar request/result/batch topics, active engine dispatch, routed Apple bridge behavior, and test scope once the file has been staged; materialization writes the staged file atomically so concurrent readers never observe a partial payload; `infernix service --config PATH` may intentionally point one daemon at an explicit substrate file for targeted diagnostics without rewriting the shared staged file | `./.build/infernix.dhall` on Apple carries host-role metadata; `/workspace/.build/outer-container/build/infernix.dhall` on the Linux outer-container path carries cluster-role metadata; cluster pods mount the cluster-role payload at `/opt/build/infernix-substrate.dhall` |
| Route registry | Haskell-owned route inventory | host or outer container during render or reconcile | records public prefixes, backend identity, rewrite rules, visibility, and publication metadata | none |
| Automation entry documents | `AGENTS.md`, `CLAUDE.md`, and their governed canonical-home links into `documents/` | repo source | point assistant users at canonical workflow rules without turning root entry docs into competing topic homes | none |
| Frontend contract generator | `infernix internal generate-purs-contracts` | host or outer container during web build | emits generated PureScript contracts from handwritten Haskell browser-contract ADTs | `web/src/Generated/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, runtime state, config publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | explicit Cabal builddir or installdir flags plus generated artifacts | host or outer container | keeps compiled output and generated files out of tracked source paths | `./.build/` on Apple; image-local `/workspace/.build/outer-container/` on the Linux outer-container path |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Linux substrate image definition | `docker/Dockerfile` | one shared build definition produces the Linux control-plane image and the Linux daemon image family while owning ghcup, Poetry, Node.js 22.5+ for the demo bundle, Playwright runtime packages, Docker buildx for nested Docker operations, npm update-notifier suppression, and the Kind toolbelt; installs Cabal/NPM/Poetry dependency layers from package metadata before the full source copy, materializes a build-arg-selected substrate file inside the image overlay before web build and Python quality checks, and writes a pruned `/opt/infernix/source-snapshot-files.txt` for git-less lint runs; host-native Apple cluster-image builds stamp source-fingerprint, runtime-mode, and fingerprint-version labels so unchanged-source `cluster up` can safely reuse `infernix-linux-cpu:local`; cabal-home and the cabal builddir live at the toolchain's natural in-image locations rather than under any bind-mounted host path; the image uses `tini` as its `ENTRYPOINT` for clean signal handling and zombie reaping | none |
| Playwright runtime | baked into `docker/Dockerfile` (Node, the Playwright runtime, and the three browsers) and invoked from inside the outer container via `npm --prefix web exec -- playwright test --config web/playwright.config.js` on Linux substrates; on Apple Silicon the host-native lane invokes `npm --prefix web exec -- playwright test` from the host CLI against the published localhost edge port using the same typed fixture. Apple routed Playwright validation closed in Waves A.1/A.2, and the rebuilt Linux GPU launcher passed 7/7 routed E2E in Wave C on the recorded validation. | none |
| Compose launcher | `compose.yaml` | outer-container launcher for supported Linux workflows; the file defines exactly the `infernix` service with two bind mounts (`./.data` and `/var/run/docker.sock`), no `environment:` block, no `build:` block, and a one-shot image selector that defaults to `infernix-linux-cpu:local` while allowing the GPU lane to choose `infernix-linux-gpu:local`. The Phase 3 Sprint 3.10 `playwright` service removal landed on the recorded validation — Playwright now runs inside the same substrate image | none |
| Shared Python adapter project | `python/pyproject.toml`, `python/adapters/` | single **framework-free** adapter tree + `check-code` quality gate for Python-native engines; declares no ML framework so `poetry run check-code` is machine-independent | none in the supported operator contract |
| Per-engine framework venvs (Phase 4 Sprint 4.16) | `python/engines/<engine>/pyproject.toml` for `transformers`, `vllm`, `pytorch`, and `diffusers` | isolated in-project venvs that path-depend on the shared `infernix-adapters` package and install their mutually-conflicting framework wheels in an optional substrate group (`--with cuda` on linux-gpu, cu128 torch for Blackwell; `--with apple-silicon` on Apple host-native `transformers`, `pytorch`, and `diffusers` engines with Darwin arm64 torch-family wheels explicitly sourced from PyPI; `--with linux-cpu` for Linux CPU `transformers` and `pytorch` validation engines); `src/Infernix/Runtime/Worker.hs` runs the per-engine venv when present and falls back to the fail-fast shared path when absent; Linux CPU and Linux GPU builds bake their applicable venvs as resilient layers. Framework adapters now return real model output or fail closed; deterministic fabricated-success paths are forbidden by the realness lint. The selected `linux-gpu` plus `linux-cpu` real-output gate closed on 2026-06-20 for the then-active catalog. Basic Pitch TensorFlow remains outside the active runtime catalog; MT3-PyTorch, MR-MT3, and Omnizart are maintained PyTorch music-transcription rows, and the post-replacement MT3 rows closed under Wave P (2026-07-04) | `python/engines/<engine>/.venv/` (gitignored build artifact) |
| Per-engine engine images and routing (Phase 4 Sprint 4.17) | `docker/Dockerfile`, `docker/engine.Dockerfile`, `src/Infernix/Models.hs`, `src/Infernix/{Types,Substrate,DemoConfig}.hs`, `src/Infernix/Runtime/{Daemon,Pulsar}.hs`, `src/Infernix/Cluster*.hs`, `chart/templates/deployment-engine.yaml`, `chart/templates/poddisruptionbudget-engine.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js` | the linux-gpu monolith (~121 GB) split into a slim 22.4 GB control-plane/coordinator image (`docker/Dockerfile`, no framework venvs) plus per-engine images (`docker/engine.Dockerfile` = CUDA-runtime base + the binary + one engine's `--with cuda` venv); `Infernix.Models` owns engine name/image mapping (`engineNameForSelectedEngine`, `frameworkEngineNamesForMode`, `perEngineImageName`) plus substrate-neutral pool/member topic derivation; generated substrate files carry `enginePools`, `engineMembers`, and explicit `engineDaemons` so targeted daemon configs survive Dhall round-trip while normal generated daemon metadata still follows the pool/member graph; the coordinator routes requests to `inference.batch.<mode>.pool.<poolId>.model.<modelId>` and pinned routes use `inference.batch.<mode>.member.<memberId>.model.<modelId>`; `infernix service --role engine --engine-name NAME` selects a stable engine member id; the chart renders per-engine Deployments/PDBs and Harbor overlays carry per-engine images. Repo-owned `linux-gpu` lifecycle values leave per-engine replicas at zero on the single-GPU lane, and the integration/E2E harness scales exactly one per-engine deployment at a time for per-model validation. Full serialized routed cluster evidence for the selected per-engine images closed in Wave I on 2026-06-20 | none |
| Apple host prerequisite bootstrap | governed docs plus Haskell bootstrap logic | minimize Apple pre-existing host installs and let `infernix` reconcile supported Homebrew-managed tools and Poetry bootstrap while requiring any Docker-backed work to use the already selected native arm64 Docker daemon; Docker readiness validation reports the current context and daemon architecture without creating or switching contexts or creating a VM | none |
| Testing doctrine docs | `documents/engineering/testing.md` and `documents/development/testing_strategy.md` | keep one canonical testing doctrine together with one operator-facing detail layer | none |
| Browser-contract source | `src/Infernix/Web/Contracts.hs`, `web/package.json` | keeps handwritten Haskell contract source out of `Generated/` while preserving generated PureScript output there | none |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | hold repo-owned workloads, ConfigMaps, Gateway resources, and third-party chart dependencies | none |
| Kind topology reference assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml` | tracked topology references and chart-lint inputs for the substrate-specific Kind shapes; the supported lifecycle renders the active runtime config from Haskell into `./.build/kind/cluster-<runtime-mode>.generated.yaml` before invoking Kind or nvkind. The `linux-cpu` reference and renderer use two worker nodes so the local CPU lane can exercise two engine pods, pod replacement, node drain, and anti-affinity; `linux-gpu` stays single-worker for the single-GPU host shape | none |
| Protobuf contract assets | `proto/infernix/...` plus on-demand generated `tools/generated_proto/` stubs under a `tools/` directory that may be absent in a clean checkout | define canonical runtime, manifest, and event schema boundaries | generated stubs must stay untracked |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native Apple CLI or Linux outer container | create or reuse Kind, scrub non-retained operator-managed Patroni PostgreSQL claim roots before recreating claim directories and after retained-state sync, retry recursive claim-root chmod when a non-retained claim directory or child disappears during cleanup/retry replay and leave the root present after the bounded missing-path race window, scrub rebuildable Harbor registry MinIO cache before MinIO claim copy-out and before cluster-up copy-in, reset StorageClasses, reconcile PVs, deploy Harbor first, publish the cluster-role substrate payload, perform Harbor-first image preparation, run a dedicated `prepare-keycloak-storage` Helm phase that applies only the Keycloak Patroni CR and binds its operator-managed PVs before full final workloads can observe those claims, apply an Apple-hosted `linux-cpu` `prepare-pulsar-runtime` Helm phase that starts Pulsar and waits for its stateful sets before Keycloak/demo/coordinator/engine pods enter the constrained Colima memory envelope, apply the full final chart without rerunning Helm hooks, deploy the role-specific coordinator and engine daemon Deployments, expose in-progress lifecycle phase, detail, and heartbeat state for status observers, retry once with a targeted Pulsar claim-root reset when retained ZooKeeper/BookKeeper state is self-inconsistent, including cookie instance-id mismatch and missing `/ledgers/cookies`, probe Pulsar stateful-set rollouts in short windows so precise retained-state markers trigger repair before the full rollout timeout while standalone ZooKeeper startup fragments are ignored, render explicit final-phase Keycloak heap/resource controls plus MinIO, Pulsar statefulset/init-job, Percona PostgreSQL database/proxy/backup, and Linux engine CPU/memory resource envelopes so local-service pods do not run uncapped under Linux CPU startup pressure, reinitialize stopped retained Harbor PostgreSQL replicas from the current Patroni leader when timeline drift leaves replicas unready after promotion, recycle unready Harbor PostgreSQL startup pods with non-waiting deletes so StatefulSet name reuse cannot block lifecycle progress, generate a single-replica Apple host-native local validation topology for Harbor/Pulsar/coordinator/demo with matching one-bookie Pulsar broker quorum on constrained native arm64 Docker daemons, and generate an Apple-hosted `linux-cpu` local profile that keeps two repo daemon replicas for failover/node-drain coverage while constraining Harbor/Pulsar/MinIO/Keycloak/Percona aggregate memory, demo pods to a `96Mi` request / `384Mi` limit, coordinator pods to `192Mi` / `768Mi`, Linux engine pods to `768Mi` / `3584Mi`, the single local Pulsar broker to `256Mi` / `768Mi`, local Pulsar JVM heap/direct-memory via SerialGC, and the local Pulsar proxy to `httpNumThreads: "8"` on the shared Colima VM | `./.data/runtime/cluster-state.state`, `./.data/kind/<runtime-mode>/...` |
| Harbor image preparation | Harbor plus Haskell image publication flow | Kind cluster plus control plane | bootstrap Harbor with explicit registry/controller resource requests, 32 MiB S3 registry chunks, reduced multipart copy concurrency, and three registry replicas on Linux bootstrap publication; final Harbor workloads also carry explicit Redis/core/jobservice/portal/nginx, registry-controller, and Trivy requests/limits, with the Apple-hosted `linux-cpu` local profile collapsing final registry/core/jobservice/portal to one replica and Trivy to zero so constrained-lane Harbor services do not run as BestEffort or oversubscribe memory; allow only Harbor-required support services to pull upstream before Harbor readiness, then mirror every remaining third-party image and publish the active `infernix` runtime image before final rollout; Docker pushes wait for registry readiness before each attempt, re-tag the source image before each bounded retry, and use capped backoff so transient Harbor resets, constrained-lane registry restarts, or missing transient target tags during large-image publication do not fail the lifecycle prematurely; rebuildable registry state includes the `harbor-registry` MinIO bucket, MinIO registry metadata/multipart/tmp working sets, and Harbor Redis blob-cache claim, all scrubbed with non-retained Harbor database state before retained-state replay can carry stale publication blobs forward | Harbor registry/cache state under `./.data/kind/<runtime-mode>/...` is rebuildable; durable product blobs remain in MinIO `infernix-models`, `infernix-engine-artifacts`, and `infernix-demo-objects` |
| PostgreSQL substrate | Percona Kubernetes operator plus Patroni PostgreSQL | Kind cluster | only supported in-cluster PostgreSQL contract for Harbor and later services; Patroni claim roots are non-retained and are scrubbed on both copy-based and Linux bind-mounted Kind paths before new claim directories are created, the Harbor/Keycloak Percona clusters run an idempotent bootstrap SQL ConfigMap that ensures the `_crunchyrepl` `LOGIN REPLICATION` role exists before replicas base-backup from the primary, retained-state reruns may trigger targeted Patroni replica reinitialization from the current leader when stopped replicas need a fresh base backup after timeline advancement, the Harbor reinit repair also reasserts that replication role on the current primary before `patronictl reinit`, and the Harbor/Keycloak Percona clusters render explicit database, pgBouncer, pgBackRest repo-host, and backup-job resources so Patroni startup bursts are bounded in Linux CPU validation lanes | `./.data/kind/<runtime-mode>/...` |
| Publication state | repo-local JSON plus routed `/api/publication` surface | repo-local state and demo API | reports control-plane context, cluster daemon location, host inference executor presence when the active substrate is Apple, the routed demo API upstream mode, the active inference dispatch mode, derived engine-pool routing metadata, the active substrate through its current `runtimeMode` field, routes, and upstream health metadata | `./.data/runtime/publication.json` |
| Edge Gateway controller | Helm-installed Envoy Gateway controller | Kind cluster | owns all browser-visible and host-consumed routing | none |
| Cluster Gateway resource | `GatewayClass/infernix-gateway` plus `Gateway/infernix-edge` | Kind cluster | single localhost-bound HTTP listener on the chosen edge port | none |
| HTTPRoute rendering | data-driven `chart/templates/httproutes.yaml` from the Haskell route registry | Kind cluster | publishes the route inventory for demo, Harbor, and Pulsar surfaces (MinIO has no external gateway route since Phase 3 Sprint 3.13; the browser reaches it only through the webapp `/api/objects` proxy) | none |
| Substrate-file publication | generated `ConfigMap/infernix-demo-config` plus repo-local mirror | Kind cluster and repo-local state | republishes the cluster-role substrate payload for cluster consumers and local inspection tooling through the shared `infernix.dhall` filename; Apple host daemons read the host-role payload under `./.build/` | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime daemons | `infernix service` plus `src/Infernix/Runtime/{Daemon,Cache,KVCache,Worker,Pulsar}.hs`, `src/Infernix/Dispatch/SingleFlight.hs`, `src/Infernix/Bridge/Result.hs`, `src/Infernix/Bootstrap/Models.hs` | cluster pods on every substrate plus host processes for Apple inference execution | the supported target is the three-role daemon model plus substrate-neutral engine pools (see [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) and [../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md)). The coordinator role (`infernix-coordinator`, stateless, HA default replicas >= 2 on Linux lanes and one generated local replica on Apple host-native validation, no PVC) owns request-topic fan-in, batching, model-to-pool routing, result-bridge writeback, and eager model-cache staging on startup from the mounted `infernix.dhall` (a `warm-model-cache` cluster-up barrier). Engine members consume derived pool/model topics, stream weights from the eagerly pre-staged `infernix-models` through the shared adapter helper, run the selected adapter, own process-local KV cache, and publish `inference.result.<mode>`. Normal pools use Pulsar `Shared` and broker-native backpressure; pinned member routes use derived per-member topics with `Exclusive`. Linux members are Kubernetes workloads; Apple members are host daemons selected by stable host id. Generated substrate files carry explicit engine daemon metadata derived from `enginePools` and `engineMembers`, and targeted validation configs may narrow that metadata without losing it on Dhall decode. Production-shaped `demo_ui = false` keeps the coordinator and engine pools while omitting demo-only workloads and routes. **Resource memory admission (Phase 4 Sprint 4.27 / Phase 5 Sprint 5.11 / Phase 6 Sprint 6.38):** every model carries `modelRamFootprintMib`, each substrate resolves a typed `InferenceMemoryBudget`, and runtime admission returns typed `InferenceError.ModelMemoryLimitExceeded { requiredMib, availableMib, resource, source }` for oversized requests. Apple uses unified host RAM after the Colima pledge and reserve without hardcoded floors, Linux CPU uses the engine pod memory limit, and Linux GPU uses GPU VRAM. One oversized catalog entry must not fail daemon startup or block smaller models. | none on cluster daemons (Pulsar cursors are broker-side; KV cache is in-memory); Linux engine pod `emptyDir` model caches and Apple host model caches are derived and rebuildable |
| Demo UI host | `infernix-demo` Deployment running `infernix service --role webapp` | cluster pod | serves `/`, `/api`, `/api/publication`, `/api/demo-config`, `/api/models`, `/api/cache`, `/api/objects/{upload,download}`, and `/ws` when demo is enabled; routed manual inference closes through the durable-context Chat surface, where the Webapp role publishes inference work and (on Apple) hands batches off to host inference daemons | none |
| Web runtime executor | PureScript bundle plus Playwright runtime (Node, the Playwright executor, and the three browsers) both baked into `docker/Dockerfile` | substrate image runs cluster-resident as the demo app; routed E2E runs in-container on Linux substrates via `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private `kind` network. Apple host-native E2E uses host `npm exec` with the same typed fixture against the published localhost edge port and is covered by Apple cohort validation batches | serves the browser bundle from the clustered demo app and runs routed E2E coverage from the same substrate image | test artifacts under `./.data/` |
| Engine adapter set | `python/adapters/` invoked via `poetry run` from the Haskell worker | host child process or cluster child process | Python-native engine boundary over typed protobuf-over-stdio | optional Apple venv under `python/.venv/` |
| Python quality gate | `poetry run check-code` | host or Linux outer-container image | runs `mypy --strict`, `black --check`, and `ruff check` against the shared adapter tree | none |
| Keycloak identity | Keycloak Helm release | Kind cluster, demo-gated | OIDC identity provider for the durable-context demo: self-signup on, email verification off, public SPA client reconciled for the routed edge URL; the local demo runs one Keycloak application pod until proxy-affinity or clustered-cache validation lands, and is absent when `demo_ui = false`; see [../documents/tools/keycloak.md](../documents/tools/keycloak.md) | Keycloak Patroni Postgres state under `./.data/kind/<runtime-mode>/...` |
| Keycloak Patroni Postgres | Percona PostgreSQL operator | Kind cluster, demo-gated | dedicated HA Patroni cluster backing Keycloak per the per-service rule in [../documents/tools/postgresql.md](../documents/tools/postgresql.md); absent when `demo_ui = false` | `./.data/kind/<runtime-mode>/...` |
| Demo artifact bucket | MinIO bucket `infernix-demo-objects` | Kind cluster, demo-gated | single shared bucket holding per-user prefix trees `users/<userId>/contexts/<contextId>/{uploads,generated}/`; the webapp `/api/objects` proxy reads/writes it server-side per user (no browser presigned URL); absent when `demo_ui = false`; see [../documents/tools/minio.md](../documents/tools/minio.md) | MinIO durable state under `./.data/kind/<runtime-mode>/...` |
| Demo conversation Pulsar topics | Pulsar topic family `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` | Pulsar broker, demo-gated | per-context append-only conversation log; single-partition, broker-assigned `MessageId` is the canonical sequence; producer-side dedup enabled; the integration suite validates real publish + Reader decode, duplicate frontend publish collapse, completed result writeback from a non-chaos dispatcher/result-bridge prompt roundtrip, and exactly-one request/batch/result/conversation-result counts through frontend, coordinator, engine, and node-drain chaos paths; absent when `demo_ui = false` | Pulsar BookKeeper state |
| Demo per-user metadata topics | Pulsar topic families `demo.user.<userId>.contexts` and `demo.user.<userId>.drafts` | Pulsar broker, demo-gated | compacted per-user metadata for the left-rail context list and drafts; broker message key is `contextId`; the integration suite validates real publish + Reader decode with key assertions, admin compaction threshold readback, explicit topic compaction, compacted-reader latest-per-key behavior, and duplicate draft publish collapse; absent when `demo_ui = false` | Pulsar BookKeeper state |
| Inference batch topics | Derived pool/model topic family `persistent://infernix/demo/inference.batch.<mode>.pool.<poolId>.model.<modelId>` plus pinned-member topic family `persistent://infernix/demo/inference.batch.<mode>.member.<memberId>.model.<modelId>` | Pulsar broker | the coordinator publishes pre-batched inference work only to topics derived from the validated engine-pool graph. Normal pool topics use `Shared` so broker permits and receiver backlog distribute work; pinned member topics use `Exclusive`. The old `inference.batch.<mode>`, `inference.batch.<mode>.<engine>`, and Apple `.host` helper topics are removed from supported routing. | Pulsar BookKeeper state |
| Platform model bucket | MinIO bucket `infernix-models` | Kind cluster, always-on (not demo-gated) | platform-owned model weights, tokenizers, and configs; eagerly staged at coordinator startup from the mounted `infernix.dhall` model set (a `warm-model-cache` cluster-up barrier blocks until all are `.ready`); per-model `.ready` sentinel object written last marks an atomic publish; Linux engine pods and Apple host engine members stream from here into derived model caches | MinIO durable state under `./.data/kind/<runtime-mode>/...` |
| Model-cache staging + fallback topic | eager coordinator staging plus the fallback Pulsar topic `persistent://infernix/system/model.bootstrap.request` and `model.bootstrap.ready.<modelId>` family | Pulsar broker, always-on | exactly-once model population workflow: on startup the coordinator iterates the mounted `infernix.dhall` model set and, per model, downloads from the upstream URL in the mounted `infernix.dhall` → uploads to `infernix-models/<modelId>/` → writes `.ready` sentinel last → publishes ready event keyed by `modelId`; the `warm-model-cache` cluster-up barrier blocks until all are `.ready`. An engine that hits an unstaged model can still publish a fallback bootstrap request (dedup key `modelId@requestedAt`), serviced by the same coordinator Failover subscription; the MinIO `.ready` guard prevents duplicate effective population. The integration suite validates real ready-topic publish + Reader decode with key assertion and staging dedup across coordinator replacement (exactly one ready event); the coordinator is the only daemon with outbound-internet egress to upstream model hosts | Pulsar BookKeeper state |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | reconcile Kind, storage, Harbor-first bootstrap, image publication, staged substrate-file publication, publication state, edge port, and repo-local kubeconfig publication while recording the active lifecycle phase, child operation, and heartbeat for supported status observers; uses scratch kubeconfig state under system temp for Kind or `nvkind` create or delete so transient lock files stay off the durable repo-local paths; retained-state Apple reruns may automatically repair stopped Harbor PostgreSQL replicas from the current Patroni leader when timeline drift leaves replicas unready, and unready startup-pod recycling uses non-waiting Kubernetes deletes so StatefulSet recreation does not become the gate |
| Cluster status | `infernix cluster status` | report cluster presence, the active substrate through its current `runtimeMode` line, publication state including `publicationInferenceDispatchMode` and derived engine-pool routing metadata instead of a single host batch topic, plus upstream mode, build or data roots, route inventory, and the active in-progress lifecycle action, phase, detail, and heartbeat fields without mutating Kubernetes resources, publication state, or authoritative repo-local state; on Linux outer-container paths it may idempotently attach the fresh launcher container to Docker's private `kind` network for observation |
| Kubernetes wrapper | `infernix kubectl ...` | scoped wrapper around upstream `kubectl` against the repo-local kubeconfig |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or reconcile derived runtime cache state without mutating authoritative sources |
| Focused lint | `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart` | run the repo-owned focused lint entrypoints for files, docs, `.proto`, and chart assets. File lint uses the baked source snapshot inside git-less images and invokes Git with a scoped `safe.directory=<repo>` override for mounted-source runs so validation does not depend on global Git config |
| Aggregate static validation | `infernix test lint` | validate the active staged substrate at command entry, then run the focused lint entrypoints together with Haskell style/build and Python quality checks |
| Docs validation | `infernix docs check` | validate the governed docs suite and phase-plan shape through the canonical docs linter |
| Service runtime | `infernix service` | consume the staged substrate file at startup, or an explicit `--config PATH` file for targeted diagnostics, and own inference for the active substrate through real Pulsar transport on supported cluster paths, with a repo-local topic-spool harness available only when Pulsar endpoints are intentionally absent |
| Demo UI runtime | `infernix service --role webapp` in the `infernix-demo` Deployment | serve the demo-only HTTP surface against the active generated substrate catalog |
| Frontend contract generation | `infernix internal generate-purs-contracts` | generate the supported PureScript contract module from Haskell source |
| Unit validation | `infernix test unit` | validate the active staged substrate at command entry, then run Haskell runtime behavior checks plus PureScript unit suites without claiming cluster matrix coverage |
| Integration validation | `infernix test integration` | validate the built substrate's published catalog contract through one substrate-aware integration suite that traverses the README matrix rows, selects the active engine from the generated `.dhall`, covers every generated active-substrate catalog entry, and carries the supported real-cluster HA or lifecycle assertions |
| Routed E2E validation | `infernix test e2e` | exercise the real routed browser surface for the built substrate through a substrate-agnostic Playwright suite that relies on `infernix-demo` to read the generated `.dhall` and dispatch the correct engine |
| Single-accelerator phase closure | chosen accelerator full-suite plus `linux-cpu` evidence | record the phase's chosen accelerator (`apple-silicon` or `linux-gpu`) plus `linux-cpu` attestation; code-side closure and its machine-independent gates stay on one machine in natural order, and the other accelerator is handled only by a sibling phase or later aggregation work |
| Style toolchain bootstrap | `src/Infernix/Lint/HaskellStyle.hs` | install `ormolu` and `hlint` through `cabal install` against the project `ghc-9.12.4` compiler into `./.build/haskell-style-tools/bin/` and run `ormolu`, `hlint`, and `cabal format` checks |

## Browser and API Surface

| Route | Upstream | Purpose | Notes |
|-------|----------|---------|-------|
| `/` | HTTPRoute -> `infernix-demo` Service | demo browser UI; anonymous visitors see only the landing card with `Sign in` and `Create account` CTAs until Keycloak auth completes | absent when `demo_ui` is false |
| `/api` | HTTPRoute -> `infernix-demo` Service | demo API prefix for models, publication, demo-config, and cache discovery | absent when `demo_ui` is false |
| `/api/publication` | `GET` endpoint on the `/api` route -> `infernix-demo` Service | routed publication metadata | absent when `demo_ui` is false |
| `/api/cache` | `GET` and `POST` endpoints on the `/api` route -> `infernix-demo` Service | demo cache lifecycle API | absent when `demo_ui` is false |
| `/auth` | HTTPRoute -> Keycloak Service | Keycloak login pages and OIDC endpoints for the durable-context demo; routed E2E covers self-registration to OIDC authorization-code redirect | absent when `demo_ui` is false |
| `/ws` | HTTPRoute -> `infernix-demo` Service | WebSocket endpoint for authenticated durable-context sessions; carries chat, drafts, context list, progress, and artifact-ready notifications | absent when `demo_ui` is false |
| `/api/objects` | HTTPRoute -> `infernix-demo` Service | webapp object-proxy: `POST /upload` (bytes), `GET /download` (streamed bytes), `POST /download` (render disposition), `GET /list`, and `DELETE` — all per-user scoped server-side; artifact bytes flow through the demo backend (no presigned MinIO URL) | absent when `demo_ui` is false |
| `/harbor/api` | HTTPRoute -> Harbor core Service | Harbor API surface | always published |
| `/harbor` | HTTPRoute -> Harbor portal Service | Harbor browser portal | always published |
| `/pulsar/admin` | HTTPRoute -> Pulsar admin Service | Pulsar admin surface | always published |
| `/pulsar/ws` | HTTPRoute -> Pulsar HTTP or WebSocket Service | Pulsar browser-facing HTTP surface | always published |

## Substrate Inventory

| Substrate | Canonical substrate id | Supported contract | Current repo gap |
|-----------|------------------------|--------------------|------------------|
| Apple Silicon / Metal | `apple-silicon` | host-native control plane, cluster `infernix-coordinator` daemon for request-topic consumption and model-to-pool routing, same-binary host engine daemons with stable host ids consuming assigned derived pool/model topics and publishing results, and clustered support services plus optional routed demo workloads sharing the same substrate file and route contracts; normal Apple pools use `Shared` across distinct host ids and exact-host routes use pinned `Exclusive` topics; Metal and Core ML native engine artifacts materialize through the headless host bridge / typed manifest lane before host-native execution | Sprint 1.14 closed the Apple host bridge/native-artifact smoke foundation after Tart implementation removal; Sprint 7.23 superseded by Sprint 7.24 engine-pool assignment and broker-native backpressure |
| Linux / CPU | `linux-cpu` | containerized Linux lane built from the shared substrate Dockerfile and driven entirely through Compose on native Linux amd64 or native Linux arm64; publication selects the normalized native host architecture from `InfernixHost.dhall`; native arm64 publication and full-suite validation closed in Wave F on the recorded validation through the selected native arm64 Docker daemon; current Wave J validation additionally proves two-worker engine-pool placement, shared-subscription backlog/backpressure, chaos/recovery, anti-affinity, lifecycle rebinding, demo-off publication, and the Linux CPU framework-venv smoke paths through the native arm64 Colima daemon | none |
| Linux / NVIDIA GPU | `linux-gpu` | GPU-enabled Kind lane built from the shared substrate Dockerfile and deployed from the same CUDA-based image used by the outer container | none |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Matrix registry -> staged substrate file | local staging boundary | typed Dhall record at `infernix.dhall`, schema reflected from the substrate decoder type | `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs` | Apple staging lives under `./.build/`; Linux outer-container staging lives under `/workspace/.build/outer-container/build/` in the launcher image; the active substrate selects engine bindings and daemon roles consumed by cluster daemons, Apple host daemons, `infernix-demo`, and the integration suite |
| Staged substrate file -> ConfigMap publication | control plane | real ConfigMap data plus repo-local mirror | `infernix cluster up` | the repo-local mirror stores the cluster-role `infernix.dhall`, and cluster-resident consumers, including Apple and Linux cluster daemons plus the routed demo surface, mount the same filename at `/opt/build/infernix-substrate.dhall`; Apple host daemons read a host-role config from the host build root |
| Browser <-> demo API | external (demo only) | JSON over HTTP | handwritten Haskell browser-contract ADTs plus generated PureScript bindings | production deployments do not expose this surface |
| Inference requester <-> Pulsar | external | protobuf over Pulsar topics | repo-owned `.proto` schemas with Haskell and Python generated bindings | production inference surface; successful `InferenceResult` payloads carry either `inline_output` text (LLM and speech families) or a typed `object_ref` into the `infernix-demo-objects` bucket (the artifact families), while failed payloads carry typed `InferenceError` values such as `ModelMemoryLimitExceeded` |
| Coordinator -> engine | internal production path on every substrate | protobuf batches over derived engine-pool Pulsar topics | `src/Infernix/Runtime/Pulsar.hs` plus coordinator-role, engine-pool, and engine-member `.dhall` config | the coordinator role publishes pre-batched inference work to derived pool/model topics with producer dedup. Engine members consume only topics assigned by the validated pool graph. Apple host daemons and Linux Kubernetes workloads share the same pool-routing contract; only placement differs by substrate. |
| Haskell worker <-> engine adapter | internal child-process boundary | protobuf over stdio for Python adapters; argv/stdout for native runners | `src/Infernix/Runtime/Worker.hs`, `python/adapters/`, and native runner entrypoints under engine roots | Python adapters are invoked through their isolated Poetry/venv entrypoints; native runners receive non-secret argv plus optional output directories; text families return engine output text, artifact families return object references, and native local artifact-file markers are uploaded by the Haskell worker using secret-backed MinIO wiring |
| Browser <-> demo WebSocket | external (demo only) | typed framed envelopes (JSON via `Simple.JSON`) carrying server-sent `ConversationState`/`*Patch` snapshots/deltas and client-sent typed actions | handwritten Haskell browser-contract ADTs in `src/Infernix/Web/Contracts.hs` plus generated PureScript bindings via purescript-bridge | absent when `demo_ui = false`; business logic stays Haskell-only |

## State and Artifact Locations

| State class | Authority | Durable home | Notes |
|-------------|-----------|--------------|-------|
| Durable PV directories | storage reconciliation in `cluster up` | `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` | deterministic host path layout for every PVC-backed workload |
| Generated Apple substrate file | binary-owned lifecycle or validation preflight, with `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]` as the explicit helper | `./.build/infernix.dhall` | Apple host path beside the build root; lifecycle staging is a binary responsibility rather than a shell bootstrap responsibility |
| Generated Apple kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` on Apple; Kind create or delete uses transient scratch kubeconfig state under system temp before this file is published |
| Generated Linux substrate file | binary-owned lifecycle or validation preflight, with `docker compose --project-name <lane> --file compose.yaml ... run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>` as the explicit helper; the Dockerfile also creates an image-local build-arg-selected copy during image build | image-local `/workspace/.build/outer-container/build/infernix.dhall` | outer-container staging path; the authoritative launcher binary remains `/usr/local/bin/infernix` inside the substrate image |
| Generated Linux kubeconfig | `cluster up` | `./.data/runtime/infernix.kubeconfig` | durable repo-local kubeconfig reused across fresh outer-container invocations; Kind or `nvkind` create or delete uses transient scratch kubeconfig state under system temp before this file is published |
| Helm dependency archive cache | `cluster up`, `test integration`, `test all`, and any supported chart-reconcile path that calls `ensureHelmDependencies` | image-local `/opt/infernix/chart/charts/` on the Linux outer-container path, exposed to Helm through `/workspace/chart/charts`; `chart/charts/` in the Apple host worktree | cached top-level Helm dependency archives for Harbor, PostgreSQL, Pulsar, and Envoy Gateway |
| Cluster-mounted substrate file | Helm deployment plus ConfigMap mount | `/opt/build/infernix-substrate.dhall` | cluster-resident consumers — `infernix-demo` (frontend), `infernix-coordinator` (Pulsar coordinator role), and `infernix-engine` (engine role on Linux substrates) — consume the cluster-role payload under the shared staged filename at `/opt/build/`; Apple on-host engine daemons read host-role config under `./.build/` |
| Outer-container build root | containerized build or runtime | image-local `/workspace/.build/outer-container/build/` in the outer container | substrate-file root used by the outer-container control plane; carries the staged substrate file only |
| Source snapshot manifest | Linux outer-container image build | `/opt/infernix/source-snapshot-files.txt` inside the substrate image | sorted source snapshot captured from the baked image context before later generated outputs so git-less image runs of `infernix lint files` validate only the baked source tree; the manifest stays in the image overlay |
| Outer-container cabal-home and builddir | Linux outer-container image overlay | the toolchain's natural in-image locations (`/root/.cabal/`, `dist-newstyle/`) | populated during `docker compose build infernix`; not bind-mounted to the host so cabal package state stays in the image overlay |
| Publication state | `cluster up`, `cluster down` | `./.data/runtime/publication.json` | route inventory and substrate metadata |
| ConfigMap publication mirror | `cluster up` | `./.data/runtime/configmaps/infernix-demo-config/` | mirrored cluster-role substrate `.dhall` plus rendered YAML |
| Chosen edge port record | cluster lifecycle | `./.data/runtime/edge-port.json` | records the `9090`-first chosen port |
| Service model cache | service runtime | `./.data/runtime/model-cache/<substrate>/<model-id>/default/` | derived cache keyed by substrate and model |
| Generated frontend contract staging | `infernix internal generate-purs-contracts` | `web/src/Generated/` | generated PureScript output only |
| Generated frontend dist | `npm --prefix web run build` | `web/dist/` | ignored static output served by `infernix-demo` |
| Apple adapter venv | Poetry on demand | `python/.venv/` | Apple-only materialized virtualenv for shared adapter project |
| Playwright and test artifacts | validation flows | `./.data/` | repo-local test output location |
| Demo artifact bucket prefixes | demo backend (webapp object-proxy, server-side) | MinIO bucket `infernix-demo-objects` (`users/<userId>/contexts/<contextId>/{uploads,generated}/`) | per-user prefix layout; browsers reach it only through the webapp `/api/objects` proxy; absent when `demo_ui = false` |
| Demo conversation Pulsar topics | demo backend | Pulsar BookKeeper | append-only per-context conversation logs; SSoT for sequencing and text; the integration suite validates real publish + Reader decode, duplicate frontend publish collapse, and completed result writeback from a non-chaos dispatcher/result-bridge prompt roundtrip; absent when `demo_ui = false` |
| Demo metadata Pulsar topics | demo backend | Pulsar BookKeeper | compacted per-user contexts and drafts topics keyed by `contextId`; SSoT for the left-rail list and unsubmitted drafts; the integration suite validates real publish + Reader decode with key assertions, admin compaction threshold readback, explicit topic compaction, compacted-reader latest-per-key behavior, and duplicate draft publish collapse; absent when `demo_ui = false` |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-ha-platform-services-and-edge-routing.md](phase-3-ha-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-e2e-and-ha-hardening.md](phase-6-validation-e2e-and-ha-hardening.md)
- [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md)
- [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md)
- [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md)
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
