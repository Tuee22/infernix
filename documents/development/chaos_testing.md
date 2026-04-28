# Chaos Testing

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Record the supported HA-failure coverage for Harbor, MinIO, operator-managed
> PostgreSQL, and Pulsar.

## Current Status

- the real non-simulated `linux-cpu` integration lane now includes supported automated HA-failure
  checks for Harbor, MinIO, Patroni PostgreSQL, and Pulsar
- Harbor coverage deletes one `infernix-harbor-core` pod, waits for the deployment rollout, then
  proves a fresh `imagePullPolicy: Always` pod can still pull the Harbor-backed `infernix-service`
  image
- MinIO coverage writes a sentinel file to the mounted MinIO data volume, deletes one MinIO pod,
  waits for that pod to return, and asserts the sentinel remains readable afterward
- Pulsar coverage publishes one routed request or result before replacing a broker pod and a second
  routed request or result after that broker is ready again
- PostgreSQL coverage deletes the Harbor Patroni primary, waits for a different primary pod to
  become ready, and separately compares the deterministic Harbor PostgreSQL PV inventory plus
  host-path mapping across `cluster down` plus `cluster up`
- the fresh outer-container `linux-cpu` rerun of that HA coverage passed on April 28, 2026
- simulated lanes still exercise route, publication, cache, and service-loop behavior without
  claiming live HA-failure coverage
- the Apple host-native lane still needs its own final supported HA-failure revalidation once the
  remaining runtime-parity work closes

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../tools/harbor.md](../tools/harbor.md)
- [../tools/minio.md](../tools/minio.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [../tools/pulsar.md](../tools/pulsar.md)
