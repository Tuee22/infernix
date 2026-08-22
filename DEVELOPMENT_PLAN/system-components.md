# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for operator surfaces, supported
> substrates, and durable state locations in `infernix`.

## Current Execution State

Phase 0 is Done: the plan corpus satisfies the mechanical Section C, D, I, J, and Q scans that
`infernix lint plan` implements, and those scans run inside the aggregate lint gate. Phases 1 through
3 and 5 are Done, closed in numerical order on Apple accelerator cohorts plus their paired `linux-cpu`
cohorts, and Phases 7 and 9 are Done on those same receipts. Since Sprint 0.25 a phase's status
describes only the scope it owns, so those closures need no allowance and are not reverted by an
earlier phase gaining sprints.

Phases 4, 6 and 8 are Active. Phase 6 Sprints 6.44 and 6.50 and Phase 8 Sprints 8.9, 8.10 and 8.13 are
implementation-complete and consume the same `linux-gpu` cohort plus its paired `linux-cpu` lane,
which needs a CUDA-capable Linux host; Section Q forbids substituting the other accelerator, so they
are validation-only residuals. Phase 4 Sprints 4.37 through 4.42 and Phase 6 Sprint 6.51 are open code
work — the Bounded Engine Launch host and device halves. Each phase document names its own open
sprints, and [README.md](README.md) holds the plan's single phase-status table.

[Wave Y](cohort-validation-waves.md) is Done and owns the Apple and paired source-matched
`linux-cpu` component closure for `llm-smollm2-safetensors`, `audio-demucs-htdemucs`,
`audio-open-unmix`, `music-mt3-infer`, `music-mr-mt3`, `music-omnizart`, and `audio-bark-small`.
Each lane record binds frozen source identity, lane, model id, adapter and engine-artifact identity
with manifest digest, request and result identity, terminal status, real-output witness, and the
exact command and settlement receipt. Apple additionally owns the materializer run, the installed
smokes, cancellation and installed-Python source isolation, the typed `image-sdxl-turbo` refusal,
and `integration` / `e2e` / `all`; `linux-cpu` owns its source-matched image and materialization
identity, the same seven outputs, and its full cohort gate.
[Wave Z](cohort-validation-waves.md) is the queued accelerator wave and owns the Phase 6 Sprint 6.44
NVIDIA enforcement sign-off, whose `linux-gpu` half Phase 6 Sprint 6.50 and Phase 8 Sprints 8.9, 8.10
and 8.13 also consume. Waves AC and AD are declared for the Bounded Engine Launch host and device
halves and are not scheduled ahead of it. Every
per-lane attestation lives in [cohort-validation-waves.md](cohort-validation-waves.md), and every
superseded surface is inventoried in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Current Repo Assessment

- the typed execution-plan refactor is landed code-side: the generated Dhall is proper unions
  throughout, compilation produces an opaque `RuntimePlan`, the engine refines declared enforcers
  against live OS evidence, only `ExecutableModel` values reach routing, and every subprocess is
  gated behind a bounded command, provisioning, or resource-indexed inference capability. The
  reflected substrate schema went from 110 lines to 54 as the derivable wire fields were deleted.
  Behavioral sign-off for its `linux-gpu` arm is the open residual in Phase 8 Sprints 8.9 and 8.10.
  See [Typed Execution Plan](../documents/architecture/typed_execution_plan.md)
- the bounded-command kernel replacement uses public Haskell process APIs: the parent self-execs
  one anchor with closed descriptor inheritance, an explicit environment, a new process group, and
  standard-stream framing. The required replacement starts the supervisor inside the anchor group
  and a self-exec pin inside the supervisor group, forwarding both provisional birth identities to
  parent custody before either helper detaches. A version-3 activity lease persists exact
  owner/anchor/supervisor/pin birth identities, while a bounded fsynced version-3 common-boot or
  version-4 distinct-boot incoming-intent filename preserves them across a crash before payload
  write. The arbitrary target remains a supervisor-owned unreaped child rather than a persisted
  birth identity. A hidden rank-2 linear session orders
  `AnchorReady -> SupervisorReady -> LeaseDurable -> TargetRunning`. The obsolete repository-owned
  subprocess C file and Cabal declaration are removed
- the Apple capped-engine footprint observer uses only fixed absolute `/usr/bin/top` process-group
  discovery and `/usr/bin/footprint` exact-byte measurement under one total deadline, bounded
  captures, an explicit environment, and exhaustive cleanup. The direct-FFI sampler and its prior
  evidence are superseded; Phase 4 Sprint 4.32 is closed on both its exact-source `linux-cpu` half
  and its selected Apple accelerator half, including the observer and adversarial-breach proof
- the repo ships the one-binary Haskell role topology, Envoy Gateway assets, the PureScript demo UI,
  the split runtime modules under `src/Infernix/Runtime/`, the shared Python project, the shared
  Linux substrate Dockerfile that bakes the source-snapshot manifest used by git-less
  `infernix lint files` runs, the route registry, and the snapshot launcher
- the supported CLI reads the active substrate from repo-root `./infernix.dhall`, without a
  user-facing runtime-mode flag
- `infernix init` is the supported operator creation path for `./infernix.dhall` and
  `./infernix-host.dhall`; `infernix test init` creates the separate `./infernix.test.dhall`
- ordinary lifecycle and validation commands validate the initialized config and fail fast naming
  the required init when it is absent; focused `infernix lint ...` and `infernix docs check` remain
  config-independent
- the Apple stage-0 `up` wrapper explicitly runs `./.build/infernix init --if-missing` before
  delegating to `cluster up`; internal image/test generation is not an operator preflight path
- the runtime config, `cluster status`, publication JSON, demo config, and generated
  browser contracts still expose that active substrate through `runtimeMode` field names
- cluster publication derives a cluster-role deployment mirror from the runtime config and mounts
  it inside cluster workloads at `/opt/build/infernix.dhall`
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
  `demo_ui = false` route/publication assertions. Wave J's two-worker placement, node-drain, and
  anti-affinity results are historical evidence for the retired replicated topology. The current
  Linux CPU shape has one worker, one engine, and one instance of each platform service; its
  current-source lifecycle proof is pending under Phase 3 Sprint 3.16 / Phase 6 Sprint 6.47.
  Physical Apple multi-host proof is hardware-deferred while no second Apple host is available.
  Existing workers use typed Python or native adapter harnesses after the coordinator eagerly stages
  every configured model in `infernix-models` behind the `warm-model-cache` barrier, and publish the
  typed per-family result surface; the selected `linux-gpu` plus `linux-cpu` real-output proof
  closed under [Wave I](cohort-validation-waves.md). Unsupported adapter ids fail fast instead of
  returning a generic success payload
