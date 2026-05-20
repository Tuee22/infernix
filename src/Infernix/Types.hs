{-# LANGUAGE OverloadedStrings #-}

module Infernix.Types
  ( ApiUpstream (..),
    ApiUpstreamMode (..),
    CacheManifest (..),
    ClusterState (..),
    DaemonConfig (..),
    DaemonRole (..),
    DemoConfig (..),
    EngineBinding (..),
    ErrorResponse (..),
    InferenceRequest (..),
    InferenceResult (..),
    LifecycleProgress (..),
    ModelDescriptor (..),
    PersistentClaim (..),
    PublicationUpstream (..),
    PulsarConnectionMode (..),
    RequestField (..),
    RequestFieldType (..),
    ResultPayload (..),
    RouteInfo (..),
    RuntimeLane (..),
    RuntimeMode (..),
    allRuntimeModes,
    apiUpstreamModeId,
    daemonRoleId,
    parseApiUpstreamMode,
    parseDaemonRole,
    parsePulsarConnectionMode,
    parseRequestFieldType,
    parseRuntimeLane,
    parseRuntimeMode,
    pulsarConnectionModeId,
    requestFieldTypeId,
    runtimeLaneId,
    runtimeModeId,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (String),
    object,
    withObject,
    withText,
    (.!=),
    (.:),
    (.:?),
    (.=),
  )
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)

data RuntimeMode
  = AppleSilicon
  | LinuxCpu
  | LinuxGpu
  deriving (Eq, Ord, Read, Show)

allRuntimeModes :: [RuntimeMode]
allRuntimeModes = [AppleSilicon, LinuxCpu, LinuxGpu]

runtimeModeId :: RuntimeMode -> Text
runtimeModeId runtimeMode = case runtimeMode of
  AppleSilicon -> "apple-silicon"
  LinuxCpu -> "linux-cpu"
  LinuxGpu -> "linux-gpu"

parseRuntimeMode :: Text -> Maybe RuntimeMode
parseRuntimeMode rawValue = case Text.toLower rawValue of
  "apple-silicon" -> Just AppleSilicon
  "linux-cpu" -> Just LinuxCpu
  "linux-gpu" -> Just LinuxGpu
  _ -> Nothing

instance ToJSON RuntimeMode where
  toJSON = String . runtimeModeId

instance FromJSON RuntimeMode where
  parseJSON = withText "RuntimeMode" $ \rawValue ->
    case parseRuntimeMode rawValue of
      Just runtimeMode -> pure runtimeMode
      Nothing -> fail ("Unsupported runtime mode: " <> Text.unpack rawValue)

data DaemonRole
  = ClusterDaemon
  | HostDaemon
  deriving (Eq, Ord, Read, Show)

daemonRoleId :: DaemonRole -> Text
daemonRoleId daemonRole = case daemonRole of
  ClusterDaemon -> "cluster"
  HostDaemon -> "host"

parseDaemonRole :: Text -> Maybe DaemonRole
parseDaemonRole rawValue = case Text.toLower rawValue of
  "cluster" -> Just ClusterDaemon
  "host" -> Just HostDaemon
  _ -> Nothing

instance ToJSON DaemonRole where
  toJSON = String . daemonRoleId

instance FromJSON DaemonRole where
  parseJSON = withText "DaemonRole" $ \rawValue ->
    case parseDaemonRole rawValue of
      Just daemonRole -> pure daemonRole
      Nothing -> fail ("Unsupported daemon role: " <> Text.unpack rawValue)

data RuntimeLane
  = AppleSiliconHost
  | KindLinuxCpu
  | KindLinuxGpuGpu
  | KindLinuxGpuShared
  deriving (Eq, Ord, Read, Show)

runtimeLaneId :: RuntimeLane -> Text
runtimeLaneId AppleSiliconHost = "apple-silicon-host"
runtimeLaneId KindLinuxCpu = "kind-linux-cpu"
runtimeLaneId KindLinuxGpuGpu = "kind-linux-gpu-gpu"
runtimeLaneId KindLinuxGpuShared = "kind-linux-gpu-shared"

parseRuntimeLane :: Text -> Maybe RuntimeLane
parseRuntimeLane rawValue = case Text.toLower rawValue of
  "apple-silicon-host" -> Just AppleSiliconHost
  "kind-linux-cpu" -> Just KindLinuxCpu
  "kind-linux-gpu-gpu" -> Just KindLinuxGpuGpu
  "kind-linux-gpu-shared" -> Just KindLinuxGpuShared
  _ -> Nothing

instance ToJSON RuntimeLane where
  toJSON = String . runtimeLaneId

