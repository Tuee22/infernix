# Chaos Testing

**Status**: Authoritative source
**Referenced by**: [testing_strategy.md](testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

> **Purpose**: Record the supported HA-failure coverage for Harbor, MinIO, and Pulsar.

## Rules

- the canonical HA-failure coverage lives in `infernix test integration`
- Harbor recovery coverage deletes a single Harbor application pod and verifies that routed portal
  access and Harbor-backed image pulls still work afterward
- MinIO recovery coverage deletes a single MinIO pod and verifies that persisted protobuf runtime
  results, manifests, and large-output objects remain available afterward
- Pulsar recovery coverage deletes a single Pulsar proxy pod and verifies that routed inference and
  schema-backed request or result transport still work afterward
- the Apple host-native final-substrate lane is the validated HA-failure path in the supported
  contract

## Cross-References

- [testing_strategy.md](testing_strategy.md)
- [../tools/harbor.md](../tools/harbor.md)
- [../tools/minio.md](../tools/minio.md)
- [../tools/pulsar.md](../tools/pulsar.md)
