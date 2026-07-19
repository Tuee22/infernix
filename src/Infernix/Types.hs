{-# LANGUAGE OverloadedStrings #-}

module Infernix.Types
  ( ApiUpstream (..),
    ApiUpstreamMode (..),
    CacheManifest (..),
    ClusterLifecycle (..),
    ClusterState (..),
    ConsumerSubscriptionType (..),
    DaemonConfig (..),
    DaemonRole (..),
    DemoConfig (..),
    EngineBinding (..),
    EngineMember (..),
    EnginePool (..),
    ErrorResponse (..),
    InferenceError (..),
    InferenceMemoryBudget (..),
    InferenceMemoryResource (..),
    InferenceRequest (..),
    InferenceResult (..),
    LifecyclePhase (..),
    LifecycleTransition (..),
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
    admitModelMemory,
    clusterLifecyclePresent,
    clusterPresent,
    daemonRoleId,
    lifecyclePhaseOf,
    lifecycleTransitionAction,
    parseLifecycleTransition,
    defaultModelBootstrapTopic,
    defaultModelsBucket,
    inferenceMemoryBudgetAvailableMib,
    inferenceMemoryBudgetResourceText,
    parseApiUpstreamMode,
    parseConsumerSubscriptionType,
    parseDaemonRole,
    parseInferenceMemoryResource,
    parsePulsarConnectionMode,
    parseRequestFieldType,
    parseRuntimeLane,
    parseRuntimeMode,
    consumerSubscriptionTypeId,
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
import Data.Char (isAlphaNum)
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
-- @engine@ vocabulary and adds @webapp@ from the three-role
-- daemon-topology contract:
--
--  * 'Coordinator' = stateless Pulsar coordination role. On Linux
--    substrates it runs as the in-cluster @infernix-coordinator@
--    Deployment; on Apple silicon it runs in-cluster too.
--  * 'Engine' = stateful inference role. On Linux it runs as the
--    in-cluster @infernix-engine@ Deployment or a pool-specific
--    workload; on Apple silicon it runs as an on-host
--    @infernix service@ daemon selected by stable engine member id.
--  * 'Webapp' = stateless demo HTTP/WebSocket role. It runs as the
--    demo-gated @infernix-demo@ Deployment using @infernix service
--    --role webapp@.
data DaemonRole
  = Coordinator
  | Engine
  | Webapp
  deriving (Eq, Ord, Read, Show)

daemonRoleId :: DaemonRole -> Text
daemonRoleId daemonRole = case daemonRole of
  Coordinator -> "coordinator"
  Engine -> "engine"
  Webapp -> "webapp"

-- | Parse the supported daemon-role identifier. Accepts the new
-- @coordinator@ / @engine@ ids plus the legacy @cluster@ / @host@
-- aliases and the @frontend@ alias so stale staged @.dhall@ files
-- still decode; the renderer always emits the supported vocabulary.
parseDaemonRole :: Text -> Maybe DaemonRole
parseDaemonRole rawValue = case Text.toLower rawValue of
  "coordinator" -> Just Coordinator
  "engine" -> Just Engine
  "webapp" -> Just Webapp
  "frontend" -> Just Webapp
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

-- | Sprint 2.14 (managed-state-transition doctrine) — which transition owns an
-- in-progress lifecycle phase. Replaces the free-form @lifecycleAction :: String@
-- ("cluster-up" / "cluster-down") with a closed tag.
data LifecycleTransition
  = LifecycleBringUp
  | LifecycleTearDown
  deriving (Eq, Read, Show)

lifecycleTransitionAction :: LifecycleTransition -> String
lifecycleTransitionAction LifecycleBringUp = "cluster-up"
lifecycleTransitionAction LifecycleTearDown = "cluster-down"

parseLifecycleTransition :: String -> Maybe LifecycleTransition
parseLifecycleTransition rawValue = case rawValue of
  "cluster-up" -> Just LifecycleBringUp
  "cluster-down" -> Just LifecycleTearDown
  _ -> Nothing

instance ToJSON LifecycleTransition where
  toJSON = String . Text.pack . lifecycleTransitionAction

instance FromJSON LifecycleTransition where
  parseJSON = withText "LifecycleTransition" $ \rawValue ->
    case parseLifecycleTransition (Text.unpack rawValue) of
      Just transition -> pure transition
      Nothing -> fail ("Unsupported lifecycle transition: " <> Text.unpack rawValue)

-- | Sprint 2.14 — a typed, resumable lifecycle phase. The phase name and detail
-- remain data, but they are reachable only inside an in-progress constructor of
-- 'ClusterLifecycle', tagged by the owning 'LifecycleTransition'.
data LifecyclePhase = LifecyclePhase
  { lifecyclePhaseTransition :: LifecycleTransition,
    lifecyclePhaseName :: String,
    lifecyclePhaseDetail :: String,
    lifecyclePhaseHeartbeatAt :: UTCTime
  }
  deriving (Eq, Read, Show)

instance ToJSON LifecyclePhase where
  toJSON phaseValue =
    object
      [ "transition" .= lifecyclePhaseTransition phaseValue,
        "name" .= lifecyclePhaseName phaseValue,
        "detail" .= lifecyclePhaseDetail phaseValue,
        "heartbeatAt" .= lifecyclePhaseHeartbeatAt phaseValue
      ]

instance FromJSON LifecyclePhase where
  parseJSON = withObject "LifecyclePhase" $ \value ->
    LifecyclePhase
      <$> value .: "transition"
      <*> value .: "name"
      <*> value .: "detail"
      <*> value .: "heartbeatAt"

-- | Sprint 2.14 — the typed cluster lifecycle machine. A closed sum over the
-- mutually exclusive lifecycle positions; the in-progress positions carry a
-- consumed, resumable 'LifecyclePhase'. It replaces the
-- (@clusterPresent :: Bool@, @lifecyclePhase :: String@) pair, which could
-- encode contradictory ambient states.
data ClusterLifecycle
  = -- | no cluster is recorded (never provisioned, or teardown complete).
    ClusterAbsent
  | -- | bringing a cluster up before the Kind API is confirmed reachable.
    ClusterProvisioning LifecyclePhase
  | -- | the Kind cluster is present; bring-up phases are still finishing.
    ClusterActivating LifecyclePhase
  | -- | the cluster is present and idle.
    ClusterReady
  | -- | the cluster is present and being torn down.
    ClusterTearingDown LifecyclePhase
  deriving (Eq, Read, Show)

instance ToJSON ClusterLifecycle where
  toJSON lifecycle = case lifecycle of
    ClusterAbsent -> object ["position" .= ("absent" :: Text)]
    ClusterReady -> object ["position" .= ("ready" :: Text)]
    ClusterProvisioning phaseValue ->
      object ["position" .= ("provisioning" :: Text), "phase" .= phaseValue]
    ClusterActivating phaseValue ->
      object ["position" .= ("activating" :: Text), "phase" .= phaseValue]
    ClusterTearingDown phaseValue ->
      object ["position" .= ("tearing-down" :: Text), "phase" .= phaseValue]

instance FromJSON ClusterLifecycle where
  parseJSON = withObject "ClusterLifecycle" $ \value -> do
    position <- value .: "position" :: Parser Text
    case position of
      "absent" -> pure ClusterAbsent
      "ready" -> pure ClusterReady
      "provisioning" -> ClusterProvisioning <$> value .: "phase"
      "activating" -> ClusterActivating <$> value .: "phase"
      "tearing-down" -> ClusterTearingDown <$> value .: "phase"
      _ -> fail ("Unsupported cluster lifecycle position: " <> Text.unpack position)

-- | Whether the recorded lifecycle means the Kind cluster is present. True from
-- 'ClusterActivating' onward and during teardown; False while still
-- provisioning or when absent.
clusterLifecyclePresent :: ClusterLifecycle -> Bool
clusterLifecyclePresent lifecycle = case lifecycle of
  ClusterAbsent -> False
  ClusterProvisioning _ -> False
  ClusterActivating _ -> True
  ClusterReady -> True
  ClusterTearingDown _ -> True

data ClusterState = ClusterState
  { clusterLifecycle :: ClusterLifecycle,
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
    updatedAt :: UTCTime
  }
  deriving (Eq, Read, Show)

-- | Sprint 2.14 — the legacy @clusterPresent@ projection. Readers keep calling
-- @clusterPresent state@ unchanged; the value is now derived from the single
-- authoritative 'clusterLifecycle' rather than an independent ambient boolean.
clusterPresent :: ClusterState -> Bool
clusterPresent = clusterLifecyclePresent . clusterLifecycle

-- | Sprint 7.29 — the in-progress lifecycle phase, if any. Replaces the retired
-- @lifecycleProgress :: ClusterState -> Maybe LifecycleProgress@ projection and
-- its stringly 'LifecycleProgress' shape: readers now consume the typed
-- 'LifecyclePhase' (with its closed 'LifecycleTransition') directly from the
-- authoritative 'clusterLifecycle'.
lifecyclePhaseOf :: ClusterState -> Maybe LifecyclePhase
lifecyclePhaseOf state = case clusterLifecycle state of
  ClusterProvisioning phaseValue -> Just phaseValue
  ClusterActivating phaseValue -> Just phaseValue
  ClusterTearingDown phaseValue -> Just phaseValue
  ClusterAbsent -> Nothing
  ClusterReady -> Nothing

instance ToJSON RouteInfo where
  toJSON routeValue =
    object ["path" .= path routeValue, "purpose" .= purpose routeValue]

instance FromJSON RouteInfo where
  parseJSON = withObject "RouteInfo" $ \value ->
    RouteInfo <$> value .: "path" <*> value .: "purpose"

instance ToJSON PersistentClaim where
  toJSON claimValue =
    object
      [ "namespace" .= namespace claimValue,
        "release" .= release claimValue,
        "workload" .= workload claimValue,
        "ordinal" .= ordinal claimValue,
        "claim" .= claim claimValue,
        "pvcName" .= pvcName claimValue,
        "requestedStorage" .= requestedStorage claimValue
      ]

instance FromJSON PersistentClaim where
  parseJSON = withObject "PersistentClaim" $ \value ->
    PersistentClaim
      <$> value .: "namespace"
      <*> value .: "release"
      <*> value .: "workload"
      <*> value .: "ordinal"
      <*> value .: "claim"
      <*> value .: "pvcName"
      <*> value .: "requestedStorage"

instance ToJSON ClusterState where
  toJSON state =
    object
      [ "clusterLifecycle" .= clusterLifecycle state,
        "edgePort" .= edgePort state,
        "harborPort" .= harborPort state,
        "routes" .= routes state,
        "storageClass" .= storageClass state,
        "claims" .= claims state,
        "clusterRuntimeMode" .= clusterRuntimeMode state,
        "kubeconfigPath" .= kubeconfigPath state,
        "generatedDemoConfigPath" .= generatedDemoConfigPath state,
        "publishedDemoConfigPath" .= publishedDemoConfigPath state,
        "publishedConfigMapManifestPath" .= publishedConfigMapManifestPath state,
        "mountedDemoConfigPath" .= mountedDemoConfigPath state,
        "updatedAt" .= updatedAt state
      ]

instance FromJSON ClusterState where
  parseJSON = withObject "ClusterState" $ \value ->
    ClusterState
      <$> value .: "clusterLifecycle"
      <*> value .: "edgePort"
      <*> value .: "harborPort"
      <*> value .: "routes"
      <*> value .: "storageClass"
      <*> value .: "claims"
      <*> value .: "clusterRuntimeMode"
      <*> value .: "kubeconfigPath"
      <*> value .: "generatedDemoConfigPath"
      <*> value .: "publishedDemoConfigPath"
      <*> value .: "publishedConfigMapManifestPath"
      <*> value .: "mountedDemoConfigPath"
      <*> value .: "updatedAt"

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
    -- | Webapp role metadata. The in-cluster @infernix-demo@
    -- Deployment now starts through @infernix service --role webapp@
    -- instead of the retired @infernix-demo@ executable.
    webappDaemon :: DaemonConfig,
    -- | Engine role metadata. The first entry is the generic engine
    -- daemon (Apple host engine, or the Linux native-runner fallback
    -- topic). Linux GPU framework engines add one entry per isolated
    -- per-engine image, selected by @infernix service --role engine
    -- --engine-name <name>@.
    engineDaemons :: [DaemonConfig],
    enginePools :: [EnginePool],
    engineMembers :: [EngineMember],
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
    models :: [ModelDescriptor],
    -- | Phase 4 Sprint 4.27 — the typed per-substrate memory budget used
    -- by runtime admission. Enforced budgets reject only the oversized
    -- request; they no longer invalidate the whole generated catalog.
    inferenceMemoryBudget :: InferenceMemoryBudget
  }
  deriving (Eq, Read, Show)

data InferenceMemoryResource
  = UnifiedHostRam
  | PodRam
  | GpuVram
  deriving (Eq, Ord, Read, Show)

inferenceMemoryBudgetResourceText :: InferenceMemoryResource -> Text
inferenceMemoryBudgetResourceText resource = case resource of
  UnifiedHostRam -> "unified-host-ram"
  PodRam -> "pod-ram"
  GpuVram -> "gpu-vram"

parseInferenceMemoryResource :: Text -> Maybe InferenceMemoryResource
parseInferenceMemoryResource rawValue = case Text.toLower rawValue of
  "unified-host-ram" -> Just UnifiedHostRam
  "pod-ram" -> Just PodRam
  "gpu-vram" -> Just GpuVram
  _ -> Nothing

instance ToJSON InferenceMemoryResource where
  toJSON = String . inferenceMemoryBudgetResourceText

instance FromJSON InferenceMemoryResource where
  parseJSON = withText "InferenceMemoryResource" $ \rawValue ->
    case parseInferenceMemoryResource rawValue of
      Just resource -> pure resource
      Nothing -> fail ("Unsupported inference memory resource: " <> Text.unpack rawValue)

data InferenceMemoryBudget
  = EnforcedMemoryBudget
      { memoryBudgetResource :: InferenceMemoryResource,
        memoryBudgetSource :: Text,
        memoryBudgetAvailableMib :: Int
      }
  | UnenforcedMemoryBudget
      { memoryBudgetReason :: Text
      }
  deriving (Eq, Read, Show)

instance ToJSON InferenceMemoryBudget where
  toJSON budget = case budget of
    EnforcedMemoryBudget {memoryBudgetResource, memoryBudgetSource, memoryBudgetAvailableMib} ->
      object
        [ "kind" .= ("enforced" :: Text),
          "resource" .= memoryBudgetResource,
          "source" .= memoryBudgetSource,
          "availableMib" .= memoryBudgetAvailableMib
        ]
    UnenforcedMemoryBudget {memoryBudgetReason} ->
      object
        [ "kind" .= ("unenforced" :: Text),
          "reason" .= memoryBudgetReason
        ]

instance FromJSON InferenceMemoryBudget where
  parseJSON = withObject "InferenceMemoryBudget" $ \value -> do
    kind <- value .: "kind"
    case Text.toLower kind of
      "enforced" ->
        EnforcedMemoryBudget
          <$> value .: "resource"
          <*> value .: "source"
          <*> value .: "availableMib"
      "unenforced" ->
        UnenforcedMemoryBudget <$> value .:? "reason" .!= "explicitly unenforced"
      _ -> fail ("Unsupported inference memory budget kind: " <> Text.unpack kind)

inferenceMemoryBudgetAvailableMib :: InferenceMemoryBudget -> Maybe Int
inferenceMemoryBudgetAvailableMib budget = case budget of
  EnforcedMemoryBudget {memoryBudgetAvailableMib} -> Just memoryBudgetAvailableMib
  UnenforcedMemoryBudget {} -> Nothing

data InferenceError
  = ModelMemoryLimitExceeded
  { inferenceErrorModelId :: Text,
    inferenceErrorRequiredMib :: Int,
    inferenceErrorAvailableMib :: Int,
    inferenceErrorResource :: InferenceMemoryResource,
    inferenceErrorSource :: Text
  }
  deriving (Eq, Read, Show)

instance ToJSON InferenceError where
  toJSON errorValue = case errorValue of
    ModelMemoryLimitExceeded {inferenceErrorModelId, inferenceErrorRequiredMib, inferenceErrorAvailableMib, inferenceErrorResource, inferenceErrorSource} ->
      object
        [ "tag" .= ("ModelMemoryLimitExceeded" :: Text),
          "modelId" .= inferenceErrorModelId,
          "requiredMib" .= inferenceErrorRequiredMib,
          "availableMib" .= inferenceErrorAvailableMib,
          "resource" .= inferenceErrorResource,
          "source" .= inferenceErrorSource
        ]

instance FromJSON InferenceError where
  parseJSON = withObject "InferenceError" $ \value -> do
    tag <- value .: "tag"
    case tag of
      "ModelMemoryLimitExceeded" ->
        ModelMemoryLimitExceeded
          <$> value .: "modelId"
          <*> value .: "requiredMib"
          <*> value .: "availableMib"
          <*> value .: "resource"
          <*> value .: "source"
      _ -> fail ("Unsupported inference error: " <> Text.unpack tag)

admitModelMemory :: InferenceMemoryBudget -> ModelDescriptor -> Maybe InferenceError
admitModelMemory budget model =
  case budget of
    UnenforcedMemoryBudget {} -> Nothing
    EnforcedMemoryBudget {memoryBudgetResource, memoryBudgetSource, memoryBudgetAvailableMib}
      | modelRamFootprintMib model > memoryBudgetAvailableMib ->
          Just
            ModelMemoryLimitExceeded
              { inferenceErrorModelId = modelId model,
                inferenceErrorRequiredMib = modelRamFootprintMib model,
                inferenceErrorAvailableMib = memoryBudgetAvailableMib,
                inferenceErrorResource = memoryBudgetResource,
                inferenceErrorSource = memoryBudgetSource
              }
      | otherwise -> Nothing

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

data ConsumerSubscriptionType
  = ConsumerShared
  | ConsumerExclusive
  | ConsumerFailover
  deriving (Eq, Ord, Read, Show)

consumerSubscriptionTypeId :: ConsumerSubscriptionType -> Text
consumerSubscriptionTypeId subscriptionType =
  case subscriptionType of
    ConsumerShared -> "shared"
    ConsumerExclusive -> "exclusive"
    ConsumerFailover -> "failover"

parseConsumerSubscriptionType :: Text -> Maybe ConsumerSubscriptionType
parseConsumerSubscriptionType rawValue =
  case Text.toLower rawValue of
    "shared" -> Just ConsumerShared
    "exclusive" -> Just ConsumerExclusive
    "failover" -> Just ConsumerFailover
    _ -> Nothing

instance ToJSON ConsumerSubscriptionType where
  toJSON = String . consumerSubscriptionTypeId

instance FromJSON ConsumerSubscriptionType where
  parseJSON = withText "ConsumerSubscriptionType" $ \rawValue ->
    case parseConsumerSubscriptionType rawValue of
      Just subscriptionType -> pure subscriptionType
      Nothing -> fail ("Unsupported consumer subscription type: " <> Text.unpack rawValue)

data DaemonConfig = DaemonConfig
  { daemonConfigRole :: DaemonRole,
    daemonConfigLocation :: Text,
    daemonConfigMemberId :: Maybe Text,
    daemonConfigRequestTopics :: [Text],
    daemonConfigResultTopic :: Text,
    daemonConfigPulsarConnectionMode :: PulsarConnectionMode,
    daemonConfigConsumerSubscriptionType :: Maybe ConsumerSubscriptionType
  }
  deriving (Eq, Read, Show)

instance ToJSON DaemonConfig where
  toJSON daemonConfig =
    object
      [ "role" .= daemonConfigRole daemonConfig,
        "location" .= daemonConfigLocation daemonConfig,
        "memberId" .= daemonConfigMemberId daemonConfig,
        "request_topics" .= daemonConfigRequestTopics daemonConfig,
        "result_topic" .= daemonConfigResultTopic daemonConfig,
        "pulsarConnectionMode" .= daemonConfigPulsarConnectionMode daemonConfig,
        "consumerSubscriptionType" .= daemonConfigConsumerSubscriptionType daemonConfig
      ]

instance FromJSON DaemonConfig where
  parseJSON = withObject "DaemonConfig" $ \value ->
    DaemonConfig
      <$> value .: "role"
      <*> value .: "location"
      <*> value .:? "memberId"
      <*> value .: "request_topics"
      <*> value .: "result_topic"
      <*> value .:? "pulsarConnectionMode" .!= ConfiguredTransport
      <*> value .:? "consumerSubscriptionType"

data EnginePool = EnginePool
  { enginePoolId :: Text,
    enginePoolRuntimeMode :: RuntimeMode,
    enginePoolModelIds :: [Text],
    enginePoolMemberIds :: [Text],
    enginePoolSubscriptionType :: ConsumerSubscriptionType,
    enginePoolMaxInflightPerMember :: Int
  }
  deriving (Eq, Read, Show)

instance ToJSON EnginePool where
  toJSON pool =
    object
      [ "id" .= enginePoolId pool,
        "runtimeMode" .= enginePoolRuntimeMode pool,
        "models" .= enginePoolModelIds pool,
        "members" .= enginePoolMemberIds pool,
        "subscription" .= enginePoolSubscriptionType pool,
        "maxInflightPerMember" .= enginePoolMaxInflightPerMember pool
      ]

instance FromJSON EnginePool where
  parseJSON = withObject "EnginePool" $ \value ->
    EnginePool
      <$> value .: "id"
      <*> value .: "runtimeMode"
      <*> value .: "models"
      <*> value .: "members"
      <*> value .: "subscription"
      <*> value .: "maxInflightPerMember"

data EngineMember = EngineMember
  { engineMemberId :: Text,
    engineMemberRuntimeMode :: RuntimeMode,
    engineMemberLocation :: Text,
    engineMemberPoolIds :: [Text]
  }
  deriving (Eq, Read, Show)

instance ToJSON EngineMember where
  toJSON member =
    object
      [ "id" .= engineMemberId member,
        "runtimeMode" .= engineMemberRuntimeMode member,
        "location" .= engineMemberLocation member,
        "pools" .= engineMemberPoolIds member
      ]

instance FromJSON EngineMember where
  parseJSON = withObject "EngineMember" $ \value ->
    EngineMember
      <$> value .: "id"
      <*> value .: "runtimeMode"
      <*> value .: "location"
      <*> value .: "pools"

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
    notes :: Text,
    -- | Phase 4 Sprint 4.26 — conservative peak host-resident memory
    -- footprint (MiB) for one serialized inference of this model on the
    -- unified-memory / CPU execution path. This is the binding constraint
    -- on @apple-silicon@, where model memory is host RAM; the on-host
    -- engine's admission control ('Infernix.Runtime' critical section)
    -- and 'Infernix.DemoConfig.validateDemoConfig' reject a model whose
    -- footprint exceeds the active 'InferenceMemoryBudget'. Values are
    -- conservative per-engine defaults until measured peak-RSS / VRAM passes
    -- refine them.
    modelRamFootprintMib :: Int
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
        "notes" .= notes modelDescriptor,
        "modelRamFootprintMib" .= modelRamFootprintMib modelDescriptor
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
      <*> value .:? "modelRamFootprintMib" .!= 0

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
    inputObjectRef :: Maybe Text,
    -- | Phase 7 Sprint 7.28 — durable-context ownership fields retained
    -- from the dispatcher envelope so worker dispatch can derive the
    -- generated artifact prefix. Direct/manual inference leaves these empty.
    requestUserId :: Maybe Text,
    requestContextId :: Maybe Text
  }
  deriving (Eq, Read, Show)

