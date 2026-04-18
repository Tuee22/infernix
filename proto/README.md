# Infernix Protobuf Contracts

This directory contains the canonical repo-owned protobuf schemas for the durable runtime and
transport contracts.

Current schema inventory:

- `infernix/runtime/inference.proto` - generated catalog, inference request, result, and error payloads
- `infernix/manifest/runtime_manifest.proto` - durable manifest and cache-materialization metadata
- `infernix/api/inference_service.proto` - service RPC boundary mapped onto the manual inference API

Runtime contract:

- the Haskell build generates `proto-lens` bindings from these schemas and uses them as the typed
  runtime boundary
- Python helpers consume the generated modules under `tools/generated_proto/`
- the routed service persists protobuf runtime manifests and results through MinIO-backed flows and
  registers protobuf schemas for request, result, and coordination topics in Pulsar
- `tools/proto_check.py` validates the required schema files, package declarations, and canonical
  symbols
