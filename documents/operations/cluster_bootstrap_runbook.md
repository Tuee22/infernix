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
  binary path to build or reuse the active launcher image, stage or validate substrate state, and
  own the requested lifecycle command
- on every supported substrate, Kind or `nvkind` create or delete uses a transient
  execution-local scratch kubeconfig under the system temp directory; after cluster creation the
  lifecycle publishes the supported repo-local kubeconfig (`./.build/infernix.kubeconfig` on
  Apple, `./.data/runtime/infernix.kubeconfig` on Linux) and cleans stale repo-local lock
  artifacts automatically
- run `infernix cluster up`
- if retained Pulsar ZooKeeper state is self-inconsistent, `cluster up` logs a targeted Pulsar
  claim-root reset and retries once; treat that retry as explicit durability repair for the
  affected runtime lane because prior Pulsar message history there is discarded
- if retained Harbor PostgreSQL replicas stay stopped after leader promotion, `cluster up` may
  log a targeted Patroni replica reinitialization from the current leader and wait for those
  replicas to resync; treat that as supported retained-state repair rather than hard bootstrap
  failure
- if the retained Harbor PostgreSQL Patroni reinitialization command itself fails because the
  upstream CLI or pod runtime throws during the repair attempt, `cluster up` logs the failure and
  continues the rollout wait; classify the repair attempt as recoverable unless the owning
  lifecycle command exits non-zero or reports completion with Harbor still unready
- on the Apple host-native path, the command may reconcile Homebrew-managed `kind`, `kubectl`,
  and `helm` before it attempts the real Kind workflow, and verifies the selected ghcup-managed
  `ghc` and `cabal` executables plus Homebrew `protoc` before direct host build handoff. Docker
  is a prerequisite boundary: the current Docker context must already point at a native arm64
  daemon, and the repo must not create or switch Docker contexts, create a Colima VM, or use
  cross-architecture emulation
- on Apple, retained Kind state under `./.data/kind/apple-silicon/` is replayed into and out of
  the worker instead of being bind-mounted, so large retained state can make `cluster up` and
  `cluster down` slower than the Linux lanes even when the supported flow is healthy
