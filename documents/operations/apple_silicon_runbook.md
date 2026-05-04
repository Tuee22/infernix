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

- build both Haskell binaries with
  `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
- stage the active substrate file with
  `./.build/infernix internal materialize-substrate apple-silicon`
- run `./.build/infernix cluster up`
- use `./.build/infernix kubectl ...` instead of mutating global
  kubeconfig
- run `./.build/infernix test all`

The first supported host-native command that needs Docker, Kubernetes tooling, Node.js, or Poetry
reconciles those prerequisites automatically.

## Rules

- the Apple host operator workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter validation or setup path is
  exercised explicitly
- supported Apple host workflows do not use repo-owned scripts; the direct `cabal` command keeps
  Cabal output under `./.build/cabal` and materializes `./.build/infernix` and
  `./.build/infernix-demo`
- supported Apple host workflows stage `./.build/infernix-substrate.dhall` explicitly through
  `./.build/infernix internal materialize-substrate apple-silicon`; add `--demo-ui false` when
  preparing a demo-off config
- `cluster up` writes `./.build/infernix.kubeconfig`
- supported flows do not mutate `$HOME/.kube/config`
- when the demo surface is enabled, the browser stays on the clustered routed surface; the direct
  `infernix service` lane remains host-native while routed manual inference executes inside the
  clustered `infernix-demo` workload in the current code path
- `/api/publication` still reports the direct Apple service lane as
  `daemonLocation: control-plane-host` while the routed demo API remains
  `apiUpstream.mode: cluster-demo`
- the host-native daemon uses the same Haskell worker contract as the cluster-resident daemon and
  forks Python adapters from `python/adapters/` only when the bound engine is Python-native
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
