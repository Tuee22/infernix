# Cluster Config Manifest

**Status**: Authoritative source
**Referenced by**: [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md), [../architecture/daemon_topology.md](../architecture/daemon_topology.md), [../tools/pulsar.md](../tools/pulsar.md), [../tools/minio.md](../tools/minio.md), [../tools/keycloak.md](../tools/keycloak.md), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md)

> **Purpose**: Define the `dhall/InfernixCluster.dhall` schema, the ConfigMap+Secret mount
> contract that replaces every infernix-owned pod's `env:` block, and the per-field source
> mapping for runtime cluster wiring.

## TL;DR

- `dhall/InfernixCluster.dhall` is the typed source of truth for every in-cluster wiring value
  that previously lived in `chart/templates/deployment-*.yaml` `env:` blocks.
- The chart renders this into a Kubernetes `ConfigMap` named `infernix-cluster-config` and
  mounts it read-only at `/opt/infernix/cluster.dhall` in coordinator / engine / demo pods.
- Credentials are NOT in this file. They live in a separate Kubernetes `Secret` mounted at
  `/etc/infernix/secrets/`, with the paths named by `dhall/InfernixSecrets.dhall`.
- The Haskell daemon decodes both at startup; no infernix-owned pod consumes env vars.

## Schema

```dhall
let Url = Text

let PulsarConfig =
      { httpBaseUrl : Url
      , wsBaseUrl : Url
      , adminUrl : Url
      , serviceUrl : Url
      , tenant : Text
      , namespace : Text
      , systemNamespace : Text
      }

let MinioConfig =
      { endpoint : Url
      , region : Text
      , presignExpirySeconds : Natural
      , modelsBucket : Text
      , demoArtifactsBucket : Text
      }

let KeycloakConfig =
      { baseUrl : Url
      , realmName : Text
      , clientId : Text
      , jwksUrl : Url
      }

let DemoBackendConfig =
      { bindHost : Text
      , port : Natural
      , bridgeMode : Text
      , publicationStatePath : Text
      , demoConfigPath : Text
      }

let EngineConfig =
      { modelCacheRoot : Text
      , modelCacheQuotaBytes : Natural
      , commandOverrides : List { mapKey : Text, mapValue : Text }
      }

let CoordinatorConfig =
      { catalogSource : Text
      , controlPlaneContext : Text
      , daemonLocation : Text
      }

in    { pulsar : PulsarConfig
      , minio : MinioConfig
      , keycloak : KeycloakConfig
      , demoBackend : DemoBackendConfig
      , engine : EngineConfig
      , coordinator : CoordinatorConfig
      }
```

The schema lives in `dhall/InfernixCluster.dhall`; the materialized cluster copy lives in
the `ConfigMap/infernix-cluster-config` resource that the chart renders.

## ConfigMap + Secret mount contract

Every infernix-owned daemon pod template (`chart/templates/deployment-{coordinator,engine,demo}.yaml`)
carries:

```yaml
volumes:
  - name: cluster-config
    configMap:
      name: infernix-cluster-config
  - name: cluster-secrets
    secret:
      secretName: infernix-cluster-secrets
containers:
  - name: …
    volumeMounts:
      - name: cluster-config
        mountPath: /opt/infernix/cluster.dhall
        subPath: cluster.dhall
        readOnly: true
      - name: cluster-secrets
        mountPath: /etc/infernix/secrets
        readOnly: true
```

The pod spec has **no `env:` block**.

The `ConfigMap/infernix-cluster-config` carries one key `cluster.dhall` whose value is the
materialized Dhall source. The `Secret/infernix-cluster-secrets` carries one key per credential
file (e.g. `minio.json`, `keycloak-admin.json`, `keycloak-db.json`).

The Haskell daemon decodes `cluster.dhall` via `Dhall.inputFile`, then reads each referenced
secret file via `readFile (SecretsConfig.<service>.credentialsPath)`.

## Per-field origin mapping

This table replaces every env var that previously appeared in
`chart/templates/deployment-*.yaml`:

| Previous env var | New Dhall field | Read by |
|------------------|------------------|---------|
| `INFERNIX_PULSAR_ADMIN_URL` | `pulsar.adminUrl` | `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_PULSAR_WS_BASE_URL` | `pulsar.wsBaseUrl` | `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_PULSAR_HTTP_BASE_URL` | `pulsar.httpBaseUrl` | `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_PULSAR_SERVICE_URL` | `pulsar.serviceUrl` | `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_PULSAR_TENANT` | `pulsar.tenant` | `src/Infernix/Conversation/Topic.hs` |
| `INFERNIX_PULSAR_NAMESPACE` | `pulsar.namespace` | `src/Infernix/Conversation/Topic.hs` |
| `INFERNIX_MINIO_ENDPOINT` | `minio.endpoint` | `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_MINIO_REGION` | `minio.region` | `src/Infernix/Demo/Api.hs` |
| `INFERNIX_MINIO_PRESIGN_EXPIRY_SECONDS` | `minio.presignExpirySeconds` | `src/Infernix/Demo/Api.hs` |
| `INFERNIX_MINIO_ACCESS_KEY` | `readFile (SecretsConfig.minio.credentialsPath)` → `accessKey` | `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_MINIO_SECRET_KEY` | `readFile (SecretsConfig.minio.credentialsPath)` → `secretKey` | same |
| `INFERNIX_MODELS_BUCKET` | `minio.modelsBucket` | `python/adapters/model_cache.py` (via stdin config from Haskell) |
| `INFERNIX_KEYCLOAK_BASE_URL` | `keycloak.baseUrl` | `src/Infernix/Demo/Auth.hs` |
| `INFERNIX_KEYCLOAK_REALM_NAME` | `keycloak.realmName` | `src/Infernix/Demo/Auth.hs` |
| `INFERNIX_KEYCLOAK_CLIENT_ID` | `keycloak.clientId` | `src/Infernix/Demo/Auth.hs` |
| `INFERNIX_KEYCLOAK_JWKS_URL` | `keycloak.jwksUrl` | `src/Infernix/Demo/Api.hs` |
| `INFERNIX_BIND_HOST` | `demoBackend.bindHost` | `src/Infernix/DemoCLI.hs` |
| `INFERNIX_DEMO_BRIDGE_MODE` | `demoBackend.bridgeMode` | `src/Infernix/DemoCLI.hs` |
| `INFERNIX_PUBLICATION_STATE_PATH` | `demoBackend.publicationStatePath` | `src/Infernix/DemoCLI.hs` |
| `INFERNIX_DEMO_CONFIG_PATH` | `demoBackend.demoConfigPath` | `src/Infernix/Service.hs` |
| `INFERNIX_MODEL_CACHE_ROOT` | `engine.modelCacheRoot` | `python/adapters/model_cache.py` |
| `INFERNIX_MODEL_CACHE_QUOTA_BYTES` | `engine.modelCacheQuotaBytes` | `python/adapters/model_cache.py` |
| `INFERNIX_ENGINE_COMMAND_<NAME>` | `engine.commandOverrides` (Map) | `src/Infernix/Runtime/Worker.hs` |
| `INFERNIX_CATALOG_SOURCE` | `coordinator.catalogSource` | `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_CONTROL_PLANE_CONTEXT` | `coordinator.controlPlaneContext` | `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_DAEMON_LOCATION` | `coordinator.daemonLocation` | `src/Infernix/Runtime/Pulsar.hs` |
| `INFERNIX_DAEMON_ROLE` | the substrate `.dhall` `daemonRole` field already | `src/Infernix/Service.hs` |

## Validation

- `infernix lint chart` rejects any `env:` block in
  `chart/templates/deployment-{coordinator,engine,demo}.yaml`.
- `infernix lint files` rejects any new `lookupEnv "INFERNIX_*"` call in the Haskell sources.
- `infernix test integration` round-trips a complete `/api/objects` flow on `linux-gpu`,
  proving the coordinator + demo + engine pods all read their config from the Dhall file +
  Secret files and never consult `env`.

## Cross-References

- [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md) — overall
  configuration substrate.
- [host_tools_manifest.md](host_tools_manifest.md) — the matching host-tools manifest.
- [../tools/{harbor,minio,pulsar,keycloak}.md](../tools/keycloak.md) — per-tool docs each name
  the cluster Dhall field that wires them; Keycloak doc additionally documents the `KC_DB_*`
  third-party-upstream exception.
