# Infernix Development Plan Standards

**Status**: Authoritative source
**Referenced by**: [README.md](README.md)

> **Purpose**: Define how the `infernix` development plan is organized, updated, and kept aligned
> with implementation, validation, and the future `documents/` suite.

## Core Principles

### A. Continuous Execution-Ordered Narrative

The plan reads as one ordered buildout from empty repository to supported local platform.

- Each phase is written after the previous phase in dependency order.
- When later implementation lands before an earlier phase's final supported-lane rerun or
  environment-dependent blocker closes, the later phase explicitly names that open dependency in
  its `Phase Status` or `Current Repo Assessment` text instead of pretending the prerequisite is
  fully closed.
- Phase 0 is always documentation and governance. No code-writing phase may be marked `Active` or
  `Done` before Phase 0 closes.
- Newly discovered gaps are handled by adding explicit follow-on work, not by leaving stale
  completion claims in older documents.
- A reader unfamiliar with the repo should be able to follow the plan from top to bottom without
  reconstructing hidden dependencies.

### B. Detailed, Implementation-Oriented Content

The plan is intentionally concrete.

- Include real files, commands, runtime surfaces, storage paths, and validation gates where they
  materially clarify what must be built.
- Command examples use the canonical binary name `infernix`.
- Examples do not need to be verbatim implementation, but they must not contradict the supported
  architecture.
- When the plan cites another repository as a source of practices, it explicitly distinguishes the
  imported governance or doctrine ideas from any product-specific features, documents, or runtime
  assumptions that remain out of scope for `infernix`.

### C. Honest Completion Tracking

Status describes the current repository state, not the intended future state.

| Status | Meaning |
|--------|---------|
| `Done` | Implemented and validated; no remaining work |
| `Active` | Partially closed; remaining work is listed explicitly |
| `Blocked` | Waiting on a named prerequisite |
| `Planned` | Ready to start; dependencies are already satisfied |

Rules:

- `Done` requires passing validation, aligned docs, and no remaining work within the scope owned
  by that phase or sprint.
- `Active` requires a `Remaining Work` section.
- `Blocked` requires a `Blocked by` line.
- `Planned` must not hide unmet blockers.
- If Phase 0 is still open, later code-writing phases use `Blocked`, not `Planned`.
- A later phase may remain `Done` while an earlier phase is still `Active` or `Blocked` only when
  the earlier open item is a clearly named external dependency or supported-lane validation
  blocker, and the later phase calls that dependency out explicitly in its phase-status or
  current-assessment text.

### D. Declarative Current-State Language

Plan documents describe the intended supported architecture in present-tense declarative language.

- Say what the system uses, owns, validates, and exposes.
- Do not turn phase docs into migration diaries.
- Cleanup history belongs in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### E. One Canonical Folder Model

The authoritative plan lives in this exact layout:

```text
DEVELOPMENT_PLAN/
├── development_plan_standards.md
├── README.md
├── 00-overview.md
├── system-components.md
├── phase-0-documentation-and-governance.md
├── phase-1-repository-and-control-plane-foundation.md
├── phase-2-kind-cluster-storage-and-lifecycle.md
├── phase-3-ha-platform-services-and-edge-routing.md
├── phase-4-inference-service-and-durable-runtime.md
├── phase-5-web-ui-and-shared-types.md
├── phase-6-validation-e2e-and-ha-hardening.md
└── legacy-tracking-for-deletion.md
```

### F. System Component Inventory

[system-components.md](system-components.md) is the authoritative inventory for:

- operator surfaces and execution modes
- cluster services and edge routing
- runtime binaries and container roles
- serialization boundaries
- state and artifact locations

When architecture changes, update the component inventory in the same change.

### G. Phase Document Requirements

Each phase document must contain sprint-level sections in this format:

```markdown
## Sprint X.Y: Name [STATUS]

**Status**: Done | Active | Planned | Blocked
**Implementation**: `path/to/file` (required for Done, recommended for Active)
**Blocked by**: sprint id(s) (required for Blocked)
**Docs to update**: `documents/...`, `README.md`

### Objective

### Deliverables

### Validation

### Remaining Work
```

Additional sections such as `Architecture`, `Execution Modes`, `Storage Doctrine`, or `Route Map`
are encouraged when they clarify closure criteria.

### H. Documentation Requirements Section

Every phase document ends with a `## Documentation Requirements` section.

Use this format:

```markdown
## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/X.md` - technical contract or implementation note

**Product or reference docs to create/update:**
- `documents/reference/Y.md` - public surface description

