# Phase 7: Demo App Multi-User Durable Context

**Status**: Done (Sprints 7.1-7.18 are `Done`. The process-local runtime KV-cache path is wired through `Infernix.Runtime.KVCache`, `executeInferenceWithKVCache`, the native worker harness, filesystem-topic drain, and WebSocket Pulsar consumption; daemon role orchestration lives in `Infernix.Runtime.Daemon`. The integration suite covers durable dispatcher/result writeback, frontend/coordinator/engine pod replacement, engine node drain, model-bootstrap deduplication, Linux engine anti-affinity, compact multi-user durable prompt throughput, platform recovery, production-shape deployment, and clean teardown. Apple cohort gates closed in [Wave A](cohort-validation-waves.md), [Wave A.1](cohort-validation-waves.md), [Wave A.2](cohort-validation-waves.md), and [Wave A.3](cohort-validation-waves.md); native `linux-cpu` and `linux-gpu` full-suite cohort validation closed in [Wave C](cohort-validation-waves.md).)
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/durable_context_design.md](../documents/architecture/durable_context_design.md), [../documents/architecture/demo_app_design.md](../documents/architecture/demo_app_design.md), [../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md)

> **Purpose**: Define the multi-user, durable-context shape of the `infernix-demo` workload —
> Keycloak self-signup, WebSocket post-login transport, Pulsar-backed per-context conversation
> history, MinIO-backed artifact upload/download with audio/image/video rendering, stateless
> backend pods, single-flight per-context inference dispatch, and the validation surface that
> proves all of it under load and pod failure.

## Phase Status

Phase 7 is `Done`.

Code-side closure: Sprints 7.1–7.17 are code-side closed covering the full
daemon-split topology (stateless `infernix-demo` frontend, two-replica stateless
`infernix-coordinator` with per-context dispatcher / result-bridge / model-bootstrap loops,
one-per-node `infernix-engine` with KV cache), the durable-context schema (per-conversation
Pulsar log topic, compacted per-user contexts + drafts topics, `infernix-models` and
`infernix-demo-objects` MinIO buckets, `/api/objects` presigner with JWKS TTL cache), and the
browser SPA (Keycloak PKCE auth + refresh-token re-auth, durable-context Chat with WebSocket
transport, Artifacts view with bounded text/JSON preview + inline media + browser-native PDF +
download-only grants, draft sync + cancel + queued-prompt accounting, WebSocket reconnect +
draft restoration). Sprint 7.14 is code-side closed for the WebSocket-to-Pulsar publisher
wiring, the coordinator-to-engine handoff contract, the real Pulsar Reader roundtrip coverage
for conversation/contexts/drafts/bootstrap-ready topic families, producer-dedup validation,
and the non-chaos dispatcher + result-bridge durable prompt roundtrip. Sprint 7.8 now
wires a process-local `EngineKVCache` through the engine daemon process and moves
daemon role orchestration into `Infernix.Runtime.Daemon`; `Infernix.Runtime.Pulsar`
remains the shared Pulsar transport and runtime-loop module. The Sprint 7.14
Linux-owned chaos/throughput block implemented the recorded cohort validation in [Wave C](cohort-validation-waves.md),
covering frontend/coordinator/engine pod replacement, engine node drain, model-bootstrap
deduplication, Linux engine anti-affinity, and compact multi-user durable prompt throughput.
The recorded validation residual sweep adds runtime bucket repair, deployed wrong-realm Keycloak token
rejection for `/api/objects` and `/ws`, throughput matrix parameterization, and extracted
Playwright artifact fixtures. Those specific changes passed the rebuilt-image `linux-gpu` full
gate on the recorded cohort validation against image digest
`sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b` and the rebuilt-image
`linux-cpu` full gate on the recorded cohort validation against image digest
`sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`. The CPU residual run
passed style/Python/unit/web-unit gates, full integration, and routed Playwright E2E (7/7).
The recorded validation mounted Linux CPU validation against the Sprint 7.8 worktree passed
`cabal build all`, `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
`cabal test infernix-integration`.

Validation closure: tracked by [cohort-validation-waves.md](cohort-validation-waves.md).
Apple cohort closed in [Wave A](cohort-validation-waves.md) (durable-context prompt roundtrip
PASS + 5/6 e2e PASS), [Wave A.1](cohort-validation-waves.md) (artifact-upload submit-race fix
→ 6/6 e2e PASS), [Wave A.2](cohort-validation-waves.md) (per-model browser smoke matrix
→ 7/7 e2e PASS exercising every demo-config catalog model), and
[Wave A.3](cohort-validation-waves.md) (Apple `engine.lock` enforcement chaos case). CUDA
Linux cohort closure closed in [Wave C](cohort-validation-waves.md): the native `linux-cpu`
full-suite gate passed on the recorded cohort validation, and the real-hardware `linux-gpu` full-suite gate passed
on the recorded cohort validation. Wave C covers the LinuxCpu integration chaos block + the multi-user throughput
suite. The rebuilt-image `linux-cpu` residual full-suite gate passed on the recorded cohort validation after Wave D.
Historical validation proof points are inventoried in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) under "Historical Validation
Evidence"; the underlying contracts they exercised still describe supported behavior.

Phase 7 is closed because every sprint below is `Done`, the governed docs named in the sprints
are aligned with the implemented behavior, `infernix test all` has passed on both Linux
substrates in the recorded cohort gates, and the per-model smoke matrix plus multi-user
throughput tests named in
[../documents/development/demo_app_test_plan.md](../documents/development/demo_app_test_plan.md)
are green.

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

Phase 7 Sprint 7.7 implemented a focused prior-cleanup pass on the recorded cohort validation: the staged
`infernix-substrate.dhall` schema now carries `models_bucket` and `model_bootstrap_topic`
fields (defaults `infernix-models` and `persistent://infernix/system/model.bootstrap.request`);
the prior `/objects/:objectRef` HTTP route and `serveObject` handler are removed across
`src/Infernix/Routes.hs`, `src/Infernix/Demo/Api.hs`, the route-validation lists in
`src/Infernix/Models.hs` and `src/Infernix/Cluster.hs`, the generated route-registry
comment in `chart/templates/httproutes.yaml`, and the route inventory rows in `README.md`,
`documents/engineering/edge_routing.md`, and `documents/reference/web_portal_surface.md`;
the 80-character inline-payload threshold in `src/Infernix/Runtime.hs` is replaced with
unconditional inline payloads; `src/Infernix/Service.hs` acquires an exclusive
`flock(2)`-style lock on `./.data/runtime/engine.lock` at engine-role startup
(the `Engine` daemon role and Linux engine pod uniformly acquire the same lock);
`src/Infernix/Runtime/Pulsar.hs` reconciles the
supported `infernix` tenant plus `infernix/system` and `infernix/demo` namespaces, sets a
compaction threshold on the demo namespace, and creates the
`persistent://infernix/system/model.bootstrap.request` topic before schema registration;
`python/adapters/model_cache.py` adds the uniform `get_model_path(model_id)` contract
with a clear `ModelCacheNotPopulated` fail-fast surface backed by the Sprint 7.14
real-cluster MinIO client and LRU eviction loop. `infernix lint files`, `infernix lint
chart`, `infernix lint docs`, `infernix lint proto`, `infernix test lint`, and
`infernix test unit` all exit zero against the post-cleanup state.

The Sprint 7.7 follow-on surface originally depended on real-cluster validation and the
broader daemon-role rename. Those items are now closed by later Phase 7 sprints: the daemon-role
vocabulary is `coordinator` / `engine`, the prior object-store tree and placeholder buckets are
gone, MinIO-backed model and artifact paths are the supported storage contract, the prior fused
service Deployment is removed, and Pulsar producer-side deduplication is wired on the durable demo
topic families.

The recorded validation `linux-cpu` validation pass surfaced and fixed three Sprint 7.7 / 7.1
follow-on bugs in three iterative cluster-up cycles, then closed the supported
`./bootstrap/linux-cpu.sh build` + `cluster up` + `cluster down` lifecycle clean:

1. **Sprint 7.7 Pulsar tenant `allowedClusters` empty list.** The initial
   `reconcileSupportedNamespaces` call sent the Pulsar admin tenant body with
   `allowedClusters: []`, which the broker rejected with `412 Precondition Failed:
   Clusters cannot be empty or blank`. The daemon retried 250+ times, blocking the
   then-current `infernix-service` rollout. Fix: the reconcile now queries `GET /admin/v2/clusters`
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
and zero references to the prior `/objects` route. `infernix-keycloak 2/2`,
`keycloak-postgresql-pgbouncer 3/3`, `infernix-demo 1/1`, and, in the fused topology at that point,
`infernix-service 1/1`.
`sessionAffinity: None` confirmed on the demo Service. The Pulsar admin reconcile
created the `infernix` tenant plus `infernix/demo` and `infernix/system` namespaces
and set the 100 MiB compaction threshold on `infernix/demo`. `cluster down` then
reconciled cluster absence cleanly: `clusterPresent: False`, `lifecycleStatus: idle`,
`lifecyclePhase: cluster-absent`.

The earlier Sprint 7.7 model-bootstrap topic residual is closed. Sprint 7.14 and Wave C validated
model-bootstrap request and ready-event behavior through real Pulsar, including
coordinator-replacement deduplication before first publish.

The recorded validation `linux-gpu` rerun then re-validated the same Sprint 7.1 + 7.3 + 7.7
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

The recorded validation `linux-gpu` lifecycle validation pass exercised the
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

The follow-on namespace-mismatch fix implemented the same day:
`runResultBridgeLoop` now takes the substrate's actual configured
result-topic name (`daemonConfigResultTopic`) as a parameter instead
of computing a fresh one from `infernix/demo`, and
`runProductionDaemon` passes the daemon's already-loaded result
topic when it forks the bridge. The bridge now listens on the same
topic the engine publishes to, irrespective of namespace. The
broader `persistent://public/default/...` retirement (prior ledger
row at line 21) still needs to happen but is decoupled from the
bridge-runtime correctness gate.

The recorded validation `linux-cpu` portability rerun then re-validated the
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

The recorded validation follow-on pass closed the remaining Sprint 7.7 architectural
items — the daemon-role rename and the chart cutover from fused to split
topology — and validated them end-to-end on `linux-cpu`. The closure surfaces:

- `Types.hs.DaemonRole` constructors updated to `Coordinator` / `Engine`;
  `DemoConfig` record fields updated to `coordinatorDaemon` /
  `engineDaemon`; `parseDaemonRole` accepts prior `cluster` / `host`
  strings during transition. Dhall schema field names and the JSON wire
  keys flipped to the new vocabulary. `infernix service` reports
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
- `src/Infernix/Models.hs.hostBatchTopicForMode` now returns the
  canonical `inference.batch.<mode>` topic on every substrate (not just
  Apple), and `Infernix.DemoConfig.engineDaemonConfig` returns `Just`
  on every substrate so the in-cluster `infernix-engine` Deployment has
  daemon metadata to start with.
- `src/Infernix/Cluster.hs.finalPhaseDeployments` waits on
  `deployment/infernix-engine` in every final deployment and adds the
  demo-gated `deployment/infernix-{coordinator,demo,keycloak}` only
  when `demo_ui = true` (no longer on the prior
  `deployment/infernix-service`); `clusterServiceEnabled` returns
  `False` across every substrate. `renderHelmValues` zeros out the
  coordinator + engine replica counts in every pre-Pulsar phase, raises
  them to the supported demo-on values (coordinator ≥ 2, engine 1) in
  `FinalPhase`, and sets `coordinator.enabled = false` when
  `demo_ui = false`.
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

The recorded validation follow-on closed three more Sprint 7.7 / 7.9 code-side
items so the remaining validation was exclusively cluster-tied:

- Sprint 7.7 `objectStoreRoot` retirement implemented. `Infernix.Config.Paths`
  no longer carries the field, `src/Infernix/Runtime/Cache.hs` is
  rewritten around `modelCacheRoot/<runtimeMode>/<modelId>/manifest.pb`
  (manifests sit beside cached weights), and the
  `s3://infernix-runtime/` URI scheme is gone from
  `src/Infernix/Demo/Api.hs.sourceArtifactManifestUri` and
  `src/Infernix/Storage.hs.cacheManifestToProto` (both now name
  `minio://infernix-models/…` and `minio://infernix-demo-objects/…`
  prefixes). The `WorkerRequest` proto envelope drops the prior
  `artifact_bundle_path` / `source_manifest_path` /
  `cache_manifest_path` fields and gains `display_name` / `family` /
  `artifact_type` / `runtime_lane` fields read straight from the
  daemon's already-loaded substrate `.dhall`;
  `python/adapters/common.py.load_adapter_context` reads them off the
  wire instead of synthesising JSON files. The prior
  `inlinePublishedPayload` overflow path in
  `src/Infernix/Runtime/Pulsar.hs` is gone.
- Sprint 7.7 Pulsar producer-side dedup structural wiring implemented.
  `publishTopicPayload` now takes `PublishOptions { producerName,
  sequenceId }`, `buildProducerSocketPath` appends stable
  `producerName` plus optional `initialSequenceId` query parameters to
  the WebSocket producer URL, and the daemon's request consumer derives a per-message `sequenceId`
  from the envelope's `userPromptMessageId` via
  `inferenceRequestSequenceId` (which packs Pulsar
  `<ledgerId>:<entryId>:...` MessageIds into a 64-bit value). The
  per-context dispatcher producer scoping (producerName
  `dispatcher-<contextId>`, sequence id drawn from the conversation
  log offset) is exposed by
  `Dispatch.SingleFlight.producerDedupSequenceId`; the runtime loop
  that uses it is implemented, and real duplicate-collapse evidence closed in
  Sprint 7.14's chaos validation.
- Sprint 7.9 JWKS TTL cache implemented; Sprint 7.17 subsequently closes the
  chart env injection path.
  `Infernix.Demo.Api` owns a process-lifetime `JwksCache` built in
  `runDemoApiServer` and threaded through both the `/ws` WebSocket
  handshake and the `/api/objects/{upload,download}` handlers, with a
  5-minute TTL. `chart/templates/deployment-demo.yaml` already
  mounts the cluster ConfigMap and cluster Secret that carry the same
  values without infernix-owned environment variables.

`cabal build all`, `infernix lint files`, `infernix lint chart`,
`infernix lint docs`, `infernix lint proto`, `infernix test lint`, and
`infernix test unit` all exit zero against the recorded cohort validation state.
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
`AppleSilicon`-only handoff conditional at `src/Infernix/Runtime/Pulsar.hs:574-590` is
generalised so any substrate forwards when `daemonConfigHostBatchTopic` is set; the recorded
Linux GPU unit validation proves a Linux coordinator forwards request-topic payload bytes to
`inference.batch.linux-cpu` without executing inference inline, and the recorded cohort validation Linux
GPU integration validation proves the routed publication JSON, `cluster status`, generated
demo config, and service runtime loop all use the Linux batch handoff contract. The
chart adds gated-off `daemonSplit.enabled` + `coordinator` / `engine` / `demoSplit`
stanzas, the engine `emptyDir` model-cache `sizeLimit` knob, the `infernix-models` and
`infernix-demo-objects` MinIO bucket entries, and five new templates
(`deployment-coordinator.yaml`, `deployment-engine.yaml`, the three PDBs).

