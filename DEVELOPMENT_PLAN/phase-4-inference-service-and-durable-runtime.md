# Phase 4: Inference Service and Durable Runtime

**Status**: Active
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the Haskell service runtime (Pulsar consumer plus engine-worker supervisor
> plus durable cache), the Python engine-adapter contract under `python/adapters/`, the
> Pulsar-driven production inference surface, the demo-only HTTP API surface served by
> `infernix-demo`, the model and artifact contracts, the comprehensive matrix registry, and the
> stable typed runtime contract that both production Pulsar consumers and the demo UI consume.

## Phase Status

Sprints 4.1 (typed configuration and protobuf contracts), 4.5 (durable cache), and 4.6
(comprehensive matrix registry) are `Done`. Sprints 4.2 (inference pipeline) and 4.3
(host-native and cluster parity) remain `Active`: the repo now has
`src/Infernix/Runtime/{Pulsar,Worker,Cache}.hs`, but `src/Infernix/Runtime/Pulsar.hs` is still a
no-subscription placeholder while the Python-native bindings now resolve through typed
protobuf-over-stdio adapters under `python/adapters/<engine>/`; the remaining adapter gap is real
engine implementation rather than process-boundary ownership. The legacy Python runtime
helpers have now been removed from `tools/`. Sprint 4.4 (Demo
Inference API Surface) is now `Done`: the manual inference HTTP surface lives only in
`infernix-demo`, is gated by `.Values.demo.enabled` plus the active `.dhall` `demo_ui` flag, and
production `infernix service` no longer binds HTTP. Sprint 4.7 declares the Python
engine-adapter contract and quality gate (Poetry, mypy strict, black, ruff strict, integrated into
every adapter container build). New Sprint 4.8 declares the Pulsar-driven production inference
surface (`.dhall` schema additions and the full Pulsar consumer runtime).

## Current Repo Assessment

The repository already has typed request or response shapes, typed runtime result metadata, a
README-matrix-backed generated catalog, protobuf-backed manifest and result persistence helpers,
explicit cache status or eviction or rebuild flows, and a manual inference API path served by the
Haskell demo surface. The supported host-native and Kind-backed paths stage the real
`ConfigMap/infernix-demo-config`, keep routed publication metadata under repo-local state, and use
the `Infernix.Runtime` facade together with `src/Infernix/Runtime/Cache.hs`,
`src/Infernix/Runtime/Worker.hs`, and `src/Infernix/Runtime/Pulsar.hs` to materialize durable
bundle metadata, cache entries, large-output object references, and the current no-HTTP
production-daemon placeholder. Python-native bindings now cross a real process boundary through
engine-specific adapter directories plus adapter-specific command overrides, and the worker
boundary now uses typed protobuf-over-stdio. The major remaining gaps are the real Pulsar
consumer loop, schema registration or publication, and replacing the current stub adapters with
real engine loaders plus cluster-backed adapter execution.

## Matrix Ownership Contract

This phase owns the conversion from README-scale planning matrix to runtime-consumable catalog.

- the service owns the typed registry that represents matrix rows
- the active runtime mode selects the engine column for each supported row
- `cluster up` emits that active-mode selection as `infernix-demo-<mode>.dhall` staging content and
  publishes it into `ConfigMap/infernix-demo-config`
- in containerized execution contexts, the service, web UI, integration suite, and E2E suite
  consume that exact generated catalog from the watched `/opt/build/` mount next to the binary

## Sprint 4.1: Typed Configuration, Model Catalog, and Runtime Contracts [Done]

