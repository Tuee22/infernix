# Cluster Bootstrap Runbook

**Status**: Authoritative source
**Referenced by**: [apple_silicon_runbook.md](apple_silicon_runbook.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Describe the supported cluster lifecycle and durable-state expectations.

## Bring-Up

- run `infernix cluster up`
- for `linux-cuda`, confirm the supported NVIDIA host satisfies `nvidia-smi -L`, `docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L`, and either `docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L` or `docker run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L` before cluster creation; on the outer-container control-plane path the launcher directly verifies the two Docker probes because it may not ship the host `nvidia-smi` binary locally
- on the supported outer-container `linux-cuda` path, expect the repo-owned bootstrap to sync
  NVIDIA userspace into the Kind worker before the device-plugin rollout when the host satisfies
  the accepted `--gpus all` plus worker-device probe but does not inject driver libraries through a
  Docker default-runtime configuration
- on the outer-container control-plane path, confirm the host exposes enough inotify instances for
  mount-bearing Kind nodes; the validated Ubuntu flow uses
  `fs.inotify.max_user_instances >= 1024`
- confirm that the chosen edge port, active runtime mode, generated demo-config paths, and build-root publication details are printed
- confirm that Harbor is the first deployed service on a pristine cluster and that only
  Harbor-required backend services such as MinIO and the PostgreSQL operator or Patroni cluster
  reconcile or pull from public container repositories before Harbor is ready for image pulls
- confirm that `cluster up` preloads the Harbor-backed final image refs onto the Kind worker before
  the remaining non-Harbor workloads begin their final rollout
- confirm that every later non-Harbor rollout, add-on, or PostgreSQL-backed service after Harbor
  readiness pulls from Harbor-backed image references rather than public upstream registries
- confirm that `infernix kubectl get pods -n platform` shows the Percona PostgreSQL operator and
  the Patroni members needed for Harbor's PostgreSQL backend reaching ready state before the final
  post-Harbor rollout depends on them, and that `harbor-postgresql-pgbouncer` is also ready
- if one Harbor PostgreSQL startup pod remains `Running` without reaching readiness during
  bootstrap, confirm the supported reconcile path recycles that pod once and still reaches a fully
  ready Patroni set before the post-Harbor rollout continues
- confirm that `infernix kubectl get jobs -n platform` shows
  `infernix-infernix-pulsar-bookie-init` and `infernix-infernix-pulsar-pulsar-init` completing
  during the final Harbor-backed rollout, because Pulsar is first enabled there
- confirm that `infernix kubectl get pods -n platform` shows `infernix-edge`, `infernix-service`,
  the Harbor application-plane workloads, the MinIO statefulset, the Pulsar statefulsets, the
  PostgreSQL operator-managed members, and the Haskell `infernix-{harbor,minio,pulsar}-gateway`
  workloads (all running from the same `infernix` OCI image with different entrypoints)
- when the active `.dhall` enables the demo UI (`demo_ui = True`), also confirm that
  `infernix-demo` is present; when it does not (the production default), confirm
  `infernix-demo` is absent, no HTTP API surface is bound by `infernix-service`, and `/`, `/api`,
  `/api/publication`, `/api/cache`, and `/objects/` do not appear in the edge route inventory
- confirm that the edge proxy and gateway pods are running the Haskell entrypoints
  (`infernix edge` and `infernix gateway harbor|minio|pulsar`) rather than legacy Python
  implementations
- confirm that `infernix kubectl get storageclass` shows only `infernix-manual`
- confirm that no PVC-backed Helm workload was dynamically provisioned and that each durable PV is
  manually pre-bound to its intended claim under `./.data/kind/...`
- confirm that `infernix kubectl get pvc -A` shows the service, Harbor, MinIO, Pulsar, and PostgreSQL claims bound through `infernix-manual`
- confirm that any service or add-on that can self-deploy PostgreSQL renders with that embedded
  database path disabled and instead targets an operator-managed Patroni cluster
- confirm routes with `infernix cluster status`
- confirm that `cluster status` reports the build root, data root, runtime result count, object-store object count, and model-cache entry count alongside the route inventory
- inspect `./.data/runtime/publication.json` or `GET /api/publication` to confirm the routed publication contract matches `cluster status`, including API-upstream mode and routed-upstream health details
- inspect the real ConfigMap with `infernix kubectl get configmap infernix-demo-config -n platform -o yaml`
- if adapter-specific engine command prefixes are required on the cluster path, export the relevant
  `INFERNIX_ENGINE_COMMAND_*` variables before `cluster up` and confirm they are present on the
  `infernix-service` deployment environment
- confirm `curl http://127.0.0.1:<port>/harbor`, `curl http://127.0.0.1:<port>/minio/s3`, and
  `curl http://127.0.0.1:<port>/pulsar/ws` all resolve through the shared edge port
- confirm non-Harbor workloads are pulling Harbor-published image references with
  `infernix kubectl get pods -A -o jsonpath=...`
- on a repeat `cluster up`, confirm the same Harbor-backed final rollout completes without a helper
  registry container reappearing and without the MinIO StatefulSet recording the old transient
  first-pull Harbor `502 Bad Gateway`
- on a repeat `cluster down` plus `cluster up`, confirm Harbor's PostgreSQL PVCs rebind to the
  same host paths under `./.data/kind/...` rather than allocating a new manual-storage location
- on a repeat `cluster up`, confirm Harbor PostgreSQL startup reconciliation does not stall
  indefinitely on a single `Running` but not-`Ready` Patroni startup pod
- confirm `docker port <kind-control-plane> 6443/tcp` and `docker port <kind-control-plane> 30090/tcp`
  report `127.0.0.1:...` bindings rather than `0.0.0.0:...`
- confirm `curl http://127.0.0.1:<port>/` reaches the routed workbench from the host
- on the outer-container control-plane path, confirm `cluster up`, `cluster status`, `infernix kubectl ...`,
  and routed browser validation reach the cluster through the private Docker `kind` network plus
  `kind get kubeconfig --internal` rather than through `host.docker.internal`
- for `linux-cuda`, confirm `infernix kubectl -n nvidia get daemonset nvidia-device-plugin-daemonset -o jsonpath='{.status.numberReady}:{.status.desiredNumberScheduled}'` reports a ready rollout, `infernix kubectl get nodes -l infernix.runtime/gpu=true -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'` reports positive values, `infernix kubectl get deployment -n platform infernix-service -o jsonpath='{.spec.template.spec.runtimeClassName}'` reports `nvidia`, and `infernix kubectl -n platform exec deployment/infernix-service -- nvidia-smi -L` reports visible GPUs

## Teardown

- run `infernix cluster down`
- expect durable state under `./.data/` to remain intact

## Cross-References

- [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
