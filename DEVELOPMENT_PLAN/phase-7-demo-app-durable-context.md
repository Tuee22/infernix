# Phase 7: Demo App Multi-User Durable Context

**Status**: Blocked — strict numerical execution waits for Phase 6.
**Blocked by**: Phase 6
**Implementation state behind the blocker**: Active — reopened by the
[Apple/`linux-cpu` evidence reset](cohort-validation-waves.md). Sprint 7.29's closure rests
explicitly on the [Wave V](cohort-validation-waves.md) apple-silicon plus linux-cpu full-suite
`test all` pass, and that attestation predates a large body of subsequently landed work that carries
no Darwin validation. No complete current-source Phase 1 gate or replacement Apple/paired-`linux-cpu`
attestation exists, so the evidence this phase's `Done` depended on is not current proof. No defect
is known in this phase's own surface — the reopen is an evidence reopen, and it re-closes when
[Wave Y](cohort-validation-waves.md) records a result. Sprint 7.28 closed by full linux-gpu plus
linux-cpu cohort validation, and the Sprint 7.29 Managed-State-Transition plus
Bounded-Command/Bounded-HTTP reopen closed under [Wave V](cohort-validation-waves.md) on the
apple-silicon plus linux-cpu full-suite `test all` pass
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the multi-user, durable-context shape of the `infernix-demo` workload —
> Keycloak self-signup, WebSocket post-login transport, Pulsar-backed per-context conversation
> history, MinIO-backed artifact upload/download with audio/image/video rendering, stateless
> backend pods, single-flight per-context inference dispatch, and the validation surface that
> proves all of it under load and pod failure.

## Phase Status

> **Common-shape reopen (Webapp role).** Closed: the demo frontend runs as the
> one-binary `Webapp` role selected by typed Dhall and `infernix service --role webapp`, per the
> shared contract (see [README.md](README.md) → Common-Shape Reopen and
> [development_plan_standards.md](development_plan_standards.md) §Q). The Webapp stays a thin
> websocket server talking only to Pulsar + MinIO (no ML compute). The former two-binary split is
> recorded as closed cleanup in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

> **Audit follow-on reopen (generated artifact ownership).** Phase 7 reopened Sprint 7.28 after an
> audit found that browser object operations are correctly proxied and per-user authorized, but
> generated artifact writers could still bypass the intended
> `users/<sub>/contexts/<ctx>/generated/` layout. Sprint 7.28 closure makes the Haskell
> coordinator/worker path own the generated output target, requires adapters/native runners to upload
> only to that target, makes the result bridge reject raw or cross-user object refs, and is validated
> by the full `linux-gpu` plus `linux-cpu` routed real-output gates.

Sprints 7.1–7.18 are closed, Sprints 7.19–7.22 closed the auth-UX quad described in the Status block
on the [Wave G](cohort-validation-waves.md) routed E2E validation, and Sprint 7.28 closed through the
full selected `linux-gpu` plus `linux-cpu` cohort gate.
Sprint 7.23's Apple `Exclusive` / `Failover` singleton design is retained only as historical plan
context and is superseded by the engine-pool routing target: normal Apple fanout uses `Shared`
across distinct host ids, exact-host routes use `Exclusive`, and the coordinator chooses pool/model
topics rather than concrete nodes.

Browser file storage sits behind the webapp. Sprint 7.25 makes `Demo/Api.hs` proxy the
upload/download bytes through the internal MinIO endpoint and drops the browser-direct presigned-URL
path, realizing the
[../documents/architecture/object_access_doctrine.md](../documents/architecture/object_access_doctrine.md)
and the [../documents/architecture/tenant_isolation_doctrine.md](../documents/architecture/tenant_isolation_doctrine.md);
Sprint 7.26 adds a per-user Files navigational view scoped to `users/<sub>/`; and Sprint 7.27 adds
in-browser MIDI/MusicXML/ZIP rendering. Sprint 7.25 (delivered jointly with
[Phase 3 Sprint 3.13](phase-3-platform-services-and-edge-routing.md), the `/minio/s3`
de-exposure) is code-side closed and cohort-closed by
[Wave M](cohort-validation-waves.md); Sprints 7.26 and 7.27 build on it and are closed
by the same wave. The Sprint 7.9 presigned-URL prose describes the superseded
pre-7.25 path; Sprint 7.27 replaces the prior download-only behavior for MIDI, MusicXML, and ZIP
stem artifacts with in-browser render dispositions.

Code-side closure: Sprints 7.1–7.17 are code-side closed covering the daemon-split topology
(stateless `infernix-demo` frontend, two-replica stateless `infernix-coordinator` with per-context
dispatcher / result-bridge / model-bootstrap loops, and engine-role runtime with KV cache), the
durable-context schema (per-conversation Pulsar log topic, compacted per-user contexts + drafts
topics, `infernix-models` and
`infernix-demo-objects` MinIO buckets, `/api/objects` with a JWKS TTL cache), and the
browser SPA (Keycloak PKCE auth + refresh-token re-auth, durable-context Chat with WebSocket
transport, Artifacts view with bounded text/JSON preview + inline media + browser-native PDF +
download handling, draft sync + cancel + queued-prompt accounting, WebSocket reconnect +
draft restoration). Sprint 7.14 is code-side closed for the WebSocket-to-Pulsar publisher
wiring, the coordinator-to-engine handoff contract, the real Pulsar Reader roundtrip coverage
for conversation/contexts/drafts/bootstrap-ready topic families, producer-dedup validation,
and the non-chaos dispatcher + result-bridge durable prompt roundtrip. Sprint 7.8
wires a process-local `EngineKVCache` through the engine daemon process and moves
daemon role orchestration into `Infernix.Runtime.Daemon`; `Infernix.Runtime.Pulsar`
remains the shared Pulsar transport and runtime-loop module. The Sprint 7.14
Linux-owned chaos/throughput block is validated in [Wave C](cohort-validation-waves.md),
covering frontend/coordinator/engine pod replacement, engine node drain, model-bootstrap
deduplication, Linux engine anti-affinity, and compact multi-user durable prompt throughput.
Runtime bucket repair, deployed wrong-realm Keycloak token rejection for `/api/objects` and `/ws`,
throughput matrix parameterization, and extracted Playwright artifact fixtures closed on the
rebuilt-image `linux-gpu` and `linux-cpu` full gates, each covering style/Python/unit/web-unit,
full integration, and routed Playwright E2E.

Validation closure: tracked by [cohort-validation-waves.md](cohort-validation-waves.md).
Apple cohort closed in [Wave A](cohort-validation-waves.md) (durable-context prompt roundtrip
plus routed e2e), [Wave A.1](cohort-validation-waves.md) (artifact-upload submit-race fix),
[Wave A.2](cohort-validation-waves.md) (per-model browser smoke matrix over every demo-config
catalog model), and
[Wave A.3](cohort-validation-waves.md) (Apple `engine.lock` enforcement chaos case, now legacy
coverage superseded by Sprint 7.24 engine-pool routing). CUDA
Linux cohort closure is recorded in [Wave C](cohort-validation-waves.md): both the native
`linux-cpu` and the real-hardware `linux-gpu` full-suite gates passed, covering the LinuxCpu
integration chaos block and the multi-user throughput suite. A rebuilt-image `linux-cpu` residual
full-suite gate passed after [Wave D](cohort-validation-waves.md).
Historical validation proof points are inventoried in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Historical Validation
Evidence"; the underlying contracts they exercised still describe supported behavior.

Sprint 7.24's pool-routing work is closed under [Wave J](cohort-validation-waves.md). The
coordinator and engine-daemon code-side pool-routing work has landed on the Linux outer-container
lane, and the Apple integration plus aggregate `test all` lanes prove pinned `Exclusive` routes,
same-machine host-member coexistence on a real `Shared` subscription, single-host logical `Shared`
backlog/backpressure, production `demo_ui = false` route/publication assertions, and the full
browser matrix on the current Apple host. The Linux CPU and Linux GPU full-suite gates
prove Kubernetes-observed pool placement, shared-subscription backlog/backpressure,
replacement/drain cases, anti-affinity, lifecycle rebinding, demo-off publication, and the routed
browser matrix on the selected CUDA Linux accelerator plus `linux-cpu`. Physical Apple multi-host
routing is hardware-deferred proof while no second Apple host is available. The earlier
durable-context and auth-UX scopes remain closed on their recorded validation.

Sprints 7.25–7.27 closed in [Wave M](cohort-validation-waves.md). The paired
`linux-cpu` gate passed with the full real-output suite, and the selected `linux-gpu` accelerator
gate passed `./bootstrap/linux-gpu.sh test`: Haskell style, Python `check-code`, Haskell unit, web
contracts, full integration with every `linux-gpu` catalog row producing real output plus
the service/cache/durable-topic and HA lifecycle tail, and routed Playwright including the
browser per-model smoke matrix. The routed browser evidence covers the Wave M-owned
object-proxy, cross-user isolation, Files view, proxied media previews, and in-browser
MIDI/MusicXML/ZIP rendering.

Sprint 7.28 makes `WorkerRequest` carry a Haskell-derived
`users/<sub>/contexts/<ctx>/generated/` output prefix, restricts Python adapter and native runner
uploads to that supplied target, and makes the result bridge parse structured object refs and
fail-close raw or cross-user generated refs. The same cohort run closed the runtime fixes the GPU
gate found: per-engine execution is serialized inside each engine daemon, and deduplicated Pulsar
producer publishes have bounded timeout/retry handling. Closure rests on the selected `linux-gpu`
plus paired `linux-cpu` full gates, each covering Haskell style, Python `check-code`, Haskell unit,
web contracts, full integration with HA/chaos and throughput, routed Playwright, and the browser
per-model matrix.

## Current Repo Assessment

The current `infernix-demo` workload ships a routed PureScript SPA, the catalog and cache
HTTP API surface from Phase 4 Sprint 4.4, and the clustered demo deployment described by
Phase 3. The Helm chart already deploys Pulsar (3-broker HA), MinIO (4-replica HA),
per-service Patroni Postgres clusters (Harbor's `harborpg` and Keycloak's `keycloakpg`), Envoy
Gateway, and the routed edge described by Phase 3. Production inference dispatch already
flows through `inference.request.<mode>` and `inference.result.<mode>` topics per Phase 4.
The prior direct manual-inference HTTP handlers, the matching CLI helper, the
`proto/infernix/api/inference_service.proto` schema, and the single-form manual
inference surface are tracked for explicit removal in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this phase.

Sprint 7.7 owns the prior-cleanup pass behind that shape: the staged `infernix.dhall` schema carries
`models_bucket` and `model_bootstrap_topic` fields (defaults `infernix-models` and
`persistent://infernix/system/model.bootstrap.request`); the prior `/objects/:objectRef` HTTP route
and `serveObject` handler are absent from `src/Infernix/Routes.hs`, `src/Infernix/Demo/Api.hs`, the
route-validation lists in `src/Infernix/Models.hs` and `src/Infernix/Cluster.hs`, the generated
route-registry comment in `chart/templates/httproutes.yaml`, and the route inventory rows in
`README.md`, `documents/engineering/edge_routing.md`, and
`documents/reference/web_portal_surface.md`; `src/Infernix/Runtime.hs` emits unconditional inline
payloads in place of the 80-character inline-payload threshold; `src/Infernix/Runtime/Pulsar.hs`
reconciles the supported `infernix` tenant plus `infernix/system` and `infernix/demo` namespaces,
sets a compaction threshold on the demo namespace, and creates the
`persistent://infernix/system/model.bootstrap.request` topic before schema registration; and
`python/adapters/model_cache.py` exposes the uniform `get_model_path(model_id)` contract with a
`ModelCacheNotPopulated` fail-fast surface backed by the real-cluster MinIO client and LRU eviction
loop. The historical Sprint 7.7 exclusive `./.data/runtime/engine.lock` acquired by
`src/Infernix/Service.hs` at engine-role startup is superseded by the Sprint 7.24 engine-pool
assignment target.

The daemon-role vocabulary is `coordinator` / `engine`, the prior object-store tree and placeholder
buckets are gone, MinIO-backed model and artifact paths are the supported storage contract, the
prior fused service Deployment is removed, and Pulsar producer-side deduplication is wired on the
durable demo topic families.

The supported `./bootstrap/linux-cpu.sh` and `./bootstrap/linux-gpu.sh` lifecycle — `build` plus
`cluster up` → `cluster status` → `cluster down` → final `cluster status` — runs clean on both
Linux substrates. `cluster up` reaches `lifecyclePhase: steady-state` with the split topology
deployed (`infernix-coordinator 2/2`, `infernix-engine 1/1`, `infernix-demo 1/1`,
`infernix-keycloak 1/1`), both Patroni Postgres clusters healthy, MinIO and the full Pulsar
broker/bookie/zookeeper set `Running`, the Pulsar admin reconcile creating the `infernix` tenant
plus the `infernix/demo` and `infernix/system` namespaces, all ten supported HTTPRoutes registered
(`/`, `/api`, `/api/objects`, `/auth`, `/ws`, and the operator route family, with the prior
`/objects` route absent), and no `infernix-{coordinator,engine,demo}` PVCs (the Sprint 7.7 PVC-free
daemon contract). The coordinator runtime loops attach in steady state — the model-bootstrap
session on `persistent://infernix/system/model.bootstrap.request` and the result-bridge session on
the substrate's configured result topic — and `runResultBridgeLoop` consumes the daemon's
already-loaded `daemonConfigResultTopic`, so the bridge listens on the exact topic the engine
publishes to regardless of namespace. `cluster down` returns the lifecycle to
`clusterPresent: False`, `lifecycleStatus: idle`, `lifecyclePhase: cluster-absent` with `./.data`
preserved. The Sprint 7.7 model-bootstrap topic residual is closed; Sprint 7.14 and Wave C
validated model-bootstrap request and ready-event behavior through real Pulsar, including
coordinator-replacement deduplication before first publish. The Sprint 7.1 + 7.3 + 7.7 + 7.8 + 7.9
chart-side surfaces are real-cluster validated on both `linux-cpu` and `linux-gpu`.

The Sprint 7.7 architectural items — the daemon-role rename and the chart cutover from fused to
split topology — are closed and validated end to end on `linux-cpu`. The resulting surfaces:

- `Types.hs.DaemonRole` constructors updated to `Coordinator` / `Engine`;
  `DemoConfig` record fields updated to `coordinatorDaemon` /
  `engineDaemons`; `parseDaemonRole` accepts prior `cluster` / `host`
  strings during transition. Dhall schema field names and the JSON wire
  keys flipped to the new vocabulary. Later Phase 4 cleanup removed legacy raw
  batch-topic projections while current Dhall rendering carries explicit `engineDaemons` metadata
  derived from `enginePools` and `engineMembers`. `infernix service` reports
  `serviceDaemonRole: coordinator` in steady state.
- `chart/templates/deployment-service.yaml` plus
  `chart/templates/persistentvolumeclaim-service-data.yaml` deleted;
  the prior `service.{enabled,image,replicaCount,command,args,dataPvc}`
  keys plus `infernix-runtime` / `infernix-results` MinIO bucket entries
  removed from `chart/values.yaml`. `daemonSplit.enabled = true` plus
  per-role `enabled: true` defaults are now the chart shape. The
  `service:` stanza is reduced to shared backend wiring
  (`service.minio.*`, `service.pulsar.*`, `service.engineAdapters.commandEnv`)
  the new Deployment templates consume.
- `chart/templates/deployment-{coordinator,engine}.yaml` mount the
  substrate ConfigMap and use mounted typed manifests for runtime state.
  Sprint 7.17 removed the remaining infernix-owned `env:` blocks from the
  demo, coordinator, and engine Deployment templates; the demo backend now
  reads MinIO and Keycloak wiring from mounted `ClusterConfig` plus
  `SecretsConfig`.
- `src/Infernix/Models.hs.hostBatchTopicForMode` historically returned the
  canonical `inference.batch.<mode>` topic on every substrate (not just
  Apple), and `Infernix.DemoConfig.engineDaemonConfigs` returned at least
  one engine daemon on every substrate so the in-cluster `infernix-engine`
  Deployment had daemon metadata to start with. Sprint 4.19 and Sprint 7.24 replace this with
  derived pool/model topics and substrate-specific engine members.
- `src/Infernix/Cluster.hs.finalPhaseDeployments` historically waited on
  `deployment/infernix-engine` in every final deployment and added demo-gated
  `deployment/infernix-{coordinator,demo,keycloak}` only when `demo_ui = true`.
  Sprint 7.24 supersedes that production shape: the coordinator is production infrastructure,
  `infernix-demo` and Keycloak remain demo-gated, and Apple engine members are host daemons rather
  than in-cluster engine pods. `clusterServiceEnabled` returns
  `False` across every substrate. `renderHelmValues` zeros out the
  coordinator + engine replica counts in every pre-Pulsar phase and raises
  them in `FinalPhase`. The retired demo-bound coordinator enablement has been removed;
  generated values now keep the coordinator enabled in production.
- `src/Infernix/Cluster/PublishImages.hs.buildHarborOverridesValue`
  rewrites `coordinator.image` + `engine.image` alongside `service.image`
  and `demo.image`, so the new pods pull from the Harbor mirror instead
  of the bare `:local` tag (which is not present on Kind worker nodes).
- `src/Infernix/Runtime/Pulsar.hs.buildConsumerSocketPath` now requests
  `subscriptionType=Shared` so two coordinator replicas can split the
  inference-request topic without 409 Conflict. Per-context exclusive
  ownership lives on the per-conversation Failover subscriptions the
  dispatcher creates (Sprint 7.6).
- `src/Infernix/DemoConfig.hs.ensureGeneratedDemoConfigFile` catches
  decode failures and re-materialises, so a stale staged `.dhall` from
  a pre-rename build doesn't strand `cluster up` on the new schema.

