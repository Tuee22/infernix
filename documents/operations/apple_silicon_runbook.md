# Apple Silicon Runbook

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-ha-platform-services-and-edge-routing.md)

> **Purpose**: Describe the supported Apple host-native operator workflow.

## Supported Flow

- build `infernix` with `./cabalw build exe:infernix`
- run `./.build/infernix cluster up`
- use `./.build/infernix kubectl ...` instead of mutating global kubeconfig
- run `./.build/infernix test all`

## Rules

- on the Apple host path, `infernix` detects repo-owned Python manifests, installs missing
  Homebrew `poetry` when those manifests require it, and installs the declared dependencies before
  running the supported command surface
- `./cabalw` is the supported host build wrapper and keeps Cabal output under `./.build/cabal`
- `cluster up` writes `./.build/infernix.kubeconfig`
- supported flows do not mutate `$HOME/.kube/config`
- `cluster up` and `cluster status` keep the publication inventory under `./.data/runtime/publication.json`
- host-native service mode repoints `/api` through the same routed edge entrypoint instead of changing the browser base URL
- when the host bridge is active, the host-native service listens on a bridge port behind the edge and the publication payload reports `apiUpstream.mode = host-daemon-bridge`
- host-native service mode reaches MinIO and Pulsar through that shared edge inventory rather than separate host-only ports
- host-native service mode is not supported as an implicit filesystem-backed daemon; it requires
  the routed MinIO or Pulsar bridge contract or explicit backend overrides, while filesystem-backed
  materialization remains fixture-only for local unit coverage
- host-native service mode uses the same process-isolated engine-worker contract as the
  cluster-resident service while retrieving durable artifacts and engine-specific source-artifact
  manifests through the routed MinIO or Pulsar bridge surfaces, and automated validation uses the
  engine-specific worker runner when no adapter-specific override is configured
- `test integration`, `test e2e`, and `test all` repeat the default validation suites across
  `apple-silicon` and `linux-cpu` when no explicit runtime-mode override is supplied; the same
  commands auto-include `linux-cuda` only when the active control-plane surface satisfies the
  NVIDIA preflight contract

## Cross-References

- [cluster_bootstrap_runbook.md](cluster_bootstrap_runbook.md)
- [../architecture/runtime_modes.md](../architecture/runtime_modes.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