instance FromJSON InferenceRequest where
  parseJSON = withObject "InferenceRequest" $ \value ->
    InferenceRequest
      <$> value .: "requestModelId"
      <*> value .: "inputText"
      <*> value .:? "inputObjectRef"
      <*> value .:? "requestUserId"
      <*> value .:? "requestContextId"

instance ToJSON InferenceRequest where
  toJSON requestValue =
    object
      [ "requestModelId" .= requestModelId requestValue,
        "inputText" .= inputText requestValue,
        "inputObjectRef" .= inputObjectRef requestValue,
        "requestUserId" .= requestUserId requestValue,
        "requestContextId" .= requestContextId requestValue
      ]

data ResultPayload = ResultPayload
  { inlineOutput :: Maybe Text,
    objectRef :: Maybe Text,
    inferenceError :: Maybe InferenceError
  }
  deriving (Eq, Read, Show)

instance ToJSON ResultPayload where
  toJSON payloadValue =
    object
      [ "inlineOutput" .= inlineOutput payloadValue,
        "objectRef" .= objectRef payloadValue,
        "inferenceError" .= inferenceError payloadValue
      ]

instance FromJSON ResultPayload where
  parseJSON = withObject "ResultPayload" $ \value ->
    ResultPayload
      <$> value .: "inlineOutput"
      <*> value .: "objectRef"
      <*> value .:? "inferenceError"

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
        "webapp" .= webappDaemon demoConfig,
        "engineDaemons" .= engineDaemons demoConfig,
        "enginePools" .= enginePools demoConfig,
        "engineMembers" .= engineMembers demoConfig,
        "request_topics" .= requestTopics demoConfig,
        "result_topic" .= resultTopic demoConfig,
        "models_bucket" .= modelsBucket demoConfig,
        "model_bootstrap_topic" .= modelBootstrapTopic demoConfig,
        "engines" .= engines demoConfig,
        "models" .= models demoConfig,
        "inferenceMemoryBudget" .= inferenceMemoryBudget demoConfig
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
    webappDaemonValue <-
      value
        .:? "webapp"
        .!= defaultWebappDaemonConfig runtimeModeValue requestTopicValues resultTopicValue
    enginePoolValues <- value .:? "enginePools" .!= []
    engineMemberValues <- value .:? "engineMembers" .!= []
    parsedEngineDaemonValues <-
      value .:? "engineDaemons" .!= []
    let engineDaemonValues =
          if null parsedEngineDaemonValues
            then deriveEngineDaemonConfigs runtimeModeValue enginePoolValues engineMemberValues resultTopicValue
            else parsedEngineDaemonValues
    modelsBucketValue <- value .:? "models_bucket" .!= defaultModelsBucket
    modelBootstrapTopicValue <-
      value .:? "model_bootstrap_topic" .!= defaultModelBootstrapTopic
    inferenceMemoryBudgetValue <-
      do
        maybeBudget <- value .:? "inferenceMemoryBudget"
        case maybeBudget of
          Just budget -> pure budget
          Nothing -> do
            legacyBudgetMib <- value .:? "inferenceRamBudgetMib" .!= 0
            pure (legacyInferenceMemoryBudget runtimeModeValue legacyBudgetMib)
    (DemoConfig runtimeModeValue <$> value .: "edgePort")
      <*> value .: "configMapName"
      <*> value .: "generatedPath"
      <*> value .: "mountedPath"
      <*> value .: "demo_ui"
      <*> pure daemonRoleValue
      <*> pure coordinatorDaemonValue
      <*> pure webappDaemonValue
      <*> pure engineDaemonValues
      <*> pure enginePoolValues
      <*> pure engineMemberValues
      <*> pure requestTopicValues
      <*> pure resultTopicValue
      <*> pure modelsBucketValue
      <*> pure modelBootstrapTopicValue
      <*> value .: "engines"
      <*> value .: "models"
      <*> pure inferenceMemoryBudgetValue

