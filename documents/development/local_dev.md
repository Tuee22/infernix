# Local Development

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Describe the supported local operator workflows for Apple host-native and
> containerized Linux execution.

## Current Status

- Apple clean-host support reduces pre-existing host requirements to Homebrew plus ghcup, treats
  Colima as the only supported Docker environment, and lets `infernix` reconcile the remaining
  supported Homebrew-managed tools plus Poetry bootstrap on demand
- after `./.build/infernix` exists on Apple Silicon, supported host-native commands reconcile
  Colima, Docker CLI, `kind`, `kubectl`, `helm`, Node.js, and Poetry through the supported package
  manager or built-in Python path when the active flow first needs them
- `linux-cpu` host prerequisites stop at Docker Engine plus the Docker Compose plugin, and
  `linux-gpu` adds only the supported NVIDIA driver and container-toolkit setup

## Apple Host-Native Flow

```bash
cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo
./.build/infernix internal materialize-substrate apple-silicon
./.build/infernix cluster up
./.build/infernix cluster status
./.build/infernix test all
./.build/infernix cluster down
```

The first supported Apple host-native command that needs Docker, Kubernetes tooling, Node.js, or
Poetry reconciles those prerequisites automatically.

## Containerized Linux Flow

```bash
docker compose build infernix
docker compose run --rm infernix infernix cluster up
docker compose run --rm infernix infernix cluster status
docker compose run --rm infernix infernix test all
docker compose run --rm infernix infernix cluster down
```

For the CUDA lane, build the shared substrate image with the CUDA base image and run it with
`--gpus all`.

## Engine Adapter Testing

When exercising a Python-native engine adapter, Poetry materializes a local environment only for
the shared adapter project:

```bash
./.build/infernix test unit
```

## Rules

- the active substrate comes from the generated `.dhall` beside the binary rather than a CLI flag
- supported staging is explicit: Apple host workflows run
  `./.build/infernix internal materialize-substrate apple-silicon` after `cabal install`, and the
  Linux image build runs `infernix internal materialize-substrate <substrate>` while baking
  `/opt/build/infernix/infernix-substrate.dhall`
- supported workflows do not use repo-owned scripts or wrapper layers
- the target Apple host workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter test or setup path is
  exercised, and `infernix` bootstraps a user-local `poetry` executable through the host's
  built-in Python when that path first needs it
- Colima is the only supported Docker environment on Apple Silicon
- Apple host builds call `cabal` directly with `--builddir=.build/cabal` and
  `--installdir=./.build`, which keeps Cabal output under `./.build/` and materializes
  `./.build/infernix` and `./.build/infernix-demo`
- Apple mode uses the repo-local kubeconfig under `./.build/`
- container mode keeps build output under `/opt/build/infernix`
- container mode runs against a baked image snapshot and bind-mounts only `./.data/` together
  with the Docker socket and the named build caches
- when `demo_ui` is enabled, the demo surface stays cluster-resident on Apple and Linux alike
- `docker compose up` and `docker compose exec` are not supported operator workflows
- assistant-facing repository workflow rules live in [assistant_workflow.md](assistant_workflow.md)

## Cross-References

- [haskell_style.md](haskell_style.md)
- [assistant_workflow.md](assistant_workflow.md)
- [python_policy.md](python_policy.md)
- [purescript_policy.md](purescript_policy.md)
- [testing_strategy.md](testing_strategy.md)
- [../operations/apple_silicon_runbook.md](../operations/apple_silicon_runbook.md)
