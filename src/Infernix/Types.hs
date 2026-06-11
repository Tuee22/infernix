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
    ResultFamily (..),
    ResultPayload (..),
    RouteInfo (..),
    RuntimeLane (..),
    RuntimeMode (..),
    allRuntimeModes,
    apiUpstreamModeId,
    daemonRoleId,
    defaultModelBootstrapTopic,
    defaultModelsBucket,
    parseApiUpstreamMode,
    parseDaemonRole,
    parsePulsarConnectionMode,
    parseRequestFieldType,
    parseRuntimeLane,
    parseRuntimeMode,
    pulsarConnectionModeId,
    requestFieldTypeId,
    resultFamilyId,
    resultFamilyIsArtifact,
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
import Data.Maybe (fromMaybe)
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

-- | Daemon role identity. Phase 7 Sprint 7.7 renames the legacy
-- @cluster@ / @host@ vocabulary to the supported @coordinator@ /
-- @engine@ pair from the three-role daemon-topology contract:
--
--  * 'Coordinator' = stateless Pulsar coordination role. On Linux
--    substrates it runs as the in-cluster @infernix-coordinator@
--    Deployment; on Apple silicon it runs in-cluster too.
--  * 'Engine' = stateful inference role. On Linux it runs as the
--    in-cluster @infernix-engine@ Deployment under required pod
--    anti-affinity; on Apple silicon it runs as the on-host
--    @infernix service@ daemon under exclusive @engine.lock@.
data DaemonRole
  = Coordinator
  | Engine
  deriving (Eq, Ord, Read, Show)

daemonRoleId :: DaemonRole -> Text
daemonRoleId daemonRole = case daemonRole of
  Coordinator -> "coordinator"
  Engine -> "engine"

-- | Parse the supported daemon-role identifier. Accepts the new
-- @coordinator@ / @engine@ ids plus the legacy @cluster@ / @host@
-- aliases so a stale staged @.dhall@ from a pre-Sprint-7.7 build still
-- decodes; the renderer always emits the new vocabulary.
parseDaemonRole :: Text -> Maybe DaemonRole
parseDaemonRole rawValue = case Text.toLower rawValue of
  "coordinator" -> Just Coordinator
  "engine" -> Just Engine
  "cluster" -> Just Coordinator
  "host" -> Just Engine
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
    harborPort :: Int,
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
    -- | Coordinator role metadata. On Linux substrates this drives the
    -- in-cluster @infernix-coordinator@ Deployment; on Apple silicon
    -- it drives the in-cluster Pulsar coordination role too.
    -- Sprint 7.7 renamed this field from @clusterDaemon@ to track the
    -- new daemon-role vocabulary.
    coordinatorDaemon :: DaemonConfig,
    -- | Engine role metadata. On Apple silicon this is present and
    -- describes the on-host engine daemon; on Linux substrates the
    -- engine role is bound to the in-cluster @infernix-engine@
    -- Deployment and this field stays 'Nothing'. Sprint 7.7 renamed
    -- this from @hostDaemon@.
    engineDaemon :: Maybe DaemonConfig,
    requestTopics :: [Text],
    resultTopic :: Text,
    -- | Always-on MinIO bucket the coordinator's bootstrap subscription
    -- populates with platform model weights, keyed by @<modelId>/<filename>@
    -- with a @.ready@ sentinel written last (Phase 7 Sprint 7.7).
    modelsBucket :: Text,
    -- | Pulsar topic the engine publishes onto when it sees an uncached
    -- model; the coordinator's bootstrap subscription consumes it,
    -- downloads weights from the model's upstream URL, uploads them to
    -- 'modelsBucket', and acknowledges with @model.bootstrap.ready.<modelId>@
    -- (Phase 7 Sprint 7.7).
    modelBootstrapTopic :: Text,
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

-- | Phase 4 Sprint 4.15 — the closed set of per-family result contracts.
-- Each README matrix row resolves to exactly one 'ResultFamily' (via
-- 'Infernix.Models.resultFamilyForDescriptor'), which decides whether the
-- engine result rides inline in the Pulsar message ('inlineOutput') or as
-- an @infernix-demo-objects@ object reference ('objectRef'). The text
-- families ('LlmText', 'SpeechTranscription') are inline; every artifact
-- family carries an object reference.
data ResultFamily
  = LlmText
  | SpeechTranscription
  | SourceSeparation
  | AudioToMidi
  | MusicTranscription
  | ImageGeneration
  | VideoGeneration
  | AudioGeneration
  | OpticalMusicRecognition
  deriving (Eq, Ord, Read, Show, Enum, Bounded)