Phase 7 closes the durable-context contract on top of that foundation. It does not modify
production inference dispatch; the new conversation, metadata, and drafts topics live in
demo-gated namespaces, the new Keycloak release, demo MinIO bucket, WebSocket endpoint, and
`/auth` and `/api/objects` routes are absent when `demo_ui = false`, and the supported
manual-inference path closes through the durable-context Chat surface rather than a
parallel HTTP request/poll cycle.

The shared-library foundation Phase 7 needs has implemented at the unit-test level. The
purescript-bridge-emitted wire types (`Infernix.Web.Contracts`), the conversation primitives
(`Infernix.Conversation.{Event,Hash,Idempotency,Reducer,Topic}`), the compacted-topic
projection patterns (`Infernix.Topic.{Metadata,Drafts}`), the pure single-flight
dispatcher (`Infernix.Dispatch.SingleFlight`), the JWKS-backed JWT validator
(`Infernix.Auth.Jwt` + `Infernix.Demo.Auth`), the per-user MinIO layout + AWS SigV4
presigned-URL minting (`Infernix.Objects.{Layout,Presigned}`), the shared-library
result-bridge (`Infernix.Bridge.Result`), and the model-bootstrap-request shape
(`Infernix.Bootstrap.Models`) are implemented, build with `-Wall -Werror`, and pass the
unit-level validation gates documented in their sprints. The Haskell route registry now
declares `/auth`, `/ws`, and `/api/objects` and the generated route sections in
`chart/templates/httproutes.yaml`, `README.md`, `documents/engineering/edge_routing.md`,
and `documents/reference/web_portal_surface.md` reflect those entries. The
`runtime/inference.proto` envelope is extended with `user_id`, `context_id`,
`user_prompt_message_id`, `client_idempotency_key`, `conversation_log_offset`,
`prefix_hash`, and `causal_ref` on the request and `causal_ref` on the result. The
`AppleSilicon`-only handoff conditional in `src/Infernix/Runtime/Pulsar.hs` is
generalised so any substrate forwards when `daemonConfigHostBatchTopic` is set: a Linux
coordinator forwards request-topic payload bytes to `inference.batch.linux-cpu` without executing
inference inline, and the routed publication JSON, `cluster status`, generated demo config, and
service runtime loop all use the Linux batch handoff contract. The
chart carries `daemonSplit.enabled` plus `coordinator` / `engine` / `demoSplit`
stanzas, the engine `emptyDir` model-cache `sizeLimit` knob, the `infernix-models` and
`infernix-demo-objects` MinIO bucket entries, and five templates
(`deployment-coordinator.yaml`, `deployment-engine.yaml`, the three PDBs).

The SPA, dispatcher, reader, model-bootstrap, object-storage, integration, chaos, E2E, and runtime
KV-cache surfaces are implemented and validated by the cohort gates named above.

## Architecture

The product-agnostic design lives at
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the demo-specific bindings live at
[../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md);
the supported three-role daemon model (stateless frontend, stateless coordinator,
substrate-specific engine pools) lives at
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) and
[../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md);
this section names the load-bearing decisions so phase readers can locate the right module
boundary without re-reading the design docs.

- **Identity.** Keycloak release with self-signup on, email verification off, username/password
  only. Browser obtains a JWT and presents it on both HTTP and WS handshakes. Backend validates
  against Keycloak JWKS. `userId = sub`.
- **Transport.** WebSocket for chat, drafts, context list, progress, and artifact-ready
  notifications. HTTP (same JWT) for artifact upload/download through the webapp `/api/objects`
  proxy; binary bytes traverse the demo backend, and the browser never receives a presigned MinIO
  URL.
- **Statelessness.** Backend pods hold zero per-user state across requests. No demo-backend
  Postgres is added; existing per-service Patroni clusters (Harbor and Keycloak's own) are
  unchanged. The browser holds no durable state — full reconstitution from server-
  side state alone on every login.
- **Pulsar topology.** Per-context conversation log topic
  `persistent://infernix/demo/demo.conversation.<userId>.<contextId>` under the supported
  default `infernix/demo` tenant/namespace, single-partition,
  append-only, broker-assigned `MessageId` as the canonical sequence. Compacted per-user
  metadata topics `demo.user.<userId>.contexts` (context list) and `demo.user.<userId>.drafts`
  (drafts keyed by `contextId`). Inference dispatch reuses the existing shared
  `inference.request.<mode>` / `inference.result.<mode>` topics, with envelopes carrying
  `(userId, contextId, causalRef, conversationLogOffset, prefixHash)`.
- **MinIO.** One shared `infernix-demo-objects` bucket. Per-user prefixes:
  `users/<userId>/contexts/<contextId>/{uploads,generated}/`. Presigned URL minting by the
  demo backend with per-user scope checks.
- **Haskell-first logic.** purescript-bridge generates every wire-crossing ADT and JSON
  instance. The Haskell reducer, idempotency dedup, `prefixHash` chain, dispatcher rule, and
  event construction live only in Haskell, in the shared `infernix` library. PureScript code
  is a thin renderer plus input handler; it never reimplements a business rule. The browser
  receives typed `ConversationState` snapshots and `ConversationStatePatch` deltas over WS and
  applies patches via trivial mechanical helpers.
- **Stateless WebSocket coordination.** Demo `Service` has `sessionAffinity: None`. WS pods
  use Pulsar `Reader` subscriptions (cursor-based, no shared subscription state across pods)
  so any pod can host any session. The per-context dispatcher uses named `Failover`
  subscriptions so exactly one pod is active per context at a time. No Redis, no NATS, no
  Keycloak-native session broker — Pulsar is the inter-pod fan-out path.
- **Per-context single-flight inference.** The dispatcher is a pure fold over the conversation
  log: dispatch a `UserPrompt` iff every prior `UserPrompt` has a matching `InferenceResult`.
  Two prompts in a row queue cleanly; cancellation is an event whose outcome is deterministic
  in the log.
- **Engine ↔ SSoT consistency.** Inference request envelopes carry `prefixHash` (Merkle-style
  content hash of the deterministic projection at the dispatch offset). Engine KV-cache key is
  `(contextId, prefixHash)`. Cache cannot diverge: hash match means provably consistent, hash
  miss means rebuild from the log.
- **Failure semantics.** Every retry path is idempotent at the broker level via Pulsar
  broker-level deduplication plus namespace producer-dedup policies on conversation,
  context, draft, inference-request, and inference-result topics, keyed by upstream
  `MessageId`s or application mutation keys. Crashes degrade to redeliveries and cache
  misses, never data loss or duplication.

### Reuse Boundary

Phase 7 introduces four concept-named module groups, mapped onto the three daemon roles in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md),
so the durable-context primitives are reusable by any future SPA-like application built on
the inference platform:

- **Shared library** (`Infernix.Conversation.*`, `Infernix.Topic.*`, `Infernix.Dispatch.*`,
  `Infernix.Objects.*`, `Infernix.Auth.*`, `Infernix.Bridge.*`) — product-agnostic,
  parameterized in topic namespace, bucket name, and JWT issuer/audience.
- **Demo binary / frontend** (`Infernix.Demo.*`) — Keycloak realm wiring, WS upgrade, HTTP
  route handlers, WS envelope tagged-sum types, first-run bootstrap. Loads in the
  `infernix-demo` Deployment.
- **Coordinator daemon** (stateless Pulsar coordination) — loads
  `Infernix.Dispatch.SingleFlight`, `Infernix.Bridge.Result`, and the optional batcher from
  the shared library. Loads in the `infernix-coordinator` Deployment. Must not import
  `Infernix.Demo.*`, `Infernix.Objects.Presigned`, `Infernix.Auth.Jwt`, any WebSocket module,
  or `Infernix.Runtime.*`.
- **Engine daemon** (`Infernix.Runtime`, `Infernix.Runtime.Cache`,
  `Infernix.Runtime.KVCache`, `Infernix.Runtime.Worker`) — imports
  `Infernix.Conversation.Reducer` and `Infernix.Conversation.Hash` for engine-side KV-cache
  consistency only. Loads in the `infernix-engine` Deployment on Linux substrates and as the
  on-host daemon on Apple silicon. Must not import `Infernix.Demo.*`,
  `Infernix.Objects.Presigned`, `Infernix.Auth.Jwt`, `Infernix.Dispatch.SingleFlight`,
  `Infernix.Bridge.Result`, or any WebSocket module.
- **Daemon orchestration** (`Infernix.Runtime.Daemon`) — owns process role startup,
  readiness markers, coordinator-loop startup, and the process-local engine KV-cache handle.
  `Infernix.Runtime.Pulsar` owns the shared Pulsar transport helpers and runtime loops.

The discipline is documented in
[../documents/engineering/implementation_boundaries.md](../documents/engineering/implementation_boundaries.md);
the reusable shape this discipline protects is codified in
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the placement, replica policy, pool ownership, and pinned-member routing rules are codified in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) and
[../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md).

## Sprint 7.1: Keycloak Release and Realm Pre-Seed [Done]

**Status**: Done
**Implementation**: `chart/templates/keycloak/`, `chart/values.yaml`, `src/Infernix/Cluster.hs`
**Docs to update**: `documents/tools/keycloak.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/architecture/demo_app_design.md`

### Objective

Deploy Keycloak in the HA cluster with its own Patroni Postgres backend and a pre-seeded realm
that allows self-signup with username/password and skips email verification.

### Deliverables

- Helm templates under `chart/templates/keycloak/` — `deployment.yaml` (preferred anti-affinity,
  JDBC wiring to the Patroni `pgbouncer` Service, `--import-realm` from the mounted ConfigMap,
  routed `--hostname=<edge>/auth`, TCP readiness/liveness probes, bootstrap admin credentials from
  `infernix-keycloak-admin`), `service.yaml` (ClusterIP on 8080 so the routed `/auth` HTTPRoute
  reaches it without a NodePort), `configmap-realm-import.yaml`, `secret-admin.yaml` (bootstrap
  admin credentials the operator rotates through the Keycloak admin UI after first login), and
  `poddisruptionbudget.yaml` (`maxUnavailable: 1`), all gated on
  `.Values.demo.enabled && .Values.keycloak.enabled`
- `chart/Chart.yaml` declares a second `pg-db` dependency aliased to `keycloakpg`, gated on
  `upstreamCharts.keycloakpg.enabled`; `chart/values.yaml` carries the matching `keycloakpg:`
  Patroni stanza (3-instance HA, `infernix-manual` storage class, pgbackrest backups) and the
  `keycloak:` stanza with image from Harbor, demo-gating tied to `demo_ui`, realm and client
  identifiers, routed external base URL, and admin/database secret names. The backing Patroni
  cluster is HA; the Keycloak application itself runs one local-demo replica. Multi-replica
  Keycloak serving is deliberately not enabled — it requires proxy affinity or a clustered cache,
  neither of which the supported local-demo shape carries
- realm definition with `registrationAllowed: true`, `verifyEmail: false`, an `infernix-spa`
  public OIDC client with PKCE, edge-aware redirect URI / web-origin defaults, and a length-only
  password policy, plus an in-binary `reconcile-keycloak-realm` lifecycle phase that patches the
  realm flags, SPA redirect URIs, web origins, and PKCE setting through the Keycloak admin API
  after final rollout so repeat `cluster up` runs do not drift
- `src/Infernix/Cluster.hs.reconcileFinalPhaseOperatorManagedPersistentVolumes` runs after the
  no-hooks FinalPhase chart apply creates the `keycloak-postgresql` PerconaPGCluster CR, waits for
  the combined Harbor plus Keycloak operator-managed PVCs, creates matching PVs, and binds them;
  the warmup-only reconcile cannot see Keycloak's claims because that CR is FinalPhase-gated
- `src/Infernix/Cluster/PublishImages.hs.pushUpstreamMultiArchViaImagetools` falls back to
  `skopeo copy --override-os=linux --override-arch=amd64` for upstream multi-arch images, derives
  content-addressed Harbor tags from the upstream linux/amd64 manifest when the containerd image
  store leaves the pulled tag non-inspectable, and routes non-taggable upstream tags straight
  through the fallback copy
- `/auth` route added to the Haskell route registry source so the auto-rendered registry
  emits it into README, `documents/reference/web_portal_surface.md`, and publication JSON
- `cluster up` reconciles Keycloak after Harbor is responsive, before the demo workload starts
  on the durable-context surface. With `demo_ui = false`, `upstreamCharts.keycloakpg.enabled`,
  `keycloak.enabled`, the `prepare-keycloak-storage` PV reconcile, and the realm reconcile all
  follow the substrate's demo flag
- `web/playwright/inference.spec.js` carries the routed Keycloak browser smoke: an OIDC
  authorization-code plus PKCE flow at `/auth`, the registration link, a fresh username/password
  account without email verification, and the return to `/` with an authorization code and the
  original state

### Validation

- `cluster up` with `demo_ui = true` deploys Keycloak and reports readiness
- a browser at `/auth` reaches the Keycloak login page
- signup with a fresh username and password succeeds without an email-verification step
- `infernix kubectl -n platform get postgrescluster` shows the Keycloak Patroni cluster
- when the demo UI is disabled, the Keycloak release and its Patroni cluster are absent

### Remaining Work

None. Closed by the Apple routed E2E gates and [Wave C](cohort-validation-waves.md).

---

## Sprint 7.2: Browser-Contract ADTs and WS Envelope [Done]

**Status**: Done
**Implementation**: `src/Infernix/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`, `web/test/Infernix/Web/ContractsSpec.purs`, `src/Infernix/CLI.hs` (import normalization)
**Docs to update**: `documents/development/frontend_contracts.md`, `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`

### Objective

Extend the Haskell-owned browser contract with every new ADT the durable-context surface
introduces, and regenerate the PureScript contract module via purescript-bridge so the browser
imports type-safe wire bindings.

### Deliverables

- new types in `src/Infernix/Web/Contracts.hs`:
  - `ConversationEvent`, `ContextMetadataEvent`, `DraftEvent`
  - `ConversationState`, `ConversationStatePatch`
  - `ContextListState`, `ContextListPatch`
  - `DraftMapState`, `DraftMapPatch`
  - `WsClientMessage`, `WsServerMessage` (tagged sums; server messages carry snapshots and
    patches, not raw events)
  - `ArtifactUploadRequest`, `ArtifactUploadGrant`, `ArtifactDownloadGrant`
  - `ObjectRef`, `ArtifactKind`, `ArtifactMimeType`, `ArtifactRenderDisposition`
  - newtypes for `UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`
- regenerated `web/src/Generated/Contracts.purs` consumed by handwritten PureScript modules
- the generator footer in `src/Infernix/Web/Contracts.hs` (`renderPhase7PursInstances`,
  `renderPursRecordKind`, `renderPursSum`, `renderShowInstanceIfAllNullary`) emits hand-rolled
  Simple.JSON `WriteForeign` / `ReadForeign` instances for every Phase 7 type plus `Show`
  instances for every nullary sum, and the import normalization in `src/Infernix/CLI.hs` adds
  `Foreign (ForeignError(..), fail) as Foreign` to the generated module
- the wire encoding matches Aeson's `TaggedObject "tag" "contents"` exactly: string-wrapping
  newtypes (`UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`, `ArtifactMimeType`)
  encode as bare strings, record-wrapping newtypes unwrap their inner record, nullary sums emit
  `{"tag": "ConstructorName"}`, positional sums emit `{"tag": ..., "contents": ...}`, and
  record-syntax sums spread the constructor's fields beside the `tag` key

### Validation

- `infernix internal generate-purs-contracts` produces deterministic output
- `infernix test unit` exercises encode/decode roundtrip across the new types in both the
  Haskell and PureScript suites
- repeated codegen runs produce byte-identical output

### Remaining Work

None.

---

## Sprint 7.3: WS Endpoint, JWT Validation, and Stateless Coordination [Done]

**Status**: Done (code-side closed for routed JWT, malformed-frame, expired-token, and per-context Reader browser coverage; Apple cohort gate closed in [Wave A](cohort-validation-waves.md); LinuxCpu frontend pod replacement coverage implemented in Sprint 7.14 on the recorded cohort validation and passed the native `linux-cpu` full-suite gate the same day; `linux-gpu` full-suite validation passed on the recorded cohort validation in [Wave C](cohort-validation-waves.md); browser-level pod-failover closed on the recorded cohort validation with the mounted-source `linux-gpu` routed E2E pass.)
**Implementation**: `src/Infernix/Demo/WebSocket.hs`, `src/Infernix/Demo/Auth.hs`, `src/Infernix/Auth/Jwt.hs`, `chart/templates/demo/service.yaml` (or equivalent), `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/reference/web_portal_surface.md`, `documents/tools/keycloak.md`

### Objective

Land the `/ws` endpoint with Keycloak JWT validation on handshake. Establish stateless
coordination using Pulsar `Reader` subscriptions on the WS path so any replica can host any
session.

### Deliverables

- `Infernix.Auth.Jwt` shared module with JWKS-backed validation parameterized in issuer and
  audience
- `Infernix.Demo.Auth` wires the Keycloak realm to `Infernix.Auth.Jwt`
- `Infernix.Demo.WebSocket` handles WS upgrade, JWT validation, framed envelope routing.
  `wsApplication` mounts on `/ws`, upgrades WAI requests through
  `Network.Wai.Handler.WebSockets.websocketsOr`, and validates the bearer JWT carried in either
  the `Authorization` header or the `?token=` query parameter — the query fallback exists because
  browsers cannot set headers on `WebSocket(...)` connects. The handshake calls
  `Infernix.Auth.Jwt.verifyAndParseJwt` and captures `UserId` from the `sub` claim
