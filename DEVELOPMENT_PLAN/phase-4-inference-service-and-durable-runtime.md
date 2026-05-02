# Phase 4: Inference Service and Durable Runtime

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the Haskell service runtime, the shared Python engine-adapter contract, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the shared Linux substrate image, the
> substrate-generated `.dhall` control contract, and the Apple host-native inference bootstrap that
> together make the runtime model honest and durable.

## Phase Status

Sprints 4.1 through 4.11 remain `Done` as the current implementation baseline, but Phase 4 is
reopened by Sprint 4.12. The current worktree still keeps filesystem-backed Pulsar fallback,
runtime-mode-selected catalog inputs, and an Apple host bridge story that the new substrate-only
doctrine no longer accepts.

## Current Repo Assessment

The repository already has typed request or response shapes, typed runtime result metadata, a
README-matrix-backed generated catalog, protobuf-backed manifest and result helpers, explicit cache
status or eviction or rebuild flows, repo-local durable object-store state under
`./.data/object-store/`, a shared Python adapter project whose setup entrypoints write idempotent
bootstrap manifests and whose workers derive deterministic engine-family-specific output from
durable bundle or manifest metadata, an opt-in real Pulsar WebSocket or admin transport path with
filesystem fallback, and a manual inference API path served by the Haskell demo surface. The Apple
host-native lane also has daemon-driven Poetry-project and setup-entrypoint bootstrap through
`src/Infernix/Engines/AppleSilicon.hs`, and the shared Linux substrate image carries the
source-snapshot manifest so `infernix lint files` remains honest in git-less image runs.

The remaining Phase 4 gap is contract ownership. The final doctrine requires the compile-time
generated substrate `.dhall` to drive daemon placement, substrate identity, and engine selection;
requires Apple demo inference to depend on the host daemon while the routed demo app stays
cluster-resident; and removes simulation code paths from the supported steady-state runtime.

## Substrate Config Ownership Contract

This phase owns the conversion from the README-scale matrix to runtime-consumable substrate state.

- the service owns the typed registry that represents matrix rows
- the built substrate selects the engine column for each supported row
- the compile-time generated substrate `.dhall` carries that selected catalog beside the binary
- host and cluster consumers use that same substrate file as the exact runtime catalog
- `infernix-demo` and the integration suite both choose the active engine binding for a README row
  from that same substrate file

## Remaining Work

- close Sprint 4.12 so daemon placement, reload behavior, and transport ownership align with the
  substrate-generated `.dhall` doctrine

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Storage.hs`, `proto/infernix/api/inference_service.proto`, `proto/infernix/manifest/runtime_manifest.proto`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`

### Objective

Make the service runtime strongly typed before transport and UI surfaces accumulate logic.

### Deliverables

- Haskell-owned ADTs for cluster state, generated demo config, model catalog entries, inference
  request shapes, and inference result shapes
- one canonical model catalog surface that lists every registered model the UI may target
- explicit distinction between authoritative durable metadata and derived local cache state
- repo-owned `.proto` schemas under `proto/` define the durable runtime-manifest, inference-payload,
  and service-event message names

### Validation

- `infernix test unit` covers runtime-mode selection, generated catalog counts, per-mode row
  inclusion or omission, generated demo-config rendering, invalid startup handling, and protobuf
  round-trips
- `infernix test lint` passes `infernix lint proto` against the repo-owned `.proto` set

### Remaining Work

None.

---

## Sprint 4.2: Inference Request Pipeline Over the Durable Object Store and Pulsar Contract [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Cache.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Demo/Api.hs`, `python/adapters/`, `infernix.cabal`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`

### Objective

Use the repo-local durable object store and the topic-shaped Pulsar contract without letting
derived local cache state become authoritative.

### Deliverables

- the service runtime stores durable manifests, artifacts, and large outputs under the repo-local
  object-store root `./.data/object-store/`
