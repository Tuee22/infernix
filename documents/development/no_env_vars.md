# No Environment Variables in Infernix Code

**Status**: Authoritative source
**Referenced by**: [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md), [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md), [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Developer-facing rules for writing Infernix code without consuming environment
> variables, without relying on PATH-resolution of external commands, and without injecting
> env entries into chart templates.

## TL;DR

- **Never call** `lookupEnv`, `getEnv`, `getEnvironment`, `setEnv`, or `unsetEnv` in Haskell runtime,
  test, or lint code. The only current exception is `Setup.hs`'s deterministic `Env.setEnv "PATH"`
  shim for Cabal/proto-lens custom setup.
- **Never call** `proc "<bare-name>"` for any external command. Use
  `runHostTool hostConfig <toolName> args` instead.
- **Never call** `findExecutable` or `findExecutables` to discover a manifest-owned tool. Use
  `HostConfig.toolPaths.*` or the fixed absolute fallback candidates in `Infernix.HostTools`.
- **Never read** `process.env` in Node/web/Playwright code, `os.environ` in Python, or inherited
  `$VAR` values in bash (except `${BASH_SOURCE[0]}` which is a bash array, not an env var).
- **Never add** an `env:` entry to `chart/templates/deployment-{coordinator,engine,demo}.yaml`.
  Mount the cluster ConfigMap + Secret instead.
- **Always thread** typed `HostConfig` / `ClusterConfig` / `SecretsConfig` records as
  parameters down your call tree.

## Current Audit Note

The June 2026 audit reopened Phase 6 Sprint 6.34 for remaining enforcement gaps, and the sprint is now
closed. `Setup.hs` no longer reads operator environment and keeps only a deterministic setup-local
`PATH` mutation for proto-lens; bootstrap shell no longer accepts inherited command overrides or
inherited `PATH` joins; Haskell-style Cabal invocations resolve through `HostConfig` or fixed
candidates; and the PureScript compiler installer no longer shells out to bare `mktemp` / `tar`.

## Haskell

### Reading settings

```haskell
-- BAD: env-var consumption
maybeEndpoint <- lookupEnv "LEGACY_MINIO_ENDPOINT"
let endpoint = fromMaybe "http://localhost:9000" maybeEndpoint

-- GOOD: typed config from ClusterConfig
let endpoint = minioEndpoint (clusterMinio clusterConfig)
```

`ClusterConfig` is loaded once at the entry point (`runDemoApiServer`, `runProductionDaemon`,
etc.) via `decodeClusterConfigFile clusterConfigPath` and threaded down. No module
deeper in the call tree calls `lookupEnv` for any reason.

### Invoking external commands

```haskell
-- BAD: PATH-resolved external command
result <- readProcess "docker" ["image", "inspect", imageRef] ""

-- GOOD: absolute path from HostConfig
result <- runHostTool hostConfig HostDocker ["image", "inspect", imageRef]
```

`runHostTool` (in `src/Infernix/HostTools.hs`) takes the typed `HostConfig` record + a
`HostTool` enum value + arguments and invokes the command by absolute path. Manifestless
bootstrap-adjacent helpers may check only the fixed absolute candidates from
`hostToolFallbackCandidates`; they must not call `findExecutable`. The `HostTool`
enum has one constructor per tool listed in
[../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md).

### Test fixtures

```haskell
-- BAD: setEnv-driven test isolation
setEnv "LEGACY_DATA_ROOT" "/tmp/test-data-123"

-- GOOD: typed HostConfig override for the test
let testHostConfig = baseHostConfig
      { filesystem = (filesystem baseHostConfig)
          { dataRoot = "/tmp/test-data-123" }
      }
withTestHostConfig testHostConfig $ \cfg -> do
  ...
```

## Python (adapters)

The Haskell daemon invokes the adapter via `runHostTool hostConfig HostPoetry [..., adapterScript]`
and passes the typed JSON config blob on stdin. The adapter parses it once at startup:

```python
# BAD: env-var consumption
import os
endpoint = os.environ.get("LEGACY_MINIO_ENDPOINT", "http://localhost:9000")

# GOOD: stdin config blob
import json, sys
config = json.load(sys.stdin)
endpoint = config["minio"]["endpoint"]
```

`os.environ` is never read by adapter code.

## Web / Node / Playwright

The Playwright config file emits the typed fixture via Playwright's `use:` block from a
Dhall-decoded JSON file written at test setup. The test declares a typed Playwright option fixture:

```javascript
// BAD: process.env consumption
const edgePort = process.env.LEGACY_EDGE_PORT || "9090";

// GOOD: Playwright option fixture
const test = base.extend({
  infernixFixture: [undefined, { option: true }],
});

test("...", async ({ page, infernixFixture }) => {
  const edgePort = infernixFixture.edgePort;
  ...
});
```

The fixture is set up in `web/playwright.config.js` from the repo-relative
`.data/runtime/playwright-fixture.json` (written by the Haskell test driver from `ClusterConfig` +
`HostConfig` at test start and resolved to `/workspace/.data/runtime/playwright-fixture.json`
inside the Linux launcher).

## Shell / Bootstrap

Bootstrap scripts derive their variables from script location, `/etc/passwd`, and literal
absolute constants — never from inherited env vars:

```bash
# BAD: inherited env var consumption
docker compose --file "$REPO_ROOT/compose.yaml" run --rm infernix infernix cluster up

# GOOD: derived from BASH_SOURCE, hardcoded absolute path
PATH=/usr/bin:/bin
REPO_ROOT="$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.."
HOME_DIR="$(/usr/bin/getent passwd "$(/usr/bin/id -u)" | /usr/bin/cut -d: -f6)"
/usr/bin/docker compose --file "${REPO_ROOT}/compose.yaml" run --rm infernix infernix cluster up
```

The first line resets `PATH=/usr/bin:/bin` so the operator's ambient PATH cannot influence
resolution. Every pre-binary command uses an absolute-path constant.

Phase 6 Sprint 6.34 retired the inherited `BOOTSTRAP_*` command override defaults from the
pre-doctrine bootstrap era. Shell entrypoints use literal absolute constants or derived absolute paths
and cannot be configured by inherited environment variables.

The only shell-level exception is the bootstrap-owned `LAUNCHER_IMAGE=... docker compose ...`
prefix used to select the already-built Linux launcher image for one Docker Compose process. It is
set by the bootstrap script or written explicitly in direct-reference commands; Infernix code
never reads it, and all runtime configuration still comes from Dhall.

## Chart templates

Pod specs for infernix-owned workloads carry no `env:` block. Mount the cluster ConfigMap +
Secret instead:

```yaml
# BAD: env: block in pod spec
spec:
  containers:
    - name: infernix-demo
      env:
        - name: LEGACY_MINIO_ENDPOINT
          value: "http://infernix-minio.platform.svc.cluster.local:9000"

# GOOD: ConfigMap + Secret mount
spec:
  volumes:
    - name: cluster-config
      configMap:
        name: infernix-cluster-config
    - name: cluster-secrets
      secret:
        secretName: infernix-cluster-secrets
  containers:
    - name: infernix-demo
      volumeMounts:
        - name: cluster-config
          mountPath: /opt/infernix/cluster.dhall
          subPath: cluster.dhall
          readOnly: true
        - name: cluster-secrets
          mountPath: /etc/infernix/secrets
          readOnly: true
```

## Apple engine materialization

The supported Apple Metal/Core ML materialization target uses typed engine-artifact records rather
than inherited process state. Adapter id, artifact kind, source references, runtime fingerprint,
install root, optional MinIO object key, entrypoint, and smoke command are explicit record fields;
no host environment variable crosses into the materialization path. The old Tart helper path has
been removed, and new Apple engine work must not add Tart, keychain, Xcode UI, or
`ssh`-with-env dependencies. The canonical home for this substrate is
[../engineering/apple_silicon_metal_headless_builds.md](../engineering/apple_silicon_metal_headless_builds.md).

## Third-party-upstream exceptions

Keycloak's upstream image consumes `KC_DB_*` env vars; the Keycloak pod spec retains those
entries, sourced from a mounted Secret where possible. The lint gates allow them by exception.
Document any future exception in `documents/tools/<tool>.md` and add it to the lint exception
list in `src/Infernix/Lint/Chart.hs`.

## Lint enforcement

The repo-local lint gates are:

- `src/Infernix/Lint/HaskellStyle.hs.forbiddenEnvFunctions` — rejects any of
  `lookupEnv`, `getEnv`, `getEnvironment`, `setEnv`, `unsetEnv` in
  `src/`, `app/`, `test/`, and `Setup.hs` except for the deterministic `Env.setEnv "PATH"` setup shim.
- `src/Infernix/Lint/HaskellStyle.hs.forbiddenBareProcCommands` — rejects
  `proc "<bare-name>"` whose name matches a registered host tool. The list is derived from the
  `Infernix.HostTools.HostTool` enum via `hostToolCommandNames` (which mirrors the
  `HostConfig`/`HostToolPaths` schema), so it cannot drift from the tool set.
- `src/Infernix/Lint/Docs.hs` — rejects governed-doc language that presents project-prefixed env
  names or shell path overrides as supported operator configuration outside the legacy-tracking
  ledger and documented exception docs. Phase 6 Sprint 6.34 expanded its required-doc and phase-doc
  coverage so newly authoritative configuration and Phase 7 documents cannot drift outside the lint
  set.
- `src/Infernix/Lint/Chart.hs` — rejects any `env:` block in
  `chart/templates/deployment-{coordinator,engine,demo}.yaml`.

Run locally: `infernix test lint`.

## Cross-References

- [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md) —
  doctrinal home.
- [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md) — the
  `InfernixHost.dhall` schema.
- [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md) —
  the `InfernixCluster.dhall` schema and ConfigMap+Secret contract.
- [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)
  Sections T and U.
