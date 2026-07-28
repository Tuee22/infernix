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
The disk model cache (`python/adapters/model_cache.py` LRU) never substitutes for the typed
execution plan. Apple and Linux CPU compilation compare each required footprint with the declared
host or pod capacity; oversized rows remain explicit `UnavailableModel` values, while fitting
placements receive indexed grants that live refinement must pair with matching enforcers. The
normal coordinator path now returns typed `ModelMemoryLimitExceeded` with explicit MiB quantities
for an unavailable request before engine launch, while smaller configured models continue to run;
the complete source-matched Phase 1 gate passed on 2026-07-25.
Linux GPU plan compilation currently fails closed with `GpuDualResourceBudgetRequired` until Phase 6
provides dual RAM/VRAM enforcement. The executable-gated capped-engine contract is owned canonically by
[../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md).

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
| PVC-backed retained data for MinIO and Pulsar, excluding the explicitly rebuildable platform-bootstrap paths below | `infernix cluster up` storage reconciliation plus the workload itself | `./.data/kind/<runtime-mode>/<namespace>/<release>/<workload>/<ordinal>/<claim>` | durable | ordinary lifecycle reruns preserve and replay the same retained data within the active runtime lane |
| Rebuildable platform-bootstrap paths: Harbor and Keycloak Patroni claim roots, Harbor Redis, and the MinIO `harbor-registry` bucket plus its bucket metadata, multipart, and temporary state | cluster lifecycle bootstrap and publication reconciliation | selected paths inside `./.data/kind/<runtime-mode>/platform/infernix/...` | derived | may be removed only after `WriterQuiesced` proves the Kind writer absent under the lifecycle lock; the next `cluster up` rebuilds database/bootstrap state and republishes Harbor content |
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
- `cluster down` plus `cluster up` must preserve retained MinIO model/demo-object data and Pulsar
  data. Apple/non-bind teardown commits a writer-frozen detached snapshot before Kind deletion and
  the next bring-up replays it before workloads start.
- Harbor/Keycloak PostgreSQL, Harbor Redis, and Harbor registry content are the explicit
  rebuildable exception. Their removal is legal only inside the post-delete `WriterQuiesced`
  region, never while a live workload can write them.
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
  can reject a request even when the weights are cache-resident on disk (canonical home:
  [../architecture/bounded_inference_memory.md](../architecture/bounded_inference_memory.md)).
- Build roots and frontend bundles are disposable because the supported build and web workflows
  regenerate them from source.
- Durable cluster-lifecycle `state` persistence replaces its `Show`/`Read` encoding with a
  fail-closed versioned aeson codec and adds phase-resume, per the managed-state-transition
  doctrine ([Managed State Transitions](../architecture/managed_state_transitions.md) is the
  canonical home). That same persisted document also names its `ClusterOwner`
  (`OperatorOwned | HarnessOwned`) and carries a first-class `ClusterMutating` position, so a
  SIGKILLed `HarnessOwned` `infernix test all` leaves `ClusterMutating` on disk as the fail-closed
  evidence the next `cluster up` reads to reconcile the interrupted mutation (uncordon drained nodes,
  scale deployments back). The owner field, mutating position, fail-closed persistence, and reconcile
  closed for their earlier scope under Wave X (Phase 2 Sprint 2.15, 2026-07-24). The 2026-07-25
  owner-atomic reservation and teardown correction remains under Phase 2 implementation and source
  review; its new source-matched Stage 1 and ordered Wave Y validation have not started.

## Cleanup Rules

- Delete durable state only through explicit operator intent such as a targeted data reset or
  manual local cleanup that accepts data loss. Ordinary supported cluster teardown preserves the
  durable retained rows and may remove only the rebuildable platform-bootstrap exception above.
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
