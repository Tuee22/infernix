# Phase 0: Documentation and Governance

**Status**: Done
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md), [00-overview.md](00-overview.md)

> **Purpose**: Create the governed `documents/` suite, define documentation maintenance rules, and
> make the development plan and docs suite stay aligned as the repository grows.

## Documentation-First Gate

This phase is closed. The governed docs, root workflow guidance, and docs validator now describe
the current doctrine: Envoy Gateway routing, per-substrate container packaging on Linux,
host-native Apple execution, per-substrate Python adapter projects, and repository hygiene rules.

## Current Repo Assessment

The repository has a governed docs suite, and the governed docs align with the doctrine declared
in [00-overview.md](00-overview.md): the two-binary topology, the Pulsar-only production
inference surface, the demo HTTP surface served only by `infernix-demo`, the Python restriction
to per-substrate adapter projects under `python/<substrate>/`, and the PureScript demo UI built
with spago and consuming Haskell-owned generated contracts derived through `purescript-bridge`.
The docs validator forbids the retired-doctrine phrases outside
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

- the docs suite distinguishes control-plane execution context from runtime mode
- the docs suite carries the README-scale model or format or engine matrix as a first-class
  planning and validation contract
- the docs suite documents generated mode-specific demo `.dhall` staging, ConfigMap-backed
  publication, `/opt/build/`, protobuf target contracts, `9090`-first edge-port selection, and
  active-mode exhaustive integration and E2E coverage
- the docs suite documents the two-binary topology, the Pulsar-only production inference surface,
  the Python restriction to engine adapters with the strict mypy plus black plus ruff quality
  gate, and the PureScript demo UI plus the current Haskell-owned contract generator
- the docs validator (`infernix lint docs`, implemented in `src/Infernix/Lint/Docs.hs`) validates
  those phrases directly so later drift is caught early, and
  enforces the retired-doctrine forbidden-phrase rule outside
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

## Sprint 0.1: `documents/` Suite Scaffold [Done]

**Status**: Done
**Implementation**: `documents/README.md`, `documents/architecture/overview.md`
**Docs to update**: `README.md`, `documents/README.md`

### Objective

Create a documentation suite shaped like the reference repositories rather than relying on README-only guidance.

### Deliverables

- `documents/README.md`
- `documents/documentation_standards.md`
- directory taxonomy:

```text
documents/
├── README.md
├── documentation_standards.md
├── architecture/
├── development/
├── engineering/
├── operations/
├── reference/
├── tools/
└── research/
```

- `documents/` becomes the canonical documentation home; `docs/` is not introduced

### Validation

- `find documents -maxdepth 1 -type d | sort` shows the governed suite structure
- `README.md` points to `documents/` and `DEVELOPMENT_PLAN/` rather than embedding layout sketches

### Remaining Work

None.

---

## Sprint 0.2: Documentation Standards and Suite Rules [Done]

**Status**: Done
**Implementation**: `documents/documentation_standards.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: `documents/documentation_standards.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Create the documentation equivalent of the reference repositories' standards files.

### Deliverables

- `documents/documentation_standards.md` defines status metadata, naming rules, cross-link rules, and suite taxonomy
- the standards file explicitly states that `DEVELOPMENT_PLAN/` owns implementation status and phase closure
- contributor guidance in `AGENTS.md` and `CLAUDE.md` stays aligned with the docs workflow

### Validation

- every governed document begins with the required metadata block
- the standards file names the canonical suite taxonomy and the SSoT rules
- root guidance files do not contradict the documentation workflow

### Remaining Work

None.

---

## Sprint 0.3: Canonical Documentation Set [Done]

**Status**: Done
**Implementation**: `documents/`
**Docs to update**: `documents/architecture/overview.md`, `documents/architecture/model_catalog.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`, `documents/development/haskell_style.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/docker_policy.md`, `documents/engineering/edge_routing.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/engineering/model_lifecycle.md`, `documents/engineering/object_storage.md`, `documents/engineering/storage_and_state.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/reference/web_portal_surface.md`, `documents/tools/harbor.md`, `documents/tools/minio.md`, `documents/tools/postgresql.md`, `documents/tools/pulsar.md`

### Objective

Create the minimum governed docs needed to explain the intended product before implementation begins, without overloading the README.

