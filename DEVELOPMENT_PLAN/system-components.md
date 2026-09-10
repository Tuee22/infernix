# Infernix System Components

**Status**: Authoritative source
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record component ownership, execution surfaces, state locations, and scoped
> implementation gaps without duplicating phase status.

## Current Execution State

[README.md](README.md#current-phase-overview) owns the single phase-status table.
Code-side work continues at Sprint 3.18; [Waves R1–R9](cohort-validation-waves.md#wave-table)
hold the separate chosen-accelerator plus CPU sign-off obligations.
Component existence is not proof that its target contract or new validation criteria are satisfied.

## Current Repo Assessment

The baseline CLI, cluster, runtime, browser, and access-control surfaces exist.
Their scoped implementation and evidence gaps are recorded below by owning sprint, not by a
second phase-status inventory. Sprints 1.44–1.46 and 2.18 have validated code-side closure; their source/image tuples and controls are recorded in Phases 1 and 2. No new cohort result is claimed. The [deletion ledger](legacy-tracking-for-deletion.md) records
still-existing shortcuts; [governed documents](../documents/README.md) own the target contracts.

## Operator and Host Components

| Component | Owner or location | Contract and remaining work |
|---|---|---|
| Apple host control plane | `bootstrap/apple-silicon.sh`; `./.build/infernix` | Native Apple build/lifecycle surface. Operator inference requires the separately started host engine; source-bound operator validation belongs to [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Apple headless Metal/Core ML materialization | `Infernix.Engines.AppleSilicon` and hidden provisioning modules | Materializes upstream engine payloads under `./.data/engines/<adapterId>/` through bounded candidate verification and activation. Domain lifetime proof precision belongs to [1.46](phase-1-repository-and-control-plane-foundation.md); no historical cohort statement substitutes for its new checks. |
| Linux native engine materialization | `Infernix.Engines.LinuxNative`; `infernix internal materialize-linux-native-engines` | Image-owned targets under `/opt/infernix/engines/<adapterId>/`; hidden target catalog and manifests select direct upstream execution. Behavioral realness controls belong to [4.50](phase-4-inference-service-and-durable-runtime.md). |
| Linux outer-container control plane | `compose.yaml`; `docker compose run --rm infernix infernix ...` | Baked launcher with Docker socket and `./.data/` mounts, plus an independent read-only checkout supplied by bootstrap. No Compose build definition. Source/image binding and validation belong to [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Bootstrap shell entrypoints | `bootstrap/*.sh` | Prerequisite/build/launcher handoff only; binary owns lifecycle and validation. Explicit Linux build and binary-generated seed obligations belong to [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Command registry | Haskell command registry | Owns parsing/help and generated references. Explicit initialization may select a substrate; ordinary operations consume initialized config. `service --config PATH` selects a config for that daemon, not a second configuration language. |
| Runtime configuration | Repo-root `./infernix.dhall`; `Infernix.ProjectInit`, `Infernix.DemoConfig`, `Infernix.Models` | System contract owns substrate and pool/model facts; roles and member identity belong to machine/process scope. Seed generation belongs to [1.44](phase-1-repository-and-control-plane-foundation.md); consumer validation to [8.15](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md). |
| Machine contract | `./infernix-host.dhall` | `machine` union carries role, member identities, cache quota and system-contract digest; `ImageDefault` grants no daemon authority. Live availability and lifetime checks belong to [1.45–1.46](phase-1-repository-and-control-plane-foundation.md). |
| Lifecycle authority | `Infernix.Cluster`; private lifecycle interpreter and lease kernel | Closed linear program owns configured path discovery and held-lock interpretation; code-side validation belongs to [1.46](phase-1-repository-and-control-plane-foundation.md). |
| Route registry | Haskell route inventory | Prefix/backend/rewrite authority; source-bound routed evidence belongs to [3.18](phase-3-platform-services-and-edge-routing.md), backend containment to [5.13](phase-5-web-ui-and-shared-types.md). |
| Automation entry documents | `AGENTS.md`, `CLAUDE.md` | Link to the canonical assistant workflow; do not own parallel workflow rules. |
| Frontend contract generator | `infernix internal generate-purs-contracts` | Emits presentation contracts from Haskell browser ADTs into `web/src/Generated/`; source/bundle binding belongs to [5.13](phase-5-web-ui-and-shared-types.md). |
| Repo-local state root | `./.data/` | Contains both authoritative lifecycle/local-result state and derived mirrors, caches and outputs; durability is classified below, not inferred from the root name. |
| Build artifact root | `./.build/`; image-local `/workspace/.build/outer-container/` | Derived build products; bounded execution and source identity follow [Phase 1](phase-1-repository-and-control-plane-foundation.md). |

## Repository Asset Components

| Component | Current location | Purpose | Scoped remaining work |
|---|---|---|---|
| Linux substrate image definition | `docker/Dockerfile` | Shared launcher/coordinator image build, toolchain, web bundle, browser runtime and baked source inventory | Selected-cohort full-suite evidence: [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Playwright runtime | `docker/Dockerfile`; `web/playwright/` | In-image Linux browser execution; native Apple browser execution through the same typed fixture | Source-bound browser evidence: [5.13](phase-5-web-ui-and-shared-types.md); useful artifact rendering: [7.33](phase-7-demo-app-durable-context.md). |
| Compose launcher | `compose.yaml` | One service, two mounts, explicit image selector; reuses a prebuilt image | Missing/stale image rejection and independent expected-source handoff: [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Shared Python adapter project | `python/pyproject.toml`; `python/adapters/` | Framework-free adapter quality/protobuf project | AST heuristics cannot prove semantic realness; behavioral controls: [4.50](phase-4-inference-service-and-durable-runtime.md). |
| Per-engine framework environments | `python/engines/<engine>/`; `Infernix.Python` | Prepared isolated framework venvs with project-bound markers; no request-time installation | Real engine behavior is validated under [4.50](phase-4-inference-service-and-durable-runtime.md), independently of environment readiness. |
| Per-engine images and routing | `docker/engine.Dockerfile`; `Infernix.Models`; `chart/templates/deployment-engine.yaml` | CUDA framework images selected by compiled pool/member routing; engine facts are projections, not parallel authored `engineMembers`/`engineDaemons` lists | Required device execution and cleanup evidence: [6.55](phase-6-validation-and-e2e-hardening.md); role-contract validation: [8.15](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md). |
| Apple prerequisite bootstrap | `bootstrap/apple-silicon.sh`; host-tool modules | Uses existing native arm64 Docker daemon; no Docker context/VM provisioning | Explicit manual engine workflow evidence: [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Testing doctrine docs | `documents/engineering/testing.md`; `documents/development/testing_strategy.md` | Canonical evidence rules and operator-facing validation detail | Implementation and new receipts remain in the owning sprints and [waves](cohort-validation-waves.md). |
| Browser-contract source | `src/Infernix/Web/Contracts.hs`; `web/package.json` | Haskell ADTs generate browser wire/presentation types | Source binding [5.13](phase-5-web-ui-and-shared-types.md), bounded artifact contract [7.33](phase-7-demo-app-durable-context.md). |
| Helm deployment assets | `chart/Chart.yaml`, `chart/values.yaml`, `chart/templates/` | Workloads, configuration, routes and third-party dependencies | Retained platform/publication evidence: [3.18](phase-3-platform-services-and-edge-routing.md). |
| Kind topology references | `kind/cluster-apple-silicon.yaml`, `kind/cluster-linux-cpu.yaml`, `kind/cluster-linux-gpu.yaml` | Reference inputs; binary renders active topology into `./.build/kind/` | Lifecycle evidence and containment: [2.18](phase-2-kind-cluster-storage-and-lifecycle.md). |
| Protobuf assets | `proto/infernix/`; four tracked modules under `src/Proto/`; generated `tools/generated_proto/` | Canonical schemas, hash-pinned Haskell bindings and untracked Python bindings | Preserve generated ownership and validate changed wire consumers in their owning sprint. |

## Cluster and Publication Components

| Component | Deployment or authority | State and contract | Scoped remaining work |
|---|---|---|---|
| Kind and Helm lifecycle | Binary on Apple host or Linux launcher | Manual retained storage, registry-first bring-up, owner-aware teardown and generated configuration | Domain-held mutation/cleanup and retained lifecycle proof: [2.18](phase-2-kind-cluster-storage-and-lifecycle.md). |
| Registry image preparation | `registry:2` plus binary publication | Registry bootstrap content is rebuildable; blob-servability requires fresh authenticated content reads, not tag presence | Source-bound platform/publication evidence: [3.18](phase-3-platform-services-and-edge-routing.md). |
| PostgreSQL substrate | Percona operator, single-instance Patroni | Platform service PVCs under `./.data/kind/<runtime-mode>/...`; no database standby topology | Retained lifecycle/platform evidence: [2.18](phase-2-kind-cluster-storage-and-lifecycle.md), [3.18](phase-3-platform-services-and-edge-routing.md). |
| Publication state | Binary lifecycle and `/api/publication` | Derived `./.data/runtime/publication.json` reports placement/configuration; placement alone is not a live engine observation | Source-bound publication evidence: [3.18](phase-3-platform-services-and-edge-routing.md). |
| Edge Gateway controller | Envoy Gateway in Kind | Browser-facing routes; Apple internal data-plane access uses separate loopback NodePorts | Routed validation: [3.18](phase-3-platform-services-and-edge-routing.md). |
| Cluster Gateway resource | `GatewayClass/infernix-gateway`; `Gateway/infernix-edge` | Single localhost-bound listener on the selected edge port | Backend and Gateway containment are independently tested by [5.13](phase-5-web-ui-and-shared-types.md). |
| HTTPRoute rendering | `chart/templates/httproutes.yaml`; route registry | Demo, registry and Pulsar routes; no external MinIO route | [3.18](phase-3-platform-services-and-edge-routing.md), [5.13](phase-5-web-ui-and-shared-types.md). |
| Runtime-config publication | `ConfigMap/infernix-demo-config` | Cluster mount `/opt/build/infernix.dhall`; local mirror under `./.data/runtime/configmaps/`; Apple engine reads repo-root config | Binary-owned generation/consumer proof: [1.44](phase-1-repository-and-control-plane-foundation.md), [8.15](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md). |
| Service runtime daemons | `Infernix.Runtime.{Daemon,Pulsar,Worker}`, `Infernix.ExecutionPlan`, `Infernix.Runtime.Enforcer` | Coordinator routes/stages, Engine executes, Webapp serves HTTP/WS. Resource-indexed RAM/VRAM capability code exists; GPU device memory remains detection-only | Cgroup availability [1.45](phase-1-repository-and-control-plane-foundation.md), artifacts [4.50](phase-4-inference-service-and-durable-runtime.md), mandatory GPU proof [6.55](phase-6-validation-and-e2e-hardening.md), replay/KV/cancel [7.30–7.32](phase-7-demo-app-durable-context.md). |
| Demo UI host | `infernix-demo` running `service --role webapp` | Demo-gated API/WS/static host; coordinator, not Webapp, batches/routes engine work | Static containment [5.13](phase-5-web-ui-and-shared-types.md), media [7.33](phase-7-demo-app-durable-context.md), cache API [9.12](phase-9-access-control-and-monitoring.md). |
| Admin and personal dashboards | PureScript application renderer and Webapp APIs | Admin cluster overview is role-gated; personal data is scoped by verified `sub` | Actual cache effects and admin/tenant regressions [9.12](phase-9-access-control-and-monitoring.md). |
| Web runtime executor | PureScript bundle; native Apple or in-image Linux Playwright | Same generated catalog and typed fixture; output artifacts are runner-local unless retained explicitly | Source/bundle binding [5.13](phase-5-web-ui-and-shared-types.md) and media proof [7.33](phase-7-demo-app-durable-context.md). |
| Engine adapter set | `python/adapters/`; hidden native target catalog | Typed one-request/one-response subprocesses; real outputs or failures, no request-time tool installation | Behavioral realness [4.50](phase-4-inference-service-and-durable-runtime.md), history-fed execution [7.31](phase-7-demo-app-durable-context.md). |
| Per-engine Python environment producer | `Infernix.Python`; closed provisioning language | Locked environment preparation with post-install source-bound markers | Lifetime authority [1.46](phase-1-repository-and-control-plane-foundation.md); actual inference is a separate proof. |
| Python quality gate | `poetry run check-code` | mypy, Black, Ruff and limited AST checks | Semantic negative controls [4.50](phase-4-inference-service-and-durable-runtime.md). |
| Keycloak identity | Demo-gated Keycloak release | One application instance; signup, PKCE, JWT role claims and logout | Admin/tenant regressions [9.12](phase-9-access-control-and-monitoring.md). |
| Keycloak Patroni PostgreSQL | Demo-gated Percona-managed database | Single-instance database backing Keycloak; bootstrap-owned rebuild rules follow storage doctrine | Lifecycle/platform evidence [2.18](phase-2-kind-cluster-storage-and-lifecycle.md), [3.18](phase-3-platform-services-and-edge-routing.md). |
| Demo artifact bucket | MinIO `infernix-demo-objects` | Durable demo-gated `users/<sub>/contexts/<ctx>/{uploads,generated}/`; webapp mediator | Preview/media [7.33](phase-7-demo-app-durable-context.md), tenant/admin regression [9.12](phase-9-access-control-and-monitoring.md). |
| Demo conversation topics | Pulsar `demo.conversation.<userId>.<contextId>` | Durable ordered conversation events; cursor alone does not restore dispatcher state | Actual restart, context reconstruction and cancellation [7.30–7.32](phase-7-demo-app-durable-context.md). |
| Demo metadata topics | Pulsar `demo.user.<userId>.{contexts,drafts}` | Compacted per-user metadata; broker-owned durability | Retained context/reconstitution evidence [Phase 7](phase-7-demo-app-durable-context.md). |
| Inference batch topics | Derived pool/model and pinned-member Pulsar topics | `Shared` normal pools, `Exclusive` pinned members; ack follows durable terminal result | Execution/cancellation/replay tests [7.30–7.32](phase-7-demo-app-durable-context.md). |
| Platform model bucket | Always-on MinIO `infernix-models` | Durable model weights/config/tokenizers, eagerly staged by coordinator | Real local hydration and complete artifact accounting [4.50](phase-4-inference-service-and-durable-runtime.md). |
| Engine software bucket | Always-on MinIO `infernix-engine-artifacts` | Immutable reusable engine software, separate from model weights and user outputs | Preserve artifact identity through [4.50](phase-4-inference-service-and-durable-runtime.md) validation. |
| Model-cache staging and fallback | Coordinator; `infernix/system/model.bootstrap.request` and ready topics | Bounded upstream staging with verified readiness; engine cache is derived from MinIO | Artifact readiness [4.50](phase-4-inference-service-and-durable-runtime.md), generated-config consumers [8.15](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md). |

## Runtime and Validation Components

| Component | Entry point | Purpose and evidence boundary |
|---|---|---|
| Cluster reconcile | `infernix cluster up` | Binary-owned lifecycle under initialized config and live ownership; [2.18](phase-2-kind-cluster-storage-and-lifecycle.md) owns new containment proof. |
| Cluster status | `infernix cluster status` | Observes presence, placement, owner and mutation state; not inference-success evidence. |
| Kubernetes wrapper | `infernix kubectl ...` | Allowlisted read-only diagnostics against repo-local kubeconfig. |
| Cache lifecycle | `infernix cache status`, `evict`, `rebuild` | Marker-based behavior is insufficient; [4.50](phase-4-inference-service-and-durable-runtime.md) owns actual engine-cache operations. |
| Focused lint | `infernix lint` with `files`, `docs`, `proto`, `chart`, or `plan` | Mechanical checks only; baked source inventory does not establish checkout freshness. |
| Aggregate static validation | `infernix test lint` | Command-level configured preflight plus static gates; does not prove real inference. |
| Docs validation | `infernix docs check` | Structure, links and generated-contract checks; not proof of prose or attestation truth. |
| Service runtime | `infernix service` | Startup-configured role over real Pulsar; endpoint-absent local spool is a separate unit/isolated harness, not routed evidence. |
| Demo UI runtime | `infernix service --role webapp` | Demo-only routed HTTP/WS/static host. |
| Frontend contract generation | `infernix internal generate-purs-contracts` | Haskell-owned presentation ADTs generate PureScript. |
| Unit validation | `infernix test unit` | Closed configured Haskell/PureScript suites; mandatory CUDA execution cannot be discharged by a skip ([6.55](phase-6-validation-and-e2e-hardening.md)). |
| Integration validation | `infernix test integration` | Active-catalog real behavior, lifecycle and explicit refusals; source-bound and per-check evidence required. |
| Routed E2E validation | `infernix test e2e` | Real Keycloak/Gateway/browser path; useful rendering, not just mounted containers. |
| Single-accelerator phase closure | `infernix test all` on chosen accelerator plus native CPU | Scope-bound retained evidence in [waves](cohort-validation-waves.md); code-side closure is separate. |
| Haskell style and manifest gates | `Infernix.Lint.HaskellStyle`; `test/haskell-style/`; `test/cabal-format/` | In-process Ormolu/HLint plus solver-isolated Cabal-format package; preserve exact generated-source exclusions. |

## Browser and API Surface

| Route | Owner | Contract and remaining proof |
|---|---|---|
| `/` | Webapp through Gateway | Demo landing/app bundle; containment [5.13](phase-5-web-ui-and-shared-types.md). |
| `/api` | Webapp through Gateway | Demo-only API prefix; endpoint-specific authentication/authorization. |
| `/api/publication` | Webapp | Placement/publication metadata, not proof of a live engine. |
| `/api/cache` and `/api/cache/{evict,rebuild}` | Admin-gated Webapp API | Actual owner-scoped cache operations [4.50](phase-4-inference-service-and-durable-runtime.md), strict parsing/admin proof [9.12](phase-9-access-control-and-monitoring.md). |
| `/auth` | Keycloak | Demo-gated login/signup/OIDC. |
| `/ws` | Webapp | Authenticated durable-context sessions; runtime completion remains an independent assertion. |
| `/api/objects` | Webapp | Per-user upload/download/list/delete; bounded preview and full download differ ([7.33](phase-7-demo-app-durable-context.md)). |
| `/registry` | Registry through Gateway | OCI API, not a registry portal; admin authorization when demo is enabled. |
| `/pulsar/admin` | Pulsar through Gateway | Admin API; admin authorization when demo is enabled. |
| `/pulsar/ws` | Pulsar through Gateway | WebSocket transport; browser-edge admin policy does not replace trusted engine data-plane access. |

The route registry and [web portal reference](../documents/reference/web_portal_surface.md)
own exact generated routing. MinIO has no browser-direct Gateway route.
Beyond the admin overview and personal dashboard, no general observability stack is deployed.
Monitoring is not a supported first-class surface.

## Substrate Inventory

| Substrate | Execution placement | Remaining proof |
|---|---|---|
| `apple-silicon` | Native host CLI and separately started host engine; cluster coordinator/platform/Webapp | Manual workflow [1.44](phase-1-repository-and-control-plane-foundation.md), artifact behavior [4.50](phase-4-inference-service-and-durable-runtime.md), browser proof [5.13](phase-5-web-ui-and-shared-types.md). |
| `linux-cpu` | Native amd64/arm64 Linux launcher and cluster engine, no emulation | Source binding and fail-closed observation [1.44–1.45](phase-1-repository-and-control-plane-foundation.md); paired lane for every open wave. |
| `linux-gpu` | Linux launcher/coordinator image plus selected CUDA engine image/workload | Mandatory device execution/cleanup [6.55](phase-6-validation-and-e2e-hardening.md); outer launcher needs no NVIDIA access. |

## Serialization Boundaries

| Boundary | Format and owner | Contract |
|---|---|---|
| Initialization to repo-root config | Dhall; `Infernix.ProjectInit` and decoder-owned defaults | System and machine contracts are distinct; binary sole-generation proof [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Runtime config to ConfigMap | Binary-produced Dhall embedded by Helm | Cluster mount `/opt/build/infernix.dhall`; Apple host reads repo-root config; consumers [8.15](phase-8-zero-tracked-dhall-config-and-eager-model-cache.md). |
| Browser to demo API | JSON; Haskell browser ADTs and generated PureScript | Demo-only presentation surface; private engine/routing authority is not browser configuration. |
| Inference requester to Pulsar | Protobuf; canonical `proto/infernix/` schemas | Text success or artifact reference; typed failure is not successful output. Demo artifacts use the demo-gated user bucket. |
| Coordinator to engine | Protobuf batches over compiled pool/member topics | Same logical routing across Linux pods and Apple host engine placement. |
| Haskell worker to adapter | One protobuf request/response for Python; typed direct-target invocation for native engines | Real engine output, verified artifact ownership, bounded process authority; actual history reconstruction [7.31](phase-7-demo-app-durable-context.md). |
| Browser to demo WebSocket | Typed JSON actions, snapshots and patches | Haskell owns business state; browser applies generated presentation contracts. |

## State and Artifact Locations

| State class | Owner and location | Durability and remaining work |
|---|---|---|
| Retained platform PV data | Binary storage reconciliation; `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` | Durable except explicitly rebuildable bootstrap-owned paths; [storage doctrine](../documents/engineering/storage_and_state.md). |
| Operator runtime and machine config | `infernix init`; `./infernix.dhall`, `./infernix-host.dhall` | Generated, untracked operator configuration; not disposable harness scratch. |
| Per-machine build ceiling | Binary derivation; `cabal.project.local` | Derived from observed capacity; use is re-admitted against live availability ([1.45](phase-1-repository-and-control-plane-foundation.md)). |
| Generated Apple kubeconfig | Cluster lifecycle; `./.build/infernix.kubeconfig` | Derived, persistent across CLI invocations; scratch kubeconfig is separate. |
| Harness config and backup | `infernix test init`; `./infernix.test.dhall`, temporary `./infernix.dhall`, `.harness-backup` | Reservation-gated transaction preserves operator intent; orphan backup refuses rather than assuming recovery authority. |
| Generated Linux kubeconfig | Cluster lifecycle; `./.data/runtime/infernix.kubeconfig` | Derived, reused across launcher invocations. |
| Helm dependency archives | `/opt/infernix/chart/charts/` in image; `chart/charts/` on Apple | Derived dependency cache; image exposes it through `/workspace/chart/charts`. |
| Cluster-mounted runtime config | Binary ConfigMap generation; `/opt/build/infernix.dhall` | Derived mirror, not a second authored contract. |
| Fleet machine contracts | `ConfigMap/infernix-machine-contracts`; pod `/workspace/infernix-host.dhall` | Generated per-member manifests; explicit multi-machine configuration only. |
| Fleet member claim topics | Pulsar `fleet.member-claim.<mode>.<member>` | Broker-owned `Exclusive` membership claims, distinct from per-machine configuration. |
| Outer-container build root | Image `/workspace/.build/outer-container/build/` | Derived build products, not operator config authority. |
| Source snapshot manifest | Image `/opt/infernix/source-snapshot-files.txt` | Baked lint inventory, not independent source freshness evidence; [1.44](phase-1-repository-and-control-plane-foundation.md). |
| Outer-container Cabal home/builddir | Image `/root/.cabal/`, `dist-newstyle/` | Derived during supported explicit bootstrap image build, not `docker compose build`. |
| Publication state | Binary lifecycle; `./.data/runtime/publication.json` | Derived route/placement metadata. |
| ConfigMap publication mirror | Binary lifecycle; `./.data/runtime/configmaps/infernix-demo-config/` | Derived Dhall/YAML inspection mirror. |
| Chosen edge port | Cluster lifecycle; `./.data/runtime/edge-port.json` | Derived selected-port record. |
| Local runtime result records | Runtime; `./.data/runtime/results/*.pb` | Explicit local result persistence, distinct from durable Pulsar conversation authority. |
| Model cache and manifests | Engine-owned Linux `/model-cache/<modelId>/`; Apple `./.data/runtime/model-cache/`; local `manifest.pb` | Derived from MinIO, never made usable by markers alone; [4.50](phase-4-inference-service-and-durable-runtime.md). |
| Conversation/KV projection | Engine/coordinator process state | Derived; hashes do not prove tensors. Reconstruct history and account retained state under [7.30–7.31](phase-7-demo-app-durable-context.md). |
| Generated browser contracts | Binary generator; `web/src/Generated/` | Derived ignored output. |
| Generated browser bundle/assets | Web build; `web/dist/` | Derived ignored output; contained serving [5.13](phase-5-web-ui-and-shared-types.md), actual MIDI samples [7.33](phase-7-demo-app-durable-context.md). |
| Tracked Haskell protobuf snapshot | Four `src/Proto/` modules; `proto/haskell-bindings.sha256` | Exact generated source exception, hash-checked; not handwritten implementation. |
| Shared adapter quality venv | Provisioning; `python/.venv/` | Derived framework-free quality/protobuf environment, not inference fallback. |
| Prepared per-engine venvs | Provisioning; `python/engines/<engine>/.venv/` | Derived or image-owned environment with fixed project-bound marker. |
| Playwright/test outputs | Runner working directories such as `test-results/`, `playwright-report/` | Re-creatable output; retained closure evidence must be explicitly exported and preserved before ephemeral runner removal. |
| Demo artifact prefixes | MinIO `infernix-demo-objects/users/<sub>/contexts/<ctx>/{uploads,generated}/` | Durable demo-gated user objects; browser access only through Webapp. |
| Demo conversation history | Pulsar BookKeeper | Durable ordered events; existing cursor plus empty reducer loses queued state until [7.30](phase-7-demo-app-durable-context.md) is implemented. |
| Demo metadata history | Pulsar BookKeeper | Durable compacted contexts/drafts keyed by context; no browser-local authority. |

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [cohort-validation-waves.md](cohort-validation-waves.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
- [../documents/engineering/storage_and_state.md](../documents/engineering/storage_and_state.md)
