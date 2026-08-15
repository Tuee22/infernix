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

The active runtime mode is encoded in repo-root `./infernix.dhall`. The file is a typed Dhall
record; the schema is reflected from the substrate decoder type
(`infernix internal dhall-schema substrate`) and decoded in-process by the `dhall` Haskell library.
`infernix init` creates operator runtime config and `infernix test init` creates the harness input;
ordinary config-dependent commands validate the file and fail fast naming the required init when it
is absent. `cluster up` derives a cluster-role payload into the repo-local publication mirror and
`ConfigMap/infernix-demo-config`; on Apple this payload is rendered from the initialized runtime
metadata and `demo_ui` setting rather than copying a build-root file.

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
`adapters.model_cache.get_model_path`, and publishes the typed per-family result surface. Realness
is guaranteed by construction — the Apple engine code cannot return a fabricated result (enforced by
the realness lint). On `apple-silicon` there are no in-cluster engine pods. The execution-plan
compiler accounts for each configured model as a fitting placement or explicit unavailable model
against the checked host partition; package-owned live observations then refine fitting placements
into `ExecutableModel`. The supported daemon runs fresh engine subprocesses under a process-local
serialization lock and an Apple physical-footprint watchdog. A configured over-capacity model must
publish a clean typed `ModelMemoryLimitExceeded` result without launch, while smaller compiled
placements keep serving. The serialization authority remains inside the opaque engine capability,
and the Apple watchdog's adversarial breach gate must leave the daemon alive with a typed failure.
See the Per-Substrate Inference RAM Budget section below for the budget contract. Apple native engine artifacts resolve from `./.data/engines/<adapterId>/` and the
materialization contract is Tart-free: a typed engine-artifact manifest surface uses public
upstream MLX GPU execution and coremltools device observation without repository-owned native
source. No Tart or native bridge helper path exists; the retained command name
writes typed manifests without a VM dependency. The canonical homes are
[../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md),
[../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md), and
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md).

On Linux substrates, `infernix internal materialize-linux-native-engines` bakes image-owned
`/opt/infernix/engines/<adapterId>/` roots with typed manifests. Those roots contain metadata, not
generated command wrappers. A Cabal-hidden target catalog selects the image-owned llama.cpp or
whisper.cpp executable, the fixed Python interpreter plus runner module, or the Audiveris JRE and
classpath directly. Materialization records a closed target-contract fingerprint and exact
descriptor-derived executable and immutable-closure evidence for every absolute image target.
Runtime revalidates that evidence before launch and compiles only target-specific argument forms.
The image build installs the native payload layer for llama.cpp and whisper.cpp using the image
architecture (`linux/amd64` or `linux/arm64`), plus Basic Pitch's ONNX model, ONNX
Runtime/CTranslate2 Python dependencies, faster-whisper, and Audiveris app jars with an
image-architecture Temurin 25 JRE. Realness for this direct-target topology is enforced in the
engine code by the realness lint.

## Per-Substrate Inference Memory Budget

The generated substrate config carries a resource-specific inference memory budget used by a shared
pure admission policy. Each `ModelDescriptor` records a required, positive `ModelMemoryFootprint`
(the wire field stays `modelRamFootprintMib`, MiB, but decode fails closed if it is absent or
non-positive), and `DemoConfig` records an `InferenceMemoryBudget` value instead of using integer
sentinels. The shape names its enforcer:

- `HostEnforcedBudget HostMemoryPartition` means the host itself owns the ceiling: admission draws
  from the partition's `inferenceCapacity` and the on-host capped-engine kernel enforces the admitted
  ceiling at runtime (the `apple-silicon` lane)
- `SubstrateEnforcedBudget PodMemoryLimit` carries substrate RAM capacity. On `linux-cpu` it
  supplies the configured outer pod envelope; refinement additionally requires the
  live process-group RSS sampler and exact `memory.max`
- `compileRuntimePlan` validates each model against the budget and mints
  `MemoryGrant resource` only inside `CompiledPlacement`; an over-capacity model remains in the
  explicit unavailable map with
  `InferenceError.ModelMemoryLimitExceeded { modelId, requiredMib, availableMib, resource, source }`
- package-owned live observations refine a compiled grant/enforcer plan into an
  `EnforcedGrant resource` inside `ExecutableModel`; public engine launch accepts only that whole
  executable capability

