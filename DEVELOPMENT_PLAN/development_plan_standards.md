# Infernix Development Plan Standards

**Status**: Authoritative source
**Referenced by**: [README.md](README.md)

> **Purpose**: Define how the `infernix` development plan is organized, updated, and kept aligned
> with implementation, validation, and the future `documents/` suite.

## Core Principles

### A. Continuous Execution-Ordered Narrative

The plan reads as one ordered buildout from empty repository to supported local platform.

- Each phase assumes the previous phase has closed.
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

### C. Honest Completion Tracking

Status describes the current repository state, not the intended future state.

| Status | Meaning |
|--------|---------|
| `Done` | Implemented and validated; no remaining work |
| `Active` | Partially closed; remaining work is listed explicitly |
| `Blocked` | Waiting on a named prerequisite |
| `Planned` | Ready to start; dependencies are already satisfied |

Rules:

- `Done` requires passing validation, aligned docs, and no remaining work.
- `Active` requires a `Remaining Work` section.
- `Blocked` requires a `Blocked by` line.
- `Planned` must not hide unmet blockers.
- If Phase 0 is still open, later code-writing phases use `Blocked`, not `Planned`.

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
  storage doctrine, and operator workflows described by the plan, even when those capabilities are
  not fully implemented yet.
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
```

Rules:

- Apple Silicon calls `kind`, `kubectl`, `helm`, and Docker directly from the host environment.
- Apple Silicon host builds place the compiled `infernix` binary and other generated build
  artifacts under `./.build/`, and supported host-native command examples use `./.build/infernix`.
- On Apple Silicon, `cluster up` writes the repo-local kubeconfig to `./.build/infernix.kubeconfig`
  and must not mutate `$HOME/.kube/config` or the user's global current context.
- `infernix kubectl ...` is the supported operator wrapper for Kubernetes access and automatically
  targets the repo-local kubeconfig in the active build-output location.
- On Apple Silicon, `infernix` may install missing host prerequisites needed by the supported local
  runtime, including Homebrew-installed `poetry` when it is absent and other declared Python
  dependencies required by repo-owned runtime flows.
- Containerized Linux uses Compose only as a one-command launcher with the Docker socket forwarded
  and `./.data/` bind mounted.
- `docker compose up` and `docker compose exec` are not supported outer-control-plane workflows.

### L. Storage Doctrine Closure

The manual storage model is a hard architectural rule and cannot be weakened in later phases.

- All default storage classes are deleted during cluster bootstrap.
- The only supported persistent storage class is a `kubernetes.io/no-provisioner` class owned by
  this repo.
- PVCs are created only by Helm-owned StatefulSets or chart-owned persistence templates.
- PVs are created only by `infernix` lifecycle code and map deterministically into `./.data/`.
- Hand-authored standalone PVC manifests for durable workloads are forbidden.

### M. CLI Surface and Behavior Contract

All supported repository operations close through the `infernix` CLI.

The canonical command surface is:

- `infernix service`
- `infernix cluster up`
- `infernix cluster down`
- `infernix cluster status`
- `infernix kubectl ...`
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
- `infernix cluster up` reconciles cluster, storage, image, Helm, and mandatory local HA service
  state to the requested target rather than performing one-shot bootstrap steps.
- `infernix cluster down` reconciles cluster absence while preserving authoritative repo data under
  `./.data/`.
- `infernix cluster status` is read-only and never mutates cluster or repo state.
- `infernix kubectl ...` is a scoped wrapper around upstream `kubectl`, automatically injecting the
  repo-local kubeconfig from the active build-output location; it is not a separate lifecycle
  orchestration surface.
- `infernix test ...` and `infernix docs check` may reuse or reconcile prerequisites, but they do
  not depend on alternate imperative setup commands outside the supported CLI surface.
- No CLI flag or alternate command family selects between non-HA and HA service topology; the
  mandatory local HA topology is the only supported cluster target.

### N. Haskell Quality Gate Contract

Haskell formatting, linting, and compiler hygiene are first-class repository requirements.

- `infernix test lint` is the canonical static-quality entrypoint.
- `fourmolu` is the authoritative formatter for repo-owned Haskell source modules.
- `cabal-fmt` is the authoritative formatter for `.cabal` and `cabal.project` files.
- `hlint` is the authoritative linting layer for stylistic and simplification checks.
- Repo-owned validation enables strict compiler warnings and treats warnings as errors on supported
  paths.
- No second Haskell formatter or competing style authority is introduced.

### O. Cabal Build Doctrine and Container Artifact Isolation

Repo-owned Cabal defaults and container build isolation are hard repository rules.

- The repo contains an authoritative `cabal.project` that encodes the default Cabal build policy
  for supported host-native workflows, including artifact placement under `./.build/` and other
  repo-owned Cabal defaults.
- Supported Apple host-native `cabal build`, `cabal test`, or equivalent bare Cabal invocations
  inherit that `cabal.project` configuration and must not recreate `dist-newstyle/` or similar
  build output in the repo root.
- The container build root is `/opt/build/infernix`.
- Repo-owned container workflows and Dockerfile `cabal` invocations pass
  `--builddir=/opt/build/infernix` explicitly for Cabal work, even though the repo-owned
  `cabal.project` defines the host-native default.
- Unqualified `cabal build`, `cabal test`, or equivalent bare Cabal invocations are not a
  supported container workflow unless the container entrypoint or wrapper guarantees the same
  `/opt/build/infernix` isolation.
- Implementation must prevent accidental recreation of `dist-newstyle/` or similar build output in
  the mounted repo during supported container workflows.

### P. Test-Cluster Configuration Generation

`cluster up` is the supported test-environment bring-up command, and it owns the test Dhall
configuration needed by validation flows.

- `cluster up` auto-generates the Dhall configuration used for supported test workflows.
- The generated configuration enables every model appropriate for the active runtime mode or test
  environment.
- Generated Dhall configuration is not a tracked source artifact and must live in ignored build
  output locations.

## Cross-Reference Conventions

- Links inside `DEVELOPMENT_PLAN/` use relative paths.
- Use Markdown links only for files that exist in the current worktree.
- Future `documents/...` obligations are written as code-formatted paths until Phase 0 creates them.
- If a file is renamed, update every plan reference in the same change.
