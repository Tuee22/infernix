{-# LANGUAGE OverloadedStrings #-}

module Infernix.Models
  ( catalogForMode,
    clusterDemoApiUpstream,
    engineBindingForSelectedEngine,
    engineBindingsForMode,
    encodeDemoConfig,
    expectedDaemonLocationForRuntime,
    findModel,
    platformClaims,
    requestTopicsForMode,
    renderPublicationState,
    renderPublicationStateWithApiUpstream,
    renderConfigMapManifest,
    resultTopicForMode,
    routeInventory,
  )
where

import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (find, intercalate)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Routes qualified as Routes
import Infernix.Types
import Infernix.Workflow (demoConfigGeneratedBanner)

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

engineBindingsForMode :: RuntimeMode -> [EngineBinding]
engineBindingsForMode runtimeMode =
  uniqueEngineBindings (map (engineBindingForSelectedEngine runtimeMode . selectedEngine) (catalogForMode runtimeMode))

requestTopicsForMode :: RuntimeMode -> [Text]
requestTopicsForMode runtimeMode =
  ["persistent://public/default/inference.request." <> runtimeModeId runtimeMode]

resultTopicForMode :: RuntimeMode -> Text
resultTopicForMode runtimeMode =
  "persistent://public/default/inference.result." <> runtimeModeId runtimeMode

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
encodeDemoConfig demoConfig =
  LazyChar8.pack (demoConfigGeneratedBanner <> renderDemoConfig demoConfig)

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

platformClaims :: [PersistentClaim]
platformClaims =
  [ PersistentClaim "platform" "infernix" "service" 0 "data" "infernix-service-0-data" "5Gi"
  ]

routeInventory :: Bool -> [RouteInfo]
routeInventory = Routes.routeInventory

clusterDemoApiUpstream :: ApiUpstream
clusterDemoApiUpstream =
  ApiUpstream
    { apiUpstreamMode = "cluster-demo",
      apiUpstreamHost = "infernix-demo.platform.svc.cluster.local",
      apiUpstreamPort = 80
    }

renderPublicationState :: String -> ClusterState -> String
renderPublicationState controlPlane state =
  renderPublicationStateWithApiUpstream controlPlane state selectedApiUpstream
  where
    selectedApiUpstream
      | stateHasDemoUi state = clusterDemoApiUpstream
      | otherwise = disabledApiUpstream

renderPublicationStateWithApiUpstream :: String -> ClusterState -> ApiUpstream -> String
renderPublicationStateWithApiUpstream controlPlane state apiUpstream =
  "{\n"
    <> "  \"clusterPresent\": "
    <> jsonBool (clusterPresent state)
    <> ",\n"
    <> "  \"controlPlaneContext\": "
    <> show controlPlane
    <> ",\n"
    <> "  \"daemonLocation\": "
    <> jsonString (daemonLocationFor state)
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
    <> "  \"apiUpstream\": "
    <> renderApiUpstream apiUpstream
    <> ",\n"
    <> "  \"updatedAt\": "
    <> show (show (updatedAt state))
    <> ",\n"
    <> "  \"upstreams\": [\n"
    <> intercalate ",\n" (map renderPublicationUpstream (publicationUpstreams (stateHasDemoUi state) apiUpstream))
    <> "\n  ],\n"
    <> "  \"routes\": [\n"
    <> intercalate ",\n" (map renderRouteInfo (routes state))
    <> "\n  ]\n"
    <> "}\n"

publicationUpstreams :: Bool -> ApiUpstream -> [PublicationUpstream]
publicationUpstreams = Routes.routePublicationUpstreams

renderApiUpstream :: ApiUpstream -> String
renderApiUpstream apiUpstream =
  "{"
    <> "\"mode\": "
    <> jsonString (apiUpstreamMode apiUpstream)
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
expectedDaemonLocationForRuntime runtimeMode =
  case runtimeMode of
    AppleSilicon -> "control-plane-host"
    _ -> "cluster-pod"

stateHasDemoUi :: ClusterState -> Bool
stateHasDemoUi state =
  any ((`elem` ["/", "/api", "/objects"]) . path) (routes state)

disabledApiUpstream :: ApiUpstream
disabledApiUpstream =
  ApiUpstream
    { apiUpstreamMode = "disabled",
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
                fieldType = "text"
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

laneFor :: RuntimeMode -> Bool -> Text
laneFor runtimeMode requiresGpu = case runtimeMode of
  AppleSilicon -> "apple-silicon-host"
  LinuxCpu -> "kind-linux-cpu"
  LinuxGpu
    | requiresGpu -> "kind-linux-gpu-gpu"
    | otherwise -> "kind-linux-gpu-shared"

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
      "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF"
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
      "https://github.com/ggml-org/whisper.cpp/tree/master/models"
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
      Nothing
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
      "TensorFlow is the preferred production lane when used on CUDA."
      "Audio Input"
      Nothing
      (Just (ModeBinding "TensorFlow CPU or default package runtime" False))
      (Just (ModeBinding "TensorFlow CUDA" True)),
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
      "https://github.com/spotify/basic-pitch/releases"
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
      "JAX is the canonical execution model."
      "Audio Input"
      (Just (ModeBinding "jax-metal" False))
      (Just (ModeBinding "JAX CPU" False))
      (Just (ModeBinding "JAX/XLA on NVIDIA" True)),
    mkRow
      "music-omnizart-tensorflow"
      "music-omnizart"
      "Omnizart"
      "music"
      "Music transcription and MIR family workload."
      "TensorFlow model family"
      "Omnizart"
      "https://github.com/Music-and-Culture-Technology-Lab/omnizart"
      "Apple support likely requires an owned export path."
      "Audio Input"
      (Just (ModeBinding "Core ML (exported path owned by deployment)" False))
      (Just (ModeBinding "TensorFlow CPU" False))
      (Just (ModeBinding "TensorFlow CUDA" True)),
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
      "https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B"
      "Small reference text-to-video model."
      "Prompt"
      (Just (ModeBinding "Diffusers on MPS (if viable)" False))
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
      "https://github.com/Audiveris/audiveris"
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

renderDemoConfig :: DemoConfig -> String
renderDemoConfig demoConfig =
  "{\n"
    <> "  \"runtimeMode\": "
    <> jsonString (runtimeModeId (configRuntimeMode demoConfig))
    <> ",\n"
    <> "  \"edgePort\": "
    <> show (configEdgePort demoConfig)
    <> ",\n"
    <> "  \"configMapName\": "
    <> jsonString (configMapName demoConfig)
    <> ",\n"
    <> "  \"generatedPath\": "
    <> jsonFilePath (generatedPath demoConfig)
    <> ",\n"
    <> "  \"mountedPath\": "
    <> jsonFilePath (mountedPath demoConfig)
    <> ",\n"
    <> "  \"demo_ui\": "
    <> jsonBool (demoUiEnabled demoConfig)
    <> ",\n"
    <> "  \"request_topics\": ["
    <> intercalate ", " (map jsonString (requestTopics demoConfig))
    <> "],\n"
    <> "  \"result_topic\": "
    <> jsonString (resultTopic demoConfig)
    <> ",\n"
    <> "  \"engines\": [\n"
    <> intercalate ",\n" (map renderEngineBinding (engines demoConfig))
    <> "\n  ],\n"
    <> "  \"models\": [\n"
    <> intercalate ",\n" (map renderModelDescriptor (models demoConfig))
    <> "\n  ]\n"
    <> "}\n"

renderEngineBinding :: EngineBinding -> String
renderEngineBinding engineBinding =
  unlines
    [ "    {",
      "      \"engine\": " <> jsonString (engineBindingName engineBinding) <> ",",
      "      \"adapterId\": " <> jsonString (engineBindingAdapterId engineBinding) <> ",",
      "      \"adapterType\": " <> jsonString (engineBindingAdapterType engineBinding) <> ",",
      "      \"adapterLocator\": " <> jsonString (engineBindingAdapterLocator engineBinding) <> ",",
      "      \"adapterEntrypoint\": " <> jsonString (engineBindingAdapterEntrypoint engineBinding) <> ",",
      "      \"setupEntrypoint\": " <> jsonString (engineBindingSetupEntrypoint engineBinding) <> ",",
      "      \"projectDirectory\": " <> jsonFilePath (engineBindingProjectDirectory engineBinding) <> ",",
      "      \"pythonNative\": " <> jsonBool (engineBindingPythonNative engineBinding),
      "    }"
    ]

renderModelDescriptor :: ModelDescriptor -> String
renderModelDescriptor model =
  unlines
    [ "    {",
      "      \"matrixRowId\": " <> jsonString (matrixRowId model) <> ",",
      "      \"modelId\": " <> jsonString (modelId model) <> ",",
      "      \"displayName\": " <> jsonString (displayName model) <> ",",
      "      \"family\": " <> jsonString (family model) <> ",",
      "      \"description\": " <> jsonString (description model) <> ",",
      "      \"artifactType\": " <> jsonString (artifactType model) <> ",",
      "      \"referenceModel\": " <> jsonString (referenceModel model) <> ",",
      "      \"downloadUrl\": " <> jsonString (downloadUrl model) <> ",",
      "      \"selectedEngine\": " <> jsonString (selectedEngine model) <> ",",
      "      \"requestShape\": [" <> intercalate ", " (map renderRequestField (requestShape model)) <> "],",
      "      \"runtimeMode\": " <> jsonString (runtimeModeId (runtimeMode model)) <> ",",
      "      \"runtimeLane\": " <> jsonString (runtimeLane model) <> ",",
      "      \"requiresGpu\": " <> jsonBool (requiresGpu model) <> ",",
      "      \"notes\": " <> jsonString (notes model),
      "    }"
    ]

renderRequestField :: RequestField -> String
renderRequestField requestField =
  "{"
    <> "\"name\": "
    <> jsonString (name requestField)
    <> ", \"label\": "
    <> jsonString (label requestField)
    <> ", \"fieldType\": "
    <> jsonString (fieldType requestField)
    <> "}"

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