**Status**: Done
**Implementation**: `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Storage.hs`, `proto/infernix/api/inference_service.proto`, `proto/infernix/manifest/runtime_manifest.proto`, `proto/infernix/runtime/inference.proto`, `tools/generated_proto/`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`

### Objective

Make the service runtime strongly typed before the transport and UI surfaces accumulate logic.

### Deliverables

- Haskell-owned ADTs for cluster state, generated demo config, model catalog entries, inference
  request shapes, and inference result shapes
- one canonical model catalog surface that lists every registered model the UI may target
- explicit distinction between authoritative durable metadata and derived local cache state
- the supported web build derives frontend contract modules from those Haskell-owned types rather
  than maintaining duplicate DTO definitions
- repo-owned `.proto` schemas under `proto/` define the canonical durable runtime-manifest,
  inference-payload, and service-RPC message names
- generated `proto-lens` modules are the supported Haskell boundary for those protobuf contracts

### Validation

- `infernix test unit` covers runtime-mode selection, representative catalog membership or
  omission, generated demo-config rendering, invalid generated-catalog startup handling, and
  protobuf runtime-manifest round-trip coverage
- `infernix test lint` passes `infernix lint proto` against the repo-owned `.proto` contract set
- the service runtime rejects unsupported runtime modes and invalid request payloads
  with typed errors
- the supported web build can derive frontend contract modules from the Haskell SSOT without hand patches

### Remaining Work

None.

---

## Sprint 4.2: Inference Request Pipeline Over Pulsar and MinIO [Active]

**Status**: Active
**Implementation**: `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Cache.hs`, `src/Infernix/Runtime/Worker.hs`, `src/Infernix/Storage.hs`, `src/Infernix/Demo/Api.hs`, `infernix.cabal`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`

### Objective

Use MinIO and Pulsar for the routed service path without letting derived local cache state become
authoritative.

### Deliverables

- the routed service path consumes internal API submissions and stores durable results or large outputs through MinIO
- the same routed service path consumes inference requests and publishes results or coordination messages through Pulsar-backed topics
- MinIO holds authoritative model artifacts, protobuf runtime manifests, and large outputs for the routed service path
- the service writes large outputs to durable object storage and returns typed references when
  payloads exceed inline limits
- durable runtime manifests serialize from repo-owned `.proto` schemas through generated
  `proto-lens` bindings on the Haskell side; per-engine Python adapters under
  `python/adapters/<engine>/` consume the matching auto-generated Python protobuf modules in
  `tools/generated_proto/`
- Pulsar topics carrying requests, results, and coordination events use Pulsar's built-in protobuf schema support rather than untyped payloads
- durable runtime artifact bundles record engine-adapter id or type or locator or availability
  together with authoritative source-artifact URI or kind metadata and the selected engine-ready
  artifact inventory used by the current worker path
- process-isolated runtime workers honor adapter-specific `INFERNIX_ENGINE_COMMAND_*` command
  prefixes when configured and otherwise use the default engine-aware runner to validate the
  selected adapter on the active host
- local materialization is idempotent and cache-oriented, not authoritative

### Validation

- `infernix test integration` proves cluster reconcile publishes the generated catalog, that
  per-entry inference execution succeeds on the final Kind and Helm substrate, that Pulsar topic
  schemas are published as protobuf, and that MinIO stores runtime results or manifests or large-output payloads
- `infernix test unit` proves large outputs return typed object references, that protobuf
  manifests or results round-trip through the supported storage helpers, and that local-file plus
  direct-upstream HTTP source artifacts materialize through the durable object-store contract
- `infernix test unit` also proves the durable bundle or cache materialization contract exercised
  by the current Haskell runtime simulation
- `infernix test integration` proves the routed cache surface reports engine-adapter availability
  together with authoritative source-artifact URI or kind metadata and selected-artifact inventory
- the routed service path persists runtime results in MinIO and exposes durable cache manifests through the routed cache lifecycle API

### Remaining Work

- `src/Infernix/Runtime/Pulsar.hs` is still a validated placeholder; it does not subscribe to
  request topics, register Pulsar schemas, or publish results yet
- the routed runtime now delegates through `src/Infernix/Runtime/Worker.hs` and
  `src/Infernix/Runtime/Cache.hs`, and Python-native bindings now speak typed
  protobuf-over-stdio, but the current adapters are still stub responders rather than real engine
  implementations
- Sprint 4.7 still owns replacing those stub adapters with real per-engine inference execution and
  cluster-backed adapter image coverage

---

