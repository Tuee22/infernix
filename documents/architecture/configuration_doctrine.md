# Configuration Doctrine

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md), [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md), [../development/no_env_vars.md](../development/no_env_vars.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define the supported configuration substrate — three typed `.dhall` files plus a
> file-based secret convention — and the no-env-var, absolute-path discipline that surrounds it.

## TL;DR

- Every runtime setting is read from one of three typed `.dhall` files:
  `dhall/InfernixHost.dhall` (host tool paths, native host architecture, and filesystem conventions),
  `dhall/InfernixCluster.dhall` (in-cluster wiring),
  `dhall/InfernixSecrets.dhall` (paths to secret files, never values).
- The `dhall` Haskell library is the only Dhall reader. There is no `dhall-to-json` bridge.
- Every external command the project ever invokes is named in `InfernixHost.dhall` by absolute
  path; no `proc "<bare-name>"` in Haskell, no bare-name invocations in shell.
- No Haskell module calls `lookupEnv` / `getEnv` / `getEnvironment` / `setEnv` / `unsetEnv`.
- No `chart/templates/deployment-*.yaml` carries an `env:` block; pods mount the cluster Dhall
  ConfigMap + the cluster Secret instead.
- `compose.yaml` carries exactly two bind mounts (`./.data` and `/var/run/docker.sock`) and no
  `environment:` block, no `build.args:` block, no `playwright` sidecar service. Its only
  interpolation surface is the one-shot launcher image selector used to keep CPU and GPU
  substrate images separate without adding CUDA baggage to CPU hosts.

## Why

The codebase previously accumulated 87 distinct env var names across 56 Haskell `lookupEnv` call
sites, 28 chart-template `env:` injections, 24 Dockerfile/Compose directives, and 8 bootstrap-shell
references — plus pervasive implicit reliance on `PATH`, `HOME`, `KUBECONFIG`, and `DOCKER_HOST`
for external-tool resolution. This created three sources of supported-config truth in conflict
(env vars, the staged substrate `.dhall`, hardcoded defaults) and exposed the project to
PATH-shadowing surprises across operator shells.

The configuration doctrine collapses that to one substrate (Dhall) and one tool-discovery surface
(absolute paths in `InfernixHost.dhall`), eliminating both the env-var-vs-Dhall conflict and the
PATH-resolution ambiguity.

## The three Dhall files

### `dhall/InfernixHost.dhall`

Typed record describing the operator's host environment:

- **Tool paths** — absolute filesystem paths for every external command the project ever invokes:
  `docker`, `kubectl`, `helm`, `kind`, `cabal`, `ghc`, `ghcup`, `ormolu`, `hlint`, `npm`, `node`,
  `python3`, `poetry`, `protoc`, `git`, `tar`, `curl`, `apt-get`, `brew`, `sudo`,
  `systemctl`, `mkdir`, `chmod`, `ln`, `install`. See
  [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md).
- **Filesystem conventions** — `repoRoot`, `buildRoot`, `dataRoot`, `runtimeRoot`,
  `kubeconfigPath`, `secretsRoot`, `homeDirectory`.
- **Host execution context and native architecture** — `apple-silicon`, `linux-cpu`,
  `linux-gpu`, `outer-container`, plus the normalized native architecture used by the
  `linux-cpu` publication selector.

The Haskell binary loads this file at startup via the `dhall` library's `Dhall.inputFile` and
decodes it into a typed `HostConfig` record passed down the call tree.

The host tool inventory includes `hostTart`, the absolute `tart` path on Apple Silicon
(`/opt/homebrew/bin/tart`), which drives the headless `tart` macOS VM that builds the Metal and
Core ML native engine artifacts. See
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md) for the full field
inventory.

#### Typed engine-build sub-record and the hermetic tart-guest rule

The Apple Silicon Metal-engine build lane (the headless `tart` macOS VM that compiles the
Xcode-only llama.cpp and whisper.cpp Metal builds and the Core ML compiled models) is configured
entirely through the typed substrate — never through inherited host process state.

A typed engine-build sub-record carries the values the build needs:

- the build toolchain and source identifiers handed to the guest,
- the allowlisted Metal/Core ML adapter ids to materialize,
- the engine-install root the built artifacts are copied to (`./.data/engines/<adapterId>/`).

The hermetic tart-guest rule: the `tart` guest receives its toolchain and source through the typed
engine-build sub-record and `tart` file mounts, **never** through inherited host `PATH`,
environment variables, or SSH-with-env. The `hostTart` path itself is read from `HostConfig`, so
the helper that launches the guest resolves `tart` by absolute path rather than through the
operator's shell search path. This keeps the Metal-engine lane inside the same no-env-var,
typed-Dhall discipline as every other Infernix codepath: the three Dhall files remain the only
configuration substrate, and the engine-build sub-record lives within the host record's typed
schema, not in any env-var or ambient-shell surface.

### `dhall/InfernixCluster.dhall`

Typed record describing in-cluster wiring values that previously lived in pod-spec `env:` blocks:

- **Pulsar** — HTTP / WS / service URLs, tenant, namespace.
- **MinIO** — endpoint, region, presign expiry.
- **Keycloak** — base URL, realm name, client id, JWKS URL.
- **Demo backend** — bind host, bridge mode, publication state path.
- **Engine** — model cache root, per-binding command overrides.

The Haskell binary loads this file at startup. On-cluster, the same file is materialized into a
Kubernetes `ConfigMap` and mounted read-only at `/opt/infernix/cluster.dhall` in coordinator /
engine / demo pods. See [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md).

### `dhall/InfernixSecrets.dhall`

Typed record naming **file paths** at which secret material lives, never the values themselves:

```dhall
{ minio = { credentialsPath = "/etc/infernix/secrets/minio.json" }
, keycloakAdmin = { credentialsPath = "/etc/infernix/secrets/keycloak-admin.json" }
, keycloakDb = { credentialsPath = "/etc/infernix/secrets/keycloak-db.json" }
}
```

On-cluster, the JSON files come from a Kubernetes `Secret` mounted at `/etc/infernix/secrets/`.
On host, they live under `./.data/runtime/secrets/` (gitignored, operator-edited). The Haskell
application loads `SecretsConfig` from the Dhall file at startup, then calls `readFile` on the
named paths when it needs the actual credentials.

No secret value is ever inline in Dhall, never injected as an env var, never written to a chart
template.

## The bootstrap stage-zero convention

Bootstrap shells are the only operator-facing entry point that runs *before* the Haskell binary is
available. They handle host-prerequisite installs, build the launcher image, and then delegate
every subsequent command to the launcher.

Convention:

1. First line: `PATH=/usr/bin:/bin`. The operator's ambient shell search path cannot influence
   resolution.
2. Repo root: `REPO_ROOT="$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.."` — derived from the
   bash array `BASH_SOURCE`, not an env var.
3. Operator home: `HOME_DIR="$(/usr/bin/getent passwd "$(/usr/bin/id -u)" | /usr/bin/cut -d: -f6)"`
   — derived from `/etc/passwd`, not `$HOME`.
4. Every pre-binary command uses a hardcoded absolute-path constant:
   `/usr/bin/apt-get`, `/usr/bin/sudo`, `"${HOME_DIR}/.ghcup/bin/ghcup"`,
   `"${HOME_DIR}/.ghcup/bin/cabal"`, `/opt/homebrew/bin/brew` (macOS),
   `/usr/bin/docker`.
5. Once the launcher exists, every operation delegates to the binary:
   - **Apple**: `"${REPO_ROOT}/.build/infernix" <command>`
   - **Linux**: `/usr/bin/docker compose --file "${REPO_ROOT}/compose.yaml" run --rm infernix infernix <command>`

The Linux GPU bootstrap sets `LAUNCHER_IMAGE=infernix-linux-gpu:local` only for the Docker Compose
process it launches. That value selects the already-built launcher image; it is not read by
Infernix code, is not an operator configuration substrate, and does not replace the typed Dhall
files.

The shell never reads a `.dhall` file directly. The Haskell binary is the only Dhall reader.

## Cluster pod contract

Every `chart/templates/deployment-*.yaml` for infernix-owned workloads (coordinator, engine, demo)
mounts two volumes and carries **no `env:` block**:

- `cluster-config` (from `ConfigMap/infernix-cluster-config`) at `/opt/infernix/cluster.dhall`
- `cluster-secrets` (from `Secret/infernix-cluster-secrets`) at `/etc/infernix/secrets/`

The Haskell daemon decodes the Dhall file natively, reads the referenced secret files by absolute
path, and never consults `env`.

## Third-party-upstream exceptions

The doctrine governs Infernix's own code. Third-party container images that consume env vars at
startup (because their upstream contract requires it) keep their env entries:

- **Keycloak** — `KC_DB`, `KC_DB_URL`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`, etc. are read by the
  upstream Keycloak image itself. The Keycloak pod spec retains these env entries, sourced from
  a mounted Secret where the Keycloak release supports it. See
  [../tools/keycloak.md](../tools/keycloak.md).

The lint gates carry an explicit exception list naming this and any future third-party upstream
contract.

## Validation

- `infernix lint files` rejects any new `lookupEnv` / `getEnv` / `proc "<bare-name>"` outside the
  documented exception list.
- `infernix lint chart` rejects any `env:` block in
  `chart/templates/deployment-{coordinator,engine,demo}.yaml`.
- `infernix lint docs` rejects governed-doc language that presents project-prefixed env names or
  shell path overrides as supported operator configuration outside the legacy-tracking ledger and
  documented exception docs.
- End-to-end coverage: `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh up` (empty starting env)
  reaches `lifecyclePhase: steady-state` — proving the contract holds when the operator's shell
  starts with no env vars at all.

## Cross-References

- [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md) —
  `InfernixHost.dhall` schema spec.
- [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md) —
  `InfernixCluster.dhall` + ConfigMap+Secret mount contract.
- [../development/no_env_vars.md](../development/no_env_vars.md) — developer-facing rules and
  lint gates.
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)
  Sections T and U.
- [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)
  for the retirement ledger.
