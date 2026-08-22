{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RoleAnnotations #-}

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
    EngineAdapterType (..),
    engineAdapterTypeId,
    parseEngineAdapterType,
    EngineBinding (..),
    EngineMember (..),
    EngineMachineCount,
    engineMachineCount,
    engineMachineCountValue,
    singleEngineMachine,
    EnginePool (..),
    ErrorResponse (..),
    InferenceError (..),
    InferenceMemoryBudget (..),
    InferenceRequest (..),
    InferenceResult (..),
    HostMemoryPartition,
    HostClaimablePool,
    ConcurrentHostPoolClaim,
    HostResidentResource,
    KnownResource,
    ModelExecutionShape (..),
    ModelGeometry (..),
    ModelLoadStrategy (..),
    ModelMemoryRequirement,
    ModelResourceRequirement (..),
    Resource (..),
    resourceValue,
    PodMemoryLimit (..),
    PodMemoryLimitSource (..),
    podMemoryLimitSourceText,
    parsePodMemoryLimitSource,
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
    clusterLifecyclePresent,
    clusterPresent,
    daemonRoleId,
    lifecyclePhaseOf,
    lifecycleTransitionAction,
    parseLifecycleTransition,
    defaultModelBootstrapTopic,
    defaultModelsBucket,
    hostPartitionForCapacity,
    hostPartitionHeadroomMib,
    hostPartitionInferenceCapacityMib,
    hostPartitionPhysicalMib,
    hostPartitionVmReserveMib,
    hostPartitionClaimablePoolMib,
    hostPartitionToolchainAccountMib,
    mkHostClaimablePool,
    hostClaimablePoolMib,
    hostClaimablePoolToolchainAccountMib,
    toolchainSharePercent,
    mkConcurrentHostPoolClaim,
    inferenceMemoryBudgetCapacityMib,
    inferenceMemoryBudgetPodLimits,
    inferenceMemoryBudgetResource,
    resourceText,
    inferenceMemoryBudgetSource,
    cappedEngineResidentCeilingSource,
    minHostHeadroomMib,
    modelMemoryLimitExceededErrorCode,
    modelRequirementUnderivableErrorCode,
    cappedEngineRefusedAtCeilingSource,
    mkHostMemoryPartition,
    mkHostAndDeviceRequirement,
    mkHostResidentRequirement,
    modelDeviceRequirement,
    modelHostResidencyRequirement,
    modelMemoryRequirementMib,
    modelResourceRequirementHostMib,
    modelResourceRequirementDeviceMib,
    requiresGpu,
    parseApiUpstreamMode,
    parseConsumerSubscriptionType,
    parseDaemonRole,
    parseResource,
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
    runtimeLaneForMode,
    clusterDaemonLocation,
    engineMemberLocationForMode,
    defaultMaxInflightPerMember,
    defaultModelCacheQuotaBytes,
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

-- | The lane a model runs in, a total function of the runtime mode and whether
-- the model uses the device. Phase 8 Sprint 8.10 retired the generated
-- @runtimeLane@ field in favour of this derivation.
runtimeLaneForMode :: RuntimeMode -> Bool -> RuntimeLane
runtimeLaneForMode runtimeModeValue gpuRequired = case runtimeModeValue of
  AppleSilicon -> AppleSiliconHost
  LinuxCpu -> KindLinuxCpu
  LinuxGpu
    | gpuRequired -> KindLinuxGpuGpu
    | otherwise -> KindLinuxGpuShared

-- | Where a coordinator or webapp daemon runs. Both are in-cluster on every
-- supported substrate, so this is a constant rather than a generated field.
clusterDaemonLocation :: Text
clusterDaemonLocation = "cluster-pod"

-- | Where an engine member runs: on the Apple control-plane host, and in a pod
-- on the Linux substrates. Phase 8 Sprint 8.10 retired the generated per-member
-- @location@ field in favour of this derivation.
engineMemberLocationForMode :: RuntimeMode -> Text
engineMemberLocationForMode runtimeModeValue = case runtimeModeValue of
  AppleSilicon -> "control-plane-host"
  LinuxCpu -> clusterDaemonLocation
  LinuxGpu -> clusterDaemonLocation

-- | In-flight requests a pool grants one member at a time.
--
-- Phase 8 Sprint 8.10 retired the generated per-pool knob. One engine process
-- per machine holds one KV cache and one copy of every loaded weight, so a
-- second concurrent request on the same member competes with the first for the
-- machine's whole admitted budget; the supported value is one, and a wire field
-- that may only ever hold one value is a field with nothing to say.
defaultMaxInflightPerMember :: Int
defaultMaxInflightPerMember = 1

-- | Phase 8 Sprint 8.11 — the model-cache quota a machine contract declares.
--
-- One constant, one concept. Before this sprint the cluster engine's generated
-- wiring said 64 GiB and the Apple host worker carried its own 32 GiB literal
-- for the same cache, and nothing made the two agree because nothing connected
-- them: they were two independent numbers describing one thing. The quota is now
-- a machine fact, generated into the machine contract from this default, and the
-- cluster engine wiring is generated from the same value.
defaultModelCacheQuotaBytes :: Integer
defaultModelCacheQuotaBytes = 68719476736

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
  | -- | Sprint 6.43 — a test-suite chaos mutation (node drain, deployment
    -- over-scale, cordon) in flight; a persisted 'ClusterMutating' phase tagged
    -- with this transition is reconciled on the next @cluster up@.
    LifecycleMutate
  deriving (Eq, Read, Show)

lifecycleTransitionAction :: LifecycleTransition -> String
lifecycleTransitionAction LifecycleBringUp = "cluster-up"
lifecycleTransitionAction LifecycleTearDown = "cluster-down"
lifecycleTransitionAction LifecycleMutate = "cluster-mutate"

parseLifecycleTransition :: String -> Maybe LifecycleTransition
parseLifecycleTransition rawValue = case rawValue of
  "cluster-up" -> Just LifecycleBringUp
  "cluster-down" -> Just LifecycleTearDown
  "cluster-mutate" -> Just LifecycleMutate
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
--
-- Sprint 6.45 — this type is additionally used promoted (@DataKinds@) as the
-- owner index of @Infernix.Cluster.ClusterTeardownAuthority@, selected at a mint
-- site by the @Infernix.Cluster.SClusterOwner@ singleton. The index only stops
-- an authority minted for one owner from being substituted where the other is
-- required; which owner a live cluster actually has stays a runtime observation.
-- Adding or renaming a constructor therefore changes a kind as well as a type.
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
    -- | Phase 8 Sprint 8.12 — the engine member identities this cluster
    -- deploys, in declared order.
    --
    -- The fleet is cluster state because it is a property of what was brought
    -- up, not of what a renderer would generate now: the rollout wait list, the
    -- scale targets, and the generated Helm overlay all have to name the same
    -- machines the Kind topology was created for. A pre-fleet state document
    -- decodes to the empty list, which reads as "one engine machine, named the
    -- way it always was" — the deployed single-node topology.
    clusterEngineMemberIds :: [Text],
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
        "clusterEngineMemberIds" .= clusterEngineMemberIds state,
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
      -- A pre-fleet document names no members; the single-machine deployment is
      -- the safe reading, and it is also the only one the rest of the state
      -- describes.
      <*> value .:? "clusterEngineMemberIds" .!= []
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
    configMapName :: Text,
    generatedPath :: FilePath,
    mountedPath :: FilePath,
    demoUiEnabled :: Bool,
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
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.38 — the physical resource a quantity is about.
--
-- This is the /only/ name for a resource in the repository. It is used at the
-- value level for the wire and for error payloads, and promoted with
-- @DataKinds@ to index every memory ceiling, grant, enforcer, enforcer plan,
-- and requirement, so a host quantity handed to a device admission is not a
-- term. The retired shape carried the same three resources twice — a promoted
-- kind in the execution planner and an ordinary value-level enumeration here —
-- joined by hand-written functions that had to agree with one another by
-- inspection and that nothing could check, because each was total over its own
-- input. Two enumerations for one concept are two chances to disagree, and the
-- disagreement is silent because both compile.
--
-- The constructor spellings are the promoted kind's, deliberately: the
-- compile-fail fixtures pin GHC's diagnostics by substring on @HostRam@,
-- @PodRam@, and @NvidiaVram@, so renaming one makes those fixtures pass or fail
-- on whether the new name happens to appear elsewhere in the error text.
data Resource
  = HostRam
  | PodRam
  | NvidiaVram
  deriving (Eq, Ord, Read, Show)

-- | The one demotion from the promoted kind to its value.
--
-- Every site that needs to report which resource a statically-indexed value is
-- about reads it from here, so the index and the reported value cannot
-- disagree. The retired shape wrote that correspondence out once per consumer:
-- a witness-to-value map in the admission path, a shape-to-list map in the
-- placement projection, and a live-resources-to-value map on the executable —
-- the last of which answered pod RAM for every device placement by
-- construction, which is how a device breach was published as a host breach.
-- The method takes any value already indexed by the resource — a witness, a
-- grant, a ceiling, a requirement — so demotion needs no proxy and no ambiguous
-- type: the caller always has the indexed value in hand at the site that has to
-- report which resource it is about.
class KnownResource (resource :: Resource) where
  resourceValue :: f resource -> Resource

instance KnownResource 'HostRam where
  resourceValue _ = HostRam

instance KnownResource 'PodRam where
  resourceValue _ = PodRam

instance KnownResource 'NvidiaVram where
  resourceValue _ = NvidiaVram

-- | The two indices that name memory resident on the executing machine: unified
-- host RAM on the Apple lane and the container's pod RAM on the Linux lanes.
--
-- They are two lanes' names for one physical quantity — bytes the engine holds
-- on the machine — which is why one derived host-residency term may be admitted
-- against either. Device memory is deliberately not an instance: a host
-- residency figure is not a statement about the card, and this class is what
-- stops it being handed to a device admission.
class HostResidentResource (resource :: Resource)

instance HostResidentResource 'HostRam

instance HostResidentResource 'PodRam

resourceText :: Resource -> Text
resourceText resource = case resource of
  HostRam -> "unified-host-ram"
  PodRam -> "pod-ram"
  NvidiaVram -> "gpu-vram"

parseResource :: Text -> Maybe Resource
parseResource rawValue = case Text.toLower rawValue of
  "unified-host-ram" -> Just HostRam
  "pod-ram" -> Just PodRam
  "gpu-vram" -> Just NvidiaVram
  _ -> Nothing

instance ToJSON Resource where
  toJSON = String . resourceText

instance FromJSON Resource where
  parseJSON = withText "Resource" $ \rawValue ->
    case parseResource rawValue of
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
--
-- The partition additionally carries the /other occupant/ of the pool it
-- divides. Splitting physical RAM says what inference may hold; it says nothing
-- about the Haskell toolchain account drawn from the same non-virtual-machine
-- pool, and a ledger blind to that account is how a fully-assigned pool gets
-- spent twice. 'hostPartitionToolchainAccountMib' is that term, and
-- 'mkConcurrentHostPoolClaim' is the only way to assert the two are fundable at
-- once — an assertion the arithmetic refuses on every host whose partition
-- spends its pool. Canonical doctrine:
-- 'documents/architecture/bounded_host_memory.md'.
data HostMemoryPartition = HostMemoryPartition
  { hostPartitionPhysicalMib :: Int,
    hostPartitionVmReserveMib :: Int,
    hostPartitionHeadroomMib :: Int,
    hostPartitionInferenceCapacityMib :: Int,
    -- | The one claimable pool this split divides, in MiB: physical RAM less
    -- the virtual-machine reserve. Both occupants are derived from this single
    -- quantity, so neither is computed from a figure blind to the other.
    hostPartitionClaimablePoolMib :: Int,
    -- | The toolchain account the same pool funds, in MiB — the pool's other
    -- occupant, recorded here so the sum is checkable rather than unchecked.
    hostPartitionToolchainAccountMib :: Int
  }
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.31 — the one non-virtual-machine pool both host occupants
-- draw from, in MiB.
--
-- The constructor is hidden and 'mkHostClaimablePool' is the only mint, because
-- the defect this type closes is two modules each computing "the memory this
-- host offers" from its own figure. The checked inference partition and the
-- Haskell toolchain account are now both derived from one value of this type.
newtype HostClaimablePool = HostClaimablePool Int
  deriving (Eq, Ord, Show)

-- | The toolchain account's share of the claimable pool, as a percentage.
--
-- Half. The other half covers the Kind cluster this repository also runs on the
-- development host, the operator's desktop session, and the memory the doctrine
-- names as attributable to no process at all. It is a declared policy number,
-- not a measured one, and it is the only such number in the ledger.
toolchainSharePercent :: Int
toolchainSharePercent = 50

-- | The only 'HostClaimablePool' mint: physical RAM less the memory reserved
-- away from it.
--
-- On Darwin the reserve is the active Colima pledge; on Linux it is whatever
-- the cgroup maximum withholds from installed physical memory. Both lanes
-- therefore describe the same quantity — what this machine actually offers a
-- host-native claimant — rather than two figures that happen to agree.
mkHostClaimablePool :: Int -> Int -> Either String HostClaimablePool
mkHostClaimablePool physicalMib reservedMib
  | physicalMib <= 0 =
      Left
        ( "host claimable pool requires positive physical RAM, got "
            <> show physicalMib
            <> " MiB"
        )
  | reservedMib < 0 =
      Left
        ( "host claimable pool reserve must be non-negative, got "
            <> show reservedMib
            <> " MiB"
        )
  | poolMib <= 0 =
      Left
        ( "host claimable pool is empty: a reserve of "
            <> show reservedMib
            <> " MiB meets or exceeds physical "
            <> show physicalMib
            <> " MiB, leaving nothing for either occupant"
        )
  | otherwise = Right (HostClaimablePool (fromInteger poolMib))
  where
    poolMib = toInteger physicalMib - toInteger reservedMib

-- | The pool, in MiB.
hostClaimablePoolMib :: HostClaimablePool -> Int
hostClaimablePoolMib (HostClaimablePool poolMib) = poolMib

-- | The toolchain account this pool funds, in MiB.
hostClaimablePoolToolchainAccountMib :: HostClaimablePool -> Int
hostClaimablePoolToolchainAccountMib (HostClaimablePool poolMib) =
  fromInteger (toInteger poolMib * toInteger toolchainSharePercent `div` 100)

-- | Phase 4 Sprint 4.31 — evidence that a claimable pool funds /both/ of its
-- occupants at the same time.
--
-- There is no exported constructor and 'mkConcurrentHostPoolClaim' is the only
-- mint, so a caller cannot assume concurrency; it has to obtain it, and the
-- arithmetic refuses whenever the split plus the toolchain account exceed the
-- pool. On the supported development host it always refuses: a 64 GiB machine
-- under a 48 GiB Colima pledge has a 16384 MiB pool that the partition spends
-- entirely — 6144 MiB of headroom plus 10240 MiB of inference capacity — so the
-- 8192 MiB account would have to come out of a pool with no residue. The
-- occupants are alternatives, admitted one at a time against a held host claim,
-- and this type is what makes the alternative-versus-addend distinction a
-- compile-time one rather than a comment.
data ConcurrentHostPoolClaim = ConcurrentHostPoolClaim
  { concurrentClaimPoolMib :: Int,
    concurrentClaimResidueMib :: Int
  }
  deriving (Eq, Show)

-- | The only 'ConcurrentHostPoolClaim' mint.
mkConcurrentHostPoolClaim ::
  HostMemoryPartition -> Either String ConcurrentHostPoolClaim
mkConcurrentHostPoolClaim partition
  | claimedMib > toInteger poolMib =
      Left
        ( "the host claimable pool of "
            <> show poolMib
            <> " MiB cannot fund both occupants at once: headroom "
            <> show (hostPartitionHeadroomMib partition)
            <> " MiB + inference capacity "
            <> show (hostPartitionInferenceCapacityMib partition)
            <> " MiB + toolchain account "
            <> show accountMib
            <> " MiB overcommit it by "
            <> show (claimedMib - toInteger poolMib)
            <> " MiB; the occupants are alternatives admitted one at a time, "
            <> "not addends"
        )
  | otherwise =
      Right
        ConcurrentHostPoolClaim
          { concurrentClaimPoolMib = poolMib,
            concurrentClaimResidueMib = fromInteger (toInteger poolMib - claimedMib)
          }
  where
    poolMib = hostPartitionClaimablePoolMib partition
    accountMib = hostPartitionToolchainAccountMib partition
    claimedMib =
      toInteger (hostPartitionHeadroomMib partition)
        + toInteger (hostPartitionInferenceCapacityMib partition)
        + toInteger accountMib

-- | The minimum host headroom (MiB) a 'HostMemoryPartition' must hold back for
-- the host's inference co-tenants: the OS (~2 GiB), the host-native
-- control-plane binary (~256 MiB), the routed-E2E Chromium + Node surface
-- (~3 GiB), and the worst-case inter-poll watchdog overshoot (~768 MiB). The
-- superseded fixed @appleHostReserveMib = 3072@ did not cover the routed
-- end-to-end browser and allowed a host OOM.
minHostHeadroomMib :: Int
minHostHeadroomMib = 6144

-- | The only 'HostMemoryPartition' mint. @physical = vmReserve + headroom +
-- inferenceCapacity@; a non-positive inference capacity means the VM pledge plus
-- headroom exhaust or oversubscribe physical RAM (rejected), and a headroom below
-- 'minHostHeadroomMib' cannot cover the co-tenants (rejected). The resulting
-- @inferenceCapacity@ is the admission budget the on-host engine draws from.
--
-- Phase 4 Sprint 4.34 tightened @> physical@ to @>= physical@. Exactly-equal
-- reservations produced a constructible zero-capacity partition, and a
-- zero-capacity partition is not a smaller budget — it is a daemon that starts,
-- passes every check, and can answer nothing, because every model's positive
-- footprint exceeds it. Refusing to construct it is the same argument the
-- headroom floor already makes one line above.
mkHostMemoryPartition :: Int -> Int -> Int -> Either String HostMemoryPartition
mkHostMemoryPartition physicalMib vmReserveMib headroomMib = do
  checkPositivePhysical
  checkNonNegativeSplit
  checkHeadroomFloor
  checkRemainingCapacity
  -- The single claimable-pool quantity both occupants are derived from. The
  -- inference capacity is this pool less the held-back headroom, and the
  -- toolchain account is this pool's declared share, so neither is computed
  -- from a figure that is blind to the other.
  pool <- mkHostClaimablePool physicalMib vmReserveMib
  pure
    HostMemoryPartition
      { hostPartitionPhysicalMib = physicalMib,
        hostPartitionVmReserveMib = vmReserveMib,
        hostPartitionHeadroomMib = headroomMib,
        hostPartitionInferenceCapacityMib = hostClaimablePoolMib pool - headroomMib,
        hostPartitionClaimablePoolMib = hostClaimablePoolMib pool,
        hostPartitionToolchainAccountMib = hostClaimablePoolToolchainAccountMib pool
      }
  where
    checkPositivePhysical
      | physicalMib > 0 = Right ()
      | otherwise =
          Left
            ( "host memory partition requires positive physical RAM, got "
                <> show physicalMib
                <> " MiB"
            )
    checkNonNegativeSplit
      | vmReserveMib >= 0 && headroomMib >= 0 = Right ()
      | otherwise =
          Left "host memory partition vmReserve and headroom must be non-negative"
    checkHeadroomFloor
      | headroomMib >= minHostHeadroomMib = Right ()
      | otherwise =
          Left
            ( "host memory partition headroom "
                <> show headroomMib
                <> " MiB cannot cover the OS + control-plane + routed-E2E browser co-tenants (minimum "
                <> show minHostHeadroomMib
                <> " MiB)"
            )
    checkRemainingCapacity
      | reservedMib < toInteger physicalMib = Right ()
      | otherwise =
          Left
            ( "host memory partition leaves no inference capacity: vmReserve "
                <> show vmReserveMib
                <> " MiB + headroom "
                <> show headroomMib
                <> " MiB meet or exceed physical "
                <> show physicalMib
                <> " MiB"
            )
    reservedMib = toInteger vmReserveMib + toInteger headroomMib

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

-- | Phase 8 Sprint 8.9 — which already-enforced substrate limit a
-- 'PodMemoryLimit' describes.
--
-- This was a free 'Text' with no refiner anywhere: the generated wire carried
-- it verbatim, the only validation was a non-blank check in the execution-plan
-- compiler, and the value flowed out through the proto envelope and into the
-- browser as user-visible provenance. The production set was always exactly
-- these two, and an enforcer source is a property of the code that enforces it,
-- so the closed sum is the honest type. The host-enforced arm's source is
-- 'hostMemoryPartitionSource' and is deliberately absent here: a pod limit
-- cannot name the host partition.
data PodMemoryLimitSource
  = -- | the engine pod's cgroup memory limit (@linux-cpu@, and the RAM half of
    -- @linux-gpu@)
    ClusterEnginePodMemoryLimit
  | -- | the NVIDIA device VRAM budget (the device half of @linux-gpu@)
    LinuxGpuVramBudget
  deriving (Eq, Ord, Read, Show)

