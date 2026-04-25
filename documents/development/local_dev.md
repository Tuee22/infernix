# Local Development

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Describe the supported local operator workflows for Apple host-native and
> containerized Linux execution.

## Apple Host-Native Flow

```bash
cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo
./.build/infernix --runtime-mode apple-silicon cluster up
./.build/infernix --runtime-mode apple-silicon cluster status
./.build/infernix --runtime-mode apple-silicon test all
./.build/infernix cluster down
```

When the demo UI is needed (host-side equivalent of the `infernix-demo` cluster workload):

```bash
./.build/infernix-demo serve --dhall ./.build/infernix-demo-apple-silicon.dhall --port 9180
```

## Containerized Linux Flow

```bash
docker compose build infernix
docker compose run --rm infernix infernix --runtime-mode linux-cpu cluster up
docker compose run --rm infernix infernix --runtime-mode linux-cpu cluster status
docker compose run --rm infernix infernix --runtime-mode linux-cpu test all
docker compose run --rm infernix infernix cluster down
```

## Engine Adapter Testing

When exercising a Python-native engine adapter (and only then), Poetry materializes a local virtual
environment in the repo:

```bash
poetry install --directory python
./.build/infernix --runtime-mode apple-silicon test integration --engine pytorch
```

`infernix` does not install Poetry as a generic platform prerequisite; it must be available on the
host before the adapter test runs.

## Rules

- runtime mode is selected independently of control-plane execution context
- supported workflows do not use repo-owned scripts or wrapper layers
- the operator workflow has no Python prerequisite; Poetry and `./.venv/` materialize only when an
  engine-adapter test is exercised explicitly (see [python_policy.md](python_policy.md))
- Apple host builds call `cabal` directly with `--builddir=.build/cabal` and
  `--installdir=./.build`, which keeps Cabal output under `./.build/` and materializes
  `./.build/infernix` and `./.build/infernix-demo`
- Apple mode uses the repo-local kubeconfig under `./.build/`
- container mode keeps build output under `/opt/build/infernix`
- container mode supports launching from the repo root or nested working directories inside the
  mounted workspace
- `docker compose up` and `docker compose exec` are not supported operator workflows

## Cross-References

- [haskell_style.md](haskell_style.md)
- [python_policy.md](python_policy.md)
- [purescript_policy.md](purescript_policy.md)
- [testing_strategy.md](testing_strategy.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