`infernix test lint` and `infernix test unit` both exit zero against this state with
roughly 200 Haskell-side assertions across the new modules.

The previously pending SPA, dispatcher, reader, model-bootstrap, object-storage,
integration, chaos, E2E, and runtime KV-cache surfaces are now implemented and validated by the
cohort gates plus the recorded cohort validation mounted Linux CPU validation recorded above.

The recorded validation pass implemented five focused increments on top of the preceding work:

1. **Sprint 7.2 closure (`Done`).** The generator footer in
   `src/Infernix/Web/Contracts.hs` (new helpers `renderPhase7PursInstances`,
   `renderPursRecordKind`, `renderPursSum`, `renderShowInstanceIfAllNullary`) emits
   hand-rolled Simple.JSON `WriteForeign` / `ReadForeign` instances for every Phase 7
   ADT plus `Show` instances for every nullary sum; the import-normalization in
   `src/Infernix/CLI.hs` adds `Foreign (ForeignError(..), fail) as Foreign` to the
   generated module. The PS roundtrip suite at
   `web/test/Infernix/Web/ContractsSpec.purs` covers 43 cases (string newtypes,
   record newtypes, nullary sums, positional sums, record-syntax sums, WebSocket
   envelopes).
2. **Sprint 7.10 partial.** `web/spago.yaml` adds the `web-socket` package;
   `web/src/Infernix/Web/WebSocket.purs` implements the real `connect` / `sendClientMessage`
   / `connectionStatus` / `close` against the `Web.Socket.WebSocket` browser binding
   with a tiny `WebSocket.js` FFI for raw payload coercion; `web/src/Infernix/Web/Chat.purs`
   exposes `applyConversationStatePatch`, `applyContextListPatch`, `applyDraftMapPatch`,
   `handleServerMessage`, `pendingPromptCount`, and the DOM-level `renderChatView`
   renderer for the context rail, model picker target, conversation pane, draft editor,
   cancel action, and queued-prompt indicator. The recorded validation Sprint 7.15
   follow-on mounts this renderer from `Main.purs` and unmounts the prior Workbench shell.
3. **Sprint 7.11 partial.** `web/src/Infernix/Web/Artifacts.purs` exposes the typed
   `ArtifactsViewState`, `artifactEntryFromReady`, `recordArtifactReady`,
   `handleArtifactsServerMessage`, `artifactsForContext`, and `buildUploadRequest`
   helpers; the MIME-to-disposition classifier handles images / audio / video / PDF /
   text / JSON / MIDI / MusicXML / unknown. The recorded validation follow-on adds the
   DOM-level `renderArtifactsView` renderer for per-context and library lists, upload
   controls, disposition-specific preview placeholders, and download action data
   attributes. The Aff-based HTTP multipart upload helper remains Sprint 7.15-tied.
4. **Sprint 7.12 backend half.** A new `src/Infernix/Dispatch/ContextModelMap.hs`
   module exposes the typed `ContextModelMap` (`IORef (Map Text Text)` keyed on
   `ContextId`) plus `newContextModelMap`, `lookupModelId`, `recordContextModel`, and
   `recordContextMetadataEvent`. `src/Infernix/Runtime/Pulsar.hs.runContextsMetadataConsumer`
   is the per-user worker the coordinator dispatcher loop spawns when it observes a
   new userId; it subscribes Failover to the per-user contexts metadata topic and
   updates the shared map. `publishDispatchedInferenceRequest` now accepts a resolved
   `modelId :: Text` and populates the proto `request_model_id` field with it;
   `handleConsumerEnvelope` validates the inbound `request_model_id` and publishes a
   typed `emptyModelIdRejectionResult` to the result topic instead of delegating to
   the generic engine path when it is empty. `assertContextModelMap` in
   `test/unit/Spec.hs` covers the invariants. The recorded validation follow-on
   plumbed the WS handler's `WebSocketOptions` dispatch callback into
   `Infernix.Runtime.Pulsar.publishDemoClientMessage`, so `ClientCreateContext`
   now publishes `ContextCreated` to the per-user contexts metadata topic.
5. **Sprint 7.13 PureScript layer (closed).** `web/test/Infernix/Web/ChatSpec.purs`
   covers 12 view-model cases; `web/test/Infernix/Web/ArtifactsSpec.purs` covers 11.
   `infernix test unit` reports 67/67 passing across the full PS suite.

`infernix test lint`, `infernix test unit`, `infernix lint files|chart|docs|proto`
all exit zero against this state.

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
the per-pod placement, replica policy, and one-per-node engine rule are codified in
[../documents/architecture/daemon_topology.md](../documents/architecture/daemon_topology.md).

## Sprint 7.1: Keycloak Release and Realm Pre-Seed [Done]

**Status**: Done
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

The recorded validation Sprint 7.1 pass implemented the chart-side scaffolding and supporting Patroni
dependency:

- `chart/Chart.yaml` declares a second `pg-db` dependency aliased to `keycloakpg`, gated
  on `upstreamCharts.keycloakpg.enabled` (default `true` when the demo surface is on).
- `chart/values.yaml` adds:
  - the `keycloakpg:` stanza mirroring `harborpg:` — Patroni cluster managed by the Percona
    operator, `keycloak` user + `keycloak` database, 3-instance HA, `infernix-manual`
    storage class, `infernix-keycloak-db-user` secret, pgbackrest backups.
  - the `keycloak:` stanza — `quay.io/keycloak/keycloak:26.0.7` image, local-demo
    application replica count 1, realm + client identifiers, routed external base URL, admin
    + database secret names, port 8080. The backing Patroni cluster remains HA; multi-pod
    Keycloak serving is held for the Sprint 7.14 proxy-affinity or clustered-cache validation
    pass.
- `chart/templates/keycloak/` adds five templates, all gated on
  `.Values.demo.enabled && .Values.keycloak.enabled`:
  - `deployment.yaml` — Keycloak Deployment with preferred anti-affinity, JDBC env wired
    to the Patroni `pgbouncer` Service, realm import via `--import-realm` from the
    mounted ConfigMap, routed `--hostname=<edge>/auth`, TCP readiness + liveness probes on
    the user-facing listener, and bootstrap admin credentials sourced from the
    `infernix-keycloak-admin` secret.
  - `service.yaml` — ClusterIP Service exposing the Keycloak HTTP listener at port 8080
    so the routed `/auth` HTTPRoute (already registered in `Infernix.Routes`) reaches it
    without a NodePort.
  - `configmap-realm-import.yaml` — realm definition with `registrationAllowed: true`,
    `verifyEmail: false`, an `infernix-spa` public OIDC client with PKCE code challenge,
    edge-aware redirect URI / web-origin defaults, and a length-only password policy.
  - `secret-admin.yaml` — bootstrap admin credentials. Operators rotate this through the
    Keycloak admin UI after first login.
  - `poddisruptionbudget.yaml` — `maxUnavailable: 1` matching the supported HA shape.

`infernix lint chart`, `infernix lint files`, `infernix lint docs`, `infernix lint proto`,
`infernix test unit`, and `infernix test lint` all exit zero with the new chart assets in
place.

The recorded validation `linux-gpu` validation pass surfaced a missing
operator-managed PV reconcile for the keycloak-postgresql Patroni cluster
and a multi-arch Docker push regression on `envoyproxy/gateway:v1.7.2`.
Both fixes implemented the same day in `src/Infernix/Cluster.hs` and
`src/Infernix/Cluster/PublishImages.hs`:

- `Cluster.hs.reconcileFinalPhaseOperatorManagedPersistentVolumes`
  runs after the FinalPhase `deployChart` call and waits for the
  combined `harborPostgresExpectedOperatorClaims + keycloakPostgresExpectedOperatorClaims = 8`
  operator-managed PVCs, creates matching PVs, and binds them. The
  previous warmup-only `reconcileOperatorManagedPersistentVolumes`
  call only ever saw Harbor's 4 PVCs because the keycloak-postgresql
  PerconaPGCluster CR is gated to FinalPhase
  (`upstreamCharts.keycloakpg.enabled`).
- `PublishImages.hs.pushUpstreamMultiArchViaImagetools` is now the
  `skopeo copy --override-os=linux --override-arch=amd64` fallback for
  upstream multi-arch images. A the recorded validation follow-on also derives content-addressed Harbor tags
  from the upstream linux/amd64 manifest when Docker's containerd image store leaves the
  original tag non-inspectable after a successful pull, carries that discovered digest through
  the push fallback so a later Docker Hub manifest rate limit does not force a second manifest
  request, and routes non-taggable upstream tags directly through the fallback copy path.

After the fixes were baked into the `infernix-linux-gpu:local` image,
`./bootstrap/linux-gpu.sh up` reached `lifecyclePhase: steady-state`
on `linux-gpu` with:

- `infernix-keycloak 1/1` (single local-demo application replica Running, supported `infernix`
  realm imported from `--import-realm`, bootstrap admin user created)
- `keycloak-postgresql-instance1-{0,1,2}-0 4/4` (Patroni cluster
  fully healthy via the new FinalPhase PV reconcile)
- `keycloak-postgresql-pgbouncer 3/3`, `keycloak-postgresql-repo-host 2/2`
- `harbor-postgresql-instance1-{0,1,2}-0 4/4` (unchanged — covered
  by the existing warmup reconcile)
- `infernix-coordinator 2/2`, `infernix-engine 1/1`, `infernix-demo 1/1`,
  `infernix-minio 4/4`, Pulsar 3-broker + 3-bookie + 3-zookeeper +
  3-recovery + 3-proxy all Running, Envoy Gateway 1/1, all eleven
  supported HTTPRoutes registered
- the Pulsar admin reconcile created the `infernix` tenant +
  `infernix/demo` + `infernix/system` namespaces + the
  `model.bootstrap.request` topic and set the 100 MiB compaction
  threshold on `infernix/demo`
- the coordinator daemon log reports
  `serviceResultBridgeMode: failover-subscription`,
  `serviceModelBootstrapMode: failover-subscription`, and
  `serviceDispatcherMode: per-context-failover` in steady state

the recorded cohort validation routed browser validation follow-on:

- `src/Infernix/Cluster.hs` renders the routed Keycloak `externalBaseUrl` for the active edge
  URL and runs a `reconcile-keycloak-realm` lifecycle phase after final rollout, patching the
  realm flags, public SPA client redirect URIs, web origins, and PKCE setting through the
  Keycloak admin API.
- `src/Infernix/Cluster.hs` now also keeps the production-shaped final phase honest when
  `demo_ui = false`: `upstreamCharts.keycloakpg.enabled`, `keycloak.enabled`, the
  `infernix-coordinator` Deployment, the final Keycloak Patroni PV reconcile, and the
  Keycloak realm reconcile all follow the active substrate's demo flag.
- `web/playwright/inference.spec.js` adds the routed Keycloak browser smoke. It starts an OIDC
  authorization-code + PKCE flow at `/auth`, follows the registration link, creates a fresh
  username/password account without email verification, and asserts the browser returns to `/`
  with an authorization code and the original state.
