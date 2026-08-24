# Cluster Bootstrap Runbook

**Status**: Authoritative source
**Referenced by**: [apple_silicon_runbook.md](apple_silicon_runbook.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Describe the supported cluster lifecycle and durable-state expectations.

## Bring-Up

- treat the supported `bootstrap/*.sh` entrypoints as restartable prerequisite reconcilers: when
  host preparation reports a required new shell or reboot boundary, rerun the same bootstrap
  command from the start after satisfying that boundary instead of continuing from a later direct
  `infernix` command
- after host prerequisites and the substrate-specific launcher are ready, bootstrap scripts invoke
  the matching `infernix` command; they do not directly create Kind clusters, apply Kubernetes
  manifests, run `kind`, `kubectl`, or `helm`, pull containers, or publish images
- on Linux substrates, the supported bootstrap invokes
  `docker compose run --rm infernix infernix <command>` and relies on that Compose-launched
  binary path to build or reuse the active launcher image, validate the initialized repo-root
  `./infernix.dhall`, and own the requested lifecycle command
- on every supported substrate, Kind or `nvkind` create or delete uses a transient
  execution-local scratch kubeconfig under the system temp directory; after cluster creation the
  lifecycle publishes the supported repo-local kubeconfig (`./.build/infernix.kubeconfig` on
  Apple, `./.data/runtime/infernix.kubeconfig` on Linux) and cleans stale repo-local lock
  artifacts automatically
- run `infernix cluster up`
- `infernix test integration`, `infernix test e2e`, and `infernix test all` are separate
  harness-owned workflows, not validation against the `OperatorOwned` cluster created by
  `cluster up`. Run governed `infernix cluster down` first when an operator cluster is live; the
  harness refuses that cluster rather than deleting it and then owns its own bring-up/teardown
- if retained Pulsar ZooKeeper state is self-inconsistent, `cluster up` logs a targeted Pulsar
  claim-root reset and retries once; treat that retry as explicit durability repair for the
  affected runtime lane because prior Pulsar message history there is discarded
- if Patroni PostgreSQL startup pods remain `Running` but fail Patroni readiness beyond the grace
  window, `cluster up` may recycle those startup pods with a non-waiting Kubernetes delete; treat
  the log as retained-state readiness repair while the lifecycle heartbeat continues
- Keycloak Patroni PostgreSQL claim roots are rebuildable: only after Kind deletion, and
  only from the detached local retained copy under a freshly proved `WriterQuiesced` lease, may the
  lifecycle scrub those roots before a later bring-up recreates them
- The registry's MinIO-backed `infernix-registry` bucket is also non-retained publication cache, not
  product data. The same post-delete `WriterQuiesced` scrub of the detached local copy may remove
  that bucket, its MinIO bucket metadata, and stale multipart/tmp upload working sets; the durable
  `infernix-models`, `infernix-engine-artifacts`, and `infernix-demo-objects` buckets stay retained.
- on the Apple host-native path, the command may reconcile Homebrew-managed `kind`, `kubectl`,
  and `helm` before it attempts the real Kind workflow, and verifies the selected ghcup-managed
  `ghc` and `cabal` executables before direct host build handoff. Exact tracked Haskell protobuf
  output means Homebrew `protoc` is not a prerequisite. Docker is a prerequisite boundary: the
  current Docker context must already point at a native arm64 daemon, and the repo must not create
  or switch Docker contexts, create a Colima VM, or use cross-architecture emulation
- on Apple, retained Kind state under `./.data/kind/apple-silicon/` is replayed into and out of
  the worker instead of being bind-mounted, so large retained state can make `cluster up` and
  `cluster down` slower than the Linux lanes even when the supported flow is healthy
- for `linux-gpu`, confirm the supported NVIDIA host satisfies the documented `nvidia-smi` and
  `docker run --gpus all` preflight contract before cluster creation
- for `linux-gpu`, also confirm the host filesystem has substantial free space before `cluster up`
  or `test all`; low disk headroom can make Kind-hosted BookKeeper ledger directories
  non-writable during the registry-backed rollout and prevent `infernix-coordinator` and
  `infernix-engine` readiness
- confirm that the chosen edge port, active runtime mode, repo-root runtime config, and publication
  details are printed
- when `cluster up` appears quiet, run `infernix cluster status` before abandoning it
- the supported progress surface reports `lifecycleStatus`, the active `lifecyclePhase`, the
  current `lifecycleDetail`, and heartbeat timestamps while `cluster up` or `cluster down` is
  still running
- the `lifecycleStatus`/`lifecyclePhase` field surface is moving under a typed `ClusterLifecycle`
  machine per [Managed State Transitions](../architecture/managed_state_transitions.md), which is
  the canonical home for that transition doctrine
- when no lifecycle action is running, the surface also reports the persisted `clusterOwner`
  (`OperatorOwned` or `HarnessOwned`) and can report a `mutation-incomplete` (dirty) `lifecyclePhase`
  instead of `steady-state`; a dirty phase means a killed `infernix test all` left its `HarnessOwned`
  cluster mid-mutation, and the next `cluster up` reconciles it
- treat elapsed wall time alone as insufficient evidence of failure; during the monitored
  subprocess phases, a heartbeat that continues to refresh roughly every 30 seconds indicates the
  supported path is still progressing
- the current monitored long-running subprocess phases are binary-owned lifecycle phases such as
  the shared runtime `docker build`, registry image publication, Kind-worker registry preload, and
  Apple retained-state replay steps
- registry image publication waits for registry readiness before Docker push attempts and retries
  transient push resets with bounded backoff; treat registry-reset logs during large image pushes
  as recoverable until the command exhausts that retry budget
- upstream multi-arch chart images may be published through the digest-pinned `skopeo copy`
  fallback when Docker's containerd image store leaves the original tag non-inspectable or
  non-taggable after a successful pull; the publisher reuses an already discovered linux/amd64
  digest when available so later Docker Hub manifest-rate limits do not force a second manifest
  request; this is expected recovery as long as registry pull verification succeeds for the
  resulting content-addressed tag
- repo-owned local images are published before third-party chart dependencies and re-tagged from
  their source image before each bounded push retry, so a missing transient target tag is
  recoverable while the source image remains present
- on the governed Apple lane, `infernix test all` may trigger multiple internal cluster bring-up
  or teardown cycles before the outer command returns; apply the same heartbeat-driven failure
  classification to those internal rounds
- on the real Kind path, confirm that the registry is the first deployed service on a pristine cluster
  and that only the storage the registry needs pulls from public container repositories before
  the registry is ready
- on supported Kind lanes, `cluster up` may hydrate missing Docker Hub warmup dependency images from
  `mirror.gcr.io`, tag them under the original chart reference, and stream warmup images into the
  worker before the Helm warmup pass by piping `docker image save` into
  `docker exec -i <worker> ctr --namespace=k8s.io images import -`; missing non-Docker-Hub
  host-cache entries fall back to normal chart pulls, and the flow intentionally avoids `docker cp`
  because CUDA-enabled Kind workers can reject copied paths through the NVIDIA runtime mount
  boundary
- after the registry is responsive, confirm that every remaining image is mirrored or published into
  the registry before its workload rolls out, including the active `infernix` runtime image on every
  substrate
- the supported registry-first bootstrap path does not use any helper-registry container or
  `./.build/kind/registry/localhost:30001` namespace; the in-cluster registry is the only registry once it
  becomes ready
- on the supported outer-container path, confirm that `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding that runtime image inside the
  launcher
- confirm that `cluster up` preloads registry-backed final image refs onto the Kind worker before the
  remaining cluster workloads begin their final rollout
- confirm that `infernix kubectl get pods -n platform` shows the Envoy Gateway data plane,
  the registry Deployment, the MinIO statefulset, the Pulsar statefulsets,
  the PostgreSQL operator-managed members, and the infernix-owned daemon set for the active
  shape: `infernix-coordinator` plus substrate-specific engine pools on production and demo
  deployments, with `infernix-demo` added only when `demo_ui = true`. On Linux, engine pools render
  as Kubernetes workloads. On Apple, engine members are host daemons outside the pod inventory. On
  `linux-gpu`, the Linux set includes the base `infernix-engine` Deployment plus zero-replica
  `infernix-engine-<engine>` per-engine Deployments for Python-native framework images; routed
  validation scales one per-engine deployment at a time on the single-GPU lane.
- confirm `infernix kubectl get deployments -n platform` returns `infernix-coordinator` and
  any Linux engine-pool Deployment set (and `infernix-demo` when `demo_ui = true`); under
  `demo_ui = false` the coordinator and engine pools remain present while demo-only workloads are
  absent
- confirm `infernix kubectl get pvc -A` returns no daemon PVCs — the `infernix-coordinator`,
  engine-role, and `infernix-demo` Deployments are PVC-free in the supported target
  shape. PVCs are still present for MinIO, Pulsar, and the operator-managed PostgreSQL
  clusters
- confirm `infernix kubectl get buckets` (or equivalent MinIO admin check) shows
  `infernix-models` and `infernix-engine-artifacts` always-on; when `demo_ui = true`, also shows
  `infernix-demo-objects`. The coordinator eagerly stages every model listed in the mounted
  `infernix.dhall`, and the `warm-model-cache` cluster-up barrier requires the corresponding
  `infernix-models/<modelId>/.ready` sentinels before bring-up completes. The per-inference
  bootstrap request path remains only a fallback for unexpected cache loss.
- on `apple-silicon`, confirm `infernix-coordinator` is present in Kind, the on-host engine
  daemon is running, and `/api/publication` reports `daemonLocation: cluster-pod`,
  `inferenceExecutorLocation: control-plane-host`, and the Apple batch topic
- confirm that `infernix kubectl get gatewayclass infernix-gateway` reports `Accepted=True`,
  `infernix kubectl -n platform get gateway infernix-edge` reports `Accepted=True` and
  `Programmed=True`, and `infernix kubectl -n platform get envoyproxy infernix-edge` is present
- when the active `.dhall` enables the demo UI (`demo_ui = True`), also confirm that
  `infernix-demo` is present; when it does not, confirm `infernix-demo` is absent
- when `demo_ui = True`, confirm `infernix-keycloak` is present, the Keycloak Patroni cluster is
  healthy, and `/auth` serves the routed Keycloak login page; the local demo default is one
  Keycloak application pod backed by its own PostgreSQL cluster
- confirm that `infernix kubectl get storageclass` shows only `infernix-manual`
- confirm routes with `infernix cluster status`
- inspect `./.data/runtime/publication.json` or `GET /api/publication` to confirm the routed
  publication contract matches `cluster status`, including separate daemon and inference-executor
  locations on Apple
- inspect the real ConfigMap with `infernix kubectl get configmap infernix-demo-config -n platform -o yaml`

<!-- infernix:route-registry:cluster-bootstrap:start -->
- `curl http://127.0.0.1:<port>/registry/` checks the `/registry -> /v2` rewrite into the in-cluster registry Service.
- `curl http://127.0.0.1:<port>/registry/_catalog` lists the published repositories through the same rewrite.
- `curl http://127.0.0.1:<port>/pulsar/admin/admin/v2/clusters` checks the `/pulsar/admin -> /` rewrite into Pulsar's `/admin/v2` surface.
- `curl http://127.0.0.1:<port>/pulsar/ws/v2/producer/infernix/demo/demo` checks the `/pulsar/ws -> /ws` rewrite and returns `405 Method Not Allowed` on the real cluster path.
<!-- infernix:route-registry:cluster-bootstrap:end -->

Those probes validate the real Gateway-backed upstream responses only; direct `infernix-demo`
execution is not a supported compatibility fallback for the registry, MinIO, or Pulsar tool routes.

## Repo-Local Lifecycle State

`cluster up` persists two host-side port selections under `./.data/runtime/` so subsequent
reconciles stay deterministic:

- `./.data/runtime/edge-port.json` — the Envoy Gateway hostPort the routed edge listens on.
  Selected by `chooseEdgePort` starting at `9090`; reused on subsequent runs when still free.
- `./.data/runtime/registry-port.json` — the Kind hostPort observed from the operator host
  for the registry. Selected by `chooseRegistryPort` starting at `30002`; reused on subsequent runs
  when still free. The in-cluster Kubernetes NodePort stays fixed at `30002`; only the
  host-side mapping is dynamic, so operators with unrelated processes on `30002` (e.g. an
  editor's debug worker) see `cluster up` select `30003` or higher automatically.

Both ports appear in `cluster status` (`edgePort`, `registryPort`) alongside `lifecyclePhase`
and the heartbeat surface. See [../tools/registry.md](../tools/registry.md) for the registry
host-port contract.

## Warning Classification

Lifecycle warning handling follows one rule: eliminate warnings that are under repository control,
and document only warnings that come from upstream tool behavior, container-build packaging
constraints, or normal Kubernetes convergence.

| Warning or event | Classification | Operator guidance |
|------------------|----------------|-------------------|
| `nvkind hit its known configmap persistence bug (nvkind reported: …)` | Recoverable only when the cluster was actually created and the repo-owned Linux GPU node bootstrap finishes | Treat as handled when `cluster up complete` follows. The warning carries the first line of the raw `nvkind` error in parentheses for triage. Treat as fatal if the command exits non-zero, if the cluster was not created (the failure then names the known bug and states the cluster was not created), or if the repo-owned `linux-gpu` node bootstrap fails (the failure then states it failed after working around the `nvkind` bug). This warning remains documented because the repository can work around the `nvkind` bug but cannot remove the upstream `nvkind` failure mode by itself. |
| registry, MinIO, PostgreSQL, or Pulsar readiness probe failures, startup `BackOff`, volume-binding races, or early scheduling warnings | Normal Kubernetes convergence during bootstrap, retained-state repair, image swap, or final rollout | Treat as recoverable while `cluster up`, `test integration`, `test e2e`, or `test all` is still active and the lifecycle heartbeat continues. Treat as failure when the owning command exits non-zero, the heartbeat stops refreshing across multiple monitor intervals, or pods remain unready after the command reports completion. |
| Long Docker builds, host-cached warmup image streaming, registry image publication, or Kind-worker registry image preload | Expected long-running lifecycle work, especially on cold `linux-gpu` runs and during large Pulsar or runtime-image publication | Use `infernix cluster status` and its `lifecycleStatus`, `lifecyclePhase`, `lifecycleDetail`, and `lifecycleHeartbeatAt` fields before abandoning the run. Elapsed wall time alone is not evidence of failure. |
| Patroni PostgreSQL startup-pod recycle during retained-state repair | Recoverable readiness repair when startup pods keep running but do not satisfy Patroni readiness | Treat the logged recycle as informational while the lifecycle heartbeat continues. The delete is intentionally non-waiting so StatefulSet pod-name reuse cannot block the lifecycle. |
| `SystemOOM` events naming unrelated host processes | Host resource contention, not an accepted product warning | Stop unrelated memory-heavy workloads, increase memory or swap, and rerun the lifecycle. Repeated `SystemOOM` on an otherwise idle supported host is actionable environment failure even when the current run eventually passes. |
| Docker Compose warning that Bake is configured but buildx is missing | Tooling regression | The host bootstrap installs `docker-buildx-plugin`, and the Linux substrate image installs `docker-buildx`. Rebuild the substrate image. If a source-built image reproduces the warning, treat it as a regression to fix rather than accepted lifecycle noise. |
| GHCup `[ Warn ] No GHCup update available` during `get-ghcup` bootstrap | Upstream bootstrap no-op warning | The upstream installer runs `ghcup upgrade` after downloading the current `ghcup` binary and reports the no-op through its warning channel. Accept only when the pinned `ghc`, pinned `cabal`, and formatter `ghc` installs complete and the image build exits zero. Do not replace the supported `ghcup` path just to hide this upstream no-op. |
| GHCup advice to adjust `PATH` during Linux substrate image build | Upstream installer guidance in a noninteractive image build | The Dockerfile deliberately prevents shell profile edits and owns `PATH` through Docker `ENV`. Accept the advice text only when subsequent `ghcup`, `ghc`, and `cabal` commands in the same image build succeed and the final image contains `/root/.ghcup/bin` and `/root/.cabal/bin` on `PATH`. |
| GHCup `Couldn't figure out login shell!` during Linux substrate image build | Substrate image-layout regression | The Linux Dockerfile leaves `BOOTSTRAP_HASKELL_ADJUST_BASHRC` unset and sets the toolchain `PATH` explicitly with Docker `ENV`. If this message returns from a freshly built image, fix the image environment instead of accepting it as bootstrap noise. |
| npm deprecation warnings from the web or Playwright toolchain | Dependency hygiene regression unless tied to a newly documented upstream constraint | The current web install avoids the legacy `purescript` npm installer, installs `purs` from the official PureScript release archive, runs Spago 1.x, overrides Spago's transitive `glob` to `glob@13.0.6`, and disables npm's update notifier in supported image builds. New deprecation warnings should be resolved by maintained upgrades or explicitly documented with validation evidence. |
| npm update notices during supported image builds | Substrate image-layout regression | The Linux substrate image sets `NPM_CONFIG_UPDATE_NOTIFIER=false`; npm version changes should come through the supported Node/npm image toolchain update path, not ad hoc notices during lifecycle runs. |
| Playwright build error `Cannot find module '/workspace/web/scripts/install-purescript.mjs'` | Toolchain-image regression, not accepted warning noise | The Linux substrate Dockerfile must copy `web/scripts/` before npm `postinstall` runs because the web toolchain installs `purs` through `web/scripts/install-purescript.mjs`. Rebuild the Linux substrate image; fix the Dockerfile if a source-built image reproduces the error. |
| Python `pip` warning about running as root during Linux substrate image build | Substrate image-layout regression | The Linux substrate image installs Poetry into `/opt/poetry`, a dedicated virtual environment, instead of using system pip as root. If a root-pip warning returns, treat it as image-layout drift; do not treat it as permission to run host adapter setup as root. |
| `update-alternatives` warnings about missing manpage symlinks during apt installs | Debian package metadata noise | Accept only when the package install and image build exit zero. These warnings are not eliminated by application code because they come from upstream package metadata in the base image. |

## Retained Snapshot Transactions

Apple and any other non-bind Kind lane keep a detached retained snapshot under
`./.data/kind/<runtime-mode>`. Teardown pauses every workload-capable worker, rechecks the
PVC-to-node binding map, copies every retained claim into a fresh `.incoming` tree, marks the
staging tree complete, and atomically commits it while preserving the prior tree as `.previous`.
Kind deletion occurs while the frozen-source lease is still held. After deletion,
`WriterQuiesced` permits only the explicit rebuildable scrub set in that detached local copy:
the Keycloak Patroni root and the MinIO `infernix-registry` bucket internals.
Retained MinIO model/demo-object data and Pulsar data remain durable.

### One-time MinIO layout migration

A cluster created before the single-instance platform topology holds its MinIO data in the
erasure-coded distributed layout that four instances produced. One instance uses a plain backend
directory instead, and the two layouts are not interchangeable, so retained MinIO data does **not**
survive this migration even though the snapshot machinery above copies it faithfully. The supported
migration is a teardown and rebuild:

```bash
infernix cluster down
infernix cluster up
```

`infernix-models` is repopulated by the coordinator's eager staging at startup and
`infernix-engine-artifacts` by the next materialization, so both recover without operator action.
`infernix-demo-objects` — user uploads and generated artifacts — is **lost**; export anything that
matters first. This is a reduction in what an in-place upgrade can do, and it applies once. See
[../tools/minio.md](../tools/minio.md).

On the next absent-cluster bring-up, the lifecycle lock and a freshly rechecked
`WriterQuiesced` lease reconcile `.incoming` / `.previous` residue before claim preparation. A
complete initial `.incoming` may be promoted; a partial unmarked tree is discarded; `.previous`
restores the last committed snapshot when the current root is absent.

Before first Kind creation the state machine persists the exact
`replay-retained-state-into-kind` intent and keeps it through worker copy and claim preparation.
A killed bring-up with a live pre-workload Kind cluster resumes only from that exact owner/runtime
intent. A live non-bind cluster with missing, legacy, or mismatched replay evidence fails closed.
An unreadable Kind kubeconfig permits delete/recreate without copy-back only when the private
recovery proof revalidates that exact pending pre-workload intent under the lifecycle lock;
ordinary live clusters are left untouched. Do not manually promote, delete, or combine snapshot
transaction roots while either lifecycle command is active.

## Teardown

- run `infernix cluster down`
- when using `bootstrap/*.sh down`, expect the shell script to delegate to the binary teardown
  path only; it deletes the cluster and must preserve `./.build/`, `./.data/`, the host-level
  container build, the Apple host binary, and installed Docker or CUDA prerequisites
- the same scratch-kubeconfig policy applies during teardown: Kind delete does not depend on the
  durable repo-local kubeconfig path or its transient lock artifacts
- Kind delete uses the generated ten-minute total policy (three attempts, two-second backoff,
  idempotent-absence classification) with no caller retry loop. The binary revalidates the global
  inventory and owner/runtime authority immediately before normal or recovery deletion; unreadable
  pre-workload recovery also rechecks the exact retained-replay intent. A terminal non-zero is
  treated as success only when the bounded readiness probe observes that the cluster is absent
- on Apple, expect teardown to copy retained Kind claim data back out of the worker before the
  cluster disappears when durable state exists
- when teardown looks quiet, use `infernix cluster status` to confirm whether the active phase is
  still `replay-retained-state` or has advanced to `delete-kind-cluster`
- a run killed mid-teardown or mid-mutation is detectable rather than silent: `cluster status`
  reports the `mutation-incomplete` (dirty) phase and the persisted `clusterOwner`, and the next
  `cluster up` reconciles the leftover state — see
  [Managed State Transitions](../architecture/managed_state_transitions.md)
- expect retained durable state under `./.data/` to remain intact; the named rebuildable
  registry/Patroni subset above may be removed after writer quiescence and recreated on bring-up

### Cluster reuse across checkouts on one host

The Kind cluster is named `infernix-<runtime>` on the shared Docker daemon, so it is
machine-global, while the lifecycle lock, the harness reservation, and the persisted state are
repo-local. The creating checkout's host-side repository root is recorded on the
cluster itself, inside the control-plane node at `/etc/infernix/cluster-checkout-identity`, and
every ownership decision reads it back and requires agreement.

What operators will see:

- `infernix cluster up` and `infernix cluster down` in the checkout that created the cluster behave
  exactly as before
- any operation from a *different* checkout is refused, naming the checkout that created the
  cluster: `the live cluster was created by the checkout at <path>, not by this one`. Tear it down
  from that checkout, or remove it with `kind delete cluster`
- a cluster created **before** this identity existed carries no marker. `infernix cluster up`
  adopts it into the current checkout and stamps the marker; `infernix cluster down` removes it as
  before. `infernix test all` refuses it, because the harness must prove the cluster is its own
  before tearing it down — the refusal names both remedies. This is a one-time step after
  upgrading; every cluster created since is stamped at creation
- a cluster whose control-plane container is missing or unreadable is treated the same as an
  unidentified one, and for the same reason: the read is what proves ownership, so an unreadable
  resource proves nothing
- if the identity cannot be recorded during adoption, bring-up prints a warning and continues; the
  cluster stays unidentified, so `infernix test all` will keep refusing it until a later
  `cluster up` succeeds in stamping it

Inside a Linux launcher container the identity is the host-side bind-mount source, not the
container-internal `/workspace`, because every launcher container is baked with the same
in-container repo root. If that translation cannot be resolved, the command fails closed rather
than claiming a colliding identity.

## Durable-Context Demo Bring-Up

When the active substrate's generated `.dhall` carries `demo_ui = true`, `cluster up`
performs the following additional reconciliation steps:

- deploys a Keycloak Helm release together with its dedicated Patroni Postgres cluster managed
  by the Percona operator; expects the registry to be responsive first, then the Keycloak Patroni
  cluster to report ready, then Keycloak itself
- idempotently imports the demo realm with self-signup on and email verification off via
  Keycloak's native `--import-realm` flag against the mounted ConfigMap; reruns are no-ops
  because Keycloak skips re-importing an existing realm
- creates the always-on `infernix-models` MinIO bucket plus the demo-gated
  `infernix-demo-objects` MinIO bucket through the chart-time MinIO provisioner
- reconciles the supported `infernix` Pulsar tenant plus the `infernix/system` and
  `infernix/demo` namespaces, sets the 100 MiB compaction threshold on `infernix/demo`,
  enables broker-side deduplication on both namespaces, and creates the
  `persistent://infernix/system/model.bootstrap.request` topic via the Pulsar admin REST
  API before schema registration; see `reconcileSupportedNamespaces` in
  `src/Infernix/Runtime/Pulsar.hs`
- registers schemas for `ConversationEvent`, `ContextMetadataEvent`, `DraftEvent`, and the
  inference request and result envelopes via the Pulsar admin API

Warning classification stays consistent with the rest of this runbook: slow Keycloak realm
import or initial Patroni instance bootstrap is healthy convergence as long as the lifecycle
heartbeat continues to update. When `demo_ui = false`, none of the above steps run and the
Keycloak release, demo MinIO bucket, and demo Pulsar namespaces are absent from the cluster.

See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) and
[../tools/keycloak.md](../tools/keycloak.md) for the full contract.

## Validation Selection

Lifecycle validation follows the selected-accelerator contract in
[../engineering/testing.md](../engineering/testing.md): one accelerator plus `linux-cpu` for a
must-pass gate, with separate evidence required for any cross-accelerator claim.

## Cross-References

- [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
- [../tools/keycloak.md](../tools/keycloak.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
