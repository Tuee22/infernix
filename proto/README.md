# Infernix Protobuf Contracts

This directory contains the canonical repo-owned protobuf schemas for the durable runtime and
transport contracts.

Current schema inventory:

- `infernix/runtime/inference.proto` - generated catalog, inference request, result, and error payloads
- `infernix/manifest/runtime_manifest.proto` - durable manifest and cache-materialization metadata

Runtime contract:

- the Haskell build consumes the four byte-exact `proto-lens-protoc` outputs below `src/Proto/` as
  the typed runtime boundary; a normal build does not run `protoc` or a generator plugin
- Python helpers consume the generated modules under `tools/generated_proto/`
- the routed service persists protobuf runtime manifests and results through MinIO-backed flows and
  registers protobuf schemas for request, result, and coordination topics in Pulsar
- `proto/haskell-bindings.sha256` inventories exactly these two canonical inputs and the four
  tracked Haskell generator outputs; `infernix lint proto` validates schema/package/symbol shape,
  the exact regular-file inventory below `src/Proto/`, and all six hashes without spawning a
  compiler
- the Linux launcher image build owns regeneration proof: pinned `libprotoc 34.1` plus
  a Docker-only bounded install of `proto-lens-protoc 0.9.0.1` generate into a temporary tree and
  byte-compare all four modules. The plugin is linked with a 1024 MiB default heap and accepts the
  fixed `GHCRTS=-M1024M` regeneration environment; no ordinary Linux or Darwin Cabal component
  depends on it. Darwin consumes and hashes the checked-in snapshot without a generator prerequisite
