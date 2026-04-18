# Infernix Protobuf Contracts

This directory contains the repo-owned protobuf schema scaffold for the final durable runtime and
transport contracts.

Current schema inventory:

- `infernix/runtime/inference.proto` - generated catalog, inference request, result, and error payloads
- `infernix/manifest/runtime_manifest.proto` - durable manifest and cache-materialization metadata
- `infernix/api/inference_service.proto` - service RPC boundary mapped onto the manual inference API

The current compatibility implementation still uses JSON over the local API and filesystem-backed
durability, but these schemas now replace the empty placeholder and define the canonical future
payload names.