- Clean rebuilt-image Linux GPU validation passed with:
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix test e2e`.
  The run reported `2 passed`, `cluster up complete`, and `cluster down complete`.
- Clean rebuilt-image Linux GPU production-shape validation passed with
  `internal materialize-substrate linux-gpu --demo-ui false`, `cluster up`, absence checks for
  the Keycloak Deployment, Service, ConfigMap, Secret, `keycloak-postgresql` Patroni cluster,
  `infernix-demo`, and `infernix-coordinator`, a positive check for `infernix-engine`, and
  `cluster down complete`.

No pending closure remains. The `/auth` browser path closed in the Apple routed E2E gates and
CUDA Linux validation closed in Wave C.

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

### Validation

- `infernix internal generate-purs-contracts` produces deterministic output
- `infernix test unit` exercises encode/decode roundtrip across the new types in both the
  Haskell and PureScript suites
- repeated codegen runs produce byte-identical output

### Remaining Work

Sprint 7.2 is complete. The Haskell side: every named type lives in
`src/Infernix/Web/Contracts.hs` with Aeson tagged-object encoding for the sum variants,
`infernix internal generate-purs-contracts` emits the full set into
`web/src/Generated/Contracts.purs` deterministically (byte-identical across repeated
invocations, verified in `infernix test unit`), and the Haskell-side suite exercises
encode/decode roundtrip across every new type.

The recorded validation pass closed the PureScript side: the generator footer in
`src/Infernix/Web/Contracts.hs` (helpers `renderPhase7PursInstances`,
`renderPursRecordKind`, `renderPursSum`) emits hand-rolled Simple.JSON
`WriteForeign` / `ReadForeign` instances for every Phase 7 type. String-wrapping
newtypes (`UserId`, `ContextId`, `MessageId`, `ClientIdempotencyKey`,
`ArtifactMimeType`) encode as bare strings on the wire (matching the Haskell-side
`deriving newtype (ToJSON)`); record-wrapping newtypes unwrap their inner record;
nullary sums emit `{"tag": "ConstructorName"}`; positional sums emit
`{"tag": "...", "contents": ...}`; record-syntax sums spread the constructor's
fields beside the `tag` key (exactly matching Aeson's `TaggedObject "tag" "contents"`
behavior). The matching `Foreign (ForeignError(..), fail) as Foreign` import is added
to the generated module by the normalization pass in `src/Infernix/CLI.hs`. The
PureScript roundtrip suite at `web/test/Infernix/Web/ContractsSpec.purs` covers
43 cases — every Phase 7 newtype, every nullary sum, every positional sum
constructor, every record-syntax sum constructor, and representative `Ws*Message`
envelopes — and asserts byte-identical re-encoding plus structural wire-shape
spot checks (`"tag"`, `"contents"`, spread field names). `infernix test unit`
reports 46/46 passing.

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

The recorded validation Sprint 7.3 pass implemented the WebSocket handshake plus framed-envelope
dispatch:

- `src/Infernix/Auth/Jwt.hs` (implemented earlier in Sprint 7.3) — JWKS-backed validation
  parameterised in issuer and audience.
- `src/Infernix/Demo/Auth.hs` (implemented earlier in Sprint 7.3) — Keycloak realm wiring
  into the shared `Auth.Jwt` validator.
- `src/Infernix/Demo/WebSocket.hs` — new. `wsApplication` mounts on the @/ws@ route,
  upgrades WAI requests via `Network.Wai.Handler.WebSockets.websocketsOr`, and validates
  the bearer JWT carried in either the `Authorization` header or the `?token=` query
  parameter (the SPA-friendly fallback because browsers cannot set headers on
  `WebSocket(...)` connects). The handshake calls
  `Infernix.Auth.Jwt.verifyAndParseJwt`, captures `UserId` from the `sub` claim, and
  hands off to a per-connection receive loop that decodes the framed envelopes from
  Sprint 7.2 (`WsClientMessage` / `WsServerMessage`). Each decoded `ClientMessage`
  family is classified through the pure `classifyClientMessage` helper. The recorded validation
  follow-on wires state-changing frames through `wsDispatchClientMessage` into
  `Infernix.Runtime.Pulsar.publishDemoClientMessage`, so prompt, cancel, draft, and
  context metadata frames publish typed JSON events to their durable Pulsar topic
  families. The recorded validation follow-on starts per-user context-list/draft Reader streams
  after `ClientHello` and per-context conversation Reader streams after
  `ClientSubscribeContext`; outbound frames are serialized behind a per-session send lock.
  Per-WS state is limited to the WS handle, the authenticated `UserId`, and session-local
  Reader cursors/projections.
- `chart/templates/service-demo.yaml` now sets `sessionAffinity: None` so any frontend
  replica can host any session and the pod-kill-survives-reconnect contract from
  Sprint 7.14 has the substrate it needs.
- `src/Infernix/Demo/Api.hs` mounts the WebSocket handler at `/ws`, using the same
  Keycloak JWKS loader the `/api/objects` handler uses; Sprint 7.17 moved that
  wiring to mounted `ClusterConfig.keycloak.*` fields instead of env overrides.
- The recorded validation routed Playwright follow-on corrected the mounted Keycloak issuer,
  audience, and JWKS URL wiring for the demo backend. The mounted cluster config now uses the
  routed issuer base at `/auth`, the public SPA client id `infernix-spa`, and the in-cluster
  Keycloak service URL with port `8080` plus the `/auth/realms/.../certs` path for JWKS. The
  same run proves the HTTP object-grant path rejects a malformed bearer token and accepts a
  real Keycloak access token exchanged from the routed self-registration auth-code flow.
- A later the recorded cohort validation routed Playwright follow-on opens `/ws?token=<real Keycloak access token>`
  from the browser and verifies the handshake succeeds, then probes `/ws?token=not-a-real-token`
  and verifies the malformed token does not open a WebSocket. The same flow sends a malformed
  frame over the valid connection and asserts the backend replies with a tagged `ServerError`
  carrying `serverErrorErrorCode = "ws_frame_decode_failed"`. The passing mounted-source Linux
  GPU `cabal run infernix -- test e2e` run now reports five Playwright tests passing.
- The recorded validation routed Playwright follow-on temporarily shortens the real Keycloak realm's
  access-token lifespan through the admin API, mints a normal `infernix-spa` access token from
  the existing browser SSO session, waits past the backend JWT leeway window, restores the realm
  setting, and asserts the expired token no longer opens `/ws`.
- the recorded cohort validation integration follow-on: `test/integration/Spec.hs` now queries the deployed
  `service/infernix-demo` and asserts `.spec.sessionAffinity == "None"` against the real
  cluster, matching the stateless WebSocket frontend contract in `chart/templates/service-demo.yaml`.
  `infernix.cabal` already exposes `Infernix.Demo.WebSocket` and depends on `wai-websockets`
  plus `websockets`.

Sprint 7.3 closure notes:

- Routed valid-token, malformed-token, and expired-token browser handshake behavior is now
  covered by Sprint 7.15 E2E.
- Per-context Pulsar Reader conversation snapshots/append patches and per-user
  context-list/draft snapshots/patches now stream back to the browser and are covered by
  Sprint 7.15 E2E. Pod-kill reconnect validation closed on the recorded cohort validation.

`infernix lint chart`, `infernix lint files`, `infernix lint docs`, `infernix lint proto`,
`infernix test lint`, and `infernix test unit` all exit zero with the new WebSocket
module in place.

Closure notes:

- Pulsar Reader cursors per-context: the `runSession` loop now publishes state-changing
  client frames to Pulsar and starts a per-context reader when the browser sends
  `ClientSubscribeContext`; submitted prompts return as canonical `ServerConversationPatch`
  append frames. It also starts per-user context-list and draft readers when the browser sends
  `ClientHello`; context creation and draft update/clear return as canonical
  `ServerContextListPatch` / `ServerDraftMapPatch` frames. Reconnect recovery is covered by
  forced WebSocket reconnect, reload/re-login draft restoration, and the browser-level
  frontend pod replacement E2E case.
- Real-cluster validation: routed browser evidence now proves a valid Keycloak-issued JWT opens
  `/ws`, malformed and expired JWTs are rejected, Linux integration asserts the deployed demo
  Service uses `sessionAffinity: None`, and the routed browser prompt flow receives an inbound
  conversation append patch. Full browser-level pod-kill-survives-reconnect coverage closed on
  the recorded cohort validation by deleting all `infernix-demo` pods during the routed browser flow, waiting for
  replacements, and proving reconnect + active-context resubscribe + prompt submission.
- PureScript-side `web/src/Infernix/Web/WebSocket.purs` client that talks to this
  endpoint (Sprint 7.10).

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
`TopicNamespace`. The shared modules import nothing from `Infernix.Demo.*`; the recorded cohort validation
Haskell style gate now rejects demo, runtime, auth, object-presign, or WebSocket imports from the
conversation primitive modules.

Closure notes:

- Conversation events now ride the Pulsar WebSocket transport as JSON
  payloads (base64-encoded into the producer envelope) from the demo
  WebSocket handler. The supported wire format is the Aeson instances
  already implemented in `Infernix.Web.Contracts`; a parallel protobuf schema
  for `ConversationEvent` is not part of the supported contract.
- Producer-side dedup *structural* wiring is implemented for the WebSocket
  producer and dispatcher paths: the WebSocket publisher uses mutation-scoped
  one-message producer names plus `initialSequenceId` baselines derived from client
  idempotency, prompt, draft, or context keys, and the dispatcher uses stable
  per-context producer scoping with monotonic broker `MessageId`-derived sequence ids.
  Real duplicate-collapse evidence closed in Sprint 7.14's chaos-validation cycle.
- Broker-side dedup is enabled both at the Pulsar broker config layer
  (`brokerDeduplicationEnabled = true` in `chart/values.yaml`) and at
  namespace scope (the recorded cohort validation `reconcileSupportedNamespaces` pass
  POSTs `true` to `/admin/v2/namespaces/<ns>/deduplication` for
  `infernix/demo` and `infernix/system`). The recorded validation Sprint 7.14
  integration pass proves duplicate frontend `(producerName,
  sequenceId)` collisions are rejected on conversation and draft topics;
  coordinator/result/bootstrap replay evidence closed in the Sprint 7.14 Wave C chaos suite.
- Integration round-trip against real Pulsar closed in Sprint 7.14.

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

The pure single-flight rule and envelope construction are implemented in
`Infernix.Dispatch.SingleFlight`. The module exposes `buildDispatchDecision`, the
`InferenceRequestEnvelope` (carrying `userId`, `contextId`, `userPromptMessageId`,
`clientIdempotencyKey`, `conversationLogOffset`, `prefixHash`, `promptText`, `causalRef`),
`producerDedupSequenceId` (keyed by `userPromptMessageId`), and the
`dispatcherSubscriptionName` helper for per-context Failover subscriptions. `infernix test
unit` exercises empty log, single prompt, two-prompts-in-a-row, and promote-after-result
cases. The shared library imports nothing from `Infernix.Runtime.*`, `Infernix.Demo.*`,
`Infernix.Objects.*`, `Infernix.Auth.*`, or any WebSocket module; the recorded cohort validation Haskell style
gate enforces that boundary for `Infernix.Dispatch.SingleFlight`,
`Infernix.Dispatch.ContextModelMap`, `Infernix.Bridge.Result`, and
`Infernix.Bootstrap.Models`.

The recorded validation pass implemented the per-context dispatcher runtime loop
in `src/Infernix/Runtime/Pulsar.hs.runDispatcherLoop` and wired it into
`runProductionDaemon` for the `Coordinator` daemon role alongside
`runResultBridgeLoop` and `runModelBootstrapLoop`. The loop:

- Polls the supported demo namespace (`infernix/demo`) every 30s via
  Pulsar admin `GET /admin/v2/persistent/<tenant>/<namespace>` and
  extracts `(UserId, ContextId)` pairs from any topic matching the
  `demo.conversation.<userId>.<contextId>` shape.
- Forks one per-context worker keyed by `ContextId` (tracked in a
  process-local `MVar (Set Text)` so repeated discovery cycles do not
  start duplicates). The worker subscribes Failover on the
  conversation topic with subscription name
  `dispatcher-<contextId>` (`Dispatch.SingleFlight.dispatcherSubscriptionName`)
  and `subscriptionInitialPosition=Earliest` so a recovered replica
  replays from the start of the log.
- Decodes each `PulsarEnvelope.envelopePayload` as a JSON
  `ConversationEvent` (via the `taggedSumOptions` instance already
  implemented in Sprint 7.2), lifts it into a `ConversationMessage`
  using the envelope's broker `MessageId`, and folds it through
  `Conversation.Reducer.stepReducer` against a per-worker
  `IORef ReducerState`.
- Calls `Dispatch.SingleFlight.buildDispatchDecision`; on
  `DispatchPrompt`, builds an `InferenceRequest` proto envelope
  populated with the dispatcher fields (`userId`, `contextId`,
  `userPromptMessageId`, `clientIdempotencyKey`,
  `conversationLogOffset`, `prefixHash`, `causalRef`) and publishes
  it to the substrate's inference request topic. Producer name is
  `dispatcher-<contextId>` and sequence id is
  `parseMessageIdToSequenceId promptMessageIdText` so the broker
  dedup gate collapses retries from a recovered replica.

The daemon log reports `serviceDispatcherMode: per-context-failover`
on startup when the daemon role is `Coordinator`. `cabal build all`,
`infernix lint files|chart|docs|proto`, `infernix test lint|unit`
all exit zero against this state.

Closure notes:

- The dispatcher-side model-id lookup is code-complete: `ClientCreateContext`
  publishes `ContextCreated { contextCreatedModelId }` to
  `demo.user.<userId>.contexts`, the contexts metadata consumer caches
  `ContextId → modelId`, and `publishDispatchedInferenceRequest` carries
  the resolved `request_model_id`. The real-cluster WS → Pulsar →
  coordinator-consumer → dispatcher round trip closed in Sprint 7.14.
- Pulsar Reader-style crash recovery: the dispatcher acks each
  message immediately after stepping the reducer, so a recovered
  replica picks up at the cursor with empty in-memory state. Producer
  dedup prevents duplicate dispatches but the single-flight queue
  guard ("hold prompt 2 until prompt 1 resolves") only covers the
  case where the recovered replica observes both prompts in the
  same session. Full crash-tolerant state recovery is covered by
  Sprint 7.14's Wave C coordinator replacement validation around durable
  prompt dispatch/writeback.
- Per-context Failover subscription real-cluster validation closed
  in Sprint 7.14.

---

## Sprint 7.7: Truly Stateless Daemon Topology and HA Chart [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime/Pulsar.hs` (batch forwarding + bootstrap subscription wiring), `src/Infernix/Models.hs` (`inference.batch.<mode>` for every substrate; `infernix/system/model.bootstrap.request` topic family), `src/Infernix/DemoConfig.hs` (split `cluster` role into `coordinator` + `engine`; add `modelsBucket` and `modelBootstrapTopic` fields), `src/Infernix/Runtime/Cache.hs` (prior `objectStoreRoot`, `localPathFromUri`, `cacheManifestProtoPath`, `durableArtifactPathFor`, `sourceManifestPathFor`, and the `s3://infernix-runtime/` URI scheme; replaced by a MinIO-backed model loader and an `emptyDir`-backed LRU eviction manager), `src/Infernix/Runtime.hs` (prior the 80-char `buildPayload` branch; text outputs always inline, binary outputs carry a MinIO `ObjectRef`), `src/Infernix/Demo/Api.hs` (prior `serveObject` and the `/objects/:objectRef` route), `src/Infernix/Routes.hs` (prior the `/objects` route entry), `src/Infernix/Service.hs` (acquire `flock(2)` on `engine.lock` at engine-role startup; fail fast with PID diagnostic on contention — uniform across Linux and Apple), `src/Infernix/Cluster.hs` (Helm rollout for the new Deployments + buckets + `infernix/system` namespace + `model.bootstrap.request` topic), `src/Infernix/Bootstrap/Models.hs` (coordinator's bootstrap Failover subscription, download-from-upstream + upload-to-MinIO with `.ready` sentinel), `src/Infernix/Bridge/Result.hs` (shared-library result-bridge, replaces the previously planned `Infernix.Demo.ResultBridge`), `python/adapters/model_cache.py` (shared adapter helper exposing `get_model_path(model_id) -> path`, MinIO client + LRU eviction rooted at `/model-cache`, uniform across every engine), `python/adapters/common.py`, `python/adapters/diffusers_python.py`, `python/adapters/jax_python.py`, `python/adapters/pytorch_python.py`, `python/adapters/tensorflow_python.py`, `python/adapters/transformers_python.py`, `python/adapters/vllm_python.py` (adapter integration with typed cache/config helpers), `chart/templates/deployment-coordinator.yaml` (no PVC), `chart/templates/deployment-engine.yaml` (no PVC; single `emptyDir` volume `model-cache` with `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}`, default `32Gi`), `chart/templates/poddisruptionbudget-coordinator.yaml`, `chart/templates/poddisruptionbudget-engine.yaml`, `chart/templates/poddisruptionbudget-demo.yaml`, `chart/values.yaml` (`infernix-models` always-on; `infernix-demo-objects` demo-gated; `coordinator`/`engine`/`demo` HA stanzas; `engine.modelCache.sizeLimit` knob), `dhall/InfernixSubstrate.dhall` (coordinator + engine role schemas; `modelsBucket : Text`; `modelBootstrapTopic : Text`; per-model `downloadUrl : Text`), `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` (prior fused Deployment, service-data PVC, object-store URI, and placeholder-bucket cleanup ledger)
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
  `sizeLimit: {{ .Values.engine.modelCache.sizeLimit }}` (default `32Gi`) at `/model-cache`,
  enforced by kubelet so the pod cannot exhaust node disk
- **Strict one-engine-per-node, uniform across substrates.** On Linux substrates this is
  enforced by `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity on the
  engine Deployment's own label with `topologyKey: kubernetes.io/hostname`; on Apple silicon
  the engine role is the on-host `infernix service` daemon and the same rule is enforced via
  an exclusive `flock(2)` on `engine.lock` acquired at daemon startup. The Linux engine pod
  acquires the same lock symmetrically (no-op in practice because anti-affinity already
  enforces uniqueness, but keeps the contract uniform)
- **Batch handoff topic family.** `src/Infernix/Runtime/Pulsar.hs:drainTopic` forwards to
  `daemonConfigHostBatchTopic` whenever that field is set, irrespective of `runtimeMode`, and
  `inference.batch.<mode>` topic definitions exist for `linux-cpu` and `linux-gpu`
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
- **Uniform model-cache adapter helper.** `python/adapters/model_cache.py` exposes
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
- **Delete prior surfaces:** `./.data/object-store/` tree, `objectStoreRoot` plumbing in
  `Runtime/Cache.hs`, the `s3://infernix-runtime/` URI scheme + `localPathFromUri` mapping,
  the `/objects/:objectRef` HTTP route handler in `Demo/Api.hs`, and the route registry
  entry in `Routes.hs`
- **Move the planned `Infernix.Demo.ResultBridge` to `src/Infernix/Bridge/Result.hs`**
  (shared library; loaded by coordinator). The demo binary carries no result-bridge module
- **Three new Deployments + PDBs**: `infernix-coordinator` (replicas ≥ 2 default, preferred
  anti-affinity, demo-gated), `infernix-engine` (replicas operator-set
  on Linux substrates; 0 on `apple-silicon`; required anti-affinity; GPU resource shape on
  `linux-gpu`), `infernix-demo` (replicas ≥ 2 default; preferred anti-affinity; demo-gated).
  PodDisruptionBudgets `maxUnavailable: 1` on each
- **Production (`demo_ui = false`) deploys only the engine Deployment.** Frontend and
  coordinator are demo-gated; production bootstrap semantics for lazy model population remain
  pending and must not reintroduce the demo coordinator deployment
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

The pure-Haskell coordination layer plus the additive chart-side scaffolding are implemented:

- `src/Infernix/Bridge/Result.hs` exposes the shared-library result-bridge contract
  (Failover subscription naming, producer-dedup key derivation keyed by
  `userPromptMessageId`, and pure construction of the `ConversationInferenceResultEvent`
  the bridge must publish on the conversation topic).
- The `AppleSilicon`-only forwarding conditional at
  `src/Infernix/Runtime/Pulsar.hs:drainTopic` is now generalised: the daemon forwards to
  `daemonConfigHostBatchTopic` whenever that field is set, irrespective of `runtimeMode`.
  The recorded validation Linux GPU validation adds a unit assertion that a Linux coordinator forwards
  invalid request protobuf bytes from `inference.request.linux-cpu` to
  `inference.batch.linux-cpu` without executing inference inline. Linux default daemon configs now
  materialize the batch handoff topic, while engine-role configs keep
  `daemonConfigHostBatchTopic = Nothing` to avoid self-forward loops.
- `Infernix.Models.canonicalBatchTopicForMode` exposes the supported
  `inference.batch.<mode>` topic name for every substrate.
- `Infernix.Conversation.Topic.systemTopicNamespace` plus
  `modelBootstrapRequestTopicName` / `modelBootstrapReadyTopicName` cover the new
  `infernix/system` namespace and the `model.bootstrap.request` /
  `model.bootstrap.ready.<modelId>` topic family.
- `chart/values.yaml` carries the `daemonSplit.enabled` gate plus `coordinator`, `engine`,
  and `demoSplit` HA stanzas including the `engine.modelCache.sizeLimit` `emptyDir` knob
  (default `32Gi`), the `infernix-models` always-on MinIO bucket, and the demo-gated
  `infernix-demo-objects` bucket. The prior `infernix-runtime` / `infernix-results` placeholder
  bucket entries are gone, and the remaining `service.*` stanza is shared backend wiring consumed
  by the role-specific templates.
- New chart templates: `chart/templates/deployment-coordinator.yaml`,
  `chart/templates/deployment-engine.yaml`, and the three PodDisruptionBudgets
  (`poddisruptionbudget-{coordinator,engine,demo}.yaml`). The engine template uses
  required pod anti-affinity on its own label keyed on `kubernetes.io/hostname`, mounts
  a single `emptyDir` `/model-cache` volume with the operator-set `sizeLimit`, and
  carries the existing `linux-gpu` `nvidia.com/gpu` shape. The new templates are gated
  on `daemonSplit.enabled` and the per-role `enabled` flags, with the split topology enabled by
  default.
- `infernix lint chart`, `infernix lint files`, `infernix lint docs`,
  `infernix lint proto` exit zero with the new chart templates in place.

The recorded validation cleanup pass additionally implemented the following sub-items, all
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
  the `./.data/object-store/results/<requestId>.txt` overflow path is absent,
  and the unit tests at `test/unit/Spec.hs` were updated to assert inline-output
  behaviour. Listed as **Completed** in `legacy-tracking-for-deletion.md`.
- `/objects/:objectRef` HTTP route cleanup: the `serveObject` handler is gone
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
  helper reads typed `ModelCacheConfig` configured by the engine daemon and uses
  `/model-cache/<modelId>/` with a `.ready` sentinel; the MinIO download client,
  LRU eviction loop, and real-cluster validation are closed by Sprint 7.14.

Closure notes:

- `src/Infernix/Bootstrap/Models.hs` real-cluster wiring implemented the recorded cohort validation:
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
  scheme + host:port separately so the mounted
  `ClusterConfig.minio.endpoint` value produces correct URLs).
  `runProductionDaemon` forks the bootstrap loop together with
  the result-bridge when `daemonRole == Coordinator`; the daemon
  log reports `serviceModelBootstrapMode: failover-subscription`
  in steady state. `Infernix.Bootstrap.Models` adds the Aeson
  `ToJSON` / `FromJSON` instances the wire envelope needs.
  Real-cluster validation closed with Sprint 7.14's Wave C
  model-bootstrap deduplication case across coordinator replacement.
