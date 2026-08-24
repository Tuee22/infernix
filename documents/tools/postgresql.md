# PostgreSQL

**Status**: Authoritative source
**Referenced by**: [registry.md](registry.md), [../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported operator-managed PostgreSQL contract for the local platform.

## Rules

- every in-cluster PostgreSQL dependency uses a Patroni cluster managed by the Percona Kubernetes operator
- a service may use a dedicated PostgreSQL cluster, but it still uses that same operator-managed Patroni model rather than a chart-managed standalone PostgreSQL deployment
- services or add-ons whose chart can self-deploy PostgreSQL disable that embedded chart path and point at an operator-managed cluster instead
- Keycloak's supported database path is the operator-managed `keycloak-postgresql` cluster
  together with its PgBouncer deployment; there is no chart-managed standalone StatefulSet.
  It is the platform's only PostgreSQL cluster: the in-cluster image registry is a single-binary
  `registry:2` and carries no database at all
- PostgreSQL claims explicitly use `storageClassName: infernix-manual`, which is backed by
  `kubernetes.io/no-provisioner`, and those claims bind to manually created PVs under
  `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>`
- `infernix test integration` validates PostgreSQL readiness and repeat lifecycle reuse of the same
  deterministic manually managed PV inventory and host paths
- each operator-managed cluster runs **one instance** with one PgBouncer proxy. The Percona
  operator is the lifecycle mechanism, not a high-availability mechanism: there is no replica to
  promote, so instance loss recovers by restart when storage remains healthy or by restore from
  backup. The supported lifecycle command language contains no replica-reinitialization operation
- the Keycloak Percona cluster references a repo-owned `databaseInitSQL` ConfigMap that
  idempotently create `_crunchyrepl` as `LOGIN REPLICATION`, matching the Patroni bootstrap role
  the Percona image expects.
- Patroni bootstrap may recycle unready startup pods when they remain `Running` but fail
  Patroni readiness beyond the supported grace window. The recycle uses Kubernetes `--wait=false`
  deletes so StatefulSet immediate name reuse does not block lifecycle progress; readiness remains
  owned by the surrounding wait loop before any dependent rollout proceeds
- on a pristine cluster, the in-cluster registry stays the first deployed service; only the
  registry plus the MinIO storage it needs may pull from public container repositories before the
  registry is ready
- once the registry is ready, every later rollout, add-on, and PostgreSQL-backed service pulls
  from registry-backed image references

## Cross-References

- [registry.md](registry.md)
- [../engineering/k8s_storage.md](../engineering/k8s_storage.md)
- [../operations/cluster_bootstrap_runbook.md](../operations/cluster_bootstrap_runbook.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