resultFamilyId :: ResultFamily -> Text
resultFamilyId resultFamily = case resultFamily of
  LlmText -> "llm-text"
  SpeechTranscription -> "speech-transcription"
  SourceSeparation -> "source-separation"
  AudioToMidi -> "audio-to-midi"
  MusicTranscription -> "music-transcription"
  ImageGeneration -> "image-generation"
  VideoGeneration -> "video-generation"
  AudioGeneration -> "audio-generation"
  OpticalMusicRecognition -> "optical-music-recognition"

-- | Whether a family's result is a binary artifact (written to
-- @infernix-demo-objects@ and carried as an 'objectRef') rather than
-- inline text. Only the two text families are inline.
resultFamilyIsArtifact :: ResultFamily -> Bool
resultFamilyIsArtifact resultFamily = case resultFamily of
  LlmText -> False
  SpeechTranscription -> False
  _ -> True

data InferenceRequest = InferenceRequest
  { requestModelId :: Text,
    inputText :: Text,
    -- | Phase 4 Sprint 4.15 — non-text input for the audio and image
    -- input families, carried as an @infernix-demo-objects@ object
    -- reference. 'Nothing' for the text families, which use 'inputText'.
    inputObjectRef :: Maybe Text
  }
  deriving (Eq, Read, Show)

instance FromJSON InferenceRequest where
  parseJSON = withObject "InferenceRequest" $ \value ->
    InferenceRequest
      <$> value .: "requestModelId"
      <*> value .: "inputText"
      <*> value .:? "inputObjectRef"

instance ToJSON InferenceRequest where
  toJSON requestValue =
    object
      [ "requestModelId" .= requestModelId requestValue,
        "inputText" .= inputText requestValue,
        "inputObjectRef" .= inputObjectRef requestValue
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
    createdAt :: UTCTime,
    -- Phase 7 Sprint 7.8: per-context routing fields the result-bridge
    -- uses to compute the destination conversation topic. Empty strings
    -- indicate a non-durable-context request that should bypass the
    -- bridge (legacy / Phase 4 manual-inference fallback).
    resultUserId :: Text,
    resultContextId :: Text,
    resultCausalRef :: Text
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
        "createdAt" .= formatUtc (createdAt resultValue),
        "userId" .= resultUserId resultValue,
        "contextId" .= resultContextId resultValue,
        "causalRef" .= resultCausalRef resultValue
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
      <*> (fromMaybe "" <$> value .:? "userId")
      <*> (fromMaybe "" <$> value .:? "contextId")
      <*> (fromMaybe "" <$> value .:? "causalRef")

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
        "coordinator" .= coordinatorDaemon demoConfig,
        "engine" .= engineDaemon demoConfig,
        "request_topics" .= requestTopics demoConfig,
        "result_topic" .= resultTopic demoConfig,
        "models_bucket" .= modelsBucket demoConfig,
        "model_bootstrap_topic" .= modelBootstrapTopic demoConfig,
        "engines" .= engines demoConfig,
        "models" .= models demoConfig
      ]