- Linux operator workflows close around Compose-driven outer containers, validation reports the
  active initialized substrate for the complete selected-substrate suite, and
  `infernix init --demo-ui false` can emit `demo_ui = false`
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
  resolution before its fixed, authority-derived build/install step. Operators invoke
  `./bootstrap/apple-silicon.sh build`, then use the generated `./.build/infernix` closed command
  surface; bare host Cabal is not a supported validation entrypoint. Phase 1 Sprint 1.24 replaces
  the former Custom Setup compiler/plugin path with four exact tracked Haskell generator outputs and
  a Linux-only regeneration gate, so Darwin has no standalone protobuf compiler prerequisite. Apple
  adapter setup or validation paths reconcile the Homebrew-managed `python@3.12` formula and
  `python3.12` command plus a user-local Poetry bootstrap on demand. The native-only workflow
  doctrine requires Docker-backed Apple work to use the current native arm64 Docker daemon and
  forbids Docker-context creation or switching, Colima VM creation, and cross-architecture
  emulation; Phase 1 Sprint 1.12 replaced the previous Colima reconciliation path with selected
  Docker-context and daemon-architecture validation and closed on positive lifecycle/full-test
  evidence plus negative no-daemon boundary evidence. The Poetry bootstrap may reuse an already
  available compatible Python 3.12+ executable when one passes the implemented version check
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
  webapp `/api/objects` proxy; [Wave M](cohort-validation-waves.md) closed that route surface with
  `linux-cpu` plus selected `linux-gpu` validation.) `web/src/Infernix/Web/Auth.js` mirrors the
  active Keycloak access token into the `infernix_operator_token` cookie on login and refresh,
  clears it during Sign out, then redirects through Keycloak OIDC logout so the upstream SSO session
  is cleared. `SecurityPolicy/infernix-operator-routes-jwt` now **authenticates and
  admin-authorizes** — it accepts that cookie or a direct `Authorization: Bearer ...` header and
  then requires the `infernix-admin` realm role before forwarding the four operator route prefixes
  (`/harbor`, `/harbor/api`, `/pulsar/admin`, `/pulsar/ws`); the same cookie authenticates
  browser-issued media `src` GETs against the webapp `/api/objects/download` proxy
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
- the shared lifecycle exposes `lifecycleStatus`, `lifecyclePhase`, `lifecycleDetail`, and
  heartbeat timestamps during monitored Docker build, Harbor publication, Harbor-backed final-image
  preload, and Apple retained-state replay work; runtime-config generation is atomic for
  concurrent readers. The retired Patroni replica-reinitialization path is not part of the current
  single-instance service topology. Sprint 2.15 adds the persisted `ClusterOwner`
  (`OperatorOwned` / `HarnessOwned`) and a `ClusterMutating` (mutation-incomplete) `lifecyclePhase`,
  so a killed test's cluster is reported dirty and reconciled on the next `cluster up` rather than
  read as a false `steady-state`. [Wave X](cohort-validation-waves.md) closes that scope; Phase 6
  Sprint 6.43 owns the later owner-atomic reservation and teardown correction
- Phase 2 carries the memory-admission and publication-verification corrections its own cohort must
  still exercise: `audio-bark-small` declares an 8192 MiB footprint, admitted placements carry a
  strict integration completion rule, the Playwright catalog-matrix runtime-ceiling escape hatch is
  removed, and exact Apple and Linux admission unit tests are implemented. The Bark adapter loads
  fp16 on MPS or CUDA and fp32 on CPU, generates under inference mode, and serializes fp32 WAV. The
  final audit's registry-only Harbor verifier is implemented: a bounded authenticated
  platform-selected skopeo copy reads the Harbor manifest, config, and layers into a fresh
  birth-identity-owned mode-0700 `dir:` store, with primary-preserving cleanup and focused command,
  redaction, and path coverage. Phase 2 is blocked by Phase 1, and Phase 4 and Phase 6 validation
  are ordered after their predecessors
- the shared lifecycle skips broad pre-Harbor support-image preloads; shell scripts never pull or
  publish images, supported lanes hydrate and stream only the narrow Harbor warmup dependency set
  into Kind before Helm warmup, only Harbor-required services may pull upstream before Harbor is
  responsive, and every remaining image, including the active `infernix` runtime image, is loaded
  into Harbor before final rollout
- legacy validation proof points are inventoried in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Retired Historical
  Validation Evidence"; [cohort-validation-waves.md](cohort-validation-waves.md) records Wave A and
  Wave C as historical evidence for their frozen source identities, not the reopened Phase 2 source.
  Phase 2 retains landed implementation plus dead-owner recovery and failure-cleanup evidence, and
  its own closure follows Phase 1 and precedes the Apple Silicon and `linux-cpu` resumption
- [cohort-validation-waves.md](cohort-validation-waves.md) records the closed lane attestations:
  Wave F for the native arm64 `linux-cpu` publication and full-suite path through the selected
  native arm64 Docker daemon, Wave J for the Linux GPU/CUDA plus rebuilt-image `linux-cpu`
  engine-pool placement and backpressure surface, Wave M for the webapp object-proxy reopen, Wave N
  for generated-artifact ownership, Wave P for the MT3 catalog replacement plus Phase 8, Wave Q for
  the Phase 9 access-control and monitoring RBAC/STS/dashboard surface on both `apple-silicon` and
  `linux-cpu`, and Wave U for the Sprint 9.9 logout and account-switching rerun on `linux-cpu` plus
  the selected `linux-gpu`
- Beyond the Phase 9 admin overview (`/api/admin/overview`) and per-user personal dashboard, no
  general observability stack (metrics, tracing, log aggregation) is deployed.
  Monitoring is not a supported first-class surface.