- `python/adapters/model_cache.py` MinIO client + LRU eviction loop
  implemented (the recorded cohort validation): `get_model_path(model_id)` now lists
  `infernix-models/<modelId>/` via boto3's S3 surface, refuses to
  proceed until the upstream `.ready` sentinel exists, streams every
  file to `/model-cache/<modelId>/` via atomic temp-file rename,
  writes the local `.ready` sentinel last, and runs an LRU eviction
  pass (32 GiB default quota). Sprint 5.9 / 7.17 moved the cache root,
  quota, models bucket, MinIO endpoint, credentials, and region into
  the typed `ModelCacheConfig` passed through `configure()` instead of
  Python environment reads. `python/pyproject.toml` declares the new
  `boto3 ^1.35.0` dependency.
- Code-level retirement of `./.data/object-store/`, `objectStoreRoot`,
  and `localPathFromUri` is implemented. `src/Infernix/Runtime/Cache.hs` is
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
  gone from `chart/values.yaml`, the prior `service.*` stanza is
  reduced to shared backend wiring, and `daemonSplit.enabled = true` is
  the default chart topology. `cabal build all`, `infernix lint files`,
  `infernix lint chart`, `infernix lint docs`, `infernix lint proto`,
  `infernix test unit`, and `infernix test lint` all exit zero against
  this state on the recorded cohort validation.
- `DemoConfig.hs` daemon-role vocabulary cutover from `cluster` / `host` strings to
  `coordinator` / `engine` is implemented across the Dhall schema field names, `Types.hs`
  `DaemonRole` constructors, test fixtures, and generated `.dhall` materialization path.
- Producer-side dedup *structural* wiring is implemented:
  `publishTopicPayload` now takes a `PublishOptions { publishProducerName,
  publishSequenceId }` record, `buildProducerSocketPath` appends a
  stable `producerName` plus optional `initialSequenceId` query parameters to the WebSocket
  producer URL, and the daemon-side request consumer derives a per-message
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

The recorded validation pass implemented the proto envelope extension plus the
real result-bridge runtime loop:

- `InferenceResult` proto envelope adds `user_id` (field 10) and
  `context_id` (field 11) alongside the existing `causal_ref` (field
  9); the `Infernix.Types.InferenceResult` domain record gains the
  matching `resultUserId` / `resultContextId` / `resultCausalRef`
  fields with Aeson `omitempty` defaults so prior callers (the
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
  routing fields (prior / Phase 4 path) are skipped cleanly without
  ack-failure so the bridge does not break the manual-inference path.
- `runResultBridgeLoop` is wired into `runProductionDaemon` so the
  `Coordinator` daemon role automatically starts the bridge on
  startup (the `Engine` role does not); the daemon log reports
  `serviceResultBridgeMode: failover-subscription` when active.
- `publishedResultFromRequest` propagates the request envelope's
  `user_id` / `context_id` / `user_prompt_message_id` into the result
  envelope so the bridge has the routing fields it needs.

the recorded validation closure:

- `src/Infernix/Runtime/KVCache.hs` exposes the engine-side
  `EngineKVCache`, `KVCacheRequest`, `KVCacheObservation`,
  `observeKVCachePrefix`, `verifyKVCachePrefix`, and
  `rebuildPrefixHashFromLog` helpers. `executeInferenceWithKVCache`
  threads observations through the worker path, and native worker output
  surfaces `kv-cache=reuse|rebuild` plus `kv-prefix-hash` when the
  durable-context envelope carries cache metadata.
- `src/Infernix/Runtime/Daemon.hs` owns production daemon role
  orchestration. It allocates one process-local engine KV cache per
  daemon process, threads it into filesystem and WebSocket Pulsar engine
  request consumption, starts coordinator loops only for the
  `Coordinator` role, and leaves `Infernix.Runtime.Pulsar` as the shared
  transport/loop module.
- `test/unit/Spec.hs.assertKVCacheConsistency` proves matching prefix
  hashes reuse cache, missing or tampered hashes force rebuild, and the
  rebuilt hash equals the canonical prefix chain. `assertRuntimeKVCachePath`
  exercises the runtime/native worker path and asserts first-run rebuild,
  matching-prefix reuse, and divergent-prefix rebuild.
- `src/Infernix/Runtime/Pulsar/Failover.hs` centralizes Failover
  consumer naming. `runResultBridgeLoop`, `runDispatcherForContext`,
  `runContextsMetadataConsumer`, and `runModelBootstrapLoop` keep their
  stable subscription names but use process-qualified consumer names so
  multiple coordinator replicas do not present identical member names
  during broker promotion. Unit coverage pins the naming policy.
- The Haskell style boundary now includes
  `src/Infernix/Runtime/KVCache.hs` alongside `Runtime.hs`,
  `Runtime/Cache.hs`, and `Runtime/Worker.hs`, so the engine-side
  cache consistency helper cannot import demo, coordinator, auth,
  object-presign, bootstrap, or WebSocket modules.
- Mounted Linux CPU validation on the recorded cohort validation passed:
  `docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm --volume /home/matt/infernix:/workspace infernix cabal build all`,
  `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and
  `cabal test infernix-integration` after restaging
  `infernix internal materialize-substrate linux-cpu --demo-ui true`.
  The integration run covered durable dispatcher/result writeback,
  frontend/coordinator/engine pod replacement, engine node drain,
  model-bootstrap deduplication, Linux engine anti-affinity, compact
  multi-user durable prompt throughput
  (`users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12 p95Seconds=67.22616362571716`),
  platform recovery, production-shape deployment, and clean teardown.

Closure notes: none.

---

## Sprint 7.9: Demo MinIO Bucket and Presigned URL Minting [Done]

**Status**: Done (runtime bucket repair code implemented on the recorded cohort validation; rebuilt-image `linux-gpu` validation passed against digest `sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b`; rebuilt-image `linux-cpu` validation passed through build, style/Python/unit/web-unit gates, full integration, and routed Playwright E2E (7/7) on the recorded cohort validation against digest `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`; Sprint 7.8 blocker closed on the recorded cohort validation.)
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
  client config and grant-time scope check
- `Infernix.Demo.Api` — `/api/objects` HTTP route that consumes JWT, validates per-user
  scope, and returns presigned PUT or GET URLs
- `Infernix.Demo.Bootstrap` — idempotent first-run bucket creation
- `/api/objects` route added to the Haskell route registry source

### Validation

- integration test mints a presigned PUT for user A, uploads, mints presigned GET, downloads;
  asserts content equality
- cross-user negative test: user A and user B with the same logical context/display name receive
  distinct per-`sub` object prefixes; one user's default grant path cannot read the other's object
- when `demo_ui = false`, the bucket and `/api/objects` route are absent

### Remaining Work

The recorded validation Sprint 7.9 pass implemented the full HTTP handler with JWT validation, per-user
scope enforcement, and presigned URL minting:

- `src/Infernix/Objects/Layout.hs` — bucket and prefix conventions
  (`users/<userId>/contexts/<contextId>/{uploads,generated}/`) plus the
  `pathBelongsToUser` scope helper. Landed earlier in Sprint 7.9 and still in place.
- `src/Infernix/Objects/Presigned.hs` — AWS SigV4-style presigned URL minting against
  MinIO with parameterised endpoint, region, access key, secret key, and expiry. Landed
  earlier in Sprint 7.9.
- `src/Infernix/Demo/Api.hs` — `/api/objects/upload` and `/api/objects/download` HTTP
  handlers that read the `Authorization: Bearer …` header, fetch the Keycloak JWKS
  from mounted `ClusterConfig.keycloak.*`, call
  `Infernix.Auth.Jwt.verifyAndParseJwt`, derive `UserId` from the `sub` claim, scope
  the requested object to `users/<userId>/contexts/<contextId>/{uploads,generated}/`,
  validate the scope via `pathBelongsToUser`, mint a presigned PUT or GET URL via the
  shared `Infernix.Objects.Presigned` helper, and return the matching
  `ArtifactUploadGrant` / `ArtifactDownloadGrant` JSON. The MinIO endpoint, region,
  presign expiry, and credential path come from mounted `ClusterConfig.minio` plus
  `SecretsConfig.minio`.
- `src/Infernix/Demo/Bootstrap.hs` — `requiredDemoBuckets` plus the
  `planDemoBucketBootstrap` pure helper that names the supported `infernix-models` and
  `infernix-demo-objects` buckets and computes the missing-bucket diff.
- `chart/values.yaml` — the demo-gated `infernix-demo-objects` bucket entry sits in the
  MinIO `provisioning.buckets` list alongside the always-on `infernix-models` bucket;
  the chart-time provisioner creates both before any pod consumes them.

`infernix lint chart`, `infernix lint files`, `infernix lint docs`, `infernix lint proto`,
`infernix test lint`, and `infernix test unit` all exit zero with the new handler in
place.

The recorded validation Sprint 7.9 follow-on closed the JWKS-cache path; Sprint 7.17 later
prior the chart env injection items:

- `src/Infernix/Demo/Api.hs` now owns a per-process `JwksCache`
  built in `runDemoApiServer` (one `IORef (Maybe (UTCTime, Jwks))`
  threaded through to both the `/ws` WebSocket handshake and the
  `/api/objects/{upload,download}` handlers). `loadJwksCached` honours
  a 5-minute TTL so a JWKS rotation surfaces within one cache cycle
  without triggering an upstream `GET .../protocol/openid-connect/certs`
  per request.
- `chart/templates/deployment-demo.yaml` mounts the cluster ConfigMap and cluster Secret
  so the demo backend can read `ClusterConfig` and `SecretsConfig` directly; it no longer
  injects infernix-owned environment variables.

the recorded cohort validation routed grant-validation follow-on:

- `chart/values.yaml`, `src/Infernix/Cluster.hs`, and the unit fixture now align the mounted
  `ClusterConfig.keycloak` fields with the routed Keycloak realm and public SPA client:
  `baseUrl` is the public `/auth` issuer base, `clientId` is `infernix-spa`, and `jwksUrl`
  points at the in-cluster Keycloak service on `:8080/auth/realms/infernix/.../certs`.
- `src/Infernix/Demo/Api.hs` bounds JWKS HTTP fetches so a bad JWKS route reports as a backend
  failure instead of waiting for the edge proxy timeout.
- `web/playwright/inference.spec.js` now registers a fresh routed Keycloak user, exchanges the
  returned authorization code through the `/auth/.../token` endpoint with PKCE, posts a malformed
  bearer token to `/api/objects/upload` and receives `401`, then posts the real access token to
  `/api/objects/upload` and `/api/objects/download`. The grant responses are scoped to
  `infernix-demo-objects/users/<sub>/contexts/<contextId>/uploads/<displayName>`.
- `ClusterConfig.minio.presignPublicEndpoint` splits the browser-facing presign base from the
  in-cluster MinIO Service endpoint. The supported local Gateway value is `<edge>/minio/s3`;
  presigned signatures keep the canonical S3 path as `/infernix-demo-objects/...` while the
  returned URL includes the routed prefix that Envoy rewrites away before MinIO receives it.
- The same routed Playwright test now PUTs bytes through the minted upload URL, mints a download
  grant for the same object, GETs the routed presigned URL, and asserts byte equality. The clean
  rebuilt Linux GPU launcher passed the mounted-source
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm --volume /home/matt/infernix:/workspace infernix cabal run infernix -- test e2e`
  gate with the routed object-grant byte roundtrip included on the recorded cohort validation.
- A later the recorded cohort validation routed Playwright follow-on registers two real Keycloak users and reuses
  the same context id plus display name. User B's download grant points at
  `users/<subB>/...`, returns `404` before user B uploads, then reads user B's bytes after upload;
  user A's original grant still reads user A's bytes. This closes the routed cross-user
  object-prefix isolation negative for `/api/objects`.
- A later the recorded cohort validation routed Playwright follow-on validates
  `ArtifactDownloadGrant.artifactDownloadGrantRenderDisposition` for image/audio/video,
  PDF, JSON, text, MIDI, MusicXML, and generic binary MIME cases. The paired
  `test/unit/Spec.hs` matrix assertion covers `Demo.Api.renderDispositionForMime`.

The recorded validation residual pass implemented runtime-time bucket repair for the demo backend:

- `src/Infernix/Objects/Presigned.hs` now exposes bucket-level S3 SigV4 URL minting through
  `PresignedBucketRequest` and `presignedBucketUrl`, reusing the same typed MinIO config as
  object PUT/GET grants.
- `src/Infernix/Demo/Api.hs.runDemoApiServer` calls `repairDemoBucketsAtStartup` when
  `demo_ui = true` and a mounted `ClusterConfig` is available. The repair path loads the mounted
  MinIO endpoint and credentials, creates the required demo buckets with presigned `PUT /<bucket>`
  requests, treats HTTP 200 and 409 as successful idempotent outcomes, retries 12 times with a
  5-second delay while MinIO converges, and logs a host-native skip when no cluster config is
  mounted.
- `test/unit/Spec.hs.assertObjectsLayoutAndPresigning` covers bucket-level presigned URL shape
  and signature material for `infernix-demo-objects`.

Closure notes:

- Rebuilt-image `linux-gpu` validation passed the startup repair code in the same container image
  used for ordinary cluster execution on the recorded cohort validation. Rebuilt-image `linux-cpu` validation passed
  the same residual gate on the recorded cohort validation through the full `./bootstrap/linux-cpu.sh test` suite,
  including routed Playwright E2E (7/7).
- `cluster up` with `demo_ui = false` already shows neither the `/api/objects` route nor the
  `infernix-demo-objects` bucket; keep that absence check in the closure suite.

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

The recorded validation pass implemented the structural transport + patch-helper
surface this sprint owns:

- `web/spago.yaml` adds `web-socket` to the package dependency list so
  the browser binding for the @WebSocket@ API is in scope.
- `web/src/Infernix/Web/WebSocket.purs` implements the real send /
  receive loop: `connect` opens @ws[s]://<edgeOrigin>/ws?token=<JWT>@
  via @Web.Socket.WebSocket.create@, wires open / close / message
  listeners via @Web.Event.EventTarget@, decodes each frame as a
  `WsServerMessage` via Simple.JSON (the tagged-sum instances implemented
  in Sprint 7.2), and exposes a typed `sendClientMessage` plus a live
  `connectionStatus` ref the SPA shell can poll. A tiny FFI shim
  (`WebSocket.js`) accepts raw WS payloads as strings.
- `web/src/Infernix/Web/Chat.purs` exposes the mechanical patch-
  application helpers (`applyConversationStatePatch`,
  `applyContextListPatch`, `applyDraftMapPatch`) plus the
  `handleServerMessage` dispatcher the WS handler hands off to. The
  `pendingPromptCount` helper drives the two-prompt queued indicator.
  None of these helpers reimplement any reducer rule — they are pure
  upserts / replaces over the projected view state.
- `web/src/Infernix/Web/Auth.purs` + `web/src/Infernix/Web/Auth.js`
  carry the typed `TokenStore` and the routed browser PKCE
  authorization-code exchange for the `infernix-spa` client. The access
  token stays in memory; only the temporary verifier/state pair crosses
  the redirect through session storage.
- `web/src/Infernix/Web/Router.purs` carries the Chat / Artifacts route
  enumeration the shell consumes.
- `web/test/Infernix/Web/ChatSpec.purs` covers the patch helpers + the
  WS dispatcher + the queued-prompt counter across 12 cases.
  `infernix test unit` reports 67/67 passing.

Closure notes:

- the recorded cohort validation follow-on: `web/src/Infernix/Web/Chat.purs`
  now exports `renderChatView`, a DOM-level renderer for the left
  rail, model picker target, active conversation pane, draft text box,
  cancel button, and two-prompt queued indicator. `infernix test unit`
  rebuilds the PureScript bundle and passes 67/67 PS tests against
  this renderer-bearing module.
- the recorded cohort validation Sprint 7.15 follow-on: `web/src/Main.purs` and
  `web/src/index.html` now mount the durable-context shell and call
  `renderChatView` / `renderArtifactsView` instead of the prior
  manual-inference Workbench shell. `web/test/Main.purs` no longer
  imports the Workbench view-model helpers; the retained routed
  Playwright smoke still checks that the SPA root and platform-state
  JSON endpoints are served.
- the recorded cohort validation Sprint 7.15 follow-on: Playwright now opens `/ws` with
  a real Keycloak access token and verifies a malformed token does not
  open a browser WebSocket. The same flow sends malformed frame data on
  the valid connection and verifies the typed `ServerError` decode
  failure response.
- the recorded cohort validation browser-shell follow-on: `web/src/Main.purs` wires the
  model-picker select, local new-context creation, and
  `ClientCreateContext` publish through the active WebSocket when a
  token-backed connection exists.
- the recorded cohort validation browser-shell follow-on: `web/src/Main.purs` wires the
  rendered Chat form submit and draft input to `ClientSubmitPrompt`
  and `ClientUpdateDraft`, includes the current context's uploaded
  `ObjectRef`s in `promptUserUploads`, and clears the local draft after
  submit while prompt rendering remains server-patch owned.
- the recorded cohort validation per-context stream follow-on: `web/src/Main.purs`
  sends `ClientSubscribeContext` when a context becomes active,
  `Infernix.Demo.WebSocket` starts the injected per-context stream,
  and `Infernix.Runtime.Pulsar.streamDemoContextConversation` reads
  the conversation topic and returns `ServerConversationSnapshot` /
  `ServerConversationPatch` frames. `Chat.purs` reconciles canonical
  broker prompt patches by `ClientIdempotencyKey`, and Playwright
  asserts the inbound append patch for a submitted prompt.
- the recorded cohort validation cancel follow-on: `Chat.purs` treats cancel events as
  prompt-resolution events for pending-count projection,
  `Main.purs.cancelLatestPrompt` targets the latest unresolved
  server-backed prompt id, and Playwright asserts outbound
  `ClientCancelPrompt`, inbound `ConversationCancelEvent`, and rendered
  cancel entry behavior.
- the recorded cohort validation per-user metadata stream follow-on:
  `web/src/Infernix/Web/WebSocket.purs` sends a typed `ClientHello`
  as the socket's first open-frame; `Infernix.Demo.WebSocket` starts
  injected per-user streams after that hello; and
  `Infernix.Runtime.Pulsar.streamDemoUserMetadata` reads the compacted
  contexts and drafts topic families, returning
  `ServerContextListSnapshot` / `ServerDraftMapSnapshot` plus
  `ServerContextListPatch` / `ServerDraftMapPatch` frames. Empty
  `ClientUpdateDraft` now publishes `DraftCleared`, and prompt submit
  sends that empty update after `ClientSubmitPrompt` so durable drafts
  clear through the broker path. Playwright asserts the context-create
  patch, draft upsert patch, and draft-remove patch.
- the recorded cohort validation draft-restore follow-on: `web/src/Main.purs` stores
  only the active context id/model id in session storage, clears that
  browser state on logout, and uses it to send the initial
  `ClientSubscribeContext` after a reload login. Playwright now proves
  draft text is restored after a forced WebSocket reconnect and after a
  full page reload plus Keycloak re-login.

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
- HTTP multipart upload helper that issues a presigned PUT request to `/api/objects`, then
  uploads directly to MinIO, then publishes a `UserUpload` event via WS
- WS handler for `ArtifactReady` server messages renders the new artifact in place

### Validation

- `purescript-spec` view-model tests for artifact-kind dispatch
- E2E (Sprint 7.15) covers upload, download, render-or-download behavior for each supported
  artifact class, and the generated-artifact lifecycle (SDXL Turbo image, bark-small audio,
  Basic Pitch MIDI, Audiveris notation)

### Remaining Work

The recorded validation pass implemented the typed view-state container, the
MIME-to-disposition classifier, the per-user/per-context artifact
library upsert helpers, the WS `ServerArtifactReady` dispatch path,
and the typed `ArtifactUploadRequest` builder the multipart upload
helper hands off to `/api/objects/upload`:

- `web/src/Infernix/Web/Artifacts.purs` exposes `ArtifactsViewState`
  (per-user library, contextually filtered via
  `artifactsForContext`), `artifactEntryFromReady` (heuristic MIME
  inference from object key when only the WS notification has
  arrived), `recordArtifactReady` (upsert keyed on bucket+key so
  repeated WS notifications collapse), `handleArtifactsServerMessage`
  (dispatch path the WS handler delegates to), and `buildUploadRequest`
  (typed @ArtifactUploadRequest@ for the @POST /api/objects/upload@
  body). `dispositionFor` is the supported MIME-to-disposition mapping:
  images / audio / video render inline, PDFs use the browser-native
  viewer, JSON / text preview bounded, MIDI / MusicXML / MXL / unknown
  / generic binary fall back to download-only.
- `web/test/Infernix/Web/ArtifactsSpec.purs` covers 11 cases — every
  MIME-to-disposition branch plus the library upsert, per-context
  filter, and typed upload-request shape.

`infernix test unit` reports 67/67 passing across the full PS suite.

Closure notes:

- the recorded cohort validation follow-on: `web/src/Infernix/Web/Artifacts.purs`
  now exports `renderArtifactsView`, a DOM-level renderer for the
  per-context list, per-user library, upload UI with progress bar,
  download action surface, inline-media / PDF / text-preview
  placeholders, and download-only fallback for MIDI / MusicXML /
  generic binary. `infernix test unit` rebuilds the PureScript bundle
  and passes 67/67 PS tests against this renderer-bearing module.
- the recorded cohort validation follow-on: `src/Infernix/Demo/Api.hs` now maps
  `/api/objects/download` MIME types to the same typed
  `ArtifactRenderDisposition` matrix used by the SPA fallback:
  image/audio/video -> `RenderInline`, PDF -> `BrowserNativePdf`,
  JSON/text -> `BoundedTextPreview`, and MIDI / MusicXML / generic
  binary -> `DownloadOnly`. `test/unit/Spec.hs` covers the Haskell
  matrix and routed Playwright covers the grant JSON returned by the
  real demo backend.
- the recorded cohort validation browser transport follow-on:
  `ArtifactTransport.purs` / `.js` binds the rendered upload and
  download controls. The browser POSTs the typed upload request to
  `/api/objects/upload`, PUTs the selected file directly to MinIO
  through the returned presigned URL, records the uploaded object in
  Artifacts state, POSTs download requests to `/api/objects/download`,
  and renders bounded text/JSON previews, inline image/audio/video
  media, browser-native PDF URLs, and MIDI / MusicXML / generic
  download-only states through routed presigned GET URLs.
- the recorded cohort validation browser artifact Playwright follow-on: the routed SPA
  flow now exercises text and JSON bounded previews, PNG image inline
  rendering, WAV audio and MP4 video media URL wiring, browser-native
  PDF URL wiring, and MIDI / MusicXML / generic binary download-only
  behavior through the rendered upload and download controls.
- the recorded cohort validation upload-event follow-on: the Haskell-owned browser contract
  adds `ClientRecordUpload`, `Infernix.Runtime.Pulsar.planDemoClientMessagePublications`
  maps it to a per-context `ConversationUserUploadEvent` with producer dedup keyed by the
  uploaded `ObjectRef`, and the SPA sends that frame after a successful browser presigned PUT.
  `test/unit/Spec.hs` and the PureScript contract spec cover the new wire variant.
- the recorded cohort validation prompt-upload follow-on: the Chat form now sends `ClientSubmitPrompt` with
  `promptUserUploads` populated from the current context's uploaded artifacts, and Playwright
  captures the outbound browser WebSocket frame to assert those object refs are present. The
  per-context stream now makes submitted prompt events browser-visible through an inbound
  `ServerConversationPatch`.
- the recorded cohort validation conversation-visible upload follow-on: `web/playwright/inference.spec.js`
  now asserts each browser upload sends `ClientRecordUpload`, receives the matching inbound
  `ConversationUserUploadEvent` append patch for the active context, and renders the upload
  message with its display name and MIME type in the Chat conversation.

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
  active catalog and rejects unknown ids
- new-context dialog opening does not create backend state; closing without confirmation leaves
  no backend state

### Validation

- E2E: open new-context dialog, see catalog entries for the active substrate (skipping
  `Not recommended`), pick model, submit prompt, see context appear in left rail
- E2E negative: closing the dialog without confirmation creates no backend frame or local context

### Remaining Work

The recorded validation pass implemented the backend half of this sprint:

- `src/Infernix/Dispatch/ContextModelMap.hs` (new) exposes the typed
  `ContextModelMap` (`IORef (Map Text Text)` keyed on `ContextId`)
  plus `newContextModelMap`, `lookupModelId`, `recordContextModel`,
  and `recordContextMetadataEvent`. `ContextCreated` pins the model
  id for the context's life; `ContextRenamed` and `ContextSoftDeleted`
  are no-ops for the binding (the supported contract pins model id
  for life, per the design doc).
- `src/Infernix/Runtime/Pulsar.hs.runContextsMetadataConsumer` is the
  per-user worker the coordinator dispatcher loop spawns when it
  observes a new userId. It subscribes Failover to
  `persistent://infernix/demo/demo.user.<userId>.contexts`, decodes
  each frame as a `ContextMetadataEvent`, and updates the shared
  `ContextModelMap`. `discoverAndStartDispatchers` now spawns both
  the per-context dispatcher worker AND the per-user contexts
  consumer the first time each is observed.
- `src/Infernix/Runtime/Pulsar.hs.publishDispatchedInferenceRequest`
  now accepts the resolved `modelId :: Text` and populates the proto
  `request_model_id` field with it (no longer hardcoded `""`).
  `handleDispatcherMessage` calls `ContextModelMap.lookupModelId`
  before publishing.
- Engine-side validation in
  `Pulsar.handleConsumerEnvelope`: when the inbound proto's
  `request_model_id` is empty, the engine publishes a typed
  `emptyModelIdRejectionResult` to the result topic instead of
  delegating to the generic engine path. The rejection result
  carries `status: "failed"` plus the typed error message; the
  coordinator's result-bridge writes it back to the conversation
  log so the SPA's Chat surface renders the typed failure.
- Haskell unit test `assertContextModelMap` in `test/unit/Spec.hs`
  covers the empty-init, direct insert, lookup-known / lookup-missing,
  `ContextCreated` populate, and `ContextRenamed` / `ContextSoftDeleted`
  no-op invariants. `infernix test unit` passes.

Closure notes:

- SPA-side model-picker dialog / event refinements in `Chat.purs` and `Main.purs` now render a
  state-backed new-context dialog. The routed browser flow opens the dialog, closes it, asserts no
  `ClientCreateContext` frame or local context appears, reopens the dialog, selects a
  non-`Not recommended` catalog row, asserts `ClientCreateContext` carries the selected `modelId`,
  and verifies the broker-backed context-list patch plus active left-rail item keep that model id.
- The WS handler publish path is code-complete as of the recorded cohort validation:
  `ClientCreateContext` publishes typed `ContextCreated` metadata to
  `persistent://infernix/demo/demo.user.<userId>.contexts` through
  `WebSocketOptions.wsDispatchClientMessage` and
  `Infernix.Runtime.Pulsar.publishDemoClientMessage`. The remaining
  gate closed in the recorded cohort validation Sprint 7.14 durable prompt roundtrip:
  the integration test publishes `ClientCreateContext`, lets the
  coordinator contexts-metadata consumer hydrate `ContextModelMap`,
  publishes `ClientSubmitPrompt`, and observes a completed result. That
  proves the WS-published metadata → Pulsar → coordinator-consumer →
  `ContextModelMap` → dispatcher model-id resolution path end to end on
  Linux GPU.
- the recorded cohort validation backend validation follow-on:
  `Infernix.Runtime.Pulsar.publishDemoClientMessage` now loads the active generated demo
  catalog before publishing `ClientCreateContext` and rejects model ids not present in that
  catalog with typed error code `unknown-model`. `Infernix.Demo.Api.mapDispatchError` preserves
  that code through the WebSocket `ServerError` response, `test/unit/Spec.hs` covers the pure
  catalog validation helper, and the routed Playwright WebSocket test sends an unknown model id
  and asserts the typed error.
- the recorded cohort validation shared-boundary validation follow-on:
  `src/Infernix/Lint/HaskellStyle.hs` now enforces the shared Phase 7 import boundary for the
  conversation primitives, dispatcher helpers, result bridge helper, and bootstrap helper. The
  mounted-source Linux GPU `infernix test lint` run passed.

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

The Haskell-side unit gate is implemented: `infernix test unit` covers 37 JSON encode/decode
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

The recorded validation pass closed the PureScript side of this sprint
together with Sprints 7.2 / 7.10 / 7.11:

- `web/test/Infernix/Web/ContractsSpec.purs` covers 43 Phase 7
  contract roundtrip cases — every string newtype, every record
  newtype, every nullary sum, every positional sum constructor, every
  record-syntax sum constructor across `ConversationStatePatch`,
  `ContextListPatch`, `DraftMapPatch`, `WsClientMessage`, and
  `WsServerMessage` — and asserts byte-identical re-encoding plus
  structural wire-shape spot checks (`"tag"`, `"contents"`, spread
  field names) so any future drift in the generator footer surfaces
  immediately.
- `web/test/Infernix/Web/ChatSpec.purs` covers 12 view-model cases:
  every `ConversationStatePatch` / `ContextListPatch` / `DraftMapPatch`
  variant's patch application, the WS `handleServerMessage`
  dispatcher (active-context match vs no-match), and the
  `pendingPromptCount` queued-prompt counter (empty, one queued, two
  queued, both resolved).
- `web/test/Infernix/Web/ArtifactsSpec.purs` covers 11 view-model
  cases: every MIME-to-disposition branch (image / audio / video /
  PDF / JSON / text / MIDI / MusicXML / unknown), library upsert with
  bucket+key matching, per-context filter, and the typed upload
  request shape.
- `test/unit/Spec.hs` covers the Haskell
  `Demo.Api.renderDispositionForMime` matrix used by
  `/api/objects/download`, keeping the server-side grant disposition
  aligned with the PureScript fallback.
- The generator footer in `src/Infernix/Web/Contracts.hs` emits
  hand-rolled Simple.JSON tagged-sum instances for every Phase 7 sum
  type, hand-rolled WriteForeign/ReadForeign for every Phase 7
  newtype (string-wrapped vs record-wrapped), and Show instances for
  every nullary sum (so the PS-side spec can use `shouldEqual` on
  them). `infernix test unit` reports 67/67 passing across the full
  PS suite + the Haskell-side unit suite.

Closure notes:

- QuickCheck-style property generators for `ConversationEvent` sequences implemented
  the recorded cohort validation (`assertConversationPropertyTests` in `test/unit/Spec.hs`):
  property generators emit arbitrary 0–8-message logs with prompt / cancel /
  inference-result / duplicate shapes and exercise three invariants — patch-stream
  replay converging to the snapshot reducer projection, `prefixHash` chain
  length-monotonicity + determinism, and idempotency dedup dropping repeated
  `(contextId, key)` pairs across 50 random shrinkable cases each. The
  `QuickCheck >=2.14 && <2.20` dep is now declared on the `infernix-unit` test
  stanza.

---

## Sprint 7.14: Integration-Layer Validation [Done]

**Status**: Done (code-side closed for WebSocket-to-Pulsar publish plumbing, the coordinator-to-engine handoff contract, real Pulsar Reader roundtrip coverage for conversation/contexts/drafts/bootstrap-ready topic families, broker compacted-reader latest-per-key coverage, real broker producer-dedup validation, the non-chaos dispatcher/result-bridge durable prompt roundtrip, the Apple `engine.lock` chaos case (Wave A.3 in [cohort-validation-waves.md](cohort-validation-waves.md)), and the Linux-owned Sprint 7.14 chaos/throughput block implemented on the recorded cohort validation: frontend pod replacement, coordinator pod replacement around durable prompt dispatch/writeback, engine pod replacement, engine node drain, model-bootstrap request/ready-event deduplication across coordinator replacement, Linux engine anti-affinity, and multi-user durable prompt throughput. Native `linux-cpu` `infernix test all` validation passed on the recorded cohort validation; `linux-gpu` `infernix test all` validation passed on the recorded cohort validation in [Wave C](cohort-validation-waves.md). The mounted Linux CPU `cabal test infernix-integration` rerun on the recorded cohort validation passed against the Sprint 7.8 runtime KV-cache and daemon-orchestration split worktree.)
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

the recorded cohort validation code-side implementation:

- `src/Infernix/Runtime/Pulsar.hs.publishDemoClientMessage` discovers the active Pulsar
  transport from mounted `ClusterConfig` (falling back through the existing transport discovery
  path), maps browser `WsClientMessage` frames to typed JSON events, and publishes them to the
  supported durable topic families:
  - `ClientSubmitPrompt` / `ClientCancelPrompt` → per-context
    `demo.conversation.<userId>.<contextId>`
  - `ClientUpdateDraft` → per-user compacted `demo.user.<userId>.drafts`
  - `ClientCreateContext` / `ClientRenameContext` / `ClientSoftDeleteContext` → per-user
    compacted `demo.user.<userId>.contexts`
- WebSocket producers use mutation-scoped one-message producer names and WebSocket
  `initialSequenceId` baselines derived from client idempotency, prompt, draft, or context keys
  so the broker-side dedup gate can collapse reconnect or retry duplicates without treating later
  independent client keys as non-monotonic repeats.
- `src/Infernix/Demo/WebSocket.hs` now dispatches through
  `WebSocketOptions.wsDispatchClientMessage`; `src/Infernix/Demo/Api.hs` wires that callback to
  `publishDemoClientMessage`.
- `test/unit/Spec.hs.assertDemoWebSocketPublicationPlanning` covers the pure publication plan for
  prompt, cancel, context-created, draft-update, hello, and subscribe frames.

the recorded cohort validation durable topic-family implementation:

- `src/Infernix/Runtime/Pulsar.hs` exposes `publishRawTopicPayload` and
  `readRawTopicPayloads` for integration-only broker probes and decodes Pulsar Reader
  envelopes with their broker message key (`key` / `partitionKey`) plus base64 payload.
- WebSocket publication planning now carries an optional Pulsar message key. Conversation events
  remain unkeyed append-only log entries; compacted contexts and drafts publish with message key
  `contextId`; `publishBootstrapReadyEvent` publishes bootstrap-ready records with message key
  `modelId`.
- `test/unit/Spec.hs.assertDemoWebSocketPublicationPlanning` asserts those key choices for
  conversation, context-created, and draft-update frames.
- `test/integration/Spec.hs.validateDurableTopicFamilyRoundTrips` publishes and reads back real
  broker records for:
  - `ClientCreateContext` -> `demo.user.<userId>.contexts`, asserting key `contextId` and a
    decoded `ContextCreated` payload
  - `ClientUpdateDraft` -> `demo.user.<userId>.drafts`, asserting key `contextId` and a decoded
    `DraftUpdated` payload
  - `ClientCancelPrompt` -> `demo.conversation.<userId>.<contextId>`, asserting no message key
    and a decoded `ConversationCancelEvent`
  - raw `ModelBootstrapReadyEvent` -> `model.bootstrap.ready.<modelId>`, asserting key
    `modelId` and a decoded ready event
- `test/integration/Spec.hs.validateCompactedTopicBrokerBehavior` reads the live
  `infernix/demo` compaction threshold through the Pulsar admin API, asserts the supported
  100 MiB policy, publishes superseded and latest records to isolated contexts and drafts
  topics, triggers topic compaction through the admin API, and uses a Java Pulsar client in the
  toolset pod with `readCompacted(true)` to assert exactly one latest payload per `contextId`.
  This closes Sprint 7.5's broker-side compaction validation gate.
- `test/integration/Spec.hs.validateProducerDeduplicationBehavior` publishes duplicate
  frontend messages with the same mutation-scoped producer name and WebSocket
  `initialSequenceId`-backed sequence id, then reads the isolated topics through a real Pulsar
  Reader. The append-only conversation topic stores exactly one duplicate cancel event, and the
  compacted draft topic stores exactly one duplicate draft event, proving the broker's
  producer-dedup gate for simulated frontend reconnects.
- `test/integration/Spec.hs.validateDurableContextPromptRoundTrip` publishes
  `ClientCreateContext`, creates the conversation topic with a no-op cancel, waits for dispatcher
  discovery, publishes `ClientSubmitPrompt`, and asserts the real broker conversation log receives
  a completed `ConversationInferenceResultEvent` with inline output. This proves the
  WS-published context metadata -> Pulsar -> coordinator contexts consumer ->
  `ContextModelMap` -> dispatcher model-id resolution path plus the non-chaos dispatcher ->
  request/batch -> engine -> result-bridge -> conversation-log path on Linux GPU. Frontend
  pod-kill reconnect coverage closed in the recorded cohort validation routed E2E pass, and coordinator
  replacement coverage closed in Wave C.

the recorded cohort validation Linux GPU validation implementation:

- `src/Infernix/Cluster.hs.cluster status` now includes
  `publicationHostInferenceBatchTopic` when the active publication state carries a configured
  batch handoff topic, so operators can see the same request -> batch split that
  `/api/publication` exposes.
- `test/integration/Spec.hs` now asserts the `hostInferenceBatchTopic` field in routed
  publication JSON for every runtime mode, asserts the matching
  `publicationHostInferenceBatchTopic` line in `cluster status`, and verifies the generated
  demo config routes the coordinator from the substrate request topic to the configured batch
  topic while the engine consumes that batch topic and keeps
  `daemonConfigHostBatchTopic = Nothing`.
- The Linux GPU launcher image was rebuilt with
  `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh build`, then validated with
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix test unit`,
  `... infernix test lint`, and `... infernix test integration`; all three commands exited
  zero. The integration run reached `cluster up complete`, exercised the linux-gpu
  per-model inference, cache lifecycle, and service runtime loops, then tore the cluster down
  cleanly with `cluster down complete`.
- The recorded validation mounted validation pass built and ran the updated library, unit tests,
  Haskell style gate, and integration suite inside the Linux GPU outer container. The clean
  baked-image pass
  rebuilt `infernix-linux-gpu:local` and then ran
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm infernix infernix test integration`;
  the integration run reached `integration-step: durable Pulsar topic families: linux-gpu` and
  then completed `cluster down complete`.
- A follow-on mounted Linux GPU validation on the recorded cohort validation added the compaction behavior proof
  above and passed `cabal test infernix-integration`; the passing run completed
  `integration tests passed` and `cluster down complete`.
- A later the recorded cohort validation mounted Linux GPU validation corrected the frontend producer-dedup wiring
  to use WebSocket `initialSequenceId` query parameters plus mutation-scoped producer names,
  hardened Docker Hub mirror fallback for multi-arch Harbor publication and Linux warmup image
  hydration, and passed:
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm --volume /home/matt/infernix:/workspace infernix cabal build test:infernix-unit test:infernix-integration`,
  `... cabal test infernix-unit`, `... cabal test infernix-haskell-style`, and
  `... cabal test infernix-integration`. The final integration run reached
  `integration-step: durable Pulsar topic families: linux-gpu`, completed the duplicate
  conversation/draft producer-dedup assertions, reported `integration tests passed`, and tore down
  with `cluster down complete`.
- A subsequent the recorded cohort validation mounted Linux GPU validation added the durable-context prompt
  roundtrip through the dispatcher and result bridge. It passed
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm --volume /home/matt/infernix:/workspace infernix cabal build test:infernix-integration`,
  `... cabal test infernix-haskell-style`, and `... cabal test infernix-integration`. The
  integration run submitted a real prompt, observed the completed conversation result event,
  reported `integration tests passed`, and tore down with `cluster down complete`.
- A the recorded cohort validation Linux/CUDA-host code-side implementation added the remaining Linux-owned Wave C
  integration cases to `test/integration/Spec.hs` and the supporting helpers in
  `src/Infernix/Runtime/Pulsar.hs` and `src/Infernix/Cluster.hs`:
  - `linux-cpu` now renders a two-worker Kind topology and two `infernix-engine` replicas;
    warmup and final Harbor-backed image preloads target every worker.
  - frontend pod replacement publishes a durable draft, deletes one `infernix-demo` pod,
    re-reads state through Pulsar, then submits a durable prompt and asserts exactly-one
    request/batch/result/conversation-result flow.
  - coordinator pod replacement and engine pod replacement submit durable prompts, replace a pod,
    wait for rollout, and assert completed writeback plus exactly-one broker pipeline counts.
  - engine node drain drains one ready engine node, proves the remaining engine still completes a
    durable prompt exactly once, then uncordons and waits for the HA shape to recover.
  - model-bootstrap dedup publishes duplicate bootstrap requests for an isolated model around
    coordinator replacement and asserts exactly one ready event on `model.bootstrap.ready.<model>`.
  - multi-user throughput uses a `ThroughputMatrix` parameter record with the integration-default
    compact matrix (3 users x 2 contexts x 2 prompts) and reports p95 completion latency while
    asserting exact prompt/result counts per context. Larger matrices can now run through
    `validateMultiUserDurablePromptThroughputWith` without rewriting the suite.
  - the mounted compile check
    `env LAUNCHER_IMAGE=infernix-linux-cpu:local docker compose --project-name infernix-linux-cpu --file compose.yaml run --rm --volume /home/matt/infernix:/workspace infernix cabal build test:infernix-integration`
    exits zero. The following full `linux-cpu` and `linux-gpu` `infernix test all` validations
    closed Wave C.
  - the first full `./bootstrap/linux-cpu.sh test` rerun on the recorded cohort validation passed rebuilt-image
    docs lint, Haskell style, Haskell unit, PureScript build, and web unit tests before failing
    in pre-scenario Harbor publication: the outer-container `skopeo copy` fallback used
    `127.0.0.1:30002`, which is launcher-container loopback, not the Kind control-plane
    NodePort. `src/Infernix/Cluster/PublishImages.hs` now routes only the `skopeo`
    destination transport ref through `harborApiHost`.
  - the next full `./bootstrap/linux-cpu.sh test` rerun on the recorded cohort validation passed docs lint,
    Haskell style, Haskell unit, PureScript build, web unit, and Harbor publication before
    stalling in Helm readiness because the host-mounted containerd registry-hosts file still
    targeted a stale `infernix-linux-gpu-80707-control-plane:30002` mirror. The root cause was
    the shared `./.build/kind/registry` path across CPU/GPU lanes plus the host-bind path skipping
    node priming. `src/Infernix/Cluster.hs` now scopes registry-hosts roots by runtime mode
    (`./.build/kind/<runtime-mode>/registry`) and always primes every Kind node's mounted
    `/etc/containerd/certs.d` namespace from the launcher-local hosts file after cluster create or
    reuse; checked-in Kind templates and docs were updated. The following rebuilt-image rerun
    verified the repaired hosts file on the CPU control-plane and both workers, completed
    `cluster up`, and reached the durable prompt integration assertions.
  - the latest full `./bootstrap/linux-cpu.sh test` rerun on the recorded cohort validation passed rebuilt-image
    docs lint, Haskell style, Haskell unit, PureScript build, web unit, Harbor publication,
    final Helm readiness, and `cluster up` before the prior durable-context prompt roundtrip
    failed because the first result written for that prompt was not `completed`. The code-side
    fix makes that roundtrip use the newer durable context helper that waits for the contexts
    metadata topic, waits one dispatcher-discovery cycle, captures the submitted prompt message
    id, and waits for the result payload for that exact prompt; the following rebuilt-image rerun
    advanced past this roundtrip.
  - the following rebuilt-image `./bootstrap/linux-cpu.sh test` rerun passed the durable prompt
    roundtrip, frontend pod replacement, and coordinator pod replacement checks, then failed at
    `integration-step: engine pod replacement preserves durable prompt result` because the exact
    prompt's conversation result payload was present but not `completed` (the assertion did not yet
    print the payload). The fix removes the dispatcher-side race that could publish an empty-model-id
    inference request before the contexts-metadata consumer hydrated `ContextModelMap`, commits the
    dispatcher reducer state only after the outbound inference request publish succeeds, and prints
    the full result payload on any chaos non-`completed` assertion.
  - the rebuilt-image rerun against the dispatcher race fix passed docs lint, Haskell style,
    Haskell unit, PureScript build, web unit, Harbor publication, final Helm readiness,
    `cluster up`, the durable prompt roundtrip, and reached `integration-step: frontend pod
    replacement preserves durable state`, then failed the new raw-topic exactly-once assertion:
    the prompt with Pulsar WebSocket message id `CNgBEAEwAA==` had one request and one batch but
    two raw inference results and two conversation results. The root cause is that
    `parseMessageIdToSequenceId` only handled colon-form Pulsar ids, so WebSocket base64 message
    ids produced no `initialSequenceId` and broker dedup could not collapse duplicate engine /
    result-bridge publishes. The code-side fix now parses Pulsar WebSocket base64 message ids,
    keeps the colon parser for compatibility, scopes coordinator batch and engine result producer
    names by context id, and adds unit coverage for the failed id shape. Mounted Linux
    outer-container `cabal build test:infernix-unit test:infernix-integration`,
    `cabal test infernix-unit`, `cabal test infernix-haskell-style`, and `infernix lint docs`
    pass.
  - the rebuilt-image `./bootstrap/linux-cpu.sh test` rerun then passed Haskell style, Haskell
    unit, PureScript build, web unit tests, full integration, every Sprint 7.14 LinuxCpu chaos
    scenario above, platform recovery checks, and routed Playwright E2E (7/7). The multi-user
    throughput smoke matrix reported `users=3 contextsPerUser=2 promptsPerContext=2
    totalPrompts=12 p95Seconds=78.95681428909302`; the passing launcher image digest was
    `sha256:a9f1f19aa9bb492c5186a0f6df8f864ee4e0c900c8209f0434ef64cf6cc821a7`.
  - the first full `./bootstrap/linux-gpu.sh test` attempt on the recorded cohort validation against rebuilt
    launcher image digest
    `sha256:1eb0863f8c7cbd19b4d87ab25796535ec592d19e965a1a54351d258d31c1c594`
    passed Haskell style, Haskell unit, PureScript build, web unit tests, full integration,
    and six of seven routed Playwright E2E specs. The remaining per-model smoke matrix spec
    failed after timing out waiting for an inbound WebSocket frame after frame index `78`;
    the cluster tore down cleanly.
  - the recorded cohort validation Playwright follow-on keeps the per-model browser matrix strict on completed
    inference results but replaces the generic 10-second inbound-frame wait with a five-minute
    completed-conversation-result wait, matching the integration first-run inference budget. It
    also fails early with the actual result payload when the backend returns `failed`. The rebuilt
    GPU launcher image carrying this fix has manifest-list digest
    `sha256:0cbd34f71a3a39b96e17740843b06d08a5c5e55096fd3f42f9f4e565d2a196a5`.
  - the fixed full `./bootstrap/linux-gpu.sh test` rerun passed Haskell style, Haskell unit,
    PureScript build, web unit tests, full integration, platform recovery checks, and routed
    Playwright E2E (7/7). The per-model browser matrix completed all 16 `linux-gpu` catalog
    rows in 7.9 minutes; the full Playwright file reported `7 passed (8.7m)`, and cluster
    teardown returned cleanly.
  - the final the recorded cohort validation `linux-gpu` closure rerun rebuilt the launcher after the browser-level
    frontend pod-replacement fixture implemented. The final image digest is
    `sha256:fd951113735f94b613a2fa014088f22e89a4df0b78193cd1ec76d6a44e191689`. The rebuilt-image
    `infernix lint docs` gate passed, then `./bootstrap/linux-gpu.sh test` passed Haskell style,
    Haskell unit, PureScript build, 71/71 web unit tests, full integration, platform recovery
    checks, and routed Playwright E2E. The artifact/chat browser test deleted all
    `infernix-demo` pods, waited for replacements, reconnected, resubscribed, and submitted
    another prompt in 40.4 seconds. The per-model browser matrix completed all 16 `linux-gpu`
    catalog rows in 2.2 minutes; the full Playwright file reported `7 passed (3.5m)`, and
    cluster teardown returned cleanly.
  - the recorded cohort validation residual sweep adds real deployed-Keycloak wrong-realm negative coverage in
    `web/playwright/inference.spec.js`: a token minted from the Keycloak admin realm is rejected
    with `401` by `/api/objects/upload`, and the same wrong-realm token cannot open the routed
    `/ws` WebSocket. Existing unit coverage still covers wrong issuer, wrong audience, expired,
    malformed, and unknown-key JWT cases at the validator layer.
  - the rebuilt-image `./bootstrap/linux-gpu.sh test` rerun after that residual sweep passed
    Haskell style, Python checks, Haskell unit, PureScript build, 71/71 web unit tests, full
    integration, platform recovery checks, and routed Playwright E2E (7/7). The browser suite
    included the wrong-realm `/api/objects/upload` and `/ws` negatives plus the fixture-backed
    artifact flow; the full file reported `7 passed (2.2m)`. The launcher image digest was
    `sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b`.
  - the matching rebuilt-image `./bootstrap/linux-cpu.sh build` completed on the recorded cohort validation against
    launcher image digest
    `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`. The subsequent
    `./bootstrap/linux-cpu.sh test` run passed Haskell style, Python checks, Haskell unit,
    PureScript build, 71/71 web unit tests, and the full integration suite, including the
    LinuxCpu chaos/throughput scenarios. The compact throughput matrix reported
    `users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12
    p95Seconds=74.05106592178345`. The run was paused at operator request during the following
    browser/e2e cluster bootstrap, before Playwright executed; `./bootstrap/linux-cpu.sh down`
    then removed the partially bootstrapped CPU Kind cluster.
  - the resumed rebuilt-image `./bootstrap/linux-cpu.sh test` run on the recorded cohort validation passed Haskell
    style, Python checks, Haskell unit, PureScript build, 71/71 web unit tests, full integration,
    platform recovery checks, and routed Playwright E2E (7/7) against the same launcher image
    digest. Integration included frontend pod replacement, coordinator replacement,
    engine replacement, engine node drain, model-bootstrap deduplication, Linux engine
    anti-affinity, multi-user durable prompt throughput, Harbor recovery, MinIO durability,
    routed Pulsar recovery, PostgreSQL failover, and PostgreSQL lifecycle rebinding. The compact
    throughput matrix reported `users=3 contextsPerUser=2 promptsPerContext=2 totalPrompts=12
    p95Seconds=76.06613969802856`. The Playwright file reported `7 passed (2.1m)`.

