# Phase 4: Inference Service and Durable Runtime

**Status**: Active (Sprint 4.13 code-side closed May 25, 2026 including the engine-command override retirement; the `linux-gpu` cluster integration validation and the MinIO endpoint/region migration paired with Sprint 7.17 secrets retirement remain open; Sprints 4.1–4.12 Done)
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [../documents/architecture/configuration_doctrine.md](../documents/architecture/configuration_doctrine.md), [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md)

> **Purpose**: Define the Haskell service runtime, the shared Python engine-adapter contract, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the shared Linux substrate image, the
> substrate-generated `.dhall` role contract, and the Apple host inference bootstrap that together
> make the runtime model honest and durable.

## Phase Status

Phase 4 is closed around the staged-substrate runtime contract, the shared Python adapter
boundary, the Pulsar-driven request or result contract, and the explicit engine-runner dispatch
implemented in this worktree. Sprints 4.1–4.12 remain `Done` for their original scope. The later
clarification that a cluster daemon always exists while Apple inference execution moves to a
same-binary host daemon is implemented in Phase 6 Sprint 6.25.

## Current Repo Assessment

The repository has typed request or response shapes, typed runtime result metadata, a
README-matrix-backed generated catalog, protobuf-backed manifest and result helpers, explicit
cache status or eviction or rebuild flows, a shared Python adapter project whose setup entrypoints
write idempotent bootstrap manifests, explicit substrate-materialization helpers, and daemon
behavior driven by the staged substrate file. Durable model artifact storage moved to the
`infernix-models` MinIO bucket under Phase 7 Sprint 7.7; the legacy `./.data/object-store/` tree
is retired and tracked in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). That file is a typed Dhall record at `infernix-substrate.dhall`, decoded
in-process by the `dhall` Haskell library. The final runtime contract distinguishes daemon role
from inference executor location:
cluster daemons exist on every substrate and own Pulsar request-topic consumption; Linux cluster
daemons run inference directly and publish results; Apple cluster daemons publish work to a
dedicated host batch topic consumed by same-binary host daemons that run Apple-native inference
and publish the completed results. The
runtime worker dispatches supported Python-native and native
adapters through explicit harness branches; the current adapters emit deterministic engine-family
output from durable metadata, and unsupported adapter ids fail fast with typed errors instead of
returning a generic success payload. The staged file, runtime result metadata, publication surface,
and browser contracts still expose the active substrate through `RuntimeMode` or `runtimeMode`
identifiers, while the final publication contract also distinguishes cluster daemon location from
host inference executor location.

## Substrate Config Ownership Contract

This phase owns the conversion from the README-scale matrix to runtime-consumable substrate state.

- the service owns the typed registry that represents matrix rows
- the built substrate selects the engine column for each supported row
- the staged substrate file carries that selected catalog beside the active build root
- host and cluster consumers use that same substrate file as the exact runtime catalog
- `infernix-demo` and the integration suite both choose the active engine binding for a README row
  from that same substrate file

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Storage.hs`, `proto/infernix/manifest/runtime_manifest.proto`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`
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

- `infernix test unit` covers generated-substrate resolution, generated catalog counts,
  per-substrate row inclusion or omission, generated demo-config rendering, invalid startup
  handling, and protobuf round-trips
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
  object-store root `./.data/object-store/` (retired by Phase 7 Sprint 7.7; durable model artifacts
  now live in the `infernix-models` MinIO bucket and the per-pod `emptyDir` model cache)
- the service runtime consumes inference requests and publishes results through the topic-shaped
  Pulsar contract, using the configured transport on supported cluster paths and the repo-local
  topic spool only in harness-oriented flows that intentionally omit those endpoints
- durable runtime bundles record engine-adapter identity, authoritative source-artifact metadata,
  and selected engine-ready artifacts
- process-isolated runtime workers honor adapter-specific command overrides when configured and
  otherwise use the canonical engine runner contract
- local materialization remains cache-oriented and idempotent, not authoritative

### Validation

- `infernix test integration` proves generated catalog publication, per-entry routed inference
  execution for the active built substrate's catalog, Pulsar schema publication, and typed topic
  or result persistence on the validated path
- `infernix test unit` proves large outputs return typed object references and protobuf manifests
  round-trip through the supported storage helpers

