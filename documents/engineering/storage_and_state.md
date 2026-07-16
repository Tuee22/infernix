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

The repository follows this split. Model weights live in MinIO
`infernix-models` (always-on, eagerly staged at startup by the coordinator
from the mounted `infernix.dhall` model set), user artifacts live in MinIO
`infernix-demo-objects` (demo-gated) under each user's `sub`-derived
prefix, and the runtime model cache is
ephemeral state under `./.data/runtime/model-cache/` (on the Apple
host) or the engine pod's `emptyDir` (on Linux substrates). Durable
state: Kind PV data, reserved MinIO cluster objects, Pulsar ledgers,
protobuf-backed inference-result files, and Patroni-backed PostgreSQL
state. Derived state: `./.build/`, `/opt/build/`, generated
publication mirrors, the runtime model cache, Playwright output,
transient Kind or `nvkind` scratch kubeconfig files, and stale
repo-local kubeconfig lock files.

This inventory bounds only **disk** state; model memory is governed separately by runtime admission.
The disk model cache (`python/adapters/model_cache.py` LRU) never substitutes for the
`InferenceMemoryBudget`: Apple uses unified host RAM after the Colima pledge and reserve, Linux CPU
uses the engine pod memory limit, and Linux GPU uses GPU VRAM. An over-budget request fails with
typed `ModelMemoryLimitExceeded` and explicit MiB quantities before the engine launches, while
smaller configured models continue to run.

The durability split is unchanged by the object-access target, but how
the browser reaches the user-visible `infernix-demo-objects` bytes is
moving: at the declarative target the `infernix-demo` webapp is the
single server-side mediator for every browser upload and download
through `/api/objects`, with per-user isolation derived server-side from
the Keycloak `sub` claim. See
[../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)
and
[../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md).
**Current Status**: implemented (Phase 7 Sprint 7.25 webapp object-proxy; Phase 3 Sprint 3.13
removed the `/minio/s3` route + `presignPublicEndpoint`). The webapp reads and writes MinIO
server-side; the browser never holds a presigned MinIO URL. Wave M closed the browser object-proxy
evidence; Phase 7 Sprint 7.28 extends the same user/context prefix ownership to generated artifacts,
and Wave N closed the full selected `linux-gpu` plus `linux-cpu` cohort validation.

## Owner And Durability Table

| State class | Owner | Authoritative home | Durability | Rebuild rule |
|-------------|-------|--------------------|------------|--------------|
| PVC-backed cluster data for Harbor, MinIO, Pulsar, and PostgreSQL | `infernix cluster up` storage reconciliation plus the workload itself | `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` | durable | do not delete implicitly; supported lifecycle reruns rebind the same deterministic host paths within the active runtime lane |
| Harbor registry content and Harbor metadata | Harbor plus operator-managed PostgreSQL | Harbor PVCs under `./.data/kind/<runtime-mode>/...` | durable | loss is a platform failure, not a cache miss |
| MinIO `infernix-models` bucket contents | coordinator's bootstrap Failover subscription + every engine pod (read) | MinIO PVCs under `./.data/kind/<runtime-mode>/...` | durable | platform model weights, tokenizers, configs under `<modelId>/<filename>` with a `<modelId>/.ready` sentinel; eagerly staged at coordinator startup and never disposed except by deliberate operator intent |
| MinIO `infernix-demo-objects` bucket contents | demo backend (webapp object-proxy, server-side PUT/GET) + engine adapters (PUT for generated artifacts) | MinIO PVCs under `./.data/kind/<runtime-mode>/...` | durable and user-visible | per-user prefixes `users/<userId>/contexts/<contextId>/{uploads,generated}/`; browsers reach it only through the webapp `/api/objects` proxy; bucket only exists when `demo_ui = true` |
| Pulsar ledgers and BookKeeper journals | Pulsar | Pulsar PVCs under `./.data/kind/<runtime-mode>/...` | durable | deletion resets message durability and is therefore explicit operator intent |
| Inference-result records | Haskell service runtime plus routed reload handlers | `./.data/runtime/results/*.pb` | durable and user-visible | reload only from protobuf-backed result files |
| Cache manifests used to inspect model-cache state | Haskell service runtime | `./.data/runtime/model-cache/<runtime-mode>/<model-id>/manifest.pb` | derived | manifests now sit beside the cached weights inside the model-cache root; rebuilding the manifest is part of `infernix cache rebuild` |
| Publication state and generated ConfigMap mirrors | cluster lifecycle and demo activation | `./.data/runtime/publication.json`, `./.data/runtime/configmaps/infernix-demo-config/` | derived but user-visible | regenerate from `cluster up`, `cluster down`, or the active generated demo config |
| Repo-local kubeconfig and chosen edge-port record | cluster lifecycle | `./.build/infernix.kubeconfig`, `./.data/runtime/infernix.kubeconfig`, `./.data/runtime/edge-port.json` | derived | recreate from the supported control-plane lifecycle; Kind and `nvkind` create or delete use transient scratch kubeconfig state under system temp and may remove stale repo-local `*.lock` artifacts automatically |
| Build roots and staged generated demo config | build or cluster lifecycle | `./.build/`, `/opt/build/` | derived | rebuild from source and the active runtime mode |
| Runtime model cache | Haskell service runtime | `./.data/runtime/model-cache/...` | derived | rebuild from durable manifests and artifacts |
| Apple adapter virtualenv | Poetry | `python/.venv/` | derived | recreate from the shared Python project |
| Playwright validation artifacts | Playwright validation tooling | Playwright default output directories such as `test-results/` and `playwright-report/` under the active runner working tree when emitted; compose-run artifacts are container-local unless explicitly bind-mounted | derived | recreate by rerunning the routed E2E validation lane |

