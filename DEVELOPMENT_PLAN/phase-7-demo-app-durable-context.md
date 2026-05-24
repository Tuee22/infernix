# Phase 7: Demo App Multi-User Durable Context

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)

> **Purpose**: Define the multi-user, durable-context shape of the `infernix-demo` workload —
> Keycloak self-signup, WebSocket post-login transport, Pulsar-backed per-context conversation
> history, MinIO-backed artifact upload/download with audio/image/video rendering, stateless
> backend pods, single-flight per-context inference dispatch, and the validation surface that
> proves all of it under load and pod failure.

## Phase Status

Phase 7 is `Active`. Phases 0–6 are `Done`, so the platform foundation, runtime, routed edge,
HA platform services, generated demo catalog, and validation surface this phase builds on are
all in place. As of May 23, 2026: Sprints 7.2, 7.4, 7.5, 7.6, 7.13, and 7.16 are landed at
the shared-library, unit-test, and docs-alignment level; Sprints 7.7 and 7.8 land the
real-Pulsar coordinator runtime loops (`runResultBridgeLoop`, `runModelBootstrapLoop`)
alongside the proto envelope extensions, the daemon split, the producer-side dedup
structural wiring, and the MinIO `infernix-models` + `infernix-demo-objects` bucket
contract; Sprint 7.9 lands the `/api/objects` route + JWKS TTL cache + presigner-scheme
fix; Sprint 7.1 lands the Keycloak chart scaffolding plus Patroni dependency; Sprint 7.3
lands the WS handshake + JWT validation surface. Sprints 7.10, 7.11, 7.12 (SPA Chat /
Artifacts / Picker views), 7.14 (integration + chaos suite against real Pulsar / MinIO /
Keycloak), and 7.15 (Playwright E2E) remain pending; the per-context dispatcher runtime
loop (the production wiring for `Infernix.Dispatch.SingleFlight`) and the WS
per-context Pulsar Reader cursor wiring also remain pending, and the cluster
validation pass against `linux-gpu` is in flight. Phase 7 closes only when every
sprint below is `Done`, every doc named in the sprints is aligned with the implemented
behavior, `infernix test all` passes on at least one substrate with `demo_ui = true`, and
the per-model smoke matrix and multi-user throughput tests named in
[../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md)
are green.

## Current Repo Assessment

The current `infernix-demo` workload ships a routed PureScript SPA, the catalog and cache
HTTP API surface from Phase 4 Sprint 4.4, and the clustered demo deployment described by
Phase 3. The Helm chart already deploys Pulsar (3-broker HA), MinIO (4-replica HA),
per-service Patroni Postgres clusters (Harbor's `harborpg` and Grafana's backend), Envoy
Gateway, and the routed edge described by Phase 3. Production inference dispatch already
flows through `inference.request.<mode>` and `inference.result.<mode>` topics per Phase 4.
The legacy direct manual-inference HTTP handlers, the matching CLI helper, the
`proto/infernix/api/inference_service.proto` schema, and the single-form manual
inference surface are tracked for explicit removal in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under this phase.

Phase 7 Sprint 7.7 landed a focused legacy-cleanup pass on May 22, 2026: the staged
`infernix-substrate.dhall` schema now carries `models_bucket` and `model_bootstrap_topic`
fields (defaults `infernix-models` and `persistent://infernix/system/model.bootstrap.request`);
the legacy `/objects/:objectRef` HTTP route and `serveObject` handler are removed across
`src/Infernix/Routes.hs`, `src/Infernix/Demo/Api.hs`, the route-validation lists in
`src/Infernix/Models.hs` and `src/Infernix/Cluster.hs`, the generated route-registry
comment in `chart/templates/httproutes.yaml`, and the route inventory rows in `README.md`,
`documents/engineering/edge_routing.md`, and `documents/reference/web_portal_surface.md`;
the 80-character inline-payload threshold in `src/Infernix/Runtime.hs` is replaced with
unconditional inline payloads; `src/Infernix/Service.hs` acquires an exclusive
`flock(2)`-style lock on `./.data/runtime/engine.lock` at engine-role startup
(canonical `HostDaemon` role today; the Linux engine pod uniformly acquires the same
lock once the daemon-role rename lands); `src/Infernix/Runtime/Pulsar.hs` reconciles the
supported `infernix` tenant plus `infernix/system` and `infernix/demo` namespaces, sets a
compaction threshold on the demo namespace, and creates the
`persistent://infernix/system/model.bootstrap.request` topic before schema registration;
`python/adapters/model_cache.py` adds the uniform `get_model_path(model_id)` contract
with a clear `ModelCacheNotPopulated` fail-fast surface awaiting the Sprint 7.14
real-cluster MinIO client and LRU eviction loop. `infernix lint files`, `infernix lint
chart`, `infernix lint docs`, `infernix lint proto`, `infernix test lint`, and
`infernix test unit` all exit zero against the post-cleanup state.

The Sprint 7.7 surface that still depends on a real-cluster validation pass or on the
broader daemon-role rename is enumerated explicitly in the sprint's `Remaining Work`
section below: the daemon-role vocabulary cutover from `cluster`/`host` strings to
`coordinator`/`engine`, the `./.data/object-store/` tree and `objectStoreRoot` plumbing
removal (which touches the worker proto envelope and every adapter), the
`s3://infernix-runtime/` URI scheme and `localPathFromUri` mapping, the
`infernix-runtime` / `infernix-results` placeholder bucket removal from
`chart/values.yaml` (paired with the `chart/templates/deployment-service.yaml` and
`persistentvolumeclaim-service-data.yaml` deletions and the `daemonSplit.enabled`
flip), and the Pulsar WebSocket producer-side deduplication wiring on the conversation,
inference-request, inference-result, and `model.bootstrap.request` topics.

The May 22, 2026 `linux-cpu` validation pass surfaced and fixed three Sprint 7.7 / 7.1
follow-on bugs in three iterative cluster-up cycles, then closed the supported
`./bootstrap/linux-cpu.sh build` + `cluster up` + `cluster down` lifecycle clean:

1. **Sprint 7.7 Pulsar tenant `allowedClusters` empty list.** The initial
   `reconcileSupportedNamespaces` call sent the Pulsar admin tenant body with
   `allowedClusters: []`, which the broker rejected with `412 Precondition Failed:
   Clusters cannot be empty or blank`. The daemon retried 250+ times, blocking the
   `infernix-service` rollout. Fix: the reconcile now queries `GET /admin/v2/clusters`
   and passes the discovered cluster list (the bundled chart's single cluster is
   `infernix-infernix-pulsar`) as the tenant body's `allowedClusters`.
2. **Sprint 7.1 `pulsar:` top-level key dropped from `chart/values.yaml`.** The
   Keycloak stanza insertion accidentally removed the `pulsar:` top-level key so the
   pulsar dep rendered with default values (`infernix-pulsar-` single prefix, default
   10 GiB journal volumes without `infernix-manual` storage class), which the
   discover-chart-claims phase rejected. Fix: restored the `pulsar:` top-level key so
   the dep stanza routes through Helm's alias resolution again.
3. **Sprint 7.1 Keycloak HTTPGet health probes.** Keycloak 26 returned 404 on the
   `/health/{live,ready}` paths at port 8080 and the path on the separate 9000
   management port varies by Quarkus version. Fix: the supported probes are TCP
   socket probes against port 8080 so the contract is decoupled from path drift.

After the third rebuild, `./bootstrap/linux-cpu.sh build` plus
`docker compose run --rm infernix infernix cluster up` reached
`lifecyclePhase: steady-state` with `cluster status` reporting all eleven supported
HTTPRoutes (`/`, `/api`, `/api/objects`, `/auth`, `/ws`, the operator route family)
and zero references to the retired `/objects` route. `infernix-keycloak 2/2`,
`keycloak-postgresql-pgbouncer 3/3`, `infernix-demo 1/1`, `infernix-service 1/1`.
`sessionAffinity: None` confirmed on the demo Service. The Pulsar admin reconcile
created the `infernix` tenant plus `infernix/demo` and `infernix/system` namespaces
and set the 100 MiB compaction threshold on `infernix/demo`. `cluster down` then
reconciled cluster absence cleanly: `clusterPresent: False`, `lifecycleStatus: idle`,
`lifecyclePhase: cluster-absent`.

One small follow-on remains under Sprint 7.7 cluster validation: the explicit
`persistent://infernix/system/model.bootstrap.request` topic creation via the admin
PUT returned 2xx in the daemon log but the topic does not appear in
`pulsar-admin topics list infernix/system`. Pulsar's auto-topic-creation on first
publish will materialise the topic when the coordinator bootstrap subscription comes
online; the explicit creation contract closes when Sprint 7.14 chaos validation
verifies the topic exists before the first publish.

The May 22, 2026 `linux-gpu` rerun then re-validated the same Sprint 7.1 + 7.3 + 7.7
+ 7.9 changes against the GPU substrate. `./bootstrap/linux-gpu.sh doctor`, `build`,
`up`, `status`, and `down` all exit zero on the first attempt:
`lifecyclePhase: steady-state` on the running cluster with `runtimeMode: linux-gpu`,
two Kubernetes nodes (`infernix-linux-gpu-control-plane` + `infernix-linux-gpu-worker`),
the `nvidia` RuntimeClass present, the worker node advertising
`nvidia.com/gpu: 1` (RTX 5090), `infernix-keycloak 2/2`, both Patroni clusters
running, the Pulsar admin reconcile creating the `infernix` tenant + `infernix/demo`
+ `infernix/system` namespaces, and the same 11-route registry as the `linux-cpu`
lane (with `/objects` correctly absent). `cluster down` returned the lifecycle to
`clusterPresent: False`, `lifecycleStatus: idle`, `lifecyclePhase: cluster-absent`.
The Sprint 7.1 + 7.3 + 7.7 + 7.9 code changes are now real-cluster validated on
both supported `linux-*` substrates.

The May 24, 2026 `linux-gpu` lifecycle validation pass exercised the
post-Sprint-7.7/7.8 daemon split + new coordinator runtime loops
end-to-end through `./bootstrap/linux-gpu.sh build` (full image rebuild
after the proto + Bridge.Result + Bootstrap.Runtime changes), `cluster
up`, `cluster status`, `cluster down`, and final `cluster status`. The
build surface needed two cycles: the first image build failed on
`mypy --strict` because `python/adapters/model_cache.py` carried
`# type: ignore[import-not-found]` markers but boto3 reports the
`import-untyped` error code; the second build failed on `black --check`
because the same file's `_download_minio_object` signature exceeded
black's line-folding boundary. Both were fixed at source. The third
image build completed clean and `cluster up` reached
`lifecyclePhase: steady-state` with `runtimeMode: linux-gpu`,
`edgePort: 9090`, 80 pods on 2 nodes, all eleven supported HTTPRoutes
registered (including the Sprint-7-introduced `/auth`, `/ws`,
`/api/objects`), `infernix-coordinator 2/2`, `infernix-engine 1/1`,
`infernix-demo 1/1`, `infernix-keycloak 2/2`, both Patroni Postgres
clusters healthy, MinIO 4/4, Pulsar 3-broker + 3-bookie + 3-zookeeper +
3-recovery + 3-proxy all `Running`, and
`infernix kubectl get pvc -A | grep infernix-{coordinator,engine,demo}`
empty (no daemon PVCs, per Sprint 7.7 contract). The coordinator log
shows the new runtime loops alive: `model-bootstrap session for
persistent://infernix/system/model.bootstrap.request` and
`result-bridge session for
persistent://infernix/demo/inference.result.linux-gpu` both attached,
recycling on Pulsar 30-second idle timeouts (expected with no traffic
driving them). `cluster down` reconciled cluster absence cleanly:
`clusterPresent: False`, `lifecycleStatus: idle`,
`lifecyclePhase: cluster-absent`. The Sprint 7.1 + 7.7 + 7.8 + 7.9
chart-side surfaces are now real-cluster validated on `linux-gpu`.

