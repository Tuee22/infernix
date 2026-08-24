# In-Cluster Registry

**Status**: Authoritative source
**Referenced by**: [../engineering/edge_routing.md](../engineering/edge_routing.md), [../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md](../../DEVELOPMENT_PLAN/phase-3-platform-services-and-edge-routing.md)

> **Purpose**: Record the supported in-cluster image-registry role in the local platform.

## Rules

- the in-cluster registry is the **single-binary CNCF distribution registry** (`registry:2`): one
  Deployment, one NodePort Service, and one ConfigMap carrying the whole `config.yml`. It has no
  database, no job service, no scanner, no Redis, and no web portal
- there is no Helm sub-chart for the registry. Its three resources are repo-owned templates under
  `chart/templates/registry/`, gated on `registry.enabled`
- the registry is the local image authority for every cluster workload on the real Kind path, and
  is always brought up before the workloads that pull registry-backed refs
- `cluster up` raises the registry in its bootstrap Helm phase and allows the registry plus only
  the storage it needs — MinIO and its bucket-provisioning Job — to pull from public container
  repositories while the registry is not yet serving. That is the whole bootstrap exception
- bootstrap shell scripts never pull or publish registry images directly; the `infernix` binary
  owns registry readiness, mirroring, runtime-image publication, and final rollout sequencing
- the registry serves **anonymously over HTTP**. There is no identity provider, no credential, and
  no `docker login` in the publication path. The NodePort listener is the boundary, the same
  exposure class as the MinIO and Pulsar NodePorts on this local Kind cluster
- `registry:2` creates a repository implicitly on first push, so the `library/` path prefix every
  published ref carries is a naming convention rather than a resource to provision
- blob storage is the MinIO-backed `infernix-registry` bucket. The registry pod is stateless, so a
  rescheduled pod re-reads the blobs it served before
- the rendered `config.yml` sets `storage.redirect.disable: true`. This is mandatory rather than
  tuning: with the default redirect behavior the S3 driver answers blob requests with a 307 to the
  cluster-only MinIO Service name, which the host-scope Docker client pushing to `localhost:30002`
  cannot resolve. Blobs are proxied through the registry itself
- the ConfigMap replaces the image's stock config outright rather than layering onto it. The
  `registry:2` image ships a default `config.yml` declaring the `filesystem` driver, and
  distribution refuses to start with two storage drivers configured
- registry blob storage is rebuildable, not product-durable state. Only after Kind deletion, and
  only while holding a freshly proved `WriterQuiesced` lease, lifecycle cleanup removes the
  rebuildable `infernix-registry` MinIO bucket and its multipart/tmp metadata from the detached
  local retained copy
- image publication runs every docker/skopeo upstream pull, push, and pull-verify through the
  bounded-command kernel (`Infernix.Cluster.Subprocess.runBoundedCommand`) under named
  per-operation `Timeout` budgets, so a hung publish exec times out and advances the retry counter
  instead of stalling `cluster up` indefinitely
- publication treats a tag's presence in the registry's `/v2/<name>/tags/list` response as metadata
  (`registryTagMetadataPresent`) that may shortcut a push, never as proof the blob is servable. The
  distinction is sharper here than it was under the retired component: `registry:2` answers both
  `/v2/` and the tag list out of its own process without reading a byte from S3, so neither is
  evidence about blob retrievability. The terminal "published" state is a `BlobServable` witness
  minted only by a real bounded registry-only `skopeo copy` of the specific ref into a fresh
  private store, so a retained-state second `cluster up` re-pushes when the rebuildable
  `infernix-registry` MinIO backing has not finished rehydrating instead of trusting stale tag
  metadata. This is an instance of the readiness-returns-evidence pattern whose canonical home is
  [Managed State Transitions](../architecture/managed_state_transitions.md)
- after the registry reaches its final rollout shape, `cluster up` preloads the registry-backed
  final image refs onto the Kind worker before the remaining workloads are scaled

## Host Port

The registry's in-cluster Kubernetes NodePort is fixed at `30002` so chart references and the
containerd registry-hosts mappings inside Kind nodes stay deterministic. The Kind `hostPort`
mapping observed from the operator host is selected dynamically by `cluster up`
(`chooseRegistryPort` in `src/Infernix/Cluster.hs`), starting at `30002` and incrementing until an
open port is found, and persisted under `./.data/runtime/registry-port.json`. The chosen port
appears in `cluster status` as `registryPort` alongside `edgePort`. This mirrors Section O of
`DEVELOPMENT_PLAN/development_plan_standards.md` (the edge port pattern). Operators on hosts where
unrelated processes hold port `30002` see `cluster up` select e.g. `30003` automatically; the
binary's registry health probe, the publication path's `docker push` / pull-verify targets, and the
containerd registry-hosts namespace name all follow the chosen port.

Containerd inside each Kind node honors the hosts.toml mappings under
`/etc/containerd/certs.d/<namespace>/hosts.toml` only when `config_path` is enabled in
`/etc/containerd/config.toml`. Kind 0.31 does not emit this by default, so `renderKindConfig`
in `src/Infernix/Cluster.hs` ships a `containerdConfigPatches` block that sets
`[plugins."io.containerd.grpc.v1.cri".registry] config_path = "/etc/containerd/certs.d"`.
The patch is part of the supported Kind config contract; see
[../engineering/docker_policy.md](../engineering/docker_policy.md) for additional context.

## Routed Surfaces

`registry:2` serves the OCI `/v2` API and nothing else — it ships no browser console, so the
operator surface is one API prefix rather than a portal.

<!-- infernix:route-registry:registry:start -->
- `/registry` -> `infernix-registry:5000`; rewrites to upstream `/v2`
<!-- infernix:route-registry:registry:end -->

## Cross-References

- [minio.md](minio.md)
- [postgresql.md](postgresql.md)
- [../engineering/object_storage.md](../engineering/object_storage.md)
- [../reference/web_portal_surface.md](../reference/web_portal_surface.md)
- [Managed State Transitions](../architecture/managed_state_transitions.md)