- the service runtime consumes inference requests and publishes results through the topic-shaped
  Pulsar contract, using real Pulsar endpoints only when configured and otherwise falling back to
  the filesystem simulation under `./.data/runtime/pulsar/`
- durable runtime bundles record engine-adapter identity, authoritative source-artifact metadata,
  and selected engine-ready artifacts
- process-isolated runtime workers honor adapter-specific command overrides when configured and
  otherwise use the canonical engine runner contract
- local materialization remains cache-oriented and idempotent, not authoritative

### Validation

- `infernix test integration` proves generated catalog publication, per-entry routed inference
  execution for the active-mode catalog, Pulsar schema publication, and filesystem-backed topic or
  result persistence on the validated path
- `infernix test unit` proves large outputs return typed object references and protobuf manifests
  round-trip through the supported storage helpers

### Remaining Work

None.

---

## Sprint 4.3: Honest Apple Host-Native and Linux Container Runtime Parity [Done]

**Status**: Done
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/object_storage.md`, `documents/operations/apple_silicon_runbook.md`, `documents/engineering/portability.md`

### Objective

Keep one service contract while telling the truth about runtime placement: Apple inference is
host-native by design, while Linux CPU and Linux CUDA are containerized lanes.

### Deliverables

- `infernix service` supports host-native Apple execution for the `apple-silicon` runtime mode
- the same executable runs in cluster pods for `linux-cpu` and `linux-cuda`
- service placement changes only publication context, generated-config source, and optional
  transport-endpoint wiring, not the request or result or catalog contract
- the current validated durable object-store contract remains repo-local `./.data/object-store/`,
  and real Pulsar transport is enabled only when the documented environment variables are set
- the shared abstraction lives at the control plane, publication, config, Pulsar, protobuf, and
  routed API or UI levels rather than a false claim of identical image layout across all lanes
- startup reports whether the daemon is running host-side or cluster-side

### Validation

- Apple host-native `infernix service` reports host-side daemon metadata and consumes the same
  generated catalog contract as the cluster path
- cluster-resident `infernix service` consumes the same generated catalog contract and
  route-or-publication semantics on the cluster path
- switching runtime modes changes generated catalog content and engine bindings, not the browser base URL

### Remaining Work

None.

---

## Sprint 4.4: Demo Inference API Surface [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Models.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`

### Objective

Expose a stable demo HTTP API surface for listing models and submitting manual inference requests
from the browser while keeping production inference Pulsar-only.

### Deliverables

- typed handlers for listing models, inspecting model request shape, submitting inference, and
  retrieving results, all exposed by `infernix-demo`
- request validation uses the same Haskell-owned model metadata used by the production path
- the manual inference path can target any model present in the generated catalog
- the demo surface dispatches into the same Haskell runtime contract that production
  `infernix service` uses

### Validation

- `infernix test e2e` proves routed model listing and manual inference submission through `/api`
- direct API calls return typed model metadata and stored results
- invalid requests fail with typed user-facing errors

### Remaining Work

None.

---

## Sprint 4.5: Durable Service Cache and Reconcile Semantics [Done]

**Status**: Done
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Storage.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/engineering/model_lifecycle.md`, `documents/engineering/storage_and_state.md`

### Objective

Make derived runtime state reproducible from durable sources and keep lifecycle cleanup explicit.

### Deliverables

- local service cache roots live under `./.data/runtime/`
- cache directories are keyed by model identity and runtime mode
- durable cache manifests under `./.data/object-store/manifests/` act as rebuild sources
- `cache status`, `cache evict`, and `cache rebuild` are explicit operator flows

### Validation

- `infernix test unit` proves cache materialization, eviction, and rebuild behavior
- `infernix test integration` proves the routed cache API can materialize and rebuild cache entries
- `cluster status` distinguishes cache, object-store, and manifest counts

### Remaining Work

None.

---

## Sprint 4.6: Comprehensive Matrix Registry and Initial Generated Demo `.dhall` Baseline [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`

