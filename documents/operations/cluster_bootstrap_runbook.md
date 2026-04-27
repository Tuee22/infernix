# Cluster Bootstrap Runbook

**Status**: Authoritative source
**Referenced by**: [apple_silicon_runbook.md](apple_silicon_runbook.md), [../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md](../../DEVELOPMENT_PLAN/phase-2-kind-cluster-storage-and-lifecycle.md)

> **Purpose**: Describe the supported cluster lifecycle and durable-state expectations.

## Bring-Up

- run `infernix cluster up`
- if Docker, Kind, Helm, or kubectl are unavailable, expect `cluster up` to use the simulated
  substrate; `cluster status` will report that mode and the published routes remain available
- for `linux-cuda`, confirm the supported NVIDIA host satisfies the documented `nvidia-smi` and
  `docker run --gpus all` preflight contract before cluster creation
- confirm that the chosen edge port, active runtime mode, generated demo-config paths, and
  build-root publication details are printed
- on the real Kind path, confirm that Harbor is the first deployed service on a pristine cluster
  and that only Harbor-required backend services pull from public container repositories before
  Harbor is ready
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
- confirm `curl http://127.0.0.1:<port>/harbor`, `curl http://127.0.0.1:<port>/minio/s3`, and
  `curl http://127.0.0.1:<port>/pulsar/admin/admin/v2/clusters` all resolve through the shared
  routed port
- confirm `curl http://127.0.0.1:<port>/pulsar/ws/v2/producer/public/default/demo` reaches the
  Pulsar proxy WebSocket servlet and returns `405 Method Not Allowed` instead of a routed `404`,
  proving the `/pulsar/ws -> /ws` rewrite is active
- on the simulated substrate, those same routes return compatibility payloads proving the published
  route and rewrite behavior rather than live Harbor, MinIO, or Pulsar content

## Teardown

- run `infernix cluster down`
- expect durable state under `./.data/` to remain intact

## Cross-References

- [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../reference/cli_surface.md](../reference/cli_surface.md)
