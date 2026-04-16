# Build Artifacts

**Status**: Authoritative source
**Referenced by**: [../development/local_dev.md](../development/local_dev.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Define where generated artifacts live and keep them out of tracked source paths.

## Build Roots

- Apple host-native Cabal output lives under `./.build/`
- containerized builds use `/opt/build/infernix`
- generated Dhall config and repo-local kubeconfig live in the active build root

## Rules

- supported host-side Cabal usage does not require a per-command `--builddir`
- supported container Cabal usage injects or enforces `--builddir=/opt/build/infernix`
- generated web and Playwright artifacts live under `./.data/` or the active mounted equivalent

## Cross-References

- [docker_policy.md](docker_policy.md)
- [storage_and_state.md](storage_and_state.md)
- [../reference/cli_reference.md](../reference/cli_reference.md)