Closure notes: none.

---

## Sprint 7.15: E2E-Layer Validation [Done]

**Status**: Done (durable-context browser flow and per-model matrix are validated; browser-suite fixture extraction implemented on the recorded cohort validation and passed rebuilt-image `linux-gpu` validation against digest `sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b`; rebuilt-image `linux-cpu` validation passed through build, style/Python/unit/web-unit gates, full integration, and routed Playwright E2E (7/7) on the recorded cohort validation against digest `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`; Sprint 7.14 blocker closed on the recorded cohort validation.)
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
- `web/test/fixtures/` checked-in canonical inputs: `audio/short-speech.wav`,
  `audio/short-mix.wav`, `audio/short-pitch.wav`, `image/score-page.png`, `prompts/*.txt`

### Validation

- `infernix test e2e` runs the Playwright suite via the active substrate image's Playwright
  runtime
- per-model smoke matrix has one passing flow per non-`Not recommended` row in the README
  matrix for the active substrate; failure on any row fails the suite
- the Playwright source is byte-identical across `apple-silicon`, `linux-cpu`, `linux-gpu`;
  substrate selection lives only in the `.dhall` the demo app reads

### Remaining Work

the recorded validation partial implementation:

- `web/src/Main.purs` now mounts the durable-context shell, loads routed
  `/api/publication` and `/api/models`, renders platform summary state,
  and delegates the main panes to `Chat.renderChatView` and
  `Artifacts.renderArtifactsView`.