instance FromJSON RuntimeLane where
  parseJSON = withText "RuntimeLane" $ \rawValue ->
    case parseRuntimeLane rawValue of
      Just runtimeLane -> pure runtimeLane
      Nothing -> fail ("Unsupported runtime lane: " <> Text.unpack rawValue)

data RouteInfo = RouteInfo
  { path :: Text,
    purpose :: Text
  }
  deriving (Eq, Read, Show)

data PersistentClaim = PersistentClaim
  { namespace :: Text,
    release :: Text,
    workload :: Text,
    ordinal :: Int,
    claim :: Text,
    pvcName :: Text,
    requestedStorage :: Text
  }
  deriving (Eq, Read, Show)

data LifecycleProgress = LifecycleProgress
  { lifecycleAction :: String,
    lifecyclePhase :: String,
    lifecycleDetail :: String,
    lifecycleHeartbeatAt :: UTCTime
  }
  deriving (Eq, Read, Show)

data ClusterState = ClusterState
  { clusterPresent :: Bool,
    edgePort :: Int,
    routes :: [RouteInfo],
    storageClass :: Text,
    claims :: [PersistentClaim],
    clusterRuntimeMode :: RuntimeMode,
    kubeconfigPath :: FilePath,
    generatedDemoConfigPath :: FilePath,
    publishedDemoConfigPath :: FilePath,
    publishedConfigMapManifestPath :: FilePath,
    mountedDemoConfigPath :: FilePath,
    lifecycleProgress :: Maybe LifecycleProgress,
    updatedAt :: UTCTime
  }
  deriving (Eq, Read, Show)

data ApiUpstreamMode
  = ClusterDemoUpstream
  | DisabledUpstream
  deriving (Eq, Ord, Read, Show)

apiUpstreamModeId :: ApiUpstreamMode -> Text
apiUpstreamModeId ClusterDemoUpstream = "cluster-demo"
apiUpstreamModeId DisabledUpstream = "disabled"

parseApiUpstreamMode :: Text -> Maybe ApiUpstreamMode
parseApiUpstreamMode rawValue = case Text.toLower rawValue of
  "cluster-demo" -> Just ClusterDemoUpstream
  "disabled" -> Just DisabledUpstream
  _ -> Nothing

instance ToJSON ApiUpstreamMode where
  toJSON = String . apiUpstreamModeId

instance FromJSON ApiUpstreamMode where
  parseJSON = withText "ApiUpstreamMode" $ \rawValue ->
    case parseApiUpstreamMode rawValue of
      Just upstreamMode -> pure upstreamMode
      Nothing -> fail ("Unsupported API upstream mode: " <> Text.unpack rawValue)

data ApiUpstream = ApiUpstream
  { apiUpstreamMode :: ApiUpstreamMode,
    apiUpstreamHost :: Text,
    apiUpstreamPort :: Int
  }
  deriving (Eq, Read, Show)

data PublicationUpstream = PublicationUpstream
  { publicationUpstreamId :: Text,
    publicationUpstreamRoutePrefix :: Text,
    publicationUpstreamTargetSurface :: Text,
    publicationUpstreamHealthStatus :: Text,
    publicationUpstreamDurableBackendState :: Text
  }
  deriving (Eq, Read, Show)

data CacheManifest = CacheManifest
  { cacheRuntimeMode :: RuntimeMode,
    cacheModelId :: Text,
    cacheSelectedEngine :: Text,
    cacheDurableSourceUri :: Text,
    cacheCacheKey :: Text
  }
  deriving (Eq, Read, Show)

data DemoConfig = DemoConfig
  { configRuntimeMode :: RuntimeMode,
    configEdgePort :: Int,
    configMapName :: Text,
    generatedPath :: FilePath,
    mountedPath :: FilePath,
    demoUiEnabled :: Bool,
    activeDaemonRole :: DaemonRole,
    clusterDaemon :: DaemonConfig,
    hostDaemon :: Maybe DaemonConfig,
    requestTopics :: [Text],
    resultTopic :: Text,
    engines :: [EngineBinding],
    models :: [ModelDescriptor]
  }
  deriving (Eq, Read, Show)

data PulsarConnectionMode
  = ConfiguredTransport
  | PublicationEdgeAutoDiscovery
  deriving (Eq, Ord, Read, Show)

pulsarConnectionModeId :: PulsarConnectionMode -> Text
pulsarConnectionModeId ConfiguredTransport = "configured-transport"
pulsarConnectionModeId PublicationEdgeAutoDiscovery = "publication-edge-auto-discovery"

