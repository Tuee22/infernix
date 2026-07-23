{-# LANGUAGE OverloadedStrings #-}

module Infernix.Types
  ( ApiUpstream (..),
    ApiUpstreamMode (..),
    CacheManifest (..),
    ClusterLifecycle (..),
    ClusterOwner (..),
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
    HostMemoryPartition,
    MemoryCeiling,
    MemoryGrant,
    ModelMemoryFootprint,
    PodMemoryLimit (..),
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
    grantMemoryCeiling,
    hostPartitionForCapacity,
    hostPartitionHeadroomMib,
    hostPartitionInferenceCapacityMib,
    hostPartitionPhysicalMib,
    hostPartitionVmReserveMib,
    inferenceMemoryBudgetCapacityMib,
    inferenceMemoryBudgetResource,
    inferenceMemoryBudgetResourceText,
    inferenceMemoryBudgetSource,
    cappedEngineResidentCeilingSource,
    memoryCeilingMib,
    minHostHeadroomMib,
    modelMemoryLimitExceededErrorCode,
    mkHostMemoryPartition,
    mkModelMemoryFootprint,
    modelMemoryFootprintMib,
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
  | -- | Sprint 2.15 — the cluster is present but a test suite is actively
    -- mutating it (a drained node, an over-scaled deployment). A distinct term
    -- from the operator's idle 'ClusterReady', so a SIGKILLed @infernix test all@
    -- leaves a persisted, detectable dirty position rather than a false
    -- steady-state; the consumed 'LifecyclePhase' names the in-flight mutation
    -- for reconcile-on-next-@cluster up@.
    ClusterMutating LifecyclePhase
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
    ClusterMutating phaseValue ->
      object ["position" .= ("mutating" :: Text), "phase" .= phaseValue]
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
      "mutating" -> ClusterMutating <$> value .: "phase"
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
  ClusterMutating _ -> True
  ClusterTearingDown _ -> True

-- | Sprint 2.15 (cluster-ownership doctrine) — who owns the single persisted
-- cluster slot. The operator's @infernix cluster up@ mints 'OperatorOwned'; the
-- test harness mints 'HarnessOwned'. The teardown surface consumes this owner as
-- typed evidence (see @Infernix.Cluster.ClusterTeardownAuthority@), so the
-- harness's seizure of the slot fails closed on an operator's running cluster
-- instead of destroying it. Canonical doctrine:
-- documents/architecture/managed_state_transitions.md.
data ClusterOwner
  = -- | brought up by an operator's @infernix cluster up@; the safe default a
    -- pre-migration (ownerless) persisted document decodes to, so an unowned
    -- but present cluster is protected rather than destroyed.
    OperatorOwned
  | -- | brought up by the test harness for a validation run; the only owner the
    -- harness seizure is permitted to tear down.
    HarnessOwned
  deriving (Eq, Read, Show)

instance ToJSON ClusterOwner where
  toJSON OperatorOwned = String "operator"
  toJSON HarnessOwned = String "harness"

instance FromJSON ClusterOwner where
  parseJSON = withText "ClusterOwner" $ \rawValue ->
    case rawValue of
      "operator" -> pure OperatorOwned
      "harness" -> pure HarnessOwned
      _ -> fail ("Unsupported cluster owner: " <> Text.unpack rawValue)

data ClusterState = ClusterState
  { clusterLifecycle :: ClusterLifecycle,
    clusterOwner :: ClusterOwner,
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
  ClusterMutating phaseValue -> Just phaseValue
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
        "clusterOwner" .= clusterOwner state,
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
      -- Sprint 2.15 — a pre-migration (ownerless) document decodes to the safe
      -- default 'OperatorOwned' so the harness seizure fails closed on it rather
      -- than destroying an unowned-but-present cluster.
      <*> value .:? "clusterOwner" .!= OperatorOwned
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

-- | Phase 4 Sprint 4.31 — a checked partition of physical host RAM. The
-- constructor is hidden; 'mkHostMemoryPartition' is the only mint, and it
-- rejects a split that oversubscribes physical RAM or whose headroom is too
-- small to cover the co-tenants that share the host with inference (the OS, the
-- control-plane binary, and the routed end-to-end browser). A partition whose
-- pieces exceed physical, or whose headroom cannot cover its co-tenants, is not
-- a constructible term. See
-- 'documents/architecture/bounded_inference_memory.md'.
data HostMemoryPartition = HostMemoryPartition
  { hostPartitionPhysicalMib :: Int,
    hostPartitionVmReserveMib :: Int,
    hostPartitionHeadroomMib :: Int,
    hostPartitionInferenceCapacityMib :: Int
  }
  deriving (Eq, Read, Show)

-- | The minimum host headroom (MiB) a 'HostMemoryPartition' must hold back for
-- the host's inference co-tenants: the OS (~2 GiB), the host-native
-- control-plane binary (~256 MiB), the routed-E2E Chromium + Node surface
-- (~3 GiB), and the worst-case inter-poll watchdog overshoot (~768 MiB). The
-- superseded fixed @appleHostReserveMib = 3072@ did not cover the routed
-- end-to-end browser and allowed a host OOM.
minHostHeadroomMib :: Int
minHostHeadroomMib = 6144

-- | The only 'HostMemoryPartition' mint. @physical = vmReserve + headroom +
-- inferenceCapacity@; a negative inference capacity means the VM pledge plus
-- headroom oversubscribe physical RAM (rejected), and a headroom below
-- 'minHostHeadroomMib' cannot cover the co-tenants (rejected). The resulting
-- @inferenceCapacity@ is the admission budget the on-host engine draws from.
mkHostMemoryPartition :: Int -> Int -> Int -> Either String HostMemoryPartition
mkHostMemoryPartition physicalMib vmReserveMib headroomMib
  | physicalMib <= 0 =
      Left ("host memory partition requires positive physical RAM, got " <> show physicalMib <> " MiB")
  | vmReserveMib < 0 || headroomMib < 0 =
      Left "host memory partition vmReserve and headroom must be non-negative"
  | headroomMib < minHostHeadroomMib =
      Left
        ( "host memory partition headroom "
            <> show headroomMib
            <> " MiB cannot cover the OS + control-plane + routed-E2E browser co-tenants (minimum "
            <> show minHostHeadroomMib
            <> " MiB)"
        )
  | inferenceCapacityMib < 0 =
      Left
        ( "host memory partition oversubscribes physical RAM: vmReserve "
            <> show vmReserveMib
            <> " MiB + headroom "
            <> show headroomMib
            <> " MiB exceed physical "
            <> show physicalMib
            <> " MiB"
        )
  | otherwise =
      Right
        HostMemoryPartition
          { hostPartitionPhysicalMib = physicalMib,
            hostPartitionVmReserveMib = vmReserveMib,
            hostPartitionHeadroomMib = headroomMib,
            hostPartitionInferenceCapacityMib = inferenceCapacityMib
          }
  where
    inferenceCapacityMib = physicalMib - vmReserveMib - headroomMib

instance ToJSON HostMemoryPartition where
  toJSON partition =
    object
      [ "physicalMib" .= hostPartitionPhysicalMib partition,
        "vmReserveMib" .= hostPartitionVmReserveMib partition,
        "headroomMib" .= hostPartitionHeadroomMib partition,
        "inferenceCapacityMib" .= hostPartitionInferenceCapacityMib partition
      ]

instance FromJSON HostMemoryPartition where
  parseJSON = withObject "HostMemoryPartition" $ \value -> do
    physicalMib <- value .: "physicalMib"
    vmReserveMib <- value .: "vmReserveMib"
    headroomMib <- value .: "headroomMib"
    case mkHostMemoryPartition physicalMib vmReserveMib headroomMib of
      Right partition -> pure partition
      Left partitionError -> fail partitionError

-- | Phase 4 Sprint 4.31 — the descriptive substrate-enforced limit. On
-- @linux-cpu@ / @linux-gpu@ the pod cgroup memory limit / CUDA allocator bound
-- the engine subprocess inside its own container, so host death is already
-- impossible; this record names that already-enforced limit for admission and
-- observability.
data PodMemoryLimit = PodMemoryLimit
  { podMemoryLimitResource :: InferenceMemoryResource,
    podMemoryLimitSource :: Text,
    podMemoryLimitMib :: Int
  }
  deriving (Eq, Read, Show)

instance ToJSON PodMemoryLimit where
  toJSON podLimit =
    object
      [ "resource" .= podMemoryLimitResource podLimit,
        "source" .= podMemoryLimitSource podLimit,
        "limitMib" .= podMemoryLimitMib podLimit
      ]

instance FromJSON PodMemoryLimit where
  parseJSON = withObject "PodMemoryLimit" $ \value ->
    PodMemoryLimit
      <$> value .: "resource"
      <*> value .: "source"
      <*> value .: "limitMib"

-- | Phase 4 Sprint 4.31 — the typed per-substrate memory budget that names its
-- enforcer. There is no "enforced by nobody" arm: @apple-silicon@ is
-- host-enforced by the grant plus the 'proc_pid_rusage' watchdog against a
-- checked 'HostMemoryPartition'; @linux-cpu@ / @linux-gpu@ are substrate-enforced
-- by the pod cgroup / VRAM limit the descriptive 'PodMemoryLimit' records.
data InferenceMemoryBudget
  = HostEnforcedBudget HostMemoryPartition
  | SubstrateEnforcedBudget PodMemoryLimit
  deriving (Eq, Read, Show)

-- | The stable source string recorded for a host-enforced admission decision.
hostMemoryPartitionSource :: Text
hostMemoryPartitionSource = "host-memory-partition-inference-capacity"

instance ToJSON InferenceMemoryBudget where
  toJSON budget = case budget of
    HostEnforcedBudget partition ->
      object
        [ "kind" .= ("host-enforced" :: Text),
          "partition" .= partition
        ]
    SubstrateEnforcedBudget podLimit ->
      object
        [ "kind" .= ("substrate-enforced" :: Text),
          "podLimit" .= podLimit
        ]

instance FromJSON InferenceMemoryBudget where
  parseJSON = withObject "InferenceMemoryBudget" $ \value -> do
    kind <- value .: "kind"
    case Text.toLower kind of
      "host-enforced" ->
        HostEnforcedBudget <$> value .: "partition"
      "substrate-enforced" ->
        SubstrateEnforcedBudget <$> value .: "podLimit"
      _ -> fail ("Unsupported inference memory budget kind: " <> Text.unpack kind)

-- | The admission capacity (MiB) a budget draws from: the partition's inference
-- capacity for a host-enforced budget, or the pod/VRAM limit for a
-- substrate-enforced one.
inferenceMemoryBudgetCapacityMib :: InferenceMemoryBudget -> Int
inferenceMemoryBudgetCapacityMib budget = case budget of
  HostEnforcedBudget partition -> hostPartitionInferenceCapacityMib partition
  SubstrateEnforcedBudget podLimit -> podMemoryLimitMib podLimit

inferenceMemoryBudgetResource :: InferenceMemoryBudget -> InferenceMemoryResource
inferenceMemoryBudgetResource budget = case budget of
  HostEnforcedBudget _ -> UnifiedHostRam
  SubstrateEnforcedBudget podLimit -> podMemoryLimitResource podLimit

inferenceMemoryBudgetSource :: InferenceMemoryBudget -> Text
inferenceMemoryBudgetSource budget = case budget of
  HostEnforcedBudget _ -> hostMemoryPartitionSource
  SubstrateEnforcedBudget podLimit -> podMemoryLimitSource podLimit

-- | Phase 4 Sprint 4.31 — a required per-model peak-resident memory footprint
-- (MiB). The constructor is hidden; 'mkModelMemoryFootprint' rejects a
-- non-positive value, so a model admitted on an absent or zero footprint (the
-- superseded bare-@Int@ that decoded to @0@ and silently disabled admission) is
-- unrepresentable.
newtype ModelMemoryFootprint = ModelMemoryFootprint Int
  deriving (Eq, Ord, Read, Show)

mkModelMemoryFootprint :: Int -> Either String ModelMemoryFootprint
mkModelMemoryFootprint mib
  | mib > 0 = Right (ModelMemoryFootprint mib)
  | otherwise = Left ("model RAM footprint must be a positive MiB value, got " <> show mib)

modelMemoryFootprintMib :: ModelMemoryFootprint -> Int
modelMemoryFootprintMib (ModelMemoryFootprint mib) = mib

-- | Phase 4 Sprint 4.30 — the admitted resident-memory ceiling (MiB) an engine
-- subprocess is bounded to. Equal to the admitted model's declared footprint.
-- The constructor is hidden; a ceiling exists only inside a 'MemoryGrant'.
newtype MemoryCeiling = MemoryCeiling Int
  deriving (Eq, Ord, Read, Show)

memoryCeilingMib :: MemoryCeiling -> Int
memoryCeilingMib (MemoryCeiling mib) = mib

-- | Phase 4 Sprint 4.30 — the typed proof that a model's footprint fit its
-- budget. The constructor is hidden and 'admitModelMemory' is the sole mint, so
-- an engine subprocess launched without an admission grant is not a
-- constructible term. The capped-engine kernel
-- ('Infernix.Runtime.CappedEngine.withCappedEngine') is the sole consumer and
-- bounds the subprocess's resident memory to the carried 'MemoryCeiling'.
newtype MemoryGrant = MemoryGrant MemoryCeiling
  deriving (Eq, Read, Show)

grantMemoryCeiling :: MemoryGrant -> MemoryCeiling
grantMemoryCeiling (MemoryGrant ceilingValue) = ceilingValue

-- | Phase 4 Sprint 4.30 — the internal 'ErrorResponse' code the capped-engine
-- kernel raises when a running engine subprocess breaches its admitted
-- 'MemoryCeiling' (the @apple-silicon@ watchdog killed its process group, or the
-- Linux pod cgroup OOM-killed it). The runtime recognizes this code and rebuilds
-- it into a typed @status=failed@ 'ModelMemoryLimitExceeded' result rather than a
-- generic worker failure, so a ceiling breach is a clean typed terminal outcome,
-- never a host OOM.
modelMemoryLimitExceededErrorCode :: Text
modelMemoryLimitExceededErrorCode = "model_memory_limit_exceeded"

-- | Phase 4 Sprint 4.30 — the @inferenceErrorSource@ a runtime resident-memory
-- ceiling breach reports (the model was admitted but its actual footprint
-- exceeded its admitted ceiling and the capped-engine kernel terminated it),
-- distinct from the pre-admission budget source a genuinely over-budget model
-- reports. Consumers distinguish the two fail-closed paths by this source.
cappedEngineResidentCeilingSource :: Text
cappedEngineResidentCeilingSource = "capped-engine-resident-ceiling"

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

-- | Phase 4 Sprint 4.30 — the single honest admission mint. Admission compares
-- the model's required footprint against the budget's capacity and, on success,
-- mints a 'MemoryGrant' carrying a 'MemoryCeiling' equal to that footprint.
-- "Admitted" is no longer a proof-free @Nothing@ but a value that could only
-- exist if the footprint fit the budget; over-budget is a typed
-- 'ModelMemoryLimitExceeded' naming the required and available MiB, the resource,
-- and the enforcing source. This is the only producer of 'MemoryGrant'; the
-- capped-engine kernel is the only consumer.
admitModelMemory :: InferenceMemoryBudget -> ModelDescriptor -> Either InferenceError MemoryGrant
admitModelMemory budget model
  | requiredMib > availableMib =
      Left
        ModelMemoryLimitExceeded
          { inferenceErrorModelId = modelId model,
            inferenceErrorRequiredMib = requiredMib,
            inferenceErrorAvailableMib = availableMib,
            inferenceErrorResource = inferenceMemoryBudgetResource budget,
            inferenceErrorSource = inferenceMemoryBudgetSource budget
          }
  | otherwise = Right (MemoryGrant (MemoryCeiling requiredMib))
  where
    requiredMib = modelMemoryFootprintMib (modelRamFootprint model)
    availableMib = inferenceMemoryBudgetCapacityMib budget

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
    -- | Phase 4 Sprint 4.31 — the required peak host-resident memory
    -- footprint for one serialized inference of this model on the
    -- unified-memory / CPU execution path, a 'ModelMemoryFootprint' whose
    -- hidden constructor rejects a non-positive value (superseding the
    -- bare-@Int@ that decoded to @0@ and silently disabled admission). This is
    -- the binding constraint on @apple-silicon@, where model memory is host
    -- RAM; 'admitModelMemory' rejects a model whose footprint exceeds the active
    -- 'InferenceMemoryBudget', and the admitted footprint becomes the
    -- capped-engine kernel's 'MemoryCeiling'. Values are conservative per-engine
    -- defaults until measured peak-RSS / VRAM passes refine them.
    modelRamFootprint :: ModelMemoryFootprint
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
        "modelRamFootprintMib" .= modelMemoryFootprintMib (modelRamFootprint modelDescriptor)
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
      <*> (value .: "modelRamFootprintMib" >>= either fail pure . mkModelMemoryFootprint)

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

-- | Decode a pre-Sprint-4.31 config that still carries a bare
-- @inferenceRamBudgetMib@ integer into the enforcer-named budget. On
-- @apple-silicon@ the integer becomes the inference capacity of a synthesized
-- 'HostMemoryPartition' (headroom held back at 'minHostHeadroomMib'); on Linux it
-- becomes the substrate-enforced pod / VRAM limit.
legacyInferenceMemoryBudget :: RuntimeMode -> Int -> InferenceMemoryBudget
legacyInferenceMemoryBudget runtimeMode availableMib = case runtimeMode of
  AppleSilicon -> HostEnforcedBudget (hostPartitionForCapacity (max 0 availableMib))
  LinuxCpu -> SubstrateEnforcedBudget (PodMemoryLimit PodRam "legacy-inferenceRamBudgetMib" (max 0 availableMib))
  LinuxGpu -> SubstrateEnforcedBudget (PodMemoryLimit GpuVram "legacy-inferenceRamBudgetMib" (max 0 availableMib))

-- | Synthesize a valid 'HostMemoryPartition' whose inference capacity is a given
-- MiB value, holding back exactly 'minHostHeadroomMib' of headroom and no VM
-- reserve. Used by the legacy-config and discovery-failure fallback paths where
-- the real physical / VM-pledge split is unknown; the result is always
-- constructible (@physical = capacity + minHostHeadroomMib@, no oversubscription).
hostPartitionForCapacity :: Int -> HostMemoryPartition
hostPartitionForCapacity capacityMib =
  case mkHostMemoryPartition (max 0 capacityMib + minHostHeadroomMib) 0 minHostHeadroomMib of
    Right partition -> partition
    Left partitionError -> error ("internal: synthesized host memory partition must be constructible: " <> partitionError)

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
