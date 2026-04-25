# Python Policy

**Status**: Authoritative source
**Referenced by**: [../architecture/overview.md](../architecture/overview.md), [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md), [../../DEVELOPMENT_PLAN/00-overview.md](../../DEVELOPMENT_PLAN/00-overview.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define when Python is permitted in this repository, how it is managed, and the
> strict quality gate every adapter container build must run.

## When Python Is Allowed

Python is permitted only under `python/adapters/<engine>/` and only when the bound inference engine
has no non-Python binding.

- the supported Python-native engines (PyTorch, JAX, vLLM, transformers, Diffusers, CTranslate2,
  TensorFlow, ONNX Runtime, basic-pitch, Omnizart, MLX, whisper.cpp Python wrappers, etc.) live
  under `python/adapters/<engine>/`
- each adapter is a thin module that loads its engine, takes a typed protobuf request from stdin,
  runs the engine, and emits a typed protobuf response to stdout
- the Haskell worker (`src/Infernix/Runtime/Worker.hs`) is the single dispatch point that forks a
  Python adapter when the bound engine is Python-native
- no other Python lives in this repository on the supported path; in particular, build helpers,
  lint, chart discovery, image publishing, demo-config parsing, doc validation, and the demo HTTP
  host are all Haskell

## Toolchain

One repo-root `python/pyproject.toml` (Poetry-managed) declares all Python dependencies needed by
adapters.

- outside the cluster, `poetry install --directory python` materializes `./.venv/` in the repo
  folder; Apple host-native Python flows use that virtual environment
- inside the engine container, Poetry installs system-wide from the same `pyproject.toml` (no
  in-container `.venv` is used)
- adapter container builds copy `python/pyproject.toml` and `python/poetry.lock` and run
  `poetry install --no-root --only main --no-cache` plus the quality gate as build steps; the
  container image build fails on any check failure
- Poetry is not a generic platform prerequisite; `infernix` does not install it during `cluster up`
  or generic operator workflows. It materializes only when an engine-adapter test is exercised
  explicitly (for example `infernix test integration --engine pytorch`)

## Quality Gate

Every adapter container build runs `tools/python_quality.sh`, a small shell script that invokes
the following in sequence and exits non-zero on any failure:

| Check | Command | Strictness |
|-------|---------|------------|
| Type check | `poetry run mypy --strict python/` | strict |
| Format check | `poetry run black --check python/` | check-only (no write) |
| Lint | `poetry run ruff check python/` | strict |

Rules:

- the gate runs as a single build step in every adapter `Dockerfile`; an adapter image cannot
  build successfully if any check fails
- `infernix test lint` runs the same gate against `./.venv/` on the host
- the gate covers the entire `python/` tree, not only the engine being built; this prevents drift
  across adapters
- adapter modules carry inline type annotations on every function and class; `# type: ignore`
  pragmas require an explanatory comment

## Adapter Contract

Each adapter under `python/adapters/<engine>/` honors a small typed protocol:

- read a length-prefixed protobuf `InferenceRequest` from stdin (schema:
  `proto/infernix/runtime/inference.proto`, generated bindings under `tools/generated_proto/`)
- execute the engine
- write a length-prefixed protobuf `InferenceResponse` to stdout
- log errors to stderr; the Haskell worker captures stderr for diagnostics

Adapters do not open network sockets, do not write to MinIO, and do not subscribe to Pulsar
themselves; the Haskell worker owns those boundaries and treats the adapter as a pure
request-to-response process.

## Cross-References

- [purescript_policy.md](purescript_policy.md)
- [haskell_style.md](haskell_style.md)
- [testing_strategy.md](testing_strategy.md)
- [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md)
- [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)