instance FromJSON DemoConfig where
  parseJSON = withObject "DemoConfig" $ \value -> do
    runtimeModeValue <- value .: "runtimeMode"
    requestTopicValues <- value .: "request_topics"
    resultTopicValue <- value .: "result_topic"
    daemonRoleValue <- value .:? "daemonRole" .!= defaultDaemonRole runtimeModeValue
    -- Phase 7 Sprint 7.7 renamed the JSON keys from
    -- @clusterDaemon@ / @hostDaemon@ to @coordinator@ / @engine@.
    -- Both names parse during the transition window.
    coordinatorDaemonValue <-
      do
        coordinatorMaybe <- value .:? "coordinator"
        case coordinatorMaybe of
          Just coordinator -> pure coordinator
          Nothing -> do
            clusterMaybe <- value .:? "clusterDaemon"
            case clusterMaybe of
              Just legacyCluster -> pure legacyCluster
              Nothing ->
                pure
                  ( defaultCoordinatorDaemonConfig
                      runtimeModeValue
                      requestTopicValues
                      resultTopicValue
                  )
    engineDaemonValue <-
      do
        engineMaybe <- value .:? "engine"
        case engineMaybe of
          Just engine -> pure engine
          Nothing -> do
            hostMaybe <- value .:? "hostDaemon"
            case hostMaybe of
              Just legacyHost -> pure legacyHost
              Nothing -> pure (defaultEngineDaemonConfig runtimeModeValue resultTopicValue)
    modelsBucketValue <- value .:? "models_bucket" .!= defaultModelsBucket
    modelBootstrapTopicValue <-
      value .:? "model_bootstrap_topic" .!= defaultModelBootstrapTopic
    (DemoConfig runtimeModeValue <$> value .: "edgePort")
      <*> value .: "configMapName"
      <*> value .: "generatedPath"
      <*> value .: "mountedPath"
      <*> value .: "demo_ui"
      <*> pure daemonRoleValue
      <*> pure coordinatorDaemonValue
      <*> pure engineDaemonValue
      <*> pure requestTopicValues
      <*> pure resultTopicValue
      <*> pure modelsBucketValue
      <*> pure modelBootstrapTopicValue
      <*> value .: "engines"
      <*> value .: "models"

-- | Supported always-on MinIO bucket name holding platform model weights.
-- The coordinator's bootstrap Failover subscription is the only writer; engines
-- and host daemons read from it through the per-adapter @get_model_path@ helper.
defaultModelsBucket :: Text
defaultModelsBucket = "infernix-models"

-- | Pulsar topic family the engine publishes onto when it sees an uncached
-- model, in the supported @infernix/system@ namespace. The coordinator's
-- bootstrap subscription consumes it with producer-side deduplication keyed
-- by @modelId@ so concurrent first-touch requests trigger exactly one upstream
-- download.
defaultModelBootstrapTopic :: Text
defaultModelBootstrapTopic =
  "persistent://infernix/system/model.bootstrap.request"

defaultDaemonRole :: RuntimeMode -> DaemonRole
defaultDaemonRole runtimeMode = case runtimeMode of
  AppleSilicon -> Engine
  _ -> Coordinator

defaultCoordinatorDaemonConfig :: RuntimeMode -> [Text] -> Text -> DaemonConfig
defaultCoordinatorDaemonConfig runtimeMode requestTopicValues resultTopicValue =
  DaemonConfig
    { daemonConfigRole = Coordinator,
      daemonConfigLocation = "cluster-pod",
      daemonConfigRequestTopics = requestTopicValues,
      daemonConfigResultTopic = resultTopicValue,
      daemonConfigHostBatchTopic = defaultHostBatchTopic runtimeMode,
      daemonConfigPulsarConnectionMode = ConfiguredTransport
    }

defaultEngineDaemonConfig :: RuntimeMode -> Text -> Maybe DaemonConfig
defaultEngineDaemonConfig runtimeMode resultTopicValue =
  case runtimeMode of
    AppleSilicon ->
      Just
        DaemonConfig
          { daemonConfigRole = Engine,
            daemonConfigLocation = "control-plane-host",
            daemonConfigRequestTopics = maybe [] pure (defaultHostBatchTopic runtimeMode),
            daemonConfigResultTopic = resultTopicValue,
            daemonConfigHostBatchTopic = Nothing,
            daemonConfigPulsarConnectionMode = PublicationEdgeAutoDiscovery
          }
    _ -> Nothing

defaultHostBatchTopic :: RuntimeMode -> Maybe Text
defaultHostBatchTopic runtimeMode =
  case runtimeMode of
    AppleSilicon -> Just ("persistent://infernix/demo/inference.batch." <> runtimeModeId runtimeMode <> ".host")
    _ -> Just ("persistent://infernix/demo/inference.batch." <> runtimeModeId runtimeMode)

formatUtc :: UTCTime -> String
formatUtc = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ"

parseUtc :: String -> Parser UTCTime
parseUtc rawValue =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" rawValue of
    Just parsedValue -> pure parsedValue
    Nothing -> fail ("Unsupported UTC timestamp: " <> rawValue)