### Objective

Turn the README matrix into the typed source of truth that drives the current runtime binding and
generated demo-catalog baseline before the later substrate-generated file reset lands.

### Deliverables

- the service owns a typed registry for every row in the README matrix
- each row records workload identity, artifact or format family, reference model metadata, and
  per-mode engine bindings
- rows whose active-mode column is `Not recommended` are absent from that mode's generated catalog
- across `apple-silicon`, `linux-cpu`, and `linux-cuda`, the generated catalogs cover every README
  row that names a real engine

### Validation

- unit tests prove generated catalog counts and per-mode row inclusion or omission
- frontend contract checks prove the generated active-mode contract carries selected engines and runtime metadata
- integration fixtures prove the published ConfigMap matches the generated active-mode catalog

### Remaining Work

None.

---

## Sprint 4.12: Substrate-Owned Daemon Placement, Reload Control, and Fallback Removal [Blocked]

**Status**: Blocked
**Blocked by**: Sprint 0.8, Sprint 1.10, Sprint 2.9, Sprint 3.9
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make daemon behavior derive entirely from the compile-time generated substrate `.dhall` and remove
the remaining supported simulation assumptions from the runtime contract.

### Deliverables

- `infernix service` derives its active substrate from the colocated substrate `.dhall` and no
  longer accepts `--runtime-mode` or `INFERNIX_RUNTIME_MODE`
- `infernix-demo` and any runtime-owned manual inference entrypoint choose the engine binding for a
  given README row only from the colocated or ConfigMap-backed substrate `.dhall`
- the Apple host daemon is the authoritative inference engine for `apple-silicon`, and the routed
  clustered demo app depends on that host daemon being live
- Linux `linux-cpu` and `linux-gpu` daemons run only as cluster-resident workloads on their
  deployed substrate images
- the daemon watches the substrate `.dhall`, reloads or restarts when it changes, and purges
  running inference-engine state during that reload
- the supported steady-state runtime removes simulated cluster, route, transport, and inference
  fallback code paths from the final contract rather than merely refusing to count them as evidence
- startup and publication reporting name substrate and daemon placement unambiguously

### Validation

- Apple host-native `infernix service` reports `apple-silicon` from the generated substrate file
  and the routed demo surface fails fast when that daemon is absent
- Linux substrate daemons read the mounted ConfigMap-backed substrate file beside the binary and do
  not rely on runtime-mode flags or environment overrides
- manual inference through `infernix-demo` and service-loop execution both use the engine binding
  selected in `.dhall` for the active README row
- runtime validation fails if the service or demo app falls back to simulated route, transport, or
  substrate behavior on a supposedly supported final lane

### Remaining Work

- Phase 6 still owns the validation entrypoints and reporting model that enforce this substrate-only
  runtime contract

---

## Sprint 4.7: Shared Python Adapter Project and Poetry-Driven Quality Gate [Done]

**Status**: Done
**Implementation**: `python/pyproject.toml`, `python/adapters/`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Models.hs`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`
**Docs to update**: `documents/development/python_policy.md`, `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`, `documents/engineering/implementation_boundaries.md`

### Objective

Collapse the Python runtime boundary to one shared project and one shared adapter tree while
keeping `poetry run` as the only supported execution path.

### Deliverables

- one shared `python/pyproject.toml` owns Python dependencies for the supported adapter set
- one shared `python/adapters/` tree contains the repo-owned adapter modules
- runtime-specific behavior stays inside the shared tree only where engine logic genuinely diverges
- per-engine setup entrypoints and adapter entrypoints are declared as Poetry console scripts
- `src/Infernix/Runtime/Worker.hs` forks `poetry run <entrypoint>` rather than raw `python`
- `poetry run check-code` is the canonical Python quality gate and runs mypy strict, black check,
  and ruff strict in sequence
