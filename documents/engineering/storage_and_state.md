# Storage And State

**Status**: Authoritative source
**Referenced by**: [build_artifacts.md](build_artifacts.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Distinguish authoritative durable state from derived build and runtime state.

## TL;DR

- Durable state lives under repo-local `./.data/` paths or in the cluster services backed by those
  paths.
- Build products, generated config mirrors, caches, virtual environments, and test artifacts are
  derived state and may be rebuilt.
- If deleting a path would lose operator intent or authoritative data, it is durable. If the path
  can be recreated from source, manifests, or cluster reconcile, it is derived.

## Current Status

The current repository already follows this split: Kind PV data, object-store metadata, MinIO
objects, Pulsar ledgers, protobuf-backed inference-result files, and Patroni-backed PostgreSQL
state are durable, while `./.build/`, `/opt/build/infernix/`, generated publication mirrors,
caches, and Playwright output are derived.

## Owner And Durability Table

| State class | Owner | Authoritative home | Durability | Rebuild rule |
|-------------|-------|--------------------|------------|--------------|
| PVC-backed cluster data for Harbor, MinIO, Pulsar, and PostgreSQL | `infernix cluster up` storage reconciliation plus the workload itself | `./.data/kind/...` | durable | do not delete implicitly; supported lifecycle reruns rebind the same deterministic host paths |
| Harbor registry content and Harbor metadata | Harbor plus operator-managed PostgreSQL | Harbor PVCs under `./.data/kind/...` | durable | loss is a platform failure, not a cache miss |
| MinIO objects | MinIO plus the service runtime | MinIO PVCs under `./.data/kind/...` | durable | objects may be republished deliberately, but they are not treated as disposable cache |
| Pulsar ledgers and BookKeeper journals | Pulsar | Pulsar PVCs under `./.data/kind/...` | durable | deletion resets message durability and is therefore explicit operator intent |
| Inference-result records | Haskell service runtime plus routed reload handlers | `./.data/runtime/results/*.pb` | durable and user-visible | reload only from protobuf-backed result files; retired `*.state` files are not part of the supported contract |
| Source-artifact manifests | Haskell service runtime | `./.data/object-store/source-artifacts/` | durable | these manifests are authoritative artifact-selection inputs |
| Runtime artifact bundles | Haskell service runtime | `./.data/object-store/artifacts/` | durable | bundles are durable worker inputs and are not rebuilt from cache directories alone |
| Cache manifests used to rebuild model caches | Haskell service runtime | `./.data/object-store/manifests/<runtime-mode>/<model-id>/default.pb` | durable | rebuild the derived cache from these protobuf-backed manifests rather than inventing alternate cache metadata |
| Publication state and generated ConfigMap mirrors | cluster lifecycle and demo activation | `./.data/runtime/publication.json`, `./.data/runtime/configmaps/infernix-demo-config/` | derived but user-visible | regenerate from `cluster up`, `cluster down`, or the active generated demo config |
| Repo-local kubeconfig and chosen edge-port record | cluster lifecycle | `./.build/infernix.kubeconfig`, `./.data/runtime/infernix.kubeconfig`, `./.data/runtime/edge-port.json` | derived | recreate from the supported control-plane lifecycle |
| Build roots and staged generated demo config | build or cluster lifecycle | `./.build/`, `/opt/build/infernix/` | derived | rebuild from source and the active runtime mode |
| Runtime model cache | Haskell service runtime | `./.data/runtime/model-cache/...` | derived | rebuild from durable manifests and artifacts |
| Apple adapter virtualenv and Playwright artifacts | Poetry or validation tooling | `python/.venv/`, `./.data/test-artifacts/playwright/` | derived | recreate from the shared Python project or rerun the validation lane |

## Failure And Rebuild Rules

- Unexpected loss of anything under the durable rows above is a correctness or durability failure,
  not a normal cleanup event.
- `cluster down` plus `cluster up` must preserve the deterministic PV inventory and host-path
  binding for the durable Harbor PostgreSQL state and the other PVC-backed workloads.
- Supported inference-result reloads depend on protobuf-backed `*.pb` records only; legacy
  `*.state` compatibility files are not part of the rebuild or reload contract.
- Publication mirrors, repo-local kubeconfig files, edge-port records, and generated demo-config
  staging are disposable because the supported lifecycle commands recreate them.
- Model-cache directories are disposable because the durable manifests and artifact bundles under
  `./.data/object-store/` are the rebuild inputs.
- Build roots and frontend bundles are disposable because the supported build and web workflows
  regenerate them from source.

## Cleanup Rules

- Delete durable state only through explicit operator intent such as supported cluster teardown,
  targeted data reset, or manual local cleanup that accepts data loss.
- Do not hand-edit derived publication mirrors, generated demo-config files, or frontend generated
  outputs; regenerate them from the owning command instead.
- Keep generated build output, generated contracts, generated protobuf bindings, and test artifacts
  out of tracked source even when they are present locally.
- Do not preserve or recreate retired `*.state` compatibility files for runtime results or cache
  manifests; supported reloads use protobuf-backed `*.pb` state only.
- Prefer rebuilding derived state over preserving stale compatibility copies.

## Validation

- `infernix docs check` fails if this document loses its required structure or metadata contract.
- `infernix test integration` verifies publication-state regeneration, deterministic Harbor
  PostgreSQL PV reuse across `cluster down` plus `cluster up`, and the active generated demo-config
  publication path.
- `infernix cluster status` reports the build or data roots that hold the currently relevant
  derived state.

## Cross-References

- [k8s_storage.md](k8s_storage.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../architecture/overview.md](../architecture/overview.md)
- [../tools/postgresql.md](../tools/postgresql.md)