parsePulsarConnectionMode :: Text -> Maybe PulsarConnectionMode
parsePulsarConnectionMode rawValue = case Text.toLower rawValue of
  "configured-transport" -> Just ConfiguredTransport
  "publication-edge-auto-discovery" -> Just PublicationEdgeAutoDiscovery
  _ -> Nothing

instance ToJSON PulsarConnectionMode where
  toJSON = String . pulsarConnectionModeId

instance FromJSON PulsarConnectionMode where
  parseJSON = withText "PulsarConnectionMode" $ \rawValue ->
    case parsePulsarConnectionMode rawValue of
      Just connectionMode -> pure connectionMode
      Nothing -> fail ("Unsupported pulsar connection mode: " <> Text.unpack rawValue)

data DaemonConfig = DaemonConfig
  { daemonConfigRole :: DaemonRole,
    daemonConfigLocation :: Text,
    daemonConfigRequestTopics :: [Text],
    daemonConfigResultTopic :: Text,
    daemonConfigHostBatchTopic :: Maybe Text,
    daemonConfigPulsarConnectionMode :: PulsarConnectionMode
  }
  deriving (Eq, Read, Show)

instance ToJSON DaemonConfig where
  toJSON daemonConfig =
    object
      [ "role" .= daemonConfigRole daemonConfig,
        "location" .= daemonConfigLocation daemonConfig,
        "request_topics" .= daemonConfigRequestTopics daemonConfig,
        "result_topic" .= daemonConfigResultTopic daemonConfig,
        "host_batch_topic" .= daemonConfigHostBatchTopic daemonConfig,
        "pulsarConnectionMode" .= daemonConfigPulsarConnectionMode daemonConfig
      ]

instance FromJSON DaemonConfig where
  parseJSON = withObject "DaemonConfig" $ \value ->
    DaemonConfig
      <$> value .: "role"
      <*> value .: "location"
      <*> value .: "request_topics"
      <*> value .: "result_topic"
      <*> value .:? "host_batch_topic"
      <*> value .:? "pulsarConnectionMode" .!= ConfiguredTransport

data EngineBinding = EngineBinding
  { engineBindingName :: Text,
    engineBindingAdapterId :: Text,
    engineBindingAdapterType :: Text,
    engineBindingAdapterLocator :: Text,
    engineBindingAdapterEntrypoint :: Text,
    engineBindingSetupEntrypoint :: Text,
    engineBindingProjectDirectory :: FilePath,
    engineBindingPythonNative :: Bool
  }
  deriving (Eq, Read, Show)

instance ToJSON EngineBinding where
  toJSON engineBinding =
    object
      [ "engine" .= engineBindingName engineBinding,
        "adapterId" .= engineBindingAdapterId engineBinding,
        "adapterType" .= engineBindingAdapterType engineBinding,
        "adapterLocator" .= engineBindingAdapterLocator engineBinding,
        "adapterEntrypoint" .= engineBindingAdapterEntrypoint engineBinding,
        "setupEntrypoint" .= engineBindingSetupEntrypoint engineBinding,
        "projectDirectory" .= engineBindingProjectDirectory engineBinding,
        "pythonNative" .= engineBindingPythonNative engineBinding
      ]

instance FromJSON EngineBinding where
  parseJSON = withObject "EngineBinding" $ \value ->
    EngineBinding
      <$> value .: "engine"
      <*> value .: "adapterId"
      <*> value .: "adapterType"
      <*> value .: "adapterLocator"
      <*> value .: "adapterEntrypoint"
      <*> value .: "setupEntrypoint"
      <*> value .: "projectDirectory"
      <*> value .: "pythonNative"

data RequestFieldType
  = TextRequestField
  deriving (Eq, Ord, Read, Show)

requestFieldTypeId :: RequestFieldType -> Text
requestFieldTypeId TextRequestField = "text"

parseRequestFieldType :: Text -> Maybe RequestFieldType
parseRequestFieldType rawValue = case Text.toLower rawValue of
  "text" -> Just TextRequestField
  _ -> Nothing

instance ToJSON RequestFieldType where
  toJSON = String . requestFieldTypeId

instance FromJSON RequestFieldType where
  parseJSON = withText "RequestFieldType" $ \rawValue ->
    case parseRequestFieldType rawValue of
      Just fieldType -> pure fieldType
      Nothing -> fail ("Unsupported request field type: " <> Text.unpack rawValue)

data RequestField = RequestField
  { name :: Text,
    label :: Text,
    fieldType :: RequestFieldType
  }
  deriving (Eq, Read, Show)

instance ToJSON RequestField where
  toJSON requestField =
    object
      [ "name" .= name requestField,
        "label" .= label requestField,
        "fieldType" .= fieldType requestField
      ]