- the duplicated `python/apple-silicon/`, `python/linux-cpu/`, and `python/linux-cuda/` project
  layout is removed from the supported architecture

### Validation

- `poetry run check-code` passes against the shared `python/` tree
- intentionally introducing a type, format, or ruff failure under `python/adapters/` causes the
  quality gate to fail
- `infernix test unit` exercises the Haskell worker plus a Python adapter handshake end to end
- `find python -name '*.py' -type f` returns only files under `python/adapters/`

### Remaining Work

None.

---

## Sprint 4.8: Pulsar-Driven Production Inference Surface [Done]

**Status**: Done
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `chart/templates/deployment-service.yaml`, `chart/values.yaml`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/tools/pulsar.md`, `documents/architecture/runtime_modes.md`, `documents/reference/cli_reference.md`

### Objective

Make the Pulsar-driven production inference surface the canonical way to request inference in any
non-demo deployment.

### Deliverables

- the active `.dhall` schema includes `request_topics`, `result_topic`, and engine-binding metadata
- `src/Infernix/Runtime/Pulsar.hs` subscribes to request topics, dispatches work through the
  worker, and publishes typed protobuf responses to the configured result topic
- production `infernix service` binds no HTTP port
- the production chart deploys `infernix-service` without a Kubernetes HTTP Service and without a
  fake compatibility listener

### Validation

- the routed `infernix internal pulsar-roundtrip` helper publishes a request through the final
  `/pulsar/admin` and `/pulsar/ws/v2` surfaces and observes the result end to end
- production pods bind no Infernix-owned HTTP listener
- repeat `cluster up` runs preserve the production inference surface

### Remaining Work

None.

---

## Sprint 4.9: Shared Linux Substrate Image Build and Snapshot Runtime [Done]

**Status**: Done
**Implementation**: `docker/linux-substrate.Dockerfile`, `compose.yaml`, `src/Infernix/Cluster.hs`, `src/Infernix/Lint/Files.hs`, `chart/values.yaml`, `chart/templates/deployment-service.yaml`, `.dockerignore`
**Docs to update**: `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/development/python_policy.md`, `documents/operations/cluster_bootstrap_runbook.md`

### Objective

Replace the current multi-file Linux Docker story with one shared substrate build definition that
produces the two real Linux runtime images and supports the image-snapshot launcher model.

### Deliverables

- one shared `docker/linux-substrate.Dockerfile` builds `infernix-linux-cpu` and
  `infernix-linux-cuda`
- build arguments cover at least the base image and runtime mode; shared build stages own the
  common toolchain
- `docker/linux-base.Dockerfile` is removed from the supported architecture
- the shared image definition owns ghcup-pinned GHC or Cabal, Python, Poetry, node, Playwright,
  and the Kind toolbelt
- on the supported Linux outer-container path, `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding the identical runtime image inside
  the launcher
- the CUDA image bakes in the `nvkind` binary through a multi-stage build rather than a host
  handoff path
- the baked image captures `/opt/build/infernix/source-snapshot-files.txt` before later generated
  outputs appear so git-less image runs of `infernix lint files` validate only the source snapshot
- inside the Linux runtime image, the daemon does not run `apt`, `pip`, `cabal build`, or compiler
  toolchains at runtime

### Validation

- `docker build -f docker/linux-substrate.Dockerfile --build-arg RUNTIME_MODE=linux-cpu -t infernix-linux-cpu:local .`
  succeeds on supported hosts
- `docker build -f docker/linux-substrate.Dockerfile --build-arg RUNTIME_MODE=linux-cuda -t infernix-linux-cuda:local .`
  succeeds on supported hosts
- smoke probes from the built images confirm the expected `infernix`, `ghc`, `cabal`, `python`,
  and Playwright tooling
- `infernix lint files` succeeds inside the baked Linux image without `.git` metadata by using the
  captured source-snapshot manifest
