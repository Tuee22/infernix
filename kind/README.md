# Kind Cluster Assets

This directory contains the repo-owned Kind topology assets rendered by `infernix cluster up`.

- `cluster-apple-silicon.yaml` defines the Apple host-compatible Kind shape, including the shared
  edge or Harbor or MinIO or Pulsar port mappings and the registry-host mount under
  `./.build/kind/registry`
- `cluster-linux-cpu.yaml` defines the CPU validation topology with the same routed port and
  registry-host contract
- `cluster-linux-cuda.yaml` adds the NVIDIA container runtime patches and GPU node labels required
  by the supported `linux-cuda` lane

`infernix cluster up` selects the active runtime mode, renders the corresponding asset, and
reconciles the real Kind cluster from that source.