## Failure And Rebuild Rules

- Unexpected loss of anything under the durable rows above is a correctness or durability failure,
  not a normal cleanup event.
- `cluster down` plus `cluster up` must preserve the deterministic PV inventory and host-path
  binding for the durable Harbor PostgreSQL state and the other PVC-backed workloads.
- when retained Pulsar ZooKeeper state is self-inconsistent and blocks `cluster up`, the supported
  control plane may log a targeted reset of the Pulsar claim roots for that runtime lane and retry
  once; treat that path as explicit durability repair that discards prior Pulsar message history
  in that lane
- Supported inference-result reloads depend on protobuf-backed `*.pb` records only.
- Publication mirrors, repo-local kubeconfig files, edge-port records, generated demo-config
  staging, transient Kind or `nvkind` scratch kubeconfig files, and repo-local kubeconfig lock
  artifacts are disposable because the supported lifecycle commands recreate or clean them.
- Model-cache directories are disposable because the durable MinIO
  `infernix-models` bucket is the rebuild input: the engine pod's
  `/model-cache` (Linux substrates) or the host's
  `./.data/runtime/model-cache/` (Apple silicon) repopulates from
  MinIO on the next adapter call via
  `python/adapters/model_cache.get_model_path`. This disposability is a
  **disk**-state property only. Model memory is handled by the typed runtime admission policy and
  can reject a request even when the weights are cache-resident on disk.
- Build roots and frontend bundles are disposable because the supported build and web workflows
  regenerate them from source.
- Durable cluster-lifecycle `state` persistence replaces its `Show`/`Read` encoding with a
  fail-closed versioned aeson codec and adds phase-resume, per the managed-state-transition
  doctrine ([Managed State Transitions](../architecture/managed_state_transitions.md) is the
  canonical home).

## Cleanup Rules

- Delete durable state only through explicit operator intent such as supported cluster teardown,
  targeted data reset, or manual local cleanup that accepts data loss.
- when `cluster up` logs the targeted Pulsar claim-root reset described above, treat it as
  operator-visible data loss for the affected runtime lane rather than as implicit cache cleanup.
- Do not hand-edit derived publication mirrors, generated demo-config files, or frontend generated
  outputs; regenerate them from the owning command instead.
- Do not preserve repo-local kubeconfig lock files as authoritative state; supported lifecycle
  commands may delete and recreate them while publishing the durable repo-local kubeconfig.
- Keep generated build output, generated contracts, generated protobuf bindings, and test artifacts
  out of tracked source even when they are present locally.
- Supported reloads use protobuf-backed `*.pb` state only.
- Prefer rebuilding derived state over preserving stale compatibility copies.

## Validation

- `infernix docs check` fails if this document loses its required structure or metadata contract.
- `infernix test integration` verifies publication-state regeneration, deterministic Harbor
  PostgreSQL PV reuse across `cluster down` plus `cluster up`, and the active generated demo-config
  publication path.
- `infernix cluster status` reports the build or data roots that hold the active
  derived state.

## Cross-References

- [k8s_storage.md](k8s_storage.md)
- [model_lifecycle.md](model_lifecycle.md)
- [../architecture/overview.md](../architecture/overview.md)
- [../architecture/object_access_doctrine.md](../architecture/object_access_doctrine.md)
- [../architecture/tenant_isolation_doctrine.md](../architecture/tenant_isolation_doctrine.md)
- [../tools/postgresql.md](../tools/postgresql.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
