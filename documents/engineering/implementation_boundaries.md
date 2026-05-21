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
- Supported repo-owned shell is limited to the `bootstrap/*.sh` stage-0 host bootstrap surface;
  it may reconcile prerequisites, build or enter the supported launcher, and invoke the supported
  command surface, but it does not become a second lifecycle, Kind, Kubernetes manifest, image
  publication, validation, or teardown implementation.

## Application Library Boundary (Planned, Phase 7)

When the durable-context demo application lands, the new modules split into three groups so
the durable-context primitives become reusable by any future SPA-like application built on the
inference platform.

- **Shared library (product-agnostic).** Concept-named modules under the `Infernix.` namespace,
  parameterized in topic namespace, bucket name, and JWT issuer/audience. Free of HTTP/WS
  specifics and SPA assumptions:
  - `Infernix.Conversation.{Event,Reducer,Idempotency,Hash,Topic}`
  - `Infernix.Topic.{Metadata,Drafts}`
  - `Infernix.Dispatch.SingleFlight`
  - `Infernix.Objects.{Layout,Presigned}`
  - `Infernix.Auth.Jwt`
- **Demo binary (product-specific glue).** Modules under `Infernix.Demo.*` carry the
  Keycloak-realm-specific JWT wiring, the WS upgrade, the HTTP route handlers, the WS envelope
  tagged-sum wire schema, and first-run bootstrap. May import any shared module.
- **Cluster daemon (engine path).** Modules under `Infernix.Runtime.*` import
  `Infernix.Conversation.Reducer` and `Infernix.Conversation.Hash` for engine-side KV-cache
  consistency only. They must not import `Infernix.Demo.*`, `Infernix.Objects.Presigned`,
  `Infernix.Auth.Jwt`, or any WebSocket module.

The dependency arrows are strict: shared library has no upward dependencies; demo binary and
cluster daemon both depend on shared library; demo binary and cluster daemon never depend on
each other.

Adding a second similar app (e.g., a hypothetical `infernix-notebook`) follows the same
pattern: a new `Infernix.<AppName>.*` namespace reuses every shared module verbatim and the
new app writes only its renderer plus the WS envelope variants it needs. The reusable surface
area is roughly 80% of the new code by line count.

See [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
for the product-agnostic design that motivates this split, and
[../architecture/demo_app_design.md](../architecture/demo_app_design.md) for the concrete
demo binding.

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
- [../architecture/durable_context_design.md](../architecture/durable_context_design.md)
- [../architecture/demo_app_design.md](../architecture/demo_app_design.md)