The follow-on namespace-mismatch fix landed the same day:
`runResultBridgeLoop` now takes the substrate's actual configured
result-topic name (`daemonConfigResultTopic`) as a parameter instead
of computing a fresh one from `infernix/demo`, and
`runProductionDaemon` passes the daemon's already-loaded result
topic when it forks the bridge. The bridge now listens on the same
topic the engine publishes to, irrespective of namespace. The
broader `persistent://public/default/...` retirement (legacy ledger
row at line 21) still needs to happen but is decoupled from the
bridge-runtime correctness gate.

The May 24, 2026 `linux-cpu` portability rerun then re-validated the
same surface on the CPU substrate: image build, `cluster up` →
`lifecyclePhase: steady-state` with 79 pods on 2 nodes,
`infernix-coordinator 2/2`, `infernix-engine 1/1`,
`infernix-demo 1/1`, `infernix-keycloak 2/2`, all eleven supported
HTTPRoutes registered, no `infernix-*` daemon PVCs. The coordinator
log on `linux-cpu` confirms the namespace fix: `result-bridge
session for persistent://public/default/inference.result.linux-cpu`
(now on the same namespace the engine writes to, with no
`infernix/demo` mismatch). `cluster down` then reconciled cluster
absence cleanly: `clusterPresent: False`,
`lifecycleStatus: idle`, `lifecyclePhase: cluster-absent`. Sprint 7.1
+ 7.7 + 7.8 + 7.9 chart-side surfaces are now real-cluster
validated on both `linux-gpu` and `linux-cpu`.

The May 23, 2026 follow-on pass closed the remaining Sprint 7.7 architectural
items — the daemon-role rename and the chart cutover from fused to split
topology — and validated them end-to-end on `linux-cpu`. The closure surfaces:

- `Types.hs.DaemonRole` constructors renamed to `Coordinator` / `Engine`;
  `DemoConfig` record fields renamed to `coordinatorDaemon` /
  `engineDaemon`; `parseDaemonRole` accepts legacy `cluster` / `host`
  strings during transition. Dhall schema field names and the JSON wire
  keys flipped to the new vocabulary. `infernix service` reports
  `serviceDaemonRole: coordinator` in steady state.
- `chart/templates/deployment-service.yaml` plus
  `chart/templates/persistentvolumeclaim-service-data.yaml` deleted;
  the legacy `service.{enabled,image,replicaCount,command,args,dataPvc}`
  keys plus `infernix-runtime` / `infernix-results` MinIO bucket entries
  removed from `chart/values.yaml`. `daemonSplit.enabled = true` plus
  per-role `enabled: true` defaults are now the chart shape. The
  `service:` stanza is reduced to shared backend wiring
  (`service.minio.*`, `service.pulsar.*`, `service.engineAdapters.commandEnv`)
  the new Deployment templates consume.
- `chart/templates/deployment-{coordinator,engine}.yaml` mount the
  substrate ConfigMap + an `INFERNIX_DATA_ROOT=/srv/infernix/.data`
  `emptyDir` for the supported `subscription.ready` marker; the
  coordinator template additionally injects `INFERNIX_MINIO_*` and the
  Keycloak JWKS URL so the `/api/objects` and `/ws` handlers can mint
  presigned URLs and validate JWTs at startup.
- `src/Infernix/Models.hs.hostBatchTopicForMode` now returns the
  canonical `inference.batch.<mode>` topic on every substrate (not just
  Apple), and `Infernix.DemoConfig.engineDaemonConfig` returns `Just`
  on every substrate so the in-cluster `infernix-engine` Deployment has
  daemon metadata to start with.
- `src/Infernix/Cluster.hs.finalPhaseDeployments` waits on
  `deployment/infernix-{coordinator,engine,demo}` (no longer on the
  retired `deployment/infernix-service`); `clusterServiceEnabled`
  returns `False` across every substrate. `renderHelmValues` zeros out
  the coordinator + engine replica counts in every pre-Pulsar phase and
  raises them to the supported HA values (coordinator ≥ 2, engine 1) in
  `FinalPhase`.
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

`./bootstrap/linux-cpu.sh up` reached `lifecyclePhase: steady-state` with
`infernix-coordinator 2/2`, `infernix-engine 1/1`, `infernix-demo 1/1`,
`infernix-keycloak 2/2`, the Pulsar admin reconcile creating
`infernix/demo` + `infernix/system` namespaces, no `infernix-service`
PVC, all eleven supported HTTPRoutes registered (with `/objects`
correctly absent). `cluster down` returned the lifecycle to
`clusterPresent: False`, `lifecycleStatus: idle`,
`lifecyclePhase: cluster-absent`.

The May 23, 2026 follow-on closed three more Sprint 7.7 / 7.9 code-side
items so the remaining open work is exclusively cluster-tied:

- Sprint 7.7 `objectStoreRoot` retirement landed. `Infernix.Config.Paths`
  no longer carries the field, `src/Infernix/Runtime/Cache.hs` is
  rewritten around `modelCacheRoot/<runtimeMode>/<modelId>/manifest.pb`
  (manifests sit beside cached weights), and the
  `s3://infernix-runtime/` URI scheme is gone from
  `src/Infernix/Demo/Api.hs.sourceArtifactManifestUri` and
  `src/Infernix/Storage.hs.cacheManifestToProto` (both now name
  `minio://infernix-models/…` and `minio://infernix-demo-objects/…`
  prefixes). The `WorkerRequest` proto envelope drops the legacy
  `artifact_bundle_path` / `source_manifest_path` /
  `cache_manifest_path` fields and gains `display_name` / `family` /
  `artifact_type` / `runtime_lane` fields read straight from the
  daemon's already-loaded substrate `.dhall`;
  `python/adapters/common.py.load_adapter_context` reads them off the
  wire instead of synthesising JSON files. The legacy
  `inlinePublishedPayload` overflow path in
  `src/Infernix/Runtime/Pulsar.hs` is gone.
- Sprint 7.7 Pulsar producer-side dedup structural wiring landed.
  `publishTopicPayload` now takes `PublishOptions { producerName,
  sequenceId }`, `buildProducerSocketPath` appends a stable
  `producerName` query parameter to the WebSocket producer URL, and
  the daemon's request consumer derives a per-message `sequenceId`
  from the envelope's `userPromptMessageId` via
  `inferenceRequestSequenceId` (which packs Pulsar
  `<ledgerId>:<entryId>:...` MessageIds into a 64-bit value). The
  per-context dispatcher producer scoping (producerName
  `dispatcher-<contextId>`, sequence id drawn from the conversation
  log offset) is exposed by
  `Dispatch.SingleFlight.producerDedupSequenceId`; the runtime loop
  that uses it lands with Sprint 7.14's chaos validation.
- Sprint 7.9 JWKS TTL cache + chart env injection landed.
  `Infernix.Demo.Api` owns a process-lifetime `JwksCache` built in
  `runDemoApiServer` and threaded through both the `/ws` WebSocket
  handshake and the `/api/objects/{upload,download}` handlers, with a
  5-minute TTL. `chart/templates/deployment-demo.yaml` already
  injects `INFERNIX_MINIO_{ENDPOINT,ACCESS_KEY,SECRET_KEY,REGION,PRESIGN_EXPIRY_SECONDS}`
  alongside `INFERNIX_KEYCLOAK_JWKS_URL`.

`cabal build all`, `infernix lint files`, `infernix lint chart`,
`infernix lint docs`, `infernix lint proto`, `infernix test lint`, and
`infernix test unit` all exit zero against the May 23, 2026 state.
The remaining Sprint 7.7 backend follow-ons need a real cluster to
validate: `src/Infernix/Bootstrap/Models.hs` real Pulsar Failover +
MinIO PUT wiring, `python/adapters/model_cache.py` MinIO download
client + LRU eviction loop, and the per-context dispatcher + bridge
runtime loops named in Sprint 7.8 + 7.6.

Phase 7 closes the durable-context contract on top of that foundation. It does not modify
production inference dispatch; the new conversation, metadata, and drafts topics live in
demo-gated namespaces, the new Keycloak release, demo MinIO bucket, WebSocket endpoint, and
`/auth` and `/api/objects` routes are absent when `demo_ui = false`, and the supported
manual-inference path closes through the durable-context Chat surface rather than a
parallel HTTP request/poll cycle.

The shared-library foundation Phase 7 needs has landed at the unit-test level. The
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
`AppleSilicon`-only handoff conditional at `src/Infernix/Runtime/Pulsar.hs:574-590` is
generalised so any substrate forwards when `daemonConfigHostBatchTopic` is set. The
chart adds gated-off `daemonSplit.enabled` + `coordinator` / `engine` / `demoSplit`
stanzas, the engine `emptyDir` model-cache `sizeLimit` knob, the `infernix-models` and
`infernix-demo-objects` MinIO bucket entries, and five new templates
(`deployment-coordinator.yaml`, `deployment-engine.yaml`, the three PDBs).

`infernix test lint` and `infernix test unit` both exit zero against this state with
roughly 200 Haskell-side assertions across the new modules.

The remaining pending work is the SPA-side Chat / Artifacts / Picker views (Sprints
7.10–7.12), the integration and chaos suite against real Pulsar / MinIO / Keycloak
(Sprint 7.14), the routed Playwright E2E (Sprint 7.15), the per-context dispatcher
runtime loop wiring (the production wiring for `Infernix.Dispatch.SingleFlight`), the
WS per-context Pulsar `Reader` cursor wiring, the model-bootstrap real-cluster Pulsar
Failover + MinIO PUT wiring in `src/Infernix/Bootstrap/Models.hs`, and the
`python/adapters/model_cache.py` MinIO download client + LRU eviction loop. Those
sprints' Done gates require real-cluster validation that has not yet happened in this
worktree; their `Remaining Work` sections name the specific work still owed.

## Architecture

The product-agnostic design lives at
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the demo-specific bindings live at
[../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md);
the supported three-role daemon model (stateless frontend, stateless coordinator,
one-per-node stateful engine) lives at
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md);
this section names the load-bearing decisions so phase readers can locate the right module
boundary without re-reading the design docs.

