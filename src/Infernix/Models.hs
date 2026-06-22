{-# LANGUAGE OverloadedStrings #-}

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
    engineMemberPinnedTopicForMode,
    engineMemberRequestTopics,
    engineMembersForMode,
    enginePoolForModel,
    enginePoolTopicForMode,
    enginePoolsForMode,
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
import Data.Char (isAlphaNum)
import Data.List (find, intercalate, nub)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (ControlPlaneContext, controlPlaneContextId)
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
      [ "music-mt3-jax",
        "music-omnizart-tensorflow",
        "video-wan21-diffusers"
      ]
    LinuxCpu ->
      [ "audio-basic-pitch-tensorflow",
        "music-mt3-jax",
        "music-omnizart-tensorflow"
      ]
    LinuxGpu ->
      [ "audio-basic-pitch-tensorflow",
        "music-mt3-jax",
        "music-omnizart-tensorflow"
      ]

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
  uniqueEngineBindings (map (engineBindingForSelectedEngine runtimeMode . selectedEngine) (catalogForMode runtimeMode))

-- | Phase 7 Sprint 7.7 (legacy row 21): the supported default Pulsar
-- tenant + namespace for inference topics is @infernix/demo@. The
-- @infernix@ tenant and @infernix/demo@ namespace are reconciled by
-- 'Infernix.Runtime.Pulsar.reconcileSupportedNamespaces' at daemon
-- startup. The previous @persistent://public/default/@ prefix is
-- retired.
defaultPulsarTopicPrefix :: Text
defaultPulsarTopicPrefix = "persistent://infernix/demo/"

requestTopicsForMode :: RuntimeMode -> [Text]
requestTopicsForMode runtimeMode =
  [defaultPulsarTopicPrefix <> "inference.request." <> runtimeModeId runtimeMode]

resultTopicForMode :: RuntimeMode -> Text
resultTopicForMode runtimeMode =
  defaultPulsarTopicPrefix <> "inference.result." <> runtimeModeId runtimeMode

-- | Phase 4 Sprint 4.17 — the per-engine engine name derived from an adapter
-- id. The python-stdio framework adapters carry a @-python@ suffix
-- (@transformers-python@ -> @transformers@); native-process-runner adapter ids
-- have no suffix and map to themselves.
engineNameForAdapterId :: Text -> Text
engineNameForAdapterId adapterId =
  fromMaybe adapterId (Text.stripSuffix "-python" adapterId)

-- | The per-engine image name a selected engine resolves to, via its adapter
-- binding.
engineNameForSelectedEngine :: RuntimeMode -> Text -> Text
engineNameForSelectedEngine runtimeMode selectedEngineValue =
  engineNameForAdapterId
    (engineBindingAdapterId (engineBindingForSelectedEngine runtimeMode selectedEngineValue))

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

-- | Derived normal-pool topic. Operators declare pools and members, never
-- raw topic strings; every legal batch topic is rendered from this helper.
enginePoolTopicForMode :: RuntimeMode -> Text -> Text -> Text
enginePoolTopicForMode runtimeMode poolId modelIdValue =
  defaultPulsarTopicPrefix
    <> "inference.batch."
    <> runtimeModeId runtimeMode
    <> ".pool."
    <> topicSegment poolId
    <> ".model."
    <> topicSegment modelIdValue

-- | Derived pinned-member topic for exact-member routes. The first pool
-- implementation does not route normal traffic here, but the helper fixes the
-- only supported topic shape for pinned routes.
engineMemberPinnedTopicForMode :: RuntimeMode -> Text -> Text -> Text
engineMemberPinnedTopicForMode runtimeMode memberId modelIdValue =
  defaultPulsarTopicPrefix
    <> "inference.batch."
    <> runtimeModeId runtimeMode
    <> ".member."
    <> topicSegment memberId
    <> ".model."
    <> topicSegment modelIdValue

enginePoolForModel :: DemoConfig -> Text -> Maybe EnginePool
enginePoolForModel demoConfig modelIdValue =
  find ((modelIdValue `elem`) . enginePoolModelIds) (enginePools demoConfig)

engineMemberRequestTopics :: RuntimeMode -> [EnginePool] -> EngineMember -> [Text]
engineMemberRequestTopics runtimeMode pools member =
  [ enginePoolTopicForMode runtimeMode (enginePoolId pool) modelIdValue
  | pool <- pools,
    enginePoolId pool `elem` engineMemberPoolIds member,
    modelIdValue <- enginePoolModelIds pool
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
  | engineName <- nub (map modelEngineName activeCatalog),
    let binding = bindingForEngineName engineName,
    let pythonNative = engineBindingPythonNative binding
  ]
  where
    activeCatalog = catalogForMode runtimeMode
    modelEngineName model = engineNameForSelectedEngine runtimeMode (selectedEngine model)
    modelsForEngine engineName = filter ((== engineName) . modelEngineName) activeCatalog
    bindingForEngineName engineName =
      case find ((== engineName) . modelEngineName) activeCatalog of
        Just model ->
          engineBindingForSelectedEngine runtimeMode (selectedEngine model)
        Nothing ->
          engineBindingForSelectedEngine runtimeMode engineName

topicSegment :: Text -> Text
topicSegment =
  Text.map
    ( \character ->
        if isAlphaNum character || character `elem` ("._-" :: String)
          then character
          else '-'
    )

-- | Per-engine image name: @infernix-engine-<engine>-<mode>:local@, built from
-- @docker/engine.Dockerfile@.
perEngineImageName :: RuntimeMode -> Text -> Text
perEngineImageName runtimeMode engineName =
  perEngineImageRepository runtimeMode engineName <> ":local"

perEngineImageRepository :: RuntimeMode -> Text -> Text
perEngineImageRepository runtimeMode engineName =
  "infernix-engine-" <> engineName <> "-" <> runtimeModeId runtimeMode

engineBindingForSelectedEngine :: RuntimeMode -> Text -> EngineBinding
engineBindingForSelectedEngine _runtimeMode selectedEngineValue =
  let normalizedEngine = Text.toLower selectedEngineValue
      adapterId
        | "vllm" `Text.isInfixOf` normalizedEngine = "vllm-python"
        | "transformers" `Text.isInfixOf` normalizedEngine = "transformers-python"
        | "diffusers" `Text.isInfixOf` normalizedEngine = "diffusers-python"
        | "torch" `Text.isInfixOf` normalizedEngine = "pytorch-python"
        | "tensorflow" `Text.isInfixOf` normalizedEngine = "tensorflow-python"
        | "jax" `Text.isInfixOf` normalizedEngine = "jax-python"
        | "whisper.cpp" `Text.isInfixOf` normalizedEngine = "whisper-cpp-cli"
        | "llama.cpp" `Text.isInfixOf` normalizedEngine = "llama-cpp-cli"
        | "onnx runtime" `Text.isInfixOf` normalizedEngine = "onnx-runtime-native"
        | "core ml" `Text.isInfixOf` normalizedEngine = "coreml-native"
        | "ctranslate2" `Text.isInfixOf` normalizedEngine = "ctranslate2-native"
        | "mlx" `Text.isInfixOf` normalizedEngine = "mlx-native"
        | "jvm" `Text.isInfixOf` normalizedEngine = "jvm-native"
        | otherwise = "engine-native"
      pythonNative =
        any
          (`Text.isInfixOf` normalizedEngine)
          ["vllm", "transformers", "diffusers", "torch", "tensorflow", "jax"]
      adapterType
        | pythonNative = "python-stdio"
        | otherwise = "native-process-runner"
      adapterLocator
        | pythonNative = "adapters/" <> adapterModuleName adapterId <> ".py"
        | otherwise = adapterId
      adapterEntrypoint
        | pythonNative = "adapter-" <> adapterId
        | otherwise = "runner-" <> adapterId
      setupEntrypoint
        | pythonNative = "setup-" <> adapterId
        | otherwise = "setup-" <> adapterId
   in EngineBinding
        { engineBindingName = selectedEngineValue,
          engineBindingAdapterId = adapterId,
          engineBindingAdapterType = adapterType,
          engineBindingAdapterLocator = adapterLocator,
          engineBindingAdapterEntrypoint = adapterEntrypoint,
          engineBindingSetupEntrypoint = setupEntrypoint,
          engineBindingProjectDirectory = "python",
          engineBindingPythonNative = pythonNative
        }
  where
    adapterModuleName = Text.replace "-" "_"

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
      "  infernix-substrate.dhall: |"
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
  case lifecycleProgress state of
    Just _ -> "in-progress"
    Nothing -> "idle"

lifecycleProgressJsonFields :: ClusterState -> String
lifecycleProgressJsonFields state =
  case lifecycleProgress state of
    Nothing -> ""
    Just progress ->
      ",\n"
        <> "  \"lifecycleAction\": "
        <> show (lifecycleAction progress)
        <> ",\n"
        <> "  \"lifecyclePhase\": "
        <> show (lifecyclePhase progress)
        <> ",\n"
        <> "  \"lifecycleDetail\": "
        <> show (lifecycleDetail progress)
        <> ",\n"
        <> "  \"lifecycleHeartbeatAt\": "
        <> show (show (lifecycleHeartbeatAt progress))

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
        runtimeLane = laneFor runtimeMode (bindingRequiresGpu binding),
        requiresGpu = bindingRequiresGpu binding,
        notes = rowNotes row
      }