## Operator and Host Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Apple host control plane | `./bootstrap/apple-silicon.sh build` plus the generated `./.build/infernix` closed command surface, backed internally by the authority-derived ghcup toolchain | host-native | canonical operator surface on Apple Silicon; host-native cluster lifecycle owner; host-side Apple inference-daemon owner; repo-local kubeconfig owner; uses a host-local scratch kubeconfig under system temp for Kind create or delete before publishing the durable repo-local kubeconfig | `./.build/`, `./.data/` |
| Apple headless Metal/Core ML materialization lane | typed engine-artifact manifests plus public upstream MLX/coremltools APIs behind a hidden opaque rank-2 provisioning/session facade; replacement for the legacy `tart` / `hostTart` / `AppleTart`, repository-owned native bridge, and raw install-first implementations, with the retained `materialize-metal-engines` command as the whole-plan facade | host-native Apple process | runs closed provisioning operations through the bounded self-exec kernel; fully hydrates, relocates, authoritatively smokes, records exact provenance, and actual-payload-hashes a sibling candidate before fsynced activation with rollback/crash reconciliation. MLX executes and synchronizes a real GPU operation, coremltools reports available compute devices, and native runner roots hydrate real host CLIs/venvs/apps. The generic closure policy stays strict: every symlink inside a hashed package closure must be relative and must not escape the closure root, and a candidate carrying an unsafe link fails the provisioning session closed. The Audiveris invocation therefore declines JavaCPP symbolic-link creation on every lane, so its extraction cache is a plain tree of regular files: JavaCPP's only fixed point is an absolute self-referential link naming its configured cache directory, which it re-establishes on every load and which names whichever root the payload currently occupies, so no spelling survives both the candidate smoke and the post-rename installed smoke. Declining the alias — which no library load traverses — makes the payload relocation-invariant rather than repaired, and the strict-relative closure policy is left as the sole defence against a stray absolute link. Sprint 1.20's correction set is implemented; the complete governed gates precede the materializer run, and the specialized validators run after it. Wave Y retains the materializer, installed smokes, cancellation and installed-Python source isolation, the exact seven-row Apple attestation, the typed `image-sdxl-turbo` refusal, and the paired source-matched `linux-cpu` closure; Wave AA's separate bounded-host-memory proof is closed and is not rerun. Wave L is historical routed real-output evidence for its then-active catalog only | engine artifacts under `./.data/engines/<adapterId>/`; optional immutable payloads in `infernix-engine-artifacts` |
| Linux native engine materialization lane | `src/Infernix/Engines/LinuxNative.hs` plus `infernix internal materialize-linux-native-engines` | Linux substrate image build | writes typed metadata roots under `/opt/infernix/engines/<adapterId>/`; a Cabal-hidden catalog selects image-owned llama.cpp, whisper.cpp, Python interpreter/module, or Audiveris JRE/classpath targets directly, and the manifest binds the selected target plus its immutable runtime closure to descriptor-derived identities and digests. No generated `bin/*` command wrapper is permitted. Fresh corrected-topology cohort evidence remains open under Phase 1 Sprint 1.20 and the reopened Phases 4/6 | image-owned `/opt/infernix/engines/<adapterId>/`; optional immutable payloads in `infernix-engine-artifacts` |
| Linux outer-container control plane | `docker compose --project-name <lane> --file compose.yaml ... run --rm infernix infernix ...` | Linux container | only supported Linux CLI surface for `linux-cpu` and `linux-gpu`; the GPU lane prefixes the same single Compose file with `LAUNCHER_IMAGE=infernix-linux-gpu:local` to select the CUDA snapshot, forwards the Docker socket, and bind-mounts only `./.data/` while the build root, source snapshot, and chart archives stay in the image overlay; uses a launcher-local scratch kubeconfig under system temp for Kind or `nvkind` create or delete before publishing the durable repo-local kubeconfig | `./.data/`, `./.data/runtime/infernix.kubeconfig` |
| Bootstrap shell entrypoints | `bootstrap/*.sh` | host shell | bounded stage-0 prerequisite and launcher builders; Apple builds the host binary, Linux installs Docker or CUDA prerequisites and enters `docker compose run --rm infernix infernix <command>`; lifecycle, validation, Kind, Kubernetes manifests, cluster workload image pulls, Harbor publication, and teardown behavior are delegated to `infernix` | preserves `./.build/`, `./.data/`, host-level images, Apple host binaries, and installed prerequisites |
| Command registry | Haskell command registry | host or outer container | owns the supported command inventory, `--help` output, and the generated CLI-reference sections that docs lint enforces, including the `infernix service --config` explicit substrate override for targeted daemon validation | none |
| Runtime configuration | the **system contract**: repo-root typed Dhall record at `./infernix.dhall`, decoded in-process by the `dhall` Haskell library | host or outer container | primary source of truth for active substrate, the pool graph and the model descriptors each pool owns, inference placement, Pulsar request/result/batch topics, active engine dispatch, routed Apple bridge behavior, and test scope; byte-identical on every machine in a fleet; `infernix init` creates the operator file atomically, `infernix test init` creates the harness input, and ordinary config-dependent commands fail fast rather than auto-materializing it; `infernix service --config PATH` may intentionally point one daemon at an explicit config for targeted diagnostics | repo-root `./infernix.dhall`; harness input `./infernix.test.dhall`; cluster deployment mirror at `/opt/build/infernix.dhall` |
| Machine contract | the `machine` block of the repo-root host manifest `./infernix-host.dhall` | host or outer container | this box's default daemon role (overridden per process by `infernix service --role`), the engine member identities it may adopt, its model-cache quota, and the content digest of the system contract it was generated against; the pools it serves are derived from its members against that pinned graph. A `Machine` block always carries its pin; `ImageDefault` is the byte-identical manifest the launcher image bakes and describes no machine, so a daemon started against it is refused by name | repo-root `./infernix-host.dhall`; image default at `/opt/infernix/dhall/InfernixHost.dhall` |
| Route registry | Haskell-owned route inventory | host or outer container during render or reconcile | records public prefixes, backend identity, rewrite rules, visibility, and publication metadata | none |
| Automation entry documents | `AGENTS.md`, `CLAUDE.md`, and their governed canonical-home links into `documents/` | repo source | point assistant users at canonical workflow rules without turning root entry docs into competing topic homes | none |
| Frontend contract generator | `infernix internal generate-purs-contracts` | host or outer container during web build | emits generated PureScript contracts from handwritten Haskell browser-contract ADTs | `web/src/Generated/` |
| Repo-local durable root | local filesystem | repo root | authoritative home for cluster state, runtime state, config publication mirrors, and test artifacts | `./.data/` |
| Build artifact root | explicit Cabal builddir or installdir flags plus generated artifacts | host or outer container | keeps compiled output and generated files out of tracked source paths | `./.build/` on Apple; image-local `/workspace/.build/outer-container/` on the Linux outer-container path |

## Repository Asset Components

