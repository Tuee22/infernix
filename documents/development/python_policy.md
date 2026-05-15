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
- on the intended Apple clean-host path, `infernix` may reconcile Homebrew `python@3.12` at
  `/opt/homebrew/opt/python@3.12/bin/python3.12` and then bootstrap the `poetry` executable when
  adapter setup or validation first needs it
- outside the cluster, `poetry install --directory python` materializes the repo-local
  `python/.venv/` environment for adapter validation on the Apple host path
- Linux substrate image builds run `poetry install --directory python` during the image build and
  then execute adapters from the shared `python/` project root through `poetry run ...`
- Poetry is not a generic platform prerequisite; it materializes only when an adapter validation or
  setup path is exercised explicitly

Current status:

- on the Apple host-native path, `infernix` reconciles Homebrew `python@3.12` at
  `/opt/homebrew/opt/python@3.12/bin/python3.12` and bootstraps a user-local `poetry` executable
  when adapter setup or validation first needs it
- once `poetry` exists, the shared project still materializes `python/.venv/` only on demand

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
- the worker request includes repo-local durable metadata paths for the selected model's artifact
  bundle, source-artifact manifest, cache manifest, and engine install root
- the shared project exposes one Poetry console script per adapter together with matching
  `setup-*` entrypoints
- each `setup-*` entrypoint writes an idempotent repo-local bootstrap manifest at
  `./.data/engines/<adapter-id>/bootstrap.json`
- adapter modules load durable runtime context from those bundle or manifest paths and emit
  deterministic engine-family-specific output through the final protobuf-over-stdio worker
  contract rather than acting as a raw stdin echo path

Adapters do not open network sockets, do not write object-store state, and do not subscribe to the
topic transport themselves; the Haskell worker owns those boundaries and treats the adapter as a
pure request-to-response process.

## Cross-References

- [purescript_policy.md](purescript_policy.md)
- [haskell_style.md](haskell_style.md)
- [testing_strategy.md](testing_strategy.md)
- [../engineering/model_lifecycle.md](../engineering/model_lifecycle.md)
- [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)
