# Configuration Doctrine

**Status**: Authoritative source
**Referenced by**: [overview.md](overview.md), [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md), [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md), [../development/no_env_vars.md](../development/no_env_vars.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define the supported configuration substrate — typed `.dhall` that is **generated
> by the `infernix` binary, never version-controlled** — the `init` / `test init` create contract,
> the fail-fast-if-missing rule, and the no-env-var, absolute-path discipline that surrounds it.

## TL;DR

- **Zero version-controlled `.dhall`.** No `.dhall` file is checked into the repository. Every
  `.dhall` in the tree is a generated artifact under `.build/` / `.data/` (gitignored) or the
  operator-created `./infernix.dhall` / `./infernix.test.dhall` (also gitignored).
- **The `infernix` binary is the sole generator of every `.dhall`** — including the bodies injected
  into pods via ConfigMap/Secret. Helm never renders or parses Dhall; it only embeds a
  binary-produced string (`nindent`). Schemas are **reflected from the Haskell decoder types**
  (`renderDecoderExpected (Dhall.auto @T)`), so the emitted schema cannot drift from what the
  decoder accepts.
- **Config is created by `init`.** `infernix init` writes the operator's runtime
  `./infernix.dhall` (the substrate: runtime mode, daemon roles, model set) and the host manifest
  `./infernix-host.dhall`. `infernix test init` writes the thin `./infernix.test.dhall`. There is
  **no hidden auto-generate-if-absent backstop** inside ordinary `infernix` commands. The Apple
  stage-0 bootstrap wrapper is the sole convenience exception: `./bootstrap/apple-silicon.sh up`
  explicitly invokes `./.build/infernix init --if-missing` before `cluster up`.
- **Everything fails fast when its config is missing**, naming the init to run
  (e.g. `runtime config missing at ./infernix.dhall; run \`infernix init\``), unless the operator
  entered through that Apple bootstrap wrapper.
- **The test harness owns the runtime config during a run**: driven by `./infernix.test.dhall`, it
  generates `./infernix.dhall`, runs the suites, and deletes it (self-created-only guard); it fails
  fast if `./infernix.dhall` already exists.
- The `dhall` Haskell library is the only Dhall reader. There is no `dhall-to-json` bridge.
- Every external command the project ever invokes is named in the host manifest by absolute path;
  no `proc "<bare-name>"` / `findExecutable` discovery in Haskell, no bare-name invocations in shell.
- No Haskell module calls `lookupEnv` / `getEnv` / `getEnvironment` / `setEnv` / `unsetEnv`; no
  infernix-owned `chart/templates/deployment-*.yaml` carries an `env:` block.

## Why

The codebase previously accumulated 87 distinct env var names across dozens of Haskell `lookupEnv`
call sites, chart-template `env:` injections, and bootstrap-shell references — plus pervasive
implicit reliance on `PATH` / `HOME` / `KUBECONFIG` / `DOCKER_HOST`. The configuration doctrine
collapses that to one substrate (typed Dhall) and one tool-discovery surface (absolute paths in the
host manifest).

A second source of drift was **hand-maintained `.dhall` schema files** committed alongside the
Haskell renderers that generate them, plus `.dhall` *values* rendered by Helm templating from
`chart/values.yaml`. Both are removed: the binary reflects each schema from its decoder type and
renders every value, so there is exactly one source of truth per config (the Haskell type), no
committed schema to drift, and no Dhall inside Helm templates.

## Generated, never tracked

Every `.dhall` is produced by the binary from a Haskell type. There is nothing to hand-edit into
existence and nothing to check in.

| Config | Haskell owner | Created by | Consumed by |
|---|---|---|---|
| **runtime `infernix.dhall`** (substrate: runtime mode, daemon roles, model set, topics) | `Infernix.Substrate` / `Infernix.Models` encoders; defaults in `Infernix.ProjectInit` | `infernix init` (operator) or the test harness (per run) | coordinator/engine/webapp daemons via `decodeDemoConfigFile` |
| **host manifest `infernix-host.dhall`** (tool paths, host context, filesystem) | `Infernix.HostConfig` | `infernix init` | host CLI tool resolution |
| **cluster config `cluster.dhall`** (in-cluster wiring) | `Infernix.ClusterConfig` (`defaultClusterConfig`) | the binary at `cluster up`, injected into Helm as an `nindent`'d string | pods via `decodeClusterConfigFile` |
| **secrets `InfernixSecrets.dhall`** (paths to secret files, never values) | `Infernix.SecretsConfig` | the binary (host) / `cluster up` (cluster), injected into Helm as a string | secret-path resolution |

Defaults live in exactly one place — `Infernix.ProjectInit` (the single `init`-and-harness defaults
owner) — so `infernix init` and the test harness share them (DRY). `infernix internal dhall-schema
host|cluster|secrets|substrate` prints the reflected schema for any config on demand; nothing reads
a schema from disk.

### The runtime config is the model source of truth

The set of models in scope for a workload is **the model list in the effective (mounted)
`infernix.dhall`** — not anything compiled into infernix core. The coordinator **eagerly populates
its model cache on startup from that mounted config** (failing fast if there is no config), and the
`warm-model-cache` cluster-up phase blocks until every listed model is staged, so tests never race a
cold cache.

For the demo, the model set is generated from the `matrixRows` table in `src/Infernix/Models.hs` —
but that hardcoding is a **demo-only convenience**: the demo must expose the identical set in its UI,
so it keeps one in-code source feeding both its generated `infernix.dhall` and the frontend. Other
workloads consuming Infernix bring their own source of truth (including dynamic selection /
rotation); infernix core never hardcodes the model set — it stages exactly what the mounted config
lists.

### Baked vs mounted config

The image-baked `infernix.dhall` (written by `infernix init` at docker-build time) lists **no
models** — it exists only so `docker run --rm infernix …` one-shots satisfy the fail-fast rule and
never trigger a download. At deploy, the coordinator's ConfigMap-mounted `infernix.dhall` (the real
model set) is volume-mounted **over** the baked file; only the deployed coordinator stages weights.