## Sprint 4.3: Host-Native Apple Runtime and Cluster Runtime Parity [Active]

**Status**: Active
**Blocked by**: Sprint 4.2
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Runtime/Worker.hs`, `infernix.cabal`, `test/integration/Spec.hs`, `test/unit/Spec.hs`
**Docs to update**: `documents/architecture/runtime_modes.md`, `documents/engineering/object_storage.md`, `documents/operations/apple_silicon_runbook.md`

### Objective

Keep one service binary and one runtime contract while allowing Apple host-native execution and
cluster-resident execution to coexist.

### Deliverables

- `infernix service` supports host-native Apple execution for direct local model runtimes
- the same executable can run in a cluster container on the Linux-supported path
- service placement selects the MinIO and Pulsar access path without changing the API contract:
  cluster-resident service placement uses cluster-local networking, while Apple host-native service
  placement uses the edge-routed `/minio/s3`, `/pulsar/admin`, and `/pulsar/ws` bridges
- in containerized execution contexts, the service consumes the active mode's ConfigMap-backed
  mounted `.dhall` from `/opt/build/`, next to the binary it watches for changes
- startup clearly reports whether the daemon is running host-side or cluster-side
- host-native Apple and cluster-resident execution both consume the same durable runtime artifact
  bundles plus source-artifact manifests, expose the same engine-adapter metadata, and honor the
  same adapter-specific command-prefix override contract
- switching runtime modes changes generated catalog content and engine bindings, not the MinIO or
  Pulsar access path used by a given service placement

### Validation

- Apple host-native `infernix service` can reach MinIO and Pulsar through the shared edge port
- cluster-resident `infernix service` can reach MinIO and Pulsar through cluster-local networking
- cluster-resident `infernix service` reads the active-mode catalog from the watched `/opt/build/`
  mount rather than an image-baked static file
- the web UI continues to work against `/api` in both modes
- `infernix test integration` proves the demo API surface (when enabled) can move to the
  `infernix-demo serve` Apple host invocation without changing the browser-visible edge entrypoint,
  while `infernix test unit` proves `src/Infernix/Runtime/Worker.hs` honors adapter-specific
  command overrides on the same host-native path

### Remaining Work

- the routed demo parity path now targets the Haskell host bridge, but the production daemon still
  lacks the real Pulsar consumer loop, topic schema registration, and per-engine adapter coverage
  planned in Sprint 4.2

---

## Sprint 4.4: Demo Inference API Surface [Done]

**Status**: Done
**Implementation**: `infernix.cabal`, `app/Demo.hs`, `src/Infernix/DemoCLI.hs`, `src/Infernix/Demo/Api.hs`, `src/Infernix/Service.hs`, `src/Infernix/Edge.hs`, `src/Infernix/Models.hs`, `chart/templates/deployment-demo.yaml`, `chart/templates/service-demo.yaml`, `test/integration/Spec.hs`, `web/playwright/inference.spec.js`
**Docs to update**: `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`

### Objective

Expose a stable demo HTTP API surface for listing models and submitting manual inference requests
from the browser. **This is the demo surface only.** Production deployments accept inference work
via Pulsar subscription only and never bind this HTTP surface.

### Deliverables

- API endpoints or typed handlers for listing models, inspecting a model's supported request shape,
  submitting an inference request, and retrieving results, all exposed by the `infernix-demo`
  Haskell binary via servant
- request validation uses the same Haskell-owned model metadata used by the production Pulsar path
- the manual inference path can target any model present in the catalog, not a hard-coded allowlist
- the demo surface dispatches into the same Haskell runtime contract that production
  `infernix service` consumes from Pulsar; there is no parallel runtime backend
- the `infernix-demo` workload is gated by `.Values.demo.enabled` (driven from the active `.dhall`
  `demo_ui` flag); production deployments leave the flag off and the API surface is absent from
  the cluster

### Validation

- `infernix test e2e` proves routed model listing and manual inference submission through the same
  `/api` surface the demo workbench uses, served by the `infernix-demo` workload
- direct API calls to `/api/models/<id>` and `/api/inference/<id>` return typed model metadata and
  stored results on the supported demo path
- invalid requests are rejected with typed user-facing errors rather than transport-level crashes
- at least one end-to-end path exercises browser submission through the same demo API used by
  the browser and Playwright coverage
- when `demo_ui` is off, the cluster has no `infernix-demo` workload and `/api` is absent from the
  edge route inventory

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
- the current service path materializes cache on demand from inference execution and keeps it
  derived rather than authoritative
- the current service runtime writes durable cache manifests under
  `./.data/object-store/manifests/` and treats those manifests as the rebuild source for derived
  cache directories
- `infernix cache status`, `infernix cache evict`, and `infernix cache rebuild` provide explicit
  operator cache lifecycle flows without mutating unrelated runtime state
- the routed service API exposes `GET /api/cache`, `POST /api/cache/evict`, and
  `POST /api/cache/rebuild` so service-path cache semantics are testable through the same routed
  surface used by the browser and integration layers

### Validation

- `infernix test unit` proves inference execution materializes runtime cache under the runtime-mode
  and model-keyed cache root, writes durable cache manifests, and can evict or rebuild cache state
  from those manifests
- `infernix test integration` proves the routed service cache API can materialize, evict, and
  rebuild a representative cache entry without changing the generated catalog contract
- `infernix cluster status` distinguishes runtime result counts, object-store object counts,
  durable-manifest counts, and model-cache entry counts while reporting the relevant roots
- `infernix cache status` reports the active runtime mode, cache root, durable manifest root, and
  manifest-backed cache entry inventory

### Remaining Work

None.

---

## Sprint 4.6: Comprehensive Matrix Registry, Generated Demo `.dhall`, and ConfigMap Publication [Done]

**Status**: Done
**Implementation**: `src/Infernix/Models.hs`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`

