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

This table records the typed input families read by each consumer.

| Input family | Dhall field family | Read by |
|--------------|--------------------|---------|
| Pulsar admin, WebSocket, HTTP, service URL, tenant, and namespace inputs | `pulsar.*` | `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Conversation/Topic.hs` |
| MinIO endpoint, public presign endpoint, region, presign-expiry, and model-bucket inputs | `minio.*` | `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs`, `python/adapters/model_cache.py` |
| MinIO access-key and secret-key inputs | `readFile (SecretsConfig.minio.credentialsPath)` -> `accessKey` / `secretKey` | `src/Infernix/Demo/Api.hs`, `src/Infernix/Runtime/Pulsar.hs` |
| Keycloak base URL, realm, client id, and JWKS URL inputs | `keycloak.*` | `src/Infernix/Demo/Auth.hs`, `src/Infernix/Demo/Api.hs` |
| Demo bind host, bridge mode, publication state path, and demo-config path inputs | `demoBackend.*` | `src/Infernix/DemoCLI.hs`, `src/Infernix/Service.hs` |
| Model-cache root and quota inputs | `engine.modelCacheRoot`, `engine.modelCacheQuotaBytes` | `python/adapters/model_cache.py` |
| Engine command override inputs | `engine.commandOverrides` | `src/Infernix/Runtime/Worker.hs` |
| Coordinator catalog-source, control-plane-context, daemon-location, and daemon-role inputs | `coordinator.*` plus the substrate `.dhall` role field | `src/Infernix/Runtime/Pulsar.hs`, `src/Infernix/Service.hs` |

`keycloak.baseUrl` is the issuer-facing public base URL and includes the routed `/auth` prefix
when the local Gateway publishes Keycloak there. `keycloak.clientId` is the public SPA client id
(`infernix-spa` for the supported demo realm). `keycloak.jwksUrl` is the backend fetch URL for
the same realm's signing keys; it may use the in-cluster Keycloak Service, but it must include the
Service port and the same `/auth/realms/<realm>/protocol/openid-connect/certs` path.

`minio.endpoint` is the in-cluster Service URL used by coordinator/bootstrap code and the webapp
object-proxy to talk to MinIO from inside Kubernetes. Phase 3 Sprint 3.13 removed the
`minio.presignPublicEndpoint` field: there is no browser-facing presign base because the browser
never receives a presigned MinIO URL — the webapp `/api/objects` proxy signs against the internal
`minio.endpoint` and streams bytes itself.

## Validation

- `infernix lint chart` rejects any `env:` block in
  `chart/templates/deployment-{coordinator,engine,demo}.yaml`.
- `infernix lint files` rejects any new project-prefixed env lookup in the Haskell sources.
- `infernix test e2e` proves the demo pod reads the mounted `keycloak.*` fields correctly by
  exchanging a real routed Keycloak auth code, rejecting a malformed bearer token, accepting the
  real access token for `/api/objects` byte upload/download through the webapp proxy, and proving
  cross-user object-prefix isolation (HTTP 403) at the server-side trust boundary.

## Cross-References

- [../architecture/configuration_doctrine.md](../architecture/configuration_doctrine.md) — overall
  configuration substrate.
- [host_tools_manifest.md](host_tools_manifest.md) — the matching host-tools manifest.
- [../tools/{harbor,minio,pulsar,keycloak}.md](../tools/keycloak.md) — per-tool docs each name
  the cluster Dhall field that wires them; Keycloak doc additionally documents the `KC_DB_*`
  third-party-upstream exception.