- decoded client frames are classified through the pure `classifyClientMessage` helper;
  state-changing frames route through `wsDispatchClientMessage` into
  `Infernix.Runtime.Pulsar.publishDemoClientMessage`, so prompt, cancel, draft, and context
  metadata frames publish typed JSON events to their durable Pulsar topic families. A malformed
  frame is answered with a tagged `ServerError` carrying
  `serverErrorErrorCode = "ws_frame_decode_failed"`
- the session starts per-user context-list/draft Reader streams after `ClientHello` and
  per-context conversation Reader streams after `ClientSubscribeContext`; outbound frames are
  serialized behind a per-session send lock
- chart Service for `infernix-demo` sets `sessionAffinity: None`; no client-IP or cookie
  affinity on the HTTPRoute either
- `/ws` route added to the Haskell route registry source
- per-WS state holds only the WS handle, the authenticated `UserId`, and Pulsar Reader
  cursors/projections; no per-user identity cache
- the mounted `ClusterConfig.keycloak` wiring the handshake reads is the routed issuer base at
  `/auth`, the public SPA client id `infernix-spa`, and the in-cluster Keycloak service URL on
  port `8080` with the `/auth/realms/.../certs` JWKS path

### Validation

- WS connection with a valid JWT succeeds; invalid/expired JWT closes the WS with a typed
  error
- `infernix kubectl -n platform get service/infernix-demo -o yaml | grep sessionAffinity`
  reports `None`
- a chaos test (Sprint 7.14) kills the WS-hosting pod and asserts the client reconnects to a
  different replica with no state loss

### Remaining Work

None. Closed by [Wave A](cohort-validation-waves.md) and [Wave C](cohort-validation-waves.md).

---

## Sprint 7.4: Conversation Primitives in Shared Library [Done]

**Status**: Done
**Implementation**: `src/Infernix/Conversation/Event.hs`, `src/Infernix/Conversation/Reducer.hs`, `src/Infernix/Conversation/Idempotency.hs`, `src/Infernix/Conversation/Hash.hs`, `src/Infernix/Conversation/Topic.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Land the product-agnostic conversation primitives in the shared library so both the demo
binary and the cluster daemon can use them. The Reducer module produces both
`ConversationState` snapshots and `ConversationStatePatch` deltas so demo backends can stream
patches to browsers without browsers ever folding raw events.

### Deliverables

- `Infernix.Conversation.Event` — `ConversationEvent` ADT, JSON and protobuf instances
- `Infernix.Conversation.Reducer` — deterministic fold; emits patches alongside state
- `Infernix.Conversation.Idempotency` — `(contextId, clientIdempotencyKey)` dedup rule
- `Infernix.Conversation.Hash` — Merkle-style `prefixHash` chain
- `Infernix.Conversation.Topic` — per-context Pulsar topic naming, schema registration,
  producer and compacted-reader helpers; parameterized in `TopicNamespace`
- Pulsar producer dedup enabled on conversation topics (`enableProducerDeduplication = true`),
  named producers, dedup sequence IDs derived from upstream `MessageId`s
- conversation events ride the Pulsar WebSocket transport as JSON payloads base64-encoded into
  the producer envelope. The supported wire format is the Aeson instances in
  `Infernix.Web.Contracts`; a parallel protobuf schema for `ConversationEvent` is deliberately
  not part of the supported contract
- broker-side dedup is enabled both at the Pulsar broker config layer
  (`brokerDeduplicationEnabled = true` in `chart/values.yaml`) and at namespace scope, where
  `reconcileSupportedNamespaces` POSTs `true` to `/admin/v2/namespaces/<ns>/deduplication` for
  `infernix/demo` and `infernix/system`. The WebSocket publisher uses mutation-scoped
  one-message producer names plus `initialSequenceId` baselines derived from client idempotency,
  prompt, draft, or context keys; the dispatcher uses stable per-context producer scoping with
  monotonic broker `MessageId`-derived sequence ids
- the Haskell style gate rejects demo, runtime, auth, object-presign, and WebSocket imports from
  the conversation primitive modules

### Validation

- Haskell property tests cover reducer determinism, idempotency dedup, hash chain
  monotonicity, and patch-stream equivalence to state-snapshot equality
- integration test (Sprint 7.14) round-trips a conversation through a real Pulsar topic with
  producer dedup verified via simulated double-publish
- no module under `Infernix.Demo.*` is imported by these shared modules

### Remaining Work

None.

---

## Sprint 7.5: Compacted Metadata Patterns in Shared Library [Done]

**Status**: Done
**Implementation**: `src/Infernix/Topic/Metadata.hs`, `src/Infernix/Topic/Drafts.hs`, `src/Infernix/Runtime/Pulsar.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`

### Objective

Land the compacted-topic projection patterns used by the contexts metadata topic and the
drafts topic, plus the namespace-level compaction policy required by the broker.

### Deliverables

- `Infernix.Topic.Metadata` — generic compacted-topic projection pattern with keyed-event fold
  helpers
- `Infernix.Topic.Drafts` — generic compacted-keyed-mutable-state pattern with
  upsert-by-key and clear-by-key fold helpers
- namespace-level compaction policy reconciled on `cluster up` for the `infernix/demo`
  namespace that owns `demo.user.*` metadata topics

### Validation

- unit tests publish N events to the shared compacted projection fold with M distinct keys and
  assert the projection yields exactly M latest values
- the Linux GPU integration suite publishes multiple context and draft records per key, reads the
  `infernix/demo` namespace compaction threshold from Pulsar admin, explicitly compacts the live
  contexts and drafts topics, and uses a Java Pulsar client with `readCompacted(true)` to assert
  exactly one latest record per `contextId`
- validation commands passed on the recorded cohort validation:
  `cabal build exe:infernix test:infernix-unit test:infernix-integration`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `cabal test infernix-integration` inside the Linux GPU outer container

### Remaining Work

None.

---

## Sprint 7.6: Single-Flight Dispatcher in Shared Library [Done]

**Status**: Done
**Implementation**: `src/Infernix/Dispatch/SingleFlight.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`

### Objective

Land the per-context single-flight inference dispatcher as a pure fold over the conversation
log. Subscribe to each active conversation topic with a Pulsar named `Failover` subscription
so exactly one pod is the active dispatcher per context at a time.

### Deliverables

- `Infernix.Dispatch.SingleFlight` — pure dispatch rule, cancellation handling, inference
  request envelope construction including `prefixHash`, `conversationLogOffset`, `causalRef`,
  `userId`, `contextId`
- Pulsar producer dedup enabled on `inference.request.<mode>` keyed by `userPromptMessageId`
- failover-subscription wiring per conversation topic. `Runtime/Pulsar.hs.runDispatcherLoop`
  polls the supported demo namespace through Pulsar admin
  `GET /admin/v2/persistent/<tenant>/<namespace>`, extracts `(UserId, ContextId)` pairs from any
  topic matching the `demo.conversation.<userId>.<contextId>` shape, and forks one per-context
  worker keyed by `ContextId` (tracked in a process-local set so repeated discovery cycles do not
  start duplicates). The worker subscribes Failover with subscription name
  `dispatcher-<contextId>` and `subscriptionInitialPosition=Earliest` so a recovered replica
  replays from the start of the log, folds each decoded `ConversationEvent` through
  `Conversation.Reducer.stepReducer`, and on `DispatchPrompt` publishes the `InferenceRequest`
  envelope with producer name `dispatcher-<contextId>` and a sequence id derived from the prompt
  `MessageId`, so the broker dedup gate collapses retries from a recovered replica
- the dispatcher acks each message immediately after stepping the reducer, so a recovered replica
  resumes at the cursor with empty in-memory state. Producer dedup prevents duplicate dispatches;
  the single-flight queue guard ("hold prompt 2 until prompt 1 resolves") covers only the case
  where the recovered replica observes both prompts in the same session, and crash-tolerant state
  recovery rests on the coordinator-replacement validation rather than on in-memory continuity
- the daemon log reports `serviceDispatcherMode: per-context-failover` when the daemon role is
  `Coordinator`
- the dispatcher is instantiated in the `infernix-coordinator` Deployment, not in the engine
  pod or any app pod, per the daemon role assignment in
  [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md);
  shared-library modules in this sprint must not import `Infernix.Runtime.*`,
  `Infernix.Demo.*`, `Infernix.Objects.Presigned`, `Infernix.Auth.Jwt`, or any WebSocket
  module

### Validation

- unit property test exercises the pure-fold rule across arbitrary log prefixes including
  cancels, two-in-a-row prompts, and out-of-order results
- integration chaos test (Sprint 7.14) kills the active dispatcher mid-prompt; asserts
  Failover promotes a surviving pod and producer dedup prevents a duplicate dispatch
- two prompts in a row in the same context produce exactly two inference requests in the
  correct order

### Remaining Work

None.

---

## Sprint 7.7: Truly Stateless Daemon Topology and HA Chart [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime/Pulsar.hs` (batch forwarding + bootstrap subscription wiring), `src/Infernix/Models.hs` (`inference.batch.<mode>` for every substrate; `infernix/system/model.bootstrap.request` topic family), `src/Infernix/DemoConfig.hs` (split `cluster` role into `coordinator` + `engine`; add `modelsBucket` and `modelBootstrapTopic` fields), `src/Infernix/Runtime/Cache.hs` (prior `objectStoreRoot`, `localPathFromUri`, `cacheManifestProtoPath`, `durableArtifactPathFor`, `sourceManifestPathFor`, and the `s3://infernix-runtime/` URI scheme; replaced by a MinIO-backed model loader and an `emptyDir`-backed LRU eviction manager), `src/Infernix/Runtime.hs` (prior the 80-char `buildPayload` branch; text outputs always inline, binary outputs carry a MinIO `ObjectRef`), `src/Infernix/Demo/Api.hs` (prior `serveObject` and the `/objects/:objectRef` route), `src/Infernix/Routes.hs` (prior the `/objects` route entry), `src/Infernix/Service.hs` (retained `engine.lock` safety check for non-Apple engine roles; Apple uniqueness is superseded by stable host-id pool membership and pinned `Exclusive` routing), `src/Infernix/Cluster.hs` (Helm rollout for the new Deployments + buckets + `infernix/system` namespace + `model.bootstrap.request` topic), `src/Infernix/Bootstrap/Models.hs` (coordinator's bootstrap Failover subscription, download-from-upstream + upload-to-MinIO with `.ready` sentinel), `src/Infernix/Bridge/Result.hs` (shared-library result-bridge, replaces the previously planned `Infernix.Demo.ResultBridge`), `python/adapters/model_cache.py` (shared adapter helper exposing `get_model_path(model_id) -> path`, MinIO client + LRU eviction rooted at `/model-cache`, uniform across every engine), `python/adapters/common.py`, `python/adapters/diffusers_python.py`, `python/adapters/pytorch_python.py`, `python/adapters/transformers_python.py`, `python/adapters/vllm_python.py` (adapter integration with typed cache/config helpers), `chart/templates/deployment-coordinator.yaml` (no PVC), `chart/templates/deployment-engine.yaml` (no PVC; single `emptyDir` volume `model-cache` with `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}`, default `64Gi`, and explicit CPU/memory resources), `chart/templates/poddisruptionbudget-coordinator.yaml`, `chart/templates/poddisruptionbudget-engine.yaml`, `chart/templates/poddisruptionbudget-demo.yaml`, `chart/values.yaml` (`infernix-models` and `infernix-engine-artifacts` always-on; `infernix-demo-objects` demo-gated; `coordinator`/`engine`/`demo` HA stanzas; `engine.modelCache.sizeLimit` and `engine.resources` knobs), `src/Infernix/Substrate.hs` (substrate decoder type — reflected schema, no tracked `.dhall`: coordinator + engine role schemas; `modelsBucket : Text`; `modelBootstrapTopic : Text`; per-model `downloadUrl : Text`), `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` (prior fused Deployment, service-data PVC, object-store URI, and placeholder-bucket cleanup ledger)
**Docs to update**: `documents/architecture/daemon_topology.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/durable_context_design.md`, `documents/engineering/object_storage.md`, `documents/engineering/portability.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/k8s_storage.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/chaos_testing.md`, `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `README.md`

### Objective

Land the supported three-role daemon topology — stateless frontend, stateless coordinator,
stateful engine — with **no PVC on any daemon**, **MinIO + Pulsar as the only durable state**,
and a **uniform one-engine-per-node policy on every substrate**. Retire the fused
`infernix-service` Deployment with role-specific `infernix-coordinator` and `infernix-engine`
Deployments; retire `./.data/object-store/`, the `s3://infernix-runtime/` URI scheme, the
80-char inline-payload threshold, the `/objects/:objectRef` route, and the chart-reserved
`infernix-runtime` + `infernix-results` placeholder buckets. Model weights are pulled from
the new `infernix-models` MinIO bucket on first use via a coordinator-owned exactly-once
bootstrap workflow; engine pods stage weights into a bounded `emptyDir` cache. See
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
and [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md)
for the authoritative target shape.

### Deliverables

- **No PVC on any daemon.** The coordinator and demo Deployments are PVC-free; the engine
  Deployment mounts a single `emptyDir` volume `model-cache` with
  `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}` (default `64Gi`) at `/model-cache`,
  enforced by kubelet so the pod cannot exhaust node disk
- **Strict engine placement.** On Linux substrates this is enforced by
  `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity on the engine Deployment's own
  label with `topologyKey: kubernetes.io/hostname`; the retained `engine.lock` is only a
  non-Apple engine-role safety check. Apple silicon uses stable host ids in the engine-pool graph:
  normal Apple pools use `Shared` subscriptions across host members, and exact-host routes use
  derived pinned topics with `Exclusive` broker ownership.
- **Batch handoff topic family.** `src/Infernix/Runtime/Pulsar.hs:drainTopic` forwards to
  `daemonConfigHostBatchTopic` whenever that field is set, irrespective of `runtimeMode`, and
  `inference.batch.<mode>` topic definitions exist for `linux-cpu` and `linux-gpu`
- **Introduce the `infernix/system` Pulsar namespace** carrying the
  `model.bootstrap.request` topic; request message key `modelId` plus
  attempt-scoped producer dedup keyed by `modelId@requestedAt`
- **Lazy model-weight population to MinIO with exactly-once semantics.** Engine sees an
  uncached model → publishes a bootstrap request; the coordinator's third Failover
  subscription (alongside dispatcher and result-bridge) downloads from the upstream URL
  carried in the active substrate `.dhall`, PUTs each file under
  `infernix-models/<modelId>/<filename>`, PUTs the `.ready` sentinel last, then publishes
  `model.bootstrap.ready.<modelId>`. Engines wait on the ready event with a 900-second bounded
  cold-bootstrap timeout and load from MinIO
- **Three MinIO buckets, drop the placeholders.** `infernix-models` is always-on and holds
  platform model weights, tokenizers, and configs under `<modelId>/<filename>` with a
  `.ready` sentinel; `infernix-engine-artifacts` is always-on and holds optional immutable
  engine payloads; `infernix-demo-objects` is demo-gated and holds user uploads plus
  engine-generated artifacts under `users/<userId>/contexts/<contextId>/{uploads,generated}/`.
  The chart-reserved `infernix-runtime` and `infernix-results` placeholders are removed
- **Uniform model-cache adapter helper.** `python/adapters/model_cache.py` defines
  `get_model_path(model_id) -> filesystem path`, the boto3 MinIO download client, and the
  LRU eviction logic. The contract is that every adapter routes through this helper,
  regardless of whether the underlying engine library supports bytes-loading; the first
  call populates `/model-cache/<modelId>/` from `infernix-models`, subsequent calls reuse
  the local copy, and eviction runs when the directory tree approaches `sizeLimit`.
  **Status:** `model_cache.py` contains the boto3 MinIO download client + LRU
  logic and the `get_model_path(model_id) -> path` contract. Wiring the adapter layer
  (transformers/diffusers/jax/pytorch/tensorflow/vllm) to call `get_model_path` and invoke the
  real engine — replacing the `common.render_engine_output` harness stub tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — is owned by
  [phase-4-inference-service-and-durable-runtime.md](phase-4-inference-service-and-durable-runtime.md)
  Sprints 4.7 and 4.15. The size-limited `/model-cache` `emptyDir` is
  mounted by `chart/templates/deployment-engine.yaml` but the daemon does not yet write
  there: the active cache uses the unbounded `engine-data` `emptyDir`
  (`Paths.modelCacheRoot = runtimeRoot/model-cache`), so the cache is not under a
  kubelet-enforced quota today (`ClusterConfig.engineModelCacheRoot` has no runtime
  consumer). Wiring every adapter through `get_model_path` / the size-limited mount is
  tracked remaining work
- **Result-payload topology simplified.** Delete the 80-char threshold branch in
  `Runtime.hs:75-91`; text outputs always ride inline in the protobuf result message; binary
  outputs are written by the adapter directly to `infernix-demo-objects` at the
  appropriate per-user prefix and the result message carries an `ObjectRef` (bucket + key),
  not host-filesystem path nor inline bytes
- **Delete prior surfaces:** `./.data/object-store/` tree, `objectStoreRoot` plumbing in
  `Runtime/Cache.hs`, the `s3://infernix-runtime/` URI scheme + `localPathFromUri` mapping,
  the `/objects/:objectRef` HTTP route handler in `Demo/Api.hs`, and the route registry
  entry in `Routes.hs`. `Runtime/Cache.hs` operates on
  `modelCacheRoot/<runtimeMode>/<modelId>/` with manifests at `manifest.pb` beside the cached
  weight files, and `Demo/Api.hs.sourceArtifactManifestUri` plus
  `Storage.hs.cacheManifestToProto` name `minio://infernix-models/…` and
  `minio://infernix-demo-objects/…` prefixes
- **Worker envelope carries model metadata, not paths.** The `WorkerRequest` proto envelope drops
  `artifact_bundle_path` / `source_manifest_path` / `cache_manifest_path` and carries
  `display_name` / `family` / `artifact_type` / `runtime_lane` read straight from the daemon's
  already-loaded substrate catalog; `python/adapters/common.py.load_adapter_context` reads them
  off the wire instead of synthesising JSON files
- **Producer-dedup plumbing.** `publishTopicPayload` takes
  `PublishOptions { publishProducerName, publishSequenceId }`, `buildProducerSocketPath` appends
  a stable `producerName` plus optional `initialSequenceId` to the WebSocket producer URL, and
  the daemon's request consumer derives a per-message sequence id from the envelope's
  `userPromptMessageId` via `inferenceRequestSequenceId`, which packs a Pulsar
  `<ledgerId>:<entryId>:...` MessageId into a 64-bit value
- **Move the planned `Infernix.Demo.ResultBridge` to `src/Infernix/Bridge/Result.hs`**
  (shared library; loaded by coordinator). The demo binary carries no result-bridge module
- **Three Deployments + PDBs**: `infernix-coordinator` (replicas ≥ 2 default, preferred
  anti-affinity, production infrastructure), `infernix-engine` (Linux engine-pool workload with
  operator-set replicas and GPU resource shape on `linux-gpu`; Apple engine members run on host),
  `infernix-demo` (replicas ≥ 2 default; preferred anti-affinity; demo-gated). PodDisruptionBudgets
  `maxUnavailable: 1` on Kubernetes workloads. Earlier Sprint 7.7 wording that demo-gated the
  coordinator is superseded by Sprint 7.24.
- **Production (`demo_ui = false`) keeps coordinator plus engine pools.** Frontend/demo API,
  identity, and demo-owned routes or buckets are demo-gated; production bootstrap semantics for lazy
  model population live in the coordinator.
- **Readiness probes** match the role: coordinator probes Pulsar subscription readiness;
  engine probes adapter startup; demo probes HTTP listener
- **Coordinator pod owns the only outbound-internet egress** in the supported daemon
  topology — used solely for upstream weight downloads on first use of a model.
  NetworkPolicy may scope egress to the catalog's listed download hosts; documented in
  governed docs

### Validation

- `infernix kubectl get pvc -A` returns empty (no daemon has a PVC) on `linux-cpu`,
  `linux-gpu`, and the cluster side of `apple-silicon`
- Integration test on `linux-cpu`: first inference request for an uncached model triggers
  a bootstrap, coordinator downloads from upstream and uploads to `infernix-models`,
  engine populates `/model-cache/<modelId>/`, inference completes; second request for the
  same model bypasses bootstrap; third request from a different engine node also bypasses
  bootstrap and pulls weights from `infernix-models` (not from upstream)
- Integration test on `linux-gpu`: round trip on a node with multiple NVIDIA devices;
  assert exactly one engine pod scheduled per node even when
  `engine.replicaCount > #engine-capable-nodes` (excess replicas stay `Pending`)
- Concurrency test: N engine pods request the same uncached model simultaneously; producer
  dedup + Pulsar Failover guarantees exactly one upstream download; all N engines observe
  the `.ready` sentinel and proceed
- Eviction test: trigger model loads until `/model-cache` size pressure exists; assert the
  adapter helper evicts LRU entries and continues to serve requests; the engine pod is
  never restarted by kubelet for ephemeral-storage exhaustion
- Pod-restart test: kill an engine pod after it has cached several models; new engine pod
  starts with empty `/model-cache`; the next request repopulates from `infernix-models`
  (not from upstream); inference completes
- Chaos: kill the active coordinator pod mid-bootstrap; surviving coordinator replica
  resumes; the `.ready` sentinel appears exactly once via producer dedup; no duplicate
  upstream download
- Chaos: kill an engine pod mid-inference; Pulsar redelivers the unacked batch; a surviving
  engine on another node rebuilds the KV cache from the conversation log via `prefixHash`;
  producer dedup on `inference.result.<mode>` prevents a duplicate result
- Chaos: drain a node hosting an engine pod; the engine PDB blocks the drain until another
  engine pod is available cluster-wide; the cluster keeps serving inference
- Engine placement enforcement: on Linux,
  `kubectl scale deployment/infernix-engine --replicas=N+1` (where N = engine-capable
  nodes) leaves one replica `Pending` with the anti-affinity rejection message. The older Apple
  `engine.lock` duplicate-daemon diagnostic is historical and is superseded by stable host-id pool
  membership plus pinned `Exclusive` routing in Sprint 7.24
- Production-shape test: deploy with `demo_ui = false`;
  `infernix kubectl -n platform get deployments` returns coordinator plus engine-pool workloads;
  `infernix-models` and `infernix-engine-artifacts` buckets are present;
  `infernix-demo-objects` bucket is absent;
  `/objects/:objectRef` route is not registered
- Per-engine smoke matrix: for every non-`Not recommended` row in the README matrix,
  confirm each adapter produces a valid deterministic harness result (text or binary
  `ObjectRef`) on the appropriate substrate. This does not assert weights load from
  `infernix-models` today; the `get_model_path` weight-loading path is pending adapter
  wiring
- `infernix lint chart`, `infernix lint docs`, `infernix lint files`,
  `infernix docs check` all exit zero

### Remaining Work

None.

---

## Sprint 7.8: Engine Prefix-Hash Cache Consistency and Result Writeback [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime/*`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/Runtime/KVCache.hs`, `src/Infernix/Runtime/Pulsar/Failover.hs`, `tools/generated_proto/` (or upstream `.proto`), `src/Infernix/Bridge/Result.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Make the engine's KV cache consistency with the Pulsar SSoT provable and crash-tolerant. Land
the result-to-conversation bridge that writes `InferenceResult` events back to the per-context
conversation topic, instantiated in the `infernix-coordinator` Deployment per the daemon role
assignment in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md).

