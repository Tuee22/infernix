{- Infernix cluster manifest schema.

   Typed record covering every in-cluster wiring value that previously
   lived in `chart/templates/deployment-*.yaml` `env:` blocks. The chart
   renders this into `ConfigMap/infernix-cluster-config`, mounted
   read-only at `/opt/infernix/cluster.dhall` in coordinator / engine /
   demo pods.

   Phase 0 Sprint 0.9 declared the no-env-var doctrine
   (see `documents/architecture/configuration_doctrine.md`). Phase 4
   Sprint 4.13 materializes this schema and threads a `ClusterConfig`
   record through every coordinator + engine entry point so no module
   needs to call `lookupEnv` for `INFERNIX_*` wiring values.

   Credentials are NOT in this file. They live in a Kubernetes Secret
   mounted at `/etc/infernix/secrets/`; `dhall/InfernixSecrets.dhall`
   declares the file paths the Haskell daemon reads from at startup.
-}

let PulsarConfig =
      { httpBaseUrl : Text
      , wsBaseUrl : Text
      , adminUrl : Text
      , serviceUrl : Text
      , tenant : Text
      , namespace : Text
      , systemNamespace : Text
      }

let MinioConfig =
      { endpoint : Text
      , region : Text
      , presignExpirySeconds : Natural
      , modelsBucket : Text
      , demoArtifactsBucket : Text
      }

let KeycloakConfig =
      { baseUrl : Text
      , realmName : Text
      , clientId : Text
      , jwksUrl : Text
      }

let DemoBackendConfig =
      { bindHost : Text
      , port : Natural
      , bridgeMode : Text
      , publicationStatePath : Text
      , demoConfigPath : Text
      }

let EngineCommandOverride = { mapKey : Text, mapValue : Text }

let EngineConfig =
      { modelCacheRoot : Text
      , modelCacheQuotaBytes : Natural
      , commandOverrides : List EngineCommandOverride
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
