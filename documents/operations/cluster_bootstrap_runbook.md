# Cluster Bootstrap Runbook

**Status**: Authoritative source
**Referenced by**: [apple_silicon_runbook.md](apple_silicon_runbook.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Describe the supported cluster lifecycle and durable-state expectations.

## Bring-Up

- confirm the active build root already carries `infernix-substrate.dhall`; on Apple host-native
  flows stage it with `./.build/infernix internal materialize-substrate apple-silicon`, and the
  supported Linux outer-container path stages it with
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  before cluster bring-up
- treat the supported `bootstrap/*.sh` entrypoints as restartable prerequisite reconcilers: when
  host preparation reports a required new shell or reboot boundary, rerun the same bootstrap
  command from the start after satisfying that boundary instead of continuing from a later direct
  `infernix` command
- the repo-owned `bootstrap/linux-cpu.sh` and `bootstrap/linux-gpu.sh` entrypoints restage that
  active Linux substrate file before supported lifecycle and test commands so lane switches do not
  reuse a stale staged payload
- run `infernix cluster up`
- if retained Pulsar ZooKeeper state is self-inconsistent, `cluster up` logs a targeted Pulsar
  claim-root reset and retries once; treat that retry as explicit durability repair for the
  affected runtime lane because prior Pulsar message history there is discarded
- if retained Harbor PostgreSQL replicas stay stopped after leader promotion, `cluster up` may
  log a targeted Patroni replica reinitialization from the current leader and wait for those
  replicas to resync; treat that as supported retained-state repair rather than hard bootstrap
  failure
- on the Apple host-native path, the command reconciles Homebrew-managed Colima, Docker CLI,
  `kind`, `kubectl`, and `helm` before it attempts the real Kind workflow, reconciles Colima to
  the supported `8 CPU / 16 GiB` profile before Docker-backed work, and verifies the selected
  ghcup-managed `ghc` and `cabal` executables plus Homebrew `protoc` before direct host build
  handoff
- on Apple, retained Kind state under `./.data/kind/apple-silicon/` is replayed into and out of
  the worker instead of being bind-mounted, so large retained state can make `cluster up` and
  `cluster down` slower than the Linux lanes even when the supported flow is healthy
- on May 13, 2026, an Apple investigation confirmed that long waits in retained-state replay,
  Docker build finalization, Harbor publication, and Kind-worker image preload were healthy
  convergence rather than hard failure; the monitored Apple `build-cluster-images` phase stayed
  healthy well past thirty minutes before Harbor publication began, and Harbor Docker pushes used
  readiness-gated bounded retries across transient registry resets during large-image publication
- for `linux-gpu`, confirm the supported NVIDIA host satisfies the documented `nvidia-smi` and
  `docker run --gpus all` preflight contract before cluster creation
- for `linux-gpu`, also confirm the host filesystem has substantial free space before `cluster up`
  or `test all`; low disk headroom can make Kind-hosted BookKeeper ledger directories
  non-writable during the Harbor-backed rollout and prevent `infernix-service` readiness
- confirm that the chosen edge port, active runtime mode, generated demo-config paths, and
  build-root publication details are printed
- when `cluster up` appears quiet, run `infernix cluster status` before abandoning it
- the supported progress surface reports `lifecycleStatus`, the active `lifecyclePhase`, the
  current `lifecycleDetail`, and heartbeat timestamps while `cluster up` or `cluster down` is
  still running
- treat elapsed wall time alone as insufficient evidence of failure; during the monitored
  subprocess phases, a heartbeat that continues to refresh roughly every 30 seconds indicates the
  supported path is still progressing
- the current monitored long-running subprocess phases are the shared runtime `docker build`,
  Harbor image publication, Kind-worker Harbor preload, and Apple retained-state replay steps
- Harbor image publication waits for registry readiness before Docker push attempts and retries
  transient push resets with bounded backoff; treat registry-reset logs during large image pushes
  as recoverable until the command exhausts that retry budget
- on the governed Apple lane, `infernix test all` may trigger multiple internal cluster bring-up
  or teardown cycles before the outer command returns; apply the same heartbeat-driven failure
  classification to those internal rounds
- on the real Kind path, confirm that Harbor is the first deployed service on a pristine cluster
  and that only Harbor-required backend services pull from public container repositories before
  Harbor is ready
- the supported Harbor-first bootstrap path no longer depends on the retired
  `infernix-bootstrap-registry` container or the old `./.build/kind/registry/localhost:30001`
  helper-registry namespace
- on the supported outer-container path, confirm that `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding that runtime image inside the
  launcher
- confirm that `cluster up` preloads Harbor-backed final image refs onto the Kind worker before the
  remaining non-Harbor workloads begin their final rollout
- confirm that `infernix kubectl get pods -n platform` shows the Envoy Gateway data plane,
  `infernix-service`, the Harbor application-plane workloads, the MinIO statefulset, the Pulsar
  statefulsets, and the PostgreSQL operator-managed members
- confirm that `infernix kubectl get gatewayclass infernix-gateway` reports `Accepted=True`,
  `infernix kubectl -n platform get gateway infernix-edge` reports `Accepted=True` and
  `Programmed=True`, and `infernix kubectl -n platform get envoyproxy infernix-edge` is present
- when the active `.dhall` enables the demo UI (`demo_ui = True`), also confirm that
  `infernix-demo` is present; when it does not, confirm `infernix-demo` is absent
- confirm that `infernix kubectl get storageclass` shows only `infernix-manual`
- confirm routes with `infernix cluster status`
- inspect `./.data/runtime/publication.json` or `GET /api/publication` to confirm the routed
  publication contract matches `cluster status`
- inspect the real ConfigMap with `infernix kubectl get configmap infernix-demo-config -n platform -o yaml`

<!-- infernix:route-registry:cluster-bootstrap:start -->
- `curl http://127.0.0.1:<port>/harbor` checks the Harbor portal route.
- `curl http://127.0.0.1:<port>/harbor/api/v2.0/projects` checks the `/harbor/api -> /api` rewrite into the Harbor core service.
- `curl http://127.0.0.1:<port>/minio/console/browser` checks the `/minio/console -> /` rewrite into the MinIO console service.
- `curl http://127.0.0.1:<port>/minio/s3/models/demo.bin` checks the `/minio/s3 -> /` rewrite into the MinIO S3 service.
- `curl http://127.0.0.1:<port>/pulsar/admin/admin/v2/clusters` checks the `/pulsar/admin -> /` rewrite into Pulsar's `/admin/v2` surface.
- `curl http://127.0.0.1:<port>/pulsar/ws/v2/producer/public/default/demo` checks the `/pulsar/ws -> /ws` rewrite and returns `405 Method Not Allowed` on the real cluster path.
<!-- infernix:route-registry:cluster-bootstrap:end -->

Those probes validate the real Gateway-backed upstream responses only; direct `infernix-demo`
execution is not a supported compatibility fallback for the Harbor, MinIO, or Pulsar tool routes.

## Teardown

- run `infernix cluster down`
- on Apple, expect teardown to copy retained Kind claim data back out of the worker before the
  cluster disappears when durable state exists
- when teardown looks quiet, use `infernix cluster status` to confirm whether the active phase is
  still `replay-retained-state` or has advanced to `delete-kind-cluster`
- expect durable state under `./.data/` to remain intact

## Cross-References

- [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