### Deliverables

- inference request envelope (proto + Haskell records) extended with `prefixHash`,
  `conversationLogOffset`, `causalRef`, `userId`, `contextId`
- inference result envelope extended with `causalRef` and a `Cancelled` status variant. The
  `InferenceResult` proto carries `user_id` and `context_id` alongside `causal_ref`, and the
  `Infernix.Types.InferenceResult` domain record carries the matching
  `resultUserId` / `resultContextId` / `resultCausalRef` fields with Aeson `omitempty` defaults
  so prior callers round-trip unchanged. `publishedResultFromRequest` propagates
  `user_id` / `context_id` / `user_prompt_message_id` from the request so the bridge has the
  routing fields it needs, and results missing those fields (the Phase 4 manual-inference path)
  are skipped cleanly without ack failure rather than breaking that path
- engine adapter / runtime reuses `Infernix.Conversation.Reducer` and
  `Infernix.Conversation.Hash` to verify `prefixHash` before reusing any KV cache; rebuild on
  miss. `src/Infernix/Runtime/KVCache.hs` owns `EngineKVCache`, `KVCacheRequest`,
  `KVCacheObservation`, `observeKVCachePrefix`, `verifyKVCachePrefix`, and
  `rebuildPrefixHashFromLog`; `executeInferenceWithKVCache` threads observations through the
  worker path, and native worker output surfaces `kv-cache=reuse|rebuild` plus `kv-prefix-hash`
  when the durable-context envelope carries cache metadata
- `src/Infernix/Runtime/Daemon.hs` owns production daemon role orchestration: it allocates one
  process-local engine KV cache per daemon process, threads it into filesystem and WebSocket
  Pulsar engine request consumption, and starts coordinator loops only for the `Coordinator`
  role, leaving `Infernix.Runtime.Pulsar` as the shared transport/loop module
- `src/Infernix/Runtime/Pulsar/Failover.hs` centralizes Failover consumer naming:
  `runResultBridgeLoop`, `runDispatcherForContext`, `runContextsMetadataConsumer`, and
  `runModelBootstrapLoop` keep stable subscription names but use process-qualified consumer names
  so multiple coordinator replicas do not present identical member names during broker promotion
- the Haskell style boundary covers `src/Infernix/Runtime/KVCache.hs` alongside `Runtime.hs`,
  `Runtime/Cache.hs`, and `Runtime/Worker.hs`, so the engine-side cache consistency helper cannot
  import demo, coordinator, auth, object-presign, bootstrap, or WebSocket modules
- `Infernix.Bridge.Result` (shared library; replaces the previously planned
  `Infernix.Demo.ResultBridge` so the result-bridge is product-agnostic) — Pulsar
  Failover-subscribed consumer on `inference.result.<mode>` that writes typed `InferenceResult`
  events to the conversation topic with producer dedup keyed by
  `(userPromptMessageId, kind = InferenceResult)`; instantiated in the `infernix-coordinator`
  Deployment, not in any app pod or the engine pod
- Pulsar producer dedup enabled on `inference.result.<mode>` keyed by `userPromptMessageId`
- the engine daemon does **not** import `Infernix.Demo.*`, `Infernix.Bridge.Result`, or
  `Infernix.Dispatch.SingleFlight`

### Validation

- unit test: tampered `prefixHash` causes cache miss; matching hash causes cache hit; rebuild
  produces identical output
- integration chaos test (Sprint 7.14) kills the engine pod mid-inference; surviving pod
  rebuilds KV cache from log; producer dedup prevents duplicate result
- E2E: prompt → response cycle works end-to-end against a real model

### Remaining Work

None.

---

## Sprint 7.9: Demo MinIO Bucket and Presigned URL Minting [Done]

**Status**: Done — runtime bucket repair, the presigned/proxied grant path, and the Sprint 7.8 blocker are closed on both rebuilt-image Linux lanes.
**Implementation**: `chart/values.yaml`, `src/Infernix/Objects/Layout.hs`, `src/Infernix/Objects/Presigned.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Demo/Bootstrap.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/minio.md`, `documents/engineering/object_storage.md`, `documents/reference/api_surface.md`

### Objective

Land the demo's user-facing MinIO bucket `infernix-demo-objects` plus per-user prefix layout
and the `/api/objects` HTTP endpoint that mints presigned PUT and GET URLs scoped to the
authenticated user. The bucket is the demo-gated member of the supported three-bucket model
defined in Sprint 7.7 (`infernix-models` always-on platform weights and
`infernix-engine-artifacts` always-on engine payloads are the other two).

### Deliverables

- `infernix-demo-objects` bucket added to `chart/values.yaml` MinIO bucket list (demo-gated)
- `Infernix.Objects.Layout` — bucket and prefix conventions
  (`users/<userId>/contexts/<contextId>/{uploads,generated}/`); per-user scope helpers
- `Infernix.Objects.Presigned` — presigned URL minting helpers parameterized in the MinIO
  client config and grant-time scope check
- `Infernix.Demo.Api` — `/api/objects` HTTP route that consumes JWT, validates per-user
  scope, and returns presigned PUT or GET URLs. The handlers read the
  `Authorization: Bearer …` header, fetch the Keycloak JWKS from mounted
  `ClusterConfig.keycloak.*` through a bounded HTTP fetch so a bad JWKS route reports as a backend
  failure instead of hanging until the edge proxy timeout, call
  `Infernix.Auth.Jwt.verifyAndParseJwt`, derive `UserId` from `sub`, scope the requested object to
  `users/<userId>/contexts/<contextId>/{uploads,generated}/`, and validate that scope through
  `pathBelongsToUser`. Sprint 7.25 replaces the presigned-URL grant body with a webapp byte proxy;
  the typed disposition carried on the download grant survives that change
- `runDemoApiServer` owns a process-lifetime `JwksCache` (`IORef (Maybe (UTCTime, Jwks))`)
  threaded through both the `/ws` handshake and the `/api/objects` handlers, with a 5-minute TTL
  so a JWKS rotation surfaces within one cache cycle without an upstream certs fetch per request
- `Infernix.Demo.Bootstrap` — idempotent first-run bucket creation via `requiredDemoBuckets` plus
  the pure `planDemoBucketBootstrap` missing-bucket diff. At startup with `demo_ui = true` and a
  mounted `ClusterConfig`, `repairDemoBucketsAtStartup` creates the required demo buckets with
  presigned `PUT /<bucket>` requests (`PresignedBucketRequest` / `presignedBucketUrl`), treats
  HTTP 200 and 409 as successful idempotent outcomes, retries while MinIO converges, and logs a
  host-native skip when no cluster config is mounted
- `/api/objects` route added to the Haskell route registry source

### Validation

- integration test mints a presigned PUT for user A, uploads, mints presigned GET, downloads;
  asserts content equality
- cross-user negative test: user A and user B with the same logical context/display name receive
  distinct per-`sub` object prefixes; one user's default grant path cannot read the other's object
- when `demo_ui = false`, the bucket and `/api/objects` route are absent

### Remaining Work

None.

---

## Sprint 7.10: SPA Chat View [Done]

**Status**: Done
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `web/src/Infernix/Web/WebSocket.purs`, `web/src/Infernix/Web/WebSocket.js`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Auth.js`, `web/src/Infernix/Web/Browser.purs`, `web/src/Infernix/Web/Browser.js`, `web/src/Infernix/Web/DomEvents.purs`, `web/src/Infernix/Web/DomEvents.js`, `web/src/Infernix/Web/Router.purs`, `web/spago.yaml`, `web/test/Infernix/Web/ChatSpec.purs`, `web/src/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`, `documents/development/purescript_policy.md`

### Objective

Land the Chat view: left rail of contexts, active conversation pane, draft restore, cancel
button, two-prompt queued indicator. All state changes flow from server-sent
`ConversationStatePatch` / `ContextListPatch` / `DraftMapPatch` messages applied by trivial
mechanical helpers; no business rule is reimplemented in PureScript.

### Deliverables

- `web/src/Infernix/Web/Auth.purs` — OIDC redirect handling, in-memory JWT storage, JWT
  refresh. The typed `TokenStore` keeps the access and refresh tokens in memory; only the
  temporary PKCE verifier/state pair crosses the redirect through session storage, and logout
  clears access token, refresh token, PKCE state, and timer state
- `web/src/Infernix/Web/WebSocket.purs` — WS connect with JWT handoff, framed-envelope send
  and receive against the `Web.Socket.WebSocket` browser binding, with a small `WebSocket.js`
  FFI for raw payload coercion. The socket sends a typed `ClientHello` as its first open frame
  and reports close events to the session layer
- `web/src/Infernix/Web/Chat.purs` — left rail context list, active conversation pane, draft
  text box, cancel button; renders projected state and applies patches mechanically through
  `applyConversationStatePatch`, `applyContextListPatch`, `applyDraftMapPatch`, the
  `handleServerMessage` dispatcher, and the `pendingPromptCount` queued-prompt counter, plus the
  DOM-level `renderChatView` renderer. None of these helpers reimplements a reducer rule.
  Pending prompts are computed by matching both inference-result and cancel events against their
  target prompt ids, and the browser cancel action targets the latest unresolved server-backed
  prompt id rather than creating a local optimistic entry
- `web/src/Infernix/Web/Router.purs` — SPA route table for Chat / Artifacts
- `web/src/Main.purs` extended to mount the durable-context surface when JWT is present, and to
  own generation-guarded WebSocket reconnect/reconstitution for authenticated sessions:
  an unexpected close clears only the stale connection, schedules reconnect with bounded backoff,
  resends `ClientHello`, and re-sends `ClientSubscribeContext` for the active context. Only the
  active context id and model id are stored in browser session storage — never tokens — and that
  state is cleared on logout

### Validation

- `purescript-spec` tests cover patch application + rendering correctness for each
  `ConversationStatePatch` variant; no reducer logic in PureScript
- E2E (Sprint 7.15) covers signup → context creation → prompt submission → response render
  → cancel → two-prompt queued indicator → conversation order preservation across reload

### Remaining Work

None.

---

## Sprint 7.11: SPA Artifacts View [Done]

**Status**: Done
**Implementation**: `web/src/Infernix/Web/Artifacts.purs`, `web/src/Infernix/Web/ArtifactTransport.purs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/test/Infernix/Web/ArtifactsSpec.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`, `documents/development/purescript_policy.md`

### Objective

Land the Artifacts view: per-context artifact list and per-user library, with upload via
presigned PUT, download via presigned GET, and in-browser rendering of image, playable audio, and
video, bounded preview for text/JSON, browser-native PDF handling, and download-only
handling for MIDI, MusicXML/MXL notation, unknown, and generic binary artifacts. Artifact
state is delivered as server-sent patches over the WS; the view is a renderer.

### Deliverables

- `web/src/Infernix/Web/Artifacts.purs` — per-context list, per-user library, upload UI
  with progress, download UI, inline rendering via `<img>` / `<audio>` / `<video>` against
  presigned URLs, bounded text/JSON preview, browser-native PDF handling, first-class
  MIDI and MusicXML/MXL notation download handling, and generic-binary download fallback
- `ArtifactsViewState` as the typed per-user library, contextually filtered by
  `artifactsForContext`, with `artifactEntryFromReady` (MIME inference from the object key when
  only the WS notification has arrived), `recordArtifactReady` (upsert keyed on bucket+key so
  repeated notifications collapse), `handleArtifactsServerMessage`, and `buildUploadRequest`.
  `dispositionFor` is the supported MIME-to-disposition mapping, and
  `Demo.Api.renderDispositionForMime` is the server-side matrix it must agree with
- HTTP upload helper that posts the typed upload request to `/api/objects`, then publishes a
  `ClientRecordUpload` frame over WS; `Runtime.Pulsar.planDemoClientMessagePublications` maps
  that frame to a per-context `ConversationUserUploadEvent` with producer dedup keyed by the
  uploaded `ObjectRef`, so a browser upload becomes visible in the conversation. Sprint 7.25
  replaces the browser-direct presigned PUT with the one-leg authenticated webapp proxy
- WS handler for `ArtifactReady` server messages renders the new artifact in place

### Validation

- `purescript-spec` view-model tests for artifact-kind dispatch
- E2E (Sprint 7.15) covers upload, download, render-or-download behavior for each supported
  artifact class, and the generated-artifact lifecycle (SDXL Turbo image, bark-small audio,
  Basic Pitch MIDI, Audiveris notation)

### Remaining Work

None.

---

## Sprint 7.12: SPA Model Picker Integration [Done]

**Status**: Done
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Dispatch/ContextModelMap.hs`, `src/Infernix/Runtime/Pulsar.hs` (`runContextsMetadataConsumer`, `emptyModelIdRejectionResult`)
**Docs to update**: `documents/architecture/demo_app_design.md`

