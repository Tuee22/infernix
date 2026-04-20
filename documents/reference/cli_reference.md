# CLI Reference

**Status**: Authoritative source
**Referenced by**: [cli_surface.md](cli_surface.md), [../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md](../../DEVELOPMENT_PLAN/phase-1-repository-and-control-plane-foundation.md)

> **Purpose**: Record the supported `infernix` command surface and behavioral contract.

## Commands

- `infernix [--runtime-mode MODE] service`
- `infernix [--runtime-mode MODE] cluster up`
- `infernix [--runtime-mode MODE] cluster down`
- `infernix [--runtime-mode MODE] cluster status`
- `infernix [--runtime-mode MODE] cache status`
- `infernix [--runtime-mode MODE] cache evict [--model MODEL_ID]`
- `infernix [--runtime-mode MODE] cache rebuild [--model MODEL_ID]`
- `infernix kubectl ...`
- `infernix test lint`
- `infernix test unit`
- `infernix [--runtime-mode MODE] test integration`
- `infernix [--runtime-mode MODE] test e2e`
- `infernix [--runtime-mode MODE] test all`
- `infernix docs check`

## Rules

- `cluster up`, `cluster down`, `cluster status`, `test ...`, and `docs check` are declarative CLI entrypoints
- `cluster status` is read-only and reports the active publication details together with route inventory and state paths
- `infernix service` keeps the routed `/api` entrypoint stable while it switches between the cluster-resident service and the Apple host bridge on the supported host-native path
- `infernix service` requires the routed MinIO or Pulsar durable-backend contract or explicit backend environment overrides; implicit filesystem-backed service fallback is not a supported operator mode
- `infernix cache status` reports the manifest-backed cache inventory for the active runtime mode, and `cache evict` or `cache rebuild` only affect derived cache state
- `infernix kubectl ...` wraps upstream `kubectl` and injects the repo-local kubeconfig
- `cluster up` forwards any `INFERNIX_ENGINE_COMMAND_*` environment variables into the service deployment so adapter-specific engine command prefixes can be configured on the cluster path without rebuilding the image
- on the Linux outer-container cluster path, `cluster up`, `cluster status`, `kubectl`, and routed
  browser checks keep host-published Kind and edge ports on `127.0.0.1` while reaching Kubernetes
  through the private Docker `kind` network and the internal kubeconfig
- `infernix test lint` runs the repo-owned lint, docs, platform-asset, Helm dependency or lint or render or claim-discovery, `.proto`, `ormolu`, `hlint`, `cabal format`, and strict compiler-warning checks
- `infernix test e2e` launches Playwright from the same web image that serves `/`; on the host-native final-substrate path that image is the Harbor-published runtime image across `apple-silicon`, `linux-cpu`, and `linux-cuda`
- `infernix test integration`, `infernix test e2e`, and `infernix test all` honor `--runtime-mode` when supplied; they exercise Apple and Linux CPU by default when no explicit runtime-mode override is supplied and auto-include Linux CUDA when the current host passes the NVIDIA preflight contract on both the Apple host-native and Linux outer-container control-plane surfaces
- `infernix --runtime-mode linux-cuda cluster up`, `test integration`, and `test e2e` fail fast with a host-preflight error when the NVIDIA runtime prerequisites are absent
- `--runtime-mode` accepts `apple-silicon`, `linux-cpu`, or `linux-cuda`

## Cross-References

- [cli_surface.md](cli_surface.md)
- [api_surface.md](api_surface.md)
- [../development/local_dev.md](../development/local_dev.md)