legacyInferenceMemoryBudget :: RuntimeMode -> Int -> InferenceMemoryBudget
legacyInferenceMemoryBudget runtimeMode availableMib =
  EnforcedMemoryBudget
    { memoryBudgetResource = legacyResource runtimeMode,
      memoryBudgetSource = "legacy-inferenceRamBudgetMib",
      memoryBudgetAvailableMib = max 0 availableMib
    }
  where
    legacyResource mode = case mode of
      AppleSilicon -> UnifiedHostRam
      LinuxCpu -> PodRam
      LinuxGpu -> GpuVram

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
defaultCoordinatorDaemonConfig _runtimeMode requestTopicValues resultTopicValue =
  DaemonConfig
    { daemonConfigRole = Coordinator,
      daemonConfigLocation = "cluster-pod",
      daemonConfigMemberId = Nothing,
      daemonConfigRequestTopics = requestTopicValues,
      daemonConfigResultTopic = resultTopicValue,
      daemonConfigPulsarConnectionMode = ConfiguredTransport,
      daemonConfigConsumerSubscriptionType = Just ConsumerShared
    }

defaultWebappDaemonConfig :: RuntimeMode -> [Text] -> Text -> DaemonConfig
defaultWebappDaemonConfig _runtimeMode requestTopicValues resultTopicValue =
  DaemonConfig
    { daemonConfigRole = Webapp,
      daemonConfigLocation = "cluster-pod",
      daemonConfigMemberId = Nothing,
      daemonConfigRequestTopics = requestTopicValues,
      daemonConfigResultTopic = resultTopicValue,
      daemonConfigPulsarConnectionMode = ConfiguredTransport,
      daemonConfigConsumerSubscriptionType = Just ConsumerShared
    }