- **Identity.** Keycloak release with self-signup on, email verification off, username/password
  only. Browser obtains a JWT and presents it on both HTTP and WS handshakes. Backend validates
  against Keycloak JWKS. `userId = sub`.
- **Transport.** WebSocket for chat, drafts, context list, progress, and artifact-ready
  notifications. HTTP (same JWT) for artifact upload/download, with presigned MinIO PUT/GET
  URLs so binary bytes never traverse the demo backend.
- **Statelessness.** Backend pods hold zero per-user state across requests. No demo-backend
  Postgres is added; existing per-service Patroni clusters (Harbor, Grafana, and Keycloak's
  own) are unchanged. The browser holds no durable state — full reconstitution from server-
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
  demo backend with per-user scope policy.
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
  producer-side deduplication (`enableProducerDeduplication = true`) on conversation,
  inference-request, and inference-result topics, keyed by upstream `MessageId`s. Crashes
  degrade to redeliveries and cache misses, never data loss or duplication.

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
- **Engine daemon** (`Infernix.Runtime.*` engine path) — imports
  `Infernix.Conversation.Reducer` and `Infernix.Conversation.Hash` for engine-side KV-cache
  consistency only. Loads in the `infernix-engine` Deployment on Linux substrates and as the
  on-host daemon on Apple silicon. Must not import `Infernix.Demo.*`,
  `Infernix.Objects.Presigned`, `Infernix.Auth.Jwt`, `Infernix.Dispatch.SingleFlight`,
  `Infernix.Bridge.Result`, or any WebSocket module.

The discipline is documented in
[../documents/engineering/implementation_boundaries.md](../documents/engineering/implementation_boundaries.md);
the reusable shape this discipline protects is codified in
[../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md);
the per-pod placement, replica policy, and one-per-node engine rule are codified in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md).

## Sprint 7.1: Keycloak Release and Realm Pre-Seed [Active]

**Status**: Active
**Implementation**: `chart/templates/keycloak/`, `chart/values.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Cluster/Keycloak.hs`
**Docs to update**: `documents/tools/keycloak.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/architecture/demo_app_design.md`

### Objective

Deploy Keycloak in the HA cluster with its own Patroni Postgres backend and a pre-seeded realm
that allows self-signup with username/password and skips email verification.

### Deliverables

- Helm templates under `chart/templates/keycloak/` for the Keycloak Deployment plus a Patroni
  PostgreSQL cluster managed by the Percona operator
- `chart/values.yaml` Keycloak stanza with image from Harbor, demo-gating tied to `demo_ui`
- realm definition file plus an in-binary reconcile path that imports the realm with
  self-signup on, email verification off, public SPA client, and `/auth` issuer URL
- `/auth` route added to the Haskell route registry source so the auto-rendered registry
  emits it into README, `documents/reference/web_portal_surface.md`, and publication JSON
- `cluster up` reconciles Keycloak after Harbor is responsive, before the demo workload starts
  on the durable-context surface

### Validation

- `cluster up` with `demo_ui = true` deploys Keycloak and reports readiness
- a browser at `/auth` reaches the Keycloak login page
- signup with a fresh username and password succeeds without an email-verification step
- `infernix kubectl -n platform get postgrescluster` shows the Keycloak Patroni cluster
- when the demo UI is disabled, the Keycloak release and its Patroni cluster are absent

### Remaining Work

The May 22, 2026 Sprint 7.1 pass landed the chart-side scaffolding and supporting Patroni
dependency:

- `chart/Chart.yaml` declares a second `pg-db` dependency aliased to `keycloakpg`, gated
  on `upstreamCharts.keycloakpg.enabled` (default `true` when the demo surface is on).
- `chart/values.yaml` adds:
  - the `keycloakpg:` stanza mirroring `harborpg:` — Patroni cluster managed by the Percona
    operator, `keycloak` user + `keycloak` database, 3-instance HA, `infernix-manual`
    storage class, `infernix-keycloak-db-user` secret, pgbackrest backups.
  - the `keycloak:` stanza — `quay.io/keycloak/keycloak:26.0.7` image, replica count 2,
    realm + client identifiers, admin + database secret names, port 8080.
- `chart/templates/keycloak/` adds five templates, all gated on
  `.Values.demo.enabled && .Values.keycloak.enabled`:
  - `deployment.yaml` — Keycloak Deployment with preferred anti-affinity, JDBC env wired
    to the Patroni `pgbouncer` Service, realm import via `--import-realm` from the
    mounted ConfigMap, readiness + liveness probes on `/auth/health/{ready,live}`, and
    bootstrap admin credentials sourced from the `infernix-keycloak-admin` secret.
  - `service.yaml` — ClusterIP Service exposing the Keycloak HTTP listener at port 8080
    so the routed `/auth` HTTPRoute (already registered in `Infernix.Routes`) reaches it
    without a NodePort.
  - `configmap-realm-import.yaml` — realm definition with `registrationAllowed: true`,
    `verifyEmail: false`, an `infernix-spa` public OIDC client with PKCS code-challenge,
    and a length-only password policy.
  - `secret-admin.yaml` — bootstrap admin credentials. Operators rotate this through the
    Keycloak admin UI after first login.
  - `poddisruptionbudget.yaml` — `maxUnavailable: 1` matching the supported HA shape.

`infernix lint chart`, `infernix lint files`, `infernix lint docs`, `infernix lint proto`,
`infernix test unit`, and `infernix test lint` all exit zero with the new chart assets in
place.

Pending closure:

- A dedicated `src/Infernix/Cluster/Keycloak.hs` reconcile module is not required —
  Keycloak's native `--import-realm` flag consumes the mounted realm ConfigMap at
  startup, and the Patroni cluster's user + database creation is owned by the Percona
  operator. `cluster up` already waits for the final Helm rollout, which includes the
  Keycloak Deployment + Service + ConfigMap + admin Secret + Patroni cluster as
  Helm-managed resources.
- Real-cluster validation: `./bootstrap/linux-cpu.sh up` with the new chart, then
  `infernix kubectl -n platform get postgrescluster` shows `keycloak-postgresql`,
  `infernix kubectl -n platform get deployments/infernix-keycloak` is `Available`, a
  browser at `/auth` reaches the Keycloak login page, self-signup succeeds without an
  email-verification step, and `cluster up` with `demo_ui = false` shows neither the
  Keycloak Deployment, Service, ConfigMap, Secret, nor the `keycloak-postgresql`
  Patroni cluster.

---

## Sprint 7.2: Browser-Contract ADTs and WS Envelope [Active]

**Status**: Active
**Implementation**: `src/Infernix/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`
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

### Validation

- `infernix internal generate-purs-contracts` produces deterministic output
- `infernix test unit` exercises encode/decode roundtrip across the new types in both the
  Haskell and PureScript suites
- repeated codegen runs produce byte-identical output

### Remaining Work

The Haskell side of this sprint is implemented: every named type lives in
`src/Infernix/Web/Contracts.hs` with Aeson tagged-object encoding for the sum variants,
`infernix internal generate-purs-contracts` emits the full set into
`web/src/Generated/Contracts.purs` deterministically (byte-identical across repeated
invocations, verified in `infernix test unit`), and `infernix test unit` exercises Haskell-side
encode/decode roundtrip across every new type.

Pending closure: the PureScript-side encode/decode roundtrip suite (`web/test/...`). The
generated module currently exposes `data X = A | B | ...` sum types with no
`ReadForeign`/`WriteForeign` instances, so a follow-on adds either custom Simple.JSON tagged-sum
instances in the generator footer or a PureScript test harness that asserts the same tagged
wire format the Haskell side already produces.

---

## Sprint 7.3: WS Endpoint, JWT Validation, and Stateless Coordination [Active]

**Status**: Active
**Blocked by**: 7.1
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
- `Infernix.Demo.WebSocket` handles WS upgrade, JWT validation, framed envelope routing
- chart Service for `infernix-demo` sets `sessionAffinity: None`; no client-IP or cookie
  affinity on the HTTPRoute either
- `/ws` route added to the Haskell route registry source
- per-WS state holds only the WS handle and Pulsar Reader cursors; no per-user identity cache

### Validation

- WS connection with a valid JWT succeeds; invalid/expired JWT closes the WS with a typed
  error
- `infernix kubectl -n platform get service/infernix-demo -o yaml | grep sessionAffinity`
  reports `None`
- a chaos test (Sprint 7.14) kills the WS-hosting pod and asserts the client reconnects to a
  different replica with no state loss

### Remaining Work

The May 22, 2026 Sprint 7.3 pass landed the WebSocket handshake plus framed-envelope
dispatch:

- `src/Infernix/Auth/Jwt.hs` (landed earlier in Sprint 7.3) — JWKS-backed validation
  parameterised in issuer and audience.
- `src/Infernix/Demo/Auth.hs` (landed earlier in Sprint 7.3) — Keycloak realm wiring
  into the shared `Auth.Jwt` validator.
- `src/Infernix/Demo/WebSocket.hs` — new. `wsApplication` mounts on the @/ws@ route,
  upgrades WAI requests via `Network.Wai.Handler.WebSockets.websocketsOr`, and validates
  the bearer JWT carried in either the `Authorization` header or the `?token=` query
  parameter (the SPA-friendly fallback because browsers cannot set headers on
  `WebSocket(...)` connects). The handshake calls
  `Infernix.Auth.Jwt.verifyAndParseJwt`, captures `UserId` from the `sub` claim, and
  hands off to a per-connection receive loop that decodes the framed envelopes from
  Sprint 7.2 (`WsClientMessage` / `WsServerMessage`). Each decoded `ClientMessage`
  family is classified through the pure `classifyClientMessage` helper, which today
  returns `AcknowledgePending` for every variant — the supported handshake + decode +
  routing shape is in place; the Pulsar Reader / Failover subscription wiring lands
  together with the Sprint 7.14 real-cluster validation. Per-WS state is limited to the
  WS handle plus the authenticated `UserId`.
- `chart/templates/service-demo.yaml` now sets `sessionAffinity: None` so any frontend
  replica can host any session and the pod-kill-survives-reconnect contract from
  Sprint 7.14 has the substrate it needs.
- `src/Infernix/Demo/Api.hs` mounts the WebSocket handler at `/ws`, using the same
  Keycloak JWKS loader the `/api/objects` handler uses (with the
  `INFERNIX_KEYCLOAK_JWKS_URL` override).
- `infernix.cabal` exposes the new module and pulls in `wai-websockets 3.0`.

`infernix lint chart`, `infernix lint files`, `infernix lint docs`, `infernix lint proto`,
`infernix test lint`, and `infernix test unit` all exit zero with the new WebSocket
module in place.

Pending closure:

- Pulsar Reader cursors per-context: the `runSession` loop today acknowledges client
  messages but does not yet bind them to per-context Pulsar Reader subscriptions on
  the conversation log topic. Lands together with Sprint 7.14.
