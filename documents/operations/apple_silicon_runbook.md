# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Current Status

- the supported Apple clean-host contract reduces pre-existing host requirements to Homebrew plus
  ghcup before the binary is built
- Colima is the only supported Docker environment on Apple Silicon
- after `./.build/infernix` exists, supported commands reconcile Homebrew-managed Colima, Docker
  CLI, `kind`, `kubectl`, `helm`, and Node.js on demand, and adapter setup or validation paths
  bootstrap Poetry through the host's built-in Python when it is absent

## Supported Flow

- run `./bootstrap/apple-silicon.sh up`
- run `./bootstrap/apple-silicon.sh status`
- run `./bootstrap/apple-silicon.sh test`
- use `./.build/infernix kubectl ...` instead of mutating global
  kubeconfig
- run `./bootstrap/apple-silicon.sh down` when tearing the cluster down

The first supported host-native command that needs Docker, Kubernetes tooling, Node.js, or Poetry
reconciles those prerequisites automatically.

Direct reference path:

- build both Haskell binaries with
  `cabal install --installdir=./.build --install-method=copy --overwrite-policy=always all:exes`
- stage the active substrate file with
  `./.build/infernix internal materialize-substrate apple-silicon`
- run `./.build/infernix cluster up`
- run `./.build/infernix test all`

## Rules

- the Apple host operator workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter validation or setup path is
  exercised explicitly
- supported Apple host shell is limited to `./bootstrap/apple-silicon.sh`; the direct `cabal`
  command lets cabal use its natural `dist-newstyle` builddir at the project root and only
  overrides `--installdir=./.build` so the materialized `./.build/infernix` and
  `./.build/infernix-demo` binaries land where the supported CLI surface expects them
- supported Apple host workflows stage `./.build/infernix-substrate.dhall` explicitly through
  `./.build/infernix internal materialize-substrate apple-silicon`; add `--demo-ui false` when
  preparing a demo-off config
- `cluster up` writes `./.build/infernix.kubeconfig`
- supported flows do not mutate `$HOME/.kube/config`
- the Apple host-native path describes where the Haskell build and control-plane commands run;
  `cluster up` still deploys `infernix-service` in-cluster and adds `infernix-demo` when
  `demo_ui` is enabled
- on `apple-silicon`, those cluster-resident repo workloads currently run from the
  `infernix-linux-cpu:local` image family while reading the staged `apple-silicon` substrate file
- `/api/publication` on Apple currently still serializes
  `daemonLocation: control-plane-host` while the routed demo API remains
  `apiUpstream.mode: cluster-demo`; treat that field as current publication output rather than
  actual service placement
- the direct `infernix service` host run uses the same Haskell worker contract as the
  cluster-resident daemon and forks Python adapters from `python/adapters/` only when the bound
  engine is Python-native
- the Apple host bootstrap uses Homebrew-managed Colima, Docker CLI, `kind`, `kubectl`, `helm`,
  Node.js, and related operator tools rather than a broader manual prerequisite list
- `infernix service` runs `ensureAppleSiliconRuntimeReady` before the daemon loop. That flow
  ensures the shared `python/` project is installed, creates repo-local engine roots under
  `./.data/engines/`, and invokes each `poetry run setup-*` entrypoint for the active mode's
  Python-native engine bindings
- the Apple bootstrap also installs Poetry through the host's built-in Python when the `poetry`
  executable is absent, after which the shared `python/.venv/` still materializes only on demand
- the current `setup-*` entrypoints remain idempotent preflight hooks layered on top of that
  prerequisite bootstrap and shared-project install flow

## Cross-References

- [cluster_bootstrap_runbook.md](cluster_bootstrap_runbook.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