instance FromJSON RequestField where
  parseJSON = withObject "RequestField" $ \value ->
    RequestField
      <$> value .: "name"
      <*> value .: "label"
      <*> value .: "fieldType"

data ModelDescriptor = ModelDescriptor
  { matrixRowId :: Text,
    modelId :: Text,
    displayName :: Text,
    family :: Text,
    description :: Text,
    artifactType :: Text,
    referenceModel :: Text,
    downloadUrl :: Text,
    selectedEngine :: Text,
    requestShape :: [RequestField],
    runtimeMode :: RuntimeMode,
    runtimeLane :: RuntimeLane,
    requiresGpu :: Bool,
    notes :: Text
  }
  deriving (Eq, Read, Show)

instance ToJSON ModelDescriptor where
  toJSON modelDescriptor =
    object
      [ "matrixRowId" .= matrixRowId modelDescriptor,
        "modelId" .= modelId modelDescriptor,
        "displayName" .= displayName modelDescriptor,
        "family" .= family modelDescriptor,
        "description" .= description modelDescriptor,
        "artifactType" .= artifactType modelDescriptor,
        "referenceModel" .= referenceModel modelDescriptor,
        "downloadUrl" .= downloadUrl modelDescriptor,
        "selectedEngine" .= selectedEngine modelDescriptor,
        "requestShape" .= requestShape modelDescriptor,
        "runtimeMode" .= runtimeMode modelDescriptor,
        "runtimeLane" .= runtimeLane modelDescriptor,
        "requiresGpu" .= requiresGpu modelDescriptor,
        "notes" .= notes modelDescriptor
      ]

instance FromJSON ModelDescriptor where
  parseJSON = withObject "ModelDescriptor" $ \value ->
    ModelDescriptor
      <$> value .: "matrixRowId"
      <*> value .: "modelId"
      <*> value .: "displayName"
      <*> value .: "family"
      <*> value .: "description"
      <*> value .: "artifactType"
      <*> value .: "referenceModel"
      <*> value .: "downloadUrl"
      <*> value .: "selectedEngine"
      <*> value .: "requestShape"
      <*> value .: "runtimeMode"
      <*> value .: "runtimeLane"
      <*> value .: "requiresGpu"
      <*> value .: "notes"

data InferenceRequest = InferenceRequest
  { requestModelId :: Text,
    inputText :: Text
  }
  deriving (Eq, Read, Show)

instance FromJSON InferenceRequest where
  parseJSON = withObject "InferenceRequest" $ \value ->
    InferenceRequest
      <$> value .: "requestModelId"
      <*> value .: "inputText"

instance ToJSON InferenceRequest where
  toJSON requestValue =
    object
      [ "requestModelId" .= requestModelId requestValue,
        "inputText" .= inputText requestValue
      ]

data ResultPayload = ResultPayload
  { inlineOutput :: Maybe Text,
    objectRef :: Maybe Text
  }
  deriving (Eq, Read, Show)

instance ToJSON ResultPayload where
  toJSON payloadValue =
    object
      [ "inlineOutput" .= inlineOutput payloadValue,
        "objectRef" .= objectRef payloadValue
      ]

instance FromJSON ResultPayload where
  parseJSON = withObject "ResultPayload" $ \value ->
    ResultPayload
      <$> value .: "inlineOutput"
      <*> value .: "objectRef"

data InferenceResult = InferenceResult
  { requestId :: Text,
    resultModelId :: Text,
    resultMatrixRowId :: Text,
    resultRuntimeMode :: RuntimeMode,
    resultSelectedEngine :: Text,
    status :: Text,
    payload :: ResultPayload,
    createdAt :: UTCTime
  }
  deriving (Eq, Read, Show)

instance ToJSON InferenceResult where
  toJSON resultValue =
    object
      [ "requestId" .= requestId resultValue,
        "resultModelId" .= resultModelId resultValue,
        "matrixRowId" .= resultMatrixRowId resultValue,
        "runtimeMode" .= resultRuntimeMode resultValue,
        "selectedEngine" .= resultSelectedEngine resultValue,
        "status" .= status resultValue,
        "payload" .= payload resultValue,
        "createdAt" .= formatUtc (createdAt resultValue)
      ]

instance FromJSON InferenceResult where
  parseJSON = withObject "InferenceResult" $ \value ->
    InferenceResult
      <$> value .: "requestId"
      <*> value .: "resultModelId"
      <*> value .: "matrixRowId"
      <*> value .: "runtimeMode"
      <*> value .: "selectedEngine"
      <*> value .: "status"
      <*> value .: "payload"
      <*> (parseUtc =<< value .: "createdAt")

