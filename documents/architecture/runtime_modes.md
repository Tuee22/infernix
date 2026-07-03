# Runtime Modes

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [daemon_topology.md](daemon_topology.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Describe the supported control-plane execution contexts, service placement options,
> and the three product runtime modes.

## Control-Plane Execution Contexts

The control-plane execution context answers where `infernix` runs.

- Apple host-native execution context runs `./.build/infernix` directly on the host
- Linux outer-container execution context runs `docker compose run --rm infernix infernix ...`

Both execution contexts use the same runtime-mode ids, generated demo-config contract, and
repo-local durable state root under `./.data/`.

## Runtime Modes

The runtime mode answers which engine column from the root README matrix is active for generated
demo catalog entries, service binding, and validation.

| Runtime mode | Canonical mode id | Engine column selected from the README matrix |
|--------------|-------------------|-----------------------------------------------|
| Apple Silicon / Metal | `apple-silicon` | `Best Apple Silicon engine` |
| Ubuntu 24.04 / CPU | `linux-cpu` | `Best Linux CPU engine` |
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-gpu` | `Best Linux CUDA engine` |

The active runtime mode is encoded in `infernix.dhall` beside the built binary. The file
is a typed Dhall record; the schema is reflected from the substrate decoder type (`infernix internal dhall-schema substrate`) and decoded
in-process by the `dhall` Haskell library. Apple host lifecycle and validation commands
materialize or verify that file under `./.build/`, and
Linux outer-container lifecycle and validation commands materialize or verify
`/workspace/.build/outer-container/build/infernix.dhall` inside the launcher image.
`infernix internal materialize-substrate <substrate> --demo-ui <true|false>` remains
the direct helper for explicit restaging or inspection. `cluster up` publishes a cluster-role
`infernix.dhall` payload into the repo-local publication mirror and
`ConfigMap/infernix-demo-config`; on Apple this cluster-role payload is rendered from the active
staged substrate metadata and `demo_ui` setting instead of copying the host-role file under
`./.build/` verbatim.

## Substrate Architecture

Each supported substrate uses native container architecture only. Apple Silicon runs natively as
`linux/arm64`. `linux-cpu` supports native Linux hosts on both `linux/amd64` and `linux/arm64`.
`linux-gpu` is the amd64 CUDA lane. Development and validation never use cross-architecture
emulation; there is no supported Rosetta, QEMU, or amd64-on-Apple validation path.

| Substrate | Linux container architecture | Source of truth |
|-----------|------------------------------|-----------------|
| `apple-silicon` | `linux/arm64` | `clusterWorkloadArchitectureForHostArchitecture` in `src/Infernix/Cluster.hs` |
| `linux-cpu` | native host Linux architecture: `linux/amd64` or `linux/arm64` | same |
| `linux-gpu` | `linux/amd64` | same |

Harbor publication pulls each upstream multi-arch image with the substrate's architecture
override (`--platform linux/<arch>` for Docker, `--override-arch=<arch>` for the `skopeo copy`
fallback) and pushes the matching single-platform variant into the cluster's Harbor namespace.
Kind worker nodes then pull the architecture-matched image from Harbor without any
cross-architecture translation. Apple Silicon workflows must not create or switch Docker contexts
or create a Colima VM; Docker-backed Apple work uses the operator's already selected native arm64
Docker daemon or stops at prerequisite validation. The supported MinIO image inventory uses upstream multi-arch
images (`minio/minio`, `minio/mc`, `busybox`) instead of single-architecture amd64-only
packaging; see [../tools/minio.md](../tools/minio.md) for the canonical
inventory.

## Apple-Native Inference

On the `apple-silicon` substrate the worker dispatches to Apple-native engine entrypoints, not to a
generic placeholder branch. The runtime worker invokes the selected Python adapter or native runner,
streams model weights from the eagerly pre-staged `infernix-models` MinIO bucket via
`adapters.model_cache.get_model_path`, and publishes the typed per-family result surface. Realness is
guaranteed by construction — the Apple engine code cannot return a fabricated result (enforced by the
realness lint). Phase 1 Sprint 1.15 materializes real Apple native engine roots, replacing the former
validation wrappers; Wave L records routed real-output proof for the then-active Apple catalog. Apple native engine artifacts resolve from
`./.data/engines/<adapterId>/` and the supported materialization target is Tart-free: a fixed host
Metal bridge for runtime Metal source compilation plus typed engine-artifact manifests for Core ML
and native runner payloads. The former Tart helper path has been removed; the retained command name
now writes typed manifests without a VM dependency. The canonical homes are
[../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md),
[../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md), and
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md).

On Linux substrates, `infernix internal materialize-linux-native-engines` bakes image-owned
`/opt/infernix/engines/<adapterId>/` roots with typed manifests and smoke-validated runner
entrypoints. The image build now installs the native payload layer for llama.cpp and whisper.cpp
using the image architecture (`linux/amd64` or `linux/arm64`), plus Basic Pitch's ONNX model, ONNX
Runtime/CTranslate2 Python dependencies, faster-whisper, and Audiveris app jars with an
image-architecture Temurin 25 JRE. Generated wrappers fail with exit 75 until the requested model
cache contains a `.ready` sentinel, can emit a local artifact-file marker for Haskell-owned MinIO
upload, and delegate strict smoke checks to those baked payloads, including launching Audiveris
through Java on the native image architecture. The reopened Phases 4/6 own full routed
`linux-gpu` plus `linux-cpu` real-output delivery, with realness enforced in the engine code by the
realness lint. Wave K proves the then-active Linux catalogs; Wave O owns proof for the MT3 rows added
on 2026-06-30.

## Generated Demo Config Contract

The generated demo catalog is the source of truth for the active runtime mode.

- `infernix.dhall` records every README matrix row supported by that mode and omits
  rows whose selected engine is `Not recommended`
- each generated entry records the selected engine, request shape, runtime lane, and workload
  metadata
- `infernix internal materialize-substrate <runtime-mode>` is the explicit staging helper, and
  `--demo-ui false` emits a demo-off config without hand-editing the file
- in cluster-resident execution contexts, `ConfigMap/infernix-demo-config` is mounted read-only
  beside the binary at `/opt/build/infernix.dhall`; cluster daemons read the cluster-role
  payload there at startup rather than watching it for reloads
- `infernix test integration` and `infernix test e2e` enumerate every generated catalog entry for
  the active runtime mode rather than using a smoke subset

## Service Placement

Service placement is a separate concept from runtime mode. The supported
target shape is the three-role daemon model codified in
[daemon_topology.md](daemon_topology.md):

- Apple host-native execution context means the supported `cluster up`, `cluster status`, and
  validation commands run through `./.build/infernix` on the host; it does not mean the supported
  clustered service daemons stay host-resident after reconcile
- `cluster up` deploys the **coordinator** Deployment (`infernix-coordinator`) on every supported
  substrate. The **frontend** Deployment (`infernix-demo`) is gated by `demo_ui`. The **engine**
  role runs as an in-cluster `infernix-engine` Deployment on Linux
  substrates through Kubernetes engine pools; on `linux-gpu`, Python-native framework work can use
  pool-specific or per-engine Deployments selected by derived pool/model topics. Repo-owned
  `linux-gpu` lifecycle values may keep heavyweight per-engine deployments at zero replicas on the
  single-GPU lane and validation scales one at a time. Apple silicon runs eligible engine-pool
  members as on-host `infernix service` daemons. Host-native Apple generated Helm values use one
  local Harbor/Pulsar/coordinator/demo replica on the already selected native arm64 Docker daemon
  so the real Apple engine gate fits constrained Colima memory; Linux generated values retain the
  HA-shaped platform defaults and own the HA evidence. The chart ships
  `chart/templates/deployment-{coordinator,engine,demo}.yaml`,
  `clusterServiceEnabled` returns `False` on every substrate, and
  `finalPhaseDeployments` waits on
  `deployment/infernix-{coordinator,engine}` plus the Linux GPU
  per-engine Deployment set when rendered. The Apple lane's
  cluster coordinator publishes Apple-native work to derived pool/model topics consumed by
  eligible on-host engine members.
- on `apple-silicon`, the clustered `infernix-demo` path runs from the
  `infernix-linux-cpu:local` image family while reading the staged `apple-silicon` substrate file
- the direct `infernix service` command remains the Apple host engine-role entrypoint and
  consumes the generated engine-role metadata, pool/member assignments, result topic, and engine
  bindings from the active `.dhall`. Generated engine-role metadata is derived from the validated
  pool/member graph and serialized in the substrate file; raw batch-topic metadata is not part of
  the supported surface
- `/api/publication` keeps `apiUpstream.mode: cluster-demo` for the stable routed browser host,
  reports `daemonLocation: cluster-pod` for the in-cluster coordinator daemon on every substrate,
  reports `inferenceExecutorLocation: control-plane-host` on Apple, and distinguishes the
  inference lane with `inferenceDispatchMode: pulsar-bridge-to-host-daemon` on Apple versus
  `pulsar-bridge-to-cluster-daemon` on Linux (the latter terminates at the in-cluster engine
  Deployment)
- cluster-resident daemons read the Pulsar WebSocket and admin transport from the mounted
  `ClusterConfig`; host-side tooling that runs outside a pod auto-discovers Pulsar's direct,
  un-gated proxy NodePort transport (the real `/admin/v2` and `/ws/v2` surfaces, not the
  Keycloak-JWT-gated `/pulsar/admin` Envoy edge) when no mounted manifest is present and the cluster
  exists — Apple host-native runs resolve it from the published cluster state on the loopback
  NodePort, and the Linux outer-container flows reach the same proxy NodePort on the control-plane
  node IPv4 over the joined `kind` network; unit-level harnesses can still exercise the repo-local
  topic spool under `./.data/runtime/pulsar/` when those endpoints are intentionally absent
- direct host runs and cluster-resident placements both launch the same process-isolated
  engine-worker contract and honor the same adapter-specific command overrides
- switching runtime modes changes generated catalog content and engine bindings, not the service
  placement contract

## Cross-References

- [overview.md](overview.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [daemon_topology.md](daemon_topology.md)
- [model_catalog.md](model_catalog.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