There is no hardcoded capacity floor such as `max 1024 ...` and no "enforced by nobody" arm: an
over-pledged Apple host is rejected when the `HostMemoryPartition` smart constructor refuses
the oversubscription, and a model whose footprint exceeds the resolved `inferenceCapacity` fail-closes
cleanly at admission. Validation may report capacity diagnostics, but it must not reject the entire
daemon solely because one configured model exceeds the current budget. The smaller configured models
still serve.

Budget sources are substrate-specific while admission and error construction stay DRY:

- on `apple-silicon`, the budget is a `HostEnforcedBudget` over a checked `HostMemoryPartition`: host
  physical RAM (`sysctl -n hw.memsize`, via the manifest `HostSysctl` tool) split into the Colima VM
  pledge (`vmReserve`, read-only `colima list --json`, read but never managed), a `minHostHeadroomMib`
  headroom whose co-tenants are enumerated once by
  [bounded_inference_memory.md](bounded_inference_memory.md), and the
  remaining `inferenceCapacity`, with resource `UnifiedHostRam`
- on `linux-cpu`, the budget is a `SubstrateEnforcedBudget` whose `PodMemoryLimit` records the
  Kubernetes engine pod memory limit for the active cluster workload, with resource `PodRam`; this is
  the real cluster cap and must participate in runtime admission
- on `linux-gpu`, an executable placement needs independently indexed pod-RAM and GPU-VRAM grants;
  a plan that names only one resource fails closed with `GpuDualResourceBudgetRequired`

Compilation, rather than an independently recomputed request-time check, is the shared pure admission
boundary. When a footprint exceeds capacity, the compiled unavailable entry supplies the typed
failure. A fitting placement receives a resource-indexed grant and can launch only after refinement
pairs it with a verified matching enforcer inside `ExecutableModel`. On
`apple-silicon` a fixed, bounded `/usr/bin/top` plus `/usr/bin/footprint` observer measures the
child process group's physical footprint without direct FFI or a caller-supplied command, and the
watchdog SIGKILLs that group on a measured ceiling breach. That path produces a typed
`status=failed ModelMemoryLimitExceeded`, and the single-flight authority remains encapsulated so
aggregate concurrent overcommit is unrepresentable. The browser renders
`ModelMemoryLimitExceeded` as a helpful capacity error naming
the model footprint and available memory in MiB.

Linux CPU refinement probes the process-group RSS sampler and exact larger cgroup envelope under the
same opaque serialization authority. CUDA OOM classification is not proof of an installed VRAM
limit, so Linux GPU refinement requires independent live NVIDIA accounting.
Engine members do not become ready until the selected enforcer has been verified against the compiled
execution plan.

The per-substrate `InferenceMemoryBudget` / `ModelMemoryLimitExceeded` typed ADT — a typed
evidence value rather than integer sentinels — is the in-repo precedent that the managed
state-transition doctrine generalizes; its canonical home is
[Managed State Transitions](managed_state_transitions.md).

**Memory-safety by construction.** The admission above proves a request *fits* before launch; the
capped-engine kernel additionally measures the engine subprocess's *actual* resident memory against
that decision and terminates it on breach, closing a gap a full-suite run once exercised as a host
OOM-kill. "By construction" describes the *admission* — an engine cannot launch without a matching
grant and enforcer — not the runtime enforcement, which is a fixed-cadence sampler. Compilation and live
refinement create an `ExecutableModel` carrying the matching resource-indexed grant/enforcer pair over a
checked `HostMemoryPartition` (physical minus the co-tenant pledge minus a headroom that covers the OS
and the routed end-to-end browser, rejecting oversubscription) with a required `ModelMemoryFootprint`
and an enforcer-typed budget (`HostEnforcedBudget` / `SubstrateEnforcedBudget`, with no unenforced
arm). Its canonical home is [bounded_inference_memory.md](bounded_inference_memory.md).

## Generated Demo Config Contract

The generated demo catalog is the source of truth for the active runtime mode.

- `infernix.dhall` records every README matrix row supported by that mode and omits
  rows whose selected engine is `Not recommended`
- each generated entry records the selected engine, request shape, runtime lane, and workload
  metadata
- `infernix init` creates the operator's repo-root `./infernix.dhall`, and
  `infernix init --demo-ui false` emits a demo-off config without hand-editing the file
- in cluster-resident execution contexts, `cluster up` derives
  `ConfigMap/infernix-demo-config` from that initialized config and mounts the deployment mirror
  read-only at `/opt/build/infernix-substrate.dhall`; cluster daemons read the cluster-role payload
  there at startup rather than watching it for reloads
- `infernix test integration` and `infernix test e2e` enumerate every generated catalog entry for
  the active runtime mode rather than using a smoke subset

## Service Placement