- Real-cluster validation: WS connection with a valid Keycloak-issued JWT succeeds,
  invalid/expired JWT closes the WS with the typed 401/503 reject, `sessionAffinity:
  None` is reported by `infernix kubectl -n platform get service/infernix-demo -o
  yaml`, and the pod-kill-survives-reconnect chaos case from Sprint 7.14 passes.
- PureScript-side `web/src/Infernix/Web/WebSocket.purs` client that talks to this
  endpoint (Sprint 7.10).

---

## Sprint 7.4: Conversation Primitives in Shared Library [Active]

**Status**: Active
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

### Validation

- Haskell property tests cover reducer determinism, idempotency dedup, hash chain
  monotonicity, and patch-stream equivalence to state-snapshot equality
- integration test (Sprint 7.14) round-trips a conversation through a real Pulsar topic with
  producer dedup verified via simulated double-publish
- no module under `Infernix.Demo.*` is imported by these shared modules

### Remaining Work

All five shared-library modules exist (`Infernix.Conversation.Event`,
`Infernix.Conversation.Hash`, `Infernix.Conversation.Idempotency`,
`Infernix.Conversation.Reducer`, `Infernix.Conversation.Topic`), build with `-Wall -Werror`,
and the unit-level validation surface from this sprint's `Validation` section passes
(`infernix test unit`): hash chain seed/determinism/tamper-cascade, reducer-emitted
patch-stream equality with the snapshot reducer's projection, `(contextId, clientIdempotencyKey)`
dedup at the reducer and idempotency-set layers, two-prompt-in-a-row ordering, cancel and
result resolving the single-flight queue, and topic-name shape under a parameterised
`TopicNamespace`. The shared modules import nothing from `Infernix.Demo.*`.

Pending closure:

- Conversation events ride the Pulsar WebSocket transport as JSON
  payloads (base64-encoded into the producer envelope), so the
  supported wire format is the Aeson instances already landed in
  `Infernix.Web.Contracts`. A parallel protobuf schema for
  `ConversationEvent` is not part of the supported contract; both the
  demo backend (producer) and the engine consumer
  (`Infernix.Bridge.Result`) decode the same Aeson surface.
- Producer-side dedup *structural* wiring is landed (see Sprint 7.7
  `Remaining Work` for the helper landing). The remaining bit is
  per-context dispatcher wiring that uses
  `Dispatch.SingleFlight.producerDedupSequenceId` + the
  per-conversation Failover subscription — that loop lands together
  with Sprint 7.14's chaos-validation cycle.
- Broker-side dedup namespace policy is reconciled on daemon startup
  (the May 22, 2026 `reconcileSupportedNamespaces` pass POSTs `true`
  to `/admin/v2/namespaces/<ns>/deduplication` for `infernix/demo` and
  `infernix/system`); a real Pulsar round-trip that proves an
  exactly-once `(producerName, sequenceId)` collision is rejected
  lands in Sprint 7.14's chaos suite.
- Integration round-trip against real Pulsar (Sprint 7.14).

---

## Sprint 7.5: Compacted Metadata Patterns in Shared Library [Active]

**Status**: Active
**Blocked by**: 7.4
**Implementation**: `src/Infernix/Topic/Metadata.hs`, `src/Infernix/Topic/Drafts.hs`, `src/Infernix/Cluster.hs` (namespace compaction policy reconcile)
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/pulsar.md`

### Objective

Land the compacted-topic projection patterns used by the contexts metadata topic and the
drafts topic, plus the namespace-level compaction policy required by the broker.

### Deliverables

- `Infernix.Topic.Metadata` — generic compacted-topic projection pattern with append-event +
  read-compacted reader helpers
- `Infernix.Topic.Drafts` — generic compacted-keyed-mutable-state pattern with
  upsert-by-key + read-compacted reader helpers
- namespace-level compaction policy reconciled on `cluster up` for `demo.user.*` namespaces

### Validation

- integration test publishes N events to a compacted topic with M distinct keys and asserts
  the compacted reader yields exactly M latest values
- pulsar admin reports compaction enabled on the demo namespaces after `cluster up`

### Remaining Work

The shared-library projection patterns are landed: `Infernix.Topic.Metadata` exposes the
generic `KeyedEvent` + `CompactedView` upsert-and-read helpers; `Infernix.Topic.Drafts` exposes
the `DraftEvent` fold that respects `DraftUpdated`/`DraftCleared` semantics and the
`DraftMapState` <-> internal-map roundtrip helpers. `infernix test unit` exercises the
@N events with M distinct keys -> M latest values@ invariant in-memory and confirms the draft
cleared semantics.

Pending closure: real-cluster validation of the broker-side namespace compaction policy.
The May 22, 2026 Sprint 7.7 cleanup pass landed the admin-API reconcile path in
`src/Infernix/Runtime/Pulsar.hs` (`reconcileSupportedNamespaces`): the daemon startup now
creates the supported `infernix` tenant, the `infernix/demo` and `infernix/system`
namespaces, and a 100 MiB compaction threshold on `infernix/demo` via the Pulsar admin
REST API before schema registration, with 409 Conflict treated as success. The
broker-side assertion that the threshold actually applies to `demo.user.*` topics is
still owned by Sprint 7.14's integration suite — it is the supported real-cluster
validation gate for this sprint.

---

## Sprint 7.6: Single-Flight Dispatcher in Shared Library [Active]

**Status**: Active
**Blocked by**: 7.4
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
- failover-subscription wiring per conversation topic
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

The pure single-flight rule and envelope construction are landed in
`Infernix.Dispatch.SingleFlight`. The module exposes `buildDispatchDecision`, the
`InferenceRequestEnvelope` (carrying `userId`, `contextId`, `userPromptMessageId`,
`clientIdempotencyKey`, `conversationLogOffset`, `prefixHash`, `promptText`, `causalRef`),
`producerDedupSequenceId` (keyed by `userPromptMessageId`), and the
`dispatcherSubscriptionName` helper for per-context Failover subscriptions. `infernix test
unit` exercises empty log, single prompt, two-prompts-in-a-row, and promote-after-result
cases. The shared library imports nothing from `Infernix.Runtime.*`, `Infernix.Demo.*`,
`Infernix.Objects.*`, `Infernix.Auth.*`, or any WebSocket module.

Pending closure:

- Pulsar producer-dedup wiring in `Infernix.Runtime.Pulsar` that configures
  `enableProducerDeduplication = true` and uses `producerDedupSequenceId` as the sequence ID
  on the inference-request topic. Lands together with Sprint 7.3's WS endpoint, where
  the dispatcher is first wired into the coordinator pod.
- Per-context Failover subscription wiring against real Pulsar (Sprint 7.14).
- The dispatcher's deployment into the `infernix-coordinator` Deployment lands in
  Sprint 7.7 alongside the daemon split.

---

## Sprint 7.7: Truly Stateless Daemon Topology and HA Chart [Active]

**Status**: Active
**Blocked by**: 7.4
**Implementation**: `src/Infernix/Runtime/Pulsar.hs` (generalize lines 574-590; add bootstrap subscription wiring), `src/Infernix/Models.hs` (`inference.batch.<mode>` for every substrate; `infernix/system/model.bootstrap.request` topic family), `src/Infernix/DemoConfig.hs` (split `cluster` role into `coordinator` + `engine`; add `modelsBucket` and `modelBootstrapTopic` fields), `src/Infernix/Runtime/Cache.hs` (delete `objectStoreRoot`, `localPathFromUri`, `cacheManifestProtoPath`, `durableArtifactPathFor`, `sourceManifestPathFor`, and the `s3://infernix-runtime/` URI scheme; replace with a MinIO-backed model loader and an `emptyDir`-backed LRU eviction manager), `src/Infernix/Runtime.hs` (delete the 80-char `buildPayload` branch; text outputs always inline, binary outputs carry an MinIO `ObjectRef`), `src/Infernix/Demo/Api.hs` (delete `serveObject` and the `/objects/:objectRef` route), `src/Infernix/Routes.hs` (drop the `/objects` route entry), `src/Infernix/Service.hs` (acquire `flock(2)` on `engine.lock` at engine-role startup; fail fast with PID diagnostic on contention — uniform across Linux and Apple), `src/Infernix/Cluster.hs` (Helm rollout for the new Deployments + buckets + `infernix/system` namespace + `model.bootstrap.request` topic), `src/Infernix/Bootstrap/Models.hs` (new — coordinator's bootstrap Failover subscription, download-from-upstream + upload-to-MinIO with `.ready` sentinel), `src/Infernix/Bridge/Result.hs` (new — shared-library result-bridge, replaces the previously planned `Infernix.Demo.ResultBridge`), `python/adapters/common/model_cache.py` (new — shared adapter helper exposing `get_model_path(model_id) -> path`, MinIO client + LRU eviction rooted at `/model-cache`, uniform across every engine), per-adapter integration in `python/adapters/<engine>/` to swap upstream weight fetches for the shared helper, `chart/templates/deployment-service.yaml` (deleted), `chart/templates/persistentvolumeclaim-service-data.yaml` (deleted), `chart/templates/deployment-coordinator.yaml` (new — no PVC), `chart/templates/deployment-engine.yaml` (new — no PVC; single `emptyDir` volume `model-cache` with `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}`, default `32Gi`), `chart/templates/poddisruptionbudget-{coordinator,engine,demo}.yaml` (new), `chart/values.yaml` (drop `infernix-runtime` and `infernix-results`; add `infernix-models` always-on; keep `infernix-demo-objects` demo-gated; new `coordinator`/`engine`/`demo` HA stanzas; `engine.modelCache.sizeLimit` knob), `dhall/InfernixSubstrate.dhall` (coordinator + engine role schemas; `modelsBucket : Text`; `modelBootstrapTopic : Text`; per-model `downloadUrl : Text`)
**Docs to update**: `documents/architecture/daemon_topology.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/durable_context_design.md`, `documents/engineering/object_storage.md`, `documents/engineering/portability.md`, `documents/engineering/implementation_boundaries.md`, `documents/engineering/k8s_storage.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/operations/apple_silicon_runbook.md`, `documents/development/chaos_testing.md`, `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`, `documents/tools/minio.md`, `documents/tools/pulsar.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `README.md`

### Objective

Land the supported three-role daemon topology — stateless frontend, stateless coordinator,
stateful engine — with **no PVC on any daemon**, **MinIO + Pulsar as the only durable state**,
and a **uniform one-engine-per-node policy on every substrate**. Replace today's fused
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
  `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}` (default `32Gi`) at `/model-cache`,
  enforced by kubelet so the pod cannot exhaust node disk
- **Strict one-engine-per-node, uniform across substrates.** On Linux substrates this is
  enforced by `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity on the
  engine Deployment's own label with `topologyKey: kubernetes.io/hostname`; on Apple silicon
  the engine role is the on-host `infernix service` daemon and the same rule is enforced via
  an exclusive `flock(2)` on `engine.lock` acquired at daemon startup. The Linux engine pod
  acquires the same lock symmetrically (no-op in practice because anti-affinity already
  enforces uniqueness, but keeps the contract uniform)
