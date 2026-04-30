# Implementation Boundaries

**Status**: Authoritative source
**Referenced by**: [../development/testing_strategy.md](../development/testing_strategy.md), [../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md](../../DEVELOPMENT_PLAN/phase-4-inference-service-and-durable-runtime.md)

> **Purpose**: Define which repository surfaces are Haskell-owned, Python-owned, chart-owned, or generated-only.

## Executive Summary

- Haskell owns the control plane, cluster lifecycle, route registry, publication logic, runtime
  orchestration, demo API, and all handwritten browser-contract source.
- Python is restricted to the shared adapter project under `python/` and is invoked only through
  the typed protobuf-over-stdio worker boundary.
- Helm and chart assets own Kubernetes manifest rendering and third-party chart wiring, not
  application control flow.
- Generated trees are write-only outputs. They may be rebuilt, deleted, or linted, but they are
  not handwritten source-of-truth locations.

## Current Status

The current worktree follows this split directly: handwritten browser contracts live in
`src/Infernix/Web/Contracts.hs`, repo-owned Python lives only under `python/adapters/`, chart
assets stay under `chart/`, and generated outputs remain untracked.

## Ownership Matrix

| Surface | Owner | Handwritten paths | Generated or derived outputs | Boundary rule |
|---------|-------|-------------------|------------------------------|---------------|
| Control plane, cluster lifecycle, command registry, docs lint, and service runtime | Haskell | `src/Infernix/`, `app/`, `test/` | repo-local state under `./.build/` and `./.data/` | supported operator behavior and validation entrypoints stay Haskell-owned |
| Browser-contract source | Haskell | `src/Infernix/Web/Contracts.hs` | `web/src/Generated/` | handwritten browser-facing types live in Haskell; frontend bindings are emitted output only |
| Python engine adapters | Python | `python/pyproject.toml`, `python/adapters/` | `python/.venv/`, generated protobuf stubs under `tools/generated_proto/` | adapters are the only supported Python runtime surface and are launched only through `poetry run` |
| Kubernetes manifests and third-party chart wiring | Helm or YAML | `chart/templates/`, `chart/Chart.yaml`, `chart/values.yaml` | rendered manifests and generated values material | charts own deployment shape, but not application-domain control flow or repo workflow logic |
| Generated frontend bundle | generated tool output | none | `web/dist/` | built browser assets stay derived and untracked |
| Generated protobuf bindings | generated tool output | none | `tools/generated_proto/` | `.proto` files own the schema; generated bindings do not become handwritten source |

## Type Boundaries

- Browser-visible request or response types originate in handwritten Haskell ADTs and flow into
  PureScript through `infernix internal generate-purs-contracts`.
- Runtime request, result, and worker protocol schemas originate in `proto/infernix/...`; Haskell
  and Python consume generated bindings instead of maintaining parallel handwritten wire types.
- Adapter-local helper types stay inside one adapter module. If a type becomes shared across
  adapters or visible to the control plane, promote it into a Haskell-owned or `.proto`-owned
  contract instead of copying it.
- Generated demo-config material, publication summaries, and route-registry renderings remain
  Haskell-owned even when they are serialized into `.dhall`, JSON, or YAML for downstream
  consumers.
- Put serialization instances and conversion helpers next to the owning domain type whenever
  possible; avoid orphan-style cross-layer instance placement that hides ownership.

## Module-Boundary Doctrine

- `src/Infernix/` modules own orchestration, domain decisions, CLI surfaces, and validation.
- Python adapter modules own engine-specific subprocess behavior only; they do not own routing,
  cluster lifecycle, docs validation, or browser APIs.
- Chart templates own Kubernetes object layout and third-party chart values, but do not become a
  second command or workflow registry.
- Generated directories such as `web/src/Generated/`, `tools/generated_proto/`, and `web/dist/`
  are rebuild targets, not review surfaces for handwritten logic.
- Supported workflows do not introduce repo-owned shell wrappers or duplicate helper scripts when a
  Haskell module already owns the behavior.

## Validation

- `infernix docs check` fails if this governed boundary document loses its required structure or
  drifts from the metadata contract enforced by `src/Infernix/Lint/Docs.hs`.
- `infernix lint files` fails if generated-only artifacts return to tracked source paths.
- `infernix test unit` covers the Haskell-to-Python protobuf-over-stdio worker handshake together
  with generated browser-contract behavior.

## Cross-References

- [build_artifacts.md](build_artifacts.md)
- [portability.md](portability.md)
- [../development/frontend_contracts.md](../development/frontend_contracts.md)
- [../development/python_policy.md](../development/python_policy.md)