- `web/src/index.html` is no longer the workbench-oriented manual
  inference form. It is a dense app shell with Chat, Artifacts, route
  inventory, and runtime summary mount points.
- `web/test/Main.purs` no longer imports `Infernix.Web.Workbench` or
  asserts the prior direct `/api/inference` result framing. The unit
  surface now centers the generated contracts plus the Phase 7
  Chat/Artifacts/Contracts specs.
- `src/Infernix/CLI.hs.runPlaywrightWithFixture` invokes Playwright from the
  repo root with the explicit `web/playwright.config.js` path, and the config
  reads the typed fixture from `.data/runtime/playwright-fixture.json`.
- `web/playwright/inference.spec.js` is now the minimal routed
  SPA/publication smoke: it checks the typed fixture, `/api/publication`,
  `/api/demo-config`, `/api/models` parity, and the routed SPA root `h1`
  value `Infernix`.
- The same Playwright file now includes a routed Keycloak self-registration smoke: it starts an
  OIDC authorization-code + PKCE request at `/auth`, creates a fresh account without email
  verification, and asserts the redirect returns to the SPA with an authorization code and the
  original state.
- The same Playwright file now exchanges that authorization code through the routed
  `/auth/realms/infernix/protocol/openid-connect/token` endpoint, decodes the access-token
  subject, verifies a malformed bearer token is rejected by `/api/objects/upload`, then proves the
  real token can mint upload and download grants scoped under
  `infernix-demo-objects/users/<sub>/contexts/<contextId>/uploads/<displayName>`.
- The routed WebSocket Playwright flow opens `/ws?token=<real Keycloak access token>` from the
  browser and verifies the handshake succeeds, sends a malformed frame and asserts the tagged
  `ServerError` with `serverErrorErrorCode = "ws_frame_decode_failed"`, then verifies
  `/ws?token=not-a-real-token` does not open.
