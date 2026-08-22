{-# LANGUAGE OverloadedStrings #-}

-- | Phase 8 Sprint 8.5: @matrixRows@ / @catalogForMode@ is a **demo-only
-- generator** of the model set, not a core runtime dependency. The source of
-- truth for which models a daemon stages and serves is the mounted
-- @infernix.dhall@ (the ConfigMap-published substrate config at deploy, or the
-- @infernix init@ / test-harness-generated file on host). The coordinator's
-- eager model-cache sweep iterates the mounted config's @models@ list, and the
-- image-baked config carries an empty model set so @docker run --rm@ never
-- stages weights; the ConfigMap-mounted config overrides it at deploy. This
-- module regenerates the demo catalog for @infernix init@, the test harness,
-- and @cluster up@ publication.
module Infernix.Models
  ( allMatrixRowIds,
    catalogForMode,
    clusterDemoApiUpstream,
    engineNameForAdapterId,
    engineNameForSelectedEngine,
    frameworkEngineNamesForMode,
    perEngineImageRepository,
    perEngineImageName,
    engineBindingForSelectedEngine,
    engineBindingsForMode,
    encodeDemoConfig,
    defaultInferenceRamBudgetMib,
    linuxEngineInferenceRamBudgetMib,
    linuxEngineInferenceVramBudgetMib,
    linuxGpuEngineInferenceRamBudgetMib,
    linuxGpuEnginePodMemoryLimitMib,
    appleFallbackInferenceRamBudgetMib,
    engineMembersForMode,
    engineMembersForFleet,
    enginePoolsForMode,
    enginePoolsForFleet,
    engineMachineCountForMode,
    engineMachineCountFromMemberIds,
    fleetMemberIds,
    expectedDaemonLocationForRuntime,
    expectedInferenceExecutorLocationForRuntime,
    expectedInferenceDispatchModeForRuntime,
    findModel,
    platformClaimsForRuntime,
    requestTopicsForMode,
    renderPublicationState,
    renderPublicationStateWithApiUpstream,
    renderConfigMapManifest,
    resultFamilyForDescriptor,
    matrixRowReadmeKeys,
    modelRequiresInputObject,
    resultTopicForMode,
    residualMatrixRowIdsForMode,
    routeInventory,
  )
where

import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Char (isDigit)
import Data.Either (fromRight)
import Data.List (find, intercalate, nub)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (ControlPlaneContext, controlPlaneContextId)
import Infernix.EngineBindings
  ( canonicalEngineBindingForSelectedEngine,
    canonicalEngineBindingsForMode,
  )
import Infernix.EngineRouting (requestTopicsForMode, resultTopicForMode)
import Infernix.ExecutionPlan (linuxOuterEnvelopeHeadroomMib)
import Infernix.Routes qualified as Routes
import Infernix.Substrate (encodeSubstrateConfig)
import Infernix.Types

data ModeBinding = ModeBinding
  { bindingEngine :: Text,
    bindingRequiresGpu :: Bool
  }

data MatrixRow = MatrixRow
  { rowId :: Text,
    rowModelId :: Text,
    rowDisplayName :: Text,
    rowFamily :: Text,
    rowDescription :: Text,
    rowArtifactType :: Text,
    rowReferenceModel :: Text,
    rowDownloadUrl :: Text,
    rowNotes :: Text,
    rowRequestLabel :: Text,
    appleBinding :: Maybe ModeBinding,
    linuxCpuBinding :: Maybe ModeBinding,
    linuxGpuBinding :: Maybe ModeBinding
  }

catalogForMode :: RuntimeMode -> [ModelDescriptor]
catalogForMode runtimeMode = mapMaybe (descriptorForMode runtimeMode) matrixRows

-- | Phase 6 Sprint 6.6 — every README matrix row id, independent of
-- substrate. The coverage invariant proven by the unit suite is that the
-- union of 'catalogForMode' over every 'RuntimeMode' equals this set: no
-- README row is missing from all generated catalogs.
allMatrixRowIds :: [Text]
allMatrixRowIds = map rowId matrixRows

matrixRowReadmeKeys :: [(Text, Text, Text)]
matrixRowReadmeKeys =
  [ (rowId row, rowArtifactType row, rowReferenceModel row)
  | row <- matrixRows
  ]

-- | Phase 4 Sprint 4.18 — named research residuals are tracked explicitly
-- instead of being surfaced as runnable model descriptors. The runtime catalog
-- remains executable-only; this list lets lint and unit coverage distinguish a
-- deliberate residual from an accidentally missing README matrix row.
residualMatrixRowIdsForMode :: RuntimeMode -> [Text]
residualMatrixRowIdsForMode runtimeMode =
  case runtimeMode of
    AppleSilicon ->
      [ "video-wan21-diffusers"
      ]
    LinuxCpu ->
      []
    LinuxGpu ->
      []

-- | Phase 4 Sprint 4.15 — resolve a catalog row to its per-family result
-- contract from @family@ + @artifactType@ + @matrixRowId@. Text families
-- (LLM, speech transcription) produce inline output; every other family
-- produces an @infernix-demo-objects@ artifact reference. Total over the
-- README matrix.
resultFamilyForDescriptor :: ModelDescriptor -> ResultFamily
resultFamilyForDescriptor model =
  case family model of
    "llm" -> LlmText
    "speech" -> SpeechTranscription
    "music" -> MusicTranscription
    "image" -> ImageGeneration
    "video" -> VideoGeneration
    "tool" -> OpticalMusicRecognition
    "audio" -> audioResultFamily (matrixRowId model)
    _ -> audioResultFamily (matrixRowId model)
  where
    audioResultFamily rowIdValue
      | "demucs" `Text.isInfixOf` rowIdValue = SourceSeparation
      | "unmix" `Text.isInfixOf` rowIdValue = SourceSeparation
      | "basic-pitch" `Text.isInfixOf` rowIdValue = AudioToMidi
      | "bark" `Text.isInfixOf` rowIdValue = AudioGeneration
      | otherwise = AudioGeneration

-- | True when the model consumes a user-uploaded object instead of only the
-- prompt text. The dispatcher uses this to carry the first prompt upload into
-- the inference request envelope without changing text-only prompt behavior.
modelRequiresInputObject :: ModelDescriptor -> Bool
modelRequiresInputObject model =
  case resultFamilyForDescriptor model of
    SpeechTranscription -> True
    SourceSeparation -> True
    AudioToMidi -> True
    MusicTranscription -> True
    OpticalMusicRecognition -> True
    _ -> False

engineBindingsForMode :: RuntimeMode -> [EngineBinding]
engineBindingsForMode runtimeMode =
  filter
    ((`elem` selectedEngineNames) . engineBindingName)
    (canonicalEngineBindingsForMode runtimeMode)
  where
    selectedEngineNames = map selectedEngine (catalogForMode runtimeMode)

-- | Phase 4 Sprint 4.17 — the per-engine engine name derived from an adapter
-- id. The python-stdio framework adapters carry a @-python@ suffix
-- (@transformers-python@ -> @transformers@); native-process-runner adapter ids
-- have no suffix and map to themselves.
engineNameForAdapterId :: Text -> Text
engineNameForAdapterId adapterId =
  fromMaybe adapterId (Text.stripSuffix "-python" adapterId)

-- | The per-engine image name a selected engine resolves to, via its adapter
-- binding.
engineNameForSelectedEngine :: RuntimeMode -> Text -> Maybe Text
engineNameForSelectedEngine runtimeMode selectedEngineValue =
  engineNameForAdapterId . engineBindingAdapterId
    <$> engineBindingForSelectedEngine runtimeMode selectedEngineValue

-- | The distinct framework (python-native) engine names present in a
-- substrate's catalog. These are the per-engine engine Deployments the chart
-- renders and the per-engine images the lifecycle builds. Native-process-runner
-- engines are handled by the separate native-binary lane (Sprint 4.17 follow-on).
frameworkEngineNamesForMode :: RuntimeMode -> [Text]
frameworkEngineNamesForMode runtimeMode =
  nub
    [ engineNameForAdapterId (engineBindingAdapterId engineBinding)
    | engineBinding <- engineBindingsForMode runtimeMode,
      engineBindingPythonNative engineBinding
    ]

enginePoolsForMode :: RuntimeMode -> [EnginePool]
enginePoolsForMode runtimeMode =
  [ EnginePool
      { enginePoolId = poolId,
        enginePoolRuntimeMode = runtimeMode,
        enginePoolModelIds = map modelId groupedModels,
        enginePoolMemberIds = memberIdsForPool runtimeMode poolId isPythonPool,
        enginePoolSubscriptionType = ConsumerShared,
        enginePoolMaxInflightPerMember = 1
      }
  | (poolId, isPythonPool, groupedModels) <- groupedModelsByEngine runtimeMode
  ]

engineMembersForMode :: RuntimeMode -> [EngineMember]
engineMembersForMode runtimeMode =
  case runtimeMode of
    AppleSilicon ->
      [ EngineMember
          { engineMemberId = "apple-host-default",
            engineMemberRuntimeMode = runtimeMode,
            engineMemberLocation = "control-plane-host",
            engineMemberPoolIds = map enginePoolId pools
          }
      ]
    LinuxCpu ->
      [ EngineMember
          { engineMemberId = "linux-cpu-engine",
            engineMemberRuntimeMode = runtimeMode,
            engineMemberLocation = "cluster-pod",
            engineMemberPoolIds = map enginePoolId pools
          }
      ]
    LinuxGpu ->
      nativeMember <> frameworkMembers
  where
    pools = enginePoolsForMode runtimeMode
    nativePoolIds =
      [ poolId
      | (poolId, isPythonPool, _) <- groupedModelsByEngine runtimeMode,
        not isPythonPool
      ]
    nativeMember =
      [ EngineMember
          { engineMemberId = "native",
            engineMemberRuntimeMode = runtimeMode,
            engineMemberLocation = "cluster-pod",
            engineMemberPoolIds = nativePoolIds
          }
      | not (null nativePoolIds)
      ]
    frameworkMembers =
      [ EngineMember
          { engineMemberId = poolId,
            engineMemberRuntimeMode = runtimeMode,
            engineMemberLocation = "cluster-pod",
            engineMemberPoolIds = [poolId]
          }
      | (poolId, isPythonPool, _) <- groupedModelsByEngine runtimeMode,
        isPythonPool
      ]

-- | Phase 8 Sprint 8.12 — the pool graph a fleet of @count@ engine machines
-- declares.
--
-- The fleet dimension multiplies /members/ and nothing else. A pool's identity,
-- its model set, its subscription type, and its per-member inflight bound are
-- all properties of the platform every machine shares, so they are generated
-- once and the fleet expansion only rewrites which member ids each pool names.
-- Writing it as a rewrite of the single-machine graph rather than as a second
-- generator is deliberate: two generators that must agree on everything except
-- the member list is exactly the permanent illegal-state shape Sprint 8.10
-- deleted from the wire.
enginePoolsForFleet :: RuntimeMode -> EngineMachineCount -> [EnginePool]
enginePoolsForFleet runtimeMode count =
  [ pool
      { enginePoolMemberIds =
          concatMap (fleetMemberIds count) (enginePoolMemberIds pool)
      }
  | pool <- enginePoolsForMode runtimeMode
  ]

-- | The member list a fleet of @count@ engine machines declares.
--
-- Each single-machine member becomes @count@ members serving the same pools:
-- the machines of a fleet are interchangeable consumers of one @Shared@ pool
-- topic, which is the topology
-- [daemon_topology.md](documents/architecture/daemon_topology.md) specifies.
-- Nothing here decides /which/ machine adopts which identity; that is the
-- machine contract's job, and preventing two machines from adopting the same
-- one is the broker-side claim's.
engineMembersForFleet :: RuntimeMode -> EngineMachineCount -> [EngineMember]
engineMembersForFleet runtimeMode count =
  [ member {engineMemberId = expandedId}
  | member <- engineMembersForMode runtimeMode,
    expandedId <- fleetMemberIds count (engineMemberId member)
  ]

-- | The member ids one single-machine member id expands to.
--
-- A one-machine fleet keeps the unsuffixed id, so the deployed single-node
-- platform's generated contract is byte identical to what it was before this
-- sprint and no existing machine contract is invalidated by the fleet
-- dimension merely existing.
fleetMemberIds :: EngineMachineCount -> Text -> [Text]
fleetMemberIds count baseMemberId
  | machines <= 1 = [baseMemberId]
  | otherwise =
      [ baseMemberId <> "-m" <> Text.pack (show machineIndex)
      | machineIndex <- [1 .. machines]
      ]
  where
    machines = engineMachineCountValue count

-- | The fleet size a decoded contract's member ids describe.
--
-- @cluster up@ republishes the system contract for the pods that mount it, and
-- that republication regenerates the payload rather than copying the operator's
-- bytes. It therefore has to learn the fleet dimension from the contract it was
-- handed, or a two-machine deployment would be published as a one-machine one
-- and the second machine would find no member to adopt.
--
-- The suffix is the evidence because the suffix is generated: 'fleetMemberIds'
-- is the only writer of a member id, and it writes @-m\<index\>@ only for a
-- fleet. An id with no suffix is a one-machine contract, which is also what an
-- empty member list means — a contract with no member declares no fleet.
engineMachineCountFromMemberIds :: [Text] -> EngineMachineCount
engineMachineCountFromMemberIds memberIds =
  case mapMaybe fleetMachineIndex memberIds of
    [] -> singleEngineMachine
    indices -> fromRight singleEngineMachine (engineMachineCount (maximum indices))

-- | The machine index a fleet member id carries, if it carries one.
fleetMachineIndex :: Text -> Maybe Int
fleetMachineIndex memberIdValue =
  case Text.breakOnEnd "-m" memberIdValue of
    (prefix, suffix)
      | not (Text.null prefix),
        not (Text.null suffix),
        Text.all isDigit suffix ->
          case reads (Text.unpack suffix) of
            [(indexValue, "")] -> Just indexValue
            _ -> Nothing
    _ -> Nothing

-- | The engine-machine count a runtime mode supports, or a named refusal.
--
-- @linux-gpu@ is refused above one machine, and the reason is a scope decision
-- rather than a defect. Its member set is already per-framework-image — a
-- python pool's member id /is/ its pool id, and the generated per-engine
-- Deployments are named from those ids — so a fleet dimension there changes
-- what an engine image is called as well as how many machines exist. That is a
-- second, independent change whose only honest proof is the CUDA Linux cohort,
-- which this sprint's lane is not. Refusing at generation is what keeps the
-- unproven shape from being written into a contract.
engineMachineCountForMode :: RuntimeMode -> Int -> Either String EngineMachineCount
engineMachineCountForMode runtimeMode requested = do
  count <- engineMachineCount requested
  case runtimeMode of
    LinuxGpu
      | engineMachineCountValue count > 1 ->
          Left
            ( "linux-gpu declares one engine member per framework engine image, so a"
                <> " fleet of "
                <> show (engineMachineCountValue count)
                <> " machines would rename every engine image as well as add machines;"
                <> " that shape is owned by the CUDA Linux cohort. Use --engine-machines 1"
                <> " on linux-gpu."
            )
    _ -> pure count

memberIdsForPool :: RuntimeMode -> Text -> Bool -> [Text]
memberIdsForPool runtimeMode poolId isPythonPool =
  case runtimeMode of
    AppleSilicon -> ["apple-host-default"]
    LinuxCpu -> ["linux-cpu-engine"]
    LinuxGpu
      | isPythonPool -> [poolId]
      | otherwise -> ["native"]

groupedModelsByEngine :: RuntimeMode -> [(Text, Bool, [ModelDescriptor])]
groupedModelsByEngine runtimeMode =
  [ (engineName, pythonNative, modelsForEngine engineName)
  | engineName <- nub (mapMaybe modelEngineName activeCatalog),
    binding <-
      take
        1
        [ resolvedBinding
        | model <- activeCatalog,
          modelEngineName model == Just engineName,
          Just resolvedBinding <-
            [engineBindingForSelectedEngine runtimeMode (selectedEngine model)]
        ],
    let pythonNative = engineBindingPythonNative binding
  ]
  where
    activeCatalog = catalogForMode runtimeMode
    modelEngineName model = engineNameForSelectedEngine runtimeMode (selectedEngine model)
    modelsForEngine engineName =
      filter ((== Just engineName) . modelEngineName) activeCatalog

-- | Per-engine image name: @infernix-engine-<engine>-<mode>:local@, built from
-- @docker/engine.Dockerfile@.
perEngineImageName :: RuntimeMode -> Text -> Text
perEngineImageName runtimeMode engineName =
  perEngineImageRepository runtimeMode engineName <> ":local"

perEngineImageRepository :: RuntimeMode -> Text -> Text
perEngineImageRepository runtimeMode engineName =
  "infernix-engine-" <> engineName <> "-" <> runtimeModeId runtimeMode

engineBindingForSelectedEngine :: RuntimeMode -> Text -> Maybe EngineBinding
engineBindingForSelectedEngine = canonicalEngineBindingForSelectedEngine

findModel :: RuntimeMode -> Text -> Maybe ModelDescriptor
findModel runtimeMode wantedModelId =
  find ((== wantedModelId) . modelId) (catalogForMode runtimeMode)

encodeDemoConfig :: DemoConfig -> LazyChar8.ByteString
encodeDemoConfig = encodeSubstrateConfig

renderConfigMapManifest :: LazyChar8.ByteString -> String
renderConfigMapManifest payload =
  unlines
    [ "apiVersion: v1",
      "kind: ConfigMap",
      "metadata:",
      "  name: infernix-demo-config",
      "  namespace: platform",
      "data:",
      "  infernix.dhall: |"
    ]
    <> indentBlock 4 (LazyChar8.unpack payload)

-- | Phase 7 Sprint 7.7: the supported three-role daemon split has no
-- daemon PVCs. The coordinator role keeps its subscription cursors on
-- the Pulsar broker side; the engine role uses an `emptyDir` model
-- cache under `engine.modelCache.sizeLimit`. The legacy
-- `infernix-service-0-data` claim is retired with the fused
-- `infernix-service` Deployment.
platformClaimsForRuntime :: RuntimeMode -> [PersistentClaim]
platformClaimsForRuntime _runtimeMode = []

routeInventory :: Bool -> [RouteInfo]
routeInventory = Routes.routeInventory

clusterDemoApiUpstream :: ApiUpstream
clusterDemoApiUpstream =
  ApiUpstream
    { apiUpstreamMode = ClusterDemoUpstream,
      apiUpstreamHost = "infernix-demo.platform.svc.cluster.local",
      apiUpstreamPort = 80
    }

renderPublicationState :: ControlPlaneContext -> ClusterState -> String
renderPublicationState controlPlane state =
  renderPublicationStateWithApiUpstream controlPlane state selectedApiUpstream
  where
    selectedApiUpstream
      | stateHasDemoUi state = clusterDemoApiUpstream
      | otherwise = disabledApiUpstream

renderPublicationStateWithApiUpstream :: ControlPlaneContext -> ClusterState -> ApiUpstream -> String
renderPublicationStateWithApiUpstream controlPlane state apiUpstream =
  "{\n"
    <> "  \"clusterPresent\": "
    <> jsonBool (clusterPresent state)
    <> ",\n"
    <> "  \"controlPlaneContext\": "
    <> show (controlPlaneContextId controlPlane)
    <> ",\n"
    <> "  \"daemonLocation\": "
    <> jsonString (daemonLocationFor state)
    <> ",\n"
    <> "  \"inferenceExecutorLocation\": "
    <> jsonString (expectedInferenceExecutorLocationForRuntime (clusterRuntimeMode state))
    <> ",\n"
    <> "  \"catalogSource\": "
    <> jsonString "generated-build-root"
    <> ",\n"
    <> "  \"runtimeMode\": "
    <> jsonString (runtimeModeId (clusterRuntimeMode state))
    <> ",\n"
    <> "  \"edgePort\": "
    <> show (edgePort state)
    <> ",\n"
    <> "  \"storageClass\": "
    <> jsonString (storageClass state)
    <> ",\n"
    <> "  \"kubeconfigPath\": "
    <> jsonFilePath (kubeconfigPath state)
    <> ",\n"
    <> "  \"generatedDemoConfigPath\": "
    <> jsonFilePath (generatedDemoConfigPath state)
    <> ",\n"
    <> "  \"publishedDemoConfigPath\": "
    <> jsonFilePath (publishedDemoConfigPath state)
    <> ",\n"
    <> "  \"publishedConfigMapManifestPath\": "
    <> jsonFilePath (publishedConfigMapManifestPath state)
    <> ",\n"
    <> "  \"mountedDemoConfigPath\": "
    <> jsonFilePath (mountedDemoConfigPath state)
    <> ",\n"
    <> "  \"demoConfigPath\": "
    <> jsonFilePath (generatedDemoConfigPath state)
    <> ",\n"
    <> "  \"workerExecutionMode\": "
    <> jsonString "process-isolated-engine-workers"
    <> ",\n"
    <> "  \"workerAdapterMode\": "
    <> jsonString "engine-specific-runner-defaults"
    <> ",\n"
    <> "  \"artifactAcquisitionMode\": "
    <> jsonString "engine-ready-artifact-manifests"
    <> ",\n"
    <> "  \"lifecycleStatus\": "
    <> jsonString (Text.pack (lifecycleStatusFor state))
    <> lifecycleProgressJsonFields state
    <> ",\n"
    <> "  \"inferenceDispatchMode\": "
    <> jsonString (inferenceDispatchModeFor state)
    <> ",\n"
    <> "  \"apiUpstream\": "
    <> renderApiUpstream apiUpstream
    <> ",\n"
    <> "  \"updatedAt\": "
    <> show (show (updatedAt state))
    <> ",\n"
    <> "  \"upstreams\": [\n"
    <> intercalate ",\n" (map renderPublicationUpstream (publicationUpstreams (stateHasDemoUi state) apiUpstream (inferenceDispatchModeFor state)))
    <> "\n  ],\n"
    <> "  \"routes\": [\n"
    <> intercalate ",\n" (map renderRouteInfo (routes state))
    <> "\n  ]\n"
    <> "}\n"

publicationUpstreams :: Bool -> ApiUpstream -> Text -> [PublicationUpstream]
publicationUpstreams = Routes.routePublicationUpstreams

renderApiUpstream :: ApiUpstream -> String
renderApiUpstream apiUpstream =
  "{"
    <> "\"mode\": "
    <> jsonString (apiUpstreamModeId (apiUpstreamMode apiUpstream))
    <> ", \"host\": "
    <> jsonString (apiUpstreamHost apiUpstream)
    <> ", \"port\": "
    <> show (apiUpstreamPort apiUpstream)
    <> "}"

renderPublicationUpstream :: PublicationUpstream -> String
renderPublicationUpstream upstream =
  "    {\"id\": "
    <> jsonString (publicationUpstreamId upstream)
    <> ", \"routePrefix\": "
    <> jsonString (publicationUpstreamRoutePrefix upstream)
    <> ", \"targetSurface\": "
    <> jsonString (publicationUpstreamTargetSurface upstream)
    <> ", \"healthStatus\": "
    <> jsonString (publicationUpstreamHealthStatus upstream)
    <> ", \"durableBackendState\": "
    <> jsonString (publicationUpstreamDurableBackendState upstream)
    <> "}"

renderRouteInfo :: RouteInfo -> String
renderRouteInfo route =
  "    {\"path\": "
    <> jsonString (path route)
    <> ", \"purpose\": "
    <> jsonString (purpose route)
    <> "}"

daemonLocationFor :: ClusterState -> Text
daemonLocationFor state =
  if clusterPresent state
    then expectedDaemonLocationForRuntime (clusterRuntimeMode state)
    else "disabled"

expectedDaemonLocationForRuntime :: RuntimeMode -> Text
expectedDaemonLocationForRuntime _runtimeMode =
  "cluster-pod"

expectedInferenceExecutorLocationForRuntime :: RuntimeMode -> Text
expectedInferenceExecutorLocationForRuntime runtimeMode =
  case runtimeMode of
    AppleSilicon -> "control-plane-host"
    _ -> "cluster-pod"

expectedInferenceDispatchModeForRuntime :: RuntimeMode -> Text
expectedInferenceDispatchModeForRuntime runtimeMode =
  case runtimeMode of
    AppleSilicon -> "pulsar-bridge-to-host-daemon"
    _ -> "pulsar-bridge-to-cluster-daemon"

stateHasDemoUi :: ClusterState -> Bool
stateHasDemoUi state =
  any ((`elem` ["/", "/api"]) . path) (routes state)

inferenceDispatchModeFor :: ClusterState -> Text
inferenceDispatchModeFor state
  | stateHasDemoUi state = expectedInferenceDispatchModeForRuntime (clusterRuntimeMode state)
  | otherwise = "disabled"

lifecycleStatusFor :: ClusterState -> String
lifecycleStatusFor state =
  case lifecyclePhaseOf state of
    Just _ -> "in-progress"
    Nothing -> "idle"

-- | Sprint 7.29: the status JSON is projected from the typed 'LifecyclePhase'
-- (the retired stringly 'LifecycleProgress' is gone); the emitted field names and
-- shape are unchanged for the browser/status surface.
lifecycleProgressJsonFields :: ClusterState -> String
lifecycleProgressJsonFields state =
  case lifecyclePhaseOf state of
    Nothing -> ""
    Just phase ->
      ",\n"
        <> "  \"lifecycleAction\": "
        <> show (lifecycleTransitionAction (lifecyclePhaseTransition phase))
        <> ",\n"
        <> "  \"lifecyclePhase\": "
        <> show (lifecyclePhaseName phase)
        <> ",\n"
        <> "  \"lifecycleDetail\": "
        <> show (lifecyclePhaseDetail phase)
        <> ",\n"
        <> "  \"lifecycleHeartbeatAt\": "
        <> show (show (lifecyclePhaseHeartbeatAt phase))

disabledApiUpstream :: ApiUpstream
disabledApiUpstream =
  ApiUpstream
    { apiUpstreamMode = DisabledUpstream,
      apiUpstreamHost = "",
      apiUpstreamPort = 0
    }

indentBlock :: Int -> String -> String
indentBlock indentWidth contents =
  unlines (map (replicate indentWidth ' ' <>) (lines contents))

descriptorForMode :: RuntimeMode -> MatrixRow -> Maybe ModelDescriptor
descriptorForMode runtimeMode row = do
  binding <- bindingForMode runtimeMode row
  pure $
    ModelDescriptor
      { matrixRowId = rowId row,
        modelId = rowModelId row,
        displayName = rowDisplayName row,
        family = rowFamily row,
        description = rowDescription row,
        artifactType = rowArtifactType row,
        referenceModel = rowReferenceModel row,
        downloadUrl = rowDownloadUrl row,
        selectedEngine = bindingEngine binding,
        requestShape =
          [ RequestField
              { name = "inputText",
                label = rowRequestLabel row,
                fieldType = TextRequestField
              }
          ],
        runtimeMode = runtimeMode,
        runtimeLane = runtimeLaneForMode runtimeMode (bindingRequiresGpu binding),
        notes = rowNotes row,
        modelExecutionShape = executionShapeForRow row binding,
        modelGeometry = rowGeometry row
      }

-- | Phase 4 Sprint 4.39 — the execution shape a catalog row runs under.
--
-- This is the second input to the derived requirement's cache term, and the
-- only memory-shaping declaration left in the catalog. It is policy rather than
-- measurement: how long a context this deployment runs is a decision, and the
-- artifact has no opinion about it. The quantities the retired table carried —
-- one conservative MiB constant per family, keyed on nothing the artifact
-- states — are gone entirely rather than demoted to a fallback, because a
-- fallback constant is consulted exactly when the derivation failed, which is
-- the one moment the artifact is known not to describe itself.
executionShapeForRow :: MatrixRow -> ModeBinding -> ModelExecutionShape
executionShapeForRow row binding =
  ModelExecutionShape
    { executionContextLength = contextLengthForRow row,
      executionBatchSize = 1,
      executionGenerationBound = generationBoundForRow row,
      executionCacheElementWidth = 2,
      executionLoadStrategy =
        if bindingRequiresGpu binding
          then StreamWeightsToDevice
          else LoadResidentHost
    }

-- | The context window one serialized inference runs under.
--
-- A row whose engine keeps no key/value cache still declares one, because the
-- shape travels to the engine either way and a family-specific absence would be
-- a second way to say what 'rowGeometry' already says.
contextLengthForRow :: MatrixRow -> Int
contextLengthForRow row =
  case rowFamily row of
    "llm" -> 2048
    _ -> 1024

-- | The generation bound the engine is given, replacing the adapter literals
-- Sprint 4.42 deletes.
generationBoundForRow :: MatrixRow -> Int
generationBoundForRow row =
  case rowFamily row of
    "llm" -> 256
    _ -> 100

-- | The declared geometry for a row whose engine keeps a key/value cache.
--
-- Every field is cross-checked against the staged artifact's own tensor table
-- before the cache term is computed from it, so a geometry that the checkpoint
-- does not corroborate yields no requirement rather than a small one. A row that
-- declares none has a cache term of zero rather than a guessed one.
rowGeometry :: MatrixRow -> Maybe ModelGeometry
rowGeometry row =
  case rowModelId row of
    -- SmolLM2-135M-Instruct: thirty layers, three key/value heads, sixty-four
    -- wide heads, 576-wide hidden state.
    "llm-smollm2-safetensors" ->
      Just (ModelGeometry 30 3 64 576)
    -- TinyLlama-1.1B-Chat: twenty-two layers, four key/value heads,
    -- sixty-four wide heads, 2048-wide hidden state.
    "llm-tinyllama-gguf" ->
      Just (ModelGeometry 22 4 64 2048)
    "llm-tinyllama-gptq" ->
      Just (ModelGeometry 22 4 64 2048)
    -- Qwen2.5-1.5B-Instruct: twenty-eight layers, two key/value heads,
    -- 128-wide heads, 1536-wide hidden state.
    "llm-qwen25-awq" ->
      Just (ModelGeometry 28 2 128 1536)
    -- Qwen1.5-1.8B-Chat: twenty-four layers, sixteen key/value heads,
    -- 128-wide heads, 2048-wide hidden state.
    "llm-qwen15-mlx" ->
      Just (ModelGeometry 24 16 128 2048)
    _ -> Nothing

-- | The Linux per-execution resident-memory budget (MiB). The engine pod's
-- outer limit is intentionally larger (5 GiB) so the Haskell daemon and RSS
-- watchdog remain outside the 4 GiB child grant.
linuxEngineInferenceRamBudgetMib :: Int
linuxEngineInferenceRamBudgetMib = 4096

-- | Phase 6 Sprint 6.44 — the @linux-gpu@ per-execution __resident-set__ budget
-- (MiB). It is deliberately *not* 'linuxEngineInferenceRamBudgetMib': the GPU
-- engine pod is provisioned with a 16 GiB limit (framework host RAM for CUDA
-- contexts and model loading) where the CPU engine pod gets 5 GiB, and runtime
-- refinement requires the observed outer envelope to equal the child budget plus
-- 'linuxOuterEnvelopeHeadroomMib' __exactly__. Reusing the 4 GiB CPU budget here
-- produced @OuterEnvelopeTooLarge 5120 16384@ on every GPU placement, so no
-- engine ever became ready. That defect was invisible to every
-- machine-independent gate because @linux-gpu@ compiled no plan at all before
-- this sprint; it is now pinned by a chart-value assertion in the unit suite.
linuxGpuEngineInferenceRamBudgetMib :: Int
linuxGpuEngineInferenceRamBudgetMib =
  linuxGpuEnginePodMemoryLimitMib - linuxOuterEnvelopeHeadroomMib

-- | The @linux-gpu@ engine pod memory limit (MiB) the cluster lifecycle emits
-- into its generated Helm values. The budget above is derived from it rather
-- than written down twice, so the two cannot drift apart silently.
linuxGpuEnginePodMemoryLimitMib :: Int
linuxGpuEnginePodMemoryLimitMib = 16384

-- | Phase 6 Sprint 6.44 — the @linux-gpu@ per-execution device-memory budget
-- (MiB). Unlike the resident-set half this is a device quantity, and the
-- supported single-GPU lane holds the whole device; the value is a conservative
-- admission ceiling, not a measurement, and the cohort is what calibrates it.
linuxEngineInferenceVramBudgetMib :: Int
linuxEngineInferenceVramBudgetMib = 4096

-- | Phase 4 Sprint 4.26 — the assumed @apple-silicon@ inference-RAM
-- budget (MiB) used only when the host-native resolver cannot read host
-- physical RAM (host physical RAM − colima pledge − reserve is the normal
-- path). Set to the supported-Apple-dev-host floor (16 GiB), which is at
-- or above every catalog model's conservative footprint so a discovery
-- failure still yields a validatable config rather than blocking bring-up;
-- the real host budget from @sysctl@ replaces it whenever discovery works.
appleFallbackInferenceRamBudgetMib :: Int
appleFallbackInferenceRamBudgetMib = 16384

-- | Phase 4 Sprint 4.26 — the pure per-substrate inference-RAM budget
-- default. The Apple value is the conservative fallback that the IO
-- resolver ('Infernix.DemoConfig.resolveInferenceMemoryBudget') replaces
-- with the host-computed budget at materialization time.
defaultInferenceRamBudgetMib :: RuntimeMode -> Int
defaultInferenceRamBudgetMib runtimeMode = case runtimeMode of
  AppleSilicon -> appleFallbackInferenceRamBudgetMib
  LinuxCpu -> linuxEngineInferenceRamBudgetMib
  LinuxGpu -> linuxEngineInferenceRamBudgetMib

bindingForMode :: RuntimeMode -> MatrixRow -> Maybe ModeBinding
bindingForMode runtimeMode row = case runtimeMode of
  AppleSilicon -> appleBinding row
  LinuxCpu -> linuxCpuBinding row
  LinuxGpu -> linuxGpuBinding row

matrixRows :: [MatrixRow]
matrixRows =
  [ mkRow
      "llm-general-text-smollm2"
      "llm-smollm2-safetensors"
      "SmolLM2-135M Instruct"
      "llm"
      "General text generation over a compact real safetensors checkpoint."
      "HF safetensors"
      "SmolLM2-135M-Instruct"
      "https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct"
      "Small real safetensors checkpoint for constrained CPU and Apple lanes."
      "Prompt"
      (Just (ModeBinding "Transformers + PyTorch MPS" False))
      (Just (ModeBinding "Transformers + PyTorch CPU" False))
      (Just (ModeBinding "vLLM" True)),
    mkRow
      "llm-awq-qwen25"
      "llm-qwen25-awq"
      "Qwen2.5-1.5B Instruct AWQ"
      "llm"
      "CUDA-focused quantized LLM checkpoint."
      "AWQ"
      "Qwen2.5-1.5B-Instruct-AWQ"
      "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-AWQ"
      "GPU-oriented quantized checkpoint."
      "Prompt"
      Nothing
      Nothing
      (Just (ModeBinding "vLLM" True)),
    mkRow
      "llm-gptq-tinyllama"
      "llm-tinyllama-gptq"
      "TinyLlama GPTQ"
      "llm"
      "Legacy GPTQ quantized checkpoint for CUDA-bound LLM flows."
      "GPTQ"
      "TinyLlama-1.1B-Chat-v1.0-GPTQ"
      "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GPTQ"
      "Older but useful quantized checkpoint family."
      "Prompt"
      Nothing
      Nothing
      (Just (ModeBinding "vLLM" True)),
    mkRow
      "llm-gguf-tinyllama"
      "llm-tinyllama-gguf"
      "TinyLlama GGUF"
      "llm"
      "Portable GGUF-based local inference path."
      "GGUF"
      "TinyLlama-1.1B-Chat-v1.0-GGUF"
      "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q2_K.gguf"
      "Best cross-platform local runtime path."
      "Prompt"
      (Just (ModeBinding "llama.cpp (Metal)" False))
      (Just (ModeBinding "llama.cpp" False))
      (Just (ModeBinding "llama.cpp" True)),
    mkRow
      "llm-mlx-qwen15"
      "llm-qwen15-mlx"
      "Qwen1.5 MLX"
      "llm"
      "Apple-native converted artifact family for local LLM execution."
      "MLX"
      "Qwen1.5-1.8B-Chat-4bit (MLX)"
      "https://huggingface.co/mlx-community/Qwen1.5-1.8B-Chat-4bit"
      "Apple-native converted artifact family."
      "Prompt"
      (Just (ModeBinding "MLX / MLX-LM" False))
      Nothing
      Nothing,
    mkRow
      "speech-whisper-cpp"
      "speech-whisper-small"
      "Whisper Small"
      "speech"
      "Compact speech transcription through whisper.cpp."
      "whisper.cpp model set / GGML-style"
      "whisper-small"
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
      "Best compact or native path."
      "Audio Input"
      (Just (ModeBinding "whisper.cpp (Metal)" False))
      (Just (ModeBinding "whisper.cpp" False))
      (Just (ModeBinding "whisper.cpp" False)),
    mkRow
      "speech-ctranslate2-faster-whisper"
      "speech-faster-whisper-ct2"
      "Faster Whisper Small"
      "speech"
      "Throughput-oriented Whisper path using CTranslate2."
      "CTranslate2"
      "faster-whisper-small"
      "https://huggingface.co/Systran/faster-whisper-small"
      "Best throughput-oriented Whisper path on CUDA."
      "Audio Input"
      (Just (ModeBinding "CTranslate2 (CPU)" False))
      (Just (ModeBinding "CTranslate2" False))
      (Just (ModeBinding "CTranslate2" True)),
    mkRow
      "audio-demucs"
      "audio-demucs-htdemucs"
      "Demucs HTDemucs"
      "audio"
      "Source separation using the canonical Demucs path."
      "PyTorch checkpoint"
      "htdemucs"
      "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/955717e8-8726e21a.th"
      "Canonical Demucs execution path."
      "Audio Input"
      (Just (ModeBinding "PyTorch MPS" False))
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CUDA" True)),
    mkRow
      "audio-open-unmix"
      "audio-open-unmix"
      "Open-Unmix"
      "audio"
      "Alternative source separation path."
      "PyTorch checkpoint"
      "Open-Unmix"
      "https://zenodo.org/records/3370489"
      "Alternate separation path."
      "Audio Input"
      (Just (ModeBinding "PyTorch MPS" False))
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CUDA" True)),
    mkRow
      "audio-basic-pitch-coreml"
      "audio-basic-pitch-coreml"
      "Basic Pitch Core ML"
      "audio"
      "Apple-native Basic Pitch execution path."
      "Core ML"
      "basic-pitch"
      "https://github.com/spotify/basic-pitch"
      "Preferred Apple production lane for Basic Pitch."
      "Audio Input"
      (Just (ModeBinding "Core ML" False))
      Nothing
      Nothing,
    mkRow
      "audio-basic-pitch-onnx"
      "audio-basic-pitch-onnx"
      "Basic Pitch ONNX"
      "audio"
      "Portable ONNX-based Basic Pitch fallback."
      "ONNX"
      "basic-pitch release artifacts"
      "https://raw.githubusercontent.com/spotify/basic-pitch/main/basic_pitch/saved_models/icassp_2022/nmp.onnx"
      "Useful portable fallback artifact."
      "Audio Input"
      (Just (ModeBinding "ONNX Runtime" False))
      (Just (ModeBinding "ONNX Runtime CPU" False))
      (Just (ModeBinding "ONNX Runtime (CPU)" False)),
    mkRow
      "music-mt3-infer"
      "music-mt3-infer"
      "MT3-PyTorch"
      "music"
      "Multi-instrument music transcription via the mt3-infer PyTorch MT3 port."
      "PyTorch checkpoint"
      "MT3-PyTorch"
      "https://github.com/kunato/mt3-pytorch/tree/master/pretrained"
      "mt3-infer-backed MT3-PyTorch row. Apple uses the PyTorch CPU path until upstream MPS support is validated."
      "Audio Input"
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CUDA" True)),
    mkRow
      "music-mr-mt3"
      "music-mr-mt3"
      "MR-MT3"
      "music"
      "Fast multi-instrument music transcription via MR-MT3 through mt3-infer."
      "PyTorch checkpoint"
      "MR-MT3"
      "https://huggingface.co/gudgud1014/MR-MT3/resolve/main/mt3.pth"
      "mt3-infer-backed MR-MT3 row. Apple uses the PyTorch CPU path until upstream MPS support is validated."
      "Audio Input"
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CUDA" True)),
    mkRow
      "music-omnizart-tensorflow"
      "music-omnizart"
      "ByteDance Piano Transcription"
      "music"
      "Music transcription via a modern maintained PyTorch model."
      "PyTorch"
      "piano_transcription_inference"
      "https://zenodo.org/record/4034264/files/CRNN_note_F1%3D0.9677_pedal_F1%3D0.9186.pth?download=1"
      "Modern PyTorch transcription model replacing the ancient-TensorFlow Omnizart stack; runs on the shared pytorch adapter. The engine binding is landed and wired (pytorch_python.py); real-output cohort evidence closed under Wave R (Apple, 2026-07-08) and Wave S (Linux, 2026-07-09)."
      "Audio Input"
      (Just (ModeBinding "PyTorch MPS" False))
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CUDA" True)),
    mkRow
      "image-sdxl-turbo"
      "image-sdxl-turbo"
      "SDXL Turbo"
      "image"
      "Image generation over the standard diffusers stack."
      "Diffusers / safetensors pipeline"
      "SDXL Turbo"
      "https://huggingface.co/stabilityai/sdxl-turbo"
      "Standard open image-generation stack."
      "Prompt"
      (Just (ModeBinding "Diffusers on MPS" False))
      Nothing
      (Just (ModeBinding "Diffusers or ComfyUI" True)),
    mkRow
      "image-apple-stable-diffusion-coreml"
      "image-apple-stable-diffusion-coreml"
      "Apple Stable Diffusion Core ML"
      "image"
      "Core ML image generation path produced by Apple conversion tooling."
      "Core ML"
      "Apple Stable Diffusion Core ML v1.5 palettized"
      "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized"
      "Apple-native exported Core ML path using preconverted Hugging Face packages."
      "Prompt"
      (Just (ModeBinding "Core ML" False))
      Nothing
      Nothing,
    mkRow
      "video-wan21-diffusers"
      "video-wan21-t2v"
      "Wan2.1 T2V"
      "video"
      "Small reference text-to-video model."
      "Diffusers / safetensors pipeline"
      "Wan2.1-T2V-1.3B"
      "https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B-Diffusers"
      "Small reference text-to-video model; Apple MPS remains residual until validated."
      "Prompt"
      Nothing
      Nothing
      (Just (ModeBinding "Diffusers or ComfyUI" True)),
    mkRow
      "audio-bark-pytorch"
      "audio-bark-small"
      "Bark Small"
      "audio"
      "Representative audio-generation family."
      "PyTorch / HF"
      "bark-small"
      "https://huggingface.co/suno/bark-small"
      "Representative audio-generation family."
      "Prompt"
      (Just (ModeBinding "PyTorch MPS" False))
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CUDA" True)),
    mkRow
      "tool-audiveris-jvm"
      "tool-audiveris"
      "Audiveris"
      "tool"
      "Optical music recognition and notation extraction tool."
      "JVM application"
      "Audiveris"
      "https://github.com/Audiveris/audiveris/releases/tag/5.10.2"
      "Treat as tool runtime, not a separately managed ANN kernel family."
      "Score Input"
      (Just (ModeBinding "JVM" False))
      (Just (ModeBinding "JVM" False))
      (Just (ModeBinding "JVM" False))
  ]

mkRow ::
  Text ->
  Text ->
  Text ->
  Text ->
  Text ->
  Text ->
  Text ->
  Text ->
  Text ->
  Text ->
  Maybe ModeBinding ->
  Maybe ModeBinding ->
  Maybe ModeBinding ->
  MatrixRow
mkRow rowIdValue modelIdValue displayNameValue familyValue descriptionValue artifactTypeValue referenceModelValue downloadUrlValue notesValue requestLabelValue appleValue linuxCpuValue linuxGpuValue =
  MatrixRow
    { rowId = rowIdValue,
      rowModelId = modelIdValue,
      rowDisplayName = displayNameValue,
      rowFamily = familyValue,
      rowDescription = descriptionValue,
      rowArtifactType = artifactTypeValue,
      rowReferenceModel = referenceModelValue,
      rowDownloadUrl = downloadUrlValue,
      rowNotes = notesValue,
      rowRequestLabel = requestLabelValue,
      appleBinding = appleValue,
      linuxCpuBinding = linuxCpuValue,
      linuxGpuBinding = linuxGpuValue
    }

jsonBool :: Bool -> String
jsonBool value
  | value = "true"
  | otherwise = "false"

jsonFilePath :: FilePath -> String
jsonFilePath = show

jsonString :: Text -> String
jsonString = show . Text.unpack