- current Apple validation evidence is recorded in
  [../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md);
  the legacy-tracking ledger at
  [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
  records obsolete-surface receipts
- for `linux-gpu`, confirm the supported NVIDIA host satisfies the documented `nvidia-smi` and
  `docker run --gpus all` preflight contract before cluster creation
- for `linux-gpu`, also confirm the host filesystem has substantial free space before `cluster up`
  or `test all`; low disk headroom can make Kind-hosted BookKeeper ledger directories
  non-writable during the Harbor-backed rollout and prevent `infernix-coordinator` and
  `infernix-engine` readiness
- confirm that the chosen edge port, active runtime mode, generated demo-config paths, and
  build-root publication details are printed
- when `cluster up` appears quiet, run `infernix cluster status` before abandoning it
- the supported progress surface reports `lifecycleStatus`, the active `lifecyclePhase`, the
  current `lifecycleDetail`, and heartbeat timestamps while `cluster up` or `cluster down` is
  still running
- treat elapsed wall time alone as insufficient evidence of failure; during the monitored
  subprocess phases, a heartbeat that continues to refresh roughly every 30 seconds indicates the
  supported path is still progressing
- the current monitored long-running subprocess phases are binary-owned lifecycle phases such as
  the shared runtime `docker build`, Harbor image publication, Kind-worker Harbor preload, and
  Apple retained-state replay steps
- Harbor image publication waits for registry readiness before Docker push attempts and retries
  transient push resets with bounded backoff; treat registry-reset logs during large image pushes
  as recoverable until the command exhausts that retry budget
- upstream multi-arch chart images may be published through the digest-pinned `skopeo copy`
  fallback when Docker's containerd image store leaves the original tag non-inspectable or
  non-taggable after a successful pull; the publisher reuses an already discovered linux/amd64
  digest when available so later Docker Hub manifest-rate limits do not force a second manifest
  request; this is expected recovery as long as Harbor pull verification succeeds for the
  resulting content-addressed tag
- repo-owned local images are published before third-party chart dependencies and re-tagged from
  their source image before each bounded push retry, so a missing transient target tag is
  recoverable while the source image remains present
- on the governed Apple lane, `infernix test all` may trigger multiple internal cluster bring-up
  or teardown cycles before the outer command returns; apply the same heartbeat-driven failure
  classification to those internal rounds
- on the real Kind path, confirm that Harbor is the first deployed service on a pristine cluster
  and that only Harbor-required backend services pull from public container repositories before
  Harbor is ready
- on Linux Kind lanes, `cluster up` may hydrate missing Docker Hub warmup dependency images from
  `mirror.gcr.io`, tag them under the original chart reference, and stream warmup images into the
  worker before the Helm warmup pass by piping `docker image save` into
  `docker exec -i <worker> ctr --namespace=k8s.io images import -`; missing non-Docker-Hub
  host-cache entries fall back to normal chart pulls, and the flow intentionally avoids `docker cp`
  because CUDA-enabled Kind workers can reject copied paths through the NVIDIA runtime mount
  boundary
- after Harbor is responsive, confirm that every remaining image is mirrored or published into
  Harbor before its workload rolls out, including the active `infernix` runtime image on every
  substrate
- the supported Harbor-first bootstrap path does not use any helper-registry container or
  `./.build/kind/registry/localhost:30001` namespace; Harbor itself is the only registry once it
  becomes ready
- on the supported outer-container path, confirm that `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding that runtime image inside the
  launcher
- confirm that `cluster up` preloads Harbor-backed final image refs onto the Kind worker before the
  remaining non-Harbor workloads begin their final rollout
- confirm that `infernix kubectl get pods -n platform` shows the Envoy Gateway data plane,
  the Harbor application-plane workloads, the MinIO statefulset, the Pulsar statefulsets,
  the PostgreSQL operator-managed members, and the infernix-owned daemon set for the active
  shape: `infernix-coordinator` plus `infernix-engine` when `demo_ui = true`, and only
  `infernix-engine` when `demo_ui = false`
- confirm `infernix kubectl get deployments -n platform` returns `infernix-coordinator` and
  `infernix-engine` (and `infernix-demo` when `demo_ui = true`); under `demo_ui = false` only
  `infernix-engine` is present
- confirm `infernix kubectl get pvc -A` returns no daemon PVCs — the `infernix-coordinator`,
  `infernix-engine`, and `infernix-demo` Deployments are PVC-free in the supported target
  shape. PVCs are still present for Harbor, MinIO, Pulsar, and the operator-managed PostgreSQL
  clusters
- confirm `infernix kubectl get buckets` (or equivalent MinIO admin check) shows
  `infernix-models` always-on; when `demo_ui = true`, also shows `infernix-demo-objects`.
  Lazy first-use bootstrap means `infernix-models` may be empty immediately after `cluster
  up`; the first inference request for a given model triggers the coordinator's bootstrap
  workflow and the model's files plus `.ready` sentinel appear under `infernix-models/<modelId>/`
  shortly afterward (latency bounded by upstream download speed)
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
  Keycloak application pod backed by HA Patroni Postgres
- confirm that `infernix kubectl get storageclass` shows only `infernix-manual`
- confirm routes with `infernix cluster status`
- inspect `./.data/runtime/publication.json` or `GET /api/publication` to confirm the routed
  publication contract matches `cluster status`, including separate daemon and inference-executor
  locations on Apple
- inspect the real ConfigMap with `infernix kubectl get configmap infernix-demo-config -n platform -o yaml`

<!-- infernix:route-registry:cluster-bootstrap:start -->
- `curl http://127.0.0.1:<port>/harbor` checks the Harbor portal route.
- `curl http://127.0.0.1:<port>/harbor/api/v2.0/projects` checks the `/harbor/api -> /api` rewrite into the Harbor core service.
- `curl http://127.0.0.1:<port>/minio/s3/models/demo.bin` checks the `/minio/s3 -> /` rewrite into the MinIO S3 service.
- `curl http://127.0.0.1:<port>/pulsar/admin/admin/v2/clusters` checks the `/pulsar/admin -> /` rewrite into Pulsar's `/admin/v2` surface.
- `curl http://127.0.0.1:<port>/pulsar/ws/v2/producer/infernix/demo/demo` checks the `/pulsar/ws -> /ws` rewrite and returns `405 Method Not Allowed` on the real cluster path.
<!-- infernix:route-registry:cluster-bootstrap:end -->

Those probes validate the real Gateway-backed upstream responses only; direct `infernix-demo`
execution is not a supported compatibility fallback for the Harbor, MinIO, or Pulsar tool routes.

## Repo-Local Lifecycle State

`cluster up` persists two host-side port selections under `./.data/runtime/` so subsequent
reconciles stay deterministic:

- `./.data/runtime/edge-port.json` — the Envoy Gateway hostPort the routed edge listens on.
  Selected by `chooseEdgePort` starting at `9090`; reused on subsequent runs when still free.
- `./.data/runtime/harbor-port.json` — the Kind hostPort observed from the operator host
  for Harbor. Selected by `chooseHarborPort` starting at `30002`; reused on subsequent runs
  when still free. The in-cluster Kubernetes NodePort stays fixed at `30002`; only the
  host-side mapping is dynamic, so operators with unrelated processes on `30002` (e.g. an
  editor's debug worker) see `cluster up` select `30003` or higher automatically.

Both ports appear in `cluster status` (`edgePort`, `harborPort`) alongside `lifecyclePhase`
and the heartbeat surface. See [../tools/harbor.md](../tools/harbor.md) for the Harbor
host-port contract.

## Warning Classification

Lifecycle warning handling follows one rule: eliminate warnings that are under repository control,
and document only warnings that come from upstream tool behavior, container-build packaging
constraints, or normal Kubernetes convergence.

| Warning or event | Classification | Operator guidance |
|------------------|----------------|-------------------|
| `nvkind hit its known configmap persistence bug` | Recoverable only when the cluster was actually created and the repo-owned Linux GPU node bootstrap finishes | Treat as handled when `cluster up complete` follows. Treat as fatal if the command exits non-zero, if the cluster was not created, or if later `linux-gpu` node setup fails. This warning remains documented because the repository can work around the `nvkind` bug but cannot remove the upstream `nvkind` failure mode by itself. |
| Harbor, MinIO, PostgreSQL, or Pulsar readiness probe failures, startup `BackOff`, volume-binding races, or early scheduling warnings | Normal Kubernetes convergence during bootstrap, retained-state repair, image swap, or final rollout | Treat as recoverable while `cluster up`, `test integration`, `test e2e`, or `test all` is still active and the lifecycle heartbeat continues. Treat as failure when the owning command exits non-zero, the heartbeat stops refreshing across multiple monitor intervals, or pods remain unready after the command reports completion. |
| Long Docker builds, host-cached warmup image streaming, Harbor image publication, or Kind-worker Harbor image preload | Expected long-running lifecycle work, especially on cold `linux-gpu` runs and during large Pulsar or runtime-image publication | Use `infernix cluster status` and its `lifecycleStatus`, `lifecyclePhase`, `lifecycleDetail`, and `lifecycleHeartbeatAt` fields before abandoning the run. Elapsed wall time alone is not evidence of failure. |
| Harbor PostgreSQL Patroni replica reinitialization command failure during retained-state repair | Recoverable retained-state repair fallback when the lifecycle continues waiting for Harbor readiness | Treat the logged repair-command exception as informational if the surrounding lifecycle later reaches `cluster up complete`. Treat it as actionable only when the owning command exits non-zero or Harbor remains unready after completion. |
| `SystemOOM` events naming unrelated host processes | Host resource contention, not an accepted product warning | Stop unrelated memory-heavy workloads, increase memory or swap, and rerun the lifecycle. Repeated `SystemOOM` on an otherwise idle supported host is actionable environment failure even when the current run eventually passes. |
| Docker Compose warning that Bake is configured but buildx is missing | Tooling regression after the substrate-image buildx fix | The host bootstrap installs `docker-buildx-plugin`, and the Linux substrate image installs `docker-buildx`. Rebuild the substrate image if the warning appears from an old image. If it appears from a freshly built image, treat it as a regression to fix rather than accepted lifecycle noise. |
| GHCup `[ Warn ] No GHCup update available` during `get-ghcup` bootstrap | Upstream bootstrap no-op warning | The upstream installer runs `ghcup upgrade` after downloading the current `ghcup` binary and reports the no-op through its warning channel. Accept only when the pinned `ghc`, pinned `cabal`, and formatter `ghc` installs complete and the image build exits zero. Do not replace the supported `ghcup` path just to hide this upstream no-op. |
| GHCup advice to adjust `PATH` during Linux substrate image build | Upstream installer guidance in a noninteractive image build | The Dockerfile deliberately prevents shell profile edits and owns `PATH` through Docker `ENV`. Accept the advice text only when subsequent `ghcup`, `ghc`, and `cabal` commands in the same image build succeed and the final image contains `/root/.ghcup/bin` and `/root/.cabal/bin` on `PATH`. |
| GHCup `Couldn't figure out login shell!` during Linux substrate image build | Substrate image-layout regression | The Linux Dockerfile leaves `BOOTSTRAP_HASKELL_ADJUST_BASHRC` unset and sets the toolchain `PATH` explicitly with Docker `ENV`. If this message returns from a freshly built image, fix the image environment instead of accepting it as bootstrap noise. |
| npm deprecation warnings from the web or Playwright toolchain | Dependency hygiene regression unless tied to a newly documented upstream constraint | The current web install avoids the legacy `purescript` npm installer, installs `purs` from the official PureScript release archive, runs Spago 1.x, overrides Spago's transitive `glob` to `glob@13.0.6`, and disables npm's update notifier in supported image builds. New deprecation warnings should be resolved by maintained upgrades or explicitly documented with validation evidence. |
| npm update notices during supported image builds | Substrate image-layout regression | The Linux substrate image sets `NPM_CONFIG_UPDATE_NOTIFIER=false`; npm version changes should come through the supported Node/npm image toolchain update path, not ad hoc notices during lifecycle runs. |
| Playwright build error `Cannot find module '/workspace/web/scripts/install-purescript.mjs'` | Toolchain-image regression, not accepted warning noise | The Linux substrate Dockerfile must copy `web/scripts/` before npm `postinstall` runs because the web toolchain installs `purs` through `web/scripts/install-purescript.mjs`. Rebuild the Linux substrate image if an old launcher image still carries the stale Dockerfile; fix the Dockerfile if a fresh image reproduces the error. |
| Python `pip` warning about running as root during Linux substrate image build | Substrate image-layout regression | The Linux substrate image installs Poetry into `/opt/poetry`, a dedicated virtual environment, instead of using system pip as root. If a root-pip warning returns, treat it as image-layout drift; do not treat it as permission to run host adapter setup as root. |
| `update-alternatives` warnings about missing manpage symlinks during apt installs | Debian package metadata noise | Accept only when the package install and image build exit zero. These warnings are not eliminated by application code because they come from upstream package metadata in the base image. |

## Teardown

- run `infernix cluster down`
- when using `bootstrap/*.sh down`, expect the shell script to delegate to the binary teardown
  path only; it deletes the cluster and must preserve `./.build/`, `./.data/`, the host-level
  container build, the Apple host binary, and installed Docker or CUDA prerequisites
- the same scratch-kubeconfig policy applies during teardown: Kind delete does not depend on the
  durable repo-local kubeconfig path or its transient lock artifacts
- on Apple, expect teardown to copy retained Kind claim data back out of the worker before the
  cluster disappears when durable state exists
- when teardown looks quiet, use `infernix cluster status` to confirm whether the active phase is
  still `replay-retained-state` or has advanced to `delete-kind-cluster`
- expect durable state under `./.data/` to remain intact

## Durable-Context Demo Bring-Up

When the active substrate's generated `.dhall` carries `demo_ui = true`, `cluster up`
performs the following additional reconciliation steps:

- deploys a Keycloak Helm release together with its dedicated Patroni Postgres cluster managed
  by the Percona operator; expects Harbor to be responsive first, then the Keycloak Patroni
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
import or initial Patroni replica bootstrap is healthy convergence as long as the lifecycle
heartbeat continues to update. When `demo_ui = false`, none of the above steps run and the
Keycloak release, demo MinIO bucket, and demo Pulsar namespaces are absent from the cluster.

See [../architecture/demo_app_design.md](../architecture/demo_app_design.md) and
[../tools/keycloak.md](../tools/keycloak.md) for the full contract.

## Cohort Validation Cadence

Lifecycle validation work on either substrate is batched into the active wave named in
[../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md).
Operators bringing up a cluster for validation should check the active wave before starting a
batched lifecycle: the waves doc names which substrate is in scope, what closure evidence is
expected, and which counterpart cohort is queued for the next switch boundary.

## Cross-References

- [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
- [../tools/keycloak.md](../tools/keycloak.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../architecture/daemon_topology.md](../architecture/daemon_topology.md)
- [../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md)