- The object-grant Playwright flow also PUTs bytes through the minted routed MinIO upload URL,
  mints a download grant for the same object, GETs the routed presigned URL, and asserts exact
  byte equality.
- The object-grant Playwright flow now also registers a second Keycloak user and reuses the same
  context id plus display name. The second user's grant points at that user's `sub` prefix, reads
  `404` before upload, reads the second user's bytes after upload, and leaves the first user's
  object readable through the first user's grant.
- The object-grant Playwright flow also validates the server-side
  `/api/objects/download` render-disposition matrix for image/audio/video inline grants,
  browser-native PDF grants, bounded JSON/text preview grants, and download-only MIDI /
  MusicXML / generic-binary grants.
- The browser artifact Playwright flow starts from the routed SPA login button, completes
  Keycloak self-registration through the app-owned PKCE redirect, creates a context, uploads text
  and JSON artifacts through the rendered form, previews both via routed presigned GETs, uploads
  PNG, WAV, MP4, PDF, MIDI, MusicXML, and generic binary artifacts through the same browser path,
  then verifies image/audio/video routed media URLs, PDF URL wiring, and download-only states for
  MIDI / MusicXML / generic binary artifacts.
- The same browser flow now asserts the socket's initial `ClientHello`, the inbound
  `ServerContextListSnapshot` and `ServerDraftMapSnapshot`, the context-create
  `ServerContextListPatch`, the draft `ServerDraftMapPatch` upsert emitted after typing in the
  prompt box, and the draft `ServerDraftMapPatch` remove emitted after prompt submit clears the
  durable draft.
- `web/src/Infernix/Web/Auth.js` now stores the Keycloak refresh token in memory, schedules
  access-token refresh before expiry, exposes the refresh path to the SPA session callback, and
  clears access token, refresh token, PKCE state, and timer state on local logout. The browser
  Playwright flow now proves local logout, same-browser re-login, and refresh-token WebSocket
  re-auth by asserting a new `ClientHello` after the manual refresh hook.
- `web/src/Main.purs` now owns generation-guarded WebSocket reconnect/reconstitution for
  authenticated sessions: unexpected close clears only the stale connection, schedules reconnect
  with bounded backoff, resends `ClientHello`, and re-sends `ClientSubscribeContext` for the
  active context. `web/src/Infernix/Web/WebSocket.purs` now sends multiple initial frames and
  reports close events to the session layer. The browser artifact Playwright flow force-closes
  the live socket, verifies reconnect plus active-context re-subscribe, receives a fresh
  `ServerConversationSnapshot`, and submits another prompt through the reconnected socket.
- `web/src/Infernix/Web/Chat.purs` now computes pending prompts by matching both inference
  result and cancel events against their target prompt ids, and exposes the latest unresolved
  prompt id for the browser cancel action. `web/src/Main.purs` no longer creates local
  optimistic cancel entries; it sends `ClientCancelPrompt` for the server-backed unresolved
  prompt id and waits for the conversation patch. The routed browser flow now asserts the cancel
  button sends `ClientCancelPrompt`, the backend returns a `ConversationCancelEvent` append
  patch, and the cancel entry renders for the canonical prompt id.
- `web/src/Main.purs` now stores the active context id/model id in browser session storage
  without persisting tokens, clears that state on logout, and includes the restored context in the
  initial WebSocket frame set after a reload login. The routed browser flow now proves an
  in-progress draft survives both a forced WebSocket reconnect and a full page reload plus
  Keycloak re-login by observing broker-backed `ServerDraftMapPatch` replay and the restored
  textarea value.
- `web/playwright/inference.spec.js` now submits a second prompt in the active context before
  the first unresolved prompt resolves, waits for the second canonical
  `ServerConversationPatch`, asserts the rendered `.chat-pending-indicator.warning` text is
  `2 queued prompts`, and then targets the second canonical prompt id in the cancel lifecycle.
- `web/playwright/inference.spec.js` now also checks each browser-uploaded artifact is visible
  in the active Chat conversation: it asserts the outbound `ClientRecordUpload`, the inbound
  `ConversationUserUploadEvent` append patch for the active context, and the rendered
  `.chat-message.upload` display name plus MIME type.
- `web/playwright/inference.spec.js` now exercises the rendered model picker before context
  creation: it selects a supported catalog option, asserts the outbound `ClientCreateContext`
  carries that `modelId`, verifies the matching `ClientSubscribeContext`, and confirms the
  broker-backed `ServerContextListPatch` plus active context rail preserve the same model id.
- `web/src/Infernix/Web/Chat.purs`, `web/src/Infernix/Web/DomEvents.purs`,
  `web/src/Infernix/Web/DomEvents.js`, and `web/src/Main.purs` now gate context creation behind a
  state-backed new-context dialog. The routed browser flow opens and closes the dialog, asserts
  that no `ClientCreateContext` frame or local context is created by close-without-confirmation,
  reopens it, selects a supported catalog model, and creates the context through the dialog action.
- The same files now render per-context rename inputs plus soft-delete actions, bind them through
  the SPA shell, and publish `ClientRenameContext` / `ClientSoftDeleteContext` over the active
  browser WebSocket. The routed browser flow asserts both outbound frames, the broker-backed
  `ServerContextListPatch` upserts, the updated title in the context rail, and
  `data-soft-deleted="true"` on the active context row.
- `src/Infernix/Runtime/Pulsar.hs` validates `ClientCreateContext` model ids against the active
  generated catalog before publishing, and `src/Infernix/Demo/Api.hs` maps the typed validation
  failure through WebSocket `ServerError` code `unknown-model`. `web/playwright/inference.spec.js`
  now sends an unknown model id over the routed authenticated WebSocket and asserts the typed
  backend rejection.
- The rebuilt Linux GPU launcher passed the mounted-source
  `env -i LAUNCHER_IMAGE=infernix-linux-gpu:local /usr/bin/docker compose --project-name infernix-linux-gpu --file compose.yaml run --rm --volume /home/matt/infernix:/workspace infernix cabal run infernix -- test e2e`
  on the recorded cohort validation against image manifest list
  `sha256:057ee5ee3e3d31f0598a010700b6b3c4a1e739425522d7a8d47afe362fb74649` with six
  Playwright tests passing, including the new-context dialog close-negative/create path,
  context rename/soft-delete frame and patch assertions, routed unknown-model
  `ClientCreateContext` backend rejection, routed expired-token WebSocket rejection, forced WebSocket
  close/reconnect, cancel lifecycle, draft reconnect/reload, and two-prompt queued indicator
  assertions plus conversation-visible upload event assertions and model-select
  `ClientCreateContext` / context-summary assertions inside the artifact/prompt browser flow,
  `cluster up complete`, and `cluster down complete`.
- The recorded validation mounted-source `linux-gpu` routed E2E rerun added browser-level frontend pod
  replacement coverage to the durable-context flow. The Playwright test deletes all current
  `infernix-demo` pods through the typed `infernix kubectl` fixture hook, waits for replacement
  pods to become ready, verifies `ClientHello` + active `ClientSubscribeContext` are resent,
  receives a fresh `ServerConversationSnapshot`, submits another prompt, and receives the
  corresponding `ServerConversationPatch`. The same mounted-source run passed the per-model
  browser matrix and reported `7 passed (2.6m)`. The final rebuilt-image
  `./bootstrap/linux-gpu.sh test` rerun repeated this browser-level pod-replacement coverage in
  the ordinary full gate: the artifact/chat test passed in 40.4 seconds, the per-model matrix
  passed in 2.2 minutes, and the file reported `7 passed (3.5m)`.
- The recorded validation residual sweep extracted the inline browser artifact payloads into
  `web/test/fixtures/artifactSamples.js` and imports them from
  `web/playwright/inference.spec.js`. The fixture module now owns the canonical text, JSON, PNG,
  WAV, MP4, PDF, MIDI, MusicXML, and generic-binary sample payloads used by the artifact flow and
  the per-model smoke matrix.
- The rebuilt-image `./bootstrap/linux-gpu.sh test` rerun after fixture extraction passed the
  fixture-backed artifact flow and the per-model browser matrix in the ordinary full gate. The
  Playwright file reported `7 passed (2.2m)` against launcher image digest
  `sha256:521a56ac6f79bf1ce5bc9d7dcd9c872e897ce4b4882661d4ada2f62faa108d7b`.
- The resumed rebuilt-image `./bootstrap/linux-cpu.sh test` rerun on the recorded cohort validation passed the
  fixture-backed artifact flow and the per-model browser matrix in the ordinary full CPU gate.
  The Playwright file reported `7 passed (2.1m)` against launcher image digest
  `sha256:dc0c003e7cc2f2e359a474fa5ddb522c8715d271e322534db7798f260e9747fa`.

Closure notes:

- Sprint 7.15 no longer has a rebuilt-image `linux-cpu` browser/e2e residual. The per-model smoke
  matrix is validated on Apple in Wave A.2, on `linux-gpu` in Wave C plus the residual full gate,
  and on rebuilt-image `linux-cpu` by the recorded cohort validation resumed full gate.

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

The recorded validation pass cleared the stale "Planned" / "today's repo still..."
framing across every governed doc and aligned the supported-target
language with the implemented behavior:

- `documents/engineering/object_storage.md` — `Current Status` now
  records the Sprint 7.7 retirement of `./.data/object-store/`,
  `objectStoreRoot`, the `s3://infernix-runtime/` URI scheme, and
  the placeholder MinIO buckets.
- `documents/engineering/storage_and_state.md` — owner table now
  names the supported MinIO buckets, the model-cache manifest
  location, and the prior object-store tree.
- `documents/engineering/model_lifecycle.md` — rules now describe
  the MinIO-backed model loader and the post-Sprint-7.7 worker
  envelope (no artifact-bundle paths).
- `documents/engineering/build_artifacts.md` — cache manifest
  location points at `./.data/runtime/model-cache/...`.
- `documents/engineering/implementation_boundaries.md` — Application
  Library Boundary section is no longer marked "Planned, Phase 7".
- `documents/architecture/runtime_modes.md` and
  `documents/architecture/daemon_topology.md` — Sprint 7.7 daemon
  split is recorded as implemented; cluster-daemon-to-host-daemon bridge
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
  as Phase 7 Sprint 7.9 implemented (no longer "Planned").
- `documents/reference/web_portal_surface.md` — "Durable Context
  Surface" section is no longer marked "Planned".
- `documents/operations/apple_silicon_runbook.md` — Apple lane
  daemon naming references the implemented `Coordinator` / `Engine`
  vocabulary instead of "after Sprint 7.7".
- `documents/operations/cluster_bootstrap_runbook.md` — "Durable-Context
  Demo Bring-Up" section names the implemented `linux-cpu` + `linux-gpu`
  validation passes.

the recorded cohort validation closure:

- governed durable-context and daemon-topology docs were realigned with the runtime KV-cache path
  and `Infernix.Runtime.Daemon` split;
- `DEVELOPMENT_PLAN/README.md`, this phase file, `system-components.md`, and
  `cohort-validation-waves.md` now record Sprint 7.8 and Phase 7 as closed;
- `infernix lint docs` exits zero through the Linux CPU outer-container context against this
  state.

---

## Sprint 7.17: Secrets-via-Files and Demo-Surface Retirement [Done]

**Status**: Done
**Implementation**: `dhall/InfernixSecrets.dhall`, `src/Infernix/SecretsConfig.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Demo/Auth.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Python.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/secret-cluster-secrets.yaml`, `chart/templates/keycloak/deployment.yaml` (KC_DB_* documented exception).
**Docs to update**: `documents/architecture/configuration_doctrine.md`, `documents/engineering/cluster_config_manifest.md`, `documents/tools/keycloak.md`, `documents/tools/minio.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the `InfernixSecrets.dhall` typed paths-only schema + matching Haskell reader. Retire
every `INFERNIX_KEYCLOAK_*` and `INFERNIX_MINIO_*` env-var consumer in favor of `ClusterConfig`
fields (for non-secret values) plus file-based Secret mounts (for credentials). Retire
`INFERNIX_POETRY_*` env reads. Mount `/etc/infernix/secrets/` on the demo pod from a Kubernetes
`Secret`; Keycloak's `KC_DB_*` upstream contract stays as the documented third-party exception.

### Deliverables

- `dhall/InfernixSecrets.dhall` schema with the `Minio`, `KeycloakAdmin`, `KeycloakDb`
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

- **`src/Infernix/Python.hs` env retirement — closed the recorded cohort validation.** The
  recorded cohort validation partial closed the @INFERNIX_POETRY_EXECUTABLE@ env
  override (replaced by `HostConfig.toolPaths.hostPoetry` via
  `pathsHostConfig paths`, with `onlyIfExists` guarding stale fixture
  paths). The Linux worker and Python-quality paths no longer inject
  Poetry virtualenv configuration through env (`python/poetry.toml`
  is the typed source). The Apple host adapter setup env handoff in
  `Engines/AppleSilicon.hs` closed during the recorded cohort validation. The remaining
  `POETRY_HOME` read and `PATH` lookup / mutation around the Apple
  Poetry bootstrap closed during the recorded cohort validation: `bootstrapPoetryOnAppleHost`
  now takes a `Paths` argument and routes through
  `HostConfig.hostFilesystem.hostHomeDirectory` for the Poetry install
  root and `HostConfig.toolPaths.hostPython3` for the bootstrap Python
  interpreter; `prependDirectoryToPath` / `activatePoetryExecutable` /
  `firstCompatibleCommandOnPath` are deleted, and downstream callers
  invoke Poetry through the absolute path returned by
  `ensurePoetryExecutable`. The
  `src/Infernix/Lint/HaskellStyle.hs.envFunctionExemptedFiles`
  exemption row for `src/Infernix/Python.hs` was deleted in the same
  change; the `bareNameProcExemptedFiles` list never carried a Python.hs
  row.
- **Linux validation — current closure in Wave C.** The governed
  `linux-cpu` and `linux-gpu` `infernix test all` passes validated the
  mounted `ClusterConfig` / `SecretsConfig` path, including the routed
  integration and Playwright layers, against live clusters.

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
  (`infernix-coordinator` + `infernix-engine` + demo-gated `infernix-demo`) and the supported
  MinIO-backed object-storage contract, with cleanup receipts held in
  `legacy-tracking-for-deletion.md`.
- Sprint 7.8/7.14/7.15/7.17 prose drops dated hardware proof points; cohort closure references
  remain.
- Per-sprint Validation sections retain test-name and gate references, drop daily proof points,
  and anchor on the canonical architecture documents.

### Validation

- The phase-specific lexical guard for unsupported historical-state vocabulary and dated
  proof-point prose returns no matches outside cleanup-ledger references.
- `infernix lint docs` exits zero against the rewritten prose.

### Remaining Work

None.

---

## Remaining Work

None. Sprints 7.1-7.18 are `Done`; Apple cohort gates closed in Waves A/A.1/A.2/A.3 and native
Linux/CUDA cohort validation closed in Wave C.

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