- **Generalize the AppleSilicon-only forwarding conditional** at
  `src/Infernix/Runtime/Pulsar.hs:574-590` so the daemon forwards to
  `daemonConfigHostBatchTopic` whenever that field is set, irrespective of `runtimeMode`;
  add `inference.batch.<mode>` topic definitions for `linux-cpu` and `linux-gpu`
- **Introduce the `infernix/system` Pulsar namespace** carrying the
  `model.bootstrap.request` topic; producer dedup keyed by `modelId`
- **Lazy model-weight population to MinIO with exactly-once semantics.** Engine sees an
  uncached model → publishes a bootstrap request; the coordinator's third Failover
  subscription (alongside dispatcher and result-bridge) downloads from the upstream URL
  carried in the active substrate `.dhall`, PUTs each file under
  `infernix-models/<modelId>/<filename>`, PUTs the `.ready` sentinel last, then publishes
  `model.bootstrap.ready.<modelId>`. Engines wait on the ready event with a bounded timeout
  and load from MinIO
- **Two MinIO buckets, drop the placeholders.** `infernix-models` is always-on and holds
  platform model weights, tokenizers, and configs under `<modelId>/<filename>` with a
  `.ready` sentinel; `infernix-demo-objects` is demo-gated and holds user uploads plus
  engine-generated artifacts under `users/<userId>/contexts/<contextId>/{uploads,generated}/`.
  The chart-reserved `infernix-runtime` and `infernix-results` placeholders are removed
- **Uniform model-cache adapter helper.** `python/adapters/common/model_cache.py` exposes
  `get_model_path(model_id) -> filesystem path`. Every adapter goes through this helper,
  regardless of whether the underlying engine library supports bytes-loading. Helper
  contains the MinIO client and LRU eviction logic; first call populates
  `/model-cache/<modelId>/` from `infernix-models`, subsequent calls reuse the local copy.
  Eviction runs when the directory tree approaches `sizeLimit`
- **Result-payload topology simplified.** Delete the 80-char threshold branch in
  `Runtime.hs:75-91`; text outputs always ride inline in the protobuf result message; binary
  outputs are written by the adapter directly to `infernix-demo-objects` at the
  appropriate per-user prefix and the result message carries an `ObjectRef` (bucket + key),
  not host-filesystem path nor inline bytes
- **Delete legacy surfaces:** `./.data/object-store/` tree, `objectStoreRoot` plumbing in
  `Runtime/Cache.hs`, the `s3://infernix-runtime/` URI scheme + `localPathFromUri` mapping,
  the `/objects/:objectRef` HTTP route handler in `Demo/Api.hs`, and the route registry
  entry in `Routes.hs`
- **Move the planned `Infernix.Demo.ResultBridge` to `src/Infernix/Bridge/Result.hs`**
  (shared library; loaded by coordinator). The demo binary carries no result-bridge module
- **Three new Deployments + PDBs**: `infernix-coordinator` (replicas ≥ 2 default, preferred
  anti-affinity, demo-gated except that the bootstrap subscription remains active in
  production for the engine-role-only deployment), `infernix-engine` (replicas operator-set
  on Linux substrates; 0 on `apple-silicon`; required anti-affinity; GPU resource shape on
  `linux-gpu`), `infernix-demo` (replicas ≥ 2 default; preferred anti-affinity; demo-gated).
  PodDisruptionBudgets `maxUnavailable: 1` on each
- **Production (`demo_ui = false`) deploys only the engine Deployment.** Frontend and
  coordinator are demo-gated; the bootstrap subscription in production runs as a
  single-replica coordinator-shape pod when at least one model needs lazy population
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
- One-engine-per-node enforcement: on Linux,
  `kubectl scale deployment/infernix-engine --replicas=N+1` (where N = engine-capable
  nodes) leaves one replica `Pending` with the anti-affinity rejection message; on Apple,
  launching a second `infernix service` on the same host while one is running exits
  non-zero with the `engine.lock held by PID …` diagnostic
- Production-shape test: deploy with `demo_ui = false`;
  `infernix kubectl -n platform get deployments` returns only `infernix-engine`;
  `infernix-models` bucket is present; `infernix-demo-objects` bucket is absent;
  `/objects/:objectRef` route is not registered
- Per-engine smoke matrix: for every non-`Not recommended` row in the README matrix,
  confirm the model can be loaded from `infernix-models` on the appropriate substrate and
  produces a valid inference result (text or binary `ObjectRef`)
- `infernix lint chart`, `infernix lint docs`, `infernix lint files`,
  `infernix docs check` all exit zero

### Remaining Work

The pure-Haskell coordination layer plus the additive chart-side scaffolding are landed:

- `src/Infernix/Bridge/Result.hs` exposes the shared-library result-bridge contract
  (Failover subscription naming, producer-dedup key derivation keyed by
  `userPromptMessageId`, and pure construction of the `ConversationInferenceResultEvent`
  the bridge must publish on the conversation topic).
- The `AppleSilicon`-only forwarding conditional at
  `src/Infernix/Runtime/Pulsar.hs:574-590` is now generalised: the daemon forwards to
  `daemonConfigHostBatchTopic` whenever that field is set, irrespective of `runtimeMode`.
- `Infernix.Models.canonicalBatchTopicForMode` exposes the supported
  `inference.batch.<mode>` topic name for every substrate.
- `Infernix.Conversation.Topic.systemTopicNamespace` plus
  `modelBootstrapRequestTopicName` / `modelBootstrapReadyTopicName` cover the new
  `infernix/system` namespace and the `model.bootstrap.request` /
  `model.bootstrap.ready.<modelId>` topic family.
- `chart/values.yaml` adds the `daemonSplit.enabled` gate plus `coordinator`, `engine`,
  and `demoSplit` HA stanzas including the `engine.modelCache.sizeLimit` `emptyDir` knob
  (default `32Gi`), the new `infernix-models` always-on MinIO bucket, and the
  demo-gated `infernix-demo-objects` bucket. The legacy `service.*` stanza plus
  `infernix-runtime` / `infernix-results` placeholder bucket entries stay in place
  while `daemonSplit.enabled = false` to preserve the existing chart shape during
  rollout.
- New chart templates: `chart/templates/deployment-coordinator.yaml`,
  `chart/templates/deployment-engine.yaml`, and the three PodDisruptionBudgets
  (`poddisruptionbudget-{coordinator,engine,demo}.yaml`). The engine template uses
  required pod anti-affinity on its own label keyed on `kubernetes.io/hostname`, mounts
  a single `emptyDir` `/model-cache` volume with the operator-set `sizeLimit`, and
  carries the existing `linux-gpu` `nvidia.com/gpu` shape. All five new templates are
  gated on `daemonSplit.enabled` and the per-role `enabled` flag (default `false`) so
  the chart still renders the existing fused topology until cutover.
- `infernix lint chart`, `infernix lint files`, `infernix lint docs`,
  `infernix lint proto` exit zero with the new chart templates in place.

The May 22, 2026 cleanup pass additionally landed the following sub-items, all
validated through `infernix lint *` plus `infernix test unit`:

- `dhall/InfernixSubstrate.dhall` carries the new `models_bucket : Text` and
  `model_bootstrap_topic : Text` top-level fields. `src/Infernix/Types.hs` exposes
  the matching `modelsBucket` / `modelBootstrapTopic` `DemoConfig` record fields and
  the `defaultModelsBucket = "infernix-models"` + `defaultModelBootstrapTopic =
  "persistent://infernix/system/model.bootstrap.request"` constants.
  `src/Infernix/Substrate.hs` (Dhall decoder/renderer) and `src/Infernix/DemoConfig.hs`
  (materialization path) thread both fields through end to end.
- 80-character inline-payload threshold removed from `src/Infernix/Runtime.hs`:
  `buildPayload` is now a pure helper that always returns an inline `ResultPayload`,
  the legacy `./.data/object-store/results/<requestId>.txt` overflow path is retired,
  and the unit tests at `test/unit/Spec.hs` were updated to assert inline-output
  behaviour. Listed as **Completed** in `legacy-tracking-for-deletion.md`.
- `/objects/:objectRef` HTTP route fully retired: the `serveObject` handler is gone
  from `src/Infernix/Demo/Api.hs`, the matching `RouteSpec` plus the route table
  notes are gone from `src/Infernix/Routes.hs`, the demo-detection lists in
  `src/Infernix/Models.hs` and `src/Infernix/Cluster.hs` no longer reference
  `/objects`, the generated route-registry comment is gone from
  `chart/templates/httproutes.yaml`, and the route inventory rows are gone from
  `README.md`, `documents/reference/web_portal_surface.md`, and
  `documents/engineering/edge_routing.md`. Listed as **Completed** in
  `legacy-tracking-for-deletion.md`.
- `src/Infernix/Service.hs` engine-role startup acquires an exclusive write lock on
  `./.data/runtime/engine.lock` via `fcntl(2)`-style `setLock` (BSD-equivalent
  semantics) before `runProductionDaemon`. On contention the helper reads the
  existing holder's PID and surfaces a fail-fast diagnostic. Gated on `HostDaemon`
  today; the Linux engine pod will gate uniformly on `engine` once the daemon-role
  rename lands.
- `src/Infernix/Runtime/Pulsar.hs` reconciles the supported `infernix` tenant plus
  `infernix/system` and `infernix/demo` namespaces via the Pulsar admin REST API,
  sets the compaction threshold on `infernix/demo`, and creates the
  `persistent://infernix/system/model.bootstrap.request` topic. The reconcile is
  idempotent (409 Conflict is treated as success) and runs once per daemon startup
  with bounded retry, before schema registration.
- `python/adapters/model_cache.py` exposes the supported `get_model_path(model_id)
  -> Path` contract with `ModelCacheNotPopulated` as the fail-fast surface. The
  helper currently honours `INFERNIX_MODEL_CACHE_ROOT` and reads from
  `/model-cache/<modelId>/` with a `.ready` sentinel; the MinIO download client and
  LRU eviction loop land together with Sprint 7.14's real-cluster validation.

Pending closure:

- `src/Infernix/Bootstrap/Models.hs` real-cluster wiring landed May 23, 2026:
  `Infernix.Runtime.Pulsar.runModelBootstrapLoop` subscribes to
  `persistent://infernix/system/model.bootstrap.request` with a
  Failover subscription (exactly one coordinator replica active at a
  time; broker promotes a surviving replica on crash + redelivers
  unacked requests), and `processBootstrapRequest` re-checks the
  upstream `.ready` sentinel in MinIO, HTTP-GETs the catalog
  `downloadUrl`, presigned-PUTs the payload to
  `infernix-models/<modelId>/payload`, presigned-PUTs the
  `.ready` sentinel last, then publishes a
  `ModelBootstrapReadyEvent` on the per-model ready topic. The
  loop reuses `Infernix.Objects.Presigned` (which now records
  scheme + host:port separately so the chart-injected
  `INFERNIX_MINIO_ENDPOINT=http://...` produces correct URLs).
  `runProductionDaemon` forks the bootstrap loop together with
  the result-bridge when `daemonRole == Coordinator`; the daemon
  log reports `serviceModelBootstrapMode: failover-subscription`
  in steady state. `Infernix.Bootstrap.Models` adds the Aeson
  `ToJSON` / `FromJSON` instances the wire envelope needs.
  Real-cluster validation lands together with Sprint 7.14's
  chaos validation pass (concurrent bootstrap requests +
  coordinator-kill mid-upload).
