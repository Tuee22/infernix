# No Environment Variables in Infernix Code

**Status**: Authoritative source
**Referenced by**: [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md), [../engineering/host_tools_manifest.md](../engineering/host_tools_manifest.md), [../engineering/cluster_config_manifest.md](../engineering/cluster_config_manifest.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Developer-facing rules for writing Infernix code without consuming environment
> variables, without relying on PATH-resolution of external commands, and without injecting
> env entries into chart templates.

## TL;DR

- **Never call** `lookupEnv`, `getEnv`, `getEnvironment`, `setEnv`, or `unsetEnv` in Haskell.
- **Never call** `proc "<bare-name>"` for any external command. Use
  `runHostTool hostConfig <toolName> args` instead.
- **Never read** `process.env` in Node/web/Playwright code, `os.environ` in Python, or `$VAR`
  in bash (except `${BASH_SOURCE[0]}` which is a bash array, not an env var).
- **Never add** an `env:` entry to `chart/templates/deployment-{coordinator,engine,demo}.yaml`.
  Mount the cluster ConfigMap + Secret instead.
- **Always thread** typed `HostConfig` / `ClusterConfig` / `SecretsConfig` records as
  parameters down your call tree.

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
`HostTool` enum value + arguments and invokes the command by absolute path. The `HostTool`
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
Dhall-decoded JSON file written at test setup. The test reads `test.info().project.use.*`:

```javascript
// BAD: process.env consumption
const edgePort = process.env.LEGACY_EDGE_PORT || "9090";

// GOOD: Playwright fixture
test("…", async ({ page }, testInfo) => {
  const edgePort = testInfo.project.use.edgePort;
  ...
});
```

The fixture is set up in `web/playwright.config.js` from
`/workspace/.data/runtime/playwright-fixture.json` (written by the Haskell test driver from
`ClusterConfig` + `HostConfig` at test start).

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

## Third-party-upstream exceptions

Keycloak's upstream image consumes `KC_DB_*` env vars; the Keycloak pod spec retains those
entries, sourced from a mounted Secret where possible. The lint gates allow them by exception.
Document any future exception in `documents/tools/<tool>.md` and add it to the lint exception
list in `src/Infernix/Lint/Chart.hs`.

## Lint enforcement

Phase 6 Sprint 6.28 adds these gates:

- `src/Infernix/Lint/HaskellStyle.hs.disallowedFunctions` — rejects any of
  `lookupEnv`, `getEnv`, `getEnvironment`, `setEnv`, `unsetEnv` in
  `src/`, `app/`, `test/`.
- `src/Infernix/Lint/HaskellStyle.hs.disallowedProcCommands` — rejects
  `proc "<bare-name>"` whose name matches a tool in
  `dhall/InfernixHost.dhall`.
- `src/Infernix/Lint/Docs.hs` — rejects governed-doc language that presents project-prefixed env
  names or shell path overrides as supported operator configuration outside the legacy-tracking
  ledger and documented exception docs.
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
