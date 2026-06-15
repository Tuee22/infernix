# Python Policy

**Status**: Authoritative source
**Referenced by**: [../architecture/overview.md](../architecture/overview.md), [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define when Python is permitted in this repository, how it is managed, and the
> strict quality gate every adapter build must run.

## When Python Is Allowed

Python is permitted only under `python/adapters/` and only when the bound inference engine has no
non-Python binding.

- supported Python-native engines live as per-engine modules inside the shared adapter package
- each adapter is a thin module that reads one worker-owned request payload from stdin, runs the
  adapter logic, and emits one worker-owned result payload to stdout
- the Haskell worker (`src/Infernix/Runtime/Worker.hs`) is the single dispatch point for
  Python-native bindings; it resolves an engine-specific Poetry entrypoint and exchanges typed
  protobuf worker messages over stdio
- no other Python lives in this repository on the supported path; build helpers, lint, chart
  discovery, image publishing, demo-config parsing, docs validation, and the demo HTTP host are
  all Haskell

## Toolchain

- the shared Poetry project lives at `python/pyproject.toml`
- on the intended Apple clean-host path, `infernix` may reconcile the Homebrew-managed
  `python@3.12` formula and `python3.12` command and then bootstrap the `poetry` executable when
  adapter setup or validation first needs it; the Poetry bootstrap may reuse an already available
  compatible Python 3.12+ executable when one passes the implemented version check
- outside the cluster, `poetry install --directory python` materializes the repo-local
  `python/.venv/` environment for adapter validation on the Apple host path
- concurrent host-daemon setup for the shared `python/` project serializes `poetry install` with
  the repo-local `python/.infernix-poetry-install.lock` directory so multiple `infernix service`
  processes do not mutate `python/.venv/` at the same time
- Linux substrate image builds run `poetry install --directory python` during the image build and
  then execute adapters from the shared `python/` project root through `poetry run ...`
- Poetry is not a generic platform prerequisite; it materializes only when an adapter validation or
  setup path is exercised explicitly

Current status:

- on the Apple host-native path, `infernix` reconciles the Homebrew-managed `python@3.12` formula
  and `python3.12` command and bootstraps a user-local `poetry` executable when adapter setup or
  validation first needs it; the Poetry bootstrap may reuse an already available compatible
  Python 3.12+ executable when one passes the implemented version check
- once `poetry` exists, the shared project still materializes `python/.venv/` only on demand
- concurrent materialization attempts for the same shared project are serialized by
  `python/.infernix-poetry-install.lock`

## Quality Gate

The canonical adapter quality gate is the `check-code` Poetry entrypoint declared in the shared
`python/pyproject.toml`.

The supported invocation is `poetry run check-code` from inside `python/`.

It invokes the following in sequence and exits non-zero on any failure:

| Check | Command | Strictness |
|-------|---------|------------|
| Type check | `poetry run mypy --strict adapters` | strict |
| Format check | `poetry run black --check adapters` | check-only |
| Lint | `poetry run ruff check adapters` | strict |

Rules:

- the gate runs as a single build step in every Linux substrate image
- `infernix test lint` runs the same gate against the shared project when adapters are present
- adapter modules carry inline type annotations on every function and class; `# type: ignore`
  pragmas require an explanatory comment

## Machine-Independent Gate Invariant

`poetry run check-code` is part of the machine-independent gate set (development plan standards
Section Q): it must pass on whichever single host is present, regardless of which substrate-specific
inference wheels that host can install. The product targets both Apple Silicon (MLX, `jax-metal`,
Core ML, Metal `llama.cpp`/`whisper.cpp`) and CUDA Linux (vLLM, CUDA PyTorch, TensorFlow), and no
single host installs every wheel. The gate stays machine-independent through one hard rule:

- Inference frameworks — `torch`, `transformers`, `vllm`, `tensorflow`, `jax`/`jax-metal`, `mlx`,
  `diffusers`, `coremltools`, `basic-pitch`, `demucs`, `omnizart`, and any future engine wheel —
  are **never** declared in `python/pyproject.toml` and **never** imported at module top level.
- Each adapter lazy-imports its framework **inside the transform body**, behind
  `try/except ImportError` that raises a typed runtime error when the wheel is absent. The
  framework modules are listed in a `[[tool.mypy.overrides]]` block in `python/pyproject.toml` with
  `ignore_missing_imports = true`, so `mypy --strict` type-checks the adapter on any host without
  the wheels present (and without per-line `# type: ignore` churn that breaks when a wheel is
  present-but-untyped on cohort hardware).
- This mirrors the established `adapters/model_cache.py` boto3 precedent: the import only fires at
  real-inference time, so `mypy --strict`/`black`/`ruff` over the adapter tree pass on any host
  without the wheels installed.
- Installing the real wheels and producing real per-family output is the **cohort gate** (Wave I),
  exercised on substrate hardware — it is never a precondition for `poetry run check-code`. A
  top-level framework import or a framework entry in `pyproject.toml` silently re-couples the gate
  to one host and is rejected on review.

## Per-Engine Framework Venvs

Phase 4 Sprint 4.16 supersedes the earlier single-shared-venv assumption. Real per-family
inference needs vLLM, PyTorch (CUDA), TensorFlow, JAX (CUDA), and Diffusers, whose pins are
mutually incompatible (vLLM pins an exact torch; TF and JAX ship their own CUDA stacks; one Poetry
lock cannot resolve `torch` from two indices). Each framework engine therefore installs into its
own isolated in-project venv:

- The shared `python/` project stays **framework-free** — it owns the `adapters` package, the
  `check-code` gate, and the protobuf stubs. Its venv (`python/.venv/`) carries no ML framework, so
  `poetry run check-code` is the machine-independent gate (see "Machine-Independent Gate Invariant").
- Each engine has its own Poetry project at `python/engines/<engine>/` (`package-mode = false`,
  in-project venv `python/engines/<engine>/.venv/`) that depends on the shared `infernix-adapters`
  package via an editable path dependency and declares its framework wheels in an **optional**
  substrate group. The default `poetry install` there pulls no framework; the substrate build opts
  in with `poetry install --directory python/engines/<engine> --with cuda` (linux-gpu, cu128 torch
  for Blackwell) or `--with apple-silicon` for the Apple host-native framework engines that publish
  Darwin arm64 wheels (`transformers`, `pytorch`, and `diffusers`). The linux-cpu framework groups
  remain a follow-on.
- The Haskell worker (`src/Infernix/Runtime/Worker.hs`) resolves the per-engine venv at dispatch:
  when `python/engines/<engine>/.venv/bin/python` exists it runs `python -m adapters.<module>` in
  that venv (the in-project venv installs console scripts with a relative shebang, so the worker
  invokes the absolute venv interpreter with `-m` rather than the script). When the per-engine venv
  is absent (the machine-independent unit environment), the worker falls back to the shared
  framework-free project so an absent framework fails fast.
- The linux-gpu image build (`docker/Dockerfile`) bakes each engine's `--with cuda` venv as a
  separate layer; a failed engine install removes its partial venv so the runtime falls back to the
  fail-fast path (a named cohort residual) rather than a broken venv. Basic Pitch TensorFlow
  (published wheel pins TensorFlow `<2.15.1`), Omnizart (TF1-era), and MT3 (unmaintained JAX) do
  not resolve on the supported Python 3.12 / CUDA 12.8 substrate and are named cohort residuals
  (see [../../DEVELOPMENT_PLAN/cohort-validation-waves.md](../../DEVELOPMENT_PLAN/cohort-validation-waves.md)).

`find python -name '*.py' -type f` still returns only files under `python/adapters/`; the
`python/engines/<engine>/` projects carry only `pyproject.toml` + `poetry.toml`, and their `.venv/`
trees are gitignored build artifacts.

## Packaging Warnings

Python packaging warnings are handled by execution context:

- on the Apple host-native path, adapter setup uses a repo-local `python/.venv/` and must not run
  host package installation as root
- inside Linux substrate Docker image builds, Poetry is installed into `/opt/poetry`, a dedicated
  virtual environment owned by the image layer, and the project dependencies still install into the
  repo-local `python/.venv/`
- a pip warning about running as root is not expected on the supported image-build path

The repository should eliminate Python packaging warnings that come from maintained tool upgrades.
If a root-pip warning returns, treat it as a substrate image-layout regression rather than as an
accepted warning.

## Adapter Contract

Each engine-specific adapter module under `python/adapters/` honors a small process contract:

- read one request payload from stdin
- execute the adapter
- write one result payload to stdout
- log errors to stderr; the Haskell worker captures stderr for diagnostics

Current state:

- the worker request and response payloads are typed protobuf messages from
  `proto/infernix/runtime/inference.proto`, consumed on the Python side through
  `tools/generated_proto/`
- the worker request includes selected-model metadata, the engine install root, non-text input
  object references, and model-cache/MinIO wiring decoded by the Haskell worker from mounted
  `ClusterConfig` plus secret-file-backed `SecretsConfig` values
- the shared project exposes one Poetry console script per adapter together with matching
  `setup-*` entrypoints
- each `setup-*` entrypoint writes an idempotent repo-local bootstrap manifest at
  `./.data/engines/<adapter-id>/bootstrap.json`
- adapter modules load durable runtime context from the protobuf request, configure
  `adapters.model_cache` from that same request before calling `get_model_path`, load model weights,
  and perform real inference over a prebuilt host wheel. The runtime worker invokes the real engine
  for the selected binding — the Python adapter transform over a prebuilt host wheel for
  python-stdio bindings, or the real native runner binary resolved from a typed HostConfig data root
  or Linux image-owned `/opt/infernix/engines/<adapterId>/` root for native-process-runner bindings —
  fetches model weights lazily from the infernix-models MinIO bucket via
  `adapters.model_cache.get_model_path`, and publishes a per-family real result: inline text for the
  LLM and speech families, and a typed object reference into the infernix-demo-objects MinIO bucket
  for the source-separation, audio-to-MIDI, music-transcription, image, video, audio-generation, and
  OMR artifact families. The shared `run_context_adapter` boundary is unchanged; an artifact-adapter
  seam returns an object reference for the non-text families rather than acting as a raw stdin echo
  path.
- Current Linux native roots are smoke wrappers produced by `infernix internal
  materialize-linux-native-engines`; Wave I replaces them with real native payloads before the
  real-output cohort gate.

Adapters do not open network sockets and do not subscribe to the topic transport themselves; the
Haskell worker owns those boundaries and treats the adapter as a pure request-to-response process.
For the artifact families the adapter returns a typed object reference for the generated bytes,
which the worker resolves against the always-on infernix-demo-objects MinIO bucket
(see [../engineering/object_storage.md](../engineering/object_storage.md)).

## Cross-References

- [purescript_policy.md](purescript_policy.md)
- [haskell_style.md](haskell_style.md)
- [testing_strategy.md](testing_strategy.md)
- [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md)
- [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)