bindingForMode :: RuntimeMode -> MatrixRow -> Maybe ModeBinding
bindingForMode runtimeMode row = case runtimeMode of
  AppleSilicon -> appleBinding row
  LinuxCpu -> linuxCpuBinding row
  LinuxGpu -> linuxGpuBinding row

laneFor :: RuntimeMode -> Bool -> RuntimeLane
laneFor runtimeMode requiresGpu = case runtimeMode of
  AppleSilicon -> AppleSiliconHost
  LinuxCpu -> KindLinuxCpu
  LinuxGpu
    | requiresGpu -> KindLinuxGpuGpu
    | otherwise -> KindLinuxGpuShared

matrixRows :: [MatrixRow]
matrixRows =
  [ mkRow
      "llm-general-text-qwen25"
      "llm-qwen25-safetensors"
      "Qwen2.5-1.5B Instruct"
      "llm"
      "General text generation over the canonical safetensors checkpoint family."
      "HF safetensors"
      "Qwen2.5-1.5B-Instruct"
      "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct"
      "Canonical source format for many open-weight LLMs."
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
      "https://github.com/facebookresearch/demucs"
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
      "https://github.com/sigsep/open-unmix-pytorch"
      "Alternate separation path."
      "Audio Input"
      (Just (ModeBinding "PyTorch MPS" False))
      (Just (ModeBinding "PyTorch CPU" False))
      (Just (ModeBinding "PyTorch CUDA" True)),
    mkRow
      "audio-basic-pitch-tensorflow"
      "audio-basic-pitch-tensorflow"
      "Basic Pitch TensorFlow"
      "audio"
      "Audio-to-MIDI or pitch transcription via TensorFlow."
      "TensorFlow model family"
      "basic-pitch"
      "https://github.com/spotify/basic-pitch"
      "Published package pins TensorFlow <2.15.1; use the ONNX or Core ML lane until a maintained TensorFlow package is adopted."
      "Audio Input"
      Nothing
      Nothing
      Nothing,
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
      (Just (ModeBinding "ONNX Runtime CUDA" True)),
    mkRow
      "music-mt3-jax"
      "music-mt3-jax"
      "MT3"
      "music"
      "Multi-instrument music transcription on the canonical JAX stack."
      "JAX checkpoint / codebase"
      "MT3"
      "https://github.com/magenta/mt3"
      "JAX is canonical upstream, but this stack remains a compatibility residual until reproven."
      "Audio Input"
      Nothing
      Nothing
      Nothing,
    mkRow
      "music-omnizart-tensorflow"
      "music-omnizart"
      "Omnizart"
      "music"
      "Music transcription and MIR family workload."
      "TensorFlow model family"
      "Omnizart"
      "https://github.com/Music-and-Culture-Technology-Lab/omnizart"
      "Compatibility is unproven on the supported Python and Apple lanes."
      "Audio Input"
      Nothing
      Nothing
      Nothing,
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
      "Apple Stable Diffusion conversion toolchain"
      "https://github.com/apple/ml-stable-diffusion"
      "Best Apple-native exported path when available."
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
      "https://github.com/Audiveris/audiveris/releases/download/5.10.2/Audiveris-5.10.2-ubuntu24.04-x86_64.deb"
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

uniqueEngineBindings :: [EngineBinding] -> [EngineBinding]
uniqueEngineBindings = go []
  where
    go seen [] = reverse seen
    go seen (engineBinding : rest)
      | any ((== engineBindingName engineBinding) . engineBindingName) seen = go seen rest
      | otherwise = go (engineBinding : seen) rest
