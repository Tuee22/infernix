# PostgreSQL

**Status**: Authoritative source
**Referenced by**: [harbor.md](harbor.md), [../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported operator-managed PostgreSQL contract for the local platform.

## Rules

- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes operator
- a service may use a dedicated PostgreSQL cluster, but it still uses that same operator-managed Patroni model rather than a chart-managed standalone PostgreSQL deployment
- services or add-ons whose chart can self-deploy PostgreSQL disable that embedded chart path and point at an operator-managed cluster instead
- Harbor's supported database path is the operator-managed `harbor-postgresql` cluster together
  with its PgBouncer deployment; there is no `infernix-harbor-database` StatefulSet
- PostgreSQL claims explicitly use `storageClassName: infernix-manual`, which is backed by
  `kubernetes.io/no-provisioner`, and those claims bind to manually created PVs under
  `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- `infernix test integration` validates PostgreSQL readiness and repeat lifecycle reuse of the same
  deterministic manually managed PV inventory and host paths
- each operator-managed cluster runs **one instance** with one PgBouncer proxy. The Percona
  operator is the lifecycle mechanism, not a high-availability mechanism: there is no replica to
  promote, so instance loss recovers by restart when storage remains healthy or by restore from
  backup. The supported lifecycle command language contains no replica-reinitialization operation
- Harbor and Keycloak Percona clusters reference repo-owned `databaseInitSQL` ConfigMaps that
  idempotently create `_crunchyrepl` as `LOGIN REPLICATION`, matching the Patroni bootstrap role
  the Percona image expects.
- Harbor PostgreSQL bootstrap may recycle unready startup pods when they remain `Running` but fail
  Patroni readiness beyond the supported grace window. The recycle uses Kubernetes `--wait=false`
  deletes so StatefulSet immediate name reuse does not block lifecycle progress; readiness remains
  owned by the surrounding wait loop before any post-Harbor rollout depends on the cluster
- on a pristine cluster, Harbor stays the first deployed service; only Harbor plus Harbor-required
  backend services such as MinIO and PostgreSQL may pull from public container repositories before
  Harbor is ready
- once Harbor is ready, every later non-Harbor rollout, add-on, and PostgreSQL-backed service
  pulls from Harbor-backed image references

## Cross-References

- [harbor.md](harbor.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