### Deliverables

- architecture docs for topology, runtime modes, model catalog, and web UI
- development docs for local setup, frontend contracts, Haskell style, and testing strategy
- engineering docs for build artifacts, Docker policy, storage, edge routing, object storage, and model lifecycle
- operations docs for cluster bootstrap and Apple Silicon workflow
- reference docs for API, CLI, and browser surfaces
- tools docs for Harbor, MinIO, PostgreSQL, and Pulsar

### Validation

- each major planned topic has exactly one canonical governed document before code writing starts
- README becomes an orientation document instead of the authoritative home of deep architecture rules
- inbound and outbound links across the suite resolve correctly

### Remaining Work

None.

---

## Sprint 0.4: Documentation Validation and Plan Harmony [Done]

**Status**: Done
**Implementation**: `src/Infernix/Lint/Docs.hs`, `README.md`
**Docs to update**: `documents/documentation_standards.md`, `documents/README.md`, `README.md`

### Objective

Make doc consistency a first-class gate and keep the plan and governed docs synchronized during the
bootstrap stage and after the Haskell CLI takes ownership of the same workflow.

### Deliverables

- `infernix lint docs` validates required headers, relative links, and plan or docs cross-references
- the plan remains authoritative for implementation status
- the docs suite remains authoritative for architecture and operator guidance once the relevant docs exist
- Phase 1 wires the same validation logic into `infernix docs check`

### Validation

- `infernix lint docs` passes after documentation edits
- changing a canonical route, storage rule, or CLI command requires updating the plan and the owning docs in the same change
- stale references to disallowed README-only architecture guidance fail the docs validation path

### Remaining Work

None. Runtime-mode matrix and generated-demo-config expansion lives in Sprint 0.5.

---

## Sprint 0.5: Runtime-Mode Matrix Documentation Realignment [Done]

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`
**Docs to update**: `README.md`, `documents/architecture/runtime_modes.md`, `documents/architecture/model_catalog.md`, `documents/development/testing_strategy.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/model_lifecycle.md`, `documents/tools/pulsar.md`, `documents/reference/web_portal_surface.md`

### Objective

Realign the governed docs and plan around the updated README direction before more implementation
closure claims continue.

### Deliverables

- the plan and governed docs explicitly distinguish the two control-plane execution contexts from
  the three runtime modes
- the README matrix is reflected as the authoritative target coverage envelope in the plan and the
  owning governed docs
- the governed docs explain that `cluster up` stages `infernix-demo-<mode>.dhall` for the active
  runtime mode and publishes it into `ConfigMap/infernix-demo-config`
- the governed docs explain that the mounted ConfigMap-backed `.dhall` file is the exact source of
  truth for cluster-resident demo-visible models and their engine binding in that mode
- the governed docs explain that, in containerized execution contexts, the mounted `.dhall` lives
  at `/opt/build/` because the daemon watches the file next to its binary
- the governed docs explain that durable runtime manifests and Pulsar payloads are defined by
  repo-owned `.proto` schemas, with `proto-lens`-generated Haskell bindings and Pulsar built-in
  protobuf schema support
- the governed docs explain that `linux-cuda` requires a GPU-enabled Kind path with NVIDIA runtime
  support and `nvidia.com/gpu` advertising
- the governed docs explain that integration and E2E enumerate every generated catalog entry for
  the active mode and use the engine binding encoded in that file
- the governed docs explain that `cluster up` chooses the edge port by trying `9090` first,
  increments by 1 until open, records the result, and prints the chosen port to the operator
- the docs validator and documentation standards name these relationships clearly enough that later
  drift is caught quickly

### Validation

- runtime-mode, model-catalog, build-artifact, and testing-strategy docs all use the same runtime
  mode names and describe the same generated demo-config contract
- the plan, README, and docs suite all state that integration and E2E coverage are active-mode
  exhaustive rather than smoke-only when no explicit exception is called out
- `infernix lint docs` passes after the alignment updates

### Remaining Work

None.

---

## Sprint 0.6: Doctrine Realignment Across Documentation Suite [Done]

**Status**: Done
**Implementation**: `documents/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: `documents/architecture/overview.md`, `documents/architecture/web_ui_architecture.md`, `documents/development/frontend_contracts.md`, `documents/development/local_dev.md`, `documents/development/testing_strategy.md`, `documents/development/python_policy.md`, `documents/development/purescript_policy.md`, `documents/engineering/edge_routing.md`, `documents/engineering/build_artifacts.md`, `documents/engineering/model_lifecycle.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/api_surface.md`, `documents/reference/web_portal_surface.md`, `documents/reference/cli_reference.md`, `documents/tools/pulsar.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`