### Remaining Work

None.

---

## Sprint 4.3: Honest Apple Host-Native and Linux Container Runtime Parity [Done]

**Status**: Done
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/object_storage.md`, `documents/operations/apple_silicon_runbook.md`, `documents/engineering/portability.md`

### Objective

Keep one service contract while telling the truth about execution context and inference
placement: Apple control-plane commands are host-native, Apple cluster daemons own request-topic
consumption and host-batch handoff, Apple inference execution and result publication are
host-side, and Linux inference execution and result publication remain cluster-resident.

### Deliverables

- `infernix service` supports direct host-side Apple inference execution for the `apple-silicon`
  substrate when operators invoke it as a host daemon
- on `apple-silicon`, routed cluster surfaces bridge into host-side inference execution instead of
  treating a containerized Apple workload as having Metal or unified-memory inference parity
- the same executable runs in cluster pods for Linux and, under the final Phase 6 contract, for the
  Apple cluster daemon role as well
- daemon role changes only publication context, generated-config source, batch-topic wiring, and
  optional transport-endpoint wiring, not the request or result or catalog contract
- the durable object-store contract closed at Sprint 4.3 around repo-local `./.data/object-store/`
  and was retired by Phase 7 Sprint 7.7 in favor of the `infernix-models` MinIO bucket;
  real Pulsar transport is enabled either by the documented Pulsar endpoint environment variables
  or, on the Apple host-native lane, by discovering the routed Pulsar edge from publication state,
  while the filesystem topic spool remains a harness-oriented fallback when no endpoint is
  intentionally present
- the shared abstraction lives at the control plane, publication, config, Pulsar, protobuf, and
  routed API or UI levels rather than a false claim of identical image layout across all lanes
- startup reports whether the daemon is running host-side or cluster-side and which role it owns
- the current generated file, publication surface, and runtime result payloads still serialize the
  active substrate under `runtimeMode` identifiers

### Validation

- Apple host-side `infernix service` reports host inference-executor metadata and consumes the same
  generated catalog contract as the cluster-daemon paths
- routed Apple demo and transport flows reach the host inference daemon through the supported Apple
  bridge instead of a cluster-resident Apple inference workload
- cluster-resident `infernix service` on `linux-cpu` and `linux-gpu` consumes the same generated
  catalog contract and route-or-publication semantics on the cluster path
- rebuilding for a different substrate changes generated catalog content and engine bindings, not
  the browser base URL

### Remaining Work

None.

---

## Sprint 4.4: Demo Catalog and Cache HTTP API Surface [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Models.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`

### Objective

Expose the stable demo HTTP API surface that the browser consumes for catalog, publication, and
cache discovery, while keeping production inference Pulsar-only. Routed manual inference
dispatch closes through the durable-context surface introduced by Phase 7 rather than a direct
HTTP request/poll cycle owned by this sprint.

### Deliverables

- typed handlers for listing models, inspecting model request shape, reporting publication
  metadata, and observing or mutating derived cache state, all exposed by `infernix-demo`
- request validation uses the same Haskell-owned model metadata used by the production path
- the demo surface dispatches into the same Haskell runtime contract that production
  `infernix service` uses for any auxiliary discovery surfaces
- the demo HTTP surface does not carry a direct manual-inference handler in the supported final
  contract; Phase 7 owns the durable-context Chat surface that replaces it

### Validation

- `infernix test e2e` proves routed model listing, publication discovery, and cache lifecycle
  through `/api`
- direct API calls return typed model metadata, publication metadata, and cache state
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
- cache directories are keyed by model identity and substrate identifier, with current durable
  payloads still serializing that identifier as `runtimeMode`
- durable cache manifests under `./.data/object-store/manifests/` acted as rebuild sources at
  Sprint 4.5 closure; retired by Phase 7 Sprint 7.7 in favor of MinIO-backed weights with cache
  rebuildability from the Pulsar conversation log via `prefixHash`
- `cache status`, `cache evict`, and `cache rebuild` are explicit operator flows

### Validation

- `infernix test unit` proves cache materialization, eviction, and rebuild behavior
- `infernix test integration` proves the routed cache API can materialize and rebuild cache entries
- `cluster status` distinguishes cache, object-store, and manifest counts (object-store and
  on-disk manifest tracking retired by Phase 7 Sprint 7.7)