podMemoryLimitSourceText :: PodMemoryLimitSource -> Text
podMemoryLimitSourceText limitSource = case limitSource of
  ClusterEnginePodMemoryLimit -> "cluster-engine-pod-memory-limit"
  LinuxGpuVramBudget -> "linux-gpu-vram-budget"

parsePodMemoryLimitSource :: Text -> Maybe PodMemoryLimitSource
parsePodMemoryLimitSource rawValue = case Text.toLower rawValue of
  "cluster-engine-pod-memory-limit" -> Just ClusterEnginePodMemoryLimit
  "linux-gpu-vram-budget" -> Just LinuxGpuVramBudget
  _ -> Nothing

instance ToJSON PodMemoryLimitSource where
  toJSON = String . podMemoryLimitSourceText

instance FromJSON PodMemoryLimitSource where
  parseJSON = withText "PodMemoryLimitSource" $ \rawValue ->
    case parsePodMemoryLimitSource rawValue of
      Just limitSource -> pure limitSource
      Nothing -> fail ("Unsupported pod memory limit source: " <> Text.unpack rawValue)

-- | Phase 4 Sprint 4.31 — the descriptive substrate-enforced limit. On
-- @linux-cpu@ / @linux-gpu@ the pod cgroup memory limit / CUDA allocator bound
-- the engine subprocess inside its own container, so host death is already
-- impossible; this record names that already-enforced limit for admission and
-- observability.
data PodMemoryLimit = PodMemoryLimit
  { podMemoryLimitResource :: Resource,
    podMemoryLimitSource :: PodMemoryLimitSource,
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
-- host-enforced by the grant plus the fixed, bounded public-tool footprint
-- observer against a checked 'HostMemoryPartition'; @linux-cpu@ / @linux-gpu@
-- are substrate-enforced by the pod cgroup / VRAM limit the descriptive
-- 'PodMemoryLimit' records.
-- @linux-gpu@ is the one substrate whose models consume two independent
-- physical resources at once, so it carries two independent limits:
-- 'DualEnforcedBudget' names the pod cgroup RAM limit first and the NVIDIA
-- device VRAM limit second. Both are required — the execution-plan compiler
-- mints one resource-indexed grant per limit and the capped-engine kernel runs
-- one watchdog per grant — so a GPU model can never be admitted against RAM
-- alone or VRAM alone.
data InferenceMemoryBudget
  = HostEnforcedBudget HostMemoryPartition
  | SubstrateEnforcedBudget PodMemoryLimit
  | DualEnforcedBudget PodMemoryLimit PodMemoryLimit
  deriving (Eq, Show)

-- | The stable source string recorded for a host-enforced admission decision.
hostMemoryPartitionSource :: Text
hostMemoryPartitionSource = "host-memory-partition-inference-capacity"

-- | Phase 8 Sprint 8.9 — the JSON projection of the budget names its alternative
-- with a __key__, not with a string value under a shared @kind@ key.
--
-- This is the JSON analogue of the Dhall union the generated wire already uses:
-- an unrecognized alternative is a structural mismatch that no reader can
-- silently misread as a known one, and a reader that omits an arm fails to find
-- its key rather than falling through a string comparison. The retired encoding
-- was @{"kind": "dual-enforced", …}@; the browser-tier reader in
-- @web/playwright/inference.spec.js@ is the only consumer and moves with it.
instance ToJSON InferenceMemoryBudget where
  toJSON budget = case budget of
    HostEnforcedBudget partition ->
      object ["hostEnforced" .= object ["partition" .= partition]]
    SubstrateEnforcedBudget podLimit ->
      object ["substrateEnforced" .= object ["podLimit" .= podLimit]]
    DualEnforcedBudget podLimit vramLimit ->
      object
        [ "dualEnforced"
            .= object
              [ "podLimit" .= podLimit,
                "vramLimit" .= vramLimit
              ]
        ]

instance FromJSON InferenceMemoryBudget where
  parseJSON = withObject "InferenceMemoryBudget" $ \value -> do
    hostEnforced <- value .:? "hostEnforced"
    substrateEnforced <- value .:? "substrateEnforced"
    dualEnforced <- value .:? "dualEnforced"
    case (hostEnforced, substrateEnforced, dualEnforced) of
      (Just arm, Nothing, Nothing) ->
        HostEnforcedBudget <$> arm .: "partition"
      (Nothing, Just arm, Nothing) ->
        SubstrateEnforcedBudget <$> arm .: "podLimit"
      (Nothing, Nothing, Just arm) ->
        DualEnforcedBudget <$> arm .: "podLimit" <*> arm .: "vramLimit"
      (Nothing, Nothing, Nothing) -> do
        -- Name the retirement rather than surfacing a bare "no alternative"
        -- error, matching the targeted Dhall migration diagnostic in
        -- 'Infernix.Substrate.Internal'.
        retiredKind <- value .:? "kind"
        case retiredKind :: Maybe Text of
          Just retiredLabel ->
            fail
              ( "inference memory budget uses the retired flat kind="
                  <> Text.unpack retiredLabel
                  <> " encoding; the alternative is now the object key "
                  <> "hostEnforced, substrateEnforced, or dualEnforced"
              )
          Nothing -> fail exactlyOneAlternative
      _ -> fail exactlyOneAlternative
    where
      exactlyOneAlternative =
        "inference memory budget must carry exactly one of hostEnforced, "
          <> "substrateEnforced, or dualEnforced"

-- | The admission capacity (MiB) a budget draws from: the partition's inference
-- capacity for a host-enforced budget, or the pod/VRAM limit for a
-- substrate-enforced one.
-- | The capacity of a budget's __primary__ admission resource. For a dual
-- budget the primary is the VRAM limit: it is the defining constraint of the
-- GPU substrate and the smaller of the two in every supported configuration.
-- Admission itself never uses this projection for a dual budget — the
-- execution-plan compiler matches the arm and admits each grant against its own
-- limit — so the projection exists for observability and single-resource error
-- payloads, not for the enforcement decision.
inferenceMemoryBudgetCapacityMib :: InferenceMemoryBudget -> Int
inferenceMemoryBudgetCapacityMib budget = case budget of
  HostEnforcedBudget partition -> hostPartitionInferenceCapacityMib partition
  SubstrateEnforcedBudget podLimit -> podMemoryLimitMib podLimit
  DualEnforcedBudget _ vramLimit -> podMemoryLimitMib vramLimit

inferenceMemoryBudgetResource :: InferenceMemoryBudget -> Resource
inferenceMemoryBudgetResource budget = case budget of
  HostEnforcedBudget _ -> HostRam
  SubstrateEnforcedBudget podLimit -> podMemoryLimitResource podLimit
  DualEnforcedBudget _ vramLimit -> podMemoryLimitResource vramLimit

inferenceMemoryBudgetSource :: InferenceMemoryBudget -> Text
inferenceMemoryBudgetSource budget = case budget of
  HostEnforcedBudget _ -> hostMemoryPartitionSource
  SubstrateEnforcedBudget podLimit -> podMemoryLimitSourceText (podMemoryLimitSource podLimit)
  DualEnforcedBudget _ vramLimit -> podMemoryLimitSourceText (podMemoryLimitSource vramLimit)

-- | Every limit a budget names, in enforcement order. A dual budget yields its
-- pod RAM limit and its VRAM limit; the single-resource arms yield one entry.
-- Config validation walks this so a new arm cannot silently escape the
-- positive-quantity and named-source checks.
inferenceMemoryBudgetPodLimits :: InferenceMemoryBudget -> [PodMemoryLimit]
inferenceMemoryBudgetPodLimits budget = case budget of
  HostEnforcedBudget _ -> []
  SubstrateEnforcedBudget podLimit -> [podLimit]
  DualEnforcedBudget podLimit vramLimit -> [podLimit, vramLimit]

-- | Phase 4 Sprint 4.38 — a required per-model memory quantity for exactly one
-- physical resource (MiB).
--
-- The constructor is hidden and the role is nominal, so a host quantity handed
-- to a device admission stops being a term rather than a review obligation. The
-- retired 'ModelMemoryFootprint' was one @Int@ behind a positivity check, and it
-- was the last un-indexed quantity feeding both admission arms: the same scalar
-- was compared against a host capacity and against a device capacity, and the
-- result was a correctly indexed grant either way. The type system was enforcing
-- non-substitutability at the far end of a pipe whose input was a single scalar.
newtype ModelMemoryRequirement (resource :: Resource) = ModelMemoryRequirement Int
  deriving (Eq, Ord, Show)

type role ModelMemoryRequirement nominal

modelMemoryRequirementMib :: ModelMemoryRequirement resource -> Int
modelMemoryRequirementMib (ModelMemoryRequirement mib) = mib

-- | Phase 4 Sprint 4.39 — where a model's weights live while it runs.
--
-- This is the one declaration that decides which resource the model-size term is
-- charged to. A host-resident load holds the weights on the executing machine; a
-- streamed load holds one tensor at a time on the host and the whole checkpoint
-- on the device, which is why the host formula for a streamed model has no
-- model-size term in it at all.
data ModelLoadStrategy
  = LoadResidentHost
  | StreamWeightsToDevice
  deriving (Eq, Ord, Read, Show)

-- | Phase 4 Sprint 4.39 — the execution shape the engine will actually run
-- under.
--
-- It is declared rather than derived, because it is policy rather than
-- measurement: how long a context this deployment runs is a decision, and the
-- artifact has no opinion about it. It is the second input to the cache term,
-- computed once by the compiler and carried to the engine, so the engine runs
-- the shape the model was admitted against rather than a number that was never
-- compared against a machine.
data ModelExecutionShape = ModelExecutionShape
  { executionContextLength :: Int,
    executionBatchSize :: Int,
    executionGenerationBound :: Int,
    -- | Bytes per key/value cache element.
    executionCacheElementWidth :: Int,
    executionLoadStrategy :: ModelLoadStrategy
  }
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.39 — the declared geometry the cache term is computed
-- from.
--
-- Every field is cross-checked against the artifact's own tensor table before it
-- is used, so a geometry that the checkpoint does not corroborate yields no
-- requirement rather than a small one. A model whose engine keeps no key/value
-- cache declares none, and its cache term is zero rather than guessed.
data ModelGeometry = ModelGeometry
  { geometryLayers :: Int,
    geometryKeyValueHeads :: Int,
    geometryHeadWidth :: Int,
    geometryHiddenWidth :: Int
  }
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.38 — what a model requires, by the resources it uses.
--
-- The retired descriptor carried @requiresGpu :: Bool@ beside a single
-- footprint, so \"this model uses the device\" and \"this model has stated what
-- it needs from the device\" were two independent fields that could disagree.
-- They are one fact here: the arms are host-only and host-plus-device, the
-- device term is present exactly on the arm that uses the device, and
-- 'requiresGpu' is derived from the arm rather than written beside it.
data ModelResourceRequirement
  = HostResidentRequirement (ModelMemoryRequirement 'HostRam)
  | HostAndDeviceRequirement
      (ModelMemoryRequirement 'HostRam)
      (ModelMemoryRequirement 'NvidiaVram)
  deriving (Eq, Show)

-- | Mint a host-only requirement. Rejects a non-positive quantity, so a model
-- admitted on an absent or zero requirement is unrepresentable.
mkHostResidentRequirement :: Int -> Either String ModelResourceRequirement
mkHostResidentRequirement hostMib
  | hostMib > 0 = Right (HostResidentRequirement (ModelMemoryRequirement hostMib))
  | otherwise =
      Left ("model host-residency requirement must be a positive MiB value, got " <> show hostMib)

-- | Mint a host-plus-device requirement. Both terms are checked, because a
-- device-using model that states nothing about the device is exactly the
-- disagreement this arm exists to make unrepresentable.
mkHostAndDeviceRequirement :: Int -> Int -> Either String ModelResourceRequirement
mkHostAndDeviceRequirement hostMib deviceMib
  | hostMib <= 0 =
      Left ("model host-residency requirement must be a positive MiB value, got " <> show hostMib)
  | deviceMib <= 0 =
      Left ("model device requirement must be a positive MiB value, got " <> show deviceMib)
  | otherwise =
      Right
        ( HostAndDeviceRequirement
            (ModelMemoryRequirement hostMib)
            (ModelMemoryRequirement deviceMib)
        )

-- | The host-residency term, indexed for whichever host-side resource the
-- executing lane admits it against. 'HostResidentResource' is what keeps the
-- device index out of this projection.
modelHostResidencyRequirement ::
  (HostResidentResource resource) =>
  ModelResourceRequirement ->
  ModelMemoryRequirement resource
modelHostResidencyRequirement requirement =
  case requirement of
    HostResidentRequirement hostRequirement ->
      ModelMemoryRequirement (modelMemoryRequirementMib hostRequirement)
    HostAndDeviceRequirement hostRequirement _ ->
      ModelMemoryRequirement (modelMemoryRequirementMib hostRequirement)

-- | The device term, present exactly on the device-using arm.
modelDeviceRequirement ::
  ModelResourceRequirement ->
  Maybe (ModelMemoryRequirement 'NvidiaVram)
modelDeviceRequirement requirement =
  case requirement of
    HostResidentRequirement _ -> Nothing
    HostAndDeviceRequirement _ deviceRequirement -> Just deviceRequirement

-- | The host-residency quantity in MiB, for rendering and observability.
modelResourceRequirementHostMib :: ModelResourceRequirement -> Int
modelResourceRequirementHostMib requirement =
  case requirement of
    HostResidentRequirement hostRequirement -> modelMemoryRequirementMib hostRequirement
    HostAndDeviceRequirement hostRequirement _ -> modelMemoryRequirementMib hostRequirement

-- | The device quantity in MiB when the model uses the device.
modelResourceRequirementDeviceMib :: ModelResourceRequirement -> Maybe Int
modelResourceRequirementDeviceMib =
  fmap modelMemoryRequirementMib . modelDeviceRequirement

-- | Phase 4 Sprint 4.30 — the internal 'ErrorResponse' code the capped-engine
-- kernel raises when a running engine subprocess breaches its admitted
-- 'MemoryCeiling' (the @apple-silicon@ watchdog killed its process group, or the
-- Linux pod cgroup OOM-killed it). The runtime recognizes this code and rebuilds
-- it into a typed @status=failed@ 'ModelMemoryLimitExceeded' result rather than a
-- generic worker failure, so a ceiling breach is a clean typed terminal outcome,
-- never a host OOM.
modelMemoryLimitExceededErrorCode :: Text
modelMemoryLimitExceededErrorCode = "model_memory_limit_exceeded"

-- | Phase 4 Sprint 4.43 — the operator-facing code for a model whose memory
-- requirement could not be established at all.
--
-- It is deliberately not the limit-exceeded code: the two demand opposite
-- responses, and a refusal that cannot say which proposition failed cannot be
-- acted on.
modelRequirementUnderivableErrorCode :: Text
modelRequirementUnderivableErrorCode = "model_requirement_underivable"

-- | Phase 4 Sprint 4.30 — the @inferenceErrorSource@ a runtime resident-memory
-- ceiling breach reports (the model was admitted but its actual footprint
-- exceeded its admitted ceiling and the capped-engine kernel terminated it),
-- distinct from the pre-admission budget source a genuinely over-budget model
-- reports. Consumers distinguish the two fail-closed paths by this source.
cappedEngineResidentCeilingSource :: Text
cappedEngineResidentCeilingSource = "capped-engine-resident-ceiling"

-- | Phase 4 Sprint 4.44 — the @inferenceErrorSource@ a /kernel refusal at the
-- installed ceiling/ names, as distinct from a sampled overrun above it.
--
-- The two are different shapes and the payload has to be able to say which. An
-- overrun reports an observation strictly above the ceiling; a refusal has no
-- such observation to report, because the kernel refused the allocation and the
-- memory never became resident. Its payload therefore carries the ceiling that
-- was installed and the peak that was actually observed — which is at or below
-- it — rather than a number invented above the limit to satisfy an invariant
-- that belongs to the other shape.
cappedEngineRefusedAtCeilingSource :: Text
cappedEngineRefusedAtCeilingSource = "capped-engine-refused-at-ceiling"

data InferenceError
  = ModelMemoryLimitExceeded
      { inferenceErrorModelId :: Text,
        inferenceErrorRequiredMib :: Int,
        inferenceErrorAvailableMib :: Int,
        inferenceErrorResource :: Resource,
        inferenceErrorSource :: Text
      }
  | -- | Phase 4 Sprint 4.39 — the model's memory requirement could not be
    -- derived from its own artifact, so the model was never admitted.
    --
    -- This is a distinct terminal outcome from a limit being exceeded, and
    -- collapsing the two would be the same defect the breach path was corrected
    -- for: a refusal that cannot say which proposition failed cannot be acted
    -- on. There is deliberately no quantity here, because the quantity is
    -- exactly what could not be established — reporting a constant in its place
    -- is the shape this derivation exists to delete.
    ModelRequirementUnderivable
      { inferenceErrorModelId :: Text,
        inferenceErrorArtifactType :: Text,
        inferenceErrorReason :: Text
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
    ModelRequirementUnderivable {inferenceErrorModelId, inferenceErrorArtifactType, inferenceErrorReason} ->
      object
        [ "tag" .= ("ModelRequirementUnderivable" :: Text),
          "modelId" .= inferenceErrorModelId,
          "artifactType" .= inferenceErrorArtifactType,
          "reason" .= inferenceErrorReason
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
      "ModelRequirementUnderivable" ->
        ModelRequirementUnderivable
          <$> value .: "modelId"
          <*> value .: "artifactType"
          <*> value .: "reason"
      _ -> fail ("Unsupported inference error: " <> Text.unpack tag)

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

-- | Phase 8 Sprint 8.12 — how many engine machines the generated system
-- contract declares.
--
-- A fleet is a count of /machines/, never a replica count: each machine runs
-- exactly one engine process, holds its own model cache, and admits work
-- against its own observed capacity. The constructor is hidden so a count can
-- only arrive through 'engineMachineCount', which rejects zero and negative
-- values — a contract declaring no engine machine has no member for any pool
-- to name, and the daemon that reads it would refuse to start anyway. Refusing
-- at generation names the defect where an operator can still fix it.
newtype EngineMachineCount = EngineMachineCount Int
  deriving (Eq, Ord, Read, Show)

engineMachineCount :: Int -> Either String EngineMachineCount
engineMachineCount requested
  | requested >= 1 = Right (EngineMachineCount requested)
  | otherwise =
      Left
        ( "engine machine count must be at least 1; got "
            <> show requested
        )

engineMachineCountValue :: EngineMachineCount -> Int
engineMachineCountValue (EngineMachineCount value) = value

-- | The deployed platform's topology: one engine machine.
singleEngineMachine :: EngineMachineCount
singleEngineMachine = EngineMachineCount 1

-- | Phase 8 Sprint 8.9 — how an engine binding's adapter is executed.
--
-- Like 'PodMemoryLimitSource' this was raw 'Text' end to end: no parser, no
-- smart constructor, and a domain closed only by a @Set@ membership check in
-- the execution-plan compiler plus string dispatch in two runtime modules. The
-- sole generator only ever produced these two, and the runtime can only
-- /execute/ these two, so the closed sum removes both the check and its
-- unreachable failure arm.
data EngineAdapterType
  = -- | launch the engine's own executable directly
    NativeProcessRunner
  | -- | drive a Python adapter over its stdio protocol
    PythonStdio
  deriving (Eq, Ord, Read, Show)

engineAdapterTypeId :: EngineAdapterType -> Text
engineAdapterTypeId adapterType = case adapterType of
  NativeProcessRunner -> "native-process-runner"
  PythonStdio -> "python-stdio"

parseEngineAdapterType :: Text -> Maybe EngineAdapterType
parseEngineAdapterType rawValue = case Text.toLower rawValue of
  "native-process-runner" -> Just NativeProcessRunner
  "python-stdio" -> Just PythonStdio
  _ -> Nothing

instance ToJSON EngineAdapterType where
  toJSON = String . engineAdapterTypeId

instance FromJSON EngineAdapterType where
  parseJSON = withText "EngineAdapterType" $ \rawValue ->
    case parseEngineAdapterType rawValue of
      Just adapterType -> pure adapterType
      Nothing -> fail ("Unsupported engine adapter type: " <> Text.unpack rawValue)

data EngineBinding = EngineBinding
  { engineBindingName :: Text,
    engineBindingAdapterId :: Text,
    engineBindingAdapterType :: EngineAdapterType,
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
    notes :: Text,
    -- | Phase 4 Sprint 4.39 — the execution shape this model runs under.
    --
    -- Sprint 4.38 put a closed requirement here in place of the retired
    -- @requiresGpu :: Bool@ plus a single authored footprint. Sprint 4.39 then
    -- took the /quantities/ off the wire entirely: they are derived from the
    -- artifact's own bytes on the machine that will execute, and what remains
    -- declared is the shape that derivation is evaluated against.
    modelExecutionShape :: ModelExecutionShape,
    -- | The declared geometry, for a model whose engine keeps a key/value
    -- cache. It is cross-checked against the artifact's tensor table before the
    -- cache term is computed from it.
    modelGeometry :: Maybe ModelGeometry
  }
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.39 — whether this model uses the device, derived from
-- where its weights live.
--
-- This was a wire field beside a footprint, so \"this model uses the device\"
-- and \"this model has stated what it needs from the device\" were two
-- independent facts that could disagree. It is one fact now: a model whose
-- weights stream to the device uses the device, and the derivation charges the
-- model-size term to the device for exactly those models.
requiresGpu :: ModelDescriptor -> Bool
requiresGpu modelDescriptor =
  case executionLoadStrategy (modelExecutionShape modelDescriptor) of
    LoadResidentHost -> False
    StreamWeightsToDevice -> True

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
        "contextLength" .= executionContextLength (modelExecutionShape modelDescriptor),
        "batchSize" .= executionBatchSize (modelExecutionShape modelDescriptor),
        "generationBound" .= executionGenerationBound (modelExecutionShape modelDescriptor),
        "cacheElementWidth"
          .= executionCacheElementWidth (modelExecutionShape modelDescriptor)
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
      <*> value .: "notes"
      <*> ( ModelExecutionShape
              <$> value .: "contextLength"
              <*> value .: "batchSize"
              <*> value .: "generationBound"
              <*> value .: "cacheElementWidth"
              <*> ( ( \gpuRequired ->
                        if gpuRequired then StreamWeightsToDevice else LoadResidentHost
                    )
                      <$> value .: "requiresGpu"
                  )
          )
      <*> pure Nothing

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
        "configMapName" .= configMapName demoConfig,
        "generatedPath" .= generatedPath demoConfig,
        "mountedPath" .= mountedPath demoConfig,
        "demo_ui" .= demoUiEnabled demoConfig,
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
    -- Phase 8 Sprint 8.9: the budget is required. The retired
    -- @inferenceRamBudgetMib@ scalar fallback defaulted to @0@ when both keys
    -- were absent, so a malformed document decoded to a silent zero-MiB budget
    -- instead of failing. Nothing in the repo ever produced that key.
    inferenceMemoryBudgetValue <- value .: "inferenceMemoryBudget"
    (DemoConfig runtimeModeValue <$> value .: "configMapName")
      <*> value .: "generatedPath"
      <*> value .: "mountedPath"
      <*> value .: "demo_ui"
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

-- | Synthesize a valid 'HostMemoryPartition' whose inference capacity is a given
-- MiB value, holding back exactly 'minHostHeadroomMib' of headroom and no VM
-- reserve. Used by the legacy-config and discovery-failure fallback paths where
-- the real physical / VM-pledge split is unknown; the result is always
-- constructible when the requested capacity is positive and it plus the
-- mandatory headroom fit in the platform 'Int'. An excessive legacy value is
-- rejected rather than wrapping into a valid-looking physical-memory partition,
-- and a non-positive one is rejected rather than normalized to zero
-- (Phase 4 Sprint 4.34).
hostPartitionForCapacity :: Int -> Either String HostMemoryPartition
hostPartitionForCapacity capacityMib
  | capacityMib <= 0 =
      Left
        ( "host memory capacity must be positive, got "
            <> show capacityMib
            <> " MiB; a zero-capacity partition admits no model at all"
        )
  | physicalMib > toInteger (maxBound :: Int) =
      Left
        ( "host memory capacity "
            <> show capacityMib
            <> " MiB plus required headroom exceeds the supported integer range"
        )
  | otherwise = mkHostMemoryPartition (fromInteger physicalMib) 0 minHostHeadroomMib
  where
    physicalMib = toInteger capacityMib + toInteger minHostHeadroomMib

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