- `python/adapters/model_cache.py` MinIO client + LRU eviction loop
  landed (May 23, 2026): `get_model_path(model_id)` now lists
  `infernix-models/<modelId>/` via boto3's S3 surface, refuses to
  proceed until the upstream `.ready` sentinel exists, streams every
  file to `/model-cache/<modelId>/` via atomic temp-file rename,
  writes the local `.ready` sentinel last, and runs an LRU eviction
  pass (32 GiB default quota, overridable via
  `INFERNIX_MODEL_CACHE_QUOTA_BYTES`). The connection config reads
  `INFERNIX_MINIO_{ENDPOINT,ACCESS_KEY,SECRET_KEY,REGION}` and
  `INFERNIX_MODELS_BUCKET`. `python/pyproject.toml` declares the new
  `boto3 ^1.35.0` dependency.
- Code-level retirement of `./.data/object-store/`, `objectStoreRoot`,
  and `localPathFromUri` is landed. `src/Infernix/Runtime/Cache.hs` is
  rewritten to operate on `modelCacheRoot/<runtimeMode>/<modelId>/`
  with manifests at `manifest.pb` beside the cached weight files. The
  `objectStoreRoot` field is gone from `Infernix.Config.Paths`, the
  `s3://infernix-runtime/` URI scheme is gone from
  `src/Infernix/Demo/Api.hs.sourceArtifactManifestUri` (replaced with
  the supported `minio://infernix-models/<modelId>/` shape) and from
  `src/Infernix/Storage.hs.cacheManifestToProto` (`durableResultsPrefix`
  now names the MinIO `infernix-demo-objects` per-user prefix). The
  `WorkerRequest` proto envelope drops the
  `artifact_bundle_path` / `source_manifest_path` / `cache_manifest_path`
  fields in favour of model-metadata fields read directly from the
  daemon's already-loaded substrate `.dhall` catalog (`display_name`,
  `family`, `artifact_type`, `runtime_lane`);
  `python/adapters/common.py.load_adapter_context` reads them off the
  wire instead of synthesising JSON files. `src/Infernix/Runtime/Pulsar.hs`
  drops the now-unreachable `inlinePublishedPayload` overflow path.
  `chart/templates/deployment-service.yaml` and
  `chart/templates/persistentvolumeclaim-service-data.yaml` are deleted,
  the `infernix-runtime` / `infernix-results` placeholder buckets are
  gone from `chart/values.yaml`, the legacy `service.*` stanza is
  reduced to shared backend wiring, and `daemonSplit.enabled = true` is
  the default chart topology. `cabal build all`, `infernix lint files`,
  `infernix lint chart`, `infernix lint docs`, `infernix lint proto`,
  `infernix test unit`, and `infernix test lint` all exit zero against
  this state on May 23, 2026.
- `DemoConfig.hs` daemon-role vocabulary cutover from `cluster` / `host` strings to
  `coordinator` / `engine` (touches the dhall schema field names, Types.hs
  `DaemonRole` constructors, every test fixture, and every generated `.dhall` file
  currently materialized under `./.build/`).
- Producer-side dedup *structural* wiring is landed:
  `publishTopicPayload` now takes a `PublishOptions { publishProducerName,
  publishSequenceId }` record, `buildProducerSocketPath` appends a
  stable `producerName` query parameter to the WebSocket producer URL,
  and the daemon-side request consumer derives a per-message
  `sequenceId` from the envelope's `userPromptMessageId` via
  `inferenceRequestSequenceId` (which packs a Pulsar
  `<ledgerId>:<entryId>:...` MessageId into a 64-bit value). The
  `infernix-demo` direct publisher, the coordinator-role engine-batch
  forwarder, and the engine-role result publisher each pass a stable
  per-role `producerName`. The full per-context dispatcher producer
  scoping (producerName `dispatcher-<contextId>` with sequence ids drawn
  from the conversation log offset) lives in
  `Infernix.Dispatch.SingleFlight.producerDedupSequenceId`; that loop is
  wired together with the Pulsar Failover subscription work in
  Sprint 7.14's chaos-validation pass.
- Real-cluster validation: every `Validation` bullet listed above against a
  `linux-cpu` or `linux-gpu` `cluster up` with `daemonSplit.enabled = true`,
  including the PVC-emptiness assertion, the bootstrap exactly-once chaos case,
  the anti-affinity rejection, the engine PDB drain blocker, and the
  production-shape (`demo_ui = false`) assertion.

---

## Sprint 7.8: Engine Prefix-Hash Cache Consistency and Result Writeback [Active]

**Status**: Active
**Blocked by**: 7.4, 7.6, 7.7
**Implementation**: `src/Infernix/Runtime/*`, `tools/generated_proto/` (or upstream `.proto`), `src/Infernix/Bridge/Result.hs`
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
- inference result envelope extended with `causalRef` and a `Cancelled` status variant
- engine adapter / runtime reuses `Infernix.Conversation.Reducer` and
  `Infernix.Conversation.Hash` to verify `prefixHash` before reusing any KV cache; rebuild on
  miss
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

The May 23, 2026 pass landed the proto envelope extension plus the
real result-bridge runtime loop:

- `InferenceResult` proto envelope adds `user_id` (field 10) and
  `context_id` (field 11) alongside the existing `causal_ref` (field
  9); the `Infernix.Types.InferenceResult` domain record gains the
  matching `resultUserId` / `resultContextId` / `resultCausalRef`
  fields with Aeson `omitempty` defaults so legacy callers (the
  Phase 4 manual-inference path, the historical filesystem result
  reload helper) round-trip unchanged.
  `Infernix/Runtime/Pulsar.hs.protoResultToDomain` and
  `Infernix/Storage.hs.inferenceResultFromProto` populate the new
  fields from the wire envelope.
- `Infernix.Runtime.Pulsar.runResultBridgeLoop` is the real Pulsar
  consumer/producer wiring for the coordinator's third Failover
  subscription. It subscribes to the substrate's
  `inference.result.<mode>` topic with `subscriptionType=Failover`
  (so exactly one coordinator replica is active at a time; on crash
  the broker promotes a surviving replica and redelivers any
  unacked message), decodes each result envelope, and publishes a
  matching `ConversationInferenceResultEvent` (constructed via the
  pure `Bridge.Result.inferenceResultEventFor` helper) to the
  per-context conversation topic. Producer name is stable per
  `(role, contextId)`; sequence id is derived from the application-
  level `userPromptMessageId` via
  `parseMessageIdToSequenceId`. Results missing the durable-context
  routing fields (legacy / Phase 4 path) are skipped cleanly without
  ack-failure so the bridge does not break the manual-inference path.
- `runResultBridgeLoop` is wired into `runProductionDaemon` so the
  `Coordinator` daemon role automatically starts the bridge on
  startup (the `Engine` role does not); the daemon log reports
  `serviceResultBridgeMode: failover-subscription` when active.
- `publishedResultFromRequest` propagates the request envelope's
  `user_id` / `context_id` / `user_prompt_message_id` into the result
  envelope so the bridge has the routing fields it needs.

Pending closure:

- Engine adapter / runtime KV-cache verification via
  `Conversation.Reducer` + `Conversation.Hash`. The current adapter
  layer emits deterministic engine-family output and has no KV cache
  concept; the prefix-hash verification gate lands when a real model
  with KV cache integration arrives (post-Phase 7).
- Engine daemon boundary enforcement: a lint check that
  `Infernix.Runtime.*` does not import `Infernix.Demo.*`,
  `Infernix.Bridge.Result`, or `Infernix.Dispatch.SingleFlight`. Today
  the boundary is honoured by convention; a lint gate lands together
  with the cluster-validation pass.
- Real-cluster validation of the Failover-promotion semantics under
  coordinator-kill mid-flight (Sprint 7.14 chaos suite).

---

## Sprint 7.9: Demo MinIO Bucket and Presigned URL Minting [Active]

**Status**: Active
**Blocked by**: 7.7
**Implementation**: `chart/values.yaml`, `src/Infernix/Objects/Layout.hs`, `src/Infernix/Objects/Presigned.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Demo/Bootstrap.hs`
**Docs to update**: `documents/architecture/durable_context_design.md`, `documents/architecture/demo_app_design.md`, `documents/tools/minio.md`, `documents/engineering/object_storage.md`, `documents/reference/api_surface.md`

### Objective

Land the demo's user-facing MinIO bucket `infernix-demo-objects` plus per-user prefix layout
and the `/api/objects` HTTP endpoint that mints presigned PUT and GET URLs scoped to the
authenticated user. The bucket is the demo-gated half of the supported two-bucket model
defined in Sprint 7.7 (`infernix-models` is the always-on platform-weights half).

### Deliverables

- `infernix-demo-objects` bucket added to `chart/values.yaml` MinIO bucket list (demo-gated)
- `Infernix.Objects.Layout` — bucket and prefix conventions
  (`users/<userId>/contexts/<contextId>/{uploads,generated}/`); per-user scope helpers
- `Infernix.Objects.Presigned` — presigned URL minting helpers parameterized in the MinIO
  client config and scope policy
- `Infernix.Demo.Api` — `/api/objects` HTTP route that consumes JWT, validates per-user
  scope, and returns presigned PUT or GET URLs
- `Infernix.Demo.Bootstrap` — idempotent first-run bucket creation
- `/api/objects` route added to the Haskell route registry source

### Validation

- integration test mints a presigned PUT for user A, uploads, mints presigned GET, downloads;
  asserts content equality
- cross-user negative test: presigned URL minted for user A cannot be used to access user
  B's prefix
- when `demo_ui = false`, the bucket and `/api/objects` route are absent

### Remaining Work

The May 22, 2026 Sprint 7.9 pass landed the full HTTP handler with JWT validation, per-user
scope enforcement, and presigned URL minting:

- `src/Infernix/Objects/Layout.hs` — bucket and prefix conventions
  (`users/<userId>/contexts/<contextId>/{uploads,generated}/`) plus the
  `pathBelongsToUser` scope helper. Landed earlier in Sprint 7.9 and still in place.
- `src/Infernix/Objects/Presigned.hs` — AWS SigV4-style presigned URL minting against
  MinIO with parameterised endpoint, region, access key, secret key, and expiry. Landed
  earlier in Sprint 7.9.