### Remaining Work

None.

---

## Sprint 4.6: Comprehensive Matrix Registry and Initial Generated Demo `.dhall` Baseline [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`

### Objective

Turn the README matrix into the typed source of truth that drives the runtime binding and
substrate-generated demo-catalog baseline.

### Deliverables

- the service owns a typed registry for every row in the README matrix
- each row records workload identity, artifact or format family, reference model metadata, and
  per-substrate engine bindings
- rows whose selected engine for a substrate is `Not recommended` are absent from that substrate's
  generated catalog
- across `apple-silicon`, `linux-cpu`, and `linux-gpu`, the generated catalogs cover every README
  row that names a real engine

### Validation

- unit tests prove generated catalog counts and per-substrate row inclusion or omission
- frontend contract checks prove the generated active-substrate contract carries selected engines
  and runtime metadata
- integration fixtures prove the published ConfigMap matches the generated active-substrate catalog

### Remaining Work

None.

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
- `poetry run check-code` is the canonical Python quality gate and runs `mypy --strict`,
  `black --check`, and `ruff check` in sequence
- the duplicated `python/apple-silicon/`, `python/linux-cpu/`, and `python/linux-gpu/` project
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
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml` (Phase 7 Sprint 7.7 split the original `chart/templates/deployment-service.yaml` into role-specific templates), `chart/values.yaml`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `proto/infernix/runtime/inference.proto`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/tools/pulsar.md`, `documents/architecture/runtime_modes.md`, `documents/reference/cli_reference.md`

### Objective

Make the Pulsar-driven production inference surface the canonical way to request inference in any
non-demo deployment.

### Deliverables

- the active `.dhall` schema includes `request_topics`, `result_topic`, daemon-role metadata, and
  engine-binding metadata; the final Apple role schema also includes host batch-topic and Pulsar
  connection-mode metadata
- `src/Infernix/Runtime/Pulsar.hs` subscribes to request topics, dispatches work through the
  worker or host-batch handoff path, and publishes typed protobuf responses to the configured
  result topic
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
  `infernix-linux-gpu`
- build arguments cover at least the base image and the substrate-selecting `RUNTIME_MODE` value;
  shared build stages own the common toolchain, and `compose.yaml` selects those inputs through
  `INFERNIX_COMPOSE_*` launcher variables without changing the supported `docker compose run --rm infernix infernix ...`
  surface
- `docker/linux-base.Dockerfile` is removed from the supported architecture
- the shared substrate image definition owns ghcup-pinned GHC or Cabal, Python, Poetry, the
  Node-based web bundle build, and the Kind toolbelt; routed Playwright execution lives in the
  separate `docker/playwright.Dockerfile` image so the substrate image carries no browser-runtime
  weight
- on the supported Linux outer-container path, `cluster up` reuses the already-built
  `infernix-linux-<mode>:local` snapshot instead of rebuilding the identical runtime image inside
  the launcher
- the CUDA image bakes in the `nvkind` binary through a multi-stage build rather than a host
  handoff path
- the baked image captures `/opt/infernix/source-snapshot-files.txt` before later generated
  outputs appear so git-less image runs of `infernix lint files` validate only the source
  snapshot; the manifest is intentionally outside the bind-mounted `./.build/` tree so it stays in
  the image overlay
- the baked image materializes a build-arg-selected substrate file inside the image overlay during
  image build, while supported Compose-launched operator commands still restage the host-visible
  `./.build/outer-container/build/infernix-substrate.dhall` after the host bind mount is applied
- inside the Linux runtime image, the daemon does not run `apt`, `pip`, `cabal build`, or compiler
  toolchains at runtime

### Validation

- `docker compose build infernix` succeeds on supported Linux CPU hosts and produces the default
  `infernix-linux-cpu:local` snapshot
- after exporting `INFERNIX_COMPOSE_IMAGE=infernix-linux-gpu:local`,
  `INFERNIX_COMPOSE_SUBSTRATE=linux-gpu`, and
  `INFERNIX_COMPOSE_BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04`,
  `docker compose build infernix` succeeds on supported Linux GPU hosts and produces the
  `infernix-linux-gpu:local` snapshot
