{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Phase 4 Sprint 4.13 — typed Haskell record for the
-- @dhall/InfernixCluster.dhall@ manifest. The supported contract is
-- declared in Phase 0 Sprint 0.9
-- (`DEVELOPMENT_PLAN/development_plan_standards.md` Sections T+U) and
-- detailed in `documents/engineering/cluster_config_manifest.md`.
--
-- The chart renders this Dhall record into
-- `ConfigMap/infernix-cluster-config` and mounts it read-only at
-- `/opt/infernix/cluster.dhall` in coordinator / engine / demo pods.
-- The Haskell daemon decodes the mounted file at startup so no pod
-- needs an `env:` block to receive Pulsar / MinIO / Keycloak / engine
-- wiring values. Credentials live in a separate Kubernetes Secret
-- mounted at `/etc/infernix/secrets/` and the file paths are declared
-- in `dhall/InfernixSecrets.dhall` (Sprint 7.17).
module Infernix.ClusterConfig
  ( ClusterConfig (..),
    PulsarWiring (..),
    MinioWiring (..),
    KeycloakWiring (..),
    DemoBackendWiring (..),
    EngineWiring (..),
    CoordinatorWiring (..),
    EngineCommandOverride (..),
    decodeClusterConfigFile,
    renderClusterConfig,
    renderClusterConfigSchema,
    encodeClusterConfig,
    clusterConfigGeneratedBanner,
    defaultClusterConfigMountPath,
  )
where

import Control.Exception (SomeException, displayException, try)
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (intercalate)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Dhall.Core qualified as DhallCore
import GHC.Generics (Generic)
import Infernix.DhallSchema.Reflection (renderDecoderExpected)
import Numeric.Natural (Natural)

-- | Pulsar wiring values. Maps to the @pulsar@ Dhall record. Replaces
-- the previous @INFERNIX_PULSAR_*@ env-var family.
data PulsarWiring = PulsarWiring
  { pulsarHttpBaseUrl :: Text,
    pulsarWsBaseUrl :: Text,
    pulsarAdminUrl :: Text,
    pulsarServiceUrl :: Text,
    pulsarTenant :: Text,
    pulsarNamespace :: Text,
    pulsarSystemNamespace :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall PulsarWiring where
  autoWith _ = Dhall.genericAutoWith pulsarFieldOptions

pulsarFieldOptions :: Dhall.InterpretOptions
pulsarFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "pulsarHttpBaseUrl" -> "httpBaseUrl"
        "pulsarWsBaseUrl" -> "wsBaseUrl"
        "pulsarAdminUrl" -> "adminUrl"
        "pulsarServiceUrl" -> "serviceUrl"
        "pulsarTenant" -> "tenant"
        "pulsarNamespace" -> "namespace"
        "pulsarSystemNamespace" -> "systemNamespace"
        other -> other
    }

-- | MinIO wiring values (non-credential fields only; credentials live
-- in `InfernixSecrets.dhall` under `minio.credentialsPath`).
data MinioWiring = MinioWiring
  { minioEndpoint :: Text,
    minioRegion :: Text,
    minioPresignExpirySeconds :: Natural,
    minioModelsBucket :: Text,
    minioDemoArtifactsBucket :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall MinioWiring where
  autoWith _ = Dhall.genericAutoWith minioFieldOptions

minioFieldOptions :: Dhall.InterpretOptions
minioFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "minioEndpoint" -> "endpoint"
        "minioRegion" -> "region"
        "minioPresignExpirySeconds" -> "presignExpirySeconds"
        "minioModelsBucket" -> "modelsBucket"
        "minioDemoArtifactsBucket" -> "demoArtifactsBucket"
        other -> other
    }

-- | Keycloak wiring values (non-credential fields only; admin /
-- database secrets live in `InfernixSecrets.dhall`).
data KeycloakWiring = KeycloakWiring
  { keycloakBaseUrl :: Text,
    keycloakRealmName :: Text,
    keycloakClientId :: Text,
    keycloakJwksUrl :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall KeycloakWiring where
  autoWith _ = Dhall.genericAutoWith keycloakFieldOptions

keycloakFieldOptions :: Dhall.InterpretOptions
keycloakFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "keycloakBaseUrl" -> "baseUrl"
        "keycloakRealmName" -> "realmName"
        "keycloakClientId" -> "clientId"
        "keycloakJwksUrl" -> "jwksUrl"
        other -> other
    }

-- | Demo-backend wiring values consumed by @infernix-demo@.
data DemoBackendWiring = DemoBackendWiring
  { demoBindHost :: Text,
    demoPort :: Natural,
    demoBridgeMode :: Text,
    demoPublicationStatePath :: Text,
    demoConfigFilePath :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall DemoBackendWiring where
  autoWith _ = Dhall.genericAutoWith demoBackendFieldOptions

demoBackendFieldOptions :: Dhall.InterpretOptions
demoBackendFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "demoBindHost" -> "bindHost"
        "demoPort" -> "port"
        "demoBridgeMode" -> "bridgeMode"
        "demoPublicationStatePath" -> "publicationStatePath"
        "demoConfigFilePath" -> "demoConfigPath"
        other -> other
    }

-- | One @INFERNIX_ENGINE_COMMAND_<NAME>@ override entry, encoded in
-- Dhall as a @{ mapKey, mapValue }@ list element.
data EngineCommandOverride = EngineCommandOverride
  { engineOverrideKey :: Text,
    engineOverrideValue :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall EngineCommandOverride where
  autoWith _ = Dhall.genericAutoWith engineOverrideFieldOptions

engineOverrideFieldOptions :: Dhall.InterpretOptions
engineOverrideFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "engineOverrideKey" -> "mapKey"
        "engineOverrideValue" -> "mapValue"
        other -> other
    }

-- | Engine-role wiring values: model-cache rooting + per-engine
-- command overrides previously delivered through
-- @INFERNIX_ENGINE_COMMAND_<NAME>@ env vars.
data EngineWiring = EngineWiring
  { engineModelCacheRoot :: Text,
    engineModelCacheQuotaBytes :: Natural,
    engineCommandOverrides :: [EngineCommandOverride]
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall EngineWiring where
  autoWith _ = Dhall.genericAutoWith engineFieldOptions

engineFieldOptions :: Dhall.InterpretOptions
engineFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "engineModelCacheRoot" -> "modelCacheRoot"
        "engineModelCacheQuotaBytes" -> "modelCacheQuotaBytes"
        "engineCommandOverrides" -> "commandOverrides"
        other -> other
    }

-- | Coordinator-role wiring values previously delivered via
-- @INFERNIX_CATALOG_SOURCE@, @INFERNIX_CONTROL_PLANE_CONTEXT@,
-- @INFERNIX_DAEMON_LOCATION@ env vars.
data CoordinatorWiring = CoordinatorWiring
  { coordinatorCatalogSource :: Text,
    coordinatorControlPlaneContext :: Text,
    coordinatorDaemonLocation :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall CoordinatorWiring where
  autoWith _ = Dhall.genericAutoWith coordinatorFieldOptions

coordinatorFieldOptions :: Dhall.InterpretOptions
coordinatorFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "coordinatorCatalogSource" -> "catalogSource"
        "coordinatorControlPlaneContext" -> "controlPlaneContext"
        "coordinatorDaemonLocation" -> "daemonLocation"
        other -> other
    }

-- | Full cluster manifest decoded by every coordinator + engine + demo
-- daemon at startup. The mounted Dhall file is the single source of
-- truth for runtime wiring in cluster-resident pods.
data ClusterConfig = ClusterConfig
  { clusterPulsar :: PulsarWiring,
    clusterMinio :: MinioWiring,
    clusterKeycloak :: KeycloakWiring,
    clusterDemoBackend :: DemoBackendWiring,
    clusterEngine :: EngineWiring,
    clusterCoordinator :: CoordinatorWiring
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall ClusterConfig where
  autoWith _ = Dhall.genericAutoWith clusterFieldOptions

clusterFieldOptions :: Dhall.InterpretOptions
clusterFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "clusterPulsar" -> "pulsar"
        "clusterMinio" -> "minio"
        "clusterKeycloak" -> "keycloak"
        "clusterDemoBackend" -> "demoBackend"
        "clusterEngine" -> "engine"
        "clusterCoordinator" -> "coordinator"
        other -> other
    }

-- | The supported mount path the chart writes the rendered cluster
-- ConfigMap to. Daemons running outside a cluster (host-native Apple
-- engine, unit tests) pass a different path explicitly.
defaultClusterConfigMountPath :: FilePath
defaultClusterConfigMountPath = "/opt/infernix/cluster.dhall"

clusterConfigGeneratedBanner :: String
clusterConfigGeneratedBanner =
  "{- Auto-generated by infernix cluster-config materialization -}\n"

-- | Serialize the typed cluster manifest to standalone Dhall source.
-- The chart uses the same record shape for
-- @ConfigMap/infernix-cluster-config@, while the unit suite round-trips
-- this renderer through 'decodeClusterConfigFile' so schema drift is
-- caught before the chart path is exercised.
encodeClusterConfig :: ClusterConfig -> LazyChar8.ByteString
encodeClusterConfig clusterConfig =
  LazyChar8.pack (clusterConfigGeneratedBanner <> renderClusterConfig clusterConfig)

renderClusterConfig :: ClusterConfig -> String
renderClusterConfig clusterConfig =
  unlines
    [ "{ pulsar = " <> renderPulsarWiring (clusterPulsar clusterConfig),
      ", minio = " <> renderMinioWiring (clusterMinio clusterConfig),
      ", keycloak = " <> renderKeycloakWiring (clusterKeycloak clusterConfig),
      ", demoBackend = " <> renderDemoBackendWiring (clusterDemoBackend clusterConfig),
      ", engine = " <> renderEngineWiring (clusterEngine clusterConfig),
      ", coordinator = " <> renderCoordinatorWiring (clusterCoordinator clusterConfig),
      "}"
    ]

renderClusterConfigSchema :: Either String Text
renderClusterConfigSchema =
  renderDecoderExpected (Dhall.auto @ClusterConfig)

renderPulsarWiring :: PulsarWiring -> String
renderPulsarWiring value =
  "{ httpBaseUrl = "
    <> dhallText (pulsarHttpBaseUrl value)
    <> ", wsBaseUrl = "
    <> dhallText (pulsarWsBaseUrl value)
    <> ", adminUrl = "
    <> dhallText (pulsarAdminUrl value)
    <> ", serviceUrl = "
    <> dhallText (pulsarServiceUrl value)
    <> ", tenant = "
    <> dhallText (pulsarTenant value)
    <> ", namespace = "
    <> dhallText (pulsarNamespace value)
    <> ", systemNamespace = "
    <> dhallText (pulsarSystemNamespace value)
    <> " }"

renderMinioWiring :: MinioWiring -> String
renderMinioWiring value =
  "{ endpoint = "
    <> dhallText (minioEndpoint value)
    <> ", region = "
    <> dhallText (minioRegion value)
    <> ", presignExpirySeconds = "
    <> dhallNatural (minioPresignExpirySeconds value)
    <> ", modelsBucket = "
    <> dhallText (minioModelsBucket value)
    <> ", demoArtifactsBucket = "
    <> dhallText (minioDemoArtifactsBucket value)
    <> " }"

renderKeycloakWiring :: KeycloakWiring -> String
renderKeycloakWiring value =
  "{ baseUrl = "
    <> dhallText (keycloakBaseUrl value)
    <> ", realmName = "
    <> dhallText (keycloakRealmName value)
    <> ", clientId = "
    <> dhallText (keycloakClientId value)
    <> ", jwksUrl = "
    <> dhallText (keycloakJwksUrl value)
    <> " }"

renderDemoBackendWiring :: DemoBackendWiring -> String
renderDemoBackendWiring value =
  "{ bindHost = "
    <> dhallText (demoBindHost value)
    <> ", port = "
    <> dhallNatural (demoPort value)
    <> ", bridgeMode = "
    <> dhallText (demoBridgeMode value)
    <> ", publicationStatePath = "
    <> dhallText (demoPublicationStatePath value)
    <> ", demoConfigPath = "
    <> dhallText (demoConfigFilePath value)
    <> " }"

renderEngineWiring :: EngineWiring -> String
renderEngineWiring value =
  "{ modelCacheRoot = "
    <> dhallText (engineModelCacheRoot value)
    <> ", modelCacheQuotaBytes = "
    <> dhallNatural (engineModelCacheQuotaBytes value)
    <> ", commandOverrides = "
    <> dhallList engineCommandOverrideType renderEngineCommandOverride (engineCommandOverrides value)
    <> " }"

renderEngineCommandOverride :: EngineCommandOverride -> String
renderEngineCommandOverride value =
  "{ mapKey = "
    <> dhallText (engineOverrideKey value)
    <> ", mapValue = "
    <> dhallText (engineOverrideValue value)
    <> " }"

renderCoordinatorWiring :: CoordinatorWiring -> String
renderCoordinatorWiring value =
  "{ catalogSource = "
    <> dhallText (coordinatorCatalogSource value)
    <> ", controlPlaneContext = "
    <> dhallText (coordinatorControlPlaneContext value)
    <> ", daemonLocation = "
    <> dhallText (coordinatorDaemonLocation value)
    <> " }"

dhallList :: String -> (a -> String) -> [a] -> String
dhallList itemType renderItem values =
  case values of
    [] -> "([] : List " <> itemType <> ")"
    _ -> "[ " <> intercalate ", " (map renderItem values) <> " ]"

dhallNatural :: Natural -> String
dhallNatural = show

dhallText :: Text -> String
dhallText value =
  Text.unpack ("\"" <> DhallCore.escapeText value <> "\"")

engineCommandOverrideType :: String
engineCommandOverrideType =
  "{ mapKey : Text, mapValue : Text }"

-- | Decode a materialized @InfernixCluster.dhall@ file. Errors carry the
-- supported failure context so daemon-startup flows surface them early.
decodeClusterConfigFile :: FilePath -> IO ClusterConfig
decodeClusterConfigFile filePath = do
  decoded <- try (Dhall.inputFile Dhall.auto filePath :: IO ClusterConfig)
  case decoded of
    Left err ->
      ioError
        ( userError
            ( "invalid cluster manifest Dhall at "
                <> filePath
                <> ":\n"
                <> displayException (err :: SomeException)
            )
        )
    Right value -> pure value
