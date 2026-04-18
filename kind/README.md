# Kind Cluster Scaffold

This directory contains the mode-specific Kind config scaffolds that the final `cluster up`
implementation will reconcile.

- `cluster-apple-silicon.yaml` captures the Apple host-compatible Kind shape
- `cluster-linux-cpu.yaml` captures the CPU validation shape
- `cluster-linux-cuda.yaml` carries the NVIDIA runtime patches and node labels required by the
  planned GPU-backed Kind lane

The current Haskell implementation still uses a compatibility cluster layer, so these files are not
yet applied automatically. They are the repo-owned source for the target Kind topology instead of a
placeholder directory.
