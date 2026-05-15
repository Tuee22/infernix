# Local Development

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Describe the supported local operator workflows for Apple host-native and
> containerized Linux execution.

## Current Status

- Apple clean-host support reduces pre-existing host requirements to Homebrew plus ghcup, exposes
  `./bootstrap/apple-silicon.sh` as the supported stage-0 entrypoint, treats Colima as the only
  supported Docker environment, and lets `infernix` reconcile the remaining supported
  Homebrew-managed tools plus Poetry bootstrap on demand
- the Apple stage-0 bootstrap now verifies the selected ghcup-managed `ghc` and `cabal`
  executables plus Homebrew `protoc` before direct `cabal install`, so the clean-host first run
  no longer depends on rerunning the same bootstrap command after Cabal is first installed
- after `./.build/infernix` exists on Apple Silicon, supported host-native commands reconcile
  the supported Colima `8 CPU / 16 GiB` profile, Docker CLI, `kind`, `kubectl`, `helm`, Node.js,
  Homebrew `python@3.12` at `/opt/homebrew/opt/python@3.12/bin/python3.12`, and Poetry through the
  supported package-manager or user-local bootstrap path when the active flow first needs them
- `linux-cpu` and `linux-gpu` expose repo-owned `bootstrap/*.sh` entrypoints that keep host
  prerequisites probe-driven and idempotent; the CPU path stops at Docker Engine plus the Docker
  Compose plugin, and the GPU path adds only the supported NVIDIA driver and container-toolkit
  setup

## Apple Host-Native Flow

```bash
./bootstrap/apple-silicon.sh up
./bootstrap/apple-silicon.sh status
./bootstrap/apple-silicon.sh test
./bootstrap/apple-silicon.sh down
```

Direct reference path:

```bash
cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes
./.build/infernix internal materialize-substrate apple-silicon
./.build/infernix cluster up
./.build/infernix cluster status
./.build/infernix test all
./.build/infernix cluster down
```

The first supported Apple host-native command that needs Docker, Kubernetes tooling, Node.js,
Python, or Poetry reconciles those prerequisites automatically.

## Containerized Linux Flow

```bash
./bootstrap/linux-cpu.sh up
./bootstrap/linux-cpu.sh status
./bootstrap/linux-cpu.sh test
./bootstrap/linux-cpu.sh down
```

Direct reference path:

```bash
docker compose build infernix
docker compose run --rm infernix infernix internal materialize-substrate linux-cpu
docker compose run --rm infernix infernix cluster up
docker compose run --rm infernix infernix cluster status
docker compose run --rm infernix infernix test all
docker compose run --rm infernix infernix cluster down
```

For `linux-gpu`, use `./bootstrap/linux-gpu.sh ...` as the supported entrypoint. The underlying
reference path exports `INFERNIX_COMPOSE_IMAGE=infernix-linux-gpu:local`,
`INFERNIX_COMPOSE_SUBSTRATE=linux-gpu`, and
`INFERNIX_COMPOSE_BASE_IMAGE=nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04` before the same
`docker compose run --rm infernix infernix ...` surface, including
`docker compose run --rm infernix infernix internal materialize-substrate linux-gpu` before
cluster lifecycle or validation commands. If the host does not already pass `nvidia-smi -L`, the
supported bootstrap installs the recommended Ubuntu compute driver, stops, and instructs the
operator to reboot before rerunning the same command.

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
  Linux outer-container path runs
  `docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode>` to
  write `./.build/outer-container/build/infernix-substrate.dhall` on the host through the
  bind-mounted build tree before supported cluster lifecycle or validation commands start
- supported repo-owned shell is limited to the `bootstrap/*.sh` stage-0 entrypoints; they prepare
  the host and then hand off to the direct `cabal`, `docker compose`, or `infernix` command
  surface; on Linux they also restage the active substrate file idempotently before supported
  lifecycle and test commands
- supported stage-0 bootstrap entrypoints are restartable host prerequisite reconcilers: they
  continue in the current process only after they can verify a usable executable for any tool they
  just installed or selected, and they stop at explicit new-shell or reboot boundaries so the
  operator reruns the same bootstrap command instead of skipping ahead to a later direct command
- the target Apple host workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter test or setup path is
  exercised, and `infernix` reconciles Homebrew `python@3.12` at
  `/opt/homebrew/opt/python@3.12/bin/python3.12` plus a user-local `poetry` executable when that
  path first needs it
- Colima is the only supported Docker environment on Apple Silicon
- supported Apple Docker-backed paths reconcile Colima to at least `8 CPU / 16 GiB` before Kind,
  Harbor, MinIO, Pulsar, or Playwright work begins
- on Apple, routed E2E readiness probes use the published host edge on `127.0.0.1:<edge-port>`,
  but the dedicated Playwright container runs on the private Docker `kind` network against the
  Kind control-plane DNS instead of `host.docker.internal`
- on Apple, retained Kind state under `./.data/kind/apple-silicon/` is replayed into and out of
  the worker instead of being bind-mounted, so large retained state can make `up`, `test`, and
  `down` noticeably slower than Linux
- the Apple direct reference build calls `cabal` with `--installdir=./.build` and lets cabal use
  its natural `dist-newstyle` builddir at the project root, which materializes
  `./.build/infernix` and `./.build/infernix-demo`
- Apple mode uses the repo-local kubeconfig under `./.build/`
- container mode keeps the staged substrate file under `./.build/outer-container/build/` on the
  host through the `./.build:/workspace/.build` bind mount, while cabal-home and the cabal
  builddir live at the toolchain's natural in-image locations rather than on any bind-mounted
  host path
- container mode runs against a baked image snapshot and bind-mounts `./.data/`, `./.build/`,
  `./chart/charts/`, and the host `compose.yaml` (read-only) together with the Docker socket; no
  docker-managed named volumes back the outer-container build root, and the substrate image uses
  `tini` as its entrypoint for clean signal handling
- on the Linux outer-container path, `./chart/charts/` is the supported host-persisted cache for
  the top-level Harbor, PostgreSQL, Pulsar, MinIO, and Envoy Gateway chart archives so fresh
  `docker compose run --rm infernix ...` invocations can reuse the same dependency bundle instead
  of reconstructing it from the network every time
- when the outer container shells out to `docker compose run --rm playwright` for routed E2E, it
  forwards `INFERNIX_HOST_REPO_ROOT` so the host docker daemon resolves the playwright service's
  bind mounts against the host repo root
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
