# Chaos Testing

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Record the supported HA-failure coverage for Harbor, MinIO, operator-managed
> PostgreSQL, and Pulsar.

## Current Status

- the repository does not yet ship supported automated HA-failure or pod-deletion validation for
  Harbor, MinIO, Patroni PostgreSQL, or Pulsar
- `infernix test integration` currently validates steady-state routed availability, publication,
  cache mutation, and service-loop request or result behavior; it does not delete or restart
  workload pods
- the remaining HA-failure automation is tracked in
  `DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md`
- the Apple host-native lane remains the intended final HA-failure closure path once that Phase 6
  work lands

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../tools/harbor.md](../tools/harbor.md)
- [../tools/minio.md](../tools/minio.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../tools/pulsar.md](../tools/pulsar.md)