- `src/Infernix/Demo/Api.hs` — `/api/objects/upload` and `/api/objects/download` HTTP
  handlers that read the `Authorization: Bearer …` header, fetch the Keycloak JWKS
  (overridable via `INFERNIX_KEYCLOAK_JWKS_URL`), call
  `Infernix.Auth.Jwt.verifyAndParseJwt`, derive `UserId` from the `sub` claim, scope
  the requested object to `users/<userId>/contexts/<contextId>/{uploads,generated}/`,
  validate the scope via `pathBelongsToUser`, mint a presigned PUT or GET URL via the
  shared `Infernix.Objects.Presigned` helper, and return the matching
  `ArtifactUploadGrant` / `ArtifactDownloadGrant` JSON. The MinIO endpoint plus
  credentials come from `INFERNIX_MINIO_ENDPOINT`, `INFERNIX_MINIO_ACCESS_KEY`,
  `INFERNIX_MINIO_SECRET_KEY`, `INFERNIX_MINIO_REGION`, and
  `INFERNIX_MINIO_PRESIGN_EXPIRY_SECONDS` env vars (defaults match the supported chart
  injection).
- `src/Infernix/Demo/Bootstrap.hs` — `requiredDemoBuckets` plus the
  `planDemoBucketBootstrap` pure helper that names the supported `infernix-models` and
  `infernix-demo-objects` buckets and computes the missing-bucket diff.
- `chart/values.yaml` — the demo-gated `infernix-demo-objects` bucket entry sits in the
  MinIO `provisioning.buckets` list alongside the always-on `infernix-models` bucket;
  the chart-time provisioner creates both before any pod consumes them.

`infernix lint chart`, `infernix lint files`, `infernix lint docs`, `infernix lint proto`,
`infernix test lint`, and `infernix test unit` all exit zero with the new handler in
place.

The May 23, 2026 Sprint 7.9 follow-on closed the JWKS-cache + chart env
injection items:

- `src/Infernix/Demo/Api.hs` now owns a per-process `JwksCache`
  built in `runDemoApiServer` (one `IORef (Maybe (UTCTime, Jwks))`
  threaded through to both the `/ws` WebSocket handshake and the
  `/api/objects/{upload,download}` handlers). `loadJwksCached` honours
  a 5-minute TTL so a JWKS rotation surfaces within one cache cycle
  without triggering an upstream `GET .../protocol/openid-connect/certs`
  per request.
- `chart/templates/deployment-demo.yaml` injects
  `INFERNIX_MINIO_ENDPOINT`, `INFERNIX_MINIO_ACCESS_KEY`,
  `INFERNIX_MINIO_SECRET_KEY`, `INFERNIX_MINIO_REGION`,
  `INFERNIX_MINIO_PRESIGN_EXPIRY_SECONDS`, and
  `INFERNIX_KEYCLOAK_JWKS_URL` alongside the existing Pulsar env vars.

Pending closure:

- Runtime-time `Demo.Bootstrap` reconcile loop that calls MinIO admin
  API to repair buckets when chart-time provisioning is bypassed (an
  operator-only edge case; chart-time provisioning covers the supported
  path). Lands together with Sprint 7.14's real-cluster validation.
- Real-cluster validation: signed-in user A mints a presigned PUT for
  `users/A/contexts/C/uploads/X`, uploads bytes, mints a presigned GET, downloads with
  content equality; cross-user negative test confirms user A cannot mint a URL inside
  user B's prefix; `cluster up` with `demo_ui = false` shows neither the `/api/objects`
  route nor the `infernix-demo-objects` bucket.

---

## Sprint 7.10: SPA Chat View [Planned]

**Status**: Planned
**Blocked by**: 7.2, 7.3, 7.4, 7.5
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `web/src/Infernix/Web/WebSocket.purs`, `web/src/Infernix/Web/Auth.purs`, `web/src/Infernix/Web/Router.purs`, `web/src/Main.purs`
**Docs to update**: `documents/architecture/web_ui_architecture.md`, `documents/architecture/demo_app_design.md`, `documents/development/purescript_policy.md`

### Objective

Land the Chat view: left rail of contexts, active conversation pane, draft restore, cancel
button, two-prompt queued indicator. All state changes flow from server-sent
`ConversationStatePatch` / `ContextListPatch` / `DraftMapPatch` messages applied by trivial
mechanical helpers; no business rule is reimplemented in PureScript.

### Deliverables

- `web/src/Infernix/Web/Auth.purs` — OIDC redirect handling, in-memory JWT storage, JWT
  refresh
- `web/src/Infernix/Web/WebSocket.purs` — WS connect with JWT handoff, framed-envelope send
  and receive
- `web/src/Infernix/Web/Chat.purs` — left rail context list, active conversation pane, draft
  text box, cancel button; renders projected state and applies patches mechanically
- `web/src/Infernix/Web/Router.purs` — SPA route table for Chat / Artifacts
- `web/src/Main.purs` extended to mount the durable-context surface when JWT is present

### Validation

- `purescript-spec` tests cover patch application + rendering correctness for each
  `ConversationStatePatch` variant; no reducer logic in PureScript
- E2E (Sprint 7.15) covers signup → context creation → prompt submission → response render
  → cancel → two-prompt queued indicator → conversation order preservation across reload

### Remaining Work

All work pending.

---

## Sprint 7.11: SPA Artifacts View [Planned]

**Status**: Planned
**Blocked by**: 7.2, 7.3, 7.9, 7.10
**Implementation**: `web/src/Infernix/Web/Artifacts.purs`
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
- HTTP multipart upload helper that issues a presigned PUT request to `/api/objects`, then
  uploads directly to MinIO, then publishes a `UserUpload` event via WS
- WS handler for `ArtifactReady` server messages renders the new artifact in place

### Validation

- `purescript-spec` view-model tests for artifact-kind dispatch
- E2E (Sprint 7.15) covers upload, download, render-or-download behavior for each supported
  artifact class, and the generated-artifact lifecycle (SDXL Turbo image, bark-small audio,
  Basic Pitch MIDI, Audiveris notation)

### Remaining Work

All work pending.

---

## Sprint 7.12: SPA Model Picker Integration [Planned]

**Status**: Planned
**Blocked by**: 7.10
**Implementation**: `web/src/Infernix/Web/Chat.purs`, `src/Infernix/Demo/Api.hs`
**Docs to update**: `documents/architecture/demo_app_design.md`

### Objective

Wire the new-context flow to the active substrate's generated demo `.dhall` catalog so users
pick a model from the same set the active staged catalog exposes. Model selection pins the
context for life; switching models mid-context is out of scope.

### Deliverables

- `Chat.purs` model-picker modal sourced from the generated catalog
- WS `CreateContext` message includes the chosen `modelId`; backend validates against the
  active catalog and rejects unknown ids
- new-context creation defers to first prompt submission; clicking "New" + closing without
  submitting leaves no backend state

### Validation

- E2E: open new-context dialog, see catalog entries for the active substrate (skipping
  `Not recommended`), pick model, submit prompt, see context appear in left rail