- smoke probes from the built images confirm the expected `infernix`, `ghc`, `cabal`, `python`,
  and Node toolchain
- `infernix lint files` succeeds inside the baked Linux image without `.git` metadata by using the
  captured source-snapshot manifest
- after `docker compose run --rm infernix infernix internal materialize-substrate linux-cpu --demo-ui true`,
  `docker compose run --rm infernix infernix cluster up` uses the active built substrate image on
  the supported path

### Remaining Work

None.

---

## Sprint 4.10: Apple Silicon Daemon-Driven Engine Bootstrap [Done]

**Status**: Done
**Implementation**: `src/Infernix/Engines/AppleSilicon.hs`, `src/Infernix/Service.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/CLI.hs`, `python/pyproject.toml`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/operations/apple_silicon_runbook.md`, `documents/development/local_dev.md`, `documents/development/python_policy.md`, `documents/engineering/portability.md`

### Objective

On Apple Silicon, keep inference execution host-native and let the host daemon own engine setup
without inventing fake container parity.

### Deliverables

- `src/Infernix/Engines/AppleSilicon.hs` provides typed engine-setup steps for the host inference
  executor lane
- the host daemon currently ensures the shared Poetry project, repo-local engine roots, and
  per-engine setup entrypoints on Apple Silicon
- the operator remains responsible for the host prerequisites documented in governed docs,
  including ghcup and the supported toolchain installs
- Apple adapter dependencies materialize on demand in `python/.venv/`
- the daemon uses the same per-engine Poetry entrypoints as the Linux runtime lanes

### Validation

- on a clean Apple Silicon host with ghcup installed,
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
  succeeds without extra supported wrapper scripts
- after `./.build/infernix internal materialize-substrate apple-silicon`, the
  `./.build/infernix cluster up` command brings up the cluster and runs the current Apple setup
  entrypoints before host-side inference execution
- `infernix test integration` exercises the Apple column of the README matrix against the
  host inference executor lane when the active substrate is `apple-silicon`

### Remaining Work

None.

---

## Sprint 4.11: Per-Substrate Engine Selection in the Catalog [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `src/Infernix/Types.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Web/Contracts.hs`, `src/Infernix/Runtime/Worker.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/development/testing_strategy.md`

### Objective

Make the per-substrate engine column in the README matrix the canonical input for catalog
generation.

### Deliverables

- each matrix row records explicit engine selection per substrate
- the active built substrate picks the appropriate engine binding when generating
  `infernix-substrate.dhall`
- the generated demo config and demo-visible surfaces expose each row through the selected engine
  for that substrate while still serializing the active substrate under `runtimeMode` fields
- daemon startup fails when the active substrate references an engine binding whose adapter
  metadata is missing

### Validation

- rebuilding for a different substrate changes per-row selected engine bindings deterministically
- the generated demo-config and routed API surfaces publish the selected engine bindings for the
  active substrate
- demo-config validation fails when the active substrate references a selected engine with no
  matching binding metadata

### Remaining Work

None.

## Sprint 4.12: Substrate-Owned Daemon Role, Startup Selection, and Fallback Removal [Done]

**Status**: Done
**Implementation**: `src/Infernix/Config.hs`, `src/Infernix/DemoConfig.hs`, `src/Infernix/Service.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Cluster.hs`, `src/Infernix/Models.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `docker/linux-substrate.Dockerfile`, `web/test/run_playwright_matrix.mjs`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, `documents/engineering/portability.md`, `documents/engineering/testing.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Make daemon behavior derive entirely from the staged substrate file at startup and remove the
remaining file-absent substrate-selection fallback from the runtime contract. Phase 6 Sprint 6.25
extends this startup contract with explicit cluster and host daemon roles.

### Deliverables

- `infernix service` derives its active substrate and daemon role from the staged substrate file
  when present and no longer accepts `--runtime-mode` or `INFERNIX_RUNTIME_MODE`
- `infernix-demo` and any runtime-owned manual inference entrypoint choose the engine binding for a
  given README row only from the colocated or ConfigMap-backed substrate `.dhall`
- Apple host workflows stage that substrate file through
  `./.build/infernix internal materialize-substrate apple-silicon [--demo-ui true|false]`, Linux
  outer-container workflows stage it through
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui <true|false>`
  onto the host-anchored `./.build/outer-container/build/` bind mount, and supported runtime
  entrypoints fail fast if it is absent