### Objective

Realign the documentation suite, the root README, and contributor guidance with the new doctrine
declared in [00-overview.md](00-overview.md) Hard Constraints 1, 13, 14, and 15:
two-binary topology (`infernix` plus `infernix-demo` sharing `infernix-lib`); production inference
surface is Pulsar subscription only; demo HTTP surface lives only in `infernix-demo`; Python is
restricted to `python/<substrate>/adapters/*.py` and validated by Poetry plus mypy strict, black, and ruff
strict in every adapter container build; and the demo UI is PureScript with frontend types derived
from Haskell-owned generated contracts derived through `purescript-bridge`.

### Deliverables

- every `documents/` file and the root `README.md`, `AGENTS.md`, and `CLAUDE.md` describe the
  new doctrine in present-tense declarative language
- new `documents/development/python_policy.md` documents when Python is allowed (engine adapters
  whose engine is Python-native), the Poetry plus `python/pyproject.toml` workflow, the
  repo-local-Poetry-environment-outside-cluster vs system-wide-inside-container split, and the strict mypy plus
  black plus ruff quality gate integrated into every adapter container build
- new `documents/development/purescript_policy.md` documents the spago plus purs toolchain, the
  `purescript-spec` test framework, and the Haskell-owned contract generator
- `documents/architecture/web_ui_architecture.md` is rewritten to describe PureScript built by
  spago, served from `web/dist/`, and consumed by `infernix-demo`
- `documents/development/frontend_contracts.md` describes the PureScript contract-generation path
  rather than build-generated JavaScript
- `documents/engineering/edge_routing.md` describes the Haskell edge proxy
- `documents/engineering/build_artifacts.md` describes `web/dist/` populated by the current
  `spago bundle` path and the two-binary OCI image with selectable entrypoint
- `documents/engineering/model_lifecycle.md` describes the Haskell worker plus per-substrate
  Python adapter modules under `python/<substrate>/adapters/`
- `documents/operations/apple_silicon_runbook.md` and `documents/development/local_dev.md` drop
  Homebrew-Poetry-as-prereq language; Poetry materializes only when an engine-adapter test is
  exercised
- `documents/operations/cluster_bootstrap_runbook.md` notes that production `.dhall` configs leave
  the demo UI off and the cluster has no HTTP API in that case
- `documents/reference/api_surface.md` and `documents/reference/web_portal_surface.md` carry an
  explicit "demo-only; not the production surface" header
- `documents/reference/cli_reference.md` adds the `infernix-demo` binary, the new `infernix edge`,
  `infernix gateway harbor|minio|pulsar`, `infernix lint`, and `infernix internal ...` subcommands,
  and describes `infernix service` as a Pulsar consumer in production
- `documents/tools/pulsar.md` adds the production-inference subscription and dispatch contract,
  including the `.dhall` schema fields `request_topics`, `result_topic`, and `engines`
- the docs validator forbids the retired-doctrine vocabulary recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) everywhere else in the
  governed suite
- root `README.md` describes the production surface as "publish protobuf to Pulsar", describes the
  demo UI as PureScript, and updates the topology diagram for two binaries
- `AGENTS.md` and `CLAUDE.md` add the doctrine line: "Custom logic in Haskell. Python only for
  Python-native engine adapters under `python/adapters/`. Frontend in PureScript with types from
  Haskell. Production accepts work via Pulsar; demo UI only via `infernix-demo`."

### Validation

- the docs validator passes against the rewritten suite
- `infernix lint docs` passes against the governed suite and the root workflow documents
- every governed document still begins with the required metadata block
- inbound and outbound links across the suite resolve correctly
- root `README.md`, `AGENTS.md`, and `CLAUDE.md` carry the doctrine line and the two-binary topology

### Remaining Work

