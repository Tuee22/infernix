# Implementation Boundaries

**Status**: Authoritative source
**Referenced by**: [../development/testing_strategy.md](../development/testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define which repository surfaces are Haskell-owned, Python-owned, chart-owned, or generated-only.

## Haskell-Owned Surfaces

- `src/Infernix/` owns the control plane, cluster lifecycle, route registry, command registry,
  service runtime, demo API, and validation entrypoints
- `src/Infernix/Web/Contracts.hs` is the handwritten browser-contract source of truth
- `infernix` and `infernix-demo` are the only supported repo-owned executables

## Python-Owned Surfaces

- Python is allowed only inside the shared adapter project rooted at `python/pyproject.toml`
- repo-owned adapter modules live only under `python/adapters/`
- the Haskell worker invokes adapters only through `poetry run <entrypoint>`
- Python does not own the control plane, cluster lifecycle, docs validator, HTTP API host, or chart tooling

## Chart-Owned Surfaces

- `chart/templates/` owns Kubernetes manifests for repo-owned workloads, Gateway resources,
  ConfigMaps, and third-party chart dependencies
- `chart/values.yaml` holds stable structural defaults only
- generated demo-config or publication payloads are reconcile-time or lint-time inputs, not committed defaults

## Generated-Only Surfaces

- `web/src/Generated/` is reserved for generated PureScript contract output
- `tools/generated_proto/`, `web/dist/`, `web/spago.lock`, Poetry lockfiles, `*.pyc`, and
  `__pycache__/` are generated artifacts and stay out of tracked source
- `src/Generated/` carries no handwritten Haskell source on the supported path

## Validation Rules

- `infernix lint docs` fails when governed docs drift from these ownership boundaries
- `infernix lint files` fails when tracked generated artifacts return
- `infernix test unit` covers the Haskell-to-Python protobuf-over-stdio worker handshake

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [portability.md](portability.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/python_policy.md](../development/python_policy.md)