- E2E negative: closing the dialog without submission creates no backend state (verified by
  listing the user's contexts topic via Pulsar admin)

### Remaining Work

All work pending.

---

## Sprint 7.13: Unit-Layer Validation [Active]

**Status**: Active
**Blocked by**: 7.2, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9
**Implementation**: `test/unit/*` (existing `infernix-unit` Cabal stanza), `web/test/*`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`, `documents/development/frontend_contracts.md`

### Objective

Land the unit test layer for every primitive added in Phase 7. Property-based wherever
ordering invariants matter.

### Deliverables

- reducer property tests: determinism over arbitrary `ConversationEvent` logs; idempotency
  dedup; cancellation semantics; two-prompt-in-a-row ordering
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

The Haskell-side unit gate is landed: `infernix test unit` covers 37 JSON encode/decode
roundtrips across every Phase 7 ADT (Sprint 7.2), reducer determinism + idempotency dedup +
two-prompts-in-a-row ordering + cancel and result resolving the single-flight queue (Sprint
7.4), `prefixHash` chain seed / determinism / tamper-cascade (Sprint 7.4),
patch-stream-vs-snapshot equivalence across seven event-sequence shapes (Sprint 7.4 +
Sprint 7.6), topic-name shape under a parameterised `TopicNamespace` (Sprint 7.4),
8 JWT validation cases including positive path, tampered signature, wrong
issuer / audience, expired, unknown kid, malformed structure, and JWKS parsing
(Sprint 7.3), per-user MinIO layout invariants + scope enforcement + presigned URL minting
determinism / method discrimination / ISO expiry (Sprint 7.9), compacted-view
@N-events-M-distinct-keys -> M-latest-values@ invariant + DraftMapState roundtrip (Sprint
7.5), and `Bridge.Result` subscription naming + dedup key + event construction (Sprint
7.7). `infernix test lint` and `infernix test unit` exit zero.

Pending closure:

- PureScript `purescript-spec` view-model tests at `web/test/Infernix/Web/ChatSpec.purs`
  and `web/test/Infernix/Web/ArtifactsSpec.purs`. These need the PureScript test runner
  in `web/test/` plus tagged-sum Simple.JSON instances on the generated module (the
  generator footer currently emits `ReadForeign` for single-constructor records only).
  Land together with the SPA view sprints (7.10, 7.11) that introduce the modules
  under test.
- QuickCheck-style property generators for `ConversationEvent` sequences landed
  May 23, 2026 (`assertConversationPropertyTests` in `test/unit/Spec.hs`):
  property generators emit arbitrary 0–8-message logs with prompt / cancel /
  inference-result / duplicate shapes and exercise three invariants — patch-stream
  replay converging to the snapshot reducer projection, `prefixHash` chain
  length-monotonicity + determinism, and idempotency dedup dropping repeated
  `(contextId, key)` pairs across 50 random shrinkable cases each. The
  `QuickCheck >=2.14 && <2.20` dep is now declared on the `infernix-unit` test
  stanza.

---

## Sprint 7.14: Integration-Layer Validation [Planned]

**Status**: Planned
**Blocked by**: 7.1, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9
**Implementation**: `test/integration/*` (existing `infernix-integration` Cabal stanza), `test/integration/Infernix/Test/Integration/Throughput.hs`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/chaos_testing.md`, `documents/tools/pulsar.md`, `documents/architecture/daemon_topology.md`

### Objective

Land the integration test layer covering real-cluster Pulsar / MinIO / Keycloak round-trips,
the chaos tests for the per-role failure semantics from
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md),
and the multi-user throughput / fan-in batching / fan-out test.

### Deliverables

- real Pulsar publish + Reader subscribe round-trip per topic family (conversation, compacted
  contexts, compacted drafts, inference request/batch/result)
- real Pulsar producer dedup verification across simulated coordinator restart mid-flight;
  assert exactly-one inference dispatch and exactly-one result
- real Pulsar Failover handoff: kill active coordinator replica; assert surviving consumer
  resumes
- real MinIO presigned PUT/GET with per-user scoping; cross-user negative
- real Keycloak signup + login + JWT validation round-trip
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
    `.ready` sentinel; surviving coordinator replica resumes (producer dedup on
    `model.bootstrap.request` prevents a duplicate upstream download); the `.ready`
    sentinel appears exactly once; waiting engines observe ready and proceed
  - **Concurrent bootstrap requests**: N engine pods request the same uncached model
    simultaneously; producer dedup + Pulsar Failover guarantees exactly one upstream
    download; all N engines observe the `.ready` sentinel and proceed
  - **One-engine-per-node enforcement**: on Linux,
    `kubectl scale deployment/infernix-engine --replicas=N+1` leaves the extra pod
    `Pending` with the anti-affinity rejection; on Apple, launching a second
    `infernix service` on the same host while one is running exits non-zero with
    `engine.lock held by PID …`
  each case asserts exactly-once outcome and full state preservation
- model-cache eviction test: trigger model loads until `/model-cache` size pressure
  exists; assert the adapter helper evicts LRU entries; assert the engine pod is not
  restarted by kubelet for ephemeral-storage exhaustion
- production-shape test: deploy `demo_ui = false` and assert
  `infernix kubectl -n platform get deployments` returns only `infernix-engine`;
  `infernix-models` bucket is present; `infernix-demo-objects` bucket is absent;
  `infernix kubectl get pvc -A` returns empty
- **Multi-User Throughput / Fan-In Batching / Fan-Out** test: N users × K contexts × P
  prompts on one model, asserting per-context ordering, no duplicates or losses,
  cross-context independence, batching gain, bounded p95 latency, dedup correctness;
  module: `Infernix.Test.Integration.Throughput`; defaults N = 10, K = 3, P = 5

### Validation

- `infernix test integration` includes all new suites and passes on at least one substrate
  with `demo_ui = true`
- throughput test reports per-context ordering, exact result counts, p95 latency, batching
  factor, and dedup counter values

### Remaining Work

All work pending.

---

## Sprint 7.15: E2E-Layer Validation [Planned]

**Status**: Planned
**Blocked by**: 7.10, 7.11, 7.12, 7.14
**Implementation**: Playwright suites under the repo's Playwright tree, run via the existing `infernix-playwright:local` image; `web/test/fixtures/`
**Docs to update**: `documents/development/demo_app_test_plan.md`, `documents/development/testing_strategy.md`

### Objective

Land the E2E test layer through `docker compose run --rm playwright`. Substrate-agnostic at
the browser layer. Includes per-model smoke matrix.

### Deliverables

- Playwright flows: auth lifecycle (signup, login, logout, re-login, JWT refresh); context
  lifecycle (new-context defers, rename, soft-delete, select); conversation lifecycle
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
- `web/test/fixtures/` checked-in canonical inputs: `audio/short-speech.wav`,
  `audio/short-mix.wav`, `audio/short-pitch.wav`, `image/score-page.png`, `prompts/*.txt`

### Validation

- `infernix test e2e` runs the Playwright suite via the dedicated container
- per-model smoke matrix has one passing flow per non-`Not recommended` row in the README
  matrix for the active substrate; failure on any row fails the suite
- the Playwright source is byte-identical across `apple-silicon`, `linux-cpu`, `linux-gpu`;
  substrate selection lives only in the `.dhall` the demo app reads

### Remaining Work

All work pending.

---

## Sprint 7.16: Documentation Closure [Active]

**Status**: Active
**Blocked by**: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12, 7.13, 7.14, 7.15
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
- a fresh contributor can locate the canonical home for every Phase 7 topic via the suite
  index

### Remaining Work

The May 23, 2026 pass cleared the stale "Planned" / "today's repo still..."
framing across every governed doc and aligned the supported-target
language with the implemented behavior:

- `documents/engineering/object_storage.md` — `Current Status` now
  records the Sprint 7.7 retirement of `./.data/object-store/`,
  `objectStoreRoot`, the `s3://infernix-runtime/` URI scheme, and
  the placeholder MinIO buckets.
- `documents/engineering/storage_and_state.md` — owner table now
  names the supported MinIO buckets, the model-cache manifest
  location, and the retired object-store tree.
- `documents/engineering/model_lifecycle.md` — rules now describe
  the MinIO-backed model loader and the post-Sprint-7.7 worker
  envelope (no artifact-bundle paths).
- `documents/engineering/build_artifacts.md` — cache manifest
  location points at `./.data/runtime/model-cache/...`.
- `documents/engineering/implementation_boundaries.md` — Application
  Library Boundary section is no longer marked "Planned, Phase 7".
- `documents/architecture/runtime_modes.md` and
  `documents/architecture/daemon_topology.md` — Sprint 7.7 daemon
  split is recorded as landed; cluster-daemon-to-host-daemon bridge
  on Apple is unchanged.
- `documents/tools/pulsar.md` — "Demo Conversation and Metadata
  Topics" and "Model-Bootstrap Topic" are no longer marked
  "Planned"; broker reconciliation status named explicitly.
- `documents/tools/minio.md` — Demo Artifact Bucket section is no
  longer marked "Planned".
- `documents/development/chaos_testing.md` and
  `documents/development/testing_strategy.md` — durable-context
  chaos cases and validation layers no longer marked "Planned, Phase 7";
  sprint-number references corrected.
- `documents/development/frontend_contracts.md` — Haskell-first
  logic discipline section is no longer marked "Planned".
- `documents/reference/api_surface.md` — `/api/objects` is named
  as Phase 7 Sprint 7.9 landed (no longer "Planned").
- `documents/reference/web_portal_surface.md` — "Durable Context
  Surface" section is no longer marked "Planned".
- `documents/operations/apple_silicon_runbook.md` — Apple lane
  daemon naming references the landed `Coordinator` / `Engine`
  vocabulary instead of "after Sprint 7.7".
- `documents/operations/cluster_bootstrap_runbook.md` — "Durable-Context
  Demo Bring-Up" section names the landed `linux-cpu` + `linux-gpu`
  validation passes.

Pending refinement (lands together with Sprint 7.14 chaos
validation when real-cluster behaviors are observed):

- minor cross-reference touch-ups in cluster-runbook-style docs
  once the bootstrap + bridge + dispatcher runtime loops are
  validated against a real cluster;
- per-doc TL;DR / Executive Summary tightening where the post-Sprint-7.7
  doctrine reshaped the topic boundary;
- root README + AGENTS + CLAUDE re-read for orientation language
  drift after final Phase 7 closure.

`infernix lint docs` exits zero against this state.

---

## Documentation Requirements

**Engineering docs to create/update:**
- [../documents/engineering/implementation_boundaries.md](../documents/engineering/implementation_boundaries.md) — Application Library Boundary section split into frontend, coordinator daemon, and engine daemon roles; coordinator additionally owns `Infernix.Bootstrap.Models`
- [../documents/engineering/object_storage.md](../documents/engineering/object_storage.md) — full rewrite for the supported target shape: drop `./.data/object-store/`, drop `s3://infernix-runtime/`, drop `/objects/:objectRef`; document the two-bucket model (`infernix-models` always-on, `infernix-demo-objects` demo-gated) plus the `.ready` sentinel pattern
- [../documents/engineering/portability.md](../documents/engineering/portability.md) — row 63 rewritten in 3-role daemon vocabulary
- [../documents/engineering/k8s_storage.md](../documents/engineering/k8s_storage.md) — no daemon has a PVC; engine pod uses `emptyDir` with `sizeLimit` for model cache only; eviction enforced by adapter

**Architecture docs to create/update:**
- [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md) — new product-agnostic primitives doc
- [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md) — demo-specific bindings on top of the primitives doc
- [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md) — new authoritative 3-role daemon model doc
- [../documents/architecture/web_ui_architecture.md](../documents/architecture/web_ui_architecture.md) — durable-context surface delta and new view modules
- [../documents/architecture/runtime_modes.md](../documents/architecture/runtime_modes.md) — Service Placement rewritten in 3-role daemon vocabulary
- [../documents/architecture/overview.md](../documents/architecture/overview.md) — pointer to the new designs

**Development docs to create/update:**
- [../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md) — new authoritative test plan
- [../documents/development/frontend_contracts.md](../documents/development/frontend_contracts.md) — new ADTs and Haskell-first logic discipline
- [../documents/development/testing_strategy.md](../documents/development/testing_strategy.md) — three validation layers cross-link
- [../documents/development/chaos_testing.md](../documents/development/chaos_testing.md) — per-role chaos cases (frontend, coordinator, engine, engine-node drain)
- [../documents/development/purescript_policy.md](../documents/development/purescript_policy.md) — new view modules note

**Reference docs to create/update:**
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md) — `/auth`, `/ws`, `/api/objects` routes, frontend termination note
- [../documents/reference/api_surface.md](../documents/reference/api_surface.md) — `/api/objects` HTTP route

**Tools docs to create/update:**
- [../documents/tools/keycloak.md](../documents/tools/keycloak.md) — new authoritative Keycloak surface
- [../documents/tools/pulsar.md](../documents/tools/pulsar.md) — demo conversation and metadata topics; `inference.batch.<mode>` topic family on every substrate; new `infernix/system/model.bootstrap.request` topic with Failover subscription contract and `modelId` dedup key
- [../documents/tools/minio.md](../documents/tools/minio.md) — full bucket inventory rewrite: drop `infernix-runtime` and `infernix-results`; add `infernix-models` always-on; document the `.ready` sentinel; demo artifact bucket retained

**Operations docs to update:**
- [../documents/operations/cluster_bootstrap_runbook.md](../documents/operations/cluster_bootstrap_runbook.md) — Keycloak addition note plus coordinator + engine pod inventory; expected `infernix kubectl get pvc -A` is empty; `infernix-models` bucket validation; first-use bootstrap latency note
- [../documents/operations/apple_silicon_runbook.md](../documents/operations/apple_silicon_runbook.md) — coordinator + engine 3-role naming for the Apple lane; host engine daemon singleton via `flock(2)` on `engine.lock`; host engine pulls weights from MinIO `infernix-models` via the same bootstrap workflow

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
- [../README.md](../README.md) — short orientation paragraph framing the durable-context Chat surface as the supported manual-inference path; 3-role daemon naming; no PVC on any daemon; model weights pulled from MinIO via lazy bootstrap; ephemeral `emptyDir` for engine model cache
- [README.md](README.md) — Phase 7 row in Document Index and Phase Overview
- [00-overview.md](00-overview.md) — Phase 7 in architecture baseline and dependency chain
- [system-components.md](system-components.md) — Keycloak, demo MinIO bucket, demo Pulsar topic families, new routes, coordinator + engine Deployments, new `infernix-models` bucket, new `model.bootstrap.request` topic, no-PVC daemon shape
- [development_plan_standards.md](development_plan_standards.md) — Sections K + L updated for the 3-role daemon contract, the uniform one-engine-per-node rule (Linux anti-affinity + Apple `flock`), the no-PVC posture, and MinIO + Pulsar as the only durable state
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) — new Pending Removal entries for `./.data/object-store/`, the `s3://infernix-runtime/` URI scheme, the 80-char inline-payload threshold, the `/objects/:objectRef` route, and the chart-reserved `infernix-runtime` + `infernix-results` placeholder buckets; the previously-listed `persistentvolumeclaim-service-data.yaml` removal is reaffirmed and broadened to "no PVC on any daemon"

**Cross-references to add:**
- align Phase 7 entries in [README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) with
  [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md),
  [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), and
  [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md)