### Objective

Wire the new-context flow to the active substrate's generated demo `.dhall` catalog so users
pick a model from the same set the active staged catalog exposes. Model selection pins the
context for life; switching models mid-context is out of scope.

### Deliverables

- `Chat.purs` model-picker modal sourced from the generated catalog
- WS `CreateContext` message includes the chosen `modelId`; backend validates against the
  active catalog and rejects unknown ids. `Runtime.Pulsar.publishDemoClientMessage` loads the
  active generated demo catalog before publishing `ClientCreateContext` and rejects model ids
  absent from it with typed error code `unknown-model`; `Demo.Api.mapDispatchError` preserves
  that code through the WebSocket `ServerError` response
- `src/Infernix/Dispatch/ContextModelMap.hs` owns the typed `ContextModelMap`
  (`IORef (Map Text Text)` keyed on `ContextId`) plus `newContextModelMap`, `lookupModelId`,
  `recordContextModel`, and `recordContextMetadataEvent`. `ContextCreated` pins the model id for
  the context's life; `ContextRenamed` and `ContextSoftDeleted` are no-ops for that binding
- `Runtime/Pulsar.hs.runContextsMetadataConsumer` is the per-user worker the coordinator
  dispatcher loop spawns on first sight of a userId: it subscribes Failover to
  `persistent://infernix/demo/demo.user.<userId>.contexts`, decodes each frame as a
  `ContextMetadataEvent`, and updates the shared map. `publishDispatchedInferenceRequest` takes
  the resolved `modelId` and populates the proto `request_model_id` field
- engine-side validation in `Pulsar.handleConsumerEnvelope` publishes a typed
  `emptyModelIdRejectionResult` (`status: "failed"` plus the typed error message) when the
  inbound `request_model_id` is empty, instead of delegating to the generic engine path; the
  result bridge writes it back to the conversation log so Chat renders the typed failure
- new-context dialog opening does not create backend state; closing without confirmation leaves
  no backend state

### Validation

- E2E: open new-context dialog, see catalog entries for the active substrate (skipping
  `Not recommended`), pick model, submit prompt, see context appear in left rail
- E2E negative: closing the dialog without confirmation creates no backend frame or local context

### Remaining Work

None.

---

## Sprint 7.13: Unit-Layer Validation [Done]

**Status**: Done
**Implementation**: `test/unit/*` (existing `infernix-unit` Cabal stanza), `web/test/Main.purs`, `web/test/Infernix/Web/ContractsSpec.purs`, `web/test/Infernix/Web/ChatSpec.purs`, `web/test/Infernix/Web/ArtifactsSpec.purs`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Land the unit test layer for every primitive added in Phase 7. Property-based wherever
ordering invariants matter.

### Deliverables

- reducer property tests: determinism over arbitrary `ConversationEvent` logs; idempotency
  dedup; cancellation semantics; two-prompt-in-a-row ordering. `assertConversationPropertyTests`
  in `test/unit/Spec.hs` generates arbitrary 0–8-message logs with prompt / cancel /
  inference-result / duplicate shapes and exercises three invariants — patch-stream replay
  converging to the snapshot reducer projection, `prefixHash` chain length-monotonicity plus
  determinism, and idempotency dedup dropping repeated `(contextId, key)` pairs — across
  shrinkable random cases; the `infernix-unit` stanza declares the QuickCheck dependency
- reducer-to-patch tests: given an event log, the Haskell reducer emits a patch stream that,
  applied to the initial state, converges to the same projection as the snapshot reducer
- `prefixHash` chain tests: determinism, monotonicity, equality under reorder of independent
  events, mismatch on tampered event
- dispatcher pure-fold rule tests across arbitrary log prefixes
- topic name derivation tests for every `TopicNamespace` shape
- JWT validation edge cases (expired, wrong issuer, wrong audience, malformed, valid)
- presigned URL minting tests (correct scope, correct expiration, signature shape)
- WS envelope codec roundtrip tests for every `WsClientMessage` / `WsServerMessage` variant
- compacted topic projection tests with synthetic in-memory broker
- PureScript `purescript-spec` view-model tests in `web/test/Infernix/Web/ChatSpec.purs` and
  `web/test/Infernix/Web/ArtifactsSpec.purs`, scoped to patch application and rendering only

### Validation

- `infernix test unit` includes all new suites and passes
- coverage report shows every new shared-library module is exercised

### Remaining Work

None.

---

## Sprint 7.14: Integration-Layer Validation [Done]

**Status**: Done (code-side closed for WebSocket-to-Pulsar publish plumbing, the coordinator-to-engine handoff contract, real Pulsar Reader roundtrip coverage for conversation/contexts/drafts/bootstrap-ready topic families, broker compacted-reader latest-per-key coverage, real broker producer-dedup validation, the non-chaos dispatcher/result-bridge durable prompt roundtrip, the Apple `engine.lock` chaos case (Wave A.3 in [cohort-validation-waves.md](cohort-validation-waves.md)), and the Linux-owned Sprint 7.14 chaos/throughput block implemented on the recorded cohort validation: frontend pod replacement, coordinator pod replacement around durable prompt dispatch/writeback, engine pod replacement, engine node drain, model-bootstrap request/ready-event deduplication across coordinator replacement, Linux engine anti-affinity, and multi-user durable prompt throughput. Native `linux-cpu` `infernix test all` validation passed on the recorded cohort validation; `linux-gpu` `infernix test all` validation passed on the recorded cohort validation in [Wave C](cohort-validation-waves.md). The mounted Linux CPU `cabal test infernix-integration` rerun on the recorded cohort validation passed against the Sprint 7.8 runtime KV-cache and daemon-orchestration split worktree.)
**Implementation**: `test/integration/*` (existing `infernix-integration` Cabal stanza), `test/integration/Spec.hs (multi-user throughput logic — ThroughputMatrix, validateMultiUserDurablePromptThroughput/...With — lives inline in this module Main)`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/chaos_testing.md`, `documents/tools/pulsar.md`, `documents/architecture/daemon_topology.md`

### Objective

Land the integration test layer covering real-cluster Pulsar / MinIO / Keycloak round-trips,
the chaos tests for the per-role failure semantics from
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md),
and the multi-user throughput / fan-in batching / fan-out test.

### Deliverables

- real Pulsar publish + Reader subscribe round-trip per topic family (conversation, compacted
  contexts, compacted drafts, inference request/batch/result).
  `src/Infernix/Runtime/Pulsar.hs.publishDemoClientMessage` maps browser `WsClientMessage` frames
  onto those durable families with mutation-scoped producer names and idempotency-derived
  WebSocket `initialSequenceId` baselines so broker dedup collapses reconnect and retry
  duplicates, and `src/Infernix/Demo/Api.hs` wires that callback through
  `WebSocketOptions.wsDispatchClientMessage`
- real Pulsar producer dedup verification across simulated coordinator restart mid-flight;
  assert exactly-one inference dispatch and exactly-one result
- real Pulsar Failover handoff: kill active coordinator replica; assert surviving consumer
  resumes
- real MinIO presigned PUT/GET byte lifecycle with per-user scoping; same-user routed byte
  equality, routed grant minting, and routed cross-user object-prefix isolation are covered by
  Sprint 7.15
- real Keycloak login + JWT validation round-trip; browser signup, auth-code exchange,
  malformed bearer rejection, backend JWT acceptance for `/api/objects`, routed WebSocket
  valid/malformed/expired-token handshake behavior, and typed malformed-frame `ServerError`
  handling are covered by Sprint 7.15
- chaos tests against the supported three-role daemon model:
  - **Frontend (WS-hosting) pod kill mid-session**: WS reconnect succeeds; no state loss
  - **Coordinator pod kill mid-dispatch**: Failover promotes a surviving coordinator;
    producer dedup on `inference.request.<mode>` and `inference.batch.<mode>` prevents
    duplicates
  - **Coordinator pod kill mid-result-bridge**: Failover promotes a surviving coordinator;
    producer dedup on the conversation topic (keyed by
    `(userPromptMessageId, kind = InferenceResult)`) prevents a duplicate writeback
  - **Engine pod kill mid-inference**: Pulsar redelivers the unacked batch; surviving engine
    on another node rebuilds KV cache via `prefixHash`; producer dedup on
    `inference.result.<mode>` prevents a duplicate result
  - **Engine node drain**: engine PDB blocks the drain until another engine pod is
    available cluster-wide; cluster keeps serving inference throughout
  - **Coordinator pod kill mid-bootstrap upload**: kill the active coordinator replica
    after some weight files have PUT to `infernix-models/<modelId>/` but before the
    `.ready` sentinel; surviving coordinator replica resumes (the Failover subscription,
    attempt-scoped request dedup, and MinIO `.ready` guard prevent duplicate effective
    population); the `.ready`
    sentinel appears exactly once; waiting engines observe ready and proceed
  - **Concurrent bootstrap requests**: N engine pods request the same uncached model
    simultaneously; producer dedup + Pulsar Failover guarantees exactly one upstream
    download; all N engines observe the `.ready` sentinel and proceed
  - **Engine placement enforcement**: on Linux,
    `kubectl scale deployment/infernix-engine --replicas=N+1` leaves the extra pod
    `Pending` with the anti-affinity rejection; the older Apple duplicate-daemon
    `engine.lock held by PID ...` diagnostic is historical and superseded by host-id pool
    membership plus pinned `Exclusive` routes
  each case asserts exactly-once outcome and full state preservation
- model-cache eviction test: trigger model loads until `/model-cache` size pressure
  exists; assert the adapter helper evicts LRU entries; assert the engine pod is not
  restarted by kubelet for ephemeral-storage exhaustion
- production-shape test: deploy `demo_ui = false` and assert
  `infernix kubectl -n platform get deployments` returns the production coordinator plus
  engine-pool workloads;
  `infernix-models` and `infernix-engine-artifacts` buckets are present;
  `infernix-demo-objects` bucket is absent;
  `infernix kubectl get pvc -A` returns empty
- **Multi-User Throughput / Fan-In Batching / Fan-Out** test: N users × K contexts × P
  prompts on one model, asserting per-context ordering, no duplicates or losses,
  cross-context independence, batching gain, bounded p95 latency, dedup correctness;
  implemented inline in `test/integration/Spec.hs` (module Main) via `validateMultiUserDurablePromptThroughput`; defaults N = 10, K = 3, P = 5

### Validation

- `infernix test integration` includes all new suites and passes on at least one substrate
  with `demo_ui = true`
- throughput test reports per-context ordering, exact result counts, p95 latency, batching
  factor, and dedup counter values
- `test/integration/Spec.hs` carries the real-broker contract as named suites: durable topic-family
  roundtrips (`validateDurableTopicFamilyRoundTrips`), compacted latest-per-key behavior
  (`validateCompactedTopicBrokerBehavior`, which also closes Sprint 7.5's compaction gate),
  producer dedup (`validateProducerDeduplicationBehavior`), the non-chaos durable-context prompt
  roundtrip (`validateDurableContextPromptRoundTrip`), the per-role chaos cases, and the
  parameterized multi-user throughput matrix (`validateMultiUserDurablePromptThroughput` /
  `...With`, integration default 3 users × 2 contexts × 2 prompts)
- per-run image digests and the attempt-by-attempt history live in
  [cohort-validation-waves.md](cohort-validation-waves.md), not here

### Remaining Work

None. The integration layer is closed.

---

## Sprint 7.15: E2E-Layer Validation [Done]

**Status**: Done — the durable-context browser flow, the fixture-backed artifact flow, and the per-model browser matrix pass on both rebuilt-image Linux lanes.
**Implementation**: `web/src/Main.purs`, `web/src/index.html`, `web/src/Infernix/Web/ArtifactTransport.purs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Auth.js`, `web/test/Main.purs`, Playwright suites under the repo's Playwright tree, run inside the active Linux substrate image; `web/test/fixtures/`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`

### Objective

Land the E2E test layer through the active substrate image's Playwright runtime. Substrate-agnostic
at the browser layer. Includes per-model smoke matrix.

### Deliverables

- Playwright flows: auth lifecycle (signup, login, logout, re-login, JWT refresh); context
  lifecycle (new-context dialog open/close/create, rename, soft-delete, select); conversation lifecycle
  (submit, response, two-in-a-row queued, cancel-mid-inference, order preservation across
  reload); draft lifecycle (type, refresh, restored, per-context isolation, submit clears
  draft); artifact upload lifecycle per supported artifact class; artifact download plus
  inline render, bounded preview, browser-native PDF handling, or download-only handling;
  generated-artifact lifecycle; multi-tab convergence; client reconstitution via Playwright
  Browser Context storage-clear; pod-failover-from-browser
- **Per-Model Smoke Matrix**: parameterized flow that reads the active substrate's generated
  `.dhall`, iterates every catalog entry whose engine cell for the active substrate is not
  `Not recommended`, creates a fresh context pinned to that model, submits a
  family-appropriate canonical input from `web/test/fixtures/`, asserts Completed
  `InferenceResult`, asserts artifact appearance and rendering
- `web/test/fixtures/artifactSamples.js` checked-in canonical sample payloads (inline
  text, JSON, PNG, WAV, MP4, PDF, MIDI, MusicXML, and generic-binary buffers via
  `textPreviewBody`, `jsonPreviewBody`, `tinyPngBuffer`, `tinyWavBuffer`, `tinyMp4Buffer`,
  `tinyPdfBuffer`, `tinyMidiBuffer`, `musicXmlBuffer`, `binaryArtifactBuffer`), imported by
  `web/playwright/inference.spec.js` and by the per-model smoke matrix
- `src/Infernix/CLI.hs.runPlaywrightWithFixture` invokes Playwright from the repo root with the
  explicit `web/playwright.config.js` path, and that config reads the typed fixture from
  `.data/runtime/playwright-fixture.json`
- `web/src/index.html` is the dense app shell with Chat, Artifacts, route inventory, and runtime
  summary mount points; `web/src/Main.purs` mounts the durable-context shell, loads routed
  `/api/publication` and `/api/models`, and delegates the main panes to `Chat.renderChatView` and
  `Artifacts.renderArtifactsView`. The prior manual-inference Workbench shell and its unit
  surface are gone
- browser-level pod-failover coverage deletes all `infernix-demo` pods through the typed
  `infernix kubectl` fixture hook, waits for replacements, verifies `ClientHello` plus the active
  `ClientSubscribeContext` are resent, receives a fresh `ServerConversationSnapshot`, and submits
  another prompt through the reconnected socket

### Validation

- `infernix test e2e` runs the Playwright suite via the active substrate image's Playwright
  runtime
- per-model smoke matrix has one passing flow per non-`Not recommended` row in the README
  matrix for the active substrate; failure on any row fails the suite
- the Playwright source is byte-identical across `apple-silicon`, `linux-cpu`, `linux-gpu`;
  substrate selection lives only in the `.dhall` the demo app reads

### Remaining Work

None. The per-model smoke matrix is validated on Apple, `linux-gpu`, and `linux-cpu`.

---

## Sprint 7.16: Documentation Closure [Done]

**Status**: Done (docs lint passed on the recorded cohort validation after the residual-sweep docs update and again on the recorded cohort validation after the runtime KV-cache plus `Infernix.Runtime.Daemon` realignment.)
**Implementation**: every doc named in this phase
**Docs to update**: all docs named in Documentation Requirements below

### Objective

Finalize the governed docs touched by Phase 7. Every doc is aligned with the implemented
behavior. `infernix lint docs` is clean.

### Deliverables

- every new doc named below exists with the required metadata block
- every existing doc named below is updated for the durable-context surface
- the `Application Library Boundary` extension to
  `documents/engineering/implementation_boundaries.md` codifies the shared-vs-demo-vs-daemon
  module ownership
- `infernix lint docs` passes

### Validation

- `infernix lint docs` exits zero
- the recorded cohort validation Linux outer-container validation:
  `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm infernix infernix lint docs`
  exits zero after the residual-sweep docs update
- a fresh contributor can locate the canonical home for every Phase 7 topic via the suite
  index

### Remaining Work

None.

---

## Sprint 7.17: Secrets-via-Files and Demo-Surface Retirement [Done]