- the direct `infernix service` entrypoint remains host-side for Apple inference execution, while
  the routed clustered demo app reads the same staged `.dhall` and enters the cluster daemon path
  before Apple batches move to the host daemon
- cluster-resident Apple workloads consume the mounted staged substrate file for cluster daemon
  behavior, catalog behavior, and route behavior; they do not stand in for the canonical Apple
  inference executor
- Linux `linux-cpu` and `linux-gpu` daemons run as cluster-resident workloads on their deployed
  substrate images and perform request consumption, inference, and result publication there
- each daemon reads the staged substrate `.dhall` at startup to select the active substrate, daemon
  role, engine catalog, and any Pulsar topic wiring; automatic file-watching or reload is not part
  of the supported contract
- the supported steady-state runtime removes simulated cluster, route, transport, and generic
  inference-success fallback code paths from the final contract rather than merely refusing to
  count them as evidence
- startup and publication reporting name substrate, daemon role, cluster daemon location, inference
  executor location, and any routed Apple batch bridge mode unambiguously

### Validation

- Apple host-side `infernix service` reports `apple-silicon` from the generated substrate file and
  the host daemon role, and routed manual inference continues to succeed through the clustered
  `infernix-demo` surface by entering the cluster daemon path before reaching host inference
- Linux substrate daemons read the mounted ConfigMap-backed substrate file at
  `/opt/build/infernix-substrate.dhall` and do not rely on runtime-mode flags
- manual inference through `infernix-demo` and service-loop execution both use the engine binding
  selected in `.dhall` for the active README row
- runtime validation fails if the service or demo app falls back to simulated route, transport, or
  substrate behavior or to a generic engine-success path that ignores the selected adapter metadata

### Remaining Work

None.

---

## Sprint 4.13: Cluster Manifest Materialization [Active — code-side done, cluster validation pending]

**Status**: Active
**Blocked by**: Phase 1 Sprint 1.11 (Host Manifest Materialization)
**Implementation**: `dhall/InfernixCluster.dhall` (new), `src/Infernix/ClusterConfig.hs` (new), `src/Infernix/Service.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `chart/templates/deployment-coordinator.yaml`, `chart/templates/deployment-engine.yaml`, `chart/templates/configmap-cluster-config.yaml` (new)
**Docs to update**: `documents/engineering/cluster_config_manifest.md`, `documents/tools/pulsar.md`, `documents/architecture/daemon_topology.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Materialize the `InfernixCluster.dhall` typed cluster-wiring record + matching Haskell decoder.
Delete every `env:` block from `chart/templates/deployment-{coordinator,engine}.yaml`; the pods
mount the cluster `ConfigMap` at `/opt/infernix/cluster.dhall` and the Haskell daemon decodes it
at startup. Retire every Pulsar / catalog / daemon-location / engine-command env-var fallback in
favor of typed `ClusterConfig` fields.

### Deliverables

- `dhall/InfernixCluster.dhall` schema with the `PulsarConfig`, `MinioConfig` (non-credential
  fields), `DemoBackendConfig`, `EngineConfig`, `CoordinatorConfig` records named in
  `documents/engineering/cluster_config_manifest.md`.
- `ClusterConfig` typed record + decoder; threaded through every coordinator + engine entry
  point.
- `INFERNIX_DEMO_CONFIG_PATH`, `INFERNIX_DAEMON_ROLE`, `INFERNIX_DAEMON_LOCATION`,
  `INFERNIX_CATALOG_SOURCE`, `INFERNIX_CONTROL_PLANE_CONTEXT`, `INFERNIX_PULSAR_*`
  (admin/ws/http/service/tenant/namespace), `INFERNIX_ENGINE_COMMAND_<NAME>` env reads deleted
  from `src/Infernix/Service.hs`, `src/Infernix/Runtime/Pulsar.hs`,
  `src/Infernix/Runtime/Worker.hs`.
- `chart/templates/deployment-coordinator.yaml` and
  `chart/templates/deployment-engine.yaml` lose every `env:` entry except any third-party
  upstream exception explicitly enumerated; they gain `cluster-config` volume mount at
  `/opt/infernix/cluster.dhall`.
