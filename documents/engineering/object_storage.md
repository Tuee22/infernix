# Object Storage

**Status**: Authoritative source
**Referenced by**: [model_lifecycle.md](model_lifecycle.md), [../architecture/runtime_modes.md](../architecture/runtime_modes.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Describe the durable object-storage contract used by the runtime today.

## Rules

- the current runtime persists durable object-store state under `./.data/object-store/`
- runtime artifact bundles live under `./.data/object-store/artifacts/<runtime-mode>/<model-id>/`
- source-artifact manifests live under
  `./.data/object-store/source-artifacts/<runtime-mode>/<model-id>/`
- large outputs live under `./.data/object-store/results/` and are surfaced back to clients as
  object references when the inline payload threshold is exceeded; when the clustered demo bridge
  receives a large inline result from the daemon, it rewrites that payload into the demo pod's own
  local object store before serving the browser-visible `/objects/:objectRef` link
- switching runtime modes changes engine bindings and generated catalog content, not the local
  object-store contract
- the chart and routed portal inventory still reserve `/minio/s3` for the real Kind-backed object
  store path, but the default validated runtime path remains repo-local filesystem storage today

## Cross-References

- [edge_routing.md](edge_routing.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../tools/minio.md](../tools/minio.md)