### Objective

Turn the README matrix into the typed source of truth that drives runtime binding, generated demo
catalogs, and later test enumeration.

### Deliverables

- the service owns a typed registry for every row in the README model or format or engine matrix
- each matrix row records workload identity, artifact or format family, reference model metadata,
  and per-mode engine bindings
- the active runtime mode selects the correct engine binding from the corresponding README matrix column
- CUDA-bound rows record the GPU runtime metadata needed for `linux-cuda` scheduling and engine
  selection on the GPU-enabled Kind substrate
- `cluster up` renders the active runtime mode's supported rows as `infernix-demo-<mode>.dhall`
  staging content and creates or updates `ConfigMap/infernix-demo-config`
- each generated `.dhall` entry records the matrix-row id, selected engine id, request or result
  contract identifiers, and runtime-lane metadata needed by the service, webapp, integration, and E2E layers
- in containerized execution contexts, cluster-resident consumers mount that ConfigMap read-only at
  `/opt/build/`, where the daemon watches the active-mode `.dhall` next to its binary
- rows whose active-mode column is `Not recommended` are absent from that mode's generated catalog
- across `apple-silicon`, `linux-cpu`, and `linux-cuda`, the generated catalogs cover every README matrix row

### Validation

- unit tests prove generated catalog counts, representative row inclusion or omission, and
  runtime-mode rendering remain stable
- frontend contract checks prove the generated active-mode contract carries selected engines,
  runtime lanes, and mode-specific catalog counts
- integration fixtures prove the published `ConfigMap/infernix-demo-config` content matches the
  generated active-mode catalog byte-for-byte before the service consumes it and that serialized
  model ids and selected engines remain aligned with the typed registry
- service startup fails when the generated catalog contains missing required metadata or a
  mismatched runtime mode

### Remaining Work

None.

---

## Sprint 4.7: Python Engine Adapter Contract and Quality Gate [Active]