Service placement is a separate concept from runtime mode. The supported
shape is the three-role daemon model codified in
[daemon_topology.md](daemon_topology.md):

- Apple host-native execution context means the supported `cluster up`, `cluster status`, and
validation commands run through `./.build/infernix` on the host; it does not mean the supported
clustered service daemons stay host-resident after reconcile.
- `cluster up` deploys the
**coordinator** Deployment (`infernix-coordinator`) on every supported substrate. The **frontend**
Deployment (`infernix-demo`) is gated by `demo_ui`. The **engine** role runs as an in-cluster
`infernix-engine` Deployment on Linux substrates through Kubernetes engine pools; on `linux-gpu`,
Python-native framework work can use pool-specific or per-engine Deployments selected by derived
pool/model topics. Repo-owned `linux-gpu` lifecycle values may keep heavyweight per-engine
deployments at zero replicas on the single-GPU lane and validation scales one at a time. Apple
silicon runs eligible engine-pool members as on-host `infernix service` daemons. Host-native Apple
generated Helm values use one local Harbor instance, one Pulsar instance, one coordinator process,
and one demo process on the already selected native arm64 Docker daemon so the real Apple engine
gate fits constrained Colima memory; Linux generated values use the single-node platform defaults
on every lane. This single-instance sizing bounds the control-plane services; the on-host `infernix service`
inference RAM is separately bounded by the typed resource-admission policy (see Per-Substrate
Inference Memory Budget), so peak *inference* memory stays within its
declared budget. Host memory as a whole has other claimants — including the host toolchain — and is
owned by [bounded host memory](bounded_host_memory.md). The chart ships
`chart/templates/deployment-{coordinator,engine,demo}.yaml`, `clusterServiceEnabled` returns `False`
on every substrate, and `finalPhaseDeployments` waits on `deployment/infernix-{coordinator,engine}`
plus the Linux GPU per-engine Deployment set when rendered. The Apple lane's cluster coordinator
publishes Apple-native work to derived pool/model topics consumed by eligible on-host engine
members.
- on `apple-silicon`, the clustered `infernix-demo` path runs from the
`infernix-linux-cpu:local` image family while reading the cluster-role deployment mirror derived
from the initialized `apple-silicon` runtime config.
- the direct `infernix service` command is
the Apple host engine-role entrypoint and consumes the generated engine-role metadata, pool/member
assignments, result topic, and engine bindings from the active `.dhall`. Generated engine-role
metadata is derived from the validated pool/member graph and serialized in the substrate file; raw
batch-topic metadata is not part of the supported surface.
- `/api/publication` keeps
`apiUpstream.mode: cluster-demo` for the stable routed browser host, reports `daemonLocation:
cluster-pod` for the in-cluster coordinator daemon on every substrate, reports
`inferenceExecutorLocation: control-plane-host` on Apple, and distinguishes the inference lane with
`inferenceDispatchMode: pulsar-bridge-to-host-daemon` on Apple versus
`pulsar-bridge-to-cluster-daemon` on Linux (the latter terminates at the in-cluster engine
Deployment).
- cluster-resident daemons read the Pulsar WebSocket and admin transport from the
mounted `ClusterConfig`; host-side tooling that runs outside a pod auto-discovers Pulsar's direct,
un-gated proxy NodePort transport (the real `/admin/v2` and `/ws/v2` surfaces, not the
Keycloak-JWT-gated `/pulsar/admin` Envoy edge) when no mounted manifest is present and the cluster
exists — Apple host-native runs resolve it from the published cluster state on the loopback
NodePort, and the Linux outer-container flows reach the same proxy NodePort on the control-plane
node IPv4 over the joined `kind` network; unit-level harnesses can still exercise the repo-local
topic spool under `./.data/runtime/pulsar/` when those endpoints are intentionally absent.
- direct
host runs and cluster-resident placements both launch the same process-isolated engine-worker
contract; commands derive only from the engine binding carried by `ExecutableModel`, with no
adapter-command override. Fitting models launch only through the refined executable capability.
- empty-model, unknown-model, wrong-route, and malformed coordinator/engine inputs terminate as
failed results before their file source is removed or Pulsar message acknowledged; no fallback
engine route exists.
- switching runtime modes changes generated catalog content and engine bindings, not the service
placement contract.

## Cross-References

- [overview.md](overview.md)
- [web_ui_architecture.md](web_ui_architecture.md)
- [daemon_topology.md](daemon_topology.md)
- [model_catalog.md](model_catalog.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
- [Managed State Transitions](managed_state_transitions.md)