| Component | Current content | Purpose | Gap |
|-----------|-----------------|---------|-----|
| Linux substrate image definition | `docker/Dockerfile` | one shared build definition produces the Linux control-plane image and the Linux daemon image family while owning ghcup, Poetry, Node.js 22.5+ for the demo bundle, Playwright runtime packages, Docker buildx for nested Docker operations, npm update-notifier suppression, and the Kind toolbelt; installs Cabal/NPM/Poetry dependency layers from package metadata before the full source copy, binary-generates a build-arg-selected empty-model runtime default inside the image overlay before web build and Python quality checks, and writes a pruned `/opt/infernix/source-snapshot-files.txt` for git-less lint runs; host-native Apple cluster-image builds stamp source-fingerprint, runtime-mode, and fingerprint-version labels so unchanged-source `cluster up` can safely reuse `infernix-linux-cpu:local`; cabal-home and the cabal builddir live at the toolchain's natural in-image locations rather than under any bind-mounted host path; the image uses `tini` as its `ENTRYPOINT` for clean signal handling and zombie reaping | none |
| Playwright runtime | baked into `docker/Dockerfile` (Node, the Playwright runtime, and the three browsers) and invoked from inside the outer container via `npm --prefix web exec -- playwright test --config web/playwright.config.js` on Linux substrates; on Apple Silicon the host-native lane invokes `npm --prefix web exec -- playwright test` from the host CLI against the published localhost edge port using the same typed fixture. Apple routed Playwright validation closed in Waves A.1/A.2, and the rebuilt Linux GPU launcher closed its routed E2E coverage in Wave C. | none |
| Compose launcher | `compose.yaml` | outer-container launcher for supported Linux workflows; the file defines exactly the `infernix` service with two bind mounts (`./.data` and `/var/run/docker.sock`), no `environment:` block, no `build:` block, and a one-shot image selector that defaults to `infernix-linux-cpu:local` while allowing the GPU lane to choose `infernix-linux-gpu:local`. The Phase 3 Sprint 3.10 `playwright` service removal is landed — Playwright now runs inside the same substrate image | none |
| Shared Python adapter project | `python/pyproject.toml`, `python/adapters/` | single **framework-free** adapter tree + `check-code` quality gate for Python-native engines; declares no ML framework so `poetry run check-code` is machine-independent | none in the supported operator contract |
| Per-engine framework venvs (Phase 4 Sprint 4.16; producer consolidated by Phase 1 Sprint 1.23) | `python/engines/<engine>/pyproject.toml` for `transformers`, `vllm`, `pytorch`, and `diffusers`; canonical Haskell plan in `Infernix.Python` | isolated in-project venvs path-depend on the shared `infernix-adapters` package and install mutually conflicting framework wheels in a substrate group. Apple prepares `transformers`, `pytorch`, and `diffusers` with `apple-silicon`; Linux CPU prepares `transformers` and `pytorch` with `linux-cpu`; Linux GPU engine images own selected `cuda` venvs. The project-lock-aware producer publishes a post-install digest marker, and Worker/CappedEngine fail closed when it is absent or stale — there is no shared-venv fallback or request-time repair. Framework adapters return real output or fail closed under the realness lint | `python/engines/<engine>/.venv/` and fixed marker (gitignored derived artifacts) |
| Per-engine engine images and routing (Phase 4 Sprint 4.17) | `docker/Dockerfile`, `docker/engine.Dockerfile`, `src/Infernix/Models.hs`, `src/Infernix/{Types,Substrate,DemoConfig}.hs`, `src/Infernix/Runtime/{Daemon,Pulsar}.hs`, `src/Infernix/Cluster*.hs`, `chart/templates/deployment-engine.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js` | the linux-gpu monolith (~121 GB) split into a slim 22.4 GB control-plane/coordinator image (`docker/Dockerfile`, no framework venvs) plus per-engine images (`docker/engine.Dockerfile` = CUDA-runtime base + the binary + one engine's `--with cuda` venv); `Infernix.Models` owns engine name/image mapping (`engineNameForSelectedEngine`, `frameworkEngineNamesForMode`, `perEngineImageName`) plus substrate-neutral pool/member topic derivation; generated runtime configs carry `enginePools`, `engineMembers`, and explicit `engineDaemons` so targeted daemon configs survive Dhall round-trip while normal generated daemon metadata still follows the pool/member graph; the coordinator routes requests to `inference.batch.<mode>.pool.<poolId>.model.<modelId>` and pinned routes use `inference.batch.<mode>.member.<memberId>.model.<modelId>`; `infernix service --role engine --engine-name NAME` selects a stable engine member id; the chart renders one engine process per machine and Harbor overlays carry per-engine images. Repo-owned `linux-gpu` lifecycle values leave per-engine image deployments at zero until the integration/E2E harness selects exactly one for per-model validation. Full serialized routed cluster evidence for the selected per-engine images closed in [Wave I](cohort-validation-waves.md) | none |
| Apple host prerequisite bootstrap | governed docs plus Haskell bootstrap logic | minimize Apple pre-existing host installs and let `infernix` reconcile supported Homebrew-managed tools and Poetry bootstrap while requiring any Docker-backed work to use the already selected native arm64 Docker daemon; Docker readiness validation reports the current context and daemon architecture without creating or switching contexts or creating a VM | none |
| Testing doctrine docs | `documents/engineering/testing.md` and `documents/development/testing_strategy.md` | keep one canonical testing doctrine together with one operator-facing detail layer | none |
| Browser-contract source | `src/Infernix/Web/Contracts.hs`, `web/package.json` | keeps handwritten Haskell contract source out of `Generated/` while preserving generated PureScript output there | none |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | hold repo-owned workloads, ConfigMaps, Gateway resources, and third-party chart dependencies | none |
| Kind topology reference assets | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml` | tracked topology references and chart-lint inputs for the substrate-specific Kind shapes; the supported lifecycle renders the active runtime config from Haskell into `./.build/kind/cluster-<runtime-mode>.generated.yaml` before invoking Kind or nvkind. Each reference uses one worker; the current `linux-cpu` lifecycle gate asserts the collapsed topology reaches readiness with no `Pending` replica | none |
| Protobuf contract assets | `proto/infernix/...` plus on-demand generated `tools/generated_proto/` stubs under a `tools/` directory that may be absent in a clean checkout | define canonical runtime, manifest, and event schema boundaries | generated stubs must stay untracked |

## Cluster and Publication Components

| Component | Technology | Deployment | Purpose | Durable state |
|-----------|------------|------------|---------|---------------|
| Kind and Helm lifecycle | Haskell control-plane orchestration in `cluster up` | host-native Apple CLI or Linux outer container | create or reuse Kind; on detached-snapshot lanes scrub the explicit rebuildable Patroni/Harbor set only from the post-delete local retained copy under `WriterQuiesced`; retry recursive claim-root chmod when a rebuildable directory or child disappears during repair and leave the root present after the bounded missing-path race window; reset StorageClasses, reconcile PVs, deploy Harbor first, publish the cluster-role runtime-config mirror, perform Harbor-first image preparation, run dedicated Keycloak/Pulsar preparation phases where required, apply final workloads without rerunning Helm hooks, deploy coordinator and engine roles, expose lifecycle progress, repair precise retained Pulsar/Patroni failure shapes, enforce local resource envelopes, and render the substrate-specific local validation topology | `./.data/runtime/cluster-state.state`, `./.data/kind/<runtime-mode>/...` |
| Harbor image preparation | Harbor plus Haskell image publication flow | Kind cluster plus control plane | bootstrap Harbor with explicit resource envelopes and only its required upstream-pull support services, then mirror every remaining third-party image and publish the active runtime before final rollout; `BlobServable` is minted only after bounded authenticated platform-selected skopeo copy reads the selected manifest, config, and layers from Harbor into a fresh protected `dir:` store independent of Docker's cache; rebuildable registry state may be scrubbed only from the post-delete detached retained copy under `WriterQuiesced` | Harbor registry/cache state under `./.data/kind/<runtime-mode>/...` is rebuildable; durable product blobs remain in MinIO `infernix-models`, `infernix-engine-artifacts`, and `infernix-demo-objects` |
| PostgreSQL substrate | Percona Kubernetes operator plus single-instance Patroni PostgreSQL | Kind cluster | only supported in-cluster PostgreSQL contract for Harbor and later services; rebuildable Patroni roots may be scrubbed only from the post-delete detached retained copy under `WriterQuiesced` before later bring-up recreates them; the current topology has one database instance and one pgBouncer per cluster, with explicit database/proxy/backup resource envelopes bounding startup pressure | `./.data/kind/<runtime-mode>/...` |
| Publication state | repo-local JSON plus routed `/api/publication` surface | repo-local state and demo API | reports control-plane context, cluster daemon location, host inference executor presence when the active substrate is Apple, the routed demo API upstream mode, the active inference dispatch mode, derived engine-pool routing metadata, the active substrate through its current `runtimeMode` field, routes, and upstream health metadata | `./.data/runtime/publication.json` |
| Edge Gateway controller | Helm-installed Envoy Gateway controller | Kind cluster | owns all browser-visible and host-consumed routing | none |
| Cluster Gateway resource | `GatewayClass/infernix-gateway` plus `Gateway/infernix-edge` | Kind cluster | single localhost-bound HTTP listener on the chosen edge port | none |
| HTTPRoute rendering | data-driven `chart/templates/httproutes.yaml` from the Haskell route registry | Kind cluster | publishes the route inventory for demo, Harbor, and Pulsar surfaces (MinIO has no external gateway route since Phase 3 Sprint 3.13; the browser reaches it only through the webapp `/api/objects` proxy) | none |
| Runtime-config publication | generated `ConfigMap/infernix-demo-config` plus repo-local deployment mirror | Kind cluster and repo-local state | derives and publishes the cluster-role payload from repo-root `./infernix.dhall`; cluster consumers use the mount `/opt/build/infernix.dhall`, while Apple host daemons read the repo-root operator config | `./.data/runtime/configmaps/infernix-demo-config/` |
| Service runtime daemons | `infernix service` plus `src/Infernix/Runtime/{Daemon,Cache,KVCache,Worker,Pulsar}.hs`, `src/Infernix/ExecutionPlan.hs`, `src/Infernix/Runtime/Enforcer.hs`, `src/Infernix/Bridge/Result.hs`, `src/Infernix/Bootstrap/Models.hs` | cluster pods on every substrate plus host processes for Apple inference execution | the three-role daemon model uses substrate-neutral engine pools (see [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) and [../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md)). The coordinator owns request fan-in, batching, compiled model-to-pool routing, result writeback, and eager model staging; engine members consume derived pool/model topics, run the compiled binding, own process-local KV cache, and publish typed results. Normal pools use Pulsar `Shared`; pinned routes use per-member `Exclusive` topics. Startup decodes hidden presentation records into `CompiledRuntimePlan`; coordinator paths project `CompiledPlacement` / `CompiledDaemon`, while package-owned live observations refine engine work into `RuntimePlan` / `ExecutableModel`. Oversized Apple/Linux CPU rows remain explicit `UnavailableModel` values and now produce typed `ModelMemoryLimitExceeded` without engine launch; empty/unknown/wrong-route/malformed inputs likewise terminate as failed results before source removal/acknowledgement. Plan-derived bootstrap publication, cross-family topic-collision rejection, raw-publisher removal, and UTF-8 Dhall emission are closed Phase 1 work. Phase 4 owns Apple/Linux CPU adversarial enforcement and encapsulated serialization. Linux GPU plan compilation fails closed with `GpuDualResourceBudgetRequired` until Phase 6 provides independently indexed host-RAM/GPU-VRAM enforcement; Phase 8 owns the final wire schema. The `unboundedEngineSpawnViolations` lint keeps new spawns on the package-internal capped-engine kernel. | none on cluster daemons (Pulsar cursors are broker-side; KV cache is in-memory); Linux engine pod `emptyDir` model caches and Apple host model caches are derived and rebuildable |
| Demo UI host | `infernix-demo` Deployment running `infernix service --role webapp` | cluster pod | serves `/`, `/api`, `/api/publication`, `/api/demo-config`, `/api/models`, `/api/cache`, `/api/objects/{upload,download}`, and `/ws` when demo is enabled; routed manual inference closes through the durable-context Chat surface, where the Webapp role publishes inference work and (on Apple) hands batches off to host inference daemons | none |
| Web runtime executor | PureScript bundle plus Playwright runtime (Node, the Playwright executor, and the three browsers) both baked into `docker/Dockerfile` | substrate image runs cluster-resident as the demo app; routed E2E runs in-container on Linux substrates via `npm --prefix web exec -- playwright test ...` against the routed cluster on Docker's private `kind` network. Apple host-native E2E uses host `npm exec` with the same typed fixture against the published localhost edge port and is covered by Apple cohort validation batches | serves the browser bundle from the clustered demo app and runs routed E2E coverage from the same substrate image | test artifacts under `./.data/` |
| Engine adapter set | shared source in `python/adapters/`; Python-stdio launch through the exact prepared `python/engines/<engine>/.venv/bin/python -m adapters.<module>` | host child process or cluster child process | Python-native engine boundary over typed protobuf-over-stdio; runtime verifies executable, project digest, and fixed marker and never installs or repairs on request | shared quality venv under `python/.venv/`; prepared per-engine venvs under `python/engines/<engine>/.venv/` |
| Per-engine Python environment producer | `Infernix.Python` plus the closed `Infernix.Engines.Provisioning` project language, invoked by `internal materialize-substrate`, Apple startup, and `internal materialize-metal-engines` | Darwin host or Linux CPU base-image build; Linux GPU engine image owns its selected CUDA venv | derives the canonical Python-stdio bindings, installs the substrate group under the project lock, recomputes `pyproject.toml` plus optional post-install `poetry.lock` digest, publishes/reads back the fixed marker, and fails closed on unavailable or malformed evidence | `python/engines/<engine>/.venv/` and `.infernix-framework-groups-*` marker |
| Python quality gate | `poetry run check-code` | host or Linux outer-container image | runs `mypy --strict`, `black --check`, and `ruff check` against the shared adapter tree | none |
| Keycloak identity | Keycloak Helm release | Kind cluster, demo-gated | OIDC identity provider for the durable-context demo: self-signup on, email verification off, public SPA client reconciled for the routed edge URL; the local demo runs one Keycloak application pod until proxy-affinity or clustered-cache validation lands, and is absent when `demo_ui = false`; see [../documents/tools/keycloak.md](../documents/tools/keycloak.md) | Keycloak Patroni Postgres state under `./.data/kind/<runtime-mode>/...` |
| Keycloak Patroni Postgres | Percona PostgreSQL operator | Kind cluster, demo-gated | dedicated single-instance Patroni cluster backing Keycloak; absent when `demo_ui = false` | `./.data/kind/<runtime-mode>/...` |
| Demo artifact bucket | MinIO bucket `infernix-demo-objects` | Kind cluster, demo-gated | single shared bucket holding per-user prefix trees `users/<userId>/contexts/<contextId>/{uploads,generated}/`; the webapp `/api/objects` proxy reads/writes it server-side per user (no browser presigned URL); absent when `demo_ui = false`; see [../documents/tools/minio.md](../documents/tools/minio.md) | MinIO durable state under `./.data/kind/<runtime-mode>/...` |
| Demo conversation Pulsar topics | Pulsar topic family `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` | Pulsar broker, demo-gated | per-context append-only conversation log; single-partition, broker-assigned `MessageId` is the canonical sequence; producer-side dedup supports an effectively-once observable terminal outcome over at-least-once delivery; the current integration suite validates real publish/Reader decode, duplicate frontend publish collapse, and completed result writeback on the supported non-chaos lifecycle path; absent when `demo_ui = false` | Pulsar BookKeeper state |
| Demo per-user metadata topics | Pulsar topic families `demo.user.<userId>.contexts` and `demo.user.<userId>.drafts` | Pulsar broker, demo-gated | compacted per-user metadata for the left-rail context list and drafts; broker message key is `contextId`; the integration suite validates real publish + Reader decode with key assertions, admin compaction threshold readback, explicit topic compaction, compacted-reader latest-per-key behavior, and duplicate draft publish collapse; absent when `demo_ui = false` | Pulsar BookKeeper state |
| Inference batch topics | Derived pool/model topic family `persistent://infernix/demo/inference.batch.<mode>.pool.<poolId>.model.<modelId>` plus pinned-member topic family `persistent://infernix/demo/inference.batch.<mode>.member.<memberId>.model.<modelId>` | Pulsar broker | the coordinator publishes pre-batched inference work only to topics derived from the validated engine-pool graph. Normal pool topics use `Shared` so broker permits and receiver backlog distribute work; pinned member topics use `Exclusive`. The old `inference.batch.<mode>`, `inference.batch.<mode>.<engine>`, and Apple `.host` helper topics are removed from supported routing. | Pulsar BookKeeper state |
| Platform model bucket | MinIO bucket `infernix-models` | Kind cluster, always-on (not demo-gated) | platform-owned model weights, tokenizers, and configs; eagerly staged at coordinator startup from the mounted `infernix.dhall` model set (a `warm-model-cache` cluster-up barrier blocks until all are `.ready`); per-model `.ready` sentinel object written last marks an atomic publish; Linux engine pods and Apple host engine members stream from here into derived model caches | MinIO durable state under `./.data/kind/<runtime-mode>/...` |
| Model-cache staging + fallback topic | eager coordinator staging plus the fallback Pulsar topic `persistent://infernix/system/model.bootstrap.request` and `model.bootstrap.ready.<modelId>` family | Pulsar broker, always-on | effectively-once model population workflow (at-least-once delivery collapsed by producer dedup and the `.ready` guard): on startup the coordinator iterates the mounted `infernix.dhall` model set and, per model, downloads from the upstream URL in the mounted `infernix.dhall` → uploads to `infernix-models/<modelId>/` → writes `.ready` sentinel last → publishes ready event keyed by `modelId`; the `warm-model-cache` cluster-up barrier blocks until all are `.ready`. An engine that hits an unstaged model can still publish a fallback bootstrap request (dedup key `modelId@requestedAt`), serviced by the same coordinator Failover subscription; the MinIO `.ready` guard prevents duplicate effective population. The integration suite validates real ready-topic publish + Reader decode with key assertion and staging dedup across coordinator replacement (exactly one ready event); the coordinator is the only daemon with outbound-internet egress to upstream model hosts | Pulsar BookKeeper state |

## Runtime and Validation Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| Cluster reconcile | `infernix cluster up` | require the initialized runtime config, then reconcile Kind, storage, Harbor-first bootstrap, image publication, the cluster runtime-config mirror, publication state, edge port, and repo-local kubeconfig while recording lifecycle phase, child operation, and heartbeat; uses scratch kubeconfig state under system temp for Kind or `nvkind` create/delete and may repair retained-state Harbor PostgreSQL replicas or recycle unready startup pods without turning StatefulSet name reuse into the gate |
| Cluster status | `infernix cluster status` | report cluster presence, active substrate, publication/routing metadata, lifecycle action/phase/detail/heartbeat, `ClusterOwner`, and mutation-incomplete `ClusterMutating`. Phase 2 owns its own closure after Phase 1, Apple, and `linux-cpu`. The command is observational |
| Kubernetes wrapper | `infernix kubectl ...` | scoped, allowlisted read-only diagnostic wrapper around upstream `kubectl` against the repo-local kubeconfig |
| Cache lifecycle | `infernix cache status`, `infernix cache evict`, `infernix cache rebuild` | inspect or reconcile derived runtime cache state without mutating authoritative sources |
| Focused lint | `infernix lint files`, `infernix lint docs`, `infernix lint proto`, `infernix lint chart` | run the repo-owned focused lint entrypoints for files, docs, `.proto`, and chart assets. File lint rejects the governed repo-owned native-source extension set, Cabal native-source fields/native-token CPP definitions, and embedded native-source/compiler relocation; it uses the baked source snapshot inside git-less images and invokes Git with a scoped `safe.directory=<repo>` override for mounted-source runs so validation does not depend on global Git config |
| Aggregate static validation | `infernix test lint` | validate the initialized runtime config at command entry, then run the focused lint entrypoints together with Haskell style/build and Python quality checks |
| Docs validation | `infernix docs check` | validate the governed docs suite and phase-plan shape through the canonical docs linter |
| Service runtime | `infernix service` | consume repo-root `./infernix.dhall` at startup, or an explicit `--config PATH` file for targeted diagnostics, and own inference for the active substrate through real Pulsar transport on supported cluster paths, with a repo-local topic-spool harness available only when Pulsar endpoints are intentionally absent |
| Demo UI runtime | `infernix service --role webapp` in the `infernix-demo` Deployment | serve the demo-only HTTP surface against the active initialized catalog |
| Frontend contract generation | `infernix internal generate-purs-contracts` | generate the supported PureScript contract module from Haskell source |
| Unit validation | `infernix test unit` | validate the initialized runtime config at command entry, then run Haskell runtime behavior checks plus PureScript unit suites without claiming cluster matrix coverage |
| Integration validation | `infernix test integration` | validate the initialized substrate's published catalog contract through one substrate-aware integration suite that traverses the README matrix rows, selects the active engine from the effective runtime config, covers every generated active-substrate catalog entry, and carries the supported single-instance lifecycle/recovery assertions |
| Routed E2E validation | `infernix test e2e` | exercise the real routed browser surface for the initialized substrate through a substrate-agnostic Playwright suite that relies on `infernix-demo` to read the effective runtime config and dispatch the correct engine |
| Single-accelerator phase closure | chosen accelerator full-suite plus `linux-cpu` evidence | record the phase's chosen accelerator (`apple-silicon` or `linux-gpu`) plus `linux-cpu` attestation; code-side closure and its machine-independent gates stay on one machine in natural order, and the other accelerator is handled only by a sibling phase or later aggregation work |
| In-process Haskell style gates | `src/Infernix/Lint/HaskellStyle.hs`, `test/haskell-style/Spec.hs`, `test/cabal-format/{Spec.hs,cabal.project,infernix-cabal-format.cabal}` | Root-package `infernix-haskell-style` owns the recursive `app/`/`src/`/`test/` inventory and readability rules behind an Ormolu/HLint callback seam, excluding only the exact four generated Proto paths. The genuinely separate Cabal-format package owns the pinned Cabal 3.16 parse/render check for both manifests. `ToolchainCabalFormat` runs it as a closed top-level child under the same sequential authority, keeping Ormolu's Cabal-syntax 3.14 solver world separate from Cabal 3.16 without a runtime install or nested style-tool process. |

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
| Apple Silicon / Metal | `apple-silicon` | host-native control plane, cluster `infernix-coordinator` daemon for request-topic consumption and model-to-pool routing, same-binary host engine daemons with stable host ids consuming assigned derived pool/model topics and publishing results, and clustered support services plus optional routed demo workloads sharing one initialized runtime contract through role-specific deployment mirrors; normal Apple pools use `Shared` across distinct host ids and exact-host routes use pinned `Exclusive` topics; Metal and Core ML native engine artifacts materialize through typed manifests and public upstream MLX/coremltools APIs before host-native execution | Sprint 1.14 retains historical Tart-removal/manifest closure only; its bridge evidence is superseded by active Sprint 1.20. Sprint 7.23 is superseded by Sprint 7.24 engine-pool assignment and broker-native backpressure |
| Linux / CPU | `linux-cpu` | containerized Linux lane built from the shared substrate Dockerfile and driven entirely through Compose on native Linux amd64 or native Linux arm64; publication selects the normalized native host architecture from `InfernixHost.dhall`; the current Kind shape has one worker, one engine process, and one instance of each platform service. Wave J's two-worker/chaos/anti-affinity results are historical; the current collapsed-topology lifecycle run remains under Phase 3 Sprint 3.16 / Phase 6 Sprint 6.47 | current-source lifecycle cohort pending |
| Linux / NVIDIA GPU | `linux-gpu` | GPU-enabled Kind lane built from the shared substrate Dockerfile and deployed from the same CUDA-based image used by the outer container | none |

## Serialization Boundaries

| Boundary | Direction | Format | Owner | Notes |
|----------|-----------|--------|-------|-------|
| Runtime-config generation -> repo-root config | local initialization boundary | typed Dhall record at `./infernix.dhall`, schema reflected from the substrate decoder type | `src/Infernix/ProjectInit.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Models.hs` | `infernix init` creates operator config; `infernix test init` creates the harness input from which a run generates its temporary runtime config; the active substrate selects engine bindings and daemon roles consumed by cluster daemons, Apple host daemons, `infernix-demo`, and the integration suite |
| Runtime config -> ConfigMap publication | control plane | real ConfigMap data plus repo-local deployment mirror | `infernix cluster up` | the repo-local mirror stores the derived cluster-role payload, and cluster-resident consumers, including Apple and Linux cluster daemons plus the routed demo surface, mount it at the compatibility path `/opt/build/infernix-substrate.dhall`; Apple host daemons read repo-root `./infernix.dhall` |
| Browser <-> demo API | external (demo only) | JSON over HTTP | handwritten Haskell browser-contract ADTs plus generated PureScript bindings | production deployments do not expose this surface |
| Inference requester <-> Pulsar | external | protobuf over Pulsar topics | repo-owned `.proto` schemas with Haskell and Python generated bindings | production inference surface; successful `InferenceResult` payloads carry either `inline_output` text (LLM and speech families) or a typed `object_ref` into the `infernix-demo-objects` bucket (the artifact families), while failed payloads carry typed `InferenceError` values such as `ModelMemoryLimitExceeded` |
| Coordinator -> engine | internal production path on every substrate | protobuf batches over derived engine-pool Pulsar topics | `src/Infernix/Runtime/Pulsar.hs` plus coordinator-role, engine-pool, and engine-member `.dhall` config | the coordinator role publishes pre-batched inference work to derived pool/model topics with producer dedup. Engine members consume only topics assigned by the validated pool graph. Apple host daemons and Linux Kubernetes workloads share the same pool-routing contract; only placement differs by substrate. |
| Haskell worker <-> engine adapter | internal child-process boundary | protobuf over stdio for Python adapters; typed target-specific argv/stdout plus descriptor-owned artifact output for direct native targets | `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Runtime/CappedEngine/Internal.hs`, the hidden native target catalog, and `python/adapters/` | Python adapters are invoked through their isolated Poetry/venv entrypoints; direct native targets receive non-secret argv plus an invocation-owned output directory. Text families return engine output text; artifact output is accepted only as a bounded descriptor-validated regular file before the Haskell worker performs secret-backed MinIO upload |
| Browser <-> demo WebSocket | external (demo only) | typed framed envelopes (JSON via `Simple.JSON`) carrying server-sent `ConversationState`/`*Patch` snapshots/deltas and client-sent typed actions | handwritten Haskell browser-contract ADTs in `src/Infernix/Web/Contracts.hs` plus generated PureScript bindings via purescript-bridge | absent when `demo_ui = false`; business logic stays Haskell-only |

## State and Artifact Locations

| State class | Authority | Durable home | Notes |
|-------------|-----------|--------------|-------|
| Durable PV directories | storage reconciliation in `cluster up` | `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` | deterministic host path layout for every PVC-backed workload |
| Apple operator runtime config | `infernix init` | repo-root `./infernix.dhall` plus `./infernix-host.dhall` | ordinary config-dependent commands validate it and fail fast naming `infernix init` when absent |
| Per-machine build ceiling | `infernix init` and `internal materialize-substrate` | untracked repo-root `cabal.project.local` | derived from the host manifest's measured `memory` facts by `Infernix.BuildMemory.deriveBuildMemoryPlan`; states its job count and per-process cap together because neither bounds anything alone. Deleting it reverts to the committed `cabal.project` floor, never to an unbounded build |
| Generated Apple kubeconfig | `cluster up` | `./.build/infernix.kubeconfig` | repo-local kubeconfig used by `infernix kubectl` on Apple; Kind create or delete uses transient scratch kubeconfig state under system temp before this file is published |
| Test-harness config | `infernix test init` plus the reservation-gated harness config transaction | repo-root `./infernix.test.dhall`; temporary repo-root `./infernix.dhall` during the run | the harness owns and restores the runtime config only after reserving the cluster slot |
| Generated Linux kubeconfig | `cluster up` | `./.data/runtime/infernix.kubeconfig` | durable repo-local kubeconfig reused across fresh outer-container invocations; Kind or `nvkind` create or delete uses transient scratch kubeconfig state under system temp before this file is published |
| Helm dependency archive cache | `cluster up`, `test integration`, `test all`, and any supported chart-reconcile path that calls `ensureHelmDependencies` | image-local `/opt/infernix/chart/charts/` on the Linux outer-container path, exposed to Helm through `/workspace/chart/charts`; `chart/charts/` in the Apple host worktree | cached top-level Helm dependency archives for Harbor, PostgreSQL, Pulsar, and Envoy Gateway |
| Cluster-mounted runtime-config mirror | Helm deployment plus ConfigMap mount | `/opt/build/infernix-substrate.dhall` | cluster-resident consumers — `infernix-demo` (frontend), `infernix-coordinator` (Pulsar coordinator role), and `infernix-engine` (engine role on Linux substrates) — consume the cluster-role deployment mirror; Apple on-host engine daemons read repo-root `./infernix.dhall` |
| Fleet machine contracts and claim topics | `cluster up` publication plus `chart/templates/configmap-machine-contracts.yaml`, `chart/templates/deployment-engine.yaml`, and `Infernix.EngineRouting.engineMemberClaimTopicForMode` | `ConfigMap/infernix-machine-contracts` (one binary-rendered manifest per machine, mounted at each pod's `/workspace/infernix-host.dhall`); one derived `persistent://infernix/demo/fleet.member-claim.<mode>.<member>` topic per member | present only when the system contract declares more than one engine machine (`infernix init --engine-machines N`). Each machine's contract names exactly one member identity, so the byte-identical image-baked manifest cannot make two machines the same one, and the published system contract is mounted at the repo-root contract path beside it so a fleet pod holds a real generated pair. The Kind topology grows one worker per machine, labelled `infernix.fleet/slot`, and the engine deploys as one `infernix-engine-m<slot>` Deployment per machine with `--engine-name` as a compiled constant. Each machine holds the only `Exclusive` subscription on its claim topic for its consuming life; a second machine on the same identity is refused by name after a bounded wall-clock reacquisition window, and a lost claim is fatal. The single-machine deployed topology renders none of this and is unchanged | claim topics are broker-owned durable state; the machine contracts are generated and untracked, like every other `.dhall` |
| Outer-container build root | containerized build or runtime | image-local `/workspace/.build/outer-container/build/` in the outer container | generated build output only; it is not the operator runtime-config authority |
| Source snapshot manifest | Linux outer-container image build | `/opt/infernix/source-snapshot-files.txt` inside the substrate image | sorted source snapshot captured from the baked image context before later generated outputs so git-less image runs of `infernix lint files` validate only the baked source tree; the manifest stays in the image overlay |
| Outer-container cabal-home and builddir | Linux outer-container image overlay | the toolchain's natural in-image locations (`/root/.cabal/`, `dist-newstyle/`) | populated during `docker compose build infernix`; not bind-mounted to the host so cabal package state stays in the image overlay |
| Publication state | `cluster up`, `cluster down` | `./.data/runtime/publication.json` | route inventory and substrate metadata |
| ConfigMap publication mirror | `cluster up` | `./.data/runtime/configmaps/infernix-demo-config/` | mirrored cluster-role substrate `.dhall` plus rendered YAML |
| Chosen edge port record | cluster lifecycle | `./.data/runtime/edge-port.json` | records the `9090`-first chosen port |
| Service model cache | service runtime | `./.data/runtime/model-cache/<substrate>/<model-id>/default/` | derived cache keyed by substrate and model |
| Generated frontend contract staging | `infernix internal generate-purs-contracts` | `web/src/Generated/` | generated PureScript output only |
| Generated frontend dist | `npm --prefix web run build` | `web/dist/` | ignored static output served by `infernix-demo` |
| Tracked Haskell protobuf snapshot | canonical `.proto` schemas plus pinned Linux `libprotoc 34.1` / `proto-lens-protoc 0.9.0.1` gate | exactly four modules under `src/Proto/` plus `proto/haskell-bindings.sha256` | generated source, not handwritten; normal builds and Darwin lint consume/hash it without code generation, while the Linux image build regenerates and byte-compares all outputs |
| Shared Apple adapter-quality venv | bounded Poetry provisioning | `python/.venv/` | shared framework-free quality/protobuf environment; not an inference fallback |
| Prepared per-engine Python venvs | shared Haskell materializer before inference | `python/engines/<engine>/.venv/` | Apple: `transformers`, `pytorch`, `diffusers` with `apple-silicon`; Linux CPU: `transformers`, `pytorch` with `linux-cpu`; exact marker binds project inputs |
| Playwright and test artifacts | validation flows | `./.data/` | repo-local test output location |
| Demo artifact bucket prefixes | demo backend (webapp object-proxy, server-side) | MinIO bucket `infernix-demo-objects` (`users/<userId>/contexts/<contextId>/{uploads,generated}/`) | per-user prefix layout; browsers reach it only through the webapp `/api/objects` proxy; absent when `demo_ui = false` |
| Demo conversation Pulsar topics | demo backend | Pulsar BookKeeper | append-only per-context conversation logs; SSoT for sequencing and text; the integration suite validates real publish + Reader decode, duplicate frontend publish collapse, and completed result writeback from a non-chaos dispatcher/result-bridge prompt roundtrip; absent when `demo_ui = false` |
| Demo metadata Pulsar topics | demo backend | Pulsar BookKeeper | compacted per-user contexts and drafts topics keyed by `contextId`; SSoT for the left-rail list and unsubmitted drafts; the integration suite validates real publish + Reader decode with key assertions, admin compaction threshold readback, explicit topic compaction, compacted-reader latest-per-key behavior, and duplicate draft publish collapse; absent when `demo_ui = false` |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-0-documentation-and-governance.md](phase-0-documentation-and-governance.md)
- [phase-1-repository-and-control-plane-foundation.md](phase-1-repository-and-control-plane-foundation.md)
- [phase-2-kind-cluster-storage-and-lifecycle.md](phase-2-kind-cluster-storage-and-lifecycle.md)
- [phase-3-platform-services-and-edge-routing.md](phase-3-platform-services-and-edge-routing.md)
- [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
- [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md)
- [phase-6-validation-and-e2e-hardening.md](phase-6-validation-and-e2e-hardening.md)
- [phase-7-demo-app-durable-context.md](phase-7-demo-app-durable-context.md)
- [phase-8-zero-tracked-dhall-config-and-eager-model-cache.md](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md)
- [phase-9-access-control-and-monitoring.md](phase-9-access-control-and-monitoring.md)
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