None. The Haskell migration of the docs validator is owned by Phase 1 Sprint 1.6.

---

## Sprint 0.7: Doctrine Realignment for Envoy Gateway API, Substrate Container, and Hygiene [Done]

**Status**: Done
**Implementation**: `documents/engineering/edge_routing.md`, `documents/engineering/docker_policy.md`, `documents/engineering/build_artifacts.md`, `documents/development/python_policy.md`, `documents/development/purescript_policy.md`, `documents/operations/apple_silicon_runbook.md`, `documents/operations/cluster_bootstrap_runbook.md`, `documents/reference/cli_reference.md`, `documents/reference/web_portal_surface.md`, `documents/architecture/overview.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `src/Infernix/Lint/Docs.hs`
**Docs to update**: every governed doc touched above

### Objective

Realign the governed documentation suite, the root README, and contributor guidance with the
new doctrine declared in [00-overview.md](00-overview.md): Envoy Gateway API replaces every
Haskell custom reverse proxy; the demo cluster runs locally with no auth; one custom container
per Linux substrate (`ubuntu:24.04` base, ghcup-pinned GHC 9.14.1 + Cabal 3.16.1.0, Python 3 +
pip + Poetry from apt and pip, in-container engine builds including llama.cpp, gcc 15.2 from
the Ubuntu Toolchain Test PPA, and a no-`apt`/`pip`/compile rule for the in-container daemon);
Apple Silicon is host-native with daemon-driven `brew` and system `clang` engine setup; no
`.sh` files anywhere in the repo; no committed build artifacts (`poetry.lock`, generated proto,
`.mypy_cache`, `.ruff_cache`, `*.pyc`, `web/dist/`, `web/spago.lock`); README quick start per
substrate; PureScript contracts derived via `purescript-bridge` from `src/Generated/Contracts.hs`.

### Deliverables

- `documents/engineering/edge_routing.md` is rewritten to describe the Envoy Gateway controller,
  the `infernix-edge` Gateway resource, the HTTPRoute manifest set as the canonical route
  contract, the demo-cluster no-auth posture, and the URLRewrite filter behavior per portal.
  The Haskell unified-proxy and per-backend Haskell gateway language is removed
- `documents/engineering/docker_policy.md` is rewritten to describe the per-substrate
  container shape (one custom Dockerfile per Linux substrate, `ubuntu:24.04` or
  `nvidia/cuda:<…>-ubuntu24.04` base, ghcup-pinned toolchain, Poetry-only Python invocation,
  in-container engine builds, gcc 15.2, no in-container `apt`/`pip`/compile from the daemon),
  and explicitly notes that `apple-silicon` has no Dockerfile (host-native build)
- `documents/engineering/build_artifacts.md` is rewritten to describe the per-substrate
  Dockerfile layout, the repo-local Apple Silicon Poetry venv at `python/apple-silicon/.venv/`,
  the substrate-container's role as launcher + workload + Playwright executor, and the
  built-artifact ignore rules covered by `.gitignore` and `.dockerignore`
- `documents/development/python_policy.md` is rewritten to describe per-substrate
  `pyproject.toml` files, the single `poetry run check-code` quality entrypoint, per-engine
  `setup-<engine>` console scripts, the all-Python-via-`poetry-run` rule, and the
  Apple-Silicon-`.venv` / Linux-system-wide split
- `documents/development/purescript_policy.md` is updated to confirm the
  `src/Generated/Contracts.hs` + `purescript-bridge` derivation path and to drop any reference
  to a separate Playwright image (Playwright now lives inside the substrate container)
- `documents/operations/apple_silicon_runbook.md` is rewritten to document the operator
  pre-installed ghcup contract (GHC 9.14.1 + Cabal 3.16.1.0 active), the daemon-driven `brew`
  and system `clang` engine setup, the `cabal build` quick start, and the lack of a
  Dockerfile on Apple Silicon
- `documents/operations/cluster_bootstrap_runbook.md` is updated to document the substrate
  container build step on Linux substrates, the Envoy Gateway controller installation flow,
  and the HTTPRoute-driven route inventory
- `documents/reference/cli_reference.md` removes `infernix edge` and `infernix gateway
  harbor|minio|pulsar` from the canonical CLI surface; the supported routing surface is the
  Helm-installed Envoy Gateway controller plus repo-owned HTTPRoute manifests
- `documents/reference/web_portal_surface.md` rewrites the route inventory to render straight
  from the HTTPRoute manifest set (Phase 3 Sprint 3.8) rather than the Haskell edge proxy
- `documents/architecture/overview.md` updates the topology to remove the Haskell edge and
  per-backend gateway pods, replace them with Envoy Gateway API + HTTPRoutes, and describe one
  substrate container per Linux runtime mode
- `README.md` is rewritten to carry per-substrate quick start subsections (Apple Silicon
  host-native, Linux CPU substrate container, Linux CUDA substrate container) plus updated
  topology language
- `AGENTS.md` and `CLAUDE.md` add the doctrine line: "Routing through Envoy Gateway API + HTTPRoute
  manifests, no auth (demo cluster, local-only). One custom container per Linux substrate
  (`ubuntu:24.04` or `nvidia/cuda:<…>-ubuntu24.04`); Apple Silicon is host-native (operator-
  installed ghcup, daemon-driven brew + clang). All Python through `poetry run`. No `.sh`
  files; no committed build artifacts."
- `src/Infernix/Lint/Docs.hs` adds the retired-doctrine forbidden-phrase set covering
  `infernix edge`, `infernix gateway`, `tools/python_quality.sh`, `web/Dockerfile`,
  `docker/<engine>-python.Dockerfile`, and Harbor admin Basic auth language outside
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

### Validation

- `infernix lint docs` passes against the rewritten suite and the root workflow documents
- `infernix lint docs` fails when any of the new forbidden retired-doctrine phrases appears
  outside `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