**Status**: Active
**Implementation**: `python/pyproject.toml`, `python/poetry.lock`, `python/adapters/common.py`, `python/adapters/fixture/`, `python/adapters/{vllm-python,transformers-python,diffusers-python,pytorch-python,tensorflow-python,jax-python}/`, `tools/python_quality.sh`, `src/Infernix/Runtime/Worker.hs`, `proto/infernix/runtime/inference.proto`, `tools/generated_proto/`, `docker/{vllm-python,transformers-python,diffusers-python,pytorch-python,tensorflow-python,jax-python}.Dockerfile`, `test/unit/Spec.hs`
**Docs to update**: `documents/development/python_policy.md` (new), `documents/engineering/model_lifecycle.md`, `documents/development/testing_strategy.md`

### Objective

Establish the Python engine-adapter contract so that Python is restricted to
`python/adapters/<engine>/` and only when the bound inference engine has no non-Python binding.
Make every adapter container build run a strict mypy plus black plus ruff quality gate that fails
the build on any check failure. Make the Haskell worker (`src/Infernix/Runtime/Worker.hs`) the
single dispatch point that forks a Python adapter over typed protobuf-over-stdio.

### Deliverables

- one repo-root `python/pyproject.toml` (Poetry-managed) declaring all Python dependencies needed
  by adapters; outside the cluster, `poetry install` materializes a repo-local adapter virtual
  environment; inside the engine container, Poetry installs system-wide from the same
  `pyproject.toml`, with no in-container `.venv`
- one `python/adapters/<engine>/` directory per Python-native inference engine (PyTorch, JAX,
  vLLM, transformers, Diffusers, etc.); each adapter is a thin module that loads the engine, takes
  a typed protobuf request from stdin, runs the engine, and emits a typed protobuf response to
  stdout
- one `tools/python_quality.sh` shell script that runs `poetry run mypy --strict python/`,
  `poetry run black --check python/`, and `poetry run ruff check python/` in sequence and exits
  non-zero on any failure
- every adapter `Dockerfile` (under `docker/<adapter>.Dockerfile` or equivalent) runs
  `tools/python_quality.sh` as a build step; the container image build fails on any check failure
- `infernix test lint` runs the same quality gate against that Poetry-managed adapter environment on the host
- `src/Infernix/Runtime/Worker.hs` forks the appropriate Python adapter for each request whose
  engine binding names a Python-native engine; the adapter speaks typed protobuf-over-stdio (or
  unix socket) using the same `.proto` schemas used by the Haskell side via `proto-lens`
- `tools/runtime_worker.py` and `tools/final_engine_runner.py` are removed; the Python execution
  path is now confined to `python/adapters/<engine>/`

### Validation

- `poetry install --directory python` succeeds on the supported Apple host and on the supported
  Linux outer-container path
- `tools/python_quality.sh` passes against the supported `python/` tree
- intentionally introducing a type error, formatting drift, or ruff violation under
  `python/adapters/` causes the adapter `docker build` to fail; `infernix test lint` also fails
  in that case
- `infernix test unit` exercises the Haskell worker plus a Python adapter handshake end-to-end and
  asserts the typed protobuf-over-stdio contract
- `infernix test integration` on a runtime mode whose active catalog selects a Python-native
  binding exercises one real adapter path end-to-end on the cluster substrate and fails if the
  adapter image's quality gate did not run
- `find python -name '*.py' -type f` returns only files under `python/adapters/`; `tools/` carries
  no engine-specific Python after the migration

### Remaining Work

- the worker now dispatches every Python-native binding through a real adapter directory and a
  typed protobuf-over-stdio contract, and every adapter Dockerfile now runs
  `tools/python_quality.sh` as a build step
- the remaining gap is engine depth rather than ownership: the current adapters are still stub
  responders that normalize the input payload instead of loading real vLLM or transformers or
  Diffusers or PyTorch or TensorFlow or JAX runtimes
- the integration suite still does not build or schedule dedicated adapter images or prove one real
  Python-native engine on the cluster substrate

---

## Sprint 4.8: Pulsar-Driven Production Inference Surface [Active]