deriveEngineDaemonConfigs :: RuntimeMode -> [EnginePool] -> [EngineMember] -> Text -> [DaemonConfig]
deriveEngineDaemonConfigs runtimeMode pools members resultTopicValue =
  map engineDaemonConfigForMember members
  where
    engineDaemonConfigForMember member =
      DaemonConfig
        { daemonConfigRole = Engine,
          daemonConfigLocation = engineMemberLocation member,
          daemonConfigMemberId = Just (engineMemberId member),
          daemonConfigRequestTopics = derivedEngineMemberRequestTopics runtimeMode pools member,
          daemonConfigResultTopic = resultTopicValue,
          daemonConfigPulsarConnectionMode =
            if runtimeMode == AppleSilicon
              then PublicationEdgeAutoDiscovery
              else ConfiguredTransport,
          daemonConfigConsumerSubscriptionType = Just ConsumerShared
        }

derivedEngineMemberRequestTopics :: RuntimeMode -> [EnginePool] -> EngineMember -> [Text]
derivedEngineMemberRequestTopics runtimeMode pools member =
  [ derivedEnginePoolTopicForMode runtimeMode (enginePoolId pool) modelIdValue
  | pool <- pools,
    enginePoolId pool `elem` engineMemberPoolIds member,
    engineMemberId member `elem` enginePoolMemberIds pool,
    modelIdValue <- enginePoolModelIds pool
  ]

derivedEnginePoolTopicForMode :: RuntimeMode -> Text -> Text -> Text
derivedEnginePoolTopicForMode runtimeMode poolId modelIdValue =
  "persistent://infernix/demo/inference.batch."
    <> runtimeModeId runtimeMode
    <> ".pool."
    <> topicSegment poolId
    <> ".model."
    <> topicSegment modelIdValue

topicSegment :: Text -> Text
topicSegment =
  Text.map replaceInvalid
  where
    replaceInvalid character
      | isAlphaNum character || character == '-' || character == '_' || character == '.' = character
      | otherwise = '-'

formatUtc :: UTCTime -> String
formatUtc = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ"

parseUtc :: String -> Parser UTCTime
parseUtc rawValue =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" rawValue of
    Just parsedValue -> pure parsedValue
    Nothing -> fail ("Unsupported UTC timestamp: " <> rawValue)
