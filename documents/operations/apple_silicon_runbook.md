# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Current Status

- the intended Apple clean-host contract reduces pre-existing host requirements to Homebrew plus
  ghcup before the binary is built
- Colima is the only supported Docker environment on Apple Silicon
- the current worktree still expects host-installed `kind`, `kubectl`, `helm`, and a `poetry`
  executable when those paths are first exercised; clean-host bootstrap closure is tracked in
  [../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md](../../DEVELOPMENT_PLAN/phase-6-validation-e2e-and-ha-hardening.md)

## Supported Flow

- build both Haskell binaries with
  `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
- run `./.build/infernix --runtime-mode apple-silicon cluster up`
- use `./.build/infernix --runtime-mode apple-silicon kubectl ...` instead of mutating global
  kubeconfig
- run `./.build/infernix --runtime-mode apple-silicon test all`

When the demo UI is needed as a host-side equivalent of the cluster `infernix-demo` workload:

- run `./.build/infernix-demo serve --dhall ./.build/infernix-demo-apple-silicon.dhall --port 9180`
  in a separate terminal; the routed surface forwards `/`, `/api`, `/api/publication`,
  `/api/cache`, and `/objects/<key>` to that host bridge

## Rules

- the Apple host operator workflow has no generic Python prerequisite; Poetry and a repo-local
  adapter virtual environment materialize only when an engine-adapter validation or setup path is
  exercised explicitly
- supported Apple host workflows do not use repo-owned scripts; the direct `cabal` command keeps
  Cabal output under `./.build/cabal` and materializes `./.build/infernix` and
  `./.build/infernix-demo`
- `cluster up` writes `./.build/infernix.kubeconfig`
- supported flows do not mutate `$HOME/.kube/config`
- when the demo surface is enabled and `infernix-demo serve` runs host-native, the routed `/api`
  reaches the Apple host bridge while the browser stays on the same base URL
- the host-native daemon uses the same Haskell worker contract as the cluster-resident daemon and
  forks Python adapters from `python/adapters/` only when the bound engine is Python-native
- the intended Apple host bootstrap uses Homebrew-managed Colima, Docker CLI, `kind`, `kubectl`,
  `helm`, Node.js, and related operator tools rather than a broader manual prerequisite list
- `infernix service` runs `ensureAppleSiliconRuntimeReady` before the daemon loop. That flow
  ensures the shared `python/` project is installed, creates repo-local engine roots under
  `./.data/engines/`, and invokes each `poetry run setup-*` entrypoint for the active mode's
  Python-native engine bindings
- the intended Apple bootstrap may also install Poetry through the host's built-in Python when the
  `poetry` executable is absent
- the current `setup-*` entrypoints are idempotent preflight hooks, not the full Homebrew or
  Poetry-bootstrap closure described above

## Cross-References

- [cluster_bootstrap_runbook.md](cluster_bootstrap_runbook.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
