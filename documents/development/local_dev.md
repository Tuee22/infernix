# Local Development

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Describe the supported local operator workflows for Apple host-native and
> containerized Linux execution.

## Apple Host-Native Flow

```bash
./cabalw build exe:infernix
./.build/infernix --runtime-mode apple-silicon cluster up
./.build/infernix --runtime-mode apple-silicon cluster status
./.build/infernix --runtime-mode apple-silicon test all
./.build/infernix cluster down
```

## Containerized Linux Flow

```bash
docker compose build infernix
docker compose run --rm infernix infernix --runtime-mode linux-cpu cluster up
docker compose run --rm infernix infernix --runtime-mode linux-cpu cluster status
docker compose run --rm infernix infernix --runtime-mode linux-cpu test all
docker compose run --rm infernix infernix cluster down
```

## Rules

- runtime mode is selected independently of control-plane execution context
- on the Apple host path, `infernix` now detects repo-owned Python manifests, installs missing
  Homebrew `poetry` when those manifests require it, and installs the declared dependencies on the
  supported path
- `./cabalw` is the supported Apple host build wrapper and injects the repo-owned Cabal build root
  unless the caller already passed `--builddir`
- Apple mode uses the repo-local kubeconfig under `./.build/`
- container mode keeps build output under `/opt/build/infernix`
- container mode supports launching from the repo root or nested working directories inside the mounted workspace
- `docker compose up` and `docker compose exec` are not supported operator workflows

## Cross-References

- [haskell_style.md](haskell_style.md)
- [testing_strategy.md](testing_strategy.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