## The three cluster-facing config records

### Host manifest (`infernix-host.dhall`)

Typed record describing the operator's host environment — absolute **tool paths** for every external
command the project invokes (`docker`, `kubectl`, `helm`, `kind`, `cabal`, `ghc`, `ghcup`, `ormolu`,
`hlint`, `npm`, `node`, `python3`, `poetry`, `protoc`, `git`, `tar`, `curl`, `apt-get`, `brew`,
`sudo`, `systemctl`, `mkdir`, `chmod`, `ln`, `install`), **filesystem conventions** (`repoRoot`,
`buildRoot`, `dataRoot`, `runtimeRoot`, `kubeconfigPath`, `secretsRoot`, `homeDirectory`), and the
**host execution context / native architecture**. Written by `infernix init`; the binary decodes it
at startup into a `HostConfig` record. See
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md). The retained Apple
materialization command is configured through typed engine-artifact records, never inherited host
process state — see
[../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

### Cluster config (`cluster.dhall`)

Typed record of in-cluster wiring that previously lived in pod-spec `env:` blocks — Pulsar
(HTTP/WS/service URLs, tenant, namespace), MinIO (endpoint, region, presign expiry, buckets),
Keycloak (base URL, realm, client id, JWKS URL), demo backend (bind host, bridge mode, publication
state path), engine (model cache root, quota, per-binding command overrides), coordinator
(control-plane context, daemon location). These are deterministic derived values, so they carry **no
`init`**: the binary renders `cluster.dhall` from `ClusterConfig.defaultClusterConfig` at `cluster
up` and hands the string to Helm, which embeds it verbatim into `ConfigMap/infernix-cluster-config`
(mounted read-only at `/opt/infernix/cluster.dhall`). Helm never parses or templates the Dhall. See
[../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md).

### Secrets (`InfernixSecrets.dhall`)

Typed record naming **file paths** at which secret material lives, never the values:

```dhall
{ minio = { credentialsPath = "/etc/infernix/secrets/minio.json" }
, keycloakAdmin = { credentialsPath = "/etc/infernix/secrets/keycloak-admin.json" }
, keycloakDb = { credentialsPath = "/etc/infernix/secrets/keycloak-db.json" }
}
```

On-cluster the JSON files come from a Kubernetes `Secret` mounted at `/etc/infernix/secrets/`; on
host they live under `./.data/runtime/secrets/` (gitignored). The binary renders both the secrets
Dhall and the credential JSON bodies and injects them into Helm as strings; no secret value is ever
inline in Dhall, injected as an env var, or hand-written into a chart template.

## The bootstrap stage-zero convention

Bootstrap shells are the only operator-facing entry point that runs *before* the Haskell binary is
available. They install host prerequisites, build the launcher image, and delegate every subsequent
command to the binary.

Convention: first line `PATH=/usr/bin:/bin`; repo root from `BASH_SOURCE` (not an env var); operator
home from `/etc/passwd` via `getent` (not `$HOME`); every pre-binary command a hardcoded absolute
path; and once the launcher exists, every operation delegates to the binary
(`"${REPO_ROOT}/.build/infernix" <command>` on Apple; `docker compose … run --rm infernix infernix
<command>` on Linux). The `LAUNCHER_IMAGE=infernix-linux-gpu:local` value the GPU bootstrap sets is
only the Compose image selector — not read by Infernix code, not a config substrate.

The shell never reads a `.dhall` file directly. The Haskell binary is the only Dhall reader.

## Cluster pod contract

Every `chart/templates/deployment-*.yaml` for infernix-owned workloads (coordinator, engine, webapp)
mounts two volumes and carries **no `env:` block**:

- `cluster-config` (from `ConfigMap/infernix-cluster-config`, whose body is the binary-rendered
  `cluster.dhall` string) at `/opt/infernix/cluster.dhall`
- `cluster-secrets` (from `Secret/infernix-cluster-secrets`, binary-rendered) at `/etc/infernix/secrets/`

The coordinator additionally mounts `ConfigMap/infernix-demo-config` (the binary-rendered runtime
`infernix.dhall`, with the real model set) **over** the image-baked config path. The daemon decodes
the Dhall natively, reads secret files by absolute path, and never consults `env`.

## Third-party-upstream exceptions

The doctrine governs Infernix's own code. Third-party images that consume env vars at startup because
their upstream contract requires it keep their env entries — e.g. **Keycloak** (`KC_DB`, `KC_DB_URL`,
…) read by the upstream image, sourced from a mounted Secret. See [../tools/keycloak.md](../tools/keycloak.md).
The lint gates carry an explicit exception list naming this and any future upstream contract.

## Validation

- `infernix test lint` (the Haskell-style suite) rejects new `lookupEnv` / `getEnv` /
  `proc "<bare-name>"` and `findExecutable` / `findExecutables` discovery outside the lint module's
  own token list and the documented exception list. `infernix lint files` rejects `os.environ` /
  `os.getenv` reads under `python/`, `process.env` reads under `web/`, and any tracked `.dhall`.
- `infernix lint chart` rejects any `env:` block in the infernix-owned
  `deployment-{coordinator,engine,demo}.yaml`, and any Dhall `let …`/schema body inside a chart
  template (Helm must only `nindent` a binary-produced payload string).
- `infernix lint docs` / `infernix docs check` keep the governed docs (this doctrine, `no_env_vars.md`,
  the manifest specs, tool docs, plan docs) in the machine lint set, reject retired-doctrine
  language, and — for the Dhall schemas — assert each reflects to a non-empty expression (there is no
  tracked `.dhall` to diff against). The unit suite additionally round-trips a default value of each
  config through encode → decode.
- A tree scan asserts **zero tracked `.dhall`** (`git ls-files '*.dhall'` is empty).
- End-to-end: `env -i /usr/bin/bash ./bootstrap/linux-gpu.sh up` (empty starting env) reaches steady
  state, proving the contract holds when the operator's shell starts with no env vars at all.

## Cross-References

- [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md) — host-manifest schema spec.
- [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md) — cluster-config record + ConfigMap/Secret mount contract.
- [../development/no_env_vars.md](../development/no_env_vars.md) — developer-facing rules and lint gates.
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md) Sections T and U.
- [../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md) for the retirement ledger.