- every governed document still begins with the required metadata block; inbound and outbound
  links across the suite resolve correctly
- root `README.md`, `AGENTS.md`, and `CLAUDE.md` carry the updated doctrine line and the per-substrate
  quick start

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/documentation_standards.md` - suite governance and SSoT rules
- `documents/architecture/overview.md` - implemented topology
- `documents/development/local_dev.md` - supported local workflows
- `documents/development/frontend_contracts.md` - Haskell-owned frontend contract and webapp build-time generation rules
- `documents/development/haskell_style.md` - Haskell formatter, lint, and compiler-warning policy
- `documents/development/testing_strategy.md` - supported validation matrix and active-mode exhaustive coverage rules
- `documents/engineering/build_artifacts.md` - builddir, generated-demo-config staging, watched mount path, and artifact isolation
- `documents/engineering/docker_policy.md` - outer-container rules
- `documents/engineering/k8s_storage.md` - manual PV doctrine
- `documents/engineering/edge_routing.md` - `9090`-first one-port route policy and operator display
- `documents/engineering/k8s_native_dev_policy.md` - Kind, Helm, and GPU-enabled `linux-cuda` workflow
- `documents/engineering/object_storage.md` - MinIO authority and routed access
- `documents/engineering/model_lifecycle.md` - artifact lifecycle and local materialization
- `documents/engineering/storage_and_state.md` - durable versus derived state
- `documents/architecture/model_catalog.md` - model registration, matrix row ownership, and generated catalog contract
- `documents/architecture/runtime_modes.md` - execution contexts versus runtime modes
- `documents/architecture/web_ui_architecture.md` - cluster-resident webapp service and UI topology
- `documents/reference/cli_reference.md` - CLI surface
- `documents/reference/cli_surface.md` - CLI summary surface
- `documents/reference/api_surface.md` - typed API contract
- `documents/reference/web_portal_surface.md` - browser surface and active-mode catalog behavior
- `documents/tools/harbor.md` - Harbor notes
- `documents/tools/minio.md` - MinIO notes
- `documents/tools/postgresql.md` - PostgreSQL operator and Patroni notes
- `documents/tools/pulsar.md` - Pulsar notes

**Product or reference docs to create/update:**
- `documents/README.md` - suite index and navigation

**Cross-references to add:**
- keep [README.md](README.md), [development_plan_standards.md](development_plan_standards.md), [00-overview.md](00-overview.md), and the governed docs aligned on runtime-mode names, ConfigMap-backed generated demo-config semantics, the watched `/opt/build/` mount path, GPU-enabled `linux-cuda` rules, and active-mode test coverage