**Cross-references to add:**
- align the relevant plan and README entry points
```

Important rule for this repository bootstrap stage:

- Until Phase 0 lands, the paths under `documents/` may not exist yet.
- They still appear in `Docs to update` and `Documentation Requirements` because the plan must make
  future documentation obligations explicit before the suite exists.
- When a phase creates or materially rewrites a broad engineering document, the owning sprint or
  phase calls out the intended document structure when it matters to closure criteria:
  - add a `TL;DR` or `Executive Summary` when the topic is broad
  - include an explicit `Current status` note when implemented behavior and target direction appear
    in the same document
  - include a `Validation` section when the document defines a contract that tests or lint must
    prove
  - answer these questions directly: what is the rule, what is current versus target, how is it
    validated, and what is local substrate detail versus true platform contract

### I. Explicit Cleanup and Removal Ledger

[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is the authoritative cleanup
ledger for obsolete paths, duplicate guidance, and stale compatibility surfaces.

- If an obsolete or duplicate surface still exists, it must appear in the ledger.
- Each item names its location, why it is slated for removal, and the owning phase or sprint.
- When cleanup lands, move the item from pending to completed.

### J. README and Documents Harmony

The plan and future `documents/` suite must agree on current-state implementation status. The root
README is exempt from current-state status parity because it is intentionally written as the
finished-product document.

- `00-overview.md`, all phase files, and `system-components.md` use the same phase names and
  current-state claims.
- `README.md` still reflects the authoritative intended product shape, canonical CLI surface,
  storage doctrine, operator workflows, runtime-mode envelope, and validation direction described by
  the plan, even when those capabilities are not fully implemented yet.
- `README.md`, `AGENTS.md`, and `CLAUDE.md` are governed root documents. When a sprint owns
  root-document governance, it explicitly states which file is canonical for a topic and which
  files are orientation or automation entry documents only.
- Root-document governance work calls out the metadata rules those files must follow, including
  explicit `Status`, `Supersedes`, and authoritative-reference or canonical-home markers when they
  distinguish canonical guidance from reference-only guidance.
- Root documents that are not canonical for a topic summarize and link to the canonical
  `documents/` home instead of restating the full contract.
- Once Phase 0 lands, `documents/documentation_standards.md` governs the docs suite while this file
  remains authoritative for the plan itself.
- When root-level workflow guidance changes, update `README.md`, `AGENTS.md`, and `CLAUDE.md` in
  the same change when needed.

### K. Dual Execution Context Contract

The supported control plane has two execution contexts, and plan documents must name which one a
command uses:

**Apple Silicon host-native control plane**

```bash
./.build/infernix cluster up
./.build/infernix kubectl get pods -A
./.build/infernix test integration
```

**Containerized Linux outer control plane**

```bash
docker compose run --rm infernix infernix cluster up
docker compose run --rm infernix infernix test integration
docker run --rm --gpus all -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD/.data:/workspace/.data" infernix-linux-cuda:local infernix --runtime-mode linux-cuda cluster up
```

Rules:

- Apple Silicon host-native control plane is the canonical operator surface. Final closure calls
  `kind`, `kubectl`, `helm`, and Docker directly from the host environment, and active phase docs
  must call out compatibility layers explicitly until that is true.
- Apple Silicon host builds place the compiled `infernix` binary and other generated build
  artifacts under `./.build/`, and supported host-native command examples use `./.build/infernix`.
- Plan documents do not introduce repo-owned scripts or wrappers for supported build or launch
  flows; they spell out direct `cabal`, `docker compose`, `docker run`, and `infernix`
  invocations when explicit flags are required.
- On Apple Silicon, `cluster up` writes the repo-local kubeconfig to `./.build/infernix.kubeconfig`
  and must not mutate `$HOME/.kube/config` or the user's global current context.
- On the Linux outer-container path, `cluster up` writes the repo-local kubeconfig to
  `./.data/runtime/infernix.kubeconfig` so fresh launcher containers can reuse the same durable
  cluster handle without depending on ephemeral `/opt/build` state.
- `infernix kubectl ...` is the supported operator wrapper for Kubernetes access and automatically
  targets the repo-local kubeconfig in the current execution context's durable location.
- On Apple Silicon, the intended minimal pre-existing host prerequisites are Homebrew plus ghcup.
- Colima is the only supported Docker environment on Apple Silicon and is installed from Homebrew
  on the supported path.
- After the binary exists, the Apple host workflow is allowed to let `infernix` reconcile the
  remaining Homebrew-managed operator tools needed by the active path and bootstrap Poetry through
  the host's system Python when adapter flows first need it; the repo-local adapter virtual
  environment still materializes only when an engine-adapter path is exercised explicitly.
- Containerized Linux uses Compose as the supported one-command launcher for `linux-cpu`, while
  `linux-cuda` uses a direct `docker run --gpus all infernix-linux-cuda:local ...` launcher with
  the Docker socket forwarded and `./.data/` bind mounted on the supported path.
- On Linux CPU, host prerequisites stop at Docker Engine plus the Docker Compose plugin.
- On Linux CUDA, host prerequisites stop at Docker Engine plus the supported NVIDIA driver and
  container-toolkit setup.
- `docker compose up` and `docker compose exec` are not supported outer-control-plane workflows.

### L. Runtime Mode Matrix Contract

The plan distinguishes control-plane execution context from supported runtime mode.

Runtime modes are the product-facing inference lanes:

| Runtime mode | Canonical mode id | Engine column selected from the README matrix |
|--------------|-------------------|-----------------------------------------------|
| Apple Silicon / Metal | `apple-silicon` | `Best Apple Silicon engine` |
| Ubuntu 24.04 / CPU | `linux-cpu` | `Best Linux CPU engine` |
| Ubuntu 24.04 / NVIDIA CUDA Container | `linux-cuda` | `Best Linux CUDA engine` |

Rules:

- Plan documents, `system-components.md`, and the governed docs must explicitly distinguish the two
  execution contexts from the three runtime modes.
- The comprehensive model, format, and engine matrix in the root README is the authoritative target
  coverage envelope for runtime-mode planning.
- For any given runtime mode, a matrix row is supported when that mode's engine column names a real
  engine rather than `Not recommended` or an empty cell.
- `linux-cuda` closes only when the Kind-backed cluster path exposes NVIDIA container runtime
  support, advertises `nvidia.com/gpu` resources to Kubernetes, and can schedule CUDA workloads on
  that substrate.
- Later-phase completion claims must not narrow the matrix to a hand-picked smoke subset once
  broad mode support is claimed.

### M. Generated Demo `.dhall` and ConfigMap Contract

`cluster up` generates the demo configuration for the active runtime mode as staging content and
publishes it into the cluster as a ConfigMap for cluster-resident consumers.

Rules:

- Apple host mode may stage the active mode's generated file under `./.build/` when the host-native
  daemon path needs it.
- Outer-container Linux stages the active mode's generated file ephemerally, then creates or
  updates the cluster ConfigMap; the outer container does not treat a static container file as the
  runtime input.
- The generated filename uses the active runtime-mode id, for example
  `infernix-demo-apple-silicon.dhall`, `infernix-demo-linux-cpu.dhall`, or
  `infernix-demo-linux-cuda.dhall`.
- The generated file enumerates every demo-visible model or workload supported in the active
  runtime mode and records the matrix row identity, artifact or format family, selected engine,
  request or result contract identifiers, and any mode-specific runtime-lane metadata needed by the
  service, web UI, or tests.
- `cluster up` creates or updates `ConfigMap/infernix-demo-config` from that generated content.
- In containerized execution contexts, cluster-resident consumers mount
  `ConfigMap/infernix-demo-config` read-only at `/opt/build/`.
- The outer-container control plane stages generated files under its active build root, while
  cluster-resident consumers read the active-mode `.dhall` from
  `/opt/build/infernix-demo-<mode>.dhall` via the mounted ConfigMap path.
- Cluster-resident consumers consume the active mode's file from that mounted path rather than
  from an image-baked static file.
- Rows whose active-mode engine cell is `Not recommended` are omitted from that mode's generated
  demo catalog.
- Across the full set of generated mode-specific demo `.dhall` files, every row in the README
  matrix appears in at least one generated catalog.
- The ConfigMap-backed mounted demo `.dhall` file is the exact source of truth for which models
  appear in the demo UI for the active runtime mode and which engine binding those models use.

### N. Storage Doctrine Closure

The manual storage model is a hard architectural rule and cannot be weakened in later phases.

- All default storage classes are deleted during cluster bootstrap.
- The only supported persistent storage class is a `kubernetes.io/no-provisioner` class owned by
  this repo.
- Every PVC-backed Helm deployment, including operator-managed durable claims reconciled from a
  repo-owned Helm release, uses that storage class.
- PVs are created only by `infernix` lifecycle code, map deterministically into `./.data/`, and
  bind explicitly to their intended claims.
- Hand-authored standalone PVC manifests for durable workloads are forbidden.
- Any in-cluster PostgreSQL deployment uses a Patroni cluster managed by the Percona Kubernetes
  operator, even when an upstream chart could self-deploy PostgreSQL.
- Dedicated PostgreSQL clusters per service are allowed, but direct chart-managed standalone
  PostgreSQL StatefulSets are not part of the supported contract.

### O. CLI Surface and Behavior Contract

All supported repository operations close through the `infernix` CLI.

The canonical command surface is:

- `infernix service`
- `infernix cluster up`
- `infernix cluster down`
- `infernix cluster status`
- `infernix cache status`
- `infernix cache evict`
- `infernix cache rebuild`
- `infernix kubectl ...`
- `infernix lint files`
- `infernix lint docs`
- `infernix lint proto`
- `infernix lint chart`
- `infernix test lint`
- `infernix test unit`
- `infernix test integration`
- `infernix test e2e`
- `infernix test all`
- `infernix docs check`

Rules:

- `infernix service` is the only supported long-running daemon entrypoint and the only command
  family that is not idempotent by design.
- Every repo-owned lifecycle, validation, and docs command other than `infernix service` is
  declarative and idempotent.
- `infernix cluster up` reconciles cluster, storage, image, Helm, mandatory local HA service state,
  the active runtime mode's demo-config staging and ConfigMap publication, and the chosen edge port
  to the requested target rather than performing one-shot bootstrap steps.
- `infernix cluster up` chooses the edge port by attempting `9090` first and incrementing by 1
  until an open port is found, records the chosen port under `./.data/runtime/edge-port.json`, and
  prints the chosen port to the operator during bring-up.
- `infernix cluster down` reconciles cluster absence while preserving authoritative repo data under
  `./.data/`.
- `infernix cluster status` is read-only and never mutates cluster or repo state.
- `infernix cache status`, `infernix cache evict`, and `infernix cache rebuild` operate only on
  manifest-backed derived cache state and do not rewrite the generated catalog or publication
  contract.
- `infernix kubectl ...` is a scoped wrapper around upstream `kubectl`, automatically injecting the
  repo-local kubeconfig from the active build-output location; it is not a separate lifecycle
  orchestration surface.
- `infernix lint ...`, `infernix test ...`, and `infernix docs check` may reuse or reconcile
  prerequisites, but they do not depend on alternate imperative setup commands outside the
  supported CLI surface.
- No CLI flag or alternate command family selects between non-HA and HA service topology; the
  mandatory local HA topology is the only supported cluster target.

### P. Integration and E2E Coverage Contract

Mode-aware validation is explicit.

- `infernix test integration` for a given active runtime mode currently validates the published
  catalog contract, routed surfaces, cache lifecycle, every generated active-mode catalog entry,
  and a service-loop roundtrip for that mode.
- when an owning phase calls out real-cluster HA or lifecycle assertions, the supported
  non-simulated lane also owns those pod-replacement, durability, failover, or rebinding checks.
- `infernix test e2e` for a given active runtime mode exercises every demo-visible catalog entry
  present in that same generated file through the routed web surface unless a narrower exception is
  called out explicitly in the owning phase document.
- Exhaustive per-entry integration coverage is claimed only once the owning phase documents that
  broader contract explicitly and keeps any remaining supported-lane validation work in `Active`
  status until those reruns close.
- Integration and E2E checks use the engine binding encoded in the mounted ConfigMap-backed demo
  `.dhall`, which must match the appropriate mode column from the README matrix.
- `infernix test all` aggregates lint, unit, integration, and E2E for the active runtime mode; the
  full Apple, CPU, and CUDA matrix closes only when those mode-specific runs all pass on their
  supported lanes.

### Q. Haskell Quality Gate Contract

Static quality and compiler hygiene are first-class repository requirements.

- `infernix test lint` is the canonical static-quality entrypoint.
- The plan must describe the actual lint, docs, formatting, or compiler-warning checks the
  repository enforces today rather than naming aspirational external tools as if they are already
  active.
- When the plan names `documents/development/haskell_style.md`, it describes the actual formatter,
  linter, `cabal format`, and warning-gate behavior that supported validation enforces today.
- The plan distinguishes mechanically enforced repository hard-gate inputs from editor-only
  guidance and keeps review guidance separate from hard validation rules.
- The plan points to `src/Infernix/Lint/HaskellStyle.hs` as the enforcement-model implementation
  when describing Haskell style-guide hard gates.
- The Haskell style-guide obligations called out by the plan include review guidance for module
  shape, function shape, effect-boundary clarity, and typed control flow.
- The Haskell style guide states the fail-fast rule explicitly: supported validation fails on
  hard-gate violations and does not silently rewrite tracked source.
- `ormolu` remains the canonical formatter unless the implementation changes; the plan must not
  imply a switch to `fourmolu` without an atomic implementation and documentation update.
- Repo-owned validation enables strict compiler warnings and treats warnings as errors on supported
  paths.
- If the repository later adopts external formatters or linters, the plan must be updated
  atomically with that implementation change so the named tools match reality.