**Status**: Active
**Blocked by**: Sprint 4.2, Sprint 4.7
**Implementation**: `src/Infernix/Service.hs`, `src/Infernix/Config.hs`, `src/Infernix/CLI.hs`, `src/Infernix/Types.hs`, `src/Infernix/Models.hs`, `src/Infernix/DemoConfig.hs`, `chart/templates/deployment-service.yaml`, `chart/values.yaml`, `src/Infernix/Runtime.hs`, `src/Infernix/Runtime/Pulsar.hs`, `proto/infernix/runtime/inference.proto`, `tools/generated_proto/`, `test/unit/Spec.hs`, `test/integration/Spec.hs`, `web/test/Main.purs`
**Docs to update**: `documents/tools/pulsar.md`, `documents/architecture/runtime_modes.md`, `documents/reference/cli_reference.md`

### Objective

Make the Pulsar-driven production inference surface the canonical way to request inference in any
non-demo deployment. `infernix service` (production) subscribes to request topics named in the
active `.dhall`, dispatches each request through the Haskell worker, and publishes results to
result topics named in the same config. **No HTTP listener is bound in production mode.**

### Deliverables

- the active `.dhall` schema gains the production inference fields:
  `request_topics : List Text`, `result_topic : Text`, `engines : List EngineBinding`; the
  existing `demo_ui : Bool` flag remains for the demo surface
- `src/Infernix/Runtime/Pulsar.hs` subscribes to each topic in `request_topics`, deserializes the
  protobuf request payload via `proto-lens`, dispatches the request to the Haskell worker, and
  publishes the typed protobuf response to `result_topic`
- production `infernix service` startup binds no HTTP port; an `ss --listening --tcp` (or
  equivalent) probe of the production pod returns no Infernix-owned listener
- request and result topics use Pulsar's built-in protobuf schema support; the same `.proto`
  schemas feed both `proto-lens` (Haskell) and the auto-generated Python protobuf modules consumed
  by `python/adapters/<engine>/`
- `chart/templates/deployment-service.yaml` no longer requires a `demo_ui = True` deployment in
  production; the chart deploys `infernix-service` with the production entrypoint
  `infernix service`, publishes no Kubernetes HTTP `Service`, and exposes no fake service port for
  the production daemon

### Validation

- `infernix test integration` (production lane) publishes a protobuf request to a request topic
  named in the active `.dhall`, asserts a result lands on the configured `result_topic`, and
  asserts that the production pod binds no HTTP port (`ss --listening --tcp` shows no Infernix
  listener)
- with `demo_ui` off in the active `.dhall`, the cluster deploys `infernix-service`,
  `infernix-edge`, and the `infernix-{harbor,minio,pulsar}-gateway` workloads but does not deploy
  `infernix-demo`; `/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/` are absent from
  the edge inventory
- with `demo_ui` on, the demo workbench can submit a request via `/api/inference` and the same
  Haskell worker dispatch path serves both the demo HTTP submission and the Pulsar subscription
  path
- repeat `cluster up` runs do not regress the production inference surface; the daemon resumes
  consuming from the configured request topics on restart

### Remaining Work

- `src/Infernix/Runtime/Pulsar.hs` now owns the no-HTTP production-daemon placeholder, but it
  still does not subscribe to request topics, register protobuf schemas with Pulsar, dispatch
  requests through a real worker supervisor, or publish results to `result_topic`

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/runtime_modes.md` - service deployment modes and parity rules
- `documents/architecture/model_catalog.md` - model registration, matrix row ownership, and generated catalog contract
- `documents/engineering/model_lifecycle.md` - MinIO authority, local materialization, and cache semantics
- `documents/engineering/object_storage.md` - service-placement-specific MinIO access contract
- `documents/engineering/storage_and_state.md` - durable versus derived state inventory
- `documents/development/testing_strategy.md` - active-mode catalog and engine-binding coverage

**Product or reference docs to create/update:**
- `documents/reference/api_surface.md` - browser and operator API contract
- `documents/reference/web_portal_surface.md` - manual inference user surface

**Cross-references to add:**
- keep [00-overview.md](00-overview.md), [system-components.md](system-components.md), and [phase-5-web-ui-and-shared-types.md](phase-5-web-ui-and-shared-types.md) aligned when the API, model catalog, or generated-demo-config contract changes
