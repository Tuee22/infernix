# PostgreSQL

**Status**: Authoritative source
**Referenced by**: [harbor.md](harbor.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported operator-managed PostgreSQL contract for the local platform.

## Rules

- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes operator
- a service may use a dedicated PostgreSQL cluster, but it still uses that same operator-managed Patroni model rather than a chart-managed standalone PostgreSQL deployment
- services that can self-deploy PostgreSQL disable that embedded chart path and point at an operator-managed cluster instead
- Harbor's supported database path is the operator-managed `harbor-postgresql` cluster together
  with its PgBouncer deployment; the old `infernix-harbor-database` StatefulSet is not part of
  the supported topology
- PostgreSQL claims use `infernix-manual`, which is backed by `kubernetes.io/no-provisioner`, and
  those claims bind to manually created PVs under `./.data/kind/...`
- `infernix test integration` validates PostgreSQL readiness, replacement-primary failover, and
  repeat lifecycle rebinding to the same manually managed PV host paths
- on a pristine cluster, Harbor stays the first deployed service; only Harbor plus Harbor-required
  backend services such as MinIO and PostgreSQL may pull from public container repositories before
  Harbor is ready
- once Harbor is ready, every later non-Harbor rollout, including PostgreSQL-backed services,
  pulls from Harbor-backed image references

## Cross-References

- [harbor.md](harbor.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
