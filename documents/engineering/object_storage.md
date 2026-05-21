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

## Presigned-URL Contract (Planned, Phase 7)

When the durable-context demo lands, the demo backend adopts a presigned-URL contract for
artifact transfer. The `./.data/object-store/` repo-local path and the `/objects/:objectRef`
route remain available to the routed cache and large-output flow described above and are
unrelated to the durable-context artifact path.

- the durable-context surface uses the dedicated MinIO bucket `infernix-demo-objects` with
  per-user prefixes `users/<userId>/contexts/<contextId>/{uploads,generated}/`; see
  [../tools/minio.md](../tools/minio.md)
- `POST /api/objects` (demo-only, JWT-validated) mints presigned PUT URLs for uploads and
  presigned GET URLs for downloads, scoped to the authenticated user's prefix via MinIO scope
  policies
- artifact bytes flow directly between the browser and MinIO; the demo backend never proxies
  artifact bytes on the durable-context path
- the demo artifact path preserves MIME/content-type metadata and classifies browser handling
  through the UI-side artifact contract in
  [../architecture/demo_app_design.md](../architecture/demo_app_design.md) and
  [../tools/minio.md](../tools/minio.md); model-weight/runtime formats are not upload MIME
  families
- presigned URLs have a short expiration; the browser requests a fresh URL per upload/download
- generated artifacts (model outputs) are written by the cluster daemon's inference path into
  the same per-user prefix layout; the demo backend includes the resulting object key in the
  `InferenceResult` event posted to the per-context conversation topic
- the `infernix-demo-objects` bucket and `/api/objects` route are absent from the cluster
  when `demo_ui = false`

## Cross-References

- [edge_routing.md](edge_routing.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
- [../tools/minio.md](../tools/minio.md)