- `chart/templates/configmap-cluster-config.yaml` renders the staged cluster Dhall into a
  ConfigMap.

### Validation

- `cabal build all` clean, `infernix test lint` clean, `infernix test unit` clean.
- `grep -rn '^\s*-\s*name:\s*INFERNIX_' chart/templates/deployment-{coordinator,engine}.yaml`
  returns zero matches.
- `infernix test integration` on `linux-gpu` round-trips through coordinator + engine pods that
  read from the mounted Dhall ConfigMap (proven by removing the corresponding `env:` entries
  before the test runs).

### Remaining Work

Foundational pieces landed (May 25, 2026):

- `dhall/InfernixCluster.dhall` — typed schema for the `pulsar`,
  `minio`, `keycloak`, `demoBackend`, `engine`, `coordinator` records
  documented in
  [../documents/engineering/cluster_config_manifest.md](../documents/engineering/cluster_config_manifest.md).
- `src/Infernix/ClusterConfig.hs` — typed `ClusterConfig` Haskell
  record + Dhall decoder, exposed via the `infernix` library and
  declared in `infernix.cabal`. The decoder uses the same
  field-name-modifier pattern as `HostConfig` so the Haskell record
  selectors stay `cluster…`-prefixed while the Dhall schema fields
  remain bare camelCase.
- `chart/templates/configmap-cluster-config.yaml` — renders the
  cluster Dhall from chart values into
  `ConfigMap/infernix-cluster-config`, keyed by `cluster.dhall`. The
  template inlines the schema header so the rendered file is a valid
  standalone Dhall document the coordinator + engine + demo pods can
  decode in-process at startup.
- `chart/values.yaml` — extended with a top-level `clusterConfig:`
  block providing the typed defaults that the new ConfigMap template
  reads (Pulsar `systemNamespace`, MinIO `region` /
  `presignExpirySeconds` / `modelsBucket` / `demoArtifactsBucket`,
  Keycloak base URL + realm + client id + JWKS URL, demo-backend
  `bindHost` + `port` + `bridgeMode`, engine `modelCacheRoot` +
  `modelCacheQuotaBytes`, coordinator `catalogSource` +
  `daemonLocation`).
- `infernix.cabal` — `extra-source-files` extended with
  `dhall/InfernixHost.dhall` and `dhall/InfernixCluster.dhall` so the
  schemas ship inside the source distribution.

Verified end-to-end on the host: `cabal build all`, `cabal test
infernix-unit` (70/70 tests), and `./.build/infernix lint
{files,chart,docs}` all exit zero.

Code-side closure landed (May 25, 2026):

- **Chart env stripping.** `chart/templates/deployment-coordinator.yaml`
  and `chart/templates/deployment-engine.yaml` drop the
  `INFERNIX_CONTROL_PLANE_CONTEXT`, `INFERNIX_DAEMON_LOCATION`,
  `INFERNIX_DAEMON_ROLE`, `INFERNIX_CATALOG_SOURCE`,
  `INFERNIX_DEMO_CONFIG_PATH`, `INFERNIX_PUBLICATION_STATE_PATH`,
  `INFERNIX_MINIO_ENDPOINT`, `INFERNIX_MINIO_REGION`, and the entire
  `INFERNIX_PULSAR_*` family from their `env:` blocks. Each Deployment
  gains a `cluster-config` volume mount at `/opt/infernix/cluster.dhall`
  (subPath `cluster.dhall`) sourced from `ConfigMap/{{ .Values.clusterConfig.name }}`.
  The remaining `env:` entries are intentional residue scheduled for
  retirement in later sprints: `INFERNIX_DATA_ROOT` retires with the
  demo-deployment rewiring (Phase 7 Sprint 7.17), `INFERNIX_MODEL_CACHE_ROOT`
  retires with the Python adapter sweep (Phase 5 Sprint 5.9), and
  `INFERNIX_MINIO_ACCESS_KEY` / `INFERNIX_MINIO_SECRET_KEY` retire with
  the `InfernixSecrets.dhall` materialization (Phase 7 Sprint 7.17).