- `infernix cluster up --runtime-mode linux-cpu` and `--runtime-mode linux-cuda` use the active
  substrate image on the supported path

### Remaining Work

None.

---

## Sprint 4.10: Apple Silicon Daemon-Driven Engine Bootstrap [Done]

**Status**: Done
**Implementation**: `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `python/pyproject.toml`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/operations/apple_silicon_runbook.md`, `documents/development/local_dev.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`

### Objective

On Apple Silicon, keep inference host-native and let the daemon own engine setup without inventing
fake container parity.

### Deliverables

- `src/Infernix/Engines/AppleSilicon.hs` provides typed engine-setup steps for the host-native lane
- the daemon currently ensures the shared Poetry project, repo-local engine roots, and per-engine
  setup entrypoints on Apple Silicon
- the operator remains responsible for the host prerequisites documented in governed docs,
  including ghcup and the supported toolchain installs
- Apple adapter dependencies materialize on demand in `python/.venv/`
- the daemon uses the same per-engine Poetry entrypoints as the Linux runtime lanes

### Validation

- on a clean Apple Silicon host with ghcup installed,
  `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
  succeeds without extra supported wrapper scripts
- `./.build/infernix --runtime-mode apple-silicon cluster up` brings up the cluster and runs the
  current Apple setup entrypoints before host-side service or inference execution
- `infernix test integration --runtime-mode apple-silicon` exercises the Apple column of the README
  matrix against the host-native runtime lane

### Remaining Work

None.

---

## Sprint 4.11: Per-Mode Engine Selection in the Catalog [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Types.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Runtime/Worker.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/development/testing_strategy.md`

### Objective

Make the per-mode engine column in the README matrix the canonical input for catalog generation.

### Deliverables

- each matrix row records explicit engine selection per runtime mode
- the active runtime mode picks the appropriate engine binding when generating
  `infernix-demo-<mode>.dhall`
- the generated demo config and demo-visible surfaces expose each row through the selected engine
  for that mode
- daemon startup fails when the active mode references an engine binding whose adapter metadata is missing

### Validation

- switching runtime modes changes per-row selected engine bindings deterministically
- the generated demo-config and routed API surfaces publish the selected engine bindings for the
  active mode
- demo-config validation fails when the active mode references a selected engine with no matching
  binding metadata

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/runtime_modes.md` - honest runtime model, host-native Apple lane, and Linux substrate lanes
- `documents/architecture/model_catalog.md` - per-mode engine binding and generated catalog contract
- `documents/engineering/docker_policy.md` - shared Linux substrate image doctrine and snapshot launcher expectations
- `documents/engineering/build_artifacts.md` - build roots, generated proto handling, and image-owned toolchain contract
- `documents/engineering/model_lifecycle.md` - durable artifacts, bundle metadata, and cache semantics
- `documents/engineering/object_storage.md` - repo-local object-store rules plus reserved MinIO path and service-placement access notes
- `documents/engineering/storage_and_state.md` - durable-versus-derived state inventory
- `documents/engineering/implementation_boundaries.md` - Haskell versus Python versus chart ownership
- `documents/engineering/portability.md` - portable platform rules versus Apple or Linux substrate detail
- `documents/development/python_policy.md` - shared Python project, `poetry run` contract, and `check-code` gate
- `documents/development/testing_strategy.md` - per-mode integration coverage and engine-binding parity
- `documents/operations/apple_silicon_runbook.md` - ghcup prerequisites and daemon-driven Apple engine setup

**Product or reference docs to create/update:**
- `documents/reference/api_surface.md` - browser and operator API contract
- `documents/reference/web_portal_surface.md` - manual inference user surface

**Cross-references to add:**
- keep [00-overview.md](00-overview.md), [system-components.md](system-components.md), and
  [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) aligned when the API,
  model catalog, or generated demo-config contract changes
