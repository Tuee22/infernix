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

The active runtime mode is encoded in `infernix-substrate.dhall` beside the built binary. The file
is a typed Dhall record; the schema is defined at `dhall/InfernixSubstrate.dhall` and decoded
in-process by the `dhall` Haskell library. Apple host lifecycle and validation commands
materialize or verify that file under `./.build/`, and
Linux outer-container lifecycle and validation commands materialize or verify
`/workspace/.build/outer-container/build/infernix-substrate.dhall` inside the launcher image.
`infernix internal materialize-substrate <substrate> --demo-ui <true|false>` remains
the direct helper for explicit restaging or inspection. `cluster up` publishes a cluster-role
`infernix-substrate.dhall` payload into the repo-local publication mirror and
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

On the `apple-silicon` substrate the worker runs real Apple-native inference, not a placeholder.
The runtime worker invokes the real engine for the selected binding — the Python adapter transform
over a prebuilt host wheel for python-stdio bindings, or the real native runner binary resolved
from a typed `HostConfig` absolute path for native-process-runner bindings — fetches model weights
lazily from the infernix-models MinIO bucket via `adapters.model_cache.get_model_path`, and
publishes a per-family real result: inline text for the LLM and speech families, and a typed object
reference into the infernix-demo-objects MinIO bucket for the source-separation, audio-to-MIDI,
music-transcription, image, video, audio-generation, and OMR artifact families. The native
Metal/Core ML engine artifacts the Apple worker runs are built host-side through the tart macOS VM
lane and resolved from `./.data/engines/<adapterId>/`; the canonical homes for that lane and the
typed host paths are [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md),
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md), and
[configuration_doctrine.md](configuration_doctrine.md).

## Generated Demo Config Contract

The generated demo catalog is the source of truth for the active runtime mode.

- `infernix-substrate.dhall` records every README matrix row supported by that mode and omits
  rows whose selected engine is `Not recommended`
- each generated entry records the selected engine, request shape, runtime lane, and workload
  metadata
- `infernix internal materialize-substrate <runtime-mode>` is the explicit staging helper, and
  `--demo-ui false` emits a demo-off config without hand-editing the file
- in cluster-resident execution contexts, `ConfigMap/infernix-demo-config` is mounted read-only
  beside the binary at `/opt/build/infernix-substrate.dhall`; cluster daemons read the cluster-role
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
- `cluster up` deploys the **frontend** Deployment (`infernix-demo`)
  and the **coordinator** Deployment (`infernix-coordinator`) whenever
  `demo_ui` is enabled, on every supported substrate. The **engine**
  role runs as an in-cluster `infernix-engine` Deployment on Linux
  substrates with a strict one-per-node anti-affinity rule; on `linux-gpu`,
  Python-native framework work can use additional
  `infernix-engine-<engine>` per-engine Deployments selected by
  `inference.batch.linux-gpu.<engine>` topics. Repo-owned `linux-gpu`
  lifecycle values keep those per-engine deployments at zero replicas on
  the single-GPU lane and validation scales one at a time. Apple silicon runs
  the engine role as the on-host `infernix service` daemon. The chart
  ships `chart/templates/deployment-{coordinator,engine,demo}.yaml`,
  `clusterServiceEnabled` returns `False` on every substrate, and
  `finalPhaseDeployments` waits on
  `deployment/infernix-{coordinator,engine}` plus the Linux GPU
  per-engine Deployment set when rendered. The Apple lane's
  cluster-coordinator-to-host-engine batch bridge carries Apple-native
  inference handoff.
- on `apple-silicon`, the clustered `infernix-demo` path runs from the
  `infernix-linux-cpu:local` image family while reading the staged `apple-silicon` substrate file
- the direct `infernix service` command remains the Apple host engine-role entrypoint and
  consumes the generated engine-role metadata, batch topic, result topic, and engine bindings
  from the active `.dhall`
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
