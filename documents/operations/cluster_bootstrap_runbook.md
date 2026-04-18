# Cluster Bootstrap Runbook

**Status**: Authoritative source
**Referenced by**: [apple_silicon_runbook.md](apple_silicon_runbook.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Describe the supported cluster lifecycle and durable-state expectations.

## Bring-Up

- run `infernix cluster up`
- confirm that the chosen edge port, active runtime mode, generated demo-config paths, and build-root publication details are printed
- confirm that `infernix kubectl get pods -n platform` shows `infernix-edge`, `infernix-web`,
  `infernix-service`, the Harbor application-plane workloads, the MinIO statefulset, the Pulsar
  statefulsets, and the Harbor or MinIO or Pulsar gateway workloads
- confirm that `infernix kubectl get storageclass` shows only `infernix-manual`
- confirm that `infernix kubectl get pvc -n platform` shows the service, Harbor, MinIO, and Pulsar claims bound through `infernix-manual`
- confirm routes with `infernix cluster status`
- confirm that `cluster status` reports the build root, data root, runtime result count, object-store object count, and model-cache entry count alongside the route inventory
- inspect `./.data/runtime/publication.json` or `GET /api/publication` to confirm the routed publication contract matches `cluster status`, including API-upstream mode and routed-upstream health details
- inspect the real ConfigMap with `infernix kubectl get configmap infernix-demo-config -n platform -o yaml`
- confirm `curl http://127.0.0.1:<port>/harbor`, `curl http://127.0.0.1:<port>/minio/s3`, and
  `curl http://127.0.0.1:<port>/pulsar/ws` all resolve through the shared edge port
- confirm non-Harbor workloads are pulling Harbor-published image references with
  `infernix kubectl get pods -A -o jsonpath=...`
- confirm `curl http://127.0.0.1:<port>/` reaches the routed workbench on the host-native path or use `host.docker.internal` from the outer-container control plane
- for `linux-cuda`, confirm `infernix kubectl get nodes -l infernix.runtime/gpu=true -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'` reports `1` and that `infernix kubectl get deployment -n platform infernix-service -o jsonpath='{.spec.template.spec.runtimeClassName}'` reports `nvidia`

## Teardown

- run `infernix cluster down`
- expect durable state under `./.data/` to remain intact

## Cross-References

- [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
