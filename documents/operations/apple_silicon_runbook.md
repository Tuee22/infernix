# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Supported Flow

- build both Haskell binaries with
  `cabal --builddir=.build/cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo`
- run `./.build/infernix cluster up`
- use `./.build/infernix kubectl ...` instead of mutating global kubeconfig
- run `./.build/infernix test all`

When the demo UI is needed (host-side equivalent of the cluster `infernix-demo` workload):

- run `./.build/infernix-demo serve --dhall ./.build/infernix-demo-apple-silicon.dhall --port 9180`
  in a separate terminal; the routed edge proxy forwards `/`, `/api`, `/api/publication`,
  `/api/cache`, and `/objects/<key>` to that host bridge

## Rules

- the Apple host operator workflow has no Python prerequisite; `infernix` does not install Poetry
  as a generic platform prerequisite. Poetry and a repo-local adapter virtual environment materialize only when an
  engine-adapter validation path is exercised explicitly (for example
  `./.build/infernix test unit` or `./.build/infernix test all`); see
  [../development/python_policy.md](../development/python_policy.md)
- supported Apple host workflows do not use repo-owned scripts; the direct `cabal` command keeps
  Cabal output under `./.build/cabal` and materializes `./.build/infernix` and
  `./.build/infernix-demo`
- `cluster up` writes `./.build/infernix.kubeconfig`
- supported flows do not mutate `$HOME/.kube/config`
- `cluster up` and `cluster status` keep the publication inventory under
  `./.data/runtime/publication.json`
- when the demo surface is enabled and `infernix-demo serve` runs host-native, the routed `/api`
  reaches the Apple host bridge while the browser stays on the same edge base URL; the publication
  payload reports `apiUpstream.mode = host-demo-bridge`
- production deployments leave the `.dhall` `demo_ui` flag off; in that case the cluster has no
  `infernix-demo` workload and `/`, `/api`, `/api/publication`, `/api/cache`, and `/objects/` are
  absent from the edge route inventory
- host-native daemon execution reaches MinIO and Pulsar through the shared edge inventory rather
  than separate host-only ports
- the host-native daemon uses the same Haskell worker contract as the cluster-resident daemon and
  forks Python adapters from `python/adapters/<engine>/` only when the bound engine is
  Python-native; those adapters now speak typed protobuf-over-stdio and the remaining work is real
  engine implementation rather than host-bridge ownership
- adapter-specific `INFERNIX_ENGINE_COMMAND_*` overrides can direct the host-native or
  cluster-resident worker path at installed host commands while preserving the same demo `/api`
  contract and durable artifact-selection semantics
- `test integration`, `test e2e`, and `test all` repeat the default validation suites across
  `apple-silicon` and `linux-cpu` when no explicit runtime-mode override is supplied; the same
  commands auto-include `linux-cuda` only when the active control-plane surface satisfies the
  NVIDIA preflight contract

## Cross-References

- [cluster_bootstrap_runbook.md](cluster_bootstrap_runbook.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