data ErrorResponse = ErrorResponse
  { errorCode :: Text,
    message :: Text
  }
  deriving (Eq, Read, Show)

instance ToJSON ErrorResponse where
  toJSON errorValue =
    object
      [ "errorCode" .= errorCode errorValue,
        "message" .= message errorValue
      ]

instance FromJSON ErrorResponse where
  parseJSON = withObject "ErrorResponse" $ \value ->
    ErrorResponse
      <$> value .: "errorCode"
      <*> value .: "message"

instance ToJSON DemoConfig where
  toJSON demoConfig =
    object
      [ "runtimeMode" .= configRuntimeMode demoConfig,
        "edgePort" .= configEdgePort demoConfig,
        "configMapName" .= configMapName demoConfig,
        "generatedPath" .= generatedPath demoConfig,
        "mountedPath" .= mountedPath demoConfig,
        "demo_ui" .= demoUiEnabled demoConfig,
        "daemonRole" .= activeDaemonRole demoConfig,
        "clusterDaemon" .= clusterDaemon demoConfig,
        "hostDaemon" .= hostDaemon demoConfig,
        "request_topics" .= requestTopics demoConfig,
        "result_topic" .= resultTopic demoConfig,
        "engines" .= engines demoConfig,
        "models" .= models demoConfig
      ]

instance FromJSON DemoConfig where
  parseJSON = withObject "DemoConfig" $ \value -> do
    runtimeModeValue <- value .: "runtimeMode"
    requestTopicValues <- value .: "request_topics"
    resultTopicValue <- value .: "result_topic"
    daemonRoleValue <- value .:? "daemonRole" .!= defaultDaemonRole runtimeModeValue
    clusterDaemonValue <-
      value
        .:? "clusterDaemon"
        .!= defaultClusterDaemonConfig runtimeModeValue requestTopicValues resultTopicValue
    hostDaemonValue <-
      value
        .:? "hostDaemon"
        .!= defaultHostDaemonConfig runtimeModeValue resultTopicValue
    (DemoConfig runtimeModeValue <$> value .: "edgePort")
      <*> value .: "configMapName"
      <*> value .: "generatedPath"
      <*> value .: "mountedPath"
      <*> value .: "demo_ui"
      <*> pure daemonRoleValue
      <*> pure clusterDaemonValue
      <*> pure hostDaemonValue
      <*> pure requestTopicValues
      <*> pure resultTopicValue
      <*> value .: "engines"
      <*> value .: "models"

defaultDaemonRole :: RuntimeMode -> DaemonRole
defaultDaemonRole runtimeMode = case runtimeMode of
  AppleSilicon -> HostDaemon
  _ -> ClusterDaemon

defaultClusterDaemonConfig :: RuntimeMode -> [Text] -> Text -> DaemonConfig
defaultClusterDaemonConfig runtimeMode requestTopicValues resultTopicValue =
  DaemonConfig
    { daemonConfigRole = ClusterDaemon,
      daemonConfigLocation = "cluster-pod",
      daemonConfigRequestTopics = requestTopicValues,
      daemonConfigResultTopic = resultTopicValue,
      daemonConfigHostBatchTopic = defaultHostBatchTopic runtimeMode,
      daemonConfigPulsarConnectionMode = ConfiguredTransport
    }

defaultHostDaemonConfig :: RuntimeMode -> Text -> Maybe DaemonConfig
defaultHostDaemonConfig runtimeMode resultTopicValue =
  case runtimeMode of
    AppleSilicon ->
      Just
        DaemonConfig
          { daemonConfigRole = HostDaemon,
            daemonConfigLocation = "control-plane-host",
            daemonConfigRequestTopics = maybe [] pure (defaultHostBatchTopic runtimeMode),
            daemonConfigResultTopic = resultTopicValue,
            daemonConfigHostBatchTopic = defaultHostBatchTopic runtimeMode,
            daemonConfigPulsarConnectionMode = PublicationEdgeAutoDiscovery
          }
    _ -> Nothing

defaultHostBatchTopic :: RuntimeMode -> Maybe Text
defaultHostBatchTopic runtimeMode =
  case runtimeMode of
    AppleSilicon -> Just ("persistent://public/default/inference.batch." <> runtimeModeId runtimeMode <> ".host")
    _ -> Nothing

formatUtc :: UTCTime -> String
formatUtc = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ"

parseUtc :: String -> Parser UTCTime
parseUtc rawValue =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" rawValue of
    Just parsedValue -> pure parsedValue
    Nothing -> fail ("Unsupported UTC timestamp: " <> rawValue)