**Status**: Done
**Implementation**: `src/Infernix/SecretsConfig.hs` (`SecretsConfig` decoder type = reflected schema; no tracked `.dhall`), `src/Infernix/Demo/Api.hs`, `src/Infernix/Demo/Auth.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Python.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/secret-cluster-secrets.yaml`, `chart/templates/keycloak/deployment.yaml` (KC_DB_* documented exception).
**Docs to update**: `documents/architecture/configuration_doctrine.md`, `documents/engineering/cluster_config_manifest.md`, `documents/tools/keycloak.md`, `documents/tools/minio.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the `InfernixSecrets.dhall` typed paths-only schema + matching Haskell reader. Retire
every `INFERNIX_KEYCLOAK_*` and `INFERNIX_MINIO_*` env-var consumer in favor of `ClusterConfig`
fields (for non-secret values) plus file-based Secret mounts (for credentials). Retire
`INFERNIX_POETRY_*` env reads. Mount `/etc/infernix/secrets/` on the demo pod from a Kubernetes
`Secret`; Keycloak's `KC_DB_*` upstream contract stays as the documented third-party exception.

### Deliverables

- the `SecretsConfig` decoder type (reflected schema) with the `Minio`, `KeycloakAdmin`, `KeycloakDb`
  paths-only records named in
  [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md).
- `SecretsConfig` typed record + decoder; threaded through the demo backend entry point.
- The Haskell application calls `readFile (SecretsConfig.minio.credentialsPath)` and parses the
  JSON for MinIO credentials; never reads `INFERNIX_MINIO_ACCESS_KEY` / `SECRET_KEY`.
- `INFERNIX_KEYCLOAK_BASE_URL`, `INFERNIX_KEYCLOAK_REALM_NAME`, `INFERNIX_KEYCLOAK_CLIENT_ID`,
  `INFERNIX_KEYCLOAK_JWKS_URL`, `INFERNIX_MINIO_ENDPOINT`, `INFERNIX_MINIO_REGION`,
  `INFERNIX_MINIO_PRESIGN_EXPIRY_SECONDS`, `INFERNIX_MINIO_ACCESS_KEY`,
  `INFERNIX_MINIO_SECRET_KEY`, `INFERNIX_POETRY_EXECUTABLE`, `POETRY_HOME`,
  `POETRY_VIRTUALENVS_IN_PROJECT` env reads all deleted from `src/Infernix/Demo/Api.hs`,
  `src/Infernix/Demo/Auth.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Python.hs`.
- `POETRY_VIRTUALENVS_IN_PROJECT` behaviour moves to a `poetry.toml` config file at the project
  root.
- the Poetry executable comes from `HostConfig.toolPaths.hostPoetry` via `pathsHostConfig paths`
  with `onlyIfExists` guarding stale fixture paths; `bootstrapPoetryOnAppleHost` takes a `Paths`
  argument and routes through `HostConfig.hostFilesystem.hostHomeDirectory` for the install root
  and `HostConfig.toolPaths.hostPython3` for the bootstrap interpreter.
  `prependDirectoryToPath`, `activatePoetryExecutable`, and `firstCompatibleCommandOnPath` are
  deleted, and downstream callers invoke Poetry through the absolute path returned by
  `ensurePoetryExecutable`. The `Lint/HaskellStyle.hs.envFunctionExemptedFiles` row for
  `src/Infernix/Python.hs` is deleted with it; `bareNameProcExemptedFiles` never carried one.
- `chart/templates/deployment-demo.yaml` `env:` block deleted; demo pod mounts the cluster
  ConfigMap + the cluster Secret at `/opt/infernix/cluster.dhall` and `/etc/infernix/secrets/`.
- `chart/templates/secret-cluster-secrets.yaml` renders the operator-supplied credentials as a
  Kubernetes `Secret`.
- `chart/templates/keycloak/deployment.yaml` retains `KC_DB_*` env entries (Keycloak upstream
  contract) and documents the third-party exception in `documents/tools/keycloak.md` + the
  lint-gate exception list.

### Validation

- `rg -n 'lookupEnv|getEnv' src/Infernix/Demo/Api.hs src/Infernix/Demo/Auth.hs src/Infernix/Runtime/Pulsar.hs` returns zero matches.
- `grep -rn '^\s*-\s*name:\s*INFERNIX_' chart/templates/deployment-demo.yaml` returns zero
  matches.
- Apple cohort validation closed in Wave A. CUDA Linux validation closed in Wave C with
  `linux-cpu` passing on the recorded cohort validation and `linux-gpu` passing on the recorded cohort validation.

### Remaining Work

None. Closed by [Wave A](cohort-validation-waves.md) and [Wave C](cohort-validation-waves.md).

---

## Sprint 7.18: Declarative-State Phase Prose Rewrite [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/phase-7-demo-app-durable-context.md` (prose only)
**Docs to update**: this file

### Objective

Rewrite Phase 7 prose so the supported three-role daemon split (`infernix-coordinator`,
`infernix-engine`, demo-gated `infernix-demo`) is described as the supported shape directly.
Cleanup history lives in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
Per-sprint dated proof points are removed; cohort closure references via
`Wave A`/`Wave A.1`/`Wave A.2`/`Wave A.3`/`Wave C` remain.

### Deliverables

- Phase Status uses present-tense vocabulary; the runtime KV-cache and `Infernix.Runtime.Daemon`
  prose describes the supported shape directly.
- Sprint 7.7 prose describes its deliverable as introducing the supported three-role split
  (`infernix-coordinator` + substrate-specific engine pools + demo-gated `infernix-demo`) and the supported
  MinIO-backed object-storage contract, with cleanup receipts held in
  `legacy-tracking-for-deletion.md`.
- Sprint 7.8/7.14/7.15/7.17 prose is declarative current-state; dated hardware proof points and
  per-run attempt chronology live in [cohort-validation-waves.md](cohort-validation-waves.md), and
  cohort closure references remain.
- Per-sprint Validation sections retain test-name and gate references, drop daily proof points,
  and anchor on the canonical architecture documents.

### Validation

- The phase-specific lexical guard for unsupported historical-state vocabulary and dated
  proof-point prose returns no matches outside cleanup-ledger references.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

None.

---

## Sprint 7.19: Auth-Gated Landing and Dual Entry Points [Done]

**Status**: Done
**Implementation**: `web/src/index.html`, `web/src/Main.purs`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Auth.js`
**Docs to update**: [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../README.md](../README.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), [system-components.md](system-components.md)

### Objective

Move the `infernix-demo` app shell behind authentication. Pre-auth visitors see a minimal
centred landing card with the `Infernix` wordmark, a one-line subtitle, and two explicit
CTAs (`Sign in` primary, `Create account` secondary), each deep-linking the matching Keycloak
form via OIDC Application Initiated Actions (AIA). The summary grid (Runtime, Control Plane,
Daemon, Dispatch, Edge, Catalog, Connection) and the Chat / Artifacts tabs are no longer
rendered for anonymous visitors.

### Deliverables

- `web/src/index.html` carries a pre-auth `<div class="app-landing">` containing the
  landing card and the new `#register-button`; the existing `.app-shell` (header + summary
  grid + tabs + workspace) stays inline so the existing `captureRefs` bootstrap path is
  unchanged. A `body` class — `auth-unknown`, `auth-signed-in`, `auth-signed-out` — toggles
  visibility via CSS: only the landing renders when signed out, only the shell renders when
  signed in, and the `auth-unknown` boot state hides both until PureScript reads the in-memory
  JWT.
- `web/src/Main.purs.renderAuthGate` sets the body class on every `renderAll` pass from
  `state.authenticated`. The bootstrap captures the body via `HTMLDocument.body` +
  `HTMLElement.toElement`; when absent (e.g. SSR fixtures) the gate is a no-op.
- `web/src/Main.purs.bindEvents` wires the new `#register-button` to
  `beginRegisterRedirect defaultInfernixRealmConfig`.
- `web/src/Infernix/Web/Auth.purs` exports
  `beginRegisterRedirect :: RealmConfig -> Effect Unit` alongside `beginLoginRedirect`.
- `web/src/Infernix/Web/Auth.js` factors the PKCE / state / nonce setup into a shared
  `beginAuthorizationCodeRedirect(config, endpoint, kcAction)` helper; `beginLoginRedirectImpl`
  uses the `auth` endpoint and `beginRegisterRedirectImpl` uses the `registrations` endpoint so
  Keycloak lands the user on the registration form. PKCE verifier, state, nonce, and the callback
  handler are unchanged — Keycloak returns to the same `redirect_uri` after either flow.

### Validation

- `npm --prefix web run build` exits zero (Haskell + PureScript; bundle written to
  `web/dist/app.js`).
- `npm --prefix web run test:unit` exits zero (71/71 cases pass).
- `./.build/infernix lint docs` exits zero after the doc edits named in `Docs to update`.
- Manual UX check at the published edge port: pre-auth shows only the landing card with two
  buttons (no header, no summary grid, no tabs); `Sign in` redirects to Keycloak's login
  form; `Create account` redirects to Keycloak's registration form; after either flow the app
  shell renders unchanged.
- A new Playwright case in `web/playwright/inference.spec.js` asserts the splash renders
  exactly the two buttons pre-auth and that each redirect lands on the matching Keycloak
  form. Apple cohort closure recorded in [cohort-validation-waves.md](cohort-validation-waves.md).

### Remaining Work

None.

### Documentation Requirements

**Architecture docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — `## Landing Surface` (pre-auth splash composition, body-class state machine) and `## Authentication Entry Points` (dual `Sign in` / `Create account` CTAs with their AIA mapping).
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — extend the identity/auth section with the dual entry points; note that the app shell is gated on JWT presence.

**Reference docs to update:**
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — `## Pre-Auth Landing` section listing the landing card + two CTAs.

**Development docs to update:**
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — new test row: "pre-auth splash renders exactly two CTAs and routes each to the matching Keycloak form."

**Root docs to update:**
- [../README.md](../README.md) — extend the demo-UI paragraph with the dual-CTA landing.

**Plan docs to update:**
- [system-components.md](system-components.md) — record the new `#register-button` plus the body-class state machine as part of the `infernix-demo` SPA bootstrap surface.
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — completed cleanup entries for the retired pre-auth shell and single-CTA surfaces.
- [cohort-validation-waves.md](cohort-validation-waves.md) — wave row for the auth-UX quad closure.

---

## Sprint 7.20: Themed Keycloak Login Surface [Done]

**Status**: Done
**Implementation**: `chart/templates/keycloak/configmap-theme.yaml`, `chart/templates/keycloak/deployment.yaml`, `chart/templates/keycloak/configmap-realm-import.yaml`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Chart.hs`, `web/playwright/inference.spec.js`
**Docs to update**: [../documents/tools/keycloak.md](../documents/tools/keycloak.md), [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../README.md](../README.md), [system-components.md](system-components.md)

### Objective

Make the routed Keycloak login and registration pages visually part of the Infernix demo without
forking or rebuilding the upstream Keycloak image. The stock Keycloak container stays in the image
inventory; the theme is a chart-owned ConfigMap selected by the realm import and preserved by the
idempotent admin reconcile.

### Deliverables

- `chart/templates/keycloak/configmap-theme.yaml` renders `ConfigMap/infernix-keycloak-theme`
  with `login/theme.properties`, `login/messages/messages_en.properties`, and
  `login/resources/css/infernix.css`.
- `chart/templates/keycloak/deployment.yaml` mounts the theme at
  `/opt/keycloak/themes/{{ .Values.keycloak.theme.name }}` and keeps the stock Keycloak image.
- `chart/templates/keycloak/configmap-realm-import.yaml` sets
  `loginTheme = {{ .Values.keycloak.theme.name }}`.
- `src/Infernix/Cluster.hs.keycloakRealmReconcilePayload` reapplies `loginTheme = infernix`
  during the post-rollout Keycloak admin reconcile so repeat `cluster up` runs do not drift back
  to the upstream default theme.
- `src/Infernix/Lint/Chart.hs` requires the theme ConfigMap and checks the key theme phrases.
- `web/playwright/inference.spec.js` asserts the themed login and registration titles in the
  routed pre-auth smoke.

### Validation

- `cabal test infernix-haskell-style` exits zero.
- `./.build/infernix lint chart` exits zero.
- `./.build/infernix lint docs` exits zero.
- `npm --prefix web run test:unit` exits zero.
- Wave G routed E2E verifies the Keycloak pages show `Sign in to Infernix` and
  `Create your Infernix account`.

### Remaining Work

None.

### Documentation Requirements

**Tools docs to update:**
- [../documents/tools/keycloak.md](../documents/tools/keycloak.md) — mounted theme ConfigMap,
  realm import, admin reconcile, and Playwright theme assertions.

**Architecture and reference docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — theme selection on the redirected Keycloak forms.
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — identity/auth section includes the themed forms.
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — user-visible `/auth` title text.

**Development docs to update:**
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — Playwright assertion for the theme.

**Root and plan docs to update:**
- [../README.md](../README.md) — demo paragraph includes the chart-owned Keycloak theme.
- [system-components.md](system-components.md) — component inventory records the theme ConfigMap.

---

## Sprint 7.21: Operator Console Ribbon and Edge JWT Gating [Done]

**Status**: Done
**Implementation**: `web/src/index.html`, `web/src/Infernix/Web/Auth.js`, `web/playwright/inference.spec.js`, `chart/templates/securitypolicy-operator-routes.yaml`, `chart/values.yaml`, `src/Infernix/Lint/Chart.hs`
**Docs to update**: [../documents/engineering/edge_routing.md](../documents/engineering/edge_routing.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../README.md](../README.md), [system-components.md](system-components.md)

### Objective

Expose the platform's local operator consoles from the authenticated demo shell and close those
published prefixes behind the same Keycloak JWT trust boundary as the demo API / WebSocket
surface.

### Deliverables

- The signed-in app shell renders an operator console ribbon linking to `/harbor`,
  `/pulsar/admin/admin/v2/clusters`, and `/minio/s3`; the ribbon stays hidden with the app shell
  before authentication.
- `web/src/Infernix/Web/Auth.js` writes the current Keycloak access token to the
  `infernix_operator_token` cookie on token receipt / refresh and clears the cookie on logout
  (with Keycloak SSO logout added later by Phase 9 Sprint 9.9).
- `chart/templates/securitypolicy-operator-routes.yaml` renders
  `SecurityPolicy/infernix-operator-routes-jwt`, targeting the Harbor portal, Pulsar Admin, and
  MinIO S3 HTTPRoutes. The policy accepts either the SPA-written cookie or a direct
  `Authorization: Bearer ...` header and validates against the configured Keycloak JWKS endpoint.
- `src/Infernix/Lint/Chart.hs` requires the new SecurityPolicy template and the chart values that
  configure operator-route JWT gating.
- The routed Playwright source asserts the ribbon links, the cookie login / refresh / logout
  lifecycle, unauthenticated operator-route rejection, and authenticated operator-route access.

### Validation

- `cabal test infernix-haskell-style` exits zero.
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  refreshes the Apple host-native `./.build/infernix` lint binary after the chart-lint change.
- `./.build/infernix lint chart` exits zero.
- `./.build/infernix lint docs` exits zero.
- `helm template infernix chart` exits zero.
- `npm --prefix web run test:unit` exits zero.
- Wave G routed E2E verifies the operator route family rejects requests without a JWT and accepts
  the real Keycloak token through the supported cookie or bearer-header paths.

### Remaining Work

None. Wave G routed E2E closed the operator-console ribbon and JWT-gated operator routes.

### Documentation Requirements

**Engineering and reference docs to update:**
- [../documents/engineering/edge_routing.md](../documents/engineering/edge_routing.md) — operator-route SecurityPolicy ownership and JWT validation contract.
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — operator console ribbon, route links, and cookie/header auth paths.

**Architecture and development docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — signed-in ribbon and token-cookie lifecycle.
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — demo identity boundary includes operator-console links.
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — Playwright assertions for ribbon visibility, cookie lifecycle, and JWT-gated operator routes.

**Root and plan docs to update:**
- [../README.md](../README.md) — demo paragraph includes the ribbon and edge JWT policy.
- [system-components.md](system-components.md) — component inventory records the SPA cookie bridge and SecurityPolicy.

---

## Sprint 7.22: Self-Service Account Deletion and State Reaping [Done]

**Status**: Done
**Implementation**: `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Conversation/Topic.hs`, `src/Infernix/Objects/Presigned.hs`, `web/src/Infernix/Web/Auth.js`, `web/src/Infernix/Web/Auth.purs`, `web/src/Main.purs`, `web/src/index.html`, `web/playwright/inference.spec.js`, `test/unit/Spec.hs`
**Docs to update**: [../documents/tools/keycloak.md](../documents/tools/keycloak.md), [../documents/tools/minio.md](../documents/tools/minio.md), [../documents/tools/pulsar.md](../documents/tools/pulsar.md), [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md), [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md), [../README.md](../README.md), [system-components.md](system-components.md)

### Objective

Let a signed-in demo user delete their account without leaving demo-owned durable state behind.
The browser must not enter Keycloak's account-deletion action until the backend has removed the
caller's MinIO prefix and user-owned Pulsar durable-context topics.

### Deliverables

- `DELETE /api/account` validates the current Keycloak JWT, derives `UserId` from `sub`, deletes
  every object returned by S3 ListObjectsV2 under
  `infernix-demo-objects/users/<userId>/`, deletes user-owned demo Pulsar topics in bounded
  routed-safe cleanup slices, and returns a cleanup summary with `cleanupComplete` plus any
  remaining topic names.
- `Infernix.Objects.Presigned` can sign S3 ListObjectsV2 bucket queries and DELETE Object
  requests without adding an SDK dependency or changing existing PUT/GET grant behavior.
- `Infernix.Conversation.Topic.topicBelongsToUser` identifies the exact caller-owned topic set:
  `demo.user.<userId>.contexts`, `demo.user.<userId>.drafts`, and
  `demo.conversation.<userId>.*`; shared inference request/batch/result topics stay intact.
- `Infernix.Runtime.Pulsar.deleteDemoUserTopics` discovers the supported Pulsar transport,
  lists `persistent://infernix/demo`, filters by the user-topic predicate, and deletes matching
  topics with the Pulsar admin API. `deleteDemoUserTopicsWithAttemptBudget` lets the routed API
  return `202` while cleanup is still draining instead of letting Envoy time out the request.
- Browser-facing Pulsar reader retry loops let async exceptions terminate the child threads, so a
  WebSocket close during account deletion does not respawn stale per-user readers and recreate the
  deleted topics.
