# Edge Routing

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Define the one-port routing contract for browser and host-consumed services.

## TL;DR

- One Haskell-owned route registry defines the supported public prefixes, rendered HTTPRoutes,
  route-aware docs, and route validation expectations.
- The routed surface always publishes Harbor, MinIO, and Pulsar, and publishes the demo routes
  only when the active generated config enables the demo UI.
- Gateway owns the supported routed surface, and direct `infernix-demo` execution intentionally
  exposes only the demo-owned HTTP surface outside the intended HTTPRoute mapping.

## Current Status

The current worktree uses the registry-backed route contract directly: the generated route table in
this document comes from the Haskell route registry, `cluster status` and `/api/publication`
publish the same routed surface, and the Harbor-first bootstrap path no longer carries a separate
helper-registry route or namespace. Integration now requires the real Harbor, MinIO, and Pulsar
upstream responses on the tool-route probes rather than any direct `infernix-demo`
compatibility payload.

## Route Inventory

- the chart-owned route contract lives in `GatewayClass/infernix-gateway`,
  `Gateway/infernix-edge`, `EnvoyProxy/infernix-edge`, and the HTTPRoute inventory rendered by
  `chart/templates/httproutes.yaml`

<!-- infernix:route-registry:edge-routing:start -->
| Public prefix | Visibility | Purpose | Backend | Rewrite |
|---------------|------------|---------|---------|---------|
| `/` | demo-only | Demo workbench | `infernix-demo:80` | no rewrite |
| `/api` | demo-only | Demo API | `infernix-demo:80` | no rewrite |
| `/objects` | demo-only | Demo object store | `infernix-demo:80` | no rewrite |
| `/harbor/api` | always published | Harbor API | `infernix-harbor-core:80` | `/harbor/api` -> `/api` |
| `/harbor` | always published | Harbor portal | `infernix-harbor-portal:80` | `/harbor` -> `/` |
| `/minio/console` | always published | MinIO console | `infernix-minio-console:9090` | `/minio/console` -> `/` |
| `/minio/s3` | always published | MinIO S3 API | `infernix-minio:9000` | `/minio/s3` -> `/` |
| `/pulsar/admin` | always published | Pulsar admin surface | `infernix-infernix-pulsar-proxy:80` | `/pulsar/admin` -> `/` |
| `/pulsar/ws` | always published | Pulsar websocket surface | `infernix-infernix-pulsar-proxy:80` | `/pulsar/ws` -> `/ws` |
<!-- infernix:route-registry:edge-routing:end -->

- when the demo surface is enabled, `/` and the demo `/api*` and `/objects/` routes target the
  `infernix-demo` workload; direct `infernix-demo serve [--dhall PATH] [--port PORT]` still
  exposes the same Haskell demo API surface outside the routed cluster path when used
  intentionally, but the supported routed Apple story keeps that HTTP host cluster-resident and
  bridges manual inference through Pulsar into the host daemon instead of treating direct `serve`
  as the browser baseline
- `/api/publication` reports daemon location, `inferenceDispatchMode`, and routed-upstream health
  plus backing-state details

## Gateway Ownership

- `cluster up` applies the Gateway API and Envoy Gateway CRDs from the bundled `gateway-helm`
  dependency before the controller rollout because Helm does not install dependency-chart CRDs on
  the supported path
- `EnvoyProxy/infernix-edge` customizes the managed Envoy Service to use the repo-owned
  `NodePort` contract on `30090` with `externalTrafficPolicy: Cluster`
- that pinned Envoy Service shape keeps the host-native and Linux outer-container routed surfaces
  on the same shared edge contract

## Port Selection Rules

- `cluster up` tries `9090` first and increments by `1` until it finds an available port
- the chosen port is recorded under `./.data/runtime/edge-port.json`
- `cluster up` prints the chosen port during bring-up
- `cluster status` reports the active runtime mode together with the chosen port, the published
  route inventory, and the publication-state details that back `/api/publication`

## Validation

- `infernix docs check` fails if this document loses its governed metadata, required structure, or
  the registry-generated route-inventory section.
- `infernix test integration` exercises the published Harbor, MinIO, Pulsar, publication, and
  demo routes and requires the real Harbor, MinIO, and Pulsar upstream responses on the
  tool-route probes.
- `infernix test e2e` verifies the routed demo surface through the shared edge port when the demo
  UI is enabled for the selected runtime mode.

## Cross-References

- [object_storage.md](object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [../tools/pulsar.md](../tools/pulsar.md)