- **DAEMON_ROLE retirement: typed CLI arg.** The chosen design is the
  `--role coordinator|engine` arg on `infernix service`, not per-role
  substrate ConfigMaps. `Infernix.CommandRegistry.ServiceCommand` now
  carries a `Maybe DaemonRole`, and the parser accepts
  `infernix service [--role coordinator|engine]`. Both Deployment
  templates pass the matching role through their `args:` block. Apple
  host-native and unit-test flows omit the flag and fall back to the
  substrate dhall's `daemonRole` field (the supported default for any
  flow that doesn't go through chart-driven splits).
- **Pulsar env retirement.** `src/Infernix/Runtime/Pulsar.hs`
  `runProductionDaemon` is now
  `Paths -> RuntimeMode -> Maybe ClusterConfig -> DaemonRole -> IO ()`;
  it consumes the typed `ClusterConfig` for control-plane context,
  catalog source, daemon location, demo-config path, and the Pulsar
  websocket / admin endpoints. The legacy `lookupEnv` reads for
  `INFERNIX_CONTROL_PLANE_CONTEXT`, `INFERNIX_DAEMON_ROLE`,
  `INFERNIX_DAEMON_LOCATION`, `INFERNIX_CATALOG_SOURCE`,
  `INFERNIX_DEMO_CONFIG_PATH`, `INFERNIX_PULSAR_WS_BASE_URL`, and
  `INFERNIX_PULSAR_ADMIN_URL` are deleted. The retired
  `Infernix.Error.InvalidControlPlaneOverride` and the
  `parseControlPlaneOverride` / `resolveControlPlaneOverride` /
  `parseDaemonRoleText` helpers are removed; the new
  `resolveClusterControlPlaneContext` helper consumes the cluster
  manifest directly.
- **Service-side wiring.** `src/Infernix/Service.hs.runService` is now
  `Maybe RuntimeMode -> Maybe DaemonRole -> IO ()`; it loads the
  cluster manifest via the new `tryLoadClusterConfig` helper (silent
  absence outside cluster pods) and threads both typed values into
  `runProductionDaemon`. `Infernix.CLI.dispatch` and
  `Infernix.HostPrereqs` pattern-match the new constructor shape.
- **Test-fixture rewiring.** `test/unit/Spec.hs` adds the
  `unitTestClusterConfigFixture` helper that constructs a synthetic
  `ClusterConfig` with loopback Pulsar + MinIO endpoints; the previous
  `withOptionalEnv "INFERNIX_PULSAR_*" / "INFERNIX_DEMO_CONFIG_PATH"`
  injection is deleted in favour of passing the typed fixture +
  `Coordinator` role to `runProductionDaemon`. The override-test path
  for `INFERNIX_ENGINE_COMMAND_TRANSFORMERS_PYTHON` remains using
  `withOptionalEnv` since the engine-command override retirement is
  deferred (see below); this is the last remaining env-var injection
  in `Spec.hs`.
- **Chart lint update.** `src/Infernix/Lint/Chart.hs` `requiredPhrases`
  table swaps the retired `INFERNIX_PULSAR_*` / `INFERNIX_DEMO_CONFIG_PATH`
  / `INFERNIX_MINIO_ENDPOINT` / `INFERNIX_PUBLICATION_STATE_PATH`
  expectations on `deployment-{coordinator,engine}.yaml` for the new
  `cluster-config` volume mount, `/opt/infernix/cluster.dhall` mount
  path, and `--role coordinator|engine` arg patterns. A new entry
  asserts that `chart/templates/configmap-cluster-config.yaml` renders
  the typed Dhall record with all six top-level fields
  (`pulsar`/`minio`/`keycloak`/`demoBackend`/`engine`/`coordinator`).
- **CLI reference doc updated.** `documents/reference/cli_reference.md`
  records the new `infernix service [--role coordinator|engine]`
  surface; the `infernix lint docs` generated-section check is green.

Verified end-to-end on the host: `cabal build all`, `cabal test
infernix-unit` (70/70 tests still passing with the typed fixture +
the new `serviceCatalogSource: unit-test-fixture` output line),
`cabal test infernix-haskell-style`, and
`./.build/infernix lint {chart,files,docs,proto}` all exit zero.

Pending closure (deferred and named so the sprint status stays
honest):