- The signed-in SPA shell renders `Delete account`; `web/src/Infernix/Web/Auth.js` confirms the
  command, retries `DELETE /api/account` while the backend reports `cleanupComplete = false`,
  clears local browser auth state after completion, then starts Keycloak with
  `kc_action=delete_account`.
- The routed Playwright source creates real per-user state, clicks `Delete account`, verifies the
  cleanup response, verifies the previously readable MinIO object returns `404`, verifies the
  user's topics disappear from Pulsar admin, and verifies the Keycloak request carries
  `kc_action=delete_account`.

### Validation

- `cabal test infernix-unit` exits zero, including the new pure topic-predicate and presigner
  query/DELETE assertions.
- `cabal test infernix-haskell-style` exits zero.
- `npm --prefix web run test:unit` exits zero (71/71 cases pass).
- `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  refreshes the Apple host-native `./.build/infernix` binary.
- `./.build/infernix test e2e` exits zero on the supported Apple host-native lane with 9/9 routed
  Playwright tests passing, including account deletion in 2.9 seconds on the final run.
- Wave G routed E2E verifies the complete browser account-deletion flow against real Keycloak,
  MinIO, Pulsar, and Envoy Gateway.

### Remaining Work

None.

### Documentation Requirements

**Tools docs to update:**
- [../documents/tools/keycloak.md](../documents/tools/keycloak.md) — `kc_action=delete_account`
  sequencing after backend cleanup.
- [../documents/tools/minio.md](../documents/tools/minio.md) — user-prefix deletion through S3
  ListObjectsV2 and DELETE Object.
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — user-owned topic deletion and
  shared-topic boundary.

**Architecture, reference, and development docs to update:**
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — delete button, backend cleanup, and redirect sequencing.
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — `/api/account` transport and state-reaping semantics.
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — visible `Delete account` command and endpoint contract.
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — routed account-deletion smoke.

**Root and plan docs to update:**
- [../README.md](../README.md) — demo paragraph includes account deletion.
- [system-components.md](system-components.md) — component inventory records the backend state reap
  and Keycloak action sequencing.

---

## Sprint 7.23: Apple Host Engine Pulsar Singleton [Done]

**Status**: Done (superseded by Sprint 7.24; no new Apple `Failover` evidence requested)
**Code-side closure**: Superseded — the singleton-oriented Apple design has been demoted. Service
consumer validation now rejects `Failover` for service consumers, accepts normal Apple `Shared`
pool membership across distinct host ids, and reserves `Exclusive` for pinned member routes.
Sprint 7.24 replaces the singleton-oriented design with substrate-neutral engine pools.
**Cohort gate**: Replaced by Sprint 7.24 pool-routing validation; no new Apple `Failover` evidence is requested.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Substrate.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/Service.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `documents/architecture/daemon_topology.md`, `documents/tools/pulsar.md`
**Docs to update**: [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md), [../documents/tools/pulsar.md](../documents/tools/pulsar.md), [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Objective

Record the superseded intermediate attempt to replace the Apple host engine filesystem lock with a
single-topic Pulsar singleton. The durable target is now engine pools: `Shared` across distinct Apple
host ids for normal work distribution and `Exclusive` only for pinned host routes.

### Deliverables

- Keep the historical code-side changes visible only as retired compatibility context now that the
  Phase 4 pool-routing cleanup has removed the single-host topic surface.
- Record Apple `Failover` standby wording as removed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), not in the supported
  architecture; the single-host-topic cleanup is completed there.
- Preserve the useful invariant that pinned routes use broker-owned `Exclusive` ownership.

### Validation

- Historical unit coverage remains useful only as a migration guard for the compatibility surfaces
  tracked by Sprint 7.24 and the deletion ledger.
- No new validation should promote Apple `Failover` as a supported operator mode.

### Remaining Work

None. The superseded singleton target survives only as historical notes and ledger rows.

### Documentation Requirements

**Architecture and tools docs to update:**
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) — remove Apple singleton/failover target wording.
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — move Apple work distribution to pool topics and broker backpressure.
- [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md) — operator-facing Apple host-member pool behavior.

**Plan docs to update:**
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — completed removal row for the old `engine.lock` primary guard.

---

## Sprint 7.24: Engine Pool Assignment and Broker-Native Backpressure [Done]

**Status**: Done
**Code-side closure**: Complete for startup-time member assignment on the present Linux
outer-container lane and the Apple pinned/shared validation path — coordinator routing resolves
model ids to validated pool topics, engine daemons select a stable member id from
`daemonConfig.memberId` / `--engine-name`, normal service consumers use `Shared`, pinned routes
retain `Exclusive`, and `Failover` remains limited to coordinator-owned
dispatcher/result-bridge/model-bootstrap loops. The current Apple integration pass proves one
pinned Apple host member consumes an exact member topic through `Exclusive`, processes a
validation request, and rejects a duplicate daemon with the broker 409 conflict by launching both
daemons against an isolated `infernix service --config` substrate file. The same pass starts two
same-machine Apple host-member daemons on one isolated derived pool/model topic, observes two real
Pulsar consumers on the `Shared` subscription through the admin stats endpoint, and completes an
inference request. It also covers Apple production `demo_ui = false` route/publication assertions.
Current source additionally adds a single-host logical `Shared` backlog harness that opens two real
Pulsar WebSocket consumers on an isolated pool/model topic with service-shaped subscription names
and `receiverQueueSize=1`, holds the first request unacked, publishes a second request, and asserts
the free consumer receives that second request by decoding the request id from the Pulsar payload,
and the Apple integration lane runs that harness against the live Apple Pulsar lane.
No hot reload is implemented in this sprint; changing pool/member assignment remains a Dhall
materialization and daemon restart or rollout boundary. The Linux CPU rebuilt-image integration
pass exercises the real-cluster Linux side of this sprint: Kubernetes-observed pool placement
across the two-worker Kind topology, unique-topic `Shared` backlog/backpressure, frontend and
engine replacement cases, engine node drain, model-bootstrap failover/deduplication, anti-affinity,
lifecycle rebinding, and demo-off coordinator/engine publication.
**Cohort gate**: Closed [Wave J](cohort-validation-waves.md) — real Pulsar integration has proved
pinned duplicate-consumer rejection, same-machine Apple `Shared` coexistence, and Apple
production `demo_ui = false` assertions, plus the single-host logical `Shared`
backlog/backpressure harness. The current full Apple aggregate `./.build/infernix test all` also
passes against this state, and Linux CPU integration proves pool placement/backpressure in Kind.
Physical Apple multi-host operation is hardware-deferred proof while no second Apple host is
available.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Daemon.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Substrate.hs` (substrate decoder type = reflected schema; no tracked `.dhall`), `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: [../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md), [../documents/tools/pulsar.md](../documents/tools/pulsar.md), [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Objective

Make coordinator-to-engine routing substrate-neutral. The coordinator chooses a model/pool topic,
not a node; Pulsar assigns work to eligible members through broker backpressure; exact-host or
exact-member routes stay explicit through `Exclusive` pinned topics.

### Deliverables

- coordinator routing reads the validated engine-pool graph and publishes only to derived topics
- Apple host daemons start with a stable host id and subscribe only to assigned model-pool topics
- Linux engine workloads subscribe to the same derived pool/model topic shape as Apple members
- normal pool consumers use `Shared` with receiver permits tied to local concurrency
- pinned member consumers use `Exclusive`
- assignment is startup-time in the current supported contract. Future hot reload, if implemented,
  must use compacted desired-state records keyed by member id; assignment changes add subscriptions
  for newly assigned models, drain removed subscriptions, and mark removed model-cache entries
  evictable
- production `demo_ui = false` keeps the coordinator and engine pools while omitting only demo-only
  workloads and routes

### Validation

- unit tests for host-id/member selection and assignment-state transitions
- Pulsar integration proving two same-machine Apple host-member daemons can coexist on one derived
  `Shared` pool/model topic
- Pulsar integration proving a busy logical shared-pool Apple member stops receiving new work while
  a free logical member on the same Apple host receives new messages
- Linux CPU integration proving Kubernetes-observed pool placement and shared-subscription
  backpressure on unique derived pool/model topics
- pinned-route duplicate-consumer test proves `Exclusive` ownership on the Apple host integration
  lane
- production-shape integration proves coordinator presence with `demo_ui = false`
- regression coverage proves dispatcher, result-bridge, and model-bootstrap Failover subscriptions
  remain coordinator-only leadership mechanisms

### Remaining Work

None. Closed by [Wave J](cohort-validation-waves.md).

### Documentation Requirements

**Architecture and tools docs to update:**
- [../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md) — startup-time pool assignment, future desired-state hot reload boundaries, and cache behavior.
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) — coordinator and engine role behavior.
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — shared-pool and pinned-route subscription rules.

**Plan docs to update:**
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — completed cleanup rows for the single Apple host topic and Apple `Failover`, plus the pending cleanup row for demo-off engine-only topology.

---

## Sprint 7.25: Webapp Object-Proxy and Per-User Isolation Hardening [Done]

**Status**: Done
**Code-side closure**: Done (machine-independent). The webapp is the single mediator for
browser file I/O. `src/Infernix/Demo/Api.hs` proxies the bytes server-side over the internal MinIO
endpoint (`loadInternalMinioPresignedConfig` + the new `putMinioObjectBytes` / `getMinioObjectBytes`
helpers, matching the file's existing account-cleanup signing pattern): `handleObjectsUpload`
(`POST /api/objects/upload`) stores the request-body bytes and returns the typed `ObjectRef`;
`handleObjectsDownloadBytes` (`GET /api/objects/download?key=…`) streams the bytes with
`Content-Type` + `Content-Disposition`, authenticated by the `Authorization` header **or** the
`infernix_operator_token` cookie (for browser-issued media `src` GETs); `handleObjectsDownloadGrant`
(`POST /api/objects/download`) returns the authoritative render disposition. The
`mintAndRespond` grants, the `artifactUploadGrantPresignedUrl` / `artifactDownloadGrantPresignedUrl`
fields in `src/Infernix/Web/Contracts.hs`, and the public-endpoint `loadPresignedConfig` are deleted.
`Infernix.Objects.Layout.sanitizeFilename` neutralizes the client display name, and
`pathBelongsToUser` on the verified `sub` is the single server-side choke point for every object
operation (re-checked on the streaming GET against the client-supplied key). The browser
`web/src/Infernix/Web/ArtifactTransport.js` now does a one-leg authenticated POST upload and a
GET-by-key download; `web/src/index.html` drops the MinIO S3 operator-ribbon link. This realizes the
[../documents/architecture/object_access_doctrine.md](../documents/architecture/object_access_doctrine.md)
and the [../documents/architecture/tenant_isolation_doctrine.md](../documents/architecture/tenant_isolation_doctrine.md).
Gates green: `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`,
`infernix lint files/chart/docs/proto`, `infernix docs check` (host toolchain); `node --check` on the
rewritten JS. The web unit suite + bundle and `poetry run check-code` are unaffected by 7.25 (no
PureScript or Python changes) and run in the Wave M container batch. Delivered jointly with
[Phase 3 Sprint 3.13](phase-3-platform-services-and-edge-routing.md). **Note:** the implementation
keeps `ArtifactDownloadGrant` (minus its URL field) as the disposition carrier and uses the file-local
`putMinioObjectBytes`/`getMinioObjectBytes` signers rather than `Infernix.Objects.Upload`'s
`ObjectUploadConfig`-typed helpers, matching the established `Demo/Api.hs` MinIO-access pattern; the
contract module is `src/Infernix/Web/Contracts.hs` (there is no `src/Infernix/Demo/Contracts.hs`).
**Cohort gate**: Closed by [Wave M](cohort-validation-waves.md) — `linux-cpu` plus the
chosen `linux-gpu` accelerator.
**Implementation**: `src/Infernix/Demo/Api.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Objects/Layout.hs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/src/index.html`
**Docs to update**: `documents/architecture/object_access_doctrine.md`, `documents/architecture/tenant_isolation_doctrine.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `documents/architecture/demo_app_design.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Replace the browser-direct presigned MinIO path with a webapp object-proxy, and make one
server-side trust boundary the sole authority for every per-user object and chat operation, so
cross-user access is impossible by construction.

### Deliverables

- `Demo/Api.hs` proxies upload/download bytes over the internal MinIO endpoint
  (`loadInternalMinioPresignedConfig` plus the file-local `putMinioObjectBytes` /
  `getMinioObjectBytes` signers, not `Infernix.Objects.Upload`)
- `artifactUploadGrantPresignedUrl` and `artifactDownloadGrantPresignedUrl` removed from `Contracts.hs`
- `sanitizeFilename` applied to the client-supplied display name
- `pathBelongsToUser` plus `topicBelongsToUser` reused as the single server-side choke point

### Validation

- cross-user-403 integration: a user's JWT receives HTTP 403 on another user's object key (list /
  get / put / delete) and cannot read another user's chat context
- e2e: the browser uploads and downloads only through the webapp `/api/objects` surface, never a
  presigned MinIO URL
- [Wave M](cohort-validation-waves.md) records the `linux-cpu` plus chosen `linux-gpu` real
  per-user attestation, including the routed cross-user-403 e2e and proxied byte upload/download
  evidence.

### Remaining Work

None. Closed by [Wave M](cohort-validation-waves.md).

### Documentation Requirements

- keep `documents/architecture/object_access_doctrine.md` and
  `documents/architecture/tenant_isolation_doctrine.md` aligned with the implemented choke point
- update `documents/reference/api_surface.md` and `documents/reference/web_portal_surface.md` to
  describe the proxied `/api/objects` byte upload/download surface
- record the retired browser-direct presigned path (the `Demo/Api.hs` `mintAndRespond` grants, the
  `artifact*GrantPresignedUrl` contract fields, and the browser PUT/GET to the presign endpoint) in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

---

## Sprint 7.26: Per-User Files Navigational View [Done]

**Status**: Done
**Code-side closure**: Done (machine-independent). `src/Infernix/Demo/Api.hs` adds
`handleObjectsList` (`GET /api/objects/list`, returns the caller's objects as a JSON array of
`ObjectRef` scoped server-side to `users/<sub>/` via the existing `listMinioUserObjectKeys`) and
`handleObjectsDelete` (`DELETE /api/objects?key=…`, removes a single caller-owned object via the
existing `deleteMinioObject`); both authorize through the same `pathBelongsToUser` choke point as
Sprint 7.25 (HTTP 403 on a cross-user key). The SPA gains a Files nav tab + `files-root` view
(`web/src/index.html`, `web/src/Infernix/Web/Router.purs` `RouteFiles`): `renderFilesView` /
`fileEntryFromObjectRef` / `filesEntriesFromObjectRefs` in `web/src/Infernix/Web/Artifacts.purs`
render a flat per-user list (list / upload / download / preview / delete) reusing the artifact render
dispositions; `web/src/Infernix/Web/FilesTransport.{purs,js}` wraps the authenticated list refresh
and the delete request; `web/src/Main.purs` wires the route, transport, and refresh-after-upload.
Gates green: `cabal build all`, `cabal test infernix-haskell-style` (ormolu + hlint clean on the new
handlers), `infernix lint files/chart/docs/proto`, `infernix docs check`, and the containerized web
suite (`spago build` clean, `spago test` 71/71).
**Cohort gate**: Closed by [Wave M](cohort-validation-waves.md) — `linux-cpu` plus the
chosen `linux-gpu` accelerator.
**Implementation**: `src/Infernix/Demo/Api.hs`, `web/src/index.html`, `web/src/Infernix/Web/Router.purs`, `web/src/Infernix/Web/Artifacts.purs`, `web/src/Infernix/Web/FilesTransport.purs`, `web/src/Infernix/Web/FilesTransport.js`, `web/src/Main.purs`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/reference/api_surface.md`, `documents/architecture/demo_app_design.md`, `documents/architecture/tenant_isolation_doctrine.md`

### Objective

Give each user a navigational Files view over their own MinIO objects, prefix-scoped to
`users/<sub>/` and authorized through the Sprint 7.25 choke point, reusing the existing render
dispositions for preview.

### Deliverables

- `GET /api/objects/list` prefix-scoped to `users/<sub>/` (derived server-side)
- `DELETE /api/objects` for a single caller-owned object
- a Files nav section in the SPA (list / upload / download / preview / delete) reusing the artifact
  render dispositions

### Validation

- scoping e2e: the Files view lists only the caller's objects, and list / download / delete on
  another user's key is rejected
- [Wave M](cohort-validation-waves.md) records the `linux-cpu` plus chosen `linux-gpu` attestation

### Remaining Work

None. Closed by [Wave M](cohort-validation-waves.md).

### Documentation Requirements

- update `documents/reference/web_portal_surface.md` and `documents/reference/api_surface.md` for
  the Files view and the `list` / `delete` object endpoints
- keep `documents/architecture/tenant_isolation_doctrine.md` aligned with the prefix-scoped listing
  and deletion behavior

---

## Sprint 7.27: In-Browser MIDI/MusicXML/ZIP Rendering [Done]

