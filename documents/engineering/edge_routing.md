# Edge Routing

**Status**: Authoritative source
**Referenced by**: [../architecture/web_ui_architecture.md](../architecture/web_ui_architecture.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Define the one-port routing contract for browser and host-consumed services.

## Route Inventory

- the unconditional published route inventory is `/harbor`, `/minio/console`, `/minio/s3`,
  `/pulsar/admin`, and `/pulsar/ws`
- when the active `.dhall` `demo_ui` flag is on, the inventory adds `/`, `/api`,
  `/api/publication`, `/api/cache`, and `/objects/<key>`
- the chart-owned route contract lives in `GatewayClass/infernix-gateway`,
  `Gateway/infernix-edge`, `EnvoyProxy/infernix-edge`, and the HTTPRoute inventory rendered by
  `chart/templates/httproutes.yaml`
- when the demo surface is enabled, `/` and the demo `/api*`, `/objects/` routes target the
  `infernix-demo` workload; on the Apple host-native path, the same demo surface can be served by
  `infernix-demo serve --dhall PATH --port N` and reached through the same base URL via the host
  bridge
- `/harbor/api` is matched before `/harbor` and rewrites to Harbor's `/api` surface
- `/harbor`, `/minio/console`, `/minio/s3`, and `/pulsar/admin` each use `URLRewrite` to strip
  the public prefix before forwarding to the chart-managed backend service
- `/pulsar/ws` rewrites to `/ws` so the public route preserves Pulsar's real WebSocket context
  root (`/ws/v2/...`) when forwarding to the proxy service
- `/api/publication` reports daemon location plus routed-upstream health and backing-state details
- when the platform toolchain is unavailable and `cluster up` uses the simulated substrate, the
  same route prefixes are still published and served by compatibility handlers so route and
  rewrite behavior remain testable

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

## Cross-References

- [object_storage.md](object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [../tools/pulsar.md](../tools/pulsar.md)