- **`INFERNIX_ENGINE_COMMAND_<NAME>` env retirement in
  `src/Infernix/Runtime/Worker.hs` — landed May 25, 2026.**
  `Worker.runInferenceWorker` now takes an explicit
  `EngineCommandOverrideMap = [(Text, Text)]` parameter keyed by the
  engine binding's adapter id. `Runtime.executeInference` threads the
  map through; `Runtime/Pulsar.runProductionDaemon` extracts it once
  from `ClusterConfig.engine.commandOverrides` (empty list when no
  manifest is mounted) and passes it through every consumer loop +
  `publishedResultFromRequest` call. The exported
  `engineCommandOverrideEnvironmentName` helper is gone; the matching
  unit-test override switched from `withOptionalEnv overrideEnvName` to
  the typed resolver and `withOptionalEnv` itself was removed from
  `test/unit/Spec.hs`. The Phase 6 Sprint 6.28 lint gate no longer
  exempts `src/Infernix/Runtime/Worker.hs`.
- **`INFERNIX_MINIO_ENDPOINT` / `INFERNIX_MINIO_REGION` reads in
  `src/Infernix/Runtime/Pulsar.hs.loadBootstrapPresignedConfig`.**
  Endpoint + region are present in `ClusterConfig.minio`; the
  remaining `INFERNIX_MINIO_ACCESS_KEY` / `INFERNIX_MINIO_SECRET_KEY`
  reads need the file-backed `SecretsConfig` landing in Phase 7
  Sprint 7.17 before the whole function can switch to typed config.
  These reads are scheduled to retire together rather than half-way.
- **Unit fixture for `ClusterConfig` decoder roundtrip.** The
  `unitTestClusterConfigFixture` helper covers construction; a
  matching renderer + roundtrip-through-`decodeClusterConfigFile`
  assertion (mirroring `assertHostConfig`) is the standalone test
  that locks the Dhall encoding. Worth adding alongside the Sprint
  6.28 lint-gate landing.
- **`infernix test integration` round-trip on `linux-gpu`.** The
  validation requires a fresh launcher image build + `cluster up` +
  the integration suite. The first-cluster bring-up on this host
  costs ~30+ minutes (per the documented long-running Harbor-first
  bootstrap), so this validation is deferred to a focused session
  rather than mixed into the code-side closure.

---

## Remaining Work

Sprint 4.13 code-side closed (Dhall schema + Haskell decoder + chart
ConfigMap template + values block + chart env stripping + typed
`--role` CLI arg + Pulsar env retirement + ClusterConfig threading +
chart lint expectations + CLI reference doc + unit-test fixture).
Pending closure (engine-command override retirement, MinIO endpoint
move, dedicated `ClusterConfig` decoder roundtrip test, and the real
`linux-gpu` cluster integration validation) is named in the sprint
section above. Sprints 4.1–4.12 closed.

---

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/runtime_modes.md` - honest runtime model, host-native Apple control-plane, cluster-daemon role, Apple host inference executor behavior, and Linux substrate lanes
- `documents/architecture/model_catalog.md` - per-substrate engine binding and generated catalog contract
- `documents/engineering/docker_policy.md` - shared Linux substrate image doctrine and snapshot launcher expectations
- `documents/engineering/build_artifacts.md` - build roots, generated proto handling, and image-owned toolchain contract
- `documents/engineering/model_lifecycle.md` - durable artifacts, bundle metadata, and cache semantics
- `documents/engineering/object_storage.md` - repo-local object-store rules plus reserved MinIO path and service-placement access notes
- `documents/engineering/storage_and_state.md` - durable-versus-derived state inventory
- `documents/engineering/implementation_boundaries.md` - Haskell versus Python versus chart ownership
- `documents/engineering/portability.md` - portable platform rules versus Apple or Linux substrate detail
- `documents/development/python_policy.md` - shared Python project, `poetry run` contract, and `check-code` gate
- `documents/development/testing_strategy.md` - per-substrate integration coverage and engine-binding parity
- `documents/operations/apple_silicon_runbook.md` - ghcup prerequisites and daemon-driven Apple engine setup

**Product or reference docs to create/update:**
- `documents/reference/api_surface.md` - browser and operator API contract
- `documents/reference/web_portal_surface.md` - manual inference user surface

**Cross-references to add:**
- keep [00-overview.md](00-overview.md), [system-components.md](system-components.md), and
  [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) aligned when the API,
  model catalog, or generated demo-config contract changes