**Status**: Done
**Code-side closure**: Done (machine-independent). New `ArtifactRenderDisposition`
variants `RenderMidi` / `RenderMusicXml` / `RenderZipStems` are added to
`src/Infernix/Web/Contracts.hs` (data type + `phase7Sums` so the regenerated `Generated.Contracts`
carries them), the `src/Infernix/Demo/Api.hs.renderDispositionForMime` classifier, and the
PureScript `web/src/Infernix/Web/Artifacts.purs` classifier (`dispositionFor`), `mimeFromObjectKey`
(`.zip`), the `dispositionLabel`/`dispositionClass`/`dispositionTag` helpers, and the
`renderArtifactPreview` mount nodes. `web/src/Infernix/Web/ArtifactTransport.js` renders the three
families in-browser through **dynamically-imported** FFI — `@tonejs/midi` + `smplr` (MIDI piano-roll
canvas + playback against self-hosted samples at `/samples/smplr`), `opensheetmusicdisplay`
(MusicXML/`.mxl` → SVG, code-split via dynamic `import()`), and `fflate` (ZIP-stems → inline
`<audio>`) — wired into `handleDownload`; `web/package.json` adds the runtime deps. The dynamic
imports keep the unit suite free of the runtime deps (resolved only by esbuild at bundle time). Gates
green: `cabal build all`, `cabal test infernix-unit` (disposition matrix + roundtrip extended),
`cabal test infernix-haskell-style`, `infernix lint files/chart/docs/proto`, `infernix docs check`,
and the containerized web suite (`spago build` clean, `spago test` 71/71 with the updated
`ArtifactsSpec`).
**Cohort gate**: Closed by [Wave M](cohort-validation-waves.md) — `linux-cpu` plus the
chosen `linux-gpu` accelerator. The esbuild bundle of the new deps, self-hosted smplr sample
provisioning, and in-browser render e2e (MIDI plays + piano-roll, MusicXML SVG, ZIP-stem audio) are
validated by the Wave M routed browser suite.
**Implementation**: `src/Infernix/Web/Contracts.hs`, `src/Infernix/Demo/Api.hs`, `web/src/Infernix/Web/Artifacts.purs`, `web/src/Infernix/Web/ArtifactTransport.js`, `web/package.json`
**Docs to update**: `documents/reference/web_portal_surface.md`, `documents/architecture/demo_app_design.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Render MIDI, MusicXML/`.mxl`, and ZIP-stem artifacts in the browser through new render dispositions
and self-hosted PureScript FFI, replacing the download-only fallback for those families.

### Deliverables

- new `ArtifactRenderDisposition` variants for audio/MIDI, MusicXML, and ZIP
- PureScript FFI for `fflate` (ZIP stems to inline audio), `@tonejs/midi` plus `smplr` (MIDI
  playback and piano-roll with self-hosted samples), and `opensheetmusicdisplay` (MusicXML/`.mxl` to
  SVG, code-split)
- flipped `DownloadOnly` disposition for `audio/midi`, MusicXML, and `application/zip`

### Validation

- e2e: a MIDI artifact plays and renders a piano-roll, a MusicXML/`.mxl` artifact renders SVG, and a
  ZIP stem set renders inline audio — none falls back to download-only
- [Wave M](cohort-validation-waves.md) records the `linux-cpu` plus chosen `linux-gpu` attestation

### Remaining Work

None. Closed by [Wave M](cohort-validation-waves.md).

### Documentation Requirements

- update `documents/reference/web_portal_surface.md` and `documents/architecture/demo_app_design.md`
  for the new render dispositions and in-browser MIDI/MusicXML/ZIP behavior
- record the retired `DownloadOnly` disposition for `audio/midi`, MusicXML, and `application/zip` in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

---

## Sprint 7.28: Generated Artifact Object Ownership and Result-Bridge Authorization [Done]

**Status**: Done
**Code-side closure**: Closed. The worker protobuf carries a Haskell-derived
generated-output prefix, Python adapters reject missing/invalid generated-output ownership and upload
only below that prefix, native artifact uploads use the same target instead of `native-generated/...`,
and the result bridge rejects raw or cross-user generated object refs.
**Cohort gate**: Closed by full selected `linux-gpu` plus `linux-cpu` routed real-output
validation with generated artifact families exercised end to end.
**Implementation**: `proto/infernix/runtime/inference.proto`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Objects/Layout.hs`, `python/adapters/common.py`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/architecture/object_access_doctrine.md`, `documents/architecture/tenant_isolation_doctrine.md`, `documents/engineering/object_storage.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make generated artifact object ownership derive from the authenticated user and context before work is
dispatched, so every artifact-family result is authorized through the same `users/<sub>/` prefix rule as
browser uploads and downloads.

### Deliverables

- add a typed generated output target or prefix to the worker request, derived from `userId` and
  `contextId` by Haskell code
- make Python adapters upload only to the supplied target and reject missing/invalid generated-output
  ownership data
- make native-process-runner uploads use the same supplied target instead of `native-generated/...`
- make the result bridge parse structured object refs and reject or fail closed on raw keys outside
  `users/<sub>/contexts/<ctx>/generated/`
- add tests proving generated artifacts use `users/<sub>/contexts/<ctx>/generated/` and cannot be read
  by another authenticated `sub`

### Validation

- `cabal test infernix-unit --test-options='--hide-successes'`, `cabal build
  test:infernix-integration`, `python3 -m py_compile python/adapters/common.py`,
  `cabal run exe:infernix -- test lint`, and `cabal run exe:infernix -- lint proto` exit zero
- `./bootstrap/linux-gpu.sh test` passes: Haskell style, Python `check-code`, Haskell unit, web
  contracts, full integration with every `linux-gpu` catalog row producing real output, routed
  Playwright, and the browser per-model matrix
- `./bootstrap/linux-cpu.sh build` rebuilds `infernix-linux-cpu:local`, and
  `./bootstrap/linux-cpu.sh test` passes: Haskell style, Python `check-code`, Haskell unit, web
  contracts, full integration with HA/chaos and throughput, routed Playwright, and the browser
  per-model matrix

### Remaining Work

None.

---

## Sprint 7.29: ClusterState Field Retirement and Object-Proxy Evidence [Active]

**Status**: Active — the typed transition-evidence retirement of the
`ClusterState`/`LifecycleProgress` stringly fields, the `DemoBucketsProvisioned`-gated object-proxy
routes, and the proven `.ready` sentinel gate are landed, but the
[Wave V](cohort-validation-waves.md) Apple plus `linux-cpu` sign-off was reset as current proof and
must be reproduced in [Wave Y](cohort-validation-waves.md) after Phase 1.
**Code-side closure**: closed — `cabal build all` (`-Wall -Werror`, clean),
`cabal test infernix-unit`, `cabal test infernix-haskell-style`, `infernix lint docs`, and
`poetry run check-code` all pass on the apple-silicon lane.
**Cohort gate**: closed by [Wave V](cohort-validation-waves.md) — apple-silicon plus
linux-cpu full-suite `test all` passed, and that attestation is superseded as current proof.
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`
**Blocked by**: Sprint 2.14, 4.28
**Docs to update**: `documents/architecture/managed_state_transitions.md`, and the phase's existing
engineering/reference docs

### Objective

This sprint is the Managed-State-Transition Doctrine reopen work for this phase: retire the
`clusterPresent::Bool` and `lifecyclePhase`/`lifecycleAction`/`lifecycleDetail`::`String` fields from
`ClusterState`/`LifecycleProgress`; gate the object-proxy routes on a `DemoBucketsProvisioned`
readiness value; and require a proven `.ready` sentinel for bootstrap — so each operation that acts on
a system state carries typed evidence for that state rather than an untyped flag, encoding evidence,
not hope. It generalizes the results-side realness contract to state transitions per the doctrine at
[../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md).

### Deliverables

- retire `clusterPresent::Bool` and the `lifecyclePhase`/`lifecycleAction`/`lifecycleDetail`::`String`
  fields from `ClusterState` and `LifecycleProgress` in favor of typed transition evidence. The
  stringly `LifecycleProgress` type and its `lifecycleAction` / `lifecyclePhase` / `lifecycleDetail`
  / `lifecycleHeartbeatAt` fields are gone from `src/Infernix/Types.hs`; readers (Models.hs status
  JSON, Cluster.hs monitor/status/resume) consume the typed `LifecyclePhase` and its closed
  `LifecycleTransition` through the `lifecyclePhaseOf` accessor.
  [Sprint 2.14](phase-2-kind-cluster-storage-and-lifecycle.md) already retired
  `clusterPresent :: Bool` in favour of the authoritative `clusterLifecycle`
- gate the `Demo/Api.hs` object-proxy routes on a `DemoBucketsProvisioned` readiness value returned by
  the provisioning transition rather than an ambient boolean: the `/api/objects`
  upload/download/list/delete routes take an opaque witness minted only by
  `ensureDemoBucketsWithRetry`, and `withDemoBucketsProvisioned` forces that evidence and responds
  503 when the buckets are not provisioned
- require a proven `.ready` sentinel in `Runtime/Pulsar.hs` before bootstrap-dependent work proceeds:
  the inference bootstrap retry awaits the typed `awaitModelBootstrapReady` evidence and then
  `proveModelReadySentinel`, a bounded MinIO HEAD of the sentinel, closing the
  event-without-durable-sentinel race with a typed `model_cache_bootstrap_sentinel_unproven` failure.
  `loadBootstrapPresignedConfig` is coordinator-only — it needs the cluster ConfigMap and Secret
  mounts, which the Apple **host** engine daemon does not have — so `proveModelReadySentinel` defers
  on the host, letting the retry proceed and relying on the host's own sentinel-gated hydration
  (`ensureNativeRunnerContractCacheReady` → `nativeModelReadySentinelExists`), while the coordinator
  and Linux engine pods run the real HEAD probe
- the typed `ModelBootstrapReadyEvent` carries the causal request-attempt key of the authorized
  request it answers (`readyEventRequestAttemptKey`, sourced from
  `modelBootstrapRequestAttemptKey`), and the field stays optional on decode so ready events
  retained from before the key existed still decode. A ready event identified only by model id is
  ambiguous whenever eager staging and engine recovery are in flight for the same model, so the
  adversarial deduplication check counts raw Pulsar message IDs only for that exact authorized
  attempt rather than attributing every concurrent ready event for the model to one replayed request
- `web/src/Infernix/Web/ArtifactTransport.js` updates every current artifact card matching the object
  key and stamps download readiness only after preview/render state is ready, so a download grant
  that resolves before the text-preview DOM update cannot report the card as ready early

### Validation

- `cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `infernix lint docs` exit zero, exercised on both the apple-silicon and linux-cpu lanes
- `poetry run check-code` exits zero for any Python/native change surface, on both lanes

### Remaining Work

- Reproduce the Apple plus paired `linux-cpu` cohort evidence in
  [Wave Y](cohort-validation-waves.md) after Phase 1's current-source closure. This sprint's own
  surface is landed and validated by `cabal build all`, `cabal test infernix-unit`,
  `cabal test infernix-haskell-style`, `infernix lint files/docs/proto/chart`, and
  `poetry run check-code`; no code-side work is claimed here and the remainder is validation only.

---

## Remaining Work

Reproduce the Sprint 7.29 cohort evidence. The [Wave V](cohort-validation-waves.md) attestation this
phase closed on was reset and is no longer a current proof point; nothing in this phase's own surface
is known broken, and no code-side work is claimed here. The residual is validation-only.

**Cohort gate**: [Wave Y](cohort-validation-waves.md), after Phase 1's complete current-source gates
and Apple/paired-`linux-cpu` cohorts. The former Sprint 1.20 bounded-command environment defect is
corrected and is historical context, not the current blocker.

## Closure Notes

- Sprint 7.28 closed through the full `linux-gpu` plus `linux-cpu` cohort gates.
- Sprint 7.24 closed through [Wave J](cohort-validation-waves.md): the selected
  `linux-gpu` accelerator and `linux-cpu` full-suite gates both passed against current source.
- Sprints 7.25–7.27 closed through [Wave M](cohort-validation-waves.md): the selected
  `linux-gpu` accelerator and `linux-cpu` full-suite gates both passed against current source.
- Physical Apple multi-host routing is deferred hardware proof, not open Phase 7 work.

---

## Documentation Requirements

**Engineering docs to create/update:**
- [../documents/engineering/implementation_boundaries.md](../documents/engineering/implementation_boundaries.md) — Application Library Boundary section split into frontend, coordinator daemon, and engine daemon roles; coordinator additionally owns `Infernix.Bootstrap.Models`
- [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md) — full rewrite for the supported target shape: drop `./.data/object-store/`, drop `s3://infernix-runtime/`, drop `/objects/:objectRef`; document the model-weight bucket, engine-artifact bucket, demo-object bucket, and `.ready` sentinel pattern
- [../documents/engineering/portability.md](../documents/engineering/portability.md) — row 63 rewritten in 3-role daemon vocabulary
- [../documents/engineering/k8s_storage.md](../documents/engineering/k8s_storage.md) — no daemon has a PVC; engine pod uses `emptyDir` with `sizeLimit` for model cache only; eviction enforced by adapter

**Architecture docs to create/update:**
- [../documents/architecture/engine_pool_routing.md](../documents/architecture/engine_pool_routing.md) — substrate-neutral engine-pool routing doctrine: startup-time pool assignment, `Shared` normal pools, and pinned `Exclusive` routes
- [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md) — new product-agnostic primitives doc
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — demo-specific bindings on top of the primitives doc
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) — new authoritative 3-role daemon model doc
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — durable-context surface delta and new view modules
- [../documents/architecture/runtime_modes.md](../documents/architecture/runtime_modes.md) — Service Placement rewritten in 3-role daemon vocabulary
- [../documents/architecture/overview.md](../documents/architecture/overview.md) — pointer to the new designs
- [../documents/architecture/managed_state_transitions.md](../documents/architecture/managed_state_transitions.md) — Managed State Transitions doctrine this phase now references for Sprint 7.29's typed transition-evidence work

**Development docs to create/update:**
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — new authoritative test plan
- [../documents/development/frontend_contracts.md](../documents/development/frontend_contracts.md) — new ADTs and Haskell-first logic discipline
- [../documents/development/testing_strategy.md](../documents/development/testing_strategy.md) — three validation layers cross-link
- [../documents/development/purescript_policy.md](../documents/development/purescript_policy.md) — new view modules note

**Reference docs to create/update:**
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — `/auth`, `/ws`, `/api/objects` routes, frontend termination note
- [../documents/reference/api_surface.md](../documents/reference/api_surface.md) — `/api/objects` HTTP route

**Tools docs to create/update:**
- [../documents/tools/keycloak.md](../documents/tools/keycloak.md) — new authoritative Keycloak surface
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — demo conversation and metadata topics; `inference.batch.<mode>` topic family on every substrate; new `infernix/system/model.bootstrap.request` topic with Failover subscription contract, model-scoped message key, and attempt-scoped dedup key
- [../documents/tools/minio.md](../documents/tools/minio.md) — full bucket inventory rewrite: drop `infernix-runtime` and `infernix-results`; add `infernix-models` always-on; document the `.ready` sentinel; demo artifact bucket retained

**Operations docs to update:**
- [../documents/operations/cluster_bootstrap_runbook.md](../documents/operations/cluster_bootstrap_runbook.md) — Keycloak addition note plus coordinator + engine pod inventory; expected `infernix kubectl get pvc -A` is empty; `infernix-models` bucket validation; first-use bootstrap latency note
- [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md) — coordinator + engine 3-role naming for the Apple lane; host engine daemon pool membership via stable host ids, `Shared` normal pools, and pinned `Exclusive` routes; host engine pulls weights from MinIO `infernix-models` via the same bootstrap workflow

**Development docs to create/update:**
(Already listed above; reaffirmed here that Sprint 7.7 adds bootstrap chaos cases to
`chaos_testing.md` and a per-engine MinIO smoke matrix to `demo_app_test_plan.md`.)

**Chart assets to create/update (delivered by Sprint 7.7):**
- `chart/templates/deployment-coordinator.yaml` (new)
- `chart/templates/deployment-engine.yaml` (new — `emptyDir` `model-cache` mount with `sizeLimit`)
- `chart/templates/poddisruptionbudget-coordinator.yaml` (new)
- `chart/templates/poddisruptionbudget-engine.yaml` (new)
- `chart/templates/poddisruptionbudget-demo.yaml` (new)
- `chart/templates/deployment-service.yaml` (deleted)
- `chart/templates/persistentvolumeclaim-service-data.yaml` (deleted)
- `chart/values.yaml` (drop `infernix-runtime` and `infernix-results` placeholder buckets; add `infernix-models` always-on; new `coordinator`, `engine`, `demo` HA stanzas; `engine.modelCache.sizeLimit` knob)

**Root docs to update:**
- [../README.md](../README.md) — short orientation paragraph framing the durable-context Chat surface as the supported manual-inference path; 3-role daemon naming; no PVC on any daemon; model weights eagerly staged to MinIO by the coordinator at startup (Phase 8); ephemeral `emptyDir` for engine model cache
- [README.md](README.md) — Phase 7 row in Document Index and Phase Overview
- [00-overview.md](00-overview.md) — Phase 7 in architecture baseline and dependency chain
- [system-components.md](system-components.md) — Keycloak, demo MinIO bucket, demo Pulsar topic families, new routes, coordinator + engine Deployments, new `infernix-models` bucket, new `model.bootstrap.request` topic, no-PVC daemon shape
- [development_plan_standards.md](development_plan_standards.md) — Sections K + L updated for the 3-role daemon contract, Linux anti-affinity, Apple host-id pool membership, the no-PVC posture, and MinIO + Pulsar as the only durable state
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — new Pending Removal entries for `./.data/object-store/`, the `s3://infernix-runtime/` URI scheme, the 80-char inline-payload threshold, the `/objects/:objectRef` route, and the chart-reserved `infernix-runtime` + `infernix-results` placeholder buckets; the previously-listed `persistentvolumeclaim-service-data.yaml` removal is reaffirmed and broadened to "no PVC on any daemon"

**Cross-references to add:**
- align Phase 7 entries in [README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) with
  [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md),
  [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), and
  [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — completed removal row for `engine.lock` as the primary Apple singleton primitive (superseded by stable host-id pool membership plus pinned `Exclusive` routing)
